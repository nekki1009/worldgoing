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
	if target_id == controlled:
		if not bool(offer.get("consent", false)): return Runtime.fail("NEEDS_CONSENT", "受控人物須自行明示接受歸降")
	elif not bool(willing.willing):
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
	var admission := _admission(orders, nation)
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
	var moved := source.adoption_row_check(destination, target_id)
	if not moved.ok: return moved
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
		site.corps = corps
	var holder: Variant = prepared.person.get("holder")
	if holder is Dictionary: holder.version = int(holder.get("version", 0)) + 1
	var actions: Variant = lab.site_controller.person_actions
	if actions.equipment_changed.is_valid(): actions.equipment_changed.call(target_id)
	actions.captivity_changed.call(target_id, captor_id, false)
	return Runtime.ok("#%d 已歸降入國 %s（未編入隊、不自動授官）" % [target_id, str(prepared.nation_id)],
		{"person_id": target_id, "team_id": prepared.destination.team_id, "nation_id": prepared.nation_id})

## nation.admission is a LATER duty: a nation record made before R3 gains its
## vacant 戶籍官 seat on first use (plan 3.2), exactly like the Region nation
## paths do, so the head acts for it instead of the duty being orphaned.
static func _admission(orders: Variant, nation: Dictionary) -> Dictionary:
	if nation.get("offices") is Dictionary and SiteOffices.ensure_catalog(nation.offices, "nation"):
		nation.offices.revision = mini(SiteOffices.MAX_SEQ, int(nation.offices.revision) + 1)
	return orders.nation_duty_resolve(nation, "nation.admission")

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
		var admission := _admission(orders, nation)
		if not bool(admission.ok): continue
		var best: TerrainArmy = null
		for team: TerrainArmy in lab.combat_armies:
			if is_instance_valid(team) and team.combat_enabled and team.has_army() and team.garrison_feature_id.is_empty() and team.faction_id == faction \
				and (best == null or team.team_id < best.team_id): best = team
		if best == null: continue
		return {"nation_id": nation_id, "destination_team_id": best.team_id, "admission_decider": int(admission.decider)}
	return {}
