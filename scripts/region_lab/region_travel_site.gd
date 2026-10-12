class_name RegionTravelSite
extends RefCounted
## Site-scene side of Region travel (R1): the 「整隊出發」 action and the
## world-open hand-off/arrival. Kept out of SiteController; it only calls the
## controller's existing capture/save/bind/exit owners.

const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const TravelPanel = preload("res://scripts/region_lab/region_travel_panel.gd")
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
	var selected := candidate.region_travel_party()
	if not selected.ok: return selected
	if not selected.party.get("upkeep", {}).get("live", {}).is_empty():
		return _open_selected_live_party(controller, candidate, manifest_path)
	if not bool(status.arrived):
		open_travel_map(controller, str(candidate.pin.world_instance_id), str(candidate.pin.slot_id), manifest_path)
		return Runtime.ok("旅隊仍在途中；開啟台灣地圖", {"travel_handoff": true})
	var lab: Node = controller.lab
	var destination: Vector2i = status.destination
	var now := float(candidate.control.logical_game_seconds)
	# Restore/admit the selected land owner while its marker still retains
	# historical admission, before a new destination genesis is published.
	var host_panel: Node = null
	if str(selected.party.get("mode", "land")) == "land" and not candidate.region_original_party_progress.is_valid():
		host_panel = TravelPanel.new()
		host_panel.visible = false
		host_panel.process_mode = Node.PROCESS_MODE_DISABLED
		controller.add_child(host_panel)
		host_panel.slot = candidate
		var hosted: Dictionary = host_panel._ensure_original_adapter_host(selected.party)
		if not hosted.get("ok", false):
			_release_arrival_host(host_panel)
			return _staged(hosted, "arrival_host")
	if str(selected.party.get("mode", "land")) == "land":
		if not candidate.region_original_party_progress.is_valid():
			_release_arrival_host(host_panel)
			return _staged(Runtime.fail("MISSING_REGION_PARTY_PROGRESS"), "arrival_party_admission")
		var original: Object = candidate.region_original_party_progress.get_object()
		if not original is TerrainLab or original.site_controller == null or original.site_controller.region_slot != candidate:
			_release_arrival_host(host_panel)
			return _staged(Runtime.fail("INVALID_REGION_PARTY_PROGRESS"), "arrival_party_admission")
		var admitted: Dictionary = original.prepare_region_party_original_owner(str(status.token), selected.party, candidate)
		if not admitted.get("ok", false):
			_release_arrival_host(host_panel)
			return _staged(admitted, "arrival_party_admission")
		var proof: Dictionary = candidate.region_original_party_runtime_proof(str(status.token), selected.party)
		if not proof.get("ok", false):
			_release_arrival_host(host_panel)
			return _staged(proof, "arrival_party_proof")
	var opened: Dictionary
	if FileAccess.file_exists(candidate.site_path(destination)):
		opened = candidate.open_site(destination) # Original exact cold replay (may be PENDING).
	else:
		var fresh: Dictionary = candidate.source.make_terrain_data(destination.x, destination.y)
		if not bool(fresh.get("ok", false)):
			_release_arrival_host(host_panel)
			return fresh
		opened = candidate._ground_destination(fresh.data, now)
		if opened.ok:
			# Decision A: a never-visited destination publishes its genesis as one
			# generation at this same game time; the arrival bind keeps its
			# published-source rule.
			var genesis := candidate.publish_region_destination_genesis(opened.data)
			if not genesis.ok:
				_release_arrival_host(host_panel)
				return controller._remember_region_pending(_staged(genesis, "destination_genesis"), request)
			if genesis.get("data") is TerrainData: opened.data = genesis.data # Continue from the selected canonical body.
	if not opened.ok:
		_release_arrival_host(host_panel)
		return controller._remember_region_pending(_staged(opened, "open_destination"), request)
	var preflight: Dictionary = controller._journey_arrival_preflight(opened.data)
	if not preflight.ok:
		_release_arrival_host(host_panel)
		return _staged(preflight, "destination_preflight")
	var original_bind := func(data: TerrainData) -> Dictionary:
		var checked: Dictionary = controller._journey_arrival_preflight(data)
		if not checked.ok: return checked
		if not lab.has_method("prepare_region_owner_bind"): return Runtime.fail("MISSING_REGION_BIND_PREFLIGHT")
		return lab.call("prepare_region_owner_bind", data, "live", candidate)
	var committed := candidate.commit_region_arrival(opened.data, original_bind)
	_release_arrival_host(host_panel)
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
	# attach_active_site marks the attached Site committed-unbound until its bind
	# is acknowledged; the arrival bind completed before the attach, so the main
	# lab re-acknowledges the same complete receipt (live, this generation).
	var live: Dictionary = candidate.acknowledge_region_bind(data, receipt)
	if not live.ok: return live
	controller._region_manifest_path = manifest_path
	controller._auto_save_blocked = false
	controller.save_path = candidate.site_path(destination)
	return Runtime.ok("旅隊已抵達目的地", {"site": [destination.x, destination.y], "arrived": true})

static func _release_arrival_host(host_panel: Node) -> void:
	if host_panel == null: return
	host_panel._release_original_adapter_host()
	host_panel.free()

static func _open_selected_live_party(controller: Node, candidate: RegionSaveSlot, manifest_path: String) -> Dictionary:
	var token := str(candidate.region_travel_journey().get("token", ""))
	var selected := candidate.region_live_party_proof(token)
	if not selected.ok: return selected
	var lab: Node = controller.lab
	if not lab.has_method("bind_selected_region_party"): return Runtime.fail("MISSING_ORIGINAL_PARTY_BIND")
	controller.region_slot = candidate
	var bound: Dictionary = lab.call("bind_selected_region_party", token, selected.party, candidate, selected.proof)
	if not bound.get("ok", false) or bound.get("complete") != true or bound.get("owner") != "travel:" + token \
			or int(bound.get("generation", -1)) != int(candidate._marker.generation):
		return bound if not bound.get("ok", false) else Runtime.fail("COMMITTED_UNBOUND", "真選定party完整graph仍待同世代綁定")
	controller._region_manifest_path = manifest_path
	controller._auto_save_blocked = true # Sole party JSON+graph checkpoint owns saves.
	controller._ship_journey.clear()
	controller.save_path = ""
	return Runtime.ok("已接回原旅隊即時場景", {"party_live": true, "token": token, "generation": int(candidate._marker.generation)})

static func request_departure(controller: Node) -> Dictionary:
	if not controller._region_departure_intent.is_empty():
		return cancel_departure(controller, str(controller._region_departure_intent.nonce))
	if controller.lab.terrain != null and float(controller.lab.terrain.site.get("combat_left", 0.0)) <= 0.0:
		return depart(controller)
	return controller._request_region_departure()

static func cancel_departure(controller: Node, nonce: String) -> Dictionary:
	return controller._cancel_region_departure(nonce)

## Read selection through the same original person/team/cape/near-enemy owners.

static func selected_departure(controller: Node) -> Dictionary:
	var lab: TerrainLab = controller.lab
	var slot: RegionSaveSlot = controller.region_slot
	if slot == null or lab.restore_only or lab.terrain == null: return Runtime.fail("NO_REGION_SLOT")
	var fault: Dictionary = controller.original_step_fault_guard()
	if not fault.ok: return fault
	if controller._crowd_active(): return Runtime.fail("REGION_BACKEND_UNADMITTED")
	if controller.ship_journey_active() or controller.ground_crossing_blocks_input() or controller.region_operation_pending() or is_instance_valid(lab._cold_replay_lab): return Runtime.fail("BUSY")
	if controller.get_tree().paused or bool(lab.terrain.site.get("paused", false)): return Runtime.fail("PAUSED")
	var scope := RegionSaveSlot.RegionBattle.scoped_controlled_person(lab)
	if not scope.ok or str(scope.get("scope", "")) != "active_original": return Runtime.fail("COMMITTED_UNBOUND")
	var identity := lab.controlled_person_id()
	var person := lab.controlled_target()
	if person.is_empty() or float(person.get("hp", 0.0)) <= 0.0: return Runtime.fail("NO_TARGET")
	var team: TerrainArmy = lab.player_army()
	if team == null and int(person.unit) >= 0: team = person.owner
	var index := lab.controlled_member_index(team)
	var captain := team != null and index != -1 and team.formal_commander == index
	var spec := {"person_id": identity, "actor_key": "", "team_id": 0, "controller": "player", "family_transfer_guard": slot.region_family_transfer_guard}
	var faction := -1
	var cells: Array[Vector2i] = [Vector2i(person.cell)]
	var people: Array[int] = [identity]
	var orders: Array = []
	var waiting := false
	if int(person.unit) >= 0:
		if not captain: spec.solo_row = identity
		faction = team.faction_id
	else:
		var actor: TerrainTestCharacter = person.owner
		spec.actor_key = "player" if actor == lab.character else "npc"
		faction = actor.faction_id
		if not actor.can_act(): return Runtime.fail("NOT_READY")
		if actor.attack_target_id != 0 or actor._rescue_left > 0.0 or actor.guarding or actor.guard_transition_left > 0.0 or actor.guard_break_left > 0.0: return Runtime.fail("IN_COMBAT")
		waiting = actor.is_moving() or actor.action_time > 0.0 or not actor.projectiles.is_empty()
		orders = [actor.ranged_order_serial, actor.ranged_enabled, actor.ranged_target.duplicate(true)]
	if captain:
		spec.team_id = team.team_id
		for row: int in range(team.combat_units.size()):
			cells.append(team.cells[row])
			var member := team.combat_identity(row)
			if not people.has(member): people.append(member)
			if float(team.combat_hot_get(row, &"ko", 0.0)) > 0.0 or str(team.combat_hot_get(row, &"pose", "")) in ["unconscious", "get_up"]: return Runtime.fail("NOT_READY")
	elif team != null and int(person.unit) < 0:
		spec.solo_actor = identity
	if team != null and (captain or int(person.unit) >= 0):
		for row: int in range(team.combat_units.size()):
			if not people.has(team.combat_identity(row)): continue
			if not team.combat_can_act(row): return Runtime.fail("NOT_READY")
			if bool(team.combat_hot_get(row, &"attack", false)): return Runtime.fail("IN_COMBAT")
			waiting = waiting or team.moving_to[row] != TerrainArmy.INVALID_CELL or float(team.combat_hot_get(row, &"action_time", 0.0)) > 0.0
		waiting = waiting or not team.projectiles.is_empty()
		orders = [team.combat_order, team.combat_goal, team.formal_commander, team.ranged_order_serial, team.ranged_target.duplicate(true)]
	if not captain and team != null:
		var cape_guard: Dictionary = controller.cape_departure_guard(identity)
		if not cape_guard.ok: return cape_guard
	if _hostile_near(lab, faction, cells): return Runtime.fail("IN_COMBAT")
	var cape_policy: Dictionary = controller.cape_policy_guard()
	if not cape_policy.ok: return cape_policy
	for mover: int in people:
		if controller._pending_deaths.has(mover) or controller.person_actions.is_busy(mover): return Runtime.fail("REGION_ACTIVE_DEPENDENCY", "本人原作業尚未准入冷交接；保留原進度")
	if person.owner == lab.character:
		waiting = waiting or not str(lab.terrain.site.manual.target).is_empty() or float(lab.terrain.site.manual.progress) > 0.0
	if person.owner == lab.npc:
		waiting = waiting or not str(lab.terrain.site.worker.target).is_empty() or float(lab.terrain.site.worker.progress) > 0.0
	for mover: int in people:
		waiting = waiting or lab.fire_reservations.has(mover)
	for flight: Dictionary in lab.fire_projectiles:
		if people.has(int(flight.get("shooter_id", 0))): waiting = true
	var mode := "sea" if controller.vehicles.is_embarked(identity) else "land"
	spec.mode = mode
	var site: Vector2i = controller._current_region_site()
	var component := 0 if mode == "sea" else start_component(slot, site, Vector2i(person.cell), lab.terrain)
	if component < 0 or component > 253: return Runtime.fail("NO_ROUTE")
	people.sort()
	return {"ok": true, "spec": spec, "people": people, "component": component, "waiting": waiting,
		"selection": var_to_bytes([identity, spec.actor_key, spec.team_id, spec.get("solo_row", 0), spec.get("solo_actor", 0), people, orders])}

