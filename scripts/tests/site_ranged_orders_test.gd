extends SceneTree
## Explicit pre-migration reference; new physical semantics use site_fire_projectile_pipeline_test.
## Original Army orders, real equipment/cargo and Lab decisions; no alternate AI.
const STEP := 1.0 / 30.0
var checks := 0

class Fixture extends RefCounted:
	var data: TerrainData
	var lab: TerrainLab
	var team: TerrainArmy
	var enemy: TerrainArmy

func _initialize() -> void:
	run.call_deferred()

func _fixture(enemy_cell: Vector2i = Vector2i(16, 10), friend: bool = false) -> Fixture:
	var f := Fixture.new()
	f.data = TerrainData.new()
	f.data.allocate(Vector2i(40, 40))
	f.data.flags.fill(TerrainData.Flag.WALKABLE)
	SiteEnvironment.initialize(f.data, "ranged-orders-regression")
	f.data.height_levels.fill(0)
	f.data.ramp_edges.fill(0)
	f.data.static_blocked.fill(0)
	assert(SiteRuntime.initialize_item_storage(f.data.site).ok)
	f.lab = TerrainLab.new()
	f.lab.physical_ranged_enabled = false # Named legacy flight/roll reference only.
	f.lab.terrain = f.data
	f.lab.exchange_enabled = true
	f.team = TerrainArmy.new()
	f.enemy = TerrainArmy.new()
	f.enemy.team_id = 2
	f.enemy.faction_id = 1
	for team: TerrainArmy in [f.team, f.enemy]:
		root.add_child(team)
		team.set_process(false)
		team.exchange_enabled = true
		var positions: Array[Vector2i] = [Vector2i(10, 10) if team == f.team else enemy_cell]
		if team == f.team and friend: positions.append(Vector2i(12, 10))
		team.roster_size = positions.size()
		assert(team.deploy_at(f.data, null, null, positions))
		assert(team.enable_combat(false, 0, &"bow" if team == f.team else TerrainArmy.TROOP_TYPE_ID))
		for index in range(team.combat_units.size()):
			var row: Dictionary = team.combat_units[index]
			row.item_state = {}
			row.cargo = {"arrow": 20} if team == f.team and index == 0 else {}
			assert(SiteRuntime.seed_person_equipment(f.data, row.item_state, int(row.person_id), row.appearance).ok)
		team.command_abilities[0].tactics = 0
	f.team.equipment_appearance_query = func(identity: int) -> Dictionary:
		var row: Dictionary = f.team.combat_units[f.team.index_for_identity(identity)]
		return SiteRuntime.equipment_appearance(f.data, row.item_state, row.appearance)
	f.enemy.equipment_appearance_query = func(identity: int) -> Dictionary:
		var row: Dictionary = f.enemy.combat_units[f.enemy.index_for_identity(identity)]
		return SiteRuntime.equipment_appearance(f.data, row.item_state, row.appearance)
	f.lab.combat_armies.assign([f.team, f.enemy])
	f.team.external_blocker = f.enemy.blocks_cell
	f.enemy.external_blocker = f.team.blocks_cell
	for team: TerrainArmy in [f.team, f.enemy]:
		team.target_query = f.lab._army_target
		team.exchange_people_query = f.lab._exchange_people.bind(false)
		team.ranged_tactics_query = f.lab._ranged_tactics
	assert(f.team.ranged_profile(0).ammo == "arrow")
	return f

func _dispose(f: Fixture) -> void:
	for actor: TerrainTestCharacter in f.lab.combat_actors:
		actor.cell_blocker = Callable()
		actor.free()
	f.lab.combat_actors.clear()
	for team: TerrainArmy in [f.team, f.enemy]:
		team.equipment_appearance_query = Callable()
		team.equipment_appearance_batch_query = Callable()
		team.external_blocker = Callable()
		team.target_query = Callable()
		team.exchange_people_query = Callable()
		team.ranged_tactics_query = Callable()
		team.controlled_person_query = Callable()
	f.lab.combat_armies.clear()
	f.team.clear()
	f.enemy.clear()
	f.team.free()
	f.enemy.free()
	f.lab.free()

func _advance(f: Fixture, seconds: float, resolve: bool = true) -> void:
	for tick in range(ceili(seconds / STEP)):
		for team: TerrainArmy in [f.team, f.enemy]:
			team.prepare_combat(STEP)
			team.settle_combat_command()
			for index in range(team.cells.size()):
				assert(f.data.is_walkable(team.cells[index]))
				if team.moving_to[index] != TerrainArmy.INVALID_CELL:
					assert(f.data.can_step(team.cells[index], team.moving_to[index]))
					assert(team._reserved_cells.get(team.moving_to[index], -1) == index)
		for actor: TerrainTestCharacter in f.lab.combat_actors: actor.advance_combat(STEP, true)
		if resolve:
			f.lab._advance_ranged(STEP)
			if tick % 3 == 0: f.lab._resolve_exchanges()

func _order(f: Fixture, value: int, goal: Vector2i = TerrainArmy.INVALID_CELL) -> void:
	assert(f.team.issue_combat_order(f.team.current_commander, value, goal,
		f.enemy.combat_identity(0) if value == TerrainArmy.CombatOrder.PURSUE else -1).ok)

func run() -> void:
	create_timer(35.0).timeout.connect(func() -> void: quit(1))
	var f: Fixture
	for order: int in [TerrainArmy.CombatOrder.ATTACK, TerrainArmy.CombatOrder.PURSUE]:
		f = _fixture(Vector2i(22, 10))
		_order(f, order)
		_advance(f, 7.0)
		assert(f.team.cells[0] != Vector2i(10, 10) and f.lab.ranged_shots > 0, "A real distant archer must approach and shoot: " + str(order))
		assert(f.team.cells[0].distance_squared_to(f.enemy.cells[0]) >= 9, "Approach must stop at firing distance")
		if order == TerrainArmy.CombatOrder.PURSUE:
			_advance(f, 20.0)
			assert(f.team.combat_order == TerrainArmy.CombatOrder.HOLD and f.team.cells[0] == Vector2i(10, 10))
			var shots := f.lab.ranged_shots
			_advance(f, 3.0)
			assert(f.lab.ranged_shots == shots and not f.team.combat_attacking, "Expired pursuit cannot restart")
		_dispose(f)
		checks += 1
	for third_threat: bool in [false, true]:
		var ordinary := _fixture(Vector2i(19, 10) if third_threat else Vector2i(24, 10), true)
		ordinary.team.combat_units[0].cargo.arrow = 0
		ordinary.team.combat_units[1].cargo.arrow = 20
		assert(ordinary.team.supports_equipment_recipe(ordinary.team.equipment_appearance(1)), "The ordinary archer uses its admitted real atlas")
		var firing_ids := {}
		ordinary.lab.ranged_resolved.connect(func(shooter: int, _target: int, _result: Dictionary) -> void: firing_ids[shooter] = true)
		var third: TerrainTestCharacter
		if third_threat:
			third = TerrainTestCharacter.new()
			third.data = ordinary.data
			third.exchange_enabled = true
			third.person_id = 9001
			third.faction_id = 2
			assert(third.place(Vector2i(12, 13), true))
			ordinary.lab.combat_actors.append(third)
			third.cell_blocker = func(cell: Vector2i, _requester: Node) -> bool: return ordinary.team.blocks_cell(cell) or ordinary.enemy.blocks_cell(cell)
			ordinary.team.external_blocker = func(cell: Vector2i) -> bool: return ordinary.enemy.blocks_cell(cell) or third.occupies_cell(cell)
			ordinary.enemy.external_blocker = func(cell: Vector2i) -> bool: return ordinary.team.blocks_cell(cell) or third.occupies_cell(cell)
			assert(third.step(Vector2i.UP))
			assert(ordinary.enemy.issue_combat_order(ordinary.enemy.current_commander, TerrainArmy.CombatOrder.MOVE, Vector2i(18, 10)).ok)
		_order(ordinary, TerrainArmy.CombatOrder.ATTACK)
		_advance(ordinary, 8.0)
		assert(ordinary.team.cells[1] != Vector2i(12, 10) and firing_ids.has(ordinary.team.combat_identity(1)), "An ordinary original row must maneuver and fire, not only a live captain")
		assert(not firing_ids.has(ordinary.team.combat_identity(0)))
		assert(ordinary.team.cells[1].distance_squared_to(ordinary.enemy.cells[0]) >= 9)
		if third_threat:
			assert(third.terrain_cell == Vector2i(12, 12) and ordinary.enemy.cells[0] == Vector2i(18, 10))
			assert(ordinary.team.cells[1].distance_squared_to(third.terrain_cell) >= 9, "Retreat from one faction must also respect the other advancing threat")
		_dispose(ordinary)
		checks += 1
	for obstruction: String in ["friend", "wall", "close", "back_only", "trapped", "empty"]:
		f = _fixture(Vector2i(12, 10) if obstruction in ["close", "back_only"] else Vector2i(16, 10), obstruction == "friend")
		if obstruction == "wall": f.data.static_blocked[f.data.index(Vector2i(13, 10))] = 1
		if obstruction == "back_only":
			for x in range(7, 13):
				for y: int in [9, 11]: f.data.static_blocked[f.data.index(Vector2i(x, y))] = 1
		if obstruction == "trapped":
			for direction: Vector2i in TerrainData.DIRECTIONS: f.data.static_blocked[f.data.index(f.team.cells[0] + direction)] = 1
		if obstruction == "empty": f.team.combat_units[0].cargo.arrow = 0
		_order(f, TerrainArmy.CombatOrder.ATTACK)
		_advance(f, 6.0)
		if obstruction in ["trapped", "empty"]:
			assert(f.team.cells[0] == Vector2i(10, 10) and f.lab.ranged_shots == 0)
			if obstruction == "empty":
				assert("彈藥" in str(f.team.combat_units[0].status))
				f.team.combat_units[0].cargo.arrow = 2 # Explicit fixture replenishment.
				_advance(f, 3.0)
				assert(f.lab.ranged_shots > 0)
		else:
			assert(f.team.cells[0] != Vector2i(10, 10) and f.lab.ranged_shots > 0, "Must find and use a legal safe firing position: " + obstruction)
			assert(f.team.cells[0].distance_squared_to(f.enemy.cells[0]) >= 9)
			if obstruction == "friend": assert(f.team.combat_units[1].hp == 100.0, "Stationary friend cannot be knowingly shot")
		_dispose(f)
		checks += 1
	for order: int in [TerrainArmy.CombatOrder.HOLD, TerrainArmy.CombatOrder.MOVE]:
		f = _fixture()
		assert(f.team.start_unit_attack(0, f.enemy.cells[0], f.enemy.combat_identity(0)))
		_order(f, order, Vector2i(8, 10) if order != TerrainArmy.CombatOrder.HOLD else TerrainArmy.INVALID_CELL)
		_advance(f, 4.0)
		assert(f.lab.ranged_shots == 0 and f.team.combat_units[0].target == -1, "New nonattack order cancels stale target")
		if order != TerrainArmy.CombatOrder.HOLD: assert(f.team.cells[0] == Vector2i(8, 10))
		_dispose(f)
		checks += 1
	# RETREAT now requires the original supply morale-collapse contract. Its
	# original route owns the exit rather than the former arbitrary MOVE goal.
	f = _fixture()
	assert(f.team.start_unit_attack(0, f.enemy.cells[0], f.enemy.combat_identity(0)))
	assert(f.team.issue_combat_order(f.team.current_commander, TerrainArmy.CombatOrder.RETREAT).code == "NOT_ROUTED")
	assert(f.team.combat_units[0].target == f.enemy.combat_identity(0), "Rejected retreat preserves the original attack target")
	var retreat_members := {}
	var retreat_checkpoints := {}
	for row: Dictionary in f.team.combat_units:
		retreat_members[int(row.person_id)] = row
		retreat_checkpoints[str(row.person_id)] = 0
	var retreat_sustain := SiteSustain.create(SiteRuntime.now(f.data) * 60.0)
	assert(SiteSustain.add_members(retreat_sustain, retreat_members, retreat_members.keys()).ok)
	if not f.data.site.has("team_supply"): f.data.site["team_supply"] = {}
	f.data.site.team_supply[str(f.team.team_id)] = {"version": 1, "sustain": retreat_sustain, "inventory": {}, "training_order": false, "training_requester": -1, "revision": 0, "delivery": {}, "life_checkpoint": retreat_checkpoints}
	f.team.sustain_routed_query = func(original: TerrainArmy) -> bool: return bool(original.data.site.team_supply[str(original.team_id)].sustain.routed)
	var retreat_outcome := SiteSustain.advance_to(retreat_sustain, retreat_members, {}, float(retreat_sustain.at) + 40.0 * SiteSustain.HOUR)
	f.data.site.minute = int(f.data.site.minute) + 2400 # Original fixture clock alignment, not live-clock proof.
	assert(retreat_outcome.ok and retreat_outcome.routed_now and retreat_outcome.damage.is_empty() and float(retreat_sustain.morale) <= 20.0 and f.team.is_sustain_routed())
	var retreat_accepted_before := f.team.accepted_count
	_order(f, TerrainArmy.CombatOrder.RETREAT)
	assert(f.team.combat_order == TerrainArmy.CombatOrder.RETREAT and not f.team.combat_attacking and f.team.needs_attack_order and f.team.combat_units[0].target == -1)
	_advance(f, 12.0)
	assert(f.lab.ranged_shots == 0 and f.team.combat_units[0].target == -1, "Real morale retreat cancels stale target and never shoots")
	assert(bool(f.team.combat_hot_get(0, &"site_exited", false)) and f.team._edge_distance(f.team.cells[0]) == 0 and f.team.moving_to[0] == TerrainArmy.INVALID_CELL)
	assert(f.team.morale_retreat_terminal() and f.team.accepted_count > retreat_accepted_before and f.team._cell_owners.is_empty() and f.team._reserved_cells.is_empty())
	assert(TerrainArmy.valid_combat_state(f.team.capture_combat_state(), f.data))
	f.team.sustain_routed_query = Callable()
	_dispose(f)
	checks += 1
	# Passive close defense never authors a persistent explicit attack, including
	# the currently controlled row.
	f = _fixture(Vector2i(11, 10))
	f.team.controlled_person_query = func() -> int: return f.team.combat_identity(0)
	assert(f.enemy.issue_combat_order(f.enemy.current_commander, TerrainArmy.CombatOrder.ATTACK).ok)
	f.lab._resolve_exchanges()
	assert(f.lab.exchange_count == 1 and f.team.combat_units[0].target == -1)
	_dispose(f)
	# A separate distant target checks that a new manual attack still works in HOLD.
	f = _fixture(Vector2i(15, 10))
	f.team.controlled_person_query = func() -> int: return f.team.combat_identity(0)
	_advance(f, 4.0)
	assert(f.team.combat_units[0].target == -1 and f.lab.ranged_shots == 0)
	assert(f.team.start_unit_attack(0, f.enemy.cells[0], f.enemy.combat_identity(0)))
	f.lab._resolve_exchanges()
	assert(f.lab.ranged_shots == 1, "A new explicit controlled attack remains authorized in HOLD")
	_dispose(f)
	checks += 1
	f = _fixture()
	_order(f, TerrainArmy.CombatOrder.ATTACK)
	assert(f.team.start_unit_attack(0, f.enemy.cells[0], f.enemy.combat_identity(0)))
	f.team.apply_unit_contact(0, {"shield": false, "result": {"hp": 0.0, "stun": 110.0, "guard_break": false}})
	f.team.settle_combat_command()
	assert(f.team.needs_attack_order and f.team.combat_units[0].target == -1 and not f.team.combat_attacking)
	f.team._wake_unit(0)
	_advance(f, 3.0)
	assert(f.team.combat_can_act(0) and f.lab.ranged_shots == 0 and f.team.needs_attack_order, "Recovering a commander does not resurrect its old attack")
	_order(f, TerrainArmy.CombatOrder.ATTACK)
	_advance(f, 1.0)
	assert(f.lab.ranged_shots > 0, "A recovered commander can explicitly authorize a new attack")
	_dispose(f)
	checks += 1
	# The canonical live publication may skip a review only while it contains no
	# ranged weapon. Direct replacement and custom queries must be observed on
	# the next review, without a stale per-army equipment cache.
	f = _fixture(Vector2i(22, 10))
	_order(f, TerrainArmy.CombatOrder.ATTACK)
	f.team.combat_attacking = true
	f.team.needs_attack_order = false
	assert(f.team.combat_order == TerrainArmy.CombatOrder.ATTACK and not f.team.is_sustain_routed())
	var publication_owner := SiteController.new()
	var identity := f.team.combat_identity(0)
	var bow_appearance: Dictionary = f.team.equipment_appearance(0)
	var melee_appearance := bow_appearance.duplicate(true)
	melee_appearance.parts.weapon = "longsword_01"
	publication_owner._equipment_appearances[identity] = melee_appearance
	f.team.equipment_appearance_query = publication_owner.person_appearance
	f.team.equipment_appearance_batch_query = publication_owner.person_appearance_batch
	var before_empty_review := var_to_bytes(f.team.combat_units)
	f.team._update_ranged_orders()
	assert(var_to_bytes(f.team.combat_units) == before_empty_review and f.team.moving_to[0] == TerrainArmy.INVALID_CELL)
	var custom_calls := {"n": 0}
	f.team.equipment_appearance_query = func(person_id: int) -> Dictionary:
		custom_calls.n += 1
		return publication_owner.person_appearance(person_id)
	f.team._update_ranged_orders()
	assert(custom_calls.n > 0, "Custom equipment query retains its per-person callback")
	f.team.equipment_appearance_query = publication_owner.person_appearance
	publication_owner._equipment_appearances[identity] = bow_appearance
	f.team._update_ranged_orders()
	assert(f.team.moving_to[0] != TerrainArmy.INVALID_CELL, "A directly replaced bow publication is visible next review")
	_dispose(f)
	publication_owner.free()
	checks += 1
	TerrainArmy.release_contact_source()
	await process_frame
	print("SITE_RANGED_ORDERS_PASS: ", checks, " cases; approach/fire, pursuit return, close spacing, friendly/wall reposition, trap, empty/replenish, order cancellation, passive defense/manual attack, command loss")
	quit(0)
