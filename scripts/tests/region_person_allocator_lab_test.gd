extends "res://scripts/tests/region_initial_world_transaction_test.gd"
## Reuse genuine pinned geography, original Lab birth, IO faults and cold reopen.
## The inherited 180-second inner deadline remains unchanged. No Godot run here.

func _run() -> void:
	var source: RegionData = _fixed_source()
	if source == null:
		_finish()
		return
	var lab: TerrainLab = _source_lab("person_allocator")
	if lab == null:
		_finish()
		return
	var world: String = _world("person_allocator")
	var born: Dictionary = lab.site_controller.open_fixed_world(manifest_path, world, SLOT, START, true, Artisans.PRIMARY)
	if _check(born.ok, "Real Controller births original player and artisan Army", born):
		_freeze(lab)
		var slot: RegionSaveSlot = lab.site_controller.region_slot
		var original: Dictionary = RegionTravel._body_records(lab.terrain.site)
		var allocator: Dictionary = slot.person_allocator_view()
		_check(slot.control.has("person_allocator") and allocator.locations.size() == original.size(), "Original first Region commit atomically indexes every real body")
		for id: int in original:
			var reference: Dictionary = slot.person_reference(id)
			var resolved: Dictionary = slot.resolve_person_reference(reference)
			_check(resolved.ok and resolved.location.id == lab.terrain.site.id, "Every original birth ID resolves to its original Site", id)
		var selected: Dictionary = slot._load_checked(slot.site_path(START), START)
		if not _check(selected.ok, "Published original body cold-loads", selected):
			_finish()
			return
		var cold: Dictionary = _cold_reopen(source, world, Artisans.PRIMARY, _facts(selected.data.site))
		if not cold.is_empty():
			_check(cold.slot.person_allocator_view() == allocator, "Cold reload preserves exact World allocator without another generation")
		var untouched: PackedByteArray = var_to_bytes(slot.person_allocator_view())
		var other: Dictionary = slot.open_site(Vector2i(1, 0), false)
		if _check(other.ok, "Real fresh travel destination opens", other):
			_check(other.data.site.get("actors", {}).is_empty(), "Travel destination creates no placeholder people")
			var private_data: TerrainData = Env.navigation_for_state(other.data, other.data.site.duplicate(true))
			var second_birth: Dictionary = lab.prepare_fresh_initial_population(private_data)
			if _check(second_birth.ok, "Original disposable Actor birth consumes the same Slot allocator on another Site", second_birth):
				var second_id: int = int(second_birth.data.site.actors.player.person_id)
				_check(not original.has(second_id) and second_id >= int(allocator.next_person_id), "Second Site gets a globally new original body ID")
			var invalid_data: TerrainData = Env.navigation_for_state(other.data, other.data.site.duplicate(true))
			invalid_data.set_meta(&"world_person_allocator", Callable())
			var before_invalid: PackedByteArray = var_to_bytes(slot.person_allocator_view())
			var invalid_army: Array[int] = lab._allocate_army_person_ids_for(1, invalid_data, [], [])
			var invalid_player: int = lab._allocate_initial_person_id(invalid_data)
			_check(invalid_army.is_empty() and invalid_player == -1 and var_to_bytes(slot.person_allocator_view()) == before_invalid, "Invalid callback refuses both real allocation entry points without touching the Slot")
		_check(var_to_bytes(allocator) == untouched, "Detached original committed view is immutable across later reservations")
	lab.free()
	if born.ok: _external_slot_generation(source, world)
	_world_ticket_scope(source)
	# These inherited cases inject only original IO and verify same-born retries.
	_failure_resume(source, "site")
	_failure_resume(source, "commit")
	_finish()

func _world_ticket_scope(source: RegionData) -> void:
	# Real open_map replaces this independent Slot's world, with identical geography.
	# No live Lab bind ownership or private allocator fields are modified.
	var slot: RegionSaveSlot = RegionSaveSlot.new()
	var context: Dictionary = {"starting_site": [0, 0], "initial_scenario_id": ""}
	var opened: Dictionary = slot.open_map(source, _world("ticket-a"), SLOT, true, context)
	if not _check(opened.ok, "First ticket world formally opens", opened): return
	var first: Dictionary = slot.open_site(START, false)
	if not _check(first.ok, "First original Site supplies allocation capability", first): return
	var old_callback: Callable = first.data.get_meta(&"world_person_allocator")
	var old_ids: Array[int] = old_callback.call(1, first.data, 1)
	if not _check(old_ids == [1], "Old callback was valid before the switch"): return
	var switched: Dictionary = slot.open_map(source, _world("ticket-b"), SLOT, true, context)
	if not _check(switched.ok, "Same Slot formally opens another world with identical geography", switched): return
	var second: Dictionary = slot.open_site(START, false)
	if not _check(second.ok, "Second original Site supplies current capability", second): return
	var current_callback: Callable = second.data.get_meta(&"world_person_allocator")
	var current_ids: Array[int] = current_callback.call(1, second.data, 1)
	if not _check(current_ids == [1], "New world has its own working allocator"): return
	var before: PackedByteArray = var_to_bytes(slot.person_allocator_view())
	var stale: Array[int] = old_callback.call(1, second.data, 1)
	_check(stale.is_empty() and var_to_bytes(slot.person_allocator_view()) == before, "Old callback rejects even a valid new-world body without consuming new IDs")
	var foreign_body: Array[int] = current_callback.call(1, first.data, 1)
	_check(foreign_body.is_empty() and var_to_bytes(slot.person_allocator_view()) == before, "Current callback rejects the old-world body without consuming new IDs")

func _finish(reason: String = "") -> void:
	if finished: return
	print("REGION_PERSON_ALLOCATOR_LAB_", "PASS" if failures.is_empty() and reason.is_empty() else "FAILED")
	super(reason)

func _external_slot_generation(source: RegionData, world: String) -> void:
	var stale_slot: RegionSaveSlot = RegionSaveSlot.new()
	var publisher: RegionSaveSlot = RegionSaveSlot.new()
	var refreshable: RegionSaveSlot = RegionSaveSlot.new()
	var opened_a: Dictionary = stale_slot.open_map(source, world, SLOT)
	var opened_b: Dictionary = publisher.open_map(source, world, SLOT)
	var opened_c: Dictionary = refreshable.open_map(source, world, SLOT)
	if not _check(opened_a.ok and opened_b.ok and opened_c.ok, "Three independent original Slots open one committed folder"): return
	var a: Dictionary = stale_slot.open_site(START)
	var b: Dictionary = publisher.open_site(START)
	if not _check(a.ok and b.ok, "Both original Slots admit real committed bodies"): return
	var old_callback: Callable = a.data.get_meta(&"world_person_allocator")
	var publish_callback: Callable = b.data.get_meta(&"world_person_allocator")
	var checkpoint: Dictionary = stale_slot.person_allocation_checkpoint()
	var old_ids: Array[int] = old_callback.call(1, a.data, 1)
	var new_ids: Array[int] = publish_callback.call(2, b.data, 1)
	if not _check(old_ids.size() == 1 and new_ids.size() == 2, "Both pending allocators initially reserve against the same generation"): return
	var before: PackedByteArray = var_to_bytes(stale_slot.person_allocator_view())
	var committed: Dictionary = publisher._publish(publisher._marker.sites, publisher.control.duplicate(true), str(publisher._marker.transfer_token), publisher._marker.journey)
	if not _check(committed.ok, "Second original Slot publishes allocator through real generation CAS", committed): return
	var reopened: Dictionary = stale_slot.open_map(source, world, SLOT)
	_check(not reopened.ok and reopened.code == "PERSON_ALLOCATION_CONFLICT", "Same-scope reopen rejects old pending reservations after an external commit", reopened)
	var stale_ids: Array[int] = old_callback.call(1, a.data, 1)
	var rolled: bool = stale_slot.rollback_person_allocation(checkpoint)
	var rejected_publish: Dictionary = stale_slot._publish(stale_slot._marker.sites, stale_slot.control.duplicate(true), str(stale_slot._marker.transfer_token), stale_slot._marker.journey)
	_check(stale_ids.is_empty() and not rolled and not rejected_publish.ok and rejected_publish.code == "PERSON_ALLOCATION_CONFLICT" and var_to_bytes(stale_slot.person_allocator_view()) == before, "Allocation/publish/rollback all reject cross-generation pending state without deleting it")
	var refreshed: Dictionary = refreshable.open_map(source, world, SLOT)
	_check(refreshed.ok and refreshable.person_allocator_view() == publisher.person_allocator_view(), "Same-scope reopen with no reservations refreshes from the new committed allocator", refreshed)
