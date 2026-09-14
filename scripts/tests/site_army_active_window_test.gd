extends SceneTree

class SamplingArmy extends TerrainArmy:
	func combat_shapes(_index: int, _kind: String) -> Array[PackedVector2Array]:
		return [PackedVector2Array([Vector2.ZERO, Vector2.RIGHT, Vector2.ONE])]

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	create_timer(18.0).timeout.connect(func() -> void: quit(1))
	var data := TerrainGenerator.generate(0, 581)
	SiteEnvironment.initialize(data, "army-active-window-fixture")
	data.height_levels.fill(0)
	data.flags.fill(TerrainData.Flag.WALKABLE)
	data.static_blocked.fill(0)
	data.ramp_edges.fill(0)
	var army := SamplingArmy.new()
	root.add_child(army)
	army.set_process(false)
	var cells: Array[Vector2i] = []
	for index in range(100):
		cells.append(Vector2i(20 + index % 10, 20 + floori(float(index) / 10.0)))
	assert(army.deploy_at(data, null, null, cells) and army.enable_combat(false))
	var previous_counts: Array[int] = []
	army.contact_query = func(previous: Array[PackedVector2Array], _current: Array[PackedVector2Array], _cell: Vector2i, _ground: Vector2, _owner: Variant, _unit: int) -> Array[Dictionary]:
		previous_counts.append(previous.size())
		return []
	assert(army.start_unit_attack(0, cells[0] + Vector2i.LEFT))
	var events := TerrainArmy.CombatTimings.events(&"walk_slash")
	army.combat_units[0].previous = army.combat_shapes(0, "weapon")
	army.combat_units[0].age = float(events.active_start) - 0.0001
	army.sample_combat()
	assert(army.combat_units[0].previous.is_empty() and previous_counts.is_empty())
	army.combat_units[0].age = float(events.active_start)
	army.sample_combat()
	assert(previous_counts == [0], "First active frame cannot sweep from a windup pose")
	army.combat_units[0].age += 0.001
	army.sample_combat()
	assert(previous_counts == [0, 1], "Consecutive active samples preserve the real previous shape")
	army.combat_units[0].age = float(events.active_end) + 0.001
	army.sample_combat()
	assert(army.combat_units[0].previous.is_empty() and previous_counts == [0, 1])
	army.prepare_combat(5.0)
	army.sustain_routed_query = func(_team: TerrainArmy) -> bool: return true
	assert(not army.issue_combat_order(army.current_commander, TerrainArmy.CombatOrder.ATTACK).ok)
	assert(not army.issue_combat_order(army.current_commander, TerrainArmy.CombatOrder.MOVE, Vector2i(10, 10)).ok)
	assert(army.issue_combat_order(army.current_commander, TerrainArmy.CombatOrder.HOLD).ok)
	assert(not army.start_unit_attack(0, cells[0] + Vector2i.LEFT))
	assert(army.start_unit_attack(0, cells[0] + Vector2i.LEFT, -1, true), "Routed no-route self-defense remains legal")
	army.prepare_combat(5.0)
	army.sustain_routed_query = Callable()
	army.combat_units[2].ko = 10.0
	army.combat_units[2].pose = "unconscious"
	army.combat_units[2].present = false
	army._cell_owners.erase(army.cells[2])
	assert(army.start_unit_rescue(1, 2))
	var hunger := {"environmental": true, "result": {"hp": 1.0, "stun": 0.0, "guard_break": false}, "shield": false}
	army.apply_unit_contact(1, hunger)
	army.apply_unit_contact(2, hunger)
	assert(army._unit_rescues.has(1), "Nonfatal hunger does not interrupt rescue as a weapon hit")
	army.apply_unit_contact(2, {"environmental": true, "result": {"hp": 100.0, "stun": 0.0, "guard_break": false}, "shield": false})
	assert(not army._unit_rescues.has(1) and army.combat_units[2].hp == 0.0 and army.combat_units[2].ko == 0.0)
	army.free()
	TerrainArmy.release_contact_source()
	print("SITE_ARMY_ACTIVE_WINDOW_PASS: no windup sweep; active-only history; routed guards; environmental hunger rescue/death")
	quit(0)
