extends "res://scripts/tests/site_siege_landing_contract_test.gd"

const Controller = preload("res://scripts/terrain_lab/site_controller.gd")

class FallLab extends TerrainLab:
	var resolve_calls := 0
	var last_change := {}
	func resolve_structure_change(result: Dictionary) -> void:
		resolve_calls += 1
		last_change = result
		super.resolve_structure_change(result)

func _run() -> void:
	create_timer(75.0).timeout.connect(func() -> void: quit(1))
	_check_same_batch_ordinary_tower_and_wall()
	_check_support_collapse_original_people_once()
	TerrainArmy.release_contact_source()
	assert(completed == 2, "A siege surface-batch contract stopped before completion")
	print("SITE_SIEGE_SURFACE_BATCH_CONTRACT_PASS: original paid deployed tower/wall, original melee PersonActions joins shared contact batch before tower surface withdrawal, one old-to-final navigation snapshot, original Army and in-flight Actor once-only fall/KO/source-cell/items/identity, support-only invalidation preserves tower HP and source terrain; headless surface fixtures only, no GPU/native/performance claim")
	quit(0)

func _fall_fixture() -> Dictionary:
	var context := _tower_fixture()
	var lab := FallLab.new()
	lab.terrain = context.data
	var controller := Controller.new()
	controller.lab = lab
	lab.site_controller = controller
	controller.person_actions.init(lab)
	controller.vehicles.init(controller)
	controller.work_team.init(lab)
	var people := CrewFixture.new()
	var first := SiteRuntime._siege_tower_cell(context.data, context.vehicle, 1, 0)
	var second := SiteRuntime._siege_tower_cell(context.data, context.vehicle, 1, 1)
	var executor := SiteRuntime._siege_tower_cell(context.data, context.vehicle, 4, 1)
	people.setup(root, context.data, [first, second, executor])
	lab.army = people.army
	lab.combat_armies.append(people.army)
	people.army.vehicle_transport = controller.vehicles
	people.army.exchange_enabled = true
	var actor := TerrainTestCharacter.new()
	actor.data = context.data
	actor.person_id = 97001
	actor.faction_id = 1
	actor.item_state = SiteRuntime.new_item_state("person:97001")
	var source := SiteRuntime._siege_tower_cell(context.data, context.vehicle, 1, 2)
	assert(actor.place(source, true))
	assert(actor.step(Vector2i.RIGHT))
	actor._advance_movement(0.01)
	assert(actor.is_moving() and actor.movement_from_cell == source)
	lab.combat_actors.append(actor)
	context.vehicle.team_id = 0 # Neutral original tower makes real hostile melee legal.
	context.merge({"lab": lab, "controller": controller, "people": people, "actor": actor,
		"source": source, "ground": context.data.height_levels.duplicate()})
	return context

func _fall_originals(context: Dictionary) -> Dictionary:
	var army: TerrainArmy = context.people.army
	var holders: Array[Dictionary] = []
	var cargo: Array[Dictionary] = []
	var ids: Array[int] = []
	var hp: Array[float] = []
	for index in range(army.combat_units.size()):
		holders.append(army.combat_units[index].item_state)
		cargo.append(army.combat_units[index].cargo)
		ids.append(army.combat_identity(index))
		hp.append(float(army.combat_hot_get(index, &"hp")))
	return {"holders": holders, "cargo": cargo, "ids": ids, "hp": hp, "cells": army.cells.duplicate(),
		"actor_holder": context.actor.item_state, "actor_id": context.actor.person_id, "actor_hp": context.actor.hp}

func _assert_original_fall(context: Dictionary, original: Dictionary) -> void:
	var army: TerrainArmy = context.people.army
	assert(context.lab.resolve_calls == 1 and context.data.height_levels == context.ground)
	assert(context.actor.terrain_cell == context.source and not context.actor.is_moving())
	assert(context.actor.hp == float(original.actor_hp) - 30.0 and context.actor.knockout_left > 0.0)
	assert(context.actor.person_id == int(original.actor_id) and is_same(context.actor.item_state, original.actor_holder))
	for index in range(army.combat_units.size()):
		assert(army.cells[index] == original.cells[index] and army.combat_identity(index) == int(original.ids[index]))
		assert(float(army.combat_hot_get(index, &"hp")) == float(original.hp[index]) - 30.0 and float(army.combat_hot_get(index, &"ko")) > 0.0)
		assert(is_same(army.combat_units[index].item_state, original.holders[index]) and is_same(army.combat_units[index].cargo, original.cargo[index]))
		assert(context.data.effective_height(army.cells[index]) == 0)
	assert(context.lab.last_change.lost_surfaces.has(context.data.index(context.source)))

func _close_fall(context: Dictionary) -> void:
	context.lab.combat_actors.clear()
	context.actor.free()
	context.lab.combat_armies.clear()
	context.people.close()
	context.controller.free()
	context.lab.free()

func _check_same_batch_ordinary_tower_and_wall() -> void:
	var context := _fall_fixture()
	var army: TerrainArmy = context.people.army
	var executor := army.combat_identity(2)
	var holder: Dictionary = army.combat_units[2].item_state
	assert(SiteRuntime.create_equipment(context.data, holder, "siege_surface_axe", {"slot": "weapon", "asset": "axe_01", "tint": [1.0, 1.0, 1.0, 1.0]}, executor, "weapon").ok)
	var lethal := SiteCombatRules.structure_damage("axe_01", "wood")
	assert(lethal > 0.0)
	context.vehicle.hp = lethal
	context.vehicle.ever_hp_damaged = true
	var original := _fall_originals(context)
	var actions: SitePersonActions = context.controller.person_actions
	assert(actions.begin_vehicle_attack(executor, context.key).ok)
	actions.advance_structure_attacks(SiteCombatRules.EXCHANGE_ROUND_SECONDS)
	context.lab.siege_begin_contact_batch()
	var result := actions.settle_after_contacts()
	assert(result.size() == 1 and result[0].ok, str(result))
	assert(float(context.vehicle.hp) == lethal and context.lab.resolve_calls == 0, "An ordinary tower hit withdrew the surface before batch snapshot")
	var support := SiteRuntime._siege_tower_cell(context.data, context.vehicle, 5, 1)
	var part := "c:" + str(context.data.index(support))
	var key := str(context.wall) + "|" + part
	assert(context.lab.siege_queue_damage({key: {"feature": context.wall, "part": part, "damage": 100.0}}, {}, executor).ok)
	context.lab.siege_flush_contact_batch()
	assert(float(context.vehicle.hp) == 0.0 and str(context.vehicle.phase) == "wrecked")
	assert(float(context.data.site.features[context.wall].parts[part].hp) == 0.0)
	_assert_original_fall(context, original)
	assert(not context.lab.has_siege_projectiles())
	_close_fall(context)
	completed += 1

func _check_support_collapse_original_people_once() -> void:
	var context := _fall_fixture()
	var original := _fall_originals(context)
	var vehicle_hp := float(context.vehicle.hp)
	var pose: Dictionary = context.vehicle.deployed_pose.duplicate(true)
	var support := SiteRuntime._siege_tower_cell(context.data, context.vehicle, 5, 1)
	var part := "c:" + str(context.data.index(support))
	var key := str(context.wall) + "|" + part
	context.lab.siege_begin_contact_batch()
	assert(context.lab.siege_queue_damage({key: {"feature": context.wall, "part": part, "damage": 60.0}}, {}, 1).ok)
	assert(context.lab.siege_queue_damage({key: {"feature": context.wall, "part": part, "damage": 40.0}}, {}, 2).ok)
	assert(context.data.effective_height(context.source) == 2 and context.lab.resolve_calls == 0)
	context.lab.siege_flush_contact_batch()
	assert(float(context.vehicle.hp) == vehicle_hp and str(context.vehicle.phase) == "disabled" and context.vehicle.deployed_pose == pose)
	_assert_original_fall(context, original)
	var hp: float = context.actor.hp
	context.lab.siege_apply_damage_batch({key: {"feature": context.wall, "part": part, "damage": 40.0}}, {})
	assert(context.actor.hp == hp and context.lab.last_change.lost_surfaces.is_empty(), "An already lost surface charged original people twice")
	_close_fall(context)
	completed += 1
