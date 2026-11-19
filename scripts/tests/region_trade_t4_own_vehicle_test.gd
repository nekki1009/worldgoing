extends SceneTree
## Trade T4 TR-40 (the player's side): the player trades from his own team's stopped cart. As region_trade_t2_vehicle_test,
## a cadre leaves as captain of 乙國's team with a parked cart (grain 30); the player's own team also has a parked cart
## (iron 2) beside him. Checks:
## - the controller finds the player's own cart (he commands its team and stands beside it); a cadre of another team, or
##   the player standing away from it, cannot use it; a cart in motion is refused; a ship's hold never trades (TR-41);
## - the player offers 1 iron from his cart's hold for 2 grain from the cadre team's cart; the team accepts and the
##   delivery moves goods between the two holds exactly once, both holds' versions rise once, his own cargo is untouched.
## Output: REGION_TRADE_T4_OWN_VEHICLE_PASS on success; quit(1) on any failure or the deadline.

const SITE := "res://scenes/terrain_lab/TerrainLab.tscn"
const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
const START := Vector2i(1170, 13252)

var checks := 0
var _finished := false

func _initialize() -> void:
	create_timer(300.0).timeout.connect(func() -> void: _fail("300-second deadline"))
	_run.call_deferred()

func _fail(message: String, detail: Variant = null) -> void:
	if _finished: return
	_finished = true
	printerr("REGION_TRADE_T4_OWN_VEHICLE_FAIL: ", message, " ", str(detail))
	quit(1)

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("REGION_TRADE_T4_OWN_VEHICLE OK ", checks, ": ", message)
		return true
	_fail(message, detail)
	return false

func _move(lab: TerrainLab, person: int, cell: Vector2i) -> bool:
	return lab.crowd_site.set_soldier_fields(int(lab.crowd_site._index_by_id[person]), {"px": float(cell.x) + 0.5, "py": float(cell.y) + 0.5})

func _run() -> void:
	if not _check(RegionEntry.request_new_world(START, {}, "本隊車輛交易測試", "", RegionData.DEFAULT_MANIFEST, {"mode": "found", "name": "甲國"}), "a new world with a founded faction is requested"): return
	change_scene_to_file(SITE)
	var lab: TerrainLab = null
	for _frame: int in range(900):
		await process_frame
		if _finished: return
		var scene := current_scene as TerrainLab
		if scene != null and scene.site_controller != null and scene.site_controller.region_slot != null and scene.site_controller._boot_request.is_empty() and scene.crowd_site != null and scene.crowd_site.active:
			lab = scene
			break
	if not _check(lab != null, "the new world opens"): return
	for _frame: int in range(240): await process_frame
	var controller: SiteController = lab.site_controller
	var actions: SitePersonActions = controller.person_actions
	var player := int(lab.controlled_person_id())
	var me: Dictionary = actions._person(player)
	var mine := controller.diplomacy_head_faction()
	# A cadre leaves as captain of his own 甲國 team; the team gets a stopped cart (a data record of the trade endpoint's
	# shape; the native convoy is not needed for a parked cart's cargo).
	var cadre := -1
	for person: Variant in lab.crowd_site._team_by_id(int(me.owner.team_id)).person_ids:
		if int(person) != player and cadre < 0: cadre = int(person)
	# He founds 乙國 (a team of the same faction would share its native slot), which makes a truce with 甲國.
	var slot: RegionSaveSlot = controller.region_slot
	var cadre_ref: Dictionary = preload("res://scripts/terrain_lab/site_join_faction.gd")._world_ref(controller, cadre)
	var prepared: Dictionary = slot.prepare_faction_creation(lab.terrain, int(slot.control.faction_registry.get("revision", 0)), [], {"name": "乙國", "kind": "npc", "leader_ref": cadre_ref, "founded_at": float(slot.control.logical_game_seconds)})
	if not _check(prepared.ok, "乙國 is prepared", prepared): return
	var detached: Dictionary = lab.crowd_site.detach_to_new_team(cadre, int(prepared.faction_id))
	if not _check(detached.ok, "a cadre leaves as captain of his own team", detached): return
	var captured: Dictionary = controller.capture_region_checkpoint("region_checkpoint", true)
	if not _check(captured.ok and slot.checkpoint_region_site(lab.terrain, captured.context, captured.owners, prepared.registry, false, captured).ok, "乙國 saves"): return
	var neutral_mind := {"version": 1}
	for axis: String in preload("res://scripts/terrain_lab/person_personality.gd").AXES: neutral_mind[axis] = 50
	actions._person(cadre).body["personality"] = neutral_mind
	controller._npc_diplomacy_day = -1
	controller.npc_diplomacy_day()
	controller.settle_diplomacy()
	if not _check(controller.answer_oldest_letter(true).ok, "甲國 accepts 乙國's truce"): return
	controller.settle_diplomacy()
	var cadre_team := int(actions._person(cadre).owner.team_id)
	var cart := "9001"
	if not lab.terrain.site.has("vehicles"): lab.terrain.site["vehicles"] = {}
	lab.terrain.site.vehicles[cart] = {"id": cart, "kind": "cart", "team_id": cadre_team, "cell": lab.terrain.index(actions._person(cadre).cell + Vector2i(1, 0)),
		"facing": [1, 0], "holder": SiteRuntime.new_item_state("vehicle:" + cart), "cargo": {}, "move": {}, "operator_id": 0, "stop_pending": false, "revision": 1, "command": {}}
	for _frame: int in range(120): await process_frame
	var vehicle: Dictionary = lab.terrain.site.vehicles[cart]
	var team: Dictionary = lab.crowd_site._team_by_id(int(vehicle.team_id))
	var captain := int(lab.crowd_site.formation_state(int(team.formation)).current_person)
	if not _check(captain > 0, "the cart's team has a current commander", team): return
	var cart_cell: Vector2i = lab.terrain.cell_from_index(int(vehicle.cell))
	var captain_cell: Vector2i = actions._person(captain).cell
	if not _check(Vector2(captain_cell).distance_to(Vector2(cart_cell)) <= 2.0 or _move(lab, captain, cart_cell + Vector2i(0, 1)), "the commander stands beside the cart"): return
	for _frame: int in range(10): await process_frame
	captain_cell = actions._person(captain).cell
	if not _check(_move(lab, player, captain_cell + Vector2i(1, 0)), "the player walks up to the commander"): return
	for _frame: int in range(10): await process_frame
	vehicle.cargo["grain"] = 30
	me = actions._person(player)
	me.cargo.clear()
	me.cargo["iron"] = 2
	var neutral := {"version": 1}
	for axis: String in preload("res://scripts/terrain_lab/person_personality.gd").AXES: neutral[axis] = 50
	actions._person(captain).body["personality"] = neutral
	if not _check(controller.trade_source_of(captain) == "vehicle:" + cart, "the commander beside the cart trades for it", [controller.trade_source_of(captain), actions._person(captain).cell, cart_cell]): return
	var other := -1
	for person: Variant in team.person_ids:
		if int(person) != captain and other < 0: other = int(person)
	var refused: Dictionary = controller.trade_propose_vehicle(other, cart, {"iron": 1}, {"grain": 2})
	if not _check(not refused.ok, "a team member who is not the commander cannot trade the cart", refused): return
	# The player's own team's parked cart, beside him, with 2 iron in its hold.
	var own_cart := "9002"
	var own_team := int(me.owner.team_id)
	var player_cell: Vector2i = actions._person(player).cell
	lab.terrain.site.vehicles[own_cart] = {"id": own_cart, "kind": "cart", "team_id": own_team, "cell": lab.terrain.index(player_cell + Vector2i(0, 1)),
		"facing": [1, 0], "holder": SiteRuntime.new_item_state("vehicle:" + own_cart), "cargo": {"iron": 2}, "move": {}, "operator_id": 0, "stop_pending": false, "revision": 1, "command": {}}
	for _frame: int in range(10): await process_frame
	var own_vehicle: Dictionary = lab.terrain.site.vehicles[own_cart]
	if not _check(controller.own_trade_vehicle() == "vehicle:" + own_cart, "the player's own cart beside him is found", [controller.own_trade_vehicle(), actions._person(player).cell, player_cell]): return
	var session: Variant = controller._trade()
	var foreign: Dictionary = session.player_side(captain, "vehicle:" + own_cart)
	if not _check(not foreign.ok and str(foreign.code) == "NO_AUTHORITY", "a commander of another team cannot trade from the player's cart", foreign): return
	# TR-41: a ship's hold never trades directly (goods are unloaded ashore first).
	lab.terrain.site.vehicles["9003"] = {"id": "9003", "kind": "ship", "team_id": own_team, "cell": lab.terrain.index(player_cell + Vector2i(1, 1)), "cargo": {"iron": 1}}
	var ship_trade: Dictionary = session.player_side(player, "vehicle:9003")
	lab.terrain.site.vehicles.erase("9003")
	if not _check(not ship_trade.ok and str(ship_trade.code) == "NO_TARGET", "a ship's hold never trades directly (TR-41)", ship_trade): return
	# In motion: refused.
	own_vehicle["move"] = {"pending": true}
	var moving: Dictionary = controller.trade_propose_vehicle(captain, cart, {"iron": 1}, {"grain": 2}, true)
	own_vehicle["move"] = {}
	if not _check(not moving.ok and str(moving.code) == "NO_TARGET", "a cart in motion is refused (the trade never falls back to his own cargo)", moving): return
	var cargo_before := JSON.stringify(me.cargo, "", true)
	var versions := [int(me.holder.version), int(vehicle.holder.version), int(own_vehicle.holder.version)]
	var offer: Dictionary = controller.trade_propose_vehicle(captain, cart, {"iron": 1}, {"grain": 2}, true)
	if not _check(offer.ok and offer.decision == "ACCEPT" and controller.trade_accept(str(offer.offer_id)).ok, "the team accepts 1 iron from the player's cart for 2 grain and the delivery starts", offer): return
	var done := false
	for _frame: int in range(1200):
		await process_frame
		if not actions.is_busy(player):
			done = true
			break
	if not _check(done, "the delivery ends"): return
	if not _check(int(own_vehicle.cargo.get("iron", 0)) == 1 and int(own_vehicle.cargo.get("grain", 0)) == 2 and int(vehicle.cargo.get("grain", 0)) == 28 and int(vehicle.cargo.get("iron", 0)) == 1,
		"the goods moved once between the two carts' holds", [own_vehicle.cargo, vehicle.cargo]): return
	if not _check(JSON.stringify(me.cargo, "", true) == cargo_before and int(me.holder.version) == versions[0], "the player's own cargo is untouched"): return
	if not _check(int(vehicle.holder.version) == versions[1] + 1 and int(own_vehicle.holder.version) == versions[2] + 1, "each hold's version rose once"): return
	# Standing away from his cart, he cannot use it.
	if not _check(_move(lab, player, player_cell + Vector2i(6, 6)), "the player walks away from his cart"): return
	for _frame: int in range(20): await process_frame
	var away: Dictionary = session.player_side(player, "vehicle:" + own_cart)
	if not _check(not away.ok and str(away.code) == "TOO_FAR" and controller.own_trade_vehicle() == "", "away from his cart he cannot trade from it", away): return
	_finished = true
	print("REGION_TRADE_T4_OWN_VEHICLE_PASS: ", checks, " checks; the player's own cart hold trades directly, commander only, beside it, not in motion")
	quit(0)
