class_name CharacterRenderContract
extends RefCounted

## One projection contract shared by the character editor and the Terrain Lab.
## The viewport can be displayed at different UI sizes, but the 3D camera and
## map pixels-per-metre are derived from this single source.
const PREVIEW_VIEWPORT_SIZE := Vector2i(1280, 1536)
const MAP_PIXELS_PER_METRE := 37.12841796875
const TEXTURE_FILTER := CanvasItem.TEXTURE_FILTER_NEAREST

const FOOT_PROFILE := {
	"target": Vector3(0.0, 0.87, 0.0),
	# The map presenter uses a 1280x1536 render target. This is the old
	# 320x426 portrait framing expressed at the canonical target height, so
	# long weapons remain inside the same texture instead of being clipped.
	"size": 7.856338,
	"camera_y": 1.20,
	"camera_z": -4.65,
}
const MOUNT_PROFILE := {
	"target": Vector3(0.0, 1.15, 0.0),
	"size": 7.856338,
	"camera_y": 1.75,
	"camera_z": -6.10,
}

static func camera_profile(mounted: bool) -> Dictionary:
	return (MOUNT_PROFILE if mounted else FOOT_PROFILE).duplicate()

static func sprite_scale(viewport_size: Vector2i, camera_size: float) -> float:
	if viewport_size.y <= 0:
		return 1.0
	return MAP_PIXELS_PER_METRE * camera_size / float(viewport_size.y)
