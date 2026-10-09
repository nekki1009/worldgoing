extends "res://scripts/tests/site_fire_shared_step_test.gd"
## Runtime namespace collision fixture. Full Slot join/frame/Family proof is separate.
const Mapping = preload("res://scripts/terrain_lab/site_region_party_runtime_mapping.gd")
const OwnerSnapshot = preload("res://scripts/terrain_lab/site_region_owner_snapshot.gd")

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 120000
	create_timer(120.0, true).timeout.connect(func() -> void: _finish_fire(false, "runtime mapping deadline"))
	_run_runtime_mapping.call_deferred()

func _paid_source() -> Dictionary:
	var lab := _new_fire_lab()
	var actor := lab.character
	# Test genesis contains one original Actor; original paid launch follows.
	lab.terrain.site["actor_presence_version"] = 1
	lab.terrain.site["actors"] = {"player": actor.capture_state()}
	lab._bind_actor_presence(lab.terrain, lab.terrain.site.actors)
	actor.combat_ability = 100.0
	actor.training = 100.0
	actor.item_state.equipped.erase("weapon")
	var equipped := Runtime.create_equipment(lab.terrain, actor.item_state, "runtime_mapping_bow",
		{"slot": "weapon", "asset": "bow_01", "tint": [1.0, 1.0, 1.0, 1.0]}, actor.person_id, "weapon")
	if not _check_fire(equipped.ok, "Original equipment owner creates the fixture bow"): return {"ok": false}
	# Test genesis prepares real original contact resources before any paid order.
	# The disposable node is a resource package, never another registered person.
	var contact_appearance: Dictionary = Runtime.equipment_appearance(lab.terrain, actor.item_state, actor.capture_state().appearance)
	if not _check_fire(HumanCharacter3DEditor.valid_appearance(contact_appearance),
		"Original equipped holder supplies the valid bow/body contact appearance"): return {"ok": false}
	var genesis_fields: Array = TerrainTestCharacter.SAVED_FLOAT_FIELDS.keys()
	genesis_fields.append_array(TerrainTestCharacter.SAVED_INT_FIELDS)
	genesis_fields.append_array(TerrainTestCharacter.SAVED_BOOL_FIELDS)
	genesis_fields.append_array(TerrainTestCharacter.SAVED_VECTOR_FIELDS)
	genesis_fields.append_array(["terrain_cell", "facing", "movement_from_cell", "_movement_duration", "_movement_elapsed",
		"_movement_start", "_movement_linear", "_movement_ride", "_movement_ride_running", "_ride_start_speed", "_ride_end_speed", "ride_speed"])
	var genesis_body := {}
	for field: String in genesis_fields: genesis_body[field] = actor.get(field)
	var genesis_body_bytes := var_to_bytes(genesis_body)
	var genesis_items := var_to_bytes([actor.item_state, actor.ammo_inventory, actor.fire_body, actor.loot_settled, actor.remains_id])
	var genesis_site := var_to_bytes(lab.terrain.site)
	var genesis_flights := var_to_bytes(lab.fire_projectiles)
	var genesis_game := Runtime.now(lab.terrain)
	var genesis_action := lab.fire_action_cursor
	var prepared_ok := true
	var unregistered := true
	if actor.editor == null:
		var prepared := TerrainTestCharacter.new()
		prepared.set_process(false)
		root.add_child(prepared)
		unregistered = prepared.person_id == 0 and not lab.combat_actors.has(prepared)
		prepared_ok = unregistered and prepared.prepare_contact_visual(contact_appearance)
		if prepared_ok: actor.adopt_contact_visual(prepared)
		prepared.free()
	else:
		prepared_ok = actor.editor.restore_appearance(contact_appearance)
	if not _check_fire(prepared_ok and unregistered and actor.editor != null and actor.editor.model_root != null
		and actor.editor.animation_player != null and actor.editor.camera != null and actor.player_sprite != null
		and actor.editor.preview_viewport != null and is_same(actor.editor.preview_host, actor)
		and actor.editor.model_root.find_child("Skeleton3D", true, false) is Skeleton3D
		and actor.editor.capture_appearance() == contact_appearance,
		"Original public contact preparation attaches real CPU model/rig/camera/sprite to the same Actor"): return {"ok": false}
	var current_body := {}
	for field: String in genesis_fields: current_body[field] = actor.get(field)
	if not _check_fire(is_same(lab.character, actor) and genesis_body_bytes == var_to_bytes(current_body)
		and genesis_items == var_to_bytes([actor.item_state, actor.ammo_inventory, actor.fire_body, actor.loot_settled, actor.remains_id])
		and genesis_site == var_to_bytes(lab.terrain.site) and genesis_flights == var_to_bytes(lab.fire_projectiles)
		and Runtime.now(lab.terrain) == genesis_game and lab.fire_action_cursor == genesis_action,
		"Original contact resource preparation preserves the same person's body/items/Site/flights and both clocks"): return {"ok": false}
	var contact_geometry: Dictionary = actor.incoming_geometry(true)
	var contact_vertices := 0
	var contact_finite: bool = not contact_geometry.body.is_empty()
	for polygon: PackedVector2Array in contact_geometry.body:
		contact_finite = contact_finite and polygon.size() >= 3
		for point: Vector2 in polygon:
			contact_vertices += 1
			contact_finite = contact_finite and point.is_finite()
	print("MAPPING_ORIGINAL_CPU_CONTACT ", JSON.stringify({"person_id": actor.person_id, "unregistered_package": unregistered,
		"body_polygons": contact_geometry.body.size(), "body_vertices": contact_vertices, "finite": contact_finite,
		"game_seconds_unchanged": Runtime.now(lab.terrain) == genesis_game, "action_seconds_unchanged": lab.fire_action_cursor == genesis_action}))
	if not _check_fire(contact_finite and contact_vertices >= 3 and actor.editor.camera.size > 0.0
		and actor.editor.preview_viewport.size.x > 0 and actor.editor.preview_viewport.size.y > 0
		and is_same(actor.player_sprite.texture, actor.editor.preview_viewport.get_texture()),
		"Real original CPU bones project finite body polygons through the Actor's bound camera/sprite"): return {"ok": false}
	actor.ammo_inventory["fire_arrow"] = 1
	var issued := lab.issue_fire_order(actor.person_id, actor, {"type": "ground", "cell": [15, 15]}, "FIRE_ARROW")
	if not _check_fire(issued.ok, "Original Actor accepts the actual arrow order"): return {"ok": false}
	for _tick: int in range(60):
		if not _shared(lab): return {"ok": false}
		if not lab.fire_projectiles.is_empty(): break
	var transport: Dictionary = lab.capture_fire_transport()
	if not _check_fire(transport.ok and lab.fire_projectiles.size() == 1 and int(lab.fire_projectiles[0].projectile_id) == 1
			and int(actor.ammo_inventory.get("fire_arrow", 0)) == 0,
		"Each original source pays exactly once and owns paid projectile ID 1"): return {"ok": false}
	# Observe the current original body endpoint after the complete paid step.
	# These original geometry APIs build derived caches without another tick.
	var observed_body := var_to_bytes(actor.capture_state())
	var observed_site := var_to_bytes(lab.terrain.site)
	var observed_flights := var_to_bytes(lab.fire_projectiles)
	var observed_transport := var_to_bytes(transport.state)
	var observed_game := Runtime.now(lab.terrain)
	var observed_action := lab.fire_action_cursor
	var observed_position: Vector2 = actor.position
	lab._capture_fire_motion()
	lab._finish_fire_motion(0.0)
	var recaptured: Dictionary = lab.capture_fire_transport()
	if not _check_fire(recaptured.ok and observed_transport == var_to_bytes(recaptured.state)
		and observed_flights == var_to_bytes(lab.fire_projectiles)
		and observed_body == var_to_bytes(actor.capture_state()) and observed_site == var_to_bytes(lab.terrain.site)
		and Runtime.now(lab.terrain) == observed_game and lab.fire_action_cursor == observed_action
		and actor.position == observed_position and lab.fire_projectiles.size() == 1
		and int(lab.fire_projectiles[0].projectile_id) == 1 and int(actor.ammo_inventory.get("fire_arrow", 0)) == 0,
		"Original zero-time geometry observation preserves paid flight, zero ammo, body, Site and both clocks"): return {"ok": false}
	var identity := int(actor.combat_identity())
	if not _check_fire(identity == 1 and lab._fire_motion.size() == 1 and lab._fire_motion.has(identity)
		and is_same(lab._fire_motion[identity].owner, actor) and int(lab._fire_motion[identity].unit) == -1
		and int(lab._fire_motion[identity].id) == identity and float(lab._fire_motion[identity].radius) > 0.0
		and not lab._fire_motion[identity].geometry.body.is_empty() and not lab._fire_body_buckets.is_empty()
		and lab._fire_motion_delta == 0.0,
		"Original paid Actor geometry supplies real typed motion and 128-pixel buckets at the unchanged endpoint"): return {"ok": false}
	return {"ok": true, "lab": lab, "transport": transport.state}

func _source(source_namespace: String, token: String, party_hash: String, transport: Dictionary) -> Dictionary:
	var ids := {"fire_projectile": [1], "fire_job": [], "formation_runtime": [], "proposal": [], "lease_token": []}
	var highwater := {"fire_projectile": int(transport.release_sequence), "fire_job": 0, "formation_runtime": 0, "proposal": 0, "lease_token": 0}
	return {"namespace": source_namespace, "owner": "travel:" + token, "token": token, "source_generation": 9,
		"party_hash": party_hash, "ids": ids, "highwater": highwater, "fire_receipts": {"floor": 0, "ids": {}}}

func _run_runtime_mapping() -> void:
	var first := _paid_source()
	if not first.ok: _finish_fire(false, "first original paid flight"); return
	var second := _paid_source()
	if not second.ok: _finish_fire(false, "second original paid flight"); return
	# Collector unit negative: these dictionary fields do not claim a Slot join
	# or a new proposal/fire job. The source roots come from an actual Lab capture.
	var context := {"purpose": "region_barrier", "mode": "live", "source_generation": 0, "runtime_revision": 0,
		"token": "collector_original_source", "game_seconds": Runtime.now(first.lab.terrain) * 60.0,
		"action_seconds": first.lab.fire_action_cursor, "fire_epoch": "collector_original_source", "fire_sequence": 0,
		"interval_complete": true, "effects_complete": true, "mode_revision": 0, "backend": "gd", "events": [], "endpoint_payload": {}}
	var actual_scene: Dictionary = first.lab.capture_region_owner_state(context)
	if not _check_fire(actual_scene.ok, "Actual original scene supplies the collector roots: " + str(actual_scene)):
		_finish_fire(false, "original collector scene"); return
	var symbols := OwnerSnapshot.validate_for_bind(actual_scene.state, func(_key: String, _kind: int) -> bool: return true, context)
	if not _check_fire(symbols.ok, "Actual captured graph decodes symbolically for the pure collector: " + str(symbols)):
		_finish_fire(false, "collector symbols"); return
	var typed_transport: Dictionary = first.transport.duplicate(true)
	typed_transport.reservations.append({"formation_id": 777}) # Negative semantic field fixture, not an admitted Fire reservation.
	var scope := {"party_id": "collector_unit", "content": {"travel_identity": {"namespace": "collector_unit"}}}
	var collected := Mapping.collect_source(scope, symbols.roots, typed_transport, {}, 0)
	if not _check_fire(collected.ok and not collected.source.ids.formation_runtime.has(777)
		and collected.source.ids.fire_projectile.has(1),
		"A Fire preparation's team field cannot manufacture runtime formation ID 777; actual paid flight 1 remains collected"):
		_finish_fire(false, "transport field domain isolation"); return
	var first_hash := "first original party".sha256_text()
	var second_hash := "second original party".sha256_text()
	var allocated := Mapping.allocate([_source("site:alpha", "player_party", first_hash, first.transport),
		_source("site:beta", "npc_party", second_hash, second.transport)], "site:alpha", 10)
	if not _check_fire(allocated.ok and Mapping.valid(allocated.mapping, "site:alpha", 10), "Exact source-scoped runtime mapping is admitted"):
		_finish_fire(false, "mapping admission"); return
	var player := Mapping.source(allocated.mapping, "travel:player_party", "site:alpha", first_hash)
	var incoming := Mapping.source(allocated.mapping, "travel:npc_party", "site:beta", second_hash)
	if not _check_fire(player.ok and incoming.ok and Mapping.current(player.source, "fire_projectile", 1) == 1
			and Mapping.current(incoming.source, "fire_projectile", 1) == 2,
		"Equal source runtime ID 1 maps injectively to two actual future flight IDs"): _finish_fire(false, "injective flight mapping"); return
	var current_people := {"person": {"1": "3"}}
	var mapped_motion := Mapping.remap_owner_roots(symbols.roots, incoming.source, current_people)
	if not _check_fire(mapped_motion.ok and not symbols.roots.lab._fire_motion.is_empty()
		and mapped_motion.roots.lab._fire_motion.has(3)
		and int(mapped_motion.roots.lab._fire_motion[3].id) == 3
		and mapped_motion.roots.lab._fire_body_buckets.keys() == symbols.roots.lab._fire_body_buckets.keys(),
		"Actual paid motion outer/inner body IDs follow one typed person map; 128-pixel bucket coordinates stay fixed"):
		_finish_fire(false, "motion person mapping"); return
	var bucket_people := 0
	for bucket: Array in mapped_motion.roots.lab._fire_body_buckets.values():
		for identity: int in bucket:
			if not _check_fire(identity == 3, "Actual broadphase membership follows the current body ID"):
				_finish_fire(false, "broadphase person mapping"); return
			bucket_people += 1
	if not _check_fire(bucket_people > 0, "Actual broadphase contains the same original body after typed mapping"):
		_finish_fire(false, "paid broadphase admission"); return
	var mapped_first := Mapping.remap_transport(first.transport, allocated.mapping, "travel:player_party", "site:alpha", first_hash)
	var mapped_second := Mapping.remap_transport(second.transport, allocated.mapping, "travel:npc_party", "site:beta", second_hash, {"person": {"1": "3"}})
	var merged := Mapping.merge_transports([mapped_first.transport, mapped_second.transport])
	if not _check_fire(mapped_first.ok and mapped_second.ok and merged.ok and merged.transport.projectiles.size() == 2
			and int(merged.transport.projectiles[0].projectile_id) != int(merged.transport.projectiles[1].projectile_id),
		"Both paid original trajectories, elapsed values and shooter records remain in the single transport"):
		_finish_fire(false, "transport union"); return
	var target := _new_fire_lab()
	var body1: Dictionary = first.lab.character.capture_state()
	var body3: Dictionary = second.lab.character.capture_state()
	body3.person_id = 3
	body3.cell = [10, 12]
	# The target NPC owns its genuine navigation; the paid Actor owns every base field.
	var original_npc_receiver: Dictionary = target.npc.capture_state()
	if not _check_fire(original_npc_receiver.get("navigation") is Dictionary,
		"Original target NPC capture supplies its own complete navigation schema"):
		_finish_fire(false, "original NPC navigation capture"); return
	var paid_body_bytes := var_to_bytes(body3)
	body3["navigation"] = original_npc_receiver.navigation.duplicate(true)
	var paid_body_check: Dictionary = body3.duplicate(true)
	paid_body_check.erase("navigation")
	if not _check_fire(var_to_bytes(paid_body_check) == paid_body_bytes
		and body3.navigation == original_npc_receiver.navigation,
		"Original receiver navigation preserves every paid source base field without time or resource edits"):
		_finish_fire(false, "paid Actor base and original NPC schema"); return
	target.terrain.site["actors"] = {"player": body1, "npc": body3}
	target.terrain.site["actor_presence_version"] = 1
	target._bind_actor_presence(target.terrain, target.terrain.site.actors)
	target.character.restore_state(body1)
	target.npc.restore_state(body3)
	if not _check_fire(target.npc.capture_state().navigation == original_npc_receiver.navigation,
		"Original NPC restore reads back the exact navigation emitted by its original capture owner"):
		_finish_fire(false, "original NPC navigation roundtrip"); return
	target.fire_action_cursor = float(merged.transport.action_cursor)
	target.terrain.site["fire_transport"] = merged.transport
	var prepared: Dictionary = target._prepare_fire_transport_restore()
	if not _check_fire(prepared.ok, "Original Fire owner restore preflights both paid namespace-mapped flights: " + str(prepared)):
		_finish_fire(false, "original transport preflight"); return
	var restored := target._publish_fire_transport_restore(prepared.prepared)
	if not _check_fire(restored.ok and target.fire_projectiles.size() == 2
			and int(target.fire_projectiles[0].projectile_id) == 1 and int(target.fire_projectiles[1].projectile_id) == 2
			and first.lab.character.ammo_inventory.get("fire_arrow", 0) == 0
			and second.lab.character.ammo_inventory.get("fire_arrow", 0) == 0,
		"Actual original runtime restores both already paid flights without another ammo debit"):
		_finish_fire(false, "actual paid runtime restore"); return
	var wrong_scope := Mapping.remap_transport(second.transport, allocated.mapping, "travel:npc_party", "site:alpha", second_hash)
	var duplicated: Dictionary = allocated.mapping.duplicate(true)
	duplicated.sources[1].maps.fire_projectile["1"] = 1
	var preserved := var_to_bytes(target.fire_projectiles)
	if not _check_fire(not wrong_scope.ok and not Mapping.valid(duplicated)
			and preserved == var_to_bytes(target.fire_projectiles),
		"Wrong source namespace and duplicate runtime destinations are refused before original graph mutation"):
		_finish_fire(false, "scope refusal"); return
	_finish_fire(not fire_failed, "two actual paid ID-1 sources restore as separate original runtime flights; scope and injectivity refusals")