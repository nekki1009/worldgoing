extends SceneTree
## 軍餉與稅收 P0 (reports/pay-and-tax-plan.md §2, §3.2, §8, PT-14): the versioned pay table, the organization finance
## section and the person's arrears are data only. Checks:
## - the pay table: one wage per payer (儒將 draws 40), the multiplier, paydays on the 1st of each month and tax days
##   on the first day of each season with their indexes;
## - PT-14: an old save (no finance section, no arrears) loads and validates; the default record is untaxed, unbound,
##   1.0× pay, with a 30-day grace; nobody owes anything;
## - season receipts roll (this season and the last only);
## - a stored record and a person's arrears validate, survive a save/load round trip with integer types, and every
##   corrupt shape is refused (bad rate, key mismatch, a holder bound by two organizations, a missing holder on this
##   Site, unsorted exemptions, extra field, zero arrears entry, a seventeenth paying organization).
## Output: SITE_PAY_FINANCE_P0_PASS on success; quit(1) on failure.
const PayTable = preload("res://scripts/terrain_lab/site_pay_table.gd")
const Finance = preload("res://scripts/terrain_lab/site_finance.gd")
const PersonSocial = preload("res://scripts/terrain_lab/person_social.gd")
const Calendar = preload("res://scripts/terrain_lab/site_calendar.gd")
const SOURCE := "res://output/time_climate_tc0/source_small.json"
const OUT := "res://.godot-temp/site_pay_finance_p0/roundtrip.json"
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _ok(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_PAY_FINANCE_P0 OK ", checks, ": ", message)
		return true
	printerr("SITE_PAY_FINANCE_P0_FAIL: ", message, " ", str(detail))
	quit(1)
	return false

func _load() -> TerrainData:
	var loaded: Dictionary = SiteStore.load_site(SOURCE, Callable(), 1, true)
	return loaded.data if loaded.ok else null

func _valid(data: TerrainData) -> Dictionary:
	return SiteStore._validate_state(data, data.site)

func _run() -> void:
	# Pay table.
	if not _ok(PayTable.wage_points(["soldier"]) == 10 and PayTable.wage_points(["officer", "official"]) == 40 and PayTable.wage_points(["clerk"]) == 20 and PayTable.wage_points([]) == 0, "one wage per payer, the highest role"): return
	if not _ok(PayTable.wage_tenths(["soldier"], 50) == 50 and PayTable.wage_tenths(["officer"], 150) == 450 and PayTable.wage_tenths(["garrison"], 100) == 80, "the multiplier applies in tenths"): return
	var may_1 := Calendar.day_of(1, 5, 1)
	var jun_1 := Calendar.day_of(1, 6, 1)
	if not _ok(PayTable.is_payday(may_1) and not PayTable.is_tax_day(may_1) and PayTable.is_payday(jun_1) and PayTable.is_tax_day(jun_1) and not PayTable.is_payday(may_1 + 1), "pay on the 1st of the month, tax on the first day of a season"): return
	var seasons := [PayTable.season_index(0), PayTable.season_index(Calendar.day_of(1, 3, 1)), PayTable.season_index(Calendar.day_of(1, 12, 1)), PayTable.season_index(Calendar.day_of(2, 2, 28)), PayTable.season_index(Calendar.day_of(2, 3, 1))]
	if not _ok(PayTable.payday_index(0) == 0 and PayTable.payday_index(Calendar.day_of(2, 1, 1)) == 12 and seasons == [0, 1, 4, 4, 5], "payday and season indexes", seasons): return
	# PT-14: an old save.
	if not _ok(FileAccess.file_exists(SOURCE), "the fixture exists"): return
	var data := _load()
	if not _ok(data != null and not data.site.has("finance"), "an old save loads without a finance section"): return
	var site_id := str(data.site.id)
	if not _ok(_valid(data).ok, "the old save validates", _valid(data)): return
	var day := Calendar.day_index(float(data.site.minute))
	var team_ref := {"kind": "team", "site_id": site_id, "org_id": "1"}
	var default_record := Finance.record_of(data, team_ref, day)
	if not _ok(default_record.pay_rate == 100 and default_record.tax_rate == 0 and default_record.pay_source.is_empty() and not default_record.auto_fund and Finance.grace_left(default_record, day) == 30 and not data.site.has("finance"), "the default record: untaxed, unbound, 1.0×, 30-day grace, not stored", default_record): return
	var player: Dictionary = data.site.actors.player
	if not _ok(PersonSocial.arrears(player).is_empty() and PersonSocial.arrears_for(player, Finance.org_key(team_ref)) == {"periods": 0, "tenths": 0}, "an old person owes nothing"): return
	# A stored record and arrears.
	var made: Dictionary = Finance.ensure(data, team_ref, day)
	var nation_ref := {"kind": "nation", "site_id": site_id, "org_id": "n1"}
	Finance.ensure(data, nation_ref, day)
	if not _ok(made.ok and data.site.finance.size() == 2 and data.site.finance[Finance.org_key(nation_ref)].auto_fund, "records are created on first use; a nation funds its teams by default"): return
	var team_record: Dictionary = data.site.finance[Finance.org_key(team_ref)]
	team_record.pay_rate = 150
	team_record.tax_rate = 10
	team_record.pay_source = {"kind": "stock", "site_id": "other-site", "feature_id": "warehouse_1"}
	team_record.treasury = team_record.pay_source.duplicate()
	team_record.tax_lord = {"kind": "nation", "id": "n1"}
	team_record.exemptions = [3, 5]
	team_record.last_payday = 4
	team_record.served = {"5": 12, "7": 30}
	team_record.accrued_day = day
	team_record.tax_carry = {"farm_1": {"grain": 40}}
	Finance.add_receipt(team_record, "produce_tax", 50, 3)
	Finance.add_receipt(team_record, "produce_tax", 20, 4)
	if not _ok(Finance.receipts_of(team_record, "produce_tax", 4) == 20 and Finance.receipts_of(team_record, "produce_tax", 4, true) == 50 and Finance.receipts_of(team_record, "produce_tax", 6, true) == 0, "season receipts roll: this season and the last", team_record.receipts): return
	var key := Finance.org_key(team_ref)
	if not _ok(PersonSocial.set_arrears(player, key, 2, 33) and PersonSocial.arrears_for(player, key) == {"periods": 2, "tenths": 33}, "arrears are written"): return
	if not _ok(_valid(data).ok, "a stored record and arrears validate", _valid(data)): return
	# Corrupt shapes, each restored after the check.
	var corrupt := {
		"pay rate 90": func() -> void: data.site.finance[key].pay_rate = 90,
		"tax rate 7": func() -> void: data.site.finance[key].tax_rate = 7,
		"extra field": func() -> void: data.site.finance[key]["balance"] = 5,
		"unsorted exemptions": func() -> void: data.site.finance[key].exemptions = [5, 3],
		"bad lord": func() -> void: data.site.finance[key].tax_lord = {"kind": "family", "id": "f"},
		"camp as a source": func() -> void: data.site.finance[key].tax_source = {"kind": "camp", "site_id": site_id, "feature_id": "x"},
		"missing holder on this Site": func() -> void: data.site.finance[key].tax_source = {"kind": "stock", "site_id": site_id, "feature_id": "nowhere"},
		"missing vehicle on this Site": func() -> void: data.site.finance[key].tax_source = {"kind": "vehicle", "site_id": site_id, "vehicle_id": "nowhere"},
		"a holder bound by two organizations": func() -> void: data.site.finance[Finance.org_key(nation_ref)].treasury = data.site.finance[key].pay_source.duplicate(),
		"carry of a whole unit": func() -> void: data.site.finance[key].tax_carry = {"farm_1": {"grain": 100}},
		"receipt of an unknown kind": func() -> void: data.site.finance[key].receipts.current["gift"] = 5,
		"served zero days": func() -> void: data.site.finance[key].served = {"5": 0},
		"served bad person": func() -> void: data.site.finance[key].served = {"x": 3},
		"key mismatch": func() -> void: data.site.finance["team:%s:9" % site_id] = data.site.finance[key].duplicate(true),
	}
	for name: String in corrupt:
		var saved: Dictionary = data.site.finance.duplicate(true)
		(corrupt[name] as Callable).call()
		var result := _valid(data)
		data.site["finance"] = saved
		if not _ok(not result.ok and str(result.get("code", "")) == "CORRUPT_SAVE", "refused: " + name, result): return
	if not _ok(_valid(data).ok, "restored after the corrupt cases"): return
	# Arrears shapes.
	var body := {}
	if not _ok(PersonSocial.set_arrears(body, key, 0, 0) and not body.has("social_state"), "nothing owed writes no packet"): return
	for index: int in range(16): PersonSocial.set_arrears(body, "team:%s:%d" % [site_id, index + 10], 1, 0)
	if not _ok(PersonSocial.arrears(body).size() == 16 and not PersonSocial.set_arrears(body, "team:%s:99" % site_id, 1, 0), "a seventeenth paying organization is refused"): return
	if not _ok(not PersonSocial.set_arrears(body, "family:%s:1" % site_id, 1, 0) and not PersonSocial.set_arrears(body, "bad", 1, 0) and not PersonSocial.set_arrears(body, key, -1, 0), "a family, a bad key and a negative value are refused"): return
	PersonSocial.set_arrears(body, "team:%s:10" % site_id, 0, 0)
	if not _ok(PersonSocial.arrears(body).size() == 15 and PersonSocial.valid(body.social_state), "settling removes the entry (sparse)"): return
	var zero_packet: Dictionary = body.social_state.duplicate(true)
	zero_packet.arrears["team:%s:11" % site_id] = {"periods": 0, "tenths": 0}
	if not _ok(not PersonSocial.valid(zero_packet), "a stored zero entry is refused"): return
	var upgraded := PersonSocial.upgraded(body.social_state)
	if not _ok(PersonSocial.valid(upgraded) and upgraded.arrears.size() == 15, "the v3 upgrade keeps the arrears"): return
	# Save / load round trip.
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT.get_base_dir()))
	var saved_result: Dictionary = SiteStore.save(data, OUT)
	if not _ok(saved_result.ok, "the Site saves", saved_result): return
	var loaded: Dictionary = SiteStore.load_site(OUT, Callable(), 1, true)
	if not _ok(loaded.ok, "the Site loads", loaded): return
	var back: TerrainData = loaded.data
	var record: Dictionary = back.site.finance[key]
	if not _ok(record.pay_rate is int and record.pay_rate == 150 and record.tax_rate == 10 and record.last_payday is int and record.exemptions == [3, 5] and record.exemptions[0] is int and record.tax_lord == {"kind": "nation", "id": "n1"} and record.since_day is int and record.served == {"5": 12, "7": 30} and record.served["5"] is int and record.accrued_day == day and record.tax_carry == {"farm_1": {"grain": 40}} and record.tax_carry.farm_1.grain is int and record.receipts.current.produce_tax is int and record.receipts.season == 4, "the record survives with integer types", record): return
	var owed := PersonSocial.arrears_for(back.site.actors.player, key)
	if not _ok(owed == {"periods": 2, "tenths": 33}, "the arrears survive", owed): return
	print("SITE_PAY_FINANCE_P0_PASS checks=", checks)
	for _frame: int in range(3): await process_frame
	quit(0)
