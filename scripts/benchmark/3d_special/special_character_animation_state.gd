class_name SpecialCharacterAnimationState
extends RefCounted

enum State { IDLE, WALK, RUN, ATTACK_SWORD, BLOCK }

static func state_name(state: int) -> StringName:
	match state:
		State.WALK:
			return &"WALK"
		State.RUN:
			return &"RUN"
		State.ATTACK_SWORD:
			return &"ATTACK_SWORD"
		State.BLOCK:
			return &"BLOCK"
		_:
			return &"IDLE"
