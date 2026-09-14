extends SceneTree
## Execute the captured pre-change owners and current owners against identical
## commands and 30 Hz steps. Visual clocks are explicitly excluded, not HP/movement.
const BEFORE := "res://output/site_exchange_animation_20260914/before_source/"
var checks := 0
var retained_scripts: Array[GDScript] = []

func _initialize() -> void:
	_run.call_deferred()

func _before(filename: String, class_line: String) -> GDScript:
	var script := GDScript.new()
	# The current declarations are unchanged (only a new presentation preload).
	# Inherit those declarations so self still satisfies the original typed rescue
	# links; override every original method with its verbatim captured body.
	var source := FileAccess.get_file_as_string(BEFORE + filename + ".txt")
	assert(source.begins_with(class_line))
	# This private presentation helper changed signature, so keep the old
	# name/call pair together instead of overriding the new typed signature.
	source = source.replace("_exchange_animation_time(", "_before_exchange_animation_time(")
	source = source.replace("_combat_clip(", "_before_combat_clip(")
	var methods := RegEx.new()
	assert(methods.compile("(?m)^(?:static )?func [^\\n]*\\n(?:^[\\t ][^\\n]*(?:\\n|$)|^\\r?\\n)*") == OK)
	var declarations := RegEx.new()
	assert(declarations.compile("(?m)^(?:static )?func ") == OK)
	assert(methods.search_all(source).size() == declarations.search_all(source).size(), "Every original method must participate in the baseline")
	script.source_code = "extends \"res://scripts/terrain_lab/" + filename + "\"\n\n"
	for method: RegExMatch in methods.search_all(source):
		script.source_code += method.get_string() + "\n"
	var error := script.reload()
	if error != OK:
		quit(1)
		return null
	retained_scripts.append(script)
	return script

func _map() -> TerrainData:
	var data := TerrainData.new()
	data.allocate(Vector2i(40, 40))
	data.seed_value = 581
	data.flags.fill(TerrainData.Flag.WALKABLE)
	SiteEnvironment.initialize(data, "short-animation-parity")
	data.static_blocked.fill(0)
	return data

func _result(role: String, big: bool = false) -> Dictionary:
	return {"role": role, "kind": "big" if big else ("draw" if role == "draw" else "small"),
		"hp": (2.0 if big else 1.0) if role == "loser" else 0.0,
		"stun": (18.0 if big else 8.0) if role == "loser" else 0.0,
		"stagger": (0.65 if big else 0.35) if role == "loser" else (0.3 if role == "draw" else 0.0),
		"fatigue": 0.5, "knockback": big and role == "loser", "other_identity": 9999}

func _same(a: Variant, b: Variant, context: String) -> bool:
	if a != b:
		push_error(context + "\nBEFORE " + str(a) + "\nAFTER " + str(b))
		quit(1)
		return false
	checks += 1
	return true

func _actor_state(actor: Variant) -> Dictionary:
	var result := {}
	for field: String in ["hp", "stun", "stun_grace", "fatigue", "fatigue_rest", "knockout_left", "exchange_cooldown", "exchange_stagger", "ranged_cooldown", "exchange_skill_cooldown", "action_time", "guarding", "guard_transition_left", "guard_break_left", "captive", "_getting_up", "_ranged_hold_left", "terrain_cell", "movement_from_cell", "_movement_duration", "_movement_elapsed", "position", "facing", "ammo_inventory"]:
		result[field] = actor.get(field)
	result["can_act"] = actor.can_act()
	result["ready"] = actor.exchange_ready()
	result["receive"] = actor.exchange_can_receive()
	result["shots"] = actor.projectiles.duplicate(true)
	return result

func _run() -> void:
	create_timer(20.0).timeout.connect(func() -> void: quit(1))
	var old_actor := _before("terrain_test_character.gd", "class_name TerrainTestCharacter")
	if old_actor == null:
		return
	for weapon: String in ["longsword_01", "axe_01", "hammer_01", "bow_01", "crossbow_01"]:
		var people: Array = [old_actor.new(), TerrainTestCharacter.new()]
		for actor: Variant in people:
			root.add_child(actor)
			actor.set_process(false)
			actor.data = _map()
			actor.person_id = 1 # Same original identity; never compare unrelated engine instance IDs.
			actor.exchange_enabled = true
			actor.combat_mode_query = func() -> bool: return true
			actor.place(Vector2i(10, 10), true)
			actor._saved_appearance = HumanCharacter3DEditor.default_appearance()
			actor._saved_appearance.parts.weapon = weapon
			actor.ammo_inventory = {"arrow": 8, "bolt": 8}
		for tick: int in 360:
			for actor: Variant in people:
				if tick % 60 == 0:
					actor.ranged_fire(actor.terrain_cell + Vector2i.DOWN * 5, tick + 1)
				if tick % 30 == 0:
					var role: String = ["winner", "loser", "draw"][floori(float(tick) / 30.0) % 3]
					actor.apply_exchange(actor.terrain_cell + Vector2i.DOWN, _result(role, tick % 90 == 30))
				if tick % 30 in [1, 8, 17]:
					actor.step(Vector2i.LEFT if tick % 60 < 30 else Vector2i.RIGHT)
				if tick % 60 in [3, 5, 7]:
					actor.ranged_apply_hit(actor.terrain_cell + Vector2i.UP, {"result": {"hp": 1.0, "stun": 2.0, "stagger": 0.2}, "shield": false})
				actor.advance_combat(1.0 / 30.0, true)
			if not _same(_actor_state(people[0]), _actor_state(people[1]), "Actor gameplay " + weapon + " tick " + str(tick)):
				return
		for actor: Variant in people:
			actor.free()
	var old_army := _before("terrain_army.gd", "class_name TerrainArmy")
	if old_army == null:
		return
	var armies: Array = [old_army.new(), TerrainArmy.new()]
	var cells: Array[Vector2i] = [Vector2i(10, 10), Vector2i(15, 10), Vector2i(20, 10), Vector2i(25, 10)]
	for army: Variant in armies:
		root.add_child(army)
		army.set_process(false)
		army.exchange_enabled = true
		army.roster_size = 4
		assert(army.deploy_at(_map(), null, null, cells) and army.enable_combat(false))
	for tick: int in 360:
		for army: Variant in armies:
			for index: int in 4:
				if tick % 30 == 0:
					var role: String = ["winner", "loser", "draw"][(floori(float(tick) / 30.0) + index) % 3]
					army.apply_exchange(index, army.cells[index] + Vector2i.DOWN, _result(role, index % 2 == 0))
				if tick % 30 in [1, 8, 17]:
					army._reserve_combat_step(index, army.cells[index] + (Vector2i.LEFT if tick % 60 < 30 else Vector2i.RIGHT))
				if tick % 60 in [3, 5, 7]:
					army.ranged_apply_hit(index, army.cells[index] + Vector2i.UP, {"result": {"hp": 1.0, "stun": 2.0, "stagger": 0.2}, "shield": false})
			army.prepare_combat(1.0 / 30.0)
		if not _same(armies[0].capture_combat_state(), armies[1].capture_combat_state(), "Army original saved/gameplay state tick " + str(tick)):
			return
		if not _same(armies[0]._reserved_cells, armies[1]._reserved_cells, "Army authoritative reservations"):
			return
	for army: Variant in armies:
		army.free()
	print("SITE_EXCHANGE_ANIMATION_GAMEPLAY_PARITY_PASS: ", checks, " exact pre-change/current comparisons; HP/stun/fatigue/locks/position/reservations/real shots unchanged")
	quit(0)
