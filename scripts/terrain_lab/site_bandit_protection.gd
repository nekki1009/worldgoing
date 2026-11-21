extends RefCounted
## Protection money (土匪 B4b, reports/bandit-faction-spec.md §5.1, §11, §12). Once a calendar day at peace on a Site with a
## founded settlement: every active raiding band whose lair lies within two Sites asks, at most once per 30 days, for
## population x 1 grain. An NPC head pays while the camp holds at least PAY_STOCK_FACTOR fees of grain, else refuses; a
## settlement headed by the controlled person gets a notice and answers with `answer` within the 30 days (no answer is
## a refusal at the next demand). Paid grain leaves the camp stock and joins the band's hoard; the registry change
## commits with a Region checkpoint and a refused commit returns the grain. A band never asks its own faction.
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Settlement = preload("res://scripts/terrain_lab/site_settlement.gd")
const Calendar = preload("res://scripts/terrain_lab/site_calendar.gd")
const Tribute = preload("res://scripts/terrain_lab/site_tribute.gd")
const ProduceTax = preload("res://scripts/terrain_lab/site_produce_tax.gd")
const Bandit = preload("res://scripts/region_lab/region_bandit.gd")

const PAY_STOCK_FACTOR := 3

static var _done := {}
## {site_id: {band: fee}} demands waiting for the player's answer (runtime only; a reload asks again after 30 days).
static var pending := {}

static func reset() -> void:
	_done.clear()

static func population(data: TerrainData) -> int:
	return ProduceTax.residents(data).size()

static func day(lab: Variant, ctx: Dictionary = {}) -> Dictionary:
	if lab == null or lab.terrain == null or lab.site_controller == null or Settlement.record(lab.terrain).is_empty(): return {}
	var today := Calendar.day_index(float(lab.terrain.site.get("minute", 0)))
	var key: int = lab.get_instance_id()
	if int(_done.get(key, -1)) == today: return {}
	_done[key] = today
	return demand(lab, today, ctx)

## Today's demands. Returns {paid: [band], refused: [band], asked: [band]}.
static func demand(lab: Variant, today: int, ctx: Dictionary = {}) -> Dictionary:
	var result := {"paid": [], "refused": [], "asked": []}
	var live := ctx.is_empty()
	if live: ctx = Tribute.context_of(lab)
	if (ctx.registry as Dictionary).is_empty(): return result
	var site_id := str(lab.terrain.site.get("id", ""))
	var settlement := Settlement.record(lab.terrain)
	var head := Settlement.head_executor(lab, true)
	var fee := Bandit.protection_fee(population(lab.terrain))
	if fee <= 0: return result
	for band: int in Bandit.protection_due(ctx.registry, site_id, today):
		if band == int(settlement.get("owner_faction", -1)): continue
		if head > 0 and head == int(lab.controlled_person_id()):
			if not pending.has(site_id): pending[site_id] = {}
			pending[site_id][band] = fee
			if lab.terrain.site.get("notices") is Array: lab.terrain.site.notices.append("土匪（勢力 %d）索要保護費 %d 糧：到財政或聚落頁答覆，30 日內不答覆視同拒絕" % [band, fee])
			result.asked.append(band)
			continue
		var pay := int(lab.terrain.site.inventory.get("grain", 0)) >= fee * PAY_STOCK_FACTOR
		var answered := answer(lab, band, pay, today, ctx)
		(result.paid if pay and answered.ok else result.refused).append(band)
		if live: ctx = Tribute.context_of(lab) # a commit replaces the registry
	return result

## Pays (or refuses) `band`'s demand for this Site's settlement.
static func answer(lab: Variant, band: int, pay: bool, today: int = -1, ctx: Dictionary = {}) -> Dictionary:
	if ctx.is_empty(): ctx = Tribute.context_of(lab)
	if today < 0: today = Calendar.day_index(float(lab.terrain.site.get("minute", 0)))
	var site_id := str(lab.terrain.site.get("id", ""))
	var fee := Bandit.protection_fee(population(lab.terrain))
	var stock: Dictionary = lab.terrain.site.inventory
	if pay and int(stock.get("grain", 0)) < fee: return Runtime.fail("NOT_ENOUGH", "營地存糧不足以付保護費")
	var paid := {"grain": fee} if pay else {}
	var candidate: Dictionary = Bandit.protection_answer(ctx.registry, band, site_id, today, paid, float(Calendar.day_start_minute(today) + 1440) * 60.0)
	if not candidate.ok: return Runtime.fail(str(candidate.get("code", "INVALID")), str(candidate.get("message", "")))
	if pay: stock["grain"] = int(stock.grain) - fee
	var committed: Dictionary = ctx.commit.call(candidate.registry)
	if not committed.ok:
		if pay: stock["grain"] = int(stock.get("grain", 0)) + fee
		return committed
	if pending.has(site_id): pending[site_id].erase(band)
	return Runtime.ok("已付保護費 %d 糧，30 日內不受該伙劫掠" % fee if pay else "已拒絕保護費", {"fee": fee if pay else 0})
