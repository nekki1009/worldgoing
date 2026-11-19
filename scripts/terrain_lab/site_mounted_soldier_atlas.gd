class_name SiteMountedSoldierAtlas
extends RefCounted
## Mounted ordinary-soldier display atlas (CAV-3b; horse layer and crowd pages CAV-3 INT).
## Display and admission only: no person, equipment, horse, HP or animation-time
## ownership belongs here.
## A manifest is accepted only when it is complete, every source fingerprint and
## every asset md5 still matches, and the required frame spec below is exact.
## available() is the single admission question: every clip and direction of the
## appearance's weapon family must exist for that body, in both layers (rider and horse).
## Layers share one ground anchor; the horse is drawn first, the rider over it (the
## rider pass already removed the limbs the horse hides).
## Pages are lossless Image resources (.res): nothing here depends on editor import of
## generated PNGs, so exported builds load the same files.

const VERSION := 2
const ROOT := "res://assets/army/mounted_soldiers/v2/"
const DIRECTIONS: Array[String] = ["down", "left", "up", "right"]
const BODIES: Array[int] = [0, 1]
const HORSE_GROUP := "horse"
const WeaponMaterials = preload("res://scripts/ui/weapon_materials.gd")
# Exact frame counts per clip. The crowd view maps progress to index floor(progress * count).
const CLIP_FRAMES := {"ride_idle": 1, "ride_walk": 8, "ride_run": 8, "ride_heavy": 6,
	"ride_slash": 8, "ride_thrust": 8, "attack_bow": 8, "attack_crossbow": 8}
const LOOPING_CLIPS := ["ride_idle", "ride_walk", "ride_run"]
# The horse clip under each rider clip (the editor's own _sync_mount_animation mapping).
const HORSE_CLIPS := {"ride_idle": "horse_idle", "ride_walk": "horse_walk", "ride_run": "horse_run", "ride_heavy": "horse_idle",
	"ride_slash": "horse_run", "ride_thrust": "horse_run", "attack_bow": "horse_idle", "attack_crossbow": "horse_idle"}
const FAMILY_CLIPS := {
	"longsword_01": ["ride_idle", "ride_walk", "ride_run", "ride_heavy", "ride_slash"],
	"axe_01": ["ride_idle", "ride_walk", "ride_run", "ride_heavy", "ride_slash"],
	"hammer_01": ["ride_idle", "ride_walk", "ride_run", "ride_heavy", "ride_slash"],
	"dagger_01": ["ride_idle", "ride_walk", "ride_run", "ride_heavy", "ride_slash"],
	"none": ["ride_idle", "ride_walk", "ride_run", "ride_heavy", "ride_slash"],
	"spear_01": ["ride_idle", "ride_walk", "ride_run", "ride_heavy", "ride_thrust"],
	"bow_01": ["ride_idle", "ride_walk", "ride_run", "ride_heavy", "ride_slash", "attack_bow"],
	"crossbow_01": ["ride_idle", "ride_walk", "ride_run", "ride_heavy", "ride_slash", "attack_crossbow"],
}
# Crowd presentation slots (CrowdSite.SLOTS) that a rider shows; every other slot falls back to idle natively.
const CROWD_SLOT_CLIPS := {"idle": "ride_idle", "walk": "ride_walk", "run": "ride_run", "attack_heavy": "ride_heavy", "guard": "ride_idle"}
const CROWD_PAGE_WIDTH := 4096
const CROWD_PAGE_MAX_HEIGHT := 16384
static var _root: String = ROOT
static var _manifest: Dictionary = {}
static var _available: Dictionary = {}
static var _textures: Dictionary = {}
static var _crowd: Dictionary = {}

# Test seam: point the reader at another directory (with trailing slash) and drop every cache.
static func set_root_for_test(root: String) -> void:
	_root = root
	_manifest = {}
	_available = {}
	_textures = {}
	_crowd = {}

static func family_for(appearance: Dictionary) -> String:
	if not HumanCharacter3DEditor.valid_appearance(appearance): return ""
	var parts: Dictionary = appearance.get("parts", {})
	var family := str(WeaponMaterials.family(StringName(str(parts.get("weapon", "none")))))
	return family if FAMILY_CLIPS.has(family) else ""

static func frame_key(body: int, family: String, clip: String, direction: String, index: int) -> String:
	return "%d/%s/%s/%s/%d" % [body, family, clip, direction, index]

static func horse_key(clip: String, direction: String, index: int) -> String:
	return "%s/%s/%d" % [clip, direction, index]

# Sample phase of frame index in clip: loops never repeat their first pose, one-shots end on their last.
static func phase(clip: String, index: int) -> float:
	var count := int(CLIP_FRAMES.get(clip, 1))
	return float(index) / float(count) if clip in LOOPING_CLIPS else float(index) / float(maxi(count - 1, 1))

# Crowd clip of a presentation slot for a mounted appearance ("" = the native idle fallback).
static func crowd_clip(slot: String, appearance: Dictionary) -> String:
	var family := family_for(appearance)
	if family.is_empty(): return ""
	match slot:
		"attack": return "ride_thrust" if family == "spear_01" else "ride_slash"
		"shoot":
			if family == "bow_01": return "attack_bow"
			if family == "crossbow_01": return "attack_crossbow"
			return ""
	return str(CROWD_SLOT_CLIPS.get(slot, ""))

# Places two layers that share one ground point. Anchors are ground minus frame centre, in source pixels.
# Returns the composite size, each layer's integer top-left and the composite's own anchor.
static func compose_layout(rider_size: Vector2i, rider_anchor: Vector2, horse_size: Vector2i, horse_anchor: Vector2) -> Dictionary:
	var rider_corner := -rider_anchor - Vector2(rider_size) * 0.5
	var horse_corner := -horse_anchor - Vector2(horse_size) * 0.5
	var base := Vector2(minf(rider_corner.x, horse_corner.x), minf(rider_corner.y, horse_corner.y))
	var rider_at := Vector2i((rider_corner - base).round())
	var horse_at := Vector2i((horse_corner - base).round())
	var size := Vector2i(maxi(rider_at.x + rider_size.x, horse_at.x + horse_size.x), maxi(rider_at.y + rider_size.y, horse_at.y + horse_size.y))
	var origin := rider_corner - Vector2(rider_at) # The rider stays exact; the horse moves by under half a pixel at most.
	return {"size": size, "rider": rider_at, "horse": horse_at, "anchor": -(origin + Vector2(size) * 0.5)}

static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _rect_ok(value: Variant) -> bool:
	if not value is Array or value.size() != 4: return false
	for number: Variant in value:
		if not _number(number) or float(number) < 0.0: return false
	return float(value[2]) >= 1.0 and float(value[3]) >= 1.0

static func _pair_ok(value: Variant) -> bool:
	return value is Array and value.size() == 2 and _number(value[0]) and _number(value[1])

static func _same_clips(value: Variant) -> bool:
	if not value is Dictionary or value.size() != HORSE_CLIPS.size(): return false
	for clip: String in HORSE_CLIPS:
		if str(value.get(clip, "")) != str(HORSE_CLIPS[clip]): return false
	return true

static func _load_manifest() -> bool:
	if not _manifest.is_empty(): return true
	var path := _root + "manifest.json"
	if not FileAccess.file_exists(path): return false
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not value is Dictionary: return false
	if value.get("version") != VERSION or value.get("complete") != true or value.get("kind") != "mounted_soldier_atlas": return false
	if value.get("directions") != ["down", "left", "up", "right"]: return false
	if value.get("bodies", []).size() != BODIES.size() or not _same_clips(value.get("horse_clips")) or not _number(value.get("map_scale")): return false
	var sources: Variant = value.get("source_fingerprints", {})
	if not sources is Dictionary or sources.is_empty(): return false
	for source_path: String in sources:
		if FileAccess.get_md5(source_path) != sources[source_path]: return false
	var asset_md5: Dictionary = value.get("asset_md5", {})
	var pages: Array = value.get("pages", [])
	if pages.is_empty(): return false
	for page_index in range(pages.size()):
		var page: Variant = pages[page_index]
		if not page is Dictionary or not _number(page.get("page")) or int(page.page) != page_index: return false
		for name: String in [str(page.get("colour_res", "")), str(page.get("dye_res", ""))]:
			if not name.ends_with(".res") or not FileAccess.file_exists(_root + name): return false
			if FileAccess.get_md5(_root + name) != asset_md5.get(name, ""): return false
	var lookup := {}
	for item: Variant in value.get("frames", []):
		if not item is Dictionary or not _number(item.get("page")) or int(item.page) < 0 or int(item.page) >= pages.size(): return false
		if not _rect_ok(item.get("rect")) or not _pair_ok(item.get("anchor")) or not _pair_ok(item.get("horse_offset")): return false
		lookup[frame_key(int(item.get("body", -1)), str(item.get("family", "")), str(item.get("clip", "")), str(item.get("direction", "")), int(item.get("frame", -1)))] = item
	var horses := {}
	for item: Variant in value.get("horse_frames", []):
		if not item is Dictionary or not _number(item.get("page")) or int(item.page) < 0 or int(item.page) >= pages.size(): return false
		if str(pages[int(item.page)].get("group", "")) != HORSE_GROUP or not _rect_ok(item.get("rect")) or not _pair_ok(item.get("anchor")): return false
		horses[horse_key(str(item.get("clip", "")), str(item.get("direction", "")), int(item.get("frame", -1)))] = item
	var durations: Variant = value.get("clip_durations", {})
	if not durations is Dictionary: return false
	value["lookup"] = lookup
	value["horse_lookup"] = horses
	_manifest = value
	return true

static func available(appearance: Dictionary) -> bool:
	if not HumanCharacter3DEditor.valid_appearance(appearance) or not bool(appearance.get("mounted", false)): return false
	var family := family_for(appearance)
	if family.is_empty(): return false
	var body := int(appearance.body)
	if not BODIES.has(body): return false
	var cache_key := "%d/%s" % [body, family]
	if _available.has(cache_key): return bool(_available[cache_key])
	var result := _family_complete(body, family)
	_available[cache_key] = result
	return result

static func _family_complete(body: int, family: String) -> bool:
	if not _load_manifest(): return false
	var counts: Dictionary = _manifest.get("frame_counts", {}).get(family, {})
	var required: Array = FAMILY_CLIPS[family]
	if counts.size() != required.size(): return false
	for clip: String in required:
		if not counts.has(clip) or int(counts[clip]) != int(CLIP_FRAMES[clip]): return false
		var seconds: Variant = _manifest.clip_durations.get(clip)
		if not _number(seconds) or float(seconds) <= 0.0: return false
		for direction: String in DIRECTIONS:
			for index: int in range(int(counts[clip])):
				if not _manifest["lookup"].has(frame_key(body, family, clip, direction, index)): return false
				if not _manifest["horse_lookup"].has(horse_key(clip, direction, index)): return false
	return true

# Sprite path. Returns {} when refused. Otherwise texture (rider AtlasTexture), dye (rider slot mask),
# horse {texture, anchor} (draw first), anchor and horse_offset in map pixels, and map_scale.
# progress is clamped to 0..1.
static func frame(appearance: Dictionary, clip: String, direction: String, progress: float) -> Dictionary:
	if not available(appearance) or not FAMILY_CLIPS[family_for(appearance)].has(clip): return {}
	if direction not in DIRECTIONS or not is_finite(progress): return {}
	var family := family_for(appearance)
	var count := int(CLIP_FRAMES[clip])
	var index := mini(count - 1, floori(clampf(progress, 0.0, 1.0) * float(count)))
	var item: Dictionary = _manifest["lookup"].get(frame_key(int(appearance.body), family, clip, direction, index), {})
	var horse: Dictionary = _manifest["horse_lookup"].get(horse_key(clip, direction, index), {})
	if item.is_empty() or horse.is_empty(): return {}
	var rider_page := _page_textures(int(item.page))
	var horse_page := _page_textures(int(horse.page))
	if rider_page.is_empty() or horse_page.is_empty(): return {}
	var scale := float(_manifest["map_scale"])
	var colour := AtlasTexture.new()
	colour.atlas = rider_page.colour
	colour.region = _rect(item.rect)
	var dye := AtlasTexture.new()
	dye.atlas = rider_page.dye
	dye.region = colour.region
	var horse_texture := AtlasTexture.new()
	horse_texture.atlas = horse_page.colour
	horse_texture.region = _rect(horse.rect)
	return {"texture": colour, "dye": dye, "key": frame_key(int(appearance.body), family, clip, direction, index),
		"map_scale": scale, "anchor": _pair(item.anchor) * scale, "horse_offset": _pair(item.horse_offset), "frame": index,
		"horse": {"texture": horse_texture, "anchor": _pair(horse.anchor) * scale}}

static func _rect(value: Array) -> Rect2:
	return Rect2(float(value[0]), float(value[1]), float(value[2]), float(value[3]))

static func _pair(value: Array) -> Vector2:
	return Vector2(float(value[0]), float(value[1]))

static func _page_images(page: int) -> Dictionary:
	var info: Dictionary = _manifest["pages"][page]
	var colour := ResourceLoader.load(_root + str(info.colour_res), "Image") as Image
	var dye := ResourceLoader.load(_root + str(info.dye_res), "Image") as Image
	if colour == null or dye == null or colour.is_empty() or dye.get_size() != colour.get_size(): return {}
	if colour.get_format() != Image.FORMAT_RGBA8 or dye.get_format() != Image.FORMAT_RGB8: return {}
	return {"colour": colour, "dye": dye}

static func _page_textures(page: int) -> Dictionary:
	if _textures.has(page): return _textures[page]
	var images := _page_images(page)
	var result := {} if images.is_empty() else {"colour": ImageTexture.create_from_image(images.colour), "dye": ImageTexture.create_from_image(images.dye)}
	_textures[page] = result
	return result

static func crowd_key(appearance: Dictionary) -> String:
	return "mounted_soldier_v%d:%d/%s" % [VERSION, int(appearance.get("body", -1)), family_for(appearance)]

# Crowd batch page for one body/family: every horse frame with its rider frame composed on top, in one
# texture with one matching dye mask (horse pixels undyed). Built once per body/family from the pages
# that hold them. sequences use the batch-view frame shape ({rect, anchor_offset, sample_time, duration}).
static func crowd_recipe(appearance: Dictionary) -> Dictionary:
	if not available(appearance): return {}
	var key := crowd_key(appearance)
	if _crowd.has(key): return _crowd[key]
	var body := int(appearance.body)
	var family := family_for(appearance)
	var scale := float(_manifest["map_scale"])
	var images := {}
	var placed: Array[Dictionary] = []
	var cursor := Vector2i.ZERO
	var row_height := 0
	for clip: String in FAMILY_CLIPS[family]:
		for direction: String in DIRECTIONS:
			for index: int in range(int(CLIP_FRAMES[clip])):
				var rider: Dictionary = _manifest["lookup"][frame_key(body, family, clip, direction, index)]
				var horse: Dictionary = _manifest["horse_lookup"][horse_key(clip, direction, index)]
				for page: int in [int(rider.page), int(horse.page)]:
					if not images.has(page):
						images[page] = _page_images(page)
						if images[page].is_empty():
							_crowd[key] = {}
							return {}
				var rider_rect := Rect2i(_rect(rider.rect))
				var horse_rect := Rect2i(_rect(horse.rect))
				var layout := compose_layout(rider_rect.size, _pair(rider.anchor), horse_rect.size, _pair(horse.anchor))
				var size: Vector2i = layout.size
				if cursor.x + size.x > CROWD_PAGE_WIDTH:
					cursor = Vector2i(0, cursor.y + row_height)
					row_height = 0
				placed.append({"clip": clip, "direction": direction, "index": index, "at": cursor, "layout": layout,
					"rider": rider, "rider_rect": rider_rect, "horse": horse, "horse_rect": horse_rect})
				cursor.x += size.x
				row_height = maxi(row_height, size.y)
	var height := cursor.y + row_height
	if height < 1 or height > CROWD_PAGE_MAX_HEIGHT:
		_crowd[key] = {}
		return {}
	var colour := Image.create(CROWD_PAGE_WIDTH, height, false, Image.FORMAT_RGBA8)
	var dye := Image.create(CROWD_PAGE_WIDTH, height, false, Image.FORMAT_RGB8)
	var sequences := {}
	for item: Dictionary in placed:
		var layout: Dictionary = item.layout
		var at: Vector2i = item.at
		var horse_page: Dictionary = images[int(item.horse.page)]
		var rider_page: Dictionary = images[int(item.rider.page)]
		colour.blit_rect(horse_page.colour, item.horse_rect, at + Vector2i(layout.horse))
		colour.blend_rect(rider_page.colour, item.rider_rect, at + Vector2i(layout.rider))
		dye.blit_rect_mask(rider_page.dye, rider_page.colour, item.rider_rect, at + Vector2i(layout.rider))
		var clip := str(item.clip)
		var seconds := float(_manifest.clip_durations[clip])
		var size: Vector2i = layout.size
		var anchor: Vector2 = layout.anchor
		var sequence_key := clip + "|" + str(item.direction)
		if not sequences.has(sequence_key): sequences[sequence_key] = []
		sequences[sequence_key].append({"rect": {"x": at.x, "y": at.y, "w": size.x, "h": size.y},
			"anchor_offset": {"x": anchor.x, "y": anchor.y}, "sample_time": seconds * phase(clip, int(item.index)),
			"duration": seconds, "frame": int(item.index)})
	var result := {"key": key, "texture": ImageTexture.create_from_image(colour), "dye": ImageTexture.create_from_image(dye),
		"sequences": sequences, "map_scale": scale}
	_crowd[key] = result
	return result
