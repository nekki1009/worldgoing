class_name SpecialCharacterRenderMode
extends RefCounted

enum Mode {
	MODULAR,
	SHARED_RESOURCES,
	SKINNED_BUNDLE,
	BUNDLE_REDUCED_SHADOW,
	BUNDLE_LOD
}

static func name_for(mode: int) -> StringName:
	match mode:
		Mode.SHARED_RESOURCES:
			return &"SHARED_RESOURCES"
		Mode.SKINNED_BUNDLE:
			return &"SKINNED_BUNDLE"
		Mode.BUNDLE_REDUCED_SHADOW:
			return &"BUNDLE_REDUCED_SHADOW"
		Mode.BUNDLE_LOD:
			return &"BUNDLE_LOD"
		_:
			return &"MODULAR"
