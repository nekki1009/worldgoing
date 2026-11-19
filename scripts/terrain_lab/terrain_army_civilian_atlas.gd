extends RefCounted
## CIV-A0 frozen contract only. New clothes, captures, admission and resident activity owners follow in A1–A4.
const PROFILE := "civilian_v1"
const DIRECTIONS := ["down", "left", "up", "right"]
const NATIVE_DIRECTIONS := ["up", "right", "down", "left"]
const ACTIONS := [
	{"id": "idle", "samples": 4, "duration": -1.0, "loop": true, "phase1": true},
	{"id": "walk", "samples": 8, "duration": -1.0, "loop": true, "phase1": true},
	{"id": "run", "samples": 8, "duration": -1.0, "loop": true, "phase1": true},
	{"id": "civilian_carry", "samples": 8, "duration": 1.0, "loop": true, "phase1": false},
	{"id": "civilian_lift", "samples": 12, "duration": 1.6, "loop": false, "reverse_reuse": true, "phase1": false},
	{"id": "civilian_sit", "samples": 8, "duration": 1.2, "loop": false, "reverse_reuse": true, "hold_last": true, "phase1": false},
	{"id": "civilian_fetch_water", "samples": 12, "duration": 2.4, "loop": false, "phase1": false},
	{"id": "hit", "samples": 8, "duration": -1.0, "loop": false, "phase1": true},
	{"id": "knockback", "samples": 8, "duration": -1.0, "loop": false, "phase1": true},
	{"id": "down", "samples": 12, "duration": -1.0, "loop": false, "phase1": true},
	{"id": "unconscious", "samples": 4, "duration": -1.0, "loop": true, "phase1": true},
	{"id": "get_up", "samples": 12, "duration": -1.0, "loop": false, "phase1": true},
]
const SOURCE_PATHS := [
	"res://assets/characters/human/q35/standard_anime_male_character_pack.glb",
	"res://assets/characters/human/q35/standard_anime_female_character_pack.glb",
	"res://assets/characters/terrain_lab_army/standard_soldier/standard_soldier_atlas.json",
	"res://scripts/ui/human_character_3d_editor.gd", "res://scripts/ui/equipment_dye.gd",
	"res://scripts/terrain_lab/terrain_army_equipment_atlas.gd", "res://scripts/terrain_lab/terrain_army_batch_view.gd",
	"res://scripts/terrain_lab/terrain_army_civilian_atlas.gd",
	"res://native/crowd10k/src/crowd_core.hpp", "res://native/crowd10k/src/render.cpp",
	"res://native/crowd10k/godot/crowd10k_gdext.cpp",
]

static func actions(phase1: bool = false) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for action: Dictionary in ACTIONS:
		if not phase1 or bool(action.phase1): result.append(action.duplicate(true))
	return result

static func frames(phase1: bool = false) -> int:
	var count: int = 0
	for action: Dictionary in actions(phase1): count += int(action.samples) * DIRECTIONS.size()
	return count

static func catalog() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for body: int in 2:
		for hatted: bool in [false, true]:
			var appearance: Dictionary = HumanCharacter3DEditor.default_appearance(body)
			appearance.parts["face"] = "face_standard_01"
			appearance.parts["hair"] = "hair_male_01" if body == 0 else "hair_female_01"
			appearance.parts["armor"] = "outfit_medieval_chinese_01"
			appearance.parts["outfit"] = "outfit_underlayer_01"
			appearance.parts["boots"] = "boots_civilian_straw_01"
			appearance.parts["helmet"] = "helmet_civilian_straw_01" if hatted else "none"
			for slot: String in ["weapon", "shield", "cape"]: appearance.parts[slot] = "none"
			var preset: String = "brown" if hatted else "blue"
			var colors: Dictionary = HumanCharacter3DEditor.EquipmentDye.PRESETS[preset].colors
			appearance["equipment_dyes"] = {"armor": colors.armor, "outfit": colors.outfit}
			result.append({"id": "CIV-%s0%d" % ["M" if body == 0 else "F", 2 if hatted else 1],
				"profile": PROFILE, "appearance": appearance, "palette_preset": preset,
				"publication": "UNPUBLISHED", "required_new_parts": ["boots_civilian_straw_01", "helmet_civilian_straw_01"] if hatted else ["boots_civilian_straw_01"]})
	return result

static func source_hashes() -> Dictionary:
	var hashes: Dictionary = {}
	for path: String in SOURCE_PATHS:
		var digest: String = FileAccess.get_sha256(path)
		if digest.length() != 64: return {}
		hashes[path] = digest
	return hashes

static func contract() -> Dictionary:
	return {"profile": PROFILE, "version": 1, "status": "CONTRACT_ONLY_UNPUBLISHED", "catalog": catalog(),
		"actions": actions(), "phase1_actions": actions(true), "directions": DIRECTIONS.duplicate(),
		"native_directions": NATIVE_DIRECTIONS.duplicate(), "frames_per_recipe": frames(), "phase1_frames_per_recipe": frames(true),
		"new_work_choice": "carry_lift_not_hoe", "geometry_recipes": 4, "palette_only_no_extra_pages": true,
		"source_sha256": source_hashes()}
