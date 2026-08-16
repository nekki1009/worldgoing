extends SceneTree

## Deterministic admission test for the isolated Pack 02 lab.
## It checks every V2 variable layer without changing the formal manifest.

const PACK02_IDS := [
	"pack02_hair_short_braid_01",
	"pack02_leather_scale_armor_01",
	"pack02_riding_boots_01",
	"pack02_open_sallet_01",
	"pack02_forest_cape_01",
	"pack02_short_spear_01",
	"pack02_round_shield_01",
	"pack02_chestnut_horse_tail_01",
	"pack02_chestnut_horse_body_01",
	"pack02_chestnut_horse_head_01",
	"pack02_forest_barding_01",
]

var _failures: PackedStringArray = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var catalog := PaperDollV2Catalog.load_staging_pack_02()
	_failures.append_array(catalog.last_issues)
	var staging_count := 0
	for manifest: PaperDollV2AssetManifest in catalog.manifests:
		if manifest != null and str(manifest.visual_id).begins_with("pack02_"):
			staging_count += 1
			if not manifest.source_path.begins_with(PaperDollV2Catalog.PACK_02_ROOT):
				_failures.append("Pack 02 manifest escaped staging: %s" % manifest.source_path)
	for id_text: String in PACK02_IDS:
		var visual_id := StringName(id_text)
		var layer := _layer_for_id(visual_id)
		var states := [PaperDollV2Contract.RenderState.MOUNTED] if PaperDollV2Contract.is_mount_layer(layer) and layer != PaperDollV2Contract.RenderLayer.MOUNT_BARDING else [PaperDollV2Contract.RenderState.ON_FOOT, PaperDollV2Contract.RenderState.MOUNTED]
		if layer == PaperDollV2Contract.RenderLayer.MOUNT_BARDING:
			states = [PaperDollV2Contract.RenderState.MOUNTED]
		for state: int in states:
			var genders := [PaperDollV2Contract.Gender.MALE, PaperDollV2Contract.Gender.FEMALE]
			for gender: int in genders:
				var manifest := catalog.find_visual(visual_id, layer, state, gender)
				if manifest == null:
					_failures.append("missing Pack 02 visual=%s state=%s gender=%s" % [id_text, PaperDollV2Contract.state_name(state), PaperDollV2Contract.gender_name(gender)])
				elif not manifest.validation_issues(catalog.template_for(state, gender if manifest.gender_policy == PaperDollV2Contract.GenderPolicy.GENDERED else PaperDollV2Contract.Gender.MALE)).is_empty():
					_failures.append("invalid Pack 02 manifest: %s" % id_text)
	if staging_count != 20:
		_failures.append("expected 20 Pack 02 manifests (gendered hair x4 + 6 unisex pairs + 4 mount layers), got %d" % staging_count)
	for gender: int in [PaperDollV2Contract.Gender.MALE, PaperDollV2Contract.Gender.FEMALE]:
		var foot_selection := _selection(false)
		var foot_recipe := catalog.resolve_recipe(gender, PaperDollV2Contract.RenderState.ON_FOOT, foot_selection, _body_id(gender, false), false)
		if foot_recipe == null:
			_failures.append("Pack 02 on-foot recipe failed for %s: %s" % [PaperDollV2Contract.gender_name(gender), catalog.last_issues])
		var mounted_selection := _selection(true)
		var mounted_recipe := catalog.resolve_recipe(gender, PaperDollV2Contract.RenderState.MOUNTED, mounted_selection, _body_id(gender, true), true)
		if mounted_recipe == null:
			_failures.append("Pack 02 mounted recipe failed for %s: %s" % [PaperDollV2Contract.gender_name(gender), catalog.last_issues])
	_verify_body_eye_landmarks()
	if _failures.is_empty():
		print("PAPER_DOLL_V2_PACK02_VERIFY_PASS manifests=%d recipes=4 body_eyes=mirrored_front_rows formal_manifest_touched=false" % staging_count)
	else:
		for failure: String in _failures:
			push_error("PAPER_DOLL_V2_PACK02_VERIFY_FAIL: %s" % failure)
		print("PAPER_DOLL_V2_PACK02_VERIFY_FAIL failures=%d" % _failures.size())
	quit(0 if _failures.is_empty() else 1)

func _verify_body_eye_landmarks() -> void:
	# This is a source-layer regression check, not a face-probe capture.  The
	# accepted evidence is the normalized Body texture consumed by the V2
	# recipe.  Every gender/state DOWN frame must have two equal 2-pixel-wide
	# eyes, no residual dark tail below them, and byte-identical mirrored eye
	# pixels.  Side/back rows are intentionally not checked: they are authored
	# profiles with one-eye/zero-eye semantics rather than a front face.
	var frame_motion: Array[Vector2i] = [
		Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, 0),
		Vector2i(0, -1), Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 0),
	]
	for state: int in [PaperDollV2Contract.RenderState.ON_FOOT, PaperDollV2Contract.RenderState.MOUNTED]:
		var pose := "mounted" if state == PaperDollV2Contract.RenderState.MOUNTED else "on_foot"
		for gender: int in [PaperDollV2Contract.Gender.MALE, PaperDollV2Contract.Gender.FEMALE]:
			var gender_name := PaperDollV2Contract.gender_name(gender)
			var path := "res://assets/paper_doll/v2/parts/body_%s_default_%s_unisex.png" % [gender_name, pose]
			var image := Image.load_from_file(ProjectSettings.globalize_path(path))
			if image == null or image.is_empty():
				_failures.append("%s Body eye source missing: %s" % [gender_name, path])
				continue
			var cell := PaperDollV2Contract.frame_size(state)
			var eye_y := 48 if state == PaperDollV2Contract.RenderState.MOUNTED else 15
			var left_x := 28 if state == PaperDollV2Contract.RenderState.MOUNTED else (26 if gender == PaperDollV2Contract.Gender.FEMALE else 27)
			var right_x := 35 if state == PaperDollV2Contract.RenderState.MOUNTED else 36
			var eye_height := 3 if state == PaperDollV2Contract.RenderState.MOUNTED else 4
			for frame_x: int in range(PaperDollV2Contract.FRAME_COLUMNS):
				var motion_origin := Vector2i(frame_x * cell.x, 0) + frame_motion[frame_x]
				for y: int in range(eye_height):
					for x: int in range(2):
						var left := image.get_pixelv(motion_origin + Vector2i(left_x + x, eye_y + y))
						var right := image.get_pixelv(motion_origin + Vector2i(right_x + (1 - x), eye_y + y))
						if not left.is_equal_approx(right):
							_failures.append("%s %s frame=%d eye mismatch at row=%d col=%d" % [gender_name, pose, frame_x, y, x])
						if left.a < 0.9 or left.v >= 0.28:
							_failures.append("%s %s frame=%d eye is not dark at row=%d col=%d" % [gender_name, pose, frame_x, y, x])
				for eye_x: int in [left_x, right_x]:
					for y: int in range(eye_height, eye_height + 2):
						for x: int in range(2):
							var tail := image.get_pixelv(motion_origin + Vector2i(eye_x + x, eye_y + y))
							if tail.v < 0.28 and tail.a > 0.9:
								_failures.append("%s %s frame=%d retained dark eye tail at x=%d y=%d" % [gender_name, pose, frame_x, eye_x + x, eye_y + y])

func _selection(mounted: bool) -> Dictionary:
	var selection := {
		PaperDollV2Contract.RenderLayer.HAIR: &"pack02_hair_short_braid_01",
		PaperDollV2Contract.RenderLayer.ARMOR: &"pack02_leather_scale_armor_01",
		PaperDollV2Contract.RenderLayer.BOOTS: &"pack02_riding_boots_01",
		PaperDollV2Contract.RenderLayer.HELMET: &"pack02_open_sallet_01",
		PaperDollV2Contract.RenderLayer.CAPE: &"pack02_forest_cape_01",
		PaperDollV2Contract.RenderLayer.WEAPON: &"pack02_short_spear_01",
		PaperDollV2Contract.RenderLayer.SHIELD: &"pack02_round_shield_01",
	}
	if mounted:
		selection[PaperDollV2Contract.RenderLayer.MOUNT_TAIL] = &"pack02_chestnut_horse_tail_01"
		selection[PaperDollV2Contract.RenderLayer.MOUNT_BODY] = &"pack02_chestnut_horse_body_01"
		selection[PaperDollV2Contract.RenderLayer.MOUNT_HEAD] = &"pack02_chestnut_horse_head_01"
		selection[PaperDollV2Contract.RenderLayer.MOUNT_BARDING] = &"pack02_forest_barding_01"
	return selection

func _body_id(gender: int, _mounted: bool) -> StringName:
	var prefix := "body_female_default" if gender == PaperDollV2Contract.Gender.FEMALE else "body_male_default"
	var pose := "mounted" if _mounted else "on_foot"
	return StringName("%s_%s_unisex" % [prefix, pose])

func _layer_for_id(visual_id: StringName) -> int:
	return PaperDollV2Catalog._layer_for_visual_id(visual_id)
