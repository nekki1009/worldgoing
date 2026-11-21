extends SceneTree
const Family = preload("res://scripts/terrain_lab/site_family_continuity.gd")
const Edit = preload("res://scripts/region_lab/region_organization_edit.gd")
var failures: Array[String] = []
var checks: int = 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _initialize() -> void:
	var offices: Dictionary = SiteOffices.default_offices("family", 1, false)
	var family: Dictionary = {"version": 2, "complete": true, "members": [{"site_id": "site", "person_id": 1, "path": "", "label": "self", "age_years": -1}], "offices": offices}
	check(Family.validate_family(family, "site"), "Original valid family fixture")
	var before: PackedByteArray = var_to_bytes(family)
	var base: Dictionary = {"families": {"family": {"record": family}}, "nations": {}}
	var transaction: Dictionary = Edit.create(base, {})
	for index: int in 3:
		var source: Dictionary = transaction.registry.families.family.record
		var candidate: Dictionary = source.duplicate(true)
		candidate.offices = Family.family_offices(source, true).duplicate(true)
		candidate.offices.duty_ai = index < 2
		check(Family.validate_family(candidate, "site") and int(candidate.offices.revision) == int(offices.revision), "Flag candidate keeps original schema and office revision")
		Edit.replace_record(transaction, "family", "family", candidate)
		check(int(transaction.revision) == index + 1 and bool(transaction.registry.families.family.record.offices.duty_ai) == (index < 2), "True, same true, false each advance only private transaction revision")
	check(var_to_bytes(family) == before and not bool(offices.duty_ai), "Pure private engine never mutates base family or office alias")
	var legacy: Dictionary = family.duplicate(true)
	legacy.offices.version = 1
	for row: Dictionary in legacy.offices.positions: row.erase("office_class")
	check(Family.validate_family(legacy, "site"), "Original legacy office shape")
	var legacy_before: PackedByteArray = var_to_bytes(legacy)
	var current: Dictionary = Family.family_offices(legacy, true)
	check(int(current.version) == SiteOffices.VERSION and int(current.revision) == int(offices.revision) and var_to_bytes(legacy) == legacy_before, "Read-only office migration retains source bytes and office revision")
	check(Family.family_offices({"version": 1}, true).is_empty(), "Unestablished family has no authority-bearing offices")
	print("FAMILY_DUTY_AI_EDIT_", "PASS" if failures.is_empty() else "FAILED", " checks=", checks, " failures=", failures)
	quit(0 if failures.is_empty() else 1)
