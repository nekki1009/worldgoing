extends "res://scripts/tests/site_technology_siege_yard_test.gd"
## Original known level3 Settlement, original head/F11 NPC/ground and Window.
## No earned research assertion; original config/geometry/cold owner checks.
const ProductiveYardWindow = preload("res://scripts/terrain_lab/site_tech_window.gd")

func _yard_window() -> void:
	var f := _yard_fixture()
	var column := VBoxContainer.new()
	root.add_child(column)
	var window := ProductiveYardWindow.new()
	f.lab.site_controller.feature_key = str(f.yard)
	var before := var_to_bytes([f.data.site, f.team.capture_combat_state()])
	window.install(f.lab.site_controller, column)
	for index: int in window._scope_node.item_count:
		if window._scope_node.get_item_metadata(index) == "S11": window._scope_node.select(index)
	window.refresh()
	for index: int in window._scope_researcher.item_count:
		var row: Dictionary = window._scope_researcher.get_item_metadata(index)
		if row.get("person_id") == int(f.executor): window._scope_researcher.select(index)
	_check(var_to_bytes([f.data.site, f.team.capture_combat_state()]) == before, "Opening/selecting actual ground/master is pure and does not appoint a new head")
	window._productive_configure(true)
	var ground: Dictionary = f.data.site.features[f.yard]
	_check(ground.kind == "training_ground" and ground.technology_siege_yard == {"version": 1, "settlement_id": str(f.settlement_id)}, "Actual original Window names the original finite six-station yard config")
	_check(Runtime.technology_siege_yard_context(f.data, str(f.yard)).ok and not Runtime.is_training_facility(ground), "Actual current original query keeps training mutually exclusive")
	f.lab.site_controller._capture_positions()
	_check(YardStore.save(f.data, "user://technology_s11_window_original.json").ok, "Original Store saves the Window-adopted true ground")
	_check(YardStore.load_site("user://technology_s11_window_original.json").ok, "Strict original cold loader accepts the actual adopted config")
	window._productive_configure(false)
	_check(not ground.has("technology_siege_yard") and Runtime.is_training_facility(ground), "Actual original head can explicitly revoke and restore the same training ground")
	column.free()
	_cleanup_fixture(f.lab, f.team)
	await process_frame

func _run() -> void:
	deadline = Time.get_ticks_msec() + 180000
	await _yard_window()
	print("SITE_PRODUCTIVE_YARD_WINDOW_SOURCE_FIXTURE: checks=%d; original ground/head/config/cold; NOT_RUN until canonical launch" % checks)
	quit(0)
