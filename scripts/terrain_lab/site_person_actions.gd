class_name SitePersonActions
extends RefCounted
## Commands reference original people and sparse holders; no surrogate bodies.
## advance() is before contact/life settlement; only settle_after_contacts commits.

const CrowdOwner = preload("res://scripts/terrain_lab/crowd_person_owner.gd")
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const PersonSocial = preload("res://scripts/terrain_lab/person_social.gd")
const SiteSocial = preload("res://scripts/terrain_lab/site_social.gd")
const Housing = preload("res://scripts/terrain_lab/site_housing.gd")
const Settlement = preload("res://scripts/terrain_lab/site_settlement.gd")
const Fatigue = preload("res://scripts/terrain_lab/person_fatigue.gd")
const Technology = preload("res://scripts/terrain_lab/site_technology.gd")
const TechnologyCatalog = preload("res://scripts/terrain_lab/site_technology_catalog.gd")
const Family = preload("res://scripts/terrain_lab/site_family_continuity.gd")
const LOOSE_BASE_SECONDS := 2.0
const LOOSE_ITEM_SECONDS := 0.2
const REMOVE_SECONDS := 5.0
const BIND_SECONDS := 4.0
const GUARD_CAPACITY := 4
const GUARD_STEPS := 4
const RANSOM_RATIONS := 100
const RANSOM_SECONDS := 10.0
const ESCAPE_SECONDS := 30.0
const TENT_SECONDS := 30.0
const FOODS := ["fish", "meat", "wild_food", "grain"]

var lab: Variant
var equipment_removal_guard: Callable # (person_id, item_ids) -> typed result; pure.
var equipment_changed: Callable # (person_id); synchronous original visual/hit update.
var opened_food_pool: Callable # (person_id) -> the original private food pool, or empty.
var opened_food_commit: Callable # (person_id, amount, original pool); infallible after checks.
var captivity_change_guard: Callable # (target_id, captor_id, capturing) -> pure result.
var captivity_supply_commit: Callable # Same arguments; fully prevalidated, no failure/yield.
var captivity_changed: Callable # Same arguments; prepared commit must not fail/yield.
var ransom_exchange_query: Callable # (payer, captive, representative) -> original inventories/owners/revisions.
var ransom_exchange_committed: Callable # (query); only synchronous owner revision notification.
var equipment_orders: Variant # Thin rules provider; this remains the only job clock.
var _results: Array[Dictionary] = []
var _jobs: Dictionary = {} # Active commands are transient; save_guard refuses them.
var _technology_source_refs: Dictionary = {} # Derived original-object references, never budgets or saved authority.

func init(owner: Variant) -> void:
	discard_checked_controlled_prefixes()
	_gd_contact_job_capture = {}
	_gd_contact_job_segment = {}
	lab = owner
	lab.terrain.set_meta(&"site_person_actions", weakref(self))
	_jobs.clear()
	end_shared_work_prefix_consumption()
	_prepared_controlled_features.clear()
	_controlled_feature_consumed.clear()
	_controlled_feature_allocation = {}
	_controlled_feature_seconds = 0.0
	_results.clear()
	_technology_source_refs.clear()
	_rebind_technology_sources()
	_rebind_scope_technology_sources()
	_next_fire_job_token = 1
	# Explicit new/legacy-empty initialization; keep original captivity records.
	if not lab.terrain.site.has("captivity"):
		lab.terrain.site["captivity"] = {}

func crowd_action_guard(identities: Array) -> Dictionary:
	if not is_instance_valid(lab):
		return Runtime.ok()
	var crowd: Variant = lab.get("crowd_site")
	if crowd != null and bool(crowd.active):
		for identity: Variant in identities:
			if crowd.contains_person(int(identity)):
				return Runtime.fail("CROWD_ACTIVE", "群眾戰鬥中由戰場規則處理")
	return Runtime.ok()

func is_busy(identity: int) -> bool:
	return not _job_key_for(identity).is_empty()

func _job_key_for(identity: int) -> String:
	var direct := str(identity)
	if _jobs.has(direct): return direct
	for key: String in _jobs:
		var job: Dictionary = _jobs[key]
		if str(job.kind) in ["technology_lesson", "captive_craft"] and int(job.target_id) == identity: return key
		if str(job.kind) == "equipment" and str(job.order.mode) == "team_issue" and job.order.target_ids.has(identity):
			return key
	return ""

func equipment_conflict(identity: int, order: Dictionary = {}) -> bool:
	var key := _job_key_for(identity)
	if key.is_empty(): return false
	var job: Dictionary = _jobs[key]
	return order.is_empty() or str(job.kind) != "equipment" or not is_same(job.order, order)

func has_active_issue(order: Dictionary = {}) -> bool:
	for job: Dictionary in _jobs.values():
		if str(job.kind) == "equipment" and str(job.order.mode) in ["issue", "team_issue"] and (order.is_empty() or not is_same(job.order, order)):
			return true
	return false

func save_guard() -> Dictionary:
	return Runtime.ok() if _jobs.is_empty() else Runtime.fail("BUSY", "人物作業未完成；完成或取消後再保存")

func job_for(identity: int) -> Dictionary:
	return _jobs.get(_job_key_for(identity), {}).duplicate(true)

func is_working(identity: int) -> bool:
	var job: Dictionary = _jobs.get(_job_key_for(identity), {})
	return not job.is_empty() and str(job.paused).is_empty()

func is_guarding(identity: int) -> bool:
	for entry: Dictionary in lab.terrain.site.captivity.values():
		if int(entry.guard_id) == identity and str(entry.get("prison_id", "")).is_empty():
			return true
	return false

func has_effective_guard(identity: int) -> bool:
	var person := _person(identity)
	var entry: Dictionary = lab.terrain.site.captivity.get(str(identity), {})
	if person.is_empty() or entry.is_empty():
		return false
	if not str(entry.get("prison_id", "")).is_empty():
		return prison_slot(identity).ok
	var guard := _person(int(entry.guard_id), false)
	if guard.is_empty() or (not bool(guard.player) and bool(_body_get(guard, "work_resting"))):
		return false
	var capable: bool = guard.owner.combat_can_act(int(guard.unit)) if int(guard.unit) >= 0 else guard.owner.can_act()
	return capable and int(guard.faction) == int(entry.captor_faction) and _within_guard_range(guard.cell, person.cell)

func prison_contacts(prison_id: String, participant_ids: Array = []) -> Array[Dictionary]:
	var identities := participant_ids.duplicate()
	for key: String in lab.terrain.site.captivity:
		if str(lab.terrain.site.captivity[key].get("prison_id", "")) == prison_id and prison_slot(int(key)).ok and not identities.has(int(key)):
			identities.append(int(key))
	var contacts: Array[Dictionary] = []
	for identity: int in identities:
		var person := _person(identity, false)
		if person.is_empty() or not person.owner is CrowdOwner or not _prison_stopped(person): continue
		var native: Dictionary = person.owner.crowd_site.soldier_state(int(person.unit))
		if absf(float(native.px) - (float(person.cell.x) + 0.5)) > 0.00001 or absf(float(native.py) - (float(person.cell.y) + 0.5)) > 0.00001: continue
		contacts.append(person)
	return contacts

func prison_blocked(cell: Vector2i, ignored_ids: Array = [], contacts: Array[Dictionary] = []) -> bool:
	if not lab.terrain.is_walkable(cell): return true
	var controller: Variant = lab.get("site_controller")
	if controller != null and controller.vehicles != null and controller.vehicles.blocks_cell(cell): return true
	var crowd: Variant = lab.get("crowd_site")
	var native_ignored := ignored_ids.duplicate()
	for person: Dictionary in contacts:
		# Only stopped, centred participants and valid inmates lose the conservative
		# adjacent safety margin. Their actual cell remains reserved for every route.
		if cell == person.cell and not ignored_ids.has(int(person.person_id)): return true
		native_ignored.append(int(person.person_id))
	if crowd != null and bool(crowd.active) and crowd.reserves_cell(cell, native_ignored): return true
	for team: TerrainArmy in lab.combat_armies:
		if crowd != null and bool(crowd.active) and crowd.owns_original_team(team): continue
		if not team.reserves_terrain_cell(cell): continue
		# Read the original reservation owners, including swept movement leases.
		var own := false
		for claims: Dictionary in [team._cell_owners, team._reserved_cells]:
			if claims.has(cell):
				if not ignored_ids.has(team.combat_identity(int(claims[cell]))): return true
				own = true
		if not own or team._passage_cell_is_protected(cell): return true
	for actor: TerrainTestCharacter in lab.combat_actors:
		if crowd != null and bool(crowd.active) and crowd.contains_person(int(actor.person_id)): continue
		if not ignored_ids.has(int(actor.person_id)) and actor.occupies_cell(cell): return true
	return false

func _prison_stopped(person: Dictionary) -> bool:
	if person.is_empty() or bool(person.moving): return false
	if person.owner is CrowdOwner:
		var state: PackedInt64Array = person.owner.crowd_site.crowd.escort_state(int(person.unit))
		return state.size() == 2 and int(state[1]) < 0 and int(state[0]) != 2
	return true

func prison_slot(identity: int) -> Dictionary:
	var relation: Dictionary = lab.terrain.site.captivity.get(str(identity), {})
	var key := str(relation.get("prison_id", ""))
	var person := _person(identity, false)
	if key.is_empty() or person.is_empty() or float(person.hp) <= 0.0 or not bool(person.captive):
		return Runtime.fail("NO_TARGET", "沒有原在監人物")
	var layout := Runtime.prison_layout(lab.terrain, key)
	if not layout.ok or not bool(layout.get("complete", false)):
		return Runtime.fail("INVALID_PRISON", "原戰俘營已失效")
	for slot: Dictionary in layout.slots:
		if slot.cell == person.cell and lab.terrain.can_step(slot.cell, slot.contact_cell):
			if person.owner is CrowdOwner:
				var native: Dictionary = person.owner.crowd_site.soldier_state(int(person.unit))
				if int(native.get("prison_id", 0)) != int(key): return Runtime.fail("INVALID_PRISON", "原生拘押關係不符")
			return Runtime.ok("", {"prison_id": key, "slot": slot, "person": person, "relation": relation, "layout": layout})
	return Runtime.fail("INVALID_PRISON", "原人物不在合法拘押格")

func prison_query(requester_id: int, prison_id: String) -> Dictionary:
	var layout := Runtime.prison_layout(lab.terrain, prison_id)
	if not layout.ok: return layout
	var inmates: Array[Dictionary] = []
	var officers: Array[Dictionary] = []
	var occupied := {}
	for key: String in lab.terrain.site.captivity:
		if str(lab.terrain.site.captivity[key].get("prison_id", "")) != prison_id: continue
		var original := prison_slot(int(key))
		if not original.ok: return original
		var person: Dictionary = original.person
		if occupied.has(person.cell): return Runtime.fail("INVALID_PRISON", "拘押格重複")
		occupied[person.cell] = true
		inmates.append({"person_id": int(key), "cell": person.cell, "hp": float(person.hp), "ko": float(person.ko)})
		var officer := _prison_officer(person)
		if not officer.is_empty(): officers.append(officer)
	var reserved_officers := 0
	var reserved_regular := 0
	for order: Dictionary in lab.terrain.site.get("escort_orders", {}).values():
		if str(order.get("prison_id", "")) == prison_id:
			for identity: String in order.get("targets", {}):
				occupied[lab.terrain.cell_from_index(int(order.targets[identity]))] = true
				if _prison_officer(_person(int(identity), false)).is_empty(): reserved_regular += 1
				else: reserved_officers += 1
	var free_slots: Array[Dictionary] = []
	var contacts := prison_contacts(prison_id, [requester_id])
	if bool(layout.complete):
		for slot: Dictionary in layout.slots:
			if not occupied.has(slot.cell) and not prison_blocked(slot.cell, [], contacts) and not prison_blocked(slot.contact_cell, [requester_id], contacts) and lab.terrain.can_step(slot.cell, slot.contact_cell):
				free_slots.append(slot)
	var reasons: Array[String] = []
	if not bool(layout.complete): reasons.append("戰俘營尚未完工")
	if free_slots.is_empty(): reasons.append("沒有可到達且未占用的拘押格")
	return Runtime.ok("原人物拘押狀態", {"prison_id": prison_id, "complete": bool(layout.complete), "capacity": int(layout.capacity),
		"inmates": inmates, "officers": officers, "officer_count": officers.size(), "regular_count": inmates.size() - officers.size(),
		"used": inmates.size(), "reserved_officers": reserved_officers, "reserved_regular": reserved_regular,
		"free_slots": free_slots, "entry": layout.entry, "reasons": reasons})

func _prison_officer(person: Dictionary) -> Dictionary:
	# Qualification survives leaving an appointment, garrisoning and captivity.
	# Only a legacy row lacking the field falls back to original appointments.
	if person.is_empty(): return {}
	var identity := int(person.person_id)
	var unit := int(person.unit)
	var officer := false
	var abilities: Dictionary = {}
	var appearance: Dictionary = {}
	if person.owner is CrowdOwner:
		var owner: CrowdOwner = person.owner
		var hot: Dictionary = owner.crowd_site.soldier_state(unit)
		if hot.has("military_role"):
			if int(hot.military_role) != 1: return {}
			officer = true
		var formation: Dictionary = owner.crowd_site.formation_state(int(owner.formation_index))
		for field: String in ["formal_person", "acting_person", "current_person"]:
			officer = officer or int(formation.get(field, -1)) == identity
		officer = officer or formation.get("officer_persons", []).has(identity)
		var roster: Dictionary = owner.crowd_site.team_record(int(owner.formation_index))
		var rows: Array = roster.get("units", [])
		for index: Variant in roster.get("officer_service", []) + roster.get("officers", []):
			var original_id := int(roster.get("player_member", {}).get("id", -1)) if int(index) == TerrainArmy.PLAYER_MEMBER else (int(rows[int(index)].person_id) if int(index) >= 0 and int(index) < rows.size() else -1)
			officer = officer or original_id == identity
		if not officer: return {}
		if int(hot.get("tactics", -1)) >= 0:
			abilities = {"tactics": int(hot.tactics), "leadership": int(hot.leadership), "coach": int(hot.coach)}
		appearance = owner.combat_hot_get(unit, &"appearance", {})
	else:
		var qualification: Variant = person.body.get("military_role")
		if qualification != null:
			if str(qualification) != "officer": return {}
			officer = true
		for team: TerrainArmy in lab.combat_armies:
			var index := team.index_for_identity(identity)
			if not team.combat_enabled or not team.is_member(index): continue
			if officer or index in [team.formal_commander, team.acting_commander, team.current_commander] or team.officer_service.has(index) or team.officer_order.has(index):
				officer = true
				abilities = person.body.command_abilities if index == TerrainArmy.PLAYER_MEMBER else team.command_abilities.get(index, {})
				break
		if not officer: return {}
		if unit < 0: abilities = person.owner.command_abilities
		appearance = person.body.get("appearance", {}) if unit >= 0 else person.owner._saved_appearance
	return {"person_id": identity, "cell": person.cell, "hp": float(person.hp), "ko": float(person.ko),
		"command_abilities": abilities.duplicate(true), "appearance": Runtime.equipment_appearance(lab.terrain, person.holder, appearance)}

func admit_prison(guard_id: int, target_id: int, prison_id: String) -> Dictionary:
	var guard := _person(guard_id)
	var target := _person(target_id)
	var relation: Dictionary = lab.terrain.site.captivity.get(str(target_id), {})
	var layout := Runtime.prison_layout(lab.terrain, prison_id)
	if not layout.ok or not bool(layout.get("complete", false)) or relation.is_empty() or not str(relation.get("prison_id", "")).is_empty():
		return Runtime.fail("NO_TARGET", "原拘押人物或已完工戰俘營不符")
	if int(relation.guard_id) != guard_id or not _ready(guard, true) or not _prison_stopped(guard) or target.is_empty() or float(target.hp) <= 0.0 or float(target.ko) > 0.0 or not bool(target.captive) or not _prison_stopped(target):
		return Runtime.fail("BUSY", "原看守與原俘虜須清醒並完成真實步進")
	if int(guard.faction) != int(relation.captor_faction): return Runtime.fail("AUTHORITY")
	var prison_owner := int(lab.terrain.site.features[prison_id].get("owner_faction", -1))
	if prison_owner >= 0 and int(guard.faction) != prison_owner: return Runtime.fail("AUTHORITY", "須由戰俘營管理方看守入監")
	var contacts := prison_contacts(prison_id, [guard_id, target_id])
	for slot: Dictionary in layout.slots:
		if target.cell != slot.cell or guard.cell != slot.contact_cell: continue
		if not _adjacent(guard.cell, target.cell) or prison_blocked(target.cell, [target_id], contacts) or prison_blocked(guard.cell, [guard_id], contacts): return Runtime.fail("OCCUPIED")
		if target.owner is CrowdOwner or guard.owner is CrowdOwner:
			if not target.owner is CrowdOwner or not guard.owner is CrowdOwner or not bool(target.owner.crowd_site.crowd.admit_prison(int(target.unit), int(guard.unit), int(prison_id), lab.terrain.index(slot.cell), lab.terrain.index(slot.contact_cell))):
				return Runtime.fail("BUSY", "原生人物尚未完成入監接觸")
		relation.prison_id = prison_id
		relation.admitted_at_game_seconds = Runtime.now(lab.terrain) * 60.0 # F02 / plan 6.1: true admission time, saved.
		return Runtime.ok("原俘虜已入監；原供養者與隨身物不變", {"person_id": target_id})
	return Runtime.fail("UNREACHABLE", "須先真實行走至拘押格與接觸格")

## v2 plan 4.2 / 6.1-6.2: a new capture's persistent fields (captivity v3). The
## episode is the person reference plus that person's own capture sequence
## (social_state v1, bumped here). The loyal organization (nation if a member,
## else the team) and the rank are snapshotted now and never re-pointed for this
## captivity, even if the person later moves teams or loses a post.
func capture_fields(target_id: int, target: Dictionary) -> Dictionary:
	var data: TerrainData = lab.terrain
	var site_id := str(data.site.get("id", ""))
	var body: Variant = target.get("body")
	var sequence := PersonSocial.next_capture_seq(body)
	var loyal: Variant = null
	var rank := "commoner"
	var role := str(body.get("military_role", "soldier")) if body is Dictionary else (str(body.get("military_role")) if body is Object else "soldier")
	if role == "officer": rank = "officer"
	var owner: Variant = target.get("owner")
	var unit := int(target.get("unit", -1))
	if owner != null and unit >= 0 and owner.has_method("is_member") and owner.is_member(unit):
		loyal = {"kind": "team", "site_id": site_id, "org_id": str(owner.get("team_id"))}
		if int(owner.get("formal_commander")) == unit: rank = "head"
	elif unit < 0:
		for team: TerrainArmy in lab.combat_armies:
			if is_instance_valid(team) and team.player_member == body:
				loyal = {"kind": "team", "site_id": site_id, "org_id": str(team.team_id)}
				if team.formal_commander == TerrainArmy.PLAYER_MEMBER: rank = "head"
	var nations: Dictionary = data.site.get("equipment_nations", {})
	for nation_id: String in nations:
		if nations[nation_id].get("members", []).has(target_id):
			loyal = {"kind": "nation", "site_id": site_id, "org_id": nation_id}
			if nations[nation_id].get("offices") is Dictionary and int(SiteOffices.head_position(nations[nation_id].offices).get("holder", -1)) == target_id: rank = "head"
			break
	return {"captured_at_game_seconds": Runtime.now(data) * 60.0, "admitted_at_game_seconds": -1.0,
		"episode": {"site_id": site_id, "person_id": target_id, "seq": sequence}, "loyal_org": loyal,
		"rank_snapshot": rank, "settled_days": 0, "legacy_observed": false}

## R2 §8.2/8.3: settle complete custody days on the saved loyal organization
## before the relation is erased; a successful ransom by that organization
## records G −20 / L +1000 once (episode-deduplicated) for the next day.
func _social_before_release(target_id: int, target: Dictionary, ransomed: bool) -> void:
	var relation: Dictionary = lab.terrain.site.captivity.get(str(target_id), {})
	var body: Variant = target.get("body")
	if relation.is_empty() or body == null: return
	var minute := int(lab.terrain.site.get("minute", 0))
	SiteSocial.settle_before_release(body, relation, minute)
	if ransomed and relation.get("loyal_org") is Dictionary and relation.get("episode") is Dictionary:
		SiteSocial.record(body, relation.loyal_org, "ransomed", -20, "ransom:%s:%d:%d" % [str(relation.episode.site_id), int(relation.episode.person_id), int(relation.episode.seq)], minute, 1000)

func begin_prison_release(executor_id: int, target_id: int, requester_id: int = -1) -> Dictionary:
	if is_busy(executor_id) or bool(lab.terrain.site.get("paused", false)): return Runtime.fail("BUSY")
	var check := _prison_release_context(executor_id, target_id)
	if not check.ok: return check
	# Settlement camps: release is the settlement.prison decision (appendix D.7);
	# the executor still has to be the one at the contact cell. Default requester = executor.
	var refused: Dictionary = Settlement.prison_authority(lab, str(check.prison_id), executor_id if requester_id < 0 else requester_id)
	if not refused.is_empty(): return refused
	var executor := _person(executor_id)
	if executor.owner is CrowdOwner:
		if not bool(executor.owner.crowd_site.crowd.order_escort_step(int(executor.unit), int(executor.unit), lab.terrain.index(executor.cell))): return Runtime.fail("BUSY")
		if not _prison_stopped(_person(executor_id)):
			executor.owner.crowd_site.crowd.cancel_escort(int(executor.unit))
			return Runtime.fail("BUSY", "原人物尚在收束格內步進，停止後可重試")
	var job := _new_job(executor, "prison_release", target_id)
	job.merge({"duration": BIND_SECONDS, "source_version": int(check.person.holder.version), "target_hit": int(check.person.hit),
		"executor_hp": float(executor.hp), "target_hp": float(check.person.hp),
		"captivity": check.relation.duplicate(), "source_cell": lab.terrain.index(check.person.cell), "terrain": lab.terrain, "site_state": lab.terrain.site})
	_jobs[str(executor_id)] = job
	return Runtime.ok("開始四秒出監解綁；完成前保持原拘押", {"seconds": BIND_SECONDS})

func _prison_release_context(executor_id: int, target_id: int, job: Dictionary = {}) -> Dictionary:
	var original := prison_slot(target_id)
	if not original.ok: return original
	var target := _person(target_id)
	var executor := _person(executor_id)
	if target.is_empty() or not _ready(executor) or not _prison_stopped(executor) or not _prison_stopped(target): return Runtime.fail("BUSY")
	if float(_body_get(target, "exchange_stagger")) > 0.0 or int(target.holder.version) >= 2147483646: return Runtime.fail("BUSY")
	if int(executor.faction) not in [int(target.faction), int(original.relation.captor_faction)]: return Runtime.fail("AUTHORITY")
	if executor.cell != original.slot.contact_cell or not _adjacent(executor.cell, target.cell): return Runtime.fail("UNREACHABLE", "須到原拘押格相鄰的出監接觸格")
	if not job.is_empty() and (not is_same(job.terrain, lab.terrain) or not is_same(job.site_state, lab.terrain.site)
		or int(executor.hit) != int(job.executor_hit) or lab.terrain.index(executor.cell) != int(job.executor_cell)
		or int(target.hit) != int(job.target_hit) or lab.terrain.index(target.cell) != int(job.source_cell)
		or float(executor.hp) != float(job.executor_hp) or float(target.hp) != float(job.target_hp)
		or int(target.holder.version) != int(job.source_version) or original.relation != job.captivity): return Runtime.fail("INTERRUPTED", "原出監作業受擊、移動或關係已變更")
	var contacts := prison_contacts(str(original.prison_id), [executor_id, target_id])
	if prison_blocked(target.cell, [target_id], contacts) or prison_blocked(executor.cell, [executor_id], contacts) or prison_blocked(original.slot.exit_cell, [executor_id], contacts): return Runtime.fail("OCCUPIED", "出監出口或接觸格被占用")
	if executor.cell != original.slot.exit_cell:
		var route: Array[Vector2i] = lab.terrain.path_between(executor.cell, original.slot.exit_cell, func(cell: Vector2i) -> bool: return prison_blocked(cell, [executor_id], contacts))
		if route.is_empty(): return Runtime.fail("UNREACHABLE", "接觸格至出口沒有合法空路")
	if not captivity_change_guard.is_valid() or not captivity_supply_commit.is_valid() or not captivity_changed.is_valid(): return Runtime.fail("UNSUPPORTED")
	var check: Dictionary = captivity_change_guard.call(target_id, int(original.relation.captor_id), false)
	if not check.ok: return check
	original.person = target
	return original

func _commit_prison_release(job: Dictionary) -> Dictionary:
	if not _gd_custody_native(job): return _commit_gd_custody_terminal(job)
	var check := _prison_release_context(int(job.executor_id), int(job.target_id), job)
	if not check.ok: return check
	var target: Dictionary = check.person
	var executor := _person(int(job.executor_id))
	if target.owner is CrowdOwner or executor.owner is CrowdOwner:
		if not target.owner is CrowdOwner or not executor.owner is CrowdOwner or not bool(target.owner.crowd_site.crowd.release_prison(int(target.unit), int(executor.unit), int(check.prison_id), lab.terrain.index(check.slot.contact_cell), lab.terrain.index(check.slot.exit_cell))): return Runtime.fail("BUSY", "原生出監接觸已失效")
	else:
		_body_set(target, "captive", false)
	var captor_id := int(check.relation.captor_id)
	_social_before_release(int(job.target_id), target, false)
	lab.terrain.site.captivity.erase(str(job.target_id))
	target.holder.version = int(target.holder.version) + 1
	captivity_supply_commit.call(int(job.target_id), captor_id, false)
	if equipment_changed.is_valid(): equipment_changed.call(int(job.target_id))
	captivity_changed.call(int(job.target_id), captor_id, false)
	return Runtime.ok("已出監解綁；生命、昏迷、位置與實物維持原值")

func _release_work_hold(job: Dictionary) -> void:
	if str(job.get("kind", "")) == "fire_suppress":
		if is_instance_valid(job.executor_owner): job.executor_owner.release_suppress_approach(int(job.executor_id), int(job.job_token))
		if is_instance_valid(job.registry): job.registry.release_work_slot(job.lease)
		return
	if str(job.get("kind", "")) != "prison_release": return
	var executor := _person(int(job.executor_id), false)
	if not executor.is_empty() and executor.owner is CrowdOwner:
		executor.owner.crowd_site.crowd.cancel_escort(int(executor.unit))

func cancel(identity: int) -> Dictionary:
	var key := _job_key_for(identity)
	if key.is_empty():
		return Runtime.fail("NO_TARGET", "沒有未完成的人物作業")
	if str(_jobs[key].kind) == "fire_suppress":
		_cancel_fire_suppress(_jobs[key], Runtime.ok("已取消未提交滅火；原已承諾步進完成後釋放"))
		_settle_cancelled_fire_suppress(key, _jobs[key])
		return Runtime.ok("已取消；原半步仍由原移動協調器收束")
	if str(_jobs[key].kind) == "housing_return":
		_cancel_housing_job(_jobs[key])
		return Runtime.ok("已取消後續返家；原已承諾步進收束後即可保存")
	if str(_jobs[key].kind) in ["ship_helm", "ship_walk", "ship_cross", "ship_evac"]:
		_jobs[key].cancelled = true
		return Runtime.ok("已取消接手意圖；已承諾通路仍完成到駕駛席再停")
	_release_work_hold(_jobs[key])
	_jobs.erase(key)
	return Runtime.ok("已取消；未完成批次沒有轉移物品")

func lootable(executor_id: int, source_kind: String, source_id: String) -> Dictionary:
	var crowd_guard := crowd_action_guard([executor_id, int(source_id) if source_kind == "person" and source_id.is_valid_int() else -1])
	if not crowd_guard.ok:
		return crowd_guard
	var executor := _person(executor_id)
	var source := _source(source_kind, source_id)
	var check := _loot_context(executor, source)
	if not check.ok:
		return check
	# Copies for a read-only panel, never adopted as inventory owners.
	return Runtime.ok("目前實際持有物", {"resources": source.cargo.duplicate(),
		"item_ids": source.holder.item_ids.duplicate(), "equipped": source.holder.equipped.duplicate(),
		"version": int(source.holder.version)})

func begin_loot(executor_id: int, source_kind: String, source_id: String, resources: Dictionary, item_ids: Array, open_amount: float = 0.0) -> Dictionary:
	var crowd_guard := crowd_action_guard([executor_id, int(source_id) if source_kind == "person" and source_id.is_valid_int() else -1])
	if not crowd_guard.ok:
		return crowd_guard
	if is_busy(executor_id):
		return Runtime.fail("BUSY", "先完成或取消原人物作業")
	var executor := _person(executor_id)
	var source := _source(source_kind, source_id)
	var check := _loot_context(executor, source)
	if not check.ok:
		return check
	check = _selection(executor, source, resources, item_ids, open_amount)
	if not check.ok:
		return check
	var worn := false
	for identity: String in item_ids:
		worn = worn or source.holder.equipped.values().has(identity)
	if worn and (item_ids.size() != 1 or not resources.is_empty() or open_amount > 0.0):
		return Runtime.fail("INVALID", "穿戴物品每批只能卸下一件，不混合散物")
	check = _removal_guard(source, item_ids)
	if not check.ok:
		return check
	var job := _new_job(executor, "loot", int(source.get("person_id", 0)))
	job.merge({"source_kind": source_kind, "source_id": source_id,
		"source_version": int(source.holder.version), "destination_version": int(executor.holder.version),
		"source_holder": source.holder, "source_cargo": source.cargo,
		"destination_holder": executor.holder, "destination_cargo": executor.cargo,
		"open_amount": open_amount, "source_open": float(source.holder.get("open_rations", 0.0)),
		"destination_pool": opened_food_pool.call(executor_id) if open_amount > 0.0 else {},
		"resources": resources.duplicate(), "item_ids": item_ids.duplicate(),
		"source_cell": lab.terrain.index(source.cell), "target_hit": int(source.get("hit", -1)),
		"duration": REMOVE_SECONDS if worn else LOOSE_BASE_SECONDS + LOOSE_ITEM_SECONDS * (Runtime.inventory_size(resources) + item_ids.size() + open_amount)})
	_jobs[str(executor_id)] = job
	return Runtime.ok("開始搜刮；完成前物品仍在來源", {"seconds": job.duration})

func begin_structure_attack(executor_id: int, feature_key: String, part_id: String) -> Dictionary:
	if is_busy(executor_id) or bool(lab.terrain.site.get("paused", false)): return Runtime.fail("BUSY")
	var check := _structure_attack_context(executor_id, feature_key, part_id)
	if not check.ok: return check
	var executor: Dictionary = check.person
	var owner: Variant = executor.owner
	var unit := int(executor.unit)
	var duration := SiteCombatRules.EXCHANGE_ROUND_SECONDS
	if owner is CrowdOwner:
		if not bool(owner.crowd_site.crowd.begin_structure_strike(unit, lab.terrain.index(check.target_cell))): return Runtime.fail("BUSY")
	elif unit >= 0:
		if not owner.exchange_ready(unit): return Runtime.fail("BUSY")
		owner.combat_hot_set(unit, &"exchange_cooldown", duration)
		owner.combat_hot_set(unit, &"exchange_stagger", duration)
		owner.facing[unit] = check.target_cell - executor.cell
		owner._begin_exchange_visual(unit, str(SiteCombatRules.exchange_attack_clip(check.weapon)))
		Fatigue.charge(executor.body, SiteCombatRules.EXCHANGE_FATIGUE)
	else:
		if not owner.exchange_ready(): return Runtime.fail("BUSY")
		owner.exchange_cooldown = duration
		owner.exchange_stagger = duration
		owner.action_time = duration
		owner.face_cell(check.target_cell)
		owner._start_exchange_visual(SiteCombatRules.exchange_attack_clip(check.weapon))
		Fatigue.charge(owner, SiteCombatRules.EXCHANGE_FATIGUE)
	var job := _new_job(executor, "structure_attack", -1)
	job.merge({"duration": duration, "feature": feature_key, "part": part_id, "feature_owner": check.feature_owner,
		"weapon": check.weapon, "weapon_id": check.weapon_id, "executor_hp": float(executor.hp),
		"terrain": lab.terrain, "site_state": lab.terrain.site})
	_jobs[str(executor_id)] = job
	Runtime.mark_combat(lab.terrain, 10.0)
	return Runtime.ok("開始攻擊原建築部件", {"seconds": duration})

func _structure_attack_context(identity: int, key: String, part_id: String, job: Dictionary = {}) -> Dictionary:
	var person := _person(identity)
	var feature: Dictionary = lab.terrain.site.features.get(key, {})
	if person.is_empty() or float(person.hp) <= 0.0 or float(person.ko) > 0.0 or bool(person.captive) or bool(person.moving): return Runtime.fail("BUSY")
	var can_act: bool = person.owner.combat_can_act(int(person.unit)) if int(person.unit) >= 0 else person.owner.can_act()
	if not can_act or is_guarding(identity) or lab.site_controller.vehicles.is_siege_crew(identity): return Runtime.fail("BUSY")
	if str(feature.get("stage", "")) != "complete": return Runtime.fail("NO_TARGET")
	if int(feature.get("owner_faction", -1)) == int(person.faction): return Runtime.fail("AUTHORITY", "己方建物請使用受保護的拆除命令")
	var part: Dictionary = Runtime.feature_geometry(lab.terrain, feature).parts.get(part_id, {})
	if part.is_empty() or float(part.hp) <= 0.0: return Runtime.fail("NO_TARGET")
	var weapon_id := str(person.holder.equipped.get("weapon", ""))
	var record: Dictionary = lab.terrain.site.item_records.get(weapon_id, {})
	var definition: Dictionary = lab.terrain.site.item_definitions.get(str(record.get("definition", "")), {})
	var weapon := str(definition.get("asset", "none"))
	if weapon_id.is_empty() or not person.holder.item_ids.has(weapon_id) or str(record.get("holder", "")) != str(person.holder.holder) or weapon == "none" or SiteCombatRules.WeaponMaterials.is_ranged(StringName(weapon)):
		return Runtime.fail("INVALID_WEAPON", "須用本人實際裝備的近戰武器破壞結構")
	if not job.is_empty() and (not is_same(job.terrain, lab.terrain) or not is_same(job.site_state, lab.terrain.site)
		or not is_same(job.feature_owner, feature) or int(person.hit) != int(job.executor_hit) or float(person.hp) < float(job.executor_hp)
		or lab.terrain.index(person.cell) != int(job.executor_cell) or weapon_id != str(job.weapon_id) or weapon != str(job.weapon)):
		return Runtime.fail("INTERRUPTED", "攻擊者、原部件、武器或位置已變更")
	var height: int = lab.terrain.effective_height(person.cell)
	for index: int in part.cells:
		var target: Vector2i = lab.terrain.cell_from_index(index)
		if absi(target.x - person.cell.x) + absi(target.y - person.cell.y) != 1: continue
		# A solid face can be struck from its side without being a walkable edge.
		if height < int(feature.level) - 1 or height > maxi(int(part.height), int(feature.level) + 2): continue
		return Runtime.ok("", {"person": person, "feature_owner": feature, "target_cell": target, "weapon": weapon, "weapon_id": weapon_id, "material": str(feature.get("material", "stone" if str(feature.get("kind", "")) == "stone_wall" else "wood"))})
	return Runtime.fail("UNREACHABLE", "須到原部件相鄰且高度可接觸的位置")

func advance_structure_attacks(action_seconds: float) -> void:
	if not is_finite(action_seconds) or action_seconds <= 0.0 or bool(lab.terrain.site.get("paused", false)): return
	for key: String in _jobs.keys():
		var job: Dictionary = _jobs[key]
		if str(job.kind) not in ["structure_attack", "vehicle_attack", "siege_takeover"]: continue
		var check := _job_context(job)
		if not check.ok:
			_finish(key, check)
			continue
		job.elapsed = minf(float(job.duration), float(job.elapsed) + action_seconds)

func begin_vehicle_attack(executor_id: int, vehicle_id: String) -> Dictionary:
	var native_site: Variant = lab.get("crowd_site")
	var native_owner: Variant = native_site.person_owner(executor_id) if native_site != null and native_site.active else null
	var guard: Dictionary = Runtime.ok() if native_owner is CrowdOwner else crowd_action_guard([executor_id])
	if not guard.ok: return guard
	if is_busy(executor_id) or bool(lab.terrain.site.get("paused", false)): return Runtime.fail("BUSY")
	var check := _vehicle_attack_context(executor_id, vehicle_id)
	if not check.ok: return check
	var executor: Dictionary = check.person
	var unit := int(executor.unit)
	var duration := float(SiteCombatRules.EXCHANGE_ROUND_SECONDS)
	if executor.owner is CrowdOwner:
		if not bool(executor.owner.crowd_site.crowd.begin_structure_strike(unit, lab.terrain.index(check.target_cell))): return Runtime.fail("BUSY")
	elif unit >= 0:
		if not executor.owner.exchange_ready(unit): return Runtime.fail("BUSY")
		executor.owner.combat_hot_set(unit, &"exchange_cooldown", duration)
		executor.owner.combat_hot_set(unit, &"exchange_stagger", duration)
		var attack_direction: Vector2i = check.target_cell - executor.cell
		if attack_direction != Vector2i.ZERO: executor.owner.facing[unit] = attack_direction
		executor.owner._begin_exchange_visual(unit, str(SiteCombatRules.exchange_attack_clip(check.weapon)))
		Fatigue.charge(executor.body, SiteCombatRules.EXCHANGE_FATIGUE)
	else:
		if not executor.owner.exchange_ready(): return Runtime.fail("BUSY")
		executor.owner.exchange_cooldown = duration
		executor.owner.exchange_stagger = duration
		executor.owner.face_cell(check.target_cell)
		executor.owner._start_exchange_visual(SiteCombatRules.exchange_attack_clip(check.weapon))
		Fatigue.charge(executor.owner, SiteCombatRules.EXCHANGE_FATIGUE)
	var job := _new_job(executor, "vehicle_attack", -1)
	job.merge({"duration": duration, "vehicle_id": vehicle_id, "vehicle_owner": check.vehicle,
		"weapon": check.weapon, "weapon_id": check.weapon_id, "executor_hp": float(executor.hp), "terrain": lab.terrain, "site_state": lab.terrain.site})
	_jobs[str(executor_id)] = job
	Runtime.mark_combat(lab.terrain, 10.0)
	return Runtime.ok("開始接觸攻擊原器具", {"seconds": duration})

func _vehicle_attack_context(identity: int, vehicle_id: String, job: Dictionary = {}) -> Dictionary:
	if lab.site_controller.has_method("ship_person_in_journey") and lab.site_controller.ship_person_in_journey(identity): return Runtime.fail("BUSY", "原人物在船旅程中")
	var person := _person(identity)
	var vehicle: Dictionary = lab.terrain.site.get("vehicles", {}).get(vehicle_id, {})
	if person.is_empty() or float(person.hp) <= 0.0 or float(person.ko) > 0.0 or bool(person.captive) or bool(person.moving) or lab.site_controller.vehicles.is_siege_crew(identity): return Runtime.fail("BUSY")
	var can_act: bool = person.owner.combat_can_act(int(person.unit)) if int(person.unit) >= 0 else person.owner.can_act()
	var vehicles: Variant = lab.site_controller.vehicles
	var ship: bool = vehicles.is_ship(vehicle)
	if not can_act or is_guarding(identity) or not ship and (not vehicles.is_siege(vehicle) or float(vehicle.hp) <= 0.0) or ship and not vehicles.ship_afloat(vehicle): return Runtime.fail("NO_TARGET")
	if ship and (not vehicle.move.is_empty() or vehicles.is_embarked(identity) and (not vehicles.ship_for_person(identity).move.is_empty() or job.is_empty() and not vehicles.ship_can_attack(identity))): return Runtime.fail("BUSY")
	var team: Variant = lab.site_controller.vehicles._siege_team(vehicle)
	if team != null and team.faction_id == int(person.faction): return Runtime.fail("AUTHORITY", "己方器具沿受保護拆除入口")
	var weapon_id := str(person.holder.equipped.get("weapon", ""))
	var record: Dictionary = lab.terrain.site.item_records.get(weapon_id, {})
	var definition: Dictionary = lab.terrain.site.item_definitions.get(str(record.get("definition", "")), {})
	var weapon := str(definition.get("asset", "none"))
	if weapon_id.is_empty() or not person.holder.item_ids.has(weapon_id) or str(record.get("holder", "")) != str(person.holder.holder) or weapon == "none" or SiteCombatRules.WeaponMaterials.is_ranged(StringName(weapon)): return Runtime.fail("INVALID_WEAPON")
	if not job.is_empty() and (not is_same(job.terrain, lab.terrain) or not is_same(job.site_state, lab.terrain.site) or not is_same(job.vehicle_owner, vehicle) or int(person.hit) != int(job.executor_hit) or float(person.hp) < float(job.executor_hp) or lab.terrain.index(person.cell) != int(job.executor_cell) or weapon_id != str(job.weapon_id) or weapon != str(job.weapon)): return Runtime.fail("INTERRUPTED")
	var cells: Array[Vector2i] = vehicles.footprint(lab.terrain, vehicle) if ship else Runtime.siege_cells(lab.terrain, vehicle)
	for cell: Vector2i in cells:
		var contact: bool = absi(cell.x - person.cell.x) + absi(cell.y - person.cell.y) == 1
		if ship:
			var ground: Vector2 = vehicles.ship_person_ground(identity) if vehicles.is_embarked(identity) else (Vector2(person.cell) + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS
			contact = ground.distance_to((Vector2(cell) + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS) <= TerrainRenderer.CELL_PIXELS * 1.05
		if contact and lab.terrain.effective_height(cell) == lab.terrain.effective_height(person.cell):
			return Runtime.ok("", {"person": person, "vehicle": vehicle, "target_cell": cell, "weapon": weapon, "weapon_id": weapon_id})
	return Runtime.fail("UNREACHABLE")


func begin_siege_takeover(executor_id: int, vehicle_id: String, requester_id: int, test_dispatch: bool = false) -> Dictionary:
	var native_site: Variant = lab.get("crowd_site")
	var native_owner: Variant = native_site.person_owner(executor_id) if native_site != null and native_site.active else null
	var guard: Dictionary = Runtime.ok() if native_owner is CrowdOwner else crowd_action_guard([executor_id])
	if not guard.ok: return guard
	if is_busy(executor_id) or bool(lab.terrain.site.get("paused", false)): return Runtime.fail("BUSY")
	var check := _siege_takeover_context(executor_id, vehicle_id, requester_id, test_dispatch)
	if not check.ok: return check
	var job := _new_job(check.person, "siege_takeover", -1)
	job.merge({"vehicle_id": vehicle_id, "vehicle_owner": check.vehicle, "expected": _siege_takeover_snapshot(check.vehicle),
		"requester_id": requester_id, "test_dispatch": test_dispatch, "new_team": int(check.person.owner.team_id),
		"duration": 10.0, "executor_hp": float(check.person.hp), "terrain": lab.terrain, "site_state": lab.terrain.site})
	_jobs[str(executor_id)] = job
	return Runtime.ok("本人開始奪取原空機具；十動作秒完成前不轉隊", {"seconds": 10.0})

func _siege_takeover_snapshot(vehicle: Dictionary) -> Dictionary:
	return {"old_team": int(vehicle.team_id), "cell": int(vehicle.cell), "facing": vehicle.facing.duplicate(),
		"hp": float(vehicle.hp), "ever_hp_damaged": bool(vehicle.ever_hp_damaged), "holder_version": int(vehicle.holder.version),
		"next_attack_seq": int(vehicle.next_attack_seq), "rng_state": int(vehicle.rng_state)}

func _siege_takeover_context(identity: int, vehicle_id: String, requester_id: int, test_dispatch: bool, job: Dictionary = {}) -> Dictionary:
	var person := _person(identity, false)
	var vehicle: Dictionary = lab.terrain.site.get("vehicles", {}).get(vehicle_id, {})
	var transport: SiteVehicleTransport = lab.site_controller.vehicles
	if person.is_empty() or not (person.owner is TerrainArmy or person.owner is CrowdOwner) or int(person.unit) < 0 or not _ready(person) \
		or transport.is_operator(identity) or transport.is_embarked(identity) or lab.site_controller.work_team.is_assigned(identity) \
		or lab.site_controller._is_delivering_person(identity): return Runtime.fail("BUSY")
	var team: Variant = person.owner
	var registered: bool = lab.crowd_site != null and lab.crowd_site.active and lab.crowd_site.person_owner(identity) == team if team is CrowdOwner else lab.combat_armies.has(team)
	if not registered or not team.is_member(int(person.unit)) or not team.command_eligible(team.current_commander) \
		or not transport._authorized(team, requester_id, identity, test_dispatch): return Runtime.fail("NO_AUTHORITY")
	if not SiteVehicleTransport.is_siege(vehicle) or float(vehicle.get("hp", 0.0)) <= 0.0: return Runtime.fail("NO_TARGET")
	var old_team: Variant = transport._siege_team(vehicle)
	if old_team != null and old_team.faction_id == team.faction_id: return Runtime.fail("NO_AUTHORITY", "同方器具沿原隊調度")
	if not vehicle.crew_slots.is_empty() or not vehicle.action.is_empty() or not vehicle.move.is_empty() \
		or not vehicle.build.is_empty() or not vehicle.repair.is_empty() or bool(vehicle.stop_pending) \
		or str(vehicle.command.get("type", "")) not in ["", "stop"]: return Runtime.fail("BUSY", "原機具須停妥且操作與攻擊已收束")
	for flight: Dictionary in lab.siege_projectiles:
		if str(flight.source_vehicle) == vehicle_id: return Runtime.fail("BUSY", "原器具的已發彈體尚未收束")
	if not transport.touches_vehicle(person.cell, vehicle): return Runtime.fail("UNREACHABLE", "本人須實際到原機具外緣相鄰格")
	var cells := SiteVehicleTransport.footprint(lab.terrain, vehicle)
	for other: Dictionary in lab._siege_people():
		if int(other.faction) == team.faction_id: continue
		var can_act: bool = other.owner.combat_can_act(int(other.unit)) if int(other.unit) >= 0 else other.owner.can_act()
		if not can_act: continue
		for cell: Vector2i in cells:
			if Vector2(other.cell - cell).length_squared() <= 4.0: return Runtime.fail("THREAT", "原機具兩格內仍有可行動敵人")
	if not job.is_empty() and (not is_same(job.terrain, lab.terrain) or not is_same(job.site_state, lab.terrain.site) \
		or not is_same(job.vehicle_owner, vehicle) or _siege_takeover_snapshot(vehicle) != job.expected \
		or int(team.team_id) != int(job.new_team) or int(person.hit) != int(job.executor_hit) \
		or float(person.hp) < float(job.executor_hp) or lab.terrain.index(person.cell) != int(job.executor_cell)):
		return Runtime.fail("INTERRUPTED", "原人、機具、位姿、物資版本或授權已改變")
	return Runtime.ok("", {"person": person, "vehicle": vehicle})

func begin_capture(executor_id: int, target_id: int, guard_id: int) -> Dictionary:
	return _begin_binding(executor_id, target_id, guard_id, true)

func begin_unbind(executor_id: int, target_id: int) -> Dictionary:
	if not str(lab.terrain.site.captivity.get(str(target_id), {}).get("prison_id", "")).is_empty():
		return begin_prison_release(executor_id, target_id)
	return _begin_binding(executor_id, target_id, -1, false)

func begin_equipment(identity: int, request: Dictionary) -> Dictionary:
	var crowd_guard := crowd_action_guard([identity])
	if not crowd_guard.ok:
		return crowd_guard
	if is_busy(identity):
		return Runtime.fail("BUSY")
	if str(request.get("mode", "")) == "issue" and has_active_issue():
		return Runtime.fail("BUSY", "同一營地已有未完成領裝作業")
	if equipment_orders == null:
		return Runtime.fail("UNSUPPORTED", "尚未接入實際領裝規則")
	var prepared: Dictionary = equipment_orders.prepare(identity, request)
	var preparing := str(prepared.get("code", "")) == "ATLAS_REQUIRED"
	if not prepared.ok and not preparing:
		return prepared
	var executor := _person(identity)
	var job := _new_job(executor, "equipment", identity)
	job.merge({"duration": 5.0, "order": prepared.order, "preparing": preparing,
		"terrain": lab.terrain, "site_state": lab.terrain.site,
		"executor_owner": executor.owner, "executor_body": executor.body,
		"executor_holder": executor.holder, "executor_cargo": executor.cargo})
	if str(prepared.order.mode) == "issue":
		job.merge({"depot_holder": lab.terrain.site.depot_items, "depot_stock": lab.terrain.site.inventory})
	var military: Dictionary = prepare_nation_military_issue_binding(prepared.order)
	if not military.ok: return military
	job.merge(military.metadata)
	if not military.payment.is_empty(): publish_phase_payment(military.payment)
	_jobs[str(identity)] = job
	if preparing:
		job.paused = "PREPARING_ATLAS"
		_prepare_equipment_atlas.call_deferred(job, prepared.appearance)
		return Runtime.ok("正在準備共用裝備圖集；完成後才開始五秒換裝，原物品保留", {"seconds": 5.0, "preparing": true})
	return Runtime.ok("開始換裝；完成前保留原實裝", {"seconds": 5.0})

func begin_team_equipment(team: TerrainArmy, requester_id: int, representative_id: int, nation_id: String, standard_id: String, include_player: bool = false, selected_ids: Array[int] = [], simulate_npc_commander: bool = false) -> Dictionary:
	var crowd_guard := crowd_action_guard([requester_id, representative_id] + selected_ids)
	if not crowd_guard.ok:
		return crowd_guard
	if equipment_orders == null: return Runtime.fail("UNSUPPORTED", "尚未接入整隊實際領裝規則")
	if has_active_issue(): return Runtime.fail("BUSY", "同一營地已有未完成領裝作業")
	var prepared: Dictionary = equipment_orders.prepare_team_issue(team, requester_id, representative_id, nation_id, standard_id, include_player, selected_ids, simulate_npc_commander)
	var preparing := str(prepared.get("code", "")) == "ATLAS_REQUIRED"
	if not prepared.ok and not preparing: return prepared
	var representative := _person(representative_id)
	var job := _new_job(representative, "equipment", representative_id)
	job.merge({"duration": 5.0, "order": prepared.order, "preparing": preparing,
		"terrain": lab.terrain, "site_state": lab.terrain.site,
		"executor_owner": representative.owner, "executor_body": representative.body,
		"executor_holder": representative.holder, "executor_cargo": representative.cargo,
		"depot_holder": lab.terrain.site.depot_items, "depot_stock": lab.terrain.site.inventory})
	_jobs[str(representative_id)] = job
	if preparing:
		job.paused = "PREPARING_ATLAS"
		_prepare_team_equipment_atlases.call_deferred(job, prepared.appearances)
	return Runtime.ok("正在準備共用裝備圖集；原物品保留" if preparing else "整隊開始五秒換裝；完成前保留原實裝",
		{"seconds": 5.0, "preparing": preparing, "target_ids": prepared.target_ids,
			"changed_ids": prepared.changed_ids, "recipe_count": int(prepared.recipe_count),
			"take_count": int(prepared.take_count), "return_count": int(prepared.return_count)})

func _prepare_team_equipment_atlases(job: Dictionary, appearances: Array) -> void:
	var key := str(job.executor_id)
	for appearance: Dictionary in appearances:
		if not is_same(_jobs.get(key), job) or not bool(job.preparing): return
		var check := _job_context(job)
		if not check.ok and str(check.code) != "ATLAS_REQUIRED":
			_finish(key, check)
			return
		var complete := false
		if is_instance_valid(lab) and lab is Node and lab.is_inside_tree():
			complete = await TerrainArmy.EquipmentAtlas.prepare_recipe(lab, appearance)
			if complete and lab.site_controller != null:
				complete = await lab.site_controller.prepare_siege_equipment_work(appearance, int(job.order.team_id))
		if not is_same(_jobs.get(key), job) or not bool(job.preparing): return
		if not complete:
			_finish(key, Runtime.fail("ATLAS_PREPARATION_FAILED", "整隊共用圖集準備失敗；原裝與全部實物保留"))
			return
	_equipment_prepared(job, true)

func _prepare_equipment_atlas(job: Dictionary, appearance: Dictionary) -> void:
	var key := str(job.executor_id)
	if not is_same(_jobs.get(key), job) or not bool(job.preparing): return
	var check := _job_context(job)
	if not check.ok and str(check.code) != "ATLAS_REQUIRED":
		_finish(key, check)
		return
	var complete := false
	if is_instance_valid(lab) and lab is Node and lab.is_inside_tree():
		complete = await TerrainArmy.EquipmentAtlas.prepare_recipe(lab, appearance)
		if complete and lab.site_controller != null:
			var person := _person(int(job.executor_id))
			var team_id := int(person.owner.team_id) if not person.is_empty() and int(person.unit) >= 0 else 0
			complete = await lab.site_controller.prepare_siege_equipment_work(appearance, team_id)
	_equipment_prepared(job, complete)

func _equipment_prepared(job: Dictionary, complete: bool) -> void:
	var key := str(job.executor_id)
	# A canceled/replaced job must never resume, including a new job for the same ID.
	if not is_same(_jobs.get(key), job) or not bool(job.preparing): return
	var check := _job_context(job)
	if not check.ok and str(check.code) != "ATLAS_REQUIRED":
		_finish(key, check)
	elif not complete or not check.ok:
		_finish(key, Runtime.fail("ATLAS_PREPARATION_FAILED", "共用裝備圖集準備失敗或仍未通過原驗證；本次換裝已取消，原裝與全部物品保留"))
	else:
		job.preparing = false
		job.paused = ""
		job.elapsed = 0.0 # Only the original clock/post-contact commit can equip.

func begin_ranged_craft(identity: int, recipe: String, technology_token: Dictionary = {}) -> Dictionary:
	var crowd_guard := crowd_action_guard([identity])
	if not crowd_guard.ok:
		return crowd_guard
	if is_busy(identity) or bool(lab.terrain.site.get("paused", false)):
		return Runtime.fail("BUSY", "先完成或取消原人物作業，暫停時不能開始")
	var executor := _person(identity)
	var check := _ranged_craft_context(executor)
	if not check.ok:
		return check
	check = Runtime.ranged_craft(lab.terrain, recipe, identity, true, technology_token)
	if not check.ok:
		return check
	var job := _new_job(executor, "ranged_craft", identity)
	job.merge({"recipe": recipe, "duration": float(Runtime.RANGED_RECIPES[recipe].duration),
		"terrain": lab.terrain, "site_state": lab.terrain.site,
		"executor_holder": executor.holder, "executor_cargo": executor.cargo, "executor_version": int(executor.holder.version),
		"depot_holder": lab.terrain.site.depot_items, "depot_stock": lab.terrain.site.inventory})
	job.duration = ranged_craft_seconds(identity, recipe)
	_jobs[str(identity)] = job
	return Runtime.ok("開始營地手作；完成才扣原材料並入庫", {"seconds": job.duration})

func begin_escape(identity: int) -> Dictionary:
	var crowd_guard := crowd_action_guard([identity])
	if not crowd_guard.ok:
		return crowd_guard
	if is_busy(identity):
		return Runtime.fail("BUSY")
	var person := _person(identity)
	var check := _escape_context(person)
	if not check.ok:
		return check
	var job := _new_job(person, "escape", identity)
	job.merge({"duration": ESCAPE_SECONDS, "captivity": lab.terrain.site.captivity[str(identity)].duplicate(),
		"source_version": int(person.holder.version)})
	_jobs[str(identity)] = job
	return Runtime.ok("開始尋找逃脫機會；連續三十秒無有效看守且無威脅才解開")

# The same original person job clock owns tent work. Inventory and the feature
# change together only at the existing post-contact completion boundary.
func tent_context(identity: int) -> Dictionary:
	var guard := crowd_action_guard([identity])
	if not guard.ok: return guard
	if not is_instance_valid(lab) or lab.terrain == null or bool(lab.terrain.site.get("paused", false)):
		return Runtime.fail("BUSY")
	var person := _person(identity)
	if person.is_empty() or not person.owner is TerrainArmy or int(person.unit) < 0 \
		or not person.owner.is_member(int(person.unit)) or not bool(person.body.get("logistics", false)):
		return Runtime.fail("NO_AUTHORITY", "須由原隊已明確指派的後勤人員操作營帳")
	var team: TerrainArmy = person.owner
	var requester := int(lab.controlled_person_id())
	if requester != identity and (not team.command_eligible(team.current_commander) or team.combat_identity(team.current_commander) != requester):
		return Runtime.fail("NO_AUTHORITY", "只有原後勤本人或原隊目前合格指揮者可下令")
	var controller: Variant = lab.site_controller
	if controller == null or not _ready(person) or float(lab.terrain.site.get("combat_left", 0.0)) > 0.0 \
		or controller.vehicles.is_operator(identity) or controller.work_team.is_assigned(identity) or controller._is_delivering_person(identity):
		return Runtime.fail("BUSY", "後勤須清醒自由、停止脫戰，先放下車輛並完成其他職務")
	return Runtime.ok("原後勤人物可操作營帳", {"person": person, "requester_id": requester})

func begin_tent_deploy(identity: int, cells: Array[int], quarter: int = 0) -> Dictionary:
	return _begin_tent(identity, "", cells, quarter)

func begin_tent_pack(identity: int, feature_key: String) -> Dictionary:
	if feature_key.is_empty(): return Runtime.fail("NO_TARGET")
	return _begin_tent(identity, feature_key, [], 0)

func _begin_tent(identity: int, feature_key: String, cells: Array[int], quarter: int) -> Dictionary:
	if is_busy(identity): return Runtime.fail("BUSY", "先完成或取消原人物作業")
	var check := tent_context(identity)
	if not check.ok: return check
	var person: Dictionary = check.person
	var job := _new_job(person, "tent_deploy" if feature_key.is_empty() else "tent_pack", identity)
	job.merge({"duration": TENT_SECONDS, "terrain": lab.terrain, "site_state": lab.terrain.site,
		"requester_id": int(check.requester_id), "executor_owner": person.owner, "executor_body": person.body,
		"executor_holder": person.holder, "executor_cargo": person.cargo, "executor_version": int(person.holder.version),
		"feature": feature_key, "feature_owner": lab.terrain.site.features.get(feature_key, {}),
		"cells": cells.duplicate(), "quarter": quarter})
	check = _tent_job_context(job)
	if not check.ok: return check
	_jobs[str(identity)] = job
	return Runtime.ok("開始搭設營帳；完成才使用本人營帳包" if feature_key.is_empty() else "開始收納營帳；完成才歸還本人行囊", {"seconds": TENT_SECONDS})

func _tent_occupied(cell: Vector2i) -> bool:
	return lab.site_controller.reserves_cell(cell)

func _tent_job_context(job: Dictionary) -> Dictionary:
	if not is_instance_valid(lab) or not is_same(lab.terrain, job.terrain) or not is_same(lab.terrain.site, job.site_state):
		return Runtime.fail("STALE_SOURCE", "原 Site 已切換，營帳與物品未提交")
	var check := tent_context(int(job.executor_id))
	if not check.ok: return check
	var person: Dictionary = check.person
	if int(check.requester_id) != int(job.requester_id) or not is_same(person.owner, job.executor_owner) or not is_same(person.body, job.executor_body) \
		or not is_same(person.holder, job.executor_holder) or not is_same(person.cargo, job.executor_cargo) or int(person.holder.version) != int(job.executor_version):
		return Runtime.fail("STALE_SOURCE", "原人物、持物或指揮權已變更，營帳與物品未提交")
	if int(person.hit) != int(job.executor_hit) or lab.terrain.index(person.cell) != int(job.executor_cell):
		return Runtime.fail("INTERRUPTED", "後勤受擊或移動，營帳與物品未提交")
	if str(job.kind) == "tent_deploy":
		if not Runtime.can_pay(person.cargo, {"camp_tent": 1}): return Runtime.fail("MATERIALS", "本人行囊須有一包營帳")
		return Runtime.preview_deploy_tent(lab.terrain, job.cells, person.cell, int(person.faction), _tent_occupied, int(job.quarter))
	if not is_same(lab.terrain.site.features.get(str(job.feature), {}), job.feature_owner):
		return Runtime.fail("STALE_SOURCE", "原營帳已變更")
	return Runtime.preview_pack_tent(lab.terrain, str(job.feature), person.cargo, person.holder, person.cell, int(person.faction), _tent_occupied)

func begin_ransom(payer_id: int, target_id: int, representative_id: int) -> Dictionary:
	var crowd_guard := crowd_action_guard([payer_id, target_id, representative_id])
	if not crowd_guard.ok:
		return crowd_guard
	if is_busy(payer_id):
		return Runtime.fail("BUSY")
	var payer := _person(payer_id)
	var target := _person(target_id)
	var representative := _person(representative_id)
	var query := _ransom_context(payer, target, representative)
	if not query.ok:
		return query
	var items := {}
	var left := RANSOM_RATIONS
	for food: String in FOODS:
		var quantity := mini(left, int(query.source.get(food, 0)))
		if quantity > 0:
			items[food] = quantity
		left -= quantity
	if left > 0:
		return Runtime.fail("MATERIALS", "原付款庫存不足一百日份")
	var job := _new_job(payer, "ransom", target_id)
	job.merge({"duration": RANSOM_SECONDS, "representative_id": representative_id,
		"representative_cell": lab.terrain.index(representative.cell), "representative_hit": int(representative.hit),
		"source_owner": str(query.source_owner), "destination_owner": str(query.destination_owner),
		"source_revision": int(query.source_revision), "destination_revision": int(query.destination_revision),
		"source_stock": query.source.duplicate(), "resources": items,
		"captivity": lab.terrain.site.captivity[str(target_id)].duplicate(), "source_version": int(target.holder.version)})
	_jobs[str(payer_id)] = job
	return Runtime.ok("開始交付一百實物日份贖回；完成前不扣糧", {"seconds": RANSOM_SECONDS})

func _begin_binding(executor_id: int, target_id: int, guard_id: int, capturing: bool) -> Dictionary:
	var crowd_guard := crowd_action_guard([executor_id, target_id, guard_id])
	if not crowd_guard.ok:
		return crowd_guard
	if is_busy(executor_id):
		return Runtime.fail("BUSY", "先完成或取消原人物作業")
	var executor := _person(executor_id)
	var target := _person(target_id)
	var check := _binding_context(executor, target, guard_id, capturing)
	if not check.ok:
		return check
	var job := _new_job(executor, "capture" if capturing else "unbind", target_id)
	job.merge({"guard_id": guard_id, "duration": BIND_SECONDS,
		"source_version": int(target.holder.version), "target_hit": int(target.hit),
		"source_cell": lab.terrain.index(target.cell)})
	_jobs[str(executor_id)] = job
	return Runtime.ok("開始拘束" if capturing else "開始解綁", {"seconds": BIND_SECONDS})

func _new_job(executor: Dictionary, kind: String, target_id: int) -> Dictionary:
	return {"version": 1, "kind": kind, "executor_id": int(executor.person_id), "target_id": target_id,
		"executor_cell": lab.terrain.index(executor.cell), "executor_hit": int(executor.hit),
		"elapsed": 0.0, "paused": ""}

func advance(seconds: float, work_plan: Dictionary = {}) -> Dictionary:
	var handled := {}
	if not is_finite(seconds) or seconds <= 0.0 or bool(lab.terrain.site.get("paused", false)):
		return {"handled_seconds": handled}
	var threats := {}
	for key: String in _jobs.keys():
		var job: Dictionary = _jobs[key]
		if str(job.kind) in ["technology_feature", "technology_vehicle"]:
			_advance_controlled_feature_work(key, job, seconds, work_plan, handled)
			continue
		if str(job.kind) == "fire_suppress":
			if job.executor_owner is CrowdPersonOwner and not bool(job.cancelled):
				job.executor_owner.advance_suppress_approach(int(job.executor_id), int(job.job_token))
			handled[int(job.executor_id)] = _fire_work_handled_seconds(job, seconds)
			continue
		if str(job.kind) in ["housing_return", "ground_boundary"] or str(job.kind).begins_with("ship_"): continue # Original ACTION boundary owns finite movement.
		var accepted: Dictionary = _consume_shared_job_advance_prefix(key, job, seconds, work_plan)
		if bool(accepted.get("duplicate", false)): continue
		var check: Dictionary = Runtime.ok() if not accepted.is_empty() else _job_context(job)
		if bool(job.get("preparing", false)) and (check.ok or str(check.code) == "ATLAS_REQUIRED"):
			continue # Preparation is not work time, fatigue, or an inventory reservation.
		if not check.ok:
			_finish(key, check)
			continue
		var executor := _person(int(job.executor_id))
		if str(job.kind) in ["structure_attack", "vehicle_attack", "siege_takeover"]: continue # Original combat action clock advances this strike.
		if str(job.kind) == "escape":
			# This original custody timer never billed fatigue in advance(). Keep
			# its watcher/reset contract outside positive-effort allocations.
			if int(executor.hit) != int(job.executor_hit) or _escape_blocked(executor, threats):
				job.elapsed = 0.0
				job.paused = "WATCHED"
				job.executor_hit = int(executor.hit)
			else:
				job.paused = ""
				job.elapsed = minf(ESCAPE_SECONDS, float(job.elapsed) + seconds)
			continue
		if work_plan.get("jobs", {}).has(key):
			var interval: Dictionary = work_plan.jobs[key]
			job.paused = str(interval.get("paused", ""))
			if job.paused == "THREAT": job.elapsed = 0.0
			else: job.elapsed = minf(float(job.duration), float(job.elapsed) + float(interval.get("effective_seconds", 0.0)))
			settlement_food_prefix_progress(job)
			for participant: Variant in interval.get("participant_seconds", {}):
				handled[int(participant)] = float(interval.participant_seconds[participant])
				if handled[int(participant)] > 0.0:
					var person := _person(int(participant))
					if not person.is_empty() and not bool(person.player): _body_set(person, "work_resting", false)
			if job.paused == "REST":
				for participant: Variant in interval.get("participant_seconds", {}):
					var person := _person(int(participant))
					if not person.is_empty() and not bool(person.player):
						_body_set(person, "work_resting", true)
						if person.owner is CrowdOwner and _shared_work_prefix_consumption.is_empty(): person.owner.work_fatigue_rest(int(participant))
				if float(job.elapsed) >= float(job.duration) - 0.00000001: job.paused = "" # Legal completion at the REST boundary.
			continue # The original shared collector charged each original pool once.
		if not work_plan.is_empty():
			job.paused = "CLOCK_NOT_READY"
			continue # A planned interval never bills a missing original provider again.
		if str(job.kind) in ["technology_lesson", "captive_craft", "water_schedule", "food_order"]:
			job.paused = "CLOCK_NOT_READY"
			continue # A joint course requires the complete original-pool work plan.
		if str(job.kind) == "equipment" and str(job.order.mode) == "team_issue":
			_advance_team_equipment(job, seconds, handled, threats)
			continue
		if str(job.kind) == "prison_release" and executor.owner is CrowdOwner:
			var work_seconds := minf(seconds, maxf(0.0, float(job.duration) - float(job.elapsed)))
			if not bool(executor.player) and _threat(executor, threats):
				_finish(key, Runtime.fail("THREAT", "原出監作業者轉回自衛，解綁尚未提交"))
				continue
			if not bool(executor.player):
				var formation: Dictionary = executor.owner.crowd_site.formation_state(int(executor.owner.formation_index))
				var rate := (10.0 / 3600.0) / maxf(1.0, float(formation.get("fatigue_count", 1)))
				work_seconds = minf(work_seconds, maxf(0.0, Fatigue.WORK_REST_AT - float(_body_get(executor, "fatigue"))) / rate)
				if work_seconds <= 0.0:
					_finish(key, Runtime.fail("REST", "原作業者已達休息門檻，出監尚未提交"))
					continue
			if work_seconds > 0.0 and not bool(executor.owner.crowd_site.crowd.charge_custody_work(int(executor.unit), work_seconds)):
				_finish(key, Runtime.fail("BUSY", "原生拘押作業已中斷"))
				continue
			job.elapsed = minf(float(job.duration), float(job.elapsed) + work_seconds)
			job.paused = ""
			handled[int(job.executor_id)] = work_seconds
			continue
		var work := seconds
		var fatigue := float(_body_get(executor, "fatigue"))
		var work_rate := Fatigue.effort_rate(executor.body)
		if not bool(executor.player):
			var resting := Fatigue.needs_work_rest(fatigue, bool(_body_get(executor, "work_resting")))
			_body_set(executor, "work_resting", resting)
			if _threat(executor, threats):
				job.paused = "THREAT"
				job.elapsed = 0.0 # This batch must be continuous; completed earlier batches stand.
				continue
			if resting:
				job.paused = "REST"
				continue
			work = minf(work, maxf(0.0, Fatigue.WORK_REST_AT - fatigue) / work_rate)
		job.paused = ""
		var remaining := maxf(0.0, float(job.duration) - float(job.elapsed))
		# Loot and handcraft share work productivity; binding retains its confirmed clock.
		var productive_work := str(job.kind) in ["loot", "ranged_craft", "tent_deploy", "tent_pack"]
		var multiplier := _technology_work_multiplier(job)
		var productive := (Fatigue.work_seconds(fatigue, work, work_rate) if productive_work else work) * multiplier
		if productive > remaining:
			# Monotone shared fatigue integral: find actual effort, not an entire long frame.
			var low := 0.0
			var high := work
			for iteration: int in 32:
				var middle := (low + high) * 0.5
				var output := (Fatigue.work_seconds(fatigue, middle, work_rate) if productive_work else middle) * multiplier
				if output < remaining:
					low = middle
				else:
					high = middle
			work = high
			productive = remaining
		job.elapsed = minf(float(job.duration), float(job.elapsed) + productive)
		var state := Fatigue.advance(fatigue, float(_body_get(executor, "fatigue_rest")), work, work_rate, false)
		_body_set(executor, "fatigue", state[0])
		_body_set(executor, "fatigue_rest", state[1])
		handled[int(job.executor_id)] = work
		if not bool(executor.player) and state[0] >= Fatigue.WORK_REST_AT - 0.000000001:
			_body_set(executor, "fatigue", Fatigue.WORK_REST_AT)
			_body_set(executor, "work_resting", true)
			if float(job.elapsed) < float(job.duration) - 0.00000001:
				job.paused = "REST"
	return {"handled_seconds": handled}

func _advance_team_equipment(job: Dictionary, seconds: float, handled: Dictionary, threats: Dictionary) -> void:
	var identities: Array[int] = job.order.target_ids.duplicate()
	if not identities.has(int(job.executor_id)): identities.append(int(job.executor_id))
	var people: Array[Dictionary] = []
	var pools: Array[Dictionary] = []
	for identity: int in identities:
		var person := _person(identity)
		people.append(person)
		if not bool(person.player):
			var fatigue := float(_body_get(person, "fatigue"))
			var resting := Fatigue.needs_work_rest(fatigue, bool(_body_get(person, "work_resting")))
			_body_set(person, "work_resting", resting)
			if _threat(person, threats):
				job.elapsed = 0.0
				job.paused = "THREAT"
				return
			if resting:
				job.paused = "REST"
				return
		var pool := Fatigue.pool(person.body)
		var group: Dictionary = {}
		if not pool.is_empty():
			for existing: Dictionary in pools:
				if is_same(existing.pool, pool): group = existing
		if group.is_empty():
			group = {"pool": pool, "body": person.body, "count": 0, "limit": false}
			pools.append(group)
		group.count = int(group.count) + 1
		group.limit = bool(group.limit) or not bool(person.player)
	var work := minf(seconds, maxf(0.0, float(job.duration) - float(job.elapsed)))
	for group: Dictionary in pools:
		if bool(group.limit):
			var group_rate := Fatigue.effort_rate(group.body) * int(group.count)
			work = minf(work, maxf(0.0, Fatigue.WORK_REST_AT - Fatigue.read(group.body)) / group_rate)
	if work <= 0.0:
		job.paused = "REST"
		return
	job.paused = ""
	job.elapsed = minf(float(job.duration), float(job.elapsed) + work)
	for person: Dictionary in people:
		var fatigue := float(_body_get(person, "fatigue"))
		var state := Fatigue.advance(fatigue, float(_body_get(person, "fatigue_rest")), work, Fatigue.effort_rate(person.body), false)
		_body_set(person, "fatigue", state[0])
		_body_set(person, "fatigue_rest", state[1])
		handled[int(person.person_id)] = work
		if not bool(person.player) and state[0] >= Fatigue.WORK_REST_AT - 0.000000001:
			_body_set(person, "fatigue", Fatigue.WORK_REST_AT)
			_body_set(person, "work_resting", true)
			if float(job.elapsed) < float(job.duration) - 0.00000001: job.paused = "REST"

func settle_after_contacts() -> Array[Dictionary]:
	if bool(lab.terrain.site.get("paused", false)):
		return [] # A completed pending batch does not commit behind a paused scene.
	# Stable original IDs are the sole tie-break; every later submission rechecks.
	var keys: Array = _jobs.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return int(a) < int(b))
	var ranged_settled := {}
	for key: String in keys:
		if ranged_settled.has(key): continue
		var job: Dictionary = _jobs[key]
		if str(job.kind) in ["technology_feature", "technology_vehicle"]:
			var current := _controlled_feature_job_context(job)
			if not current.ok: _finish(key, current)
			continue
		if str(job.kind) == "fire_suppress":
			if lab.crowd_site != null and lab.crowd_site.active and job.executor_owner is CrowdOwner and lab.crowd_site.work_fatigue_point_active(): continue
			_settle_fire_suppress(key, job)
			continue
		if str(job.kind) == "housing_return":
			_settle_housing_job(key, job)
			continue
		if str(job.kind) == "ground_boundary":
			_settle_ground_boundary(key, job)
			continue
		if str(job.kind).begins_with("ship_"):
			_settle_ship_job(key, job)
			continue
		var check := _job_context(job)
		if bool(job.get("preparing", false)) and (check.ok or str(check.code) == "ATLAS_REQUIRED"):
			continue
		if check.ok and str(job.kind) == "escape":
			var person := _person(int(job.executor_id))
			if int(person.hit) != int(job.executor_hit) or _escape_blocked(person, {}):
				job.elapsed = 0.0
				job.paused = "WATCHED"
				job.executor_hit = int(person.hit)
		elif check.ok and str(job.kind) == "equipment" and str(job.order.mode) == "team_issue":
			var identities: Array[int] = job.order.target_ids.duplicate()
			if not identities.has(int(job.executor_id)): identities.append(int(job.executor_id))
			for identity: int in identities:
				var person := _person(identity)
				if not bool(person.player) and _threat(person, {}):
					job.elapsed = 0.0
					job.paused = "THREAT"
					break
		elif check.ok and str(job.kind) == "captive_craft":
			pass # Original context rechecks actual guard-side threat after contacts.
		elif check.ok and str(job.kind) == "technology_lesson":
			for identity: int in [int(job.executor_id), int(job.target_id)]:
				var participant := _person(identity)
				if not bool(participant.player) and _threat(participant, {}):
					job.elapsed = 0.0
					job.paused = "THREAT"
					break
		elif check.ok and str(job.kind) not in ["structure_attack", "vehicle_attack", "siege_takeover"]:
			var executor := _person(int(job.executor_id))
			if not bool(executor.player) and _threat(executor, {}):
				job.elapsed = 0.0
				job.paused = "THREAT" # A new contact/wake threat wins the completion boundary.
		if not check.ok:
			_finish(key, check)
		elif str(job.paused).is_empty() and float(job.elapsed) >= float(job.duration) - 0.00000001:
			if str(job.kind) in ["ranged_craft", "captive_craft"]:
				var batch: Dictionary = _settle_ranged_terminal_chunk(keys, key)
				if not batch.ok: _finish(key, batch)
				else:
					for completed_key: String in batch.keys: ranged_settled[completed_key] = true
			elif _gd_typed_terminal_kind(str(job.kind)) and not _gd_typed_terminal_native(job):
				# Current numeric endpoint: prepare EVERY owner before its first debit,
				# then publish that one original no-fail transaction. A later job is
				# re-queried after this genuine earlier tail, never from fake versions.
				_finish(key, _commit_gd_typed_terminal(job))
			else: _finish(key, _commit(job))
	var results := _results
	_results = []
	return results

func _finish(key: String, result: Dictionary) -> void:
	_release_work_hold(_jobs.get(key, {}))
	_jobs.erase(key)
	result["executor_id"] = int(key)
	_results.append(result)

func _commit(job: Dictionary) -> Dictionary:
	if str(job.kind) in ["capture", "unbind", "ransom", "prison_release"] and not _gd_custody_native(job): return _commit_gd_custody_terminal(job)
	if str(job.kind) == "water_schedule": return _commit_water_schedule(job)
	if str(job.kind) == "nation_administration": return _commit_nation_administration(job)
	if str(job.kind) == "technology_analysis": return _commit_technology_analysis(job)
	if str(job.kind) == "captive_craft": return _commit_captive_craft(job)
	if str(job.kind) == "food_order": return _commit_settlement_food_work(job)
	var executor := _person(int(job.executor_id))
	if str(job.kind) in ["equipment", "loot", "tent_deploy", "tent_pack"] and not _gd_typed_terminal_native(job): return _commit_gd_typed_terminal(job)
	if str(job.kind) == "technology_lesson": return _commit_technology_lesson(job)
	if str(job.kind) == "siege_takeover":
		return Runtime.takeover_siege(lab.terrain, str(job.vehicle_id), job.expected, int(job.new_team))
	if str(job.kind) == "tent_deploy":
		return Runtime.deploy_tent(lab.terrain, job.cells, executor.cargo, executor.holder, int(job.executor_version), executor.cell, int(executor.faction), _tent_occupied, int(job.quarter))
	if str(job.kind) == "tent_pack":
		return Runtime.pack_tent(lab.terrain, str(job.feature), executor.cargo, executor.holder, int(job.executor_version), executor.cell, int(executor.faction), _tent_occupied)
	if str(job.kind) == "structure_attack":
		var part: Dictionary = Runtime.feature_geometry(lab.terrain, job.feature_owner).parts.get(str(job.part), {})
		var material := "wood" if str(part.get("role", "")) == "leaf" else str(job.feature_owner.get("material", "stone" if str(job.feature_owner.get("kind", "")) == "stone_wall" else "wood"))
		var key := str(job.feature) + "|" + str(job.part)
		return lab.siege_queue_damage({key: {"feature": str(job.feature), "part": str(job.part), "damage": SiteCombatRules.structure_damage(str(job.weapon), material)}}, {}, int(job.executor_id))
	if str(job.kind) == "vehicle_attack":
		var damage := SiteCombatRules.structure_damage(str(job.weapon), "wood")
		return lab.siege_queue_damage({}, {str(job.vehicle_id): damage}, int(job.executor_id))
	if str(job.kind) == "prison_release":
		return _commit_prison_release(job)
	if str(job.kind) == "ranged_craft":
		if job.has("technology_scope_token"): return _commit_scope_ranged_craft(job)
		if job.has("technology_project"): return _commit_technology_trial(job)
		return Runtime.ranged_craft(lab.terrain, str(job.recipe), int(job.executor_id))
	if str(job.kind) == "equipment":
		var audio_data: TerrainData = lab.terrain
		var audio_ground: Vector2 = executor.get("position", Vector2(-1, -1))
		if lab.has_method("_audio_p3_person_ground"):
			audio_ground = lab.call("_audio_p3_person_ground", int(job.executor_id), audio_ground)
		var result: Dictionary = equipment_orders.commit_team_issue(job.order) if str(job.order.mode) == "team_issue" else equipment_orders.commit(job.order)
		var changed: bool = not result.get("changed_ids", []).is_empty() if str(job.order.mode) == "team_issue" else job.order.planned != job.order.before
		if result.ok and changed and lab.has_method("_audio_p3_operation_completed"):
			lab.call("_audio_p3_operation_completed", audio_data, &"equipment_handle", audio_ground, int(job.executor_id))
		return result
	if str(job.kind) == "loot":
		var audio_data: TerrainData = lab.terrain
		var audio_ground: Vector2 = executor.get("position", Vector2(-1, -1))
		if lab.has_method("_audio_p3_person_ground"):
			audio_ground = lab.call("_audio_p3_person_ground", int(job.executor_id), audio_ground)
		var source := _source(str(job.source_kind), str(job.source_id))
		var result := Runtime.ok()
		if not job.resources.is_empty() or not job.item_ids.is_empty():
			result = Runtime.transfer_items(lab.terrain, source.holder, source.cargo, executor.holder, executor.cargo,
				job.resources, job.item_ids, int(job.source_version), int(job.destination_version))
		elif float(job.open_amount) > 0.0:
			source.holder.version = int(source.holder.version) + 1
			executor.holder.version = int(executor.holder.version) + 1
		if result.ok:
			if float(job.open_amount) > 0.0:
				source.holder.open_rations = float(source.holder.open_rations) - float(job.open_amount)
				opened_food_commit.call(int(executor.person_id), float(job.open_amount), job.destination_pool)
			if str(job.source_kind) == "ground" and source.holder.item_ids.is_empty() and Runtime.inventory_size(source.cargo) == 0:
				Runtime.clear_empty_ground_loot(lab.terrain, str(job.source_id))
			var original_owner := int(source.get("person_id", source.holder.get("original_owner", 0)))
			if original_owner > 0 and equipment_changed.is_valid():
				equipment_changed.call(original_owner)
			if equipment_changed.is_valid():
				equipment_changed.call(int(executor.person_id))
			if (not job.resources.is_empty() or not job.item_ids.is_empty() or float(job.open_amount) > 0.0) \
					and lab.has_method("_audio_p3_operation_completed"):
				lab.call("_audio_p3_operation_completed", audio_data, &"material_transfer", audio_ground, int(job.executor_id))
		return result
	var target := _person(int(job.target_id))
	if str(job.kind) == "ransom":
		var query := _ransom_context(executor, target, _person(int(job.representative_id)))
		if not query.ok:
			return query
		# Both original owners have been checked. No callback/yield until both move.
		Runtime.add_items(query.source, job.resources, -1)
		for resource: String in query.source.keys():
			if int(query.source[resource]) == 0:
				query.source.erase(resource)
		Runtime.add_items(query.destination, job.resources)
		ransom_exchange_committed.call(query)
	var capturing := str(job.kind) == "capture"
	var captor_id := int(job.executor_id) if capturing else int(lab.terrain.site.captivity[str(job.target_id)].captor_id)
	var container := ""
	if capturing:
		var sealed := _sealed_selection(target)
		if not sealed.item_ids.is_empty() or not sealed.resources.is_empty():
			var result := Runtime.leave_ground_loot(lab.terrain, target.holder, target.cargo, int(job.target_id), target.cell,
				"sealed", sealed.resources, sealed.item_ids, int(job.source_version))
			if not result.ok:
				return result
			container = str(result.container_id)
		var relation := {"version": 3, "captor_id": captor_id,
			"guard_id": int(job.guard_id), "captor_faction": int(executor.faction), "sealed_container": container, "prison_id": ""}
		relation.merge(capture_fields(int(job.target_id), target))
		lab.terrain.site.captivity[str(job.target_id)] = relation
	else:
		_social_before_release(int(job.target_id), target, str(job.kind) == "ransom")
		lab.terrain.site.captivity.erase(str(job.target_id))
	_body_set(target, "captive", capturing)
	if capturing and bool(target.surrender_pending):
		_body_set(target, "surrender_pending", false)
	# Binding is an original-holder state transition even if there was no gear.
	# It invalidates older simultaneous body requests without another person ledger.
	target.holder.version = int(target.holder.version) + 1
	captivity_supply_commit.call(int(job.target_id), captor_id, capturing)
	if equipment_changed.is_valid():
		equipment_changed.call(int(job.target_id))
	captivity_changed.call(int(job.target_id), captor_id, capturing)
	return Runtime.ok("已拘束；封存物留在原地" if capturing else "已解綁；生命與昏迷不變", {"container_id": container})

func _job_context(job: Dictionary) -> Dictionary:
	if str(job.kind) == "food_order": return _settlement_food_job_context(job)
	if str(job.kind) == "water_schedule": return _water_schedule_context(job)
	if str(job.kind) in ["technology_feature", "technology_vehicle"]: return _controlled_feature_job_context(job)
	if str(job.kind) == "nation_administration": return _nation_administration_context(job)
	if str(job.kind) == "technology_analysis": return _technology_analysis_job_context(job)
	if str(job.kind) == "captive_craft": return _captive_craft_job_context(job)
	if str(job.kind) == "technology_lesson": return _technology_lesson_context(job)
	if str(job.kind) == "fire_suppress": return _fire_suppress_context(job)
	if str(job.kind) == "siege_takeover":
		return _siege_takeover_context(int(job.executor_id), str(job.vehicle_id), int(job.requester_id), bool(job.test_dispatch), job)
	if str(job.kind) in ["tent_deploy", "tent_pack"]:
		return _tent_job_context(job)
	if str(job.kind) == "structure_attack":
		return _structure_attack_context(int(job.executor_id), str(job.feature), str(job.part), job)
	if str(job.kind) == "vehicle_attack":
		return _vehicle_attack_context(int(job.executor_id), str(job.vehicle_id), job)
	if str(job.kind) == "prison_release":
		return _prison_release_context(int(job.executor_id), int(job.target_id), job)
	var ids := [job.get("executor_id", -1), job.get("target_id", -1), job.get("guard_id", -1), job.get("representative_id", -1)]
	if str(job.get("source_kind", "")) == "person":
		ids.append(int(job.get("source_id", -1)))
	var crowd_guard := crowd_action_guard(ids)
	if not crowd_guard.ok:
		return crowd_guard
	if str(job.kind) == "equipment" and not is_instance_valid(lab):
		return Runtime.fail("STALE_SOURCE", "原 Site 已離開；換裝未扣物")
	if str(job.kind) == "ranged_craft" and (not is_same(lab.terrain, job.terrain) or not is_same(lab.terrain.site, job.site_state)):
		return Runtime.fail("STALE_SOURCE", "原營地／Site 已切換，手作未扣材料")
	if str(job.kind) == "equipment" and (not is_same(lab.terrain, job.terrain) or not is_same(lab.terrain.site, job.site_state)):
		return Runtime.fail("STALE_SOURCE", "原營地／Site 已切換，換裝未扣物")
	var executor := _person(int(job.executor_id))
	if str(job.kind) == "escape":
		var check := _escape_context(executor)
		if not check.ok:
			return check
		if lab.terrain.index(executor.cell) != int(job.executor_cell):
			return Runtime.fail("INTERRUPTED", "逃脫者移動")
		if lab.terrain.site.captivity.get(str(job.target_id), {}) != job.captivity or int(executor.holder.version) != int(job.source_version):
			return Runtime.fail("STALE_SOURCE")
		return Runtime.ok()
	if executor.is_empty() or int(executor.hit) != int(job.executor_hit) or lab.terrain.index(executor.cell) != int(job.executor_cell):
		return Runtime.fail("INTERRUPTED", "執行者受擊、移動或已不存在")
	if str(job.kind) == "ranged_craft":
		var check := _ranged_craft_context(executor)
		if not check.ok:
			return check
		if not is_same(executor.holder, job.executor_holder) or not is_same(executor.cargo, job.executor_cargo) \
			or int(executor.holder.version) != int(job.executor_version) \
			or not is_same(lab.terrain.site.depot_items, job.depot_holder) or not is_same(lab.terrain.site.inventory, job.depot_stock):
			return Runtime.fail("STALE_SOURCE", "原人物或營地持物已切換，手作未扣材料")
		check = Runtime.ranged_craft(lab.terrain, str(job.recipe), int(job.executor_id), true, job.get("technology_scope_token", {}))
		if check.ok and job.has("technology_scope_token"): return _scope_ranged_job_context(job)
		if check.ok and job.has("technology_project"): return _technology_trial_context(job)
		return check
	if str(job.kind) == "equipment":
		if not is_same(executor.owner, job.executor_owner) or not is_same(executor.body, job.executor_body) \
			or not is_same(executor.holder, job.executor_holder) or not is_same(executor.cargo, job.executor_cargo):
			return Runtime.fail("STALE_SOURCE", "原人物或持物已替換；換裝未扣物")
		if str(job.order.mode) in ["issue", "team_issue"] and (not is_same(lab.terrain.site.depot_items, job.depot_holder) or not is_same(lab.terrain.site.inventory, job.depot_stock)):
			return Runtime.fail("STALE_SOURCE", "原補給點持物已替換；換裝未扣物")
		if equipment_orders == null: return Runtime.fail("UNSUPPORTED")
		if job.has("nation_issue_token"):
			var issue_context := _nation_military_issue_job_context(job)
			if not issue_context.ok: return issue_context
		return equipment_orders.check_team_issue(job.order) if str(job.order.mode) == "team_issue" else equipment_orders.check(job.order)
	if str(job.kind) == "loot":
		var source := _source(str(job.source_kind), str(job.source_id))
		var check := _loot_context(executor, source)
		if not check.ok:
			return check
		if int(source.holder.version) != int(job.source_version) or int(executor.holder.version) != int(job.destination_version):
			return Runtime.fail("STALE_SOURCE")
		if not is_same(source.holder, job.source_holder) or not is_same(source.cargo, job.source_cargo) or not is_same(executor.holder, job.destination_holder) or not is_same(executor.cargo, job.destination_cargo):
			return Runtime.fail("STALE_SOURCE", "原持物資料已被替換")
		if float(job.open_amount) > 0.0:
			var pool: Dictionary = opened_food_pool.call(int(executor.person_id))
			if float(source.holder.get("open_rations", 0.0)) != float(job.source_open) or (not pool.is_empty() or not job.destination_pool.is_empty()) and not is_same(pool, job.destination_pool):
				return Runtime.fail("STALE_SOURCE", "開封口糧來源或私人餐份持有人已變更")
		if lab.terrain.index(source.cell) != int(job.source_cell) or int(source.get("hit", -1)) != int(job.target_hit):
			return Runtime.fail("INTERRUPTED", "搜身目標受擊或移動")
		check = _selection(executor, source, job.resources, job.item_ids, float(job.open_amount))
		return check if not check.ok else _removal_guard(source, job.item_ids)
	var target := _person(int(job.target_id))
	if str(job.kind) == "ransom":
		var representative := _person(int(job.representative_id))
		var query := _ransom_context(executor, target, representative)
		if not query.ok:
			return query
		if int(representative.hit) != int(job.representative_hit) or lab.terrain.index(representative.cell) != int(job.representative_cell):
			return Runtime.fail("INTERRUPTED", "拘押代表受擊或移動")
		if str(query.source_owner) != str(job.source_owner) or str(query.destination_owner) != str(job.destination_owner) or int(query.source_revision) != int(job.source_revision) or int(query.destination_revision) != int(job.destination_revision):
			return Runtime.fail("STALE_SOURCE")
		if query.source != job.source_stock or not Runtime.can_pay(query.source, job.resources):
			return Runtime.fail("STALE_SOURCE", "付款庫存已被供餐消耗或變更")
		if lab.terrain.site.captivity.get(str(job.target_id), {}) != job.captivity or int(target.holder.version) != int(job.source_version):
			return Runtime.fail("STALE_SOURCE")
		return Runtime.ok()
	if target.is_empty() or int(target.hit) != int(job.target_hit) or lab.terrain.index(target.cell) != int(job.source_cell):
		return Runtime.fail("INTERRUPTED", "目標受擊、移動或已不存在")
	if int(target.holder.version) != int(job.source_version):
		return Runtime.fail("STALE_SOURCE")
	return _binding_context(executor, target, int(job.guard_id), str(job.kind) == "capture")

func _ranged_craft_context(executor: Dictionary) -> Dictionary:
	var depot := _source("depot", "depot")
	if depot.is_empty() or not _ready(executor) or not _adjacent(executor.cell, depot.cell) or float(lab.terrain.site.get("combat_left", 0.0)) > 0.0:
		return Runtime.fail("BUSY", "手作須脫戰、清醒自由、停止於營地相鄰合法格且無其他作業")
	return Runtime.ok()

func _loot_context(executor: Dictionary, source: Dictionary) -> Dictionary:
	if source.is_empty():
		return Runtime.fail("NO_TARGET", "來源不存在或尚未初始化實際持物")
	var contact: bool = false
	if not executor.is_empty():
		var ship_context: bool = source.holder.has("vehicle_id") or source.get("body") is Dictionary and source.body.has("embarked_vehicle_id") or executor.body is Dictionary and executor.body.has("embarked_vehicle_id")
		# Only a vehicle source needs the controller's vehicle owner.
		contact = _ship_loot_contact(executor, source) if ship_context else (lab.site_controller.vehicles.touches_vehicle(executor.cell, source.vehicle) if source.has("vehicle") else _adjacent(executor.cell, source.cell))
	if not _ready(executor) or not contact:
		return Runtime.fail("BUSY", "須清醒自由、停止於相鄰可達格且沒有其他作業")
	if source.has("person_id"):
		if bool(source.player) or float(source.hp) <= 0.0 or float(source.ko) <= 0.0 or bool(source.captive) or bool(source.moving):
			return Runtime.fail("NO_TARGET", "只可搜身已停止的存活昏迷 NPC；死亡請重新選遺物")
	return Runtime.ok()

func _selection(executor: Dictionary, source: Dictionary, resources: Dictionary, item_ids: Array, open_amount: float = 0.0) -> Dictionary:
	if int(executor.holder.version) >= 2147483646 or int(source.holder.version) >= 2147483646:
		return Runtime.fail("STALE_SOURCE", "原持物提交版本已用盡，未取物")
	if not is_finite(open_amount) or open_amount < 0.0 or open_amount > Runtime.CARRY_CAPACITY:
		return Runtime.fail("INVALID", "開封口糧數量")
	if not Runtime._resource_stack(resources, false) or (resources.is_empty() and item_ids.is_empty() and open_amount <= 0.0):
		return Runtime.fail("INVALID", "請選正整數資源或實際物品")
	if open_amount > 0.0 and (source.has("person_id") or not opened_food_pool.is_valid() or not opened_food_commit.is_valid() or float(source.holder.get("open_rations", 0.0)) < open_amount):
		return Runtime.fail("EMPTY", "請選原地面容器的實際開封口糧")
	if not Runtime.can_pay(source.cargo, resources):
		return Runtime.fail("EMPTY")
	var selected := {}
	for identity: Variant in item_ids:
		if not identity is String or selected.has(identity) or not source.holder.item_ids.has(identity):
			return Runtime.fail("INVALID", "不存在或重複物品")
		var record: Dictionary = lab.terrain.site.item_records.get(identity, {})
		if str(record.get("holder", "")) != str(source.holder.holder):
			return Runtime.fail("STALE_SOURCE")
		selected[identity] = true
	if Runtime.carried_load(lab.terrain.site, executor.cargo, executor.holder) + Runtime.inventory_size(resources) + item_ids.size() + open_amount > Runtime.CARRY_CAPACITY:
		return Runtime.fail("STORAGE_FULL")
	return lab.terrain.item_transfer_guard.call(source.holder, executor.holder, resources, item_ids, open_amount) if lab.terrain.item_transfer_guard.is_valid() else Runtime.ok()

func _removal_guard(source: Dictionary, item_ids: Array) -> Dictionary:
	var owner_id := int(source.get("person_id", 0))
	if owner_id <= 0 and str(source.holder.get("kind", "")) == "remains":
		for identity: String in item_ids:
			if source.holder.equipped.values().has(identity):
				owner_id = int(source.holder.original_owner)
	if owner_id <= 0 or item_ids.is_empty():
		return Runtime.ok()
	if not equipment_removal_guard.is_valid() or not equipment_changed.is_valid():
		return Runtime.fail("UNSUPPORTED", "尚未接好原人物實裝／命中更新")
	return equipment_removal_guard.call(owner_id, item_ids)

func _binding_context(executor: Dictionary, target: Dictionary, guard_id: int, capturing: bool) -> Dictionary:
	if not _ready(executor, capturing) or target.is_empty() or float(target.hp) <= 0.0 or bool(target.moving) or not _adjacent(executor.cell, target.cell):
		return Runtime.fail("BUSY", "雙方須存活、停止並相鄰可達")
	if capturing:
		if (float(target.ko) <= 0.0 and not bool(target.surrender_pending)) or bool(target.captive) or lab.terrain.site.captivity.has(str(target.person_id)):
			return Runtime.fail("NO_TARGET", "目標須昏迷或投降待俘，且尚未被俘")
		var guard := _person(guard_id, false)
		if not _ready(guard, true) or (not bool(guard.player) and bool(_body_get(guard, "work_resting"))) or int(guard.faction) != int(executor.faction) or not _within_guard_range(guard.cell, target.cell):
			return Runtime.fail("GUARD", "需要同拘押方清醒自由、四步合法路程內的看守")
		var count := 0
		for entry: Dictionary in lab.terrain.site.captivity.values():
			count += int(int(entry.guard_id) == guard_id and str(entry.get("prison_id", "")).is_empty())
		if count >= GUARD_CAPACITY or (guard_id != int(executor.person_id) and is_busy(guard_id)):
			return Runtime.fail("GUARD", "看守已滿四人或有其他作業")
		var sealed := _sealed_selection(target)
		var equipment_check := _removal_guard(target, sealed.item_ids)
		if not equipment_check.ok:
			return equipment_check
	else:
		if not bool(target.captive) or not lab.terrain.site.captivity.has(str(target.person_id)) or int(target.faction) != int(executor.faction):
			return Runtime.fail("NO_TARGET", "外部解綁只適用原友方俘虜")
	if not captivity_change_guard.is_valid() or not captivity_supply_commit.is_valid() or not captivity_changed.is_valid():
		return Runtime.fail("UNSUPPORTED", "尚未接好原人物拘押／供養提交")
	var captor_id := int(executor.person_id) if capturing else int(lab.terrain.site.captivity[str(target.person_id)].captor_id)
	return captivity_change_guard.call(int(target.person_id), captor_id, capturing)

func _escape_context(person: Dictionary) -> Dictionary:
	if person.is_empty() or float(person.hp) <= 0.0 or float(person.ko) > 0.0 or not bool(person.captive) or bool(person.moving) or not lab.terrain.site.captivity.has(str(person.person_id)):
		return Runtime.fail("BUSY", "只有原清醒俘虜能自行逃脫；死亡或失能優先")
	if not str(lab.terrain.site.captivity[str(person.person_id)].get("prison_id", "")).is_empty():
		return Runtime.fail("CONFINED", "仍受戰俘營拘押，須由出口作業解綁")
	if not captivity_change_guard.is_valid() or not captivity_supply_commit.is_valid() or not captivity_changed.is_valid():
		return Runtime.fail("UNSUPPORTED")
	return captivity_change_guard.call(int(person.person_id), int(lab.terrain.site.captivity[str(person.person_id)].captor_id), false)

func _escape_blocked(person: Dictionary, candidates: Dictionary) -> bool:
	return has_effective_guard(int(person.person_id)) or _threat(person, candidates)

func _ransom_context(payer: Dictionary, target: Dictionary, representative: Dictionary) -> Dictionary:
	if not _ready(payer) or not _ready(representative, true) or target.is_empty() or float(target.hp) <= 0.0 or not bool(target.captive) or not lab.terrain.site.captivity.has(str(target.person_id)):
		return Runtime.fail("BUSY", "須由雙方清醒自由的實際代表交付")
	if not str(lab.terrain.site.captivity[str(target.person_id)].get("prison_id", "")).is_empty():
		return Runtime.fail("CONFINED", "先由战俘營相鄰接觸格完成出監解綁")
	if is_busy(int(representative.person_id)):
		return Runtime.fail("BUSY", "拘押代表已有其他未完成作業")
	if int(payer.faction) != int(target.faction) or int(representative.faction) != int(lab.terrain.site.captivity[str(target.person_id)].captor_faction) or not _adjacent(payer.cell, representative.cell):
		return Runtime.fail("AUTHORITY", "友方付款代表與拘押方代表須相鄰可達")
	if not ransom_exchange_query.is_valid() or not ransom_exchange_committed.is_valid() or not captivity_change_guard.is_valid() or not captivity_supply_commit.is_valid() or not captivity_changed.is_valid():
		return Runtime.fail("UNSUPPORTED")
	var check: Dictionary = captivity_change_guard.call(int(target.person_id), int(lab.terrain.site.captivity[str(target.person_id)].captor_id), false)
	if not check.ok:
		return check
	var query: Dictionary = ransom_exchange_query.call(int(payer.person_id), int(target.person_id), int(representative.person_id))
	if not query.ok:
		return query
	if not query.get("source") is Dictionary or not query.get("destination") is Dictionary or is_same(query.source, query.destination) or str(query.get("source_owner", "")).is_empty() or str(query.get("destination_owner", "")).is_empty() or str(query.source_owner) == str(query.destination_owner):
		return Runtime.fail("INVALID", "贖回須使用兩個不同的原實物庫存")
	if not Runtime._resource_stack(query.source) or not Runtime._resource_stack(query.destination) or not query.get("source_revision") is int or not query.get("destination_revision") is int or int(query.source_revision) < 0 or int(query.destination_revision) < 0:
		return Runtime.fail("INVALID", "原實物庫存或提交版本不合法")
	return query

func _sealed_selection(target: Dictionary) -> Dictionary:
	var ids: Array = []
	for identity: String in target.holder.item_ids:
		var record: Dictionary = lab.terrain.site.item_records[identity]
		var definition: Dictionary = lab.terrain.site.item_definitions[str(record.definition)]
		if str(definition.slot) in ["weapon", "shield"]:
			ids.append(identity)
	var resources := {}
	for ammunition: String in ["arrow", "fire_arrow", "bolt"]:
		if int(target.cargo.get(ammunition, 0)) > 0:
			resources[ammunition] = int(target.cargo[ammunition])
	return {"resources": resources, "item_ids": ids}

func _source(kind: String, identity: String) -> Dictionary:
	if kind == "wreck":
		var vehicle: Dictionary = lab.terrain.site.get("vehicles", {}).get(identity, {})
		if not lab.site_controller.vehicles.is_siege(vehicle) or float(vehicle.get("hp", 1.0)) != 0.0 or not vehicle.get("crew_slots", {}).is_empty() or not vehicle.get("action", {}).is_empty(): return {}
		return {"holder": vehicle.holder, "cargo": vehicle.cargo, "cell": lab.terrain.cell_from_index(int(vehicle.cell)), "vehicle": vehicle, "vehicle_id": identity}
	if kind == "person":
		return _person(int(identity)) if identity.is_valid_int() and str(int(identity)) == identity else {}
	if kind == "depot" and identity == "depot":
		var depot: Dictionary = lab.terrain.site.get("depot_items", {})
		if not Runtime._item_holder_shape(depot) or str(depot.holder) != "depot" or not lab.terrain.site.get("inventory") is Dictionary or not lab.terrain.site.has("depot_cell"):
			return {}
		return {"holder": depot, "cargo": lab.terrain.site.inventory, "cell": lab.terrain.cell_from_index(int(lab.terrain.site.depot_cell))}
	if kind != "ground":
		return {}
	var holder: Dictionary = lab.terrain.site.get("ground_loot", {}).get(identity, {})
	if holder.is_empty():
		return {}
	if holder.has("vehicle_id"):
		if not Runtime.valid_ship_loot_location(lab.terrain, {"vehicle_id": holder.vehicle_id, "local_position": holder.get("local_position")}): return {}
		var vehicles: Variant = lab.site_controller.vehicles
		var point: Vector2 = vehicles.ship_loot_ground(holder)
		return {"holder": holder, "cargo": holder.cargo, "cell": Vector2i((point / TerrainRenderer.CELL_PIXELS).floor()), "vehicle": vehicles.records()[str(holder.vehicle_id)], "vehicle_id": str(holder.vehicle_id)}
	return {"holder": holder, "cargo": holder.cargo, "cell": lab.terrain.cell_from_index(int(holder.cell))}

func _person(identity: int, require_items: bool = true) -> Dictionary:
	var person: Dictionary = lab._original_person_target(identity)
	if person.is_empty():
		return {}
	var owner: Variant = person.owner
	var unit := int(person.unit)
	if owner is CrowdOwner:
		return owner.person(unit, require_items)
	var body: Variant = owner.combat_units[unit] if unit >= 0 else owner
	if unit >= 0:
		person.hp = float(owner.combat_hot_get(unit, &"hp"))
	var holder: Variant = body.get("item_state")
	if require_items and (not holder is Dictionary or not Runtime._item_holder_shape(holder)):
		return {}
	var cargo: Dictionary = {}
	if unit >= 0:
		if not body.get("cargo") is Dictionary:
			if require_items:
				return {}
		else:
			cargo = body.cargo
	elif owner == lab.character:
		cargo = lab.terrain.site.manual.cargo
	elif owner == lab.npc:
		cargo = lab.terrain.site.worker.cargo
	else:
		return {} # An original owner must explicitly expose its real cargo.
	person.merge({"body": body, "holder": holder, "cargo": cargo, "person_id": identity,
		"ko": float(owner.combat_hot_get(unit, &"ko") if unit >= 0 else body.knockout_left),
		"captive": bool(owner.combat_hot_get(unit, &"captive") if unit >= 0 else body.get("captive")),
		"surrender_pending": bool(owner.combat_hot_get(unit, &"surrender_pending", false)) if unit >= 0 else body.get("surrender_pending") == true,
		"faction": int(owner.faction_id), "player": identity == (int(lab.controlled_person_id()) if lab.has_method("controlled_person_id") else int(lab.character.person_id)),
		"moving": owner.moving_to[unit] != Vector2i(-1, -1) if unit >= 0 else owner.is_moving(),
		"hit": int(body.get("hit_revision", 0)) if unit >= 0 else int(owner._received_effective_hit)})
	if lab.site_controller != null and unit >= 0 and body.has("embarked_vehicle_id"):
		var vehicles: Variant = lab.site_controller.vehicles
		var ship: Dictionary = vehicles.ship_for_person(identity)
		if not ship.is_empty():
			person.cell = vehicles.ship_person_cell(identity)
			var job: Dictionary = _jobs.get(str(identity), {})
			person.moving = vehicles._ship_in_journey(str(ship.id)) or not ship.move.is_empty() or str(job.get("kind", "")) in ["ship_helm", "ship_walk", "ship_cross", "ship_evac"]
	return person

func _ready(person: Dictionary, allow_guard: bool = false) -> bool:
	if person.is_empty() or float(person.hp) <= 0.0 or float(person.ko) > 0.0 or bool(person.captive) or bool(person.moving):
		return false
	if lab.site_controller != null:
		if lab.site_controller.has_method("region_operation_pending") and lab.site_controller.region_operation_pending(): return false
		if lab.site_controller.has_method("ship_person_in_journey") and lab.site_controller.ship_person_in_journey(int(person.person_id)): return false
		var vehicles: Variant = lab.site_controller.vehicles
		if vehicles.is_siege_crew(int(person.person_id)): return false
		if person.body is Dictionary and person.body.has("embarked_vehicle_id"):
			var ship: Dictionary = vehicles.ship_for_person(int(person.person_id))
			if not ship.is_empty() and (not ship.move.is_empty() or not vehicles.ship_job(str(ship.id)).is_empty()): return false
	if float(_body_get(person, "exchange_stagger")) > 0.0:
		return false # Action eligibility reads the original lock, not a render-only hit pose.
	if not allow_guard and is_guarding(int(person.person_id)):
		return false
	for entry: Dictionary in lab.terrain.site.get("team_supply", {}).values():
		var delivery: Dictionary = entry.get("delivery", {})
		if not delivery.is_empty() and int(person.person_id) in [int(delivery.get("player_id", -1)), int(delivery.get("representative_id", -1))]:
			return false
	if person.owner is CrowdOwner:
		if not person.owner.crowd_site.work_fatigue_work_start_ready(int(person.person_id)): return false
		return person.owner.combat_can_act(int(person.unit)) and not bool(_body_get(person, "attack")) and str(_body_get(person, "pose")) == "idle"
	if int(person.unit) >= 0:
		return person.owner.combat_can_act(int(person.unit)) and not bool(_body_get(person, "attack")) and str(_body_get(person, "pose")) == "idle" and person.body.get("work_task", {}).is_empty()
	var actor: Variant = person.owner
	if not actor.can_act() or actor.action_time > 0.0 or actor.guarding or actor.guard_transition_left > 0.0 or actor.guard_break_left > 0.0 or actor._rescue_left > 0.0:
		return false
	if actor == lab.npc and (int(actor.command) != 0 or not actor._path.is_empty()):
		return false # Do not steal an already queued original NPC movement command.
	var activity: Dictionary = lab.terrain.site.manual if actor == lab.character else lab.terrain.site.worker
	if not str(activity.get("target", "")).is_empty():
		return false
	return true

func _adjacent(from: Vector2i, to: Vector2i) -> bool:
	return absi(from.x - to.x) + absi(from.y - to.y) == 1 and lab.terrain.can_step(from, to)

func _within_guard_range(from: Vector2i, to: Vector2i) -> bool:
	if from == to or absi(from.x - to.x) + absi(from.y - to.y) > GUARD_STEPS:
		return false
	# Query only during an explicit capture command, not each idle guard per frame.
	var path: Array[Vector2i] = lab.terrain.path_between(from, to, func(cell: Vector2i) -> bool:
		return absi(from.x - cell.x) + absi(from.y - cell.y) > GUARD_STEPS)
	return not path.is_empty() and path.size() <= GUARD_STEPS

func _threat(person: Dictionary, candidates: Dictionary) -> bool:
	return bool(lab._fatigue_threat(person.cell, int(person.faction), person.owner, int(person.unit), candidates))

func _body_get(person: Dictionary, field: String) -> Variant:
	if field == "technology":
		return person.body.get(field, {}) if person.body is Dictionary else person.body.get(field)
	if person.owner is CrowdOwner:
		if field in ["work_resting", "loot_settled", "captive", "attack", "surrender_pending"]:
			return person.owner.combat_hot_get(int(person.unit), StringName(field), false)
		return person.owner.combat_hot_get(int(person.unit), StringName(field), 0.0)
	if field in ["fatigue", "fatigue_rest"]: return Fatigue.read(person.body, field)
	if int(person.unit) >= 0:
		if field == "work_resting":
			return person.owner.combat_hot_get(int(person.unit), StringName(field), false)
		return person.owner.combat_hot_get(int(person.unit), StringName(field), 0.0)
	if person.body is Dictionary:
		if field == "work_resting":
			return person.body.get(field, false)
		return person.body.get(field, 0.0)
	return person.body.get(field)

func _body_set(person: Dictionary, field: String, value: Variant) -> void:
	if person.owner is CrowdOwner:
		person.owner.combat_hot_set(int(person.unit), StringName(field), value)
		if field in ["hp", "ko", "captive", "surrender_pending"]:
			person[field] = value
		return
	if field in ["fatigue", "fatigue_rest"]:
		Fatigue.write(person.body, field, float(value))
		return
	if int(person.unit) >= 0:
		person.owner.combat_hot_set(int(person.unit), StringName(field), value)
		if field in ["hp", "ko", "captive", "surrender_pending"]:
			person[field] = value
		return
	if person.body is Dictionary:
		person.body[field] = value
	else:
		person.body.set(field, value)


func begin_ship_board(person_id: int, vehicle_id: String, requester_id: int, berth: int = -1, test_dispatch: bool = false) -> Dictionary:
	return _begin_ship_action("ship_board", person_id, vehicle_id, requester_id, berth, TerrainArmy.INVALID_CELL, test_dispatch)

func begin_ship_disembark(person_id: int, vehicle_id: String, requester_id: int, shore: Vector2i = TerrainArmy.INVALID_CELL, test_dispatch: bool = false, retreat: bool = false) -> Dictionary:
	return _begin_ship_action("ship_disembark", person_id, vehicle_id, requester_id, -1, shore, test_dispatch, retreat)

func begin_ship_helm(person_id: int, vehicle_id: String, requester_id: int, test_dispatch: bool = false, retreat: bool = false) -> Dictionary:
	return _begin_ship_action("ship_helm", person_id, vehicle_id, requester_id, 0, TerrainArmy.INVALID_CELL, test_dispatch, retreat)

func begin_ship_walk(person_id: int, local_target: Vector2, requester_id: int, test_dispatch: bool = false) -> Dictionary:
	var query: Dictionary = lab.site_controller.vehicles.ship_walk_query(person_id, local_target, requester_id, test_dispatch)
	if not query.ok: return query
	return _begin_ship_path_job("ship_walk", query, requester_id, test_dispatch)

func begin_ship_cross(person_id: int, target_id: String, requester_id: int, berth: int = -1, test_dispatch: bool = false) -> Dictionary:
	var query: Dictionary = lab.site_controller.vehicles.ship_cross_query(person_id, target_id, berth, requester_id, test_dispatch)
	if not query.ok: return query
	return _begin_ship_path_job("ship_cross", query, requester_id, test_dispatch)

func begin_ship_evacuation(person_id: int, path: Array[Vector2]) -> Dictionary:
	var vehicles: Variant = lab.site_controller.vehicles
	var person: Dictionary = vehicles.ship_person(person_id)
	var vehicle: Dictionary = vehicles.ship_for_person(person_id)
	if person.is_empty() or vehicle.is_empty() or is_busy(person_id) or path.size() < 2: return Runtime.fail("BUSY")
	if str(vehicle.get("naval", {}).get("state", "")) != "wrecked" or not person.owner.combat_can_act(int(person.unit)): return Runtime.fail("NO_TARGET")
	return _begin_ship_path_job("ship_evac", {"person": person, "vehicle": vehicle, "path": path}, 0, false)

func _begin_ship_path_job(kind: String, query: Dictionary, requester_id: int, test_dispatch: bool) -> Dictionary:
	var person: Dictionary = query.person
	if is_busy(int(person.id)): return Runtime.fail("BUSY")
	var job := _new_job(person, kind, 0)
	var path: Array = query.path
	var distance := 0.0
	for index in range(1, path.size()): distance += path[index - 1].distance_to(path[index])
	var speed := 1.0 / (TerrainArmy.MOVE_DURATION * (1.0 + Fatigue.slowdown(float(_body_get(person, "fatigue")))))
	if kind == "ship_evac": speed = minf(speed, 0.5)
	job.merge({"vehicle_id": str(query.vehicle.id), "ship_revision": int(query.vehicle.revision),
		"path": path, "speed": speed, "duration": maxf(0.000001, distance / speed),
		"requester_id": requester_id, "test_dispatch": test_dispatch, "cancelled": false,
		"terrain": lab.terrain, "site_state": lab.terrain.site})
	if kind == "ship_cross":
		job.secondary_vehicle_id = str(query.target.id)
		job.target_revision = int(query.target.revision)
		job.berth_id = int(query.berth_id)
	_jobs[str(person.id)] = job
	return Runtime.ok("原人物開始甲板／接舷／撤岸路徑", {"seconds": float(job.duration)})

func _begin_ship_action(kind: String, person_id: int, vehicle_id: String, requester_id: int, berth: int, shore: Vector2i, test_dispatch: bool, retreat: bool = false) -> Dictionary:
	if is_busy(person_id): return Runtime.fail("BUSY")
	var vehicles: Variant = lab.site_controller.vehicles
	var check: Dictionary = vehicles.ship_action_query(kind, person_id, vehicle_id, berth, shore, requester_id, test_dispatch, {}, retreat)
	if not check.ok: return check
	var person: Dictionary = check.person
	var job := _new_job(person, kind, 0)
	job.merge({"vehicle_id": vehicle_id, "berth_id": int(check.berth_id), "shore": check.shore,
		"requester_id": requester_id, "test_dispatch": test_dispatch, "retreat": retreat,
		"ship_revision": int(check.vehicle.revision), "terrain": lab.terrain, "site_state": lab.terrain.site,
		"source_berth": int(person.row.get("berth_id", -1)), "duration": 2.0, "cancelled": false})
	if kind == "ship_helm":
		var path: Array[Vector2] = vehicles.ship_deck_path(person_id, vehicles.Ship.local_position(str(check.vehicle.ship_type), 0)) if person.row.has("ship_deck_position") else vehicles.Ship.helm_path(str(check.vehicle.ship_type), int(person.row.berth_id))
		if path.is_empty(): return Runtime.fail("UNREACHABLE", "沒有船型的合法駕駛通路")
		var distance := 0.0
		for index in range(1, path.size()): distance += path[index - 1].distance_to(path[index])
		job.path = path
		job.speed = 1.0 / (TerrainArmy.MOVE_DURATION * (1.0 + Fatigue.slowdown(float(_body_get(person, "fatigue")))))
		job.duration = distance / float(job.speed)
	_jobs[str(person_id)] = job
	return Runtime.ok("原人物開始船內／水岸作業；完成前保留原關係", {"seconds": float(job.duration)})

func _ship_job_context(job: Dictionary) -> Dictionary:
	var vehicles: Variant = lab.site_controller.vehicles
	if str(job.kind) in ["ship_helm", "ship_walk", "ship_cross", "ship_evac"]:
		var person: Dictionary = vehicles.ship_person(int(job.executor_id))
		var vehicle: Dictionary = vehicles.records().get(str(job.vehicle_id), {})
		if person.is_empty() or not vehicles.is_ship(vehicle) or not is_same(job.terrain, lab.terrain) or not is_same(job.site_state, lab.terrain.site) or str(person.row.get("embarked_vehicle_id", "")) != str(job.vehicle_id) or not vehicle.move.is_empty(): return Runtime.fail("STALE")
		return Runtime.ok("", {"person": person, "vehicle": vehicle})
	var check: Dictionary = vehicles.ship_action_query(str(job.kind), int(job.executor_id), str(job.vehicle_id), int(job.berth_id), job.shore, int(job.requester_id), bool(job.test_dispatch), job, bool(job.retreat))
	if not check.ok: return check
	if int(check.person.hit) != int(job.executor_hit) or lab.terrain.index(check.person.cell) != int(job.executor_cell): return Runtime.fail("INTERRUPTED", "原人物受擊或位置已變；未提交登離船")
	return check

func advance_ship_jobs(action_seconds: float) -> void:
	if not is_finite(action_seconds) or action_seconds <= 0.0 or bool(lab.terrain.site.get("paused", false)): return
	var keys: Array = _jobs.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return int(a) < int(b))
	for key: String in keys:
		var job: Dictionary = _jobs[key]
		if str(job.kind) == "ground_boundary":
			_advance_ground_boundary(key, job, action_seconds)
		elif str(job.kind).begins_with("ship_"):
			_advance_ship_job(key, job, action_seconds)

func _advance_ship_job(key: String, job: Dictionary, seconds: float) -> void:
	var check := _ship_job_context(job)
	if not check.ok:
		_finish(key, check)
		return
	var person: Dictionary = check.person
	if str(job.kind) == "ship_evac" and float(person.hp) > 0.0 and not person.owner.combat_can_act(int(person.unit)):
		lab.site_controller.vehicles._kill_ship_person(person)
		_finish(key, _commit_ship_path(job))
		return
	if str(job.kind) in ["ship_helm", "ship_walk", "ship_cross", "ship_evac"] and float(person.hp) <= 0.0:
		_finish(key, _commit_ship_path(job))
		return
	var work := minf(seconds, maxf(0.0, float(job.duration) - float(job.elapsed)))
	job.elapsed = minf(float(job.duration), float(job.elapsed) + work)
	# This is movement on the original ACTION clock, not WORK on the game clock.
	# Original fatigue handles its no-rest state; the boat's crew work is separate.

func _settle_ship_job(key: String, job: Dictionary) -> void:
	var check := _ship_job_context(job)
	if not check.ok:
		_finish(key, check)
		return
	if str(job.kind) == "ship_evac" and float(check.person.hp) > 0.0 and not check.person.owner.combat_can_act(int(check.person.unit)):
		lab.site_controller.vehicles._kill_ship_person(check.person)
		_finish(key, _commit_ship_path(job))
		return
	if str(job.kind) in ["ship_helm", "ship_walk", "ship_cross", "ship_evac"] and float(check.person.hp) <= 0.0:
		_finish(key, _commit_ship_path(job))
		return
	if float(job.elapsed) + 0.00000001 < float(job.duration): return
	var result: Dictionary = _commit_ship_path(job)
	_finish(key, result)

func _commit_ship_path(job: Dictionary) -> Dictionary:
	var vehicles: Variant = lab.site_controller.vehicles
	var person: Dictionary = vehicles.ship_person(int(job.executor_id))
	if str(job.kind) in ["ship_cross", "ship_evac"] and not person.is_empty() and float(person.hp) <= 0.0:
		var location: Dictionary = vehicles.ship_death_location(int(person.id))
		if location.has("local_position"): person.row.ship_death_local = location.local_position
		return Runtime.ok("原死亡入口保留途中物品在原船殘骸")
	match str(job.kind):
		"ship_helm": return vehicles.commit_ship_helm(job)
		"ship_walk": return vehicles.commit_ship_walk(job)
		"ship_cross": return vehicles.commit_ship_cross(job)
		"ship_evac": return vehicles.commit_ship_evacuation(job)
	return vehicles.commit_ship_person(job)


# V1 fixed seats share their own boat's original loot collection; no deck navmap.
# Land access still needs the original validated berth-to-shore contact.
func _ship_loot_contact(executor: Dictionary, source: Dictionary) -> bool:
	var vehicles: Variant = lab.site_controller.vehicles
	var source_ship: String = vehicles.ship_holder_vehicle(source.holder)
	var target_ship: String = vehicles.ship_holder_vehicle(executor.holder)
	if source_ship.is_empty(): return false
	var ship: Dictionary = vehicles.records().get(source_ship, {})
	if not vehicles.is_ship(ship) or not ship.move.is_empty() or not vehicles.ship_job(source_ship).is_empty(): return false
	if not target_ship.is_empty(): return source_ship == target_ship
	return vehicles.ship_supply_contact(ship, executor.cell)

# Add Housing preload and append these methods to SitePersonActions.
# Skip housing_return in game-WORK advance and branch before after-contact
# _job_context. cancel keeps the original pending step until physically settled.
func begin_housing_return(person_id: int, requester_id: int) -> Dictionary:
	if is_busy(person_id): return Runtime.fail("BUSY")
	var registered: Dictionary = Housing.relation(lab, person_id)
	if registered.is_empty(): return Runtime.fail("NO_TARGET", "須先分配原住宅")
	var checked: Dictionary = Housing.context(lab, person_id, str(registered.house_id), requester_id)
	if not checked.ok: return checked
	if checked.person.owner is CrowdOwner and not checked.person.owner.crowd_site.crowd.has_method("order_housing_step"): return Runtime.fail("CROWD_BUILD_MISMATCH")
	if Housing._attends(lab, person_id): return Runtime.ok("原人物已在家")
	var destination: Vector2i = lab.terrain.cell_from_index(int(registered.cell))
	var route: Array[Vector2i] = lab.terrain.path_between(checked.person.cell, destination, func(cell: Vector2i) -> bool: return prison_blocked(cell, [person_id]))
	if checked.person.cell != destination and route.is_empty(): return Runtime.fail("UNREACHABLE")
	var job := _new_job(checked.person, "housing_return", 0)
	job.merge({"house_id": str(registered.house_id), "cell": int(registered.cell), "requester_id": requester_id, "duration": 0.0,
		"terrain": lab.terrain, "site_state": lab.terrain.site, "cancelled": false, "reason": "", "route_elapsed": 0.5})
	_jobs[str(person_id)] = job
	if person_id == int(lab.controlled_person_id()): lab._clear_movement_input()
	return Runtime.ok("原人物逐格返家；在途作業完成或取消收束後才可保存")

func _housing_job_context(job: Dictionary) -> Dictionary:
	if not is_same(job.terrain, lab.terrain) or not is_same(job.site_state, lab.terrain.site): return Runtime.fail("STALE_SITE")
	var registered: Dictionary = Housing.relation(lab, int(job.executor_id))
	if str(registered.get("house_id", "")) != str(job.house_id) or int(registered.get("cell", -1)) != int(job.cell): return Runtime.fail("STALE_SOURCE")
	var checked: Dictionary = Housing.context(lab, int(job.executor_id), str(job.house_id), int(job.requester_id), true)
	if not checked.ok: return checked
	if int(checked.person.hit) != int(job.executor_hit): return Runtime.fail("INTERRUPTED", "原人物受擊；保留住房並收束原步進")
	if not checked.layout.slots.has(int(job.cell)): return Runtime.fail("STALE_SOURCE", "原返家格已失效")
	return checked

func _cancel_housing_job(job: Dictionary, reason: String = "已取消返家") -> void:
	job.cancelled = true
	job.reason = reason
	job.paused = "CANCELLED"
	var person := _person(int(job.executor_id), false)
	if not person.is_empty() and person.owner is CrowdOwner and person.owner.crowd_site.crowd.has_method("cancel_housing_step"):
		person.owner.crowd_site.crowd.cancel_housing_step(int(person.unit))

func intercept_housing_input(person_id: int) -> bool:
	var job: Dictionary = _jobs.get(str(person_id), {})
	if str(job.get("kind", "")) != "housing_return": return false
	_cancel_housing_job(job, "手動控制取消返家；先收束原步進")
	return true

func advance_housing_jobs(action_seconds: float) -> void:
	if not is_finite(action_seconds) or action_seconds <= 0.0 or bool(lab.terrain.site.get("paused", false)): return
	var keys: Array = _jobs.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return int(a) < int(b))
	for key: String in keys:
		var job: Dictionary = _jobs[key]
		if str(job.kind) != "housing_return" or bool(job.cancelled): continue
		var checked := _housing_job_context(job)
		if not checked.ok:
			_cancel_housing_job(job, str(checked.message))
			continue
		var person: Dictionary = checked.person
		if bool(person.moving) or not _prison_stopped(person): continue
		if not _ready(person): _cancel_housing_job(job, "原返家人物已開始其他動作"); continue
		if lab.terrain.index(person.cell) == int(job.cell): continue
		job.route_elapsed = float(job.route_elapsed) + action_seconds
		if float(job.route_elapsed) < 0.5: continue
		job.route_elapsed = 0.0
		var route: Array[Vector2i] = lab.terrain.path_between(person.cell, lab.terrain.cell_from_index(int(job.cell)), func(cell: Vector2i) -> bool: return prison_blocked(cell, [int(job.executor_id)]))
		if route.is_empty(): job.paused = "WAIT_OCCUPANCY"; continue
		var committed := false
		if person.owner is CrowdOwner:
			committed = bool(person.owner.crowd_site.crowd.order_housing_step(int(person.unit), lab.terrain.index(route[0])))
			if committed: person.owner.crowd_site._occupancy_cache.clear()
		elif int(person.unit) >= 0: committed = person.owner._reserve_combat_step(int(person.unit), route[0])
		else: committed = person.owner.step(route[0] - Vector2i(person.cell), false)
		job.paused = "" if committed else "WAIT_OCCUPANCY"

func _settle_housing_job(key: String, job: Dictionary) -> void:
	var person := _person(int(job.executor_id), false)
	if not is_same(job.terrain, lab.terrain) or not is_same(job.site_state, lab.terrain.site): _finish(key, Runtime.fail("STALE_SITE")); return
	if person.is_empty(): _cancel_housing_job(job, "原人物引用失效，保存保持受阻"); return
	if not bool(job.cancelled):
		var checked := _housing_job_context(job)
		if not checked.ok: _cancel_housing_job(job, str(checked.message))
	if bool(job.cancelled):
		if bool(person.moving) or not _prison_stopped(person): return
		_finish(key, Runtime.ok(str(job.reason)))
		return
	if bool(person.moving) or lab.terrain.index(person.cell) != int(job.cell): return
	if person.owner is CrowdOwner:
		var state: PackedInt64Array = person.owner.crowd_site.crowd.escort_state(int(person.unit))
		if state.size() != 2 or int(state[1]) >= 0: return
		person.owner.crowd_site.crowd.cancel_housing_step(int(person.unit))
	if _prison_stopped(person) and Housing._attends(lab, int(job.executor_id), job): _finish(key, Runtime.ok("原人物已到家；供養与疲勞仍由原 owner 處理"))


# Candidate methods for the EXISTING SitePersonActions _jobs owner.
# No bind/save runs during contacts. A ready result is committed by TerrainLab
# only after its original complete shared step and clock publication.

func begin_ground_boundary(identity: int, prepared: Dictionary) -> Dictionary:
	if not bool(prepared.get("ok", false)) or not prepared.get("request") is Dictionary:
		return Runtime.fail("INVALID", "缺少原存檔槽跨界預檢")
	if is_busy(identity): return Runtime.fail("BUSY", "原人物作業尚未結束")
	var person := _person(identity)
	if person.is_empty() or int(person.unit) >= 0 or not bool(person.player) or not _ready(person) or person.owner is CrowdOwner:
		return Runtime.fail("BUSY", "只允許停穩且可行動的原受控 GD 獨立人物")
	var request: Dictionary = prepared.request
	if int(request.get("person_id", -1)) != identity or request.get("from_cell") != person.cell \
			or request.get("direction") not in TerrainData.DIRECTIONS or lab.terrain.contains(person.cell + request.direction) \
			or int(request.get("hit_revision", -1)) != int(person.hit):
		return Runtime.fail("STALE", "原人物與跨界預檢不一致")
	var job := _new_job(person, "ground_boundary", identity)
	job.duration = TerrainTestCharacter.MOVE_DURATION
	job.request = request.duplicate(true)
	job.terrain = lab.terrain
	job.site_state = lab.terrain.site
	job.owner = person.owner
	_jobs[str(identity)] = job
	person.owner.release_movement_intent()
	return Runtime.ok("原人物開始跨界一步", {"seconds": float(job.duration)})

func _ground_boundary_context(job: Dictionary) -> Dictionary:
	if not is_same(job.terrain, lab.terrain) or not is_same(job.site_state, lab.terrain.site):
		return Runtime.fail("STALE", "原跨界地點已變")
	var person := _person(int(job.executor_id))
	if person.is_empty() or int(person.unit) >= 0 or not bool(person.player) or not _ready(person) \
			or not is_same(person.owner, job.owner) or person.cell != job.request.from_cell or int(person.hit) != int(job.executor_hit):
		return Runtime.fail("INTERRUPTED", "原人物移動、受擊或失能，跨界未提交")
	return Runtime.ok()

func _advance_ground_boundary(key: String, job: Dictionary, action_seconds: float) -> void:
	var context := _ground_boundary_context(job)
	if not context.ok:
		_finish(key, context)
		return
	job.elapsed = minf(float(job.duration), float(job.elapsed) + action_seconds)

func _settle_ground_boundary(key: String, job: Dictionary) -> void:
	var context := _ground_boundary_context(job)
	if not context.ok:
		_finish(key, context)
		return
	if float(job.elapsed) + 0.00000001 < float(job.duration): return
	_finish(key, Runtime.ok("原跨界一步已完成，等待本 shared step 結算", {
		"ground_boundary_ready": true, "request": job.request.duplicate(true),
		"completed_action_seconds": float(job.elapsed)}))

# P3 candidate for the EXISTING SitePersonActions owner. No separate jobs,
# movement, inventory or fatigue owner. Initial admission is GD Army/HOLD only.
const FireWorkCollision = preload("res://scripts/terrain_lab/terrain_weapon_collision.gd")
var _next_fire_job_token := 1

func begin_fire_suppress(requester_id: int, executor_id: int, target_key: String, slot_cell: Vector2i,
		test_dispatch: bool = false) -> Dictionary:
	return _begin_fire_work(requester_id, executor_id, target_key, slot_cell, test_dispatch, "SUPPRESS")

func begin_fire_ignite(requester_id: int, executor_id: int, target_key: String, slot_cell: Vector2i,
		test_dispatch: bool = false) -> Dictionary:
	return _begin_fire_work(requester_id, executor_id, target_key, slot_cell, test_dispatch, "IGNITE")

func _begin_fire_work(requester_id: int, executor_id: int, target_key: String, slot_cell: Vector2i, test_dispatch: bool, mode: String) -> Dictionary:
	if not is_instance_valid(lab) or lab.terrain == null or bool(lab.terrain.site.get("paused", false)): return Runtime.fail("BUSY")
	if not lab.exchange_enabled or lab.crowd_site != null and lab.crowd_site.active and not lab.crowd_site.fire_host_active(): return Runtime.fail("UNSUPPORTED_BACKEND")
	if is_busy(executor_id) or lab.fire_reservations.has(executor_id): return Runtime.fail("BUSY", "原人物工作或射擊準備尚未收束")
	var person := _person(executor_id)
	var checked := _fire_suppress_person(person, requester_id, test_dispatch)
	if not checked.ok: return checked
	if not _ready(person): return Runtime.fail("BUSY")
	var target := Runtime.fire_work_target(lab.terrain, target_key, mode)
	if not target.ok: return target
	if bool(target.complete): return Runtime.ok("目標工作已完成；未建立作業或扣補給", {"complete": true})
	var contact := _fire_suppress_contact(target, slot_cell, executor_id)
	if not contact.ok: return contact
	var profile := SiteCombatRules.fire_work_profile(mode)
	var supply_field := str(profile.supply_field)
	if not person.holder.get(supply_field) is int or int(person.holder[supply_field]) <= 0 \
		or int(person.holder[supply_field]) > int(profile.supply_cap_q): return Runtime.fail("NO_SUPPRESSION_SUPPLY" if mode == "SUPPRESS" else "NO_IGNITION_SUPPLY")
	if _next_fire_job_token >= 2147483647: return Runtime.fail("WORK_SEQUENCE_EXHAUSTED")
	var team: Variant = person.owner
	var token := _next_fire_job_token
	var movement: Dictionary = team.begin_suppress_approach(executor_id, token, slot_cell, team.get_order_serial())
	if not movement.ok: return movement
	# No further fallible admission after the original Registry accepts this lease.
	_next_fire_job_token += 1
	var job := _new_job(person, "fire_suppress", 0)
	job.merge({"terrain": lab.terrain, "site_state": lab.terrain.site, "executor_owner": team, "executor_body": person.body,
		"executor_holder": person.holder, "executor_cargo": person.cargo, "executor_version": int(person.holder.version),
		"executor_hp": float(person.hp), "requester_id": requester_id, "test_dispatch": test_dispatch, "job_token": token,
		"order_serial": team.get_order_serial(), "ranged_order_serial": team.ranged_order_serial, "target_key": target_key,
		"generation": int(target.generation), "slot": slot_cell, "lease": movement.lease, "registry": movement.registry,
		"phase": "MOVING_TO_SLOT", "cancelled": false, "cancel_result": {}, "pending": {}, "fraction_q": 0.0,
		"action_deadline": lab.fire_action_cursor + float(profile.job_timeout_seconds), "last_interval_end": lab.fire_action_cursor,
		"approach_deadline": lab.fire_action_cursor + float(profile.approach_timeout_seconds),
		"committed_q": 0, "supply_q": int(person.holder[supply_field]), "profile_version": str(profile.config_version), "fire_work_mode": mode, "supply_field": supply_field})
	_jobs[str(executor_id)] = job
	return Runtime.ok("原人物接近原登記工作槽；到位前不扣補給", {"executor_id": executor_id, "job_token": token, "mode": mode})

func _fire_suppress_person(person: Dictionary, requester_id: int, test_dispatch: bool, allow_native_approach: bool = false) -> Dictionary:
	if person.is_empty() or not (person.owner is TerrainArmy or person.owner is CrowdPersonOwner) or int(person.unit) < 0: return Runtime.fail("UNSUPPORTED_EXECUTOR")
	var team: Variant = person.owner
	var native := team is CrowdPersonOwner
	var identity := int(person.person_id)
	var index := int(person.unit)
	if native:
		if lab.crowd_site == null or not lab.crowd_site.active or not team.has_army() or not team.is_member(index) \
			or not team.crowd_site.fire_host_active() or identity == int(lab.controlled_person_id()): return Runtime.fail("BUSY")
	elif not lab.combat_armies.has(team) or not team.is_member(index) or team.is_controlled_person(index):
		return Runtime.fail("BUSY")
	if not team.combat_can_act(index) or float(person.hp) <= 0.0 or float(person.ko) > 0.0 or bool(person.captive): return Runtime.fail("BUSY")
	if not lab.site_controller.vehicles._authorized(team, requester_id, identity, test_dispatch): return Runtime.fail("NO_AUTHORITY")
	var backing: Variant = team._command_owner(index) if native else team
	var backing_index: int = team._command_index(index) if native else index
	var garrisoned: bool = bool(team.crowd_site.formation_state(team.formation_index).get("garrisoned", false)) if native else not team.garrison_feature_id.is_empty()
	var own_native_approach: bool = native and (allow_native_approach or team._suppress_approaches.has(identity))
	var on_ship := false
	var blocked_step := false
	if native:
		on_ship = not str(person.body.get("embarked_vehicle_id", "")).is_empty()
		blocked_step = bool(_body_get(person, "attack")) or bool(person.moving) and not own_native_approach
	else:
		on_ship = team._ship_embarked(index) or team._ship_in_journey(index)
		blocked_step = team._combat_action_blocks_step(index)
	var rescued: bool = backing is TerrainArmy and backing._unit_rescues.has(backing_index)
	if team.combat_order != TerrainArmy.CombatOrder.HOLD or garrisoned or on_ship or blocked_step \
		or rescued or not person.body.get("work_task", {}).is_empty() or is_guarding(identity) \
		or lab.site_controller.work_team.is_assigned(identity) or lab.site_controller._is_delivering_person(identity) \
		or lab.site_controller.vehicles.is_operator(identity) or lab.site_controller.vehicles.is_siege_crew(identity): return Runtime.fail("BUSY")
	if lab.site_controller.region_operation_pending(): return Runtime.fail("BUSY")
	return Runtime.ok("", {"person": person})

func _fire_suppress_contact(target: Dictionary, slot: Vector2i, executor_id: int) -> Dictionary:
	var data: TerrainData = lab.terrain
	var profile := SiteCombatRules.fire_suppression_profile()
	if not data.contains(slot) or not data.is_walkable(slot) or data.water_kind[data.index(slot)] != 0: return Runtime.fail("NO_WORK_SLOT")
	if Runtime.fire_hazard_at(data, slot) > float(profile.slot_risk_max): return Runtime.fail("UNSAFE_WORK_SLOT")
	var exit_exists := false
	for direction: Vector2i in TerrainData.DIRECTIONS:
		var next := slot + direction
		if data.can_step(slot, next) and Runtime.fire_hazard_at(data, next) <= float(profile.slot_risk_max) \
			and not prison_blocked(next, [executor_id]): exit_exists = true; break
	if not exit_exists: return Runtime.fail("NO_SAFE_ROUTE", "原工作槽沒有仍可用的相鄰退出格")
	var descriptor: Dictionary = target.descriptor
	var eye := float(data.effective_height(slot)) + 1.0
	if absf(eye - float(descriptor.height)) > float(profile.maximum_contact_height): return Runtime.fail("OUT_OF_RANGE")
	lab._capture_fire_static() # Disposable collision view of original parts, never new geometry.
	var from := Vector3(float(slot.x) + 0.5, float(slot.y) + 0.5, eye)
	for value: int in descriptor.cells:
		var cell := data.cell_from_index(value)
		if absi(cell.x - slot.x) + absi(cell.y - slot.y) != 1: continue
		var to := Vector3(float(cell.x) + 0.5, float(cell.y) + 0.5, eye)
		var blocked := false
		var bounds := Rect2(Vector2(from.x, from.y), Vector2.ZERO).expand(Vector2(to.x, to.y)).grow(0.015)
		for y in range(floori(bounds.position.y), floori(bounds.end.y) + 1):
			for x in range(floori(bounds.position.x), floori(bounds.end.x) + 1):
				var sample := Vector2i(x, y)
				if not data.contains(sample): blocked = true; continue
				for collider: Dictionary in lab._fire_static_buckets.get(sample, []):
					if str(collider.type) == "structure" and str(target.key) == "feature:" + str(collider.feature) + ":" + str(collider.part): continue
					if not FireWorkCollision.segment_prism_contact(from, to, collider.bounds, float(collider.lower), float(collider.upper), 0.015).is_empty(): blocked = true
				var terrain_top := float(data.height_levels[data.index(sample)])
				if data.static_blocked[data.index(sample)] != 0 and int(data.feature_at[data.index(sample)]) == 0 and sample != cell: terrain_top += 2.0
				if not FireWorkCollision.segment_prism_contact(from, to, Rect2(Vector2(sample), Vector2.ONE), -1000.0, terrain_top, 0.015).is_empty(): blocked = true
		if not blocked: return Runtime.ok("", {"target_cell": cell})
	return Runtime.fail("LINE_OF_FIRE_BLOCKED", "须真正到達可接觸原部件的側面；不能隔牆冷卻")

func _fire_suppress_context(job: Dictionary) -> Dictionary:
	if not is_same(lab.terrain, job.terrain) or not is_same(lab.terrain.site, job.site_state): return Runtime.fail("STALE_SITE")
	var person := _person(int(job.executor_id))
	var check := _fire_suppress_person(person, int(job.requester_id), bool(job.test_dispatch))
	if not check.ok: return check
	var team: Variant = person.owner
	if not is_same(team, job.executor_owner) or not is_same(person.body, job.executor_body) \
		or not is_same(person.holder, job.executor_holder) or not is_same(person.cargo, job.executor_cargo) \
		or int(person.holder.version) != int(job.executor_version) or int(person.hit) != int(job.executor_hit) \
		or float(person.hp) < float(job.executor_hp) or team.get_order_serial() != int(job.order_serial) \
		or team.ranged_order_serial != int(job.ranged_order_serial): return Runtime.fail("INTERRUPTED")
	var movement: Dictionary = team.suppress_approach_query(int(job.executor_id), int(job.job_token))
	if not movement.ok or not is_same(movement.get("lease"), job.lease) \
		or not is_same(movement.get("registry"), job.registry): return Runtime.fail("STALE_WORK_SLOT")
	var target := Runtime.fire_work_target(lab.terrain, str(job.target_key), str(job.get("fire_work_mode", "SUPPRESS")), int(job.generation))
	if not target.ok: return target
	var contact := _fire_suppress_contact(target, job.slot, int(job.executor_id))
	if not contact.ok: return contact
	if _threat(person, {}): return Runtime.fail("THREAT")
	return Runtime.ok("", {"person": person, "movement": movement, "target": target, "target_cell": contact.target_cell})

func _cancel_fire_suppress(job: Dictionary, result: Dictionary) -> void:
	job.cancelled = true
	job.cancel_result = result
	job.pending = {}
	job.paused = str(result.get("code", "CANCELLED"))
	job.phase = "SETTLING"
	if is_instance_valid(job.executor_owner): job.executor_owner.release_suppress_approach(int(job.executor_id), int(job.job_token))
	elif is_instance_valid(job.registry): job.registry.release_work_slot(job.lease)

func _settle_cancelled_fire_suppress(key: String, job: Dictionary) -> void:
	if is_instance_valid(job.executor_owner):
		var movement: Dictionary = job.executor_owner.release_suppress_approach(int(job.executor_id), int(job.job_token))
		if not bool(movement.get("done", false)):
			var person := _person(int(job.executor_id), false)
			if not person.is_empty() and bool(person.moving): return
			var queried: Dictionary = job.executor_owner.suppress_approach_query(int(job.executor_id), int(job.job_token))
			if str(queried.get("phase", "")) == "SETTLING" and not bool(queried.get("done", false)): return
	if is_instance_valid(job.registry): job.registry.release_work_slot(job.lease)
	_finish(key, job.cancel_result.duplicate(true))

func advance_fire_jobs(action_begin: float, action_end: float, game_seconds: float) -> void:
	if not is_finite(action_begin) or not is_finite(action_end) or not is_finite(game_seconds) or game_seconds <= 0.0 \
		or action_end <= action_begin or bool(lab.terrain.site.get("paused", false)): return
	var profile := SiteCombatRules.fire_suppression_profile()
	if action_end - action_begin > float(profile.maximum_action_slice) + Runtime.FIRE_EPS: return
	var fire_keys: Array = _jobs.keys()
	fire_keys.sort_custom(func(a: String, b: String) -> bool: return int(a) < int(b))
	for key: String in fire_keys:
		var job: Dictionary = _jobs[key]
		if str(job.kind) != "fire_suppress": continue
		if bool(job.cancelled): _settle_cancelled_fire_suppress(key, job); continue
		if action_end <= float(job.last_interval_end) + Runtime.FIRE_EPS: continue
		job.pending = {}
		job.last_interval_end = action_end
		if action_end > float(job.action_deadline): _cancel_fire_suppress(job, Runtime.fail("WORK_DEADLINE")); continue
		var check := _fire_suppress_context(job)
		if not check.ok: _cancel_fire_suppress(job, check); continue
		if bool(check.target.complete): _cancel_fire_suppress(job, Runtime.ok("原工作目標已完成；原損壞與燃料保持")); continue
		job.supply_q = int(check.person.holder.get(str(job.get("supply_field", "fire_lab_suppression_q")), 0))
		if int(job.supply_q) <= 0: _cancel_fire_suppress(job, Runtime.fail("NO_SUPPRESSION_SUPPLY")); continue
		if str(check.movement.phase) != "ARRIVED":
			if action_end > float(job.approach_deadline): _cancel_fire_suppress(job, Runtime.fail("WORK_APPROACH_DEADLINE")); continue
			job.phase = "MOVING_TO_SLOT"
			job.paused = "MOVING"
			continue
		if bool(check.person.moving) or check.person.cell != job.slot or not _ready(check.person):
			_cancel_fire_suppress(job, Runtime.fail("INTERRUPTED")); continue
		var fatigue := float(_body_get(check.person, "fatigue"))
		var resting := Fatigue.needs_work_rest(fatigue, bool(_body_get(check.person, "work_resting")))
		_body_set(check.person, "work_resting", resting)
		if resting: job.phase = "REST"; job.paused = "REST"; continue
		job.phase = "WORKING"
		job.paused = ""
		var direction: Vector2i = check.target_cell - Vector2i(job.slot)
		if check.person.owner is TerrainArmy:
			check.person.owner.facing[int(check.person.unit)] = direction
			check.person.owner._mark_visual_row(int(check.person.unit))
		job.pending = {"begin": action_begin, "end": action_end, "game_seconds": game_seconds}

func _fire_work_handled_seconds(job: Dictionary, game_seconds: float) -> float:
	# Suppress jobs do not enter generic advance/commit. Reserve this original
	# game-time interval against a second fatigue/rest charge before contacts.
	return minf(game_seconds, float(job.pending.get("game_seconds", 0.0))) if str(job.phase) == "WORKING" else 0.0

func blocks_fatigue_rest(identity: int) -> bool:
	var job: Dictionary = _jobs.get(_job_key_for(identity), {})
	if job.is_empty(): return false
	if str(job.kind) == "captive_craft":
		return str(job.paused) != "REST" or not _captive_craft_job_context(job).ok
	if str(job.kind) == "technology_lesson":
		return str(job.paused) != "REST" or not _technology_lesson_context(job).ok
	if str(job.kind) != "fire_suppress" or str(job.phase) != "REST" or not job.pending.is_empty() or bool(job.cancelled): return true
	var check := _fire_suppress_context(job)
	# Only a centred, stopped, safe rest phase relaxes the existing busy gate.
	# Lab still checks ALL original shared-pool members and its other rest guards.
	return not check.ok or str(check.movement.phase) != "ARRIVED" or bool(check.person.moving) or not _ready(check.person)

func _settle_fire_suppress(key: String, job: Dictionary) -> void:
	if bool(job.cancelled): _settle_cancelled_fire_suppress(key, job); return
	var check := _fire_suppress_context(job)
	if not check.ok: _cancel_fire_suppress(job, check); _settle_cancelled_fire_suppress(key, job); return
	if job.pending.is_empty(): return
	var pending: Dictionary = job.pending
	job.pending = {} # The same contact-completion callback cannot bill twice.
	if str(check.movement.phase) != "ARRIVED" or bool(check.person.moving) or not _ready(check.person):
		_cancel_fire_suppress(job, Runtime.fail("INTERRUPTED")); return
	if bool(check.target.complete): _cancel_fire_suppress(job, Runtime.ok("原工作目標已完成")); return
	var person: Dictionary = check.person
	var profile := SiteCombatRules.fire_work_profile(str(job.get("fire_work_mode", "SUPPRESS")))
	var action_seconds := float(pending.end) - float(pending.begin)
	var game_ratio := float(pending.game_seconds) / action_seconds
	var rate := Fatigue.effort_rate(person.body)
	var work := minf(action_seconds, maxf(0.0, Fatigue.WORK_REST_AT - float(_body_get(person, "fatigue"))) / rate / game_ratio)
	if work <= Runtime.FIRE_EPS: job.phase = "REST"; job.paused = "REST"; _body_set(person, "work_resting", true); return
	var exact := float(job.fraction_q) + work * int(profile.supply_q_per_second)
	var requested := floori(exact + Runtime.FIRE_EPS)
	if requested == 0:
		job.fraction_q = exact
		_charge_fire_suppress_work(person, work * game_ratio)
		return
	var prepared := Runtime.fire_prepare_suppression(lab.terrain, str(job.target_key), int(job.generation),
		float(pending.begin), float(pending.begin) + work, requested, person.holder, int(job.executor_version), str(job.get("fire_work_mode", "SUPPRESS")))
	if not prepared.ok:
		if str(prepared.get("code", "")) == "CAPACITY_DEFERRED": job.paused = "CAPACITY_DEFERRED"; return
		_cancel_fire_suppress(job, prepared); return
	if int(prepared.get("paid_q", 0)) == 0:
		if bool(prepared.get("complete", false)): _cancel_fire_suppress(job, Runtime.ok("原工作目標已完成"))
		return
	# The final finite holder remainder may end before this action slice ends.
	# Previously earned sub-quantum work already paid its fatigue in an earlier
	# interval, so only newly productive seconds belong to this interval's debit.
	var charged_work := work
	if int(prepared.paid_q) < requested:
		charged_work = minf(work, maxf(0.0, float(prepared.paid_q) - float(job.fraction_q)) / int(profile.supply_q_per_second))
		prepared = Runtime.fire_prepare_suppression(lab.terrain, str(job.target_key), int(job.generation),
			float(pending.begin), float(pending.begin) + charged_work, int(prepared.paid_q), person.holder, int(job.executor_version), str(job.get("fire_work_mode", "SUPPRESS")))
		if not prepared.ok or int(prepared.get("paid_q", 0)) <= 0: _cancel_fire_suppress(job, prepared); return
	# No callbacks intervene between this final person/lease query and Runtime's
	# original-holder debit + queued effect transaction.
	check = _fire_suppress_context(job)
	if not check.ok: _cancel_fire_suppress(job, check); return
	var committed := Runtime.fire_commit_suppression(lab.terrain, prepared)
	if not committed.ok: _cancel_fire_suppress(job, committed); return
	var paid := int(committed.paid_q)
	job.executor_version = int(person.holder.version)
	job.supply_q = int(person.holder[str(profile.supply_field)])
	job.committed_q = int(job.committed_q) + paid
	job.fraction_q = maxf(0.0, exact - requested) if paid == requested else 0.0
	var effort := charged_work * game_ratio
	_charge_fire_suppress_work(person, effort)
	job.elapsed = float(job.elapsed) + float(paid) / int(profile.supply_q_per_second)
	if int(job.supply_q) == 0: _cancel_fire_suppress(job, Runtime.fail("NO_SUPPRESSION_SUPPLY", "本人有限補給已用盡；既有已付效果保留"))

func _charge_fire_suppress_work(person: Dictionary, game_seconds: float) -> void:
	var state := Fatigue.advance(float(_body_get(person, "fatigue")), float(_body_get(person, "fatigue_rest")),
		game_seconds, Fatigue.effort_rate(person.body), false)
	_body_set(person, "fatigue", state[0])
	_body_set(person, "fatigue_rest", state[1])
	if state[0] >= Fatigue.WORK_REST_AT - Runtime.FIRE_EPS: _body_set(person, "work_resting", true)

# P5 serialization of original _jobs only. No second work clock or holder.
const FIRE_JOBS_CONFIG_VERSION := "site_fire_jobs_v1"
const FIRE_JOB_INTEGER_FIELDS := ["executor_id", "executor_cell", "executor_hit", "executor_version", "requester_id", "job_token", "order_serial", "ranged_order_serial", "generation", "committed_q", "supply_q"]
const FIRE_JOB_NUMBER_FIELDS := ["executor_hp", "fraction_q", "action_deadline", "last_interval_end", "approach_deadline", "elapsed"]
const FIRE_JOB_STRING_FIELDS := ["target_key", "phase", "profile_version", "fire_work_mode", "supply_field", "paused"]

func export_fire_jobs(action_cursor: float) -> Dictionary:
	if not is_instance_valid(lab) or not Runtime._fire_time_valid(action_cursor) or absf(float(lab.fire_action_cursor) - action_cursor) > Runtime.FIRE_EPS: return Runtime.fail("INVALID_FIRE_JOB_BARRIER")
	var rows: Array = []
	var ids: Array = _jobs.keys()
	ids.sort_custom(func(a: String, b: String) -> bool: return int(a) < int(b))
	for id: String in ids:
		var job: Dictionary = _jobs[id]
		if str(job.kind) != "fire_suppress" or not job.pending.is_empty() or not is_instance_valid(job.executor_owner): return Runtime.fail("BUSY", "原人物作業未到保存邊界")
		if not is_same(job.terrain, lab.terrain) or not is_same(job.site_state, lab.terrain.site): return Runtime.fail("STALE_FIRE_JOB")
		if not bool(job.cancelled):
			var context := _fire_suppress_context(job)
			if not context.ok: return Runtime.fail("BUSY", "原工作失效尚待既有取消邊界")
		var row := {"team_id": int(job.executor_owner.team_id), "slot": [job.slot.x, job.slot.y], "cancelled": bool(job.cancelled), "test_dispatch": bool(job.test_dispatch), "cancel_result": {}}
		for field: String in FIRE_JOB_INTEGER_FIELDS: row[field] = job[field]
		for field: String in FIRE_JOB_NUMBER_FIELDS: row[field] = job[field]
		for field: String in FIRE_JOB_STRING_FIELDS: row[field] = job[field]
		if bool(job.cancelled):
			row.cancel_result = {"ok": bool(job.cancel_result.get("ok", false)), "code": str(job.cancel_result.get("code", "CANCELLED")), "message": str(job.cancel_result.get("message", ""))}
		rows.append(row)
	var raw := {"version": 1, "config_version": FIRE_JOBS_CONFIG_VERSION, "site_id": str(lab.terrain.site.id), "action_cursor": action_cursor, "next_token": _next_fire_job_token, "jobs": rows}
	var check := validate_fire_jobs_snapshot(raw, action_cursor)
	if not check.ok: return check
	return Runtime.ok("", {"state": raw, "job_tokens": check.job_tokens})

func fire_jobs_save_guard(action_cursor: float) -> Dictionary:
	for job: Dictionary in _jobs.values():
		if str(job.get("kind", "")) != "fire_suppress": return Runtime.fail("BUSY", "其他人物作業尚未完成；完成或取消後再保存")
	var captured := export_fire_jobs(action_cursor)
	return Runtime.ok() if captured.ok else captured

func validate_fire_jobs_snapshot(raw: Variant, action_cursor: float) -> Dictionary:
	if not is_instance_valid(lab) or lab.terrain == null or not Runtime._fire_time_valid(action_cursor) or not Runtime._fire_snapshot_json(raw) \
		or not Runtime._fire_snapshot_keys(raw, ["version", "config_version", "site_id", "action_cursor", "next_token", "jobs"]): return Runtime.fail("INVALID_FIRE_JOBS")
	if not Runtime._building_integer(raw.version, 1, 1) or raw.config_version != FIRE_JOBS_CONFIG_VERSION or raw.site_id != str(lab.terrain.site.id) \
		or not Runtime._building_number(raw.action_cursor, 0.0, float(Runtime.FIRE_MAX_STEP) / Runtime.FIRE_HZ) \
		or absf(float(raw.action_cursor) - action_cursor) > Runtime.FIRE_EPS or not Runtime._building_integer(raw.next_token, 1, 2147483647) \
		or not raw.jobs is Array or raw.jobs.size() > 65536: return Runtime.fail("INVALID_FIRE_JOBS")
	var fields := ["team_id", "slot", "cancelled", "test_dispatch", "cancel_result"]
	fields.append_array(FIRE_JOB_INTEGER_FIELDS)
	fields.append_array(FIRE_JOB_NUMBER_FIELDS)
	fields.append_array(FIRE_JOB_STRING_FIELDS)
	var tokens := {}
	var used_tokens := {}
	var state: Dictionary = raw.duplicate(true)
	state.version = 1
	state.next_token = int(raw.next_token)
	for row: Variant in state.jobs:
		if not Runtime._fire_snapshot_keys(row, fields) or not Runtime._building_integer(row.team_id, 1, 2147483647) \
			or not row.slot is Array or row.slot.size() != 2 or not Runtime._building_integer(row.slot[0], 0, lab.terrain.size.x - 1) \
			or not Runtime._building_integer(row.slot[1], 0, lab.terrain.size.y - 1) or not row.cancelled is bool or not row.test_dispatch is bool:
			return Runtime.fail("INVALID_FIRE_JOB")
		for field: String in FIRE_JOB_INTEGER_FIELDS:
			if not Runtime._building_integer(row[field], 0, 2147483647): return Runtime.fail("INVALID_FIRE_JOB")
			row[field] = int(row[field])
		for field: String in FIRE_JOB_STRING_FIELDS:
			if not row[field] is String or str(row[field]).length() > 512: return Runtime.fail("INVALID_FIRE_JOB")
		for field: String in FIRE_JOB_NUMBER_FIELDS:
			if not Runtime._building_number(row[field], 0.0, 1.0e12): return Runtime.fail("INVALID_FIRE_JOB")
		if int(row.executor_id) < 1 or int(row.requester_id) < 1 or int(row.generation) < 1 or int(row.job_token) < 1 or int(row.job_token) >= int(raw.next_token) \
			or int(row.executor_cell) >= lab.terrain.size.x * lab.terrain.size.y or float(row.fraction_q) >= 1.0 \
			or float(row.last_interval_end) > action_cursor + Runtime.FIRE_EPS or float(row.approach_deadline) > float(row.action_deadline) \
			or row.fire_work_mode not in ["SUPPRESS", "IGNITE"] or row.phase not in ["MOVING_TO_SLOT", "WORKING", "REST", "SETTLING"] \
			or tokens.has(int(row.executor_id)) or used_tokens.has(int(row.job_token)): return Runtime.fail("INVALID_FIRE_JOB")
		var profile := SiteCombatRules.fire_work_profile(str(row.fire_work_mode))
		if row.profile_version != profile.config_version or row.supply_field != profile.supply_field or int(row.supply_q) > int(profile.supply_cap_q) \
			or float(row.action_deadline) > action_cursor + float(profile.job_timeout_seconds) + Runtime.FIRE_EPS \
			or float(row.approach_deadline) > action_cursor + float(profile.approach_timeout_seconds) + Runtime.FIRE_EPS \
			or absf(float(row.elapsed) - float(row.committed_q) / int(profile.supply_q_per_second)) > Runtime.FIRE_EPS: return Runtime.fail("INVALID_FIRE_JOB_PROGRESS")
		if bool(row.cancelled):
			if row.phase != "SETTLING" or not Runtime._fire_snapshot_keys(row.cancel_result, ["ok", "code", "message"]) \
				or not row.cancel_result.ok is bool or not row.cancel_result.code is String or not row.cancel_result.message is String \
				or str(row.cancel_result.code).length() > 128 or str(row.cancel_result.message).length() > 1024: return Runtime.fail("INVALID_FIRE_JOB_CANCEL")
		elif row.phase == "SETTLING" or not row.cancel_result is Dictionary or not row.cancel_result.is_empty() \
			or float(row.action_deadline) + Runtime.FIRE_EPS < action_cursor or int(row.supply_q) <= 0 \
			or absf(float(row.last_interval_end) - action_cursor) > Runtime.FIRE_EPS: return Runtime.fail("INVALID_FIRE_JOB_PHASE")
		row.team_id = int(row.team_id)
		row.slot = [int(row.slot[0]), int(row.slot[1])]
		tokens[int(row.executor_id)] = int(row.job_token)
		used_tokens[int(row.job_token)] = true
	return Runtime.ok("", {"state": state, "job_tokens": tokens})

func prepare_restore_fire_jobs(raw: Variant, navigation_prepared_by_team_id: Dictionary, registry_candidate: SiteDeploymentReservationRegistry,
		action_cursor: float) -> Dictionary:
	# The staged lab already owns validated original terrain/person/holder state.
	# Registry and original Army/Native navigation metadata are still candidates.
	if not _jobs.is_empty() or registry_candidate == null or not is_instance_valid(lab) or absf(float(lab.fire_action_cursor) - action_cursor) > Runtime.FIRE_EPS: return Runtime.fail("BUSY")
	var checked := validate_fire_jobs_snapshot(raw, action_cursor)
	if not checked.ok: return checked
	var jobs := {}
	var expected_people := {}
	var lease_refs := {}
	for row: Dictionary in checked.state.jobs:
		var identity := int(row.executor_id)
		var person := _person(identity, not bool(row.cancelled))
		if person.is_empty() or not (person.owner is TerrainArmy or person.owner is CrowdPersonOwner) or int(person.owner.team_id) != int(row.team_id): return Runtime.fail("STALE_FIRE_JOB_PERSON")
		var team: Variant = person.owner
		var nav: Dictionary = navigation_prepared_by_team_id.get(int(row.team_id), {})
		if not bool(nav.get("ok", false)) or not nav.get("work") is Dictionary: return Runtime.fail("MISSING_FIRE_JOB_NAVIGATION")
		var work: Dictionary = nav.work.get(identity, {})
		var slot := Vector2i(int(row.slot[0]), int(row.slot[1]))
		if work.is_empty() or int(work.job_token) != int(row.job_token) or work.slot != slot or bool(work.cancelled) != bool(row.cancelled) \
			or int(work.order_serial) != int(row.order_serial) or int(work.ranged_order_serial) != int(row.ranged_order_serial) \
			or not is_same(work.terrain, lab.terrain) or not is_same(work.site_state, lab.terrain.site) or not is_same(work.registry, registry_candidate):
			return Runtime.fail("STALE_FIRE_JOB_NAVIGATION")
		if not bool(row.cancelled):
			var admission := _fire_suppress_person(person, int(row.requester_id), bool(row.test_dispatch), team is CrowdPersonOwner)
			if not admission.ok: return admission
			if team.get_order_serial() != int(row.order_serial) or int(nav.ranged_serial) != int(row.ranged_order_serial) \
				or int(person.hit) != int(row.executor_hit) or int(person.holder.version) != int(row.executor_version) \
				or float(person.hp) < float(row.executor_hp) or float(person.hp) <= 0.0 or float(person.ko) > 0.0 or bool(person.captive) \
				or not Runtime._building_integer(person.holder.get(row.supply_field), int(row.supply_q), int(row.supply_q)) \
				or work.lease == null or not is_same(registry_candidate.owner_of(slot), work.lease): return Runtime.fail("STALE_FIRE_JOB_CONTEXT")
			var target := Runtime.fire_work_target(lab.terrain, str(row.target_key), str(row.fire_work_mode), int(row.generation))
			if not target.ok: return target
			var contact := _fire_suppress_contact(target, slot, identity)
			if not contact.ok: return contact
			if _threat(person, {}): return Runtime.fail("THREAT")
			if row.phase in ["WORKING", "REST"] and (bool(person.moving) or person.cell != slot): return Runtime.fail("INVALID_FIRE_JOB_POSITION")
			lease_refs[slot] = work.lease
		var job := _new_job(person, "fire_suppress", 0)
		for field: String in FIRE_JOB_INTEGER_FIELDS: job[field] = row[field]
		for field: String in FIRE_JOB_NUMBER_FIELDS: job[field] = row[field]
		for field: String in FIRE_JOB_STRING_FIELDS: job[field] = row[field]
		job.merge({"terrain": lab.terrain, "site_state": lab.terrain.site, "executor_owner": team, "executor_body": person.body,
			"executor_holder": person.holder if person.holder is Dictionary else {}, "executor_cargo": person.cargo,
			"test_dispatch": bool(row.test_dispatch), "slot": slot, "lease": work.lease, "registry": registry_candidate,
			"cancelled": bool(row.cancelled), "cancel_result": row.cancel_result.duplicate(true), "pending": {}})
		jobs[str(identity)] = job
		expected_people[identity] = {"owner": team, "body": person.body, "holder": person.holder, "cargo": person.cargo,
			"holder_version": int(person.holder.get("version", -1)) if person.holder is Dictionary else -1,
			"hit": int(person.hit), "hp": float(person.hp), "ko": float(person.ko), "captive": bool(person.captive)}
	for nav: Dictionary in navigation_prepared_by_team_id.values():
		for identity: int in nav.get("work", {}):
			if not checked.job_tokens.has(identity): return Runtime.fail("ORPHAN_FIRE_JOB_NAVIGATION")
	return Runtime.ok("", {"jobs": jobs, "next_token": int(checked.state.next_token), "people": expected_people, "leases": lease_refs,
		"jobs_owner": _jobs, "expected_next_token": _next_fire_job_token, "terrain": lab.terrain, "site_state": lab.terrain.site,
		"action_cursor": action_cursor, "registry_candidate": registry_candidate})

func can_publish_restore_fire_jobs(prepared: Dictionary, registry: SiteDeploymentReservationRegistry) -> bool:
	if not bool(prepared.get("ok", false)) or not is_instance_valid(lab) or registry == null or not is_same(_jobs, prepared.get("jobs_owner")) \
		or not _jobs.is_empty() or _next_fire_job_token != int(prepared.get("expected_next_token", -1)) \
		or not is_same(lab.terrain, prepared.get("terrain")) or not is_same(lab.terrain.site, prepared.get("site_state")) \
		or absf(float(lab.fire_action_cursor) - float(prepared.get("action_cursor", -1.0))) > Runtime.FIRE_EPS: return false
	for identity: int in prepared.people:
		var person := _person(identity, not bool(prepared.jobs[str(identity)].cancelled))
		var expected: Dictionary = prepared.people[identity]
		if person.is_empty() or not is_same(person.owner, expected.owner) or not is_same(person.body, expected.body) \
			or not is_same(person.holder, expected.holder) or not is_same(person.cargo, expected.cargo) \
			or int(person.hit) != int(expected.hit) or float(person.hp) != float(expected.hp) \
			or float(person.ko) != float(expected.ko) or bool(person.captive) != bool(expected.captive): return false
		if person.holder is Dictionary and int(person.holder.get("version", -1)) != int(expected.holder_version): return false
	for cell: Vector2i in prepared.leases:
		if not is_same(registry.owner_of(cell), prepared.leases[cell]): return false
	return true

func publish_restore_fire_jobs(prepared: Dictionary, registry: SiteDeploymentReservationRegistry) -> Dictionary:
	if not can_publish_restore_fire_jobs(prepared, registry): return Runtime.fail("STALE_FIRE_JOB_RESTORE")
	# Caller checked ALL original owners before this synchronous, infallible tail.
	for job: Dictionary in prepared.jobs.values(): job.registry = registry
	_jobs = prepared.jobs
	_next_fire_job_token = int(prepared.next_token)
	return Runtime.ok()

# Technology commands remain here, beside the original real handcraft job.
func _technology_site_id() -> String:
	return str(lab.terrain.site.get("id", ""))

func _technology_ref(identity: int) -> Dictionary:
	return {"site_id": _technology_site_id(), "person_id": identity}

# Pure original task/body query for Runtime skill guards and product provenance.
# A caller cannot substitute another learned bystander at the same station.
func _technology_operator_for_task(task: Dictionary, identity: int = 0) -> Dictionary:
	if bool(lab.terrain.site.get("paused", false)) or task.is_empty(): return {}
	if identity <= 0:
		if is_same(task, lab.terrain.site.get("manual", {})): identity = _technology_controlled()
		elif is_same(task, lab.terrain.site.get("worker", {})) and lab.npc != null: identity = int(lab.npc.person_id)
	var person := _person(identity)
	if person.is_empty() or float(person.hp) <= 0.0 or float(person.ko) > 0.0 or bool(person.captive) or bool(person.moving): return {}
	if person.owner is CrowdOwner and not person.owner.crowd_site.work_fatigue_work_start_ready(identity): return {}
	if lab.terrain.index(person.cell) != int(task.get("cell", -1)) or int(task.get("cell", -1)) != int(task.get("work_cell", task.get("cell", -1))): return {}
	var genuine := false
	if person.owner is CrowdOwner and person.body is TerrainTestCharacter:
		# SAME original Actor body, actual Native owner/hot qualification.
		genuine = is_same(person.body, lab.character) and identity == _technology_controlled() and is_same(task, lab.terrain.site.get("manual", {})) \
			or is_same(person.body, lab.npc) and is_same(task, lab.terrain.site.get("worker", {}))
		if not person.owner.combat_can_act(int(person.unit)) or bool(person.owner.combat_hot_get(int(person.unit), &"attack")) or str(person.owner.combat_hot_get(int(person.unit), &"pose")) != "idle" \
			or float(person.owner.combat_hot_get(int(person.unit), &"exchange_stagger", 0.0)) > 0.0: return {}
	elif person.body is Dictionary and int(person.unit) >= 0:
		genuine = is_same(person.body.get("work_task", {}), task) and lab.site_controller != null and lab.site_controller.work_team.is_assigned(identity)
		if not person.owner.combat_can_act(int(person.unit)) or bool(_body_get(person, "attack")) or str(_body_get(person, "pose")) != "idle" \
			or float(_body_get(person, "exchange_stagger")) > 0.0: return {}
	else:
		genuine = person.owner == lab.character and identity == _technology_controlled() and is_same(task, lab.terrain.site.get("manual", {})) \
			or person.owner == lab.npc and is_same(task, lab.terrain.site.get("worker", {}))
		if not person.owner.can_act() or person.owner.action_time > 0.0 or person.owner.guarding or person.owner.guard_transition_left > 0.0 \
			or person.owner.guard_break_left > 0.0 or person.owner._rescue_left > 0.0: return {}
	var job: Dictionary = _jobs.get(_job_key_for(identity), {})
	if str(job.get("kind", "")) in ["technology_feature", "technology_vehicle"] and is_same(job.get("work_task", {}), task):
		genuine = is_same(job.get("technology_executor_body"), person.body) and is_same(job.get("site_state"), lab.terrain.site)
	if not genuine or _threat(person, {}): return {}
	return person

func _technology_controlled() -> int:
	return int(lab.controlled_person_id()) if lab.has_method("controlled_person_id") else int(lab.character.person_id)

func _technology_family() -> Dictionary:
	var family: Variant = lab.terrain.site.get("family", {})
	return family if Family.validate_family(family, _technology_site_id()) and family.has("offices") else {}

func _technology_member(identity: int) -> bool:
	return Family.member_ids(_technology_family(), _technology_site_id()).has(identity)

func _technology_duty(duty: String) -> Dictionary:
	var family := _technology_family()
	if family.is_empty(): return Runtime.fail("UNREGISTERED", "先明確登錄原族人並指定合法家主")
	if family.has("technology") and not Technology.local_holder(family.technology, _technology_site_id()): return Runtime.fail("REMOTE_HOLDER", "原家族科技由另一處 holder 持有；須沿 Region 原引用接續")
	var offices: Dictionary = family.offices.duplicate(true)
	SiteOffices.upgrade(offices)
	SiteOffices.ensure_catalog(offices, "family")
	var eligible := func(identity: int) -> bool:
		var person := _person(identity)
		return Family.member_ids(family, _technology_site_id()).has(identity) and not person.is_empty() and float(person.hp) > 0.0 and float(person.ko) <= 0.0 and not bool(person.captive)
	var head := int(SiteOffices.head_position(offices).get("holder", -1))
	return SiteOffices.resolve(offices, duty, head if eligible.call(head) else -1, eligible)

func _technology_authority(requester_id: int, duty: String) -> Dictionary:
	if requester_id != _technology_controlled(): return Runtime.fail("NO_AUTHORITY", "須由目前受控的原人物明示下令")
	var result := _technology_duty(duty)
	if not bool(result.get("ok", false)): return result
	if int(result.decider) != requester_id: return Runtime.fail("NO_AUTHORITY", "須由本家族當前合法的研習／授徒決策者下令")
	return Runtime.ok()

func _technology_person_context(identity: int, busy_allowed: bool = false) -> Dictionary:
	if not _technology_member(identity): return Runtime.fail("NO_AUTHORITY", "須為這個 Site 明確登錄的原族人")
	var guard := crowd_action_guard([identity])
	if not guard.ok: return guard
	if bool(lab.terrain.site.get("paused", false)) or (not busy_allowed and is_busy(identity)): return Runtime.fail("BUSY", "先完成或取消原人物作業")
	return _ranged_craft_context(_person(identity))

func _technology_team(person: Dictionary) -> Variant:
	if person.get("owner") is TerrainArmy: return person.owner
	var teams: Variant = lab.get("combat_armies")
	if teams is Array:
		for team: Variant in teams:
			if team is TerrainArmy and team.index_for_identity(int(person.person_id)) == TerrainArmy.PLAYER_MEMBER: return team
	return null

func _technology_consent_candidate(identity: int, project_purpose: String) -> Dictionary:
	var check := _technology_person_context(identity)
	if not check.ok: return check
	var native_person := _person(identity)
	if native_person.get("owner") is CrowdOwner: return _technology_scope_consent_candidate(native_person, project_purpose, _technology_controlled())
	var team: Variant = _technology_team(_person(identity))
	if team == null: return Runtime.ok("原人不受隊伍派工管轄", {"consent": {}})
	if not team.has_method("technology_work_consent"): return Runtime.fail("UNSUPPORTED", "原隊具名派工請求入口尚未接線")
	return team.technology_work_consent(identity, project_purpose, _technology_controlled())

func _technology_consent_valid(identity: int, consents: Array, project_purpose: String, bound_token: Dictionary = {}, read_only: bool = false, bound_order: Dictionary = {}) -> bool:
	if not bound_order.is_empty():
		var military_selector := _technology_military_selector_for_order(bound_order)
		if not military_selector.is_empty():
			if int(bound_order.operator_id) != identity or consents.size() != (0 if bound_order.work_consent.is_empty() else 1) \
				or not consents.is_empty() and not is_same(consents[0], bound_order.work_consent): return false
		else:
			if not is_same(consents, bound_order.get("payload", {}).get("consents", [])): return false
	var person := _person(identity)
	if person.is_empty(): return false
	if read_only and person.owner is CrowdOwner: return _technology_native_consent_readonly(person, consents, project_purpose, bound_token, bound_order)
	var team: Variant = _technology_team(person)
	if team == null: return true
	var n08_driver: bool = _nation_n08_driver_context(identity, project_purpose).get("ok", false) == true
	if team.combat_order != TerrainArmy.CombatOrder.HOLD or team.moving_member_count() > 0 or team.get_active_move_plan() != null or team.is_sustain_routed() \
		or float(team.data.site.get("combat_left", 0.0)) > 0.0 or team.has_ship_journey() or team._team_ship_activity(): return false
	var index: int = team.index_for_identity(identity)
	if (index < 0 and index != TerrainArmy.PLAYER_MEMBER) or not team._member_can_serve(index): return false
	var supply: Dictionary = team.data.site.get("team_supply", {}).get(str(team.team_id), {})
	if bool(supply.get("training_order", false)): return false
	if index != TerrainArmy.PLAYER_MEMBER:
		if bool(team.combat_units[index].get("logistics", false)) and not n08_driver or not team.combat_units[index].get("work_task", {}).is_empty() and not _technology_matching_original_task(person, bound_token) and not _technology_matching_public_task(person, bound_order) and not _technology_matching_settlement_task(person, project_purpose) \
			or team.moving_to[index] != TerrainArmy.INVALID_CELL or team._combat_action_blocks_step(index) \
			or team._ship_embarked(index) or team._siege_crew(index) or team._unit_rescues.has(index) or team.patient_has_rescuer(index): return false
	if team.vehicle_transport != null and team.vehicle_transport.is_operator(identity) and not n08_driver: return false
	if (int(team.duty_resolve_readonly("team.work").get("decider", -1)) if read_only else team.duty_decider("team.work")) <= 0: return false
	for consent: Dictionary in consents:
		if int(consent.person_id) == identity and int(consent.team_id) == int(team.team_id) and str(consent.site_id) == _technology_site_id() \
			and str(consent.purpose) == project_purpose and str(consent.status) == "accepted": return true
	return false

# REPLACE _technology_scope_duty

func _technology_candidate() -> Dictionary:
	var result := _technology_family().duplicate(true)
	if result.is_empty() or result.has("technology") and not Technology.local_holder(result.technology, _technology_site_id()): return {}
	SiteOffices.upgrade(result.offices)
	SiteOffices.ensure_catalog(result.offices, "family")
	if not result.has("technology"):
		result.version = 3
		result.family_id = Crypto.new().generate_random_bytes(16).hex_encode()
		result.technology = {"version": 1, "known": [], "holder_site_id": _technology_site_id(), "epoch": 1, "next_project": 1, "active": 0, "projects": []}
	return result

func _technology_source_key(family: Dictionary, project: Dictionary) -> String:
	return str(family.get("family_id", "")) + ":" + str(int(project.id))

func _rebind_technology_sources() -> void:
	# init follows the original candidate admission/bind. Live replacements do
	# not get this rebinding privilege; inventory version changes remain legal.
	var family := _technology_family()
	if not family.has("technology") or not Technology.local_holder(family.technology, _technology_site_id()): return
	for project: Dictionary in family.technology.projects:
		if project.budget.is_empty() or project.budget.status != "granted" or project.budget.source_site_id != _technology_site_id(): continue
		_technology_source_refs[_technology_source_key(family, project)] = {"terrain": lab.terrain, "site": lab.terrain.site,
			"depot": lab.terrain.site.get("depot_items", {}), "stock": lab.terrain.site.get("inventory", {})}

func _technology_source_valid(family: Dictionary, project: Dictionary) -> bool:
	var source: Dictionary = _technology_source_refs.get(_technology_source_key(family, project), {})
	return not source.is_empty() and is_same(source.terrain, lab.terrain) and is_same(source.site, lab.terrain.site) \
		and is_same(source.depot, lab.terrain.site.get("depot_items", {})) and is_same(source.stock, lab.terrain.site.get("inventory", {}))

func prepare_technology(requester_id: int, executor_id: int, mode: String = "first", tech_id: String = "F07", route_id: String = "default") -> Dictionary:
	if tech_id != "F07": return prepare_scope_technology(requester_id, executor_id, tech_id, "", route_id, mode)
	var check := _technology_authority(requester_id, "family.research")
	if not check.ok: return check
	check = _technology_person_context(executor_id)
	if not check.ok: return check
	if mode not in ["first", "relearn"]: return Runtime.fail("INVALID", "請選首次研究或明示重學")
	var executor := _person(executor_id)
	if Technology.learned(_body_get(executor, "technology")): return Runtime.fail("ALREADY_LEARNED", "此人已學會；可沿普通製弓使用原技藝")
	var family := _technology_candidate()
	var tech: Dictionary = family.technology
	if (mode == "first") == tech.known.has("F07"): return Runtime.fail("INVALID_MODE", "家族未知才首次研究；已知時選重學或授課")
	var current := Technology.active_project(tech)
	if not current.is_empty() and not current.executor.is_empty() and is_busy(int(current.executor.person_id)): return Runtime.fail("BUSY", "先取消原在途试作，再選另一名原人")
	var wanted := Technology.purpose("F07", mode, _technology_ref(executor_id))
	var selected := {}
	for project: Dictionary in tech.projects:
		if str(project.purpose) == wanted or mode == "relearn" and project.tech_id == "F07" and Technology.project_purpose_matches(project, _technology_ref(executor_id), tech.get("person_links", [])): selected = project
	if selected.is_empty():
		if int(tech.next_project) >= Technology.MAX_ID: return Runtime.fail("CAPACITY", "原研究項目序號已用盡")
		selected = {"id": int(tech.next_project), "purpose": wanted, "tech_id": "F07", "rules_version": 1, "closed": false,
			"executor": _technology_ref(executor_id), "next_attempt": 1, "receipts": [], "budget": {}, "consents": []}
		tech.projects.append(selected)
		tech.next_project = int(tech.next_project) + 1
	if bool(selected.closed): return Runtime.fail("ALREADY_LEARNED", "此用途已完成，不重開或重發成果")
	selected.executor = _technology_ref(executor_id)
	tech.active = int(selected.id)
	if not Technology.valid_family_tech(tech): return Runtime.fail("INVALID_TECHNOLOGY")
	lab.terrain.site.family = family
	return Runtime.ok("已選原項目與原人；尚未占人、扣料或授予技藝")

func request_technology_consent(requester_id: int, person_id: int) -> Dictionary:
	var check := _technology_authority(requester_id, "family.research")
	if not check.ok: return check
	var family := _technology_family()
	if not family.has("technology"): return Runtime.fail("NO_TARGET", "先選原研究項目")
	var project := Technology.active_project(family.technology)
	if project.is_empty() or int(project.executor.person_id) != person_id: return Runtime.fail("NO_TARGET", "請求須綁本項目所選原人")
	check = _technology_consent_candidate(person_id, str(project.purpose))
	if not check.ok: return check
	var candidate: Dictionary = check.get("consent", {})
	if candidate.is_empty(): return check
	for index: int in project.consents.size():
		if int(project.consents[index].person_id) == person_id and str(project.consents[index].site_id) == _technology_site_id():
			project.consents[index] = candidate
			return Runtime.ok("原隊已同意本次具名研習")
	project.consents.append(candidate)
	return Runtime.ok("原隊已同意本次具名研習")

func revoke_technology_consent(requester_id: int, person_id: int) -> Dictionary:
	var family := _technology_family()
	if not family.has("technology"): return Runtime.fail("NO_TARGET")
	var project := Technology.active_project(family.technology)
	var person := _person(person_id)
	var team: Variant = _technology_team(person) if not person.is_empty() else null
	if requester_id != _technology_controlled() or team == null or team.duty_decider("team.work") != requester_id: return Runtime.fail("NO_AUTHORITY")
	for consent: Dictionary in project.get("consents", []):
		if int(consent.person_id) == person_id and int(consent.team_id) == int(team.team_id) and str(consent.site_id) == _technology_site_id():
			consent.status = "revoked"
			var job := job_for(person_id)
			if job.has("technology_project") and int(job.technology_project) == int(project.id) and job.get("technology_family_id") == family.get("family_id"): cancel(person_id)
			return Runtime.ok("原隊已撤銷未完成研習同意；已付實物與階段保留")
	return Runtime.fail("NO_TARGET")

func grant_technology_budget(requester_id: int, cap: Dictionary, operation: String = "grant") -> Dictionary:
	if requester_id != _technology_controlled(): return Runtime.fail("NO_AUTHORITY", "核額須由目前受控的原人物親自操作")
	var check := crowd_action_guard([requester_id])
	if not check.ok: return check
	if bool(lab.terrain.site.get("paused", false)) or is_busy(requester_id): return Runtime.fail("BUSY")
	check = _ranged_craft_context(_person(requester_id))
	if not check.ok: return check
	var family := _technology_family()
	if not family.has("technology"): return Runtime.fail("NO_TARGET", "先準備本次試作項目")
	var project := Technology.active_project(family.technology)
	if project.is_empty(): return Runtime.fail("NO_TARGET", "先準備本次試作項目")
	if int(project.get("rules_version", 1)) == 2:
		return grant_scope_technology_budget(requester_id, "family", str(family.family_id), cap, operation)
	if operation not in ["grant", "increase", "revoke"]: return Runtime.fail("INVALID")
	if operation == "revoke":
		if project.budget.is_empty(): return Runtime.fail("NO_TARGET", "此項目尚無材料授權")
		project.budget.status = "revoked"
		var identity := int(project.executor.person_id)
		if is_busy(identity) and job_for(identity).has("technology_project"): cancel(identity)
		return Runtime.ok("已撤销後續試作材料核額；已付成品、證據與支出保留")
	if not Technology.keys(cap, ["wood", "fiber"]): return Runtime.fail("INVALID_BUDGET", "須明定木材及纖維的有限總額")
	for resource: String in Technology.TRIAL_COST:
		if not Technology.integer(cap[resource], 0, 1000000): return Runtime.fail("INVALID_BUDGET")
		if not project.budget.is_empty() and int(cap[resource]) < int(project.budget.cap[resource]): return Runtime.fail("INVALID_BUDGET", "加額只能提高原累計上限")
	if operation == "increase" and project.budget.is_empty(): return Runtime.fail("NO_TARGET", "先首次核額")
	var spent: Dictionary = {"wood": 0, "fiber": 0} if project.budget.is_empty() else project.budget.spent.duplicate()
	project.budget = {"authorization_id": int(project.id), "source_site_id": _technology_site_id(), "holder": "depot", "grantor": _technology_ref(requester_id),
		"status": "granted", "cap": {"wood": int(cap.wood), "fiber": int(cap.fiber)}, "spent": spent}
	_technology_source_refs[_technology_source_key(family, project)] = {"terrain": lab.terrain, "site": lab.terrain.site,
		"depot": lab.terrain.site.depot_items, "stock": lab.terrain.site.inventory}
	return Runtime.ok("已核准原營地有限總額；未預扣或保留庫存")

func begin_technology_trial(requester_id: int, executor_id: int = -1) -> Dictionary:
	var check := _technology_authority(requester_id, "family.research")
	if not check.ok: return check
	return _begin_technology_trial(requester_id, executor_id)

func _begin_technology_trial(_requester_id: int, executor_id: int) -> Dictionary:
	var check := Runtime.ok()
	var family := _technology_family()
	if not family.has("technology"): return Runtime.fail("NO_TARGET")
	var project := Technology.active_project(family.technology)
	if project.is_empty(): return Runtime.fail("NO_TARGET", "先選本次項目與原試作者")
	if project.tech_id != "F07" or int(project.rules_version) != 1: return Runtime.fail("NO_TARGET", "此入口只執行原 F07 製弓階段")
	if executor_id < 0: executor_id = int(project.executor.person_id)
	if project.executor != _technology_ref(executor_id): return Runtime.fail("NO_TARGET", "不能代用另一人的階段")
	check = _technology_person_context(executor_id)
	if not check.ok: return check
	if not _technology_consent_valid(executor_id, project.consents, str(project.purpose)): return Runtime.fail("NO_CONSENT", "先請求原隊本次具名派工同意")
	if int(project.next_attempt) >= Technology.MAX_ID: return Runtime.fail("CAPACITY")
	check = begin_ranged_craft(executor_id, "bow")
	if not check.ok: return check
	var job: Dictionary = _jobs[str(executor_id)]
	job.duration = Technology.TRIAL_SECONDS
	job.merge({"technology_project": int(project.id), "technology_purpose": str(project.purpose), "technology_family_id": str(family.family_id),
		"technology_epoch": int(family.technology.epoch), "technology_attempt": int(project.next_attempt),
		"technology_executor_owner": _person(executor_id).owner, "technology_executor_body": _person(executor_id).body})
	var valid := _technology_trial_context(job)
	if not valid.ok:
		_jobs.erase(str(executor_id))
		return valid
	project.next_attempt = int(project.next_attempt) + 1
	return Runtime.ok("開始本人的真試作；完成原交易後才記一階段", {"seconds": job.duration})

func _technology_trial_context(job: Dictionary) -> Dictionary:
	var family := _technology_family()
	if not family.has("technology") or family.get("family_id") != job.technology_family_id or int(family.technology.epoch) != int(job.technology_epoch): return Runtime.fail("STALE_PROJECT")
	var project := Technology.active_project(family.technology)
	if project.is_empty() or project.tech_id != "F07" or int(project.rules_version) != 1 or int(project.id) != int(job.technology_project) or bool(project.closed) or str(project.purpose) != str(job.technology_purpose) \
		or project.executor != _technology_ref(int(job.executor_id)): return Runtime.fail("STALE_PROJECT")
	var executor := _person(int(job.executor_id))
	if executor.is_empty() or not _technology_member(int(job.executor_id)): return Runtime.fail("NO_AUTHORITY")
	if not is_same(executor.owner, job.technology_executor_owner) or not is_same(executor.body, job.technology_executor_body): return Runtime.fail("STALE_SOURCE", "原試作身體來源已被替換")
	if Technology.learned(_body_get(executor, "technology")): return Runtime.fail("ALREADY_LEARNED")
	if not bool(_technology_duty("family.research").get("ok", false)): return Runtime.fail("NO_AUTHORITY", "家族研習職責目前無合法決策者")
	if (Technology.mode(project) == "first") == family.technology.known.has("F07"): return Runtime.fail("INVALID_MODE")
	if Technology.stages(project, _technology_ref(int(job.executor_id)), family.technology.get("person_links", [])) >= 3: return Runtime.fail("ALREADY_LEARNED")
	for receipt: Dictionary in project.receipts:
		if int(receipt.attempt) == int(job.technology_attempt): return Runtime.fail("DUPLICATE", "已提交的真成品不重放")
	if not _technology_consent_valid(int(job.executor_id), project.consents, str(project.purpose)): return Runtime.fail("NO_CONSENT")
	var budget: Dictionary = project.budget
	if budget.is_empty() or str(budget.status) != "granted" or str(budget.source_site_id) != _technology_site_id(): return Runtime.fail("NO_BUDGET", "本次試作尚無有效材料核額")
	if not _technology_source_valid(family, project): return Runtime.fail("STALE_SOURCE", "原核額來源已被替換；須重新核准同項目且保留累計支出")
	for resource: String in Technology.TRIAL_COST:
		if int(budget.spent[resource]) + int(Technology.TRIAL_COST[resource]) > int(budget.cap[resource]): return Runtime.fail("BUDGET_EXCEEDED", "原累計材料核額不足；須由合法來源人明示加額")
	return Runtime.ok("", {"project": project})

func _commit_technology_trial(job: Dictionary) -> Dictionary:
	var check := _technology_trial_context(job)
	if not check.ok: return check
	var family := _technology_family()
	var candidate: Dictionary = family.technology.duplicate(true)
	var project := Technology.active_project(candidate)
	project.receipts.append({"site_id": _technology_site_id(), "person_id": int(job.executor_id), "attempt": int(job.technology_attempt)})
	for resource: String in Technology.TRIAL_COST: project.budget.spent[resource] = int(project.budget.spent[resource]) + int(Technology.TRIAL_COST[resource])
	var complete := Technology.stages(project, _technology_ref(int(job.executor_id)), family.technology.get("person_links", [])) == 3
	var executor := _person(int(job.executor_id))
	var person_candidate := Technology.learned_candidate(_body_get(executor, "technology")) if complete else {}
	if complete:
		if person_candidate.is_empty(): return Runtime.fail("INVALID_TECHNOLOGY")
		if not candidate.known.has("F07"): candidate.known.append("F07")
		project.closed = true
		candidate.active = 0
	if not Technology.valid_family_tech(candidate): return Runtime.fail("INVALID_TECHNOLOGY")
	# Every technology failure is above the original synchronous real-item commit.
	var result := Runtime.ranged_craft(lab.terrain, "bow", int(job.executor_id))
	if not result.ok: return result
	family.technology = candidate
	if complete: _body_set(executor, "technology", person_candidate)
	result.message = "真弓已入原庫；本人試作 %d/3%s" % [Technology.stages(project, _technology_ref(int(job.executor_id)), family.technology.get("person_links", [])), "，已學會 F07" if complete else ""]
	return result

func begin_technology_lesson(requester_id: int, teacher_id: int, student_id: int, tech_id: String = "F07") -> Dictionary:
	if tech_id != "F07" and TechnologyCatalog.get_node(tech_id).get("enabled") != true: return Runtime.fail("UNIMPLEMENTED")
	var check := _technology_authority(requester_id, "family.teach")
	if not check.ok: return check
	if not Technology.FAMILY_IDS.has(tech_id): return Runtime.fail("INVALID_TECHNOLOGY")
	if teacher_id == student_id: return Runtime.fail("INVALID", "老師學生須為不同原人物")
	var family := _technology_family()
	if not family.get("technology", {}).get("known", []).has(tech_id): return Runtime.fail("UNKNOWN_TECHNOLOGY", "本家族尚未知 " + tech_id)
	for identity: int in [teacher_id, student_id]:
		check = _technology_person_context(identity)
		if not check.ok: return check
	var teacher := _person(teacher_id)
	var student := _person(student_id)
	if not Technology.learned(_body_get(teacher, "technology"), tech_id): return Runtime.fail("NO_TEACHER", "老師本人須已學會 " + tech_id)
	if Technology.learned(_body_get(student, "technology"), tech_id): return Runtime.fail("ALREADY_LEARNED")
	var course_purpose := tech_id + ":lesson:" + JSON.stringify([_technology_site_id(), str(family.family_id), teacher_id, student_id])
	var consents: Array = []
	for identity: int in [teacher_id, student_id]:
		check = _technology_consent_candidate(identity, course_purpose)
		if not check.ok: return check
		if not check.consent.is_empty(): consents.append(check.consent)
	var job := _new_job(teacher, "technology_lesson", student_id)
	job.merge({"duration": Technology.LESSON_SECONDS, "terrain": lab.terrain, "site_state": lab.terrain.site, "technology_family_id": str(family.family_id),
		"technology_epoch": int(family.technology.epoch), "technology_purpose": course_purpose, "consents": consents,
		"technology_id": tech_id,
		"student_cell": lab.terrain.index(student.cell), "student_hit": int(student.hit), "teacher_body": teacher.body, "student_body": student.body})
	_jobs[str(teacher_id)] = job
	return Runtime.ok("原師徒開始一課；無材料費、無弓獎品", {"seconds": Technology.LESSON_SECONDS})

func _technology_lesson_context(job: Dictionary) -> Dictionary:
	if not is_same(lab.terrain, job.terrain) or not is_same(lab.terrain.site, job.site_state): return Runtime.fail("STALE_SOURCE")
	var family := _technology_family()
	var tech_id := str(job.get("technology_id", "F07"))
	if not Technology.FAMILY_IDS.has(tech_id): return Runtime.fail("INVALID_TECHNOLOGY")
	if family.get("family_id") != job.technology_family_id or not family.has("technology") or int(family.technology.epoch) != int(job.technology_epoch) \
		or not family.technology.known.has(tech_id): return Runtime.fail("STALE_PROJECT")
	if not bool(_technology_duty("family.teach").get("ok", false)): return Runtime.fail("NO_AUTHORITY")
	for identity: int in [int(job.executor_id), int(job.target_id)]:
		var check := _technology_person_context(identity, true)
		if not check.ok: return check
		var person := _person(identity)
		var teacher: bool = identity == int(job.executor_id)
		if int(person.hit) != int(job.executor_hit if teacher else job.student_hit) or lab.terrain.index(person.cell) != int(job.executor_cell if teacher else job.student_cell) \
			or not is_same(person.body, job.teacher_body if teacher else job.student_body): return Runtime.fail("INTERRUPTED", "原師徒移動、受擊或身分來源已變")
		if not _technology_consent_valid(identity, job.consents, str(job.technology_purpose)): return Runtime.fail("NO_CONSENT")
		if Technology.learned(_body_get(person, "technology"), tech_id) != teacher: return Runtime.fail("ALREADY_LEARNED" if not teacher else "NO_TEACHER")
	return Runtime.ok()

func _commit_technology_lesson(job: Dictionary) -> Dictionary:
	var prepared: Dictionary = _prepare_technology_lesson_completion(job)
	if not prepared.ok: return prepared
	var checked: Dictionary = _validate_technology_lesson_completion(prepared)
	if not checked.ok: return checked
	_publish_technology_lesson_completion(prepared)
	return Runtime.ok("原學生已學會 " + str(job.get("technology_id", "F07")) + "；已付重學歷史保留，不追加成品")

func stop_technology(requester_id: int, participant_id: int = 0) -> Dictionary:
	var participant_job := job_for(participant_id) if participant_id > 0 else {}
	var family := _technology_family()
	if participant_id > 0:
		if participant_job.is_empty() or not family.has("technology") or participant_job.get("technology_family_id") != family.get("family_id") \
			or int(participant_job.get("technology_epoch", -1)) != int(family.technology.epoch): return Runtime.fail("NO_TARGET", "此人沒有本家族的未完科技作業")
		if str(participant_job.kind) != "technology_lesson":
			var selected := Technology.active_project(family.technology)
			if not participant_job.has("technology_project") or selected.is_empty() or int(participant_job.technology_project) != int(selected.id) \
				or selected.executor != _technology_ref(participant_id) or str(participant_job.technology_purpose) != str(selected.purpose): return Runtime.fail("NO_TARGET", "不取消無關的原作業")
	var check := _technology_authority(requester_id, "family.teach" if participant_id > 0 and str(job_for(participant_id).get("kind", "")) == "technology_lesson" else "family.research")
	if not check.ok: return check
	if participant_id > 0: return cancel(participant_id)
	if not family.has("technology"): return Runtime.fail("NO_TARGET")
	var project := Technology.active_project(family.technology)
	if project.is_empty(): return Runtime.fail("NO_TARGET")
	var identity := int(project.executor.person_id)
	if is_busy(identity) and job_for(identity).has("technology_project"): cancel(identity)
	family.technology.active = 0
	return Runtime.ok("已停本次研習；原成功階段、成品與累計支出保留")

func technology_query() -> Dictionary:
	var family := _technology_family()
	if family.is_empty(): return Runtime.fail("UNREGISTERED", "先於原家族入口登錄原族人並指定家主")
	if family.has("technology") and not Technology.local_holder(family.technology, _technology_site_id()): return Runtime.fail("REMOTE_HOLDER", "原家族科技目前由另一處 holder 持有；此處引用不代表未知或可重開研究")
	var tech: Dictionary = family.get("technology", {})
	var project := Technology.active_project(tech)
	if not project.is_empty() and (project.tech_id != "F07" or int(project.rules_version) != 1): project = {}
	var people: Array = []
	for member: Dictionary in family.members:
		if str(member.site_id) != _technology_site_id(): continue
		var person := _person(int(member.person_id))
		if person.is_empty(): continue
		people.append({"site_id": _technology_site_id(), "person_id": int(member.person_id), "label": str(member.label),
			"team_id": int(_technology_team(person).team_id) if _technology_team(person) != null else -1, "learned": Technology.learned(_body_get(person, "technology")),
			"stages": Technology.stages(project, _technology_ref(int(member.person_id)), tech.get("person_links", [])), "busy": is_busy(int(member.person_id)), "job": job_for(int(member.person_id))})
	var projection := {}
	if not project.is_empty():
		projection = {"id": int(project.id), "purpose": str(project.purpose), "mode": Technology.mode(project), "tech_id": "F07", "executor_id": int(project.executor.get("person_id", -1)),
			"stages": Technology.stages(project, project.executor, tech.get("person_links", [])), "consents": [], "status_text": "已選項目，等待合法試作", "block_reasons": []}
		var budget: Dictionary = project.budget
		projection.budget = {"cap": budget.get("cap", {"wood": 0, "fiber": 0}).duplicate(), "spent": budget.get("spent", {"wood": 0, "fiber": 0}).duplicate(),
			"status": str(budget.get("status", "pending")), "source_site_id": str(budget.get("source_site_id", _technology_site_id())), "holder": "depot",
			"grantor_id": int(budget.get("grantor", {}).get("person_id", -1)), "active": str(budget.get("status", "")) == "granted"}
		for consent: Dictionary in project.consents:
			projection.consents.append({"person_id": int(consent.person_id), "team_id": int(consent.team_id), "decider_id": int(consent.decider_id), "status": str(consent.status)})
		if budget.is_empty() or budget.status != "granted": projection.block_reasons.append("尚無本次有效材料核額")
		if not _technology_consent_valid(int(project.executor.person_id), project.consents, str(project.purpose), {}, true): projection.block_reasons.append("尚無原隊本次具名同意")
	return Runtime.ok("", {"registered": true, "family_id": str(family.get("family_id", "")), "known": tech.get("known", []).has("F07"),
		"research_decider": int(_technology_duty("family.research").get("decider", -1)), "teaching_decider": int(_technology_duty("family.teach").get("decider", -1)),
		"current_person_id": _technology_controlled(), "people": people, "project": projection})

# This read-only demand joins the Lab's original complete-pool collector.
func work_requests(seconds: float) -> Array[Dictionary]:
	var requests: Array[Dictionary] = []
	_prepared_controlled_features.clear()
	_controlled_feature_consumed.clear()
	_controlled_feature_allocation = {}
	_controlled_feature_seconds = seconds
	if not is_finite(seconds) or seconds <= 0.0 or bool(lab.terrain.site.get("paused", false)): return requests
	var keys: Array = _jobs.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return int(a) < int(b))
	for key: String in keys:
		var job: Dictionary = _jobs[key]
		if bool(job.get("preparing", false)): continue
		if str(job.kind) in ["technology_feature", "technology_vehicle"]:
			var request := _controlled_feature_work_request(key, job, seconds)
			if not request.is_empty(): requests.append(request)
			continue
		if str(job.kind) == "captive_craft":
			var captive_request := _captive_craft_request(job, seconds)
			if not captive_request.is_empty(): requests.append(captive_request)
			continue
		if str(job.kind) not in ["loot", "ranged_craft", "tent_deploy", "tent_pack", "technology_lesson", "technology_analysis", "nation_administration", "water_schedule", "food_order", "capture", "unbind", "ransom", "equipment", "prison_release"]: continue
		if not _job_context(job).ok: continue
		var ids := [int(job.executor_id)]
		if str(job.kind) == "technology_lesson": ids.append(int(job.target_id))
		if str(job.kind) == "equipment" and str(job.order.mode) == "team_issue":
			for identity: int in job.order.target_ids:
				if not ids.has(identity): ids.append(identity)
		var participants: Array = []
		var paused := ""
		for identity: int in ids:
			var person := _person(identity)
			var participant := _shared_work_participant(person)
			if participant.is_empty():
				participants.clear()
				break # An unprepared native pool cannot fall back to cold GD state.
			participants.append(participant)
			if not bool(person.player):
				if _threat(person, {}): paused = "THREAT"
				elif paused.is_empty() and Fatigue.needs_work_rest(float(_body_get(person, "fatigue")), bool(_body_get(person, "work_resting"))): paused = "REST"
		if participants.is_empty(): continue
		var kind := "joint" if str(job.kind) == "technology_lesson" else ("single" if str(job.kind) in ["loot", "ranged_craft", "tent_deploy", "tent_pack", "technology_analysis", "nation_administration", "water_schedule", "food_order"] else "raw")
		var request: Dictionary = {"provider": "person_actions", "key": key, "participants": participants, "remaining": maxf(0.0, float(job.duration) - float(job.elapsed)),
			"productive_kind": kind, "progress_multiplier": _technology_work_multiplier(job), "max_game_seconds": seconds, "paused": paused}
		if str(job.kind) == "ranged_craft" and paused.is_empty() and float(request.remaining) <= seconds * float(request.progress_multiplier) + Fatigue.WORK_PLAN_EPS:
			request.payment_source = lab.terrain.site.inventory
			request.payment = Runtime.RANGED_RECIPES[str(job.recipe)].cost.duplicate(true)
			request.payment_key = "person_actions:" + key
		if str(job.kind) == "technology_lesson" and job.has("nation_course_id") and paused.is_empty() \
			and float(request.remaining) <= seconds * float(request.progress_multiplier) + Fatigue.WORK_PLAN_EPS:
			var source: Dictionary = equipment_orders.prepare_funded_course_source(str(job.nation_course_nation), str(job.nation_course_id), job)
			if source.ok:
				request.payment_source = source.source_cargo
				request.payment = {"grain": 2}
				request.payment_key = "person_actions:" + key
			else: request.paused = str(source.get("code", "MATERIALS"))
		requests.append(request)
	return requests

func _shared_work_participant(person: Dictionary) -> Dictionary:
	if person.is_empty(): return {}
	if person.owner is CrowdOwner:
		var crowd: Variant = lab.get("crowd_site")
		if crowd == null or not crowd.has_method("work_fatigue_participant"): return {}
		return crowd.work_fatigue_participant(int(person.person_id), not bool(person.player), Fatigue.WORK_RATE)
	return {"person_id": int(person.person_id), "body": person.body, "effort_rate": Fatigue.effort_rate(person.body), "rest_limited": not bool(person.player)}

func effort_requests(seconds: float) -> Array[Dictionary]:
	return work_requests(seconds)

func ranged_craft_seconds(identity: int, recipe: String) -> float:
	if not Runtime.RANGED_RECIPES.has(recipe): return NAN
	var duration := float(Runtime.RANGED_RECIPES[recipe].duration)
	var person := _person(identity)
	var skill := "F07" if recipe == "bow" else "F08" if recipe == "crossbow" else ""
	return duration * 0.9 if not skill.is_empty() and not person.is_empty() and Technology.learned(_body_get(person, "technology"), skill) else duration

# This later entry does not grant sources or personnel consent. The original
# SiteDutyAI owns selection/cadence and resolves its real NPC before calling.
func _technology_npc_authority(requester_id: int) -> Dictionary:
	var family := _technology_family()
	if requester_id == _technology_controlled() or family.is_empty() or not bool(family.offices.get("duty_ai", false)): return Runtime.fail("DUTY_AI_OFF")
	var resolved := _technology_duty("family.research")
	if not bool(resolved.get("ok", false)) or int(resolved.decider) != requester_id: return Runtime.fail("NO_AUTHORITY")
	return Runtime.ok()

func technology_ai_query(requester_id: int) -> Dictionary:
	var check := _technology_npc_authority(requester_id)
	if not check.ok: return check
	var family := _technology_family()
	var tech: Dictionary = family.get("technology", {})
	var project := Technology.active_project(tech)
	if project.is_empty() or Technology.mode(project) != "first" or tech.get("known", []).has("F07"): return Runtime.fail("NO_CANDIDATE", "沒有尚未知且已合法準備的 F07 項目")
	var identity := int(project.executor.person_id)
	var person := _person(identity)
	if person.is_empty() or bool(person.player): return Runtime.fail("NO_CANDIDATE", "此項只自動安排原 NPC 試作者")
	if Technology.learned(_body_get(person, "technology")): return Runtime.fail("NO_CANDIDATE", "已會者不重做首次研究")
	check = _technology_person_context(identity)
	if not check.ok: return check
	if not _technology_consent_valid(identity, project.consents, str(project.purpose)): return Runtime.fail("NO_CONSENT")
	if project.budget.is_empty() or str(project.budget.status) != "granted" or not _technology_source_valid(family, project): return Runtime.fail("NO_BUDGET")
	if Fatigue.needs_work_rest(float(_body_get(person, "fatigue")), bool(_body_get(person, "work_resting"))): return Runtime.fail("REST")
	if _threat(person, {}): return Runtime.fail("THREAT")
	for resource: String in Technology.TRIAL_COST:
		if int(project.budget.spent[resource]) + int(Technology.TRIAL_COST[resource]) > int(project.budget.cap[resource]): return Runtime.fail("BUDGET_EXCEEDED")
	check = Runtime.ranged_craft(lab.terrain, "bow", identity, true)
	if not check.ok: return check
	return Runtime.ok("", {"candidates": [{"tech_id": "F07", "person_id": identity, "project_id": int(project.id), "stages": Technology.stages(project, _technology_ref(identity), family.technology.get("person_links", [])),
		"seconds": Technology.TRIAL_SECONDS, "cost": Technology.TRIAL_COST.duplicate(), "purpose": str(project.purpose)}]})

func begin_npc_technology_trial(requester_id: int, executor_id: int = -1) -> Dictionary:
	var check := technology_ai_query(requester_id)
	if not check.ok: return check
	var selected := int(check.candidates[0].person_id)
	if executor_id >= 0 and executor_id != selected: return Runtime.fail("NO_CANDIDATE")
	return _begin_technology_trial(requester_id, selected)

func _technology_work_multiplier(job: Dictionary) -> float:
	if job.get("kind") == "food_order" and not job.get("nation_token", {}).is_empty() and lab.get("restore_only") == true and not bool(_person(int(job.executor_id)).get("player", true)): return 0.5
	return 0.5 if (job.has("technology_project") or job.has("technology_scope_token")) and lab.get("restore_only") == true and not bool(_person(int(job.executor_id)).get("player", true)) else 1.0

# T2: only admitted original NPC trial jobs may checkpoint mid-work in cold
# replay. Ordinary/manual saves still use save_guard() and remain BUSY.
func export_cold_technology_jobs() -> Dictionary:
	if lab.get("restore_only") != true: return Runtime.fail("BUSY", "人工在途科研仍須完成或取消後保存")
	var rows: Array = []
	for job: Dictionary in _jobs.values():
		if str(job.kind) != "ranged_craft" or not (job.has("technology_project") or job.has("technology_scope_token")) or bool(_person(int(job.executor_id)).get("player", true)):
			return Runtime.fail("BUSY", "冷科研終點只允合法原 NPC 研究；其他作業沿原守衛")
		var check := _job_context(job)
		if not check.ok: return check
		if float(job.elapsed) >= float(job.duration) - 0.00000001: return Runtime.fail("BUSY", "先沿原接觸後提交已完成試作")
		var row := {}
		for field: String in Technology.cold_job_fields(job): row[field] = job[field]
		rows.append(row)
	var expanded: bool = rows.any(func(row: Dictionary) -> bool: return row.has("technology_scope_token"))
	var state := {"version": 2 if expanded else 1, "config_version": Technology.F15_COLD_CONFIG if expanded else Technology.COLD_CONFIG, "site_id": _technology_site_id(), "jobs": rows}
	return Runtime.ok("", {"state": state})

func cold_technology_jobs_save_guard() -> Dictionary:
	var captured := export_cold_technology_jobs()
	return Runtime.ok() if captured.ok else captured

func prepare_restore_cold_technology_jobs(raw: Variant) -> Dictionary:
	if not _jobs.is_empty(): return Runtime.fail("BUSY")
	var people := {}
	if raw is Dictionary and raw.get("jobs") is Array:
		for row: Variant in raw.jobs:
			if not row is Dictionary or not Technology.integer(row.get("executor_id"), 1, 2147483647): return Runtime.fail("INVALID_TECHNOLOGY_JOB")
			var person := _person(int(row.executor_id))
			if person.is_empty(): return Runtime.fail("NO_TARGET")
			var saved := {"item_state": person.holder, "technology": _body_get(person, "technology"), "hp": float(person.hp), "ko": float(person.ko), "captive": bool(person.captive)}
			people[int(row.executor_id)] = saved
	var checked := Technology.cold_jobs_candidate(raw, lab.terrain.site, people)
	if not checked.ok: return checked
	var jobs := {}
	var expected := {}
	for row: Dictionary in checked.state.jobs:
		var person := _person(int(row.executor_id))
		if bool(person.player) or lab.terrain.index(person.cell) != int(row.executor_cell) or int(person.hit) != int(row.executor_hit): return Runtime.fail("STALE_TECHNOLOGY_PERSON")
		var job := _new_job(person, "ranged_craft", int(row.executor_id))
		for field: String in Technology.cold_job_fields(row): job[field] = row[field]
		job.merge({"terrain": lab.terrain, "site_state": lab.terrain.site, "executor_holder": person.holder, "executor_cargo": person.cargo,
			"depot_holder": lab.terrain.site.depot_items, "depot_stock": lab.terrain.site.inventory, "technology_executor_owner": person.owner, "technology_executor_body": person.body})
		var check := _job_context(job)
		if not check.ok: return check
		jobs[str(int(row.executor_id))] = job
		expected[int(row.executor_id)] = {"owner": person.owner, "body": person.body, "holder": person.holder, "cargo": person.cargo,
			"version": int(person.holder.version), "hit": int(person.hit), "cell": person.cell}
	return Runtime.ok("", {"jobs": jobs, "people": expected, "jobs_owner": _jobs, "terrain": lab.terrain, "site_state": lab.terrain.site, "cold_state": checked.state.duplicate(true)})

func can_publish_restore_cold_technology_jobs(prepared: Dictionary) -> bool:
	if not bool(prepared.get("ok", false)) or not is_same(prepared.get("jobs_owner"), _jobs) or not _jobs.is_empty() \
		or not is_same(prepared.get("terrain"), lab.terrain) or not is_same(prepared.get("site_state"), lab.terrain.site): return false
	if not prepared.get("jobs") is Dictionary or not prepared.get("people") is Dictionary or not prepared.get("cold_state") is Dictionary or prepared.jobs.size() != prepared.people.size(): return false
	var raw := {"version": int(prepared.cold_state.version), "config_version": str(prepared.cold_state.config_version), "site_id": _technology_site_id(), "jobs": []}
	var people := {}
	for identity: int in prepared.people:
		var person := _person(identity)
		var expected: Dictionary = prepared.people[identity]
		if person.is_empty() or not is_same(person.owner, expected.owner) or not is_same(person.body, expected.body) or not is_same(person.holder, expected.holder) \
			or not is_same(person.cargo, expected.cargo) or int(person.holder.version) != int(expected.version) or int(person.hit) != int(expected.hit) or person.cell != expected.cell: return false
		if not prepared.jobs.has(str(identity)) or not prepared.jobs[str(identity)] is Dictionary or not _job_context(prepared.jobs[str(identity)]).ok: return false
		var row := {}
		for field: String in Technology.cold_job_fields(prepared.jobs[str(identity)]):
			if not prepared.jobs[str(identity)].has(field): return false
			row[field] = prepared.jobs[str(identity)][field]
		raw.jobs.append(row)
		people[identity] = {"item_state": person.holder, "technology": _body_get(person, "technology"), "hp": float(person.hp), "ko": float(person.ko), "captive": bool(person.captive)}
	var admitted := Technology.cold_jobs_candidate(raw, lab.terrain.site, people)
	if not admitted.ok or admitted.state != prepared.cold_state: return false
	return true

func publish_restore_cold_technology_jobs(prepared: Dictionary) -> Dictionary:
	if not can_publish_restore_cold_technology_jobs(prepared): return Runtime.fail("STALE_TECHNOLOGY_JOBS")
	_jobs = prepared.jobs
	return Runtime.ok("原 NPC 未完試作已恢復；未推進時間、發產品或重扣材料")

func begin_captive_craft(requester_id: int, captive_id: int, supervisor_id: int = -1, recipe: String = "bow") -> Dictionary:
	if requester_id != _technology_controlled(): return Runtime.fail("NO_AUTHORITY", "須由目前受控的原監管決策者明示下令")
	var relation: Dictionary = lab.terrain.site.get("captivity", {}).get(str(captive_id), {})
	if supervisor_id < 0: supervisor_id = int(relation.get("guard_id", -1))
	if is_busy(captive_id) or is_busy(supervisor_id): return Runtime.fail("BUSY")
	var checked := _captive_craft_context(requester_id, captive_id, supervisor_id, recipe)
	if not checked.ok: return checked
	var captive: Dictionary = checked.person
	var supervisor: Dictionary = checked.supervisor
	var job := _new_job(captive, "captive_craft", supervisor_id)
	job.merge({"requester_id": requester_id, "guard_id": supervisor_id, "recipe": recipe,
		"duration": ranged_craft_seconds(captive_id, recipe), "terrain": lab.terrain, "site_state": lab.terrain.site,
		"captivity": checked.relation.duplicate(true), "executor_owner": captive.owner, "executor_body": captive.body,
		"executor_holder": captive.holder, "executor_cargo": captive.cargo, "executor_version": int(captive.holder.version),
		"guard_owner": supervisor.owner, "guard_body": supervisor.body, "guard_holder": supervisor.holder, "guard_cargo": supervisor.cargo,
		"guard_version": int(supervisor.holder.version), "guard_cell": lab.terrain.index(supervisor.cell), "guard_hit": int(supervisor.hit),
		"depot_holder": lab.terrain.site.depot_items, "depot_stock": lab.terrain.site.inventory, "depot_cell": int(lab.terrain.site.depot_cell)})
	_jobs[str(captive_id)] = job
	return Runtime.ok("開始原俘虜受監管製作；仍被俘，完成原交易才入庫", {"seconds": job.duration})

func _captive_craft_body_ready(person: Dictionary) -> bool:
	# Deliberately does NOT call/relax can_act: that denies every captive.
	if person.is_empty() or float(person.hp) <= 0.0 or float(person.ko) > 0.0 or not bool(person.captive) \
		or bool(person.surrender_pending) or not _prison_stopped(person) or float(_body_get(person, "exchange_stagger")) > 0.0: return false
	if person.body is Dictionary:
		if bool(person.body.get("departed", false)) or bool(person.body.get("site_exited", false)) or bool(person.body.get("attack", false)) \
			or str(person.body.get("pose", "")) != "idle" or not person.body.get("work_task", {}).is_empty(): return false
		if not str(person.body.get("embarked_vehicle_id", "")).is_empty(): return false
		if person.owner is TerrainArmy and (person.owner._unit_rescues.has(int(person.unit)) or person.owner.patient_has_rescuer(int(person.unit))): return false
	else:
		var actor: TerrainTestCharacter = person.owner
		if actor.site_exited or actor._getting_up or actor.action_time > 0.0 or actor.guarding or actor.guard_transition_left > 0.0 \
			or actor.guard_break_left > 0.0 or actor._rescue_left > 0.0: return false
		if actor is TerrainTestNPC and (actor.command != TerrainTestNPC.Command.STOP or not actor._path.is_empty()): return false
		var activity: Dictionary = lab.terrain.site.manual if actor == lab.character else lab.terrain.site.worker
		if not str(activity.get("target", "")).is_empty(): return false
	var vehicles: Variant = lab.site_controller.vehicles
	return not vehicles.is_siege_crew(int(person.person_id)) and not vehicles.is_operator(int(person.person_id))

func _captive_craft_authority(requester_id: int, supervisor: Dictionary, prison_id: String, accepted: bool) -> Dictionary:
	if not prison_id.is_empty() and Settlement.prison_governed(lab, prison_id):
		# Accepted scope survives a lawful warden duty handover; issuing/stopping
		# new work still belongs to the CURRENT original settlement decider.
		if accepted:
			return Runtime.ok() if bool(Settlement.duty_resolve(lab, "settlement.prison").get("ok", false)) else Runtime.fail("NO_AUTHORITY")
		var refusal := Settlement.prison_authority(lab, prison_id, requester_id)
		return Runtime.ok() if refusal.is_empty() else refusal
	if accepted: return Runtime.ok() # Physical original guard relation is independently rechecked below.
	var escort: Variant = lab.site_controller.captive_escort
	if escort == null or not escort._authority(requester_id, supervisor): return Runtime.fail("NO_AUTHORITY", "只有原看守本人或其當前合法指揮者可派受監管工作")
	return Runtime.ok()

func _captive_craft_context(requester_id: int, captive_id: int, supervisor_id: int, recipe: String, job: Dictionary = {}) -> Dictionary:
	if not is_instance_valid(lab) or lab.site_controller == null: return Runtime.fail("STALE_SOURCE")
	var guarded := crowd_action_guard([captive_id, supervisor_id])
	if not guarded.ok: return guarded
	if bool(lab.terrain.site.get("paused", false)) or float(lab.terrain.site.get("combat_left", 0.0)) > 0.0 \
		or lab.site_controller.region_operation_pending(): return Runtime.fail("BUSY")
	if lab is Node and lab.is_inside_tree() and lab.get_tree().paused: return Runtime.fail("BUSY")
	if recipe != "bow": return Runtime.fail("UNSUPPORTED", "本包只接已有真技藝與生產端的 F07 製弓")
	var person := _person(captive_id)
	var supervisor := _person(supervisor_id)
	var relation: Dictionary = lab.terrain.site.get("captivity", {}).get(str(captive_id), {})
	if relation.is_empty() or captive_id == supervisor_id or int(relation.get("guard_id", -1)) != supervisor_id: return Runtime.fail("NO_AUTHORITY", "必須引用此原俘虜當下的真監管關係")
	if not _captive_craft_body_ready(person) or not _ready(supervisor, true) or not _prison_stopped(supervisor): return Runtime.fail("BUSY")
	if int(supervisor.faction) != int(relation.get("captor_faction", -1)): return Runtime.fail("NO_AUTHORITY")
	if supervisor.owner is TerrainArmy:
		var row: Dictionary = supervisor.body
		var supply: Dictionary = lab.terrain.site.get("team_supply", {}).get(str(supervisor.owner.team_id), {})
		if bool(supply.get("training_order", false)) or bool(row.get("logistics", false)) or not row.get("work_task", {}).is_empty(): return Runtime.fail("BUSY")
	if not lab.terrain.site.get("escort_orders", {}).get(str(supervisor_id), {}).is_empty(): return Runtime.fail("BUSY", "原押送未完成")
	if not job.is_empty() and (is_busy(captive_id) and _job_key_for(captive_id) != str(job.executor_id) \
		or is_busy(supervisor_id) and _job_key_for(supervisor_id) != str(job.executor_id)): return Runtime.fail("BUSY")
	if not Technology.learned(_body_get(person, "technology"), "F07"): return Runtime.fail("NO_SKILL", "只能運用此原俘虜已掌握的技藝")
	var depot := _source("depot", "depot")
	if depot.is_empty() or not _adjacent(person.cell, depot.cell): return Runtime.fail("UNREACHABLE", "原製作者須在原營地合法相鄰工作格")
	var prison_id := str(relation.get("prison_id", ""))
	if prison_id.is_empty():
		if not has_effective_guard(captive_id): return Runtime.fail("GUARD", "原看守失效，受監管生產停止")
	else:
		var slot := prison_slot(captive_id)
		if not slot.ok: return slot
		if supervisor.cell != slot.slot.contact_cell or not _adjacent(supervisor.cell, person.cell): return Runtime.fail("GUARD")
		var owner_faction := int(lab.terrain.site.features[prison_id].get("owner_faction", -1))
		if owner_faction >= 0 and owner_faction != int(supervisor.faction): return Runtime.fail("NO_AUTHORITY")
	var authority := _captive_craft_authority(requester_id, supervisor, prison_id, not job.is_empty())
	if not authority.ok: return authority
	# Original escort checks threat from the actual guard's side. An authorized
	# guard is not treated as an enemy merely because the captive retains faction.
	if _captive_craft_threat(person, supervisor): return Runtime.fail("THREAT", "原監管作業格有敵情或危險")
	if not job.is_empty():
		if not is_same(lab.terrain, job.terrain) or not is_same(lab.terrain.site, job.site_state) or relation != job.captivity \
			or not is_same(person.owner, job.executor_owner) or not is_same(person.body, job.executor_body) \
			or not is_same(person.holder, job.executor_holder) or not is_same(person.cargo, job.executor_cargo) \
			or int(person.holder.version) != int(job.executor_version) or int(person.hit) != int(job.executor_hit) \
			or lab.terrain.index(person.cell) != int(job.executor_cell) \
			or not is_same(supervisor.owner, job.guard_owner) or not is_same(supervisor.body, job.guard_body) \
			or not is_same(supervisor.holder, job.guard_holder) or not is_same(supervisor.cargo, job.guard_cargo) \
			or int(supervisor.holder.version) != int(job.guard_version) or int(supervisor.hit) != int(job.guard_hit) \
			or lab.terrain.index(supervisor.cell) != int(job.guard_cell) \
			or not is_same(lab.terrain.site.depot_items, job.depot_holder) or not is_same(lab.terrain.site.inventory, job.depot_stock) \
			or int(lab.terrain.site.depot_cell) != int(job.depot_cell): return Runtime.fail("STALE_SOURCE", "原監管／原人／本次來源已改變")
	var preview := Runtime.ranged_craft(lab.terrain, recipe, captive_id, true)
	if not preview.ok: return preview
	return Runtime.ok("", {"person": person, "supervisor": supervisor, "relation": relation})

func _captive_craft_job_context(job: Dictionary) -> Dictionary:
	return _captive_craft_context(int(job.requester_id), int(job.executor_id), int(job.guard_id), str(job.recipe), job)

func _commit_captive_craft(job: Dictionary) -> Dictionary:
	if not is_same(_jobs.get(str(int(job.get("executor_id", -1))), {}), job) or not str(job.get("paused", "")).is_empty() \
		or not Technology.finite_number(job.get("elapsed")) or float(job.elapsed) + Fatigue.WORK_PLAN_EPS < float(job.duration): return Runtime.fail("STALE_SOURCE")
	var check: Dictionary = _captive_craft_job_context(job)
	if not check.ok: return check
	var prepared: Dictionary = Runtime.prepare_ranged_craft(lab.terrain, str(job.recipe), int(job.executor_id))
	if not prepared.ok: return prepared
	# The original equipment allocation callback may change a real endpoint;
	# recheck BOTH same original people/guard relation and the actual source.
	check = _captive_craft_job_context(job)
	if not check.ok: return check
	if not is_same(_jobs.get(str(int(job.executor_id)), {}), job) or not str(job.paused).is_empty() \
		or not Runtime.validate_prepared_ranged_craft(prepared): return Runtime.fail("STALE_SOURCE")
	# Original atomic item tail only: no research purpose/receipt/skill write.
	return Runtime.publish_prepared_ranged_craft(prepared)

func stop_captive_craft(requester_id: int, participant_id: int) -> Dictionary:
	if requester_id != _technology_controlled(): return Runtime.fail("NO_AUTHORITY")
	var job := job_for(participant_id)
	if str(job.get("kind", "")) != "captive_craft" or not is_same(lab.terrain, job.terrain) \
		or not is_same(lab.terrain.site, job.site_state): return Runtime.fail("NO_TARGET")
	var supervisor := _person(int(job.guard_id))
	if not _ready(supervisor, true): return Runtime.fail("NO_AUTHORITY")
	var authority := _captive_craft_authority(requester_id, supervisor, str(job.captivity.get("prison_id", "")), false)
	if not authority.ok: return authority
	return cancel(participant_id)

func _captive_craft_request(job: Dictionary, seconds: float) -> Dictionary:
	var checked := _captive_craft_job_context(job)
	if not checked.ok: return {}
	var people: Array = []
	var paused := ""
	for person: Dictionary in [checked.person, checked.supervisor]:
		var participant := _shared_work_participant(person)
		if participant.is_empty(): return {}
		people.append(participant)
		if not bool(person.player) and Fatigue.needs_work_rest(float(_body_get(person, "fatigue")), bool(_body_get(person, "work_resting"))): paused = "REST"
	var request: Dictionary = {"provider": "person_actions", "key": str(job.executor_id), "participants": people,
		"remaining": maxf(0.0, float(job.duration) - float(job.elapsed)), "productive_kind": "joint",
		"progress_multiplier": 1.0, "max_game_seconds": seconds, "paused": paused}
	if paused.is_empty() and float(request.remaining) <= seconds + Fatigue.WORK_PLAN_EPS:
		request.payment_source = lab.terrain.site.inventory
		request.payment = Runtime.RANGED_RECIPES[str(job.recipe)].cost.duplicate(true)
		request.payment_key = "person_actions:" + str(job.executor_id)
	return request

func captive_work_rest_allowed(identity: int) -> bool:
	# Only original FATIGUE IDLE admission uses this; never combat/move/can_act.
	var person := _person(identity)
	if not _captive_craft_body_ready(person) or not _captive_craft_rest_latched(person): return false
	var job := job_for(identity)
	if not job.is_empty() and (str(job.kind) != "captive_craft" or str(job.paused) != "REST"): return false
	var relation: Dictionary = lab.terrain.site.get("captivity", {}).get(str(identity), {})
	var supervisor := _person(int(relation.get("guard_id", -1)))
	if relation.is_empty() or not _ready(supervisor, true) or _captive_craft_threat(person, supervisor) or not has_effective_guard(identity): return false
	if bool(lab.terrain.site.get("paused", false)) or float(lab.terrain.site.get("combat_left", 0.0)) > 0.0: return false
	if not str(relation.get("prison_id", "")).is_empty():
		var slot := prison_slot(identity)
		return slot.ok
	return _within_guard_range(supervisor.cell, person.cell)

func _captive_craft_threat(person: Dictionary, supervisor: Dictionary) -> bool:
	# Actual supervision supplies the observation side; captive keeps its real
	# faction. Check original guard AND actual captive cell, including fire.
	return _threat(supervisor, {}) or lab._fatigue_threat(person.cell, int(supervisor.faction), person.owner, int(person.unit), {})

func _captive_craft_rest_latched(person: Dictionary) -> bool:
	if bool(_body_get(person, "work_resting")): return true
	var original_pool: Dictionary = Fatigue.pool(person.body)
	if original_pool.is_empty(): return false
	# A shared original pool can enter REST because another captive did the
	# work. Its safe non-working captive members must not self-block recovery.
	for identity: String in lab.terrain.site.get("captivity", {}):
		var member := _person(int(identity))
		if not member.is_empty() and bool(_body_get(member, "work_resting")) \
			and is_same(Fatigue.pool(member.body), original_pool): return true
	return false

func technology_capture_for_submit(vehicle_id: String, expected: Dictionary, new_team: int) -> Dictionary:
	# Runtime reads a COMPLETED genuine original takeover job; a direct Runtime
	# call without it must not create technology evidence from team IDs alone.
	for job: Dictionary in _jobs.values():
		if str(job.kind) != "siege_takeover" or str(job.vehicle_id) != vehicle_id or int(job.new_team) != new_team \
			or job.expected != expected or float(job.elapsed) < float(job.duration) - 0.00000001 or not str(job.paused).is_empty(): continue
		var check := _siege_takeover_context(int(job.executor_id), vehicle_id, int(job.requester_id), bool(job.test_dispatch), job)
		if not check.ok: continue
		var original: Variant = lab.site_controller.vehicles._siege_team(check.vehicle)
		var recipient: Variant = check.person.owner
		if original == null or original == recipient or int(original.team_id) <= 0 or int(original.faction_id) == int(recipient.faction_id): return {}
		var reference := {"site_id": str(lab.terrain.site.id), "vehicle_id": vehicle_id}
		return {"version": 1, "vehicle": reference,
			"capture_id": JSON.stringify([reference.site_id, vehicle_id, int(check.vehicle.holder.version) + 1]),
			"source_team_id": int(original.team_id), "source_faction": int(original.faction_id),
			"recipient_team_id": int(recipient.team_id), "recipient_faction": int(recipient.faction_id)}
	return {}

func begin_technology_analysis(requester_id: int, executor_id: int, vehicle_id: String) -> Dictionary:
	if requester_id != _technology_controlled(): return Runtime.fail("NO_AUTHORITY")
	var selected_project := Technology.active_project(_technology_family().get("technology", {}))
	if not selected_project.is_empty() and not bool(TechnologyCatalog.get_node(str(selected_project.tech_id)).get("enabled", false)): return Runtime.fail("NOT_DELIVERED", "本技藝新分析操作尚未交付")
	if is_busy(executor_id): return Runtime.fail("BUSY")
	var check := _technology_analysis_context(requester_id, executor_id, vehicle_id)
	if not check.ok: return check
	var person: Dictionary = check.person
	var research: Dictionary = check.research
	var job := _new_job(person, "technology_analysis", -1)
	job.merge({"requester_id": requester_id, "vehicle_id": vehicle_id, "vehicle_owner": check.vehicle, "asset_team_owner": check.source_team,
		"vehicle_state": check.vehicle.duplicate(true), "duration": float(research.duration), "terrain": lab.terrain, "site_state": lab.terrain.site,
		"technology_family_id": str(research.family.family_id), "technology_epoch": int(research.family.technology.epoch),
		"technology_project": int(research.project.id), "technology_purpose": str(research.project.purpose), "technology_id": str(research.project.tech_id),
		"executor_owner": person.owner, "executor_body": person.body, "executor_holder": person.holder, "executor_cargo": person.cargo,
		"executor_version": int(person.holder.version), "executor_technology": _body_get(person, "technology").duplicate(true)})
	_jobs[str(executor_id)] = job
	return Runtime.ok("原研究者開始拆解分析；尚未消耗器械或取得證據", {"seconds": job.duration})

func _technology_analysis_context(requester_id: int, executor_id: int, vehicle_id: String, job: Dictionary = {}) -> Dictionary:
	var guarded := crowd_action_guard([executor_id])
	if not guarded.ok: return guarded
	if not has_method("_technology_analysis_research_candidate"): return Runtime.fail("UNIMPLEMENTED", "原器械研究與個人抵扣階段尚未接妥")
	var person := _person(executor_id)
	if not _ready(person) or not _technology_member(executor_id) or bool(lab.terrain.site.get("paused", false)) \
		or float(lab.terrain.site.get("combat_left", 0.0)) > 0.0 or lab.site_controller.region_operation_pending(): return Runtime.fail("BUSY")
	if is_busy(executor_id) and (job.is_empty() or _job_key_for(executor_id) != str(job.executor_id)): return Runtime.fail("BUSY")
	var vehicle: Dictionary = lab.terrain.site.get("vehicles", {}).get(vehicle_id, {})
	var transport: SiteVehicleTransport = lab.site_controller.vehicles
	if not transport.is_siege(vehicle) or float(vehicle.get("hp", 0.0)) <= 0.0 \
		or str(vehicle.get("phase", "")) in ["building", "wrecked"]: return Runtime.fail("NO_TARGET")
	if int(vehicle.get("vehicle_version", -1)) == 2 and not vehicle.has("technology_capture"): return Runtime.fail("NO_PROVENANCE", "舊器械可使用但不能分析")
	if int(vehicle.get("vehicle_version", -1)) != 3 or not vehicle.has("technology_capture") \
		or not Runtime.technology_capture_valid(vehicle.technology_capture): return Runtime.fail("INVALID_PROVENANCE", "新版原器械來源不合法，不能當成舊缺欄位")
	if vehicle.technology_capture.is_empty(): return Runtime.fail("NO_PROVENANCE", "只接受真敵對繳獲來源；無來源器械可使用但不能分析")
	var source_team: Variant = transport._siege_team(vehicle)
	if source_team == null or not transport._authorized(source_team, requester_id, 0, false) \
		or int(source_team.faction_id) != int(vehicle.technology_capture.recipient_faction): return Runtime.fail("NO_AUTHORITY", "須同時有原器械當前合法處置權")
	if not transport.touches_vehicle(person.cell, vehicle): return Runtime.fail("UNREACHABLE")
	for flight: Dictionary in lab.siege_projectiles:
		if str(flight.source_vehicle) == vehicle_id: return Runtime.fail("BUSY")
	var removal := Runtime.remove_siege_vehicle(lab.terrain, vehicle_id, int(vehicle.team_id), lab.site_controller._siege_people_occupied, true)
	if not removal.ok: return removal
	if not job.is_empty() and (not is_same(lab.terrain, job.terrain) or not is_same(lab.terrain.site, job.site_state) \
		or not is_same(vehicle, job.vehicle_owner) or not is_same(source_team, job.asset_team_owner) or vehicle != job.vehicle_state \
		or not is_same(person.owner, job.executor_owner) or not is_same(person.body, job.executor_body) \
		or not is_same(person.holder, job.executor_holder) or not is_same(person.cargo, job.executor_cargo) \
		or int(person.holder.version) != int(job.executor_version) or int(person.hit) != int(job.executor_hit) \
		or lab.terrain.index(person.cell) != int(job.executor_cell) or _body_get(person, "technology") != job.executor_technology): return Runtime.fail("STALE_SOURCE")
	# Root's actual expanded research owner validates current authority OR the
	# accepted scope, real prerequisites (including F12 original traction receipt),
	# project/executor/purpose/epoch, enabled operation, original team consent,
	# credit phase and original lifetime receipt. It returns candidates only.
	var research: Dictionary = call("_technology_analysis_research_candidate", requester_id, executor_id, vehicle, job)
	if not bool(research.get("ok", false)): return research
	if str(research.project.tech_id) not in ["F11", "F12"] or not is_finite(float(research.duration)) or float(research.duration) <= 0.0: return Runtime.fail("UNIMPLEMENTED")
	return Runtime.ok("", {"person": person, "vehicle": vehicle, "source_team": source_team, "research": research})

func _technology_analysis_job_context(job: Dictionary) -> Dictionary:
	return _technology_analysis_context(int(job.requester_id), int(job.executor_id), str(job.vehicle_id), job)

func _commit_technology_analysis(job: Dictionary) -> Dictionary:
	var check := _technology_analysis_job_context(job)
	if not check.ok: return check
	var prepared: Dictionary = check.research
	# The root hook must give a valid original Family candidate referencing the
	# same original person receipt, not an independent project credit authority.
	if not Technology.valid_person(prepared.person_candidate) \
		or not Family.validate_family(prepared.family_candidate, _technology_site_id()): return Runtime.fail("INVALID_TECHNOLOGY")
	var removed := Runtime.remove_siege_vehicle(lab.terrain, str(job.vehicle_id), int(check.vehicle.team_id), lab.site_controller._siege_people_occupied)
	if not removed.ok: return removed
	# All guards precede removal. These two original owner writes cannot fail or
	# yield. No material refund, skill grant, knowledge or automatic phase finish.
	_body_set(check.person, "technology", prepared.person_candidate)
	lab.terrain.site.family = prepared.family_candidate
	return Runtime.ok("已消耗原繳獲器械並同次提交此人的一次性分析抵扣", {"vehicle": str(job.vehicle_id), "person_id": int(job.executor_id)})

func _technology_analysis_research_candidate(requester_id: int, executor_id: int, vehicle: Dictionary, job: Dictionary = {}) -> Dictionary:
	var family := _technology_family()
	var raw: Dictionary = family.get("technology", {})
	if not Technology.valid_scope_record(raw, "family") or not Technology.local_holder(raw, _technology_site_id()): return Runtime.fail("REMOTE_HOLDER")
	var project := Technology.active_project(raw)
	if project.is_empty() or int(project.rules_version) != 2 or project.tech_id not in ["F11", "F12"] \
		or not Technology.same_person_ref(project.executor, _technology_ref(executor_id), raw.get("person_links", [])): return Runtime.fail("NO_TARGET")
	if not _technology_scope_duty("family", family).ok or not _technology_consent_valid(executor_id, project.consents, str(project.purpose)): return Runtime.fail("NO_AUTHORITY")
	if job.is_empty():
		var authority := _technology_scope_command(requester_id, "family", family)
		if not authority.ok: return authority
	elif str(job.technology_family_id) != str(family.family_id) or int(job.technology_epoch) != int(raw.epoch) \
		or int(job.technology_project) != int(project.id) or str(job.technology_purpose) != str(project.purpose): return Runtime.fail("STALE_PROJECT")
	var known := _technology_known_for()
	for required: String in TechnologyCatalog.get_node(str(project.tech_id)).prerequisites.all:
		if not known.has(required): return Runtime.fail("PREREQUISITE")
	if project.tech_id == "F12" and (str(vehicle.get("kind", "")) != "counterweight_trebuchet" or not Technology.family_traction_recorded(raw)): return Runtime.fail("PREREQUISITE")
	if project.tech_id == "F11" and str(vehicle.get("kind", "")) not in ["ballista", "ram", "traction_trebuchet", "siege_tower"]: return Runtime.fail("NO_TARGET")
	var remaining: Dictionary = Runtime.technology_remaining_work(lab.terrain, project, _technology_ref(executor_id))
	if not remaining.ok or float(remaining.get("remaining_baseline", 0.0)) <= 0.0: return remaining if not remaining.ok else Runtime.fail("NO_TARGET")
	var person := _person(executor_id)
	var candidate := Technology.analysis_candidate(_body_get(person, "technology"), str(project.tech_id), str(family.family_id), project,
		str(vehicle.id), str(vehicle.technology_capture.capture_id))
	if candidate.is_empty(): return Runtime.fail("ANALYSIS_ALREADY_USED", "此人已領過此節點分析，或本人科技資料不合法")
	for receipt: Dictionary in candidate.analysis:
		if receipt.tech_id == project.tech_id:
			receipt.credited_work = minf(float(receipt.credited_work), float(remaining.remaining_baseline) * 0.5)
	if not Technology.valid_person(candidate): return Runtime.fail("INVALID_TECHNOLOGY")
	return Runtime.ok("", {"family": family, "project": project, "person_candidate": candidate, "family_candidate": family.duplicate(true), "duration": 600.0})

func technology_phase_work_credit_candidate(token: Dictionary, remaining_work: float) -> Dictionary:
	if not is_finite(remaining_work) or remaining_work <= 0.0: return Runtime.fail("INVALID_WORK")
	var owner := _technology_scope_owner(str(token.get("scope", "")), str(token.get("scope_id", "")))
	var project := Technology.active_project(owner.get("technology", {}))
	var initial := not project.is_empty() and int(token.get("attempt", -1)) == int(project.next_attempt)
	var checked := _technology_phase_context(token, true) if initial else _technology_paid_phase_context(token)
	if not checked.ok: return checked
	if token.scope != "family" or token.tech_id not in ["F11", "F12"]: return Runtime.ok("", {"credit": 0.0})
	var original: Dictionary = _body_get(checked.person, "technology")
	if original.is_empty(): return Runtime.ok("", {"credit": 0.0})
	if not Technology.valid_person(original): return Runtime.fail("INVALID_TECHNOLOGY")
	var candidate := Technology.normalize_person(original)
	for receipt: Dictionary in candidate.get("analysis", []):
		if receipt.tech_id != token.tech_id or receipt.family_id != str(checked.owner.family_id) \
			or int(receipt.project_id) != int(token.project_id) or receipt.purpose != token.purpose: continue
		var credit := minf(maxf(0.0, float(receipt.credited_work) - float(receipt.used_work)), remaining_work * 0.5)
		if credit <= 0.0: return Runtime.ok("", {"credit": 0.0})
		receipt.used_work = float(receipt.used_work) + credit
		if not Technology.valid_person(candidate): return Runtime.fail("INVALID_TECHNOLOGY")
		return Runtime.ok("", {"credit": credit, "remaining_work": remaining_work, "person": checked.person, "expected_person": original, "person_candidate": candidate})
	return Runtime.ok("", {"credit": 0.0})

func can_publish_phase_work_credit(prepared: Dictionary) -> bool:
	return bool(prepared.get("ok", false)) and (float(prepared.get("credit", 0.0)) == 0.0 \
		or Technology.valid_person(prepared.get("person_candidate")) and _body_get(prepared.person, "technology") == prepared.expected_person)

func publish_phase_work_credit(prepared: Dictionary) -> void:
	if float(prepared.get("credit", 0.0)) > 0.0: _body_set(prepared.person, "technology", prepared.person_candidate)

func technology_family_siege_history_candidate(person_id: int, vehicle_id: String, binding: String, research_prepared: Dictionary = {}) -> Dictionary:
	var family := _technology_family()
	if not _technology_member(person_id) or family.is_empty(): return Runtime.ok("", {"state": {}})
	var runtime_script: Variant = Runtime
	if not runtime_script.has_method("technology_siege_history_source_candidate"): return Runtime.fail("UNIMPLEMENTED")
	var person := _person(person_id)
	var task: Dictionary = person.body.get("work_task", {}) if person.body is Dictionary else (lab.terrain.site.manual if person.owner == lab.character else lab.terrain.site.worker)
	# Controlled original vehicle work lives in this original PA job, not the
	# camp manual dictionary. Preserve Army/camp fallback for their true tasks.
	var job: Dictionary = _jobs.get(_job_key_for(person_id), {})
	var original_vehicle: Dictionary = lab.terrain.site.get("vehicles", {}).get(vehicle_id, {})
	if str(job.get("kind", "")) == "technology_vehicle" and int(job.get("executor_id", -1)) == person_id \
		and job.get("vehicle_id") == vehicle_id and is_same(job.get("terrain"), lab.terrain) \
		and is_same(job.get("site_state"), lab.terrain.site) and is_same(job.get("vehicle_ref"), original_vehicle) \
		and is_same(job.get("build_ref"), original_vehicle.get("build")) and is_same(job.get("technology_executor_body"), person.body) \
		and job.get("work_task") is Dictionary and job.work_task.get("target") == "vehicle:" + vehicle_id and job.work_task.get("action") == "construct":
		task = job.work_task
	var source: Dictionary = runtime_script.call("technology_siege_history_source_candidate", lab.terrain, vehicle_id, person_id, task)
	if not source.ok or source.get("binding") != binding: return source if not source.ok else Runtime.fail("INVALID_RECEIPT")
	var candidate := _technology_candidate()
	if candidate.is_empty(): return Runtime.ok("", {"state": {}})
	var record: Dictionary = candidate.technology
	if not research_prepared.is_empty():
		if not is_same(research_prepared.get("owner"), family) or not is_same(research_prepared.get("site_state"), lab.terrain.site) \
			or not Technology.valid_family_tech(research_prepared.get("state")): return Runtime.fail("STALE_SOURCE")
		record = research_prepared.state
	var receipt := {"event_id": JSON.stringify([_technology_site_id(), vehicle_id, "siege_complete"]), "site_id": _technology_site_id(),
		"vehicle_id": vehicle_id, "person_id": person_id, "binding": binding}
	var state := Technology.family_siege_history_candidate(record, receipt)
	if state.is_empty(): return Runtime.fail("INVALID_TECHNOLOGY")
	candidate.technology = state
	if not Family.validate_family(candidate, _technology_site_id()): return Runtime.fail("INVALID_TECHNOLOGY")
	return Runtime.ok("", {"owner": family, "state": state, "site_state": lab.terrain.site})

func publish_family_siege_history(prepared: Dictionary) -> void:
	if not prepared.state.is_empty(): prepared.owner.technology = prepared.state

# Expanded research stays on the same original people, scopes and operation
# owners. The token is stored on their original feature/order, never here.
func _technology_scope_owner(scope: String, scope_id: String = "") -> Dictionary:
	if scope == "family":
		var family := _technology_family()
		return family if not family.is_empty() and (scope_id.is_empty() or family.get("family_id") == scope_id) else {}
	if scope == "settlement":
		var settlement := Settlement.record(lab.terrain)
		return settlement if not settlement.is_empty() and (scope_id.is_empty() or settlement.get("settlement_id") == scope_id) else {}
	if scope == "nation": return lab.terrain.site.get("equipment_nations", {}).get(scope_id, {})
	return {}

func _rebind_scope_technology_sources() -> void:
	# Only init after original validated bind may rebuild physical witnesses.
	# A later replacement never acquires this admission by object similarity.
	var scopes: Array[Dictionary] = [{"scope": "family", "owner": _technology_family(), "id": ""}, {"scope": "settlement", "owner": Settlement.record(lab.terrain), "id": ""}]
	for identity: String in lab.terrain.site.get("equipment_nations", {}):
		scopes.append({"scope": "nation", "owner": lab.terrain.site.equipment_nations[identity], "id": identity})
	for item: Dictionary in scopes:
		var owner: Dictionary = item.owner
		var raw: Dictionary = owner.get("technology", {})
		if not Technology.valid_scope_record(raw, str(item.scope)) or raw.holder_site_id != _technology_site_id(): continue
		var identity := _technology_scope_id(str(item.scope), owner, str(item.id))
		for project: Dictionary in raw.projects:
			if int(project.rules_version) != 2 or project.budget.is_empty() or project.budget.status != "granted" \
				or project.budget.source_site_id != _technology_site_id(): continue
			var source_key := JSON.stringify([str(item.scope), identity, int(project.id)])
			if project.budget.holder == "depot":
				_technology_source_refs[source_key] = {"terrain": lab.terrain, "site": lab.terrain.site, "depot": lab.terrain.site.depot_items, "stock": lab.terrain.site.inventory}
			elif item.scope == "family" and project.tech_id == "F15" and str(project.budget.holder).begins_with("vehicle:"):
				var vehicle: Dictionary = lab.terrain.site.get("vehicles", {}).get(str(project.budget.holder).trim_prefix("vehicle:"), {})
				if not vehicle.is_empty(): _technology_source_refs[source_key] = {"terrain": lab.terrain, "site": lab.terrain.site, "vehicle": vehicle, "holder": vehicle.holder, "cargo": vehicle.cargo}
			elif item.scope == "nation" and str(project.budget.holder).begins_with("nation-order:"):
				var source := _rebind_nation_order_source(owner, identity, project)
				if not source.is_empty(): _technology_source_refs[source_key] = source

func _rebind_nation_order_source(nation: Dictionary, nation_id: String, project: Dictionary) -> Dictionary:
	if equipment_orders == null or not is_same(equipment_orders.lab, lab) \
		or not equipment_orders.valid_nation_operation_record(nation.get("technology_operations"), lab.terrain.site.item_definitions, {}): return {}
	var holder := str(project.budget.holder)
	var source_namespace: Variant = JSON.parse_string(holder.trim_prefix("nation-order:"))
	if not source_namespace is Array or source_namespace.size() != 3 or source_namespace[0] != _technology_site_id() \
		or source_namespace[1] != nation_id or not source_namespace[2] is String or holder != "nation-order:" + JSON.stringify(source_namespace): return {}
	var operations: Dictionary = nation.technology_operations
	if str(source_namespace[2]).begins_with("production_"):
		var order: Dictionary = operations.get("orders", {}).get(str(source_namespace[2]), {})
		if order.is_empty() or order.status not in ["active", "complete"] or order.source.is_empty() or order.source.status != "granted" \
			or order.source.site_id != _technology_site_id() or project.tech_id != "N05" or int(project.rules_version) != 2 \
			or not Technology.valid_ref(project.executor) or project.executor.site_id != _technology_site_id() or int(order.operator_id) != int(project.executor.person_id): return {}
		var grantor := {"site_id": _technology_site_id(), "person_id": int(order.source.person_id)}
		if project.budget.grantor != grantor: return {}
		for resource: String in project.budget.cap:
			if int(project.budget.cap[resource]) > int(order.source.cap.get(resource, 0)): return {}
		for resource: String in project.budget.spent:
			if int(project.budget.spent[resource]) > int(order.source.spent.get(resource, 0)): return {}
		var stock := SiteStockpiles.stock_endpoint(lab.terrain, str(order.feature_id))
		if stock.is_empty(): return {}
		return Runtime.ok("", {"kind": "nation_order", "holder": holder, "source_site_id": _technology_site_id(), "grantor": grantor,
			"cap": order.source.cap.duplicate(), "spent": {}, "physical_holder": stock.holder, "physical_cargo": stock.cargo,
			"holder_version": int(stock.holder.version), "expected_refs": {"terrain": lab.terrain, "site": lab.terrain.site, "nation": nation,
				"operations": operations, "order": order, "holder": stock.holder, "cargo": stock.cargo}})
	var order: Dictionary = operations.get("public_orders", {}).get(str(source_namespace[2]), {})
	if order.is_empty() or order.status == "revoked" or order.scope_site_id != _technology_site_id() or order.scope_nation_id != nation_id \
		or order.tech_id != project.tech_id or int(order.project_id) != int(project.id) or not equipment_orders._public_source_paid(order): return {}
	var authorization: Dictionary = order.payload.source
	var grantor := {"site_id": _technology_site_id(), "person_id": int(authorization.person_id)}
	if project.budget.grantor != grantor: return {}
	for resource: String in project.budget.cap:
		if int(project.budget.cap[resource]) > int(authorization.cap.get(resource, 0)): return {}
	var stock := SiteStockpiles.stock_endpoint(lab.terrain, str(order.payload.reserve_feature_id))
	if stock.is_empty(): return {}
	return Runtime.ok("", {"kind": "nation_order", "holder": holder, "source_site_id": _technology_site_id(), "grantor": grantor,
		"cap": authorization.cap.duplicate(), "spent": {}, "physical_holder": stock.holder, "physical_cargo": stock.cargo,
		"holder_version": int(stock.holder.version), "expected_refs": {"terrain": lab.terrain, "site": lab.terrain.site, "nation": nation,
			"operations": operations, "order": order, "holder": stock.holder, "cargo": stock.cargo}})

func _technology_scope_id(scope: String, owner: Dictionary, nation_id: String = "") -> String:
	return str(owner.get("family_id", "")) if scope == "family" else (str(owner.get("settlement_id", "")) if scope == "settlement" else nation_id)

func _technology_scope_duty(scope: String, owner: Dictionary, read_only: bool = false) -> Dictionary:
	if scope == "family": return _technology_duty("family.research")
	if scope == "settlement": return Settlement.duty_resolve(lab, "settlement.head", read_only)
	if scope == "nation" and equipment_orders != null: return equipment_orders.nation_duty_resolve(owner, "nation.institutions", read_only)
	return Runtime.fail("NO_AUTHORITY")

# REPLACE _technology_phase_context

func _technology_scope_person(scope: String, owner: Dictionary, identity: int, busy_allowed: bool = false, bound_token: Dictionary = {}) -> Dictionary:
	var guarded := crowd_action_guard([identity])
	if not guarded.ok: return guarded
	var person := _person(identity)
	if person.is_empty(): return Runtime.fail("BUSY")
	var ready := _ready(person)
	if not ready and _technology_matching_original_task(person, bound_token):
		# The exact original research task is allowed here, not cleared or hidden.
		# Runtime/WorkTeam still validate its station, tools, water and materials.
		ready = not person.is_empty() and float(person.hp) > 0.0 and float(person.ko) <= 0.0 and not bool(person.captive) and not bool(person.moving) \
			and float(_body_get(person, "exchange_stagger")) <= 0.0 and not bool(_body_get(person, "attack")) and str(_body_get(person, "pose")) == "idle" \
			and not is_guarding(identity) and not lab.site_controller.region_operation_pending() \
			and (person.owner.combat_can_act(int(person.unit)) if int(person.unit) >= 0 else person.owner.can_act())
	if person.owner is CrowdOwner and not person.owner.crowd_site.work_fatigue_work_start_ready(identity): ready = false
	if not ready or not busy_allowed and is_busy(identity) or bool(lab.terrain.site.get("paused", false)) \
		or float(lab.terrain.site.get("combat_left", 0.0)) > 0.0: return Runtime.fail("BUSY")
	if scope == "family" and not _technology_member(identity): return Runtime.fail("NO_AUTHORITY")
	if scope == "settlement" and not Settlement.office_person_ok(lab, identity): return Runtime.fail("NO_AUTHORITY")
	if scope == "nation" and (equipment_orders == null or not equipment_orders._member(owner, identity)): return Runtime.fail("NO_AUTHORITY")
	return Runtime.ok("", {"person": person})

func _technology_matching_original_task(person: Dictionary, token: Dictionary) -> bool:
	if person.is_empty() or token.is_empty() or not Technology.valid_ref(token.get("person")) \
		or token.person.site_id != _technology_site_id() or int(token.person.person_id) != int(person.person_id): return false
	var original_job: Dictionary = _jobs.get(_job_key_for(int(person.person_id)), {})
	if original_job.get("kind") == "food_order":
		return settlement_food_own_job(person, original_job.get("food_order", {})) and is_same(original_job.get("nation_token"), token) \
			and Runtime._settlement_food_token(lab.terrain, token, original_job.food_order)
	if original_job.get("kind") == "water_schedule":
		return is_same(original_job.get("executor_body"), person.body) \
			and is_same(original_job.get("terrain"), lab.terrain) and is_same(original_job.get("site_state"), lab.terrain.site) \
			and original_job.get("nation_token") == token and token.get("binding") == "water_priority" \
			and token.get("target_id") == "feature:" + str(Settlement.record(lab.terrain).get("center_id", ""))
	var target := str(token.get("target_id", ""))
	var task: Dictionary = {}
	if person.body is Dictionary: task = person.body.get("work_task", {})
	else: task = lab.terrain.site.manual if person.owner == lab.character else lab.terrain.site.worker
	var job: Dictionary = _jobs.get(_job_key_for(int(person.person_id)), {})
	if job.get("kind") in ["technology_feature", "technology_vehicle"] and is_same(job.get("technology_executor_body"), person.body) \
		and is_same(job.get("site_state"), lab.terrain.site): task = job.work_task
	var named_transit: bool = Technology.integer(task.get("version"), 3, 3) and task.get("named") == true and str(task.get("mode", "")) in ["idle", "travel"] and SiteWorkTeam.valid_task(lab.terrain, lab.terrain.site, task)
	if task.is_empty() or str(task.get("mode", "")) not in ["work", "rest"] and not named_transit: return false
	if target.begins_with("feature:"):
		var key := target.trim_prefix("feature:")
		var feature: Dictionary = lab.terrain.site.get("features", {}).get(key, {})
		return str(task.get("target", "")) == target and is_same(feature.get("tech_trial"), token)
	if target.begins_with("vehicle:"):
		var key := target.trim_prefix("vehicle:")
		var vehicle: Dictionary = lab.terrain.site.get("vehicles", {}).get(key, {})
		return str(task.get("target", "")) == target and is_same(vehicle.get("tech_trial"), token)
	return false

func _technology_scope_command(requester_id: int, scope: String, owner: Dictionary) -> Dictionary:
	if requester_id != _technology_controlled() or owner.is_empty(): return Runtime.fail("NO_AUTHORITY")
	var duty := _technology_scope_duty(scope, owner)
	if not duty.ok or int(duty.get("decider", -1)) != requester_id: return Runtime.fail("NO_AUTHORITY")
	return _technology_scope_person(scope, owner, requester_id)

func _technology_known_for(nation_id: String = "") -> Array:
	var known: Array = []
	for owner: Dictionary in [_technology_family(), Settlement.record(lab.terrain), _technology_scope_owner("nation", nation_id)]:
		var raw: Variant = owner.get("technology", {})
		if not raw is Dictionary or Technology.is_holder_reference(raw): continue
		for identity: Variant in raw.get("known", []):
			if identity is String and not known.has(identity): known.append(identity)
	return known

func prepare_scope_technology(requester_id: int, executor_id: int, tech_id: String, scope_id: String = "", route_id: String = "default", mode: String = "first") -> Dictionary:
	var node := TechnologyCatalog.get_node(tech_id)
	if node.get("enabled") != true: return Runtime.fail("UNIMPLEMENTED", "此節點的原用途及驗收尚未開放")
	var scope := str(node.get("scope", ""))
	if scope not in ["family", "settlement", "nation"] or tech_id == "F07": return Runtime.fail("INVALID_TECHNOLOGY")
	var owner := _technology_scope_owner(scope, scope_id)
	var check := _technology_scope_command(requester_id, scope, owner)
	if not check.ok: return check
	check = _technology_scope_person(scope, owner, executor_id)
	if not check.ok: return check
	if scope == "family" and Technology.learned(_body_get(check.person, "technology"), tech_id): return Runtime.fail("ALREADY_LEARNED")
	var known := _technology_known_for(scope_id if scope == "nation" else "")
	if tech_id == "F12" and not Technology.family_traction_recorded(owner.get("technology", {})): return Runtime.fail("PREREQUISITE", "本族須有原牽引投石機完成實績")
	var route := Technology.scope_route(tech_id, route_id)
	if route.is_empty(): return Runtime.fail("INVALID_ROUTE")
	for required: String in node.prerequisites.all:
		if not known.has(required): return Runtime.fail("PREREQUISITE", "尚未完成原前置 " + required)
	if not node.prerequisites.any.is_empty():
		var found := false
		for required: String in node.prerequisites.any: found = found or known.has(required)
		if not found: return Runtime.fail("PREREQUISITE")
	for required: String in route.requires_all:
		if not known.has(required): return Runtime.fail("PREREQUISITE", "此原路線尚缺 " + required)
	var candidate: Dictionary = _technology_candidate() if scope == "family" else owner.duplicate(true)
	if candidate.is_empty(): return Runtime.fail("REMOTE_HOLDER")
	var raw: Dictionary = candidate.get("technology", {})
	var current := Technology.active_project(raw)
	if not current.is_empty() and not current.executor.is_empty() and is_busy(int(current.executor.person_id)): return Runtime.fail("BUSY")
	var prepared := Technology.scope_prepare_candidate(raw, scope, tech_id, _technology_ref(executor_id), route_id, mode)
	if not prepared.ok: return prepared
	if scope == "settlement":
		if not Technology.integer(candidate.get("version"), 1, 2): return Runtime.fail("CORRUPT_STATE", "原聚落版本不符")
		var original_fields: Array = SiteSettlement.FIELDS.duplicate()
		if int(candidate.version) == 2:
			original_fields.append("technology")
			if candidate.has("technology_operations"): original_fields.append("technology_operations")
		if candidate.has("technology_operations") and not SiteSettlement.valid_technology_operations(lab.terrain, candidate.technology_operations): return Runtime.fail("CORRUPT_STATE")
		if not Technology.keys(candidate, original_fields): return Runtime.fail("CORRUPT_STATE", "原聚落欄位不符")
	candidate.technology = prepared.state
	if scope == "settlement":
		candidate.version = 2
		var fields: Array = SiteSettlement.FIELDS.duplicate()
		fields.append("technology")
		if candidate.has("technology_operations"): fields.append("technology_operations")
		if not Technology.keys(candidate, fields) or not Technology.valid_scope_record(candidate.technology, "settlement"):
			return Runtime.fail("CORRUPT_STATE", "原聚落科技候選欄位不符")
	if scope == "family":
		if not Family.validate_family(candidate, _technology_site_id()): return Runtime.fail("INVALID_TECHNOLOGY")
		lab.terrain.site.family = candidate
	else:
		if scope == "settlement": owner.version = int(candidate.version)
		owner["technology"] = prepared.state
	return Runtime.ok("已準備原範疇研究；實際工位、材料及成果由原作業入口核對", {"phase": prepared.phase, "scope": scope, "scope_id": _technology_scope_id(scope, candidate, scope_id)})

func grant_scope_technology_budget(requester_id: int, scope: String, scope_id: String, cap: Dictionary, operation: String = "grant") -> Dictionary:
	var owner := _technology_scope_owner(scope, scope_id)
	var check := _technology_scope_person(scope, owner, requester_id)
	if requester_id != _technology_controlled() or owner.is_empty() or not check.ok: return Runtime.fail("NO_AUTHORITY")
	check = _ranged_craft_context(check.person)
	if not check.ok: return check
	var raw: Dictionary = owner.get("technology", {})
	if operation != "revoke" and not _scope_project_activation(raw): return Runtime.fail("UNIMPLEMENTED")
	var prepared := Technology.scope_budget_candidate(raw, scope, _technology_ref(requester_id), "depot", cap, operation)
	if not prepared.ok: return prepared
	owner.technology = prepared.state
	var project := Technology.active_project(owner.technology)
	_technology_source_refs[JSON.stringify([scope, scope_id, int(project.id)])] = {"terrain": lab.terrain, "site": lab.terrain.site, "depot": lab.terrain.site.depot_items, "stock": lab.terrain.site.inventory}
	return Runtime.ok("原營地已核定有限累計材料，實際交易仍由原作業付款")

func _technology_phase_context(token: Dictionary, binding: bool = false, require_material_source: bool = true, read_only: bool = true) -> Dictionary:
	if token.get("tech_id") == "F15" and token.get("binding") == "fire_pot_shot": return _fire_pot_shot_phase_context(token, binding, require_material_source)
	var owner := _technology_scope_owner(str(token.get("scope", "")), str(token.get("scope_id", "")))
	var raw: Dictionary = owner.get("technology", {})
	var scope := str(token.get("scope", ""))
	if not Technology.valid_scope_record(raw, scope) or int(raw.epoch) != int(token.get("epoch", -1)) or raw.holder_site_id != _technology_site_id(): return Runtime.fail("STALE_PROJECT")
	var project := Technology.active_project(raw)
	var reference: Dictionary = token.get("person", {})
	if project.is_empty() or int(project.rules_version) != 2 or int(project.id) != int(token.get("project_id", -1)) \
		or project.purpose != token.get("purpose") or project.tech_id != token.get("tech_id") \
		or not Technology.same_person_ref(project.executor, reference, raw.get("person_links", [])) \
		or (not Technology.integer(token.get("attempt"), int(project.next_attempt), int(project.next_attempt)) if binding else not Technology.integer(token.get("attempt"), 1, int(project.next_attempt) - 1)): return Runtime.fail("STALE_PROJECT")
	var phase := Technology.scope_next_phase(project, reference, raw.get("person_links", []))
	if phase.is_empty() or phase.id != token.get("phase_id") or phase.binding != token.get("binding") \
		or not Technology.scope_phase_materials(token.get("materials"), phase.materials): return Runtime.fail("STALE_PHASE")
	var person_check := _technology_scope_person(scope, owner, int(reference.get("person_id", -1)), true, token if not binding else {})
	if not person_check.ok: return person_check
	if not _technology_scope_duty(scope, owner, read_only).ok or not _technology_consent_valid(int(reference.person_id), project.consents, str(project.purpose), token if not binding else {}, read_only): return Runtime.fail("NO_AUTHORITY")
	var context := Runtime.ok("", {"owner": owner, "record": raw, "project": project, "phase": phase, "person": person_check.person})
	if not require_material_source: return context # Candidate caller must separately prove its true original source.
	if phase.materials.is_empty(): return context # No zero-cost financial approval is invented.
	if project.budget.is_empty() or project.budget.status != "granted" or project.budget.source_site_id != _technology_site_id(): return Runtime.fail("NO_BUDGET")
	var source: Dictionary = _technology_source_refs.get(JSON.stringify([scope, str(token.scope_id), int(project.id)]), {})
	if str(project.budget.holder).begins_with("nation-order:") or str(project.budget.holder).begins_with("settlement-order:"):
		if not source.get("physical_holder") is Dictionary or not Technology.integer(source.physical_holder.get("version")): return Runtime.fail("STALE_SOURCE")
		# An accepted grant is not a reservation on the whole Warehouse version.
		# Candidate/prepayment queries below still compare their held version;
		# later work rechecks current authority and the SAME true owner references.
		var current := source.duplicate()
		current.holder_version = int(source.physical_holder.version)
		var checked := _technology_original_source_query(token, current)
		if not checked.ok or checked.holder != project.budget.holder or checked.grantor != project.budget.grantor: return Runtime.fail("STALE_SOURCE")
		for resource: String in project.budget.cap:
			if int(project.budget.cap[resource]) > int(checked.cap.get(resource, 0)): return Runtime.fail("NO_BUDGET")
		return context
	if project.budget.holder != "depot" or source.is_empty() or not is_same(source.get("terrain"), lab.terrain) \
		or not is_same(source.get("site"), lab.terrain.site) or not is_same(source.get("depot"), lab.terrain.site.depot_items) \
		or not is_same(source.get("stock"), lab.terrain.site.inventory): return Runtime.fail("STALE_SOURCE")
	return context

# REPLACE _nation_original_order_context

func technology_phase_active_guard(token: Dictionary) -> Dictionary:
	return _technology_paid_phase_context(token)

# EXACT additional call sites to change in their original methods:
# technology_phase_receipt_candidate: first _technology_phase_context(token)
#     becomes _technology_paid_phase_context(token).
# technology_phase_work_credit_candidate: preserve its computed initial-binding
#     predicate. initial=true uses _technology_phase_context(token,true), while
#     initial=false uses _technology_paid_phase_context(token). A NEW vehicle
#     still needs its original full source guard, not the old-attempt fallback.
#     Initial binding/payment APIs retain their original material-source query.
# Original technology_phase_work_preflight: initial=true keeps source-free true
#     owner admission plus Runtime's separately held source candidate; existing
#     initial=false takes technology_phase_active_guard(token) after the true
#     Runtime paid target proof. Never generally flip require_material_source.

func request_scope_technology_consent(requester_id: int, scope: String, scope_id: String, person_id: int) -> Dictionary:
	var owner := _technology_scope_owner(scope, scope_id)
	var checked := _technology_scope_command(requester_id, scope, owner)
	if not checked.ok: return checked
	checked = _technology_scope_person(scope, owner, person_id)
	if not checked.ok: return checked
	var raw: Dictionary = owner.get("technology", {})
	if not _scope_project_activation(raw): return Runtime.fail("UNIMPLEMENTED")
	var project := Technology.active_project(raw)
	if project.is_empty() or int(project.executor.get("person_id", -1)) != person_id: return Runtime.fail("NO_TARGET")
	checked = _technology_scope_consent_candidate(checked.person, str(project.purpose), requester_id)
	if not checked.ok: return checked
	if checked.consent.is_empty(): return checked
	for index: int in project.consents.size():
		if project.consents[index].site_id == _technology_site_id() and int(project.consents[index].person_id) == person_id:
			project.consents[index] = checked.consent
			return Runtime.ok("原隊已同意本次範疇具名工作")
	project.consents.append(checked.consent)
	return Runtime.ok("原隊已同意本次範疇具名工作")

func technology_phase_binding_candidate(token: Dictionary, original_source: Dictionary = {}) -> Dictionary:
	if not Technology.keys(token, ["scope", "scope_id", "project_id", "epoch", "purpose", "tech_id", "phase_id", "attempt", "person", "binding", "target_id", "materials"]) \
		or not token.scope is String or not token.scope_id is String or not token.target_id is String or token.target_id.is_empty(): return Runtime.fail("INVALID_TECHNOLOGY")
	var checked := _technology_phase_context(token, true, original_source.is_empty())
	if not checked.ok: return checked
	var source_record: Dictionary = checked.record
	var source := {}
	if not original_source.is_empty():
		source = _technology_original_source_query(token, original_source)
		if not source.ok: return source
		var budget: Dictionary = checked.project.budget
		if not budget.is_empty() and budget.holder != source.holder:
			for resource: String in budget.spent:
				if int(budget.spent[resource]) > 0: return Runtime.fail("BOUND_SOURCE", "已付項目不換有限來源清支出")
			if budget.holder != "no_materials": return Runtime.fail("BOUND_SOURCE", "不能以私單冒用原depot核額")
		var funded := Technology.scope_budget_candidate(source_record, str(token.scope), source.grantor, str(source.holder), source.cap)
		if not funded.ok: return funded
		source_record = funded.state
	var project := Technology.active_project(source_record)
	for resource: String in token.materials:
		if int(project.budget.spent.get(resource, 0)) + int(token.materials[resource]) > int(project.budget.cap.get(resource, 0)): return Runtime.fail("BUDGET_EXCEEDED")
	var attempted := Technology.scope_attempt_candidate(source_record, str(token.scope), token.person)
	if not attempted.ok or int(attempted.get("attempt", -1)) != int(token.attempt): return attempted if not attempted.ok else Runtime.fail("STALE_PROJECT")
	if token.materials.is_empty() and project.budget.is_empty():
		var duty := _technology_scope_duty(str(token.scope), checked.owner)
		var zero_budget := Technology.scope_budget_candidate(attempted.state, str(token.scope), _technology_ref(int(duty.decider)), "no_materials", {})
		if not zero_budget.ok: return zero_budget
		attempted.state = zero_budget.state
	return Runtime.ok("", {"owner": checked.owner, "record": checked.record, "state": attempted.state, "site_state": lab.terrain.site,
		"original_source": source, "source_key": JSON.stringify([str(token.scope), str(token.scope_id), int(token.project_id)])})

func publish_phase_binding(prepared: Dictionary) -> void:
	prepared.owner.technology = prepared.state
	if not prepared.get("original_source", {}).is_empty():
		var source: Dictionary = prepared.original_source.duplicate()
		source.holder_version = int(source.physical_holder.version)
		_technology_source_refs[str(prepared.source_key)] = source

func begin_scope_technology_phase(requester_id: int, scope: String, scope_id: String, binding: String, target_id: String, work_target: Dictionary = {}) -> Dictionary:
	var owner := _technology_scope_owner(scope, scope_id)
	var checked := _technology_scope_command(requester_id, scope, owner)
	if not checked.ok: return checked
	var raw: Dictionary = owner.get("technology", {})
	if not _scope_project_activation(raw): return Runtime.fail("UNIMPLEMENTED")
	if not Technology.valid_scope_record(raw, scope): return Runtime.fail("INVALID_TECHNOLOGY")
	var project := Technology.active_project(raw)
	if project.is_empty() or int(project.rules_version) != 2: return Runtime.fail("NO_TARGET")
	var phase := Technology.scope_next_phase(project, project.executor, raw.get("person_links", []))
	if phase.is_empty() or str(phase.binding) != binding: return Runtime.fail("STALE_PHASE")
	var token := {"scope": scope, "scope_id": _technology_scope_id(scope, owner, scope_id), "project_id": int(project.id), "epoch": int(raw.epoch),
		"purpose": str(project.purpose), "tech_id": str(project.tech_id), "phase_id": str(phase.id), "attempt": int(project.next_attempt),
		"person": project.executor.duplicate(), "binding": binding, "target_id": target_id, "materials": phase.materials.duplicate()}
	# Runtime owns the actual geometry/task/material transaction. It checks the
	# complete exact original cost, original worker and this bound candidate,
	# attaches only to that original task, then publishes this one attempt.
	return Runtime.begin_technology_operation(lab.terrain, token, false, work_target)

func stop_scope_technology(requester_id: int, scope: String, scope_id: String, permanent: bool = false) -> Dictionary:
	if permanent: return Runtime.fail("UNIMPLEMENTED", "原永久解除研究綁定尚須與已付目標入口同批接妥")
	var owner := _technology_scope_owner(scope, scope_id)
	var raw: Dictionary = owner.get("technology", {})
	if not Technology.valid_scope_record(raw, scope): return Runtime.fail("INVALID_TECHNOLOGY")
	var project := Technology.active_project(raw)
	if project.is_empty() or int(project.rules_version) != 2: return Runtime.fail("NO_TARGET")
	var duty := _technology_scope_duty(scope, owner)
	if requester_id != _technology_controlled() or not duty.ok or int(duty.get("decider", -1)) != requester_id: return Runtime.fail("NO_AUTHORITY")
	var executor_id := int(project.executor.person_id)
	var person := _person(executor_id)
	var token: Dictionary = {}
	for collection: Dictionary in [lab.terrain.site.get("features", {}), lab.terrain.site.get("vehicles", {})]:
		for target: Dictionary in collection.values():
			var attached: Dictionary = target.get("tech_trial", {})
			if attached.get("scope") == scope and attached.get("scope_id") == _technology_scope_id(scope, owner, scope_id) \
				and int(attached.get("project_id", -1)) == int(project.id) and attached.get("purpose") == project.purpose \
				and Technology.same_person_ref(attached.get("person", {}), project.executor, raw.get("person_links", [])):
				if not _technology_matching_original_task(person, attached): continue
				if not token.is_empty(): return Runtime.fail("CORRUPT_STATE", "同一原作業綁定多個科技目標")
				token = attached
	var check := _technology_scope_person(scope, owner, requester_id, true, token if requester_id == executor_id else {})
	if not check.ok: return check
	if not token.is_empty():
		var task_matches := _technology_matching_original_task(person, token)
		var released: Dictionary = Runtime.release_technology_operation(lab.terrain, token)
		if not released.ok: return released
		if task_matches:
			if person.body is Dictionary: lab.site_controller.work_team.cancel(executor_id)
			else:
				var task: Dictionary = lab.terrain.site.manual if person.owner == lab.character else lab.terrain.site.worker
				task.mode = "idle"
				task.target = ""
				task.progress = 0.0
	var job := job_for(executor_id)
	var job_token: Dictionary = job.get("nation_token", {})
	if not job_token.is_empty() and job_token.get("scope") == scope and job_token.get("scope_id") == _technology_scope_id(scope, owner, scope_id) \
		and int(job_token.get("project_id", -1)) == int(project.id) and job_token.get("purpose") == project.purpose: cancel(executor_id)
	elif scope == "family" and job.get("technology_family_id") == owner.get("family_id") \
		and int(job.get("technology_project", -1)) == int(project.id) and job.get("technology_purpose") == project.purpose: cancel(executor_id)
	owner.technology.active = 0
	return Runtime.ok("已停原研究；已付材料、成功階段及原目標進度保留")

func technology_phase_payment_candidate(token: Dictionary, materials: Dictionary, binding_prepared: Dictionary = {}, original_source: Dictionary = {}) -> Dictionary:
	if not Technology.material_equal(materials, token.get("materials", {})): return Runtime.fail("MATERIALS")
	var held: Dictionary = original_source
	if held.is_empty(): held = binding_prepared.get("original_source", {})
	var checked := _technology_phase_context(token, not binding_prepared.is_empty(), held.is_empty())
	if not checked.ok: return checked
	var source_record: Dictionary = checked.record
	if not binding_prepared.is_empty():
		if not is_same(binding_prepared.get("owner"), checked.owner) or not is_same(binding_prepared.get("record"), checked.record) \
			or not is_same(binding_prepared.get("site_state"), lab.terrain.site) or not Technology.valid_scope_record(binding_prepared.get("state"), str(token.scope)): return Runtime.fail("STALE_SOURCE")
		source_record = binding_prepared.state
	var source := {}
	if not held.is_empty():
		source = _technology_original_source_query(token, held)
		if not source.ok: return source
		var project := Technology.active_project(source_record)
		if project.budget.is_empty() or project.budget.status != "granted" or project.budget.holder != source.holder \
			or project.budget.grantor != source.grantor: return Runtime.fail("NO_BUDGET")
		for resource: String in project.budget.cap:
			if int(project.budget.cap[resource]) > int(source.cap.get(resource, 0)): return Runtime.fail("NO_BUDGET")
	var payment_id := JSON.stringify([_technology_site_id(), str(token.scope), str(token.scope_id), int(token.project_id), str(token.purpose), int(token.attempt), str(token.target_id)])
	var payment := {"payment_id": payment_id, "attempt": int(token.attempt), "phase_id": str(token.phase_id), "person": token.person.duplicate(), "materials": materials.duplicate(), "target_id": str(token.target_id)}
	var prepared := Technology.scope_payment_candidate(source_record, str(token.scope), payment)
	if not prepared.ok: return prepared
	return Runtime.ok("", {"owner": checked.owner, "record": checked.record, "state": prepared.state, "payment_id": payment_id, "site_state": lab.terrain.site,
		"original_source": source, "source_key": JSON.stringify([str(token.scope), str(token.scope_id), int(token.project_id)])})

func publish_phase_payment(prepared: Dictionary) -> void:
	# The original synchronous material owner commits its real transfer FIRST.
	# This failure-free tail only publishes its already checked scope candidate.
	prepared.owner.technology = prepared.state
	if not prepared.get("original_source", {}).is_empty():
		var source: Dictionary = prepared.original_source.duplicate()
		source.holder_version = int(source.physical_holder.version)
		_technology_source_refs[str(prepared.source_key)] = source

func technology_phase_receipt_candidate(token: Dictionary, original: Dictionary) -> Dictionary:
	var checked := _technology_paid_phase_context(token)
	if not checked.ok: return checked
	if original.get("site_id") != _technology_site_id() or original.get("target_id") != token.target_id \
		or original.get("binding") != token.binding or int(original.get("operator_id", -1)) != int(token.person.person_id) \
		or not original.get("id") is String or str(original.id).is_empty() \
		or not Technology.finite_number(original.get("work_seconds")): return Runtime.fail("INVALID_RECEIPT")
	var payment: Dictionary = {}
	for candidate: Dictionary in checked.project.budget.payments:
		if int(candidate.attempt) == int(token.attempt) and candidate.phase_id == token.phase_id and candidate.target_id == token.target_id \
			and Technology.same_person_ref(candidate.person, token.person) and Technology.material_equal(candidate.materials, original.get("materials", {})):
			payment = candidate
	if payment.is_empty(): return Runtime.fail("NO_PAYMENT")
	# This is the actual original operation's prospective completed transaction,
	# not an arbitrary caller-supplied output. Its true ledger, complete cycle,
	# named operator and original item sequence are rechecked before publication.
	var real_output: Dictionary = Runtime.technology_output_candidate(lab.terrain, token, original)
	if not real_output.ok: return real_output
	var receipt := {"site_id": _technology_site_id(), "person_id": int(token.person.person_id), "attempt": int(token.attempt), "phase_id": str(token.phase_id),
		"event_id": str(original.id), "work_seconds": float(original.work_seconds), "payment_id": str(payment.payment_id)}
	var prepared := Technology.scope_receipt_candidate(checked.record, str(token.scope), receipt)
	if not prepared.ok: return prepared
	var learned: Dictionary = {}
	if prepared.complete and str(token.scope) == "family":
		learned = Technology.learned_candidate(_body_get(checked.person, "technology"), str(token.tech_id))
		if learned.is_empty(): return Runtime.fail("INVALID_TECHNOLOGY")
	return Runtime.ok("", {"owner": checked.owner, "record": checked.record, "state": prepared.state, "person": checked.person, "person_candidate": learned, "complete": prepared.complete, "site_state": lab.terrain.site})

func publish_phase_receipt(prepared: Dictionary) -> void:
	prepared.owner.technology = prepared.state
	if not prepared.person_candidate.is_empty(): _body_set(prepared.person, "technology", prepared.person_candidate)

func _technology_original_source_valid(token: Dictionary, source: Dictionary) -> bool:
	return _technology_original_source_query(token, source).ok

func _technology_original_source_query(token: Dictionary, source: Dictionary) -> Dictionary:
	if source.get("kind") == "settlement_order": return _technology_settlement_source_query(token, source)
	var fields := ["ok", "code", "message", "kind", "holder", "source_site_id", "grantor", "cap", "spent", "physical_holder", "physical_cargo", "holder_version", "expected_refs"]
	if source.has("paid_witness"): fields.append("paid_witness")
	if not Technology.keys(source, fields) or not source.ok is bool or source.ok != true \
		or not source.code is String or not source.message is String or not source.kind is String or source.kind != "nation_order" or token.get("scope") != "nation" \
		or not source.holder is String or not source.holder.begins_with("nation-order:") or not source.source_site_id is String or source.source_site_id != _technology_site_id() \
		or not Technology.valid_ref(source.grantor) or source.grantor.site_id != _technology_site_id() \
		or not Technology.material_stack(source.cap) or not source.spent is Dictionary or not source.spent.is_empty() \
		or not source.physical_holder is Dictionary or not source.physical_cargo is Dictionary or not Technology.integer(source.holder_version) \
		or not Technology.keys(source.expected_refs, ["terrain", "site", "nation", "operations", "order", "holder", "cargo"]): return Runtime.fail("STALE_SOURCE")
	var technology_source_namespace: Variant = JSON.parse_string(source.holder.trim_prefix("nation-order:"))
	if not technology_source_namespace is Array or technology_source_namespace.size() != 3 or technology_source_namespace[0] != _technology_site_id() \
		or technology_source_namespace[1] != token.get("scope_id") or not technology_source_namespace[2] is String \
		or source.holder != "nation-order:" + JSON.stringify(technology_source_namespace): return Runtime.fail("STALE_SOURCE")
	if not has_method("nation_research_source_candidate"): return Runtime.fail("UNSUPPORTED")
	var actual: Dictionary = nation_research_source_candidate(token, str(technology_source_namespace[2]))
	if not actual.ok: return actual
	if source.has("paid_witness"):
		var witness: Variant = source.paid_witness
		if not witness is Dictionary or not is_same(witness.get("owner"), equipment_orders) \
			or not is_same(witness.get("order"), actual.expected_refs.order): return Runtime.fail("STALE_SOURCE")
		if witness.has("job"):
			if not witness.job is Dictionary or not has_method("nation_research_paid_source_candidate"): return Runtime.fail("STALE_SOURCE")
			actual = nation_research_paid_source_candidate(token, str(technology_source_namespace[2]), witness.job)
			if not actual.ok: return actual
		if not actual.has("paid_witness") or not Technology.keys(witness, actual.paid_witness.keys()): return Runtime.fail("STALE_SOURCE")
		for key: String in ["owner", "order", "job", "receipts"]:
			if witness.has(key) and not is_same(witness[key], actual.paid_witness[key]): return Runtime.fail("STALE_SOURCE")
		if witness.has("transfer"):
			if not witness.transfer is Dictionary: return Runtime.fail("STALE_SOURCE")
			var transfer: Dictionary = actual.paid_witness.transfer
			for key: String in ["nation_ref", "source", "source_cargo", "destination", "destination_cargo"]:
				if not is_same(witness.transfer.get(key), transfer.get(key)): return Runtime.fail("STALE_SOURCE")
			for key: String in ["source_version", "destination_version", "operations"]:
				if witness.transfer.get(key) != transfer.get(key): return Runtime.fail("STALE_SOURCE")
	for key: String in ["kind", "holder", "source_site_id", "grantor", "cap", "spent", "holder_version"]:
		if source[key] != actual[key]: return Runtime.fail("STALE_SOURCE")
	for key: String in ["physical_holder", "physical_cargo"]:
		if not is_same(source[key], actual[key]): return Runtime.fail("STALE_SOURCE")
	for key: String in ["terrain", "site", "nation", "operations", "order", "holder", "cargo"]:
		if not is_same(source.expected_refs[key], actual.expected_refs[key]): return Runtime.fail("STALE_SOURCE")
	if not is_same(actual.expected_refs.terrain, lab.terrain) or not is_same(actual.expected_refs.site, lab.terrain.site) \
		or not is_same(actual.expected_refs.nation, _technology_scope_owner("nation", str(token.get("scope_id", "")))): return Runtime.fail("STALE_SOURCE")
	return actual

# Append to ORIGINAL SitePersonActions. Integration points:
# _job_context: nation_administration -> _nation_administration_context(job).
# _commit: nation_administration -> _commit_nation_administration(job).
# work_requests: add nation_administration to admitted original kinds (raw).
# No second advance/clock/receipt save owner. Original shared collector,
# advance(), threats, cancellation and settle_after_contacts own these jobs.
# Core dependencies: technology_phase_binding_candidate gains second
# original_source, payment gains fourth original_source, phase_context gains
# third require_material_source. CORE_NATION_SOURCE_PATCH owns those replacements.

func _nation_original_order_context(nation_id: String, order_id: String, binding: String, completed: bool = false) -> Dictionary:
	if equipment_orders == null: return Runtime.fail("NO_TARGET")
	var nation: Dictionary = lab.terrain.site.get("equipment_nations", {}).get(nation_id, {})
	if not equipment_orders.valid_nation_operation_record(nation.get("technology_operations"), lab.terrain.site.item_definitions, {}): return Runtime.fail("CORRUPT_STATE")
	var order: Dictionary = nation.technology_operations.get("public_orders", {}).get(order_id, {})
	if order.is_empty() or order.scope_site_id != _technology_site_id() or order.scope_nation_id != nation_id \
		or order.status == "revoked" or not completed and order.status == "complete": return Runtime.fail("STALE_ORDER")
	var checked: Dictionary = equipment_orders._nation_operation_context(int(order.authorizer_id), nation_id,
		str(equipment_orders.PUBLIC_DUTIES[str(order.tech_id)]), str(order.tech_id), binding, true)
	if not checked.ok: return checked
	if order.status != "complete":
		checked = equipment_orders._public_context(nation_id, order_id, binding, true)
		if not checked.ok: return checked
	return Runtime.ok("", {"nation": nation, "operations": nation.technology_operations, "order": order})

# This is a pure projection of the original finite authorization and original
# Warehouse endpoint. Funding is not manufacture payment: physical_cargo is
# still consumed by the original material owner when that real job pays.

# APPEND; Runtime separately prepares the true source before a new binding.
func nation_research_source_candidate(token: Dictionary, order_id: String) -> Dictionary:
	if not Technology.keys(token, ["scope", "scope_id", "project_id", "epoch", "purpose", "tech_id", "phase_id", "attempt", "person", "binding", "target_id", "materials"]) \
		or token.scope != "nation" or not Technology.valid_ref(token.person) or not Technology.material_stack(token.materials) \
		or not Technology.integer(token.project_id, 1) or not Technology.integer(token.epoch, 1) or not Technology.integer(token.attempt, 1): return Runtime.fail("INVALID_TECHNOLOGY")
	if token.tech_id == "N01" and order_id.begins_with("procurement:"):
		return _nation_procurement_material_source(token, order_id.trim_prefix("procurement:"))
	if token.tech_id == "N05" and order_id.begins_with("production_"):
		var source := _nation_military_material_source(str(token.scope_id), order_id)
		if not source.ok: return source
		var nation: Dictionary = source.expected_refs.nation
		var order: Dictionary = source.expected_refs.order
		var project := Technology.active_project(nation.get("technology", {}))
		var phase := Technology.scope_next_phase(project, token.person)
		if project.is_empty() or int(nation.technology.epoch) != int(token.epoch) or int(project.id) != int(token.project_id) \
			or project.purpose != token.purpose or project.tech_id != "N05" or phase.get("id") != token.phase_id \
			or phase.get("binding") != "workshop_bow" or token.binding != "workshop_bow" \
			or not Technology.same_person_ref(project.executor, token.person) or int(order.operator_id) != int(token.person.person_id) \
			or token.target_id != "feature:" + str(order.feature_id) or not Technology.material_equal(token.materials, Runtime.RANGED_RECIPES.bow.cost): return Runtime.fail("STALE_PROJECT")
		return source
	var checked := _nation_original_order_context(str(token.get("scope_id", "")), order_id, str(token.get("binding", "")), true)
	if not checked.ok: return checked
	var order: Dictionary = checked.order
	if order.tech_id != token.get("tech_id") or int(order.project_id) != int(token.get("project_id", -1)) \
		or not order.payload.has("source") or not equipment_orders._public_source_paid(order): return Runtime.fail("NO_BUDGET")
	var project := Technology.active_project(checked.nation.technology)
	var phase := Technology.scope_next_phase(project, token.person)
	if project.is_empty() or int(checked.nation.technology.epoch) != int(token.epoch) or int(project.id) != int(token.project_id) or project.purpose != token.get("purpose") \
		or phase.get("id") != token.phase_id or phase.get("binding") != token.binding or not Technology.scope_phase_materials(token.materials, phase.get("materials", {})) \
		or not Technology.same_person_ref(project.executor, token.person): return Runtime.fail("STALE_PROJECT")
	var source: Dictionary = order.payload.source
	for resource: String in token.materials:
		if int(source.cap.get(resource, 0)) < int(token.materials[resource]) or int(source.spent.get(resource, 0)) < int(token.materials[resource]): return Runtime.fail("NO_BUDGET")
	var stock := SiteStockpiles.stock_endpoint(lab.terrain, str(order.payload.reserve_feature_id))
	if stock.is_empty(): return Runtime.fail("NO_SOURCE")
	var result := Runtime.ok("", {"kind": "nation_order", "holder": "nation-order:" + JSON.stringify([_technology_site_id(), str(token.scope_id), order_id]),
		"source_site_id": _technology_site_id(), "grantor": {"site_id": _technology_site_id(), "person_id": int(source.person_id)},
		"cap": source.cap.duplicate(), "spent": {}, "physical_holder": stock.holder, "physical_cargo": stock.cargo,
		"holder_version": int(stock.holder.version), "expected_refs": {"terrain": lab.terrain, "site": lab.terrain.site, "nation": checked.nation,
			"operations": checked.operations, "order": order, "holder": stock.holder, "cargo": stock.cargo}})
	if order.tech_id in ["N03", "N09"] and equipment_orders._public_order_complete(order):
		result.paid_witness = {"owner": equipment_orders, "order": order, "receipts": order.receipts}
	return result

# Completed original grain transfers are paid witnesses for the subsequent
# actual 300s administration. Their stored 0s never supplies the work time.
func nation_research_paid_source_candidate(token: Dictionary, order_id: String, original_job: Dictionary) -> Dictionary:
	var source := nation_research_source_candidate(token, order_id)
	if not source.ok: return source
	if not is_same(_jobs.get(str(int(original_job.get("executor_id", -1))), {}), original_job) \
		or not is_same(original_job.get("terrain"), lab.terrain) or not is_same(original_job.get("site_state"), lab.terrain.site) \
		or int(original_job.executor_id) != int(token.person.person_id): return Runtime.fail("STALE_SOURCE")
	var order: Dictionary = source.expected_refs.order
	if original_job.get("kind") == "nation_administration":
		if original_job.get("nation_order_id") != order_id or original_job.get("nation_id") != token.scope_id \
			or order.tech_id not in ["N03", "N09"] or not equipment_orders._public_order_complete(order): return Runtime.fail("NO_PAYMENT")
		source.paid_witness = {"owner": equipment_orders, "order": order, "receipts": order.receipts, "job": original_job}
		return source
	if original_job.get("kind") == "technology_lesson":
		if original_job.get("nation_course_id") != order_id or original_job.get("nation_course_nation") != token.scope_id \
			or order.tech_id != "N07": return Runtime.fail("NO_PAYMENT")
		var checked := _technology_lesson_context(original_job)
		if not checked.ok: return checked
		var student := _person(int(original_job.target_id))
		var learned := Technology.learned_candidate(_body_get(student, "technology"), str(order.payload.skill_id))
		var transfer: Dictionary = equipment_orders.prepare_funded_course_completion(str(token.scope_id), order_id, original_job, learned)
		if not transfer.ok: return transfer
		source.paid_witness = {"owner": equipment_orders, "order": order, "job": original_job, "transfer": transfer}
		return source
	return Runtime.fail("NO_PAYMENT")

func _nation_administration_requirement(context: Dictionary, binding: String) -> Dictionary:
	var order: Dictionary = context.order
	var payload: Dictionary = order.payload
	match str(order.tech_id):
		"N02", "N10":
			if binding != ("labor_register" if order.tech_id == "N02" else "mandate") or not order.receipts.is_empty(): return Runtime.fail("STALE_ORDER")
			if order.tech_id == "N10" and not equipment_orders._mandate_effective(order): return Runtime.fail("EXPIRED_MANDATE")
			return Runtime.ok("", {"items": []})
		"N03", "N09", "N12":
			if binding != ("aid_order" if order.tech_id == "N03" else ("tax" if order.tech_id == "N09" else "fleet")) \
				or order.status != "complete" or not equipment_orders._public_order_complete(order): return Runtime.fail("INCOMPLETE_OPERATION")
			return Runtime.ok("", {"items": []})
		"N11":
			if binding != "arsenal" or order.receipts.size() != 1 or payload.target_id.is_empty(): return Runtime.fail("INCOMPLETE_OPERATION")
			if payload.route == "armor":
				var item_id := str(order.receipts[0].item_ids[0])
				if str(lab.terrain.site.item_records.get(item_id, {}).get("definition", "")) != "armor:armor_iron_01": return Runtime.fail("NO_PRODUCT")
				return Runtime.ok("", {"items": [item_id]})
			var product: Dictionary = lab.terrain.site.get("vehicles", {}).get(str(payload.target_id).trim_prefix("vehicle:"), {})
			if product.is_empty() or str(product.get("kind", "")) != "ballista" or str(product.get("phase", "")) != "ready": return Runtime.fail("NO_PRODUCT")
			return Runtime.ok("", {"items": []})
	return Runtime.fail("INVALID", "本入口只完成具名原行政工作，制造／授課仍沿其原作業")

func _nation_phase_token(nation_id: String, order_id: String, binding: String, target: String) -> Dictionary:
	var checked := _nation_original_order_context(nation_id, order_id, binding, true)
	if not checked.ok: return checked
	if Technology.scope_known(checked.nation.technology, str(checked.order.tech_id)): return Runtime.ok("", {"token": {}})
	var record: Dictionary = checked.nation.technology
	var project := Technology.active_project(record)
	var phase := Technology.scope_next_phase(project, project.get("executor", {}))
	if project.is_empty() or int(project.id) != int(checked.order.project_id) or project.tech_id != checked.order.tech_id \
		or phase.get("binding") != binding: return Runtime.fail("STALE_PHASE")
	# A cancelled job keeps its paid attempt: payments are never refunded, so a
	# paid phase on this target without its receipt resumes on that attempt.
	var attempt := int(project.next_attempt)
	var paid := false
	for payment: Dictionary in project.get("budget", {}).get("payments", []):
		if str(payment.get("phase_id")) != str(phase.id) or str(payment.get("target_id")) != target or payment.get("person") != project.executor: continue
		var receipted := false
		for receipt: Dictionary in project.get("receipts", []):
			if str(receipt.get("payment_id", "")) == str(payment.payment_id) or int(receipt.get("attempt", -1)) == int(payment.attempt): receipted = true
		if not receipted:
			attempt = int(payment.attempt)
			paid = true
	return Runtime.ok("", {"paid": paid, "token": {"scope": "nation", "scope_id": nation_id, "project_id": int(project.id), "epoch": int(record.epoch),
		"purpose": str(project.purpose), "tech_id": str(project.tech_id), "phase_id": str(phase.id), "attempt": attempt,
		"person": project.executor.duplicate(), "binding": binding, "target_id": target, "materials": phase.materials.duplicate()}})

func begin_nation_administration(requester_id: int, nation_id: String, order_id: String, binding: String) -> Dictionary:
	if requester_id != _technology_controlled(): return Runtime.fail("NO_AUTHORITY")
	if binding in ["procurement", "workshop_certificate"]: return begin_nation_original_administration(requester_id, nation_id, order_id, binding)
	var checked := _nation_original_order_context(nation_id, order_id, binding, true)
	if not checked.ok: return checked
	if checked.order.tech_id in ["N03", "N09", "N12"] and Technology.scope_known(checked.nation.technology, str(checked.order.tech_id)):
		return Runtime.fail("NO_CHANGE", "本原操作已完成；已知制度不重開首次300秒研究工作")
	if not equipment_orders._nation_duty_ok(requester_id, checked.nation, str(equipment_orders.PUBLIC_DUTIES[str(checked.order.tech_id)])): return Runtime.fail("NO_AUTHORITY")
	var required := _nation_administration_requirement(checked, binding)
	if not required.ok: return required
	var target: String = equipment_orders._public_order_target(checked.order, order_id)
	if checked.order.tech_id == "N11": target = str(checked.order.payload.target_id)
	var selection := _nation_phase_token(nation_id, order_id, binding, target)
	if not selection.ok: return selection
	var token: Dictionary = selection.token
	var identity := requester_id if token.is_empty() else int(token.person.person_id)
	# A known N11 has no research token: its acceptance worker is the order's named
	# operator, as in the research case. Requester authority was checked above.
	if token.is_empty() and checked.order.tech_id == "N11": identity = int(checked.order.payload.operator_id)
	if checked.order.tech_id == "N11" and identity != int(checked.order.payload.operator_id): return Runtime.fail("NO_WORKER")
	var ready := _technology_scope_person("nation", checked.nation, identity)
	if not ready.ok: return ready
	var binding_prepared := {}
	var payment_prepared := {}
	if not token.is_empty() and bool(selection.get("paid", false)):
		# Resume of a paid attempt: its binding and payment already exist.
		var resumed := _technology_paid_phase_context(token)
		if not resumed.ok: return resumed
	elif not token.is_empty():
		var source := {} if token.materials.is_empty() else nation_research_source_candidate(token, order_id)
		if not source.is_empty() and not source.ok: return source
		binding_prepared = technology_phase_binding_candidate(token, source)
		if not binding_prepared.ok: return binding_prepared
		payment_prepared = technology_phase_payment_candidate(token, token.materials, binding_prepared, source)
		if not payment_prepared.ok: return payment_prepared
	var executor: Dictionary = ready.person
	var job := _new_job(executor, "nation_administration", 0)
	job.merge({"duration": 300.0, "terrain": lab.terrain, "site_state": lab.terrain.site, "nation_id": nation_id, "nation_order_id": order_id,
		"nation_ref": checked.nation, "nation_order_ref": checked.order, "executor_body": executor.body, "nation_binding": binding,
		"nation_target": target, "nation_items": required.items.duplicate(), "nation_token": token,
		"nation_event_id": equipment_orders._public_event_id(checked.order, order_id, "administration", binding)})
	_jobs[str(identity)] = job
	if not payment_prepared.is_empty(): publish_phase_payment(payment_prepared)
	return Runtime.ok("原行政作業開始；真移交／船步已完成才可記制度工作", {"seconds": 300.0})

func _nation_administration_context(job: Dictionary) -> Dictionary:
	if job.has("nation_original_kind"): return _nation_original_administration_context(job)
	if not is_same(_jobs.get(str(int(job.executor_id)), {}), job) or not is_same(lab.terrain, job.terrain) \
		or not is_same(lab.terrain.site, job.site_state): return Runtime.fail("STALE_SOURCE")
	var checked := _nation_original_order_context(str(job.nation_id), str(job.nation_order_id), str(job.nation_binding), true)
	if not checked.ok: return checked
	if not is_same(checked.nation, job.nation_ref) or not is_same(checked.order, job.nation_order_ref): return Runtime.fail("STALE_ORDER")
	var executor := _technology_scope_person("nation", checked.nation, int(job.executor_id), true)
	if not executor.ok: return executor
	if not is_same(executor.person.body, job.executor_body) or int(executor.person.hit) != int(job.executor_hit) \
		or lab.terrain.index(executor.person.cell) != int(job.executor_cell): return Runtime.fail("INTERRUPTED")
	var required := _nation_administration_requirement(checked, str(job.nation_binding))
	if not required.ok: return required
	if required.items != job.nation_items: return Runtime.fail("STALE_PRODUCT")
	if not job.nation_token.is_empty():
		var phase := _technology_phase_context(job.nation_token, false, false)
		if not phase.ok: return phase
	return Runtime.ok("", {"context": checked, "person": executor.person})

func _nation_administration_event(job: Dictionary) -> Dictionary:
	return {"id": str(job.nation_event_id), "site_id": _technology_site_id(), "target_id": str(job.nation_target),
		"operator_id": int(job.executor_id), "binding": str(job.nation_binding), "work_seconds": float(job.duration),
		"item_ids": job.nation_items.duplicate(), "outputs": {}, "materials": job.nation_token.get("materials", {}).duplicate()}

func _commit_nation_administration(job: Dictionary) -> Dictionary:
	if job.has("nation_original_kind"): return _commit_nation_original_administration(job)
	var checked := _nation_administration_context(job)
	if not checked.ok: return checked
	if float(job.elapsed) + 0.00000001 < float(job.duration): return Runtime.fail("INCOMPLETE")
	var event := _nation_administration_event(job)
	var order_prepared := {}
	if checked.context.order.tech_id in ["N02", "N10", "N11"]:
		order_prepared = equipment_orders.prepare_public_owner_receipt(str(job.nation_id), str(job.nation_order_id), str(job.nation_binding), str(job.nation_target), str(event.id))
		if not order_prepared.ok: return order_prepared
	var phase_prepared := {}
	if not job.nation_token.is_empty():
		phase_prepared = nation_scope_receipt_candidate(job.nation_token, event)
		if not phase_prepared.ok: return phase_prepared
	# No callback/decision follows this original PA completion tail.
	if not order_prepared.is_empty(): equipment_orders.publish_public_owner_receipt(order_prepared)
	if not phase_prepared.is_empty(): publish_phase_receipt(phase_prepared)
	return Runtime.ok("原300秒行政工作與真操作證據同次完成")

func nation_scope_receipt_candidate(token: Dictionary, event: Dictionary, payment_prepared: Dictionary = {}) -> Dictionary:
	if not Technology.keys(event, ["id", "site_id", "target_id", "operator_id", "binding", "work_seconds", "item_ids", "outputs", "materials"]) \
		or event.site_id != _technology_site_id() or event.target_id != token.get("target_id") or event.binding != token.get("binding") \
		or not Technology.valid_ref(token.get("person")) or not Technology.integer(event.operator_id, 1) \
		or int(event.operator_id) != int(token.person.person_id) or not Technology.material_equal(event.materials, token.get("materials", {})): return Runtime.fail("INVALID_RECEIPT")
	var actual := nation_original_receipt_query(str(token.get("binding", "")), str(token.get("target_id", "")), str(event.get("id", "")))
	if not actual.ok or actual.receipt != _nation_receipt_projection(event) or actual.get("token", {}) != token: return Runtime.fail("INVALID_RECEIPT")
	var checked := _technology_phase_context(token, false, false)
	if not checked.ok: return checked
	var source: Dictionary = checked.record
	if not payment_prepared.is_empty():
		if not is_same(payment_prepared.get("owner"), checked.owner) or not is_same(payment_prepared.get("record"), checked.record) \
			or not is_same(payment_prepared.get("site_state"), lab.terrain.site): return Runtime.fail("STALE_SOURCE")
		source = payment_prepared.state
	var project := Technology.active_project(source)
	var payment_id := ""
	for payment: Dictionary in project.budget.get("payments", []):
		if int(payment.attempt) == int(token.attempt) and payment.phase_id == token.phase_id and payment.target_id == token.target_id \
			and Technology.same_person_ref(payment.person, token.person) and Technology.material_equal(payment.materials, event.get("materials", {})): payment_id = str(payment.payment_id)
	if payment_id.is_empty(): return Runtime.fail("NO_PAYMENT")
	var receipt := {"site_id": _technology_site_id(), "person_id": int(token.person.person_id), "attempt": int(token.attempt), "phase_id": str(token.phase_id),
		"event_id": str(event.id), "work_seconds": float(event.work_seconds), "payment_id": payment_id}
	var candidate := Technology.scope_receipt_candidate(source, "nation", receipt)
	if not candidate.ok: return candidate
	return Runtime.ok("", {"owner": checked.owner, "record": checked.record, "state": candidate.state, "person": checked.person,
		"person_candidate": {}, "complete": candidate.complete, "site_state": lab.terrain.site})

func _nation_receipt_projection(event: Dictionary) -> Dictionary:
	return {"id": event.get("id"), "site_id": event.get("site_id"), "target_id": event.get("target_id"), "operator_id": event.get("operator_id"),
		"binding": event.get("binding"), "work_seconds": event.get("work_seconds"), "item_ids": event.get("item_ids")}

# Pure current/prospective true-owner lookup. Finished jobs are cleared normally;
# accepted original Nops retains bounded history, not a second job/event ledger.
func nation_original_receipt_query(binding: String, target: String, event_id: String) -> Dictionary:
	if binding == "public_route" and lab.site_controller != null and lab.site_controller.region_slot != null:
		return lab.site_controller.region_slot.region_nation_route_receipt(lab, target, event_id)
	for job: Dictionary in _jobs.values():
		if job.get("kind") == "equipment" and job.has("nation_issue_token") and binding == "issue_bow" \
			and job.nation_issue_token.target_id == target and job.nation_issue_event_id == event_id:
			return nation_military_issue_receipt_query(job.nation_issue_token, _nation_military_issue_event(job))
		if job.get("kind") == "technology_lesson" and job.has("nation_course_id"):
			var checked := _technology_lesson_context(job)
			if not checked.ok: continue
			var order_context := _nation_original_order_context(str(job.nation_course_nation), str(job.nation_course_id), "funded_course")
			if not order_context.ok: continue
			var wanted: String = equipment_orders._public_event_id(order_context.order, str(job.nation_course_id), "lesson", str(int(job.target_id)))
			if binding != "funded_course" or target != "person:" + str(int(job.target_id)) or event_id != wanted: continue
			var student := _person(int(job.target_id))
			var learned := Technology.learned_candidate(_body_get(student, "technology"), str(order_context.order.payload.skill_id))
			var transfer: Dictionary = equipment_orders.prepare_funded_course_completion(str(job.nation_course_nation), str(job.nation_course_id), job, learned)
			if not transfer.ok: return transfer
			return Runtime.ok("", {"receipt": {"id": wanted, "site_id": _technology_site_id(), "target_id": target, "operator_id": int(job.executor_id),
				"binding": binding, "work_seconds": float(job.duration), "item_ids": []}, "token": job.get("nation_course_token", {})})
		if job.get("kind") == "nation_administration" and job.get("nation_event_id") == event_id \
			and job.get("nation_binding") == binding and job.get("nation_target") == target:
			var checked := _nation_administration_context(job)
			if not checked.ok: return checked
			if float(job.elapsed) + 0.00000001 < float(job.duration): return Runtime.fail("INCOMPLETE")
			return Runtime.ok("", {"receipt": _nation_receipt_projection(_nation_administration_event(job)), "token": job.nation_token})
	var record: Dictionary = {}
	if target.begins_with("feature:"): record = lab.terrain.site.get("features", {}).get(target.trim_prefix("feature:"), {})
	elif target.begins_with("vehicle:"): record = lab.terrain.site.get("vehicles", {}).get(target.trim_prefix("vehicle:"), {})
	var raw_token: Variant = record.get("tech_trial", {})
	var raw_ledger: Variant = record.get("tech_batch", {})
	if not raw_token is Dictionary or not raw_ledger is Dictionary: return Runtime.fail("NO_RECEIPT")
	var token: Dictionary = raw_token
	var ledger: Dictionary = raw_ledger
	if ledger.is_empty() or ledger.get("payment_id") != event_id or ledger.get("token") != token \
		or not Technology.integer(ledger.get("operator_id"), 1) or not Technology.finite_number(ledger.get("work_seconds")) \
		or not Technology.material_stack(ledger.get("materials")): return Runtime.fail("NO_RECEIPT")
	if token.is_empty():
		if not Technology.keys(record.get("technology_order"), ["nation_id", "order_id"]): return Runtime.fail("NO_RECEIPT")
	elif token.get("binding") != binding or token.get("target_id") != target: return Runtime.fail("NO_RECEIPT")
	var items: Array = []
	var outputs: Dictionary = {}
	if target.begins_with("feature:") and str(record.get("stage", "")) == "complete":
		var definition := Runtime.feature_recipe(record)
		outputs = definition.get("output", {}).duplicate()
		for index: int in range(definition.get("output_items", []).size()): items.append(str(int(lab.terrain.site.next_item) + index))
	var event := {"id": event_id, "site_id": _technology_site_id(), "target_id": target, "operator_id": int(ledger.operator_id), "binding": binding,
		"work_seconds": float(ledger.work_seconds), "item_ids": items, "outputs": outputs, "materials": ledger.materials.duplicate()}
	var checked: Dictionary = Runtime.technology_public_output_candidate(lab.terrain, record, event) if token.is_empty() \
		else Runtime.technology_output_candidate(lab.terrain, token, event)
	if not checked.ok: return checked
	var receipt := _nation_receipt_projection(event)
	# An iron_armor receipt carries the batch's effective seconds as recorded now.
	if binding == "iron_armor" and ledger.has("effective_seconds"): receipt["effective_seconds"] = float(ledger.effective_seconds)
	return Runtime.ok("", {"receipt": receipt, "token": token})

func begin_nation_funded_course(nation_id: String, order_id: String, teacher_id: int, student_id: int, skill_id: String) -> Dictionary:
	var checked := _nation_original_order_context(nation_id, order_id, "funded_course")
	if not checked.ok: return checked
	if checked.order.tech_id != "N07" or teacher_id != int(checked.order.payload.teacher_id) \
		or not checked.order.payload.student_ids.has(student_id) or skill_id != checked.order.payload.skill_id \
		or not equipment_orders._public_source_paid(checked.order): return Runtime.fail("STALE_COURSE")
	var selection := _nation_phase_token(nation_id, order_id, "funded_course", "person:" + str(student_id))
	if not selection.ok: return selection
	var token: Dictionary = selection.token
	var binding_prepared := {}
	if not token.is_empty():
		if int(token.person.person_id) != teacher_id: return Runtime.fail("NO_TEACHER")
		var source := nation_research_source_candidate(token, order_id)
		if not source.ok: return source
		binding_prepared = technology_phase_binding_candidate(token, source)
		if not binding_prepared.ok: return binding_prepared
	var begun := begin_technology_lesson(_technology_controlled(), teacher_id, student_id, skill_id)
	if not begun.ok: return begun
	var job: Dictionary = _jobs[str(teacher_id)]
	job.merge({"nation_course_nation": nation_id, "nation_course_id": order_id, "nation_course_token": token})
	if not binding_prepared.is_empty(): publish_phase_binding(binding_prepared)
	return begun

# _commit_technology_lesson calls after its family/native learned candidates,
# BEFORE either family or person changes. Once ALL candidates pass, call original
# commit_funded_course_payment first, then publish original family/person and
# phase in the same failure-free tail. An ordinary course returns no funding.
func prepare_nation_funded_lesson(job: Dictionary, learned_person_candidate: Dictionary) -> Dictionary:
	if not job.has("nation_course_id"): return Runtime.ok("", {"payment": {}, "phase": {}})
	var funding: Dictionary = equipment_orders.prepare_funded_course_completion(str(job.nation_course_nation), str(job.nation_course_id), job, learned_person_candidate)
	if not funding.ok: return funding
	var phase := {}
	var token: Dictionary = job.get("nation_course_token", {})
	if not token.is_empty():
		var source := nation_research_paid_source_candidate(token, str(job.nation_course_id), job)
		if not source.ok: return source
		var payment := technology_phase_payment_candidate(token, token.materials, {}, source)
		if not payment.ok: return payment
		var order: Dictionary = source.expected_refs.order
		var event := {"id": equipment_orders._public_event_id(order, str(job.nation_course_id), "lesson", str(int(job.target_id))),
			"site_id": _technology_site_id(), "target_id": "person:" + str(int(job.target_id)), "operator_id": int(job.executor_id),
			"binding": "funded_course", "work_seconds": float(job.duration), "item_ids": [], "outputs": {}, "materials": {"grain": 2}}
		phase = nation_scope_receipt_candidate(token, event, payment)
		if not phase.ok: return phase
	return Runtime.ok("", {"payment": funding, "phase": phase})


func _commit_scope_ranged_craft(job: Dictionary) -> Dictionary:
	var token: Dictionary = job.technology_scope_token
	var checked := _scope_ranged_craft_guard(int(job.executor_id), token)
	if not checked.ok: return checked
	var payment := technology_phase_payment_candidate(token, token.materials)
	if not payment.ok: return payment
	var event_id := str(token.tech_id) + ":ranged:" + JSON.stringify([_technology_site_id(), int(token.project_id), int(token.attempt), str(token.binding)])
	var completed := _prepare_scope_phase_completion(token, payment, event_id, float(job.duration))
	if not completed.ok: return completed
	# All current owner/phase/person/material/output candidates precede the
	# original synchronous real stack debit+output. No later rejecting callback.
	var real := Runtime.ranged_craft(lab.terrain, str(job.recipe), int(job.executor_id), false, token)
	if not real.ok: return real
	publish_phase_receipt(completed)
	return real

func _scope_ranged_job_context(job: Dictionary) -> Dictionary:
	var token: Dictionary = job.get("technology_scope_token", {})
	var context := _technology_phase_context(token, false)
	if not context.ok: return context
	var recipe := _scope_ranged_recipe(token)
	if token.get("tech_id") == "F08" and (context.phase.get("items") != ["weapon:crossbow_01"] or context.phase.get("outputs") != {} or float(context.phase.get("seconds", -1.0)) != 180.0): return Runtime.fail("STALE_PHASE")
	if job.kind != "ranged_craft" or recipe.is_empty() \
		or int(job.executor_id) != int(token.person.person_id) or job.recipe != recipe or not is_same(job.get("technology_executor_body"), context.person.body) \
		or not is_same(job.get("technology_executor_owner"), context.person.owner) or not is_same(job.get("executor_holder"), context.person.holder) \
		or not is_same(job.get("executor_cargo"), context.person.cargo) or not is_same(job.get("depot_holder"), lab.terrain.site.depot_items) \
		or not is_same(job.get("depot_stock"), lab.terrain.site.inventory) or not Technology.finite_number(job.elapsed) \
		or float(job.elapsed) > float(job.duration) or float(job.duration) != float(Runtime.RANGED_RECIPES[str(job.recipe)].duration) \
		or not Technology.material_equal(token.materials, Runtime.RANGED_RECIPES[str(job.recipe)].cost): return Runtime.fail("STALE_SOURCE")
	return context

func _scope_ranged_recipe(token: Dictionary) -> String:
	if not Runtime._technology_trial_shape(token, lab.terrain) or TechnologyCatalog.get_node(str(token.get("tech_id", ""))).get("enabled") != true: return ""
	var recipe := ""
	if token.scope == "family" and token.tech_id == "F08" and token.binding == "crossbow" and token.target_id == "ranged:" + str(int(token.person.person_id)):
		recipe = "crossbow"
	elif token.scope == "family" and token.tech_id == "F15" and token.binding in ["fire_arrow", "fire_pot"] and token.target_id == "ranged:" + str(int(token.person.person_id)):
		recipe = str(token.binding)
	elif token.scope == "settlement" and token.tech_id == "S08" and token.binding == "spares" and token.target_id == "depot": recipe = "ballista_spares"
	if recipe.is_empty() or not Runtime.RANGED_RECIPES.has(recipe) or not Technology.material_equal(token.materials, Runtime.RANGED_RECIPES[recipe].cost): return ""
	return recipe

func begin_scope_ranged_craft(token: Dictionary, recipe: String, preview: bool = false) -> Dictionary:
	var identity := int(token.get("person", {}).get("person_id", 0))
	if recipe != _scope_ranged_recipe(token) or recipe.is_empty(): return Runtime.fail("INVALID_TECHNOLOGY")
	var held := technology_phase_binding_candidate(token)
	if not held.ok: return held
	if is_busy(identity): return Runtime.fail("BUSY")
	var person := _person(identity)
	var checked := _ranged_craft_context(person)
	if not checked.ok: return checked
	checked = Runtime.ranged_craft(lab.terrain, recipe, identity, true, token)
	if not checked.ok or preview: return checked
	var begun := begin_ranged_craft(identity, recipe, token)
	if not begun.ok: return begun
	var job: Dictionary = _jobs[_job_key_for(identity)]
	job.merge({"technology_scope_token": token, "technology_executor_body": person.body, "technology_executor_owner": person.owner})
	publish_phase_binding(held)
	return begun

func begin_fire_pot_shot_phase(token: Dictionary, target: Dictionary, preview: bool = false) -> Dictionary:
	var checked := _fire_pot_shot_phase_context(token, true)
	if not checked.ok: return checked
	if int(checked.project.budget.spent.get("fire_pot", 0)) + 1 > int(checked.project.budget.cap.get("fire_pot", 0)): return Runtime.fail("BUDGET_EXCEEDED")
	var held := technology_phase_binding_candidate(token)
	if not held.ok: return held
	var vehicle: Dictionary = checked.vehicle
	if not vehicle.action.is_empty() or not vehicle.move.is_empty() or int(vehicle.cargo.get("fire_pot", 0)) < 1: return Runtime.fail("BUSY")
	var aim: Dictionary = lab.siege_fire_preview(vehicle, target, true)
	if not aim.ok: return aim
	if preview: return Runtime.ok("", {"token": token, "target_id": token.target_id})
	# Actual source captain authorization remains mandatory at the original
	# public order entry; the research decider alone cannot borrow another crew.
	var order: Dictionary = lab.site_controller.vehicles.order_siege(str(vehicle.id), "attack", target, _technology_controlled(), false, "fire_pot", int(token.person.person_id), token)
	if not order.ok: return order
	publish_phase_binding(held)
	return order

func begin_settlement_food_work(requester_id: int, settlement_id: String, order_id: String, preview: bool = false) -> Dictionary:
	var checked := Runtime.settlement_food_work_preflight(lab.terrain, settlement_id, order_id, "food_order")
	if not checked.ok: return checked
	if requester_id != _technology_controlled() or requester_id != Settlement.head_executor(lab): return Runtime.fail("NO_AUTHORITY")
	if checked.order.payload.stage != "arrived": return Runtime.fail("WAITING", "真持糧人尚未交到原倉庫")
	if settlement_food_own_job(checked.person, checked.order): return Runtime.ok("原到貨驗證作業已存在", {"duplicate": true})
	if not checked.order.payload.token.is_empty():
		var phase := _technology_paid_phase_context(checked.order.payload.token)
		if not phase.ok: return phase
	var prepared := prepare_settlement_food_work(checked)
	if not prepared.ok: return prepared
	if preview: return Runtime.ok("真已到貨作業可續作", {"remaining": 300.0 - float(prepared.job.elapsed)})
	publish_settlement_food_work(prepared)
	return Runtime.ok("沿原已付到貨進度續作；不重扣來源", {"remaining": 300.0 - float(prepared.job.elapsed)})

func _nation_procurement_material_source(token: Dictionary, spec_id: String) -> Dictionary:
	if token.get("tech_id") != "N01" or token.get("scope") != "nation" or token.get("binding") != "procurement" \
		or not Technology.valid_ref(token.get("person")) or not Technology.material_equal(token.get("materials", {}), {"wood": 2, "grain": 2}): return Runtime.fail("INVALID_TECHNOLOGY")
	var nation: Dictionary = _technology_scope_owner("nation", str(token.scope_id))
	var operations: Dictionary = nation.get("technology_operations", {})
	var spec: Dictionary = operations.get("specs", {}).get(spec_id, {})
	if spec.is_empty() or token.target_id != "nation-procurement:" + JSON.stringify([_technology_site_id(), str(token.scope_id), spec_id]) \
		or not equipment_orders.valid_nation_operation_record(operations, lab.terrain.site.item_definitions, {}): return Runtime.fail("STALE_SOURCE")
	var duty: Dictionary = equipment_orders._nation_operation_context(int(spec.authorizer_id), str(token.scope_id), "nation.procurement", "N01", "procurement", true)
	if not duty.ok: return duty
	var context := _technology_phase_context(token, not spec.has("tech_trial"), false)
	if not context.ok: return context
	if spec.has("tech_trial") and spec.tech_trial != token or not spec.has("tech_trial") and not spec.receipts.is_empty(): return Runtime.fail("BOUND_SOURCE")
	if int(token.person.person_id) != _technology_controlled() or int(spec.authorizer_id) != int(token.person.person_id) \
		or not spec.items.is_empty() or spec.resources.keys().size() != 2: return Runtime.fail("NO_AUTHORITY")
	for resource: String in ["wood", "grain"]:
		if not spec.resources.has(resource) or int(spec.resources[resource].total) != 2 or int(spec.resources[resource].batch) > 2: return Runtime.fail("NO_BUDGET")
	var person := _person(int(token.person.person_id))
	if person.is_empty() or str(person.holder.holder) != "person:" + str(int(token.person.person_id)): return Runtime.fail("STALE_SOURCE")
	return Runtime.ok("", {"kind": "nation_order", "holder": "nation-order:" + JSON.stringify([_technology_site_id(), str(token.scope_id), "procurement:" + spec_id]),
		"source_site_id": _technology_site_id(), "grantor": token.person.duplicate(), "cap": {"wood": 2, "grain": 2}, "spent": {},
		"physical_holder": person.holder, "physical_cargo": person.cargo, "holder_version": int(person.holder.version),
		"expected_refs": {"terrain": lab.terrain, "site": lab.terrain.site, "nation": nation, "operations": operations, "order": spec, "holder": person.holder, "cargo": person.cargo}})

func prepare_nation_procurement_delivery(nation_id: String, spec_id: String, next_spec: Dictionary, transfer: Dictionary) -> Dictionary:
	var nation: Dictionary = _technology_scope_owner("nation", nation_id)
	if Technology.scope_known(nation.get("technology", {}), "N01"): return Runtime.ok("", {"binding": {}, "payment": {}, "job": {}})
	var spec: Dictionary = nation.get("technology_operations", {}).get("specs", {}).get(spec_id, {})
	if spec.is_empty() or not Runtime.validate_prepared_item_transfer(transfer).ok: return Runtime.fail("STALE_SOURCE")
	var target := "nation-procurement:" + JSON.stringify([_technology_site_id(), nation_id, spec_id])
	var selection := _nation_original_research_token(nation_id, spec_id, "N01", "procurement", target, spec.get("tech_trial", {}))
	if not selection.ok or selection.token.is_empty(): return selection if not selection.ok else Runtime.fail("STALE_PROJECT")
	var token: Dictionary = selection.token
	var ready := _technology_scope_person("nation", nation, int(token.person.person_id))
	if not ready.ok: return ready
	var source := _nation_procurement_material_source(token, spec_id)
	if not source.ok: return source
	if not is_same(transfer.get("source"), source.physical_holder) or not is_same(transfer.get("source_cargo"), source.physical_cargo) \
		or not transfer.get("selected", {}).is_empty() or not Technology.material_equal(transfer.get("resources", {}), {"wood": 1, "grain": 1}) \
		or next_spec.receipts.size() != spec.receipts.size() + 1 \
		or next_spec.receipts.size() > 2 or next_spec.receipts[-1].source_person_id != token.person.person_id \
		or not Technology.material_equal(next_spec.receipts[-1].resources, {"wood": 1, "grain": 1}): return Runtime.fail("INVALID_DELIVERY", "首次研究須兩次本原人各交真木1／糧1")
	var destination: Dictionary = SiteStockpiles.stock_endpoint(lab.terrain, str(spec.destination_feature_id))
	if destination.is_empty() or not is_same(transfer.get("destination"), destination.holder) or not is_same(transfer.get("destination_cargo"), destination.cargo): return Runtime.fail("STALE_SOURCE")
	var binding := {}
	if not spec.has("tech_trial"):
		binding = technology_phase_binding_candidate(token, source)
		if not binding.ok: return binding
		next_spec.tech_trial = token
	var payment := {}
	var job := {}
	if next_spec.receipts.size() == 2:
		for receipt: Dictionary in next_spec.receipts:
			if int(receipt.source_person_id) != int(token.person.person_id) or not Technology.material_equal(receipt.resources, {"wood": 1, "grain": 1}) or not receipt.items.is_empty(): return Runtime.fail("INVALID_RECEIPT")
		payment = technology_phase_payment_candidate(token, token.materials, binding, source)
		if not payment.ok: return payment
		job = _nation_original_administration_job(ready.person, nation, spec, "procurement", spec_id, token, next_spec)
	return Runtime.ok("", {"binding": binding, "payment": payment, "job": job})

func prepare_nation_workshop_administration(nation_id: String, certificate_id: String, certificate: Dictionary) -> Dictionary:
	var nation: Dictionary = _technology_scope_owner("nation", nation_id)
	if Technology.scope_known(nation.get("technology", {}), "N04"): return Runtime.ok("", {"binding": {}, "payment": {}, "job": {}})
	var target := "nation-certificate:" + JSON.stringify([_technology_site_id(), nation_id, certificate_id, int(certificate.revision)])
	var selection := _nation_original_research_token(nation_id, certificate_id, "N04", "workshop_certificate", target)
	if not selection.ok or selection.token.is_empty(): return selection if not selection.ok else Runtime.fail("STALE_PROJECT")
	var token: Dictionary = selection.token
	var routes := {"metal": "S04", "textile": "S05", "bow": "S07"}
	if not routes.has(str(selection.context.project.route_id)) or str(certificate.industry_id) != str(routes[str(selection.context.project.route_id)]): return Runtime.fail("SPEC_MISMATCH", "原檢驗須對應本次明選產業")
	var output: Dictionary = equipment_orders._output_receipt(str(certificate.feature_id), int(certificate.receipt_id))
	if output.is_empty() or output != certificate.get("accepted_receipt", {}) or int(certificate.operator_id) != int(token.person.person_id) \
		or not equipment_orders._workshop_context(str(certificate.feature_id), str(certificate.industry_id), int(certificate.operator_id)).ok: return Runtime.fail("NO_RECEIPT")
	var ready := _technology_scope_person("nation", nation, int(token.person.person_id))
	if not ready.ok: return ready
	var binding := technology_phase_binding_candidate(token)
	if not binding.ok: return binding
	var payment := technology_phase_payment_candidate(token, {}, binding)
	if not payment.ok: return payment
	var original: Dictionary = nation.get("technology_operations", {}).get("certificates", {}).get(certificate_id, certificate)
	var job := _nation_original_administration_job(ready.person, nation, original, "certificate", certificate_id, token, certificate)
	return Runtime.ok("", {"binding": {}, "payment": payment, "job": job})

func nation_military_issue_receipt_query(token: Dictionary, event: Dictionary) -> Dictionary:
	if not Technology.keys(token, ["scope", "scope_id", "project_id", "epoch", "purpose", "tech_id", "phase_id", "attempt", "person", "binding", "target_id", "materials"]) \
		or not Technology.valid_ref(token.get("person")) \
		or not Technology.keys(event, ["id", "site_id", "target_id", "operator_id", "binding", "work_seconds", "item_ids", "outputs", "materials"]): return Runtime.fail("INVALID_RECEIPT")
	var job: Dictionary = _jobs.get(str(int(token.get("person", {}).get("person_id", -1))), {})
	if job.is_empty() or job.get("nation_issue_token", {}) != token or event != _nation_military_issue_event(job): return Runtime.fail("NO_RECEIPT")
	var current := _nation_military_issue_job_context(job)
	if not current.ok: return current
	if bool(job.get("preparing", false)) or not str(job.get("paused", "")).is_empty() or float(job.elapsed) + 0.00000001 < 5.0: return Runtime.fail("INCOMPLETE")
	var equipment: Dictionary = equipment_orders.check(job.order)
	if not equipment.ok: return equipment
	var actual: Dictionary = equipment_orders._military_issue_check(job.order)
	if not actual.ok or not is_same(actual.get("production"), job.nation_issue_order_ref) or str(actual.get("product", "")) != str(job.nation_issue_product): return actual if not actual.ok else Runtime.fail("STALE_PRODUCT")
	return Runtime.ok("", {"receipt": _nation_receipt_projection(event), "token": token})

func prepare_nation_military_issue_binding(order: Dictionary) -> Dictionary:
	if not order.has("military_production_id"): return Runtime.ok("", {"payment": {}, "metadata": {}})
	if not order.get("military_production_id") is String or not order.get("nation_id") is String \
		or not Technology.integer(order.get("person_id"), 1) or not order.get("standard_id") is String \
		or not Technology.integer(order.get("standard_revision"), 1) or not order.get("take") is Array \
		or not order.get("planned") is Dictionary: return Runtime.fail("INVALID")
	var military: Dictionary = equipment_orders._military_issue_check(order)
	if not military.ok: return military
	var nation: Dictionary = military.nation
	if Technology.scope_known(nation.get("technology", {}), "N05"): return Runtime.ok("", {"payment": {}, "metadata": {}})
	if TechnologyCatalog.get_node("N05").get("enabled") != true: return Runtime.fail("UNIMPLEMENTED")
	if not equipment_orders._nation_duty_ok(_technology_controlled(), nation, "nation.production"): return Runtime.fail("NO_AUTHORITY", "本次原軍需領裝須由當前受控真職責行使者明示")
	var project := Technology.active_project(nation.get("technology", {}))
	var phase := Technology.scope_next_phase(project, project.get("executor", {}))
	if project.get("tech_id") != "N05" or phase.get("binding") != "issue_bow" \
		or not Technology.valid_ref(project.get("executor")) or project.executor.site_id != _technology_site_id() \
		or int(project.executor.person_id) != int(order.person_id) or int(military.production.operator_id) != int(order.person_id): return Runtime.fail("NO_AUTHORITY", "首次軍需研究由同一本原人實際造弓再領裝")
	var expected_holder := "nation-order:" + JSON.stringify([_technology_site_id(), str(order.nation_id), str(order.military_production_id)])
	if project.budget.get("holder") != expected_holder or not _nation_military_first_payment(project, order): return Runtime.fail("BOUND_SOURCE", "只驗本次原項目真正付款生產的有限訂單")
	var ready := _technology_scope_person("nation", nation, int(order.person_id))
	if not ready.ok: return ready
	var token := {"scope": "nation", "scope_id": str(order.nation_id), "project_id": int(project.id), "epoch": int(nation.technology.epoch),
		"purpose": str(project.purpose), "tech_id": "N05", "phase_id": str(phase.id), "attempt": int(project.next_attempt),
		"person": project.executor.duplicate(), "binding": "issue_bow", "target_id": "person:" + str(int(order.person_id)), "materials": {}}
	var binding := technology_phase_binding_candidate(token)
	if not binding.ok: return binding
	var payment := technology_phase_payment_candidate(token, {}, binding)
	if not payment.ok: return payment
	return Runtime.ok("", {"payment": payment, "metadata": {"nation_issue_token": token, "nation_issue_nation_ref": nation,
		"nation_issue_order_ref": military.production, "nation_issue_product": str(military.product),
		"nation_issue_event_id": JSON.stringify([_technology_site_id(), str(order.nation_id), int(project.id), str(project.purpose), int(token.attempt), str(order.military_production_id), str(military.product), "issue"])}})

func prepare_nation_military_issue_receipt(order: Dictionary, military: Dictionary) -> Dictionary:
	if not military.has("production") or Technology.scope_known(military.nation.get("technology", {}), "N05"): return Runtime.ok("", {"phase": {}})
	var job: Dictionary = _jobs.get(str(int(order.person_id)), {})
	if job.is_empty() or not is_same(job.get("order"), order) or not is_same(job.get("nation_issue_order_ref"), military.production) \
		or not job.get("nation_issue_token") is Dictionary: return Runtime.fail("NO_RECEIPT")
	var token: Dictionary = job.nation_issue_token
	var event := _nation_military_issue_event(job)
	var actual := nation_military_issue_receipt_query(token, event)
	if not actual.ok: return actual
	var phase := nation_scope_receipt_candidate(token, event)
	return Runtime.ok("", {"phase": phase}) if phase.ok else phase

func _technology_paid_phase_context(token: Dictionary) -> Dictionary:
	var runtime_script: Variant = Runtime
	if not runtime_script.has_method("technology_existing_paid_phase_source"): return _technology_phase_context(token)
	var paid: Dictionary = runtime_script.call("technology_existing_paid_phase_source", lab.terrain, token)
	if not paid.ok: return _technology_phase_context(token)
	var context := _technology_phase_context(token, false, false)
	if not context.ok: return context
	var budget: Dictionary = context.project.budget
	if budget.is_empty() or budget.status != "granted" or budget.source_site_id != _technology_site_id() \
		or not Technology.material_equal(paid.materials, token.materials): return Runtime.fail("NO_BUDGET")
	var matched := 0
	for payment: Dictionary in budget.payments:
		if payment.payment_id != paid.payment_id: continue
		if int(payment.attempt) != int(token.attempt) or payment.phase_id != token.phase_id or payment.target_id != token.target_id \
			or not Technology.same_person_ref(payment.person, token.person, context.record.get("person_links", [])) \
			or not Technology.material_equal(payment.materials, paid.materials): return Runtime.fail("STALE_SOURCE")
		matched += 1
	if matched != 1: return Runtime.fail("STALE_SOURCE", "原付費工單缺唯一完整付款歷史")
	if str(budget.holder).begins_with("nation-order:"):
		var technology_paid_namespace: Variant = JSON.parse_string(str(budget.holder).trim_prefix("nation-order:"))
		if not technology_paid_namespace is Array or technology_paid_namespace.size() != 3 or budget.holder != "nation-order:" + JSON.stringify(technology_paid_namespace) \
			or technology_paid_namespace[0] != _technology_site_id() or token.scope != "nation" or technology_paid_namespace[1] != token.scope_id \
			or not technology_paid_namespace[2] is String: return Runtime.fail("STALE_SOURCE")
		if str(technology_paid_namespace[2]).begins_with("production_"):
			var military: Dictionary = equipment_orders.call("military_work_preflight", str(token.scope_id), str(technology_paid_namespace[2]))
			if not military.ok: return military
			var order: Dictionary = military.order
			if token.tech_id != "N05" or token.binding != "workshop_bow" or int(order.operator_id) != int(token.person.person_id) \
				or token.target_id != "feature:" + str(order.feature_id) or int(order.source.person_id) != int(budget.grantor.person_id) \
				or paid.source_holder != "feature:" + str(order.feature_id): return Runtime.fail("STALE_SOURCE")
			for resource: String in budget.cap:
				if int(budget.cap[resource]) > int(order.source.cap.get(resource, 0)): return Runtime.fail("NO_BUDGET")
			return context # SAME target/full paid ledger already proven above; no new stock query.
		var order_context := _nation_original_order_context(str(token.scope_id), str(technology_paid_namespace[2]), str(token.binding), true)
		if not order_context.ok: return order_context
		var order: Dictionary = order_context.order
		var source: Dictionary = order.get("payload", {}).get("source", {})
		if order.tech_id != token.tech_id or int(order.project_id) != int(token.project_id) or order.status in ["complete", "revoked"] \
			or source.is_empty() or int(source.get("person_id", -1)) != int(budget.grantor.person_id) \
			or paid.source_holder != "feature:" + str(order.payload.get("reserve_feature_id", "")) \
			or not equipment_orders._public_source_paid(order): return Runtime.fail("STALE_SOURCE")
		for resource: String in budget.cap:
			if int(budget.cap[resource]) > int(source.cap.get(resource, 0)): return Runtime.fail("NO_BUDGET")
	elif str(budget.holder).begins_with("settlement-order:"):
		var paid_parts: Variant = JSON.parse_string(str(budget.holder).trim_prefix("settlement-order:"))
		if not paid_parts is Array or paid_parts.size() != 3 or budget.holder != "settlement-order:" + JSON.stringify(paid_parts) \
			or paid_parts[0] != _technology_site_id() or token.scope != "settlement" or paid_parts[1] != token.scope_id or not paid_parts[2] is String: return Runtime.fail("STALE_SOURCE")
		var paid_runtime: Variant = Runtime
		if not paid_runtime.has_method("settlement_operation_paid_source_candidate"): return Runtime.fail("UNIMPLEMENTED")
		var original_paid: Dictionary = paid_runtime.call("settlement_operation_paid_source_candidate", lab.terrain, token, str(paid_parts[2]))
		if not original_paid.ok: return original_paid
		if original_paid.get("kind") != "settlement_order" or original_paid.get("holder") != budget.holder \
			or original_paid.get("source_site_id") != _technology_site_id() or original_paid.get("grantor") != budget.grantor \
			or not is_same(original_paid.get("settlement"), context.owner) \
			or not is_same(original_paid.get("operations"), context.owner.get("technology_operations")) \
			or not is_same(original_paid.get("order"), original_paid.operations.get("orders", {}).get(str(paid_parts[2]))) \
			or original_paid.get("source_holder") != paid.source_holder: return Runtime.fail("STALE_SOURCE")
		for resource: String in budget.cap:
			if int(budget.cap[resource]) > int(original_paid.get("cap", {}).get(resource, -1)): return Runtime.fail("NO_BUDGET")
	elif budget.holder != "depot" and (budget.holder != "no_materials" or not paid.materials.is_empty()):
		return Runtime.fail("STALE_SOURCE")
	return context

# REPLACE this existing wrapper; all authority/physical/consent guards remain.

# Append to ORIGINAL SitePersonActions. The original _jobs holds the transient
# command; Runtime still owns all feature progress, payment and actual output.

func _scope_people_row(scope: String, owner: Dictionary, identity: int, tech_id: String) -> Dictionary:
	var person := _person(identity, false)
	if person.is_empty(): return {}
	var label := "原居民"
	if scope == "family":
		for member: Dictionary in owner.members:
			if member.site_id == _technology_site_id() and int(member.person_id) == identity: label = str(member.label)
	var team: Variant = person.owner if person.owner is CrowdOwner else _technology_team(person)
	return {"site_id": _technology_site_id(), "person_id": identity, "label": label,
		"team_id": int(team.team_id) if team != null else -1, "owner_ref": person.owner, "body_ref": person.body,
		"learned": Technology.learned(_body_get(person, "technology"), tech_id), "ready": _ready(person),
		"busy": is_busy(identity), "job": job_for(identity)}

func scope_technology_query(tech_id: String, scope_id: String = "") -> Dictionary:
	if lab == null or lab.terrain == null: return Runtime.fail("NO_SITE")
	var node := TechnologyCatalog.get_node(tech_id)
	var scope := str(node.get("scope", ""))
	if scope not in ["family", "settlement", "nation"]: return Runtime.fail("INVALID_TECHNOLOGY")
	var owner := _technology_scope_owner(scope, scope_id)
	if owner.is_empty(): return Runtime.fail("UNREGISTERED", "原家族／聚落／國家尚未正式建立；此窗不建立組織")
	var raw: Variant = owner.get("technology", {})
	if not raw is Dictionary or owner.has("technology") and not (Technology.valid_family_tech(raw) if scope == "family" else Technology.valid_scope_record(raw, scope)): return Runtime.fail("INVALID_TECHNOLOGY")
	if owner.has("technology") and (not Technology.local_holder(raw, _technology_site_id()) if scope == "family" else raw.holder_site_id != _technology_site_id()): return Runtime.fail("REMOTE_HOLDER", "科技原 holder 在另一處；此窗不重建知識或另開項目")
	var identities: Array[int] = Family.member_ids(owner, _technology_site_id()) if scope == "family" else Settlement.residents(lab)
	if scope == "nation":
		identities.clear()
		if equipment_orders == null: return Runtime.fail("NO_OWNER_HOOK")
		for value: Variant in owner.get("members", []):
			if Technology.integer(value, 1) and equipment_orders._member(owner, int(value)): identities.append(int(value))
	var people: Array[Dictionary] = []
	for identity: int in identities:
		var row := _scope_people_row(scope, owner, identity, tech_id)
		if not row.is_empty(): people.append(row)
	# S12 carriers: every person on this Site that the order's own per-person rule
	# admits (Runtime.settlement_ship_person_eligible), not only housed residents.
	var carriers: Array[Dictionary] = []
	if scope == "settlement" and lab.site_controller != null:
		for candidate: Dictionary in lab.site_controller._nation_ui_people():
			if not Runtime.settlement_ship_person_eligible(lab.terrain, owner, int(candidate.id)): continue
			var row := _scope_people_row(scope, owner, int(candidate.id), tech_id)
			if not row.is_empty(): carriers.append(row)
	var project := Technology.active_project(raw)
	var phase := {}
	if not project.is_empty() and int(project.rules_version) == 2: phase = Technology.scope_next_phase(project, project.executor, raw.get("person_links", []))
	var duty := _technology_scope_duty(scope, owner, true)
	var teaching := _technology_duty("family.teach") if scope == "family" else Runtime.fail("NO_FAMILY_LESSON")
	return Runtime.ok("", {"scope": scope, "scope_id": _technology_scope_id(scope, owner, scope_id), "tech_id": tech_id,
		"terrain_ref": lab.terrain, "site_ref": lab.terrain.site, "owner_ref": owner, "site_id": _technology_site_id(),
		"current_person_id": _technology_controlled(), "research_decider": int(duty.get("decider", -1)),
		"teaching_decider": int(teaching.get("decider", -1)), "duty_result": duty.duplicate(true),
		"known": Technology.scope_known(raw, tech_id), "known_ids": _technology_known_for(scope_id if scope == "nation" else ""), "people": people, "carriers": carriers,
		"project": project.duplicate(true), "phase": phase, "routes": node.research.routes.duplicate(true)})

# Narrow original technology_query replacement: immediately after reading
# Technology.active_project(tech), discard only the *presentation* of another
# node's active project. The owner and active project remain untouched.
# BEFORE:
#   var project := Technology.active_project(tech)
# AFTER:
#   var project := Technology.active_project(tech)
#   if not project.is_empty() and (project.tech_id != "F07" or int(project.rules_version) != 1): project = {}
# This preserves F07's original 3-bow UI/costs while the new section shows the
# actual generic node. Existing F07 command guards still recheck the true owner.

func technology_supervision_query(captive_id: int = 0, supervisor_id: int = 0, executor_id: int = 0, vehicle_id: String = "") -> Dictionary:
	if not is_instance_valid(lab) or lab.terrain == null or lab.site_controller == null: return Runtime.fail("STALE_SOURCE")
	var site: Dictionary = lab.terrain.site
	var requester_id := _technology_controlled()
	var captives: Array = []
	var supervisors: Array = []
	var seen_guards := {}
	for key: String in site.get("captivity", {}):
		if not key.is_valid_int(): continue
		var relation: Dictionary = site.captivity[key]
		var captive := _technology_supervision_person(int(key))
		if captive.is_empty(): continue
		captive.merge({"guard_id": int(relation.get("guard_id", 0)), "relation_ref": relation, "relation_state": relation.duplicate(true)})
		captives.append(captive)
		var guard_id := int(relation.get("guard_id", 0))
		if not seen_guards.has(guard_id):
			var supervisor := _technology_supervision_person(guard_id)
			if not supervisor.is_empty(): supervisors.append(supervisor)
			seen_guards[guard_id] = true
	var analysts: Array = []
	var project := {}
	var family := _technology_family()
	if not family.is_empty():
		var raw: Dictionary = family.get("technology", {})
		var active := Technology.active_project(raw)
		if not active.is_empty() and int(active.get("rules_version", 0)) == 2 and active.get("tech_id") in ["F11", "F12"]:
			project = {"id": int(active.id), "purpose": str(active.purpose), "tech_id": str(active.tech_id), "family_id": str(family.family_id)}
			var analyst := _technology_supervision_person(int(active.executor.person_id))
			if not analyst.is_empty():
				analyst.merge({"project_ref": active, "project_id": int(active.id), "purpose": str(active.purpose), "family_ref": family})
				analysts.append(analyst)
	var vehicles: Array = []
	for key: String in site.get("vehicles", {}):
		var vehicle: Dictionary = site.vehicles[key]
		if not lab.site_controller.vehicles.is_siege(vehicle): continue
		var capture: Variant = vehicle.get("technology_capture", {})
		vehicles.append({"vehicle_id": key, "label": "原%s #%s · %s" % [str(vehicle.get("kind", "")), key, "來源資料不合法" if not capture is Dictionary else "真繳獲來源" if not capture.is_empty() else "無可分析來源"],
			"vehicle_ref": vehicle, "capture_ref": capture if capture is Dictionary else null, "capture_state": capture.duplicate(true) if capture is Dictionary else capture})
	var captive_begin := Runtime.fail("SELECT_TARGET", "請明選原俘虜及其當前真看守。")
	var captive_stop := Runtime.fail("NO_TARGET", "請明選本次受監管工單的原俘虜及真看守。")
	if captive_id > 0 and supervisor_id > 0:
		captive_begin = Runtime.fail("BUSY") if is_busy(captive_id) or is_busy(supervisor_id) else _captive_craft_context(requester_id, captive_id, supervisor_id, "bow")
		var job := job_for(captive_id)
		if job.get("kind") == "captive_craft" and int(job.get("guard_id", 0)) == supervisor_id \
			and is_same(job.get("terrain"), lab.terrain) and is_same(job.get("site_state"), site):
			var supervisor := _person(supervisor_id)
			if _ready(supervisor, true): captive_stop = _captive_craft_authority(requester_id, supervisor, str(job.captivity.get("prison_id", "")), false)
	var analysis_begin := Runtime.fail("NO_TARGET", "先於本族 F11／F12 明示準備項目、取得同意，再選同一原研究者及真繳獲器械。")
	if executor_id > 0 and not vehicle_id.is_empty():
		analysis_begin = Runtime.fail("NOT_DELIVERED", "本技藝操作尚未交付。") if not project.is_empty() and not bool(TechnologyCatalog.get_node(str(project.tech_id)).get("enabled", false)) else Runtime.fail("BUSY") if is_busy(executor_id) else _technology_analysis_context(requester_id, executor_id, vehicle_id)
	return Runtime.ok("只讀原人物／監管／研究／器械", {"terrain_ref": lab.terrain, "site_ref": site, "site_id": _technology_site_id(), "current_person_id": requester_id,
		"captives": captives, "supervisors": supervisors, "analysts": analysts, "vehicles": vehicles, "project": project,
		"captive_begin": {"ok": bool(captive_begin.ok), "code": str(captive_begin.get("code", "")), "message": str(captive_begin.get("message", ""))},
		"captive_stop": {"ok": bool(captive_stop.ok), "code": str(captive_stop.get("code", "")), "message": str(captive_stop.get("message", ""))},
		"analysis_begin": {"ok": bool(analysis_begin.ok), "code": str(analysis_begin.get("code", "")), "message": str(analysis_begin.get("message", ""))}})

func _controlled_feature_work_request(key: String, job: Dictionary, seconds: float) -> Dictionary:
	if job.get("kind") == "technology_vehicle": return _controlled_vehicle_work_request(key, job, seconds)
	var context := _controlled_feature_job_context(job)
	if not context.ok: return {}
	var person: Dictionary = context.person
	var limit := floori(Runtime.CARRY_CAPACITY - Runtime.carried_load(lab.terrain.site, {}, person.holder))
	var checked := Runtime.work_preflight(lab.terrain, job.work_task, person.cargo, limit, int(person.faction), int(person.person_id), _tent_occupied)
	if not checked.ok: return {}
	var remaining := float(checked.get("remaining", NAN))
	var productivity := float(checked.get("productivity", NAN))
	var factor := float(checked.get("progress_multiplier", 1.0))
	var expected_factor := Runtime.technology_cold_work_multiplier(lab.terrain, job.feature_ref, job.work_task)
	if not is_finite(remaining) or remaining < 0.0 or not is_finite(productivity) or productivity <= 0.0 or not is_finite(factor) or factor != expected_factor \
		or not str(checked.get("required_skill", "")).is_empty() and not bool(checked.get("eligible_master", false)): return {}
	var skills: Dictionary = lab.site_controller.work_team._work_skill_facts(checked)
	if skills.is_empty(): return {}
	var participant := _shared_work_participant(person)
	if participant.is_empty(): return {}
	participant["progress_multiplier"] = productivity * factor
	var paused := "REST" if not bool(person.player) and Fatigue.needs_work_rest(float(_body_get(person, "fatigue")), bool(_body_get(person, "work_resting"))) else ""
	_prepared_controlled_features[key] = {"job": job, "task": job.work_task, "person": person, "cargo": person.cargo,
		"holder": person.holder, "holder_version": int(person.holder.version), "carry_limit": limit, "remaining": remaining,
		"productivity": productivity, "factor": factor, "required_skills": skills.required, "eligible_skills": skills.eligible, "required_skill": str(checked.get("required_skill", "")), "eligible_master": bool(checked.get("eligible_master", false))}
	var request := {"provider": "person_actions", "key": key, "participants": [participant], "remaining": remaining, "productive_kind": "sum",
		"progress_multiplier": 1.0, "max_game_seconds": seconds, "paused": paused, "task": job.work_task}
	_prepared_controlled_features[key]["request"] = request
	return request

func refresh_controlled_feature_work_request(request: Dictionary) -> Dictionary:
	if request.get("provider") != "person_actions" or not request.get("key") is String or not request.get("task") is Dictionary: return {}
	var key: String = request.key
	var held: Dictionary = _prepared_controlled_features.get(key, {})
	if held.is_empty() or not is_same(held.task, request.task) or not is_same(_jobs.get(key), held.job): return {}
	if held.job.get("kind") == "technology_vehicle" and not is_same(held.get("request"), request): return {}
	var updated := _controlled_feature_work_request(key, held.job, _controlled_feature_seconds)
	if not updated.is_empty(): _prepared_controlled_features[key]["request"] = request
	return updated

func valid_checked_work_prefix(task: Dictionary, identity: int, prefix_ref: Dictionary) -> bool:
	var prefix: Dictionary = checked_work_prefix_for_task(task, identity)
	if not _gd_contact_job_segment.is_empty(): return not prefix.is_empty() and is_same(prefix, prefix_ref) and _valid_gd_checked_controlled_prefix(prefix)
	if prefix.is_empty() or prefix.get("owner") != self or not is_same(prefix, prefix_ref) or not is_same(prefix.plan, _checked_controlled_prefixes.plan) or not is_same(prefix.runtime_priors, _checked_controlled_prefixes.runtime_priors): return false
	var held: Dictionary = prefix.shared_item.held
	var job: Dictionary = _jobs.get(str(prefix.key), {})
	if not is_same(job, held.job) or not is_same(job.get("work_task"), task) or task != held.task_start: return false
	var person: Dictionary = _person(identity)
	var start: Dictionary = prefix.start
	if person.is_empty() or person.owner != start.owner or int(person.unit) != int(start.unit) or not is_same(person.body, start.body) or not is_same(person.holder, start.holder) or not is_same(person.cargo, start.cargo) or int(person.holder.version) != int(start.holder_version): return false
	if held.kind == "technology_feature": return is_same(job.get("feature_ref"), prefix.target_ref) and is_same(lab.terrain.site.features.get(job.feature_id), prefix.target_ref)
	if held.kind == "technology_vehicle": return is_same(job.get("vehicle_ref"), prefix.target_ref) and is_same(lab.terrain.site.vehicles.get(job.vehicle_id), prefix.target_ref) and is_same(prefix.target_ref.get("repair" if str(task.get("action", "")) == "repair" else "build"), held.build)
	return false

func shared_vehicle_work_request_facts(request: Dictionary) -> Dictionary:
	if request.get("provider") != "person_actions" or request.get("productive_kind") != "sum" or str(request.get("paused", "")) not in ["", "REST", "SHARED_MASTER"]: return {}
	var key: String = str(request.get("key", ""))
	var held: Dictionary = _prepared_controlled_features.get(key, {})
	var job: Dictionary = _jobs.get(key, {})
	if held.is_empty() or not is_same(held.get("request"), request) or job.get("kind") not in ["technology_feature", "technology_vehicle"] or not is_same(held.job, job) or not is_same(request.get("task"), held.task) or not is_same(job.get("work_task"), held.task) or request.get("participants", []).size() != 1: return {}
	if not is_equal_approx(float(request.get("remaining", -1.0)), float(held.remaining)) or float(request.get("max_game_seconds", -1.0)) < 0.0 or float(request.max_game_seconds) > _controlled_feature_seconds + Fatigue.WORK_PLAN_EPS: return {}
	var participant: Dictionary = request.participants[0]
	var identity: int = int(job.executor_id)
	if int(participant.person_id) != identity or not is_same(participant.get("original_body", participant.get("body")), held.person.body) or not is_equal_approx(float(participant.get("progress_multiplier", 1.0)), float(held.productivity) * float(held.factor)) or not is_equal_approx(float(request.progress_multiplier), 1.0): return {}
	var physical: Dictionary = Runtime.shared_physical_work_unit(lab.terrain, held.task)
	if physical.is_empty() or not is_same(physical.target_ref, job.get("vehicle_ref") if job.kind == "technology_vehicle" else job.get("feature_ref")): return {}
	var facts: Dictionary = physical.duplicate(false)
	facts.merge({"owner": self, "request": request, "site": lab.terrain.site, "held": held, "job": job, "task": held.task, "person_ids": [identity],
		"required_skills": held.required_skills.duplicate(), "eligible_by_id": {identity: held.eligible_skills.duplicate()},
		"remaining": float(physical.physical_remaining), "participants": request.participants, "values": request.duplicate(false),
		"participant_values": lab.site_controller.work_team._shared_vehicle_participant_values(request)})
	_shared_vehicle_request_facts[key] = facts
	return facts

func valid_shared_vehicle_work_request_facts(request: Dictionary, facts: Dictionary) -> bool:
	var held: Dictionary = _prepared_controlled_features.get(str(request.get("key", "")), {})
	if facts.get("owner") != self or not is_same(facts.get("request"), request) or not is_same(facts.get("site"), lab.terrain.site) or not is_same(facts.get("participants"), request.get("participants")) or request != facts.get("values") or lab.site_controller.work_team._shared_vehicle_participant_values(request) != facts.get("participant_values") or not is_same(_shared_vehicle_request_facts.get(str(request.key)), facts) or not is_same(held, facts.get("held")) or not is_same(_jobs.get(str(request.key)), facts.get("job")) or not is_same(facts.job.get("work_task"), facts.get("task")): return false
	var physical: Dictionary = Runtime.shared_physical_work_unit(lab.terrain, facts.task)
	return not physical.is_empty() and is_same(physical.target_ref, facts.target_ref) and is_same(physical.work_unit, facts.work_unit) and physical.action == facts.action and physical.field == facts.field

func prepare_gd_contact_job_segment(planned: Dictionary, seconds: float, defer_runtime: bool = false) -> Dictionary:
	if _gd_contact_job_capture.is_empty() or not _gd_contact_job_segment.is_empty() or planned.get("ok") != true \
		or not is_same(planned, lab.gd_mesh_work_segment_plan()) or not is_finite(seconds) or seconds <= 0.0 \
		or not is_equal_approx(float(planned.get("seconds", -1.0)), seconds) \
		or float(_gd_contact_job_capture.elapsed) + seconds > float(_gd_contact_job_capture.seconds) + Fatigue.WORK_PLAN_EPS:
		return Runtime.fail("STALE_WORK_PREFIX")
	var candidates: Array[Dictionary] = []
	var allocations: Dictionary = planned.get("jobs", {}).get("person_actions", {})
	for key: String in _gd_contact_job_capture.prepared.held:
		var held: Dictionary = _gd_contact_job_capture.prepared.held[key]
		if held.kind in ["technology_feature", "technology_vehicle"]: continue # Real physical unit, never a PA parallel elapsed timer.
		var allocation: Dictionary = allocations.get(key, {})
		if allocation.is_empty(): continue
		# Only SAME captured jobs can be advanced. A true original cancellation
		# stops later intervals; it is never replaced with a projected alive job.
		if not is_same(_jobs.get(key), held.job): continue
		if float(held.job.elapsed) != float(held.committed_elapsed) or float(held.job.duration) != float(held.duration): return Runtime.fail("STALE_SOURCE")
		var actual: float = float(allocation.get("actual_seconds", 0.0))
		var productive: float = float(allocation.get("effective_seconds", 0.0))
		if not is_finite(actual) or not is_finite(productive) or actual < 0.0 or actual > seconds + Fatigue.WORK_PLAN_EPS \
			or productive < 0.0 or productive > seconds * float(held.request.get("progress_multiplier", 1.0)) + Fatigue.WORK_PLAN_EPS:
			return Runtime.fail("INVALID_WORK")
		for identity: int in held.people:
			var effort: float = float(allocation.get("participant_seconds", {}).get(identity, 0.0))
			if not is_finite(effort) or effort < 0.0 or effort > seconds + Fatigue.WORK_PLAN_EPS: return Runtime.fail("INVALID_WORK")
		candidates.append({"held": held, "allocation": allocation,
			"elapsed": minf(float(held.duration), float(held.committed_elapsed) + productive)})
	_gd_contact_job_segment = {"owner": self, "plan": planned, "seconds": seconds, "candidates": candidates, "published": false,
		"prefixes": [], "runtime": [], "priors": lab.gd_mesh_work_segment_priors()}
	for envelope: Dictionary in _gd_contact_job_capture.controlled_envelopes:
		var original: Dictionary = envelope.prepared.prefix_ref
		var held: Dictionary = original.shared_item.held
		var allocation: Dictionary = allocations.get(str(held.key), {})
		var identity: int = int(original.person_id)
		var actual: float = float(allocation.get("participant_seconds", {}).get(identity, 0.0))
		var productive: float = float(allocation.get("participant_effective_seconds", {}).get(identity, 0.0))
		if actual <= 0.0 or productive <= 0.0:
			if float(original.entry.remaining) > Fatigue.WORK_PLAN_EPS: continue
			var already := false
			for prior: Dictionary in _gd_contact_job_capture.runtime_priors: already = already or is_same(prior.task, original.task)
			if already: continue
		var prefix: Dictionary = original.duplicate(false)
		prefix.plan = planned
		prefix.allocation = allocation
		prefix.runtime_priors = _gd_contact_job_segment.priors
		prefix.actual_seconds = actual
		prefix.productive_seconds = productive
		prefix.applied_productive_seconds = productive * float(original.entry.get("productivity", 1.0)) * float(original.entry.get("factor", 1.0))
		prefix.group_actual_seconds = float(allocation.get("actual_seconds", 0.0))
		_gd_contact_job_segment.prefixes.append(prefix)
	if defer_runtime: return Runtime.ok("同段真PA分配已登記", {"segment": _gd_contact_job_segment})
	return validate_gd_contact_job_runtime_segment(_gd_contact_job_segment)

func validate_gd_contact_job_runtime_segment(segment: Dictionary) -> Dictionary:
	if not is_same(segment, _gd_contact_job_segment) or bool(segment.get("published", true)) or not segment.get("runtime", []).is_empty() or not is_same(segment.get("plan"), lab.gd_mesh_work_segment_plan()) or not is_same(segment.get("priors"), lab.gd_mesh_work_segment_priors()): return Runtime.fail("STALE_WORK_PREFIX")
	for envelope: Dictionary in _gd_contact_job_capture.controlled_envelopes:
		for prefix: Dictionary in segment.prefixes:
			if not is_same(prefix.entry, envelope.prepared.prefix_ref.entry): continue
			var restricted: Dictionary = Runtime.restrict_gd_contact_work_prefix(envelope, prefix, segment.priors)
			if not restricted.ok: return restricted
			segment.runtime.append(restricted)
			segment.priors.append(restricted)
	return Runtime.ok("原人物真段工時已派生；未寫timer/成本/學習", {"segment": _gd_contact_job_segment})

func cold_technology_checkpoint_guard() -> Dictionary:
	# Original Region graph only; a physical PA envelope owns no timer work.
	# Its SAME selector/target/paid task must pass the original physical owners.
	if not is_instance_valid(lab) or lab.restore_only != true: return Runtime.fail("INVALID_MODE")
	for key: String in _jobs:
		var job: Dictionary = _jobs[key]
		var physical: bool = str(job.get("kind", "")) in ["technology_feature", "technology_vehicle"]
		var selector: Variant = job.get("operation_selector", {})
		if physical and not selector is Dictionary: return Runtime.fail("CORRUPT_TECHNOLOGY")
		var physical_research: bool = physical and selector.has("token")
		if physical_research and (not Technology.keys(selector, ["token"]) or not selector.token is Dictionary or selector.token.is_empty()):
			return Runtime.fail("CORRUPT_TECHNOLOGY")
		var research: bool = physical_research or job.has("technology_project") or not job.get("technology_scope_token", {}).is_empty() \
			or not job.get("nation_token", {}).is_empty() or str(job.get("kind", "")) == "technology_lesson"
		if not research: continue # Existing nonresearch Region admission stays unchanged.
		var person := _person(int(job.executor_id))
		if person.is_empty() or bool(person.get("player", true)): return Runtime.fail("BUSY", "人工在途科研不屬 NPC 冷保存")
		var pending: Variant = job.get("pending", {})
		if not pending is Dictionary or not pending.is_empty(): return Runtime.fail("BUSY", "原人物接觸後提交尚未結束")
		if str(job.kind) == "technology_lesson" and bool(_person(int(job.target_id)).get("player", true)): return Runtime.fail("BUSY", "人工授課參與者仍沿原保存守衛")
		var checked := _job_context(job)
		if not checked.ok: return checked
		if not is_same(job.get("terrain"), lab.terrain) or not is_same(job.get("site_state"), lab.terrain.site): return Runtime.fail("STALE_SOURCE")
		if not is_finite(float(job.get("elapsed", -1.0))) or float(job.get("elapsed", -1.0)) < 0.0 \
			or not is_finite(float(job.get("duration", -1.0))) or float(job.duration) < 0.0: return Runtime.fail("CORRUPT_TECHNOLOGY")
		if physical_research:
			if not job.get("work_task") is Dictionary or float(job.duration) != 0.0: return Runtime.fail("CORRUPT_TECHNOLOGY")
			var target: Dictionary = job.vehicle_ref if str(job.kind) == "technology_vehicle" else job.feature_ref
			if not is_same(target.get("tech_trial"), selector.token) or selector.token.target_id != job.work_task.target \
				or int(selector.token.person.person_id) != int(job.executor_id): return Runtime.fail("STALE_PROJECT")
			var paid := Runtime.validate_technology_trial_project_storage(lab.terrain, target)
			if not paid.ok: return paid
			var limit := floori(Runtime.CARRY_CAPACITY - Runtime.carried_load(lab.terrain.site, {}, person.holder))
			var work := Runtime.work_preflight(lab.terrain, job.work_task, person.cargo, limit, int(person.faction), int(person.person_id), _tent_occupied)
			if not work.ok: return work
			if not is_finite(float(work.get("remaining", -1.0))) or float(work.remaining) <= 0.00000001:
				return Runtime.fail("BUSY", "原已完成物理工序必先沿同點交貨")
			continue # Zero duration is this original physical envelope, never a completed timer.
		if float(job.elapsed) >= float(job.duration) - 0.00000001:
			return Runtime.fail("BUSY", "原已完成試作必先沿同點提交")
	return Runtime.ok()

func _controlled_vehicle_work_request(key: String, job: Dictionary, seconds: float) -> Dictionary:
	var context := _controlled_vehicle_job_context(job)
	if not context.ok: return {}
	var person: Dictionary = context.person
	var limit := floori(Runtime.CARRY_CAPACITY - Runtime.carried_load(lab.terrain.site, {}, person.holder))
	var checked := Runtime.work_preflight(lab.terrain, job.work_task, person.cargo, limit, int(person.faction), int(person.person_id), _tent_occupied)
	if not checked.ok: return {}
	var remaining := float(checked.get("remaining", NAN))
	var factor := float(checked.get("progress_multiplier", NAN))
	var productivity := float(checked.get("productivity", 1.0))
	var original_credit: Dictionary = Runtime.technology_work_credit_facts(lab.terrain, job.vehicle_ref) if job.work_task.action == "construct" else Runtime.ok("", {"factor": 1.0})
	if not original_credit.ok: return {}
	var expected_factor := float(original_credit.factor) * Runtime.technology_cold_work_multiplier(lab.terrain, job.vehicle_ref, job.work_task)
	if not is_finite(remaining) or remaining < 0.0 or not is_finite(factor) or factor != expected_factor or float(original_credit.factor) < 1.0 or float(original_credit.factor) > 2.0 or not is_finite(productivity) or not (is_equal_approx(productivity, 1.0) or is_equal_approx(productivity, 10.0 / 9.0)): return {}
	var skills: Dictionary = lab.site_controller.work_team._work_skill_facts(checked)
	if skills.is_empty(): return {}
	var participant := _shared_work_participant(person)
	if participant.is_empty(): return {}
	participant["progress_multiplier"] = productivity * factor
	var paused := "REST" if not bool(person.player) and Fatigue.needs_work_rest(float(_body_get(person, "fatigue")), bool(_body_get(person, "work_resting"))) else ""
	# A valid helper can wait for another original provider's actual master.
	# Raw standalone planning remains zero effort; only the true same-target
	# union can resolve this derived wait using actual participant skills.
	if paused.is_empty():
		for skill: String in skills.required:
			if not skills.eligible.has(skill): paused = "SHARED_MASTER"
	_prepared_controlled_features[key] = {"job": job, "task": job.work_task, "person": person, "cargo": person.cargo, "holder": person.holder,
		"holder_version": int(person.holder.version), "carry_limit": limit, "remaining": remaining, "productivity": productivity, "factor": factor,
		"required_skill": str(checked.get("required_skill", "")), "eligible_master": bool(checked.get("eligible_master", false)),
		"required_skills": skills.required, "eligible_skills": skills.eligible}
	var request := {"provider": "person_actions", "key": key, "participants": [participant], "remaining": remaining, "productive_kind": "sum",
		"progress_multiplier": 1.0, "max_game_seconds": seconds, "paused": paused, "task": job.work_task}
	_prepared_controlled_features[key]["request"] = request
	return request

func prepare_checked_controlled_prefix_allocations(admitted: Dictionary, runtime_priors: Array = []) -> Dictionary:
	if admitted.get("ok") != true or admitted.get("owner") != self or not _checked_controlled_prefixes.is_empty(): return Runtime.fail("CLOCK_NOT_READY")
	_checked_controlled_prefixes = {"owner": self, "admitted": admitted, "plan": admitted.plan, "prefixes": [], "runtime": [], "runtime_priors": runtime_priors}
	for key: String in admitted.admitted:
		var item: Dictionary = admitted.admitted[key]
		var held: Dictionary = item.held
		if held.kind not in ["technology_feature", "technology_vehicle"]: continue
		var job: Dictionary = held.job
		var entry: Dictionary = _prepared_controlled_features.get(key, {})
		var identity: int = int(job.executor_id)
		if entry.is_empty() or not is_same(entry.job, job) or not is_same(entry.task, held.task) or not held.people.has(identity): return Runtime.fail("STALE_SOURCE")
		var start: Dictionary = held.people[identity].duplicate(false)
		start.item_state = start.holder
		start.cell = start.start_cell
		start.occupied = _tent_occupied
		start.carry_limit = int(entry.carry_limit)
		start.row = start.body
		var target_ref: Dictionary = held.feature if held.kind == "technology_feature" else held.vehicle
		var action: String = str(held.task.get("action", ""))
		start.work_unit = target_ref.get("repair", {}) if action == "repair" else target_ref.get("pending_build", target_ref) if action == "construct" and held.kind == "technology_feature" else held.build if held.kind == "technology_vehicle" else target_ref
		var actual: float = float(item.allocation.get("participant_seconds", {}).get(identity, 0.0))
		var productive: float = float(item.allocation.get("participant_effective_seconds", {}).get(identity, 0.0))
		var multiplier: float = float(entry.get("productivity", 1.0)) * float(entry.get("factor", 1.0))
		var applied: float = productive * multiplier
		if not is_finite(actual) or not is_finite(productive) or not is_finite(applied) or actual < 0.0 or productive < 0.0 or productive > actual + Fatigue.WORK_PLAN_EPS or applied < 0.0: return Runtime.fail("INVALID_WORK")
		if (actual <= 0.0 or productive <= 0.0) and float(entry.remaining) > Fatigue.WORK_PLAN_EPS: continue
		var prefix := {"owner": self, "plan": admitted.plan, "entry": entry, "person_id": identity, "task": held.task,
			"start": start, "target_ref": target_ref, "target": str(held.task.target), "plan_key": str(item.allocation.get("shared_vehicle_group", {}).get("key", "person_actions:" + key)), "shared_vehicle_group": item.allocation.get("shared_vehicle_group", {}),
			"actual_seconds": actual, "productive_seconds": productive, "applied_productive_seconds": applied,
			"group_actual_seconds": float(item.allocation.get("actual_seconds", 0.0)), "allocation": item.allocation,
			"required_skill": str(entry.get("required_skill", "")), "eligible_master": bool(entry.get("eligible_master", false)),
			"required_skills": entry.get("required_skills", []).duplicate(), "eligible_skills": entry.get("eligible_skills", []).duplicate(),
			"runtime_priors": runtime_priors, "shared_item": item, "key": key,
			"work_unit": start.work_unit, "policy_exception": str(held.get("trial_facts", {}).get("policy_exception", ""))}
		_checked_controlled_prefixes.prefixes.append(prefix)
	return Runtime.ok("原PA真实分配已登记，尚未材料预验", {"owner": self, "registered": _checked_controlled_prefixes})

func valid_gd_contact_work_prefix(envelope: Dictionary, prefix: Dictionary, priors: Array) -> bool:
	if _gd_contact_job_capture.is_empty() or _gd_contact_job_segment.is_empty() or bool(_gd_contact_job_capture.finished) \
		or not is_same(priors, _gd_contact_job_segment.priors): return false
	for prior: Dictionary in priors:
		if not lab.gd_mesh_work_prior_candidate(prior, priors): return false
	var found := false
	for original: Dictionary in _gd_contact_job_capture.controlled_envelopes: found = found or is_same(original, envelope)
	if not found or envelope.owner != self or prefix.get("owner") != self: return false
	for actual: Dictionary in _gd_contact_job_segment.prefixes:
		if not is_same(actual, prefix): continue
		var held: Dictionary = envelope.prepared.prefix_ref.shared_item.held
		var allocation: Dictionary = _gd_contact_job_segment.plan.jobs.get("person_actions", {}).get(str(held.key), {})
		var identity: int = int(prefix.person_id)
		var seconds: float = float(allocation.get("participant_seconds", {}).get(identity, 0.0))
		var productive: float = float(allocation.get("participant_effective_seconds", {}).get(identity, 0.0))
		var multiplier: float = float(prefix.entry.get("productivity", 1.0)) * float(prefix.entry.get("factor", 1.0))
		return seconds >= 0.0 and seconds <= float(_gd_contact_job_segment.seconds) + Fatigue.WORK_PLAN_EPS \
			and productive >= 0.0 and productive <= seconds + Fatigue.WORK_PLAN_EPS \
			and is_equal_approx(float(prefix.actual_seconds), seconds) and is_equal_approx(float(prefix.productive_seconds), productive) \
			and is_equal_approx(float(prefix.applied_productive_seconds), productive * multiplier) \
			and is_same(prefix.entry, envelope.prepared.prefix_ref.entry) and is_same(prefix.shared_item.held, held) \
			and is_same(prefix.plan, _gd_contact_job_segment.plan) and is_same(prefix.task, envelope.prepared.task) \
			and is_same(prefix.target_ref, envelope.target) and is_same(prefix.work_unit, envelope.unit) \
			and identity == int(envelope.prepared.identity)
	return false

func prepare_gd_contact_job_prefix(requests: Array, seconds: float) -> Dictionary:
	if not _gd_contact_job_capture.is_empty() or not _gd_contact_job_segment.is_empty(): return Runtime.fail("CLOCK_NOT_READY")
	var captured: Dictionary = prepare_shared_work_prefix(requests, seconds)
	if not captured.ok: return captured
	var people := {}
	for key: String in captured.held:
		var held: Dictionary = captured.held[key]
		var job: Dictionary = held.job
		var controlled: bool = held.kind in ["technology_feature", "technology_vehicle"]
		var multiplier: float = float(held.request.get("progress_multiplier", 1.0))
		var remaining: float = maxf(0.0, float(held.duration) - float(held.elapsed))
		var already_due: bool = remaining <= Fatigue.WORK_PLAN_EPS
		var can_finish: bool = already_due or (str(held.request.get("paused", "")).is_empty() and remaining <= seconds * multiplier + Fatigue.WORK_PLAN_EPS)
		if held.kind in ["ranged_craft", "captive_craft"] and can_finish:
			var source: Dictionary = Runtime.prepare_ranged_craft(lab.terrain, str(job.recipe), int(job.executor_id), job.get("technology_scope_token", {}), false, true)
			if not source.ok: return source
			held["ranged_source"] = source
		if held.kind == "technology_lesson" and job.has("nation_course_id") and can_finish:
			var source: Dictionary = equipment_orders.prepare_funded_course_source(str(job.nation_course_nation), str(job.nation_course_id), job)
			if not source.ok: return source
			held["funded_source"] = source
		if _gd_typed_terminal_kind(str(held.kind)) and can_finish:
			var source: Dictionary = prepare_gd_typed_terminal(job, true)
			if not source.ok: return source
			held["typed_source"] = source
		# Nonterminal ordinary timers cannot reach an inventory tail. The pure
		# terminal source/publisher seam remains explicit only where it is due.
		if not controlled and can_finish and (held.kind not in ["ranged_craft", "captive_craft", "technology_lesson", "technology_analysis", "nation_administration", "water_schedule", "food_order"] and not _gd_typed_terminal_kind(str(held.kind))):
			return Runtime.fail("CONTACT_JOB_ENDPOINT_SOURCE_NOT_PREPARED", held.kind)
		for identity: int in held.people:
			if people.has(identity): return Runtime.fail("DUPLICATE_ACTIVITY")
			var original: Dictionary = held.people[identity]
			var person: Dictionary = _person(identity)
			people[identity] = {"held": held, "owner": original.owner, "body": original.body,
				"unit": int(original.unit), "hit": int(person.hit), "cell": person.cell}
		held["committed_elapsed"] = float(held.elapsed)
	_gd_contact_job_capture = Runtime.ok("原PA合法起點/有限endpoint已純核", {"owner": self, "prepared": captured,
		"seconds": seconds, "elapsed": 0.0, "people": people, "published": [], "controlled_envelopes": [], "runtime_priors": [], "finished": false})
	return _gd_contact_job_capture

func _prepare_ranged_technology_completion(job: Dictionary) -> Dictionary:
	# CURRENT original completion only. Upper source previews never enter here.
	if job.get("kind") == "captive_craft":
		var supervised: Dictionary = _captive_craft_job_context(job)
		return Runtime.ok("", {"kind": "", "owner": {}, "record": {}}) if supervised.ok else supervised
		# Captive manufacture NEVER creates Scope/Family/learning evidence.
	if job.has("technology_scope_token"):
		var token: Dictionary = job.technology_scope_token
		var checked: Dictionary = _scope_ranged_craft_guard(int(job.executor_id), token)
		if not checked.ok: return checked
		var payment: Dictionary = technology_phase_payment_candidate(token, token.materials)
		if not payment.ok: return payment
		var event_id: String = str(token.tech_id) + ":ranged:" + JSON.stringify([_technology_site_id(), int(token.project_id), int(token.attempt), str(token.binding)])
		var completed: Dictionary = _prepare_scope_phase_completion(token, payment, event_id, float(job.duration))
		if not completed.ok: return completed
		return Runtime.ok("", {"kind": "scope", "owner": completed.owner, "record": completed.record,
			"record_before": completed.record.duplicate(true), "receipt": completed})
	if not job.has("technology_project"): return Runtime.ok("", {"kind": "", "owner": {}, "record": {}})
	var check: Dictionary = _technology_trial_context(job)
	if not check.ok: return check
	var family: Dictionary = _technology_family()
	var record: Dictionary = family.technology
	var candidate: Dictionary = record.duplicate(true)
	var project: Dictionary = Technology.active_project(candidate)
	project.receipts.append({"site_id": _technology_site_id(), "person_id": int(job.executor_id), "attempt": int(job.technology_attempt)})
	for resource: String in Technology.TRIAL_COST: project.budget.spent[resource] = int(project.budget.spent[resource]) + int(Technology.TRIAL_COST[resource])
	var complete: bool = Technology.stages(project, _technology_ref(int(job.executor_id)), record.get("person_links", [])) == 3
	var executor: Dictionary = _person(int(job.executor_id))
	var person_candidate: Dictionary = Technology.learned_candidate(_body_get(executor, "technology")) if complete else {}
	if complete:
		if person_candidate.is_empty(): return Runtime.fail("INVALID_TECHNOLOGY")
		if not candidate.known.has("F07"): candidate.known.append("F07")
		project.closed = true
		candidate.active = 0
	if not Technology.valid_family_tech(candidate): return Runtime.fail("INVALID_TECHNOLOGY")
	return Runtime.ok("", {"kind": "family", "owner": family, "record": record, "record_before": record.duplicate(true),
		"state": candidate, "person": executor, "person_candidate": person_candidate, "complete": complete,
		"message": "真弓已入原庫；本人試作 %d/3%s" % [Technology.stages(project, _technology_ref(int(job.executor_id)), candidate.get("person_links", [])), "，已學會 F07" if complete else ""]})

func _publish_ranged_technology_completion(prepared: Dictionary, result: Dictionary) -> void:
	# All current authority/source/phase/person candidates were checked BEFORE
	# the original Runtime batch's first inventory cost. No callback or guard.
	if prepared.kind == "scope": publish_phase_receipt(prepared.receipt)
	elif prepared.kind == "family":
		prepared.owner.technology = prepared.state
		if bool(prepared.complete): _body_set(prepared.person, "technology", prepared.person_candidate)
		result.message = str(prepared.message)

func _settle_ranged_terminal_chunk(keys: Array, first_key: String) -> Dictionary:
	# Keep the ORIGINAL ascending person-ID order and stop at every other job
	# kind/current interruption. No later cost crosses another original tail.
	var first: int = keys.find(first_key)
	if first < 0: return Runtime.fail("STALE_SOURCE")
	var jobs: Array[Dictionary] = []
	var originals: Array[Dictionary] = []
	var completions: Array[Dictionary] = []
	var selected: Array[String] = []
	var scope_owners: Array = []
	for index: int in range(first, keys.size()):
		var key: String = str(keys[index])
		var job: Dictionary = _jobs.get(key, {})
		if job.get("kind") not in ["ranged_craft", "captive_craft"] or bool(job.get("preparing", false)) or not str(job.get("paused", "")).is_empty() \
			or float(job.get("elapsed", 0.0)) < float(job.get("duration", 0.0)) - Fatigue.WORK_PLAN_EPS: break
		var checked: Dictionary = _job_context(job)
		var executor: Dictionary = _person(int(job.executor_id))
		if checked.ok and job.kind != "captive_craft" and not bool(executor.player) and _threat(executor, {}): break
		var completion: Dictionary = _prepare_ranged_technology_completion(job) if checked.ok else checked
		if not completion.ok:
			if jobs.is_empty():
				_finish(key, completion)
				return Runtime.ok("", {"keys": [key]})
			break
		# One actual active project may have only one completion candidate per
		# transaction. Its next true job is re-queried after this publication.
		var conflict: bool = false
		if not str(completion.kind).is_empty():
			for owner: Dictionary in scope_owners: conflict = conflict or is_same(owner, completion.owner)
		if conflict: break
		var original: Dictionary = Runtime.prepare_ranged_craft(lab.terrain, str(job.recipe), int(job.executor_id), job.get("technology_scope_token", {}))
		if not original.ok:
			if jobs.is_empty():
				_finish(key, original)
				return Runtime.ok("", {"keys": [key]})
			break
		selected.append(key)
		jobs.append(job)
		originals.append(original)
		completions.append(completion)
		if not str(completion.kind).is_empty(): scope_owners.append(completion.owner)
	if jobs.is_empty(): return Runtime.ok("", {"keys": []})
	var batch: Dictionary = Runtime.prepare_ranged_craft_batch(lab.terrain, originals)
	if not batch.ok:
		# Pure failure before any terminal cost. Preserve original failure order:
		# the first job reports it, later original jobs remain for re-query.
		_finish(selected[0], batch)
		return Runtime.ok("", {"keys": [selected[0]]})
	# The original equipment factory may call its original transfer guard.
	# Recheck every SAME current endpoint after that callback, still BEFORE cost.
	for index: int in jobs.size():
		var job: Dictionary = jobs[index]
		var completion: Dictionary = completions[index]
		var executor: Dictionary = _person(int(job.executor_id))
		var checked: Dictionary = _job_context(job)
		if not is_same(_jobs.get(selected[index]), job) or not checked.ok or executor.is_empty() \
			or not str(job.paused).is_empty() or float(job.elapsed) < float(job.duration) - Fatigue.WORK_PLAN_EPS \
			or job.kind != "captive_craft" and not bool(executor.player) and _threat(executor, {}):
			return Runtime.fail("STALE_SOURCE")
		if not str(completion.kind).is_empty() and (not is_same(completion.owner.get("technology"), completion.record) \
			or completion.record != completion.record_before): return Runtime.fail("STALE_PROJECT")
	if not Runtime.validate_prepared_ranged_craft_batch(batch): return Runtime.fail("STALE_SOURCE")
	var results: Array[Dictionary] = Runtime.publish_prepared_ranged_craft_batch(batch)
	for index: int in jobs.size():
		if bool(results[index].ok): _publish_ranged_technology_completion(completions[index], results[index])
		_finish(selected[index], results[index])
	return Runtime.ok("", {"keys": selected})

func prepare_gd_ranged_terminal_upper(runtime_priors: Array) -> Dictionary:
	# Only the original Lab's SAME admitted upper source array can be used.
	# These are source reservations, NEVER fabricated completed jobs/receipts.
	if _gd_contact_job_capture.is_empty() or not is_same(runtime_priors, lab.gd_mesh_work_upper_priors()): return Runtime.fail("STALE_SOURCE")
	var typed: Dictionary = _prepare_gd_typed_terminal_upper(runtime_priors)
	if not typed.ok: return typed
	var funded: Dictionary = _prepare_gd_funded_lesson_upper(runtime_priors)
	if not funded.ok: return funded
	var stock: Dictionary = lab.terrain.site.inventory
	var depot: Dictionary = lab.terrain.site.depot_items
	var available: Dictionary = stock.duplicate(true)
	var version: int = int(depot.version)
	var item_count: int = 0
	var upper: Array[Dictionary] = []
	var source_keys := {}
	var decisions: Array[Dictionary] = []
	for key: String in _gd_contact_job_capture.prepared.held:
		var held: Dictionary = _gd_contact_job_capture.prepared.held[key]
		if held.kind not in ["ranged_craft", "captive_craft"]: continue
		if float(held.duration) - float(held.elapsed) > Fatigue.WORK_PLAN_EPS and not str(held.request.get("paused", "")).is_empty():
			decisions.append({"held": held, "status": str(held.request.paused), "source": {}})
			continue # Original finite source ledger already refused this request before the planner.
		var source: Dictionary = held.get("ranged_source", {})
		if source.is_empty(): continue
		if not is_same(_jobs.get(key), held.job) or not Runtime.validate_prepared_ranged_source(source): return Runtime.fail("STALE_SOURCE")
		if float(held.duration) - float(held.elapsed) > Fatigue.WORK_PLAN_EPS:
			upper.append(source)
			source_keys[int(source.owner_id)] = key
	_gd_contact_job_capture["ranged_upper_decisions"] = decisions
	if upper.is_empty(): return Runtime.ok("本段沒有可能新增努力的製作終點；既有零工時提交另驗當前來源")
	for prior: Dictionary in runtime_priors:
		if not lab.gd_mesh_work_upper_candidate(prior): return Runtime.fail("STALE_SOURCE")
		var payment: Dictionary = prior.get("payment", {})
		if not payment.is_empty() and is_same(payment.get("cargo"), stock):
			if not Runtime.can_pay(available, payment.cost): return Runtime.fail("MATERIALS")
			Runtime.add_items(available, payment.cost, -1)
			version += 1
		# A genuinely due foreign inventory/output endpoint needs its own common
		# typed transaction. Maps or merely active ordinary work never imply it.
		if bool(prior.get("deferred_endpoint", false)):
			var collision: bool = prior.get("endpoint") == "depot"
			if prior.get("endpoint") == "feature" and prior.task.action == "operate":
				var recipe: Dictionary = Runtime.feature_recipe(prior.target)
				collision = recipe.has("asset") or is_same(prior.start.cargo, stock)
			elif prior.get("endpoint") == "resource": collision = is_same(prior.start.cargo, stock)
			if collision: return Runtime.fail("CONTACT_RANGED_RUNTIME_ENDPOINT_COLLISION")
	for source: Dictionary in upper:
		var key: String = str(source_keys[int(source.owner_id)])
		var held: Dictionary = _gd_contact_job_capture.prepared.held[key]
		if not Runtime.can_pay(available, source.cost):
			decisions.append({"held": held, "status": "MATERIALS", "source": source})
			# A genuine refused allocation has zero WORK. A positive allocation
			# here would violate the SAME original shared payment ledger, so reject
			# that stale source contract before ANY body/clock/material mutation.
			var allocation: Dictionary = lab._shared_work_plan.get("jobs", {}).get("person_actions", {}).get(key, {})
			if float(allocation.get("actual_seconds", 0.0)) > 0.0: return Runtime.fail("WORK_PAYMENT_SOURCE")
			continue
		Runtime.add_items(available, source.cost, -1)
		for resource: String in source.cost:
			if int(available[resource]) == 0: available.erase(resource)
		if source.recipe.has("asset"): item_count += 1
		else: Runtime.add_items(available, source.output)
		version += 1
		if version > 2147483646 or Runtime.carried_load(lab.terrain.site, available, depot) + item_count > float(lab.terrain.site.capacity): return Runtime.fail("CONTACT_RANGED_BATCH_CAPACITY")
		for resource: String in source.output:
			if int(available.get(resource, 0)) > 1000000: return Runtime.fail("CONTACT_RANGED_BATCH_CAPACITY")
		decisions.append({"held": held, "status": "", "source": source})
	if item_count > 0:
		var next_item: int = int(lab.terrain.site.get("next_item", 0))
		if next_item <= 0 or next_item + item_count > 2147483647: return Runtime.fail("STALE_SOURCE")
		for index: int in item_count:
			if lab.terrain.site.item_records.has(str(next_item + index)): return Runtime.fail("STALE_SOURCE")
	_gd_contact_job_capture["ranged_upper"] = upper
	return Runtime.ok("原真held營地製作有限來源上界已純核")

func gd_contact_job_person_ready(identity: int) -> bool:
	if _gd_contact_job_capture.is_empty() or not _gd_contact_job_capture.people.has(identity): return false
	var start: Dictionary = _gd_contact_job_capture.people[identity]
	var held: Dictionary = start.held
	var person: Dictionary = _person(identity)
	if not person.is_empty() and held.kind in ["technology_feature", "technology_vehicle"]:
		var team: Variant = _technology_team(person)
		if held.kind == "technology_vehicle" and (not team is TerrainArmy or not is_same(held.job.get("team_ref"), team)): return false
		if team is TerrainArmy and (team.is_sustain_routed() or team.combat_order != TerrainArmy.CombatOrder.HOLD): return false
	if not is_same(_jobs.get(str(held.key)), held.job) or person.is_empty() \
		or person.owner != start.owner or int(person.unit) != int(start.unit) or not is_same(person.body, start.body) \
		or int(person.hit) != int(start.hit) or person.cell != start.cell or bool(person.moving): return false
	if held.kind == "captive_craft":
		var supervised: Dictionary = _captive_craft_job_context(held.job)
		if not supervised.ok: return false
		if identity == int(held.job.executor_id):
			return is_same(supervised.person.body, person.body) and _captive_craft_body_ready(person)
		if identity != int(held.job.guard_id) or not is_same(supervised.supervisor.body, person.body): return false
	if held.kind not in ["technology_feature", "technology_vehicle", "captive_craft"]:
		# Re-read the SAME original job source after EACH true contact and BEFORE
		# the next planner segment. Preserve earlier accepted effort; never borrow
		# an old alive body, source version, permission or peaceful camp context.
		var current: Dictionary = _job_context(held.job)
		if not current.ok or not bool(person.player) and _threat(person, {}): return false
	return not bool(person.captive) and (person.owner.combat_can_act(int(person.unit)) if int(person.unit) >= 0 else person.owner.can_act())

func _gd_typed_terminal_kind(kind: String) -> bool:
	return kind in ["equipment", "loot", "tent_deploy", "tent_pack", "capture", "unbind", "ransom", "prison_release"]

func _gd_typed_terminal_people_ids(job: Dictionary) -> Array[int]:
	var result: Array[int] = []
	var identities: Array = []
	for field: String in ["executor_id", "target_id", "guard_id", "representative_id"]:
		if int(job.get(field, -1)) > 0: identities.append(int(job[field]))
	if job.get("order") is Dictionary:
		for identity: int in job.order.get("target_ids", []): identities.append(identity)
	if job.get("source_kind") == "person" and str(job.get("source_id", "")).is_valid_int(): identities.append(int(job.source_id))
	for identity: int in identities:
		if not result.has(identity): result.append(identity)
	return result

func _gd_typed_terminal_native(job: Dictionary) -> bool:
	for identity: int in _gd_typed_terminal_people_ids(job):
		var person: Dictionary = _person(identity, false)
		if not person.is_empty() and person.owner is CrowdOwner: return true
	return false

func _prepare_gd_typed_terminal_upper(runtime_priors: Array) -> Dictionary:
	if _gd_contact_job_capture.is_empty() or not is_same(runtime_priors, lab.gd_mesh_work_upper_priors()): return Runtime.fail("STALE_SOURCE")
	var keys: Array = _gd_contact_job_capture.prepared.held.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return int(a) < int(b))
	for key: String in keys:
		var held: Dictionary = _gd_contact_job_capture.prepared.held[key]
		var source: Dictionary = held.get("typed_source", {})
		if source.is_empty(): continue
		if not is_same(source.get("job"), held.job) or source.get("source_only") != true: return Runtime.fail("STALE_SOURCE")
		var checked: Dictionary = validate_gd_typed_terminal(source, false)
		if not checked.ok: return checked
	# This upper reader certifies real current source facts only. It does not
	# publish, reserve a fabricated future holder version, or promise a receipt.
	# Every original numeric endpoint obtains a fresh complete transaction after
	# actual prior endpoints/contact before its own first debit. Refusal leaves
	# no material mutation and does not undo the already accepted work prefix.
	return Runtime.ok("原真typed作業來源已在首成本前核；當前端點另作真交易")

func prepare_gd_typed_terminal(job: Dictionary, source_only: bool = false) -> Dictionary:
	# This source reader always starts with the SAME original job. A source
	# preview is not an elapsed timer, completed receipt or permission grant.
	var key: String = str(int(job.get("executor_id", -1)))
	var kind: String = str(job.get("kind", ""))
	if not _gd_typed_terminal_kind(kind) or not is_same(_jobs.get(key), job) or bool(job.get("preparing", false)) or _gd_typed_terminal_native(job):
		return Runtime.fail("STALE_SOURCE")
	if not source_only and (not str(job.get("paused", "")).is_empty() or not Technology.finite_number(job.get("elapsed")) \
		or not Technology.finite_number(job.get("duration")) or float(job.elapsed) + Fatigue.WORK_PLAN_EPS < float(job.duration)):
		return Runtime.fail("NOT_COMPLETED")
	var context: Dictionary = _job_context(job)
	if not context.ok: return context
	var executor: Dictionary = _person(int(job.executor_id))
	if executor.is_empty() or executor.owner is CrowdOwner: return Runtime.fail("UNSUPPORTED", "原GD完成交易不替代Native人物owner")
	var people: Array[Dictionary] = []
	for identity: int in _gd_typed_terminal_people_ids(job):
		var person: Dictionary = _person(identity)
		if person.is_empty() or person.owner is CrowdOwner: return Runtime.fail("STALE_SOURCE")
		people.append(_gd_custody_person_snapshot(person))
	var prepared: Dictionary = Runtime.ok("原真作業來源候選；尚未付款或發物", {"owner": self, "job": job,
		"job_before": job.duplicate(true), "kind": kind, "people": people, "source_only": source_only, "runtime": {}, "equipment": {}, "food": {}, "custody": {}, "original_owner": 0, "published": false})
	match kind:
		"equipment":
			prepared.equipment = equipment_orders.prepare_team_equipment_change(job.order, source_only) if job.order.mode == "team_issue" else equipment_orders.prepare_equipment_change(job.order, source_only)
			if not prepared.equipment.ok: return prepared.equipment
		"loot":
			var source: Dictionary = _source(str(job.source_kind), str(job.source_id))
			prepared.original_owner = int(source.get("person_id", source.holder.get("original_owner", 0)))
			prepared.runtime = Runtime.prepare_loot_transfer(lab.terrain, source.holder, source.cargo, executor.holder, executor.cargo,
				job.resources, job.item_ids, int(job.source_version), int(job.destination_version), float(job.open_amount))
			if not prepared.runtime.ok: return prepared.runtime
			if float(job.open_amount) > 0.0:
				# A custom callback is not evidence that the original Supply owner
				# has accepted a pure, failure-free destination transaction.
				if opened_food_pool != Callable(lab.site_controller, "_personal_opened_food") \
					or opened_food_commit != Callable(lab.site_controller, "_receive_opened_food"): return Runtime.fail("UNSUPPORTED", "原開封餐份owner未接純提交")
				prepared.food = lab.site_controller.prepare_received_opened_food(int(job.executor_id), float(job.open_amount), job.destination_pool, source_only)
				if not prepared.food.ok: return prepared.food
		"tent_deploy":
			prepared.runtime = Runtime.prepare_deploy_tent(lab.terrain, job.cells, executor.cargo, executor.holder, int(job.executor_version), executor.cell, int(executor.faction), _tent_occupied, int(job.quarter))
			if not prepared.runtime.ok: return prepared.runtime
		"tent_pack":
			prepared.runtime = Runtime.prepare_pack_tent(lab.terrain, str(job.feature), executor.cargo, executor.holder, int(job.executor_version), executor.cell, int(executor.faction), _tent_occupied)
			if not prepared.runtime.ok: return prepared.runtime
		_:
			prepared.custody = prepare_gd_custody_terminal(job, source_only)
			if not prepared.custody.ok: return prepared.custody
	var checked: Dictionary = validate_gd_typed_terminal(prepared, not source_only)
	return prepared if checked.ok else checked

func validate_gd_typed_terminal(prepared: Dictionary, require_completion: bool = true) -> Dictionary:
	if prepared.get("ok") != true or prepared.get("owner") != self or prepared.get("published") != false \
		or not prepared.get("source_only") is bool or require_completion and bool(prepared.get("source_only", true)) \
		or not prepared.get("job") is Dictionary or not prepared.get("job_before") is Dictionary \
		or not prepared.get("people") is Array \
		or not prepared.get("runtime") is Dictionary or not prepared.get("equipment") is Dictionary \
		or not prepared.get("food") is Dictionary or not prepared.get("custody") is Dictionary: return Runtime.fail("STALE_SOURCE")
	var job: Dictionary = prepared.get("job", {})
	var key: String = str(int(job.get("executor_id", -1)))
	var kind: String = str(job.get("kind", ""))
	if not _gd_typed_terminal_kind(kind) or kind != prepared.get("kind") or not is_same(_jobs.get(key), job) or job != prepared.get("job_before"):
		return Runtime.fail("STALE_SOURCE")
	if require_completion and (not str(job.get("paused", "")).is_empty() or not Technology.finite_number(job.get("elapsed")) \
		or not Technology.finite_number(job.get("duration")) or float(job.elapsed) + Fatigue.WORK_PLAN_EPS < float(job.duration)):
		return Runtime.fail("NOT_COMPLETED")
	var identities: Array[int] = _gd_typed_terminal_people_ids(job)
	if prepared.people.size() != identities.size(): return Runtime.fail("STALE_SOURCE")
	for index: int in identities.size():
		var snapshot: Variant = prepared.people[index]
		if not snapshot is Dictionary or int(snapshot.get("person", {}).get("person_id", -1)) != identities[index] \
			or not _gd_custody_person_matches(snapshot): return Runtime.fail("STALE_SOURCE")
	var checked: Dictionary = _job_context(job)
	if not checked.ok: return checked
	var executor: Dictionary = _person(int(job.executor_id))
	if executor.is_empty() or executor.owner is CrowdOwner: return Runtime.fail("UNSUPPORTED")
	if require_completion and not bool(executor.player) and _threat(executor, {}): return Runtime.fail("THREAT")
	match kind:
		"equipment":
			if not is_same(prepared.get("equipment", {}).get("order"), job.get("order")) or prepared.equipment.get("source_only") != prepared.source_only \
				or not prepared.runtime.is_empty() or not prepared.food.is_empty() or not prepared.custody.is_empty(): return Runtime.fail("INVALID")
			checked = equipment_orders.validate_team_equipment_change(prepared.equipment, require_completion) if job.order.mode == "team_issue" else equipment_orders.validate_equipment_change(prepared.equipment, require_completion)
		"loot":
			var source: Dictionary = _source(str(job.source_kind), str(job.source_id))
			var original: Dictionary = prepared.get("runtime", {})
			if source.is_empty() or not is_same(original.get("source"), source.get("holder")) or not is_same(original.get("source_cargo"), source.get("cargo")) \
				or not is_same(original.get("destination"), executor.holder) or not is_same(original.get("destination_cargo"), executor.cargo) \
				or not is_same(original.get("terrain"), lab.terrain) or not is_same(original.get("site_state"), lab.terrain.site) \
				or original.get("resources") != job.resources or original.get("item_ids") != job.item_ids or original.get("open_amount") != job.open_amount \
				or int(original.get("source_version", -1)) != int(job.source_version) or int(original.get("destination_version", -1)) != int(job.destination_version) \
				or int(original.get("capacity", -1)) != Runtime.CARRY_CAPACITY or int(prepared.get("original_owner", -1)) != int(source.get("person_id", source.holder.get("original_owner", 0))) \
				or not prepared.equipment.is_empty() or not prepared.custody.is_empty(): return Runtime.fail("INVALID")
			if float(job.open_amount) > 0.0:
				if prepared.food.get("owner") != lab.site_controller or int(prepared.food.get("identity", -1)) != int(job.executor_id) \
					or prepared.food.get("amount") != job.open_amount or prepared.food.get("source_only") != prepared.source_only \
					or (not job.destination_pool.is_empty() or not prepared.food.get("original", {}).is_empty()) and not is_same(prepared.food.get("original"), job.destination_pool): return Runtime.fail("INVALID")
			elif not prepared.food.is_empty(): return Runtime.fail("INVALID")
			checked = Runtime.validate_prepared_loot_transfer(original)
			if not checked.ok: return checked
			# The original item transfer guard can be a callback. Its source CAS
			# completes before the destination food owner's final pure recheck.
			if not prepared.food.is_empty(): checked = lab.site_controller.validate_received_opened_food(prepared.food, require_completion)
		"tent_deploy":
			var original: Dictionary = prepared.get("runtime", {})
			if not is_same(original.get("cargo"), executor.cargo) or not is_same(original.get("holder"), executor.holder) \
				or not is_same(original.get("terrain"), lab.terrain) or not is_same(original.get("site_state"), lab.terrain.site) \
				or original.get("cells") != job.cells or int(original.get("expected_version", -1)) != int(job.executor_version) \
				or original.get("actor_cell") != executor.cell or int(original.get("quarter", -1)) != int(job.quarter) \
				or int(original.get("owner_faction", -1)) != int(executor.faction) or original.get("occupied") != Callable(self, "_tent_occupied") \
				or not prepared.equipment.is_empty() or not prepared.food.is_empty() or not prepared.custody.is_empty(): return Runtime.fail("INVALID")
			checked = Runtime.validate_prepared_deploy_tent(original)
		"tent_pack":
			var original: Dictionary = prepared.get("runtime", {})
			if not is_same(original.get("cargo"), executor.cargo) or not is_same(original.get("holder"), executor.holder) \
				or not is_same(original.get("terrain"), lab.terrain) or not is_same(original.get("site_state"), lab.terrain.site) \
				or original.get("key") != job.feature or int(original.get("expected_version", -1)) != int(job.executor_version) \
				or original.get("actor_cell") != executor.cell or not is_same(original.get("feature"), job.feature_owner) \
				or int(original.get("owner_faction", -1)) != int(executor.faction) or int(original.get("capacity", -1)) != Runtime.CARRY_CAPACITY \
				or original.get("occupied") != Callable(self, "_tent_occupied") \
				or not prepared.equipment.is_empty() or not prepared.food.is_empty() or not prepared.custody.is_empty(): return Runtime.fail("INVALID")
			checked = Runtime.validate_prepared_pack_tent(original)
		_:
			if not is_same(prepared.get("custody", {}).get("job"), job) or prepared.custody.get("source_only") != prepared.source_only \
				or not prepared.equipment.is_empty() or not prepared.food.is_empty() or not prepared.runtime.is_empty(): return Runtime.fail("INVALID")
			# Root's original Supply change guard cache is refreshed LAST here;
			# no later owner callback or old cached plan may cross its publication.
			checked = validate_gd_custody_terminal(prepared.custody)
	if not checked.ok: return checked
	# The original owner validators above may invoke genuine admission
	# callbacks. Only direct SAME-job scalar/ref comparison follows them.
	if not is_same(_jobs.get(key), job) or job != prepared.job_before: return Runtime.fail("STALE_SOURCE")
	for snapshot: Dictionary in prepared.people:
		if not _gd_custody_person_matches(snapshot): return Runtime.fail("STALE_SOURCE")
	return Runtime.ok()

func publish_gd_typed_terminal(prepared: Dictionary) -> Dictionary:
	assert(prepared.ok and prepared.owner == self and not prepared.source_only and not prepared.published)
	var job: Dictionary = prepared.job
	var result: Dictionary = Runtime.ok()
	match str(prepared.kind):
		"equipment":
			if job.order.mode == "team_issue": equipment_orders.publish_team_equipment_change(prepared.equipment)
			else: equipment_orders.publish_equipment_change(prepared.equipment)
			result = prepared.equipment.result
		"loot":
			result = Runtime.publish_prepared_loot_transfer(prepared.runtime)
			if not prepared.food.is_empty(): lab.site_controller.publish_received_opened_food(prepared.food)
			if not prepared.runtime.cleanup.is_empty():
				Runtime.publish_prepared_clear_empty_ground_loot(prepared.runtime.cleanup)
				Runtime.notify_cleared_ground_loot(prepared.runtime.cleanup)
			var original_owner: int = int(prepared.original_owner)
			if original_owner > 0 and equipment_changed.is_valid(): equipment_changed.call(original_owner)
			if equipment_changed.is_valid(): equipment_changed.call(int(job.executor_id))
		"tent_deploy": result = Runtime.publish_prepared_deploy_tent(prepared.runtime)
		"tent_pack": result = Runtime.publish_prepared_pack_tent(prepared.runtime)
		_: result = publish_gd_custody_terminal(prepared.custody)
	prepared.published = true
	return result

func _commit_gd_typed_terminal(job: Dictionary) -> Dictionary:
	var prepared: Dictionary = prepare_gd_typed_terminal(job)
	if not prepared.ok: return prepared
	var checked: Dictionary = validate_gd_typed_terminal(prepared)
	return publish_gd_typed_terminal(prepared) if checked.ok else checked

func _gd_custody_native(job: Dictionary) -> bool:
	for field: String in ["executor_id", "target_id", "guard_id", "representative_id"]:
		var identity: int = int(job.get(field, -1))
		if identity < 0: continue
		var person: Dictionary = _person(identity, false)
		if not person.is_empty() and person.owner is CrowdOwner: return true
	return false

func _gd_custody_job_signature(job: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for field: String in ["kind", "executor_id", "target_id", "guard_id", "representative_id", "executor_hit", "executor_cell", "target_hit", "source_cell", "executor_hp", "target_hp", "source_version", "duration", "elapsed", "paused", "preparing", "captivity", "resources", "representative_hit", "representative_cell", "source_owner", "destination_owner", "source_revision", "destination_revision", "source_stock"]:
		if job.has(field): result[field] = job[field]
	return result.duplicate(true)

func _gd_custody_person_snapshot(person: Dictionary) -> Dictionary:
	return {"person": person, "holder_before": person.holder.duplicate(true), "cargo_before": person.cargo.duplicate(true),
		"physical": {"person_id": int(person.person_id), "unit": int(person.unit), "cell": person.cell, "hit": int(person.hit),
			"hp": float(person.hp), "ko": float(person.ko), "moving": bool(person.moving), "captive": bool(person.captive),
			"surrender_pending": bool(person.surrender_pending), "faction": int(person.faction)}}

func _gd_custody_person_matches(snapshot: Dictionary) -> bool:
	var original: Dictionary = snapshot.get("person", {})
	if original.is_empty(): return false
	var person: Dictionary = _person(int(original.person_id))
	if person.is_empty() or person.owner is CrowdOwner or not is_same(person.owner, original.owner) \
		or not is_same(person.body, original.body) or not is_same(person.holder, original.holder) or not is_same(person.cargo, original.cargo) \
		or person.holder != snapshot.holder_before or person.cargo != snapshot.cargo_before: return false
	return _gd_custody_person_snapshot(person).physical == snapshot.physical

func _gd_custody_capture_fields(sequence: int) -> Dictionary:
	# Projection of new_capture_fields at the CURRENT clock only. No sequence
	# is drawn until this actual endpoint publishes; an upper source is not
	# a completed capture or an admission/research witness.
	return {"captured_at_game_seconds": Runtime.now(lab.terrain) * 60.0, "admitted_at_game_seconds": -1.0,
		"episode": "%s:%d" % [str(lab.terrain.site.get("id", "")), sequence], "legacy_observed": false}

func _gd_custody_ransom_resources(stock: Dictionary) -> Dictionary:
	var selected: Dictionary = {}
	var left: int = RANSOM_RATIONS
	for food: String in FOODS:
		var quantity: int = mini(left, int(stock.get(food, 0)))
		if quantity > 0: selected[food] = quantity
		left -= quantity
	return selected if left == 0 else {}

func prepare_gd_custody_terminal(job: Dictionary, source_only: bool = false) -> Dictionary:
	if job.get("kind") not in ["capture", "unbind", "ransom", "prison_release"] or _gd_custody_native(job): return Runtime.fail("UNSUPPORTED")
	if not is_same(_jobs.get(str(int(job.get("executor_id", -1))), {}), job) \
		or bool(lab.terrain.site.get("paused", false)) or not str(job.get("paused", "")).is_empty() and (not source_only or str(job.paused) != "REST") \
		or bool(job.get("preparing", false)) or not Technology.finite_number(job.get("elapsed")) \
		or not Technology.finite_number(job.get("duration")) \
		or not source_only and float(job.elapsed) + Fatigue.WORK_PLAN_EPS < float(job.duration): return Runtime.fail("STALE_SOURCE")
	var check: Dictionary = _job_context(job)
	if not check.ok: return check
	var executor: Dictionary = _person(int(job.executor_id))
	var target: Dictionary = _person(int(job.target_id))
	if executor.is_empty() or target.is_empty() or int(target.holder.version) >= 2147483646: return Runtime.fail("STALE_SOURCE")
	var site: Dictionary = lab.terrain.site
	var people: Array[Dictionary] = []
	var seen: Dictionary = {}
	for field: String in ["executor_id", "target_id", "guard_id", "representative_id"]:
		var identity: int = int(job.get(field, -1))
		if identity < 0 or seen.has(identity): continue
		var person: Dictionary = _person(identity)
		if person.is_empty() or person.owner is CrowdOwner: return Runtime.fail("STALE_SOURCE")
		seen[identity] = true
		people.append(_gd_custody_person_snapshot(person))
	var capturing: bool = job.kind == "capture"
	var relation: Dictionary = site.captivity.get(str(job.target_id), {})
	var captor_id: int = int(job.executor_id) if capturing else int(relation.get("captor_id", -1))
	var prepared: Dictionary = Runtime.ok("原GD拘押完成來源已純核", {"job": job, "job_signature": _gd_custody_job_signature(job),
		"terrain": lab.terrain, "site_state": site, "captivity": site.captivity, "relation": relation,
		"relation_before": relation.duplicate(true), "executor": executor, "target": target, "people": people,
		"capturing": capturing, "captor_id": captor_id, "sealed": {}, "loot": {}, "container_id": "",
		"query": {}, "source_before": {}, "destination_before": {}, "sequence": -1,
		"next_relation": {}, "source_only": source_only, "published": false})
	if capturing:
		var sequence: Variant = site.get("capture_episode_next", 1)
		if not sequence is int or int(sequence) < 1 or int(sequence) >= 2147483647: return Runtime.fail("STALE_SOURCE")
		prepared.sequence = int(sequence)
		prepared.sealed = _sealed_selection(target)
		if not prepared.sealed.resources.is_empty() or not prepared.sealed.item_ids.is_empty():
			prepared.loot = Runtime.prepare_leave_ground_loot(lab.terrain, target.holder, target.cargo, int(job.target_id), target.cell,
				"sealed", prepared.sealed.resources, prepared.sealed.item_ids, int(job.source_version))
			if not prepared.loot.ok: return prepared.loot
			prepared.container_id = str(prepared.loot.identity)
		prepared.next_relation = {"version": 3, "captor_id": captor_id, "guard_id": int(job.guard_id),
			"captor_faction": int(executor.faction), "sealed_container": prepared.container_id, "prison_id": ""}
		prepared.next_relation.merge(_gd_custody_capture_fields(int(prepared.sequence)))
	elif job.kind == "ransom":
		prepared.query = _ransom_context(executor, target, _person(int(job.representative_id)))
		if not prepared.query.ok: return prepared.query
		prepared.source_before = prepared.query.source.duplicate(true)
		prepared.destination_before = prepared.query.destination.duplicate(true)
	var stable: Dictionary = validate_gd_custody_terminal(prepared)
	return prepared if stable.ok else stable

func validate_gd_custody_terminal(prepared: Dictionary) -> Dictionary:
	if prepared.get("ok") != true or prepared.get("published") != false or not prepared.get("source_only") is bool \
		or not is_same(prepared.get("terrain"), lab.terrain) or not is_same(prepared.get("site_state"), lab.terrain.site): return Runtime.fail("STALE_SOURCE")
	var job: Dictionary = prepared.get("job", {})
	if job.get("kind") not in ["capture", "unbind", "ransom", "prison_release"] or _gd_custody_native(job) \
		or not is_same(_jobs.get(str(int(job.get("executor_id", -1))), {}), job) \
		or bool(lab.terrain.site.get("paused", false)) or _gd_custody_job_signature(job) != prepared.get("job_signature") \
		or not str(job.get("paused", "")).is_empty() and (not bool(prepared.source_only) or str(job.paused) != "REST") or bool(job.get("preparing", false)) \
		or not Technology.finite_number(job.get("elapsed")) or not Technology.finite_number(job.get("duration")) \
		or not bool(prepared.source_only) and float(job.elapsed) + Fatigue.WORK_PLAN_EPS < float(job.duration): return Runtime.fail("STALE_SOURCE")
	var site: Dictionary = lab.terrain.site
	var executor: Dictionary = _person(int(job.executor_id))
	var target: Dictionary = _person(int(job.target_id))
	var capturing: bool = job.kind == "capture"
	var relation: Dictionary = site.captivity.get(str(job.target_id), {})
	if not is_same(site.captivity, prepared.captivity) or executor.is_empty() or target.is_empty() \
		or not is_same(executor.body, prepared.executor.body) or not is_same(target.body, prepared.target.body) \
		or not is_same(executor.owner, prepared.executor.owner) or not is_same(target.owner, prepared.target.owner) \
		or not is_same(executor.holder, prepared.executor.holder) or not is_same(target.holder, prepared.target.holder) \
		or not is_same(executor.cargo, prepared.executor.cargo) or not is_same(target.cargo, prepared.target.cargo) \
		or _gd_custody_person_snapshot(executor).physical != _gd_custody_person_snapshot(prepared.executor).physical \
		or _gd_custody_person_snapshot(target).physical != _gd_custody_person_snapshot(prepared.target).physical \
		or capturing != bool(prepared.capturing) or int(target.holder.version) >= 2147483646 \
		or relation != prepared.relation_before or not capturing and not is_same(relation, prepared.relation): return Runtime.fail("STALE_SOURCE")
	var captor_id: int = int(job.executor_id) if capturing else int(relation.get("captor_id", -1))
	if captor_id != int(prepared.captor_id): return Runtime.fail("STALE_SOURCE")
	var expected_ids: Array[int] = []
	for field: String in ["executor_id", "target_id", "guard_id", "representative_id"]:
		var identity: int = int(job.get(field, -1))
		if identity >= 0 and not expected_ids.has(identity): expected_ids.append(identity)
	if not prepared.get("people") is Array or prepared.people.size() != expected_ids.size(): return Runtime.fail("INVALID")
	for index: int in range(expected_ids.size()):
		if not prepared.people[index] is Dictionary or int(prepared.people[index].get("person", {}).get("person_id", -1)) != expected_ids[index]: return Runtime.fail("INVALID")
	if capturing:
		if int(site.get("capture_episode_next", 1)) != int(prepared.sequence) or prepared.sealed != _sealed_selection(target): return Runtime.fail("STALE_SOURCE")
		var loot: Dictionary = prepared.loot
		if prepared.sealed.resources.is_empty() and prepared.sealed.item_ids.is_empty():
			if not loot.is_empty() or not str(prepared.container_id).is_empty(): return Runtime.fail("INVALID")
		else:
			if not is_same(loot.get("terrain"), lab.terrain) or not is_same(loot.get("site_state"), site) \
				or not is_same(loot.get("source"), target.holder) or not is_same(loot.get("source_cargo"), target.cargo) \
				or str(loot.get("identity", "")) != str(prepared.container_id) \
				or loot.get("kind") != "sealed" or int(loot.get("original_owner", -1)) != int(job.target_id) \
				or loot.get("cell") != target.cell or loot.get("resources") != prepared.sealed.resources \
				or loot.get("item_ids") != prepared.sealed.item_ids: return Runtime.fail("INVALID")
			var checked_loot: Dictionary = Runtime.validate_prepared_leave_ground_loot(loot)
			if not checked_loot.ok: return checked_loot
		var expected: Dictionary = {"version": 3, "captor_id": captor_id, "guard_id": int(job.guard_id),
			"captor_faction": int(executor.faction), "sealed_container": str(prepared.container_id), "prison_id": ""}
		expected.merge(_gd_custody_capture_fields(int(prepared.sequence)))
		if prepared.next_relation != expected: return Runtime.fail("INVALID")
	elif job.kind == "ransom":
		var query: Dictionary = _ransom_context(executor, target, _person(int(job.representative_id)))
		if not query.ok: return query
		var held: Dictionary = prepared.query
		if not is_same(query.source, held.get("source")) or not is_same(query.destination, held.get("destination")) \
			or not is_same(query.source_entry, held.get("source_entry")) or not is_same(query.destination_entry, held.get("destination_entry")) \
			or query.source != prepared.source_before or query.destination != prepared.destination_before \
			or query.source_owner != held.source_owner or query.destination_owner != held.destination_owner \
			or int(query.source_revision) != int(held.source_revision) or int(query.destination_revision) != int(held.destination_revision) \
			or int(query.source_revision) >= 2147483646 or int(query.destination_revision) >= 2147483646 \
			or job.resources != _gd_custody_ransom_resources(query.source) or not Runtime.can_pay(query.source, job.resources): return Runtime.fail("STALE_SOURCE")
		var after: Dictionary = query.destination.duplicate(true)
		Runtime.add_items(after, job.resources)
		if not Runtime._resource_stack(after): return Runtime.fail("STORAGE_FULL")
	# Original source guards can call original owners. The final successful
	# guard must be the SAME current supply plan: that owner intentionally
	# retains only its latest prepared change. No other candidate or callback
	# may run between this validation and its synchronous publication.
	var current: Dictionary = _job_context(job)
	if not current.ok: return current
	var supply: Dictionary = captivity_change_guard.call(int(job.target_id), captor_id, capturing)
	if not supply.ok: return supply
	if not is_same(_jobs.get(str(int(job.executor_id)), {}), job) or _gd_custody_job_signature(job) != prepared.job_signature \
		or not is_same(lab.terrain, prepared.terrain) or not is_same(lab.terrain.site, prepared.site_state) \
		or not is_same(site.captivity, prepared.captivity) or site.captivity.get(str(job.target_id), {}) != prepared.relation_before: return Runtime.fail("STALE_SOURCE")
	if capturing and (int(site.get("capture_episode_next", 1)) != int(prepared.sequence) \
		or prepared.sealed != _sealed_selection(_person(int(job.target_id))) \
		or prepared.next_relation.get("captured_at_game_seconds") != Runtime.now(lab.terrain) * 60.0): return Runtime.fail("STALE_SOURCE")
	for person: Dictionary in prepared.people:
		if not _gd_custody_person_matches(person): return Runtime.fail("STALE_SOURCE")
	if capturing and not prepared.loot.is_empty():
		var final_loot: Dictionary = Runtime.validate_prepared_leave_ground_loot(prepared.loot)
		if not final_loot.ok: return final_loot
	if job.kind == "ransom" and (prepared.query.source != prepared.source_before or prepared.query.destination != prepared.destination_before \
		or int(prepared.query.source_entry.revision) != int(prepared.query.source_revision) \
		or int(prepared.query.destination_entry.revision) != int(prepared.query.destination_revision) \
		or not is_same(site.get("team_supply", {}).get(str(prepared.query.source_owner).get_slice(":", 1)), prepared.query.source_entry) \
		or not is_same(site.get("team_supply", {}).get(str(prepared.query.destination_owner).get_slice(":", 1)), prepared.query.destination_entry)): return Runtime.fail("STALE_SOURCE")
	return Runtime.ok()

func publish_gd_custody_terminal(prepared: Dictionary) -> Dictionary:
	assert(prepared.ok and not prepared.source_only and not prepared.published)
	var job: Dictionary = prepared.job
	var target: Dictionary = prepared.target
	if job.kind == "ransom":
		Runtime.add_items(prepared.query.source, job.resources, -1)
		for resource: String in prepared.query.source.keys():
			if int(prepared.query.source[resource]) == 0: prepared.query.source.erase(resource)
		Runtime.add_items(prepared.query.destination, job.resources)
		ransom_exchange_committed.call(prepared.query)
	if prepared.capturing:
		if not prepared.loot.is_empty(): Runtime.publish_prepared_leave_ground_loot(prepared.loot)
		prepared.site_state.capture_episode_next = int(prepared.sequence) + 1
		prepared.next_relation.merge(capture_fields(int(job.target_id), target), true)
		prepared.captivity[str(job.target_id)] = prepared.next_relation
	else:
		_social_before_release(int(job.target_id), target, str(job.kind) == "ransom")
		prepared.captivity.erase(str(job.target_id))
	_body_set(target, "captive", bool(prepared.capturing))
	if prepared.capturing and bool(target.surrender_pending): _body_set(target, "surrender_pending", false)
	target.holder.version = int(target.holder.version) + 1
	captivity_supply_commit.call(int(job.target_id), int(prepared.captor_id), bool(prepared.capturing))
	prepared.published = true
	if equipment_changed.is_valid(): equipment_changed.call(int(job.target_id))
	captivity_changed.call(int(job.target_id), int(prepared.captor_id), bool(prepared.capturing))
	return Runtime.ok("已出監解綁；生命、昏迷、位置與實物維持原值" if job.kind == "prison_release" else ("已拘束；封存物留在原地" if prepared.capturing else "已解綁；生命與昏迷不變"), {"container_id": str(prepared.container_id)})

func _commit_gd_custody_terminal(job: Dictionary) -> Dictionary:
	var prepared: Dictionary = prepare_gd_custody_terminal(job)
	if not prepared.ok: return prepared
	var current: Dictionary = validate_gd_custody_terminal(prepared)
	if not current.ok: return current
	return publish_gd_custody_terminal(prepared)

func _prepare_technology_lesson_completion(job: Dictionary) -> Dictionary:
	if not is_same(_jobs.get(str(int(job.get("executor_id", -1))), {}), job) or job.get("kind") != "technology_lesson" \
		or not str(job.get("paused", "")).is_empty() or not Technology.finite_number(job.get("duration"), 300.0) \
		or not Technology.finite_number(job.get("elapsed")) or float(job.elapsed) + Fatigue.WORK_PLAN_EPS < float(job.duration): return Runtime.fail("STALE_COURSE")
	var check: Dictionary = _technology_lesson_context(job)
	if not check.ok: return check
	var family: Dictionary = _technology_family()
	var record: Dictionary = family.technology
	var candidate: Dictionary = record.duplicate(true)
	var tech_id: String = str(job.get("technology_id", "F07"))
	var student: Dictionary = _person(int(job.target_id))
	var previous: Dictionary = _body_get(student, "technology")
	var learned: Dictionary = Technology.learned_candidate(previous, tech_id)
	if learned.is_empty(): return Runtime.fail("INVALID_TECHNOLOGY")
	candidate = _technology_lesson_family_candidate(record, job)
	if candidate.is_empty(): return Runtime.fail("INVALID_TECHNOLOGY")
	var prepared: Dictionary = Runtime.ok("", {"job": job, "family": family, "record": record, "record_before": record.duplicate(true),
		"state": candidate, "student": student, "previous": previous.duplicate(true), "learned": learned, "funding": {}, "phase_before": {}, "published": false})
	prepared.funding = prepare_nation_funded_lesson(job, learned)
	if not prepared.funding.ok: return prepared.funding
	if not prepared.funding.phase.is_empty(): prepared.phase_before = prepared.funding.phase.record.duplicate(true)
	var stable: Dictionary = _validate_technology_lesson_completion(prepared)
	return prepared if stable.ok else stable

func _validate_technology_lesson_completion(prepared: Dictionary) -> Dictionary:
	if prepared.get("ok") != true or prepared.get("published") != false: return Runtime.fail("STALE_COURSE")
	var job: Dictionary = prepared.get("job", {})
	if not is_same(_jobs.get(str(int(job.get("executor_id", -1))), {}), job) or not str(job.get("paused", "")).is_empty() \
		or not Technology.finite_number(job.get("elapsed")) or float(job.elapsed) + Fatigue.WORK_PLAN_EPS < float(job.duration): return Runtime.fail("STALE_COURSE")
	var check: Dictionary = _technology_lesson_context(job)
	if not check.ok: return check
	var family: Dictionary = _technology_family()
	var student: Dictionary = _person(int(job.target_id))
	if not is_same(family, prepared.family) or not is_same(family.get("technology"), prepared.record) or prepared.record != prepared.record_before \
		or student.is_empty() or not is_same(student.body, prepared.student.body) or _body_get(student, "technology") != prepared.previous \
		or prepared.state != _technology_lesson_family_candidate(prepared.record, job) or prepared.learned != Technology.learned_candidate(prepared.previous, str(job.get("technology_id", "F07"))): return Runtime.fail("STALE_PROJECT")
	var funding: Dictionary = prepared.funding
	if not funding.payment.is_empty():
		var paid: Dictionary = equipment_orders.validate_funded_course_payment(funding.payment)
		if not paid.ok: return paid
	# A schema-valid packet is not proof of THIS actual completed lesson. Requery
	# the true named course/payment/event and compare its exact derived Scope
	# payload; a caller cannot substitute other legal knowledge/history.
	var expected: Dictionary = prepare_nation_funded_lesson(job, prepared.learned)
	if not expected.ok: return expected
	if funding.phase.is_empty() != expected.phase.is_empty() or funding.payment.is_empty() != expected.payment.is_empty(): return Runtime.fail("INVALID_RECEIPT")
	if not funding.phase.is_empty():
		var phase: Dictionary = funding.phase
		var actual: Dictionary = expected.phase
		if not is_same(phase.site_state, lab.terrain.site) or not is_same(phase.owner.get("technology"), phase.record) \
			or phase.record != prepared.phase_before or not is_same(phase.owner, actual.owner) or not is_same(phase.record, actual.record) \
			or not is_same(phase.person.body, actual.person.body) or phase.state != actual.state \
			or phase.person_candidate != actual.person_candidate or phase.complete != actual.complete: return Runtime.fail("INVALID_RECEIPT")
	# The original transfer guard inside the requery can call original owners;
	# after it, recheck all old held endpoints before the first material cost.
	check = _technology_lesson_context(job)
	if not check.ok: return check
	family = _technology_family()
	student = _person(int(job.target_id))
	if not is_same(_jobs.get(str(int(job.executor_id)), {}), job) or not is_same(family, prepared.family) \
		or not is_same(family.get("technology"), prepared.record) or prepared.record != prepared.record_before \
		or student.is_empty() or not is_same(student.body, prepared.student.body) or _body_get(student, "technology") != prepared.previous \
		or not str(job.get("paused", "")).is_empty() or float(job.elapsed) + Fatigue.WORK_PLAN_EPS < float(job.duration): return Runtime.fail("STALE_PROJECT")
	if not funding.payment.is_empty():
		var paid: Dictionary = equipment_orders.validate_funded_course_payment(funding.payment)
		if not paid.ok: return paid
	return Runtime.ok()

func _publish_technology_lesson_completion(prepared: Dictionary) -> void:
	assert(prepared.ok and not prepared.published)
	var funding: Dictionary = prepared.funding
	if not funding.payment.is_empty(): equipment_orders.publish_funded_course_payment(funding.payment)
	prepared.family.technology = prepared.state
	_body_set(prepared.student, "technology", prepared.learned)
	if not funding.phase.is_empty(): publish_phase_receipt(funding.phase)
	prepared.published = true

func _prepare_gd_funded_lesson_upper(runtime_priors: Array) -> Dictionary:
	if _gd_contact_job_capture.is_empty() or not is_same(runtime_priors, lab.gd_mesh_work_upper_priors()): return Runtime.fail("STALE_SOURCE")
	var sources: Array[Dictionary] = []
	var available: Array[Dictionary] = []
	for key: String in _gd_contact_job_capture.prepared.held:
		var held: Dictionary = _gd_contact_job_capture.prepared.held[key]
		var source: Dictionary = held.get("funded_source", {})
		if source.is_empty(): continue
		var valid: Dictionary = equipment_orders.validate_funded_course_source(source)
		if not is_same(_jobs.get(key), held.job) or not valid.ok: return valid if not valid.ok else Runtime.fail("STALE_COURSE")
		var found: int = -1
		for index: int in sources.size():
			if is_same(sources[index].source_cargo, source.source_cargo): found = index
		if found < 0:
			found = sources.size()
			sources.append(source)
			available.append(source.source_cargo.duplicate(true))
			for prior: Dictionary in runtime_priors:
				if not lab.gd_mesh_work_upper_candidate(prior): return Runtime.fail("STALE_SOURCE")
				var payment: Dictionary = prior.get("payment", {})
				if not payment.is_empty() and is_same(payment.get("cargo"), source.source_cargo):
					if not Runtime.can_pay(available[found], payment.cost): return Runtime.fail("MATERIALS")
					Runtime.add_items(available[found], payment.cost, -1)
		for prior: Dictionary in runtime_priors:
			if bool(prior.get("deferred_endpoint", false)) and (is_same(prior.start.get("cargo"), source.source_cargo) \
				or is_same(prior.start.get("cargo"), source.destination_cargo)): return Runtime.fail("CONTACT_FUNDED_RUNTIME_ENDPOINT_COLLISION")
		if not Runtime.can_pay(available[found], {"grain": 2}):
			var allocation: Dictionary = lab._shared_work_plan.get("jobs", {}).get("person_actions", {}).get(key, {})
			if float(allocation.get("actual_seconds", 0.0)) > 0.0: return Runtime.fail("WORK_PAYMENT_SOURCE")
			continue # Original numeric zero-effort failure rechecks after earlier true payment.
		Runtime.add_items(available[found], {"grain": 2}, -1)
	return Runtime.ok("原有限授課庫量／當前原師徒容量已純核；不建立完成證據")

func _technology_lesson_family_candidate(record: Dictionary, job: Dictionary) -> Dictionary:
	# Pure projection of the SAME current original Family record. Only the
	# student's previously paid matching relearn history closes; archives and
	# every other actor/project remain exact, and no knowledge is added here.
	if not Technology.valid_family_tech(record): return {}
	var candidate: Dictionary = record.duplicate(true)
	var tech_id: String = str(job.get("technology_id", "F07"))
	var wanted: String = tech_id + ":relearn:" + JSON.stringify([_technology_site_id(), int(job.target_id)])
	for project: Dictionary in candidate.projects:
		if project.tech_id == tech_id and (str(project.purpose) == wanted or Technology.project_purpose_matches(project, _technology_ref(int(job.target_id)), candidate.get("person_links", []))) and not bool(project.closed):
			project.closed = true
			if int(candidate.active) == int(project.id): candidate.active = 0
	return candidate if Technology.valid_family_tech(candidate) else {}

func _prepare_scope_phase_completion(token: Dictionary, payment: Dictionary, event_id: String, productive: float) -> Dictionary:
	var context := _technology_phase_context(token, false, false)
	if not context.ok: return context
	if not payment.get("ok", false) or not is_same(payment.get("owner"), context.owner) \
		or not is_same(payment.get("record"), context.record) or not is_same(payment.get("site_state"), lab.terrain.site): return Runtime.fail("STALE_SOURCE")
	var receipt := {"site_id": _technology_site_id(), "person_id": int(token.person.person_id), "attempt": int(token.attempt),
		"phase_id": str(token.phase_id), "event_id": event_id, "work_seconds": productive, "payment_id": str(payment.payment_id)}
	var candidate := Technology.scope_receipt_candidate(payment.state, str(token.scope), receipt)
	if not candidate.ok: return candidate
	var learned: Dictionary = {}
	if candidate.complete and token.scope == "family":
		learned = Technology.learned_candidate(_body_get(context.person, "technology"), str(token.tech_id))
		if learned.is_empty(): return Runtime.fail("INVALID_TECHNOLOGY")
	return Runtime.ok("", {"owner": context.owner, "record": context.record, "state": candidate.state,
		"person": context.person, "person_candidate": learned, "complete": candidate.complete, "site_state": lab.terrain.site})

func _scope_ranged_craft_guard(identity: int, token: Dictionary, preview: bool = false) -> Dictionary:
	var recipe := _scope_ranged_recipe(token)
	if recipe.is_empty() or int(token.person.person_id) != identity: return Runtime.fail("INVALID_TECHNOLOGY")
	var context := _technology_phase_context(token, false)
	var job: Dictionary = _jobs.get(_job_key_for(identity), {})
	if preview and job.is_empty(): return context if context.ok else _technology_phase_context(token, true)
	if not context.ok: return context
	if job.get("kind") != "ranged_craft" or not is_same(job.get("technology_scope_token"), token) \
		or not is_same(job.get("terrain"), lab.terrain) or not is_same(job.get("site_state"), lab.terrain.site) \
		or not is_same(job.get("technology_executor_body"), context.person.body) \
		or not is_same(job.get("depot_holder"), lab.terrain.site.depot_items) or not is_same(job.get("depot_stock"), lab.terrain.site.inventory) \
		or job.get("recipe") != recipe or float(job.duration) != float(Runtime.RANGED_RECIPES[recipe].duration) \
		or not Technology.material_equal(token.materials, Runtime.RANGED_RECIPES[recipe].cost): return Runtime.fail("STALE_SOURCE")
	if not preview and float(job.elapsed) + 0.00000001 < float(job.duration): return Runtime.fail("WAITING")
	return context

func begin_scope_food_order(proposed: Dictionary, preview: bool = false) -> Dictionary:
	var parts: Variant = JSON.parse_string(str(proposed.get("target_id", "")).trim_prefix("settlement-food:"))
	if not parts is Array or parts.size() != 3 or parts[0] != _technology_site_id() \
		or proposed.get("target_id") != Runtime.settlement_food_target(str(parts[0]), str(parts[1]), str(parts[2])): return Runtime.fail("NO_TARGET")
	var refs := Runtime._settlement_food_refs(lab.terrain, str(parts[1]), str(parts[2]))
	if refs.is_empty() or not Runtime._settlement_food_token(lab.terrain, proposed, refs.order): return Runtime.fail("STALE_PROJECT")
	var p: Dictionary = refs.order.payload
	var token: Dictionary = proposed if p.stage == "prepared" else p.token
	if p.stage != "prepared":
		var current := _technology_paid_phase_context(token)
		if not current.ok: return current
	if p.stage in ["prepared", "carrier"]:
		return transfer_settlement_food_order(_technology_controlled(), str(parts[1]), str(parts[2]), "load" if p.stage == "prepared" else "arrive", token, preview)
	if p.stage == "arrived": return begin_settlement_food_work(_technology_controlled(), str(parts[1]), str(parts[2]), preview)
	return Runtime.fail("COMPLETE")

func begin_water_schedule_trial(token: Dictionary, categories: Array, preview: bool = false) -> Dictionary:
	if token.get("scope") != "settlement" or token.get("tech_id") != "S01" or token.get("binding") != "water_priority": return Runtime.fail("INVALID_TECHNOLOGY")
	var context := _technology_phase_context(token, true)
	if not context.ok: return context
	var duty := _technology_scope_duty("settlement", context.owner, true)
	if not duty.ok: return duty
	var prepared: Dictionary = Runtime.prepare_water_schedule(lab.terrain, int(duty.decider), categories, token)
	if not prepared.ok: return prepared
	var binding := technology_phase_binding_candidate(token)
	if not binding.ok: return binding
	var payment := technology_phase_payment_candidate(token, {}, binding)
	if not payment.ok: return payment
	var sample: Dictionary = Runtime.water_allocation_sample(lab.terrain, categories)
	if not Runtime.valid_water_allocation_sample(sample) or float(sample.source_capacity) <= 0.0: return Runtime.fail("WATER")
	if preview: return Runtime.ok("原供水排程試驗可開始", {"seconds": 300.0, "allocation": sample.duplicate(true)})
	var executor: Dictionary = context.person
	var job := _new_job(executor, "water_schedule", 0)
	job.merge({"duration": 300.0, "terrain": lab.terrain, "site_state": lab.terrain.site,
		"executor_body": executor.body, "water_center": prepared.center, "water_settlement": prepared.settlement,
		"water_schedule": prepared.schedule, "water_first_sample": sample.duplicate(true), "nation_token": token.duplicate(true),
		"water_event_id": str(payment.payment_id)})
	# All candidates, the source capacity, real worker and same owner were checked.
	publish_phase_payment(payment)
	_jobs[str(int(executor.person_id))] = job
	prepared.center.technology_water_schedule = prepared.schedule
	lab.terrain.site.water_status = sample.allocation
	lab.terrain.environment_revision += 1
	return Runtime.ok("原供水優先序已實施；具名原人沿共同工時驗證300秒", {"seconds": 300.0})

func _fire_pot_shot_phase_context(token: Dictionary, binding: bool = false, require_source: bool = true) -> Dictionary:
	if TechnologyCatalog.get_node("F15").get("enabled") != true: return Runtime.fail("UNIMPLEMENTED")
	if not Runtime._technology_trial_shape(token, lab.terrain) or token.scope != "family" or token.tech_id != "F15" \
		or token.binding != "fire_pot_shot" or not Technology.material_equal(token.materials, {"fire_pot": 1}): return Runtime.fail("INVALID_TECHNOLOGY")
	var owner := _technology_family()
	var raw: Dictionary = owner.get("technology", {})
	if not Technology.valid_scope_record(raw, "family") or int(raw.epoch) != int(token.epoch) or raw.holder_site_id != _technology_site_id() \
		or token.scope_id != str(owner.get("family_id", "")): return Runtime.fail("STALE_PROJECT")
	var project := Technology.active_project(raw)
	if project.is_empty() or int(project.rules_version) != 2 or project.tech_id != "F15" or int(project.id) != int(token.project_id) \
		or project.purpose != token.purpose or not Technology.same_person_ref(project.executor, token.person, raw.get("person_links", [])) \
		or (int(token.attempt) != int(project.next_attempt) if binding else int(token.attempt) != int(project.next_attempt) - 1): return Runtime.fail("STALE_PROJECT")
	var phase := Technology.scope_next_phase(project, token.person, raw.get("person_links", []))
	if phase.is_empty() or phase.id != token.phase_id or phase.binding != token.binding: return Runtime.fail("STALE_PHASE")
	var person := _person(int(token.person.person_id))
	var key := str(token.target_id).trim_prefix("vehicle:")
	var vehicle: Dictionary = lab.terrain.site.get("vehicles", {}).get(key, {})
	if token.target_id != "vehicle:" + key or not Runtime.siege_ammo_valid(str(vehicle.get("kind", "")), "fire_pot") \
		or person.is_empty() or not _technology_member(int(person.person_id)) or float(person.hp) <= 0.0 or float(person.ko) > 0.0 \
		or bool(person.captive) or bool(person.moving) or bool(_body_get(person, "attack")) or str(_body_get(person, "pose")) != "idle" \
		or float(_body_get(person, "exchange_stagger")) > 0.0 or bool(lab.terrain.site.get("paused", false)) \
		or float(lab.terrain.site.get("combat_left", 0.0)) > 0.0 or not _technology_duty("family.research").ok \
		or not _fire_pot_crew_consent(person, project): return Runtime.fail("BUSY")
	if person.owner is CrowdOwner and not person.owner.crowd_site.work_fatigue_work_start_ready(int(person.person_id)): return Runtime.fail("BUSY")
	if binding and (not vehicle.crew_slots.values().has(int(person.person_id)) or not lab.site_controller.vehicles.crew_ready(vehicle)): return Runtime.fail("BUSY")
	var financial: Dictionary = project.budget
	if financial.is_empty() or financial.status != "granted" or financial.source_site_id != _technology_site_id() or financial.holder != "vehicle:" + key: return Runtime.fail("NO_BUDGET")
	if not require_source: return Runtime.ok("", {"owner": owner, "record": raw, "project": project, "phase": phase, "person": person, "vehicle": vehicle})
	var budget: Dictionary = project.budget
	if budget.is_empty() or budget.status != "granted" or budget.holder != "vehicle:" + key or budget.source_site_id != _technology_site_id(): return Runtime.fail("NO_BUDGET")
	var held: Dictionary = _technology_source_refs.get(JSON.stringify(["family", str(token.scope_id), int(project.id)]), {})
	if not is_same(held.get("terrain"), lab.terrain) or not is_same(held.get("site"), lab.terrain.site) or not is_same(held.get("vehicle"), vehicle) \
		or not is_same(held.get("holder"), vehicle.get("holder")) or not is_same(held.get("cargo"), vehicle.get("cargo")): return Runtime.fail("STALE_SOURCE")
	return Runtime.ok("", {"owner": owner, "record": raw, "project": project, "phase": phase, "person": person, "vehicle": vehicle})

func fire_pot_ammo_guard(vehicle: Dictionary, identity: int, token: Dictionary = {}) -> Dictionary:
	if TechnologyCatalog.get_node("F15").get("enabled") != true: return Runtime.fail("UNIMPLEMENTED")
	if lab.crowd_site != null and lab.crowd_site.active and not lab.crowd_site.fire_host_active(): return Runtime.fail("UNSUPPORTED_BACKEND")
	if lab.site_controller == null or not is_same(lab.terrain.site.get("vehicles", {}).get(str(vehicle.get("id", ""))), vehicle) \
		or str(vehicle.get("kind", "")) not in ["traction_trebuchet", "counterweight_trebuchet"] \
		or not vehicle.get("crew_slots", {}).values().has(identity): return Runtime.fail("NO_AUTHORITY")
	var person := _person(identity)
	if person.is_empty() or float(person.hp) <= 0.0 or float(person.ko) > 0.0 or bool(person.captive) or bool(person.moving) \
		or not lab.site_controller.vehicles.crew_ready(vehicle) \
		or bool(_body_get(person, "attack")) or str(_body_get(person, "pose")) != "idle" \
		or float(_body_get(person, "exchange_stagger")) > 0.0: return Runtime.fail("BUSY")
	if person.owner is CrowdOwner and not person.owner.crowd_site.work_fatigue_work_start_ready(identity): return Runtime.fail("BUSY")
	if not token.is_empty():
		if not _technology_member(identity): return Runtime.fail("NO_AUTHORITY")
		return _fire_pot_shot_trial_guard(vehicle, identity, token)
	if not Technology.learned(_body_get(person, "technology"), "F15"): return Runtime.fail("NO_TECHNOLOGY", "火罐須由在位且本人已學會 F15 的原操作班成員發射")
	return Runtime.ok()

func prepare_fire_pot_release_payment(vehicle: Dictionary, token: Dictionary) -> Dictionary:
	if token.is_empty(): return Runtime.ok("", {"payment": {}})
	var checked := _fire_pot_shot_trial_guard(vehicle, int(token.get("person", {}).get("person_id", 0)), token)
	if not checked.ok: return checked
	var payment := technology_phase_payment_candidate(token, {"fire_pot": 1})
	return Runtime.ok("", {"payment": payment}) if payment.ok else payment

func grant_fire_pot_vehicle_budget(requester_id: int, vehicle_id: String, fire_pot_cap: int, operation: String = "grant") -> Dictionary:
	var owner := _technology_family()
	var raw: Dictionary = owner.get("technology", {})
	var project := Technology.active_project(raw)
	var vehicle: Dictionary = lab.terrain.site.get("vehicles", {}).get(vehicle_id, {})
	var team: Variant = lab.site_controller.vehicles._siege_team(vehicle)
	if requester_id != _technology_controlled() or not (team is TerrainArmy or team is CrowdOwner) or not lab.site_controller.vehicles._authorized(team, requester_id, 0, false) \
		or not Runtime.siege_ammo_valid(str(vehicle.get("kind", "")), "fire_pot") or project.is_empty() or project.tech_id != "F15" \
		or int(project.rules_version) != 2 or not Technology.valid_scope_record(raw, "family") \
		or not Technology.integer(fire_pot_cap, 0, 1000000) or not _technology_duty("family.research").ok: return Runtime.fail("NO_AUTHORITY")
	var phase := Technology.scope_next_phase(project, project.executor, raw.get("person_links", []))
	if phase.is_empty() or phase.binding != "fire_pot_shot": return Runtime.fail("STALE_PHASE")
	var holder: Dictionary = vehicle.get("holder", {})
	var cargo: Dictionary = vehicle.get("cargo", {})
	if not Runtime._item_holder_shape(holder) or holder.holder != "vehicle:" + vehicle_id or not Runtime._resource_stack(cargo): return Runtime.fail("STALE_SOURCE")
	var original: Variant = team._order_owner() if team is CrowdOwner else team
	if team is CrowdOwner:
		for plan: Dictionary in team.crowd_site._original_team_plans:
			if int(plan.team_id) == int(vehicle.team_id) and plan.source is TerrainArmy: original = plan.source; break
	if not original is TerrainArmy or int(original.duty_resolve_readonly("team.work", team if team is CrowdOwner else null).get("decider", -1)) != requester_id \
		or team.combat_order != TerrainArmy.CombatOrder.HOLD or team.is_sustain_routed() or bool(lab.terrain.site.get("paused", false)) \
		or float(lab.terrain.site.get("combat_left", 0.0)) > 0.0: return Runtime.fail("NO_AUTHORITY")
	var spent: Dictionary = project.budget.get("spent", {})
	if operation != "revoke" and (fire_pot_cap < int(spent.get("fire_pot", 0)) \
		or fire_pot_cap > int(spent.get("fire_pot", 0)) + int(cargo.get("fire_pot", 0))): return Runtime.fail("NO_BUDGET")
	# Preserve every previous lifetime cap, spend and payment. The only remaining
	# F15 phase is the shot, so this entry grants no new former craft material.
	var cap: Dictionary = project.budget.get("cap", {}).duplicate()
	cap.fire_pot = fire_pot_cap
	var candidate := Technology.scope_budget_candidate(raw, "family", _technology_ref(requester_id), "vehicle:" + vehicle_id, cap, operation)
	if not candidate.ok: return candidate
	owner.technology = candidate.state
	_technology_source_refs[JSON.stringify(["family", str(owner.family_id), int(project.id)])] = {"terrain": lab.terrain,
		"site": lab.terrain.site, "vehicle": vehicle, "holder": holder, "cargo": cargo}
	return Runtime.ok("原投石機有限火罐核額已更新；先前支出與付款不清零")

func technology_phase_work_preflight(token: Dictionary, binding: bool = false) -> Dictionary:
	if not Technology.keys(token, ["scope", "scope_id", "project_id", "epoch", "purpose", "tech_id", "phase_id", "attempt", "person", "binding", "target_id", "materials"]) \
		or not Technology.valid_ref(token.person) or not token.scope is String or not token.scope_id is String \
		or not token.target_id is String or token.target_id.is_empty(): return Runtime.fail("INVALID_TECHNOLOGY")
	var owner := _technology_scope_owner(str(token.scope), str(token.scope_id))
	var record: Dictionary = owner.get("technology", {})
	if not Technology.valid_scope_record(record, str(token.scope)): return Runtime.fail("STALE_PROJECT")
	var project := Technology.active_project(record)
	var preparing := binding or Technology.integer(token.attempt, int(project.get("next_attempt", -1)), int(project.get("next_attempt", -1)))
	var checked := _technology_phase_context(token, true, false, true) if preparing else technology_phase_active_guard(token)
	if not checked.ok: return checked
	var person: Dictionary = checked.person
	var team: Variant = person.owner if person.owner is CrowdOwner else _technology_team(person)
	checked.merge({"team": team, "person_ids": [int(token.person.person_id)], "groups": [{"team": team, "person_ids": [int(token.person.person_id)]}],
		"requester_id": _technology_controlled(), "operation_ref": {}, "controlled_worker": int(token.person.person_id) == _technology_controlled()})
	return checked

# APPEND; a genuine accepted ordinary N order may continue its OWN named task.
# No copied order/consent, matching target alone or boolean caller bypass works.

func set_water_use_priority(requester_id: int, categories: Array) -> Dictionary:
	return Runtime.set_water_use_priority(lab.terrain, requester_id, categories)

func _technology_military_consent_candidate(identity: int, purpose: String) -> Dictionary:
	var person := _person(identity)
	if person.is_empty() or not _technology_military_person_ready(person, {}): return Runtime.fail("BUSY")
	var team: Variant = _technology_team(person)
	if person.owner is CrowdOwner:
		var source: Variant = person.owner._command_owner(int(person.unit))
		if source is TerrainArmy: team = source
		if team != null and (team.data != lab.terrain or int(team.team_id) != int(person.owner.team_id) or not person.owner.crowd_site.owns_original_team(team)): return Runtime.fail("STALE_SOURCE")
	if team == null: return Runtime.ok("原人不受隊伍派工管轄", {"consent": {}})
	# The original Army/DutyAI command still makes this named decision, including
	# current decider/control and duty_ai. Native physical guards recheck its result.
	var response: Dictionary = team.technology_work_consent(identity, purpose, _technology_controlled(), person.owner if person.owner is CrowdOwner else null)
	if not response.ok: return response
	if not _technology_consent_valid(identity, [response.consent], purpose, {}, true): return Runtime.fail("BUSY")
	return response

func request_settlement_processing_order(requester_id: int, kind: String, feature_id: String, operator_id: int, max_batches: int, source_feature_id: String = "", project_id: int = 0) -> Dictionary:
	var runtime_script: Variant = Runtime
	if not runtime_script.has_method("request_settlement_processing_order"): return Runtime.fail("UNIMPLEMENTED")
	return runtime_script.call("request_settlement_processing_order", lab.terrain, kind, feature_id, operator_id, max_batches, requester_id, source_feature_id, project_id)

func begin_settlement_processing_operation(requester_id: int, settlement_id: String, order_id: String) -> Dictionary:
	var settlement: Dictionary = _technology_scope_owner("settlement", settlement_id)
	var authorized: Dictionary = _technology_scope_command(requester_id, "settlement", settlement)
	if not authorized.ok: return authorized
	var runtime_script: Variant = Runtime
	if not runtime_script.has_method("begin_settlement_processing_operation"): return Runtime.fail("UNIMPLEMENTED")
	return runtime_script.call("begin_settlement_processing_operation", lab.terrain, settlement_id, order_id)

func prepare_settlement_metal_transfer_receipt(token: Dictionary, original_prepared: Dictionary) -> Dictionary:
	var runtime_script: Variant = Runtime
	if not runtime_script.has_method("validate_settlement_metal_transfer") or not runtime_script.has_method("settlement_metal_paid_source_candidate"): return Runtime.fail("UNIMPLEMENTED")
	var original: Dictionary = runtime_script.call("validate_settlement_metal_transfer", original_prepared)
	if not original.ok: return original
	if not is_same(original_prepared.terrain, lab.terrain) or original_prepared.get("leg") != 1 or original_prepared.token != token \
		or original_prepared.order_ref.payload.carry_receipts.size() != 1 or original_prepared.order_ref.payload.carry_receipts[0].token != token \
		or original_prepared.candidate.payload.carry_receipts.size() != 2 or original_prepared.fact.leg != "deposit": return Runtime.fail("INVALID_RECEIPT")
	var paid: Dictionary = runtime_script.call("settlement_metal_paid_source_candidate", lab.terrain, token, str(original_prepared.order_id))
	if not paid.ok: return paid
	var checked := _technology_phase_context(token, false, false)
	if not checked.ok: return checked
	if not is_same(checked.owner, paid.settlement) or not is_same(paid.operations, original_prepared.operations_ref) or not is_same(paid.order, original_prepared.order_ref) \
		or not is_same(paid.paid, original_prepared.order_ref.payload.carry_receipts[0]) \
		or checked.project.budget.is_empty() or checked.project.budget.status != "granted" or checked.project.budget.holder != paid.holder: return Runtime.fail("STALE_SOURCE")
	var payment := {}
	for row: Dictionary in checked.project.budget.payments:
		if row.payment_id == original_prepared.order_ref.payload.carry_receipts[0].payment_id:
			if not payment.is_empty(): return Runtime.fail("CORRUPT_STATE")
			payment = row
	if payment.is_empty() or payment.attempt != token.attempt or payment.phase_id != token.phase_id or payment.target_id != token.target_id \
		or not Technology.same_person_ref(payment.person, token.person, checked.record.get("person_links", [])) \
		or not Technology.material_equal(payment.materials, {"iron": 2}): return Runtime.fail("NO_PAYMENT")
	# The original accepted first withdrawal + prospective second real contact are
	# the only producer. Neither caller flags nor a fabricated feature ledger can
	# create this zero-work transfer phase evidence.
	var event_id := JSON.stringify([_technology_site_id(), "metal_chain", str(original_prepared.settlement_id), str(original_prepared.order_id), "deposit", int(original_prepared.order_ref.revision)])
	var receipt := {"site_id": _technology_site_id(), "person_id": int(token.person.person_id), "attempt": int(token.attempt), "phase_id": str(token.phase_id),
		"event_id": event_id, "work_seconds": 0.0, "payment_id": str(payment.payment_id)}
	var prepared := Technology.scope_receipt_candidate(checked.record, "settlement", receipt)
	if not prepared.ok: return prepared
	return Runtime.ok("", {"owner": checked.owner, "record": checked.record, "state": prepared.state, "person": checked.person, "person_candidate": {}, "complete": prepared.complete, "site_state": lab.terrain.site})

func begin_settlement_metal_operation(requester_id: int, settlement_id: String, order_id: String) -> Dictionary:
	var settlement := _technology_scope_owner("settlement", settlement_id)
	var admitted := _technology_scope_command(requester_id, "settlement", settlement)
	if not admitted.ok: return admitted
	var runtime_script: Variant = Runtime
	if not runtime_script.has_method("begin_settlement_metal_operation"): return Runtime.fail("UNIMPLEMENTED")
	return runtime_script.call("begin_settlement_metal_operation", lab.terrain, settlement_id, order_id)

func settlement_metal_order_view(settlement_id: String, order_id: String) -> Dictionary:
	var runtime_script: Variant = Runtime
	if not runtime_script.has_method("settlement_metal_order_view"): return Runtime.fail("UNIMPLEMENTED")
	return runtime_script.call("settlement_metal_order_view", lab.terrain, settlement_id, order_id)

func request_settlement_metal_order(requester_id: int, smelter_id: String, smithy_id: String, operator_id: int, project_id: int = 0) -> Dictionary:
	var settlement: Dictionary = lab.terrain.site.get("settlement", {})
	var admitted := _technology_scope_command(requester_id, "settlement", settlement)
	if not admitted.ok: return admitted
	var runtime_script: Variant = Runtime
	if not runtime_script.has_method("request_settlement_metal_order"): return Runtime.fail("UNIMPLEMENTED")
	return runtime_script.call("request_settlement_metal_order", lab.terrain, smelter_id, smithy_id, operator_id, requester_id, project_id)

func prepare_settlement_food_work(checked: Dictionary, transfer: Dictionary = {}) -> Dictionary:
	if not checked.get("ok", false) or not is_same(checked.settlement, Settlement.record(lab.terrain)): return Runtime.fail("STALE_SOURCE")
	var order: Dictionary = checked.order
	var person: Dictionary = checked.person
	if order.payload.stage != ("arrived" if transfer.is_empty() else "carrier") or is_busy(int(person.person_id)) \
		or not _ready(person) or not lab.site_controller._delivery_person_ready(person): return Runtime.fail("BUSY")
	if transfer.is_empty():
		var entrance: Vector2i = checked.stock.cell
		if absi(person.cell.x - entrance.x) + absi(person.cell.y - entrance.y) > 1 \
			or not lab.terrain.contains(person.cell) or not lab.terrain.contains(entrance) \
			or person.cell != entrance and not lab.terrain.can_step(person.cell, entrance): return Runtime.fail("POSITION")
	else:
		if not is_same(transfer.destination, checked.stock.holder) or not is_same(transfer.destination_cargo, checked.stock.cargo) \
			or not is_same(transfer.source, person.holder) or not is_same(transfer.source_cargo, person.cargo) \
			or transfer.resources != {"grain": int(order.payload.quantity)}: return Runtime.fail("STALE_SOURCE")
	var job := _new_job(person, "food_order", 0)
	job.merge({"duration": 300.0, "elapsed": float(order.payload.work_seconds), "terrain": lab.terrain, "site_state": lab.terrain.site,
		"executor_body": person.body, "food_settlement": checked.settlement, "food_operations": checked.operations, "food_order": order,
		"food_warehouse": checked.feature, "food_holder": checked.stock.holder, "food_cargo": checked.stock.cargo, "nation_token": order.payload.token,
		"food_event_id": str(order.payload.paid.payment_id)})
	return Runtime.ok("原PA300秒作業候選；尚未佔用或扣時", {"owner": self, "jobs": _jobs, "job": job, "person_id": int(person.person_id), "site": lab.terrain.site, "terrain": lab.terrain})

func publish_settlement_food_work(prepared: Dictionary) -> void:
	# Actual second transfer and its arrival receipt publish immediately before.
	# Preparation is the sole admission; this tail performs no failure-prone call.
	_jobs[str(int(prepared.person_id))] = prepared.job

func settlement_food_own_job(person: Dictionary, order: Dictionary) -> bool:
	if person.is_empty(): return false
	var job: Dictionary = _jobs.get(str(int(person.person_id)), {})
	return job.get("kind") == "food_order" and is_same(job.get("food_order"), order) \
		and is_same(job.get("executor_body"), person.body) and is_same(job.get("terrain"), lab.terrain) \
		and is_same(job.get("site_state"), lab.terrain.site)

func request_warehouse_food_order(requester_id: int, warehouse_id: String, operator_id: int, source_holder: String, project_id: int = 0, preview: bool = false) -> Dictionary:
	return Runtime.request_warehouse_food_order(lab.terrain, warehouse_id, operator_id, requester_id, source_holder, project_id, preview)

func transfer_settlement_food_order(requester_id: int, settlement_id: String, order_id: String, leg: String, token: Dictionary = {}, preview: bool = false) -> Dictionary:
	var prepared := Runtime.prepare_settlement_food_transfer(lab.terrain, settlement_id, order_id, leg, requester_id, token)
	if not prepared.ok: return prepared
	if preview: return Runtime.ok("原具名實物腿已純預檢", {"leg": leg, "quantity": int(prepared.payload.quantity)})
	var checked := Runtime.validate_settlement_food_transfer(prepared)
	if not checked.ok: return checked
	return Runtime.publish_settlement_food_transfer(prepared)

func _technology_military_person_ready(person: Dictionary, order: Dictionary) -> bool:
	if person.is_empty() or float(person.hp) <= 0.0 or float(person.ko) > 0.0 or bool(person.captive) or bool(person.moving): return false
	var matching := _technology_matching_military_task(person, order) or not order.is_empty() and _technology_matching_settlement_task(person, str(order.get("payload", {}).get("purpose", "")))
	var task := _technology_military_task(person)
	if is_busy(int(person.person_id)) and not matching or not str(task.get("target", "")).is_empty() and not matching: return false
	if person.owner is CrowdOwner and not person.owner.crowd_site.work_fatigue_work_start_ready(int(person.person_id)): return false
	if _ready(person): return true
	if not matching: return false
	# Only the SAME accepted work task relaxes its own occupied-work check.
	# Other original action, transport and delivery locks still apply.
	if lab.site_controller.ship_person_in_journey(int(person.person_id)) or lab.site_controller.vehicles.is_siege_crew(int(person.person_id)): return false
	for entry: Dictionary in lab.terrain.site.get("team_supply", {}).values():
		var delivery: Dictionary = entry.get("delivery", {})
		if not delivery.is_empty() and int(person.person_id) in [int(delivery.get("player_id", -1)), int(delivery.get("representative_id", -1))]: return false
	if not person.owner is CrowdOwner and int(person.unit) < 0:
		var actor: Variant = person.owner
		if not actor.can_act() or actor.action_time > 0.0 or actor.guarding or actor.guard_transition_left > 0.0 or actor.guard_break_left > 0.0 or actor._rescue_left > 0.0: return false
		if actor == lab.npc and (int(actor.command) != 0 or not actor._path.is_empty()): return false
	return float(_body_get(person, "exchange_stagger")) <= 0.0 and not bool(_body_get(person, "attack")) and str(_body_get(person, "pose")) == "idle" \
		and not is_guarding(int(person.person_id)) and not lab.site_controller.region_operation_pending() \
		and (person.owner.combat_can_act(int(person.unit)) if int(person.unit) >= 0 else person.owner.can_act())

func publish_nation_original_administration(prepared: Dictionary) -> void:
	if not prepared.get("payment", {}).is_empty(): publish_phase_payment(prepared.payment)
	elif not prepared.get("binding", {}).is_empty(): publish_phase_binding(prepared.binding)
	if not prepared.get("job", {}).is_empty(): _jobs[str(int(prepared.job.executor_id))] = prepared.job

func begin_nation_original_administration(requester_id: int, nation_id: String, original_key: String, binding: String) -> Dictionary:
	if requester_id != _technology_controlled(): return Runtime.fail("NO_AUTHORITY")
	var nation: Dictionary = _technology_scope_owner("nation", nation_id)
	var technology_id := "N01" if binding == "procurement" else "N04"
	if binding not in ["procurement", "workshop_certificate"] or nation.is_empty(): return Runtime.fail("NO_TARGET")
	if Technology.scope_known(nation.get("technology", {}), technology_id): return Runtime.fail("NO_CHANGE", "已知原制度不重開首次研究工作")
	var duty := "nation.procurement" if technology_id == "N01" else "nation.workshop"
	if not equipment_orders._nation_duty_ok(requester_id, nation, duty): return Runtime.fail("NO_AUTHORITY")
	var key := original_key.trim_prefix("procurement:" if technology_id == "N01" else "certificate:")
	var original: Dictionary = nation.get("technology_operations", {}).get("specs" if technology_id == "N01" else "certificates", {}).get(key, {})
	if original.is_empty(): return Runtime.fail("NO_TARGET")
	var prepared := {}
	if technology_id == "N04":
		prepared = prepare_nation_workshop_administration(nation_id, key, original)
	else:
		var selection := _nation_original_research_token(nation_id, key, "N01", "procurement", "nation-procurement:" + JSON.stringify([_technology_site_id(), nation_id, key]), original.get("tech_trial", {}))
		if not selection.ok or selection.token.is_empty() or not original.has("tech_trial") or original.receipts.size() != 2: return selection if not selection.ok else Runtime.fail("INCOMPLETE_OPERATION")
		var ready := _technology_scope_person("nation", nation, int(selection.token.person.person_id))
		if not ready.ok: return ready
		var paid := false
		for payment: Dictionary in selection.context.project.budget.get("payments", []):
			if payment.attempt == selection.token.attempt and payment.phase_id == selection.token.phase_id and payment.target_id == selection.token.target_id \
				and payment.person == selection.token.person and Technology.material_equal(payment.materials, selection.token.materials): paid = true
		if not paid: return Runtime.fail("NO_PAYMENT")
		for receipt: Variant in original.receipts:
			if not Technology.keys(receipt, ["id", "source_person_id", "resources", "items"]) or receipt.source_person_id != selection.token.person.person_id \
				or not Technology.material_equal(receipt.resources, {"wood": 1, "grain": 1}) or not receipt.items is Dictionary or not receipt.items.is_empty(): return Runtime.fail("INVALID_RECEIPT")
		var job := _nation_original_administration_job(ready.person, nation, original, "procurement", key, selection.token, original)
		prepared = Runtime.ok("", {"binding": {}, "payment": {}, "job": job})
	if not prepared.ok: return prepared
	# A stopped paid original N01 resumes work only; no delivery or payment repeats.
	publish_nation_original_administration(prepared)
	return Runtime.ok("原制度300秒檢验作業開始／重做；原已付物資不再扣", {"seconds": 300.0})

func _nation_original_administration_job(person: Dictionary, nation: Dictionary, original: Dictionary, kind: String, key: String, token: Dictionary, expected: Dictionary) -> Dictionary:
	var job := _new_job(person, "nation_administration", 0)
	job.merge({"duration": 300.0, "terrain": lab.terrain, "site_state": lab.terrain.site, "executor_body": person.body,
		"nation_id": str(token.scope_id), "nation_order_id": key, "nation_original_kind": kind, "nation_ref": nation,
		"nation_order_ref": original, "nation_original_expected": expected.duplicate(true), "nation_binding": str(token.binding),
		"nation_target": str(token.target_id), "nation_items": [], "nation_token": token,
		"nation_event_id": JSON.stringify([_technology_site_id(), str(token.scope_id), str(token.purpose), int(token.project_id), int(token.attempt), kind, key, int(expected.revision)])})
	return job

func _nation_original_research_token(nation_id: String, _key: String, technology_id: String, binding: String, target: String, held: Dictionary = {}) -> Dictionary:
	var nation: Dictionary = _technology_scope_owner("nation", nation_id)
	if nation.is_empty() or Technology.scope_known(nation.get("technology", {}), technology_id): return Runtime.ok("", {"token": {}})
	var project := Technology.active_project(nation.get("technology", {}))
	var phase := Technology.scope_next_phase(project, project.get("executor", {}))
	if project.is_empty() or project.tech_id != technology_id or phase.get("binding") != binding: return Runtime.fail("STALE_PHASE")
	var token := {"scope": "nation", "scope_id": nation_id, "project_id": int(project.id), "epoch": int(nation.technology.epoch),
		"purpose": str(project.purpose), "tech_id": technology_id, "phase_id": str(phase.id), "attempt": int(project.next_attempt),
		"person": project.executor.duplicate(), "binding": binding, "target_id": target, "materials": phase.materials.duplicate()}
	if not held.is_empty():
		if not Technology.keys(held, token.keys()) or held.scope != "nation" or held.scope_id != nation_id or held.project_id != token.project_id or held.epoch != token.epoch \
			or held.purpose != token.purpose or held.tech_id != technology_id or held.phase_id != token.phase_id or held.person != token.person \
			or held.binding != binding or held.target_id != target or not Technology.material_equal(held.materials, token.materials): return Runtime.fail("STALE_PROJECT")
		token = held
	var checked := _technology_phase_context(token, held.is_empty(), false)
	return Runtime.ok("", {"token": token, "context": checked}) if checked.ok else checked

func _nation_military_issue_event(job: Dictionary) -> Dictionary:
	return {"id": str(job.nation_issue_event_id), "site_id": _technology_site_id(), "target_id": str(job.nation_issue_token.target_id),
		"operator_id": int(job.executor_id), "binding": "issue_bow", "work_seconds": 5.0, "item_ids": [], "outputs": {}, "materials": {}}

func _nation_military_issue_job_context(job: Dictionary) -> Dictionary:
	if not is_same(_jobs.get(str(int(job.executor_id)), {}), job) or str(job.get("kind", "")) != "equipment" \
		or not job.has("nation_issue_token") or not is_same(job.get("terrain"), lab.terrain) or not is_same(job.get("site_state"), lab.terrain.site): return Runtime.fail("STALE_SOURCE")
	var order: Dictionary = job.order
	var nation: Dictionary = _technology_scope_owner("nation", str(order.get("nation_id", "")))
	var production: Dictionary = nation.get("technology_operations", {}).get("orders", {}).get(str(order.get("military_production_id", "")), {})
	var token: Dictionary = job.nation_issue_token
	if not is_same(nation, job.nation_issue_nation_ref) or not is_same(production, job.nation_issue_order_ref) \
		or production.get("status") != "complete" or int(production.get("operator_id", -1)) != int(job.executor_id) \
		or int(production.get("recipient_id", -1)) != int(job.executor_id) or int(order.person_id) != int(job.executor_id) \
		or token.get("binding") != "issue_bow" or token.get("tech_id") != "N05" or token.get("target_id") != "person:" + str(int(job.executor_id)) \
		or token.get("scope_id") != order.nation_id or token.get("person", {}).get("person_id") != job.executor_id: return Runtime.fail("STALE_ORDER")
	var current := _technology_phase_context(token, false, false)
	if not current.ok: return current
	if current.project.budget.get("holder") != "nation-order:" + JSON.stringify([_technology_site_id(), str(order.nation_id), str(order.military_production_id)]) \
		or not _nation_military_first_payment(current.project, order): return Runtime.fail("BOUND_SOURCE")
	var paid := false
	for payment: Dictionary in current.project.budget.get("payments", []):
		if payment.attempt == token.attempt and payment.phase_id == token.phase_id and payment.target_id == token.target_id \
			and payment.person == token.person and payment.materials.is_empty(): paid = true
	return current if paid else Runtime.fail("NO_PAYMENT")

func _nation_military_first_payment(project: Dictionary, order: Dictionary) -> bool:
	var first_phase := "one_standard_bow_order"
	var first_payment := ""
	var nation: Dictionary = _technology_scope_owner("nation", str(order.get("nation_id", "")))
	var production: Dictionary = nation.get("technology_operations", {}).get("orders", {}).get(str(order.get("military_production_id", "")), {})
	for payment: Dictionary in project.get("budget", {}).get("payments", []):
		if payment.phase_id == first_phase and payment.person == project.executor and payment.target_id == "feature:" + str(production.get("feature_id", "")) \
			and Technology.material_equal(payment.materials, {"wood": 4, "fiber": 2}): first_payment = str(payment.payment_id)
	for receipt: Dictionary in project.get("receipts", []):
		if receipt.phase_id == first_phase and receipt.person_id == project.executor.person_id and receipt.site_id == project.executor.site_id \
			and not first_payment.is_empty() and receipt.payment_id == first_payment: return true
	return false

func _scope_project_activation(raw: Dictionary) -> bool:
	var project := Technology.active_project(raw)
	return not project.is_empty() and int(project.get("rules_version", -1)) == 2 and TechnologyCatalog.get_node(str(project.get("tech_id", ""))).get("enabled") == true

# APPEND to original PA. Canonical orders.production_N selector only; no new
# saved order/person/source authority and no acceptance based on caller flags.

func _technology_supervision_person(identity: int) -> Dictionary:
	var person := _person(identity)
	if person.is_empty(): return {}
	return {"person_id": identity, "label": "原人物 #%d · %s%s" % [identity, "已學 F07" if Technology.learned(_body_get(person, "technology"), "F07") else "未學 F07", " · 原作業忙碌" if is_busy(identity) else ""],
		"owner_ref": person.owner, "body_ref": person.body, "holder_ref": person.holder, "cargo_ref": person.cargo, "job": job_for(identity)}

func prepare_gd_contact_controlled_prefix(registered: Dictionary) -> Dictionary:
	if _gd_contact_job_capture.is_empty() or registered.get("owner") != self or not is_same(registered.get("registered"), _checked_controlled_prefixes) \
		or not is_same(_checked_controlled_prefixes.admitted.prepared, _gd_contact_job_capture.prepared): return Runtime.fail("STALE_WORK_PREFIX")
	var admitted: Dictionary = validate_checked_controlled_runtime_prefixes(registered)
	if not admitted.ok: return admitted
	for candidate: Dictionary in admitted.checked.runtime:
		var envelope: Dictionary = Runtime.prepare_gd_contact_work_envelope(candidate)
		if not envelope.ok: return envelope
		_gd_contact_job_capture.controlled_envelopes.append(envelope)
	return Runtime.ok("原受控工作同held有限來源上界已純核", {"capture": _gd_contact_job_capture})

func prepare_shared_nonwork_timers(seconds: float) -> Dictionary:
	# The original escape watcher has NO effort/fatigue request. Capture its
	# original start verdict, then settle its same raw timer after Native pub.
	if not is_finite(seconds) or seconds <= 0.0: return Runtime.fail("INVALID_INTERVAL")
	var held: Array[Dictionary] = []
	for key: String in _jobs:
		var job: Dictionary = _jobs[key]
		if job.get("kind") != "escape": continue
		var context: Dictionary = _job_context(job)
		if not context.ok: continue
		var person: Dictionary = _person(int(job.executor_id))
		held.append({"key": key, "job": job, "elapsed": float(job.elapsed), "hit": int(person.hit),
			"watched": int(person.hit) != int(job.executor_hit) or _escape_blocked(person, {})})
	return Runtime.ok("原无努力逃脱计时起点已捕捉", {"owner": self, "seconds": seconds, "held": held})

func prepare_shared_work_prefix(requests: Array, seconds: float) -> Dictionary:
	if not is_finite(seconds) or seconds <= 0.0 or not _shared_work_prefix_consumption.is_empty(): return Runtime.fail("CLOCK_NOT_READY")
	var held := {}
	for request: Dictionary in requests:
		if request.get("provider") != "person_actions": continue
		var key: String = str(request.get("key", ""))
		var job: Dictionary = _jobs.get(key, {})
		if key.is_empty() or held.has(key) or job.is_empty() or str(job.get("kind", "")) == "fire_suppress" \
			or bool(job.get("preparing", false)) or not request.get("participants") is Array: return Runtime.fail("STALE_SOURCE")
		var qualified: Dictionary = _job_context(job) # TRUE original start qualification, before World/contacts.
		if not qualified.ok: return qualified
		var people := {}
		for participant: Dictionary in request.participants:
			var identity: int = int(participant.get("person_id", -1))
			var person: Dictionary = _person(identity)
			if identity <= 0 or people.has(identity) or person.is_empty(): return Runtime.fail("STALE_SOURCE")
			var original_body: Variant = participant.get("original_body", participant.get("body"))
			if not is_same(original_body, person.body): return Runtime.fail("STALE_SOURCE")
			if participant.has("native_snapshot"):
				var snapshot: Dictionary = participant.native_snapshot
				if not person.owner is CrowdOwner or participant.get("native_owner") != person.owner \
					or int(participant.get("unit", -1)) != int(person.unit) \
					or not is_same(snapshot, lab.crowd_site.work_fatigue_snapshot_for_owner(person.owner)):
					return Runtime.fail("STALE_NATIVE_WORK_PLAN")
			people[identity] = {"owner": person.owner, "body": person.body, "holder": person.holder, "cargo": person.cargo,
				"holder_version": int(person.holder.version), "person_id": identity, "unit": int(person.unit),
				"faction": int(person.faction), "player": bool(person.player), "start_cell": person.cell}
		if people.is_empty() or not people.has(int(job.get("executor_id", -1))): return Runtime.fail("STALE_SOURCE")
		var task: Dictionary = job.get("work_task", {})
		var item := {"key": key, "job": job, "kind": str(job.kind), "request": request, "people": people,
			"task": task, "task_start": task.duplicate(true), "elapsed": float(job.get("elapsed", 0.0)),
			"duration": float(job.get("duration", 0.0)), "feature": {}, "zone": {}, "vehicle": {}, "build": {}, "selector": {}, "scope": {}, "trial_facts": {}}
		if str(job.kind) in ["technology_feature", "technology_vehicle"]:
			var controlled: Dictionary = _prepared_controlled_features.get(key, {})
			if controlled.is_empty() or not is_same(controlled.job, job) or not is_same(controlled.task, task): return Runtime.fail("STALE_SOURCE")
			var target_ref: Dictionary
			if str(job.kind) == "technology_feature":
				item.feature = job.feature_ref
				item.zone = job.zone_ref
				item.build = job.get("repair_ref", {})
				target_ref = item.feature
			else:
				item.vehicle = job.vehicle_ref
				item.build = job.build_ref
				target_ref = item.vehicle
			item.trial_facts = Runtime.technology_trial_work_facts(lab.terrain, target_ref, task, int(job.executor_id)) if target_ref.has("tech_trial") else Runtime.ok("", {"policy_exception": ""})
			if not item.trial_facts.ok: return item.trial_facts
			item.selector = job.operation_selector.duplicate(true)
			if job.operation_selector.has("token"):
				var token: Dictionary = job.operation_selector.token
				var authority: Dictionary = technology_phase_active_guard(token) # original start-only query.
				if not authority.ok: return authority
				item.scope = {"token": token, "token_start": token.duplicate(true), "owner": authority.owner,
					"record": authority.record, "project": authority.project, "project_start": authority.project.duplicate(true)}
		held[key] = item
	return Runtime.ok("原人物作業起點與held refs已純捕捉", {"owner": self, "terrain": lab.terrain,
		"site": lab.terrain.site, "jobs_ref": _jobs, "seconds": seconds, "held": held})

func validate_shared_work_prefix(prepared: Dictionary, planned: Dictionary, requests: Array) -> Dictionary:
	# AFTER actual contacts, BEFORE any material/progress/Native final publication.
	# Original death queue remains undrained. HP/hit/THREAT at this endpoint cannot
	# erase the already qualified non-P5 prefix; product/receipt endpoints still
	# need their actual CURRENT original life/authority/material/geometry guards.
	if prepared.get("owner") != self or not is_same(prepared.get("terrain"), lab.terrain) \
		or not is_same(prepared.get("site"), lab.terrain.site) or not is_same(prepared.get("jobs_ref"), _jobs) \
		or planned.get("ok") != true or not is_equal_approx(float(planned.get("seconds", -1.0)), float(prepared.seconds)):
		return Runtime.fail("STALE_SOURCE")
	var current := {}
	for request: Dictionary in requests:
		if request.get("provider") != "person_actions": continue
		var key: String = str(request.get("key", ""))
		if current.has(key): return Runtime.fail("DUPLICATE_ACTIVITY")
		current[key] = request
	var allocations: Dictionary = planned.get("jobs", {}).get("person_actions", {})
	var admitted := {}
	for key: String in prepared.held:
		var held: Dictionary = prepared.held[key]
		var job: Dictionary = _jobs.get(key, {})
		if not is_same(job, held.job) or str(job.get("kind", "")) != held.kind \
			or not current.has(key) or not is_same(current[key].participants, held.request.participants) \
			or not is_same(job.get("work_task", held.task), held.task) or held.task != held.task_start \
			or float(job.get("elapsed", 0.0)) != float(held.elapsed) or float(job.get("duration", 0.0)) != float(held.duration):
			return Runtime.fail("STALE_SOURCE")
		for identity: int in held.people:
			var start: Dictionary = held.people[identity]
			var person: Dictionary = _person(identity) # current refs only, no forged alive projection.
			if person.is_empty() or person.owner != start.owner or int(person.unit) != int(start.unit) \
				or not is_same(person.body, start.body) or not is_same(person.holder, start.holder) \
				or not is_same(person.cargo, start.cargo) or int(person.holder.version) != int(start.holder_version):
				return Runtime.fail("STALE_SOURCE")
		if held.kind in ["technology_feature", "technology_vehicle"]:
			var target_ref: Dictionary = held.feature if held.kind == "technology_feature" else held.vehicle
			if held.kind == "technology_feature":
				if not is_same(lab.terrain.site.features.get(job.feature_id), held.feature) \
					or int(job.work_task.zone) < 0 or int(job.work_task.zone) >= lab.terrain.site.zones.size() \
					or not is_same(lab.terrain.site.zones[int(job.work_task.zone)], held.zone) \
					or not is_same(job.feature_ref, held.feature) or not is_same(job.zone_ref, held.zone) \
					or job.operation_selector != held.selector or held.task.action == "repair" and not is_same(held.feature.get("repair"), held.build): return Runtime.fail("STALE_SOURCE")
			else:
				if not is_same(lab.terrain.site.get("vehicles"), job.vehicles_ref) or not is_same(job.vehicles_ref.get(job.vehicle_id), held.vehicle) or not is_same(job.vehicle_ref, held.vehicle) or not is_same(held.vehicle.get("repair" if held.task.action == "repair" else "build"), held.build) or not is_same(job.build_ref, held.build) or job.operation_selector != held.selector: return Runtime.fail("STALE_SOURCE")
			if not held.scope.is_empty():
				var scope: Dictionary = held.scope
				if not is_same(target_ref.get("tech_trial"), scope.token) or scope.token != scope.token_start \
					or not is_same(_technology_scope_owner(str(scope.token.scope), str(scope.token.scope_id)), scope.owner) \
					or not is_same(scope.owner.get("technology"), scope.record) \
					or not is_same(Technology.active_project(scope.record), scope.project) or scope.project != scope.project_start:
					return Runtime.fail("STALE_PROJECT")
		var allocation: Dictionary = allocations.get(key, {})
		if allocation.is_empty(): continue # A rejected/waiting request grants no prefix.
		var actual: float = float(allocation.get("actual_seconds", 0.0))
		var productive: float = float(allocation.get("effective_seconds", 0.0))
		if not is_finite(actual) or not is_finite(productive) or actual < 0.0 or actual > float(prepared.seconds) + Fatigue.WORK_PLAN_EPS or productive < 0.0:
			return Runtime.fail("INVALID_WORK")
		var active := false
		for identity: int in held.people:
			var effort: float = float(allocation.get("participant_seconds", {}).get(identity, 0.0))
			if not is_finite(effort) or effort < 0.0 or effort > float(prepared.seconds) + Fatigue.WORK_PLAN_EPS: return Runtime.fail("INVALID_WORK")
			if effort > 0.0: active = true
		if active or held.kind in ["technology_feature", "technology_vehicle"] and float(held.request.get("remaining", -1.0)) == 0.0: admitted[key] = {"held": held, "allocation": allocation, "advance_consumed": false}
	return Runtime.ok("原合法起點前綴已預驗；無成本／進度寫入", {"owner": self, "prepared": prepared,
		"plan": planned, "seconds": float(prepared.seconds), "admitted": admitted})

func publish_gd_contact_job_segment(segment: Dictionary) -> void:
	assert(is_same(segment, _gd_contact_job_segment) and not bool(segment.published))
	for candidate: Dictionary in segment.runtime:
		Runtime.publish_checked_work_prefix(candidate)
		_gd_contact_job_capture.runtime_priors.append(candidate)
	for prefix: Dictionary in segment.prefixes:
		var held: Dictionary = prefix.shared_item.held
		_controlled_feature_consumed[str(held.key)] = true
		held.job.paused = str(prefix.allocation.get("paused", ""))
		var person: Dictionary = _person(int(prefix.person_id))
		if not person.is_empty() and not bool(person.player):
			if float(prefix.actual_seconds) > 0.0: _body_set(person, "work_resting", false)
			if str(prefix.allocation.get("participant_paused", {}).get(int(prefix.person_id), prefix.allocation.get("paused", ""))) == "REST": _body_set(person, "work_resting", true)
	for key: String in _gd_contact_job_capture.prepared.held:
		var held: Dictionary = _gd_contact_job_capture.prepared.held[key]
		if held.kind in ["technology_feature", "technology_vehicle"]: _controlled_feature_consumed[key] = true
	for candidate: Dictionary in segment.candidates:
		var held: Dictionary = candidate.held
		var job: Dictionary = held.job
		job.elapsed = float(candidate.elapsed)
		job.paused = str(candidate.allocation.get("paused", ""))
		settlement_food_prefix_progress(job)
		if job.paused == "REST" and float(job.elapsed) >= float(held.duration) - Fatigue.WORK_PLAN_EPS: job.paused = ""
		held.committed_elapsed = float(job.elapsed)
		for identity: int in held.people:
			var person: Dictionary = _person(identity)
			if person.is_empty() or bool(person.player): continue
			var actual: float = float(candidate.allocation.get("participant_seconds", {}).get(identity, 0.0))
			if actual > 0.0: _body_set(person, "work_resting", false)
			if str(candidate.allocation.get("participant_paused", {}).get(identity, candidate.allocation.get("paused", ""))) == "REST":
				_body_set(person, "work_resting", true)
	_gd_contact_job_capture.elapsed = float(_gd_contact_job_capture.elapsed) + float(segment.seconds)
	_gd_contact_job_capture.published.append(segment)
	segment.published = true
	_gd_contact_job_segment = {}

func finish_gd_contact_job_prefix() -> void:
	# Original settle_after_contacts owns all CURRENT output/receipt/learning.
	# No elapsed advance(), material callback or proxy fatigue fallback here.
	var last: Array[Dictionary] = []
	for candidate: Dictionary in _gd_contact_job_capture.get("runtime_priors", []):
		for index: int in range(last.size() - 1, -1, -1):
			if is_same(last[index].unit, candidate.unit): last.remove_at(index)
		last.append(candidate)
	for candidate: Dictionary in last: Runtime.settle_checked_work_prefix(candidate)
	discard_checked_controlled_prefixes()
	_gd_contact_job_capture = {}
	_gd_contact_job_segment = {}

func finish_shared_nonwork_timers(prepared: Dictionary) -> void:
	if prepared.get("owner") != self or bool(prepared.get("finished", false)): return
	prepared.finished = true
	for held: Dictionary in prepared.held:
		var job: Dictionary = _jobs.get(str(held.key), {})
		if not is_same(job, held.job): continue
		var current: Dictionary = _job_context(job)
		if not current.ok: _finish(str(held.key), current); continue
		var person: Dictionary = _person(int(job.executor_id))
		if bool(held.watched) or int(person.hit) != int(held.hit) or _escape_blocked(person, {}):
			job.elapsed = 0.0
			job.paused = "WATCHED"
			job.executor_hit = int(person.hit)
		else:
			job.paused = ""
			job.elapsed = minf(ESCAPE_SECONDS, float(held.elapsed) + float(prepared.seconds))

# ORIGINAL Lab caller supplement:
# preWorld: nonwork = PA.prepare_shared_nonwork_timers(actual_game_seconds)
# nofail tail (after begin_shared_work_prefix_consumption):
#   PA.publish_checked_controlled_prefixes(checked.controlled)
#   PA.publish_shared_job_prefix_timers(checked.person_actions)
#   PA.end_shared_work_prefix_consumption()
# Never call legacy PA.advance in this tail, even for no-allocation jobs.
# after World pub:
#   PA.finish_shared_job_prefix_timers(checked.person_actions)
#   PA.finish_shared_nonwork_timers(nonwork)
#   checked control/WT/Training REST and true current endpoints, then
#   original PA.settle_after_contacts / true Native death event handoff.
# Native suppression approach stays ORIGINAL prepare/actions before World;
# final P5 classification/cost comes only from its already prevalidated pack.

func _controlled_feature_job_context(job: Dictionary) -> Dictionary:
	if job.get("kind") == "technology_vehicle": return _controlled_vehicle_job_context(job)
	if not is_same(job.get("terrain"), lab.terrain) or not is_same(job.get("site_state"), lab.terrain.site) \
		or not is_same(job.get("features_ref"), lab.terrain.site.features) or not is_same(job.get("zones_ref"), lab.terrain.site.zones) \
		or not is_same(lab.terrain.site.features.get(job.feature_id), job.feature_ref): return Runtime.fail("STALE_SOURCE")
	var task: Dictionary = job.work_task
	if int(task.zone) < 0 or int(task.zone) >= lab.terrain.site.zones.size() or not is_same(lab.terrain.site.zones[int(task.zone)], job.zone_ref) \
		or job.zone_ref.get("active") != true or task.target != "feature:" + str(job.feature_id) or task.action != job.zone_ref.action: return Runtime.fail("NO_ZONE")
	if task.action == "repair" and not is_same(job.feature_ref.get("repair"), job.get("repair_ref")): return Runtime.fail("STALE_SOURCE")
	var person := _person(int(job.executor_id))
	if person.is_empty() or not is_same(person.owner, job.executor_owner) or not is_same(person.body, job.technology_executor_body) \
		or not is_same(person.holder, job.executor_holder) or not is_same(person.cargo, job.executor_cargo) \
		or int(person.holder.version) != int(job.executor_version) or int(person.hit) != int(job.executor_hit) \
		or lab.terrain.index(person.cell) != int(job.executor_cell) or int(task.cell) != int(task.work_cell) or int(task.work_cell) != int(job.executor_cell): return Runtime.fail("INTERRUPTED")
	if not _ready(person) or _threat(person, {}): return Runtime.fail("BUSY")
	var selector: Dictionary = job.operation_selector
	var authority: Dictionary
	if selector.has("token"):
		if not is_same(job.feature_ref.get("tech_trial"), selector.token): return Runtime.fail("STALE_PROJECT")
		authority = technology_phase_active_guard(selector.token)
	elif Technology.keys(selector, ["irrigation"]):
		authority = Runtime.technology_irrigation_work_preflight(lab.terrain, selector, false)
	else:
		authority = technology_build_admission(selector)
	if not authority.ok: return authority
	return Runtime.ok("原已受理本人／當前原職責與同意仍有效", {"person": person})

func _valid_gd_checked_controlled_prefix(prefix: Dictionary) -> bool:
	for envelope: Dictionary in _gd_contact_job_capture.get("controlled_envelopes", []):
		if is_same(prefix.get("entry"), envelope.prepared.prefix_ref.entry): return valid_gd_contact_work_prefix(envelope, prefix, prefix.runtime_priors)
	return false

func checked_work_prefix_for_task(task: Dictionary, identity: int) -> Dictionary:
	if not _gd_contact_job_segment.is_empty():
		for prefix: Dictionary in _gd_contact_job_segment.prefixes:
			if int(prefix.person_id) == identity and is_same(prefix.task, task): return prefix
		return lab.checked_shared_vehicle_prefix_for_task(task, identity) if lab.has_method("checked_shared_vehicle_prefix_for_task") else {}
	for prefix: Dictionary in _checked_controlled_prefixes.get("prefixes", []):
		if int(prefix.person_id) == identity and is_same(prefix.task, task): return prefix
	return lab.checked_shared_vehicle_prefix_for_task(task, identity) if lab.has_method("checked_shared_vehicle_prefix_for_task") else {}

func owned_checked_work_prefixes() -> Array:
	return _gd_contact_job_segment.prefixes if not _gd_contact_job_segment.is_empty() else _checked_controlled_prefixes.get("prefixes", [])

func _controlled_vehicle_job_context(job: Dictionary) -> Dictionary:
	if not is_same(job.get("terrain"), lab.terrain) or not is_same(job.get("site_state"), lab.terrain.site) \
		or not is_same(job.get("vehicles_ref"), lab.terrain.site.get("vehicles")) or not is_same(job.vehicles_ref.get(job.vehicle_id), job.vehicle_ref) \
		or not is_same(job.vehicle_ref.get("repair" if job.work_task.action == "repair" else "build"), job.build_ref) or job.build_ref.is_empty() \
		or job.work_task.target != "vehicle:" + str(job.vehicle_id) or job.work_task.action not in ["construct", "repair"]: return Runtime.fail("STALE_SOURCE")
	var person := _person(int(job.executor_id))
	if person.is_empty() or not is_same(person.owner, job.executor_owner) or not is_same(person.body, job.technology_executor_body) \
		or not is_same(person.holder, job.executor_holder) or not is_same(person.cargo, job.executor_cargo) \
		or int(person.holder.version) != int(job.executor_version) or int(person.hit) != int(job.executor_hit) \
		or lab.terrain.index(person.cell) != int(job.executor_cell) or int(job.work_task.cell) != int(job.executor_cell) \
		or (not is_same(person.owner if person.owner is CrowdOwner else _technology_team(person), job.team_ref) if job.work_task.action == "repair" else not is_same(_technology_team(person), job.team_ref)) or int(job.team_ref.team_id) != int(job.vehicle_ref.team_id): return Runtime.fail("INTERRUPTED")
	if not _ready(person) or _threat(person, {}): return Runtime.fail("BUSY")
	var selector: Dictionary = job.operation_selector
	var authority: Dictionary
	if job.work_task.action == "repair":
		authority = Runtime.settlement_spare_work_guard(lab.terrain, job.vehicle_ref, job.work_task, int(job.executor_id))
	elif selector.has("token"):
		if not is_same(job.vehicle_ref.get("tech_trial"), selector.token): return Runtime.fail("STALE_PROJECT")
		authority = technology_phase_active_guard(selector.token)
	elif not selector.is_empty(): authority = equipment_orders.public_work_preflight(str(selector.nation_id), str(selector.order_id), "ballista_build")
	else:
		if job.team_ref.combat_order != TerrainArmy.CombatOrder.HOLD or job.team_ref.get_active_move_plan() != null \
			or job.team_ref.has_ship_journey() or job.team_ref._team_ship_activity() \
			or bool(lab.terrain.site.get("team_supply", {}).get(str(job.team_ref.team_id), {}).get("training_order", false)): return Runtime.fail("BUSY")
		authority = Runtime.ok()
	if not authority.ok: return authority
	return Runtime.ok("原已受理本人仍在本器械原工位", {"person": person})

func fire_pot_craft_guard(identity: int, token: Dictionary = {}, preview: bool = false) -> Dictionary:
	if TechnologyCatalog.get_node("F15").get("enabled") != true: return Runtime.fail("UNIMPLEMENTED")
	var person := _person(identity)
	if person.is_empty(): return Runtime.fail("NO_AUTHORITY")
	if float(person.hp) <= 0.0 or float(person.ko) > 0.0 or bool(person.captive): return Runtime.fail("BUSY")
	if not token.is_empty():
		if not _technology_member(identity): return Runtime.fail("NO_AUTHORITY")
		return _scope_ranged_craft_guard(identity, token, preview)
	if not Technology.learned(_body_get(person, "technology"), "F15"): return Runtime.fail("NO_TECHNOLOGY", "原製作者本人須已學會 F15")
	return Runtime.ok()

func scope_ranged_craft_guard(identity: int, recipe: String, token: Dictionary, preview: bool = false) -> Dictionary:
	return _scope_ranged_craft_guard(identity, token, preview) if recipe == _scope_ranged_recipe(token) and not recipe.is_empty() else Runtime.fail("INVALID_TECHNOLOGY")

func _commit_settlement_food_work(job: Dictionary) -> Dictionary:
	var checked := _settlement_food_job_context(job)
	if not checked.ok: return checked
	if float(job.elapsed) != 300.0 or checked.order.receipts.size() != 2: return Runtime.fail("WAITING")
	var phase := {}
	if not job.nation_token.is_empty():
		phase = technology_phase_receipt_candidate(job.nation_token, _settlement_food_event(job))
		if not phase.ok: return phase
	var order: Dictionary = checked.order
	var arrival: Dictionary = order.receipts[1]
	var receipt := {"id": JSON.stringify([_technology_site_id(), str(order.payload.settlement_id), str(order.id), "work"]), "kind": "work", "operator_id": int(job.executor_id),
		"from": "feature:" + str(order.payload.warehouse_id), "to": "feature:" + str(order.payload.warehouse_id), "quantity": int(order.payload.quantity),
		"source_version": int(arrival.destination_version), "destination_version": int(arrival.destination_version), "work_seconds": 300.0}
	# All current life/Scope/source-history/real delivery checks precede this tail.
	order.receipts.append(receipt)
	order.payload.work_seconds = 300.0
	order.payload.stage = "completed"
	order.status = "completed"
	order.revision = int(order.revision) + 1
	if not phase.is_empty(): publish_phase_receipt(phase)
	lab.terrain.environment_revision += 1
	return Runtime.ok("原有限糧食單完成；真轉移與工時各一次")

func _commit_water_schedule(job: Dictionary) -> Dictionary:
	var event := _water_schedule_event(job)
	var samples := water_schedule_receipt_query(job.nation_token, event)
	if not samples.ok: return samples
	var phase := technology_phase_receipt_candidate(job.nation_token, event)
	if not phase.ok: return phase
	# The same original allocator's second sample and sole Scope receipt publish
	# together. No fallible authority, capacity, source or callback follows.
	lab.terrain.site.water_status = samples.second.allocation
	publish_phase_receipt(phase)
	lab.terrain.environment_revision += 1
	return Runtime.ok("原300秒供水排程試驗完成，供水總量守恆")

func finish_controlled_feature_work(feature_id: String) -> void:
	# Original Runtime calls in its successful no-yield receipt tail. No source
	# lookup, command permission, arbitrary callback or duplicate product here.
	for key: String in _jobs.keys():
		var job: Dictionary = _jobs[key]
		if job.get("kind") == "technology_feature" and job.get("feature_id") == feature_id:
			_finish(key, Runtime.ok("原具名工序已完成；本人停止這項工作"))

func finish_controlled_vehicle_work(vehicle_id: String) -> void:
	for key: String in _jobs.keys():
		var job: Dictionary = _jobs[key]
		if job.get("kind") == "technology_vehicle" and job.get("vehicle_id") == vehicle_id: _finish(key, Runtime.ok("原器械施工已完成，本人停止這項工作"))

func nation_operation_material_source_candidate(nation_id: String, order_id: String, binding_id: String) -> Dictionary:
	if order_id.begins_with("production_"):
		if binding_id != "workshop_bow": return Runtime.fail("STALE_ORDER")
		var military := _nation_military_material_source(nation_id, order_id, true)
		return Runtime.ok("", {"source": military}) if military.ok else military
	var context := _nation_original_order_context(nation_id, order_id, binding_id)
	if not context.ok: return context
	var order: Dictionary = context.order
	if int(order.project_id) != 0 or not Technology.scope_known(context.nation.technology, str(order.tech_id)): return Runtime.fail("STALE_PROJECT")
	if not order.payload.has("source"): return Runtime.ok("", {"source": {}})
	if not equipment_orders._public_source_paid(order): return Runtime.fail("NO_BUDGET")
	var source: Dictionary = order.payload.source
	var stock := SiteStockpiles.stock_endpoint(lab.terrain, str(order.payload.get("reserve_feature_id", "")))
	if stock.is_empty(): return Runtime.fail("NO_SOURCE")
	return Runtime.ok("", {"source": Runtime.ok("", {"kind": "nation_order", "holder": "nation-order:" + JSON.stringify([_technology_site_id(), nation_id, order_id]),
		"source_site_id": _technology_site_id(), "grantor": {"site_id": _technology_site_id(), "person_id": int(source.person_id)},
		"cap": source.cap.duplicate(), "spent": {}, "physical_holder": stock.holder, "physical_cargo": stock.cargo,
		"holder_version": int(stock.holder.version), "expected_refs": {"terrain": lab.terrain, "site": lab.terrain.site, "nation": context.nation,
			"operations": context.operations, "order": order, "holder": stock.holder, "cargo": stock.cargo}})})

func technology_phase_material_source_candidate(token: Dictionary) -> Dictionary:
	if not Technology.keys(token, ["scope", "scope_id", "project_id", "epoch", "purpose", "tech_id", "phase_id", "attempt", "person", "binding", "target_id", "materials"]): return Runtime.fail("INVALID_TECHNOLOGY")
	var context := _technology_phase_context(token, true, false)
	if not context.ok: context = _technology_phase_context(token, false, false)
	if not context.ok: return context
	if token.tech_id == "N05" and token.scope == "nation":
		var candidates: Array[Dictionary] = []
		for order_id: String in context.owner.get("technology_operations", {}).get("orders", {}):
			var source := nation_research_source_candidate(token, order_id)
			if not source.ok: continue
			if not context.project.budget.is_empty() and context.project.budget.holder != source.holder: continue
			var checked := _technology_original_source_query(token, source)
			if checked.ok: candidates.append(checked)
		if candidates.size() != 1: return Runtime.fail("NO_BUDGET" if candidates.is_empty() else "AMBIGUOUS_SOURCE")
		return Runtime.ok("", {"source": candidates[0]})
	if token.scope == "settlement" and token.tech_id in ["S03", "S04", "S05", "S06", "S12"]:
		var settlement_sources: Array[Dictionary] = []
		for order_id: String in context.owner.get("technology_operations", {}).get("orders", {}):
			var order: Dictionary = context.owner.technology_operations.orders[order_id]
			if int(order.get("payload", {}).get("project_id", -1)) != int(token.project_id) or order.get("payload", {}).get("purpose") != token.purpose: continue
			var actual: Dictionary = settlement_research_source_candidate(token, order_id)
			if not actual.ok: continue
			if not context.project.budget.is_empty() and context.project.budget.holder not in [actual.holder, "no_materials"]: continue
			var checked: Dictionary = _technology_settlement_source_query(token, actual)
			if checked.ok: settlement_sources.append(checked)
		if settlement_sources.size() != 1: return Runtime.fail("NO_BUDGET" if settlement_sources.is_empty() else "AMBIGUOUS_SOURCE")
		return Runtime.ok("", {"source": settlement_sources[0]})
	if token.materials.is_empty(): return Runtime.ok("", {"source": {}})
	var budget: Dictionary = context.project.budget
	if not budget.is_empty() and budget.holder == "depot":
		var existing := _technology_phase_context(token, true)
		if not existing.ok: existing = _technology_phase_context(token)
		return Runtime.ok("", {"source": {}}) if existing.ok else existing
	if token.scope != "nation" or equipment_orders == null: return Runtime.fail("NO_BUDGET")
	var candidates: Array[Dictionary] = []
	var orders: Dictionary = context.owner.get("technology_operations", {}).get("public_orders", {})
	for order_id: String in orders:
		var order: Dictionary = orders[order_id]
		if order.get("tech_id") != token.tech_id or int(order.get("project_id", -1)) != int(token.project_id) or order.get("status") == "revoked": continue
		var actual := nation_research_source_candidate(token, order_id)
		if not actual.ok: continue
		# Transfer/lesson paid witnesses belong to those original completions,
		# never a second debit at a construction material endpoint.
		if actual.has("paid_witness"): continue
		if not budget.is_empty() and budget.holder != actual.holder and budget.holder != "no_materials": continue
		var checked := _technology_original_source_query(token, actual)
		if checked.ok: candidates.append(checked)
	if candidates.size() != 1: return Runtime.fail("NO_BUDGET" if candidates.is_empty() else "AMBIGUOUS_SOURCE")
	return Runtime.ok("", {"source": candidates[0]})

func technology_build_admission(operation_selector: Dictionary) -> Dictionary:
	if Technology.keys(operation_selector, ["irrigation"]): return Runtime.technology_irrigation_work_preflight(lab.terrain, operation_selector)
	if Technology.keys(operation_selector, ["settlement_id", "order_id"]):
		var settlement: Dictionary = SiteSettlement.record(lab.terrain)
		var raw: Variant = settlement.get("technology_operations")
		if not SiteSettlement.valid_technology_operations(lab.terrain, raw): return Runtime.fail("CORRUPT_STATE")
		var order: Dictionary = raw.orders.get(operation_selector.order_id, {})
		if order.get("kind") != "defense" or order.get("status") not in ["prepared", "active"] or int(order.next_step) >= order.steps.size(): return Runtime.fail("NO_TARGET")
		return Runtime.settlement_defense_work_preflight(lab.terrain, operation_selector, {}, str(order.steps[int(order.next_step)].action))
	if Technology.keys(operation_selector, ["token"]) and operation_selector.token is Dictionary:
		if not has_method("technology_phase_work_preflight"): return Runtime.fail("UNIMPLEMENTED")
		var token: Dictionary = operation_selector.token
		var checked: Dictionary = call("technology_phase_work_preflight", token, true)
		if not checked.ok: checked = call("technology_phase_work_preflight", token, false)
		if not checked.ok: return checked
		var identity: int = int(checked.person.person_id)
		var operation_ref := {}
		if token.scope == "settlement" and token.tech_id in ["S03", "S04", "S05", "S06", "S12"]:
			var paid_context: Dictionary = _technology_paid_phase_context(token)
			var holder_name := ""
			if paid_context.ok and str(paid_context.project.budget.get("holder", "")).begins_with("settlement-order:"):
				holder_name = str(paid_context.project.budget.holder)
			else:
				var source: Dictionary = technology_phase_material_source_candidate(token)
				if not source.ok: return source
				holder_name = str(source.source.get("holder", ""))
			var source_parts: Variant = JSON.parse_string(holder_name.trim_prefix("settlement-order:"))
			if not source_parts is Array or source_parts.size() != 3 or source_parts[0] != _technology_site_id() or source_parts[1] != token.scope_id: return Runtime.fail("STALE_SOURCE")
			var admitted: Dictionary = _settlement_operation_context(str(token.scope_id), str(source_parts[2]), str(token.binding))
			if not admitted.ok or (admitted.person_ids != [identity] and (token.tech_id != "S12" or admitted.person_ids.size() != 2 or admitted.person_ids[0] != identity or admitted.order.kind != "ship_cooperation")): return admitted if not admitted.ok else Runtime.fail("NO_WORKER")
			admitted["scope_context"] = checked
			return admitted
		if token.scope == "nation" and token.tech_id == "N05":
			var source := technology_phase_material_source_candidate(token)
			if not source.ok: return source
			var order_source_parts: Variant = JSON.parse_string(str(source.source.holder).trim_prefix("nation-order:"))
			if not order_source_parts is Array or order_source_parts.size() != 3: return Runtime.fail("STALE_SOURCE")
			var admitted: Dictionary = equipment_orders.call("military_work_preflight", str(token.scope_id), str(order_source_parts[2]))
			if not admitted.ok or admitted.person_ids != [identity]: return admitted if not admitted.ok else Runtime.fail("NO_WORKER")
			admitted["scope_context"] = checked
			return admitted
		if token.scope == "nation" and equipment_orders != null:
			var orders: Dictionary = checked.owner.get("technology_operations", {}).get("public_orders", {})
			for order_id: String in orders:
				var order: Dictionary = orders[order_id]
				if order.get("tech_id") != token.tech_id or int(order.get("project_id", -1)) != int(token.project_id) or order.get("status") == "revoked": continue
				var admitted: Dictionary = equipment_orders.call("public_work_preflight", str(token.scope_id), order_id, str(token.binding))
				if not admitted.ok or not admitted.person_ids.has(identity): continue
				if not operation_ref.is_empty(): return Runtime.fail("AMBIGUOUS_SOURCE")
				operation_ref = {"nation_id": str(token.scope_id), "order_id": order_id}
		return Runtime.ok("", {"team": _technology_team(checked.person), "person_ids": [identity], "requester_id": _technology_controlled(), "operation_ref": operation_ref,
			"person": checked.person, "scope_context": checked})
	if Technology.keys(operation_selector, ["settlement_id", "order_id"]) and operation_selector.settlement_id is String and operation_selector.order_id is String:
		var order: Dictionary = lab.terrain.site.get("settlement", {}).get("technology_operations", {}).get("orders", {}).get(str(operation_selector.order_id), {})
		if order.get("kind") == "defense":
			if not SiteSettlement.valid_technology_operations(lab.terrain, lab.terrain.site.settlement.technology_operations): return Runtime.fail("CORRUPT_STATE")
			return Runtime.settlement_defense_work_preflight(lab.terrain, operation_selector)
		return _settlement_operation_context(operation_selector.settlement_id, operation_selector.order_id)
	if not Technology.keys(operation_selector, ["nation_id", "order_id"]) or not operation_selector.nation_id is String or not operation_selector.order_id is String \
		or operation_selector.nation_id.is_empty() or operation_selector.order_id.is_empty() or equipment_orders == null: return Runtime.fail("INVALID")
	if str(operation_selector.order_id).begins_with("production_"):
		if not equipment_orders.has_method("military_work_preflight"): return Runtime.fail("UNIMPLEMENTED")
		return equipment_orders.call("military_work_preflight", operation_selector.nation_id, operation_selector.order_id)
	if not equipment_orders.has_method("public_work_preflight"): return Runtime.fail("UNIMPLEMENTED")
	return equipment_orders.call("public_work_preflight", operation_selector.nation_id, operation_selector.order_id)

func prepare_controlled_vehicle_work(selector: Dictionary, vehicle: Dictionary, vehicles_candidate: Dictionary = {}, actual_operator_id: int = 0, repair_candidate: Dictionary = {}) -> Dictionary:
	if bool(lab.terrain.site.get("paused", false)): return Runtime.fail("BUSY")
	var spare := not repair_candidate.is_empty()
	var spare_resume := spare and is_same(vehicle.get("repair"), repair_candidate.get("repair"))
	if spare and (not spare_resume and not vehicle.get("repair", {}).is_empty() or not Runtime.valid_settlement_spare_repair_storage(lab.terrain, vehicle, repair_candidate)): return Runtime.fail("STALE_SOURCE")
	var admission := Runtime.settlement_spare_admission(lab.terrain, actual_operator_id, int(vehicle.get("team_id", -1)), selector.get("token", {}), vehicle if spare_resume else {}) if spare else (technology_vehicle_work_admission(actual_operator_id, int(vehicle.get("team_id", -1))) if selector.is_empty() else technology_build_admission(selector))
	if not admission.ok: return admission
	var identity := _technology_controlled()
	if admission.get("person_ids") != [identity] or is_busy(identity): return Runtime.fail("BUSY")
	var person := _person(identity)
	var team: Variant = admission.team if spare else _technology_team(person)
	if team == null or not _ready(person) or _threat(person, {}) or int(team.team_id) != int(vehicle.get("team_id", -1)): return Runtime.fail("NO_AUTHORITY")
	var definition: Dictionary = Runtime.SIEGE_DEFINITIONS.get(str(vehicle.get("kind", "")), {})
	var build: Dictionary = repair_candidate.repair if spare else vehicle.get("build", {})
	var action := "repair" if spare else "construct"
	if definition.is_empty() or (vehicle.get("phase") not in ["idle", "ready", "disabled"] if spare else vehicle.get("phase") != "building") or float(vehicle.get("hp", 0.0)) <= 0.0 or build.is_empty() \
		or not Technology.material_equal(build.get("paid_cost", {}), {"ballista_spares": 1} if spare else definition.cost) \
		or not is_equal_approx(float(build.get("total_work", -1.0)), 300.0 if spare else float(definition.work_seconds)) \
		or not Technology.finite_number(build.get("progress")) or float(build.progress) > float(build.total_work) \
		or not vehicle.get("action", {}).is_empty() or not vehicle.get("move", {}).is_empty() or not vehicle.get("crew_slots", {}).is_empty(): return Runtime.fail("NO_TARGET")
	var key := ""
	var vehicles: Dictionary = lab.terrain.site.get("vehicles", vehicles_candidate)
	if lab.terrain.site.has("vehicles") and not vehicles_candidate.is_empty() and not is_same(vehicles_candidate, vehicles) \
		or not lab.terrain.site.has("vehicles") and not vehicles_candidate.is_empty(): return Runtime.fail("STALE_SOURCE")
	for current: String in lab.terrain.site.get("vehicles", {}):
		if is_same(lab.terrain.site.vehicles[current], vehicle): key = current; break
	var prospective := key.is_empty()
	if prospective: key = str(int(lab.terrain.site.get("next_vehicle", 1)))
	if vehicle.get("id") != key: return Runtime.fail("STALE_SOURCE")
	var token: Dictionary = repair_candidate.get("tech_trial", {}) if spare else vehicle.get("tech_trial", {})
	var held_selector := selector.duplicate()
	if selector.has("token"):
		if token.is_empty() or selector.token != token or token.target_id != "vehicle:" + key: return Runtime.fail("STALE_PROJECT")
		held_selector.token = token
	var physical: int = lab.terrain.index(person.cell)
	var selected := {}
	var claims: Dictionary = lab.site_controller.work_team.reserved_targets()
	for slot: Dictionary in Runtime.siege_work_slots(lab.terrain, vehicle):
		if int(slot.cell) != physical: continue
		if not selected.is_empty(): return Runtime.fail("INVALID_OWNER")
		if claims.has(Runtime.work_claim_key({"target": "vehicle:" + key, "action": action, "work_slot": int(slot.slot)})): return Runtime.fail("BUSY")
		selected = slot
	if selected.is_empty() or not lab.terrain.is_walkable(person.cell): return Runtime.fail("UNREACHABLE", "受控原人须已在本器械的原施工工位")
	var clear := technology_vehicle_station_clear(held_selector, vehicle, person.cell, actual_operator_id, repair_candidate)
	if not clear.ok: return clear
	for job: Dictionary in _jobs.values():
		if job.get("kind") in ["technology_feature", "technology_vehicle"] and Runtime.work_claim_key(job.work_task) == "vehicle:" + key + "@" + str(int(selected.slot)): return Runtime.fail("BUSY")
	var source := {}
	if spare:
		if not Runtime.can_pay(lab.terrain.site.inventory, {"tools": 1}) or not spare_resume and not Runtime.can_pay(lab.terrain.site.inventory, build.paid_cost): return Runtime.fail("MATERIALS")
		if spare_resume:
			source = Runtime.technology_existing_paid_phase_source(lab.terrain, token) if selector.has("token") else Runtime.ok("原已付備件")
		else:
			source = technology_phase_material_source_candidate(token) if selector.has("token") else Runtime.ok("原營地實物備件", {"source": {"physical_holder": lab.terrain.site.depot_items}})
		if not source.ok: return source
	elif not prospective:
		if selector.has("token"):
			source = Runtime.technology_existing_paid_phase_source(lab.terrain, token)
			if not source.ok: return source
			var active := technology_phase_active_guard(token)
			if not active.ok: return active
		elif not selector.is_empty():
			var ledger: Dictionary = vehicle.get("tech_batch", {})
			if not Runtime.validate_technology_target_storage(lab.terrain, key, vehicle, "vehicle").ok or not ledger.get("token", {}).is_empty() \
				or vehicle.get("technology_order", {}) != selector or not Technology.material_equal(ledger.get("materials", {}), build.paid_cost): return Runtime.fail("STALE_SOURCE")
			source = Runtime.ok("原已付公共器械", {"ledger": ledger})
	else:
		if selector.is_empty():
			if not Runtime.can_pay(lab.terrain.site.inventory, build.paid_cost) or not Runtime.can_pay(lab.terrain.site.inventory, {"tools": 1}): return Runtime.fail("MATERIALS")
			source = Runtime.ok("原營地普通施工", {"source": {"physical_holder": lab.terrain.site.depot_items}})
		else:
			source = technology_phase_material_source_candidate(token) if selector.has("token") \
				else nation_operation_material_source_candidate(str(selector.nation_id), str(selector.order_id), "ballista_build")
		if not source.ok: return source
	var task := {"version": 3, "zone": -1, "target": "vehicle:" + key, "action": action, "work_cell": physical, "cell": physical,
		"mode": "work", "progress": 0.0, "status": "受控原人固定原器械工位", "work_slot": int(selected.slot), "named": true,
		"operation_ref": admission.get("operation_ref", {}).duplicate()}
	var job := _new_job(person, "technology_vehicle", 0)
	job.merge({"duration": 0.0, "terrain": lab.terrain, "site_state": lab.terrain.site, "technology_executor_body": person.body,
		"executor_owner": person.owner, "executor_holder": person.holder, "executor_cargo": person.cargo, "executor_version": int(person.holder.version),
		"vehicle_id": key, "vehicle_ref": vehicle, "vehicles_ref": vehicles, "build_ref": build,
		"team_ref": team, "work_task": task, "operation_selector": held_selector, "source_admission": source, "spare_original_team": admission.get("original_team"), "repair_candidate": repair_candidate})
	var source_holder: Variant = source.get("source", {}).get("physical_holder")
	if prospective and is_same(source_holder, person.holder): job.executor_version = int(person.holder.version) + 1
	return Runtime.ok("原本人／原器械工位／原有限用途預檢完成", {"job_key": str(identity), "job": job, "prior_jobs": _jobs,
		"terrain": lab.terrain, "site": lab.terrain.site, "vehicle": vehicle, "person": person})

func publish_controlled_vehicle_work(prepared: Dictionary) -> void:
	assert(prepared.ok and is_same(prepared.prior_jobs, _jobs) and not _jobs.has(prepared.job_key))
	var job: Dictionary = prepared.job
	assert(is_same(prepared.terrain, lab.terrain) and is_same(prepared.site, lab.terrain.site) \
		and is_same(job.vehicles_ref, lab.terrain.site.vehicles) and is_same(job.vehicles_ref.get(job.vehicle_id), prepared.vehicle))
	assert(is_same(prepared.person.holder, job.executor_holder) and int(job.executor_holder.version) == int(job.executor_version))
	if not job.get("repair_candidate", {}).is_empty(): assert(is_same(job.vehicle_ref.get("repair"), job.repair_candidate.repair))
	_jobs[prepared.job_key] = job

func technology_vehicle_work_admission(operator_id: int, team_id: int) -> Dictionary:
	if operator_id <= 0 or team_id <= 0 or bool(lab.terrain.site.get("paused", false)) or float(lab.terrain.site.get("combat_left", 0.0)) > 0.0: return Runtime.fail("BUSY")
	var person := _person(operator_id)
	var team: Variant = _technology_team(person)
	if team == null or not team is TerrainArmy or int(team.team_id) != team_id or not lab.combat_armies.has(team) \
		or not team.combat_enabled or team.combat_order != TerrainArmy.CombatOrder.HOLD: return Runtime.fail("NO_AUTHORITY")
	var duty: Dictionary = team.duty_resolve_readonly("team.work", team)
	if not duty.ok or int(duty.get("decider", -1)) != _technology_controlled(): return Runtime.fail("NO_AUTHORITY")
	if not _ready(person) or _threat(person, {}) or is_busy(operator_id) or team.is_sustain_routed() or team.get_active_move_plan() != null \
		or team.moving_member_count() > 0 or is_instance_valid(team.player_member) and team.player_member.is_moving() \
		or team.has_ship_journey() or team._team_ship_activity() \
		or bool(lab.terrain.site.get("team_supply", {}).get(str(team_id), {}).get("training_order", false)): return Runtime.fail("BUSY")
	return Runtime.ok("原工作首長明示本次普通器械工人", {"team": team, "person_ids": [operator_id], "requester_id": _technology_controlled(),
		"operation_ref": {}, "controlled_worker": operator_id == _technology_controlled(), "person": person})

# Re-query the named ORIGINAL person at an original construction station. This
# is an occupancy query only; it does not approve a job or bypass a reservation.

func technology_vehicle_station_clear(selector: Dictionary, vehicle: Dictionary, cell: Vector2i, actual_operator_id: int = 0, repair_candidate: Dictionary = {}) -> Dictionary:
	var admission := Runtime.settlement_spare_admission(lab.terrain, actual_operator_id, int(vehicle.get("team_id", -1)), selector.get("token", {}), vehicle if is_same(vehicle.get("repair"), repair_candidate.get("repair")) else {}) if not repair_candidate.is_empty() else (technology_vehicle_work_admission(actual_operator_id, int(vehicle.get("team_id", -1))) if selector.is_empty() else technology_build_admission(selector))
	if not admission.ok: return admission
	if admission.get("person_ids", []).size() != 1: return Runtime.fail("NO_OPERATOR")
	var person := _person(int(admission.person_ids[0]))
	var original: Variant = admission.get("original_team", admission.get("team")) if not repair_candidate.is_empty() else _technology_team(person)
	if person.is_empty() or original == null or int(original.team_id) != int(vehicle.get("team_id", -1)) or person.cell != cell or not _ready(person): return Runtime.fail("OCCUPIED")
	var at_station := false
	for station: Dictionary in Runtime.siege_work_slots(lab.terrain, vehicle):
		if int(station.cell) == lab.terrain.index(cell): at_station = true; break
	if not at_station: return Runtime.fail("OCCUPIED")
	var controller: Variant = lab.site_controller
	if controller.vehicles.blocks_cell(cell): return Runtime.fail("OCCUPIED")
	if person.owner is TerrainTestCharacter:
		if controller._actor_people_blocked(cell, person.owner): return Runtime.fail("OCCUPIED")
	elif controller.work_team._occupied(cell, person.owner, int(person.unit)): return Runtime.fail("OCCUPIED")
	# Passage protection belongs to the original formations, including this
	# worker's own formation. No standing worker makes that lease disappear.
	for team: TerrainArmy in lab.combat_armies:
		if team.has_army() and team._passage_cell_is_protected(cell): return Runtime.fail("OCCUPIED")
	if "combat_movement_coordinator" in lab and lab.combat_movement_coordinator != null:
		var lease: Variant = lab.combat_movement_coordinator.deployment_registry.slot_owners.get(cell)
		if lease != null and int(lease.formation_id) != int(original.team_id): return Runtime.fail("OCCUPIED")
	return Runtime.ok("只排除已核定且实际站在本原工位的这名原工人", {"person": person})

# APPEND to ORIGINAL PA after shared-start and controlled feature/vehicle packs.
# SAME _jobs/_prepared_controlled_features only. Root merges function-local.

func prepare_controlled_feature_work(selector: Dictionary, feature: Dictionary, zone: Dictionary, action: String = "construct", repair_candidate: Dictionary = {}) -> Dictionary:
	if action not in ["construct", "operate", "repair"] or bool(lab.terrain.site.get("paused", false)): return Runtime.fail("INVALID")
	var admission := technology_build_admission(selector)
	if not admission.ok: return admission
	var identity := _technology_controlled()
	if not admission.get("person_ids") is Array or admission.person_ids != [identity] or is_busy(identity): return Runtime.fail("BUSY")
	var person := _person(identity)
	if person.get("owner") is CrowdOwner and not person.owner.crowd_site.work_fatigue_work_start_ready(identity): return Runtime.fail("BUSY")
	if not _ready(person) or _threat(person, {}): return Runtime.fail("BUSY")
	if floori(Runtime.CARRY_CAPACITY - Runtime.carried_load(lab.terrain.site, {}, person.holder)) < 0: return Runtime.fail("STORAGE_FULL")
	var layout := Runtime.validate_feature_layout(lab.terrain, feature, false)
	if not layout.ok: return layout
	if int(feature.get("owner_faction", -1)) >= 0 and int(feature.owner_faction) != int(person.faction): return Runtime.fail("NO_AUTHORITY")
	var key := ""
	for current_key: String in lab.terrain.site.features:
		if is_same(lab.terrain.site.features[current_key], feature): key = current_key; break
	var prospective := key.is_empty()
	if not repair_candidate.is_empty() and (action != "repair" or prospective or not Runtime.valid_feature_repair_candidate(lab.terrain, feature, repair_candidate) \
		or not feature.get("repair", {}).is_empty() and not is_same(feature.repair, repair_candidate)): return Runtime.fail("STALE_SOURCE")
	var repair: Dictionary = feature.get("repair", {}) if repair_candidate.is_empty() else repair_candidate
	if prospective:
		if action != "construct": return Runtime.fail("STALE_SOURCE")
		key = str(int(lab.terrain.site.next_feature))
	var target := "feature:" + key
	if selector.has("token") and selector.token.get("target_id") != target: return Runtime.fail("STALE_PROJECT")
	var held_selector := selector.duplicate()
	var feature_token: Variant = feature.get("tech_trial", {})
	if not feature_token is Dictionary or not feature.get("tech_batch", {}) is Dictionary: return Runtime.fail("INVALID_TECHNOLOGY")
	if selector.has("token") and not feature_token.is_empty():
		if feature_token != selector.token: return Runtime.fail("STALE_PROJECT")
		held_selector.token = feature_token # Runtime's SAME actual prepared binding, not an equal token copy.
	if not (Technology.keys(zone, ["cells", "kind", "action", "feature", "active"]) or Technology.keys(zone, ["cells", "kind", "action", "feature", "active", "technology_owned"]) and zone.technology_owned == true and action == "operate") or zone.cells != feature.cells \
		or not Technology.integer(zone.kind, -1, -1) or zone.action != action or zone.feature != key or not zone.active is bool: return Runtime.fail("NO_ZONE")
	var zone_index := -1
	for index: int in lab.terrain.site.zones.size():
		if is_same(lab.terrain.site.zones[index], zone): zone_index = index; break
	if zone_index < 0:
		if not zone.active: return Runtime.fail("NO_ZONE")
		for current: Dictionary in lab.terrain.site.zones:
			if current.get("feature") == key and current.get("action") == action: return Runtime.fail("STALE_SOURCE")
		zone_index = lab.terrain.site.zones.size()
	var construction: Dictionary = feature.get("pending_build", feature)
	if action == "construct":
		if feature.get("stage") == "complete" and not feature.has("pending_build"): return Runtime.fail("NO_CHANGE")
		for resource_id: String in construction.get("clearing", []):
			if not bool(Runtime.Env.resource(lab.terrain, resource_id).get("cleared", true)): return Runtime.fail("CLEARING_REQUIRED")
	elif action == "repair":
		if repair.is_empty(): return Runtime.fail("NO_TARGET")
	elif feature.get("stage") != "complete" or feature.has("pending_build") or feature.has("repair") or not Runtime.feature_usable(feature): return Runtime.fail("NO_TARGET")
	var physical_cell: int = lab.terrain.index(person.cell)
	# Typed per branch: an untyped ternary literal cannot fill Array[Dictionary].
	var slots: Array[Dictionary] = []
	if action == "operate": slots = Runtime.feature_work_slots(lab.terrain, feature)
	else: slots.append({"slot": -1, "cell": int(repair.work_cell) if action == "repair" else int(construction.entrance)})
	var selected := {}
	for slot: Dictionary in slots:
		if int(slot.cell) != physical_cell: continue
		if not selected.is_empty(): return Runtime.fail("INVALID_OWNER")
		selected = slot
	if selected.is_empty() or not lab.terrain.is_walkable(person.cell): return Runtime.fail("UNREACHABLE", "受控原人須已站在這個原工位；不自動移動或選另一工位")
	var claim := Runtime.work_claim_key({"target": target, "action": action, "work_slot": int(selected.slot)})
	if lab.site_controller.work_team.reserved_targets().has(claim): return Runtime.fail("BUSY")
	for existing: Dictionary in _jobs.values():
		if existing.get("kind") == "technology_feature" and Runtime.work_claim_key(existing.work_task) == claim: return Runtime.fail("BUSY")
	var source := _controlled_feature_source(held_selector, feature, key, action, admission, repair)
	if not source.ok: return source
	var task := {"version": 3, "zone": zone_index, "target": target, "action": action, "work_cell": physical_cell, "cell": physical_cell,
		"mode": "work", "progress": 0.0, "status": "受控原人固定原工位", "work_slot": int(selected.slot), "named": true,
		"operation_ref": admission.get("operation_ref", {}).duplicate()}
	var job := _new_job(person, "technology_feature", 0)
	# duration/elapsed are original job envelope fields only. Neither produces an
	# item or completes this command; Runtime's actual endpoint is the sole end.
	job.merge({"duration": 0.0, "terrain": lab.terrain, "site_state": lab.terrain.site, "technology_executor_body": person.body,
		"executor_owner": person.owner, "executor_holder": person.holder, "executor_cargo": person.cargo,
		"executor_version": int(person.holder.version), "feature_id": key, "feature_ref": feature, "zone_ref": zone,
		"features_ref": lab.terrain.site.features, "zones_ref": lab.terrain.site.zones, "work_task": task,
		"operation_selector": held_selector, "source_admission": source, "repair_ref": repair})
	if not bool(source.get("already_paid", false)) and is_same(source.get("holder"), person.holder): job.executor_version = int(person.holder.version) + 1
	return Runtime.ok("原本人／原工位／原有限來源預檢完成", {"job_key": str(identity), "job": job, "prior_jobs": _jobs,
		"terrain": lab.terrain, "site": lab.terrain.site, "feature": feature, "zone": zone, "person": person})

func publish_controlled_feature_work(prepared: Dictionary) -> void:
	assert(prepared.ok and is_same(prepared.prior_jobs, _jobs) and not _jobs.has(prepared.job_key))
	var job: Dictionary = prepared.job
	assert(is_same(prepared.terrain, lab.terrain) and is_same(prepared.site, lab.terrain.site) \
		and is_same(job.features_ref, lab.terrain.site.features) and is_same(job.zones_ref, lab.terrain.site.zones))
	assert(is_same(job.features_ref.get(job.feature_id), prepared.feature) and is_same(job.zones_ref[int(job.work_task.zone)], prepared.zone) and prepared.zone.active)
	assert(is_same(prepared.person.holder, job.executor_holder) and int(job.executor_holder.version) == int(job.executor_version))
	if job.work_task.action == "repair": assert(is_same(prepared.feature.get("repair"), job.repair_ref))
	_jobs[prepared.job_key] = job

func _fire_pot_crew_consent(person: Dictionary, project: Dictionary) -> bool:
	var team: Variant = _fire_pot_original_team(person)
	if not team is TerrainArmy: return false
	var physical: Variant = person.owner if person.owner is CrowdOwner else team
	if physical.combat_order != TerrainArmy.CombatOrder.HOLD or team.get_active_move_plan() != null or team.has_ship_journey() \
		or team._team_ship_activity() or physical.is_sustain_routed() or bool(lab.terrain.site.get("team_supply", {}).get(str(team.team_id), {}).get("training_order", false)) \
		or int(team.duty_resolve_readonly("team.work", physical if physical is CrowdOwner else null).get("decider", -1)) <= 0: return false
	if not (physical.combat_can_act(int(person.unit)) if int(person.unit) >= 0 else person.owner.can_act()): return false
	for receipt: Variant in project.consents:
		if Technology.keys(receipt, ["site_id", "team_id", "person_id", "purpose", "decider_id", "revision", "status"]) \
			and receipt.site_id == _technology_site_id() and int(receipt.team_id) == int(team.team_id) \
			and int(receipt.person_id) == int(person.person_id) and receipt.purpose == project.purpose and receipt.status == "accepted": return true
	return false

func _fire_pot_shot_trial_guard(vehicle: Dictionary, identity: int, token: Dictionary) -> Dictionary:
	var checked := _fire_pot_shot_phase_context(token, false)
	if not checked.ok:
		# Pure initial order admission precedes publishing this one attempt.
		checked = _fire_pot_shot_phase_context(token, true)
	if not checked.ok: return checked
	if int(token.person.person_id) != identity or not is_same(checked.vehicle, vehicle): return Runtime.fail("STALE_SOURCE")
	var proof: Dictionary = vehicle.get("tech_fire_pot_shot", {})
	if not proof.is_empty() and int(proof.token.attempt) == int(token.attempt): return Runtime.fail("WAITING", "同一次真發射不重扣火罐")
	if int(checked.project.budget.spent.get("fire_pot", 0)) + 1 > int(checked.project.budget.cap.get("fire_pot", 0)): return Runtime.fail("BUDGET_EXCEEDED")
	return checked

func water_schedule_active(schedule: Dictionary) -> bool:
	for job: Dictionary in _jobs.values():
		if job.get("kind") == "water_schedule" and is_same(job.get("water_schedule"), schedule) \
			and is_same(job.get("site_state"), lab.terrain.site) and is_same(job.get("terrain"), lab.terrain):
			return _water_schedule_context(job).ok
	return false

func technology_settlement_order_person_ready(person: Dictionary, order: Dictionary) -> Dictionary:
	if person.is_empty() or not order.get("payload") is Dictionary: return Runtime.fail("INVALID_MEMBER")
	var settlement: Dictionary = lab.terrain.site.get("settlement", {})
	var operations: Dictionary = settlement.get("technology_operations", {})
	if not is_same(operations.get("orders", {}).get(str(order.get("id", ""))), order) \
		or (int(order.payload.get("operator_id", -1)) != int(person.person_id) and (order.get("kind") != "ship_cooperation" or int(person.person_id) not in [int(order.payload.helper_id), int(order.payload.carrier_id)])) \
		or not SiteSettlement.valid_technology_operations(lab.terrain, operations): return Runtime.fail("STALE_SOURCE")
	if not _technology_military_person_ready(person, order): return Runtime.fail("BUSY", "原具名工人被其他任務、威脅、移動或身體狀態占用")
	return Runtime.ok("原人物資格可作此具名工單", {"person": person})

func _technology_matching_settlement_task(person: Dictionary, purpose: String) -> bool:
	if person.is_empty() or purpose.is_empty(): return false
	var task := {}
	if person.owner is CrowdOwner:
		var actual: Dictionary = lab.crowd_site.siege_original_person(int(person.person_id))
		if actual.is_empty() or actual.owner != person.owner or int(actual.unit) != int(person.unit): return false
		task = actual.row.get("work_task", {})
	elif person.body is Dictionary: task = person.body.get("work_task", {})
	var job: Dictionary = _jobs.get(_job_key_for(int(person.person_id)), {})
	if job.get("kind") == "technology_feature" and is_same(job.get("site_state"), lab.terrain.site) \
		and is_same(job.get("technology_executor_body"), person.body): task = job.get("work_task", {})
	if not Technology.integer(task.get("version"), 3, 3) or task.get("named") != true \
		or not Technology.keys(task.get("operation_ref"), ["settlement_id", "order_id"]) \
		or not task.get("target") is String or not str(task.target).begins_with("feature:"): return false
	var settlement: Dictionary = SiteSettlement.record(lab.terrain)
	var raw: Variant = settlement.get("technology_operations")
	if settlement.get("settlement_id") != task.operation_ref.settlement_id or not SiteSettlement.valid_technology_operations(lab.terrain, raw): return false
	var order: Dictionary = raw.orders.get(task.operation_ref.order_id, {})
	var key: String = str(task.target).trim_prefix("feature:")
	var feature: Dictionary = lab.terrain.site.features.get(key, {})
	if order.get("kind") == "ship_cooperation":
		return order.status == "active" and order.payload.purpose == purpose \
			and int(person.person_id) in [int(order.payload.operator_id), int(order.payload.helper_id)] \
			and task.action == "operate" and feature.get("technology_settlement_order") == task.operation_ref \
			and Runtime.valid_settlement_ship_target(lab.terrain, key, feature) and SiteWorkTeam.valid_task(lab.terrain, lab.terrain.site, task)
	if order.get("kind") in ["charcoal_batch", "textile_batch", "metal_chain"]:
		return order.get("status") == "active" and order.get("payload", {}).get("purpose") == purpose \
			and int(order.payload.get("operator_id", -1)) == int(person.person_id) and task.action == "operate" \
			and feature.get("technology_settlement_order") == task.operation_ref \
			and Runtime.valid_settlement_processing_target(lab.terrain, key, feature) and SiteWorkTeam.valid_task(lab.terrain, lab.terrain.site, task)
	if order.get("kind") != "defense" or order.get("status") != "active" or order.get("purpose") != purpose \
		or order.get("paid", {}).get("feature_id") != key or int(order.get("next_step", -1)) >= order.get("steps", []).size() \
		or not Runtime.valid_settlement_work_storage(lab.terrain, key, feature) or not SiteWorkTeam.valid_task(lab.terrain, lab.terrain.site, task): return false
	var step: Dictionary = order.steps[int(order.next_step)]
	return int(step.operator_id) == int(person.person_id) and task.action == step.action \
		and feature.settlement_work.order_id == task.operation_ref.order_id and feature.settlement_work.settlement_id == task.operation_ref.settlement_id

func _technology_matching_military_task(person: Dictionary, order: Dictionary) -> bool:
	var selector := _technology_military_selector_for_order(order)
	if person.is_empty() or selector.is_empty() or order.get("status") != "active" or int(order.get("operator_id", -1)) != int(person.person_id): return false
	var task := _technology_military_task(person)
	var feature: Dictionary = lab.terrain.site.get("features", {}).get(str(order.feature_id), {})
	return Technology.integer(task.get("version"), 3, 3) and task.get("named") == true \
		and Technology.keys(task.get("operation_ref"), ["nation_id", "order_id"]) and task.operation_ref == selector \
		and task.get("target") == "feature:" + str(order.feature_id) and task.get("action") == "operate" \
		and not feature.is_empty() and feature.get("technology_order") == selector \
		and SiteWorkTeam.valid_task(lab.terrain, lab.terrain.site, task)

func _technology_military_task(person: Dictionary) -> Dictionary:
	if person.is_empty(): return {}
	var task: Dictionary = {}
	if person.owner is CrowdOwner:
		var actual: Dictionary = lab.crowd_site.siege_original_person(int(person.person_id))
		if actual.is_empty() or actual.owner != person.owner or int(actual.unit) != int(person.unit): return {}
		task = actual.row.get("work_task", {})
		var actor: Variant = person.owner.actors.get(int(person.unit))
		if actor != null: task = lab.terrain.site.manual if is_same(actor, lab.character) else (lab.terrain.site.worker if is_same(actor, lab.npc) else {})
	elif person.body is Dictionary: task = person.body.get("work_task", {})
	else: task = lab.terrain.site.manual if person.owner == lab.character else lab.terrain.site.worker
	var job: Dictionary = _jobs.get(_job_key_for(int(person.person_id)), {})
	if job.get("kind") == "technology_feature" and is_same(job.get("technology_executor_body"), person.body) \
		and is_same(job.get("site_state"), lab.terrain.site): task = job.work_task
	return task

func _technology_military_team(person: Dictionary) -> Variant:
	if person.is_empty(): return null
	if person.owner is CrowdOwner:
		var original: Variant = person.owner._command_owner(int(person.unit))
		return person.owner if original is TerrainArmy or _technology_team(person) != null else null
	return _technology_team(person)

func gd_contact_job_runtime_candidate(candidate: Dictionary) -> bool:
	for actual: Dictionary in _gd_contact_job_capture.get("runtime_priors", []):
		if is_same(actual, candidate): return true
	for actual: Dictionary in _gd_contact_job_segment.get("runtime", []):
		if is_same(actual, candidate): return true
	return false

func validate_checked_controlled_runtime_prefixes(registered: Dictionary) -> Dictionary:
	if registered.get("owner") != self or not is_same(registered.get("registered"), _checked_controlled_prefixes): return Runtime.fail("STALE_SOURCE")
	var runtime_priors: Array = _checked_controlled_prefixes.runtime_priors
	for prefix: Dictionary in _checked_controlled_prefixes.prefixes:
		var candidate: Dictionary = Runtime.prepare_checked_work_prefix(lab.terrain, prefix.task, float(prefix.applied_productive_seconds), float(prefix.actual_seconds), prefix)
		if not candidate.ok: return candidate
		_checked_controlled_prefixes.runtime.append(candidate)
		runtime_priors.append(candidate) # Same original Lab finite batch/source ledger.
	return Runtime.ok("原受控任务已纯预验同held合法前缀", {"owner": self, "checked": _checked_controlled_prefixes})

func settlement_food_prefix_progress(job: Dictionary) -> void:
	# Called immediately after the ORIGINAL shared timer writes job.elapsed.
	# This is saved evidence of that timer, not a second elapsed owner.
	if job.get("kind") == "food_order": job.food_order.payload.work_seconds = float(job.elapsed)

func discard_checked_controlled_prefixes() -> void:
	_shared_vehicle_request_facts.clear()
	_checked_controlled_prefixes = {}
	_publishing_checked_controlled = false

func begin_shared_work_prefix_consumption(admitted: Dictionary) -> void:
	# Sole original Lab calls after ALL pure gates and Native final prepare, then
	# consumes original providers in a synchronous no-failure tail. No callbacks.
	assert(admitted.ok and admitted.owner == self and _shared_work_prefix_consumption.is_empty())
	assert(is_same(admitted.plan, lab._shared_work_plan) and is_same(admitted.plan, lab.site_controller._shared_work_plan))
	if lab.crowd_site != null and lab.crowd_site.active:
		assert(lab.crowd_site.work_fatigue_point_active())
		var state: PackedFloat64Array = lab.crowd_site.crowd.work_point_state()
		assert(state.size() == 5 and state[1] == 1.0 and is_equal_approx(state[4], float(admitted.seconds)))
	_shared_work_prefix_consumption = admitted

func end_shared_work_prefix_consumption() -> void:
	_shared_work_prefix_consumption = {}

func finish_shared_job_prefix_timers(admitted: Dictionary) -> void:
	# After World publication only. Original endpoint settle follows separately.
	if admitted.get("owner") != self or not bool(admitted.get("timers_published", false)) or bool(admitted.get("timers_finished", false)): return
	admitted.timers_finished = true
	for key: String in admitted.prepared.held:
		var held: Dictionary = admitted.prepared.held[key]
		if held.kind in ["technology_feature", "technology_vehicle", "fire_suppress"]: continue
		var allocation: Dictionary = admitted.plan.get("jobs", {}).get("person_actions", {}).get(key, {})
		for identity: int in held.people:
			var person: Dictionary = _person(identity)
			if person.is_empty() or bool(person.player): continue
			var actual: float = float(allocation.get("participant_seconds", {}).get(identity, 0.0))
			if actual > 0.0: _body_set(person, "work_resting", false)
			var paused: String = str(allocation.get("participant_paused", {}).get(identity, allocation.get("paused", "")))
			if paused == "REST":
				_body_set(person, "work_resting", true)
				if person.owner is CrowdOwner: person.owner.work_fatigue_rest(identity)

func publish_checked_controlled_prefixes(prepared: Dictionary) -> void:
	assert(prepared.get("owner") == self and is_same(prepared.get("checked"), _checked_controlled_prefixes))
	if bool(prepared.get("published", false)): return
	assert(not _shared_work_prefix_consumption.is_empty() and is_same(_shared_work_prefix_consumption.plan, _checked_controlled_prefixes.plan))
	_publishing_checked_controlled = true
	for candidate: Dictionary in _checked_controlled_prefixes.runtime: Runtime.publish_checked_work_prefix(candidate)
	for key: String in _checked_controlled_prefixes.admitted.prepared.held:
		var held: Dictionary = _checked_controlled_prefixes.admitted.prepared.held[key]
		if held.kind not in ["technology_feature", "technology_vehicle"]: continue
		_controlled_feature_consumed[key] = true # Also zero/REST jobs: never legacy fallback in point tail.
		held.job.paused = str(_checked_controlled_prefixes.plan.jobs.get("person_actions", {}).get(key, {}).get("paused", ""))
	_publishing_checked_controlled = false
	prepared.published = true

func publish_shared_job_prefix_timers(admitted: Dictionary) -> Dictionary:
	assert(admitted.get("owner") == self and admitted.ok and is_same(admitted, _shared_work_prefix_consumption))
	if bool(admitted.get("timers_published", false)): return {"handled_seconds": {}}
	var handled := {}
	for key: String in admitted.prepared.held:
		var held: Dictionary = admitted.prepared.held[key]
		if held.kind in ["technology_feature", "technology_vehicle", "fire_suppress"]: continue
		var allocation: Dictionary = admitted.plan.get("jobs", {}).get("person_actions", {}).get(key, {})
		if allocation.is_empty(): continue # No allocation never reaches legacy charge/callback.
		var job: Dictionary = held.job
		job.paused = str(allocation.get("paused", ""))
		job.elapsed = 0.0 if job.paused == "THREAT" else minf(float(held.duration), float(held.elapsed) + float(allocation.get("effective_seconds", 0.0)))
		settlement_food_prefix_progress(job)
		if job.paused == "REST" and float(job.elapsed) >= float(job.duration) - 0.00000001: job.paused = ""
		for identity: int in held.people:
			var actual: float = float(allocation.get("participant_seconds", {}).get(identity, 0.0))
			if actual > 0.0: handled[identity] = actual
		if admitted.admitted.has(key): admitted.admitted[key].advance_consumed = true
	admitted.timers_published = true
	return {"handled_seconds": handled}

func _settlement_food_event(job: Dictionary) -> Dictionary:
	return {"id": str(job.food_event_id), "site_id": _technology_site_id(), "target_id": Runtime.settlement_food_target(_technology_site_id(), str(job.food_order.payload.settlement_id), str(job.food_order.id)),
		"operator_id": int(job.executor_id), "binding": "food_order", "work_seconds": float(job.elapsed), "item_ids": [], "outputs": {}, "materials": job.food_order.payload.paid.materials.duplicate(true)}

func _settlement_food_job_context(job: Dictionary) -> Dictionary:
	if not is_same(_jobs.get(str(int(job.executor_id))), job) or not is_same(job.terrain, lab.terrain) \
		or not is_same(job.site_state, lab.terrain.site): return Runtime.fail("STALE_SOURCE")
	var checked := Runtime.settlement_food_work_preflight(lab.terrain, str(job.food_order.payload.settlement_id), str(job.food_order.id), "food_order")
	if not checked.ok: return checked
	if not is_same(checked.settlement, job.food_settlement) or not is_same(checked.operations, job.food_operations) \
		or not is_same(checked.order, job.food_order) or checked.order.payload.stage != "arrived" \
		or not is_same(checked.feature, job.food_warehouse) or not is_same(checked.stock.holder, job.food_holder) \
		or not is_same(checked.stock.cargo, job.food_cargo) or not is_same(checked.person.body, job.executor_body) \
		or int(checked.person.hit) != int(job.executor_hit) or lab.terrain.index(checked.person.cell) != int(job.executor_cell) \
		or not lab.site_controller._delivery_person_ready(checked.person, job): return Runtime.fail("INTERRUPTED")
	if not bool(checked.person.player) and _threat(checked.person, {}): return Runtime.fail("THREAT")
	if not job.nation_token.is_empty():
		if not is_same(job.nation_token, checked.order.payload.token): return Runtime.fail("STALE_PROJECT")
		var phase := _technology_paid_phase_context(job.nation_token)
		if not phase.ok: return phase
	return checked

func _water_schedule_event(job: Dictionary) -> Dictionary:
	return {"id": str(job.water_event_id), "site_id": _technology_site_id(), "target_id": str(job.nation_token.target_id),
		"operator_id": int(job.executor_id), "binding": "water_priority", "work_seconds": float(job.duration),
		"item_ids": [], "outputs": {}, "materials": {}}

func water_schedule_receipt_query(token: Dictionary, event: Dictionary) -> Dictionary:
	var job: Dictionary = _jobs.get(str(int(token.get("person", {}).get("person_id", -1))), {})
	if job.get("kind") != "water_schedule" or job.get("nation_token") != token \
		or float(job.elapsed) + 0.00000001 < float(job.duration) or _water_schedule_event(job) != event: return Runtime.fail("INVALID_RECEIPT")
	var context := _water_schedule_context(job)
	if not context.ok: return context
	var first: Dictionary = job.water_first_sample
	var second: Dictionary = Runtime.water_allocation_sample(lab.terrain, job.water_schedule.categories)
	if not Runtime.valid_water_allocation_sample(first) or not Runtime.valid_water_allocation_sample(second) \
		or float(second.source_capacity) <= 0.0 or first.categories != second.categories: return Runtime.fail("WATER")
	return Runtime.ok("兩次原水源預算內的真需求/供給/優先序", {"first": first, "second": second})

func grant_settlement_metal_source(requester_id: int, settlement_id: String, order_id: String, revoke: bool = false) -> Dictionary:
	var settlement := _technology_scope_owner("settlement", settlement_id)
	var admitted := _technology_scope_command(requester_id, "settlement", settlement)
	if not admitted.ok: return admitted
	var runtime_script: Variant = Runtime
	if not runtime_script.has_method("grant_settlement_operation_source"): return Runtime.fail("UNIMPLEMENTED")
	var view := settlement_metal_order_view(settlement_id, order_id)
	if not view.ok: return view
	var refs: Dictionary = runtime_script.call("_settlement_order_state", lab.terrain, settlement_id, order_id)
	if refs.is_empty() or refs.order.get("kind") != "metal_chain": return Runtime.fail("NO_TARGET")
	var holder_key := str(refs.order.payload.smithy_id) if refs.order.payload.carry_receipts.size() == 2 else str(refs.order.payload.smelter_id)
	return runtime_script.call("grant_settlement_operation_source", lab.terrain, settlement_id, order_id, requester_id, holder_key, revoke)

func stop_settlement_metal_order(requester_id: int, settlement_id: String, order_id: String, permanent: bool = false) -> Dictionary:
	var settlement := _technology_scope_owner("settlement", settlement_id)
	var admitted := _technology_scope_command(requester_id, "settlement", settlement)
	if not admitted.ok: return admitted
	var runtime_script: Variant = Runtime
	if not runtime_script.has_method("stop_settlement_processing_order"): return Runtime.fail("UNIMPLEMENTED")
	var view := settlement_metal_order_view(settlement_id, order_id)
	if not view.ok: return view
	return runtime_script.call("stop_settlement_processing_order", lab.terrain, settlement_id, order_id, requester_id, permanent)

func cancel_settlement_food_order(requester_id: int, settlement_id: String, order_id: String) -> Dictionary:
	var refs := Runtime._settlement_food_refs(lab.terrain, settlement_id, order_id)
	if refs.is_empty() or requester_id != _technology_controlled() or requester_id != Settlement.head_executor(lab): return Runtime.fail("NO_AUTHORITY")
	if refs.order.status in ["completed", "cancelled"]: return Runtime.fail("COMPLETE")
	var key := str(int(refs.order.payload.operator_id))
	var job: Dictionary = _jobs.get(key, {})
	if job.get("kind") == "food_order" and is_same(job.get("food_order"), refs.order):
		refs.order.payload.work_seconds = float(job.elapsed)
		_jobs.erase(key)
	refs.order.status = "cancelled"
	refs.order.payload.source.status = "revoked"
	refs.order.revision = int(refs.order.revision) + 1
	return Runtime.ok("原糧食單已撤回；真已交物及有限spent保留")

func accepted_controlled_feature_interval(task: Dictionary, named_id: int) -> Dictionary:
	if _controlled_feature_allocation.is_empty() or named_id <= 0: return {}
	var held: Dictionary = _controlled_feature_allocation.held
	if not is_same(held.task, task) or int(held.job.executor_id) != named_id \
		or not is_same(_jobs.get(_controlled_feature_allocation.key), held.job) or not _controlled_feature_job_context(held.job).ok: return {}
	var interval: Dictionary = _controlled_feature_allocation.interval
	var actual := float(interval.get("participant_seconds", {}).get(named_id, 0.0))
	var productive := float(interval.get("participant_effective_seconds", {}).get(named_id, 0.0))
	if not is_finite(actual) or not is_finite(productive) or actual <= 0.0 or productive <= 0.0 \
		or actual + Fatigue.WORK_PLAN_EPS < float(interval.get("actual_seconds", 0.0)): return {}
	var original_target: Dictionary = held.job.get("vehicle_ref", held.job.get("feature_ref", {}))
	var token: Dictionary = original_target.get("tech_trial", {})
	if not token.is_empty() and (int(token.person.person_id) != named_id or token.person.site_id != _technology_site_id() \
		or token.target_id != task.target or not is_same(held.job.operation_selector.get("token"), token)): return {}
	return {"person_id": named_id, "actual_seconds": actual, "productive": productive, "productive_seconds": productive,
		"target": str(task.target), "phase_id": str(token.get("phase_id", "")), "attempt": int(token.get("attempt", -1))}


# Append to ORIGINAL SitePersonActions; root owns the function-local merge.
# This is a call-local view of its original held _jobs, never a permission flag,
# second person/work owner, clock, saved schema or fake alive person.

func _nation_military_material_source(nation_id: String, order_id: String, require_known: bool = false) -> Dictionary:
	if equipment_orders == null or not equipment_orders.has_method("military_work_preflight"): return Runtime.fail("UNIMPLEMENTED")
	var checked: Dictionary = equipment_orders.call("military_work_preflight", nation_id, order_id)
	if not checked.ok: return checked
	if require_known and not Technology.scope_known(checked.nation.get("technology", {}), "N05"): return Runtime.fail("STALE_PROJECT")
	var order: Dictionary = checked.order
	var stock := SiteStockpiles.stock_endpoint(lab.terrain, str(order.feature_id))
	if stock.is_empty() or str(checked.feature.get("supply_mode", "")) != "local": return Runtime.fail("NO_SOURCE")
	# source.spent proves the earlier REAL donor->localstock transfer. It is never
	# copied into the new Scope payment or deducted from the donor a second time.
	return Runtime.ok("", {"kind": "nation_order", "holder": "nation-order:" + JSON.stringify([_technology_site_id(), nation_id, order_id]),
		"source_site_id": _technology_site_id(), "grantor": {"site_id": _technology_site_id(), "person_id": int(order.source.person_id)},
		"cap": order.source.cap.duplicate(), "spent": {}, "physical_holder": stock.holder, "physical_cargo": stock.cargo,
		"holder_version": int(stock.holder.version), "expected_refs": {"terrain": lab.terrain, "site": lab.terrain.site, "nation": checked.nation,
			"operations": checked.operations, "order": order, "holder": stock.holder, "cargo": stock.cargo}})

# APPEND after frozen 4CF4 checked-prefix package. NO change to that package.
# A common point never calls whole legacy advance() in its no-failure tail.

func _technology_settlement_source_query(token: Dictionary, source: Dictionary) -> Dictionary:
	if not Technology.keys(source, ["ok", "code", "message", "kind", "holder", "source_site_id", "grantor", "cap", "spent", "physical_holder", "physical_cargo", "holder_version", "expected_refs"]) \
		or source.ok != true or not source.ok is bool or not source.code is String or not source.message is String \
		or source.kind != "settlement_order" or token.get("scope") != "settlement" \
		or not source.holder is String or not source.holder.begins_with("settlement-order:") or source.source_site_id != _technology_site_id() \
		or not Technology.valid_ref(source.grantor) or source.grantor.site_id != _technology_site_id() \
		or not Technology.material_stack(source.cap) or not Technology.material_stack(source.spent) \
		or not source.physical_holder is Dictionary or not source.physical_cargo is Dictionary or not Technology.integer(source.holder_version) \
		or not Technology.keys(source.expected_refs, ["terrain", "site", "nation", "operations", "order", "holder", "cargo"]): return Runtime.fail("STALE_SOURCE")
	var source_parts: Variant = JSON.parse_string(source.holder.trim_prefix("settlement-order:"))
	if not source_parts is Array or source_parts.size() != 3 or source_parts[0] != _technology_site_id() \
		or source_parts[1] != token.get("scope_id") or not source_parts[2] is String \
		or source.holder != "settlement-order:" + JSON.stringify(source_parts): return Runtime.fail("STALE_SOURCE")
	var actual: Dictionary = settlement_research_source_candidate(token, str(source_parts[2]))
	if not actual.ok: return actual
	for key: String in ["kind", "holder", "source_site_id", "grantor", "cap", "spent", "holder_version"]:
		if source[key] != actual.get(key): return Runtime.fail("STALE_SOURCE")
	for key: String in ["physical_holder", "physical_cargo"]:
		if not is_same(source[key], actual.get(key)): return Runtime.fail("STALE_SOURCE")
	for key: String in ["terrain", "site", "nation", "operations", "order", "holder", "cargo"]:
		if not is_same(source.expected_refs[key], actual.expected_refs.get(key)): return Runtime.fail("STALE_SOURCE")
	var settlement: Dictionary = _technology_scope_owner("settlement", str(token.get("scope_id", "")))
	if not is_same(actual.expected_refs.terrain, lab.terrain) or not is_same(actual.expected_refs.site, lab.terrain.site) \
		or not is_same(actual.expected_refs.nation, settlement) or not is_same(actual.expected_refs.operations, settlement.get("technology_operations")) \
		or not is_same(actual.expected_refs.order, actual.expected_refs.operations.get("orders", {}).get(str(source_parts[2]))) \
		or not is_same(actual.expected_refs.holder, actual.physical_holder) or not is_same(actual.expected_refs.cargo, actual.physical_cargo): return Runtime.fail("STALE_SOURCE")
	return actual

func settlement_research_source_candidate(token: Dictionary, order_id: String) -> Dictionary:
	if token.get("scope") != "settlement" or token.get("tech_id") not in ["S03", "S04", "S05", "S06", "S12"]: return Runtime.fail("NO_BUDGET")
	var ready: Dictionary = _settlement_operation_context(str(token.get("scope_id", "")), order_id, str(token.get("binding", "")))
	if not ready.ok: return ready
	var payload: Dictionary = ready.order.get("payload", {})
	if int(payload.get("project_id", -1)) != int(token.get("project_id", -2)) or payload.get("purpose") != token.get("purpose") \
		or int(payload.get("operator_id", -1)) != int(token.get("person", {}).get("person_id", -2)): return Runtime.fail("STALE_PROJECT")
	return settlement_operation_material_source_candidate(str(token.scope_id), order_id, str(token.binding))

func _settlement_operation_context(settlement_id: String, order_id: String, binding: String = "") -> Dictionary:
	var runtime_script: Variant = Runtime
	if not runtime_script.has_method("settlement_processing_preflight"): return Runtime.fail("UNIMPLEMENTED")
	return runtime_script.call("settlement_processing_preflight", lab.terrain, settlement_id, order_id, binding)

func _controlled_feature_source(selector: Dictionary, feature: Dictionary, key: String, action: String, admission: Dictionary, repair: Dictionary = {}) -> Dictionary:
	if Technology.keys(selector, ["irrigation"]):
		if action != "construct" or feature.get("kind") != "irrigation_channel": return Runtime.fail("INVALID")
		var config: Dictionary = selector.irrigation.duplicate()
		config.erase("operator_id")
		if config != feature.get("irrigation"): return Runtime.fail("STALE_SOURCE")
		if is_same(lab.terrain.site.features.get(key), feature):
			if not Runtime.validate_irrigation_storage(lab.terrain, lab.terrain.site).ok: return Runtime.fail("STALE_SOURCE")
			return Runtime.ok("原渠道已完整付料，接續不重扣", {"already_paid": true, "feature": feature})
		return Runtime.ok("原本次營地完整建造來源", {"already_paid": false, "holder": lab.terrain.site.depot_items, "cargo": lab.terrain.site.inventory})
	if Technology.keys(selector, ["settlement_id", "order_id"]):
		var order: Dictionary = lab.terrain.site.get("settlement", {}).get("technology_operations", {}).get("orders", {}).get(str(selector.order_id), {})
		if order.get("kind") == "defense": return Runtime.settlement_defense_material_source(lab.terrain, selector, feature, key, action, repair)
		if action != "operate" or not is_same(lab.terrain.site.features.get(key), feature): return Runtime.fail("STALE_SOURCE")
		if not feature.get("tech_batch", {}).is_empty():
			if feature.get("technology_settlement_order") != selector or not Runtime.valid_settlement_processing_target(lab.terrain, key, feature) \
				or not Runtime.valid_technology_batch(feature.tech_batch, lab.terrain, key) or not feature.tech_batch.token.is_empty() \
				or not Runtime.validate_technology_ledger_source(lab.terrain, feature, feature.tech_batch): return Runtime.fail("STALE_SOURCE")
			return Runtime.ok("原聚落已付款工序接續", {"already_paid": true, "ledger": feature.tech_batch})
		var queried := settlement_operation_material_source_candidate(str(selector.settlement_id), str(selector.order_id))
		if not queried.ok: return queried
		return Runtime.ok("原有限聚落新來源", {"already_paid": false, "holder": queried.physical_holder, "cargo": queried.physical_cargo, "original_source": queried})
	# A prospective future ledger is not a payment. Only the SAME live target can
	# use an already-paid witness; new requests still query their real source.
	if is_same(lab.terrain.site.features.get(key), feature) and selector.has("token"):
		var paid := Runtime.technology_existing_paid_phase_source(lab.terrain, feature.get("tech_trial", {}))
		if paid.ok and is_same(feature.get("tech_trial"), selector.token):
			var active := technology_phase_active_guard(selector.token)
			if not active.ok: return active
			return Runtime.ok("原已付款工序接續", {"already_paid": true, "witness": paid})
	if is_same(lab.terrain.site.features.get(key), feature) and not selector.has("token") and not feature.get("tech_batch", {}).is_empty():
		var ledger: Dictionary = feature.tech_batch
		if not Runtime.valid_technology_batch(ledger, lab.terrain, key, "feature") or not ledger.token.is_empty() \
			or feature.get("technology_order") != selector or not Runtime.validate_technology_order_storage(lab.terrain, key, feature, "feature").ok: return Runtime.fail("STALE_SOURCE")
		var cost: Dictionary = feature.get("pending_build", feature).get("cost", {}) if action == "construct" else Runtime.feature_recipe(feature).get("input", {})
		if not Technology.material_equal(ledger.materials, cost) or action == "operate" and not bool(feature.get("batch_paid", false)) \
			or not Technology.finite_number(feature.get("production", 0.0) if action == "operate" else feature.get("pending_build", feature).get("progress", 0.0)): return Runtime.fail("STALE_SOURCE")
		return Runtime.ok("原公共單已付款工序接續", {"already_paid": true, "ledger": ledger})
	var queried: Dictionary = technology_phase_material_source_candidate(selector.token) if selector.has("token") \
		else nation_operation_material_source_candidate(str(selector.nation_id), str(selector.order_id), "workshop_bow" if str(selector.order_id).begins_with("production_") else "iron_armor" if admission.order.tech_id == "N11" else "house_build" if admission.order.tech_id == "N06" else "road_build")
	if not queried.ok: return queried
	var source: Dictionary = queried.source
	return Runtime.ok("原新來源已查證", {"already_paid": false, "holder": source.get("physical_holder"), "cargo": source.get("physical_cargo"), "original_source": source})

func _fire_pot_original_team(person: Dictionary) -> Variant:
	if person.owner is CrowdOwner:
		var original: Variant = person.owner._command_owner(int(person.unit))
		if original is TerrainArmy and person.owner.crowd_site.owns_original_team(original): return original
	return _technology_team(person)

func _water_schedule_context(job: Dictionary) -> Dictionary:
	if not is_same(_jobs.get(str(int(job.executor_id))), job) or not is_same(job.terrain, lab.terrain) \
		or not is_same(job.site_state, lab.terrain.site): return Runtime.fail("STALE_SOURCE")
	var settlement: Dictionary = Settlement.record(lab.terrain)
	var center: Dictionary = Settlement.center(lab.terrain)
	if not is_same(settlement, job.water_settlement) or not is_same(center, job.water_center) \
		or not is_same(center.get("technology_water_schedule"), job.water_schedule) \
		or not Runtime.valid_water_schedule(job.water_schedule, lab.terrain.site) \
		or Settlement.status(lab).get("effective") != true: return Runtime.fail("NO_AUTHORITY")
	var context := _technology_phase_context(job.nation_token, false, false)
	if not context.ok: return context
	var person: Dictionary = context.person
	if not is_same(person.body, job.executor_body) or int(person.hit) != int(job.executor_hit) \
		or lab.terrain.index(person.cell) != int(job.executor_cell): return Runtime.fail("INTERRUPTED")
	return context

func _technology_military_selector_for_order(order: Dictionary) -> Dictionary:
	if equipment_orders == null or not is_same(equipment_orders.lab, lab) or order.is_empty(): return {}
	for nation_id: String in lab.terrain.site.get("equipment_nations", {}):
		var nation: Dictionary = lab.terrain.site.equipment_nations[nation_id]
		var operations: Dictionary = nation.get("technology_operations", {})
		if not equipment_orders.valid_nation_operation_record(operations, lab.terrain.site.item_definitions, {}): continue
		for order_id: String in operations.get("orders", {}):
			if is_same(operations.orders[order_id], order): return {"nation_id": nation_id, "order_id": order_id}
	return {}

func settlement_operation_material_source_candidate(settlement_id: String, order_id: String, binding: String = "") -> Dictionary:
	var ready: Dictionary = _settlement_operation_context(settlement_id, order_id, binding)
	if not ready.ok: return ready
	var runtime_script: Variant = Runtime
	if not runtime_script.has_method("settlement_operation_material_source_candidate"): return Runtime.fail("UNIMPLEMENTED")
	return runtime_script.call("settlement_operation_material_source_candidate", lab.terrain, settlement_id, order_id, binding)

var _shared_vehicle_request_facts: Dictionary = {}

## Commands reference original people and sparse holders; no surrogate bodies.
## advance() is before contact/life settlement; only settle_after_contacts commits.

var _gd_contact_job_capture: Dictionary = {}

var _gd_contact_job_segment: Dictionary = {}

var _prepared_controlled_features: Dictionary = {}

var _controlled_feature_seconds: float = 0.0

var _controlled_feature_consumed: Dictionary = {}

var _controlled_feature_allocation: Dictionary = {}

var _shared_work_prefix_consumption: Dictionary = {}

var _checked_controlled_prefixes: Dictionary = {}

var _publishing_checked_controlled := false

func _technology_matching_public_task(person: Dictionary, order: Dictionary) -> bool:
	if not _technology_military_selector_for_order(order).is_empty(): return _technology_matching_military_task(person, order)
	if person.is_empty() or order.is_empty() or equipment_orders == null or not is_same(equipment_orders.lab, lab): return false
	var nation_id := str(order.get("scope_nation_id", ""))
	var nation: Dictionary = lab.terrain.site.get("equipment_nations", {}).get(nation_id, {})
	var operations: Dictionary = nation.get("technology_operations", {})
	if not equipment_orders.valid_nation_operation_record(operations, lab.terrain.site.item_definitions, {}) \
		or order.get("scope_site_id") != _technology_site_id() or order.get("status") not in ["prepared", "active"]: return false
	var task: Dictionary = {}
	if person.owner is CrowdOwner:
		var actual: Dictionary = lab.crowd_site.siege_original_person(int(person.person_id))
		if actual.is_empty() or actual.owner != person.owner or int(actual.unit) != int(person.unit): return false
		task = actual.row.get("work_task", {})
	elif person.body is Dictionary:
		task = person.body.get("work_task", {})
	var job: Dictionary = _jobs.get(_job_key_for(int(person.person_id)), {})
	if job.get("kind") in ["technology_feature", "technology_vehicle"] and is_same(job.get("technology_executor_body"), person.body) \
		and is_same(job.get("site_state"), lab.terrain.site): task = job.work_task
	if not Technology.integer(task.get("version"), 3, 3) or not task.get("named") is bool or task.named != true \
		or not Technology.keys(task.get("operation_ref"), ["nation_id", "order_id"]) \
		or task.operation_ref.nation_id != nation_id or not task.operation_ref.order_id is String \
		or not is_same(operations.public_orders.get(task.operation_ref.order_id), order) \
		or not SiteWorkTeam.valid_task(lab.terrain, lab.terrain.site, task): return false
	var target := "feature:" + str(order.payload.get("feature_id", ""))
	var identities: Array = order.payload.get("person_ids", order.payload.get("worker_ids", []))
	if order.tech_id == "N10": identities = [int(order.payload.local_person_id)]
	elif order.tech_id == "N11":
		identities = [int(order.payload.operator_id)]
		target = str(order.payload.target_id)
	return order.tech_id in ["N02", "N06", "N10", "N11"] and identities.has(int(person.person_id)) \
		and task.get("target") == target and str(task.get("action")) == ("operate" if order.tech_id == "N11" and order.payload.route == "armor" else "construct")

# APPEND; Native fitness uses the current original physical owner. The disabled
# original Army supplies only its actual organization/offices and stable IDs.

func _technology_native_consent_readonly(person: Dictionary, consents: Array, purpose: String, token: Dictionary, order: Dictionary) -> bool:
	var physical: CrowdOwner = person.owner
	var original: Variant = physical._command_owner(int(person.unit))
	if original is TerrainTestCharacter: original = _technology_team(person)
	if not original is TerrainArmy: return _technology_team(person) == null
	if original.data != lab.terrain or int(physical.team_id) != int(original.team_id) or not physical.crowd_site.owns_original_team(original) or physical.member_gone(int(person.unit)) \
		or not physical.combat_can_act(int(person.unit)) or physical.combat_order != TerrainArmy.CombatOrder.HOLD or physical.is_sustain_routed() \
		or original.get_active_move_plan() != null or original.has_ship_journey() or original._team_ship_activity() \
		or float(lab.terrain.site.get("combat_left", 0.0)) > 0.0: return false
	for index: int in physical.combat_units:
		if bool(physical.person(index, false).get("moving", true)): return false
	var supply: Dictionary = lab.terrain.site.get("team_supply", {}).get(str(physical.team_id), {})
	if bool(supply.get("training_order", false)): return false
	var actual: Dictionary = lab.crowd_site.siege_original_person(int(person.person_id))
	if actual.is_empty() or actual.owner != physical or int(actual.unit) != int(person.unit) or bool(actual.row.get("logistics", false)): return false
	var current_task: Dictionary = actual.row.get("work_task", {})
	var source_actor: Variant = physical.actors.get(int(person.unit))
	if source_actor != null:
		if original.index_for_identity(int(person.person_id)) != TerrainArmy.PLAYER_MEMBER or not is_same(source_actor, original.player_member): return false
		current_task = lab.terrain.site.manual if is_same(source_actor, lab.character) else (lab.terrain.site.worker if is_same(source_actor, lab.npc) else {})
		if str(current_task.get("target", "")).is_empty(): current_task = {}
	if not current_task.is_empty():
		var view := person.duplicate() # original row reference, never a second body
		view.body = actual.row if source_actor == null else source_actor
		if source_actor != null: view.owner = source_actor # task selector only; all fitness below remains Native
		if not _technology_matching_original_task(view, token) and not _technology_matching_public_task(person, order) and not _technology_matching_settlement_task(person, purpose): return false
	if physical.moving_to[int(person.unit)] != TerrainArmy.INVALID_CELL or float(physical.combat_hot_get(int(person.unit), &"exchange_stagger", 0.0)) > 0.0 \
		or bool(physical.combat_hot_get(int(person.unit), &"attack")) or str(physical.combat_hot_get(int(person.unit), &"pose")) != "idle": return false
	if lab.site_controller != null and (lab.site_controller.vehicles.is_siege_crew(int(person.person_id)) \
		or lab.site_controller.vehicles.is_operator(int(person.person_id)) or lab.site_controller.ship_person_in_journey(int(person.person_id))): return false
	if int(original.duty_resolve_readonly("team.work", physical).get("decider", -1)) <= 0: return false
	for receipt: Variant in consents:
		if Technology.keys(receipt, ["site_id", "team_id", "person_id", "purpose", "decider_id", "revision", "status"]) \
			and receipt.site_id == _technology_site_id() and Technology.integer(receipt.team_id, int(physical.team_id), int(physical.team_id)) \
			and Technology.integer(receipt.person_id, int(person.person_id), int(person.person_id)) and receipt.purpose == purpose and receipt.status == "accepted": return true
	return false

func _technology_scope_consent_candidate(person: Dictionary, purpose: String, requester_id: int) -> Dictionary:
	if person.is_empty(): return Runtime.fail("NO_MEMBER")
	if person.get("owner") is CrowdOwner and person.owner.crowd_site == null: return Runtime.fail("INVALID_OWNER")
	var team: Variant = _technology_team(person)
	var physical: Variant = person.get("owner") if person.get("owner") is CrowdOwner else null
	if physical != null:
		var source: Variant = physical._command_owner(int(person.unit))
		if source is TerrainArmy:
			team = source
		elif source is TerrainTestCharacter:
			if not physical.actors.has(int(person.unit)) or not is_same(physical.actors[int(person.unit)], source) or int(source.person_id) != int(person.person_id): return Runtime.fail("NO_MEMBER")
			if team != null and (team.index_for_identity(int(person.person_id)) != TerrainArmy.PLAYER_MEMBER or not is_same(team.player_member, source)): return Runtime.fail("NO_MEMBER")
		else: return Runtime.fail("NO_MEMBER", "原Native人物缺原隊／Actor來源，不視為自由人")
		if team != null and (not team is TerrainArmy or not is_same(team.data, lab.terrain) or int(team.team_id) != int(physical.team_id) \
			or not physical.crowd_site.owns_original_team(team)): return Runtime.fail("INVALID_OWNER")
	if team == null: return Runtime.ok("原真人不受原隊派工管轄", {"consent": {}})
	if not team.has_method("technology_work_consent"): return Runtime.fail("UNSUPPORTED")
	var response: Dictionary = team.technology_work_consent(int(person.person_id), purpose, requester_id, physical)
	if not response.ok: return response
	var current: Dictionary = team.duty_resolve_readonly("team.work", physical)
	if not bool(current.get("ok", false)) or response.consent.get("decider_id") != current.get("decider") or response.consent.get("revision") != current.get("revision") \
		or not _technology_consent_valid(int(person.person_id), [response.consent], purpose, {}, true): return Runtime.fail("STALE_AUTHORITY")
	return response

func _commit_nation_original_administration(job: Dictionary) -> Dictionary:
	var checked := _nation_original_administration_context(job)
	if not checked.ok: return checked
	if float(job.elapsed) + 0.00000001 < 300.0: return Runtime.fail("INCOMPLETE")
	var phase := nation_scope_receipt_candidate(job.nation_token, _nation_administration_event(job))
	if not phase.ok: return phase
	# All original operator/source/product/Scope checks precede this tail.
	if job.nation_original_kind == "procurement": job.nation_order_ref.erase("tech_trial")
	publish_phase_receipt(phase)
	return Runtime.ok("原兩筆採購／原作坊實績及真人300秒檢验同次完成")

func _nation_original_administration_context(job: Dictionary) -> Dictionary:
	if not is_same(_jobs.get(str(int(job.executor_id)), {}), job) or not is_same(job.terrain, lab.terrain) or not is_same(job.site_state, lab.terrain.site): return Runtime.fail("STALE_SOURCE")
	var nation: Dictionary = _technology_scope_owner("nation", str(job.nation_id))
	var kind := str(job.nation_original_kind)
	var map_key := "specs" if kind == "procurement" else "certificates"
	var original: Dictionary = nation.get("technology_operations", {}).get(map_key, {}).get(str(job.nation_order_id), {})
	if not is_same(nation, job.nation_ref) or not is_same(original, job.nation_order_ref) or original != job.nation_original_expected: return Runtime.fail("STALE_ORDER")
	var duty_id := "nation.procurement" if kind == "procurement" else "nation.workshop"
	var checked: Dictionary = equipment_orders._nation_operation_context(int(original.authorizer_id), str(job.nation_id), duty_id, "N01" if kind == "procurement" else "N04", str(job.nation_binding), true)
	if not checked.ok: return checked
	var person := _technology_scope_person("nation", nation, int(job.executor_id), true)
	if not person.ok: return person
	if not is_same(person.person.body, job.executor_body) or int(person.person.hit) != int(job.executor_hit) or lab.terrain.index(person.person.cell) != int(job.executor_cell): return Runtime.fail("INTERRUPTED")
	var phase := _technology_phase_context(job.nation_token, false, false)
	if not phase.ok: return phase
	var paid := false
	for payment: Dictionary in phase.project.budget.get("payments", []):
		if payment.attempt == job.nation_token.attempt and payment.phase_id == job.nation_token.phase_id and payment.target_id == job.nation_target \
			and payment.person == job.nation_token.person and Technology.material_equal(payment.materials, job.nation_token.materials): paid = true
	if not paid: return Runtime.fail("NO_PAYMENT")
	if kind == "procurement":
		if original.get("tech_trial", {}) != job.nation_token or original.receipts.size() != 2: return Runtime.fail("INVALID_RECEIPT")
		for receipt: Dictionary in original.receipts:
			if receipt.source_person_id != job.executor_id or not Technology.material_equal(receipt.resources, {"wood": 1, "grain": 1}) or not receipt.items.is_empty(): return Runtime.fail("INVALID_RECEIPT")
	else:
		var output: Dictionary = equipment_orders._output_receipt(str(original.feature_id), int(original.receipt_id))
		if original.status != "active" or output.is_empty() or output != original.accepted_receipt \
			or not equipment_orders._workshop_context(str(original.feature_id), str(original.industry_id), int(original.operator_id)).ok: return Runtime.fail("STALE_PRODUCT")
	return Runtime.ok("", {"context": {"nation": nation, "order": original}, "person": person.person})

func settlement_food_receipt_query(token: Dictionary, event: Dictionary) -> Dictionary:
	var job: Dictionary = _jobs.get(str(int(token.get("person", {}).get("person_id", -1))), {})
	if job.get("kind") != "food_order" or not is_same(job.get("nation_token"), token) \
		or _settlement_food_event(job) != event or float(job.elapsed) != 300.0: return Runtime.fail("INVALID_RECEIPT")
	var checked := _settlement_food_job_context(job)
	if not checked.ok: return checked
	if checked.order.receipts.size() != 2 or checked.order.receipts[1].kind != "arrive" \
		or int(checked.order.receipts[1].quantity) != 8 or not Technology.material_equal(event.materials, {"grain": 8}): return Runtime.fail("WAITING")
	return Runtime.ok("原來源到倉庫8糧已實交且原具名300秒完成")

func settle_fire_pot_trials() -> void:
	for vehicle: Dictionary in lab.terrain.site.get("vehicles", {}).values():
		var proof: Dictionary = vehicle.get("tech_fire_pot_shot", {})
		if proof.get("phase") != "contact": continue
		var unit: Dictionary = lab.terrain.site.get("fire", {}).get("units", {}).get(str(proof.unit_key), {})
		if unit.is_empty() or int(unit.generation) != int(proof.generation) or float(unit.scorch) <= float(proof.scorch) + 0.000000001: continue
		var token: Dictionary = proof.token
		var context := _fire_pot_shot_phase_context(token, false, false)
		if not context.ok: continue # Current life/authority governs knowledge.
		var paid: Dictionary = {}
		for payment: Dictionary in context.project.budget.payments:
			if payment.payment_id == proof.payment_id and int(payment.attempt) == int(token.attempt) \
				and payment.phase_id == token.phase_id and payment.target_id == token.target_id \
				and Technology.same_person_ref(payment.person, token.person) and Technology.material_equal(payment.materials, {"fire_pot": 1}): paid = payment
		if paid.is_empty(): continue
		var payment := Runtime.ok("", {"owner": context.owner, "record": context.record, "state": context.record,
			"payment_id": str(paid.payment_id), "site_state": lab.terrain.site})
		var completed := _prepare_scope_phase_completion(token, payment, "F15:shot:" + str(proof.attack_id), 0.0)
		if not completed.ok: continue
		publish_phase_receipt(completed)
		proof.phase = "complete"

func publish_native_fire_point(prepared: Dictionary) -> void:
	# Original point no-failure tail only: no context queries, new planning,
	# fatigue writes, Runtime reprepare or callbacks between actual holder debits.
	if bool(prepared.published): return # SAME original point candidate cannot debit twice.
	prepared.published = true
	for row: Dictionary in prepared.rows:
		var job: Dictionary = row.job
		job.pending = {}
		if str(row.status) == "WORK":
			if int(row.paid_q) > 0:
				var committed: Dictionary = Runtime.publish_validated_fire_suppression(lab.terrain, row.prepared, row.check)
				job.executor_version = int(committed.holder_version)
				job.supply_q = int(committed.remaining_q)
				job.committed_q = int(job.committed_q) + int(row.paid_q)
				var profile: Dictionary = SiteCombatRules.fire_work_profile(str(job.get("fire_work_mode", "SUPPRESS")))
				job.elapsed = float(job.elapsed) + float(row.paid_q) / int(profile.supply_q_per_second)
			job.fraction_q = float(row.fraction_after)
			job.paused = str(row.get("paused", ""))
		elif str(row.status) == "DEFER": job.paused = "CAPACITY_DEFERRED"
	# Post-tail original cancellation/release/REST owners run after all Native
	# fatigue/progress publication. They never classify or debit this point again.

func native_fire_point_envelope_requests(game_seconds: float) -> Dictionary:
	# PURE conservative pre-World upper effort, solely for clipping REST80.
	# This is not permission to work and is never passed to a real consumer.
	# Include existing approach jobs: they can truly arrive at this endpoint.
	if not is_finite(game_seconds) or game_seconds <= 0.0: return Runtime.fail("INVALID_TIME")
	var requests: Array[Dictionary] = []
	var keys: Array = _jobs.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return int(a) < int(b))
	for key: String in keys:
		var job: Dictionary = _jobs[key]
		if str(job.kind) != "fire_suppress" or bool(job.cancelled) or not job.executor_owner is CrowdOwner: continue
		var participant: Dictionary = lab.crowd_site.work_fatigue_participant(int(job.executor_id), true)
		if participant.is_empty(): continue # Original fresh host input forbids work.
		requests.append({"provider": "fire_envelope", "key": key, "participants": [participant],
			"remaining": game_seconds, "productive_kind": "raw", "progress_multiplier": 1.0, "max_game_seconds": game_seconds})
	return Runtime.ok("原滅火努力上界；不代表授權／真消費", {"requests": requests})

func finish_native_fire_point(prepared: Dictionary) -> void:
	if not bool(prepared.published) or bool(prepared.finished): return
	prepared.finished = true
	for row: Dictionary in prepared.rows:
		var job: Dictionary = row.job
		if str(row.status) == "CANCEL": _cancel_fire_suppress(job, row.result)
		elif str(row.status) == "WORK":
			var person: Dictionary = _person(int(job.executor_id), false)
			if not person.is_empty():
				# Read TRUE published hot fatigue. A prefix ending exactly at80 is
				# legal even when the planner does not iterate another REST segment.
				var resting: bool = str(row.get("paused", "")) == "REST" or Fatigue.needs_work_rest(
					float(_body_get(person, "fatigue")), bool(_body_get(person, "work_resting")))
				_body_set(person, "work_resting", resting)
				if resting:
					job.phase = "REST"; job.paused = "REST"
					person.owner.work_fatigue_rest(int(job.executor_id))
			if int(job.supply_q) <= 0: _cancel_fire_suppress(job, Runtime.fail("NO_SUPPRESSION_SUPPLY", "本人有限補給已用盡"))
		if bool(job.cancelled): _settle_cancelled_fire_suppress(str(row.key), job)

func _advance_controlled_feature_work(key: String, job: Dictionary, seconds: float, work_plan: Dictionary, handled: Dictionary) -> void:
	if job.get("kind") == "technology_vehicle":
		_advance_controlled_vehicle_work(key, job, seconds, work_plan, handled)
		return
	if _controlled_feature_consumed.has(key) or not is_equal_approx(seconds, _controlled_feature_seconds): return
	_controlled_feature_consumed[key] = true
	var original_plan: Dictionary = lab.site_controller._shared_work_plan
	if not is_same(original_plan, lab._shared_work_plan) or not bool(original_plan.get("ok", false)) \
		or not is_equal_approx(float(original_plan.get("seconds", -1.0)), seconds) \
		or not is_same(work_plan.get("jobs"), original_plan.get("jobs", {}).get("person_actions")): job.paused = "CLOCK_NOT_READY"; return
	var held: Dictionary = _prepared_controlled_features.get(key, {})
	if held.is_empty() or not is_same(held.job, job) or not is_same(_jobs.get(key), job): job.paused = "CLOCK_NOT_READY"; return
	var context := _controlled_feature_job_context(job)
	if not context.ok: _finish(key, context); return
	var current := Runtime.work_preflight(lab.terrain, job.work_task, held.cargo, int(held.carry_limit), int(context.person.faction), int(job.executor_id), _tent_occupied)
	if not current.ok or not is_equal_approx(float(current.get("productivity", -1.0)), float(held.productivity)) \
		or current.get("required_skill", "") != held.required_skill or bool(current.get("eligible_master", false)) != bool(held.eligible_master): job.paused = "STALE_SOURCE"; return
	var interval: Dictionary = work_plan.get("jobs", {}).get(key, {})
	if interval.is_empty() and float(held.remaining) > 0.0: job.paused = "CLOCK_NOT_READY"; return
	var identity := int(job.executor_id)
	var effort := float(interval.get("participant_seconds", {}).get(identity, 0.0))
	var base := float(interval.get("participant_effective_seconds", {}).get(identity, 0.0))
	if not is_finite(effort) or effort < 0.0 or not is_finite(base) or base < 0.0: job.paused = "CLOCK_NOT_READY"; return
	job.paused = str(interval.get("paused", ""))
	if not bool(context.person.player):
		if effort > 0.0: _body_set(context.person, "work_resting", false)
		if job.paused == "REST" or interval.get("participant_paused", {}).get(identity) == "REST":
			_body_set(context.person, "work_resting", true)
			if context.person.owner is CrowdOwner: context.person.owner.work_fatigue_rest(identity)
	if base <= 0.0 and float(held.remaining) > 0.0: return
	_controlled_feature_allocation = {"key": key, "held": held, "interval": interval}
	var consumed := {"used": false}
	var work_time := func(_manual: bool, _minutes: float) -> float:
		if consumed.used: return 0.0
		consumed.used = true
		handled[identity] = effort
		return base / 60.0 # The original complete-pool collector charged fatigue once.
	Runtime._work(lab.terrain, seconds / 60.0, true, false, _tent_occupied, work_time, job.work_task, held.cargo,
		int(held.carry_limit), Runtime.CARRY_CAPACITY, int(context.person.faction), false, identity)
	_controlled_feature_allocation = {}
	if _jobs.has(key) and str(job.work_task.get("target", "")).is_empty(): _finish(key, Runtime.ok("原工序已收束，本人停止"))

func _consume_shared_job_advance_prefix(key: String, job: Dictionary, seconds: float, work_plan: Dictionary) -> Dictionary:
	var item: Dictionary = shared_job_work_prefix(key, job)
	if item.is_empty(): return {}
	if not is_equal_approx(seconds, float(_shared_work_prefix_consumption.seconds)) \
		or not is_same(work_plan.get("jobs"), _shared_work_prefix_consumption.plan.get("jobs", {}).get("person_actions")):
		return {"duplicate": true} # Wrong interval must not consume the held prefix or fall back.
	if bool(item.advance_consumed): return {"duplicate": true}
	item.advance_consumed = true
	return {"duplicate": false, "prefix": item}

func record_fire_pot_release(vehicle: Dictionary, flight: Dictionary) -> void:
	var token: Dictionary = flight.get("tech_trial", {})
	if token.is_empty(): return
	if not lab.siege_projectiles.any(func(row: Dictionary) -> bool: return is_same(row, flight)) \
		or not is_same(lab.terrain.site.get("vehicles", {}).get(str(vehicle.get("id", ""))), vehicle) \
		or not is_same(vehicle.command.get("tech_trial"), token) or flight.get("ammo") != "fire_pot" \
		or str(flight.source_vehicle) != str(vehicle.id) or int(flight.source_member_id) != int(token.person.person_id) \
		or str(flight.attack_id) != _technology_site_id() + "|" + str(vehicle.id) + "|" + str(int(vehicle.next_attack_seq) - 1): return
	var raw: Dictionary = _technology_family().get("technology", {})
	var project := Technology.active_project(raw)
	if project.is_empty() or project.get("tech_id") != "F15" or int(project.id) != int(token.project_id): return
	var paid := false
	for payment: Dictionary in project.budget.get("payments", []):
		if payment.payment_id == str(flight.technology_payment_id) and int(payment.attempt) == int(token.attempt) \
			and payment.phase_id == token.phase_id and payment.target_id == token.target_id \
			and Technology.same_person_ref(payment.person, token.person) and Technology.material_equal(payment.materials, {"fire_pot": 1}): paid = true
	if not paid: return
	# Only the original launcher calls after its no-fail real ammo/payment tail.
	# This persisted result belongs to that same original vehicle, not a new job.
	vehicle.tech_fire_pot_shot = {"version": 1, "token": token, "attack_id": str(flight.attack_id),
		"projectile_id": int(flight.projectile_id), "payment_id": str(flight.technology_payment_id), "phase": "flight",
		"unit_key": "", "generation": 0, "scorch": 0.0, "impact_action": 0.0}

func native_fire_point_candidates(action_begin: float, action_end: float, game_seconds: float) -> Dictionary:
	if not is_finite(game_seconds) or game_seconds <= 0.0 or not is_finite(action_begin) or not is_finite(action_end) or action_end <= action_begin:
		return Runtime.fail("INVALID_TIME")
	var records: Array[Dictionary] = []
	var requests: Array[Dictionary] = []
	var keys: Array = _jobs.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return int(a) < int(b))
	for key: String in keys:
		var job: Dictionary = _jobs[key]
		if str(job.kind) != "fire_suppress": continue
		if not job.executor_owner is CrowdOwner: continue # A truly dead Native executor still needs fail0cost settlement.
		var row := {"key": key, "job": job, "pending": job.pending, "status": "SKIP", "result": Runtime.ok(),
			"ratio": game_seconds / (action_end - action_begin), "limit": 0.0, "request": {}}
		records.append(row)
		if bool(job.cancelled) or job.pending.is_empty(): continue
		if absf(float(job.pending.begin) - action_begin) > Runtime.FIRE_EPS or absf(float(job.pending.end) - action_end) > Runtime.FIRE_EPS \
			or absf(float(job.pending.game_seconds) - game_seconds) > Runtime.FIRE_EPS:
			return Runtime.fail("STALE_FIRE_INTERVAL")
		if lab.native_checked_forecast_hp(int(job.executor_id)) <= 0.0:
			row.status = "CANCEL"; row.result = Runtime.fail("DEAD"); continue
		var check: Dictionary = _fire_suppress_context(job) # TRUE end-contact qualification, no mutation.
		if not check.ok:
			row.status = "CANCEL"; row.result = check; continue
		if bool(check.target.complete):
			row.status = "CANCEL"; row.result = Runtime.ok("原工作目標已完成"); continue
		if str(check.movement.phase) != "ARRIVED" or bool(check.person.moving) or not _ready(check.person) \
			or not lab.crowd_site.work_fatigue_work_start_ready(int(job.executor_id)):
			row.status = "CANCEL"; row.result = Runtime.fail("INTERRUPTED"); continue
		var participant: Dictionary = lab.crowd_site.work_fatigue_participant(int(job.executor_id), true)
		if participant.is_empty(): return Runtime.fail("CLOCK_NOT_READY")
		var profile: Dictionary = SiteCombatRules.fire_work_profile(str(job.get("fire_work_mode", "SUPPRESS")))
		var fraction: float = float(job.fraction_q)
		if not is_finite(fraction) or fraction < 0.0 or fraction >= 1.0 + Runtime.FIRE_EPS: return Runtime.fail("INVALID_WORK")
		var supply_field: String = str(profile.supply_field)
		var stock: int = int(check.person.holder.get(supply_field, 0))
		if stock <= 0:
			row.status = "CANCEL"; row.result = Runtime.fail("NO_SUPPRESSION_SUPPLY"); continue
		var duration: float = minf(action_end - action_begin, maxf(0.0, float(stock) - fraction) / int(profile.supply_q_per_second))
		if duration <= Runtime.FIRE_EPS: continue
		var requested: int = floori(fraction + duration * int(profile.supply_q_per_second) + Runtime.FIRE_EPS)
		if requested > 0:
			var paid: Dictionary = Runtime.fire_prepare_suppression(lab.terrain, str(job.target_key), int(job.generation),
				action_begin, action_begin + duration, requested, check.person.holder, int(job.executor_version), str(job.get("fire_work_mode", "SUPPRESS")))
			if not paid.ok:
				row.status = "DEFER" if str(paid.get("code", "")) == "CAPACITY_DEFERRED" else "CANCEL"
				row.result = paid; continue
			if int(paid.get("paid_q", 0)) <= 0: continue
			if int(paid.paid_q) < requested: duration = minf(duration, maxf(0.0, float(paid.paid_q) - fraction) / int(profile.supply_q_per_second))
		row.status = "WORK"
		row.limit = duration * float(row.ratio)
		row.request = {"provider": "fire_suppress", "key": key, "participants": [participant],
			"remaining": float(row.limit), "productive_kind": "raw", "progress_multiplier": 1.0, "max_game_seconds": float(row.limit)}
		requests.append(row.request)
	return Runtime.ok("原滅火接觸後努力候選", {"records": records, "requests": requests})

func prepare_native_fire_point(records: Array, plan: Dictionary) -> Dictionary:
	# Pure finalization. Replan limits only decrease; no pending/holder/body/job
	# progress is touched before every Native/Runtime/material final gate passes.
	var rows: Array[Dictionary] = []
	var paid_rows: Array[Dictionary] = []
	for source: Dictionary in records:
		var row: Dictionary = source.duplicate(false)
		var job: Dictionary = row.job
		if not is_same(_jobs.get(str(row.key), {}), job) or not is_same(job.pending, row.pending): return Runtime.fail("STALE_FIRE_JOB")
		row.actual_game = 0.0; row.actual_action = 0.0; row.paid_q = 0; row.fraction_after = float(job.fraction_q)
		row.prepared = {}; row.check = {}
		rows.append(row)
		if str(row.status) != "WORK": continue
		var allocation: Dictionary = plan.get("jobs", {}).get("fire_suppress", {}).get(str(row.key), {})
		if allocation.is_empty(): return Runtime.fail("MISSING_FIRE_ALLOCATION")
		row.paused = str(allocation.get("paused", ""))
		row.actual_game = float(allocation.get("participant_seconds", {}).get(int(job.executor_id), 0.0))
		if not is_finite(float(row.actual_game)) or float(row.actual_game) < 0.0 or float(row.actual_game) > float(row.limit) + Runtime.FIRE_EPS:
			return Runtime.fail("INVALID_WORK")
		if float(row.actual_game) <= Runtime.FIRE_EPS: continue
		var context: Dictionary = _fire_suppress_context(job)
		if not context.ok: return Runtime.fail("FIRE_POINT_RECLASSIFY", "原接觸結果已變，尚未支付")
		var profile: Dictionary = SiteCombatRules.fire_work_profile(str(job.get("fire_work_mode", "SUPPRESS")))
		row.actual_action = float(row.actual_game) / float(row.ratio)
		var exact: float = float(job.fraction_q) + float(row.actual_action) * int(profile.supply_q_per_second)
		var requested: int = floori(exact + Runtime.FIRE_EPS)
		if requested == 0:
			row.fraction_after = exact # Legitimate fraction work STILL has real effort.
			continue
		var prepared: Dictionary = Runtime.fire_prepare_suppression(lab.terrain, str(job.target_key), int(job.generation),
			float(row.pending.begin), float(row.pending.begin) + float(row.actual_action), requested, context.person.holder,
			int(job.executor_version), str(job.get("fire_work_mode", "SUPPRESS")))
		if not prepared.ok or int(prepared.get("paid_q", 0)) != requested:
			return Runtime.fail("FIRE_POINT_RECLASSIFY", "原供給或目標候選已變，尚未支付")
		row.prepared = prepared
		row.paid_q = requested
		row.fraction_after = maxf(0.0, exact - requested)
		paid_rows.append({"key": str(row.key), "prepared": prepared,
			"fraction": float(job.fraction_q), "ratio": float(row.ratio), "supply_per_second": int(profile.supply_q_per_second)})
	var batch: Dictionary = Runtime.prepare_fire_suppression_batch(lab.terrain, paid_rows)
	if not batch.ok: return batch
	if bool(batch.get("needs_replan", false)):
		return Runtime.ok("同點有限供給／火量已重新配額；未扣款", {"needs_replan": true, "limits": batch.limits})
	for row: Dictionary in rows:
		if int(row.paid_q) <= 0: continue
		var admitted: Dictionary = batch.jobs[str(row.key)]
		row.prepared = admitted.prepared; row.check = admitted.check
	return Runtime.ok("原滅火同點全部純預驗完成", {"rows": rows, "needs_replan": false, "published": false, "finished": false})

func record_fire_pot_impact(flight: Dictionary, received: Dictionary, impact_action: float) -> void:
	var vehicle: Dictionary = lab.terrain.site.get("vehicles", {}).get(str(flight.source_vehicle), {})
	var proof: Dictionary = vehicle.get("tech_fire_pot_shot", {})
	if proof.is_empty() or proof.attack_id != flight.attack_id or int(proof.projectile_id) != int(flight.projectile_id) \
		or proof.token != flight.get("tech_trial", {}) or proof.phase != "flight": return
	proof.phase = "miss"
	if not received.get("ok", false) or not received.get("accepted", false) or received.get("duplicate", false): return
	var unit: Dictionary = lab.terrain.site.get("fire", {}).get("units", {}).get(str(received.unit_key), {})
	if unit.is_empty() or int(unit.generation) != int(received.generation): return
	proof.merge({"phase": "contact", "unit_key": str(received.unit_key), "generation": int(received.generation),
		"scorch": float(unit.scorch), "impact_action": impact_action})

func finish_checked_controlled_prefixes(prepared: Dictionary) -> void:
	# Native already published. Original current product/receipt guard may now
	# defer/cancel; it never discards the original paid completed progress.
	if prepared.get("owner") != self or not bool(prepared.get("published", false)) or bool(prepared.get("finished", false)): return
	prepared.finished = true
	for key: String in prepared.checked.admitted.prepared.held:
		var held: Dictionary = prepared.checked.admitted.prepared.held[key]
		if held.kind not in ["technology_feature", "technology_vehicle"]: continue
		var person: Dictionary = _person(int(held.job.executor_id))
		if person.is_empty() or bool(person.player): continue
		var allocation: Dictionary = prepared.checked.plan.jobs.get("person_actions", {}).get(key, {})
		var actual: float = float(allocation.get("participant_seconds", {}).get(int(person.person_id), 0.0))
		if actual > 0.0: _body_set(person, "work_resting", false)
		if str(allocation.get("paused", "")) == "REST" or str(allocation.get("participant_paused", {}).get(int(person.person_id), "")) == "REST":
			_body_set(person, "work_resting", true)
			if person.owner is CrowdOwner: person.owner.work_fatigue_rest(int(person.person_id))
	for candidate: Dictionary in prepared.checked.runtime: Runtime.settle_checked_work_prefix(candidate)
	discard_checked_controlled_prefixes()

# Root glue: init/teardown invokes discard_checked_controlled_prefixes().
# Existing advance controlled feature and controlled vehicle branch remain
# FIRST; both _advance methods early-return for _controlled_feature_consumed.
# Their legacy predicates/_work/advance_siege_work are never the point tail.
# No Native allocation/checked admission means CLOCK_NOT_READY, not fallback.

func finish_shared_work_prefix(admitted: Dictionary) -> void:
	# AFTER Native publication and before original new-death queue handoff.
	# Original cancellation/receipt logic still runs in settle_after_contacts.
	if admitted.get("owner") != self or not is_same(admitted.prepared.site, lab.terrain.site): return
	if bool(admitted.get("rest_finished", false)): return
	admitted.rest_finished = true
	for key: String in admitted.admitted:
		var item: Dictionary = admitted.admitted[key]
		for identity: int in item.held.people:
			var person: Dictionary = _person(identity)
			if person.is_empty() or not person.owner is CrowdOwner or bool(person.player): continue
			var paused: String = str(item.allocation.get("participant_paused", {}).get(identity, item.allocation.get("paused", "")))
			if paused == "REST" or Fatigue.needs_work_rest(float(_body_get(person, "fatigue")), bool(_body_get(person, "work_resting"))):
				_body_set(person, "work_resting", true)
				person.owner.work_fatigue_rest(identity)

func _advance_controlled_vehicle_work(key: String, job: Dictionary, seconds: float, work_plan: Dictionary, handled: Dictionary) -> void:
	if _controlled_feature_consumed.has(key) or not is_equal_approx(seconds, _controlled_feature_seconds): return
	_controlled_feature_consumed[key] = true
	var original_plan: Dictionary = lab.site_controller._shared_work_plan
	if not is_same(original_plan, lab._shared_work_plan) or not bool(original_plan.get("ok", false)) \
		or not is_equal_approx(float(original_plan.get("seconds", -1.0)), seconds) \
		or not is_same(work_plan.get("jobs"), original_plan.get("jobs", {}).get("person_actions")): job.paused = "CLOCK_NOT_READY"; return
	var held: Dictionary = _prepared_controlled_features.get(key, {})
	if held.is_empty() or not is_same(held.job, job) or not is_same(_jobs.get(key), job): job.paused = "CLOCK_NOT_READY"; return
	var context := _controlled_vehicle_job_context(job)
	if not context.ok: _finish(key, context); return
	var current := Runtime.work_preflight(lab.terrain, job.work_task, held.cargo, int(held.carry_limit), int(context.person.faction), int(job.executor_id), _tent_occupied)
	if not current.ok or not is_equal_approx(float(current.get("progress_multiplier", -1.0)), float(held.factor)) \
		or not is_equal_approx(float(current.get("productivity", -1.0)), float(held.productivity)) \
		or current.get("required_skill", "") != held.required_skill or bool(current.get("eligible_master", false)) != bool(held.eligible_master): job.paused = "STALE_SOURCE"; return
	var interval: Dictionary = work_plan.get("jobs", {}).get(key, {})
	if interval.is_empty() and float(held.remaining) > 0.0: job.paused = "CLOCK_NOT_READY"; return
	var identity := int(job.executor_id)
	var effort := float(interval.get("participant_seconds", {}).get(identity, 0.0))
	var base := float(interval.get("participant_effective_seconds", {}).get(identity, 0.0))
	if not is_finite(effort) or effort < 0.0 or not is_finite(base) or base < 0.0: job.paused = "CLOCK_NOT_READY"; return
	job.paused = str(interval.get("paused", ""))
	if not bool(context.person.player):
		if effort > 0.0: _body_set(context.person, "work_resting", false)
		if job.paused == "REST" or interval.get("participant_paused", {}).get(identity) == "REST": _body_set(context.person, "work_resting", true)
	if base <= 0.0 and float(held.remaining) > 0.0: return
	_controlled_feature_allocation = {"key": key, "held": held, "interval": interval}
	handled[identity] = effort # Fatigue belongs to the original complete-pool publisher.
	var result := Runtime.advance_siege_work(lab.terrain, str(job.vehicle_id), "construct", base, context.person.cell,
		int(job.work_task.work_slot), int(job.team_ref.team_id), job.work_task, identity)
	_controlled_feature_allocation = {}
	if _jobs.has(key):
		job.work_task.status = str(result.message)
		if not result.ok: job.paused = str(result.code)

# Original ordinary team.work command. Its current decider names an existing
# member; membership/duty/fitness are re-queried, never a caller approval bool.

func shared_job_work_prefix(key: String, job: Dictionary) -> Dictionary:
	if _shared_work_prefix_consumption.is_empty() or not is_same(_shared_work_prefix_consumption.plan, lab._shared_work_plan): return {}
	var item: Dictionary = _shared_work_prefix_consumption.admitted.get(key, {})
	if item.is_empty() or not is_same(_jobs.get(key), job) or not is_same(item.held.job, job): return {}
	return item # metadata only, no fake current person and no receipt permission.

func controlled_feature_work_task(task: Dictionary) -> Dictionary:
	for key: String in _prepared_controlled_features:
		var held: Dictionary = _prepared_controlled_features[key]
		if not is_same(held.task, task) or not is_same(_jobs.get(key), held.job): continue
		var context := _controlled_feature_job_context(held.job)
		if not context.ok: return {}
		return {"task": task, "person_id": int(held.job.executor_id), "site": lab.terrain.site, "target": str(task.target),
			"work_cell": int(task.work_cell), "work_slot": int(task.work_slot), "action": str(task.action)}
	return {}

func prepare_nation_route_load_phase(nation_id: String, order_id: String, original_order: Dictionary) -> Dictionary:
	var selected := _nation_original_research_token(nation_id, order_id, "N08", "public_route", str(original_order.payload.destination_holder))
	if not selected.ok: return selected
	if selected.token.is_empty(): return Runtime.ok("", {"token": {}, "binding": {}, "payment": {}})
	var token: Dictionary = selected.token
	if int(token.person.person_id) != int(original_order.payload.driver_id) or not Technology.material_equal(token.materials, {"grain": 4}):
		return Runtime.fail("WRONG_EXECUTOR", "本次研究須由本單原車的真舵手／操作人執行同四糧運輸")
	var source := nation_research_source_candidate(token, order_id)
	if not source.ok: return source
	var binding := technology_phase_binding_candidate(token, source)
	if not binding.ok: return binding
	var payment := technology_phase_payment_candidate(token, {"grain": 4}, binding, source)
	if not payment.ok: return payment
	return Runtime.ok("", {"token": token, "binding": binding, "payment": payment})

## Research work-consent still comes from the original team.work owner.
## Only the exact current N08 project/order may use its actual wagon operator.

func _nation_n08_driver_context(identity: int, purpose: String) -> Dictionary:
	if lab.site_controller == null or lab.site_controller.region_slot == null: return Runtime.fail("NO_REGION_SLOT")
	for nation_id: String in lab.terrain.site.get("equipment_nations", {}):
		var nation: Dictionary = lab.terrain.site.equipment_nations[nation_id]
		var record: Dictionary = nation.get("technology", {})
		var project := Technology.active_project(record)
		if project.get("tech_id") != "N08" or project.get("purpose") != purpose or int(project.get("executor", {}).get("person_id", -1)) != identity: continue
		return lab.site_controller.region_slot.nation_n08_driver_consent_context(lab, nation_id, identity, purpose)
	return Runtime.fail("NO_TARGET")
