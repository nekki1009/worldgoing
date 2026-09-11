extends SceneTree

const FEMALE_PACK := "res://assets/characters/human/q35/standard_anime_female_character_pack.glb"

func _init() -> void:
	var glb: PackedScene = load(FEMALE_PACK)
	var inst := glb.instantiate()
	root.add_child(inst)
	var anim_player: AnimationPlayer = null
	for child in inst.find_children("*", "AnimationPlayer"):
		anim_player = child
		break
	
	var skel: Skeleton3D = null
	for child in inst.find_children("*", "Skeleton3D"):
		skel = child
		break

	var obj_top: MeshInstance3D = null
	var obj_c: MeshInstance3D = null
	var obj_shield_bk: MeshInstance3D = null
	var obj_cape: MeshInstance3D = null
	for child in inst.find_children("*", "MeshInstance3D"):
		if child.name == "Outfit_Underlayer_01_Top":
			obj_top = child
		elif child.name == "Armor_Iron_01_Cuirass_Front":
			obj_c = child
		elif child.name == "Shield_Heater_01_Holstered_Field":
			obj_shield_bk = child
		elif child.name == "Cape_Travel_01_Main":
			obj_cape = child

	print("Shield bk:", obj_shield_bk != null, "Cape:", obj_cape != null)
	if obj_shield_bk:
		print("Shield parent: ", obj_shield_bk.get_parent().name, " class: ", obj_shield_bk.get_parent().get_class())
		print("Shield skin is null? ", obj_shield_bk.skin == null)
		print("Shield transform: ", obj_shield_bk.transform)
		print("Shield global_transform: ", obj_shield_bk.global_transform)

	var obj_bot: MeshInstance3D = null
	var obj_girdle: MeshInstance3D = null
	var obj_apron: MeshInstance3D = null
	for child in inst.find_children("*", "MeshInstance3D"):
		if child.name == "Outfit_Underlayer_01_UnderwearBottom":
			obj_bot = child
		elif child.name == "Armor_Iron_01_Girdle":
			obj_girdle = child
		elif child.name == "Armor_Iron_01_FrontApron":
			obj_apron = child

	if skel and anim_player:
		var check_anims = ["T-Pose", "idle", "walk", "run"]
		for anim_name in check_anims:
			if not anim_player.has_animation(anim_name):
				continue
			var anim = anim_player.get_animation(anim_name)
			var length = anim.length if anim else 1.0
			var step = length / 4.0 if length > 0 else 0.0
			for f_step in range(5):
				var t = f_step * step
				anim_player.play(anim_name)
				anim_player.seek(t, true)
				anim_player.advance(0.0)

				# Calculate deformed vertices for top and cuirass
				var get_verts = func(mi: MeshInstance3D) -> PackedVector3Array:
					var m = mi.mesh
					var arrays = m.surface_get_arrays(0)
					var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
					var bones = arrays[Mesh.ARRAY_BONES]
					var weights = arrays[Mesh.ARRAY_WEIGHTS]
					var skin = mi.skin
					var res := PackedVector3Array()
					res.resize(verts.size())
					for i in range(verts.size()):
						var v = verts[i]
						var def_v := Vector3.ZERO
						for b_slot in range(4):
							var w = weights[i * 4 + b_slot]
							if w <= 0.001:
								continue
							var b_idx = bones[i * 4 + b_slot]
							var b_name := StringName()
							if skin:
								b_name = skin.get_bind_name(b_idx)
							var skel_b = skel.find_bone(b_name)
							if skel_b < 0:
								continue
							var b_pose = skel.get_bone_global_pose(skel_b)
							var b_inv = skin.get_bind_pose(b_idx) if skin else Transform3D.IDENTITY
							var xf = b_pose * b_inv
							def_v += (xf * v) * w
						res[i] = def_v
					return res

				var v_top = get_verts.call(obj_top)
				var v_c = get_verts.call(obj_c)

				# Find any vertex of v_top that penetrates beyond v_c
				var max_clip := 0.0
				var clip_count := 0
				for vt in v_top:
					# Looking in front (+Z in Godot coordinates):
					# Find closest cuirass vertices within 3cm XY radius
					var max_cz := -999.0
					var found_cz := false
					for vc in v_c:
						var dxy = Vector2(vt.x - vc.x, vt.y - vc.y).length()
						if dxy < 0.025:
							if vc.z > max_cz:
								max_cz = vc.z
								found_cz = true
					if found_cz:
						var diff = vt.z - max_cz
						if diff > 0.0005:
							clip_count += 1
							if diff > max_clip:
								max_clip = diff
				if clip_count > 0:
					print("CLIPPING DETECTED! Anim: %s (t=%.2f) -> %d verts clipping, max depth = %.2f mm" % [anim_name, t, clip_count, max_clip * 1000.0])
					if anim_name == "T-Pose" and f_step == 0:
						for idx in range(v_top.size()):
							var vt = v_top[idx]
							var max_cz := -999.0
							var found_cz := false
							for vc in v_c:
								var dxy = Vector2(vt.x - vc.x, vt.y - vc.y).length()
								if dxy < 0.025:
									if vc.z > max_cz:
										max_cz = vc.z
										found_cz = true
							if found_cz and (vt.z - max_cz) > 0.0005:
								var raw_v = obj_top.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX][idx]
								print("  Clip v[%d]: raw_co=%s, def_co=%s, max_cz=%.4f, diff=%.2f mm" % [idx, str(raw_v), str(vt), max_cz, (vt.z - max_cz) * 1000.0])
				else:
					print("OK: Anim: %s (t=%.2f) -> clean" % [anim_name, t])

				# Check Underwear Bottom vs Girdle / Apron
				if obj_bot and obj_girdle:
					var v_b = get_verts.call(obj_bot)
					var v_g = get_verts.call(obj_girdle)
					var b_clip := 0
					var b_max := 0.0
					for vb in v_b:
						var max_gz := -999.0
						var found_gz := false
						for vg in v_g:
							var dxy = Vector2(vb.x - vg.x, vb.y - vg.y).length()
							if dxy < 0.025:
								if vg.z > max_gz:
									max_gz = vg.z
									found_gz = true
						if found_gz and (vb.z - max_gz) > 0.0005:
							b_clip += 1
							b_max = max(b_max, vb.z - max_gz)
					if b_clip > 0:
						print("  BOTTOM VS GIRDLE CLIPPING! Anim: %s (t=%.2f) -> %d verts, max depth = %.2f mm" % [anim_name, t, b_clip, b_max * 1000.0])
					else:
						print("  BOTTOM VS GIRDLE: OK")
				# Check Shield vs Cape
				if obj_shield_bk and obj_cape:
					var v_s = get_verts.call(obj_shield_bk)
					var v_cape = get_verts.call(obj_cape)
					var min_sz = 999.0; var max_sz = -999.0
					var min_cz = 999.0; var max_cz = -999.0
					for vs in v_s:
						min_sz = min(min_sz, vs.z); max_sz = max(max_sz, vs.z)
					for vc in v_cape:
						min_cz = min(min_cz, vc.z); max_cz = max(max_cz, vc.z)
					print("  [%s t=%.2f] Shield Z: [%.4f, %.4f], Cape Z: [%.4f, %.4f]" % [anim_name, t, min_sz, max_sz, min_cz, max_cz])
	quit()

