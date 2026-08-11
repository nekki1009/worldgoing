class_name PaperDollMountVisual
extends Resource

@export var mount_visual_id: StringName = &""
@export var tail: PaperDollLayerVisual
@export var body: PaperDollLayerVisual
@export var head: PaperDollLayerVisual

func validation_issues() -> PackedStringArray:
	var issues: PackedStringArray = []
	var label: String = str(mount_visual_id) if not mount_visual_id.is_empty() else "<empty mount id>"
	if not PaperDollLayerVisual.is_valid_visual_id(mount_visual_id):
		issues.append("%s: mount_visual_id must use lowercase ASCII snake_case" % label)
	_append_part_issues(issues, tail, PaperDollLayerVisual.RenderLayer.MOUNT_TAIL, "%s tail" % label)
	_append_part_issues(issues, body, PaperDollLayerVisual.RenderLayer.MOUNT_BODY, "%s body" % label)
	_append_part_issues(issues, head, PaperDollLayerVisual.RenderLayer.MOUNT_HEAD, "%s head" % label)
	return issues

func parts() -> Array[PaperDollLayerVisual]:
	return [tail, body, head]

static func _append_part_issues(
		issues: PackedStringArray,
		part: PaperDollLayerVisual,
		expected_layer: int,
		label: String
	) -> void:
	if part == null:
		issues.append("%s is missing" % label)
		return
	if part.render_layer != expected_layer:
		issues.append("%s uses the wrong render layer" % label)
	issues.append_array(part.validation_issues())
