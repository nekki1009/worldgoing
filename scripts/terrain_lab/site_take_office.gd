extends RefCounted
## R5 S2: the narrow vacancy take-office core, shared by the settlement, family and nation entries. Controlled
## authority only in this slice; a vacancy-contest authority (S5) is refused. Every check runs before any write.
## A refusal leaves the source byte-identical; an accepted take commits one revision step.

const Settlement := preload("res://scripts/terrain_lab/site_settlement.gd")
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const VacancyEpisode = preload("res://scripts/terrain_lab/site_vacancy_episode.gd") # R5 S7: vacancy episode record.
const Social = preload("res://scripts/terrain_lab/site_social.gd")

## Stage only social packets on the first close; a later closed episode must never emit losses again.
static func prepare_contest_losses(lab: Variant, episode: Dictionary, winner_id: int, owner_ref: Dictionary, members: Array) -> Dictionary:
	if episode.is_empty(): return Runtime.ok("", {"losses": []})
	if not VacancyEpisode.valid_episode(episode) or str(episode.status) != "open": return Runtime.fail("CLOSED", "空缺已結束或格式非法")
	if not Social.PersonSocial.valid_org_ref(owner_ref): return Runtime.fail("NO_TARGET", "落敗事件缺少原組織引用")
	var owner_id: String = str(owner_ref.site_id) if str(owner_ref.kind) == "settlement" else str(owner_ref.org_id)
	if str(owner_ref.site_id) != str(lab.terrain.site.id) or str(episode.owner_kind) != str(owner_ref.kind) or str(episode.owner_id) != owner_id:
		return Runtime.fail("NO_AUTHORITY", "空缺紀錄不屬於此次接任的原組織")
	var losses: Array[Dictionary] = []
	for candidate: int in episode.candidates:
		if candidate == winner_id: continue
		if not members.has(candidate): return Runtime.fail("NO_TARGET", "落敗候選已不屬於此組織")
		var person: Dictionary = lab.site_controller.person_actions._person(candidate, false)
		var body: Variant = person.get("body")
		if person.is_empty() or (not body is Dictionary and not is_instance_valid(body)):
			return Runtime.fail("NO_TARGET", "落敗候選的原人物引用已失效")
		var source: Dictionary = Social.PersonSocial.read(body)
		if not source.is_empty() and not Social.PersonSocial.valid(source): return Runtime.fail("CORRUPT_STATE", "落敗候選的社會狀態非法")
		# record() may migrate or append; give it a detached packet, never the original body.
		var staged: Dictionary = {"social_state": source.duplicate(true)}
		var event_id: String = "%s:loss:%d" % [str(episode.episode_id), candidate]
		if not Social.record(staged, owner_ref, "vacancy_loss", 10, event_id, int(lab.terrain.site.get("minute", 0))):
			return Runtime.fail("SOCIAL_EVENT_REJECTED", "落敗事件已存在或待結清單已滿；整份接任保持原狀")
		if not Social.PersonSocial.valid(staged.social_state): return Runtime.fail("SOCIAL_EVENT_REJECTED", "落敗事件超出原社會狀態容量")
		losses.append({"body": body, "packet": staged.social_state})
	return Runtime.ok("", {"losses": losses})

## No callbacks, yields or fallible work between preparation and the owner's synchronous commit.
static func commit_contest_losses(losses: Array) -> void:
	for loss: Dictionary in losses:
		var body: Variant = loss.body
		if body is Dictionary: body.social_state = loss.packet
		else: body.set("social_state", loss.packet)

## Only the controlled person, acting for the head seat, may take an office in this slice.
## R5 S5F: a vacancy_contest authority is accepted only for the matching open episode at its deadline, and only for its
## candidate as requester; the episode is passed in by the owner (empty when none matches).
static func authority_refusal(authority: Variant, requester_id: int, controlled_id: int, episode: Dictionary = {}) -> Dictionary:
	if not authority is Dictionary: return Runtime.fail("NO_AUTHORITY", "缺少接任授權")
	if str(authority.get("kind", "")) == "vacancy_contest":
		if episode.is_empty() or str(episode.get("episode_id", "")) != str(authority.get("episode_id", "")): return Runtime.fail("NO_AUTHORITY", "未對應開放中的空缺紀錄")
		if str(episode.get("status", "")) != "open" or str(episode.timer.status) != "deadline_reached": return Runtime.fail("NO_AUTHORITY", "空缺尚未到期或已結束")
		if requester_id <= 0 or not episode.candidates.has(requester_id): return Runtime.fail("NO_AUTHORITY", "得位者須是此空缺的候選人")
		if str(authority.get("seat", "head")) != "head": return Runtime.fail("UNSUPPORTED", "副職接任尚未支援")
		return {"ok": true, "code": "", "message": ""}
	if str(authority.get("kind", "")) != "controlled": return Runtime.fail("NO_AUTHORITY", "本階段只接受受控授權")
	if requester_id <= 0 or requester_id != controlled_id: return Runtime.fail("NO_AUTHORITY", "須由目前受控的人本人接任")
	if str(authority.get("seat", "head")) != "head": return Runtime.fail("UNSUPPORTED", "副職接任尚未支援")
	return {"ok": true, "code": "", "message": ""}

## One commit on a copy: the head seat takes the person, any other seat that person held is cleared (moved, not
## duplicated), and one revision step is added. The source offices are never written here.
static func commit_head(offices: Dictionary, person_id: int) -> Dictionary:
	if person_id <= 0 or SiteOffices.head_position(offices).is_empty(): return Runtime.fail("NO_TARGET", "沒有首長職位")
	var candidate: Dictionary = offices.duplicate(true)
	for entry: Dictionary in candidate.positions:
		if int(entry.holder) == person_id and not bool(entry.head): entry.holder = -1
	SiteOffices.head_position(candidate).holder = person_id
	candidate.revision = mini(SiteOffices.MAX_SEQ, int(candidate.revision) + 1)
	return {"ok": true, "code": "", "message": "", "offices": candidate}

## Settlement: the requester is the controlled person taking the head seat for himself (as claim_head does).
## R5 S7: the open episode named by a vacancy_contest authority, only when it belongs to this owner; else empty.
static func contest_episode(site: Dictionary, authority: Variant, owner_kind: String, owner_id: String) -> Dictionary:
	if not authority is Dictionary or str(authority.get("kind", "")) != "vacancy_contest" or not site.has("vacancy_episodes"): return {}
	var episodes: Dictionary = site.vacancy_episodes
	var episode: Dictionary = episodes.get(str(authority.get("episode_id", "")), {})
	if episode.is_empty() or str(episode.get("owner_kind", "")) != owner_kind or str(episode.get("owner_id", "")) != owner_id: return {}
	return episode

static func take_settlement_head(lab: Variant, requester_id: int, person_id: int, authority: Variant) -> Dictionary:
	var data: TerrainData = lab.terrain
	var settlement: Dictionary = Settlement.record(data)
	if settlement.is_empty() or int(settlement.level) <= 0: return Runtime.fail("NO_TARGET", "尚未建制聚落")
	var contest: Dictionary = contest_episode(data.site, authority, "settlement", str(data.site.id))
	var auth: Dictionary = authority_refusal(authority, requester_id, int(lab.controlled_person_id()), contest)
	if not auth.ok: return auth
	if person_id != requester_id: return Runtime.fail("NO_TARGET", "聚落首長只能由受控人本人就任")
	var head := SiteOffices.head_position(settlement.offices)
	if int(head.holder) > 0: return Runtime.fail("BUSY", "首長在任")
	var person: Dictionary = lab.site_controller.person_actions._person(person_id, false)
	if not Settlement._fit(person) or int(person.faction) != int(settlement.owner_faction) or not Settlement.cell_in_jurisdiction(data, Vector2i(person.cell)):
		return Runtime.fail("NO_TARGET", "須是在管轄內清醒自由的同陣營原人物")
	var committed: Dictionary = commit_head(settlement.offices, person_id)
	if not committed.ok: return committed
	var closed_episode: Dictionary = {}
	if not contest.is_empty():
		var closed: Dictionary = VacancyEpisode.close(contest, person_id)
		if not closed.ok: return closed
		closed_episode = closed.episode
	var losses: Dictionary = prepare_contest_losses(lab, contest, person_id,
		{"kind": "settlement", "site_id": str(data.site.id), "org_id": str(settlement.settlement_id)},
		Settlement.faction_members(lab, int(settlement.owner_faction)).keys())
	if not losses.ok: return losses
	settlement.offices = committed.offices
	settlement.offices.duty_ai = not bool(person.player)
	if not closed_episode.is_empty():
		var episodes: Dictionary = data.site.vacancy_episodes.duplicate(true)
		episodes[str(closed_episode.episode_id)] = closed_episode
		data.site.vacancy_episodes = episodes
	commit_contest_losses(losses.losses)
	return Runtime.ok("已就任「%s」" % str(head.name), {"revision": int(settlement.offices.revision)})

## R5 S7: the per-seat observation shared by nation and settlement (the family keeps its own, same rules). An open episode
## is cancelled by a present holder (appointment) or by a designated heir in place (D7, heir_return). A vacant seat with no
## heir opens one episode per owner. Nothing is overwritten; the record changes only on an open or a cancel.
static func observe_seat(site: Dictionary, owner_kind: String, owner_id: String, present: bool, heir_designated: bool, onset_day: int) -> Dictionary:
	var episodes: Dictionary = site.vacancy_episodes.duplicate(true) if site.has("vacancy_episodes") else {}
	var open: Dictionary = VacancyEpisode.find_open(episodes, owner_kind, owner_id)
	var result := {"ok": true, "code": "", "message": "", "opened": false, "cancelled": false}
	var changed := false
	if present:
		if not open.is_empty():
			var cancelled: Dictionary = VacancyEpisode.cancel(open, "appointment")
			if not cancelled.ok: return cancelled
			episodes[str(open.episode_id)] = cancelled.episode
			result.cancelled = true
			changed = true
	elif heir_designated and not open.is_empty():
		var heir_cancelled: Dictionary = VacancyEpisode.cancel(open, "heir_return")
		if not heir_cancelled.ok: return heir_cancelled
		episodes[str(open.episode_id)] = heir_cancelled.episode
		result.cancelled = true
		changed = true
	elif not heir_designated and open.is_empty():
		var episode: Dictionary = VacancyEpisode.empty_episode(owner_kind, owner_id, "%s-%s-%d-%d" % [owner_kind, owner_id, onset_day, episodes.size()], onset_day)
		episodes[str(episode.episode_id)] = episode
		result.opened = true
		changed = true
	if changed: site.vacancy_episodes = episodes
	return result

## R5 S7: a G0 proven political day advances the owner's open episode timer (the caller passes only proven days).
static func observe_proven(site: Dictionary, owner_kind: String, owner_id: String, proven_day: int) -> Dictionary:
	if not site.has("vacancy_episodes"): return {"ok": true, "code": "", "message": "", "advanced": false}
	var episodes: Dictionary = site.vacancy_episodes.duplicate(true)
	var open: Dictionary = VacancyEpisode.find_open(episodes, owner_kind, owner_id)
	if open.is_empty(): return {"ok": true, "code": "", "message": "", "advanced": false}
	var ticked: Dictionary = VacancyEpisode.tick(open, proven_day)
	if not ticked.ok: return ticked
	episodes[str(open.episode_id)] = ticked.episode
	site.vacancy_episodes = episodes
	return {"ok": true, "code": "", "message": "", "advanced": true}

## R5 S7: the deadline result of the owner's open episode (pure decide). Returns the winner and the episode id; nothing is written.
static func settle_seat_winner(site: Dictionary, owner_kind: String, owner_id: String, leadership: Dictionary) -> Dictionary:
	var episodes: Dictionary = site.vacancy_episodes if site.has("vacancy_episodes") else {}
	var open: Dictionary = VacancyEpisode.find_open(episodes, owner_kind, owner_id)
	if open.is_empty(): return Runtime.fail("NO_TARGET", "沒有開放中的空缺")
	var decided: Dictionary = VacancyEpisode.decide(open, leadership)
	if not decided.ok: return decided
	return {"ok": true, "code": "", "message": "", "winner": int(decided.winner), "episode_id": str(open.episode_id)}

## R5 S7: the settlement seat through the shared observation (a present and fit holder, or a designated heir).
static func observe_settlement_vacancy(lab: Variant, onset_day: int) -> Dictionary:
	var data: TerrainData = lab.terrain
	var settlement: Dictionary = Settlement.record(data)
	if settlement.is_empty(): return Runtime.fail("NO_TARGET", "尚未建制聚落")
	var seat := SiteOffices.head_position(settlement.offices)
	var present: bool = int(seat.get("holder", -1)) > 0 and Settlement.office_person_ok(lab, int(seat.holder))
	var heir: bool = settlement.has("succession") and (settlement.succession.get("heirs", {}) as Dictionary).has(str(seat.get("id", "")))
	return observe_seat(data.site, "settlement", str(data.site.id), present, heir, onset_day)

static func observe_settlement_proven_day(lab: Variant, proven_day: int) -> Dictionary:
	return observe_proven(lab.terrain.site, "settlement", str(lab.terrain.site.id), proven_day)

static func settle_settlement_contest(lab: Variant, leadership: Dictionary = {}) -> Dictionary:
	var site: Dictionary = lab.terrain.site
	var won: Dictionary = settle_seat_winner(site, "settlement", str(site.id), leadership)
	if not won.ok: return won
	return take_settlement_head(lab, int(won.winner), int(won.winner), {"kind": "vacancy_contest", "episode_id": str(won.episode_id)})
