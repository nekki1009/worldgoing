extends "res://scripts/tests/crowd_c2_clear_handoff_test.gd"
## Dedicated original-Actor timer roundtrip after the inherited real first B.
## --crowd --crowd-test <fresh> --clear-member --clear-actor-busy --case baseline
## Root runs this through the bounded canonical helper; no production test hook.

func _actor_timers(actor: TerrainTestCharacter) -> Dictionary:
	return {"stagger": actor.exchange_stagger, "exch_cd": actor.exchange_cooldown,
		"ranged_cd": actor.ranged_cooldown, "skill_cd": actor.exchange_skill_cooldown}

func _returned_actor_busy_guards() -> bool:
	if not _check(args.has("--clear-member") and args.has("--clear-actor-busy") and case_name == "baseline"
		and not args.has("--clear-large") and not args.has("--clear-auto-mode"), "timer fixture uses the inherited first B and ordinary member-control path"): return false
	var actor: TerrainTestCharacter = lab.character
	var actor_id: int = actor.person_id
	var controlled: int = lab.controlled_person_id()
	if not _check(not site.active and actor_id != controlled and actor.has_meta(&"crowd_handoff") and actor.exchange_enabled,
		"returned original Actor owns its ordinary exchange clock after first B", actor_id): return false
	var live_meta: Dictionary = actor.get_meta(&"crowd_handoff")
	var metadata_before: Dictionary = live_meta.duplicate(true)
	if not _check(metadata_before.has("solo_source_sha256") and metadata_before.has("solo_formation"), "returned Actor retains the original solo envelope"): return false
	# Explicit fixture inputs, written to the existing Actor owner before any tick.
	# Its inherited metadata deliberately remains the previous native snapshot.
	actor.exchange_stagger = 20.0
	actor.exchange_cooldown = 21.0
	actor.ranged_cooldown = 22.0
	actor.exchange_skill_cooldown = 23.0
	var declared: Dictionary = _actor_timers(actor)
	for tick in range(4): lab._advance_action_time(DT)
	var after_four: Dictionary = _actor_timers(actor)
	for field: String in declared:
		if not _check(float(after_four[field]) > 0.0 and float(after_four[field]) < float(declared[field]), "actual Lab clock decreases the declared ordinary timer", {"field": field, "declared": declared[field], "after_four_ticks": after_four[field]}): return false
	var pending_before: Dictionary = _ordinary_pending_actions()
	var settle_ticks: int = 0
	for tick in range(300):
		if _ordinary_pending_actions().is_empty() and lab.site_controller.supply_save_guard().ok: break
		lab._advance_action_time(DT)
		settle_ticks += 1
	var pending_after: Dictionary = _ordinary_pending_actions()
	var guard: Dictionary = lab.site_controller.supply_save_guard()
	var current: Dictionary = _actor_timers(actor)
	var settle: Dictionary = {"ticks": settle_ticks, "action_seconds": settle_ticks * DT,
		"pending_before": pending_before, "pending_after": pending_after, "guard": guard}
	if not _check(pending_after.is_empty() and guard.ok and settle_ticks * DT <= 10.0,
		"original clocks settle every Actor/Army pending action within ten additional seconds", settle): return false
	for field: String in current:
		if not _check(float(current[field]) > 0.0 and not _same_value(current[field], metadata_before[field]), "saved timer remains nonzero and differs from stale metadata", {"field": field, "actual": current[field], "stale": metadata_before[field]}): return false
	if not _check(is_same(actor.get_meta(&"crowd_handoff"), live_meta) and _same_value(live_meta, metadata_before),
		"ordinary clock advancement leaves the original metadata object and every value unchanged"): return false
	var expected_extra: Dictionary = metadata_before.duplicate(true)
	for field: String in current: expected_extra[field] = current[field]
	var original_ids: Array[int] = []
	for identity: int in original_rows: original_ids.append(identity)
	original_ids.append(actor_id)
	original_ids.sort()
	var original_items: Dictionary = lab.terrain.site.item_records.duplicate(true)
	var cold_before: Dictionary = {}
	for identity: int in original_rows:
		var person: Dictionary = _ordinary(identity)
		if not _check(not person.is_empty(), "original ordinary row is present before timer save", identity): return false
		cold_before[identity] = {"item_state": person.row.item_state.duplicate(true), "cargo": person.row.cargo.duplicate(true), "appearance": person.row.appearance.duplicate(true)}
	var actor_cold: Dictionary = {"item_state": actor.item_state.duplicate(true), "cargo": actor.ammo_inventory.duplicate(true)}
	if not _check(not site.contains_person(actor_id), "first B leaves a real empty Crowd owner for foreign Actor capture"): return false
	var stale_foreign: Dictionary = Handoff._actor_state(site, actor)
	if not _check(_same_value(stale_foreign.get("crowd_handoff", {}), expected_extra)
		and is_same(actor.get_meta(&"crowd_handoff"), live_meta) and _same_value(live_meta, metadata_before),
		"Clear foreign capture reads actual timers even while the live metadata still contains stale values", stale_foreign.get("crowd_handoff")): return false
	lab.site_controller._capture_positions()
	var captured_extra: Dictionary = lab.terrain.site.actors.player.crowd_handoff
	if not _check(not is_same(captured_extra, live_meta) and _same_value(captured_extra, expected_extra),
		"actual Controller capture copies current timers and preserves every other native-only/solo field", captured_extra): return false
	if not _check(is_same(actor.get_meta(&"crowd_handoff"), live_meta) and _same_value(live_meta, metadata_before),
		"capture does not update or re-sign the live metadata"): return false
	var save_path: String = lab.site_controller.save_path
	var saved: Dictionary = lab.site_controller.save_to(save_path)
	if not _check(saved.ok, "ordinary Actor timers save through actual Controller and Store", saved): return false
	var envelope: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if not _check(envelope is Dictionary and envelope.get("payload") is String and not envelope.has("payload_encoding")
		and str(envelope.get("checksum", "")) == str(envelope.payload).sha256_text(), "ordinary on-disk timer save has its real complete payload and checksum"): return false
	var payload: Variant = JSON.parse_string(envelope.payload)
	if not _check(payload is Dictionary and payload.get("state") is Dictionary and payload.state.get("actors") is Dictionary,
		"ordinary on-disk timer snapshot decodes"): return false
	var disk_extra: Dictionary = payload.state.actors.player.crowd_handoff
	if not _check(_same_value(disk_extra, expected_extra), "saved JSON has current four timers plus unchanged solo SHA/formation and native-only fields", disk_extra): return false
	if not _check(is_same(actor.get_meta(&"crowd_handoff"), live_meta) and _same_value(live_meta, metadata_before),
		"complete save leaves the original live metadata object and values unchanged"): return false
	var loaded: Dictionary = lab.site_controller.load_from(save_path)
	if not _check(loaded.ok and (lab.crowd_site == null or not lab.crowd_site.active), "actual Controller loads the ordinary timer snapshot", loaded.get("code", "OK")): return false
	actor = lab.character
	if not _check(actor.person_id == actor_id and lab.controlled_person_id() == controlled and _same_value(_actor_timers(actor), current),
		"ordinary load restores all four current timers and original identities/control", _actor_timers(actor)): return false
	var loaded_extra: Dictionary = actor.get_meta(&"crowd_handoff", {})
	if not _check(_same_value(loaded_extra, expected_extra), "loaded metadata retains the saved timers and original source SHA/formation", loaded_extra): return false
	if not _check(_same_value(actor.item_state, actor_cold.item_state) and _same_value(actor.ammo_inventory, actor_cold.cargo)
		and is_same(actor.ammo_inventory, lab.terrain.site.manual.cargo), "ordinary load preserves the original Actor's real items and Site cargo alias"): return false
	if not _original_item_records_unchanged(original_items, "timer ordinary save/load"): return false
	# A real inactive Crowd owner selects Clear's foreign-Actor capture branch.
	var foreign_host: Node = lab.crowd_site
	var owns_foreign_host: bool = foreign_host == null
	if owns_foreign_host:
		foreign_host = Crowd.new()
		foreign_host.setup(lab)
	var foreign_ok: bool = not foreign_host.active and not foreign_host.contains_person(actor_id)
	if not _check(foreign_ok, "real empty Crowd owner exposes the foreign-Actor capture boundary"):
		if owns_foreign_host: foreign_host.free()
		return false
	var foreign: Dictionary = Handoff._actor_state(foreign_host, actor)
	if owns_foreign_host: foreign_host.free()
	if not _check(_same_value(foreign.get("crowd_handoff", {}), expected_extra)
		and is_same(actor.get_meta(&"crowd_handoff"), loaded_extra) and _same_value(loaded_extra, expected_extra),
		"actual Clear foreign-Actor capture preserves current timers without modifying metadata", foreign.get("crowd_handoff")): return false
	# Disk loading rehydrates ordinary row dictionaries. Those actual loaded owners
	# become the reference baseline for the subsequent no-copy D5 transfer.
	original_rows.clear()
	original_holders.clear()
	original_cargo.clear()
	original_appearances.clear()
	for identity: int in cold_before:
		var person: Dictionary = _ordinary(identity)
		if not _check(not person.is_empty(), "original row identity survives ordinary disk load", identity): return false
		for field: String in ["item_state", "cargo", "appearance"]:
			if not _check(_same_value(person.row[field], cold_before[identity][field]), "original row cold values survive ordinary disk load", {"person": identity, "field": field}): return false
		original_rows[identity] = person.row
		original_holders[identity] = person.row.item_state
		original_cargo[identity] = person.row.cargo
		original_appearances[identity] = person.row.appearance
	var loaded_holder: Dictionary = actor.item_state
	var loaded_cargo: Dictionary = actor.ammo_inventory
	var ordinary_hot: Dictionary = _ordinary_actual_hot()
	var imported: Dictionary = lab.deploy_trial_armies([{"faction": 0, "count": 1, "attack": false, "ai_enabled": false, "entry": "north"}])
	if not _check(imported.ok and lab.crowd_site != null and lab.crowd_site.active, "real D5 imports the loaded ordinary people and one requested newcomer", imported): return false
	site = lab.crowd_site
	for identity: int in original_ids:
		if not _check(site.contains_person(identity), "timer roundtrip D5 retains each original native identity", identity): return false
	for identity: int in original_rows:
		var row: Dictionary = site._records[identity]
		if not _check(is_same(row, original_rows[identity]) and is_same(row.item_state, original_holders[identity])
			and is_same(row.cargo, original_cargo[identity]) and is_same(row.appearance, original_appearances[identity]),
			"D5 retains every loaded original row/holder/cargo/appearance reference", identity): return false
		var hot: Dictionary = site.soldier_state(int(site.crowd.soldier_index(identity)))
		for field: String in ordinary_hot.people[identity]:
			if not _check(_same_value(hot[field], ordinary_hot.people[identity][field]), "D5 retains each original ordinary row's actual hot state", {"person": identity, "field": field}): return false
	var native_actor: Dictionary = site.soldier_state(int(site.crowd.soldier_index(actor_id)))
	for field: String in current:
		if not _check(_same_value(native_actor[field], current[field]), "D5 imports the actual loaded Actor timer instead of the stale metadata value", {"field": field, "expected": current[field], "native": native_actor[field], "old": metadata_before[field]}): return false
	if not _check(is_same(site._actors[actor_id], actor) and is_same(actor.item_state, loaded_holder)
		and is_same(actor.ammo_inventory, loaded_cargo) and is_same(loaded_cargo, lab.terrain.site.manual.cargo),
		"D5 retains the loaded original Actor, real-item holder and original Site cargo alias"): return false
	if not _original_item_records_unchanged(original_items, "timer roundtrip D5"): return false
	if not _check(site._records.size() == original_rows.size() + 1 and int(site.crowd.soldier_count()) == original_ids.size() + 1,
		"timer roundtrip adds exactly the one requested native row", {"original_rows": original_rows.size(), "native_rows": site._records.size(), "native_people": site.crowd.soldier_count()}): return false
	roundtrip_evidence["actor_timer_save"] = {"actor": actor_id, "declared": declared, "after_four_ticks": after_four,
		"settle": settle, "actual_before_save": current, "stale_metadata": metadata_before, "saved_extra": disk_extra,
		"loaded_extra": loaded_extra.duplicate(true), "native_after_D5": native_actor, "new_native_rows": 1,
		"save_path": save_path, "original_ids": original_ids, "source_sha_not_resigned": true}
	print("CROWD_B_ACTOR_TIMER_SAVE_PASS checks=", checks.size())
	return true
