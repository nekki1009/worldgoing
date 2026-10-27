extends RefCounted
## Formula metadata only. Original person, sustain, structure and siege owners
## receive the effects; Slot alone owns the accepted interval and durable commit.

const Policy = preload("res://scripts/region_lab/region_gameplay_ai.gd")
const VERSION := 1
const ROUND_GAME_SECONDS := 600.0
const EPSILON := 0.000001
const RULES_REVISION := "region_battle_v1"

static func create(spec: Dictionary) -> Dictionary:
	for key: String in ["id", "site_id", "attackers", "defenders", "game_time"]:
		if not spec.has(key): return _fail("INVALID_BATTLE")
	if bool(spec.get("player_site", false)) or bool(spec.get("player_party", false)) or bool(spec.get("player_barrier", false)):
		return _fail("PLAYER_BARRIER")
	if str(spec.id).is_empty() or str(spec.site_id).is_empty() or not spec.attackers is Array or not spec.defenders is Array:
		return _fail("INVALID_BATTLE")
	var coefficient := float(spec.get("loss_coefficient", 1.0 / 600.0))
	if not is_finite(coefficient) or coefficient < 0.0: return _fail("INVALID_RULES")
	var start := float(spec.game_time)
	if not is_finite(start) or start < 0.0: return _fail("INVALID_BATTLE")
	var battle := {"version": VERSION, "id": str(spec.id), "site_id": str(spec.site_id),
		"kind": str(spec.get("kind", "ordinary")), "phase": str(spec.get("phase", "engage")),
		"mode": "formula_active", "start_game_time": start, "completed_game_time": start,
		"round_end": start + ROUND_GAME_SECONDS, "rules_revision": str(spec.get("rules_revision", RULES_REVISION)),
		"loss_coefficient": coefficient, "attackers": spec.attackers.duplicate(), "defenders": spec.defenders.duplicate(),
		"rng_state": int(spec.get("rng_state", 1)), "revision": 0, "pending": [], "receipts": {},
		"round_inputs": {}, "policy": spec.get("policy", {}).duplicate(true)}
	return {"ok": true, "code": "", "battle": battle}

static func next_event(battle: Dictionary) -> float:
	if str(battle.get("kind", "")) == "siege" and str(battle.get("mode", "")) != "formula_active": return INF
	var result := float(battle.get("round_end", INF))
	for event: Dictionary in battle.get("pending", []): result = minf(result, float(event.get("game_time", INF)))
	var inputs: Dictionary = battle.get("round_inputs", {})
	for side: String in ["attackers", "defenders"]:
		var info: Dictionary = inputs.get(side, {})
		var rate := float(info.get("hp_rate", 0.0))
		if rate > EPSILON and not info.get("target", {}).is_empty():
			result = minf(result, float(inputs.get("start", battle.completed_game_time)) + float(info.target.hp) / rate)
		var stun_rate := float(info.get("stun_rate", 0.0))
		if stun_rate > EPSILON and not info.get("target", {}).is_empty():
			result = minf(result, float(inputs.get("start", battle.completed_game_time)) + maxf(0.0, SiteCombatRules.STUN_LIMIT - float(info.target.get("stun", 0.0))) / stun_rate)
	for endpoint: Variant in battle.get("owner_endpoints", []): result = minf(result, float(endpoint))
	return result

## readonly people shape: {person_id: {id, hp, ready, eligible, side,
## rank, ability, training, morale, fatigue, weapon, armor, resident?}}.
## Eligible is original physical deployment/contact evidence, never rank alone.
static func prepare_interval(battle: Dictionary, interval: Dictionary, original_people: Dictionary) -> Dictionary:
	if str(battle.get("mode", "")) != "formula_active": return _fail("WRONG_MODE")
	if str(battle.get("phase", "")) == "finished": return _fail("BATTLE_FINISHED")
	if bool(interval.get("player_site", false)) or bool(interval.get("player_party", false)) :
		return _fail("PLAYER_BARRIER")
	var checked := _validate_interval(battle, interval)
	if not bool(checked.ok): return checked
	if not battle.get("pending", []).is_empty(): return _fail("EFFECTS_PENDING")
	var candidate: Dictionary = battle.duplicate(true)
	var game_start := float(interval.game_start)
	var game_end := float(interval.game_end)
	if candidate.round_inputs.is_empty():
		candidate.round_inputs = _inputs(candidate, original_people, game_start)
	var inputs: Dictionary = candidate.round_inputs
	var endpoint := next_event(candidate)
	if game_end > endpoint + EPSILON: return {"ok": false, "code": "EVENT_CLIP_REQUIRED", "next_event": endpoint}
	var effects: Array[Dictionary] = []
	var elapsed := game_end - game_start
	if str(candidate.kind) == "ordinary" or str(candidate.phase) == "assault":
		for side: String in ["attackers", "defenders"]:
			var info: Dictionary = inputs[side]
			if info.target.is_empty() or float(info.hp_rate) <= 0.0: continue
			var victim: Dictionary = info.target
			var hp := float(info.hp_rate) * elapsed
			var attack_id := _effect_id(candidate, interval, "damage:" + str(victim.id))
			for person_id: Variant in [victim.id, info.source.get("id", -1)]:
				if int(person_id) <= 0: continue
				var fatigue_id := _effect_id(candidate, interval, "fatigue:" + side + ":" + str(person_id))
				effects.append({"kind": "fatigue", "id": fatigue_id, "person_id": int(person_id),
					"amount": float(info.fatigue_rate) * elapsed, "game_time": game_end})
			effects.append({"kind": "damage", "id": attack_id, "attack_id": attack_id, "person_id": int(victim.id),
				"source_person_id": int(info.source.get("id", -1)), "hp": hp, "stun": float(info.stun_rate) * elapsed,
				"game_time": game_end, "rules_revision": str(candidate.rules_revision),
				"contact": {"site_id": str(candidate.site_id), "source": int(info.source.get("id", -1)),
					"target": int(victim.id), "game_time": float(inputs.start),
					"source_cell": info.source.get("contact_cell", []).duplicate(),
					"target_cell": victim.get("contact_cell", []).duplicate(),
					"verified": bool(info.source.get("contact_resolved", false)) and info.source.get("legal_targets", []).has(int(victim.id))}})
		# All original pools pay the accepted historical effort before a death
		# unbinds a member. This is the original exchange batch ordering.
		effects.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return str(a.kind) == "fatigue" and str(b.kind) != "fatigue")
	# Siege uses the exact existing owner for stages, finite ammo, impact IDs,
	# paid crew cost, builds/repairs and capture. It receives raw action once.
	if str(candidate.kind) == "siege":
		effects.append({"kind": "siege_round", "id": _effect_id(candidate, interval, "siege"),
			"game_time": game_end, "interval": interval.duplicate(true), "phase": str(candidate.phase)})
	var known: Dictionary = candidate.get("policy", {})
	for side: String in ["attackers", "defenders"]:
		var policy: Dictionary = known.get(side, {})
		if not policy.get("known_enemy") is Dictionary or policy.known_enemy.is_empty(): continue
		var own: Dictionary = inputs[side]
		var enemy_power := float(policy.known_enemy.get("power", -1.0))
		if enemy_power < 0.0: continue
		var thresholds := Policy.military_thresholds(policy.get("personality", {}))
		var ratio := float(own.power) / maxf(0.1, enemy_power)
		if ratio < float(thresholds.withdraw) or float(own.health) < float(thresholds.health) or float(own.ready_fraction) < float(thresholds.ready) or float(own.morale) < float(thresholds.morale) or float(own.fatigue) >= float(thresholds.fatigue):
			effects.append({"kind": "order", "id": _effect_id(candidate, interval, "withdraw:" + side),
				"side": side, "order": "RETREAT", "game_time": game_end, "known_receipt": str(policy.known_enemy.get("id", ""))})
	candidate.completed_game_time = game_end
	candidate.pending = effects.duplicate(true)
	candidate.revision = int(candidate.revision) + 1
	if is_equal_approx(game_end, float(candidate.round_end)):
		candidate.round_end = game_end + ROUND_GAME_SECONDS
		candidate.round_inputs = {}
	elif is_equal_approx(game_end, endpoint):
		candidate.round_inputs = {} # Death/KO/crew/work endpoint requires original fresh inputs.
	return {"ok": true, "code": "", "base_revision": int(battle.revision),
		"candidate": candidate, "effects": effects, "interval": interval.duplicate(true)}

## Called only after the interval-complete/player barrier phase. Successful
## effects carry receipts even when a later owner fails; retry never repeats them.
static func apply_pending(battle: Dictionary, prepared: Dictionary, callbacks: Dictionary) -> Dictionary:
	if not bool(prepared.get("ok", false)): return _fail("INVALID_PREPARED")
	if int(battle.get("revision", -1)) != int(prepared.base_revision): return _fail("STALE_REVISION")
	if bool(prepared.interval.get("player_barrier", false)): return _fail("PLAYER_BARRIER")
	var candidate: Dictionary = prepared.candidate.duplicate(true)
	var receipts: Dictionary = battle.get("receipts", {}).duplicate(true)
	var remaining: Array[Dictionary] = []
	var results: Array[Dictionary] = []
	for effect: Dictionary in prepared.effects:
		var effect_id := str(effect.id)
		if receipts.has(effect_id): continue
		var callback: Callable = callbacks.get(str(effect.kind), Callable())
		if not callback.is_valid():
			remaining.append(effect)
			continue
		var outcome: Dictionary = callback.call(effect.duplicate(true))
		if not bool(outcome.get("ok", false)):
			battle.receipts = receipts
			return {"ok": false, "code": str(outcome.get("code", "OWNER_REFUSED")),
				"effect_id": effect_id, "owner_results": results}
		receipts[effect_id] = {"game_time": float(effect.game_time), "kind": str(effect.kind)}
		results.append({"id": effect_id, "result": outcome})
	if not remaining.is_empty():
		battle.receipts = receipts
		return {"ok": false, "code": "MISSING_EFFECT_OWNER", "pending": remaining, "owner_results": results}
	candidate.receipts = receipts
	candidate.pending = []
	battle.clear()
	battle.merge(candidate, true)
	return {"ok": true, "code": "", "owner_results": results}

## Ephemeral references to the original Lab. A caller restriction can only
## remove legal people; it cannot turn a hidden/blocked person into a contact.
## Ranged releases retain the original finite-ammo/flight owner and are omitted.
static func resolve_people(lab: TerrainLab, battle: Dictionary, eligibility_query: Callable = Callable(), scope: Dictionary = {}) -> Dictionary:
	if lab == null or lab.terrain == null or str(lab.terrain.site.get("id", "")) != str(battle.get("site_id", "")):
		return _fail("WRONG_BATTLE_SITE")
	if lab.crowd_site != null and lab.crowd_site.active: return _fail("UNSUPPORTED_BACKEND")
	var original_refs := {}
	var values := {}
	# A detached bind child has no Slot of its own; its caller supplies the scope.
	var control_scope := scope if not scope.is_empty() else scoped_controlled_person(lab)
	if not control_scope.get("ok", false): return control_scope
	var controlled := int(control_scope.person_id)
	for side: String in ["attackers", "defenders"]:
		for value: Variant in battle.get(side, []):
			var identity := int(value)
			if identity == controlled and controlled > 0: return _fail("PLAYER_BARRIER")
			var person: Dictionary = lab._combat_target_in_site(identity)
			if person.is_empty(): continue
			var owner: Variant = person.owner
			var index := int(person.unit)
			if not owner is TerrainArmy and not owner is TerrainTestCharacter: return _fail("UNSUPPORTED_BACKEND")
			var receives: bool = owner.exchange_can_receive(index) if index >= 0 else owner.exchange_can_receive()
			var initiates: bool = owner.exchange_ready(index) if index >= 0 else owner.exchange_ready()
			var restriction := not eligibility_query.is_valid() or bool(eligibility_query.call(identity, side, person))
			var stats: Dictionary = owner.exchange_stats(index) if index >= 0 else owner.exchange_stats()
			stats = stats.duplicate(true)
			stats.merge({"id": identity, "side": side, "hp": float(person.hp), "stun": float(owner.combat_hot_get(index, &"stun")) if index >= 0 else float(owner.stun),
				"ready": receives and restriction, "eligible": false, "can_initiate": initiates and restriction,
				"rank": _original_rank(owner, identity), "resident": index >= 0 and not owner.is_member(index),
				"morale": lab._exchange_morale(identity), "facility": SiteRuntime.exchange_facility_bonus(lab.terrain, person.cell),
				"legal_targets": [], "contact_resolved": true, "contact_cell": [person.cell.x, person.cell.y]}, true)
			values[identity] = stats
			original_refs[identity] = {"owner": owner, "unit": index, "id": identity, "cell": person.cell, "faction": int(owner.faction_id)}
	for identity: int in original_refs:
		var source: Dictionary = original_refs[identity]
		if not bool(values[identity].ready) or not bool(values[identity].can_initiate): continue
		for other_id: int in original_refs:
			if str(values[identity].side) == str(values[other_id].side) or not bool(values[other_id].ready): continue
			var target: Dictionary = original_refs[other_id]
			if not _legal_melee_pair(lab, source, target) or not lab._exchange_initiates(source, other_id, true): continue
			values[identity].legal_targets.append(other_id)
			values[other_id].eligible = true
	return {"ok": true, "code": "", "people": values, "scope": "original_melee_contacts"}

static func _original_rank(owner: Variant, identity: int) -> int:
	if not owner is TerrainArmy: return 0
	var commander: int = int(owner.combat_identity(int(owner.current_commander)))
	var officers: Array = []
	for seat: Dictionary in owner.team_offices(true).positions:
		if not bool(seat.head) and int(seat.holder) > 0: officers.append(int(seat.holder))
	return Policy.rank_for(identity, commander, officers)

static func _legal_melee_pair(lab: TerrainLab, source: Dictionary, target: Dictionary) -> bool:
	if int(source.faction) == int(target.faction): return false
	var gap: Vector2i = target.cell - source.cell
	if absi(gap.x) + absi(gap.y) != 1 and not lab._combat_ship_pair(int(source.id), int(target.id)): return false
	return lab._combat_melee_clear(int(source.id), int(target.id), source.cell, target.cell)

## Exact ordinary owner adapters. Death/KO and fatigue-pool unbinding occur in
## their original methods; the original Controller keeps the down-animation
## cleanup delay. Slot must provide actual siege/work/capture/order consumers.
static func owner_callbacks(lab: TerrainLab, battle: Dictionary, extras: Dictionary = {}) -> Dictionary:
	var callbacks := {"damage": func(effect: Dictionary) -> Dictionary: return _owned_damage(lab, battle, effect),
		"fatigue": func(effect: Dictionary) -> Dictionary: return _owned_fatigue(lab, battle, effect)}
	callbacks.merge(extras, true)
	return callbacks

static func _effect_person(lab: TerrainLab, battle: Dictionary, identity: int) -> Dictionary:
	if lab == null or lab.terrain == null or str(lab.terrain.site.get("id", "")) != str(battle.get("site_id", "")): return {}
	if not battle.get("attackers", []).has(identity) and not battle.get("defenders", []).has(identity): return {}
	return lab._combat_target_in_site(identity)

static func _owned_damage(lab: TerrainLab, battle: Dictionary, effect: Dictionary) -> Dictionary:
	var target := _effect_person(lab, battle, int(effect.get("person_id", -1)))
	var source := _effect_person(lab, battle, int(effect.get("source_person_id", -1)))
	if target.is_empty() or source.is_empty(): return _fail("NO_ORIGINAL_PERSON")
	var target_id := int(effect.person_id)
	var source_id := int(effect.source_person_id)
	var control_scope := scoped_controlled_person(lab)
	if not control_scope.get("ok", false): return control_scope
	var controlled := int(control_scope.person_id)
	if controlled > 0 and (target_id == controlled or source_id == controlled): return _fail("PLAYER_BARRIER")
	var source_ref := {"id": source_id, "faction": int(source.owner.faction_id), "cell": source.cell}
	var target_ref := {"id": target_id, "faction": int(target.owner.faction_id), "cell": target.cell}
	var witness: Dictionary = effect.get("contact", {})
	if bool(witness.get("verified", false)):
		# The original solver admitted this contact at interval begin. Its paid
		# historical effort remains valid when either original body moves before
		# the endpoint. Membership, identity and opposing faction still bind here.
		if str(witness.get("site_id", "")) != str(battle.site_id) or int(witness.get("source", -1)) != source_id or int(witness.get("target", -1)) != target_id:
			return _fail("INVALID_CONTACT_WITNESS")
		if int(source_ref.faction) == int(target_ref.faction) or not is_finite(float(witness.get("game_time", NAN))) or float(witness.game_time) > float(effect.game_time):
			return _fail("INVALID_CONTACT_WITNESS")
		for key: String in ["source_cell", "target_cell"]:
			if not witness.get(key) is Array or witness[key].size() != 2: return _fail("INVALID_CONTACT_WITNESS")
	else:
		if not _legal_melee_pair(lab, source_ref, target_ref): return _fail("CONTACT_CHANGED")
	var hp := float(effect.get("hp", NAN))
	var stun := float(effect.get("stun", NAN))
	if not is_finite(hp) or hp < 0.0 or not is_finite(stun) or stun < 0.0: return _fail("INVALID_EFFECT")
	var packet := {"attack_id": str(effect.get("attack_id", effect.get("id", ""))), "source_person_id": source_id,
		"shield": false, "result": {"hp": hp, "stun": stun, "guard_break": false}}
	var index := int(target.unit)
	if target.owner is TerrainArmy and index >= 0:
		target.owner.apply_unit_contact(index, packet)
	elif target.owner is TerrainTestCharacter and index < 0:
		target.owner.apply_contact(packet)
	else: return _fail("UNSUPPORTED_BACKEND")
	return {"ok": true, "code": "", "owner": "original_apply_contact", "person_id": target_id}

static func _owned_fatigue(lab: TerrainLab, battle: Dictionary, effect: Dictionary) -> Dictionary:
	var person := _effect_person(lab, battle, int(effect.get("person_id", -1)))
	if person.is_empty(): return _fail("NO_ORIGINAL_PERSON")
	var control_scope := scoped_controlled_person(lab)
	if not control_scope.get("ok", false): return control_scope
	if int(control_scope.person_id) > 0 and int(effect.person_id) == int(control_scope.person_id): return _fail("PLAYER_BARRIER")
	var amount := float(effect.get("amount", NAN))
	if not is_finite(amount) or amount < 0.0: return _fail("INVALID_EFFECT")
	var index := int(person.unit)
	if person.owner is TerrainArmy and index >= 0:
		PersonFatigue.charge(person.owner.combat_units[index], amount)
	elif person.owner is TerrainTestCharacter and index < 0:
		PersonFatigue.charge(person.owner, amount)
	else: return _fail("UNSUPPORTED_BACKEND")
	return {"ok": true, "code": "", "owner": "PersonFatigue.charge", "person_id": int(effect.person_id)}
static func _validate_interval(battle: Dictionary, interval: Dictionary) -> Dictionary:
	for field: String in ["game_start", "game_end", "action_start", "action_end", "time_scale", "tactical_action", "permit_id", "journal_revision"]:
		if not interval.has(field): return _fail("MISSING_INTERVAL_PERMIT")
	var game_start := float(interval.game_start)
	var game_end := float(interval.game_end)
	var action := float(interval.action_end) - float(interval.action_start)
	var tactical := float(interval.tactical_action)
	var scale := float(interval.time_scale)
	if not is_finite(game_start) or not is_finite(game_end) or not is_finite(action) or not is_finite(scale) or not is_finite(tactical) or scale <= 0.0 or action < 0.0 or tactical < 0.0 or tactical > action + EPSILON or game_end < game_start:
		return _fail("CLOCK_CONTRACT")
	if str(interval.permit_id).is_empty() or int(interval.journal_revision) < 0: return _fail("MISSING_INTERVAL_PERMIT")
	if absf(game_start - float(battle.completed_game_time)) > EPSILON: return _fail("NONCONTIGUOUS_INTERVAL")
	if absf(game_end - game_start - (tactical + 60.0 * (action - tactical)) * scale) > EPSILON:
		return _fail("CLOCK_CONTRACT")
	return {"ok": true, "code": ""}

static func _inputs(battle: Dictionary, people: Dictionary, game_time: float) -> Dictionary:
	var result := {"start": game_time}
	for side: String in ["attackers", "defenders"]:
		var candidates: Array[Dictionary] = []
		var sources: Array[Dictionary] = []
		var total := 0
		var ready_count := 0
		var hp_sum := 0.0
		var fatigue_sum := 0.0
		var morale_sum := 0.0
		var power := 0.0
		for identity: Variant in battle[side]:
			var person: Dictionary = people.get(int(identity), people.get(str(identity), {}))
			if person.is_empty(): continue
			total += 1
			if not bool(person.get("ready", false)) or float(person.get("hp", 0.0)) <= 0.0: continue
			ready_count += 1
			var value := {"id": int(identity), "hp": float(person.hp), "stun": float(person.get("stun", 0.0)),
				"rank": int(person.get("rank", 0)), "ability": float(person.get("ability", 50.0)),
				"training": float(person.get("training", 0.0)), "morale": float(person.get("morale", 100.0)),
				"fatigue": float(person.get("fatigue", 0.0)), "weapon": str(person.get("weapon", "none")),
				"armor": str(person.get("armor", "none")), "resident": bool(person.get("resident", false)),
				"armorbonus": float(person.get("armorbonus", 0.0)), "facility": float(person.get("facility", 0.0)),
				"skill": str(person.get("skill", "")), "legal_targets": person.get("legal_targets", []).duplicate(),
				"contact_resolved": bool(person.get("contact_resolved", false)),
				"contact_cell": person.get("contact_cell", []).duplicate()}
			var weight := 0.5 if bool(value.get("resident", false)) else 1.0
			power += weight * float(value.hp) / 100.0 * maxf(0.1, SiteCombatRules.exchange_score(value) / 50.0)
			hp_sum += float(value.hp)
			fatigue_sum += float(value.get("fatigue", 0.0))
			morale_sum += float(value.get("morale", 100.0))
			if bool(person.get("eligible", false)): candidates.append(value)
			if not bool(value.contact_resolved) and bool(person.get("eligible", false)) or not value.legal_targets.is_empty():
				sources.append(value)
		var rank_order := func(a: Dictionary, b: Dictionary) -> bool:
			if int(a.get("rank", 0)) != int(b.get("rank", 0)): return int(a.get("rank", 0)) < int(b.get("rank", 0))
			return int(a.id) < int(b.id)
		candidates.sort_custom(rank_order)
		sources.sort_custom(rank_order)
		result[side] = {"power": power, "health": hp_sum / (100.0 * maxi(1, ready_count)),
			"ready_fraction": float(ready_count) / maxi(1, total), "fatigue": fatigue_sum / maxi(1, ready_count),
			"morale": morale_sum / maxi(1, ready_count), "target": candidates[0] if not candidates.is_empty() else {},
			"source": {}, "sources": sources, "hp_rate": 0.0, "stun_rate": 0.0, "fatigue_rate": 0.0}
	for side: String in ["attackers", "defenders"]:
		var enemy: String = "defenders" if side == "attackers" else "attackers"
		var info: Dictionary = result[side]
		var opposing: Dictionary = result[enemy]
		if info.target.is_empty(): continue
		for source: Dictionary in opposing.sources:
			if bool(source.get("contact_resolved", false)) and not source.legal_targets.has(int(info.target.id)): continue
			info.source = source
			break
		if info.source.is_empty(): continue
		var hit_hp := SiteCombatRules.exchange_hp(str(info.source.get("weapon", "none")), str(info.target.get("armor", "none")))
		info.hp_rate = pow(float(opposing.power), 2.0) / maxf(1.0, float(info.power)) * float(battle.loss_coefficient) * hit_hp
		var impact := SiteCombatRules.exchange_stun(str(info.source.get("weapon", "none")))
		if str(info.source.get("skill", "")) == "power": impact += SiteCombatRules.EXCHANGE_POWER_STUN
		info.stun_rate = float(info.hp_rate) / maxf(EPSILON, hit_hp) * impact
		info.fatigue_rate = float(info.hp_rate) / maxf(EPSILON, hit_hp) * SiteCombatRules.EXCHANGE_FATIGUE
	for side: String in ["attackers", "defenders"]: result[side].erase("sources")
	return result
static func _effect_id(battle: Dictionary, interval: Dictionary, kind: String) -> String:
	return "%s|%s|%d|%s" % [str(battle.id), str(interval.permit_id), int(interval.journal_revision), kind]

static func _fail(code: String) -> Dictionary:
	return {"ok": false, "code": code}


static func scoped_controlled_person(lab: TerrainLab) -> Dictionary:
	if not is_instance_valid(lab) or lab.terrain == null: return _fail("NO_ORIGINAL_PERSON")
	var identity := int(lab.controlled_person_id())
	var slot: RegionSaveSlot = lab.site_controller.region_slot if lab.site_controller != null else null
	if slot == null: return {"ok": true, "person_id": identity, "scope": "ordinary_original"}
	var active := str(slot.control.get("active_site_id", ""))
	var owner := str(lab.terrain.site.get("id", ""))
	if not active.is_empty():
		if owner != active: return {"ok": true, "person_id": -1, "scope": "cold_original"}
		var receipt: Dictionary = lab.region_bind_receipt(lab.terrain)
		if lab._region_bound_data != lab.terrain or receipt.get("complete") != true or receipt.get("owners_restored") != true or receipt.get("owner") != active or int(receipt.get("generation", -1)) != int(slot._marker.get("generation", 0)):
			return _fail("COMMITTED_UNBOUND")
		return {"ok": true, "person_id": identity, "scope": "active_original"}
	var journey: Dictionary = slot.region_travel_journey()
	var token := str(journey.get("token", ""))
	if token.is_empty() or owner != "travel:" + token: return {"ok": true, "person_id": -1, "scope": "cold_original"}
	# The existing getter is read-only after this SAME runtime-cache guard.
	if slot._travel_party_runtime_token != token or slot._travel_party_runtime.is_empty(): return _fail("STALE_REGION_PARTY_OWNER")
	var selected: Dictionary = slot.region_travel_party()
	if not selected.get("ok", false): return selected
	var runtime: Dictionary = slot.region_original_party_runtime_proof(token, selected.party)
	if not runtime.get("ok", false): return runtime
	if runtime.get("lab") != lab or not is_same(runtime.get("party"), selected.party): return _fail("STALE_REGION_PARTY_OWNER")
	return {"ok": true, "person_id": identity, "scope": "player_party_original"}


## Four siege phases are derived from the SAME original paid owners. This
## metadata selects no target, changes no placement and owns no work/timer.
## Until a measured casualty rule is admitted, the original exact GD consumer
## remains responsible for people as well as finite siege/work/contact tails.


const SIEGE_VERSION: int = 2

const SIEGE_PHASES := ["siege", "breach", "assault", "capture", "finished"]

const SIEGE_FIELDS := ["version", "center_id", "defender_faction", "attacker_faction", "phase", "source", "bodies", "structures", "vehicles", "flights", "work", "routes", "arrivals", "capture", "source_sha256", "resolution"]

const SiegeCheckpoint = preload("res://scripts/terrain_lab/site_region_checkpoint.gd")


static func _siege_hash(value: Variant) -> String:
	return Marshalls.raw_to_base64(var_to_bytes(SiegeCheckpoint.wire(_siege_order(value)))).sha256_text()

## The original siege snapshot is compared across a selected reopen. Saved
## Sites come back through the Store's JSON reader, which can move a fractional
## binary64 by one ulp (a decayed knockout 0x40cc1f7851eb8526 reads back as
## ...25), while the Slot keeps the snapshot as computed. The snapshot builder
## therefore takes every fractional number of the stored snapshot and of each
## fresh candidate in its persisted form: the Store's own writer->reader round
## trip (SiteRuntime.json_stable_seconds), which one more round trip does not
## change. A restored body and the body it was saved from then give the same
## snapshot exactly when their saved forms are equal. Integral values in the
## exact-integer range are already persisted exactly; the source stamp keeps
## the exact clock. Only the snapshot builder uses this domain.
static func _siege_persisted(value: Variant) -> Variant:
	if value is float:
		if not is_finite(value) or value == floorf(value) and absf(value) < 9007199254740992.0: return value
		return SiteRuntime.json_stable_seconds(value)
	if value is Dictionary:
		var mapped: Dictionary = {}
		for key: Variant in value: mapped[key] = _siege_persisted(value[key])
		return mapped
	if value is Array:
		var listed: Array = []
		for entry: Variant in value: listed.append(_siege_persisted(entry))
		return listed
	return value

static func _siege_persisted_hash(value: Variant) -> String:
	return _siege_hash(_siege_persisted(value))

static func _siege_order(value: Variant) -> Variant:
	if value is Dictionary:
		var keys: Array = value.keys()
		keys.sort_custom(func(left: Variant, right: Variant) -> bool: return var_to_bytes(SiegeCheckpoint.wire(left)).hex_encode() < var_to_bytes(SiegeCheckpoint.wire(right)).hex_encode())
		var ordered: Dictionary = {}
		for key: Variant in keys: ordered[key] = _siege_order(value[key])
		return ordered
	if value is Array:
		var ordered: Array = []
		for entry: Variant in value: ordered.append(_siege_order(entry))
		return ordered
	return value

static func _siege_legacy_hash(value: Variant) -> String:
	return JSON.stringify(SiegeCheckpoint._hash_numbers(SiegeCheckpoint.wire(value)), "", true, true).sha256_text()


static func validate_siege_metadata(value: Variant) -> Dictionary:
	if not value is Dictionary or value.size() != SIEGE_FIELDS.size(): return _fail("INVALID_SIEGE_SOURCE")
	for field: String in SIEGE_FIELDS:
		if not value.has(field): return _fail("INVALID_SIEGE_SOURCE")
	if not SiegeCheckpoint.integer(value.version, 1) or int(value.version) not in [1, SIEGE_VERSION] or value.phase not in SIEGE_PHASES or not value.center_id is String or value.center_id.is_empty() \
		or not SiegeCheckpoint.integer(value.defender_faction) or not SiegeCheckpoint.integer(value.attacker_faction) \
		or int(value.defender_faction) == int(value.attacker_faction) or value.resolution != "original_exact_gd":
		return _fail("INVALID_SIEGE_SOURCE")
	for field: String in ["source", "bodies", "structures", "vehicles", "flights", "work", "routes", "arrivals", "capture"]:
		if not value[field] is Dictionary or value[field].size() > 65536: return _fail("INVALID_SIEGE_SOURCE")
	var source: Dictionary = value.source
	if source.size() != 9 or not source.get("owner") is String or source.owner.is_empty() \
		or not SiegeCheckpoint.integer(source.get("generation")) or not SiegeCheckpoint.integer(source.get("runtime_revision")) \
		or not SiegeCheckpoint.time(source.get("game_seconds")) or not SiegeCheckpoint.time(source.get("action_seconds")) \
		or not source.get("fire_epoch") is String or source.fire_epoch.is_empty() or not SiegeCheckpoint.integer(source.get("fire_sequence")) \
		or not SiegeCheckpoint.integer(source.get("navigation_revision")) or not SiegeCheckpoint.integer(source.get("environment_revision")):
		return _fail("INVALID_SIEGE_SOURCE")
	var references: Dictionary = _validate_siege_references(value)
	if not references.ok: return references
	if not value.source_sha256 is String or value.source_sha256 != _siege_source_hash(value): return _fail("INVALID_SIEGE_SOURCE")
	return {"ok": true}


static func _siege_cell(value: Variant) -> bool:
	return value is Array and value.size() == 2 and SiegeCheckpoint.integer(value[0], -1) and SiegeCheckpoint.integer(value[1], -1)


static func _siege_digest(value: Variant) -> bool:
	if not value is String or value.length() != 64: return false
	for offset: int in value.length():
		if not "0123456789abcdef".contains(value.substr(offset, 1)): return false
	return true


static func _validate_siege_references(value: Dictionary) -> Dictionary:
	for key: Variant in value.bodies:
		var body: Variant = value.bodies[key]
		if not key is String or not body is Dictionary or body.size() != 15 or not SiegeCheckpoint.integer(body.get("person_id"), 1) or key != str(int(body.person_id)) \
			or not SiegeCheckpoint.integer(body.get("faction")) or int(body.faction) not in [int(value.attacker_faction), int(value.defender_faction)] \
			or not _siege_cell(body.get("cell")) or not _siege_cell(body.get("moving_from")) or not _siege_cell(body.get("moving_to")) \
			or not SiegeCheckpoint.integer(body.get("surface")) or not SiegeCheckpoint.time(body.get("hp")) or not SiegeCheckpoint.time(body.get("ko")) \
			or not body.get("captive") is bool or not body.get("moving") is bool or not SiegeCheckpoint.integer(body.get("team_id"), -1) \
			or not SiegeCheckpoint.integer(body.get("order"), -1) or not SiegeCheckpoint.integer(body.get("commander"), -1) \
			or not body.get("role") is String or not _siege_digest(body.get("holder_sha256")): return _fail("INVALID_SIEGE_REFERENCE")
	for key: Variant in value.structures:
		var feature: Variant = value.structures[key]
		if not key is String or key.is_empty() or not feature is Dictionary or feature.size() != 4 or not feature.get("kind") is String \
			or not SiegeCheckpoint.integer(feature.get("owner_faction"), -1) or not _siege_digest(feature.get("sha256")) or not feature.get("parts") is Dictionary: return _fail("INVALID_SIEGE_REFERENCE")
		for part: Variant in feature.parts:
			if not part is String or part.is_empty() or not _siege_digest(feature.parts[part]): return _fail("INVALID_SIEGE_REFERENCE")
	if not value.structures.has(str(value.center_id)) or str(value.structures[str(value.center_id)].kind) != "settlement_center": return _fail("INVALID_SIEGE_REFERENCE")
	for key: Variant in value.vehicles:
		var vehicle: Variant = value.vehicles[key]
		if not key is String or key.is_empty() or not vehicle is Dictionary or vehicle.size() != 6 or not SiteRuntime.SIEGE_DEFINITIONS.has(vehicle.get("kind")) \
			or not SiegeCheckpoint.integer(vehicle.get("team_id"), 1) or not SiegeCheckpoint.integer(vehicle.get("faction"), -1) \
			or not _siege_digest(vehicle.get("sha256")) or not SiegeCheckpoint.integer(vehicle.get("holder_version")) or not SiegeCheckpoint.integer(vehicle.get("attack_seq")): return _fail("INVALID_SIEGE_REFERENCE")
	for key: Variant in value.flights:
		var flight: Variant = value.flights[key]
		if not key is String or key.is_empty() or not flight is Dictionary or flight.size() != 6 or not flight.get("source_vehicle") is String or flight.source_vehicle.is_empty() \
			or not SiteRuntime.SIEGE_DEFINITIONS.has(flight.get("kind")) or not SiegeCheckpoint.integer(flight.get("faction")) \
			or not SiegeCheckpoint.integer(flight.get("rule_version"), 1) or int(flight.rule_version) != 1 or not _siege_cell(flight.get("source_cell")) \
			or not _siege_digest(flight.get("sha256")): return _fail("INVALID_SIEGE_REFERENCE")
	for key: Variant in value.work:
		if not key is String or not _siege_digest(value.work[key]) or not ((key.begins_with("feature:") and value.structures.has(key.trim_prefix("feature:"))) or (key.begins_with("vehicle:") and value.vehicles.has(key.trim_prefix("vehicle:")))): return _fail("INVALID_SIEGE_REFERENCE")
	for key: Variant in value.routes:
		var route: Variant = value.routes[key]
		if not value.bodies.has(key) or not route is Dictionary or route.size() != 4 or not _siege_cell(route.get("source")) or not _siege_cell(route.get("goal")) \
			or not _siege_digest(route.get("path_sha256")) or not SiegeCheckpoint.integer(route.get("steps"), 1): return _fail("INVALID_SIEGE_REFERENCE")
	for key: Variant in value.arrivals:
		var arrival: Variant = value.arrivals[key]
		if not key is String or key.is_empty() or not arrival is Dictionary or arrival.size() != 5 or not _siege_cell(arrival.get("origin")) \
			or not arrival.get("plan_path") is String or arrival.plan_path.is_empty() or not _siege_digest(arrival.get("plan_sha256")) \
			or not SiegeCheckpoint.time(arrival.get("arrival_game_seconds")) or not _siege_digest(arrival.get("mapping_sha256")): return _fail("INVALID_SIEGE_REFERENCE")
	var capture: Dictionary = value.capture
	if capture.size() != 4 or not capture.get("sample") is Dictionary or capture.sample.size() != 3 or not SiegeCheckpoint.integer(capture.sample.get("owner")) \
		or not SiegeCheckpoint.integer(capture.sample.get("attacker"), -1) or not SiegeCheckpoint.integer(capture.sample.get("leader"), -1) \
		or not _siege_digest(capture.get("fall_sha256")) or not SiegeCheckpoint.time(capture.get("elapsed_action")) or not SiegeCheckpoint.time(capture.get("unconsumed_game_seconds")): return _fail("INVALID_SIEGE_REFERENCE")
	return {"ok": true}


static func _siege_source_hash(value: Dictionary) -> String:
	var fields := {}
	for field: String in SIEGE_FIELDS:
		if field != "source_sha256": fields[field] = value[field]
	return _siege_legacy_hash(fields) if int(value["version"]) == 1 else _siege_hash(fields)


static func _siege_person_ref(lab: TerrainLab, identity: int) -> Dictionary:
	var person: Dictionary = lab.site_controller.person_actions._person(identity, false)
	if person.is_empty(): return {}
	var cell: Vector2i = person.cell
	var owner: Variant = person.owner
	var unit := int(person.unit)
	var ref := {"person_id": identity, "faction": int(person.faction), "cell": [cell.x, cell.y],
		"surface": int(lab.terrain.effective_height(cell)), "hp": float(person.hp), "ko": float(person.ko),
		"captive": bool(person.captive), "moving": bool(person.moving), "team_id": int(owner.team_id) if owner is TerrainArmy else -1,
		"holder_sha256": _siege_persisted_hash(person.get("holder", {})), "role": SiteSettlement._role(person)}
	if owner is TerrainArmy:
		ref["order"] = int(owner.combat_order)
		ref["commander"] = int(owner.combat_identity(owner.current_commander)) if owner.current_commander >= 0 else -1
		ref["moving_from"] = [owner.cells[unit].x, owner.cells[unit].y]
		ref["moving_to"] = [owner.moving_to[unit].x, owner.moving_to[unit].y]
	else:
		ref["order"] = -1
		ref["commander"] = -1
		ref["moving_from"] = [owner.movement_from_cell.x, owner.movement_from_cell.y]
		ref["moving_to"] = [cell.x, cell.y]
	return ref

## A path is the actual original person's source/goal-purpose navigation proof.
## Every edge uses the SAME TerrainData and tower/vehicle person-step guard.
## It proves topology only; original movement/occupancy still admits each step.


static func original_siege_path(lab: TerrainLab, identity: int, goal: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var person: Dictionary = lab.site_controller.person_actions._person(identity, false)
	if person.is_empty() or not lab.terrain.is_walkable(goal): return result
	var source: Vector2i = person.cell
	if source == goal:
		result.append(source)
		return result
	var blocked := func(from: Vector2i, to: Vector2i) -> bool:
		return lab.site_controller.vehicles.blocks_person_step(identity, source, from, to, goal)
	return lab.terrain.path_between(source, goal, Callable(), blocked)


static func prepare_original_siege(lab: TerrainLab, battle: Dictionary = {}) -> Dictionary:
	if not is_instance_valid(lab) or lab.terrain == null or lab.site_controller == null or lab.site_controller.region_slot == null:
		return _fail("MISSING_ORIGINAL_SIEGE_OWNER")
	var slot: RegionSaveSlot = lab.site_controller.region_slot
	var data := lab.terrain
	if lab._region_bound_data != data or slot._region_bound_original_lab(data) != lab: return _fail("STALE_ORIGINAL_SIEGE_OWNER")
	if lab.crowd_site != null and lab.crowd_site.active: return _fail("REGION_BACKEND_UNADMITTED")
	var settlement := SiteSettlement.record(data)
	var center := SiteSettlement.center(data)
	if settlement.is_empty() or center.is_empty() or int(settlement.level) <= 0: return {"ok": true, "present": false}
	var existing: Dictionary = battle.get("siege", {})
	if not existing.is_empty():
		var valid := validate_siege_metadata(existing)
		if not valid.ok: return valid
		if str(existing.source.owner) != str(data.site.id) or str(existing.center_id) != str(settlement.center_id): return _fail("SIEGE_CENTER_CHANGED")
	var defender := int(existing.get("defender_faction", settlement.owner_faction))
	var factions := {}
	var bodies := {}
	var scope := scoped_controlled_person(lab)
	if not scope.ok: return scope
	var controlled := int(scope.person_id)
	var identities: Array[int] = []
	for actor: TerrainTestCharacter in lab.combat_actors:
		if lab.actor_present(actor) and not actor.site_exited and actor.person_id != controlled: identities.append(actor.person_id)
	for team: TerrainArmy in lab.combat_armies:
		if not team.combat_enabled: continue
		for unit: int in team.combat_units.size():
			if team.member_gone(unit): continue
			var identity := team.combat_identity(unit)
			if identity != controlled: identities.append(identity)
	identities.sort()
	for identity: int in identities:
		if identity <= 0 or bodies.has(str(identity)): return _fail("INVALID_ORIGINAL_SIEGE_ROSTER")
		var ref := _siege_person_ref(lab, identity)
		if ref.is_empty(): return _fail("INVALID_ORIGINAL_SIEGE_ROSTER")
		bodies[str(identity)] = ref
		if not factions.has(int(ref.faction)): factions[int(ref.faction)] = []
		factions[int(ref.faction)].append(identity)
	var attacker := int(existing.get("attacker_faction", -1))
	if attacker < 0:
		var hostile := factions.keys()
		hostile.erase(defender)
		if hostile.size() != 1 or int(hostile[0]) < 0: return {"ok": true, "present": false, "reason": "EXACT_FACTION_TOPOLOGY"}
		attacker = int(hostile[0])
	for faction: int in factions:
		if faction not in [attacker, defender]: return {"ok": true, "present": false, "reason": "EXACT_FACTION_TOPOLOGY"}
	var structures := {}
	var work := {}
	var feature_keys: Array = data.site.features.keys()
	feature_keys.sort()
	for key: String in feature_keys:
		var feature: Dictionary = data.site.features[key]
		var geometry := SiteRuntime.feature_geometry(data, feature)
		var parts := {}
		for part: String in geometry.parts: parts[part] = _siege_persisted_hash(geometry.parts[part])
		structures[key] = {"kind": str(feature.kind), "owner_faction": int(feature.get("owner_faction", -1)),
			"sha256": _siege_persisted_hash(feature), "parts": parts}
		if not feature.get("repair", {}).is_empty() or str(feature.get("stage", "")) != "complete": work["feature:" + key] = _siege_persisted_hash(feature)
	var vehicles := {}
	var breach := false
	var activity := false
	var vehicle_keys: Array = data.site.vehicles.keys()
	vehicle_keys.sort()
	for key: String in vehicle_keys:
		var vehicle: Dictionary = data.site.vehicles[key]
		if not lab.site_controller.vehicles.is_siege(vehicle): continue
		var team: Variant = lab.site_controller.vehicles._siege_team(vehicle)
		# A spent source may be disabled or its original crew no longer ready.
		# Read the SAME existing team reference; this grants no command/crew duty.
		var faction: int = int(team.faction_id) if team != null else lab._siege_faction(vehicle)
		vehicles[key] = {"kind": str(vehicle.kind), "team_id": int(vehicle.team_id), "faction": faction,
			"sha256": _siege_persisted_hash(vehicle), "holder_version": int(vehicle.holder.version), "attack_seq": int(vehicle.next_attack_seq)}
		if not vehicle.build.is_empty() or not vehicle.repair.is_empty(): work["vehicle:" + key] = _siege_persisted_hash([vehicle.build, vehicle.repair])
		if faction != attacker: continue
		activity = true
		var target: Dictionary = vehicle.action.get("target", vehicle.command.get("target", {}))
		var target_feature: Dictionary = data.site.features.get(str(target.get("feature_id", "")), {})
		if str(target.get("type", "")) == "structure" and int(target_feature.get("owner_faction", -1)) == defender \
			and (str(vehicle.command.get("type", "")) == "attack" or not vehicle.action.is_empty()) \
			and lab.siege_fire_preview(vehicle, target, false).get("ok", false): breach = true
	var flights := {}
	for flight: Dictionary in lab.siege_projectiles:
		var key := str(flight.get("source_vehicle", ""))
		var attack_id := str(flight.get("attack_id", ""))
		if attack_id.is_empty() or flights.has(attack_id): return _fail("INVALID_ORIGINAL_SIEGE_FLIGHT")
		var source_cell: Vector2i = flight.get("source_cell", Vector2i(-1, -1))
		# Original flight snapshot owns its paid rule/faction/geometry/attack ID.
		# Legal wreck clearing may erase the source vehicle while this continues.
		flights[attack_id] = {"source_vehicle": key, "kind": str(flight.get("kind", "")), "faction": int(flight.get("faction", -1)),
			"rule_version": int(flight.get("rule_version", -1)), "source_cell": [source_cell.x, source_cell.y], "sha256": _siege_persisted_hash(flight)}
		if int(flight.get("faction", -1)) == attacker:
			activity = true
			breach = breach or str(existing.get("phase", "")) == "breach"
	var arrivals := {}
	for token: String in slot.region_registry().parties:
		var ref: Dictionary = slot.region_registry().parties[token]
		if str(ref.get("phase", "")) != "entered" or str(ref.get("destination_site", "")) != str(data.site.id): continue
		var own_arrival := false
		for local: Variant in ref.get("arrival_mapping", {}).get("maps", {}).get("person", {}).values():
			if factions.get(attacker, []).has(int(local)): own_arrival = true
		if not own_arrival: continue
		arrivals[token] = {"origin": ref.get("origin", []).duplicate(), "plan_path": str(ref.get("plan_path", "")),
			"plan_sha256": str(ref.get("plan_sha256", "")), "arrival_game_seconds": float(ref.get("arrival_game_seconds", 0.0)),
			"mapping_sha256": _siege_persisted_hash(ref.get("arrival_mapping", {}))}
		activity = true
	var capture := SiteSettlement.capture_sample(lab)
	var fall: Dictionary = settlement.fall_record
	var paths := {}
	var assault := false
	var goals: Array = SiteSettlement.capture_zone(data).keys()
	goals.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return data.index(a) < data.index(b))
	for identity: int in factions.get(attacker, []):
		var person: Dictionary = lab.site_controller.person_actions._person(identity, false)
		if not SiteSettlement._fit(person) or SiteSettlement._role(person) == "civilian" or lab.site_controller.vehicles.is_siege_crew(identity): continue
		if not person.owner is TerrainArmy: continue
		var original_attack: bool = person.owner.combat_order == TerrainArmy.CombatOrder.ATTACK
		var original_advance: bool = person.owner.combat_order == TerrainArmy.CombatOrder.MOVE and SiteSettlement.capture_zone(data).has(person.owner.combat_goal)
		if not original_attack and not original_advance: continue
		activity = true
		var prior: Dictionary = existing.get("routes", {}).get(str(identity), {})
		var source_cell: Vector2i = person.cell
		if not prior.is_empty() and prior.get("source", []) == [source_cell.x, source_cell.y] \
			and existing.get("vehicles", {}) == vehicles \
			and int(existing.get("source", {}).get("navigation_revision", -1)) == int(data.navigation_revision) \
			and int(existing.get("source", {}).get("environment_revision", -1)) == int(data.environment_revision):
			paths[str(identity)] = prior.duplicate(true)
			assault = true
			continue
		for goal: Vector2i in goals:
			var path := original_siege_path(lab, identity, goal)
			if path.is_empty(): continue
			var first: Vector2i = person.cell
			paths[str(identity)] = {"source": [first.x, first.y], "goal": [goal.x, goal.y], "path_sha256": _siege_hash(path), "steps": path.size()}
			assault = true
			break
	if not activity and existing.is_empty(): return {"ok": true, "present": false}
	var phase := "capture" if int(capture.get("attacker", -1)) == attacker else ("assault" if assault else ("breach" if breach else "siege"))
	if int(settlement.owner_faction) != defender:
		if int(settlement.owner_faction) != attacker or int(fall.last_fall.get("from", -1)) != defender or int(fall.last_fall.get("to", -1)) != attacker:
			return _fail("SIEGE_CENTER_CHANGED")
		phase = "finished"
	var source := {"owner": str(data.site.id), "generation": int(slot._marker.generation), "runtime_revision": int(slot.region_registry().revision),
		"game_seconds": float(slot.control.logical_game_seconds), "action_seconds": float(slot.control.fire_clock.action_seconds),
		"fire_epoch": str(slot.control.fire_clock.epoch), "fire_sequence": int(slot.control.fire_clock.sequence),
		"navigation_revision": int(data.navigation_revision), "environment_revision": int(data.environment_revision)}
	var value := {"version": SIEGE_VERSION, "center_id": str(settlement.center_id), "defender_faction": defender,
		"attacker_faction": attacker, "phase": phase, "source": source, "bodies": bodies, "structures": structures,
		"vehicles": vehicles, "flights": flights, "work": work, "routes": paths, "arrivals": arrivals,
		"capture": {"sample": capture, "fall_sha256": _siege_persisted_hash(fall), "elapsed_action": float(lab.site_controller._settlement_elapsed),
			"unconsumed_game_seconds": float(lab.site_controller._settlement_game_seconds)}, "source_sha256": "", "resolution": "original_exact_gd"}
	# Every snapshot field except its exact source stamp is kept in the persisted
	# number domain (_siege_persisted), for the stored snapshot and the candidate alike.
	for field: String in value.keys():
		if field != "source": value[field] = _siege_persisted(value[field])
	value.source_sha256 = _siege_source_hash(value)
	var valid := validate_siege_metadata(value)
	if not valid.ok: return valid
	return {"ok": true, "present": true, "siege": value,
		"attackers": factions.get(attacker, []).duplicate(), "defenders": factions.get(defender, []).duplicate()}

