extends "res://scripts/tests/site_workflow_test.gd"
## True original Actor join / depot carrying / original Army mesh contact.
## Starting stationary legal geometry is explicit, not a navigation claim.
const Fatigue = preload("res://scripts/terrain_lab/person_fatigue.gd")

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 180000
	_run.call_deferred()

func _check_supply_reader(controller: SiteController, team: TerrainArmy, actor: TerrainTestCharacter) -> Callable:
	var members: Dictionary = controller._team_members(team)
	var reader: Callable = controller._gd_mesh_supply_reader(members)
	var person: Dictionary = controller._supply_person(actor.person_id)
	var body_ko: Variant = controller.person_actions._body_get(person, "ko")
	var reader_ko: Variant = reader.call(actor.person_id, &"ko")
	assert(is_same(person.body, actor) and int(person.unit) < 0 and body_ko == null)
	assert(person.ko is float and reader_ko is float and reader_ko == actor.knockout_left)
	var sampled: Dictionary = controller._gd_mesh_supply_life(members, reader)
	assert(sampled.ok and sampled.life[actor.person_id].hp is float and sampled.life[actor.person_id].captive is bool)
	var projection: Dictionary = {actor.person_id: {"present": false}}
	var presence_reader: Callable = controller._gd_mesh_supply_reader(projection)
	var absent: Variant = presence_reader.call(actor.person_id, &"present")
	projection[actor.person_id].present = true
	var present: Variant = presence_reader.call(actor.person_id, &"present")
	assert(absent is bool and not absent and present is bool and present)
	var invalid: Array[Dictionary] = [{actor.person_id: null}]
	for field: String in ["hp", "ko"]:
		for value: Variant in [null, &"100", {}, "100", true, false, NAN, INF, -1.0]:
			var member: Dictionary = {"hp": 100.0, "ko": 0.0, "captive": false}
			member[field] = value
			invalid.append({actor.person_id: member})
	for value: Variant in [null, &"false", {}, "false", 0, 0.0]:
		invalid.append({actor.person_id: {"hp": 100.0, "ko": 0.0, "captive": value}})
	for sample: Dictionary in invalid:
		var before: PackedByteArray = var_to_bytes(sample)
		var rejected: Dictionary = controller._gd_mesh_supply_life(sample, Callable())
		assert(not rejected.ok and rejected.code == "INVALID_SUSTAIN" and var_to_bytes(sample) == before)
	var valid: Dictionary = {actor.person_id: {"hp": 100, "ko": 0.0, "captive": false}}
	var accepted: Dictionary = controller._gd_mesh_supply_life(valid, Callable())
	assert(accepted.ok and accepted.life[actor.person_id].hp == 100.0 and accepted.life[actor.person_id].ko == 0.0 and accepted.life[actor.person_id].captive == false)
	return reader

func _run() -> void:
	var lab: TerrainLab = TerrainLab.new()
	lab.npc = TerrainTestNPC.new() # Explicit original presenter; formal Lab has no default NPC.
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
	var player_placed: bool = lab.character.place(Vector2i(21, 22), true)
	var npc_placed: bool = lab.npc.place(Vector2i(35, 35), true) if player_placed else false
	assert(player_placed and npc_placed)
	# Headless Lab skips the presenter by design (_initialize_visual_resources returns early), which leaves the real Actor with no body mesh.
	# Explicitly prepare the same original presenter on this live Actor (CPU contact path), then pose it idle as the other contact tests do.
	var actor_appearance: Dictionary = HumanCharacter3DEditor.default_appearance(0)
	actor_appearance.parts.shield = "none" # Spec-free fixture choice: default parts include shield_heater_01 (human_character_3d_editor.gd:107); precedent terrain_lab.gd:4885.
	var body_prepared: bool = lab.character.prepare_contact_visual(actor_appearance)
	assert(body_prepared and lab.character.editor != null and lab.character.editor.model_root != null, "Real Actor body mesh exists before the contact loop")
	lab.character.play_pose(&"idle")
	var team: TerrainArmy = lab.army
	team.exchange_enabled = true # Receiver uses the original shared pool; Lab/enemy keep real GD mesh contact.
	team.roster_size = 4
	var cells: Array[Vector2i] = [Vector2i(25, 25), Vector2i(26, 25), Vector2i(25, 26), Vector2i(26, 26)]
	var team_deployed: bool = team.deploy_at(data, lab.character, lab.npc, cells)
	var team_enabled: bool = team.enable_combat(false) if team_deployed else false
	assert(team_deployed and team_enabled)
	team.faction_id = lab.character.faction_id
	team.settle_combat_command()
	lab.site_controller.initialize_team_items(team)
	var joined: Dictionary = team.join_player(lab.character)
	assert(joined.ok, "Original membership/supply/appearance owner admits the real Actor; no captain/logistics/consent fields written")
	assert(is_same(team.player_member, lab.character) and is_same(Fatigue.pool(lab.character), team.team_fatigue))
	var enemy: TerrainArmy = lab.opposing_army
	enemy.roster_size = 4
	var enemy_cells: Array[Vector2i] = [Vector2i(22, 22), Vector2i(23, 22), Vector2i(22, 23), Vector2i(23, 23)]
	var enemy_deployed: bool = enemy.deploy_at(data, lab.character, lab.npc, enemy_cells)
	var enemy_enabled: bool = enemy.enable_combat(false) if enemy_deployed else false
	assert(enemy_deployed and enemy_enabled)
	enemy.faction_id = team.faction_id + 1
	enemy.settle_combat_command()
	assert(not lab.exchange_enabled and not enemy.exchange_enabled and team.exchange_enabled)
	data.site.army_next_team = maxi(team.team_id, enemy.team_id) + 1
	data.site.depot_cell = data.index(Vector2i(20, 22))
	data.site.inventory.grain = 4 # Explicit finite initial source; no authored product or elapsed work.
	var controller: SiteController = lab.site_controller
	var supply_reader: Callable = _check_supply_reader(controller, team, lab.character)
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
			var attack_started: bool = enemy.start_unit_attack(attacker, lab.character.terrain_cell, lab.character.person_id)
			assert(attack_started)
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
	var live_hp: Variant = supply_reader.call(lab.character.person_id, &"hp")
	var live_ko: Variant = supply_reader.call(lab.character.person_id, &"ko")
	var live_captive: Variant = supply_reader.call(lab.character.person_id, &"captive")
	assert(live_hp is float and live_ko is float and live_captive is bool)
	assert(live_hp == lab.character.hp and live_ko == lab.character.knockout_left and live_captive == lab.character.captive)
	controller.work_team.discard_prepared_interval()
	lab.free()
	TerrainArmy.release_contact_source()
	print("GD_CONTACT_DELIVERY_MESH_PASS scope=true_joined_actor_depot_real_mesh_midframe_prefix_current_endpoint_zerofood_only native_world_birth_not_claimed")
	quit(0)
