extends "res://scripts/tests/site_r3_prison_interface_test.gd"
## R5 S1B (pure static): settlement v5 and family v5 heir designation (D-V1, D-F1, D-S1).
## Designation changes only the candidate; refusals leave the source byte-identical; a JSON round trip
## restores exact integers; v4 and older records are never given a succession section.

const Family := preload("res://scripts/terrain_lab/site_family_continuity.gd")
const Succession := preload("res://scripts/terrain_lab/site_succession.gd")

func _alive_all(_identity: int) -> bool:
	return true

func _run() -> void:
	deadline = Time.get_ticks_msec() + 120000
	var head := 101
	var heir := 102
	var outsider := 103
	var faction := 7

	# --- Settlement v4 candidate and designation rules ---
	var settlement: Dictionary = {"version": 4, "owner_faction": faction, "offices": SiteOffices.default_offices("settlement", head, false)}
	var people: Dictionary = {head: {"_housing_faction": faction}, heir: {"_housing_faction": faction}, outsider: {"_housing_faction": 9}}
	var members: Dictionary = {head: true, heir: true}
	var seat_id: String = str(SiteOffices.head_position(settlement.offices).id)
	var settlement_before: PackedByteArray = var_to_bytes(settlement)
	var refused: Dictionary = Settlement.designate_heir_candidate(settlement, heir, heir, members, Callable(self, "_alive_all"))
	if not _r3_check(str(refused.code) == "NO_AUTHORITY" and not bool(refused.ok), "a non-head cannot designate a settlement heir: %s" % str(refused)): return
	if not _r3_check(var_to_bytes(settlement) == settlement_before, "the settlement NO_AUTHORITY refusal leaves the source byte-identical"): return
	var self_heir: Dictionary = Settlement.designate_heir_candidate(settlement, head, head, members, Callable(self, "_alive_all"))
	if not _r3_check(str(self_heir.code) == "DUPLICATE_HOLDER", "the seated head cannot be its own settlement heir: %s" % str(self_heir)): return
	var outsider_heir: Dictionary = Settlement.designate_heir_candidate(settlement, head, outsider, members, Callable(self, "_alive_all"))
	if not _r3_check(str(outsider_heir.code) == "NO_TARGET", "a person outside the member set is refused: %s" % str(outsider_heir)): return
	var designated: Dictionary = Settlement.designate_heir_candidate(settlement, head, heir, members, Callable(self, "_alive_all"))
	if not _r3_check(bool(designated.ok), "the settlement head designates a living member: %s" % str(designated)): return
	var candidate: Dictionary = designated.settlement
	if not _r3_check(int(candidate.version) == 5, "a designation upgrades the settlement to v5"): return
	if not _r3_check(int(candidate.succession.heirs[seat_id]) == heir, "the settlement heir is stored on the head seat"): return
	if not _r3_check(int(candidate.offices.revision) == int(settlement.offices.revision) + 1, "one settlement offices revision step"): return
	if not _r3_check(var_to_bytes(settlement) == settlement_before, "the source settlement is untouched by designation"): return
	if not _r3_check(Settlement.valid_succession(candidate, people), "the designated v5 settlement validates against its owner faction"): return
	# The heir must be a person of the owner faction; an outsider cannot be stored as heir.
	var bad_people: Dictionary = {head: {"_housing_faction": faction}, heir: {"_housing_faction": 9}}
	if not _r3_check(not Settlement.valid_succession(candidate, bad_people), "an heir from another faction fails validation"): return
	# A v4 record must never carry a succession section.
	var v4_with_heir: Dictionary = settlement.duplicate(true)
	v4_with_heir["succession"] = candidate.succession.duplicate(true)
	if not _r3_check(not Settlement.valid_succession(v4_with_heir, people), "a v4 settlement with a succession section is refused"): return
	if not _r3_check(Settlement.valid_succession(settlement, people), "a v4 settlement without a succession section is valid"): return

	# --- Setter version rule (D-V1) ---
	if not _r3_check(Settlement.setter_version(4) == 4, "the v4 setter keeps version 4"): return
	if not _r3_check(Settlement.setter_version(5) == 5, "the setter keeps a v5 record at version 5"): return
	if not _r3_check(Settlement.setter_version(1) == 4, "the setter writes at least the v4 ceiling"): return

	# --- JSON round trip: floats restored to exact integers, then valid ---
	var parsed: Variant = JSON.parse_string(JSON.stringify(candidate))
	if not _r3_check(parsed is Dictionary, "the designated settlement survives a JSON round trip"): return
	Succession.normalize_numbers(parsed.succession)
	if not _r3_check(Succession.valid_record(parsed.succession, [seat_id], members), "the round-tripped succession validates after normalize"): return
	if not _r3_check(int(parsed.succession.heirs[seat_id]) == heir, "the round-tripped heir is an exact integer"): return

	# --- Family v4 candidate and designation rules (D-F1) ---
	var family: Dictionary = {
		"version": 4, "name": "", "lineage_id": 1, "complete": true,
		"members": [{"site_id": "s1", "person_id": head}, {"site_id": "s1", "person_id": heir}],
		"offices": SiteOffices.default_offices("family", head, false),
	}
	var family_before: PackedByteArray = var_to_bytes(family)
	var family_refused: Dictionary = Family.designate_heir_candidate(family, "s1", heir, heir, Callable(self, "_alive_all"))
	if not _r3_check(str(family_refused.code) == "NO_AUTHORITY", "a non-head cannot designate a family heir: %s" % str(family_refused)): return
	if not _r3_check(var_to_bytes(family) == family_before, "the family NO_AUTHORITY refusal leaves the source byte-identical"): return
	var family_designated: Dictionary = Family.designate_heir_candidate(family, "s1", head, heir, Callable(self, "_alive_all"))
	if not _r3_check(bool(family_designated.ok), "the family head designates a local member: %s" % str(family_designated)): return
	var family_candidate: Dictionary = family_designated.family
	if not _r3_check(int(family_candidate.version) == 5, "a family designation upgrades the family to v5"): return
	if not _r3_check(var_to_bytes(family) == family_before, "the source family is untouched by designation"): return
	if not _r3_check(Family.valid_succession(family_candidate, "s1"), "the designated family validates for its own site"): return
	if not _r3_check(not Family.valid_succession(family_candidate, "s2"), "a family heir is not valid for another site"): return
	var family_v3: Dictionary = family.duplicate(true)
	family_v3.version = 3
	var v3_refused: Dictionary = Family.designate_heir_candidate(family_v3, "s1", head, heir, Callable(self, "_alive_all"))
	if not _r3_check(str(v3_refused.code) == "NO_TARGET", "a v3 family cannot take a succession section: %s" % str(v3_refused)): return

	print("SITE R5 S1B PASS: settlement and family v5 designation accept a living member on the head seat, refuse non-head, self-heir and outsider with byte-identical sources, validate the owner faction or local site, keep v4 and older records without a succession section, and survive a JSON round trip with exact integers.")
	quit(0)
