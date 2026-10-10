extends "res://scripts/tests/site_workflow_test.gd"
## True original Actor join / depot carrying / original Army mesh contact.
## Starting stationary legal geometry is explicit, not a navigation claim.
const Fatigue = preload("res://scripts/terrain_lab/person_fatigue.gd")

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 180000
	_run.call_deferred()

func _run() -> void:
	var lab := TerrainLab.new()
	lab.exchange_enabled = false
	lab.pause_when_unfocused = false
	root.add_child(lab)
	for owner: Node in [lab, lab.character, lab.npc, lab.site_controller, lab.army, lab.opposing_army]: owner.set_process(false)
	lab.site_controller._auto_save_blocked = true
	var data: TerrainData = _fixture()
	lab.bind_terrain(data)
	lab.site_controller.release_worker()
	lab.npc.faction_id = lab.character.faction_id
	lab.npc.issue_command(TerrainTestNPC.Command.STOP)
	assert(lab.character.place(Vector2i(21, 22), true) and lab.npc.place(Vector2i(35, 35), true))
	var team: TerrainArmy = lab.army
	team.roster_size = 4
	var cells: Array[Vector2i] = [Vector2i(25, 25), Vector2i(26, 25), Vector2i(25, 26), Vector2i(26, 26)]
	assert(team.deploy_at(data, lab.character, lab.npc, cells) and team.enable_combat(false))
	team.faction_id = lab.character.faction_id
	team.settle_combat_command()
	lab.site_controller.initialize_team_items(team)
	assert(team.join_player(lab.character).ok, "Original membership/supply/appearance owner admits the real Actor; no captain/logistics/consent fields written")
	assert(is_same(team.player_member, lab.character) and is_same(Fatigue.pool(lab.character), team.team_fatigue))
	var enemy: TerrainArmy = lab.opposing_army
	enemy.roster_size = 4
	var enemy_cells: Array[Vector2i] = [Vector2i(22, 22), Vector2i(23, 22), Vector2i(22, 23), Vector2i(23, 23)]
	assert(enemy.deploy_at(data, lab.character, lab.npc, enemy_cells) and enemy.enable_combat(false))
	enemy.faction_id = team.faction_id + 1
	enemy.settle_combat_command()
	data.site.army_next_team = maxi(team.team_id, enemy.team_id) + 1
	data.site.depot_cell = data.index(Vector2i(20, 22))
	data.site.inventory.grain = 4 # Explicit finite initial source; no authored product or elapsed work.
	var controller: SiteController = lab.site_controller
	var begun: Dictionary = controller.begin_team_food(team, 4, lab.character.person_id, {"kind": "depot"})
	assert(begun.ok, str(begun))
	var entry: Dictionary = controller._supply_entry(team)
	var job: Dictionary = entry.delivery
	assert(job.player_id == lab.character.person_id and job.representative_id == lab.character.person_id and controller._delivery_people(entry).size() == 1)
	var source_grain: int = int(data.site.inventory.grain)
	var attacker := -1
	for index: int in enemy.combat_units.size():
		if enemy.combat_can_act(index) and enemy.ranged_profile(index).is_empty() and enemy.cells[index] == Vector2i(22, 22): attacker = index; break
	assert(attacker >= 0 and enemy.contact_sink.is_valid(), "Original stationary melee body and original bound mesh sink exist")
	var packets: Array[Dictionary] = []
	var original_sink: Callable = enemy.contact_sink
	enemy.contact_sink = func(packet: Dictionary) -> void:
		if is_same(packet.get("target"), lab.character): packets.append({"fraction": float(packet.fraction), "hp": float(packet.result.hp), "stun": float(packet.result.stun)})
		original_sink.call(packet) # EXACT original geometry/material packet, observation only.
	var contact := {}
	var before_hits: int = int(lab.character._received_effective_hit)
	for tick: int in 1800:
		assert(Time.get_ticks_msec() <= deadline)
		if not bool(enemy.combat_hot_get(attacker, &"attack")) and enemy.combat_can_act(attacker):
			assert(enemy.start_unit_attack(attacker, lab.character.terrain_cell, lab.character.person_id))
		var count: int = packets.size()
		var fatigue: float = Fatigue.read(lab.character)
		var rate: float = Fatigue.effort_rate(lab.character)
		var left: float = float(job.left)
		var step: Dictionary = lab._advance_original_shared_step(TerrainLab.ACTION_STEP)
		assert(step.ok and step.get("completed", false) and lab._region_point_pending.is_empty(), str(step))
		if packets.size() > count and int(lab.character._received_effective_hit) > before_hits:
			contact = {"packet": packets.back(), "fatigue": fatigue, "rate": rate, "game_seconds": float(step.game_seconds), "left_before": left, "left_after": float(job.left)}
			break
		assert(not entry.delivery.is_empty(), "Actual contact must precede the finite real 2.8-second delivery endpoint; no handpicked work prefix")
	enemy.contact_sink = original_sink
	assert(not contact.is_empty() and float(contact.packet.fraction) > 0.0 and float(contact.packet.fraction) < 1.0, "Actual original mesh hit occurs strictly inside the original work interval")
	var prefix: float = float(contact.game_seconds) * float(contact.packet.fraction)
	var effective: float = Fatigue.work_seconds(float(contact.fatigue), prefix, float(contact.rate))
	assert(float(contact.left_before) - float(contact.left_after) > 0.0 and float(contact.left_before) - float(contact.left_after) <= effective + 0.00000001, "No delivery work after its real source-person hit")
	assert(entry.delivery.is_empty() and int(data.site.inventory.grain) == source_grain, "Current true contact endpoint cancels without food debit, but preserves the legal positive prefix")
	assert(Fatigue.read(lab.character) <= float(contact.fatigue) + float(contact.rate) * prefix + 0.00000001, "Original shared formation WORK stops at the same actual fraction, no post-contact duplicate fatigue")
	assert(controller.original_step_fault_guard().ok and lab._shared_work_plan.is_empty())
	controller.work_team.discard_prepared_interval()
	lab.free()
	TerrainArmy.release_contact_source()
	print("GD_CONTACT_DELIVERY_MESH_PASS scope=true_joined_actor_depot_real_mesh_midframe_prefix_current_endpoint_zerofood_only native_world_birth_not_claimed")
	quit(0)
