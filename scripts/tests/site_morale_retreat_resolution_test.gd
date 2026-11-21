extends SceneTree

const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")

func _initialize() -> void:
	call_deferred("_run")

func _check(value: bool, label: String) -> bool:
	if value:
		return true
	push_error(label)
	quit(1)
	return false

func _blocked_edge_map() -> TerrainData:
	var data := Helper.build_flat_map(15, 15)
	for x in range(data.size.x):
		data.flags[data.index(Vector2i(x, 0))] = 0
		data.flags[data.index(Vector2i(x, data.size.y - 1))] = 0
	for y in range(data.size.y):
		data.flags[data.index(Vector2i(0, y))] = 0
		data.flags[data.index(Vector2i(data.size.x - 1, y))] = 0
	data.navigation_revision += 1
	return data

func _army(data: TerrainData, start: Vector2i = Vector2i(5, 5)) -> TerrainArmy:
	var army := Helper.create_test_army(data, 1, 0, 1, start)
	army.sustain_routed_query = func(_team: TerrainArmy) -> bool: return true
	return army

func _run() -> void:
	var open := Helper.build_flat_map(15, 15)
	open.site.features["nearby-house"] = {"kind": "house", "stage": "complete", "entrance": open.index(Vector2i(6, 5)), "cells": [open.index(Vector2i(6, 6))], "solid": true}
	var edge := _army(open)
	if not _check(bool(edge.begin_morale_retreat().ok), "edge: collapse starts retreat"): return
	var refused_hold := edge.issue_combat_order(edge.current_commander, TerrainArmy.CombatOrder.HOLD)
	if not _check(not bool(refused_hold.ok) and edge.combat_order == TerrainArmy.CombatOrder.RETREAT, "collapse: HOLD must not cancel forced escape"): return
	for tick in range(50):
		edge.prepare_combat(0.5)
		if bool(edge.combat_hot_get(0, &"site_exited", false)):
			break
	if not _check(bool(edge.combat_hot_get(0, &"site_exited", false)), "edge: living member must actually leave map"): return
	if not _check(edge._cell_owners.is_empty() and edge.morale_retreat_terminal(), "edge: exit clears cell ownership and terminates"): return
	var edge_save := edge.capture_combat_state()
	if not _check(TerrainArmy.valid_combat_state(edge_save, open), "edge: exit snapshot valid"): return
	edge.free()

	var sealed := _blocked_edge_map()
	var surrender := _army(sealed)
	if not _check(bool(surrender.begin_morale_retreat().ok), "sealed: collapse starts retreat"): return
	surrender.prepare_combat(0.6)
	if not _check(bool(surrender.combat_hot_get(0, &"surrender_pending", false)) and not bool(surrender.combat_hot_get(0, &"captive", false)), "sealed: no refuge means awaiting capture, not fake captivity"): return
	if not _check(TerrainArmy.valid_combat_state(surrender.capture_combat_state(), sealed), "sealed: surrender snapshot valid"): return
	surrender.free()

	var built := _blocked_edge_map()
	built.site.features["house-1"] = {"kind": "house", "stage": "complete", "entrance": built.index(Vector2i(6, 5)), "cells": [built.index(Vector2i(6, 6))], "solid": true}
	var refuge := _army(built, Vector2i(4, 5))
	refuge.begin_morale_retreat()
	for tick in range(10):
		refuge.prepare_combat(0.5)
	if not _check(not bool(refuge.combat_hot_get(0, &"surrender_pending", false)) and not bool(refuge.combat_hot_get(0, &"site_exited", false)) and refuge.cells[0] == Vector2i(5, 5), "building: reachable completed approach is second priority"): return
	var controller := SiteController.new()
	if not _check(refuge.morale_retreat_sheltered() and controller._team_stopped(refuge, true), "building: sheltered original people must be physically stopped for safe Sustain regroup"): return
	controller.free()
	refuge.free()

	var reopened_data := _blocked_edge_map()
	reopened_data.site.features["reopened-house"] = {"kind": "house", "stage": "complete", "entrance": reopened_data.index(Vector2i(6, 5)), "cells": [reopened_data.index(Vector2i(6, 6))], "solid": true}
	var reopened := _army(reopened_data, Vector2i(4, 5))
	reopened.begin_morale_retreat()
	for tick in range(10): reopened.prepare_combat(0.5)
	if not _check(reopened.morale_retreat_sheltered(), "reopened: member first reaches a real shelter"): return
	reopened_data.flags[reopened_data.index(Vector2i(0, 5))] = TerrainData.Flag.WALKABLE
	reopened_data.navigation_revision += 1
	for tick in range(30):
		reopened.prepare_combat(0.5)
		if bool(reopened.combat_hot_get(0, &"site_exited", false)): break
	if not _check(bool(reopened.combat_hot_get(0, &"site_exited", false)), "reopened: edge regains priority after shelter"): return
	reopened.free()

	var actor_data := _blocked_edge_map()
	actor_data.site.features["actor-house"] = {"kind": "house", "stage": "complete", "entrance": actor_data.index(Vector2i(6, 5)), "cells": [actor_data.index(Vector2i(6, 6))], "solid": true}
	var actor_blocked := _army(actor_data, Vector2i(4, 5))
	var hostile_actor := TerrainTestCharacter.new()
	hostile_actor.data = actor_data
	hostile_actor.terrain_cell = Vector2i(6, 5)
	hostile_actor.faction_id = 1
	actor_blocked.npc = hostile_actor
	actor_blocked.begin_morale_retreat()
	for tick in range(5): actor_blocked.prepare_combat(0.5)
	if not _check(bool(actor_blocked.combat_hot_get(0, &"surrender_pending", false)), "hostile Actor at entrance invalidates building shelter"): return
	actor_blocked.free()
	hostile_actor.free()

	var hostile_data := _blocked_edge_map()
	hostile_data.site.features["blocked-house"] = {"kind": "house", "stage": "complete", "entrance": hostile_data.index(Vector2i(6, 5)), "cells": [hostile_data.index(Vector2i(6, 6))], "solid": true}
	var hunted := _army(hostile_data, Vector2i(4, 5))
	var hostile := Helper.create_test_army(hostile_data, 2, 1, 1, Vector2i(6, 5))
	var coordinator := SiteCombatMovementCoordinator.new()
	coordinator.register_formation(hunted)
	coordinator.register_formation(hostile)
	hunted.begin_morale_retreat()
	for tick in range(5): hunted.prepare_combat(0.5)
	if not _check(bool(hunted.combat_hot_get(0, &"surrender_pending", false)), "enemy at building entrance makes the whole building unavailable"): return
	hunted.free()
	hostile.free()

	var occupied_edge_data := _blocked_edge_map()
	occupied_edge_data.flags[occupied_edge_data.index(Vector2i(0, 5))] = TerrainData.Flag.WALKABLE
	occupied_edge_data.navigation_revision += 1
	occupied_edge_data.site.features["alternate-house"] = {"kind": "house", "stage": "complete", "entrance": occupied_edge_data.index(Vector2i(7, 5)), "cells": [occupied_edge_data.index(Vector2i(7, 6))], "solid": true}
	var diverted := _army(occupied_edge_data, Vector2i(5, 5))
	var edge_guard := Helper.create_test_army(occupied_edge_data, 3, 1, 1, Vector2i(0, 5))
	var edge_coordinator := SiteCombatMovementCoordinator.new()
	edge_coordinator.register_formation(diverted)
	edge_coordinator.register_formation(edge_guard)
	diverted.begin_morale_retreat()
	for tick in range(15): diverted.prepare_combat(0.5)
	if not _check(diverted.morale_retreat_sheltered() and not bool(diverted.combat_hot_get(0, &"site_exited", false)), "enemy holding sole exit forces reachable building fallback"): return
	diverted.free()
	edge_guard.free()

	var shared_data := _blocked_edge_map()
	shared_data.site.features["shared-house"] = {"kind": "house", "stage": "complete", "entrance": shared_data.index(Vector2i(7, 5)), "cells": [shared_data.index(Vector2i(7, 6))], "solid": true}
	var shared := Helper.create_test_army(shared_data, 4, 0, 2, Vector2i(4, 5))
	shared.sustain_routed_query = func(_team: TerrainArmy) -> bool: return true
	shared.begin_morale_retreat()
	for tick in range(25): shared.prepare_combat(0.5)
	if not _check(shared.morale_retreat_sheltered() and shared.cells[0] != shared.cells[1] and not bool(shared.combat_hot_get(0, &"surrender_pending", false)) and not bool(shared.combat_hot_get(1, &"surrender_pending", false)), "two people shelter in distinct real building approaches"): return
	shared.free()

	var waiting_data := _blocked_edge_map()
	waiting_data.site.features["waiting-house"] = {"kind": "house", "stage": "complete", "entrance": waiting_data.index(Vector2i(6, 5)), "cells": [waiting_data.index(Vector2i(6, 6))], "solid": true}
	var waiting := _army(waiting_data, Vector2i(4, 5))
	var temporary := {"blocked": true}
	waiting.external_blocker = func(cell: Vector2i) -> bool:
		return bool(temporary.blocked) and cell in [Vector2i(5, 5), Vector2i(6, 5), Vector2i(7, 5), Vector2i(6, 4), Vector2i(6, 6)]
	waiting.begin_morale_retreat()
	waiting.prepare_combat(0.5)
	var waiting_entry: Dictionary = waiting._retreat_resolution.get("members", {}).get(str(waiting.combat_identity(0)), {})
	if not _check(waiting_entry.get("status") == "waiting" and not bool(waiting.combat_hot_get(0, &"surrender_pending", false)) and TerrainArmy.valid_combat_state(waiting.capture_combat_state(), waiting_data), "temporary blocker: wait without false surrender and keep valid save"): return
	temporary.blocked = false
	for tick in range(10): waiting.prepare_combat(0.5)
	if not _check(waiting.morale_retreat_sheltered(), "temporary blocker: replan to available building after release"): return
	waiting.free()
	print("SITE MORALE RETREAT RESOLUTION PASS: edge exit, sealed surrender, completed building refuge")
	quit(0)
