class_name PaperDollAnimation
extends RefCounted

## Presentation-only action vocabulary shared by the data catalog, composer,
## and character creator.  Each clip is a sequence of the existing 8 columns.
## Art can later provide an authored action-specific 512x192 sheet without
## changing the caller.  Until that exists, the catalog creates a deterministic
## split-part transform sheet so the action still changes every selected layer
## under one frame controller.
enum Action {
	IDLE,
	WALK,
	RUN,
	ATTACK,
	SPRINT_ATTACK,
	WORK,
	HIT,
	DOWN,
	COUNT,
}

static func is_valid_action(action: int) -> bool:
	return action >= Action.IDLE and action < Action.COUNT

static func action_name(action: int) -> String:
	match action:
		Action.IDLE:
			return "IDLE"
		Action.WALK:
			return "WALK"
		Action.RUN:
			return "RUN"
		Action.ATTACK:
			return "ATTACK"
		Action.SPRINT_ATTACK:
			return "SPRINT ATTACK"
		Action.WORK:
			return "WORK"
		Action.HIT:
			return "HIT"
		Action.DOWN:
			return "DOWN"
		_:
			return "UNKNOWN"

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
		Action.SPRINT_ATTACK:
			return PackedInt32Array([0, 2, 4, 6, 7])
		Action.WORK:
			return PackedInt32Array([0, 1, 2, 3, 2, 1])
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
		Action.RUN:
			return 12.0
		Action.ATTACK:
			return 12.0
		Action.SPRINT_ATTACK:
			return 16.0
		Action.WORK:
			return 8.0
		Action.HIT, Action.DOWN:
			return 6.0
		_:
			return 8.0

static func next_frame(action: int, current_frame: int) -> int:
	var frames: PackedInt32Array = frames_for(action)
	if frames.is_empty():
		return 0
	var current_index: int = frames.find(current_frame)
	if current_index < 0:
		return frames[0]
	return frames[(current_index + 1) % frames.size()]
