extends "res://scripts/tests/site_work_team_test.gd"
## Explicit small fixtures for unavailable sources and dynamic occupancy.
const OUT := "res://output/npc_ai_acceptance_20260918/work"

func run() -> void:
	create_timer(25.0).timeout.connect(func() -> void: quit(1))
	_check_missing_work_and_resume()
	_check_missing_tools_and_delivery()
	_check_blocked_route_and_resume()
	_check_disabled_zone_and_replacement()
	assert(completed_checks == 4)
	print("SITE_WORK_AI_BOUNDARIES_PASS: explicit fixture; no-source retry, missing-tools wait then original second worker supplies tools and work resumes, mid-route blockage/cargo retention/recovery, disabled-zone release and new-zone replacement")
	TerrainArmy.release_contact_source()
	quit(0)

func _check_missing_work_and_resume() -> void:
	var f := _fixture()
	var identity := f.ids()[0]
	var row: Dictionary = f.army.combat_units[1]
	f.terrain.site.zones[0].active = false
	assert(f.crew.assign(f.army, [identity], f.army.combat_identity(0)).ok)
	var before := JSON.stringify([f.terrain.site.inventory, row.cargo, f.terrain.site.total_produced])
	f.tick(90.0)
	assert(row.work_task.target == "" and row.work_task.mode == "idle")
	assert(JSON.stringify([f.terrain.site.inventory, row.cargo, f.terrain.site.total_produced]) == before)
	assert(f.crew.is_assigned(identity), "No work is waiting, not silent command cancellation")
	f.terrain.site.zones[0].active = true
	f.tick(30.0)
	assert(row.work_task.target == "crew_a" and row.work_task.progress > 0.0)
	f.tick(300.0)
	assert(row.cargo == {"wood": 4})
	f.close()
	completed_checks += 1

func _check_missing_tools_and_delivery() -> void:
	var f := _fixture()
	var first: Dictionary = f.army.combat_units[1]
	var second: Dictionary = f.army.combat_units[2]
	# Declared scarcity fixture: tools start on the second original worker,
	# not in camp. Recovery requires that body's native travel and deposit.
	f.terrain.site.inventory.clear()
	second.cargo.tools = 1
	assert(f.crew.assign(f.army, [f.ids()[0]], f.army.combat_identity(0)).ok)
	f.tick(300.0)
	assert(first.cargo.is_empty() and int(f.terrain.site.total_produced) == 0)
	assert("工具" in str(first.work_task.status) and float(first.work_task.progress) == 0.0)
	assert(f.crew.assign(f.army, [f.ids()[1]], f.army.combat_identity(0)).ok)
	var delivered_tools := false
	var harvested := false
	for step in range(60):
		f.tick(30.0)
		f.army.prepare_combat(0.5)
		delivered_tools = delivered_tools or int(f.terrain.site.inventory.get("tools", 0)) == 1
		harvested = harvested or int(first.cargo.get("wood", 0)) > 0
		if not delivered_tools: assert(int(f.terrain.site.total_produced) == 0)
		if harvested and first.cargo.is_empty(): break
	assert(delivered_tools and harvested and first.cargo.is_empty() and int(f.terrain.site.inventory.get("wood", 0)) >= 4)
	assert(second.cargo.get("tools", 0) == 0 and f.terrain.site.inventory.tools == 1)
	f.close()
	completed_checks += 1

func _check_blocked_route_and_resume() -> void:
	var f := _fixture()
	var identity := f.ids()[0]
	var row: Dictionary = f.army.combat_units[1]
	assert(f.crew.assign(f.army, [identity], f.army.combat_identity(0)).ok)
	f.tick(300.0)
	assert(row.cargo == {"wood": 4})
	f.tick(1.0)
	assert(row.work_task.target == "depot" and f.army.moving_to[1] != TerrainArmy.INVALID_CELL)
	f.army.prepare_combat(0.5)
	# Boundary fixture: all original worker neighbors become an external
	# occupancy query. Neither terrain nor the person is moved to recover it.
	var blocked := {"enabled": true}
	var from := f.army.cells[1]
	f.crew.vehicle_blocked = func(cell: Vector2i) -> bool:
		return bool(blocked.enabled) and cell != from
	var before := JSON.stringify([f.terrain.site.inventory, row.cargo, f.army.cells, f.army.moving_to])
	f.tick(90.0)
	assert(f.army.cells[1] == from and f.army.moving_to[1] == TerrainArmy.INVALID_CELL)
	assert(JSON.stringify([f.terrain.site.inventory, row.cargo, f.army.cells, f.army.moving_to]) == before)
	assert(row.work_task.target == "depot" and "受阻" in str(row.work_task.status))
	blocked.enabled = false
	for step in range(30):
		f.tick(30.0)
		f.army.prepare_combat(0.5)
		if row.cargo.is_empty(): break
	assert(row.cargo.is_empty() and f.terrain.site.inventory.get("wood", 0) == 4)
	assert(f.army.cells[1] != from, "Unblocking must resume real steps and deliver, not discard cargo")
	f.close()
	completed_checks += 1

func _check_disabled_zone_and_replacement() -> void:
	var f := _fixture()
	var identity := f.ids()[0]
	var row: Dictionary = f.army.combat_units[1]
	assert(f.crew.assign(f.army, [identity], f.army.combat_identity(0)).ok)
	f.tick(60.0)
	assert(row.work_task.target == "crew_a" and row.work_task.progress == 1.0)
	f.terrain.site.zones[0].active = false
	var before := int(SiteEnvironment.resource(f.terrain, "crew_a").remaining)
	f.tick(600.0)
	assert(row.work_task.target == "" and row.cargo.is_empty())
	assert(int(SiteEnvironment.resource(f.terrain, "crew_a").remaining) == before)
	assert(SiteRuntime.add_zone(f.terrain, Rect2i(12, 15, 1, 1), SiteEnvironment.Kind.TIMBER).ok)
	for step in range(40):
		f.tick(30.0)
		f.army.prepare_combat(0.5)
		if int(f.terrain.site.inventory.get("wood", 0)) > 0: break
	assert(int(f.terrain.site.inventory.get("wood", 0)) == 4 and row.cargo.is_empty())
	assert(int(SiteEnvironment.resource(f.terrain, "crew_a").remaining) == before)
	assert(int(SiteEnvironment.resource(f.terrain, "crew_b").remaining) == 0)
	f.close()
	completed_checks += 1
