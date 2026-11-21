extends "res://scripts/tests/site_building_ui_test.gd"
## Authored initial knowledge tests actual new operations, not earned research.
## Work is the original feature owner; whole collector/navigation are excluded.
const FamilyTech = preload("res://scripts/terrain_lab/site_technology.gd")

func _run() -> void:
	var data := _building_fixture()
	var farm := _formal_feature(data, "farm", Vector2i(18, 14), Vector2i(2, 2))
	_formal_feature(data, "well", Vector2i(17, 14))
	var charcoal := _formal_feature(data, "charcoal", Vector2i(26, 14))
	var weaver := _formal_feature(data, "weaver", Vector2i(32, 14))
	var tannery := _formal_feature(data, "tannery", Vector2i(38, 14))
	_formal_feature(data, "well", Vector2i(37, 14)) # The tannery recipe needs water; its own nearby original well.
	var lab := _building_lab(data)
	var actions: SitePersonActions = lab.site_controller.person_actions
	var npc_id := int(lab.npc.person_id)
	var references: Array = []
	for identity: int in [int(lab.controlled_person_id()), npc_id]:
		references.append({"site_id": str(data.site.id), "person_id": identity, "path": "", "label": "初始原人", "age_years": -1})
	assert(lab.site_controller.family_continuity.register_members(references, true, int(lab.controlled_person_id())).ok)
	assert(lab.site_controller.family_continuity.appoint_head(int(lab.controlled_person_id()), int(lab.controlled_person_id())).ok)
	var family := actions._technology_candidate()
	family.technology = FamilyTech.empty_scope_record(str(data.site.id))
	family.technology.known = ["F02", "F03", "F05", "F14"]
	data.site.family = family
	var entries := [
		{"key": farm, "recipe": "retain_seed", "skill": "F02", "input": {"seeds": 1}, "output": {"grain": 6, "seeds": 2}, "cycle": 480.0},
		{"key": charcoal, "recipe": "controlled_fire", "skill": "F03", "input": {"wood": 4}, "output": {"charcoal": 2}, "cycle": 9.0},
		{"key": weaver, "recipe": "prepared_rope", "skill": "F05", "input": {"fiber": 2}, "output": {"rope": 2}, "cycle": 6.4},
		{"key": tannery, "recipe": "careful_tan", "skill": "F14", "input": {"hide": 2}, "output": {"leather": 2}, "cycle": 13.5},
	]
	for entry: Dictionary in entries:
		assert(Runtime.request_feature_recipe(data, str(entry.key), str(entry.recipe), 1).ok)
		var feature: Dictionary = data.site.features[entry.key]
		var definition := Runtime.feature_recipe(feature)
		assert(definition.input == entry.input and definition.output == entry.output and is_equal_approx(float(definition.cycle), float(entry.cycle)))
		var slot: Dictionary = Runtime.feature_work_slots(data, feature)[0]
		assert(lab.npc.place(data.cell_from_index(int(slot.cell)), true))
		Runtime.assign_task(data, Runtime.ok("", {"target": "feature:" + str(entry.key), "action": "operate", "cell": int(slot.cell), "work_slot": int(slot.slot)}))
		var task: Dictionary = data.site.worker
		task.cell = int(slot.cell)
		task.mode = "work"
		Runtime.set_operating_slots(data, [{"task": task}])
		Runtime.allocate_water(data) # Original allocation publishes this demand from the real well before the full preflight.
		var before := var_to_bytes([data.site, lab.npc.technology])
		assert(not Runtime.work_preflight(data, task, lab.npc.ammo_inventory, Runtime.CARRY_CAPACITY, 1, npc_id).ok)
		assert(var_to_bytes([data.site, lab.npc.technology]) == before, "An unlearned actual worker cannot pay or obtain this family method")
		lab.npc.technology = FamilyTech.learned_candidate({}, str(entry.skill))
		data.site.erase("family") # D03: carrying a personal skill requires no local clan archive.
		var checked := Runtime.work_preflight(data, task, lab.npc.ammo_inventory, Runtime.CARRY_CAPACITY, 1, npc_id)
		assert(checked.ok, str(checked))
		var stock_before = data.site.inventory.duplicate()
		var cargo_before := lab.npc.ammo_inventory.duplicate()
		Runtime._feature_work(data, str(entry.key), float(checked.remaining) / 60.0 + 0.00001, Callable(), Callable(), task, lab.npc.ammo_inventory, Runtime.CARRY_CAPACITY, 1, npc_id)
		assert(not bool(feature.batch_paid) and is_zero_approx(float(feature.production)) and str(task.target).is_empty(), "The actual successful original batch ends")
		for resource: String in entry.input:
			assert(int(data.site.inventory.get(resource, 0)) == int(stock_before.get(resource, 0)) - int(entry.input[resource]))
		for resource: String in entry.output:
			assert(int(lab.npc.ammo_inventory.get(resource, 0)) == int(cargo_before.get(resource, 0)) + int(entry.output[resource]))
		assert(int(data.site.inventory.tools) == int(stock_before.tools))
		assert(feature.technology_output.receipts.size() == 1 and feature.technology_output.receipts[0].recipe_id == entry.recipe)
		lab.npc.ammo_inventory.clear()
		lab.npc.technology = {}
		Runtime.set_operating_slots(data, [])
	assert(Runtime.FEATURES.farm.output == {"grain": 8} and Runtime.FEATURES.charcoal.cycle == 10.0 \
		and Runtime.FEATURE_RECIPES.weaver.rope.cycle == 8.0 and Runtime.FEATURES.tannery.cycle == 15.0, "Basic operations remain intact")
	lab.queue_free()
	print("FAMILY_RECIPE_REAL_EFFECT_PASS: true F02/F03/F05/F14 recipe/input/output/water/work operator; authoredknowledge, fullresearch/UI/collector/Native excluded")
	quit(0)
