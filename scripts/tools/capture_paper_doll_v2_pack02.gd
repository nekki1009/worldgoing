extends SceneTree

## GPU contact sheets for the isolated Pack 02 variable-slot surface.
## Outputs are placed under preview/ so they remain easy to open and share;
## formal V2 reference captures are never overwritten.

const OUTPUT_DIR := "res://preview/paper_doll_v2/pack_02"
const SCALE := 4

var _catalog: PaperDollV2Catalog
var _viewport: SubViewport
var _composer: PaperDollV2Composer
var _failures: PackedStringArray = []
var _report: Array[Dictionary] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_catalog = PaperDollV2Catalog.load_staging_pack_02()
	_failures.append_array(_catalog.last_issues)
	if _failures.is_empty():
		for state: int in [PaperDollV2Contract.RenderState.ON_FOOT, PaperDollV2Contract.RenderState.MOUNTED]:
			_create_viewport(state)
			await _settle()
			for gender: int in [PaperDollV2Contract.Gender.MALE, PaperDollV2Contract.Gender.FEMALE]:
				await _capture_case(gender, state)
		_write_report()
	if _failures.is_empty():
		print("PAPER_DOLL_V2_PACK02_CAPTURE_PASS cases=%d" % _report.size())
	else:
		for failure: String in _failures:
			push_error("PAPER_DOLL_V2_PACK02_CAPTURE_FAIL: %s" % failure)
		print("PAPER_DOLL_V2_PACK02_CAPTURE_FAIL failures=%d cases=%d" % [_failures.size(), _report.size()])
	quit(0 if _failures.is_empty() else 1)

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

func _capture_case(gender: int, state: int) -> void:
	var selection := {
		PaperDollV2Contract.RenderLayer.HAIR: &"pack02_hair_short_braid_01",
		PaperDollV2Contract.RenderLayer.ARMOR: &"pack02_leather_scale_armor_01",
		PaperDollV2Contract.RenderLayer.BOOTS: &"pack02_riding_boots_01",
		PaperDollV2Contract.RenderLayer.HELMET: &"pack02_open_sallet_01",
		PaperDollV2Contract.RenderLayer.CAPE: &"pack02_forest_cape_01",
		PaperDollV2Contract.RenderLayer.WEAPON: &"pack02_short_spear_01",
		PaperDollV2Contract.RenderLayer.SHIELD: &"pack02_round_shield_01",
	}
	if state == PaperDollV2Contract.RenderState.MOUNTED:
		selection[PaperDollV2Contract.RenderLayer.MOUNT_TAIL] = &"pack02_chestnut_horse_tail_01"
		selection[PaperDollV2Contract.RenderLayer.MOUNT_BODY] = &"pack02_chestnut_horse_body_01"
		selection[PaperDollV2Contract.RenderLayer.MOUNT_HEAD] = &"pack02_chestnut_horse_head_01"
		selection[PaperDollV2Contract.RenderLayer.MOUNT_BARDING] = &"pack02_forest_barding_01"
	var prefix := "female" if gender == PaperDollV2Contract.Gender.FEMALE else "male"
	var pose := "mounted" if state == PaperDollV2Contract.RenderState.MOUNTED else "on_foot"
	var body_prefix := "body_female_default" if gender == PaperDollV2Contract.Gender.FEMALE else "body_male_default"
	var body_id := StringName("%s_%s_unisex" % [body_prefix, pose])
	var recipe := _catalog.resolve_recipe(gender, state, selection, body_id, true)
	if recipe == null:
		_failures.append("%s_%s recipe: %s" % [prefix, pose, _catalog.last_issues])
		return
	if not _composer.apply_recipe(recipe):
		_failures.append("%s_%s composer: %s" % [prefix, pose, _composer.last_error])
		return
	var frame_size := PaperDollV2Contract.frame_size(state)
	var contact := Image.create(frame_size.x * PaperDollV2Contract.FRAME_COLUMNS, frame_size.y * 4, false, Image.FORMAT_RGBA8)
	contact.fill(Color("121821"))
	var metrics: Array[Dictionary] = []
	for facing: int in range(4):
		for frame_x: int in range(PaperDollV2Contract.FRAME_COLUMNS):
			if not _composer.update_frame(facing, frame_x):
				_failures.append("%s_%s frame update failed %d/%d" % [prefix, pose, facing, frame_x])
				continue
			await _settle()
			var image := _viewport.get_texture().get_image()
			var bbox := image.get_used_rect()
			if bbox.size.x <= 0 or bbox.size.y <= 0:
				_failures.append("%s_%s frame empty %d/%d" % [prefix, pose, facing, frame_x])
			elif bbox.position.x < 0 or bbox.position.y < 0 or bbox.end.x > frame_size.x or bbox.end.y > frame_size.y:
				_failures.append("%s_%s frame spills %d/%d: %s" % [prefix, pose, facing, frame_x, bbox])
			metrics.append({"facing": facing, "frame": frame_x, "bbox": str(bbox)})
			contact.blend_rect(image, Rect2i(Vector2i.ZERO, frame_size), Vector2i(frame_x * frame_size.x, facing * frame_size.y))
	var output_name := "pack02_%s_%s_contact.png" % [prefix, pose]
	var output_path := ProjectSettings.globalize_path(OUTPUT_DIR.path_join(output_name))
	DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
	var enlarged := contact.duplicate()
	enlarged.resize(contact.get_width() * SCALE, contact.get_height() * SCALE, Image.INTERPOLATE_NEAREST)
	if enlarged.save_png(output_path) != OK:
		_failures.append("could not save %s" % output_name)
	_report.append({
		"case": "%s_%s" % [prefix, pose],
		"output": OUTPUT_DIR.path_join(output_name),
		"gender": prefix,
		"state": pose,
		"frame_size": [frame_size.x, frame_size.y],
		"anchor": [PaperDollV2Contract.anchor_px(state).x, PaperDollV2Contract.anchor_px(state).y],
		"metrics": metrics,
	})

func _write_report() -> void:
	var output_path := ProjectSettings.globalize_path(OUTPUT_DIR.path_join("validation.json"))
	DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		_failures.append("could not write validation.json")
		return
	file.store_string(JSON.stringify({
		"result": "PASS" if _failures.is_empty() else "FAIL",
		"catalog": "PaperDollV2Catalog.load_staging_pack_02",
		"formal_manifest_touched": false,
		"cases": _report,
		"failures": Array(_failures),
	}, "\t"))
	file.close()

func _settle() -> void:
	await process_frame
	await process_frame
	await process_frame
