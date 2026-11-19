extends "res://scripts/tests/site_market_t3_test.gd"
## 貿易 T3 slice 4 (reports/trade-plan.md §5.2, TR-34): listings seen elsewhere (RegionMarketObservation). Fixture: a
## level 2 settlement with a market listing 2 grain for 1 salt, 3 lots a day; the NPC holds a nation office (an officer
## present) and has travelled (a stable person ref); the Region slot is a test stand-in holding only the ledger and the
## logical clock (the real Region evaluation calls the same record).
## Checks:
## - the officer records the market's listings once: the receipt passes the ledger's rules, follows his stable ref, and
##   is about "market:<site>", not about the market feature (it never shadows a visible-feature receipt);
## - an unchanged market seen again adds nothing; changed listings add a newer receipt that is what he knows;
## - three game days later the listings he knows have expired and are not taken as current;
## - a Site whose market is not complete records nothing.
## Output: SITE_MARKET_OBSERVATION_T3_PASS on success; push_error + quit(1) on failure.

const Observation = preload("res://scripts/region_lab/region_market_observation.gd")
const RegionAI = preload("res://scripts/region_lab/region_gameplay_ai.gd")

class StandInSlot:
	var registry := {}
	var control := {"logical_game_seconds": 1000.0}
	func region_registry() -> Dictionary:
		return registry

var observation_checks := 0

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	observation_checks += 1
	if condition:
		print("SITE_MARKET_OBSERVATION_T3 OK ", observation_checks, ": ", message)
		return true
	push_error("SITE_MARKET_OBSERVATION_T3_FAIL: %s %s" % [message, str(detail)])
	quit(1)
	return false

func _run() -> void:
	var data := _building_fixture()
	data.site.id = RegionGrid.site_id(RegionGrid.ATLAS_ID, Vector2i.ZERO)
	var lab := _building_lab(data)
	var player := int(lab.character.person_id)
	var npc := int(lab.npc.person_id)
	var placed: bool = lab.character.place(Vector2i(20, 18), true)
	if not _check(placed, "the founder stands beside the center site"): return
	var layout := Runtime.building_cells(data, "settlement_center", Vector2i(20, 20), Vector2i(5, 5), OPTIONS)
	var center_cells: Array[int] = []
	center_cells.assign(layout.get("cells", []))
	var founded := Settlement.found(lab, player, center_cells, {"layout_version": 1, "quarter": 0}, Callable(), "觀測村")
	if not _check(founded.ok, "the player founds the settlement", founded): return
	var center_key := str(founded.feature)
	_complete_key(data, center_key)
	var center: Dictionary = data.site.features[center_key]
	var terms := Runtime.civil_investment_terms(data, center, 2)
	center["cost"] = terms.cost
	center["work"] = terms.work
	center["progress"] = terms.work
	data.site.settlement["level"] = 2
	var built := Runtime.request_build(data, "market", _cells(data, Vector2i(27, 20)), Callable(), OPTIONS)
	if not _check(built.ok, "the market is planned", built): return
	var key := str(built.feature)
	var scope := str(data.site.id)
	# The NPC holds a nation office (an officer present) and has travelled (a stable ref). Test-only, never saved.
	if not data.site.has("equipment_nations"): data.site["equipment_nations"] = {}
	data.site.equipment_nations["observation_test_nation"] = {"members": [npc], "standards": {}, "offices": SiteOffices.default_offices("nation", npc, true)}
	if not data.site.has("travel_identity"): data.site["travel_identity"] = {}
	if not data.site.travel_identity.has("refs"): data.site.travel_identity["refs"] = {}
	if not data.site.travel_identity.refs.has("person"): data.site.travel_identity.refs["person"] = {}
	data.site.travel_identity.refs.person[str(npc)] = {"type": "person", "namespace": "market_observation_test", "lineage": 7}
	var reference := RegionAI.person_ref(data.site, npc)
	if not _check(RegionAI.valid_person_ref(reference) and Strength_has(lab, npc), "the NPC is an officer present with a stable ref", reference): return
	var slot := StandInSlot.new()

	# A market still being built records nothing.
	var unbuilt := Observation.record(slot, lab)
	if not _check(unbuilt.ok and int(unbuilt.observed) == 0 and Observation.known(slot.registry, npc, 1000.0, scope, reference).is_empty(), "a market not yet complete records nothing", unbuilt): return
	_complete_key(data, key)
	var stocked := Stockpiles.ensure_storage(data, key, 1)
	var bound := Settlement.bind_trade_source(lab, player, key, {"grain": {"per_trade": 10, "total": 100}})
	var listed := Market.set_listings(lab, player, [{"give": {"grain": 2}, "want": {"salt": 1}, "daily": 3}])
	if not _check(stocked.ok and bound.ok and listed.ok, "the market stands with one listing", [stocked, bound, listed]): return

	# TR-34: recorded once, by the officer's stable ref, about the market object.
	var first := Observation.record(slot, lab)
	var known := Observation.known(slot.registry, npc, 1000.0, scope, reference)
	if not _check(first.ok and int(first.observed) == 1 and known.has(scope), "the officer records the market's listings", [first, known.keys()]): return
	var seen: Dictionary = known[scope].value
	if not _check(str(seen.market) == key and seen.rows.size() == 1 and _same_counts(seen.rows[0].give, {"grain": 2}) and _same_counts(seen.rows[0].want, {"salt": 1}) and int(seen.rows[0].daily) == 3 and bool(seen.open),
		"he knows the listing as it stands: 2 grain for 1 salt, 3 lots, open", seen): return
	var receipt: Dictionary = {}
	for value: Variant in slot.registry.observations.values():
		if str(value.get("observation_kind", "")) == Observation.KIND: receipt = value
	if not _check(str(receipt.get("object", "")) == "market:" + scope and RegionAI.observation_object_key(receipt) != scope + "/feature:" + key and receipt.get("receiver_ref") == reference,
		"the receipt is about market:<site> (never shadowing the feature) and follows his stable ref", receipt): return
	var again := Observation.record(slot, lab)
	if not _check(again.ok and int(again.observed) == 0, "an unchanged market seen again adds nothing", again): return

	# Changed listings: a newer receipt is what he knows.
	slot.control.logical_game_seconds = 2000.0
	var relisted := Market.set_listings(lab, player, [{"give": {"grain": 2}, "want": {"salt": 1}, "daily": 2}])
	var second := Observation.record(slot, lab)
	known = Observation.known(slot.registry, npc, 2000.0, scope, reference)
	if not _check(relisted.ok and second.ok and int(second.observed) == 1 and int(known[scope].value.rows[0].daily) == 2 and is_equal_approx(float(known[scope].game_time), 2000.0),
		"changed listings add a newer receipt that is what he knows", [second, known]): return

	# TR-34: expired listings are not current.
	var later := 2000.0 + Observation.LISTING_SECONDS + 1.0
	if not _check(Observation.known(slot.registry, npc, later, scope, reference).is_empty(), "three game days later the listings he knows have expired"): return

	print("SITE_MARKET_OBSERVATION_T3_PASS checks=", observation_checks, "; unbuilt nothing, recorded once by stable ref, market object, unchanged nothing, newer on change, expiry")
	_finish_workflow_body()
	for _frame: int in range(3): await process_frame
	lab.free()
	TerrainArmy.release_contact_source()
	quit(0)

func Strength_has(lab: TerrainLab, person: int) -> bool:
	return (load("res://scripts/region_lab/region_site_strength.gd") as Script).call("officers", lab).has(person)
