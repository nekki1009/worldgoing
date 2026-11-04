extends RefCounted
## Joining a faction in person (Nekki 2026-11-04/05, plan "勢力爵位與封地規劃", step 2).
## The neutral player captain meets an official of another faction in the same Site: the faction head, or a noble of
## viscount and above. The official decides by the agreed acceptance score; each cadre decides by the follow score.
## Accepted: refusing cadres leave on the spot as captains of their own one-person neutral teams, the rest of the team is
## relabelled to the faction, and the player swears fealty to the official (an untitled "none" peerage record).
## Refused outright while the team is routed or a fight is going on near the player. No remote joining.
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const DutyAI = preload("res://scripts/terrain_lab/site_duty_ai.gd")
const CrowdSite = preload("res://scripts/terrain_lab/crowd_site.gd")
## Cells around the player inside which any fighting person refuses a join.
const COMBAT_NEARBY_CELLS := 24.0

static func _world_ref(controller: Variant, person_id: int) -> Dictionary:
	var slot: Variant = controller.region_slot
	var resolved: Dictionary = slot.resolve_person_reference(slot.person_reference(person_id))
	if not resolved.get("ok", false): return {}
	if RegionFactionQuery.ref_valid(resolved.get("typed_ref", {}), "person"): return resolved.typed_ref
	if resolved.get("status") == "current": return RegionPeerage.world_person_ref(str(slot.pin.world_instance_id), person_id)
	return {}

## The registry with the official's record; a faction head without one (founded before peerage) is crowned first.
static func _official_registry(registry: Dictionary, faction: int, official_ref: Dictionary, now: float) -> Dictionary:
	if not RegionPeerage.record_of(registry, official_ref).is_empty(): return {"ok": true, "registry": registry}
	var head: Dictionary = RegionPeerage.head_of(registry, faction)
	if head.ok and RegionPeerage.same_ref(head.get("person_ref"), official_ref): return RegionPeerage.crown_founder(registry, faction, official_ref, now)
	return Runtime.fail("NOT_ACCEPTOR", "對方不是勢力首長，也沒有子爵以上的爵位，不能收投靠")

static func _fight_nearby(lab: Variant, centre: Vector2) -> bool:
	var host: Variant = lab.crowd_site
	for identity: Variant in host._index_by_id.keys():
		var target: Dictionary = host.combat_target(int(identity))
		if target.is_empty() or Vector2(target.position).distance_to(centre) > COMBAT_NEARBY_CELLS * CrowdSite.CELL: continue
		if host.person_fighting(int(identity)): return true
	return false

static func _faction_people(lab: Variant, faction: int) -> int:
	var count := 0
	for team: Dictionary in lab.crowd_site.teams:
		if int(team.get("faction", -1)) == faction and not bool(team.get("departed", false)): count += team.get("person_ids", []).size()
	return count

## Read-only preview: {accepted, score, cadres: [{id, score, follows}]}, or a refusal.
static func preview(controller: Variant, official_id: int) -> Dictionary:
	var lab: Variant = controller.lab
	if controller.region_slot == null: return Runtime.fail("NO_REGION_SLOT", "須在台灣地圖世界中才能投靠")
	if lab.crowd_site == null or not lab.crowd_site.active: return Runtime.fail("UNSUPPORTED", "此地點不是群眾 Site")
	var player: int = lab.controlled_person_id()
	var mine: Dictionary = lab._original_person_target(player)
	var theirs: Dictionary = lab._original_person_target(official_id)
	if mine.is_empty() or int(mine.get("unit", -1)) < 0: return Runtime.fail("NO_TARGET", "你不在自己的隊伍中")
	if theirs.is_empty(): return Runtime.fail("NO_TARGET", "對方不在此地；投靠須當面見到官員")
	if official_id == player: return Runtime.fail("INVALID", "不能向自己投靠")
	var team_id := int(mine.owner.team_id)
	var roster: Dictionary = lab.crowd_site.native_roster(team_id)
	if roster.is_empty() or not lab.crowd_site.contains_person(player): return Runtime.fail("UNSUPPORTED", "你的隊伍不在群眾名冊")
	if int(mine.owner.faction_id) != RegionFactionQuery.NEUTRAL_FACTION_ID: return Runtime.fail("NOT_NEUTRAL", "只有中立隊伍能投靠；離開勢力是另一個流程")
	if CrowdSite._roster_index_for_person(roster, player) != int(roster.get("formal_commander", -1)): return Runtime.fail("CAPTAIN_REQUIRED", "須由正式隊長本人帶全隊投靠")
	var faction := int(theirs.owner.faction_id)
	if faction == RegionFactionQuery.NEUTRAL_FACTION_ID or faction < 0: return Runtime.fail("NO_FACTION", "對方不屬於任何勢力")
	var now := float(controller.region_slot.control.logical_game_seconds)
	var registry: Dictionary = controller.region_slot.control.get("faction_registry", {})
	if not RegionFactionQuery.active(registry, faction).ok: return Runtime.fail("NO_FACTION", "對方的勢力已不存在")
	var official_ref := _world_ref(controller, official_id)
	var player_ref := _world_ref(controller, player)
	if official_ref.is_empty() or player_ref.is_empty(): return Runtime.fail("NO_PERSON_REF", "人物沒有世界身分，無法記錄效忠")
	var titled: Dictionary = _official_registry(registry, faction, official_ref, now)
	if not titled.ok: return titled
	if not RegionPeerage.may_hold(RegionPeerage.record_of(titled.registry, official_ref), "none"): return Runtime.fail("NOT_ACCEPTOR", "只有首長或子爵以上的貴族能收投靠")
	var morale: Dictionary = lab.crowd_site.team_morale_of(int(mine.owner.formation_index))
	if bool(morale.get("routed", false)): return Runtime.fail("ROUTED", "隊伍潰退中，不能投靠")
	if _fight_nearby(lab, Vector2(mine.position)): return Runtime.fail("IN_COMBAT", "附近正在交戰，不能投靠")
	var player_mind: Dictionary = DutyAI.personality(player, null, lab)
	var official_mind: Dictionary = DutyAI.personality(official_id, null, lab)
	var score := RegionPeerage.accept_score(official_mind, player_mind, roster.units.size(), _faction_people(lab, faction))
	var cadres: Array = []
	for at in range(roster.units.size()):
		var identity := int(roster.units[at].person_id)
		if identity == player or not CrowdSite.cadre_index(roster, at): continue
		var follow := RegionPeerage.follow_score(DutyAI.personality(identity, null, lab), official_mind, player_mind)
		cadres.append({"id": identity, "score": follow, "follows": follow >= RegionPeerage.FOLLOW_THRESHOLD})
	return Runtime.ok("", {"accepted": score >= RegionPeerage.ACCEPT_THRESHOLD, "score": score, "cadres": cadres, "faction_id": faction,
		"team_id": team_id, "official_ref": official_ref, "player_ref": player_ref, "registry": titled.registry, "now": now})

## Ask to join. Nothing changes on a refusal; an accepted join is saved with a Region checkpoint.
static func join(controller: Variant, official_id: int) -> Dictionary:
	var seen: Dictionary = preview(controller, official_id)
	if not seen.ok: return seen
	if not seen.accepted: return Runtime.fail("REFUSED", "對方拒絕收你（接受分 %.1f，需 %.0f）" % [seen.score, RegionPeerage.ACCEPT_THRESHOLD])
	var sworn: Dictionary = RegionPeerage.swear(seen.registry, seen.official_ref, seen.player_ref, float(seen.now))
	if not sworn.ok: return sworn
	var lab: Variant = controller.lab
	var left: Array = []
	for cadre: Dictionary in seen.cadres:
		if cadre.follows: continue
		var detached: Dictionary = lab.crowd_site.detach_to_new_team(int(cadre.id), RegionFactionQuery.NEUTRAL_FACTION_ID)
		if not detached.ok: return Runtime.fail(str(detached.get("code", "DETACH_FAILED")), "幹部 #%d 離隊失敗：%s（已離隊 %d 人）" % [int(cadre.id), str(detached.get("message", "")), left.size()])
		left.append(int(cadre.id))
	var joined: Dictionary = lab.relabel_team_faction(int(seen.team_id), int(seen.faction_id))
	if not joined.ok: return joined
	var captured: Dictionary = controller.capture_region_checkpoint("region_checkpoint", true)
	var committed: Dictionary = controller.region_slot.checkpoint_region_site(lab.terrain, captured.context, captured.owners, sworn.registry, false, captured) if captured.ok else captured
	if not committed.ok:
		lab.relabel_team_faction(int(seen.team_id), RegionFactionQuery.NEUTRAL_FACTION_ID)
		return committed
	var message := "已投靠，全隊改屬此勢力" if left.is_empty() else "已投靠；%d 名幹部不願跟隨，已自成中立隊" % left.size()
	return Runtime.ok(message, {"faction_id": int(seen.faction_id), "left_cadres": left, "score": seen.score})
