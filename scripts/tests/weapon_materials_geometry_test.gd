extends "res://scripts/tests/site_army_equipment_query_test.gd"
## Reuse the actual Actor versus shared query comparison, including armor.
const Materials = preload("res://scripts/ui/weapon_materials.gd")

func run() -> void:
	assert(DisplayServer.get_name() != "headless")
	var args := OS.get_cmdline_user_args()
	assert(args.size() == 1 and args[0] in ["wood", "stone", "iron", "steel"])
	assert(TerrainArmy.load_combat_bake())
	var baseline: Dictionary = TerrainArmy._combat_bake.manifest.appearance.duplicate(true)
	var actor := TerrainTestCharacter.new()
	root.add_child(actor)
	actor.set_process(false)
	actor.initialize_visual()
	assert(actor.editor.restore_appearance(baseline))
	actor.editor.set_process(false)
	actor.editor.combat_ready = true
	actor.editor.visual_state.combat_ready = true
	actor.editor.set_playing(false)
	var source := Source.new()
	assert(source.initialize(root, baseline, actor.editor))
	for row: Dictionary in Materials.OPTIONS:
		if row.get("material") != args[0]: continue
		var appearance := baseline.duplicate(true)
		appearance.parts.weapon = row.id
		appearance.parts.shield = "none"
		var weapon := StringName(row.id)
		assert(row.id in source._available_parts.weapon)
		var query := compare_pose(source, actor, appearance, &"attack", 0.537, Vector2i.RIGHT)
		assert(actor.editor.selected_animation == Materials.ATTACKS[Materials.family(weapon)])
		assert(source.editor.selected_animation == actor.editor.selected_animation)
		assert(query.weapon.is_empty() == Materials.is_ranged(weapon))
		var guard := compare_pose(source, actor, appearance, &"guard", 0.093, Vector2i.LEFT)
		assert(guard.parry.is_empty() == Materials.is_ranged(weapon))
		if not Materials.is_ranged(weapon):
			assert(source.editor.selected_animation == (&"guard_polearm" if Materials.is_polearm(weapon) else &"guard_weapon"))
		print("WEAPON_MATERIAL_GEOMETRY_OPTION_PASS ", row.id)
	source.dispose()
	actor.queue_free()
	await process_frame
	print("WEAPON_MATERIAL_GEOMETRY_PASS material=",args[0]," poses=",checked," armor_points=",armor_points," max_boundary_error=",maximum_error)
	quit(0)
