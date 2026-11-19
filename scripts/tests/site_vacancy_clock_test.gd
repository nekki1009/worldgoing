extends SceneTree
## R5 S9 (pure): the owner's proven political day is the latest stored G0 stamp among affiliated members. Unaffiliated,
## unstamped and malformed packets are ignored; nothing is derived from state. A float day from JSON reads as an integer.

const Clock = preload("res://scripts/terrain_lab/site_vacancy_clock.gd")
const SiteSocial = preload("res://scripts/terrain_lab/site_social.gd")

func _initialize() -> void:
	call_deferred("run")

func _check(condition: bool, message: String) -> bool:
	if not condition:
		push_error(message)
		quit(1)
	return condition

func _packet(owner_ref: Dictionary, proven: Variant, affiliated: bool) -> Dictionary:
	var orgs := {}
	if affiliated: orgs[SiteSocial.org_key(owner_ref)] = {"ref": owner_ref.duplicate(), "G": 0, "L": 6000}
	return {"version": 3, "orgs": orgs, "proven": proven}

func run() -> void:
	var owner := {"kind": "family", "site_id": "site-1", "org_id": "site-1"}
	var other := {"kind": "nation", "site_id": "site-1", "org_id": "n1"}
	if not _check(Clock.owner_proven_day([], owner) == -1, "no members means no proven day"): return
	var five: Dictionary = _packet(owner, {"day": 5, "start": 0, "end": 1440}, true)
	var nine: Dictionary = _packet(owner, {"day": 9, "start": 0, "end": 1440}, true)
	if not _check(Clock.owner_proven_day([five, nine], owner) == 9, "the latest affiliated stamp is the owner's day, not the first"): return
	if not _check(Clock.owner_proven_day([nine, five], owner) == 9, "the owner's day does not depend on member order"): return
	var stranger: Dictionary = _packet(owner, {"day": 20, "start": 0, "end": 1440}, false)
	if not _check(Clock.owner_proven_day([five, stranger], owner) == 5, "an unaffiliated stamp is ignored"): return
	var other_owner: Dictionary = _packet(other, {"day": 30, "start": 0, "end": 1440}, true)
	if not _check(Clock.owner_proven_day([five, other_owner], owner) == 5, "a stamp of another owner is ignored"): return
	var unstamped: Dictionary = _packet(owner, {}, true)
	if not _check(Clock.owner_proven_day([unstamped], owner) == -1, "an affiliated person without a proven stamp gives no day"): return
	if not _check(Clock.owner_proven_day([null, "x", {}], owner) == -1, "malformed packets are ignored"): return
	var floaty: Dictionary = _packet(owner, {"day": 12.0, "start": 0.0, "end": 1440.0}, true)
	if not _check(Clock.owner_proven_day([floaty], owner) == 12 and typeof(Clock.owner_proven_day([floaty], owner)) == TYPE_INT, "a JSON float day reads as an integer"): return
	print("SITE R5 S9 OWNER CLOCK PASS: the owner's proven day is the latest stored G0 stamp among affiliated members; unaffiliated, other-owner, unstamped and malformed packets are ignored; the result is an integer.")
	quit(0)
