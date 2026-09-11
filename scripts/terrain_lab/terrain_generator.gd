class_name TerrainGenerator
extends RefCounted

static func generate(preset: int, seed_value: int, overrides: Dictionary = {}) -> TerrainData:
	assert(preset >= 0 and preset < TerrainPreset.NAMES.size())
	var data := TerrainData.new()
	data.parameters = TerrainPreset.defaults(preset)
	data.parameters.merge(overrides, true)
	var grid_size: Vector2i = data.parameters["size"]
	grid_size = grid_size.clamp(Vector2i(16, 16), Vector2i(128, 128))
	data.parameters["size"] = grid_size
	data.parameters["max_height"] = clampi(int(data.parameters["max_height"]), 1, 5)
	data.parameters["micro_strength"] = clampf(float(data.parameters["micro_strength"]), 0.0, 0.04)
	data.allocate(grid_size)
	data.preset = preset
	data.seed_value = seed_value
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	# Macro landmarks are chosen once per map, not independently per cell.
	var centre := Vector2(rng.randf_range(0.43, 0.57), rng.randf_range(0.43, 0.57))
	var phase: float = rng.randf_range(-PI, PI)
	var stretch: float = rng.randf_range(0.78, 1.18)
	var rotation: int = rng.randi_range(0, 3)
	var variation := FastNoiseLite.new()
	variation.seed = int(seed_value & 0x7fffffff)
	variation.frequency = 0.055
	var height_field := PackedFloat32Array()
	height_field.resize(grid_size.x * grid_size.y)
	var maximum: int = int(data.parameters["max_height"])
	for y: int in range(grid_size.y):
		for x: int in range(grid_size.x):
			var cell := Vector2i(x, y)
			var i: int = data.index(cell)
			var p := Vector2((float(x) + 0.5) / grid_size.x, (float(y) + 0.5) / grid_size.y)
			for _turn: int in range(rotation):
				p = Vector2(1.0 - p.y, p.x)
			var n: float = variation.get_noise_2d(float(x), float(y))
			var radial: Vector2 = (p - centre) / Vector2(0.44 * stretch, 0.43 / stretch)
			var radius: float = radial.length()
			var lobes: float = sin(radial.angle() * 3.0 + phase) * 0.065 \
				+ sin(radial.angle() * 5.0 - phase) * 0.028
			var coast: float = 0.25 + sin(p.y * 6.0 + phase) * 0.055 + sin(p.y * 13.0 - phase) * 0.018
			var river: float = centre.x + sin(p.y * 6.8 + phase) * 0.12 + sin(p.y * 12.0 - phase) * 0.026
			var river_distance: float = absf(p.x - river)
			var height: float = 0.0
			var surface: int = TerrainData.Surface.GRASS
			match preset:
				TerrainPreset.Kind.PLAINS:
					height = 0.35 + sin(p.x * 5.0 + phase) * 0.32 + cos(p.y * 4.0) * 0.25
					if ((p - centre) / Vector2(0.22, 0.12)).length() < 1.0:
						surface = TerrainData.Surface.WETLAND
					elif n > 0.3:
						surface = TerrainData.Surface.DIRT
				TerrainPreset.Kind.TERRACED_HIGHLAND:
					height = clampf(1.05 - radius + lobes, 0.0, 1.0)
				TerrainPreset.Kind.COASTAL_CLIFF:
					var inland: float = p.x - coast
					height = clampf((inland - 0.13) * 1.8, 0.0, 1.0)
					if inland < 0.0:
						surface = TerrainData.Surface.WATER
					elif inland < 0.075:
						surface = TerrainData.Surface.SAND
				TerrainPreset.Kind.FOREST:
					height = 0.28 + sin(p.x * 4.0 + phase) * 0.3 + p.y * 0.22
					surface = TerrainData.Surface.FOREST_GROUND
					var glade_a: float = ((p - centre) / Vector2(0.16, 0.2)).length()
					var glade_b: float = ((p - Vector2(0.72, 0.25)) / Vector2(0.12, 0.14)).length()
					if river_distance < 0.05 or glade_a < 1.0 or glade_b < 1.0:
						surface = TerrainData.Surface.GRASS
				TerrainPreset.Kind.WETLAND:
					var basin_a: float = ((p - Vector2(centre.x - 0.13, 0.36)) / Vector2(0.24, 0.25)).length()
					var basin_b: float = ((p - Vector2(centre.x + 0.12, 0.64)) / Vector2(0.24, 0.25)).length()
					var basin: float = minf(basin_a, basin_b) + n * 0.09
					height = clampf((basin - 1.2) * 0.6, 0.0, 0.8)
					surface = TerrainData.Surface.WATER if basin < 0.68 else TerrainData.Surface.WETLAND
					if basin > 1.28:
						surface = TerrainData.Surface.GRASS
				TerrainPreset.Kind.ROCKY_HIGHLAND:
					var ridge_x: float = centre.x + sin(p.y * 5.0 + phase) * 0.1
					var ridge: float = absf(p.x - ridge_x) / 0.37
					var end_falloff: float = pow(absf(p.y - 0.5) / 0.53, 3.0)
					height = clampf(1.06 - ridge - end_falloff * 0.4 + n * 0.06, 0.0, 1.0)
					surface = TerrainData.Surface.ROCK if height > 0.35 else TerrainData.Surface.GRASS
				TerrainPreset.Kind.RIVER_VALLEY:
					height = clampf((river_distance - 0.14) * 2.6, 0.0, 1.0)
					if river_distance < 0.036:
						surface = TerrainData.Surface.WATER
					elif river_distance < 0.065:
						surface = TerrainData.Surface.WETLAND
				TerrainPreset.Kind.ISLAND:
					var island_radius: float = radius - lobes
					height = clampf((0.83 - island_radius) * 1.25, 0.0, 1.0)
					if island_radius > 0.96 or x == 0 or y == 0 or x == grid_size.x - 1 or y == grid_size.y - 1:
						surface = TerrainData.Surface.WATER
					elif island_radius > 0.8:
						surface = TerrainData.Surface.SAND
			# Small variation cannot replace the coastline, river or plateau shape.
			height_field[i] = clampf(height + n * float(data.parameters["micro_strength"]), 0.0, 1.0)
			data.surface_types[i] = surface
	# Quantization is separate from surface: grass, rock and sand may share levels.
	for i: int in range(height_field.size()):
		var water: bool = data.surface_types[i] == TerrainData.Surface.WATER
		data.height_levels[i] = 0 if water else mini(maximum, floori(height_field[i] * (maximum + 1)))
		data.flags[i] = TerrainData.Flag.BLOCKED | TerrainData.Flag.WET if water else TerrainData.Flag.WALKABLE
		if data.surface_types[i] == TerrainData.Surface.WETLAND:
			data.flags[i] |= TerrainData.Flag.WET
	_detect_edges(data)
	_connect_platforms(data, rng)
	# Micro appearance only: packed tonal variation, no gameplay objects.
	for i: int in range(data.detail_variation.size()):
		data.detail_variation[i] = rng.randi_range(0, 255)
	_choose_spawn(data)
	return data

static func _detect_edges(data: TerrainData) -> void:
	for y: int in range(data.size.y):
		for x: int in range(data.size.x):
			var cell := Vector2i(x, y)
			var i: int = data.index(cell)
			for d: int in range(4):
				var next: Vector2i = cell + TerrainData.DIRECTIONS[d]
				if not data.contains(next):
					continue
				var j: int = data.index(next)
				var drop: int = maxi(0, int(data.height_levels[i]) - int(data.height_levels[j]))
				data.cliff_drops[i * 4 + d] = drop
				if drop > 0:
					data.flags[i] |= TerrainData.Flag.CLIFF
				if data.surface_types[i] != TerrainData.Surface.WATER and data.surface_types[j] == TerrainData.Surface.WATER:
					data.flags[i] |= TerrainData.Flag.SHORE

static func _root(parents: PackedInt32Array, cell: int) -> int:
	var current: int = cell
	while parents[current] != current:
		parents[current] = parents[parents[current]]
		current = parents[current]
	return current

static func _connect_platforms(data: TerrainData, rng: RandomNumberGenerator) -> void:
	# Join same-level components, then choose a spanning set of one-level passes.
	# This is generation-time connectivity, not a character pathfinding system.
	var parents := PackedInt32Array()
	parents.resize(data.height_levels.size())
	for i: int in range(parents.size()):
		parents[i] = i
	var candidates := PackedInt32Array()
	for y: int in range(data.size.y):
		for x: int in range(data.size.x):
			var cell := Vector2i(x, y)
			if not data.is_walkable(cell):
				continue
			var a: int = data.index(cell)
			for d: int in [1, 2]:
				var next: Vector2i = cell + TerrainData.DIRECTIONS[d]
				if not data.is_walkable(next):
					continue
				var b: int = data.index(next)
				var difference: int = absi(int(data.height_levels[a]) - int(data.height_levels[b]))
				if difference == 0:
					parents[_root(parents, a)] = _root(parents, b)
				elif difference == 1:
					candidates.append(a * 4 + d)
	for i: int in range(candidates.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var swap: int = candidates[i]
		candidates[i] = candidates[j]
		candidates[j] = swap
	for encoded: int in candidates:
		var a: int = floori(float(encoded) / 4.0)
		var d: int = encoded % 4
		var b: int = a + (1 if d == 1 else data.size.x)
		var root_a: int = _root(parents, a)
		var root_b: int = _root(parents, b)
		if root_a == root_b:
			continue
		parents[root_a] = root_b
		data.ramp_edges[a] |= 1 << d
		data.ramp_edges[b] |= 1 << ((d + 2) % 4)
		data.flags[a] |= TerrainData.Flag.RAMP
		data.flags[b] |= TerrainData.Flag.RAMP

static func _choose_spawn(data: TerrainData) -> void:
	var best: float = INF
	for y: int in range(data.size.y):
		for x: int in range(data.size.x):
			var cell := Vector2i(x, y)
			if not data.is_walkable(cell):
				continue
			var score: float = Vector2(cell).distance_squared_to(Vector2(data.size) * 0.5)
			if score < best:
				best = score
				data.spawn_cell = cell
