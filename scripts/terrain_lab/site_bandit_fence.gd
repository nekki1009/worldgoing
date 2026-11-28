extends RefCounted
## 土匪 B5b-1 銷贓（reports/bandit-faction-spec.md §7.1，A 市集暗盤，草案 2026-11-22）.
## A settlement's officials (warehouse, market listings, head) refuse a band (§7). A band member may still sell, in
## person, to a settlement civilian: a person of the settlement's owner faction with no office, a civilian military
## role and no duty, trading from his own cargo. The band side gives goods only (no coin); the civilian pays in food or
## coin only. He wants twice the value he pays (PRICE_FACTOR on the original haggling margin), and he refuses while an
## able office holder or soldier of the owner faction can see either party (WATCHED, judged at the offer, the accept
## and every frame of the delivery). A completed sale raises the band's heat by Bandit.HEAT_FENCE.
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Settlement = preload("res://scripts/terrain_lab/site_settlement.gd")
const Sight = preload("res://scripts/terrain_lab/site_army_ai.gd")
const Strength = preload("res://scripts/region_lab/region_site_strength.gd")
const Bandit = preload("res://scripts/region_lab/region_bandit.gd")
const Values = preload("res://scripts/terrain_lab/site_trade_values.gd")

const PRICE_FACTOR := 2.0
const WATCHED_TEXT := "聚落的官員或士兵看得到，對方不敢收贓"
const HOSTILE_TEXT := "敵對勢力之間不能交易"
const NOT_FENCE_TEXT := "敵對勢力之間不能交易（只有聚落平民會私下收贓）"

static func _registry(controller: Variant) -> Dictionary:
	if controller == null or controller.region_slot == null: return {}
	return controller.region_slot.control.get("faction_registry", {})

## The band of `person` (a world person dictionary from SitePersonActions._person), or -1.
static func band_of(controller: Variant, person: Dictionary) -> int:
	var faction := int(person.get("faction", -1))
	return faction if RegionFactionQuery.is_bandit(_registry(controller), faction) else -1

## People holding a settlement or nation office on this Site.
static func office_holders(data: TerrainData) -> Dictionary:
	var holders := {}
	var settlement: Dictionary = Settlement.record(data)
	for entry: Dictionary in settlement.get("offices", {}).get("positions", []):
		if int(entry.get("holder", -1)) > 0: holders[int(entry.holder)] = true
	for nation: Variant in data.site.get("equipment_nations", {}).values():
		if not nation is Dictionary: continue
		for entry: Dictionary in nation.get("offices", {}).get("positions", []):
			if int(entry.get("holder", -1)) > 0: holders[int(entry.holder)] = true
	return holders

## "" when `npc_id` may buy stolen goods here, else why not.
static func civilian_refusal(controller: Variant, npc_id: int, npc: Dictionary) -> String:
	var data: TerrainData = controller.lab.terrain
	var settlement: Dictionary = Settlement.record(data)
	if settlement.is_empty() or not settlement.has("owner_faction"): return "NO_SETTLEMENT"
	if int(npc.get("faction", -1)) != int(settlement.owner_faction): return "NOT_RESIDENT"
	if SiteOffices.body_military_role(npc.get("body")) != "civilian": return "NOT_CIVILIAN"
	if office_holders(data).has(npc_id): return "OFFICIAL"
	# A standing duty (guard post, work team, delivery, vehicle operator). Being busy is judged by the trade itself
	# (both sides idle at the offer and the accept); during the delivery the civilian is busy with this very trade.
	if controller.person_actions.is_guarding(npc_id) or controller.work_team.is_assigned(npc_id) or controller._is_delivering_person(npc_id) \
			or controller.vehicles.is_operator(npc_id): return "ON_DUTY"
	return ""

## Is any able office holder or soldier of the settlement's owner faction in sight of one of `cells`?
static func watched(controller: Variant, cells: Array) -> bool:
	var lab: Variant = controller.lab
	var settlement: Dictionary = Settlement.record(lab.terrain)
	if settlement.is_empty() or not settlement.has("owner_faction"): return false
	var owner := int(settlement.owner_faction)
	var holders := office_holders(lab.terrain)
	var watchers: Array = []
	for person: Dictionary in Strength.people(lab):
		if int(person.faction) != owner or not (bool(person.armed) or holders.has(int(person.id))): continue
		watchers.append({"cell": person.cell})
	if watchers.is_empty(): return false
	for cell: Variant in cells:
		if Sight._observed_cell(lab, watchers, Vector2i(cell), Sight.THREAT_DISTANCE): return true
	return false

## A hostile pair may still trade when `a` (the controlled side) is a band member selling from his own cargo to a
## settlement civilian who is not watched. Returns ok {band} or HOSTILE / WATCHED.
static func admit(controller: Variant, a: Dictionary, b: Dictionary, npc_id: int, npc_holder: String, player_holder: String) -> Dictionary:
	var band := band_of(controller, a)
	if band < 0: return Runtime.fail("HOSTILE", HOSTILE_TEXT)
	if not npc_holder.is_empty() or not player_holder.is_empty() or not civilian_refusal(controller, npc_id, b).is_empty():
		return Runtime.fail("HOSTILE", NOT_FENCE_TEXT)
	if watched(controller, [a.cell, b.cell]): return Runtime.fail("WATCHED", WATCHED_TEXT)
	return Runtime.ok("", {"band": band})

## "" when the goods fit a fence deal: the band gives goods only (no coin), the civilian pays food or coin only.
static func goods_refusal(band_gives: Dictionary, civilian_gives: Dictionary) -> String:
	if int(band_gives.get("resources", {}).get("coin", 0)) > 0: return "銷贓只賣不買：不能出錢"
	if not civilian_gives.get("item_ids", []).is_empty(): return "銷贓只換糧或錢"
	for resource: String in civilian_gives.get("resources", {}):
		if int(civilian_gives.resources[resource]) > 0 and resource != "coin" and not resource in Values.FOODS: return "銷贓只換糧或錢"
	return ""

## After a committed fence deal: the band's heat rises by Bandit.HEAT_FENCE. A registry commit captures the Site, which
## is refused while a Region point is open or consuming (REGION_EFFECT_RUNNING), so the rise is queued on the controller
## and committed by flush() at the next frame the Site is at rest (SiteController.settle_person_deaths, as the daily hooks).
static func queue_heat(controller: Variant, band: int) -> void:
	var due: Dictionary = controller.get_meta(&"fence_heat_due", {})
	due[band] = int(due.get(band, 0)) + 1
	controller.set_meta(&"fence_heat_due", due)

## Commits every queued rise in one registry commit. {ok, flushed: {band: sales}} or {ok false, code} (kept queued).
static func flush(controller: Variant) -> Dictionary:
	var due: Dictionary = controller.get_meta(&"fence_heat_due", {})
	if due.is_empty(): return Runtime.ok("", {"flushed": {}})
	var slot: Variant = controller.region_slot
	if slot == null: return Runtime.fail("UNSUPPORTED")
	var lab: Variant = controller.lab
	if lab != null and (not lab._region_point_pending.is_empty() or lab._region_point_consuming or lab._region_point_dispatching): return Runtime.fail("REGION_EFFECT_RUNNING")
	var registry: Dictionary = slot.control.faction_registry
	var now := float(slot.control.logical_game_seconds)
	var bands: Array = due.keys()
	bands.sort()
	var candidate := {"ok": true, "registry": registry}
	for band: Variant in bands:
		if not RegionFactionQuery.is_bandit(candidate.registry, int(band)): continue # the band ended meanwhile
		var heat := int(RegionFactionQuery.bandit_of(candidate.registry, int(band)).get("heat", 0))
		for _sale: int in range(int(due[band])): heat = Bandit.heat_after(heat, "fence")
		candidate = Bandit.set_heat(candidate.registry, int(band), heat, now)
		if not candidate.ok: return candidate
	var committed: Dictionary = controller.commit_registry(candidate)
	if not committed.ok: return committed
	controller.remove_meta(&"fence_heat_due")
	return Runtime.ok("", {"flushed": due})
