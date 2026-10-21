extends SceneTree
## Flat native/original contract plus the actual Store integration boundaries.
const Store = preload("res://scripts/terrain_lab/site_store.gd")
var kernel: RefCounted
var checks := 0
var failed := false

class Observer extends RefCounted:
	var calls := 0
	func _to_string() -> String:
		calls += 1
		return "coat"

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	checks += 1
	failed = failed or not ok
	print("ITEM RECORDS ", "OK: " if ok else "FAIL: ", label)

static func _original(state: Dictionary) -> Dictionary:
	for identity: Variant in state.item_records:
		var record: Variant = state.item_records[identity]
		if not Store._serial(identity, int(state.next_item)) or not record is Dictionary or record.size() != 3 + int(record.has("dye_color")):
			return Store.Runtime.fail("CORRUPT_SAVE", "裝備身分")
		if not record.get("definition") is String or not state.item_definitions.has(record.definition) or not Store._integer(record.get("original_owner"), 1, 2147483647) or not record.get("holder") is String:
			return Store.Runtime.fail("CORRUPT_SAVE", "裝備定義／物主引用")
		if record.has("dye_color") and (not Store.Runtime.EquipmentDye.valid_color(record.dye_color) or str(state.item_definitions[record.definition].slot) not in Store.Runtime.EquipmentDye.SLOTS):
			return Store.Runtime.fail("CORRUPT_SAVE", "裝備染色格式／槽位")
	return Store.Runtime.ok()

static func native_or_original(state: Dictionary) -> Dictionary:
	var api := TerrainArmy._get_idle_kernel()
	if api != null and api.has_method("item_records_valid") and api.item_records_valid(state.item_records, state.item_definitions, int(state.next_item), Store.Runtime.EquipmentDye.SLOTS):
		return Store.Runtime.ok()
	return _original(state)

func _base() -> Dictionary:
	return {"item_records": {"1": {"definition": "coat", "original_owner": 1, "holder": "person:1"}},
		"item_definitions": {"coat": {"slot": "armor", "asset": "armor_01", "tint": [1.0, 1.0, 1.0, 1.0]}}, "next_item": 4}

func _case(label: String, state: Dictionary, expected_hit: bool, valid: bool, message: String = "") -> void:
	var before := var_to_bytes(state)
	var original := _original(state)
	var hit: bool = kernel.item_records_valid(state.item_records, state.item_definitions, int(state.next_item), Store.Runtime.EquipmentDye.SLOTS)
	var actual := native_or_original(state)
	_check(hit == expected_hit and (not hit or original.ok), label + " native true only proves original success")
	_check(original == actual and bool(original.ok) == valid and (message.is_empty() or original.message == Store.Runtime.fail("CORRUPT_SAVE", message).message), label + " complete original/fallback result and error order")
	_check(before == var_to_bytes(state), label + " all input bytes unchanged")

func _guard_only(label: String, state: Dictionary) -> void:
	var before := var_to_bytes(state)
	_check(not kernel.item_records_valid(state.item_records, state.item_definitions, int(state.next_item), Store.Runtime.EquipmentDye.SLOTS), label + " native refusal without invoking unsafe original coercion")
	_check(before == var_to_bytes(state), label + " input unchanged")

func _cases() -> void:
	var state := _base()
	_check(Store.Runtime.valid_item_definition("coat", state.item_definitions.coat), "base uses a valid original definition")
	_case("canonical", state, true, true)
	state = _base()
	state.item_records.clear()
	_case("empty", state, true, true)
	for identity: Variant in ["0", "01", "+1", "-1", " 1", "1 ", "", "１", "١", "1😀", &"1", 1, "4", "10000000001"]:
		state = _base()
		state.item_records = {identity: state.item_records["1"]}
		_case("identity " + str(identity), state, false, false, "裝備身分")
	state = _base()
	state.next_item = 2147483647
	state.item_records = {"2147483646": state.item_records["1"]}
	_case("max canonical ID below next", state, true, true)
	for identity: String in ["9223372036854775808", "18446744073709551616", "1".repeat(100)]:
		state = _base()
		state.item_records = {identity: state.item_records["1"]}
		_guard_only("overflow/long identity", state)
	for owner: Variant in [1, 1.0, 2147483647, 2147483647.0, 0, -1, 2147483648, 1.5, NAN, INF, -INF, true, false, "1", null, 9223372036854775807, -9223372036854775807 - 1]:
		state = _base()
		state.item_records["1"].original_owner = owner
		var valid: bool = Store._integer(owner, 1, 2147483647)
		_case("owner " + str(owner), state, valid, valid, "" if valid else "裝備定義／物主引用")
	for field: String in ["definition", "original_owner", "holder"]:
		state = _base()
		state.item_records["1"].erase(field)
		_case("missing " + field, state, false, false, "裝備身分")
	for pair: Array in [["definition", "missing"], ["definition", &"coat"], ["definition", null], ["holder", &"person:1"], ["holder", null]]:
		state = _base()
		state.item_records["1"][pair[0]] = pair[1]
		_case("field type/reference " + str(pair[0]), state, false, false, "裝備定義／物主引用")
	state = _base()
	state.item_records["1"].holder = ""
	_case("empty holder is still flat-valid", state, true, true)
	state = _base()
	state.item_records["1"]["extra"] = true
	_case("extra size", state, false, false, "裝備身分")
	for body: Variant in [null, [], 1]:
		state = _base()
		state.item_records["1"] = body
		_case("record shape", state, false, false, "裝備身分")
	for color: Variant in ["123456ff", "ABCDEFfF", "12345600", "12345fff0", "12345ff", "ggggggff", "１２３４５６ff", "12345😀ff", "+fffffff", "-fffffff", null, 1]:
		state = _base()
		state.item_records["1"]["dye_color"] = color
		var valid: bool = Store.Runtime.EquipmentDye.valid_color(color)
		var signed: bool = color is String and color in ["+fffffff", "-fffffff"]
		_case("dye " + str(color), state, valid and not signed, valid, "" if valid else "裝備染色格式／槽位")
	for color: String in ["+fffffff", "-fffffff"]:
		_check(Store.Runtime.EquipmentDye.valid_color(color), "signed hex original policy is explicitly valid")
	for slot: String in ["helmet", "armor", "boots", "cape", "outfit", "weapon"]:
		state = _base()
		state.item_records["1"]["dye_color"] = "abcdefFF"
		state.item_definitions.coat.slot = slot
		var valid: bool = slot in Store.Runtime.EquipmentDye.SLOTS
		_case("original dye slot " + slot, state, valid, valid, "" if valid else "裝備染色格式／槽位")
	state = _base()
	state.item_records["1"] = {&"definition": "coat", &"original_owner": 1.0, &"holder": "person:1", &"dye_color": "abcdefFF"}
	state.item_definitions.coat = {&"slot": "armor", &"asset": "armor_01", &"tint": [1.0, 1.0, 1.0, 1.0]}
	_case("StringName field keys use engine lookup", state, true, true)
	var typed_records: Dictionary[String, Dictionary] = {"1": _base().item_records["1"]}
	state = _base()
	state.item_records = typed_records
	_case("typed records fallback", state, false, true)
	var typed_body: Dictionary[String, Variant] = {"definition": "coat", "original_owner": 1, "holder": "person:1"}
	state = _base()
	state.item_records["1"] = typed_body
	_case("typed record fallback", state, false, true)
	var typed_defs: Dictionary[String, Dictionary] = {"coat": _base().item_definitions.coat}
	state = _base()
	state.item_definitions = typed_defs
	_case("typed definitions fallback", state, false, true)
	state = _base()
	state.item_records["2"] = state.item_records["1"]
	var original_record: Dictionary = state.item_records["1"]
	var original_def: Dictionary = state.item_definitions.coat
	original_record.make_read_only()
	original_def.make_read_only()
	state.item_records.make_read_only()
	state.item_definitions.make_read_only()
	_case("readonly dictionaries and shared record", state, true, true)
	_check(is_same(state.item_records["1"], original_record) and is_same(state.item_records["2"], original_record) and is_same(state.item_definitions.coat, original_def) and original_record.is_read_only() and original_def.is_read_only(), "readonly input identities, flags and shared alias retained")
	for reverse: bool in [false, true]:
		state = _base()
		var bad_owner: Dictionary = state.item_records["1"].duplicate()
		bad_owner.original_owner = 0
		state.item_records = {"2": bad_owner, "01": {}} if not reverse else {"01": {}, "2": bad_owner}
		_case("multiple errors insertion order", state, false, false, "裝備定義／物主引用" if not reverse else "裝備身分")
	for definition: Variant in [null, 1, [], {"slot": 1}]:
		state = _base()
		state.item_definitions.coat = definition
		_guard_only("malformed definition direct native guard", state)
	state = _base()
	state.item_records.clear()
	var shared: Dictionary = _base().item_records["1"]
	for index in range(1, 100001): state.item_records[str(index)] = shared
	state.next_item = 100002
	_case("100000 soft admission boundary", state, true, true)
	state.item_records["100001"] = shared
	_case("100001 soft cap complete original fallback", state, false, true)
	_check(is_same(state.item_records["1"], shared) and is_same(state.item_records["100001"], shared), "soft cap retains original shared record identity")

func _integration() -> void:
	var observer := Observer.new()
	for field: String in ["definition", "holder", "dye_color"]:
		var state := _base()
		state.item_records["1"][field] = observer
		_case("Object field " + field, state, false, false, "裝備染色格式／槽位" if field == "dye_color" else "裝備定義／物主引用")
	_check(observer.calls == 0, "native and original never invoke Object conversion")
	var dyed := _base()
	dyed.item_records["1"]["dye_color"] = "abcdefFF"
	var slots: Array[String] = []
	slots.resize(64)
	slots.fill("armor")
	_check(kernel.item_records_valid(dyed.item_records, dyed.item_definitions, 4, slots), "64 typed String slots accepted")
	slots.append("armor")
	_check(not kernel.item_records_valid(dyed.item_records, dyed.item_definitions, 4, slots), "65 slots decline only native admission")
	_check(not kernel.item_records_valid(dyed.item_records, dyed.item_definitions, 4, [1]), "non String slot declines native admission")
	var readonly_slots := ["armor"]
	readonly_slots.make_read_only()
	_check(kernel.item_records_valid(dyed.item_records, dyed.item_definitions, 4, readonly_slots) and readonly_slots.is_read_only() and readonly_slots == ["armor"], "readonly dye slots preserved")
	for next_value: int in [0, 1, 2147483648]:
		_check(not kernel.item_records_valid(dyed.item_records, dyed.item_definitions, next_value, Store.Runtime.EquipmentDye.SLOTS), "next item outside native admission or ID range")
	var checked_before: bool = TerrainArmy._idle_kernel_checked
	var data := TerrainData.new()
	var state := _base()
	# A real Site always carries features/stockpiles; Store validates facility stock before holders.
	state.merge({"item_storage_version": Store.Runtime.ITEM_STORAGE_VERSION, "ground_loot": {}, "depot_items": {}, "next_loot": 1, "features": {}, "stockpiles": {}})
	for api: RefCounted in [kernel, null, RefCounted.new()]:
		TerrainArmy._idle_kernel_checked = true
		TerrainArmy._idle_kernel = api
		var invalid := state.duplicate(true)
		invalid.item_records["1"].original_owner = 0
		var before := var_to_bytes(invalid)
		_check(Store._validate_items(data, invalid) == Store.Runtime.fail("CORRUPT_SAVE", "裝備定義／物主引用") and before == var_to_bytes(invalid), "actual Store native/missing/missing-method complete fallback")
		invalid.item_definitions.coat.tint = [1]
		_check(Store._validate_items(data, invalid) == Store.Runtime.fail("CORRUPT_SAVE", "共用裝備定義"), "actual Store definitions fail before record error")
		_check(Store._validate_items(data, state) == Store.Runtime.fail("CORRUPT_SAVE", "物品持有欄位"), "actual Store still validates holders after flat success")
	TerrainArmy._idle_kernel = kernel
	TerrainArmy._idle_kernel_checked = checked_before

func _run() -> void:
	create_timer(60.0).timeout.connect(func() -> void: printerr("ITEM RECORDS FAIL: deadline"); quit(3))
	kernel = TerrainArmy._get_idle_kernel()
	if kernel == null:
		_check(_original(_base()).ok and native_or_original(_base()) == _original(_base()), "missing optional accelerator uses complete original loop")
		print("ITEM RECORDS SKIP: optional native boundary checks")
	else:
		_check(kernel.has_method("item_records_valid"), "installed actual native method required")
		if not failed:
			_cases()
			_integration()
	print("SITE STORE ITEM RECORDS PASS: " if not failed else "SITE STORE ITEM RECORDS FAIL: ", checks, " checks")
	quit(2 if failed else 0)
