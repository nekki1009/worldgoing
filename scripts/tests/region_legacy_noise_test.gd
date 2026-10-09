extends "res://scripts/tests/site_fire_shared_step_test.gd"
## Actual original cell-flight capture, original owner restore and original impact.
## Pure source scope/projection fixture; this does not claim a Slot transaction.
const Mapping = preload("res://scripts/terrain_lab/site_region_party_runtime_mapping.gd")
const Travel = preload("res://scripts/region_lab/region_travel.gd")
const OwnerSnapshot = preload("res://scripts/terrain_lab/site_region_owner_snapshot.gd")

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 120000
	create_timer(120.0, true).timeout.connect(func() -> void: _finish_fire(false, "legacy noise deadline"))
	_run_legacy_noise.call_deferred()

func _legacy_context(lab: TerrainLab) -> Dictionary:
	return {"purpose": "region_barrier", "mode": "live", "source_generation": 7, "runtime_revision": 0,
		"token": "legacy_source", "game_seconds": Runtime.now(lab.terrain) * 60.0,
		"action_seconds": lab.fire_action_cursor, "fire_epoch": "legacy_source", "fire_sequence": 0,
		"interval_complete": true, "effects_complete": true, "mode_revision": 0, "backend": "gd", "events": [], "endpoint_payload": {}}

func _run_legacy_noise() -> void:
	var source := _new_fire_lab()
	source.physical_ranged_enabled = false
	source.character.exchange_enabled = true
	source.npc.exchange_enabled = true
	source.npc.faction_id = 2
	if not _check_fire(source.npc.place(Vector2i(14, 10), true), "The actual original NPC stands in the real projectile ray"):
		_finish_fire(false, "target genesis"); return
	source.character.item_state.equipped.erase("weapon")
	var bow := Runtime.create_equipment(source.terrain, source.character.item_state, "legacy_noise_bow",
		{"slot": "weapon", "asset": "bow_01", "tint": [1.0, 1.0, 1.0, 1.0]}, source.character.person_id, "weapon")
	if not _check_fire(bow.ok, "Original inventory/equipment owner creates the fixture bow"):
		_finish_fire(false, "source equipment"); return
	source.character.ammo_inventory["arrow"] = 1
	if not _check_fire(source.character.ranged_fire(Vector2i(14, 10), 1)
		and source.character.ammo_inventory.arrow == 0 and source.character.projectiles.size() == 1,
		"Actual Actor pays one arrow and publishes original cell flight serial 1"):
		_finish_fire(false, "paid original release"); return
	source.terrain.site.actors = {"player": source.character.capture_state(), "npc": source.npc.capture_state()}
	source.terrain.site.actor_presence_version = 1
	source.terrain.site.controlled_person_id = source.character.person_id
	var identity := Travel.prepare_identity(source.terrain.site, "legacy:source")
	if not _check_fire(identity.ok, "Original Travel identity owner admits both actual person bodies"):
		_finish_fire(false, "source typed identity"); return
	source.terrain.site = identity.state
	source._bind_actor_presence(source.terrain, source.terrain.site.actors)
	var context := _legacy_context(source)
	var captured := source.capture_region_owner_state(context)
	if not _check_fire(captured.ok, "Actual original scene captures the already paid cell trajectory: " + str(captured)):
		_finish_fire(false, "original capture"); return
	var decoded := OwnerSnapshot.validate_for_bind(captured.state, func(_key: String, _kind: int) -> bool: return true, context)
	if not _check_fire(decoded.ok, "Actual original graph decodes before source projection"):
		_finish_fire(false, "source graph"); return
	var party := {"party_id": "legacy_source", "content": {"travel_identity": source.terrain.site.travel_identity}, "upkeep": {}}
	var source_hash: String = source._region_party_hash(party)
	var proof := {"generation": 7, "owner": "travel:legacy_source", "token": "legacy_source", "party_hash": source_hash}
	var prepared := source._region_project_legacy_noise(decoded.roots, party, proof)
	if not _check_fire(prepared.ok and not source.character.projectiles[0].has("_region_legacy_noise"),
		"Actual source admission derives lineage in a detached graph without changing the ordinary live flight"):
		_finish_fire(false, "source lineage"); return
	var raw := Mapping.collect_source(party, prepared.roots, {}, {}, 7)
	var admitted := Mapping.allocate([raw.source], "legacy:source", 8)
	if not _check_fire(raw.ok and admitted.ok, "The original captured owner roots supply the source epoch receipt"):
		_finish_fire(false, "runtime lineage"); return
	var projection := {"version": 1, "source_width": 100, "source_height": 100, "size": [100, 100],
		"world_origin": [0, 0], "default_offset": [2, 2], "people": {}, "teams": {}, "vehicles": {}}
	var moved := Travel.project_owner_coordinates(prepared.roots, projection)
	var source_shooter := str(source.character.person_id)
	var source_target := str(source.npc.person_id)
	var maps := {"person": {source_shooter: "11", source_target: "12"}}
	var remapped := Mapping.remap_owner_roots(moved.roots, admitted.mapping.sources[0], maps)
	if not _check_fire(moved.ok and remapped.ok and remapped.roots.actor_hot["11"].projectiles[0].shooter_id == 11
		and remapped.roots.actor_hot["11"].projectiles[0].shot_id == 1,
		"Only the current shooter/body references change; paid serial 1 remains the Actor's original serial"):
		_finish_fire(false, "current identity mapping"); return
	var body_coordinates := Travel.project_owner_coordinates(source.terrain.site, projection)
	var body_ids := Mapping.remap_original_runtime_body(body_coordinates.roots, admitted.mapping.sources[0], maps)
	var target_data: TerrainData = Env.navigation_for_state(source.terrain, body_ids.content)
	target_data.site.travel_identity.refs.person = {"11": source.terrain.site.travel_identity.refs.person[source_shooter].duplicate(true),
		"12": source.terrain.site.travel_identity.refs.person[source_target].duplicate(true)}
	target_data.set_meta(&"region_party_runtime_mapping", admitted.mapping)
	target_data.seed_value = source.terrain.seed_value ^ 12345
	var target := _building_lab(target_data)
	fire_labs.append(target)
	target.physical_ranged_enabled = false
	target.exchange_enabled = true
	target.character.exchange_enabled = true
	target.npc.exchange_enabled = true
	target.npc.faction_id = 2
	target.character.restore_state(target_data.site.actors.player)
	target.npc.restore_state(target_data.site.actors.npc)
	if not _check_fire(target.character.person_id == 11 and target.npc.person_id == 12,
		"Original Actor restore owns the same two typed bodies with current IDs 11 and 12"):
		_finish_fire(false, "target original bodies"); return
	var wire := OwnerSnapshot.capture_bind_roots(remapped.roots, context)
	if not _check_fire(wire.ok, "Original codec stores projected paid flight and its immutable XOR inputs"):
		_finish_fire(false, "durable symbolic graph"); return
	var restored := target.prepare_restore_region_owner_state({"scene": wire.state}, context)
	if not _check_fire(restored.ok, "Actual original owner preflight admits the projected paid flight: " + str(restored)):
		_finish_fire(false, "original owner preflight"); return
	var published := target.publish_restore_region_owner_state(restored)
	if not _check_fire(published.ok and target.character.projectiles.size() == 1
		and target.character.ammo_inventory.get("arrow", -1) == 0,
		"Original owner publishes the paid trajectory without another ammo debit"):
		_finish_fire(false, "original owner publication"); return
	var before := var_to_bytes(target.character.projectiles)
	for bad_kind: String in ["paid_serial", "source_scope", "source_geometry"]:
		var bad: Dictionary = Mapping._clone(remapped.roots, [], [])
		var flight: Dictionary = bad.actor_hot["11"].projectiles[0]
		if bad_kind == "paid_serial": flight._region_legacy_noise.shot_id = 2
		elif bad_kind == "source_scope": flight._region_legacy_noise.source.party_hash = "wrong original source".sha256_text()
		else: flight.position += Vector2(1.0, 0.0)
		var bad_wire := OwnerSnapshot.capture_bind_roots(bad, context)
		var rejected := target.prepare_restore_region_owner_state({"scene": bad_wire.state}, context)
		if not _check_fire(not rejected.ok and var_to_bytes(target.character.projectiles) == before,
			"Strict original preflight refuses " + bad_kind + " without changing paid flight/body state"):
			_finish_fire(false, "strict " + bad_kind); return
	var source_result: Array = []
	var target_result: Array = []
	source.ranged_resolved.connect(func(_shooter: int, _target: int, result: Dictionary) -> void: source_result.append(result.duplicate(true)))
	target.ranged_resolved.connect(func(_shooter: int, _target: int, result: Dictionary) -> void: target_result.append(result.duplicate(true)))
	var source_hp := source.npc.hp
	var target_hp := target.npc.hp
	source._advance_ranged(1.0)
	target._advance_ranged(1.0)
	if not _check_fire(source_result.size() == 1 and target_result.size() == 1
		and source_result[0] == target_result[0]
		and is_equal_approx(source_hp - source.npc.hp, target_hp - target.npc.hp)
		and target.character.projectiles.is_empty() and target.character.ammo_inventory.get("arrow", -1) == 0,
		"The same true target receives the original result after seed/coordinate/current-ID changes via original impact, without another debit"):
		_finish_fire(false, "original endpoint result"); return
	_finish_fire(not fire_failed, "actual legacy paid capture/restore/impact preserve original XOR and true target result")

