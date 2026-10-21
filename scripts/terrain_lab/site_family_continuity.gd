extends RefCounted
## References and death-only control continuity, never another person's body.
## Original SiteStore loads and the Lab's control/bind transaction are injected
## so Store can reuse validate_family without a circular preload dependency.

const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Technology = preload("res://scripts/terrain_lab/site_technology.gd")
## Version 4 display name (at most NAME_MAX characters, may be empty) and stable lineage id.
const NAME_MAX := 32
const LINEAGE_MAX := 2147483646
var lab: Variant
var load_site_query: Callable # (path) -> original SiteStore.load_site result.
var archive_current: Callable # () -> guarded original snapshot/save result.
var control_selected: Callable # (validated_data_or_null, identity) -> atomic Lab result.
var resolve_owner: Callable # (reference) -> original Slot/Site/Party observation.
var commit_control_transition: Callable # (reference, source, family) -> original atomic commit.
var _seen_death: Array = []

func init(scene: Variant) -> void:
	lab = scene
	_seen_death.clear()

static func _integer(value: Variant, lower: int, upper: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= lower and float(value) <= upper and float(value) == floorf(float(value))

## `site_id`: the Site whose `site.family` this is. Office holders are people of
## that Site, so they must be registered with that site_id (F01): a person with
## the same number elsewhere is not a member here.
const Succession = preload("res://scripts/terrain_lab/site_succession.gd") # R5 S1B: optional v5 heir section.
const Take = preload("res://scripts/terrain_lab/site_take_office.gd") # R5 S2: vacancy take-office core.
const VacancyEpisode = preload("res://scripts/terrain_lab/site_vacancy_episode.gd") # R5 S3F: vacancy episode hook.

static func validate_family(value: Variant, site_id: String) -> bool:
	# v1: unestablished registry. v2: the same registry plus offices, created by
	# the first explicit head appointment (OFFICE plan 6.3).
	if not value is Dictionary or not _integer(value.get("version"), 1, 5) or not value.get("complete") is bool or not value.get("members") is Array:
		return false
	if value.size() != (3 if int(value.version) == 1 else (4 if int(value.version) == 2 else 6 + int(int(value.version) == 5 and value.has("succession")))) or int(value.version) >= 2 and not SiteOffices.validate(value.get("offices"), "family"):
		return false
	if int(value.version) == 3 and (not Technology.valid_family_id(value.get("family_id")) or not Technology.valid_family_tech(value.get("technology"))): return false
	if int(value.version) >= 4 and not valid_identity(value.get("name"), value.get("lineage_id")): return false
	if not valid_succession(value, site_id): return false
	var seen := {}
	for member: Variant in value.members:
		if not member is Dictionary or member.size() != 5 or not member.get("site_id") is String or str(member.site_id).is_empty() or not member.get("path") is String or not member.get("label") is String:
			return false
		if not _integer(member.get("person_id"), 1, 2147483647) or int(member.person_id) == 1000000000 or not _integer(member.get("age_years"), -1, 200):
			return false
		var key := [str(member.site_id), int(member.person_id)]
		if seen.has(key):
			return false
		seen[key] = true
	if int(value.version) >= 2:
		for seat: Dictionary in value.offices.positions:
			if int(seat.holder) > 0 and not member_ids(value, site_id).has(int(seat.holder)): return false
	return true

## R5 S1B (D-F1): the optional v5 succession section. The heir is a current family member of this Site, on the head seat.
static func valid_succession(family: Dictionary, site_id: String) -> bool:
	if not family.has("succession"): return true
	if int(family.get("version", 0)) != 5 or not family.get("offices") is Dictionary: return false
	var seats: Array = []
	var head := SiteOffices.head_position(family.offices)
	if not head.is_empty(): seats.append(str(head.id))
	var members := {}
	for identity: int in member_ids(family, site_id): members[identity] = true
	return Succession.valid_record(family.succession, seats, members)

## R5 S1B: the candidate of a family heir designation. Authority = the family head; family v4 or later (identity present).
static func designate_heir_candidate(family: Dictionary, site_id: String, requester_id: int, person_id: int, alive: Callable) -> Dictionary:
	if int(family.get("version", 0)) < 4 or not family.get("offices") is Dictionary: return {"ok": false, "code": "NO_TARGET"}
	var head := SiteOffices.head_position(family.offices)
	var holder := int(head.get("holder", -1))
	if holder <= 0 or requester_id != holder: return {"ok": false, "code": "NO_AUTHORITY"}
	var members := {}
	for identity: int in member_ids(family, site_id): members[identity] = true
	var record: Dictionary = family.succession if family.has("succession") else Succession.empty_record()
	var designated: Dictionary = Succession.designate(record, str(head.id), person_id, [str(head.id)], members, holder, alive)
	if not bool(designated.ok): return designated
	var candidate: Dictionary = family.duplicate(true)
	candidate.version = 5
	candidate.succession = designated.record
	candidate.offices.revision = mini(SiteOffices.MAX_SEQ, int(candidate.offices.revision) + 1)
	return {"ok": true, "code": "", "family": candidate}

## R5 S1B: the lab command. The family head designates a living local member, in place, in one commit.
func designate_heir(requester_id: int, person_id: int) -> Dictionary:
	var family: Variant = lab.terrain.site.get("family", {})
	if not family is Dictionary or family.is_empty(): return Runtime.fail("NO_TARGET", "沒有家族紀錄")
	var checked: Dictionary = designate_heir_candidate(family, str(lab.terrain.site.id), requester_id, person_id, func(identity: int) -> bool: return office_person_ok(family, identity))
	if not bool(checked.get("ok", false)): return Runtime.fail(str(checked.code), "家族繼承人指定未通過；原狀未變")
	family.clear()
	family.merge(checked.family, true)
	return Runtime.ok("已指定家族繼承人", {"person_id": person_id})

## Version 4 identity: display name (String, may be empty) and an integer lineage id.
static func valid_identity(display_name: Variant, lineage_id: Variant) -> bool:
	return display_name is String and str(display_name).length() <= NAME_MAX and _integer(lineage_id, 1, LINEAGE_MAX)

## Formal owner of the version 4 identity. Only the controlled member may name the
## family; the Site counter next_lineage issues the id once and advances. Never on load.
func establish_identity(requester_id: int, display_name: String) -> Dictionary:
	var site: Dictionary = lab.terrain.site
	var family: Variant = site.get("family")
	if not validate_family(family, str(site.id)): return Runtime.fail("UNREGISTERED", "先明確登錄家族名單")
	if requester_id != _controlled_id(): return Runtime.fail("NO_AUTHORITY", "只有目前受控的族人可以建立家族身分")
	var version := int(family.get("version", 1))
	if version == 3: return Runtime.fail("TECHNOLOGY_FAMILY", "已有科技的家族維持 v3，本次不改寫")
	if version >= 4: return Runtime.fail("ALREADY_IDENTIFIED", "家族身分已建立")
	if not valid_identity(display_name, 1): return Runtime.fail("INVALID_FAMILY_NAME", "家族名稱最多 32 字")
	var lineage := int(site.get("next_lineage", 1))
	if lineage < 1 or lineage > LINEAGE_MAX: return Runtime.fail("LINEAGE_LIMIT", "家族序號已達上限")
	var offices: Dictionary = family.offices.duplicate(true) if version >= 2 else SiteOffices.default_offices("family", -1, false)
	var candidate := {"version": 4, "complete": bool(family.complete), "members": family.members.duplicate(true), "offices": offices, "name": display_name, "lineage_id": lineage}
	if not validate_family(candidate, str(site.id)): return Runtime.fail("INVALID_FAMILY", "家族身分未通過驗證；未改變")
	site.family = candidate
	site.next_lineage = lineage + 1
	return Runtime.ok("已建立家族身分", {"lineage_id": lineage})

## P4 S4B: the editor name candidate (data level). A version 1 or 2 family becomes version 4 with
## `lineage` as its id (the caller advances the Site counter); a version 4 family is renamed and
## keeps its id. Nothing is written here.
static func name_candidate(family: Variant, site_id: String, lineage: int, display_name: String) -> Dictionary:
	if not validate_family(family, site_id): return Runtime.fail("UNREGISTERED", "先建立並登錄家族名單")
	var version := int(family.get("version", 1))
	if version == 3: return Runtime.fail("TECHNOLOGY_FAMILY", "已有科技的家族維持 v3，本次不改寫")
	if not valid_identity(display_name, 1): return Runtime.fail("INVALID_FAMILY_NAME", "家族名稱最多 32 字")
	var candidate: Dictionary
	if version >= 4:
		candidate = family.duplicate(true)
		candidate.name = display_name
	else:
		if lineage < 1 or lineage > LINEAGE_MAX: return Runtime.fail("LINEAGE_LIMIT", "家族序號已達上限")
		var offices: Dictionary = family.offices.duplicate(true) if version >= 2 else SiteOffices.default_offices("family", -1, false)
		candidate = {"version": 4, "complete": bool(family.complete), "members": family.members.duplicate(true), "offices": offices, "name": display_name, "lineage_id": lineage}
	if not validate_family(candidate, site_id): return Runtime.fail("INVALID_FAMILY", "家族名稱候選未通過驗證；未改變")
	return Runtime.ok("", {"family": candidate})

## P4 S4: pure authoring plan for a family roster. Never writes. `requested` is the complete
## list of member references the editor wants (each with the five roster fields). Other-Site
## members are read-only: they must be kept exactly, and no local edit may add one. A local
## member who holds an office seat is never dropped silently: the refusal lists the seats.
static func roster_plan(family: Variant, site_id: String, requested: Array) -> Dictionary:
	if not validate_family(family, site_id): return Runtime.fail("INVALID_FAMILY", "家族名冊未通過驗證")
	var offices: Dictionary = family.get("offices", {}) if int(family.version) >= 2 else {}
	var existing_keys := {}
	for prior_member: Dictionary in family.members:
		existing_keys[JSON.stringify([str(prior_member.site_id), int(prior_member.person_id)])] = true
	var wanted_keys := {}
	for requested_member: Variant in requested:
		if not requested_member is Dictionary or requested_member.size() != 5 or not requested_member.get("site_id") is String \
				or not _integer(requested_member.get("person_id"), 1, 2147483647) or not requested_member.get("path") is String \
				or not requested_member.get("label") is String or not _integer(requested_member.get("age_years"), -1, 200):
			return Runtime.fail("INVALID_MEMBER", "人物引用欄位不完整")
		var wanted_key := JSON.stringify([str(requested_member.site_id), int(requested_member.person_id)])
		if wanted_keys.has(wanted_key): return Runtime.fail("DUPLICATE_MEMBER", "同一原人物只能登錄一次")
		if str(requested_member.site_id) != site_id and not existing_keys.has(wanted_key): return Runtime.fail("FOREIGN_MEMBER", "外地人物只能保留唯讀，不能由本地名冊新增")
		wanted_keys[wanted_key] = true
	var references: Array = []
	for existing_member: Dictionary in family.members:
		var current_key := JSON.stringify([str(existing_member.site_id), int(existing_member.person_id)])
		if wanted_keys.has(current_key): continue
		if str(existing_member.site_id) != site_id: return Runtime.fail("FOREIGN_READ_ONLY", "外地族人須原樣保留，不能由本地名冊移除")
		var seat: Dictionary = SiteOffices.position_of(offices, int(existing_member.person_id)) if not offices.is_empty() else {}
		if not seat.is_empty(): references.append(str(seat.name))
	if not references.is_empty():
		var refused := Runtime.fail("HOLDS_OFFICE", "此人仍擔任職位，須先卸任：" + ", ".join(PackedStringArray(references)))
		refused.references = references
		return refused
	var candidate: Dictionary = family.duplicate(true)
	candidate.members = []
	for candidate_member: Dictionary in requested:
		candidate.members.append({"site_id": str(candidate_member.site_id), "person_id": int(candidate_member.person_id),
			"path": str(candidate_member.path), "label": str(candidate_member.label), "age_years": int(candidate_member.age_years)})
	if not validate_family(candidate, site_id): return Runtime.fail("INVALID_FAMILY", "名冊候選未通過驗證；未改變")
	return Runtime.ok("", {"family": candidate})

## Members who are people of `site_id` (full reference: site + person, F01).
## R6 S1 (plan 10.1): a family member leaves the family. An NPC leaves only by a declared npc_event; the controlled person
## leaves only by an explicit controlled act. The member's entries are removed and the seats it held are vacated (a vacated
## head is a legal vacancy that the S3F hook picks up). Nothing else changes: nation, team, lineage, items and captives stay.
static func departure_candidate(family: Dictionary, site_id: String, person_id: int, authority: Variant, controlled_id: int) -> Dictionary:
	if not validate_family(family, site_id): return Runtime.fail("UNREGISTERED", "先明確登錄家族名單")
	if not member_ids(family, site_id).has(person_id): return Runtime.fail("NO_TARGET", "此人不是本家族成員")
	if not authority is Dictionary: return Runtime.fail("NO_AUTHORITY", "缺少離族授權")
	var kind: String = str(authority.get("kind", ""))
	if kind == "controlled" and person_id != controlled_id: return Runtime.fail("NO_AUTHORITY", "只有受控者本人可明示離族")
	if kind == "npc_event" and person_id == controlled_id: return Runtime.fail("NO_AUTHORITY", "受控者離族須明示操作")
	if kind != "controlled" and kind != "npc_event": return Runtime.fail("NO_AUTHORITY", "未知的離族授權")
	var candidate: Dictionary = family.duplicate(true)
	var kept: Array = []
	for member: Dictionary in candidate.members:
		if not (str(member.site_id) == site_id and int(member.person_id) == person_id): kept.append(member)
	if kept.is_empty(): return Runtime.fail("NO_TARGET", "家族至少須保留一位族人")
	candidate.members = kept
	var seat_vacated: bool = false
	var changed: bool = false
	if candidate.get("offices") is Dictionary:
		for entry: Dictionary in candidate.offices.positions:
			if int(entry.holder) == person_id:
				entry.holder = -1
				changed = true
				if bool(entry.head): seat_vacated = true
	# A departing member cannot remain a designated heir of this organization.
	if candidate.get("succession") is Dictionary:
		for seat_id: String in candidate.succession.heirs.keys():
			if int(candidate.succession.heirs[seat_id]) == person_id:
				candidate.succession.heirs.erase(seat_id)
				changed = true
	if changed: candidate.offices.revision = mini(SiteOffices.MAX_SEQ, int(candidate.offices.revision) + 1)
	if not validate_family(candidate, site_id): return Runtime.fail("CORRUPT_STATE", "離族後家族紀錄不合法")
	return {"ok": true, "code": "", "message": "", "family": candidate, "seat_vacated": seat_vacated}

## R6 S1: the optional departure history on the site (absent in old saves). Strict: four keys, integer ids and minute,
## a known authority kind, and a boolean seat flag.
static func valid_departures(raw: Variant) -> bool:
	if not raw is Array: return false
	for entry: Variant in raw:
		if not entry is Dictionary or entry.size() != 4: return false
		for key: String in ["person_id", "minute", "authority", "seat_vacated"]:
			if not entry.has(key): return false
		if not _integer(entry.person_id, 1, 2147483647) or not _integer(entry.minute, 0, 2147483647): return false
		if not entry.authority is String or not ["controlled", "npc_event"].has(str(entry.authority)): return false
		if not entry.seat_vacated is bool: return false
	return true

static func member_ids(family: Dictionary, site_id: String) -> Array[int]:
	var result: Array[int] = []
	for member: Dictionary in family.get("members", []):
		if str(member.site_id) == site_id and not result.has(int(member.person_id)): result.append(int(member.person_id))
	return result

func local_member_ids(family: Dictionary) -> Array[int]:
	return member_ids(family, str(lab.terrain.site.id))

static func family_offices(family: Variant, read_only: bool = false) -> Dictionary:
	if not family is Dictionary or not family.has("offices"): return {}
	if read_only:
		if not SiteOffices.validate(family.offices, "family"): return {}
		var current: Dictionary = family.offices
		var migration := int(current.version) < SiteOffices.VERSION
		for duty: String in SiteOffices.duty_ids("family"):
			migration = migration or not current.duties.has(duty)
		if migration:
			current = current.duplicate(true)
			SiteOffices.upgrade(current)
			SiteOffices.ensure_catalog(current, "family")
		return current
	SiteOffices.upgrade(family.offices)
	if SiteOffices.ensure_catalog(family.offices, "family"): family.offices.revision = mini(SiteOffices.MAX_SEQ, int(family.offices.revision) + 1)
	return family.offices

## Exercising a family duty needs the person here, alive, conscious and free.

## Exercising a family duty needs the person here, alive, conscious and free.
func office_person_ok(family: Dictionary, identity: int) -> bool:
	if not local_member_ids(family).has(identity): return false
	var person := _current_person(identity)
	return not person.is_empty() and float(person.hp) > 0.0 and float(person.ko) <= 0.0 and not bool(person.captive)

func head_executor(family: Dictionary, read_only: bool = false) -> int:
	var head := int(SiteOffices.head_position(family_offices(family, read_only)).get("holder", -1))
	return head if head > 0 and office_person_ok(family, head) else -1

## Unestablished families have no offices: every caller keeps today's behavior.

## Unestablished families have no offices: every caller keeps today's behavior.
func duty_resolve(duty_id: String, read_only: bool = false) -> Dictionary:
	var family: Variant = lab.terrain.site.get("family", {})
	var offices := family_offices(family, read_only)
	if offices.is_empty(): return {"ok": false, "code": "UNESTABLISHED", "message": "家族尚未建制", "duty_id": duty_id}
	return SiteOffices.resolve(offices, duty_id, head_executor(family, read_only), func(identity: int) -> bool: return office_person_ok(family, identity))

## The head is named by the controlled family member while the seat is vacant
## or its holder cannot act (D7); a fit head hands over through the same entry.
## The first call founds the family's offices with the one-seat default.

## The head is named by the controlled family member while the seat is vacant
## or its holder cannot act (D7); a fit head hands over through the same entry.
## The first call founds the family's offices with the one-seat default.
## Original caller/physical preflight, shared by both explicit targets.
## read_only=false preserves legacy office upgrade-on-read behavior.
func _prepare_head_appointment(family: Variant, requester_id: int, person_id: int, read_only: bool = false) -> Dictionary:
	if not validate_family(family, str(lab.terrain.site.id)): return Runtime.fail("UNREGISTERED", "先明確登錄家族名單")
	var members: Array[int] = local_member_ids(family)
	if not members.has(person_id) or not members.has(requester_id) or requester_id != _controlled_id():
		return Runtime.fail("NO_AUTHORITY", "須由目前受控的族人指定家主，人選也須是登錄族人")
	var current: int = head_executor(family, read_only)
	if current > 0 and current != requester_id: return Runtime.fail("NO_AUTHORITY", "家主在任且清醒；只有家主本人可交接")
	var person: Dictionary = _current_person(person_id)
	if person.is_empty() or float(person.hp) <= 0.0: return Runtime.fail("NO_TARGET", "家主人選須是在此地存活的原人物")
	var offices: Dictionary = family_offices(family, read_only).duplicate(true)
	var planned: Dictionary = head_offices_candidate(offices, person_id, _controlled_id())
	if not planned.ok: return planned
	planned["family_version"] = maxi(2, int(family.get("version", 1)))
	return planned

## Pure office construction only; this is not caller or physical qualification.
static func head_offices_candidate(offices: Dictionary, person_id: int, controlled_id: int) -> Dictionary:
	var candidate: Dictionary = offices.duplicate(true)
	if not candidate.is_empty() and not SiteOffices.validate(candidate, "family"): return Runtime.fail("INVALID_OFFICES", "家族原職位紀錄無效")
	if candidate.is_empty(): candidate = SiteOffices.default_offices("family", -1, person_id != controlled_id)
	var seat: Dictionary = SiteOffices.position_of(candidate, person_id)
	if not seat.is_empty() and not bool(seat.head): return Runtime.fail("DUPLICATE_HOLDER", "同一人在同一組織最多擔任一個職位；請先卸任「%s」" % seat.name)
	SiteOffices.head_position(candidate).holder = person_id
	candidate.revision = mini(SiteOffices.MAX_SEQ, int(candidate.revision) + 1)
	return Runtime.ok("", {"offices": candidate, "revision": int(candidate.revision), "validation": "office_candidate_only"})

func appoint_head(requester_id: int, person_id: int) -> Dictionary:
	var family: Variant = lab.terrain.site.get("family")
	var planned: Dictionary = _prepare_head_appointment(family, requester_id, person_id)
	if not planned.ok: return planned
	family.version = int(planned.family_version)
	family.offices = planned.offices
	return Runtime.ok("已指定家主 #%d" % person_id, {"revision": int(planned.revision)})

## First migrated writer sink: private-only, real live authority AND draft
## authority must pass. No supplied candidate, validator or person facts.
func appoint_head_in_organization_edit(ticket: Dictionary, revision: int, requester_id: int, person_id: int) -> Dictionary:
	if not is_instance_valid(lab) or not is_instance_valid(lab.site_controller) or lab.site_controller.family_continuity != self or lab.site_controller.region_slot == null: return Runtime.fail("NO_ORIGINAL_FAMILY_OWNER", "須使用原 Controller 的家族 owner")
	# Keep Family free of a circular preload of Slot/Registry/Edit.
	var slot: RefCounted = lab.site_controller.region_slot
	var target: Dictionary = slot.call("organization_family_edit_target", ticket, revision, lab.terrain, self)
	if not target.ok: return target
	var draft: Dictionary = target.family
	if int(draft.get("version", 1)) < 2: return Runtime.fail("ORGANIZATION_IDENTITY_MIGRATION_REQUIRED", "本片不在 private 路徑建立 v1 家族職位")
	var live_plan: Dictionary = _prepare_head_appointment(lab.terrain.site.family, requester_id, person_id, true)
	if not live_plan.ok: return live_plan
	var draft_plan: Dictionary = _prepare_head_appointment(draft, requester_id, person_id, true)
	if not draft_plan.ok: return draft_plan
	var candidate: Dictionary = draft.duplicate(true)
	candidate.offices = draft_plan.offices
	# Existing typed version/lineage stays unchanged; live v1 upgrade remains above.
	var changed: Dictionary = slot.call("mutate_organization_edit", ticket, revision, "family", target.reference, candidate)
	if changed.ok:
		changed["command"] = "family.appoint_head"
		changed["validation"] = "family_head_command_preflight_only"
	return changed

## R5 S2: the family head seat is taken only when no awake head holds it (an absent or unfit head is replaced in one commit).
## Controlled authority only; the seated awake head refuses (BUSY).
func take_vacant_head(requester_id: int, person_id: int, authority: Variant) -> Dictionary:
	var family: Variant = lab.terrain.site.get("family")
	if not validate_family(family, str(lab.terrain.site.id)): return Runtime.fail("UNREGISTERED", "先明確登錄家族名單")
	var contest_episode: Dictionary = _contest_episode(lab.terrain.site, authority)
	var auth: Dictionary = Take.authority_refusal(authority, requester_id, _controlled_id(), contest_episode)
	if not auth.ok: return auth
	var members := local_member_ids(family)
	if not members.has(person_id) or not members.has(requester_id): return Runtime.fail("NO_TARGET", "接任人須是登錄族人")
	if head_executor(family, true) > 0: return Runtime.fail("BUSY", "家主在任且清醒")
	var person := _current_person(person_id)
	if person.is_empty() or float(person.hp) <= 0.0: return Runtime.fail("NO_TARGET", "家主人選須是在此地存活的原人物")
	var offices: Dictionary = family_offices(family, true).duplicate(true)
	if offices.is_empty(): offices = SiteOffices.default_offices("family", -1, person_id != _controlled_id())
	var committed: Dictionary = Take.commit_head(offices, person_id)
	if not committed.ok: return committed
	var closed_episode: Dictionary = {}
	if not contest_episode.is_empty():
		var closed: Dictionary = VacancyEpisode.close(contest_episode, person_id)
		if not closed.ok: return closed
		closed_episode = closed.episode
	var losses: Dictionary = Take.prepare_contest_losses(lab, contest_episode, person_id,
		{"kind": "family", "site_id": str(lab.terrain.site.id), "org_id": str(lab.terrain.site.id)}, members)
	if not losses.ok: return losses
	family.version = maxi(2, int(family.get("version", 1)))
	family.offices = committed.offices
	if not closed_episode.is_empty():
		var episodes: Dictionary = lab.terrain.site.vacancy_episodes.duplicate(true)
		episodes[str(closed_episode.episode_id)] = closed_episode
		lab.terrain.site.vacancy_episodes = episodes
	Take.commit_contest_losses(losses.losses)
	return Runtime.ok("已就任家主 #%d" % person_id, {"revision": int(committed.offices.revision)})

## R5 S5F: the open episode named by a vacancy_contest authority, or empty.
func _contest_episode(site: Dictionary, authority: Variant) -> Dictionary:
	if not authority is Dictionary or str(authority.get("kind", "")) != "vacancy_contest" or not site.has("vacancy_episodes"): return {}
	var episodes: Dictionary = site.vacancy_episodes
	return episodes.get(str(authority.get("episode_id", "")), {})

## R5 S5F: the deadline close and winner. Zero votes or no candidate is pending (no change). The winner takes the head
## through take_vacant_head with the matching vacancy_contest authority, in one commit with the episode close.
func settle_contest(leadership: Dictionary = {}) -> Dictionary:
	var site: Dictionary = lab.terrain.site
	var episodes: Dictionary = site.vacancy_episodes if site.has("vacancy_episodes") else {}
	var open: Dictionary = VacancyEpisode.find_open(episodes, "family", str(site.id))
	if open.is_empty(): return Runtime.fail("NO_TARGET", "沒有開放中的家族空缺")
	var decided: Dictionary = VacancyEpisode.decide(open, leadership)
	if not decided.ok: return decided
	var winner := int(decided.winner)
	return take_vacant_head(winner, winner, {"kind": "vacancy_contest", "episode_id": str(open.episode_id)})

## R6 S1: the family departure transaction. It writes the family and the site's departure history only (the S3F hook picks up
## a vacated head on the next observation). Refusals leave the family and the history byte-identical.
func leave_family(person_id: int, authority: Variant) -> Dictionary:
	var site: Dictionary = lab.terrain.site
	var family: Variant = site.get("family")
	if not family is Dictionary: return Runtime.fail("UNREGISTERED", "先明確登錄家族名單")
	var checked: Dictionary = departure_candidate(family, str(site.id), person_id, authority, _controlled_id())
	if not checked.ok: return checked
	var history: Array = site.family_departures.duplicate(true) if site.has("family_departures") else []
	history.append({"person_id": person_id, "minute": int(site.get("minute", 0)), "authority": str(authority.get("kind", "")), "seat_vacated": bool(checked.seat_vacated)})
	family.clear()
	family.merge(checked.family, true)
	site.family_departures = history
	return Runtime.ok("已離族", {"seat_vacated": bool(checked.seat_vacated)})

## R5 S3F: the vacancy episode hook. Explicit call (the per-tick settle path is a later slice). An episode opens when the
## family head seat has no awake holder and no designated heir (one open episode per owner, never an overwrite). An awake
## holder cancels the open episode as a legitimate appointment. Otherwise nothing changes.
func observe_vacancy(onset_day: int) -> Dictionary:
	var site: Dictionary = lab.terrain.site
	var family: Variant = site.get("family")
	if not family is Dictionary or not validate_family(family, str(site.id)): return Runtime.fail("UNREGISTERED", "先明確登錄家族名單")
	var episodes: Dictionary = site.vacancy_episodes.duplicate(true) if site.has("vacancy_episodes") else {}
	var seat_id := str(SiteOffices.head_position(family_offices(family, true)).get("id", ""))
	var heir_designated: bool = family.has("succession") and (family.succession.get("heirs", {}) as Dictionary).has(seat_id)
	var open: Dictionary = VacancyEpisode.find_open(episodes, "family", str(site.id))
	var result := {"ok": true, "code": "", "message": "", "opened": false, "cancelled": false}
	var changed := false
	if head_executor(family, true) > 0:
		if not open.is_empty():
			var cancelled: Dictionary = VacancyEpisode.cancel(open, "appointment")
			if not cancelled.ok: return cancelled
			episodes[str(open.episode_id)] = cancelled.episode
			result.cancelled = true
			changed = true
	elif heir_designated and not open.is_empty():
		# R5 S5F (D7): the designated heir is in place; the open episode is cancelled and kept, the seat is not overwritten.
		var heir_cancelled: Dictionary = VacancyEpisode.cancel(open, "heir_return")
		if not heir_cancelled.ok: return heir_cancelled
		episodes[str(open.episode_id)] = heir_cancelled.episode
		result.cancelled = true
		changed = true
	elif not heir_designated and open.is_empty():
		var episode: Dictionary = VacancyEpisode.empty_episode("family", str(site.id), "family-%d-%d" % [onset_day, episodes.size()], onset_day)
		episodes[str(episode.episode_id)] = episode
		result.opened = true
		changed = true
	if changed: site.vacancy_episodes = episodes
	return result

## R5 S3F: a G0 proven political day advances the open family episode's S4 timer. Only proven days are passed in.
func observe_proven_day(proven_day: int) -> Dictionary:
	var site: Dictionary = lab.terrain.site
	if not site.has("vacancy_episodes"): return {"ok": true, "code": "", "message": "", "advanced": false}
	var episodes: Dictionary = site.vacancy_episodes.duplicate(true)
	var open: Dictionary = VacancyEpisode.find_open(episodes, "family", str(site.id))
	if open.is_empty(): return {"ok": true, "code": "", "message": "", "advanced": false}
	var ticked: Dictionary = VacancyEpisode.tick(open, proven_day)
	if not ticked.ok: return ticked
	episodes[str(open.episode_id)] = ticked.episode
	site.vacancy_episodes = episodes
	return {"ok": true, "code": "", "message": "", "advanced": true}

## Organization adjustment is the head's own, non-delegable power (3.5).
func apply_office_plan(requester_id: int, expected_revision: int, ops: Array) -> Dictionary:
	var family: Variant = lab.terrain.site.get("family", {})
	if not _office_plan_authorized(family, requester_id):
		return Runtime.fail("NO_AUTHORITY", "只有清醒自由的家主可調整家族職位")
	var members := local_member_ids(family)
	var result := SiteOffices.apply_plan(family.offices, "family", expected_revision, ops, func(identity: int, _office_class: String) -> bool: return members.has(identity))
	if not bool(result.ok): return result
	family.offices = result.offices
	return Runtime.ok("已套用家族人事方案", {"revision": int(family.offices.revision), "refs": result.refs})

## Original non-delegable head predicate; default retains live upgrade-on-read.
func _office_plan_authorized(family: Variant, requester_id: int, read_only: bool = false) -> bool:
	return not family_offices(family, read_only).is_empty() and requester_id == head_executor(family, read_only)

## Actual live authority and membership cannot be granted by draft edits.
func apply_office_plan_in_organization_edit(ticket: Dictionary, revision: int, requester_id: int, expected_revision: int, ops: Array) -> Dictionary:
	if not is_instance_valid(lab) or not is_instance_valid(lab.site_controller) or lab.site_controller.family_continuity != self or lab.site_controller.region_slot == null: return Runtime.fail("NO_ORIGINAL_FAMILY_OWNER", "須使用原 Controller 的家族 owner")
	var slot: RefCounted = lab.site_controller.region_slot
	var target: Dictionary = slot.call("organization_family_edit_target", ticket, revision, lab.terrain, self)
	if not target.ok: return target
	var draft: Dictionary = target.family
	var live: Dictionary = lab.terrain.site.family
	if requester_id <= 0 or not _office_plan_authorized(live, requester_id, true) or not _office_plan_authorized(draft, requester_id, true):
		return Runtime.fail("NO_AUTHORITY", "只有清醒自由的家主可調整家族職位")
	var live_members: Array[int] = local_member_ids(live)
	var draft_members: Array[int] = local_member_ids(draft)
	var result: Dictionary = SiteOffices.apply_plan(family_offices(draft, true), "family", expected_revision, ops,
		func(identity: int, _office_class: String) -> bool: return live_members.has(identity) and draft_members.has(identity))
	if not result.ok: return result
	var candidate: Dictionary = draft.duplicate(true)
	candidate.offices = result.offices
	var changed: Dictionary = slot.call("mutate_organization_edit", ticket, revision, "family", target.reference, candidate)
	if changed.ok:
		changed["command"] = "family.apply_office_plan"
		changed["validation"] = "family_office_command_preflight_only"
		changed["office_revision"] = int(result.offices.revision)
		changed["refs"] = result.refs.duplicate(true)
	return changed

func set_duty_ai_enabled(requester_id: int, enabled: bool) -> Dictionary:
	var family: Variant = lab.terrain.site.get("family", {})
	if family_offices(family).is_empty() or requester_id != head_executor(family):
		return Runtime.fail("NO_AUTHORITY", "職責 AI 開關屬家主的組織設定")
	family.offices.duty_ai = enabled
	return Runtime.ok("已%s家族職責 AI" % ("開啟" if enabled else "關閉"))

func _controlled_id() -> int:
	return int(lab.terrain.site.get("controlled_person_id", lab.character.person_id))

func _current_person(identity: int) -> Dictionary:
	var person: Dictionary = lab._combat_target(identity)
	if person.is_empty():
		return {}
	var body: Variant = person.owner.combat_units[int(person.unit)] if int(person.unit) >= 0 else person.owner
	return {"hp": float(person.hp), "captive": bool(person.owner.combat_hot_get(int(person.unit), &"captive") if int(person.unit) >= 0 else body.get("captive")),
		"ko": float(person.owner.combat_hot_get(int(person.unit), &"ko") if int(person.unit) >= 0 else body.knockout_left),
		"kind": "army" if int(person.unit) >= 0 else "actor"}

static func _saved_person(data: TerrainData, identity: int) -> Dictionary:
	for actor: Dictionary in data.site.get("actors", {}).values():
		if int(actor.person_id) == identity:
			return {"hp": float(actor.hp), "captive": bool(actor.captive), "ko": float(actor.knockout_left), "kind": "actor"}
	for team: Dictionary in data.site.get("armies", []):
		for row: Dictionary in team.units:
			if int(row.person_id) == identity:
				return {"hp": float(row.hp), "captive": bool(row.captive), "ko": float(row.ko), "kind": "army"}
	return {}

func _source(site_reference: Dictionary) -> Dictionary:
	if resolve_owner.is_valid():
		var resolved: Variant = resolve_owner.call(site_reference.duplicate(true))
		if not resolved is Dictionary or not resolved.get("ok") is bool: return Runtime.fail("NO_SOURCE", "原人物擁有者查核回傳無效")
		return resolved
	if str(site_reference.site_id) == str(lab.terrain.site.id):
		return Runtime.ok("", {"data": lab.terrain, "local": true})
	if str(site_reference.path).is_empty() or not load_site_query.is_valid():
		return Runtime.fail("NO_SOURCE", "異地人物尚無可讀取的原 Site 快照")
	var result: Dictionary = load_site_query.call(str(site_reference.path))
	if not bool(result.get("ok", false)):
		return result
	if not result.get("data") is TerrainData or str(result.data.site.get("id", "")) != str(site_reference.site_id):
		return Runtime.fail("STALE_SITE", "快照不是該家人的原 Site；未替換目前場景")
	return Runtime.ok("", {"data": result.data, "local": false})

func _observation(member_reference: Dictionary, source: Dictionary) -> Dictionary:
	var result := member_reference.duplicate(true)
	result.merge({"status": "UNKNOWN", "selectable": false, "message": "", "kind": ""})
	if not bool(source.get("ok", false)):
		result.message = str(source.get("message", "原人物資料不可讀取"))
		result.code = str(source.get("code", "NO_SOURCE"))
		return result
	var person: Dictionary = source.get("person", {}) if source.has("person") else (_current_person(int(member_reference.person_id)) if bool(source.get("local", false)) else _saved_person(source.data, int(member_reference.person_id)))
	if person.is_empty():
		result.message = "已驗證快照中找不到原人物；不視為死亡"
		result.code = "NO_PERSON"
		return result
	result.merge(person)
	result.status = "ALIVE" if float(person.hp) > 0.0 else "DEAD"
	result.selectable = float(person.hp) > 0.0 and not (str(member_reference.site_id) == str(lab.terrain.site.id) and int(member_reference.person_id) == _controlled_id())
	result.code = "OK"
	return result

func _inspect_family(family: Dictionary) -> Dictionary:
	var observations: Array = []
	var groups := {}
	for member: Dictionary in family.members:
		var key := [str(member.site_id), str(member.path)]
		if not groups.has(key):
			groups[key] = []
		groups[key].append(member)
	var living := 0
	var unknown := 0
	# Explicit panel refresh/registration only, never death_tick or 120 Hz.
	# One validated Site at a time; don't retain full remote maps as a family DB.
	for references: Array in groups.values():
		var source := _source(references[0])
		for member_reference: Dictionary in references:
			var observation := _observation(member_reference, _source(member_reference) if resolve_owner.is_valid() else source)
			observations.append(observation)
			var self_reference: bool = str(member_reference.site_id) == str(lab.terrain.site.id) and int(member_reference.person_id) == _controlled_id()
			if not self_reference:
				living += int(str(observation.status) == "ALIVE")
				unknown += int(str(observation.status) == "UNKNOWN")
	var current := _current_person(_controlled_id())
	var dead := not current.is_empty() and float(current.hp) <= 0.0
	var status := "ALIVE" if not dead else "CHOOSE"
	if current.is_empty():
		status = "DATA_MISSING"
	elif dead and living == 0:
		status = "GAME_OVER" if bool(family.complete) and unknown == 0 else "DATA_MISSING"
	return Runtime.ok("", {"status": status, "complete": bool(family.complete), "members": observations,
		"living_relatives": living, "unknown_relatives": unknown, "controlled_person_id": _controlled_id()})

func inspect() -> Dictionary:
	if not lab.terrain.site.has("family"):
		return Runtime.ok("家族尚未登錄；不能據此判定無人在世", {"status": "UNREGISTERED", "members": [], "complete": false})
	var family: Variant = lab.terrain.site.family
	if not validate_family(family, str(lab.terrain.site.id)):
		return Runtime.fail("INVALID_FAMILY", "家族引用名單無效；未改變控制人物")
	return _inspect_family(family)

func register_members(members: Array, complete: bool, requester_id: int = -1) -> Dictionary:
	# Called only by an explicit user registration UI. Never infer kinship from
	# factions, proximity, node names, or a newly spawned demonstration roster.
	var family := {"version": 1, "complete": complete, "members": members.duplicate(true)}
	var offices := family_offices(lab.terrain.site.get("family", {})).duplicate(true)
	if not offices.is_empty():
		# Established family: the registry is family.roster, manual-only (D15).
		var resolved := duty_resolve("family.roster")
		if not bool(resolved.ok): return Runtime.fail(str(resolved.code), str(resolved.get("message", "")))
		if int(resolved.decider) != requester_id or requester_id != _controlled_id():
			return SiteOffices.refusal(resolved, requester_id, offices)
		var kept := {}
		for member: Variant in members:
			if member is Dictionary and _integer(member.get("person_id"), 1, 2147483647): kept[int(member.person_id)] = true
		SiteOffices.vacate_unless(offices, func(identity: int) -> bool: return kept.has(identity))
		family.version = 2
		family.offices = offices
	var previous: Dictionary = lab.terrain.site.get("family", {})
	if int(previous.get("version", 1)) == 4:
		# Version 4 keeps its identity through every roster rewrite (offices already carried above).
		family.version = 4
		family.name = previous.name
		family.lineage_id = previous.lineage_id
		family.offices = offices
	if int(previous.get("version", 1)) == 3:
		family.version = 3
		family.family_id = previous.family_id
		family.technology = previous.technology.duplicate(true)
		family.offices = offices
		for project: Dictionary in family.technology.projects:
			if bool(project.closed) or project.executor.is_empty(): continue
			var kept := false
			for member: Dictionary in family.members:
				if str(member.site_id) == str(project.executor.site_id) and int(member.person_id) == int(project.executor.person_id): kept = true
			if not kept: return Runtime.fail("BUSY", "先沿原科技 owner 收束現任研究者，不能由名冊刪除其原專案")
	if not validate_family(family, str(lab.terrain.site.id)):
		return Runtime.fail("INVALID_FAMILY", "請登錄不重複的原 Site／人物引用；未知年齡填 -1")
	var checked := _inspect_family(family)
	for member: Dictionary in checked.members:
		if str(member.status) == "UNKNOWN":
			return Runtime.fail(str(member.code), "無法確認原人物，不會新增虛構家人：" + str(member.message))
	lab.terrain.site.family = family
	return Runtime.ok("已明確登錄既有人物；沒有建立人物、親屬身體或財物")

func death_tick() -> Dictionary:
	var identity := _controlled_id()
	var person := _current_person(identity)
	if person.is_empty():
		return Runtime.fail("NO_CONTROL_OWNER", "受控原人物不存在；不視為死亡或 Game Over")
	if float(person.hp) > 0.0:
		_seen_death.clear()
		return Runtime.ok("", {"status": "ALIVE", "changed": false, "person_id": identity})
	var key := [str(lab.terrain.site.id), identity]
	var changed := _seen_death != key
	_seen_death = key
	# Root pauses the selection UI after original committed death work settles.
	# No offline catch-up, forced combat-clock reset, or implicit second clock.
	return Runtime.ok("原受控人物已死亡", {"status": "DEAD", "changed": changed, "person_id": identity})

func choose(site_id: String, identity: int) -> Dictionary:
	var current := _current_person(_controlled_id())
	if current.is_empty() or float(current.hp) > 0.0:
		return Runtime.fail("NOT_DEAD", "只有原受控人物真正死亡後才能接續；昏迷或被俘不適用")
	var family: Variant = lab.terrain.site.get("family")
	if not validate_family(family, str(lab.terrain.site.id)):
		return Runtime.fail("INVALID_FAMILY", "家族未登錄或資料不足；保留目前人物")
	var selected := {}
	for member: Dictionary in family.members:
		if str(member.site_id) == site_id and int(member.person_id) == identity:
			selected = member
			break
	if selected.is_empty() or (site_id == str(lab.terrain.site.id) and identity == _controlled_id()):
		return Runtime.fail("NO_HEIR", "請選擇已明確登錄的另一位原家人")
	var source := _source(selected)
	if not source.ok:
		return source
	var observation := _observation(selected, source)
	if str(observation.status) != "ALIVE":
		return Runtime.fail("NO_HEIR", "原家人已死亡或資料不足；不製造新的接續人物")
	if commit_control_transition.is_valid():
		var committed: Variant = commit_control_transition.call(selected.duplicate(true), source, family.duplicate(true))
		if not committed is Dictionary or not committed.get("ok") is bool: return Runtime.fail("INVALID_TRANSITION", "原控制交易未回傳有效結果")
		return committed
	if not control_selected.is_valid():
		return Runtime.fail("UNSUPPORTED", "尚未接好原人物控制入口")
	if not bool(source.local):
		if not archive_current.is_valid():
			return Runtime.fail("UNSUPPORTED", "尚未接好原 Site 的安全歸檔入口")
		var saved: Dictionary = archive_current.call()
		if not bool(saved.get("ok", false)):
			return saved # Including BUSY: selection stays; never delete old remains.
		# Carry only the explicit reference registry, not old HP/cargo/office data.
		source.data.site.family = family.duplicate(true)
	return control_selected.call(null if bool(source.local) else source.data, identity)
