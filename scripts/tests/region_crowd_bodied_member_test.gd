extends SceneTree
## Bodied roster members S1 (design bodied_roster_members_design_20261103). A live friendly crowd team of seven (formal
## captain, two deploy cadre, four soldiers) and a three-person enemy team. Checks:
## - CrowdSite.bodied_ids and the live bodied set name exactly the formal commanders, cadre and officers of every team
##   (rows 0-2 of a deployed team), plus anyone the native formation refs name; never the controlled actor body;
## - display build: each bodied person has one presenter node (CrowdBody_<id>) and native kit -1, while its atlas kit stays
##   in _kit_ids as the fallback; headless: the bookkeeping only (no node, kits unchanged);
## - a soldier promoted to officer gains a body, and loses it again when demoted (no orphan node, atlas kit back);
## - save and load reproduce the same bodied set (nothing about bodies is saved);
## - a cadre split and then a whole-team departure release people and leave no orphan body.
## Display-only assertions (presenter nodes, kit -1) run only when DisplayServer is not headless ("visual" mode).
## Run only with: --crowd --crowd-test <fresh_run_id>
## Output: REGION_CROWD_BODIED_MEMBER_PASS on success; quit(1) on any failure.

const DT := 1.0 / 30.0
const CrowdSiteScript = preload("res://scripts/terrain_lab/crowd_site.gd")

var checks := 0
var lab: TerrainLab
var display := false

func _initialize() -> void:
	create_timer(300.0).timeout.connect(func() -> void: _fail("300-second deadline"))
	_run.call_deferred()

func _fail(message: String, detail: Variant = null) -> void:
	printerr("REGION_CROWD_BODIED_MEMBER_FAIL: ", message, " ", str(detail))
	quit(1)

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("REGION_CROWD_BODIED_MEMBER OK ", checks, ": ", message)
		return true
	_fail(message, detail)
	return false

func _side(count: int, faction: int) -> Dictionary:
	var parsed: Dictionary = lab._trial_side_settings({"friendly_count": count, "friendly_training": 0,
		"friendly_female_percent": 0, "friendly_attack": false, "friendly_ai_enabled": false}, "friendly")
	if not _check(parsed.ok, "original side settings accepted", parsed): return {}
	var side: Dictionary = parsed.side
	side.faction = faction
	return side

func _sorted(values: Variant) -> Array[int]:
	var result: Array[int] = []
	for value: Variant in values: result.append(int(value))
	result.sort()
	return result

## Deploy rule: rows 0-2 of every crowd roster are officers (0 formal captain, 1-2 officer_service).
func _deploy_cadre(crowd: Variant) -> Array[int]:
	var result: Array[int] = []
	for roster: Dictionary in crowd.rosters:
		for index in range(mini(3, roster.units.size())):
			var identity := int(roster.units[index].person_id)
			if crowd.contains_person(identity): result.append(identity)
	result.sort()
	return result

## Every person a live roster's native formation refs name as a commander or officer.
func _native_named(crowd: Variant) -> Array[int]:
	var result: Array[int] = []
	for roster: Dictionary in crowd.rosters:
		var refs: PackedInt64Array = crowd.crowd.formation_refs(int(roster.crowd_formation))
		for at in range(refs.size()):
			if at == 3 or int(refs[at]) <= 0: continue
			if crowd.contains_person(int(refs[at])) and not result.has(int(refs[at])): result.append(int(refs[at]))
	return result

## Live presenter nodes in the lab, not queued for deletion.
func _live_body_nodes() -> int:
	var count := 0
	for child: Node in lab.get_children():
		if str(child.name).begins_with("CrowdBody_") and not child.is_queued_for_deletion(): count += 1
	return count

## A copy of `base` with another face or hair that the editor accepts but the soldier atlas cannot draw; {} if none.
func _created_look(base: Dictionary) -> Dictionary:
	for slot: Dictionary in HumanCharacter3DEditor.PART_SLOTS:
		if not str(slot.id) in ["face", "hair"]: continue
		var options: Array = HumanCharacter3DEditor.HAIR_OPTIONS[int(base.body)] if slot.id == &"hair" else slot.options
		for option: Dictionary in options:
			for dyed: bool in [false, true]:
				var look: Dictionary = base.duplicate(true)
				look.parts[str(slot.id)] = str(option.id)
				if dyed:
					look.hair_dyed = true
					look.hair_dye = "8a3324ff"
				if look != base and HumanCharacter3DEditor.valid_appearance(look) and CrowdSiteScript.atlas_cannot_draw(look): return look
	return {}

## Renders until every bodied person has its presenter (display) or once (headless); bodies are created a few per frame.
func _settle(crowd: Variant) -> void:
	for frame in range(12):
		crowd.render(DT)
		await process_frame
		if not display or crowd._bodies.size() + crowd._body_failed.size() >= crowd._body_set.size(): break
	await process_frame

## The bodied set, nodes and kits match `expected` exactly.
func _bodies_match(crowd: Variant, expected: Array[int], phase: String) -> bool:
	if not _check(_sorted(crowd.bodied_people()) == expected, phase + ": the bodied set is exactly the expected people", [_sorted(crowd.bodied_people()), expected]): return false
	var controlled := int(lab.controlled_person_id())
	if not _check(not crowd._body_set.has(controlled) and crowd._actors.has(controlled), phase + ": the controlled actor body is never a bodied roster member"): return false
	var kits: PackedInt32Array = crowd.render_kit_ids()
	if not _check(kits.size() == crowd._kit_ids.size(), phase + ": one submitted kit per soldier"): return false
	for identity: int in expected:
		var index := int(crowd._index_by_id[identity])
		if crowd._no_atlas.has(identity):
			if not _check(int(crowd._kit_ids[index]) == -1, phase + ": a created look has no atlas kit and no substitute (kit -1)", identity): return false
		elif not _check(int(crowd._kit_ids[index]) >= 0, phase + ": a bodied person keeps its atlas kit as the fallback", identity): return false
		if display:
			var body: Variant = crowd._bodies.get(identity)
			if not _check(is_instance_valid(body) and body.is_inside_tree() and body.get_parent() == lab and body.editor != null, phase + ": a display build gives the bodied person one presenter", identity): return false
			if not _check(kits[index] == -1, phase + ": native draws no atlas sprite for a bodied person (kit -1)", identity): return false
		elif not _check(kits[index] == crowd._kit_ids[index], phase + ": headless keeps the atlas kit", identity): return false
	if display:
		if not _check(_sorted(crowd._bodies.keys()) == expected and _live_body_nodes() == expected.size(), phase + ": no orphan or missing presenter node", [_sorted(crowd._bodies.keys()), _live_body_nodes()]): return false
	elif not _check(crowd._bodies.is_empty() and _live_body_nodes() == 0, phase + ": headless creates no presenter node"): return false
	for identity: Variant in crowd._index_by_id.keys():
		if expected.has(int(identity)): continue
		var index := int(crowd._index_by_id[identity])
		if not _check(kits[index] == crowd._kit_ids[index], phase + ": an unbodied person keeps its own kit", identity): return false
	return true

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if not _check(args.has("--crowd") and args.has("--crowd-test"), "native startup and a fresh --crowd-test run id required"): return
	display = CrowdSiteScript.bodies_display()
	print("REGION_CROWD_BODIED_MEMBER mode: ", "display" if display else "headless")
	var packed := load("res://scenes/terrain_lab/TerrainLab.tscn") as PackedScene
	if not _check(packed != null, "formal TerrainLab scene exists"): return
	lab = packed.instantiate() as TerrainLab
	if not _check(lab != null, "formal TerrainLab instance exists"): return
	lab.pause_when_unfocused = false
	lab.movement_input_enabled = false
	root.add_child(lab)
	current_scene = lab
	lab.set_process(false)
	if not _check(lab.character != null and lab.site_controller != null, "formal scene has its player body and Controller"): return
	lab.character.set_process(false)
	lab.site_controller._auto_save_blocked = true
	if not _check(lab.crowd_site != null and not lab.crowd_site.active, "formal scene has an inactive CrowdSite"): return
	if not _check(lab.terrain != null and lab.terrain.spawn_cell != Vector2i(-1, -1), "scene has a legal spawn cell"): return
	var centre: Vector2i = lab.terrain.spawn_cell
	var friendly_cells: Array[Vector2i] = []
	for offset: int in range(-3, 4): friendly_cells.append(centre + Vector2i(offset, 3))
	var enemy_cells: Array[Vector2i] = [centre + Vector2i(-1, -40), centre + Vector2i(0, -40), centre + Vector2i(1, -40)]
	var sides: Array[Dictionary] = [_side(friendly_cells.size(), 0), _side(enemy_cells.size(), 1)]
	if not _check(sides[0].size() > 0 and sides[1].size() > 0, "both original sides exist"): return
	var entered: Dictionary = lab.crowd_site.deploy(sides, [friendly_cells, enemy_cells])
	if not _check(entered.get("ok", false) and lab.crowd_site.active, "two-faction native crowd activates", entered): return
	var crowd: Variant = lab.crowd_site
	await _settle(crowd)

	# 1. Deploy: the formal commanders and cadre of both teams are bodied; ordinary soldiers keep the atlas.
	var roster: Dictionary = {}
	for candidate: Dictionary in crowd.rosters:
		if int(candidate.faction_id) == 0: roster = candidate
	if not _check(not roster.is_empty() and roster.units.size() == 7 and int(roster.formal_commander) == 0, "the friendly crowd team has a formal captain and seven rows"): return
	var cadre := _deploy_cadre(crowd)
	if not _check(cadre.size() == 6, "both teams deploy three cadre each", cadre): return
	for identity: int in _native_named(crowd):
		if not _check(cadre.has(identity), "every native commander or officer ref names a deploy cadre", identity): return
	var pure: Dictionary = CrowdSiteScript.bodied_ids(crowd.rosters, int(lab.controlled_person_id()), crowd.crowd)
	var pure_roster: Array[int] = []
	for identity: Variant in pure:
		if crowd.contains_person(int(identity)) and not crowd._actors.has(int(identity)): pure_roster.append(int(identity))
	pure_roster.sort()
	if not _check(pure_roster == cadre and pure.keys()[0] == int(lab.controlled_person_id()), "the pure bodied_ids rule names the controlled person first and the cadre", pure.keys()): return
	if not _bodies_match(crowd, cadre, "deploy"): return

	# 2. Promotion and demotion: an ordinary soldier gains a body as an officer, and loses it as a soldier again.
	var soldier := int(roster.units[5].person_id)
	var soldier_index := int(crowd._index_by_id[soldier])
	var atlas_kit := int(crowd._kit_ids[soldier_index])
	if not _check(atlas_kit >= 0 and not crowd._body_set.has(soldier), "an ordinary soldier is drawn by the atlas"): return
	var promoted: Dictionary = crowd.native_set_military_role(soldier, "officer")
	if not _check(promoted.ok and str(roster.units[5].military_role) == "officer", "the soldier is promoted to officer", promoted): return
	await _settle(crowd)
	var with_soldier: Array[int] = []
	with_soldier.append_array(cadre)
	with_soldier.append(soldier)
	with_soldier.sort()
	if not _bodies_match(crowd, with_soldier, "promotion"): return
	var demoted: Dictionary = crowd.native_set_military_role(soldier, "soldier")
	if not _check(demoted.ok, "the officer is demoted back to soldier", demoted): return
	await _settle(crowd)
	if not _bodies_match(crowd, cadre, "demotion"): return
	if not _check(int(crowd.render_kit_ids()[soldier_index]) == atlas_kit, "the demoted soldier is drawn by his atlas kit again"): return

	# 2b. S2 sticky rule: an ordinary soldier given a created look (one the atlas cannot draw) is admitted, bodied, and has
	# kit -1; promoted and demoted again, he keeps the body because no atlas kit can draw him.
	var created_id := int(roster.units[6].person_id)
	var created_index := int(crowd._index_by_id[created_id])
	var record: Dictionary = crowd._records[created_id]
	var look: Dictionary = _created_look(record.appearance)
	if not _check(not look.is_empty(), "a valid created face/hair look the atlas cannot draw exists", record.appearance): return
	var guard: Dictionary = crowd.equipment_recipe_guard(created_id, look)
	if not _check(guard.ok, "the recipe guard admits a created look instead of MISSING_ASSET", guard): return
	record.appearance = look
	crowd.equipment_changed(created_id)
	if not _check(crowd.last_event_error.is_empty() or str(crowd.last_event_error.get("code", "")) != "MISSING_ASSET", "the created look is not refused", crowd.last_event_error): return
	await _settle(crowd)
	var unatlased: Array[int] = crowd.unatlased_people()
	if not _check(unatlased.size() == 1 and unatlased[0] == created_id, "the created look is recorded as unatlased", unatlased): return
	var with_created: Array[int] = []
	with_created.append_array(cadre)
	with_created.append(created_id)
	with_created.sort()
	if not _bodies_match(crowd, with_created, "created look"): return
	if not _check(crowd.native_set_military_role(created_id, "officer").ok, "the created-look soldier is promoted"): return
	await _settle(crowd)
	if not _check(crowd.native_set_military_role(created_id, "soldier").ok, "and demoted again"): return
	await _settle(crowd)
	if not _bodies_match(crowd, with_created, "sticky demotion"): return
	if not _check(int(crowd.render_kit_ids()[created_index]) == -1, "the demoted created look keeps kit -1 (no substitute)"): return
	cadre = with_created # The sticky person stays bodied through save/load and the split below.

	# 3. Save and load: the same bodied set comes back from the rosters, control and native refs alone.
	var saved: Dictionary = lab.site_controller.save_to(lab.site_controller.save_path)
	if not _check(saved.get("ok", false) == true, "the crowd Site saves", saved): return
	var section: Dictionary = lab.terrain.site.get("crowd", {})
	for key: Variant in section.keys():
		if not _check(not str(key).contains("bod"), "the crowd save section carries no body field", key): return
	var loaded: Dictionary = lab.site_controller.load_from(lab.site_controller.save_path)
	if not _check(loaded.get("ok", false) == true, "the crowd Site loads", loaded): return
	crowd = lab.crowd_site
	if not _check(crowd != null and crowd.active, "the loaded crowd is active"): return
	await _settle(crowd)
	if not _bodies_match(crowd, cadre, "load"): return
	roster = {}
	for candidate: Dictionary in crowd.rosters:
		if int(candidate.faction_id) == 0: roster = candidate
	if not _check(not roster.is_empty() and roster.units.size() == 7, "the loaded friendly roster keeps seven rows"): return

	# 4. Cadre split: the cadre (row 1) leads one ordinary member out; both leave no body behind.
	var team_id := int(roster.team_id)
	var leader := int(roster.units[1].person_id)
	var member := int(roster.units[5].person_id)
	var plan: Dictionary = crowd.split_departure_plan(leader, [member])
	if not _check(plan.get("ok", false) == true, "the cadre's sub-party passes the split plan", plan): return
	var split: Dictionary = crowd.split_departure_release(plan, team_id + 1000)
	if not _check(split.get("ok", false) == true and int(split.released) == 2, "the sub-party is released", split): return
	await _settle(crowd)
	var after_split: Array[int] = []
	for identity: int in cadre:
		if identity != leader: after_split.append(identity)
	if not _check(not crowd.contains_person(leader) and not crowd._body_set.has(leader) and not crowd._bodies.has(leader), "the departed cadre has no body and no record on the Site"): return
	if not _bodies_match(crowd, after_split, "split"): return

	# 5. Whole-team departure: the captain's team leaves; only the enemy cadre stay bodied.
	var captain := int(roster.units[int(roster.formal_commander)].person_id)
	var departure: Dictionary = crowd.departure_plan(captain)
	if not _check(departure.get("ok", false) == true, "the remaining friendly team passes the departure plan", departure): return
	var left: Dictionary = crowd.departure_release(departure)
	if not _check(left.get("ok", false) == true and int(left.released) == 5, "the remaining friendly team is released", left): return
	await _settle(crowd)
	var enemy_only: Array[int] = []
	for identity: int in after_split:
		if crowd.contains_person(identity): enemy_only.append(identity)
	if not _check(enemy_only.size() == 3 and not enemy_only.has(captain), "only the enemy cadre remain on the Site", enemy_only): return
	if not _bodies_match(crowd, enemy_only, "departure"): return

	lab.queue_free()
	await process_frame
	print("REGION_CROWD_BODIED_MEMBER_PASS (", "display" if display else "headless", "): ", checks, " checks; cadre and commanders are bodied, promotion and demotion follow, save/load reproduces the set, split and departure leave no orphan body")
	quit(0)
