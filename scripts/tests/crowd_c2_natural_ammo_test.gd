extends SceneTree
## Formal original-item test. No event is injected or drained by this script.
## --ammo-capture-death selects a separate CAPTURED-pending -> real DEATH case.
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Sustain = preload("res://scripts/terrain_lab/site_sustain.gd")
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const DT := 1.0 / 30.0
var lab: TerrainLab
var controller: SiteController
var site: Node
var out_dir := ""
var failed := false
var capture_death := false
var checks: Array[Dictionary] = []
var samples: Array[Dictionary] = []
var events: Array[Dictionary] = []
var event_error := ""
var seen_dead := {}
var observed_steps := 0
var action_seconds := 0.0
var result := {}
var result_serial := 0
var result_dialog: AcceptDialog
var archer := -1
var guard := -1
var archer_index := -1
var guard_index := -1
var archer_team := {}
var guard_team := {}
var initial_items := 0
var original_holder := {}
var original_cargo := {}
var weapon_ids: Array = []
var sealed_id := ""
var conservation_steps := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, label: String, details: Variant = null) -> bool:
	checks.append({"ok": ok, "check": label, "details": details})
	print("NATURAL_AMMO ", "OK " if ok else "FAIL ", label, " ", str(details) if details != null else "")
	if not ok:
		failed = true
		_write()
		printerr("GATE FAIL: ", label)
		quit(2)
	return ok

func _write() -> void:
	if out_dir.is_empty(): return
	var file := FileAccess.open(out_dir.path_join("natural_ammo.json"), FileAccess.WRITE)
	if file == null: return
	file.store_string(JSON.stringify({"ok": not failed, "case": "capture_pending_then_death" if capture_death else "shots_ko_capture_escape_busy",
		"checks": checks, "events": events, "samples": samples, "conservation_steps": conservation_steps,
		"action_seconds": action_seconds, "archer": archer, "guard": guard,
		"setup": "Formal TerrainLab; one original bow row versus one original stronger melee row; original player is neutral to both factions. Original bow cargo and native ammo start at 12; conscious bow starts with stun 99 and long grace so an actual melee hit can cause KO. After exactly three native SHOT events, bow HOLD and enemy ATTACK; native AI auto-capture. Escape case shortens already-real KO wait after capture and disables guard using actual environment damage. No captive flag or event is authored. Pending-death case holds original delivery BUSY before actual native capture then applies actual environment death to the captive.",
		"not_covered": ["clear/redeploy requires the separate lifecycle test", "performance", "large battle acceptance"]}, "\t", true, true))
	file.close()

func _on_events(batch: PackedInt64Array) -> void:
	if batch.size() % 4 != 0:
		event_error = "native event batch is not a multiple of four"
		return
	var ids: PackedInt64Array = site.crowd.person_ids()
	for offset in range(0, batch.size(), 4):
		var kind := int(batch[offset])
		var person := int(batch[offset + 1])
		var other := int(batch[offset + 2])
		var formation := int(batch[offset + 3])
		var valid := kind >= 0 and kind <= 10 and formation >= 0 and formation < int(site.crowd.formation_count())
		if kind in [7, 8, 9]: valid = valid and person == -1
		else: valid = valid and ids.has(person)
		if kind in [1, 2, 5, 8, 9, 10]: valid = valid and other == -1
		elif kind in [3, 4, 7]: valid = valid and ids.has(other)
		else: valid = valid and (other == -1 or ids.has(other))
		if kind in [0, 1, 2, 4] and seen_dead.has(person): valid = false
		if kind == 0: seen_dead[person] = true
		if not valid: event_error = "invalid event or post-death event: %s" % str([kind, person, other, formation])
		events.append({"kind": kind, "person": person, "other": other, "formation": formation,
			"native_tick": int(site.crowd.stats()[36]), "game_seconds": Runtime.now(lab.terrain) * 60.0})

## Failure evidence only: each condition of CrowdPersonOwner.exchange_ready for the archer.
func _archer_ready_parts() -> Dictionary:
	var owner: Variant = site.person_owner(archer)
	var index := archer_index_in_owner()
	var source: Variant = owner._command_owner(index)
	var controller: SiteController = lab.site_controller
	return {"fire_host": site.fire_host_active(), "can_act": owner.combat_can_act(index), "moving": owner.person(index, false).get("moving", null),
		"stagger": owner.combat_hot_get(index, &"exchange_stagger", 0.0), "cooldown": owner.combat_hot_get(index, &"exchange_cooldown", 0.0),
		"ranged_cooldown": owner.combat_hot_get(index, &"ranged_cooldown", 0.0), "source": str(source), "source_exchange": source.exchange_enabled if source != null else null,
		"order": owner.combat_order, "routed": owner.is_sustain_routed(), "work_task": owner._cold_get(index, "work_task", {}),
		"busy": controller.person_actions.is_busy(archer), "guarding": controller.person_actions.is_guarding(archer), "assigned": controller.work_team.is_assigned(archer),
		"delivering": controller._is_delivering_person(archer), "operator": controller.vehicles.is_operator(archer),
		"fire_people": _archer_fire_facts()}

## Failure evidence only: the archer as the physical fire scheduler sees it (read-only original queries).
func _archer_fire_facts() -> Dictionary:
	var people: Array[Dictionary] = lab._siege_people()
	var found: Dictionary = {}
	var target: Dictionary = {}
	for person: Dictionary in people:
		if int(person.id) == archer: found = person
		if int(person.id) == guard: target = person
	if found.is_empty(): return {"in_people": false, "people": people.size()}
	var owner: Variant = found.owner
	var profile: Dictionary = owner.ranged_profile(int(found.unit), str(owner.ranged_ammo_mode))
	var cargo: Dictionary = owner.combat_hot_get(int(found.unit), &"cargo", {})
	var facts := {"in_people": true, "ready": lab._fire_person_ready(found), "profile": profile, "cargo": cargo,
		"defers": lab.site_controller._region_departure_defers_person(archer), "held_work": lab.site_controller.native_held_actual_work_person(archer),
		"query_phase": lab._exchange_phase, "cursor": lab.fire_action_cursor}
	if not target.is_empty():
		var from: Vector2i = lab._fire_attack_cell(found)
		var to: Vector2i = lab._fire_attack_cell(target)
		facts["cells"] = [from, to]
		facts["initiates"] = lab._exchange_initiates(found, guard)
		facts["line"] = lab._person_ranged_line_clear(archer, from, to)
		facts["melee_clear"] = lab._combat_melee_clear(archer, guard, from, to)
		facts["target_can_act"] = target.owner.combat_can_act(int(target.unit))
	return facts

## Failure evidence only: the archer's index inside its own person owner.
func archer_index_in_owner() -> int:
	return int(site.person_owner(archer).index_for_identity(archer))

func _count(kind: int, identity: int = -1) -> int:
	var total := 0
	for event: Dictionary in events:
		if int(event.kind) == kind and (identity == -1 or int(event.person) == identity): total += 1
	return total

func _capture_result(value: Dictionary) -> void:
	result = value.duplicate(true)
	result_serial += 1

func _position(index: int) -> Vector2:
	var hot: Dictionary = site.soldier_state(index)
	return Vector2(hot.px, hot.py)

func _person() -> Dictionary:
	return site.person_owner(archer).person(archer_index)

func _state_snapshot() -> Dictionary:
	var holders := {}
	for owner in site.person_owners():
		for index: int in owner.combat_units:
			var person: Dictionary = owner.person(index)
			holders[int(person.person_id)] = {"holder": person.holder.duplicate(true), "cargo": person.cargo.duplicate(true)}
	return {"site": lab.terrain.site.duplicate(true), "native": str(site.crowd.state_hash()), "holders": holders,
		"jobs": controller.person_actions._jobs.duplicate(true), "prepared": controller.captivity_supply._prepared.duplicate(true),
		"pending": site.pending_captivity.duplicate(true)}

func _blocked(label: String, action: Callable) -> bool:
	var before := _state_snapshot()
	var serial := result_serial
	var returned: Variant = action.call()
	var answer: Dictionary = returned if returned is Dictionary else result if result_serial > serial else {}
	var after := _state_snapshot()
	var difference := _first_difference(before, after)
	return _check(not bool(answer.get("ok", true)) and str(answer.get("code", "")) == "CROWD_ACTIVE" and str(answer.get("message", "")) == "CROWD_ACTIVE：群眾戰鬥中由戰場規則處理" and difference.is_empty(),
		label + " returns exact CROWD_ACTIVE without changing native, original items, supply, allocators or jobs", {"result": answer, "snapshot_difference": difference, "native_before": before.native, "native_after": after.native})

func _first_difference(a: Variant, b: Variant, path: String = "snapshot") -> String:
	if a is Dictionary and b is Dictionary:
		for key: Variant in a:
			if not b.has(key): return "%s.%s missing" % [path, str(key)]
			var nested := _first_difference(a[key], b[key], path + "." + str(key))
			if not nested.is_empty(): return nested
		for key: Variant in b:
			if not a.has(key): return "%s.%s added" % [path, str(key)]
		return ""
	if a is Array and b is Array:
		if a.size() != b.size(): return "%s size %d -> %d" % [path, a.size(), b.size()]
		for index in range(a.size()):
			var nested := _first_difference(a[index], b[index], path + "[%d]" % index)
			if not nested.is_empty(): return nested
		return ""
	return "" if a == b else "%s %s -> %s" % [path, str(a), str(b)]

func _conservation(label: String, record: bool = false) -> bool:
	var arrows := 0
	var containers: Array = []
	for identity: String in lab.terrain.site.ground_loot:
		var container: Dictionary = lab.terrain.site.ground_loot[identity]
		if int(container.original_owner) == archer and str(container.kind) == "sealed":
			arrows += int(container.cargo.get("arrow", 0))
			containers.append(identity)
	var cargo := int(original_cargo.get("arrow", 0))
	var shots := _count(10, archer)
	var data := {"label": label, "tick": int(site.crowd.stats()[36]), "action_seconds": action_seconds,
		"cargo": cargo, "sealed_arrows": arrows, "shots": shots, "containers": containers,
		"native_ammo": int(site.soldier_state(archer_index).ammo), "hot": site.soldier_state(archer_index),
		"pending": site.pending_captivity.duplicate(true), "event_error": event_error}
	conservation_steps += 1
	if record: samples.append(data)
	if not event_error.is_empty() or cargo + arrows + shots != 12 or shots > 3 or containers.size() > 1 or not is_same(_person().holder, original_holder) or not is_same(_person().cargo, original_cargo):
		return _check(false, "12 = original cargo + sealed arrows + real shots at every step", data)
	return true

func _advance(label: String) -> bool:
	lab._advance_action_time(DT)
	action_seconds += DT
	observed_steps += 1
	return _conservation(label, observed_steps % 30 == 0)

func _supply_members(team: Dictionary) -> Array:
	return Sustain._ids(lab.terrain.site.team_supply[str(team.team_id)].sustain)

func _unique_items(label: String) -> bool:
	var locations := {}
	var holders: Array = [lab.terrain.site.depot_items]
	for owner in site.person_owners():
		for index: int in owner.combat_units: holders.append(owner.person(index).holder)
	for holder: Dictionary in lab.terrain.site.ground_loot.values(): holders.append(holder)
	for holder: Dictionary in holders:
		for identity: String in holder.item_ids:
			if locations.has(identity): return _check(false, label + " item has two locations", identity)
			locations[identity] = holder.holder
			if lab.terrain.site.item_records[identity].holder != holder.holder: return _check(false, label + " original holder disagrees with item record", identity)
	return _check(locations.size() == initial_items and lab.terrain.site.item_records.size() == initial_items, label + " every original item has exactly one location", locations.size())

func _native_equipment_clear() -> bool:
	var packed: int = site._packed_equip(site._appearance(archer))
	var before: int = site.crowd.state_hash()
	var copy: RefCounted = ClassDB.instantiate("ArmyCrowd")
	copy.setup(1, 971)
	if not _check(copy.load_state(site.crowd.save_state()), "native equipment inspection clone loads actual live state"): return false
	var hash_before: int = copy.state_hash()
	var same: bool = copy.set_soldier_equip(archer_index, packed) and copy.state_hash() == hash_before
	return _check((packed & 255) == 0 and (packed & (1 << 24)) == 0 and same and site.crowd.state_hash() == before,
		"native weapon and shield already match original sealed removal; inspection never mutates live world")

func _initial_d4() -> bool:
	controller.person_executor_id = lab.controlled_person_id()
	controller.selected = Vector2i(_position(archer_index).floor())
	if not _check(controller._selected_people().has(archer), "original click selector resolves crowd roster person at native cell", controller._selected_people()): return false
	controller._open_person_inventory(false)
	var dialog: AcceptDialog = lab.find_child("PersonInventoryDialog", true, false)
	if not _check(dialog != null, "original inventory dialog opens for clicked crowd roster person"): return false
	var choice: OptionButton = dialog.find_child("LootSource", true, false)
	var selection := -1
	for index in range(choice.item_count):
		var source: Dictionary = choice.get_item_metadata(index)
		if source.kind == "person" and int(source.id) == archer: selection = index
	if not _check(selection >= 0, "original inventory choice references the existing archer"): return false
	choice.select(selection)
	choice.item_selected.emit(selection)
	for button_name: String in ["BeginLoot", "BeginCapture", "BeginUnbind"]:
		var button: Button = dialog.find_child(button_name, true, false)
		if not _check(button != null, "original action button exists " + button_name): return false
		if not _blocked("formal " + button_name, func() -> void: button.pressed.emit()): return false
	dialog.free()
	var appearance: Dictionary = controller.person_appearance(archer)
	if not _check(appearance == site._appearance(archer) and str(appearance.get("parts", {}).get("weapon", "none")) != "none", "formal equipment query reads the original crowd holder's actual bow", appearance.get("parts", {})): return false
	if not _blocked("formal equipment selection removal", func() -> void: controller._request_person_equipment("weapon", "none", archer)): return false
	var escape: Button = lab.find_child("BeginCaptiveEscape", true, false)
	if not _check(escape != null, "original captive escape button exists"): return false
	if not _blocked("formal controlled escape button", func() -> void: escape.pressed.emit()): return false
	for action: Dictionary in [
		{"label": "roster direct loot", "call": func() -> Dictionary: return controller.person_actions.begin_loot(guard, "person", str(archer), {}, [])},
		{"label": "roster direct capture", "call": func() -> Dictionary: return controller.person_actions.begin_capture(guard, archer, guard)},
		{"label": "roster direct unbind", "call": func() -> Dictionary: return controller.person_actions.begin_unbind(guard, archer)},
		{"label": "roster direct equipment", "call": func() -> Dictionary: return controller.person_actions.begin_equipment(archer, {"mode": "personal", "slot": "weapon", "item_id": ""})},
		{"label": "roster direct ransom", "call": func() -> Dictionary: return controller.person_actions.begin_ransom(archer, archer, guard)}]:
		if not _blocked(action.label, action["call"]): return false
	return true

func _captured_d4() -> bool:
	if not _blocked("actual captive escape action", func() -> Dictionary: return controller.person_actions.begin_escape(archer)): return false
	controller._open_ransom(archer)
	var dialog: AcceptDialog = lab.find_child("RansomDialog", true, false)
	if not _check(dialog != null, "original ransom dialog opens for actually captured archer"): return false
	var choice: OptionButton = dialog.find_child("RansomRepresentative", true, false)
	var selection := -1
	for index in range(1, choice.item_count):
		if int(choice.get_item_metadata(index)) == guard: selection = index
	if not _check(selection >= 0, "original ransom choices contain the actual native captor"): return false
	choice.select(selection)
	var button: Button = dialog.find_child("BeginRansom", true, false)
	if not _blocked("formal ransom delivery button", func() -> void: button.pressed.emit()): return false
	dialog.free()
	return true

func _find_corridor() -> Vector2i:
	var player := _position(site.player_index)
	for y in range(4, lab.terrain.size.y - 4):
		for x in range(4, lab.terrain.size.x - 10):
			var start := Vector2i(x, y)
			if player.distance_to(Vector2(start)) < 24.0: continue
			var legal := true
			for row in range(-1, 2):
				for offset in range(9):
					var here := start + Vector2i(offset, row)
					if not lab.terrain.is_walkable(here): legal = false
					if offset > 0 and not lab.terrain.can_step(here - Vector2i.RIGHT, here): legal = false
			if legal: return start
	return Vector2i(-1, -1)

func _place(identity: int, position: Vector2) -> bool:
	var owner: RefCounted = site.person_owner(identity)
	return site.set_soldier_fields(owner.index_for_identity(identity), {"px": position.x, "py": position.y}) and site.set_formation_fields(owner.formation_index,
		{"cx": position.x, "cy": position.y, "goal_x": position.x, "goal_y": position.y, "origin_x": position.x, "origin_y": position.y, "ref_x": position.x, "ref_y": position.y, "ref_valid": true, "ai_enabled": false})

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	capture_death = args.has("--ammo-capture-death")
	var stamp := Time.get_datetime_string_from_system().replace("-", "").replace(":", "").replace("T", "_")
	out_dir = "res://output/crowd_c2_c3_20261001/natural_ammo_%s_%s_%d" % ["death" if capture_death else "escape", stamp, Time.get_ticks_msec()]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var ignore := FileAccess.open(out_dir.path_join(".gdignore"), FileAccess.WRITE)
	if ignore != null: ignore.close()
	create_timer(180.0).timeout.connect(func() -> void:
		failed = true
		_write()
		printerr("GATE FAIL: natural ammo deadline 180 seconds")
		quit(3))
	if not _check(args.has("--crowd") and args.has("--crowd-test"), "named isolated crowd test mode required"): return
	lab = load("res://scenes/terrain_lab/TerrainLab.tscn").instantiate()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	current_scene = lab
	lab.set_process(false)
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	controller = lab.site_controller
	controller._auto_save_blocked = true
	lab.character.faction_id = 2 # Explicit neutral fixture observer, not a combat participant.
	site = lab.crowd_site
	result_dialog = AcceptDialog.new()
	controller._equipment_dialog = result_dialog
	controller._equipment_result = _capture_result
	var deployed: Dictionary = lab.deploy_trial_armies([
		{"faction": 0, "count": 1, "training": 0.0, "ai_enabled": false, "attack": false, "troop_type": "bow", "entry": "west"},
		{"faction": 1, "count": 1, "training": 100.0, "ai_enabled": false, "attack": false, "troop_type": "melee_infantry", "entry": "east"}])
	if not _check(deployed.ok and site.active and not controller.crowd_test_run_id.is_empty(), "formal original bow and melee deployment", deployed): return
	if not _check(site.has_signal("events_received"), "production observer exposes consumed native event batch without draining it"): return
	site.connect("events_received", _on_events)
	var teams: Array = site.command_teams()
	archer_team = site._team_by_id(int(teams[0].team_id))
	guard_team = site._team_by_id(int(teams[1].team_id))
	archer = int(archer_team.person_ids[0])
	guard = int(guard_team.person_ids[0])
	archer_index = int(site.crowd.soldier_index(archer))
	guard_index = int(site.crowd.soldier_index(guard))
	if not _check(site.crowd.set_hostile(0, 2, false) and site.crowd.set_hostile(1, 2, false), "original fixture observer is neutral to both test factions"): return
	var corridor := _find_corridor()
	if not _check(corridor.x >= 0 and _place(archer, Vector2(corridor) + Vector2.ONE * 0.5) and _place(guard, Vector2(corridor + Vector2i(6, 0)) + Vector2.ONE * 0.5), "author legal unobstructed six-cell ranged corridor", corridor): return
	original_holder = _person().holder
	original_cargo = _person().cargo
	original_cargo.arrow = 12
	if not _check(site.set_soldier_fields(archer_index, {"ammo": 12, "stun": 99.0, "grace": 120.0}) and float(site.soldier_state(archer_index).ko) == 0.0, "original archer starts conscious with exactly 12 real arrows and authored near-KO stun"): return
	for item: String in original_holder.item_ids:
		var definition: Dictionary = lab.terrain.site.item_definitions[lab.terrain.site.item_records[item].definition]
		if str(definition.slot) in ["weapon", "shield"]: weapon_ids.append(item)
	if not _check(not weapon_ids.is_empty(), "archer begins with an original real weapon to seal", weapon_ids): return
	initial_items = lab.terrain.site.item_records.size()
	for team: Dictionary in [archer_team, guard_team]:
		var enabled: Dictionary = controller.captivity_supply.enable_team(site.person_owner(int(team.person_ids[0])))
		if not _check(enabled.ok, "enable original team meal history", enabled.get("code", "OK")): return
		lab.terrain.site.team_supply[str(team.team_id)].inventory.grain = 1000
	if not _initial_d4(): return
	if not _unique_items("initial") or not _conservation("initial", true): return
	var attack: Dictionary = site.issue_order(int(archer_team.team_id), TerrainArmy.CombatOrder.ATTACK, Vector2i(-1, -1), guard, "test")
	if not _check(attack.ok, "original archer receives ATTACK against actual six-cell enemy", attack): return
	for tick in range(900):
		if not _advance("shooting"): return
		if _count(10, archer) == 3: break
		if tick % 30 == 0: await process_frame
	if not _check(_count(10, archer) == 3 and int(site.soldier_state(archer_index).ammo) == 9 and int(original_cargo.arrow) == 9 and _count(1, archer) == 0, "native releases exactly three real shots and synchronizes original cargo 12 to 9", {"shots": _count(10, archer), "cargo_arrow": original_cargo.arrow, "state": site.soldier_state(archer_index), "order": site.formation_state(int(archer_team.formation)),
		"scheduler": lab.fire_scheduler_result, "reservations": lab.fire_reservations.size(), "last_refusal": lab.get_meta(&"last_refused_result", {}), "step_fault": lab.site_controller._original_step_fault, "crowd_error": site.last_event_error, "action_seconds": action_seconds, "physical": lab.physical_ranged_enabled, "combat_left": lab.terrain.site.get("combat_left", 0.0),
		"ranged_enabled": site.person_owner(archer).ranged_enabled, "ranged_target": site.person_owner(archer).ranged_target, "exchange_ready": site.person_owner(archer).exchange_ready(archer_index_in_owner()), "ready_parts": _archer_ready_parts()}): return
	if not _check(float(lab.terrain.site.combat_left) > 0.0 or site.has_projectiles(),
		"three actual shots leave combat or projectiles busy before the clear-button check",
		{"combat_left": lab.terrain.site.combat_left, "projectiles": site.has_projectiles()}): return
	controller._open_combat_window()
	var clear_button: Button = controller.combat_window.find_child("ClearMeleeTrial", true, false)
	if not _check(clear_button != null, "original clear button exists"): return
	var before := _state_snapshot()
	var serial := result_serial
	clear_button.pressed.emit()
	var difference := _first_difference(before, _state_snapshot())
	if not _check(result_serial > serial and not bool(result.get("ok", true)) and str(result.get("code", "")) == "BUSY" and site.active and not controller.message.text.contains("已清除") and difference.is_empty(),
		"actual clear button preserves active original people and BUSY message without reporting false success", {"result": result, "visible_message": controller.message.text, "snapshot_difference": difference}): return
	controller.combat_window.hide()
	var held: Dictionary = site.issue_order(int(archer_team.team_id), TerrainArmy.CombatOrder.HOLD, Vector2i(-1, -1), -1, "test")
	var counter: Dictionary = site.issue_order(int(guard_team.team_id), TerrainArmy.CombatOrder.ATTACK, Vector2i(-1, -1), archer, "test")
	if not _check(held.ok and counter.ok, "bow ceases fire and stronger original enemy attacks through ordinary command owner"): return
	for tick in range(900):
		if not _advance("melee_ko"): return
		if _count(1, archer) > 0: break
		if tick % 30 == 0: await process_frame
	if not _check(_count(1, archer) == 1 and _count(10, archer) == 3 and float(site.soldier_state(archer_index).hp) > 0.0 and float(site.soldier_state(archer_index).ko) > 0.0, "actual native melee contact produces KO after the three shots", site.soldier_state(archer_index)): return
	var guard_hold: Dictionary = site.issue_order(int(guard_team.team_id), TerrainArmy.CombatOrder.HOLD, Vector2i(-1, -1), -1, "test")
	if not _check(guard_hold.ok and site.set_team_ai(int(guard_team.team_id), true).ok, "actual stronger enemy enters AI HOLD for native auto-capture"): return
	if capture_death: lab.terrain.site.team_supply[str(guard_team.team_id)].delivery = {"fixture": "hold native CAPTURED commit", "requester_id": -1, "player_id": -1, "representative_id": -1}
	for tick in range(900):
		if not _advance("native_capture"): return
		if _count(4, archer) > 0: break
		if tick % 30 == 0: await process_frame
	if not _check(_count(4, archer) == 1 and bool(site.soldier_state(archer_index).captive) and int(site.soldier_state(archer_index).captor_person) == guard, "native auto-capture emits CAPTURED naming the real guard", site.last_event_error): return
	if capture_death:
		if not await _pending_capture_death(): return
	else:
		if not await _captured_escape(): return
	if not _check(event_error.is_empty() and _count(10, archer) == 3 and _count(1, archer) == 1 and _count(4, archer) == 1, "all observed native fields and exact SHOT/KO/CAPTURED sequence pass", events): return
	var sequence: Array[int] = []
	for event: Dictionary in events:
		if int(event.person) != archer or not int(event.kind) in [0, 1, 4, 5, 10]: continue
		sequence.append(int(event.kind))
		if not _check(int(event.formation) == int(archer_team.formation) and (int(event.other) == guard if int(event.kind) in [0, 4] else int(event.other) == -1), "archer event uses exact original formation and other-person contract", event): return
	if not _check(sequence == [10, 10, 10, 1, 4, 0 if capture_death else 5], "exact native event order is three SHOTs then KO, CAPTURED and the selected terminal event", sequence): return
	if not _unique_items("final") or not _conservation("final", true): return
	if not _check(site.crowd.validate() and controller.person_actions._jobs.is_empty() and controller.captivity_supply._prepared.is_empty(), "native and original action transaction owners finish valid"): return
	_write()
	controller._equipment_dialog = null
	controller._equipment_result = Callable()
	result_dialog.free()
	lab.queue_free()
	await process_frame
	print("GATE OK: natural ammo conservation, original D4 routes and ", "CAPTURED before DEATH" if capture_death else "ESCAPED BUSY", " checks=", checks.size(), " steps=", conservation_steps)
	quit(0)

## Owner decision 2026-10-27 (custody atlas): a capture first prepares the captive's undressed atlas on the GPU (visual
## run); that preparation is presentation work, not simulation time. The relation then commits within three steps.
func _captive_atlas_preparing() -> bool:
	for job: Dictionary in site._captivity_atlas_jobs.values():
		if str(job.get("state", "")) == "preparing": return true
	return false

func _captured_escape() -> bool:
	var steps := 0
	var preparation_deadline := Time.get_ticks_msec() + 150000
	while not site.pending_captivity.is_empty() and steps < 3:
		if _captive_atlas_preparing():
			if Time.get_ticks_msec() > preparation_deadline: break
			await process_frame
			continue
		if not _advance("capture_commit"): return false
		if not _captive_atlas_preparing(): steps += 1
	var relation: Dictionary = lab.terrain.site.captivity.get(str(archer), {})
	if not _check(site.pending_captivity.is_empty() and not relation.is_empty() and int(relation.captor_id) == guard and int(relation.guard_id) == guard, "actual CAPTURED commits original relation in at most three steps", site.last_event_error): return false
	sealed_id = str(relation.sealed_container)
	var container: Dictionary = lab.terrain.site.ground_loot.get(sealed_id, {})
	if not _check(not container.is_empty() and int(container.cargo.get("arrow", 0)) == 9 and int(original_cargo.get("arrow", 0)) == 0 and int(site.soldier_state(archer_index).ammo) == 0 and container.item_ids == weapon_ids and not original_holder.equipped.has("weapon") and not original_holder.equipped.has("shield"), "capture seals the original nine arrows and real weapon exactly once", container): return false
	if not _check(archer in _supply_members(guard_team) and not archer in _supply_members(archer_team), "native capture transfers original meal cohort to actual captor"): return false
	if not _native_equipment_clear() or not _captured_d4() or not _conservation("captured", true): return false
	var guard_entry: Dictionary = lab.terrain.site.team_supply[str(guard_team.team_id)]
	guard_entry.delivery = {"fixture": "block only original ESCAPED supply commit", "requester_id": -1, "player_id": -1, "representative_id": -1}
	# This is an explicit bounded wake-time fixture; KO and CAPTURED already occurred naturally.
	if not _check(site.set_soldier_fields(archer_index, {"ko": 0.25}) and site.apply_environment_damage(guard, 10000.0) == 0.0 and _count(0, guard) == 1, "shorten actual captive KO and disable its only guard through real environment death"): return false
	var escape_boundary := {}
	for tick in range(1800):
		var prior_hot: Dictionary = site.soldier_state(archer_index)
		if not _advance("unguarded_escape"): return false
		var after: Dictionary = site.soldier_state(archer_index)
		if float(after.ko) > 0.0 or float(after.getup) > 0.0:
			if not bool(after.captive) or float(after.escape_t) != 0.0: return _check(false, "no escape countdown during KO or get-up", after)
		if _count(5, archer) > 0:
			escape_boundary = {"prior_escape_t": prior_hot.escape_t, "game_delta": float(site.crowd.stats()[34]), "after": after}
			break
		if tick % 30 == 0: await process_frame
	if not _check(_count(5, archer) == 1 and not bool(site.soldier_state(archer_index).captive) and not escape_boundary.is_empty() and float(escape_boundary.prior_escape_t) < 30.0 and float(escape_boundary.prior_escape_t) + float(escape_boundary.game_delta) >= 30.0 - 0.000001, "native ESCAPED occurs in the first qualified step crossing 30 game seconds", escape_boundary): return false
	if not _check(site.pending_captivity.size() == 1 and int(site.pending_captivity[0].kind) == 5 and str(site.last_event_error.get("code", "")) == "BUSY" and lab.terrain.site.captivity.get(str(archer), {}) == relation and controller.captivity_supply._prepared.is_empty(), "ESCAPED BUSY preserves original captivity until atomic supply commit", site.last_event_error): return false
	var before := _state_snapshot()
	site.settle_events()
	if not _check(_state_snapshot() == before and str(site.last_event_error.get("code", "")) == "BUSY", "repeated ESCAPED BUSY leaves original cold data, native hash and queue unchanged"): return false
	var save: Dictionary = controller.save_to(controller.save_path)
	if not _check(not save.ok and save.code == "BUSY", "actual pending escape refuses full Site save", save): return false
	guard_entry.delivery.clear()
	for tick in range(3):
		if not _advance("escape_retry"): return false
		if site.pending_captivity.is_empty(): break
	if not _check(site.pending_captivity.is_empty() and not lab.terrain.site.captivity.has(str(archer)) and archer in _supply_members(archer_team) and not archer in _supply_members(guard_team), "escape retry commits and returns original supply within three steps"): return false
	if not _check(lab.terrain.site.ground_loot[sealed_id] == container and int(site.soldier_state(archer_index).ammo) == 0 and int(original_cargo.get("arrow", 0)) == 0, "escape leaves original sealed equipment and nine arrows in place"): return false
	var synced: Dictionary = site.sync_to_site()
	if not _check(synced.ok, "post-escape original-state synchronization completes", synced): return false
	if not _native_equipment_clear() or not _conservation("escape_after_sync", true): return false
	var custody: Dictionary = Store._validate_captivity(lab.terrain, lab.terrain.site)
	return _check(custody.ok, "original captivity validator accepts completed natural escape", custody)

func _pending_capture_death() -> bool:
	if not _check(site.pending_captivity.size() == 1 and int(site.pending_captivity[0].kind) == 4 and str(site.last_event_error.get("code", "")) == "BUSY" and not lab.terrain.site.captivity.has(str(archer)) and int(original_cargo.get("arrow", 0)) == 9, "actual native CAPTURED waits on original supply with original items untouched", site.last_event_error): return false
	if not _check(site.apply_environment_damage(archer, 10000.0) == 0.0 and _count(0, archer) == 1 and controller._pending_deaths.has(archer), "actual captured person DEATH is queued after uncommitted CAPTURED"): return false
	for tick in range(120):
		if not _advance("capture_blocks_death"): return false
		if tick % 30 == 0: await process_frame
	if not _check(controller._pending_deaths.has(archer) and site.pending_captivity.size() == 1 and not bool(_person().body.loot_settled) and str(_person().body.remains_id).is_empty() and not lab.terrain.site.captivity.has(str(archer)) and int(original_cargo.get("arrow", 0)) == 9, "death settlement waits longer than down pose while capture remains BUSY"): return false
	var before := _state_snapshot()
	site.settle_events()
	if not _check(_state_snapshot() == before and controller.captivity_supply._prepared.is_empty(), "delayed dead-person capture retry is atomic while original supply remains BUSY"): return false
	lab.terrain.site.team_supply[str(guard_team.team_id)].delivery.clear()
	for tick in range(3):
		if not _advance("dead_capture_commit"): return false
		if site.pending_captivity.is_empty(): break
	if not _check(site.pending_captivity.is_empty() and lab.terrain.site.captivity.has(str(archer)) and controller._pending_deaths.has(archer), "capture commits before the already-queued death settles"): return false
	sealed_id = str(lab.terrain.site.captivity[str(archer)].sealed_container)
	if not _check(lab.terrain.site.ground_loot.has(sealed_id) and int(lab.terrain.site.ground_loot[sealed_id].cargo.get("arrow", 0)) == 9 and lab.terrain.site.ground_loot[sealed_id].item_ids == weapon_ids, "delayed capture seals original nine arrows and weapon once"): return false
	for tick in range(180):
		if not _advance("death_settlement"): return false
		if not controller._pending_deaths.has(archer): break
		if tick % 30 == 0: await process_frame
	var body: Dictionary = _person().body
	if not _check(not controller._pending_deaths.has(archer) and not lab.terrain.site.captivity.has(str(archer)) and bool(body.loot_settled) and not str(body.remains_id).is_empty() and str(body.remains_id) != sealed_id and lab.terrain.site.ground_loot.has(str(body.remains_id)), "original death settlement follows capture, removes custody and creates exactly one distinct remains holder", body.remains_id): return false
	var containers: Dictionary = lab.terrain.site.ground_loot.duplicate(true)
	controller.settle_person_deaths(10.0)
	if not _check(lab.terrain.site.ground_loot == containers and _count(0, archer) == 1 and _count(5, archer) == 0, "settled captured death cannot duplicate remains or later escape"): return false
	if not _native_equipment_clear(): return false
	var custody: Dictionary = Store._validate_captivity(lab.terrain, lab.terrain.site)
	return _check(custody.ok, "original custody validator accepts capture-before-death completion", custody)