extends SceneTree

const Preview = preload("res://scripts/region_lab/region_site_preview.gd")
const Atlas = preload("res://scripts/region_lab/region_data.gd")
const Adapter = preload("res://scripts/region_lab/region_terrain_adapter.gd")
const Grid = preload("res://scripts/region_lab/region_grid.gd")
const Env = preload("res://scripts/terrain_lab/site_environment.gd")
const REAL_SITES: Array[Vector2i] = [Vector2i(1228, 12981), Vector2i(1097, 12194),
	Vector2i(1098, 12194), Vector2i(1545, 12170)]

class FixedSource extends RefCounted:
	var response: Dictionary = {}
	var requested := Vector2i.ZERO
	func make_terrain_data(x: int, y: int) -> Dictionary:
		requested = Vector2i(x, y)
		return response

class HaloSource extends RefCounted:
	var manifest := {"atlas_id": "ramp_fixture", "base_revision": "fixture"}
	var manifest_hash := "b".repeat(64)
	var direction := 0
	var altered_east := false
	var invalid_corner := false
	func _sample_site_meters(east: float, north: float, _cache: Dictionary) -> Dictionary:
		var x := floori(east / 2.0)
		var y := floori(north / 2.0)
		var axis := y if direction in [0, 2] else x
		var level := 2 + int(axis >= 50 if direction in [0, 1] else axis < 50)
		if altered_east and x >= 100:
			level += 1
		if invalid_corner and x == -1 and y == 100:
			level = 9
		return {"ok": true, "level": level, "water_kind": 0, "elevation_m": level * 16.0,
			"elevation_valid": true, "source_quality_code": 1}

var _finished := false
var _failures: Array[String] = []
var _checked_cells := 0
var _checked_edges := 0
var _continuity_checks := 0

func _init() -> void:
	call_deferred("_run")

func _process(_delta: float) -> bool:
	if not _finished:
		printerr("REGION_PREVIEW_CONTRACT_INTERRUPTED")
		quit(1)
	return false

func _run() -> void:
	_synthetic()
	_resource_marks()
	_ramp_continuity()
	_parallel_border()
	var manifest_path := Atlas.DEFAULT_MANIFEST
	var synthetic_only := false
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--manifest="):
			manifest_path = argument.trim_prefix("--manifest=")
		elif argument == "--synthetic-only":
			synthetic_only = true
	var source := Atlas.new()
	var records: Array[Dictionary] = []
	if not synthetic_only:
		var loaded: Dictionary = source.load_manifest(manifest_path)
		_check(bool(loaded.get("ok", false)), "manifest:" + str(loaded.get("code", "unknown")))
		if bool(loaded.get("ok", false)):
			var water_edges: Array[PackedByteArray] = []
			for site: Vector2i in REAL_SITES:
				var started := Time.get_ticks_usec()
				var baked := Preview.bake(source, site)
				_check(bool(baked.get("ok", false)), "real_bake:" + str(site))
				if not bool(baked.get("ok", false)):
					continue
				var data: TerrainData = baked.terrain_result.data
				var before := data.fingerprint()
				_check(baked.site == site and baked.size == Vector2i(300, 300), "real_identity")
				_check(before == str(baked.terrain_result.base.terrain_fingerprint), "real_fingerprint")
				_check(data.site.is_empty(), "preview_created_site_state")
				_check_pixels(data, Preview.from_terrain(data, false))
				_check(Preview.from_terrain(data) == baked.pixels and data.fingerprint() == before,
					"preview_changed_terrain_or_pixels")
				_check(baked.resource_counts == Preview.visible_resource_counts(data),
					"preview_resource_counts_mismatch")
				var direct: Dictionary = source.make_terrain_data(site.x, site.y)
				_check(bool(direct.get("ok", false)) and direct.data.fingerprint() == before,
					"preview_and_entry_diverged")
				if site.x in [1097, 1098]:
					var edge := PackedByteArray()
					for y: int in range(100):
						var x := 99 if site.x == 1097 else 0
						edge.append(1 if data.water_body[data.index(Vector2i(x, y))] == 7433 else 0)
					water_edges.append(edge)
				if site == Vector2i(1228, 12981):
					_check(data.height_levels.count(data.height_levels[0]) < data.height_levels.size(), "yushan_lost_relief")
					_check_real_ramp_boundary(source, site, baked)
					_check_real_bounded_passes(data)
				if site == Vector2i(1545, 12170):
					_check(data.water_kind.has(0) and data.water_kind.has(2), "lanyu_lost_coast")
				records.append({"site": [site.x, site.y], "fingerprint": before,
					"elapsed_ms": (Time.get_ticks_usec() - started) / 1000.0})
			if water_edges.size() == 2:
				var shared := 0
				for y: int in range(100):
					if water_edges[0][y] == 1 and water_edges[1][y] == 1:
						shared += 1
				_check(shared > 0, "cross_site_body_7433_lost")
			else:
				_check(false, "cross_site_body_not_checked")
	_finished = true
	var report := {"manifest": manifest_path, "manifest_sha256": source.manifest_hash,
		"synthetic_only": synthetic_only, "cells": _checked_cells, "edges": _checked_edges,
		"continuity_checks": _continuity_checks, "sites": records, "failures": _failures}
	print("REGION_PREVIEW_CONTRACT_", "PASS " if _failures.is_empty() else "FAIL ", JSON.stringify(report))
	quit(0 if _failures.is_empty() else 1)

func _synthetic() -> void:
	var source := FixedSource.new()
	source.response = {"ok": false, "code": "MISSING_DATA", "message": "original missing source", "sentinel": 17}
	_check(Preview.bake(source, Vector2i(-8, 3)) == source.response, "source_error_not_forwarded")
	_check(source.requested == Vector2i(-8, 3), "source_coordinate_changed")
	_check(Preview.from_terrain(null).is_empty(), "null_terrain_accepted")
	var data := TerrainData.new()
	data.allocate(Vector2i(100, 100))
	data.water_kind.resize(10000)
	for y: int in range(100):
		for x: int in range(100):
			var index := data.index(Vector2i(x, y))
			data.height_levels[index] = (x + y) % 6
			data.surface_types[index] = floori(float(x) / 10.0) % 7
			if data.surface_types[index] == TerrainData.Surface.WATER:
				data.water_kind[index] = 2 if y < 50 else 4
	# Cliff markings must come from their owner, not reconstructed neighbouring levels.
	for direction: int in range(4):
		var cell := Vector2i(20 + direction * 4, 20)
		var index := data.index(cell)
		data.cliff_drops[index * 4 + direction] = 3
	var before := data.fingerprint()
	source.response = {"ok": true, "data": data, "sentinel": 19}
	var result := Preview.bake(source, Vector2i(7, -3))
	_check(result.ok and result.terrain_result == source.response and result.terrain_result.data == data,
		"original_terrain_result_not_retained")
	_check(result.size == Vector2i(300, 300) and result.pixels.size() == 300 * 300 * 4, "raster_shape")
	_check_pixels(data, result.pixels)
	_check(data.fingerprint() == before, "synthetic_owner_mutated")
	_check(_pixel(result.pixels, Vector2i(1, 1)) == Color("65854e"), "northwest_orientation")
	data.height_levels.resize(1)
	_check(Preview.from_terrain(data).is_empty(), "truncated_terrain_accepted")

func _resource_marks() -> void:
	var data := TerrainData.new()
	data.allocate(Vector2i(100, 100))
	data.surface_types.fill(TerrainData.Surface.GRASS)
	var resource_cells: Array[Vector2i] = [Vector2i(10, 10), Vector2i(20, 20), Vector2i(30, 30), Vector2i(40, 40)]
	var kinds := [Env.Kind.TIMBER, Env.Kind.STONE, Env.Kind.FOOD, Env.Kind.IRON]
	for index: int in range(kinds.size()):
		var cell_index := data.index(resource_cells[index])
		data.resource_base["test:%d" % index] = {"kind": kinds[index], "cell": cell_index,
			"cells": [cell_index], "capacity": 10, "variant": 0, "blocks": index < 2, "recover": 0}
	var before := data.fingerprint()
	var ground := Preview.from_terrain(data, false)
	var marked := Preview.from_terrain(data)
	var counts := Preview.visible_resource_counts(data)
	var source := FixedSource.new()
	source.response = {"ok": true, "data": data}
	var baked: Dictionary = Preview.bake(source, Vector2i(4, 5))
	_check(bool(baked.get("ok", false)) and baked.pixels == marked and baked.resource_counts == counts,
		"resource_bake_did_not_use_same_base")
	_check(counts[Env.Kind.TIMBER] == 1 and counts[Env.Kind.STONE] == 1
		and counts[Env.Kind.FOOD] == 1 and counts[Env.Kind.IRON] == 0,
		"resource_preview_count_or_undiscovered_iron")
	for index: int in range(3):
		var center := resource_cells[index] * 3 + Vector2i.ONE
		var tint: Color = Env.COLORS[kinds[index]].lightened(0.25)
		_check(_pixel(marked, center) == Color8(tint.r8, tint.g8, tint.b8),
			"resource_mark_color:%d" % index)
		_check(_pixel(marked, center) != _pixel(ground, center), "resource_mark_missing:%d" % index)
	var iron_center := resource_cells[3] * 3 + Vector2i.ONE
	_check(_pixel(marked, iron_center) == _pixel(ground, iron_center), "hidden_iron_leaked_to_preview")
	_check(data.site.is_empty() and data.fingerprint() == before, "resource_preview_created_state")

func _ramp_continuity() -> void:
	var data := _empty_ramp_map()
	for direction: int in range(4):
		var low := Vector2i(30 + direction * 6, 40)
		_link_ramp(data, low, low + TerrainData.DIRECTIONS[direction], 1, 2)
	_link_ramp(data, Vector2i(20, 20), Vector2i(21, 20), 1, 2)
	_link_ramp(data, Vector2i(21, 20), Vector2i(22, 20), 2, 3)
	_link_ramp(data, Vector2i(40, 60), Vector2i(41, 60), 1, 2)
	_link_ramp(data, Vector2i(41, 60), Vector2i(41, 61), 2, 3)
	for row: int in [50, 51]:
		_link_ramp(data, Vector2i(70, row), Vector2i(71, row), 1, 2)
	var before := data.fingerprint()
	var pixels := Preview.from_terrain(data)
	_check_pixels(data, pixels)
	_check(data.fingerprint() == before, "ramp_fixture_mutated")
	for direction: int in range(4):
		var low := Vector2i(30 + direction * 6, 40)
		_check_shared_ramp(data, pixels, low, data, pixels, low + TerrainData.DIRECTIONS[direction], direction)
	for cell: Vector2i in [Vector2i(21, 20), Vector2i(41, 60)]:
		_check(_pixel(pixels, cell * 3 + Vector2i.ONE) == _ramp_color(2.0), "ramp_junction_color_reset")
		_continuity_checks += 1
	# Two adjacent parallel slopes share a filled seam, including their middle crossing.
	for x: int in range(70 * 3 + 1, 71 * 3 + 2):
		var upper := _pixel(pixels, Vector2i(x, 50 * 3 + 2))
		var lower := _pixel(pixels, Vector2i(x, 51 * 3))
		_check(upper == lower and upper in [_ramp_color(1.0), _ramp_color(1.5), _ramp_color(2.0)],
			"parallel_ramp_seam_gap")
		_continuity_checks += 1
	# Each Site owns only its half; the halo-derived drop still gives the same shared colour.
	for direction: int in range(4):
		var first := _empty_ramp_map()
		var second := _empty_ramp_map()
		var low: Vector2i = [Vector2i(50, 0), Vector2i(99, 50), Vector2i(50, 99), Vector2i(0, 50)][direction]
		var high: Vector2i = [Vector2i(50, 99), Vector2i(0, 50), Vector2i(50, 0), Vector2i(99, 50)][direction]
		first.height_levels[first.index(low)] = 1
		first.ramp_edges[first.index(low)] = 1 << direction
		second.height_levels[second.index(high)] = 2
		second.ramp_edges[second.index(high)] = 1 << ((direction + 2) % 4)
		second.cliff_drops[second.index(high) * 4 + ((direction + 2) % 4)] = 1
		var first_hash := first.fingerprint()
		var second_hash := second.fingerprint()
		_check_shared_ramp(first, Preview.from_terrain(first), low,
			second, Preview.from_terrain(second), high, direction)
		_check(first.fingerprint() == first_hash and second.fingerprint() == second_hash,
			"border_ramp_fixture_mutated")

func _empty_ramp_map() -> TerrainData:
	var data := TerrainData.new()
	data.allocate(Vector2i(100, 100))
	data.water_kind.resize(10000)
	data.flags.fill(TerrainData.Flag.WALKABLE)
	return data

func _parallel_border() -> void:
	for direction: int in range(4):
		var fixture := HaloSource.new()
		fixture.direction = direction
		var normal: Vector2i = TerrainData.DIRECTIONS[direction]
		var tangent := Vector2i(-normal.y, normal.x)
		var cell: Vector2i = [Vector2i(99, 50), Vector2i(49, 99), Vector2i(0, 49), Vector2i(50, 0)][direction]
		var other_cell := cell + tangent
		other_cell = Vector2i(posmod(other_cell.x, 100), posmod(other_cell.y, 100))
		var first := Adapter.build(fixture, Vector2i.ZERO)
		var second := Adapter.build(fixture, Vector2i(tangent.x, -tangent.y))
		_check(first.ok and second.ok, "parallel_halo_fixture_failed")
		var data: TerrainData = first.data
		var adjacent: TerrainData = second.data
		_check(data.parameters.ramp_visual_halo.size() == 404, "halo_not_complete_outer_ring")
		# Explicit parallel test entrances: natural height-only halo samples must
		# not widen them, even when a neighbour has the same two levels.
		for pair: Array in [[data, cell], [adjacent, other_cell]]:
			var terrain: TerrainData = pair[0]
			var from: Vector2i = pair[1]
			var to := from + normal
			_link_ramp(terrain, from, to, int(terrain.height_levels[terrain.index(from)]), int(terrain.height_levels[terrain.index(to)]))
			terrain.flags[terrain.index(from)] |= TerrainData.Flag.RAMP
			terrain.flags[terrain.index(to)] |= TerrainData.Flag.RAMP
		var before := data.fingerprint()
		var other_before := adjacent.fingerprint()
		_check(TerrainRenderer.ramp_span(data, cell, direction) == Vector2(-18, 18)
			and TerrainRenderer.ramp_span(adjacent, other_cell, direction) == Vector2(-18, 18), "natural_halo_invented_wide_pass")
		_check(data.fingerprint() == before and adjacent.fingerprint() == other_before, "parallel_halo_mutated_terrain")
		if direction == 0:
			var atlas := Atlas.new()
			var old_halo: Dictionary = data.parameters.ramp_visual_halo.duplicate(true)
			var revision := data.navigation_revision
			fixture.altered_east = true
			fixture.invalid_corner = true
			var rejected := atlas.refresh_boundary(data, Vector2i.ZERO, _query_halo.bind(fixture))
			_check(not rejected.ok and rejected.code == "INVALID_NEIGHBOUR"
				and data.fingerprint() == before and data.parameters.ramp_visual_halo == old_halo
				and data.navigation_revision == revision, "invalid_corner_committed_partial_boundary")
			fixture.invalid_corner = false
			_check(atlas.refresh_boundary(data, Vector2i.ZERO, _query_halo.bind(fixture)).ok,
				"edited_neighbour_refresh_failed")
			_check(TerrainRenderer.ramp_span(data, cell, direction).y == 18.0
				and data.parameters.ramp_visual_halo != old_halo,
				"edited_neighbour_kept_stale_halo")
			fixture.altered_east = false
			_check(atlas.refresh_boundary(data, Vector2i.ZERO, _query_halo.bind(fixture)).ok,
				"restored_neighbour_refresh_failed")
			_check(TerrainRenderer.ramp_span(data, cell, direction).y == 18.0
				and data.parameters.ramp_visual_halo == old_halo and data.fingerprint() == before,
				"restored_neighbour_did_not_restore_join")

func _query_halo(site: Vector2i, cell: Vector2i, fixture: HaloSource) -> Dictionary:
	var center := Grid.cell_center_mm(site, cell)
	return fixture._sample_site_meters(float(center.easting_mm) / 1000.0, float(center.northing_mm) / 1000.0, {})

func _check_real_bounded_passes(data: TerrainData) -> void:
	var checked := 0
	for index: int in range(data.ramp_edges.size()):
		for direction: int in range(4):
			if (data.ramp_edges[index] & (1 << direction)) != 0:
				_check(TerrainRenderer.ramp_span(data, data.cell_from_index(index), direction) == Vector2(-18, 18), "real_pass_ate_cliff_shoulders")
				checked += 1
	_check(checked > 0, "real_yushan_no_selected_passes")
	_continuity_checks += checked

func _link_ramp(data: TerrainData, from: Vector2i, to: Vector2i, from_level: int, to_level: int) -> void:
	var direction := TerrainData.DIRECTIONS.find(to - from)
	var opposite := (direction + 2) % 4
	var a := data.index(from)
	var b := data.index(to)
	data.height_levels[a] = from_level
	data.height_levels[b] = to_level
	data.ramp_edges[a] |= 1 << direction
	data.ramp_edges[b] |= 1 << opposite
	data.cliff_drops[a * 4 + direction] = maxi(0, from_level - to_level)
	data.cliff_drops[b * 4 + opposite] = maxi(0, to_level - from_level)

func _check_shared_ramp(a: TerrainData, a_pixels: PackedByteArray, a_cell: Vector2i,
		b: TerrainData, b_pixels: PackedByteArray, b_cell: Vector2i, direction: int) -> void:
	var normal: Vector2i = TerrainData.DIRECTIONS[direction]
	var expected := _ramp_color((float(a.height_levels[a.index(a_cell)]) + float(b.height_levels[b.index(b_cell)])) * 0.5)
	var first := _pixel(a_pixels, a_cell * 3 + Vector2i.ONE + normal)
	var second := _pixel(b_pixels, b_cell * 3 + Vector2i.ONE - normal)
	_check(first == expected and second == expected, "shared_ramp_colour_discontinuity")
	_continuity_checks += 1

func _check_real_ramp_boundary(source: RegionData, site: Vector2i, baked: Dictionary) -> void:
	var data: TerrainData = baked.terrain_result.data
	for direction: int in range(4):
		var cells: Array[Vector2i] = []
		for offset: int in range(100):
			var cell: Vector2i = [Vector2i(offset, 0), Vector2i(99, offset), Vector2i(offset, 99), Vector2i(0, offset)][direction]
			if data.ramp_edges[data.index(cell)] & (1 << direction):
				cells.append(cell)
		if cells.is_empty():
			continue
		var normal: Vector2i = TerrainData.DIRECTIONS[direction]
		var other := Preview.bake(source, site + Vector2i(normal.x, -normal.y))
		_check(bool(other.get("ok", false)), "real_neighbour_ramp_unavailable")
		if not bool(other.get("ok", false)):
			return
		var adjacent: TerrainData = other.terrain_result.data
		var ground := Preview.from_terrain(data, false)
		var adjacent_ground := Preview.from_terrain(adjacent, false)
		for cell: Vector2i in cells:
			var neighbour := cell + normal
			neighbour = Vector2i(posmod(neighbour.x, 100), posmod(neighbour.y, 100))
			_check((adjacent.ramp_edges[adjacent.index(neighbour)] & (1 << ((direction + 2) % 4))) != 0,
				"real_ramp_boundary_not_reciprocal")
			_check_shared_ramp(data, ground, cell, adjacent, adjacent_ground, neighbour, direction)
		return
	_check(false, "real_yushan_has_no_boundary_ramp_for_test")

func _check_pixels(data: TerrainData, pixels: PackedByteArray) -> void:
	if pixels.size() != 300 * 300 * 4:
		_check(false, "pixel_buffer_length")
		return
	for y: int in range(100):
		for x: int in range(100):
			var cell := Vector2i(x, y)
			var index := data.index(cell)
			var water := data.surface_types[index] == TerrainData.Surface.WATER
			var expected: Color = Preview.SURFACE_COLORS[data.surface_types[index]]
			if water:
				expected = Preview.SEA_COLOR if data.water_kind[index] == 2 else Preview.INLAND_WATER_COLOR
			else:
				expected = expected.lerp(Color(0.96, 0.91, 0.63), float(data.height_levels[index]) * 0.04)
			var center := cell * 3 + Vector2i.ONE
			var center_color := _ramp_color(float(data.height_levels[index])) if not water and data.ramp_edges[index] != 0 \
				else Color8(expected.r8, expected.g8, expected.b8)
			_check(_pixel(pixels, center) == center_color, "cell_content:%s" % cell)
			_checked_cells += 1
			for direction: int in range(4):
				var adjacent := cell + TerrainData.DIRECTIONS[direction]
				var edge_color := expected
				if data.cliff_drops[index * 4 + direction] > 0:
					edge_color = Preview.CLIFF_COLOR
				elif not water and data.contains(adjacent) and data.surface_types[data.index(adjacent)] == TerrainData.Surface.WATER:
					edge_color = Preview.SHORE_COLOR
				if not water and data.ramp_edges[index] & (1 << direction):
					var other_level := float(data.height_levels[data.index(adjacent)]) if data.contains(adjacent) \
						else float(data.height_levels[index]) + (-1.0 if data.cliff_drops[index * 4 + direction] > 0 else 1.0)
					edge_color = _ramp_color((float(data.height_levels[index]) + other_level) * 0.5)
				elif not water:
					for perpendicular: int in [(direction + 1) % 4, (direction + 3) % 4]:
						if (data.ramp_edges[index] & (1 << perpendicular)) == 0:
							continue
						var axis: Vector2i = TerrainData.DIRECTIONS[perpendicular]
						var tangent := Vector2i(-axis.y, axis.x)
						var offset: Vector2i = TerrainData.DIRECTIONS[direction]
						var across := float(offset.x * tangent.x + offset.y * tangent.y) * 64.0 / 3.0
						var span := TerrainRenderer.ramp_span(data, cell, perpendicular)
						if across >= span.x and across <= span.y:
							edge_color = center_color
				_check(_pixel(pixels, center + TerrainData.DIRECTIONS[direction]) == Color8(edge_color.r8, edge_color.g8, edge_color.b8),
					"owner_edge:%s:%d" % [cell, direction])
				_checked_edges += 1

func _ramp_color(level: float) -> Color:
	var color := Preview.RAMP_LOW_COLOR.lerp(Preview.RAMP_COLOR, clampf(level / 5.0, 0.0, 1.0))
	return Color8(color.r8, color.g8, color.b8)

func _pixel(pixels: PackedByteArray, point: Vector2i) -> Color:
	var offset := (point.y * 300 + point.x) * 4
	return Color8(pixels[offset], pixels[offset + 1], pixels[offset + 2], pixels[offset + 3])

func _check(ok: bool, message: String) -> void:
	if not ok and _failures.size() < 20:
		_failures.append(message)
