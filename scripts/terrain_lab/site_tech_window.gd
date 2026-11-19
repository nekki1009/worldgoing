class_name SiteTechWindow
extends RefCounted
## Presentation and input drafts in the original family Window. Gameplay stays
## in the original Family / SitePersonActions owners; opening never gives orders.

const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")

var _controller: Variant
var _root: VBoxContainer
var _status: Label
var _project: Label
var _people: Label
var _reasons: Label
var _researcher: OptionButton
var _teacher: OptionButton
var _student: OptionButton
var _wood: SpinBox
var _fiber: SpinBox
var _buttons: Dictionary = {}
var _scope: Dictionary = {} # UI context only; never exported to a gameplay save.
var _refreshing := false

func install(controller: Variant, column: VBoxContainer) -> void:
	if is_instance_valid(_root):
		refresh()
		return
	_controller = controller
	_root = VBoxContainer.new()
	_root.name = "F07Technology"
	_root.add_theme_constant_override("separation", 8)
	column.add_child(_root)
	_root.add_child(HSeparator.new())
	_label("F07 製弓工法 · 研究與傳授", 18)
	_label("人工安排；NPC 自動研究尚未開放。\n首次研究／無師傅重學：本人成功試作 3 把真弓，共木材 12、纖維 6；每把基準 120 有效遊戲秒。\n已學會者的新普通製弓為 108 秒；弩、配方與戰力不變。授課 300 有效遊戲秒，不耗材料、不產生弓。", 15)
	_status = _label("")
	_status.name = "F07Status"
	_project = _label("", 15)
	_project.name = "F07ProjectStatus"
	_people = _label("", 15)
	_people.name = "F07PeopleStatus"
	_reasons = _label("", 15)
	_reasons.name = "F07BlockReasons"
	_reasons.modulate = Color("f0d7a0")
	_label("研究／重學：選原試作者，再準備同目的項目。等待核准不占人物、不扣料。", 15)
	_researcher = _choice("F07Researcher")
	_button("準備首次研究／續用同目的", "F07PrepareFirst", func() -> void:
		_perform("prepare_technology", [_requester(), _id(_researcher), "first"], [_ref(_researcher)]))
	_button("明示無師傅重學／續用同目的", "F07PrepareRelearn", func() -> void:
		_perform("prepare_technology", [_requester(), _id(_researcher), "relearn"], [_ref(_researcher)]))
	_button("請求原隊同意本次試作", "F07RequestConsent", func() -> void:
		_perform("request_technology_consent", [_requester(), _id(_researcher)], [_ref(_researcher)]))
	_label("本 Site 原營地科研總額（不是庫存預留）：只有當前受控者具原營地取用資格才可核額。", 15)
	var budget_row := HBoxContainer.new()
	_root.add_child(budget_row)
	_wood = _amount(budget_row, "木材", "F07WoodCap", 12)
	_fiber = _amount(budget_row, "纖維", "F07FiberCap", 6)
	_button("核准本次總額", "F07GrantBudget", func() -> void: _budget("grant"))
	_button("提高同一授權總額", "F07IncreaseBudget", func() -> void: _budget("increase"))
	_button("撤銷研究材料授權", "F07RevokeBudget", func() -> void: _budget("revoke"))
	_button("開始下一把具研究用途的試作", "F07BeginTrial", func() -> void:
		_perform("begin_technology_trial", [_requester(), _id(_researcher)], [_ref(_researcher)]))
	_button("停止在途研究作業（保留目的歷史）", "F07StopResearch", func() -> void:
		_perform("stop_technology", [_requester(), 0]))
	_root.add_child(HSeparator.new())
	_label("傳授：選本族已學老師與未學學生；按開始時分別向兩隊請求本次同意，全部批准才開一課。\n授課不要求材料額度；研究材料撤銷不取消合法課程。", 15)
	_label("老師", 15)
	_teacher = _choice("F07Teacher")
	_label("學生", 15)
	_student = _choice("F07Student")
	_button("請求雙方原隊同意並開始授課", "F07BeginLesson", func() -> void:
		_perform("begin_technology_lesson", [_requester(), _id(_teacher), _id(_student)], [_ref(_teacher), _ref(_student)]))
	_button("從老師端停止相關授課", "F07StopTeacherLesson", func() -> void:
		_perform("stop_technology", [_requester(), _id(_teacher)], [_ref(_teacher)]))
	_button("從學生端停止相關授課", "F07StopStudentLesson", func() -> void:
		_perform("stop_technology", [_requester(), _id(_student)], [_ref(_student)]))
	_install_scope_controls()
	_install_supervised_controls()
	refresh()

func refresh() -> void:
	if _refreshing or not is_instance_valid(_root): return
	_refreshing = true
	_refresh_supervised_controls()
	if not is_instance_valid(_controller) or _controller.lab == null or _controller.lab.terrain == null:
		_unavailable("原 Site 尚未就緒。")
		_scope_unavailable("原 Site 尚未就緒。")
		_refreshing = false
		return
	_refresh_scope_controls()
	if not _controller.person_actions.has_method("technology_query"):
		_unavailable("科技操作尚未接入原人物作業入口。")
		_refreshing = false
		return
	if not _scope.is_empty() and not _scope_current(): _clear_draft()
	var query: Dictionary = _controller.person_actions.technology_query()
	if not bool(query.get("ok", false)):
		_unavailable(str(query.get("message", query.get("code", "科技資料不可用。"))))
		_refreshing = false
		return
	var lab: Variant = _controller.lab
	_scope = {"terrain": lab.terrain, "site": lab.terrain.site,
		"site_id": str(lab.terrain.site.get("id", "")), "control": int(query.current_person_id)}
	if not bool(query.registered):
		_unavailable("家族未明確登錄（UNREGISTERED）；請先使用合法家族情境或原保存資料。此窗不建立家族／親屬。")
		_refreshing = false
		return
	var rows: Array = query.people
	for choice: OptionButton in [_researcher, _teacher, _student]: _fill_people(choice, rows)
	_status.text = "家族 %s · F07 %s\n研究負責原人 #%d · 授徒負責原人 #%d · 目前受控原人 #%d" % [
		str(query.family_id), "已知" if bool(query.known) else "尚未知",
		int(query.research_decider), int(query.teaching_decider), int(query.current_person_id)]
	var project: Dictionary = query.project
	_project.text = _project_text(project)
	var descriptions: Array[String] = []
	for person: Dictionary in rows:
		var job: Dictionary = person.get("job", {})
		var working := "閒置"
		if bool(person.busy):
			working = "忙碌 · %s" % str(job.get("kind", "原作業"))
			if job.has("elapsed") and job.has("duration"):
				working += " 工時 %.1f／%.1f 秒" % [float(job.elapsed), float(job.duration)]
			if not str(job.get("paused", "")).is_empty():
				working += " · " + str({"THREAT": "敵情停工", "REST": "休息中"}.get(str(job.paused), str(job.paused)))
		descriptions.append("%s #%d · 地點 %s · %s · 本人試作 %d／3 · %s" % [str(person.label), int(person.person_id),
			str(person.site_id), "已學 F07" if bool(person.learned) else "未學 F07", int(person.stages), working])
	_people.text = "\n".join(descriptions)
	_update_buttons(query, rows, project)
	_refreshing = false

func context_changed() -> void:
	_clear_draft()
	_clear_scope_draft()
	_supervised_clear()
	if is_instance_valid(_root): _unavailable("原人物／Site 上下文已變更，請重新選擇原參與者。")

func _clear_draft() -> void:
	_scope.clear()
	for choice: OptionButton in [_researcher, _teacher, _student]:
		if is_instance_valid(choice): choice.clear()
	if is_instance_valid(_wood): _wood.value = 12
	if is_instance_valid(_fiber): _fiber.value = 6

func _label(value: String, size: int = 17) -> Label:
	var label: Label = _controller._label(_root, value, size)
	label.custom_minimum_size.x = 0
	return label

func _choice(node_name: String) -> OptionButton:
	var choice: OptionButton = _controller._options(_root, [], node_name)
	choice.item_selected.connect(func(_index: int) -> void: refresh())
	return choice

func _button(title: String, node_name: String, action: Callable) -> void:
	_buttons[node_name] = _controller._button(_root, title, node_name, action)

func _amount(parent: HBoxContainer, title: String, node_name: String, initial: int) -> SpinBox:
	var label := Label.new()
	label.text = title
	parent.add_child(label)
	var amount := SpinBox.new()
	amount.name = node_name
	amount.min_value = 1
	amount.max_value = 2147483647
	amount.step = 1
	amount.value = initial
	amount.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(amount)
	return amount

func _fill_people(choice: OptionButton, rows: Array) -> void:
	var previous := _ref(choice)
	choice.clear()
	choice.add_item("請選擇本 Site 原族人")
	choice.set_item_metadata(0, {})
	choice.disabled = false
	for person: Dictionary in rows:
		if str(person.site_id) != str(_scope.site_id): continue
		choice.add_item("%s #%d · %s · %s" % [str(person.label), int(person.person_id),
			"已學" if bool(person.learned) else "未學", "隊 #%d" % int(person.team_id) if int(person.team_id) >= 0 else "獨立原人"])
		var reference := {"person_id": int(person.person_id), "site_id": str(person.site_id)}
		choice.set_item_metadata(choice.item_count - 1, reference)
		if reference == previous: choice.select(choice.item_count - 1)

func _ref(choice: OptionButton) -> Dictionary:
	if not is_instance_valid(choice) or choice.selected < 0: return {}
	var value: Variant = choice.get_item_metadata(choice.selected)
	return value.duplicate() if value is Dictionary else {}

func _id(choice: OptionButton) -> int:
	return int(_ref(choice).get("person_id", 0))

func _requester() -> int:
	return int(_scope.get("control", -1))

func _scope_current() -> bool:
	if _scope.is_empty() or not is_instance_valid(_controller) or _controller.lab == null: return false
	var lab: Variant = _controller.lab
	return lab.terrain != null and is_same(lab.terrain, _scope.terrain) and is_same(lab.terrain.site, _scope.site) \
		and str(lab.terrain.site.get("id", "")) == str(_scope.site_id) and int(lab.controlled_person_id()) == int(_scope.control)

func _perform(method: String, arguments: Array, references: Array = []) -> void:
	if not _scope_current():
		_controller.show_result(Runtime.fail("STALE_SOURCE", "原人物／Site 已變更，請重新選擇"))
		context_changed()
		refresh()
		return
	var query: Dictionary = _controller.person_actions.technology_query()
	if not bool(query.get("ok", false)) or not bool(query.get("registered", false)):
		_controller.show_result(query if not bool(query.get("ok", false)) else Runtime.fail("UNREGISTERED", "原家族未登錄"))
		refresh()
		return
	for reference: Dictionary in references:
		var present := false
		for person: Dictionary in query.people:
			if int(person.person_id) == int(reference.get("person_id", 0)) and str(person.site_id) == str(reference.get("site_id", "")) \
				and str(person.site_id) == str(_scope.site_id): present = true
		if not present:
			_controller.show_result(Runtime.fail("STALE_SOURCE", "所選原參與者已不在本 Site 合法家族，請重新選擇"))
			refresh()
			return
	# The action performs the authoritative checks; neither UI enablement nor the
	# read-only query grants a duty, team consent, material budget or person skill.
	var result: Dictionary = _controller.person_actions.callv(method, arguments)
	_controller.show_result(result)
	refresh()

func _budget(operation: String) -> void:
	_perform("grant_technology_budget", [_requester(), {"wood": int(_wood.value), "fiber": int(_fiber.value)}, operation])

func _project_text(project: Dictionary) -> String:
	if project.is_empty(): return "尚無研究項目；先明示準備，再取得適用同意與原營地額度。"
	var lines: Array[String] = ["項目 %s · %s · %s · 原試作者 #%d · %d／3" % [
		str(project.get("id", "")), str(project.get("tech_id", "F07")),
		"無師傅重學" if str(project.get("mode", "first")) == "relearn" else "首次研究",
		int(project.get("executor_id", 0)), int(project.get("stages", 0))]]
	var budget: Dictionary = project.get("budget", {})
	var cap: Dictionary = budget.get("cap", {})
	var spent: Dictionary = budget.get("spent", {})
	var source_site := str(budget.get("source_site_id", ""))
	lines.append("原來源 %s／營地 %s · 核准原人 #%d · 額度 %s（%s）\n木材：已支出 %d／總額 %d；纖維：已支出 %d／總額 %d" % [
		source_site if not source_site.is_empty() else "尚未核准", str(budget.get("holder", "depot")), int(budget.get("grantor_id", 0)),
		{"granted": "已核准", "revoked": "已撤銷", "pending": "待核准"}.get(str(budget.get("status", "pending")), "不可用"),
		"有效" if bool(budget.get("active", false)) else "未生效／停效",
		int(spent.get("wood", 0)), int(cap.get("wood", 0)), int(spent.get("fiber", 0)), int(cap.get("fiber", 0))])
	for consent: Dictionary in project.get("consents", []):
		lines.append("原人 #%d · 隊 #%d · 真決策者 #%d · 同意 %s" % [int(consent.person_id), int(consent.team_id), int(consent.decider_id), str(consent.status)])
	if not str(project.get("status_text", "")).is_empty(): lines.append(str(project.status_text))
	return "\n".join(lines)

func _person_row(rows: Array, identity: int) -> Dictionary:
	for person: Dictionary in rows:
		if int(person.person_id) == identity and str(person.site_id) == str(_scope.site_id): return person
	return {}

func _update_buttons(query: Dictionary, rows: Array, project: Dictionary) -> void:
	var researcher := _person_row(rows, _id(_researcher))
	var teacher := _person_row(rows, _id(_teacher))
	var student := _person_row(rows, _id(_student))
	var research_reason := "" if int(query.research_decider) == _requester() else "目前受控者不是當前合法研究決策者。"
	var teaching_reason := "" if int(query.teaching_decider) == _requester() else "目前受控者不是當前合法授徒決策者。"
	var person_reason := "請先選擇原試作者。" if researcher.is_empty() else ("原試作者已學會 F07。" if bool(researcher.learned) else ("原試作者正忙碌。" if bool(researcher.busy) else ""))
	var project_reason := "請先準備正式研究／重學項目。" if project.is_empty() else ""
	var first_reason := "家族已知 F07；未學者請授課或明示重學。" if bool(query.known) else ""
	var relearn_reason := "家族尚未知 F07；請先首次研究。" if not bool(query.known) else ""
	_set_reason("F07PrepareFirst", _first_reason([research_reason, person_reason, first_reason]))
	_set_reason("F07PrepareRelearn", _first_reason([research_reason, person_reason, relearn_reason]))
	_set_reason("F07RequestConsent", _first_reason([research_reason, project_reason, person_reason]))
	_set_reason("F07BeginTrial", _first_reason([research_reason, project_reason, person_reason]))
	_set_reason("F07StopResearch", _first_reason([research_reason, project_reason]))
	# Material authorization is independent of the family research duty. Actual
	# controlled-person / camp eligibility is checked by the original action API.
	for key: String in ["F07GrantBudget", "F07IncreaseBudget", "F07RevokeBudget"]: _set_reason(key, project_reason)
	var lesson_reason := ""
	if not bool(query.known): lesson_reason = "家族尚未知 F07。"
	elif teacher.is_empty() or student.is_empty(): lesson_reason = "請分別選擇老師與學生。"
	elif _id(_teacher) == _id(_student): lesson_reason = "老師與學生須為兩位不同原人。"
	elif not bool(teacher.learned): lesson_reason = "老師尚未學會 F07。"
	elif bool(student.learned): lesson_reason = "學生已學會 F07。"
	elif bool(teacher.busy) or bool(student.busy): lesson_reason = "老師或學生正忙碌；REST 期間仍占本課。"
	_set_reason("F07BeginLesson", _first_reason([teaching_reason, lesson_reason]))
	_set_reason("F07StopTeacherLesson", _first_reason([teaching_reason, "請選擇老師。" if teacher.is_empty() else ""]))
	_set_reason("F07StopStudentLesson", _first_reason([teaching_reason, "請選擇學生。" if student.is_empty() else ""]))
	var reasons: Array[String] = []
	for reason: String in project.get("block_reasons", []):
		if not reason.is_empty() and not reasons.has(reason): reasons.append(reason)
	for button: Button in _buttons.values():
		if button.disabled and not reasons.has(button.tooltip_text): reasons.append(button.tooltip_text)
	_reasons.text = "缺項／停止原因：\n" + "\n".join(reasons) if not reasons.is_empty() else "開始前重查資格、兩隊同意、來源、材料、容量與人物占用。"

func _first_reason(reasons: Array) -> String:
	for reason: String in reasons:
		if not reason.is_empty(): return reason
	return ""

func _set_reason(key: String, reason: String) -> void:
	var button: Button = _buttons[key]
	button.disabled = not reason.is_empty()
	button.tooltip_text = reason if not reason.is_empty() else "提交時重查當前資格與材料。"

func _unavailable(reason: String) -> void:
	_status.text = reason
	_project.text = ""
	_people.text = ""
	_reasons.text = reason
	for choice: OptionButton in [_researcher, _teacher, _student]:
		choice.clear()
		choice.disabled = true
	for key: String in _buttons: _set_reason(key, reason)


func _scope_fill_targets(query: Dictionary, phase: Dictionary) -> void:
	var previous := _ref(_scope_target)
	_scope_target.clear()
	_scope_target.add_item("請選真原目標／完整原草稿")
	_scope_target.set_item_metadata(0, {})
	if _scope_tech_id() in ["S03", "S05", "S12"]:
		_productive_scope_targets(query, phase, previous)
		return
	if _scope_tech_id() == "S04":
		_metal_scope_targets(query, phase, previous)
		return
	if _scope_tech_id() == "S01":
		var center_key := str(query.site_ref.get("settlement", {}).get("center_id", ""))
		var center: Dictionary = query.site_ref.get("features", {}).get(center_key, {})
		if center.get("kind") == "settlement_center":
			for categories: Array in [["house", "farm", "workshop"], ["house", "workshop", "farm"], ["farm", "house", "workshop"], ["farm", "workshop", "house"], ["workshop", "house", "farm"], ["workshop", "farm", "house"]]:
				var names := {"house": "住宅", "farm": "農牧", "workshop": "工坊"}
				_scope_add_target("本中心 #%s · %s → %s → %s" % [center_key, names[categories[0]], names[categories[1]], names[categories[2]]],
					{"kind": "water_schedule", "key": center_key, "target_ref": center, "target_id": "feature:" + center_key, "work_target": {"categories": categories.duplicate()}}, previous)
		return
	if _scope_tech_id() == "S06":
		_scope_fill_food_orders(query, previous)
		return
	if phase.is_empty(): return
	var site: Dictionary = _scope_context.site
	var binding := str(phase.binding)
	if binding in ["crossbow", "fire_arrow", "fire_pot", "spares"]:
		var person := _scope_project_person(query)
		if not person.is_empty(): _scope_add_target("本項原人 #%d · 原營地真手作" % int(person.person_id), {"kind": "scope_craft", "person_id": int(person.person_id), "owner_ref": person.owner_ref, "body_ref": person.body_ref, "target_id": "depot" if binding == "spares" else "ranged:" + str(int(person.person_id))}, previous)
		return
	if binding == "spare_repair":
		for key: String in site.get("vehicles", {}):
			var vehicle: Dictionary = site.vehicles[key]
			if vehicle.get("kind") == "ballista": _scope_add_target("原固定重弩 #%s · 原備件修理預檢" % key, {"kind": "scope_repair", "key": key, "target_ref": vehicle, "target_id": "vehicle:" + key}, previous)
		return
	if binding == "fire_pot_shot":
		_scope_fill_shot_targets(query, previous)
		return
	for collection: String in ["features", "vehicles"]:
		for identity: String in site.get(collection, {}):
			var target: Dictionary = site[collection][identity]
			var token: Dictionary = target.get("tech_trial", {})
			if token.get("scope") != query.scope or token.get("scope_id") != query.scope_id or int(token.get("project_id", -1)) != int(query.project.id) \
				or token.get("phase_id") != phase.id or token.get("binding") != binding: continue
			_scope_add_target("續作原已綁目標 %s:%s" % [collection, identity], {"kind": "resume", "collection": collection, "key": identity,
				"target_ref": target, "token_ref": token, "target_id": ("feature:" if collection == "features" else "vehicle:") + identity}, previous)
	if Runtime.TECHNOLOGY_FEATURE_BINDINGS.has(binding) or binding == "ferry_build":
		var host := "shipyard" if binding == "ferry_build" else str(Runtime.TECHNOLOGY_FEATURE_BINDINGS[binding][0])
		for identity: String in site.get("features", {}):
			var target: Dictionary = site.features[identity]
			if target.get("kind") != host or target.get("stage") != "complete": continue
			_scope_add_target("原 %s #%s · 格 %s" % [host, identity, str(target.get("entrance", -1))],
				{"kind": "feature", "key": identity, "target_ref": target, "target_id": "feature:" + identity}, previous)
	if Runtime.TECHNOLOGY_BUILD_BINDINGS.has(binding):
		var draft := _scope_build_draft(binding)
		if draft.ok: _scope_add_target("本次完整原 %s 草稿 · %d 實格" % [str(Runtime.TECHNOLOGY_BUILD_BINDINGS[binding]), draft.work_target.cells.size()], draft, previous)
	elif Runtime.TECHNOLOGY_SIEGE_BINDINGS.has(binding):
		var person := _scope_project_person(query)
		if not person.is_empty() and int(person.team_id) > 0:
			var draft := {"kind": "siege_draft", "target_id": "vehicle:" + str(int(site.get("next_vehicle", 1))),
				"work_target": {"anchor": _controller.selected, "facing": [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP][_scope_facing.selected], "team_id": int(person.team_id)}}
			_scope_add_target("原 %s · 地圖實格 %s · 原隊 #%d" % [str(Runtime.TECHNOLOGY_SIEGE_BINDINGS[binding]), str(_controller.selected), int(person.team_id)], draft, previous)

func _scope_target_candidate(query: Dictionary, selected: Dictionary) -> Dictionary:
	if selected.is_empty() or query.project.get("tech_id") != _scope_tech_id() or query.phase.is_empty(): return Runtime.fail("NO_TARGET", "先選本項真原目標")
	var site: Dictionary = query.site_ref
	var binding := str(query.phase.binding)
	if selected.get("kind") == "scope_craft":
		var person := _scope_project_person(query)
		var id := "depot" if binding == "spares" else "ranged:" + str(int(person.get("person_id", 0)))
		if binding not in ["crossbow", "fire_arrow", "fire_pot", "spares"] or person.is_empty() or person.person_id != selected.get("person_id") or not is_same(person.owner_ref, selected.get("owner_ref")) or not is_same(person.body_ref, selected.get("body_ref")) or selected.get("target_id") != id: return Runtime.fail("STALE_SOURCE")
		return Runtime.ok("", {"target_id": id, "work_target": {}})
	if selected.get("kind") == "scope_repair":
		var vehicle: Dictionary = site.get("vehicles", {}).get(str(selected.get("key", "")), {})
		if binding != "spare_repair" or vehicle.get("kind") != "ballista" or not is_same(vehicle, selected.get("target_ref")) or selected.get("target_id") != "vehicle:" + str(selected.key): return Runtime.fail("STALE_SOURCE")
		return Runtime.ok("", {"target_id": str(selected.target_id), "work_target": {}})
	if selected.get("kind") == "scope_shot": return _scope_shot_selection(query, selected)
	if selected.get("kind") == "productive_order": return _productive_scope_selection(query, selected)
	if selected.get("kind") == "metal_order" and _scope_tech_id() == "S04": return _metal_scope_target(query, selected)
	if selected.get("kind") == "water_schedule" and binding == "water_priority":
		var checked := _scope_water_selection(query, selected)
		return checked
	if selected.get("kind") == "food_order": return _scope_food_selection(query, selected)
	if selected.get("kind") == "resume":
		var actual: Dictionary = site.get(str(selected.get("collection", "")), {}).get(str(selected.get("key", "")), {})
		var token: Dictionary = actual.get("tech_trial", {})
		if not is_same(actual, selected.get("target_ref")) or not is_same(token, selected.get("token_ref")) \
			or token.get("scope") != query.scope or token.get("scope_id") != query.scope_id or int(token.get("project_id", -1)) != int(query.project.id) \
			or token.get("phase_id") != query.phase.id or token.get("binding") != binding: return Runtime.fail("STALE_SOURCE")
		return Runtime.ok("", {"target_id": str(selected.target_id), "work_target": {}})
	if selected.get("kind") == "feature":
		var actual: Dictionary = site.get("features", {}).get(str(selected.get("key", "")), {})
		var host := "shipyard" if binding == "ferry_build" else str(Runtime.TECHNOLOGY_FEATURE_BINDINGS.get(binding, [""])[0])
		if not is_same(actual, selected.get("target_ref")) or actual.get("kind") != host or actual.get("stage") != "complete": return Runtime.fail("STALE_SOURCE")
		var target := {}
		if binding == "ferry_build":
			var person := _scope_project_person(query)
			if person.is_empty() or int(person.team_id) <= 0: return Runtime.fail("NO_AUTHORITY")
			target = {"team_id": int(person.team_id)}
		return Runtime.ok("", {"target_id": "feature:" + str(selected.key), "work_target": target})
	if selected.get("kind") == "build_draft":
		var current := _scope_build_draft(binding)
		if not current.ok: return current
		return current if current.target_id == selected.get("target_id") and current.work_target == selected.get("work_target") else Runtime.fail("STALE_SOURCE", "原完整建設草稿／下一原 ID 已變更；請重新選擇")
	if selected.get("kind") == "siege_draft" and Runtime.TECHNOLOGY_SIEGE_BINDINGS.has(binding):
		var person := _scope_project_person(query)
		var target: Dictionary = selected.get("work_target", {})
		var facing: Vector2i = [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP][_scope_facing.selected]
		if person.is_empty() or int(person.team_id) <= 0 or int(target.get("team_id", -1)) != int(person.team_id) \
			or target.get("anchor") != _controller.selected or target.get("facing") != facing or selected.target_id != "vehicle:" + str(int(site.get("next_vehicle", 1))): return Runtime.fail("STALE_SOURCE")
		return Runtime.ok("", {"target_id": str(selected.target_id), "work_target": target.duplicate()})
	return Runtime.fail("NO_OWNER_HOOK", "此階段尚無已接線的原目標／作業入口；不能以手填 target 或假收據開始")

func _scope_fire_pot_grant() -> void:
	var query := _scope_submit_query()
	if not query.ok: _controller.show_result(query); refresh(); return
	var selected := _ref(_scope_target)
	var actual := _scope_shot_selection(query, selected)
	if not actual.ok: _controller.show_result(actual); refresh(); return
	_scope_dispatch("grant_fire_pot_vehicle_budget", [_scope_requester(), str(selected.key), 1, "grant"])

func _scope_apply_water() -> void:
	var query := _scope_submit_query()
	if not query.ok or _scope_tech_id() != "S01" or not bool(query.get("known", false)):
		_controller.show_result(query if not query.ok else Runtime.fail("NO_TECHNOLOGY"))
		refresh()
		return
	var selected := _scope_water_selection(query, _ref(_scope_target))
	if not selected.ok:
		_controller.show_result(selected)
		refresh()
		return
	_scope_dispatch("set_water_use_priority", [_scope_requester(), selected.work_target.categories])

func _productive_adopt(preview: bool) -> void:
	var query := _scope_submit_query()
	if not query.ok: _productive_result(query); return
	var source := _productive_source_selection(query)
	var person := _scope_row(query.people, _ref(_scope_researcher))
	if not source.ok or person.is_empty(): _productive_result(source if not source.ok else Runtime.fail("NO_WORKER")); return
	var project_id := int(query.project.get("id", 0)) if query.project.get("tech_id") == _scope_tech_id() else 0
	if project_id > 0 and int(query.project.executor.person_id) != int(person.person_id): _productive_result(Runtime.fail("STALE_PROJECT")); return
	var kind := _productive_kind()
	var key := str(_controller.feature_key)
	var runtime: Variant = Runtime
	var result: Dictionary
	if kind == "ship_cooperation":
		var helper := _scope_row(query.people, _ref(_productive_form().helper))
		var carrier := _scope_row(query.get("carriers", []), _ref(_productive_form().carrier))
		if helper.is_empty() or carrier.is_empty(): _productive_result(Runtime.fail("NO_WORKER", "請具名第二原工人及搬料者")); return
		result = runtime.call("request_settlement_ship_order", query.terrain_ref, key, int(person.person_id), int(helper.person_id), int(carrier.person_id), str(source.holder_id), _scope_requester(), project_id, preview)
	else:
		if kind not in ["charcoal_batch", "textile_batch"]: _productive_result(Runtime.fail("NO_TARGET")); return
		result = runtime.call("request_settlement_processing_order", query.terrain_ref, kind, key, int(person.person_id), 3 if kind == "charcoal_batch" else 2, _scope_requester(), str(source.source_feature_id), project_id, preview)
	_productive_result(result)

func _productive_configure(adopt: bool) -> void:
	var query := _scope_submit_query(not adopt)
	if not query.ok: _productive_result(query); return
	if _scope_tech_id() not in ["S11", "S12"]: _productive_result(Runtime.fail("NO_TARGET")); return
	var person := _scope_row(query.people, _ref(_scope_researcher))
	if adopt and person.is_empty(): _productive_result(Runtime.fail("NO_WORKER")); return
	var runtime: Variant = Runtime
	_productive_result(runtime.call("configure_siege_yard" if _scope_tech_id() == "S11" else "configure_shipyard_work", query.terrain_ref, str(_controller.feature_key), _scope_requester(), int(person.get("person_id", 0)), adopt))

func _productive_source(revoke: bool) -> void:
	var query := _scope_submit_query(revoke)
	if not query.ok: _productive_result(query); return
	var selected := _productive_order(query)
	if not selected.ok: _productive_result(selected); return
	var source := Runtime.ok("", {"source_feature_id": ""}) if revoke else _productive_source_selection(query)
	if not source.ok: _productive_result(source); return
	var runtime: Variant = Runtime
	_productive_result(runtime.call("grant_settlement_operation_source", query.terrain_ref, str(query.scope_id), str(selected.order.id), _scope_requester(), str(source.source_feature_id), revoke))

func _productive_step() -> void:
	var query := _scope_submit_query()
	if not query.ok: _productive_result(query); return
	var selected := _productive_order(query)
	if not selected.ok: _productive_result(selected); return
	var order: Dictionary = selected.order
	var runtime: Variant = Runtime
	if order.kind == "ship_cooperation" and not Runtime.settlement_ship_delivery_complete(order.payload):
		var prepared: Dictionary = runtime.call("prepare_settlement_ship_delivery", query.terrain_ref, str(query.scope_id), str(order.id), _scope_requester())
		_productive_result(runtime.call("publish_settlement_ship_delivery", prepared) if prepared.ok else prepared)
		return
	if int(order.payload.project_id) > 0:
		var source := {"kind": "productive_order", "key": str(order.id), "target_ref": order, "target_id": "feature:" + str(order.payload.feature_id)}
		var actual := _productive_scope_selection(query, source)
		if not actual.ok: _productive_result(actual); return
		_scope_dispatch("begin_scope_technology_phase", [_scope_requester(), "settlement", str(query.scope_id), str(query.phase.binding), str(actual.target_id), actual.work_target])
	else:
		_productive_result(runtime.call("begin_settlement_ship_operation" if order.kind == "ship_cooperation" else "begin_settlement_processing_operation", query.terrain_ref, str(query.scope_id), str(order.id)))

func _metal_begin() -> void:
	var query := _scope_submit_query()
	if not query.ok: _controller.show_result(query); refresh(); return
	var order := _metal_current_order(query)
	if order.is_empty(): _controller.show_result(Runtime.fail("STALE_SOURCE")); refresh(); return
	var view: Dictionary = _controller.person_actions.settlement_metal_order_view(str(query.scope_id), str(order.id))
	if not view.ok: _controller.show_result(view); refresh(); return
	if int(order.payload.project_id) == 0:
		_scope_dispatch("begin_settlement_metal_operation", [_scope_requester(), str(query.scope_id), str(order.id)])
	elif query.project.get("id") != order.payload.project_id or query.phase.get("binding") != view.binding:
		_controller.show_result(Runtime.fail("STALE_PHASE")); refresh()
	else:
		_scope_dispatch("begin_scope_technology_phase", [_scope_requester(), "settlement", str(query.scope_id), str(view.binding), str(view.target_id), {"order_id": str(order.id)}])

func _metal_request() -> void:
	var query := _scope_submit_query()
	if not query.ok: _controller.show_result(query); refresh(); return
	var smelter := _ref(_metal_form.smelter)
	var smithy := _ref(_metal_form.smithy)
	var person := _ref(_metal_form.person)
	if query.scope != "settlement" or _scope_tech_id() != "S04" or not is_same(query.site_ref.get("features", {}).get(str(smelter.get("id", ""))), smelter.get("ref")) \
		or not is_same(query.site_ref.get("features", {}).get(str(smithy.get("id", ""))), smithy.get("ref")): _controller.show_result(Runtime.fail("STALE_SOURCE")); refresh(); return
	var actual := {}
	for row: Dictionary in query.people:
		if int(row.person_id) == int(person.get("id", -1)) and is_same(row.body_ref, person.get("ref")): actual = row
	if actual.is_empty(): _controller.show_result(Runtime.fail("NO_WORKER")); refresh(); return
	var project_id := int(query.project.id) if query.project.get("tech_id") == "S04" else 0
	_scope_dispatch("request_settlement_metal_order", [_scope_requester(), str(smelter.id), str(smithy.id), int(person.id), project_id])

func _scope_food_adopt() -> void:
	var query := _scope_submit_query()
	if not query.ok or _scope_tech_id() != "S06": _controller.show_result(query if not query.ok else Runtime.fail("INVALID")); return
	var source := _ref(_scope_food_source)
	var current: Dictionary = _controller.vehicles._stock(str(source.get("holder_id", "")), str(source.get("holder_id", "")).begins_with("feature:"))
	var destination: Dictionary = query.site_ref.get("features", {}).get(str(_controller.feature_key), {})
	if source.is_empty() or current.is_empty() or not is_same(source.get("holder"), current.holder) or not is_same(source.get("cargo"), current.cargo) \
		or destination.get("kind") != "warehouse": _controller.show_result(Runtime.fail("NO_TARGET", "先在原地圖選指定倉庫，並明示原有限來源")); return
	var project_id: int = int(query.project.get("id", 0)) if query.project.get("tech_id") == "S06" else 0
	var operator_id: int = int(query.project.executor.person_id) if project_id > 0 else _id(_scope_researcher)
	_scope_dispatch("request_warehouse_food_order", [_scope_requester(), str(_controller.feature_key), operator_id, str(source.holder_id), project_id])

func _scope_food_step() -> void:
	var query := _scope_submit_query()
	if not query.ok: _controller.show_result(query); return
	var selection := _scope_food_selection(query, _ref(_scope_target))
	if not selection.ok: _controller.show_result(selection); refresh(); return
	var order: Dictionary = _ref(_scope_target).target_ref
	if int(order.payload.project_id) > 0:
		_scope_dispatch("begin_scope_technology_phase", [_scope_requester(), "settlement", str(query.scope_id), "food_order", str(selection.target_id), selection.work_target])
	elif order.payload.stage == "arrived":
		_scope_dispatch("begin_settlement_food_work", [_scope_requester(), str(query.scope_id), str(order.id)])
	else:
		_scope_dispatch("transfer_settlement_food_order", [_scope_requester(), str(query.scope_id), str(order.id), "load" if order.payload.stage == "prepared" else "arrive"])

func _refresh_scope_controls() -> void:
	if not is_instance_valid(_scope_node): return
	if not _scope_context.is_empty() and not _scope_context_current(): _clear_scope_draft()
	var node := Catalog.get_node(_scope_tech_id())
	if node.is_empty():
		_scope_unavailable("請選原家族／聚落科技。")
		return
	var previous_route := _scope_route_id() if _scope_context.get("tech_id") == _scope_tech_id() else ""
	_scope_route.clear()
	if node.research.routes.size() > 1:
		_scope_route.add_item("請明示選原研究路線")
		_scope_route.set_item_metadata(0, "")
	for route: Dictionary in node.research.routes:
		_scope_route.add_item("原路線 " + str(route.id))
		_scope_route.set_item_metadata(_scope_route.item_count - 1, str(route.id))
		if str(route.id) == previous_route: _scope_route.select(_scope_route.item_count - 1)
	if not _controller.person_actions.has_method("scope_technology_query"):
		_scope_unavailable("原 Scope 唯讀查詢尚未接線。")
		return
	_refresh_scope_nations(str(node.scope))
	var nation_id: String = str(_ref(_scope_nation_choice()).get("id", "")) if node.scope == "nation" else ""
	if node.scope == "nation" and nation_id.is_empty():
		_scope_unavailable("請明示選擇本 Site 原國家；此窗不建立國家")
		return
	var query: Dictionary = _controller.person_actions.call("scope_technology_query", _scope_tech_id(), nation_id)
	if not bool(query.get("ok", false)):
		var reason := str(query.get("message", ""))
		_scope_unavailable(reason if not reason.is_empty() else str(query.get("code", "原資料不可用")))
		return
	_scope_context = {"terrain": query.terrain_ref, "site": query.site_ref, "site_id": str(query.site_id),
		"control": int(query.current_person_id), "scope": str(query.scope), "scope_id": str(query.scope_id), "tech_id": _scope_tech_id(), "owner": query.owner_ref}
	for choice: OptionButton in [_scope_researcher, _scope_teacher, _scope_student]: _scope_fill_people(choice, query.people)
	var project: Dictionary = query.project
	var selected_project: bool = not project.is_empty() and project.get("tech_id") == _scope_tech_id() and int(project.get("rules_version", -1)) == 2
	_scope_route.disabled = selected_project
	if selected_project:
		for index: int in _scope_route.item_count:
			if _scope_route.get_item_metadata(index) == project.route_id: _scope_route.select(index)
	var phase: Dictionary = query.phase if selected_project else {}
	_scope_facing.visible = Runtime.TECHNOLOGY_SIEGE_BINDINGS.has(str(phase.get("binding", "")))
	_scope_fill_budget(project if selected_project else {})
	_scope_fill_food_sources(query)
	_scope_fill_targets(query, phase)
	var activation := _scope_activation_reason()
	_scope_status.text = "%s %s · %s · 原組織 %s\n當前受控原人 #%d · 研究決策者 #%d · 授課決策者 #%d\n%s" % [str(node.id), str(node.name), "已知" if bool(query.known) else "尚未知", str(query.scope_id) if not str(query.scope_id).is_empty() else "已登錄，科技歸屬尚未初始化", int(query.current_person_id), int(query.research_decider), int(query.teaching_decider), activation]
	var summary := "尚無本節點活動項目。"
	if not project.is_empty():
		var budget: Dictionary = project.budget
		summary = "活動項目 #%d · %s · 執行原人 #%d\n真完成階段 %d · 原來源 %s · 材料授權 %s\n總額 %s · 已支出 %s" % [int(project.id), str(project.tech_id), int(project.executor.get("person_id", -1)), project.receipts.size(), str(budget.get("source_site_id", "尚未核准")), str(budget.get("status", "尚未核准")), Runtime.items_text(budget.get("cap", {})), Runtime.items_text(budget.get("spent", {}))]
	if not phase.is_empty(): summary += "\n下一原階段 %s · %s · 第 %d／%d 次 · 本次材料 %s · 基準 %.1f 秒" % [str(phase.id), str(phase.binding), int(phase.occurrence), int(phase.repeat), Runtime.items_text(phase.materials), float(phase.seconds)]
	var source := Catalog.binding(str(phase.get("binding", "")))
	if not source.is_empty(): summary += "\n原作業場所：%s%s" % [str(source.host), " · 相關新增操作尚待交付" if not bool(node.enabled) else ""]
	_scope_details.text = summary
	var authority := "" if int(query.research_decider) == _scope_requester() else "目前受控者不是當前原研究決策者。"
	var researcher := _scope_row(query.people, _ref(_scope_researcher))
	var worker := "請選本 Site 原研究執行人。" if researcher.is_empty() else ("原人已學此技藝。" if bool(researcher.learned) else ("原人正忙碌／不能開始原工作。" if bool(researcher.busy) or not bool(researcher.ready) else ""))
	var route_reason := "請明示選原研究路線。" if _scope_route_id().is_empty() else ""
	_scope_reason("ScopePrepareFirst", _first_reason([activation, authority, worker, route_reason, "此範疇已知本節點。" if bool(query.known) else ""]))
	_scope_reason("ScopePrepareRelearn", _first_reason([activation, authority, worker, route_reason, "僅本族已知技藝可無師傅重學。" if query.scope != "family" or not bool(query.known) else ""]))
	var project_reason := "先選本節點並準備原項目。" if not selected_project else ""
	var executor_reason := "請選本項原執行人。" if researcher.is_empty() or not selected_project or int(researcher.person_id) != int(project.executor.get("person_id", -1)) else ""
	_scope_reason("ScopeRequestConsent", _first_reason([activation, authority, project_reason, executor_reason]))
	for key: String in ["ScopeGrantBudget", "ScopeIncreaseBudget"]: _scope_reason(key, _first_reason([activation, project_reason]))
	_scope_reason("ScopeRevokeBudget", _first_reason([project_reason, "本項尚無材料授權。" if project.get("budget", {}).is_empty() else ""]))
	_scope_reason("ScopeBeginPhase", _first_reason([activation, authority, project_reason, executor_reason, "原下一階段／真目標尚未就緒。" if phase.is_empty() or _ref(_scope_target).is_empty() else ""]))
	_scope_reason("ScopeFoodAdopt", _first_reason([activation, authority, "先選S06、指定倉庫及有限來源。" if _scope_tech_id() != "S06" or _ref(_scope_food_source).is_empty() else ""]))
	_scope_reason("ScopeFoodStep", _first_reason([activation, authority, "先選原糧食單。" if _ref(_scope_target).get("kind") != "food_order" else ""]))
	_scope_reason("ScopeFoodCancel", _first_reason([authority, "先選原糧食單。" if _ref(_scope_target).get("kind") != "food_order" else ""]))
	_scope_reason("ScopeApplyWater", _first_reason([activation, authority,
		"僅本聚落已知 S01 可套用。" if _scope_tech_id() != "S01" or not bool(query.known) else "",
		"請選本中心的明示用途順序。" if _ref(_scope_target).get("kind") != "water_schedule" else ""]))
	for key: String in ["ScopeStop", "ScopeRelease"]: _scope_reason(key, _first_reason([authority, project_reason]))
	for key: String in ["ScopeSurveyPlan", "ScopeSurveyFirst", "ScopeSurveySecond"]: _scope_reason(key, "只對 F09 測量的真草稿選取。" if _scope_tech_id() != "F09" else "")
	var teacher := _scope_row(query.people, _ref(_scope_teacher))
	var student := _scope_row(query.people, _ref(_scope_student))
	var teaching := "" if query.scope == "family" and int(query.teaching_decider) == _scope_requester() else "僅當前本族授徒決策者可安排原課程。"
	var lesson := ""
	if not bool(query.known): lesson = "本族尚未知本技藝。"
	elif teacher.is_empty() or student.is_empty(): lesson = "請選兩位不同原師徒。"
	elif int(teacher.person_id) == int(student.person_id): lesson = "師徒不能是同一原人。"
	elif not bool(teacher.learned) or bool(student.learned): lesson = "老師須已學、學生須未學。"
	elif bool(teacher.busy) or bool(student.busy) or not bool(teacher.ready) or not bool(student.ready): lesson = "原師徒正忙碌／不可開始授課。"
	_scope_reason("ScopeBeginLesson", _first_reason([activation, teaching, lesson]))
	_scope_reason("ScopeStopTeacher", _first_reason([teaching, "請選原老師。" if teacher.is_empty() else ""]))
	_scope_reason("ScopeStopStudent", _first_reason([teaching, "請選原學生。" if student.is_empty() else ""]))
	if query.scope == "nation":
		for key: String in ["ScopeGrantBudget", "ScopeIncreaseBudget", "ScopeRevokeBudget", "ScopeBeginPhase"]:
			_scope_reason(key, "本國階段沿具名原工單來源、付款與驗收；請開啟本國具名原操作")
	_scope_reason("ScopeNationOperations", _first_reason([activation, "請先選原國家節點。" if query.scope != "nation" else ""]))
	_refresh_metal_controls(query)
	_refresh_productive_controls(query)
	_scope_reason("ScopeFirePotShotGrant", _first_reason([activation, authority, "請選本F15發射階段的真原器械與真部件。" if _scope_tech_id() != "F15" or str(phase.get("binding", "")) != "fire_pot_shot" or _ref(_scope_target).get("kind") != "scope_shot" else ""]))

func _scope_open_nation_operations() -> void:
	var query := _scope_submit_query()
	if not query.ok: _controller.show_result(query); refresh(); return
	if query.scope != "nation": _controller.show_result(Runtime.fail("INVALID")); return
	_controller._open_nation_operations(str(query.scope_id), null, _scope_tech_id())

func _install_supervised_controls() -> void:
	_root.add_child(HSeparator.new())
	_label("原俘虜監管生產／真繳獲器械分析", 18)
	_label("監管生產：只用原俘虜已學 F07 製一把真弓（108 有效秒、木4纖維2），保持被俘，不授研究證據；真看守共同占用。\n分析：本族當前 F11／F12 原研究者拆解真繳獲器械，600 有效秒後才消耗器械並核本人的終身50%上限；不代選原人。", 15)
	_supervised_form.status = _label("")
	_supervised_form.captive = _choice("TechnologyCaptive")
	_supervised_form.supervisor = _choice("TechnologySupervisor")
	_supervised_form.analyst = _choice("TechnologyAnalyst")
	_supervised_form.vehicle = _choice("TechnologyAnalysisVehicle")
	_supervised_form.begin_captive = _controller._button(_root, "明示真看守監管原俘虜製弓", "TechnologyCaptiveBegin", func() -> void: _supervised_submit("begin_captive_craft"))
	_supervised_form.stop_captive = _controller._button(_root, "停止本次監管生產（不釋放俘虜）", "TechnologyCaptiveStop", func() -> void: _supervised_submit("stop_captive_craft"))
	_supervised_form.begin_analysis = _controller._button(_root, "原研究者開始600秒拆解分析", "TechnologyAnalysisBegin", func() -> void: _supervised_submit("begin_technology_analysis"))
	_label("分析在途使用上方本族『停止在途研究』；未完成不領抵扣。原權限、接觸、威脅、忙碌與材料由每次原入口重查。", 15)

func _refresh_supervised_controls() -> void:
	if _supervised_form.is_empty(): return
	if _supervised_form.has("context") and not _supervised_context_current(): _supervised_clear()
	var query := _supervised_query()
	if not query.ok:
		_supervised_unavailable(str(query.get("message", query.get("code", "原操作不可用"))))
		return
	_supervised_form.context = {"terrain": query.terrain_ref, "site": query.site_ref, "site_id": query.site_id, "control": int(query.current_person_id)}
	for pair: Array in [["captive", "captives", "請明選原俘虜"], ["supervisor", "supervisors", "請明選其原真看守"], ["analyst", "analysts", "請明選當前F11/F12原研究者"], ["vehicle", "vehicles", "請明選真原器械；舊/無來源不可分析"]]:
		_supervised_fill(_supervised_form[pair[0]], query[pair[1]], str(pair[2]))
	# Clearing a stale selected ref must also clear its displayed admission.
	query = _supervised_query()
	for pair: Array in [["begin_captive", "captive_begin"], ["stop_captive", "captive_stop"], ["begin_analysis", "analysis_begin"]]:
		var check: Dictionary = query[pair[1]]
		var button: Button = _supervised_form[pair[0]]
		button.disabled = not bool(check.ok)
		button.tooltip_text = "提交時重查原人／監管／項目／器械。" if check.ok else str(check.get("message", "")) + " [" + str(check.get("code", "")) + "]"
	_supervised_form.status.text = "原受控人 #%d · 真監管關係 %d 筆 · 原器械 %d 件\n分析項目：%s；選項不授權、不移動人物、不造家族。" % [int(query.current_person_id), query.captives.size(), query.vehicles.size(), str(query.project)]

func _install_scope_controls() -> void:
	_root.add_child(HSeparator.new())
	_label("家族／聚落／國家科技 · 原範疇操作", 18)
	_label("未交付真實新操作與具名驗收的節點只讀，不核额、不收費。F07 繼續使用上方原入口。\n所有按鈕提交時重新查本 Site 原組織、原人物與原目標；顯示或選擇不授予知識、職責、同意或材料。", 15)
	var nation_choice := _choice("ScopeTechnologyNation")
	_root.set_meta(&"nation_scope_choice", nation_choice)
	nation_choice.item_selected.connect(func(_index: int) -> void: _scope_context.clear(); refresh())
	_scope_node = _choice("ScopeTechnologyNode")
	for node: Dictionary in Catalog.all():
		if node.scope not in ["family", "settlement", "nation"]: continue
		_scope_node.add_item("%s %s · %s" % [str(node.id), str(node.name), "家族" if node.scope == "family" else "聚落" if node.scope == "settlement" else "國家"])
		_scope_node.set_item_metadata(_scope_node.item_count - 1, str(node.id))
	_scope_route = _choice("ScopeTechnologyRoute")
	_scope_status = _label("", 15)
	_scope_details = _label("", 15)
	_label("原研究執行人（不自動選工）", 15)
	_scope_researcher = _choice("ScopeTechnologyResearcher")
	_scope_button("明示準備首次研究／續用同目的", "ScopePrepareFirst", func() -> void: _scope_prepare("first"))
	_scope_button("明示本族無師傅重學／續用同目的", "ScopePrepareRelearn", func() -> void: _scope_prepare("relearn"))
	_scope_button("請求原隊本項具名同意", "ScopeRequestConsent", func() -> void:
		_scope_dispatch("request_scope_technology_consent", [_scope_requester(), _scope_kind(), _scope_owner_id(), _id(_scope_researcher)], [_ref(_scope_researcher)]))
	_label("原營地有限累計科研額度：以下為人工輸入總額；真付款仍沿原來源與作業。試作產出不自動抵銷核額。", 15)
	_scope_budget_row = HBoxContainer.new()
	_root.add_child(_scope_budget_row)
	_scope_button("核准此項總額", "ScopeGrantBudget", func() -> void: _scope_budget("grant"))
	_scope_button("提高同一項累計總額", "ScopeIncreaseBudget", func() -> void: _scope_budget("increase"))
	_scope_button("撤銷本項材料授權", "ScopeRevokeBudget", func() -> void: _scope_budget("revoke"))
	_label("下一階段：選現有原設施／器械，或本次完整原建設草稿；不接受手填 target 或完成收據。", 15)
	_scope_target = _choice("ScopeTechnologyTarget")
	_label("S06：原地圖選指定倉庫、明示來源與原持糧人；每單來源最多8糧，須實際交付兩腿。", 15)
	_scope_food_source = _choice("ScopeFoodSource")
	_scope_button("採用原有限糧食單", "ScopeFoodAdopt", _scope_food_adopt)
	_scope_button("實交／續作所選原糧食單", "ScopeFoodStep", _scope_food_step)
	_scope_button("撤回所選原糧食單（保留已付）", "ScopeFoodCancel", _scope_food_cancel)
	_scope_facing = _controller._options(_root, ["器械朝東", "器械朝南", "器械朝西", "器械朝北"], "ScopeTechnologyFacing")
	_scope_facing.item_selected.connect(func(_index: int) -> void: refresh())
	_scope_button("開始／續作下一原階段", "ScopeBeginPhase", _scope_begin)
	_scope_button("套用已驗收供水用途順序", "ScopeApplyWater", _scope_apply_water)
	_scope_button("停止在途研究（保留支出與成功歷史）", "ScopeStop", func() -> void:
		_scope_dispatch("stop_scope_technology", [_scope_requester(), _scope_kind(), _scope_owner_id(), false], [], true))
	_scope_button("永久解除原目標的本項研究綁定", "ScopeRelease", func() -> void:
		_scope_dispatch("stop_scope_technology", [_scope_requester(), _scope_kind(), _scope_owner_id(), true], [], true))
	_label("測量草稿：先沿原建設介面畫完整方案，再保存於此視窗；兩個測樁從地圖目前實格分別選取。", 15)
	_scope_button("記住目前完整原施工方案（僅草稿）", "ScopeSurveyPlan", _scope_capture_survey)
	_scope_button("以地圖目前實格選測樁 1", "ScopeSurveyFirst", func() -> void: _scope_pick_stake(0))
	_scope_button("以地圖目前實格選測樁 2", "ScopeSurveySecond", func() -> void: _scope_pick_stake(1))
	_label("本族傳授：老師本人已學、學生未學；真正雙隊同意仍由原授課入口逐一請求。聚落制度不寫入個人技藝。", 15)
	_scope_teacher = _choice("ScopeTechnologyTeacher")
	_scope_student = _choice("ScopeTechnologyStudent")
	_scope_button("請求雙隊同意並開始本族授課", "ScopeBeginLesson", func() -> void:
		_scope_dispatch("begin_technology_lesson", [_scope_requester(), _id(_scope_teacher), _id(_scope_student), _scope_tech_id()], [_ref(_scope_teacher), _ref(_scope_student)]))
	_scope_button("停止所選老師的原授課", "ScopeStopTeacher", func() -> void:
		_scope_dispatch("stop_technology", [_scope_requester(), _id(_scope_teacher)], [_ref(_scope_teacher)], true))
	_scope_button("停止所選學生的原授課", "ScopeStopStudent", func() -> void:
		_scope_dispatch("stop_technology", [_scope_requester(), _id(_scope_student)], [_ref(_scope_student)], true))
	_scope_button("開啟本國具名原操作（來源／付款／下一階段）", "ScopeNationOperations", _scope_open_nation_operations)
	_install_metal_controls()
	_install_productive_controls()
	_scope_button("核准所選原投石機本項最多一火罐", "ScopeFirePotShotGrant", _scope_fire_pot_grant)

func _scope_unavailable(reason: String) -> void:
	if is_instance_valid(_scope_status): _scope_status.text = reason
	if is_instance_valid(_scope_details): _scope_details.text = ""
	for button: Button in _scope_buttons.values():
		button.disabled = true
		button.tooltip_text = reason
	_metal_unavailable()
	for key: String in ["ScopeProductivePreview", "ScopeProductiveAdopt", "ScopeProductiveStep", "ScopeProductiveGrant", "ScopeProductiveRevoke", "ScopeProductivePause", "ScopeProductiveRelease", "ScopeYardAdopt", "ScopeYardRevoke"]:
		if _scope_buttons.has(key): _scope_reason(key, reason)

func _metal_scope_targets(query: Dictionary, phase: Dictionary, previous: Dictionary) -> void:
	if phase.is_empty() or query.project.get("tech_id") != "S04" or not _controller.person_actions.has_method("settlement_metal_order_view"): return
	for key: String in query.owner_ref.get("technology_operations", {}).get("orders", {}):
		var order: Dictionary = query.owner_ref.technology_operations.orders[key]
		if order.get("kind") != "metal_chain" or order.payload.project_id != query.project.id or order.payload.purpose != query.project.purpose: continue
		var view: Dictionary = _controller.person_actions.settlement_metal_order_view(str(query.scope_id), key)
		if not view.ok or view.binding != phase.binding: continue
		_scope_add_target("本原有限鏈 %s · %s · %s" % [key, str(view.binding), str(view.target_id)], {"kind": "metal_order", "key": key, "target_ref": order,
			"target_id": str(view.target_id), "work_target": {"order_id": key}}, previous)

func _productive_scope_targets(query: Dictionary, phase: Dictionary, previous: Dictionary) -> void:
	if phase.is_empty() or query.project.get("tech_id") != _scope_tech_id(): return
	for key: String in query.owner_ref.get("technology_operations", {}).get("orders", {}):
		var order: Dictionary = query.owner_ref.technology_operations.orders[key]
		if order.get("kind") != _productive_kind() or order.status not in ["prepared", "active", "suspended"] or order.payload.project_id != query.project.id or order.payload.purpose != query.project.purpose: continue
		if not Runtime.valid_settlement_processing_order(query.terrain_ref, query.site_ref, order): continue
		_scope_add_target("本原有限工單 " + key, {"kind": "productive_order", "key": key, "target_ref": order, "target_id": "feature:" + str(order.payload.feature_id)}, previous)

func _scope_add_target(title: String, reference: Dictionary, previous: Dictionary) -> void:
	_scope_target.add_item(title)
	_scope_target.set_item_metadata(_scope_target.item_count - 1, reference)
	var same: bool = not previous.is_empty() and previous.get("kind") == reference.kind and previous.get("target_id") == reference.target_id
	if reference.has("target_ref"): same = same and is_same(previous.get("target_ref"), reference.target_ref)
	else: same = same and previous.get("work_target") == reference.get("work_target")
	if reference.get("kind") == "water_schedule": same = same and previous.get("work_target") == reference.get("work_target")
	if same: _scope_target.select(_scope_target.item_count - 1)

func _scope_build_draft(binding: String) -> Dictionary:
	if not Runtime.TECHNOLOGY_BUILD_BINDINGS.has(binding): return Runtime.fail("NO_OWNER_HOOK")
	var kind := str(Runtime.TECHNOLOGY_BUILD_BINDINGS[binding])
	var cells: Array[int] = []
	var options := {}
	if binding == "survey":
		if _survey_cells.size() != 2 or _survey_plan.is_empty(): return Runtime.fail("NO_TARGET", "先选两真樁及完整原施工方案")
		cells = _survey_cells.duplicate()
		options = {"layout_version": Runtime.BUILDING_LAYOUT_VERSION, "survey_plan": _survey_plan.duplicate(true)}
	else:
		if _controller._building_kind() != kind or _controller.build_cells.is_empty(): return Runtime.fail("NO_TARGET", "先於原建設介面畫完整 " + kind + " 草稿")
		cells = _controller.build_cells.duplicate()
		options = _controller._building_options().duplicate(true)
	var checked := Runtime.irrigation_channel_draft(_controller.lab.terrain, cells, options, _controller.reserves_cell) if kind == "irrigation_channel" else Runtime.preview_build(_controller.lab.terrain, kind, cells, _controller.reserves_cell, options)
	if not checked.ok: return checked
	return Runtime.ok("", {"kind": "build_draft", "target_id": "feature:" + str(int(_scope_context.site.next_feature)), "work_target": {"cells": cells, "options": options}})

func _scope_fill_food_orders(query: Dictionary, previous: Dictionary) -> void:
	var settlement: Dictionary = query.site_ref.get("settlement", {})
	if query.scope != "settlement" or query.scope_id != settlement.get("settlement_id"): return
	var research: bool = query.project.get("tech_id") == "S06"
	if not research and not bool(query.get("known", false)): return
	for key: String in settlement.get("technology_operations", {}).get("orders", {}):
		var order: Dictionary = settlement.technology_operations.orders[key]
		if order.get("kind") != "food_order" or not Runtime.valid_settlement_food_order(query.terrain_ref, query.site_ref, order) \
			or order.status not in ["prepared", "active"]: continue
		if research:
			if order.payload.project_id != query.project.id or order.payload.purpose != query.project.purpose or order.payload.operator_id != query.project.executor.person_id: continue
		elif int(order.payload.project_id) != 0: continue
		_scope_add_target("原糧食單 %s · 倉庫#%s · %s · %.1f/300秒" % [key, str(order.payload.warehouse_id), str(order.payload.stage), float(order.payload.work_seconds)],
			{"kind": "food_order", "key": key, "target_ref": order, "target_id": Runtime.settlement_food_target(str(query.site_ref.id), str(query.scope_id), key)}, previous)

func _scope_fill_shot_targets(query: Dictionary, previous: Dictionary) -> void:
	if not query.terrain_ref.contains(_controller.selected): return
	var index: int = query.terrain_ref.index(_controller.selected)
	var key := str(int(query.terrain_ref.feature_at[index]))
	var feature: Dictionary = query.site_ref.get("features", {}).get(key, {})
	var geometry := Runtime.feature_geometry(query.terrain_ref, feature)
	for part_id: String in geometry.get("parts", {}):
		if not geometry.parts[part_id].cells.has(index): continue
		for id: String in query.site_ref.get("vehicles", {}):
			var vehicle: Dictionary = query.site_ref.vehicles[id]
			if not Runtime.siege_ammo_valid(str(vehicle.get("kind", "")), "fire_pot"): continue
			_scope_add_target("原投石機#%s → 真部件#%s/%s" % [id, key, part_id], {"kind": "scope_shot", "key": id, "target_ref": vehicle, "feature_ref": feature, "aim_cell": _controller.selected, "target_id": "vehicle:" + id, "work_target": {"type": "structure", "feature_id": key, "part_id": part_id}}, previous)

func _scope_project_person(query: Dictionary) -> Dictionary:
	for person: Dictionary in query.people:
		if int(person.person_id) == int(query.project.get("executor", {}).get("person_id", -1)): return person
	return {}

func _scope_tech_id() -> String:
	return str(_scope_node.get_item_metadata(_scope_node.selected)) if is_instance_valid(_scope_node) and _scope_node.selected >= 0 else ""

func _metal_scope_target(query: Dictionary, selected: Dictionary) -> Dictionary:
	var order: Dictionary = query.owner_ref.get("technology_operations", {}).get("orders", {}).get(str(selected.get("key", "")), {})
	if order.is_empty() or order.get("kind") != "metal_chain" or not is_same(order, selected.get("target_ref")) \
		or order.payload.project_id != query.project.get("id") or order.payload.purpose != query.project.get("purpose"): return Runtime.fail("STALE_SOURCE")
	var view: Dictionary = _controller.person_actions.settlement_metal_order_view(str(query.scope_id), str(order.id))
	if not view.ok: return view
	if view.binding != query.phase.get("binding") or view.target_id != selected.get("target_id") or selected.get("work_target") != {"order_id": str(order.id)}: return Runtime.fail("STALE_PHASE")
	return Runtime.ok("", {"target_id": str(view.target_id), "work_target": {"order_id": str(order.id)}})

func _productive_scope_selection(query: Dictionary, selected: Dictionary) -> Dictionary:
	var order: Dictionary = query.owner_ref.get("technology_operations", {}).get("orders", {}).get(str(selected.get("key", "")), {})
	if query.phase.is_empty() or order.is_empty() or not is_same(order, selected.get("target_ref")) or order.get("kind") != _productive_kind() or not Runtime.valid_settlement_processing_order(query.terrain_ref, query.site_ref, order) \
		or order.status not in ["prepared", "active", "suspended"] or order.payload.project_id != query.project.get("id") or order.payload.purpose != query.project.get("purpose") \
		or order.payload.operator_id != query.project.get("executor", {}).get("person_id") or selected.get("target_id") != "feature:" + str(order.payload.feature_id): return Runtime.fail("STALE_PROJECT")
	if not Runtime.settlement_operation_binding_valid(order, str(query.phase.binding)): return Runtime.fail("STALE_PHASE")
	return Runtime.ok("", {"target_id": str(selected.target_id), "work_target": {"order_id": str(order.id)}})

func _scope_food_selection(query: Dictionary, selected: Dictionary) -> Dictionary:
	var order: Dictionary = query.site_ref.get("settlement", {}).get("technology_operations", {}).get("orders", {}).get(str(selected.get("key", "")), {})
	if not is_same(order, selected.get("target_ref")) or not Runtime.valid_settlement_food_order(query.terrain_ref, query.site_ref, order) \
		or order.status not in ["prepared", "active"] \
		or selected.get("target_id") != Runtime.settlement_food_target(str(query.site_ref.id), str(query.scope_id), str(order.id)): return Runtime.fail("STALE_SOURCE")
	if query.project.get("tech_id") == "S06":
		if order.payload.project_id != query.project.id or order.payload.purpose != query.project.purpose or order.payload.operator_id != query.project.executor.person_id: return Runtime.fail("STALE_PROJECT")
	elif not bool(query.get("known", false)) or int(order.payload.project_id) != 0: return Runtime.fail("NO_TECHNOLOGY")
	return Runtime.ok("", {"target_id": str(selected.target_id), "work_target": {"order_id": str(order.id)}})

func _scope_shot_selection(query: Dictionary, selected: Dictionary) -> Dictionary:
	var vehicle: Dictionary = query.site_ref.get("vehicles", {}).get(str(selected.get("key", "")), {})
	var target: Dictionary = selected.get("work_target", {})
	var feature: Dictionary = query.site_ref.get("features", {}).get(str(target.get("feature_id", "")), {})
	var geometry := Runtime.feature_geometry(query.terrain_ref, feature)
	if _scope_tech_id() != "F15" or query.phase.get("binding") != "fire_pot_shot" or not is_same(vehicle, selected.get("target_ref")) or not is_same(feature, selected.get("feature_ref")) \
		or not Runtime.siege_ammo_valid(str(vehicle.get("kind", "")), "fire_pot") or selected.get("target_id") != "vehicle:" + str(selected.get("key", "")) \
		or selected.get("aim_cell") != _controller.selected or not query.terrain_ref.contains(_controller.selected) or target.get("type") != "structure" \
		or not geometry.get("parts", {}).has(str(target.get("part_id", ""))) or not geometry.parts[str(target.part_id)].cells.has(query.terrain_ref.index(_controller.selected)): return Runtime.fail("STALE_SOURCE")
	return Runtime.ok("", {"target_id": str(selected.target_id), "work_target": target.duplicate()})

func _scope_water_selection(query: Dictionary, selected: Dictionary) -> Dictionary:
	var site: Dictionary = query.site_ref
	var key := str(site.get("settlement", {}).get("center_id", ""))
	var center: Dictionary = site.get("features", {}).get(key, {})
	var target: Dictionary = selected.get("work_target", {})
	if selected.get("kind") != "water_schedule" or selected.get("key") != key or not is_same(center, selected.get("target_ref")) \
		or center.get("kind") != "settlement_center" or selected.get("target_id") != "feature:" + key \
		or not Technology.keys(target, ["categories"]) or not target.categories is Array: return Runtime.fail("STALE_SOURCE")
	return Runtime.ok("", {"target_id": "feature:" + key, "work_target": target.duplicate(true)})

func _scope_dispatch(method: String, arguments: Array, references: Array = [], maintenance: bool = false) -> void:
	var checked := _scope_submit_query(maintenance)
	if not checked.ok:
		_controller.show_result(checked)
		refresh()
		return
	if method in ["grant_scope_technology_budget", "request_scope_technology_consent", "stop_scope_technology"] \
		and (checked.project.get("tech_id") != _scope_tech_id() or int(checked.project.get("rules_version", -1)) != 2):
		_controller.show_result(Runtime.fail("STALE_PROJECT", "所選節點不是當前原活動項目"))
		refresh()
		return
	for reference: Dictionary in references:
		if _scope_row(checked.people, reference).is_empty():
			_controller.show_result(Runtime.fail("STALE_SOURCE", "所選原人已離開此範疇或原 owner/body 已替換"))
			refresh()
			return
	if method == "stop_technology":
		var row := _scope_row(checked.people, references[0] if not references.is_empty() else {})
		var job: Dictionary = row.get("job", {})
		if job.get("kind") != "technology_lesson" or str(job.get("technology_id", "F07")) != _scope_tech_id():
			_controller.show_result(Runtime.fail("NO_TARGET", "所選原人沒有本技藝的原授課作業"))
			refresh()
			return
	if not _controller.person_actions.has_method(method):
		_controller.show_result(Runtime.fail("UNIMPLEMENTED", "原作業入口尚未接線：" + method))
	else:
		_controller.show_result(_controller.person_actions.callv(method, arguments))
	refresh()

func _scope_requester() -> int:
	return int(_scope_context.get("control", -1))

func _scope_submit_query(maintenance: bool = false) -> Dictionary:
	if not _scope_context_current() or not _controller.person_actions.has_method("scope_technology_query"): return Runtime.fail("STALE_SOURCE", "原 Site／受控人已變更；請重新選擇")
	if _scope_kind() == "nation":
		var selected: Dictionary = _ref(_scope_nation_choice())
		if selected.get("id") != _scope_owner_id() or not is_same(selected.get("owner_ref"), _scope_context.owner): return Runtime.fail("STALE_SOURCE", "所選原國家已變更")
	if not maintenance and not _scope_activation_reason().is_empty(): return Runtime.fail("NOT_DELIVERED", _scope_activation_reason())
	var query: Dictionary = _controller.person_actions.call("scope_technology_query", _scope_tech_id(), _scope_owner_id())
	if not query.ok: return query
	if query.scope != _scope_kind() or query.scope_id != _scope_owner_id() or not is_same(query.owner_ref, _scope_context.owner) \
		or not is_same(query.terrain_ref, _scope_context.terrain) or not is_same(query.site_ref, _scope_context.site) or int(query.current_person_id) != _scope_requester(): return Runtime.fail("STALE_SOURCE", "原組織／Site 引用已變更；請重新選擇")
	return query

func _productive_form() -> Dictionary:
	return _root.get_meta(&"productive_form", {}) if is_instance_valid(_root) and _root.has_meta(&"productive_form") else {}

func _productive_kind() -> String:
	return str({"S03": "charcoal_batch", "S05": "textile_batch", "S12": "ship_cooperation"}.get(_scope_tech_id(), ""))

func _productive_result(result: Dictionary) -> void:
	_controller.show_result(result)
	refresh()

func _productive_source_selection(query: Dictionary) -> Dictionary:
	var selected := _ref(_productive_form().source)
	var id := str(selected.get("id", ""))
	if id.is_empty(): return Runtime.fail("NO_TARGET", "請明示原來源")
	var current: Dictionary = _controller.vehicles._stock(id, id.begins_with("feature:"))
	if current.is_empty() or not is_same(current.holder, selected.get("holder")) or not is_same(current.cargo, selected.get("cargo")): return Runtime.fail("STALE_SOURCE")
	return Runtime.ok("", {"holder_id": id, "source_feature_id": id.trim_prefix("feature:") if id.begins_with("feature:") else ""})

func _scope_row(people: Array, reference: Dictionary) -> Dictionary:
	if reference.is_empty(): return {}
	for person: Dictionary in people:
		if str(person.site_id) == str(reference.get("site_id", "")) and int(person.person_id) == int(reference.get("person_id", -1)) \
			and is_same(person.owner_ref, reference.get("owner_ref")) and is_same(person.body_ref, reference.get("body_ref")): return person
	return {}

func _productive_order(query: Dictionary) -> Dictionary:
	var selected := _ref(_productive_form().order)
	var order: Dictionary = query.owner_ref.get("technology_operations", {}).get("orders", {}).get(str(selected.get("key", "")), {})
	if order.is_empty() or not is_same(order, selected.get("target_ref")) or order.get("kind") != _productive_kind() or not Runtime.valid_settlement_processing_order(query.terrain_ref, query.site_ref, order): return Runtime.fail("STALE_SOURCE")
	return Runtime.ok("", {"order": order})

func _metal_current_order(query: Dictionary) -> Dictionary:
	var selected := _ref(_metal_form.order)
	var order: Dictionary = query.owner_ref.get("technology_operations", {}).get("orders", {}).get(str(selected.get("id", "")), {})
	return order if not order.is_empty() and order.get("kind") == "metal_chain" and is_same(order, selected.get("ref")) else {}

func _clear_scope_draft() -> void:
	_scope_context.clear()
	_survey_plan.clear()
	_survey_cells.clear()
	_scope_budget_key = ""
	for choice: OptionButton in [_scope_researcher, _scope_teacher, _scope_student, _scope_target, _scope_food_source]:
		if is_instance_valid(choice): choice.clear()
	_scope_unavailable("原 Site／人物上下文已變更；請重新選原人與原目標。")

func _refresh_metal_controls(query: Dictionary) -> void:
	if _metal_form.is_empty(): return
	_metal_form.box.visible = _scope_tech_id() == "S04"
	if not _metal_form.box.visible: return
	var smelters: Array = []
	var smithies: Array = []
	for key: String in query.site_ref.get("features", {}):
		var feature: Dictionary = query.site_ref.features[key]
		if feature.get("stage") != "complete" or feature.get("kind") not in ["smelter", "smithy"]: continue
		var row := {"id": key, "ref": feature, "title": "原 %s #%s · 接觸格 %s" % [str(feature.kind), key, str(feature.get("entrance", -1))]}
		if feature.kind == "smelter": smelters.append(row)
		else: smithies.append(row)
	_metal_fill(_metal_form.smelter, smelters, "請選真原冶爐")
	_metal_fill(_metal_form.smithy, smithies, "請選真原鍛坊")
	var people: Array = []
	for person: Dictionary in query.people: people.append({"id": int(person.person_id), "ref": person.body_ref, "title": "%s #%d · 同人操作／搬運" % [str(person.label), int(person.person_id)]})
	_metal_fill(_metal_form.person, people, "請具名原 F04 操作者／搬運者")
	var orders: Array = []
	for key: String in query.owner_ref.get("technology_operations", {}).get("orders", {}):
		var order: Dictionary = query.owner_ref.technology_operations.orders[key]
		if order.get("kind") == "metal_chain": orders.append({"id": key, "ref": order, "title": "%s · %s · 生產 %d/2 · 搬運 %d/2" % [key, str(order.status), int(order.payload.completed), order.payload.carry_receipts.size()]})
	_metal_fill(_metal_form.order, orders, "請選真原有限鏈")
	var selected := _ref(_metal_form.order)
	var view: Dictionary = _controller.person_actions.settlement_metal_order_view(str(query.scope_id), str(selected.get("id", ""))) if not selected.is_empty() and _controller.person_actions.has_method("settlement_metal_order_view") else Runtime.fail("NO_TARGET")
	_metal_form.status.text = "節點尚未交付驗收：只讀，不核額／扣料。" if not _scope_activation_reason().is_empty() else "先具名採用原鏈；所有提交仍重查原組織、人員、工位與實物來源。"
	if view.ok: _metal_form.status.text += "\n下一段 %s · 原人 #%d · %s\n用途總額 %s · 累計已用 %s · 來源 %s (%s)" % [str(view.binding), int(view.operator_id), str(view.target_id), Runtime.items_text(view.cap), Runtime.items_text(view.spent), str(view.source.holder), str(view.source.status)]
	var enabled := _scope_activation_reason().is_empty() and int(query.research_decider) == _scope_requester()
	_metal_form.request.disabled = not enabled or _ref(_metal_form.smelter).is_empty() or _ref(_metal_form.smithy).is_empty() or _ref(_metal_form.person).is_empty()
	for button: Button in [_metal_form.begin, _metal_form.grant]: button.disabled = not enabled or not view.ok or view.status in ["completed", "cancelled"]
	for button: Button in [_metal_form.revoke, _metal_form.stop, _metal_form.cancel]: button.disabled = int(query.research_decider) != _scope_requester() or not view.ok or view.status in ["completed", "cancelled"]

func _refresh_productive_controls(query: Dictionary) -> void:
	var form := _productive_form()
	if form.is_empty(): return
	_scope_fill_people(form.helper, query.people)
	# S12 carriers follow the order's own per-person rule (query.carriers).
	_scope_fill_people(form.carrier, query.get("carriers", []) if _productive_kind() == "ship_cooperation" else query.people)
	var old_source := _ref(form.source)
	form.source.clear()
	form.source.add_item("請明示原有限來源（不自動選來源）")
	form.source.set_item_metadata(0, {})
	var ids: Array[String] = ["depot"]
	for key: String in query.site_ref.get("stockpiles", {}): ids.append("feature:" + key)
	for id: String in ids:
		var stock: Dictionary = _controller.vehicles._stock(id, id.begins_with("feature:"))
		if stock.is_empty(): continue
		form.source.add_item("原來源 " + id)
		form.source.set_item_metadata(form.source.item_count - 1, {"id": id, "holder": stock.holder, "cargo": stock.cargo})
		if old_source.get("id") == id and is_same(old_source.get("holder"), stock.holder) and is_same(old_source.get("cargo"), stock.cargo): form.source.select(form.source.item_count - 1)
	var old_order := _ref(form.order)
	form.order.clear()
	form.order.add_item("請選本原有限工單")
	form.order.set_item_metadata(0, {})
	for key: String in query.owner_ref.get("technology_operations", {}).get("orders", {}):
		var order: Dictionary = query.owner_ref.technology_operations.orders[key]
		if order.get("kind") != _productive_kind() or not Runtime.valid_settlement_processing_order(query.terrain_ref, query.site_ref, order): continue
		form.order.add_item("%s · %s · 已付%s" % [key, str(order.status), Runtime.items_text(order.payload.spent)])
		form.order.set_item_metadata(form.order.item_count - 1, {"key": key, "target_ref": order})
		if old_order.get("key") == key and is_same(old_order.get("target_ref"), order): form.order.select(form.order.item_count - 1)
	var relevant: bool = _scope_tech_id() in ["S03", "S05", "S11", "S12"] and query.scope == "settlement"
	form.status.text = "原地圖目前設施 #%s；首長、師傅、來源接觸與同意均於原入口重查。" % str(_controller.feature_key) if relevant else "此區只對S03／S05／S11／S12；其他節點沿上方原操作。"
	var reason := _first_reason([_scope_activation_reason(), "請選S03／S05／S12原有限工序。" if _productive_kind().is_empty() or query.scope != "settlement" else ""])
	for key: String in ["ScopeProductivePreview", "ScopeProductiveAdopt", "ScopeProductiveStep", "ScopeProductiveGrant"]: _scope_reason(key, reason)
	for key: String in ["ScopeProductiveRevoke", "ScopeProductivePause", "ScopeProductiveRelease"]: _scope_reason(key, "請選本原有限工單。" if _productive_kind().is_empty() or _ref(form.order).is_empty() else "")
	_scope_reason("ScopeYardAdopt", _first_reason([_scope_activation_reason(), "僅本聚落已知S11／S12可指定原工位。" if _scope_tech_id() not in ["S11", "S12"] or not bool(query.known) else ""]))
	_scope_reason("ScopeYardRevoke", "只對原S11／S12設施配置。" if _scope_tech_id() not in ["S11", "S12"] or query.scope != "settlement" else "")

func _refresh_scope_nations(scope_kind: String) -> void:
	var choice := _scope_nation_choice()
	if not is_instance_valid(choice): return
	var previous := _ref(choice)
	choice.clear()
	choice.add_item("請明示選擇原國家")
	choice.set_item_metadata(0, {})
	for identity: String in _controller.lab.terrain.site.get("equipment_nations", {}):
		var owner: Dictionary = _controller.lab.terrain.site.equipment_nations[identity]
		choice.add_item(identity)
		choice.set_item_metadata(choice.item_count - 1, {"id": identity, "owner_ref": owner})
		if previous.get("id") == identity and is_same(previous.get("owner_ref"), owner): choice.select(choice.item_count - 1)
	choice.visible = scope_kind == "nation"

func _scope_activation_reason() -> String:
	if _scope_tech_id() == "F07": return "F07 請使用上方原製弓入口。"
	return "尚未交付真實新操作／效果與具名驗收；目前只讀，不核額、不收費。" if not bool(Catalog.get_node(_scope_tech_id()).get("enabled", false)) else ""

func _scope_context_current() -> bool:
	if _scope_context.is_empty() or not is_instance_valid(_controller) or _controller.lab == null: return false
	var lab: Variant = _controller.lab
	return lab.terrain != null and is_same(lab.terrain, _scope_context.terrain) and is_same(lab.terrain.site, _scope_context.site) \
		and str(lab.terrain.site.get("id", "")) == str(_scope_context.site_id) and int(lab.controlled_person_id()) == _scope_requester()

func _scope_fill_budget(project: Dictionary) -> void:
	var key := JSON.stringify([_scope_tech_id(), _scope_route_id(), int(project.get("id", 0)), project.get("budget", {}).get("cap", {})])
	if key == _scope_budget_key: return
	_scope_budget_key = key
	for child: Node in _scope_budget_row.get_children(): child.queue_free()
	_scope_caps.clear()
	var cap: Dictionary = Catalog.research_budget(_scope_tech_id(), _scope_route_id()).get("transaction_inputs", {}).duplicate()
	for resource: String in project.get("budget", {}).get("cap", {}): cap[resource] = int(project.budget.cap[resource])
	for resource: String in cap:
		var amount := _amount(_scope_budget_row, str(Env.ITEM_NAMES.get(resource, resource)), "ScopeCap" + resource, int(cap[resource]))
		amount.min_value = 0
		amount.max_value = 1000000
		_scope_caps[resource] = amount

func _scope_fill_food_sources(query: Dictionary) -> void:
	var previous := _ref(_scope_food_source)
	_scope_food_source.clear()
	_scope_food_source.add_item("請明示有限糧食來源")
	_scope_food_source.set_item_metadata(0, {})
	_scope_food_source.disabled = _scope_tech_id() != "S06"
	if _scope_food_source.disabled: return
	var choices: Array[String] = ["depot"]
	for key: String in query.site_ref.get("stockpiles", {}): choices.append("feature:" + key)
	for identity: String in choices:
		var stock: Dictionary = _controller.vehicles._stock(identity, identity.begins_with("feature:"))
		if stock.is_empty() or stock.get("withdraw_only", false) or int(stock.get("faction", int(query.owner_ref.get("owner_faction", -1)))) != int(query.owner_ref.get("owner_faction", -2)): continue
		_scope_food_source.add_item("原%s · 現有%d糧 · 本单最多8糧" % [identity, int(stock.cargo.get("grain", 0))])
		_scope_food_source.set_item_metadata(_scope_food_source.item_count - 1, {"holder_id": identity, "holder": stock.holder, "cargo": stock.cargo})
		if previous.get("holder_id") == identity and is_same(previous.get("holder"), stock.holder) and is_same(previous.get("cargo"), stock.cargo): _scope_food_source.select(_scope_food_source.item_count - 1)

func _scope_fill_people(choice: OptionButton, people: Array) -> void:
	var previous := _ref(choice)
	choice.clear()
	choice.add_item("請選本 Site 原人")
	choice.set_item_metadata(0, {})
	for person: Dictionary in people:
		choice.add_item("%s #%d · 隊 #%d · %s%s" % [str(person.label), int(person.person_id), int(person.team_id), "已學" if bool(person.learned) else "未學", " · 忙碌" if bool(person.busy) else ""])
		var reference := {"site_id": str(person.site_id), "person_id": int(person.person_id), "owner_ref": person.owner_ref, "body_ref": person.body_ref}
		choice.set_item_metadata(choice.item_count - 1, reference)
		if not _scope_row([person], previous).is_empty(): choice.select(choice.item_count - 1)

func _scope_nation_choice() -> OptionButton:
	return _root.get_meta(&"nation_scope_choice", null) as OptionButton

func _scope_reason(key: String, reason: String) -> void:
	var button: Button = _scope_buttons[key]
	button.disabled = not reason.is_empty()
	button.tooltip_text = reason if not reason.is_empty() else "提交時重查原權限、來源、同意、工位與完整候選。"

func _scope_route_id() -> String:
	return str(_scope_route.get_item_metadata(_scope_route.selected)) if is_instance_valid(_scope_route) and _scope_route.selected >= 0 else ""

func _supervised_submit(method: String) -> void:
	if method not in ["begin_captive_craft", "stop_captive_craft", "begin_technology_analysis"]:
		_controller.show_result(Runtime.fail("UNSUPPORTED"))
		return
	if not _supervised_context_current():
		_controller.show_result(Runtime.fail("STALE_SOURCE", "原Site／受控人已變更，請重新明選。"))
		_supervised_clear()
		refresh()
		return
	var query := _supervised_query()
	if not query.ok:
		_controller.show_result(query)
		refresh()
		return
	var pairs: Array = [["analyst", "analysts"], ["vehicle", "vehicles"]] if method == "begin_technology_analysis" else [["captive", "captives"], ["supervisor", "supervisors"]]
	for pair: Array in pairs:
		var selected := _ref(_supervised_form[pair[0]])
		var found := false
		for row: Dictionary in query[pair[1]]:
			if _supervised_same(selected, row): found = true; break
		if not found:
			_controller.show_result(Runtime.fail("STALE_SOURCE", "未明選或原人物／監管／項目／器械引用已替換。"))
			refresh()
			return
	var requester := int(query.current_person_id)
	var arguments: Array = [requester, _id(_supervised_form.analyst), str(_ref(_supervised_form.vehicle).vehicle_id)] if method == "begin_technology_analysis" else [requester, _id(_supervised_form.captive)]
	if method == "begin_captive_craft": arguments.append(_id(_supervised_form.supervisor)); arguments.append("bow")
	_controller.show_result(_controller.person_actions.callv(method, arguments))
	refresh()

func _supervised_clear() -> void:
	_supervised_form.erase("context")
	for key: String in ["captive", "supervisor", "analyst", "vehicle"]:
		var choice: Variant = _supervised_form.get(key)
		if is_instance_valid(choice): choice.clear()
	_supervised_unavailable("原 Site／受控人變更，請重新明選原參與者。")

func _supervised_context_current() -> bool:
	var context: Dictionary = _supervised_form.get("context", {})
	return not context.is_empty() and is_instance_valid(_controller) and _controller.lab != null and _controller.lab.terrain != null \
		and is_same(_controller.lab.terrain, context.terrain) and is_same(_controller.lab.terrain.site, context.site) \
		and str(_controller.lab.terrain.site.get("id", "")) == str(context.site_id) and int(_controller.lab.controlled_person_id()) == int(context.control)

func _supervised_fill(choice: OptionButton, rows: Array, title: String) -> void:
	var previous := _ref(choice)
	choice.clear()
	choice.add_item(title)
	choice.set_item_metadata(0, {})
	choice.disabled = rows.is_empty()
	for row: Dictionary in rows:
		choice.add_item(str(row.label))
		choice.set_item_metadata(choice.item_count - 1, row.duplicate())
		if _supervised_same(previous, row): choice.select(choice.item_count - 1)

func _supervised_query() -> Dictionary:
	if not is_instance_valid(_controller) or _controller.lab == null or not _controller.person_actions.has_method("technology_supervision_query"): return Runtime.fail("NO_OWNER_HOOK", "原監管／分析只讀入口尚未接線。")
	return _controller.person_actions.call("technology_supervision_query", _id(_supervised_form.captive), _id(_supervised_form.supervisor), _id(_supervised_form.analyst), str(_ref(_supervised_form.vehicle).get("vehicle_id", "")))

func _supervised_unavailable(reason: String) -> void:
	if is_instance_valid(_supervised_form.get("status")): _supervised_form.status.text = reason
	for key: String in ["begin_captive", "stop_captive", "begin_analysis"]:
		var button: Variant = _supervised_form.get(key)
		if is_instance_valid(button): button.disabled = true; button.tooltip_text = reason

func _install_metal_controls() -> void:
	var box := VBoxContainer.new()
	box.name = "SettlementMetalChain"
	box.visible = false
	_root.add_child(box)
	_metal_form.box = box
	box.add_child(HSeparator.new())
	_controller._label(box, "S04 冶鐵協作 · 原同人三段有限鏈", 18)
	_controller._label(box, "原冶爐 3 礦＋2 炭→2 鐵／900 秒；本人分別接觸冶爐與鍛坊搬運 2 鐵；原鍛坊 2 鐵＋1 炭＋1 木→1 工具／720 秒。\n初始輸入先用原裝卸搬入冶爐；搬入鍛坊後首長須在鍛坊明示續用來源。研究付款不向營地另扣。", 14)
	_metal_form.smelter = _controller._options(box, [], "MetalOriginalSmelter")
	_metal_form.smithy = _controller._options(box, [], "MetalOriginalSmithy")
	_metal_form.person = _controller._options(box, [], "MetalOriginalOperatorCarrier")
	_metal_form.order = _controller._options(box, [], "MetalOriginalOrder")
	for choice: OptionButton in [_metal_form.smelter, _metal_form.smithy, _metal_form.person, _metal_form.order]:
		choice.item_selected.connect(func(_index: int) -> void: refresh())
	_metal_form.status = _controller._label(box, "", 14)
	var row := HBoxContainer.new()
	box.add_child(row)
	_metal_form.request = _controller._button(row, "採用所選三段原鏈", "MetalRequestOrder", _metal_request)
	_metal_form.begin = _controller._button(row, "開始／接續下一真段", "MetalBeginNext", _metal_begin)
	row = HBoxContainer.new()
	box.add_child(row)
	_metal_form.grant = _controller._button(row, "在当前原來源明示續用", "MetalGrantSource", func() -> void: _metal_dispatch("grant_settlement_metal_source", [false]))
	_metal_form.revoke = _controller._button(row, "撤銷本原材料用途", "MetalRevokeSource", func() -> void: _metal_dispatch("grant_settlement_metal_source", [true], true))
	_metal_form.stop = _controller._button(row, "停止本普通原鏈", "MetalStopOrder", func() -> void: _metal_dispatch("stop_settlement_metal_order", [false], true))
	_metal_form.cancel = _controller._button(row, "永久取消本普通原鏈", "MetalCancelOrder", func() -> void: _metal_dispatch("stop_settlement_metal_order", [true], true))

func _install_productive_controls() -> void:
	_label("S03／S05／S11／S12 · 原設施採用與有限工單", 18)
	_label("先在原地圖選本設施，再具名原人與來源。S03最多3批、S05最多2批；S12一艘渡船、兩名同原隊NPC工人、一搬料者。兩腿搬料後在真船塢核來源；原庫位／装卸仍由設施庫存窗管理。受控原人可沿原單人派工，雙人船單保留原NPC限制。", 15)
	var form := {"helper": _choice("ScopeProductiveHelper"), "carrier": _choice("ScopeProductiveCarrier"), "source": _choice("ScopeProductiveSource"), "order": _choice("ScopeProductiveOrder"), "status": _label("", 15)}
	_root.set_meta(&"productive_form", form) # Unsaved UI draft; no gameplay owner.
	_scope_button("預檢目前原設施採用／有限工單", "ScopeProductivePreview", func() -> void: _productive_adopt(true))
	_scope_button("明示採用目前原設施有限工單", "ScopeProductiveAdopt", func() -> void: _productive_adopt(false))
	_scope_button("沿原工單實交下一腿／開始或續作", "ScopeProductiveStep", _productive_step)
	_scope_button("在所選原來源明示續用本單總額", "ScopeProductiveGrant", func() -> void: _productive_source(false))
	_scope_button("撤銷本單材料用途（已付不退）", "ScopeProductiveRevoke", func() -> void: _productive_source(true))
	_scope_button("停止本有限工單（保留已付）", "ScopeProductivePause", func() -> void: _productive_stop(false))
	_scope_button("永久撤回本有限工單", "ScopeProductiveRelease", func() -> void: _productive_stop(true))
	_scope_button("指定目前原校場／船塢工位", "ScopeYardAdopt", func() -> void: _productive_configure(true))
	_scope_button("撤回目前原校場／船塢工位", "ScopeYardRevoke", func() -> void: _productive_configure(false))
	_controller._button(_root, "開目前原設施庫存／装卸窗", "ScopeProductiveStorage", func() -> void: _controller._open_feature_storage())

func _scope_begin() -> void:
	var query := _scope_submit_query()
	if not query.ok:
		_controller.show_result(query)
		refresh()
		return
	var selected := _ref(_scope_target)
	var current := _scope_target_candidate(query, selected)
	if not current.ok:
		_controller.show_result(current)
		refresh()
		return
	_scope_dispatch("begin_scope_technology_phase", [_scope_requester(), _scope_kind(), _scope_owner_id(), str(query.phase.binding), str(current.target_id), current.work_target])

func _scope_budget(operation: String) -> void:
	var cap := {}
	for resource: String in _scope_caps: cap[resource] = int(_scope_caps[resource].value)
	_scope_dispatch("grant_scope_technology_budget", [_scope_requester(), _scope_kind(), _scope_owner_id(), cap, operation], [], operation == "revoke")

func _scope_button(title: String, key: String, action: Callable) -> void:
	_scope_buttons[key] = _controller._button(_root, title, key, action)

func _scope_capture_survey() -> void:
	if not _scope_context_current() or _scope_tech_id() != "F09": return
	var cells: Array[int] = _controller.build_cells.duplicate()
	var kind := str(_controller._building_kind())
	var options: Dictionary = _controller._building_options().duplicate(true)
	var checked := Runtime.preview_build(_controller.lab.terrain, kind, cells, _controller.reserves_cell, options)
	if checked.ok:
		_survey_plan = {"kind": kind, "cells": cells, "options": options}
		_controller.show_result(Runtime.ok("完整原施工方案已記為視窗草稿；尚未付款或建造"))
	else: _controller.show_result(checked)
	refresh()

func _scope_food_cancel() -> void:
	var query := _scope_submit_query(true)
	if not query.ok: _controller.show_result(query); return
	var selection := _scope_food_selection(query, _ref(_scope_target))
	if not selection.ok: _controller.show_result(selection); return
	_scope_dispatch("cancel_settlement_food_order", [_scope_requester(), str(query.scope_id), str(selection.work_target.order_id)], [], true)

func _scope_kind() -> String:
	return str(_scope_context.get("scope", ""))

func _scope_owner_id() -> String:
	return str(_scope_context.get("scope_id", ""))

func _scope_pick_stake(index: int) -> void:
	if not _scope_context_current() or _scope_tech_id() != "F09": return
	if index > _survey_cells.size():
		_controller.show_result(Runtime.fail("NO_TARGET", "先選第一個原測樁實格"))
		return
	var cell: Vector2i = _controller.selected
	if not _controller.lab.terrain.contains(cell):
		_controller.show_result(Runtime.fail("INVALID", "須選本 Site 真地圖實格"))
		return
	var identity: int = _controller.lab.terrain.index(cell)
	if _survey_cells.size() > 0 and _survey_cells[0] == identity and index == 1:
		_controller.show_result(Runtime.fail("INVALID", "兩個原測樁須不同實格"))
		return
	if index == _survey_cells.size(): _survey_cells.append(identity)
	else: _survey_cells[index] = identity
	refresh()

func _scope_prepare(mode: String) -> void:
	_scope_dispatch("prepare_scope_technology", [_scope_requester(), _id(_scope_researcher), _scope_tech_id(), _scope_owner_id(), _scope_route_id(), mode], [_ref(_scope_researcher)])

func _metal_unavailable() -> void:
	if _metal_form.is_empty(): return
	_metal_form.box.visible = false
	for key: String in ["smelter", "smithy", "person", "order"]: _metal_form[key].clear()

func _metal_fill(choice: OptionButton, rows: Array, title: String) -> void:
	var previous: Dictionary = _ref(choice)
	choice.clear()
	choice.add_item(title)
	choice.set_item_metadata(0, {})
	for row: Dictionary in rows:
		choice.add_item(str(row.title))
		choice.set_item_metadata(choice.item_count - 1, row)
		if row.get("id") == previous.get("id") and is_same(row.get("ref"), previous.get("ref")): choice.select(choice.item_count - 1)

func _supervised_same(previous: Dictionary, current: Dictionary) -> bool:
	if previous.is_empty() or current.is_empty(): return false
	for key: String in ["person_id", "guard_id", "vehicle_id", "project_id", "purpose", "relation_state", "capture_state"]:
		if previous.get(key) != current.get(key): return false
	for key: String in ["owner_ref", "body_ref", "holder_ref", "cargo_ref", "relation_ref", "vehicle_ref", "capture_ref", "project_ref", "family_ref"]:
		if not is_same(previous.get(key), current.get(key)): return false
	return true

func _metal_dispatch(method: String, extra: Array, maintenance: bool = false) -> void:
	var query := _scope_submit_query(maintenance)
	if not query.ok: _controller.show_result(query); refresh(); return
	var order := _metal_current_order(query)
	if order.is_empty(): _controller.show_result(Runtime.fail("STALE_SOURCE")); refresh(); return
	var args: Array = [_scope_requester(), str(query.scope_id), str(order.id)]
	args.append_array(extra)
	_scope_dispatch(method, args, [], maintenance)

func _productive_stop(permanent: bool) -> void:
	var query := _scope_submit_query(true)
	if not query.ok: _productive_result(query); return
	var selected := _productive_order(query)
	if not selected.ok: _productive_result(selected); return
	var runtime: Variant = Runtime
	_productive_result(runtime.call("stop_settlement_ship_order" if selected.order.kind == "ship_cooperation" else "stop_settlement_processing_order", query.terrain_ref, str(query.scope_id), str(selected.order.id), _scope_requester(), permanent))

var _metal_form: Dictionary = {} # Original window input draft only.

var _scope_food_source: OptionButton # UI draft only; no saved source authority.

var _supervised_form: Dictionary = {} # UI choices/context only; never saved gameplay state.

const Catalog = preload("res://scripts/terrain_lab/site_technology_catalog.gd")
const Technology = preload("res://scripts/terrain_lab/site_technology.gd")

const Env = preload("res://scripts/terrain_lab/site_environment.gd")

var _scope_node: OptionButton

var _scope_route: OptionButton

var _scope_researcher: OptionButton

var _scope_teacher: OptionButton

var _scope_student: OptionButton

var _scope_target: OptionButton

var _scope_facing: OptionButton

var _scope_status: Label

var _scope_details: Label

var _scope_budget_row: HBoxContainer

var _scope_caps: Dictionary = {}

var _scope_buttons: Dictionary = {}

var _scope_context: Dictionary = {} # Presentation refs only, never authority.

var _scope_budget_key := ""

var _survey_plan: Dictionary = {}

var _survey_cells: Array[int] = []
