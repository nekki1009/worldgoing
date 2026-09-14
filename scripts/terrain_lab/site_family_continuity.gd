extends RefCounted
## References and death-only control continuity, never another person's body.
## Original SiteStore loads and the Lab's control/bind transaction are injected
## so Store can reuse validate_family without a circular preload dependency.

const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
var lab: Variant
var load_site_query: Callable # (path) -> original SiteStore.load_site result.
var archive_current: Callable # () -> guarded original snapshot/save result.
var control_selected: Callable # (validated_data_or_null, identity) -> atomic Lab result.
var _seen_death: Array = []

func init(scene: Variant) -> void:
	lab = scene
	_seen_death.clear()

static func _integer(value: Variant, lower: int, upper: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= lower and float(value) <= upper and float(value) == floorf(float(value))

static func validate_family(value: Variant) -> bool:
	if not value is Dictionary or value.size() != 3 or not _integer(value.get("version"), 1, 1) or not value.get("complete") is bool or not value.get("members") is Array:
		return false
	var seen := {}
	for member: Variant in value.members:
		if not member is Dictionary or member.size() != 5 or not member.get("site_id") is String or str(member.site_id).is_empty() or not member.get("path") is String or not member.get("label") is String:
			return false
		if not _integer(member.get("person_id"), 1, 2147483647) or int(member.person_id) == 1000000000 or not _integer(member.get("age_years"), -1, 200):
			return false
		var key := [str(member.site_id), int(member.person_id)]
		if seen.has(key):
			return false
		seen[key] = true
	return true

func _controlled_id() -> int:
	return int(lab.terrain.site.get("controlled_person_id", lab.character.person_id))

func _current_person(identity: int) -> Dictionary:
	var person: Dictionary = lab._combat_target(identity)
	if person.is_empty():
		return {}
	var body: Variant = person.owner.combat_units[int(person.unit)] if int(person.unit) >= 0 else person.owner
	return {"hp": float(person.hp), "captive": bool(body.get("captive")),
		"ko": float(body.get("ko") if int(person.unit) >= 0 else body.knockout_left),
		"kind": "army" if int(person.unit) >= 0 else "actor"}

static func _saved_person(data: TerrainData, identity: int) -> Dictionary:
	for actor: Dictionary in data.site.get("actors", {}).values():
		if int(actor.person_id) == identity:
			return {"hp": float(actor.hp), "captive": bool(actor.captive), "ko": float(actor.knockout_left), "kind": "actor"}
	for team: Dictionary in data.site.get("armies", []):
		for row: Dictionary in team.units:
			if int(row.person_id) == identity:
				return {"hp": float(row.hp), "captive": bool(row.captive), "ko": float(row.ko), "kind": "army"}
	return {}

func _source(site_reference: Dictionary) -> Dictionary:
	if str(site_reference.site_id) == str(lab.terrain.site.id):
		return Runtime.ok("", {"data": lab.terrain, "local": true})
	if str(site_reference.path).is_empty() or not load_site_query.is_valid():
		return Runtime.fail("NO_SOURCE", "異地人物尚無可讀取的原 Site 快照")
	var result: Dictionary = load_site_query.call(str(site_reference.path))
	if not bool(result.get("ok", false)):
		return result
	if not result.get("data") is TerrainData or str(result.data.site.get("id", "")) != str(site_reference.site_id):
		return Runtime.fail("STALE_SITE", "快照不是該家人的原 Site；未替換目前場景")
	return Runtime.ok("", {"data": result.data, "local": false})

func _observation(member_reference: Dictionary, source: Dictionary) -> Dictionary:
	var result := member_reference.duplicate(true)
	result.merge({"status": "UNKNOWN", "selectable": false, "message": "", "kind": ""})
	if not bool(source.get("ok", false)):
		result.message = str(source.get("message", "原人物資料不可讀取"))
		result.code = str(source.get("code", "NO_SOURCE"))
		return result
	var person := _current_person(int(member_reference.person_id)) if bool(source.local) else _saved_person(source.data, int(member_reference.person_id))
	if person.is_empty():
		result.message = "已驗證快照中找不到原人物；不視為死亡"
		result.code = "NO_PERSON"
		return result
	result.merge(person)
	result.status = "ALIVE" if float(person.hp) > 0.0 else "DEAD"
	result.selectable = float(person.hp) > 0.0 and not (str(member_reference.site_id) == str(lab.terrain.site.id) and int(member_reference.person_id) == _controlled_id())
	result.code = "OK"
	return result

func _inspect_family(family: Dictionary) -> Dictionary:
	var observations: Array = []
	var groups := {}
	for member: Dictionary in family.members:
		var key := [str(member.site_id), str(member.path)]
		if not groups.has(key):
			groups[key] = []
		groups[key].append(member)
	var living := 0
	var unknown := 0
	# Explicit panel refresh/registration only, never death_tick or 120 Hz.
	# One validated Site at a time; don't retain full remote maps as a family DB.
	for references: Array in groups.values():
		var source := _source(references[0])
		for member_reference: Dictionary in references:
			var observation := _observation(member_reference, source)
			observations.append(observation)
			var self_reference: bool = str(member_reference.site_id) == str(lab.terrain.site.id) and int(member_reference.person_id) == _controlled_id()
			if not self_reference:
				living += int(str(observation.status) == "ALIVE")
				unknown += int(str(observation.status) == "UNKNOWN")
	var current := _current_person(_controlled_id())
	var dead := not current.is_empty() and float(current.hp) <= 0.0
	var status := "ALIVE" if not dead else "CHOOSE"
	if current.is_empty():
		status = "DATA_MISSING"
	elif dead and living == 0:
		status = "GAME_OVER" if bool(family.complete) and unknown == 0 else "DATA_MISSING"
	return Runtime.ok("", {"status": status, "complete": bool(family.complete), "members": observations,
		"living_relatives": living, "unknown_relatives": unknown, "controlled_person_id": _controlled_id()})

func inspect() -> Dictionary:
	if not lab.terrain.site.has("family"):
		return Runtime.ok("家族尚未登錄；不能據此判定無人在世", {"status": "UNREGISTERED", "members": [], "complete": false})
	var family: Variant = lab.terrain.site.family
	if not validate_family(family):
		return Runtime.fail("INVALID_FAMILY", "家族引用名單無效；未改變控制人物")
	return _inspect_family(family)

func register_members(members: Array, complete: bool) -> Dictionary:
	# Called only by an explicit user registration UI. Never infer kinship from
	# factions, proximity, node names, or a newly spawned demonstration roster.
	var family := {"version": 1, "complete": complete, "members": members.duplicate(true)}
	if not validate_family(family):
		return Runtime.fail("INVALID_FAMILY", "請登錄不重複的原 Site／人物引用；未知年齡填 -1")
	var checked := _inspect_family(family)
	for member: Dictionary in checked.members:
		if str(member.status) == "UNKNOWN":
			return Runtime.fail(str(member.code), "無法確認原人物，不會新增虛構家人：" + str(member.message))
	lab.terrain.site.family = family
	return Runtime.ok("已明確登錄既有人物；沒有建立人物、親屬身體或財物")

func death_tick() -> Dictionary:
	var identity := _controlled_id()
	var person := _current_person(identity)
	if person.is_empty():
		return Runtime.fail("NO_CONTROL_OWNER", "受控原人物不存在；不視為死亡或 Game Over")
	if float(person.hp) > 0.0:
		_seen_death.clear()
		return Runtime.ok("", {"status": "ALIVE", "changed": false, "person_id": identity})
	var key := [str(lab.terrain.site.id), identity]
	var changed := _seen_death != key
	_seen_death = key
	# Root pauses the selection UI after original committed death work settles.
	# No offline catch-up, forced combat-clock reset, or implicit second clock.
	return Runtime.ok("原受控人物已死亡", {"status": "DEAD", "changed": changed, "person_id": identity})

func choose(site_id: String, identity: int) -> Dictionary:
	var current := _current_person(_controlled_id())
	if current.is_empty() or float(current.hp) > 0.0:
		return Runtime.fail("NOT_DEAD", "只有原受控人物真正死亡後才能接續；昏迷或被俘不適用")
	var family: Variant = lab.terrain.site.get("family")
	if not validate_family(family):
		return Runtime.fail("INVALID_FAMILY", "家族未登錄或資料不足；保留目前人物")
	var selected := {}
	for member: Dictionary in family.members:
		if str(member.site_id) == site_id and int(member.person_id) == identity:
			selected = member
			break
	if selected.is_empty() or (site_id == str(lab.terrain.site.id) and identity == _controlled_id()):
		return Runtime.fail("NO_HEIR", "請選擇已明確登錄的另一位原家人")
	var source := _source(selected)
	if not source.ok:
		return source
	var observation := _observation(selected, source)
	if str(observation.status) != "ALIVE":
		return Runtime.fail("NO_HEIR", "原家人已死亡或資料不足；不製造新的接續人物")
	if not control_selected.is_valid():
		return Runtime.fail("UNSUPPORTED", "尚未接好原人物控制入口")
	if not bool(source.local):
		if not archive_current.is_valid():
			return Runtime.fail("UNSUPPORTED", "尚未接好原 Site 的安全歸檔入口")
		var saved: Dictionary = archive_current.call()
		if not bool(saved.get("ok", false)):
			return saved # Including BUSY: selection stays; never delete old remains.
		# Carry only the explicit reference registry, not old HP/cargo/office data.
		source.data.site.family = family.duplicate(true)
	return control_selected.call(null if bool(source.local) else source.data, identity)
