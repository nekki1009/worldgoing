extends SceneTree
## L1/L2 supply integration through the actual common action clock in each mode.
const Sustain = preload("res://scripts/terrain_lab/site_sustain.gd")
const DT := 1.0 / 30.0
var lab: TerrainLab
var checks := 0
var failed := false
var rows: Array[Dictionary] = []
var crowd_mode := false
var out := ""

func _initialize() -> void: _run.call_deferred()

func _check(ok: bool, label: String, details: Variant = null) -> bool:
	checks += 1
	rows.append({"ok": ok, "check": label, "details": details})
	print("SUSTAIN_SCENE ", "OK " if ok else "FAIL ", label, " ", details)
	if not ok: failed = true
	return ok

func _time() -> float:
	return (float(lab.terrain.site.minute) + float(lab.terrain.site.phase)) * 60.0

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	crowd_mode = not args.has("--grid")
	if not _check(args.has("--crowd-test"), "isolated named test required"): quit(2); return
	create_timer(240.0).timeout.connect(func() -> void: printerr("GATE FAIL: sustain scene deadline"); quit(3))
	var stamp := Time.get_datetime_string_from_system().replace("-", "").replace(":", "").replace("T", "_")
	out = "res://output/crowd_c2_c3_20261001/sustain_scene_%s_%s" % ["crowd" if crowd_mode else "ordinary", stamp]
	var output_at := args.find("--crowd-output")
	if output_at >= 0:
		if not _check(output_at + 1 < args.size(), "--crowd-output requires a directory"): quit(2); return
		out = args[output_at + 1].replace("\\", "/").simplify_path()
	if not _check(out.begins_with("res://output/") and not FileAccess.file_exists(out.path_join("sustain_scene.json")), "evidence output is project-local and preserves earlier results", out): quit(2); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	lab = load("res://scenes/terrain_lab/TerrainLab.tscn").instantiate()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	current_scene = lab
	lab.set_process(false)
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	lab.site_controller._auto_save_blocked = true
	var sides: Array[Dictionary] = []
	for index in range(3): sides.append({"faction": 0, "count": 2, "attack": false, "ai_enabled": false, "entry": "west", "training": 50.0})
	var deployed: Dictionary = lab.deploy_trial_armies(sides)
	if not _check(deployed.ok, "formal safe allied deployment", deployed): quit(2); return
	# Let original stationary formation initialization finish before the two-hour window.
	for tick in range(150):
		lab._advance_action_time(DT)
		if tick % 30 == 0: await process_frame
	var owners: Array = lab.crowd_site.person_owners() if crowd_mode else lab.combat_armies
	var tested: Array[Dictionary] = []
	lab.terrain.site.team_supply = {}
	for owner in owners:
		if crowd_mode and lab.crowd_site.team_record(owner.formation_index).is_empty(): continue
		if not crowd_mode and not owner.has_army(): continue
		var members: Dictionary = owner.original_members() if crowd_mode else lab.site_controller.captivity_supply._original_members(owner)
		var state: Dictionary = Sustain.create(_time())
		if not _check(Sustain.add_members(state, members, members.keys()).ok, "enable original supply history", owner.team_id): quit(2); return
		var slot := tested.size()
		state.morale = 60.0
		state.routed = slot == 2
		state.regroup_seconds = 0.0
		state.cohorts[0].hunger = 4.0
		if slot == 0:
			# Same legitimate partial meal in both modes: completes after one hour.
			state.cohorts[0].coverage = 1.0
			state.cohorts[0].meal_until = _time() + 3600.0
			state.cohorts[0].bonus_pending = true
		var life := {}
		for identity: int in members: life[str(identity)] = 0
		var entry := {"version": 1, "sustain": state, "inventory": {"grain": 4} if slot == 0 else {},
			"training_order": false, "training_requester": -1, "revision": 0, "delivery": {}, "life_checkpoint": life}
		lab.terrain.site.team_supply[str(owner.team_id)] = entry
		if crowd_mode:
			if not _check(lab.crowd_site.set_formation_fields(owner.formation_index, {"morale": 60.0, "routed": slot == 2, "rally_rest": 0.0}), "set authored morale on original native formation", slot): quit(2); return
		tested.append({"team": owner, "entry": entry, "slot": slot})
	if not _check(tested.size() == 3 and float(lab.terrain.site.combat_left) == 0.0, "three noncombat original supply owners"): quit(2); return
	var start := _time()
	var steps := 0
	var clock_error := {}
	while _time() - start < 7200.0 - 0.00001:
		lab._advance_action_time(DT)
		steps += 1
		for record: Dictionary in tested:
			var state: Dictionary = record.entry.sustain
			if not state.cohorts.is_empty() and absf(float(state.at) - _time()) > 0.00001:
				clock_error = {"team": record.team.team_id, "site": _time(), "supply": state.at, "step": steps}
		if not clock_error.is_empty(): break
		if steps % 120 == 0: await process_frame
	if not _check(clock_error.is_empty() and _time() - start >= 7200.0 - 0.00001, "every occupied supply owner matches Site clock for two game hours", {"seconds": _time() - start, "steps": steps, "difference": clock_error}):
		_write_and_quit()
		return
	var values: Array[Dictionary] = []
	for record: Dictionary in tested:
		var state: Dictionary = record.entry.sustain
		var hot: Dictionary = lab.crowd_site.formation_state(record.team.formation_index) if crowd_mode else {"morale": state.morale, "rally_rest": state.regroup_seconds, "routed": state.routed}
		values.append({"slot": record.slot, "morale": hot.morale, "rally_rest": hot.rally_rest, "routed": bool(hot.routed), "supply_at": state.at, "cold_morale": state.morale, "cohorts": state.cohorts.duplicate(true)})
		var expected := 72.0 if record.slot == 0 else 56.0
		_check(absf(float(hot.morale) - expected) <= 0.01, "two-hour food/shortage morale matches original formula", {"slot": record.slot, "expected": expected, "actual": hot.morale})
		_check(absf(float(hot.rally_rest) - (1800.0 if record.slot == 0 else 0.0)) <= 0.01, "full food accumulates and shortage resets rally time", {"slot": record.slot, "actual": hot.rally_rest})
		if record.slot == 2: _check(bool(hot.routed), "zero food cannot rally routed original team")
	rows.append({"mode": "crowd" if crowd_mode else "ordinary", "seconds": _time() - start, "values": values})
	_write_and_quit()

func _write_and_quit() -> void:
	var file := FileAccess.open(out.path_join("sustain_scene.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"ok": not failed, "checks": checks, "results": rows}, "\t", true, true))
	file.close()
	lab.queue_free()
	await process_frame
	print("GATE FAIL: sustain scene" if failed else "GATE OK: sustain scene", " ", out)
	quit(2 if failed else 0)
