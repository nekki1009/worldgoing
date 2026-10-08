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
static func resolve_people(lab: TerrainLab, battle: Dictionary, eligibility_query: Callable = Callable()) -> Dictionary:
	if lab == null or lab.terrain == null or str(lab.terrain.site.get("id", "")) != str(battle.get("site_id", "")):
		return _fail("WRONG_BATTLE_SITE")
	if lab.crowd_site != null and lab.crowd_site.active: return _fail("UNSUPPORTED_BACKEND")
	var original_refs := {}
	var values := {}
	var controlled := int(lab.controlled_person_id())
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
	for seat: Dictionary in owner.team_offices().positions:
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
	if target_id == int(lab.controlled_person_id()) or source_id == int(lab.controlled_person_id()): return _fail("PLAYER_BARRIER")
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
	if int(effect.person_id) == int(lab.controlled_person_id()): return _fail("PLAYER_BARRIER")
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
