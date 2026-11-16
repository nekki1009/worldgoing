extends RefCounted
## 財政頁 (軍餉與稅收 P4, reports/pay-and-tax-plan.md §7). One dialog for the organizations the controlled person runs
## here: his team (as captain), the settlement (as head or 度支), a nation (as head or 財產徵支).
## - team: pay source (a stockpile of the team's faction or one of its vehicles), pay rate 50–200%, next payday, this
##   month's bill against what the source holds, members owed pay, 犒賞 (SitePayReward);
## - settlement: production tax rate and tax source, the fief treasury, this season's receipts, the next tax day, the
##   liege, unpaid seasons, residents' tax grievance, 「可養 N 人」 (§4.4);
## - nation: its treasury (R4), auto-funding of its teams, last funding; a faction head exempts a vassal's fief for the
##   next season.
## The data calls live here so tests can drive them without the dialog.
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Finance = preload("res://scripts/terrain_lab/site_finance.gd")
const PayTable = preload("res://scripts/terrain_lab/site_pay_table.gd")
const Payroll = preload("res://scripts/terrain_lab/site_payroll.gd")
const ProduceTax = preload("res://scripts/terrain_lab/site_produce_tax.gd")
const Tribute = preload("res://scripts/terrain_lab/site_tribute.gd")
const Reward = preload("res://scripts/terrain_lab/site_pay_reward.gd")
const Calendar = preload("res://scripts/terrain_lab/site_calendar.gd")
const Settlement = preload("res://scripts/terrain_lab/site_settlement.gd")
const Stocks = preload("res://scripts/terrain_lab/site_stockpiles.gd")
const EquipmentOrders = preload("res://scripts/terrain_lab/site_equipment_orders.gd")
const PersonSocial = preload("res://scripts/terrain_lab/person_social.gd")
const RegionFinance = preload("res://scripts/region_lab/region_finance.gd")
const BanditProtection = preload("res://scripts/terrain_lab/site_bandit_protection.gd")

## Soldier pay and food for a season (§4.4: 30 + 90 points).
const SOLDIER_SEASON := 120

static func _today(lab: Variant) -> int:
	return Calendar.day_index(float(lab.terrain.site.get("minute", 0)))

## [{kind, ref, label}] of the organizations the controlled person may run here.
static func orgs(lab: Variant) -> Array:
	var result: Array = []
	var me := int(lab.controlled_person_id())
	var site_id := str(lab.terrain.site.get("id", ""))
	var team: Variant = lab.player_army()
	if team != null and is_instance_valid(team):
		var ref := {"kind": "team", "site_id": site_id, "org_id": str(team.team_id)}
		if Payroll.authority(lab, ref) == me: result.append({"kind": "team", "ref": ref, "label": "本隊 #%d" % int(team.team_id)})
	var settlement_ref := ProduceTax.settlement_ref(lab.terrain)
	if not settlement_ref.is_empty() and (Settlement.head_executor(lab, true) == me or ProduceTax.decider(lab) == me):
		result.append({"kind": "settlement", "ref": settlement_ref, "label": "聚落 %s" % str(Settlement.record(lab.terrain).get("name", settlement_ref.org_id))})
	var nations: Dictionary = lab.terrain.site.get("equipment_nations", {})
	var keys: Array = nations.keys()
	keys.sort()
	for nation_id: String in keys:
		var ref := {"kind": "nation", "site_id": site_id, "org_id": nation_id}
		if Payroll.authority(lab, ref) == me or Payroll._nation_finance(lab, ref) == me: result.append({"kind": "nation", "ref": ref, "label": "國家 %s" % nation_id})
	return result

## [{label, source}] of the holders an organization may bind here.
static func holders(lab: Variant, ref: Dictionary) -> Array:
	var result: Array = []
	var site_id := str(lab.terrain.site.get("id", ""))
	var keys: Array = lab.terrain.site.get("stockpiles", {}).keys()
	keys.sort()
	for key: String in keys:
		var source := {"kind": "stock", "site_id": site_id, "feature_id": key}
		if not Payroll.source_check(lab, ref, source).ok: continue
		var feature: Dictionary = lab.terrain.site.features.get(key, {})
		result.append({"label": "%s #%s" % [str(Runtime.FEATURES.get(str(feature.get("kind", "")), {}).get("name", feature.get("kind", ""))), key], "source": source})
	if str(ref.kind) == "team":
		var vehicles: Array = lab.terrain.site.get("vehicles", {}).keys()
		vehicles.sort()
		for key: String in vehicles:
			var source := {"kind": "vehicle", "site_id": site_id, "vehicle_id": key}
			if Payroll.source_check(lab, ref, source).ok: result.append({"label": "車輛 #%s" % key, "source": source})
	return result

static func _holder_text(lab: Variant, source: Dictionary) -> String:
	if source.is_empty(): return "未綁定"
	var found := Payroll.source_of(lab, source)
	if found.is_empty(): return "已失效"
	var coin := int(found.cargo.get("coin", 0))
	var food := 0
	for item: String in PayTable.FOOD_ORDER: food += int(found.cargo.get(item, 0))
	return "#%s（幣 %d、糧 %d）" % [str(source.get("feature_id", source.get("vehicle_id", ""))), coin, food]

## The org's summary lines.
static func summary(lab: Variant, org: Dictionary) -> String:
	var ref: Dictionary = org.ref
	var today := _today(lab)
	var record := Finance.record_of(lab.terrain, ref, today)
	var lines: Array = []
	match str(ref.kind):
		"team":
			var next := Calendar.next_start(today + 1)
			var bill := Tribute.bill(lab, record) if Finance.records(lab.terrain).has(Finance.org_key(ref)) else 0
			var source := Payroll.source_of(lab, record.pay_source)
			var held := Tribute.goods_tenths(Tribute.pick_goods(source.cargo, 2000000000)) if not source.is_empty() else 0
			lines.append("餉源：%s · 餉表倍率 %d%%" % [_holder_text(lab, record.pay_source), int(record.pay_rate)])
			lines.append("下個發餉日：%s（%d 日後）" % [Calendar.date_text(float(Calendar.day_start_minute(next))), next - today])
			lines.append("本期應付約 %.1f 點；餉源可付 %.1f 點%s" % [float(bill) / PayTable.TENTHS, float(held) / PayTable.TENTHS, "（不足）" if held < bill else ""])
			var owed := 0
			var roll := Payroll.roll_of(lab, ref)
			for identity: Variant in roll.roles:
				var person: Dictionary = lab.site_controller.person_actions._person(int(identity), false)
				if not person.is_empty() and person.get("body") != null and int(PersonSocial.arrears_for(person.body, Finance.org_key(ref)).tenths) >= PayTable.TENTHS: owed += 1
			lines.append("欠餉人數：%d／%d" % [owed, roll.roles.size()])
			if Finance.grace_left(record, today) > 0: lines.append("寬限期尚餘 %d 日（期內欠餉不記不滿）" % Finance.grace_left(record, today))
		"settlement":
			var season := PayTable.season_index(today)
			var next := Calendar.next_start(today + 1, true)
			var receipts := 0
			var last := 0
			for kind: String in Tribute.TRIBUTE_KINDS:
				receipts += Finance.receipts_of(record, kind, season)
				last += Finance.receipts_of(record, kind, season, true)
			var treasury := Payroll.source_of(lab, record.treasury)
			var stored := Tribute.goods_tenths(Tribute.pick_goods(treasury.cargo, 2000000000)) if not treasury.is_empty() else 0
			var ctx := Tribute.context_of(lab)
			var liege := Tribute.liege_of(ctx, Settlement.head_executor(lab, true))
			lines.append("產出稅 %d%% · 稅源：%s" % [int(record.tax_rate), _holder_text(lab, record.tax_source)])
			lines.append("封地庫：%s" % _holder_text(lab, record.treasury))
			lines.append("本季實收 %.1f 點（上季 %.1f 點）" % [float(receipts) / PayTable.TENTHS, float(last) / PayTable.TENTHS])
			lines.append("下次繳稅日：%s · 繳給：%s · 欠繳 %d 季" % [Calendar.date_text(float(Calendar.day_start_minute(next))), "無上級" if liege.is_empty() else str(liege.key), int(record.unpaid_seasons)])
			lines.append("可養約 %d 人（上季實收＋封地庫半數，每兵每季 %d 點）" % [floori((float(last) + float(stored) * 0.5) / PayTable.TENTHS / SOLDIER_SEASON), SOLDIER_SEASON])
			var grievance := int(ProduceTax.UNHAPPY.get(int(record.tax_rate), 0))
			if grievance > 0: lines.append("稅率偏高：登記居民 %d 人每日不滿 +%d" % [ProduceTax.residents(lab.terrain).size(), grievance])
			var asked: Dictionary = BanditProtection.pending.get(str(lab.terrain.site.get("id", "")), {})
			for band: Variant in asked: lines.append("土匪（勢力 %d）索要保護費 %d 糧，尚未答覆" % [int(band), int(asked[band])])
			if int(record.tax_rate) > PayTable.FREE_TAX_MAX or not ProduceTax.high_rate_allowed(lab.terrain): lines.append("15%／20% 需要國家已知「稅籍與財政制度」（N09）")
		"nation":
			var nation: Dictionary = lab.terrain.site.get("equipment_nations", {}).get(str(ref.org_id), {})
			var treasury_ref: Dictionary = nation.get("ransom_data", {}).get("treasury", {})
			var source := {"kind": "stock", "site_id": str(ref.site_id), "feature_id": str(treasury_ref.get("feature_id", ""))} if not treasury_ref.is_empty() else {}
			lines.append("國庫：%s" % _holder_text(lab, source))
			lines.append("自動撥餉給本國隊伍：%s（發餉日前 1 日，每日上限 %d 枚、留底 %d 枚）" % ["開" if bool(record.auto_fund) else "關", Tribute.FUND_DAILY, Tribute.FUND_RESERVE])
			lines.append("本季已撥 %.1f 點" % (float(Finance.receipts_of(record, "fund", PayTable.season_index(today))) / PayTable.TENTHS))
	return "\n".join(lines)

## The faction head's vassal fiefs he may exempt: [{label, site_id}].
static func vassal_fiefs(lab: Variant) -> Array:
	var ctx := Tribute.context_of(lab)
	var registry: Dictionary = ctx.registry
	var result: Array = []
	if registry.is_empty(): return result
	var me := RegionPeerage.world_person_ref(str(ctx.world), int(lab.controlled_person_id()))
	var record := RegionPeerage.record_of(registry, me)
	if record.is_empty() or record.get("liege_ref") != null: return result
	for vassal: Variant in RegionPeerage.vassals_of(registry, me):
		var fiefs: Dictionary = RegionPeerage.record_of(registry, vassal).get("fiefs", {})
		var sites: Array = fiefs.keys()
		sites.sort()
		for site_id: String in sites: result.append({"label": "%s 的封地 %s" % [RegionPeerage.key_of(vassal), site_id], "site_id": site_id})
	return result

# --- Commands ------------------------------------------------------------------------------------------------------

static func bind(lab: Variant, org: Dictionary, field: String, source: Dictionary) -> Dictionary:
	var me := int(lab.controlled_person_id())
	match field:
		"pay_source": return Payroll.bind_pay_source(lab, me, org.ref, source)
		"tax_source":
			var record := Finance.record_of(lab.terrain, org.ref, _today(lab))
			return ProduceTax.set_tax(lab, me, int(record.tax_rate), source)
		"treasury": return Tribute.bind_treasury(lab, me, source)
	return Runtime.fail("INVALID")

static func set_auto_fund(lab: Variant, org: Dictionary, on: bool) -> Dictionary:
	var me := int(lab.controlled_person_id())
	if str(org.ref.kind) != "nation" or (me != Payroll.authority(lab, org.ref) and me != Payroll._nation_finance(lab, org.ref)): return Runtime.fail("NO_AUTHORITY", "只有元首或財產徵支能改自動撥餉")
	var made := Finance.ensure(lab.terrain, org.ref, _today(lab))
	if not made.ok: return made
	made.record.auto_fund = on
	return Runtime.ok("自動撥餉已" + ("開啟" if on else "關閉"))

## Answers the first pending protection demand on this Site (the settlement's head only).
static func _answer_protection(lab: Variant, pay: bool) -> Dictionary:
	var asked: Dictionary = BanditProtection.pending.get(str(lab.terrain.site.get("id", "")), {})
	if asked.is_empty(): return Runtime.fail("NO_TARGET", "目前沒有待答覆的保護費")
	if Settlement.head_executor(lab, true) != int(lab.controlled_person_id()): return Runtime.fail("NO_AUTHORITY", "只有聚落長能答覆保護費")
	var bands: Array = asked.keys()
	bands.sort()
	return BanditProtection.answer(lab, int(bands[0]), pay)

# --- The dialog ----------------------------------------------------------------------------------------------------

static func open(controller: Variant, host: Window = null) -> void:
	var lab: Variant = controller.lab
	var context := str(lab.controlled_person_id())
	if controller._existing_dialog("finance", context, host): return
	var choices := orgs(lab)
	if choices.is_empty():
		controller.show_result(Runtime.fail("NO_TARGET", "目前受控人物沒有主管的隊伍、聚落或國家財政"))
		return
	var dialog := Window.new()
	dialog.name = "FinanceDialog"
	dialog.title = "財政頁"
	dialog.size = Vector2i(720, 560)
	dialog.min_size = Vector2i(560, 440)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 14)
	dialog.add_child(margin)
	var column := VBoxContainer.new()
	margin.add_child(column)
	var labels: Array = []
	for org: Dictionary in choices: labels.append(org.label)
	var org_choice: OptionButton = controller._options(column, labels, "FinanceOrg")
	var text: Label = controller._label(column, "", 15)
	text.name = "FinanceSummary"
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var holder_choice: OptionButton = controller._options(column, [], "FinanceHolder")
	var bind_row := HBoxContainer.new()
	column.add_child(bind_row)
	var rate_row := HBoxContainer.new()
	column.add_child(rate_row)
	var pay_rates: Array = []
	for rate: int in PayTable.PAY_RATES: pay_rates.append("餉表 %d%%" % rate)
	var pay_rate: OptionButton = controller._options(rate_row, pay_rates, "FinancePayRate")
	var tax_rates: Array = []
	for rate: int in PayTable.TAX_RATES: tax_rates.append("稅率 %d%%" % rate)
	var tax_rate: OptionButton = controller._options(rate_row, tax_rates, "FinanceTaxRate")
	var reward_row := HBoxContainer.new()
	column.add_child(reward_row)
	var reward_item: OptionButton = controller._options(reward_row, ["幣", "穀物"], "FinanceRewardItem")
	var reward_count := SpinBox.new()
	reward_count.name = "FinanceRewardCount"
	reward_count.min_value = 1
	reward_count.max_value = 1000
	reward_count.value = 5
	reward_row.add_child(reward_count)
	var fief_choice: OptionButton = controller._options(column, [], "FinanceFief")
	var status: Label = controller._label(column, "", 15)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var options := {"holders": [], "fiefs": []}
	var current := func() -> Dictionary: return choices[clampi(org_choice.selected, 0, choices.size() - 1)]
	var refresh := func() -> void:
		var org: Dictionary = current.call()
		text.text = summary(lab, org)
		holder_choice.clear()
		options.holders = holders(lab, org.ref)
		for entry: Dictionary in options.holders: holder_choice.add_item(entry.label)
		var record := Finance.record_of(lab.terrain, org.ref, _today(lab))
		pay_rate.select(maxi(0, PayTable.PAY_RATES.find(int(record.pay_rate))))
		tax_rate.select(maxi(0, PayTable.TAX_RATES.find(int(record.tax_rate))))
		var kind := str(org.ref.kind)
		pay_rate.visible = kind == "team"
		reward_row.visible = kind == "team"
		tax_rate.visible = kind == "settlement"
		holder_choice.visible = kind != "nation"
		fief_choice.clear()
		options.fiefs = vassal_fiefs(lab) if kind == "nation" else []
		for entry: Dictionary in options.fiefs: fief_choice.add_item(entry.label)
		fief_choice.visible = not options.fiefs.is_empty()
		for node: Node in bind_row.get_children(): node.visible = node.has_meta("kinds") and kind in node.get_meta("kinds")
	var act := func(result: Dictionary) -> void:
		status.text = str(result.get("message", ""))
		controller.show_result(result)
		refresh.call()
	var picked := func() -> Dictionary: return options.holders[holder_choice.selected].source if holder_choice.selected >= 0 and holder_choice.selected < options.holders.size() else {}
	var buttons := [
		["綁定為餉源", "FinanceBindPay", ["team"], func() -> void: act.call(bind(lab, current.call(), "pay_source", picked.call()))],
		["定餉表倍率", "FinanceSetPayRate", ["team"], func() -> void: act.call(Payroll.set_pay_rate(lab, int(lab.controlled_person_id()), current.call().ref, int(PayTable.PAY_RATES[pay_rate.selected])))],
		["犒賞全隊", "FinanceReward", ["team"], func() -> void: act.call(Reward.reward(lab, int(lab.controlled_person_id()), current.call().ref, ["coin", "grain"][reward_item.selected], int(reward_count.value)))],
		["綁定為稅源", "FinanceBindTax", ["settlement"], func() -> void: act.call(bind(lab, current.call(), "tax_source", picked.call()))],
		["定稅率", "FinanceSetTax", ["settlement"], func() -> void: act.call(ProduceTax.set_tax(lab, int(lab.controlled_person_id()), int(PayTable.TAX_RATES[tax_rate.selected])))],
		["綁定為封地庫", "FinanceBindTreasury", ["settlement"], func() -> void: act.call(bind(lab, current.call(), "treasury", picked.call()))],
		["付保護費", "FinancePayProtection", ["settlement"], func() -> void: act.call(_answer_protection(lab, true))],
		["拒絕保護費", "FinanceRefuseProtection", ["settlement"], func() -> void: act.call(_answer_protection(lab, false))],
		["切換自動撥餉", "FinanceAutoFund", ["nation"], func() -> void:
			var record := Finance.record_of(lab.terrain, current.call().ref, _today(lab))
			act.call(set_auto_fund(lab, current.call(), not bool(record.auto_fund)))],
		["豁免所選封地下一季上繳", "FinanceExempt", ["nation"], func() -> void:
			if fief_choice.selected < 0 or fief_choice.selected >= options.fiefs.size():
				act.call(Runtime.fail("NO_TARGET", "沒有可豁免的封地"))
				return
			var next := Calendar.next_start(_today(lab) + 1, true)
			act.call(Tribute.exempt(lab, int(lab.controlled_person_id()), str(options.fiefs[fief_choice.selected].site_id), PayTable.season_index(next)))],
	]
	for spec: Array in buttons:
		var button: Button = controller._button(bind_row, str(spec[0]), str(spec[1]), spec[3])
		button.set_meta("kinds", spec[2])
	org_choice.item_selected.connect(func(_index: int) -> void: refresh.call())
	dialog.close_requested.connect(dialog.queue_free)
	refresh.call()
	controller._show_dialog(dialog, "finance", context, host)
