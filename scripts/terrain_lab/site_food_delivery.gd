extends RefCounted
## Source projection and atomic food movement for the original Controller job.
## No clock, people, permanent inventory, or second ground-container framework.
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Sustain = preload("res://scripts/terrain_lab/site_sustain.gd")
const Ship = preload("res://scripts/terrain_lab/site_vehicle_ship_definitions.gd")
## The Site itself owns its Depot and ground-loot stock. A live job lives inside
## that Site's own state, so naming the owning TerrainData there would make the Site
## hold itself (a container cycle that is never released). Its identity is already
## proved by the SAME stock and version holders; the owner is this fixed name.
const SITE_OWNER := "site"
var controller: Variant

func init(owner: Variant) -> void:
	controller = owner

func _person(identity: int) -> Dictionary:
	return controller._supply_person(identity)

func _member(team: TerrainArmy, identity: int) -> bool:
	var index := team.index_for_identity(identity)
	return index >= 0 and (index == TerrainArmy.PLAYER_MEMBER or team.is_member(index))

func _team(identity: int) -> TerrainArmy:
	for team: TerrainArmy in controller.lab.combat_armies:
		if team.combat_enabled and team.team_id == identity:
			return team
	return null

func _adjacent(first: Vector2i, second: Vector2i) -> bool:
	var offset := second - first
	return absi(offset.x) + absi(offset.y) == 1 and controller.lab.terrain.can_step(first, second)

func _command_receiver(receiver: Dictionary) -> bool:
	if receiver.is_empty():
		return false
	if int(receiver.person_id) == controller.lab.controlled_person_id():
		return true
	# Joined Actors remain their actual Actor, not an invented Army row.
	for team: TerrainArmy in controller.lab.combat_armies:
		if team.combat_enabled and _member(team, int(receiver.person_id)):
			return team.command_eligible(team.current_commander) and team.combat_identity(team.current_commander) == controller.lab.controlled_person_id()
	return false

func source(specification: Dictionary, receiver: Dictionary) -> Dictionary:
	var data: TerrainData = controller.lab.terrain
	var kind := str(specification.get("kind", "person"))
	var sender := _person(controller.lab.controlled_person_id())
	var stock: Dictionary = {}
	var opened: Dictionary = {}
	var version_owner: Dictionary = {}
	var version_field := "version"
	var origin := Vector2i.ZERO
	var original_owner: Variant = null
	var source_ship := ""
	match kind:
		"person":
			if sender.is_empty():
				return {}
			stock = sender.cargo
			opened = data.site.get("person_supply", {}).get(str(sender.person_id), {})
			version_owner = sender.holder
			origin = sender.cell
			original_owner = sender.owner
		"team":
			var team := _team(int(specification.get("team_id", -1)))
			sender = _person(int(specification.get("representative_id", -1)))
			if team == null or sender.is_empty() or not _member(team, int(sender.person_id)) or not controller._team_stopped(team):
				return {}
			var requester := team.index_for_identity(controller.lab.controlled_person_id())
			if requester != team.current_commander or not team.command_eligible(requester):
				return {}
			var entry: Dictionary = controller._supply_entry(team)
			if entry.is_empty():
				return {}
			if int(entry.version) == 3 and not controller._supply_locations_valid(team, entry.locations): return {}
			var endpoint: Dictionary = controller._team_food_endpoint(team, int(sender.person_id))
			if endpoint.is_empty(): return {}
			stock = endpoint.inventory
			opened = endpoint.opened
			if str(endpoint.key).begins_with("vehicle:"): source_ship = str(endpoint.key).trim_prefix("vehicle:")
			version_owner = entry
			version_field = "revision"
			origin = sender.cell
			original_owner = team
		"vehicle":
			var vehicle: Dictionary = data.site.get("vehicles", {}).get(str(specification.get("vehicle_id", "")), {})
			if not controller.vehicles.is_ship(vehicle) or not vehicle.move.is_empty() or not controller.vehicles.ship_job(str(vehicle.id)).is_empty(): return {}
			var team := _team(int(vehicle.team_id))
			if team == null or not controller.vehicles._authorized(team, controller.lab.controlled_person_id(), 0): return {}
			if not _command_receiver(receiver): return {}
			sender = receiver
			stock = vehicle.cargo
			version_owner = vehicle.holder
			original_owner = vehicle
			origin = receiver.cell
			source_ship = str(vehicle.id)
		"depot", "ground":
			# A real commanded receiver does the carrying at the actual stock cell.
			if not _command_receiver(receiver):
				return {}
			sender = receiver
			if kind == "depot":
				stock = data.site.inventory
				version_owner = data.site.depot_items
				origin = data.cell_from_index(int(data.site.depot_cell))
				original_owner = SITE_OWNER
			else:
				var container: Dictionary = data.site.ground_loot.get(str(specification.get("container_id", "")), {})
				if container.is_empty():
					return {}
				stock = container.cargo
				opened = container
				version_owner = container
				source_ship = str(container.get("vehicle_id", ""))
				origin = data.cell_from_index(int(container.cell)) if source_ship.is_empty() else receiver.cell
				original_owner = SITE_OWNER
		_:
			return {}
	if receiver.is_empty() or not controller._delivery_person_ready(sender) or not controller._delivery_person_ready(receiver):
		return {}
	var sender_ship: Dictionary = controller.vehicles.ship_for_person(int(sender.person_id))
	var receiver_ship: Dictionary = controller.vehicles.ship_for_person(int(receiver.person_id))
	if kind in ["person", "team"] and not sender_ship.is_empty(): source_ship = str(sender_ship.id)
	if kind in ["person", "team"] and (int(sender.person_id) == int(receiver.person_id) or int(sender.faction) != int(receiver.faction)):
		return {}
	if not source_ship.is_empty() or not receiver_ship.is_empty():
		var receiving := str(receiver_ship.get("id", ""))
		if not source_ship.is_empty() and not receiving.is_empty():
			if source_ship != receiving: return {} # No first-version ship-to-ship food transfer.
		elif not source_ship.is_empty():
			var vehicle: Dictionary = data.site.vehicles.get(source_ship, {})
			if not controller.vehicles.ship_supply_contact(vehicle, receiver.cell): return {}
		elif not controller.vehicles.ship_supply_contact(receiver_ship, sender.cell if kind in ["person", "team"] else origin): return {}
	elif kind in ["person", "team"]:
		if int(sender.person_id) == int(receiver.person_id) or int(sender.faction) != int(receiver.faction) or not _adjacent(sender.cell, receiver.cell):
			return {}
	elif not _adjacent(receiver.cell, origin):
		return {}
	return {"kind": kind, "sender": sender, "stock": stock, "opened": opened,
		"version_owner": version_owner, "version_field": version_field, "origin": origin, "owner": original_owner, "source_ship": source_ship}

func _destination(team: TerrainArmy, receiver_id: int, entry: Dictionary) -> Dictionary:
	if entry.is_empty(): return {"inventory": {}, "opened": {"open_rations": 0.0}, "key": "", "exists": false}
	return controller._team_food_endpoint(team, receiver_id, true)

func _capacity(team: TerrainArmy, entry: Dictionary, endpoint: Dictionary, resolved: Dictionary, quantity: float) -> bool:
	var internal := not entry.is_empty() and is_same(resolved.version_owner, entry)
	var held := 0.0 if entry.is_empty() else Sustain.rations(entry.sustain, controller._supply_stock(entry))
	if held + (0.0 if internal else quantity) > controller.team_food_capacity(team) + Sustain.EPS: return false
	var target_ship := str(endpoint.key).trim_prefix("vehicle:") if str(endpoint.key).begins_with("vehicle:") else ""
	if target_ship.is_empty() or target_ship == str(resolved.source_ship): return true
	var vehicle: Dictionary = controller.lab.terrain.site.vehicles.get(target_ship, {})
	return controller.vehicles.ship_load(target_ship) + quantity <= float(controller.vehicles.capacity_of(vehicle)) + Sustain.EPS

func prepare(team: TerrainArmy, quantity: float, receiver_id: int, specification: Dictionary) -> Dictionary:
	if not is_finite(quantity) or quantity <= 0.0 or quantity > 30.0:
		return Runtime.fail("INVALID", "每批1–30日份，或來源未滿1日份的整批已拆餐份")
	var receiver := _person(receiver_id)
	if team == null or not team.combat_enabled or receiver.is_empty() or not _member(team, receiver_id) or not controller._team_stopped(team):
		return Runtime.fail("NO_TARGET", "接收者須是停止隊伍的實際自由成員")
	var kind := str(specification.get("kind", "person"))
	if kind == "team":
		var supplying := _team(int(specification.get("team_id", -1)))
		if supplying == null:
			return Runtime.fail("NO_TARGET", "原供糧隊伍不存在")
		var requester := supplying.index_for_identity(controller.lab.controlled_person_id())
		if requester != supplying.current_commander or not supplying.command_eligible(requester):
			return Runtime.fail("NO_AUTHORITY", "只有原供糧隊當前合格指揮者可調用其共有糧")
	elif kind in ["depot", "ground"] and not _command_receiver(receiver):
		return Runtime.fail("NO_AUTHORITY", "须由本人或本人有權指派的原代表實際搬取")
	var resolved := source(specification, receiver)
	if resolved.is_empty():
		return Runtime.fail("UNREACHABLE", "來源權限／代表／實際相鄰可達位置不合；未遠端扣物")
	if not Sustain._number(resolved.opened.get("open_rations", 0.0), 0.0, 1000000.0) or not Runtime._resource_stack(resolved.stock):
		return Runtime.fail("INVALID_SUSTAIN", "原口糧／開封份資料無效")
	if int(resolved.version_owner[resolved.version_field]) >= 2147483646:
		return Runtime.fail("STALE_SOURCE", "原物資版本序號已達上限")
	if int(receiver.faction) != team.faction_id:
		return Runtime.fail("NO_AUTHORITY")
	var destination: Dictionary = controller._supply_entry(team)
	var endpoint := _destination(team, receiver_id, destination)
	if endpoint.is_empty(): return Runtime.fail("UNREACHABLE", "接收者沒有合法的本船或岸格供糧位置")
	if not destination.is_empty() and int(destination.version) == 3 and not controller._supply_locations_valid(team, destination.locations): return Runtime.fail("INVALID_SUSTAIN")
	if not destination.is_empty() and is_same(resolved.stock, endpoint.inventory):
		return Runtime.fail("INVALID", "來源與接收方是同一份共有庫存")
	if not destination.is_empty() and int(destination.revision) >= 2147483646:
		return Runtime.fail("STALE_SOURCE", "接收物資版本序號已達上限")
	for person: Dictionary in [resolved.sender, receiver]:
		if int(person.person_id) != controller.lab.controlled_person_id() and PersonFatigue.needs_work_rest(float(controller.person_actions._body_get(person, "fatigue")), bool(controller.person_actions._body_get(person, "work_resting"))):
			return Runtime.fail("BUSY", "搬運代表疲勞輪休中；降至50才接新作業")
	var opened := float(resolved.opened.get("open_rations", 0.0))
	var items := {}
	var take_open := 0.0
	if quantity < 1.0:
		if opened >= 1.0 or absf(quantity - opened) > 0.000000001:
			return Runtime.fail("INVALID", "未滿1日份只能搬取來源整批已拆餐份")
		take_open = opened
	elif quantity != floorf(quantity):
		return Runtime.fail("INVALID", "完整日份須為整數，零頭另選原已拆餐份")
	else:
		# Opened stock can accumulate through actual transfers; consume it first.
		# Use an integer amount of that pool, then whole original food items.
		take_open = minf(quantity, floorf(opened))
		var left := int(quantity - take_open)
		for food: String in Sustain.FOODS:
			var taken := mini(left, int(resolved.stock.get(food, 0)))
			if taken > 0:
				items[food] = taken
			left -= taken
		if left > 0:
			return Runtime.fail("MATERIALS", "指定原庫存沒有足夠完整日份")
	if not _capacity(team, destination, endpoint, resolved, quantity):
		return Runtime.fail("STORAGE_FULL", "原隊伍實際3／6日份載量不足")
	var sender: Dictionary = resolved.sender
	var food := {}
	for food_name: String in Sustain.FOODS:
		food[food_name] = int(resolved.stock.get(food_name, 0))
	return Runtime.ok("已核對實際來源", {"job": {"player_id": int(sender.person_id), "representative_id": receiver_id,
		"requester_id": controller.lab.controlled_person_id(), "source_spec": specification.duplicate(true),
		"source_cell": sender.cell, "target_cell": receiver.cell, "player_hit": int(sender.hit), "target_hit": int(receiver.hit),
		"source_cargo": resolved.stock, "source_holder": resolved.version_owner, "source_body": sender.body, "source_owner": resolved.owner,
		"receiver_body": receiver.body, "receiver_owner": receiver.owner, "source_open": resolved.opened,
		"source_version": int(resolved.version_owner[resolved.version_field]), "source_origin": resolved.origin,
		"source_food": food, "source_open_amount": opened, "items": items, "open_amount": take_open,
		"target_location": str(endpoint.key), "quantity": quantity, "left": 2.0 + 0.2 * quantity, "pending": false}})

func valid(team: TerrainArmy, entry: Dictionary) -> bool:
	var job: Dictionary = entry.delivery
	if job.is_empty() or int(job.requester_id) != controller.lab.controlled_person_id() or not _member(team, int(job.representative_id)) or not controller._team_stopped(team):
		return false
	var receiver := _person(int(job.representative_id))
	var resolved := source(job.source_spec, receiver)
	if resolved.is_empty():
		return false
	var endpoint := _destination(team, int(job.representative_id), entry)
	if endpoint.is_empty() or str(endpoint.key) != str(job.get("target_location", "")): return false
	if int(entry.version) == 3 and not controller._supply_locations_valid(team, entry.locations): return false
	var sender: Dictionary = resolved.sender
	if int(sender.person_id) != int(job.player_id) or sender.cell != job.source_cell or receiver.cell != job.target_cell or resolved.origin != job.source_origin or int(sender.hit) != int(job.player_hit) or int(receiver.hit) != int(job.target_hit):
		return false
	if not is_same(sender.body, job.source_body) or not is_same(receiver.body, job.receiver_body) or receiver.owner != job.receiver_owner or resolved.owner != job.source_owner or not is_same(resolved.stock, job.source_cargo) or not is_same(resolved.version_owner, job.source_holder):
		return false
	# Empty optional opened pools are values, not a stored owner reference.
	if not resolved.opened.is_empty() and not is_same(resolved.opened, job.source_open):
		return false
	if int(resolved.version_owner[resolved.version_field]) != int(job.source_version) or float(resolved.opened.get("open_rations", 0.0)) != float(job.source_open_amount):
		return false
	for food: String in Sustain.FOODS:
		if int(resolved.stock.get(food, 0)) != int(job.source_food[food]):
			return false
	return int(entry.revision) < 2147483646 and Runtime.can_pay(resolved.stock, job.items) and _capacity(team, entry, endpoint, resolved, float(job.quantity))

func commit(team: TerrainArmy, entry: Dictionary) -> Dictionary:
	var prepared: Dictionary = prepare_completion(team, entry)
	if not prepared.ok: return prepared
	if not validate_prepared_completion(prepared): return Runtime.fail("STALE_SOURCE", "原人物、來源或容量變更，當批未扣物")
	return publish_prepared_completion(prepared)

func drop_excess(team: TerrainArmy) -> Dictionary:
	var entry: Dictionary = controller._supply_entry(team)
	if entry.is_empty():
		return Runtime.ok()
	if int(entry.version) == 3: return _drop_location_excess(team, entry)
	var held := Sustain.rations(entry.sustain, entry.inventory)
	if held <= 0.000000001:
		return Runtime.ok()
	var capacity: float = controller.team_food_capacity(team)
	# Actual defeat is not necessarily morale-rout: all KO/dead/captive bodies
	# have zero carrying capacity even when the morale event did not reach 20.
	if not bool(entry.sustain.routed) and team.combat_order != TerrainArmy.CombatOrder.RETREAT and capacity > 0.0:
		return Runtime.ok()
	var excess: float = held - capacity
	if excess <= 0.000000001:
		return Runtime.ok()
	# The last carrier may be dead: original bodies/cells still own the landing
	# position. Wait for committed movement/down settlement, never use a centroid.
	var bearer := {}
	for index: int in range(team.combat_units.size()):
		if not team.is_member(index) or bool(team.combat_hot_get(index, &"site_exited", false)) or team.moving_to[index] != TerrainArmy.INVALID_CELL:
			continue
		var person := _person(team.combat_identity(index))
		if person.is_empty() or controller._pending_deaths.has(int(person.person_id)) or not controller.lab.terrain.is_walkable(person.cell):
			continue
		bearer = person
		if float(person.hp) > 0.0:
			break
	if bearer.is_empty() and is_instance_valid(team.player_member) and not team.player_member.site_exited and not team.player_member.is_moving() and not controller._pending_deaths.has(team.player_member.person_id):
		bearer = _person(team.player_member.person_id)
	if bearer.is_empty():
		return Runtime.fail("BUSY", "超額共有口糧保留原處，等待原人物步進／倒地落點收束")
	var items := {}
	var remaining := excess
	for food: String in Sustain.FOODS:
		var taken := mini(floori(remaining), int(entry.inventory.get(food, 0)))
		if taken > 0:
			items[food] = taken
		remaining -= taken
	var opened := minf(remaining, float(entry.sustain.open_rations))
	if absf(remaining - opened) > 0.000000001:
		return Runtime.fail("INVALID_SUSTAIN", "超額口糧無法對應原整數存糧與已拆份")
	var result := Runtime.leave_ground_loot(controller.lab.terrain, bearer.holder, entry.inventory,
		int(bearer.person_id), bearer.cell, "cargo", items, [], int(bearer.holder.version), entry.sustain, opened)
	if result.ok:
		entry["revision"] = int(entry.revision) + 1
	return result

func _drop_location_excess(team: TerrainArmy, entry: Dictionary) -> Dictionary:
	if not controller._supply_locations_valid(team, entry.locations): return Runtime.fail("INVALID_SUSTAIN")
	var held := Sustain.rations(entry.sustain, entry.locations)
	var capacity: float = controller.team_food_capacity(team)
	if not bool(entry.sustain.routed) and team.combat_order != TerrainArmy.CombatOrder.RETREAT and capacity > 0.0: return Runtime.ok()
	var remaining := held - capacity
	if remaining <= Sustain.EPS: return Runtime.ok()
	if int(entry.revision) >= 2147483646: return Runtime.fail("STALE_SOURCE")
	var plans: Array[Dictionary] = []
	var keys: Array = entry.locations.keys()
	keys.sort()
	for key: String in keys:
		var stock: Dictionary = entry.locations[key]
		var items := {}
		var wanted := remaining
		for food: String in Sustain.FOODS:
			var taken := mini(floori(wanted), int(stock.inventory.get(food, 0)))
			if taken > 0: items[food] = taken
			wanted -= taken
		var opened := minf(wanted, float(stock.open_rations))
		var quantity := float(Runtime.inventory_size(items)) + opened
		if quantity <= Sustain.EPS: continue
		var bearer := {}
		var ship_location := {}
		if key.begins_with("vehicle:"):
			var vehicle: Dictionary = controller.lab.terrain.site.vehicles[key.trim_prefix("vehicle:")]
			for person: Dictionary in controller.vehicles.ship_people(vehicle, false):
				if person.owner != team or controller._pending_deaths.has(int(person.person_id)): continue
				bearer = person
				ship_location = controller.vehicles.ship_death_location(int(person.person_id))
				break
			if bearer.is_empty():
				# Food remains physically on this boat after its last carrier dies.
				# Its original vehicle holder can drop it without inventing a person.
				for index in range(team.combat_units.size()):
					if not team.is_member(index): continue
					var identity := team.combat_identity(index)
					bearer = {"person_id": identity, "holder": vehicle.holder, "cell": controller.lab.terrain.cell_from_index(int(vehicle.cell))}
					var local := Ship.local_position(str(vehicle.ship_type), Ship.HELM_BERTH)
					ship_location = {"vehicle_id": str(vehicle.id), "local_position": [local.x, local.y]}
					break
		else:
			var shore: Vector2i = controller.lab.terrain.cell_from_index(int(key.trim_prefix("shore:")))
			for index in range(team.combat_units.size()):
				var person := _person(team.combat_identity(index))
				if person.is_empty() or controller.vehicles.is_embarked(int(person.person_id)) or bool(person.moving) or controller._pending_deaths.has(int(person.person_id)) or not controller._supply_shore_contact(person.cell, shore): continue
				bearer = person
				break
			if bearer.is_empty() and is_instance_valid(team.player_member):
				var person := _person(team.player_member.person_id)
				if not person.is_empty() and not bool(person.moving) and controller._supply_shore_contact(person.cell, shore): bearer = person
		if bearer.is_empty(): return Runtime.fail("BUSY", "超額口糧保留原位置，等原人物可在現場處理")
		var cell: Vector2i = bearer.cell if not ship_location.is_empty() else controller.lab.terrain.cell_from_index(int(key.trim_prefix("shore:")))
		var checked := Runtime.leave_ground_loot(controller.lab.terrain, bearer.holder, stock.inventory, int(bearer.person_id), cell, "cargo", items, [], int(bearer.holder.version), stock, opened, true, ship_location)
		if not checked.ok: return checked
		plans.append({"bearer": bearer, "stock": stock, "cell": cell, "items": items, "opened": opened, "ship_location": ship_location})
		remaining -= quantity
		if remaining <= Sustain.EPS: break
	if remaining > Sustain.EPS: return Runtime.fail("INVALID_SUSTAIN", "超額口糧無法對應原整數糧與開封份")
	var next := int(controller.lab.terrain.site.next_loot)
	if next + plans.size() > 2147483647: return Runtime.fail("INVALID", "遺物序號已用盡")
	for offset in range(plans.size()):
		if controller.lab.terrain.site.ground_loot.has(str(next + offset)): return Runtime.fail("STALE_SOURCE")
	var result := Runtime.ok()
	for plan: Dictionary in plans:
		var person: Dictionary = plan.bearer
		result = Runtime.leave_ground_loot(controller.lab.terrain, person.holder, plan.stock.inventory, int(person.person_id), plan.cell, "cargo", plan.items, [], int(person.holder.version), plan.stock, float(plan.opened), false, plan.ship_location)
		assert(result.ok, "Preflighted location supply drop must commit synchronously")
	entry["revision"] = int(entry.revision) + 1
	return result


func prepare_completion(team: TerrainArmy, entry: Dictionary, require_endpoint: bool = false) -> Dictionary:
	if require_endpoint and (entry.get("delivery", {}).is_empty() or not bool(entry.delivery.get("pending", false)) or float(entry.delivery.get("left", -1.0)) != 0.0): return Runtime.fail("INCOMPLETE")
	if not valid(team, entry):
		return Runtime.fail("STALE_SOURCE", "原人物、來源或容量變更，當批未扣物")
	var job: Dictionary = entry.delivery
	var resolved := source(job.source_spec, _person(int(job.representative_id)))
	var state: Dictionary = entry.sustain.duplicate(true)
	var stock: Dictionary = controller._supply_stock(entry).duplicate(true)
	var internal := int(entry.version) == 3 and is_same(resolved.version_owner, entry)
	var destination := stock
	var opened := state
	if int(entry.version) == 3:
		var target_key := str(job.target_location)
		if not stock.has(target_key): stock[target_key] = {"inventory": {}, "open_rations": 0.0}
		destination = stock[target_key].inventory
		opened = stock[target_key]
		if internal:
			for key: String in entry.locations:
				if is_same(entry.locations[key].inventory, resolved.stock):
					Runtime.add_items(stock[key].inventory, job.items, -1)
					stock[key].open_rations = maxf(0.0, float(stock[key].open_rations) - float(job.open_amount))
					break
	Runtime.add_items(destination, job.items)
	opened.open_rations = float(opened.open_rations) + float(job.open_amount)
	var members: Dictionary = controller._team_members(team)
	var context := {}
	if int(entry.version) == 3:
		if not controller._supply_locations_valid(team, stock): return Runtime.fail("INVALID_SUSTAIN")
		context["food_locations"] = controller.ship_food_locations(team, members, stock)
	var supplied := Sustain.resupply(state, members, stock, false, controller._supply_hot_reader(team, members, {}), {}, context)
	if not supplied.ok:
		return supplied
	return Runtime.ok("原交糧完成候選已核；尚未扣物", {"owner": self, "data": controller.lab.terrain, "team": team, "entry": entry, "job": job,
		"resolved": resolved, "state": state, "stock": stock, "internal": internal, "members": members, "supplied": supplied,
		"entry_revision": int(entry.revision), "entry_state": entry.sustain.duplicate(true), "entry_stock": controller._supply_stock(entry).duplicate(true),
		"job_values": job.duplicate(true), "source_version": int(resolved.version_owner[resolved.version_field]), "source_stock": resolved.stock.duplicate(true),
		"source_open": resolved.opened.duplicate(true), "require_endpoint": require_endpoint, "published": false})

func validate_prepared_completion(prepared: Dictionary) -> bool:
	if prepared.get("owner") != self or prepared.get("published", true) or not is_same(prepared.get("data"), controller.lab.terrain) or not prepared.get("team") is TerrainArmy 		or not is_same(prepared.get("entry"), controller._supply_entry(prepared.team)) or not is_same(prepared.entry.get("delivery"), prepared.get("job")) 		or not prepared.get("require_endpoint") is bool: return false
	var expected: Dictionary = prepare_completion(prepared.team, prepared.entry, bool(prepared.require_endpoint))
	if not expected.ok or prepared.size() != expected.size(): return false
	for key: String in expected:
		if not prepared.has(key): return false
	for key: String in ["entry", "job", "data"]:
		if not is_same(prepared[key], expected[key]): return false
	for key: String in ["owner", "team", "state", "stock", "internal", "members", "supplied", "entry_revision", "entry_state", "entry_stock", "job_values", "source_version", "source_stock", "source_open", "require_endpoint", "published"]:
		if prepared[key] != expected[key]: return false
	for key: String in ["stock", "opened", "version_owner"]:
		# Empty optional opened pools are original values, not stored owners.
		if key == "opened" and expected.resolved[key].is_empty():
			if not prepared.resolved[key].is_empty(): return false
		elif not is_same(prepared.resolved[key], expected.resolved[key]): return false
	for key: String in ["kind", "version_field", "origin", "owner", "source_ship"]:
		if prepared.resolved[key] != expected.resolved[key]: return false
	for key: String in ["body", "cargo", "holder"]:
		if not is_same(prepared.resolved.sender[key], expected.resolved.sender[key]): return false
	return true

func publish_prepared_completion(prepared: Dictionary) -> Dictionary:
	# Caller validates all original source/state/stock effects immediately before
	# the first food cost. This tail contains no new guard, resupply, or callback.
	assert(prepared.owner == self and not prepared.published)
	var team: TerrainArmy = prepared.team
	var entry: Dictionary = prepared.entry
	var job: Dictionary = prepared.job
	var resolved: Dictionary = prepared.resolved
	var state: Dictionary = prepared.state
	var stock: Dictionary = prepared.stock
	var internal: bool = bool(prepared.internal)
	var supplied: Dictionary = prepared.supplied
	if not internal:
		Runtime.add_items(resolved.stock, job.items, -1)
		if float(job.open_amount) > 0.0:
			resolved.opened.open_rations = maxf(0.0, float(resolved.opened.open_rations) - float(job.open_amount))
		resolved.version_owner[resolved.version_field] = int(resolved.version_owner[resolved.version_field]) + 1
	if int(entry.version) == 3:
		for key: String in stock:
			if entry.locations.has(key):
				entry.locations[key].inventory.clear()
				entry.locations[key].inventory.merge(stock[key].inventory)
				entry.locations[key].open_rations = stock[key].open_rations
			else: entry.locations[key] = stock[key]
	else:
		entry.inventory.clear()
		entry.inventory.merge(stock)
	entry.sustain.clear()
	entry.sustain.merge(state)
	entry["revision"] = int(entry.revision) + 1
	entry["delivery"] = {}
	if str(resolved.kind) == "ground":
		Runtime.clear_empty_ground_loot(controller.lab.terrain, str(job.source_spec.container_id))
	prepared["published"] = true
	return Runtime.ok("已實際交付；原餐份與缺餐信用守恆", {"consumed_rations": supplied.consumed_rations})
