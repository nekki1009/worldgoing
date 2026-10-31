extends SceneTree
## SUSTAIN1 v5 (crowd sustain probe). The friendly crowd team is opted into team supply through the production path
## (SiteController._enable_team_supply, the call begin_team_food makes), then given a known stock. One case per run, --sustain-case:
##   peace      no combat. sustain.at advances with the Site clock; a meal falls due and the stock drops by the grid amount.
##   combat     combat_left > 0 during the ticks. sustain.at still advances with the Site clock.
##   saveload   after the peace ticks, sustain.at and the stock survive capture_for_save, a native save/load, save_to and Store.load_site.
## Run: -- --crowd --crowd-test <fresh run_id> --sustain-case <case> --crowd-atlas-root res://output/site_siege_close_20261004/equipment_atlas_runtime
## PROBE, not run: expectations are the grid rule (Sustain.advance_to on duplicated state, stock and members) and the Site clock.
## The probe never changes the controlled person: the native section must save with the one the crowd was built with.
const DT := 1.0 / 30.0
const TICKS := 300
const KNOWN_GRAIN := 12
const MEAL_SOON := 300.0 # seconds after the opt-in at which the first meal is forced due
const CASES := ["peace", "combat", "saveload"]
const Sustain := preload("res://scripts/terrain_lab/site_sustain.gd")
const Store := preload("res://scripts/terrain_lab/site_store.gd")
const SAVE_NAME := "sustain1_clock.json"
var lab: TerrainLab
var controller: SiteController
var site: Node
var case_name := "peace"

func _initialize() -> void:
	_run.call_deferred()

# Records one check. A failed check quits with code 2; callers return right after a false result, so no later read runs.
func check(ok: bool, label: String, details: Variant = null) -> bool:
	print("SUSTAIN1 ", "OK " if ok else "FAIL ", label, " ", str(details) if details != null else "")
	if not ok:
		printerr("GATE FAIL: ", label)
		quit(2)
	return ok

func _tick(count: int) -> bool:
	for step in range(count):
		lab._process(DT)
		controller.person_actions.settle_after_contacts()
		if not controller._original_step_fault.is_empty():
			printerr("SUSTAIN1 latched frame fault: ", controller._original_step_fault)
			print("SUSTAIN1 FAIL latched frame fault: ", controller._original_step_fault)
			quit(2)
			return false
	return true

# The Site clock in game seconds (the reading crowd_c2_sustain_scene_test uses).
func _site_seconds() -> float:
	return (float(lab.terrain.site.minute) + float(lab.terrain.site.phase)) * 60.0

func _run() -> void:
	create_timer(420.0).timeout.connect(func() -> void: quit(3))
	var args := OS.get_cmdline_user_args()
	if not check(args.has("--crowd") and args.has("--crowd-test"), "isolated crowd startup required"): return
	var pick := args.find("--sustain-case")
	if pick >= 0 and pick + 1 < args.size(): case_name = str(args[pick + 1])
	if not check(case_name in CASES, "a known sustain case is selected", case_name): return
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
	var owner: Variant = _owner(team_id)
	if not check(owner != null, "the friendly crowd owner exists"): return
	# Production opt-in: the same call begin_team_food makes when a player starts a delivery.
	var opted: Dictionary = controller._enable_team_supply(owner)
	if not check(not opted.is_empty(), "the crowd team opts into team supply through _enable_team_supply"): return
	# Re-read the live entry the controller stores. A fresh opt-in is version 2 (inventory may be missing) or version 3 (locations).
	var entry: Dictionary = controller._supply_entry(owner)
	var version := int(entry.get("version", 0))
	if not check(version == 2 or version == 3, "the opted-in supply entry is version 2 or 3", version): return
	if not check(version == 2 or not entry.get("locations", {}).is_empty(), "a version 3 supply entry has at least one location"): return
	# Known stock: every location of a version 3 entry, or the entry's own inventory of a version 2 entry (created when missing).
	var before_seed := _rations(team_id)
	var seeded := _seed_stock(entry)
	var expected_total := before_seed + float(KNOWN_GRAIN * seeded)
	if not check(absf(_rations(team_id) - expected_total) < 0.000001, "the known stock reads back through _supply_stock (%d holder(s))" % seeded,
		{"before": before_seed, "after": _rations(team_id), "expected": expected_total}): return
	match case_name:
		"peace":
			_clock_case(team_id, false)
		"combat":
			_clock_case(team_id, true)
		"saveload":
			_saveload_case(team_id)

func _owner(team_id: int) -> Variant:
	for owner: Variant in site.person_owners():
		if int(owner.team_id) == team_id: return owner
	return null

func _entry(team_id: int) -> Dictionary:
	return controller._supply_entry(_owner(team_id))

# The team's stock as the controller and Sustain read it: the locations of a version 3 entry, or the inventory of version 2.
func _stock_all(entry: Dictionary) -> Dictionary:
	return controller._supply_stock(entry)

# Seeds known grain into the LIVE entry (bracket keys) and returns how many stock holders it seeded: every location of a version 3
# entry, or the entry's own inventory of a version 2 entry. A missing version 2 inventory is created on the entry itself, so the
# write is not lost to a throwaway default dictionary in _supply_stock.
func _seed_stock(entry: Dictionary) -> int:
	if int(entry.get("version", 0)) == 3:
		var count := 0
		for key: String in entry.locations:
			entry.locations[key].inventory["grain"] = KNOWN_GRAIN
			count += 1
		return count
	if not entry.has("inventory") or not entry["inventory"] is Dictionary:
		entry["inventory"] = {}
	entry["inventory"]["grain"] = KNOWN_GRAIN
	return 1

# Total rations across all locations, the same reading Sustain.rations gives the meal rule.
func _rations(team_id: int) -> float:
	var entry := _entry(team_id)
	return Sustain.rations(entry.sustain, _stock_all(entry))

# Members exactly as advance_crowd_sustain builds them for this owner (read-only).
func _members(owner: Variant) -> Dictionary:
	var originals := {}
	for index: int in owner.records: originals[owner.combat_identity(index)] = owner.records[index]
	for index: int in owner.actors: originals[owner.combat_identity(index)] = controller._actor_supply_adapter(owner.actors[index])
	return controller.captivity_supply.team_members(owner, originals, controller.captivity_supply.feeding_index(), site._records)

func _clock_case(team_id: int, in_combat: bool) -> void:
	var owner: Variant = _owner(team_id)
	var at_before := float(_entry(team_id).sustain.at)
	var clock_before := _site_seconds()
	if not in_combat:
		# Force the first meal due inside the tick window: a probe-only fixture write, as site_supply_opt_in_test sets meal_until.
		for cohort: Dictionary in _entry(team_id).sustain.cohorts: cohort["meal_until"] = at_before + MEAL_SOON
	var rations_before := _rations(team_id)
	var grid_state: Dictionary = _entry(team_id).sustain.duplicate(true)
	var grid_stock: Dictionary = _stock_all(_entry(team_id)).duplicate(true)
	var members := _members(owner)
	var context := {"safe": false, "stopped": false}
	if int(_entry(team_id).get("version", 0)) == 3: context["food_locations"] = controller.ship_food_locations(owner, members)
	lab.terrain.site["combat_left"] = 30.0 if in_combat else 0.0
	if not _tick(TICKS): return
	lab.terrain.site["combat_left"] = 0.0
	var at_delta := float(_entry(team_id).sustain.at) - at_before
	var clock_delta := _site_seconds() - clock_before
	if not check(at_delta > 0.0, "the team's sustain clock advances under crowd (%s)" % case_name, {"at_delta": at_delta, "clock_delta": clock_delta}): return
	if not check(absf(at_delta - clock_delta) <= 1.0, "the team's sustain clock matches the Site clock (%s)" % case_name,
		{"at_delta": at_delta, "clock_delta": clock_delta, "minute": lab.terrain.site.minute, "phase": lab.terrain.site.phase}): return
	if not in_combat:
		# Grid amount: the same Sustain rules on duplicates of the pre-tick state, stock and members, run to the post-tick clock.
		var reference := Sustain.advance_to(grid_state, members.duplicate(true), grid_stock, float(_entry(team_id).sustain.at), context)
		var expected := float(reference.get("consumed_rations", -1.0))
		var dropped := rations_before - _rations(team_id)
		if not check(bool(reference.get("ok", false)) and expected > 0.0, "a due meal consumes rations under the grid rule (reference)", {"expected": expected, "reference": reference.get("message", "")}): return
		if not check(absf(dropped - expected) <= 0.000001, "the crowd team's stock drops by the grid amount for the meal",
			{"dropped": dropped, "expected": expected, "rations_before": rations_before, "rations_after": _rations(team_id)}): return
	print("SUSTAIN1 GATE OK: %s" % case_name)
	quit(0)

func _saveload_case(team_id: int) -> void:
	if not _tick(TICKS): return
	var at_before := float(_entry(team_id).sustain.at)
	var rations_before := _rations(team_id)
	var captured: Dictionary = controller._capture_for_save()
	if not check(bool(captured.get("ok", false)), "the save capture is valid after the sustain ticks", captured.get("code", "OK")): return
	var blob: PackedByteArray = site.crowd.save_state()
	if not check(site.crowd.load_state(blob), "the native state reloads"): return
	site.crowd.render_set_kits(site._kit_ids)
	site._rebuild_rider_ids()
	var save_path: String = controller.save_root.path_join(SAVE_NAME)
	var saved: Dictionary = controller.save_to(save_path)
	if not check(bool(saved.get("ok", false)), "the crowd save writes the team sustain: %s" % str(saved), saved): return
	var loaded: Dictionary = Store.load_site(save_path)
	if not check(bool(loaded.get("ok", false)), "the sustain save loads: %s" % str(loaded.get("message", "")), loaded): return
	var entry: Dictionary = loaded.data.site.get("team_supply", {}).get(str(team_id), {})
	if not check(not entry.is_empty(), "the saved team has a supply entry"): return
	var at_after := float(entry.sustain.at)
	var rations_after := Sustain.rations(entry.sustain, controller._supply_stock(entry))
	if not check(absf(at_after - at_before) < 0.000001, "the team's sustain clock survives save and load: %s / %s" % [at_before, at_after], {"at": at_after}): return
	if not check(absf(rations_after - rations_before) < 0.000001, "the team's stock survives save and load: %s / %s" % [rations_before, rations_after], {"rations": rations_after}): return
	print("SUSTAIN1 GATE OK: saveload sustain_at=%s" % str(at_before))
	quit(0)
