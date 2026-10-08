extends SceneTree

const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
const Coordinator = preload("res://scripts/terrain_lab/site_combat_movement_coordinator.gd")
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const OUTPUT := "res://output/team_formation_switch_impl_20260926/ko_hold_roundtrip.json"

func _initialize() -> void:
	call_deferred("_run")

func _require(ok: bool, message: String) -> bool:
	if not ok:
		push_error(message)
		quit(1)
	return ok

func _run() -> void:
	var terrain := TerrainGenerator.generate(TerrainPreset.Kind.PLAINS, 581)
	SiteEnvironment.initialize(terrain, "formation-ko-store-fixture")
	for index in range(terrain.height_levels.size()):
		terrain.height_levels[index] = 0
		terrain.flags[index] = TerrainData.Flag.WALKABLE
		terrain.static_blocked[index] = 0
	terrain.ramp_edges.fill(0)
	var army := Helper.create_test_army(terrain, 1, 0, 4, Vector2i(2, 8))
	var coordinator := Coordinator.new()
	coordinator.register_formation(army)
	if not _require(bool(army.issue_combat_order(army.current_commander, TerrainArmy.CombatOrder.MOVE, Vector2i(12, 8), -1, Vector2i.RIGHT, "square").get("ok", false)), "KO fixture MOVE was refused"): return
	var fallen := 3
	army.combat_units[fallen].ko = 10.0
	army.combat_units[fallen].pose = "unconscious"
	army.combat_units[fallen].present = false
	var saw_absence := false
	var completed := false
	for tick in range(1200):
		coordinator.combat_logic_tick(0.05)
		army.prepare_combat(0.05)
		coordinator.complete_committed_moves()
		saw_absence = saw_absence or not army._combat_absent_slots.is_empty()
		if army.combat_order == TerrainArmy.CombatOrder.HOLD:
			completed = army.command_status.begins_with("已抵達")
			break
	if not _require(saw_absence and completed, "Temporary KO was not observed and the remaining formation did not arrive"): return
	var plan: CombatDeploymentPlan = army.get_active_deployment_plan()
	if not _require(plan != null and army.get_active_move_plan() == null and army._combat_absent_slots.is_empty()
		and plan.slot_lease_timers.is_empty() and plan.slot_lease_owner_map.is_empty() and plan.slot_lease_role_map.is_empty()
		and plan.slot_lease_queue_index_map.is_empty(), "Completed HOLD retained a temporary absence lease"): return
	terrain.site.armies = [army.capture_combat_state()]
	if not _require(bool(Store.save(terrain, OUTPUT).get("ok", false)), "SiteStore rejected a HOLD immediately after temporary KO"): return
	var loaded: Dictionary = Store.load_site(OUTPUT)
	if not _require(bool(loaded.get("ok", false)), "SiteStore could not reload the completed KO formation: " + str(loaded)): return
	var restored := TerrainArmy.new()
	var restored_coordinator := Coordinator.new()
	restored_coordinator.register_formation(restored)
	restored.restore_combat_state(loaded.data.site.armies[0], loaded.data, null, null)
	if not _require(restored.combat_order == TerrainArmy.CombatOrder.HOLD and restored.get_active_move_plan() == null
		and restored.get_active_deployment_plan() != null and restored.formation_preset_id == "square"
		and restored._combat_absent_slots.is_empty(), "KO HOLD round-trip lost the selected formation or resumed stale absence"): return
	print("COMBAT FORMATION KO HOLD STORE PASS")
	restored_coordinator.unregister_formation(restored)
	restored.free()
	coordinator.unregister_formation(army)
	army.free()
	quit(0)
