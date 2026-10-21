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
	var before: PackedByteArray = var_to_bytes(nation)
	var members: Callable = func(id: int, _class: String) -> bool: return Orders._member(nation, id)
	# Same normalization as the private writer: upgrade + catalog revision on a detached candidate.
	var candidate: Dictionary = nation.duplicate(true)
	Orders.nation_offices(candidate)
	var seat: String = str(candidate.offices.duties["nation.ransom"])
	check(int(candidate.offices.revision) == 1 and var_to_bytes(nation) == before, "Candidate normalization adds the catalog revision once without touching the source")
	var stale: Dictionary = SiteOffices.apply_plan(candidate.offices, "nation", 0, [{"op": "appoint", "position_id": seat, "person_id": 2}], members)
	check(not stale.ok and stale.code == "STALE_REVISION", "Plan revision is the normalized office revision")
	var outsider: Dictionary = SiteOffices.apply_plan(candidate.offices, "nation", 1, [{"op": "appoint", "position_id": seat, "person_id": 3}], members)
	check(not outsider.ok and outsider.code == "NOT_ELIGIBLE", "Original membership callback rejects nonmembers")
	var head_twice: Dictionary = SiteOffices.apply_plan(candidate.offices, "nation", 1, [{"op": "appoint", "position_id": seat, "person_id": 1}], members)
	check(not head_twice.ok and head_twice.code == "DUPLICATE_HOLDER", "Head cannot hold a second nation position")
	var assigned: Dictionary = SiteOffices.apply_plan(candidate.offices, "nation", 1, [{"op": "appoint", "position_id": seat, "person_id": 2}], members)
	check(assigned.ok and int(assigned.offices.revision) == 2 and int(SiteOffices.position_of(assigned.offices, 2).get("holder", -1)) == 2, "Whole-plan engine appoints on the normalized revision")
	candidate["offices"] = assigned.offices
	check(Registry.canonical(candidate).ok and Orders.valid_nations({"n1": candidate}, {}, {1: true, 2: true}), "Private candidate is JSON-canonical and a valid original nation")
	check(var_to_bytes(nation) == before, "All pure success/refusal paths preserve source bytes")
	print("NATION_OFFICE_EDIT_", "PASS" if failures.is_empty() else "FAILED", " checks=", checks, " failures=", failures)
	quit(0 if failures.is_empty() else 1)
