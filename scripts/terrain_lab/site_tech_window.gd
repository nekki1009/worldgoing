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
	refresh()

func refresh() -> void:
	if _refreshing or not is_instance_valid(_root): return
	_refreshing = true
	if not is_instance_valid(_controller) or _controller.lab == null or _controller.lab.terrain == null:
		_unavailable("原 Site 尚未就緒。")
		_refreshing = false
		return
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
