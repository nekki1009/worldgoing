extends "res://scripts/terrain_lab/crowd_site.gd"
## Every override delegates to the original owner; no extra event observer.
var profiler: RefCounted

func _consume_events() -> void:
	var token: Dictionary = profiler.begin("crowd.consume_events_including_observers")
	super._consume_events()
	profiler.end(token)

func settle_events() -> void:
	var count := pending_captivity.size()
	var token: Dictionary = profiler.begin("crowd.settle_events")
	super.settle_events()
	var elapsed: int = profiler.end(token)
	if not token.is_empty() and count > 0:
		profiler.batches.append({"step": _steps, "input_pending": count, "remaining": pending_captivity.size(), "inclusive_us": elapsed})

func _commit_captivity(event: Dictionary, event_context: Dictionary = {}) -> Dictionary:
	var token: Dictionary = profiler.begin("crowd.commit_captivity")
	var result: Dictionary = super._commit_captivity(event, event_context)
	profiler.end(token)
	return result

func _captivity_atlas_guard(identity: int, appearance: Dictionary) -> Dictionary:
	var token: Dictionary = profiler.begin("crowd.captivity_atlas_guard")
	var result: Dictionary = super._captivity_atlas_guard(identity, appearance)
	profiler.end(token)
	return result

func _captivity_appearance(identity: int, holder: Dictionary, sealed_ids: Array) -> Dictionary:
	var token: Dictionary = profiler.begin("crowd.captivity_appearance")
	var result: Dictionary = super._captivity_appearance(identity, holder, sealed_ids)
	profiler.end(token)
	return result

func _sync_ammo(identity: int, state: Dictionary = {}) -> void:
	var token: Dictionary = profiler.begin("crowd.sync_ammo")
	super._sync_ammo(identity, state)
	profiler.end(token)

func equipment_changed(identity: int) -> void:
	var token: Dictionary = profiler.begin("crowd.equipment_changed")
	super.equipment_changed(identity)
	profiler.end(token)

func captivity_changed(identity: int, captor_id: int, capturing: bool) -> void:
	var token: Dictionary = profiler.begin("crowd.captivity_changed")
	super.captivity_changed(identity, captor_id, capturing)
	profiler.end(token)
