extends RefCounted
## Presentation-only edits of the original clips. Never supplies damage,
## cooldowns, movement, or the historical geometry/baker's source clock.
const Authored = preload("res://scripts/terrain_lab/character_combat_timings.gd")
const ATTACK_SECONDS := 0.85
const HIT_SECONDS := 0.45
const KNOCKBACK_SECONDS := 0.75
const DRAW_SECONDS := 0.3
const MOVE_CORE_SECONDS := 0.1
const END_HOLD_SECONDS := 2.0 / 30.0

# Source-frame presentation markers, not collision/hit tests. Start near the
# stroke instead of replaying seconds of preparation after a resolved result.
const STROKE_FRAMES := {
	&"walk_slash": 32.0, &"attack_sword": 32.0, &"attack_spear": 30.0,
	&"attack_axe": 44.0, &"attack_hammer": 53.0, &"attack_dagger": 24.0,
	&"attack_unarmed": 18.0, &"attack_jump_heavy": 37.0,
	&"ride_slash": 20.0, &"ride_thrust": 20.0,
}
const REACTION_LENGTHS := {
	&"hit": 23.0 / 24.0, &"hit_back": 32.0 / 24.0,
	&"knockback": 29.0 / 24.0, &"guard": 17.0 / 24.0,
	&"guard_weapon": 1.2, &"guard_polearm": 1.2,
	&"guard_unshielded": 1.2, &"guard_spear": 1.2,
}

static func duration(clip: StringName) -> float:
	if Authored.ATTACKS.has(clip):
		return ATTACK_SECONDS
	if clip in [&"hit", &"hit_back"]:
		return HIT_SECONDS
	if clip == &"knockback":
		return KNOCKBACK_SECONDS
	if REACTION_LENGTHS.has(clip):
		return DRAW_SECONDS
	return 0.0

static func authored_duration(clip: StringName) -> float:
	if Authored.ATTACKS.has(clip):
		return float(Authored.ATTACKS[clip][0]) / Authored.FPS
	return float(REACTION_LENGTHS.get(clip, Authored.POSE_SECONDS.get(clip, 0.0)))

static func reaction_priority(clip: StringName) -> int:
	return 2 if clip == &"knockback" else (1 if clip in [&"hit", &"hit_back"] else 0)

static func sample_time(clip: StringName, elapsed: float, source_length: float) -> float:
	var length := source_length if source_length > 0.0 else authored_duration(clip)
	var window := duration(clip)
	if length <= 0.0 or window <= 0.0:
		return maxf(0.0, elapsed)
	var age := maxf(0.0, elapsed)
	var finish := window - END_HOLD_SECONDS
	if age >= finish:
		return length # Reach the actual final pose before the owner clears it.
	if clip in [&"attack_bow", &"attack_crossbow"]:
		return lerpf(minf(length, float(Authored.ATTACKS[clip][3]) / Authored.FPS), length, age / finish)
	if STROKE_FRAMES.has(clip):
		var contact := minf(length, float(STROKE_FRAMES[clip]) / Authored.FPS)
		var core_end := minf(length, contact + 2.0 / Authored.FPS)
		if age < MOVE_CORE_SECONDS:
			return lerpf(contact, core_end, age / MOVE_CORE_SECONDS)
		var recovery := minf(length, float(Authored.ATTACKS[clip][2]) / Authored.FPS)
		var recover_at := finish - 0.15
		if age < recover_at:
			return lerpf(core_end, maxf(core_end, recovery), (age - MOVE_CORE_SECONDS) / (recover_at - MOVE_CORE_SECONDS))
		return lerpf(maxf(core_end, recovery), length, (age - recover_at) / (finish - recover_at))
	return lerpf(0.0, length, age / finish)
