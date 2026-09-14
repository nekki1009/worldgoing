extends RefCounted
## Shared presentation data only. No soldier, item, health or animation clock owner.
const Plan = preload("res://scripts/tools/terrain_army_recipe_bake_plan.gd")
const RangedAtlas = preload("res://scripts/terrain_lab/terrain_army_ranged_atlas.gd")
const DyeAtlas = preload("res://scripts/terrain_lab/terrain_army_dye_atlas.gd")
const BASE_MANIFEST := "res://assets/characters/terrain_lab_army/standard_soldier/standard_soldier_atlas.json"
const CATALOG := "res://assets/characters/terrain_lab_army/standard_soldier/recipes/v1/catalog.json"
const PAGE_CACHE_BYTES := 64 * 1024 * 1024
static var _catalog_path := CATALOG
static var _catalog_checked := false
static var _catalog := {}
static var _base := {}
static var _sources := {}
static var _recipes := {}
static var _rejected := {}
static var _pages := {}
static var _page_refs := {}
static var _page_bytes := 0
static var _use_serial := 0
static var page_load_count := 0 # Diagnostics only; no texture lifetime changes.
static var page_load_usec := 0
static var page_evictions := 0

static func set_catalog_path(path: String) -> bool:
	var clean := path.simplify_path()
	if clean != CATALOG and not clean.begins_with("res://output/"):
		return false
	_catalog_path = clean
	_catalog_checked = false
	_catalog.clear()
	_sources.clear()
	_recipes.clear()
	_rejected.clear()
	_pages.clear()
	_page_refs.clear()
	_page_bytes = 0
	return true

static func supports(appearance: Dictionary) -> bool:
	if not HumanCharacter3DEditor.valid_appearance(appearance) or not DyeAtlas.supports(appearance): return false
	appearance = DyeAtlas.Dye.geometry_appearance(appearance)
	if str(appearance.get("parts", {}).get("weapon", "")) in RangedAtlas.WEAPONS:
		return not RangedAtlas.recipe(appearance).is_empty()
	var mask := _appearance_mask(appearance)
	return mask >= 0 and not _recipe(mask, _appearance_iron(appearance)).is_empty()

static func frame(appearance: Dictionary, clip: String, direction: String, sample_time: float) -> Dictionary:
	if not HumanCharacter3DEditor.valid_appearance(appearance) or not DyeAtlas.supports(appearance): return {}
	appearance = DyeAtlas.Dye.geometry_appearance(appearance)
	if not is_finite(sample_time) or sample_time < 0.0:
		return {}
	var recipe := {}
	if str(appearance.get("parts", {}).get("weapon", "")) in RangedAtlas.WEAPONS:
		recipe = RangedAtlas.recipe(appearance)
	else:
		var mask := _appearance_mask(appearance)
		if mask >= 0:
			recipe = _recipe(mask, _appearance_iron(appearance))
	if recipe.is_empty():
		return {}
	# Existing Army may already have resolved a no-shield guard's logical alias.
	clip = "guard" if clip in ["guard_unshielded", "guard_weapon"] else clip.replace("guard_weapon_", "guard_")
	var key := clip + "|" + direction
	if not recipe.sequences.has(key):
		return {}
	var sequence: Array = recipe.sequences[key]
	var first: Dictionary = sequence[0]
	var last: Dictionary = sequence.back()
	var elapsed := fposmod(sample_time, float(first.duration)) if float(last.sample_time) < float(first.duration) - 0.000001 else minf(sample_time, float(first.duration))
	var low := 0
	var high := sequence.size()
	while low + 1 < high:
		var middle := low + ((high - low) >> 1)
		if float(sequence[middle].sample_time) <= elapsed + 0.000000001:
			low = middle
		else:
			high = middle
	var selected: Dictionary = sequence[low]
	var texture: AtlasTexture
	if selected.has("_texture"):
		texture = selected._texture.get_ref() as AtlasTexture
	if texture == null:
		var page := _page(selected._page)
		if page == null:
			return {}
		texture = AtlasTexture.new()
		texture.atlas = page
		texture.region = Rect2(float(selected.rect.x), float(selected.rect.y), float(selected.rect.w), float(selected.rect.h))
		selected._texture = weakref(texture)
	var result := selected.duplicate(false)
	result.erase("_texture")
	result.erase("_page")
	result.texture = texture
	result.map_scale = recipe.map_scale
	return result

static func _appearance_iron(appearance: Dictionary) -> int:
	var iron := 0
	var bit := 1
	for slot: String in Plan.IRON_PARTS:
		if appearance.get("parts", {}).get(slot) == Plan.IRON_PARTS[slot]:
			iron |= bit
		bit <<= 1
	return iron

static func _appearance_mask(appearance: Dictionary) -> int:
	if not _load_base() or appearance.size() != _base.appearance.size() or not appearance.get("parts") is Dictionary:
		return -1
	var baseline: Dictionary = _base.appearance
	if appearance.parts.size() != baseline.parts.size():
		return -1
	for key: Variant in baseline:
		if key != "parts" and appearance.get(key) != baseline[key]:
			return -1
	var mask := 0
	for slot: Variant in baseline.parts:
		var actual := str(appearance.parts.get(slot, ""))
		var bit := Plan.SLOTS.find(str(slot))
		if bit >= 0 and actual == "none":
			continue
		if actual != str(baseline.parts[slot]) and (not Plan.IRON_PARTS.has(slot) or actual != Plan.IRON_PARTS[slot]):
			return -1
		if bit >= 0:
			mask |= 1 << bit
	return mask

static func _load_base() -> bool:
	if not _base.is_empty():
		return true
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(BASE_MANIFEST))
	if not parsed is Dictionary or not parsed.get("appearance") is Dictionary or not parsed.get("clips") is Array or not parsed.get("frames") is Array:
		return false
	_base = parsed
	return true

static func _recipe(mask: int, iron: int = 0) -> Dictionary:
	var key := Plan.recipe_key(mask, iron)
	if _recipes.has(key):
		return _recipes[key]
	if _rejected.has(key):
		return {}
	if not _catalog_checked:
		_catalog_checked = true
		if FileAccess.file_exists(_catalog_path):
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(_catalog_path))
			if parsed is Dictionary and parsed.get("schema_version") == 1 and parsed.get("recipes") is Dictionary and str(parsed.get("source_manifest_md5", "")) == FileAccess.get_md5(BASE_MANIFEST) and not _fingerprints().is_empty() and parsed.get("source_fingerprints") == _fingerprints():
				_catalog = parsed
	var paths: Variant = _catalog.get("recipes", {}).get(key)
	if not paths is Array or paths.is_empty():
		_rejected[key] = true
		return {}
	var batches: Array[Dictionary] = []
	var directory := _catalog_path.get_base_dir() + "/"
	for path: Variant in paths:
		if not path is String or not _inside(path, directory) or not FileAccess.file_exists(path):
			_rejected[key] = true
			return {}
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not parsed is Dictionary:
			_rejected[key] = true
			return {}
		batches.append(parsed)
	var validated := validate_batches(mask, batches, directory, iron)
	if validated.is_empty():
		_rejected[key] = true
	else:
		_recipes[key] = validated
	return validated

static func validate_batches(mask: int, batches: Array[Dictionary], directory: String, iron: int = 0) -> Dictionary:
	if mask < 0 or mask > 31 or iron < 0 or iron > 7 or batches.is_empty() or not _load_base():
		return {}
	var original_clips: Array[Dictionary] = []
	original_clips.assign(_base.clips)
	var original_directions: Array[Dictionary] = []
	original_directions.assign(_base.directions)
	var plan := Plan.build(PackedStringArray(["--recipe-mask=%d" % mask, "--recipe-iron=%d" % iron, "--recipe-output=res://output/validation", "--recipe-clips=all", "--recipe-directions=all", "--recipe-first=0", "--recipe-count=128"]), original_clips, original_directions, _base.appearance)
	if not plan.ok:
		return {}
	var expected := {}
	for clip: Dictionary in plan.clips:
		for direction: Dictionary in plan.directions:
			for index: int in int(clip.samples):
				expected["%s|%s|%d" % [clip.id, direction.id, index]] = clip
	var references := {}
	for value: Dictionary in _base.frames:
		references["%s|%s|%d" % [value.clip, value.direction, int(value.frame)]] = value
	var seen := {}
	var sequences := {}
	for batch: Dictionary in batches:
		if batch.get("schema_version") != 1 or batch.get("kind") != "terrain_army_recipe_batch" or batch.get("recipe_key") != Plan.recipe_key(mask, iron) or batch.get("recipe_mask") != mask or batch.get("recipe_iron", 0) != iron or batch.get("appearance") != plan.appearance or batch.get("source_manifest_md5") != FileAccess.get_md5(BASE_MANIFEST) or _fingerprints().is_empty() or batch.get("source_fingerprints") != _fingerprints():
			return {}
		if not batch.get("pages") is Array or not batch.get("frames") is Array or not batch.get("batch") is Dictionary or batch.batch.get("recipe_total") != expected.size() or batch.batch.get("count") != batch.frames.size() or batch.frames.size() > Plan.MAX_BATCH_FRAMES or batch.frames.is_empty():
			return {}
		if not _number(batch.get("map_scale")) or not is_equal_approx(float(batch.map_scale), float(_base.map_scale)):
			return {}
		var pages := {}
		for page: Variant in batch.pages:
			if not page is Dictionary or not _integer(page.get("page"), 0, 1024) or pages.has(int(page.page)) or not _integer(page.get("width"), 1, 16384) or not _integer(page.get("height"), 1, 16384):
				return {}
			if not _inside(str(page.get("path", "")), directory) or not _inside(str(page.get("resource_path", "")), directory) or not FileAccess.file_exists(page.path) or not FileAccess.file_exists(page.resource_path):
				return {}
			pages[int(page.page)] = page
		for value: Variant in batch.frames:
			if not value is Dictionary or not _integer(value.get("frame"), 0, 32) or not _integer(value.get("page"), 0, 1024) or not pages.has(int(value.page)):
				return {}
			var key := "%s|%s|%d" % [str(value.get("clip", "")), str(value.get("direction", "")), int(value.frame)]
			if not expected.has(key) or seen.has(key):
				return {}
			var source_clip := str(value.clip)
			if (mask & 3) == 1 and source_clip.begins_with("guard"):
				source_clip = "guard_unshielded" if source_clip == "guard" else source_clip.replace("guard", "guard_weapon")
			var reference_frame: Dictionary = references.get("%s|%s|%d" % [source_clip, value.direction, int(value.frame)], {})
			var pose := str(expected[key].get("pose", value.clip))
			if (mask & 3) == 1 and pose.begins_with("guard"):
				pose = pose.replace("guard", "guard_weapon")
			if reference_frame.is_empty() or not _number(value.get("sample_time")) or not _number(value.get("duration")) or absf(float(value.sample_time) - float(reference_frame.sample_time)) > 0.000001 or absf(float(value.duration) - float(reference_frame.duration)) > 0.000001 or value.get("resolved_pose") != pose:
				return {}
			var rect: Variant = value.get("rect")
			var anchor: Variant = value.get("anchor_offset")
			var page: Dictionary = pages[int(value.page)]
			if not rect is Dictionary or not anchor is Dictionary or not _integer(rect.get("x"), 0, int(page.width)) or not _integer(rect.get("y"), 0, int(page.height)) or not _integer(rect.get("w"), 1, int(page.width)) or not _integer(rect.get("h"), 1, int(page.height)) or int(rect.x) + int(rect.w) > int(page.width) or int(rect.y) + int(rect.h) > int(page.height) or not _number(anchor.get("x")) or not _number(anchor.get("y")):
				return {}
			var selected: Dictionary = value.duplicate(true)
			selected._page = page
			seen[key] = selected
	if seen.size() != expected.size() or seen.size() != 536:
		return {}
	for clip: Dictionary in plan.clips:
		for direction: Dictionary in plan.directions:
			var sequence: Array[Dictionary] = []
			for index: int in int(clip.samples):
				sequence.append(seen["%s|%s|%d" % [clip.id, direction.id, index]])
			sequences[str(clip.id) + "|" + str(direction.id)] = sequence
	return {"sequences": sequences, "map_scale": float(_base.map_scale)}

static func _page(descriptor: Dictionary) -> Texture2D:
	var path := str(descriptor.resource_path)
	_use_serial += 1
	if _pages.has(path):
		_pages[path].used = _use_serial
		return _pages[path].texture
	var texture: Texture2D = _page_refs[path].get_ref() as Texture2D if _page_refs.has(path) else null
	if texture == null:
		var started := Time.get_ticks_usec()
		texture = ResourceLoader.load(path, "Texture2D", ResourceLoader.CACHE_MODE_IGNORE) as Texture2D
		page_load_count += 1
		page_load_usec += Time.get_ticks_usec() - started
	if texture == null or texture.get_width() != int(descriptor.width) or texture.get_height() != int(descriptor.height):
		return null
	_page_refs[path] = weakref(texture)
	var bytes := int(descriptor.width) * int(descriptor.height) * 4
	# Bounded shared page references, not an eagerly resident recipe pack. Actual
	# Sprite2D/AtlasTexture users retain their page safely if the cache evicts it.
	while not _pages.is_empty() and _page_bytes + bytes > PAGE_CACHE_BYTES:
		var oldest: String = _pages.keys()[0]
		for candidate: String in _pages:
			if int(_pages[candidate].used) < int(_pages[oldest].used):
				oldest = candidate
		_page_bytes -= int(_pages[oldest].bytes)
		_pages.erase(oldest)
		page_evictions += 1
	if bytes <= PAGE_CACHE_BYTES:
		_pages[path] = {"texture": texture, "bytes": bytes, "used": _use_serial}
		_page_bytes += bytes
	return texture

static func _inside(path: String, directory: String) -> bool:
	return path == path.simplify_path() and path.begins_with(directory) and not path.ends_with("/")

static func _fingerprints() -> Dictionary:
	if _sources.is_empty():
		_sources = Plan.fingerprints()
	return _sources

static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return _number(value) and float(value) == floorf(float(value)) and float(value) >= minimum and float(value) <= maximum
