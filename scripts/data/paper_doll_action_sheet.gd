class_name PaperDollActionSheet
extends RefCounted

## Deterministic presentation fallback for split parts that do not yet have a
## dedicated action sheet.  It preserves the 512x192 / 8x3 contract, so every
## Sprite2D still uses one shared frame controller and every equipment choice
## remains independently replaceable.

static func build(
		sheet: Texture2D,
		layer: int,
		action: int,
		mounted: bool
	) -> Texture2D:
	if sheet == null or not PaperDollAnimation.is_valid_action(action) \
			or action == PaperDollAnimation.Action.IDLE:
		return sheet
	var source: Image = sheet.get_image()
	if source == null or source.is_empty():
		return sheet
	if source.is_compressed():
		source.decompress()
	if source.get_format() != Image.FORMAT_RGBA8:
		source.convert(Image.FORMAT_RGBA8)
	var output: Image = Image.create(
		PaperDollLayerVisual.SHEET_SIZE.x,
		PaperDollLayerVisual.SHEET_SIZE.y,
		false,
		Image.FORMAT_RGBA8
	)
	output.fill(Color.TRANSPARENT)
	var frame_map: PackedInt32Array = _frame_map(action)
	for row: int in range(PaperDollLayerVisual.SOURCE_ROWS):
		for frame_x: int in range(PaperDollLayerVisual.FRAME_COLUMNS):
			var source_x: int = frame_map[frame_x]
			var frame: Image = source.get_region(Rect2i(
				Vector2i(source_x * PaperDollLayerVisual.FRAME_SIZE.x, row * PaperDollLayerVisual.FRAME_SIZE.y),
				PaperDollLayerVisual.FRAME_SIZE
			))
			var transformed: Image = _transform_frame(frame, layer, action, frame_x, row, mounted)
			output.blit_rect(
				transformed,
				Rect2i(Vector2i.ZERO, PaperDollLayerVisual.FRAME_SIZE),
				Vector2i(frame_x * PaperDollLayerVisual.FRAME_SIZE.x, row * PaperDollLayerVisual.FRAME_SIZE.y)
			)
	return ImageTexture.create_from_image(output)

static func _frame_map(_action: int) -> PackedInt32Array:
	# Keep source columns stable. The shared controller selects the sparse clip
	# itself; remapping here would sample different columns per layer.
	return PackedInt32Array([0, 1, 2, 3, 4, 5, 6, 7])

static func _transform_frame(
		frame: Image,
		layer: int,
		action: int,
		frame_x: int,
		row: int,
		mounted: bool
	) -> Image:
	var phase: float = float(frame_x) / 7.0
	var bounce: int = 0
	match action:
		PaperDollAnimation.Action.WALK:
			return _walk_or_run_frame(frame, layer, frame_x, row, mounted, false)
		PaperDollAnimation.Action.RUN:
			return _walk_or_run_frame(frame, layer, frame_x, row, mounted, true)
		PaperDollAnimation.Action.ATTACK, PaperDollAnimation.Action.SPRINT_ATTACK:
			# The fallback is deliberately one shared pose transform.  A previous
			# version moved only the weapon, which made the sword detach from the
			# hand and made attack frames look like idle frames.
			var attack_upper: Vector2i = Vector2i(
				[0, 1, 2, 1, 0, -1, 0, 0][frame_x],
				[0, -1, -2, -1, 0, 1, 0, -1][frame_x]
			)
			var attack_lower: Vector2i = Vector2i(
				[0, 0, 1, 0, -1, -1, 0, 0][frame_x], 0
			)
			if action == PaperDollAnimation.Action.SPRINT_ATTACK:
				attack_upper.x += [0, 1, 2, 1, 0, -1, 0, 0][frame_x]
				attack_lower.x += [0, 1, 1, 0, -1, -1, 0, 0][frame_x]
			if layer in _rider_layers():
				if layer == PaperDollLayerVisual.RenderLayer.WEAPON:
					return _attack_weapon_frame(frame, row, frame_x, mounted, attack_upper.y)
				return _split_shift_frame(frame, attack_upper, attack_lower, 36 if mounted else 34)
			bounce = attack_upper.y
		PaperDollAnimation.Action.WORK:
			bounce = [0, -1, -2, -1, -2, -1, 0, -1][frame_x]
			if layer in _rider_layers():
				var work_upper := Vector2i(
					[0, 0, 1, 1, 1, 0, 0, 0][frame_x], bounce
				)
				var work_lower := Vector2i([0, 0, 1, 1, 0, 0, 0, 0][frame_x], 0)
				return _split_shift_frame(frame, work_upper, work_lower, 36 if mounted else 34)
		PaperDollAnimation.Action.HIT:
			bounce = [0, 0, -1, -1, 0, 1, 1, 0][frame_x]
			if layer in _rider_layers():
				var recoil := Vector2i(
					[0, -1, -2, -1, 1, 2, 1, 0][frame_x], bounce
				)
				return _split_shift_frame(frame, recoil, Vector2i.ZERO, 36 if mounted else 34)
		PaperDollAnimation.Action.DOWN:
			if layer in _rider_layers():
				# On foot the body falls around its centre.  Mounted characters fall
				# off the saddle while the horse layers remain upright.
				var pivot := Vector2(32.0, 32.0) if not mounted else Vector2(32.0, 24.0)
				var angle: float = PI * 0.5 if row != PaperDollLayerVisual.Facing.UP else -PI * 0.5
				return _rotate_frame(frame, angle, pivot, Vector2.ZERO)
			bounce = 2

	if layer == PaperDollLayerVisual.RenderLayer.WEAPON \
			and action in [PaperDollAnimation.Action.ATTACK, PaperDollAnimation.Action.SPRINT_ATTACK]:
		var angle_start: float = -0.75 if row != PaperDollLayerVisual.Facing.UP else 0.75
		var angle_end: float = 1.20 if row != PaperDollLayerVisual.Facing.UP else -1.20
		return _rotate_frame(
			frame,
			lerpf(angle_start, angle_end, phase),
			Vector2(46.0, 40.0),
			Vector2(0.0, bounce)
		)
	if layer == PaperDollLayerVisual.RenderLayer.SHIELD \
			and action == PaperDollAnimation.Action.SPRINT_ATTACK:
		return _shift_frame(frame, 0, bounce - 1)
	if layer == PaperDollLayerVisual.RenderLayer.CAPE:
		var cape_sway: int = roundi(sin(phase * TAU) * (2.0 if action != PaperDollAnimation.Action.HIT else 1.0))
		return _shift_frame(frame, cape_sway, bounce)
	if layer == PaperDollLayerVisual.RenderLayer.MOUNT_HEAD \
			and action in [PaperDollAnimation.Action.RUN, PaperDollAnimation.Action.SPRINT_ATTACK]:
		return _shift_frame(frame, 0, floori(float(bounce) * 0.5))
	if layer == PaperDollLayerVisual.RenderLayer.MOUNT_BODY \
			and action in [PaperDollAnimation.Action.WORK, PaperDollAnimation.Action.HIT]:
		return _split_shift_frame(frame, Vector2i(0, bounce), Vector2i([0, -1, 1, 1, 0, -1, 1, 0][frame_x], 0), 38)
	if layer == PaperDollLayerVisual.RenderLayer.MOUNT_TAIL \
			and action != PaperDollAnimation.Action.DOWN:
		return _shift_frame(frame, [0, 1, 2, 1, 0, -1, -2, -1][frame_x], 0)
	return _shift_frame(frame, 0, bounce)

static func _rider_layers() -> Array[int]:
	return [
		PaperDollLayerVisual.RenderLayer.BODY,
		PaperDollLayerVisual.RenderLayer.ARMOR,
		PaperDollLayerVisual.RenderLayer.HAIR,
		PaperDollLayerVisual.RenderLayer.HELMET,
		PaperDollLayerVisual.RenderLayer.CAPE,
		PaperDollLayerVisual.RenderLayer.WEAPON,
		PaperDollLayerVisual.RenderLayer.SHIELD,
	]

static func _attack_weapon_frame(
		frame: Image,
		_row: int,
		frame_x: int,
		mounted: bool,
		delta_y: int
	) -> Image:
	# The source weapon is already aligned to the hand for each direction.  Use
	# a small swing around that hand pivot instead of rotating around the frame
	# centre (which was the source of detached/off-screen weapons).
	var pivot := Vector2(34.0, 28.0) if _row <= PaperDollLayerVisual.Facing.UP else Vector2(35.0, 38.0)
	if mounted:
		pivot += Vector2(0.0, -3.0)
	var angle_start: float = -0.22 if _row != PaperDollLayerVisual.Facing.UP else 0.22
	var angle_end: float = 0.42 if _row != PaperDollLayerVisual.Facing.UP else -0.42
	return _rotate_frame(
		frame,
		lerpf(angle_start, angle_end, float(frame_x) / 7.0),
		pivot,
		Vector2(0.0, delta_y)
	)

static func _walk_or_run_frame(
		frame: Image,
		layer: int,
		frame_x: int,
		_row: int,
		mounted: bool,
		run: bool
	) -> Image:
	var leg_phase: Array = [
		-2, 0, 2, 1, -1, -2, 1, 2
	] if run else [
		-1, 0, 1, 1, -1, -1, 0, 1
	]
	var bob: Array = [0, -1, -2, -1, 0, 1, 0, -1] if run else [0, -1, 0, 1, 0, -1, 0, 1]
	var lean: Array = [0, 1, 1, 0, -1, -1, 0, 1] if run else [0, 0, 1, 0, -1, 0, 0, 1]
	var upper := Vector2i(lean[frame_x], bob[frame_x])
	var lower := Vector2i(leg_phase[frame_x], 0)
	if layer in [PaperDollLayerVisual.RenderLayer.BODY, PaperDollLayerVisual.RenderLayer.ARMOR]:
		return _split_shift_frame(frame, upper, lower, 34)
	if layer in [PaperDollLayerVisual.RenderLayer.HAIR, PaperDollLayerVisual.RenderLayer.HELMET]:
		return _shift_frame(frame, upper.x, upper.y)
	if layer == PaperDollLayerVisual.RenderLayer.CAPE:
		var sway: int = [0, 1, 2, 1, 0, -1, -2, -1][frame_x]
		return _split_shift_frame(frame, Vector2i(sway + upper.x, upper.y), Vector2i(sway, 0), 38)
	if layer == PaperDollLayerVisual.RenderLayer.WEAPON:
		return _shift_frame(frame, leg_phase[frame_x] / 2, bob[frame_x])
	if layer == PaperDollLayerVisual.RenderLayer.SHIELD:
		return _shift_frame(frame, -leg_phase[frame_x] / 2, bob[frame_x])
	if mounted and layer == PaperDollLayerVisual.RenderLayer.MOUNT_BODY:
		return _split_shift_frame(frame, Vector2i(0, bob[frame_x]), lower, 38)
	if mounted and layer == PaperDollLayerVisual.RenderLayer.MOUNT_HEAD:
		return _shift_frame(frame, 0, bob[frame_x])
	if mounted and layer == PaperDollLayerVisual.RenderLayer.MOUNT_TAIL:
		return _shift_frame(frame, [0, 1, 2, 1, 0, -1, -2, -1][frame_x], bob[frame_x] / 2)
	return _shift_frame(frame, upper.x, upper.y)

static func _split_shift_frame(source: Image, upper: Vector2i, lower: Vector2i, split_y: int) -> Image:
	var output: Image = Image.create(64, 64, false, Image.FORMAT_RGBA8)
	output.fill(Color.TRANSPARENT)
	for y: int in range(64):
		for x: int in range(64):
			var pixel: Color = source.get_pixel(x, y)
			if pixel.a <= 0.01:
				continue
			var shift: Vector2i = lower if y >= split_y else upper
			var target := Vector2i(x, y) + shift
			if target.x >= 0 and target.x < 64 and target.y >= 0 and target.y < 64:
				output.set_pixelv(target, pixel)
	return output

static func _shift_frame(source: Image, dx: int, dy: int) -> Image:
	var output: Image = Image.create(64, 64, false, Image.FORMAT_RGBA8)
	output.fill(Color.TRANSPARENT)
	output.blit_rect(
		source,
		Rect2i(Vector2i.ZERO, Vector2i(64, 64)),
		Vector2i(dx, dy)
	)
	return output

static func _rotate_frame(source: Image, angle: float, pivot: Vector2, offset: Vector2) -> Image:
	var output: Image = Image.create(64, 64, false, Image.FORMAT_RGBA8)
	output.fill(Color.TRANSPARENT)
	var cosine: float = cos(angle)
	var sine: float = sin(angle)
	for y: int in range(64):
		for x: int in range(64):
			var pixel: Color = source.get_pixel(x, y)
			if pixel.a <= 0.01:
				continue
			var delta: Vector2 = Vector2(x, y) - pivot
			var destination: Vector2 = Vector2(
				pivot.x + delta.x * cosine - delta.y * sine,
				pivot.y + delta.x * sine + delta.y * cosine
			) + offset
			var target: Vector2i = Vector2i(roundi(destination.x), roundi(destination.y))
			if target.x >= 0 and target.x < 64 and target.y >= 0 and target.y < 64:
				output.set_pixelv(target, pixel)
	return output
