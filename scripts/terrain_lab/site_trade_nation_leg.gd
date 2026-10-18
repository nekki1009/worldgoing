extends RefCounted
## T6 S5 part 2 (TR-63 / TR-64): one all-or-nothing commit for goods legs plus coin payment legs,
## with an optional nation side. No class_name (loaded by preload).
## D-T7: coin is a payment leg, never a goods leg. D-T8: a nation pays coin only from its bound treasury
## and the payment counts against the treasury's daily ceiling (the shared ransom ledger: spent_day/spent).
## D-T9: a person pays coin only from coin it physically carries (its own cargo; the S1 original-cargo rule).
## Receipts are keyed trade_id:side like S4; a repeated trade_id with the same request replays and changes nothing.
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Gate = preload("res://scripts/terrain_lab/site_trade_nation_source.gd")
const RansomData = preload("res://scripts/terrain_lab/site_ransom_data.gd")
const MAX_DAY := 2147483646
const MAX_COIN := 1000000

## Pure ledger rule shared with the ransom spend ledger. Nothing is written here.
static func ledger_candidate(record: Dictionary, day: int, spend: int, held: int) -> Dictionary:
	if not RansomData.valid_record(record): return {"ok": false, "code": "CORRUPT_STATE"}
	if spend < 0 or spend > MAX_COIN or day < 0 or day > MAX_DAY: return {"ok": false, "code": "INVALID"}
	if spend == 0: return {"ok": true, "code": "", "spent_day": int(record.spent_day), "spent": int(record.spent)}
	if not bool(record.policy.authorized): return {"ok": false, "code": "NOT_AUTHORIZED"}
	var spent_today: int = int(record.spent) if int(record.spent_day) == day else 0
	if spent_today + spend > int(record.policy.daily): return {"ok": false, "code": "DAILY_CEILING"}
	if held - spend < int(record.policy.reserve): return {"ok": false, "code": "RESERVE"}
	return {"ok": true, "code": "", "spent_day": day, "spent": spent_today + spend}

static func _trade_id_valid(trade_id: String) -> bool:
	return not trade_id.is_empty() and trade_id.length() <= 64 and not trade_id.contains(":")

static func _store(data: TerrainData) -> Dictionary:
	var store: Variant = data.site.get("trade_leg_receipts", {})
	if store is Dictionary: return store
	return {}

static func _tax_receipts_for(data: TerrainData, trade_id: String) -> bool:
	var store: Variant = data.site.get("trade_tax_receipts", {})
	if not store is Dictionary: return false
	for key: Variant in store.keys():
		if str(key).begins_with(trade_id + ":"): return true
	return false

static func _receipts_for(data: TerrainData, trade_id: String) -> Dictionary:
	var found: Dictionary = {}
	var store: Dictionary = _store(data)
	for key: Variant in store.keys():
		if str(key).begins_with(trade_id + ":"): found[str(key)] = store[key]
	return found

static func _request(goods_legs: Array, coin_legs: Array, nation_id: String, nation_holder: String, day: int) -> String:
	return JSON.stringify([goods_legs, coin_legs, nation_id, nation_holder, day])

## Commit entry. Replay is checked before any state is read for changes.
static func commit(data: TerrainData, refs: Array, goods_legs: Array, coin_legs: Array, trade_id: String, nation_id: String, nation_holder: String, day: int, preview: bool = false) -> Dictionary:
	if data == null or not _trade_id_valid(trade_id): return Runtime.fail("INVALID", "貿易編號不合法")
	# One trade_id names one kind of receipt: an id already used by an S4 tax receipt is refused.
	if _tax_receipts_for(data, trade_id): return Runtime.fail("INVALID", "貿易編號已用於稅收據")
	var request: String = _request(goods_legs, coin_legs, nation_id, nation_holder, day)
	var existing: Dictionary = _receipts_for(data, trade_id)
	if not existing.is_empty():
		for key: Variant in existing.keys():
			if str(existing[key].get("request", "")) != request: return Runtime.fail("INVALID", "收據鍵已用於不同交易")
		return Runtime.ok("重複提交：沿用原收據，未再付款", {"replayed": true, "receipt_keys": existing.keys()})
	var prepared: Dictionary = prepare(data, refs, goods_legs, coin_legs, trade_id, nation_id, nation_holder, day)
	if not prepared.ok: return prepared
	return Runtime.ok() if preview else publish(prepared)

static func prepare(data: TerrainData, refs: Array, goods_legs: Array, coin_legs: Array, trade_id: String, nation_id: String, nation_holder: String, day: int) -> Dictionary:
	if data == null or not _trade_id_valid(trade_id) or day < 0 or day > MAX_DAY: return Runtime.fail("INVALID")
	# Coin legs: exact shape, positive integer amount, payer is a person (D-T9) or the nation's treasury (D-T8).
	var converted: Array = []
	var spend: int = 0
	var refs_ids: Array = []
	for ref: Variant in refs:
		if ref is Dictionary and ref.get("holder") is String: refs_ids.append(str(ref.holder))
	for leg: Variant in coin_legs:
		if not leg is Dictionary or not Runtime.Technology.keys(leg, ["from", "to", "amount"]) or not leg.from is String or not leg.to is String \
			or not leg.amount is int or int(leg.amount) < 1 or int(leg.amount) > MAX_COIN:
			return Runtime.fail("INVALID", "硬幣付款腿格式不合法")
		var payer: String = leg.from
		var nation_payer: bool = nation_id != "" and payer == nation_holder
		if not payer.begins_with("person:") and not nation_payer: return Runtime.fail("COIN_PAYER", "硬幣只能由本人隨身持有者或本國國庫付款")
		if nation_payer: spend += int(leg.amount)
		converted.append({"from": payer, "to": leg.to, "resources": {"coin": int(leg.amount)}, "item_ids": []})
	# Nation side: the nation's bound treasury only (TR-64), and the shared daily ledger (D-T8).
	var ledger: Dictionary = {}
	var nation_json: String = ""
	if nation_id != "":
		if nation_holder.is_empty() or not refs_ids.has(nation_holder): return Runtime.fail("INVALID", "國家交易須列入國庫持有人")
		var gate: Dictionary = Gate.nation_source(data.site, nation_id, nation_holder)
		if not gate.ok: return gate
		var nation: Dictionary = data.site.equipment_nations[nation_id]
		var record: Dictionary = nation.ransom_data
		var stock: Dictionary = data.site.stockpiles[str(record.treasury.feature_id)]
		var held: int = int(stock.get("cargo", {}).get("coin", 0))
		# RansomData.valid_nations refuses spent_day after the game clock, so a trade spend may not name a future day.
		if spend > 0 and day > floori(float(data.site.get("minute", 0)) / 1440.0): return Runtime.fail("INVALID", "國庫付款日不得晚於遊戲現在")
		ledger = ledger_candidate(record, day, spend, held)
		if not ledger.ok: return Runtime.fail(str(ledger.code), "國庫付款未通過，原狀未變")
		nation_json = JSON.stringify(record)
	elif spend > 0:
		return Runtime.fail("INVALID", "硬幣由國庫付款須指定國家")
	var prepared: Dictionary = Runtime.prepare_candidate_with_coin(data, refs, goods_legs, converted)
	if not prepared.ok: return prepared
	var receipts: Array = []
	var request: String = _request(goods_legs, coin_legs, nation_id, nation_holder, day)
	for holder_id: String in refs_ids:
		var received: Dictionary = {}
		var items: Array = []
		var given: Dictionary = {}
		for good: Dictionary in goods_legs:
			if str(good.get("to", "")) == holder_id:
				for key: Variant in good.resources.keys(): received[str(key)] = int(received.get(str(key), 0)) + int(good.resources[key])
				items.append_array(good.item_ids)
			if str(good.get("from", "")) == holder_id:
				for key: Variant in good.resources.keys(): given[str(key)] = int(given.get(str(key), 0)) + int(good.resources[key])
		for payment: Dictionary in converted:
			if str(payment.to) == holder_id: received["coin"] = int(received.get("coin", 0)) + int(payment.resources.coin)
			if str(payment.from) == holder_id: given["coin"] = int(given.get("coin", 0)) + int(payment.resources.coin)
		if received.is_empty() and items.is_empty(): continue
		receipts.append({"key": trade_id + ":" + holder_id, "record": {"kind": "nation_leg" if nation_id != "" else "trade",
			"trade_id": trade_id, "side": holder_id, "nation_id": nation_id, "day": day, "received": received, "given": given,
			"items": items, "treasury_spend": spend if holder_id == nation_holder else 0, "request": request}})
	prepared["receipts"] = receipts
	prepared["nation_id"] = nation_id
	prepared["nation_holder"] = nation_holder
	prepared["ledger"] = ledger
	prepared["nation_json"] = nation_json
	return prepared

static func publish(prepared: Dictionary) -> Dictionary:
	var stable: Dictionary = Runtime.validate_prepared_item_candidate(prepared)
	if not stable.ok: return stable
	var data: TerrainData = prepared.terrain
	var nation_id: String = str(prepared.nation_id)
	if nation_id != "":
		var gate: Dictionary = Gate.nation_source(data.site, nation_id, str(prepared.nation_holder))
		if not gate.ok: return Runtime.fail("STALE_SOURCE", "國庫來源已改變")
		var record: Dictionary = data.site.equipment_nations[nation_id].ransom_data
		if JSON.stringify(record) != str(prepared.nation_json): return Runtime.fail("STALE_SOURCE", "國庫帳本已改變")
	var store: Dictionary = _store(data)
	for entry: Dictionary in prepared.receipts:
		if store.has(str(entry.key)): return Runtime.fail("STALE_SOURCE", "收據已存在")
	var committed: Dictionary = Runtime.publish_item_candidate(prepared)
	if not committed.ok: return committed
	# The ledger is the shared ransom record: trade spends and ransom spends both move spent_day/spent.
	# With nothing spent, ledger holds the unchanged values, so this write is a no-op.
	if nation_id != "":
		var ransom: Dictionary = data.site.equipment_nations[nation_id].ransom_data
		ransom.spent_day = int(prepared.ledger.spent_day)
		ransom.spent = int(prepared.ledger.spent)
	if not data.site.get("trade_leg_receipts") is Dictionary: data.site["trade_leg_receipts"] = {}
	var saved: Dictionary = data.site["trade_leg_receipts"]
	var keys: Array = []
	for entry: Dictionary in prepared.receipts:
		saved[str(entry.key)] = entry.record
		keys.append(str(entry.key))
	committed["receipt_keys"] = keys
	return committed
