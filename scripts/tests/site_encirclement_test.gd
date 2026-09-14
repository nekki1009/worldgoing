extends SceneTree
## Original rows, Lab references and committed grid steps; no surrogate movement.

const STEP := 1.0 / 30.0
const FRONT := Vector2i(9, 10)
const ENEMY := Vector2i(10, 10)

class Fixture extends RefCounted:
	var data: TerrainData
	var lab: TerrainLab
	var team: TerrainArmy
	var enemy: TerrainArmy
	var queries := 0

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	create_timer(20.0).timeout.connect(func() -> void: quit(1))
	_check_actual_surround_and_pause()
	_check_claims_save_and_new_order()
	_check_blocked_flanks()
	_check_candidate_guards()
	_check_contact_free_vacancy_guards()
	_check_order_guards()
	assert(TerrainArmy._contact_source == null, "Tactical grid decisions must not load old body/weapon geometry")
	print("SITE_ENCIRCLEMENT_PASS: actual multi-direction contact, pinned front, original claims/slots/save, walls/reservations, candidate authority and duties, order/pause/pursuit guards, bounded cadence")
	quit(0)

func _fixture(enemy_cell: Vector2i = ENEMY) -> Fixture:
	var fixture := Fixture.new()
	fixture.data = TerrainData.new()
	fixture.data.allocate(Vector2i(32, 32))
	fixture.data.flags.fill(TerrainData.Flag.WALKABLE)
	SiteEnvironment.initialize(fixture.data, "encirclement-original-owner")
	fixture.data.height_levels.fill(0)
	fixture.data.ramp_edges.fill(0)
	fixture.data.static_blocked.fill(0)
	fixture.lab = TerrainLab.new()
	fixture.lab.terrain = fixture.data
	fixture.team = TerrainArmy.new()
	fixture.enemy = TerrainArmy.new()
	fixture.enemy.team_id = 2
	fixture.enemy.faction_id = 1
	var selected: Array[Vector2i] = [FRONT, Vector2i(8, 10), Vector2i(8, 9),
		Vector2i(8, 11), Vector2i(7, 9), Vector2i(7, 11)]
	for army: TerrainArmy in [fixture.team, fixture.enemy]:
		root.add_child(army)
		army.set_process(false)
		army.exchange_enabled = true
	fixture.team.roster_size = selected.size()
	fixture.enemy.roster_size = 1
	assert(fixture.team.deploy_at(fixture.data, null, null, selected) and fixture.team.enable_combat(false))
	var opposition: Array[Vector2i] = [enemy_cell]
	assert(fixture.enemy.deploy_at(fixture.data, null, null, opposition) and fixture.enemy.enable_combat(false))
	fixture.lab.combat_armies.assign([fixture.team, fixture.enemy])
	fixture.team.external_blocker = fixture.enemy.blocks_cell
	fixture.enemy.external_blocker = fixture.team.blocks_cell
	fixture.team.target_query = fixture.lab._army_target
	fixture.team.exchange_people_query = func() -> Array[Dictionary]:
		fixture.queries += 1
		return fixture.lab._exchange_people()
	fixture.team.command_abilities[0].tactics = 0
	return fixture

func _dispose(fixture: Fixture) -> void:
	fixture.team.exchange_people_query = Callable()
	fixture.team.person_busy_query = Callable()
	fixture.team.controlled_person_query = Callable()
	fixture.team.sustain_routed_query = Callable()
	fixture.team.equipment_appearance_query = Callable()
	fixture.team.target_query = Callable()
	fixture.team.external_blocker = Callable()
	fixture.enemy.external_blocker = Callable()
	fixture.lab.combat_armies.clear()
	fixture.team.clear()
	fixture.enemy.clear()
	fixture.team.free()
	fixture.enemy.free()
	fixture.lab.free()

func _attack(fixture: Fixture) -> void:
	assert(fixture.team.issue_combat_order(fixture.team.current_commander, TerrainArmy.CombatOrder.ATTACK).ok)

func _advance(fixture: Fixture, seconds: float) -> void:
	for _tick in range(ceili(seconds / STEP)):
		var issued := fixture.team.encirclement_steps
		fixture.team.prepare_combat(STEP)
		fixture.team.settle_combat_command()
		assert(fixture.team.encirclement_steps - issued <= TerrainArmy.ENCIRCLEMENT_STEPS)
		_assert_claims(fixture)

func _assert_claims(fixture: Fixture) -> void:
	var occupied := {}
	for army: TerrainArmy in [fixture.team, fixture.enemy]:
		for index in range(army.combat_units.size()):
			if army.blocks_cell(army.cells[index]) and (army.combat_can_act(index) or army.moving_to[index] != TerrainArmy.INVALID_CELL):
				assert(not occupied.has(army.cells[index]), "Two real standing/moving sources cannot overlap")
				occupied[army.cells[index]] = army.combat_identity(index)
	var reserved := {}
	for army: TerrainArmy in [fixture.team, fixture.enemy]:
		for cell: Vector2i in army._reserved_cells:
			var index := int(army._reserved_cells[cell])
			assert(not occupied.has(cell) and not reserved.has(cell), "A tactical destination cannot steal a source or another claim")
			assert(army.moving_to[index] == cell and fixture.data.can_step(army.cells[index], cell))
			assert(not army._is_external_cell(cell))
			reserved[cell] = army.combat_identity(index)

func _contact_sectors(fixture: Fixture) -> int:
	var sectors := {}
	for index in range(fixture.team.combat_units.size()):
		var cell := fixture.team.cells[index]
		var offset := cell - fixture.enemy.cells[0]
		if fixture.team.combat_can_act(index) and absi(offset.x) + absi(offset.y) == 1 \
			and fixture.data.can_attack_across(cell, fixture.enemy.cells[0]):
			sectors[offset] = true
	return sectors.size()

func _check_actual_surround_and_pause() -> void:
	var fixture := _fixture()
	_attack(fixture)
	assert(_contact_sectors(fixture) == 1)
	var before := JSON.stringify(fixture.team.capture_combat_state())
	paused = true
	_advance(fixture, 0.6)
	assert(JSON.stringify(fixture.team.capture_combat_state()) == before and fixture.queries == 0)
	paused = false
	_advance(fixture, 3.0)
	assert(_contact_sectors(fixture) >= 2, "The original rear soldiers must actually reach a second legal side, not merely choose goals")
	assert(fixture.team.cells[0] == FRONT and fixture.team.moving_to[0] == TerrainArmy.INVALID_CELL, "The engaged front cannot abandon its contact")
	assert(fixture.team.encirclement_steps > 0 and fixture.queries <= 7, "One bounded review follows the original command cadence, not every 30 Hz step")
	assert(fixture.enemy.cells[0] == ENEMY and fixture.enemy.combat_units[0].hp == 100.0)
	_dispose(fixture)

func _check_claims_save_and_new_order() -> void:
	var fixture := _fixture()
	_attack(fixture)
	for _tick in range(30):
		_advance(fixture, STEP)
		if fixture.team.encirclement_steps > 0:
			break
	assert(fixture.team.moving_count() > 0)
	fixture.team.settle_combat_command()
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(fixture.team.capture_combat_state()))
	assert(TerrainArmy.valid_combat_state(snapshot, fixture.data), "Flanking must remain representable by the original slots and committed-step snapshot")
	var copy := TerrainArmy.new()
	root.add_child(copy)
	copy.set_process(false)
	copy.exchange_enabled = true
	copy.restore_combat_state(snapshot, fixture.data, null, null)
	assert(copy.cells == fixture.team.cells and copy.combat_slots == fixture.team.combat_slots and copy.moving_to == fixture.team.moving_to)
	assert(copy._reserved_cells == fixture.team._reserved_cells)
	copy.clear()
	copy.free()
	var destinations := fixture.team.moving_to.duplicate()
	var endpoints := fixture.team.cells.duplicate()
	for index in range(endpoints.size()):
		if destinations[index] != TerrainArmy.INVALID_CELL:
			endpoints[index] = destinations[index]
	var steps := fixture.team.encirclement_steps
	assert(fixture.team.issue_combat_order(fixture.team.current_commander, TerrainArmy.CombatOrder.HOLD).ok)
	assert(fixture.team.moving_to == destinations, "New HOLD cannot erase or replace any original in-flight step")
	_advance(fixture, 1.0)
	assert(fixture.team.cells == endpoints and fixture.team.combat_slots == endpoints)
	assert(fixture.team.moving_count() == 0 and fixture.team.encirclement_steps == steps)
	_dispose(fixture)

func _check_blocked_flanks() -> void:
	var fixture := _fixture()
	for cell: Vector2i in [ENEMY + Vector2i.UP, ENEMY + Vector2i.DOWN, ENEMY + Vector2i.RIGHT]:
		fixture.data.static_blocked[fixture.data.index(cell)] = 1
	_attack(fixture)
	var original := fixture.team.cells.duplicate()
	_advance(fixture, 1.2)
	assert(fixture.team.cells == original and fixture.team.moving_count() == 0 and fixture.team.encirclement_steps == 0,
		"Closed sides must wait, never cross walls or push the engaged front out of its occupied cell")
	_dispose(fixture)
	fixture = _fixture()
	_attack(fixture)
	var claimed := Vector2i(9, 9)
	assert(fixture.team._reserve_combat_step(2, claimed))
	assert(fixture.team._try_exchange_encirclement())
	assert(fixture.team._reserved_cells[claimed] == 2 and fixture.team.moving_to[2] == claimed,
		"A pre-existing friendly claim survives the tactical review")
	_assert_claims(fixture)
	_dispose(fixture)

func _only_candidate(fixture: Fixture, index: int = 2) -> void:
	var allowed := fixture.team.combat_identity(index)
	fixture.team.person_busy_query = func(identity: int) -> bool: return identity != allowed

func _duty_guard(fixture: Fixture, guard: String) -> void:
	var row: Dictionary = fixture.team.combat_units[2]
	match guard:
		"ranged":
			var appearance: Dictionary = TerrainArmy._combat_bake.manifest.appearance.duplicate(true)
			appearance.parts.weapon = "bow_01"
			appearance.parts.shield = "none"
			row.appearance = appearance
			row.item_state = {}
			assert(SiteRuntime.seed_person_equipment(fixture.data, row.item_state, int(row.person_id), appearance).ok)
			fixture.team.equipment_appearance_query = func(identity: int) -> Dictionary:
				return SiteRuntime.equipment_appearance(fixture.data, row.item_state, row.appearance) if identity == int(row.person_id) else {}
			assert(fixture.team.ranged_profile(2).get("ammo", "") == "arrow", "Exclude the actual equipped bow even with no arrows")
		"work":
			row.work_task = {"mode": "rest"} # Existing assignment remains a duty while resting.
		"controlled":
			fixture.team.controlled_person_query = func() -> int: return fixture.team.combat_identity(2)
		"busy":
			fixture.team.person_busy_query = func(_identity: int) -> bool: return true
		"routed":
			fixture.team.sustain_routed_query = func(_team: TerrainArmy) -> bool: return true
		"needs_attack_order":
			fixture.team.needs_attack_order = true

func _check_candidate_guards() -> void:
	var baseline := _fixture()
	_only_candidate(baseline)
	_attack(baseline)
	_advance(baseline, 0.6)
	assert(baseline.team.encirclement_steps > 0, "The guard fixture must first prove its sole rear candidate can flank")
	_dispose(baseline)
	for guard: String in ["ranged", "work", "controlled", "nonmember", "stagger", "rescue", "busy", "routed", "ko", "get_up"]:
		var fixture := _fixture()
		_only_candidate(fixture)
		_attack(fixture)
		var row: Dictionary = fixture.team.combat_units[2]
		match guard:
			"ranged", "work", "controlled", "busy":
				_duty_guard(fixture, guard)
			"nonmember":
				row.member = false
				row.present = false
			"stagger":
				row.exchange_stagger = 2.0
			"rescue":
				fixture.team.apply_unit_contact(4, {"shield": false, "result": {"hp": 0.0, "stun": 110.0, "guard_break": false}})
				assert(fixture.team.start_unit_rescue(2, 4))
			"routed":
				fixture.team.sustain_routed_query = func(_team: TerrainArmy) -> bool: return true
			"ko":
				fixture.team.apply_unit_contact(2, {"shield": false, "result": {"hp": 0.0, "stun": 110.0, "guard_break": false}})
			"get_up":
				row.pose = "get_up"
				row.age = 0.0
		var original := fixture.team.cells.duplicate()
		_advance(fixture, 0.6)
		assert(fixture.team.cells == original and fixture.team.moving_count() == 0 and fixture.team.encirclement_steps == 0,
			"Autonomous encirclement must respect the original " + guard + " guard")
		if guard == "rescue":
			assert(fixture.team._unit_rescues.has(2), "Tactical planning cannot cancel a real rescue")
		_dispose(fixture)

func _check_contact_free_vacancy_guards() -> void:
	var baseline := _fixture(Vector2i(20, 20))
	_only_candidate(baseline)
	_attack(baseline)
	var vacant := baseline.team.cells[1]
	baseline.team.apply_unit_contact(1, {"shield": false, "result": {"hp": 100.0, "stun": 0.0, "guard_break": false}})
	_advance(baseline, 1.2)
	assert(baseline.team.cells[2] == vacant and int(baseline.team._vacancy_assignments.get(1, -1)) == 2,
		"The contact-free fixture must prove the original fallback can fill its actual casualty slot")
	assert(baseline.team.encirclement_reviews == 0)
	_dispose(baseline)
	for guard: String in ["ranged", "work", "busy", "controlled", "routed", "needs_attack_order"]:
		for retained_slot: bool in [false, true]:
			var fixture := _fixture(Vector2i(20, 20))
			_only_candidate(fixture)
			_attack(fixture)
			fixture.team.apply_unit_contact(1, {"shield": false, "result": {"hp": 100.0, "stun": 0.0, "guard_break": false}})
			if retained_slot:
				# Author the old goal through the real vacancy owner before duty/control
				# changes. No source cell or movement reservation is fabricated.
				fixture.team._assign_combat_vacancy()
				assert(int(fixture.team._vacancy_assignments.get(1, -1)) == 2)
				assert(fixture.team.combat_slots[2] == fixture.team.cells[1])
			_duty_guard(fixture, guard)
			var original := fixture.team.cells.duplicate()
			_advance(fixture, 1.2)
			assert(fixture.team.cells == original and fixture.team.moving_count() == 0,
				"Contact-free " + ("retained-slot movement" if retained_slot else "vacancy selection") + " must retain the " + guard + " exclusion")
			assert(fixture.team.encirclement_reviews == 0 and fixture.team.encirclement_steps == 0)
			if not retained_slot:
				assert(not fixture.team._vacancy_assignments.values().has(2), "Fallback cannot assign a protected person before its movement guard")
			_dispose(fixture)

func _check_order_guards() -> void:
	var fixture := _fixture(Vector2i(20, 20))
	_attack(fixture)
	var original := fixture.team.cells.duplicate()
	_advance(fixture, 1.2)
	assert(fixture.team.cells == original and fixture.team.encirclement_steps == 0, "ATTACK without real local contact is not automatic distant pursuit")
	_dispose(fixture)
	for order: int in [TerrainArmy.CombatOrder.HOLD, TerrainArmy.CombatOrder.MOVE, TerrainArmy.CombatOrder.RETREAT]:
		fixture = _fixture()
		var goal := Vector2i(fixture.team.command_reference.floor()) + Vector2i.LEFT * 2
		assert(fixture.team.issue_combat_order(fixture.team.current_commander, order, goal).ok)
		assert(not fixture.team._try_exchange_encirclement() and fixture.team.encirclement_steps == 0,
			"Encirclement cannot replace HOLD, MOVE or RETREAT")
		_dispose(fixture)
	fixture = _fixture()
	assert(fixture.team.issue_combat_order(fixture.team.current_commander, TerrainArmy.CombatOrder.PURSUE,
		TerrainArmy.INVALID_CELL, fixture.enemy.combat_identity(0)).ok)
	fixture.team.pursuit_left = STEP * 0.5 # Existing owner countdown at its final boundary.
	_advance(fixture, STEP)
	assert(fixture.team.combat_order != TerrainArmy.CombatOrder.PURSUE and fixture.team.pursuit_left == 0.0)
	assert(not fixture.team.combat_attacking and fixture.team.encirclement_steps == 0,
		"Expired pursuit closes before the tactical planner can issue a new step")
	_dispose(fixture)
