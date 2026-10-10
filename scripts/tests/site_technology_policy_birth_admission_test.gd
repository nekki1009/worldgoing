extends SceneTree
## World birth admits only catalog-admitted threshold categories (plan D10 lines
## 22/168/172). Any category the loaded catalog does not admit is still refused.

const Policy = preload("res://scripts/terrain_lab/site_technology_policy.gd")
var _failed := false

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		push_error("SITE_TECHNOLOGY_POLICY_BIRTH_ADMISSION_FAIL: " + message)

func _initialize() -> void:
	var admitted: Array[String] = Policy.catalog_admitted_categories()
	for category: String in admitted:
		_check(SiteTechnologyCatalog.get_node(category).get("enabled") == true, "Admitted category %s is an enabled catalog node" % category)
	var empty: Dictionary = Policy.new_policy([])
	_check(empty.ok and Policy.birth_categories_admitted(empty.policy), "An empty policy is always admitted at birth")
	var refused := 0
	for category: String in Policy.CATEGORIES:
		var single: Dictionary = Policy.new_policy([category])
		_check(single.ok, "Policy with %s is well-formed" % category)
		if admitted.has(category):
			_check(Policy.birth_categories_admitted(single.policy), "Catalog-admitted %s is admitted at birth" % category)
		else:
			refused += 1
			_check(not Policy.birth_categories_admitted(single.policy), "Category %s that the catalog does not admit is refused at birth" % category)
			var mixed: Dictionary = Policy.new_policy(admitted + [category] if not admitted.has(category) else admitted)
			_check(mixed.ok and not Policy.birth_categories_admitted(mixed.policy), "Adding unadmitted %s to admitted categories is still refused" % category)
			var lab_result: Dictionary = _birth_guard_result(single.policy)
			_check(not lab_result.ok and str(lab_result.code) == "TECH_POLICY_CONFLICT", "TerrainLab birth guard refuses unadmitted %s: %s" % [category, str(lab_result)])
	_check(refused > 0 or admitted.size() == Policy.CATEGORIES.size(), "Refusal coverage is exercised whenever any category is unadmitted")
	if _failed:
		quit(1)
		return
	print("SITE_TECHNOLOGY_POLICY_BIRTH_ADMISSION_PASS: admitted=%s refused_categories=%d" % [str(admitted), refused])
	quit(0)

func _birth_guard_result(policy: Dictionary) -> Dictionary:
	var lab: TerrainLab = TerrainLab.new()
	var data := TerrainData.new()
	data.site = {"id": "policy-birth", "world_pin": {"format": 2, "technology_policy": policy}}
	var result: Dictionary = lab.prepare_fresh_initial_population(data)
	lab.free()
	return result
