extends SceneTree
## R6 S1 (pure): the family departure candidate. A controlled person leaves only by a controlled act and an NPC only by an
## NPC event; the source is never written; a vacated head is reported; a family keeps at least one member; the history
## validator is strict. Deterministic: no lab, no clock.

const Family = preload("res://scripts/terrain_lab/site_family_continuity.gd")

func _initialize() -> void:
	call_deferred("run")

func _check(condition: bool, message: String) -> bool:
	if not condition:
		push_error(message)
		quit(1)
	return condition

func _family(site_id: String, head: int, others: Array) -> Dictionary:
	var members: Array = []
	for identity: int in [head] + others:
		members.append({"site_id": site_id, "person_id": identity, "path": "", "label": "pure #%d" % identity, "age_years": -1})
	return {"version": 4, "name": "", "lineage_id": 1, "complete": true, "members": members, "offices": SiteOffices.default_offices("family", head, false)}

func run() -> void:
	var site_id := "site-1"
	var family: Dictionary = _family(site_id, 1, [2, 3])
	var before: PackedByteArray = var_to_bytes(family)
	if not _check(str(Family.departure_candidate(family, site_id, 9, {"kind": "npc_event"}, 1).code) == "NO_TARGET", "a non-member cannot leave"): return
	if not _check(str(Family.departure_candidate(family, site_id, 1, {"kind": "npc_event"}, 1).code) == "NO_AUTHORITY", "the controlled person cannot leave by an NPC event"): return
	if not _check(str(Family.departure_candidate(family, site_id, 2, {"kind": "controlled"}, 1).code) == "NO_AUTHORITY", "an NPC cannot leave by a controlled act"): return
	if not _check(str(Family.departure_candidate(family, site_id, 2, "npc_event", 1).code) == "NO_AUTHORITY", "a bare string is not departure authority"): return
	if not _check(var_to_bytes(family) == before, "refusals leave the source byte-identical"): return

	var npc_left: Dictionary = Family.departure_candidate(family, site_id, 2, {"kind": "npc_event"}, 1)
	if not _check(bool(npc_left.ok) and not bool(npc_left.seat_vacated), "an NPC leaves by its event"): return
	var kept: Array = []
	for member: Dictionary in npc_left.family.members: kept.append(int(member.person_id))
	if not _check(kept == [1, 3], "only the leaving NPC is removed"): return
	if not _check(var_to_bytes(family) == before, "the source is not written by the candidate"): return

	var head_left: Dictionary = Family.departure_candidate(family, site_id, 1, {"kind": "controlled"}, 1)
	if not _check(bool(head_left.ok) and bool(head_left.seat_vacated) and int(SiteOffices.head_position(head_left.family.offices).holder) == -1, "the controlled head leaves and vacates the head seat"): return

	var lone: Dictionary = _family(site_id, 1, [])
	if not _check(str(Family.departure_candidate(lone, site_id, 1, {"kind": "controlled"}, 1).code) == "NO_TARGET", "a family keeps at least one member"): return

	var entry := {"person_id": 2, "minute": 1440, "authority": "npc_event", "seat_vacated": false}
	if not _check(Family.valid_departures([entry]) and Family.valid_departures([]), "a well-formed history is valid; an empty history is valid"): return
	if not _check(not Family.valid_departures([{"person_id": 2, "minute": 1440, "authority": "other", "seat_vacated": false}]), "an unknown authority kind is refused"): return
	if not _check(not Family.valid_departures([{"person_id": 2.5, "minute": 1440, "authority": "npc_event", "seat_vacated": false}]), "a fractional person id is refused"): return
	if not _check(not Family.valid_departures([{"person_id": 2, "minute": 1440, "authority": "npc_event"}]), "a missing key is refused"): return
	if not _check(not Family.valid_departures("x"), "a non-array history is refused"): return

	print("SITE R6 S1 FAMILY DEPARTURE PURE PASS: the candidate enforces controlled-only and NPC-event-only departure, refuses non-members, bare strings and a lone member, reports a vacated head, never writes the source, and the history validator is strict.")
	quit(0)
