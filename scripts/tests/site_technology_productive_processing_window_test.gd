extends "res://scripts/tests/site_technology_settlement_processing_test.gd"
## Actual original known operation through thin Window. Initial knowledge is
## fixture authorship; the oracle is a real paid batch, not earned research.
const ProcessingWindow = preload("res://scripts/terrain_lab/site_tech_window.gd")

func _processing_window() -> void:
	var f := _processing_fixture(true)
	var column := VBoxContainer.new()
	root.add_child(column)
	var window := ProcessingWindow.new()
	f.lab.site_controller.feature_key = str(f.kiln)
	var before := var_to_bytes([f.data.site, f.team.capture_combat_state()])
	window.install(f.lab.site_controller, column)
	for index: int in window._scope_node.item_count:
		if window._scope_node.get_item_metadata(index) == "S03": window._scope_node.select(index)
	window.refresh()
	for index: int in window._scope_researcher.item_count:
		if window._scope_researcher.get_item_metadata(index).get("person_id") == int(f.executor): window._scope_researcher.select(index)
	var form: Dictionary = window._productive_form()
	for index: int in form.source.item_count:
		if form.source.get_item_metadata(index).get("id") == "depot": form.source.select(index)
	window._productive_adopt(true)
	_check(var_to_bytes([f.data.site, f.team.capture_combat_state()]) == before, "Thin UI pure preview preserves actual original head/worker/source/order state")
	window._productive_adopt(false)
	var operations: Dictionary = f.data.site.settlement.technology_operations
	_check(operations.orders.size() == 1, "Original UI adopts one bounded charcoal order")
	var id := str(operations.orders.keys()[0])
	var order: Dictionary = operations.orders[id]
	_check(order.payload.max_batches == 3 and order.payload.cap == {"wood": 12} and order.payload.spent.is_empty(), "UI cannot convert the finite three-batch command into an unlimited owner")
	for index: int in form.order.item_count:
		if form.order.get_item_metadata(index).get("key") == id: form.order.select(index)
	var stock = f.data.site.inventory.duplicate()
	var archive := var_to_bytes([f.data.site.family.technology, f.data.site.settlement.technology, f.row.technology])
	window._productive_step()
	_check(int(f.data.site.inventory.wood) == int(stock.wood) - 4 and order.payload.spent == {"wood": 4}, "Actual UI start performs one original full batch payment")
	_processing_finish(f, str(f.kiln))
	_check(int(f.row.cargo.get("charcoal", 0)) == 2 and order.receipts.size() == 1 and order.payload.completed == 1, "Actual original output enters true worker cargo and bounded order history once")
	window._productive_source(true)
	_check(order.payload.source.status == "revoked" and order.payload.spent == {"wood": 4} and order.payload.cap == {"wood": 12}, "UI revocation preserves original finite cap and spent history")
	window._productive_source(false)
	_check(order.payload.source.status == "granted" and order.payload.spent == {"wood": 4}, "Explicit original camp regrant does not replenish spent")
	_check(var_to_bytes([f.data.site.family.technology, f.data.site.settlement.technology, f.row.technology]) == archive, "Ordinary UI operation never grants research evidence or another personal skill")
	column.free()
	_cleanup_fixture(f.lab, f.team)
	await process_frame

func _run() -> void:
	deadline = Time.get_ticks_msec() + 180000
	await _processing_window()
	print("SITE_PRODUCTIVE_PROCESSING_WINDOW_SOURCE_FIXTURE: checks=%d; original head/camp/batch/output/revoke; NOT_RUN until canonical launch" % checks)
	quit(0)
