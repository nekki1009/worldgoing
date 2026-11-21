extends SceneTree
## R5 S3E (pure): the vacancy episode record. Candidates and ballots are recorded only while open; one ballot per
## voter; a legitimate appointment or heir return cancels it (D7) and keeps the record; a closed episode never changes.
## The clock is the S4 timer on G0 proven days. JSON round trip keeps the ids as integers.

const Episode = preload("res://scripts/terrain_lab/site_vacancy_episode.gd")

func _initialize() -> void:
	call_deferred("run")

func _check(condition: bool, message: String) -> bool:
	if not condition:
		push_error(message)
		quit(1)
	return condition

func run() -> void:
	var episode: Dictionary = Episode.empty_episode("settlement", "site-1", "ep-1", 10)
	if not _check(Episode.valid_episode(episode) and str(episode.status) == "open", "a new episode is valid and open"): return
	var bad_owner: Dictionary = episode.duplicate(true)
	bad_owner.owner_kind = "village"
	if not _check(not Episode.valid_episode(bad_owner), "an unknown owner kind is refused"): return

	# The S4 clock: one proven day after the onset opens the contest; the episode stays open.
	var ticked: Dictionary = Episode.tick(episode, 11)
	if not _check(bool(ticked.ok) and str(ticked.episode.timer.status) == "open" and str(ticked.episode.status) == "open", "one proven day opens the contest inside the episode"): return
	episode = ticked.episode

	# Candidates: unique positive people; a duplicate is refused and the record is unchanged.
	var with_21: Dictionary = Episode.add_candidate(episode, 21)
	var with_22: Dictionary = Episode.add_candidate(with_21.episode, 22)
	if not _check(bool(with_22.ok) and with_22.episode.candidates == [21, 22], "two candidates are recorded"): return
	episode = with_22.episode
	var before_dup: PackedByteArray = var_to_bytes(episode)
	var dup: Dictionary = Episode.add_candidate(episode, 21)
	if not _check(str(dup.code) == "DUPLICATE_CANDIDATE" and var_to_bytes(episode) == before_dup, "a duplicate candidate is refused and the record is unchanged"): return
	if not _check(str(Episode.add_candidate(episode, 0).code) == "NO_TARGET", "a non-person candidate is refused"): return

	# Ballots: one per voter; a recast and a non-candidate are refused with the record unchanged.
	var voted: Dictionary = Episode.cast(episode, 31, 21)
	if not _check(bool(voted.ok), "a voter casts a ballot for a candidate"): return
	episode = voted.episode
	var before_recast: PackedByteArray = var_to_bytes(episode)
	var recast: Dictionary = Episode.cast(episode, 31, 22)
	if not _check(str(recast.code) == "ALREADY_CAST" and var_to_bytes(episode) == before_recast, "a second ballot from the same voter is refused and unchanged"): return
	if not _check(str(Episode.cast(episode, 32, 99).code) == "NO_TARGET", "a ballot for a non-candidate is refused"): return

	# A legitimate appointment cancels the episode (D7); the record is kept and a closed episode never changes.
	var appointed: Dictionary = Episode.cancel(episode, "appointment")
	if not _check(bool(appointed.ok) and str(appointed.episode.status) == "cancelled" and appointed.episode.ballots.has("31"), "a legitimate appointment cancels the episode and keeps its ballots"): return
	var closed_before: PackedByteArray = var_to_bytes(appointed.episode)
	if not _check(str(Episode.tick(appointed.episode, 13).code) == "CLOSED" and str(Episode.add_candidate(appointed.episode, 23).code) == "CLOSED" and str(Episode.cast(appointed.episode, 33, 21).code) == "CLOSED", "a cancelled episode refuses tick, candidates and ballots"): return
	if not _check(str(Episode.cancel(appointed.episode, "heir_return").code) == "CLOSED" and var_to_bytes(appointed.episode) == closed_before, "a cancelled episode is never cancelled again and does not change"): return

	# Heir return also cancels; an unknown reason is refused on an open episode.
	var open_again: Dictionary = Episode.empty_episode("family", "site-1", "ep-2", 10)
	if not _check(str(Episode.cancel(open_again, "other").code) == "NO_AUTHORITY", "an unknown cancel reason is refused"): return
	var returned: Dictionary = Episode.cancel(open_again, "heir_return")
	if not _check(bool(returned.ok) and str(returned.episode.cancel_reason) == "heir_return", "an heir's return cancels the episode"): return

	# JSON round trip: ids and counters come back as integers and the record validates.
	var parsed: Variant = JSON.parse_string(JSON.stringify(appointed.episode))
	if not _check(parsed is Dictionary, "the cancelled episode survives a JSON round trip"): return
	Episode.normalize_numbers(parsed)
	if not _check(Episode.valid_episode(parsed) and str(parsed.status) == "cancelled", "the round-tripped episode validates as cancelled"): return
	if not _check(typeof(parsed.candidates[0]) == TYPE_INT and int(parsed.candidates[0]) == 21, "a candidate id is an integer after the round trip"): return
	if not _check(typeof(parsed.ballots["31"]) == TYPE_INT and int(parsed.ballots["31"]) == 21, "a ballot value is an integer after the round trip"): return

	# Corrupt shapes are refused: a ballot for a non-candidate and an extra field.
	var stray: Dictionary = appointed.episode.duplicate(true)
	stray.ballots["40"] = 99
	if not _check(not Episode.valid_episode(stray), "a ballot for a non-candidate is refused by the validator"): return
	var extra: Dictionary = appointed.episode.duplicate(true)
	extra["wall_clock"] = 0
	if not _check(not Episode.valid_episode(extra), "an episode with an extra field is refused"): return

	print("SITE R5 S3E EPISODE PASS: the episode records candidates and one ballot per voter while open, refuses duplicates and recasts with the record unchanged, cancels by appointment or heir return (D7) and keeps the record, never changes once closed, and keeps ids as integers through JSON.")
	quit(0)
