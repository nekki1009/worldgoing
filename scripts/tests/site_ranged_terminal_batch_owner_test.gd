extends "res://scripts/tests/site_building_ui_test.gd"
## SOURCE-ONLY component fixture, canonical visual 180/210.
## Uses the real original TerrainLab/Controller/VehicleTransport item guard and
## original depot/item registry. Finite initial depot inputs are explicit
## backgrounds. Real NoCombat PA timer is exercised separately; does not claim contact, first research, World birth,
## Native, common-point publication or the full40 acceptance.

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 180000
	_run.call_deferred()

func _stock(data: TerrainData, resources: Dictionary) -> void:
	data.site.inventory.clear()
	data.site.inventory.merge(resources, true)

func _run() -> void:
	var data: TerrainData = _building_fixture()
	var lab: TerrainLab = _building_lab(data)
	var person_a: int = int(lab.character.person_id)
	var person_b: int = int(lab.npc.person_id)
	assert(person_a > 0 and person_b > 0 and person_a != person_b)
	_stock(data, {"wood": 8, "fiber": 3, "iron": 2, "tools": 1})
	var version: int = int(data.site.depot_items.version)
	var next_item: int = int(data.site.next_item)
	var revision: int = int(data.environment_revision)
	var elapsed: Array = [data.site.minute, data.site.phase, lab.character.fatigue, lab.npc.fatigue]
	var before: PackedByteArray = var_to_bytes(data.site)
	var bow: Dictionary = Runtime.prepare_ranged_craft(data, "bow", person_a)
	var crossbow: Dictionary = Runtime.prepare_ranged_craft(data, "crossbow", person_b)
	assert(bow.ok and crossbow.ok and var_to_bytes(data.site) == before)
	var batch: Dictionary = Runtime.prepare_ranged_craft_batch(data, [bow, crossbow])
	assert(batch.ok and Runtime.validate_prepared_ranged_craft_batch(batch))
	assert(var_to_bytes(data.site) == before, "All cost/item allocation is pure before the first material debit")
	var forged: Dictionary = batch.duplicate(false)
	forged.stock_after = batch.stock_after.duplicate(true)
	forged.stock_after.fire_pot = 999
	assert(not Runtime.validate_prepared_ranged_craft_batch(forged), "Same original inputs do not authorize a caller-supplied output projection")
	assert(var_to_bytes(data.site) == before)
	var results: Array[Dictionary] = Runtime.publish_prepared_ranged_craft_batch(batch)
	assert(results.size() == 2 and results[0].ok and results[1].ok)
	assert(results[0].item_id == str(next_item) and results[1].item_id == str(next_item + 1))
	assert(data.site.item_records[results[0].item_id].original_owner == person_a)
	assert(data.site.item_records[results[1].item_id].original_owner == person_b)
	assert(data.site.item_records[results[0].item_id].definition == "weapon:bow_01")
	assert(data.site.item_records[results[1].item_id].definition == "weapon:crossbow_01")
	assert(int(data.site.next_item) == next_item + 2 and int(data.site.depot_items.version) == version + 2)
	assert(int(data.environment_revision) == revision + 2 and data.site.inventory == {"tools": 1})
	assert([data.site.minute, data.site.phase, lab.character.fatigue, lab.npc.fatigue] == elapsed)
	assert(not Runtime.validate_prepared_ranged_craft_batch(batch), "A published batch cannot replay")
	assert(not Runtime.validate_prepared_ranged_craft(bow) and not Runtime.validate_prepared_ranged_craft(crossbow))

	# Both jobs can independently prepare from the one real finite input pair;
	# the same original sorted transaction keeps only the first payable output.
	_stock(data, {"wood": 1, "iron": 1, "tools": 1})
	version = int(data.site.depot_items.version)
	before = var_to_bytes(data.site)
	var arrow: Dictionary = Runtime.prepare_ranged_craft(data, "arrow", person_a)
	var bolt: Dictionary = Runtime.prepare_ranged_craft(data, "bolt", person_b)
	assert(arrow.ok and bolt.ok)
	batch = Runtime.prepare_ranged_craft_batch(data, [arrow, bolt])
	assert(batch.ok and batch.results[0].ok and not batch.results[1].ok and batch.results[1].code == "MATERIALS")
	assert(var_to_bytes(data.site) == before)
	results = Runtime.publish_prepared_ranged_craft_batch(batch)
	assert(results[0].ok and not results[1].ok and int(data.site.inventory.get("arrow", 0)) == 10)
	assert(int(data.site.inventory.get("bolt", 0)) == 0 and int(data.site.depot_items.version) == version + 1)
	assert(data.site.inventory == {"arrow": 10, "tools": 1})

	# Real original Runtime mutation changes the original source version. A
	# stale candidate is rejected by pure validation, before it can cost again.
	_stock(data, {"wood": 4, "fiber": 2, "stone": 2, "tools": 1})
	bow = Runtime.prepare_ranged_craft(data, "bow", person_a)
	assert(bow.ok and Runtime.ranged_craft(data, "siege_stone", person_b).ok)
	before = var_to_bytes(data.site)
	assert(not Runtime.validate_prepared_ranged_craft(bow))
	assert(not Runtime.prepare_ranged_craft_batch(data, [bow]).ok)
	assert(var_to_bytes(data.site) == before, "Stale batch rejection has zero additional source/material/output cost")

	# Genuine original PA jobs consume the real shared clock. No elapsed write,
	# synthetic contact, hand-picked prefix or fixture-owned inventory publisher.
	_stock(data, {"wood": 2, "iron": 2, "tools": 1})
	# Camp craft requires a legal cell 4-adjacent to the depot (9,9); the shared
	# fixture leaves the character diagonal at (10,10), so stand it at (9,10).
	var character_placed: bool = lab.character.place(Vector2i(9, 10), true)
	assert(character_placed)
	var actions: SitePersonActions = lab.site_controller.person_actions
	assert(actions.begin_ranged_craft(person_a, "arrow").ok)
	assert(actions.begin_ranged_craft(person_b, "bolt").ok)
	version = int(data.site.depot_items.version)
	var minute_before: int = int(data.site.minute)
	var phase_before: float = float(data.site.phase)
	var game_seconds := 0.0
	var points := 0
	while actions.is_busy(person_a) or actions.is_busy(person_b):
		assert(Time.get_ticks_msec() < deadline and points < 250)
		var point: Dictionary = lab._advance_original_shared_step(TerrainLab.ACTION_STEP)
		assert(point.ok and float(point.get("game_seconds", 0.0)) > 0.0)
		game_seconds += float(point.game_seconds)
		points += 1
	assert(is_equal_approx(game_seconds, 60.0))
	assert(int(data.site.minute) == minute_before + 1 and is_equal_approx(float(data.site.phase), phase_before))
	assert(data.site.inventory == {"arrow": 10, "bolt": 10, "tools": 1})
	assert(int(data.site.depot_items.version) == version + 2)
	before = var_to_bytes(data.site)
	assert(actions.settle_after_contacts().is_empty() and var_to_bytes(data.site) == before)

	# The ORIGINAL shared source ledger accepts first numericID and holds the
	# second without charging its impossible final productive prefix. The first
	# actual output is retained; no aggregate upper refusal cancels the point.
	_stock(data, {"wood": 1, "iron": 1, "tools": 1})
	assert(person_a < person_b, "Original fixture playerID precedes NPCID; do not fabricate or swap original identities")
	assert(actions.begin_ranged_craft(person_a, "arrow").ok)
	assert(actions.begin_ranged_craft(person_b, "bolt").ok)
	version = int(data.site.depot_items.version)
	points = 0
	while actions.is_busy(person_a) or actions.is_busy(person_b):
		assert(Time.get_ticks_msec() < deadline and points < 250)
		var point: Dictionary = lab._advance_original_shared_step(TerrainLab.ACTION_STEP)
		assert(point.ok and float(point.get("game_seconds", 0.0)) > 0.0)
		points += 1
	assert(data.site.inventory == {"arrow": 10, "tools": 1})
	assert(int(data.site.inventory.get("bolt", 0)) == 0 and int(data.site.depot_items.version) == version + 1)
	assert(actions.job_for(person_a).is_empty() and actions.job_for(person_b).is_empty())
	lab.free()
	print("RANGED_TERMINAL_BATCH_OWNER_COMPONENT_PASS original depot/factory source and replay guards; true NoCombat original ACTION_STEP twojobs/one clock plus finite numeric firstpay/second zerooutput; CONTACT_AND_SCOPE_RUNTIME_NOT_RUN")
	quit(0)
