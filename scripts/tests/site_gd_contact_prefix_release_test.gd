extends SceneTree
## Pure owner-lifetime contract. No mesh/asset/world/clock behavior claim.

func _cycle() -> Dictionary:
	var data: TerrainData = TerrainData.new()
	var priors: Array = []
	var prefix: Dictionary = {"runtime_priors": priors}
	var candidate: Dictionary = {"data": data, "prefix_ref": prefix}
	priors.append(candidate)
	return {"weak": weakref(data), "published": [{"prefixes": [prefix]}]}

func _runtime_discard() -> void:
	var controller: SiteController = SiteController.new()
	var held: Dictionary = _cycle()
	var reference: WeakRef = held["weak"]
	controller._gd_contact_runtime_capture = {"published": held["published"]}
	held = {}
	assert(reference.get_ref() != null, "A discarded published segment really pins the original TerrainData before cleanup")
	controller.discard_checked_runtime_work_prefix()
	assert(reference.get_ref() == null, "Runtime owner discard releases published prefix cycles without a live current segment")
	controller.discard_checked_runtime_work_prefix()
	controller.free()

func _work_discard() -> void:
	var work: SiteWorkTeam = SiteWorkTeam.new()
	var held: Dictionary = _cycle()
	var reference: WeakRef = held["weak"]
	work._gd_contact_work_capture = {"published": held["published"]}
	held = {}
	assert(reference.get_ref() != null, "A published team-work prefix retains its actual data resource")
	work.discard_checked_work_prefix()
	assert(reference.get_ref() == null, "WorkTeam discard releases published prefix cycles before dropping its capture")
	work.discard_checked_work_prefix()

func _initialize() -> void:
	_runtime_discard()
	_work_discard()
	print("SITE_GD_CONTACT_PREFIX_RELEASE_PASS original_discard_owners_weak_lifetime_only")
	quit(0)
