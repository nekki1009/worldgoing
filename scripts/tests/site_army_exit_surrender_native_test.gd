extends SceneTree
## Original-row flags across native cold and hot readers; no rendering/FPS claim.
const EXTENSION := "res://native/army_idle/army_idle.gdextension"

func _initialize() -> void:
	_run.call_deferred()

func _row(identity: int) -> Dictionary:
	return {"person_id": identity, "hp": 100.0, "ko": 0.0, "age": 0.25, "think": 0.5,
		"stun": 0.0, "grace": 0.0, "pose": "idle", "attack": false, "member": true,
		"captive": false, "departed": false, "present": true, "visual_role": "male_atlas"}

func _project(reader: RefCounted, rows: Array, cells: Array) -> Array:
	var owners := {}
	var publications := {}
	var previous := []
	var descriptors := []
	var moving := []
	var facing := []
	var sprites := []
	var appearance := {"parts": {}}
	appearance.make_read_only()
	for index in range(rows.size()):
		owners[cells[index]] = index
		publications[int(rows[index].person_id)] = appearance
		previous.append(appearance)
		descriptors.append({"page": 0, "palette": 0})
		moving.append(Vector2i(-1, -1))
		facing.append(Vector2i.UP)
		sprites.append(null)
	var directions := []
	for direction in range(4):
		directions.append([direction, 1.0, true, PackedFloat64Array([0.0]), PackedVector2Array([Vector2.ZERO])])
	return [reader.call("capture_columns", rows, cells), reader.call("capture_people", rows, cells, self, 0),
		reader.call("movement_roster", rows, cells, owners, 0, Vector2i.ZERO),
		reader.call("movement_roster", rows, cells, owners, 1, Vector2i.ZERO),
		reader.call("movement_roster", rows, cells, owners, 2, Vector2i.ZERO),
		reader.call("command_presence", rows, cells, {}),
		reader.call("command_presence_delta", rows, cells, {}, 10.0, []),
		reader.call("render_idle", rows, cells, moving, facing, publications, previous, descriptors, [directions], sprites, 64.0)]

func _run() -> void:
	if not GDExtensionManager.is_extension_loaded(EXTENSION):
		assert(GDExtensionManager.load_extension(EXTENSION) == GDExtensionManager.LOAD_STATUS_OK)
	var kernel: RefCounted = ClassDB.instantiate(&"ArmyIdleKernel")
	var hot: RefCounted = ClassDB.instantiate(&"ArmyCombatHot")
	var rows := [_row(11), _row(12), _row(13), _row(14)]
	rows[1]["site_exited"] = true
	rows[2]["surrender_pending"] = true
	rows[3].merge({"site_exited": false, "surrender_pending": false})
	var cells := [Vector2i(2, 3), Vector2i(3, 3), Vector2i(4, 3), Vector2i(5, 3)]
	var original := var_to_bytes(rows)
	var expected := _project(kernel, rows, cells)
	assert(expected[0][0] == PackedInt32Array([0, 2, 3]), "Surrendered people remain hit targets; exited people do not")
	assert(expected[1].size() == 3 and expected[1][1].id == 13)
	assert(expected[2].value == [11, 14] and expected[3].value == Vector2i(4, 3), "Only active people enter movement roster/center")
	assert(expected[4].value == {11: cells[0], 13: cells[2], 14: cells[3]}, "Surrender keeps occupancy; site exit releases it")
	assert(expected[5][1][1] < 0.0 and expected[5][1][2] < 0.0, "Neither exited nor surrendered people have command presence")
	assert(expected[7][0] == PackedByteArray([1, 0, 1, 1]), "Surrender stays visible; site exit is absent from native render")
	assert(original == var_to_bytes(rows), "Native projections cannot mutate original people")
	assert(hot.load_rows(rows))
	assert(hot.can_act(0) and not hot.can_act(1) and not hot.can_act(2) and hot.can_act(3))
	assert(hot.retained_idle_mask() == PackedByteArray([1, 0, 1, 1]))
	assert(hot.column("site_exited") == PackedFloat64Array([0, 1, 0, 0]))
	assert(hot.column("surrender_pending") == PackedFloat64Array([0, 0, 1, 0]))
	assert(not hot.has_field(0, "site_exited") and not hot.get_field(0, "surrender_pending", false))
	var cold_rows := rows.duplicate(true)
	for index in range(rows.size()):
		for field: Variant in hot.capture_row(index).keys():
			cold_rows[index].erase(field)
	assert(var_to_bytes(_project(hot, cold_rows, cells)) == var_to_bytes(expected), "Stripped hot rows preserve every native projection")
	assert(hot.set_field(0, "surrender_pending", true) and not hot.can_act(0))
	assert(hot.capture_columns(cold_rows, cells)[0] == PackedInt32Array([0, 2, 3]))
	assert(hot.erase_field(0, "surrender_pending") and hot.can_act(0), "Legacy missing bool means false")
	assert(hot.set_field(0, "site_exited", true) and not hot.can_act(0) and hot.retained_idle_mask()[0] == 0)
	assert(hot.capture_columns(cold_rows, cells)[0] == PackedInt32Array([2, 3]))
	assert(hot.erase_field(0, "site_exited") and hot.can_act(0))
	for field: String in ["site_exited", "surrender_pending"]:
		assert(not hot.set_field(0, field, 1), "Flags require real bools")
		var invalid := [_row(21)]
		invalid[0][field] = null
		assert(not hot.load_rows(invalid) and hot.row_count() == 4, "Invalid load preserves prior original hot state")
	print("SITE_EXIT_SURRENDER_NATIVE_PASS legacy flags, hot mutation, targets, roster, occupancy, command presence, render projection, retained mask")
	quit(0)
