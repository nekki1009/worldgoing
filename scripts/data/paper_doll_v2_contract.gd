class_name PaperDollV2Contract
extends RefCounted

## V2 has its own contract instead of changing the V1 constants in place.
## This keeps old captures reproducible while the new 64x64/64x96 pipeline is
## brought up and verified.

enum RenderState {
	ON_FOOT,
	MOUNTED,
}

enum Gender {
	MALE,
	FEMALE,
}

enum Facing {
	DOWN,
	UP,
	RIGHT,
	LEFT,
}

enum GenderPolicy {
	GENDERED,
	UNISEX,
}

enum SymmetryPolicy {
	MIRROR_RIGHT,
	AUTHORED_LEFT,
	ASYMMETRIC_ALLOWED,
}

enum RenderLayer {
	MOUNT_TAIL,
	CAPE,
	MOUNT_BODY,
	BODY,
	BOOTS,
	ARMOR,
	HAIR,
	HELMET,
	WEAPON,
	SHIELD,
	MOUNT_HEAD,
	MOUNT_BARDING,
	COUNT,
}

const FRAME_COLUMNS: int = 8
const SOURCE_ROWS: int = 3
const ON_FOOT_FRAME_SIZE := Vector2i(64, 64)
const MOUNTED_FRAME_SIZE := Vector2i(64, 96)
const ON_FOOT_ANCHOR := Vector2i(32, 56)
const MOUNTED_ANCHOR := Vector2i(32, 88)

static func frame_size(state: int) -> Vector2i:
	return MOUNTED_FRAME_SIZE if state == RenderState.MOUNTED else ON_FOOT_FRAME_SIZE

static func sheet_size(state: int) -> Vector2i:
	return Vector2i(frame_size(state).x * FRAME_COLUMNS, frame_size(state).y * SOURCE_ROWS)

static func anchor_px(state: int) -> Vector2i:
	return MOUNTED_ANCHOR if state == RenderState.MOUNTED else ON_FOOT_ANCHOR

static func state_name(state: int) -> String:
	return "mounted" if state == RenderState.MOUNTED else "on_foot"

static func gender_name(gender: int) -> String:
	return "female" if gender == Gender.FEMALE else "male"

static func is_valid_state(state: int) -> bool:
	return state == RenderState.ON_FOOT or state == RenderState.MOUNTED

static func is_valid_gender(gender: int) -> bool:
	return gender == Gender.MALE or gender == Gender.FEMALE

static func is_valid_facing(facing: int) -> bool:
	return facing >= Facing.DOWN and facing <= Facing.LEFT

static func is_valid_layer(layer: int) -> bool:
	return layer >= RenderLayer.MOUNT_TAIL and layer < RenderLayer.COUNT

static func is_mount_layer(layer: int) -> bool:
	return layer == RenderLayer.MOUNT_TAIL \
		or layer == RenderLayer.MOUNT_BODY \
		or layer == RenderLayer.MOUNT_HEAD \
		or layer == RenderLayer.MOUNT_BARDING

static func source_row_for(facing: int) -> int:
	return Facing.RIGHT if facing == Facing.LEFT else facing

static func layer_name(layer: int) -> String:
	match layer:
		RenderLayer.MOUNT_TAIL:
			return "MountTail"
		RenderLayer.CAPE:
			return "Cape"
		RenderLayer.MOUNT_BODY:
			return "MountBody"
		RenderLayer.BODY:
			return "Body"
		RenderLayer.BOOTS:
			return "Boots"
		RenderLayer.ARMOR:
			return "Armor"
		RenderLayer.HAIR:
			return "Hair"
		RenderLayer.HELMET:
			return "Helmet"
		RenderLayer.WEAPON:
			return "Weapon"
		RenderLayer.SHIELD:
			return "Shield"
		RenderLayer.MOUNT_HEAD:
			return "MountHead"
		RenderLayer.MOUNT_BARDING:
			return "MountBarding"
		_:
			return "Unknown"

static func z_index_for(layer: int, facing: int) -> int:
	match layer:
		RenderLayer.MOUNT_TAIL:
			return -10
		RenderLayer.CAPE:
			if facing == Facing.DOWN:
				return -5
			return 15 if facing == Facing.UP else 5
		RenderLayer.MOUNT_BODY:
			return 0
		RenderLayer.BODY:
			return 10
		RenderLayer.BOOTS:
			return 11
		RenderLayer.ARMOR:
			return 12
		RenderLayer.HAIR:
			return 13
		RenderLayer.HELMET:
			return 14
		RenderLayer.WEAPON:
			return -1 if facing == Facing.UP or facing == Facing.LEFT else 15
		RenderLayer.SHIELD:
			return -2 if facing == Facing.UP or facing == Facing.RIGHT else 16
		RenderLayer.MOUNT_HEAD:
			return -5 if facing == Facing.UP else 20
		RenderLayer.MOUNT_BARDING:
			return 1 if facing == Facing.UP else 21
		_:
			return 0

static func is_valid_visual_id(value: StringName) -> bool:
	var text := str(value)
	if text.is_empty():
		return false
	for index: int in range(text.length()):
		var code := text.unicode_at(index)
		var lower := code >= 97 and code <= 122
		var digit := code >= 48 and code <= 57
		if not lower and not digit and code != 95:
			return false
		if index == 0 and not lower:
			return false
	return true
