class_name PaperDollV2Animation
extends RefCounted

enum Action {
	IDLE,
	WALK,
	RUN,
	ATTACK,
	HIT,
	DOWN,
	COUNT,
}

static func is_valid_action(action: int) -> bool:
	return action >= Action.IDLE and action < Action.COUNT

static func frames_for(action: int) -> PackedInt32Array:
	match action:
		Action.IDLE:
			return PackedInt32Array([0])
		Action.WALK:
			return PackedInt32Array([0, 1, 2, 3, 4, 5, 6, 7])
		Action.RUN:
			return PackedInt32Array([0, 2, 4, 6])
		Action.ATTACK:
			return PackedInt32Array([0, 1, 3, 5, 7])
		Action.HIT:
			return PackedInt32Array([4, 5, 4, 3])
		Action.DOWN:
			return PackedInt32Array([7])
		_:
			return PackedInt32Array([0])

static func default_fps(action: int) -> float:
	match action:
		Action.IDLE:
			return 4.0
		Action.WALK:
			return 8.0
		Action.RUN, Action.ATTACK:
			return 12.0
		Action.HIT, Action.DOWN:
			return 6.0
		_:
			return 8.0

static func next_frame(action: int, current_frame: int) -> int:
	var frames := frames_for(action)
	if frames.is_empty():
		return 0
	var index := frames.find(current_frame)
	return frames[0] if index < 0 else frames[(index + 1) % frames.size()]
