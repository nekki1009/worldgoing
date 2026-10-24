class_name SiteStore
extends RefCounted

const Env = preload("res://scripts/terrain_lab/site_environment.gd")
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const VacancyEpisode = preload("res://scripts/terrain_lab/site_vacancy_episode.gd") # R5 S3F: vacancy episode map.
const Boarding = preload("res://scripts/terrain_lab/site_boarding_link_contract.gd")
const Trade = preload("res://scripts/terrain_lab/site_trade.gd")
const RegionCheckpoint = preload("res://scripts/terrain_lab/site_region_checkpoint.gd")
const Housing = preload("res://scripts/terrain_lab/site_housing.gd")
const ResidentRoster = preload("res://scripts/terrain_lab/site_resident_roster.gd")
const Settlement = preload("res://scripts/terrain_lab/site_settlement.gd")
const Stockpiles = preload("res://scripts/terrain_lab/site_stockpiles.gd")
const Sustain = preload("res://scripts/terrain_lab/site_sustain.gd")
const EquipmentOrders = preload("res://scripts/terrain_lab/site_equipment_orders.gd")
const CaptiveEscort = preload("res://scripts/terrain_lab/site_captive_escort.gd")
const FamilyContinuity = preload("res://scripts/terrain_lab/site_family_continuity.gd")
const Technology = preload("res://scripts/terrain_lab/site_technology.gd")
const TechnologyPolicy = preload("res://scripts/terrain_lab/site_technology_policy.gd")
const WorkTeam = preload("res://scripts/terrain_lab/site_work_team.gd")
const Vehicles = preload("res://scripts/terrain_lab/site_vehicle_transport.gd")
const ShipDefs = preload("res://scripts/terrain_lab/site_vehicle_ship_definitions.gd")
const RiderAtlas = preload("res://scripts/terrain_lab/site_vehicle_rider_atlas.gd")
const Destination = preload("res://scripts/terrain_lab/formation_destination_planner.gd")
const FORMAT := 4
const TERRAIN_VERSION := 1
const DEFAULT_PATH := "user://sites/current.json"
const MAX_ARMIES := 50
const MAX_ARMY_ROWS := 5000
const MAX_BYTES := 32 * 1024 * 1024
const MAX_CROWD_BYTES := 16 * 1024 * 1024
const MAX_CROWD_ROWS := 10000
const CROWD_PAYLOAD_ENCODING := "zstd-base64-json-v1"
const CROWD_FLOAT_EPSILON := 4.0 * 2.220446049250313e-16
const CROWD_DLL := "res://native/crowd10k/bin/crowd10k.windows.x86_64.dll"

# The live event owner is queried through metadata; no transient counter is saved.
static func siege_event_guard(data: TerrainData) -> Dictionary:
	if data == null or not data.has_meta(&"siege_event_guard"): return Runtime.ok()
	var callback: Variant = data.get_meta(&"siege_event_guard")
	if not callback is Callable or not callback.is_valid(): return Runtime.fail("BUSY", "攻城事件擁有者未能安全查核")
	var result: Variant = callback.call()
	if not result is Dictionary or not result.get("ok") is bool: return Runtime.fail("BUSY", "攻城事件守衛回傳無效")
	return result

static func fire_event_guard(data: TerrainData, allow_dirty_fire_save: bool = false) -> Dictionary:
	var history := Runtime.fire_save_guard(data)
	if not history.ok: return history
	if data == null: return Runtime.ok()
	var fire_state: Variant = data.site.get("fire", {})
	if not data.has_meta(&"fire_event_guard"):
		if data.has_meta(&"site_garrison_lab") and not data.site.get("fire", {}).is_empty():
			return Runtime.fail("BUSY", "現場 Fire owner 未能安全查核")
	else:
		var callback: Variant = data.get_meta(&"fire_event_guard")
		if not callback is Callable or not callback.is_valid(): return Runtime.fail("BUSY", "Fire owner unavailable")
		var result: Variant = callback.call(allow_dirty_fire_save) if allow_dirty_fire_save and callback.get_argument_count() > 0 else callback.call()
		if not result is Dictionary or not result.get("ok") is bool: return Runtime.fail("BUSY", "Invalid fire guard")
		if not result.ok: return result
	var transport: Variant = data.site.get("fire_transport", {})
	if data.has_meta(&"fire_transport_snapshot"):
		var capture: Variant = data.get_meta(&"fire_transport_snapshot")
		if not capture is Callable or not capture.is_valid(): return Runtime.fail("BUSY", "Fire transport owner unavailable")
		var captured: Variant = capture.call()
		if not captured is Dictionary or not captured.get("ok") is bool: return Runtime.fail("BUSY", "Invalid fire transport capture")
		if not captured.ok: return captured
		transport = captured.get("state", {})
	var checked := _validate_fire_transport_snapshot(data, fire_state if fire_state is Dictionary else {}, transport)
	if not checked.ok: return checked
	if not data.has_meta(&"fire_transport_snapshot") and not checked.state.is_empty():
		return _validate_fire_transport_owners(data, data.site, checked.state)
	return Runtime.ok()

static func _validate_fire_transport_owners(_data: TerrainData, site_state: Dictionary, transport: Dictionary) -> Dictionary:
	var owners := {}
	var members := {}
	for key: String in site_state.get("actors", {}):
		var actor: Variant = site_state.actors[key]
		if not actor is Dictionary or not _integer(actor.get("person_id"), 1, 2147483647): return Runtime.fail("CORRUPT_FIRE_OWNER", "Fire actor snapshot has an invalid person identity: " + key)
		var identity := int(actor.person_id)
		var group := -identity
		if identity <= 0 or owners.has(group) or members.has(identity): return Runtime.fail("CORRUPT_FIRE_OWNER", "Fire actor identity is invalid or duplicated: " + key)
		owners[group] = {"kind": "actor", "key": key, "row": actor, "team_id": 0}
		members[identity] = group
	for army: Variant in site_state.get("armies", []):
		if not army is Dictionary or not _integer(army.get("team_id"), 1, 999999) or not army.get("units") is Array: return Runtime.fail("CORRUPT_FIRE_OWNER", "Fire Army snapshot is malformed")
		var team_id := int(army.team_id)
		if team_id <= 0 or owners.has(team_id): return Runtime.fail("CORRUPT_FIRE_OWNER", "Fire Army identity is invalid or duplicated")
		owners[team_id] = {"kind": "army", "row": army, "team_id": team_id}
		for unit: Variant in army.units:
			if not unit is Dictionary or not _integer(unit.get("person_id"), 1, 2147483647): return Runtime.fail("CORRUPT_FIRE_OWNER", "Fire Army member has an invalid person identity")
			var identity := int(unit.person_id)
			if identity <= 0 or members.has(identity): return Runtime.fail("CORRUPT_FIRE_OWNER", "Fire Army member identity is invalid or duplicated")
			members[identity] = team_id
	if owners.size() != transport.get("orders", {}).size():
		return Runtime.fail("CORRUPT_FIRE_OWNER", "Fire 命令數與原人物／隊伍名冊不相符: owners=%s orders=%s" % [owners.keys(), transport.get("orders", {}).keys()])
	for group: int in transport.get("orders", {}):
		if not owners.has(group): return Runtime.fail("CORRUPT_FIRE_OWNER", "Fire command has no matching original owner: " + str(group))
		var owner: Dictionary = owners[group]
		var order: Dictionary = transport.orders[group]
		if owner.kind == "actor":
			if bool(order.enabled) and (int(order.issuer_id) != int(owner.row.person_id)
				or int(site_state.get("controlled_person_id", site_state.get("actors", {}).get("player", {}).get("person_id", -1))) != int(owner.row.person_id)):
				return Runtime.fail("CORRUPT_FIRE_ORDER_AUTHORITY")
		else:
			var team: Dictionary = owner.row
			var commander := int(team.get("current_commander", -1))
			var commander_id := -1
			if commander == TerrainArmy.PLAYER_MEMBER:
				commander_id = int(team.get("player_member", {}).get("id", -1))
			elif commander >= 0 and commander < team.units.size():
				commander_id = int(team.units[commander].get("person_id", -1))
			if bool(order.enabled) and (commander_id <= 0 or int(order.issuer_id) != commander_id):
				return Runtime.fail("CORRUPT_FIRE_ORDER_AUTHORITY")
		for identity: int in order.release_ids:
			if int(members.get(identity, 0)) != group: return Runtime.fail("CORRUPT_FIRE_RELEASE_OWNER")
	for identity: int in transport.get("reservations", {}):
		var reservation: Dictionary = transport.reservations[identity]
		var group := int(reservation.formation_id) if int(reservation.formation_id) > 0 else -identity
		if int(members.get(identity, 0)) != group or not owners.has(group): return Runtime.fail("CORRUPT_FIRE_PREPARATION_OWNER")
		var order: Dictionary = transport.orders.get(group, {})
		if order.is_empty() or not bool(order.enabled) or int(order.serial) != int(reservation.serial) \
			or str(order.mode) != str(reservation.mode) or order.target != reservation.target:
			return Runtime.fail("CORRUPT_FIRE_PREPARATION_ORDER")
		var owner: Dictionary = owners[group]
		var holder: Dictionary
		var cargo: Dictionary
		if owner.kind == "actor":
			holder = owner.row.get("item_state", {})
			var cargo_key := "manual" if owner.key == "player" else "worker"
			cargo = site_state.get(cargo_key, {}).get("cargo", {})
		else:
			for unit: Dictionary in owner.row.units:
				if int(unit.person_id) == identity:
					holder = unit.get("item_state", {})
					cargo = unit.get("cargo", {})
					break
		if not holder is Dictionary or not cargo is Dictionary or str(holder.get("holder", "")) != str(reservation.stamp.holder) \
			or int(holder.get("version", 0)) != int(reservation.stamp.version) or cargo != reservation.stamp.cargo:
			return Runtime.fail("STALE_FIRE_PREPARATION")
	return Runtime.ok()

static func _fire_requires_transport(state: Dictionary) -> bool:
	for field: String in ["units", "active", "contacts", "receipt_ids", "repair_generations", "suppression_pending",
		"collapse_warnings", "collapse_receipts", "structure_pending", "contents_remainders", "inventory_pending", "inventory_receipts"]:
		var value: Variant = state.get(field, {})
		if value is Dictionary and not value.is_empty() or value is Array and not value.is_empty(): return true
	return int(state.get("receipt_floor", 0)) > 0 or int(state.get("suppression_sequence", 0)) > 0 \
		or int(state.get("collapse_next_sequence", 0)) > 0

static func _fire_transport_coordinate_wire(value: Variant, count: int) -> Array:
	var result: Array = []
	if not value is String: return result
	var text: String = str(value).strip_edges()
	if not text.begins_with("(") or not text.ends_with(")"): return result
	var components: PackedStringArray = text.substr(1, text.length() - 2).split(",", false)
	if components.size() != count: return result
	for component: String in components:
		var token := component.strip_edges()
		if not token.is_valid_float(): return []
		var number := token.to_float()
		if not is_finite(number): return []
		result.append(number)
	return result

static func _validate_fire_transport_snapshot(data: TerrainData, fire_state: Dictionary, raw: Variant, pending_action_cursor: float = -1.0) -> Dictionary:
	if not raw is Dictionary: return Runtime.fail("CORRUPT_FIRE_TRANSPORT")
	if raw.is_empty():
		return Runtime.fail("BUSY", "Fire receipt／物體狀態仍待原 transport 保存恢復") if _fire_requires_transport(fire_state) else Runtime.ok("", {"state": {}, "wire": {}})
	# SiteStore keeps the normalized owner maps in live Site state; the JSON wire
	# format stays arrays. Accept both forms at this shared save/load boundary.
	var wire: Dictionary = raw.duplicate(true)
	if wire.get("orders") is Dictionary:
		var orders: Array = []
		for group: Variant in wire.orders:
			var order: Dictionary = wire.orders[group]
			if order.get("release_ids") is Dictionary:
				var releases: Array = []
				for identity: Variant in order.release_ids: releases.append([int(identity), int(order.release_ids[identity])])
				order["release_ids"] = releases
			order["group"] = int(group)
			orders.append(order)
		wire["orders"] = orders
	if wire.get("reservations") is Dictionary:
		var reservations: Array = []
		for identity: Variant in wire.reservations:
			var reservation: Dictionary = wire.reservations[identity]
			reservation["person_id"] = int(identity)
			reservations.append(reservation)
		wire["reservations"] = reservations
	if wire.get("member_cursor") is Dictionary:
		var cursors: Array = []
		for group: Variant in wire.member_cursor: cursors.append([int(group), int(wire.member_cursor[group])])
		wire["member_cursor"] = cursors
	# A loaded/validated Site may already carry typed flight coordinates. Convert
	# those back to the JSON wire shape before passing through the same validator.
	if wire.get("projectiles") is Array:
		for flight: Variant in wire.projectiles:
			if not flight is Dictionary: continue
			for field: String in ["origin", "position", "velocity"]:
				var point: Variant = flight.get(field)
				if point is Vector3: flight[field] = [point.x, point.y, point.z]
				elif point is String: flight[field] = _fire_transport_coordinate_wire(point, 3)
			var cell: Variant = flight.get("source_cell")
			if cell is Vector2i: flight.source_cell = [cell.x, cell.y]
			elif cell is String: flight.source_cell = _fire_transport_coordinate_wire(cell, 2)
	var json_wire: Variant = Runtime._fire_snapshot_json_copy(wire)
	if not json_wire is Dictionary: return Runtime.fail("CORRUPT_FIRE_TRANSPORT")
	wire = json_wire
	var checked := TerrainLab.validate_fire_transport(data, wire)
	if not checked.ok: return checked
	var transport: Dictionary = checked.state
	var expected_cursor: Variant = fire_state.get("observed_action_end", -1.0) if not fire_state.is_empty() else -1.0
	var settlement: Variant = data.site.get("fire_settlement", {})
	if settlement is Dictionary and settlement.has("action_seconds"): expected_cursor = settlement.action_seconds
	if expected_cursor != -1.0 and absf(float(transport.action_cursor) - float(expected_cursor)) > maxf(0.00000001, absf(float(expected_cursor)) * 0.000000001) and not _region_cursor_matches_pending(float(transport.action_cursor), pending_action_cursor, float(expected_cursor)):
		return Runtime.fail("FIRE_CLOCK_MISMATCH", "transport=%s watermark=%s" % [str(transport.action_cursor), str(expected_cursor)])
	var release_sequence := int(transport.release_sequence)
	if int(fire_state.get("receipt_floor", 0)) > release_sequence: return Runtime.fail("CORRUPT_FIRE_RELEASE_WATERMARK")
	for identity: Variant in fire_state.get("receipt_ids", {}):
		if not str(identity).is_valid_int() or int(identity) < 1 or int(identity) > release_sequence: return Runtime.fail("CORRUPT_FIRE_RELEASE_WATERMARK")
	for identity: String in fire_state.get("contacts", {}):
		if not identity.begins_with("arrow:"): continue
		var suffix := identity.trim_prefix("arrow:")
		if not suffix.is_valid_int() or str(int(suffix)) != suffix or int(suffix) < 1 or int(suffix) > release_sequence:
			return Runtime.fail("CORRUPT_FIRE_RELEASE_WATERMARK")
	return Runtime.ok("", {"state": transport, "wire": wire})

static func _validate_fire_owner_snapshot(data: TerrainData, site_state: Dictionary, raw: Variant, action_cursor: float) -> Dictionary:
	if raw == null or raw is Dictionary and raw.is_empty(): return Runtime.ok("", {"state":{}})
	if data == null or not raw is Dictionary or not Runtime._fire_snapshot_json(raw) \
		or not Runtime._fire_snapshot_keys(raw, ["version", "site_id", "action_cursor", "teams", "leases", "jobs", "navigation"]):
		return Runtime.fail("CORRUPT_FIRE_OWNER_SNAPSHOT")
	if not Runtime._building_integer(raw.version, 1, 1) or raw.site_id != str(site_state.get("id", "")) \
		or not Runtime._building_number(raw.action_cursor, 0.0, 1.0e12) or absf(float(raw.action_cursor) - action_cursor) > Runtime.FIRE_EPS \
		or not raw.teams is Array or raw.teams.size() > MAX_ARMIES or not raw.leases is Dictionary \
		or not raw.jobs is Dictionary or not raw.navigation is Array:
		return Runtime.fail("CORRUPT_FIRE_OWNER_SNAPSHOT")
	var expected_teams := {}
	for army: Variant in site_state.get("armies", []):
		if army is Dictionary:
			expected_teams[int(army.get("team_id", -1))] = true
	var teams := {}
	for identity: Variant in raw.teams:
		if not Runtime._building_integer(identity, 1, 999999) or teams.has(int(identity)) or not expected_teams.has(int(identity)):
			return Runtime.fail("CORRUPT_FIRE_OWNER_SNAPSHOT")
		teams[int(identity)] = true
	if raw.navigation.size() != teams.size() or not Runtime._fire_snapshot_keys(raw.leases, ["version", "next_token", "leases"]) \
		or not Runtime._building_integer(raw.leases.version, 1, 1) or not Runtime._building_integer(raw.leases.next_token, 1, 2147483647) \
		or not raw.leases.leases is Array or raw.leases.leases.size() > data.size.x * data.size.y:
		return Runtime.fail("CORRUPT_FIRE_OWNER_SNAPSHOT")
	for row: Variant in raw.leases.leases:
		if not Runtime._fire_snapshot_keys(row, ["team_id", "order_serial", "member_id", "role", "cell", "absence_left"]) \
			or not Runtime._building_integer(row.team_id, 1, 999999) or not teams.has(int(row.team_id)):
			return Runtime.fail("CORRUPT_FIRE_LEASE_ROW")
	var navigation_seen := {}
	for row: Variant in raw.navigation:
		if not Runtime._fire_snapshot_keys(row, ["team_id", "snapshot"]) or not Runtime._building_integer(row.team_id, 1, 999999) \
			or not teams.has(int(row.team_id)) or navigation_seen.has(int(row.team_id)) or not Runtime._fire_snapshot_keys(row.snapshot,
			["version", "team_id", "serial", "ranged_serial", "hazard_epoch", "threat_last_end", "work", "hazard", "batches", "deployment"]) \
			or int(row.snapshot.get("team_id", -1)) != int(row.team_id) or not row.snapshot.work is Array \
			or not row.snapshot.hazard is Dictionary or not row.snapshot.batches is Array or not row.snapshot.deployment is Dictionary:
			return Runtime.fail("CORRUPT_FIRE_NAVIGATION_SNAPSHOT")
		navigation_seen[int(row.team_id)] = true
	if not Runtime._fire_snapshot_keys(raw.jobs, ["version", "config_version", "site_id", "action_cursor", "next_token", "jobs"]) \
		or not Runtime._building_integer(raw.jobs.version, 1, 1) or raw.jobs.site_id != str(site_state.get("id", "")) \
		or not Runtime._building_integer(raw.jobs.next_token, 1, 2147483647) or not Runtime._building_number(raw.jobs.action_cursor, 0.0, 1.0e12) \
		or absf(float(raw.jobs.action_cursor) - action_cursor) > Runtime.FIRE_EPS \
		or not raw.jobs.jobs is Array or raw.jobs.jobs.size() > 65536:
		return Runtime.fail("CORRUPT_FIRE_JOBS")
	for row: Variant in raw.jobs.jobs:
		if not row is Dictionary or not Runtime._building_integer(row.get("team_id", -1), 1, 999999) \
			or not teams.has(int(row.team_id)): return Runtime.fail("CORRUPT_FIRE_JOB_OWNER")
	return Runtime.ok("", {"state":Runtime._fire_snapshot_json_copy(raw)})

static func has_siege_vehicles(state: Dictionary) -> bool:
	var records: Variant = state.get("vehicles", {})
	if not records is Dictionary: return false
	for vehicle: Variant in records.values():
		if vehicle is Dictionary and Runtime.SIEGE_DEFINITIONS.has(str(vehicle.get("kind", ""))): return true
	return false

static func siege_save_guard(data: TerrainData, allow_dirty_fire_save: bool = false) -> Dictionary:
	var fire := fire_event_guard(data, allow_dirty_fire_save)
	if not fire.ok: return fire
	var events := siege_event_guard(data)
	if not events.ok: return events
	if data == null: return Runtime.fail("NO_TARGET")
	for feature: Variant in data.site.get("features", {}).values():
		if feature is Dictionary and str(feature.get("kind", "")) == "siege_ladder" and feature.get("ladder") is Dictionary and not str(feature.ladder.get("pending", "")).is_empty():
			return Runtime.fail("BUSY", "兩人架梯／收梯作業與交接尚未收束")
	var records: Variant = data.site.get("vehicles", {})
	if not records is Dictionary: return Runtime.fail("CORRUPT_SAVE", "車輛資料")
	for vehicle: Variant in records.values():
		if not vehicle is Dictionary or not Runtime.SIEGE_DEFINITIONS.has(str(vehicle.get("kind", ""))): continue
		if not vehicle.get("action") is Dictionary or not vehicle.get("move") is Dictionary: return Runtime.fail("CORRUPT_SAVE", "攻城器具動作欄位")
		if not vehicle.get("command") is Dictionary: return Runtime.fail("CORRUPT_SAVE", "攻城器具命令欄位")
		if str(vehicle.get("phase", "")) not in ["building", "idle", "ready", "disabled", "wrecked", "deployed"] or str(vehicle.get("phase", "")) == "deployed" and str(vehicle.get("kind", "")) != "siege_tower" or not vehicle.get("action", {}).is_empty() or not vehicle.get("move", {}).is_empty() or bool(vehicle.get("stop_pending", false)):
			return Runtime.fail("BUSY", "攻城器具動作／交接尚未收束；原現場與存檔保留")
		if not vehicle.command.is_empty() and str(vehicle.command.get("type", "")) not in ["stop", "attack"]: return Runtime.fail("BUSY", "攻城操作班就位／解除或轉向命令尚未收束")
	return Runtime.ok()

static func save(data: TerrainData, path: String = DEFAULT_PATH, native_candidate: Variant = null,
	allow_dirty_fire_save: bool = false, region_context: Dictionary = {}, capture_only: bool = false, live_family_target: int = 0, capture_read_only: bool = false) -> Dictionary:
	if data == null or data.site.is_empty():
		return Runtime.fail("NO_TARGET")
	var boarding: Dictionary = Boarding.data_save_guard(data)
	if not boarding.ok: return boarding
	var definitions: Dictionary = Env.validate_resource_definitions(data, data.resource_base)
	if not definitions.ok: return Runtime.fail("CORRUPT_SAVE", str(definitions.get("message", "Invalid resource definitions")))
	var live_state := {}
	if live_family_target != 0 or capture_read_only:
		var original: Variant = data.get_meta(&"site_garrison_lab") if data.has_meta(&"site_garrison_lab") else null
		if original is WeakRef: original = original.get_ref()
		if original == null or not is_instance_valid(original) or original.get("terrain") != data or original.get("site_controller") == null:
			return Runtime.fail("NO_ORIGINAL_OWNER")
		if live_family_target != 0:
			var prepared: Dictionary = original.site_controller.live_family_handover_state(live_family_target)
			if not prepared["ok"]: return prepared
			live_state = prepared["state"]
		else:
			live_state = data.site.duplicate(true)
			original.site_controller._capture_positions(live_state, true)
	var source_data: TerrainData = data
	var region_capture := _region_capture_owners(region_context) if not region_context.is_empty() else Runtime.ok()
	if not region_capture.ok: return region_capture
	var hot := not region_context.is_empty()
	var scene_capture := _region_scene_capture_guard(data, region_capture) if hot else Runtime.ok("", {"complete": false})
	if not scene_capture.ok: return scene_capture
	var pending_action_cursor := _region_pending_fire_cursor(data.site, region_capture.get("context", {}), region_capture.get("owners", {}))
	var completion_guard := _region_capture_completion_guard(data.site, region_capture.get("context", {}))
	if not completion_guard.ok: return completion_guard
	if not hot:
		for event: Variant in data.site.get("region_life_events", []):
			if event is Dictionary and event.get("status") == "pending": return Runtime.fail("BUSY", "原旅行生命端點須先完成，或經 Region barrier checkpoint 保存")
	if hot and (data.site.has("crowd") or native_candidate != null): return Runtime.fail("REGION_BACKEND_UNADMITTED")
	var siege_guard := _region_fire_guard(data, region_capture) if hot else siege_save_guard(data, allow_dirty_fire_save)
	if not siege_guard.ok: return siege_guard
	var fixed_base: Variant = data.parameters.get("fixed_base")
	var rule_base: Dictionary = fixed_base if fixed_base is Dictionary else {}
	if not _same_land_condition_rule(data.parameters, rule_base, "fixed_land_condition_rule", "land_condition_rule"):
		return Runtime.fail("SAVE_VERSION", "Fixed land-condition declaration invalid; original archive retained")
	if fixed_base is Dictionary and not _resource_base_matches(data, fixed_base):
		return Runtime.fail("SAVE_VERSION", "固定資源基底已變更，原存檔保留")
	if not data.site.get("armies", []) is Array:
		return Runtime.fail("CORRUPT_SAVE", "軍隊快照格式")
	var raw_fire: Variant = data.site.get("fire", {})
	if not raw_fire is Dictionary: return Runtime.fail("CORRUPT_FIRE_SNAPSHOT")
	if bool(data.site.get("army_trial_active", false)) and data.site.get("armies", []).is_empty():
		return Runtime.fail("BUSY", "軍隊交戰快照尚未接入；請明確結束近戰測試後保存，避免默默遺失傷亡")
	# This synchronous save only writes top-level defaults/transient removals.
	# Nested validators are read-only; legacy normalizers make their own copies.
	var crowd_snapshot: bool = data.site.has("crowd")
	var state: Dictionary = data.site.duplicate(not crowd_snapshot) if live_state.is_empty() else live_state
	state.erase("region_snapshot")
	if hot:
		var delivery_snapshot := _region_prepare_deliveries(state)
		if not delivery_snapshot.ok: return delivery_snapshot
	if not state.has("actors"):
		state["actors"] = {}
	if not state.has("armies"):
		state["armies"] = []
	if not raw_fire.is_empty():
		var cursor: Variant = data.get_meta(&"fire_completed_action_end", raw_fire.get("observed_action_end", -1.0))
		var settlement: Variant = state.get("fire_settlement", {})
		if settlement is Dictionary and settlement.has("action_seconds"): cursor = settlement.action_seconds
		if not Runtime._fire_time_valid(cursor): return Runtime.fail("INVALID_FIRE_BARRIER")
		var fire_snapshot := _region_capture_fire(data, float(cursor), region_capture) if hot else Runtime.capture_fire_snapshot(data, float(cursor))
		if not fire_snapshot.ok: return fire_snapshot
		state["fire"] = fire_snapshot.state
	var transport_snapshot: Dictionary
	var transport_wire: Dictionary
	if data.has_meta(&"fire_transport_snapshot"):
		var capture: Variant = (data.get_meta(&"region_fire_transport_snapshot") if data.has_meta(&"region_fire_transport_snapshot") else null) if hot else data.get_meta(&"fire_transport_snapshot")
		if not capture is Callable or not capture.is_valid(): return Runtime.fail("BUSY", "Fire transport owner unavailable")
		if hot:
			var original: Variant = data.get_meta(&"site_garrison_lab") if data.has_meta(&"site_garrison_lab") else null
			if original is WeakRef: original = original.get_ref()
			if original == null or not is_instance_valid(original) or capture.get_object() != original or original.get("terrain") != data:
				return Runtime.fail("STALE_REGION_FIRE_OWNER")
		var captured: Variant = capture.call(region_capture.context, region_capture.owners) if hot else capture.call()
		if not captured is Dictionary or not captured.get("ok") is bool: return Runtime.fail("BUSY", "Invalid fire transport capture")
		if not captured.ok: return captured
		if hot:
			for field: String in ["token", "source_generation", "runtime_revision", "game_seconds", "action_seconds", "fire_epoch", "fire_sequence"]:
				if captured.get(field) != region_capture.context.get(field): return Runtime.fail("STALE_REGION_FIRE_OWNER")
			if captured.get("owner_graph_hash") != RegionCheckpoint.state_hash({"graph": region_capture.owners.scene}):
				return Runtime.fail("STALE_REGION_FIRE_OWNER")
		transport_snapshot = captured.get("state", {})
		var checked_capture := _validate_fire_transport_snapshot(data, raw_fire, transport_snapshot, pending_action_cursor)
		if not checked_capture.ok: return checked_capture
		transport_snapshot = checked_capture.state
		transport_wire = checked_capture.wire
	else:
		var checked_transport := _validate_fire_transport_snapshot(data, raw_fire, state.get("fire_transport", {}), pending_action_cursor)
		if not checked_transport.ok: return checked_transport
		transport_snapshot = checked_transport.state
		transport_wire = checked_transport.wire
	if transport_snapshot.is_empty(): state.erase("fire_transport")
	else:
		var fire_owner_validation := _validate_fire_transport_owners(data, state, transport_snapshot)
		if not fire_owner_validation.ok: return fire_owner_validation
		state["fire_transport"] = transport_wire
	var fire_owner_snapshot: Variant = state.get("fire_owners", {})
	if bool(scene_capture.complete):
		# The same full original graph includes all PA jobs, FireNavigation and
		# shared leases. The old Fire-only exporter deliberately refuses those
		# other jobs; retaining a stale duplicate snapshot would reset them.
		fire_owner_snapshot = {}
	elif data.has_meta(&"fire_owner_snapshot"):
		var capture: Variant = data.get_meta(&"fire_owner_snapshot")
		if not capture is Callable or not capture.is_valid(): return Runtime.fail("BUSY", "Fire owner snapshot unavailable")
		var captured: Variant = capture.call()
		if not captured is Dictionary or not captured.get("ok") is bool: return Runtime.fail("BUSY", "Invalid Fire owner snapshot")
		if not captured.ok: return captured
		fire_owner_snapshot = captured.get("state", {})
	if fire_owner_snapshot is Dictionary and fire_owner_snapshot.is_empty():
		state.erase("fire_owners")
	else:
		var owner_cursor := float(fire_owner_snapshot.get("action_cursor", -1.0)) if fire_owner_snapshot is Dictionary else -1.0
		var checked_owners := _validate_fire_owner_snapshot(data, state, fire_owner_snapshot, owner_cursor)
		if not checked_owners.ok: return checked_owners
		var owner_fire: Dictionary = state.get("fire", {})
		var owner_settlement: Variant = state.get("fire_settlement", {})
		var expected_owner_cursor: Variant = owner_fire.get("observed_action_end", -1.0)
		if owner_settlement is Dictionary and owner_settlement.has("action_seconds"): expected_owner_cursor = owner_settlement.action_seconds
		if expected_owner_cursor != -1.0 and absf(float(expected_owner_cursor) - owner_cursor) > Runtime.FIRE_EPS and not _region_cursor_matches_pending(owner_cursor, pending_action_cursor, float(expected_owner_cursor)) \
			or not transport_snapshot.is_empty() and absf(float(transport_snapshot.action_cursor) - owner_cursor) > Runtime.FIRE_EPS:
			return Runtime.fail("FIRE_CLOCK_MISMATCH", "owner=%s settlement=%s transport=%s" % [str(owner_cursor),
				str(expected_owner_cursor), str(transport_snapshot.get("action_cursor", -1.0))])
		state["fire_owners"] = checked_owners.state
	if not hot and float(data.site.combat_left) > 0.0 and (not data.has_meta(&"fire_transport_snapshot")
		or transport_snapshot.get("projectiles", []).is_empty()):
		return Runtime.fail("BUSY", "地圖保存會等到脫戰；本版不保存戰鬥中的角色與投射物")
	var identity_validation := _validate_travel_identity(state)
	if not identity_validation.ok: return identity_validation
	var layout_validation := _validate_site_values(data, state)
	if not layout_validation.ok: return layout_validation
	var surface_inputs := _validate_siege_surface_inputs(data, state, hot)
	if not surface_inputs.ok: return surface_inputs
	# Validate the saved features' projection, never a stale live navigation cache.
	var candidate_data := Env.navigation_for_state(data, state)
	data = candidate_data
	var tower_layouts := _validate_siege_tower_layouts(data, state)
	if not tower_layouts.ok: return tower_layouts
	for feature: Dictionary in state.features.values():
		var feature_validation := Runtime.validate_feature_layout(data, feature)
		if not feature_validation.ok: return feature_validation
	var crowd_validation := _validate_crowd(data, state, 1, native_candidate)
	if not crowd_validation.ok: return crowd_validation
	var item_migration := Runtime.initialize_item_storage(state)
	if not item_migration.ok:
		return item_migration
	var item_validation := _validate_items(data, state, region_capture.get("context", {}))
	if not item_validation.ok:
		return item_validation
	var army_validation := _validate_armies(data, state, true)
	if not army_validation.ok:
		return army_validation
	var vehicle_validation := _validate_vehicles(data, state, true, region_capture.get("context", {}))
	if not vehicle_validation.ok:
		return vehicle_validation
	var army_assets := _validate_army_assets(data, state)
	if not army_assets.ok:
		return army_assets
	var actor_validation := _validate_actors(data, state)
	if not actor_validation.ok:
		return actor_validation
	var military_validation := _validate_military(data, state)
	if not military_validation.ok:
		return military_validation
	var corps_validation := _validate_corps(state)
	if not corps_validation.ok:
		return corps_validation
	var cape_validation := _validate_cape_roles(state)
	if not cape_validation.ok: return cape_validation
	var trade_validation: Dictionary = Trade.validate_snapshot(state, float(region_capture.get("context", {}).get("action_seconds", -1.0)), data)
	if not trade_validation.ok: return trade_validation
	var allocator_validation := _validate_person_allocator(state)
	if not allocator_validation.ok:
		return allocator_validation
	var supply_validation := _validate_supply(state, data, region_capture.get("context", {}))
	if not supply_validation.ok:
		return supply_validation
	var opened_validation := _validate_settled_opened_food(state)
	if not opened_validation.ok:
		return opened_validation
	if crowd_validation.has("native"):
		# A supplied World is the live capture owner: validate it without any setter.
		# A null argument was recreated privately by _validate_crowd, so only that
		# detached World may rebuild derived navigation/crew after every validator.
		if native_candidate == null:
			var navigation_restore := _restore_crowd_navigation(data, crowd_validation.native)
			if not navigation_restore.ok: return navigation_restore
		var crew_validation := _validate_crowd_siege_crew(state, crowd_validation.native, native_candidate == null)
		if not crew_validation.ok: return crew_validation
	state.erase("water_links")
	state.erase("water_status")
	state["notices"] = []
	if hot:
		# Hash the same detached canonical body that load_site returns. Optional
		# supply/housing defaults must exist before authentication, not appear
		# only after the persisted checkpoint has already been validated.
		_normalize_state(state)
		var checkpoint := RegionCheckpoint.make(state, region_capture.context, region_capture.owners)
		if not checkpoint.ok: return checkpoint
		state = checkpoint.state
		state["region_snapshot"] = checkpoint.snapshot
	var params: Dictionary = data.parameters.duplicate()
	params.erase("fixed_ramp_edges") # Rebuilt from the pinned source, never a saved authority.
	params["size"] = [data.size.x, data.size.y]
	var payload := {"format": FORMAT, "terrain_version": TERRAIN_VERSION, "environment_version": Env.VERSION,
		"preset": data.preset, "seed": data.seed_value, "parameters": params, "state": state}
	if capture_only:
		return Runtime.ok("", {"state": state, "context": region_capture.get("context", {}), "snapshot": state.get("region_snapshot", {}), "payload": payload, "owners": region_capture.get("owners", {})})
	# The checksum covers the exact stored JSON text, not sorted key order.
	# Keep full float precision and the ordinary snapshot encoding unchanged.
	var body := _stringify_crowd_payload(payload) if crowd_snapshot else JSON.stringify(payload, "", true, true)
	var wrapper := {"checksum": body.sha256_text(), "payload": body}
	if state.has("crowd"):
		# The original JSON payload and its checksum stay unchanged. Only its
		# envelope is compressed; decoded size is bounded before allocation.
		var original := body.to_utf8_buffer()
		if original.size() > MAX_BYTES:
			return Runtime.fail("SAVE_TOO_LARGE", "未壓縮存檔超過 32 MiB，原檔保留")
		var compressed := original.compress(FileAccess.COMPRESSION_ZSTD)
		if compressed.is_empty(): return Runtime.fail("SAVE_IO", "存檔壓縮失敗，原檔保留")
		wrapper["payload"] = Marshalls.raw_to_base64(compressed)
		wrapper["payload_encoding"] = CROWD_PAYLOAD_ENCODING
		wrapper["payload_bytes"] = original.size()
	var envelope := JSON.stringify(wrapper, "\t")
	if envelope.to_utf8_buffer().size() > MAX_BYTES:
		return Runtime.fail("SAVE_TOO_LARGE", "存檔超過 32 MiB，原存檔保留；未刪除任何現場物資")
	var absolute := ProjectSettings.globalize_path(path)
	var result := DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	if result != OK:
		return Runtime.fail("SAVE_IO", error_string(result))
	var temp_path := absolute + ".tmp"
	var backup_path := absolute + ".bak"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return Runtime.fail("SAVE_IO", error_string(FileAccess.get_open_error()))
	file.store_string(envelope)
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK or FileAccess.get_file_as_string(temp_path) != envelope:
		return Runtime.fail("SAVE_IO", "暫存檔寫入校驗失敗，原存檔保留")
	var had_original := FileAccess.file_exists(absolute)
	if had_original:
		if FileAccess.file_exists(backup_path):
			result = DirAccess.remove_absolute(backup_path)
			if result != OK:
				return Runtime.fail("SAVE_IO", error_string(result))
		result = DirAccess.rename_absolute(absolute, backup_path)
		if result != OK:
			return Runtime.fail("SAVE_IO", error_string(result))
	result = DirAccess.rename_absolute(temp_path, absolute)
	if result != OK:
		if had_original:
			DirAccess.rename_absolute(backup_path, absolute)
		return Runtime.fail("SAVE_IO", "替換失敗，保留／恢復上一份存檔")
	var committed_fire_owners: Variant = state.get("fire_owners", {})
	source_data.set_meta(&"fire_owner_checkpoint", committed_fire_owners.duplicate(true) if committed_fire_owners is Dictionary else {})
	invalidate_faction_summary_path(absolute)
	return Runtime.ok("地圖已保存", {"path": path})

class CrowdJsonBatch extends RefCounted:
	var values: Array = []
	var slots: Array[int] = []
	var parts: Array[String] = []

	func _append_value(value: Variant) -> void:
		slots.append(parts.size())
		parts.append("")
		values.append(value)

	func partition(value: Dictionary, depth: int = 0) -> void:
		parts.append("{")
		var first := true
		for key: Variant in value:
			if not first: parts.append(",")
			first = false
			# str(key) uses the same Variant::operator String as Godot JSON.
			parts.append(JSON.stringify(str(key), "", false, true) + ":")
			var text_key: bool = key is String or key is StringName
			if depth == 0 and text_key and key == "state":
				partition(value[key], 1)
			elif depth == 1 and text_key and key == "armies":
				parts.append("[")
				var first_roster := true
				for roster: Variant in value[key]:
					if not first_roster: parts.append(",")
					first_roster = false
					_append_value(roster)
				parts.append("]")
			else:
				_append_value(value[key])
		parts.append("}")

	func _encode_one(index: int) -> void:
		# Inputs remain unchanged until join; each worker writes a different slot.
		parts[slots[index]] = JSON.stringify(values[index], "", false, true)

	func encode() -> bool:
		var workers := mini(values.size(), clampi(OS.get_processor_count(), 1, 8))
		var group := WorkerThreadPool.add_group_task(_encode_one, values.size(), workers, true, "Crowd save JSON")
		if group < 0: return false
		WorkerThreadPool.wait_for_group_task_completion(group)
		for slot: int in slots:
			if parts[slot].is_empty(): return false
		return true

static func _stringify_crowd_payload(payload: Dictionary) -> String:
	if not Thread.is_main_thread() or OS.get_processor_count() < 2:
		return JSON.stringify(payload, "", false, true)
	var state: Variant = payload.get("state")
	if not state is Dictionary or not state.get("crowd") is Dictionary or not state.get("armies") is Array:
		return JSON.stringify(payload, "", false, true)
	if state.armies.size() < 2 or state.armies.size() > MAX_ARMIES:
		return JSON.stringify(payload, "", false, true)
	for roster: Variant in state.armies:
		if not roster is Dictionary: return JSON.stringify(payload, "", false, true)
	var kernel := TerrainArmy._get_idle_kernel()
	if kernel == null or not kernel.has_method("contains_json_unsupported") or kernel.contains_json_unsupported(payload):
		return JSON.stringify(payload, "", false, true)
	# Nonfinite leaves and callback-bearing values stay on the original caller thread.
	var batch := CrowdJsonBatch.new()
	batch.partition(payload)
	if not batch.encode(): return JSON.stringify(payload, "", false, true)
	return "".join(batch.parts)

static func load_site(path: String = DEFAULT_PATH, fixed_base_loader: Callable = Callable(), crowd_workers: int = 1, preserve_simulation: bool = false) -> Dictionary:
	var decoded := _read(path)
	if not decoded.ok:
		return decoded
	var payload: Dictionary = decoded.payload
	if not payload.state.get("id") is String:
		return Runtime.fail("CORRUPT_SAVE", "地圖身分")
	var params: Dictionary = payload.parameters.duplicate(true)
	params["size"] = Vector2i(int(params.size[0]), int(params.size[1]))
	var data: TerrainData
	var fixed_base: Variant = params.get("fixed_base")
	if fixed_base != null:
		if not fixed_base is Dictionary or fixed_base.get("base_kind") != "fixed_geography" \
				or not fixed_base.get("terrain_fingerprint") is String \
				or not fixed_base.get("site_id") is String:
			return Runtime.fail("CORRUPT_SAVE", "固定地圖基底識別非法")
		if not fixed_base_loader.is_valid():
			return Runtime.fail("SAVE_VERSION", "固定地圖基底尚未載入，原存檔保留")
		var loaded_base: Variant = fixed_base_loader.call(fixed_base)
		if not loaded_base is Dictionary or not bool(loaded_base.get("ok", false)) \
				or not loaded_base.get("data") is TerrainData or not _same_fixed_base(loaded_base.get("base"), fixed_base):
			return Runtime.fail("SAVE_VERSION", "固定地圖基底不相容，原存檔保留")
		data = loaded_base.data
		# The true source loader supplies the rule. Saved parameters cannot invent,
		# erase, change type or downgrade a declared source rule.
		if not _same_land_condition_rule(params, data.parameters, "fixed_land_condition_rule", "fixed_land_condition_rule"):
			return Runtime.fail("SAVE_VERSION", "Fixed land-condition source differs; original archive retained")
		if data.size != params.size or data.preset != int(payload.preset) \
				or data.seed_value != int(payload.seed) or not _same_fixed_base(data.parameters.get("fixed_base"), fixed_base) \
				or data.fingerprint() != str(fixed_base.terrain_fingerprint) \
				or not _resource_base_matches(data, fixed_base) \
				or str(fixed_base.site_id) != str(payload.state.id):
			return Runtime.fail("SAVE_VERSION", "固定地圖格網或來源版本不同，原存檔保留")
		if data.spawn_cell == Vector2i(-1, -1) and not payload.state.has("marine"):
			return Runtime.fail("NO_TARGET", "此地點沒有合法落腳點，僅能檢視地形")
	else:
		data = TerrainGenerator.generate(int(payload.preset), int(payload.seed), params)
	var definitions: Dictionary = Env.validate_resource_definitions(data, data.resource_base) if fixed_base != null else Runtime.ok()
	if not definitions.ok: return Runtime.fail("CORRUPT_SAVE", str(definitions.get("message", "Invalid resource definitions")))
	Env.initialize(data, str(payload.state.id))
	if RegionTerrainAdapter.has_author_identity(fixed_base) and RegionTerrainAdapter.author_environment_fingerprint(data) != str(fixed_base.effective_environment_sha256):
		return Runtime.fail("SAVE_VERSION", "作者環境基底摘要不符；原存檔保留")
	# Army paths and final slots must be checked against the terrain that was
	# actually saved. Validate the delta before applying it to this new data.
	var saved_terrain_changes: Variant = payload.state.get("terrain_changes", {})
	if not saved_terrain_changes is Dictionary:
		return Runtime.fail("CORRUPT_SAVE", "整地差異")
	for key: Variant in saved_terrain_changes.keys():
		if not key is String or not key.is_valid_int() or not _valid_cell(data, int(key)) or not _integer(saved_terrain_changes[key], 0, 5):
			return Runtime.fail("CORRUPT_SAVE", "整地差異")
		data.height_levels[int(key)] = int(saved_terrain_changes[key])
	if not saved_terrain_changes.is_empty():
		Runtime.rebuild_terrain_edges(data)
	var region_loaded := Runtime.ok()
	if payload.state.has("region_snapshot"):
		region_loaded = RegionCheckpoint.validate(payload.state, payload.state.region_snapshot)
		if not region_loaded.ok: return region_loaded
		if payload.state.has("crowd"): return Runtime.fail("REGION_BACKEND_UNADMITTED")
		preserve_simulation = true
	_normalize_boarding_numbers(payload.state)
	var validation := _validate_state(data, payload.state, crowd_workers, null, region_loaded.get("context", {}))
	if not validation.ok:
		return validation
	var legacy_ko_clock := false
	for actor: Dictionary in payload.state.get("actors", {}).values():
		legacy_ko_clock = legacy_ko_clock or actor.get("schema") == 1
	for team: Dictionary in payload.state.get("armies", []):
		legacy_ko_clock = legacy_ko_clock or team.get("schema") == 1
	# _read created this private payload for this call. Its validated crowd
	# state has no live/input owner to protect from normalization or migration.
	data.site = payload.state if payload.state.has("crowd") else payload.state.duplicate(true)
	# JSON numbers are normalized at the boundary; generated base is not in the save.
	_normalize_state(data.site)
	data.site["minute"] = int(data.site.minute)
	data.site["next_feature"] = int(data.site.next_feature)
	data.site["depot_cell"] = int(data.site.depot_cell)
	data.site["capacity"] = int(data.site.capacity)
	data.site.worker.cell = int(data.site.worker.cell)
	data.site.worker.progress = float(data.site.worker.progress)
	if not preserve_simulation:
		data.site.worker.mode = "idle" if str(data.site.worker.target).is_empty() else "travel"
		data.site["combat_left"] = 0.0
	data.site["water_links"] = {}
	data.site["water_status"] = {}
	data.site["notices"] = []
	Env.rebuild_indexes(data)
	Runtime.rebuild_water(data)
	Runtime.rebuild_loot_index(data)
	if not data.site.has("marine") and (not data.is_walkable(data.cell_from_index(int(data.site.worker.cell))) or not data.is_walkable(data.cell_from_index(int(data.site.get("player_cell", data.site.depot_cell))))):
		return Runtime.fail("CORRUPT_SAVE", "角色位於阻擋格")
	var actors: Dictionary = data.site.get("actors", {})
	for key: String in actors:
		var actor_cell := Vector2i(int(actors[key].cell[0]), int(actors[key].cell[1]))
		if not data.is_walkable(actor_cell):
			return Runtime.fail("CORRUPT_SAVE", "人物快照位於阻擋格")
	var army_validation := _validate_armies(data, data.site, true)
	if not army_validation.ok:
		return army_validation
	var vehicle_validation := _validate_vehicles(data, data.site, true, region_loaded.get("context", {}))
	if not vehicle_validation.ok:
		return vehicle_validation
	var army_assets := _validate_army_assets(data, data.site, true)
	if not army_assets.ok:
		return army_assets
	# Earlier format-3 deaths may have left real opened food at their private
	# owner. Migrate the validated loaded copy only, never rewrite the source file
	# or rerun the original person's death/animation/equipment initialization.
	var opened_migration := Runtime.migrate_settled_opened_food(data)
	if not opened_migration.ok:
		return opened_migration
	var opened_validation := _validate_settled_opened_food(data.site)
	if not opened_validation.ok:
		return opened_validation
	# Region first authenticates its exact selected source; its original owner
	# bind/replay then prepares and captures the detached ecology candidate.
	if not preserve_simulation:
		var ecology := prepare_ecology_candidate(data)
		if not ecology.ok: return ecology
		data = ecology.data
	var loaded := {"data": data}
	if preserve_simulation and not data.site.has("ecology_version"):
		loaded["ecology_migration_pending"] = true
	if payload.state.has("region_snapshot"):
		loaded["region_snapshot"] = region_loaded.snapshot
		loaded["region_context"] = region_loaded.context
		loaded["region_owners"] = region_loaded.owners
		loaded["owners_restored"] = false
		loaded["bind_complete"] = false
	if validation.has("crowd_native"):
		# This detached candidate belongs to this load result only, never the Site
		# snapshot or a persistent cache. Admission still rechecks its exact bytes.
		loaded["crowd_native"] = validation.crowd_native
	return Runtime.ok("已載入地圖；接續保存時刻" + ("（舊地圖沒有角色快照，首次使用初始角色狀態）" if bool(payload.get("legacy_actor_state", false)) else "") + ("（舊版昏迷剩餘秒數已按比例一次轉為遊戲秒）" if legacy_ko_clock else ""), loaded)

static func read_fixed_terrain_changes(path: String) -> Dictionary:
	# Region boundary refresh reads the original checksum-verified Site delta.
	# It does not create or modify a second copy of the Site state.
	var decoded := _read(path)
	if not decoded.ok:
		return decoded
	var payload: Dictionary = decoded.payload
	var base: Variant = payload.parameters.get("fixed_base")
	var changes: Variant = payload.state.get("terrain_changes")
	if not base is Dictionary or base.get("base_kind") != "fixed_geography" or not changes is Dictionary:
		return Runtime.fail("CORRUPT_SAVE", "固定地形修改格式非法")
	var size_value: Array = payload.parameters.size
	var count := int(size_value[0]) * int(size_value[1])
	for key: Variant in changes:
		if not key is String or not key.is_valid_int() or int(key) < 0 or int(key) >= count \
				or not _integer(changes[key], 0, 5):
			return Runtime.fail("CORRUPT_SAVE", "固定地形修改格位非法")
	return Runtime.ok("", {"base": base, "changes": changes})

# Reject non-String rules before JSON can erase their original Variant type.
static func _same_land_condition_rule(left: Dictionary, right: Dictionary, left_key: String, right_key: String) -> bool:
	if left.has(left_key) != right.has(right_key): return false
	if not left.has(left_key): return true
	return left[left_key] is String and right[right_key] is String \
		and left[left_key] == "terrain_mapped_potential_v1" and right[right_key] == left[left_key]

static func _same_fixed_base(left: Variant, right: Variant) -> bool:
	if not left is Dictionary or not right is Dictionary or left.size() != right.size():
		return false
	if not RegionTerrainAdapter.same_author_identity(left, right, true): return false
	for key: String in ["base_kind", "atlas_id", "base_revision", "manifest_sha256", "site_id", "terrain_fingerprint"]:
		if not left.get(key) is String or left.get(key) != right.get(key):
			return false
	if not _same_land_condition_rule(left, right, "land_condition_rule", "land_condition_rule"): return false
	if left.get("ramp_rule_revision", "") != right.get("ramp_rule_revision", ""):
		return false
	if not _same_resource_pin(left, right, true):
		return false
	if not _integer(left.get("grid_contract_version"), 1, 1000) \
			or not _integer(right.get("grid_contract_version"), 1, 1000) \
			or int(left.grid_contract_version) != int(right.get("grid_contract_version", -1)):
		return false
	var a: Variant = left.get("site")
	var b: Variant = right.get("site")
	return a is Array and b is Array and a.size() == 2 and b.size() == 2 \
		and _integer(a[0], -10000000, 10000000) and _integer(a[1], -10000000, 10000000) \
		and _integer(b[0], -10000000, 10000000) and _integer(b[1], -10000000, 10000000) \
		and int(a[0]) == int(b[0]) and int(a[1]) == int(b[1])

static func _same_resource_pin(left: Dictionary, right: Dictionary, include_fingerprint: bool = false) -> bool:
	var fields: Array[String] = ["resource_layer_sha256", "resource_rule_revision"]
	if include_fingerprint:
		fields.append("resource_fingerprint")
	var pinned := false
	for key: String in fields:
		pinned = pinned or left.has(key) or right.has(key)
	if not pinned:
		return true # Both sides are legacy geography-only bases.
	for key: String in fields:
		if not left.get(key) is String or not right.get(key) is String \
				or str(left[key]).is_empty() or left[key] != right[key]:
			return false
		if key != "resource_rule_revision" and (str(left[key]).length() != 64 or not str(left[key]).is_valid_hex_number(false)):
			return false
	return true

static func _resource_base_matches(data: TerrainData, base: Dictionary) -> bool:
	return _same_resource_pin(base, base, true) and (not base.has("resource_fingerprint") \
		or JSON.stringify(data.resource_base, "", true, true).sha256_text() == base.resource_fingerprint)

static func retire_default_worker(data: TerrainData) -> Dictionary:
	# The removed startup fixture must not respawn from an older save. This is
	# the same ground-stock departure contract as before_clear_team_items: retain
	# every physical item, and refuse to erase an established person's relations.
	# Generic snapshot reads and explicit NPC fixtures retain their original owner.
	if not data.site.get("actors", {}).has("npc") and Runtime.inventory_size(data.site.worker.cargo) == 0:
		return Runtime.ok()
	var original: Dictionary = data.site
	data.site = original.duplicate(true)
	var result := _retire_default_worker_copy(data)
	if not result.ok:
		data.site = original
		Runtime.rebuild_loot_index(data)
	return result

static func _retire_default_worker_copy(data: TerrainData) -> Dictionary:
	var state: Dictionary = data.site
	var actors: Dictionary = state.get("actors", {})
	var body: Dictionary = actors.get("npc", {})
	var identity := int(body.get("person_id", 2))
	var cargo: Dictionary = state.worker.cargo
	if not body.is_empty() and body.has("technology") and not body.technology.get("learned", []).is_empty():
		return Runtime.fail("BUSY", "舊工人已有原人技藝；須沿原人物遷移，不可由預設工人退役刪除")
	if body.is_empty():
		# Format-1 worker cargo has no actor snapshot. Its original fixed identity
		# may be used only when no surviving person already owns that identity.
		for actor: Dictionary in actors.values():
			if int(actor.person_id) == identity: return Runtime.fail("BUSY", "舊工人物資的原身分已被占用；原存檔保留")
		for team: Dictionary in state.get("armies", []):
			for unit: Dictionary in team.units:
				if int(unit.person_id) == identity: return Runtime.fail("BUSY", "舊工人物資的原身分已被占用；原存檔保留")
	if not body.is_empty():
		for team: Dictionary in state.get("crowd", {}).get("teams", []):
			if identity in team.get("person_ids", []):
				return Runtime.fail("INVALID_CROWD", "舊工人仍是群眾原人物；此場景沒有其呈現者，原存檔保留")
		if int(state.get("controlled_person_id", -1)) == identity:
			return Runtime.fail("BUSY", "舊工人仍是受控人物；原存檔保留，不能自動刪除原人物")
		for relative: Dictionary in state.get("family", {}).get("members", []):
			if str(relative.site_id) == str(state.id) and int(relative.person_id) == identity:
				return Runtime.fail("BUSY", "舊工人已列家族名單；原存檔保留，不能自動刪除家人")
		for nation: Dictionary in state.get("equipment_nations", {}).values():
			if nation.members.has(identity) or EquipmentOrders.office_holders(nation).has(identity):
				return Runtime.fail("BUSY", "舊工人仍有國別／職務引用；原存檔保留")
		if bool(body.captive):
			return Runtime.fail("BUSY", "舊工人仍受拘押；原存檔保留")
		for key: String in state.get("captivity", {}):
			var relation: Dictionary = state.captivity[key]
			if int(key) == identity or int(relation.captor_id) == identity or int(relation.guard_id) == identity:
				return Runtime.fail("BUSY", "舊工人仍有俘虜／看守關係；原存檔保留")
		for key: String in state.get("escort_orders", {}):
			if int(key) == identity or state.escort_orders[key].captives.has(identity):
				return Runtime.fail("BUSY", "舊工人仍有押送關係；原存檔保留")
		for actor: Dictionary in actors.values():
			if float(actor._rescue_left) > 0.0 and (int(actor.person_id) == identity or int(actor.rescue_target) == identity):
				return Runtime.fail("BUSY", "舊工人仍有救助關係；原存檔保留")
		for team: Dictionary in state.get("armies", []):
			if int(team.get("player_member", {}).get("id", -1)) == identity or int(team.get("pursuit_target", -1)) == identity:
				return Runtime.fail("BUSY", "舊工人仍有隊伍／追擊關係；原存檔保留")
		for vehicle: Dictionary in state.get("vehicles", {}).values():
			if int(vehicle.get("operator_id", -1)) == identity:
				return Runtime.fail("BUSY", "舊工人仍是原車輛操作人；原存檔保留")
		var transport: Variant = state.get("fire_transport", {})
		if transport is Dictionary and not transport.is_empty():
			var reservations: Variant = transport.get("reservations", [])
			if reservations is Dictionary and reservations.has(identity): return Runtime.fail("BUSY", "舊工人仍有原射擊準備；原存檔保留")
			for reservation: Variant in (reservations.values() if reservations is Dictionary else reservations):
				if reservation is Dictionary and int(reservation.get("person_id", 0)) == identity:
					return Runtime.fail("BUSY", "舊工人仍有原射擊準備；原存檔保留")
			for flight: Variant in transport.get("projectiles", []):
				if flight is Dictionary and int(flight.get("source_member_id", 0)) == identity:
					return Runtime.fail("BUSY", "舊工人仍有飛行中的原射擊；原存檔保留")
		for key: String in state.get("person_supply", {}):
			for member: int in Sustain._ids(state.person_supply[key]):
				if int(key) == identity and member != identity or int(key) != identity and member == identity:
					return Runtime.fail("BUSY", "舊工人仍與他人共用餐份歷史；原存檔保留")
		for supply: Dictionary in state.get("team_supply", {}).values():
			if identity in Sustain._ids(supply.sustain):
				return Runtime.fail("BUSY", "舊工人仍屬原隊伍供養；原存檔保留")
	var holder: Dictionary = body.get("item_state", {})
	if holder.is_empty():
		if body.is_empty():
			holder = Runtime.new_item_state("person:%d" % identity)
		else:
			var seeded := Runtime.seed_person_equipment(data, holder, identity, body.appearance)
			if not seeded.ok: return seeded
	var pool: Dictionary = state.get("person_supply", {}).get(str(identity), {})
	var dropped := Runtime.leave_ground_loot(data, holder, cargo, identity, data.cell_from_index(int(state.worker.cell)), "cargo", cargo, holder.item_ids.duplicate(), int(holder.version), pool, float(pool.get("open_rations", 0.0)))
	if not dropped.ok and str(dropped.code) != "EMPTY": return dropped
	state.get("person_supply", {}).erase(str(identity))
	actors.erase("npc")
	# The retired actor's own idle Fire order and cursor leave with it; the shared
	# release watermark (release_sequence) is unchanged.
	var fire_transport: Variant = state.get("fire_transport", {})
	if fire_transport is Dictionary and not fire_transport.is_empty():
		# Loaded state keys orders/cursors by group; the wire form lists them.
		var retired_group := -identity
		for field: String in ["orders", "member_cursor"]:
			var entries: Variant = fire_transport.get(field)
			if entries is Dictionary:
				entries.erase(retired_group)
			elif entries is Array:
				var kept: Array = []
				for entry: Variant in entries:
					var group: Variant = entry.get("group") if entry is Dictionary else (entry[0] if entry is Array and not entry.is_empty() else null)
					if group == null or int(group) != retired_group: kept.append(entry)
				fire_transport[field] = kept
	for actor: Dictionary in actors.values():
		if int(actor.get("attack_target", 0)) == identity: actor.attack_target = 0
		actor.hit_ids.erase(identity)
	for team: Dictionary in state.get("armies", []):
		for unit: Dictionary in team.units:
			if int(unit.get("target", -1)) == identity: unit.target = -1
			unit.hits.erase(identity)
	if state.has("next_person_id"):
		state["next_person_id"] = maxi(int(state.next_person_id), identity + 1)
	state["worker_enabled"] = false
	state.worker.merge({"target": "", "action": "harvest", "progress": 0.0, "mode": "idle", "status": "開場測試工人已移除", "zone": -1, "manual_control": false}, true)
	return _validate_state(data, state)

static func _validate_army_assets(data: TerrainData, state: Dictionary, fresh: bool = false) -> Dictionary:
	if state.get("armies", []).is_empty(): return Runtime.ok()
	var has_ordinary := false
	for roster: Dictionary in state.armies:
		has_ordinary = has_ordinary or not bool(roster.get("crowd", false))
	if not has_ordinary: return Runtime.ok()
	if not TerrainArmy.load_combat_bake():
		return Runtime.fail("MISSING_ASSET", "軍隊圖集／碰撞資料缺失；未替換目前地圖")
	if fresh:
		TerrainArmy.EquipmentAtlas.refresh_female_sources()
	var checked := {}
	for original: Dictionary in state.armies:
		if bool(original.get("crowd", false)): continue
		for unit: Dictionary in TerrainArmy.normalize_roster_snapshot(original).units:
			if str(unit.visual_role).ends_with("live") or not unit.has("appearance"):
				continue # Legacy rows without equipment retain the admitted baseline.
			var appearance: Dictionary = unit.appearance
			if unit.has("item_state"):
				var holder: Dictionary = unit.item_state
				if float(unit.hp) <= 0.0 and bool(unit.get("loot_settled", false)):
					holder = state.ground_loot.get(str(unit.get("remains_id", "")), Runtime.new_item_state("empty-remains"))
				appearance = Runtime.equipment_appearance(data, holder, appearance, state)
			var key := JSON.stringify(appearance)
			if checked.has(key): continue
			var baseline: bool = not appearance.is_empty() and appearance.get("body") == 0 and HumanCharacter3DEditor.EquipmentDye.geometry_appearance(appearance) == TerrainArmy._combat_bake.manifest.appearance and TerrainArmy.EquipmentAtlas.DyeAtlas.supports(appearance)
			if not baseline and not TerrainArmy.EquipmentAtlas.supports(appearance):
				return Runtime.fail("MISSING_ASSET", "人物 #%d 的實際配裝缺少完整圖集／染色；未替換目前地圖或存檔" % int(unit.person_id))
			checked[key] = true
	return Runtime.ok()

static func _validate_cape_roles(state: Dictionary) -> Dictionary:
	# Called only after existing people, roster and item validation. Read original
	# identities/holders, including legacy appearance-only people; never mint ranks
	# or rewrite the incoming save to make an unsupported costume appear valid.
	var people: Dictionary = {}
	var permitted := {}
	for actor: Dictionary in state.get("actors", {}).values():
		people[int(actor.person_id)] = actor
		if str(actor.get("military_role", _legacy_actor_military_role(actor, state))) == "officer":
			permitted[int(actor.person_id)] = true
	for nation: Dictionary in state.get("equipment_nations", {}).values():
		var identity := EquipmentOrders.military_head(nation)
		if EquipmentOrders._member(nation, identity): permitted[identity] = true
	for original: Dictionary in state.get("armies", []):
		var team: Dictionary = original if original.get("crowd") == true else TerrainArmy.normalize_roster_snapshot(original)
		var service: Array = team.get("officer_service", team.get("officers", []))
		for index in range(team.units.size()):
			var row: Dictionary = team.units[index]
			var identity := int(row.person_id)
			people[identity] = row
			if str(row.get("military_role", _legacy_row_military_role(team, index))) == "officer" or bool(row.get("member", true)) and not bool(row.get("departed", false)) and EquipmentOrders.rank_grants_cape(index, int(team.get("formal_commander", -1)), service, team.get("officers", [])):
				permitted[identity] = true
		if not team.get("player_member", {}).is_empty() and EquipmentOrders.rank_grants_cape(TerrainArmy.PLAYER_MEMBER, int(team.get("formal_commander", -1)), service, team.get("officers", [])):
			permitted[int(team.player_member.id)] = true
	for identity: int in people:
		var person: Dictionary = people[identity]
		if float(person.hp) <= 0.0 or permitted.has(identity): continue
		var wears_cape: bool = person.item_state.equipped.has("cape") if person.has("item_state") else str(person.get("appearance", {}).get("parts", {}).get("cape", "none")) != "none"
		if wears_cape:
			return Runtime.fail("CAPE_ROLE_RESTRICTED", "原人物 %d 並非現任軍官以上；披風須先卸回本人行囊，未替換現場或改寫存檔" % identity)
	return Runtime.ok()

static func _legacy_row_military_role(team: Dictionary, index: int) -> String:
	if index in [int(team.get("formal_commander", -1)), int(team.get("acting_commander", -1)), int(team.get("current_commander", -1))] \
		or index in team.get("officers", []) or index in team.get("officer_service", []):
		return "officer"
	return "soldier"

static func _legacy_actor_military_role(actor: Dictionary, state: Dictionary) -> String:
	for original: Dictionary in state.get("armies", []):
		if int(original.get("player_member", {}).get("id", -1)) != int(actor.get("person_id", 0)):
			continue
		var team: Dictionary = original if original.get("crowd") == true else TerrainArmy.normalize_roster_snapshot(original)
		return _legacy_row_military_role(team, TerrainArmy.PLAYER_MEMBER)
	return "civilian"

static func _validate_military(data: TerrainData, state: Dictionary) -> Dictionary:
	for actor: Dictionary in state.get("actors", {}).values():
		var role: Variant = actor.get("military_role", _legacy_actor_military_role(actor, state))
		if not role is String or role not in ["officer", "soldier", "civilian"]:
			return Runtime.fail("CORRUPT_SAVE", "原人物軍官／士兵／平民資格")
		if actor.has("personality") and not TerrainTestCharacter.PersonPersonality.valid(actor.personality):
			return Runtime.fail("CORRUPT_SAVE", "原人物性格資料")
		if actor.has("social_state") and not TerrainTestCharacter.PersonSocial.valid(actor.social_state):
			return Runtime.fail("CORRUPT_SAVE", "原人物社會狀態")
	var counts := {}
	for original: Dictionary in state.get("armies", []):
		var team: Dictionary = original if original.get("crowd") == true else TerrainArmy.normalize_roster_snapshot(original)
		var garrison_id: Variant = team.get("garrison_feature_id", "")
		if not garrison_id is String:
			return Runtime.fail("CORRUPT_SAVE", "原駐營容器必須引用軍營身分")
		for index in range(team.units.size()):
			var row: Dictionary = team.units[index]
			var role: Variant = row.get("military_role", _legacy_row_military_role(team, index))
			if not role is String or role not in ["officer", "soldier", "civilian"]:
				return Runtime.fail("CORRUPT_SAVE", "原名冊軍官／士兵／平民資格")
			if row.has("personality") and not TerrainTestCharacter.PersonPersonality.valid(row.personality):
				return Runtime.fail("CORRUPT_SAVE", "原名冊人物性格資料")
			if row.has("social_state") and not TerrainTestCharacter.PersonSocial.valid(row.social_state):
				return Runtime.fail("CORRUPT_SAVE", "原名冊人物社會狀態")
		if str(garrison_id).is_empty():
			continue
		var feature: Dictionary = state.get("features", {}).get(garrison_id, {})
		if str(feature.get("kind", "")) != "barracks" or str(feature.get("stage", "")) != "complete" or int(feature.get("layout_version", 0)) != Runtime.BUILDING_LAYOUT_VERSION \
			or int(feature.get("owner_faction", -1)) != int(team.get("faction_id", -2)):
			return Runtime.fail("CORRUPT_SAVE", "駐營容器必須引用同 Site 同方已完工軍營")
		for field: String in ["formal_commander", "acting_commander", "current_commander"]:
			if not _integer(team.get(field, -1), -1, -1):
				return Runtime.fail("CORRUPT_SAVE", "未編成駐營容器不能保留指揮任命")
		for field: String in ["officers", "officer_service"]:
			if not team.get(field, []) is Array or not team.get(field, []).is_empty():
				return Runtime.fail("CORRUPT_SAVE", "未編成駐營容器不能保留指揮職表")
		var goal: Variant = team.get("goal", [-1, -1])
		if not goal is Array or goal.size() != 2 or not _integer(goal[0], -1, -1) or not _integer(goal[1], -1, -1):
			return Runtime.fail("CORRUPT_SAVE", "未編成駐營容器仍保留軍令目的地")
		if int(team.get("combat_order", -1)) != TerrainArmy.CombatOrder.HOLD or team.get("needs_attack_order") != true \
			or bool(team.get("combat_attacking", false)) or bool(team.get("tactical_ai", {}).get("enabled", false)) or float(team.get("pursuit_left", 0.0)) != 0.0 \
			or team.get("combat_move_plan") != null:
			return Runtime.fail("CORRUPT_SAVE", "未編成駐營容器仍有軍令或在途行軍")
		var inside := {}
		for index: int in Runtime.military_walkable_cells(data, feature):
			inside[index] = true
		if not team.get("player_member", {}).is_empty():
			return Runtime.fail("CORRUPT_SAVE", "駐營原人物須先沿原入退隊入口處理玩家隊員")
		var living := 0
		for row: Dictionary in team.units:
			if row.get("member", true) != true or bool(row.get("departed", false)) or bool(row.get("site_exited", false)):
				return Runtime.fail("CORRUPT_SAVE", "駐營容器含已離隊／出場人物")
			if not _valid_walkable_pair(data, row.get("slot")) or not inside.has(data.index(Vector2i(int(row.slot[0]), int(row.slot[1])))):
				return Runtime.fail("CORRUPT_SAVE", "原駐營人物的登記返營格不在軍營可站格")
			# Registration survives capture/escort/release. Current positions and
			# committed steps still obey the original people/captivity validators.
			if not _valid_walkable_pair(data, row.get("cell")):
				return Runtime.fail("CORRUPT_SAVE", "原駐營人物目前格位非法")
			var destination: Variant = row.get("destination", [-1, -1])
			if not _valid_xy_pair(data, destination):
				return Runtime.fail("CORRUPT_SAVE", "原駐營人物步進目的格格式")
			var next := Vector2i(int(destination[0]), int(destination[1]))
			if next != TerrainArmy.INVALID_CELL and not data.can_step(Vector2i(int(row.cell[0]), int(row.cell[1])), next):
				return Runtime.fail("CORRUPT_SAVE", "原駐營人物步進跨越非法地形")
			# Dead original rows remain validated and referenced, but are neither
			# military strength nor capacity. Every living registration reserves
			# capacity, including KO, captives and people returning from outside.
			living += int(float(row.get("hp", 0.0)) > 0.0)
		counts[garrison_id] = int(counts.get(garrison_id, 0)) + living
		if int(counts[garrison_id]) > Runtime.military_capacity(data, feature):
			return Runtime.fail("CORRUPT_SAVE", "軍營容量不能遺失或重複原人物")
	return Runtime.ok()

# T6 S4b: per-side in-kind trade tax receipts (site_runtime.gd, S4) are a top-level Site key "trade_tax_receipts".
# Keys are "trade_id:side". A missing key is a valid old save. Load validates before normalization, so whole-number
# JSON floats are admitted here and made int by _normalize_trade_tax_receipts.
const TRADE_RECEIPT_FIELDS := ["trade_id", "side", "collector", "percent", "received", "tax", "items", "request"]
const TRADE_RECEIPT_ID_MAX := 64
const TRADE_RECEIPT_SIDE_MAX := 128
const TRADE_RECEIPT_REQUEST_MAX := 1048576

static func validate_trade_tax_receipts(state: Dictionary) -> Dictionary:
	if not state.has("trade_tax_receipts"): return Runtime.ok()
	var store: Variant = state.trade_tax_receipts
	if not store is Dictionary: return Runtime.fail("CORRUPT_SAVE", "貿易稅收據格式")
	for key: Variant in store:
		var entry: Variant = store[key]
		if not key is String or not entry is Dictionary or not Technology.keys(entry, TRADE_RECEIPT_FIELDS) or not _trade_receipt_valid(str(key), entry):
			return Runtime.fail("CORRUPT_SAVE", "貿易稅收據")
	return Runtime.ok()

static func _trade_receipt_valid(key: String, entry: Dictionary) -> bool:
	var parts: PackedStringArray = key.split(":", true, 1)
	if parts.size() != 2 or parts[0].is_empty() or parts[0].length() > TRADE_RECEIPT_ID_MAX or parts[1].is_empty() or parts[1].length() > TRADE_RECEIPT_SIDE_MAX: return false
	if not entry.trade_id is String or str(entry.trade_id) != parts[0] or not entry.side is String or str(entry.side) != parts[1]: return false
	if not _integer(entry.percent, 1, Settlement.TRADE_TAX_MAX): return false
	var percent: int = int(entry.percent)
	if not entry.collector is String or str(entry.collector).is_empty() or str(entry.collector).length() > TRADE_RECEIPT_SIDE_MAX or str(entry.collector) == parts[1]: return false
	if not entry.request is String or str(entry.request).length() > TRADE_RECEIPT_REQUEST_MAX: return false
	if not entry.items is Array: return false
	for identity: Variant in entry.items:
		if not identity is String or str(identity).is_empty(): return false
	if not entry.received is Dictionary or not entry.tax is Dictionary: return false
	var received: Dictionary = entry.received
	var tax: Dictionary = entry.tax
	for resource: Variant in received:
		if not resource is String or str(resource).is_empty() or not _integer(received[resource], 1, 2147483647): return false
		# Exact tax rule of S4: floor(received * percent / 100) per resource; no tax entry means 0.
		var levied: int = int(received[resource]) * percent / 100
		if int(tax.get(resource, 0)) != levied: return false
	for resource: Variant in tax:
		if not resource is String or not received.has(resource) or not _integer(tax[resource], 1, 2147483647): return false
	return true

static func _normalize_trade_tax_receipts(state: Dictionary) -> void:
	var store: Variant = state.get("trade_tax_receipts")
	if not store is Dictionary: return
	for key: Variant in store.keys():
		var entry: Dictionary = store[key]
		entry["percent"] = int(entry.percent)
		for field: String in ["received", "tax"]:
			var amounts: Dictionary = entry[field]
			for resource: Variant in amounts.keys(): amounts[resource] = int(amounts[resource])

# T6 S5C: trade payment and nation-leg receipts (site_trade_nation_leg.gd) are a separate top-level key
# "trade_leg_receipts". Its shape differs from the S4 tax receipts (kind, nation_id, day, given, treasury_spend), so it
# has its own exact field set and validator. A missing key is a valid old save. Keys are "trade_id:side".
const TRADE_LEG_FIELDS := ["trade_id", "side", "kind", "nation_id", "day", "received", "given", "items", "treasury_spend", "request"]
const TRADE_LEG_KINDS := ["nation_leg", "trade"]

static func validate_trade_leg_receipts(state: Dictionary) -> Dictionary:
	if not state.has("trade_leg_receipts"): return Runtime.ok()
	var store: Variant = state.trade_leg_receipts
	if not store is Dictionary: return Runtime.fail("CORRUPT_SAVE", "交易付款收據格式")
	for key: Variant in store:
		var entry: Variant = store[key]
		if not key is String or not entry is Dictionary or not Technology.keys(entry, TRADE_LEG_FIELDS) or not _trade_leg_valid(str(key), entry):
			return Runtime.fail("CORRUPT_SAVE", "交易付款收據")
	return Runtime.ok()

static func _trade_leg_valid(key: String, entry: Dictionary) -> bool:
	var parts: PackedStringArray = key.split(":", true, 1)
	if parts.size() != 2 or parts[0].is_empty() or parts[0].length() > TRADE_RECEIPT_ID_MAX or parts[1].is_empty() or parts[1].length() > TRADE_RECEIPT_SIDE_MAX: return false
	if not entry.trade_id is String or str(entry.trade_id) != parts[0] or not entry.side is String or str(entry.side) != parts[1]: return false
	if not entry.kind is String or not (str(entry.kind) in TRADE_LEG_KINDS): return false
	if not entry.nation_id is String or str(entry.nation_id).length() > TRADE_RECEIPT_SIDE_MAX: return false
	# A nation-leg receipt names its nation; a plain trade receipt names none and spends no treasury coin.
	if (str(entry.kind) == "nation_leg") != (not str(entry.nation_id).is_empty()): return false
	if not _integer(entry.day, 0, 2147483646) or not _integer(entry.treasury_spend, 0, 1000000): return false
	if str(entry.kind) == "trade" and int(entry.treasury_spend) != 0: return false
	if not entry.request is String or str(entry.request).length() > TRADE_RECEIPT_REQUEST_MAX: return false
	if not entry.items is Array: return false
	for identity: Variant in entry.items:
		if not identity is String or str(identity).is_empty(): return false
	for field: String in ["received", "given"]:
		if not entry[field] is Dictionary: return false
		var amounts: Dictionary = entry[field]
		for resource: Variant in amounts:
			if not resource is String or str(resource).is_empty() or not _integer(amounts[resource], 1, 1000000): return false
	return true

static func _normalize_trade_leg_receipts(state: Dictionary) -> void:
	var store: Variant = state.get("trade_leg_receipts")
	if not store is Dictionary: return
	for key: Variant in store.keys():
		var entry: Dictionary = store[key]
		entry["day"] = int(entry.day)
		entry["treasury_spend"] = int(entry.treasury_spend)
		for field: String in ["received", "given"]:
			var amounts: Dictionary = entry[field]
			for resource: Variant in amounts.keys(): amounts[resource] = int(amounts[resource])

static func _normalize_portable_lineage(value: Variant) -> void:
	if value is Dictionary:
		if value.has("type") and value.has("namespace") and value.has("lineage") and (value.lineage is int or value.lineage is float):
			value.lineage = int(value.lineage)
		for key: Variant in value: _normalize_portable_lineage(value[key])
	elif value is Array:
		for entry: Variant in value: _normalize_portable_lineage(entry)

## B5E: JSON numbers load as floats. Integral floats in the vehicle and boarding link integer fields become int
## at the load boundary, before the contract's exact-type checks. Non-integral values are left untouched.
static func _normalize_boarding_numbers(state: Dictionary) -> void:
	var vehicles: Variant = state.get("vehicles", {})
	if not vehicles is Dictionary: return
	for identity: Variant in vehicles:
		var vehicle: Variant = vehicles[identity]
		if not vehicle is Dictionary: continue
		var naval: Variant = vehicle.get("naval")
		if not naval is Dictionary: continue
		var link: Variant = naval.get("boarding_link")
		if not link is Dictionary: continue
		_int_field_b5e(vehicle, "cell")
		_int_field_b5e(vehicle, "revision")
		if vehicle.get("facing") is Array:
			for index: int in range(vehicle.facing.size()): _int_index_b5e(vehicle.facing, index)
		_int_field_b5e(naval, "version")
		_int_field_b5e(naval, "link_epoch")
		_int_field_b5e(link, "version")
		_int_field_b5e(link, "epoch")
		_int_field_b5e(link, "crosser_id")
		for frame_key: String in ["frame", "peer_frame"]:
			var frame: Variant = link.get(frame_key)
			if not frame is Dictionary: continue
			for key: String in ["anchor", "facing"]:
				var values: Variant = frame.get(key)
				if values is Array:
					for index: int in range(values.size()): _int_index_b5e(values, index)

static func _int_field_b5e(holder: Dictionary, key: String) -> void:
	if holder.has(key) and (holder[key] is float) and is_finite(holder[key]) and holder[key] == floorf(holder[key]): holder[key] = int(holder[key])

static func _int_index_b5e(values: Array, index: int) -> void:
	var value: Variant = values[index]
	if (value is float) and is_finite(value) and value == floorf(value): values[index] = int(value)

static func _normalize_state(state: Dictionary) -> void:
	Trade.normalize_snapshot(state)
	_normalize_trade_tax_receipts(state)
	_normalize_trade_leg_receipts(state)
	# Raw identity was validated with all original candidate fields before this
	# normalizer runs. Only detached integer metadata is canonicalized.
	if state.has("travel_identity"):
		var original: GDScript = load("res://scripts/region_lab/region_travel.gd")
		state["travel_identity"] = original.normalize_identity(state.travel_identity)
	# Portable organization references compare by value; their lineage and the
	# container version are whole numbers like the travel identity they mirror.
	if state.get("organization_refs") is Dictionary:
		var portable: Dictionary = state.organization_refs
		if portable.has("version"): portable["version"] = int(portable.version)
		_normalize_portable_lineage(portable)
	if state.has("ecology_version"):
		state["ecology_version"] = int(state.ecology_version)
	# The validated world pin reads back with JSON numbers and an untyped list;
	# restore the integer fields and the policy's own canonical form.
	var world_pin: Variant = state.get("world_pin")
	if world_pin is Dictionary:
		for field: String in ["format", "grid_contract_version"]:
			if world_pin.has(field): world_pin[field] = int(world_pin[field])
		if world_pin.has("technology_policy"):
			var policy := TechnologyPolicy.validate(world_pin.technology_policy)
			if policy.ok: world_pin.technology_policy = policy.policy
	_normalize_fs_targets(state)
	Stockpiles.normalize(state)
	for corps: Dictionary in state.get("corps", {}).values():
		corps.version = int(corps.version)
		corps.commander_person_id = int(corps.commander_person_id)
		corps.team_ids = _int_array(corps.team_ids)
	if state.has("controlled_person_id"):
		state["controlled_person_id"] = int(state.controlled_person_id)
	for event: Dictionary in state.get("region_life_events", []):
		event.person_id = int(event.person_id)
		event.sequence = int(event.sequence)
		event.at = float(event.at)
		if event.kind == "supply_damage":
			for field: String in ["old_hp", "ending_hp", "loss"]: event[field] = float(event[field])
	if state.has("family"):
		state.family.version = int(state.family.version)
		if state.family.has("lineage_id"): state.family.lineage_id = int(state.family.lineage_id)
		if state.family.get("offices") is Dictionary: SiteOffices.normalize_numbers(state.family.offices)
		if state.family.get("succession") is Dictionary: EquipmentOrders.Succession.normalize_numbers(state.family.succession)
		if state.family.has("technology"): state.family.technology = Technology.normalize_family_tech(state.family.technology)
		for member: Dictionary in state.family.members:
			member.person_id = int(member.person_id)
			member.age_years = int(member.age_years)
	if state.get("family_departures") is Array:
		for entry: Dictionary in state.family_departures:
			entry.person_id = int(entry.person_id)
			entry.minute = int(entry.minute)
	if state.get("vacancy_episodes") is Dictionary: VacancyEpisode.normalize_episodes(state.vacancy_episodes)
	if state.has("next_lineage"):
		state["next_lineage"] = int(state.next_lineage)
	else:
		# Legacy Site without the counter: continue after its one version 4 identity, else start at 1.
		var legacy_family: Variant = state.get("family", {})
		state["next_lineage"] = int(legacy_family.get("lineage_id", 0)) + 1 if legacy_family is Dictionary and int(legacy_family.get("version", 0)) == 4 else 1
	if state.has("next_person_id"):
		state["next_person_id"] = int(state.next_person_id)
	if not state.has("team_supply"):
		state["team_supply"] = {}
	if not state.has("housing"): state["housing"] = {}
	Settlement.normalize(state)
	for registered: Dictionary in state.housing.values():
		registered.version = int(registered.version)
		registered.cell = int(registered.cell)
	if not state.has("person_supply"):
		state["person_supply"] = {}
	for sustain: Dictionary in state.person_supply.values():
		_normalize_sustain(sustain)
	for supply: Dictionary in state.team_supply.values():
		if int(supply.version) == 1:
			# Old location-free orders stop; earned training, meals and fatigue remain.
			supply.version = 2
			supply.training_feature_id = ""
			supply.training_order = false
			supply.training_requester = -1
		for field: String in ["version", "training_requester", "revision"]:
			supply[field] = int(supply[field])
		_normalize_sustain(supply.sustain)
		if int(supply.version) == 3:
			for location: Dictionary in supply.locations.values():
				for resource: String in location.inventory: location.inventory[resource] = int(location.inventory[resource])
		else:
			for resource: String in supply.inventory:
				supply.inventory[resource] = int(supply.inventory[resource])
		for identity: String in supply.life_checkpoint:
			supply.life_checkpoint[identity] = int(supply.life_checkpoint[identity])
	for field: String in ["item_storage_version", "next_loot", "next_item"]:
		state[field] = int(state[field])
	var item_holders: Array = [state.depot_items]
	if not state.has("vehicles"): state["vehicles"] = {}
	state["next_vehicle"] = int(state.get("next_vehicle", 1))
	for vehicle: Dictionary in state.vehicles.values():
		for field: String in ["cell", "team_id", "operator_id"]: vehicle[field] = int(vehicle[field])
		vehicle.facing = _int_array(vehicle.facing)
		if vehicle.has("travel_patients"):
			vehicle.travel_patients.version = int(vehicle.travel_patients.version)
			vehicle.travel_patients.reserved_capacity = int(vehicle.travel_patients.reserved_capacity)
			vehicle.travel_patients.person_ids = _int_array(vehicle.travel_patients.person_ids)
		if str(vehicle.kind) == "ship":
			for field: String in ["ship_version", "definition_version", "revision"]: vehicle[field] = int(vehicle[field])
			if not vehicle.command.is_empty(): vehicle.command.goal = int(vehicle.command.goal)
		if Runtime.SIEGE_DEFINITIONS.has(str(vehicle.kind)):
			# Raw v2/v3 shape and provenance were validated before migration.
			if int(vehicle.vehicle_version) == 2:
				vehicle.vehicle_version = 3
				vehicle.technology_capture = {}
			elif not vehicle.technology_capture.is_empty():
				for field: String in ["version", "source_team_id", "source_faction", "recipient_team_id", "recipient_faction"]:
					vehicle.technology_capture[field] = int(vehicle.technology_capture[field])
			if str(vehicle.kind) == "siege_tower" and not vehicle.deployed_pose.is_empty():
				for field: String in ["version", "cell", "level"]: vehicle.deployed_pose[field] = int(vehicle.deployed_pose[field])
				vehicle.deployed_pose.facing = _int_array(vehicle.deployed_pose.facing)
			for field: String in ["vehicle_version", "definition_version", "next_attack_seq", "rng_state"]: vehicle[field] = int(vehicle[field])
			# The raw ranged-action schema already admitted these bounded integers.
			# Restore their original types at the same JSON boundary as the vehicle.
			if str(vehicle.kind) in ["ballista", "traction_trebuchet", "counterweight_trebuchet"] \
				and str(vehicle.action.get("stage", "")) in ["loading", "aiming", "recovering"]:
				for field: String in ["cargo_version", "rng_state"]: vehicle.action[field] = int(vehicle.action[field])
			vehicle.hp = float(vehicle.hp)
			for slot: String in vehicle.crew_slots: vehicle.crew_slots[slot] = int(vehicle.crew_slots[slot])
			for job: Dictionary in [vehicle.build, vehicle.repair]:
				for field: String in ["total_work", "progress", "amount", "applied"]:
					if job.has(field): job[field] = float(job[field])
				for resource: String in job.get("paid_cost", {}): job.paid_cost[resource] = int(job.paid_cost[resource])
			var target: Dictionary = vehicle.command.get("target", {})
			if target.get("type") == "person": target["person_id"] = int(target.person_id)
			if target.get("type") == "ground": target["cell"] = _int_array(target.cell)
		if not vehicle.move.is_empty():
			if str(vehicle.kind) == "ship":
				for field: String in ["from_cell", "cell"]: vehicle.move[field] = int(vehicle.move[field])
				vehicle.move.from_facing = _int_array(vehicle.move.from_facing)
				vehicle.move.elapsed = float(vehicle.move.elapsed)
				vehicle.move.duration = float(vehicle.move.duration)
			elif Runtime.SIEGE_DEFINITIONS.has(str(vehicle.kind)):
				for field: String in ["from", "cell", "priority_member"]:
					if vehicle.move.has(field): vehicle.move[field] = int(vehicle.move[field])
				vehicle.move.duration = float(vehicle.move.duration)
				for member: Dictionary in vehicle.move.participants:
					for field: String in ["person_id", "from", "to"]: member[field] = int(member[field])
				for key: String in vehicle.move.source_heights: vehicle.move.source_heights[key] = int(vehicle.move.source_heights[key])
			else:
				for field: String in ["cell", "operator_from", "operator_to"]: vehicle.move[field] = int(vehicle.move[field])
			vehicle.move.facing = _int_array(vehicle.move.facing)
			vehicle.move.sweep = _int_array(vehicle.move.sweep)
		for resource: String in vehicle.cargo: vehicle.cargo[resource] = int(vehicle.cargo[resource])
		item_holders.append(vehicle.holder)
	for container: Dictionary in state.ground_loot.values():
		if container.has("vehicle_id"): container.local_position = [float(container.local_position[0]), float(container.local_position[1])]
		else: container.cell = int(container.cell)
		container.original_owner = int(container.original_owner)
		for resource: String in container.cargo:
			container.cargo[resource] = int(container.cargo[resource])
		item_holders.append(container)
	for actor: Dictionary in state.get("actors", {}).values():
		if actor.get("schema") == 1:
			var normalized_actor := TerrainTestCharacter.normalize_saved_state(actor)
			actor.clear()
			actor.merge(normalized_actor)
		if not actor.has("military_role"):
			actor.military_role = _legacy_actor_military_role(actor, state)
		if actor.has("technology"): actor.technology = Technology.normalize_person(actor.technology)
		if actor.has("item_state"):
			item_holders.append(actor.item_state)
	for team_index in range(state.get("armies", []).size()):
		if not bool(state.armies[team_index].get("crowd", false)):
			state.armies[team_index] = TerrainArmy.normalize_roster_snapshot(state.armies[team_index])
		else:
			var roster: Dictionary = state.armies[team_index]
			if not roster.has("garrison_feature_id"): roster["garrison_feature_id"] = ""
			for index in range(roster.units.size()):
				if not roster.units[index].has("military_role"):
					roster.units[index].military_role = _legacy_row_military_role(roster, index)
		for unit: Dictionary in state.armies[team_index].units:
			if unit.has("technology"): unit.technology = Technology.normalize_person(unit.technology)
			if unit.has("berth_id"): unit.berth_id = int(unit.berth_id)
			if unit.has("work_task"):
				unit.work_task = WorkTeam.normalize_task(unit.work_task)
			if unit.has("item_state"):
				item_holders.append(unit.item_state)
			for resource: String in unit.get("cargo", {}):
				unit.cargo[resource] = int(unit.cargo[resource])
	for holder: Dictionary in item_holders:
		holder.version = int(holder.version)
		for field: String in ["fire_lab_suppression_q", "fire_lab_ignition_q"]:
			if holder.has(field): holder[field] = int(holder[field])
	for record: Dictionary in state.item_records.values():
		record.original_owner = int(record.original_owner)
	for relation_key: String in state.get("captivity", {}):
		var relation: Dictionary = state.captivity[relation_key]
		for field: String in ["version", "captor_id", "guard_id", "captor_faction"]:
			relation[field] = int(relation[field])
		if int(relation.version) == 1:
			relation["version"] = 2
			relation["prison_id"] = ""
		if int(relation.version) == 2:
			# F02 / plan 6.1 one-time migration: true times, loyalty and rank of old
			# records are unknown, so they count from this load (legacy_observed),
			# with no loyal organization and an "unknown" rank; then saved as v3.
			var seconds := (float(state.get("minute", 0)) + float(state.get("phase", 0.0))) * 60.0
			relation["version"] = 3
			relation["captured_at_game_seconds"] = seconds
			relation["admitted_at_game_seconds"] = seconds if not str(relation.prison_id).is_empty() else -1.0
			relation["episode"] = {"site_id": str(state.get("id", "")), "person_id": int(relation_key), "seq": 0}
			relation["loyal_org"] = null
			relation["rank_snapshot"] = "unknown"
			relation["settled_days"] = 0
			relation["legacy_observed"] = true
		relation["captured_at_game_seconds"] = float(relation.captured_at_game_seconds)
		relation["admitted_at_game_seconds"] = float(relation.admitted_at_game_seconds)
		relation["settled_days"] = int(relation.settled_days)
		relation.episode.person_id = int(relation.episode.person_id)
		relation.episode.seq = int(relation.episode.seq)
	for nation: Dictionary in state.get("equipment_nations", {}).values():
		if nation.has("faction_id"): nation.faction_id = int(nation.faction_id); nation.faction_version = int(nation.faction_version)
		if nation.has("military_head"): nation.military_head = int(nation.military_head)
		if nation.get("ransom_data") is Dictionary: EquipmentOrders.RansomData.normalize_numbers(nation.ransom_data)
		if nation.get("succession") is Dictionary: EquipmentOrders.Succession.normalize_numbers(nation.succession)
		if nation.get("offices") is Dictionary: SiteOffices.normalize_numbers(nation.offices)
		for index in range(nation.members.size()):
			nation.members[index] = int(nation.members[index])
		for standard: Dictionary in nation.standards.values():
			standard.revision = int(standard.revision)
	# Nation research and public/military operation records carry JSON numbers too;
	# their own normalizer validates first and leaves an invalid state untouched.
	if state.get("equipment_nations") is Dictionary and not state.equipment_nations.is_empty():
		EquipmentOrders.normalize_nation_operations(state)
	for order: Dictionary in state.get("escort_orders", {}).values():
		order.destination = int(order.destination)
		if order.has("version"): order.version = int(order.version)
		for identity: String in order.get("targets", {}): order.targets[identity] = int(order.targets[identity])
		for index in range(order.captives.size()):
			order.captives[index] = int(order.captives[index])
	for item: String in state.inventory:
		state.inventory[item] = int(state.inventory[item])
	for key: String in state.changes:
		for field: String in ["remaining", "next_recovery", "used_minute"]:
			if state.changes[key].has(field):
				state.changes[key][field] = int(state.changes[key][field])
	for key: String in state.terrain_changes:
		state.terrain_changes[key] = int(state.terrain_changes[key])
	for actor_key: String in ["worker", "manual"]:
		var actor: Dictionary = state[actor_key]
		for field: String in ["zone", "cell", "work_cell"]:
			if actor.has(field):
				actor[field] = int(actor[field])
		for item: String in actor.cargo:
			actor.cargo[item] = int(actor.cargo[item])
	for key: String in state.features:
		var feature: Dictionary = state.features[key]
		feature["cells"] = _int_array(feature.cells)
		feature["entrance"] = int(feature.entrance)
		feature["level"] = int(feature.level)
		if str(feature.get("kind", "")) == "survey_stakes":
			feature.survey_plan.cells = _int_array(feature.survey_plan.cells)
			for field: String in feature.survey_plan.options:
				if field not in ["variant", "material", "camp_type"]: feature.survey_plan.options[field] = int(feature.survey_plan.options[field])
			feature.survey_operator.person_id = int(feature.survey_operator.person_id)
		if feature.has("barracks_layout_version"):
			feature["barracks_layout_version"] = int(feature.barracks_layout_version)
		if feature.has("waterfront_version"):
			feature["waterfront_version"] = int(feature.waterfront_version)
			feature["launch_cell"] = int(feature.launch_cell)
		if feature.has("ship_build"):
			for field: String in ["version", "recipe_version", "team_id"]: feature.ship_build[field] = int(feature.ship_build[field])
			feature.ship_build.total_work = float(feature.ship_build.total_work)
			for resource: String in feature.ship_build.paid_cost: feature.ship_build.paid_cost[resource] = int(feature.ship_build.paid_cost[resource])
		for field: String in ["civil_version", "building_grade", "layout_version", "fire_layout_version", "owner_faction", "quarter"]:
			if feature.has(field): feature[field] = int(feature[field])
		if feature.get("gate") is Dictionary and feature.gate.has("operator_id"): feature.gate.operator_id = int(feature.gate.operator_id)
		if feature.has("residents"):
			feature["residents"] = int(feature.residents)
		for item: String in feature.cost:
			feature.cost[item] = int(feature.cost[item])
		for field: String in ["pending_build", "repair"]:
			if feature.has(field):
				feature[field].work = float(feature[field].work)
				feature[field].progress = float(feature[field].progress)
				for item: String in feature[field].cost:
					feature[field].cost[item] = int(feature[field].cost[item])
		if feature.has("pending_build"):
			feature.pending_build.cells = _int_array(feature.pending_build.cells)
			feature.pending_build.added_cells = _int_array(feature.pending_build.added_cells)
			feature.pending_build.entrance = int(feature.pending_build.entrance)
			if feature.pending_build.has("target_grade"): feature.pending_build.target_grade = int(feature.pending_build.target_grade)
			if feature.pending_build.has("target_level"): feature.pending_build.target_level = int(feature.pending_build.target_level)
		if feature.has("repair"):
			feature.repair.amount = float(feature.repair.amount)
			feature.repair.work_cell = int(feature.repair.work_cell)
	for zone: Dictionary in state.zones:
		zone.cells = _int_array(zone.cells)
		zone.kind = int(zone.kind)
	state["total_produced"] = int(state.total_produced)
	if state.has("player_cell"):
		state["player_cell"] = int(state.player_cell)

static func _int_array(values: Array) -> Array[int]:
	var result: Array[int] = []
	for value: Variant in values:
		result.append(int(value))
	return result

static func _normalize_sustain(state: Dictionary) -> void:
	state["version"] = int(state.version)
	state["last_combat_event"] = int(state.last_combat_event)
	for cohort: Dictionary in state.cohorts:
		cohort.ids = _int_array(cohort.ids)

static func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return Runtime.fail("NO_SAVE", "尚無保存地圖")
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return Runtime.fail("SAVE_IO", error_string(FileAccess.get_open_error()))
	if file.get_length() > MAX_BYTES or file.get_length() < 10:
		file.close()
		return Runtime.fail("CORRUPT_SAVE", "檔案大小不合法")
	var text := file.get_as_text()
	file.close()
	var envelope_parser := JSON.new()
	if envelope_parser.parse(text) != OK:
		return Runtime.fail("CORRUPT_SAVE", "檔案不是有效 JSON，原檔保留")
	var envelope: Variant = envelope_parser.data
	if not envelope is Dictionary or not envelope.get("payload") is String or not envelope.get("checksum") is String:
		return Runtime.fail("CORRUPT_SAVE", "格式損壞；可嘗試上一份 .bak")
	var body: String = envelope.payload
	if envelope.has("payload_encoding"):
		if envelope.payload_encoding != CROWD_PAYLOAD_ENCODING or not _integer(envelope.get("payload_bytes"), 1, MAX_BYTES):
			return Runtime.fail("CORRUPT_SAVE", "存檔壓縮格式或展開大小非法")
		var compressed := Marshalls.base64_to_raw(body)
		if compressed.is_empty() or Marshalls.raw_to_base64(compressed) != body:
			return Runtime.fail("CORRUPT_SAVE", "存檔壓縮內容不是合法 base64")
		var original := compressed.decompress(int(envelope.payload_bytes), FileAccess.COMPRESSION_ZSTD)
		if original.size() != int(envelope.payload_bytes):
			return Runtime.fail("CORRUPT_SAVE", "存檔壓縮內容或展開大小不符")
		body = original.get_string_from_utf8()
		if body.to_utf8_buffer() != original: return Runtime.fail("CORRUPT_SAVE", "存檔壓縮內容不是 UTF-8")
	if body.sha256_text() != str(envelope.checksum):
		return Runtime.fail("CORRUPT_SAVE", "校驗失敗，未修改目前地圖")
	var payload_parser := JSON.new()
	if payload_parser.parse(body) != OK:
		return Runtime.fail("CORRUPT_SAVE", "內容不是有效 JSON，原檔保留")
	var payload: Variant = payload_parser.data
	if not payload is Dictionary:
		return Runtime.fail("CORRUPT_SAVE")
	if not _integer(payload.get("format"), 1, FORMAT) or int(payload.get("terrain_version", -1)) != TERRAIN_VERSION or int(payload.get("environment_version", -1)) != Env.VERSION:
		return Runtime.fail("SAVE_VERSION", "生成／存檔版本不同，原檔保留")
	if not payload.get("state") is Dictionary or not payload.get("parameters") is Dictionary:
		return Runtime.fail("CORRUPT_SAVE")
	if int(payload.format) < 4:
		for nation: Variant in payload.state.get("equipment_nations", {}).values():
			if nation is Dictionary and (nation.has("faction_version") or nation.has("faction_id")): return Runtime.fail("SAVE_VERSION", "formal faction binding requires Site format 4")
	if int(payload.format) == 1:
		# Explicit migration of this Site format only; no retired World saves.
		payload.state["actors"] = {}
		payload["legacy_actor_state"] = true
	elif not payload.state.get("actors") is Dictionary:
		return Runtime.fail("CORRUPT_SAVE", "缺少人物快照欄位")
	if int(payload.format) < 3:
		payload.state["armies"] = []
		payload.state["army_trial_active"] = false
	elif not payload.state.get("armies") is Array:
		return Runtime.fail("CORRUPT_SAVE", "缺少軍隊快照欄位")
	var item_migration := Runtime.initialize_item_storage(payload.state)
	if not item_migration.ok:
		return item_migration
	if not _integer(payload.get("seed"), -2147483648, 2147483647) or not _integer(payload.get("preset"), 0, TerrainPreset.NAMES.size() - 1):
		return Runtime.fail("CORRUPT_SAVE", "seed／地貌非法")
	var size_value: Variant = payload.parameters.get("size")
	if not size_value is Array or size_value.size() != 2 or not _integer(size_value[0], 16, 128) or not _integer(size_value[1], 16, 128):
		return Runtime.fail("CORRUPT_SAVE", "地圖大小非法")
	if not _number(payload.parameters.get("max_height"), 1, 5) or not _number(payload.parameters.get("micro_strength"), 0, 0.04):
		return Runtime.fail("CORRUPT_SAVE", "生成參數非法")
	return Runtime.ok("", {"payload": payload, "checksum": str(envelope.checksum)})

static func _crowd_float_equal(left: Variant, right: Variant) -> bool:
	# JSON's decimal parser can move the final binary64 bit (for example long
	# KO timers). This bound covers that serialization round trip only; the
	# native blob and its exact hash remain the hot-state authority.
	if not (left is int or left is float) or not (right is int or right is float): return false
	var a := float(left)
	var b := float(right)
	return is_finite(a) and is_finite(b) and absf(a - b) <= CROWD_FLOAT_EPSILON * maxf(1.0, maxf(absf(a), absf(b)))

static func _validate_crowd(data: TerrainData, state: Dictionary, workers: int = 1, native_candidate: Variant = null) -> Dictionary:
	var rosters: Variant = state.get("armies", [])
	if not state.has("crowd"):
		if native_candidate != null:
			return Runtime.fail("INVALID_CROWD", "原生候選缺少群眾存檔區段")
		if rosters is Array:
			for roster: Variant in rosters:
				if roster is Dictionary and roster.has("crowd") and roster.crowd != false:
					return Runtime.fail("INVALID_CROWD", "群眾名冊缺少原生區段")
		return Runtime.ok() # Ordinary snapshots retain their original validators.
	if not rosters is Array: return Runtime.fail("INVALID_CROWD", "群眾名冊格式")
	var crowd_rosters := {}
	for roster: Variant in rosters:
		if not roster is Dictionary: return Runtime.fail("INVALID_CROWD", "人物名冊格式")
		if roster.has("crowd") and not roster.crowd is bool: return Runtime.fail("INVALID_CROWD", "群眾名冊標記")
		if bool(roster.get("crowd", false)):
			if not _integer(roster.get("schema"), 2, 2) or not _integer(roster.get("roster_version"), 1, 1) or not _integer(roster.get("team_id"), 1, 999999) or not _integer(roster.get("faction_id"), 0, 100000000) or not roster.get("units") is Array:
				return Runtime.fail("INVALID_CROWD", "群眾名冊版本／队伍")
			if crowd_rosters.has(int(roster.team_id)): return Runtime.fail("INVALID_CROWD", "重複群眾隊伍")
			crowd_rosters[int(roster.team_id)] = roster
	if not state.has("crowd"):
		return Runtime.ok() if crowd_rosters.is_empty() else Runtime.fail("INVALID_CROWD", "群眾名冊缺少原生區段")
	var section: Variant = state.crowd
	if not section is Dictionary or not _integer(section.get("version"), 1, 1): return Runtime.fail("INVALID_CROWD", "群眾存檔版本")
	for key: String in ["blob", "blob_sha256", "dll_sha256", "build_id"]:
		if not section.get(key) is String: return Runtime.fail("INVALID_CROWD", "群眾識別／內容格式")
	if section.blob.is_empty() or section.blob.length() > ceili(float(MAX_CROWD_BYTES) / 3.0) * 4:
		return Runtime.fail("INVALID_CROWD", "群眾內容為空或超過 16 MiB")
	var bytes := Marshalls.base64_to_raw(section.blob)
	if bytes.is_empty() or bytes.size() > MAX_CROWD_BYTES or Marshalls.raw_to_base64(bytes) != section.blob:
		return Runtime.fail("INVALID_CROWD", "群眾 base64 無效")
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(bytes)
	if digest.finish().hex_encode() != section.blob_sha256: return Runtime.fail("INVALID_CROWD", "群眾內容雜湊不符")
	if FileAccess.get_sha256(CROWD_DLL) != section.dll_sha256:
		return Runtime.fail("CROWD_BUILD_MISMATCH", "群眾存檔來自不同版本（DLL 不同），目前場景與原檔均保留")
	if not ClassDB.class_exists("ArmyCrowd"): return Runtime.fail("INVALID_CROWD", "群眾原生模組未載入")
	var native: Object
	if native_candidate == null:
		native = ClassDB.instantiate("ArmyCrowd")
	else:
		# A supplied result/Dictionary is never validation authority. Only the
		# compiled native class can prove its current state equals this exact blob.
		if not native_candidate is Object or not is_instance_valid(native_candidate) or native_candidate.get_class() != &"ArmyCrowd" or native_candidate.get_script() != null:
			return Runtime.fail("INVALID_CROWD", "群眾原生候選型別非法")
		native = native_candidate
	if not native.has_method("person_ids") or not native.has_method("load_state") or not native.has_method("build_id"):
		return Runtime.fail("CROWD_BUILD_MISMATCH", "群眾原生模組缺少安全載入介面")
	if str(native.call("build_id")) != section.build_id: return Runtime.fail("CROWD_BUILD_MISMATCH", "群眾 build_id 不符")
	if not native.has_method("memberships") or not native.has_method("formation_count") or not native.has_method("formation_info"):
		return Runtime.fail("CROWD_BUILD_MISMATCH", "群眾原生模組缺少名冊一致性介面")
	if native_candidate == null:
		native.call("setup", clampi(workers, 1, 8), int(data.seed_value))
		if not bool(native.call("load_state", bytes)): return Runtime.fail("INVALID_CROWD", "群眾候選原生內容非法")
	else:
		# Full native invariants and byte equality replace only recreate/load.
		# All existing record, membership, reference and build checks below remain.
		if not native.has_method("validate") or not native.has_method("save_state") or not bool(native.call("validate")) or native.call("save_state") != bytes:
			return Runtime.fail("INVALID_CROWD", "群眾候選已變更或與原存檔內容不符")
	var expected_terrain := PackedByteArray()
	expected_terrain.resize(8)
	expected_terrain.encode_s32(0, data.size.x)
	expected_terrain.encode_s32(4, data.size.y)
	for values: PackedByteArray in [data.navigation_heights(), data.navigation_flags(), data.navigation_ramps(), data.static_blocked, data.facility_cells, data.height_levels]:
		expected_terrain.append_array(values)
	if not native.has_method("terrain_state") or native.call("terrain_state") != expected_terrain:
		return Runtime.fail("INVALID_CROWD", "群眾地形與建築推導通行資料不符")
	var blob_ids: PackedInt64Array = native.call("person_ids")
	if blob_ids.is_empty() or blob_ids.size() > MAX_CROWD_ROWS: return Runtime.fail("INVALID_CROWD", "原生群眾內容非法")
	var memberships: PackedInt32Array = native.call("memberships")
	if memberships.size() != blob_ids.size() * 3: return Runtime.fail("INVALID_CROWD", "群眾原生成員表不完整")
	var native_indices := {}
	for index in range(blob_ids.size()): native_indices[blob_ids[index]] = index
	if not _integer(state.get("next_person_id"), 2, 2147483647): return Runtime.fail("INVALID_CROWD", "人物編號上限")
	var next_id := int(state.next_person_id)
	var records := {}
	var actor_ids := {}
	var checked_appearances := {}
	if not state.get("actors") is Dictionary: return Runtime.fail("INVALID_CROWD", "原人物紀錄格式")
	for actor: Variant in state.actors.values():
		if not actor is Dictionary or not _integer(actor.get("person_id"), 1, next_id - 1) or records.has(int(actor.get("person_id", 0))):
			return Runtime.fail("INVALID_CROWD", "重複或非法 actor 人物紀錄")
		records[int(actor.person_id)] = actor
		actor_ids[int(actor.person_id)] = true
	for roster: Dictionary in rosters:
		if not roster.get("units") is Array: return Runtime.fail("INVALID_CROWD", "人物名冊格式")
		for row: Variant in roster.units:
			if not row is Dictionary or not _integer(row.get("person_id"), 1, next_id - 1) or records.has(int(row.get("person_id", 0))):
				return Runtime.fail("INVALID_CROWD", "重複或非法名冊人物紀錄")
			records[int(row.person_id)] = row
			if bool(roster.get("crowd", false)):
				if not _number(row.get("hp"), 0.0, 100.0) or not _number(row.get("ko"), 0.0, 14400.0) or not row.get("captive") is bool or not row.get("item_state") is Dictionary or not row.get("cargo") is Dictionary or not row.get("appearance") is Dictionary:
					return Runtime.fail("INVALID_CROWD", "群眾人物生命／物品／外觀格式")
				if not checked_appearances.has(row.appearance):
					if not HumanCharacter3DEditor.valid_appearance(row.appearance): return Runtime.fail("INVALID_CROWD", "群眾人物外觀格式")
					checked_appearances[row.appearance] = true
				if not TerrainTestCharacter._saved_cell(row.get("cell"), data): return Runtime.fail("INVALID_CROWD", "群眾人物格位")
	if not section.get("teams") is Array or section.teams.is_empty() or section.teams.size() > 128 or not section.get("player") is Dictionary or not section.has("deploy"):
		return Runtime.fail("INVALID_CROWD", "群眾隊伍／玩家／部署格式")
	if section.teams.size() != int(native.call("formation_count")):
		return Runtime.fail("INVALID_CROWD", "群眾隊伍數與原生陣列不符")
	var references := {}
	var formations := {}
	var teams_seen := {}
	var slots := {}
	var referenced_rosters := {}
	var escort_people := {}
	for guard_key: String in state.get("escort_orders", {}):
		escort_people[int(guard_key)] = true
		for captive_id: Variant in state.escort_orders[guard_key].get("captives", []): escort_people[int(captive_id)] = true
	for team: Variant in section.teams:
		if not team is Dictionary or not _integer(team.get("formation"), 0, section.teams.size() - 1) or formations.has(int(team.get("formation", -1))) or not _integer(team.get("team_id"), 1, 999999) or teams_seen.has(int(team.get("team_id", -1))) or not team.get("solo") is bool or not team.get("person_ids") is Array or team.person_ids.is_empty() or not _integer(team.get("faction"), 0, 100000000) or not _integer(team.get("troop"), 0, 3) or not _integer(team.get("slot"), -1, 10000):
			return Runtime.fail("INVALID_CROWD", "群眾隊伍引用格式")
		var native_formation: PackedInt32Array = native.call("formation_info", int(team.formation))
		if native_formation.size() < 2 or native_formation[0] != int(team.faction) or native_formation[1] != int(team.troop):
			return Runtime.fail("INVALID_CROWD", "群眾隊伍陣營／兵種與原生陣列不符")
		var original_roster: Dictionary = crowd_rosters.get(int(team.team_id), {})
		var garrisoned := not str(original_roster.get("garrison_feature_id", "")).is_empty()
		if not native.has_method("get_garrisoned") or bool(native.call("get_garrisoned", int(team.formation))) != garrisoned:
			return Runtime.fail("INVALID_CROWD", "群眾駐營狀態與原軍營引用不符")
		formations[int(team.formation)] = true
		teams_seen[int(team.team_id)] = true
		if not bool(team.solo):
			if slots.has(int(team.slot)): return Runtime.fail("INVALID_CROWD", "群眾隊伍 slot 重複")
			slots[int(team.slot)] = true
		var roster_ids := {}
		for identity: Variant in team.person_ids:
			if not _integer(identity, 1, next_id - 1) or not records.has(int(identity)) or references.has(int(identity)):
				return Runtime.fail("INVALID_CROWD", "群眾目前引用未唯一解析")
			if not native_indices.has(int(identity)): return Runtime.fail("INVALID_CROWD", "群眾人物缺少原生索引")
			var native_index := int(native_indices[int(identity)])
			if memberships[native_index * 3] != int(team.formation) or memberships[native_index * 3 + 1] != int(team.faction):
				return Runtime.fail("INVALID_CROWD", "群眾人物所屬隊伍／陣營與原生陣列不符")
			var hot: PackedFloat64Array = native.call("get_soldier_state", native_index)
			var record: Dictionary = records[int(identity)]
			var role: Variant = record.get("military_role")
			if role == null:
				if actor_ids.has(int(identity)):
					role = _legacy_actor_military_role(record, state)
				else:
					for row_index in range(original_roster.get("units", []).size()):
						if int(original_roster.units[row_index].person_id) == int(identity):
							role = _legacy_row_military_role(original_roster, row_index)
							break
			if not role is String or role not in ["officer", "soldier", "civilian"] or not native.has_method("get_military_role") \
				or int(native.call("get_military_role", native_index)) != int({"soldier": 0, "officer": 1, "civilian": 2}[role]):
				return Runtime.fail("INVALID_CROWD", "群眾軍官／士兵／平民資格與原人物不符")
			var captivity: Dictionary = state.get("captivity", {}).get(str(int(identity)), {})
			var soldier_refs: PackedInt64Array = native.call("soldier_refs", native_index)
			var escort: PackedInt64Array = native.call("escort_state", native_index)
			if soldier_refs.size() != 3 or int(soldier_refs[2]) != int(captivity.get("prison_id", "0")):
				return Runtime.fail("INVALID_CROWD", "群眾監禁鏡像與原拘押關係不符")
			if escort.size() != 2 or int(escort[0]) == 1 and not escort_people.has(int(identity)): return Runtime.fail("INVALID_CROWD", "群眾押送保持狀態缺少原押送命令")
			if not str(captivity.get("prison_id", "")).is_empty():
				if escort.size() != 2 or int(escort[0]) != 0 or int(escort[1]) != -1 or hot.size() <= 12 or not is_zero_approx(hot[12]): return Runtime.fail("INVALID_CROWD", "在監人物仍有押送步進或野外逃脫計時")
			if hot.size() < 16 or not _crowd_float_equal(record.get("hp", -1.0), hot[0]) or not _crowd_float_equal(record.get("knockout_left" if actor_ids.has(int(identity)) else "ko", -1.0), hot[3]) or bool(record.get("captive", false)) != bool(hot[6]):
				return Runtime.fail("INVALID_CROWD", "群眾人物生命與原生陣列不符")
			if not TerrainTestCharacter._saved_cell(record.get("cell"), data) or Vector2i(int(record.cell[0]), int(record.cell[1])) != Vector2i(floori(hot[14]), floori(hot[15])):
				return Runtime.fail("INVALID_CROWD", "群眾人物格位與原生陣列不符")
			if garrisoned and not bool(record.get("captive", false)) and int(escort[0]) == 2 and not escort_people.has(int(identity)):
				# A return uses the original one-step native commit. Mode 2 also
				# finishes an already cancelled escort after release; never infer
				# a new direction or demand a fabricated escort order for that step.
				var from := Vector2i(int(record.cell[0]), int(record.cell[1]))
				var destination := data.cell_from_index(int(escort[1]))
				if not _valid_walkable_pair(data, record.get("slot")) or not data.is_walkable(from) or not data.is_walkable(destination) \
					or from != destination and not data.can_step(from, destination):
					return Runtime.fail("INVALID_CROWD", "原駐營人物返營／收束步進非法")
			if actor_ids.has(int(identity)):
				if record.has("crowd_handoff"):
					if not _valid_crowd_actor_handoff(record.crowd_handoff, int(identity)) or hot.size() < 22: return Runtime.fail("INVALID_CROWD", "群眾 actor 交接快照非法")
					var handoff: Dictionary = record.crowd_handoff
					if bool(handoff.bandaged) != bool(hot[7]) or int(handoff.role) != int(hot[13]): return Runtime.fail("INVALID_CROWD", "群眾 actor 包紮／職位與原生陣列不符")
					for field: String in {"escape_t": 12, "face": 16, "knock_t": 20, "act_t": 21, "stagger": 5, "exch_cd": 17, "ranged_cd": 18, "skill_cd": 19}:
						var at: int = {"escape_t": 12, "face": 16, "knock_t": 20, "act_t": 21, "stagger": 5, "exch_cd": 17, "ranged_cd": 18, "skill_cd": 19}[field]
						if not _crowd_float_equal(handoff[field], hot[at]): return Runtime.fail("INVALID_CROWD", "群眾 actor 交接計時與原生陣列不符：" + field)
				var native_position := Vector2(hot[14], hot[15]) * TerrainRenderer.CELL_PIXELS
				if not TerrainTestCharacter._saved_vector(record.get("position")) or not _crowd_float_equal(record.position[0], native_position.x) or not _crowd_float_equal(record.position[1], native_position.y):
					return Runtime.fail("INVALID_CROWD", "群眾 actor 座標與原生陣列不符")
			references[int(identity)] = true
			if not actor_ids.has(int(identity)): roster_ids[int(identity)] = true
		if bool(team.solo):
			if team.person_ids.size() != 1 or not roster_ids.is_empty(): return Runtime.fail("INVALID_CROWD", "solo 只能引用一位原 actor")
		else:
			if not crowd_rosters.has(int(team.team_id)): return Runtime.fail("INVALID_CROWD", "群眾隊伍缺少名冊")
			var roster: Dictionary = crowd_rosters[int(team.team_id)]
			if int(roster.faction_id) != int(team.faction) or roster.units.size() != roster_ids.size(): return Runtime.fail("INVALID_CROWD", "群眾名冊／隊伍引用不符")
			for row: Dictionary in roster.units:
				if not roster_ids.has(int(row.person_id)): return Runtime.fail("INVALID_CROWD", "群眾名冊不屬於引用隊伍")
			referenced_rosters[int(team.team_id)] = true
		var handoff_formation: Variant = records[int(team.person_ids[0])].get("crowd_handoff", {}).get("solo_formation") if bool(team.solo) else crowd_rosters[int(team.team_id)].get("crowd_state")
		if handoff_formation != null:
			var native_refs: PackedInt64Array = native.call("formation_refs", int(team.formation))
			if not handoff_formation is Dictionary or native_refs.size() < 4:
				return Runtime.fail("INVALID_CROWD", "群眾隊伍交接引用格式")
			var reference_fields := ["formal_person", "acting_person", "current_person", "target_person"]
			for index in range(4):
				if not _integer(handoff_formation.get(reference_fields[index]), -1, 2147483647) or int(handoff_formation[reference_fields[index]]) != native_refs[index]:
					return Runtime.fail("INVALID_CROWD", "群眾隊伍交接引用與原生陣列不符：" + reference_fields[index])
			if not handoff_formation.get("officer_persons") is Array or handoff_formation.officer_persons.size() != native_refs.size() - 4:
				return Runtime.fail("INVALID_CROWD", "群眾隊伍交接軍官數與原生陣列不符")
			for index in range(handoff_formation.officer_persons.size()):
				if not _integer(handoff_formation.officer_persons[index], 1, 2147483647) or int(handoff_formation.officer_persons[index]) != native_refs[index + 4]:
					return Runtime.fail("INVALID_CROWD", "群眾隊伍交接軍官與原生陣列不符")
	if referenced_rosters.size() != crowd_rosters.size(): return Runtime.fail("INVALID_CROWD", "未引用的群眾名冊")
	if references.size() != blob_ids.size(): return Runtime.fail("INVALID_CROWD", "群眾 blob 與隊伍人数不符")
	var native_seen := {}
	for identity: int in blob_ids:
		if not references.has(identity) or native_seen.has(identity): return Runtime.fail("INVALID_CROWD", "群眾 blob 人物集合不符")
		native_seen[identity] = true
	if not _integer(section.player.get("person_id"), 1, next_id - 1) or not _integer(section.player.get("soldier_index"), 0, blob_ids.size() - 1) or int(section.player.person_id) != int(state.get("controlled_person_id", state.actors.get("player", {}).get("person_id", -1))) or blob_ids[int(section.player.soldier_index)] != int(section.player.person_id):
		return Runtime.fail("INVALID_CROWD", "群眾受控人物引用不符")
	return Runtime.ok("", {"native": native})

static func _validate_state(data: TerrainData, state: Dictionary, crowd_workers: int = 1, native_candidate: Variant = null, region_context: Dictionary = {}) -> Dictionary:
	var boarding: Dictionary = Boarding.save_guard(state, data)
	if not boarding.ok: return boarding
	var hot := not region_context.is_empty()
	var region_capture := {"context": region_context}
	var pending_action_cursor := _region_pending_fire_cursor(state, region_context)
	if hot:
		var checked := RegionCheckpoint.validate_context(region_context)
		if not checked.ok: return checked
	var identity_validation := _validate_travel_identity(state)
	if not identity_validation.ok: return identity_validation
	var completion_guard := _region_capture_completion_guard(state, region_context)
	if not completion_guard.ok: return completion_guard
	var layout_validation := _validate_site_values(data, state)
	if not layout_validation.ok: return layout_validation
	var surface_inputs := _validate_siege_surface_inputs(data, state, hot)
	if not surface_inputs.ok: return surface_inputs
	data = Env.navigation_for_state(data, state)
	var fire_guard := Runtime.fire_save_guard(data)
	if not fire_guard.ok: return fire_guard
	var tower_layouts := _validate_siege_tower_layouts(data, state)
	if not tower_layouts.ok: return tower_layouts
	for feature: Dictionary in state.features.values():
		var feature_validation := Runtime.validate_feature_layout(data, feature)
		if not feature_validation.ok: return feature_validation
	var crowd_validation := _validate_crowd(data, state, crowd_workers, native_candidate)
	if not crowd_validation.ok: return crowd_validation
	var army_validation := _validate_armies(data, state)
	if not army_validation.ok:
		return army_validation
	var vehicle_validation := _validate_vehicles(data, state, false, region_context)
	if not vehicle_validation.ok:
		return vehicle_validation
	var actor_validation := _validate_actors(data, state)
	if not actor_validation.ok:
		return actor_validation
	var military_validation := _validate_military(data, state)
	if not military_validation.ok:
		return military_validation
	var corps_validation := _validate_corps(state)
	if not corps_validation.ok:
		return corps_validation
	var item_validation := _validate_items(data, state, region_capture.get("context", {}))
	if not item_validation.ok:
		return item_validation
	var cape_validation := _validate_cape_roles(state)
	if not cape_validation.ok: return cape_validation
	var trade_validation: Dictionary = Trade.validate_snapshot(state, float(region_context.get("action_seconds", -1.0)), data)
	if not trade_validation.ok: return trade_validation
	var allocator_validation := _validate_person_allocator(state)
	if not allocator_validation.ok:
		return allocator_validation
	var supply_validation := _validate_supply(state, data, region_capture.get("context", {}))
	if not supply_validation.ok:
		return supply_validation
	var raw_fire: Variant = state.get("fire", {})
	if not raw_fire is Dictionary: return Runtime.fail("CORRUPT_FIRE_SNAPSHOT")
	if not raw_fire.is_empty():
		var cursor: Variant = raw_fire.get("observed_action_end", -1.0)
		var settlement: Variant = state.get("fire_settlement", {})
		if settlement is Dictionary and settlement.has("action_seconds"): cursor = settlement.action_seconds
		if not Runtime._fire_time_valid(cursor): return Runtime.fail("INVALID_FIRE_BARRIER")
		var fire_snapshot := Runtime.validate_fire_snapshot(data, raw_fire, float(cursor))
		if not fire_snapshot.ok: return fire_snapshot
		state["fire"] = fire_snapshot.state
	var transport_snapshot := _validate_fire_transport_snapshot(data, state.get("fire", {}), state.get("fire_transport", {}), pending_action_cursor)
	if not transport_snapshot.ok: return transport_snapshot
	if not transport_snapshot.state.is_empty():
		var fire_owners := _validate_fire_transport_owners(data, state, transport_snapshot.state)
		if not fire_owners.ok: return fire_owners
	if transport_snapshot.state.is_empty(): state.erase("fire_transport")
	else:
		# Region metadata authenticates the original persisted body. Keep the
		# original validated wire; the original Lab restore prepares runtime
		# maps separately. An ordinary load keeps its existing normalized maps.
		state["fire_transport"] = transport_snapshot.wire if state.has("region_snapshot") else transport_snapshot.state
	var fire_owner_snapshot: Variant = state.get("fire_owners", {})
	if fire_owner_snapshot is Dictionary and not fire_owner_snapshot.is_empty():
		var cursor := float(fire_owner_snapshot.get("action_cursor", -1.0))
		var settlement: Variant = state.get("fire_settlement", {})
		if settlement is Dictionary and settlement.has("action_seconds") and absf(float(settlement.action_seconds) - cursor) > Runtime.FIRE_EPS and not _region_cursor_matches_pending(cursor, pending_action_cursor, float(settlement.action_seconds)):
			return Runtime.fail("FIRE_CLOCK_MISMATCH")
		var checked_owners := _validate_fire_owner_snapshot(data, state, fire_owner_snapshot, cursor)
		if not checked_owners.ok: return checked_owners
		var owner_fire: Dictionary = state.get("fire", {})
		var expected_owner_cursor: Variant = owner_fire.get("observed_action_end", -1.0)
		if expected_owner_cursor != -1.0 and absf(float(expected_owner_cursor) - cursor) > Runtime.FIRE_EPS and not _region_cursor_matches_pending(cursor, pending_action_cursor, float(expected_owner_cursor)) \
			or not transport_snapshot.state.is_empty() and absf(float(transport_snapshot.state.action_cursor) - cursor) > Runtime.FIRE_EPS:
			return Runtime.fail("FIRE_CLOCK_MISMATCH")
		state["fire_owners"] = checked_owners.state
	if crowd_validation.has("native"):
		# All callers supplying a native here pass the original detached load
		# result, never the scene's live World. Prove its existing flags before
		# reload; otherwise rebuilding could conceal a bad supplied candidate.
		if native_candidate != null:
			var supplied_crew := _validate_crowd_siege_crew(state, crowd_validation.native)
			if not supplied_crew.ok: return supplied_crew
		var navigation_restore := _restore_crowd_navigation(data, crowd_validation.native)
		if not navigation_restore.ok: return navigation_restore
		# Original navigation reload resets derived crew. Rebuild only afterwards.
		var restored_crew := _validate_crowd_siege_crew(state, crowd_validation.native, true)
		if not restored_crew.ok: return restored_crew
		return Runtime.ok("", {"crowd_native": crowd_validation.native})
	return Runtime.ok()

static func _validate_crowd_siege_crew(state: Dictionary, native: Object, restore_derived: bool = false) -> Dictionary:
	# This follows every original Site/vehicle/person validator. JSON crew_slots
	# is the only persistent assignment authority; native flags are derived.
	for method: String in ["person_ids", "siege_person_state", "siege_busy", "set_siege_crew_members", "validate", "save_state"]:
		if not native.has_method(method): return Runtime.fail("CROWD_BUILD_MISMATCH", "群眾原生模組缺少原攻城操作班保存介面")
	if bool(native.call("siege_busy")): return Runtime.fail("INVALID_CROWD", "原攻城人物承諾步／複合提交尚未收束")
	var ids: PackedInt64Array = native.call("person_ids")
	var indices := {}
	for index in range(ids.size()): indices[int(ids[index])] = index
	var expected := {}
	var crew_indices := PackedInt32Array()
	for vehicle: Dictionary in state.get("vehicles", {}).values():
		if not Runtime.SIEGE_DEFINITIONS.has(str(vehicle.get("kind", ""))): continue
		for identity: int in vehicle.get("crew_slots", {}).values():
			if expected.has(identity) or not indices.has(identity): return Runtime.fail("INVALID_CROWD", "原攻城操作班不屬原生人物集合或重複引用")
			expected[identity] = true
			crew_indices.append(int(indices[identity]))
	if restore_derived:
		# Only a detached World reaches this branch. The setter may rebuild flags,
		# but must preserve every serialized hot value, clock, order and reference.
		var original_bytes: PackedByteArray = native.call("save_state")
		if original_bytes.is_empty() or not bool(native.call("set_siege_crew_members", crew_indices)):
			return Runtime.fail("INVALID_CROWD", "原攻城操作班無法由已驗證 Site 引用還原")
		if not bool(native.call("validate")) or native.call("save_state") != original_bytes:
			return Runtime.fail("INVALID_CROWD", "原攻城操作班還原改變原生保存內容或不變量")
	var steady_crew := PackedInt64Array([1, 0, -1, 0, -1, -1, 0, 0])
	for index in range(ids.size()):
		var marks: PackedInt64Array = native.call("siege_person_state", index)
		var assigned: bool = expected.has(int(ids[index]))
		if marks.size() != 8 or int(marks[0]) != int(assigned):
			return Runtime.fail("INVALID_CROWD", "原生操作班旗標與原 Site 操作人集合不符")
		# Do not impose mode 0 on unrelated custody/housing/work participants.
		# Their original World serialization/load and Site owners retain the gate.
		if assigned and marks != steady_crew:
			return Runtime.fail("INVALID_CROWD", "原生攻城操作人仍在途／複合提交或兼任其他原作業")
	return Runtime.ok()

static func _restore_crowd_navigation(data: TerrainData, native: Object) -> Dictionary:
	# Called only after every original Site validator succeeds on this detached
	# candidate. A live scene is never passed here as a navigation authority.
	for method: String in ["person_ground_cells", "load_state_with_siege_navigation", "save_state"]:
		if not native.has_method(method): return Runtime.fail("CROWD_BUILD_MISMATCH", "群眾原生模組缺少原 Site 導航恢復介面")
	var ground_cells: PackedInt64Array = native.call("person_ground_cells")
	var mask_script: Script = load("res://scripts/terrain_lab/crowd_site.gd")
	if mask_script == null: return Runtime.fail("MISSING_ASSET", "原群眾 Site 導航推導不可用")
	var navigation: Dictionary = mask_script.call("build_siege_navigation", data, ground_cells)
	if not navigation.ok: return navigation
	var bytes: PackedByteArray = native.call("save_state")
	if bytes.is_empty() or not bool(native.call("load_state_with_siege_navigation", bytes, navigation.blocked, navigation.wreck_exit)):
		return Runtime.fail("INVALID_CROWD", "原群眾 Site 導航無法原子恢復，原場景與存檔保留")
	return Runtime.ok()


static func _validate_site_values(data: TerrainData, state: Dictionary) -> Dictionary:
	var definitions: Dictionary = Env.validate_resource_definitions(data, data.resource_base)
	if not definitions.ok: return Runtime.fail("CORRUPT_SAVE", str(definitions.get("message", "Invalid resource definitions")))
	var deltas: Dictionary = Env.validate_resource_deltas(data, state)
	if not deltas.ok: return Runtime.fail("CORRUPT_SAVE", str(deltas.get("message", "Invalid resource deltas")))
	if state.has("initial_scenario"):
		var born: Variant = state.initial_scenario
		var born_pin: Variant = state.get("world_pin", {})
		if not born is Dictionary or born.size() != 3 or not _integer(born.get("version"), 1, 1) or born.get("scenario_id") not in ["existing_primary_army_artisans_v1", "existing_three_armies_artisans_v1"] or not born.get("world_id") is String or str(born.world_id).is_empty() or not born_pin is Dictionary or str(born.world_id) != str(born_pin.get("world_instance_id", "")):
			return Runtime.fail("CORRUPT_SAVE", "首次場景出生識別非法")
	var world_pin := _validate_world_pin(data, state)
	if not world_pin.ok: return world_pin
	var marine_validation := _validate_marine_state(data, state)
	if not marine_validation.ok: return marine_validation
	var trade_tax_validation: Dictionary = validate_trade_tax_receipts(state)
	if not trade_tax_validation.ok: return trade_tax_validation
	var trade_leg_validation: Dictionary = validate_trade_leg_receipts(state)
	if not trade_leg_validation.ok: return trade_leg_validation
	if state.has("actor_presence_version") and not _integer(state.actor_presence_version, 1, 1): return Runtime.fail("CORRUPT_SAVE", "原獨立人物存在格式版本")
	if state.has("simulation_settlement"):
		var settlement: Variant = state.simulation_settlement
		if not settlement is Dictionary or settlement.size() != 2 or not _integer(settlement.get("version"), 1, 1) or not _number(settlement.get("last_settled_game_seconds"), 0.0, 1000000000000.0): return Runtime.fail("CORRUPT_SAVE", "Site 共用時計結算版本／水印非法")
	for key: String in ["changes", "features", "terrain_changes", "inventory", "worker", "manual"]:
		if not state.get(key) is Dictionary:
			return Runtime.fail("CORRUPT_SAVE", key)
	var ecology_validation := _validate_ecology_state(data, state)
	if not ecology_validation.ok: return ecology_validation
	if not state.get("id") is String or str(state.id).is_empty() or not state.get("zones") is Array or not state.get("paused") is bool:
		return Runtime.fail("CORRUPT_SAVE", "地圖身分／工作區")
	if state.has("worker_enabled") and not state.worker_enabled is bool:
		return Runtime.fail("CORRUPT_SAVE", "工人啟用狀態")
	if not _integer(state.get("minute"), 0, 1000000000) or not _number(state.get("phase"), 0, 0.999999999) or not _integer(state.get("next_feature"), 1, 1000000):
		return Runtime.fail("CORRUPT_SAVE", "時間／編號")
	if not _integer(state.get("capacity"), 1, 1000000) or not _valid_site_anchor(data, state, state.get("depot_cell")):
		return Runtime.fail("CORRUPT_SAVE", "營地")
	for key: String in state.inventory:
		if not Env.ITEM_NAMES.has(key) or not _integer(state.inventory[key], 0, 1000000):
			return Runtime.fail("CORRUPT_SAVE", "存貨")
	var occupied := {}
	for key: String in state.features:
		var feature: Variant = state.features[key]
		if not key.is_valid_int() or int(key) < 1 or int(key) >= int(state.next_feature) or not feature is Dictionary:
			return Runtime.fail("CORRUPT_SAVE", "建物身分")
		var modern: bool = feature.has("layout_version")
		var large_plot: bool = modern and str(feature.get("kind", "")) in Runtime.FARM_KINDS + Runtime.PASTURE_KINDS + Runtime.MILITARY_KINDS
		if not Runtime.FEATURES.has(str(feature.get("kind", ""))) or not _valid_cells(data, feature.get("cells"), 2500 if large_plot else 36):
			return Runtime.fail("CORRUPT_SAVE", "建物占地")
		if not _valid_cell(data, feature.get("entrance")) or str(feature.get("stage", "")) not in ["planned", "building", "complete"]:
			return Runtime.fail("CORRUPT_SAVE", "建物入口／階段")
		for field: String in ["progress", "production", "work"]:
			if not _number(feature.get(field), 0, 1000000):
				return Runtime.fail("CORRUPT_SAVE", "工作進度")
		if float(feature.work) <= 0.0 or not feature.get("batch_paid") is bool or not feature.get("solid") is bool or not feature.get("cost") is Dictionary or not feature.get("clearing") is Array:
			return Runtime.fail("CORRUPT_SAVE", "建物工作資料")
		if bool(feature.solid) != bool(Runtime.FEATURES[str(feature.kind)].solid) or float(feature.progress) > float(feature.work):
			return Runtime.fail("CORRUPT_SAVE", "建物規格")
		if str(feature.kind) in ["pasture", "horse_ranch"]:
			var species := "horse" if str(feature.kind) == "horse_ranch" else "sheep"
			if str(feature.get("species", "")) != species or not _integer(feature.get("residents"), 0 if modern else 1, 10000 if modern else 36):
				return Runtime.fail("CORRUPT_SAVE", "畜種與種畜")
		elif feature.has("species") or feature.has("residents"):
			return Runtime.fail("CORRUPT_SAVE", "非牧場含有牲畜")
		if not feature.get("source") is String or not feature.get("status") is String or not _integer(feature.get("level"), 0, 5):
			return Runtime.fail("CORRUPT_SAVE", "建物來源")
		for i: Variant in feature.cells:
			if occupied.has(int(i)):
				return Runtime.fail("CORRUPT_SAVE", "占地重疊")
			occupied[int(i)] = true
		var feature_validation := Runtime.validate_feature_layout(data, feature, false)
		if not feature_validation.ok: return feature_validation
		for i: Variant in feature.get("pending_build", {}).get("added_cells", []):
			if occupied.has(int(i)): return Runtime.fail("CORRUPT_SAVE", "擴建占地重疊")
			occupied[int(i)] = true
		for resource_key: Variant in feature.clearing:
			if not resource_key is String or not data.resource_base.has(resource_key):
				return Runtime.fail("CORRUPT_SAVE", "清理來源")
		for item: Variant in feature.cost:
			if not item is String or not Env.ITEM_NAMES.has(item) or not _integer(feature.cost[item], 0, 1000000):
				return Runtime.fail("CORRUPT_SAVE", "施工投入")
	for key: String in state.changes:
		if not data.resource_base.has(key) or not state.changes[key] is Dictionary:
			return Runtime.fail("CORRUPT_SAVE", "資源 ID")
		var fields: Dictionary = state.changes[key]
		for field: String in fields:
			if field not in ["remaining", "next_recovery", "cleared", "discovered", "used", "used_minute", "eco_mode", "eco_resting"]:
				return Runtime.fail("CORRUPT_SAVE", "不支援的資源差異")
		if fields.has("remaining") and not _integer(fields.remaining, 0, int(data.resource_base[key].capacity)):
			return Runtime.fail("CORRUPT_SAVE", "資源儲量")
		for flag: String in ["cleared", "discovered"]:
			if fields.has(flag) and not fields[flag] is bool:
				return Runtime.fail("CORRUPT_SAVE", "資源狀態")
		if fields.has("next_recovery") and not _integer(fields.next_recovery, -1, 1100000000):
			return Runtime.fail("CORRUPT_SAVE", "恢復期限")
		if fields.has("used") and not _number(fields.used, 0, 1000000):
			return Runtime.fail("CORRUPT_SAVE", "來源使用量")
		if fields.has("used_minute") and not _integer(fields.used_minute, 0, 1000000000):
			return Runtime.fail("CORRUPT_SAVE", "來源時間")
	var ecology_latches := _validate_ecology_latches(data, state)
	if not ecology_latches.ok: return ecology_latches
	for key: String in state.terrain_changes:
		if not key.is_valid_int() or not _valid_cell(data, int(key)) or not _integer(state.terrain_changes[key], 0, 5):
			return Runtime.fail("CORRUPT_SAVE", "整地差異")
	for zone: Variant in state.zones:
		if not zone is Dictionary: return Runtime.fail("CORRUPT_SAVE", "工作區資料")
		var feature_zone := str(zone.get("action", "")) in ["construct", "operate", "repair"]
		if not _valid_cells(data, zone.get("cells"), 2500 if feature_zone else 1600) or not zone.get("active") is bool:
			return Runtime.fail("CORRUPT_SAVE", "工作區資料")
		if str(zone.get("action", "")) not in ["harvest", "clear", "survey", "capture", "restore", "construct", "operate", "repair"] or not _integer(zone.get("kind"), -1, 8):
			return Runtime.fail("CORRUPT_SAVE", "工作區命令")
		if str(zone.action) == "restore" and int(zone.kind) not in [-1, Env.Kind.TIMBER, Env.Kind.FOOD, Env.Kind.HERB]:
			return Runtime.fail("CORRUPT_SAVE", "復育工作區來源")
		if str(zone.action) == "capture" and int(zone.kind) not in [-1, Env.Kind.WILDLIFE]:
			return Runtime.fail("CORRUPT_SAVE", "活捉工作區畜種")
		if feature_zone and not zone.get("feature") is String:
			return Runtime.fail("CORRUPT_SAVE", "工作區建物")
		if zone.has("technology_owned") and (zone.technology_owned != true or str(zone.action) != "operate"):
			return Runtime.fail("CORRUPT_SAVE", "工作區科技所有標記")
	for actor_key: String in ["worker", "manual"]:
		var actor: Dictionary = state[actor_key]
		if actor.has("work_slot") and (actor_key != "worker" or not _integer(actor.work_slot, -1, 80)):
			return Runtime.fail("CORRUPT_SAVE", "工作分區")
		if not actor.get("target") is String or not _number(actor.get("progress"), 0, 1000000) or not actor.get("cargo") is Dictionary:
			return Runtime.fail("CORRUPT_SAVE", "作業狀態")
		var target := str(actor.target)
		if target.is_empty() and str(actor.get("action", "")) == "restore" and float(actor.progress) != 0.0:
			return Runtime.fail("CORRUPT_SAVE", "無目標復育進度")
		if not target.is_empty():
			if not data.resource_base.has(target) and target != "depot" and not (target.begins_with("feature:") and state.features.has(target.trim_prefix("feature:"))):
				return Runtime.fail("CORRUPT_SAVE", "作業目標")
			if str(actor.get("action", "")) not in ["harvest", "clear", "survey", "capture", "restore", "construct", "operate", "repair", "deposit"]:
				return Runtime.fail("CORRUPT_SAVE", "作業行為")
			if str(actor.action) == "restore":
				var source: Dictionary = data.resource_base.get(target, {})
				if source.is_empty() or int(source.kind) not in [Env.Kind.TIMBER, Env.Kind.FOOD, Env.Kind.HERB] or not bool(state.changes.get(target, {}).get("cleared", false)) or not _integer(state.changes.get(target, {}).get("remaining", source.capacity), 0, 0) or not _number(actor.progress, 0.0, Runtime.resource_work_minutes(int(source.kind), "restore")):
					return Runtime.fail("CORRUPT_SAVE", "復育作業來源／進度")
			if str(actor.action) == "capture" and Runtime.capturable_species(data.resource_base.get(target, {})).is_empty():
				return Runtime.fail("CORRUPT_SAVE", "活捉作業畜種")
			if actor_key == "worker" and not _valid_cell(data, actor.get("work_cell")):
				return Runtime.fail("CORRUPT_SAVE", "工作目的地")
			if actor_key == "manual" and (not data.resource_base.has(target) or not _valid_cell(data, actor.get("cell")) or str(actor.action) not in ["harvest", "survey", "clear", "capture", "restore"]):
				return Runtime.fail("CORRUPT_SAVE", "手動作業")
		for item: String in actor.cargo:
			if not Env.ITEM_NAMES.has(item) or not _integer(actor.cargo[item], 0, Runtime.CARRY_CAPACITY):
				return Runtime.fail("CORRUPT_SAVE", "攜帶物")
		if Runtime.inventory_size(actor.cargo) > Runtime.CARRY_CAPACITY:
			return Runtime.fail("CORRUPT_SAVE", "攜帶超量")
		for cell_key: String in ["cell", "work_cell"]:
			if actor.has(cell_key) and not _valid_site_anchor(data, state, actor[cell_key]):
				return Runtime.fail("CORRUPT_SAVE", "作業格位")
	if not _valid_site_anchor(data, state, state.worker.get("cell")) or str(state.worker.get("mode", "")) not in ["idle", "travel", "work"] or not state.worker.get("status") is String or not _integer(state.worker.get("zone"), -1, state.zones.size() - 1):
		return Runtime.fail("CORRUPT_SAVE", "工人")
	if not state.manual.get("action") is String or not _number(state.get("total_produced"), 0, 1000000000):
		return Runtime.fail("CORRUPT_SAVE", "產量")
	if not state.worker.get("manual_control", false) is bool:
		return Runtime.fail("CORRUPT_SAVE", "原工人手動作業欄位")
	if state.has("player_cell") and not _valid_site_anchor(data, state, state.player_cell):
		return Runtime.fail("CORRUPT_SAVE", "玩家格位")
	return Runtime.ok()

static func _validate_ecology_state(data: TerrainData, state: Dictionary) -> Dictionary:
	# Raw schema checks only. A valid legacy source is not admitted to E1 until
	# the original load/bind owner prepares a detached migration candidate.
	var modern := state.has("ecology_version")
	if modern and not _integer(state.ecology_version, Env.ECOLOGY_VERSION, Env.ECOLOGY_VERSION):
		return Runtime.fail("CORRUPT_SAVE", "生態版本")
	for key: Variant in state.changes:
		if not key is String or not data.resource_base.has(key) or not state.changes[key] is Dictionary:
			return Runtime.fail("CORRUPT_SAVE", "生態資源 ID")
		var fields: Dictionary = state.changes[key]
		for field: Variant in fields:
			if not field is String: return Runtime.fail("CORRUPT_SAVE", "生態差異欄位")
		var kind := int(data.resource_base[key].kind)
		var biological := kind in [Env.Kind.TIMBER, Env.Kind.FOOD, Env.Kind.HERB, Env.Kind.FISH, Env.Kind.WILDLIFE]
		if fields.has("eco_mode") and (not modern or not biological or not fields.eco_mode is String or fields.eco_mode not in Env.ECOLOGY_MODES):
			return Runtime.fail("CORRUPT_SAVE", "生態管理模式")
		if fields.has("eco_resting") and (not modern or kind not in [Env.Kind.FISH, Env.Kind.WILDLIFE] or not fields.eco_resting is bool):
			return Runtime.fail("CORRUPT_SAVE", "生態休養狀態")
		# False is meaningful history inside the L/R band. Modern resource
		# differences must carry it explicitly instead of guessing on load.
		if modern and kind in [Env.Kind.FISH, Env.Kind.WILDLIFE] and not fields.has("eco_resting"):
			for field: String in ["remaining", "eco_mode", "next_recovery", "cleared"]:
				if fields.has(field): return Runtime.fail("CORRUPT_SAVE", "缺少明確生態休養狀態")
	if not modern:
		for key: String in ["worker", "manual"]:
			if str(state[key].get("action", "")) == "restore": return Runtime.fail("CORRUPT_SAVE", "舊來源含復育作業")
		if state.get("zones") is Array:
			for zone: Variant in state.zones:
				if zone is Dictionary and str(zone.get("action", "")) == "restore": return Runtime.fail("CORRUPT_SAVE", "舊來源含復育工作區")
	return Runtime.ok()

static func _validate_ecology_latches(data: TerrainData, state: Dictionary) -> Dictionary:
	if not state.has("ecology_version"): return Runtime.ok()
	# Feature/resource structure is already checked. Derive habitat from this
	# exact candidate, never the live data.site or a second threshold formula.
	var view := Env.navigation_for_state(data, state)
	for key: String in state.changes:
		var fields: Dictionary = state.changes[key]
		if not fields.has("eco_resting"): continue
		var resource := Env.resource(view, key)
		var ecology := Env.ecology_info(view, key)
		if Env.ecology_resting(int(resource.remaining), int(ecology.capacity), fields.eco_resting) != bool(fields.eco_resting):
			return Runtime.fail("CORRUPT_SAVE", "生態休養狀態與原棲地存量不符")
	return Runtime.ok()

static func prepare_ecology_candidate(data: TerrainData, region_context: Dictionary = {}) -> Dictionary:
	# All validation and migration use private values. Check the original
	# checkpoint before removing it; publication must recapture actual owners.
	if data == null or data.site.is_empty(): return Runtime.fail("NO_SITE")
	var context := region_context.duplicate(true)
	if data.site.has("region_snapshot"):
		var checkpoint := RegionCheckpoint.validate(data.site, data.site.region_snapshot, context)
		if not checkpoint.ok: return checkpoint
		context = checkpoint.context
	var source_validation := _validate_state(data, data.site.duplicate(true), 1, null, context)
	if not source_validation.ok: return source_validation
	var candidate := Env.navigation_for_state(data, data.site.duplicate(true))
	for field: String in ["height_levels", "surface_types", "flags", "cliff_drops", "ramp_edges", "detail_variation", "fertility", "moisture", "drainage", "foundation", "groundwater", "water_kind", "water_body"]:
		candidate.set(field, data.get(field).duplicate())
	candidate["parameters"] = data.parameters.duplicate(true)
	candidate["resource_base"] = data.resource_base.duplicate(true)
	if not candidate.site.has("ecology_version"):
		candidate.site["ecology_version"] = Env.ECOLOGY_VERSION
	else:
		candidate.site["ecology_version"] = int(candidate.site.ecology_version)
	var reconciled := Runtime.ecology_reconcile(candidate)
	if not reconciled.ok: return reconciled
	var changed := candidate.site != data.site
	var needs_recapture := changed and candidate.site.has("region_snapshot")
	if needs_recapture: candidate.site.erase("region_snapshot")
	var validation := _validate_state(candidate, candidate.site.duplicate(true), 1, null, context)
	if not validation.ok: return validation
	Runtime.rebuild_loot_index(candidate)
	return Runtime.ok("", {"data": candidate, "state": candidate.site, "changed": changed, "needs_region_recapture": needs_recapture})

static func _valid_site_anchor(data: TerrainData, state: Dictionary, value: Variant) -> bool:
	return _integer(value, -1, -1) if state.has("marine") else _valid_cell(data, value)

static func _validate_marine_state(data: TerrainData, state: Dictionary) -> Dictionary:
	if not state.has("marine"): return Runtime.ok()
	var marine: Variant = state.marine
	if not marine is Dictionary or marine.size() != 1 or not _integer(marine.get("version"), 1, 1) or data.parameters.get("composition") != "fixed_geography" or not data.parameters.get("fixed_base") is Dictionary or data.spawn_cell != Vector2i(-1, -1): return Runtime.fail("CORRUPT_SAVE", "海域 Site 格式／固定来源不合法")
	if not _integer(state.get("actor_presence_version"), 1, 1) or state.get("actors") != {} or state.get("worker_enabled") != false or not _integer(state.get("depot_cell"), -1, -1) or not _integer(state.get("player_cell"), -1, -1) or not state.get("worker") is Dictionary or not _integer(state.worker.get("cell"), -1, -1): return Runtime.fail("CORRUPT_SAVE", "海域不能包含假陸地人物／營地")
	if state.get("inventory") != {} or state.get("features") != {} or state.get("zones") != [] or not str(state.worker.get("target", "!")).is_empty() or not state.get("manual") is Dictionary or not str(state.manual.get("target", "!")).is_empty(): return Runtime.fail("CORRUPT_SAVE", "海域含未支持陸地生產作業")
	return Runtime.ok()

static func _crowd_handoff_json_value(value: Variant) -> Variant:
	# JSON reads every number as float. Normalize both live and read-back values
	# before hashing, without rounding or changing the underlying owner state.
	if value is int or value is float: return float(value)
	if value is Array:
		var values: Array = []
		for entry: Variant in value: values.append(_crowd_handoff_json_value(entry))
		return values
	if value is Dictionary:
		var values: Dictionary = {}
		for key: Variant in value: values[str(key)] = _crowd_handoff_json_value(value[key])
		return values
	return value

static func _crowd_handoff_source_sha256(ordinary: Dictionary) -> String:
	# A full-precision JSON round trip can still move a binary64 value. Hash
	# only a fixed point of that transport, never round or rewrite owner values.
	var encoded := JSON.stringify(_crowd_handoff_json_value(ordinary), "", true, true)
	for _round in range(8):
		var decoded: Variant = JSON.parse_string(encoded)
		if not decoded is Dictionary: return ""
		var next := JSON.stringify(decoded, "", true, true)
		if next == encoded: return encoded.sha256_text()
		encoded = next
	return "" # An unstable representation cannot authorize a frozen handoff.

static func _crowd_actor_source_sha256(actor_state: Dictionary) -> String:
	var ordinary: Dictionary = actor_state.duplicate(false)
	ordinary.erase("crowd_handoff")
	return _crowd_handoff_source_sha256(ordinary)

static func _crowd_actor_solo_current(actor_state: Dictionary, handoff: Dictionary) -> bool:
	if not handoff.has("solo_source_sha256"): return true # Existing format-1 handoffs.
	return str(handoff.solo_source_sha256).length() == 64 and str(handoff.solo_source_sha256) == _crowd_actor_source_sha256(actor_state)

static func _crowd_roster_source_sha256(snapshot: Dictionary) -> String:
	var ordinary: Dictionary = snapshot.duplicate(false)
	ordinary.erase("crowd_state")
	ordinary.erase("crowd_source_sha256")
	return _crowd_handoff_source_sha256(ordinary)

static func _crowd_roster_handoff_current(snapshot: Dictionary) -> bool:
	return str(snapshot.get("crowd_source_sha256", "")).length() == 64 and str(snapshot.crowd_source_sha256) == _crowd_roster_source_sha256(snapshot)

static func _valid_crowd_handoff_formation(formation: Variant) -> bool:
	if not formation is Dictionary or formation.size() != 33 + int(formation.has("garrisoned")): return false
	if formation.has("garrisoned") and not formation.garrisoned is bool: return false
	for field: String in ["morale", "rally_rest", "fatigue", "fatigue_rest", "training", "fatigue_count", "order", "goal_x", "goal_y", "goal_facing", "pursuit_left", "origin_x", "origin_y", "cx", "cy", "facing", "order_delay", "ref_x", "ref_y"]:
		if not _number(formation.get(field), -1000000000000.0, 1000000000000.0): return false
	for field: String in ["morale", "fatigue"]:
		if not _number(formation[field], 0.0, 100.0): return false
	if not _number(formation.training, 0.0, 1000000000000.0): return false
	for field: String in ["pursuit_left", "order_delay"]:
		if float(formation[field]) <= -1.0: return false
	for field: String in ["rally_rest", "fatigue_rest"]:
		if float(formation[field]) < 0.0: return false
	if not _integer(formation.order, 0, 5) or not _integer(formation.fatigue_count, 0, MAX_CROWD_ROWS): return false
	for field: String in ["routed", "needs_attack_order", "commander_present", "ai_enabled", "no_orders", "attacking", "ref_valid", "resupplying", "host_center"]:
		if not formation.get(field) is bool: return false
	for field: String in ["formal_person", "acting_person", "current_person", "target_person"]:
		if not _integer(formation.get(field), -1, 2147483647) or int(formation[field]) == 0: return false
	if not formation.get("officer_persons") is Array: return false
	var officers: Dictionary = {}
	for officer: Variant in formation.officer_persons:
		if not _integer(officer, 1, 2147483647) or officers.has(int(officer)): return false
		officers[int(officer)] = true
	return true

static func _valid_crowd_actor_handoff(value: Variant, identity: int = -1) -> bool:
	if not value is Dictionary or value.size() != 11 + int(value.has("solo_formation")) + int(value.has("solo_source_sha256")) or not _integer(value.get("version"), 1, 1) or not value.get("bandaged") is bool or not _integer(value.get("role"), 0, 2) or not _number(value.get("face"), -1000000000.0, 1000000000.0):
		return false
	if value.has("solo_source_sha256"):
		if not value.has("solo_formation") or not value.solo_source_sha256 is String or value.solo_source_sha256.length() != 64: return false
		for character: String in str(value.solo_source_sha256):
			if not "0123456789abcdef".contains(character): return false
	for field: String in ["escape_t", "knock_t", "act_t", "stagger", "exch_cd", "ranged_cd", "skill_cd"]:
		if not _number(value.get(field), 0.0, 1000000000000.0): return false
	if value.has("solo_formation"):
		var formation: Variant = value.solo_formation
		if not _valid_crowd_handoff_formation(formation): return false
		for field: String in ["formal_person", "acting_person", "current_person"]:
			if int(formation[field]) != -1 and int(formation[field]) != identity: return false
		if formation.officer_persons.size() > 1: return false
		for officer: Variant in formation.officer_persons:
			if int(officer) != identity: return false
	return true

static func _validate_actors(data: TerrainData, state: Dictionary) -> Dictionary:
	var actors: Variant = state.get("actors", {})
	if not actors is Dictionary:
		return Runtime.fail("CORRUPT_SAVE", "人物快照格式")
	if state.has("actor_presence_version") and not _integer(state.actor_presence_version, 1, 1):
		return Runtime.fail("CORRUPT_SAVE", "原人物存在版本非法")
	if actors.is_empty():
		return Runtime.ok() # Empty presence-v1 is an intentionally empty original container; no respawn.
	var explicit_presence := state.has("actor_presence_version")
	if explicit_presence:
		if not _integer(state.actor_presence_version, 1, 1): return Runtime.fail("CORRUPT_SAVE", "原人物存在版本非法")
		for key: Variant in actors:
			if not key is String or key not in ["player", "npc"]: return Runtime.fail("CORRUPT_SAVE", "原人物容器鍵非法")
	elif not actors.has("player") or actors.size() > 2 or (actors.size() == 2 and not actors.has("npc")):
		return Runtime.fail("CORRUPT_SAVE", "人物快照不完整")
	if not state.get("worker") is Dictionary or (not explicit_presence or actors.has("npc")) and not _valid_cell(data, state.worker.get("cell")) or (not explicit_presence or actors.has("player")) and not _valid_cell(data, state.get("player_cell", data.index(data.spawn_cell))):
		return Runtime.fail("CORRUPT_SAVE", "人物地圖格位")
	var identities := {}
	var native_people := {}
	for team: Dictionary in state.get("crowd", {}).get("teams", []):
		for identity: Variant in team.get("person_ids", []): native_people[int(identity)] = true
	for key: String in actors:
		var actor: Variant = actors[key]
		if actor is Dictionary and (actor.has("embarked_vehicle_id") or actor.has("berth_id") or actor.has("ship_death_local") or actor.has("ship_death_settled")): return Runtime.fail("CORRUPT_SAVE", "首版 Actor 不支持乘船字段")
		if actor is Dictionary and actor.has("crowd_handoff") and not _valid_crowd_actor_handoff(actor.crowd_handoff, int(actor.get("person_id", -1))):
			return Runtime.fail("INVALID_CROWD", "群眾人物交接快照格式：" + key)
		var checked_actor: Variant = actor
		if actor is Dictionary and native_people.has(int(actor.get("person_id", -1))):
			if not _valid_walkable_pair(data, actor.get("cell")) or not TerrainTestCharacter._saved_vector(actor.get("position")):
				return Runtime.fail("INVALID_CROWD", "群眾人物連續座標非法：" + key)
			var cell := Vector2i(int(actor.cell[0]), int(actor.cell[1]))
			var position := Vector2(float(actor.position[0]), float(actor.position[1]))
			# Native doubles select the cell; Vector2 presentation can round up at its edge.
			var lower := Vector2(cell) * TerrainRenderer.CELL_PIXELS - Vector2.ONE * 0.001
			var upper := Vector2(cell + Vector2i.ONE) * TerrainRenderer.CELL_PIXELS + Vector2.ONE * 0.001
			if position.x < lower.x or position.y < lower.y or position.x > upper.x or position.y > upper.y or float(actor.get("movement_left", -1.0)) != 0.0:
				return Runtime.fail("INVALID_CROWD", "群眾人物座標與格位不一致：" + key)
			checked_actor = actor.duplicate(true)
			var centre := (Vector2(cell) + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS
			checked_actor.position = [centre.x, centre.y]
		if not TerrainTestCharacter.valid_state(checked_actor, data):
			return Runtime.fail("CORRUPT_SAVE", "人物狀態／實裝非法：" + key)
		var identity := int(actor.person_id)
		if identities.has(identity):
			return Runtime.fail("CORRUPT_SAVE", "重複人物身分")
		identities[identity] = actor
		var expected_cell := int(state.get("player_cell", data.index(data.spawn_cell))) if key == "player" else int(state.worker.cell)
		if data.index(Vector2i(int(actor.cell[0]), int(actor.cell[1]))) != expected_cell:
			return Runtime.fail("CORRUPT_SAVE", "人物與地圖格位不一致")
	var hit_identities := identities.duplicate()
	var rescuers := {}
	for original_team: Dictionary in state.get("armies", []):
		if bool(original_team.get("crowd", false)):
			for unit: Dictionary in original_team.units:
				var identity := int(unit.person_id)
				hit_identities[identity] = true
				identities[identity] = {"hp": unit.hp, "knockout_left": unit.ko, "faction_id": original_team.faction_id, "cell": unit.cell, "movement_left": 0.0}
			continue
		var team := TerrainArmy.normalize_roster_snapshot(original_team)
		for index in range(team.units.size()):
			var identity := int(team.units[index].person_id)
			var unit: Dictionary = team.units[index]
			hit_identities[identity] = true
			identities[identity] = {"hp": unit.hp, "knockout_left": unit.ko, "faction_id": team.faction_id, "cell": unit.cell,
				"movement_left": 0.0 if Vector2(float(unit.destination[0]), float(unit.destination[1])) == Vector2(-1, -1) else 1.0}
		for entry: Dictionary in team.get("rescues", []):
			var patient := int(entry.patient)
			var identity := int(team.player_member.id) if patient == TerrainArmy.PLAYER_MEMBER else int(team.units[patient].person_id)
			if rescuers.has(identity):
				return Runtime.fail("CORRUPT_SAVE", "重複施救者")
			rescuers[identity] = true
	for key: String in actors:
		var actor: Dictionary = actors[key]
		var attack_target := int(actor.get("attack_target", 0))
		if attack_target != 0 and (not hit_identities.has(attack_target) or attack_target == int(actor.person_id)):
			return Runtime.fail("CORRUPT_SAVE", "攻擊目標指向未知人物")
		for identity: Variant in actor.hit_ids:
			if not hit_identities.has(int(identity)) or int(identity) == int(actor.person_id):
				return Runtime.fail("CORRUPT_SAVE", "命中去重指向未知人物")
		if float(actor._rescue_left) <= 0.0:
			if int(actor.rescue_target) != 0:
				return Runtime.fail("CORRUPT_SAVE", "失效的救助關係")
			continue
		var target_id := int(actor.rescue_target)
		if not identities.has(target_id) or target_id == int(actor.person_id) or rescuers.has(target_id):
			return Runtime.fail("CORRUPT_SAVE", "救助關係重複／失效")
		var target: Dictionary = identities[target_id]
		if float(actor.hp) <= 0.0 or float(actor.knockout_left) > 0.0 or bool(actor.captive) or float(target.hp) <= 0.0 or float(target.knockout_left) <= 0.0 or int(actor.faction_id) != int(target.faction_id):
			return Runtime.fail("CORRUPT_SAVE", "救助資格失效")
		var from_cell := Vector2i(int(actor.cell[0]), int(actor.cell[1]))
		var target_cell := Vector2i(int(target.cell[0]), int(target.cell[1]))
		var offset := target_cell - from_cell
		if float(actor.movement_left) > 0.0 or float(target.movement_left) > 0.0 or absi(offset.x) + absi(offset.y) != 1 or not data.can_step(from_cell, target_cell):
			return Runtime.fail("CORRUPT_SAVE", "救助位置失效")
		rescuers[target_id] = int(actor.person_id)
	if not actors.has("npc"):
		return Runtime.ok()
	var navigation: Variant = actors.npc.get("navigation")
	if not navigation is Dictionary or not _integer(navigation.get("command"), 0, 2) or not navigation.get("status") is String or str(navigation.status).length() > 256 or not navigation.get("path") is Array or navigation.path.size() > data.size.x * data.size.y:
		return Runtime.fail("CORRUPT_SAVE", "NPC 命令快照")
	if not TerrainTestCharacter._saved_vector(navigation.get("target")):
		return Runtime.fail("CORRUPT_SAVE", "NPC 目標快照")
	if int(navigation.command) != TerrainTestNPC.Command.STOP and not TerrainTestCharacter._saved_cell(navigation.target, data):
		return Runtime.fail("CORRUPT_SAVE", "NPC 目標格位")
	for cell: Variant in navigation.path:
		if not TerrainTestCharacter._saved_cell(cell, data):
			return Runtime.fail("CORRUPT_SAVE", "NPC 路線快照")
	return Runtime.ok()

static func _validate_corps(state: Dictionary) -> Dictionary:
	if not EquipmentOrders.valid_organization_refs(state): return Runtime.fail("CORRUPT_SAVE", "跨 Site 原組織引用非法")
	var people := {}
	var teams := {}
	for actor: Dictionary in state.get("actors", {}).values():
		people[int(actor.person_id)] = int(actor.faction_id)
	for original: Dictionary in state.get("armies", []):
		var team: Dictionary = original if original.get("crowd") == true else TerrainArmy.normalize_roster_snapshot(original)
		teams[int(team.team_id)] = int(team.faction_id)
		for unit: Dictionary in team.units:
			people[int(unit.person_id)] = int(team.faction_id)
	var remote: Dictionary = state.get("organization_refs", {})
	for key: String in remote.get("remote_people", {}): people[int(key)] = int(remote.remote_people[key].faction_id)
	for key: String in remote.get("remote_teams", {}): teams[int(key)] = int(remote.remote_teams[key].faction_id)
	if not Runtime.valid_corps(state.get("corps", {}), people, teams):
		return Runtime.fail("CORRUPT_SAVE", "軍團長／所屬隊伍引用非法")
	return Runtime.ok()

static func _validate_armies(data: TerrainData, state: Dictionary, check_terrain: bool = false) -> Dictionary:
	var armies: Variant = state.get("armies", [])
	if not armies is Array or armies.size() > MAX_ARMIES:
		return Runtime.fail("CORRUPT_SAVE", "軍隊名冊格式")
	var identities := {}
	var claims := {}
	var source_claims := {}
	var destination_claims := {}
	var batch_groups := {}
	var deployment_claims := {}
	var maximum_team := 0
	var teams_seen := {}
	var total_rows := 0
	var live_presenters := 0
	var actors: Variant = state.get("actors", {})
	if not actors is Dictionary or not actors.get("player", {}) is Dictionary:
		return Runtime.fail("CORRUPT_SAVE", "人物名冊格式")
	var memberships := {}
	var work_claims := {}
	for activity: Variant in [state.get("worker", {}), state.get("manual", {})]:
		if not activity is Dictionary:
			return Runtime.fail("CORRUPT_SAVE", "原作業資料格式")
		if not str(activity.get("target", "")).is_empty():
			var claim := Runtime.work_claim_key(activity)
			if work_claims.has(claim):
				return Runtime.fail("CORRUPT_SAVE", "原作業來源重複")
			work_claims[claim] = true
	for original_team: Variant in armies:
		if original_team is Dictionary and bool(original_team.get("crowd", false)):
			var crowd_team_id := int(original_team.team_id)
			if teams_seen.has(crowd_team_id): return Runtime.fail("INVALID_CROWD", "重複隊伍身分")
			teams_seen[crowd_team_id] = true
			maximum_team = maxi(maximum_team, crowd_team_id)
			for row: Dictionary in original_team.units:
				var identity := int(row.person_id)
				if identities.has(identity): return Runtime.fail("INVALID_CROWD", "重複人物紀錄")
				identities[identity] = true
			continue
		if original_team is Dictionary and original_team.has("crowd_source_sha256"):
			var source_sha: Variant = original_team.crowd_source_sha256
			if not source_sha is String or source_sha.length() != 64 or not _valid_crowd_handoff_formation(original_team.get("crowd_state")):
				return Runtime.fail("CORRUPT_SAVE", "軍隊群眾交接快照／來源雜湊格式")
			for character: String in str(source_sha):
				if not "0123456789abcdef".contains(character): return Runtime.fail("CORRUPT_SAVE", "軍隊群眾交接來源雜湊格式")
			# A stale envelope is inactive evidence; never re-sign it during validation.
		var member_actor: Dictionary = actors.get("player", {})
		if original_team is Dictionary and original_team.get("player_member") is Dictionary and not original_team.player_member.is_empty():
			member_actor = {}
			for actor: Dictionary in actors.values():
				if int(actor.get("person_id", 0)) == int(original_team.player_member.get("id", -1)):
					member_actor = actor
		# Army person social packet this build does not admit: SAVE_VERSION, the same contract as
		# _validate_unadmitted_social_state (army units). Only social rejection; other invalid state stays CORRUPT_SAVE.
		var army_units: Array = original_team.get("units", []) if original_team is Dictionary and original_team.get("units") is Array else []
		for unit: Variant in army_units:
			if unit is Dictionary and unit.has("social_state") and not TerrainTestCharacter.PersonSocial.valid(unit.social_state):
				return Runtime.fail("SAVE_VERSION", "Army person social_state 尚未准入；完整原檔與原現場保留")
		if not TerrainArmy.valid_combat_state(original_team, data, member_actor, state):
			return Runtime.fail("CORRUPT_SAVE", "軍隊人物／動作／指揮關係非法")
		var team := TerrainArmy.normalize_roster_snapshot(original_team)
		var excluded_crew := {}
		for unit: Dictionary in team.units:
			if unit.has("embarked_vehicle_id"): excluded_crew[int(unit.person_id)] = true
		if state.get("vehicles", {}) is Dictionary:
			for vehicle: Variant in state.get("vehicles", {}).values():
				if not vehicle is Dictionary or not Runtime.SIEGE_DEFINITIONS.has(str(vehicle.get("kind", ""))) or not _integer(vehicle.get("team_id"), int(team.team_id), int(team.team_id)) or not vehicle.get("crew_slots") is Dictionary: continue
				for person_id: Variant in vehicle.crew_slots.values():
					if _integer(person_id, 1, 2147483647): excluded_crew[int(person_id)] = true
		if not _valid_combat_movement_snapshot(data, team, batch_groups, excluded_crew, state):
			return Runtime.fail("CORRUPT_SAVE", "軍隊行軍／部署／在途依賴非法")
		var deployment: Variant = team.get("combat_deployment_plan", null)
		if deployment is Dictionary:
			for pair: Array in deployment.get("member_slot_map", {}).values():
				var slot := Vector2i(int(pair[0]), int(pair[1]))
				if deployment_claims.has(slot) and deployment_claims[slot] != int(team.team_id):
					return Runtime.fail("CORRUPT_SAVE", "跨隊部署槽位重疊")
				deployment_claims[slot] = int(team.team_id)
			for key: String in deployment.get("slot_lease_timers", {}).keys():
				var parts := key.split(",")
				var leased_slot := Vector2i(int(parts[0]), int(parts[1]))
				if deployment_claims.has(leased_slot) and deployment_claims[leased_slot] != int(team.team_id):
					return Runtime.fail("CORRUPT_SAVE", "跨隊部署槽位重疊")
				deployment_claims[leased_slot] = int(team.team_id)
		if teams_seen.has(int(team.team_id)):
			return Runtime.fail("CORRUPT_SAVE", "重複隊伍身分")
		teams_seen[int(team.team_id)] = true
		total_rows += team.units.size()
		if total_rows > MAX_ARMY_ROWS:
			return Runtime.fail("CORRUPT_SAVE", "目前 Site 上限為 %d 列軍隊人物" % MAX_ARMY_ROWS)
		if not team.get("player_member", {}).is_empty():
			var member_id := int(team.player_member.id)
			if memberships.has(member_id):
				return Runtime.fail("CORRUPT_SAVE", "同一玩家不能加入兩隊")
			memberships[member_id] = true
		maximum_team = maxi(maximum_team, int(team.team_id))
		for index in range(team.units.size()):
			var identity := int(team.units[index].person_id)
			if identities.has(identity):
				return Runtime.fail("CORRUPT_SAVE", "重複軍隊人物身分")
			identities[identity] = true
			var unit: Dictionary = team.units[index]
			var work: Variant = unit.get("work_task", {})
			if not WorkTeam.valid_task(data, state, work):
				return Runtime.fail("CORRUPT_SAVE", "原隊員作業引用／欄位")
			if not bool(unit.get("member", true)) and not work.is_empty() and not bool(work.get("manual", false)):
				return Runtime.fail("CORRUPT_SAVE", "獨立原人物不能帶回原隊伍的自動派工令")
			if not work.is_empty() and str(work.mode) not in ["paused", "rest"] and not str(work.target).is_empty():
				var claim := Runtime.work_claim_key(work)
				if work_claims.has(claim):
					return Runtime.fail("CORRUPT_SAVE", "同一來源由多名原人物重複作業")
				work_claims[claim] = true
			live_presenters += int(str(unit.visual_role) in ["female_live", "male_live"])
			if live_presenters > MAX_ARMIES:
				return Runtime.fail("CORRUPT_SAVE", "現場原隊長呈現者超過隊伍上限")
			if unit.has("embarked_vehicle_id") or unit.get("ship_death_settled", false) == true: continue # Historical shore cell is not an active position.
			var cell := Vector2i(int(unit.cell[0]), int(unit.cell[1]))
			var destination := Vector2i(int(unit.destination[0]), int(unit.destination[1]))
			if check_terrain and (not data.is_walkable(cell) or destination != TerrainArmy.INVALID_CELL and not data.can_step(cell, destination)):
				return Runtime.fail("CORRUPT_SAVE", "軍隊格位／移動跨越非法地形")
			var standing := float(unit.hp) > 0.0 and float(unit.ko) <= 0.0 and not bool(unit.departed) and not bool(unit.get("site_exited", false))
			if standing or destination != TerrainArmy.INVALID_CELL:
				if source_claims.has(cell):
					return Runtime.fail("CORRUPT_SAVE", "軍隊來源占位重疊")
				source_claims[cell] = identity
			if destination != TerrainArmy.INVALID_CELL:
				if destination_claims.has(destination):
					return Runtime.fail("CORRUPT_SAVE", "軍隊目的格預約重疊")
				destination_claims[destination] = identity
	for cell: Vector2i in destination_claims.keys():
		if source_claims.has(cell):
			var source_id: int = source_claims[cell]
			var moving_id: int = destination_claims[cell]
			if not batch_groups.has(source_id) or batch_groups.get(source_id) != batch_groups.get(moving_id):
				return Runtime.fail("CORRUPT_SAVE", "未宣告的軍隊來源／目的格重疊")
	claims = source_claims.duplicate()
	for cell: Vector2i in destination_claims.keys():
		claims[cell] = destination_claims[cell]
	if state.has("army_next_team") and not _integer(state.army_next_team, maximum_team + 1, 999999):
		return Runtime.fail("CORRUPT_SAVE", "軍隊身分序號失效")
	var native_actor_ids := {}
	for native_team: Dictionary in state.get("crowd", {}).get("teams", []):
		for identity: Variant in native_team.get("person_ids", []): native_actor_ids[int(identity)] = true
	for actor: Variant in actors.values():
		# _validate_actors performs native continuous-coordinate and legacy metadata validation.
		# A social packet this build does not admit is SAVE_VERSION (not yet admitted), the same contract as
		# _validate_unadmitted_social_state. Only social rejection; other invalid state stays CORRUPT_SAVE.
		if actor is Dictionary and not native_actor_ids.has(int(actor.get("person_id", -1))) and actor.has("social_state") and not TerrainTestCharacter.PersonSocial.valid(actor.social_state):
			return Runtime.fail("SAVE_VERSION", "Actor social_state 尚未准入；完整原檔與原現場保留")
		if not actor is Dictionary or (not native_actor_ids.has(int(actor.get("person_id", -1))) and not TerrainTestCharacter.valid_state(actor, data)):
			return Runtime.fail("CORRUPT_SAVE", "人物狀態非法")
		if identities.has(int(actor.person_id)):
			return Runtime.fail("CORRUPT_SAVE", "軍隊與人物身分重複")
		identities[int(actor.person_id)] = true
		if not armies.is_empty() and not bool(actor.get("site_exited", false)) and (float(actor.hp) > 0.0 and float(actor.knockout_left) <= 0.0 or float(actor.movement_left) > 0.0):
			var cell := Vector2i(int(actor.cell[0]), int(actor.cell[1]))
			var previous := Vector2i(int(actor.movement_from[0]), int(actor.movement_from[1]))
			if claims.has(cell) or float(actor.movement_left) > 0.0 and claims.has(previous):
				return Runtime.fail("CORRUPT_SAVE", "人物與軍隊占位重疊")
	for original_team: Dictionary in armies:
		if bool(original_team.get("crowd", false)): continue
		var team := TerrainArmy.normalize_roster_snapshot(original_team)
		if int(team.combat_order) == TerrainArmy.CombatOrder.PURSUE and (float(team.pursuit_left) <= 0.0 or not identities.has(int(team.pursuit_target))):
			return Runtime.fail("CORRUPT_SAVE", "追擊目標／倒數失效")
		for index in range(team.units.size()):
			for identity: Variant in team.units[index].hits:
				if not identities.has(int(identity)) or int(identity) == int(team.units[index].person_id):
					return Runtime.fail("CORRUPT_SAVE", "軍隊命中去重指向未知人物")
	return Runtime.ok()

static func _valid_combat_movement_snapshot(data: TerrainData, team: Dictionary, batch_groups: Dictionary, excluded_crew: Dictionary = {}, state: Dictionary = {}) -> bool:
	if team.has("structure_waiting") and (team.structure_waiting != true or int(team.get("combat_order", 0)) == TerrainArmy.CombatOrder.HOLD): return false
	var people: Dictionary = {}
	for unit: Dictionary in team.units:
		people[int(unit.person_id)] = unit
	var team_preset: Variant = team.get("formation_preset_id", "auto")
	if not team_preset is String or not Destination.is_valid_preset(team_preset): return false
	var separate_intent := team.has("formation_intent_version")
	if separate_intent and not _integer(team.formation_intent_version, 1, 1): return false
	var deployment: Variant = team.get("combat_deployment_plan", null)
	var movement: Variant = team.get("combat_move_plan", null)
	var absent_slots: Variant = team.get("combat_absent_slots", {})
	if not absent_slots is Dictionary or absent_slots.size() > team.units.size() or (deployment == null or movement == null) and not absent_slots.is_empty(): return false
	var deployment_anchor: Variant = null
	if deployment != null:
		if not deployment is Dictionary:
			return false
		var saved_version: Variant = deployment.get("shape_version", 1)
		if not _integer(saved_version, 1, 3): return false
		var legacy_deployment: bool = int(saved_version) == 1
		var partial_deployment: bool = int(saved_version) == 3
		var deployment_preset := "auto"
		if legacy_deployment:
			if deployment.has("formation_preset_id") or (not separate_intent and team_preset != "auto"): return false
		else:
			var plan_preset: Variant = deployment.get("formation_preset_id", null)
			if not team.has("formation_preset_id") or not plan_preset is String or not Destination.is_valid_preset(plan_preset) or (not separate_intent and plan_preset != team_preset): return false
			deployment_preset = plan_preset
		deployment_anchor = deployment.get("resolved_anchor")
		if not _valid_walkable_pair(data, deployment_anchor):
			if not legacy_deployment or not movement is Dictionary or not _valid_walkable_pair(data, movement.get("resolved_anchor")):
				return false
			deployment_anchor = movement.resolved_anchor
		if not legacy_deployment and not _valid_xy_pair(data, deployment.get("final_facing")):
			return false
		if deployment.has("final_facing"):
			if not _valid_xy_pair(data, deployment.final_facing):
				return false
			var facing := Vector2i(int(deployment.final_facing[0]), int(deployment.final_facing[1]))
			if facing not in TerrainData.DIRECTIONS:
				return false
		if not _integer(deployment.get("order_serial"), 1, 2147483647):
			return false
		if not legacy_deployment and (not _integer(team.get("combat_order_serial"), 1, 2147483647) \
			or int(team.combat_order_serial) != int(deployment.order_serial)):
			return false
		var platform: Variant = deployment.get("platform_slots", [])
		var queue: Variant = deployment.get("approach_queue_slots", [])
		var member_slots: Variant = deployment.get("member_slot_map", {})
		var member_roles: Variant = deployment.get("member_role_map", {})
		var followers: Variant = deployment.get("following_member_ids", [])
		if not platform is Array or not queue is Array or not member_slots is Dictionary or not member_roles is Dictionary \
			or platform.size() > data.size.x * data.size.y or queue.size() > data.size.x * data.size.y or member_slots.size() > team.units.size() or member_roles.size() != member_slots.size():
			return false
		if not followers is Array or followers.size() > team.units.size() or (partial_deployment and not deployment.has("following_member_ids")) or (not partial_deployment and not followers.is_empty()): return false
		var following_set: Dictionary = {}
		for value: Variant in followers:
			if not _integer(value, 1, 2147483647): return false
			var id: int = int(value)
			if following_set.has(id) or not people.has(id) or member_slots.has(str(id)) or member_slots.has(id) or member_roles.has(str(id)) or member_roles.has(id) or absent_slots.has(str(id)) or absent_slots.has(id): return false
			var person: Dictionary = people[id]
			if float(person.hp) <= 0.0 or bool(person.get("dead", false)) or bool(person.departed) or bool(person.get("site_exited", false)) or not bool(person.get("member", true)): return false
			following_set[id] = true
		if not followers.is_empty() and (not movement is Dictionary or int(team.combat_order) != TerrainArmy.CombatOrder.MOVE): return false
		if not followers.is_empty() and int(movement.get("phase", -1)) == CombatMovementTypes.CombatMovePhase.COMPLETE: return false
		var platform_set: Dictionary = {}
		var queue_set: Dictionary = {}
		for pair: Variant in platform:
			if not _valid_walkable_pair(data, pair): return false
			var cell := Vector2i(int(pair[0]), int(pair[1]))
			if platform_set.has(cell): return false
			platform_set[cell] = true
		for pair: Variant in queue:
			if not _valid_walkable_pair(data, pair): return false
			var cell := Vector2i(int(pair[0]), int(pair[1]))
			if platform_set.has(cell) or queue_set.has(cell): return false
			queue_set[cell] = true
		if not legacy_deployment:
			var requested: Variant = deployment.get("requested_count")
			if not _integer(requested, 1, 200) or int(requested) > team.units.size(): return false
			var facing := Vector2i(int(deployment.final_facing[0]), int(deployment.final_facing[1]))
			var side := Vector2i(-facing.y, facing.x)
			var width: Variant = deployment.get("final_width")
			var depth: Variant = deployment.get("final_depth")
			var anchor := Vector2i(int(deployment_anchor[0]), int(deployment_anchor[1]))
			var dimension_limit: int = maxi(data.size.x, data.size.y)
			if partial_deployment:
				dimension_limit = maxi(dimension_limit, Destination.MAX_PRESET_RADIUS * 2 + 1)
			if not _integer(width, 1, dimension_limit) or not _integer(depth, 1, dimension_limit): return false
			if partial_deployment and member_slots.size() + followers.size() + absent_slots.size() > int(requested): return false
			if deployment_preset == "auto":
				var columns: Dictionary = {}
				for cell: Vector2i in platform_set.keys():
					columns[(cell.x - anchor.x) * side.x + (cell.y - anchor.y) * side.y] = true
				var auto_width := mini(10, maxi(1, columns.size()))
				var auto_depth := ceili(float(platform.size()) / float(auto_width))
				if partial_deployment:
					auto_depth = maxi(1, auto_depth)
				if int(width) != auto_width or int(depth) != auto_depth: return false
			else:
				if (not partial_deployment and platform.size() != int(requested)) or platform.size() > int(requested): return false
				var expected: Array[Vector2i] = Destination.shape_slots(deployment_preset, int(requested), anchor, facing)
				if expected.size() != int(requested): return false
				for cell: Vector2i in platform_set.keys():
					if not expected.has(cell): return false
				var min_side := 2147483647
				var max_side := -2147483647
				var min_front := 2147483647
				var max_front := -2147483647
				for cell: Vector2i in expected:
					if not partial_deployment and not platform_set.has(cell): return false
					var offset := cell - anchor
					var lateral := offset.x * side.x + offset.y * side.y
					var axial := offset.x * facing.x + offset.y * facing.y
					min_side = mini(min_side, lateral)
					max_side = maxi(max_side, lateral)
					min_front = mini(min_front, axial)
					max_front = maxi(max_front, axial)
				if int(width) != max_side - min_side + 1 or int(depth) != max_front - min_front + 1: return false
		var assigned: Dictionary = {}
		for key: Variant in member_slots.keys():
			if not str(key).is_valid_int() or str(int(key)) != str(key) or not people.has(int(key)) or not member_roles.has(key) or not _valid_walkable_pair(data, member_slots[key]):
				return false
			var cell := Vector2i(int(member_slots[key][0]), int(member_slots[key][1]))
			var role: Variant = member_roles[key]
			if assigned.has(cell) or not _integer(role, 0, 1) or (int(role) == 0 and not platform_set.has(cell)) or (int(role) == 1 and not queue_set.has(cell)) \
				or (not legacy_deployment and deployment_preset != "auto" and int(role) != 0):
				return false
			assigned[cell] = true
		if partial_deployment:
			for id: int in people.keys():
				var person: Dictionary = people[id]
				if float(person.hp) > 0.0 and float(person.ko) <= 0.0 and str(person.pose) != "get_up" and not bool(person.get("dead", false)) and not bool(person.departed) and not bool(person.get("site_exited", false)) and bool(person.get("member", true)) \
					and not member_slots.has(str(id)) and not following_set.has(id) and not absent_slots.has(str(id)) and not excluded_crew.has(id):
					return false
		var list_sets: Dictionary = {}
		for field: String in ["queue_member_ids", "pending_platform_member_ids", "admitted_platform_member_ids", "settled_platform_member_ids", "settled_queue_member_ids"]:
			if not legacy_deployment and not deployment.has(field): return false
			var mids: Variant = deployment.get(field, [])
			if not mids is Array or mids.size() > member_slots.size(): return false
			var seen: Dictionary = {}
			for value: Variant in mids:
				if not _integer(value, 1, 2147483647): return false
				var id: int = int(value)
				var member_key := str(id)
				if seen.has(id) or not member_slots.has(member_key): return false
				if field == "queue_member_ids" or field == "settled_queue_member_ids":
					if int(member_roles[member_key]) != 1: return false
				elif int(member_roles[member_key]) != 0:
					return false
				seen[id] = true
			list_sets[field] = seen
		for key: Variant in member_roles.keys():
			if int(member_roles[key]) == 1 and not list_sets["queue_member_ids"].has(int(key)): return false
		for id: int in list_sets["settled_queue_member_ids"].keys():
			if not list_sets["queue_member_ids"].has(id): return false
		for id: int in list_sets["settled_platform_member_ids"].keys():
			if deployment.has("admitted_platform_member_ids") and not list_sets["admitted_platform_member_ids"].has(id): return false
		var ever_admitted: Variant = deployment.get("ever_admitted_platform_member_ids", deployment.get("admitted_platform_member_ids", []))
		if not ever_admitted is Array or ever_admitted.size() > team.units.size(): return false
		var ever_seen: Dictionary = {}
		for value: Variant in ever_admitted:
			if not _integer(value, 1, 2147483647): return false
			var id: int = int(value)
			if ever_seen.has(id) or not people.has(id) or (not member_slots.has(str(id)) and not absent_slots.has(str(id))): return false
			ever_seen[id] = true
		for id: int in list_sets["admitted_platform_member_ids"].keys():
			if not ever_seen.has(id): return false
		if not legacy_deployment:
			for id: int in list_sets["pending_platform_member_ids"].keys():
				if list_sets["admitted_platform_member_ids"].has(id): return false
		if deployment.has("queue_released") and not deployment.queue_released is bool: return false
		if not legacy_deployment and not deployment.has("queue_released"): return false
		var locks: Variant = deployment.get("member_slot_locked", {})
		if not locks is Dictionary: return false
		for key: Variant in locks.keys():
			if not member_slots.has(key) or not locks[key] is bool: return false
		var tactical: Variant = deployment.get("slot_tactical_roles", {})
		if not tactical is Dictionary: return false
		for key: Variant in tactical.keys():
			if not _valid_grid_key(data, key) or not _integer(tactical[key], 0, 4): return false
		var timers: Variant = deployment.get("slot_lease_timers", {})
		var owners: Variant = deployment.get("slot_lease_owner_map", {})
		var lease_roles: Variant = deployment.get("slot_lease_role_map", {})
		var queue_indexes: Variant = deployment.get("slot_lease_queue_index_map", {})
		if not timers is Dictionary or not owners is Dictionary or not lease_roles is Dictionary or not queue_indexes is Dictionary or timers.size() != owners.size() or timers.size() != lease_roles.size(): return false
		for key: Variant in timers.keys():
			if not _valid_grid_key(data, key) or not owners.has(key) or not lease_roles.has(key) or not _number(timers[key], 0.0, 60.0) or not _integer(owners[key], 1, 2147483647) or not _integer(lease_roles[key], 0, 1): return false
			var parts: PackedStringArray = str(key).split(",")
			var lease_cell := Vector2i(int(parts[0]), int(parts[1]))
			var owner_id: int = int(owners[key])
			var owner_key := str(owner_id)
			if key != "%d,%d" % [lease_cell.x, lease_cell.y] or assigned.has(lease_cell) or not people.has(owner_id) or not absent_slots.has(owner_key) or not _valid_walkable_pair(data, absent_slots[owner_key]): return false
			if lease_cell != Vector2i(int(absent_slots[owner_key][0]), int(absent_slots[owner_key][1])): return false
			var person: Dictionary = people[owner_id]
			if float(person.hp) <= 0.0 or bool(person.departed) or not bool(person.get("member", true)): return false
			var lease_role: int = int(lease_roles[key])
			if (lease_role == 0 and (not platform_set.has(lease_cell) or queue_indexes.has(key))) or (lease_role == 1 and (not queue_set.has(lease_cell) or not queue_indexes.has(key))): return false
		for key: Variant in lease_roles.keys():
			if not timers.has(key) or not _integer(lease_roles[key], 0, 1): return false
		for key: Variant in queue_indexes.keys():
			if not timers.has(key) or not _integer(queue_indexes[key], 0, team.units.size()): return false
		if not _integer(deployment.get("available_platform_capacity", platform.size()), platform.size(), data.size.x * data.size.y) \
			or not _integer(deployment.get("queue_capacity", queue.size()), queue.size(), data.size.x * data.size.y): return false
	for key: Variant in absent_slots.keys():
		if not str(key).is_valid_int() or str(int(key)) != str(key) or not people.has(int(key)) or not _valid_walkable_pair(data, absent_slots[key]): return false
		var person: Dictionary = people[int(key)]
		if float(person.hp) <= 0.0 or bool(person.departed) or not bool(person.get("member", true)) or deployment.member_slot_map.has(key): return false
		var cell := Vector2i(int(absent_slots[key][0]), int(absent_slots[key][1]))
		var in_final_set := false
		for pair: Variant in deployment.get("platform_slots", []) + deployment.get("approach_queue_slots", []):
			if cell == Vector2i(int(pair[0]), int(pair[1])):
				in_final_set = true
				break
		if not in_final_set: return false
		var lease_key := "%d,%d" % [cell.x, cell.y]
		var lease_owners: Dictionary = deployment.get("slot_lease_owner_map", {})
		if lease_owners.has(lease_key) and int(lease_owners[lease_key]) != int(key): return false
	if movement != null:
		if not movement is Dictionary or deployment == null or not _integer(movement.get("order_serial"), 1, 2147483647) \
			or int(movement.order_serial) != int(deployment.order_serial) or not _valid_walkable_pair(data, movement.get("resolved_anchor")) \
			or movement.resolved_anchor != deployment_anchor or not _integer(movement.get("phase"), 0, 5):
			return false
		if movement.has("structure_blocked") and not movement.structure_blocked is bool: return false
		if bool(movement.get("structure_blocked", false)) and (team.get("structure_waiting") != true or movement.get("macro_path", []).size() != 1 or int(movement.get("macro_cursor", -1)) != 0): return false
		if movement.has("platform_settled_highwater") and not _integer(movement.platform_settled_highwater, deployment.settled_platform_member_ids.size(), team.units.size()): return false
		if movement.has("vacancy_chain_state") and not _valid_vacancy_chain_state(data, deployment, movement.vacancy_chain_state, people): return false
		var vacated_cells: Variant = movement.get("member_recovery_vacated_cell", {})
		if not vacated_cells is Dictionary or vacated_cells.size() > deployment.member_slot_map.size(): return false
		for key: Variant in vacated_cells.keys():
			if not key is String or not key.is_valid_int() or str(int(key)) != key or not deployment.member_slot_map.has(key) \
				or int(deployment.member_role_map.get(key, -1)) != 0 or not _valid_walkable_pair(data, vacated_cells[key]):
				return false
			var vacated_cell := Vector2i(int(vacated_cells[key][0]), int(vacated_cells[key][1]))
			var is_platform_slot := false
			for pair: Array in deployment.platform_slots:
				if vacated_cell == Vector2i(int(pair[0]), int(pair[1])):
					is_platform_slot = true
					break
			if not is_platform_slot: return false
		var path: Variant = movement.get("macro_path", [])
		if not path is Array or path.is_empty() or path.size() > data.size.x * data.size.y or not _integer(movement.get("macro_cursor"), 0, path.size() - 1): return false
		var previous := Vector2i(-1, -1)
		for pair: Variant in path:
			if not _valid_walkable_pair(data, pair): return false
			var cell := Vector2i(int(pair[0]), int(pair[1]))
			if previous != Vector2i(-1, -1) and not data.can_step(previous, cell): return false
			previous = cell
	var batches: Variant = team.get("combat_batches", [])
	if not batches is Array or batches.size() > team.units.size(): return false
	var retreat_members: Variant = team.get("combat_batch_retreat_members", [])
	if not retreat_members is Array or retreat_members.size() > team.units.size(): return false
	var retreat_member_set: Dictionary = {}
	for value: Variant in retreat_members:
		if not _integer(value, 1, 2147483647) or not people.has(int(value)) or retreat_member_set.has(int(value)): return false
		retreat_member_set[int(value)] = true
	var move_members: Variant = team.get("combat_batch_move_members", [])
	if not move_members is Array or move_members.size() > team.units.size(): return false
	var move_member_set: Dictionary = {}
	for value: Variant in move_members:
		if not _integer(value, 1, 2147483647) or not people.has(int(value)) or move_member_set.has(int(value)) or retreat_member_set.has(int(value)): return false
		move_member_set[int(value)] = true
	var seen_batch_members: Dictionary = {}
	for group_index in range(batches.size()):
		var group: Variant = batches[group_index]
		if not group is Array or group.is_empty() or group.size() > team.units.size(): return false
		var sources: Dictionary = {}
		var destinations: Dictionary = {}
		var direction := Vector2i.ZERO
		var same_direction := true
		var retreat_count := 0
		var move_count := 0
		for value: Variant in group:
			if not _integer(value, 1, 2147483647) or not people.has(int(value)) or seen_batch_members.has(int(value)): return false
			var unit: Dictionary = people[int(value)]
			var source := Vector2i(int(unit.cell[0]), int(unit.cell[1]))
			var destination := Vector2i(int(unit.destination[0]), int(unit.destination[1]))
			var step := destination - source
			if destination == TerrainArmy.INVALID_CELL or step not in TerrainData.DIRECTIONS or sources.has(source) or destinations.has(destination): return false
			if direction != Vector2i.ZERO and direction != step: same_direction = false
			direction = step
			sources[source] = true
			destinations[destination] = true
			retreat_count += int(retreat_member_set.has(int(value)))
			move_count += int(move_member_set.has(int(value)))
			seen_batch_members[int(value)] = true
			batch_groups[int(value)] = "%d:%d" % [int(team.team_id), group_index]
		var empty_tails := 0
		for destination: Vector2i in destinations.keys():
			if not sources.has(destination): empty_tails += 1
		# A committed reciprocal pair keeps its starting order when a new combat
		# order arrives before the physical completion barrier.
		if empty_tails == 0:
			if group.size() != 2 or (move_count != 2 and retreat_count != 2): return false
		elif not same_direction or empty_tails != 1:
			var compound_bound: bool = false
			if state.get("vehicles") is Dictionary:
				for vehicle: Variant in state.vehicles.values():
					if not vehicle is Dictionary or not TerrainArmy.valid_saved_siege_compound(team, data, vehicle) or vehicle.crew_slots.size() != group.size(): continue
					var same_members: bool = true
					for member: Variant in group:
						if not vehicle.crew_slots.values().has(int(member)): same_members = false
					if same_members: compound_bound = true; break
			if not compound_bound: return false
	for mid: int in retreat_member_set:
		if not seen_batch_members.has(mid): return false
	for mid: int in move_member_set:
		if not seen_batch_members.has(mid): return false
	return true

static func _valid_vacancy_chain_state(data: TerrainData, deployment: Dictionary, value: Variant, people: Dictionary) -> bool:
	if not value is Dictionary:
		return false
	for field: String in ["planning_time_sec", "last_platform_progress_time_sec", "next_platform_recovery_time_sec", "started_sec", "last_progress_sec"]:
		if not _number(value.get(field), 0.0, 1000000000.0):
			return false
	var now: float = float(value.planning_time_sec)
	if float(value.started_sec) > now or float(value.last_progress_sec) > now or float(value.last_platform_progress_time_sec) > now:
		return false
	var active: Variant = value.get("active")
	var queued: Variant = value.get("queued")
	var hold: Variant = value.get("hold")
	var verified: Variant = value.get("verified")
	var starts: Variant = value.get("start_cells")
	var targets: Variant = value.get("targets")
	if not active is Array or not queued is Array or not hold is Array or not verified is Array or not starts is Dictionary or not targets is Dictionary \
		or active.size() > people.size() or queued.size() > people.size() or hold.size() > people.size() or verified.size() > people.size() \
		or starts.size() != active.size() or targets.size() != active.size() or not value.get("verified_pending") is bool \
		or not _integer(value.get("arrived_count"), 0, active.size()) or not _integer(value.get("waiting"), -1, 2147483647):
		return false
	var assigned: Dictionary = deployment.member_slot_map
	var roles: Dictionary = deployment.member_role_map
	var active_ids: Dictionary = {}
	for member: Variant in active:
		if not _integer(member, 1, 2147483647):
			return false
		var id: int = int(member)
		var key := str(id)
		if active_ids.has(id) or id == int(value.waiting) or not people.has(id) or not assigned.has(key) or int(roles.get(key, -1)) != 0 \
			or not starts.has(key) or not targets.has(key) or not _valid_walkable_pair(data, starts[key]) or not _valid_walkable_pair(data, targets[key]):
			return false
		var start := Vector2i(int(starts[key][0]), int(starts[key][1]))
		var target := Vector2i(int(targets[key][0]), int(targets[key][1]))
		var physical := Vector2i(int(people[id].cell[0]), int(people[id].cell[1]))
		if target != Vector2i(int(assigned[key][0]), int(assigned[key][1])) or physical != start and physical != target or not data.can_step(start, target):
			return false
		active_ids[id] = true
	for field_map: Dictionary in [starts, targets]:
		for key: Variant in field_map:
			if not key is String or not key.is_valid_int() or str(int(key)) != key or not active_ids.has(int(key)):
				return false
	var held_ids: Dictionary = {}
	for member: Variant in hold:
		if not _integer(member, 1, 2147483647) or held_ids.has(int(member)) or not assigned.has(str(int(member))):
			return false
		held_ids[int(member)] = true
	var verified_ids: Dictionary = {}
	for member: Variant in verified:
		if not _integer(member, 1, 2147483647) or verified_ids.has(int(member)) or not assigned.has(str(int(member))):
			return false
		verified_ids[int(member)] = true
	var waiting: int = int(value.waiting)
	if waiting >= 0 and (not assigned.has(str(waiting)) or int(roles.get(str(waiting), -1)) != 0 or not held_ids.has(waiting)):
		return false
	if not queued.is_empty() and (active.size() != 1 or waiting < 0):
		return false
	var expected := Vector2i(-1, -1)
	if waiting >= 0:
		expected = Vector2i(int(assigned[str(waiting)][0]), int(assigned[str(waiting)][1]))
	var queued_ids: Dictionary = {}
	for i in range(queued.size() - 1, -1, -1):
		var step: Variant = queued[i]
		if not step is Dictionary or step.size() != 3 or not _integer(step.get("actor"), 1, 2147483647) \
			or not _valid_walkable_pair(data, step.get("from")) or not _valid_walkable_pair(data, step.get("to")):
			return false
		var id: int = int(step.actor)
		var key := str(id)
		var source := Vector2i(int(step["from"][0]), int(step["from"][1]))
		var target := Vector2i(int(step["to"][0]), int(step["to"][1]))
		if queued_ids.has(id) or active_ids.has(id) or id == waiting or not people.has(id) or not assigned.has(key) \
			or int(roles.get(key, -1)) != 0 or source != Vector2i(int(assigned[key][0]), int(assigned[key][1])) \
			or source != Vector2i(int(people[id].cell[0]), int(people[id].cell[1])) or target != expected or not data.can_step(source, target):
			return false
		queued_ids[id] = true
		expected = source
	if not queued.is_empty() and Vector2i(int(starts[str(int(active[0]))][0]), int(starts[str(int(active[0]))][1])) != Vector2i(int(assigned[str(waiting)][0]), int(assigned[str(waiting)][1])):
		return false
	if waiting < 0 and (not queued.is_empty() or not active.is_empty()):
		return false
	return true

static func _valid_xy_pair(data: TerrainData, value: Variant) -> bool:
	return value is Array and value.size() == 2 and _integer(value[0], -1, data.size.x - 1) and _integer(value[1], -1, data.size.y - 1)

static func _valid_walkable_pair(data: TerrainData, value: Variant) -> bool:
	return _valid_xy_pair(data, value) and data.contains(Vector2i(int(value[0]), int(value[1]))) and data.is_walkable(Vector2i(int(value[0]), int(value[1])))

static func _valid_grid_key(data: TerrainData, key: Variant) -> bool:
	if not key is String: return false
	var parts: PackedStringArray = key.split(",")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int(): return false
	return _valid_walkable_pair(data, [int(parts[0]), int(parts[1])])

static func _validate_vehicles(data: TerrainData, state: Dictionary, check_terrain: bool = false, region_context: Dictionary = {}) -> Dictionary:
	var vehicles: Variant = state.get("vehicles", {})
	if not vehicles is Dictionary or vehicles.size() > data.size.x * data.size.y or not _integer(state.get("next_vehicle", 1), 1, 2147483647):
		return Runtime.fail("CORRUPT_SAVE", "車輛資料／序號")
	var people := {}
	var team_counts := {}
	var claims := {}
	var total := 0
	for original_team: Dictionary in state.get("armies", []):
		var team := TerrainArmy.normalize_roster_snapshot(original_team)
		team_counts[int(team.team_id)] = team.units.size()
		total += team.units.size()
		for unit: Dictionary in team.units:
			people[int(unit.person_id)] = {"team": int(team.team_id), "body": unit, "snapshot": team}
	for actor: Dictionary in state.get("actors", {}).values(): people[int(actor.person_id)] = {"team": 0, "body": actor}
	var fs_schema := _validate_fs_targets(data, state, people)
	if not fs_schema.ok: return fs_schema
	var ship_relationships := _validate_ship_relationships(data, state, people)
	if not ship_relationships.ok: return ship_relationships
	var ship_build_teams := _validate_ship_build_teams(state)
	if not ship_build_teams.ok: return ship_build_teams
	if vehicles.is_empty(): return Runtime.ok()
	for identity: int in people:
		var body: Dictionary = people[identity].body
		if body.has("embarked_vehicle_id"): continue # Original ship-relative person has no LAND claim.
		var cell := Vector2i(int(body.cell[0]), int(body.cell[1]))
		var destination: Array = body.get("destination", [-1, -1])
		var moving := Vector2i(int(destination[0]), int(destination[1])) != TerrainArmy.INVALID_CELL
		if body.has("movement_left") and float(body.movement_left) > 0.0:
			destination = body.movement_from
			moving = true
		if float(body.hp) > 0.0 and float(body.get("ko", body.get("knockout_left", 0.0))) <= 0.0 and not bool(body.get("departed", false)) and not bool(body.get("site_exited", false)) or moving:
			claims[cell] = identity
			if moving: claims[Vector2i(int(destination[0]), int(destination[1]))] = identity
	var operators := {}
	var travel_patients := {}
	var guards := {}
	if not state.get("captivity", {}) is Dictionary: return Runtime.fail("CORRUPT_SAVE", "原看守職務格式")
	for relation: Variant in state.get("captivity", {}).values():
		if not relation is Dictionary or not _integer(relation.get("guard_id"), 1, 2147483647): return Runtime.fail("CORRUPT_SAVE", "原看守職務引用")
		if str(relation.get("prison_id", "")).is_empty():
			guards[int(relation.guard_id)] = true
	for identity: Variant in vehicles:
		var vehicle: Variant = vehicles[identity]
		if vehicle is Dictionary and str(vehicle.get("kind", "")) == "ship":
			var ship_validation := _validate_ship_vehicle(data, state, identity, vehicle, people, team_counts, claims, operators, guards, check_terrain)
			if not ship_validation.ok: return ship_validation
			continue # Ships do not consume the original cart/team quota.
		if vehicle is Dictionary and Runtime.SIEGE_DEFINITIONS.has(str(vehicle.get("kind", ""))):
			var siege_validation := _validate_siege_vehicle(data, state, identity, vehicle, people, team_counts, claims, operators, guards, check_terrain, region_context)
			if not siege_validation.ok: return siege_validation
			continue # Siege assets preserve the existing personnel/cart quota.
		if not _serial(identity, int(state.get("next_vehicle", 1))) or not vehicle is Dictionary or vehicle.size() != 10 + int(vehicle.has("travel_patients")) + _fs_vehicle_optional_count(vehicle) or vehicle.get("id") != identity or not vehicle.get("kind") is String or not Vehicles.CAPACITY.has(vehicle.kind):
			return Runtime.fail("CORRUPT_SAVE", "車輛種類／身分")
		if not _integer(vehicle.get("team_id"), 0, 999999) or not _integer(vehicle.get("operator_id"), 0, 2147483647) or not _valid_cell(data, vehicle.get("cell")) or not vehicle.get("stop_pending") is bool or not vehicle.get("move") is Dictionary:
			return Runtime.fail("CORRUPT_SAVE", "車輛所屬／操作人／格位")
		if not _vehicle_facing(vehicle.get("facing")): return Runtime.fail("CORRUPT_SAVE", "車輛方向")
		var team_id := int(vehicle.team_id)
		var operator_id := int(vehicle.operator_id)
		if team_id > 0:
			if not team_counts.has(team_id): return Runtime.fail("CORRUPT_SAVE", "車輛所屬隊伍不存在")
			team_counts[team_id] = int(team_counts[team_id]) + 1
			total += 1
			if int(team_counts[team_id]) > 100: return Runtime.fail("CORRUPT_SAVE", "車隊人物與車輛超過100名額")
		elif operator_id > 0 or not vehicle.move.is_empty(): return Runtime.fail("CORRUPT_SAVE", "停泊無所屬車輛不能自行移動")
		var patient_validation := _validate_travel_patients(vehicle, people, travel_patients)
		if not patient_validation.ok: return patient_validation
		var occupied := {}
		for cell: Vector2i in Vehicles.footprint(data, vehicle): occupied[cell] = true
		var body := {}
		if operator_id > 0:
			if operators.has(operator_id) or guards.has(operator_id) or not people.has(operator_id) or int(people[operator_id].team) != team_id:
				return Runtime.fail("CORRUPT_SAVE", "操作人重複或不屬於原隊")
			operators[operator_id] = true
			body = people[operator_id].body
			# Runtime holder projections require boundary-normalized integer versions.
			# This exact check runs on save and again after load normalization/terrain rebuild.
			if check_terrain and str(vehicle.kind) == "wagon" and not RiderAtlas.supports(Runtime.equipment_appearance(data, body.get("item_state", {}), body.get("appearance", {}), state)):
				return Runtime.fail("MISSING_ASSET", "原馬車騎手資料或固定布裝騎姿素材未就緒")
			var cell := Vector2i(int(body.cell[0]), int(body.cell[1]))
			var direction := Vector2i(int(vehicle.facing[0]), int(vehicle.facing[1]))
			if not bool(vehicle.move.get("boarding", false)) and data.cell_from_index(int(vehicle.cell)) != Vehicles.anchor_from_operator(str(vehicle.kind), cell, direction): return Runtime.fail("CORRUPT_SAVE", "人車相對格位失效")
			var moving := Vector2i(int(body.destination[0]), int(body.destination[1])) != TerrainArmy.INVALID_CELL
			if moving == vehicle.move.is_empty(): return Runtime.fail("CORRUPT_SAVE", "原人物與車輛必須共用同一步預約")
			var incapable := float(body.hp) <= 0.0 or float(body.ko) > 0.0 or str(body.pose) == "get_up" or bool(body.captive) or bool(body.departed) or bool(body.get("site_exited", false)) or bool(body.get("surrender_pending", false)) or not bool(body.get("member", true))
			var resting_rider: bool = str(vehicle.kind) == "wagon" and float(body.hp) > 0.0 and (float(body.ko) > 0.0 or str(body.pose) == "get_up" or bool(body.get("surrender_pending", false)) or bool(body.captive)) and not bool(body.departed) and not bool(body.get("site_exited", false)) and bool(body.get("member", true)) and vehicle.move.is_empty() and bool(vehicle.stop_pending)
			if incapable and (vehicle.move.is_empty() or not bool(vehicle.stop_pending)) and not resting_rider: return Runtime.fail("CORRUPT_SAVE", "失能操作人不能開始新車步")
			if vehicle.move.is_empty() and bool(vehicle.stop_pending) and not resting_rider: return Runtime.fail("CORRUPT_SAVE", "停止旗標僅限在途步進或原馬背失能／待俘者")
			if not body.get("work_task", {}).is_empty(): return Runtime.fail("CORRUPT_SAVE", "操作人不能兼任工作")
		elif not vehicle.move.is_empty() or bool(vehicle.stop_pending): return Runtime.fail("CORRUPT_SAVE", "無真人操作卻有車步")
		if not vehicle.move.is_empty():
			var move: Dictionary = vehicle.move
			var boarding := bool(move.get("boarding", false))
			var dismount := bool(move.get("dismount", false))
			if move.size() != 5 + int(boarding) + int(dismount) or boarding and dismount or not move.get("boarding", false) is bool or not move.get("dismount", false) is bool or not _valid_cell(data, move.get("cell")) or not _valid_cell(data, move.get("operator_from")) or not _valid_cell(data, move.get("operator_to")) or not _vehicle_facing(move.get("facing")) or not move.get("sweep") is Array:
				return Runtime.fail("CORRUPT_SAVE", "人車預約欄位")
			var from := data.cell_from_index(int(move.operator_from))
			var to := data.cell_from_index(int(move.operator_to))
			var direction := Vector2i(int(move.facing[0]), int(move.facing[1]))
			var previous_direction := Vector2i(int(vehicle.facing[0]), int(vehicle.facing[1]))
			var expected_direction := previous_direction if to - from == -previous_direction else to - from
			if from != Vector2i(int(body.cell[0]), int(body.cell[1])) or to != Vector2i(int(body.destination[0]), int(body.destination[1])) or absi(to.x - from.x) + absi(to.y - from.y) != 1:
				return Runtime.fail("CORRUPT_SAVE", "車步未引用原人物預約")
			if boarding or dismount:
				var horse_cell := data.cell_from_index(int(vehicle.cell)) + previous_direction * 2
				if str(vehicle.kind) != "wagon" or int(move.cell) != int(vehicle.cell) or direction != previous_direction or boarding and to != horse_cell or dismount and (from != horse_cell or Vehicles.footprint(data, vehicle).has(to) or not bool(vehicle.stop_pending)):
					return Runtime.fail("CORRUPT_SAVE", "上下馬必须引用原馬格與真人一步，車體保持停止")
			elif direction != expected_direction or data.cell_from_index(int(move.cell)) != Vehicles.anchor_from_operator(str(vehicle.kind), to, direction):
				return Runtime.fail("CORRUPT_SAVE", "原騎乘／推車位置不符")
			var minimum := from
			var maximum := from
			for cell: Vector2i in Vehicles.footprint(data, vehicle) + Vehicles.footprint(data, vehicle, true) + [to]:
				minimum = Vector2i(mini(minimum.x, cell.x), mini(minimum.y, cell.y))
				maximum = Vector2i(maxi(maximum.x, cell.x), maxi(maximum.y, cell.y))
			var expected := {}
			for y in range(minimum.y, maximum.y + 1):
				for x in range(minimum.x, maximum.x + 1): expected[data.index(Vector2i(x, y))] = true
			var actual := {}
			for value: Variant in move.sweep:
				if not _valid_cell(data, value) or actual.has(int(value)): return Runtime.fail("CORRUPT_SAVE", "車輛掃掠預約重複／越界")
				actual[int(value)] = true
				occupied[data.cell_from_index(int(value))] = true
			if expected != actual: return Runtime.fail("CORRUPT_SAVE", "車輛轉彎掃掠預約不完整")
		for cell: Vector2i in occupied:
			if not data.contains(cell) or check_terrain and not data.is_walkable(cell) or claims.has(cell) and claims[cell] != operator_id:
				return Runtime.fail("CORRUPT_SAVE", "車輛與人物／車輛占格預約衝突")
			if check_terrain:
				for direction: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
					if occupied.has(cell + direction) and not data.can_step(cell, cell + direction): return Runtime.fail("CORRUPT_SAVE", "車輛跨越非法地勢")
			claims[cell] = "vehicle:" + str(identity)
	if total > MAX_ARMY_ROWS: return Runtime.fail("CORRUPT_SAVE", "軍隊人物與車輛合計超過%d名額" % MAX_ARMY_ROWS)
	return Runtime.ok()

static func _siege_saved_person(state: Dictionary, people: Dictionary, identity: int) -> Dictionary:
	var original: Dictionary = people.get(identity, {})
	if original.is_empty() or original.has("snapshot"): return original
	if not state.has("crowd"): return {} # GD Actor is not an original land-vehicle operator.
	# Only siege crew consume this view. The original Actor dictionary remains
	# its body authority; generic vehicle/ship admission still sees team 0.
	var actor_count := 0
	for actor: Dictionary in state.get("actors", {}).values():
		if _integer(actor.get("person_id"), identity, identity): actor_count += 1
	if actor_count != 1: return {}
	var membership := {}
	for roster: Dictionary in state.get("armies", []):
		for row: Dictionary in roster.get("units", []):
			if _integer(row.get("person_id"), identity, identity): return {}
		var member: Variant = roster.get("player_member", {})
		if not member is Dictionary or not _integer(member.get("id"), identity, identity): continue
		if not membership.is_empty() or not _integer(roster.get("team_id"), 1, 999999): return {}
		membership = roster
	if membership.is_empty(): return {}
	if state.has("crowd"):
		# _validate_crowd already checks these IDs against the original World.
		# A changed player_member must not borrow another native team's Actor.
		var native_member := false
		for team: Dictionary in state.crowd.teams:
			if not bool(team.solo) and int(team.team_id) == int(membership.team_id) and (team.person_ids.has(identity) or team.person_ids.has(float(identity))): native_member = true
		if not native_member: return {}
	return {"team": int(membership.team_id), "body": original.body, "snapshot": membership, "actor": true}

static func _validate_siege_vehicle(data: TerrainData, state: Dictionary, identity: Variant, vehicle: Dictionary, people: Dictionary, team_counts: Dictionary, claims: Dictionary, operators: Dictionary, guards: Dictionary, check_terrain: bool, region_context: Dictionary = {}) -> Dictionary:
	var yard_view := Env.navigation_for_state(data, state)
	var yard_source := Runtime.validate_technology_yard_vehicle(yard_view, vehicle)
	if not yard_source.ok: return yard_source
	var hot := not region_context.is_empty()
	const FIELDS := ["id", "kind", "team_id", "cell", "facing", "operator_id", "holder", "cargo", "move", "stop_pending", "vehicle_version", "definition_version", "hp", "ever_hp_damaged", "phase", "crew_slots", "build", "repair", "command", "action", "next_attack_seq", "rng_state"]
	var tower := str(vehicle.get("kind", "")) == "siege_tower"
	var current := _integer(vehicle.get("vehicle_version"), 3, 3)
	var legacy := _integer(vehicle.get("vehicle_version"), 2, 2)
	if not current and not legacy: return Runtime.fail("CORRUPT_SAVE", "攻城器具版本")
	if vehicle.size() != FIELDS.size() + int(tower) + int(current) + _fs_vehicle_optional_count(vehicle) or tower and not vehicle.has("deployed_pose") or not _serial(identity, int(state.get("next_vehicle", 1))) or vehicle.get("id") != identity: return Runtime.fail("CORRUPT_SAVE", "攻城器具身分／欄位")
	if current and (not vehicle.has("technology_capture") or not Runtime.technology_capture_valid(vehicle.technology_capture)): return Runtime.fail("CORRUPT_SAVE", "攻城繳獲來源")
	if legacy and vehicle.has("technology_capture"): return Runtime.fail("CORRUPT_SAVE", "舊版不能夾帶來源")
	for field: String in FIELDS:
		if not vehicle.has(field): return Runtime.fail("CORRUPT_SAVE", "攻城器具缺少 " + field)
	var definition: Dictionary = Runtime.SIEGE_DEFINITIONS.get(str(vehicle.get("kind", "")), {})
	if definition.is_empty(): return Runtime.fail("CORRUPT_SAVE", "未知攻城器具種類")
	if not _integer(vehicle.vehicle_version, 2, 3) or not _integer(vehicle.definition_version, 1, 1) or not _number(vehicle.hp, 0, float(definition.max_hp)) or not vehicle.ever_hp_damaged is bool or float(vehicle.hp) < float(definition.max_hp) and not bool(vehicle.ever_hp_damaged): return Runtime.fail("CORRUPT_SAVE", "攻城器具版本／耐久歷史")
	if not _integer(vehicle.team_id, 0, 999999) or int(vehicle.team_id) > 0 and not team_counts.has(int(vehicle.team_id)) or not _integer(vehicle.operator_id, 0, 2147483647) or not _valid_cell(data, vehicle.cell) or not _vehicle_facing(vehicle.facing): return Runtime.fail("CORRUPT_SAVE", "攻城器具所屬／位姿")
	if not _integer(vehicle.next_attack_seq, 1, 2147483647) or not _integer(vehicle.rng_state, 0, 2147483647): return Runtime.fail("CORRUPT_SAVE", "攻城攻擊序號／隨機狀態")
	for field: String in ["move", "action", "crew_slots", "build", "repair", "command", "cargo", "holder"]:
		if not vehicle[field] is Dictionary: return Runtime.fail("CORRUPT_SAVE", "攻城器具 " + field)
	if not vehicle.stop_pending is bool or not vehicle.phase is String or (not _region_siege_transient(data, state, vehicle, people, region_context) if hot else (vehicle.stop_pending or not vehicle.move.is_empty() or not vehicle.action.is_empty() or str(vehicle.phase) not in ["building", "idle", "ready", "disabled", "wrecked", "deployed"])) or str(vehicle.phase) == "deployed" and not tower: return Runtime.fail("CORRUPT_SAVE", "攻城作業尚未收束")
	var phase := str(vehicle.phase)
	if (float(vehicle.hp) == 0.0) != (phase == "wrecked") and not (hot and float(vehicle.hp) == 0.0 and str(vehicle.action.get("stage", "")) in ["rotate", "collision", "recovering"]): return Runtime.fail("CORRUPT_SAVE", "攻城殘骸與耐久矛盾")
	if vehicle.crew_slots.size() > int(definition.standard_crew) or int(vehicle.operator_id) != int(vehicle.crew_slots.get("0", 0)): return Runtime.fail("CORRUPT_SAVE", "攻城主槽／角色關係")
	if phase in ["building", "wrecked"] and (not vehicle.crew_slots.is_empty() or not vehicle.command.is_empty()) and not (hot and phase == "wrecked" and vehicle.command.get("type") == "release"): return Runtime.fail("CORRUPT_SAVE", "工地／殘骸不能帶操作班或攻擊命令")
	if phase == "wrecked" and (not vehicle.build.is_empty() or not vehicle.repair.is_empty()): return Runtime.fail("CORRUPT_SAVE", "殘骸不能繼續建造／修理")
	if phase == "building":
		if not _valid_siege_job(vehicle.build, definition.cost, float(definition.work_seconds), false, 140.0, hot and _region_due_work(region_context, str(identity))): return Runtime.fail("CORRUPT_SAVE", "攻城施工投入／進度")
		if not vehicle.repair.is_empty(): return Runtime.fail("CORRUPT_SAVE", "工地不能兼任修理")
	elif not vehicle.build.is_empty(): return Runtime.fail("CORRUPT_SAVE", "完工器具仍帶施工交易")
	if not vehicle.repair.is_empty():
		if phase not in ["idle", "disabled"] or not vehicle.crew_slots.is_empty() or vehicle.command.get("type") == "attack" or not _number(vehicle.repair.get("amount"), 0.000001, float(definition.max_hp)): return Runtime.fail("CORRUPT_SAVE", "攻城修理資格／額度")
		if vehicle.has("technology_spare_repair") and not Runtime.valid_settlement_spare_repair_storage(data, vehicle, {}, state): return Runtime.fail("CORRUPT_SAVE", "原備件修理格式")
		var terms := Runtime.settlement_spare_repair_terms(float(vehicle.repair.amount)) if vehicle.has("technology_spare_repair") else Runtime.siege_repair_terms(vehicle, float(vehicle.repair.amount))
		if not _valid_siege_job(vehicle.repair, terms.paid_cost, float(terms.total_work), true, float(definition.max_hp), hot and _region_due_work(region_context, str(identity))): return Runtime.fail("CORRUPT_SAVE", "攻城修理投入／進度")
	if not (_region_siege_command(data, state, vehicle.command, people) if hot else _valid_siege_command(data, state, vehicle.command, people)): return Runtime.fail("CORRUPT_SAVE", "攻城命令／目標引用")
	if Runtime.inventory_size(vehicle.cargo) > int(definition.capacity): return Runtime.fail("CORRUPT_SAVE", "原石彈與火罐合計超過同一彈艙容量")
	if vehicle.command.get("ammo") == "fire_pot" and (not Runtime.siege_ammo_valid(str(vehicle.kind), "fire_pot") or not vehicle.crew_slots.values().has(int(vehicle.command.operator_id)) or vehicle.command.has("tech_trial") and vehicle.command.tech_trial.target_id != "vehicle:" + str(vehicle.id)): return Runtime.fail("CORRUPT_SAVE", "火罐命令必須綁同一原投石機與原操作班本人")
	if tower and vehicle.command.get("type") == "attack": return Runtime.fail("CORRUPT_SAVE", "攻城塔無攻擊命令")
	for resource: Variant in vehicle.cargo:
		if not Runtime.siege_ammo_valid(str(vehicle.kind), str(resource)) or not _integer(vehicle.cargo[resource], 0, int(definition.capacity)): return Runtime.fail("CORRUPT_SAVE", "攻城器具僅接受定義內的原實物彈藥")
	var footprint: Array[Vector2i] = Runtime.siege_cells(data, vehicle)
	if footprint.size() != int(definition.size.x) * int(definition.size.y): return Runtime.fail("CORRUPT_SAVE", "攻城占地")
	if check_terrain:
		var foundation: Array[Vector2i] = footprint.duplicate()
		if phase == "building" or not vehicle.repair.is_empty():
			var stations := Runtime.siege_work_slots(yard_view, vehicle)
			if stations.size() not in [4, 6]: return Runtime.fail("CORRUPT_SAVE", "攻城工位越界")
			for station: Dictionary in stations: foundation.append(data.cell_from_index(int(station.cell)))
		var base: int = int(data.height_levels[data.index(footprint[0])]) if tower else data.effective_height(footprint[0])
		for cell: Vector2i in foundation:
			if not data.contains(cell) or not data.is_walkable(cell) or int(data.height_levels[data.index(cell)]) != base or not tower and data.effective_height(cell) != base or int(data.surface_types[data.index(cell)]) in [TerrainData.Surface.WATER, TerrainData.Surface.WETLAND] or not Runtime.technology_siege_ground_cell_allowed(yard_view, vehicle, cell): return Runtime.fail("CORRUPT_SAVE", "攻城地基／工位非合法平整乾燥地面或原校場")
	var physical := Runtime.siege_tower_physical_cells(data, vehicle) if tower else footprint
	for cell: Vector2i in physical:
		if not data.contains(cell) or claims.has(cell) and not _siege_tower_person_claim(data, vehicle, cell, claims[cell], people) and not (hot and _region_siege_claim(data, vehicle, cell, claims[cell])) or check_terrain and not data.is_walkable(cell): return Runtime.fail("CORRUPT_SAVE", "攻城器具與原人物／車輛／地形重疊")
		if check_terrain:
			for adjacent: Vector2i in footprint:
				if absi(cell.x - adjacent.x) + absi(cell.y - adjacent.y) == 1 and not data.can_step(cell, adjacent): return Runtime.fail("CORRUPT_SAVE", "攻城器具地基不平整")
		claims[cell] = "vehicle:" + str(identity)
	var tower_people := _validate_siege_tower_people(data, vehicle, people)
	if not tower_people.ok: return tower_people
	for slot: Variant in vehicle.crew_slots:
		var person_id: Variant = vehicle.crew_slots[slot]
		var person := _siege_saved_person(state, people, int(person_id)) if _integer(person_id, 1, 2147483647) else {}
		if not slot is String or not slot.is_valid_int() or str(int(slot)) != slot or int(slot) < 0 or int(slot) >= int(definition.standard_crew) or not _integer(person_id, 1, 2147483647) or operators.has(int(person_id)) or guards.has(int(person_id)) or person.is_empty() or int(person.team) != int(vehicle.team_id) or int(vehicle.team_id) == 0: return Runtime.fail("CORRUPT_SAVE", "攻城操作人重複／所屬非法")
		var body: Dictionary = person.body
		var destination: Variant = body.get("destination", [-1, -1])
		# Semantic validation precedes boundary normalization on JSON load.
		var stopped: bool = destination is Array and destination.size() == 2 and _integer(destination[0], -1, -1) and _integer(destination[1], -1, -1)
		if not hot and bool(person.get("actor", false)):
			if float(body.get("hp", 0.0)) <= 0.0 or not _number(body.get("knockout_left"), 0.0, 0.0) or bool(body.get("captive", true)) or bool(body.get("site_exited", false)) or bool(body.get("surrender_pending", false)) or bool(body.get("_getting_up", false)) or str(body.get("pose", "")) != "idle" or not _number(body.get("action_time"), 0.0, 0.0) or not _number(body.get("_rescue_left"), 0.0, 0.0) or bool(body.get("guarding", true)) or not body.get("work_task", {}).is_empty() or not _number(body.get("movement_left"), 0.0, 0.0) or not stopped: return Runtime.fail("CORRUPT_SAVE", "攻城操作人失能／兼任／在途")
		elif not hot and (float(body.hp) <= 0.0 or float(body.ko) > 0.0 or bool(body.captive) or bool(body.departed) or bool(body.get("site_exited", false)) or not bool(body.get("member", true)) or bool(body.get("surrender_pending", false)) or str(body.pose) != "idle" or bool(body.get("attack", false)) or not body.get("work_task", {}).is_empty() or not stopped): return Runtime.fail("CORRUPT_SAVE", "攻城操作人失能／兼任／在途")
		var team: Dictionary = person.snapshot
		var deployment: Variant = team.get("combat_deployment_plan", null)
		if deployment is Dictionary and (deployment.get("member_slot_map", {}).has(str(int(person_id))) or deployment.get("slot_lease_owner_map", {}).values().has(int(person_id))): return Runtime.fail("CORRUPT_SAVE", "攻城操作人仍占一般隊形槽位／租約")
		var cell := Vector2i(int(body.cell[0]), int(body.cell[1]))
		if footprint.has(cell) or check_terrain and not data.is_walkable(cell): return Runtime.fail("CORRUPT_SAVE", "攻城操作人非法工位")
		if phase == "ready" and not hot:
			var expected := Runtime.siege_crew_cell(data, vehicle, slot)
			if cell != expected: return Runtime.fail("CORRUPT_SAVE", "就緒攻城操作人尚未到原工位")
			var station_base := int(data.height_levels[int(vehicle.cell)]) if tower else data.effective_height(data.cell_from_index(int(vehicle.cell)))
			if check_terrain and (data.effective_height(cell) != station_base or data.effective_height(cell) != int(data.height_levels[data.index(cell)]) or not Runtime.technology_siege_ground_cell_allowed(yard_view, vehicle, cell) or int(data.surface_types[data.index(cell)]) in [TerrainData.Surface.WATER, TerrainData.Surface.WETLAND]): return Runtime.fail("CORRUPT_SAVE", "就緒攻城操作人須在同高原地面工位")
		operators[int(person_id)] = true
	if phase == "ready" and vehicle.crew_slots.size() < int(definition.min_crew): return Runtime.fail("CORRUPT_SAVE", "攻城就緒卻沒有最低操作班")
	return Runtime.ok()


static func _valid_siege_job(job: Dictionary, cost: Dictionary, work: float, repair: bool, max_hp: float = 140.0, due: bool = false) -> bool:
	if job.size() != (5 if repair else 3) or not job.get("paid_cost") is Dictionary or not _number(job.get("total_work"), 0.000001, 1000000.0) or not is_equal_approx(float(job.total_work), work) or not _number(job.get("progress"), 0, work) or float(job.progress) >= work and not due or job.paid_cost.size() != cost.size(): return false
	for resource: String in cost:
		if not _integer(job.paid_cost.get(resource), int(cost[resource]), int(cost[resource])): return false
	if repair and (not _number(job.get("amount"), 0.000001, max_hp) or not _number(job.get("applied"), 0, float(job.amount)) or not is_equal_approx(float(job.applied), float(job.amount) * float(job.progress) / work)): return false
	return true

static func _valid_siege_command(data: TerrainData, state: Dictionary, command: Dictionary, people: Dictionary) -> bool:
	if command.is_empty(): return true
	if command.get("type") == "stop": return command.size() == 2 and command.get("reason") is String and str(command.reason).length() <= 512
	if command.size() != 2 + int(command.has("ai")) + 2 * int(command.has("ammo")) + int(command.has("tech_trial")) or command.get("type") != "attack" or not command.get("target") is Dictionary or not command.get("ai", false) is bool: return false
	if command.has("ammo") and (command.ammo != "fire_pot" or not _integer(command.get("operator_id"), 1, 2147483647) or not people.has(int(command.operator_id))): return false
	if command.has("tech_trial") and (not command.has("ammo") or not Runtime._technology_trial_shape(command.tech_trial, data) or command.tech_trial.get("tech_id") != "F15" or command.tech_trial.get("binding") != "fire_pot_shot" or int(command.tech_trial.person.person_id) != int(command.operator_id)): return false
	var target: Dictionary = command.target
	match str(target.get("type", "")):
		"ground": return target.size() == 2 and _valid_xy_pair(data, target.get("cell")) and data.contains(Vector2i(int(target.cell[0]), int(target.cell[1])))
		"person": return target.size() == 2 and _integer(target.get("person_id"), 1, 2147483647) and people.has(int(target.person_id))
		"vehicle": return target.size() == 2 and target.get("vehicle_id") is String and state.get("vehicles", {}).has(target.vehicle_id)
		"structure":
			if target.size() != 3 or not target.get("feature_id") is String or not target.get("part_id") is String: return false
			var feature: Dictionary = state.features.get(target.feature_id, {})
			return str(feature.get("stage", "")) == "complete" and feature.get("parts", {}).has(target.part_id)
	return false


static func _vehicle_facing(value: Variant) -> bool:
	return value is Array and value.size() == 2 and _integer(value[0], -1, 1) and _integer(value[1], -1, 1) and absi(int(value[0])) + absi(int(value[1])) == 1

static func _valid_cells(data: TerrainData, value: Variant, maximum: int) -> bool:
	if not value is Array or value.is_empty() or value.size() > maximum:
		return false
	var seen := {}
	for cell: Variant in value:
		if not _valid_cell(data, cell) or seen.has(int(cell)):
			return false
		seen[int(cell)] = true
	return true

static func _saved_supply_locations(data: TerrainData, state: Dictionary, team_id: int, locations: Variant) -> bool:
	if data == null or not locations is Dictionary: return false
	for key: Variant in locations:
		if not Sustain._valid_location_key(key) or not locations[key] is Dictionary: return false
		var location: Dictionary = locations[key]
		if location.size() != 2 or not _saved_resource_stack(location.get("inventory")) or not _number(location.get("open_rations"), 0, 1000000.0): return false
		for resource: String in location.inventory:
			if resource not in Sustain.FOODS: return false
		if str(key).begins_with("shore:"):
			var index := int(str(key).trim_prefix("shore:"))
			if not _valid_cell(data, index) or not data.is_walkable(data.cell_from_index(index)): return false
		else:
			var vehicle: Variant = state.get("vehicles", {}).get(str(key).trim_prefix("vehicle:"))
			if not vehicle is Dictionary or not Vehicles.is_ship(vehicle) or int(vehicle.get("team_id", -1)) != team_id: return false
	return true

static func _validate_supply(state: Dictionary, data: TerrainData = null, region_context: Dictionary = {}) -> Dictionary:
	var supplies: Variant = state.get("team_supply", {})
	var personal: Variant = state.get("person_supply", {})
	if not supplies is Dictionary or not personal is Dictionary:
		return Runtime.fail("CORRUPT_SAVE", "隊伍供養資料")
	if supplies.is_empty() and personal.is_empty():
		return Runtime.ok() # Legacy snapshots have no institutional state to regenerate.
	if not _integer(state.get("minute"), 0, 1000000000) or not _number(state.get("phase"), 0, 0.999999999):
		return Runtime.fail("CORRUPT_SAVE", "供養時鐘")
	var site_seconds := (float(state.minute) + float(state.phase)) * 60.0
	var members := {}
	var teams := {}
	if not state.get("actors", {}) is Dictionary or not state.get("armies", []) is Array:
		return Runtime.fail("CORRUPT_SAVE", "供養人物名冊")
	for actor: Variant in state.get("actors", {}).values():
		if not actor is Dictionary or not _integer(actor.get("person_id"), 1, 2147483647):
			return Runtime.fail("CORRUPT_SAVE", "供養人物引用")
		members[int(actor.person_id)] = actor
	for original_team: Variant in state.get("armies", []):
		if not original_team is Dictionary:
			return Runtime.fail("CORRUPT_SAVE", "供養隊伍引用")
		var team: Dictionary = original_team if original_team.get("crowd") == true else TerrainArmy.normalize_roster_snapshot(original_team)
		if not team.get("units") is Array or not _integer(team.get("team_id"), 1, 999999):
			return Runtime.fail("CORRUPT_SAVE", "供養隊伍引用")
		teams[int(team.team_id)] = team
		for unit: Variant in team.units:
			if not unit is Dictionary or not _integer(unit.get("person_id"), 1, 2147483647):
				return Runtime.fail("CORRUPT_SAVE", "供養軍隊人物引用")
			members[int(unit.person_id)] = unit
	var feeding: Array = []
	var maximum_supply_team := 0
	for key: Variant in supplies:
		var supply: Variant = supplies[key]
		if not _serial(key, 1000000) or not supply is Dictionary or not _integer(supply.get("version"), 1, 3):
			return Runtime.fail("CORRUPT_SAVE", "隊伍供養版本／身分")
		var modern_training: bool = int(supply.version) >= 2
		var positional: bool = int(supply.version) == 3
		if supply.size() != (9 if modern_training else 8) or (modern_training and not supply.get("training_feature_id") is String):
			return Runtime.fail("CORRUPT_SAVE", "隊伍供養欄位／校場引用")
		maximum_supply_team = maxi(maximum_supply_team, int(key))
		if not supply.get("sustain") is Dictionary or not Sustain.validate(supply.sustain, members):
			return Runtime.fail("CORRUPT_SAVE", "供餐／缺糧／士氣歷史")
		if supply.sustain.version != (2 if positional else 1) or positional and supply.has("inventory") or not positional and supply.has("locations"):
			return Runtime.fail("CORRUPT_SAVE", "共糧格式不可雙份或混用舊開封量")
		if float(supply.sustain.at) > site_seconds + 0.00001:
			return Runtime.fail("CORRUPT_SAVE", "供養時鐘超前 Site")
		if not supply.sustain.cohorts.is_empty() and float(supply.sustain.at) < site_seconds - 0.00001:
			return Runtime.fail("CORRUPT_SAVE", "有成員的供養時鐘落後 Site，不能跳過缺糧或餐份時段")
		if not (_saved_supply_locations(data, state, int(key), supply.get("locations")) if positional else _saved_resource_stack(supply.get("inventory"))) or not supply.get("training_order") is bool or not _integer(supply.get("training_requester"), -1, 2147483647) or not _integer(supply.get("revision"), 0, 2147483647):
			return Runtime.fail("CORRUPT_SAVE", "隊伍庫存／訓練指令")
		for resource: String in supply.get("inventory", {}):
			if resource not in Sustain.FOODS:
				return Runtime.fail("CORRUPT_SAVE", "隊伍口糧含非食物")
		if not supply.get("delivery") is Dictionary or not supply.get("life_checkpoint") is Dictionary:
			return Runtime.fail("CORRUPT_SAVE", "隊伍交付／生死事件")
		if not supply.delivery.is_empty() and not region_context.is_empty():
			if not _valid_region_delivery(supply.delivery, members): return Runtime.fail("CORRUPT_REGION_DELIVERY")
		elif not supply.delivery.is_empty():
			return Runtime.fail("BUSY", "口糧交付尚未完成；物資仍在原處，本版等動作結束後保存")
		var supplied := {}
		for cohort: Dictionary in supply.sustain.cohorts:
			for identity: Variant in cohort.ids:
				supplied[str(int(identity))] = true
		if supply.life_checkpoint.size() != supplied.size():
			return Runtime.fail("CORRUPT_SAVE", "供養生死事件名單不符")
		for identity: Variant in supply.life_checkpoint:
			if not identity is String or not supplied.has(identity) or not _integer(supply.life_checkpoint[identity], 0, 2):
				return Runtime.fail("CORRUPT_SAVE", "供養生死事件引用")
		if not teams.has(int(key)) and not supplied.is_empty():
			return Runtime.fail("CORRUPT_SAVE", "已移除隊伍仍供養人物")
		if positional and bool(teams.get(int(key), {}).get("crowd", false)):
			return Runtime.fail("CORRUPT_SAVE", "首版位置供養只支援原 GDScript 隊伍")
		if bool(supply.training_order):
			if not supplied.has(str(int(supply.training_requester))):
				return Runtime.fail("CORRUPT_SAVE", "訓練下令人已不在供養名冊")
			if modern_training:
				var training_id := str(supply.training_feature_id)
				var feature: Dictionary = state.get("features", {}).get(training_id, {})
				var team: Dictionary = teams.get(int(key), {})
				if training_id.is_empty() or team.is_empty() or not str(team.get("garrison_feature_id", "")).is_empty() \
					or not Runtime.is_training_facility(feature) or str(feature.get("stage", "")) != "complete" \
					or int(feature.get("layout_version", 0)) != Runtime.BUILDING_LAYOUT_VERSION or int(feature.get("owner_faction", -1)) != int(team.faction_id):
					return Runtime.fail("CORRUPT_SAVE", "訓練命令須引用原編成軍隊同方已完工校場或西式軍營")
		elif int(supply.training_requester) != -1:
			return Runtime.fail("CORRUPT_SAVE", "無訓練命令卻保留下令人")
		elif modern_training and not str(supply.training_feature_id).is_empty():
			return Runtime.fail("CORRUPT_SAVE", "無訓練命令卻保留校場引用")
		feeding.append(supply.sustain)
	if not supplies.is_empty() and not _integer(state.get("army_next_team"), maximum_supply_team + 1, 999999):
		return Runtime.fail("CORRUPT_SAVE", "供糧庫存的原隊伍身分不可重新使用")
	for key: Variant in personal:
		var sustain: Variant = personal[key]
		if not _serial(key, 2147483648) or not members.has(int(key)) or not sustain is Dictionary or sustain.get("version") != 1 or not Sustain.validate(sustain, members):
			return Runtime.fail("CORRUPT_SAVE", "私人供養必須引用原人物及有效餐份歷史")
		if float(sustain.at) > site_seconds + 0.00001:
			return Runtime.fail("CORRUPT_SAVE", "私人供養時鐘超前 Site")
		if not sustain.cohorts.is_empty() and float(sustain.at) < site_seconds - 0.00001:
			return Runtime.fail("CORRUPT_SAVE", "有成員的私人供養時鐘落後 Site，不能跳過缺糧或餐份時段")
		for cohort: Dictionary in sustain.cohorts:
			for identity: Variant in cohort.ids:
				if int(identity) != int(key):
					var relation: Dictionary = state.get("captivity", {}).get(str(int(identity)), {})
					if float(members[int(identity)].hp) > 0.0 and int(relation.get("captor_id", -1)) != int(key):
						return Runtime.fail("CORRUPT_SAVE", "私人餐份只能供養本人及實際由本人拘押的原俘虜")
		feeding.append(sustain)
	if not Sustain.validate_owners(feeding, members):
		return Runtime.fail("CORRUPT_SAVE", "同一人物有重複供養來源")
	return Runtime.ok()

static func _validate_crowd_formation_references(state: Dictionary) -> Dictionary:
	var records := {}
	var formations: Array[Dictionary] = []
	for actor: Dictionary in state.get("actors", {}).values():
		var identity := int(actor.get("person_id", -1))
		records[identity] = int(records.get(identity, 0)) + 1
		var handoff: Variant = actor.get("crowd_handoff", {})
		if handoff is Dictionary and handoff.has("solo_formation") and (state.has("crowd") or _crowd_actor_solo_current(actor, handoff)):
			formations.append({"state": handoff.solo_formation, "members": {identity: true}})
	for roster: Dictionary in state.get("armies", []):
		var members := {}
		for person: Dictionary in roster.get("units", []):
			var identity := int(person.get("person_id", -1))
			records[identity] = int(records.get(identity, 0)) + 1
			members[identity] = true
		var player_member: Variant = roster.get("player_member", {})
		if player_member is Dictionary and _integer(player_member.get("id"), 1, 2147483647):
			# The actor already contributes one original record above; membership is not a copy.
			members[int(player_member.id)] = true
		if roster.has("crowd_state") and (state.has("crowd") or not roster.has("crowd_source_sha256") or _crowd_roster_handoff_current(roster)):
			formations.append({"state": roster.crowd_state, "members": members})
	for entry: Dictionary in formations:
		if not entry.state is Dictionary:
			return Runtime.fail("INVALID_CROWD", "群眾交接隊伍快照格式")
		var formation: Dictionary = entry.state
		for field: String in ["formal_person", "acting_person", "current_person", "target_person"]:
			if not _integer(formation.get(field), -1, 2147483647) or int(formation[field]) == 0:
				return Runtime.fail("INVALID_CROWD", "群眾交接目前人物引用格式：" + field)
			var identity := int(formation[field])
			if identity == -1: continue
			if int(records.get(identity, 0)) != 1 or (field != "target_person" and not entry.members.has(identity)):
				return Runtime.fail("INVALID_CROWD", "群眾交接目前人物引用未唯一解析：" + field)
		if not formation.get("officer_persons") is Array:
			return Runtime.fail("INVALID_CROWD", "群眾交接軍官引用格式")
		var officers := {}
		for value: Variant in formation.officer_persons:
			if not _integer(value, 1, 2147483647):
				return Runtime.fail("INVALID_CROWD", "群眾交接軍官人物編號")
			var identity := int(value)
			if officers.has(identity) or int(records.get(identity, 0)) != 1 or not entry.members.has(identity):
				return Runtime.fail("INVALID_CROWD", "群眾交接軍官未唯一解析至原隊伍")
			officers[identity] = true
	return Runtime.ok()

## Lineage counter: a Site without the key is filled on load; a present counter must lie past the family id.
static func _validate_lineage_allocator(state: Dictionary) -> Dictionary:
	if not state.has("next_lineage"): return Runtime.ok()
	if not _integer(state.next_lineage, 1, 2147483647): return Runtime.fail("CORRUPT_SAVE", "家族序號")
	var family: Variant = state.get("family", {})
	if family is Dictionary and int(family.get("version", 0)) == 4 and int(family.get("lineage_id", 0)) >= int(state.next_lineage):
		return Runtime.fail("CORRUPT_SAVE", "家族序號會重用既有家族身分")
	return Runtime.ok()

static func _validate_person_allocator(state: Dictionary) -> Dictionary:
	var lineage_validation := _validate_lineage_allocator(state)
	if not lineage_validation.ok: return lineage_validation
	var current_references := _validate_crowd_formation_references(state)
	if not current_references.ok: return current_references
	if not state.has("next_person_id"):
		return Runtime.ok() # Original-owner initialization performs the explicit legacy scan.
	if not _integer(state.next_person_id, 1, 2147483647) or int(state.next_person_id) == TerrainArmy.PLAYER_MEMBER:
		return Runtime.fail("CORRUPT_SAVE", "人物身分序號")
	var maximum := 0
	for actor: Dictionary in state.get("actors", {}).values():
		maximum = maxi(maximum, int(actor.person_id))
	for original_team: Dictionary in state.get("armies", []):
		var roster: Dictionary = original_team if original_team.get("crowd") == true else TerrainArmy.normalize_roster_snapshot(original_team)
		for unit: Variant in roster.get("units", []):
			var identity: Variant = unit.get("person_id", -1) if unit is Dictionary else -1
			maximum = maxi(maximum, int(identity))
	for record: Dictionary in state.get("item_records", {}).values():
		maximum = maxi(maximum, int(record.original_owner))
	for container: Dictionary in state.get("ground_loot", {}).values():
		maximum = maxi(maximum, int(container.original_owner))
	for relation: Dictionary in state.get("captivity", {}).values():
		maximum = maxi(maximum, maxi(int(relation.captor_id), int(relation.guard_id)))
	if int(state.next_person_id) <= maximum:
		return Runtime.fail("CORRUPT_SAVE", "人物身分序號會重用現有人物或遺留物原物主")
	return Runtime.ok()

static func _validate_items(data: TerrainData, state: Dictionary, region_context: Dictionary = {}) -> Dictionary:
	if not _integer(state.get("item_storage_version"), Runtime.ITEM_STORAGE_VERSION, Runtime.ITEM_STORAGE_VERSION):
		return Runtime.fail("CORRUPT_SAVE", "物品資料版本")
	for field: String in ["item_definitions", "item_records", "ground_loot", "depot_items"]:
		if not state.get(field) is Dictionary:
			return Runtime.fail("CORRUPT_SAVE", "物品欄位：" + field)
	for field: String in ["next_item", "next_loot"]:
		if not _integer(state.get(field), 1, 2147483647):
			return Runtime.fail("CORRUPT_SAVE", "物品序號")
	for identity: Variant in state.item_definitions:
		if not Runtime.valid_item_definition(identity, state.item_definitions[identity]):
			return Runtime.fail("CORRUPT_SAVE", "共用裝備定義")
	var kernel := TerrainArmy._get_idle_kernel()
	if kernel == null or not kernel.has_method("item_records_valid") or not kernel.item_records_valid(state.item_records, state.item_definitions, int(state.next_item), Runtime.EquipmentDye.SLOTS):
		for identity: Variant in state.item_records:
			var record: Variant = state.item_records[identity]
			if not _serial(identity, int(state.next_item)) or not record is Dictionary or record.size() != 3 + int(record.has("dye_color")):
				return Runtime.fail("CORRUPT_SAVE", "裝備身分")
			if not record.get("definition") is String or not state.item_definitions.has(record.definition) or not _integer(record.get("original_owner"), 1, 2147483647) or not record.get("holder") is String:
				return Runtime.fail("CORRUPT_SAVE", "裝備定義／物主引用")
			if record.has("dye_color") and (not Runtime.EquipmentDye.valid_color(record.dye_color) or str(state.item_definitions[record.definition].slot) not in Runtime.EquipmentDye.SLOTS):
				return Runtime.fail("CORRUPT_SAVE", "裝備染色格式／槽位")
	var stock_validation := Stockpiles.validate(state)
	if not stock_validation.ok: return stock_validation
	var checked_appearances := {}
	var locations := {}
	var result := _item_holder_validation_error(state.depot_items, "depot", state, locations, state.get("inventory", {}), int(state.get("capacity", 0)))
	if not result.is_empty():
		return Runtime.fail("CORRUPT_SAVE", result)
	for key: String in state.get("stockpiles", {}):
		var stock: Dictionary = state.stockpiles[key]
		result = _item_holder_validation_error(stock.holder, Stockpiles.identity(key), state, locations, stock.cargo, Stockpiles.capacity(state.features[key]))
		if not result.is_empty(): return Runtime.fail("CORRUPT_SAVE", result)
	if not state.get("vehicles", {}) is Dictionary:
		return Runtime.fail("CORRUPT_SAVE", "車輛持物資料")
	for identity: Variant in state.get("vehicles", {}):
		var vehicle: Variant = state.vehicles[identity]
		if not vehicle is Dictionary or not vehicle.get("kind") is String:
			return Runtime.fail("CORRUPT_SAVE", "車輛種類／持物資料")
		var capacity := 0
		if vehicle.kind == "ship":
			if not vehicle.get("ship_type") is String or not ShipDefs.is_kind(vehicle.ship_type) or not _integer(vehicle.get("ship_version"), 1, 1) or not _integer(vehicle.get("definition_version"), ShipDefs.VERSION, ShipDefs.VERSION): return Runtime.fail("SAVE_VERSION", "船艦持物的船型定義版本")
			capacity = int(ShipDefs.definition(vehicle.ship_type).capacity)
		elif Runtime.SIEGE_DEFINITIONS.has(vehicle.kind): capacity = int(Runtime.SIEGE_DEFINITIONS[vehicle.kind].capacity)
		elif Vehicles.CAPACITY.has(vehicle.kind): capacity = int(Vehicles.CAPACITY[vehicle.kind]) - int(vehicle.get("travel_patients", {}).get("reserved_capacity", 0))
		else: return Runtime.fail("CORRUPT_SAVE", "車輛種類／持物資料")
		result = _item_holder_validation_error(vehicle.get("holder"), "vehicle:" + str(identity), state, locations, vehicle.get("cargo"), capacity)
		if not result.is_empty(): return Runtime.fail("CORRUPT_SAVE", result)
		if not vehicle.holder.equipped.is_empty(): return Runtime.fail("CORRUPT_SAVE", "車輛不能穿戴裝備，所有實物均占載量")
	for identity: Variant in state.ground_loot:
		var container: Variant = state.ground_loot[identity]
		if not container is Dictionary: return Runtime.fail("CORRUPT_SAVE", "遺留物身分")
		var location_validation := _validate_ship_loot_location(data, state, identity, container)
		if not location_validation.ok: return location_validation
		if not _number(container.get("open_rations", 0.0), 0.0, 1000000.0):
			return Runtime.fail("CORRUPT_SAVE", "現場開封口糧數量")
		if container.get("kind") not in ["remains", "sealed", "cargo"] or not _integer(container.get("original_owner"), 1, 2147483647):
			return Runtime.fail("CORRUPT_SAVE", "遺留物種類／位置")
		result = _item_holder_validation_error(container, "ground:" + identity, state, locations, container.get("cargo"), 1000000)
		if not result.is_empty():
			return Runtime.fail("CORRUPT_SAVE", result)
		if float(Runtime.carried_size(container.cargo, container)) + float(container.get("open_rations", 0.0)) > 1000000.0:
			return Runtime.fail("CORRUPT_SAVE", "現場物資與開封口糧合計超量")
	var actors: Variant = state.get("actors", {})
	var armies: Variant = state.get("armies", [])
	if not actors is Dictionary or not armies is Array:
		return Runtime.fail("CORRUPT_SAVE", "物品持有人名冊")
	for key: Variant in actors:
		var actor: Variant = actors[key]
		if not actor is Dictionary:
			return Runtime.fail("CORRUPT_SAVE", "物品持有人")
		var death_validation := _remains_validation_error(actor, state, state.get("manual" if key == "player" else "worker", {}).get("cargo", {}))
		if not death_validation.is_empty():
			return Runtime.fail("CORRUPT_SAVE", death_validation)
		if not actor.has("item_state"):
			continue # Explicit legacy body migration is owned by the original person.
		var worker: Variant = state.get("manual" if key == "player" else "worker", {})
		if not worker is Dictionary or not _integer(actor.get("person_id"), 1, 2147483647):
			return Runtime.fail("CORRUPT_SAVE", "物品持有人引用")
		result = _item_holder_validation_error(actor.item_state, "person:" + str(int(actor.person_id)), state, locations, worker.get("cargo"), Runtime.CARRY_CAPACITY)
		if not result.is_empty():
			return Runtime.fail("CORRUPT_SAVE", result)
	for original_team: Variant in armies:
		if not original_team is Dictionary:
			return Runtime.fail("CORRUPT_SAVE", "軍隊物品名冊")
		var team: Dictionary = original_team if original_team.get("crowd") == true else TerrainArmy.normalize_roster_snapshot(original_team)
		if not team.get("units") is Array:
			return Runtime.fail("CORRUPT_SAVE", "軍隊物品名冊")
		for unit: Variant in team.units:
			if not unit is Dictionary:
				return Runtime.fail("CORRUPT_SAVE", "軍隊物品持有人")
			if unit.has("appearance") and not checked_appearances.has(unit.appearance):
				if not HumanCharacter3DEditor.valid_appearance(unit.appearance): return Runtime.fail("CORRUPT_SAVE", "原軍隊人物外觀")
				checked_appearances[unit.appearance] = true
			var death_validation := _remains_validation_error(unit, state, unit.get("cargo", {}))
			if not death_validation.is_empty():
				return Runtime.fail("CORRUPT_SAVE", death_validation)
			if not unit.has("item_state"):
				if unit.has("cargo") and not _saved_resource_stack(unit.cargo):
					return Runtime.fail("CORRUPT_SAVE", "軍隊隨身資源")
				continue
			if not _integer(unit.get("person_id"), 1, 2147483647):
				return Runtime.fail("CORRUPT_SAVE", "軍隊物品持有人引用")
			result = _item_holder_validation_error(unit.item_state, "person:" + str(int(unit.person_id)), state, locations, unit.get("cargo", {}), Runtime.CARRY_CAPACITY)
			if not result.is_empty():
				return Runtime.fail("CORRUPT_SAVE", result)
	if locations.size() != state.item_records.size():
		return Runtime.fail("CORRUPT_SAVE", "裝備沒有唯一實際位置")
	return _validate_captivity(data, state, region_context)

static func _validate_captivity(data: TerrainData, state: Dictionary, region_context: Dictionary = {}) -> Dictionary:
	var relations: Variant = state.get("captivity", {})
	if not relations is Dictionary or relations.size() > (MAX_CROWD_ROWS if state.has("crowd") else MAX_ARMY_ROWS) + 2:
		return Runtime.fail("CORRUPT_SAVE", "拘押關係欄位")
	var people := {}
	for actor: Dictionary in state.get("actors", {}).values():
		people[int(actor.person_id)] = actor
	for team: Dictionary in state.get("armies", []):
		var roster: Dictionary = team if team.get("crowd") == true else TerrainArmy.normalize_roster_snapshot(team)
		for unit: Dictionary in roster.units:
			people[int(unit.person_id)] = unit
	var housing_people := {}
	for actor: Dictionary in state.get("actors", {}).values():
		var projection: Dictionary = actor.duplicate()
		projection["_housing_faction"] = int(actor.faction_id)
		housing_people[int(actor.person_id)] = projection
	for team: Dictionary in state.get("armies", []):
		var roster: Dictionary = team if team.get("crowd") == true else TerrainArmy.normalize_roster_snapshot(team)
		for unit: Dictionary in roster.units:
			var projection: Dictionary = unit.duplicate()
			projection["_housing_faction"] = int(roster.faction_id)
			housing_people[int(unit.person_id)] = projection
	var housing_validation := Housing.validate(data, state, housing_people)
	if not housing_validation.ok: return housing_validation
	var settlement_validation := Settlement.validate(data, state, housing_people)
	if not settlement_validation.ok: return settlement_validation
	if not EquipmentOrders.valid_nations(state.get("equipment_nations", {}), state.item_definitions, people, state):
		return Runtime.fail("CORRUPT_SAVE", "原國別／軍事首長／正式配裝標準")
	if state.has("controlled_person_id") and (not _integer(state.controlled_person_id, 1, 2147483647) or not people.has(int(state.controlled_person_id))):
		return Runtime.fail("CORRUPT_SAVE", "受控原人物不存在")
	if state.has("family") and not FamilyContinuity.validate_family(state.family, str(state.get("id", ""))):
		return Runtime.fail("CORRUPT_SAVE", "家族原人物引用名單")
	if state.has("vacancy_episodes") and not VacancyEpisode.valid_episodes(state.vacancy_episodes): return Runtime.fail("CORRUPT_SAVE", "空缺紀錄")
	if state.has("family_departures") and not FamilyContinuity.valid_departures(state.family_departures): return Runtime.fail("CORRUPT_SAVE", "家族離族紀錄")
	if not ResidentRoster.valid_state(state): return Runtime.fail("CORRUPT_SAVE", "居民名冊格式")
	if not CaptiveEscort.valid_orders(state.get("escort_orders", {}), data.size.x * data.size.y, people, relations):
		return Runtime.fail("CORRUPT_SAVE", "原人押送命令／拘押引用")
	var guarded := {}
	var prison_claims := {}
	for key: Variant in relations:
		var relation: Variant = relations[key]
		if not _serial(key, 2147483648) or not relation is Dictionary or not _integer(relation.get("version"), 1, 3) or relation.size() != [5, 6, 13][int(relation.version) - 1]:
			return Runtime.fail("CORRUPT_SAVE", "拘押身分／版本")
		if int(relation.version) >= 2 and not relation.get("prison_id") is String: return Runtime.fail("CORRUPT_SAVE", "監禁引用欄位")
		# v3 (F02 / plan 6.1): capture and admission game seconds, episode, legacy marker.
		if int(relation.version) == 3:
			var site_seconds := (float(state.get("minute", 0)) + float(state.get("phase", 0.0))) * 60.0 + 0.001
			var captured: Variant = relation.get("captured_at_game_seconds")
			var admitted: Variant = relation.get("admitted_at_game_seconds")
			if not _number(captured, 0.0, site_seconds) or not (admitted is int or admitted is float) \
				or (str(relation.prison_id).is_empty() and float(admitted) != -1.0) \
				or (not str(relation.prison_id).is_empty() and not _number(admitted, float(captured), site_seconds)) \
				or not relation.get("legacy_observed") is bool:
				return Runtime.fail("CORRUPT_SAVE", "拘押／入監時間")
			var episode: Variant = relation.get("episode")
			if not episode is Dictionary or episode.size() != 3 or not episode.get("site_id") is String or not _integer(episode.get("person_id"), 1, 2147483647) \
				or int(episode.person_id) != int(key) or not _integer(episode.get("seq"), 0, 2147483647):
				return Runtime.fail("CORRUPT_SAVE", "捕獲 episode")
			if relation.get("loyal_org") != null and not TerrainTestCharacter.PersonSocial.valid_org_ref(relation.loyal_org) \
				or str(relation.get("rank_snapshot", "")) not in TerrainTestCharacter.PersonSocial.RANKS \
				or not _integer(relation.get("settled_days"), 0, floori(maxf(0.0, site_seconds - float(captured)) / 86400.0)):
				return Runtime.fail("CORRUPT_SAVE", "效忠組織／身分快照／已結算拘押日")
		for field: String in ["captor_id", "guard_id"]:
			if not _integer(relation.get(field), 1, 2147483647) or int(relation[field]) == int(key) or int(relation[field]) == TerrainArmy.PLAYER_MEMBER:
				return Runtime.fail("CORRUPT_SAVE", "拘押者／看守原人物引用")
		if not _integer(relation.get("captor_faction"), 0, 100000000) or not relation.get("sealed_container") is String:
			return Runtime.fail("CORRUPT_SAVE", "拘押陣營／封存包")
		var target: Dictionary = people.get(int(key), {})
		if target.is_empty() or not _number(target.get("hp"), 0.000000001, 100.0) or target.get("captive") != true:
			return Runtime.fail("CORRUPT_SAVE", "拘押關係必須引用原存活被俘人物")
		var sealed := str(relation.sealed_container)
		if not sealed.is_empty():
			if not _serial(sealed, int(state.next_loot)):
				return Runtime.fail("CORRUPT_SAVE", "封存包序號")
			var container: Dictionary = state.ground_loot.get(sealed, {})
			if not container.is_empty() and (container.kind != "sealed" or int(container.original_owner) != int(key)):
				return Runtime.fail("CORRUPT_SAVE", "封存包不是原受俘者的實物")
		if state.has("crowd") and (not people.has(int(relation.captor_id)) or not people.has(int(relation.guard_id))):
			return Runtime.fail("INVALID_CROWD", "拘押的目前引用無人物紀錄")
		var prison_id := str(relation.get("prison_id", ""))
		if not prison_id.is_empty():
			if not _serial(prison_id, int(state.next_feature)): return Runtime.fail("CORRUPT_SAVE", "戰俘營引用")
			var feature: Dictionary = state.features.get(prison_id, {})
			if str(feature.get("kind", "")) != "prison" or str(feature.get("stage", "")) != "complete" or int(feature.get("layout_version", 0)) != Runtime.BUILDING_LAYOUT_VERSION: return Runtime.fail("CORRUPT_SAVE", "監禁須引用已完工戰俘營")
			if int(feature.get("owner_faction", -1)) >= 0 and int(feature.owner_faction) != int(relation.captor_faction): return Runtime.fail("CORRUPT_SAVE", "原拘押方不是戰俘營管理方")
			var layout := Runtime._prison_geometry(data, feature)
			var cell := Vector2i(int(target.cell[0]), int(target.cell[1]))
			var legal := false
			for slot: Dictionary in layout.slots:
				if slot.cell == cell: legal = true
			if not legal or prison_claims.has(cell): return Runtime.fail("CORRUPT_SAVE", "在監人物不在唯一合法拘押格")
			prison_claims[cell] = int(key)
			if float(target.get("movement_left", 0.0)) > 0.0 or (target.has("destination") and Vector2i(int(target.destination[0]), int(target.destination[1])) != Vector2i(-1, -1)): return Runtime.fail("CORRUPT_SAVE", "在監人物仍在步進")
			continue
		var guard_id := int(relation.guard_id)
		guarded[guard_id] = int(guarded.get(guard_id, 0)) + 1
		if int(guarded[guard_id]) > 4:
			return Runtime.fail("CORRUPT_SAVE", "同一原看守超過四位俘虜")
	for identity: int in people:
		var person: Dictionary = people[identity]
		if float(person.get("hp", 0.0)) <= 0.0: continue
		var cell := Vector2i(int(person.cell[0]), int(person.cell[1]))
		if prison_claims.has(cell) and int(prison_claims[cell]) != identity: return Runtime.fail("CORRUPT_SAVE", "其他原人物占用在監拘押格")
	for order: Dictionary in state.get("escort_orders", {}).values():
		if str(order.get("kind", "")) != "prison": continue
		var feature: Dictionary = state.features.get(str(order.prison_id), {})
		if str(feature.get("kind", "")) != "prison" or str(feature.get("stage", "")) != "complete" or int(feature.get("layout_version", 0)) != Runtime.BUILDING_LAYOUT_VERSION: return Runtime.fail("CORRUPT_SAVE", "入監命令引用失效")
		var layout := Runtime._prison_geometry(data, feature)
		if data.index(layout.entry) != int(order.destination): return Runtime.fail("CORRUPT_SAVE", "入監命令出口不符")
		var slots := {}
		for slot: Dictionary in layout.slots: slots[data.index(slot.cell)] = true
		for index: Variant in order.targets.values():
			var cell := data.cell_from_index(int(index))
			if not slots.has(int(index)) or prison_claims.has(cell): return Runtime.fail("CORRUPT_SAVE", "入監命令拘押格重複或失效")
			prison_claims[cell] = true
	var technology := _validate_technology(state, people)
	if not technology.ok: return technology
	return _validate_region_life_events(state, people, region_context)

static func _validate_settled_opened_food(state: Dictionary) -> Dictionary:
	# Saves use the new invariant; load permits old format-3 shape first and
	# invokes the idempotent migration before enforcing this same guard.
	var people: Array = state.get("actors", {}).values()
	for team: Dictionary in state.get("armies", []):
		people.append_array(team.units)
	for person: Dictionary in people:
		if bool(person.get("loot_settled", false)) and float(state.get("person_supply", {}).get(str(int(person.person_id)), {}).get("open_rations", 0.0)) != 0.0:
			return Runtime.fail("CORRUPT_SAVE", "已結算死者仍持有未轉存的私人開封口糧")
	return Runtime.ok()

static func _validate_remains(person: Dictionary, state: Dictionary, cargo: Variant) -> Dictionary:
	var error := _remains_validation_error(person, state, cargo)
	return Runtime.ok() if error.is_empty() else Runtime.fail("CORRUPT_SAVE", error)

static func _remains_validation_error(person: Dictionary, state: Dictionary, cargo: Variant) -> String:
	if not person.get("loot_settled", false) is bool or not person.get("remains_id", "") is String:
		return "人物遺物結算欄位"
	var settled: bool = person.get("loot_settled", false)
	var remains_reference := str(person.get("remains_id", ""))
	if not settled:
		return "" if remains_reference.is_empty() else "未結算卻引用遺物"
	if not person.has("item_state") or not _number(person.get("hp"), 0, 0) or not cargo is Dictionary or Runtime.inventory_size(cargo) != 0 or not person.item_state.get("item_ids", []).is_empty():
		return "已轉存死者仍持有物品／非死亡"
	if not remains_reference.is_empty():
		if not _serial(remains_reference, int(state.next_loot)):
			return "遺物引用序號"
		var container: Dictionary = state.ground_loot.get(remains_reference, {})
		if person.get("ship_death_settled", false) == true and container.is_empty(): return "新船死者非空遺物引用不存在"
		# Old LAND empty containers may have been reclaimed; IDs are never reused.
		if not container.is_empty() and (container.kind != "remains" or int(container.original_owner) != int(person.person_id)):
			return "遺物引用不是原死者"
	return ""

static func _validate_item_holder(holder: Variant, expected: String, state: Dictionary, locations: Dictionary, cargo: Variant, capacity: int) -> Dictionary:
	var error := _item_holder_validation_error(holder, expected, state, locations, cargo, capacity)
	return Runtime.ok() if error.is_empty() else Runtime.fail("CORRUPT_SAVE", error)

static func _item_holder_validation_error(holder: Variant, expected: String, state: Dictionary, locations: Dictionary, cargo: Variant, capacity: int) -> String:
	if not holder is Dictionary or holder.get("holder") != expected or not _integer(holder.get("version"), 0, 2147483647) or not holder.get("item_ids") is Array or not holder.get("equipped") is Dictionary or not _saved_resource_stack(cargo):
		return "物品持有欄位"
	if expected.begins_with("person:"):
		var extra_fields := 0
		for field: String in ["fire_lab_suppression_q", "fire_lab_ignition_q"]:
			if holder.has(field):
				extra_fields += 1
				var maximum := int(SiteCombatRules.fire_work_profile("SUPPRESS" if field.ends_with("suppression_q") else "IGNITE").supply_cap_q)
				if not _integer(holder[field], 0, maximum): return "原人物火攻有限補給欄位"
		if holder.size() != 4 + extra_fields: return "原人物物品持有欄位"
	elif not expected.begins_with("ground:") and holder.size() != 4:
		return "物品持有欄位"
	var worn := {}
	for identity: Variant in holder.item_ids:
		if not identity is String or locations.has(identity) or not state.item_records.has(identity) or str(state.item_records[identity].holder) != expected:
			return "同件裝備重複／不存在／持有人不符"
		locations[identity] = expected
	for slot: Variant in holder.equipped:
		var identity: Variant = holder.equipped[slot]
		if not slot is String or not identity is String or not holder.item_ids.has(identity) or worn.has(identity):
			return "實裝引用不存在／同物重複穿戴"
		var definition: Dictionary = state.item_definitions[state.item_records[identity].definition]
		if slot != str(definition.slot):
			return "裝備槽不符"
		worn[identity] = true
	var carried := Runtime.carried_size(cargo, holder)
	if carried > capacity:
		return "資源及裝備合計攜帶超量"
	if expected.begins_with("person:"):
		var personal: Variant = state.get("person_supply", {})
		if not personal is Dictionary:
			return "原私人餐份欄位"
		var pool: Variant = personal.get(expected.trim_prefix("person:"), {})
		if not pool is Dictionary or not _number(pool.get("open_rations", 0.0), 0.0, 1000000.0):
			return "原私人開封口糧"
		if float(carried) + float(pool.get("open_rations", 0.0)) > capacity:
			return "私人開封口糧與原行囊合計超量"
	return ""

static func _saved_resource_stack(cargo: Variant) -> bool:
	if not cargo is Dictionary:
		return false
	for resource: Variant in cargo:
		if not (resource is String or resource is StringName) or not Env.ITEM_NAMES.has(str(resource)) or not _integer(cargo[resource], 0, 1000000):
			return false
	return true

static func _serial(value: Variant, next_value: int) -> bool:
	return value is String and value.is_valid_int() and str(int(value)) == value and int(value) > 0 and int(value) < next_value

static func _valid_cell(data: TerrainData, value: Variant) -> bool:
	return _integer(value, 0, data.size.x * data.size.y - 1)

static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	if not (value is int or value is float): return false
	var number := float(value)
	# Keep original double comparisons, including rounded large-int boundaries.
	return is_finite(number) and number >= minimum and number <= maximum and (value is int or number == floorf(number))

static func _number(value: Variant, minimum: float, maximum: float) -> bool:
	if not (value is int or value is float): return false
	var number := float(value)
	return is_finite(number) and number >= minimum and number <= maximum


static func _validate_ship_build_teams(state: Dictionary) -> Dictionary:
	var teams := {}
	for army: Dictionary in state.get("armies", []): teams[int(army.team_id)] = int(army.faction_id)
	for feature: Dictionary in state.get("features", {}).values():
		if not feature.has("ship_build"): continue
		var team_id := int(feature.ship_build.team_id)
		if not teams.has(team_id) or int(teams[team_id]) != int(feature.owner_faction): return Runtime.fail("CORRUPT_SAVE", "造船原隊引用不存在或管理方不同")
	return Runtime.ok()

static func _validate_ship_relationships(_data: TerrainData, state: Dictionary, people: Dictionary) -> Dictionary:
	var slots := {}
	var positions := {}
	for identity: int in people:
		var original: Dictionary = people[identity]
		var body: Dictionary = original.body
		if body.has("ship_death_local") or body.has("ship_death_channel"):
			return Runtime.fail("BUSY", "船上死亡位置仍待原死亡結算；原人與物保留")
		if body.has("ship_death_settled"):
			if body.ship_death_settled != true or not body.ship_death_settled is bool or float(body.hp) > 0.0 or body.get("loot_settled", false) != true or body.has("embarked_vehicle_id") or body.has("berth_id"):
				return Runtime.fail("CORRUPT_SAVE", "船上死者結算標記與原人物不符")
		if body.has("ship_death_world"):
			if float(body.hp) > 0.0 or not Runtime.valid_ship_world_point(_data, body.ship_death_world): return Runtime.fail("CORRUPT_SAVE", "Original ship death world point")
			if body.get("loot_settled", false) != true: return Runtime.fail("BUSY", "Original world-point death still pending")
			if body.get("ship_death_settled", false) != true: return Runtime.fail("CORRUPT_SAVE", "Original world-point death closure")
		var aboard := body.has("embarked_vehicle_id")
		if body.has("ship_deck_position") or body.has("ship_guest"):
			if not aboard: return Runtime.fail("CORRUPT_SAVE", "甲板位置／接舷者缺少原船引用")
		if aboard != body.has("berth_id"):
			return Runtime.fail("CORRUPT_SAVE", "原人物乘船關係須互存")
		if not aboard: continue
		if int(original.team) <= 0 or not original.has("snapshot") or bool(original.snapshot.get("crowd", false)):
			return Runtime.fail("CORRUPT_SAVE", "首版乘載僅支持原 GD Army 人物；Actor/native 不得偷放")
		if not body.embarked_vehicle_id is String or body.embarked_vehicle_id.is_empty():
			return Runtime.fail("CORRUPT_SAVE", "船引用須為非空原車輛 ID")
		var vehicle: Variant = state.get("vehicles", {}).get(body.embarked_vehicle_id)
		if not vehicle is Dictionary or vehicle.get("kind") != "ship" or not vehicle.get("ship_type") is String or not ShipDefs.is_kind(vehicle.ship_type):
			return Runtime.fail("CORRUPT_SAVE", "人物乘載引用不存在或不屬於原容器隊伍")
		var guest: bool = int(vehicle.get("team_id", 0)) != int(original.team)
		if guest != body.has("ship_guest") or body.has("ship_guest") and body.ship_guest != true: return Runtime.fail("CORRUPT_SAVE", "接舷者與原隊／本船管理方引用不符")
		var definition := ShipDefs.definition(vehicle.ship_type)
		if not _integer(body.berth_id, 0, int(definition.max_people) - 1):
			return Runtime.fail("CORRUPT_SAVE", "人物船席超出船型版本")
		var local := ShipDefs.local_position(str(vehicle.ship_type), int(body.berth_id))
		if body.has("ship_deck_position"):
			var value: Variant = body.ship_deck_position
			if not value is Array or value.size() != 2 or not _number(value[0], -0.25, float(definition.width) - 0.75) or not _number(value[1], -0.25, float(definition.length) - 0.75): return Runtime.fail("CORRUPT_SAVE", "原甲板位置越界／非數值")
			local = Vector2(float(value[0]), float(value[1]))
		for previous: Vector2 in positions.get(str(vehicle.id), []):
			if previous.distance_to(local) < 0.13: return Runtime.fail("CORRUPT_SAVE", "原活人甲板位置重疊")
		if not positions.has(str(vehicle.id)): positions[str(vehicle.id)] = []
		positions[str(vehicle.id)].append(local)
		if float(body.hp) <= 0.0:
			return Runtime.fail("BUSY", "船上死亡轉存尚未成功，不可保存原 pending death")
		if body.get("loot_settled", false) == true or bool(body.get("departed", false)) or bool(body.get("site_exited", false)) or bool(body.get("surrender_pending", false)) or bool(body.get("captive", false)):
			return Runtime.fail("CORRUPT_SAVE", "乘載活人不得同時死亡結算／離場／投降／被俘")
		var path: Variant = body.get("path", [])
		if not _ship_saved_stopped(body) or not path is Array or not path.is_empty() or not body.get("work_task", {}).is_empty():
			return Runtime.fail("CORRUPT_SAVE", "船上原人物仍有陸地步進／未承諾路徑／作業")
		if _ship_saved_land_references(original.snapshot, identity):
			return Runtime.fail("CORRUPT_SAVE", "船上原人物仍被陸地隊形／部署／批次預約引用")
		if not bool(body.get("member", true)) and not _ship_saved_retired_person(state, identity):
			return Runtime.fail("CORRUPT_SAVE", "退隊原人物須保留同原容器及本人私人供養")
		var slot := str(body.embarked_vehicle_id) + ":" + str(int(body.berth_id))
		if slots.has(slot): return Runtime.fail("CORRUPT_SAVE", "兩個活人不能共用一個固定船席；KO 仍占席")
		slots[slot] = identity
	return Runtime.ok()

static func _ship_saved_land_references(snapshot: Dictionary, identity: int) -> bool:
	var people: Variant = snapshot.get("units", [])
	if not people is Array: return true
	var person_index := -1
	for index in range(people.size()):
		if not people[index] is Dictionary: return true
		if _integer(people[index].get("person_id"), identity, identity): person_index = index
	var vacancies: Variant = snapshot.get("vacancies", [])
	if not vacancies is Array: return true
	for pair: Variant in vacancies:
		if not pair is Array or pair.size() != 2: return true
		if person_index >= 0 and (_integer(pair[0], person_index, person_index) or _integer(pair[1], person_index, person_index)): return true
	var absent: Variant = snapshot.get("combat_absent_slots", {})
	if not absent is Dictionary or absent.has(str(identity)) or absent.has(identity): return true
	var deployment: Variant = snapshot.get("combat_deployment_plan")
	if deployment != null:
		if not deployment is Dictionary: return true
		for field: String in ["member_slot_map", "member_role_map", "member_slot_locked"]:
			var mapping: Variant = deployment.get(field, {})
			if not mapping is Dictionary or mapping.has(str(identity)) or mapping.has(identity): return true
		for field: String in ["following_member_ids", "queue_member_ids", "pending_platform_member_ids", "admitted_platform_member_ids", "settled_platform_member_ids", "settled_queue_member_ids"]:
			var ids: Variant = deployment.get(field, [])
			if not ids is Array or ids.has(identity): return true
		var owners: Variant = deployment.get("slot_lease_owner_map", {})
		if not owners is Dictionary or owners.values().has(identity): return true
	var movement: Variant = snapshot.get("combat_move_plan")
	if movement != null:
		if not movement is Dictionary: return true
		var vacated: Variant = movement.get("member_recovery_vacated_cell", {})
		if not vacated is Dictionary or vacated.has(str(identity)) or vacated.has(identity): return true
	for field: String in ["combat_batch_move_members", "combat_batch_retreat_members"]:
		var ids: Variant = snapshot.get(field, [])
		if not ids is Array or ids.has(identity): return true
	var batches: Variant = snapshot.get("combat_batches", [])
	if not batches is Array: return true
	for group: Variant in batches:
		if not group is Array or group.has(identity): return true
	return false

static func _ship_saved_retired_person(state: Dictionary, identity: int) -> bool:
	# Original leave_row transfers supply ownership. Current control may later
	# change to another family person, so do not require controlled_person_id == id.
	var personal: Variant = state.get("person_supply", {})
	if not personal is Dictionary: return false
	var pool: Variant = personal.get(str(identity))
	if not pool is Dictionary or not pool.get("cohorts") is Array: return false
	for cohort: Variant in pool.cohorts:
		if not cohort is Dictionary or not cohort.get("ids") is Array: return false
		for value: Variant in cohort.ids:
			if _integer(value, identity, identity): return true
	return false

static func _ship_saved_stopped(body: Dictionary) -> bool:
	# JSON numbers may be floats. Require the exact integral sentinel, without
	# relying on Array Variant-type equality or truncating malformed coordinates.
	var destination: Variant = body.get("destination")
	return destination is Array and destination.size() == 2 and _integer(destination[0], -1, -1) and _integer(destination[1], -1, -1)

static func _ship_saved_body_can_act(body: Dictionary) -> bool:
	return float(body.get("hp", 0.0)) > 0.0 and float(body.get("ko", 0.0)) <= 0.0 and str(body.get("pose", "")) != "get_up" and not bool(body.get("dead", false)) and not bool(body.get("captive", false)) and not bool(body.get("departed", false)) and not bool(body.get("site_exited", false)) and not bool(body.get("surrender_pending", false)) and _ship_saved_stopped(body) and body.get("work_task", {}).is_empty()

static func _validate_ship_vehicle(data: TerrainData, state: Dictionary, identity: Variant, vehicle: Dictionary, people: Dictionary, team_counts: Dictionary, claims: Dictionary, operators: Dictionary, guards: Dictionary, check_terrain: bool) -> Dictionary:
	const FIELDS := ["id", "kind", "team_id", "operator_id", "cell", "facing", "cargo", "holder", "move", "stop_pending", "ship_version", "ship_type", "definition_version", "revision", "command"]
	if vehicle.size() != FIELDS.size() + int(vehicle.has("naval")) + _fs_vehicle_optional_count(vehicle) or not _serial(identity, int(state.get("next_vehicle", 1))) or vehicle.get("id") != identity:
		return Runtime.fail("CORRUPT_SAVE", "船艦身分／欄位")
	for field: String in FIELDS:
		if not vehicle.has(field): return Runtime.fail("CORRUPT_SAVE", "船艦缺少 " + field)
	if vehicle.kind != "ship" or not vehicle.ship_type is String or not ShipDefs.is_kind(vehicle.ship_type) or not _integer(vehicle.ship_version, 1, 1) or not _integer(vehicle.definition_version, ShipDefs.VERSION, ShipDefs.VERSION):
		return Runtime.fail("SAVE_VERSION", "船型／資料／定義版本不相容；保留現場與原檔")
	var naval_validation := _validate_ship_naval(data, state, vehicle)
	if not naval_validation.ok: return naval_validation
	if not _integer(vehicle.team_id, 0, 999999) or not _integer(vehicle.operator_id, 0, 2147483647) or not _integer(vehicle.revision, 1, 2147483647) or not _valid_cell(data, vehicle.cell) or not _vehicle_facing(vehicle.facing) or not vehicle.move is Dictionary or not vehicle.stop_pending is bool or not vehicle.command is Dictionary:
		return Runtime.fail("CORRUPT_SAVE", "船艦所屬／操作人／位置／版本／作業欄位")
	var team_id := int(vehicle.team_id)
	var operator_id := int(vehicle.operator_id)
	if team_id > 0 and not team_counts.has(team_id): return Runtime.fail("CORRUPT_SAVE", "船艦所屬原隊伍不存在")
	if team_id == 0 and (operator_id > 0 or not vehicle.move.is_empty() or not vehicle.command.is_empty()): return Runtime.fail("CORRUPT_SAVE", "原清隊停泊船不能留操作人或移動命令")
	if not vehicle.command.is_empty():
		if vehicle.command.size() != 3 or not _valid_cell(data, vehicle.command.get("goal")) or not vehicle.command.get("retreat") is bool or not vehicle.command.get("docking") is bool:
			return Runtime.fail("CORRUPT_SAVE", "船艦未來命令欄位")
	if bool(vehicle.stop_pending) and (vehicle.move.is_empty() or not vehicle.command.is_empty()): return Runtime.fail("CORRUPT_SAVE", "停船旗標須為原半步且已清未來航路")
	var definition := ShipDefs.definition(vehicle.ship_type)
	var people_count := 0
	for original: Dictionary in people.values():
		var body: Dictionary = original.body
		if str(body.get("embarked_vehicle_id", "")) == str(identity) and float(body.hp) > 0.0: people_count += 1
	if people_count > int(definition.max_people): return Runtime.fail("CORRUPT_SAVE", "船艦活人席位 N 超量；KO 仍保留 N")
	if str(vehicle.get("naval", {}).get("state", "")) == "wrecked" and people_count > 0: return Runtime.fail("BUSY", "沉船原乘員尚未完成撤岸／死亡结算")
	if operator_id > 0:
		if operators.has(operator_id) or guards.has(operator_id) or not people.has(operator_id) or int(people[operator_id].team) != team_id:
			return Runtime.fail("CORRUPT_SAVE", "船艦操作人重複／原 ID 或所屬不符")
		var body: Dictionary = people[operator_id].body
		var ready: bool = _ship_saved_body_can_act(body) and str(body.get("embarked_vehicle_id", "")) == str(identity) and _integer(body.get("berth_id"), ShipDefs.HELM_BERTH, ShipDefs.HELM_BERTH)
		if body.has("ship_deck_position"):
			ready = ready and Vector2(float(body.ship_deck_position[0]), float(body.ship_deck_position[1])).is_equal_approx(ShipDefs.local_position(str(vehicle.ship_type), ShipDefs.HELM_BERTH))
		if not ready:
			var historical: bool = not vehicle.move.is_empty() and bool(vehicle.stop_pending) and _ship_saved_stopped(body)
			if float(body.hp) <= 0.0:
				historical = historical and body.get("loot_settled", false) == true and not body.has("embarked_vehicle_id") and not body.has("berth_id")
				for other: Dictionary in people.values():
					var other_body: Dictionary = other.body
					if float(other_body.hp) > 0.0 and str(other_body.get("embarked_vehicle_id", "")) == str(identity) and _integer(other_body.get("berth_id"), ShipDefs.HELM_BERTH, ShipDefs.HELM_BERTH): historical = false
			else:
				historical = historical and not _ship_saved_body_can_act(body) and str(body.get("embarked_vehicle_id", "")) == str(identity) and _integer(body.get("berth_id"), ShipDefs.HELM_BERTH, ShipDefs.HELM_BERTH)
			if not historical: return Runtime.fail("CORRUPT_SAVE", "失能操作引用僅限可驗證原半步；不要求死者必有 remains")
		operators[operator_id] = true
	elif not vehicle.move.is_empty() or not vehicle.command.is_empty():
		return Runtime.fail("CORRUPT_SAVE", "船舶在途／航路缺少原操作人；停穩 operator=0 合法")
	var anchor := data.cell_from_index(int(vehicle.cell))
	var facing := Vector2i(int(vehicle.facing[0]), int(vehicle.facing[1]))
	var occupied := ShipDefs.footprint(vehicle.ship_type, anchor, facing)
	for cell: Vector2i in occupied:
		if not data.contains(cell): return Runtime.fail("CORRUPT_SAVE", "整個船體越界")
	if not vehicle.move.is_empty():
		var move: Dictionary = vehicle.move
		const MOVE_FIELDS := ["from_cell", "from_facing", "cell", "facing", "elapsed", "duration", "sweep", "action"]
		if move.size() != MOVE_FIELDS.size(): return Runtime.fail("CORRUPT_SAVE", "船步欄位")
		for field: String in MOVE_FIELDS:
			if not move.has(field): return Runtime.fail("CORRUPT_SAVE", "船步缺少 " + field)
		if not _valid_cell(data, move.from_cell) or int(move.from_cell) != int(vehicle.cell) or not _vehicle_facing(move.from_facing) or move.from_facing != vehicle.facing or not _valid_cell(data, move.cell) or not _vehicle_facing(move.facing) or not move.sweep is Array or move.action not in ["forward", "reverse", "turn", "dock"] or not _number(move.duration, 0.000001, 1000000.0) or not _number(move.elapsed, 0.0, float(move.duration)):
			return Runtime.fail("CORRUPT_SAVE", "原船步來源／目的／時間／動作")
		var destination := data.cell_from_index(int(move.cell))
		var next_facing := Vector2i(int(move.facing[0]), int(move.facing[1]))
		var delta := destination - anchor
		if move.action == "turn":
			if destination != anchor or facing.x * next_facing.x + facing.y * next_facing.y != 0: return Runtime.fail("CORRUPT_SAVE", "原地船轉向須為九十度")
		elif next_facing != facing or move.action == "forward" and delta != facing or move.action == "reverse" and delta != -facing or move.action == "dock" and delta not in [facing, -facing]:
			return Runtime.fail("CORRUPT_SAVE", "船直行／倒船／靠泊只許沿原向一格")
		occupied = ShipDefs.swept_footprint(vehicle.ship_type, anchor, facing, destination, next_facing)
		if occupied.is_empty(): return Runtime.fail("CORRUPT_SAVE", "原船型動作掃掠未定義")
		var expected := {}
		for cell: Vector2i in occupied:
			if not data.contains(cell): return Runtime.fail("CORRUPT_SAVE", "船步旋轉／直行掃掠越界")
			expected[data.index(cell)] = true
		var actual := {}
		for value: Variant in move.sweep:
			if not _valid_cell(data, value) or actual.has(int(value)): return Runtime.fail("CORRUPT_SAVE", "船掃掠重複／越界")
			actual[int(value)] = true
		if actual != expected: return Runtime.fail("CORRUPT_SAVE", "船掃掠與原船型唯一保守幾何不符")
	if check_terrain and not data.can_place_water_vehicle(occupied): return Runtime.fail("CORRUPT_SAVE", "整個船體／掃掠／水邊不合法或未知可航來源")
	for cell: Vector2i in occupied:
		if claims.has(cell): return Runtime.fail("CORRUPT_SAVE", "船掃掠與原陸地人物／車輛預約衝突")
	for cell: Vector2i in occupied: claims[cell] = "vehicle:" + str(identity)
	var load_amount := _ship_saved_load(state, vehicle, people)
	if not load_amount.ok: return load_amount
	if float(load_amount.load) > float(definition.capacity) + 0.000001: return Runtime.fail("CORRUPT_SAVE", "全船 Q 超量：原艙／人物實裝行囊／遺物／共用及私人口糧")
	return Runtime.ok()

static func _validate_ship_naval(data: TerrainData, state: Dictionary, vehicle: Dictionary) -> Dictionary:
	if not vehicle.has("naval"): return Runtime.ok() # Known original v1 hulls remain valid.
	var naval: Variant = vehicle.naval
	if not naval is Dictionary or naval.size() != 4 + int(naval.has("boarding_link")) + int(naval.has("link_epoch")) or not _integer(naval.get("version"), 1, 2) or not _number(naval.get("hp"), 0.0, ShipDefs.hull_hp(str(vehicle.ship_type))) or not naval.get("state") is String or naval.state not in ["afloat", "sinking", "wrecked"] or not naval.get("repair") is Dictionary:
		return Runtime.fail("CORRUPT_SAVE", "船體耐久／狀態版本非法")
	if (str(naval.state) == "afloat") != (float(naval.hp) > 0.0): return Runtime.fail("CORRUPT_SAVE", "船體耐久與沉船狀態不符")
	var repair_validation: Dictionary = Runtime.validate_ship_repair(data, vehicle, state)
	if not repair_validation.ok: return repair_validation
	if str(naval.state) != "afloat" and (not vehicle.command.is_empty() or not vehicle.move.is_empty() and not bool(vehicle.stop_pending)):
		return Runtime.fail("CORRUPT_SAVE", "沉船只准完成原 committed step")
	return Runtime.ok()

static func _validate_ship_loot_location(data: TerrainData, state: Dictionary, identity: Variant, container: Dictionary) -> Dictionary:
	var world: bool = container.has("world_point")
	var channel := container.has("channel_point")
	var afloat := container.has("vehicle_id") or container.has("local_position") or channel
	var fields := ["holder", "version", "item_ids", "equipped", "kind", "original_owner", "cargo"]
	fields.append_array(["ship_world_version", "world_point"] if world else ((["vehicle_id", "peer_vehicle_id", "channel_point"] if channel else ["vehicle_id", "local_position"]) if afloat else ["cell"]))
	if container.size() != fields.size() + int(container.has("open_rations")) + int(container.has("boarding_position")) or not _serial(identity, int(state.get("next_loot", 1))): return Runtime.fail("CORRUPT_SAVE", "原遺物身分／互斥位置欄位")
	for field: String in fields:
		if not container.has(field): return Runtime.fail("CORRUPT_SAVE", "原遺物缺少 " + field)
	if world:
		return Runtime.ok() if Runtime.valid_ship_loot_location(data, {"ship_world_version": container.ship_world_version, "world_point": container.world_point}) else Runtime.fail("CORRUPT_SAVE", "Original fixed ship death point")
	if not afloat:
		return Runtime.ok() if _valid_cell(data, container.cell) else Runtime.fail("CORRUPT_SAVE", "原地面遺物格位")
	if container.has("cell") or not container.vehicle_id is String or container.vehicle_id.is_empty(): return Runtime.fail("CORRUPT_SAVE", "船上遺物不留地面 cell／claim 或空船引用")
	var vehicle: Variant = state.get("vehicles", {}).get(container.vehicle_id)
	if not vehicle is Dictionary or vehicle.get("kind") != "ship" or not vehicle.get("ship_type") is String or not ShipDefs.is_kind(vehicle.ship_type): return Runtime.fail("CORRUPT_SAVE", "船上遺物引用不存在的船型")
	if channel:
		if container.has("local_position") or container.has("cell"): return Runtime.fail("CORRUPT_SAVE", "通道遺物不得同時帶地面或船內相對位置")
		var peer: Variant = state.get("vehicles", {}).get(container.get("peer_vehicle_id"))
		if not peer is Dictionary or peer.get("kind") != "ship" or not peer.get("ship_type") is String or not ShipDefs.is_kind(peer.ship_type): return Runtime.fail("CORRUPT_SAVE", "通道遺物的對方船不存在")
		var point: Variant = container.channel_point
		if not point is Array or point.size() != 2 or not _number(point[0], -1.0e9, 1.0e9) or not _number(point[1], -1.0e9, 1.0e9): return Runtime.fail("CORRUPT_SAVE", "通道遺物位置格式")
		var near: bool = ShipDefs.channel_point_near_pair(vehicle.ship_type, data.cell_from_index(int(vehicle.cell)), Vector2i(int(vehicle.facing[0]), int(vehicle.facing[1])), peer.ship_type, data.cell_from_index(int(peer.cell)), Vector2i(int(peer.facing[0]), int(peer.facing[1])), Vector2(float(point[0]), float(point[1])))
		return Runtime.ok() if near else Runtime.fail("CORRUPT_SAVE", "通道遺物位置不在接舷兩船的通道範圍內")
	var definition := ShipDefs.definition(vehicle.ship_type)
	var position: Variant = container.local_position
	if not position is Array or position.size() != 2 or not _number(position[0], -0.5, float(definition.width) - 0.5) or not _number(position[1], -0.5, float(definition.length) - 0.5) or float(position[0]) >= float(definition.width) - 0.5 or float(position[1]) >= float(definition.length) - 0.5:
		return Runtime.fail("CORRUPT_SAVE", "原船相對遺物位置越出格中心船體邊界")
	return Runtime.ok() # Does not reserve a berth/land cell or contribute to N.

static func _ship_saved_holder_load(state: Dictionary, cargo: Variant, holder: Variant) -> float:
	if not _saved_resource_stack(cargo) or not holder is Dictionary or not holder.get("item_ids") is Array or not holder.get("equipped") is Dictionary or not holder.get("holder") is String: return -1.0
	var personal: Variant = state.get("person_supply", {})
	if not personal is Dictionary: return -1.0
	var pool: Variant = personal.get(str(holder.holder).trim_prefix("person:"), {}) if str(holder.holder).begins_with("person:") else holder
	if not pool is Dictionary or not _number(pool.get("open_rations", 0.0), 0.0, 1000000.0): return -1.0
	# The original item validator proves IDs/slots/records uniquely. Add worn items
	# back once, since carried_load omits equipped items for PERSONAL carry limits.
	return Runtime.carried_load(state, cargo, holder) + float(holder.equipped.size())

static func _ship_saved_load(state: Dictionary, vehicle: Dictionary, people: Dictionary) -> Dictionary:
	var load_amount := _ship_saved_holder_load(state, vehicle.cargo, vehicle.holder)
	if load_amount < 0.0: return Runtime.fail("CORRUPT_SAVE", "船艙原 holder／cargo／口糧資料")
	for original: Dictionary in people.values():
		var body: Dictionary = original.body
		if str(body.get("embarked_vehicle_id", "")) != str(vehicle.id): continue
		var amount := _ship_saved_holder_load(state, body.get("cargo", {}), body.get("item_state"))
		if amount < 0.0: return Runtime.fail("CORRUPT_SAVE", "船上原人物 holder／cargo／私人口糧資料")
		load_amount += amount
	var ground_loot: Variant = state.get("ground_loot", {})
	if not ground_loot is Dictionary: return Runtime.fail("CORRUPT_SAVE", "原遺物字典")
	for container: Variant in ground_loot.values():
		if not container is Dictionary: return Runtime.fail("CORRUPT_SAVE", "原遺物容器資料")
		if str(container.get("vehicle_id", "")) != str(vehicle.id): continue
		# Original ground_loot IS its item holder; container.holder is a string.
		var amount := _ship_saved_holder_load(state, container.get("cargo", {}), container)
		if amount < 0.0: return Runtime.fail("CORRUPT_SAVE", "船上原遺物 holder／cargo／開封口糧資料")
		load_amount += amount # carried_load already includes container.open_rations once.
	var supplies: Variant = state.get("team_supply", {})
	if not supplies is Dictionary: return Runtime.fail("CORRUPT_SAVE", "原隊伍供養字典")
	for supply: Variant in supplies.values():
		if not supply is Dictionary: return Runtime.fail("CORRUPT_SAVE", "原隊伍供養資料")
		if not supply.get("locations", {}) is Dictionary: return Runtime.fail("CORRUPT_SAVE", "原隊伍存糧位置資料")
		var stock: Variant = supply.get("locations", {}).get("vehicle:" + str(vehicle.id), {})
		if not stock is Dictionary: return Runtime.fail("CORRUPT_SAVE", "本船原共有存糧資料")
		if stock.is_empty(): continue
		if stock.size() != 2 or not _saved_resource_stack(stock.get("inventory")) or not _number(stock.get("open_rations"), 0.0, 1000000.0): return Runtime.fail("CORRUPT_SAVE", "本船原共有存糧／開封口糧")
		load_amount += float(Runtime.inventory_size(stock.inventory)) + float(stock.open_rations)
	return Runtime.ok("", {"load": load_amount})

# Shape-only input prepass. It intentionally precedes Env's detached projection;
# the normal vehicle validator still owns versions, cargo, crew and relations.
static func _validate_siege_surface_inputs(data: TerrainData, state: Dictionary, hot: bool = false) -> Dictionary:
	for feature: Dictionary in state.get("features", {}).values():
		if not hot and str(feature.get("kind", "")) == "siege_ladder" and not str(feature.get("ladder", {}).get("pending", "")).is_empty(): return Runtime.fail("CORRUPT_SAVE", "保存梯具架設／收起作業尚未收束")
	var vehicles: Variant = state.get("vehicles", {})
	if not vehicles is Dictionary: return Runtime.fail("CORRUPT_SAVE", "候選塔導航需要原車具表")
	for key: Variant in vehicles:
		var vehicle: Variant = vehicles[key]
		if not key is String or not vehicle is Dictionary or not vehicle.get("kind") is String or not _valid_cell(data, vehicle.get("cell")) or not _vehicle_facing(vehicle.get("facing")):
			return Runtime.fail("CORRUPT_SAVE", "候選塔導航車具位姿非法")
		if not vehicle.get("move", {}) is Dictionary or not vehicle.get("action", {}) is Dictionary: return Runtime.fail("CORRUPT_SAVE", "候選塔導航車具作業非法")
		for operation: Dictionary in [vehicle.get("move", {}), vehicle.get("action", {})]:
			if not operation.get("sweep", []) is Array: return Runtime.fail("CORRUPT_SAVE", "候選塔導航掃掠非法")
			for cell: Variant in operation.get("sweep", []):
				if not _valid_cell(data, cell): return Runtime.fail("CORRUPT_SAVE", "候選塔導航掃掠越界")
		if str(vehicle.kind) == "ship" and (not vehicle.get("ship_type") is String or not ShipDefs.is_kind(vehicle.ship_type)): return Runtime.fail("CORRUPT_SAVE", "候選塔導航船種非法")
		var pose := Runtime.validate_siege_tower_pose(data, vehicle)
		if not pose.ok: return pose
	return Runtime.ok()

static func _validate_siege_tower_layouts(data: TerrainData, state: Dictionary) -> Dictionary:
	for vehicle: Dictionary in state.get("vehicles", {}).values():
		if str(vehicle.get("kind", "")) != "siege_tower": continue
		var geometry := Runtime.siege_tower_geometry(data, vehicle)
		for cell: Vector2i in geometry.physical:
			if not data.contains(cell): return Runtime.fail("CORRUPT_SAVE", "攻城塔實體範圍越界")
		if str(vehicle.phase) == "deployed" and not bool(geometry.active): return Runtime.fail("CORRUPT_SAVE", "保存塔的部署支承已失效")
	return Runtime.ok()

# The general _validate_siege_vehicle loop calls this before rejecting a person
# claim; vehicle:<id> claims always remain physical conflicts. A second pass
# includes settled KO/dead people that are absent from live movement claims.
static func _siege_tower_person_claim(data: TerrainData, vehicle: Dictionary, cell: Vector2i, identity: Variant, people: Dictionary) -> bool:
	if not (identity is int or identity is float) or not _integer(identity, 1, 2147483647) or not people.has(int(identity)): return false
	return Runtime.siege_tower_saved_person_allowed(data, vehicle, people[int(identity)].body, cell)

static func _validate_siege_tower_people(data: TerrainData, vehicle: Dictionary, people: Dictionary) -> Dictionary:
	if str(vehicle.get("kind", "")) != "siege_tower": return Runtime.ok()
	var physical := Runtime.siege_tower_physical_cells(data, vehicle)
	for person: Dictionary in people.values():
		var body: Dictionary = person.body
		if body.has("embarked_vehicle_id") or bool(body.get("departed", false)) or bool(body.get("site_exited", false)): continue
		var cell := Vector2i(int(body.cell[0]), int(body.cell[1]))
		if physical.has(cell) and not Runtime.siege_tower_saved_person_allowed(data, vehicle, body, cell): return Runtime.fail("CORRUPT_SAVE", "原人物不在合法塔面／失效塔原地收束位置")
	return Runtime.ok()

## Region captures keep the original payload and validators; no ordinary-save bypass flag.
static func capture_region_snapshot(data: TerrainData, context: Dictionary, owners: Dictionary = {}, read_only: bool = false) -> Dictionary:
	var request := context.duplicate(true)
	request["owners"] = owners if not owners.is_empty() else context.get("owners", {})
	return save(data, "", null, false, request, true, 0, read_only)

static func save_region_snapshot(data: TerrainData, path: String, context: Dictionary, owners: Dictionary = {}) -> Dictionary:
	var request := context.duplicate(true)
	request["owners"] = owners if not owners.is_empty() else context.get("owners", {})
	return save(data, path, null, false, request)

static func validate_region_snapshot(data: TerrainData, raw: Dictionary, expected: Dictionary = {}) -> Dictionary:
	if data == null: return Runtime.fail("NO_TARGET")
	var state: Dictionary = raw.get("state", data.site)
	var snapshot: Variant = raw.get("snapshot", raw.get("region_snapshot", state.get("region_snapshot", {})))
	var checked := RegionCheckpoint.validate(state, snapshot, expected)
	if not checked.ok: return checked
	var validated := _validate_state(data, state.duplicate(true), 1, null, checked.context)
	if not validated.ok: return validated
	return checked

static func restore_region_snapshot(data: TerrainData, raw: Dictionary, owner_restore: Callable) -> Dictionary:
	var checked := validate_region_snapshot(data, raw)
	if not checked.ok: return checked
	if not owner_restore.is_valid(): return Runtime.fail("REGION_BIND_PENDING", "original owner restore unavailable")
	var result: Variant = owner_restore.call(checked.owners, checked.context)
	if not result is Dictionary or not bool(result.get("ok", false)): return result if result is Dictionary else Runtime.fail("REGION_BIND_PENDING")
	for field: String in ["token", "source_generation", "runtime_revision", "game_seconds", "action_seconds", "fire_epoch", "fire_sequence"]:
		if result.get(field) != checked.context[field]: return Runtime.fail("STALE_REGION_RESTORE", field)
	if not bool(result.get("owners_restored", false)) or not result.get("effects_complete") is bool: return Runtime.fail("REGION_BIND_PENDING")
	return Runtime.ok("", {"context": checked.context, "owners_restored": true, "bind_complete": false, "effects_pending": not bool(result.effects_complete), "zero_world_only": not bool(result.effects_complete)})

static func _region_capture_owners(request: Dictionary) -> Dictionary:
	var context := request.duplicate(true)
	var sources: Variant = context.get("owners", {})
	context.erase("owners")
	var checked := RegionCheckpoint.validate_context(context)
	if not checked.ok: return checked
	if not sources is Dictionary: return Runtime.fail("INVALID_REGION_OWNERS")
	var owners := {}
	for key: Variant in sources:
		if not key is String or str(key).is_empty(): return Runtime.fail("INVALID_REGION_OWNERS")
		var source: Variant = sources[key]
		if source is Callable:
			if not source.is_valid(): return Runtime.fail("REGION_OWNER_UNAVAILABLE", str(key))
			var captured: Variant = source.call(checked.context)
			if not captured is Dictionary or not bool(captured.get("ok", false)) or not captured.get("state") is Dictionary: return captured if captured is Dictionary else Runtime.fail("INVALID_REGION_OWNERS", str(key))
			for field: String in ["token", "source_generation", "runtime_revision", "game_seconds", "action_seconds"]:
				if captured.get(field) != checked.context[field]: return Runtime.fail("STALE_REGION_OWNER", str(key) + "." + field)
			owners[key] = captured.state
		else:
			if not source is Dictionary: return Runtime.fail("INVALID_REGION_OWNERS", str(key))
			owners[key] = source.duplicate(true)
	if not RegionCheckpoint.supported(owners): return Runtime.fail("INVALID_REGION_OWNERS")
	return Runtime.ok("", {"context": checked.context, "owners": owners})

static func _region_siege_command(data: TerrainData, state: Dictionary, command: Dictionary, people: Dictionary, depth: int = 0) -> bool:
	if depth > 2: return false
	if command.get("type") in ["attack", "stop"] or command.is_empty(): return _valid_siege_command(data, state, command, people)
	match str(command.get("type", "")):
		"crew": return command.size() == 1
		"move": return command.size() == 2 and command.get("target") is Dictionary and command.target.size() == 2 and command.target.get("type") == "ground" and _valid_xy_pair(data, command.target.get("cell"))
		"turn": return command.size() == 2 and _vehicle_facing(command.get("facing"))
		"release":
			if command.size() != 3 + int(command.has("resume")) or not command.get("people") is Array or not command.get("reason") is String: return false
			var seen := {}
			for identity: Variant in command.people:
				if not _integer(identity, 1, 2147483647) or not people.has(int(identity)) or seen.has(int(identity)): return false
				seen[int(identity)] = true
			return not command.has("resume") or command.resume is Dictionary and _region_siege_command(data, state, command.resume, people, depth + 1)
	return false

static func _region_siege_transient(data: TerrainData, state: Dictionary, vehicle: Dictionary, people: Dictionary, context: Dictionary = {}) -> bool:
	if str(vehicle.phase) not in ["building", "idle", "ready", "disabled", "wrecked", "deployed", "turning", "moving", "preparing", "collision", "recovering", "deploying", "loading", "aiming"]: return false
	var action: Dictionary = vehicle.action
	if str(vehicle.kind) in ["ballista", "traction_trebuchet", "counterweight_trebuchet"] and str(vehicle.phase) == "recovering" and action.get("stage") != "recovering": return false
	if str(vehicle.phase) in ["loading", "aiming"] and str(action.get("stage", "")) != str(vehicle.phase): return false
	if not action.is_empty():
		if str(action.get("stage", "")) not in ["approach", "rotate", "return", "preparing", "collision", "recovering", "tower_deploy", "tower_retract", "loading", "aiming"] or not _number(action.get("elapsed"), 0.0, 1000000.0) or action.has("native_token"): return false
		var ranged: bool = str(vehicle.kind) in ["ballista", "traction_trebuchet", "counterweight_trebuchet"]
		if str(action.stage) in ["loading", "aiming"] or ranged and str(action.stage) == "recovering":
			if not _region_ranged_siege_action(data, state, vehicle, people, context): return false
		elif str(action.stage) in ["preparing", "collision", "recovering"]:
			if str(vehicle.kind) != "ram" or not _number(action.get("multiplier"), 0.5, 1.0) or not action.get("target") is Dictionary or not _valid_siege_command(data, state, {"type": "attack", "target": action.target}, people) or not action.get("attack_id") is String or not action.get("people") is Dictionary or not action.get("parts") is Dictionary: return false
			var attack_id := str(action.attack_id)
			if not attack_id.is_empty():
				var prefix := str(state.id) + "|" + str(vehicle.id) + "|"
				if not attack_id.begins_with(prefix) or not attack_id.trim_prefix(prefix).is_valid_int() or int(attack_id.trim_prefix(prefix)) < 1 or int(attack_id.trim_prefix(prefix)) >= int(vehicle.next_attack_seq): return false
			if float(action.elapsed) > (2.0 if action.stage == "preparing" else (0.25 if action.stage == "collision" else 0.75)) / float(action.multiplier) + 0.000001: return false
		if str(action.stage) in ["approach", "rotate", "return"]:
			if not _vehicle_facing(action.get("facing")) or not action.get("participants") is Array or not action.get("sweep") is Array: return false
			for identity: Variant in action.participants:
				if not _integer(identity, 1, 2147483647) or not vehicle.crew_slots.values().has(int(identity)): return false
			for cell: Variant in action.sweep:
				if not _valid_cell(data, cell): return false
			if action.stage == "rotate" and (not action.get("source_heights") is Dictionary or not action.get("compound_id") is String or str(action.compound_id).is_empty()): return false
		if str(action.stage) in ["tower_deploy", "tower_retract"] and (str(vehicle.kind) != "siege_tower" or action.get("settled_phase") not in ["idle", "ready", "deployed", "disabled"]): return false
	var move: Dictionary = vehicle.move
	if move.is_empty(): return true
	if move.get("mode") != "translate" or move.get("vehicle_id") != vehicle.id or move.get("command") != vehicle.command or move.has("native_token") or not _valid_cell(data, move.get("from")) or int(move.from) != int(vehicle.cell) or not _valid_cell(data, move.get("cell")) or not _vehicle_facing(move.get("facing")) or not _number(move.get("duration"), 0.000001, 1000000.0) or not move.get("compound_id") is String or str(move.compound_id).is_empty() or not move.get("participants") is Array or move.participants.size() != vehicle.crew_slots.size() or not move.get("sweep") is Array or not move.get("source_heights") is Dictionary: return false
	var seen := {}
	var shift := data.cell_from_index(int(move.cell)) - data.cell_from_index(int(move.from))
	if absi(shift.x) + absi(shift.y) != 1: return false
	for member: Variant in move.participants:
		if not member is Dictionary or not _integer(member.get("person_id"), 1, 2147483647) or not vehicle.crew_slots.values().has(int(member.person_id)) or seen.has(int(member.person_id)) or not _valid_cell(data, member.get("from")) or not _valid_cell(data, member.get("to")): return false
		seen[int(member.person_id)] = true
		var person: Dictionary = people.get(int(member.person_id), {})
		if person.is_empty(): return false
		var body: Dictionary = person.body
		var destination := data.cell_from_index(int(member.to))
		if destination - data.cell_from_index(int(member.from)) != shift or Vector2i(int(body.cell[0]), int(body.cell[1])) != data.cell_from_index(int(member.from)) or body.get("destination") != [destination.x, destination.y]: return false
	for cell: Variant in move.sweep:
		if not _valid_cell(data, cell): return false
	for key: Variant in move.source_heights:
		if not key is String or not key.is_valid_int() or not _valid_cell(data, int(key)) or not _integer(move.source_heights[key], 0, 10): return false
	return true

## Original ranged work uses scaled work elapsed, with an already-paid source retained in recovery.
static func _region_ranged_siege_action(data: TerrainData, state: Dictionary, vehicle: Dictionary, people: Dictionary, context: Dictionary = {}) -> bool:
	var action: Dictionary = vehicle["action"]
	var rule: Dictionary = SiteCombatRules.siege_attack(str(vehicle["kind"]))
	var stage: String = str(action.get("stage", ""))
	if rule.get("projectile") not in ["bolt", "stone"] or stage not in ["loading", "aiming", "recovering"] or action.size() != 6 or not vehicle["move"].is_empty(): return false
	if stage == "recovering" and str(vehicle["phase"]) not in ["recovering", "wrecked"]: return false
	if stage != "recovering" and str(vehicle["phase"]) not in [stage, "disabled"]: return false
	for field: String in ["stage", "elapsed", "cargo_version", "rng_state", "multiplier", "target"]:
		if not action.has(field): return false
	if not _number(action["elapsed"], 0.0, 1000000.0) or not _number(action["multiplier"], 0.5, 1.0) \
		or not _integer(action["cargo_version"], 0, 2147483646) or not _integer(action["rng_state"], 0, 2147483647) \
		or not action["target"] is Dictionary or not _valid_siege_command(data, state, {"type": "attack", "target": action["target"]}, people): return false
	var maximum: float = float(rule[stage])
	if float(action["elapsed"]) > maximum:
		# Deferral retains one already-paid shared interval before its original P0 transition.
		var point: Dictionary = context.get("endpoint_payload", {})
		if context.get("effects_complete", true) or point.get("interval_complete") != true or point.get("epoch") != context.get("fire_epoch") \
			or point.get("sequence") != context.get("fire_sequence") or point.get("game_end") != context.get("game_seconds") \
			or point.get("action_end") != context.get("action_seconds") or point.get("fire_action_end") != context.get("action_seconds") \
			or not _number(point.get("fire_action_begin"), 0.0, float(context.get("action_seconds", -1.0))): return false
		var paid: float = float(context["action_seconds"]) - float(point["fire_action_begin"])
		maximum += paid * float(action["multiplier"])
		if float(action["elapsed"]) > maximum: return false
	if stage == "recovering": return int(action["cargo_version"]) < int(vehicle["holder"]["version"]) and int(vehicle["next_attack_seq"]) >= 2
	return int(action["cargo_version"]) == int(vehicle["holder"]["version"]) and int(action["rng_state"]) == int(vehicle["rng_state"])

static func _region_siege_claim(data: TerrainData, vehicle: Dictionary, cell: Vector2i, identity: Variant) -> bool:
	if not _integer(identity, 1, 2147483647): return false
	for member: Dictionary in vehicle.move.get("participants", []):
		if int(member.person_id) == int(identity) and data.cell_from_index(int(member.to)) == cell: return true
	return false

static func _validate_travel_patients(vehicle: Dictionary, people: Dictionary, all_patients: Dictionary) -> Dictionary:
	if not vehicle.has("travel_patients"): return Runtime.ok()
	var manifest: Variant = vehicle.travel_patients
	if not manifest is Dictionary or manifest.size() != 3 or manifest.get("version") != 1 or not manifest.get("person_ids") is Array or manifest.person_ids.is_empty() or manifest.person_ids.size() > (1 if vehicle.kind == "cart" else 2) or not _integer(manifest.get("reserved_capacity"), 50 * manifest.person_ids.size(), 50 * manifest.person_ids.size()): return Runtime.fail("CORRUPT_TRAVEL_PATIENTS")
	for value: Variant in manifest.person_ids:
		if not _integer(value, 1, 2147483647) or not people.has(int(value)) or all_patients.has(int(value)) or int(value) == int(vehicle.operator_id): return Runtime.fail("CORRUPT_TRAVEL_PATIENTS")
		var person: Dictionary = people[int(value)]
		var body: Dictionary = person.body
		if int(person.team) != int(vehicle.team_id) or bool(body.get("site_exited", false)) or bool(body.get("departed", false)) or not str(body.get("embarked_vehicle_id", "")).is_empty() or float(body.get("hp", 0.0)) <= 0.0 or float(body.get("ko", body.get("knockout_left", 0.0))) <= 0.0: return Runtime.fail("CORRUPT_TRAVEL_PATIENTS")
		all_patients[int(value)] = str(vehicle.id)
	return Runtime.ok()


const RegionCold = preload("res://scripts/terrain_lab/site_region_cold.gd")

static func prepare_region_cold(data: TerrainData, interval: Dictionary, mode: String = "cold_exact") -> Dictionary:
	return RegionCold.prepare(data, interval, mode)

static func advance_region_cold(data: TerrainData, target: float, exact_step: Callable = Callable(), budget: int = 4096) -> Dictionary:
	return RegionCold.advance(data, target, exact_step, budget)


static func _region_due_work(context: Dictionary, owner: String) -> bool:
	if bool(context.get("effects_complete", true)): return false
	for event: Dictionary in context.get("events", []):
		if event.get("kind") == "work" and event.get("status") == "pending" and (str(event.get("owner", "")) == owner or str(event.get("payload", {}).get("vehicle_id", "")) == owner): return true
	for entry: Variant in context.get("endpoint_payload", {}).get("work", []):
		if entry is Dictionary and str(entry.get("owner", "")) == owner and entry.get("pending") == true and not str(entry.get("id", "")).is_empty(): return true
	return false

static func _validate_technology(state: Dictionary, people: Dictionary) -> Dictionary:
	for body: Dictionary in people.values():
		if body.has("technology") and not Technology.valid_person(body.technology): return Runtime.fail("CORRUPT_TECHNOLOGY", "原人物技藝版本／種類非法")
	if state.has("family") and int(state.family.get("version", 1)) == 3 and not Technology.valid_family_tech_for_site(state.family, str(state.id), people, state.get("armies", [])):
		return Runtime.fail("CORRUPT_TECHNOLOGY", "家族科技 holder／原人物及隊伍引用非法")
	return Runtime.ok()

static func _validate_travel_identity(state: Dictionary) -> Dictionary:
	if not state.has("travel_identity"): return Runtime.ok()
	var original: GDScript = load("res://scripts/region_lab/region_travel.gd")
	if original == null or not original.has_method("validate_identity") or not original.validate_identity(state.travel_identity): return Runtime.fail("CORRUPT_TRAVEL_IDENTITY")
	return Runtime.ok()

static func _region_prepare_deliveries(state: Dictionary) -> Dictionary:
	for supply: Dictionary in state.get("team_supply", {}).values():
		var job: Variant = supply.get("delivery", {})
		if not job is Dictionary: return Runtime.fail("CORRUPT_REGION_DELIVERY")
		if job.is_empty(): continue
		if job.get("region_transient") == 1: continue
		var recipe: Dictionary = job.duplicate(true)
		for field: String in ["source_owner", "receiver_owner", "source_body", "receiver_body", "source_cargo", "source_holder", "source_open"]: recipe.erase(field)
		for field: String in ["source_cell", "target_cell", "source_origin"]:
			var cell: Variant = recipe.get(field)
			if cell is Vector2i or cell is Vector2: recipe[field] = [cell.x, cell.y]
		recipe["region_transient"] = 1
		if not Runtime._fire_snapshot_json(recipe): return Runtime.fail("CORRUPT_REGION_DELIVERY")
		supply["delivery"] = recipe
	return Runtime.ok()

static func _valid_region_delivery(job: Dictionary, members: Dictionary) -> bool:
	if job.get("region_transient") != 1 or not _integer(job.get("player_id"), 1, 2147483647) or not _integer(job.get("representative_id"), 1, 2147483647) or not _integer(job.get("requester_id"), 1, 2147483647) or not members.has(int(job.player_id)) or not members.has(int(job.representative_id)) or not job.get("source_spec") is Dictionary or not job.get("items") is Dictionary or not _number(job.get("quantity"), 0.000001, 1000000.0) or not _number(job.get("left"), 0.0, 200002.0) or not job.get("pending") is bool or not job.get("target_location") is String:
		return false
	for field: String in ["player_hit", "target_hit", "source_version"]:
		if not _integer(job.get(field), 0, 2147483647): return false
	for field: String in ["source_cell", "target_cell"]:
		if not job.get(field) is Array or job[field].size() != 2: return false
		for value: Variant in job[field]:
			if not _integer(value, 0, 127): return false
	if not job.get("source_food") is Dictionary or not _number(job.get("source_open_amount"), 0.0, 1000000.0) or not _number(job.get("open_amount"), 0.0, float(job.quantity)): return false
	for food: Variant in job.items:
		if str(food) not in Sustain.FOODS or not _integer(job.items[food], 0, 1000000): return false
	for key: String in ["source_owner", "receiver_owner", "source_body", "receiver_body", "source_cargo", "source_holder", "source_open"]:
		if job.has(key): return false
	return Runtime._fire_snapshot_json(job)

## The original Controller reattaches all live stock/body/Node aliases only after
## candidate admission; this helper proves it kept the original paid-free recipe.
static func restore_region_deliveries(data: TerrainData, rehydrate: Callable) -> Dictionary:
	if data == null: return Runtime.fail("NO_TARGET")
	for team_id: String in data.site.get("team_supply", {}):
		var entry: Dictionary = data.site.team_supply[team_id]
		var recipe: Dictionary = entry.get("delivery", {})
		if recipe.is_empty() or recipe.get("region_transient") != 1: continue
		if not rehydrate.is_valid(): return Runtime.fail("REGION_BIND_PENDING", "原口糧交付 owner 未復原")
		var restored: Variant = rehydrate.call(int(team_id), recipe.duplicate(true))
		if not restored is Dictionary or not bool(restored.get("ok", false)) or not restored.get("job") is Dictionary: return restored if restored is Dictionary else Runtime.fail("REGION_BIND_PENDING")
		var job: Dictionary = restored.job
		for field: String in ["player_id", "representative_id", "requester_id", "source_spec", "player_hit", "target_hit", "source_version", "quantity", "left", "pending", "items", "open_amount", "target_location"]:
			if job.get(field) != recipe.get(field): return Runtime.fail("STALE_REGION_DELIVERY", field)
		for field: String in ["source_owner", "receiver_owner", "source_body", "receiver_body", "source_cargo", "source_holder", "source_open"]:
			if not job.has(field): return Runtime.fail("REGION_BIND_PENDING", field)
		entry["delivery"] = job
	return Runtime.ok()

static func _region_fire_guard(data: TerrainData, captured: Dictionary) -> Dictionary:
	if data.has_meta(&"fire_structure_step"): return Runtime.fail("BUSY", "原結構副作用執行中；沒有可保存的完整 interval")
	var boundary: Variant = data.get_meta(&"fire_boundary", {})
	if not boundary is Dictionary: return Runtime.fail("INVALID_FIRE_BARRIER")
	if boundary.is_empty(): return Runtime.fire_save_guard(data)
	var context: Dictionary = captured.get("context", {})
	var receipt: Variant = captured.get("owners", {}).get("fire_boundary_receipt", {})
	if bool(context.get("effects_complete", true)) or not bool(context.get("interval_complete", false)) or not receipt is Dictionary or receipt.size() != 6:
		return Runtime.fail("REGION_FIRE_BOUNDARY_PENDING", "原完成佇列須由同一 interval 的 owner snapshot 收據保存")
	if boundary.size() != 5 or str(boundary.get("site_id", "")) != str(data.site.id) or not boundary.get("resources") is Array or not boundary.get("features") is Array or boundary.get("flushing") != false or not Runtime._fire_time_valid(boundary.get("action_end")):
		return Runtime.fail("INVALID_FIRE_BARRIER")
	if receipt.get("site_id") != str(data.site.id) or receipt.get("token") != context.get("token") or receipt.get("action_end") != boundary.action_end or not RegionCheckpoint.time(receipt.get("action_start_cursor")) or float(receipt.action_start_cursor) > float(boundary.action_end) or receipt.get("resource_count") != boundary.resources.size() or receipt.get("feature_count") != boundary.features.size() or absf(float(boundary.action_end) - float(context.action_seconds)) > Runtime.FIRE_EPS:
		return Runtime.fail("STALE_FIRE_BOUNDARY")
	return Runtime.ok()

static func _region_capture_fire(data: TerrainData, cursor: float, captured: Dictionary) -> Dictionary:
	if data.get_meta(&"fire_boundary", {}).is_empty(): return Runtime.capture_fire_snapshot(data, cursor)
	var guarded := _region_fire_guard(data, captured)
	if not guarded.ok: return guarded
	# Same conversion and original validator as capture_fire_snapshot; the original
	# pending boundary and all live aliases remain intact for zero-time completion.
	var raw: Dictionary = data.site.get("fire", {}).duplicate(true)
	if not raw.is_empty():
		if not raw.get("receipt_ids") is Dictionary: return Runtime.fail("INVALID_FIRE_RECEIPT")
		var receipts := {}
		for identity: Variant in raw.receipt_ids:
			if not identity is int: return Runtime.fail("INVALID_FIRE_RECEIPT")
			receipts[str(identity)] = raw.receipt_ids[identity]
		raw["receipt_ids"] = receipts
	var normalized: Variant = Runtime._fire_snapshot_json_copy(raw)
	if not normalized is Dictionary or not Runtime._fire_snapshot_json(normalized): return Runtime.fail("INVALID_FIRE_SNAPSHOT")
	var checked := Runtime.validate_fire_snapshot(data, normalized, cursor)
	if not checked.ok: return checked
	return Runtime.ok("", {"state": normalized})
static func _validate_region_life_events(state: Dictionary, people: Dictionary, context: Dictionary = {}) -> Dictionary:
	if not state.has("region_life_events"): return Runtime.ok()
	var events: Variant = state.region_life_events
	if not events is Array or events.size() > 100000: return Runtime.fail("CORRUPT_REGION_LIFE_EVENT")
	if events.is_empty(): return Runtime.ok()
	var accepted: Variant = context.get("game_seconds", state.get("region_snapshot", {}).get("context", {}).get("game_seconds", state.get("simulation_settlement", {}).get("last_settled_game_seconds", -1.0)))
	if not _number(accepted, 0.0, 1000000000000.0): return Runtime.fail("REGION_LIFE_TIME_MISMATCH")
	var controlled := int(state.get("controlled_person_id", state.get("actors", {}).get("player", {}).get("person_id", -1)))
	var prior := 0
	var seen := {}
	for event: Variant in events:
		if not event is Dictionary or event.get("kind") not in ["supply_damage", "wake"] or event.size() != (10 if event.kind == "supply_damage" else 6) or not _integer(event.get("person_id"), 1, 2147483647) or not people.has(int(event.person_id)) or not _number(event.get("at"), 0.0, 1000000000000.0) or absf(float(event.at) - float(accepted)) > 0.000001 or not _integer(event.get("sequence"), 1, 2147483647) or int(event.sequence) <= prior or event.get("status") not in ["pending", "complete"] or not event.get("controlled") is bool or bool(event.controlled) != (int(event.person_id) == controlled):
			return Runtime.fail("CORRUPT_REGION_LIFE_EVENT")
		prior = int(event.sequence)
		var key := str(event.kind) + ":" + str(int(event.person_id))
		if seen.has(key): return Runtime.fail("CORRUPT_REGION_LIFE_EVENT", "duplicate original endpoint")
		seen[key] = true
		var body: Dictionary = people[int(event.person_id)]
		if bool(body.get("departed", false)) or bool(body.get("site_exited", false)): return Runtime.fail("REGION_LIFE_OWNER_MISSING")
		if event.kind == "supply_damage":
			if not event.get("death") is bool or not _number(event.get("old_hp"), 0.000001, 1000000.0) or not _number(event.get("loss"), 0.000001, 1000000.0) or not _number(event.get("ending_hp"), 0.0, float(event.old_hp)) or absf(float(event.ending_hp) - maxf(0.0, float(event.old_hp) - float(event.loss))) > 0.000001 or bool(event.death) != (float(event.ending_hp) <= 0.0) or absf(float(body.get("hp", -1.0)) - float(event.old_hp if event.status == "pending" else event.ending_hp)) > 0.000001:
				return Runtime.fail("STALE_REGION_LIFE_EVENT")
		else:
			if float(body.get("hp", 0.0)) <= 0.0 or float(body.get("ko", body.get("knockout_left", 0.0))) != 0.0 or event.status == "pending" and str(body.get("pose", "")) not in ["unconscious", "down"]:
				return Runtime.fail("STALE_REGION_WAKE_EVENT")
	return Runtime.ok()
## The original fall_record is the inclusive completion marker. Ordinary saves
## wait for its original capture owner; pending Region barriers retain it intact.
static func _region_capture_completion_guard(state: Dictionary, context: Dictionary = {}) -> Dictionary:
	var settlement: Variant = state.get("settlement", {})
	if not settlement is Dictionary: return Runtime.ok() # Original validator reports malformed records.
	var fall: Variant = settlement.get("fall_record", {})
	if not fall is Dictionary or not _number(fall.get("contest_seconds"), Settlement.CAPTURE_SECONDS, 1.0e12): return Runtime.ok()
	if context.is_empty(): return Runtime.fail("BUSY", "原聚落攻陷已達末點，須先由原 owner 結算或保存 pending Region barrier")
	var checked := RegionCheckpoint.validate_context(context)
	if not checked.ok: return checked
	if bool(context.effects_complete): return Runtime.fail("REGION_EFFECTS_PENDING", "原聚落攻陷末點尚未完成")
	return Runtime.ok()

## World identity/policy stays in the original Slot pin projection. The fixed
## terrain base remains unchanged and supplies the geography comparison only.
static func _validate_world_pin(data: TerrainData, state: Dictionary) -> Dictionary:
	var source_base: Variant = data.parameters.get("fixed_base") if data != null else null
	var declared_land: bool = source_base is Dictionary and source_base.has("land_condition_rule")
	var declared_author := RegionTerrainAdapter.has_author_identity(source_base)
	if not state.has("world_pin"):
		if declared_author: return Runtime.fail("SAVE_VERSION", "作者來源需要完整format3世界pin")
		return Runtime.fail("SAVE_VERSION", "Declared fixed land source requires the original full world pin") if declared_land else Runtime.ok()
	var pin: Variant = state.world_pin
	var base: Variant = data.parameters.get("fixed_base") if data != null else null
	if not pin is Dictionary or not base is Dictionary or base.get("base_kind") != "fixed_geography" or not _integer(pin.get("format"), 1, 3):
		return Runtime.fail("SAVE_VERSION", "Site 原世界 pin 缺少固定地理來源或版本非法")
	var author_format := int(pin.format) == 3
	if author_format != declared_author or not RegionTerrainAdapter.same_author_identity(pin, base): return Runtime.fail("SAVE_VERSION", "作者身分不能借用自然／legacy格式")
	if author_format and (not RegionTerrainAdapter.valid_author_identity(base, true) or not pin.has("technology_policy")): return Runtime.fail("SAVE_VERSION", "作者來源／政策pin不完整")
	if declared_land and ((int(pin.format) != 2 and not author_format) or not pin.has("technology_policy")):
		return Runtime.fail("SAVE_VERSION", "Declared fixed land source cannot downgrade the original world policy pin")
	const FIELDS := ["format", "world_instance_id", "slot_id", "atlas_id", "grid_contract_version", "base_revision", "manifest_sha256", "ramp_rule_revision"]
	var keys: Array = FIELDS.duplicate()
	if pin.has("resource_layer_sha256") or pin.has("resource_rule_revision"):
		keys.append("resource_layer_sha256"); keys.append("resource_rule_revision")
	if pin.has("technology_policy"): keys.append("technology_policy")
	if author_format:
		for field: String in RegionTerrainAdapter.AUTHOR_FIELDS: keys.append(field)
	if pin.size() != keys.size(): return Runtime.fail("SAVE_VERSION", "Site 原世界 pin 欄位非法")
	for key: String in keys:
		if not pin.has(key): return Runtime.fail("SAVE_VERSION", "Site 原世界 pin 欄位缺少 " + key)
	for key: String in ["world_instance_id", "slot_id"]:
		if not _world_pin_identity(pin[key]): return Runtime.fail("SAVE_VERSION", "Site 原世界與存檔身分非法")
	for key: String in ["atlas_id", "base_revision", "manifest_sha256", "ramp_rule_revision"]:
		if not pin[key] is String or str(pin[key]).is_empty() or pin[key] != base.get(key): return Runtime.fail("SAVE_VERSION", "Site 原世界地理 pin 不符 " + key)
	if str(pin.manifest_sha256).length() != 64 or not str(pin.manifest_sha256).is_valid_hex_number(false) or not _integer(pin.grid_contract_version, 1, 1000) or int(pin.grid_contract_version) != int(base.get("grid_contract_version", -1)) or str(state.get("id", "")) != str(base.get("site_id", "")) or not _same_resource_pin(pin, base):
		return Runtime.fail("SAVE_VERSION", "Site 原世界地理／資源 pin 不符")
	var policy := TechnologyPolicy.candidate(pin, int(pin.format) == 1)
	if not policy.ok: return policy
	return Runtime.ok("", {"policy": policy.policy, "legacy": bool(policy.get("legacy", false))})

static func _world_pin_identity(value: Variant) -> bool:
	if not value is String or str(value).is_empty() or str(value).length() > 64: return false
	for index: int in str(value).length():
		var code := str(value).unicode_at(index)
		if not (code >= 48 and code <= 57 or code >= 65 and code <= 90 or code >= 97 and code <= 122 or code in [45, 95]): return false
	return true
## The old physical cursor is preserved until the original boundary consumes
## its accepted effects. Only that same pending snapshot can admit the lag.
static func _region_cursor_matches_pending(cursor: float, pending: float, end: float) -> bool:
	return pending >= 0.0 and pending <= end + Runtime.FIRE_EPS and absf(cursor - pending) <= Runtime.FIRE_EPS

static func _region_pending_fire_cursor(state: Dictionary, context: Dictionary, captured_owners: Dictionary = {}) -> float:
	if context.is_empty() or bool(context.get("effects_complete", true)): return -1.0
	var owners := captured_owners
	if owners.is_empty():
		var checked := RegionCheckpoint.validate(state, state.get("region_snapshot", {}), context)
		if not checked.ok: return -1.0
		owners = checked.owners
	var receipt: Variant = owners.get("fire_boundary_receipt", {})
	if not receipt is Dictionary or receipt.size() != 6 or receipt.get("site_id") != state.get("id") or receipt.get("token") != context.get("token") or not RegionCheckpoint.time(receipt.get("action_start_cursor")) or not RegionCheckpoint.time(receipt.get("action_end")) or absf(float(receipt.action_end) - float(context.action_seconds)) > Runtime.FIRE_EPS or float(receipt.action_start_cursor) > float(receipt.action_end) or not RegionCheckpoint.integer(receipt.get("resource_count")) or not RegionCheckpoint.integer(receipt.get("feature_count")):
		return -1.0
	return float(receipt.action_start_cursor)

static func _region_scene_capture_guard(data: TerrainData, captured: Dictionary) -> Dictionary:
	var context: Dictionary = captured.get("context", {})
	var owners: Dictionary = captured.get("owners", {})
	if context.is_empty() or not owners.get("scene") is Dictionary: return Runtime.fail("REGION_SCENE_OWNER_REQUIRED")
	var codec: Variant = load("res://scripts/terrain_lab/site_region_owner_snapshot.gd")
	var reference_shape := func(key: String, kind: int) -> bool:
		return not key.is_empty() and kind in [TYPE_OBJECT, TYPE_CALLABLE, TYPE_DICTIONARY, TYPE_ARRAY]
	var shape: Dictionary = codec.validate_for_bind(owners.scene, reference_shape, context)
	if not shape.ok: return shape
	const ROOTS := ["version", "site_id", "lab", "controller", "actions", "work", "escort", "army_hot", "actor_hot", "plans", "coordinator", "registry", "fire_meta", "fatigue_work", "deliveries", "duty", "reference_objects"]
	var roots: Dictionary = shape.roots
	if roots.size() != ROOTS.size() or not RegionCheckpoint.integer(roots.get("version"), 1) or int(roots.version) != 1 or roots.get("site_id") != str(data.site.id): return Runtime.fail("INVALID_REGION_SCENE_OWNER")
	for field: String in ROOTS:
		if not roots.has(field): return Runtime.fail("INVALID_REGION_SCENE_OWNER")
	for field: String in ["lab", "controller", "actions", "work", "escort", "army_hot", "actor_hot", "plans", "coordinator", "registry", "fire_meta", "deliveries", "duty", "reference_objects"]:
		if not roots[field] is Dictionary: return Runtime.fail("INVALID_REGION_SCENE_OWNER")
	if not roots.fatigue_work is Array or not roots.actions.get("_jobs") is Dictionary or not roots.actions.get("_results") is Array or not RegionCheckpoint.integer(roots.actions.get("_next_fire_job_token"), 1) or not roots.lab.has("fire_action_cursor") or not roots.lab.has("_region_point_pending") or not roots.work.has("_working"):
		return Runtime.fail("INVALID_REGION_SCENE_OWNER")
	var original: Variant = data.get_meta(&"site_garrison_lab") if data.has_meta(&"site_garrison_lab") else null
	if original is WeakRef: original = original.get_ref()
	if original != null and is_instance_valid(original) and original.get("terrain") == data and original.has_method("capture_region_owner_state"):
		var actual: Dictionary = original.capture_region_owner_state(context)
		if not actual.ok: return actual
		if RegionCheckpoint.state_hash({"graph": actual.state}) != shape.graph_hash:
			return Runtime.fail("STALE_REGION_SCENE_OWNER")
		return Runtime.ok("", {"complete": true, "graph_hash": shape.graph_hash})
	# An unbound reserialization must retain the already validated exact graph,
	# body hash and context. It cannot stamp a new context without original owners.
	var existing := RegionCheckpoint.validate(data.site, data.site.get("region_snapshot", {}), context)
	if not existing.ok or RegionCheckpoint.state_hash({"owners": existing.owners}) != RegionCheckpoint.state_hash({"owners": owners}):
		return Runtime.fail("REGION_SCENE_OWNER_UNAVAILABLE")
	return Runtime.ok("", {"complete": true, "graph_hash": shape.graph_hash})

## Append to ORIGINAL SiteStore after the Runtime F/S fragments are merged.
## Optional absence remains legacy. Present payloads pass the original schemas.
const FS_TARGET_OPTIONALS := ["tech_fire_pot_shot", "technology_spare_repair", "settlement_work", "tech_trial", "tech_batch", "tech_work_credit", "technology_output", "technology_construction", "technology_product_id", "technology_order"]

static func _fs_vehicle_optional_count(vehicle: Dictionary) -> int:
	var count := int(vehicle.has("technology_yard_id")) + int(vehicle.has("technology_siege_method"))
	for key: String in FS_TARGET_OPTIONALS: count += int(vehicle.has(key))
	return count


static func _validate_fs_targets(data: TerrainData, state: Dictionary, people: Dictionary) -> Dictionary:
	# Runtime owns the exact target schemas. This original Store adds current
	# person and payment-holder references against the same detached state.
	var view := Env.navigation_for_state(data, state)
	var channels := Runtime.validate_irrigation_storage(view, state)
	if not channels.ok: return channels
	var water := Runtime.validate_water_schedule_storage(view, state)
	if not water.ok: return water
	for entry: Array in [["feature", state.get("features", {})], ["vehicle", state.get("vehicles", {})]]:
		for key: String in entry[1]:
			var target: Variant = entry[1][key]
			if not target is Dictionary: return Runtime.fail("CORRUPT_TECHNOLOGY", "原目標格式")
			var checked := Runtime.validate_technology_target_storage(view, key, target, str(entry[0]))
			if not checked.ok: return checked
			var project_checked := Runtime.validate_technology_trial_project_storage(view, target)
			if not project_checked.ok: return project_checked
			if target.has("settlement_work"):
				var order: Dictionary = state.settlement.technology_operations.orders[target.settlement_work.order_id]
				if not people.has(int(order.paid.operator_id)): return Runtime.fail("CORRUPT_TECHNOLOGY", "原活動防禦清單人物不存在")
			if target.has("tech_fire_pot_shot"):
				if str(entry[0]) != "vehicle": return Runtime.fail("CORRUPT_SAVE")
				var shot := _validate_fire_pot_shot_record(data, state, target, people)
				if not shot.ok: return shot
			if target.has("tech_trial") and not people.has(int(target.tech_trial.person.person_id)):
				return Runtime.fail("CORRUPT_TECHNOLOGY", "原具名試作人物引用")
			if target.has("tech_batch"):
				var batch: Dictionary = target.tech_batch
				if int(batch.operator_id) > 0 and not people.has(int(batch.operator_id)): return Runtime.fail("CORRUPT_TECHNOLOGY", "原活動批次人物不存在")
				if not Runtime.validate_technology_ledger_source(view, target, batch):
					return Runtime.fail("CORRUPT_TECHNOLOGY", "原付款來源持有人引用")
	return Runtime.ok()


static func _fs_serial_text(value: String) -> bool:
	return value.is_valid_int() and str(int(value)) == value and _integer(int(value), 1, 2147483646)

static func _valid_fs_construction(event: Variant, kind: String, key: String) -> bool:
	const FIELDS := ["id", "site_id", "target_id", "operator_id", "binding", "work_seconds", "item_ids", "outputs", "materials"]
	if not Technology.keys(event, FIELDS) or not event.id is String or str(event.id).is_empty() or not event.site_id is String or str(event.site_id).is_empty() \
		or not event.target_id is String or not str(event.target_id).begins_with(kind + ":") or not _fs_serial_text(str(event.target_id).trim_prefix(kind + ":")) \
		or not _integer(event.operator_id, 1, 2147483646) or not event.binding is String or str(event.binding).is_empty() \
		or not _number(event.work_seconds, 0.000000001, 1.0e12) or not event.item_ids is Array or not event.item_ids.is_empty() \
		or not event.outputs is Dictionary or not event.outputs.is_empty() or not Technology.material_stack(event.materials): return false
	# A completed vehicle may travel and receive a new local ID. Its immutable
	# source site/target payment witness remains historical lineage.
	return kind == "vehicle" or str(event.target_id) == kind + ":" + key

static func _normalize_fs_targets(state: Dictionary) -> void:
	# Raw payloads have already passed validation. Canonicalization creates no
	# missing optional record and preserves the original immutable lineage.
	for entry: Dictionary in [state.get("features", {}), state.get("vehicles", {})]:
		for target: Dictionary in entry.values(): Runtime.normalize_technology_target_storage(target)


static func _normalize_fs_token(token: Dictionary) -> void:
	for field: String in ["project_id", "epoch", "attempt"]: token[field] = int(token[field])
	token.person.person_id = int(token.person.person_id)
	for resource: String in token.materials: token.materials[resource] = int(token.materials[resource])

static func _validate_unadmitted_social_state(state: Dictionary) -> Dictionary:
	var actors: Variant = state.get("actors", {})
	if actors is Dictionary:
		for body: Variant in actors.values():
			if body is Dictionary and body.has("social_state") and not TerrainTestCharacter.PersonSocial.valid(body.social_state):
				return Runtime.fail("SAVE_VERSION", "Actor social_state 尚未准入；完整原檔與原現場保留")
	var armies: Variant = state.get("armies", [])
	if armies is Array:
		for army: Variant in armies:
			if not army is Dictionary: continue
			var units: Variant = army.get("units", [])
			if not units is Array: continue
			for body: Variant in units:
				if body is Dictionary and body.has("social_state") and not TerrainTestCharacter.PersonSocial.valid(body.social_state):
					return Runtime.fail("SAVE_VERSION", "Army person social_state 尚未准入；完整原檔與原現場保留")
	return Runtime.ok()


static func _validate_fire_pot_shot_record(data: TerrainData, state: Dictionary, vehicle: Dictionary, people: Dictionary) -> Dictionary:
	var proof: Variant = vehicle.get("tech_fire_pot_shot")
	var fields := ["version", "token", "attack_id", "projectile_id", "payment_id", "phase", "unit_key", "generation", "scorch", "impact_action"]
	if not proof is Dictionary or proof.size() != fields.size(): return Runtime.fail("CORRUPT_SAVE", "原火罐發射收據欄位")
	for key: String in fields:
		if not proof.has(key): return Runtime.fail("CORRUPT_SAVE")
	var view := Env.navigation_for_state(data, state)
	if not _integer(proof.version, 1, 1) or not Runtime.siege_ammo_valid(str(vehicle.kind), "fire_pot") \
		or not Runtime._technology_trial_shape(proof.token, view) or proof.token.get("scope") != "family" or proof.token.get("tech_id") != "F15" \
		or proof.token.get("binding") != "fire_pot_shot" or proof.token.get("target_id") != "vehicle:" + str(vehicle.id) \
		or not people.has(int(proof.token.person.person_id)) or not _integer(proof.projectile_id, 1, 2147483647) \
		or not proof.payment_id is String or proof.payment_id.is_empty() or proof.phase not in ["flight", "miss", "contact", "complete"] \
		or not proof.unit_key is String or not _integer(proof.generation, 0, 2147483647) or not _number(proof.scorch, 0.0, 1.0) \
		or not _number(proof.impact_action, 0.0, 1000000000.0) or not proof.attack_id is String: return Runtime.fail("CORRUPT_SAVE", "原火罐發射身分／數值")
	var prefix := str(state.id) + "|" + str(vehicle.id) + "|"
	if not proof.attack_id.begins_with(prefix) or not proof.attack_id.trim_prefix(prefix).is_valid_int() \
		or proof.attack_id != prefix + str(int(proof.attack_id.trim_prefix(prefix))) \
		or not _integer(int(proof.attack_id.trim_prefix(prefix)), 1, int(vehicle.next_attack_seq) - 1): return Runtime.fail("CORRUPT_SAVE")
	if proof.phase in ["contact", "complete"] and (proof.unit_key.is_empty() or int(proof.generation) < 1): return Runtime.fail("CORRUPT_SAVE")
	if proof.phase in ["flight", "miss"] and (not proof.unit_key.is_empty() or int(proof.generation) != 0 or float(proof.scorch) != 0.0): return Runtime.fail("CORRUPT_SAVE")
	var family: Dictionary = state.get("family", {})
	var raw: Dictionary = family.get("technology", {})
	if not Technology.valid_scope_record(raw, "family") or family.get("family_id") != proof.token.scope_id: return Runtime.fail("CORRUPT_SAVE")
	var found := false
	var completed := false
	for project: Dictionary in raw.projects:
		if int(project.id) != int(proof.token.project_id) or project.tech_id != "F15" or project.purpose != proof.token.purpose: continue
		for payment: Dictionary in project.budget.get("payments", []):
			if payment.payment_id == proof.payment_id and int(payment.attempt) == int(proof.token.attempt) and payment.phase_id == proof.token.phase_id \
				and payment.target_id == proof.token.target_id and Technology.same_person_ref(payment.person, proof.token.person, raw.get("person_links", [])) \
				and Technology.material_equal(payment.materials, {"fire_pot": 1}): found = true
		for receipt: Dictionary in project.receipts:
			if receipt.payment_id == proof.payment_id and int(receipt.attempt) == int(proof.token.attempt) \
				and receipt.phase_id == proof.token.phase_id and int(receipt.person_id) == int(proof.token.person.person_id) \
				and receipt.site_id == str(state.id) and receipt.event_id == "F15:shot:" + str(proof.attack_id): completed = true
	if not found: return Runtime.fail("CORRUPT_SAVE", "原火罐發射缺一次真付款")
	if completed != (proof.phase == "complete"): return Runtime.fail("CORRUPT_SAVE", "原火罐完成須對應同一次真接觸後收據")
	return Runtime.ok()

# Derived plain facts only; this writer owner never references RegionSaveSlot.
static var faction_summary_cache: Dictionary = {}
static var faction_summary_memo: Dictionary = {}
static var faction_summary_metadata: Dictionary = {}
static var _faction_summary_mutex: Mutex = Mutex.new()
static var _faction_summary_serial: int = 0

static func faction_summary_path(path: String) -> String:
	var absolute: String = ProjectSettings.globalize_path(path).simplify_path()
	return absolute.to_lower() if OS.has_feature("windows") else absolute

static func faction_summary_serial() -> int:
	_faction_summary_mutex.lock()
	var serial: int = _faction_summary_serial
	_faction_summary_mutex.unlock()
	return serial

static func invalidate_faction_summary_path(path: String) -> void:
	var absolute: String = faction_summary_path(path)
	_faction_summary_mutex.lock()
	_faction_summary_serial += 1
	for key: Variant in faction_summary_cache.keys():
		var metadata: Variant = faction_summary_metadata.get(key)
		if not metadata is Dictionary or metadata.get("site_path") == absolute:
			faction_summary_cache.erase(key)
			faction_summary_memo.erase(key)
			faction_summary_metadata.erase(key)
	_faction_summary_mutex.unlock()

static func clear_faction_summary_cache() -> void:
	_faction_summary_mutex.lock()
	faction_summary_cache.clear()
	faction_summary_memo.clear()
	faction_summary_metadata.clear()
	_faction_summary_serial += 1 # Prevent an in-flight old validation repopulating cleared facts.
	_faction_summary_mutex.unlock()
