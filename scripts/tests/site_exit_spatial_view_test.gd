extends SceneTree
## Original identity survives exit; disposable spatial/render projections do not.
const Snapshot = preload("res://scripts/terrain_lab/site_exchange_snapshot.gd")
const Batch = preload("res://scripts/terrain_lab/terrain_army_batch_view.gd")

func _initialize() -> void:
	_run.call_deferred()

func _row(identity: int) -> Dictionary:
	return {"person_id": identity, "hp": 100.0, "ko": 0.0, "age": 0.25, "think": 0.5,
		"stun": 0.0, "grace": 0.0, "pose": "idle", "attack": false, "member": true,
		"captive": false, "departed": false, "present": true, "exchange_cooldown": 1.0}

func _ids(people: Array[Dictionary]) -> Array[int]:
	var identities: Array[int] = []
	for person: Dictionary in people: identities.append(int(person.id))
	return identities

func _run() -> void:
	var lab := TerrainLab.new()
	var team := TerrainArmy.new()
	var actor := TerrainTestCharacter.new()
	team.combat_enabled = true
	team.exchange_enabled = true
	team.combat_units = [_row(11), _row(12), _row(13)]
	team.combat_units[1]["site_exited"] = true
	team.combat_units[2]["surrender_pending"] = true
	team.cells = [Vector2i(2, 3), Vector2i(3, 3), Vector2i(4, 3)]
	team.moving_to = [TerrainArmy.INVALID_CELL, TerrainArmy.INVALID_CELL, TerrainArmy.INVALID_CELL]
	actor.person_id = 1
	actor.terrain_cell = Vector2i(1, 3)
	actor.position = (Vector2(actor.terrain_cell) + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS
	actor.exchange_enabled = true
	actor.exchange_cooldown = 1.0
	actor.surrender_pending = true
	lab.character = actor
	lab.combat_actors = [actor]
	lab.combat_armies = [team]
	lab.selected_army_label = Label.new()
	assert(lab._combat_target(12).owner == team, "Exit cannot erase original person identity")
	assert(lab._combat_target_in_site(12, true).is_empty())
	assert(lab._combat_target_in_site(13).owner == team, "Surrender remains a spatial target")
	assert(not lab.select_army_target(team.cells[1]))
	assert(lab.select_army_target(team.cells[2]) and lab.selected_army_target == 13)
	var occupants := lab._ranged_occupants()
	assert(occupants.size() == 3 and not occupants.has(team.cells[1]))
	assert(occupants[team.cells[2]][0].id == 13)
	for native: bool in [false, true]:
		team.native_queries_enabled = native
		var snapshot := Snapshot.new()
		snapshot.capture(lab.combat_actors, lab.combat_armies)
		assert(snapshot.identities == PackedInt64Array([1, 11, 13]), "Cooldown/surrender bodies must match native and GD admission")
		assert(not snapshot.person(0).ready and not snapshot.person(0).receive)
		assert(_ids(lab._exchange_people(false)) == [1, 11, 13])
		var ready := lab._exchange_people(true)
		assert(_ids(ready) == [1, 11, 13] and not ready[2].ready and not ready[2].receive)
	actor.exchange_cooldown = 0.0
	team.combat_units[2].exchange_cooldown = 0.0
	assert(actor.exchange_can_receive() and team.exchange_can_receive(2), "Conscious surrender can receive hits")
	assert(not actor.exchange_ready() and not team.exchange_ready(2), "Surrender cannot initiate")
	actor.site_exited = true
	assert(lab._combat_target(1).owner == actor and lab._combat_target_in_site(1).is_empty())
	assert(not lab._ranged_occupants().has(actor.terrain_cell))
	_check_batch(team)
	for row: Dictionary in team.combat_units: row["site_exited"] = true
	var sweep: Array[PackedVector2Array] = [PackedVector2Array([Vector2.ZERO, Vector2(1024, 0), Vector2(0, 1024)])]
	assert(lab._collect_unit_contacts([], sweep, Vector2i.ZERO, Vector2.ZERO, null, -1).is_empty())
	var empty_snapshot := Snapshot.new()
	empty_snapshot.capture(lab.combat_actors, lab.combat_armies)
	assert(empty_snapshot.identities.is_empty() and lab._exchange_people().is_empty())
	lab.selected_army_label.free()
	lab.free()
	team.free()
	actor.free()
	print("SITE_EXIT_SPATIAL_VIEW_PASS identity, selection, contacts, projectile occupancy, native/GD surrender bodies, retained batch and Sprite removal")
	quit(0)

func _check_batch(team: TerrainArmy) -> void:
	var batch := Batch.new()
	root.add_child(batch)
	batch.setup(team, 3)
	batch._rows = {13: [1]}
	batch._page[1] = 0
	batch._index_row[1] = 13
	batch._index_run[1] = 0
	batch.rendered_count = 1
	batch._retained_mode = true
	batch._retained_ready = true
	batch._row_spans = {13: [{"page": 0, "members": [1], "start": 0, "stop": 1}]}
	var stale := MultiMeshInstance2D.new()
	batch.add_child(stale)
	batch._batches[Vector2i(13, 0)] = stale
	batch.remove(1)
	assert(batch._rows.is_empty() and batch.rendered_count == 0 and batch._page[1] == -1)
	batch.flush_retained()
	assert(not stale.visible and batch.active_batches == 0)
	batch._native_mask = PackedByteArray([0, 1, 0])
	batch._native_rows = PackedInt32Array([0, 13, 0])
	assert(batch.submit_prepared(1) and batch._native_mask[1] == 0 and batch._rows.is_empty())
	assert(batch.submit(1, Vector2.ZERO, {}, "idle", "south", 0.0))
	var exited_sprite := Sprite2D.new()
	root.add_child(exited_sprite)
	batch.submit_sprite(1, Vector2.ZERO, exited_sprite)
	assert(not exited_sprite.visible and batch._rows.is_empty())
	var pending_sprite := Sprite2D.new()
	root.add_child(pending_sprite)
	batch.submit_sprite(2, Vector2.ZERO, pending_sprite)
	assert(pending_sprite.visible and batch._rows[10] == [2])
	team.combat_units[2]["site_exited"] = true
	batch._retained_mode = true
	assert(batch.sample_retained_animations(PackedFloat64Array([0, 0, 0]), PackedByteArray([0, 0, 0])) == 0)
	assert(not pending_sprite.visible and batch._rows.is_empty(), "Ineligible retained masks cannot keep an exited original Sprite")
	exited_sprite.free()
	batch.free()
