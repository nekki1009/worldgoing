extends SceneTree

const OUTPUT := "res://.visual_captures/site_player_soldier"
var phase := "all"

class ContactLab extends TerrainLab:
	var player_packets: Array[Dictionary] = []
	func _resolve_combat_contacts() -> void:
		for packet: Dictionary in _combat_contacts:
			if packet.attacker == character:
				player_packets.append(packet.duplicate())
		super._resolve_combat_contacts()

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--phase="):
			phase = argument.trim_prefix("--phase=")
	assert(phase in ["all", "contact", "rescue"])
	call_deferred("run")

func run() -> void:
	create_timer(23.0).timeout.connect(func() -> void: quit(1))
	root.size = Vector2i(1400, 900)
	var lab := ContactLab.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	current_scene = lab
	for node: Node in [lab, lab.site_controller, lab.character, lab.npc, lab.army, lab.opposing_army]:
		node.set_process(false)
	var data := TerrainGenerator.generate(0, 581)
	SiteEnvironment.initialize(data, "player-soldier-visual")
	data.resource_base.clear()
	data.resources_at.clear()
	for index in range(data.size.x * data.size.y):
		data.height_levels[index] = 0
		data.flags[index] = TerrainData.Flag.WALKABLE
		data.static_blocked[index] = 0
	data.ramp_edges.fill(0)
	lab.bind_terrain(data)
	lab.character.place(Vector2i(50, 50), true)
	lab.npc.place(Vector2i(52, 50), true)
	assert(lab.start_melee_trial().ok)
	for team: TerrainArmy in lab.combat_armies:
		assert(team.issue_combat_order(team.current_commander, TerrainArmy.CombatOrder.HOLD).ok)
		team.enemy_query = Callable()
	lab.get_node("SiteUI").hide()
	lab.get_node("TerrainLabUI").hide()
	var player := lab.character
	var target := lab.opposing_army
	assert(player.place(target.cells[99] + Vector2i.RIGHT, true))
	assert(player.editor.select_part_by_id(&"weapon", &"longsword_01"))
	lab.camera.zoom = Vector2.ONE * 2.5
	lab.camera.position = player.position + Vector2(-50, -60)
	assert(lab.select_army_target(target.cells[99]))
	if phase != "rescue":
		assert(lab.attack_selected_soldier())
		for tick in range(180):
			lab._advance_combat(1.0 / 120.0)
		var first_hp := float(target.combat_units[99].hp)
		assert(player._attack_hits.has(target.combat_identity(99)) and lab.player_packets.size() == 1)
		var sword: Dictionary = lab.player_packets[0]
		assert(sword.target == target and int(sword.target_unit) == 99 and not bool(sword.ranged))
		assert(is_equal_approx(first_hp, 100.0 - float(sword.result.hp)), "Real shield/armor may legitimately reduce HP loss to zero")
		print("PLAYER SOLDIER SWORD CONTACT shield=", sword.shield, " result=", sword.result)
		assert(lab.npc.hp == 100.0)
		target.advance_frame(0.0)
		await capture("01_player_sword_contact.png")
		while player.action_time > 0.0:
			lab._advance_combat(1.0 / 120.0)
		assert(player.editor.select_part_by_id(&"weapon", &"bow_01"))
		player.ammo_inventory["arrow"] = 2
		assert(player.place(target.cells[99] + Vector2i(3, 0), true))
		# A deliberate same-faction shot exercises the player's permitted friendly fire.
		target.faction_id = player.faction_id
		assert(lab.attack_selected_soldier())
		# The authored bow releases at frame 116/24, after the 1.15 s reload.
		for tick in range(ceili((player.action_time + 1.0) * 120.0)):
			lab._advance_combat(1.0 / 120.0)
		assert(int(player.ammo_inventory.arrow) == 1 and lab.player_packets.size() == 2)
		var arrow: Dictionary = lab.player_packets[1]
		assert(arrow.target == target and int(arrow.target_unit) == 99 and bool(arrow.ranged))
		assert(is_equal_approx(float(target.combat_units[99].hp), first_hp - float(arrow.result.hp)))
		assert(lab.npc.hp == 100.0, "Release-time aiming cannot fall back to the old NPC opponent")
		print("PLAYER SOLDIER ACTUAL CONTACT sword_hp=", first_hp, " arrow_hp=", target.combat_units[99].hp)
		if phase == "contact":
			print("SITE PLAYER SOLDIER CONTACT VISUAL PASS: actual sword and friendly arrow contact, exact HP packets and one arrow consumed; no rescue scenario")
			await finish(lab)
			return
	assert(player.place(target.cells[99] + Vector2i.RIGHT, true))
	target.apply_unit_contact(99, {"result": {"hp": 0.0, "stun": 110.0, "guard_break": false}, "shield": false})
	if phase == "rescue":
		assert(not lab.rescue_selected_soldier(), "Enemy rescue must remain rejected")
	# The combined case established this in its friendly-arrow setup.
	target.faction_id = player.faction_id
	assert(lab.rescue_selected_soldier())
	assert(target.set_unit_guard(98, true))
	for tick in range(150):
		lab._advance_combat(1.0 / 120.0)
	target.advance_frame(0.0)
	assert(player.visual_state.animation_id == &"rescue" and target.combat_units[99].ko > 0.0)
	assert(target.combat_frame(98).clip == "guard")
	lab.camera.position = player.position + Vector2(-50, -60)
	await capture("02_player_rescue_and_soldier_guard.png")
	for tick in range(331):
		lab._advance_combat(1.0 / 120.0)
	target.advance_frame(0.0)
	assert(target.combat_units[99].ko == 0.0 and str(target.combat_units[99].pose) == "get_up", "Wake state: %s; owner=%s" % [target.combat_units[99], target._cell_owners.get(target.cells[99])])
	await capture("03_soldier_get_up.png")
	print("SITE PLAYER SOLDIER VISUAL PASS: phase=", phase, "; authored rescue/guard/get-up with injected KO fixture, original 200 soldiers and one player")
	await finish(lab)

func finish(lab: TerrainLab) -> void:
	lab.clear_army()
	lab.queue_free()
	await process_frame
	await process_frame
	quit(0)

func capture(filename: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	assert(root.get_texture().get_image().save_png(OUTPUT + "/" + filename) == OK)
