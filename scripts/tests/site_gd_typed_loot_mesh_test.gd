extends "res://scripts/tests/site_gd_typed_loot_point_test.gd"
## Original remote melee mesh + unaffected real ground-food executor.
## No sampler replay, generated contact, manual prefix or timer/body write.

func _run() -> void:
	var f: Dictionary = _opened_fixture(20.0)
	var lab: TerrainLab = f.lab
	var actions: SitePersonActions = f.actions
	var data: TerrainData = f.data
	var receiver: Dictionary = actions._person(int(lab.character.person_id))
	assert(lab.npc.place(Vector2i(45, 45), true)) # Explicit original starting geometry, not a movement-route test.
	var victim_id: int = int(lab.npc.person_id)
	var enemy: TerrainArmy = lab.opposing_army
	enemy.roster_size = 4
	var positions: Array[Vector2i] = [Vector2i(44, 45), Vector2i(40, 30), Vector2i(42, 30), Vector2i(44, 30)]
	assert(enemy.deploy_at(data, lab.character, lab.npc, positions) and enemy.enable_combat(false))
	enemy.faction_id = 2
	enemy.settle_combat_command()
	var attacker: int = -1
	for index: int in enemy.combat_units.size():
		if enemy.cells[index] == positions[0] and enemy.ranged_profile(index).is_empty() and enemy.combat_can_act(index): attacker = index; break
	assert(attacker >= 0 and enemy.contact_sink.is_valid())
	var packets: Array[Dictionary] = []
	var original_sink: Callable = enemy.contact_sink
	enemy.contact_sink = func(packet: Dictionary) -> void:
		packets.append({"fraction": float(packet.fraction), "target": packet.get("target"), "hp": float(packet.result.hp), "stun": float(packet.result.stun)})
		original_sink.call(packet) # SAME original mesh packet and original life owner.
	assert(enemy.start_unit_attack(attacker, lab.npc.terrain_cell, victim_id))
	var events: Dictionary = TerrainArmy.CombatTimings.events(enemy.attack_clip(attacker))
	while TerrainArmy.CombatTimings.sample_time(enemy.attack_clip(attacker), float(enemy.combat_hot_get(attacker, &"age")),
		float(enemy.combat_units[attacker].attack_reduction), float(enemy.combat_units[attacker].attack_fatigue)) < float(events.active_start) - 2.0 * TerrainLab.ACTION_STEP:
		_step_typed(lab) # The actual original point advances the windup; no timing-field write.
	var amount: float = minf(20.0, float(Runtime.CARRY_CAPACITY) - float(Runtime.carried_load(data.site, receiver.cargo, receiver.holder)))
	assert(amount >= 10.0, "Original receiver's finite carrying capacity allows a genuine multi-point loot timer")
	var begun: Dictionary = actions.begin_loot(int(receiver.person_id), "ground", f.source_id, {}, [], amount)
	assert(begun.ok and is_equal_approx(float(begun.seconds), 2.0 + amount * 0.2), str(begun))
	var job: Dictionary = actions._jobs[str(int(receiver.person_id))]
	var hit_before: int = int(lab.npc._received_effective_hit)
	var observed: Dictionary = {}
	while actions.is_busy(int(receiver.person_id)):
		var count: int = packets.size()
		var before: float = float(job.elapsed)
		var fatigue: float = Fatigue.read(receiver.body)
		var rate: float = Fatigue.effort_rate(receiver.body)
		var point: Dictionary = _step_typed(lab)
		if packets.size() > count and int(lab.npc._received_effective_hit) > hit_before and actions.is_busy(int(receiver.person_id)):
			observed = {"packets": packets.slice(count), "game_seconds": float(point.game_seconds), "before": before,
				"after": float(job.elapsed), "fatigue": fatigue, "rate": rate}
			break
	enemy.contact_sink = original_sink
	assert(not observed.is_empty(), "Genuine mesh contact occurs during the actual, still-uncompleted ground-food timer")
	var interior: bool = false
	for packet: Dictionary in observed.packets:
		interior = interior or is_same(packet.target, lab.npc) and float(packet.fraction) > 0.0 and float(packet.fraction) < 1.0 and (float(packet.hp) > 0.0 or float(packet.stun) > 0.0)
	assert(interior, "Strict interior fraction comes only from original melee sweep geometry")
	var effective: float = Fatigue.work_seconds(float(observed.fatigue), float(observed.game_seconds), float(observed.rate))
	assert(absf(float(observed.after) - float(observed.before) - effective) < 0.00000001,
		"Unaffected original executor receives the exact one point integral across actual disjoint contact segments")
	while actions.is_busy(int(receiver.person_id)): _step_typed(lab)
	var received: Dictionary = f.ctl._personal_opened_food(int(receiver.person_id))
	assert(is_equal_approx(float(received.open_rations), amount))
	assert(not data.site.ground_loot.has(f.source_id) if amount == 20.0 else is_equal_approx(float(f.source.open_rations), 20.0 - amount))
	assert(lab._region_point_pending.is_empty() and lab._shared_work_plan.is_empty() and f.ctl.original_step_fault_guard().ok)
	_close_typed(lab)
	TerrainArmy.release_contact_source()
	print("GD_TYPED_LOOT_MESH_PASS scope=original_unaffected_executor_remote_melee_true_fraction_food_tail_once no_native_world_claim")
	quit(0)
