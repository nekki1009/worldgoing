extends SceneTree
## EQCROWD: equipment orders for crowd people (owner decision 2026-10-31). Visual crowd battle with an atlas root.
## One case per run, picked with --equipment-case:
##   peaceful_equip_weapon   a spare weapon, ordered through the normal order flow (begin, live frames, commit), reaches the crowd kit
##   peaceful_mount_horse    a horse, ordered through the normal order flow, makes the soldier a native rider
##   combat_refused          combat_left > 0: CROWD_ACTIVE, and nothing changes
##   fighting_person_refused a person in an exchange timer: CROWD_ACTIVE, and nothing changes
##   saveload_after_change   a peaceful weapon change survives capture_for_save and a native save/load round trip
## Run: -- --crowd --crowd-test <fresh run_id> --equipment-case <case> --crowd-atlas-root res://output/site_siege_close_20261004/equipment_atlas_runtime
## Fails fast on the first failed check.
const DT := 1.0 / 30.0
const CASES := ["peaceful_equip_weapon", "peaceful_mount_horse", "combat_refused", "fighting_person_refused", "saveload_after_change"]
const SPARE_WEAPON := "longsword_01"
var lab: TerrainLab
var controller: SiteController
var site: Node
var case_name := "peaceful_equip_weapon"

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String, details: Variant = null) -> bool:
	print("EQCROWD ", "OK " if ok else "FAIL ", label, " ", str(details) if details != null else "")
	if not ok:
		printerr("GATE FAIL: ", label)
		quit(2)
	return ok

# One real frame of the live game step, as in site_cavalry_crowd_test.gd. The lab step itself settles job results
# into controller.show_result, so the last shown message is the order's outcome.
func _tick(count: int) -> bool:
	for step in range(count):
		lab._process(DT)
		controller.person_actions.settle_after_contacts()
		if not controller._original_step_fault.is_empty():
			printerr("EQCROWD latched frame fault: ", controller._original_step_fault)
			return false
	return true

func _run() -> void:
	create_timer(300.0).timeout.connect(func() -> void: quit(3))
	var args := OS.get_cmdline_user_args()
	if not check(args.has("--crowd") and args.has("--crowd-test"), "isolated crowd startup required"): return
	var pick := args.find("--equipment-case")
	if pick >= 0 and pick + 1 < args.size(): case_name = str(args[pick + 1])
	if not check(case_name in CASES, "a known equipment case is selected", case_name): return
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
	var soldier_id := int(friend_team.person_ids[1])
	if not check(not site._actors.has(soldier_id), "the chosen soldier is an ordinary crowd person", soldier_id): return
	var index := int(site._index_by_id[soldier_id])
	match case_name:
		"peaceful_equip_weapon":
			_equip_weapon_case(soldier_id, index)
		"peaceful_mount_horse":
			_mount_horse_case(soldier_id, index)
		"combat_refused":
			_combat_refused_case(soldier_id, index)
		"fighting_person_refused":
			_fighting_refused_case(soldier_id, index)
		"saveload_after_change":
			_saveload_case(soldier_id, index)

# Spare weapon held by the soldier's own goods (not worn), created the way the equipment tests create items.
func _spare_weapon(soldier_id: int) -> String:
	var record: Dictionary = site._records[soldier_id]
	var definition := {"slot": "weapon", "asset": SPARE_WEAPON, "tint": [1.0, 1.0, 1.0, 1.0]}
	var created: Dictionary = SiteRuntime.create_equipment(lab.terrain, record.item_state, "weapon:" + SPARE_WEAPON, definition, soldier_id, "")
	check(bool(created.get("ok", false)), "the spare weapon item is created", created)
	return str(created.get("item_id", ""))

# The normal order flow: the soldier is the controlled person for a personal order, begin runs the guard and prepare,
# then live frames run until the timed job has committed. Control is restored afterwards.
func _order_personal(soldier_id: int, slot: String, item_id: String) -> Dictionary:
	# The deployed team marches in from its edge; equipment needs a stopped person (SitePersonActions._ready).
	var stopped := false
	for step in range(900):
		if not _tick(1): return {"ok": false, "code": "FAULT", "finished": false, "begun": {}, "outcome": "latched fault"}
		var person: Dictionary = controller.person_actions._person(soldier_id, false)
		if not person.is_empty() and not bool(person.get("moving", false)):
			stopped = true
			break
	if not stopped: return {"ok": false, "code": "NOT_STILL", "finished": false, "begun": {}, "outcome": "the soldier never stopped"}
	var previous_control := lab.controlled_person_id()
	lab.terrain.site["controlled_person_id"] = soldier_id
	var begun: Dictionary = controller.equipment_orders.begin_personal(soldier_id, slot, item_id)
	var finished := false
	if bool(begun.get("ok", false)):
		for step in range(300):
			if not _tick(1): return {"ok": false, "code": "FAULT", "finished": false, "begun": begun}
			if not controller.person_actions.is_busy(soldier_id):
				finished = true
				break
	lab.terrain.site["controlled_person_id"] = previous_control
	return {"ok": bool(begun.get("ok", false)) and finished, "begun": begun, "finished": finished, "outcome": controller.message.text}

func _kit_matches(soldier_id: int, index: int) -> bool:
	var appearance: Dictionary = site._appearance(soldier_id)
	var kit := int(site._kit_cache.get(JSON.stringify(appearance), -1))
	return kit >= 0 and int(site._kit_ids[index]) == kit

func _equip_weapon_case(soldier_id: int, index: int) -> void:
	var item_id := _spare_weapon(soldier_id)
	var record: Dictionary = site._records[soldier_id]
	var before_weapon := str(record.item_state.equipped.get("weapon", ""))
	if not check(not item_id.is_empty() and before_weapon != item_id, "the soldier holds a different spare weapon", [before_weapon, item_id]): return
	var order := _order_personal(soldier_id, "weapon", item_id)
	if not check(bool(order.begun.get("ok", false)), "the peaceful weapon order begins", order.begun): return
	if not check(bool(order.finished), "the weapon order commits within its five seconds", order.outcome): return
	if not check(str(record.item_state.equipped.get("weapon", "")) == item_id, "the spare weapon is worn after the commit", [record.item_state.equipped, order.outcome]): return
	var appearance: Dictionary = site._appearance(soldier_id)
	if not check(str(appearance.parts.get("weapon", "")) == SPARE_WEAPON, "the crowd appearance shows the new weapon", appearance.parts): return
	if not check(_kit_matches(soldier_id, index), "the soldier's crowd kit follows the new weapon"): return
	if not check(_tick(30), "live frames after the weapon change have no latched fault"): return
	print("EQCROWD GATE OK: peaceful_equip_weapon")
	quit(0)

func _mount_horse_case(soldier_id: int, index: int) -> void:
	var record: Dictionary = site._records[soldier_id]
	if not record.get("cargo") is Dictionary: record["cargo"] = {}
	record.cargo["horse"] = int(record.cargo.get("horse", 0)) + 1
	var horses_before := int(record.cargo.horse)
	var order := _order_personal(soldier_id, SiteRuntime.MOUNT_SLOT, SiteRuntime.MOUNT_GOODS)
	if not check(bool(order.begun.get("ok", false)), "the peaceful horse order begins", order.begun): return
	if not check(bool(order.finished), "the horse order commits within its five seconds", order.begun): return
	var item_id := SiteRuntime.mount_item_id(record.item_state)
	if not check(not item_id.is_empty() and lab.terrain.site.item_records.has(item_id), "the mount slot holds a real horse item", [record.item_state, order.outcome]): return
	if not check(int(record.cargo.get("horse", 0)) == horses_before - 1, "exactly one horse left the soldier's goods", record.cargo): return
	if not check(site.crowd.soldier_mounted(index) and site.rider_identities().has(soldier_id), "the native rider flag and rider list follow the mount slot"): return
	var appearance: Dictionary = site._appearance(soldier_id)
	if not check(bool(appearance.get("mounted", false)) and _kit_matches(soldier_id, index), "the mounted crowd kit follows the horse"): return
	if not check(_tick(30), "live frames with the new rider have no latched fault"): return
	if not check(site.crowd.soldier_mounted(index), "the new rider stays mounted"): return
	print("EQCROWD GATE OK: peaceful_mount_horse")
	quit(0)

func _combat_refused_case(soldier_id: int, index: int) -> void:
	var item_id := _spare_weapon(soldier_id)
	var record: Dictionary = site._records[soldier_id]
	var before_equipped: Dictionary = record.item_state.equipped.duplicate(true)
	var before_version := int(record.item_state.version)
	lab.terrain.site["combat_left"] = 30.0
	var refused: Dictionary = controller.equipment_orders.begin_personal(soldier_id, "weapon", item_id)
	var mount_refused: Dictionary = controller.equipment_orders.begin_personal(soldier_id, SiteRuntime.MOUNT_SLOT, SiteRuntime.MOUNT_GOODS)
	lab.terrain.site["combat_left"] = 0.0
	if not check(str(refused.get("code", "")) == "CROWD_ACTIVE" and str(mount_refused.get("code", "")) == "CROWD_ACTIVE", "equipment orders are refused in combat with CROWD_ACTIVE", [refused, mount_refused]): return
	if not check(not controller.person_actions.is_busy(soldier_id), "no equipment job starts in combat"): return
	if not check(record.item_state.equipped == before_equipped and int(record.item_state.version) == before_version, "the worn equipment is unchanged in combat", record.item_state.equipped): return
	if not check(not site.crowd.soldier_mounted(index), "the soldier is not mounted by a refused order"): return
	print("EQCROWD GATE OK: combat_refused")
	quit(0)

func _fighting_refused_case(soldier_id: int, index: int) -> void:
	var item_id := _spare_weapon(soldier_id)
	var record: Dictionary = site._records[soldier_id]
	var before_equipped: Dictionary = record.item_state.equipped.duplicate(true)
	if not check(not site.person_fighting(soldier_id), "a soldier in peace is not fighting"): return
	if not check(bool(site.set_soldier_fields(index, {"stagger": 0.5})), "an exchange stagger is set on the soldier"): return
	if not check(site.person_fighting(soldier_id), "the staggered soldier counts as fighting"): return
	var refused: Dictionary = controller.equipment_orders.begin_personal(soldier_id, "weapon", item_id)
	if not check(str(refused.get("code", "")) == "CROWD_ACTIVE", "a fighting person's equipment order is refused with CROWD_ACTIVE", refused): return
	if not check(not controller.person_actions.is_busy(soldier_id) and record.item_state.equipped == before_equipped, "nothing changes for the fighting person"): return
	print("EQCROWD GATE OK: fighting_person_refused")
	quit(0)

func _saveload_case(soldier_id: int, index: int) -> void:
	var item_id := _spare_weapon(soldier_id)
	var order := _order_personal(soldier_id, "weapon", item_id)
	if not check(bool(order.finished) and bool(order.begun.get("ok", false)), "the peaceful weapon order commits before the save", order.begun): return
	if not check(_tick(30), "live frames before the save have no latched fault"): return
	var captured: Dictionary = controller._capture_for_save()
	if not check(bool(captured.get("ok", false)), "the save capture is valid after the weapon change", captured.get("code", "OK")): return
	var blob: PackedByteArray = site.crowd.save_state()
	if not check(site.crowd.load_state(blob), "the native state reloads"): return
	site.crowd.render_set_kits(site._kit_ids)
	site._rebuild_rider_ids()
	var record: Dictionary = site._records[soldier_id]
	if not check(str(record.item_state.equipped.get("weapon", "")) == item_id, "the worn weapon survives the save", record.item_state.equipped): return
	if not check(_kit_matches(soldier_id, index), "the reloaded crowd kit follows the weapon"): return
	if not check(_tick(1), "the frame after the reload has no latched fault"): return
	print("EQCROWD GATE OK: saveload_after_change")
	quit(0)
