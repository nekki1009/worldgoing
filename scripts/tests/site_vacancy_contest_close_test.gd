extends SceneTree
## R5 S5F (pure): the contest result at its deadline (plan 489-495). Zero votes or no candidate selects nobody; the most
## supporters win; a supporter tie goes to the higher leadership, then the lower person id. A close needs the deadline
## and a candidate. A vacancy_contest authority is accepted only for the matching open episode at its deadline.

const Episode = preload("res://scripts/terrain_lab/site_vacancy_episode.gd")
const Take = preload("res://scripts/terrain_lab/site_take_office.gd")

func _initialize() -> void:
	call_deferred("run")

func _check(condition: bool, message: String) -> bool:
	if not condition:
		push_error(message)
		quit(1)
	return condition

func _at_deadline() -> Dictionary:
	var episode: Dictionary = Episode.empty_episode("family", "site-1", "ep-x", 10)
	for day: int in [11, 12, 14]:
		episode = Episode.tick(episode, day).episode
	return episode

func run() -> void:
	var fresh: Dictionary = Episode.empty_episode("family", "site-1", "ep-x", 10)
	if not _check(str(Episode.decide(fresh).code) == "NOT_AT_DEADLINE", "a contest is not decided before its deadline"): return
	if not _check(str(Episode.decide(_at_deadline()).code) == "NO_CANDIDATE", "a deadline with no candidate selects nobody"): return

	var episode: Dictionary = _at_deadline()
	for person: int in [5, 6, 7]: episode = Episode.add_candidate(episode, person).episode
	if not _check(str(Episode.decide(episode).code) == "NO_VOTES", "a deadline with zero votes selects nobody (pending)"): return
	for pair: Array in [[101, 5], [102, 5], [103, 6], [104, 6], [105, 7]]:
		episode = Episode.cast(episode, int(pair[0]), int(pair[1])).episode

	# Most supporters wins; a supporter tie (5 and 6 with two each) goes to the higher leadership, then the lower id.
	var by_leadership: Dictionary = Episode.decide(episode, {5: 10, 6: 20})
	if not _check(bool(by_leadership.ok) and int(by_leadership.winner) == 6, "a supporter tie goes to the higher leadership"): return
	var by_id: Dictionary = Episode.decide(episode, {})
	if not _check(bool(by_id.ok) and int(by_id.winner) == 5, "a supporter tie with equal leadership goes to the lower person id"): return
	var by_lead_5: Dictionary = Episode.decide(episode, {5: 30, 6: 20})
	if not _check(int(by_lead_5.winner) == 5, "the higher leadership of the tied candidate wins"): return

	var closed: Dictionary = Episode.close(episode, 6)
	if not _check(bool(closed.ok) and str(closed.episode.status) == "closed" and int(closed.episode.winner) == 6 and Episode.valid_episode(closed.episode), "the deadline closes the episode with a candidate winner"): return
	if not _check(str(Episode.close(episode, 9).code) == "NO_TARGET", "a non-candidate cannot close the episode as winner"): return
	if not _check(str(Episode.close(fresh, 5).code) == "NOT_AT_DEADLINE", "an episode cannot close before its deadline"): return

	# The vacancy_contest authority: only the matching open episode at its deadline, with a candidate requester.
	var contest: Dictionary = {"kind": "vacancy_contest", "episode_id": "ep-x"}
	if not _check(bool(Take.authority_refusal(contest, 6, 0, episode).ok), "the candidate of the matching deadline episode is authorised"): return
	if not _check(str(Take.authority_refusal(contest, 9, 0, episode).code) == "NO_AUTHORITY", "a non-candidate is not authorised by the contest"): return
	if not _check(str(Take.authority_refusal({"kind": "vacancy_contest", "episode_id": "other"}, 6, 0, episode).code) == "NO_AUTHORITY", "a mismatched episode id is not authorised"): return
	if not _check(str(Take.authority_refusal(contest, 6, 0, fresh).code) == "NO_AUTHORITY", "an episode before its deadline is not authorised"): return
	if not _check(str(Take.authority_refusal(contest, 6, 0, closed.episode).code) == "NO_AUTHORITY", "a closed episode is not authorised again"): return
	if not _check(str(Take.authority_refusal({"kind": "controlled"}, 6, 6).code) == "" or bool(Take.authority_refusal({"kind": "controlled"}, 6, 6).ok), "controlled authority is unchanged"): return

	# Legacy nine-key records load unchanged; an open record with a winner is refused; a winner must be a candidate.
	if not _check(Episode.valid_episode(fresh) and not fresh.has("winner"), "a legacy nine-key open episode is valid"): return
	var open_with_winner: Dictionary = episode.duplicate(true)
	open_with_winner["winner"] = 6
	if not _check(not Episode.valid_episode(open_with_winner), "an open episode with a winner is refused"): return

	# JSON round trip of the closed record keeps the winner an integer.
	var parsed: Variant = JSON.parse_string(JSON.stringify(closed.episode))
	if not _check(parsed is Dictionary, "the closed episode survives a JSON round trip"): return
	Episode.normalize_numbers(parsed)
	if not _check(Episode.valid_episode(parsed) and typeof(parsed.winner) == TYPE_INT and int(parsed.winner) == 6, "the round-tripped closed episode keeps an integer winner"): return

	print("SITE R5 S5F CONTEST CLOSE PASS: zero votes and no candidate select nobody; the most supporters win with the leadership and the lower id as ties; the close needs the deadline and a candidate; the contest authority is accepted only for the matching open episode at its deadline; legacy records load and the winner survives JSON as an integer.")
	quit(0)
