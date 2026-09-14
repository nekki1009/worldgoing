class_name SiteCombatRules
extends RefCounted
## Shared numerical rules. Callers own people, contact geometry and simulation time.
## Initial balance values, not measured final balance (SITE_COMBAT_DESIGN D68–79).

const STUN_LIMIT := 100.0
const STUN_GRACE := 3.0
const STUN_RECOVERY := 10.0
const KNOCKOUT_SECONDS := 30.0
const GUARD_TRANSITION := 0.15
const GUARD_BREAK_SECONDS := 0.4
const GUARD_BREAK_IMPACT := 30.0

# Adjacent exchanges are an explicitly different combat policy, not a geometry
# approximation. Original owners supply attributes and apply the returned effects.
const EXCHANGE_ROUND_SECONDS := 1.0
const EXCHANGE_DRAW_MARGIN := 5.0
const EXCHANGE_BIG_MARGIN := 25.0
const EXCHANGE_ROLL_LIMIT := 10.0
const EXCHANGE_TRAINING_WEIGHT := 0.2
const EXCHANGE_FATIGUE_WEIGHT := 0.2
const EXCHANGE_MORALE_WEIGHT := 0.1
const EXCHANGE_SURROUND_SECTOR_PENALTY := 8.0
const EXCHANGE_SURROUND_LIMIT := 24.0
const EXCHANGE_SMALL_STUN := 8.0
const EXCHANGE_BIG_STUN := 18.0
const EXCHANGE_SMALL_STAGGER := 0.35
const EXCHANGE_BIG_STAGGER := 0.65
const EXCHANGE_DRAW_HOLD := 0.3
const EXCHANGE_FATIGUE := 0.5
const EXCHANGE_BIG_LOSER_FATIGUE := 0.5
const EXCHANGE_SKILL_BONUS := 15.0
const EXCHANGE_POWER_STUN := 10.0
const EXCHANGE_SKILL_COOLDOWN := 8.0
const RANGED_MAX_RANGE := 10.0

static func ranged_profile(weapon: String) -> Dictionary:
	match weapon:
		"bow_01":
			return {"ammo": "arrow", "range": 8.0, "cooldown": 2.0, "hold": 0.25, "speed": 10.0}
		"crossbow_01":
			return {"ammo": "bolt", "range": RANGED_MAX_RANGE, "cooldown": 3.0, "hold": 0.4, "speed": 14.0}
	return {}

static func ranged_in_range(source: Vector2i, goal: Vector2i, maximum_range: float) -> bool:
	var offset := goal - source
	return is_finite(maximum_range) and maximum_range > 1.0 and maximum_range <= RANGED_MAX_RANGE \
		and absi(offset.x) + absi(offset.y) > 1 and Vector2(offset).length_squared() <= maximum_range * maximum_range

static func ranged_result(shooter: Dictionary, defender: Dictionary, distance: float, roll: float) -> Dictionary:
	# Target ownership/faction, ammunition and the captured flight event belong to
	# callers. In particular, a friendly occupant receives the same numerical rule.
	var result := {"kind": "miss", "hp": 0.0, "stun": 0.0, "stagger": 0.0,
		"knockback": false, "guard_break": false, "chance": 0.0}
	if not is_finite(distance) or distance <= 1.0 or distance > RANGED_MAX_RANGE \
		or not is_finite(roll) or roll < 0.0 or roll >= 100.0:
		return result
	var power := str(shooter.get("skill", "")) == "power"
	var chance := 65.0 + (clampf(float(shooter.get("ability", 50.0)), 0.0, 100.0) - 50.0) * 0.5 \
		+ clampf(float(shooter.get("training", 0.0)), 0.0, 100.0) * 0.1 \
		- clampf(float(shooter.get("fatigue", 0.0)), 0.0, 100.0) * 0.25 \
		- maxf(0.0, distance - 2.0) * 4.0 + (EXCHANGE_SKILL_BONUS if power else 0.0) \
		- (20.0 if bool(defender.get("moving", false)) else 0.0) \
		- (15.0 if bool(defender.get("shield", false)) else 0.0) \
		- maxf(0.0, float(defender.get("armor_stab", 0.0))) * 0.2 \
		- (20.0 if bool(defender.get("facility", false)) else 0.0) \
		- (EXCHANGE_SKILL_BONUS if str(defender.get("skill", "")) == "brace" else 0.0)
	chance = clampf(chance, 5.0, 95.0)
	result.chance = chance
	if roll >= chance:
		return result
	var hit := roll < chance * 0.6
	result.kind = "hit" if hit else "graze"
	result.hp = 2.0 if hit else 1.0
	result.stun = (12.0 if hit else 6.0) + (EXCHANGE_POWER_STUN if power else 0.0)
	result.stagger = 0.35 if hit else 0.2
	return result

static func ranged_cells(source: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	# Exact integer boundary comparisons trace center-to-center supercover. At a
	# corner both side cells precede the diagonal cell; this is NOT a walking path.
	var cells: Array[Vector2i] = []
	var offset := goal - source
	if source == goal or Vector2(offset).length_squared() > RANGED_MAX_RANGE * RANGED_MAX_RANGE:
		return cells
	var nx := absi(offset.x)
	var ny := absi(offset.y)
	var dx := Vector2i(signi(offset.x), 0)
	var dy := Vector2i(0, signi(offset.y))
	var ix := 0
	var iy := 0
	var current := source
	while ix < nx or iy < ny:
		var x_boundary := (2 * ix + 1) * ny
		var y_boundary := (2 * iy + 1) * nx
		if x_boundary == y_boundary:
			cells.append(current + dx)
			cells.append(current + dy)
			current += dx + dy
			ix += 1
			iy += 1
		elif x_boundary < y_boundary:
			current += dx
			ix += 1
		else:
			current += dy
			iy += 1
		cells.append(current)
	return cells

static func ranged_line_clear(data: TerrainData, source: Vector2i, goal: Vector2i) -> bool:
	if data == null or not data.contains(source) or not data.contains(goal):
		return false
	var cells := ranged_cells(source, goal)
	if cells.is_empty():
		return false
	var covered := {source: true}
	for cell: Vector2i in cells:
		covered[cell] = true
	var offset := goal - source
	var directions: Array[Vector2i] = [Vector2i(signi(offset.x), 0), Vector2i(0, signi(offset.y))]
	# Every touched forward edge uses the original terrain owner. At an exact
	# corner all four edges of the two possible routes must be clear.
	for cell: Vector2i in covered:
		for direction: Vector2i in directions:
			var next := cell + direction
			if direction != Vector2i.ZERO and covered.has(next) and not data.can_attack_across(cell, next):
				return false
	return true

static func exchange_score(person: Dictionary) -> float:
	var sectors := clampi(int(person.get("encirclement", 1)) - 1, 0, 3)
	var surround := minf(float(sectors) * EXCHANGE_SURROUND_SECTOR_PENALTY, EXCHANGE_SURROUND_LIMIT)
	var skill_bonus := EXCHANGE_SKILL_BONUS if str(person.get("skill", "")) in ["brace", "power"] else 0.0
	return clampf(float(person.get("ability", 50.0)), 0.0, 100.0) \
		+ clampf(float(person.get("training", 0.0)), 0.0, 100.0) * EXCHANGE_TRAINING_WEIGHT \
		+ (clampf(float(person.get("morale", 100.0)), 0.0, 100.0) - 100.0) * EXCHANGE_MORALE_WEIGHT \
		- clampf(float(person.get("fatigue", 0.0)), 0.0, 100.0) * EXCHANGE_FATIGUE_WEIGHT \
		+ float(person.get("armorbonus", 0.0)) + float(person.get("facility", 0.0)) \
		+ skill_bonus - surround

static func exchange_result(a: Dictionary, b: Dictionary, roll: float = 0.0) -> Dictionary:
	# One bounded, caller-owned roll is added to A's margin. Swap A/B and negate
	# that same roll to obtain the mirrored result; this helper has no RNG state.
	var score_a := exchange_score(a)
	var score_b := exchange_score(b)
	var margin := score_a - score_b + clampf(roll, -EXCHANGE_ROLL_LIMIT, EXCHANGE_ROLL_LIMIT)
	var result := {"winner": 0, "kind": "draw", "hp": 0.0, "stun": 0.0, "stagger": 0.0,
		"hold": EXCHANGE_DRAW_HOLD, "knockback": false, "guard_break": false,
		"fatigue_a": EXCHANGE_FATIGUE, "fatigue_b": EXCHANGE_FATIGUE,
		"score_a": score_a, "score_b": score_b, "margin": margin}
	if absf(margin) <= EXCHANGE_DRAW_MARGIN:
		return result
	var a_wins := margin > 0.0
	var big := absf(margin) >= EXCHANGE_BIG_MARGIN
	var winner: Dictionary = a if a_wins else b
	var loser: Dictionary = b if a_wins else a
	result.winner = 1 if a_wins else -1
	result.kind = "big" if big else "small"
	result.hp = 2.0 if big else 1.0
	result.stun = (EXCHANGE_BIG_STUN if big else EXCHANGE_SMALL_STUN) \
		+ (EXCHANGE_POWER_STUN if str(winner.get("skill", "")) == "power" else 0.0)
	result.stagger = EXCHANGE_BIG_STAGGER if big else EXCHANGE_SMALL_STAGGER
	result.hold = 0.0
	result.knockback = big and str(loser.get("skill", "")) != "brace"
	if big:
		result["fatigue_b" if a_wins else "fatigue_a"] += EXCHANGE_BIG_LOSER_FATIGUE
	return result

static func diminishing(value: float, cap: float) -> float:
	var nonnegative := maxf(0.0, value)
	return cap * nonnegative / (100.0 + nonnegative)

static func attack_profile(clip: StringName) -> Dictionary:
	var kind := "slash"
	if clip in [&"attack_spear", &"ride_thrust", &"attack_dagger", &"attack_bow", &"attack_crossbow"]:
		kind = "stab"
	elif clip in [&"attack_hammer", &"attack_unarmed"]:
		kind = "blunt"
	return {"kind": kind, "power": 30.0 if clip in [&"attack_jump_heavy", &"attack_axe", &"attack_hammer"] else 20.0,
		"impact": {"slash": 12.0, "stab": 8.0, "blunt": 35.0}[kind],
		"ranged": clip in [&"attack_bow", &"attack_crossbow"], "pierces_people": false}

static func armor_profile(item: String) -> Dictionary:
	# One profile per equipped item, never per triangle or rendered submesh.
	if "mingguang" in item or "steel" in item:
		return {"slash": 35.0, "stab": 25.0, "blunt": 15.0, "cushion": 10.0}
	if "iron" in item:
		return {"slash": 25.0, "stab": 18.0, "blunt": 10.0, "cushion": 6.0}
	if "leather" in item:
		return {"slash": 12.0, "stab": 6.0, "blunt": 4.0, "cushion": 4.0}
	if item.begins_with("outfit_"):
		return {"slash": 1.0, "stab": 0.0, "blunt": 0.0, "cushion": 2.0}
	return {"slash": 0.0, "stab": 0.0, "blunt": 0.0, "cushion": 0.0}

static func damage(profile: Dictionary, armor: float, cushion: float, body_index: int, shield_contact: bool = false) -> Dictionary:
	var impact := maxf(0.0, float(profile.impact))
	var broken := shield_contact and impact >= GUARD_BREAK_IMPACT
	var hp_multiplier := 1.5 if body_index == 1 else (1.0 if body_index == 0 else 0.75)
	var stun_multiplier := 1.5 if body_index == 1 else 1.0
	if shield_contact:
		return {"hp": 0.0, "stun": maxf(0.0, impact * (0.5 if broken else 0.25) - maxf(0.0, cushion)), "guard_break": broken}
	return {"hp": maxf(0.0, float(profile.power) - maxf(0.0, armor)) * hp_multiplier,
		"stun": maxf(0.0, impact - maxf(0.0, cushion)) * stun_multiplier, "guard_break": false}

static func terrain_line_clear(data: TerrainData, source: Vector2i, goal: Vector2i) -> bool:
	if data == null or not data.contains(source) or not data.contains(goal):
		return false
	var cell := source
	while cell != goal:
		var dx := Vector2i(signi(goal.x - cell.x), 0)
		var dy := Vector2i(0, signi(goal.y - cell.y))
		if dx != Vector2i.ZERO:
			if not data.can_attack_across(cell, cell + dx):
				return false
			cell += dx
		if dy != Vector2i.ZERO:
			if not data.can_attack_across(cell, cell + dy):
				return false
			cell += dy
	return true
