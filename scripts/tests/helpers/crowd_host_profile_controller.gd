extends "res://scripts/terrain_lab/site_controller.gd"
## Installed on the same fresh Node before its original setup/bind. No new owner.
var profiler: RefCounted
var _tail_token := {}

func advance_crowd_sustain(seconds: float) -> void:
	var token: Dictionary = profiler.begin("host.crowd_supply")
	super.advance_crowd_sustain(seconds)
	profiler.end(token)

func advance_person_supply(seconds: float) -> void:
	var token: Dictionary = profiler.begin("host.personal_supply")
	super.advance_person_supply(seconds)
	profiler.end(token)

func settle_person_deaths(seconds: float) -> void:
	# The unchanged D caller runs this, action settlement, deliveries, ordinary
	# command settlement, then check_family_death synchronously in that order.
	assert(_tail_token.is_empty(), "A prior original host tail was not closed")
	_tail_token = profiler.begin("host.original_life_orders_family_tail")
	super.settle_person_deaths(seconds)

func check_family_death() -> void:
	super.check_family_death()
	profiler.end(_tail_token)
	_tail_token = {}
