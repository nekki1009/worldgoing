extends RefCounted
## One Site's open battle (Nekki 2026-11-05 battle log and personal records). A battle opens when the Site's combat mark
## turns on and closes once it has been off (no clash anywhere) for RegionBattleLog.QUIET_SECONDS of game time.
## Participants are the people seen fighting, plus every victim, striker and captor of a DEATH / KO / CAPTURED event.
## Pure bookkeeping: CrowdSite feeds it, SiteController turns the closed battle into the log entry and personal records.
const BattleLog = preload("res://scripts/region_lab/region_battle_log.gd")

var open := false
var site_id := ""
var started_at := 0.0
var quiet_since := -1.0
var participants := {} # person id -> faction
var deaths := {} # faction -> count
var kos := {}
var captured := {}
var routed_teams := {} # team id -> faction
## Personal deltas: person id -> {field: amount}
var deltas := {}

func _add(person: int, field: String, amount: int = 1) -> void:
	if person <= 0: return
	var row: Dictionary = deltas.get(person, {})
	row[field] = int(row.get(field, 0)) + amount
	deltas[person] = row

func begin(site: String, now: float) -> void:
	open = true
	site_id = site
	started_at = now
	quiet_since = -1.0
	participants = {}
	deaths = {}
	kos = {}
	captured = {}
	routed_teams = {}
	deltas = {}

func join(person: int, faction: int) -> void:
	if open and person > 0 and faction >= 0: participants[person] = faction

## kind: 0 DEATH, 1 KO, 4 CAPTURED. `striker` is the native last striker (DEATH / KO), `captor` the event's other (CAPTURED).
func on_event(kind: int, victim: int, victim_faction: int, striker: int, striker_faction: int, captor: int, captor_faction: int, victim_titled: bool) -> void:
	if not open: return
	join(victim, victim_faction)
	match kind:
		0:
			deaths[victim_faction] = int(deaths.get(victim_faction, 0)) + 1
			if striker > 0 and striker != victim:
				join(striker, striker_faction)
				_add(striker, "kills")
		1:
			kos[victim_faction] = int(kos.get(victim_faction, 0)) + 1
			_add(victim, "kod")
			if striker > 0 and striker != victim:
				join(striker, striker_faction)
				_add(striker, "kos_dealt")
		4:
			captured[victim_faction] = int(captured.get(victim_faction, 0)) + 1
			_add(victim, "captured")
			if captor > 0:
				join(captor, captor_faction)
				_add(captor, "captures")
				if victim_titled: _add(captor, "nobles_captured")

func on_rout(team_id: int, faction: int, members: Array) -> void:
	if not open: return
	routed_teams[team_id] = faction
	for person: Variant in members: _add(int(person), "routs")

## Advance with the Site combat mark; returns true when the battle should close now.
func tick(combat_on: bool, now: float) -> bool:
	if not open: return false
	if combat_on:
		quiet_since = -1.0
		return false
	if quiet_since < 0.0: quiet_since = now
	return now - quiet_since >= BattleLog.QUIET_SECONDS

## Builds the log entry and the final personal deltas. `standing` = faction -> people still able to fight; `commanders` =
## faction -> {ref, person}. A battle with fewer than two factions is no battle (returns {}).
func close(now: float, standing: Dictionary, commanders: Dictionary) -> Dictionary:
	open = false
	var people := {}
	for person: Variant in participants: people[int(participants[person])] = int(people.get(int(participants[person]), 0)) + 1
	if people.size() < 2: return {}
	var sides := {}
	for faction: Variant in people:
		var command: Dictionary = commanders.get(int(faction), {})
		sides[str(int(faction))] = {"faction": int(faction), "commander_ref": command.get("ref"), "people": int(people[faction]),
			"deaths": int(deaths.get(int(faction), 0)), "kos": int(kos.get(int(faction), 0)), "captured": int(captured.get(int(faction), 0))}
	var routed_factions := {}
	for team: Variant in routed_teams: routed_factions[int(routed_teams[team])] = true
	var winner := BattleLog.winner_of(people, routed_factions, standing)
	for person: Variant in participants:
		var faction := int(participants[person])
		_add(int(person), "battles")
		if winner >= 0: _add(int(person), "wins" if faction == winner else "losses")
	for faction: Variant in commanders:
		var person := int(commanders[faction].get("person", -1))
		if person > 0 and people.has(int(faction)): _add(person, "commanded")
	var routed: Array = []
	for team: Variant in routed_teams: routed.append(int(team))
	routed.sort()
	return {"battle": {"id": 0, "site_id": site_id, "started_at": started_at, "ended_at": now, "sides": sides, "routed_teams": routed, "winner": winner},
		"deltas": deltas.duplicate(true)}
