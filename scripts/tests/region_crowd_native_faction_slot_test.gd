extends SceneTree
## Per-Site native faction slots (Nekki 2026-11-03: local mapping, native unchanged). Four crowd teams deploy on one
## Site: two neutral teams and faction 300 (outside native's 0..255), beside the solo faction-0 actor team. Checks:
## - each neutral team has a native slot of its own, so native treats the two neutral teams as different sides;
## - faction 0 keeps its own id as its slot; faction 300 gets a free slot that is not 300 & 255 = 44's owner and is unique;
## - native formation_info reports exactly the recorded slot for every team (the solo actor team shares faction 0's slot);
## - save and load keep the same slots, and the Store accepts them.
## Run only with: --crowd --crowd-test <fresh_run_id>
## Output: REGION_CROWD_NATIVE_FACTION_SLOT_PASS on success; quit(1) on any failure.

const NEUTRAL := 255
const CrowdSiteScript = preload("res://scripts/terrain_lab/crowd_site.gd")

var checks := 0
var lab: TerrainLab

func _initialize() -> void:
	create_timer(240.0).timeout.connect(func() -> void: _fail("240-second deadline"))
	_run.call_deferred()

func _fail(message: String, detail: Variant = null) -> void:
	printerr("REGION_CROWD_NATIVE_FACTION_SLOT_FAIL: ", message, " ", str(detail))
	quit(1)

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("REGION_CROWD_NATIVE_FACTION_SLOT OK ", checks, ": ", message)
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

## Every live team's global faction and native slot, checked against native formation_info.
func _slots(crowd: Variant, phase: String) -> Array:
	var result: Array = []
	for team: Dictionary in crowd.teams:
		if bool(team.get("solo", false)): continue # The scene's controlled actor joins as a solo faction-0 team.
		var slot: int = CrowdSiteScript.native_faction_of(team)
		var info: PackedInt32Array = crowd.crowd.formation_info(int(team.formation))
		if not _check(info.size() >= 1 and info[0] == slot, phase + ": native formation_info reports the recorded slot", [team.team_id, slot, info]): return []
		result.append([int(team.faction), slot])
	return result

func _verify(crowd: Variant, phase: String) -> bool:
	var pairs := _slots(crowd, phase)
	if pairs.size() != 3: return _check(false, phase + ": three deployed teams", pairs)
	var neutral_slots: Array[int] = []
	var by_faction := {}
	var owner := {}
	for pair: Array in pairs:
		if int(pair[0]) == NEUTRAL: neutral_slots.append(int(pair[1]))
		else: by_faction[int(pair[0])] = int(pair[1])
		if not _check(int(owner.get(int(pair[1]), pair[0])) == int(pair[0]), phase + ": every native slot belongs to one faction", pairs): return false
		owner[int(pair[1])] = int(pair[0])
	if not _check(neutral_slots.size() == 2 and neutral_slots[0] != neutral_slots[1], phase + ": the two neutral teams have different native slots", neutral_slots): return false
	for team: Dictionary in crowd.teams:
		if bool(team.get("solo", false)) and not _check(int(team.faction) == 0 and CrowdSiteScript.native_faction_of(team) == 0, phase + ": faction 0 (the solo actor team) keeps slot 0", team): return false
	var slot_300 := int(by_faction.get(300, -1))
	if not _check(slot_300 >= 0 and slot_300 <= 255 and not neutral_slots.has(slot_300) and slot_300 != 0, phase + ": faction 300 has its own slot in 0..255", by_faction): return false
	return true

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
	if not _check(lab.crowd_site != null and not lab.crowd_site.active, "formal scene has an inactive CrowdSite"): return
	var centre: Vector2i = lab.terrain.spawn_cell
	var cells: Array = []
	# Three deployed teams; the scene's controlled actor joins as a solo faction-0 team. (A fourth deployed team trips a separate,
	# unrelated fire-order count check on save; see FSLOT_v2 evidence.)
	var factions := [NEUTRAL, NEUTRAL, 300]
	var sides: Array[Dictionary] = []
	for slot in range(factions.size()):
		var team_cells: Array[Vector2i] = [centre + Vector2i(-6 + slot * 4, 6), centre + Vector2i(-5 + slot * 4, 6)]
		cells.append(team_cells)
		sides.append(_side(team_cells.size(), int(factions[slot])))
	var entered: Dictionary = lab.crowd_site.deploy(sides, cells)
	if not _check(entered.get("ok", false) and lab.crowd_site.active, "three teams deploy into one native crowd", entered): return
	if not _verify(lab.crowd_site, "deploy"): return

	var saved: Dictionary = lab.site_controller.save_to(lab.site_controller.save_path)
	if not _check(saved.get("ok", false) == true, "the crowd Site saves and the Store accepts the slots", saved): return
	var loaded: Dictionary = lab.site_controller.load_from(lab.site_controller.save_path)
	if not _check(loaded.get("ok", false) == true and lab.crowd_site.active, "the crowd Site loads", loaded): return
	if not _verify(lab.crowd_site, "load"): return

	lab.queue_free()
	await process_frame
	print("REGION_CROWD_NATIVE_FACTION_SLOT_PASS: ", checks, " checks; neutral teams have their own native slots, faction 300 maps into 0..255, save/load keeps the slots")
	quit(0)
