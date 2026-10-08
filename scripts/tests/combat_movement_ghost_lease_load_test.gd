extends SceneTree

const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
const Coordinator = preload("res://scripts/terrain_lab/site_combat_movement_coordinator.gd")
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const SAVE := "res://.godot-temp/site_combat/ghost-lease-base.json"
const CORRUPT := "res://.godot-temp/site_combat/ghost-lease-corrupt.json"

func _initialize() -> void:
	call_deferred("_run")

func _require(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error(message)
	quit(1)
	return false

func _run() -> void:
	var data := TerrainGenerator.generate(TerrainPreset.Kind.PLAINS, 581)
	SiteEnvironment.initialize(data, "ghost-lease-fixture")
	for index in range(data.height_levels.size()):
		data.height_levels[index] = 0
		data.site.terrain_changes[str(index)] = 0
	SiteRuntime.rebuild_terrain_edges(data)
	var origin := TerrainArmy.INVALID_CELL
	for y in range(2, data.size.y - 8):
		for x in range(2, data.size.x - 15):
			var legal := true
			for dy in range(7):
				for dx in range(14):
					if not data.is_walkable(Vector2i(x + dx, y + dy)):
						legal = false
						break
				if not legal: break
			if legal:
				origin = Vector2i(x + 1, y + 3)
				break
		if origin != TerrainArmy.INVALID_CELL:
			break
	if not _require(origin != TerrainArmy.INVALID_CELL, "No legal test room"): return
	var army := Helper.create_test_army(data, 1, 0, 2, origin)
	var coordinator := Coordinator.new()
	coordinator.register_formation(army)
	if not _require(bool(army.issue_combat_order(army.current_commander, TerrainArmy.CombatOrder.MOVE, origin + Vector2i(10, 0)).get("ok", false)), "Fixture MOVE must be accepted"): return
	data.site["army_trial_active"] = true
	data.site["army_next_team"] = 2
	data.site["actors"] = {}
	data.site["armies"] = [army.capture_combat_state()]
	data.site.combat_left = 0.0
	if not _require(bool(Store.save(data, SAVE).get("ok", false)), "Valid fixture must save"): return
	var saved_text := FileAccess.get_file_as_string(SAVE)
	var baseline: Dictionary = Store.load_site(SAVE)
	if not _require(bool(baseline.get("ok", false)), "Valid fixture must load"): return
	var active_data: TerrainData = baseline.data
	var active_site: Dictionary = active_data.site.duplicate(true)
	var envelope: Dictionary = JSON.parse_string(saved_text)
	var payload: Dictionary = JSON.parse_string(envelope.payload)
	var deployment: Dictionary = payload.state.armies[0].combat_deployment_plan
	var final_cells: Dictionary = {}
	for pair: Array in deployment.platform_slots + deployment.approach_queue_slots:
		final_cells[Vector2i(int(pair[0]), int(pair[1]))] = true
	var ghost := TerrainArmy.INVALID_CELL
	for y in range(data.size.y):
		for x in range(data.size.x):
			var candidate := Vector2i(x, y)
			if data.is_walkable(candidate) and not final_cells.has(candidate):
				ghost = candidate
				break
		if ghost != TerrainArmy.INVALID_CELL:
			break
	if not _require(ghost != TerrainArmy.INVALID_CELL, "No walkable ghost cell outside the final deployment"): return
	var ghost_key := "%d,%d" % [ghost.x, ghost.y]
	var existing_mid := int(payload.state.armies[0].units[0].person_id)
	deployment.slot_lease_timers[ghost_key] = 4.0
	deployment.slot_lease_owner_map[ghost_key] = existing_mid
	deployment.slot_lease_role_map[ghost_key] = 0
	var corrupt_body := JSON.stringify(payload, "", true, true)
	var corrupt_text := JSON.stringify({"checksum": corrupt_body.sha256_text(), "payload": corrupt_body}, "\t")
	var file := FileAccess.open(CORRUPT, FileAccess.WRITE)
	if not _require(file != null, "Cannot write corrupt fixture"): return
	file.store_string(corrupt_text)
	file.close()
	var rejected: Dictionary = Store.load_site(CORRUPT)
	if not _require(not bool(rejected.get("ok", false)) and str(rejected.get("code", "")) == "CORRUPT_SAVE" and not rejected.has("data"), "A checksummed ghost lease must be rejected during real load: " + str(rejected)): return
	if not _require(active_data.site == active_site and FileAccess.get_file_as_string(SAVE) == saved_text, "Rejected load must preserve active terrain and valid save"): return
	army.combat_units[1].ko = 2.0
	army.combat_units[1].pose = "down"
	army.update_combat_deployment(0.05)
	var absent: Dictionary = JSON.parse_string(JSON.stringify(army.capture_combat_state()))
	if not _require(Store._valid_combat_movement_snapshot(data, absent, {}), "A real KO lease must remain valid"): return
	if not _require(absent.combat_deployment_plan.slot_lease_timers.size() == 1, "KO fixture must contain one temporary lease"): return
	var lease_key: String = absent.combat_deployment_plan.slot_lease_timers.keys()[0]
	var wrong_owner: Dictionary = absent.duplicate(true)
	wrong_owner.combat_deployment_plan.slot_lease_owner_map[lease_key] = int(wrong_owner.units[0].person_id)
	if not _require(not Store._valid_combat_movement_snapshot(data, wrong_owner, {}), "A lease owner must match the absent member for that slot"): return
	var wrong_role: Dictionary = absent.duplicate(true)
	wrong_role.combat_deployment_plan.slot_lease_role_map[lease_key] = 1 - int(wrong_role.combat_deployment_plan.slot_lease_role_map[lease_key])
	if not _require(not Store._valid_combat_movement_snapshot(data, wrong_role, {}), "A lease role must match its platform or queue slot"): return
	print("COMBAT MOVEMENT GHOST LEASE LOAD PASS")
	coordinator.unregister_formation(army)
	army.free()
	quit(0)
