extends RefCounted
## Hand-off between the main menu, the Taiwan Region map and the main Site scene.
## Requests survive scene changes as static state; each fixed world keeps a small
## `world.json` (display name, times, active Site) for the menu's world list.

const MAIN_MENU := "res://scenes/main_menu/MainMenu.tscn"
const SITE_SCENE := "res://scenes/terrain_lab/TerrainLab.tscn"
const REGION_SCENE := "res://scenes/region_lab/RegionLab.tscn"
const MAP_EDITOR_SCENE := "res://scenes/map_editor/MapEditor.tscn"
const WORLDS := "user://region_lab/worlds"
const LAST_WORLD := "user://region_lab/last_world.json"
const SLOT := "main"
const MAX_WORLD_NAME := 32
const TechnologyPolicy = preload("res://scripts/terrain_lab/site_technology_policy.gd")
const TechnologyArtisans = preload("res://scripts/terrain_lab/site_technology_artisans.gd")

## Main-scene request: {manifest, world_id, slot_id, site, create_new[, character, world_name]}.
static var pending: Dictionary = {}
# Author UI hand-off is separate from gameplay/Technology initial_scenario_id.
static var author_request: Dictionary = {}

static func request_author_editor() -> void:
	author_request = {"manifest": RegionData.DEFAULT_MANIFEST}

static func take_author_request() -> Dictionary:
	var request := author_request
	author_request = {}
	return request
## RegionLab mode: "pick_start" from New Game, "view" from inside the game, "" for the lab.
static var region_mode := ""
## Map context while viewing from the game: {world_id, slot_id, active, visited}.
static var view: Dictionary = {}
## New Game draft carried between the menu and the start-Site picker.
static var draft: Dictionary = {}
## Failure to report on the main menu after a scene hand-off.
static var menu_message := ""

## start_faction: {"mode": "neutral"} (default), {"mode": "found", "name": ...} or {"mode": "bandit", "name": ...} (落草, bandit
## spec §10; only when the scenario allows it): the main-menu start choice, settled after birth.
## Bandit spec §10: a scenario may forbid the 落草 start with `allow_bandit_start: false`; the default allows it.
static func bandit_start_allowed(initial_scenario_id: String) -> bool:
	if initial_scenario_id.is_empty(): return true
	return bool(TechnologyArtisans.scenario_config(initial_scenario_id).get("allow_bandit_start", true))

static func request_new_world(site: Vector2i, character: Dictionary = {}, world_name: String = "", initial_scenario_id: String = "", manifest_path: String = RegionData.DEFAULT_MANIFEST, start_faction: Dictionary = {}) -> bool:
	if not initial_scenario_id.is_empty() and TechnologyArtisans.scenario_config(initial_scenario_id).is_empty():
		menu_message = "未知起始情境；未建立世界或人物"
		return false
	var mode := str(start_faction.get("mode", "neutral"))
	if mode not in ["neutral", "found", "bandit"] or mode != "neutral" and (str(start_faction.get("name", "")).strip_edges().is_empty() or str(start_faction.name).strip_edges().length() > 32):
		menu_message = ("落草的山寨" if mode == "bandit" else "自建勢力") + "須取 1–32 字的名稱；未建立世界"
		return false
	if mode == "bandit" and not bandit_start_allowed(initial_scenario_id):
		menu_message = "這個起始情境不允許落草開局；未建立世界"
		return false
	var accepted := false
	for choice: Dictionary in new_world_source_choices(): accepted = accepted or str(choice.path) == manifest_path
	if not accepted:
		var author: RegionData = RegionData.new()
		var loaded: Dictionary = author.load_author_package(manifest_path)
		var context: Dictionary = author.author_initial_context()
		accepted = loaded.ok and not context.is_empty() and initial_scenario_id.is_empty() and Vector2i(int(context.starting_site[0]), int(context.starting_site[1])) == site
	if not accepted:
		menu_message = "所選固定來源尚未發布或配對不完整；未建立世界"
		return false
	pending = {"manifest": manifest_path, "world_id": "taiwan_%d" % int(Time.get_unix_time_from_system()),
		"slot_id": SLOT, "site": site, "create_new": true, "character": character.duplicate(true),
		"world_name": world_name.strip_edges(), "initial_scenario_id": initial_scenario_id, "start_faction": start_faction.duplicate(true)}
	return true


static func request_world(world_id: String, slot_id: String = SLOT) -> bool:
	var meta := read_world(world_id)
	if meta.is_empty(): return false
	pending = {"manifest": str(meta.get("manifest", RegionData.DEFAULT_MANIFEST)), "world_id": world_id,
		"slot_id": slot_id, "site": Vector2i(-1, -1), "create_new": false}
	return true

static func request_resume() -> bool:
	return request_world(str(last_world().get("world_id", "")))

static func take_pending() -> Dictionary:
	var request := pending
	pending = {}
	return request

static func last_world() -> Dictionary:
	var decoded: Variant = _read_json(LAST_WORLD)
	if not decoded is Dictionary or str(decoded.get("world_id", "")).is_empty(): return {}
	if read_world(str(decoded.world_id)).is_empty(): return {}
	return decoded

## Records the world as opened/saved now. Keeps the first creation time and name.
static func record_world(world_id: String, slot_id: String, manifest_path: String, active: Vector2i, day: int, world_name: String = "") -> void:
	var meta := read_world(world_id)
	var slot_pin: Variant = _read_json(WORLDS.path_join(world_id).path_join("slots").path_join(slot_id).path_join("manifest.json"))
	if not slot_pin is Dictionary: return
	var policy: Dictionary = TechnologyPolicy.candidate(slot_pin, int(slot_pin.get("format", 0)) == 1)
	if not policy.ok: return
	if not meta.is_empty():
		var same: Dictionary = TechnologyPolicy.same_candidate(meta, slot_pin, int(meta.get("version", 0)) == 1, int(slot_pin.get("format", 0)) == 1)
		if not same.ok: return
	elif FileAccess.file_exists(world_path(world_id)): return # Preserve invalid metadata.
	var now := int(Time.get_unix_time_from_system())
	if meta.is_empty():
		meta = {"version": 2 if int(slot_pin.get("format", 0)) in [2, 3] else 1, "world_id": world_id, "created_unix": now,
			"name": world_name if not world_name.is_empty() else "台灣 %s" % Time.get_datetime_string_from_unix_time(now, true)}
	if int(meta.version) == 2: meta["technology_policy"] = policy.policy.duplicate(true)
	meta["slot_id"] = slot_id
	meta["manifest"] = manifest_path
	meta["saved_unix"] = now
	meta["active_site"] = [active.x, active.y]
	meta["day"] = day
	_write_json(world_path(world_id), meta)
	_write_json(LAST_WORLD, {"world_id": world_id, "slot_id": slot_id})

static func world_path(world_id: String) -> String:
	return WORLDS.path_join(world_id).path_join("world.json")

static func read_world(world_id: String) -> Dictionary:
	if world_id.is_empty() or not world_id.is_valid_filename(): return {}
	var decoded: Variant = _read_json(world_path(world_id))
	if not decoded is Dictionary or str(decoded.get("world_id", "")) != world_id: return {}
	var version: Variant = decoded.get("version")
	if not (version is int or version is float) or not is_finite(float(version)) or float(version) != floorf(float(version)) or int(version) not in [1, 2]: return {}
	var checked: Dictionary = TechnologyPolicy.candidate(decoded, int(version) == 1)
	return decoded if checked.ok else {}

## Worlds that have menu metadata, newest save first.
static func list_worlds() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var directory := DirAccess.open(WORLDS)
	if directory == null: return result
	for world_id: String in directory.get_directories():
		var meta := read_world(world_id)
		if not meta.is_empty(): result.append(meta)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("saved_unix", 0)) > int(b.get("saved_unix", 0)))
	return result

## Sites that have a saved generation (`<seq>_<x>_<y>_<hash>.json`) in this
## world's slot. Display only; the slot's commit chain stays authoritative.
static func visited_sites(world_id: String, slot_id: String) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var generations := DirAccess.open(WORLDS.path_join(world_id).path_join("slots").path_join(slot_id).path_join("generations"))
	if generations == null: return result
	for file: String in generations.get_files():
		var parts := file.get_basename().split("_")
		if file.get_extension() != "json" or parts.size() != 4 or not parts[1].is_valid_int() or not parts[2].is_valid_int(): continue
		var site := Vector2i(int(parts[1]), int(parts[2]))
		if site not in result: result.append(site)
	return result


static func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path): return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))

static func _write_json(path: String, value: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(value, "\t"))


## The released sources cannot change while the game runs, so the SHA-256 work below (a 6 MB manifest and
## its resource pair) runs once per process. The stamp (path, size, modified time of the checked files)
## guards the rare case of files replaced under a running editor; a changed stamp recomputes.
static var _source_choices_cache: Array[Dictionary] = []
static var _source_choices_stamp := ""

static func _source_choices_fingerprint() -> String:
	var parts: Array[String] = []
	var paths: Array[String] = ["res://assets/region_lab/earth_tw_tm2_121_v1_r4/manifest.terrain_mapped_potential_v1.json"]
	for pair: Dictionary in RegionData.RESOURCE_SOURCE_PAIRS.values(): paths.append(str(pair.path))
	for path: String in paths:
		var file := FileAccess.open(path, FileAccess.READ)
		parts.append("%s|%d|%d" % [path, file.get_length() if file != null else -1, FileAccess.get_modified_time(path)])
	return "\n".join(parts)

static func new_world_source_choices() -> Array[Dictionary]:
	var stamp := _source_choices_fingerprint()
	var result: Array[Dictionary] = []
	if stamp == _source_choices_stamp and not _source_choices_cache.is_empty():
		result.assign(_source_choices_cache.duplicate(true))
		return result
	result = _compute_new_world_source_choices()
	_source_choices_cache.assign(result.duplicate(true))
	_source_choices_stamp = stamp
	return result

static func _compute_new_world_source_choices() -> Array[Dictionary]:
	# Selection projects original released source metadata; it grants neither
	# knowledge nor policy. Candidate publication requires the same release gates.
	var result: Array[Dictionary] = [{"path": RegionData.DEFAULT_MANIFEST, "label": "台灣（原地類規則）"}]
	var catalog: Script = load("res://scripts/terrain_lab/site_technology_catalog.gd")
	for identity: String in ["F04", "F06", "F11", "F12"]:
		var node: Dictionary = catalog.call("get_node", identity) if catalog != null else {}
		if node.get("enabled") != true or node.get("status") != "implemented" or node.get("tuning_confirmed") != true: return result
	var geography := "res://assets/region_lab/earth_tw_tm2_121_v1_r4/manifest.terrain_mapped_potential_v1.json"
	var hash := FileAccess.get_sha256(geography)
	var pairs: Dictionary = RegionData.RESOURCE_SOURCE_PAIRS
	var pair: Dictionary = pairs.get(hash, {})
	if hash != "cdf59e3247c9db3eb1e5399f7346014f8dec5c2f90bb977fd41ea35bc3444446" or pair.is_empty() or FileAccess.get_sha256(str(pair.path)) != str(pair.sha256): return result
	result.append({"path": geography, "label": "台灣（地形衍生建設與水井條件）"})
	return result

