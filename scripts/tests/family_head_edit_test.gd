extends SceneTree
const Registry = preload("res://scripts/region_lab/region_organization_registry.gd")
const Travel = preload("res://scripts/region_lab/region_travel.gd")
const Family = preload("res://scripts/terrain_lab/site_family_continuity.gd")
var failures: Array[String] = []
var checks: int = 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _initialize() -> void:
	var original_source: Dictionary = {"id": "typed_producer"}
	var source_bytes: PackedByteArray = var_to_bytes(original_source)
	var produced: Dictionary = Travel.prepare_identity(original_source)
	check(produced.ok and Registry.canonical(produced.state).ok and var_to_bytes(original_source) == source_bytes, "Original identity producer emits String keys without changing source")
	var strict: Dictionary = {}
	strict[StringName("family_members")] = {}
	check(not Registry.canonical(strict).ok, "Canonical still refuses actual StringName keys")
	var empty: Dictionary = {}
	var npc: Dictionary = Family.head_offices_candidate(empty, 2, 1)
	var controlled: Dictionary = Family.head_offices_candidate(empty, 1, 1)
	check(npc.ok and npc.offices.duty_ai and int(SiteOffices.head_position(npc.offices).holder) == 2, "Original NPC-founded defaults retained")
	check(controlled.ok and not controlled.offices.duty_ai and int(SiteOffices.head_position(controlled.offices).holder) == 1, "Original controlled-founder defaults retained")
	check(empty.is_empty() and npc.validation == "office_candidate_only", "Pure plan mutates no input and grants no caller/physical authority")
	var offices: Dictionary = SiteOffices.default_offices("family", -1, false)
	var before: PackedByteArray = var_to_bytes(offices)
	var first: Dictionary = Family.head_offices_candidate(offices, 1, 1)
	var repeated: Dictionary = Family.head_offices_candidate(first.offices, 1, 1)
	check(first.ok and repeated.ok and int(repeated.offices.revision) == int(offices.revision) + 2 and var_to_bytes(offices) == before, "Original same-head revision behavior and detached office copy retained")
	var occupied: Dictionary = offices.duplicate(true)
	var seat_found: bool = false
	for seat: Dictionary in occupied.positions:
		if not seat.head:
			seat.holder = 2
			seat_found = true
			break
	check(seat_found and SiteOffices.validate(occupied, "family"), "Duplicate-holder fixture uses original valid office catalog")
	var occupied_before: PackedByteArray = var_to_bytes(occupied)
	var refused: Dictionary = Family.head_offices_candidate(occupied, 2, 1)
	check(not refused.ok and refused.code == "DUPLICATE_HOLDER" and var_to_bytes(occupied) == occupied_before, "Existing non-head holder is refused without mutation")
	var maxed: Dictionary = offices.duplicate(true)
	maxed.revision = SiteOffices.MAX_SEQ
	var capped: Dictionary = Family.head_offices_candidate(maxed, 1, 1)
	check(capped.ok and int(capped.offices.revision) == SiteOffices.MAX_SEQ, "Original revision clamp retained")
	var legacy: Dictionary = offices.duplicate(true)
	legacy.version = 1
	for seat: Dictionary in legacy.positions: seat.erase("office_class")
	var family: Dictionary = {"version": 2, "complete": true, "members": [{"site_id": "site", "person_id": 1, "path": "", "label": "self", "age_years": -1}], "offices": legacy}
	check(Family.validate_family(family, "site"), "Original v1 office record remains valid")
	var legacy_before: PackedByteArray = var_to_bytes(family)
	var read_only: Dictionary = Family.family_offices(family, true)
	var legacy_plan: Dictionary = Family.head_offices_candidate(read_only, 1, 1)
	check(legacy_plan.ok and int(legacy_plan.offices.version) == SiteOffices.VERSION and var_to_bytes(family) == legacy_before, "Original read_only query builds current offices without upgrading the source")
	var migrated: Dictionary = legacy.duplicate(true)
	var upgraded: bool = SiteOffices.upgrade(migrated)
	check(upgraded and Registry.canonical(migrated).ok and var_to_bytes(family) == legacy_before, "Original v1 office producer inserts String office_class keys without changing source fixture")
	check(Registry.canonical(SiteOffices.default_offices("family", 1)).ok, "Original default office producer remains canonical")
	var malformed: Dictionary = Family.head_offices_candidate({"wrong": true}, 1, 1)
	check(not malformed.ok and malformed.code == "INVALID_OFFICES", "Malformed office plan refuses through original schema")
	print("FAMILY_HEAD_EDIT_", "PASS" if failures.is_empty() else "FAILED", " checks=", checks, " failures=", failures)
	quit(0 if failures.is_empty() else 1)
