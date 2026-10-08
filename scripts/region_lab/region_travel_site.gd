class_name RegionTravelSite
extends RefCounted
## Site-scene side of Region travel (R1): the 「整隊出發」 action and the
## world-open hand-off/arrival. Kept out of SiteController; it only calls the
## controller's existing capture/save/bind/exit owners.

const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const ENEMY_RADIUS := 24 # cells (48 m): an able hostile this close means "not out of combat".

static func _hostile_near(lab: Node, faction: int, cells: Array[Vector2i]) -> bool:
	var enemies: Array[Vector2i] = []
	for actor: TerrainTestCharacter in lab.combat_actors:
		if lab.actor_present(actor) and actor.faction_id != faction and actor.can_act(): enemies.append(actor.terrain_cell)
	for team: TerrainArmy in lab.combat_armies:
		if not team.combat_enabled or team.faction_id == faction: continue
		for index: int in range(team.combat_units.size()):
			if team.combat_can_act(index) and not bool(team.combat_hot_get(index, &"site_exited", false)):
				enemies.append(team.cells[index])
	for enemy: Vector2i in enemies:
		for cell: Vector2i in cells:
			if maxi(absi(enemy.x - cell.x), absi(enemy.y - cell.y)) <= ENEMY_RADIUS: return true
	return false

## No nearest-cell fallback: a disconnected original position remains blocked.
static func start_component(slot: RegionSaveSlot, site: Vector2i, cell: Vector2i, active: TerrainData = null) -> int:
	var prepared := slot.prepare_region_route_context(active)
	if not prepared.ok: return -1
	var built := RegionRoute.effective_terrain(slot.source, site, prepared.context)
	if not bool(built.get("ok", false)): return -1
	var cover: Dictionary = slot.source.site_resource_cover(site)
	var derived := RegionRoute.table_from_terrain(built.data, cover.get("cover", PackedByteArray()), true)
	if not derived.ok: return -1
	return RegionRoute.component_of(derived, cell)

## 「整隊出發」: captain takes the whole team; anyone else leaves the team and goes alone.
static func depart(controller: Node) -> Dictionary:
	var lab: Node = controller.lab
	var slot: RegionSaveSlot = controller.region_slot
	if slot == null or lab.restore_only: return Runtime.fail("NO_REGION_SLOT", "須在台灣地圖世界中才能整隊出發")
	var fault: Dictionary = controller.original_step_fault_guard()
	if not fault.ok: return fault
	if controller._crowd_active(): return Runtime.fail("UNSUPPORTED", "群眾模式（Crowd）暫不支援整隊出發")
	if controller.ship_journey_active() or controller.ground_crossing_blocks_input() or is_instance_valid(lab._cold_replay_lab):
		return Runtime.fail("BUSY", "船隊旅程、跨界或補算尚未結束")
	if controller.get_tree().paused or bool(lab.terrain.site.get("paused", false)): return Runtime.fail("PAUSED", "暫停時不能出發")
	if float(lab.terrain.site.get("combat_left", 0.0)) > 0.0: return Runtime.fail("IN_COMBAT", "戰鬥中不能整隊出發")
	var identity: int = lab.controlled_person_id()
	var person: Dictionary = lab.controlled_target()
	if person.is_empty() or float(person.get("hp", 0.0)) <= 0.0: return Runtime.fail("NO_TARGET", "沒有可出發的受控人物")
	var team: TerrainArmy = lab.player_army()
	if team == null and int(person.unit) >= 0: team = person.owner
	var index: int = lab.controlled_member_index(team)
	var captain := team != null and index != -1 and team.formal_commander == index
	var spec := {"person_id": identity, "actor_key": "", "team_id": 0}
	var faction := -1
	var cells: Array[Vector2i] = [Vector2i(person.cell)]
	if int(person.unit) >= 0:
		if not captain: spec.solo_row = identity
		faction = team.faction_id
	else:
		var actor: TerrainTestCharacter = person.owner
		spec.actor_key = "player" if actor == lab.character else "npc"
		faction = actor.faction_id
	if captain:
		spec.team_id = team.team_id
		for row: int in range(team.combat_units.size()):
			cells.append(team.cells[row])
			if float(team.combat_hot_get(row, &"ko", 0.0)) > 0.0 or str(team.combat_hot_get(row, &"pose", "")) in ["unconscious", "get_up"]:
				return Runtime.fail("NOT_READY", "有隊員倒地；須先救起或包紮才能出發")
	elif team != null and int(person.unit) < 0:
		spec.solo_actor = identity
	if not captain and team != null:
		var cape_guard: Dictionary = controller.cape_departure_guard(identity)
		if not cape_guard.ok: return cape_guard
	if _hostile_near(lab, faction, cells): return Runtime.fail("IN_COMBAT", "附近有敵人；脫離戰鬥後才能出發")
	var guard: Dictionary = controller.supply_save_guard()
	if not guard.ok: return guard
	var captured: Dictionary = controller._capture_for_save()
	if not captured.ok: return captured
	var site: Vector2i = controller._current_region_site()
	var mode := "sea" if controller.vehicles.is_embarked(identity) else "land"
	spec.mode = mode
	spec.game_seconds = float(slot.control.logical_game_seconds)
	var component := 0 if mode == "sea" else start_component(slot, site, Vector2i(person.cell), lab.terrain)
	if not slot.cold_site_advance.is_valid(): slot.cold_site_advance = lab.advance_cold_site
	var result := slot.begin_region_travel(lab.terrain, spec, component)
	if not result.ok: return result
	# The committed generation owns the source now; this scene must never save again.
	controller._auto_save_blocked = true
	lab.terrain.site.paused = true
	open_travel_map(controller, str(slot.pin.world_instance_id), str(slot.pin.slot_id), controller._region_manifest_path)
	var census := RegionTravel.census(result.party)
	var note := "；已離開原住處" if not result.vacated_housing.is_empty() else ""
	return Runtime.ok(("已整隊出發（%d 人、%d 輛車）%s" if captain else "已退隊並單獨出發（%d 人、%d 輛車）%s") % [census.people.size(), census.vehicles.size(), note], {"token": result.token})

## Headless contract tests keep the scene; the game always changes to the map.
static var scene_handoff := true

static func _staged(result: Dictionary, stage: String) -> Dictionary:
	if not bool(result.get("ok", false)) and str(result.get("code", "")) != "PENDING": result["stage"] = stage
	return result

static func open_travel_map(controller: Node, world_id: String, slot_id: String, manifest: String) -> void:
	RegionEntry.region_mode = "travel"
	RegionEntry.view = {"world_id": world_id, "slot_id": slot_id, "manifest": manifest}
	if scene_handoff: controller._leave_site.call_deferred(controller.REGION_MAP_SCENE)

## Called by open_fixed_world for an existing world. Empty result = not a
## travelling slot. Otherwise the world either hands off to the map or arrives.
static func world_opened(controller: Node, candidate: RegionSaveSlot, manifest_path: String, request: Dictionary) -> Dictionary:
	var status := candidate.region_travel_status()
	if not status.ok: return status
	if not bool(status.get("pending", false)): return {}
	if not bool(status.arrived):
		open_travel_map(controller, str(candidate.pin.world_instance_id), str(candidate.pin.slot_id), manifest_path)
		return Runtime.ok("旅隊仍在途中；開啟台灣地圖", {"travel_handoff": true})
	var lab: Node = controller.lab
	var destination: Vector2i = status.destination
	var now := float(candidate.control.logical_game_seconds)
	var opened: Dictionary
	if FileAccess.file_exists(candidate.site_path(destination)):
		opened = candidate.open_site(destination) # Original exact cold replay (may be PENDING).
	else:
		var fresh: Dictionary = candidate.source.make_terrain_data(destination.x, destination.y)
		if not bool(fresh.get("ok", false)): return fresh
		opened = candidate._ground_destination(fresh.data, now)
	if not opened.ok: return controller._remember_region_pending(_staged(opened, "open_destination"), request)
	var preflight: Dictionary = controller._journey_arrival_preflight(opened.data)
	if not preflight.ok: return _staged(preflight, "destination_preflight")
	var original_bind := func(data: TerrainData) -> Dictionary:
		var checked: Dictionary = controller._journey_arrival_preflight(data)
		if not checked.ok: return checked
		if not lab.has_method("prepare_region_owner_bind"): return Runtime.fail("MISSING_REGION_BIND_PREFLIGHT")
		return lab.call("prepare_region_owner_bind", data, "live", candidate)
	var committed := candidate.commit_region_arrival(opened.data, original_bind)
	if not committed.ok: return _staged(committed, "commit_arrival")
	var data: TerrainData = committed.destination_data
	var attached := candidate.attach_active_site(data)
	if not attached.ok: return attached
	controller.region_slot = candidate
	controller._ship_journey.clear()
	var receipt: Dictionary = lab.region_bind_receipt(data)
	if not receipt.get("complete", false) or str(receipt.get("owner", "")) != str(data.site.id) \
			or int(receipt.get("generation", -1)) != int(committed.generation):
		return Runtime.fail("BIND_FAILED_AFTER_COMMIT", "旅隊已提交抵達，原人物／物品／租約尚未完整綁定；請從主選單繼續重試")
	controller._region_manifest_path = manifest_path
	controller._auto_save_blocked = false
	controller.save_path = candidate.site_path(destination)
	return Runtime.ok("旅隊已抵達目的地", {"site": [destination.x, destination.y], "arrived": true})
