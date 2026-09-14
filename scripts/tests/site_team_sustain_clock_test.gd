extends "res://scripts/tests/site_workflow_test.gd"

const Sustain = preload("res://scripts/terrain_lab/site_sustain.gd")

class ClockLab extends TerrainLab:
	var interrupt_delivery := false
	var hit_at := -1.0
	func _resolve_combat_contacts() -> void:
		super._resolve_combat_contacts()
		# Exercise the actual damage entrypoint precisely between advance and
		# commit. This fixture verifies transaction ordering, not hit geometry.
		if interrupt_delivery:
			var entry: Dictionary = site_controller._supply_entry(army)
			if not entry.is_empty() and not entry.delivery.is_empty() and float(entry.delivery.left) <= 0.00000001:
				interrupt_delivery = false
				character.apply_contact({"result": {"hp": 1.0, "stun": 0.0, "guard_break": false}, "shield": false})
		if hit_at >= 0.0:
			var entry: Dictionary = site_controller._supply_entry(army)
			if float(entry.sustain.at) >= hit_at - 0.00000001:
				hit_at = -1.0
				character.apply_contact({"result": {"hp": 1.0, "stun": 0.0, "guard_break": false}, "shield": false})

func near(actual: float, expected: float, label: String) -> void:
	assert(absf(actual - expected) < 0.00001, "%s: %.12f != %.12f" % [label, actual, expected])

func _run() -> void:
	var lab := ClockLab.new()
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
	lab.npc.faction_id = lab.character.faction_id
	assert(lab.npc.place(Vector2i(18, 20), true))
	assert(lab.character.place(Vector2i(21, 22), true))
	var team := lab.army
	team.roster_size = 4
	var cells: Array[Vector2i] = [Vector2i(22, 22), Vector2i(23, 22), Vector2i(22, 23), Vector2i(23, 23)]
	assert(team.deploy_at(data, lab.character, lab.npc, cells))
	assert(team.enable_combat(false))
	# This four-row fixture bypasses the normal hundred-row deploy button only;
	# retain the same monotonic Site identity checkpoint as that entrypoint.
	data.site.army_next_team = team.team_id + 1
	team.set_process(false)
	team.faction_id = lab.character.faction_id
	team.settle_combat_command()
	var controller: SiteController = lab.site_controller
	data.site.manual.cargo = {"grain": 8}
	lab.character.ammo_inventory = data.site.manual.cargo
	assert(controller.begin_team_food(team, 4, team.combat_identity(0)).ok)
	var entry: Dictionary = controller._supply_entry(team)
	lab._process(0.025) # Peace: 1.5 game seconds, still before the deadline.
	assert(data.site.manual.cargo.grain == 8 and not entry.delivery.is_empty())
	var before_pause := entry.duplicate(true)
	data.site.paused = true
	lab._process(1.0)
	assert(entry == before_pause)
	data.site.paused = false
	lab._process(0.025)
	assert(entry.delivery.is_empty() and data.site.manual.cargo.grain == 4)
	near(float(entry.sustain.at), 3.0, "common peace clock")
	assert(is_same(lab.character.ammo_inventory, data.site.manual.cargo), "Delivery preserves the actual cargo reference")
	if "--panel-only" in OS.get_cmdline_user_args():
		# Bounded GPU companion: show the real delivered stock without loading
		# the full scene twice. The complete save/rebind matrix runs headless.
		await capture_panel(lab)
		lab.queue_free()
		await process_frame
		TerrainArmy.release_contact_source()
		print("SITE TEAM SUSTAIN PANEL PASS: actual adjacent delivery, pause and original supply panel; full save/rebind tested separately")
		quit(0)
		return
	assert(controller.order_team_training(team, team.current_commander, true).ok)
	var training_before := team.training
	var fatigue_before := float(team.combat_units[1].fatigue)
	lab._process(1.0)
	near(float(entry.sustain.at), 63.0, "training uses game seconds")
	assert(team.training > training_before)
	near(float(team.combat_units[1].fatigue) - fatigue_before, PersonFatigue.WORK_RATE * 60.0, "one training fatigue charge, not resting or double charging")
	assert(controller.order_team_training(team, team.current_commander, false).ok)
	data.site.combat_left = 0.5
	lab._process(1.0)
	near(float(entry.sustain.at), 93.5, "one frame spanning combat-to-peace clock boundary")
	assert(team.join_player(lab.character).ok)
	lab._process(0.1)
	assert(team.leave_player().ok)
	var personal: Dictionary = data.site.person_supply[str(lab.character.person_id)]
	assert(not personal.cohorts.is_empty())
	var history: Array = personal.cohorts.duplicate(true)
	var private_food: Dictionary = data.site.manual.cargo.duplicate()
	assert(team.join_player(lab.character).ok)
	assert(personal.cohorts.is_empty() and data.site.manual.cargo == private_food)
	personal.at = float(personal.at) - 1.0 # Legal empty-owner lag from a save.
	personal.open_rations = 0.25
	assert(team.leave_player().ok)
	assert(personal.cohorts == history, "Instant leave/rejoin retains actual hunger and meal credit")
	near(float(personal.open_rations), 0.25, "Aligning empty prior owner must not consume its opened food")
	lab._process(0.1)
	near(float(personal.at), float(entry.sustain.at), "personal and team clocks stay aligned")
	controller._capture_positions()
	var path := "res://.godot-temp/site_resources_contract/team_sustain_clock.json"
	var saved := Store.save(data, path)
	assert(saved.ok, str(saved))
	var loaded := Store.load_site(path)
	assert(loaded.ok, str(loaded))
	var food_before := Sustain.rations(entry.sustain, entry.inventory)
	var personal_before := personal.duplicate(true)
	lab.bind_terrain(loaded.data)
	data = lab.terrain
	team = lab.army
	entry = controller._supply_entry(team)
	personal = data.site.person_supply[str(lab.character.person_id)]
	near(Sustain.rations(entry.sustain, entry.inventory), food_before, "food survives actual bind/load")
	# JSON normalizes numeric/typed-array storage. Compare the exact persisted
	# representation plus explicit clock precision, not Variant container types.
	assert(JSON.stringify(personal) == JSON.stringify(personal_before), "Personal persisted history survives actual bind/load")
	near(float(personal.at), float(personal_before.at), "personal saved timestamp")
	var loaded_at := float(entry.sustain.at)
	lab._process(0.1)
	near(float(entry.sustain.at), loaded_at + 6.0, "loaded team continues common clock")
	near(float(personal.at), float(entry.sustain.at), "loaded personal clock follows")
	# Start from the same real adjacent actors, then damage at the deadline.
	assert(controller.begin_team_food(team, 1, team.combat_identity(0)).ok)
	private_food = data.site.manual.cargo.duplicate()
	lab.interrupt_delivery = true
	lab._process(0.1)
	assert(not lab.interrupt_delivery and entry.delivery.is_empty())
	assert(data.site.manual.cargo == private_food, "Effective hit at the exact commit step must win over delivery")
	assert(lab.character.hp == 99.0)
	# A newly discovered first hit at .05 real seconds must slow the remainder
	# of this .1-second frame immediately: 3 peace seconds + .05 combat seconds.
	data.site.combat_left = 0.0
	var before_hit := float(entry.sustain.at)
	lab.hit_at = before_hit + 3.0
	lab._process(0.1)
	assert(lab.hit_at == -1.0 and lab.character.hp == 98.0)
	near(float(entry.sustain.at) - before_hit, 3.05, "new hit slows the remainder of the same frame")
	near(Runtime.now(data) * 60.0, float(entry.sustain.at), "Site work clock and team clock agree after new hit")
	near(float(personal.at), float(entry.sustain.at), "personal clock agrees after new hit")
	lab.queue_free()
	await process_frame
	TerrainArmy.release_contact_source()
	print("SITE TEAM SUSTAIN CLOCK PASS: actual Lab common clock, pause, training fatigue once, combat boundary, join/leave meal history, full save/load/bind, effective-hit-before-delivery ordering; not collision geometry")
	quit(0)

func capture_panel(lab: TerrainLab) -> void:
	assert(DisplayServer.get_name() != "headless")
	root.size = Vector2i(1440, 1000)
	var controller: SiteController = lab.site_controller
	controller.supply_team_choice.select(1)
	controller.update_ui()
	var scroll := controller.panel.get_child(0) as ScrollContainer
	await process_frame
	scroll.ensure_control_visible(controller.team_supply_label)
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.visual_captures/site_team_sustain"))
	assert(root.get_texture().get_image().save_png("res://.visual_captures/site_team_sustain/panel.png") == OK)
