class_name PaperDollLayerVisual
extends Resource

enum Gender {
	MALE,
	FEMALE,
}

enum GenderPolicy {
	GENDERED,
	UNISEX,
}

enum Facing {
	DOWN,
	UP,
	RIGHT,
	LEFT,
}

enum RenderLayer {
	MOUNT_TAIL,
	CAPE,
	MOUNT_BODY,
	BODY,
	ARMOR,
	HAIR,
	HELMET,
	WEAPON,
	SHIELD,
	MOUNT_HEAD,
	MOUNT_BARDING,
	COUNT,
}

const FRAME_SIZE: Vector2i = Vector2i(64, 64)
const SHEET_SIZE: Vector2i = Vector2i(512, 192)
const FRAME_COLUMNS: int = 8
const SOURCE_ROWS: int = 3
const WORLD_ANCHOR: Vector2 = Vector2(32.0, 56.0)
const SPRITE_OFFSET: Vector2 = -WORLD_ANCHOR
const CAPE_SHOULDER_TOP: int = 22
# Side-facing horse muzzle pixels may remain in this upper band; every horse
# foreground pixel below it must leave the rider's Body/Armor silhouette clear.
const MOUNT_RIDER_CLEARANCE_HEAD_END: int = 12
# In frontal mounted views the horse neck/head belongs in front of the
# rider's lower torso.  Preserve that overlap below the rider's chest while
# keeping the face/head band clear.
const MOUNT_FRONT_HEAD_OVERLAP_START: int = 28

@export var visual_id: StringName = &""
@export_enum(
	"Mount Tail", "Cape", "Mount Body", "Body", "Armor", "Hair",
	"Helmet", "Weapon", "Shield", "Mount Head", "Mount Barding"
) var render_layer: int = RenderLayer.BODY
@export_enum("Gendered", "Unisex") var gender_policy: int = GenderPolicy.GENDERED

@export_group("On Foot")
@export var on_foot_male: Texture2D
@export var on_foot_female: Texture2D
@export var on_foot_unisex: Texture2D

@export_group("Mounted")
@export var mounted_male: Texture2D
@export var mounted_female: Texture2D
@export var mounted_unisex: Texture2D

## Optional action-specific sheets.  Indexes use PaperDollAnimation.Action.
## Each supplied sheet keeps the same 8 columns x 3 direction rows contract.
## Empty entries deliberately fall back to the pose's base sheet.
@export_group("Optional Action Sheets")
@export var on_foot_action_sheets: Array[Texture2D] = []
@export var mounted_action_sheets: Array[Texture2D] = []

func has_action_sheet(is_mounted: bool, action: int) -> bool:
	if not PaperDollAnimation.is_valid_action(action):
		return false
	var sheets: Array[Texture2D] = mounted_action_sheets if is_mounted else on_foot_action_sheets
	return action < sheets.size() and sheets[action] != null

func resolve(gender: int, is_mounted: bool) -> Texture2D:
	if not is_valid_gender(gender):
		return null
	if gender_policy == GenderPolicy.UNISEX:
		return mounted_unisex if is_mounted else on_foot_unisex
	if gender_policy != GenderPolicy.GENDERED:
		return null
	if is_mounted:
		return mounted_male if gender == Gender.MALE else mounted_female
	return on_foot_male if gender == Gender.MALE else on_foot_female

func resolve_action(gender: int, is_mounted: bool, action: int) -> Texture2D:
	var base: Texture2D = resolve(gender, is_mounted)
	if not PaperDollAnimation.is_valid_action(action):
		return base
	var sheets: Array[Texture2D] = mounted_action_sheets if is_mounted else on_foot_action_sheets
	if action < sheets.size() and sheets[action] != null:
		return sheets[action]
	return base

func validation_issues() -> PackedStringArray:
	var issues: PackedStringArray = []
	var label: String = str(visual_id) if not visual_id.is_empty() else "<empty visual id>"
	if not is_valid_visual_id(visual_id):
		issues.append("%s: visual_id must use lowercase ASCII snake_case" % label)
	if not is_valid_layer(render_layer):
		issues.append("%s: render_layer is invalid" % label)
		return issues
	if gender_policy < GenderPolicy.GENDERED or gender_policy > GenderPolicy.UNISEX:
		issues.append("%s: gender_policy is invalid" % label)
		return issues

	if is_mounted_only_layer(render_layer):
		if is_mount_intrinsic_layer(render_layer) and gender_policy != GenderPolicy.UNISEX:
			issues.append("%s: intrinsic mount layers must be UNISEX" % label)
		if gender_policy == GenderPolicy.UNISEX:
			_append_texture_issue(issues, mounted_unisex, "%s mounted_unisex" % label)
		else:
			_append_texture_issue(issues, mounted_male, "%s mounted_male" % label)
			_append_texture_issue(issues, mounted_female, "%s mounted_female" % label)
		_validate_action_sheets(issues, label)
		return issues

	if gender_policy == GenderPolicy.UNISEX:
		_append_texture_issue(issues, on_foot_unisex, "%s on_foot_unisex" % label)
		_append_texture_issue(issues, mounted_unisex, "%s mounted_unisex" % label)
	else:
		_append_texture_issue(issues, on_foot_male, "%s on_foot_male" % label)
		_append_texture_issue(issues, on_foot_female, "%s on_foot_female" % label)
		_append_texture_issue(issues, mounted_male, "%s mounted_male" % label)
		_append_texture_issue(issues, mounted_female, "%s mounted_female" % label)
	_validate_action_sheets(issues, label)
	return issues

func _validate_action_sheets(issues: PackedStringArray, label: String) -> void:
	for action: int in range(PaperDollAnimation.Action.COUNT):
		if action < on_foot_action_sheets.size() and on_foot_action_sheets[action] != null:
			_append_texture_issue(
				issues,
				on_foot_action_sheets[action],
				"%s on_foot action %s" % [label, PaperDollAnimation.action_name(action)]
			)
		if action < mounted_action_sheets.size() and mounted_action_sheets[action] != null:
			_append_texture_issue(
				issues,
				mounted_action_sheets[action],
				"%s mounted action %s" % [label, PaperDollAnimation.action_name(action)]
			)

static func is_valid_visual_id(value: StringName) -> bool:
	var text: String = str(value)
	if text.is_empty():
		return false
	for index: int in range(text.length()):
		var code: int = text.unicode_at(index)
		var is_lower: bool = code >= 97 and code <= 122
		var is_digit: bool = code >= 48 and code <= 57
		if not is_lower and not is_digit and code != 95:
			return false
		if index == 0 and not is_lower:
			return false
	return true

static func is_valid_gender(gender: int) -> bool:
	return gender == Gender.MALE or gender == Gender.FEMALE

static func is_valid_facing(facing: int) -> bool:
	return facing >= Facing.DOWN and facing <= Facing.LEFT

static func is_valid_layer(layer: int) -> bool:
	return layer >= RenderLayer.MOUNT_TAIL and layer < RenderLayer.COUNT

static func is_mount_intrinsic_layer(layer: int) -> bool:
	return layer == RenderLayer.MOUNT_TAIL \
		or layer == RenderLayer.MOUNT_BODY \
		or layer == RenderLayer.MOUNT_HEAD

static func is_mounted_only_layer(layer: int) -> bool:
	return is_mount_intrinsic_layer(layer) or layer == RenderLayer.MOUNT_BARDING

static func source_row_for(facing: int) -> int:
	return Facing.RIGHT if facing == Facing.LEFT else facing

static func armor_top_cut(_is_mounted: bool, _source_row: int) -> int:
	# The reference armor includes shoulder/collar pixels above the Body's
	# torso centre.  Keep that upper shoulder band; the packer separately clears
	# only pixels that actually overlap the face.  This prevents the runtime
	# armor from degenerating into leg plates while preserving the head slot.
	return 18

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

static func gender_name(gender: int) -> String:
	return "male" if gender == Gender.MALE else "female"

static func pose_name(is_mounted: bool) -> String:
	return "mounted" if is_mounted else "on_foot"

static func _append_texture_issue(
		issues: PackedStringArray,
		texture: Texture2D,
		label: String
	) -> void:
	if texture == null:
		issues.append("%s is missing" % label)
		return
	if Vector2i(texture.get_width(), texture.get_height()) != SHEET_SIZE:
		issues.append("%s must be %dx%d" % [label, SHEET_SIZE.x, SHEET_SIZE.y])
		return
	var image: Image = texture.get_image()
	if image == null or image.is_empty():
		issues.append("%s is not readable" % label)
		return
	if image.is_compressed() and image.decompress() != OK:
		issues.append("%s cannot be decompressed" % label)
		return
	if image.get_format() != Image.FORMAT_RGBA8:
		issues.append("%s must use RGBA8" % label)
		return
	if image.detect_alpha() == Image.ALPHA_NONE:
		issues.append("%s requires transparent pixels" % label)
	for row: int in range(SOURCE_ROWS):
		for frame_x: int in range(FRAME_COLUMNS):
			var frame: Image = image.get_region(Rect2i(
				Vector2i(frame_x * FRAME_SIZE.x, row * FRAME_SIZE.y),
				FRAME_SIZE
			))
			if frame.is_invisible():
				issues.append("%s frame (%d,%d) is empty" % [label, frame_x, row])
