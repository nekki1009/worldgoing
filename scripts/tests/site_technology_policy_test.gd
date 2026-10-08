extends SceneTree
## Pure policy contract. This does not prove original-world persistence, actual
## craft guards, material conservation, trial evidence or starting artisans.
const Policy = preload("res://scripts/terrain_lab/site_technology_policy.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var empty := Policy.new_policy()
	assert(empty.ok and empty.policy.categories.is_empty())
	var first := Policy.new_policy(["F04"])
	var later := Policy.new_policy(["F06", "F04"])
	assert(first.ok and later.ok and first.policy.categories == ["F04"])
	assert(later.policy.categories == ["F04", "F06"])
	assert(not is_same(first.policy.categories, later.policy.categories))
	var original := later.policy.duplicate(true)
	var parsed := Policy.validate(later.policy)
	parsed.policy.categories.clear()
	assert(later.policy == original, "Query results cannot mutate the original frozen policy")
	assert(Policy.validate(JSON.parse_string(JSON.stringify(first.policy))).ok)
	assert(Policy.candidate({}, true).policy == empty.policy)
	assert(not Policy.candidate({}).ok and not Policy.candidate(null, true).ok)
	for raw: Variant in [{}, {"version": 1, "categories": []}, {"version": 1, "rules_version": 1, "categories": null},
		{"version": true, "rules_version": 1, "categories": []}, {"version": 2, "rules_version": 1, "categories": []},
		{"version": 1, "rules_version": 2, "categories": []}, {"version": 1, "rules_version": 1, "categories": ["F04", "F04"]},
		{"version": 1, "rules_version": 1, "categories": ["F07"]}, {"version": 1, "rules_version": 1, "categories": [], "free": true}]:
		assert(not Policy.candidate({"technology_policy": raw}, true).ok, "Existing invalid data never falls back to legacy")
	assert(not Policy.candidate({"technology_policy": null}, true).ok)
	assert(not Policy.new_policy(["F04", "F04"]).ok and not Policy.new_policy(["F07"]).ok)
	assert(Policy.same_candidate({}, {"technology_policy": empty.policy}, true).ok)
	assert(not Policy.same_candidate({"technology_policy": first.policy}, {"technology_policy": later.policy}).ok)
	assert(Policy.gate(first.policy, "F04").gated)
	for category: String in ["F06", "F11", "F12"]:
		assert(not Policy.gate(first.policy, category).gated)
	for category: String in Policy.CATEGORIES:
		assert(not Policy.gate(empty.policy, category).gated)
		assert(not Policy.gate(Policy.candidate({}, true).policy, category).gated)
	assert(not Policy.gate(null, "F04").ok and not Policy.gate(empty.policy, "F07").ok)
	assert(Policy.recipe_category("smelter", "steel") == "F04")
	assert(Policy.recipe_category("smithy", "steel_tools") == "F04")
	assert(Policy.recipe_category("weaver", "wool_cloth") == "F06")
	for pair: Array in [["weaver", ""], ["weaver", "rope"], ["smithy", ""], ["armor", "steel"], ["warehouse", "cloth"], ["shipyard", "warship"]]:
		assert(Policy.recipe_category(str(pair[0]), str(pair[1])).is_empty())
	assert(Policy.siege_category("siege_tower") == "F11")
	assert(Policy.siege_category("counterweight_trebuchet") == "F12")
	for kind: String in ["traction_trebuchet", "ram", "ballista", "ship"]:
		assert(Policy.siege_category(kind).is_empty())
	for kind: String in ["siege_tower", "counterweight_trebuchet"]:
		assert(Policy.siege_category(kind, "repair").is_empty())
	print("SITE_TECHNOLOGY_POLICY_HELPER_PASS: explicit legacy/empty/partial/frozen candidates, strict corruption rejection and four exact original manufacturing routes; actual owner gates and world persistence remain separate")
	quit(0)
