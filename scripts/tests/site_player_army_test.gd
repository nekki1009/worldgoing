extends SceneTree

const Store = preload("res://scripts/terrain_lab/site_store.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	create_timer(18.0).timeout.connect(func() -> void: quit(1))
	var lab := TerrainLab.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	lab.set_process(false)
	lab.site_controller.set_process(false)
	var data := TerrainGenerator.generate(0, 581)
	SiteEnvironment.initialize(data, "player-army-fixture")
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
	var deployed_teams := 0
	for team: TerrainArmy in lab.combat_armies:
		team.set_process(false)
		if not team.combat_enabled:
			continue
		deployed_teams += 1
		assert(team.issue_combat_order(team.current_commander, TerrainArmy.CombatOrder.HOLD).ok)
	assert(deployed_teams == 2, "The original melee fixture deploys exactly two armies; the third slot remains undeployed")
	var army := lab.army
	var actor := lab.character
	var original_id := actor.get_instance_id()
	var original_position := actor.position
	var original_state := actor.capture_state()
	army.training = 60.0
	assert(lab.join_player_army().ok)
	assert(army.player_member == actor and army.combat_units.size() == 100 and army.cells.size() == 100)
	assert(actor.capture_state() == original_state and actor.position == original_position, "Membership cannot clone/heal/move/equip the player")
	assert(is_equal_approx(army.training, 6000.0 / 101.0))
	var trained := army.training
	assert(not lab.join_player_army().ok and army.training == trained, "Duplicate join cannot apply training twice")
	assert(not army.player_present and army.current_commander != TerrainArmy.PLAYER_MEMBER, "Same map is not present")
	assert(lab.issue_player_army_order(TerrainArmy.CombatOrder.ATTACK).code == "NO_AUTHORITY")
	# Just outside the physical formation but inside its presence radius.
	actor.place(army.cells[0] + Vector2i(0, -1), true)
	army._command_dirty = true
	army.settle_combat_command()
	assert(army.command_eligible(TerrainArmy.PLAYER_MEMBER))
	assert(actor.command_abilities.is_empty(), "An ordinary player has no pre-rolled command stats")
	assert(army.issue_combat_order(army.current_commander, TerrainArmy.CombatOrder.MOVE, Vector2i(25, 20)).ok)
	assert(army.player_goal == Vector2i(25, 20) and not actor.is_moving())
	assert(army.issue_combat_order(army.current_commander, TerrainArmy.CombatOrder.HOLD).ok)
	# Officer preference beats the player; then the player is the sole eligible
	# ordinary member. No acceptance dialog, replacement actor or implicit attack.
	army.officer_order.assign([1, 2, 3])
	for index: int in army.officer_order:
		army._ensure_command_abilities(index)
	assert(not army.reorder_officers(TerrainArmy.PLAYER_MEMBER, [3, 2, 1]).ok)
	var lethal := {"result": {"hp": 100.0, "stun": 0.0, "guard_break": false}, "shield": false}
	army.apply_unit_contact(0, lethal)
	army.settle_combat_command()
	assert(army.current_commander == 1)
	for index in range(1, 100):
		army.apply_unit_contact(index, {"result": {"hp": 7.5, "stun": 110.0, "guard_break": false}, "shield": false} if index in [2, 3] else lethal)
	army.settle_combat_command()
	assert(army.formal_commander == TerrainArmy.PLAYER_MEMBER and army.current_commander == TerrainArmy.PLAYER_MEMBER)
	assert(actor.get_instance_id() == original_id and not actor.is_moving() and actor.action_time == 0.0)
	assert(actor.command_abilities.size() == 3 and not army.command_abilities.has(TerrainArmy.PLAYER_MEMBER))
	var abilities := actor.command_abilities.duplicate()
	assert(lab.issue_player_army_order(TerrainArmy.CombatOrder.HOLD).ok)
	data.site.combat_left = 0.0
	assert(army.reorder_officers(TerrainArmy.PLAYER_MEMBER, [3, 2]).ok)
	assert(army.officer_order == [3, 2])
	# Exercise the real dialog signals, not only its backend permission guard.
	lab.site_controller._open_officer_priority()
	var dialogs := lab.get_node("SiteUI").find_children("*", "AcceptDialog", true, false)
	var dialog := dialogs.back() as AcceptDialog
	var items := dialog.find_children("*", "ItemList", true, false)[0] as ItemList
	assert(items.item_count == 2 and not paused)
	items.select(1)
	(dialog.find_child("PriorityUp", true, false) as Button).pressed.emit()
	assert(army.officer_order == [3, 2], "Draft editing cannot mutate the live ranking")
	data.site.combat_left = 1.0
	dialog.confirmed.emit()
	assert(army.officer_order == [3, 2], "A battle starting while the panel is open rejects the entire draft")
	await process_frame
	data.site.combat_left = 1.0
	assert(not army.reorder_officers(TerrainArmy.PLAYER_MEMBER, [2, 3]).ok and army.officer_order == [3, 2], "Apply must atomically recheck combat status")
	data.site.combat_left = 0.0
	assert(not army.reorder_officers(TerrainArmy.PLAYER_MEMBER, [3, 3]).ok and army.officer_order == [3, 2])
	# Player KO uses the original HP/KO state and removes command authority.
	actor.apply_contact({"result": {"hp": 7.5, "stun": 110.0, "guard_break": false}, "shield": false})
	army.prepare_combat(0.01)
	army.settle_combat_command()
	assert(army.current_commander == -1 and army.formal_commander == TerrainArmy.PLAYER_MEMBER and army.needs_attack_order)
	assert(actor.attack_target_id == 0, "Clearing a member Actor uses its original no-target sentinel, not an Army-row index sentinel")
	for unit: Dictionary in army.combat_units:
		assert(int(unit.target) == -1, "Original NPC-row target clearing remains -1")
	assert(lab.issue_player_army_order(TerrainArmy.CombatOrder.ATTACK).code == "NO_AUTHORITY")
	data.site.combat_left = 0.0
	lab.site_controller._capture_positions()
	var original_validation := Store._validate_armies(data, data.site, true)
	if not original_validation.ok and OS.get_cmdline_user_args().has("--dump-player-validation"):
		_dump_original_validation(lab, data, original_validation)
	assert(original_validation.ok, str(original_validation))
	var saved := JSON.parse_string(JSON.stringify(data.site)) as Dictionary
	assert(TerrainArmy.valid_combat_state(saved.armies[0], data, saved.actors.player))
	assert(not TerrainArmy.valid_combat_state(saved.armies[0], data), "Missing referenced player cannot be fabricated")
	var corrupt := saved.duplicate(true)
	corrupt.armies[1].player_member = corrupt.armies[0].player_member.duplicate()
	corrupt.armies[1].faction_id = corrupt.actors.player.faction_id
	assert(not Store._validate_armies(data, corrupt).ok, "Reject duplicate membership before rebinding")
	corrupt = saved.duplicate(true)
	corrupt.actors.player.command_abilities.tactics = 1.5
	assert(not Store._validate_armies(data, corrupt).ok)
	actor.restore_state(saved.actors.player)
	army.restore_combat_state(saved.armies[0], data, actor, lab.npc)
	assert(army.player_member == actor and actor.get_instance_id() == original_id and actor.hp == 92.5 and actor.knockout_left > 0.0)
	assert(actor.command_abilities == abilities and army.current_commander == -1)
	assert(army.officer_order == [3, 2])
	assert(army.leave_player().ok and army.player_member == null and army.formal_commander == -1)
	assert(actor.command_abilities == abilities and actor.hp == 92.5, "Leaving preserves personal command abilities and wounds")
	lab.clear_army()
	lab.queue_free()
	await process_frame
	await process_frame
	print("SITE PLAYER ARMY PASS: one actor/state, ordinary authority, independent movement, officer priority, mandatory appointment, KO/save/restore, duplicate rejection, retained abilities")
	quit(0)

func _dump_original_validation(lab: TerrainLab, data: TerrainData, result: Dictionary) -> void:
	# Opt-in evidence only: inspect the already captured state, never settle,
	# repair, normalize in place or relax the original failing assertion.
	var evidence := {"result": result, "state": data.site, "map_size": [data.size.x, data.size.y],
		"pending_deaths": lab.site_controller._pending_deaths.duplicate(),
		"save_guard": lab.site_controller.supply_save_guard(), "actor_valid": {}, "army_valid": []}
	for key: String in data.site.actors:
		evidence.actor_valid[key] = TerrainTestCharacter.valid_state(data.site.actors[key], data)
	for snapshot: Dictionary in data.site.armies:
		var member_actor: Dictionary = data.site.actors.player
		if not snapshot.get("player_member", {}).is_empty():
			member_actor = {}
			for actor: Dictionary in data.site.actors.values():
				if int(actor.person_id) == int(snapshot.player_member.id): member_actor = actor
		evidence.army_valid.append({"team_id": snapshot.team_id,
			"valid": TerrainArmy.valid_combat_state(snapshot, data, member_actor, data.site)})
	var directory := "res://output/equipment_limits_20260919/cape_role"
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		push_error("PLAYER VALIDATION DUMP: cannot create evidence directory")
		return
	var path := directory + "/player_diagnostic_%d_%d.json" % [int(Time.get_unix_time_from_system()), Time.get_ticks_usec()]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("PLAYER VALIDATION DUMP: cannot open evidence file")
		return
	file.store_string(JSON.stringify(evidence, "\t", true, true))
	file.close()
	print("PLAYER VALIDATION DUMP: ", path)
