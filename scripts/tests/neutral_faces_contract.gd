extends SceneTree

const Store = preload("res://scripts/terrain_lab/site_store.gd")
const OUT := "res://output/neutral_faces_20260918/"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var face_options: Array = HumanCharacter3DEditor.PART_SLOTS[0].options
	assert(face_options.size() == 9) # Eight faces plus the original None option.
	var ids := {}
	for option: Dictionary in face_options:
		assert(not ids.has(option.id))
		ids[option.id] = true
	for model_path in [HumanCharacter3DEditor.MALE_MODEL_PATH,HumanCharacter3DEditor.FEMALE_MODEL_PATH]:
		var packed := load(model_path) as PackedScene
		assert(packed != null)
		var model := packed.instantiate()
		var skeletons := model.find_children("*","Skeleton3D",true,false)
		assert(skeletons.size() == 1)
		var faces := model.find_children("Face_Standard_*","MeshInstance3D",true,false)
		assert(faces.size() == 8)
		for number in range(5,9):
			var face := model.find_child("Face_Standard_%02d" % number,true,false) as MeshInstance3D
			assert(face != null and face.skin != null and face.mesh != null)
			assert(face.mesh.get_blend_shape_count() == 0)
			assert(face.get_node(face.skeleton) == skeletons[0])
		model.free()
	var lab := TerrainLab.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	current_scene = lab
	lab.set_process(false)
	lab.character.set_process(false)
	lab.npc.set_process(false)
	assert(lab.character.editor == null and lab.npc.editor == null,"Run this state test headless")
	for number in range(5,9):
		var face_id := "face_standard_%02d" % number
		for actor: TerrainTestCharacter in [lab.character,lab.npc]:
			var state := actor.capture_state()
			state.appearance.parts.face = face_id
			assert(TerrainTestCharacter.valid_state(state,lab.terrain))
			actor.restore_state(state)
		lab.site_controller._capture_positions()
		var save_path := OUT+"save_face_%02d.json" % number
		var saved := Store.save(lab.terrain,save_path)
		assert(saved.ok,str(saved))
		var loaded := Store.load_site(save_path)
		assert(loaded.ok,str(loaded))
		lab.bind_terrain(loaded.data)
		assert(lab.character.capture_state().appearance.parts.face == face_id)
		assert(lab.npc.capture_state().appearance.parts.face == face_id)
		assert(lab.character.capture_state().appearance.body == 0)
		assert(lab.npc.capture_state().appearance.body == 1)
		var invalid := lab.character.capture_state()
		invalid.appearance.parts.face = "face_standard_99"
		assert(not TerrainTestCharacter.valid_state(invalid,lab.terrain))
	var report := FileAccess.open(OUT+"runtime_contract.json",FileAccess.WRITE)
	report.store_string(JSON.stringify({"faces_per_sex":8,"new_faces_per_sex":4,"save_load_cases":8,"native_skeleton":true,"expression":"neutral","ordinary_npc_bake":false},"  "))
	report.close()
	lab.queue_free()
	await process_frame
	print("NEUTRAL_FACES_CONTRACT_PASS imported native skeletons, eight faces each, eight male/female SiteStore round trips, invalid ID rejected")
	quit(0)
