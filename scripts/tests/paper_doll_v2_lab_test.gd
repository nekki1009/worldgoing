extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load("res://scenes/ui/PaperDollV2Lab.tscn") as PackedScene
	assert(packed != null, "V2 lab scene did not load")
	var lab := packed.instantiate() as PaperDollV2Lab
	assert(lab != null, "V2 lab root type is wrong")
	get_root().add_child(lab)
	await process_frame
	await process_frame
	assert(lab.catalog != null)
	assert(lab.catalog.last_issues.is_empty(), "V2 lab catalog: %s" % lab.catalog.last_issues)
	assert(lab.composer.render_state == PaperDollV2Contract.RenderState.ON_FOOT)
	assert(lab.composer.frame_size() == Vector2i(64, 64))
	assert(lab.composer.visible)
	assert(lab.composer.visible_sprite_count() == 1, "reference baseline must be one calibrated board")
	assert(lab.status_label.text.find("REFERENCE PASS") >= 0, lab.status_label.text)
	lab._on_mounted_toggled(true)
	await process_frame
	assert(lab.composer.render_state == PaperDollV2Contract.RenderState.MOUNTED)
	assert(lab.composer.frame_size() == Vector2i(64, 96))
	assert(lab.composer.anchor_px() == Vector2i(32, 88))
	assert(lab.composer.visible_sprite_count() == 1)
	assert(lab.status_label.text.find("REFERENCE PASS") >= 0, lab.status_label.text)
	lab._on_gender_selected(PaperDollV2Contract.Gender.FEMALE)
	await process_frame
	assert(lab.gender == PaperDollV2Contract.Gender.FEMALE)
	assert(lab.composer.visible)
	assert(lab.composer.visible_sprite_count() == 1, "female reference baseline must be one calibrated board")
	assert(lab.status_label.text.find("REFERENCE PASS") >= 0, lab.status_label.text)
	lab._on_mounted_toggled(false)
	await process_frame
	assert(lab.composer.render_state == PaperDollV2Contract.RenderState.ON_FOOT)
	assert(lab.composer.visible)
	assert(lab.composer.visible_sprite_count() == 1)
	lab._on_mounted_toggled(true)
	await process_frame
	assert(lab.composer.render_state == PaperDollV2Contract.RenderState.MOUNTED)
	assert(lab.composer.visible)
	assert(lab.composer.visible_sprite_count() == 1)
	lab._on_gender_selected(PaperDollV2Contract.Gender.MALE)
	await process_frame
	await process_frame
	assert(lab.composer.visible)
	assert(lab.composer.visible_sprite_count() == 1)
	lab._set_facing(PaperDollV2Contract.Facing.LEFT)
	lab._on_frame_changed(4.0)
	assert(lab.composer.current_facing == PaperDollV2Contract.Facing.LEFT)
	assert(lab.composer.current_frame_x == 4)
	assert(lab.composer.sprite_for(PaperDollV2Contract.RenderLayer.BODY).flip_h)
	print("PAPER_DOLL_V2_LAB_TEST_PASS state=%d gender=%d frame=%d" % [lab.composer.render_state, lab.gender, lab.frame_x])
	lab.queue_free()
	quit(0)
