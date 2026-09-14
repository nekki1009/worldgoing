extends "res://scripts/tests/site_workflow_test.gd"
const Actions = preload("res://scripts/terrain_lab/site_person_actions.gd")

func _run() -> void:
	var lab := TerrainLab.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	lab.set_process(false)
	lab.character.set_process(false)
	lab.npc.set_process(false)
	lab.npc_retaliates = false
	lab.site_controller._auto_save_blocked = true
	var data := _fixture()
	data.site.worker_enabled = false
	lab.bind_terrain(data)
	var controller: SiteController = lab.site_controller
	var actions: Actions = controller.person_actions
	var player := lab.character
	var target := lab.npc
	target.faction_id = player.faction_id
	assert(player.place(Vector2i(21, 22), true))
	assert(target.place(Vector2i(22, 22), true))
	if "--visual" in OS.get_cmdline_user_args():
		await _visual_companion(lab)
		lab.queue_free()
		await process_frame
		TerrainArmy.release_contact_source()
		print("SITE LOOT VISUAL COMPANION PASS: original timed item transactions and visible removed armor/shield; complete Site clock and save/load tested headless")
		quit(0)
		return
	var original_body := target.get_instance_id()
	var original_holder := target.item_state
	var count: int = data.site.item_records.size()
	var armor: String = target.item_state.equipped.armor
	var before: Array = target.item_state.item_ids.duplicate()
	data.site.worker.cargo.arrow = 6
	target.apply_contact({"result": {"hp": 0.0, "stun": 100.0, "guard_break": false}, "shield": false})
	assert(target.knockout_left > 0.0 and data.site.ground_loot.is_empty())
	assert(actions.begin_loot(player.person_id, "person", str(target.person_id), {}, [armor]).ok)
	lab._process(4.9)
	assert(target.item_state.item_ids.has(armor) and not player.item_state.item_ids.has(armor))
	lab._process(0.11)
	assert(not actions.is_busy(player.person_id))
	assert(not target.item_state.equipped.has("armor") and player.item_state.item_ids.has(armor))
	assert(controller.person_appearance(target.person_id).parts.armor == "none")
	assert(data.site.item_records.size() == count and is_same(original_holder, target.item_state))
	# Wake and a second knockout retain the same actual missing equipment.
	target.knockout_left = 0.001
	lab._process(float(TerrainArmy.CombatTimings.POSE_SECONDS[&"get_up"]) + 0.1)
	assert(target.can_act() and not target.item_state.item_ids.has(armor))
	target.apply_contact({"result": {"hp": 0.0, "stun": 100.0, "guard_break": false}, "shield": false})
	assert(data.site.ground_loot.is_empty() and data.site.item_records.size() == count)
	# A committed legal step is not discarded by death. Drop only after fall/arrival.
	target.knockout_left = 0.0
	target._getting_up = false
	assert(target.place(Vector2i(22, 23)))
	target.apply_contact({"result": {"hp": 100.0, "stun": 0.0, "guard_break": false}, "shield": false})
	assert(target.hp == 0.0 and not target.loot_settled)
	lab._process(0.1)
	assert(data.site.ground_loot.is_empty())
	lab._process(float(TerrainArmy.CombatTimings.POSE_SECONDS[&"down"]) + 0.1)
	assert(target.get_instance_id() == original_body and target.loot_settled and not target.is_moving())
	assert(target.item_state.item_ids.is_empty() and data.site.worker.cargo.is_empty())
	assert(data.site.ground_loot.size() == 1)
	var remains: Dictionary = data.site.ground_loot[target.remains_id]
	assert(int(remains.cell) == data.index(Vector2i(22, 23)) and remains.cargo.arrow == 6)
	assert(remains.item_ids.size() == before.size() - 1 and not remains.item_ids.has(armor))
	assert(controller.person_appearance(target.person_id).parts.shield != "none")
	var next: int = data.site.next_loot
	target.apply_contact({"result": {"hp": 100.0, "stun": 100.0, "guard_break": false}, "shield": false})
	lab._process(0.1)
	assert(data.site.next_loot == next and data.site.item_records.size() == count)
	assert(player.place(Vector2i(21, 23), true))
	var shield: String = remains.equipped.shield
	assert(actions.begin_loot(player.person_id, "ground", target.remains_id, {}, [shield]).ok)
	lab._process(5.1)
	assert(player.item_state.item_ids.has(shield) and not remains.equipped.has("shield"))
	assert(controller.person_appearance(target.person_id).parts.shield == "none")
	controller._capture_positions()
	data.site.combat_left = 0.0 # Legal post-combat snapshot, not a combat-save bypass.
	var path := "res://.godot-temp/site_resources_contract/loot_lifecycle.json"
	var saved := Store.save(data, path)
	assert(saved.ok, str(saved))
	var loaded := Store.load_site(path)
	assert(loaded.ok, str(loaded))
	var saved_next := int(data.site.next_loot)
	lab.bind_terrain(loaded.data)
	assert(lab.npc.hp == 0.0 and lab.npc.loot_settled)
	assert(lab.terrain.site.item_records.size() == count and lab.terrain.site.next_loot == saved_next)
	assert(lab.npc.item_state.item_ids.is_empty())
	assert(controller.person_appearance(lab.npc.person_id).parts.armor == "none")
	assert(controller.person_appearance(lab.npc.person_id).parts.shield == "none")
	lab._process(0.05)
	assert(lab.terrain.site.next_loot == saved_next)
	lab.queue_free()
	await process_frame
	TerrainArmy.release_contact_source()
	print("SITE LOOT LIFECYCLE PASS: original NPC KO loot, missing armor, wake/re-KO, deferred real death drop, original cargo and corpse shield loot, full save/load/bind without refill")
	quit(0)

func _visual_companion(lab: TerrainLab) -> void:
	# Render/transaction companion only: do not replay thousands of live GPU
	# geometry samples or duplicate the complete headless save/clock proof here.
	assert(DisplayServer.get_name() != "headless")
	print("LOOT VISUAL stage: scene ready")
	root.size = Vector2i(1440, 1000)
	root.content_scale_size = Vector2i(1440, 1000)
	await process_frame
	await process_frame
	var target := lab.npc
	var controller: SiteController = lab.site_controller
	var actions: Actions = controller.person_actions
	lab.camera.zoom = Vector2.ONE * 3.0
	lab.camera.position = target.position + Vector2(65, -25)
	lab.camera.force_update_scroll()
	target.apply_contact({"result": {"hp": 0.0, "stun": 100.0, "guard_break": false}, "shield": false})
	target.editor.animation_player.seek(float(TerrainArmy.CombatTimings.POSE_SECONDS[&"down"]), true)
	await _capture_loot_frame("before_loot")
	print("LOOT VISUAL stage: original gear captured")
	var armor: String = target.item_state.equipped.armor
	assert(actions.begin_loot(lab.character.person_id, "person", str(target.person_id), {}, [armor]).ok)
	actions.advance(5.01)
	var results := actions.settle_after_contacts()
	assert(results.size() == 1 and results[0].ok)
	assert(target.editor.capture_appearance().parts.armor == "none")
	target.apply_contact({"result": {"hp": 100.0, "stun": 0.0, "guard_break": false}, "shield": false})
	controller.settle_person_deaths(float(TerrainArmy.CombatTimings.POSE_SECONDS[&"down"]) + 0.01)
	var remains: Dictionary = lab.terrain.site.ground_loot[target.remains_id]
	var shield: String = remains.equipped.shield
	assert(actions.begin_loot(lab.character.person_id, "ground", target.remains_id, {}, [shield]).ok)
	actions.advance(5.01)
	results = actions.settle_after_contacts()
	assert(results.size() == 1 and results[0].ok)
	assert(target.editor.capture_appearance().parts.armor == "none" and target.editor.capture_appearance().parts.shield == "none")
	target.editor.animation_player.seek(float(TerrainArmy.CombatTimings.POSE_SECONDS[&"down"]), true)
	controller.view.animate(0.0)
	controller.select_cell(target.terrain_cell)
	controller._open_person_inventory()
	var dialog := lab.get_node("SiteUI").get_children().back() as Window
	var source := dialog.find_child("LootSource", true, false) as OptionButton
	source.select(1)
	source.item_selected.emit(1)
	dialog.position = Vector2i(865, 140)
	print("LOOT VISUAL stage: removed gear and real loot panel")
	await _capture_loot_frame("loot_panel")

func _capture_loot_frame(label: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var output := "res://output/site_loot_lifecycle_20260913/" + label + ".png"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
	assert(root.get_texture().get_image().save_png(ProjectSettings.globalize_path(output)) == OK)
