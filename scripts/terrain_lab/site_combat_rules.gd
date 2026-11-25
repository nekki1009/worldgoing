class_name SiteCombatRules
extends RefCounted
## Shared numerical rules. Callers own people, contact geometry and simulation time.
## Initial balance values, not measured final balance (SITE_COMBAT_DESIGN D68–79).

const STUN_LIMIT := 100.0
const STUN_GRACE := 3.0
const STUN_RECOVERY := 10.0
const LEGACY_KNOCKOUT_ACTION_SECONDS := 30.0
const KNOCKOUT_GAME_SECONDS := 4.0 * 3600.0
const RESCUED_KNOCKOUT_GAME_SECONDS := 3600.0
const GUARD_TRANSITION := 0.15
const GUARD_BREAK_SECONDS := 0.4
const GUARD_BREAK_IMPACT := 30.0
## Bare hands are a blunt attack, but stun far less than a hammer's 35 (2026-11-25): with the hammer's value ten unarmed
## residents and two soldiers knocked out nine and ten armed bandits in the measured far raids (a sword stuns 12, and
## draws stun both sides). At 14 an unarmed resident counts about half a soldier with sword, leather and shield, the
## coefficient of residents who fight in the off-screen battle rules (10A.3). Adjustable.
const UNARMED_IMPACT := 14.0

# Adjacent exchanges are an explicitly different combat policy, not a geometry
# approximation. Original owners supply attributes and apply the returned effects.
const EXCHANGE_ROUND_SECONDS := 1.0
const EXCHANGE_DRAW_MARGIN := 5.0
const EXCHANGE_BIG_MARGIN := 25.0
const EXCHANGE_ROLL_LIMIT := 10.0
const EXCHANGE_TRAINING_WEIGHT := 0.2
const EXCHANGE_FATIGUE_WEIGHT := 0.2
const EXCHANGE_MORALE_WEIGHT := 0.1
const EXCHANGE_SMALL_STAGGER := 0.35
const EXCHANGE_BIG_STAGGER := 0.65
const EXCHANGE_DRAW_HOLD := 0.3
const EXCHANGE_FATIGUE := 0.5
const EXCHANGE_BIG_LOSER_FATIGUE := 0.5
const EXCHANGE_SKILL_BONUS := 15.0
const EXCHANGE_POWER_STUN := 10.0
const EXCHANGE_SKILL_COOLDOWN := 8.0
const RANGED_MAX_RANGE := 10.0
const FIRE_RANGED_CONFIG_VERSION := "fire_ranged_v1"
const WeaponMaterials = preload("res://scripts/ui/weapon_materials.gd")

const BALLISTA := {"ammo": "siege_bolt", "minimum": 3.0, "range": 30.0, "speed": 20.0,
	"loading": 5.0, "aiming": 2.0, "recovering": 1.0, "budget": 100.0, "body_resistance": 40.0,
	"people_limit": 3, "power": 60.0, "impact": 35.0, "kind": "stab", "radius": 3.0}


static func siege_attack(kind: String = "ballista") -> Dictionary:
	match kind:
		"ballista":
			var result := BALLISTA.duplicate()
			result["projectile"] = "bolt"
			result["wood"] = 8.0
			result["stone"] = 2.0
			return result
		"traction_trebuchet":
			return {"ammo": "siege_stone", "minimum": 8.0, "range": 40.0, "speed": 10.0,
				"loading": 8.0, "aiming": 3.0, "recovering": 1.0, "power": 70.0, "impact": 80.0,
				"kind": "blunt", "projectile": "stone", "radius_cells": 0.25, "arc": 5.0,
				"scatter": 1.5, "wood": 50.0, "stone": 40.0}
		"counterweight_trebuchet":
			return {"ammo": "siege_stone", "minimum": 15.0, "range": 60.0, "speed": 10.0,
				"loading": 15.0, "aiming": 4.0, "recovering": 1.0, "power": 90.0, "impact": 100.0,
				"kind": "blunt", "projectile": "stone", "radius_cells": 0.375, "arc": 7.0,
				"scatter": 2.0, "wood": 100.0, "stone": 90.0}
		"ram":
			return {"ammo": "", "minimum": 0.0, "range": 1.0, "preparing": 2.0,
				"collision": 0.25, "recovering": 0.75, "power": 35.0, "impact": 60.0,
				"kind": "blunt", "projectile": "ram", "wood": 60.0, "stone": 6.0}
	return {}

static func siege_hit_profile(kind: String, remaining_budget: float = 100.0) -> Dictionary:
	if kind == "ballista": return siege_profile(remaining_budget)
	var rule := siege_attack(kind)
	if rule.is_empty(): return {}
	return {"kind": str(rule.kind), "power": float(rule.power), "impact": float(rule.impact),
		"ranged": kind != "ram", "siege": true}

static func siege_crew_multiplier(count: int, minimum: int = 1, standard: int = 2) -> float:
	if count < minimum: return 0.0
	if minimum == standard: return 1.0
	return clampf(0.5 + 0.5 * float(count - minimum) / float(standard - minimum), 0.5, 1.0)

static func siege_shield_resistance(asset: String) -> float:
	if "steel" in asset: return 55.0
	if "stone" in asset: return 35.0
	if "wood" in asset: return 25.0
	return 45.0 # Existing unqualified shield assets are iron.

static func siege_profile(remaining_budget: float) -> Dictionary:
	var ratio := clampf(remaining_budget / float(BALLISTA.budget), 0.0, 1.0)
	return {"kind": "stab", "power": float(BALLISTA.power) * ratio,
		"impact": float(BALLISTA.impact) * ratio, "ranged": true, "siege": true}

static func structure_damage(weapon: String, material: String, siege_kind: String = "") -> float:
	var rule := siege_attack(siege_kind) if not siege_kind.is_empty() else {}
	if not rule.is_empty(): return float(rule.stone if material == "stone" else rule.wood)
	return exchange_hp(weapon, "none") * (0.05 if material == "stone" else 0.25)

static func siege_in_range(origin: Vector2, goal: Vector2, facing: Vector2i, kind: String = "ballista") -> bool:
	var rule := siege_attack(kind)
	if rule.is_empty(): return false
	var offset := goal - origin
	var distance := offset.length()
	return distance + 0.000001 >= float(rule.minimum) and distance <= float(rule.range) + 0.000001 \
		and Vector2(facing).dot(offset.normalized()) + 0.000001 >= sqrt(0.5)

static func ranged_profile(weapon: String) -> Dictionary:
	match str(WeaponMaterials.family(StringName(weapon))):
		"bow_01":
			return {"ammo": "arrow", "range": 8.0, "cooldown": 2.0, "hold": 0.25, "speed": 10.0}
		"crossbow_01":
			return {"ammo": "bolt", "range": RANGED_MAX_RANGE, "cooldown": 3.0, "hold": 0.4, "speed": 14.0}
	return {}

static func ranged_in_range(source: Vector2i, goal: Vector2i, maximum_range: float) -> bool:
	var offset := goal - source
	return is_finite(maximum_range) and maximum_range > 1.0 and maximum_range <= RANGED_MAX_RANGE \
		and absi(offset.x) + absi(offset.y) > 1 and Vector2(offset).length_squared() <= maximum_range * maximum_range

static func fire_ranged_profile(weapon: String, ammo_mode: String = "NORMAL") -> Dictionary:
	var profile := ranged_profile(weapon)
	if profile.is_empty() or ammo_mode not in ["NORMAL", "FIRE_ARROW"] \
		or ammo_mode == "FIRE_ARROW" and str(profile.ammo) != "arrow":
		return {}
	var burning := ammo_mode == "FIRE_ARROW"
	profile.merge({"id": "fire_arrow_v1" if burning else ("normal_arrow_v1" if str(profile.ammo) == "arrow" else "normal_bolt_v1"),
		"mode": ammo_mode, "prepare": 0.8 if burning else 0.0,
		"scatter_multiplier": 1.15 if burning else 1.0, "kinetic_multiplier": 1.0,
		"ember": 20.0 if burning else 0.0, "air_decay": 2.0 if burning else 0.0,
		"rain_decay": float(fire_environment_profile().rain_ember_decay) if burning else 0.0,
		"environment_config_version": FIRE_ENVIRONMENT_CONFIG_VERSION,
		"contact_rate": 10.0 if burning else 0.0, "contact_seconds": 2.0 if burning else 0.0,
		"gravity": 4.0, "life": 4.0, "config_version": FIRE_RANGED_CONFIG_VERSION})
	if burning: profile.ammo = "fire_arrow"
	return profile

static func fire_aim_offset(shooter: Dictionary, distance: float, target_moving: bool, seed_value: int, member_id: int, order_serial: int, release_sequence: int, scatter_multiplier: float = 1.0) -> Vector2:
	# The original release owner advances this sequence only on commit and rejects
	# duplicate releases. A pure rule cannot keep a second sequence authority.
	var ability := float(shooter.get("ability", 50.0))
	var training := float(shooter.get("training", 0.0))
	var fatigue := float(shooter.get("fatigue", 0.0))
	if release_sequence <= 0 or not is_finite(distance) or distance < 0.0 \
		or not is_finite(scatter_multiplier) or scatter_multiplier < 0.0 \
		or not is_finite(ability) or not is_finite(training) or not is_finite(fatigue):
		return Vector2.INF
	var quality := clampf(65.0 + (clampf(ability, 0.0, 100.0) - 50.0) * 0.5 \
		+ clampf(training, 0.0, 100.0) * 0.1 - clampf(fatigue, 0.0, 100.0) * 0.25 \
		- maxf(0.0, distance - 2.0) * 4.0 \
		+ (EXCHANGE_SKILL_BONUS if str(shooter.get("skill", "")) == "power" else 0.0) \
		- (20.0 if target_moving else 0.0) 		- clampf(float(shooter.get("weather_penalty", 0.0)), 0.0, 60.0), 5.0, 95.0) # 時間與氣候 TC10: rain, night, wind
	var radius := (0.10 + distance * 0.12 * (100.0 - quality) / 100.0) * scatter_multiplier
	# Versioned SHA samples are in [0,1), independent of any presentation/global RNG.
	var digest := ("%s|%d|%d|%d|%d" % [FIRE_RANGED_CONFIG_VERSION, seed_value, member_id, order_serial, release_sequence]).sha256_text()
	var u := float(digest.substr(0, 8).hex_to_int()) / 4294967296.0
	var v := float(digest.substr(8, 8).hex_to_int()) / 4294967296.0
	return Vector2.from_angle(TAU * v) * (radius * sqrt(u))

static func fire_trajectory(origin: Vector3, aim: Vector3, profile: Dictionary) -> Dictionary:
	var speed := float(profile.get("speed", 0.0))
	var gravity := float(profile.get("gravity", 0.0))
	var life := float(profile.get("life", 0.0))
	# The launch owner supplies the pre-scatter distance in its profile copy.
	var distance := float(profile.get("nominal_distance", origin.distance_to(aim)))
	if not origin.is_finite() or not aim.is_finite() or not is_finite(speed) or speed <= 0.0 \
		or not is_finite(gravity) or gravity < 0.0 or not is_finite(life) or life <= 0.0 \
		or not is_finite(distance) or distance <= 0.0:
		return {}
	var total := distance / speed
	if total > life: return {}
	# Original Site/siege coordinates keep navigation in XY and height in Z.
	var velocity := (aim - origin) / total + Vector3(0, 0, 1) * (0.5 * gravity * total)
	if not velocity.is_finite(): return {}
	return {"origin": origin, "velocity": velocity,
		"gravity": gravity, "total": total, "life": life}

static func fire_position(flight: Dictionary, t: float) -> Vector3:
	var origin: Vector3 = flight.get("origin", Vector3.INF)
	var velocity: Vector3 = flight.get("velocity", Vector3.INF)
	var gravity := float(flight.get("gravity", -1.0))
	var life := float(flight.get("life", -1.0))
	if not origin.is_finite() or not velocity.is_finite() or not is_finite(gravity) or gravity < 0.0 \
		or not is_finite(life) or life <= 0.0 or not is_finite(t) or t < 0.0 or t > life:
		return Vector3.INF
	return origin + velocity * t + Vector3(0, 0, -1) * (0.5 * gravity * t * t)

static func fire_contact_result(shooter: Dictionary, defender: Dictionary, incidence: float, shield: bool, kinetic_multiplier: float = 1.0, siege_fire_pot: bool = false) -> Dictionary:
	var weapon := str(shooter.get("weapon", "none"))
	if not siege_fire_pot and ranged_profile(weapon).is_empty() or not is_finite(incidence) or absf(incidence) > 1.000001 \
		or not is_finite(kinetic_multiplier) or kinetic_multiplier < 0.0:
		return {}
	# incidence is the actual relative-velocity/contact-normal cosine. No roll or
	# abstract shield, armor_stab, facility or moving chance is read after contact.
	var graze := not shield and absf(incidence) < 0.35
	var scale := 0.5 if graze else 1.0
	var brace := 0.8 if str(defender.get("skill", "")) == "brace" else 1.0
	var armor := str(defender.get("armor", "none"))
	return {"kind": "shield" if shield else ("graze" if graze else "hit"),
		"contact_kind": "SHIELD_CONTACT" if shield else ("BODY_GRAZE" if graze else "BODY_HIT"),
		"hp": 0.0 if shield or siege_fire_pot else exchange_hp(weapon, armor) * scale * kinetic_multiplier * brace,
		"stun": 0.0 if shield or siege_fire_pot else (exchange_stun(weapon) * scale + (EXCHANGE_POWER_STUN if str(shooter.get("skill", "")) == "power" else 0.0)) * brace,
		"stagger": 0.0 if shield else (0.2 if graze else 0.35), "knockback": false, "guard_break": false,
		"contact_scale": scale, "heat_transfer": 0.10 if shield else 1.0 / (1.0 + armor_level(armor))}

static func ranged_result(shooter: Dictionary, defender: Dictionary, distance: float, roll: float) -> Dictionary:
	# Target ownership/faction, ammunition and the captured flight event belong to
	# callers. In particular, a friendly occupant receives the same numerical rule.
	var result := {"kind": "miss", "hp": 0.0, "stun": 0.0, "stagger": 0.0,
		"knockback": false, "guard_break": false, "chance": 0.0}
	var weapon := str(shooter.get("weapon", "none"))
	if not WeaponMaterials.is_ranged(StringName(weapon)) \
		or not is_finite(distance) or distance <= 1.0 or distance > RANGED_MAX_RANGE \
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
	result["chance"] = chance
	if roll >= chance:
		return result
	var hit := roll < chance * 0.6
	result["kind"] = "hit" if hit else "graze"
	# A released shot keeps its launch weapon; the actual arrival target supplies
	# current armor. A graze halves the shared tier/weapon effects, not accuracy.
	var contact_scale := 1.0 if hit else 0.5
	result.hp = exchange_hp(weapon, str(defender.get("armor", "none"))) * contact_scale
	result.stun = exchange_stun(weapon) * contact_scale + (EXCHANGE_POWER_STUN if power else 0.0)
	result["stagger"] = 0.35 if hit else 0.2
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

static func ranged_height(data: TerrainData, source: Vector2i, goal: Vector2i, sample: Vector2i, source_eye: float = -1.0, goal_eye: float = -1.0) -> float:
	if source_eye < 0.0: source_eye = data.effective_height(source) + 1.0
	if goal_eye < 0.0: goal_eye = data.effective_height(goal) + 1.0
	var offset := Vector2(goal - source)
	var along := clampf(Vector2(sample - source).dot(offset) / maxf(1.0, offset.length_squared()), 0.0, 1.0)
	return lerpf(source_eye, goal_eye, along)

static func ranged_cell_clear(data: TerrainData, source: Vector2i, goal: Vector2i, sample: Vector2i, source_eye: float = -1.0, goal_eye: float = -1.0) -> bool:
	if not data.contains(sample): return false
	if sample == source: return true
	var solid_top := float(data.effective_height(sample)) + (2.0 if not data.static_blocked.is_empty() and data.static_blocked[data.index(sample)] != 0 else 0.0)
	return solid_top < ranged_height(data, source, goal, sample, source_eye, goal_eye) - 0.000001

static func ranged_body_intersects(data: TerrainData, source: Vector2i, goal: Vector2i, sample: Vector2i, source_eye: float = -1.0, goal_eye: float = -1.0) -> bool:
	var height := ranged_height(data, source, goal, sample, source_eye, goal_eye)
	var floor_height := float(data.effective_height(sample))
	return height >= floor_height and height <= floor_height + 1.5

static func ranged_line_clear(data: TerrainData, source: Vector2i, goal: Vector2i) -> bool:
	if data == null or not data.is_walkable(source) or not data.contains(goal): return false
	var cells := ranged_cells(source, goal)
	if cells.is_empty(): return false
	for cell: Vector2i in cells:
		if not ranged_cell_clear(data, source, goal, cell): return false
	return true

static func ranged_friendly_clear(source: Vector2i, goal: Vector2i, friendly_cells: Dictionary, data: TerrainData = null) -> bool:
	for cell: Vector2i in ranged_cells(source, goal):
		if friendly_cells.has(cell) and (data == null or ranged_body_intersects(data, source, goal, cell)): return false
	return true

static func exchange_score(person: Dictionary) -> float:
	var skill_bonus := EXCHANGE_SKILL_BONUS if str(person.get("skill", "")) in ["brace", "power"] else 0.0
	return clampf(float(person.get("ability", 50.0)), 0.0, 100.0) \
		+ clampf(float(person.get("training", 0.0)), 0.0, 100.0) * EXCHANGE_TRAINING_WEIGHT \
		+ (clampf(float(person.get("morale", 100.0)), 0.0, 100.0) - 100.0) * EXCHANGE_MORALE_WEIGHT \
		- clampf(float(person.get("fatigue", 0.0)), 0.0, 100.0) * EXCHANGE_FATIGUE_WEIGHT \
		+ float(person.get("armorbonus", 0.0)) + float(person.get("facility", 0.0)) \
		+ skill_bonus

static func weapon_level(asset: String) -> int:
	# Equipment records keep their existing asset IDs. Combat derives this
	# disposable balance tier without adding another saved item field.
	return int({"": 0, "wood": 1, "stone": 2, "iron": 3, "steel": 4}.get(
		WeaponMaterials.material(StringName(asset)), 0))

static func armor_level(asset: String) -> int:
	if "mingguang" in asset or "steel" in asset:
		return 4
	if "iron" in asset:
		return 3
	if "leather" in asset:
		return 2
	if asset.begins_with("outfit_medieval_"):
		return 1
	return 0

static func exchange_attack_clip(asset: String) -> StringName:
	return StringName(WeaponMaterials.ATTACKS.get(WeaponMaterials.family(StringName(asset)), &"attack_unarmed"))

static func exchange_stun(asset: String) -> float:
	# The actual weapon decides impact; the big-win jump is presentation only.
	return float(attack_profile(exchange_attack_clip(asset)).impact)

static func exchange_hp(weapon: String, armor: String, big: bool = false) -> float:
	var value := pow(2.0, weapon_level(weapon) - armor_level(armor))
	return value * (2.0 if big else 1.0)

static func exchange_result(a: Dictionary, b: Dictionary, roll: float = 0.0) -> Dictionary:
	# One bounded, caller-owned roll is added to A's margin. Swap A/B and negate
	# that same roll to obtain the mirrored result; this helper has no RNG state.
	var score_a := exchange_score(a)
	var score_b := exchange_score(b)
	var margin := score_a - score_b + clampf(roll, -EXCHANGE_ROLL_LIMIT, EXCHANGE_ROLL_LIMIT)
	var result := {"winner": 0, "kind": "draw", "hp": 0.0, "stun": 0.0,
		"hp_a": 0.0, "hp_b": 0.0,
		"stun_a": exchange_stun(str(b.get("weapon", "none"))),
		"stun_b": exchange_stun(str(a.get("weapon", "none"))), "stagger": 0.0,
		"hold": EXCHANGE_DRAW_HOLD, "knockback": false, "guard_break": false,
		"fatigue_a": 0.0, "fatigue_b": 0.0,
		"score_a": score_a, "score_b": score_b, "margin": margin}
	if absf(margin) <= EXCHANGE_DRAW_MARGIN:
		return result
	var a_wins := margin > 0.0
	var big := absf(margin) >= EXCHANGE_BIG_MARGIN
	var winner: Dictionary = a if a_wins else b
	var loser: Dictionary = b if a_wins else a
	result["winner"] = 1 if a_wins else -1
	result["kind"] = "big" if big else "small"
	result["fatigue_a"] = EXCHANGE_FATIGUE
	result["fatigue_b"] = EXCHANGE_FATIGUE
	var hp := exchange_hp(str(winner.get("weapon", "none")), str(loser.get("armor", "none")), big)
	var stun := exchange_stun(str(winner.get("weapon", "none"))) \
		+ (EXCHANGE_POWER_STUN if str(winner.get("skill", "")) == "power" else 0.0)
	result.hp = hp # Compatibility summary: the losing side's HP effect.
	result.stun = stun # Compatibility summary: the losing side's stun effect.
	result["hp_b"] = hp if a_wins else 0.0
	result["hp_a"] = 0.0 if a_wins else hp
	result["stun_b"] = stun if a_wins else 0.0
	result["stun_a"] = 0.0 if a_wins else stun
	result["stagger"] = EXCHANGE_BIG_STAGGER if big else EXCHANGE_SMALL_STAGGER
	result["hold"] = 0.0
	result["knockback"] = big and str(loser.get("skill", "")) != "brace"
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
		"impact": UNARMED_IMPACT if clip == &"attack_unarmed" else {"slash": 12.0, "stab": 8.0, "blunt": 35.0}[kind],
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

# P2 candidate: append to original SiteCombatRules, no state or second clock.
const SITE_FIRE_CONFIG_VERSION := "site_fire_v1"

static func fire_profile(identity: String) -> Dictionary:
	var common := {"config_version": SITE_FIRE_CONFIG_VERSION, "ignition_heat": 100.0, "sustain_heat": 50.0,
		"heat_limit": 240.0, "cooling_rate": 2.0, "burn_rate_q": 512.0, "heat_per_q": 80.0 / 1024.0,
		"spread_rate": 8.0, "damage_per_q": 40.0 / 1024.0, "ember_intensity": 0.1,
		"moisture_ignition": 0.5, "moisture_cooling": 1.0}
	match identity:
		"WOOD_COMPONENT": return common
		"TIMBER":
			common.merge({"ignition_heat": 40.0, "sustain_heat": 20.0, "heat_limit": 150.0,
				"burn_rate_q": 256.0, "damage_per_q": 0.0}, true)
			return common
		"TEST_HEAT_100":
			# FI-01's explicitly named zero-loss test profile. Formal original asset
			# descriptors can only select TIMBER/WOOD_COMPONENT, never this profile.
			common.merge({"heat_limit": 1000.0, "cooling_rate": 0.0, "burn_rate_q": 1280.0,
				"heat_per_q": 0.0, "spread_rate": 0.0, "damage_per_q": 0.0,
				"moisture_ignition": 0.0, "moisture_cooling": 0.0}, true)
			return common
	return {}


# P3-A candidate engineering profile, versioned separately from P2 fuel rules.
# Values are proposed tuning defaults, not historical P0 acceptance numbers.
const FIRE_BODY_VERSION := "body_v1_candidate"
const FIRE_BODY := {"dose_threshold": 20.0, "dose_limit": 60.0, "dose_decay": 2.0,
	"hazard_dose_rate": 12.0, "hazard_hp_rate": 6.0, "burn_hp_rate": 3.0,
	"burn_seconds": 4.0, "episode_seconds": 8.0, "plume_height": 0.75}

static func fire_risk_band(risk: float) -> int:
	return 0 if risk <= 0.00000001 else (1 if risk < 0.2 else (2 if risk < 0.6 else 3))

static func fire_body_active(state: Dictionary) -> bool:
	return float(state.get("dose", 0.0)) > 0.00000001 or float(state.get("burn_left", 0.0)) > 0.00000001 or not state.get("contacts", {}).is_empty()

static func fire_body_visual_code(state: Dictionary) -> int:
	return 2 if float(state.get("burn_left", 0.0)) > 0.00000001 else (1 if float(state.get("dose", 0.0)) > 0.00000001 else 0)

static func fire_body_tint(code: int) -> Color:
	return Color(1.0, 0.35, 0.12) if code == 2 else (Color(1.0, 0.75, 0.42) if code == 1 else Color.WHITE)

static func fire_body_receive_contact(state: Dictionary, payload: Dictionary) -> bool:
	# Called only after the original Runtime receipt accepted a nonduplicate
	# terminal event. The kinetic packet has already been applied exactly once.
	var rate := float(payload.heat_rate) * float(payload.heat_transfer) * float(payload.contact_scale)
	var amount := float(payload.remaining_heat_budget) * float(payload.heat_transfer) * float(payload.contact_scale)
	if rate <= 0.0 or amount <= 0.0: return false
	var duration := minf(float(payload.max_seconds), amount / rate)
	if duration <= 0.0: return false
	if state.is_empty(): _fire_body_initialize(state)
	var event_id := str(payload.event_id)
	if state.contacts.has(event_id): return false
	state.contacts[event_id] = {"start": float(payload.action_time), "end": float(payload.action_time) + duration, "rate": rate}
	return true

static func _fire_body_initialize(state: Dictionary) -> void:
	state.merge({"version": FIRE_BODY_VERSION, "dose": 0.0, "burn_left": 0.0,
		"episode_left": 0.0, "armed": true, "contacts": {}, "last_interval": -1, "last_action_end": -1.0})

static func _fire_body_integrate(state: Dictionary, seconds: float, risk: float, contact_rate: float, protection: float) -> float:
	var dose := float(state.dose)
	var net_rate := maxf(0.0, risk) * float(FIRE_BODY.hazard_dose_rate) * protection + contact_rate - float(FIRE_BODY.dose_decay)
	var ignition_at := INF
	if bool(state.armed):
		if dose >= float(FIRE_BODY.dose_threshold): ignition_at = 0.0
		elif net_rate > 0.0: ignition_at = (float(FIRE_BODY.dose_threshold) - dose) / net_rate
	var burn_damage := 0.0
	if ignition_at <= seconds:
		state["armed"] = false
		state["episode_left"] = float(FIRE_BODY.episode_seconds)
		state["burn_left"] = float(FIRE_BODY.burn_seconds)
		var burning_seconds := seconds - ignition_at
		burn_damage = minf(burning_seconds, float(state.burn_left)) * float(FIRE_BODY.burn_hp_rate)
		state["burn_left"] = maxf(0.0, float(state.burn_left) - burning_seconds)
		state["episode_left"] = maxf(0.0, float(state.episode_left) - burning_seconds)
	elif float(state.burn_left) > 0.0:
		# An episode's remaining lifetime only decreases. Continuous heat cannot
		# extend it indefinitely; cooling all the way to zero is required to rearm.
		if net_rate > 0.0:
			state["burn_left"] = minf(float(state.episode_left), maxf(float(state.burn_left), float(FIRE_BODY.burn_seconds)))
		burn_damage = minf(seconds, float(state.burn_left)) * float(FIRE_BODY.burn_hp_rate)
		state["burn_left"] = maxf(0.0, float(state.burn_left) - seconds)
		state["episode_left"] = maxf(0.0, float(state.episode_left) - seconds)
	state["dose"] = clampf(dose + net_rate * seconds, 0.0, float(FIRE_BODY.dose_limit))
	if float(state.dose) <= 0.00000001 and float(state.burn_left) <= 0.00000001:
		state["armed"] = true
		state["episode_left"] = 0.0
	return maxf(0.0, risk) * float(FIRE_BODY.hazard_hp_rate) * protection * seconds + burn_damage

static func fire_body_advance(state: Dictionary, sequence: int, action_begin: float, action_end: float,
		segments: Array[Dictionary], protection: float) -> Dictionary:
	if sequence < 0 or not is_finite(action_begin) or not is_finite(action_end) or action_end <= action_begin:
		return {"ok": false, "code": "INVALID_EXPOSURE_INTERVAL"}
	if state.is_empty(): _fire_body_initialize(state)
	if str(state.version) != FIRE_BODY_VERSION: return {"ok": false, "code": "FIRE_BODY_VERSION"}
	if sequence <= int(state.last_interval) or action_end <= float(state.last_action_end) + 0.00000001:
		return {"ok": true, "duplicate": true, "hp": 0.0, "active": fire_body_active(state)}
	if action_begin < float(state.last_action_end) - 0.00000001:
		return {"ok": false, "code": "OVERLAPPING_EXPOSURE_INTERVAL"}
	# Validate the entire original completed partition before changing any dose.
	var cursor := action_begin
	for segment: Dictionary in segments:
		if absf(float(segment.begin) - cursor) > 0.0000001 or not is_finite(float(segment.risk)) or float(segment.risk) < 0.0 or float(segment.end) <= cursor:
			return {"ok": false, "code": "INVALID_EXPOSURE_PARTITION"}
		cursor = float(segment.end)
	if absf(cursor - action_end) > 0.0000001: return {"ok": false, "code": "INCOMPLETE_EXPOSURE_PARTITION"}
	# One ordered event sweep, not every contact multiplied by every event.
	var events: Array[Dictionary] = []
	var active := {}
	var contact_rate := 0.0
	for event_id: String in state.contacts:
		var contact: Dictionary = state.contacts[event_id]
		if float(contact.end) <= action_begin: continue
		if float(contact.start) <= action_begin:
			active[event_id] = float(contact.rate)
			contact_rate += float(contact.rate)
		elif float(contact.start) < action_end: events.append({"at": float(contact.start), "id": event_id, "start": true})
		if float(contact.end) < action_end: events.append({"at": float(contact.end), "id": event_id, "start": false})
	events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if float(a.at) != float(b.at): return float(a.at) < float(b.at)
		if bool(a.start) != bool(b.start): return not bool(a.start)
		return str(a.id) < str(b.id))
	var hp := 0.0
	var event_index := 0
	for segment: Dictionary in segments:
		cursor = float(segment.begin)
		while cursor < float(segment.end):
			while event_index < events.size() and float(events[event_index].at) <= cursor:
				var event: Dictionary = events[event_index]
				event_index += 1
				var event_id := str(event.id)
				if bool(event.start) and state.contacts.has(event_id):
					active[event_id] = float(state.contacts[event_id].rate)
					contact_rate += float(active[event_id])
				elif active.has(event_id):
					contact_rate -= float(active[event_id])
					active.erase(event_id)
			var end := minf(float(segment.end), float(events[event_index].at)) if event_index < events.size() else float(segment.end)
			if bool(segment.wet):
				state["dose"] = 0.0
				state["burn_left"] = 0.0
				state["episode_left"] = 0.0
				state["armed"] = true
				for event_id: String in active: state.contacts.erase(event_id)
				active.clear()
				contact_rate = 0.0
			else:
				hp += _fire_body_integrate(state, end - cursor, float(segment.risk), maxf(0.0, contact_rate), clampf(protection, 0.0, 1.0))
			cursor = end
	for event_id: String in state.contacts.keys():
		if float(state.contacts[event_id].end) <= action_end + 0.00000001: state.contacts.erase(event_id)
	state["last_interval"] = sequence
	state["last_action_end"] = action_end
	return {"ok": true, "duplicate": false, "hp": hp, "active": fire_body_active(state)}

static func fire_environment_packet(hp: float) -> Dictionary:
	return {"result": {"hp": hp, "stun": 0.0, "guard_break": false}, "shield": false,
		"environmental": true, "attacker": null, "attacker_unit": -1}

# P3 engineering initial values. Append to ORIGINAL SiteCombatRules only.
# These are not new resources or a measured balancing result.
const FIRE_SUPPRESSION_CONFIG_VERSION := "site_suppression_v1"

static func fire_suppression_profile() -> Dictionary:
	return {"config_version": FIRE_SUPPRESSION_CONFIG_VERSION, "supply_q_per_second": 1024,
		"supply_cap_q": 30720, "cooling_per_second": 64.0, "moisture_per_second": 0.10,
		"drying_per_second": 0.02, "slot_risk_max": 0.0, "maximum_action_slice": 1.0 / 30.0,
		"maximum_contact_height": 1.5, "approach_timeout_seconds": 120.0,
		"job_timeout_seconds": 21600.0, "pending_cap": 64}

static func fire_moisture_at(unit: Dictionary, base: float, action_time: float) -> float:
	# Dormant cold units need no active ticking merely to dry. The original
	# completed action timestamp determines the same value on the next input.
	var profile := fire_suppression_profile()
	var elapsed := maxf(0.0, action_time - float(unit.get("moisture_action", action_time)))
	return maxf(base, float(unit.moisture) - float(profile.drying_per_second) * elapsed)

# P3-B engineering values, not measured balancing or performance acceptance.
static func fire_navigation_profile() -> Dictionary:
	return {"version": "fire_navigation_v1", "normal_max_band": 1, "evacuate_band": 2,
		"immediate_band": 3, "safe_goal_band": 0, "band_costs": [0, 4, 16, 64],
		"replan_seconds": 0.5, "safe_seconds": 1.0, "retry_seconds": 1.0,
		"aging_ticks": 3, "route_lookahead": 12, "route_minimum_charge": 32}

# P4 extension of original SiteCombatRules; finite FireLab genesis supply only.
const FIRE_WORK_CONFIG_VERSION := "site_fire_work_v1"

static func fire_work_profile(mode: String = "SUPPRESS") -> Dictionary:
	var profile := fire_suppression_profile()
	profile["mode"] = mode
	profile["supply_field"] = "fire_lab_suppression_q" if mode == "SUPPRESS" else "fire_lab_ignition_q"
	profile["heating_per_second"] = 64.0 if mode == "IGNITE" else 0.0
	# A bound on committed finite input records, not a new work/route quota.
	# The original PersonActions/Registry and formation route budget admit work.
	profile.pending_cap = 4096
	if mode == "IGNITE":
		profile.config_version = FIRE_WORK_CONFIG_VERSION
		profile.cooling_per_second = 0.0
		profile.moisture_per_second = 0.0
	return profile

# Engineering starting values; all use original action seconds, not FPS/game speed.
const FIRE_ENVIRONMENT_CONFIG_VERSION := "site_fire_environment_v1"

static func fire_environment_profile() -> Dictionary:
	return {"config_version": FIRE_ENVIRONMENT_CONFIG_VERSION, "weather_history_cap": 4096,
		"rain_wetting_per_second": 0.08, "rain_cooling_per_second": 8.0, "rain_ember_decay": 32.0,
		"wind_weight": 0.75, "smoke_source_per_second": 8.0, "smoke_transfer_per_second": 0.6,
		"smoke_decay_per_second": 0.35, "smoke_vertical_span": 3.0, "smoke_min_density": 0.0001,
		"smoke_field_cap": 65536, "smoke_scatter_per_depth": 0.04, "smoke_scatter_max": 4.0,
		"smoke_visibility_depth": 40.0}

# P5 keeps the original body's finite dose/contact state. This is serialization
# only: no restored receipt may reapply HP or restart an episode.
const FIRE_BODY_SAVED_FIELDS := ["version", "dose", "burn_left", "episode_left", "armed", "contacts", "last_interval", "last_action_end"]

static func _fire_body_saved_number(value: Variant, lower: float, upper: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= lower and float(value) <= upper

static func fire_body_saved_valid(value: Variant) -> bool:
	if not value is Dictionary: return false
	if value.is_empty(): return true
	if value.size() != FIRE_BODY_SAVED_FIELDS.size(): return false
	for field: String in FIRE_BODY_SAVED_FIELDS:
		if not value.has(field): return false
	if value.version != FIRE_BODY_VERSION or not value.armed is bool or not value.contacts is Dictionary: return false
	if not _fire_body_saved_number(value.dose, 0.0, float(FIRE_BODY.dose_limit)) or not _fire_body_saved_number(value.burn_left, 0.0, float(FIRE_BODY.burn_seconds)) or not _fire_body_saved_number(value.episode_left, 0.0, float(FIRE_BODY.episode_seconds)): return false
	if float(value.burn_left) > float(value.episode_left) + 0.00000001: return false
	if bool(value.armed) and (float(value.burn_left) > 0.0 or float(value.episode_left) > 0.0): return false
	if not _fire_body_saved_number(value.last_interval, -1.0, 2147483647.0) or float(value.last_interval) != floorf(float(value.last_interval)): return false
	if not _fire_body_saved_number(value.last_action_end, -1.0, 2147483647.0 / 5.0): return false
	if (int(value.last_interval) == -1) != (float(value.last_action_end) == -1.0) or int(value.last_interval) >= 0 and float(value.last_action_end) <= 0.0: return false
	for identity: Variant in value.contacts:
		if not identity is String or not str(identity).begins_with("arrow:"): return false
		var serial := str(identity).trim_prefix("arrow:")
		if not serial.is_valid_int() or str(int(serial)) != serial or int(serial) < 1 or int(serial) > 2147483647: return false
		var contact: Variant = value.contacts[identity]
		if not contact is Dictionary or contact.size() != 3 or not contact.has("start") or not contact.has("end") or not contact.has("rate"): return false
		if not _fire_body_saved_number(contact.start, 0.0, 2147483647.0 / 5.0) or not _fire_body_saved_number(contact.end, 0.0, 2147483647.0 / 5.0) or not _fire_body_saved_number(contact.rate, 0.0, 10.0): return false
		var duration := float(contact.end) - float(contact.start)
		if duration <= 0.0 or duration > 2.0 + 0.00000001 or float(contact.rate) <= 0.0 or duration * float(contact.rate) > 20.0 + 0.00000001: return false
	return true

static func fire_body_capture(state: Dictionary) -> Dictionary:
	if state.is_empty(): return {}
	var saved := {}
	for field: String in FIRE_BODY_SAVED_FIELDS: saved[field] = state[field]
	saved["contacts"] = state.contacts.duplicate(true)
	return saved

static func fire_body_restore(saved: Dictionary) -> Dictionary:
	if saved.is_empty(): return {}
	var result := saved.duplicate(true)
	result["last_interval"] = int(saved.last_interval)
	for field: String in ["dose", "burn_left", "episode_left", "last_action_end"]: result[field] = float(saved[field])
	for contact: Dictionary in result.contacts.values():
		for field: String in ["start", "end", "rate"]: contact[field] = float(contact[field])
	return result


static func fire_pot_profile() -> Dictionary:
	# First F15 payload reuses the existing finite thermal configuration. The
	# real trebuchet remains the kinetic/arc owner; no invented blast or heat.
	var original := fire_ranged_profile("bow_01", "FIRE_ARROW")
	return {"id": "fire_pot_v1", "ember": float(original.ember), "air_decay": float(original.air_decay),
		"rain_decay": float(original.rain_decay), "contact_rate": float(original.contact_rate),
		"contact_seconds": float(original.contact_seconds), "config_version": str(original.config_version)}
