extends SceneTree
## R6 bounded regression: departing heirs are invalidated atomically; legacy military heads do not create unsavable nations.
const Family = preload("res://scripts/terrain_lab/site_family_continuity.gd")
const Orders = preload("res://scripts/terrain_lab/site_equipment_orders.gd")

func _initialize() -> void:
	call_deferred("run")

func _check(condition: bool, message: String) -> bool:
	if not condition:
		push_error(message)
		quit(1)
	return condition

func run() -> void:
	var members: Array = []
	for identity: int in [1, 2, 3]:
		members.append({"site_id": "s1", "person_id": identity, "path": "", "label": "original person", "age_years": -1})
	var family: Dictionary = {"version": 5, "name": "", "lineage_id": 1, "complete": true, "members": members, "offices": SiteOffices.default_offices("family", 1, false)}
	var family_seat: String = str(SiteOffices.head_position(family.offices).id)
	family.succession = {"version": 1, "heirs": {family_seat: 2}}
	if not _check(Family.validate_family(family, "s1"), "the family starts with a valid designated heir"): return
	var family_before: PackedByteArray = var_to_bytes(family)
	var family_revision: int = int(family.offices.revision)
	var left_family: Dictionary = Family.departure_candidate(family, "s1", 2, {"kind": "npc_event"}, 1)
	if not _check(bool(left_family.ok), "a designated family heir may leave by its own event"): return
	if not _check(Family.validate_family(left_family.family, "s1") and left_family.family.succession.heirs.is_empty(), "the departing heir reference is removed in a valid family candidate"): return
	if not _check(int(left_family.family.offices.revision) == family_revision + 1 and var_to_bytes(family) == family_before, "the family candidate advances once and preserves the source"): return
	var other_heir_family: Dictionary = family.duplicate(true)
	other_heir_family.succession.heirs[family_seat] = 3
	var other_family_left: Dictionary = Family.departure_candidate(other_heir_family, "s1", 2, {"kind": "npc_event"}, 1)
	if not _check(bool(other_family_left.ok) and int(other_family_left.family.succession.heirs[family_seat]) == 3, "another family heir is preserved"): return

	var known: Dictionary = {1: true, 2: true, 3: true}
	var nation: Dictionary = {"members": [1, 2, 3], "standards": {}, "offices": SiteOffices.default_offices("nation", 1, false)}
	var nation_seat: String = str(SiteOffices.head_position(nation.offices).id)
	nation.succession = {"version": 1, "heirs": {nation_seat: 2}}
	if not _check(Orders.valid_nations({"n1": nation}, {}, known), "the nation starts with a valid designated heir"): return
	var nation_before: PackedByteArray = var_to_bytes(nation)
	var nation_revision: int = int(nation.offices.revision)
	var left_nation: Dictionary = Orders.nation_departure_candidate(nation, 2, {"kind": "npc_event"}, 1)
	if not _check(bool(left_nation.ok), "a designated national heir may leave by its own event"): return
	if not _check(Orders.valid_nations({"n1": left_nation.nation}, {}, known) and left_nation.nation.succession.heirs.is_empty(), "the national candidate removes the obsolete heir and passes the original validator"): return
	if not _check(int(left_nation.nation.offices.revision) == nation_revision + 1 and var_to_bytes(nation) == nation_before, "the national candidate advances once and preserves the source"): return
	var other_heir_nation: Dictionary = nation.duplicate(true)
	other_heir_nation.succession.heirs[nation_seat] = 3
	var other_nation_left: Dictionary = Orders.nation_departure_candidate(other_heir_nation, 2, {"kind": "npc_event"}, 1)
	if not _check(bool(other_nation_left.ok) and int(other_nation_left.nation.succession.heirs[nation_seat]) == 3 and Orders.valid_nations({"n1": other_nation_left.nation}, {}, known), "another national heir is preserved"): return

	var legacy: Dictionary = {"members": [1, 2], "standards": {}, "military_head": 1}
	if not _check(Orders.valid_nations({"n1": legacy}, {}, known), "the legacy nation starts valid"): return
	var legacy_before: PackedByteArray = var_to_bytes(legacy)
	var legacy_head_left: Dictionary = Orders.nation_departure_candidate(legacy, 1, {"kind": "controlled"}, 1)
	if not _check(not bool(legacy_head_left.ok) and str(legacy_head_left.code) == "MIGRATION_REQUIRED" and var_to_bytes(legacy) == legacy_before, "a legacy military head waits for explicit migration without damaging the nation"): return
	var legacy_member_left: Dictionary = Orders.nation_departure_candidate(legacy, 2, {"kind": "npc_event"}, 1)
	if not _check(bool(legacy_member_left.ok) and Orders.valid_nations({"n1": legacy_member_left.nation}, {}, known), "a legacy ordinary member can leave while the original military head remains"): return
	print("SITE R6 DEPARTURE REFERENCE PASS: obsolete heir references cleared atomically; other heirs preserved; legacy head refusal preserves source; ordinary legacy departure stays valid")
	quit(0)
