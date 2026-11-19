extends RefCounted
## 貿易 T3 slice 4 (reports/trade-plan.md §5.2, TR-34): market listings seen elsewhere. At each Region evaluation of a
## Site with a completed market, every officer present (RegionSiteStrength.officers: team commanders and nation office
## holders) records the market's listings as they stand: a receipt about "market:<site id>" that follows him by his
## stable person ref (he carries what he saw) and expires after LISTING_SECONDS, so a decider elsewhere knows the
## listings as they were when seen and never takes an expired one as current. An unchanged market seen again adds
## nothing; a market with nothing listed is recorded too, so old listings stop being current. The object is not a
## feature ref, so it never shadows the officer's visible-feature receipt about the same building.
const RegionAI = preload("res://scripts/region_lab/region_gameplay_ai.gd")
const Strength = preload("res://scripts/region_lab/region_site_strength.gd")
const Market = preload("res://scripts/terrain_lab/site_market.gd")
const Settlement = preload("res://scripts/terrain_lab/site_settlement.gd")
const Calendar = preload("res://scripts/terrain_lab/site_calendar.gd")

const KIND := "market_listings"
const LISTING_SECONDS := 3.0 * 86400.0

static func object_of(site_id: String) -> String:
	return "market:" + site_id

## What an officer sees of this Site's market: {market, rows [{give, want, daily}], open, settlement_owner}, or {} with no
## completed market.
static func value_of(lab: Variant) -> Dictionary:
	var data: TerrainData = lab.terrain
	var key := Market.market_key(data.site)
	if key.is_empty() or str(data.site.features[key].get("stage", "")) != "complete": return {}
	var rows: Array = []
	for row: Variant in Market.listings(data).get("rows", []):
		if row is Dictionary: rows.append({"give": row.give.duplicate(), "want": row.want.duplicate(), "daily": int(row.daily)})
	return {"market": key, "rows": rows, "open": bool(Market.open_state(data, key).open), "settlement_owner": int(Settlement.record(data).get("owner_faction", -1))}

## Records this Site's market for every officer present. {ok, observed}.
static func record(slot: Variant, lab: Variant) -> Dictionary:
	var value := value_of(lab)
	if value.is_empty(): return {"ok": true, "observed": 0}
	var registry: Dictionary = slot.region_registry()
	var scope := str(lab.terrain.site.id)
	var now := float(slot.control.logical_game_seconds)
	var object := object_of(scope)
	var observed := 0
	for officer: int in Strength.officers(lab):
		var reference := RegionAI.person_ref(lab.terrain.site, officer)
		if not RegionAI.valid_person_ref(reference): continue
		var prior: Dictionary = RegionAI.view(registry, officer, now, scope, reference).get(object, {})
		if prior.get("observation_kind") == KIND and prior.get("value") == value: continue
		var receipt := {"id": "market-listings:%s:%s:%.6f" % [scope, RegionTravel.stable_key(reference), now],
			"source": "site_observation", "observation_kind": KIND, "observer": officer, "receiver": officer,
			"observer_scope": scope, "receiver_scope": scope, "object_scope": scope,
			"observer_ref": reference.duplicate(true), "receiver_ref": reference.duplicate(true), "object": object, "value": value,
			"game_time": now, "expires_at": now + LISTING_SECONDS, "confidence": 1.0}
		var recorded := RegionAI.observe(registry, receipt)
		if not recorded.ok:
			if str(recorded.get("code", "")) == "OBSERVATION_CONFLICT": continue # a second change in the same instant waits
			return recorded
		observed += 1
	return {"ok": true, "observed": observed}

## The markets `person` knows of, unexpired at `now`: {site id: {value, game_time, expires_at}}.
static func known(registry: Dictionary, person: int, now: float, scope: String = "", reference: Dictionary = {}) -> Dictionary:
	var result := {}
	var seen := RegionAI.view(registry, person, now, scope, reference)
	for object: Variant in seen:
		var receipt: Dictionary = seen[object]
		if receipt.get("observation_kind") != KIND: continue
		result[str(receipt.get("object_scope", ""))] = {"value": receipt.value, "game_time": float(receipt.game_time), "expires_at": float(receipt.expires_at)}
	return result

## 貿易 T4 TR-42: what the player's map says of a Site's market. `known` is RegionMarketObservation.known for the player;
## a Site he has no unexpired receipt for is "未知" (never a guess, never someone else's knowledge).
static func line_for(known: Dictionary, site_id: String) -> String:
	if not known.has(site_id): return "市集掛牌：未知"
	var entry: Dictionary = known[site_id]
	return "市集掛牌：%s（觀察於 %s）" % [summary(entry.get("value", {})), Calendar.clock_text(float(floori(float(entry.game_time) / 60.0)))]

## The listings as people read them: "付 鹽 1 得 糧食 2（每日 3 份）；…", "沒有掛牌", with "（暫停）" when closed.
static func summary(value: Dictionary) -> String:
	var parts: Array = []
	for row: Variant in value.get("rows", []):
		if row is Dictionary: parts.append("付 %s 得 %s（每日 %d 份）" % [Market.stack_text(row.get("want", {})), Market.stack_text(row.get("give", {})), int(row.get("daily", 0))])
	var text := "沒有掛牌" if parts.is_empty() else "；".join(parts)
	return text + ("" if bool(value.get("open", true)) else "（暫停）")
