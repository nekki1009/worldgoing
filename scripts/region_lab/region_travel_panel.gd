extends VBoxContainer
## Region-map controls for a travelling party (R1). The map stays a viewer; this
## panel supplies travel intent and real-time input. The original Slot owns the
## one world clock and every committed interval or checkpoint.

const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
const SPEEDS: Array[float] = [0.5, 1.0, 2.0, 4.0, 8.0, 16.0] # TC2 (T2 A): travel also ×8 / ×16
const CHECKPOINT_REAL_SECONDS := 5.0
const SITE_SCENE := "res://scenes/terrain_lab/TerrainLab.tscn"

var map: Control
var slot: RegionSaveSlot
var world_id := ""
var slot_id := ""
var manifest := ""
var running := false
var speed := 1.0
var preview: Array = []
var preview_target := Vector2i(-1, -1)
var party_summary := ""
var _accumulated := 0.0
var _since_checkpoint := 0.0
var _route_thread: Thread
var _route_search: RegionRoute.Search
var _route_source: RegionData
var _arriving := false
var _info: Label
var _clock: Label
var _status: Label
var _plan_button: Button
var _go_button: Button
var _pause_button: Button
var _retry_button: Button
var _mode_button: Button
var _toll_row: HBoxContainer
var _toll_pay_button: Button
var _toll_fight_button: Button
var _toll_flee_button: Button
var _toll_event := ""
var _toll_error := ""
var _speed_buttons: Array[Button] = []
var _reroute_after_leg := false
var _reroute_target := Vector2i.ZERO
var _mode_after_leg := false
var _original_adapter_host: Node
var _owns_original_adapter_host := false

func setup(owner_map: Control) -> void:
	map = owner_map
	name = "RegionTravelPanel"
	add_theme_constant_override("separation", 8)
	var title := Label.new()
	title.text = "旅隊"
	title.add_theme_font_size_override("font_size", 30)
	add_child(title)
	_clock = Label.new()
	_clock.name = "TravelClock"
	add_child(_clock)
	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.add_theme_font_size_override("font_size", 20)
	add_child(_info)
	_plan_button = _button("規劃到所選地點", "PlanTravelRoute", plan_to_selected)
	var row := HBoxContainer.new()
	add_child(row)
	_go_button = _button("出發", "StartTravel", start_moving, row)
	_pause_button = _button("暫停", "PauseTravel", pause_moving, row)
	_retry_button = _button("重試入界", "RetryTravelArrival", retry_arrival)
	_mode_button = _button("在此停靠／上下船", "TravelModeStop", mode_stop)
	# Bandit B4c: shown only while a band holds the party for a toll.
	_toll_row = HBoxContainer.new()
	_toll_row.name = "TravelToll"
	_toll_row.visible = false
	add_child(_toll_row)
	_toll_pay_button = _button("付買路錢", "TravelTollPay", answer_toll.bind(true), _toll_row)
	_toll_fight_button = _button("不付，開打", "TravelTollFight", answer_toll.bind(false), _toll_row)
	_toll_flee_button = _button("逃", "TravelTollFlee", flee_toll, _toll_row)
	var speeds := HBoxContainer.new()
	add_child(speeds)
	for value: float in SPEEDS:
		var button := _button("×%s" % ("0.5" if value == 0.5 else str(int(value))), "TravelSpeed%d" % int(value * 10), set_speed.bind(value), speeds)
		_speed_buttons.append(button)
	_button("保存並回主選單", "TravelToMainMenu", leave_to_menu)
	_status = Label.new()
	_status.name = "TravelStatus"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 20)
	add_child(_status)

func _button(text: String, node_name: String, action: Callable, parent: Node = self) -> Button:
	var button := Button.new()
	button.text = text
	button.name = node_name
	button.pressed.connect(action)
	parent.add_child(button)
	return button

## Opens the travelling world's slot. Returns the party's current Site.
func start(view: Dictionary) -> Dictionary:
	world_id = str(view.get("world_id", ""))
	slot_id = str(view.get("slot_id", RegionEntry.SLOT))
	manifest = str(view.get("manifest", RegionData.DEFAULT_MANIFEST))
	if manifest.is_empty(): manifest = RegionData.DEFAULT_MANIFEST
	var source := RegionData.new()
	var loaded := source.load_manifest(manifest)
	if not loaded.ok: return _fail(loaded)
	slot = RegionSaveSlot.new()
	var opened := slot.open_map(source, world_id, slot_id)
	if not opened.ok: return _fail(opened)
	var status := slot.region_travel_status()
	if not status.ok: return _fail(status)
	if not bool(status.get("pending", false)): return _fail({"message": "此世界沒有在途旅隊"})
	_route_source = RegionData.new()
	_route_source.load_manifest(manifest)
	var party := slot.region_travel_party()
	if not party.ok: return _fail(party)
	var hosted := _ensure_original_adapter_host(party.party)
	if not hosted.ok: return _fail(hosted)
	var census := RegionTravel.census(party.party)
	party_summary = "%d 人・%d 輛車・%.1f 公里／時" % [census.people.size(), census.vehicles.size(), float(party.party.speed_mps) * 3.6]
	_record_world(status.site)
	_refresh()
	if bool(status.arrived): _status.text = "已抵達目的地；按「出發」進入地點。"
	elif bool(status.moving): _status.text = "旅程暫停中；按「出發」繼續，或選新地點改道。"
	else: _status.text = "在地圖上點選目的地，再按「規劃到所選地點」。"
	return {"ok": true, "site": status.site}

func _ensure_original_adapter_host(party: Dictionary) -> Dictionary:
	# A live Callable is insufficient proof after a scene handoff. The host
	# itself must hold the complete original marker-selected graph for this Slot.
	var handle: Variant = slot.get_meta(&"region_original_adapter_host") if slot.has_meta(&"region_original_adapter_host") else null
	var existing: Node = handle.get_ref() if handle is WeakRef else null
	if is_instance_valid(existing) and existing.is_inside_tree() and existing.site_controller.region_slot == slot:
		var receipt: Dictionary = existing.region_bind_receipt(existing.terrain)
		if receipt.get("complete", false):
			_original_adapter_host = existing
			return {"ok": true, "receipt": receipt}
	if is_instance_valid(existing): return {"ok": false, "code": "STALE_REGION_ADAPTER_HOST", "message": "原adapter host仍有未完成graph；保留原owner待重試"}
	var prefix := str(slot.pin.atlas_id) + ":"
	var identity := str(party.get("origin_site_id", ""))
	if not identity.begins_with(prefix): return {"ok": false, "code": "WRONG_SITE"}
	var parts := identity.trim_prefix(prefix).split(":")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int(): return {"ok": false, "code": "WRONG_SITE"}
	var coordinate := Vector2i(int(parts[0]), int(parts[1]))
	if RegionGrid.site_id(str(slot.pin.atlas_id), coordinate) != identity: return {"ok": false, "code": "WRONG_SITE"}
	var selected := slot.effective_site_path(coordinate)
	if not selected.ok: return selected
	# Read the selected source epoch. Catch-up remains the original shared-step
	# adapter's work after wiring, never the host constructor's second clock.
	var opened := slot._load_checked(str(selected.path), coordinate)
	if not opened.ok: return opened
	var scene: PackedScene = load(SITE_SCENE)
	if scene == null: return {"ok": false, "code": "MISSING_ORIGINAL_SCENE"}
	var original: Node = scene.instantiate()
	original.restore_only = true
	original.visible = false
	original.pause_when_unfocused = false
	original.process_mode = Node.PROCESS_MODE_DISABLED
	if opened.data.site.get("actors", {}).has("npc"): original.npc = TerrainTestNPC.new()
	add_child(original)
	original.site_controller.region_slot = slot
	original.site_controller._auto_save_blocked = true
	var restored: Dictionary = original.restore_original_site(opened.data)
	if not restored.get("ok", false) or not original.region_bind_receipt(original.terrain).get("complete", false):
		original.free()
		return restored if not restored.get("ok", false) else {"ok": false, "code": "REGION_BIND_INCOMPLETE"}
	if not original.has_method("_wire_region_gameplay_adapters"):
		original.free()
		return {"ok": false, "code": "MISSING_REGION_ADAPTER", "message": "原完整Lab adapter尚未接入"}
	_original_adapter_host = original
	_owns_original_adapter_host = true
	slot.set_meta(&"region_original_adapter_host", weakref(original))
	for property: Dictionary in slot.get_property_list():
		if str(property.name) == "_region_original_labs":
			slot.get("_region_original_labs")[identity] = original
	var wired: Dictionary = original.call("_wire_region_gameplay_adapters", slot)
	if not wired.get("ok", false):
		_release_original_adapter_host()
		return wired
	var requested_mode := str(slot.region_registry().modes.get(identity, {}).get("mode", "cold_exact"))
	if requested_mode not in ["cold_exact", "formula_active"]: requested_mode = "cold_exact"
	var admitted: Dictionary = original._region_gameplay_owner_lab(identity, requested_mode)
	if not admitted.get("ok", false):
		_release_original_adapter_host()
		return admitted
	return {"ok": true, "receipt": original.region_bind_receipt(original.terrain)}

func _release_original_adapter_host() -> void:
	if not _owns_original_adapter_host or not is_instance_valid(_original_adapter_host): return
	var original := _original_adapter_host
	if slot != null:
		for property: Dictionary in slot.get_property_list():
			var field := str(property.name)
			var value: Variant = slot.get(field)
			if value is Callable:
				var owner: Object = value.get_object()
				if owner is Node and (owner == original or original.is_ancestor_of(owner)): slot.set(field, Callable())
			elif field in ["_region_original_labs", "_region_party_original_labs"] and value is Dictionary:
				for key: Variant in value.keys():
					var owner: Variant = value[key]
					if owner is Node and is_instance_valid(owner) and (owner == original or original.is_ancestor_of(owner)): value.erase(key)
		var handle: Variant = slot.get_meta(&"region_original_adapter_host") if slot.has_meta(&"region_original_adapter_host") else null
		if handle is WeakRef and handle.get_ref() == original: slot.remove_meta(&"region_original_adapter_host")
		var parties: Dictionary = slot.get_meta(&"region_party_owner_labs", {})
		for token: Variant in parties.keys():
			var owner: Variant = parties[token]
			if owner is Node and is_instance_valid(owner) and (owner == original or original.is_ancestor_of(owner)): parties.erase(token)
	_original_adapter_host = null
	_owns_original_adapter_host = false
	original.free()

func _fail(result: Dictionary) -> Dictionary:
	_status.text = "旅隊資料無法開啟：" + str(result.get("message", result.get("code", "未知錯誤")))
	_plan_button.disabled = true
	_go_button.disabled = true
	return {"ok": false, "message": _status.text}

func status() -> Dictionary:
	return slot.region_travel_status() if slot != null else {"ok": false}

func set_speed(value: float) -> void:
	_accumulated = 0.0
	speed = value
	_refresh()

func plan_to_selected() -> void:
	if slot == null or _route_thread != null: return
	var target: Vector2i = _reroute_target if _reroute_after_leg else map.selected_site
	_reroute_after_leg = false
	var current := status()
	if not current.ok: return
	if running: pause_moving()
	_accumulated = 0.0
	if bool(current.get("moving", false)) or bool(current.get("arrived", false)):
		var stopped := slot.stop_region_travel()
		if not stopped.ok: _status.text = str(stopped.get("message", "改道尚未停止")); return
		if bool(stopped.get("pending", false)):
			_reroute_after_leg = true
			_reroute_target = target
			running = true
			_status.text = "完成目前原航段後改道；已保留未完船步。"
			_refresh()
			return
		current = status()
	var party := slot.region_travel_party()
	if not party.ok: _status.text = str(party.get("message", "原旅隊尚未讀取")); return
	var prepared := slot.prepare_region_route_context(null, party.party)
	if not prepared.ok: _status.text = str(prepared.get("message", "原有效導航尚未準備")); return
	_route_search = RegionRoute.Search.new()
	_route_search.source = _route_source
	_route_search.start_site = current.site
	_route_search.start_component = int(current.component)
	_route_search.goal_site = target
	_route_search.context = prepared.context
	if not current.get("vehicle_poses", {}).is_empty(): _route_search.context.capabilities.vehicle_poses = current.vehicle_poses.duplicate(true)
	preview_target = target
	preview = []
	_route_thread = Thread.new()
	_route_thread.start(_route_search.run)
	_status.text = "依實際地形計算路線中…"
	_refresh()

func _finish_route() -> void:
	var result: Dictionary = _route_thread.wait_to_finish()
	_route_thread = null
	if not result.ok:
		_status.text = "無法規劃路線：" + str(result.get("message", result.get("code", "")))
		preview = []
	else:
		preview = result.steps
		if result.has("action_steps"):
			_status.text = "航線 %.1f 公里，經過 %d 個地點。按「出發」沿此航線前進。" % [float(result.metres) / 1000.0, preview.size()]
		else:
			var party := slot.region_travel_party()
			var mps := maxf(0.001, float(party.party.speed_mps)) if party.ok else RegionTravel.WALK_MPS
			_status.text = "路線 %.1f 公里，約 %s（地形換算後），檢查 %d 個地點。按「出發」沿此路線前進。" % [float(result.metres) / 1000.0, _duration(float(result.metres) / mps), int(result.site_builds)]
	_refresh()
	map.get("_overlay").queue_redraw()

func start_moving() -> void:
	if slot == null or _arriving: return
	var current := status()
	if not current.ok: return
	if not preview.is_empty():
		if bool(current.moving) or bool(current.arrived):
			var stopped := slot.stop_region_travel()
			if not stopped.ok: _status.text = str(stopped.message); return
			current = status()
		var first: Dictionary = preview[0]
		if Vector2i(int(first.site[0]), int(first.site[1])) != current.site or int(first.component) != int(current.component):
			_status.text = "旅隊位置已改變；請重新規劃路線。"
			preview = []
			_refresh()
			return
		var planned := slot.set_region_travel_plan(preview)
		if not planned.ok:
			_status.text = "路線未採用：" + str(planned.message)
			return
		preview = []
	elif bool(current.arrived):
		arrive()
		return
	elif not bool(current.moving):
		_status.text = "先選目的地並規劃路線。"
		return
	running = true
	_accumulated = 0.0
	_status.text = "行進中；時間流動。"
	_refresh()

## Bandit B4c: the player's answer to the band that holds the party (pay = pass, refuse = the ordinary encounter).
func answer_toll(pay: bool) -> void:
	if slot == null or _arriving or _toll_event.is_empty(): return
	var answered: Dictionary = slot.answer_region_toll(_toll_event, pay)
	if not answered.ok:
		_toll_error = "買路錢未處理：%s %s" % [str(answered.get("code", "")), str(answered.get("message", ""))]
		_refresh()
		return
	_toll_event = ""
	_toll_error = ""
	if pay:
		var parts: Array[String] = []
		for food: String in answered.get("paid", {}): parts.append("%s %d" % [food, int(answered.paid[food])])
		_status.text = "已付買路錢（%s）；該伙 3 日內不再攔這支隊伍。可繼續行進。" % "、".join(parts)
	else:
		# The encounter takes the party off the map; _process enters the materialised Site.
		_status.text = "拒付買路錢；與土匪交戰。"
		_toll_row.visible = false
		return
	_refresh()

## Bandit B4c: the party tries to outrun the band; a slower party is caught and fights.
func flee_toll() -> void:
	if slot == null or _arriving or _toll_event.is_empty(): return
	var answered: Dictionary = slot.flee_region_toll(_toll_event)
	if not answered.ok:
		_toll_error = "逃跑未處理：%s %s" % [str(answered.get("code", "")), str(answered.get("message", ""))]
		_refresh()
		return
	_toll_event = ""
	_toll_error = ""
	if str(answered.get("toll", "")) == "fled":
		_status.text = "甩開了土匪；可繼續行進（他們之後仍可能再攔）。"
		_refresh()
		return
	_status.text = "沒跑掉；與土匪交戰。"
	_toll_row.visible = false

func pause_moving() -> void:
	_accumulated = 0.0
	if not running: return
	running = false
	_checkpoint()
	_status.text = "已暫停；時間停止。"
	_refresh()

func retry_arrival() -> void:
	if slot == null or _arriving or not slot.has_method("retry_region_arrival"): return
	running = false
	_accumulated = 0.0
	var ready: Dictionary = slot.call("retry_region_arrival", {})
	if not ready.ok:
		_status.text = "入界仍受阻：" + str(ready.get("message", ready.get("code", "")))
		_refresh()
		return
	arrive()

func mode_stop() -> void:
	if slot == null or _arriving or not slot.has_method("prepare_region_mode_stop"): return
	running = false
	_accumulated = 0.0
	preview = []
	var selected: Dictionary = slot.region_travel_party()
	if not selected.ok: _fail(selected); return
	if str(selected.party.upkeep.get("live", {}).get("upkeep", "")) == "mapBody":
		_return_original_body_mode(selected.party)
		return
	var ready: Dictionary = slot.call("prepare_region_mode_stop")
	if not ready.ok:
		_status.text = "尚未停靠：" + str(ready.get("message", ready.get("code", "")))
		_refresh()
		return
	if bool(ready.get("pending", false)):
		_mode_after_leg = true
		running = true
		_status.text = str(ready.get("message", "完成原航段後停靠。"))
		_refresh()
		return
	_mode_after_leg = false
	arrive()

func _checkpoint() -> void:
	_since_checkpoint = 0.0
	var saved := slot.checkpoint_region_travel()
	if not saved.ok:
		running = false
		_status.text = "旅程保存失敗，已暫停：" + str(saved.message)
		return
	_record_world(status().get("site", Vector2i(-1, -1)))

func _record_world(site: Vector2i) -> void:
	if world_id.is_empty(): return
	var day := floori(float(slot.control.logical_game_seconds) / 86400.0) + 1
	RegionEntry.record_world(world_id, slot_id, manifest, site, day)

func _process(delta: float) -> void:
	if slot != null and slot.has_meta(&"region_player_materialized") and not _arriving:
		_enter_materialized_player_site.call_deferred()
		return
	if _route_thread != null and not _route_thread.is_alive(): _finish_route()
	elif _route_thread != null and _route_search != null:
		_status.text = "依實際地形計算路線中…已檢查 %d 個地點" % _route_search.builds
	if not running or slot == null: return
	_accumulated += delta * RegionTravel.GAME_SECONDS_PER_REAL * speed
	var whole := floori(_accumulated / RegionTravel.step_game_seconds())
	if whole > 0:
		var advanced := slot.advance_region_travel(whole)
		if not advanced.ok:
			running = false
			_accumulated = 0.0
			_status.text = "旅程時間無法推進：" + str(advanced.get("message", ""))
			return
		_accumulated = maxf(0.0, _accumulated - float(advanced.get("advanced", float(advanced.steps) * RegionTravel.step_game_seconds())))
		if bool(advanced.get("discard_accumulator", false)): _accumulated = 0.0
		if bool(advanced.get("reroute_ready", false)):
			running = false
			_accumulated = 0.0
			_checkpoint()
			if _mode_after_leg: mode_stop.call_deferred()
			elif _reroute_after_leg: plan_to_selected.call_deferred()
		if bool(advanced.get("barrier", false)):
			running = false
			_accumulated = 0.0
			_checkpoint()
			_status.text = "旅隊事件待處理；航段與未完船步已保存。"
		if bool(advanced.get("blocked", false)):
			running = false
			_accumulated = 0.0
			_checkpoint()
			_status.text = "旅隊已停下：" + str(advanced.get("message", advanced.get("reason", "入口條件已改變；可重新規劃路線")))
		elif bool(advanced.get("resting", false)):
			_status.text = "旅隊休息中；仍沿原時間與供養結算，恢復後續行。"
		if bool(advanced.arrived):
			running = false
			_accumulated = 0.0
			_checkpoint()
			_status.text = "抵達目的地。"
			arrive.call_deferred()
	_since_checkpoint += delta
	if _since_checkpoint >= CHECKPOINT_REAL_SECONDS: _checkpoint()
	_refresh()
	map.get("_overlay").queue_redraw()

## Enter the destination Site: the main scene opens the world and commits arrival.
func _enter_materialized_player_site() -> void:
	if _arriving or slot == null or not slot.has_meta(&"region_player_materialized"): return
	var selected: Variant = slot.get_meta(&"region_player_materialized")
	if not selected is Dictionary or not selected.get("site") is Vector2i \
			or int(selected.get("generation", -1)) != int(slot._marker.get("generation", 0)):
		running = false
		_status.text = "玩家已入界；仍須選定原世代完整綁定。"
		return
	_arriving = true
	running = false
	_accumulated = 0.0
	_record_world(selected.site)
	RegionEntry.pending = {"manifest": manifest, "world_id": world_id, "slot_id": slot_id,
		"site": selected.site, "create_new": false}
	RegionEntry.view = {}
	var changed := get_tree().change_scene_to_file(SITE_SCENE)
	if changed != OK:
		_arriving = false
		_status.text = "原玩家地點已提交；場景待真完整重綁，可重試。"
		_refresh()

func arrive() -> void:
	if _arriving: return
	var current := status()
	if not current.ok or not bool(current.get("arrived", false)): return
	_arriving = true
	_accumulated = 0.0
	RegionEntry.pending = {"manifest": manifest, "world_id": world_id, "slot_id": slot_id,
		"site": current.site, "create_new": false}
	RegionEntry.view = {}
	var changed := get_tree().change_scene_to_file(SITE_SCENE)
	if changed != OK:
		_arriving = false
		_status.text = "地點場景尚未開啟；可重試或重新規劃路線。"
		_refresh()

func leave_to_menu() -> void:
	if running: pause_moving()
	elif slot != null: _checkpoint()
	RegionEntry.view = {}
	get_tree().change_scene_to_file(RegionEntry.MAIN_MENU)

func _exit_tree() -> void:
	if _route_thread != null:
		if _route_search != null: _route_search.cancelled = true
		_route_thread.wait_to_finish()
		_route_thread = null
	if running and slot != null and not _arriving: slot.checkpoint_region_travel()
	_release_original_adapter_host()

static func _duration(seconds: float) -> String:
	var minutes := roundi(seconds / 60.0)
	return "%d 小時 %d 分" % [minutes / 60, minutes % 60] if minutes >= 60 else "%d 分" % minutes

func _refresh() -> void:
	if slot == null: return
	var current := status()
	if not current.ok: return
	var now := float(slot.control.logical_game_seconds)
	var party := slot.region_travel_party()
	if party.ok:
		var census := RegionTravel.census(party.party)
		if str(party.party.get("mode", "land")) == "sea": party_summary = "%d 人・%d 艘船（海路）" % [census.people.size(), census.vehicles.size()]
		else: party_summary = "%d 人・%d 輛車・%.1f 公里／時（陸路）" % [census.people.size(), census.vehicles.size(), float(party.party.get("speed_mps", 0.0)) * 3.6]
	var minute := floori(now / 60.0)
	_clock.text = "%s　速度 ×%s%s" % [preload("res://scripts/terrain_lab/site_calendar.gd").clock_text(float(minute)),
		"0.5" if speed == 0.5 else str(int(speed)), "　（行進中）" if running else "　（暫停）"]
	var lines: Array[String] = [party_summary, "位置：Site %d, %d" % [current.site.x, current.site.y]]
	if current.has("destination"):
		lines.append("目的地：Site %d, %d" % [current.destination.x, current.destination.y])
		if bool(current.arrived): lines.append("已抵達")
		elif bool(current.get("eta_pending", false)): lines.append("剩餘航程：%.1f 公尺；船員與休息狀態隨航程更新。" % float(current.get("remaining_metres", 0.0)))
		else: lines.append("剩餘：%s" % _duration(float(current.remaining_game_seconds)))
	if not preview.is_empty():
		lines.append("預覽路線：%d 個地點" % preview.size())
	var known := slot.region_player_known_intel()
	if known.is_empty(): lines.append("情報：尚無有效回報")
	else:
		var keys: Array = known.keys()
		keys.sort()
		for object: String in keys:
			var receipt: Dictionary = known[object]
			lines.append("回報：%s（觀察於 %s；收到於 %s）" % [slot.region_known_intel_label(receipt), _duration(float(receipt.game_time)), _duration(float(receipt.get("received_at", receipt.game_time)))])
	_info.text = "\n".join(lines)
	for index: int in range(_speed_buttons.size()):
		_speed_buttons[index].disabled = SPEEDS[index] == speed
	_plan_button.disabled = _route_thread != null or _arriving
	_go_button.text = "進入目的地" if bool(current.arrived) else ("出發" if not bool(current.moving) or not preview.is_empty() else "繼續")
	_go_button.disabled = running or _arriving or _route_thread != null or not bool(current.arrived) and not bool(current.moving) and preview.is_empty()
	_pause_button.disabled = not running
	_retry_button.disabled = not bool(current.get("arrived", false)) or _arriving or not slot.has_method("retry_region_arrival")
	_mode_button.disabled = _arriving or _route_thread != null or not slot.has_method("prepare_region_mode_stop")
	var toll: Dictionary = slot.region_toll_pending() if slot.has_method("region_toll_pending") else {"ok": true, "offer": false}
	var held: bool = toll.get("ok", false) and bool(toll.get("offer", false))
	_toll_row.visible = held
	_toll_event = str(toll.get("event_id", "")) if held else ""
	if held:
		running = false
		_toll_pay_button.text = "付買路錢（%d 糧）" % int(toll.fee)
		_toll_pay_button.disabled = _arriving or not bool(toll.can_pay)
		_toll_fight_button.disabled = _arriving
		_toll_flee_button.disabled = _arriving
		_go_button.disabled = true
		_status.text = "%s %d 人攔路，索要買路錢 %d 糧（隊伍存糧 %d）。付了放行，3 日內不再攔；不付就開打；比土匪快才逃得掉。" % [str(toll.band_name), int(toll.band_people), int(toll.fee), int(toll.food)]
		if not _toll_error.is_empty(): _status.text += "\n" + _toll_error
	_mode_button.text = "回到原旅隊實體操作" if party.ok and str(party.party.upkeep.get("live", {}).get("upkeep", "")) == "mapBody" else "在此停靠／上下船"

func _site_center(site: Variant) -> Vector2:
	var coordinate := Vector2i(int(site[0]), int(site[1])) if site is Array else Vector2i(site)
	return map.call("_site_rect", coordinate).get_center()

## Draw the party, its committed route and any preview on the map overlay.
func draw_on(canvas: Control) -> void:
	if slot == null: return
	var current := status()
	if not current.ok: return
	var plan: Dictionary = current.get("plan", {})
	var party_point := _site_center(current.site)
	if not plan.is_empty():
		var points := PackedVector2Array()
		for step: Dictionary in plan.steps: points.append(_site_center(step.site))
		if points.size() >= 2: canvas.draw_polyline(points, Color(1.0, 0.78, 0.3, 0.9), 3.0)
		var index := int(current.step_index)
		if bool(current.moving) and index + 1 < plan.steps.size():
			party_point = _site_center(plan.steps[index].site).lerp(_site_center(plan.steps[index + 1].site), float(current.fraction))
		canvas.draw_circle(_site_center(plan.steps.back().site), 7.0, Color(1.0, 0.45, 0.25))
	if not preview.is_empty():
		var points := PackedVector2Array()
		for step: Dictionary in preview: points.append(_site_center(step.site))
		if points.size() >= 2: canvas.draw_polyline(points, Color(0.55, 0.9, 1.0, 0.85), 2.0)
		canvas.draw_circle(points[points.size() - 1], 6.0, Color(0.55, 0.9, 1.0))
	# Party icon: a banner disc with a direction notch.
	canvas.draw_circle(party_point, 11.0, Color("1d3b4a"))
	canvas.draw_circle(party_point, 8.0, Color("ffd36b"))
	canvas.draw_line(party_point + Vector2(0, -8), party_point + Vector2(0, -22), Color("1d3b4a"), 2.0)
	canvas.draw_colored_polygon(PackedVector2Array([party_point + Vector2(0, -22), party_point + Vector2(12, -18), party_point + Vector2(0, -14)]), Color("e0533d"))

## The existing map mode control returns input to the original full body.
## Its next visible Lab binds the selected graph through the existing API.

func _return_original_body_mode(party: Dictionary) -> void:
	var hosted := _ensure_original_adapter_host(party)
	if not hosted.ok: _fail(hosted); return
	var original: Dictionary = _original_adapter_host.prepare_region_party_original_owner(str(party.party_id), party, slot)
	if not original.ok: _fail(original); return
	var guarded: Dictionary = slot.prepare_region_party_map_resume(original.lab)
	if not guarded.ok: _fail(guarded); return
	var returned: Dictionary = slot.return_original_mode(original.lab)
	if not returned.ok: _fail(returned); return
	_arriving = true
	running = false
	_mode_after_leg = false
	_accumulated = 0.0
	RegionEntry.pending = {"manifest": manifest, "world_id": world_id, "slot_id": slot_id,
		"site": guarded.site, "create_new": false}
	RegionEntry.view = {}
	var changed := get_tree().change_scene_to_file(SITE_SCENE)
	if changed != OK:
		_arriving = false
		_status.text = "原旅隊操作模式已保存；場景待同一選定原 graph 綁定，可重試。"
		_refresh()

