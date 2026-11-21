class_name RegionBattleLog
extends RefCounted
## Battle log and personal combat records (Nekki 2026-11-05: "2 想要更詳細點，還要記錄個人戰績" → 可以).
## Pure helpers. The log lives in the faction registry's optional `battles` table (RegionSaveSlot owns publication):
##   {version, next_id, records [battle], pair_last {pair key: end time}}
## battle: {id, site_id, started_at, ended_at, sides {faction: side}, routed_teams [team id], winner (faction or -1)}
## side: {faction, commander_ref, people, deaths, kos, captured}
## The newest MAX_RECORDS battles are kept; pair_last keeps every pair's last fight for diplomacy (§11.6 "no fighting for
## D days"). Personal records live on each person's social_state (PersonSocial.combat_record).
const VERSION := 1
const MAX_RECORDS := 200
## A battle ends when nobody in the Site has clashed for this many game seconds.
const QUIET_SECONDS := 60.0
const RECORD_FIELDS := ["battles", "wins", "losses", "routs", "kills", "kos_dealt", "captures", "nobles_captured", "captured", "kod", "commanded"]
const SIDE_FIELDS := ["faction", "commander_ref", "people", "deaths", "kos", "captured"]

static func fail(code: String, message: String = "") -> Dictionary:
	return {"ok": false, "code": code, "message": message}

static func empty() -> Dictionary:
	return {"version": VERSION, "next_id": 1, "records": [], "pair_last": {}}

static func table(registry: Dictionary) -> Dictionary:
	var value: Variant = registry.get("battles")
	return value if value is Dictionary else empty()

static func empty_record() -> Dictionary:
	var record := {}
	for field: String in RECORD_FIELDS: record[field] = 0
	return record

## The last time two factions fought (end of their latest shared battle), or -1 when no fight is recorded.
static func last_fight(registry: Dictionary, a: int, b: int) -> float:
	return float(table(registry).pair_last.get(RegionDiplomacy.pair_key(a, b), -1.0))

## A finished battle (built by the Site tracker) joins the log. Every pair of hostile sides in it gets its end time.
static func add(registry: Dictionary, battle: Dictionary, now: float) -> Dictionary:
	if not valid_battle(battle): return fail("INVALID", "戰役紀錄格式錯誤")
	var candidate: Dictionary = registry.duplicate(true)
	var log := table(registry).duplicate(true)
	var record: Dictionary = battle.duplicate(true)
	record.id = int(log.next_id)
	log.next_id = int(log.next_id) + 1
	log.records.append(record)
	while log.records.size() > MAX_RECORDS: log.records.pop_front()
	var factions: Array = record.sides.keys()
	for x in range(factions.size()):
		for y in range(x + 1, factions.size()):
			log.pair_last[RegionDiplomacy.pair_key(int(factions[x]), int(factions[y]))] = float(record.ended_at)
	candidate.battles = log
	candidate.revision = int(candidate.get("revision", 0)) + 1
	var checked: Dictionary = RegionFactionQuery.validate(candidate, now)
	if not checked.ok: return checked
	return {"ok": true, "registry": candidate, "battle_id": int(record.id)}

static func valid_battle(value: Variant) -> bool:
	if not value is Dictionary or not RegionFactionQuery.keys(value, ["id", "site_id", "started_at", "ended_at", "sides", "routed_teams", "winner"]): return false
	if not value.site_id is String or not (value.started_at is float or value.started_at is int) or not (value.ended_at is float or value.ended_at is int) or float(value.ended_at) < float(value.started_at): return false
	if not value.sides is Dictionary or not value.routed_teams is Array or not RegionFactionQuery.whole(value.winner, -1, RegionFactionQuery.MAX_ID): return false
	for key: Variant in value.sides:
		var side: Variant = value.sides[key]
		if not side is Dictionary or not RegionFactionQuery.keys(side, SIDE_FIELDS) or str(int(side.faction)) != str(key): return false
		for field: String in ["people", "deaths", "kos", "captured"]:
			if not RegionFactionQuery.whole(side[field], 0, 1000000): return false
	return true

static func validate(value: Variant, now: float) -> Dictionary:
	if not value is Dictionary or not RegionFactionQuery.keys(value, ["version", "next_id", "records", "pair_last"]): return fail("CORRUPT_SAVE", "battle log fields")
	if not RegionFactionQuery.whole(value.version, VERSION, VERSION) or not RegionFactionQuery.whole(value.next_id, 1, RegionFactionQuery.MAX_REVISION) or not value.records is Array or not value.pair_last is Dictionary: return fail("CORRUPT_SAVE", "battle log tables")
	if value.records.size() > MAX_RECORDS: return fail("CORRUPT_SAVE", "battle log size")
	for record: Variant in value.records:
		if not valid_battle(record) or int(record.id) >= int(value.next_id) or float(record.ended_at) > now: return fail("CORRUPT_SAVE", "battle record")
	for key: Variant in value.pair_last:
		if not key is String or not (value.pair_last[key] is float or value.pair_last[key] is int) or float(value.pair_last[key]) > now: return fail("CORRUPT_SAVE", "battle pair time")
	return {"ok": true}

static func canonical(value: Dictionary) -> Dictionary:
	var result: Dictionary = value.duplicate(true)
	result.version = int(result.get("version", VERSION))
	result.next_id = int(result.get("next_id", 1))
	for record: Dictionary in result.get("records", []):
		record.id = int(record.id)
		record.winner = int(record.winner)
		record.started_at = float(record.started_at)
		record.ended_at = float(record.ended_at)
		var routed: Array = []
		for team: Variant in record.routed_teams: routed.append(int(team))
		record.routed_teams = routed
		for side: Dictionary in record.sides.values():
			for field: String in ["faction", "people", "deaths", "kos", "captured"]: side[field] = int(side[field])
			if side.commander_ref is Dictionary: side.commander_ref = RegionPeerage.canonical_ref(side.commander_ref)
	for key: String in result.get("pair_last", {}): result.pair_last[key] = float(result.pair_last[key])
	return result

## The winning faction: the only side with no team routed and someone still standing; -1 for a draw or no decision.
static func winner_of(sides: Dictionary, routed_factions: Dictionary, standing: Dictionary) -> int:
	var unbroken: Array = []
	for faction: Variant in sides:
		if not routed_factions.has(int(faction)) and int(standing.get(int(faction), 0)) > 0: unbroken.append(int(faction))
	return int(unbroken[0]) if unbroken.size() == 1 else -1

## Personal record helpers (the record dictionary lives in PersonSocial).
static func add_to(record: Dictionary, field: String, amount: int = 1) -> Dictionary:
	var result: Dictionary = empty_record()
	for key: String in RECORD_FIELDS: result[key] = int(record.get(key, 0))
	if result.has(field): result[field] = maxi(0, int(result[field]) + amount)
	return result
