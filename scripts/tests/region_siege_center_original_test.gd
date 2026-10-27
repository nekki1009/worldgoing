extends "res://scripts/tests/region_controlled_death_restriction_test.gd"
## Reuses only the original pinned-map/restore-shell/isolated-IO helpers.
## Actual main and cached cold owners accrue capture through common shared steps.
## This covers the center's 59/59.x selected restore contract; it is not a full
## siege-arrival, all-phase materialize or main-menu input acceptance claim.
const Settlement = preload("res://scripts/terrain_lab/site_settlement.gd")
const Housing = preload("res://scripts/terrain_lab/site_housing.gd")
const GenesisPanel = preload("res://scripts/region_lab/region_travel_panel.gd")
var capture_scenes: Array[TerrainLab] = []
var capture_results: Array[Dictionary] = []
var center_owner: TerrainLab
var center_coordinate := Vector2i.ZERO
var center_house := ""
var center_prison_seat := ""
var center_office_holder := -1
var center_defender := -1
var center_founder := -1
var center_heir := -1
var center_attackers: TerrainArmy
var genesis_panel: GenesisPanel

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 360000
	fixture_land_condition_rule = "terrain_mapped_potential_v1" # Original founding needs mapped land.
	out = "res://.godot-temp/region_siege_center_original/run_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	last_world_exists = FileAccess.file_exists(Entry.LAST_WORLD)
	if last_world_exists: last_world_bytes = FileAccess.get_file_as_bytes(Entry.LAST_WORLD)
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if not finished and Time.get_ticks_msec() > deadline: _finish(false, "360-second original center deadline")
	return false

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	capture_results.append({"ok": condition, "check": message, "details": detail if not detail is Object else str(detail)})
	if not condition:
		failed = true
		push_error("REGION_SIEGE_CENTER_ORIGINAL_FAIL: " + message + " " + str(detail))
	return condition

func _shell() -> TerrainLab:
	var packed := load("res://scenes/terrain_lab/TerrainLab.tscn") as PackedScene
	if packed == null: return null
	var scene := packed.instantiate() as TerrainLab
	scene.restore_only = true
	scene.pause_when_unfocused = false
	scene.exchange_enabled = true
	scene.visible = false
	root.add_child(scene)
	_freeze(scene)
	capture_scenes.append(scene)
	return scene

func _run() -> void:
	RegionTravelSite.scene_handoff = false
	RegionRoute.clear_memory_cache()
	if not _write_manifest(): _finish(); return
	for spec: Dictionary in [{"mode": "live", "at": 59.0, "defender": false, "qualifier": "continue"},
		{"mode": "cold_exact", "at": 59.25, "defender": false, "qualifier": "continue"},
		{"mode": "cold_exact", "at": 59.25, "defender": true, "qualifier": "unarmed_civilian"},
		{"mode": "cold_exact", "at": 59.25, "defender": false, "qualifier": "knocked_defender"},
		{"mode": "cold_exact", "at": 59.25, "defender": false, "qualifier": "captive_defender"},
		{"mode": "cold_exact", "at": 59.25, "defender": false, "qualifier": "same_faction_replacement"},
		{"mode": "cold_exact", "at": 59.25, "defender": false, "qualifier": "invalid_attackers"},
		{"mode": "cold_exact", "at": 59.25, "defender": false, "qualifier": "multiple_attackers"}]:
		if not await _case(spec): _finish(); return
	_finish()

func _case(spec: Dictionary) -> bool:
	center_coordinate = Vector2i.ZERO if str(spec.mode) == "live" else Vector2i(1, 0)
	if not _open_center_world(center_coordinate): return false
	center_owner = lab
	if not _center_fixture(center_owner, str(spec.mode) != "cold_exact"): return false
	if str(spec.mode) == "cold_exact":
		if not _birth_successor(): return false
		# A cold remote Site has no people, so its defender settlement is founded while that Site
		# is hot; the founder then hands control to a living family member who leaves for the
		# source Site (Nekki 2026-10-23 decision A). The founder stays as the cold defender.
		if not await _hand_over_and_leave(Vector2i.ZERO): return false
		var created: Dictionary = lab._region_gameplay_owner_lab(Grid.site_id(str(slot.pin.atlas_id), center_coordinate), "cold_exact")
		if not _check(created.ok and created.lab is TerrainLab, "actual cached original cold factory completes", created): return false
		center_owner = created.lab
		_freeze(center_owner)
		if not _check(center_owner.actor_present(center_owner.character) and center_owner.character.person_id == center_founder,
			"the living founder remains the cold defender Site's original person", center_owner.character.person_id): return false
		if not _deploy_center_attackers(center_owner): return false
	center_defender = -1
	if str(spec.qualifier) in ["knocked_defender", "captive_defender"]:
		if not _birth_original_knocked_defender(): return false
		if str(spec.qualifier) == "captive_defender" and not await _pay_original_capture(): return false
	var due: Dictionary = slot.consume_due_region_events()
	if not _check(due.ok and due.get("complete", false), "real same-point scheduled owners consume before positive capture", due): return false
	if not await _drive_capture(float(spec.at)): return false
	var source_center: Dictionary = center_owner.terrain.site.settlement
	var source_fall: Dictionary = source_center.fall_record.duplicate(true)
	var source_elapsed: float = center_owner.site_controller._settlement_elapsed
	var source_game := float(slot.control.logical_game_seconds)
	var source_action := float(slot.control.fire_clock.action_seconds)
	var source_sequence := int(slot.control.fire_clock.sequence)
	var source_data_instance := center_owner.terrain.get_instance_id()
	if not _check(int(source_center.owner_faction) == 1 and int(source_fall.contest_faction) == 2
		and absf(float(source_fall.contest_seconds) - float(spec.at)) <= EPS
		and source_elapsed < 0.25 and center_owner.site_controller._settlement_game_seconds == 0.0,
		"actual original capture reaches 59/59.x while quarter-second UI cadence is incomplete", {"spec": spec, "fall": source_fall, "actual_ui_elapsed": source_elapsed}): return false
	if bool(spec.defender):
		var defender: Dictionary = center_owner.site_controller.person_actions._person(center_founder, false)
		if not _check(not defender.is_empty() and defender.owner == center_owner.character
			and center_owner.character.military_role == "civilian" and float(defender.hp) > 0.0 and float(defender.ko) <= 0.0,
			"actual ordinary civilian defender supplies original conscious qualification", defender.get("person_id")): return false
		if not _check(center_owner.character.place(Vector2i(19, 19), true), "same original defender enters actual center zone"): return false
		if not _check(str(center_owner.character.exchange_stats().weapon) == "none",
			"The original conscious civilian has no equipped weapon after one actual holder transfer"): return false
		var sample := Settlement.capture_sample(center_owner)
		if not _check(int(sample.attacker) == -1 and source_center.fall_record == source_fall,
			"new original occupancy blocks future capture without rewriting the old paid interval", sample): return false
	if not _change_original_capture_qualification(spec, source_fall): return false
	var checkpoint: Dictionary = controller.checkpoint_region_internal("region_checkpoint", true)
	if not _check(checkpoint.ok, "original Slot checkpoints active plus cached center at one complete endpoint", checkpoint): return false
	var generation := int(slot._marker.generation)
	var reopened := RegionSaveSlot.new()
	var independent: Dictionary = reopened.open_map(slot.source, world_id, "main")
	if not _check(independent.ok and int(reopened._marker.generation) == generation,
		"new original Slot reopens the same complete selected epoch", independent): return false
	var main_read: Dictionary = reopened.open_site(Vector2i.ZERO)
	if not _check(main_read.ok and main_read.data.site.has("region_snapshot"), "mode-aware selected open preserves full original active owner", main_read.get("code")): return false
	var resumed_main := _restore_selected(main_read.data, reopened, false)
	if resumed_main == null: return false
	var resumed_center: TerrainLab = resumed_main
	if center_coordinate != Vector2i.ZERO:
		var center_read: Dictionary = reopened.open_site(center_coordinate)
		if not _check(center_read.ok and center_read.data.site.has("region_snapshot"), "cold selected open retains full original center graph", center_read.get("code")): return false
		resumed_center = _restore_selected(center_read.data, reopened, true)
		if resumed_center == null: return false
		reopened._region_original_labs[str(resumed_center.terrain.site.id)] = resumed_center
		var activated: Dictionary = resumed_main._region_gameplay_owner_lab(str(resumed_center.terrain.site.id), "cold_exact")
		if not _check(activated.ok and activated.lab == resumed_center, "cold positive restore activates its own actual complete original owner", activated.get("code")): return false
	if not _check(float(reopened.control.logical_game_seconds) == source_game
		and float(reopened.control.fire_clock.action_seconds) == source_action and int(reopened.control.fire_clock.sequence) == source_sequence
		and resumed_center.terrain.site.settlement.fall_record == source_fall
		and absf(resumed_center.site_controller._settlement_elapsed - source_elapsed) <= EPS
		and resumed_center.site_controller._settlement_game_seconds == 0.0,
		"successful original full bind preserves capture/qualification/cadence at the exact selected World/ACTION/sequence"): return false
	lab = resumed_main
	controller = resumed_main.site_controller
	slot = reopened
	center_owner = resumed_center
	if bool(spec.defender) or str(spec.qualifier) == "invalid_attackers":
		var prefix: Dictionary = lab._advance_original_shared_step(1.0 / 1200.0)
		if not _check(prefix.ok and prefix.get("completed", false) and float(prefix.game_seconds) > 0.0,
			"original common main accepts a genuine future interval after defender restore", prefix): return false
		if not _check(int(center_owner.terrain.site.settlement.owner_faction) == 1
			and int(center_owner.terrain.site.settlement.fall_record.contest_faction) == -1
			and float(center_owner.terrain.site.settlement.fall_record.contest_seconds) == 0.0,
			"restored original qualification interrupts only the future sample"): return false
	elif str(spec.qualifier) == "multiple_attackers":
		var prefix: Dictionary = lab._advance_original_shared_step(1.0 / 1200.0)
		var final_contest: Dictionary = center_owner.terrain.site.settlement.fall_record
		if not _check(prefix.ok and prefix.get("completed", false) and float(prefix.game_seconds) > 0.0
			and int(center_owner.terrain.site.settlement.owner_faction) == 1 and int(final_contest.contest_faction) == 3
			and float(final_contest.contest_seconds) > 0.0 and float(final_contest.contest_seconds) < 1.0,
			"A genuinely larger third faction starts only its own new future contest through the original rule", prefix): return false
	else:
		var final_sample := Settlement.capture_sample(center_owner)
		if not await _drive_capture(Settlement.CAPTURE_SECONDS): return false
		var final: Dictionary = center_owner.terrain.site.settlement
		var leader := int(final_sample.leader)
		if not _check(int(final.owner_faction) == 2 and int(final.fall_record.last_fall.get("from", -1)) == 1
			and int(final.fall_record.last_fall.get("to", -1)) == 2
			and int(SiteOffices.head_position(final.offices).holder) == leader
			and int(center_owner.terrain.site.features[str(final.center_id)].owner_faction) == 2,
			"one original fall transaction changes actual center and appoints the actual occupying leader", final.fall_record): return false
		if not _check(int(center_owner.terrain.site.features[center_house].owner_faction) == 2
			and not center_owner.terrain.site.housing.has(str(center_founder)) and int(SiteOffices.position(final.offices, center_prison_seat).holder) == -1
			and not final.offices.positions.any(func(seat: Dictionary) -> bool: return int(seat.holder) == center_office_holder),
			"The same original transaction transfers its paid house, releases the real registered resident and vacates the old actual officer"): return false
		var unchanged := var_to_bytes([final, center_owner.terrain.site.features, center_owner.terrain.site.housing])
		var retry: Dictionary = center_owner.site_controller.settle_settlement_endpoint()
		if not _check(retry.ok and unchanged == var_to_bytes([final, center_owner.terrain.site.features, center_owner.terrain.site.housing]),
			"original zero-time fall retry cannot repeat the real transfer", retry): return false
	report["%s_%.2f_%s" % [str(spec.mode), float(spec.at), str(spec.qualifier)]] = {
		"actual_checkpoint_generation": generation, "actual_source_world": source_game,
		"actual_source_action": source_action, "actual_source_sequence": source_sequence,
		"paid_source_fall": source_fall, "actual_ui_elapsed": source_elapsed,
		"selected_restore_completed": true, "source_data_instance_id": source_data_instance, "restored_data_instance_id": center_owner.terrain.get_instance_id(), "original_center_id": str(center_owner.terrain.site.settlement.center_id),
		"actual_house_id": center_house, "actual_old_office_holder": center_office_holder, "actual_defender_id": center_defender,
		"final_fall": center_owner.terrain.site.settlement.fall_record.duplicate(true)}
	return true

func _open_center_world(start: Vector2i, prefix: String = "r0_center") -> bool:
	lab = _shell()
	if not _check(lab != null, "actual original restore shell exists"): return false
	controller = lab.site_controller
	var archive := TerrainGenerator.generate(TerrainPreset.Kind.PLAINS, 12345, {"size": Vector2i(32, 32)})
	Env.initialize(archive, "center-original:archive")
	lab.bind_terrain(archive)
	lab.restore_only = false
	controller.save_root = out.path_join("archive_%d" % capture_scenes.size())
	world_id = "%s_%d_%d" % [prefix, OS.get_process_id(), Time.get_ticks_usec()]
	var opened: Dictionary = controller.open_fixed_world(manifest_path, world_id, "main", start, true)
	if not _check(opened.ok, "original Controller creates and live-binds a genuine pinned world", opened): return false
	_freeze(lab)
	slot = controller.region_slot
	var wired := lab._wire_region_gameplay_adapters(slot)
	return _check(wired.ok, "same original Slot and owners wire", wired)

func _genesis_cells(near: Vector2i, count: int, source_owner: TerrainLab = null) -> Array[Vector2i]:
	var original: TerrainLab = lab if source_owner == null else source_owner
	var cells: Array[Vector2i] = []
	# Existing callers retain their exact radius. A different original Site may
	# have water at the old gate hint; inspect only that Site's genuine ground.
	var limit: int = 12 if source_owner == null else maxi(original.terrain.size.x, original.terrain.size.y) + 1
	for radius: int in range(1, limit):
		for y: int in range(-radius, radius + 1):
			for x: int in range(-radius, radius + 1):
				if source_owner != null and absi(x) != radius and absi(y) != radius: continue
				var cell := near + Vector2i(x, y)
				if cells.size() < count and original.terrain.contains(cell) and original.terrain.is_walkable(cell) and not cells.has(cell) and cell != original.character.terrain_cell:
					if source_owner != null:
						if original._armies_block_cell(cell): continue
						var occupied: bool = false
						for actor: TerrainTestCharacter in original.combat_actors:
							if actor.occupies_cell(cell): occupied = true
						if occupied: continue
					cells.append(cell)
					if source_owner != null and cells.size() == count: return cells
	return cells

## The successor's real team is born before any fixture combat or work starts.
func _birth_successor() -> bool:
	var cells := _genesis_cells(lab.character.terrain_cell + Vector2i(3, 0), 2)
	if not _check(cells.size() == 2, "actual free cells beside the founder", cells): return false
	# The successor is the defender's own living family, so it shares the founder's faction.
	var side: Dictionary = {"prefix": "friendly", "count": 2, "slot_count": 2, "female_count": 0, "faction": int(lab.character.faction_id), "training": 0.0,
		"role": "combat", "troop_type": "melee_infantry", "attack": false, "cart_count": 0, "wagon_count": 0, "abilities": {}, "ai_enabled": false}
	var sides: Array[Dictionary] = [side]
	# Slots 0-2 are the scenario's attackers, officials and defenders; the successor uses its own.
	var born: Dictionary = lab._deploy_trial_teams(sides, [cells], 4)
	if not _check(born.ok, "original named genesis births the successor's real team", born): return false
	var team: TerrainArmy = null
	for candidate: TerrainArmy in lab.combat_armies:
		if candidate.combat_enabled and candidate.cells.has(cells[0]): team = candidate
	if not _check(team != null, "the successor's original team is present"): return false
	var heir := team.combat_identity(team.formal_commander)
	center_heir = heir
	return true

## The founder hands control to a living family member born beside them, who travels to
## destination through the original Region route; lab/controller/slot then belong to it.
func _hand_over_and_leave(destination: Vector2i) -> bool:
	var head := lab.controlled_person_id()
	var heir := center_heir
	var site_id := str(lab.terrain.site.id)
	var family = controller.family_continuity
	var registered: Dictionary = family.register_members([{"site_id": site_id, "person_id": head, "path": "", "label": "創辦人", "age_years": -1},
		{"site_id": site_id, "person_id": heir, "path": "", "label": "接班人", "age_years": -1}], true)
	if not _check(registered.ok, "original family registers the founder and the successor", registered): return false
	var appointed: Dictionary = family.appoint_head(head, head)
	if not _check(appointed.ok, "original head appointment gives the founder family authority", appointed): return false
	var due: Dictionary = slot.consume_due_region_events()
	if not _check(due.ok and bool(due.get("complete", false)), "original due endpoints finish before the handover", due): return false
	var settled: Dictionary = controller.checkpoint_region_internal("region_checkpoint")
	if not _check(settled.ok, "original complete checkpoint captures the founded Site before the handover", settled): return false
	var handed: Dictionary = family.handover(head, site_id, heir)
	if not _check(handed.ok and lab.controlled_person_id() == heir, "original living handover gives control to the successor", handed): return false
	lab.terrain.site["paused"] = false
	paused = false
	var departed_lab := lab
	var departed: Dictionary = RegionTravelSite.depart(controller)
	if not _check(departed.ok, "the successor departs through the original Region travel", departed): return false
	if is_instance_valid(genesis_panel): genesis_panel.free()
	genesis_panel = GenesisPanel.new()
	root.add_child(genesis_panel)
	genesis_panel.setup(genesis_panel)
	genesis_panel.set_process(false)
	var opened: Dictionary = genesis_panel.start({"world_id": world_id, "slot_id": "main", "manifest": manifest_path})
	if not _check(opened.ok and is_instance_valid(genesis_panel._original_adapter_host), "production travel panel restores the original map host", opened): return false
	lab = genesis_panel._original_adapter_host
	controller = lab.site_controller
	slot = genesis_panel.slot
	var selected: Dictionary = slot.region_travel_party()
	if not _check(selected.ok, "original map selects the successor's party", selected): return false
	var current: Dictionary = slot.region_travel_status()
	var route_context: Dictionary = slot.prepare_region_route_context(null, selected.party)
	if not _check(route_context.ok, "original party route context", route_context): return false
	var search := RegionRoute.Search.new()
	search.source = slot.source
	search.start_site = current.site
	search.start_component = int(current.component)
	search.goal_site = destination
	search.context = route_context.context
	var route: Dictionary = search.run()
	if not _check(route.ok, "original route producer reaches the source Site", route): return false
	var planned: Dictionary = slot.set_region_travel_plan(route.steps)
	if not _check(planned.ok, "original Slot admits the successor's route", planned): return false
	for iteration: int in range(18000):
		current = slot.region_travel_status()
		if not _check(current.ok, "the successor's route has one original status", current): return false
		if bool(current.get("arrived", false)): break
		var advanced: Dictionary = slot.advance_region_travel(37)
		if not _check(advanced.ok, "original map caller advances one common interval", advanced): return false
		if bool(advanced.get("arrived", false)): break
		if iteration % 60 == 0: await process_frame
	if not _check(bool(slot.region_travel_status().get("arrived", false)), "the successor genuinely arrives at the source Site"): return false
	var stored: Dictionary = slot.checkpoint_region_travel()
	if not _check(stored.ok, "the original travel publisher stores the arrived party", stored): return false
	# The departed scene's own Controller opens the arrival, as the real world-open path does.
	var visible := departed_lab
	var visible_open: Dictionary = visible.site_controller.open_fixed_world(manifest_path, world_id, "main", Vector2i(-1, -1), false)
	for retry: int in range(200000):
		if str(visible_open.get("code", "")) != "PENDING" and not visible.site_controller.region_operation_pending(): break
		visible_open = visible.site_controller.resume_region_operation()
		if retry % 60 == 0:
			await process_frame
			if finished or not is_instance_valid(visible): return false # The deadline already finished the test and freed its scenes.
	if not _check(visible_open.ok and bool(visible_open.get("arrived", false)), "production world-open binds the arrived source Site", visible_open): return false
	_freeze(visible)
	lab = visible
	controller = visible.site_controller
	slot = controller.region_slot
	var wired := lab._wire_region_gameplay_adapters(slot)
	if not _check(wired.ok, "arrived Site wires the same original Slot owners", wired): return false
	return _check(lab.controlled_person_id() == heir and str(slot.control.active_site_id) == str(lab.terrain.site.id), "the successor controls the arrived source Site")

func _center_fixture(original: TerrainLab, with_attackers: bool = true) -> bool:
	var data := original.terrain
	for key: String in data.resource_base: Env.change(data, key, {"cleared": true, "remaining": 0})
	data.site.capacity = 100000
	for item: String in Env.ITEM_NAMES: data.site.inventory[item] = 1000
	if not _check(SiteRuntime.initialize_item_storage(data.site).ok, "original depot owns explicitly authored initial fixture stock"): return false
	# New worlds birth the starter in faction 0; this scenario's defender side is faction 1 (as the
	# phase scenario explicitly sets its founder faction).
	original.character.faction_id = 1
	if not _check(original.character.place(Vector2i(20, 15), true), "actual founder is near the true center build"): return false
	var layout := SiteRuntime.building_cells(data, "settlement_center", Vector2i(20, 20), Vector2i(5, 5), {"layout_version": 1, "quarter": 0, "owner_faction": 1})
	if not _check(layout.ok, "original complete center geometry is legal", layout): return false
	var cells: Array[int] = []; cells.assign(layout.cells)
	center_founder = original.controlled_person_id()
	var founded := Settlement.found(original, original.controlled_person_id(), cells, {"layout_version": 1, "quarter": 0}, Callable(), "原中心測試")
	if not _check(founded.ok, "original founder reserves real center materials", founded): return false
	var feature: Dictionary = data.site.features[str(founded.feature)]
	var task := {"version": 2, "zone": -1, "target": "feature:" + str(founded.feature), "action": "construct",
		"work_cell": int(feature.entrance), "cell": int(feature.entrance), "mode": "work", "progress": 0.0, "status": "", "work_slot": -1}
	SiteRuntime._feature_work(data, str(founded.feature), float(feature.work), Callable(), Callable(), task, {}, 20, 1)
	if not _check(str(feature.stage) == "complete" and int(data.site.settlement.level) == 1,
		"original paid work completes the real center"): return false
	if not _prepare_original_house_and_office(original): return false
	var actual_player: Dictionary = original.site_controller.person_actions._person(original.controlled_person_id())
	var unarm: Array[String] = []
	for slot_name: String in ["weapon", "shield"]:
		if actual_player.holder.equipped.has(slot_name): unarm.append(str(actual_player.holder.equipped[slot_name]))
	if not unarm.is_empty():
		var stowed := SiteRuntime.transfer_items(data, actual_player.holder, actual_player.cargo, data.site.depot_items,
			data.site.inventory, {}, unarm, int(actual_player.holder.version), int(data.site.depot_items.version), int(data.site.capacity))
		if not _check(stowed.ok, "Original item transaction moves the founder's real weapon/shield into the actual depot", stowed): return false
		if not _check(original.site_controller.person_actions.equipment_changed.is_valid(), "Original equipment presentation callback is wired"): return false
		original.site_controller.person_actions.equipment_changed.call(original.controlled_person_id())
	if not _check(original.character.place(Vector2i(80, 80), true), "actual founder leaves capture zone before source interval"): return false
	return _deploy_center_attackers(original) if with_attackers else true

## The attackers arrive at the real center last: a cold genesis deploys them only after the
## successor has left, so no capture accrues during that journey.
func _deploy_center_attackers(original: TerrainLab) -> bool:
	var data := original.terrain
	var attackers := original.army
	if attackers.combat_enabled or not attackers.combat_units.is_empty():
		# A restored cold owner already fills its first slot with the saved officials.
		attackers = null
		for slot_index: int in range(original.combat_armies.size() + 1):
			original._ensure_army_slots(slot_index + 1)
			var candidate: TerrainArmy = original.combat_armies[slot_index]
			if not candidate.combat_enabled and candidate.combat_units.is_empty():
				attackers = candidate
				break
		if not _check(attackers != null, "a free original Army slot holds the arriving attackers"): return false
		attackers.team_id = original._next_army_identity() # A new formation identity, not a saved one.
	center_attackers = attackers
	attackers.faction_id = 2
	attackers.roster_size = 2
	var positions: Array[Vector2i] = [Vector2i(20, 18), Vector2i(21, 18)]
	if not _check(attackers.deploy_at(data, null, null, positions) and attackers.enable_combat(false), "original actual attackers deploy in the real zone"): return false
	attackers.set_process(false)
	original.site_controller.initialize_team_items(attackers)
	data.site.army_next_team = original._next_army_identity()
	var sample := Settlement.capture_sample(original)
	return _check(int(sample.attacker) == 2 and int(data.site.settlement.fall_record.contest_faction) == -1
		and float(data.site.settlement.fall_record.contest_seconds) == 0.0, "source has actual qualified original attackers and no fabricated accrued timer", sample)

func _prepare_original_house_and_office(original: TerrainLab) -> bool:
	var data := original.terrain
	var layout := SiteRuntime.building_cells(data, "house", Vector2i(27, 22), Vector2i.ONE,
		{"layout_version": 1, "quarter": 0, "owner_faction": 1, "variant": "standard"})
	if not _check(layout.ok, "Original house layout is legal in the real center jurisdiction", layout): return false
	var cells: Array[int] = []; cells.assign(layout.cells)
	var built := SiteRuntime.request_build(data, "house", cells, Callable(),
		{"layout_version": 1, "quarter": 0, "owner_faction": 1, "variant": "standard"})
	if not _check(built.ok, "Actual original house construction pays its authored stock", built): return false
	center_house = str(built.feature)
	var feature: Dictionary = data.site.features[center_house]
	var task := {"version": 2, "zone": -1, "target": "feature:" + center_house, "action": "construct",
		"work_cell": int(feature.entrance), "cell": int(feature.entrance), "mode": "work", "progress": 0.0, "status": "", "work_slot": -1}
	SiteRuntime._feature_work(data, center_house, float(feature.work), Callable(), Callable(), task, {}, 20, 1)
	if not _check(str(feature.stage) == "complete" and Settlement.feature_in_jurisdiction(data, feature), "Real paid house finishes under the original Runtime"): return false
	var assigned := Housing.assign(original, original.controlled_person_id(), center_house, original.controlled_person_id())
	if not _check(assigned.ok and data.site.housing.has(str(original.controlled_person_id())), "Original living founder registers a real original housing relation", assigned): return false
	original._ensure_army_slots(2)
	var officials: TerrainArmy = original.combat_armies[1]
	officials.faction_id = 1
	officials.roster_size = 2
	var positions: Array[Vector2i] = [Vector2i(75, 75), Vector2i(76, 75)]
	if not _check(officials.deploy_at(data, null, null, positions) and officials.enable_combat(false), "Original local officers birth outside the actual capture jurisdiction"): return false
	original.site_controller.initialize_team_items(officials)
	center_office_holder = officials.combat_identity(0)
	var offices := Settlement.offices(original)
	center_prison_seat = str(offices.duties["settlement.prison"])
	var appointed := Settlement.apply_office_plan(original, original.controlled_person_id(), int(offices.revision),
		[{"op": "appoint", "position_id": center_prison_seat, "person_id": center_office_holder}])
	return _check(appointed.ok and int(SiteOffices.position(data.site.settlement.offices, center_prison_seat).holder) == center_office_holder,
		"Original founder lawfully appoints the real old faction office holder", appointed)

func _birth_original_knocked_defender() -> bool:
	center_owner._ensure_army_slots(3)
	var defenders: TerrainArmy = center_owner.combat_armies[2]
	defenders.faction_id = 1
	defenders.roster_size = 2
	var positions: Array[Vector2i] = [Vector2i(70, 70), Vector2i(20, 19)]
	if not _check(defenders.deploy_at(center_owner.terrain, null, null, positions) and defenders.enable_combat(false), "Actual defender row births in the true capture zone"): return false
	center_owner.site_controller.initialize_team_items(defenders)
	center_defender = defenders.combat_identity(1)
	var civilian := defenders.set_military_role(center_defender, "civilian")
	if not _check(civilian.ok, "Original role transaction removes soldier qualification from the actual defender", civilian): return false
	defenders.apply_unit_contact(1, {"result": {"hp": 1.0, "stun": 110.0, "guard_break": false}, "shield": false, "environmental": true})
	center_owner.terrain.site.army_next_team = center_owner._next_army_identity()
	var person: Dictionary = center_owner.site_controller.person_actions._person(center_defender, false)
	return _check(float(person.hp) > 0.0 and float(person.ko) > 0.0 and not bool(person.captive)
		and int(Settlement.capture_sample(center_owner).attacker) == 2,
		"Actual original contact causes knockout and the existing center rule admits capture", {"identity": center_defender, "ko": person.get("ko")})

func _pay_original_capture() -> bool:
	var executor := center_attackers.combat_identity(0)
	var started: Dictionary = center_owner.site_controller.person_actions.begin_capture(executor, center_defender, executor)
	if not _check(started.ok, "Original person action begins lawful custody of the actual knocked defender", started): return false
	var count := 0
	var paid_action := 0.0
	while center_owner.site_controller.person_actions._jobs.has(str(executor)):
		if count >= 3000 or Time.get_ticks_msec() > deadline: return _check(false, "Actual custody did not finish within the common-step bound")
		var step: Dictionary = lab._advance_original_shared_step(TerrainLab.EXCHANGE_ACTION_STEP)
		if not _check(step.ok and step.get("completed", false) and float(step.action_seconds) > 0.0, "Original common step pays the custody work and all owner endpoints", step): return false
		paid_action += float(step.action_seconds)
		count += 1
		if count % 60 == 0: await process_frame
	var person: Dictionary = center_owner.site_controller.person_actions._person(center_defender, false)
	return _check(bool(person.captive) and center_owner.terrain.site.captivity.has(str(center_defender))
		and paid_action >= float(started.seconds) - EPS and int(Settlement.capture_sample(center_owner).attacker) == 2,
		"Actual paid custody creates its original holder/supply reference and never becomes a capture blocker", {"paid_action": paid_action, "custody": center_owner.terrain.site.captivity.get(str(center_defender), {})})

func _change_original_capture_qualification(spec: Dictionary, paid_fall: Dictionary) -> bool:
	var qualifier := str(spec.qualifier)
	if qualifier in ["knocked_defender", "captive_defender"]:
		var defender: Dictionary = center_owner.site_controller.person_actions._person(center_defender, false)
		if not _check(not defender.is_empty() and (float(defender.ko) > 0.0 if qualifier == "knocked_defender" else bool(defender.captive))
			and int(Settlement.capture_sample(center_owner).attacker) == 2, "True original KO/custody qualification remains correct at 59.x", qualifier): return false
	if qualifier in ["same_faction_replacement", "invalid_attackers"]:
		if qualifier == "invalid_attackers":
			var demoted := center_attackers.set_military_role(center_attackers.combat_identity(1), "civilian")
			if not _check(demoted.ok, "Original remaining attacker changes its real role before the next sample", demoted): return false
		center_attackers.apply_unit_contact(0, {"result": {"hp": 1.0, "stun": 110.0, "guard_break": false}, "shield": false, "environmental": true})
		var sample := Settlement.capture_sample(center_owner)
		if not _check(int(sample.attacker) == (2 if qualifier == "same_faction_replacement" else -1)
			and center_owner.terrain.site.settlement.fall_record == paid_fall,
			"Actual replacement or loss of qualification never resamples the old paid interval", sample): return false
	if qualifier == "multiple_attackers":
		center_owner._ensure_army_slots(3)
		var third: TerrainArmy = center_owner.combat_armies[2]
		third.faction_id = 3
		third.roster_size = 3
		var positions: Array[Vector2i] = [Vector2i(22, 18), Vector2i(23, 18), Vector2i(24, 18)]
		if not _check(third.deploy_at(center_owner.terrain, null, null, positions) and third.enable_combat(false), "A real third faction births its own original three qualified rows"): return false
		center_owner.site_controller.initialize_team_items(third)
		center_owner.terrain.site.army_next_team = center_owner._next_army_identity()
		if not _check(int(Settlement.capture_sample(center_owner).attacker) == 3
			and center_owner.terrain.site.settlement.fall_record == paid_fall,
			"Original multi-faction rule selects actual larger faction while retaining the old paid sample"): return false
	return true

func _drive_capture(target: float) -> bool:
	var steps := 0
	while int(center_owner.terrain.site.settlement.owner_faction) == 1:
		var accrued := float(center_owner.terrain.site.settlement.fall_record.contest_seconds)
		if target < Settlement.CAPTURE_SECONDS and accrued >= target - EPS: break
		if steps >= 12000 or Time.get_ticks_msec() > deadline: return _check(false, "bounded original capture progress did not complete", target)
		var maximum := TerrainLab.EXCHANGE_ACTION_STEP if lab.exchange_enabled else TerrainLab.ACTION_STEP
		var tactical := minf(maximum, float(lab.terrain.site.get("combat_left", 0.0)))
		var actual_originals: Array[TerrainLab] = [lab]
		for owner: String in slot._region_original_labs:
			var actual: TerrainLab = slot._region_original_labs[owner]
			if actual != lab: actual_originals.append(actual)
		for actual: TerrainLab in actual_originals:
			var demand := minf(maximum, float(actual.terrain.site.get("combat_left", 0.0)))
			if actual._siege_tactical_active() or actual._fire_activity() or actual._region_melee_tactical_demand(): demand = maximum
			tactical = maxf(tactical, demand)
		tactical = RegionSaveSlot.GameplayClock.tactical_seconds(slot.region_registry(), float(slot.control.fire_clock.action_seconds), maximum, tactical)
		var remaining := target - accrued
		# These are the same readonly original GAME/ACTION conversion and real
		# owner demands used by the common producer. The producer still selects
		# and clips the accepted interval, including a real zero-time completion.
		var requested := maximum
		if remaining > TerrainLab.ACTION_TIME_EPSILON:
			requested = minf(maximum, RegionSaveSlot.GameplayClock.action_for_game(remaining, lab.simulation_speed, tactical))
		var result: Dictionary = lab._advance_original_shared_step(requested)
		if result.get("ok", false) and str(result.get("status", "")) == "REGION_EVENT_PENDING" and int(center_owner.terrain.site.settlement.owner_faction) == 1:
			# A due Region event (e.g. the arrived party's scheduled evaluation) is consumed by the
			# same original zero-time consumer the map caller uses; no interval is paid.
			var consumed: Dictionary = slot.consume_due_region_events()
			if not _check(consumed.ok, "original zero-time consumer takes the due Region event", consumed): return false
			steps += 1
			continue
		var paid: bool = result.get("ok", false) and result.get("completed", false) and float(result.get("action_seconds", 0.0)) > 0.0 and float(result.get("game_seconds", 0.0)) > 0.0
		var actual_zero_fall: bool = result.get("ok", false) and not result.get("completed", false) and target == Settlement.CAPTURE_SECONDS and int(center_owner.terrain.site.settlement.owner_faction) == 2 and float(result.get("action_seconds", 0.0)) == 0.0 and float(result.get("game_seconds", 0.0)) == 0.0
		if not _check(paid or actual_zero_fall, "actual common producer pays one interval or consumes its real completed center endpoint", result): return false
		steps += 1
		if steps % 60 == 0: await process_frame
	var reached: bool = int(center_owner.terrain.site.settlement.owner_faction) == 2 if target == Settlement.CAPTURE_SECONDS else absf(float(center_owner.terrain.site.settlement.fall_record.contest_seconds) - target) <= EPS
	return _check(reached, "original source reaches the requested actual capture observation", {"target": target, "steps": steps, "fall": center_owner.terrain.site.settlement.fall_record})

func _restore_selected(data: TerrainData, reopened: RegionSaveSlot, cold_mode: bool) -> TerrainLab:
	var scene := _shell()
	if not _check(scene != null, "fresh actual original restore scene exists"): return null
	var prepared := scene.prepare_selected_region_owner_restore(data, reopened)
	if not _check(prepared.ok, "original selected private preflight validates whole actual owner graph", prepared.get("code")): return null
	scene.restore_only = cold_mode
	scene.site_controller.region_slot = reopened
	scene.bind_terrain(prepared.data, prepared)
	_freeze(scene)
	var actual := scene.region_bind_receipt(prepared.data)
	if not _check(actual.ok and actual.complete and actual.owners_restored and actual.effects_complete
		and str(actual.backend) == "gd", "positive selected bind completes all actual original owners", actual): return null
	return scene

func _finish(ok: bool = true, message: String = "") -> void:
	if finished: return
	finished = true
	failed = failed or not ok
	if not message.is_empty(): printerr(message)
	paused = false
	if is_instance_valid(genesis_panel): genesis_panel.free()
	for scene: TerrainLab in capture_scenes:
		if is_instance_valid(scene): scene.free()
	var current: Variant = JSON.parse_string(FileAccess.get_file_as_string(Entry.LAST_WORLD)) if FileAccess.file_exists(Entry.LAST_WORLD) else null
	if current is Dictionary and str(current.get("world_id", "")).begins_with("r0_center_%d_" % OS.get_process_id()):
		if last_world_exists:
			var restore := FileAccess.open(Entry.LAST_WORLD, FileAccess.WRITE); restore.store_buffer(last_world_bytes); restore.close()
		else: DirAccess.remove_absolute(ProjectSettings.globalize_path(Entry.LAST_WORLD))
	TerrainArmy.release_contact_source()
	var evidence := {"failed": failed, "checks": checks, "cases": report, "checks_evidence": capture_results,
		"scope": "actual center 59/59.x prefix, original unarmed/civilian/KO/custody/attacker replacement/multiple factions, house/offices single transfer, complete selected positive restore; no body-age invention, full C01/C09 or siege-arrival claim"}
	var file := FileAccess.open(out.path_join("center_original_receipt.json"), FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(evidence, "\t", true, true)); file.close()
	print("REGION_SIEGE_CENTER_ORIGINAL_", "FAILED" if failed else "PASS", " ", JSON.stringify(evidence))
	quit(1 if failed else 0)
