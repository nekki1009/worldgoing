extends SceneTree

const PersonFixture = preload("res://scripts/tests/site_person_actions_test.gd")
const WorkFixture = preload("res://scripts/tests/site_work_team_test.gd")

class ObservedArmy extends TerrainArmy:
	var atlas_calls := 0
	var live_calls := 0
	var observed: Dictionary = {}
	func _set_soldier_frame(index: int, _force: bool = false) -> void:
		atlas_calls += 1
		var frame := combat_frame(index)
		observed[index] = {"clip": str(frame.clip), "time": float(frame.sample_time),
			"direction": str(frame.direction), "appearance": equipment_appearance(index).duplicate(true)}
	func _sync_captain_combat(_frame: Dictionary, _index: int = 0) -> void:
		live_calls += 1

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	create_timer(18.0).timeout.connect(func() -> void: quit(1))
	_person_readiness()
	_work_readiness()
	_render_dirty()
	print("SITE_EXCHANGE_READINESS_RENDER_PASS: original actor/army action locks, no loot/equipment/work during stagger, retained work orders, dirty-only atlas and live captain dispatch, pose/movement/equipment invalidation, legacy dispatch preserved")
	quit(0)

func _person_readiness() -> void:
	var fixture := PersonFixture.Fixture.new()
	fixture.controlled_id = 3
	var row: Dictionary = fixture.army.combat_units[0]
	row.exchange_stagger = 0.35
	assert(fixture.army.combat_can_act(0), "Stagger cannot revoke life/command eligibility")
	assert(not fixture.actions._ready(fixture.actions._person(3)))
	fixture.npc.knockout_left = 10.0
	fixture.terrain.site.worker.cargo.grain = 1
	assert(fixture.actions.begin_loot(3, "person", "2", {"grain": 1}, []).code == "BUSY")
	assert(not fixture.actions.is_busy(3) and fixture.terrain.site.worker.cargo.grain == 1)
	var equipment := SiteEquipmentOrders.new()
	equipment.init(fixture, fixture.actions)
	assert(equipment.prepare(3, {"mode": "issue", "nation_id": "missing", "standard_id": "missing"}).code == "BUSY", "Equipment's original provider must share the central action lock")
	row.exchange_stagger = 0.0
	assert(fixture.actions._ready(fixture.actions._person(3)))
	assert(fixture.actions.begin_loot(3, "person", "2", {"grain": 1}, []).ok)
	fixture.actions.cancel(3)
	fixture.character.exchange_stagger = 0.3
	assert(fixture.character.can_act() and not fixture.actions._ready(fixture.actions._person(1)), "Actor render-only reaction cannot permit parallel work")
	fixture.character.exchange_stagger = 0.0
	assert(fixture.actions._ready(fixture.actions._person(1)))
	equipment.lab = null
	equipment.actions = null
	fixture.actions.equipment_orders = null
	fixture.close()

func _work_readiness() -> void:
	var fixture := WorkFixture.Fixture.new()
	fixture.army.exchange_enabled = true
	fixture.setup(root)
	var ids := fixture.ids()
	var row: Dictionary = fixture.army.combat_units[1]
	row.exchange_stagger = 0.35
	assert(fixture.crew.assign(fixture.army, ids, fixture.army.combat_identity(0)).code == "BUSY")
	assert(fixture.crew.active_ids().is_empty(), "Blocked batch must not partly assign other workers")
	row.exchange_stagger = 0.0
	assert(fixture.crew.assign(fixture.army, ids, fixture.army.combat_identity(0)).ok)
	row.exchange_stagger = 0.35
	fixture.crew.advance(1.0)
	assert(fixture.crew.is_assigned(ids[0]) and not fixture.crew.is_working(ids[0]) and row.work_task.mode == "paused")
	assert(row.work_task.progress == 0.0, "Incoming stagger must not perform productive work")
	row.exchange_stagger = 0.0
	fixture.crew.advance(1.0)
	assert(fixture.crew.is_assigned(ids[0]) and fixture.crew.is_working(ids[0]), "Recovery resumes the same original assigned order")
	fixture.crew.cancel(ids[0])
	fixture.controlled_id = ids[0]
	row.exchange_stagger = 0.35
	assert(fixture.crew.begin_manual(ids[0], "crew_a").code == "BUSY")
	row.exchange_stagger = 0.0
	assert(fixture.crew.begin_manual(ids[0], "crew_a").ok)
	row.exchange_stagger = 0.35
	fixture.crew.advance(1.0)
	assert(not fixture.crew.is_assigned(ids[0]) and row.work_task.is_empty(), "A manual batch is interrupted, not secretly worked during reaction")
	fixture.close()

func _render_dirty() -> void:
	var data := TerrainData.new()
	data.allocate(Vector2i(32, 32))
	data.flags.fill(TerrainData.Flag.WALKABLE)
	SiteEnvironment.initialize(data, "exchange-render-dirty")
	data.static_blocked.fill(0)
	var army := ObservedArmy.new()
	root.add_child(army)
	army.set_process(false)
	army.exchange_enabled = true
	army.roster_size = 3
	var selected: Array[Vector2i] = [Vector2i(10, 10), Vector2i(12, 10), Vector2i(14, 10)]
	assert(army.deploy_at(data, null, null, selected) and army.enable_combat(false))
	# Headless draw-dispatch instrumentation, not a claim of GPU pixel acceptance.
	for index in range(3):
		var sprite := Sprite2D.new()
		army.add_child(sprite)
		army._sprites.append(sprite)
	army._soldier_sprite_anchors.resize(3)
	army.advance_frame(0.01)
	assert(army.atlas_calls == 2 and army.live_calls == 1 and not army._visual_dirty)
	var prior_profile := army.combat_render_usec
	army.advance_frame(0.01)
	assert(army.atlas_calls == 2 and army.live_calls == 1, "No new logical state means no repeated atlas or live pose evaluation")
	assert(army.combat_render_usec - prior_profile == army.last_frame_cpu_usec)
	army.prepare_combat(1.2) # Cross the actual four-sample held-idle atlas boundary.
	army.advance_frame(0.01)
	assert(army.atlas_calls == 4 and float(army.observed[1].time) > 0.0)
	army.apply_exchange(1, selected[1] + Vector2i.RIGHT, {"role": "loser", "kind": "small", "hp": 1.0, "stun": 8.0, "stagger": 0.35, "fatigue": 0.5})
	army.advance_frame(0.01)
	assert(army.atlas_calls == 6 and army.observed[1].clip == "hit" and army.observed[1].direction == "right")
	army.advance_frame(0.01)
	assert(army.atlas_calls == 6)
	assert(army.start_unit_attack(2, selected[2] + Vector2i.UP, 999))
	army.advance_frame(0.01)
	assert(army.atlas_calls == 8 and army.observed[2].direction == "up", "Requested facing must invalidate before the next exchange tick")
	assert(army._reserve_combat_step(2, selected[2] + Vector2i.UP))
	army.advance_frame(0.01)
	assert(army.atlas_calls == 10 and army.observed[2].clip == "combat_walk")
	army.advance_frame(0.01)
	assert(army.atlas_calls == 10, "No movement progression occurred between these two rendered frames")
	army.prepare_combat(TerrainArmy.MOVE_DURATION)
	army.advance_frame(0.01)
	assert(army.atlas_calls == 12 and army.observed[2].clip == "combat_idle")
	var appearance: Dictionary = TerrainArmy._combat_bake.manifest.appearance.duplicate(true)
	army.equipment_appearance_query = func(_identity: int) -> Dictionary: return appearance
	# SiteController.equipment_changed invalidates this same existing flag after
	# an atomic holder commit; there is no appearance cache in TerrainArmy.
	appearance.parts.shield = "none"
	army._visual_dirty = true
	army.advance_frame(0.01)
	assert(army.atlas_calls == 14 and army.observed[2].appearance.parts.shield == "none")
	assert(army.set_unit_guard(2, true))
	army.advance_frame(0.01)
	assert(army.atlas_calls == 16 and army.observed[2].clip == "guard_weapon_raise")
	army.apply_unit_contact(2, {"result": {"hp": 0.0, "stun": 110.0, "guard_break": false}, "shield": false})
	army.advance_frame(0.01)
	assert(army.atlas_calls == 18 and army.observed[2].clip == "down")
	army._wake_unit(2)
	army.advance_frame(0.01)
	assert(army.atlas_calls == 20 and army.observed[2].clip == "get_up", "Wake must invalidate even when invoked outside prepare_combat")
	army.exchange_enabled = false
	army.advance_frame(0.01)
	army.advance_frame(0.01)
	assert(army.atlas_calls == 24, "Legacy geometry mode retains its prior per-render selection")
	army.clear()
	army.free()
