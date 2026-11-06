extends SceneTree
## Pure catalog/schema and pinned original-operation metadata, not gameplay validation.
const Catalog = preload("res://scripts/terrain_lab/site_technology_catalog.gd")
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Ships = preload("res://scripts/terrain_lab/site_vehicle_ship_definitions.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var entries := Catalog.all()
	assert(entries.size() == 40 and Catalog.validate_catalog(entries))
	assert(Catalog.validate_catalog(JSON.parse_string(JSON.stringify(entries))), "JSON exact-number admission")
	var all_ids := Catalog.ids()
	assert(all_ids.size() == 40)
	all_ids.clear()
	assert(Catalog.ids().size() == 40, "Catalog IDs are caller-local")
	for entry: Dictionary in entries:
		# Accepted nodes (Nekki 2026-11-06 node-by-node acceptance) are enabled and implemented; every other stays off.
		assert(bool(entry.enabled) == (str(entry.status) == "implemented"), "Only accepted (implemented) nodes are enabled; candidates and P1 integration cannot claim runtime completion")
		if str(entry.id) == "F03": assert(bool(entry.enabled), "F03 is accepted")
		assert(not entry.operations.is_empty() and not entry.research.routes.is_empty())
		for hook: String in entry.required_hooks: _check_hook(hook)
		for route: Dictionary in entry.research.routes:
			assert(not Catalog.research_budget(str(entry.id), str(route.id)).is_empty())
			for phase: Dictionary in route.phases:
				var original := Catalog.binding(str(phase.binding))
				_check_hook(str(original.file) + ":" + str(original.anchor))
				if bool(original.existing): _check_original_terms(phase, original)
		for operation: Dictionary in entry.operations:
			var original := Catalog.binding(str(operation.binding))
			assert(bool(original.existing) or not str(original.extension).is_empty(), "Missing operations need precise extensions")

	var f07 := Catalog.get_node("F07")
	var f07_budget := Catalog.research_budget("F07")
	assert(f07_budget.external_materials == {"wood": 12, "fiber": 6} and float(f07_budget.seconds) == 360.0)
	assert(int(f07.research.routes[0].phases[0].repeat) == 3)
	assert(f07.operations[0].effect.parameters.baseline_seconds == 120 and f07.operations[0].effect.parameters.new_seconds == 108)
	assert(f07.operations[1].effect.parameters.effective_seconds == 300 and f07.operations[1].effect.parameters.materials.is_empty())
	f07.research.routes[0].phases[0].materials.wood = 999
	assert(Catalog.get_node("F07").research.routes[0].phases[0].materials.wood == 4, "Deep catalog isolation")
	var bow_binding := Catalog.binding("bow")
	bow_binding.recipe = "not-original"
	assert(Catalog.binding("bow").recipe == "bow", "Deep binding isolation")

	var steel := Catalog.research_budget("F04")
	assert(steel.external_materials == {"iron_ore": 3, "charcoal": 5, "wood": 1}, "Zero-steel bootstrap uses its own real intermediates")
	assert(steel.transaction_inputs == {"iron_ore": 3, "charcoal": 5, "iron": 2, "steel": 1, "wood": 1}, "Every original batch still pays its actual inputs")
	assert(steel.remaining_trial_outputs == {"tools": 2})
	assert(Catalog.POLICY_CATEGORIES == ["F04", "F06", "F11", "F12"] and not Catalog.POLICY_CATEGORIES.has("F07"))
	assert(Catalog.get_node("S07").prerequisites.all == ["F07"] and not Catalog.get_node("S04").prerequisites.all.has("S03"))
	assert(Catalog.get_node("F13").operations[0].effect.parameters.existing_six_ship_build_rights_unchanged)
	assert(Catalog.get_node("S08").operations[0].effect.parameters.basic_repair_unchanged)
	assert(Catalog.get_node("N05").operations[0].effect.parameters.setting_existing_standard_unlocked)
	var n04_facts := _facts(Catalog.get_node("N04"))
	assert(Catalog.prerequisites_met("N04", ["N01", "S07"], n04_facts))
	assert(Catalog.prerequisites_met("N04", ["N01", "S04"], n04_facts))
	assert(not Catalog.prerequisites_met("N04", ["N01"], n04_facts))
	assert(Catalog.prerequisites_met("N04", ["N01", "S07"], n04_facts, "bow"))
	assert(not Catalog.prerequisites_met("N04", ["N01", "S07"], n04_facts, "metal"), "Any industry does not authorize a different route")
	assert(not Catalog.prerequisites_met("N04", ["N01", "S07"], n04_facts, "unknown-route"))
	assert(Catalog.research_budget("N04").is_empty(), "OR industry routes are not silently chosen")
	var f12_facts := _facts(Catalog.get_node("F12"))
	f12_facts.erase("family_original_traction_build_receipt")
	assert(not Catalog.prerequisites_met("F12", ["F11"], f12_facts))
	f12_facts.family_original_traction_build_receipt = true
	assert(Catalog.prerequisites_met("F12", ["F11"], f12_facts))

	var invalid := Catalog.all()
	invalid[0].prerequisites.all = ["F00"]
	assert(not Catalog.validate_catalog(invalid))
	invalid = Catalog.all()
	invalid[0].prerequisites.all = ["F01"]
	assert(not Catalog.validate_catalog(invalid))
	invalid = Catalog.all()
	invalid[0].prerequisites.all = ["F02"] # F02 already requires F01.
	assert(not Catalog.validate_catalog(invalid), "A real dependency cycle is rejected")
	invalid = Catalog.all()
	invalid[0].research.routes[0].phases[0].required_skills = ["F02"]
	assert(not Catalog.validate_catalog(invalid), "A required personal skill cannot hide a research cycle")
	invalid = Catalog.all()
	invalid[0].research.routes[0].phases[0].worker = "qualified_original_workers_bound_per_phase"
	assert(not Catalog.validate_catalog(invalid), "Family evidence cannot silently become shared worker credit")
	invalid = Catalog.all()
	invalid[0].research.routes[0].phases[0].materials.seeds = -1
	assert(not Catalog.validate_catalog(invalid))
	invalid = Catalog.all()
	invalid[0].research.routes[0].phases[0].policy_exception = "F01"
	assert(not Catalog.validate_catalog(invalid), "Only the four bound D10 self-trials may waive their own gate")
	invalid = Catalog.all()
	invalid[0].enabled = true
	assert(not Catalog.validate_catalog(invalid), "An unimplemented operation cannot become enabled")
	invalid = Catalog.all()
	invalid[0].research.routes[0].phases[0].binding = "fictional-owner"
	assert(not Catalog.validate_catalog(invalid))
	invalid = Catalog.all()
	invalid[1].id = "F01"
	assert(not Catalog.validate_catalog(invalid))
	print("SITE_TECHNOLOGY_CATALOG_PASS: 40 disabled entries, acyclic explicit prerequisites/OR routes, 55 original anchors, real recipe terms, zero-steel bootstrap, F07 pins, strict invalid schema; operation runtime/gameplay excluded")
	quit(0)

func _facts(entry: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for fact: String in entry.prerequisites.conditions: result[fact] = true
	return result

func _check_hook(hook: String) -> void:
	var separator := hook.rfind(":")
	assert(separator > 6)
	var path := hook.left(separator)
	var anchor := hook.substr(separator + 1)
	assert(FileAccess.file_exists(path), path)
	var source := FileAccess.get_file_as_string(path)
	var expression := RegEx.new()
	assert(expression.compile("(?m)^\\s*(?:(?:static\\s+)?func\\s+" + anchor + "\\(|const\\s+" + anchor + "(?:\\s|:))") == OK)
	assert(expression.search(source) != null, hook)

func _check_original_terms(phase: Dictionary, original: Dictionary) -> void:
	var recipe := str(original.recipe)
	var host := str(original.host)
	var inputs: Dictionary = {}
	var outputs: Dictionary = {}
	var seconds := -1.0
	var items: Array[String] = []
	if original.anchor == "_feature_work":
		var terms: Dictionary = Runtime.FEATURES[host].duplicate(true)
		if not recipe.is_empty(): terms.merge(Runtime.FEATURE_RECIPES[host][recipe], true)
		inputs = terms.input
		outputs = terms.output
		seconds = float(terms.cycle) * 60.0
	elif original.anchor == "ranged_craft":
		var terms: Dictionary = Runtime.RANGED_RECIPES[recipe]
		inputs = terms.cost
		outputs = terms.get("output", {})
		seconds = float(terms.duration)
		if terms.has("asset"): items.append("weapon:" + str(terms.asset))
	elif original.anchor == "begin_siege_build":
		inputs = Runtime.SIEGE_DEFINITIONS[recipe].cost
		seconds = float(Runtime.SIEGE_DEFINITIONS[recipe].work_seconds)
	elif original.anchor == "begin_ship_build":
		inputs = Ships.build_cost(recipe)
		seconds = Ships.build_work_seconds(recipe)
	elif original.anchor == "request_build":
		inputs = Runtime.FEATURES[recipe].cost
		seconds = float(Runtime.FEATURES[recipe].work) * 60.0
	if seconds < 0.0: return # Transport/issue use their own original bound transaction and actual arrival.
	if str(phase.duration_tech) in ["F03", "F07", "F13"]: seconds *= 0.9
	assert(phase.materials == inputs, str(phase.id) + " material pin")
	assert(is_equal_approx(float(phase.seconds), seconds), str(phase.id) + " original seconds/effect pin")
	assert(phase.outputs == outputs and phase.items == items, str(phase.id) + " true original product pin")

