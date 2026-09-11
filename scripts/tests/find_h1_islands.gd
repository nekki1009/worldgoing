extends SceneTree

const FEMALE_MODEL_PATH: String = "res://assets/characters/human/q35/standard_anime_female_character_pack.glb"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene := load(FEMALE_MODEL_PATH) as PackedScene
	var inst := scene.instantiate() as Node3D
	root.add_child(inst)
	var skeleton := inst.find_child("Skeleton3D", true, false) as Skeleton3D
	var head_bone_idx := skeleton.find_bone("J_Bip_C_Head")
	var head_world: Transform3D = skeleton.global_transform * skeleton.get_bone_global_pose(head_bone_idx)
	var inv_head := head_world.affine_inverse()
	
	var node := inst.find_child("Hair_Long_01", true, false) as MeshInstance3D
	var m := node.mesh
	var arrays := m.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	
	# Find connected components (mesh islands)
	var adj := {}
	for i in range(verts.size()):
		adj[i] = []
	for tri in range(0, indices.size(), 3):
		var i0 := indices[tri]
		var i1 := indices[tri + 1]
		var i2 := indices[tri + 2]
		adj[i0].append(i1)
		adj[i1].append(i0)
		adj[i1].append(i2)
		adj[i2].append(i1)
		adj[i2].append(i0)
		adj[i0].append(i2)
	
	var visited := {}
	var island_id := 0
	for i in range(verts.size()):
		if visited.has(i):
			continue
		var island := []
		var stack := [i]
		visited[i] = true
		while not stack.is_empty():
			var cur: int = stack.pop_back()
			island.append(cur)
			for nxt: int in adj[cur]:
				if not visited.has(nxt):
					visited[nxt] = true
					stack.append(nxt)
		# Compute bounds for island
		var min_p := Vector3(INF, INF, INF)
		var max_p := Vector3(-INF, -INF, -INF)
		var sum_p := Vector3.ZERO
		for vi: int in island:
			var hp := inv_head * (node.global_transform * verts[vi])
			min_p.x = minf(min_p.x, hp.x)
			min_p.y = minf(min_p.y, hp.y)
			min_p.z = minf(min_p.z, hp.z)
			max_p.x = maxf(max_p.x, hp.x)
			max_p.y = maxf(max_p.y, hp.y)
			max_p.z = maxf(max_p.z, hp.z)
			sum_p += hp
		var avg_p := sum_p / float(island.size())
		print("Island ", island_id, " (", island.size(), " verts): avg=", avg_p, " min=", min_p, " max=", max_p)
		island_id += 1
	quit(0)
