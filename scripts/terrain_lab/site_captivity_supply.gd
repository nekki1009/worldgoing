extends RefCounted
## Original feeding-owner coordination only. Captivity/actions and people remain
## with their existing owners; prepared copies are never saved or advanced.

const Sustain = preload("res://scripts/terrain_lab/site_sustain.gd")
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const RANSOM_RATIONS := 100
var controller: Variant
var _prepared: Dictionary = {}

func init(owner: Variant) -> void:
	controller = owner
	_prepared.clear()

func _body(identity: int) -> Dictionary:
	var person: Dictionary = controller.lab._combat_target(identity)
	if person.is_empty():
		return {}
	if int(person.unit) >= 0:
		return person.owner.combat_units[int(person.unit)]
	return controller._actor_supply_adapter(person.owner)

func _original_team(identity: int) -> Variant:
	for team: TerrainArmy in controller.lab.combat_armies:
		var index := team.index_for_identity(identity)
		if team.combat_enabled and index >= 0 and (index == TerrainArmy.PLAYER_MEMBER or bool(team.combat_units[index].get("member", true))):
			return team
	return null

func _original_members(team: TerrainArmy) -> Dictionary:
	var result := {}
	for row: Dictionary in team.combat_units:
		if bool(row.get("member", true)):
			result[int(row.person_id)] = row
	if is_instance_valid(team.player_member):
		result[team.player_member.person_id] = controller._actor_supply_adapter(team.player_member, team.player_present)
	return result

func _all_members() -> Dictionary:
	var result := {}
	for team: TerrainArmy in controller.lab.combat_armies:
		for row: Dictionary in team.combat_units:
			result[int(row.person_id)] = row # Independent original rows remain real people.
		if is_instance_valid(team.player_member):
			result[team.player_member.person_id] = controller._actor_supply_adapter(team.player_member, team.player_present)
	for actor: TerrainTestCharacter in [controller.lab.character, controller.lab.npc]:
		if not result.has(actor.person_id):
			result[actor.person_id] = controller._actor_supply_adapter(actor)
	return result

func _states() -> Dictionary:
	var result := {}
	for id: String in controller.lab.terrain.site.get("team_supply", {}):
		var entry: Dictionary = controller.lab.terrain.site.team_supply[id]
		result["team:" + id] = {"state": entry.sustain.duplicate(true), "original": entry.sustain,
			"entry": entry, "created": false, "dirty": false}
	for id: String in controller.lab.terrain.site.get("person_supply", {}):
		var state: Dictionary = controller.lab.terrain.site.person_supply[id]
		result["person:" + id] = {"state": state.duplicate(true), "original": state,
			"entry": {}, "created": false, "dirty": false}
	return result

func _feeding_owner(identity: int, states: Dictionary) -> String:
	for key: String in states:
		if identity in Sustain._ids(states[key].state):
			return key
	return ""

func team_members(team: TerrainArmy, original: Dictionary) -> Dictionary:
	# Cohorts are the saved feeding ownership. A dead captive's relationship may
	# already be cleared, but that does not move or refund their eaten meal.
	var result := original.duplicate()
	for identity: int in result.keys():
		if not bool(result[identity].get("member", true)):
			result.erase(identity)
	var own_key := "team:%d" % team.team_id
	for key: String in controller.lab.terrain.site.get("team_supply", {}):
		var state: Dictionary = controller.lab.terrain.site.team_supply[key].sustain
		for id: int in Sustain._ids(state):
			if "team:" + key != own_key:
				result.erase(id)
			elif not result.has(id):
				var body := _body(id)
				if not body.is_empty():
					result[id] = body
	for state: Dictionary in controller.lab.terrain.site.get("person_supply", {}).values():
		for id: int in Sustain._ids(state):
			result.erase(id)
	return result

func personal_members(actor: TerrainTestCharacter) -> Dictionary:
	return personal_members_id(actor.person_id)

func personal_members_id(identity: int) -> Dictionary:
	var result := {}
	var state: Dictionary = controller.lab.terrain.site.get("person_supply", {}).get(str(identity), {})
	if not state.is_empty():
		for id: int in Sustain._ids(state):
			var body := _body(id)
			if not body.is_empty():
				result[id] = body
	return result

func _home(identity: int) -> Dictionary:
	var team: Variant = _original_team(identity)
	if team != null:
		return {"key": "team:%d" % team.team_id, "team": team}
	var person: Dictionary = controller.lab._combat_target(identity)
	if not person.is_empty() and int(person.unit) >= 0:
		var row: Dictionary = person.owner.combat_units[int(person.unit)]
		return {"key": "person:%d" % identity, "row": row} if row.get("cargo") is Dictionary else {}
	for actor: TerrainTestCharacter in [controller.lab.character, controller.lab.npc]:
		if actor.person_id == identity:
			var activity: Dictionary = controller.lab.terrain.site.manual if actor == controller.lab.character else controller.lab.terrain.site.worker
			if not activity.get("cargo") is Dictionary:
				return {}
			return {"key": "person:%d" % identity, "actor": actor}
	return {} # No original inventory owner; never invent a team or proxy person.

func _align(owner: Dictionary, at_seconds: float) -> bool:
	if not owner.entry.get("delivery", {}).is_empty():
		return false
	return controller._align_supply_clock(owner.state, at_seconds)

func _add(state: Dictionary, members: Dictionary, ids: Array) -> bool:
	var morale := float(state.morale)
	var result := Sustain.add_members(state, members, ids)
	state.morale = morale # Opting into meals is not actual roster reinforcement.
	return bool(result.ok)

func _move(identity: int, source: String, target: String, states: Dictionary, members: Dictionary, moves: Array, at_seconds: float) -> bool:
	if not _align(states[source], at_seconds) or not _align(states[target], at_seconds):
		return false
	if source == target:
		return true
	var destination: Dictionary = states[target].state
	var command := [destination.morale, destination.routed, destination.regroup_seconds]
	if not Sustain.move_members(states[source].state, states[target].state, members, [identity]).ok:
		return false
	# Feeding a captive is not merging their army. Keep the destination's own
	# morale/rout; only the original cohort's hunger and eaten credit move.
	destination.morale = command[0]
	destination.routed = command[1]
	destination.regroup_seconds = command[2]
	states[source].dirty = true
	states[target].dirty = true
	moves.append([identity, source, target])
	return true

func _ensure(home: Dictionary, states: Dictionary, members: Dictionary, moves: Array, at_seconds: float, target_id: int) -> bool:
	var key := str(home.key)
	if states.has(key):
		return _align(states[key], at_seconds)
	states[key] = {"state": Sustain.create(at_seconds), "original": {}, "entry": {}, "created": true, "dirty": true}
	# Explicit capture activates the ORIGINAL team together, like its existing
	# supply opt-in. A previously fed player member brings their meal history.
	var initial: Dictionary = _original_members(home.team) if home.has("team") else {int(home.row.person_id): home.row} if home.has("row") else {home.actor.person_id: members[home.actor.person_id]}
	var fresh: Array[int] = []
	for id: int in initial:
		if id == target_id or bool(initial[id].get("captive", false)):
			continue
		var previous := _feeding_owner(id, states)
		if previous.is_empty():
			fresh.append(id)
		elif previous.begins_with("person:"):
			if not _move(id, previous, key, states, members, moves, at_seconds):
				return false
		else:
			return false # An unrelated team's recorded ownership is not ours to steal.
	return fresh.is_empty() or _add(states[key].state, members, fresh)

func enable_team(team: TerrainArmy) -> Dictionary:
	# Explicit first opt-in uses the same original feeding transaction as
	# captivity/membership. An already eaten private meal is never a fresh meal.
	if team == null or not team.combat_enabled:
		return Runtime.fail("NO_TARGET")
	var existing: Dictionary = controller._supply_entry(team)
	if not existing.is_empty():
		return Runtime.ok("", {"entry": existing})
	var members := _all_members()
	var states := _states()
	var values: Array = []
	for owner: Dictionary in states.values():
		values.append(owner.state)
	if not Sustain.validate_owners(values, members):
		return Runtime.fail("INVALID_SUSTAIN", "原供養歷史無效，未啟用新餐份")
	var at_seconds := Runtime.now(controller.lab.terrain) * 60.0
	var key := "team:%d" % team.team_id
	var moves: Array = []
	if not _ensure({"key": key, "team": team}, states, members, moves, at_seconds, -1):
		return Runtime.fail("BUSY", "原個人供養時段尚未同步，未重設餐份")
	var original := _original_members(team)
	for captive_key: String in controller.lab.terrain.site.get("captivity", {}):
		var relation: Dictionary = controller.lab.terrain.site.captivity[captive_key]
		var captor := int(relation.captor_id)
		if not original.has(captor) or bool(original[captor].get("captive", false)):
			continue
		var captive := int(captive_key)
		var previous := _feeding_owner(captive, states)
		if previous == "person:%d" % captor and not _move(captive, previous, key, states, members, moves, at_seconds):
			return Runtime.fail("BUSY", "原受養俘虜的餐份尚未同步")
	values.clear()
	for owner: Dictionary in states.values():
		values.append(owner.state)
	if not Sustain.validate_owners(values, members):
		return Runtime.fail("INVALID_SUSTAIN", "啟用將重複原人物供養")
	_commit_states({"site": controller.lab.terrain.site, "states": states, "members": members, "moves": moves})
	return Runtime.ok("", {"entry": controller._supply_entry(team)})

func change_guard(target_id: int, captor_id: int, capturing: bool) -> Dictionary:
	# PersonActions rechecks immediately before each non-yielding commit. Keep
	# only that latest plan, not a history of cancelled/deployed person IDs.
	_prepared.clear()
	var target := _body(target_id)
	var captor := _body(captor_id)
	var site: Dictionary = controller.lab.terrain.site
	if target.is_empty() or float(target.hp) <= 0.0 or target_id == captor_id:
		return Runtime.fail("NO_TARGET", "需要原存活人物及不同拘押者")
	if capturing:
		if captor.is_empty() or float(captor.hp) <= 0.0 or bool(captor.captive) or bool(target.captive) or site.get("captivity", {}).has(str(target_id)):
			return Runtime.fail("NO_TARGET", "拘押者須自由存活，目標尚未被俘")
	elif int(site.get("captivity", {}).get(str(target_id), {}).get("captor_id", -1)) != captor_id:
		return Runtime.fail("NO_TARGET", "原拘押關係已變更")
	var destination := _home(captor_id if capturing else target_id)
	var original := _home(target_id)
	if destination.is_empty() or original.is_empty():
		return Runtime.fail("NO_SUPPLY_OWNER", "沒有可接續的原隊伍或個人行囊供養者")
	var states := _states()
	var members := _all_members()
	var values: Array = []
	for state: Dictionary in states.values():
		values.append(state.state)
	if not Sustain.validate_owners(values, members):
		return Runtime.fail("INVALID_SUSTAIN", "原供養名單重複或資料無效")
	var at_seconds := Runtime.now(controller.lab.terrain) * 60.0
	var moves: Array = []
	var source := _feeding_owner(target_id, states)
	if source.is_empty():
		if not capturing:
			return Runtime.fail("INVALID_SUSTAIN", "俘虜缺少原供养歷史，不可重設已吃餐份")
		if not _ensure(original, states, members, moves, at_seconds, target_id):
			return Runtime.fail("BUSY", "原供養時段或交糧尚未收束")
		source = str(original.key)
		if not _add(states[source].state, members, [target_id]):
			return Runtime.fail("INVALID_SUSTAIN")
		states[source].dirty = true
	if not _ensure(destination, states, members, moves, at_seconds, target_id) or not _move(target_id, source, str(destination.key), states, members, moves, at_seconds):
		return Runtime.fail("BUSY", "供養時段或交糧尚未收束；未移轉食物或人物")
	# The action owner rechecks immediately before its synchronous commit. Only
	# event-local copies are retained; failed/cancelled checks change no Site data.
	_prepared[target_id] = {"site": site, "at": at_seconds, "captor_id": captor_id, "capturing": capturing,
		"states": states, "members": members, "moves": moves}
	return Runtime.ok()

func commit_change(target_id: int, captor_id: int, capturing: bool) -> void:
	assert(_prepared.has(target_id), "Captivity supply requires a successful same-step preflight")
	var plan: Dictionary = _prepared[target_id]
	_prepared.erase(target_id)
	assert(is_same(plan.site, controller.lab.terrain.site) and plan.captor_id == captor_id and plan.capturing == capturing)
	assert(float(plan.at) == Runtime.now(controller.lab.terrain) * 60.0)
	_commit_states(plan)

func _commit_states(plan: Dictionary) -> void:
	var site: Dictionary = plan.site
	for key: String in plan.states:
		var owner: Dictionary = plan.states[key]
		if not bool(owner.dirty):
			continue
		var identity := key.get_slice(":", 1)
		if key.begins_with("team:"):
			if not site.has("team_supply"):
				site.team_supply = {}
			if bool(owner.created):
				owner.entry = {"version": 1, "sustain": owner.state, "inventory": {}, "training_order": false,
					"training_requester": -1, "revision": 0, "delivery": {}, "life_checkpoint": {}}
				site.team_supply[identity] = owner.entry
			else:
				owner.original.clear()
				owner.original.merge(owner.state)
			owner.entry.revision = int(owner.entry.revision) + 1
		else:
			if not site.has("person_supply"):
				site.person_supply = {}
			if bool(owner.created):
				site.person_supply[identity] = owner.state
			else:
				owner.original.clear()
				owner.original.merge(owner.state)
	for move: Array in plan.moves:
		var checkpoint: int = controller._life(plan.members[int(move[0])])
		var source: Dictionary = plan.states[move[1]].entry
		var destination: Dictionary = plan.states[move[2]].entry
		if not source.is_empty():
			checkpoint = int(source.life_checkpoint.get(str(move[0]), checkpoint))
			source.life_checkpoint.erase(str(move[0]))
			if int(source.training_requester) == int(move[0]):
				source.training_order = false
				source.training_requester = -1
		if not destination.is_empty():
			destination.life_checkpoint[str(move[0])] = checkpoint
	for owner: Dictionary in plan.states.values():
		if bool(owner.created) and not owner.entry.is_empty():
			for id: int in Sustain._ids(owner.state):
				if not owner.entry.life_checkpoint.has(str(id)):
					owner.entry.life_checkpoint[str(id)] = controller._life(plan.members[id])
	for addition: Array in plan.get("joined", []):
		var entry: Dictionary = plan.states[addition[1]].entry
		if not entry.is_empty():
			entry.life_checkpoint[str(addition[0])] = controller._life(plan.members[int(addition[0])])

func move_roster(source: TerrainArmy, target: TerrainArmy, ids: Array[int]) -> Dictionary:
	# Army has checked command authority/positions and calls this immediately
	# before moving the ORIGINAL rows. Build the complete feeding transaction on
	# event-local copies first; no row, stock, meal or checkpoint changes on failure.
	if source == null or target == null or source == target or ids.is_empty():
		return Runtime.fail("INVALID_MEMBERS")
	var selected := {}
	for id: int in ids:
		if selected.has(id) or source.index_for_identity(id) < 0 or target.index_for_identity(id) >= 0:
			return Runtime.fail("INVALID_MEMBERS")
		selected[id] = true
	return _change_membership_supply(source, {"key": "team:%d" % target.team_id, "team": target}, ids)

func membership_change(team: TerrainArmy, identity: int, joining: bool) -> Dictionary:
	# Called by the original row leave/join entry after its body/action guards,
	# immediately before flipping membership. Storage owner/row/cargo never move.
	if team == null:
		return Runtime.fail("INVALID_MEMBERS")
	var index := team.index_for_identity(identity)
	var personal := {}
	if index >= 0 and index != TerrainArmy.PLAYER_MEMBER:
		var row: Dictionary = team.combat_units[index]
		if bool(row.get("member", true)) == joining or not row.get("cargo") is Dictionary:
			return Runtime.fail("INVALID_MEMBERS")
		personal = {"key": "person:%d" % identity, "row": row}
	else:
		var person: Dictionary = controller.lab._combat_target(identity)
		if person.is_empty() or int(person.unit) >= 0 or (team.player_member == person.owner) == joining:
			return Runtime.fail("INVALID_MEMBERS")
		personal = {"key": "person:%d" % identity, "actor": person.owner}
	var destination := {"key": "team:%d" % team.team_id, "team": team} if joining else personal
	return _change_membership_supply(team, destination, [identity])

func _change_membership_supply(source: TerrainArmy, destination_home: Dictionary, ids: Array[int]) -> Dictionary:
	var site: Dictionary = controller.lab.terrain.site
	var members := _all_members()
	var states := _states()
	var values: Array = []
	for owner: Dictionary in states.values():
		values.append(owner.state)
	if not Sustain.validate_owners(values, members):
		return Runtime.fail("INVALID_SUSTAIN", "原供養名單重複或無法對應實際人物")
	var selected := {}
	for id: int in ids:
		if selected.has(id) or not members.has(id):
			return Runtime.fail("INVALID_MEMBERS")
		selected[id] = true
	var source_key := "team:%d" % source.team_id
	var target_key := str(destination_home.key)
	var at_seconds := Runtime.now(controller.lab.terrain) * 60.0
	for key: String in [source_key, target_key]:
		if states.has(key) and not _align(states[key], at_seconds):
			return Runtime.fail("BUSY", "原隊伍的供養時段／交糧尚未收束")
	var destinations := {}
	var followers := {}
	var has_history := states.has(source_key) or states.has(target_key)
	for id: int in ids:
		var feeding := _feeding_owner(id, states)
		if bool(members[id].get("captive", false)):
			if feeding.is_empty():
				return Runtime.fail("INVALID_SUSTAIN", "被俘原人缺少供養歷史；不能重建已吃餐份")
			destinations[id] = feeding # Military registration is not release.
		else:
			destinations[id] = target_key
		has_history = has_history or not feeding.is_empty()
	for captive_key: String in site.get("captivity", {}):
		var relation: Dictionary = site.captivity[captive_key]
		var captor := int(relation.captor_id)
		if not selected.has(captor):
			continue # A temporary guard changing teams does not own the meals.
		var captive := int(captive_key)
		if not members.has(captive) or _feeding_owner(captive, states).is_empty():
			return Runtime.fail("INVALID_SUSTAIN", "拘押者的原俘虜缺少唯一供養歷史")
		followers[captive] = true
		destinations[captive] = destinations[captor]
		has_history = true
	# Active jobs retain original owners/revisions; wait for their existing
	# completion/cancellation instead of invalidating a half-finished transaction.
	for job: Dictionary in controller.person_actions._jobs.values():
		for field: String in ["executor_id", "target_id", "guard_id", "representative_id"]:
			if destinations.has(int(job.get(field, -1))):
				return Runtime.fail("BUSY", "涉及的原人物作業尚未收束")
		if str(job.get("source_kind", "")) == "person" and destinations.has(int(job.get("source_id", -1))):
			return Runtime.fail("BUSY", "涉及的原持物人仍在作業")
	if not has_history:
		return Runtime.ok() # Two never-opted-in rosters do not invent feeding.
	var moves: Array = []
	var joined: Array = []
	if target_key in destinations.values() and not states.has(target_key):
		states[target_key] = {"state": Sustain.create(at_seconds), "original": {}, "entry": {}, "created": true, "dirty": true}
		# Enable only the existing recipient's actual free members. Previously
		# held captives/dead meal history remains at its saved feeding owner.
		var original: Dictionary = _original_members(destination_home.team) if destination_home.has("team") else {int(destination_home.row.person_id): destination_home.row} if destination_home.has("row") else {destination_home.actor.person_id: members[destination_home.actor.person_id]}
		for id: int in original:
			if selected.has(id):
				continue # The original membership batch below carries its history once.
			if bool(members[id].get("captive", false)):
				continue
			var previous := _feeding_owner(id, states)
			if previous.is_empty():
				if not _add(states[target_key].state, members, [id]):
					return Runtime.fail("INVALID_SUSTAIN")
				joined.append([id, target_key])
			elif previous.begins_with("person:"):
				if not _move(id, previous, target_key, states, members, moves, at_seconds):
					return Runtime.fail("BUSY", "接收隊員的個人供養尚未同步")
	# Free reinforcement goes first, grouped by its real prior feeding owner so
	# Sustain's original shared morale weighting is applied once per batch.
	var batches := {}
	for id: int in destinations:
		if bool(members[id].get("captive", false)) or followers.has(id):
			continue
		var previous := _feeding_owner(id, states)
		var destination := str(destinations[id])
		if previous == destination:
			continue
		if previous.is_empty():
			if not Sustain.add_members(states[destination].state, members, [id]).ok:
				return Runtime.fail("INVALID_SUSTAIN")
			states[destination].dirty = true
			joined.append([id, destination])
		else:
			if not batches.has(previous):
				batches[previous] = []
			batches[previous].append(id)
	for previous: String in batches:
		if not _align(states[previous], at_seconds) or not _align(states[target_key], at_seconds):
			return Runtime.fail("BUSY", "原人物的實際供養時段／交糧尚未同步")
		var moved := Sustain.move_members(states[previous].state, states[target_key].state, members, batches[previous])
		if not moved.ok:
			return moved
		states[previous].dirty = true
		states[target_key].dirty = true
		for id: int in batches[previous]:
			moves.append([id, previous, target_key])
	for id: int in followers:
		if not _move(id, _feeding_owner(id, states), str(destinations[id]), states, members, moves, at_seconds):
			return Runtime.fail("BUSY", "原俘虜的供養時段／交糧尚未同步")
	values.clear()
	for owner: Dictionary in states.values():
		values.append(owner.state)
	if not Sustain.validate_owners(values, members):
		return Runtime.fail("INVALID_SUSTAIN", "供養移轉將造成重複或遺失原人歷史")
	_commit_states({"site": site, "states": states, "members": members, "moves": moves, "joined": joined})
	var source_entry: Dictionary = controller._supply_entry(source)
	if not source_entry.is_empty() and selected.has(int(source_entry.training_requester)):
		source_entry.training_order = false
		source_entry.training_requester = -1
	return Runtime.ok()

func _authorized_team(identity: int) -> Variant:
	var team: Variant = _original_team(identity)
	if team == null or team.current_commander < 0 or not team.command_eligible(team.current_commander):
		return null
	var index: int = team.index_for_identity(identity)
	if index not in [team.current_commander, TerrainArmy.PLAYER_MEMBER] or not team.command_eligible(index):
		return null
	return team

func ransom_exchange_query(payer_id: int, target_id: int, representative_id: int) -> Dictionary:
	var relation: Dictionary = controller.lab.terrain.site.get("captivity", {}).get(str(target_id), {})
	var payer: Variant = _authorized_team(payer_id)
	var recipient: Variant = _authorized_team(representative_id)
	if relation.is_empty() or payer == null or recipient == null or payer == recipient:
		return Runtime.fail("AUTHORITY", "須由兩隊合格當前指揮者或原玩家隊員代表交付")
	if _original_team(int(relation.captor_id)) != recipient:
		return Runtime.fail("AUTHORITY", "收糧代表不是原拘押者所屬隊伍")
	var target: Dictionary = controller.lab._combat_target(target_id)
	if target.is_empty() or int(payer.faction_id) != int(target.owner.faction_id) or int(recipient.faction_id) != int(relation.captor_faction):
		return Runtime.fail("AUTHORITY", "付款方須為原友方，收糧方須為原拘押方")
	if not controller._team_stopped(payer) or not controller._team_stopped(recipient):
		return Runtime.fail("BUSY", "兩隊须停止並收束原動作")
	var first: Dictionary = controller._supply_entry(payer)
	var second: Dictionary = controller._supply_entry(recipient)
	if first.is_empty() or second.is_empty():
		return Runtime.fail("NO_SUPPLY_OWNER", "實物贖回需要兩個已啟用的原隊伍庫存")
	if not first.delivery.is_empty() or not second.delivery.is_empty():
		return Runtime.fail("BUSY", "先完成或取消原口糧交付")
	var now := Runtime.now(controller.lab.terrain) * 60.0
	if absf(float(first.sustain.at) - now) > 0.00001 or absf(float(second.sustain.at) - now) > 0.00001:
		return Runtime.fail("BUSY", "原供養時段尚未同步")
	if not Runtime._resource_stack(first.inventory) or not Runtime._resource_stack(second.inventory):
		return Runtime.fail("INVALID", "原隊伍庫存無效")
	var stock := 0
	for food: String in Sustain.FOODS:
		stock += int(first.inventory.get(food, 0))
	if stock < RANSOM_RATIONS:
		return Runtime.fail("MATERIALS", "原付款庫存不足一百完整實物日份")
	if Sustain.rations(second.sustain, second.inventory) + RANSOM_RATIONS > controller.team_food_capacity(recipient):
		return Runtime.fail("STORAGE_FULL", "拘押隊伍的實際攜糧容量不足，含已拆餐份")
	return Runtime.ok("", {"source": first.inventory, "destination": second.inventory,
		"source_owner": "team:%d" % payer.team_id, "destination_owner": "team:%d" % recipient.team_id,
		"source_revision": int(first.revision), "destination_revision": int(second.revision),
		"source_entry": first, "destination_entry": second})

func ransom_exchange_committed(query: Dictionary) -> void:
	# PersonActions has already moved the checked original resource dictionaries.
	# Membership commit follows synchronously and never rewrites stock/open food.
	query.source_entry.revision = int(query.source_entry.revision) + 1
	query.destination_entry.revision = int(query.destination_entry.revision) + 1
