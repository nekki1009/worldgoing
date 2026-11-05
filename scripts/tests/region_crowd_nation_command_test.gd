extends SceneTree
## ORDSERIAL: a Region nation command is received by a native crowd team exactly as by an original TerrainArmy.
## Pinned synthetic Region world (same manifest as region_crowd_bind_test.gd), one original GD team imported into a
## native crowd plus three crowd teams (nation HQ, receiving team, enemy). Checks:
## - the native formation order serial: a GD team's counters continue in the crowd; +1 per accepted crowd order and
##   none for a refused one; the ranged counter is written through CrowdPersonOwner; KW20 save / load keeps both;
## - the source gate admits an active crowd (no UNSUPPORTED_BACKEND) and the receiving team is the CrowdPersonOwner;
## - receive applies: the captain's own HOLD goes through crowd_site.issue_order, adds one to the serial, leaves the
##   tactical AI, records the prior policy, and the native order delay is the recorded original delay;
## - restoring the prior policy does not change the serials;
## - a newer order (and a newer ranged order) supersedes: the receive refuses COMMAND_SUPERSEDED and issues nothing.
## No world step runs, so no native AI order can move a serial between the checks.
## Run only with: --crowd --crowd-test <fresh_run_id>
## Output: REGION_CROWD_NATION_COMMAND_PASS on success; quit(1) on any failure.

const Grid = preload("res://scripts/region_lab/region_grid.gd")
const AI = preload("res://scripts/region_lab/region_gameplay_ai.gd")
const NATION_ID := "ordserial_nation"

var out := ""
var manifest_path := ""
var checks := 0
var lab: TerrainLab
var controller: SiteController
var slot: RegionSaveSlot

func _initialize() -> void:
	out = "res://.godot-temp/region_crowd_nation_command/run_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	create_timer(300.0).timeout.connect(func() -> void: _fail("300-second deadline"))
	_run.call_deferred()

func _fail(message: String, detail: Variant = null) -> void:
	printerr("REGION_CROWD_NATION_COMMAND_FAIL: ", message, " ", str(detail))
	quit(1)

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("REGION_CROWD_NATION_COMMAND OK ", checks, ": ", message)
		return true
	_fail(message, detail)
	return false

func _freeze(scene: TerrainLab) -> void:
	scene.set_process(false)
	scene.set_process_input(false)
	scene.set_process_unhandled_input(false)
	scene.site_controller.set_process(false)
	scene.site_controller._auto_save_blocked = true
	for actor: TerrainTestCharacter in scene.combat_actors: actor.set_process(false)
	for team: TerrainArmy in scene.combat_armies: team.set_process(false)

func _asset(name: String, bytes: PackedByteArray) -> Dictionary:
	var path := out.path_join(name)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()
	return {"path": name, "sha256": FileAccess.get_sha256(path)}

## Same pinned synthetic manifest as region_crowd_bind_test.gd.
func _write_manifest() -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	var summary := PackedByteArray()
	summary.resize(9 * 6)
	summary.fill(2)
	var summary_record := _asset("summary.u8", summary)
	summary_record.merge({"size": [9, 6], "site_origin": [-2, -2], "encoding": "u8", "row_order": "north_to_south", "nodata": 0})
	var width := 90
	var height := 60
	var elevation := PackedByteArray()
	var levels := PackedByteArray()
	var water := PackedByteArray()
	elevation.resize(width * height * 2)
	levels.resize(width * height)
	water.resize(width * height)
	for y in range(height):
		var north := -400 + (height - 1 - y) * 20 + 10
		for x in range(width):
			var east := -400 + x * 20 + 10
			var index := y * width + x
			var sea := east >= 400 and east < 440 and north < 400
			elevation.encode_s16(index * 2, -32767 if sea else 40)
			levels[index] = 0 if sea else 2
			water[index] = 2 if sea else 0
	var height_record := _asset("travel.height.zlib", elevation.compress(FileAccess.COMPRESSION_DEFLATE))
	var level_record := _asset("travel.levels.zlib", levels.compress(FileAccess.COMPRESSION_DEFLATE))
	var water_record := _asset("travel.water.zlib", water.compress(FileAccess.COMPRESSION_DEFLATE))
	height_record.merge({"id": "travel_plain", "origin": [-400, -400], "size": [width, height], "spacing_m": 20,
		"encoding": "int16_le_zlib", "row_order": "north_to_south", "nodata": -32767,
		"derived": {"encoding": "u8_zlib", "levels_path": level_record.path, "levels_sha256": level_record.sha256,
			"water_path": water_record.path, "water_sha256": water_record.sha256}})
	var manifest := {"format": 1, "synthetic_fixture": true, "atlas_id": Grid.ATLAS_ID, "grid_contract_version": 1,
		"base_revision": "region-travel-r1-fixture-v1", "crs": "EPSG:3826",
		"grid": {"origin": [0, 0], "cell_m": 2, "site_cells": 100, "region_sites": 100},
		"summary": summary_record, "elevation_tiles": [height_record], "sources": [{"title": "Synthetic Region travel fixture only"}]}
	manifest_path = out.path_join("manifest.json")
	var file := FileAccess.open(manifest_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "", true, true))
	file.close()
	var source := RegionData.new()
	return _check(source.load_manifest(manifest_path).ok, "pinned checksummed manifest loads")

func _side(count: int, faction: int) -> Dictionary:
	var parsed: Dictionary = lab._trial_side_settings({"friendly_count": count, "friendly_training": 0,
		"friendly_female_percent": 0, "friendly_attack": false, "friendly_ai_enabled": false}, "friendly")
	if not _check(parsed.ok, "original side settings accepted", parsed): return {}
	var side: Dictionary = parsed.side
	side.faction = faction
	return side

func _team_with(person_id: int) -> Variant:
	for team: Variant in AI.command_team_owners(lab):
		if team.index_for_identity(person_id) >= 0: return team
	return null

func _serials(team: Variant) -> PackedInt64Array:
	return lab.crowd_site.crowd.order_serials(int(team.formation_index))

func _receive(command: Dictionary, receiver_ref: Dictionary) -> Dictionary:
	var report := {"id": "ordserial_test_report", "delivery": {"command": command, "receiver_ref": receiver_ref.duplicate(true)}}
	return slot._region_receive_nation_command(report, lab, {})

func _run() -> void:
	RegionTravelSite.scene_handoff = false
	var args := OS.get_cmdline_user_args()
	if not _check(args.has("--crowd") and args.has("--crowd-test"), "native startup and a fresh --crowd-test run id required"): return
	if not _write_manifest(): return
	var packed := load("res://scenes/terrain_lab/TerrainLab.tscn") as PackedScene
	if not _check(packed != null, "formal TerrainLab scene exists"): return
	lab = packed.instantiate() as TerrainLab
	if not _check(lab != null, "formal TerrainLab instance exists"): return
	lab.pause_when_unfocused = false
	lab.movement_input_enabled = false
	root.add_child(lab)
	current_scene = lab
	lab.set_process(false)
	if not _check(lab.character != null, "formal scene has its player body"): return
	lab.character.set_process(false)
	controller = lab.site_controller
	if not _check(controller != null and lab.crowd_site != null and not lab.crowd_site.active and not controller.crowd_test_run_id.is_empty(),
		"formal scene has its inactive CrowdSite and isolated Controller"): return
	_freeze(lab)
	var world_id := "r0_crowd_nation_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var opened: Dictionary = controller.open_fixed_world(manifest_path, world_id, "main", Vector2i.ZERO, true)
	if not _check(opened.ok, "Controller publishes and live-binds a pinned Region world", opened): return
	_freeze(lab)
	slot = controller.region_slot
	if not _check(slot != null, "Region slot exists after the fixed world binds"): return
	# Neutral part 2: the bind opens the Site as a live native crowd (the player's start team); clear it to GD first.
	var bind_live: Dictionary = lab.region_bind_receipt(lab.terrain)
	if not _check(bind_live.get("complete") == true and str(bind_live.get("backend", "")) == "native" and lab.crowd_site.active, "a new world binds straight into a live native crowd", bind_live): return
	var cleared: Dictionary = lab.crowd_site.clear()
	if not _check(cleared.get("ok", false) == true and not lab.crowd_site.active, "the player's crowd team returns to GD before the test sides deploy", cleared): return
	# Stand-in for the pending join relabel: the player's start team joins the friendly faction 0, as the old actor
	# player was. Neutral is hostile to everyone, so a neutral player beside the test team would block its departure.
	for team: TerrainArmy in lab.combat_armies:
		if team.has_army() and team.combat_identity(0) == lab.controlled_person_id(): team.faction_id = 0
	var site_id := str(lab.terrain.site.id)
	var centre: Vector2i = lab.terrain.spawn_cell
	if not _check(centre != Vector2i(-1, -1), "Region fixed world has a legal spawn cell", centre): return

	# One original GD team first: the crowd takes it over through the D5 import and continues its order counters.
	var inactive = lab.crowd_site
	var gd_cells: Array[Vector2i] = [centre + Vector2i(4, 3), centre + Vector2i(5, 3)]
	var gd_sides: Array[Dictionary] = [_side(gd_cells.size(), 0)]
	var gd_formations: Array = [gd_cells]
	lab.crowd_site = null
	var gd_deployed: Dictionary = lab._deploy_trial_teams(gd_sides, gd_formations, 1) # Slot 0 holds the player team.
	lab.crowd_site = inactive
	if not _check(gd_deployed.ok, "original GD team deploys before native activation", gd_deployed): return

	# Native crowd: nation HQ (one captain), the receiving team, an enemy team.
	var hq_cells: Array[Vector2i] = [centre + Vector2i(-4, 3)]
	var receiver_cells: Array[Vector2i] = [centre + Vector2i(-1, 3), centre + Vector2i(0, 3)]
	var enemy_cells: Array[Vector2i] = [centre + Vector2i(-1, -6), centre + Vector2i(0, -6)]
	var sides: Array[Dictionary] = [_side(hq_cells.size(), 0), _side(receiver_cells.size(), 0), _side(enemy_cells.size(), 1)]
	var formations: Array = [hq_cells, receiver_cells, enemy_cells]
	var entered: Dictionary = lab.crowd_site.deploy(sides, formations)
	if not _check(entered.get("ok", false) and lab.crowd_site.active, "native crowd battle activates", entered): return
	_freeze(lab)
	var crowd: Object = lab.crowd_site.crowd
	if not _check(crowd.has_method("order_serials") and crowd.has_method("set_order_serials"), "ArmyCrowd exposes the ORDSERIAL counters"): return

	# GD -> crowd: the imported team's native counters equal its original TerrainArmy's.
	# The player team (slot 0) is imported too; the original fixture team is the other one.
	if not _check(lab.crowd_site._original_team_plans.size() == 2, "the player team and the one original team were imported", lab.crowd_site._original_team_plans.size()): return
	var source: TerrainArmy = null
	for plan: Variant in lab.crowd_site._original_team_plans:
		if plan.source.combat_identity(0) != lab.controlled_person_id(): source = plan.source
	if not _check(source != null, "the original fixture team was imported"): return
	var imported: Variant = null
	for team: Variant in AI.command_team_owners(lab):
		if int(team.team_id) == int(source.team_id): imported = team
	if not _check(imported is CrowdPersonOwner, "the imported original team has a crowd command owner"): return
	var imported_serials := _serials(imported)
	if not _check(imported_serials.size() == 2 and int(imported_serials[0]) == int(source.get_order_serial()) and int(imported_serials[1]) == int(source.ranged_order_serial)
		and imported.get_order_serial() == int(source.get_order_serial()) and imported.ranged_order_serial == int(source.ranged_order_serial),
		"the crowd continues the original team's order and ranged order serials", {"native": imported_serials, "order": source.get_order_serial(), "ranged": source.ranged_order_serial}): return

	# Crowd-only teams: counters start at 1 / 0 and are read natively (no original owner to delegate to).
	# Crowd-deployed sides take team ids in side order; the imported original team keeps its own id.
	var crowd_rows: Array = []
	for row: Dictionary in lab.crowd_site.teams:
		# The player's start team was imported from GD as well; it is neither a crowd-deployed side nor the fixture team.
		if not bool(row.get("solo", false)) and int(row.team_id) != int(source.team_id) and not row.person_ids.has(lab.controlled_person_id()): crowd_rows.append(row)
	crowd_rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.team_id) < int(b.team_id))
	if not _check(crowd_rows.size() == 3, "the crowd has the HQ, receiving and enemy teams", crowd_rows.size()): return
	var hq_team: Dictionary = crowd_rows[0]
	var receiver_team_row: Dictionary = crowd_rows[1]
	if not _check(hq_team.person_ids.size() == 1 and receiver_team_row.person_ids.size() == 2 and int(crowd_rows[2].faction) == 1, "crowd teams follow the side order"): return
	var head := int(hq_team.person_ids[0])
	var team: Variant = _team_with(int(receiver_team_row.person_ids[0]))
	if not _check(team is CrowdPersonOwner and int(team.team_id) == int(receiver_team_row.team_id), "the receiving crowd team has its command owner"): return
	if not _check(team._order_owner() == null, "a crowd-deployed team has no original owner (the old 0 / missing-owner case)"): return
	var start := _serials(team)
	if not _check(start.size() == 2 and int(start[0]) == 1 and int(start[1]) == 0 and team.get_order_serial() == 1 and team.ranged_order_serial == 0,
		"a crowd team starts at order serial 1 and ranged serial 0 read from native state", start): return
	var held: Dictionary = lab.crowd_site.issue_order(int(team.team_id), TerrainArmy.CombatOrder.HOLD, Vector2i(-1, -1), -1, "ui")
	if not _check(held.ok and team.get_order_serial() == 2 and team.ranged_order_serial == 0, "an accepted crowd order adds one to the order serial only", held): return
	if not _check(float(lab.crowd_site.formation_state(int(team.formation_index)).order_delay) > 0.0, "an accepted crowd HOLD starts the original order delay"): return
	var refused: Dictionary = lab.crowd_site.issue_order(int(team.team_id), TerrainArmy.CombatOrder.RETREAT, Vector2i(-1, -1), -1, "ui")
	if not _check(not refused.ok and team.get_order_serial() == 2, "a refused crowd order leaves the serial", refused): return
	team.ranged_order_serial = 4
	if not _check(team.ranged_order_serial == 4 and int(_serials(team)[1]) == 4 and int(_serials(team)[0]) == 2, "the ranged order counter is written to the native formation"): return
	team.ranged_order_serial = 0
	var blob: PackedByteArray = crowd.save_state()
	if not _check(blob.size() > 4 and blob[0] == 0x4B and blob[1] == 0x57 and blob[2] == 0x32 and blob[3] == 0x30, "the native save magic is KW20 (KW19 order serials, KW20 formation shapes)"): return
	var copy: RefCounted = ClassDB.instantiate("ArmyCrowd")
	copy.setup(1, 971)
	if not _check(copy.load_state(blob) and copy.order_serials(int(team.formation_index)) == _serials(team) and copy.order_serials(int(imported.formation_index)) == imported_serials,
		"a KW20 save loads with the same counters"): return

	# Nation authority in this same Site: head = HQ captain; members = head and the receiving team.
	var members: Array[int] = [head]
	for identity: Variant in receiver_team_row.person_ids: members.append(int(identity))
	if not lab.terrain.site.has("equipment_nations"): lab.terrain.site["equipment_nations"] = {}
	lab.terrain.site.equipment_nations[NATION_ID] = {"members": members, "standards": {}, "offices": SiteOffices.default_offices("nation", head, true)}
	var identified := RegionTravel.prepare_identity(lab.terrain.site)
	if not _check(identified.ok, "original identity allocator indexes the crowd people, teams and the nation", identified): return
	lab.terrain.site["travel_identity"] = identified.state.travel_identity
	var nation_ref: Dictionary = lab.terrain.site.travel_identity.refs.nation[NATION_ID].duplicate(true)
	var team_ref: Dictionary = lab.terrain.site.travel_identity.refs.team.get(str(int(team.team_id)), {}).duplicate(true)
	var head_ref := AI.person_ref(lab.terrain.site, head)
	var commander_ref := AI.person_ref(lab.terrain.site, team.combat_identity(team.current_commander))
	if not _check(AI.delivery_reference(nation_ref, "nation") and AI.delivery_reference(team_ref, "team") and AI.valid_person_ref(head_ref) and AI.valid_person_ref(commander_ref),
		"stable nation, team and person references exist for the crowd teams"): return
	var memberships: Array = []
	for identity: Variant in receiver_team_row.person_ids:
		memberships.append({"person": AI.person_ref(lab.terrain.site, int(identity)), "nation": nation_ref.duplicate(true),
			"source_site_id": site_id, "source_nation_id": NATION_ID, "office_ids": []})
	lab.terrain.site["organization_refs"] = {"version": 1, "remote_people": {}, "remote_teams": {}, "nation_memberships": memberships, "corps_memberships": []}
	if not _check(SiteEquipmentOrders.valid_organization_refs(lab.terrain.site), "the receiving team's nation memberships are valid organization references"): return
	var resolved: Dictionary = controller.equipment_orders.nation_duty_resolve(lab.terrain.site.equipment_nations[NATION_ID], "nation.dispatch")
	if not _check(resolved.get("ok", false) and int(resolved.decider) == head, "the crowd HQ captain decides the nation dispatch duty", resolved): return
	if not _check(slot._region_nation_team(lab, team_ref) == team, "the nation command's receiving team under a crowd is its CrowdPersonOwner"): return

	var command := {"version": AI.DELIVERY_VERSION, "duty": "nation.dispatch", "source_scope": site_id, "nation_id": NATION_ID,
		"nation_ref": nation_ref.duplicate(true), "issuer_ref": head_ref.duplicate(true), "offices_revision": int(resolved.revision),
		"receiver_team_ref": team_ref.duplicate(true), "target_site": Grid.site_id(str(slot.pin.atlas_id), Vector2i(0, 1)), "target_coordinate": [0, 1],
		"receiver_order_serial": int(team.get_order_serial()), "receiver_ranged_order_serial": int(team.ranged_order_serial)}
	# The real Region flow wires the Slot's original-owner adapters on the first live advance
	# (TerrainLab advance -> _wire_region_gameplay_adapters); open_fixed_world alone does not. No step runs here,
	# so wire them through the same real function. The nation source needs region_owner_lab (live scope -> this lab).
	if not slot.region_owner_lab.is_valid():
		var wired: Dictionary = lab._wire_region_gameplay_adapters(slot)
		if not _check(slot.region_owner_lab.is_valid(), "the real Region adapter wiring installs the original-owner adapter", wired): return
	var owner_probe: Dictionary = slot.region_owner_lab.call(site_id, "live")
	if not _check(owner_probe.get("ok", false) and owner_probe.get("lab") == lab, "the live owner adapter resolves this crowd Site", owner_probe): return
	var authority: Dictionary = slot._region_remote_nation_source(command)
	if not _check(authority.get("ok", false), "the nation source admits an active crowd (no UNSUPPORTED_BACKEND)", authority): return

	# Receive applies.
	if not _check(lab.crowd_site.set_team_ai(int(team.team_id), true).ok and team.tactical_ai_enabled, "the receiving captain runs its own tactical AI before the command"): return
	var before := _serials(team)
	var received := _receive(command, commander_ref)
	if not _check(received.get("ok", false) and received.get("delivered", false), "the crowd team receives the nation command", received): return
	var effect: Dictionary = received.effect
	var native_delay := float(lab.crowd_site.formation_state(int(team.formation_index)).order_delay)
	if not _check(effect.kind == "original_nation_dispatch" and effect.execution == "pending"
		and int(effect.before_order_serial) == int(before[0]) and int(effect.accepted_order_serial) == int(before[0]) + 1 and team.get_order_serial() == int(before[0]) + 1
		and int(effect.before_ranged_order_serial) == int(before[1]) and int(effect.accepted_ranged_order_serial) == int(before[1]),
		"the captain's own HOLD went through crowd_site.issue_order and the effect records both serials", effect): return
	if not _check(bool(effect.prior_tactical_ai_enabled) and not team.tactical_ai_enabled and team.combat_order == TerrainArmy.CombatOrder.HOLD,
		"the HOLD leaves the tactical AI and the prior policy is recorded", effect): return
	if not _check(float(effect.original_order_delay) > 0.0 and float(effect.original_order_delay) == native_delay
		and slot._region_team_order_delay(team) == native_delay and native_delay > TerrainLab.ACTION_TIME_EPSILON,
		"the recorded original order delay is the native formation's order delay, still unpaid", {"effect": effect.original_order_delay, "native": native_delay}): return
	var after_receive := _serials(team)
	if not _check(slot._region_team_restore_policy(team).ok and team.tactical_ai_enabled and _serials(team) == after_receive,
		"restoring the prior tactical policy changes neither serial"): return
	if not _check(lab.crowd_site.set_team_ai(int(team.team_id), false).ok and _serials(team) == after_receive, "handing the team back to the host changes neither serial"): return

	# A newer order supersedes.
	var stale := command.duplicate(true)
	stale["receiver_order_serial"] = int(team.get_order_serial())
	stale["receiver_ranged_order_serial"] = int(team.ranged_order_serial)
	var newer: Dictionary = lab.crowd_site.issue_order(int(team.team_id), TerrainArmy.CombatOrder.HOLD, Vector2i(-1, -1), -1, "ui")
	if not _check(newer.ok and team.get_order_serial() == int(stale.receiver_order_serial) + 1, "the captain issues a newer order", newer): return
	var superseded_serials := _serials(team)
	var superseded := _receive(stale, commander_ref)
	if not _check(superseded.get("ok", false) and not superseded.get("delivered", true) and str(superseded.get("receipt", {}).get("code", "")) == "COMMAND_SUPERSEDED"
		and _serials(team) == superseded_serials, "a newer order supersedes the command: COMMAND_SUPERSEDED and no order issued", superseded): return

	# A newer ranged order supersedes too (the same pair rule as the grid).
	var ranged_stale := command.duplicate(true)
	ranged_stale["receiver_order_serial"] = int(team.get_order_serial())
	ranged_stale["receiver_ranged_order_serial"] = int(team.ranged_order_serial)
	team.ranged_order_serial = int(team.ranged_order_serial) + 1
	var ranged_serials := _serials(team)
	var ranged_superseded := _receive(ranged_stale, commander_ref)
	if not _check(ranged_superseded.get("ok", false) and not ranged_superseded.get("delivered", true)
		and str(ranged_superseded.get("receipt", {}).get("code", "")) == "COMMAND_SUPERSEDED" and _serials(team) == ranged_serials,
		"a newer ranged order supersedes the command too", ranged_superseded): return

	# A current command is received again (the rule refuses only stale serials).
	var current := command.duplicate(true)
	current["receiver_order_serial"] = int(team.get_order_serial())
	current["receiver_ranged_order_serial"] = int(team.ranged_order_serial)
	var again := _receive(current, commander_ref)
	if not _check(again.get("ok", false) and again.get("delivered", false) and int(again.effect.accepted_order_serial) == int(current.receiver_order_serial) + 1,
		"a command signed against the current serials is received", again): return
	print("REGION_CROWD_NATION_COMMAND_PASS: ", checks, " checks; crowd order serials count, save and continue the original team; a nation command is received through crowd_site.issue_order and a newer order supersedes it")
	quit(0)
