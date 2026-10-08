extends SceneTree
## Read-only source/terrain contract for sparse Taiwan mountain passes.

const Atlas = preload("res://scripts/region_lab/region_data.gd")
const Adapter = preload("res://scripts/region_lab/region_terrain_adapter.gd")
const Slot = preload("res://scripts/region_lab/region_save_slot.gd")
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const SITE := Vector2i(1228, 12981)
var _output := "res://output/region_mountain_passes/20261001/result.json"

var _failures: Array[String] = []
var _report: Dictionary = {"site": [SITE.x, SITE.y]}

func _init() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			_output = argument.trim_prefix("--output=")
	call_deferred("_run")

func _run() -> void:
	var source: RegionData = Atlas.new()
	var loaded: Dictionary = source.load_manifest()
	if not _check(bool(loaded.get("ok", false)), "MANIFEST_LOAD:" + str(loaded.get("code", "UNKNOWN"))):
		_finish()
		return
	var opened: Dictionary = source.make_terrain_data(SITE.x, SITE.y)
	if not _check(bool(opened.get("ok", false)), "YUSHAN_BUILD:" + str(opened.get("code", "UNKNOWN"))):
		_finish()
		return
	var data: TerrainData = opened.data
	var original_fingerprint: String = data.fingerprint()
	var original_ramps: PackedByteArray = data.ramp_edges.duplicate()
	_report["manifest_sha256"] = source.manifest_hash
	_report["ramp_rule_revision"] = str(opened.base.get("ramp_rule_revision", ""))
	_report["fingerprint"] = original_fingerprint
	_check(str(opened.base.get("ramp_rule_revision", "")) == str(Adapter.RAMP_RULE_REVISION), "BASE_RAMP_RULE_UNPINNED")
	_check(str(Adapter.RAMP_RULE_REVISION) == "sparse_platform_passes_v1", "UNEXPECTED_RAMP_RULE_REVISION")
	_check(original_fingerprint == str(opened.base.terrain_fingerprint), "BASE_FINGERPRINT_MISMATCH")
	_check(data.parameters.get("fixed_ramp_edges") is PackedByteArray
		and data.parameters.fixed_ramp_edges == original_ramps, "BASE_RAMP_TEMPLATE_MISSING")
	_check_old_pin(source)
	_check_terrain(data)
	var refreshed: Dictionary = source.refresh_boundary(data, SITE)
	_check(bool(refreshed.get("ok", false)) and data.ramp_edges == original_ramps
		and data.fingerprint() == original_fingerprint, "REFRESH_REPAINTED_OR_CHANGED_PASSES")
	_check_template_restore(source, data, original_fingerprint, original_ramps)
	_check_saved_passes(source, data)
	for direction: int in range(4):
		var normal: Vector2i = TerrainData.DIRECTIONS[direction]
		var neighbour_site := SITE + Vector2i(normal.x, -normal.y)
		var neighbour_result: Dictionary = source.make_terrain_data(neighbour_site.x, neighbour_site.y)
		if _check(bool(neighbour_result.get("ok", false)), "NEIGHBOUR_BUILD_%d" % direction):
			_check_boundary(data, neighbour_result.data, direction)
	var repeated: Dictionary = source.make_terrain_data(SITE.x, SITE.y)
	_check(bool(repeated.get("ok", false)) and repeated.data.fingerprint() == original_fingerprint
		and repeated.data.ramp_edges == original_ramps, "REPEAT_BUILD_UNSTABLE")
	_finish()

func _check_old_pin(source: RegionData) -> void:
	var pin: Dictionary = {"format": 1, "world_instance_id": "pass_contract", "slot_id": "test",
		"atlas_id": str(source.manifest.atlas_id),
		"grid_contract_version": int(source.manifest.grid_contract_version),
		"base_revision": str(source.manifest.base_revision), "manifest_sha256": source.manifest_hash,
		"ramp_rule_revision": str(Adapter.RAMP_RULE_REVISION)}
	if not source.resource_manifest_hash.is_empty():
		pin["resource_layer_sha256"] = source.resource_manifest_hash
		pin["resource_rule_revision"] = source.resource_rule_revision
	var old_pin: Dictionary = pin.duplicate(true)
	old_pin.erase("ramp_rule_revision")
	_check(Slot._same_pin(pin, pin) and not Slot._same_pin(old_pin, pin), "OLD_SLOT_PIN_ACCEPTED")

func _check_terrain(data: TerrainData) -> void:
	var legacy: PackedInt32Array = _components(data, true)
	var sparse: PackedInt32Array = _components(data, false)
	var mapping: Dictionary = {}
	var legacy_groups: Dictionary = {}
	var sparse_groups: Dictionary = {}
	for i: int in range(legacy.size()):
		if legacy[i] < 0:
			_check(sparse[i] < 0, "COMPONENT_CELL_SET_CHANGED")
			continue
		legacy_groups[legacy[i]] = true
		sparse_groups[sparse[i]] = true
		if mapping.has(legacy[i]):
			_check(int(mapping[legacy[i]]) == sparse[i], "ORIGINAL_REACHABILITY_SPLIT")
		else:
			mapping[legacy[i]] = sparse[i]
	var candidate_count := 0
	var pass_count := 0
	var blocked_direct := 0
	var detour_from := Vector2i(-1, -1)
	var detour_to := Vector2i(-1, -1)
	for y: int in range(data.size.y):
		for x: int in range(data.size.x):
			var cell := Vector2i(x, y)
			var i: int = data.index(cell)
			if not data.is_terrain_walkable(cell):
				continue
			for direction: int in [1, 2]:
				var next: Vector2i = cell + TerrainData.DIRECTIONS[direction]
				if not data.is_terrain_walkable(next):
					continue
				var j: int = data.index(next)
				if absi(int(data.height_levels[i]) - int(data.height_levels[j])) != 1:
					continue
				candidate_count += 1
				var has_pass: bool = (data.ramp_edges[i] & (1 << direction)) != 0 \
					and (data.ramp_edges[j] & (1 << ((direction + 2) % 4))) != 0
				if has_pass:
					pass_count += 1
				else:
					blocked_direct += 1
					_check(not data.can_step(cell, next), "UNMARKED_ONE_LEVEL_EDGE_WALKABLE")
					if detour_from.x < 0 and sparse[i] >= 0 and sparse[i] == sparse[j]:
						detour_from = cell
						detour_to = next
	_check(candidate_count > 0 and pass_count * 2 < candidate_count, "MOUNTAIN_PASSES_NOT_SPARSE")
	_check(legacy_groups.size() == sparse_groups.size() and legacy_groups.size() > 0,
		"REACHABLE_COMPONENT_COUNT_CHANGED")
	var route: Array[Vector2i] = []
	if detour_from.x >= 0:
		route = data.path_between(detour_from, detour_to)
	_check(detour_from.x >= 0 and route.size() > 1 and route[route.size() - 1] == detour_to,
		"NO_INDIRECT_UPHILL_ROUTE")
	_report["terrain"] = {"dry_one_level_edges": candidate_count, "selected_internal_passes": pass_count,
		"non_pass_one_level_edges": blocked_direct, "legacy_components": legacy_groups.size(),
		"sparse_components": sparse_groups.size(), "detour_steps": route.size()}

func _components(data: TerrainData, legacy: bool) -> PackedInt32Array:
	var parents := PackedInt32Array()
	parents.resize(data.size.x * data.size.y)
	for i: int in range(parents.size()):
		parents[i] = i if data.is_walkable(data.cell_from_index(i)) \
			and (data.static_blocked.is_empty() or data.static_blocked[i] == 0) else -1
	for y: int in range(data.size.y):
		for x: int in range(data.size.x):
			var cell := Vector2i(x, y)
			var i: int = data.index(cell)
			if parents[i] < 0:
				continue
			for direction: int in [1, 2]:
				var next: Vector2i = cell + TerrainData.DIRECTIONS[direction]
				if not data.contains(next):
					continue
				var j: int = data.index(next)
				if parents[j] < 0:
					continue
				var connected: bool = absi(int(data.height_levels[i]) - int(data.height_levels[j])) <= 1 \
					if legacy else data.can_step(cell, next)
				if connected:
					var a: int = _root(parents, i)
					var b: int = _root(parents, j)
					parents[a] = b
	for i: int in range(parents.size()):
		if parents[i] >= 0:
			parents[i] = _root(parents, i)
	return parents

func _root(parents: PackedInt32Array, i: int) -> int:
	var current := i
	while parents[current] != current:
		parents[current] = parents[parents[current]]
		current = parents[current]
	return current

func _check_boundary(data: TerrainData, other: TerrainData, direction: int) -> void:
	var opposite := (direction + 2) % 4
	var contacts := PackedInt32Array()
	contacts.resize(100)
	var mismatches := 0
	for offset: int in range(100):
		var a: int = data.index(Adapter.boundary_cell(direction, offset))
		var b: int = other.index(Adapter.boundary_cell(opposite, offset))
		var dry: bool = data.surface_types[a] != TerrainData.Surface.WATER \
			and other.surface_types[b] != TerrainData.Surface.WATER
		var level_a: int = data.height_levels[a]
		var level_b: int = other.height_levels[b]
		contacts[offset] = level_a * 8 + level_b if dry and absi(level_a - level_b) == 1 else -1
		var bit_a: bool = (data.ramp_edges[a] & (1 << direction)) != 0
		var bit_b: bool = (other.ramp_edges[b] & (1 << opposite)) != 0
		if bit_a != bit_b:
			mismatches += 1
	var selected := PackedInt32Array()
	var start := 0
	while start < 100:
		var end := start + 1
		while end < 100 and contacts[end] == contacts[start]:
			end += 1
		if contacts[start] >= 0:
			selected.append(floori(float(start + end - 1) * 0.5))
		start = end
	for offset: int in range(100):
		var a: int = data.index(Adapter.boundary_cell(direction, offset))
		var bit: bool = (data.ramp_edges[a] & (1 << direction)) != 0
		if bit != selected.has(offset):
			mismatches += 1
	_check(mismatches == 0, "BOUNDARY_PASS_MISMATCH_%d" % direction)
	_report["boundary_%d" % direction] = {"segments": selected.size(), "midpoint_offsets": selected,
		"mismatches": mismatches}

func _check_template_restore(source: RegionData, data: TerrainData, original: String,
		original_ramps: PackedByteArray) -> void:
	var low := Vector2i(-1, -1)
	var high := Vector2i(-1, -1)
	var direction := -1
	for y: int in range(1, 99):
		if direction >= 0:
			break
		for x: int in range(1, 99):
			var cell := Vector2i(x, y)
			var i: int = data.index(cell)
			for d: int in [1, 2]:
				var next: Vector2i = cell + TerrainData.DIRECTIONS[d]
				var j: int = data.index(next)
				if (original_ramps[i] & (1 << d)) == 0 \
					or int(data.height_levels[i]) == int(data.height_levels[j]):
					continue
				low = cell if data.height_levels[i] < data.height_levels[j] else next
				high = next if low == cell else cell
				direction = TerrainData.DIRECTIONS.find(high - low)
				break
			if direction >= 0:
				break
	if not _check(direction >= 0, "NO_INTERNAL_PASS_FOR_TEMPLATE_RESTORE"):
		return
	var high_i: int = data.index(high)
	var low_i: int = data.index(low)
	var previous_height: int = data.height_levels[high_i]
	data.height_levels[high_i] = data.height_levels[low_i]
	Runtime.rebuild_terrain_edges(data)
	var removed: bool = (data.ramp_edges[low_i] & (1 << direction)) == 0 \
		and (data.ramp_edges[high_i] & (1 << ((direction + 2) % 4))) == 0
	data.height_levels[high_i] = previous_height
	Runtime.rebuild_terrain_edges(data)
	var refreshed: Dictionary = source.refresh_boundary(data, SITE)
	var restored: bool = bool(refreshed.get("ok", false)) \
		and (data.ramp_edges[low_i] & (1 << direction)) != 0 \
		and (data.ramp_edges[high_i] & (1 << ((direction + 2) % 4))) != 0 \
		and data.ramp_edges == original_ramps and data.fingerprint() == original
	_check(removed and restored, "FIXED_PASS_TEMPLATE_NOT_RESTORED")
	_report["template_roundtrip"] = {"low": [low.x, low.y], "high": [high.x, high.y],
		"removed_at_equal_height": removed, "restored_fingerprint": restored}

func _check_saved_passes(source: RegionData, base: TerrainData) -> void:
	var slot := Slot.new()
	var created := slot.open_map(source, "mountain_%d" % Time.get_ticks_usec(), "passes")
	if not _check(bool(created.get("ok", false)), "SAVE_SLOT_CREATE"):
		return
	var opened := slot.open_site(SITE)
	if not _check(bool(opened.get("ok", false)), "SAVE_SITE_OPEN"):
		return
	var data: TerrainData = opened.data
	var selected := Vector2i(-1, -1)
	var closed := Vector2i(-1, -1)
	for y: int in range(2, 98):
		for x: int in range(2, 98):
			var cell := Vector2i(x, y)
			var a := data.index(cell)
			var b := data.index(cell + Vector2i.RIGHT)
			if selected.x < 0 and (data.ramp_edges[a] & (1 << 1)) != 0:
				selected = cell
			if closed.x < 0 and data.ramp_edges[a] == 0 and data.ramp_edges[b] == 0 \
					and data.height_levels[a] == data.height_levels[b] and data.height_levels[a] < 5:
				closed = cell
	if not _check(selected.x >= 0 and closed.x >= 0, "SAVE_PASS_FIXTURE_MISSING"):
		return
	var count := 0
	for case_name: String in ["selected_equal", "selected_restored", "closed_new_one_level", "closed_restored"]:
		var cell := selected if case_name.begins_with("selected") else closed
		var a := data.index(cell)
		var b := data.index(cell + Vector2i.RIGHT)
		var target_height := int(base.height_levels[b])
		if case_name == "selected_equal":
			target_height = int(data.height_levels[a])
		elif case_name == "closed_new_one_level":
			target_height = int(data.height_levels[a]) + 1
		data.height_levels[b] = target_height
		data.site.terrain_changes[str(b)] = target_height
		Runtime.rebuild_terrain_edges(data)
		var should_have_pass := case_name == "selected_restored"
		_check(((data.ramp_edges[a] & (1 << 1)) != 0) == should_have_pass, "LIVE_PASS_SELECTION_" + case_name)
		var saved := slot.save_site(data)
		if not _check(bool(saved.get("ok", false)), "SAVE_FAILED_" + case_name):
			return
		var before := data.fingerprint()
		var before_ramps := data.ramp_edges.duplicate()
		var before_step := data.can_step(cell, cell + Vector2i.RIGHT)
		var envelope: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(slot.site_path(SITE)))
		var payload: Dictionary = JSON.parse_string(str(envelope.payload))
		_check(not payload.parameters.has("fixed_ramp_edges"), "TRANSIENT_TEMPLATE_WAS_SAVED")
		var reloaded := slot.open_site(SITE)
		if not _check(bool(reloaded.get("ok", false)), "RELOAD_FAILED_" + case_name):
			return
		var after: TerrainData = reloaded.data
		_check(after.ramp_edges == before_ramps and after.fingerprint() == before
			and after.can_step(cell, cell + Vector2i.RIGHT) == before_step
			and after.parameters.get("fixed_ramp_edges") is PackedByteArray, "SAVE_PASS_CHANGED_" + case_name)
		count += 1
	_report["save_roundtrips"] = count

func _check(condition: bool, code: String) -> bool:
	if not condition and _failures.size() < 32:
		_failures.append(code)
	return condition

func _finish() -> void:
	_report["failures"] = _failures
	var absolute := ProjectSettings.globalize_path(_output)
	var folder := absolute.get_base_dir()
	if DirAccess.make_dir_recursive_absolute(folder) == OK:
		var file := FileAccess.open(absolute, FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(_report, "\t"))
			file.close()
		else:
			_failures.append("REPORT_WRITE_FAILED")
	else:
		_failures.append("REPORT_DIRECTORY_FAILED")
	_report["failures"] = _failures
	print("REGION_MOUNTAIN_PASS_CONTRACT_", "PASS " if _failures.is_empty() else "FAIL ", JSON.stringify(_report))
	quit(0 if _failures.is_empty() else 1)
