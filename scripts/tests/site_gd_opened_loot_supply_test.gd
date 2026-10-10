extends "res://scripts/tests/site_building_ui_test.gd"
## Original Runtime transfer/private Supply component, not a point/Native test.
const Sustain = preload("res://scripts/terrain_lab/site_sustain.gd")

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 180000
	_run.call_deferred()

func _run() -> void:
	var data: TerrainData = _building_fixture()
	var lab: TerrainLab = _building_lab(data)
	var controller: SiteController = lab.site_controller
	var actions: SitePersonActions = controller.person_actions
	var source_person: Dictionary = actions._person(int(lab.npc.person_id))
	var receiver: Dictionary = actions._person(int(lab.character.person_id))
	assert(not source_person.is_empty() and not receiver.is_empty())
	# Explicit finite starting opened food in the EXISTING private Supply map.
	var original: Dictionary = Sustain.create(Runtime.now(data) * 60.0)
	assert(Sustain.add_members(original, controller.captivity_supply._all_members(), [int(source_person.person_id)]).ok)
	original.open_rations = 3.0
	data.site.person_supply = {str(int(source_person.person_id)): original}
	var dropped: Dictionary = Runtime.leave_ground_loot(data, source_person.holder, source_person.cargo, int(source_person.person_id), source_person.cell,
		"cargo", {}, [], int(source_person.holder.version), original, 3.0)
	assert(dropped.ok and float(original.open_rations) == 0.0)
	var source: Dictionary = data.site.ground_loot[str(dropped.container_id)]
	var before: PackedByteArray = var_to_bytes([source, receiver.holder, receiver.cargo, data.site.person_supply])
	var source_only: Dictionary = controller.prepare_received_opened_food(int(receiver.person_id), 2.0, {}, true)
	assert(source_only.ok and controller.validate_received_opened_food(source_only, false).ok)
	assert(not controller.validate_received_opened_food(source_only).ok, "Pure source-only food is not a publisher/completed loot")
	assert(var_to_bytes([source, receiver.holder, receiver.cargo, data.site.person_supply]) == before)
	var transfer: Dictionary = Runtime.prepare_loot_transfer(data, source, source.cargo, receiver.holder, receiver.cargo, {}, [], int(source.version), int(receiver.holder.version), 2.0)
	var food: Dictionary = controller.prepare_received_opened_food(int(receiver.person_id), 2.0, {})
	assert(transfer.ok and food.ok and Runtime.validate_prepared_loot_transfer(transfer).ok and controller.validate_received_opened_food(food).ok)
	var forged: Dictionary = food.duplicate(false)
	forged.state = food.state.duplicate(true)
	forged.state.open_rations = 999.0
	assert(not controller.validate_received_opened_food(forged).ok)
	var source_version: int = int(source.version)
	var destination_version: int = int(receiver.holder.version)
	assert(Runtime.publish_prepared_loot_transfer(transfer).ok)
	controller.publish_received_opened_food(food)
	var received: Dictionary = controller._personal_opened_food(int(receiver.person_id))
	assert(float(source.open_rations) == 1.0 and float(received.open_rations) == 2.0 and Sustain._ids(received) == [int(receiver.person_id)])
	assert(int(source.version) == source_version + 1 and int(receiver.holder.version) == destination_version + 1)
	assert(not Runtime.validate_prepared_loot_transfer(transfer).ok and not controller.validate_received_opened_food(food).ok, "Same completed transaction cannot pay/feed twice")
	var stale: Dictionary = controller.prepare_received_opened_food(int(receiver.person_id), 1.0, received)
	var stale_transfer: Dictionary = Runtime.prepare_loot_transfer(data, source, source.cargo, receiver.holder, receiver.cargo, {}, [], int(source.version), int(receiver.holder.version), 1.0)
	assert(stale.ok and stale_transfer.ok)
	# A true intervening original transfer changes the private food owner.
	var second_drop: Dictionary = Runtime.leave_ground_loot(data, receiver.holder, receiver.cargo, int(receiver.person_id), receiver.cell,
		"cargo", {}, [], int(receiver.holder.version), received, 1.0)
	assert(second_drop.ok and float(received.open_rations) == 1.0)
	before = var_to_bytes([source, receiver.holder, receiver.cargo, data.site.person_supply])
	assert(not controller.validate_received_opened_food(stale).ok and not Runtime.validate_prepared_loot_transfer(stale_transfer).ok)
	assert(var_to_bytes([source, receiver.holder, receiver.cargo, data.site.person_supply]) == before, "Stale pure candidate refuses before any extra food/holder debit")
	controller.work_team.discard_prepared_interval()
	lab._clear_shared_work_step()
	lab.free()
	TerrainArmy.release_contact_source()
	print("GD_OPENED_LOOT_SUPPLY_COMPONENT_PASS scope=original_transfer_and_current_private_supply_only no_maincaller_native_world_claim")
	quit(0)
