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
	if not raw is Dictionary: return false
	# R5 S5F: the winner key is optional (legacy nine-key records load unchanged); when present it is required by the size rule.
	if raw.size() != KEYS.size() + (1 if raw.has("winner") else 0): return false
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
	if raw.has("winner") and (not _whole(raw.winner, 0, 2147483646) or (int(raw.winner) > 0 and not seen.has(int(raw.winner)))): return false
	if str(raw.status) == "closed":
		return raw.has("winner") and int(raw.winner) > 0 and str(raw.cancel_reason) == ""
	if str(raw.status) == "open":
		return (not raw.has("winner") or int(raw.winner) == 0) and str(raw.cancel_reason) == ""
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
	episode["timer"] = advanced.timer
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
	episode["status"] = "cancelled"
	episode["cancel_reason"] = reason
	return {"ok": true, "code": "", "message": "", "episode": episode}

## JSON numbers load as floats; restore exact integers after validation.
static func normalize_numbers(episode: Dictionary) -> void:
	episode["version"] = int(episode.version)
	if episode.has("winner"): episode["winner"] = int(episode.winner)
	Contest.normalize_numbers(episode.timer)
	for index in range(episode.candidates.size()):
		episode.candidates[index] = int(episode.candidates[index])
	for voter: String in episode.ballots:
		episode.ballots[voter] = int(episode.ballots[voter])

static func _fail(code: String, message: String) -> Dictionary:
	return {"ok": false, "code": code, "message": message}

## R5 S3F: the site episode map, keyed by episode id. An absent or empty map is valid (old saves have none).
static func valid_episodes(raw: Variant) -> bool:
	if not raw is Dictionary: return false
	for key: Variant in raw:
		if not key is String or not raw[key] is Dictionary: return false
		if str(raw[key].get("episode_id", "")) != str(key) or not valid_episode(raw[key]): return false
	return true

## JSON numbers load as floats; restore exact integers for every episode in the map.
static func normalize_episodes(raw: Dictionary) -> void:
	for key: String in raw:
		normalize_numbers(raw[key])

## The open episode of one owner, or an empty dictionary.
static func find_open(raw: Dictionary, owner_kind: String, owner_id: String) -> Dictionary:
	for key: String in raw:
		var episode: Dictionary = raw[key]
		if str(episode.owner_kind) == owner_kind and str(episode.owner_id) == owner_id and str(episode.status) == "open": return episode
	return {}

## R5 S5F: the tally of the open episode's ballots per candidate (a candidate with no ballot counts zero).
static func tally(episode: Dictionary) -> Dictionary:
	var counts := {}
	for person: int in episode.candidates: counts[person] = 0
	for voter: String in episode.ballots: counts[int(episode.ballots[voter])] = int(counts[int(episode.ballots[voter])]) + 1
	return counts

## R5 S5F: the contest result at its deadline (plan 489-495). Zero votes or no candidate selects nobody (pending, the
## seat stays vacant). Otherwise the most supporters win; a supporter tie goes to the higher leadership (the caller passes
## leadership by person id, default 0), then to the lower person id (the stable order). Nothing is written here.
static func decide(episode: Variant, leadership: Dictionary = {}) -> Dictionary:
	if not valid_episode(episode): return _fail("CORRUPT_STATE", "空缺紀錄格式非法")
	if str(episode.status) != "open": return _fail("CLOSED", "此空缺已結束")
	if str(episode.timer.status) != "deadline_reached": return _fail("NOT_AT_DEADLINE", "尚未到期")
	if episode.candidates.is_empty(): return _fail("NO_CANDIDATE", "沒有合法候選人；空缺待辦")
	var counts: Dictionary = tally(episode)
	var total := 0
	for person: int in counts: total += int(counts[person])
	if total == 0: return _fail("NO_VOTES", "全零票；空缺待辦，不選首長")
	var best := -1
	for person: int in episode.candidates:
		var candidate := int(person)
		if best < 0: best = candidate
		elif int(counts[candidate]) > int(counts[best]): best = candidate
		elif int(counts[candidate]) == int(counts[best]):
			var lead_c := int(leadership.get(candidate, 0))
			var lead_b := int(leadership.get(best, 0))
			if lead_c > lead_b or (lead_c == lead_b and candidate < best): best = candidate
	return {"ok": true, "code": "", "message": "", "winner": best}

## R5 S5F: close the open episode with its winner, at its deadline, on a candidate only.
static func close(episode: Variant, winner_id: int) -> Dictionary:
	if not valid_episode(episode): return _fail("CORRUPT_STATE", "空缺紀錄格式非法")
	if str(episode.status) != "open": return _fail("CLOSED", "此空缺已結束")
	if str(episode.timer.status) != "deadline_reached": return _fail("NOT_AT_DEADLINE", "尚未到期")
	if winner_id <= 0 or not episode.candidates.has(winner_id): return _fail("NO_TARGET", "得位者須是候選人")
	var closed: Dictionary = episode.duplicate(true)
	closed["status"] = "closed"
	closed["winner"] = winner_id
	return {"ok": true, "code": "", "message": "", "episode": closed}
