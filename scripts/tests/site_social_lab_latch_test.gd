extends SceneTree
## R2 day settlement is latched per live lab, not per process: two labs on the
## same game day each run their own first full pass, so each player body gets
## its own social_state (the ecology replay compares a paced and a one-shot lab
## in one process and found only the first one carried it).

const SiteSocial = preload("res://scripts/terrain_lab/site_social.gd")

class FakeTerrain:
	extends RefCounted
	var site := {"id": "latch", "minute": 840}

class FakeLab:
	extends RefCounted
	var terrain := FakeTerrain.new()
	var crowd_site: Variant = null
	var combat_armies: Array = []
	var combat_actors: Array = []
	func controlled_person_id() -> int: return -1

func _initialize() -> void:
	call_deferred("run")

func _fail(message: String) -> void:
	push_error(message)
	quit(1)

func _lab(person_id: int) -> FakeLab:
	var lab := FakeLab.new()
	var actor := TerrainTestCharacter.new()
	actor.person_id = person_id
	lab.combat_actors.append(actor)
	return lab

func run() -> void:
	SiteSocial.reset_site_state()
	var first := _lab(1)
	var second := _lab(2)
	SiteSocial.settle_site(first)
	SiteSocial.settle_site(second)
	var a: TerrainTestCharacter = first.combat_actors[0]
	var b: TerrainTestCharacter = second.combat_actors[0]
	var ok := not a.social_state.is_empty() and not b.social_state.is_empty() and a.social_state == b.social_state
	var detail := "first %s second %s" % [str(a.social_state), str(b.social_state)]
	a.free()
	b.free()
	if not ok: return _fail("Each lab runs its own first full pass on the same day: " + detail)
	print("SITE SOCIAL LAB LATCH PASS: two labs on one day each settle their own player body (identical packets)")
	quit(0)
