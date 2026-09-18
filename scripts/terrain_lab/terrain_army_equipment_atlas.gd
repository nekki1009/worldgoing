extends RefCounted
## Shared presentation data only. No soldier, item, health or animation clock owner.
const Plan = preload("res://scripts/tools/terrain_army_recipe_bake_plan.gd")
const RangedAtlas = preload("res://scripts/terrain_lab/terrain_army_ranged_atlas.gd")
const DyeAtlas = preload("res://scripts/terrain_lab/terrain_army_dye_atlas.gd")
const WagonRecipe = preload("res://scripts/terrain_lab/site_wagon_rider_recipe.gd")
const BASE_MANIFEST := "res://assets/characters/terrain_lab_army/standard_soldier/standard_soldier_atlas.json"
const CATALOG := "res://assets/characters/terrain_lab_army/standard_soldier/recipes/v1/catalog.json"
const FEMALE_ROOT := "res://assets/characters/terrain_lab_army/standard_female/v1"
const FEMALE_BAKER := "res://scripts/tools/bake_terrain_army_female.gd"
const FEMALE_RANGED_ROOT := "res://assets/characters/terrain_lab_army/standard_female/ranged/v1"
const FEMALE_RANGED_BAKER := "res://scripts/tools/bake_terrain_army_female_ranged.gd"
const WAGON_FOOT_ROOT := "res://assets/vehicles/logistics/v1/riders/foot"
const WAGON_FOOT_BAKER := "res://scripts/tools/bake_wagon_rider_foot.gd"
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
static var _female := {}
static var _female_dye := {}
static var _female_materials := {}
static var _female_ranged := {}
static var _female_root := FEMALE_ROOT # Same private publication root; tests use isolated output fixtures.
static var _wagon_foot := {}

static func refresh_female_sources() -> void:
	# Recheck disk provenance at a load boundary, never on each rendered frame.
	_female.clear()
	_female_dye.clear()
	_female_ranged.clear()
	_female_materials.clear()
	_wagon_foot.clear()

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
	if not wagon_foot_recipe(appearance).is_empty(): return true
	if appearance.get("body") == 1:
		return not female_recipe(appearance).is_empty() and (appearance.get("equipment_dyes", {}).is_empty() or not dye_entry(appearance).is_empty())
	if not HumanCharacter3DEditor.valid_appearance(appearance) or not DyeAtlas.supports(appearance): return false
	appearance = DyeAtlas.Dye.geometry_appearance(appearance)
	if RangedAtlas.supports_weapon(str(appearance.get("parts", {}).get("weapon", ""))) and not RangedAtlas.recipe(appearance).is_empty():
		return true
	var mask := _appearance_mask(appearance)
	return mask >= 0 and not _recipe(mask, _appearance_iron(appearance)).is_empty()

static func frame(appearance: Dictionary, clip: String, direction: String, sample_time: float) -> Dictionary:
	if not HumanCharacter3DEditor.valid_appearance(appearance): return {}
	var recipe := wagon_foot_recipe(appearance)
	if recipe.is_empty():
		if appearance.get("body") == 1:
			if not supports(appearance): return {}
		elif not DyeAtlas.supports(appearance): return {}
	appearance = DyeAtlas.Dye.geometry_appearance(appearance)
	if not is_finite(sample_time) or sample_time < 0.0:
		return {}
	if recipe.is_empty() and appearance.get("body") == 1:
		recipe = female_recipe(appearance)
	if recipe.is_empty() and RangedAtlas.supports_weapon(str(appearance.get("parts", {}).get("weapon", ""))):
		recipe = RangedAtlas.recipe(appearance)
	if recipe.is_empty():
		var mask := _appearance_mask(appearance)
		if mask >= 0:
			recipe = _recipe(mask, _appearance_iron(appearance))
	if recipe.is_empty():
		return {}
	# Existing Army may already have resolved a no-shield guard's logical alias.
	clip = normalized_clip(clip)
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

static func female_appearance() -> Dictionary:
	if not _load_base(): return {}
	var appearance: Dictionary = _base.appearance.duplicate(true)
	appearance.body = 1.0
	appearance.parts.hair = HumanCharacter3DEditor.default_appearance(1).parts.hair
	return appearance

static func female_recipe(appearance: Dictionary) -> Dictionary:
	if not HumanCharacter3DEditor.valid_appearance(appearance): return {}
	appearance = DyeAtlas.Dye.geometry_appearance(appearance)
	if appearance != female_appearance():
		var weapon := str(appearance.get("parts", {}).get("weapon", ""))
		var ranged_plan := female_ranged_plan(weapon)
		if ranged_plan.is_empty() or appearance != ranged_plan.appearance: return {}
		if _female_ranged.has(weapon): return _female_ranged[weapon]
		var ranged := _single_page_recipe(appearance, FEMALE_RANGED_ROOT + "/" + weapon, "terrain_army_female_ranged_recipe", female_ranged_sources(), 29, ranged_plan)
		if not ranged.is_empty(): _female_ranged[weapon] = ranged
		return ranged
	if not _female.is_empty(): return _female
	var sources := Plan.fingerprints()
	sources[FEMALE_BAKER] = FileAccess.get_md5(FEMALE_BAKER)
	_female = _single_page_recipe(female_appearance(), _female_root, "terrain_army_female_recipe", sources, 31)
	return _female

static func female_ranged_plan(weapon: String) -> Dictionary:
	if weapon not in RangedAtlas.WEAPONS or not _load_base(): return {}
	var selected := RangedAtlas.plan(weapon, _base)
	if selected.is_empty(): return {}
	selected.appearance.body = 1.0
	selected.appearance.parts.hair = HumanCharacter3DEditor.default_appearance(1).parts.hair
	selected.key = "standard_female_ranged_v1/" + weapon
	return selected

static func female_ranged_sources() -> Dictionary:
	var sources := RangedAtlas.fingerprints()
	if sources.is_empty(): return {}
	for path: String in [FEMALE_RANGED_BAKER, "res://scripts/terrain_lab/terrain_army_equipment_atlas.gd"]:
		var digest := FileAccess.get_md5(path)
		if digest.length() != 32: return {}
		sources[path] = digest
	return sources

static func wagon_foot_recipe(appearance: Dictionary) -> Dictionary:
	if not WagonRecipe.matches(appearance): return {}
	var body := int(appearance.body)
	appearance = DyeAtlas.Dye.geometry_appearance(WagonRecipe.appearance(body))
	if _wagon_foot.has(body): return _wagon_foot[body]
	var sources := Plan.fingerprints()
	if sources.is_empty(): return {}
	for path: String in [WAGON_FOOT_BAKER, "res://scripts/terrain_lab/site_wagon_rider_recipe.gd"]:
		var digest := FileAccess.get_md5(path)
		if digest.length() != 32: return {}
		sources[path] = digest
	var recipe := _single_page_recipe(appearance, WAGON_FOOT_ROOT + ("/male" if body == 0 else "/female"), "terrain_army_wagon_rider_foot", sources, 28)
	if not recipe.is_empty(): _wagon_foot[body] = recipe
	return recipe

static func _single_page_recipe(appearance: Dictionary, directory: String, kind: String, sources: Dictionary, mask: int, ranged_plan: Dictionary = {}) -> Dictionary:
	if not _load_base() or sources.is_empty(): return {}
	var path := directory + "/manifest.json"
	if not FileAccess.file_exists(path): return {}
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not manifest is Dictionary or manifest.get("schema_version") != 1 or manifest.get("kind") != kind or manifest.get("appearance") != appearance or manifest.get("source_fingerprints") != sources or manifest.get("source_manifest_md5") != FileAccess.get_md5(BASE_MANIFEST): return {}
	var clips: Array[Dictionary] = []
	clips.assign(_base.clips)
	var directions: Array[Dictionary] = []
	directions.assign(_base.directions)
	var plan := Plan.build(PackedStringArray(["--recipe-mask=%d" % mask, "--recipe-output=res://output/check", "--recipe-clips=all", "--recipe-directions=all", "--recipe-first=0", "--recipe-count=128"]), clips, directions, _base.appearance)
	if not ranged_plan.is_empty():
		plan = ranged_plan.duplicate(true)
		plan.ok = true
		if manifest.get("recipe_key") != plan.key: return {}
	if not plan.ok or manifest.get("clips") != plan.clips or manifest.get("directions") != plan.directions or not manifest.get("frames") is Array or manifest.frames.size() != plan.recipe_total or not manifest.get("pages") is Array or manifest.pages.size() != 1 or not _number(manifest.get("map_scale")) or not is_equal_approx(float(manifest.map_scale), float(_base.map_scale)): return {}
	var page: Variant = manifest.pages[0]
	if not page is Dictionary or page.get("page") != 0 or not _integer(page.get("width"), 1, 16384) or not _integer(page.get("height"), 1, 16384): return {}
	for field: String in ["path", "resource_path"]:
		if not _inside(str(page.get(field, "")), directory + "/") or not FileAccess.file_exists(page[field]): return {}
	if page.get("png_md5") != FileAccess.get_md5(page.path) or page.get("resource_md5") != FileAccess.get_md5(page.resource_path): return {}
	var metrics: Variant = manifest.get("metrics")
	if not metrics is Dictionary or str(metrics.get("pixel_sha256", "")).length() != 64 or metrics.get("pixel_sha256") != metrics.get("png_decoded_sha256") or metrics.get("pixel_sha256") != metrics.get("resource_decoded_sha256"): return {}
	var sequences := {}
	var ordinal := 0
	for clip: Dictionary in plan.clips:
		for direction: Dictionary in plan.directions:
			var sequence: Array[Dictionary] = []
			var pose := str(clip.get("pose", clip.id))
			var looping := pose in ["idle", "walk", "run", "guard", "unconscious"]
			for index in range(int(clip.samples)):
				var value: Variant = manifest.frames[ordinal]
				if not value is Dictionary or value.get("clip") != clip.id or value.get("direction") != direction.id or value.get("frame") != index or value.get("selection_index") != ordinal or value.get("page") != 0 or value.get("resolved_pose") != pose: return {}
				if not _number(value.get("duration")) or float(value.duration) <= 0.0 or not _number(value.get("sample_time")): return {}
				var expected := float(value.duration) * index / float(int(clip.samples) if looping else int(clip.samples) - 1)
				if not is_equal_approx(float(value.sample_time), expected) or (not sequence.is_empty() and value.duration != sequence[0].duration): return {}
				var rect: Variant = value.get("rect")
				var anchor: Variant = value.get("anchor_offset")
				if not rect is Dictionary or not anchor is Dictionary or not _integer(rect.get("x"), 0, int(page.width)) or not _integer(rect.get("y"), 0, int(page.height)) or not _integer(rect.get("w"), 1, int(page.width)) or not _integer(rect.get("h"), 1, int(page.height)) or int(rect.x) + int(rect.w) > int(page.width) or int(rect.y) + int(rect.h) > int(page.height) or not _number(anchor.get("x")) or not _number(anchor.get("y")): return {}
				value._page = page
				sequence.append(value)
				ordinal += 1
			sequences[str(clip.id) + "|" + str(direction.id)] = sequence
	return {"sequences": sequences, "map_scale": float(manifest.map_scale), "source_manifest": path}

static func dye_entry(appearance: Dictionary) -> Dictionary:
	if appearance.get("body") != 1: return DyeAtlas.entry(appearance)
	var recipe := female_recipe(appearance)
	if recipe.is_empty(): return {}
	var directory := str(recipe.source_manifest).get_base_dir()
	if _female_dye.has(directory): return _female_dye[directory]
	var path := directory + "/dye.json"
	if not FileAccess.file_exists(path): return {}
	var record: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not record is Dictionary or record.get("schema_version") != 1 or record.get("complete") != true or record.get("slots") != DyeAtlas.Dye.SLOTS or record.get("source_fingerprints") != DyeAtlas.fingerprints() or record.get("appearance") != DyeAtlas.Dye.geometry_appearance(appearance): return {}
	var source_path := directory + "/manifest.json"
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(source_path))
	if record.get("source_manifest") != source_path or record.get("source_manifest_md5") != FileAccess.get_md5(source_path) or record.get("frame_count") != source.frames.size() or record.get("mask_path") != directory + "/dye.png" or record.get("mask_md5") != FileAccess.get_md5(record.mask_path) or record.get("width") != source.pages[0].width or record.get("height") != source.pages[0].height: return {}
	_female_dye[directory] = record
	return record

static func apply_dye(sprite: Sprite2D, appearance: Dictionary) -> bool:
	if appearance.get("body") != 1: return DyeAtlas.apply(sprite, appearance)
	if sprite.get_meta("equipment_dye_appearance", {}) == appearance: return true
	var colors: Dictionary = appearance.get("equipment_dyes", {})
	if colors.is_empty():
		sprite.material = null
	else:
		var record := dye_entry(appearance)
		if record.is_empty(): return false
		var key := str(record.mask_path)
		if not _female_materials.has(key):
			var mask := Image.load_from_file(record.mask_path)
			if mask == null: return false
			var material := ShaderMaterial.new()
			material.shader = Shader.new()
			material.shader.code = DyeAtlas.SHADER
			material.set_shader_parameter("dye_map", ImageTexture.create_from_image(mask))
			_female_materials[key] = material
		sprite.material = _female_materials[key]
		for slot: String in DyeAtlas.Dye.SLOTS:
			sprite.set_instance_shader_parameter(slot + "_dye", DyeAtlas.canvas_color(colors[slot]) if colors.has(slot) else Vector4.ZERO)
	sprite.set_meta("equipment_dye_appearance", appearance.duplicate(true))
	return true

static func normalized_clip(clip: String) -> String:
	return "guard" if clip in ["guard_unshielded", "guard_weapon", "guard_polearm", "guard_spear"] else clip.replace("guard_weapon_", "guard_").replace("guard_polearm_", "guard_")

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
	if seen.size() != expected.size():
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
