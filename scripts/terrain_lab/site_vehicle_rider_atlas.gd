extends RefCounted
## Mounted-only cloth display selected by gender, independent of actual gear.
## Dismount restores the original person's normal renderer; no appearance is saved.
## Legacy manifests remain readable for source audits. No person,
## vehicle, horse, equipment or animation-time ownership belongs to this reader.
const ROOT := "res://assets/vehicles/logistics/v1/riders/"
const CLOTH_ROOT := ROOT + "cloth_v1/"
const ClothRecipe = preload("res://scripts/terrain_lab/site_wagon_rider_recipe.gd")
const DyeAtlas = preload("res://scripts/terrain_lab/terrain_army_dye_atlas.gd")
const EquipmentAtlas = preload("res://scripts/terrain_lab/terrain_army_equipment_atlas.gd")
static var _manifest := {}
static var _cloth_manifest := {}

static func _load_manifest(cloth: bool = false) -> bool:
	if not (_cloth_manifest if cloth else _manifest).is_empty(): return true
	var directory := CLOTH_ROOT if cloth else ROOT
	if not FileAccess.file_exists(directory + "manifest.json"): return false
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(directory + "manifest.json"))
	if not value is Dictionary or value.get("version") != 1 or value.get("complete") != true or value.get("frames", []).size() != 72: return false
	if cloth and value.get("appearances") != [DyeAtlas.Dye.geometry_appearance(ClothRecipe.appearance(0)), DyeAtlas.Dye.geometry_appearance(ClothRecipe.appearance(1))]: return false
	for path: String in value.get("source_fingerprints", {}):
		if FileAccess.get_md5(path) != value.source_fingerprints[path]: return false
	for name: String in ["atlas.res", "dye.png"]:
		if not FileAccess.file_exists(directory + name) or FileAccess.get_md5(directory + name) != value.get("asset_md5", {}).get(name, ""): return false
	value.directory = directory
	value.lookup = {}
	for item: Dictionary in value.frames:
		value.lookup["%d/%s/%s/%d" % [int(item.body), item.clip, item.direction, int(item.frame)]] = item
	if cloth: _cloth_manifest = value
	else: _manifest = value
	return true

static func _bundle(appearance: Dictionary) -> Dictionary:
	if not HumanCharacter3DEditor.valid_appearance(appearance): return {}
	# The input still validates the original real person/holder, but only gender
	# selects this display. Never equip, recolour, cache over or serialize their kit.
	return _cloth_manifest if _load_manifest(true) else {}

static func supports(appearance: Dictionary) -> bool:
	return not _bundle(appearance).is_empty()

static func frame(appearance: Dictionary, direction: String, moving: bool, progress: float) -> Dictionary:
	if not supports(appearance) or direction not in ["down", "left", "up", "right"] or not is_finite(progress): return {}
	var bundle := _bundle(appearance)
	var number := mini(7, floori(clampf(progress, 0.0, 1.0) * 8.0)) if moving else 0
	var key := "%d/%s/%s/%d" % [int(appearance.body), "ride_walk" if moving else "ride_idle", direction, number]
	if not bundle.lookup.has(key): return {}
	var item: Dictionary = bundle.lookup[key]
	if not bundle.has("texture"): bundle.texture = load(str(bundle.directory) + "atlas.res") as Texture2D
	if bundle.texture == null: return {}
	if not item.has("texture"):
		var texture := AtlasTexture.new()
		texture.atlas = bundle.texture
		texture.region = Rect2(float(item.rect[0]), float(item.rect[1]), float(item.rect[2]), float(item.rect[3]))
		item.texture = texture
	return {"texture": item.texture, "key": key, "map_scale": float(bundle.map_scale),
		"anchor": Vector2(float(item.anchor[0]), float(item.anchor[1])) * float(bundle.map_scale),
		"horse_offset": Vector2(float(item.horse_offset[0]), float(item.horse_offset[1])), "frame": number}

static func apply(sprite: Sprite2D, appearance: Dictionary, value: Dictionary) -> bool:
	if value.is_empty() or not supports(appearance): return false
	sprite.texture = value.texture
	sprite.scale = Vector2.ONE * float(value.map_scale)
	sprite.material = null # Fixed cloth pixels; no faction or actual-item dye.
	sprite.set_meta("vehicle_rider_frame", value.key)
	# The ordinary equipment shader must be restored after an actual dismount.
	sprite.remove_meta("equipment_dye_appearance")
	return true
