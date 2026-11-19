extends "res://scripts/tests/site_r3_prison_interface_test.gd"

## R4b-2 lab-level contract through the real controller: 贖務官 binding, ceilings, payer-side authorization,
## revocation, appointed holder, non-holder refusals, byte-identical refusals and the nation dialog.
## No coin is moved and no captive is released.
const RansomPure = preload("res://scripts/terrain_lab/site_ransom_data.gd")
const StockPure = preload("res://scripts/terrain_lab/site_stockpiles.gd")

func _run() -> void:
	# Pure raw-load rules first: an authorized flag alone is never accepted.
	var pure: Dictionary = RansomPure.empty_record()
	pure.treasury = {"site_id": "pure", "feature_id": "f", "holder": StockPure.identity("f")}
	pure.policy.authorized = true
	if not _r3_check(not RansomPure.valid_record(pure), "raw authorized without authorized_by is refused on load"): return
	pure.policy.authorized_by = 7
	if not _r3_check(RansomPure.valid_record(pure), "named authorizer with a bound treasury is valid"): return
	pure.treasury = {}
	if not _r3_check(not RansomPure.valid_record(pure), "authorization without a treasury is refused"): return
	var data := _building_fixture()
	if not _r3_check(not _r3_failed and data != null, "inherited terrain setup failed"): return
	var lab := _building_lab(data)
	if not _r3_check(not _r3_failed and lab != null, "inherited lab setup failed"): return
	var controller: SiteController = lab.site_controller
	var orders: SiteEquipmentOrders = controller.equipment_orders
	var requester := int(lab.controlled_person_id())
	var keeper := int(lab.npc.person_id)
	if not _r3_check(requester > 0 and keeper > 0 and requester != keeper, "two distinct real people"): return
	var key := _formal_feature(data, "warehouse", Vector2i(20, 20))
	if not _r3_check(not _r3_failed and not key.is_empty(), "complete warehouse"): return
	if not _r3_check(StockPure.ensure_storage(data, key, 1).ok, "warehouse stock"): return
	# Formal nation: the controlled person is the head; the 贖務官 seat is vacant so the head acts.
	data.site.equipment_nations = {"n1": {"offices": SiteOffices.default_offices("nation", requester, false), "members": [requester, keeper], "standards": {}}}
	# The original validator reads the Site's captured bodies (site.actors/armies), which the
	# controller writes on save or handoff. Capture them first so head and keeper are known people.
	controller._capture_positions()
	if not _r3_check(data.site.actors.has("player") and data.site.actors.has("npc"), "captured bodies present"): return
	var prepared: Dictionary = SiteEquipmentOrders.prepare_faction_nation(data.site, "n1", 1)
	if not _r3_check(bool(prepared.ok), "formal faction binding: " + str(prepared)): return
	data.site = prepared.state
	var nation: Dictionary = data.site.equipment_nations.n1
	var no_treasury: Dictionary = orders.authorize_nation_ransom(requester, "n1", true)
	if not _r3_check(str(no_treasury.code) == "NO_TREASURY", "authorization needs a bound treasury: " + str(no_treasury)): return
	var stranger_bind: Dictionary = orders.bind_nation_treasury(keeper, "n1", key)
	if not _r3_check(str(stranger_bind.code) == "NO_AUTHORITY", "a member who is not the decider cannot bind: " + str(stranger_bind)): return
	var bound: Dictionary = orders.bind_nation_treasury(requester, "n1", key)
	if not _r3_check(bool(bound.ok), "acting head binds the national treasury: " + str(bound)): return
	if not _r3_check(str(data.site.stockpiles[key].nation_id) == "n1", "the warehouse is claimed by n1"): return
	var policy: Dictionary = orders.set_nation_ransom_policy(requester, "n1", 20, 60, 10)
	if not _r3_check(bool(policy.ok), "acting head sets ceilings: " + str(policy)): return
	var stranger_auth: Dictionary = orders.authorize_nation_ransom(keeper, "n1", true)
	if not _r3_check(str(stranger_auth.code) == "NO_AUTHORITY", "a non-decider cannot authorize: " + str(stranger_auth)): return
	# Nation dialog: shows the same state, and its authorize button calls the real command.
	controller._open_nation_ransom("n1", null)
	var dialog: Node = root.find_child("NationRansomDialog", true, false)
	if not _r3_check(dialog != null, "the nation ransom dialog opens"): return
	var status: Label = dialog.find_child("NationRansomStatus", true, false)
	if not _r3_check(status != null and status.text.contains("國庫：倉庫 " + key) and status.text.contains("未授權付款"), "dialog shows the bound treasury and unauthorized state"): return
	var authorize_button: Button = dialog.find_child("NationRansomAuthorize", true, false)
	if not _r3_check(authorize_button != null and not authorize_button.text.contains("撤銷"), "dialog offers authorization"): return
	authorize_button.pressed.emit()
	if not _r3_check(bool(nation.ransom_data.policy.authorized) and int(nation.ransom_data.policy.authorized_by) == requester, "dialog authorization records the controlled holder"): return
	var coin_before: Dictionary = data.site.stockpiles[key].cargo.duplicate(true)
	var revoked: Dictionary = orders.authorize_nation_ransom(requester, "n1", false)
	if not _r3_check(bool(revoked.ok) and not bool(nation.ransom_data.policy.authorized) and not nation.ransom_data.policy.has("authorized_by"), "holder revokes authorization: " + str(revoked)): return
	var reauthorized: Dictionary = orders.authorize_nation_ransom(requester, "n1", true)
	if not _r3_check(bool(reauthorized.ok), "holder authorizes again"): return
	# Appoint the keeper as 贖務官: the head no longer exercises it, the appointee does.
	var seat_id: String = str(nation.offices.duties["nation.ransom"])
	# 文武官 W2: a 文官 seat needs a 文吏 (a 武官 seat an officer); the fixture qualifies its holder first.
	TerrainTestCharacter.PersonSocial.set_civil_role(lab.site_controller.person_actions._person(keeper, false).body, "clerk")
	var appoint: Dictionary = orders.apply_nation_office_plan(requester, "n1", int(nation.offices.revision), [{"op": "appoint", "position_id": seat_id, "person_id": keeper}])
	if not _r3_check(bool(appoint.ok), "head appoints the 贖務官: " + str(appoint)): return
	var before: PackedByteArray = var_to_bytes([nation, data.site.stockpiles[key]])
	var by_head: Dictionary = orders.set_nation_ransom_policy(requester, "n1", 25, 60, 10)
	if not _r3_check(str(by_head.code) == "NO_AUTHORITY", "the head no longer acts for the seated 贖務官: " + str(by_head)): return
	var refused_auth: Dictionary = orders.authorize_nation_ransom(requester, "n1", false)
	if not _r3_check(str(refused_auth.code) == "NO_AUTHORITY", "the head cannot revoke either"): return
	if not _r3_check(before == var_to_bytes([nation, data.site.stockpiles[key]]), "refused commands leave nation and stock byte-identical"): return
	var by_holder: Dictionary = orders.authorize_nation_ransom(keeper, "n1", true)
	if not _r3_check(bool(by_holder.ok) and int(nation.ransom_data.policy.authorized_by) == keeper, "the appointed 贖務官 authorizes: " + str(by_holder)): return
	var repeat_holder: Dictionary = orders.authorize_nation_ransom(keeper, "n1", true)
	if not _r3_check(str(repeat_holder.code) == "NO_CHANGE", "the same authorizer re-sending is no change: " + str(repeat_holder)): return
	var repriced: Dictionary = orders.set_nation_ransom_policy(keeper, "n1", 25, 60, 10)
	if not _r3_check(bool(repriced.ok) and not bool(nation.ransom_data.policy.authorized) and not nation.ransom_data.policy.has("authorized_by"), "changing ceilings revokes the authorization"): return
	if not _r3_check(data.site.stockpiles[key].cargo == coin_before, "no coin or item moved across authorization and revocation"): return
	print("SITE R4B2 AUTHORIZATION PASS: lab-level 贖務官 binds the national treasury, sets ceilings, authorizes and revokes payer-side spending; head acts only while the seat is vacant; appointee exercises the duty; non-deciders and byte-identical refusals hold; dialog calls the same commands; ceilings changes revoke authorization; no coin moved, no release.")
	quit(0)
