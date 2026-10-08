extends "res://scripts/tests/site_fire_suppress_navigation_test.gd"
## Original Army snapshots plus original Registry handoff, JSON.
## Root still owns the full Site/PersonActions/action-barrier acceptance.

func _finish(ok: bool, reason: String = "") -> void:
	if finished: return
	finished = true
	for f: Dictionary in fixtures.duplicate(): _close(f)
	TerrainArmy.release_contact_source()
	print("SITE_FIRE_NAVIGATION_PERSISTENCE_", "PASS" if ok else "FAIL", ": checks=", checks, " ", reason)
	await process_frame
	quit(0 if ok else 1)

func _json(value: Dictionary) -> Dictionary:
	var parsed: Variant = JSON.parse_string(JSON.stringify(value))
	return parsed if parsed is Dictionary else {}

func _snapshot(f: Dictionary) -> Dictionary:
	var army: TerrainArmy = f.army
	return _json({"army":army.capture_combat_state(),"navigation":army.fire_navigation_snapshot(),
		"registry":f.coordinator.deployment_registry.fire_lease_snapshot([army.team_id])})

func _restore(f: Dictionary, saved: Dictionary, tokens: Dictionary) -> Dictionary:
	var army: TerrainArmy = f.army
	var registry: SiteDeploymentReservationRegistry = f.coordinator.deployment_registry
	army.restore_combat_state(saved.army,f.data,null,null)
	var prepared_registry := registry.prepare_fire_lease_restore(saved.registry,[army.team_id],f.data)
	if not prepared_registry.ok: return prepared_registry
	var prepared_army := army.prepare_fire_navigation_restore(saved.navigation,prepared_registry.candidate,tokens,STEP)
	if not prepared_army.ok: return prepared_army
	var publication := registry.publish_handoff(prepared_registry)
	if not publication.ok: return publication
	if not army.can_publish_fire_navigation_restore(prepared_army,registry):
		registry.restore_handoff_state(publication.rollback)
		return {"ok":false,"code":"STALE_FIRE_RESTORE"}
	return army.publish_fire_navigation_restore(prepared_army,registry)

func _work_roundtrip(cancel_first: bool, arrived: bool = false) -> bool:
	var source := _fixture()
	var army: TerrainArmy = source.army
	var ids: Array[int] = [army.combat_identity(0),army.combat_identity(1)]
	var tokens := {ids[0]:301,ids[1]:302}
	var targets: Array[Vector2i] = [army.cells[0]+Vector2i(0,2),army.cells[1]+Vector2i(0,-2)]
	for index in range(2):
		if not _check(army.begin_suppress_approach(ids[index],301+index,targets[index],army.get_order_serial()).ok,"Original work admits before JSON save"): return false
	_tick(source)
	if arrived:
		for tick in range(60): _tick(source)
	var endpoints: Array[Vector2i] = [army.moving_to[0],army.moving_to[1]]
	if cancel_first: army.release_suppress_approach(ids[0],301)
	if not _check(army.fire_navigation_save_guard().ok,"Original completed barrier admits intact work navigation metadata"): return false
	var saved := _snapshot(source)
	if not _check(not saved.is_empty() and saved.navigation.work.size()==2 and saved.navigation.batches.size()==(0 if arrived else 2),
		"Pure-ID JSON retains both jobs and exact original batch count",{"arrived":arrived}): return false
	var target := _fixture()
	var restored: TerrainArmy = target.army
	var registry: SiteDeploymentReservationRegistry = target.coordinator.deployment_registry
	registry.try_replace_reservations(99,0,7,[Vector2i(20,18)])
	var foreign: Variant = registry.owner_of(Vector2i(20,18))
	var result := _restore(target,saved,tokens)
	if not _check(result.ok and is_same(foreign,registry.owner_of(Vector2i(20,18)))
		and restored.ranged_order_serial==int(saved.navigation.ranged_serial)
		and restored.cells[0]==army.cells[0] and restored.moving_to[0]==endpoints[0]
		and is_equal_approx(restored.move_progress[0],army.move_progress[0]),
		"Original restore retains exact physical half-step and foreign lease, with saved ranged generation",result): return false
	for tick in range(60): _tick(target)
	if not _check(restored.cells[0]==(endpoints[0] if cancel_first else targets[0]) and restored.cells[1]==targets[1]
		and restored._reserved_cells.is_empty() and target.coordinator.get_inflight_batches_for_formation(restored).is_empty()
		and restored.suppress_approach_query(ids[1],302).phase=="ARRIVED",
		"Loaded original bodies finish once and independent work really arrives",{"cancel_first":cancel_first,"cells":restored.cells}): return false
	if cancel_first and not _check(restored.suppress_approach_query(ids[0],301).done,"Loaded cancelled half-step cleans only that job"): return false
	_close(source)
	_close(target)
	return true

func _reject_without_publish() -> bool:
	var source := _fixture()
	var army: TerrainArmy = source.army
	var mid := army.combat_identity(1)
	if not _check(army.begin_suppress_approach(mid,401,army.cells[1]+Vector2i(0,2),army.get_order_serial()).ok,"Work admits before rejection fixture"): return false
	_tick(source)
	var saved := _snapshot(source)
	var target := _fixture()
	var restored: TerrainArmy = target.army
	restored.restore_combat_state(saved.army,target.data,null,null)
	var registry: SiteDeploymentReservationRegistry = target.coordinator.deployment_registry
	var before := registry.capture_handoff_state()
	var physical := restored._fire_navigation_restore_stamp()
	var malformed_registry: Dictionary = saved.registry.duplicate(true)
	malformed_registry.leases.append(malformed_registry.leases[0].duplicate(true))
	if not _check(not registry.prepare_fire_lease_restore(malformed_registry,[7],target.data).ok
		and registry.capture_handoff_state()==before and restored._fire_navigation_restore_stamp()==physical,
		"Duplicate saved lease rejects without mutating any live owner"): return false
	var prepared := registry.prepare_fire_lease_restore(saved.registry,[7],target.data)
	if not _check(prepared.ok,"Original handoff candidate is prepared privately"): return false
	var malformed: Dictionary = saved.navigation.duplicate(true)
	malformed.work[0].job_token=999
	var rejected := restored.prepare_fire_navigation_restore(malformed,prepared.candidate,{mid:401},STEP)
	if not _check(not rejected.ok and registry.capture_handoff_state()==before and restored._fire_navigation_restore_stamp()==physical,
		"Orphan job token rejects before live Registry/Army publication",rejected): return false
	malformed=saved.navigation.duplicate(true)
	malformed.batches.clear()
	rejected=restored.prepare_fire_navigation_restore(malformed,prepared.candidate,{mid:401},STEP)
	if not _check(not rejected.ok and registry.capture_handoff_state()==before and restored._fire_navigation_restore_stamp()==physical,
		"Missing physical batch provenance rejects atomically",rejected): return false
	_close(source)
	_close(target)
	return true

func _heat(f: Dictionary, cell: Vector2i) -> void:
	var key := "%d:%d" % [SiteEnvironment.Kind.TIMBER,f.data.index(cell)]
	SiteEnvironment._add_resource(f.data,SiteEnvironment.Kind.TIMBER,f.data.index(cell),256,0)
	var state := SiteRuntime._fire_state(f.data,0.0)
	var unit := SiteRuntime._fire_unit(f.data,state,SiteRuntime._fire_resource_descriptor(f.data,key))
	SiteEnvironment.change(f.data,key,{"remaining":0,"cleared":true})
	SiteEnvironment.rebuild_indexes(f.data)
	unit.merge({"profile":"TEST_HEAT_100","heat":0.0,"state":"BURNING","intensity":1.0,"moisture":0.0,"residue_q":256*SiteRuntime.FIRE_Q},true)
	state.active["resource:"+key]=true
	SiteRuntime.fire_hazard_invalidate(f.data)

func _hazard_roundtrip() -> bool:
	var source := _fixture()
	var army: TerrainArmy = source.army
	var hot: Vector2i = army.cells[1]
	_heat(source,hot)
	_tick(source)
	var endpoint: Vector2i = army.moving_to[1]
	var saved := _snapshot(source)
	if not _check(endpoint!=TerrainArmy.INVALID_CELL and not saved.navigation.hazard.is_empty(),"Real original escape half-step is captured"): return false
	var target := _fixture()
	_heat(target,hot)
	var result := _restore(target,saved,{})
	var restored: TerrainArmy = target.army
	if not _check(result.ok and restored._committed_intent_order(restored.combat_identity(1))==restored.FIRE_HAZARD_STEP
		and restored._fire_navigation.members.size()==army._fire_navigation.members.size(),"Loaded hazard intent rebinds original batch metadata and exact lease",result): return false
	for tick in range(20): _tick(target)
	if not _check(restored.cells[1]==endpoint and restored.moving_to[1]==TerrainArmy.INVALID_CELL and restored._reserved_cells.is_empty()
		and restored.combat_order==TerrainArmy.CombatOrder.HOLD,"Loaded hazard half-step completes once without replay or forced retreat"): return false
	_close(source)
	_close(target)
	return true

func _run() -> void:
	_finish(_work_roundtrip(false) and _work_roundtrip(true) and _work_roundtrip(false,true) and _reject_without_publish() and _hazard_roundtrip())
