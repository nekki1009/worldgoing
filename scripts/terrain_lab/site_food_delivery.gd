extends RefCounted
## Source projection and atomic food movement for the original Controller job.
## No clock, people, permanent inventory, or second ground-container framework.
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Sustain = preload("res://scripts/terrain_lab/site_sustain.gd")
var controller: Variant

func init(owner: Variant) -> void:
	controller = owner

func _person(identity: int) -> Dictionary:
	return controller.person_actions._person(identity)

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
			stock = entry.inventory
			opened = entry.sustain
			version_owner = entry
			version_field = "revision"
			origin = sender.cell
			original_owner = team
		"depot", "ground":
			# A real commanded receiver does the carrying at the actual stock cell.
			if not _command_receiver(receiver):
				return {}
			sender = receiver
			if kind == "depot":
				stock = data.site.inventory
				version_owner = data.site.depot_items
				origin = data.cell_from_index(int(data.site.depot_cell))
				original_owner = data
			else:
				var container: Dictionary = data.site.ground_loot.get(str(specification.get("container_id", "")), {})
				if container.is_empty():
					return {}
				stock = container.cargo
				opened = container
				version_owner = container
				origin = data.cell_from_index(int(container.cell))
				original_owner = data
		_:
			return {}
	if receiver.is_empty() or not controller._delivery_person_ready(sender) or not controller._delivery_person_ready(receiver):
		return {}
	if kind in ["person", "team"]:
		if int(sender.person_id) == int(receiver.person_id) or int(sender.faction) != int(receiver.faction) or not _adjacent(sender.cell, receiver.cell):
			return {}
	elif not _adjacent(receiver.cell, origin):
		return {}
	return {"kind": kind, "sender": sender, "stock": stock, "opened": opened,
		"version_owner": version_owner, "version_field": version_field, "origin": origin, "owner": original_owner}

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
	if not destination.is_empty() and is_same(resolved.stock, destination.inventory):
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
	var held := 0.0 if destination.is_empty() else Sustain.rations(destination.sustain, destination.inventory)
	if held + quantity > controller.team_food_capacity(team) + 0.000000001:
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
		"quantity": quantity, "left": 2.0 + 0.2 * quantity, "pending": false}})

func valid(team: TerrainArmy, entry: Dictionary) -> bool:
	var job: Dictionary = entry.delivery
	if job.is_empty() or int(job.requester_id) != controller.lab.controlled_person_id() or not _member(team, int(job.representative_id)) or not controller._team_stopped(team):
		return false
	var receiver := _person(int(job.representative_id))
	var resolved := source(job.source_spec, receiver)
	if resolved.is_empty():
		return false
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
	return int(entry.revision) < 2147483646 and Runtime.can_pay(resolved.stock, job.items) and Sustain.rations(entry.sustain, entry.inventory) + float(job.quantity) <= controller.team_food_capacity(team) + 0.000000001

func commit(team: TerrainArmy, entry: Dictionary) -> Dictionary:
	if not valid(team, entry):
		return Runtime.fail("STALE_SOURCE", "原人物、來源或容量變更，當批未扣物")
	var job: Dictionary = entry.delivery
	var resolved := source(job.source_spec, _person(int(job.representative_id)))
	var state: Dictionary = entry.sustain.duplicate(true)
	var stock: Dictionary = entry.inventory.duplicate(true)
	Runtime.add_items(stock, job.items)
	state.open_rations = float(state.open_rations) + float(job.open_amount)
	var supplied := Sustain.resupply(state, controller._team_members(team), stock)
	if not supplied.ok:
		return supplied
	# All possible failures preceded this original synchronous commit.
	Runtime.add_items(resolved.stock, job.items, -1)
	if float(job.open_amount) > 0.0:
		resolved.opened.open_rations = maxf(0.0, float(resolved.opened.open_rations) - float(job.open_amount))
	resolved.version_owner[resolved.version_field] = int(resolved.version_owner[resolved.version_field]) + 1
	entry.inventory.clear()
	entry.inventory.merge(stock)
	entry.sustain.clear()
	entry.sustain.merge(state)
	entry.revision = int(entry.revision) + 1
	entry.delivery = {}
	if str(resolved.kind) == "ground":
		Runtime.clear_empty_ground_loot(controller.lab.terrain, str(job.source_spec.container_id))
	return Runtime.ok("已實際交付；原餐份與缺餐信用守恆", {"consumed_rations": supplied.consumed_rations})

func drop_excess(team: TerrainArmy) -> Dictionary:
	var entry: Dictionary = controller._supply_entry(team)
	if entry.is_empty():
		return Runtime.ok()
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
		if not team.is_member(index) or team.moving_to[index] != TerrainArmy.INVALID_CELL:
			continue
		var person := _person(team.combat_identity(index))
		if person.is_empty() or controller._pending_deaths.has(int(person.person_id)) or not controller.lab.terrain.is_walkable(person.cell):
			continue
		bearer = person
		if float(person.hp) > 0.0:
			break
	if bearer.is_empty() and is_instance_valid(team.player_member) and not team.player_member.is_moving() and not controller._pending_deaths.has(team.player_member.person_id):
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
		entry.revision = int(entry.revision) + 1
	return result
