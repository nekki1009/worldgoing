extends RefCounted
## R5 S2: the narrow vacancy take-office core, shared by the settlement, family and nation entries. Controlled
## authority only in this slice; a vacancy-contest authority (S5) is refused. Every check runs before any write.
## A refusal leaves the source byte-identical; an accepted take commits one revision step.

const Settlement := preload("res://scripts/terrain_lab/site_settlement.gd")
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")

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
static func take_settlement_head(lab: Variant, requester_id: int, person_id: int, authority: Variant) -> Dictionary:
	var data: TerrainData = lab.terrain
	var settlement: Dictionary = Settlement.record(data)
	if settlement.is_empty() or int(settlement.level) <= 0: return Runtime.fail("NO_TARGET", "尚未建制聚落")
	var auth: Dictionary = authority_refusal(authority, requester_id, int(lab.controlled_person_id()))
	if not auth.ok: return auth
	if person_id != requester_id: return Runtime.fail("NO_TARGET", "聚落首長只能由受控人本人就任")
	var head := SiteOffices.head_position(settlement.offices)
	if int(head.holder) > 0: return Runtime.fail("BUSY", "首長在任")
	var person: Dictionary = lab.site_controller.person_actions._person(person_id, false)
	if not Settlement._fit(person) or int(person.faction) != int(settlement.owner_faction) or not Settlement.cell_in_jurisdiction(data, Vector2i(person.cell)):
		return Runtime.fail("NO_TARGET", "須是在管轄內清醒自由的同陣營原人物")
	var committed: Dictionary = commit_head(settlement.offices, person_id)
	if not committed.ok: return committed
	settlement.offices = committed.offices
	settlement.offices.duty_ai = not bool(person.player)
	return Runtime.ok("已就任「%s」" % str(head.name), {"revision": int(settlement.offices.revision)})
