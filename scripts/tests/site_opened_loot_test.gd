extends "res://scripts/tests/site_work_team_clock_test.gd"
## Original Lab common-clock integration; no replacement inventory or time skip.
const Sustain = preload("res://scripts/terrain_lab/site_sustain.gd")
const OPEN_SAVE := "res://.godot-temp/site_resources_contract/opened_loot.json"

func _ground_cell(lab: TerrainLab, identity: int) -> Vector2i:
	var person := lab.controlled_target() if identity == lab.controlled_person_id() else lab._combat_target(identity)
	for direction: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var cell: Vector2i = person.cell + direction
		if lab.terrain.can_step(person.cell, cell) and not lab.site_controller.reserves_cell(cell):
			return cell
	assert(false, "The original person needs a legal adjacent ground cell")
	return TerrainArmy.INVALID_CELL

func _drop(lab: TerrainLab, recipient: int, amount: float) -> String:
	# Explicit starting fixture food is placed through the real sparse transfer;
	# no whole grain is minted to represent a fractional meal.
	var original_open := {"open_rations": amount}
	var result := Runtime.leave_ground_loot(lab.terrain, lab.npc.item_state, lab.terrain.site.worker.cargo,
		lab.npc.person_id, _ground_cell(lab, recipient), "cargo", {}, [], int(lab.npc.item_state.version), original_open, amount)
	assert(result.ok and float(original_open.open_rations) == 0.0)
	return str(result.container_id)

func _open_loot(lab: TerrainLab, container_id: String) -> AcceptDialog:
	var controller: SiteController = lab.site_controller
	controller.select_cell(lab.terrain.cell_from_index(int(lab.terrain.site.ground_loot[container_id].cell)))
	_press(controller, "InspectLoot")
	var dialog := lab.get_node("SiteUI/PersonInventoryDialog") as AcceptDialog
	var choice := dialog.find_child("LootSource", true, false) as OptionButton
	var found := false
	for index: int in range(choice.item_count):
		if choice.get_item_metadata(index) == {"kind": "ground", "id": container_id}:
			choice.select(index)
			choice.item_selected.emit(index)
			found = true
	assert(found)
	var opened := dialog.find_child("LootOpenedFood", true, false) as CheckButton
	assert(not opened.disabled)
	opened.button_pressed = true
	return dialog

func _begin_ui(lab: TerrainLab, container_id: String, accepted: bool = true) -> void:
	var dialog := _open_loot(lab, container_id)
	(dialog.find_child("BeginLoot", true, false) as Button).pressed.emit()
	assert(lab.site_controller.person_actions.is_busy(lab.controlled_person_id()) == accepted, lab.site_controller.message.text)
	dialog.free()

func _finish_clock(lab: TerrainLab) -> void:
	var job: Dictionary = lab.site_controller.person_actions.job_for(lab.controlled_person_id())
	assert(not job.is_empty() and float(lab.terrain.site.combat_left) == 0.0)
	var seconds := float(job.duration) - float(job.elapsed)
	lab._process(seconds / 60.0)
	assert(not lab.site_controller.person_actions.is_busy(lab.controlled_person_id()), lab.site_controller.message.text)

func _assert_existing_meals(before: Dictionary, after: Dictionary) -> void:
	# Cohorts may compact while the same original people recover hunger. Compare
	# each person's paid credit, not the incidental grouping or a frozen clock.
	var prior_ids := Sustain._ids(before)
	var current_ids := Sustain._ids(after)
	prior_ids.sort()
	current_ids.sort()
	assert(prior_ids == current_ids)
	var seconds := float(after.at) - float(before.at)
	assert(seconds >= -Sustain.EPS)
	for prior: Dictionary in before.cohorts:
		assert(float(prior.meal_until) > float(after.at), "This short fixture must not cross the next real meal")
		for identity: int in prior.ids:
			var matches := 0
			for current: Dictionary in after.cohorts:
				if identity not in current.ids:
					continue
				matches += 1
				_near(float(current.coverage), float(prior.coverage), "existing original person's paid coverage")
				_near(float(current.meal_until), float(prior.meal_until), "existing original person's paid meal deadline")
				var deficit := 1.0 - float(prior.coverage)
				var hunger := float(prior.hunger) + seconds / Sustain.HOUR * deficit if deficit > 0.0 else maxf(0.0, float(prior.hunger) - seconds / Sustain.HOUR * 0.5)
				_near(float(current.hunger), hunger, "original common-clock hunger progress")
				assert(bool(current.bonus_paid) == (bool(prior.bonus_paid) if hunger > 0.0 else false))
				assert(bool(current.bonus_pending) == (bool(prior.bonus_pending) if hunger > 0.0 else false))
			assert(matches == 1, "Each original person retains one meal owner")

func _run() -> void:
	var lab := TerrainLab.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	lab.set_process(false)
	lab.character.set_process(false)
	lab.npc.set_process(false)
	lab.npc_retaliates = false
	var fixture := _work_fixture()
	var data: TerrainData = fixture.data
	lab.bind_terrain(data)
	var controller: SiteController = lab.site_controller
	controller._auto_save_blocked = true
	lab.npc.faction_id = lab.character.faction_id
	lab.npc.issue_command(TerrainTestNPC.Command.STOP)
	var team: TerrainArmy = lab.army
	team.roster_size = 3
	var cells: Array[Vector2i] = []
	cells.assign(fixture.cells)
	assert(team.deploy_at(data, lab.character, lab.npc, cells) and team.enable_combat(false))
	team.set_process(false)
	team.faction_id = lab.character.faction_id
	team.settle_combat_command()
	controller.initialize_team_items(team)
	data.site.army_next_team = team.team_id + 1
	var player_id := lab.character.person_id
	var row_id := team.combat_identity(1)
	var fed_id := team.combat_identity(2)
	data.site.manual.cargo["stone"] = 19
	var cargo: Dictionary = data.site.manual.cargo
	var holder: Dictionary = lab.character.item_state
	var key := _drop(lab, player_id, 0.375)
	var container: Dictionary = data.site.ground_loot[key]
	for original: Dictionary in [holder, container]:
		var version := int(original.version)
		original.version = 2147483646
		assert(controller.person_actions.begin_loot(player_id, "ground", key, {}, [], 0.375).code == "STALE_SOURCE")
		assert(not controller.person_actions.is_busy(player_id) and float(container.open_rations) == 0.375 and controller._personal_opened_food(player_id).is_empty())
		original.version = version
	_begin_ui(lab, key)
	var before_clock := Runtime.now(data)
	var before_job: Dictionary = controller.person_actions.job_for(player_id)
	data.site.paused = true
	lab._process(1.0)
	data.site.paused = false
	paused = true
	lab._process(1.0)
	paused = false
	assert(Runtime.now(data) == before_clock and controller.person_actions.job_for(player_id) == before_job)
	assert(controller._personal_opened_food(player_id).is_empty() and float(container.open_rations) == 0.375)
	assert(controller.person_actions.cancel(player_id).ok)
	# Source revision and equal-value source-holder replacement both interrupt.
	for reason: String in ["version", "reference"]:
		_begin_ui(lab, key)
		if reason == "version":
			container.version = int(container.version) + 1
		else:
			data.site.ground_loot[key] = container.duplicate(true)
			container = data.site.ground_loot[key]
		lab._process(0.25 / 60.0)
		assert(not controller.person_actions.is_busy(player_id) and float(container.open_rations) == 0.375)
		assert(controller._personal_opened_food(player_id).is_empty(), "Rejected pickup cannot create a private pool")
	_begin_ui(lab, key)
	var before_version := int(holder.version)
	_finish_clock(lab)
	var pool := controller._personal_opened_food(player_id)
	assert(float(pool.open_rations) == 0.375 and Sustain._ids(pool) == [player_id])
	_near(float(pool.at), Runtime.now(data) * 60.0, "new private owner starts at current common clock")
	assert(not data.site.ground_loot.has(key) and float(container.open_rations) == 0.0)
	assert(int(holder.version) == before_version + 1 and is_same(cargo, data.site.manual.cargo) and is_same(holder, lab.character.item_state))
	assert(cargo == {"stone": 19} and Runtime.carried_load(data.site, cargo, holder) == 19.375)
	assert(controller.person_actions.settle_after_contacts().is_empty() and not Runtime.clear_empty_ground_loot(data, key).ok)
	# Fractions count against the same 20-item carrying bound before any job.
	var full_key := _drop(lab, player_id, 0.75)
	_begin_ui(lab, full_key, false)
	assert(controller.message.text.begins_with(Runtime.fail("STORAGE_FULL").message) and float(data.site.ground_loot[full_key].open_rations) == 0.75, controller.message.text)
	controller.save_path = OPEN_SAVE
	controller.save_current()
	controller._auto_save_blocked = true
	assert(controller.message.text == "地圖已保存", controller.message.text)
	controller.load_current()
	controller._auto_save_blocked = true
	assert(lab.terrain != data, controller.message.text)
	data = lab.terrain
	team = lab.army
	cargo = data.site.manual.cargo
	holder = lab.character.item_state
	pool = controller._personal_opened_food(player_id)
	assert(float(pool.open_rations) == 0.375 and cargo == {"stone": 19})
	assert(float(data.site.ground_loot[full_key].open_rations) == 0.75 and lab.controlled_person_id() == player_id)
	# The actual next small step pays the first meal once, without whole grain.
	lab._process(1.0 / 60.0)
	assert(float(pool.open_rations) > 0.125 and float(pool.open_rations) < 0.126 and cargo == {"stone": 19})
	var meal_before: Dictionary = pool.duplicate(true)
	var opened_before := float(pool.open_rations)
	key = _drop(lab, player_id, 0.25)
	_begin_ui(lab, key)
	_finish_clock(lab)
	_near(float(pool.open_rations), opened_before + 0.25, "existing private food increased without resetting the already paid meal")
	_assert_existing_meals(meal_before, pool)
	assert(not cargo.has("grain"))
	# Detach the original row before any team feeding was enabled. An existing
	# empty historical store may lag, but cannot leave this independent person unfed.
	# Direct control-bind calls below are fixture setup, not inheritance UI proof.
	assert(controller._control_family_person(null, row_id).ok)
	_press(controller, "LeavePlayerArmy")
	var index := team.index_for_identity(row_id)
	var row: Dictionary = team.combat_units[index]
	assert(not team.is_member(index) and controller._personal_opened_food(row_id).is_empty())
	var orphan := Sustain.create(0.0)
	data.site.person_supply[str(row_id)] = orphan
	var row_cargo: Dictionary = row.cargo
	key = _drop(lab, row_id, 0.375)
	_begin_ui(lab, key)
	_finish_clock(lab)
	assert(is_same(orphan, controller._personal_opened_food(row_id)) and float(orphan.open_rations) == 0.375)
	assert(Sustain._ids(orphan) == [row_id] and not team.is_member(index) and is_same(row_cargo, row.cargo) and row_cargo.is_empty())
	_near(float(orphan.at), Runtime.now(data) * 60.0, "empty old private pool aligns only before attaching its original person")
	lab._process(1.0 / 60.0)
	assert(float(orphan.open_rations) > 0.125 and float(orphan.open_rations) < 0.126)
	key = _drop(lab, row_id, 0.25)
	_begin_ui(lab, key)
	data.site.person_supply[str(row_id)] = orphan.duplicate(true)
	var replacement: Dictionary = data.site.person_supply[str(row_id)]
	opened_before = float(replacement.open_rations)
	meal_before = replacement.duplicate(true)
	lab._process(0.25 / 60.0)
	assert(not controller.person_actions.is_busy(row_id) and float(data.site.ground_loot[key].open_rations) == 0.25)
	assert(float(replacement.open_rations) == opened_before)
	_assert_existing_meals(meal_before, replacement)
	# A team-fed original member gets only a private stock pool, never a second
	# feeding cohort. Their existing team meal remains at its original owner.
	assert(controller._control_family_person(null, player_id).ok)
	_press(controller, "JoinPlayerArmy")
	var entry := controller._enable_team_supply(team)
	entry.inventory["fish"] = 4 # Explicit fixture team stock for its real members.
	assert(Sustain.resupply(entry.sustain, controller._team_members(team), entry.inventory).ok)
	assert(controller._control_family_person(null, fed_id).ok)
	assert(controller._personal_opened_food(fed_id).is_empty())
	var shared_before: Dictionary = entry.sustain.duplicate(true)
	var stock_before: Dictionary = entry.inventory.duplicate(true)
	key = _drop(lab, fed_id, 0.375)
	_begin_ui(lab, key)
	_finish_clock(lab)
	var private_stock := controller._personal_opened_food(fed_id)
	assert(private_stock.cohorts.is_empty() and float(private_stock.open_rations) == 0.375)
	_assert_existing_meals(shared_before, entry.sustain)
	assert(entry.inventory == stock_before and float(entry.sustain.open_rations) == float(shared_before.open_rations))
	assert(fed_id in Sustain._ids(entry.sustain))
	var states: Array = []
	for owner: Dictionary in controller.captivity_supply._states().values():
		states.append(owner.original)
	assert(Sustain.validate_owners(states, controller.captivity_supply._all_members()))
	var saved_independent_pool := controller._personal_opened_food(row_id).duplicate(true)
	controller.save_current()
	controller._auto_save_blocked = true
	assert(controller.message.text == "地圖已保存", controller.message.text)
	var reloaded := Store.load_site(OPEN_SAVE)
	assert(reloaded.ok, str(reloaded))
	var restored_pool: Dictionary = reloaded.data.site.person_supply[str(row_id)]
	_near(float(restored_pool.at), float(saved_independent_pool.at), "saved private owner common clock")
	_near(float(restored_pool.open_rations), float(saved_independent_pool.open_rations), "saved actual opened private food")
	_assert_existing_meals(saved_independent_pool, restored_pool)
	assert(reloaded.data.site.person_supply[str(fed_id)].cohorts.is_empty())
	assert(float(reloaded.data.site.person_supply[str(fed_id)].open_rations) == 0.375)
	var saved_independent := false
	for saved_team: Dictionary in reloaded.data.site.armies:
		for saved_row: Dictionary in saved_team.units:
			if int(saved_row.person_id) == row_id:
				saved_independent = not bool(saved_row.member) and saved_row.cargo == row_cargo
	assert(saved_independent, "The saved independent original row is not replaced or silently re-enlisted")
	# All callbacks on an old inventory dialog retain the same original scope.
	key = _drop(lab, fed_id, 0.125)
	var dialog := _open_loot(lab, key)
	assert(controller._control_family_person(null, lab.npc.person_id).ok)
	for button_name: String in ["BeginLoot", "BeginCapture", "BeginUnbind", "BeginRansomDialog"]:
		(dialog.find_child(button_name, true, false) as Button).pressed.emit()
		assert(controller.message.text.begins_with("STALE") and not controller.person_actions.is_busy(lab.npc.person_id))
	dialog.free()
	# A now non-controlled original person dies with their own picked-up open
	# food and original gear. The original down/death path leaves one remains.
	var fallen_index := team.index_for_identity(fed_id)
	var fallen: Dictionary = team.combat_units[fallen_index]
	var original_gear: Array = fallen.item_state.item_ids.duplicate()
	var ground_count: int = data.site.ground_loot.size()
	var record_count: int = data.site.item_records.size()
	team.apply_unit_contact(fallen_index, {"result": {"hp": 100.0, "stun": 0.0, "guard_break": false}, "shield": false})
	assert(float(fallen.hp) == 0.0 and not bool(fallen.get("loot_settled", false)))
	lab._process(float(TerrainArmy.CombatTimings.POSE_SECONDS[&"down"]) + 0.01)
	assert(bool(fallen.loot_settled) and data.site.ground_loot.size() == ground_count + 1)
	var remains: Dictionary = data.site.ground_loot[str(fallen.remains_id)]
	assert(float(remains.open_rations) == 0.375 and float(private_stock.open_rations) == 0.0)
	assert(remains.item_ids == original_gear and fallen.item_state.item_ids.is_empty() and fallen.cargo.is_empty())
	assert(int(remains.original_owner) == fed_id and data.site.item_records.size() == record_count)
	controller.settle_person_deaths(0.1)
	assert(data.site.ground_loot.size() == ground_count + 1 and float(remains.open_rations) == 0.375)
	# A real effective hit wins over pickup and cannot create a fresh private pool.
	assert(controller._personal_opened_food(lab.npc.person_id).is_empty())
	key = _drop(lab, lab.npc.person_id, 0.375)
	_begin_ui(lab, key)
	lab.npc.apply_contact({"result": {"hp": 1.0, "stun": 0.0, "guard_break": false}, "shield": false})
	lab._process(0.001)
	assert(not controller.person_actions.is_busy(lab.npc.person_id))
	assert(controller._personal_opened_food(lab.npc.person_id).is_empty() and float(data.site.ground_loot[key].open_rations) == 0.375)
	assert(not data.site.manual.cargo.has("grain") and not row_cargo.has("grain") and not data.site.worker.cargo.has("grain"))
	controller._auto_save_blocked = true
	lab.queue_free()
	await process_frame
	TerrainArmy.release_contact_source()
	print("SITE OPENED LOOT PASS: actual UI/common clock, original actor and independent row fractional food, private/shared meal ownership, 20-load capacity, pause/hit/version/reference/stale-dialog guards, one-time ground clear/save/load and original non-controlled death remains; no whole grain conversion")
	quit(0)
