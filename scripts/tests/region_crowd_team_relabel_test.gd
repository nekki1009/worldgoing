extends SceneTree
## Joining a faction, base step (Nekki 2026-11-04, C): a whole crowd team changes faction. Teams: a neutral team, two
## faction-1 teams (they share faction 1's native slot) and a faction-2 team. Checks:
## - the neutral team relabels to faction 1: its teams entry, roster row and TerrainArmy container say faction 1, it keeps
##   its own native slot, and RegionFactionQuery.same_side now holds with faction 1;
## - a faction-1 team that shares its slot with another faction-1 team is refused (leaving a faction is a later flow);
## - save and load keep the relabel; the Store accepts faction 1 holding two native slots.
## Run only with: --crowd --crowd-test <fresh_run_id>
## Output: REGION_CROWD_TEAM_RELABEL_PASS on success; quit(1) on any failure.

const NEUTRAL := 255
const CrowdSiteScript = preload("res://scripts/terrain_lab/crowd_site.gd")

var checks := 0
var lab: TerrainLab

func _initialize() -> void:
	create_timer(240.0).timeout.connect(func() -> void: _fail("240-second deadline"))
	_run.call_deferred()

func _fail(message: String, detail: Variant = null) -> void:
	printerr("REGION_CROWD_TEAM_RELABEL_FAIL: ", message, " ", str(detail))
	quit(1)

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("REGION_CROWD_TEAM_RELABEL OK ", checks, ": ", message)
		return true
	_fail(message, detail)
	return false

func _side(count: int, faction: int) -> Dictionary:
	var parsed: Dictionary = lab._trial_side_settings({"friendly_count": count, "friendly_training": 0,
		"friendly_female_percent": 0, "friendly_attack": false, "friendly_ai_enabled": false}, "friendly")
	if not _check(parsed.ok, "original side settings accepted", parsed): return {}
	var side: Dictionary = parsed.side
	side.faction = faction
	return side

func _entry(crowd: Variant, team_id: int) -> Dictionary:
	for team: Dictionary in crowd.teams:
		if int(team.team_id) == team_id: return team
	return {}

func _roster(crowd: Variant, team_id: int) -> Dictionary:
	for row: Dictionary in crowd.rosters:
		if int(row.team_id) == team_id: return row
	return {}

func _container_faction(team_id: int) -> int:
	for army: TerrainArmy in lab.combat_armies:
		if army.team_id == team_id: return army.faction_id
	return -1

## The joined team holds faction 1 everywhere and keeps its own slot `slot`.
func _joined(crowd: Variant, team_id: int, slot: int, phase: String) -> bool:
	var entry := _entry(crowd, team_id)
	if not _check(int(entry.get("faction", -1)) == 1 and CrowdSiteScript.native_faction_of(entry) == slot, phase + ": the joined team is faction 1 on its own slot", entry): return false
	if not _check(int(_roster(crowd, team_id).get("faction_id", -1)) == 1, phase + ": the joined roster row is faction 1"): return false
	if not _check(_container_faction(team_id) == 1, phase + ": the joined team's TerrainArmy container is faction 1", _container_faction(team_id)): return false
	return _check(RegionFactionQuery.same_side(int(entry.faction), 1), phase + ": the joined team is on faction 1's side")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if not _check(args.has("--crowd") and args.has("--crowd-test"), "native startup and a fresh --crowd-test run id required"): return
	var packed := load("res://scenes/terrain_lab/TerrainLab.tscn") as PackedScene
	if not _check(packed != null, "formal TerrainLab scene exists"): return
	lab = packed.instantiate() as TerrainLab
	if not _check(lab != null, "formal TerrainLab instance exists"): return
	lab.pause_when_unfocused = false
	lab.movement_input_enabled = false
	root.add_child(lab)
	current_scene = lab
	lab.set_process(false)
	if not _check(lab.character != null and lab.site_controller != null, "formal scene has its player body and Controller"): return
	lab.character.set_process(false)
	lab.site_controller._auto_save_blocked = true
	var centre: Vector2i = lab.terrain.spawn_cell
	var factions := [NEUTRAL, 1, 1, 2]
	var cells: Array = []
	var sides: Array[Dictionary] = []
	for slot in range(factions.size()):
		var team_cells: Array[Vector2i] = [centre + Vector2i(-6 + slot * 4, 6), centre + Vector2i(-5 + slot * 4, 6)]
		cells.append(team_cells)
		sides.append(_side(team_cells.size(), int(factions[slot])))
	var entered: Dictionary = lab.crowd_site.deploy(sides, cells)
	if not _check(entered.get("ok", false) and lab.crowd_site.active, "four teams deploy into one native crowd", entered): return
	var crowd: Variant = lab.crowd_site
	var ids: Array[int] = []
	for team: Dictionary in crowd.teams:
		if not bool(team.get("solo", false)): ids.append(int(team.team_id))
	ids.sort()
	if not _check(ids.size() == 4, "four deployed teams", ids): return
	var neutral_id := ids[0]
	var neutral_slot := CrowdSiteScript.native_faction_of(_entry(crowd, neutral_id))
	if not _check(int(_entry(crowd, neutral_id).faction) == NEUTRAL, "the first team starts neutral"): return

	var joined: Dictionary = lab.relabel_team_faction(neutral_id, 1)
	if not _check(joined.get("ok", false) == true and joined.get("changed", false) == true, "the neutral team joins faction 1", joined): return
	if not _joined(crowd, neutral_id, neutral_slot, "relabel"): return
	var again: Dictionary = lab.relabel_team_faction(neutral_id, 1)
	if not _check(again.get("ok", false) == true and again.get("changed", true) == false, "joining the same faction again changes nothing", again): return
	var shared: Dictionary = lab.relabel_team_faction(ids[1], 2)
	if not _check(shared.get("ok", true) == false and str(shared.get("code", "")) == "BUSY", "a team sharing its faction's slot cannot change faction alone", shared): return

	var saved: Dictionary = lab.site_controller.save_to(lab.site_controller.save_path)
	if not _check(saved.get("ok", false) == true, "the relabelled Site saves; faction 1 may hold two native slots", saved): return
	var loaded: Dictionary = lab.site_controller.load_from(lab.site_controller.save_path)
	if not _check(loaded.get("ok", false) == true and lab.crowd_site.active, "the relabelled Site loads", loaded): return
	if not _joined(lab.crowd_site, neutral_id, neutral_slot, "load"): return
	if not _check(lab.crowd_site.last_event_error.is_empty() or str(lab.crowd_site.last_event_error.get("code", "")) != "INVALID", "the load re-asserts the slot alliances", lab.crowd_site.last_event_error): return

	lab.queue_free()
	await process_frame
	print("REGION_CROWD_TEAM_RELABEL_PASS: ", checks, " checks; a whole team joins faction 1 on its own slot, a shared slot refuses, save/load keeps it")
	quit(0)
