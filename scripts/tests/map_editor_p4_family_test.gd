extends SceneTree
## P4 S4: the pure authoring plan for a family roster (FamilyContinuity.roster_plan).
## Other-Site members are read-only, local members who hold an office are never dropped
## silently, and a refused plan changes nothing. No editor UI here (see NOTES.md).

const FamilyContinuity = preload("res://scripts/terrain_lab/site_family_continuity.gd")

const SITE := "p4s4_site"
const OTHER := "p4s4_other"

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> bool:
	if condition: return true
	push_error("MAP_EDITOR_P4_FAMILY_FAIL: " + message)
	quit(1)
	return false

func _m(site_id: String, identity: int, label: String) -> Dictionary:
	return {"site_id": site_id, "person_id": identity, "path": "", "label": label, "age_years": -1}

func _family(holder: int) -> Dictionary:
	# Version 2: roster plus offices; the head holder is a local member.
	return {"version": 2, "complete": true,
		"members": [_m(SITE, 1, "本人"), _m(SITE, 2, "兄"), _m(OTHER, 5, "遠地堂弟")],
		"offices": SiteOffices.default_offices("family", holder, false)}

func _run() -> void:
	create_timer(30.0).timeout.connect(func() -> void: push_error("MAP_EDITOR_P4_FAMILY_TIMEOUT"); quit(1))
	var base: Dictionary = _family(1)
	var base_before: Dictionary = base.duplicate(true)
	if not _check(FamilyContinuity.validate_family(base, SITE), "base family validates"): return

	# Keep everything and add a local member: candidate has four members and validates.
	var added: Dictionary = FamilyContinuity.roster_plan(base, SITE, [_m(SITE, 1, "本人"), _m(SITE, 2, "兄"), _m(OTHER, 5, "遠地堂弟"), _m(SITE, 3, "侄")])
	if not _check(added.ok and added.family.members.size() == 4, "local member added: " + str(added)): return
	if not _check(FamilyContinuity.validate_family(added.family, SITE), "candidate validates"): return

	# A foreign member cannot be added from this roster.
	var foreign_add: Dictionary = FamilyContinuity.roster_plan(base, SITE, [_m(SITE, 1, "本人"), _m(SITE, 2, "兄"), _m(OTHER, 5, "遠地堂弟"), _m(OTHER, 6, "外人")])
	if not _check(not foreign_add.ok and foreign_add.code == "FOREIGN_MEMBER", "foreign member add refused"): return

	# A foreign member already in the roster must be kept exactly.
	var foreign_drop: Dictionary = FamilyContinuity.roster_plan(base, SITE, [_m(SITE, 1, "本人"), _m(SITE, 2, "兄")])
	if not _check(not foreign_drop.ok and foreign_drop.code == "FOREIGN_READ_ONLY", "foreign member cannot be dropped"): return

	# The head holds a seat: dropping the head is refused and names the seat.
	var head_drop: Dictionary = FamilyContinuity.roster_plan(base, SITE, [_m(SITE, 2, "兄"), _m(OTHER, 5, "遠地堂弟")])
	if not _check(not head_drop.ok and head_drop.code == "HOLDS_OFFICE" and head_drop.references.size() == 1, "office holder drop refused with references"): return

	# A local member without a seat can be dropped.
	var seatless: Dictionary = FamilyContinuity.roster_plan(base, SITE, [_m(SITE, 1, "本人"), _m(OTHER, 5, "遠地堂弟")])
	if not _check(seatless.ok and seatless.family.members.size() == 2, "seatless local member dropped"): return

	# Duplicates and malformed references are refused.
	var duplicate: Dictionary = FamilyContinuity.roster_plan(base, SITE, [_m(SITE, 1, "本人"), _m(SITE, 1, "本人"), _m(OTHER, 5, "遠地堂弟")])
	if not _check(not duplicate.ok and duplicate.code == "DUPLICATE_MEMBER", "duplicate member refused"): return
	var short_reference := {"site_id": SITE, "person_id": 3}
	var malformed: Dictionary = FamilyContinuity.roster_plan(base, SITE, [_m(SITE, 1, "本人"), short_reference, _m(OTHER, 5, "遠地堂弟")])
	if not _check(not malformed.ok and malformed.code == "INVALID_MEMBER", "incomplete member reference refused"): return

	# Version 4 keeps its display name and lineage id through a roster plan.
	var named: Dictionary = _family(1)
	named.version = 4
	named.name = "甲族"
	named.lineage_id = 7
	var renamed_plan: Dictionary = FamilyContinuity.roster_plan(named, SITE, [_m(SITE, 1, "本人"), _m(SITE, 2, "兄"), _m(OTHER, 5, "遠地堂弟")])
	if not _check(renamed_plan.ok and int(renamed_plan.family.version) == 4 and renamed_plan.family.name == "甲族" and int(renamed_plan.family.lineage_id) == 7, "version 4 identity kept"): return

	# No refused or accepted plan changes the input family.
	if not _check(base == base_before, "input family unchanged by every plan"): return

	print("MAP_EDITOR_P4_FAMILY_PASS: local add, foreign read-only, office holder refusal with references, duplicates, malformed refs, version 4 identity kept")
	quit(0)
