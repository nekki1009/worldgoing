extends "res://scripts/tests/site_fire_shared_step_test.gd"
## P5 original Lab/Store bind round trip for an armed owner order.

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 120000
	create_timer(120.0, true).timeout.connect(func() -> void: _finish_transport(false, "120-second transport deadline"))
	_run_transport.call_deferred()

func _finish_transport(ok: bool, reason: String) -> void:
	for lab: TerrainLab in fire_labs:
		if is_instance_valid(lab) and lab.terrain != null and lab.terrain.has_meta(&"fire_transport_snapshot"):
			lab.terrain.remove_meta(&"fire_transport_snapshot")
	_finish_fire(ok, reason)

func _run_transport() -> void:
	var lab := _new_fire_lab()
	var actor := lab.character
	actor.combat_ability = 100.0
	actor.training = 100.0
	actor.item_state.equipped.erase("weapon")
	var equipped := Runtime.create_equipment(lab.terrain, actor.item_state, "p5_transport_bow",
		{"slot": "weapon", "asset": "bow_01", "tint": [1.0, 1.0, 1.0, 1.0]}, actor.person_id, "weapon")
	if not _check_fire(equipped.ok, "Original equipment owner equips the ranged weapon"): _finish_transport(false, "weapon genesis"); return
	actor.ammo_inventory["fire_arrow"] = 1
	var target := {"type": "ground", "cell": [15, 15]}
	var issued := lab.issue_fire_order(actor.person_id, actor, target, "FIRE_ARROW")
	if not _check_fire(issued.ok and actor.ranged_enabled, "Original controller admits one unlaunched Fire Arrow order"): _finish_transport(false, "order genesis"); return
	if not _check_fire(lab.fire_projectiles.is_empty() and lab.fire_reservations.is_empty()
		and float(lab.terrain.site.combat_left) <= 0.0, "No projectile, reservation or combat interval is fabricated before saving"): _finish_transport(false, "quiescent barrier"); return
	var captured: Dictionary = lab.site_controller._capture_for_save()
	if not _check_fire(captured.ok, "Original Site Controller captures the same actor and holder state"): _finish_transport(false, "controller capture"); return
	var path := "user://site_fire_transport_%d.json" % Time.get_ticks_usec()
	var saved: Dictionary = lab.site_controller.save_to(path)
	if not _check_fire(saved.ok, "Store writes original Fire transport: " + str(saved)): _finish_transport(false, "Store save"); return
	var loaded := SiteStore.load_site(path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if not _check_fire(loaded.ok, "Store validates original owner references before bind: " + str(loaded)): _finish_transport(false, "Store load"); return
	var saved_transport: Dictionary = loaded.data.site.get("fire_transport", {})
	if not _check_fire(saved_transport.get("orders", {}).has(-actor.person_id), "JSON load preserves the original actor command owner"): _finish_transport(false, "owner snapshot"); return
	var serial := int(saved_transport.orders[-actor.person_id].serial)
	lab.bind_terrain(loaded.data)
	var restored_actor := lab.character
	if not _check_fire(lab.terrain == loaded.data and restored_actor.ranged_enabled
		and restored_actor.ranged_order_serial == serial and restored_actor.ranged_target == target
		and restored_actor.ranged_ammo_mode == "FIRE_ARROW" and restored_actor.ammo_inventory.fire_arrow == 1,
		"Bind restores the original enabled order, target, generation and unpaid personal ammo"): _finish_transport(false, "Lab restore"); return
	var launched := false
	for _tick: int in range(60):
		if not _shared(lab): _finish_transport(false, "launch shared barrier"); return
		if not lab.fire_projectiles.is_empty(): launched = true; break
	if not _check_fire(launched, "Original shared step releases a paid Fire Arrow into the sole Lab flight pool"):
		_finish_transport(false, "flight genesis"); return
	var flight_id := int(lab.fire_projectiles[0].projectile_id)
	var live_transport: Dictionary = lab.capture_fire_transport()
	if not _check_fire(live_transport.ok, "Lab serializes the live paid flight as strict JSON: " + str(live_transport)):
		_finish_transport(false, "flight transport capture"); return
	var checked_live_transport: Dictionary = SiteStore._validate_fire_transport_snapshot(lab.terrain, {}, live_transport.state)
	if not _check_fire(checked_live_transport.ok, "Store accepts the exact captured in-flight transport: " + str(checked_live_transport)):
		_finish_transport(false, "flight transport validation"); return
	var path_after_release := "user://site_fire_transport_flight_%d.json" % Time.get_ticks_usec()
	var flight_save: Dictionary = lab.site_controller._capture_for_save()
	if not _check_fire(flight_save.ok, "Controller captures the paid in-flight Fire Arrow at its completed barrier"): _finish_transport(false, "flight capture"); return
	var flight_guard: Dictionary = lab.site_controller.supply_save_guard(false, true)
	if not _check_fire(flight_guard.ok, "Original Controller/Fire guards admit Fire-only flight state with no legacy ranged flight"): _finish_transport(false, "flight save guard"); return
	var saved_flight: Dictionary = lab.site_controller.save_to(path_after_release)
	if not _check_fire(saved_flight.ok, "Store writes the in-flight Fire Arrow and its original owner transport: " + str(saved_flight)):
		_finish_transport(false, "flight Store save"); return
	var wire_read: Dictionary = SiteStore._read(path_after_release)
	var wire_state: Dictionary = wire_read.get("payload", {}).get("state", {})
	var wire_transport: Dictionary = wire_state.get("fire_transport", {})
	var wire_flights: Variant = wire_transport.get("projectiles", [])
	var wire_flight: Dictionary = wire_flights[0] if wire_flights is Array and not wire_flights.is_empty() and wire_flights[0] is Dictionary else {}
	var wire_coordinates_ok: bool = not wire_flight.is_empty() and wire_flight.get("source_cell") is Array \
		and wire_flight.source_cell.size() == 2
	for field: String in ["origin", "position", "velocity"]:
		var coordinate: Variant = wire_flight.get(field)
		wire_coordinates_ok = wire_coordinates_ok and coordinate is Array and coordinate.size() == 3
	if not _check_fire(wire_read.ok and wire_coordinates_ok, "Store keeps flight vectors in canonical JSON array form"):
		_finish_transport(false, "flight wire coordinates"); return
	var legacy_transport: Dictionary = wire_transport.duplicate(true)
	var legacy_flight: Dictionary = legacy_transport.projectiles[0]
	for field: String in ["origin", "position", "velocity"]:
		var components: Array = wire_flight[field]
		legacy_flight[field] = str(Vector3(float(components[0]), float(components[1]), float(components[2])))
	var source_cell: Array = wire_flight.source_cell
	legacy_flight.source_cell = str(Vector2i(int(source_cell[0]), int(source_cell[1])))
	var legacy_checked: Dictionary = SiteStore._validate_fire_transport_snapshot(lab.terrain, {}, legacy_transport)
	if not _check_fire(legacy_checked.ok and legacy_checked.state.projectiles.size() == 1,
		"Store reads legacy Godot-string flight coordinates before binding"):
		_finish_transport(false, "legacy flight coordinates"); return
	var loaded_flight := SiteStore.load_site(path_after_release)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path_after_release))
	if not _check_fire(loaded_flight.ok, "Store validates the in-flight Fire Arrow before rebinding: " + str(loaded_flight)):
		_finish_transport(false, "flight Store load"); return
	var expected_flight: Dictionary = SiteStore._validate_fire_transport_snapshot(loaded_flight.data, {},
		loaded_flight.data.site.get("fire_transport", {}))
	if not _check_fire(expected_flight.ok and expected_flight.state.projectiles.size() == 1
		and int(expected_flight.state.projectiles[0].projectile_id) == flight_id,
		"JSON preserves the paid projectile identity and flight state: id=%d snapshot=%s" % [flight_id, str(expected_flight)]):
		_finish_transport(false, "flight snapshot"); return
	lab.bind_terrain(loaded_flight.data)
	var rebound := lab.capture_fire_transport()
	var actual_flight: Dictionary = SiteStore._validate_fire_transport_snapshot(lab.terrain, {}, rebound.get("state", {}))
	if not _check_fire(rebound.ok and actual_flight.ok and lab.fire_projectiles.size() == 1
		and int(lab.fire_projectiles[0].projectile_id) == flight_id
		and JSON.stringify(expected_flight.state) == JSON.stringify(actual_flight.state)
		and SiteStore.fire_event_guard(lab.terrain).ok,
		"Original Lab restores the same in-flight Fire Arrow and passes the next Store guard"):
		_finish_transport(false, "flight restore"); return
	var controller_path := "user://site_fire_controller_flight_%d.json" % Time.get_ticks_usec()
	var controller_saved: Dictionary = lab.site_controller.save_to(controller_path)
	if not _check_fire(controller_saved.ok, "Original Controller admits and checkpoints the restored paid flight: " + str(controller_saved)):
		_finish_transport(false, "Controller flight save"); return
	lab.site_controller.save_path = controller_path
	var ui: SiteController = lab.site_controller
	var input_anchor := Vector2i(7, 9)
	var input_direction := Vector2i.UP
	ui._facing_order_anchor = input_anchor
	ui._facing_preview_direction = input_direction
	lab.exchange_enabled = false
	var live_before_mode_reject: PackedByteArray = var_to_bytes([lab.terrain.site, actor.capture_state(), lab.fire_projectiles,
		lab.fire_reservations, lab.fire_action_cursor, lab._fire_unsaved, lab.exchange_enabled])
	var file_before_mode_reject: PackedByteArray = FileAccess.get_file_as_bytes(controller_path)
	var mode_rejected: Dictionary = ui.load_from(controller_path)
	var live_after_mode_reject: PackedByteArray = var_to_bytes([lab.terrain.site, actor.capture_state(), lab.fire_projectiles,
		lab.fire_reservations, lab.fire_action_cursor, lab._fire_unsaved, lab.exchange_enabled])
	var mode_reject_preserved: bool = not mode_rejected.ok and str(mode_rejected.code) == "UNSUPPORTED_AMMO" \
		and is_same(lab.terrain, loaded_flight.data) and live_after_mode_reject == live_before_mode_reject \
		and FileAccess.get_file_as_bytes(controller_path) == file_before_mode_reject \
		and ui._facing_order_anchor == input_anchor and ui._facing_preview_direction == input_direction
	if not _check_fire(mode_reject_preserved, "Controller preflights an incompatible saved Fire order before clearing input or the live paid flight: "
		+ str(mode_rejected) + " live_unchanged=" + str(live_after_mode_reject == live_before_mode_reject)
		+ " file_unchanged=" + str(FileAccess.get_file_as_bytes(controller_path) == file_before_mode_reject)
		+ " facing=" + str([ui._facing_order_anchor, ui._facing_preview_direction])):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(controller_path))
		_finish_transport(false, "unsupported-mode atomic preflight"); return
	lab.exchange_enabled = true
	var controller_loaded: Dictionary = lab.site_controller.load_from(controller_path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(controller_path))
	var controller_transport: Dictionary = lab.capture_fire_transport()
	if not _check_fire(controller_loaded.ok and is_same(lab.terrain, controller_loaded.data)
		and controller_transport.ok and lab.fire_projectiles.size() == 1
		and int(lab.fire_projectiles[0].projectile_id) == flight_id and SiteStore.fire_event_guard(lab.terrain).ok,
		"Original Controller load_from atomically rebinds the checkpointed in-flight Fire Arrow"):
		_finish_transport(false, "Controller flight load"); return
	_finish_transport(not fire_failed, "P5 original SiteStore/Controller/Actor order and paid flight round trips; jobs, navigation, Native and performance remain open")
