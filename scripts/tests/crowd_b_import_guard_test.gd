extends "res://scripts/tests/crowd_c2_clear_handoff_test.gd"
## Real first Actor admission, B return, exact full import and next-step rules.
## Reuses the formal handoff fixture and source snapshot readers; no native stubs.
var seeded_hit_row_id := 0

func _write() -> void:
	if out_dir.is_empty(): return
	var file := FileAccess.open(out_dir.path_join("import_guard.json"), FileAccess.WRITE)
	if file == null: return
	file.store_string(JSON.stringify({"ok": not failed, "args": Array(args), "checks": checks,
		"evidence": roundtrip_evidence,
		"scope": "Formal TerrainLab first solo Actor bootstrap, genuine B between returned-Actor fixtures, exact unknown-ability and KO full imports before a tick, unchanged native clone bytes through the complete formation setter, and normal next action-step command rules; independent ordinary facing and real equipment-job changes from fresh B metadata, followed by actual D5.",
		"not_covered": ["Army radius/geometry mismatch", "full natural DR battle", "native RNG parity across a successful first import", "candidate rollback on SOURCE_STATE_MISMATCH"]}, "\t", true, true))
	file.close()

func _admission_checkpoint(actor: TerrainTestCharacter) -> Dictionary:
	var state := _busy_actor_snapshot(actor)
	var data: Dictionary = lab.terrain.site
	var rows := {}
	for identity: int in original_rows:
		var row: Dictionary = _ordinary(identity).row
		rows[identity] = {"equipped": row.item_state.equipped, "item_ids": row.item_state.item_ids,
			"appearance_parts": row.appearance.parts, "hit_revision": int(row.get("hit_revision", 0))}
	return {"state": state, "site": data, "manual": data.manual, "cargo": data.manual.cargo,
		"item_records": data.item_records, "item_definitions": data.item_definitions,
		"items": data.item_records.duplicate(), "definitions": data.item_definitions.duplicate(),
		"cache": lab.site_controller._equipment_appearances,
		"cache_entries": lab.site_controller._equipment_appearances.duplicate(),
		"cache_values": lab.site_controller._equipment_appearances.duplicate(true),
		"holder": actor.item_state, "equipped": actor.item_state.equipped, "item_ids": actor.item_state.item_ids,
		"abilities": actor.command_abilities, "handoff": actor.get_meta(&"crowd_handoff"),
		"handoff_value": actor.get_meta(&"crowd_handoff").duplicate(true), "rows": rows}

func _returned_actor_request(actor: TerrainTestCharacter) -> Dictionary:
	# Both declarations supersede their B envelope. The existing importer therefore
	# requests a fresh one-person HOLD formation plus current ordinary fatigue/training.
	# Spell out that request before deployment; never use the setter's result as expected.
	var position := actor.position / Crowd.CELL
	var facing := Vector2(actor.facing).angle()
	var hot: Dictionary = Crowd._actor_native_fields(actor, lab.terrain.site.captivity,
		actor.capture_state().appearance, actor.ammo_inventory)
	var formation := {"morale": 100.0, "rally_rest": 0.0, "fatigue": actor.fatigue,
		"fatigue_rest": actor.fatigue_rest, "training": actor.training, "routed": false,
		"needs_attack_order": false, "commander_present": true, "fatigue_count": 1, "order": 0,
		"goal_x": position.x, "goal_y": position.y, "goal_facing": facing, "pursuit_left": 0.0,
		"origin_x": position.x, "origin_y": position.y, "ai_enabled": false,
		"cx": position.x, "cy": position.y, "facing": facing, "no_orders": true,
		"order_delay": 0.0, "attacking": false, "ref_x": position.x, "ref_y": position.y,
		"ref_valid": true, "resupplying": false, "host_center": true,
		"formal_person": actor.person_id, "acting_person": -1, "current_person": actor.person_id,
		"target_person": -1, "officer_persons": []}
	return {"hot": hot, "formation": formation}

func _complete_returned_import(actor: TerrainTestCharacter, before: Dictionary, request: Dictionary,
		result: Dictionary, label: String) -> bool:
	if not _check(result.ok and site.active and site.crowd.validate(), label + " actual D5 admits the complete source before any tick", result): return false
	var owner: Variant = site.person_owner(actor.person_id)
	var formation: int = int(owner.formation_index)
	var desired := {"people": {actor.person_id: request.hot}, "formations": {formation: request.formation}}
	var guarded: Dictionary = site._source_state_guard(desired)
	var expected_keys: Array[String] = []
	for field: String in Crowd.SOLDIER_FIELDS.slice(0, 22): expected_keys.append(field)
	expected_keys.append_array(["captor_person", "prison_id", "hit_revision"])
	expected_keys.sort()
	var actual_keys: Array[String] = []
	for field: Variant in request.hot.keys(): actual_keys.append(String(field))
	actual_keys.sort()
	if not _check(actual_keys == expected_keys and request.formation.size() == Crowd.FORMATION_FIELDS.size() + 5
		and guarded.ok, label + " retains exact 22 packed fields, two refs, integer counter and complete formation references", {"guard": guarded, "actual_keys": actual_keys, "expected_keys": expected_keys}): return false
	var actor_index: int = int(site.crowd.soldier_index(actor.person_id))
	if not _check(typeof(request.hot.hit_revision) == TYPE_INT and int(request.hot.hit_revision) == 9
		and int(site.crowd.contact_revision(actor_index)) == 9 and int(site.soldier_state(actor_index).hit_revision) == 9
		and actor._received_effective_hit == 9, label + " actual D5 seeds original Actor counter 9 before a tick"): return false
	if not _check(is_same(actor.command_abilities, before.abilities)
		and actor.command_abilities == before.ability_values and is_same(lab.terrain.site.manual, before.manual)
		and not Store._crowd_actor_solo_current(actor.capture_state(), before.handoff),
		label + " preserves the original ordinary ability object and leaves its genuine B envelope stale"): return false
	if not _b8_keeps_originals(actor, before, before.metadata_bytes, label): return false
	for team_key: String in before.state.sources:
		var source: Dictionary = before.state.sources[team_key]
		if not _check(source.owner.command_rng.state == source.rng,
			label + " preserves the original Army command RNG", team_key): return false
	for identity: int in before.rows:
		var row: Dictionary = site._records[identity]
		var row_index: int = int(site.crowd.soldier_index(identity))
		if not _check(int(site.crowd.contact_revision(row_index)) == int(before.rows[identity].hit_revision)
			and int(site.soldier_state(row_index).hit_revision) == int(before.rows[identity].hit_revision),
			label + " actual D5 seeds the original row counter", {"person": identity, "expected": before.rows[identity].hit_revision, "actual": site.crowd.contact_revision(row_index)}): return false
		if (not is_same(row.item_state.equipped, before.rows[identity].equipped)
			or not is_same(row.item_state.item_ids, before.rows[identity].item_ids)
			or not is_same(row.appearance.parts, before.rows[identity].appearance_parts)):
			return _check(false, label + " retains nested original holder and appearance references", identity)
	var live_bytes: PackedByteArray = site.crowd.save_state()
	var copy: RefCounted = ClassDB.instantiate("ArmyCrowd")
	copy.setup(1, 971)
	if not _check(copy.load_state(live_bytes), label + " inspection clone loads the actual pre-tick native world"): return false
	var clone_before: PackedByteArray = copy.save_state()
	var values: PackedFloat64Array = copy.get_formation_state(formation)
	var refs: PackedInt64Array = copy.formation_refs(formation)
	if not _check(copy.set_formation_state(formation, values, refs) and copy.save_state() == clone_before
		and site.crowd.save_state() == live_bytes,
		label + " complete formation setter preserves exact native bytes including RNG, dirty, presence, stats and events"): return false
	var hot: Dictionary = site.soldier_state(int(site.crowd.soldier_index(actor.person_id)))
	roundtrip_evidence[label] = {"request": request, "pre_tick_hot": hot,
		"pre_tick_formation": site.formation_state(formation), "clone_bytes": clone_before.size(),
		"metadata_sha": before.handoff.solo_source_sha256}
	return true

func _returned_next_tick(actor: TerrainTestCharacter, before: Dictionary, unknown: bool, label: String) -> bool:
	var index: int = int(site.crowd.soldier_index(actor.person_id))
	var formation: int = int(site.person_owner(actor.person_id).formation_index)
	var hot_before: Dictionary = site.soldier_state(index)
	var events: Array = []
	var receive: Callable = func(values: PackedInt64Array) -> void:
		for offset in range(0, values.size(), 4):
			if int(values[offset + 3]) == formation:
				events.append({"kind": int(values[offset]), "person": int(values[offset + 1]), "other": int(values[offset + 2])})
	site.events_received.connect(receive)
	var elapsed: float = TerrainLab.EXCHANGE_ACTION_STEP if lab.exchange_enabled else TerrainLab.ACTION_STEP
	var game_seconds: float = SiteRuntime.game_seconds(elapsed, float(lab.terrain.site.combat_left)) * lab.simulation_speed
	var steps: int = int(site._steps)
	lab._advance_action_time(elapsed)
	site.events_received.disconnect(receive)
	var hot: Dictionary = site.soldier_state(index)
	var state: Dictionary = site.formation_state(formation)
	if not _check(int(site._steps) == steps + 1 and site.crowd.validate(), label + " advances exactly one real common action step"): return false
	if unknown:
		for field: String in ["tactics", "leadership", "coach"]:
			if not _check(float(hot_before[field]) == -1.0 and float(hot[field]) == float(int(hot[field]))
				and int(hot[field]) >= 0 and int(hot[field]) <= 100,
				label + " generates " + field + " only during the normal step", {"before": hot_before[field], "after": hot[field]}): return false
		if not _check(int(state.formal_person) == actor.person_id and int(state.current_person) == actor.person_id
			and int(state.acting_person) == -1 and int(state.needs_attack_order) == 0 and events.is_empty(),
			label + " keeps the same eligible commander without a succession event", events): return false
	else:
		for field: String in ["tactics", "leadership", "coach"]:
			if not _check(float(hot[field]) == float(hot_before[field]), label + " keeps exact known " + field): return false
		if not _check(float(hot_before.ko) == 1234.0 and float(hot.ko) == 1234.0 - game_seconds
			and int(state.formal_person) == actor.person_id and int(state.current_person) == -1
			and int(state.acting_person) == -1 and int(state.needs_attack_order) == 1 and int(state.commander_present) == 0
			and events == [{"kind": 7, "person": -1, "other": actor.person_id}],
			label + " applies normal KO time and command loss only on the real step",
			{"ko": hot.ko, "game_seconds": game_seconds, "formation": state, "events": events}): return false
	if not _b8_keeps_originals(actor, before, before.metadata_bytes, label + " next step"): return false
	roundtrip_evidence[label].next_tick = {"hot": hot, "formation": state, "events": events, "game_seconds": game_seconds}
	return true

func _deploy_one() -> Dictionary:
	return lab.deploy_trial_armies([{"faction": 0, "count": 1, "attack": false, "ai_enabled": false, "entry": "north"}])

func _b8_fresh_actor(actor: TerrainTestCharacter, label: String) -> bool:
	for identity: int in site._records:
		var row: Dictionary = site._records[identity]
		original_rows[identity] = row
		original_holders[identity] = row.item_state
		original_cargo[identity] = row.cargo
		original_appearances[identity] = row.appearance
	var hit_before := {}
	for identity: int in site._records:
		hit_before[identity] = int(site.crowd.contact_revision(int(site.crowd.soldier_index(identity))))
	var actor_hit_before: int = int(site.crowd.contact_revision(int(site.crowd.soldier_index(actor.person_id))))
	var result: Dictionary = site.clear()
	if not _check(result.ok and not site.active, label + " uses actual B to return the original owners", result): return false
	if not _check(actor._received_effective_hit == actor_hit_before and actor_hit_before == 9, label + " actual B preserves the original Actor counter"): return false
	for identity: int in hit_before:
		var original: Dictionary = _ordinary(identity)
		if not _check(not original.is_empty() and int(original.row.get("hit_revision", -1)) == int(hit_before[identity]), label + " actual B preserves the exact original row counter", identity): return false
	if not _check(seeded_hit_row_id > 0 and int(_ordinary(seeded_hit_row_id).row.hit_revision) == 7, label + " original row counter 7 survives B and reentry"): return false
	for team: TerrainArmy in lab.combat_armies: team.set_process(false)
	return _same_refs() and _check(actor.has_meta(&"crowd_handoff")
		and Store._crowd_actor_solo_current(actor.capture_state(), actor.get_meta(&"crowd_handoff")),
		label + " starts with a genuinely current original solo source hash")

func _b8_keeps_originals(actor: TerrainTestCharacter, before: Dictionary, metadata_bytes: PackedByteArray, label: String) -> bool:
	if not _check(is_same(lab.terrain.site, before.site) and is_same(actor.item_state, before.holder)
		and is_same(actor.item_state.equipped, before.equipped) and is_same(actor.item_state.item_ids, before.item_ids)
		and is_same(actor.ammo_inventory, before.cargo) and is_same(lab.terrain.site.manual.cargo, before.cargo)
		and is_same(lab.terrain.site.item_records, before.item_records)
		and is_same(actor.get_meta(&"crowd_handoff"), before.handoff)
		and var_to_bytes(actor.get_meta(&"crowd_handoff")) == metadata_bytes,
		label + " retains the original actor, holder, cargo, registry and exact unsigned metadata object"): return false
	for identity: int in original_rows:
		var row: Dictionary = site._records[identity] if site.active else _ordinary(identity).row
		if not is_same(row, original_rows[identity]) or not is_same(row.item_state, original_holders[identity]) \
			or not is_same(row.cargo, original_cargo[identity]) or not is_same(row.appearance, original_appearances[identity]):
			return _check(false, label + " preserves every original Army cold reference", identity)
	for identity: String in before.items:
		if not is_same(lab.terrain.site.item_records.get(identity), before.items[identity]):
			return _check(false, label + " preserves original real-item record references", identity)
	return _original_item_records_unchanged(before.b8_item_values, label)

func _b8_independent_sources(actor: TerrainTestCharacter) -> bool:
	if not _b8_fresh_actor(actor, "B8 facing-only case"): return false
	var turn_before: Dictionary = _admission_checkpoint(actor)
	turn_before.b8_item_values = lab.terrain.site.item_records.duplicate(true)
	var turn_metadata_bytes: PackedByteArray = var_to_bytes(turn_before.handoff)
	var turn_source: Dictionary = actor.capture_state()
	var start_cell: Vector2i = actor.terrain_cell
	var start_position: Vector2 = actor.position
	var direction := Vector2i.RIGHT if actor.facing != Vector2i.RIGHT else Vector2i.DOWN
	actor.face_cell(start_cell + direction)
	var turned: Dictionary = actor.capture_state()
	var unchanged_before: Dictionary = turn_source.duplicate(true)
	var unchanged_after: Dictionary = turned.duplicate(true)
	# The original face_cell also derives the visual stance offset when ready.
	for field: String in ["facing", "_stance_offset"]:
		unchanged_before.erase(field)
		unchanged_after.erase(field)
	var facing_only: Dictionary = turn_source.duplicate(true)
	facing_only.facing = turned.facing.duplicate()
	if not _check(actor.facing == direction and actor.terrain_cell == start_cell and actor.position == start_position
		and not actor.is_moving() and unchanged_before == unchanged_after
		and not Store._crowd_actor_solo_current(turned, turn_before.handoff)
		and not Store._crowd_actor_solo_current(facing_only, turn_before.handoff),
		"original face_cell alone supersedes the fresh source hash without a movement or item change"): return false
	var expected_face: float = PackedFloat32Array([Vector2(direction).angle()])[0]
	var turn_deployed: Dictionary = _deploy_one()
	if not _check(turn_deployed.ok and site.active and site.crowd.validate(), "actual D5 imports the independently turned actor", turn_deployed): return false
	var turn_hot: Dictionary = site.soldier_state(int(site.crowd.soldier_index(actor.person_id)))
	if not _check(float(turn_hot.face) == expected_face and float(turn_hot.px) == start_position.x / Crowd.CELL
		and float(turn_hot.py) == start_position.y / Crowd.CELL,
		"native facing uses the current ordinary direction at the exact unchanged position", {"expected": expected_face, "native": turn_hot.face}): return false
	if not _b8_keeps_originals(actor, turn_before, turn_metadata_bytes, "facing-only D5"): return false
	roundtrip_evidence.B8_facing = {"before": turn_source.facing, "after": turned.facing,
		"native_face": turn_hot.face, "cell": [start_cell.x, start_cell.y], "metadata_sha": turn_before.handoff.solo_source_sha256}
	if not _b8_fresh_actor(actor, "B8 real bow inventory setup"): return false
	var definition: Dictionary = lab.terrain.site.item_definitions.get("weapon:bow_01",
		{"slot": "weapon", "asset": "bow_01", "tint": [1.0, 1.0, 1.0, 1.0]})
	var created: Dictionary = SiteRuntime.create_equipment(lab.terrain, actor.item_state, "weapon:bow_01", definition, actor.person_id)
	if not _check(created.ok and actor.item_state.item_ids.has(str(created.item_id))
		and not actor.item_state.equipped.values().has(str(created.item_id)), "original Runtime creates one real unequipped bow in the original holder", created): return false
	var bow_id: String = str(created.item_id)
	# Creating inventory also changes the source. A complete D5/B cycle obtains
	# a new genuine current envelope before testing the independent equipment job.
	var setup_deployed: Dictionary = _deploy_one()
	if not _check(setup_deployed.ok, "real deployment admits the prepared unequipped bow inventory", setup_deployed): return false
	if not _b8_fresh_actor(actor, "B8 independent equipment case"): return false
	var equipment_before: Dictionary = _admission_checkpoint(actor)
	equipment_before.b8_item_values = lab.terrain.site.item_records.duplicate(true)
	var equipment_metadata_bytes: PackedByteArray = var_to_bytes(equipment_before.handoff)
	var equipment_source: Dictionary = actor.capture_state()
	var original_equipped: Dictionary = actor.item_state.equipped.duplicate()
	var original_ids: Array = actor.item_state.item_ids.duplicate()
	var original_cargo_value: Dictionary = actor.ammo_inventory.duplicate(true)
	# Option C: ordinary action time cannot step after clear, so the five-second
	# personal equipment job is retired from this crowd-clear path. The owned bow
	# is committed through the real holder and the real equipment-change owner.
	actor.item_state.equipped.weapon = bow_id
	actor.item_state.version = int(actor.item_state.version) + 1
	lab.site_controller.equipment_changed(actor.person_id)
	var equipped: Dictionary = actor.capture_state()
	var item_only: Dictionary = equipment_source.duplicate(true)
	item_only.appearance = equipped.appearance.duplicate(true)
	item_only.item_state = equipped.item_state.duplicate(true)
	if not _check(str(actor.item_state.equipped.get("weapon", "")) == bow_id
		and str(equipped.appearance.parts.weapon) == "bow_01" and actor.item_state.item_ids == original_ids
		and actor.ammo_inventory == original_cargo_value and actor.terrain_cell == start_cell and actor.position == start_position
		and not actor.is_moving() and not Store._crowd_actor_solo_current(equipped, equipment_before.handoff)
		and not Store._crowd_actor_solo_current(item_only, equipment_before.handoff),
		"authored owned bow commit through the real equipment owner invalidates the fresh metadata",
		{"bow": bow_id, "parts": equipped.appearance.parts}): return false
	if not _b8_keeps_originals(actor, equipment_before, equipment_metadata_bytes, "ordinary equipment commit"): return false
	var gear_deployed: Dictionary = _deploy_one()
	if not _check(gear_deployed.ok and site.active and site.crowd.validate(), "actual D5 imports the completed original equipment job", gear_deployed): return false
	var gear_index: int = int(site.crowd.soldier_index(actor.person_id))
	var gear_hot: Dictionary = site.soldier_state(gear_index)
	var appearance: Dictionary = site._appearance(actor.person_id)
	var packed: int = site._packed_equip(appearance)
	var native_hash: int = site.crowd.state_hash()
	var copy: RefCounted = ClassDB.instantiate("ArmyCrowd")
	copy.setup(1, 971)
	if not _check(copy.load_state(site.crowd.save_state()), "read-only equipment inspection clone loads the actual native world"): return false
	var copy_hash: int = copy.state_hash()
	var equip_matches: bool = copy.set_soldier_equip(gear_index, packed) and copy.state_hash() == copy_hash
	if not _check(str(appearance.parts.weapon) == "bow_01" and (packed & 255) == 7 and equip_matches
		and site.crowd.state_hash() == native_hash and float(gear_hot.ammo) == float(original_cargo_value.arrow)
		and float(gear_hot.face) == expected_face and float(gear_hot.px) == start_position.x / Crowd.CELL
		and float(gear_hot.py) == start_position.y / Crowd.CELL,
		"actual native weapon, ammunition, position and facing match current ordinary equipment without altering the live native state"): return false
	if not _b8_keeps_originals(actor, equipment_before, equipment_metadata_bytes, "equipment D5"): return false
	roundtrip_evidence.B8_equipment = {"bow_id": bow_id, "before_equipped": original_equipped,
		"after_equipped": actor.item_state.equipped.duplicate(), "native_packed": packed, "native_ammo": gear_hot.ammo,
		"metadata_sha": equipment_before.handoff.solo_source_sha256,
		"isolation": "Live work preserves its legitimate fatigue changes; the detached gear-only source probe substitutes only the real committed appearance and item_state into the pre-job capture, without signing or changing any live metadata."}
	return true

func _run() -> void:
	args = OS.get_cmdline_user_args()
	if not _check(args.has("--crowd-test") and args.has("--crowd"), "guard test requires named isolated crowd startup"): return
	var stamp := Time.get_datetime_string_from_system().replace("-", "").replace(":", "").replace("T", "_")
	out_dir = "res://output/crowd_c2_c3_b_atlas_20261001/import_guard_%s_%d" % [stamp, Time.get_ticks_msec()]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var ignore := FileAccess.open(out_dir.path_join(".gdignore"), FileAccess.WRITE)
	if ignore != null: ignore.close()
	create_timer(240.0).timeout.connect(func() -> void:
		failed = true
		_write()
		printerr("GATE FAIL: import guard deadline")
		quit(3))
	lab = load("res://scenes/terrain_lab/TerrainLab.tscn").instantiate()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	current_scene = lab
	lab.set_process(false)
	for person: TerrainTestCharacter in lab.combat_actors: person.set_process(false)
	lab.site_controller._auto_save_blocked = true
	var actor: TerrainTestCharacter = lab.character
	if not _check(actor.command_abilities.is_empty() and not actor.has_meta(&"crowd_handoff"),
		"default original Actor starts with no appointed abilities or B metadata"): return
	# Declared nonempty original stock makes cargo alias/value rollback observable.
	lab.terrain.site.manual.cargo.arrow = 3
	if not _check(is_same(actor.ammo_inventory, lab.terrain.site.manual.cargo), "original actor uses the real Site ammunition dictionary"): return
	actor.military_role = "officer" # This original fixture exercises eligible command, unknown abilities and KO succession.
	actor._received_effective_hit = 9 # Explicit original Actor fixture before first Native activation.
	var original_actor: Dictionary = actor.capture_state()
	var initial: Dictionary = lab.deploy_trial_armies([
		{"faction": 0, "count": 4, "attack": false, "ai_enabled": false, "entry": "west"},
		{"faction": 0, "count": 4, "attack": false, "ai_enabled": false, "entry": "east"}])
	if not _check(initial.ok, "real first-time default Actor deployment is admitted", initial): return
	site = lab.crowd_site
	var first_index: int = int(site.crowd.soldier_index(actor.person_id))
	var first_hot: Dictionary = site.soldier_state(first_index)
	if not _check(actor.military_role == "officer" and int(site.crowd.get_military_role(first_index)) == 1
		and int(first_hot.military_role) == 1, "actual Native activation preserves the original eligible officer qualification"): return
	if not _check(int(site.crowd.contact_revision(first_index)) == 9 and int(first_hot.hit_revision) == 9
		and actor._received_effective_hit == 9, "fresh actual Native activation preserves original Actor hit counter 9"): return
	var first_abilities := {}
	for field: String in ["tactics", "leadership", "coach"]:
		var value: float = float(first_hot[field])
		if not _check(is_finite(value) and value == float(int(value)) and value >= 0.0 and value <= 100.0,
			"fresh native bootstrap produces a valid " + field, value): return
		first_abilities[field] = int(value)
	if not _check(float(first_hot.hp) == float(original_actor.hp) and float(first_hot.stun) == float(original_actor.stun)
		and float(first_hot.ko) == float(original_actor.knockout_left) and actor.command_abilities.is_empty()
		and not actor.has_meta(&"crowd_handoff") and actor.ammo_inventory.arrow == 3,
		"first admission keeps original body/cargo and adds no persistent bootstrap marker"): return
	roundtrip_evidence.fresh_abilities = first_abilities
	for identity: int in site._records:
		original_rows[identity] = site._records[identity]
		original_holders[identity] = site._records[identity].item_state
		original_cargo[identity] = site._records[identity].cargo
		original_appearances[identity] = site._records[identity].appearance
	var cleared: Dictionary = site.clear()
	if not _check(cleared.ok and not site.active and lab.crowd_site == site, "real B returns the same people to ordinary owners", cleared): return
	for team: TerrainArmy in lab.combat_armies: team.set_process(false)
	if not _same_refs(): return
	if not _check(actor._received_effective_hit == 9 and not original_rows.is_empty(), "first actual B preserves Actor counter and original rows"): return
	seeded_hit_row_id = int(original_rows.keys()[0])
	var seeded_original: Dictionary = _ordinary(seeded_hit_row_id)
	if not _check(not seeded_original.is_empty(), "nonzero row fixture uses its real original Army owner", seeded_hit_row_id): return
	seeded_original.team.combat_hot_set(int(seeded_original.index), &"hit_revision", 7)
	if not _check(not site.active and int(seeded_original.row.hit_revision) == 7, "author legal original row counter 7 before D5 reentry", seeded_hit_row_id): return
	if not _check(actor.has_meta(&"crowd_handoff") and actor.get_meta(&"crowd_handoff").has("solo_source_sha256")
		and actor.command_abilities == first_abilities, "B preserves exact generated abilities and installs its real frozen handoff metadata"): return
	var returned_abilities: Dictionary = actor.command_abilities.duplicate()
	# A returned unknown-ability source must never be mistaken for first admission.
	actor.command_abilities = {}
	if not _check(TerrainTestCharacter.valid_state(actor.capture_state(), lab.terrain)
		and not Store._crowd_actor_solo_current(actor.capture_state(), actor.get_meta(&"crowd_handoff")),
		"declared returned Actor with absent abilities is valid ordinary state and supersedes its frozen solo state"): return
	var unknown_before := _admission_checkpoint(actor)
	unknown_before.ability_values = actor.command_abilities.duplicate()
	unknown_before.b8_item_values = lab.terrain.site.item_records.duplicate(true)
	unknown_before.metadata_bytes = var_to_bytes(unknown_before.handoff)
	var unknown_request := _returned_actor_request(actor)
	var unknown_result := _deploy_one()
	if not _complete_returned_import(actor, unknown_before, unknown_request, unknown_result, "returned_unknown"): return
	if not _returned_next_tick(actor, unknown_before, true, "returned_unknown"): return
	if not _b8_fresh_actor(actor, "unknown-to-KO genuine B boundary"): return
	# A separate valid ordinary KO fixture retains the declared command state
	# through import; only the next real native step applies command loss.
	actor.command_abilities = returned_abilities.duplicate()
	var ordinary_hot := {"ko": actor.knockout_left, "getup": actor._getting_up,
		"action_time": actor.action_time, "guarding": actor.guarding}
	actor.knockout_left = 1234.0
	actor._getting_up = false
	actor.action_time = 0.0
	actor.guarding = false
	if not _check(actor.hp > 0.0 and not actor.captive and TerrainTestCharacter.valid_state(actor.capture_state(), lab.terrain)
		and not Store._crowd_actor_solo_current(actor.capture_state(), actor.get_meta(&"crowd_handoff")),
		"declared KO source is valid and keeps known abilities while invalidating only the frozen formation"): return
	var ko_before := _admission_checkpoint(actor)
	ko_before.ability_values = actor.command_abilities.duplicate()
	ko_before.b8_item_values = lab.terrain.site.item_records.duplicate(true)
	ko_before.metadata_bytes = var_to_bytes(ko_before.handoff)
	var ko_request := _returned_actor_request(actor)
	var ko_result := _deploy_one()
	if not _complete_returned_import(actor, ko_before, ko_request, ko_result, "returned_ko"): return
	if not _returned_next_tick(actor, ko_before, false, "returned_ko"): return
	if not _b8_fresh_actor(actor, "KO-to-known genuine B boundary"): return
	# Independent positive fixture: current ordinary abilities are authoritative,
	# even though the retained B source hash no longer matches this source.
	actor.knockout_left = ordinary_hot.ko
	actor._getting_up = ordinary_hot.getup
	actor.action_time = ordinary_hot.action_time
	actor.guarding = ordinary_hot.guarding
	var authored := {"tactics": (int(returned_abilities.tactics) + 17) % 101,
		"leadership": (int(returned_abilities.leadership) + 29) % 101, "coach": (int(returned_abilities.coach) + 43) % 101}
	actor.command_abilities = authored.duplicate()
	var metadata: Dictionary = actor.get_meta(&"crowd_handoff")
	var metadata_value: Dictionary = metadata.duplicate(true)
	var retry_before := _admission_checkpoint(actor)
	var retried := _deploy_one()
	if not _check(retried.ok and site.active and site.crowd.validate(), "real returned Actor retry admits its current known three abilities", retried): return
	var returned_hot: Dictionary = site.soldier_state(int(site.crowd.soldier_index(actor.person_id)))
	for field: String in authored:
		if not _check(int(returned_hot[field]) == int(authored[field]), "returned Actor preserves exact authored " + field,
			{"expected": authored[field], "actual": returned_hot[field]}): return
	if not _check(is_same(actor.get_meta(&"crowd_handoff"), metadata) and actor.get_meta(&"crowd_handoff") == metadata_value
		and is_same(lab.terrain.site, retry_before.site) and is_same(actor.item_state, retry_before.holder)
		and is_same(actor.ammo_inventory, retry_before.cargo) and actor.ammo_inventory.arrow == 3,
		"successful retry preserves original holders and stale B metadata without re-signing it"): return
	for identity: int in original_rows:
		var row: Dictionary = site._records[identity]
		if (not is_same(row, original_rows[identity]) or not is_same(row.item_state, original_holders[identity])
			or not is_same(row.cargo, original_cargo[identity]) or not is_same(row.appearance, original_appearances[identity])):
			_check(false, "positive retry retains every original Army person and real-item/appearance owner", identity)
			return
	roundtrip_evidence.returned_known = {"before": returned_abilities, "authored": authored, "native": returned_hot,
		"original_people": original_rows.size(), "native_people": site.crowd.soldier_count()}
	if not await _b8_independent_sources(actor): return
	_write()
	lab.queue_free()
	await process_frame
	print("GATE OK: crowd import guard checks=", checks.size())
	quit(0)
