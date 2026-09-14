extends SceneTree

const Store = preload("res://scripts/terrain_lab/site_store.gd")
const SAVE := "res://.godot-temp/site_combat/snapshot.json"

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	create_timer(12.0).timeout.connect(func() -> void: quit(1))
	var lab := TerrainLab.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	current_scene = lab
	lab.set_process(false)
	lab.character.set_process(false)
	lab.npc.set_process(false)
	lab.site_controller.save_path = SAVE
	var a := lab.character
	var b := lab.npc
	a.hp = 37.25
	a.stun = 112.5
	a.stun_grace = 2.5
	a.knockout_left = 17.0
	a._stop_fighting("Unconscious")
	b.hp = 63.5
	lab.terrain.site.manual.cargo["arrow"] = 2
	lab.site_controller._capture_positions()
	assert(Store.save(lab.terrain, SAVE).ok, "Valid person snapshot must save")
	var checksum := FileAccess.get_sha256(SAVE)
	var loaded := Store.load_site(SAVE)
	assert(loaded.ok, str(loaded))
	lab.bind_terrain(loaded.data)
	assert(a.hp == 37.25 and a.stun == 112.5 and a.knockout_left == 17.0)
	assert(b.hp == 63.5 and a.stun_grace == 2.5, "Load must not heal either actor")
	assert(a.visual_state.animation_id == &"down")
	assert(int(a.ammo_inventory.arrow) == 2 and b.visual_state.body_index == 1)
	a.advance_combat(5.0)
	assert(a.knockout_left == 12.0 and a.hp == 37.25)
	lab.terrain.site.combat_left = 5.0
	lab.site_controller._capture_positions()
	assert(not Store.save(lab.terrain, SAVE).ok)
	assert(FileAccess.get_sha256(SAVE) == checksum, "Busy save changed the existing file")
	lab.terrain.site.combat_left = 0.0
	a.reset_combat()
	b.reset_combat()
	assert(a.start_attack(b))
	a._attack_elapsed = 0.31
	a.action_time = a._attack_duration - 0.31
	a._attack_hits[b.person_id] = true
	a._did_hit = true
	a.projectiles.append({"position": a.position + Vector2(0, -25), "velocity": Vector2.RIGHT * 420.0,
		"ground": a.position, "ground_velocity": Vector2.RIGHT * 420.0, "source_cell": a.terrain_cell,
		"remaining": 128.0, "faction": a.faction_id, "profile": SiteCombatRules.attack_profile(&"attack_bow")})
	# Exercise the serializer directly without relaxing the live save-time policy.
	var encoded := JSON.stringify(a.capture_state())
	var snapshot: Dictionary = JSON.parse_string(encoded)
	assert(TerrainTestCharacter.valid_state(snapshot, lab.terrain), "Serialized active state invalid")
	a.reset_combat()
	a.restore_state(snapshot)
	assert(a._attack_elapsed == 0.31 and a._did_hit and a._attack_hits.has(b.person_id))
	assert(a.projectiles.size() == 1 and float(a.projectiles[0].remaining) == 128.0)
	a.restore_state(snapshot)
	assert(a.projectiles.size() == 1 and int(a.ammo_inventory.arrow) == 2, "Restore duplicated projectile or consumed ammo twice")
	var broken: Dictionary = snapshot.duplicate(true)
	broken.hp = -1
	assert(not TerrainTestCharacter.valid_state(broken, lab.terrain))
	broken = snapshot.duplicate(true)
	broken.appearance.parts.weapon = "invented_weapon"
	assert(not TerrainTestCharacter.valid_state(broken, lab.terrain))
	broken = snapshot.duplicate(true)
	broken.position = [65535, 65535]
	assert(not TerrainTestCharacter.valid_state(broken, lab.terrain), "Cell/physical-position mismatch accepted")
	a.reset_combat()
	b.reset_combat()
	lab.terrain.site.combat_left = 0.0
	lab.site_controller._capture_positions()
	var bad_state: Dictionary = lab.terrain.site.duplicate(true)
	bad_state.actors.npc.person_id = bad_state.actors.player.person_id
	assert(not Store._validate_actors(lab.terrain, bad_state).ok)
	bad_state = lab.terrain.site.duplicate(true)
	bad_state.worker = 4
	assert(not Store._validate_actors(lab.terrain, bad_state).ok, "Malformed parent state must fail cleanly")
	var original := Store._read(SAVE)
	assert(original.ok)
	var old_payload: Dictionary = original.payload.duplicate(true)
	old_payload.format = 1
	old_payload.state.erase("actors")
	var body := JSON.stringify(old_payload, "", true, true)
	var old_file := FileAccess.open(SAVE + ".legacy", FileAccess.WRITE)
	old_file.store_string(JSON.stringify({"checksum": body.sha256_text(), "payload": body}))
	old_file.close()
	var migrated := Store.load_site(SAVE + ".legacy")
	assert(migrated.ok and migrated.data.site.actors.is_empty())
	assert("舊地圖" in str(migrated.message), "Legacy actor defaults must be explicit")
	a.fatigue = 90
	b.fatigue = 75
	lab.bind_terrain(migrated.data)
	assert(a.fatigue == 0 and b.fatigue == 0 and a.fatigue_rest == 0, "Explicit no-person legacy migration cannot inherit another map's fatigue")
	lab.queue_free()
	await process_frame
	print("SITE COMBAT SAVE PASS: HP/stun/KO/appearance, existing save guard, attack dedup, projectile/ammo, corrupt snapshots, explicit legacy migration")
	quit(0)
