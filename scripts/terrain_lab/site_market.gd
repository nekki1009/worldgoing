extends RefCounted
## 貿易 T3 slice 1 (reports/trade-plan.md §5.2, Q4 C; TR-35, TR-36, TR-37): the market building, a settlement's standing
## trade place. Fixed 4x4 with one entrance; wood 20, stone 10, rope 4 and 30 minutes of work, paid and refunded through
## the original pending_build. It is an ordinary civil building (Runtime.CIVIL_KINDS: body HP, repair, grade 1-3 under
## the settlement's grade cap) with a tiled roof (Runtime.FIRE_ROOF_KINDS: once the roof burns through, its stock burns
## like a warehouse's), and its attached stock holds 20x(grade+1) (SiteStockpiles) but never feeds processing. The
## settlement head may bind it as a trade source like a warehouse (SiteSettlement.TRADE_SOURCE_KINDS).
## Slice 2 (§5.2 掛牌; TR-30, TR-31): listings; slice 3 (TR-32, TR-33): the 市正's listings by the duty AI. Both below.
## Observations of listings seen elsewhere (TR-34) are a later slice.
## Placement: an established settlement of level 2 or more, a cell in its jurisdiction, no other market on the Site (one
## settlement per Site, one market per settlement in this version), and the formal building_v2 art for its facing.
## Missing art refuses (MISSING_ART); nothing is placeheld.
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const KIND := "market"
const MIN_SETTLEMENT_LEVEL := 2
const FACING_SUFFIX := ["", "_west", "_north", "_east"]

## Whether the formal art for the market facing `quarter` is published. `assets` replaces the manifest's asset table
## (tests only); null reads the real manifest.
static func art_available(quarter: int, assets: Variant = null) -> bool:
	if quarter < 0 or quarter > 3: return false
	if assets == null: return Runtime.formal_building_art_available(KIND, quarter)
	return assets is Dictionary and assets.has(KIND + FACING_SUFFIX[quarter])

## The build guard (TR-35, TR-36), read only. `assets` as in art_available.
static func build_guard(data: TerrainData, cells: Array[int], quarter: int, assets: Variant = null) -> Dictionary:
	var settlement: Variant = data.site.get("settlement", {})
	if not settlement is Dictionary or settlement.is_empty() or int(settlement.get("level", 0)) < MIN_SETTLEMENT_LEVEL:
		return Runtime.fail("REQUIREMENTS", "市集須已建制聚落 %d 級" % MIN_SETTLEMENT_LEVEL)
	if not SiteSettlement.feature_in_jurisdiction(data, {"cells": cells}): return Runtime.fail("REQUIREMENTS", "市集須建在聚落轄區內")
	if not market_key(data.site).is_empty(): return Runtime.fail("LIMIT", "每座聚落只能有一座市集")
	if not art_available(quarter, assets): return Runtime.fail("MISSING_ART", "市集缺正式美術資產；不以占位圖替代")
	return Runtime.ok()

## The market's feature key on this Site, any stage ("" when none).
static func market_key(state: Dictionary) -> String:
	var keys: Array = state.get("features", {}).keys()
	keys.sort()
	for key: Variant in keys:
		var feature: Variant = state.features[key]
		if feature is Dictionary and str(feature.get("kind", "")) == KIND: return str(key)
	return ""

## Whether the market `key` can trade now (§5.2 暫停條件, building half): complete, not being built, upgraded or repaired,
## and its body standing (HP above 0). {open, reason}; reason one of "", NO_MARKET, BUILDING, DAMAGED. The representative
## half (present, able, free) belongs to the listing slice.
static func open_state(data: TerrainData, key: String) -> Dictionary:
	var feature: Variant = data.site.get("features", {}).get(key, {})
	if not feature is Dictionary or str(feature.get("kind", "")) != KIND: return {"open": false, "reason": "NO_MARKET"}
	if str(feature.get("stage", "")) != "complete" or feature.has("pending_build") or feature.has("repair"): return {"open": false, "reason": "BUILDING"}
	if not Runtime.feature_usable(feature): return {"open": false, "reason": "DAMAGED"}
	return {"open": true, "reason": ""}

## Strict save validation: at most one market on a Site (§5.2, SiteStore). Read only.
static func validate(state: Dictionary) -> Dictionary:
	var features: Variant = state.get("features", {})
	if not features is Dictionary: return Runtime.ok() # the feature validator owns the shape
	var count := 0
	for feature: Variant in features.values():
		if feature is Dictionary and str(feature.get("kind", "")) == KIND: count += 1
	if count > 1: return Runtime.fail("CORRUPT_SAVE", "每座聚落只能有一座市集")
	return Runtime.ok()

# --- Slice 2: listings (§5.2 掛牌; TR-30, TR-31) ------------------------------------------------------------------------
## A listing is a pre-approved offer: the settlement pays `give` out of the market's own stock for `want`, at most `daily`
## lots a game day; an outsider takes lots from the 市正 standing at the market with no valuation or bargaining, and the
## delivery and single commit are those of any trade (SiteTradeSession.take_listing). The settlement record holds them
## (optional `market_listings`): {revision, day, rows [{id, give {resource: n}, want {resource: n}, daily, used}],
## jobs {offer_id: {row, lots}}}. `used` counts the day's committed lots (it restarts when the game day changes); `jobs`
## the lots of deliveries under way, counted at their commit and dropped when they end otherwise (nothing is made up
## later). The market's grade sets its daily lots across all rows (10 a grade); each lot still passes the trade source's
## limits (TR-21).
const MAX_ROWS := 4
const LOTS_PER_GRADE := 10
const MAX_UNITS := 100
const MAX_KINDS := 2
const LISTING_FIELDS := ["revision", "day", "rows", "jobs"]
const ROW_FIELDS := ["id", "give", "want", "daily", "used"]
const CLOSED_TEXT := {"NO_MARKET": "此地沒有市集", "BUILDING": "市集施工中，暫停交易", "DAMAGED": "市集受損，暫停交易"}
const FORMAT_TEXT := "掛牌格式：付出物資:數量+…>收取物資:數量+…|每日份數，多份以分號分隔（例：grain:2>salt:1|5）"

## The market's daily lots across all its listings.
static func daily_cap(feature: Dictionary) -> int:
	return LOTS_PER_GRADE * clampi(Runtime.building_grade(feature), 1, Runtime.CIVIL_MAX_GRADE)

static func game_day(site: Dictionary) -> int:
	return floori((float(site.get("minute", 0)) + float(site.get("phase", 0.0))) / 1440.0)

## The settlement's listings record ({} when none).
static func listings(data: TerrainData) -> Dictionary:
	var settlement: Variant = data.site.get("settlement", {})
	if not settlement is Dictionary: return {}
	var value: Variant = settlement.get("market_listings", {})
	return value if value is Dictionary else {}

static func _int(value: Variant, lower: int, upper: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value)) \
		and float(value) >= lower and float(value) <= upper

static func valid_stack(stack: Variant) -> bool:
	if not stack is Dictionary or stack.is_empty() or stack.size() > MAX_KINDS: return false
	for resource: Variant in stack:
		# 貿易 T6 S8 (TR-63): coin may be listed; it moves as an untaxed payment leg (a listing needs no valuation).
		if not resource is String or not Runtime.Env.ITEM_NAMES.has(resource) or not _int(stack[resource], 1, MAX_UNITS): return false
	return true

static func _clean(stack: Dictionary) -> Dictionary:
	var clean := {}
	for resource: Variant in stack: clean[str(resource)] = int(stack[resource])
	return clean

static func _times(stack: Dictionary, lots: int) -> Dictionary:
	var resources := {}
	for resource: Variant in stack: resources[str(resource)] = int(stack[resource]) * lots
	return {"resources": resources, "item_ids": []}

## Why a row as set ({give, want, daily}) is refused ("" when it is legal).
static func _row_refusal(row: Variant, cap: int) -> String:
	if not row is Dictionary: return "掛牌格式"
	if not valid_stack(row.get("give")) or not valid_stack(row.get("want")): return "每份兩邊各 1–%d 種已知物資、各 1–%d 個" % [MAX_KINDS, MAX_UNITS]
	for resource: Variant in row.give:
		if row.want.has(resource): return "同一物資不能同時付出與收取"
	if not _int(row.get("daily"), 1, cap): return "每日份數須 1–%d" % cap
	return ""

static func _row(record: Dictionary, row_id: String) -> Dictionary:
	for row: Variant in record.get("rows", []):
		if row is Dictionary and str(row.get("id", "")) == row_id: return row
	return {}

static func _pending(record: Dictionary, row_id: String) -> int:
	var lots := 0
	for job: Variant in record.get("jobs", {}).values():
		if job is Dictionary and str(job.get("row", "")) == row_id: lots += int(job.get("lots", 0))
	return lots

static func _roll(record: Dictionary, today: int) -> void:
	if int(record.get("day", -1)) == today: return
	record["day"] = today
	for row: Variant in record.get("rows", []):
		if row is Dictionary: row["used"] = 0

static func _able(lab: Variant, identity: int) -> bool:
	var person: Dictionary = lab.site_controller.person_actions._person(identity)
	return not person.is_empty() and float(person.get("hp", 0.0)) > 0.0 and float(person.get("ko", 0.0)) <= 0.0 \
		and not bool(person.get("captive", false)) and not bool(person.get("surrender_pending", false))

## Who trades for the settlement now: SiteOffices' `settlement.trade` (the head acts while the seat is vacant), able;
## -1 when nobody can (as SiteTradeSession.settlement_party resolves it).
static func decider(lab: Variant) -> int:
	var settlement: Variant = lab.terrain.site.get("settlement", {})
	if not settlement is Dictionary or not settlement.get("offices") is Dictionary: return -1
	var offices: Dictionary = settlement.offices
	SiteOffices.ensure_catalog(offices, "settlement")
	var head := int(SiteOffices.head_position(offices).get("holder", 0))
	var resolved: Dictionary = SiteOffices.resolve(offices, "settlement.trade", head, func(identity: int) -> bool: return _able(lab, identity), true)
	return int(resolved.get("decider", -1)) if bool(resolved.get("ok", false)) else -1

## The 市正 (the head while the seat is vacant) sets the market's listings `rows` ([{give, want, daily}], at most 4; an
## empty list takes them all down). The market must stand complete and be bound as a trade source (every lot pays out of
## its own stock within the binding's limits). A row kept unchanged keeps the day's count, so re-listing never resets
## the daily lots; nothing changes while a listed delivery is under way. `by_duty`: the duty AI acting for the decider.
static func set_listings(lab: Variant, requester: int, rows: Array, by_duty: bool = false) -> Dictionary:
	var data: TerrainData = lab.terrain
	var settlement: Variant = data.site.get("settlement", {})
	if not settlement is Dictionary or settlement.is_empty() or int(settlement.get("level", 0)) <= 0: return Runtime.fail("NO_TARGET", "此地沒有聚落")
	var key := market_key(data.site)
	var feature: Dictionary = data.site.features.get(key, {}) if not key.is_empty() else {}
	if feature.is_empty() or str(feature.get("stage", "")) != "complete": return Runtime.fail("NO_TARGET", "市集尚未完工")
	if not by_duty and requester != int(lab.controlled_person_id()): return Runtime.fail("NO_AUTHORITY", "只有受控本人能在此設定掛牌")
	if decider(lab) != requester: return Runtime.fail("NO_AUTHORITY", "只有市正（缺任時由首長代行）能設定掛牌")
	if not settlement.get("trade_sources", {}).has(key): return Runtime.fail("NOT_BOUND", "市集庫存須先由首長綁為交易來源")
	var old := listings(data)
	if not old.get("jobs", {}).is_empty(): return Runtime.fail("BUSY", "按掛牌的交付進行中")
	if rows.size() > MAX_ROWS: return Runtime.fail("INVALID", "至多 %d 份掛牌" % MAX_ROWS)
	var cap := daily_cap(feature)
	var today := game_day(data.site)
	var total := 0
	var made: Array = []
	for index: int in rows.size():
		var refusal := _row_refusal(rows[index], cap)
		if not refusal.is_empty(): return Runtime.fail("INVALID", "第 %d 份：%s" % [index + 1, refusal])
		total += int(rows[index].daily)
		var row := {"id": str(index + 1), "give": _clean(rows[index].give), "want": _clean(rows[index].want), "daily": int(rows[index].daily), "used": 0}
		for previous: Variant in old.get("rows", []):
			if int(old.get("day", -1)) == today and previous is Dictionary and previous.give == row.give and previous.want == row.want:
				row["used"] = mini(int(previous.used), int(row.daily))
		made.append(row)
	if total > cap: return Runtime.fail("INVALID", "每日份數合計不能超過 %d（市集 %d 級）" % [cap, Runtime.building_grade(feature)])
	if made.is_empty():
		settlement.erase("market_listings")
		return Runtime.ok("已撤下全部掛牌")
	settlement["market_listings"] = {"revision": int(old.get("revision", 0)) + 1, "day": today, "rows": made, "jobs": {}}
	return Runtime.ok("已設定 %d 份掛牌" % made.size(), {"revision": int(settlement.market_listings.revision)})

## The market half of taking `lots` lots of listing `row_id` (TR-30, TR-31): the market open, the row listed and the lots
## within the day's lots (committed and under way). {ok, key, give, want} with the goods of the whole take.
static func take_guard(data: TerrainData, row_id: String, lots: int) -> Dictionary:
	var key := market_key(data.site)
	var open := open_state(data, key)
	if not bool(open.open): return Runtime.fail("MARKET_CLOSED", str(CLOSED_TEXT.get(str(open.reason), "市集暫停")))
	var record := listings(data)
	if record.is_empty(): return Runtime.fail("NO_TARGET", "市集沒有掛牌")
	_roll(record, game_day(data.site))
	var row := _row(record, row_id)
	if row.is_empty(): return Runtime.fail("NO_TARGET", "沒有這份掛牌")
	if lots < 1 or lots > MAX_UNITS: return Runtime.fail("INVALID", "份數須 1–%d" % MAX_UNITS)
	var left := int(row.daily) - int(row.used) - _pending(record, row_id)
	if lots > left: return Runtime.fail("DAILY_LIMIT", "今日此掛牌只剩 %d 份" % maxi(0, left))
	return Runtime.ok("", {"key": key, "give": _times(row.give, lots), "want": _times(row.want, lots)})

## A listed delivery under way (its lots are counted at the commit).
static func reserve(data: TerrainData, offer_id: String, row_id: String, lots: int) -> void:
	var record := listings(data)
	if not record.is_empty(): record.jobs[offer_id] = {"row": row_id, "lots": lots}

## A listed delivery committed: its lots count for the day. Whether `offer_id` was a listed one.
static func commit(data: TerrainData, offer_id: String) -> bool:
	var record := listings(data)
	if record.is_empty() or not record.jobs.has(offer_id): return false
	var job: Dictionary = record.jobs[offer_id]
	record.jobs.erase(offer_id)
	_roll(record, game_day(data.site))
	var row := _row(record, str(job.row))
	if not row.is_empty(): row["used"] = mini(int(row.daily), int(row.used) + int(job.lots))
	return true

## A listed delivery that ended without its commit: its lots are free again.
static func release(data: TerrainData, offer_id: String) -> void:
	var record := listings(data)
	if not record.is_empty(): record.jobs.erase(offer_id)

## Strict save validation of `settlement.market_listings` (Settlement.validate): the market exists, every row legal,
## ids unique, the day's lots within each row and the market's cap, every delivery under way an open trade offer.
static func valid_listings(raw: Variant, state: Dictionary) -> bool:
	if not raw is Dictionary or not Runtime.Technology.keys(raw, LISTING_FIELDS): return false
	var key := market_key(state)
	if key.is_empty(): return false
	var cap := daily_cap(state.features[key])
	if not _int(raw.revision, 1, 2147483646) or not _int(raw.day, 0, 2147483646) or not raw.rows is Array or raw.rows.is_empty() \
		or raw.rows.size() > MAX_ROWS or not raw.jobs is Dictionary: return false
	var rows := {}
	var total := 0
	for row: Variant in raw.rows:
		if not row is Dictionary or not Runtime.Technology.keys(row, ROW_FIELDS) or not row.id is String or str(row.id).is_empty() \
			or str(row.id).length() > 16 or rows.has(row.id): return false
		if not _row_refusal(row, cap).is_empty() or not _int(row.used, 0, int(row.daily)): return false
		rows[row.id] = row
		total += int(row.daily)
	if total > cap: return false
	var trade: Variant = state.get("trade", {})
	var offers: Variant = trade.get("offers", {}) if trade is Dictionary else {}
	var pending := {}
	for offer_id: Variant in raw.jobs:
		var job: Variant = raw.jobs[offer_id]
		if not offer_id is String or not offers is Dictionary or not offers.has(offer_id): return false
		if not job is Dictionary or not Runtime.Technology.keys(job, ["row", "lots"]) or not job.row is String or not rows.has(job.row) \
			or not _int(job.lots, 1, int(rows[job.row].daily)): return false
		pending[job.row] = int(pending.get(job.row, 0)) + int(job.lots)
	for id: Variant in pending:
		if int(rows[id].used) + int(pending[id]) > int(rows[id].daily): return false
	return true

## JSON loads numbers as floats; Settlement.normalize calls this.
static func normalize_listings(raw: Dictionary) -> void:
	for field: String in ["revision", "day"]:
		if raw.get(field) is float: raw[field] = int(raw[field])
	for row: Variant in raw.get("rows", []):
		if not row is Dictionary: continue
		for field: String in ["daily", "used"]:
			if row.get(field) is float: row[field] = int(row[field])
		for side: String in ["give", "want"]:
			if row.get(side) is Dictionary:
				for resource: Variant in row[side].keys(): row[side][resource] = int(row[side][resource])
	if raw.get("jobs") is Dictionary:
		for job: Variant in raw.jobs.values():
			if job is Dictionary and job.get("lots") is float: job["lots"] = int(job.lots)

## Listing rows written "grain:2>salt:1|5; wood:3+rope:1>cloth:2|10" (give > want | daily lots); the values are checked
## by set_listings.
static func parse_rows(text: String) -> Dictionary:
	var rows: Array = []
	for part: String in text.split(";", false):
		var line := part.strip_edges()
		if line.is_empty(): continue
		var halves := line.split("|")
		var sides := halves[0].split(">") if halves.size() == 2 else PackedStringArray()
		if sides.size() != 2 or not halves[1].strip_edges().is_valid_int(): return Runtime.fail("INVALID", FORMAT_TEXT)
		var give := _parse_stack(sides[0])
		var want := _parse_stack(sides[1])
		if give.is_empty() or want.is_empty(): return Runtime.fail("INVALID", FORMAT_TEXT)
		rows.append({"give": give, "want": want, "daily": int(halves[1].strip_edges())})
	return Runtime.ok("", {"rows": rows})

static func _parse_stack(text: String) -> Dictionary:
	var stack := {}
	for piece: String in text.split("+", false):
		var pair := piece.strip_edges().split(":")
		if pair.size() != 2 or not pair[1].strip_edges().is_valid_int() or pair[0].strip_edges().is_empty(): return {}
		stack[pair[0].strip_edges()] = int(pair[1].strip_edges())
	return stack

## The listings as editable text (parse_rows' format).
static func rows_text(record: Dictionary) -> String:
	var lines: Array = []
	for row: Variant in record.get("rows", []):
		if row is Dictionary: lines.append("%s>%s|%d" % [_stack_code(row.give), _stack_code(row.want), int(row.daily)])
	return "; ".join(lines)

static func _stack_code(stack: Dictionary) -> String:
	var keys: Array = stack.keys()
	keys.sort()
	var parts: Array = []
	for resource: Variant in keys: parts.append("%s:%d" % [str(resource), int(stack[resource])])
	return "+".join(parts)

## A stack for people to read: "糧食 2、錢幣 1".
static func stack_text(stack: Dictionary) -> String:
	var keys: Array = stack.keys()
	keys.sort()
	var parts: Array = []
	for resource: Variant in keys: parts.append("%s %d" % [str(Runtime.Env.ITEM_NAMES.get(resource, resource)), int(stack[resource])])
	return "、".join(parts)

# --- Slice 3: the 市正's listings by the duty AI (TR-32, TR-33) ---------------------------------------------------------
## Food the settlement holds for its listing decision: the depot and every stock bound to its trade.
const FOODS := ["grain", "wild_food", "fish", "meat"]
const FOOD_DAYS := 14 # residents x 14 days, the settlement's trade food target (SiteTradeSession.SETTLEMENT_FOOD_DAYS)
## Goods the settlement barters grain against (coin is not a trade good): it buys grain with the first it holds in the
## market and may pay out, and sells grain for the first, at the trade value table's ratio (SiteTradeValues).
const STAPLES := ["salt", "cloth", "pottery", "tools"]
const Values = preload("res://scripts/terrain_lab/site_trade_values.gd")
## The last decision of day() (tests and diagnostics only; never saved).
static var last_evaluation := {}

static func settlement_food(data: TerrainData) -> int:
	var total := 0
	for resource: String in FOODS: total += int(data.site.get("inventory", {}).get(resource, 0))
	var settlement: Variant = data.site.get("settlement", {})
	var sources: Variant = settlement.get("trade_sources", {}) if settlement is Dictionary else {}
	if sources is Dictionary:
		for key: Variant in sources:
			var stock: Dictionary = data.site.get("stockpiles", {}).get(str(key), {})
			for resource: String in FOODS: total += int(stock.get("cargo", {}).get(resource, 0))
	return total

static func _same_rows(current: Array, wanted: Array) -> bool:
	if current.size() != wanted.size(): return false
	for index: int in current.size():
		var row: Variant = current[index]
		if not row is Dictionary or row.give != wanted[index].give or row.want != wanted[index].want or int(row.daily) != int(wanted[index].daily): return false
	return true

## On the duty review (live Site, at peace): with the settlement's duty AI on and an NPC trading for it (never the
## controlled person, who decides himself), the market lists by the settlement's food against its target (residents x
## 14 days): below it, buy grain with one unit of the first STAPLE the market holds and may pay out; above twice it,
## sell grain for one unit of the first STAPLE; otherwise nothing (the ratio by the trade value table). A side the
## market's binding has no limit for is not listed, and nothing else (building materials included) is ever listed by the
## AI. Unchanged listings stand untouched, so the day's lots go on; a delivery under way defers any change. With the duty
## AI off nothing changes, and the market still answers trades on its standing listings (TR-33).
static func day(lab: Variant) -> Dictionary:
	var data: TerrainData = lab.terrain
	var settlement: Variant = data.site.get("settlement", {})
	if not settlement is Dictionary or settlement.is_empty() or int(settlement.get("level", 0)) <= 0 or not settlement.get("offices") is Dictionary:
		return _evaluated({"reason": "no_settlement"})
	if not bool(settlement.offices.get("duty_ai", false)): return _evaluated({"reason": "duty_ai_off"})
	var key := market_key(data.site)
	var feature: Dictionary = data.site.features.get(key, {}) if not key.is_empty() else {}
	if feature.is_empty() or str(feature.get("stage", "")) != "complete": return _evaluated({"reason": "no_market"})
	var source: Dictionary = settlement.get("trade_sources", {}).get(key, {})
	if source.is_empty(): return _evaluated({"reason": "not_bound"})
	var trader := decider(lab)
	if trader <= 0 or trader == int(lab.controlled_person_id()): return _evaluated({"reason": "no_npc_trader", "trader": trader})
	var food := settlement_food(data)
	var target: int = SiteSettlement.residents(lab).size() * FOOD_DAYS
	var cap := daily_cap(feature)
	var rows: Array = []
	var stock: Dictionary = data.site.get("stockpiles", {}).get(key, {}).get("cargo", {})
	if food < target:
		for staple: String in STAPLES:
			if source.limits.has(staple) and int(stock.get(staple, 0)) > 0:
				rows = [{"give": {staple: 1}, "want": {"grain": grain_for(staple)}, "daily": cap}]
				break
	elif food > 2 * target and source.limits.has("grain"): rows = [{"give": {"grain": grain_for(STAPLES[0])}, "want": {STAPLES[0]: 1}, "daily": cap}]
	var facts := {"food": food, "target": target, "trader": trader, "rows": rows}
	if _same_rows(listings(data).get("rows", []), rows): return _evaluated(facts.merged({"reason": "unchanged"}))
	var result := set_listings(lab, trader, rows, true)
	return _evaluated(facts.merged({"reason": "set" if result.ok else "refused", "result": result}))

## Grain worth one unit of `resource` by the trade value table (at least 1, at most MAX_UNITS).
static func grain_for(resource: String) -> int:
	return clampi(roundi(Values.resource_value(resource) / Values.resource_value("grain")), 1, MAX_UNITS)

static func _evaluated(facts: Dictionary) -> Dictionary:
	last_evaluation = facts
	return facts
