extends "res://scripts/tests/site_technology_settlement_ship_test.gd"
## True original Window -> actual finite order -> two physical transfer legs ->
## local source -> original WT/Fatigue -> one original ferry. NOT_RUN.
## Opening/querying never creates knowledge; known S12/F13 are fixture inputs.
const ProductiveWindow = preload("res://scripts/terrain_lab/site_tech_window.gd")

func _choose_ui(choice: OptionButton, field: String, value: Variant) -> void:
	for index: int in choice.item_count:
		var ref: Variant = choice.get_item_metadata(index)
		if ref is Dictionary and ref.get(field) == value:
			choice.select(index)
			return
	_check(false, "Original UI has the actual selector %s=%s" % [field, str(value)])

func _choose_node(window: SiteTechWindow, node_id: String) -> void:
	for index: int in window._scope_node.item_count:
		if window._scope_node.get_item_metadata(index) == node_id:
			window._scope_node.select(index)
			window.refresh()
			return
	_check(false, "Original Window contains the selected productive node")

func _window_ship_output() -> void:
	var f := _ship_order_fixture()
	var column := VBoxContainer.new()
	root.add_child(column)
	var window := ProductiveWindow.new()
	f.lab.site_controller.feature_key = str(f.yard)
	var before := var_to_bytes([f.data.site, f.team.capture_combat_state()])
	window.install(f.lab.site_controller, column)
	_choose_node(window, "S12")
	_check(var_to_bytes([f.data.site, f.team.capture_combat_state()]) == before, "Installing/selecting original productive controls is byte-identical")
	var form: Dictionary = window._productive_form()
	_choose_ui(window._scope_researcher, "person_id", int(f.executor))
	_choose_ui(form.helper, "person_id", int(f.helper))
	_choose_ui(form.carrier, "person_id", int(f.control))
	_choose_ui(form.source, "id", "feature:" + str(f.warehouse))
	window._productive_adopt(true)
	_check(var_to_bytes([f.data.site, f.team.capture_combat_state()]) == before, "Actual UI adoption preview does not pay, spawn or create a saved order")
	window._productive_adopt(false)
	var orders: Dictionary = f.data.site.settlement.technology_operations.orders
	_check(orders.size() == 1, "Actual original UI command adopts exactly one finite owner order")
	var id := str(orders.keys()[0])
	_choose_ui(form.order, "key", id)
	_check(Stocks.ensure_storage(f.data, str(f.yard), 1).ok, "Explicit original stock owner opens the adopted yard endpoint")
	window.refresh()
	_choose_ui(form.order, "key", id)
	window._productive_step()
	_check(orders[id].payload.delivery_receipts.size() == 1 and orders[id].payload.spent.is_empty(), "UI first step publishes one real donor-to-carrier transfer without manufacture double-payment")
	_check(f.lab.character.place(f.data.cell_from_index(int(f.data.site.features[f.yard].entrance)), true), "Same actual carrier reaches the second original contact")
	window._productive_step()
	_check(orders[id].payload.delivery_receipts.size() == 2, "UI second step deposits the real original carrier materials once")
	_choose_ui(form.source, "id", "feature:" + str(f.yard))
	window._productive_source(false)
	_check(orders[id].payload.source.status == "granted" and orders[id].payload.spent.is_empty(), "UI explicit finite source grant changes no manufacture spend")
	var next := str(f.data.site.next_vehicle)
	var camp := var_to_bytes([f.data.site.inventory, f.data.site.depot_items])
	window._productive_step()
	_check(f.data.site.features[f.yard].has("ship_build") and f.row.work_task.named and f.team.combat_units[2].work_task.named, "UI begins the original paid hull with two true original named tasks")
	_place_ship_workers(f)
	var intervals := 0
	while f.data.site.features[f.yard].has("ship_build") and intervals < 20:
		_shipyard_work_point(f, 30.0)
		intervals += 1
	_check(intervals == 9 and f.data.site.vehicles[next].ship_type == "ferry" and orders[id].receipts.size() == 1, "Thin original UI reaches one real ferry and bounded owner output at540 aggregate effort")
	_check(var_to_bytes([f.data.site.inventory, f.data.site.depot_items]) == camp, "The original UI never converts private local cost into camp debit")
	window.refresh()
	_choose_ui(form.order, "key", id)
	before = var_to_bytes([f.data.site, f.team.capture_combat_state()])
	window._productive_step()
	_check(var_to_bytes([f.data.site, f.team.capture_combat_state()]) == before, "Completed UI order cannot manufacture another ferry")
	column.free()
	_cleanup_fixture(f.lab, f.team)
	await process_frame

func _run() -> void:
	deadline = Time.get_ticks_msec() + 180000
	await _window_ship_output()
	print("SITE_PRODUCTIVE_SHIP_WINDOW_SOURCE_FIXTURE: checks=%d; actual original order/physical source/ferry; NOT_RUN until canonical launch" % checks)
	quit(0)
