extends RefCounted
## Authored events in source frames (24 fps), checked against the formal clips.
## No percentage-derived damage window. Editor, actor and offline atlas share this.
const FPS := 24.0
const MOVE_DURATION := 0.38
const RUN_DURATION := 0.18

static func advance_movement_progress(progress: float, delta: float, duration: float) -> float:
	var next := minf(1.0, progress + delta / duration)
	# Match the original actor's one-nanosecond endpoint cleanup. Keep the
	# progress in float64 so repeated 120 Hz steps cannot accumulate float32 lag.
	return 1.0 if (1.0 - next) * duration <= 0.000000001 else next

static func movement_weight(progress: float, legacy_smoothstep: bool = false) -> float:
	var fraction := clampf(progress, 0.0, 1.0)
	return smoothstep(0.0, 1.0, fraction) if legacy_smoothstep else fraction * (2.0 - fraction)

const ATTACKS := {
	&"walk_slash": [82, 20, 58, -1],
	&"attack_sword": [82, 20, 58, -1], # Editor's canonical sword alias is walk_slash.
	&"attack_spear": [70, 18, 40, -1],
	&"attack_axe": [115, 26, 60, -1],
	&"attack_hammer": [138, 31, 72, -1],
	&"attack_dagger": [71, 13, 40, -1],
	&"attack_unarmed": [36, 12, 24, -1],
	&"attack_jump_heavy": [70, 30, 44, -1],
	&"attack_bow": [150, 116, 118, 116],
	&"attack_crossbow": [30, 15, 17, 15],
	&"ride_slash": [42, 12, 29, -1],
	&"ride_thrust": [42, 12, 29, -1],
}
const POSE_SECONDS := {&"guard_raise": .15, &"guard_lower": .15, &"guard_break": .4,
	&"down": 2.875, &"unconscious": 2.4, &"get_up": 2.2, &"rescue": 4.0,
	&"reload_bow": 1.15, &"reload_crossbow": 1.5,
	&"guard_weapon": 1.2, &"guard_weapon_raise": .15, &"guard_weapon_lower": .15, &"guard_weapon_break": .4,
	&"guard_polearm": 1.2, &"guard_polearm_raise": .15, &"guard_polearm_lower": .15, &"guard_polearm_break": .4}

static func events(clip: StringName) -> Dictionary:
	if not ATTACKS.has(clip):
		return {}
	var frames: Array = ATTACKS[clip]
	return {"duration": frames[0] / FPS, "active_start": frames[1] / FPS,
		"active_end": frames[2] / FPS, "release": frames[3] / FPS if frames[3] >= 0 else -1.0}

static func action_duration(clip: StringName, reduction: float, fatigue_slowdown: float = 0.0) -> float:
	if ATTACKS.has(clip):
		var frames: Array = ATTACKS[clip]
		var duration: float = frames[0] / FPS
		var authored_start: float = frames[1] / FPS
		var authored_end: float = frames[2] / FPS
		var active_duration: float = authored_end - authored_start
		return active_duration + (float(duration) - active_duration) * (1.0 - reduction) * (1.0 + fatigue_slowdown)
	# Preserve the original invalid-clip diagnostic path; do not invent a value.
	var event := events(clip)
	var active: float = event.active_end - event.active_start
	return active + (float(event.duration) - active) * (1.0 - reduction) * (1.0 + fatigue_slowdown)

static func sample_time(clip: StringName, elapsed: float, reduction: float, fatigue_slowdown: float = 0.0) -> float:
	if ATTACKS.has(clip):
		var frames: Array = ATTACKS[clip]
		var duration: float = frames[0] / FPS
		var authored_start: float = frames[1] / FPS
		var authored_end: float = frames[2] / FPS
		var scalar_speed := (1.0 - reduction) * (1.0 + fatigue_slowdown)
		var scalar_windup: float = authored_start * scalar_speed
		var scalar_active_end: float = scalar_windup + authored_end - authored_start
		if elapsed < scalar_windup:
			return elapsed / scalar_speed
		if elapsed <= scalar_active_end:
			return authored_start + elapsed - scalar_windup
		return minf(duration, authored_end + (elapsed - scalar_active_end) / scalar_speed)
	# Same original cold-path operations, including invalid-clip errors.
	var event := events(clip)
	var speed := (1.0 - reduction) * (1.0 + fatigue_slowdown)
	var windup: float = event.active_start * speed
	var active_end: float = windup + event.active_end - event.active_start
	if elapsed < windup:
		return elapsed / speed
	if elapsed <= active_end:
		return event.active_start + elapsed - windup
	return minf(event.duration, event.active_end + (elapsed - active_end) / speed)

static func attack_step_weight(fraction: float) -> float:
	return smoothstep(0.0, 0.20, fraction) * (1.0 - smoothstep(0.72, 1.0, fraction))
