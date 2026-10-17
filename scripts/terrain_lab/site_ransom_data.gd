extends RefCounted
## Data only: original nation/stock references and immutable capture-rank pricing.
## No authority resolution, policy activation, payment, release or supply commit.
const Stocks = preload("res://scripts/terrain_lab/site_stockpiles.gd")
const Technology = preload("res://scripts/terrain_lab/site_technology.gd")

static func empty_record() -> Dictionary:
	return {"version": 1, "treasury": {}, "policy": {"authorized": false, "per_person": 35, "daily": 50, "reserve": 20}, "spent_day": -1, "spent": 0}

static func _keys(raw: Variant, fields: Array[String]) -> bool:
	if not raw is Dictionary or raw.size() != fields.size(): return false
	for field: String in fields:
		if not raw.has(field): return false
	return true

static func valid_record(raw: Variant) -> bool:
	if not _keys(raw, ["version", "treasury", "policy", "spent_day", "spent"]) \
		or not Technology.integer(raw.version, 1, 1) or not raw.treasury is Dictionary \
		or not Technology.integer(raw.spent_day, -1, 2147483647) or not Technology.integer(raw.spent, 0, 1000000): return false
	if int(raw.spent_day) == -1 and int(raw.spent) != 0: return false
	var policy: Dictionary = raw.policy if raw.policy is Dictionary else {}
	var plain := _keys(policy, ["authorized", "per_person", "daily", "reserve"])
	var named := _keys(policy, ["authorized", "per_person", "daily", "reserve", "authorized_by"])
	if not (plain or named) or not policy.authorized is bool \
		or not Technology.integer(policy.per_person, 1, 35) or not Technology.integer(policy.daily, 1, 1000000) \
		or not Technology.integer(policy.reserve, 0, 1000000): return false
	# R4b-2: authority exists only as a command result: a bound treasury and one named authorizer.
	# A raw authorized flag without authorized_by (or without treasury) is still refused on load.
	if policy.authorized:
		if raw.treasury.is_empty() or not named or not Technology.integer(policy.authorized_by, 1, 2147483646): return false
	elif named: return false
	if raw.treasury.is_empty(): return true
	return _keys(raw.treasury, ["site_id", "feature_id", "holder"]) \
		and raw.treasury.site_id is String and not raw.treasury.site_id.is_empty() \
		and raw.treasury.feature_id is String and not raw.treasury.feature_id.is_empty() \
		and raw.treasury.holder is String and raw.treasury.holder == Stocks.identity(raw.treasury.feature_id)

static func valid_nations(nations: Dictionary, state: Dictionary) -> bool:
	var stocks: Variant = state.get("stockpiles", {})
	var features: Variant = state.get("features", {})
	if not stocks is Dictionary or not features is Dictionary: return false
	var claims := {}
	for nation_id: String in nations:
		var nation: Dictionary = nations[nation_id]
		if not nation.has("ransom_data"): continue
		if not nation.has("offices") or not valid_record(nation.ransom_data): return false
		var record: Dictionary = nation.ransom_data
		if bool(record.policy.authorized) and not _named_member(nation, int(record.policy.authorized_by)): return false
		if int(record.spent_day) > floori(float(state.get("minute", 0)) / 1440.0): return false
		if record.treasury.is_empty(): continue
		if nation_id.begins_with("trial_team_"): return false
		var ref: Dictionary = record.treasury
		if ref.site_id != str(state.get("id", "")) or claims.has(ref.feature_id): return false
		var feature: Variant = features.get(ref.feature_id)
		var stock: Variant = stocks.get(ref.feature_id)
		if not feature is Dictionary or not stock is Dictionary \
			or not feature.get("kind") is String or feature.kind != "warehouse" \
			or not feature.get("stage") is String or feature.stage != "complete" \
			or not Technology.integer(feature.get("owner_faction"), 0, 2147483647) \
			or not stock.get("nation_id") is String or stock.nation_id != nation_id or not stock.get("holder") is Dictionary \
			or not stock.holder.get("holder") is String or stock.holder.holder != ref.holder: return false
		claims[ref.feature_id] = nation_id
	for key: Variant in stocks:
		var stock: Variant = stocks[key]
		if stock is Dictionary and stock.has("nation_id"):
			if not key is String or not stock.nation_id is String or not claims.has(key) or claims[key] != stock.nation_id: return false
	# The original stock validator owns counts, real holder shape and combined load.
	if not claims.is_empty():
		var checked: Dictionary = Stocks.validate(state)
		if not checked.ok: return false
	return true

static func normalize_numbers(record: Dictionary) -> void:
	# Store validates raw JSON before normalization; never synthesize a missing record.
	if not valid_record(record): return
	record.version = int(record.version)
	record.spent_day = int(record.spent_day)
	record.spent = int(record.spent)
	for field: String in ["per_person", "daily", "reserve"]: record.policy[field] = int(record.policy[field])
	if record.policy.has("authorized_by"): record.policy.authorized_by = int(record.policy.authorized_by)

static func _round_tenths(value: int) -> int:
	return (1 if value >= 0 else -1) * floori(float(absi(value)) / 10.0 + 0.5)

## Caller must supply the current settlement.prison resolved PersonRef/personality,
## then revalidate that authority and the custody episode before any real offer.
static func quote(captivity: Dictionary, resolved_prison_decider: Dictionary) -> Dictionary:
	if not _keys(resolved_prison_decider, ["duty_id", "person_ref", "thrift", "mercy"]) \
		or not resolved_prison_decider.duty_id is String or resolved_prison_decider.duty_id != "settlement.prison" \
		or not Technology.valid_ref(resolved_prison_decider.person_ref) \
		or not Technology.integer(resolved_prison_decider.thrift, 0, 100) \
		or not Technology.integer(resolved_prison_decider.mercy, 0, 100) \
		or not Technology.integer(captivity.get("version"), 1, 3): return {"ok": false, "code": "INVALID_QUOTE_DATA"}
	var rank := "unknown"
	if int(captivity.version) == 3:
		if not captivity.get("rank_snapshot") is String \
			or captivity.rank_snapshot not in ["commoner", "officer", "head", "unknown"]: return {"ok": false, "code": "INVALID_CAPTURE_RANK"}
		rank = str(captivity.rank_snapshot)
	var base: int = 25 if rank == "head" else (15 if rank == "officer" else 10)
	var price: int = clampi(base + _round_tenths(int(resolved_prison_decider.thrift) - 50) - _round_tenths(int(resolved_prison_decider.mercy) - 50), 5, 35)
	return {"ok": true, "code": "QUOTE_DATA_ONLY", "coin": price, "base": base,
		"rank_source": "legacy_unknown" if rank == "unknown" else "captured_snapshot",
		"decider": resolved_prison_decider.duplicate(true)}

## R4b-1 candidate: bind the nation's own treasury to one complete warehouse it owns.
## Pure: the caller has already resolved the nation.ransom duty. No coin moves here.
static func bind_candidate(site: Dictionary, nation_id: String, nation: Dictionary, feature_id: String) -> Dictionary:
	if nation_id.begins_with("trial_team_") or not nation.has("offices") or not nation.has("faction_id") \
		or not Technology.integer(nation.faction_id, 0, 2147483647): return {"ok": false, "code": "NO_FORMAL_NATION"}
	var record: Dictionary = nation.ransom_data if nation.has("ransom_data") else empty_record()
	if not valid_record(record): return {"ok": false, "code": "CORRUPT_STATE"}
	if not record.treasury.is_empty(): return {"ok": false, "code": "TREASURY_BOUND"}
	var features: Variant = site.get("features", {})
	var stockpiles: Variant = site.get("stockpiles", {})
	if not features is Dictionary or not stockpiles is Dictionary: return {"ok": false, "code": "CORRUPT_STATE"}
	var feature: Variant = features.get(feature_id)
	var stock: Variant = stockpiles.get(feature_id)
	if not feature is Dictionary or not stock is Dictionary: return {"ok": false, "code": "NO_TARGET"}
	if str(feature.get("kind", "")) != "warehouse" or str(feature.get("stage", "")) != "complete": return {"ok": false, "code": "NOT_WAREHOUSE"}
	if not Technology.integer(feature.get("owner_faction"), 0, 2147483647) or int(feature.owner_faction) != int(nation.faction_id): return {"ok": false, "code": "FOREIGN_FACTION"}
	if stock.has("nation_id"): return {"ok": false, "code": "STOCK_CLAIMED"}
	var candidate_record: Dictionary = record.duplicate(true)
	candidate_record.treasury = {"site_id": str(site.get("id", "")), "feature_id": feature_id, "holder": Stocks.identity(feature_id)}
	var candidate_nation: Dictionary = nation.duplicate(true)
	candidate_nation.ransom_data = candidate_record
	var candidate_stock: Dictionary = stock.duplicate(true)
	candidate_stock.nation_id = nation_id
	if not valid_nations({nation_id: candidate_nation}, _view(site, feature_id, candidate_stock)): return {"ok": false, "code": "CORRUPT_STATE"}
	return {"ok": true, "code": "", "nation": candidate_nation, "stock": candidate_stock}

## R4b-1 policy candidate: ceilings only. `authorized` stays false; R4b-2 owns activation.
static func policy_candidate(site: Dictionary, nation_id: String, nation: Dictionary, per_person: int, daily: int, reserve: int) -> Dictionary:
	if nation_id.begins_with("trial_team_") or not nation.has("offices"): return {"ok": false, "code": "NO_FORMAL_NATION"}
	var record: Dictionary = nation.ransom_data if nation.has("ransom_data") else empty_record()
	if not valid_record(record): return {"ok": false, "code": "CORRUPT_STATE"}
	var candidate_record: Dictionary = record.duplicate(true)
	candidate_record.policy.per_person = per_person
	candidate_record.policy.daily = daily
	candidate_record.policy.reserve = reserve
	# Changing ceilings revokes payer authorization; the holder must authorize the new numbers.
	candidate_record.policy.authorized = false
	candidate_record.policy.erase("authorized_by")
	if not valid_record(candidate_record): return {"ok": false, "code": "INVALID_POLICY"}
	var candidate_nation: Dictionary = nation.duplicate(true)
	candidate_nation.ransom_data = candidate_record
	if not valid_nations({nation_id: candidate_nation}, _view(site, "", {})): return {"ok": false, "code": "CORRUPT_STATE"}
	return {"ok": true, "code": "", "nation": candidate_nation}

## Read-only validation view: the site's own features and stock, with one candidate stock replaced.
static func _view(site: Dictionary, feature_id: String, stock: Dictionary) -> Dictionary:
	var stockpiles: Dictionary = site.get("stockpiles", {}).duplicate(false)
	if not feature_id.is_empty(): stockpiles[feature_id] = stock
	return {"id": site.get("id", ""), "minute": site.get("minute", 0), "features": site.get("features", {}), "stockpiles": stockpiles}

## R4b-2 payer-side authorization candidate. Only the caller's resolved nation.ransom authority may
## use it. Authorization needs a bound treasury; revocation clears the authorizer. Grants no spend (R4c).
static func authorize_candidate(site: Dictionary, nation_id: String, nation: Dictionary, requester_id: int, authorized: bool) -> Dictionary:
	if nation_id.begins_with("trial_team_") or not nation.has("offices") or not nation.has("ransom_data"): return {"ok": false, "code": "NO_TREASURY"}
	var record: Dictionary = nation.ransom_data
	if not valid_record(record): return {"ok": false, "code": "CORRUPT_STATE"}
	if authorized and record.treasury.is_empty(): return {"ok": false, "code": "NO_TREASURY"}
	if authorized and requester_id <= 0: return {"ok": false, "code": "NO_AUTHORITY"}
	# Re-sending the same state by the same authorizer is no change; a different legitimate
	# authorizer re-authorizing updates authorized_by (a real change of who stands behind it).
	if authorized == bool(record.policy.authorized) and (not authorized or int(record.policy.authorized_by) == requester_id): return {"ok": false, "code": "NO_CHANGE"}
	var candidate_record: Dictionary = record.duplicate(true)
	candidate_record.policy.authorized = authorized
	if authorized: candidate_record.policy.authorized_by = requester_id
	else: candidate_record.policy.erase("authorized_by")
	var candidate_nation: Dictionary = nation.duplicate(true)
	candidate_nation.ransom_data = candidate_record
	if not valid_nations({nation_id: candidate_nation}, _view(site, "", {})): return {"ok": false, "code": "CORRUPT_STATE"}
	return {"ok": true, "code": "", "nation": candidate_nation}

static func _named_member(nation: Dictionary, identity: int) -> bool:
	for member: Variant in nation.get("members", []):
		if int(member) == identity: return true
	return false

## R4c-1 pure spend candidate: ceilings, reserve and payer authorization for one coin ransom.
## `authority_ok` is the caller's live check (D4: the current nation.ransom authority equals authorized_by,
## and authorized_by is still a living member). Moves no coin: the caller applies `coin_after` and `record`
## in one publish together with the captive release, or changes nothing.
static func spend_candidate(site: Dictionary, nation_id: String, nation: Dictionary, price: int, day: int, authority_ok: bool) -> Dictionary:
	if not authority_ok: return {"ok": false, "code": "STALE_AUTHORITY"}
	if nation_id.begins_with("trial_team_") or not nation.has("ransom_data") or not valid_record(nation.ransom_data): return {"ok": false, "code": "CORRUPT_STATE"}
	var record: Dictionary = nation.ransom_data
	if record.treasury.is_empty() or not bool(record.policy.authorized): return {"ok": false, "code": "NOT_AUTHORIZED"}
	if price < 5 or price > 35: return {"ok": false, "code": "INVALID_PRICE"}
	if price > int(record.policy.per_person): return {"ok": false, "code": "PER_PERSON_CEILING"}
	var spent: int = int(record.spent) if int(record.spent_day) == day else 0
	if spent + price > int(record.policy.daily): return {"ok": false, "code": "DAILY_CEILING"}
	var stock: Variant = site.get("stockpiles", {}).get(str(record.treasury.feature_id))
	if not stock is Dictionary or str(stock.get("nation_id", "")) != nation_id: return {"ok": false, "code": "NO_TREASURY_STOCK"}
	var held: int = int(stock.get("cargo", {}).get("coin", 0))
	if held - price < int(record.policy.reserve): return {"ok": false, "code": "RESERVE"}
	var candidate_record: Dictionary = record.duplicate(true)
	candidate_record.spent_day = day
	candidate_record.spent = spent + price
	return {"ok": true, "code": "", "record": candidate_record, "coin_after": held - price}
