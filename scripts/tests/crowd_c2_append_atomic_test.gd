extends SceneTree
## L1: real native append rejection restores hot state, owners and existing renderer kits.
const CrowdSite = preload("res://scripts/terrain_lab/crowd_site.gd")
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")

class LabFixture extends Node2D:
	var terrain := TerrainData.new()
	var character := TerrainTestCharacter.new()
	var npc: TerrainTestCharacter
	var combat_actors: Array[TerrainTestCharacter] = []
	var combat_profile_enabled := false # CrowdSite reads the Lab's optional profiling switch.
	func controlled_person_id() -> int:
		return 10
	func _next_army_identity() -> int:
		return 2

func _initialize() -> void:
	# The root joins the tree only after _initialize returns; contact preparation needs a live tree.
	create_timer(120.0).timeout.connect(func() -> void: printerr("CROWD_C2_APPEND_ATOMIC deadline"); quit(1))
	_run.call_deferred()

func _run() -> void:
	assert(ClassDB.class_exists("ArmyCrowd"))
	var lab := LabFixture.new()
	root.add_child(lab) # Contact appearance preparation parks its resource Actor under the Lab's tree.
	lab.terrain.allocate(Vector2i(16, 16))
	lab.terrain.flags.fill(TerrainData.Flag.WALKABLE)
	lab.terrain.site = {"manual": {"cargo": {}}, "worker": {"cargo": {}}, "captivity": {}}
	assert(Runtime.initialize_item_storage(lab.terrain.site).ok)
	var actor := lab.character
	actor.person_id = 20
	actor.faction_id = 0
	actor.position = Vector2(7.5, 8.5) * 64.0
	actor._saved_appearance = HumanCharacter3DEditor.default_appearance()
	actor.item_state = Runtime.new_item_state("person:20")
	actor.hp = 37.0
	actor.stun = 21.0
	actor.exchange_cooldown = -1.0 # Native import rejects after formation/person append.
	lab.combat_actors.append(actor)
	var site := CrowdSite.new()
	site.lab = lab
	site.crowd = ClassDB.instantiate("ArmyCrowd")
	site.crowd.setup(1, 71)
	assert(site.crowd.set_terrain(16, 16, lab.terrain.height_levels, lab.terrain.flags, lab.terrain.ramp_edges, lab.terrain.static_blocked, PackedByteArray()))
	var formation: int = site.crowd.add_formation(0, 4.5, 4.5, 0.0, 1, 1.0, 0, 0.0)
	assert(site.crowd.add_soldiers(formation, PackedInt64Array([10]), PackedInt32Array([0]), PackedByteArray([1]), PackedInt32Array([0])) == 0)
	site.crowd.finalize()
	site.crowd.set_host_control(0, true)
	var appearance := HumanCharacter3DEditor.default_appearance()
	site._records[10] = {"person_id": 10, "appearance": appearance, "item_state": Runtime.new_item_state("person:10"), "cargo": {}}
	site.teams.append({"slot": 0, "team_id": 1, "formation": formation, "faction": 0, "troop": 0, "person_ids": [10], "solo": false})
	site._bind_people()
	var tracks := PackedInt32Array()
	tracks.resize(site.SLOTS.size() * 4)
	tracks.fill(-1)
	assert(site.crowd.render_add_kit(0, 0, 1.0, tracks) == 0)
	site._kit_ids = PackedInt32Array([0])
	site._kit_appearances = [appearance]
	site._kit_cache = {"retained": 0}
	assert(site.crowd.render_set_kits(site._kit_ids))
	site.player_index = 0
	site.active = true
	var owner: Variant = site.person_owner(10)
	var before: PackedByteArray = site.crowd.save_state()
	var native_hash: int = site.crowd.state_hash()
	var original_site := lab.terrain.site.duplicate(true)
	var rejected: Dictionary = site.on_control_changed(10, 20)
	assert(not rejected.ok and rejected.code == "INVALID")
	assert(site.crowd.save_state() == before and site.crowd.state_hash() == native_hash and site.crowd.validate())
	assert(site.crowd.soldier_count() == 1 and site.crowd.formation_count() == 1)
	assert(site.player_index == 0 and site.teams.size() == 1 and site._actors.is_empty() and not site.contains_person(20))
	assert(is_same(site.person_owner(10), owner) and site.owners.size() == 1)
	assert(site._kit_ids == PackedInt32Array([0]) and site._kit_appearances.size() == 1 and site._kit_cache == {"retained": 0})
	assert(lab.terrain.site == original_site and actor.hp == 37.0 and actor.stun == 21.0)
	# Native load keeps the atlas kit table; only per-person indices need restoration.
	assert(site.crowd.render_add_kit(0, 0, 1.0, tracks) == 1)
	actor.exchange_cooldown = 0.75
	actor.fatigue = -1.0 # Soldier import succeeds, then formation import rejects.
	rejected = site.on_control_changed(10, 20)
	assert(not rejected.ok and site.crowd.save_state() == before and site.crowd.state_hash() == native_hash)
	assert(site.player_index == 0 and site.teams.size() == 1 and site._actors.is_empty() and is_same(site.person_owner(10), owner))
	assert(site._kit_ids == PackedInt32Array([0]) and lab.terrain.site == original_site)
	actor.fatigue = 14.0
	var accepted: Dictionary = site.on_control_changed(10, 20)
	assert(accepted.ok and site.player_index == 1 and site.crowd.soldier_count() == 2 and site.crowd.formation_count() == 2)
	assert(site.contains_person(20) and site.teams.size() == 2 and site._actors.size() == 1 and is_same(site.person_owner(10), owner))
	assert(site._kit_ids == PackedInt32Array([0, -1]) and site._kit_appearances.size() == 2 and site._kit_cache == {"retained": 0})
	var hot: Dictionary = site.soldier_state(1)
	assert(hot.hp == 37.0 and hot.stun == 21.0 and hot.exch_cd == 0.75)
	assert(site.formation_state(1).no_orders and site.formation_state(1).host_center and site.formation_state(1).fatigue == 14.0 and site.crowd.validate())
	assert(lab.terrain.site == original_site)
	site.free()
	actor.free()
	lab.free()
	TerrainArmy.release_contact_source() # The append prepared a contact source; release it before exit like other crowd tests.
	await process_frame
	print("CROWD_C2_APPEND_ATOMIC_PASS")
	quit(0)
