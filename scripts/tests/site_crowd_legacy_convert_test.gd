extends SceneTree
## Legacy grid Site save -> live crowd on load (CrowdSite.convert_existing).
## Run: -- --crowd --crowd-test <fresh-run-id>
## Phase 1 makes grid teams with crowd off and saves them. Phase 2 (crowd off) and phase 3 (crowd requested)
## load that same file. Phase 2 also drives the battle-in-progress refusal on the grid Site.
## Ship-journey refusal is not fixtured here: it needs a ship with a begun journey. The guard is in convert_existing.
const Crowd = preload("res://scripts/terrain_lab/crowd_site.gd")
const POSITION_TOLERANCE := 0.01
var checks := 0
var save_path := ""
var marked_path := ""

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, label: String, details: Variant = null) -> bool:
	checks += 1
	print("LEGACY ", "OK " if ok else "FAIL ", checks, ": ", label, " ", details)
	if not ok:
		printerr("GATE FAIL: ", label)
		quit(2)
	return ok

func _run() -> void:
	create_timer(300.0).timeout.connect(func() -> void: quit(3))
	var args := OS.get_cmdline_user_args()
	if not check(args.has("--crowd") and args.has("--crowd-test"), "run as: -- --crowd --crowd-test <fresh-run-id>"): return

	# Phase 1: grid teams made with crowd off, then saved. The save has no crowd section.
	var grid_lab := _new_lab(false)
	var setups: Array[Dictionary] = [{"faction": 0, "count": 6, "entry": "west", "attack": false, "ai_enabled": false},
		{"faction": 1, "count": 4, "entry": "east", "attack": false, "ai_enabled": false}]
	var deployed: Dictionary = grid_lab.deploy_trial_armies(setups)
	if not check(deployed.ok, "grid teams deployed with crowd off", deployed): return
	var expected := _grid_census(grid_lab)
	check(expected.teams.size() == 2 and expected.people.size() >= 10, "grid census has two teams and at least ten people", expected.people.size())
	for team: TerrainArmy in grid_lab.combat_armies:
		if team.combat_enabled and team.has_army():
			check(team.pending_cadre().is_empty(), "no pending cadre before save", team.team_id)
	# Ordinary save from this version (carries crowd_era) and a legacy copy of it without the marker.
	marked_path = grid_lab.site_controller.save_root.path_join("ordinary_grid.json")
	var saved: Dictionary = grid_lab.site_controller.save_to(marked_path)
	if not check(saved.ok, "grid save written by this version with crowd off", saved): return
	check(not grid_lab.terrain.site.has("crowd"), "grid save has no crowd section")
	save_path = grid_lab.site_controller.save_root.path_join("legacy_grid.json")
	check(_copy_without_era(marked_path, save_path), "legacy copy without crowd_era marker written")
	var digest := FileAccess.get_sha256(save_path)
	var marked_digest := FileAccess.get_sha256(marked_path)
	check(not digest.is_empty() and not marked_digest.is_empty(), "save digests recorded")
	await _discard(grid_lab)

	# Phase 2: crowd off. The loaded Site stays grid. Then the battle refusal and the successful conversion.
	var off_lab := _new_lab(false)
	var loaded_off: Dictionary = off_lab.site_controller.load_from(save_path)
	if not check(loaded_off.ok, "grid save loads with crowd off", loaded_off): return
	check(not (off_lab.crowd_site != null and off_lab.crowd_site.active), "crowd off: loaded Site stays grid")
	check(_diff(_grid_census(off_lab), expected) == "", "crowd off: grid census equals saved census", _diff(_grid_census(off_lab), expected))

	var convert_node := _attach_crowd(off_lab)
	off_lab.terrain.site["combat_left"] = 5.0
	var refused: Dictionary = convert_node.convert_existing()
	check(not refused.ok and str(refused.get("code", "")) == "BATTLE_IN_PROGRESS", "battle in progress refuses conversion", refused.get("code", ""))
	check(not convert_node.active, "refusal leaves crowd inactive")
	check(_diff(_grid_census(off_lab), expected) == "", "refusal leaves grid teams intact")
	check(FileAccess.get_sha256(save_path) == digest, "refusal does not write the save file")

	off_lab.terrain.site["combat_left"] = 0.0
	var converted: Dictionary = convert_node.convert_existing()
	if not check(converted.ok, "after the battle ends the same Site converts", converted): return
	check(convert_node.active, "converted crowd is active")
	check(_diff(_crowd_census(convert_node, off_lab), expected) == "", "converted: teams, people, positions and items equal", _diff(_crowd_census(convert_node, off_lab), expected))
	check(_no_grid_live(off_lab), "converted grid teams are disabled (single authority)")
	check(FileAccess.get_sha256(save_path) == digest, "conversion on the live Site does not write the save file")
	await _discard(off_lab)

	# Phase 3: crowd requested. The load path converts the legacy save itself (terrain_lab hook).
	var crowd_lab := _new_lab(true)
	check(crowd_lab.crowd_startup_requested, "crowd requested at startup")
	var loaded_on: Dictionary = crowd_lab.site_controller.load_from(save_path)
	if not check(loaded_on.ok, "grid save loads with crowd requested", loaded_on): return
	check(crowd_lab.crowd_site != null and crowd_lab.crowd_site.active, "crowd requested: legacy save becomes a live crowd")
	check(_diff(_crowd_census(crowd_lab.crowd_site, crowd_lab), expected) == "", "crowd requested: roster, positions and items preserved", _diff(_crowd_census(crowd_lab.crowd_site, crowd_lab), expected))
	check(_no_grid_live(crowd_lab), "crowd requested: no grid team keeps authority")
	check(FileAccess.get_sha256(save_path) == digest, "load under crowd leaves the original save byte-identical")
	await _discard(crowd_lab)

	# Phase 4 (option C): an ordinary grid save from this version reloaded under crowd also converts; its bytes stay.
	var ordinary_lab := _new_lab(true)
	var loaded_ordinary: Dictionary = ordinary_lab.site_controller.load_from(marked_path)
	if not check(loaded_ordinary.ok, "ordinary save loads with crowd requested", loaded_ordinary): return
	check(not ordinary_lab.terrain.get_meta(&"legacy_grid_save", false), "ordinary save is not flagged legacy")
	check(ordinary_lab.crowd_site != null and ordinary_lab.crowd_site.active, "ordinary grid reload under crowd becomes a live crowd")
	check(_diff(_crowd_census(ordinary_lab.crowd_site, ordinary_lab), expected) == "", "ordinary reload preserves roster, positions and items", _diff(_crowd_census(ordinary_lab.crowd_site, ordinary_lab), expected))
	check(_no_grid_live(ordinary_lab), "ordinary reload: no grid team keeps authority")
	check(FileAccess.get_sha256(marked_path) == marked_digest, "ordinary reload leaves its save byte-identical")
	await _discard(ordinary_lab)

	print("GATE OK: legacy grid save converts on crowd load ", checks)
	quit(0)

func _new_lab(requested: bool) -> TerrainLab:
	var lab := TerrainLab.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	current_scene = lab
	lab.set_process(false)
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	# _ready reads CrowdSite.requested() from --crowd. Phase 2 overrides it to model an ordinary (no --crowd) start.
	lab.crowd_startup_requested = requested
	if not requested and lab.crowd_site != null:
		var stale: Node = lab.crowd_site
		lab.crowd_site = null
		stale.get_parent().remove_child(stale)
		stale.free()
	return lab

func _attach_crowd(lab: TerrainLab) -> Node:
	var node := Crowd.new()
	node.name = "CrowdSite"
	lab.crowd_site = node
	lab.add_child(node)
	node.setup(lab)
	return node

func _discard(lab: TerrainLab) -> void:
	lab.queue_free()
	await process_frame

func _no_grid_live(lab: TerrainLab) -> bool:
	for team: TerrainArmy in lab.combat_armies:
		if team.combat_enabled and team.has_army(): return false
	return true

func _grid_census(lab: TerrainLab) -> Dictionary:
	var teams: Array = []
	var people: Dictionary = {}
	for team: TerrainArmy in lab.combat_armies:
		if not team.combat_enabled or not team.has_army(): continue
		teams.append(team.team_id)
		for index in range(team.combat_units.size()):
			people[int(team.combat_identity(index))] = team.combat_ground(index) / 64.0
		# The team's joined player member is a grid person outside combat_units.
		if is_instance_valid(team.player_member):
			people[int(team.player_member.person_id)] = team.player_member.position / 64.0
	# Present actors not in any team (a solo controlled actor) are grid people too.
	for actor: TerrainTestCharacter in lab.combat_actors:
		if is_instance_valid(actor) and actor.person_id > 0 and not people.has(int(actor.person_id)):
			people[int(actor.person_id)] = actor.position / 64.0
	return _census(teams, people, lab.terrain.site.item_records.size())

# Rewrites only the envelope without crowd_era. The checksum covers the payload text, which stays byte-identical.
func _copy_without_era(source: String, target: String) -> bool:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(source))
	if not parsed is Dictionary or not parsed.has("crowd_era"): return false
	parsed.erase("crowd_era")
	var file := FileAccess.open(target, FileAccess.WRITE)
	if file == null: return false
	file.store_string(JSON.stringify(parsed, "\t"))
	file.close()
	return true

func _crowd_census(node: Node, lab: TerrainLab) -> Dictionary:
	var teams: Array = []
	for roster: Dictionary in node.rosters: teams.append(int(roster.team_id))
	var people: Dictionary = {}
	for identity: int in node.crowd.person_ids():
		var state: Dictionary = node.soldier_state(int(node.crowd.soldier_index(identity)))
		people[int(identity)] = Vector2(float(state.get("px", -1.0)), float(state.get("py", -1.0)))
	return _census(teams, people, lab.terrain.site.item_records.size())

func _census(teams: Array, people: Dictionary, items: int) -> Dictionary:
	teams.sort()
	return {"teams": teams, "people": people, "items": items}

# Empty string when equal; otherwise the first difference found.
func _diff(a: Dictionary, b: Dictionary) -> String:
	if a.teams != b.teams: return "teams %s vs %s" % [str(a.teams), str(b.teams)]
	if a.items != b.items: return "items %d vs %d" % [int(a.items), int(b.items)]
	var only_a: Array = []
	var only_b: Array = []
	for identity: int in a.people:
		if not b.people.has(identity): only_a.append(identity)
	for identity: int in b.people:
		if not a.people.has(identity): only_b.append(identity)
	if not only_a.is_empty() or not only_b.is_empty():
		return "people only in first %s, only in second %s" % [str(only_a), str(only_b)]
	for identity: int in a.people:
		if (a.people[identity] as Vector2).distance_to(b.people[identity] as Vector2) > POSITION_TOLERANCE:
			return "position of person %d" % identity
	return ""
