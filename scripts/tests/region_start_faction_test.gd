extends SceneTree
## Main-menu start choice "found own faction" (Nekki 2026-11-04, C). A new world is requested through RegionEntry with
## start_faction {"mode": "found", "name": ...} and opened in the formal TerrainLab scene. Checks:
## - the Region faction registry holds a new active faction of kind "player" with that name;
## - the player's start team (the controlled captain and the cadres) is that faction, not neutral, live in the crowd;
## - an empty name is refused before any world is created.
## Output: REGION_START_FACTION_PASS on success; quit(1) on any failure or the deadline.

const SITE := "res://scenes/terrain_lab/TerrainLab.tscn"
const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
const START := Vector2i(1170, 13252)
const NAME := "測試國"

var checks := 0
var _finished := false

func _initialize() -> void:
	create_timer(280.0).timeout.connect(func() -> void: _fail("280-second deadline"))
	_run.call_deferred()

func _fail(message: String, detail: Variant = null) -> void:
	if _finished: return
	_finished = true
	printerr("REGION_START_FACTION_FAIL: ", message, " ", str(detail))
	quit(1)

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("REGION_START_FACTION OK ", checks, ": ", message)
		return true
	_fail(message, detail)
	return false

func _run() -> void:
	var refused: bool = RegionEntry.request_new_world(START, {}, "空名", "", RegionData.DEFAULT_MANIFEST, {"mode": "found", "name": "  "})
	if not _check(not refused, "an empty faction name is refused before any world", RegionEntry.menu_message): return
	var requested: bool = RegionEntry.request_new_world(START, {}, "自建勢力世界", "", RegionData.DEFAULT_MANIFEST, {"mode": "found", "name": NAME})
	if not _check(requested and str(RegionEntry.pending.get("start_faction", {}).get("mode", "")) == "found", "the found-faction start is requested", RegionEntry.menu_message): return
	change_scene_to_file(SITE)
	var lab: TerrainLab = null
	for _frame: int in range(900):
		await process_frame
		if _finished: return
		var scene := current_scene as TerrainLab
		if scene != null and scene.site_controller != null and scene.site_controller.region_slot != null and scene.site_controller._boot_request.is_empty() and scene.crowd_site != null and scene.crowd_site.active:
			lab = scene
			break
	if not _check(lab != null, "the new world opens and settles its boot request", [current_scene.scene_file_path if current_scene != null else "", RegionEntry.menu_message, (current_scene as TerrainLab).site_controller.message.text if current_scene is TerrainLab else "", (current_scene as TerrainLab).crowd_site.active if current_scene is TerrainLab and (current_scene as TerrainLab).crowd_site != null else null]): return
	for _frame: int in range(5): await process_frame
	var slot: RegionSaveSlot = lab.site_controller.region_slot
	var registry: Dictionary = slot.control.get("faction_registry", {})
	var founded := -1
	for key: String in registry.get("entries", {}):
		var entry: Dictionary = registry.entries[key]
		if str(entry.get("kind", "")) == "player" and str(entry.get("name", "")) == NAME and str(entry.get("status", "")) == "active": founded = int(entry.faction_id)
	if not _check(founded >= 0 and founded != RegionFactionQuery.NEUTRAL_FACTION_ID, "the registry holds the new active player faction", registry.get("entries", {}).keys()): return
	var leader: Variant = registry.entries[str(founded)].get("leader_ref")
	var crowned: Dictionary = RegionPeerage.record_of(registry, leader)
	if not _check(RegionFactionQuery.ref_valid(leader, "person") and crowned.get("rank") == "king" and crowned.get("liege_ref") == null, "the founder is the faction's leader and its king (head of the peerage)", [leader, crowned]): return
	var player := int(lab.controlled_person_id())
	var target: Dictionary = lab._original_person_target(player)
	if not _check(not target.is_empty() and int(target.get("unit", -1)) >= 0, "the player is a roster person of its start team"): return
	var owner: Variant = target.owner
	if not _check(int(owner.faction_id) == founded, "the player's start team is the founded faction", [owner.faction_id, founded]): return
	var team_entry: Dictionary = {}
	for team: Dictionary in lab.crowd_site.teams:
		if int(team.team_id) == int(owner.team_id): team_entry = team
	if not _check(int(team_entry.get("faction", -1)) == founded and team_entry.get("person_ids", []).size() == 1 + TerrainLab.INITIAL_CADRES, "the whole start team (captain and cadres) joined", team_entry): return
	_finished = true
	print("REGION_START_FACTION_PASS: ", checks, " checks; the found-faction start creates a player faction and the start team joins it")
	quit(0)
