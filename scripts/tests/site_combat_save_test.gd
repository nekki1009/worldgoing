extends SceneTree

const Store = preload("res://scripts/terrain_lab/site_store.gd")
const SAVE := "res://.godot-temp/site_combat/snapshot.json"

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	create_timer(12.0).timeout.connect(func() -> void: quit(1))
	var lab := TerrainLab.new()
	lab.npc = TerrainTestNPC.new() # Explicit legacy command-test fixture; formal TerrainLab remains player-only.
	lab.pause_when_unfocused = false
	root.add_child(lab)
	current_scene = lab
	lab.set_process(false)
	lab.character.set_process(false)
	lab.npc.set_process(false)
	lab.site_controller.save_path = SAVE
	var data := TerrainGenerator.generate(0, 581)
	SiteEnvironment.initialize(data, "combat-save-fixture")
	lab.bind_terrain(data)
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
	a.exchange_enabled = false
	b.exchange_enabled = false
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
	var old_ko_payload: Dictionary = original.payload.duplicate(true)
	old_ko_payload.state.actors.player.schema = 1
	old_ko_payload.state.actors.player.knockout_left = 17.0
	var old_ko_body := JSON.stringify(old_ko_payload, "", true, true)
	var old_ko_file := FileAccess.open(SAVE + ".old_ko", FileAccess.WRITE)
	old_ko_file.store_string(JSON.stringify({"checksum": old_ko_body.sha256_text(), "payload": old_ko_body}))
	old_ko_file.close()
	var old_ko_loaded := Store.load_site(SAVE + ".old_ko")
	assert(old_ko_loaded.ok and old_ko_loaded.data.site.actors.player.schema == 2 and old_ko_loaded.data.site.actors.player.knockout_left == 8160.0, str(old_ko_loaded))
	assert("舊版昏迷" in str(old_ko_loaded.message))
	assert(Store.save(old_ko_loaded.data, SAVE + ".new_ko").ok)
	var new_ko_loaded := Store.load_site(SAVE + ".new_ko")
	assert(new_ko_loaded.ok and new_ko_loaded.data.site.actors.player.knockout_left == 8160.0, "KO migration repeated on second load")
	old_ko_payload.state.actors.player.schema = 3
	old_ko_body = JSON.stringify(old_ko_payload, "", true, true)
	old_ko_file = FileAccess.open(SAVE + ".invalid_ko", FileAccess.WRITE)
	old_ko_file.store_string(JSON.stringify({"checksum": old_ko_body.sha256_text(), "payload": old_ko_body}))
	old_ko_file.close()
	assert(not Store.load_site(SAVE + ".invalid_ko").ok and FileAccess.get_sha256(SAVE) == checksum, "Invalid KO schema changed the valid save")
	var old_payload: Dictionary = original.payload.duplicate(true)
	old_payload.format = 1
	old_payload.state.erase("actors")
	# The old map-only format has no person holders for this fixture's seeded gear.
	old_payload.state.item_records.clear()
	# Nor does it have Fire transport: every current save writes one Fire order per actor/Army owner
	# (_capture_fire_transport_payload), and those owners are exactly the actors erased above.
	assert(original.payload.state.has("fire_transport"), "Current save carries the per-owner Fire transport this fixture removes")
	old_payload.state.erase("fire_transport")
	var body := JSON.stringify(old_payload, "", true, true)
	var old_file := FileAccess.open(SAVE + ".legacy", FileAccess.WRITE)
	old_file.store_string(JSON.stringify({"checksum": body.sha256_text(), "payload": body}))
	old_file.close()
	# Site save format 5 (neutral part 2): older formats are refused outright, never migrated.
	var migrated := Store.load_site(SAVE + ".legacy")
	assert(not migrated.ok and str(migrated.get("code", "")) == "OLD_SAVE_UNSUPPORTED", str(migrated))
	assert(FileAccess.get_sha256(SAVE) == checksum, "Refused old save left the valid save unchanged")
	lab.queue_free()
	await process_frame
	print("SITE COMBAT SAVE PASS: HP/stun/KO/appearance, existing save guard, attack dedup, projectile/ammo, corrupt snapshots, old format refused")
	quit(0)
