extends SceneTree

const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
const Types = preload("res://scripts/terrain_lab/combat_movement_types.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var data := Helper.build_flat_map(20, 20)
	var army := Helper.create_test_army(data, 1, 0, 1, Vector2i(5, 5))
	var mid := army.combat_identity(0)
	var plan := CombatMovePlan.new()
	for y in range(16):
		plan.macro_path.append(Vector2i(5, y))
	plan.macro_cursor = 5
	plan.member_sequence_rank[mid] = 0
	plan.member_transit_slots[mid] = Vector2i(5, 5)
	plan.member_path_s[mid] = 5.0
	army._combat_move_plan = plan
	army.combat_order = TerrainArmy.CombatOrder.MOVE
	army.finalize_combat_movement_tick(0.1, null, null)
	if not _require(float(plan.member_observed_path_s.get(mid, -1.0)) == 5.0,
		"Initial physical cell must receive its path projection"): return
	# Planning changes while the soldier has not physically moved must not
	# promote its order in the formation.
	plan.member_transit_slots[mid] = Vector2i(6, 5)
	plan.member_path_s[mid] = 9.0
	var revised_route: Array[Vector2i] = [Vector2i(5, 5), Vector2i(6, 5)]
	plan.member_paths[mid] = revised_route
	plan.macro_cursor = 8
	army.finalize_combat_movement_tick(0.1, null, null)
	if not _require(float(plan.member_observed_path_s[mid]) == 5.0 and int(plan.member_observed_path_k[mid]) == 5,
		"Soft target, cached route, and cursor changes on the same cell must preserve observed progress"): return
	# Mirror Grid's atomic cell-owner commit; cells[] alone is not the authority.
	army._cell_owners.erase(Vector2i(5, 5))
	army.cells[0] = Vector2i(5, 6)
	army._cell_owners[Vector2i(5, 6)] = 0
	plan.member_paths.erase(mid)
	plan.member_transit_slots[mid] = Vector2i(5, 6)
	plan.member_path_s[mid] = 6.0
	army.finalize_combat_movement_tick(0.1, null, null)
	if not _require(float(plan.member_observed_path_s[mid]) == 6.0,
		"A completed legal physical cell change must update observed progress"): return
	plan.path_epoch += 1
	plan.member_path_s[mid] = 8.0
	army.finalize_combat_movement_tick(0.1, null, null)
	if not _require(float(plan.member_observed_path_s[mid]) == 8.0,
		"A new path epoch must reproject even on the same physical cell"): return
	plan.terrain_revision += 1
	plan.member_path_s[mid] = 10.0
	army.finalize_combat_movement_tick(0.1, null, null)
	if not _require(float(plan.member_observed_path_s[mid]) == 10.0,
		"A terrain revision must reproject even on the same physical cell"): return
	plan.phase = Types.CombatMovePhase.PLATFORM_INGRESS
	plan.member_path_s[mid] = 11.0
	army.finalize_combat_movement_tick(0.1, null, null)
	if not _require(float(plan.member_observed_path_s[mid]) == 11.0,
		"Platform ingress must reproject a changed target on the same physical cell"): return
	print("COMBAT MOVEMENT OBSERVED STATIC CELL PASS")
	army.free()
	quit(0)

func _require(ok: bool, message: String) -> bool:
	if ok:
		return true
	push_error(message)
	quit(1)
	return false
