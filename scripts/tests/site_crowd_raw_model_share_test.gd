extends SceneTree

const SharedSource = preload("res://scripts/terrain_lab/terrain_army_shared_visual_source.gd")
const Plan = preload("res://scripts/tools/terrain_army_recipe_bake_plan.gd")
const BASE_MANIFEST := "res://assets/characters/terrain_lab_army/standard_soldier/standard_soldier_atlas.json"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var baseline: Variant = JSON.parse_string(FileAccess.get_file_as_string(BASE_MANIFEST))
	assert(baseline is Dictionary and baseline.source_fingerprints == Plan.fingerprints(), "Crowd cache must not invalidate published atlas sources")
	var host := Node2D.new()
	root.add_child(host)
	for body_index: int in [0, 1]:
		var first := _open_source(host, body_index)
		var second := _open_source(host, body_index)
		assert(first.preview_viewport.size == CharacterRenderContract.MAP_VIEWPORT_SIZE)
		assert(second.preview_viewport.size == CharacterRenderContract.MAP_VIEWPORT_SIZE)
		assert(first.model_root != second.model_root)
		assert(first.model_root.find_children("*", "", true, false).size() == second.model_root.find_children("*", "", true, false).size())
		assert(first.animation_player != null and second.animation_player != null)
		for library_name: StringName in first.animation_player.get_animation_library_list():
			assert(first.animation_player.get_animation_library(library_name) != second.animation_player.get_animation_library(library_name), "Animations must stay private to each presenter")
		assert(_shared_mesh_count(first.model_root, second.model_root) > 0, "Repeated crowd models must share immutable mesh resources")
		first.close()
		second.close()
	host.queue_free()
	await process_frame
	print("site_crowd_raw_model_share_test PASS")
	quit(0)

func _open_source(host: Node2D, body_index: int) -> HumanCharacter3DEditor:
	var source := SharedSource.new()
	source.preview_host = host
	source.visual_state.body_index = body_index
	host.add_child(source)
	source.open()
	assert(source.model_root != null)
	return source

func _shared_mesh_count(first: Node3D, second: Node3D) -> int:
	var meshes := {}
	for child: Node in first.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		meshes[str(first.get_path_to(mesh))] = mesh.mesh
	var count := 0
	for child: Node in second.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		if mesh.mesh != null and mesh.mesh == meshes.get(str(second.get_path_to(mesh))):
			count += 1
	return count
