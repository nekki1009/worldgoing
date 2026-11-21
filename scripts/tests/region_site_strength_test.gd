extends SceneTree
## 跨 Site 兵力情報 (RegionSiteStrength). A world opens with a founded faction (the player captains his cadres) on a live
## crowd Site. One cadre stands apart as his own team (an officer of the player's faction), one as an armed neutral, one
## as a neutral civilian. Checks:
## - record: every officer present records this Site's strength: the armed neutral counts, the civilian does not; the
##   receipt passes the ledger rules, follows the officer's stable ref, and an unchanged second record adds nothing;
## - a strength receipt the officer carries about another Site is told in person to the faction's office holder here
##   (a "report" addressed to him), once; the holder's scoped intel on this crowd Site then offers that Site as a dispatch
##   target with its power; this Site itself is never a target.
## Output: REGION_SITE_STRENGTH_PASS on success; quit(1) on any failure or the deadline.

const SITE := "res://scenes/terrain_lab/TerrainLab.tscn"
const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
const Strength = preload("res://scripts/region_lab/region_site_strength.gd")
const RegionAI = preload("res://scripts/region_lab/region_gameplay_ai.gd")
const START := Vector2i(1170, 13252)

var checks := 0
var _finished := false

func _initialize() -> void:
	create_timer(300.0).timeout.connect(func() -> void: _fail("300-second deadline"))
	_run.call_deferred()

func _fail(message: String, detail: Variant = null) -> void:
	if _finished: return
	_finished = true
	printerr("REGION_SITE_STRENGTH_FAIL: ", message, " ", str(detail))
	quit(1)

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("REGION_SITE_STRENGTH OK ", checks, ": ", message)
		return true
	_fail(message, detail)
	return false

func _team_of(lab: TerrainLab, person: int) -> Dictionary:
	for team: Dictionary in lab.crowd_site.teams:
		if not bool(team.get("departed", false)) and team.get("person_ids", []).has(person): return team
	return {}

func _run() -> void:
	if not _check(RegionEntry.request_new_world(START, {}, "兵力情報世界", "", RegionData.DEFAULT_MANIFEST, {"mode": "found", "name": "甲國"}), "a world is requested", RegionEntry.menu_message): return
	change_scene_to_file(SITE)
	var lab: TerrainLab = null
	for _frame: int in range(900):
		await process_frame
		if _finished: return
		var scene := current_scene as TerrainLab
		if scene != null and scene.site_controller != null and scene.site_controller.region_slot != null and scene.site_controller._boot_request.is_empty() and scene.crowd_site != null and scene.crowd_site.active:
			lab = scene
			break
	if not _check(lab != null, "the new world opens", RegionEntry.menu_message): return
	for _frame: int in range(5): await process_frame
	var slot: RegionSaveSlot = lab.site_controller.region_slot
	var player := int(lab.controlled_person_id())
	var own := int(_team_of(lab, player).faction)
	var cadres: Array[int] = []
	for person: Variant in _team_of(lab, player).person_ids:
		if int(person) != player: cadres.append(int(person))
	cadres.sort()
	if not _check(cadres.size() >= 3, "the player has three cadres", cadres): return
	var officer := cadres[0]
	var armed := cadres[1]
	var civilian := cadres[2]
	if not _check(lab.crowd_site.detach_to_new_team(officer, own).ok, "an officer of the player's faction captains his own team"): return
	if not _check(lab.crowd_site.detach_to_new_team(armed, RegionFactionQuery.NEUTRAL_FACTION_ID).ok, "an armed neutral stands on the Site"): return
	if not _check(lab.crowd_site.detach_to_new_team(civilian, RegionFactionQuery.NEUTRAL_FACTION_ID).ok and lab.crowd_site.native_set_military_role(civilian, "civilian").ok, "a neutral civilian stands on the Site"): return
	# A test-only nation (never saved) whose head is the player.
	if not lab.terrain.site.has("equipment_nations"): lab.terrain.site["equipment_nations"] = {}
	lab.terrain.site.equipment_nations["strength_test_nation"] = {"members": [player, officer], "standards": {}, "offices": SiteOffices.default_offices("nation", player, true)}
	var holders: Array[int] = Strength._holders(lab)
	if not _check(not holders.is_empty() and not holders.has(officer), "the faction has office holders; the officer is not one", holders): return
	var holder := holders[0]
	# The officer has travelled (a stable ref); the player has not (told by id and scope). Test-only, never saved.
	var identity_refs: Dictionary = lab.terrain.site.get("travel_identity", {}).get("refs", {}).get("person", {})
	var had_ref := identity_refs.has(str(officer))
	if not had_ref:
		if not lab.terrain.site.has("travel_identity"): lab.terrain.site["travel_identity"] = {"refs": {}}
		if not lab.terrain.site.travel_identity.has("refs"): lab.terrain.site.travel_identity["refs"] = {}
		if not lab.terrain.site.travel_identity.refs.has("person"): lab.terrain.site.travel_identity.refs["person"] = {}
		lab.terrain.site.travel_identity.refs.person[str(officer)] = {"type": "person", "namespace": "strength_test", "lineage": officer}
	var scope := str(lab.terrain.site.id)
	var now := float(slot.control.logical_game_seconds)

	var recorded: Dictionary = Strength.record(slot, lab)
	if not _check(recorded.ok and int(recorded.observed) == 1, "the officer with a stable ref records this Site (one without is skipped)", [recorded, Strength.officers(lab), Strength.people(lab).size(), lab.team_owners().size(),
		lab.team_owners().map(func(t: Variant) -> Array: return [t.team_id, t.combat_enabled, Strength.indices(t).size(), Strength.indices(t).filter(func(i: int) -> bool: return t.combat_can_act(i)).size()]),
		RegionAI.person_ref(lab.terrain.site, officer), RegionAI.person_ref(lab.terrain.site, player)]): return
	var reference := RegionAI.person_ref(lab.terrain.site, officer)
	var mine: Dictionary = RegionAI.view(slot.region_registry(), officer, now, "elsewhere", reference).get(scope, {})
	if not _check(mine.get("observation_kind") == Strength.KIND, "the receipt follows the officer by his stable ref, not by scope", mine): return
	var neutral := str(RegionFactionQuery.NEUTRAL_FACTION_ID)
	if not _check(int(mine.value.factions.get(neutral, 0)) >= 1 and int(mine.value.power) == int(mine.value.factions.values().reduce(func(a: int, b: int) -> int: return a + b, 0)), "the armed neutral counts", mine.value): return
	var seen_civilian := Strength.seen_by(lab, own, Strength.people(lab))
	var people := Strength.people(lab)
	var civilian_row: Array = people.filter(func(p: Dictionary) -> bool: return int(p.id) == civilian)
	if not _check(civilian_row.size() == 1 and not bool(civilian_row[0].armed) and int(seen_civilian.power) == int(mine.value.power), "the civilian is not armed and not counted", seen_civilian): return
	var again: Dictionary = Strength.record(slot, lab)
	if not _check(again.ok and int(again.observed) == 0, "an unchanged second record adds nothing", again): return

	# He carries what he saw at another Site.
	var elsewhere := str(slot.pin.atlas_id) + ":1:0"
	if elsewhere == scope: elsewhere = str(slot.pin.atlas_id) + ":2:0"
	var carried := {"id": "test-strength:" + elsewhere, "source": "site_observation", "observation_kind": Strength.KIND, "observer": officer, "receiver": officer,
		"observer_scope": elsewhere, "receiver_scope": elsewhere, "object_scope": elsewhere, "observer_ref": reference.duplicate(true), "receiver_ref": reference.duplicate(true),
		"object": elsewhere, "value": {"power": 3, "factions": {neutral: 3}}, "game_time": now, "expires_at": now + 86400.0, "confidence": 1.0}
	if not _check(RegionAI.observe(slot.region_registry(), carried).ok, "the officer carries a strength receipt about another Site"): return
	var told: Dictionary = Strength.record(slot, lab)
	if not _check(told.ok and int(told.told) >= 1, "he tells the office holder in person", told): return
	var holder_ref := RegionAI.person_ref(lab.terrain.site, holder)
	var heard: Dictionary = RegionAI.view(slot.region_registry(), holder, now, scope, holder_ref).get(elsewhere, {})
	if not _check(str(heard.get("source", "")) == "report" and int(heard.get("receiver", -1)) == holder and int(heard.value.power) == 3, "the holder now knows that Site's strength", heard): return
	if not _check(int(Strength.record(slot, lab).told) == 0, "he is told once"): return
	var intel: Dictionary = slot.scoped_region_intel(lab, now)
	var targets: Array[Dictionary] = RegionAI.dispatch_known_targets(lab, intel, holder, now)
	var found: Array = targets.filter(func(t: Dictionary) -> bool: return str(t.site_id) == elsewhere)
	if not _check(found.size() == 1 and is_equal_approx(float(found[0].power), 3.0), "the holder's scoped intel on this crowd Site offers it as a dispatch target", targets): return
	if not _check(targets.filter(func(t: Dictionary) -> bool: return str(t.site_id) == scope).is_empty(), "this Site itself is never a target"): return
	lab.terrain.site.equipment_nations.erase("strength_test_nation")
	if not had_ref: lab.terrain.site.travel_identity.refs.person.erase(str(officer))
	_finished = true
	print("REGION_SITE_STRENGTH_PASS: ", checks, " checks; officers record and tell Site strength")
	quit(0)
