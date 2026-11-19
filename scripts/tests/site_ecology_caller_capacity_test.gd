extends "res://scripts/tests/site_ecology_contract_test.gd"
## E03/04/07 supplement through original caller, source and construction owners.
## Small source/land fixtures are endpoints, not generated-geography acceptance.

const ORIGINAL_SCENE = preload("res://scenes/terrain_lab/TerrainLab.tscn")
const Settlement = preload("res://scripts/terrain_lab/site_settlement.gd")

func _initialize() -> void:
	_deadline = Time.get_ticks_msec() + 120000
	_run.call_deferred()

func _run() -> void:
	for caller: String in ["manual", "worker", "army"]:
		_caller_quota_and_claims(caller)
		await process_frame
		_caller_revalidates_policy(caller)
		await process_frame
	_overlapping_zone_and_mode_history()
	await process_frame
	_completed_land_capacity_and_rearm()
	assert(_groups == 8)
	TerrainArmy.release_contact_source()
	print("SITE_ECOLOGY_CALLER_CAPACITY_PASS groups=8 original_callers=manual,worker,Army claims_exclusive=true partial_batch=1 source_history_shared=true policy_revalidated=true completed_road_capacity=true demolition_rearm=true existing_deadline_preserved=true; no GPU, cold replay, deletion UI, generated geography or performance claim")
	quit(0)

func _caller_lab() -> TerrainLab:
	var data := _synthetic(Env.Kind.FISH, 20)
	var lab := ORIGINAL_SCENE.instantiate() as TerrainLab
	assert(lab != null)
	lab.restore_only = true
	lab.npc = TerrainTestNPC.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	lab.bind_terrain(data)
	assert(lab.terrain == data, 'Original PackedScene did not bind the caller source fixture')
	lab.restore_only = false
	lab.site_controller._auto_save_blocked = true
	lab.set_process(false)
	lab.set_process_input(false)
	lab.set_process_unhandled_input(false)
	for actor: TerrainTestCharacter in lab.combat_actors:
		actor.set_process(false)
		if actor.editor != null:
			actor.editor.set_process(false)
			actor.editor.animation_player.pause()
	assert(lab.character.place(Vector2i(12, 10), true))
	assert(lab.npc.place(Vector2i(13, 10), true))
	lab.site_controller.release_worker()
	lab.site_controller.source_key = "eco_source"
	# Reach a legal N5 / K20 non-resting history using real harvest and due events.
	assert(Settlement.set_ecology_modes(lab, lab.controlled_person_id(), ["eco_source"], "general").ok)
	for _batch in range(5):
		assert(Runtime.harvest(data, "eco_source", lab.character.terrain_cell, data.site.manual.cargo).ok)
	assert(int(Env.resource(data, "eco_source").remaining) == 10)
	assert(Settlement.set_ecology_modes(lab, lab.controlled_person_id(), ["eco_source"], "sustainable").ok)
	Runtime.advance(data, 120.0)
	assert(int(Env.resource(data, "eco_source").remaining) == 11)
	for _batch in range(3):
		assert(Runtime.harvest(data, "eco_source", lab.character.terrain_cell, data.site.manual.cargo).ok)
	assert(int(Env.resource(data, "eco_source").remaining) == 5 and not bool(Env.ecology_info(data, "eco_source").resting))
	var depot := data.cell_from_index(int(data.site.depot_cell))
	assert(lab.character.place(depot, true))
	assert(Runtime.deposit(data, data.site.manual.cargo, depot).ok)
	assert(lab.character.place(Vector2i(12, 10), true))
	var army := TerrainArmy.new()
	army.team_id = 1
	army.roster_size = 2
	army.exchange_enabled = true
	lab.add_child(army)
	army.set_process(false)
	var cells: Array[Vector2i] = [Vector2i(10, 10), Vector2i(14, 10)]
	# Reuse this scene's raw animations; the original enable_combat assertion still admits the source.
	TerrainArmy.load_contact_source(lab.character.editor)
	assert(army.deploy_at(data, null, null, cells) and army.enable_combat(false))
	for row: Dictionary in army.combat_units:
		row["cargo"] = {}
		row["item_state"] = Runtime.new_item_state("person:" + str(row.person_id))
	lab.combat_armies.append(army)
	lab.site_controller.work_team.init(lab)
	assert(Runtime.add_zone(data, Rect2i(12, 9, 5, 1), Env.Kind.FISH).ok)
	return lab

func _control(lab: TerrainLab, identity: int) -> void:
	# Original stored identity endpoint; this does not test control handoff UI.
	lab.terrain.site["controlled_person_id"] = identity

func _army_identity(lab: TerrainLab) -> int:
	return lab.combat_armies.back().combat_identity(1)

func _task(lab: TerrainLab, caller: String) -> Dictionary:
	if caller == "army": return lab.combat_armies.back().combat_units[1].get("work_task", {})
	return lab.terrain.site[caller]

func _cargo(lab: TerrainLab, caller: String) -> Dictionary:
	if caller == "army": return lab.combat_armies.back().combat_units[1].cargo
	return lab.terrain.site[caller].cargo

func _begin_caller(lab: TerrainLab, caller: String) -> bool:
	var controller: SiteController = lab.site_controller
	if caller == "army":
		_control(lab, _army_identity(lab))
		controller.manual_work()
	elif caller == "manual":
		_control(lab, lab.character.person_id)
		controller.manual_work()
	else:
		_control(lab, lab.character.person_id)
		controller.enable_worker()
		var inputs := controller._prepare_original_work_inputs()
		assert(bool(inputs.worker_ready) and not bool(inputs.manual_ready))
	var task := _task(lab, caller)
	assert(str(task.get("target", "")) == "eco_source" and str(task.action) == "harvest", caller)
	return true

func _advance_caller(lab: TerrainLab, minutes: float) -> void:
	var controller: SiteController = lab.site_controller
	var inputs := controller._prepare_original_work_inputs()
	Runtime.advance(lab.terrain, minutes, bool(inputs.worker_ready), bool(inputs.manual_ready),
		controller.reserves_cell, Callable(), func(seconds: float) -> void: controller.work_team.advance(seconds),
		int(inputs.worker_limit), int(inputs.manual_limit), 1.0, int(inputs.worker_faction))

func _all_cargo(lab: TerrainLab) -> PackedByteArray:
	return var_to_bytes([lab.terrain.site.manual.cargo, lab.terrain.site.worker.cargo,
		lab.combat_armies.back().combat_units[0].cargo, lab.combat_armies.back().combat_units[1].cargo])

func _preflight_caller(lab: TerrainLab, caller: String) -> Dictionary:
	var task := _task(lab, caller)
	if str(task.get("target", "")).is_empty(): return Runtime.fail("NO_TARGET")
	if caller == "manual":
		# Original manual state has no worker mode/work_cell fields. Its actual
		# preflight is harvest(preview), as used by the original Runtime._work.
		return Runtime.harvest(lab.terrain, str(task.target), lab.character.terrain_cell, task.cargo, str(task.action), true)
	var identity := _army_identity(lab) if caller == "army" else lab.npc.person_id
	return Runtime.work_preflight(lab.terrain, task, _cargo(lab, caller), 20, 1, identity, lab.site_controller.reserves_cell)

func _assert_claims_exclusive(lab: TerrainLab, caller: String) -> bool:
	var controller: SiteController = lab.site_controller
	var before := _all_cargo(lab)
	var change := var_to_bytes(lab.terrain.site.changes)
	if caller != "army":
		_control(lab, _army_identity(lab))
		var row_before := var_to_bytes(lab.combat_armies.back().combat_units[1].get("work_task", {}))
		assert(controller.work_team.begin_manual(_army_identity(lab), "eco_source").code == "BUSY")
		assert(var_to_bytes(lab.combat_armies.back().combat_units[1].get("work_task", {})) == row_before)
	if caller != "manual":
		_control(lab, lab.character.person_id)
		controller.manual_work()
		assert(str(lab.terrain.site.manual.target).is_empty(), "Formal manual caller must respect original worker/Army source claim")
	if caller != "worker":
		_control(lab, lab.character.person_id)
		controller.enable_worker()
		controller._prepare_original_work_inputs()
		assert(str(lab.terrain.site.worker.target).is_empty(), "Original automatic worker must exclude the original source claim")
		controller.release_worker()
	assert(_all_cargo(lab) == before and var_to_bytes(lab.terrain.site.changes) == change)
	_control(lab, _army_identity(lab) if caller == "army" else lab.character.person_id)
	return true

func _caller_quota_and_claims(caller: String) -> void:
	var lab := _caller_lab()
	var produced := int(lab.terrain.site.total_produced)
	var base := var_to_bytes(lab.terrain.resource_base)
	assert(_begin_caller(lab, caller))
	assert(_assert_claims_exclusive(lab, caller))
	_advance_caller(lab, Runtime.resource_work_minutes(Env.Kind.FISH, "harvest") + 0.25)
	assert(_cargo(lab, caller) == {"fish": 1}, caller + " did not commit the shared one-unit quota")
	assert(int(lab.terrain.site.total_produced) == produced + 1)
	var info := Env.ecology_info(lab.terrain, "eco_source")
	assert(int(info.remaining) == 4 and bool(info.resting) and int(info.takeable) == 0)
	assert(var_to_bytes(lab.terrain.resource_base) == base)
	var change := var_to_bytes(lab.terrain.site.changes)
	var cargo := _all_cargo(lab)
	var revision := lab.terrain.environment_revision
	for cell: Vector2i in [Vector2i(12, 10), Vector2i(13, 10), Vector2i(14, 10)]:
		assert(Runtime.harvest(lab.terrain, "eco_source", cell, {}, "harvest", true).code == "ECOLOGY_RESTING")
	assert(var_to_bytes(lab.terrain.site.changes) == change and _all_cargo(lab) == cargo and lab.terrain.environment_revision == revision)
	lab.free()
	_groups += 1

func _caller_revalidates_policy(caller: String) -> void:
	var lab := _caller_lab()
	assert(_begin_caller(lab, caller))
	_advance_caller(lab, 1.0)
	var task := _task(lab, caller)
	assert(_preflight_caller(lab, caller).ok)
	assert(float(task.progress) > 0.0 and _cargo(lab, caller).is_empty())
	assert(Settlement.set_ecology_modes(lab, lab.controlled_person_id(), ["eco_source"], "protected").ok)
	var change := var_to_bytes(lab.terrain.site.changes)
	var cargo := _all_cargo(lab)
	var produced := int(lab.terrain.site.total_produced)
	_advance_caller(lab, 4.0)
	assert(_all_cargo(lab) == cargo and int(lab.terrain.site.total_produced) == produced, "Old " + caller + " preflight cannot authorize a later protected-source commit")
	assert(var_to_bytes(lab.terrain.site.changes) == change and int(Env.resource(lab.terrain, "eco_source").remaining) == 5)
	assert(not _preflight_caller(lab, caller).ok)
	lab.free()
	_groups += 1

func _overlapping_zone_and_mode_history() -> void:
	var lab := _caller_lab()
	var data: TerrainData = lab.terrain
	var controller: SiteController = lab.site_controller
	assert(Runtime.add_zone(data, Rect2i(12, 9, 3, 1), Env.Kind.FISH).ok)
	assert(_begin_caller(lab, "worker"))
	_advance_caller(lab, 4.25)
	assert(data.site.worker.cargo == {"fish": 1} and int(Env.resource(data, "eco_source").remaining) == 4)
	var history := [int(Env.resource(data, "eco_source").remaining), bool(Env.ecology_info(data, "eco_source").resting), int(Env.resource(data, "eco_source").next_recovery)]
	var cargo := _all_cargo(lab)
	controller.update_ui()
	assert(controller.zones.get_child_count() == 2)
	for node: Node in controller.zones.get_children():
		(node as CheckButton).button_pressed = false # Existing UI signal owns zone disable.
	assert(not bool(data.site.zones[0].active) and not bool(data.site.zones[1].active))
	# There is no delete_zone command in the current product. Exercise removal
	# of the original serialized zone list as an explicitly bounded endpoint.
	data.site.zones.clear()
	controller.update_ui()
	for mode: String in ["protected", "general", "sustainable"]:
		assert(Settlement.set_ecology_modes(lab, lab.controlled_person_id(), ["eco_source", "eco_source"], mode).ok)
		var resource := Env.resource(data, "eco_source")
		assert([int(resource.remaining), bool(Env.ecology_info(data, "eco_source").resting), int(resource.next_recovery)] == history)
		assert(_all_cargo(lab) == cargo)
	assert(Env.ecology_info(data, "eco_source").mode == "sustainable" and int(Env.ecology_info(data, "eco_source").takeable) == 0)
	assert(Runtime.add_zone(data, Rect2i(12, 9, 5, 1), Env.Kind.FISH).ok)
	controller.enable_worker()
	controller._prepare_original_work_inputs()
	assert(str(data.site.worker.target) != "eco_source", "Replacing zones cannot reset the original source resting latch")
	lab.free()
	_groups += 1

func _complete_road(data: TerrainData, cells: Array[int]) -> String:
	var built := Runtime.request_build(data, "road", cells)
	assert(built.ok, str(built))
	var key := str(built.feature)
	var feature: Dictionary = data.site.features[key]
	assert(feature.clearing.is_empty(), "Population habitat land work must not clear the population source")
	Runtime.assign_task(data, Runtime.ok("original construction endpoint", {"target": "feature:" + key,
		"action": "construct", "cell": int(feature.entrance)}))
	data.site.worker.cell = int(feature.entrance)
	data.site.worker.mode = "work"
	Runtime.advance(data, float(feature.work), true)
	assert(str(data.site.features[key].stage) == "complete" and is_equal_approx(float(data.site.features[key].progress), float(data.site.features[key].work)))
	return key

func _completed_land_capacity_and_rearm() -> void:
	var data := _synthetic(Env.Kind.WILDLIFE, 5)
	var base := var_to_bytes(data.resource_base)
	var cells: Array[int] = [int(data.resource_base.eco_source.cells[1]), int(data.resource_base.eco_source.cells[2]), int(data.resource_base.eco_source.cells[3])]
	var road := _complete_road(data, cells)
	assert(Env.habitat_capacity(data, "eco_source") == 2)
	assert(Runtime.ecology_set_modes(data, ["eco_source"], "general").ok)
	var cargo := {}
	for _batch in range(4):
		assert(Runtime.harvest(data, "eco_source", Env.work_cells(data, "eco_source")[0], cargo).ok)
	assert(int(Env.resource(data, "eco_source").remaining) == 1)
	var produced := int(data.site.total_produced)
	var held := var_to_bytes(cargo)
	var due := int(Env.resource(data, "eco_source").next_recovery)
	assert(due == ceili(Runtime.now(data)) + 1440)
	data.site.minute = due - 1 # Due-event boundary, not an accelerated full-cycle test.
	Runtime.advance(data, 1.0)
	assert(int(Env.resource(data, "eco_source").remaining) == 2 and int(Env.resource(data, "eco_source").next_recovery) == -1)
	var inventory: Dictionary = data.site.inventory.duplicate(true)
	assert(Runtime.cancel_feature(data, road).ok)
	assert(Env.habitat_capacity(data, "eco_source") == 5 and int(Env.resource(data, "eco_source").remaining) == 2)
	assert(int(Env.resource(data, "eco_source").next_recovery) == ceili(Runtime.now(data)) + 1440, "Demolition must rearm an under-full population with no old deadline")
	assert(data.site.inventory == inventory, "A completed road cannot refund materials or produce animals on demolition")
	due = int(Env.resource(data, "eco_source").next_recovery)
	var second := _complete_road(data, cells)
	assert(int(Env.resource(data, "eco_source").next_recovery) == due)
	assert(Runtime.cancel_feature(data, second).ok)
	assert(int(Env.resource(data, "eco_source").next_recovery) == due, "Later construction/demolition must preserve an already scheduled recovery")
	assert(var_to_bytes(cargo) == held and int(data.site.total_produced) == produced and var_to_bytes(data.resource_base) == base)
	_groups += 1
