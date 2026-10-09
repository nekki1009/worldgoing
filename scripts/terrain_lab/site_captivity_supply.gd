extends RefCounted
## Original feeding-owner coordination only. Captivity/actions and people remain
## with their existing owners; prepared copies are never saved or advanced.

const CrowdOwner = preload("res://scripts/terrain_lab/crowd_person_owner.gd")
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
		return person.owner.combat_hot_materialize(int(person.unit))
	return controller._actor_supply_adapter(person.owner)

func _original_team(identity: int) -> Variant:
	var crowd: Variant = controller.lab.get("crowd_site")
	if crowd != null and bool(crowd.active) and crowd.contains_person(identity):
		var owner: Variant = crowd.person_owner(identity)
		return owner if not crowd.team_record(owner.formation_index).is_empty() else null
	for team: TerrainArmy in controller.lab.combat_armies:
		var index := team.index_for_identity(identity)
		if team.combat_enabled and index >= 0 and (index == TerrainArmy.PLAYER_MEMBER or team.is_member(index)):
			return team
	return null

func _original_members(team: Variant) -> Dictionary:
	if team is CrowdOwner:
		return team.original_members()
	var result := {}
	for index in range(team.combat_units.size()):
		if team.is_member(index):
			result[team.combat_identity(index)] = team.combat_hot_materialize(index)
	if is_instance_valid(team.player_member):
		result[team.player_member.person_id] = controller._actor_supply_adapter(team.player_member, team.player_present)
	return result

func _all_members() -> Dictionary:
	var result := {}
	var crowd: Variant = controller.lab.get("crowd_site")
	if crowd != null and bool(crowd.active):
		for owner: Variant in crowd.person_owners():
			result.merge(owner.original_members(), false)
	_append_other_members(result)
	return result

func _event_members() -> Dictionary:
	# This view belongs only to the synchronous native captivity batch. Its
	# consumers validate/move meal cohorts (hp) and retain life checkpoints
	# (person_id/hp/ko); ordinary callers still receive the full original rows.
	var crowd: Variant = controller.lab.get("crowd_site")
	if crowd == null or not bool(crowd.active) or crowd.crowd == null or not crowd.crowd.has_method("get_life_states"):
		return _all_members()
	var owners: Array = crowd.person_owners()
	for owner: Variant in owners:
		# A custom owner may add semantics to original_members/materialization.
		if owner.get_script() != CrowdOwner: return _all_members()
	var required: Variant = _event_member_ids(crowd)
	if required == null: return _all_members()
	var life: PackedFloat64Array = crowd.crowd.get_life_states()
	if life.size() != int(crowd.crowd.soldier_count()) * 3: return _all_members()
	var result := {}
	for identity: int in required:
		var owner: Variant = crowd.person_owner(identity)
		if owner == null: continue # Unknown IDs remain absent for full validation.
		var index: int = owner.index_for_identity(identity)
		if not owner.combat_units.has(index) or owner.combat_identity(index) != identity: continue
		var offset := index * 3
		if offset < 0 or offset + 2 >= life.size(): return _all_members()
		result[identity] = {"person_id": identity, "hp": life[offset], "ko": life[offset + 1], "captive": bool(life[offset + 2])}
	_append_other_members(result, crowd)
	return result

func _event_member_ids(crowd: Variant) -> Variant:
	var pending: Variant = crowd.get("pending_captivity")
	if not pending is Array or pending.is_empty(): return null
	var required := {}
	# All existing cohorts are still validated, including unrelated owners.
	# Deduplication here never hides duplicates in the original cohort arrays.
	for field: String in ["team_supply", "person_supply"]:
		var entries: Variant = controller.lab.terrain.site.get(field, {})
		if not entries is Dictionary: return null
		for entry: Variant in entries.values():
			if not entry is Dictionary: return null
			var state: Variant = entry.get("sustain") if field == "team_supply" else entry
			if not state is Dictionary or not state.get("cohorts") is Array: return null
			for cohort: Variant in state.cohorts:
				if not cohort is Dictionary or not cohort.get("ids") is Array: return null
				for identity: Variant in cohort.ids:
					if Sustain._integer(identity, 1): required[int(identity)] = true
	# A later event can opt in its original source/captor team. Admit those
	# entire original rosters now, before ANY commit, using the same life sample.
	var participants := {}
	for event: Variant in pending:
		if not event is Dictionary or event.get("kind") not in [4, 5]: return null
		var identities: Array = [event.get("person", -1)]
		if int(event.kind) == 4: identities.append(event.get("other", -1))
		for identity: Variant in identities:
			var owner: Variant = crowd.person_owner(int(identity))
			if owner == null: return null
			participants[owner] = true
	for owner: Variant in participants:
		for index: int in owner.combat_units:
			required[owner.combat_identity(index)] = true
	return required

func _append_other_members(result: Dictionary, sparse_crowd: Variant = null) -> void:
	for team: TerrainArmy in controller.lab.combat_armies:
		for index in range(team.combat_units.size()):
			var identity := team.combat_identity(index)
			if not result.has(identity) and (sparse_crowd == null or sparse_crowd.person_owner(identity) == null):
				result[identity] = team.combat_hot_materialize(index)
		if is_instance_valid(team.player_member) and not result.has(team.player_member.person_id) and (sparse_crowd == null or sparse_crowd.person_owner(team.player_member.person_id) == null):
			result[team.player_member.person_id] = controller._actor_supply_adapter(team.player_member, team.player_present)
	for actor: TerrainTestCharacter in controller.lab.combat_actors:
		if not result.has(actor.person_id) and (sparse_crowd == null or sparse_crowd.person_owner(actor.person_id) == null):
			result[actor.person_id] = controller._actor_supply_adapter(actor)

func _states(copy_state: bool = true) -> Dictionary:
	var result := {}
	for id: String in controller.lab.terrain.site.get("team_supply", {}):
		var entry: Dictionary = controller.lab.terrain.site.team_supply[id]
		result["team:" + id] = {"state": entry.sustain.duplicate(true) if copy_state else entry.sustain, "original": entry.sustain,
			"entry": entry, "created": false, "dirty": false, "copied": copy_state}
	for id: String in controller.lab.terrain.site.get("person_supply", {}):
		var state: Dictionary = controller.lab.terrain.site.person_supply[id]
		result["person:" + id] = {"state": state.duplicate(true) if copy_state else state, "original": state,
			"entry": {}, "created": false, "dirty": false, "copied": copy_state}
	return result

func _feeding_owner(identity: int, states: Dictionary, feeding: Variant = null) -> String:
	if feeding is Dictionary: return str(feeding.get(identity, ""))
	for key: String in states:
		if identity in Sustain._ids(states[key].state):
			return key
	return ""

func feeding_index() -> Dictionary:
	# One caller-owned synchronous view, derived only from the original cohorts.
	# Duplicate facts are retained; never overwrite an owner and conceal bad data.
	var result := {"owners": {}, "team_ids": {}, "duplicate_ids": []}
	for id: String in controller.lab.terrain.site.get("team_supply", {}):
		var key := "team:" + id
		var ids := Sustain._ids(controller.lab.terrain.site.team_supply[id].sustain)
		result.team_ids[key] = ids
		for identity: int in ids:
			if result.owners.has(identity): result.duplicate_ids.append(identity)
			else: result.owners[identity] = key
	for id: String in controller.lab.terrain.site.get("person_supply", {}):
		var key := "person:" + id
		for identity: int in Sustain._ids(controller.lab.terrain.site.person_supply[id]):
			if result.owners.has(identity): result.duplicate_ids.append(identity)
			else: result.owners[identity] = key
	return result

func team_members(team: Variant, original: Dictionary, feeding: Dictionary = {}, known_records: Dictionary = {}) -> Dictionary:
	# Cohorts are the saved feeding ownership. A dead captive's relationship may
	# already be cleared, but that does not move or refund their eaten meal.
	# The sole caller has already admitted only real members via team.is_member().
	var result := original.duplicate()
	var own_key := "team:%d" % team.team_id
	if not feeding.is_empty() and feeding.duplicate_ids.is_empty():
		# With unique feeding ownership these removals commute. Own-cohort additions
		# retain the original cohort order and every retained original body reference.
		for identity: int in original:
			var key := str(feeding.owners.get(identity, ""))
			if not key.is_empty() and key != own_key: result.erase(identity)
		for identity: int in feeding.team_ids.get(own_key, []):
			if not result.has(identity):
				# Crowd sustain supplies original rows and reads life through its hot_read.
				var body: Dictionary = known_records[identity] if known_records.has(identity) else _body(identity)
				if not body.is_empty(): result[identity] = body
		return result
	# Any duplicate uses the unchanged ordered legacy path below. Full Sustain
	# validation still rejects malformed owners; the index cannot mask conflicts.
	for key: String in controller.lab.terrain.site.get("team_supply", {}):
		var state: Dictionary = controller.lab.terrain.site.team_supply[key].sustain
		for id: int in Sustain._ids(state):
			if "team:" + key != own_key:
				result.erase(id)
			elif not result.has(id):
				var body: Dictionary = known_records[id] if known_records.has(id) else _body(id)
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
	if not person.is_empty() and person.owner is CrowdOwner and person.owner.actors.has(int(person.unit)):
		return {"key": "person:%d" % identity, "actor": person.owner.actors[int(person.unit)]}
	if not person.is_empty() and int(person.unit) >= 0:
		var row: Dictionary = person.owner.combat_hot_materialize(int(person.unit))
		return {"key": "person:%d" % identity, "row": row} if row.get("cargo") is Dictionary else {}
	for actor: TerrainTestCharacter in controller.lab.combat_actors:
		if actor.person_id == identity:
			var activity: Dictionary = controller.lab.terrain.site.manual if actor == controller.lab.character else controller.lab.terrain.site.worker
			if not activity.get("cargo") is Dictionary:
				return {}
			return {"key": "person:%d" % identity, "actor": actor}
	return {} # No original inventory owner; never invent a team or proxy person.

func _align(owner: Dictionary, at_seconds: float) -> bool:
	if not owner.entry.get("delivery", {}).is_empty():
		return false
	if int(owner.state.get("version", 1)) == 2 and not Sustain._valid_locations(owner.entry.get("locations", {})):
		return false
	# Event preflight reads every owner, but only participants need writable copies.
	# Clone before even a clock-alignment write; a failed preflight stays atomic.
	if not bool(owner.get("copied", true)):
		owner.state = owner.state.duplicate(true)
		owner.copied = true
	return controller._align_supply_clock(owner.state, at_seconds)

func _add(state: Dictionary, members: Dictionary, ids: Array) -> bool:
	var morale := float(state.morale)
	var result := Sustain.add_members(state, members, ids)
	state.morale = morale # Opting into meals is not actual roster reinforcement.
	return bool(result.ok)

func _move(identity: int, source: String, target: String, states: Dictionary, members: Dictionary, moves: Array, at_seconds: float, feeding: Variant = null) -> bool:
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
	if feeding is Dictionary: feeding[identity] = target
	return true

func _ensure(home: Dictionary, states: Dictionary, members: Dictionary, moves: Array, at_seconds: float, target_id: int, feeding: Variant = null) -> bool:
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
		var previous := _feeding_owner(id, states, feeding)
		if previous.is_empty():
			fresh.append(id)
		elif previous.begins_with("person:"):
			if not _move(id, previous, key, states, members, moves, at_seconds, feeding):
				return false
		else:
			return false # An unrelated team's recorded ownership is not ours to steal.
	if not fresh.is_empty() and not _add(states[key].state, members, fresh): return false
	if feeding is Dictionary:
		for identity: int in fresh: feeding[identity] = key
	return true

func enable_team(team: Variant, preview: bool = false) -> Dictionary:
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
	if preview:
		var entry := {"version": 2, "sustain": states[key].state, "inventory": {}, "training_order": false,
			"training_requester": -1, "training_feature_id": "", "revision": 0, "delivery": {}, "life_checkpoint": {}}
		for id: int in Sustain._ids(entry.sustain): entry.life_checkpoint[str(id)] = controller._life(members[id])
		return Runtime.ok("", {"entry": entry})
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
	return _prepare_change(target_id, captor_id, capturing)

func event_change_guard(target_id: int, captor_id: int, capturing: bool, event_context: Dictionary = {}) -> Dictionary:
	# Native has already committed this transition; life/captive rechecks would
	# reject valid delayed events (including CAPTURED followed by DEATH).
	_prepared.clear()
	var site: Dictionary = controller.lab.terrain.site
	if _body(target_id).is_empty() or target_id == captor_id:
		return Runtime.fail("NO_TARGET", "群眾事件缺少原人物")
	var relation: Dictionary = site.get("captivity", {}).get(str(target_id), {})
	if capturing:
		if not relation.is_empty() or _body(captor_id).is_empty():
			return Runtime.fail("NO_TARGET", "群眾捕獲事件的原拘押關係不符")
	elif int(relation.get("captor_id", -1)) != captor_id:
		return Runtime.fail("NO_TARGET", "群眾逃脫事件的原拘押關係不符")
	return _prepare_change(target_id, captor_id, capturing, event_context)

func discard(target_id: int) -> void:
	_prepared.erase(target_id)

func _prepare_change(target_id: int, captor_id: int, capturing: bool, event_context: Dictionary = {}) -> Dictionary:
	var site: Dictionary = controller.lab.terrain.site
	var destination := _home(captor_id if capturing else target_id)
	var original := _home(target_id)
	if destination.is_empty() or original.is_empty():
		return Runtime.fail("NO_SUPPLY_OWNER", "沒有可接續的原隊伍或個人行囊供養者")
	var members: Dictionary
	if event_context.is_empty():
		members = _all_members()
	else:
		var active_crowd: Variant = controller.lab.get("crowd_site")
		if bool(event_context.get("invalid", false)) or not is_same(event_context.get("site"), site) or not is_same(event_context.get("terrain"), controller.lab.terrain) or active_crowd == null or not is_same(event_context.get("native"), active_crowd.crowd) or int(event_context.get("step", -1)) != int(active_crowd._steps) or float(event_context.get("at", -1.0)) != Runtime.now(controller.lab.terrain) * 60.0:
			event_context.erase("members")
			event_context.invalid = true
			return Runtime.fail("BUSY", "群眾供養批次已離開原 Site 或動作時段；未使用舊人物快照")
		if not event_context.has("members"): event_context.members = _event_members()
		members = event_context.members
	# Read the latest cohorts and validate every owner for every event. Copy only
	# actual transaction participants before mutation; other owners stay read-only.
	var states := _states(event_context.is_empty())
	var values: Array = []
	var keys: Array[String] = []
	for key: String in states:
		values.append(states[key].state)
		keys.append(key)
	var ownership := Sustain.validate_owner_index(values, members, keys)
	if not ownership.ok:
		return Runtime.fail("INVALID_SUSTAIN", "原供養名單重複或資料無效")
	var feeding: Dictionary = ownership.owners
	var at_seconds := Runtime.now(controller.lab.terrain) * 60.0
	var moves: Array = []
	var source := _feeding_owner(target_id, states, feeding)
	if source.is_empty():
		if not capturing:
			return Runtime.fail("INVALID_SUSTAIN", "俘虜缺少原供养歷史，不可重設已吃餐份")
		if not _ensure(original, states, members, moves, at_seconds, target_id, feeding):
			return Runtime.fail("BUSY", "原供養時段或交糧尚未收束")
		source = str(original.key)
		if not _add(states[source].state, members, [target_id]):
			return Runtime.fail("INVALID_SUSTAIN")
		states[source].dirty = true
		if feeding is Dictionary: feeding[target_id] = source
	if not _ensure(destination, states, members, moves, at_seconds, target_id, feeding) or not _move(target_id, source, str(destination.key), states, members, moves, at_seconds, feeding):
		return Runtime.fail("BUSY", "供養時段或交糧尚未收束；未移轉食物或人物")
	# The action owner rechecks immediately before its synchronous commit. Only
	# event-local copies are retained; failed/cancelled checks change no Site data.
	# The original team revision is saved with a strict signed-int bound.
	# Refuse before any real membership/stock publication at its ceiling.
	for key: String in states:
		var owner: Dictionary = states[key]
		if key.begins_with("team:") and bool(owner.dirty) and not bool(owner.created) \
			and not Runtime._building_integer(owner.entry.get("revision"), 0, 2147483646): return Runtime.fail("BUSY", "原隊伍提交版本已用盡，未改供養名單")
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
				owner.entry = {"version": 2, "sustain": owner.state, "inventory": {}, "training_order": false,
					"training_requester": -1, "training_feature_id": "", "revision": 0, "delivery": {}, "life_checkpoint": {}}
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
				source.training_feature_id = ""
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
		var row: Dictionary = team.combat_hot_materialize(index)
		if team.is_member(index) == joining or not row.get("cargo") is Dictionary:
			return Runtime.fail("INVALID_MEMBERS")
		personal = {"key": "person:%d" % identity, "row": row}
	else:
		var person: Dictionary = controller.lab._combat_target(identity)
		if person.is_empty() or int(person.unit) >= 0 or (team.player_member == person.owner) == joining:
			return Runtime.fail("INVALID_MEMBERS")
		personal = {"key": "person:%d" % identity, "actor": person.owner}
	var destination := {"key": "team:%d" % team.team_id, "team": team} if joining else personal
	return _change_membership_supply(team, destination, [identity])

func _change_membership_supply(source: Variant, destination_home: Dictionary, ids: Array[int], dry_run: bool = false) -> Dictionary:
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
	if dry_run: return Runtime.ok()
	_commit_states({"site": site, "states": states, "members": members, "moves": moves, "joined": joined})
	var source_entry: Dictionary = controller._supply_entry(source)
	if not source_entry.is_empty() and selected.has(int(source_entry.training_requester)):
		source_entry.training_order = false
		source_entry.training_requester = -1
		source_entry.training_feature_id = ""
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
	var source: Dictionary = controller._team_food_endpoint(payer, payer_id)
	var destination: Dictionary = controller._team_food_endpoint(recipient, representative_id, true)
	if source.is_empty() or destination.is_empty() or not Runtime._resource_stack(source.inventory) or not Runtime._resource_stack(destination.inventory):
		return Runtime.fail("INVALID", "原隊伍庫存無效")
	# The original ransom action still requires its real representatives to be
	# adjacent. Its inventories must also be at those actual contact positions.
	if int(first.version) == 3 and not controller._supply_locations_valid(payer, first.locations) or int(second.version) == 3 and not controller._supply_locations_valid(recipient, second.locations):
		return Runtime.fail("INVALID_SUSTAIN")
	if str(source.key).begins_with("vehicle:") or str(destination.key).begins_with("vehicle:"):
		return Runtime.fail("UNREACHABLE", "首版贖回須先將指定共有糧卸到雙方實際可達岸格")
	var stock := 0
	for food: String in Sustain.FOODS:
		stock += int(source.inventory.get(food, 0))
	if stock < RANSOM_RATIONS:
		return Runtime.fail("MATERIALS", "原付款庫存不足一百完整實物日份")
	if Sustain.rations(second.sustain, controller._supply_stock(second)) + RANSOM_RATIONS > controller.team_food_capacity(recipient):
		return Runtime.fail("STORAGE_FULL", "拘押隊伍的實際攜糧容量不足，含已拆餐份")
	if not bool(destination.exists):
		return Runtime.fail("NO_SUPPLY_OWNER", "須先由原交糧入口建立實際岸格庫存，再接贖回實物")
	return Runtime.ok("", {"source": source.inventory, "destination": destination.inventory,
		"source_owner": "team:%d" % payer.team_id, "destination_owner": "team:%d" % recipient.team_id,
		"source_revision": int(first.revision), "destination_revision": int(second.revision),
		"source_entry": first, "destination_entry": second})

func ransom_exchange_committed(query: Dictionary) -> void:
	# PersonActions has already moved the checked original resource dictionaries.
	# Membership commit follows synchronously and never rewrites stock/open food.
	query.source_entry.revision = int(query.source_entry.revision) + 1
	query.destination_entry.revision = int(query.destination_entry.revision) + 1
