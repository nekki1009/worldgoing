extends SceneTree
const Family = preload("res://scripts/terrain_lab/site_family_continuity.gd")
const Registry = preload("res://scripts/region_lab/region_organization_registry.gd")
var failures: Array[String] = []
var checks: int = 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _member(id: int, site: String = "site") -> Dictionary:
	return {"site_id": site, "person_id": id, "path": "", "label": "Original person", "age_years": -1}

func _initialize() -> void:
	var family: Dictionary = {"version": 4, "name": "原家族", "lineage_id": 1, "complete": true, "members": [_member(1), _member(2), _member(3), _member(4, "remote")], "offices": SiteOffices.default_offices("family", 1)}
	var before: PackedByteArray = var_to_bytes(family)
	var alive: Callable = func(_id: int) -> bool: return true
	var result: Dictionary = Family.designate_heir_candidate(family, "site", 1, 2, alive)
	check(result.ok and Family.validate_family(result.family, "site") and int(result.family.version) == 5 and Registry.canonical(result.family).ok, "Original v4-to-v5 producer emits valid canonical String-key family")
	check(var_to_bytes(family) == before and not family.has("succession"), "Original candidate never inserts succession into source")
	var seat: String = str(SiteOffices.head_position(family.offices).id)
	check(int(result.family.succession.heirs[seat]) == 2 and int(result.family.offices.revision) == 1 and int(SiteOffices.head_position(result.family.offices).holder) == 1, "Heir stored on original head seat with one office revision and unchanged incumbent")
	var repeated: Dictionary = Family.designate_heir_candidate(result.family, "site", 1, 2, alive)
	var changed: Dictionary = Family.designate_heir_candidate(repeated.family, "site", 1, 3, alive)
	check(repeated.ok and changed.ok and int(changed.family.offices.revision) == 3 and int(changed.family.succession.heirs[seat]) == 3 and Registry.canonical(changed.family).ok, "Repeated designation and replacement keep original office revision behavior")
	var bad_requester: Dictionary = Family.designate_heir_candidate(family, "site", -1, 2, alive)
	var self_heir: Dictionary = Family.designate_heir_candidate(family, "site", 1, 1, alive)
	var remote: Dictionary = Family.designate_heir_candidate(family, "site", 1, 4, alive)
	var dead: Dictionary = Family.designate_heir_candidate(family, "site", 1, 2, func(_id: int) -> bool: return false)
	check(not bad_requester.ok and bad_requester.code == "NO_AUTHORITY" and not self_heir.ok and self_heir.code == "DUPLICATE_HOLDER" and not remote.ok and remote.code == "NO_TARGET" and not dead.ok and dead.code == "NO_TARGET", "Original positive seated head, distinct local member and physical callback refusals")
	var maxed: Dictionary = result.family.duplicate(true)
	maxed.offices["revision"] = SiteOffices.MAX_SEQ
	var capped: Dictionary = Family.designate_heir_candidate(maxed, "site", 1, 3, alive)
	check(capped.ok and int(capped.family.offices.revision) == SiteOffices.MAX_SEQ, "Original revision clamp retained")
	var strict: Dictionary = {}
	strict[StringName("succession")] = {}
	check(not Registry.canonical(strict).ok and var_to_bytes(family) == before, "Actual StringName still refused; all pure paths preserve source")
	print("FAMILY_HEIR_EDIT_", "PASS" if failures.is_empty() else "FAILED", " checks=", checks, " failures=", failures)
	quit(0 if failures.is_empty() else 1)
