extends SceneTree
## Author-map worlds (world_pin format 3, P5B) carry the same fixed technology policy as new worlds (format 2), and the
## work preflight reads it (found 2026-11-26: format 3 was refused as INVALID_TECH_POLICY, so in a scenario world nobody
## could do any work on a live Site; only the coarse catch-up, which does not ask, produced). Data only.

var checks := 0

func _initialize() -> void:
	_run()

func _ok(condition: bool, message: String, detail: Variant = null) -> bool:
	if condition:
		checks += 1
		return true
	push_error("SITE_AUTHOR_WORLD_POLICY_FAIL: %s %s" % [message, JSON.stringify(detail) if detail != null else ""])
	quit(1)
	return false

func _data(pin: Variant) -> TerrainData:
	var data := TerrainData.new()
	data.site = {} if pin == null else {"world_pin": pin}
	return data

func _run() -> void:
	var policy := {"version": 1, "rules_version": 1, "categories": ["F04", "F06", "F11", "F12"]}
	var author: Dictionary = SiteRuntime._technology_policy(_data({"format": 3, "world_instance_id": "w", "slot_id": "main", "technology_policy": policy}))
	if not _ok(author.get("ok", false) and author.policy.categories.size() == 4 and not bool(author.get("legacy", true)), "an author world's policy is read", author): return
	var new_world: Dictionary = SiteRuntime._technology_policy(_data({"format": 2, "technology_policy": policy}))
	if not _ok(new_world.get("ok", false), "a new world's policy is read", new_world): return
	if not _ok(SiteRuntime._technology_policy(_data({"format": 1})).get("legacy", false), "an old world has the empty legacy policy"): return
	if not _ok(SiteRuntime._technology_policy(_data(null)).get("ok", false), "a Site without a world has the empty policy"): return
	for wrong: Variant in [{"format": 3}, {"format": 4, "technology_policy": policy}, {"format": 2}, {"format": 3, "technology_policy": {"version": 1}}, "x"]:
		if not _ok(not SiteRuntime._technology_policy(_data(wrong)).get("ok", true), "refused: %s" % JSON.stringify(wrong)): return
	print("SITE_AUTHOR_WORLD_POLICY_PASS: ", checks, " checks")
	quit(0)
