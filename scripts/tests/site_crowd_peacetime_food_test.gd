extends SceneTree
## PEACE1e (NEKKI_DECISION_20261031_crowd_peacetime_systems): food delivery under crowd, at peace only.
## One case per run, picked with --peace-case:
##   food_delivery_peace        a stopped friendly crowd carrier hands one ration to an adjacent friendly crowd member. The timed job
##                              completes; the carrier's cargo loses the food and the team's supply gains one ration.
##   food_delivery_refused_in_combat  the same start during combat (combat_left > 0) is refused with CROWD_ACTIVE; nothing changes.
##   saveload_food_delivery     the team's rations after a completed crowd delivery survive capture_for_save, a native save/load and
##                              controller.save_to / Store.load_site.
## Run: -- --crowd --crowd-test <fresh run_id> --peace-case <case> --crowd-atlas-root res://output/site_siege_close_20261004/equipment_atlas_runtime
## Fails fast on the first failed check. Needs two adjacent friendly crowd members at rest; the fixture reports when it has none.
const DT := 1.0 / 30.0
const CASES := ["food_delivery_peace", "food_delivery_refused_in_combat", "saveload_food_delivery"]
const Sustain := preload("res://scripts/terrain_lab/site_sustain.gd")
const Store := preload("res://scripts/terrain_lab/site_store.gd")
const SAVE_NAME := "peace1_food.json"
var crowd_controlled := -1 # the controlled person the native crowd section was saved with (restored before save)
var lab: TerrainLab
var controller: SiteController
var site: Node
var case_name := "food_delivery_peace"

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String, details: Variant = null) -> bool:
	print("PEACE1E ", "OK " if ok else "FAIL ", label, " ", str(details) if details != null else "")
	if not ok:
		printerr("GATE FAIL: ", label)
		quit(2)
	return ok

func _tick(count: int) -> bool:
	for step in range(count):
		lab._process(DT)
		controller.person_actions.settle_after_contacts()
		if not controller._original_step_fault.is_empty():
			printerr("PEACE1E latched frame fault: ", controller._original_step_fault, " | ", _delivery_diag(0))
			print("PEACE1E FAIL latched frame fault: ", controller._original_step_fault)
			quit(2) # fail fast with the fault: the wait loops never reach the outer watchdog
			return false
	return true

func _run() -> void:
	create_timer(420.0).timeout.connect(func() -> void: quit(3))
	var args := OS.get_cmdline_user_args()
	if not check(args.has("--crowd") and args.has("--crowd-test"), "isolated crowd startup required"): return
	var pick := args.find("--peace-case")
	if pick >= 0 and pick + 1 < args.size(): case_name = str(args[pick + 1])
	if not check(case_name in CASES, "a known peace case is selected", case_name): return
	lab = load("res://scenes/terrain_lab/TerrainLab.tscn").instantiate()
	lab.npc = TerrainTestNPC.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	current_scene = lab
	lab.set_process(false)
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	controller = lab.site_controller
	site = lab.crowd_site
	controller._auto_save_blocked = true
	var deployed: Dictionary = lab.deploy_trial_armies([
		{"faction": 0, "count": 4, "troop_type": "melee_infantry", "female_percent": 0, "training": 80.0, "ai_enabled": false, "attack": false, "entry": "west"},
		{"faction": 1, "count": 6, "female_percent": 0, "training": 80.0, "ai_enabled": false, "attack": false, "entry": "east"}])
	if not check(deployed.ok and site.active and site.command_teams().size() == 2, "a crowd battle deploys two opposing teams", deployed): return
	var friend_team: Dictionary = site._team_by_id(int(site.command_teams()[0].team_id))
	var team_id := int(friend_team.team_id)
	crowd_controlled = int(lab.controlled_person_id())
	lab.terrain.site["controlled_person_id"] = int(friend_team.person_ids[0])
	# Stop the team (food needs a stopped team), then find two adjacent friendly members.
	# Original sequence: the team stops, then the fixture takes the adjacent pair. The members may still drift into place after the
	# stop check passes, so the pair wait is bounded (wall time and frames) and requires the team to be stopped in the same frame.
	var stopped := false
	for step in range(900):
		if not _tick(1): return
		if controller._team_stopped(_owner(team_id)):
			stopped = true
			break
	if not check(stopped, "the friendly team stops before the delivery"): return
	var wait_began := Time.get_ticks_msec()
	var pair: Array = []
	for step in range(900):
		if Time.get_ticks_msec() - wait_began > 200000: break
		if not _tick(1): return
		pair = _adjacent_pair(friend_team)
		if pair.size() == 2 and controller._team_stopped(_owner(team_id)): break
	if not check(pair.size() == 2, "the fixture has two adjacent friendly crowd members while the team is stopped (fixture check) | %s" % _delivery_diag(team_id), pair): return
	var carrier: int = int(pair[0])
	var receiver: int = int(pair[1])
	lab.terrain.site["controlled_person_id"] = carrier
	var record: Dictionary = site._records[carrier]
	if not record.get("cargo") is Dictionary: record["cargo"] = {}
	record.cargo["fish"] = int(record.cargo.get("fish", 0)) + 2
	match case_name:
		"food_delivery_peace":
			_delivery_case(team_id, carrier, receiver, false)
		"food_delivery_refused_in_combat":
			_delivery_case(team_id, carrier, receiver, true)
		"saveload_food_delivery":
			_saveload_case(team_id, carrier, receiver)

func _owner(team_id: int) -> Variant:
	for owner: Variant in site.person_owners():
		if int(owner.team_id) == team_id: return owner
	return null

# Two friendly members of the team on adjacent cells, read from the crowd owner (the grid helper does not apply to crowd rows).
func _adjacent_pair(team: Dictionary) -> Array:
	var cells := {}
	for identity: Variant in team.person_ids:
		var person: Dictionary = controller.person_actions._person(int(identity), false)
		if not person.is_empty(): cells[int(identity)] = Vector2i(person.cell)
	for first: int in cells:
		for second: int in cells:
			if first != second and (cells[first] - cells[second]).length_squared() == 1: return [first, second]
	return []

func _carrier_fish(carrier: int) -> int:
	return int(site._records[carrier].cargo.get("fish", 0))

func _rations(team_id: int) -> float:
	var entry: Dictionary = controller._supply_entry(_owner(team_id))
	if entry.is_empty(): return 0.0
	return Sustain.rations(entry.sustain, controller._supply_stock(entry))

# P1g diagnostic: the delivery entry, the controller's crowd sustain counters and the game clock, in one line.
func _delivery_diag(team_id: int) -> String:
	var owner: Variant = _owner(team_id)
	var supply: Dictionary = lab.terrain.site.get("team_supply", {})
	var entry: Dictionary = controller._supply_entry(owner) if owner != null else {}
	var delivery: Dictionary = entry.get("delivery", {})
	var delivery_text := "none" if delivery.is_empty() else "left=%.4f pending=%s requester=%s representative=%s" % [float(delivery.get("left", -1.0)), str(delivery.get("pending", false)), str(delivery.get("requester_id", -1)), str(delivery.get("representative_id", -1))]
	var people := ""
	for identity: int in [int(delivery.get("player_id", -1)), int(delivery.get("representative_id", -1))]:
		var person: Dictionary = controller.person_actions._person(identity, false)
		if person.is_empty(): continue
		people += " p%d[fatigue=%.2f rest=%s work_rest=%s threat=%s]" % [identity, float(controller.person_actions._body_get(person, "fatigue")), str(controller.person_actions._body_get(person, "fatigue_rest")), str(controller.person_actions._body_get(person, "work_resting")), str(controller.person_actions._threat(person, {}))]
	return "team=%d owner_team=%s supply_keys=%s delivery=[%s]%s crowd_sustain runs=%d skip=[%s] steps=%d last=[%s] settle runs=%d pending_seen=%d paused=%s site_paused=%s minute=%s" % [
		team_id, str(owner.team_id) if owner != null else "none", str(supply.keys()), delivery_text, people,
		controller.crowd_sustain_runs, controller.crowd_sustain_skip, controller.crowd_delivery_steps, controller.crowd_delivery_last,
		controller.supply_settle_runs, controller.supply_settle_pending, str(lab.get_tree().paused), str(bool(lab.terrain.site.paused)), str(lab.terrain.site.get("minute", -1))]

func _delivery_case(team_id: int, carrier: int, receiver: int, in_combat: bool) -> void:
	var before_fish := _carrier_fish(carrier)
	var before_rations := _rations(team_id)
	lab.terrain.site["combat_left"] = 30.0 if in_combat else 0.0
	var begun: Dictionary = controller.begin_team_food(_owner(team_id), 1.0, receiver)
	lab.terrain.site["combat_left"] = 0.0
	if in_combat:
		if not check(str(begun.get("code", "")) == "CROWD_ACTIVE", "food delivery is refused in combat with CROWD_ACTIVE", begun): return
		if not check(_carrier_fish(carrier) == before_fish and is_equal_approx(_rations(team_id), before_rations), "nothing moves in a refused delivery"): return
		print("PEACE1E GATE OK: food_delivery_refused_in_combat")
		quit(0)
		return
	if not check(bool(begun.get("ok", false)), "the peaceful delivery starts | %s" % _delivery_diag(team_id), begun): return
	print("PEACE1E DIAG start: %s" % _delivery_diag(team_id))
	var finished := false
	var wait_started := Time.get_ticks_msec()
	for step in range(1800):
		if Time.get_ticks_msec() - wait_started > 200000:
			break # bounded wall time: fail with the diagnostic instead of timing out at the outer watchdog
		if not _tick(1): return
		if lab.terrain.site.get("team_supply", {}).get(str(team_id), {}).get("delivery", {}).is_empty():
			finished = true
			break
	if not check(finished, "the timed delivery completes and clears its job | %s" % _delivery_diag(team_id)): return
	# The grid rule (site_food_delivery_test.gd _food conservation): the completion commit adds the ration to the team's stock and
	# then Sustain.resupply fills the current meal's missing coverage from it, reported as consumed_rations. A team that was not fed
	# for this meal eats part of the ration at once, so the conserved quantity is stock gain + eaten = the ration delivered.
	var completion: Dictionary = controller.supply_settle_result
	if not check(bool(completion.get("ok", false)) and completion.has("consumed_rations"), "the completion commit succeeded and reports the meal it fed | settle=[%s]" % controller.supply_settle_last, completion): return
	var eaten: float = float(completion.consumed_rations)
	if not check(eaten >= 0.0 and eaten <= 1.0 + 0.000001, "the meal eats at most the delivered ration", eaten): return
	if not check(_carrier_fish(carrier) == before_fish - 1 and absf(_rations(team_id) - before_rations + eaten - 1.0) < 0.000001, "the carrier loses one ration and the team gains it (stock gain + eaten = 1) | settle=[%s] message=[%s] %s" % [controller.supply_settle_last, controller.message.text, _delivery_diag(team_id)], [before_fish, _carrier_fish(carrier), before_rations, _rations(team_id), eaten]): return
	print("PEACE1E GATE OK: food_delivery_peace")
	quit(0)

func _saveload_case(team_id: int, carrier: int, receiver: int) -> void:
	_delivery_prepare_and_finish(team_id, receiver)
	lab.terrain.site["controlled_person_id"] = crowd_controlled # the test set the carrier as controlled for the job; the native section keeps the original
	var before := _rations(team_id)
	var captured: Dictionary = controller._capture_for_save()
	if not check(bool(captured.get("ok", false)), "the save capture is valid after the delivery", captured.get("code", "OK")): return
	var blob: PackedByteArray = site.crowd.save_state()
	if not check(site.crowd.load_state(blob), "the native state reloads"): return
	site.crowd.render_set_kits(site._kit_ids)
	site._rebuild_rider_ids()
	var save_path: String = controller.save_root.path_join(SAVE_NAME)
	var saved: Dictionary = controller.save_to(save_path)
	if not check(bool(saved.get("ok", false)), "the crowd save writes the team rations: %s" % str(saved), saved): return
	var loaded: Dictionary = Store.load_site(save_path)
	if not check(bool(loaded.get("ok", false)), "the food save loads: %s" % str(loaded.get("message", "")), loaded): return
	var entry: Dictionary = loaded.data.site.get("team_supply", {}).get(str(team_id), {})
	var after: float = Sustain.rations(entry.sustain, controller._supply_stock(entry)) if not entry.is_empty() else 0.0
	if not check(is_equal_approx(after, before), "the team rations survive save and load: %s / %s" % [before, after], entry): return
	print("PEACE1E GATE OK: saveload_food_delivery rations=%s" % str(before))
	quit(0)

func _delivery_prepare_and_finish(team_id: int, receiver: int) -> void:
	var begun: Dictionary = controller.begin_team_food(_owner(team_id), 1.0, receiver)
	if not begun.ok:
		printerr("PEACE1E delivery did not start: ", begun)
		quit(2)
	var wait_started := Time.get_ticks_msec()
	for step in range(1800):
		if Time.get_ticks_msec() - wait_started > 200000:
			break # bounded wall time: fail with the diagnostic instead of timing out at the outer watchdog
		_tick(1)
		if lab.terrain.site.get("team_supply", {}).get(str(team_id), {}).get("delivery", {}).is_empty(): return
	printerr("PEACE1E delivery did not finish | ", _delivery_diag(team_id))
	quit(2)
