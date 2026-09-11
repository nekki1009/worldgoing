class_name SpecialShadowBudget
extends RefCounted

enum Mode { ALL, BODY_BUNDLE_ONLY, BODY_MAJOR, DISTANCE_BUDGETED }

static func name_for(mode: int) -> StringName:
	match mode:
		Mode.BODY_BUNDLE_ONLY:
			return &"BODY_BUNDLE_ONLY"
		Mode.BODY_MAJOR:
			return &"BODY_MAJOR"
		Mode.DISTANCE_BUDGETED:
			return &"DISTANCE_BUDGETED"
		_:
			return &"ALL"

static func rigid_casts(shadow_class: int, mode: int, actor_rank: int, max_full_shadow_actors: int) -> bool:
	match mode:
		Mode.BODY_BUNDLE_ONLY:
			return false
		Mode.BODY_MAJOR:
			return shadow_class == RigidEquipmentRenderRegistry.ShadowClass.MAJOR
		Mode.DISTANCE_BUDGETED:
			return actor_rank < max_full_shadow_actors and shadow_class == RigidEquipmentRenderRegistry.ShadowClass.MAJOR
		_:
			return true
