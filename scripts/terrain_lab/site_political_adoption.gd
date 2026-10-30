extends RefCounted
## R3 (v2 plan §6.2–6.3): a captive's own willingness to surrender, the captor
## side's acceptance (settlement 典獄, else the captor) and the target nation's
## admission (nation.admission, default 戶籍官, head acting while vacant), then
## one atomic political adoption: custody days settled, captivity ended,
## feeding moved once to the person's own owner, the original row moved into the
## adopting faction's destination team as a non-member, nationality changed
## uniquely, old national posts vacated and corps the person commanded ended.
## Nothing is committed unless every check passes. Willing ≠ accepted: both
## authorities must consent. No officer post, cape, kit, knowledge or command is
## granted; recruitment and appointment use their own entries afterwards.
## First package: original Army-row captives only (an Actor captive waits for
## its own transfer path; no third Actor is cloned). Crowd: CROWD_UNSUPPORTED.

const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const SiteSocial = preload("res://scripts/terrain_lab/site_social.gd")
const Settlement = preload("res://scripts/terrain_lab/site_settlement.gd")

## `offer`: {"nation_id": String, "destination_team_id": int, "consent": bool}.
## `consent` is only read for the controlled person, who must confirm explicitly.
static func prepare(lab: Variant, target_id: int, offer: Dictionary, jail_requester: int, admission_requester: int) -> Dictionary:
	if lab == null or lab.terrain == null or lab.site_controller == null: return Runtime.fail("NO_SITE")
	var site: Dictionary = lab.terrain.site
	if lab.crowd_site != null and lab.crowd_site.active: return Runtime.fail("CROWD_UNSUPPORTED", "群眾模擬中不處理政治歸降")
	if bool(site.get("paused", false)) or float(site.get("combat_left", 0.0)) > 0.0: return Runtime.fail("BUSY", "須在停止、脫戰時處理歸降")
	var relation: Dictionary = site.get("captivity", {}).get(str(target_id), {})
	if relation.is_empty() or int(relation.get("version", 0)) < 3: return Runtime.fail("NO_TARGET", "沒有此人的原拘押紀錄")
	var actions: Variant = lab.site_controller.person_actions
	var person: Dictionary = actions._person(target_id)
	if person.is_empty() or not person.owner is TerrainArmy or int(person.unit) < 0:
		return Runtime.fail("ACTOR_PENDING", "原 Actor 的歸降移交尚未提供；保留拘押，不複製人物")
	var source: TerrainArmy = person.owner
	var unit := int(person.unit)
	if float(person.hp) <= 0.0 or float(person.ko) > 0.0 or actions.is_busy(target_id):
		return Runtime.fail("BUSY", "本人須清醒且沒有進行中的作業")
	# Willingness (§6.2): the controlled person only by explicit consent.
	var minute := int(site.get("minute", 0))
	var controlled := int(lab.controlled_person_id())
	var willing := SiteSocial.surrender_willingness(source.combat_units[unit], relation, minute)
	# Persuasion (site_persuasion.gd) already decided willingness by its own rules; only that caller sets "persuaded".
	var persuaded := bool(offer.get("persuaded", false)) and target_id != controlled
	if target_id == controlled:
		if not bool(offer.get("consent", false)): return Runtime.fail("NEEDS_CONSENT", "受控人物須自行明示接受歸降")
	elif not persuaded and not bool(willing.willing):
		return Runtime.fail("NOT_WILLING", "本人目前不願歸降（忠誠 %.2f／門檻 %.2f）" % [float(willing.get("L", 0)) / 100.0, float(willing.get("T", 0)) / 100.0])
	# Captor side (§6.3): the settlement 典獄 of the captor faction, else the captor.
	var settlement: Dictionary = Settlement.record(lab.terrain)
	if not settlement.is_empty() and int(settlement.owner_faction) == int(relation.captor_faction):
		var jail := Settlement.duty_resolve(lab, "settlement.prison")
		if not bool(jail.ok) or int(jail.decider) != jail_requester: return SiteOffices.refusal(jail, jail_requester, Settlement.offices(lab))
	elif jail_requester != int(relation.captor_id):
		return Runtime.fail("NO_AUTHORITY", "須由拘押方（典獄或原拘押者）接受歸降")
	# Target nation (§6.3): a formally established nation whose head is present.
	var nations: Dictionary = site.get("equipment_nations", {})
	var nation_id := str(offer.get("nation_id", ""))
	var nation: Dictionary = nations.get(nation_id, {})
	var orders: Variant = lab.site_controller.equipment_orders
	if nation.is_empty() or not nation.has("offices") or orders.nation_head_executor(nation) <= 0:
		return Runtime.fail("NO_NATION", "目標國尚未正式建制或元首不在；保留拘押")
	if nation.get("members", []).has(target_id): return Runtime.fail("NO_CHANGE", "此人已是目標國國民")
	var admission: Dictionary = orders.nation_duty_resolve(nation, "nation.admission")
	if not bool(admission.ok) or int(admission.decider) != admission_requester:
		return SiteOffices.refusal(admission, admission_requester, nation.offices)
	# Destination owner (§6.3): explicit team of the nation's faction (proved by
	# its head's actual faction, never guessed from the nation name).
	var destination: TerrainArmy = null
	for team: TerrainArmy in lab.combat_armies:
		if is_instance_valid(team) and team.team_id == int(offer.get("destination_team_id", -1)): destination = team
	var head: Dictionary = actions._person(orders.nation_head_executor(nation))
	if destination == null or head.is_empty() or int(head.faction) != int(destination.faction_id):
		return Runtime.fail("NO_DESTINATION", "須明示目標國勢力的合法接收隊伍")
	# The original prison owner proves contact, exit and current custody before
	# Supply prepares the political transaction's final home (not old release home).
	if not str(relation.get("prison_id", "")).is_empty():
		if actions.is_busy(jail_requester): return Runtime.fail("BUSY", "典獄須先完成現有作業")
		var exit: Dictionary = actions._prison_release_geometry(jail_requester, target_id)
		if not exit.ok: return exit
	var moved := source.adoption_row_check(destination, target_id)
	if not moved.ok: return moved
	if not actions.captivity_changed.is_valid(): return Runtime.fail("UNSUPPORTED", "原拘押通知尚未安裝")
	var supply: Dictionary = lab.site_controller.captivity_supply.adoption_guard(target_id, int(relation.captor_id), source.combat_hot_materialize(unit))
	if not supply.ok: return supply
	var old_nations: Array[String] = []
	for other_id: String in nations:
		if nations[other_id].get("members", []).has(target_id): old_nations.append(other_id)
	var corps_keys: Array[String] = []
	for key: String in site.get("corps", {}):
		if int(site.corps[key].get("commander_person_id", -1)) == target_id: corps_keys.append(key)
	return Runtime.ok("", {"target_id": target_id, "relation": relation, "source": source, "destination": destination,
		"nation_id": nation_id, "old_nations": old_nations, "corps": corps_keys, "minute": minute, "person": person,
		"willingness": willing})

## Formal direct/UI command: only the actual controlled person gives manual
## consent. Other sides use their existing enabled, deterministic R3 policy.
static func command(lab: Variant, target_id: int, offer: Dictionary, requester_id: int) -> Dictionary:
	if lab == null or lab.terrain == null or lab.site_controller == null: return Runtime.fail("NO_SITE")
	if requester_id != int(lab.controlled_person_id()): return Runtime.fail("NO_AUTHORITY", "須由目前受控人物明示同意")
	if not offer.get("nation_id") is String or not Runtime._building_integer(offer.get("destination_team_id"), 1, 2147483646) \
		or offer.has("consent") and not offer.consent is bool: return Runtime.fail("INVALID", "歸降提案須有目標國、真接收隊伍與布林本人同意")
	for field: Variant in offer:
		if field not in ["nation_id", "destination_team_id", "consent"]: return Runtime.fail("INVALID", "歸降提案含未知欄位")
	if lab.crowd_site != null and lab.crowd_site.active: return Runtime.fail("CROWD_UNSUPPORTED")
	if requester_id != target_id and not lab.site_controller.person_actions._ready(lab.site_controller.person_actions._person(requester_id)):
		return Runtime.fail("BUSY", "明示下令者須清醒自由且可行動")
	var relation: Dictionary = lab.terrain.site.get("captivity", {}).get(str(target_id), {})
	if relation.is_empty(): return Runtime.fail("NO_TARGET")
	var settlement: Dictionary = Settlement.record(lab.terrain)
	var governed := not settlement.is_empty() and int(settlement.owner_faction) == int(relation.captor_faction)
	var jail: Dictionary = Settlement.duty_resolve(lab, "settlement.prison") if governed else {"ok": true, "decider": int(relation.captor_id)}
	if not bool(jail.get("ok", false)): return Runtime.fail("NO_AUTHORITY", "拘押方職責暫停")
	var nations: Dictionary = lab.terrain.site.get("equipment_nations", {})
	var nation: Dictionary = nations.get(str(offer.get("nation_id", "")), {})
	var orders: Variant = lab.site_controller.equipment_orders
	if nation.is_empty() or not nation.has("offices"): return Runtime.fail("NO_NATION")
	var admission: Dictionary = orders.nation_duty_resolve(nation, "nation.admission")
	if not bool(admission.get("ok", false)): return Runtime.fail("NO_AUTHORITY", "戶籍官職責暫停")
	var jail_id := int(jail.decider)
	var admission_id := int(admission.decider)
	if requester_id not in [target_id, jail_id, admission_id]: return Runtime.fail("NO_AUTHORITY", "須由本人、典獄或戶籍官提出")
	if jail_id != requester_id:
		if not governed or not Settlement.prison_governed(lab, str(relation.get("prison_id", ""))) 			or not bool(Settlement.offices(lab).get("duty_ai", false)):
			return Runtime.fail("NEEDS_CONSENT", "拘押方尚未明示接受；職責 AI 關閉時不能代其同意")
	if admission_id != requester_id and not bool(nation.offices.get("duty_ai", false)):
		return Runtime.fail("NEEDS_CONSENT", "戶籍官尚未明示接受；職責 AI 關閉時不能代其同意")
	var submitted := offer.duplicate(true)
	submitted["consent"] = target_id == requester_id and bool(offer.get("consent", false))
	return adopt(lab, target_id, submitted, jail_id, admission_id)

## Only this proven GD-row/prison path has the R3 assessment policy. Actor and
## Crowd paths retain their prior policy until their own transfer is admitted.
static func prison_policy_supported(lab: Variant, target_id: int) -> bool:
	if lab == null or lab.terrain == null or lab.site_controller == null: return false
	if lab.crowd_site != null and lab.crowd_site.active: return false
	var relation: Dictionary = lab.terrain.site.get("captivity", {}).get(str(target_id), {})
	if int(relation.get("version", 0)) != 3 or not Settlement.prison_governed(lab, str(relation.get("prison_id", ""))): return false
	var person: Dictionary = lab.site_controller.person_actions._person(target_id, false)
	return not person.is_empty() and person.owner is TerrainArmy and int(person.unit) >= 0 and person.owner.garrison_feature_id.is_empty() 		and bool(lab.site_controller.person_actions.prison_slot(target_id).get("ok", false))

## Commit (no fallible step after prepare). Called in the same step as prepare.
static func commit(lab: Variant, prepared: Dictionary) -> Dictionary:
	var site: Dictionary = lab.terrain.site
	var target_id := int(prepared.target_id)
	var relation: Dictionary = prepared.relation
	var source: TerrainArmy = prepared.source
	var body: Dictionary = source.combat_units[source.index_for_identity(target_id)]
	SiteSocial.settle_before_release(body, relation, int(prepared.minute)) # §8.2: complete custody days first.
	var captor_id := int(relation.captor_id)
	site.captivity.erase(str(target_id))
	lab.site_controller.captivity_supply.commit_change(target_id, captor_id, false)
	source.adopt_row_into(prepared.destination, target_id)
	var nations: Dictionary = site.equipment_nations
	for old_id: String in prepared.old_nations:
		nations[old_id].members.erase(target_id)
		if nations[old_id].get("offices") is Dictionary:
			SiteOffices.vacate_unless(nations[old_id].offices, func(holder: int) -> bool: return holder != target_id)
	nations[str(prepared.nation_id)].members.append(target_id)
	if not prepared.corps.is_empty():
		var corps: Dictionary = site.corps.duplicate(true)
		for key: String in prepared.corps: corps.erase(key) # Only corps this person commanded end.
		site["corps"] = corps
	var holder: Variant = prepared.person.get("holder")
	if holder is Dictionary: holder.version = int(holder.get("version", 0)) + 1
	var actions: Variant = lab.site_controller.person_actions
	if actions.equipment_changed.is_valid(): actions.equipment_changed.call(target_id)
	actions.captivity_changed.call(target_id, captor_id, false)
	return Runtime.ok("#%d 已歸降入國 %s（未編入隊、不自動授官）" % [target_id, str(prepared.nation_id)],
		{"person_id": target_id, "team_id": prepared.destination.team_id, "nation_id": prepared.nation_id})

static func adopt(lab: Variant, target_id: int, offer: Dictionary, jail_requester: int, admission_requester: int) -> Dictionary:
	var prepared := prepare(lab, target_id, offer, jail_requester, admission_requester)
	return commit(lab, prepared) if prepared.ok else prepared

## The offer a captor-side AI may make (§6.3 first package): the nation of the
## jail keeper's faction whose head is present, its admission decider, and the
## lowest-ID free team of that faction. {} when no legal offer exists (wait).
static func standing_offer(lab: Variant, relation: Dictionary) -> Dictionary:
	var orders: Variant = lab.site_controller.equipment_orders
	var actions: Variant = lab.site_controller.person_actions
	var faction := int(relation.get("captor_faction", -1))
	var nations: Dictionary = lab.terrain.site.get("equipment_nations", {})
	var keys := nations.keys()
	keys.sort()
	for nation_id: String in keys:
		var nation: Dictionary = nations[nation_id]
		if not nation.has("offices") or orders.nation_head_executor(nation) <= 0: continue
		var head: Dictionary = actions._person(orders.nation_head_executor(nation))
		if head.is_empty() or int(head.faction) != faction: continue
		var admission: Dictionary = orders.nation_duty_resolve(nation, "nation.admission")
		if not bool(admission.ok): continue
		var best: TerrainArmy = null
		for team: TerrainArmy in lab.combat_armies:
			if is_instance_valid(team) and team.combat_enabled and team.has_army() and team.garrison_feature_id.is_empty() and team.faction_id == faction \
				and (best == null or team.team_id < best.team_id): best = team
		if best == null: continue
		return {"nation_id": nation_id, "destination_team_id": best.team_id, "admission_decider": int(admission.decider)}
	return {}
