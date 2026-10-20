extends RefCounted
## R7 B (plan 10.3): the two-phase companion-batch executor for family and national departures. Phase 1 computes every request's
## candidate over copies, in order, through the existing pure candidates (FamilyContinuity.departure_candidate and
## SiteEquipmentOrders.nation_departure_candidate), so each owner's rules and guards apply. A single refusal returns before any
## write. Phase 2 writes the family, the nations and the family departure history; it cannot fail. The controlled person is never
## batched (plan 10.2: controlled departures are explicit). At most MAX_BATCH real persons per batch (plan 10.3).

const FamilyContinuity = preload("res://scripts/terrain_lab/site_family_continuity.gd")
const EquipmentOrders = preload("res://scripts/terrain_lab/site_equipment_orders.gd")
const MAX_BATCH := 10
const TeamDeparture = preload("res://scripts/terrain_lab/site_team_departure.gd") # R7 C: the team seat candidate.
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd") # R7 C: the shared last-member refusal.

## requests: Array of {person_id: int, owner_kind: "family" | "nation", nation_id: String (nation only)}.
static func execute(lab: Variant, requests: Array) -> Dictionary:
	if requests.size() > MAX_BATCH: return {"ok": false, "code": "BATCH_TOO_LARGE", "message": "每批最多 %d 人" % MAX_BATCH}
	var site: Dictionary = lab.terrain.site
	var controlled := int(lab.controlled_person_id())
	var seen := {}
	for request: Variant in requests:
		if not request is Dictionary: return {"ok": false, "code": "NO_TARGET", "message": "批次項目格式非法"}
		var person_id := int(request.get("person_id", 0))
		if person_id == controlled: return {"ok": false, "code": "NO_AUTHORITY", "message": "受控者不入批次，須明示離開"}
		var key := "%s:%s:%d" % [str(request.get("owner_kind", "")), str(request.get("nation_id", "")), person_id]
		if seen.has(key): return {"ok": false, "code": "DUPLICATE_ID", "message": "同一原人物同一組織不可重複列入"}
		seen[key] = true

	# Phase 1: validate every request over copies, in order. Nothing in the site is written here.
	var family_candidate: Variant = site.get("family")
	var family_changed := false
	var departures: Array = []
	var nation_candidates: Dictionary = {}
	var team_plans: Array = []
	var team_seen := {}
	for request: Variant in requests:
		var person_id := int(request.get("person_id", 0))
		var authority := {"kind": "npc_event", "event_id": "batch"}
		if str(request.get("owner_kind", "")) == "family":
			if not family_candidate is Dictionary: return {"ok": false, "code": "UNREGISTERED", "message": "先明確登錄家族名單"}
			var checked_family: Dictionary = FamilyContinuity.departure_candidate(family_candidate, str(site.id), person_id, authority, controlled)
			if not checked_family.get("ok", false): return {"ok": false, "code": str(checked_family.code), "message": "整批未提交：%s" % str(checked_family.get("message", "")), "failed": person_id}
			family_candidate = checked_family.family
			family_changed = true
			departures.append({"person_id": person_id, "minute": int(site.get("minute", 0)), "authority": "npc_event", "seat_vacated": bool(checked_family.get("seat_vacated", false))})
		elif str(request.get("owner_kind", "")) == "nation":
			var nation_id := str(request.get("nation_id", ""))
			var nations: Dictionary = site.get("equipment_nations", {})
			var nation_now: Variant = nation_candidates.get(nation_id, nations.get(nation_id, {}))
			if not nation_now is Dictionary or nation_now.is_empty(): return {"ok": false, "code": "NO_TARGET", "message": "沒有此國家", "failed": person_id}
			var checked_nation: Dictionary = EquipmentOrders.nation_departure_candidate(nation_now, person_id, authority, controlled)
			if not checked_nation.get("ok", false): return {"ok": false, "code": str(checked_nation.code), "message": "整批未提交：%s" % str(checked_nation.get("message", "")), "failed": person_id}
			nation_candidates[nation_id] = checked_nation.nation
		elif str(request.get("owner_kind", "")) == "team":
			var team: TerrainArmy = _team_by_id(lab, int(request.get("team_id", 0)))
			if team == null: return {"ok": false, "code": "NO_TARGET", "message": "沒有此隊伍", "failed": person_id}
			if team_seen.has(team.team_id): return {"ok": false, "code": "TEAM_MULTI", "message": "同一批僅能處理一隊的成員（供養計畫不互相接續）", "failed": person_id}
			team_seen[team.team_id] = true
			var refusal: Dictionary = team.row_membership_refusal(person_id, false, -1, true)
			if not bool(refusal.get("ok", false)): return {"ok": false, "code": str(refusal.get("code", "BUSY")), "message": "整批未提交：%s" % str(refusal.get("message", "")), "failed": person_id}
			var last_member: Dictionary = Runtime.team_last_member_refusal(lab.terrain, team, false)
			if not bool(last_member.get("ok", false)): return {"ok": false, "code": "BUSY", "message": "整批未提交：先完成或取消本隊原船塢作業", "failed": person_id}
			var supply: Dictionary = lab.site_controller.captivity_supply.membership_change_candidate(team, person_id, false)
			if not bool(supply.get("ok", false)): return {"ok": false, "code": str(supply.get("code", "INVALID_SUSTAIN")), "message": "整批未提交：供養計畫不可提交", "failed": person_id}
			var seats: Dictionary = TeamDeparture.vacate_seats(team.team_offices(true), person_id)
			if not bool(seats.get("ok", false)): return {"ok": false, "code": "NO_TARGET", "message": "整批未提交：隊職位不可更新", "failed": person_id}
			team_plans.append({"team": team, "person": person_id, "plan": supply.get("plan", {}), "changed": bool(seats.get("changed", false)), "offices": seats.offices})
		else:
			return {"ok": false, "code": "NO_TARGET", "message": "未知的組織種類", "failed": person_id}

	# Phase 2: commit. Every candidate was validated above; these writes cannot fail.
	if family_changed:
		var history: Array = site.family_departures.duplicate(true) if site.has("family_departures") else []
		history.append_array(departures)
		site.family.clear()
		site.family.merge(family_candidate, true)
		site.family_departures = history
	for nation_id: String in nation_candidates:
		var target: Dictionary = site.equipment_nations[nation_id]
		target.clear()
		target.merge(nation_candidates[nation_id], true)
	for plan: Dictionary in team_plans:
		var team: TerrainArmy = plan.team
		if not plan.plan.is_empty(): lab.site_controller.captivity_supply.membership_change_commit(plan.plan)
		team.commit_row_membership_change(int(plan.person), false)
		if bool(plan.changed): team.offices = plan.offices
	return {"ok": true, "code": "", "message": "已整批離開", "count": requests.size()}

static func _team_by_id(lab: Variant, team_id: int) -> TerrainArmy:
	for team: TerrainArmy in lab.combat_armies:
		if is_instance_valid(team) and team.team_id == team_id: return team
	return null
