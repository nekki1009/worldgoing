extends "res://scripts/tests/site_n04_workshop_earned_test.gd"
## Test-only original owners. Initial infrastructure/stocks/archives are explicit
## prior-world fixtures. Target work always uses the original shared main step.
const EarnedGrid = preload("res://scripts/region_lab/region_grid.gd")
const EarnedEntry = preload("res://scripts/region_lab/region_entry.gd")
var earned_out = ""
var earned_last_exists = false
var earned_last_bytes = PackedByteArray()
var earned_labs: Array[TerrainLab] = []

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 480000 # Crowd port: real whole-Lab points; 240 s → 480 s (outer 600), the over-budget rule.
	earned_last_exists = FileAccess.file_exists(EarnedEntry.LAST_WORLD)
	if earned_last_exists: earned_last_bytes = FileAccess.get_file_as_bytes(EarnedEntry.LAST_WORLD)
	_run.call_deferred()

func _earned_freeze_scene(lab: TerrainLab) -> void:
	lab.set_process(false)
	lab.set_process_input(false)
	lab.set_process_unhandled_input(false)
	lab.site_controller.set_process(false)
	lab.site_controller._auto_save_blocked = true
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	for team: TerrainArmy in lab.combat_armies: team.set_process(false)

func _earned_natural_data() -> TerrainData:
	var data = TerrainGenerator.generate(TerrainPreset.Kind.PLAINS, 12345)
	Env.initialize(data, "nation-first-earned-natural")
	return data # No generated terrain or land-condition field is overwritten.

func _earned_natural_lab(data: TerrainData) -> TerrainLab:
	var lab = TerrainLab.new()
	lab.npc = TerrainTestNPC.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	lab.set_process(false)
	lab.character.set_process(false)
	lab.npc.set_process(false)
	lab.site_controller._auto_save_blocked = true
	lab.bind_terrain(data)
	lab.character.faction_id = 1
	lab.npc.faction_id = 1
	var camp = data.cell_from_index(int(data.site.depot_cell))
	_check(lab.character.place(camp, true), "Actual Actor reaches the original generated camp")
	var npc_cell = Vector2i(-1, -1)
	for direction: Vector2i in TerrainData.DIRECTIONS:
		var cell = camp + direction
		if data.contains(cell) and data.is_walkable(cell) and data.can_step(camp, cell):
			npc_cell = cell
			break
	_check(npc_cell.x >= 0 and lab.npc.place(npc_cell, true), "The second original Actor has a distinct legal camp contact")
	lab.site_controller.release_worker()
	return lab

func _earned_setup_geometry(lab: TerrainLab, kind: String, near: Vector2i, extent: Vector2i, options: Dictionary = {}, excluded: Array = []) -> Dictionary:
	var data = lab.terrain
	var settings = {"layout_version": 1, "quarter": 0, "owner_faction": 1}
	settings.merge(options, true)
	for radius: int in range(9):
		for y: int in range(-radius, radius + 1):
			for x: int in range(-radius, radius + 1):
				if absi(x) + absi(y) != radius: continue
				var anchor = near + Vector2i(x, y)
				var geometry = Runtime.building_cells(data, kind, anchor, extent, settings)
				if not geometry.ok: continue
				if geometry.cells.any(func(index: int) -> bool: return excluded.has(index)): continue
				var preview = Runtime.preview_build(data, kind, geometry.cells, lab.site_controller.reserves_cell, settings)
				if not preview.ok: continue
				geometry["fixture_anchor"] = anchor
				geometry["fixture_options"] = settings
				geometry["fixture_preview"] = preview
				return geometry
	_check(false, "Original finite setup scan must find a legal " + kind + " near " + str(near))
	return {}

func _earned_setup_feature(lab: TerrainLab, kind: String, near: Vector2i, extent: Vector2i = Vector2i.ONE, options: Dictionary = {}, excluded: Array = []) -> String:
	var geometry = _earned_setup_geometry(lab, kind, near, extent, options, excluded)
	# Explicit prior-world infrastructure: sparse resource clearing is through
	# its original Env owner, never an unrecorded terrain/soil array mutation.
	for key: String in geometry.fixture_preview.get("clearing", []): Env.change(lab.terrain, key, {"cleared": true, "remaining": 0})
	return _formal_feature(lab.terrain, kind, geometry.fixture_anchor, extent, options)

func _earned_land_bytes(data: TerrainData) -> PackedByteArray:
	return var_to_bytes([data.fertility, data.moisture, data.drainage, data.foundation, data.groundwater])

func _earned_asset(name: String, bytes: PackedByteArray) -> Dictionary:
	var path = earned_out.path_join(name)
	var file = FileAccess.open(path, FileAccess.WRITE)
	_check(file != null, "Original test map asset is writable")
	file.store_buffer(bytes)
	file.close()
	return {"path": name, "sha256": FileAccess.get_sha256(path)}

func _earned_pinned_manifest() -> String:
	# Original region_travel_test's checksummed flat finite synthetic source, with
	# the new rule encoded in the actual metadata/hash/pin (never a parameter
	# patch over an old source). Potential is original game formula, not soil
	# measurement or a real Taiwan source. Without the
	# irrelevant sea detour. RegionData/Adapter own the actual generated Site.
	earned_out = "user://technology_nation_earned_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	_check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(earned_out)) == OK, "Test-only pinned map directory exists")
	var summary = PackedByteArray()
	summary.resize(54)
	summary.fill(2)
	var summary_ref = _earned_asset("summary.u8", summary)
	summary_ref.merge({"size": [9, 6], "site_origin": [-2, -2], "encoding": "u8", "row_order": "north_to_south", "nodata": 0})
	var elevation = PackedByteArray()
	var levels = PackedByteArray()
	var water = PackedByteArray()
	elevation.resize(90 * 60 * 2)
	levels.resize(90 * 60)
	water.resize(90 * 60)
	levels.fill(2)
	water.fill(0)
	for index: int in range(90 * 60): elevation.encode_s16(index * 2, 40)
	var height_ref = _earned_asset("plain.height.zlib", elevation.compress(FileAccess.COMPRESSION_DEFLATE))
	var level_ref = _earned_asset("plain.levels.zlib", levels.compress(FileAccess.COMPRESSION_DEFLATE))
	var water_ref = _earned_asset("plain.water.zlib", water.compress(FileAccess.COMPRESSION_DEFLATE))
	height_ref.merge({"id": "earned_plain", "origin": [-400, -400], "size": [90, 60], "spacing_m": 20,
		"encoding": "int16_le_zlib", "row_order": "north_to_south", "nodata": -32767,
		"derived": {"encoding": "u8_zlib", "levels_path": level_ref.path, "levels_sha256": level_ref.sha256,
			"water_path": water_ref.path, "water_sha256": water_ref.sha256}})
	var manifest = {"format": 1, "synthetic_fixture": true, "atlas_id": EarnedGrid.ATLAS_ID, "grid_contract_version": 1,
		"base_revision": "technology-earned-clock-fixture-land-v2", "land_condition_rule": "terrain_mapped_potential_v1", "crs": "EPSG:3826",
		"grid": {"origin": [0, 0], "cell_m": 2, "site_cells": 100, "region_sites": 100},
		"summary": summary_ref, "elevation_tiles": [height_ref], "sources": [{"title": "Finite original Slot clock fixture only"}]}
	var path = earned_out.path_join("manifest.json")
	var file = FileAccess.open(path, FileAccess.WRITE)
	_check(file != null, "Actual original map manifest can be written")
	file.store_string(JSON.stringify(manifest, "", true, true))
	file.close()
	var map = RegionData.new()
	_check(map.load_manifest(path).ok, "Original RegionData validates checksums and the actual fixed map contract")
	return path

## Since the neutral-team start the controlled person is the captain row of a one-person team,
## not the legacy Actor. Stand both at the cell and join that team to the fixture's faction 1
## (neutral cannot found or govern), as region_crowd_save_slot_test does for its founder.
func _earned_place_controlled(lab: TerrainLab, cell: Vector2i) -> bool:
	var placed: bool = lab.character.place(cell, true)
	var control := int(lab.controlled_person_id())
	for own_team: TerrainArmy in lab.combat_armies:
		var index := own_team.index_for_identity(control)
		if own_team.has_army() and index >= 0 and index < own_team.cells.size():
			own_team.faction_id = 1
			own_team.cells[index] = cell
	# Crowd port: on an active crowd the controlled head is the same native soldier; the fixture station moves it too, and
	# real points run until it stands (a placement changes no velocity until the next step).
	if placed and lab.crowd_site != null and lab.crowd_site.active and lab.crowd_site.contains_person(control):
		var native := int(lab.crowd_site.crowd.soldier_index(control))
		placed = native >= 0 and lab.crowd_site.set_soldier_fields(native, {"px": cell.x + 0.5, "py": cell.y + 0.5})
		var head_team: Variant = lab.crowd_site.person_owner(control)
		if placed and head_team != null and head_team.combat_units.size() == 1: # A lone head's team holds where it stands.
			lab.crowd_site.set_formation_fields(int(head_team.formation_index), {"cx": cell.x + 0.5, "cy": cell.y + 0.5,
				"origin_x": cell.x + 0.5, "origin_y": cell.y + 0.5, "goal_x": cell.x + 0.5, "goal_y": cell.y + 0.5})
		# Few points: each fixture point is real World time, and a mandate or job deadline is running.
		for settle: int in 200:
			if settle >= 4 and head_team != null and head_team.moving_member_count() == 0: break
			if settle < 3: lab.crowd_site.siege_approach_step(control, cell)
			elif settle == 3 and head_team != null: head_team.siege_cancel_step(head_team.index_for_identity(control))
			if not lab._advance_original_shared_step(TerrainLab.EXCHANGE_ACTION_STEP if lab.exchange_enabled else TerrainLab.ACTION_STEP).ok: break
		if head_team != null: head_team.siege_cancel_step(head_team.index_for_identity(control))
		placed = placed and lab.crowd_site.siege_original_person(control).cell == cell
	return placed

func _earned_pinned_lab() -> TerrainLab:
	var path = _earned_pinned_manifest()
	var lab = _earned_natural_lab(_earned_natural_data())
	lab.site_controller.save_root = earned_out.path_join("archive")
	# Crowd port: the fixed world binds without its crowd; the fixture converts after building its teams (_earned_fixture).
	lab.crowd_startup_requested = false
	var opened = lab.site_controller.open_fixed_world(path, "tech_earned_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()], "main", Vector2i.ZERO, true)
	_check(opened.ok and lab.site_controller.region_slot != null and not lab.site_controller.region_slot.pin.is_empty(), "Original Controller creates, commits and live-binds a real original Slot; no clock/pin dictionary injection")
	_earned_freeze_scene(lab)
	_check(lab.site_controller.region_slot._coordinate(lab.terrain).ok, "The actual generated Site retains the same immutable original map pin")
	return lab

func _earned_army(lab: TerrainLab, count: int, excluded_cells: Array = []) -> TerrainArmy:
	var team = TerrainArmy.new()
	root.add_child(team)
	team.set_process(false)
	team.team_id = 402 if count == 40 else 301
	# Real deployments advance the site team counter past the new team.
	lab.terrain.site["army_next_team"] = maxi(int(lab.terrain.site.get("army_next_team", 1)), int(team.team_id) + 1)
	team.roster_size = count
	team.faction_id = 1
	team.person_id_allocator = Callable(lab, "_allocate_army_person_ids")
	var cells: Array[Vector2i] = []
	for index: int in range(count):
		# The 40-person army stands beside the workshops so production's command
		# radius covers the named operator's workplace.
		var near = Vector2i(14 + index % 20, 21 + floori(float(index) / 20.0)) if count == 40 else Vector2i(11 + index, 11)
		var chosen = Vector2i(-1, -1)
		for radius: int in range(5):
			for y: int in range(-radius, radius + 1):
				for x: int in range(-radius, radius + 1):
					if absi(x) + absi(y) != radius: continue
					var candidate = near + Vector2i(x, y)
					if lab.terrain.contains(candidate) and lab.terrain.is_walkable(candidate) and not cells.has(candidate) and candidate not in [lab.character.terrain_cell, lab.npc.terrain_cell] \
						and (excluded_cells.is_empty() or lab.terrain.feature_at[lab.terrain.index(candidate)] == 0 and not excluded_cells.has(lab.terrain.index(candidate))):
						chosen = candidate
						break
				if chosen.x >= 0: break
			if chosen.x >= 0: break
		_check(chosen.x >= 0, "Original generated terrain has one distinct legal deployment cell for each initial original NPC")
		cells.append(chosen)
	_check(team.deploy_at(lab.terrain, null, null, cells) and team.enable_combat(false), "Original finite Army plus actual Lab person allocator creates the real pre-existing NPC rows")
	for row: Dictionary in team.combat_units:
		row.cargo = {}
		row.item_state = Runtime.new_item_state("person:" + str(row.person_id))
	lab.combat_armies.append(team)
	team.controlled_person_query = lab.controlled_person_id
	team.person_busy_query = lab.site_controller.person_actions.is_busy
	team.settle_combat_command()
	_check(team.set_duty_ai_enabled(team.combat_identity(team.formal_commander), true).ok, "The true living original captain explicitly admits reactive duty AI")
	return team

func _earned_fixture(target: String, fixed: bool = false, metropolis: bool = false) -> Dictionary:
	var lab = _earned_pinned_lab() if fixed else _earned_natural_lab(_earned_natural_data())
	earned_labs.append(lab)
	var data: TerrainData = lab.terrain
	_earned_freeze_scene(lab)
	lab.character.faction_id = 1
	for resource: String in Env.ITEM_NAMES: data.site.inventory[resource] = 10000
	data.site.capacity = 1000000
	var controller = lab.site_controller
	var control = int(lab.controlled_person_id())
	# The 40-person army deploys after the buildings (below); the small one now.
	var team = null if metropolis else _earned_army(lab, 2)
	var executor = control if target == "N10" or team == null else team.combat_identity(1)
	var center_anchor = Vector2i(25, 25) if metropolis else Vector2i(18, 10)
	var center = _earned_setup_geometry(lab, "settlement_center", center_anchor, Vector2i(5, 5))
	var reserved_center: Array = center.cells.duplicate()
	reserved_center.append(int(center.fixture_preview.entrance))
	var houses: Array[String] = []
	if metropolis:
		for y: int in [10, 40]:
			for x: int in [10, 17, 24, 31, 38]: houses.append(_earned_setup_feature(lab, "house", Vector2i(x, y), Vector2i.ONE, {"variant": "large"}, reserved_center))
	else: houses.append(_earned_setup_feature(lab, "house", Vector2i(13, 18), Vector2i(2, 2), {}, reserved_center))
	var actor_home = _earned_setup_feature(lab, "house", Vector2i(17, 18), Vector2i.ONE, {}, reserved_center) if target == "N10" else ""
	var warehouse = _earned_setup_feature(lab, "warehouse", Vector2i(8, 18) if metropolis else Vector2i(13, 13), Vector2i.ONE, {}, reserved_center)
	_check(Stocks.ensure_storage(data, warehouse, 1).ok, "The completed original Warehouse owns a real stock endpoint before any public order destination query")
	var smithy = _earned_setup_feature(lab, "smithy", Vector2i(25, 18), Vector2i.ONE, {}, reserved_center)
	var tannery = ""
	if metropolis:
		tannery = _earned_setup_feature(lab, "tannery", Vector2i(34, 18), Vector2i.ONE, {}, reserved_center)
		for key: String in [smithy, tannery]:
			_check(Runtime.request_upgrade(data, key, 1).ok, "Original un-founded world legally upgrades the initial real workshop to grade2")
			_complete_key(data, key)
			_check(Runtime.request_upgrade(data, key, 1).ok, "Original un-founded world legally upgrades the same original workshop to grade3")
			_complete_key(data, key)
		# Inside the radius-12 jurisdiction of the center at (25, 25).
		_earned_setup_feature(lab, "well", Vector2i(20, 31), Vector2i.ONE, {}, reserved_center)
		_earned_setup_feature(lab, "farm", Vector2i(15, 25), Vector2i(2, 2), {}, reserved_center)
		# Deploy after the buildings: never on a building cell, any entrance or the
		# reserved center; deploy_at then sets command radius and presence itself.
		var army_excluded: Array = reserved_center.duplicate()
		for fixture_key: String in data.site.features:
			army_excluded.append(int(data.site.features[fixture_key].get("entrance", -1)))
			# Keep a one-cell ring round every building free: work cells and access paths.
			for fixture_cell: Variant in data.site.features[fixture_key].get("cells", []):
				var ring_centre: Vector2i = data.cell_from_index(int(fixture_cell))
				for ring_y: int in range(-1, 2):
					for ring_x: int in range(-1, 2):
						var ring_cell: Vector2i = ring_centre + Vector2i(ring_x, ring_y)
						if data.contains(ring_cell): army_excluded.append(data.index(ring_cell))
		team = _earned_army(lab, 40, army_excluded)
		executor = control if target == "N10" else team.combat_identity(1)
	var founding_cell: Vector2i = data.cell_from_index(int(center.fixture_preview.entrance))
	_check(_earned_place_controlled(lab, founding_cell), "The actual controlled founder reaches the true original founding radius")
	var center_cells: Array[int] = []
	center_cells.assign(center.cells)
	for key: String in center.fixture_preview.get("clearing", []): Env.change(data, key, {"cleared": true, "remaining": 0})
	var founded = Settlement.found(lab, control, center_cells)
	_check(founded.ok, "Original founding transaction creates the true local head and same original center: " + str(founded))
	_complete_key(data, str(founded.feature))
	# Initial NPC housing is a strict prior-world relation to the finite original
	# people and actual original house slots; no population or permission field.
	var slots: Array[Dictionary] = []
	# Fixture worlds carry generated natural resources; clear any on each house's
	# entrance row (as for the center clearing) so its real slots are counted.
	for fixture_house: String in houses:
		var fixture_feature: Dictionary = data.site.features[fixture_house]
		for fixture_pair: Dictionary in Runtime._building_entrances(data, fixture_feature.cells, int(fixture_feature.quarter)):
			for fixture_key: String in Env.resources_in(data, Rect2i(fixture_pair.cell, Vector2i.ONE)): Env.change(data, fixture_key, {"cleared": true, "remaining": 0})
	Env.rebuild_indexes(data)
	for key: String in houses:
		var layout = Runtime.house_layout(data, key)
		_check(layout.ok, "True original house computes its actual resident slots")
		for cell: int in layout.slots: slots.append({"house_id": key, "cell": cell})
	var people = {}
	var housing = {}
	var identities: Array[int] = []
	for index: int in team.combat_units.size(): identities.append(team.combat_identity(index))
	if slots.size() < identities.size():
		# The houses fell short on this generated world (height step / edge overlap);
		# one more genuine large house keeps a real house slot for every resident.
		var extra_house: String = _earned_setup_feature(lab, "house", Vector2i(38, 25), Vector2i.ONE, {"variant": "large"}, reserved_center)
		var extra_feature: Dictionary = data.site.features[extra_house]
		for fixture_pair: Dictionary in Runtime._building_entrances(data, extra_feature.cells, int(extra_feature.quarter)):
			for fixture_key: String in Env.resources_in(data, Rect2i(fixture_pair.cell, Vector2i.ONE)): Env.change(data, fixture_key, {"cleared": true, "remaining": 0})
		Env.rebuild_indexes(data)
		houses.append(extra_house)
		# The new house can take cells from a neighbour's entrance row: recount all.
		slots.clear()
		for recount_house: String in houses:
			for cell: int in Runtime.house_layout(data, recount_house).slots: slots.append({"house_id": recount_house, "cell": cell})
	_check(slots.size() >= identities.size(), "Actual initial houses hold all original finite NPC residents")
	for index: int in identities.size():
		housing[str(identities[index])] = {"version": 1, "house_id": str(slots[index].house_id), "cell": int(slots[index].cell)}
		people[identities[index]] = {"hp": float(team.combat_units[index].hp), "faction_id": 1}
	data.site.housing = housing
	_check(Homes.validate(data, data.site, people).ok, "The unchanged strict original Housing validator admits every real prior resident reference")
	if target == "N10":
		_check(Homes.assign(lab, control, actor_home, control).ok and Settlement.residents(lab).has(control), "The actual controlled local head uses the original legal housing command for its own residency")
	if metropolis:
		for level: int in [2, 3]:
			_check(Settlement.request_upgrade(lab, control).ok, "Original Settlement requirements and payment permit the actual next city level")
			_complete_key(data, str(founded.feature))
			_check(int(Settlement.record(data).level) == level and Settlement.status(lab).effective, "The original same center completes its true upgrade; no level field is forged")
	_check(Settlement.status(lab).effective, "The actual original settlement is currently effective")
	data.site.settlement.version = 2
	data.site.settlement.technology = Technology.empty_scope_record(str(data.site.id))
	data.site.settlement.technology.known = ["S13"] if metropolis else []
	var nation = {"offices": SiteOffices.default_offices("nation", control), "members": [control] + identities, "standards": {}, "technology": Technology.empty_scope_record(str(data.site.id))}
	nation.technology.known = ["N04"] if target == "N11" else ["N02", "N09"] if target == "N10" else []
	data.site.equipment_nations = {"n1": nation}
	if target == "N11": team.combat_units[1].technology = Technology.learned_candidate({}, "F04")
	_check(bool(NationCatalog.get_node(target).get("enabled", false)) and not Technology.scope_known(nation.technology, target), "The isolated enabled target institution starts genuinely unknown; only stated prior inputs exist")
	# Crowd port (2026-11-11): the scenario's hand-built teams enter the native crowd as any legacy grid Site does on bind
	# (crowd_fixture_port_guide); --grid keeps the retired army.
	if not OS.get_cmdline_user_args().has("--grid") and lab.crowd_site == null:
		lab.crowd_site = TerrainLab.CrowdSiteScript.new()
		lab.crowd_site.name = "CrowdSite"
		lab.add_child(lab.crowd_site)
		lab.crowd_site.setup(lab)
	if not OS.get_cmdline_user_args().has("--grid") and lab.crowd_site != null and not lab.crowd_site.active:
		var converted: Dictionary = lab.crowd_site.convert_existing()
		if converted.ok: converted = lab._region_write_converted_crowd_section()
		_check(converted.ok, "The original teams enter the native crowd: " + str(converted))
		# Consent and named work need the whole team standing (the crowd settle rule): the converted members walk to their
		# formation slots by the real rules first; the fixture waits with real points, as a player would.
		# The controlled head's own team holds where the fixture stationed the head (its HOLD centre is its deployment cell).
		var head: Dictionary = lab.crowd_site.siege_original_person(control)
		var head_team: Variant = lab.crowd_site.person_owner(control)
		if head_team != null and not head.is_empty():
			lab.crowd_site.set_formation_fields(int(head_team.formation_index), {"cx": head.cell.x + 0.5, "cy": head.cell.y + 0.5,
				"origin_x": head.cell.x + 0.5, "origin_y": head.cell.y + 0.5, "goal_x": head.cell.x + 0.5, "goal_y": head.cell.y + 0.5})
		var owners: Array = []
		for candidate: Variant in [lab.crowd_site.person_owner(int(team.combat_identity(0))), head_team]:
			if candidate != null and not owners.has(candidate): owners.append(candidate)
		var settle := 0
		var walking := func() -> bool:
			for owner: Variant in owners:
				if owner.moving_member_count() > 0: return true
			return false
		while (settle < 30 or walking.call()) and settle < 3600:
			var point: Dictionary = lab._advance_original_shared_step(TerrainLab.EXCHANGE_ACTION_STEP if lab.exchange_enabled else TerrainLab.ACTION_STEP)
			if not point.ok: break
			settle += 1
		_check(not owners.is_empty() and not walking.call(), "The converted original teams stand in formation")
	return {"lab": lab, "data": data, "controller": controller, "actions": controller.person_actions, "orders": controller.equipment_orders,
		"control": control, "executor": executor, "team": team, "row": team.combat_units[1], "nation": nation,
		"warehouse": warehouse, "smithy": smithy, "tannery": tannery, "center": str(founded.feature)}

func _earned_true_step(f: Dictionary) -> Dictionary:
	_check(Time.get_ticks_msec() < deadline, "Actual original common-point fixture remains inside its internal deadline")
	var slot: RegionSaveSlot = f.controller.region_slot
	var before = float(slot.control.logical_game_seconds) if slot != null else -1.0
	var point: Dictionary = {}
	var attempts = 0
	while true:
		point = f.lab._advance_original_shared_step(TerrainLab.EXCHANGE_ACTION_STEP if f.lab.exchange_enabled else TerrainLab.ACTION_STEP)
		_check(point.ok, "Original main point guard must succeed without suppressing canonical errors: " + str(point))
		if point.get("completed") == true: break
		_check(point.get("status") == "REGION_EVENT_PENDING" and float(point.get("game_seconds", -1)) == 0.0, "Only genuine original Region pending consumption may defer a point; no fake work time")
		attempts += 1
		_check(attempts < 200 and Time.get_ticks_msec() < deadline, "Original due Region event consumption is bounded inside the actual test deadline")
	_check(point.ok and point.get("completed") == true and float(point.game_seconds) > 0.0, "Original Lab performs one accepted work/body/fatigue/food/contact/endpoint point: " + str(point))
	if slot != null:
		_check(absf(float(slot.control.logical_game_seconds) - before - float(point.game_seconds)) < 0.000001, "Original Slot publishes exactly the same completed World seconds once")
	return point

func _earned_speed(f: Dictionary) -> void:
	while float(f.lab.simulation_speed) < 4.0: f.lab.change_simulation_speed(1)
	_check(float(f.lab.simulation_speed) == 4.0, "Original public speed control selects the supported scale4; no clock/elapsed assignment")

func _earned_bytes(f: Dictionary) -> PackedByteArray:
	return var_to_bytes([f.data.site, f.lab.character.capture_state(), f.team.combat_units, f.team.cells, f.actions._jobs.keys()])

func _earned_prepare(f: Dictionary, node: String, route: String = "default") -> void:
	_check(f.actions.prepare_scope_technology(f.control, f.executor, node, "n1", route).ok, "True current national research duty prepares the unknown node with the one actual original executor")
	_check(f.actions.request_scope_technology_consent(f.control, "nation", "n1", f.executor).ok, "The original independent person or living original team accepts the exact active research purpose")
	var project = Technology.active_project(f.nation.technology)
	_check(project.executor.person_id == f.executor and project.tech_id == node and project.receipts.is_empty() and project.budget.is_empty(), "First research starts with no output, payment or borrowed executor evidence")

func _earned_depot_grant(f: Dictionary, cap: Dictionary) -> void:
	var contact: Vector2i = f.data.cell_from_index(int(f.data.site.depot_cell)) + Vector2i.RIGHT
	_check(_earned_place_controlled(f.lab, contact), "The true controlled grantor reaches the actual original camp contact")
	var granted: Dictionary = f.actions.grant_scope_technology_budget(f.control, "nation", "n1", cap)
	_check(granted.ok, "The original camp grants an explicit finite material purpose; zero-material prior work is not a second debit: " + str(granted) + " cap=" + str(cap))

func _earned_road_preview(f: Dictionary, cell: Vector2i) -> Dictionary:
	for radius: int in range(20):
		for y: int in range(-radius, radius + 1):
			for x: int in range(-radius, radius + 1):
				if absi(x) + absi(y) != radius: continue
				var candidate = cell + Vector2i(x, y)
				if not f.data.contains(candidate) or not Settlement.cell_in_jurisdiction(f.data, candidate): continue
				var cells: Array[int] = [f.data.index(candidate)]
				var geometry = Runtime.preview_build(f.data, "road", cells, f.controller.reserves_cell, {"layout_version": 1, "quarter": 0, "owner_faction": 1})
				if not geometry.ok or not geometry.get("clearing", []).is_empty(): continue
				if int(geometry.entrance) == f.data.index(f.lab.character.terrain_cell): continue
				_check(float(geometry.work) == 3.0 and geometry.cost == {"stone": 1}, "Original one-cell road retains full180-second work and stone1 cost")
				geometry["fixture_cell"] = candidate
				return geometry
	_check(false, "Original finite scan must find one unchanged legal road in the current real jurisdiction")
	return {}

## Crowd: the named worker walks to its work slot by the crowd work rules itself (no hot-position write). As in play the
## team stays with its worker: its HOLD centre moves beside the work, so the captain stays within command presence (the
## team.work decider; crowd_fixture_port_guide). The grid keeps the original fixture placement.
func _at_feature(lab: TerrainLab, team: TerrainArmy, executor: int, key: String) -> Dictionary:
	if lab.crowd_site == null or not lab.crowd_site.active: return super._at_feature(lab, team, executor, key)
	var owner: Variant = lab.crowd_site.person_owner(executor)
	var task: Dictionary = owner._cold_get(owner.index_for_identity(executor), "work_task", {}) if owner != null else {}
	_check(task.get("version") == 3 and task.get("named") == true and task.get("target") == "feature:" + key, "Runtime published the true original named task in the same paid commit")
	# A large team (the forty-person N11 army) keeps its own ground clear of the workshop (_earned_team_aside); its captain
	# decides there, and the worker alone walks to its slot.
	if owner != null and task.has("work_cell") and owner.combat_units.size() <= 4:
		var work: Vector2i = lab.terrain.cell_from_index(int(task.work_cell))
		var centre := work + Vector2i(0, 3)
		if not lab.terrain.contains(centre) or not lab.terrain.is_walkable(centre): centre = work
		lab.crowd_site.set_formation_fields(int(owner.formation_index), {"cx": centre.x + 0.5, "cy": centre.y + 0.5,
			"origin_x": centre.x + 0.5, "origin_y": centre.y + 0.5, "goal_x": centre.x + 0.5, "goal_y": centre.y + 0.5})
	return task

## Crowd: the team's HOLD centre moves a few cells off a workshop so its standing bodies leave the work slots and paths open
## (a crowd body covers the cells beside it); the team walks there by the real rules and the fixture waits until it stands.
func _earned_team_aside(f: Dictionary, key: String) -> void:
	var lab: TerrainLab = f.lab
	if lab.crowd_site == null or not lab.crowd_site.active: return
	var owner: Variant = lab.crowd_site.person_owner(int(f.executor))
	if owner == null: return
	var entrance: Vector2i = f.data.cell_from_index(int(f.data.site.features[key].entrance))
	# An open 9x9 ground (no building, all walkable) 6-14 cells away holds a forty-person formation without pressing on walls.
	var centre := entrance
	var found := false
	for radius: int in range(6, 15):
		for dy: int in range(-radius, radius + 1):
			for dx: int in range(-radius, radius + 1):
				if found or maxi(absi(dx), absi(dy)) != radius: continue
				var spot := entrance + Vector2i(dx, dy)
				var open := true
				for oy: int in range(-4, 5):
					for ox: int in range(-4, 5):
						var c := spot + Vector2i(ox, oy)
						open = open and f.data.contains(c) and f.data.is_walkable(c) and int(f.data.feature_at[f.data.index(c)]) == 0
				if open: centre = spot; found = true
	lab.crowd_site.set_formation_fields(int(owner.formation_index), {"cx": centre.x + 0.5, "cy": centre.y + 0.5,
		"origin_x": centre.x + 0.5, "origin_y": centre.y + 0.5, "goal_x": centre.x + 0.5, "goal_y": centre.y + 0.5})
	for settle: int in 1200:
		if settle >= 4 and owner.moving_member_count() == 0: break
		if not lab._advance_original_shared_step(TerrainLab.EXCHANGE_ACTION_STEP if lab.exchange_enabled else TerrainLab.ACTION_STEP).ok: break
	_check(owner.moving_member_count() == 0, "Crowd team stands aside of the workshop: %d walking" % owner.moving_member_count())

## Crowd: wait with real points until the executor's team stands (the crowd settle rule named-work consent reads).
func _earned_team_still(f: Dictionary) -> void:
	var lab: TerrainLab = f.lab
	if lab.crowd_site == null or not lab.crowd_site.active: return
	var owner: Variant = lab.crowd_site.person_owner(int(f.executor))
	if owner == null: return
	for settle: int in 1200:
		if owner.moving_member_count() == 0: break
		if not lab._advance_original_shared_step(TerrainLab.EXCHANGE_ACTION_STEP if lab.exchange_enabled else TerrainLab.ACTION_STEP).ok: break
	_check(owner.moving_member_count() == 0, "Crowd team stands before the next named work: %d walking" % owner.moving_member_count())

func _earned_until_idle(f: Dictionary) -> void:
	var count = 0
	_earned_speed(f)
	while f.actions.is_busy(int(f.executor)) or f.controller.work_team.is_assigned(int(f.executor)):
		_earned_true_step(f)
		count += 1
		_check(count < 2000, "Original effective-work completion or REST recovery is finitely bounded")
		if count >= 2000: break # Report the bound once instead of running into the timeout.
	_check(not f.actions.is_busy(int(f.executor)) and not f.controller.work_team.is_assigned(int(f.executor)), "Original work owners release the real completed named task")

func _earned_cold(f: Dictionary, node: String, expected_known: bool = true) -> void:
	var source_fingerprint = f.data.fingerprint()
	var land_conditions = _earned_land_bytes(f.data)
	var captured: Dictionary = f.controller._capture_for_save()
	_check(captured.ok, "Original Controller captures the actual original people/items/tasks before strict cold validation")
	var path = "user://technology_first_%s_%d_%d.json" % [node, OS.get_process_id(), Time.get_ticks_usec()]
	var saved = Store.save(f.data, path)
	_check(saved.ok, "Original Store saves genuinely earned owner history: " + str(saved))
	# A pinned fixed-world Site saves only its fixed_base identity; rebuild that base from the
	# same original manifest, as the region tests do. Generated Sites never call the loader.
	var fixed_loader := func(saved_base: Dictionary) -> Dictionary:
		var source := RegionData.new()
		if not source.load_manifest(earned_out.path_join("manifest.json")).ok or not saved_base.get("site") is Array or saved_base.site.size() != 2:
			return Runtime.fail("SAVE_VERSION", "fixture fixed base source")
		var rebuilt: Dictionary = RegionRoute.fresh_fixed_base(source, Vector2i(int(saved_base.site[0]), int(saved_base.site[1])))
		if not bool(rebuilt.get("ok", false)) or not Store._same_fixed_base(rebuilt.get("base"), saved_base):
			return Runtime.fail("SAVE_VERSION", "fixture fixed base rebuild")
		return rebuilt
	var loaded = Store.load_site(path, fixed_loader)
	_check(loaded.ok and Technology.scope_known(loaded.data.site.equipment_nations.n1.technology, node) == expected_known, "Original JSON loader preserves exactly the actual partial/earned knowledge and accepted receipts: " + str(loaded))
	_check(loaded.data.fingerprint() == source_fingerprint and _earned_land_bytes(loaded.data) == land_conditions,
		"Original cold generated/fixed source and all five original land-condition arrays remain identical")
	_check(loaded.data.site.equipment_nations.n1.technology == f.nation.technology, "Original normalized cold Scope state equals the real accepted history")
	_check(DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK, "Only this test's unique temporary cold file is removed")

func _earned_finish() -> void:
	for lab: TerrainLab in earned_labs:
		if is_instance_valid(lab):
			for team: TerrainArmy in lab.combat_armies:
				team.controlled_person_query = Callable()
				team.person_busy_query = Callable()
				team.person_id_allocator = Callable()
				team.queue_free()
			_earned_nation_cleanup(lab)
	if earned_last_exists:
		var last = FileAccess.open(EarnedEntry.LAST_WORLD, FileAccess.WRITE)
		_check(last != null, "Original prior last-world preference can be restored")
		last.store_buffer(earned_last_bytes)
		last.close()
	elif FileAccess.file_exists(EarnedEntry.LAST_WORLD):
		_check(DirAccess.remove_absolute(ProjectSettings.globalize_path(EarnedEntry.LAST_WORLD)) == OK, "The test removes only its newly created last-world preference")
	TerrainArmy.release_contact_source()
