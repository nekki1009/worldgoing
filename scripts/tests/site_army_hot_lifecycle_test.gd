extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _row(identity: int) -> Dictionary:
	return {"person_id": identity, "hp": 100.0, "ko": 0.0, "age": 0.0, "think": 0.5,
		"stun": 0.0, "grace": 0.0, "pose": "idle", "attack": false,
		"captive": false, "departed": false, "present": true, "cargo": {"rice": 2}}

func _run() -> void:
	var army := TerrainArmy.new()
	army.native_hot_enabled = true
	var first := _row(101)
	var second := _row(102)
	army.combat_units.assign([first, second])
	assert(army.combat_hot_index_for_identity(102) == 1)
	assert(army._try_install_combat_hot_store())
	assert(army.combat_hot_active())
	assert(army.index_for_identity(999) == -1 and army.index_for_identity(999) == -1)
	assert(army.index_for_identity(102) == 1)
	assert(not first.has("hp") and first.has("cargo"))
	assert(army.is_member(0))
	army.combat_hot_set(0, &"member", false)
	assert(not army.is_member(0))
	army.combat_hot_set(0, &"member", true)
	assert(army.combat_hot_get(0, &"hp") == 100.0)
	army.combat_hot_set(0, &"hp", 63.25)
	army.combat_hot_set(1, &"captive", true)
	assert(not first.has("hp") and army.combat_hot_column(&"hp") == PackedFloat64Array([63.25, 100.0]))
	assert(army.combat_hot_column(&"captive") == PackedFloat64Array([0.0, 1.0]))
	assert(not army.combat_hot_has(0, &"exchange_cooldown"))
	army.combat_hot_set(0, &"exchange_cooldown", 0.5)
	assert(army.combat_hot_has(0, &"exchange_cooldown"))
	army.combat_hot_erase(0, &"exchange_cooldown")
	assert(not army.combat_hot_has(0, &"exchange_cooldown"))
	var single := army.combat_hot_materialize(0)
	assert(float(single.hp) == 63.25 and single.cargo.rice == 2)
	assert(not single.has("exchange_cooldown"))
	army._borrow_combat_hot_row(0)
	assert(float(first.hp) == 63.25)
	first.hp = 58.5
	army._return_combat_hot_row()
	assert(not first.has("hp") and float(army.combat_hot_get(0, &"hp")) == 58.5)
	var all_rows := army.materialized_combat_rows()
	assert(all_rows.size() == 2 and float(all_rows[0].hp) == 58.5 and bool(all_rows[1].captive))
	army._release_combat_hot_store(true)
	assert(not army.combat_hot_active() and float(first.hp) == 58.5 and bool(second.captive))
	assert(army.combat_hot_index_for_identity(102) == 1)
	second.person_id = 999
	assert(army.index_for_identity(999) == 1 and army.index_for_identity(102) == -1)
	assert(army._try_install_combat_hot_store())
	assert(army.index_for_identity(999) == 1 and army.index_for_identity(102) == -1)
	army._release_combat_hot_store(true)
	army.free()
	var output := FileAccess.open("res://output/site_army_5k_hot_close_20260926/hot_lifecycle_smoke.json", FileAccess.WRITE)
	assert(output != null)
	output.store_string(JSON.stringify({"checks": {"admission": true, "owner_reads_and_writes": true,
		"cold_reference": true, "optional_key": true, "single_and_full_materialization": true,
		"release_rebind": true, "active_negative_id_cache": true, "single_row_borrow": true, "member_query": true}, "army_sha256": FileAccess.get_sha256("res://scripts/terrain_lab/terrain_army.gd"),
		"cpp_sha256": FileAccess.get_sha256("res://native/army_idle/army_idle.cpp"),
		"dll_sha256": FileAccess.get_sha256("res://native/army_idle/bin/army_idle.windows.x86_64.dll"),
		"test_sha256": FileAccess.get_sha256("res://scripts/tests/site_army_hot_lifecycle_test.gd")}))
	output.close()
	print("ARMY_COMBAT_HOT_LIFECYCLE_PASS")
	quit(0)
