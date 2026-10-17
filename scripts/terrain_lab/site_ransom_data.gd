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
	# Activation requires the future true-head command; this schema grants no spend.
	if not _keys(policy, ["authorized", "per_person", "daily", "reserve"]) \
		or not policy.authorized is bool or policy.authorized \
		or not Technology.integer(policy.per_person, 1, 35) or not Technology.integer(policy.daily, 1, 1000000) \
		or not Technology.integer(policy.reserve, 0, 1000000): return false
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
