extends SceneTree
## Real native ABI + original contact mesh source, equipment holder and formal Lab query.
const Crowd = preload("res://scripts/terrain_lab/crowd_site.gd")
const Owner = preload("res://scripts/terrain_lab/crowd_person_owner.gd")
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Atlas = preload("res://scripts/terrain_lab/terrain_army_equipment_atlas.gd")
var body_index := 0

class ProbeLab extends TerrainLab:
	func _ready() -> void: pass
	func controlled_person_id() -> int: return 103

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	create_timer(120.0).timeout.connect(func() -> void: printerr("NATIVE_SIEGE_BODY_CONTACT deadline"); quit(2))
	var arguments := OS.get_cmdline_user_args()
	var selected := arguments.find("--siege-contact-body")
	if selected >= 0 and selected + 1 < arguments.size():
		assert(arguments[selected + 1] in ["male", "female"])
		body_index = 1 if arguments[selected + 1] == "female" else 0
	assert(ClassDB.class_exists(&"ArmyCrowd"))
	for api: StringName in [&"apply_siege_contact", &"charge_siege_round", &"contact_pose_state", &"set_siege_crew"]:
		assert(ClassDB.class_has_method(&"ArmyCrowd", api), "Paired native build missing " + str(api))
	assert(TerrainArmy.load_combat_bake())
	var lab := ProbeLab.new()
	root.add_child(lab)
	lab.set_process(false)
	lab.terrain = TerrainData.new()
	lab.terrain.allocate(Vector2i(32, 32))
	lab.terrain.flags.fill(TerrainData.Flag.WALKABLE)
	# Original migration requires all item-storage fields to be absent together.
	# The original initializer creates ground_loot and the version atomically.
	lab.terrain.site = {"manual": {"cargo": {}}, "worker": {"cargo": {}}, "inventory": {}, "captivity": {}, "team_supply": {}, "person_supply": {}, "vehicles": {}}
	var storage := Runtime.initialize_item_storage(lab.terrain.site)
	assert(storage.ok, "Original item-storage fixture initialization: " + str(storage))
	var site := Crowd.new()
	site.lab = lab
	root.add_child(site)
	var native: RefCounted = ClassDB.instantiate(&"ArmyCrowd")
	assert(native.setup(1, 71))
	assert(native.set_terrain(32, 32, lab.terrain.height_levels, lab.terrain.flags, lab.terrain.ramp_edges, PackedByteArray(), PackedByteArray()))
	var formation: int = native.add_formation(0, 9.5, 10.5, 0.0, 1, 1.0, 0, 0.0)
	var male: Dictionary = TerrainArmy._combat_bake.manifest.appearance.duplicate(true)
	var female: Dictionary = Atlas.female_appearance()
	var appearance: Dictionary = female if body_index == 1 else male
	assert(TerrainArmy.prepare_contact_source_for(male))
	assert(TerrainArmy.prepare_contact_source_for(appearance))
	var source: RefCounted = TerrainArmy.contact_source_for(appearance)
	assert(source != null and int(source.editor._body_index) == body_index)
	assert(source.skeleton != null and source.skeleton.get_bone_count() > 0)
	assert(source.editor.model_root != null and source.sprite != null)
	assert(is_same(source, TerrainArmy.contact_source_for(appearance)))
	assert(TerrainArmy.prepare_contact_source_for(appearance) and is_same(source, TerrainArmy.contact_source_for(appearance)))
	assert(not TerrainArmy._contact_source.supports_appearance(female), "Male original guard must still reject the female recipe")
	var mounted: Dictionary = appearance.duplicate(true)
	mounted.mounted = true
	# CAV-3: an admitted rider answers with its same-body foot source; without a riding atlas it stays refused.
	if SiteMountedSoldierAtlas.available(mounted):
		assert(TerrainArmy.prepare_contact_source_for(mounted) and is_same(TerrainArmy.contact_source_for(mounted), source))
	else:
		assert(not TerrainArmy.prepare_contact_source_for(mounted) and TerrainArmy.contact_source_for(mounted) == null)
	var row := {"person_id": 103, "hp": 999.0, "ko": 0.0, "captive": false, "cell": [1, 1], "appearance": appearance, "item_state": {}, "cargo": {"bolt": 7}, "loot_settled": false, "site_exited": false, "hit_revision": 0}
	assert(Runtime.seed_person_equipment(lab.terrain, row.item_state, 103, appearance).ok)
	assert(native.add_soldiers(formation, PackedInt64Array([103]), PackedInt32Array([site._packed_equip(appearance)]), PackedByteArray([0]), PackedInt32Array([0])) == 0)
	assert(native.finalize())
	var values: PackedFloat64Array = native.get_soldier_state(0)
	values[14] = 9.875; values[15] = 10.25; values[16] = PI * 0.5
	assert(native.set_soldier_state(0, values, native.soldier_refs(0)))
	site.crowd = native; site.active = true
	site._records[103] = row; site._index_by_id[103] = 0
	var owner := Owner.new()
	owner.setup(site, formation, 7, 0, {0: row})
	site.owners.append(owner); site._owner_by_id[103] = owner
	lab.crowd_site = site
	var person := owner.person(0)
	assert(is_same(person.body, row) and is_same(person.holder, row.item_state) and is_same(person.cargo, row.cargo))
	assert(person.cell == Vector2i(9, 10) and person.position == Vector2(9.875, 10.25) * 64.0)
	assert(owner.equipment_appearance(0) == appearance and float(person.hp) == 100.0)
	var original_items: Dictionary = lab.terrain.site.item_records.duplicate(true)
	var original_definitions: Dictionary = lab.terrain.site.item_definitions.duplicate(true)
	var original_next_item: int = int(lab.terrain.site.next_item)
	var depot_before: Dictionary = lab.terrain.site.depot_items.duplicate(true)
	var inventory_before: Dictionary = lab.terrain.site.inventory.duplicate(true)
	var holder_before: Dictionary = row.item_state.duplicate(true)
	var cargo_before: Dictionary = row.cargo.duplicate(true)
	var revision: int = native.contact_revision(0)

	# Independent raw idle pose at native time zero, translated to current native ground.
	var geometry := owner.incoming_geometry(0)
	assert(geometry.body.size() == 10)
	var clock: Array = TerrainArmy._combat_bake.contact_clocks.combat_idle.down
	var raw: Dictionary = source.sample(clock[0], 0.0, Vector2i.DOWN, Vector2.ZERO, 0.0, appearance, false)
	var origin := Vector2(9.875, 10.25) * 64.0
	for part in range(raw.body.size()):
		assert(raw.body[part].size() == geometry.body[part].size())
		for vertex in range(raw.body[part].size()):
			assert((geometry.body[part][vertex] - raw.body[part][vertex]).distance_to(origin) < 0.001)
	var hit_point := Vector2.ZERO
	for point: Vector2 in geometry.body[0]: hit_point += point
	hit_point /= geometry.body[0].size()
	var profile := SiteCombatRules.siege_hit_profile("counterweight_trebuchet")
	var actual := owner.contact_protection(0, {"point": hit_point, "body": 0, "shield": false}, profile)
	var expected: Vector2 = source.armor_at(clock[0], 0.0, Vector2i.DOWN, hit_point - origin, str(profile.kind), Vector2.ZERO, 0.0, appearance)
	assert(actual.distance_to(expected) < 0.00001)
	var mesh_material: Vector2 = source.geometry.armor_at({"editor": source.editor, "player_sprite": source.sprite}, hit_point - origin, str(profile.kind))
	assert(actual.distance_to(mesh_material) < 0.00001 and actual.x > 0.0, "Actual same-body armor triangles/material must cover the torso contact")
	var queried := lab._combat_target(103, true)
	assert(queried.cell == Vector2i(9, 10) and queried.bodies == geometry.body)
	var people := lab._siege_people()
	assert(people.size() == 1 and people[0].id == 103 and people[0].owner == owner and people[0].ground == origin)
	var separate_actor := TerrainTestCharacter.new()
	separate_actor.person_id = 204; separate_actor.hp = 87.0
	separate_actor.position = Vector2(15.5, 16.5) * 64.0
	lab.combat_actors.append(separate_actor)
	people = lab._siege_people()
	assert(people.size() == 2 and people[1].owner == separate_actor and people[1].unit == -1 and people[1].id == 204)
	lab.combat_actors.clear(); separate_actor.free()

	# A hot native position change immediately moves contact geometry; original cold row stays intact.
	values = native.get_soldier_state(0); values[14] += 1.0
	assert(native.set_soldier_state(0, values, native.soldier_refs(0)))
	var moved := owner.incoming_geometry(0)
	for part in range(geometry.body.size()):
		for vertex in range(geometry.body[part].size()):
			assert((moved.body[part][vertex] - geometry.body[part][vertex]).distance_to(Vector2(64.0, 0.0)) < 0.001)
	assert(row.cell == [1, 1] and row.hp == 999.0)
	# Original TerrainData surface projection, with no extra person height owner.
	lab.terrain.walk_height_levels = lab.terrain.height_levels.duplicate()
	lab.terrain.walk_height_levels.fill(2)
	lab.terrain.has_raised_surfaces = true
	var raised := owner.incoming_geometry(0)
	for part in range(moved.body.size()):
		for vertex in range(moved.body[part].size()):
			assert((raised.body[part][vertex] - moved.body[part][vertex]).distance_to(Vector2(0.0, -96.0)) < 0.001)
	lab.terrain.has_raised_surfaces = false
	# The original resource's actual skinned vertices and projection back each
	# body. Native and fallback skinning must agree on every visible real mesh.
	var vertex_count := 0
	for node: Node in source.editor.model_root.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if not mesh.is_visible_in_tree() or mesh.mesh == null: continue
		var original: PackedVector3Array = source.geometry.posed_vertices(mesh, source.skeleton, false)
		var skinned: PackedVector3Array = source.geometry.posed_vertices(mesh, source.skeleton)
		assert(original.size() == skinned.size())
		for vertex in range(original.size()): assert(original[vertex].distance_to(skinned[vertex]) < 0.00001)
		vertex_count += original.size()
	assert(vertex_count > 0, "Actual body meshes must supply their original vertices")
	var generation := int(source.pose_cache_generation)
	TerrainArmy.begin_contact_step()
	assert(int(source.pose_cache_generation) > generation and is_same(source, TerrainArmy.contact_source_for(appearance)))
	assert(owner.incoming_geometry(0).body == moved.body)
	generation = int(source.pose_cache_generation)
	TerrainArmy.clear_contact_samples()
	assert(int(source.pose_cache_generation) > generation and is_same(source, TerrainArmy.contact_source_for(appearance)))
	assert(owner.incoming_geometry(0).body == moved.body)

	# Original material projection changes solely from actual equipped item IDs.
	var old_weapon: String = str(row.item_state.equipped.weapon)
	var old_armor: String = str(row.item_state.equipped.armor)
	var transferred := Runtime.transfer_items(lab.terrain, row.item_state, row.cargo,
		lab.terrain.site.depot_items, lab.terrain.site.inventory, {}, [old_weapon, old_armor],
		int(row.item_state.version), int(lab.terrain.site.depot_items.version), 100000)
	assert(transferred.ok, "Original weapon transfer to original depot: " + str(transferred))
	assert(not row.item_state.equipped.has("weapon") and lab.terrain.site.depot_items.item_ids.has(old_weapon))
	var equipment := Runtime.create_equipment(lab.terrain, row.item_state, "native_siege_test:axe", {"slot": "weapon", "asset": "axe_01", "tint": [1.0, 1.0, 1.0, 1.0]}, 103, "weapon")
	assert(equipment.ok, "Original real axe creation/equipment: " + str(equipment))
	assert(str(owner.equipment_appearance(0).parts.weapon) == "axe_01")
	var armor := Runtime.create_equipment(lab.terrain, row.item_state, "native_siege_test:steel", {"slot": "armor", "asset": "armor_western_steel_01", "tint": [1.0, 1.0, 1.0, 1.0]}, 103, "armor")
	assert(armor.ok, "Original real steel armor creation/equipment: " + str(armor))
	assert(str(owner.equipment_appearance(0).parts.armor) == "armor_western_steel_01")
	assert(is_same(source, TerrainArmy.contact_source_for(owner.equipment_appearance(0))))
	var equipped_geometry := owner.incoming_geometry(0)
	var armor_point := Vector2.ZERO
	for point: Vector2 in equipped_geometry.body[0]: armor_point += point
	armor_point /= equipped_geometry.body[0].size()
	var steel_actual := owner.contact_protection(0, {"point": armor_point, "body": 0, "shield": false}, profile)
	var steel_mesh: Vector2 = source.geometry.armor_at({"editor": source.editor, "player_sprite": source.sprite}, armor_point - origin - Vector2(64.0, 0.0), str(profile.kind))
	assert(source.editor.capture_appearance().parts.armor == "armor_western_steel_01")
	assert(steel_actual.distance_to(steel_mesh) < 0.00001 and steel_actual.x > actual.x, "Native armor protection must change with the actual original equipped steel mesh/material")
	assert(is_same(owner.person(0).holder, row.item_state))
	row.item_state.clear(); row.item_state.merge(holder_before, true)
	lab.terrain.site.item_records.clear(); lab.terrain.site.item_records.merge(original_items, true)
	lab.terrain.site.item_definitions.clear(); lab.terrain.site.item_definitions.merge(original_definitions, true)
	lab.terrain.site.depot_items.clear(); lab.terrain.site.depot_items.merge(depot_before, true)
	lab.terrain.site.next_item = original_next_item
	assert(lab.terrain.site.inventory == inventory_before and row.cargo == cargo_before)
	assert(owner.equipment_appearance(0) == appearance)

	owner.ranged_apply_hit(0, Vector2i(3, 10), {"siege": true, "result": {"hp": 10.0, "stun": 5.0, "stagger": 0.35}})
	values = native.get_soldier_state(0)
	assert(values[0] == 90.0 and values[1] == 5.0 and absf(values[5] - 0.35) < 0.000001)
	assert(native.contact_revision(0) == revision + 1 and row.hp == 999.0 and row.hit_revision == 0)
	assert(row.item_state == holder_before and row.cargo == cargo_before and lab.terrain.site.item_records == original_items)
	assert(native.contact_pose_state(0)[0] == 6.0)
	assert(native.set_siege_crew(0, true))
	assert(native.charge_siege_round(PackedInt32Array([0]), SiteCombatRules.EXCHANGE_FATIGUE))
	assert(native.get_formation_state(formation)[2] == SiteCombatRules.EXCHANGE_FATIGUE)
	assert(row.get("fatigue", 0.0) == 0.0)

	owner.crowd_site = null; owner.combat_units.clear(); owner.records.clear()
	site.active = false; site.crowd = null; site.lab = null; site.owners.clear(); site._owner_by_id.clear()
	lab.crowd_site = null
	site.free(); lab.free()
	TerrainArmy.release_contact_source()
	assert(TerrainArmy.contact_source_for(appearance) == null and source.editor == null and TerrainArmy._body_contact_sources.is_empty())
	print("NATIVE_SIEGE_BODY_CONTACT_ADAPTER_PASS body=", body_index, " vertices=", vertex_count, " real ABI, native position/pose/revision/fatigue, same-body original mesh/Skeleton/armor/material/item holders and lifecycle; excludes complete native siege workflow and GPU presentation")
	quit(0)
