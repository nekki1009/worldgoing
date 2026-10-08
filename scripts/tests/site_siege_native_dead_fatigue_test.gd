extends "res://scripts/tests/site_siege_native_integration_test.gd"
## Output candidate. Requires the paired native death-event/Source owner patch.
## Uses the original formal fixture, World contact APIs, Store, C2 and D5 entry.
var _dead_specs: Array[Dictionary] = []
var _completed_phases: Array[String] = []

func _run() -> void:
	case_name = "dead_fatigue"
	if output_root == "res://output/site_siege_close_20261004/native_integration":
		output_root = "res://output/site_siege_close_20261004/native_dead_fatigue"
	create_timer(180.0).timeout.connect(func() -> void:
		failed = true; _write_result(); printerr("NATIVE DEAD FATIGUE FAIL: deadline"); quit(3))
	if not _preflight(): return
	if not _check(ClassDB.class_has_method(&"ArmyCrowd", &"peek_events")
		and ClassDB.class_has_method(&"ArmyCrowd", &"event_fatigue"), "new paired event read ABI is actually installed"): return
	var context: Dictionary = _make_context("ballista", 2, true, "stone", true)
	if failed: return
	var host: Node = lab.crowd_site
	var native: Variant = host.crowd
	if not _check(host.active, "original formal CrowdSite owns the real Native World", {
		"dll_sha256": FileAccess.get_sha256(host.DLL_PATH), "build_id": str(native.build_id()),
		"test_sha256": FileAccess.get_sha256("res://scripts/tests/site_siege_native_dead_fatigue_test.gd"),
		"parent_sha256": FileAccess.get_sha256("res://scripts/tests/site_siege_native_integration_test.gd")}): return
	var actor_id: int = int(lab.character.person_id)
	var actor_original: TerrainTestCharacter = lab.character
	var controlled: Dictionary = lab.site_controller._control_family_person(null, int(context.commander))
	if not _check(controlled.ok and lab.controlled_person_id() == int(context.commander)
		and is_same(lab.character, actor_original), "same original living commander receives public control before original Actor death", controlled): return
	if not await _until(func() -> bool: return lab.site_controller.vehicles.crew_ready(_vehicle(context)),
		40.0, "original crew reaches its real stations before fatigue fixture begins"): return
	if not await _settled_native_crew(context, "original Native crew really settles before contact fixture"): return
	if not await _until(func() -> bool: return float(lab.terrain.site.combat_left) <= 0.0 and lab.site_controller._pending_deaths.is_empty(),
		20.0, "true original cooldown leaves only the pending-event guard to test", false): return
	if not _check(host.save_guard().ok and lab.site_controller.person_actions.save_guard().ok
		and float(lab.terrain.site.combat_left) == 0.0 and lab.site_controller._pending_deaths.is_empty(),
		"original clear has no pre-existing clock/action/death blocker before fatal packet fixture"): return
	# Fixture values enter the existing Native formation owner before any contact.
	# The saved cold values still differ, so reading stale cold data cannot pass.
	var row_id: int = int(context.victim)
	for entry: Dictionary in [{"id": row_id, "fatigue": 51.25, "rest": 7.5, "hit": 8, "stun": 35.0, "actor": false},
			{"id": actor_id, "fatigue": 25.75, "rest": 6.25, "hit": 10, "stun": 0.0, "actor": true}]:
		var person: Dictionary = lab.site_controller.person_actions._person(int(entry.id), false)
		if not _check(not person.is_empty() and float(person.hp) > 0.0 and person.owner is CrowdOwner,
			"same original live person enters the nonzero formation fixture", entry): return
		var formation: int = int(person.owner.formation_index)
		var seeded: bool = bool(host.set_formation_fields(formation, {"fatigue": entry.fatigue, "fatigue_rest": entry.rest}))
		var state: Dictionary = host.formation_state(formation)
		entry.index = int(person.unit); entry.formation = formation; entry.count = int(state.fatigue_count)
		entry.body = person.body; entry.holder = person.holder; entry.cargo = person.cargo
		if not _check(seeded and entry.count > 0 and _near(float(state.fatigue), float(entry.fatigue))
			and _near(float(state.fatigue_rest), float(entry.rest))
			and _near(float(person.owner.combat_hot_get(int(person.unit), &"fatigue")), float(entry.fatigue))
			and _near(float(person.owner.combat_hot_get(int(person.unit), &"fatigue_rest")), float(entry.rest)),
			"actual live formation and hot getters hold exact nonzero input before fatal contact", {"id": entry.id, "formation": state}): return
		_dead_specs.append(entry)
	var aliases: Dictionary = _current_aliases()
	if failed: return
	var events_before: int = int(host.event_counts.get(0, 0))
	var row: Dictionary = _dead_specs[0]
	var actor: Dictionary = _dead_specs[1]
	# Both are original public native contact paths. No HP, pose, fatigue or
	# clock setter is used after the fatal contact; ordinary environmental and
	# siege damage both go through World::apply_contact and its actual DEATH.
	var actor_hp: float = float(host.soldier_state(int(actor.index)).hp)
	var row_hp: float = float(host.soldier_state(int(row.index)).hp)
	if not _check(bool(native.apply_environment_damage(int(actor.index), actor_hp)), "real ordinary environmental contact kills original Actor through the original World"): return
	if not _check(bool(native.apply_siege_contact(int(row.index), row_hp, 35.0, 0.0)), "real siege contact kills the original row through the same World death owner"): return
	var hash_before: int = int(native.state_hash())
	var blob_before: PackedByteArray = native.save_state()
	var clock_before: Array = [float(lab.terrain.site.combat_left), float(native.combat_mark())]
	# The unchanged raw blob/hash include Native action time/game_dt/combat_left.
	# No unsupported time getter or mutating diagnostic stats() call is used.
	var packet: PackedInt64Array = native.peek_events()
	var values: PackedFloat64Array = native.event_fatigue()
	if not _check(packet.size() % 4 == 0 and values.size() == (packet.size() >> 1), "actual paired getters preserve original stride4 and two-double order", {"events": Array(packet), "fatigue": Array(values)}): return
	var seen := {}
	for offset in range(0, packet.size(), 4):
		if int(packet[offset]) != 0: continue
		var identity: int = int(packet[offset + 1])
		if not _check(not seen.has(identity), "each original fatal person has exactly one real queued death", identity): return
		seen[identity] = true
		var specification: Dictionary = row if identity == int(row.id) else (actor if identity == int(actor.id) else {})
		if not _check(not specification.is_empty(), "death packet only contains the two real tested identities", identity): return
		if not _check(int(packet[offset + 3]) == int(specification.formation)
			and _near(values[offset >> 1], float(specification.fatigue))
			and _near(values[(offset >> 1) + 1], float(specification.rest)),
			"death event retains its actual formation value at the original contact instant", {"id": identity, "fatigue": values[offset >> 1], "rest": values[(offset >> 1) + 1]}): return
	if not _check(seen.size() == 2 and seen.has(actor_id) and seen.has(row_id)
		and native.peek_events() == packet and native.event_fatigue() == values
		and int(native.state_hash()) == hash_before and native.save_state() == blob_before
		and [float(lab.terrain.site.combat_left), float(native.combat_mark())] == clock_before,
		"paired reads never drain or change true World blob/hash/clock", {"seen": seen, "hash": hash_before}): return
	# C2 admission must not commit a still-pending original event to cold rows.
	var before_clear: Dictionary = _canonical()
	var rejected: Dictionary = host.clear()
	if not _check(rejected == SiteRuntime.fail("BUSY", "收兵須等原生人物事件交接完成") and native.peek_events() == packet
		and native.event_fatigue() == values and native.save_state() == blob_before and int(native.state_hash()) == hash_before
		and _same_gameplay(before_clear, _canonical()),
		"original clear rejects pending events without consuming the true native queue", rejected): return
	if not _check(bool(host._consume_events()), "complete true packets commit through original CrowdSite once", host.last_event_error): return
	if not _check(int(host.event_counts.get(0, 0)) == events_before + 2 and native.peek_events().is_empty()
		and native.event_fatigue().is_empty(), "two original deaths notify once and consume exactly the same real queue"): return
	for spec: Dictionary in _dead_specs:
		var formation: Dictionary = host.formation_state(int(spec.formation))
		if not _check(int(formation.fatigue_count) == int(spec.count) - 1,
			"fatal contact decrements only its original formation count once", {"id": spec.id, "formation": formation}): return
	if not _assert_dead_fields(false, "death-instant original personal fields"): return
	if not _check_aliases(aliases, true, "death commit keeps original bodies/holders/cargo"): return
	_completed_phases.append("death_instant")
	# Test the original host clock entry explicitly; these are legal inputs to
	# CrowdSite.step, not clock setters or a substitute SceneTree simulation.
	if not _check(bool(host.step(DT, 0.0, float(lab.terrain.site.combat_left))), "original Native action slice accepts zero game seconds", host.last_event_error): return
	action_seconds += DT
	if not _assert_dead_fields(false, "zero-game slice preserves death-instant personal rest"): return
	if not _check_aliases(aliases, true, "zero-game slice preserves original source aliases"): return
	_completed_phases.append("zero_game_slice")
	if not _check(bool(host.step(DT, DT, float(lab.terrain.site.combat_left))), "original Native action slice accepts positive game seconds", host.last_event_error): return
	action_seconds += DT
	if not _assert_dead_fields(true, "positive-game slice uses original unsafe-rest formula"): return
	if not _check_aliases(aliases, true, "positive-game slice preserves original source aliases"): return
	_completed_phases.append("positive_game_slice")
	if not _check(host.sync_to_site().ok, "original snapshot writer syncs dead personal fields without live formation replacement"): return
	if not _assert_dead_fields(true, "original actor/row snapshot writers preserve exact personal fields"): return
	if not await _until(func() -> bool: return float(lab.terrain.site.combat_left) <= 0.0 and lab.site_controller._pending_deaths.is_empty(),
		20.0, "original cooldown and both true death/loot settlements complete", false): return
	if not _assert_dead_fields(true, "dead fatigue does not recover during later peaceful team rest"): return
	if not _persistence_chain(context): return
	if not _d5_reentry(): return
	if not _check(_completed_phases == ["death_instant", "zero_game_slice", "positive_game_slice", "native_reload", "c2", "gd_reload", "d5_reentry"]
		and checks >= 60 and _dead_specs.size() == 2,
		"every required exact-value/owner/persistence phase completed before PASS", _completed_phases): return
	_write_result()
	await _close_lab()
	TerrainArmy.release_contact_source()
	print("SITE_SIEGE_NATIVE_DEAD_FATIGUE_PASS: row + Actor, real ordinary/siege deaths, zero/positive game slices, original Store/Native/C2/GD/D5 chain; ", checks, " checks")
	quit(0)

func _near(first: float, second: float) -> bool:
	return absf(first - second) <= EPS

func _current_aliases() -> Dictionary:
	var aliases := {}
	for identity: Variant in _canonical().people:
		var id: int = int(identity)
		var person: Dictionary = lab.site_controller.person_actions._person(id, false)
		if not _check(not person.is_empty(), "every canonical original ID resolves at alias boundary", id): return {}
		aliases[id] = {"body": person.body, "holder": person.holder, "cargo": person.cargo}
	return aliases

func _check_aliases(aliases: Dictionary, include_body: bool, label: String) -> bool:
	for identity: int in aliases:
		var person: Dictionary = lab.site_controller.person_actions._person(identity, false)
		if not _check(not person.is_empty() and is_same(person.holder, aliases[identity].holder)
			and is_same(person.cargo, aliases[identity].cargo) and (not include_body or is_same(person.body, aliases[identity].body)), label, identity): return false
	return true

func _assert_dead_fields(rest_reset: bool, label: String) -> bool:
	var native_active: bool = lab.crowd_site != null and lab.crowd_site.active
	for spec: Dictionary in _dead_specs:
		var person: Dictionary = lab.site_controller.person_actions._person(int(spec.id), false)
		if not _check(not person.is_empty(), label + ": exact original identity still resolves", spec.id): return false
		var value: float = float(person.owner.combat_hot_get(int(person.unit), &"fatigue", 0.0)) if int(person.unit) >= 0 else PersonFatigue.read(person.body)
		var rested: float = float(person.owner.combat_hot_get(int(person.unit), &"fatigue_rest", 0.0)) if int(person.unit) >= 0 else PersonFatigue.read(person.body, "fatigue_rest")
		var stun: float = float(person.owner.combat_hot_get(int(person.unit), &"stun", 0.0)) if int(person.unit) >= 0 else float(person.body.stun)
		var expected_rest: float = 0.0 if rest_reset else float(spec.rest)
		if not _check(float(person.hp) == 0.0 and float(person.ko) == 0.0 and int(person.hit) == int(spec.hit)
			and _near(stun, float(spec.stun)) and _near(value, float(spec.fatigue)) and _near(rested, expected_rest)
			and PersonFatigue.pool(person.body).is_empty()
			and _near(PersonFatigue.read(person.body), float(spec.fatigue))
			and _near(PersonFatigue.read(person.body, "fatigue_rest"), expected_rest), label + ": actual HP/KO/stun/hit/fatigue/rest and unbound original body remain exact",
			{"id": spec.id, "hp": person.hp, "ko": person.ko, "stun": stun, "hit": person.hit, "fatigue": value, "rest": rested, "native": native_active}): return false
		if native_active:
			var materialized: Dictionary = person.owner.combat_hot_materialize(int(person.unit))
			if not _check(_near(float(materialized.fatigue), float(spec.fatigue)) and _near(float(materialized.fatigue_rest), expected_rest),
				label + ": original hot materialize also reads dead personal values", spec.id): return false
	return true

func _persistence_chain(context: Dictionary) -> bool:
	var before: Dictionary = _canonical()
	var saved: Dictionary = lab.site_controller.save_to(lab.site_controller.save_path)
	if not _check(saved.ok, "real original Controller/Store saves both dead personal rows", saved): return false
	var loaded: Dictionary = lab.site_controller.load_from(lab.site_controller.save_path)
	var after: Dictionary = _canonical()
	if not _check(loaded.ok and lab.crowd_site.active and _same_gameplay(before, after)
		and lab.crowd_site.crowd.peek_events().is_empty() and lab.crowd_site.crowd.event_fatigue().is_empty(),
		"real Native reload with no new death event preserves full original canonical state", {"load": loaded.get("code", ""), "difference": _first_gameplay_difference(before, after)}): return false
	if not _assert_dead_fields(true, "loaded HP0 uses persisted personal values without an event"): return false
	_completed_phases.append("native_reload")
	var aliases: Dictionary = _current_aliases()
	if failed: return false
	before = _canonical()
	var cleared: Dictionary = lab.crowd_site.clear()
	after = _canonical()
	if not _check(cleared.ok and not lab.crowd_site.active and _same_gameplay(before, after),
		"real C2 keeps every canonical field of both corpses and all original live people/assets", {"clear": cleared, "difference": _first_gameplay_difference(before, after)}): return false
	if not _check_aliases(aliases, false, "C2 keeps original holders and cargo references"): return false
	if not _assert_dead_fields(true, "C2 Actor/row exports preserve exact dead fields"): return false
	_completed_phases.append("c2")
	var gd_saved: Dictionary = lab.site_controller.save_to(lab.site_controller.save_path)
	if not _check(gd_saved.ok, "returned original GD owners save through the same full Store", gd_saved): return false
	var gd_loaded: Dictionary = lab.site_controller.load_from(lab.site_controller.save_path)
	after = _canonical()
	if not _check(gd_loaded.ok and not lab.crowd_site.active and _same_gameplay(before, after),
		"true GD reload preserves complete canonical fields including dead personal fatigue", {"load": gd_loaded.get("code", ""), "difference": _first_gameplay_difference(before, after)}): return false
	if not _assert_dead_fields(true, "ordinary Store reload retains both original corpse values"): return false
	if not _check(_vehicle(context).crew_slots.size() == int(context.count), "same original live crew occupation survives both stores", _vehicle(context).crew_slots): return false
	_completed_phases.append("gd_reload")
	return true

func _d5_reentry() -> bool:
	var before: Dictionary = _canonical()
	var aliases: Dictionary = _current_aliases()
	if failed: return false
	# The original public deploy requires at least one new trial team. Account
	# for that lawful allocator addition explicitly; no existing person is recreated.
	var side: Dictionary = _side(1, 2)
	var formation: Array[Vector2i] = [Vector2i(70, 66)]
	var entered: Dictionary = lab.crowd_site.deploy([side], [formation])
	var after: Dictionary = _canonical()
	if not _check(entered.ok and lab.crowd_site.active, "original public D5 reentry imports the same GD corpses and existing armies", entered): return false
	var additions: Array = []
	for identity: Variant in after.people:
		if not before.people.has(identity): additions.append(identity)
	if not _check(after.people.size() == before.people.size() + 1 and additions.size() == 1,
		"public deployment adds exactly one separately accounted original allocator person", additions): return false
	for identity: Variant in before.people:
		if not _check(after.people.has(identity) and _same_gameplay(before.people[identity], after.people[identity]),
			"D5 preserves every full canonical field of each existing real person", {"id": identity, "difference": _first_gameplay_difference(before.people[identity], after.people.get(identity, {}))}): return false
	for field: String in ["vehicles", "parts", "ground_loot", "depot_items", "inventory"]:
		if not _check(_same_gameplay(before[field], after[field]), "D5 keeps complete original " + field,
			_first_gameplay_difference(before[field], after[field], field)): return false
	for field: String in ["item_records", "item_definitions"]:
		for identity: Variant in before[field]:
			if not _check(after[field].has(identity) and _same_gameplay(before[field][identity], after[field][identity]),
				"D5 retains every existing original " + field + " ID/value", identity): return false
	var newcomer: Dictionary = after.people[additions[0]]
	var lawful_items: Array = newcomer.holder.item_ids
	for identity: Variant in after.item_records:
		if not before.item_records.has(identity) and not _check(lawful_items.has(identity),
			"any newly seeded item belongs only to the one publicly deployed new person", identity): return false
	if not _check_aliases(aliases, false, "D5 keeps every existing original holder/cargo alias"): return false
	if not _assert_dead_fields(true, "D5 HP0 import with no death event still preserves personal fields"): return false
	if not _check(lab.crowd_site.crowd.peek_events().is_empty() and lab.crowd_site.crowd.event_fatigue().is_empty(),
		"D5 does not manufacture a second death to reconstruct old corpse fields"): return false
	_completed_phases.append("d5_reentry")
	return true
