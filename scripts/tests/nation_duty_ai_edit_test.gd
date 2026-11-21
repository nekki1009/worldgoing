extends SceneTree
const Orders = preload("res://scripts/terrain_lab/site_equipment_orders.gd")
const Registry = preload("res://scripts/region_lab/region_organization_registry.gd")
var failures: Array[String] = []
var checks: int = 0
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _old(offices: Dictionary) -> void:
	offices["version"] = 1
	var removed: String = str(offices.duties["nation.ransom"])
	offices.duties.erase("nation.ransom")
	for row: Dictionary in offices.positions.duplicate():
		if row.id == removed: offices.positions.erase(row)
		else: row.erase("office_class")

func _initialize() -> void:
	var nation: Dictionary = {"members": [1, 2], "standards": {}, "offices": SiteOffices.default_offices("nation", 1)}
	_old(nation.offices)
	check(Orders.valid_nations({"n1": nation}, {}, {1: true, 2: true}), "Original schema accepts old offices and missing later catalog")
	var before: PackedByteArray = var_to_bytes(nation)
	var readonly: Dictionary = Orders.nation_offices(nation, true)
	check(int(readonly.version) == SiteOffices.VERSION and readonly.duties.has("nation.ransom") and int(readonly.revision) == 0 and var_to_bytes(nation) == before, "Readonly authority derivation upgrades only a copy without catalog revision")
	var candidate: Dictionary = nation.duplicate(true)
	var alias: Dictionary = candidate.offices
	Orders.nation_offices(candidate)
	candidate.offices["duty_ai"] = true
	check(is_same(alias, candidate.offices) and int(candidate.offices.revision) == 1 and candidate.offices.duties.has("nation.ransom") and Registry.canonical(candidate).ok and Orders.valid_nations({"n1": candidate}, {}, {1: true, 2: true}), "Original successful writer normalization preserves alias and applies complete catalog revision once")
	Orders.nation_offices(candidate)
	candidate.offices["duty_ai"] = true
	check(int(candidate.offices.revision) == 1 and Registry.canonical(candidate).ok and var_to_bytes(nation) == before, "Same flag adds no office revision and source bytes remain unchanged")
	var legacy: Dictionary = {"members": [1], "standards": {}, "military_head": 1}
	var legacy_before: PackedByteArray = var_to_bytes(legacy)
	var legacy_view: Dictionary = Orders.nation_offices(legacy, true)
	check(not legacy_view.is_empty() and not legacy.has("offices") and var_to_bytes(legacy) == legacy_before, "Unestablished legacy view never grants an installed head office")
	var invalid: Dictionary = {}
	invalid[StringName("duty_ai")] = true
	check(not Registry.canonical(invalid).ok, "StringName remains refused by unchanged canonical")
	print("NATION_DUTY_AI_EDIT_", "PASS" if failures.is_empty() else "FAILED", " checks=", checks, " failures=", failures)
	quit(0 if failures.is_empty() else 1)
