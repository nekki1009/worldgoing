extends SceneTree

const Rules = preload("res://scripts/terrain_lab/site_combat_rules.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	assert(Rules.ranged_profile("bow_01") == {"ammo": "arrow", "range": 8.0, "cooldown": 2.0, "hold": 0.25, "speed": 10.0})
	assert(Rules.ranged_profile("crossbow_01") == {"ammo": "bolt", "range": 10.0, "cooldown": 3.0, "hold": 0.4, "speed": 14.0})
	assert(Rules.ranged_profile("longsword_01").is_empty() and Rules.ranged_profile("none").is_empty())
	assert(not Rules.ranged_in_range(Vector2i.ZERO, Vector2i.RIGHT, 8.0))
	assert(not Rules.ranged_in_range(Vector2i.ZERO, Vector2i.ZERO, 8.0))
	assert(Rules.ranged_in_range(Vector2i.ZERO, Vector2i(1, 1), 8.0), "Diagonal distance is not cardinal adjacency")
	assert(Rules.ranged_in_range(Vector2i.ZERO, Vector2i(8, 0), 8.0))
	assert(not Rules.ranged_in_range(Vector2i.ZERO, Vector2i(8, 1), 8.0))
	assert(Rules.ranged_in_range(Vector2i.ZERO, Vector2i(6, 8), 10.0))
	assert(not Rules.ranged_in_range(Vector2i.ZERO, Vector2i(7, 8), 10.0))
	for invalid_range: float in [0.0, 1.0, 10.01, INF, NAN]:
		assert(not Rules.ranged_in_range(Vector2i.ZERO, Vector2i(2, 0), invalid_range))
	var hit := Rules.ranged_result({}, {}, 2.0, 0.0)
	assert(hit.chance == 65.0 and hit.kind == "hit" and hit.hp == 2.0 and hit.stun == 12.0 and hit.stagger == 0.35)
	assert(not hit.knockback and not hit.guard_break)
	assert(Rules.ranged_result({}, {}, 2.0, 38.999).kind == "hit")
	var graze := Rules.ranged_result({}, {}, 2.0, 39.0)
	assert(graze.kind == "graze" and graze.hp == 1.0 and graze.stun == 6.0 and graze.stagger == 0.2)
	assert(Rules.ranged_result({}, {}, 2.0, 64.999).kind == "graze")
	var miss := Rules.ranged_result({}, {}, 2.0, 65.0)
	assert(miss.kind == "miss" and miss.hp == 0.0 and miss.stun == 0.0 and miss.stagger == 0.0)
	assert(Rules.ranged_result({}, {}, 8.0, 0.0).chance == 41.0)
	assert(Rules.ranged_result({"ability": 100.0, "training": 100.0, "fatigue": 100.0, "skill": "power"}, {}, 8.0, 0.0).chance == 66.0)
	for modifier: Dictionary in [{"moving": true}, {"facility": true}]:
		assert(Rules.ranged_result({}, modifier, 2.0, 0.0).chance == 45.0)
	for modifier: Dictionary in [{"shield": true}, {"skill": "brace"}]:
		assert(Rules.ranged_result({}, modifier, 2.0, 0.0).chance == 50.0)
	assert(Rules.ranged_result({}, {"armor_stab": 25.0}, 2.0, 0.0).chance == 60.0)
	assert(Rules.ranged_result({}, {"moving": true, "shield": true, "armor_stab": 100.0, "facility": true, "skill": "brace"}, 2.0, 0.0).chance == 5.0)
	assert(Rules.ranged_result({"ability": 100.0, "training": 100.0, "skill": "power"}, {}, 2.0, 0.0).chance == 95.0)
	assert(Rules.ranged_result({"skill": "power"}, {}, 2.0, 0.0).stun == 22.0)
	assert(Rules.ranged_result({"skill": "power"}, {}, 2.0, 60.0).stun == 16.0)
	assert(Rules.ranged_result({"skill": "power"}, {}, 2.0, 99.0).stun == 0.0)
	assert(Rules.ranged_result({"faction": 0}, {"faction": 0}, 2.0, 0.0) == hit, "Faction selection stays with the original event owner; friendly impact is not exempt")
	assert(Rules.ranged_result({"faction": 0}, {"faction": 1}, 2.0, 0.0) == hit)
	for roll: float in [-1.0, 100.0, INF, NAN]:
		assert(Rules.ranged_result({}, {}, 2.0, roll).kind == "miss", "Invalid event rolls cannot manufacture a hit")
	for distance: float in [-1.0, 0.0, 1.0, 10.01, INF, NAN]:
		assert(Rules.ranged_result({}, {}, distance, 0.0).kind == "miss")
	var data := TerrainData.new()
	data.allocate(Vector2i(32, 32))
	data.flags.fill(TerrainData.Flag.WALKABLE)
	data.static_blocked.resize(32 * 32)
	data.static_blocked.fill(0)
	var source := Vector2i(12, 12)
	assert(Rules.ranged_cells(source, source).is_empty())
	assert(Rules.ranged_cells(source, source + Vector2i(11, 0)).is_empty())
	assert(not Rules.ranged_line_clear(null, source, source + Vector2i(2, 0)))
	assert(not Rules.ranged_line_clear(data, Vector2i(-1, 0), Vector2i(2, 0)))
	var corner := source + Vector2i(1, 1)
	assert(Rules.ranged_cells(source, corner) == [source + Vector2i.RIGHT, source + Vector2i.DOWN, corner])
	for blocked: Vector2i in [source + Vector2i.RIGHT, source + Vector2i.DOWN, corner]:
		data.static_blocked[data.index(blocked)] = 1
		assert(not Rules.ranged_line_clear(data, source, corner) and not Rules.ranged_line_clear(data, corner, source), "Neither side of a diagonal corner can bypass a wall")
		data.static_blocked[data.index(blocked)] = 0
	var long_goal := source + Vector2i(9, 1)
	data.static_blocked[data.index(source + Vector2i(1, 1))] = 1
	assert(Rules.ranged_line_clear(data, source, long_goal), "The ray does not walk one X then one Y regardless of slope")
	data.static_blocked[data.index(source + Vector2i(1, 1))] = 0
	data.height_levels[data.index(source + Vector2i.RIGHT)] = 2
	assert(not Rules.ranged_line_clear(data, source, long_goal), "Original cliff attack edges remain authoritative")
	data.height_levels[data.index(source + Vector2i.RIGHT)] = 0
	var cases := 0
	for dx in range(-10, 11):
		for dy in range(-10, 11):
			var goal := source + Vector2i(dx, dy)
			if goal == source or dx * dx + dy * dy > 100:
				continue
			var cells := Rules.ranged_cells(source, goal)
			var covered := {source: true}
			for cell: Vector2i in cells:
				assert(not covered.has(cell), "A ray visits each touched cell once")
				covered[cell] = true
			assert(cells.back() == goal and cells.size() <= 30)
			var reverse := {goal: true}
			for cell: Vector2i in Rules.ranged_cells(goal, source):
				reverse[cell] = true
			assert(covered == reverse, "All octants preserve the same touched cells on reversal")
			for y in range(mini(source.y, goal.y), maxi(source.y, goal.y) + 1):
				for x in range(mini(source.x, goal.x), maxi(source.x, goal.x) + 1):
					var cell := Vector2i(x, y)
					assert(covered.has(cell) == _segment_touches_cell(source, goal, cell), "Supercover differs from independent inclusive rectangle clipping")
			assert(Rules.ranged_line_clear(data, source, goal))
			for blocked: Vector2i in cells:
				data.static_blocked[data.index(blocked)] = 1
				assert(not Rules.ranged_line_clear(data, source, goal), "Every covered blocker stops the line")
				data.static_blocked[data.index(blocked)] = 0
			cases += 1
	print("SITE RANGED RULES PASS: profiles, exact 0/1/2 HP, probabilities/skills/cover, friendly numerical parity, %d supercover rays and original terrain edges" % cases)
	quit(0)

func _segment_touches_cell(source: Vector2i, goal: Vector2i, cell: Vector2i) -> bool:
	var start := Vector2(source) + Vector2.ONE * 0.5
	var direction := Vector2(goal - source)
	var enter := 0.0
	var leave := 1.0
	for axis in range(2):
		if direction[axis] == 0.0:
			if start[axis] < float(cell[axis]) or start[axis] > float(cell[axis] + 1):
				return false
			continue
		var first := (float(cell[axis]) - start[axis]) / direction[axis]
		var last := (float(cell[axis] + 1) - start[axis]) / direction[axis]
		enter = maxf(enter, minf(first, last))
		leave = minf(leave, maxf(first, last))
	return enter <= leave + 0.000000001
