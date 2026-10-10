extends "res://scripts/tests/site_building_ui_test.gd"
## Actual original owners with F15 still disabled. NOT_RUN.
const Catalog = preload("res://scripts/terrain_lab/site_technology_catalog.gd")

func _run() -> void:
	assert(Catalog.get_node("F15").enabled == false, "Disabled oracle runs before the separate isolated activation hunk")
	var data := _building_fixture()
	var lab := _building_lab(data)
	var identity := lab.controlled_person_id()
	assert(lab.character.place(Vector2i(9, 10), true))
	var before := var_to_bytes(data.site)
	assert(not lab.site_controller.person_actions.prepare_scope_technology(identity, identity, "F15").ok)
	assert(not Runtime.ranged_craft(data, "fire_pot", identity, true).ok)
	assert(not Runtime.ranged_craft(data, "fire_pot", identity).ok)
	assert(var_to_bytes(data.site) == before, "Disabled F15 rejects before actual materials, jobs or fatigue")
	assert(Runtime.ranged_craft(data, "fire_arrow", identity, true).ok, "Original fire-arrow admission remains available under its original recipe rules")
	lab.site_controller.work_team.discard_prepared_interval()
	lab.free()
	TerrainArmy.release_contact_source()
	print("SITE_TECHNOLOGY_FIRE_POT_DISABLED_PASS original disabled zero-cost boundary and unchanged fire-arrow recipe")
	quit(0)
