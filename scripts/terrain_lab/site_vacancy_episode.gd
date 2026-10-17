extends RefCounted
## R5 S3E (pure data, validator and JSON normalize): the vacancy episode record. One episode per vacant owner seat.
## The only clock is the S4 contest timer driven by G0 proven political days. Candidates and ballots are recorded
## while the episode is open. A legitimate appointment or the heir's return (D7) cancels it and keeps the record;
## a cancelled episode never changes again. Closing and the winner's seating are later slices (S4 full, S5).

const Contest := preload("res://scripts/terrain_lab/site_succession_contest.gd")

const VERSION := 1
const OWNER_KINDS := ["settlement", "family", "nation"]
const CANCEL_REASONS := ["appointment", "heir_return"]
const MAX_CANDIDATES := 16
const MAX_BALLOTS := 4096
const KEYS := ["version", "owner_kind", "owner_id", "episode_id", "status", "timer", "candidates", "ballots", "cancel_reason"]

## `onset_day`: the political day the vacancy began (the S4 timer counts only later proven days).
static func empty_episode(owner_kind: String, owner_id: String, episode_id: String, onset_day: int) -> Dictionary:
	return {"version": VERSION, "owner_kind": owner_kind, "owner_id": owner_id, "episode_id": episode_id,
		"status": "open", "timer": Contest.empty_timer(onset_day), "candidates": [], "ballots": {}, "cancel_reason": ""}

static func _whole(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value)) \
		and float(value) >= float(low) and float(value) <= float(high)

static func _text(value: Variant, limit: int) -> bool:
	return value is String and not str(value).is_empty() and str(value).length() <= limit

## Strict shape: exactly the nine keys; known owner kind; open or cancelled with a matching reason; a valid S4 timer;
## unique positive candidates; ballots keyed by a positive voter id (string, as JSON stores keys) for a candidate.
static func valid_episode(raw: Variant) -> bool:
	if not raw is Dictionary or raw.size() != KEYS.size(): return false
	for key: String in KEYS:
		if not raw.has(key): return false
	if not _whole(raw.version, VERSION, VERSION): return false
	if not raw.owner_kind is String or not OWNER_KINDS.has(str(raw.owner_kind)): return false
	if not _text(raw.owner_id, 96) or not _text(raw.episode_id, 96): return false
	if not Contest.valid_timer(raw.timer): return false
	if not raw.candidates is Array or raw.candidates.size() > MAX_CANDIDATES: return false
	var seen := {}
	for person: Variant in raw.candidates:
		if not _whole(person, 1, 2147483646) or seen.has(int(person)): return false
		seen[int(person)] = true
	if not raw.ballots is Dictionary or raw.ballots.size() > MAX_BALLOTS: return false
	for voter: Variant in raw.ballots:
		if not voter is String or not str(voter).is_valid_int() or int(str(voter)) <= 0: return false
		if not _whole(raw.ballots[voter], 1, 2147483646) or not seen.has(int(raw.ballots[voter])): return false
	if not raw.status is String: return false
	if str(raw.status) == "open":
		return str(raw.cancel_reason) == ""
	if str(raw.status) == "cancelled":
		return CANCEL_REASONS.has(str(raw.cancel_reason))
	return false

static func _refuse_if_closed(raw: Dictionary) -> Dictionary:
	if str(raw.status) != "open": return _fail("CLOSED", "此空缺已結束；紀錄保留不變")
	return {"ok": true, "code": "", "message": ""}

## G0 proven political day: advances the S4 timer only while the episode is open.
static func tick(raw: Variant, proven_day: int) -> Dictionary:
	if not valid_episode(raw): return _fail("CORRUPT_STATE", "空缺紀錄格式非法")
	var open := _refuse_if_closed(raw)
	if not open.ok: return open
	var advanced: Dictionary = Contest.tick(raw.timer, proven_day)
	if not advanced.ok: return advanced
	var episode: Dictionary = raw.duplicate(true)
	episode.timer = advanced.timer
	return {"ok": true, "code": "", "message": "", "episode": episode}

static func add_candidate(raw: Variant, person_id: int) -> Dictionary:
	if not valid_episode(raw): return _fail("CORRUPT_STATE", "空缺紀錄格式非法")
	var open := _refuse_if_closed(raw)
	if not open.ok: return open
	if person_id <= 0: return _fail("NO_TARGET", "候選人須是真實人物")
	if raw.candidates.has(person_id): return _fail("DUPLICATE_CANDIDATE", "此人已是候選人")
	if raw.candidates.size() >= MAX_CANDIDATES: return _fail("FULL", "候選人已達上限")
	var episode: Dictionary = raw.duplicate(true)
	episode.candidates.append(person_id)
	return {"ok": true, "code": "", "message": "", "episode": episode}

## One ballot per voter. A recast is refused (ALREADY_CAST) and the record is left unchanged.
static func cast(raw: Variant, voter_id: int, candidate_id: int) -> Dictionary:
	if not valid_episode(raw): return _fail("CORRUPT_STATE", "空缺紀錄格式非法")
	var open := _refuse_if_closed(raw)
	if not open.ok: return open
	if voter_id <= 0 or not raw.candidates.has(candidate_id): return _fail("NO_TARGET", "投票須投給登記的候選人")
	if raw.ballots.has(str(voter_id)): return _fail("ALREADY_CAST", "每人只能投一票")
	var episode: Dictionary = raw.duplicate(true)
	episode.ballots[str(voter_id)] = candidate_id
	return {"ok": true, "code": "", "message": "", "episode": episode}

## D7: a legitimate appointment or the heir's return cancels the episode and keeps the record (no overwrite).
static func cancel(raw: Variant, reason: String) -> Dictionary:
	if not valid_episode(raw): return _fail("CORRUPT_STATE", "空缺紀錄格式非法")
	var open := _refuse_if_closed(raw)
	if not open.ok: return open
	if not CANCEL_REASONS.has(reason): return _fail("NO_AUTHORITY", "取消的理由須是合法任命或繼承人歸來")
	var episode: Dictionary = raw.duplicate(true)
	episode.status = "cancelled"
	episode.cancel_reason = reason
	return {"ok": true, "code": "", "message": "", "episode": episode}

## JSON numbers load as floats; restore exact integers after validation.
static func normalize_numbers(episode: Dictionary) -> void:
	episode.version = int(episode.version)
	Contest.normalize_numbers(episode.timer)
	for index in range(episode.candidates.size()):
		episode.candidates[index] = int(episode.candidates[index])
	for voter: String in episode.ballots:
		episode.ballots[voter] = int(episode.ballots[voter])

static func _fail(code: String, message: String) -> Dictionary:
	return {"ok": false, "code": code, "message": message}
