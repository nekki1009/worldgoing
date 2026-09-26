extends SceneTree

const OUTPUT := "res://output/site_army_5k_hot_close_20260926/hot_prepare_smoke.json"

func _initialize() -> void:
	_run.call_deferred()

func _army(hot: bool) -> TerrainArmy:
	var army := TerrainArmy.new()
	army.native_hot_enabled = hot
	army.combat_hot_diagnostics_enabled = hot
	army.combat_enabled = true
	army.exchange_enabled = true
	army.combat_order = TerrainArmy.CombatOrder.ATTACK
	var rows: Array[Dictionary] = []
	for index in range(8):
		rows.append({"person_id": 100 + index, "hp": 100.0, "ko": 0.0,
			"age": 0.0, "think": 5.0, "stun": 0.0, "grace": 0.0,
			"pose": "idle", "attack": false, "member": true,
			"captive": false, "departed": false, "present": true})
		army.moving_to.append(TerrainArmy.INVALID_CELL)
	army.combat_units.assign(rows)
	army.move_progress = PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	army.move_duration = PackedFloat64Array([0.38, 0.38, 0.38, 0.38, 0.38, 0.38, 0.38, 0.38])
	if hot:
		assert(army._try_install_combat_hot_store())
	return army

func _run() -> void:
	var legacy := _army(false)
	var hot := _army(true)
	for step in range(4):
		legacy.prepare_combat(1.0 / 30.0)
		hot.prepare_combat(1.0 / 30.0)
		if legacy.materialized_combat_rows() != hot.materialized_combat_rows():
			push_error("active prepare differs at step %d" % step)
			quit(1)
			return
	var stats: Dictionary = hot.combat_hot_stats()
	if int(stats.native_calls) != 4 or int(stats.native_rows) != 32 or int(stats.fallback_rows) != 0:
		push_error("active prepare did not use native whole rows: " + str(stats))
		quit(1)
		return
	for team: TerrainArmy in [legacy, hot]:
		team.combat_order = TerrainArmy.CombatOrder.HOLD
		team.combat_hot_set(1, &"think", 0.01)
		team.combat_hot_set(2, &"ko", 3.0)
		team.combat_hot_set(2, &"pose", "unconscious")
		team.combat_hot_set(3, &"hp", 0.0)
		team.combat_hot_set(4, &"pose", "guard")
		team.combat_hot_set(5, &"pose", "get_up")
		team.combat_hot_set(6, &"ko", 3.0)
		team.combat_hot_set(6, &"pose", "down")
		team.combat_hot_set(6, &"age", 2.9)
	hot.combat_hot_reset_stats()
	for step in range(2):
		legacy.prepare_combat(1.0 / 30.0)
		hot.prepare_combat(1.0 / 30.0)
		var legacy_rows := legacy.materialized_combat_rows()
		var hot_rows := hot.materialized_combat_rows()
		if legacy_rows != hot_rows:
			for index in range(legacy_rows.size()):
				if legacy_rows[index] != hot_rows[index]:
					print("HOLD_DIFFERENCE index=", index, " legacy=", legacy_rows[index], " hot=", hot_rows[index])
			push_error("active HOLD prepare differs at step %d stats=%s" % [step, hot.combat_hot_stats()])
			quit(1)
			return
	var hold_stats: Dictionary = hot.combat_hot_stats()
	if int(hold_stats.native_calls) < 2 or int(hold_stats.native_rows) <= 0 or int(hold_stats.fallback_rows) <= 0:
		push_error("active HOLD missed safe native prefix or real barriers: " + str(hold_stats))
		quit(1)
		return
	var visual_legacy := _army(false)
	var visual_hot := _army(true)
	var delta := 1.0 / 30.0
	var visual := {"pose": "hit", "age": 0.2, "left": 0.8, "facing": Vector2i.DOWN}
	visual_legacy.combat_hot_set(0, &"exchange_visual", visual.duplicate(true))
	visual_hot.combat_hot_set(0, &"exchange_visual", visual.duplicate(true))
	visual_hot.combat_hot_reset_stats()
	visual_legacy.prepare_combat(delta)
	visual_hot.prepare_combat(delta)
	var pure_stats: Dictionary = visual_hot.combat_hot_stats()
	if visual_legacy.materialized_combat_rows() != visual_hot.materialized_combat_rows() \
			or int(pure_stats.native_rows) != 8 or not (pure_stats.barriers as Dictionary).is_empty() or int(pure_stats.fallback_rows) != 0:
		push_error("pure visual exact/native classification differs: " + str(pure_stats))
		quit(1)
		return
	visual.left = delta * 0.5
	visual_legacy.combat_hot_set(0, &"exchange_visual", visual.duplicate(true))
	visual_hot.combat_hot_set(0, &"exchange_visual", visual.duplicate(true))
	visual_hot.combat_hot_reset_stats()
	visual_legacy.prepare_combat(delta)
	visual_hot.prepare_combat(delta)
	var expiry_stats: Dictionary = visual_hot.combat_hot_stats()
	if visual_legacy.materialized_combat_rows() != visual_hot.materialized_combat_rows() \
			or (expiry_stats.barriers as Dictionary).is_empty() or int(expiry_stats.fallback_rows) <= 0:
		push_error("visual expiry ordered owner parity differs: " + str(expiry_stats))
		quit(1)
		return
	for sample: Dictionary in [stats, hold_stats, pure_stats, expiry_stats]:
		var reason_total := 0
		for count: int in (sample.owner_reasons as Dictionary).values(): reason_total += count
		if reason_total != int((sample.barriers as Dictionary).get(3, 0)):
			push_error("HOT_OWNER reason sum differs from barriers: " + str(sample))
			quit(1)
			return
	if int((expiry_stats.owner_reasons as Dictionary).get("visual_expiry", 0)) != 1:
		push_error("Expected one real visual expiry reason: " + str(expiry_stats))
		quit(1)
		return
	var attack_legacy := _army(false)
	var attack_hot := _army(true)
	for team: TerrainArmy in [attack_legacy, attack_hot]:
		team.combat_hot_set(0, &"pose", "attack_unarmed")
		team.combat_hot_set(0, &"attack", true)
		team.combat_hot_set(0, &"exchange_pose_duration", 1.0)
		team.combat_hot_set(0, &"exchange_visual", {"pose": "attack_unarmed", "age": 0.2, "left": 0.8, "facing": Vector2i.DOWN})
		team.combat_hot_set(1, &"pose", "hit")
		team.combat_hot_set(1, &"think", 0.0)
	attack_hot.combat_hot_reset_stats()
	for step in range(2):
		attack_legacy.prepare_combat(delta)
		attack_hot.prepare_combat(delta)
		if attack_legacy.materialized_combat_rows() != attack_hot.materialized_combat_rows():
			push_error("Attack/think native two-step exactness differs at step %d" % step)
			quit(1)
			return
	var attack_stats: Dictionary = attack_hot.combat_hot_stats()
	if int(attack_stats.native_calls) != 2 or int(attack_stats.native_rows) != 16 \
			or not (attack_stats.barriers as Dictionary).is_empty() or int(attack_stats.fallback_rows) != 0:
		push_error("Attack/think pure clocks fell back per row: " + str(attack_stats))
		quit(1)
		return
	for team: TerrainArmy in [attack_legacy, attack_hot]: team.combat_hot_set(0, &"age", 1.0 - delta * 0.5)
	attack_hot.combat_hot_reset_stats()
	attack_legacy.prepare_combat(delta)
	attack_hot.prepare_combat(delta)
	var attack_expiry_stats: Dictionary = attack_hot.combat_hot_stats()
	if attack_legacy.materialized_combat_rows() != attack_hot.materialized_combat_rows() \
			or int((attack_expiry_stats.owner_reasons as Dictionary).get("pose_expiry", 0)) != 1 \
			or int(attack_expiry_stats.fallback_rows) != 1:
		push_error("Attack pose expiry lost ordered owner parity: " + str(attack_expiry_stats))
		quit(1)
		return
	for sample: Dictionary in [attack_stats, attack_expiry_stats]:
		var reason_total := 0
		for count: int in (sample.owner_reasons as Dictionary).values(): reason_total += count
		if reason_total != int((sample.barriers as Dictionary).get(3, 0)):
			push_error("Attack HOT_OWNER reason sum differs: " + str(sample))
			quit(1)
			return
	var output := FileAccess.open(OUTPUT, FileAccess.WRITE)
	assert(output != null)
	output.store_string(JSON.stringify({"checks": {"four_step_exact_rows": true,
		"native_no_barrier_whole_roster": true, "hold_safe_prefix_and_barrier_exact": true,
		"pure_visual_no_owner_barrier": true, "visual_expiry_ordered_barrier_exact": true,
		"owner_reason_totals_exact": true, "attack_think_two_step_exact_native": true,
		"attack_pose_expiry_exact": true},
		"stats": stats, "hold_stats": hold_stats, "pure_visual_stats": pure_stats, "visual_expiry_stats": expiry_stats,
		"attack_think_stats": attack_stats, "attack_expiry_stats": attack_expiry_stats,
		"army_sha256": FileAccess.get_sha256("res://scripts/terrain_lab/terrain_army.gd"),
		"cpp_sha256": FileAccess.get_sha256("res://native/army_idle/army_idle.cpp"),
		"dll_sha256": FileAccess.get_sha256("res://native/army_idle/bin/army_idle.windows.x86_64.dll"),
		"test_sha256": FileAccess.get_sha256("res://scripts/tests/site_army_hot_prepare_test.gd")}))
	output.close()
	legacy.free()
	hot.free()
	visual_legacy.free()
	visual_hot.free()
	attack_legacy.free()
	attack_hot.free()
	print("ARMY_COMBAT_HOT_PREPARE_PASS")
	quit(0)
