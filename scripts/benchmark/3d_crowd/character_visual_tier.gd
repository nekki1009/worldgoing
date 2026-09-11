class_name CharacterVisualTier
extends RefCounted

enum Tier { SPECIAL, REGULAR }

static func tier_name(tier: int) -> StringName:
	return &"SPECIAL" if tier == Tier.SPECIAL else &"REGULAR"
