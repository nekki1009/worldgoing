extends RefCounted
## CIV-A3 props (Nekki 2026-11-19 23:31Z): the hand-held box and water bucket of the civilian work clips. The images are
## Codex art (assets/characters/terrain_lab_army/civilian/props, CC-20261120-206); this file only places them. Each
## prop is an unshaded camera-facing quad in the editor's preview world, placed at the hands every sampled pose, so the
## original GPU capture draws it and the body occludes it naturally. In the dye-mask pass the quad is opaque black (no
## dye), so the colour and mask silhouettes stay identical.
##   civilian_carry, civilian_lift -> box between both hands
##   civilian_fetch_water          -> bucket in the right hand
const ROOT := "res://assets/characters/terrain_lab_army/civilian/props"
const MANIFEST := ROOT + "/props.json"
const CLIP_PROP := {"civilian_carry": "box", "civilian_lift": "box", "civilian_fetch_water": "bucket"}
const KEYS := ["box_front", "box_side", "bucket_front", "bucket_side"]

## Sources the civilian pages depend on (their md5s join the civilian fingerprint).
static func sources() -> Array[String]:
	var paths: Array[String] = [MANIFEST]
	for key: String in KEYS: paths.append(ROOT + "/" + key + ".png")
	return paths

static func available() -> bool:
	for path: String in sources():
		if not FileAccess.file_exists(path): return false
	return true

var _quads := {} # key -> MeshInstance3D
var _info := {}
var _skeleton: Skeleton3D

## Builds the four quads (hidden) in `world`. `masks`: the dye-mask pass draws them black. Returns false when the art
## or its manifest is missing or malformed.
func setup(world: Node3D, skeleton: Skeleton3D, masks: bool) -> bool:
	_skeleton = skeleton
	if not available(): return false
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	if not manifest is Dictionary: return false
	for key: String in KEYS:
		var row: Variant = manifest.get(key)
		if not row is Dictionary or not row.get("size_px") is Array or not row.get("grip_px") is Array or not (row.get("real_width_m") is float or row.get("real_width_m") is int): return false
		var image := Image.load_from_file(ROOT + "/" + key + ".png")
		if image == null or image.is_empty(): return false
		var width := float(row.real_width_m)
		var height := width * float(image.get_height()) / float(image.get_width())
		var quad := QuadMesh.new()
		quad.size = Vector2(width, height)
		# The grip point becomes the quad's origin: shift the mesh so (grip_px) sits at (0, 0).
		var grip := Vector2(float(row.grip_px[0]) / image.get_width(), float(row.grip_px[1]) / image.get_height())
		quad.center_offset = Vector3((0.5 - grip.x) * width, (grip.y - 0.5) * height, 0.0)
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		material.alpha_scissor_threshold = 0.5
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		material.albedo_texture = ImageTexture.create_from_image(image)
		if masks: material.albedo_color = Color(0, 0, 0, 1) # alpha still cut by the texture; RGB black = no dye
		quad.material = material
		var node := MeshInstance3D.new()
		node.name = "CivilianProp_" + key
		node.mesh = quad
		node.visible = false
		world.add_child(node)
		_quads[key] = node
		_info[key] = row
	return true

## After every seek: shows the prop of `clip` (side view when the yaw is +-90 degrees) at the hands, hides the rest.
func place(clip: String, yaw_degrees: float) -> void:
	for node: Variant in _quads.values(): node.visible = false
	var prop := str(CLIP_PROP.get(clip, ""))
	if prop.is_empty() or _skeleton == null: return
	var side := absf(absf(fposmod(yaw_degrees + 180.0, 360.0) - 180.0) - 90.0) < 1.0
	var node: MeshInstance3D = _quads.get(prop + ("_side" if side else "_front"))
	if node == null: return
	var left := _hand("J_Bip_L_Hand")
	var right := _hand("J_Bip_R_Hand")
	node.global_position = (left + right) * 0.5 if prop == "box" else right
	node.visible = true

func _hand(bone_name: String) -> Vector3:
	var bone := _skeleton.find_bone(bone_name)
	return _skeleton.global_transform * _skeleton.get_bone_global_pose(bone).origin if bone >= 0 else _skeleton.global_position
