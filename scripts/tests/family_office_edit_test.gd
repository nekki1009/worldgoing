extends SceneTree
const Family = preload("res://scripts/terrain_lab/site_family_continuity.gd")
var failures: Array[String] = []
var checks: int = 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _initialize() -> void:
	var offices: Dictionary = SiteOffices.default_offices("family", 1)
	var before: PackedByteArray = var_to_bytes(offices)
	var members: Array[int] = [1, 2]
	var seat: String = str(offices.duties["family.research"])
	var eligible: Callable = func(id: int, _class: String) -> bool: return members.has(id)
	var assigned: Dictionary = SiteOffices.apply_plan(offices, "family", 0, [{"op": "appoint", "position_id": seat, "person_id": 2}], eligible)
	check(assigned.ok and int(assigned.offices.revision) == 1 and var_to_bytes(offices) == before, "Original whole-plan engine creates detached final-state candidate")
	var duplicate: Dictionary = SiteOffices.apply_plan(offices, "family", 0, [{"op": "appoint", "position_id": seat, "person_id": 1}], eligible)
	check(not duplicate.ok and duplicate.code == "DUPLICATE_HOLDER", "Head cannot hold a second family position")
	var missing: Dictionary = SiteOffices.apply_plan(offices, "family", 0, [{"op": "appoint", "position_id": seat, "person_id": 3}], eligible)
	check(not missing.ok and missing.code == "NOT_ELIGIBLE", "Original membership callback rejects nonmembers")
	var stale: Dictionary = SiteOffices.apply_plan(offices, "family", 1, [{"op": "rename", "position_id": seat, "name": "族務官"}], eligible)
	var orphan: Dictionary = SiteOffices.apply_plan(offices, "family", 0, [{"op": "abolish", "position_id": seat}], eligible)
	check(not stale.ok and stale.code == "STALE_REVISION" and not orphan.ok and orphan.code == "DUTY_ORPHAN", "Original stale office revision and orphan-duty rules retained")
	var added: Dictionary = SiteOffices.apply_plan(offices, "family", 0, [{"op": "add", "name": "新族務官", "ref": "new"}, {"op": "assign", "duty_id": "family.research", "position_id": "new"}, {"op": "appoint", "position_id": "new", "person_id": 2}], eligible)
	check(added.ok and added.refs.has("new") and SiteOffices.position_of(added.offices, 2).id == added.refs.new, "Atomic add/assign/appoint resolves original refs")
	var legacy: Dictionary = offices.duplicate(true)
	legacy.version = 1
	for row: Dictionary in legacy.positions: row.erase("office_class")
	var family: Dictionary = {"offices": legacy}
	var legacy_before: PackedByteArray = var_to_bytes(family)
	var detached: Dictionary = Family.family_offices(family, true)
	var upgraded: Dictionary = SiteOffices.apply_plan(detached, "family", int(detached.revision), [{"op": "appoint", "position_id": seat, "person_id": 2}], eligible)
	check(upgraded.ok and int(upgraded.offices.version) == SiteOffices.VERSION and var_to_bytes(family) == legacy_before, "Read-only legacy offices remain byte-identical on successful plan")
	check(var_to_bytes(offices) == before, "All pure success/refusal paths preserve source bytes")
	print("FAMILY_OFFICE_EDIT_", "PASS" if failures.is_empty() else "FAILED", " checks=", checks, " failures=", failures)
	quit(0 if failures.is_empty() else 1)
