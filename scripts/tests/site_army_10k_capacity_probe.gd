extends SceneTree

## Match the transient TerrainLab 10k fixture's two half-map deployment scans.
const PER_TEAM := 5000
const SIZE := Vector2i(128, 128)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var data := TerrainGenerator.generate(TerrainPreset.Kind.PLAINS, 581, {"size": SIZE})
	SiteEnvironment.initialize(data, "site-army-10k-capacity-probe")
	if data.size != SIZE:
		_fail("Generator did not retain 128x128")
		return
	var player_cell := data.spawn_cell
	var claimed := {}
	var available := [0, 0]
	var selected := [0, 0]
	for side in range(2):
		for depth in range(data.size.x / 2):
			for y in range(data.size.y):
				var cell := Vector2i(data.size.x / 2 - 1 - depth if side == 0 else data.size.x / 2 + depth, y)
				if not data.is_walkable(cell) or cell == player_cell:
					continue
				available[side] += 1
				if selected[side] >= PER_TEAM:
					continue
				if claimed.has(cell):
					_fail("Overlapping deployment cell %s" % cell)
					return
				claimed[cell] = side
				selected[side] += 1
	var walkable := 0
	var static_blocked := 0
	for y in range(data.size.y):
		for x in range(data.size.x):
			var cell := Vector2i(x, y)
			walkable += int(data.is_walkable(cell))
			static_blocked += int(data.static_blocked[data.index(cell)] != 0)
	if selected != [PER_TEAM, PER_TEAM] or claimed.size() != PER_TEAM * 2 or claimed.has(player_cell):
		_fail("Insufficient unique legal cells: available=%s selected=%s claimed=%d" % [available, selected, claimed.size()])
		return
	print("SITE_ARMY_10K_CAPACITY_PASS size=%s walkable=%d static_blocked=%d player=%s side_available=%s unique_selected=%d" % [data.size, walkable, static_blocked, player_cell, available, claimed.size()])
	quit(0)

func _fail(message: String) -> void:
	push_error("SITE_ARMY_10K_CAPACITY_FAIL " + message)
	quit(1)
