extends SceneTree

## GPU-backed V2 reference capture.  The output is the actual V2 Composer,
## driven by calibrated boards derived from assets/doll/reference.  The strict
## pixel gate lives in verify_paper_doll_v2_reference.gd; this script produces
## a human-readable four-direction contact sheet from the same recipes.

const OUTPUT_DIR := "res://.visual_captures/paper_doll_v2"
const SCALE := 4

var _catalog: PaperDollV2Catalog
var _viewport: SubViewport
var _composer: PaperDollV2Composer
var _failures := PackedStringArray()
var _report: Array[Dictionary] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_catalog = PaperDollV2Catalog.load_generated_pack()
	_failures.append_array(_catalog.last_issues)
	_failures.append_array(_catalog.validation_issues())
	if not _failures.is_empty():
		_finish()
		return
	_create_viewport(PaperDollV2Contract.RenderState.ON_FOOT)
	await _settle()
	await _capture_case("male_on_foot_reference", PaperDollV2Contract.Gender.MALE, PaperDollV2Contract.RenderState.ON_FOOT, false)
	await _capture_case("male_on_foot_armed_reference", PaperDollV2Contract.Gender.MALE, PaperDollV2Contract.RenderState.ON_FOOT, true)
	await _capture_case("female_on_foot_reference", PaperDollV2Contract.Gender.FEMALE, PaperDollV2Contract.RenderState.ON_FOOT, false)
	await _capture_case("female_on_foot_armed_reference", PaperDollV2Contract.Gender.FEMALE, PaperDollV2Contract.RenderState.ON_FOOT, true)
	_create_viewport(PaperDollV2Contract.RenderState.MOUNTED)
	await _settle()
	await _capture_case("male_mounted_reference", PaperDollV2Contract.Gender.MALE, PaperDollV2Contract.RenderState.MOUNTED, false)
	await _capture_case("male_mounted_armed_reference", PaperDollV2Contract.Gender.MALE, PaperDollV2Contract.RenderState.MOUNTED, true)
	await _capture_case("female_mounted_reference", PaperDollV2Contract.Gender.FEMALE, PaperDollV2Contract.RenderState.MOUNTED, false)
	await _capture_case("female_mounted_armed_reference", PaperDollV2Contract.Gender.FEMALE, PaperDollV2Contract.RenderState.MOUNTED, true)
	_write_report()
	_finish()

func _create_viewport(state: int) -> void:
	if _viewport != null:
		_viewport.queue_free()
	_viewport = SubViewport.new()
	_viewport.size = PaperDollV2Contract.frame_size(state)
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	get_root().add_child(_viewport)
	_composer = PaperDollV2Composer.new()
	_composer.position = Vector2(PaperDollV2Contract.anchor_px(state))
	_viewport.add_child(_composer)

func _capture_case(case_id: String, gender: int, state: int, armed: bool) -> void:
	var prefix := "reference_female_" if gender == PaperDollV2Contract.Gender.FEMALE else "reference_"
	var pose := "armed_" if armed else "body_"
	var state_name := "mounted" if state == PaperDollV2Contract.RenderState.MOUNTED else "on_foot"
	var reference_id := StringName(prefix + pose + state_name)
	var recipe := _catalog.resolve_reference_recipe(gender, state, reference_id)
	if recipe == null:
		_failures.append("%s recipe: %s" % [case_id, _catalog.last_issues])
		return
	if not _composer.apply_recipe(recipe):
		_failures.append("%s composer: %s" % [case_id, _composer.last_error])
		return
	# The calibrated board already contains the accepted palette.  Do not tint
	# a flattened board; it has no per-layer masks.
	_composer.clear_dyes()
	var frame_size := PaperDollV2Contract.frame_size(state)
	var contact := Image.create(frame_size.x * PaperDollV2Contract.FRAME_COLUMNS, frame_size.y * 4, false, Image.FORMAT_RGBA8)
	contact.fill(Color("121821"))
	var metrics: Array[Dictionary] = []
	for facing: int in range(4):
		for frame_x: int in range(PaperDollV2Contract.FRAME_COLUMNS):
			if not _composer.update_frame(facing, frame_x):
				_failures.append("%s facing=%d frame=%d update failed" % [case_id, facing, frame_x])
				continue
			await _settle()
			var image := _viewport.get_texture().get_image()
			if image == null or image.is_empty():
				_failures.append("%s facing=%d frame=%d empty" % [case_id, facing, frame_x])
				continue
			var bbox := image.get_used_rect()
			var metric := {
				"facing": facing,
				"frame": frame_x,
				"bbox": str(bbox),
				"width": bbox.size.x,
				"height": bbox.size.y,
				"bottom": bbox.end.y,
			}
			metrics.append(metric)
			if bbox.size.x <= 0 or bbox.size.y <= 0:
				_failures.append("%s facing=%d frame=%d empty bbox" % [case_id, facing, frame_x])
			if bbox.position.x < 0 or bbox.position.y < 0 or bbox.end.x > frame_size.x or bbox.end.y > frame_size.y:
				_failures.append("%s facing=%d frame=%d spills frame: %s" % [case_id, facing, frame_x, bbox])
			contact.blend_rect(image, Rect2i(Vector2i.ZERO, frame_size), Vector2i(frame_x * frame_size.x, facing * frame_size.y))
	var output_path := ProjectSettings.globalize_path(OUTPUT_DIR.path_join("%s_contact.png" % case_id))
	var enlarged := contact.duplicate()
	enlarged.resize(contact.get_width() * SCALE, contact.get_height() * SCALE, Image.INTERPOLATE_NEAREST)
	DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
	if enlarged.save_png(output_path) != OK:
		_failures.append("%s output save failed" % case_id)
	_report.append({
		"case": case_id,
		"state": PaperDollV2Contract.state_name(state),
		"gender": PaperDollV2Contract.gender_name(gender),
		"frame_size": [frame_size.x, frame_size.y],
		"anchor": [PaperDollV2Contract.anchor_px(state).x, PaperDollV2Contract.anchor_px(state).y],
		"metrics": metrics,
		"output": "res://.visual_captures/paper_doll_v2/%s_contact.png" % case_id,
	})
	var down := metrics[0]
	var up := metrics[PaperDollV2Contract.FRAME_COLUMNS]
	if state == PaperDollV2Contract.RenderState.ON_FOOT \
			and (up["width"] as int) > (down["width"] as int) + 4:
		_failures.append("%s UP is wider than DOWN: up=%d down=%d" % [case_id, up["width"], down["width"]])
	if state == PaperDollV2Contract.RenderState.MOUNTED:
		await _validate_mounted_rider_width(case_id, recipe)

func _validate_mounted_rider_width(case_id: String, recipe: PaperDollV2Recipe) -> void:
	if recipe.is_reference_composite:
		return
	# Horse silhouette and cape are intentionally excluded: the acceptance rule
	# is about the rider core, not comparing a horse's back width with its head.
	var hidden_layers := [
		PaperDollV2Contract.RenderLayer.MOUNT_TAIL,
		PaperDollV2Contract.RenderLayer.MOUNT_BODY,
		PaperDollV2Contract.RenderLayer.MOUNT_HEAD,
		PaperDollV2Contract.RenderLayer.MOUNT_BARDING,
		PaperDollV2Contract.RenderLayer.CAPE,
		PaperDollV2Contract.RenderLayer.WEAPON,
		PaperDollV2Contract.RenderLayer.SHIELD,
	]
	var old_visibility := {}
	for layer: int in hidden_layers:
		var sprite := _composer.sprite_for(layer)
		old_visibility[layer] = sprite.visible
		sprite.visible = false
	var widths: Array[int] = []
	for facing: int in [PaperDollV2Contract.Facing.DOWN, PaperDollV2Contract.Facing.UP]:
		_composer.update_frame(facing, 0)
		await _settle()
		var bbox := _viewport.get_texture().get_image().get_used_rect()
		widths.append(bbox.size.x)
	for layer: int in hidden_layers:
		_composer.sprite_for(layer).visible = old_visibility[layer]
	_composer.apply_recipe(recipe)
	if widths.size() == 2 and widths[1] > widths[0] + 4:
		_failures.append("%s rider core UP is wider than DOWN: up=%d down=%d" % [case_id, widths[1], widths[0]])

func _write_report() -> void:
	var path := ProjectSettings.globalize_path(OUTPUT_DIR.path_join("report.json"))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({
			"result": "PASS" if _failures.is_empty() else "FAIL",
			"failures": Array(_failures),
			"captures": _report,
			"contract": "V2 actual Composer, state-sized frames, four directions x eight frames",
		}, "\t"))
		file.close()

func _finish() -> void:
	if _failures.is_empty():
		print("PAPER_DOLL_V2_REFERENCE_CAPTURE_PASS captures=%d" % _report.size())
	else:
		for failure: String in _failures:
			push_error("PAPER_DOLL_V2_REFERENCE_CAPTURE_FAIL: %s" % failure)
		print("PAPER_DOLL_V2_REFERENCE_CAPTURE_FAIL failures=%d captures=%d" % [_failures.size(), _report.size()])
	quit(0 if _failures.is_empty() else 1)

func _settle() -> void:
	await process_frame
	await process_frame
	await process_frame
