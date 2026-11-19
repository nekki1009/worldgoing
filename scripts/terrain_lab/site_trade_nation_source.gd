extends RefCounted
## T6 S5 (TR-64): pure gate for a nation acting as a trade SELLER. No class_name (loaded by preload).
## A nation may sell only from its own bound treasury (R4b-1 ransom_data.treasury, stock nation_id).
## Every other holder (general warehouse, procurement destination, person, depot, vehicle) is refused.
## Reads the Site dictionary only; never writes it.
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const TREASURY_PREFIX := "feature:"

static func nation_source(site: Dictionary, nation_id: String, holder_id: String) -> Dictionary:
	if site.is_empty() or nation_id.is_empty(): return Runtime.fail("NO_TARGET")
	var nations: Variant = site.get("equipment_nations", {})
	if not nations is Dictionary or not nations.get(nation_id) is Dictionary: return Runtime.fail("NO_TARGET", "須為已建立的國家")
	var nation: Dictionary = nations[nation_id]
	var ransom: Variant = nation.get("ransom_data", {})
	var treasury: Variant = {}
	if ransom is Dictionary: treasury = ransom.get("treasury", {})
	if not treasury is Dictionary or treasury.is_empty() or not treasury.get("feature_id") is String or not treasury.get("holder") is String:
		return Runtime.fail("NO_TREASURY", "國家尚未綁定國庫")
	var bound: String = str(treasury.feature_id)
	if str(treasury.get("site_id", "")) != str(site.get("id", "")) or str(treasury.holder) != TREASURY_PREFIX + bound:
		return Runtime.fail("NO_TREASURY", "國庫綁定不在本聚落")
	if holder_id != TREASURY_PREFIX + bound: return Runtime.fail("NOT_NATION_SOURCE", "國家只能從綁定國庫出貨")
	var stock: Variant = site.get("stockpiles", {}).get(bound)
	if not stock is Dictionary or str(stock.get("nation_id", "")) != nation_id: return Runtime.fail("NO_TREASURY", "國庫未明示本國")
	return Runtime.ok("", {"holder": holder_id})
