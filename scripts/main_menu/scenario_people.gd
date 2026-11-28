extends RefCounted
## 選現成人物 v1 (Nekki 2026-11-27 「都依建議」, 第六節「1.開放 2.依建議 3.清單加地圖」; plan doc 選現成人物第一版規劃):
## the people of a scenario package a new game may take over, read from the package files before any world exists.
## - 勢力首領: the head of a faction's first settlement in the scenario's office order (SiteController._scenario_head);
## - 村長: the head of every other settlement;
## - 寨主: the first member of a band's first team (SiteController._scenario_chief);
## - 隊長／軍官: the captain (first member) of every other team: settlement militia and town garrisons.
## Scenario names are unique (the generator draws each name once), so a name finds one person at birth.
## people(path) returns {ok, people: [{name, role, title, site: Vector2i, cell: Vector2i, faction_id, faction, people}],
## sites: {"x:y": {kind "settlement" | "lair" | "start", faction_id, faction}}} or {ok false, message}.

const ROLES := ["leader", "head", "chief", "captain"]
const ROLE_LABELS := {"leader": "勢力首領", "head": "村長", "chief": "寨主", "captain": "隊長與軍官"}

static func _read(path: String) -> Variant:
	if not FileAccess.file_exists(path): return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))

static func _key(pair: Variant) -> String:
	return "%d:%d" % [int(pair[0]), int(pair[1])]

static func _pair(pair: Variant) -> Vector2i:
	return Vector2i(int(pair[0]), int(pair[1]))

static func people(package_path: String) -> Dictionary:
	var manifest: Variant = _read(package_path)
	if not manifest is Dictionary or not manifest.get("files") is Array: return {"ok": false, "message": "劇本包讀不到"}
	var folder := package_path.get_base_dir()
	var scenario: Variant = null
	var initial := {}
	for entry: Variant in manifest.files:
		if not entry is Dictionary: continue
		if entry.get("kind") == "scenario": scenario = _read(folder.path_join(str(entry.path)))
		elif entry.get("kind") == "initial" and entry.get("site") is Array: initial[_key(entry.site)] = folder.path_join(str(entry.path))
	if not scenario is Dictionary: return {"ok": false, "message": "這個劇本沒有人物資料"}
	var factions := {}
	for row: Variant in scenario.get("factions", []):
		if row is Dictionary: factions[int(row.get("id", 0))] = row
	var result: Array = []
	var sites := {}
	if manifest.get("start") is Dictionary and manifest.start.get("site") is Array: sites[_key(manifest.start.site)] = {"kind": "start", "faction_id": -1, "faction": ""}
	# Settlements: their owner is the faction of their residents; the first settlement of a faction leads it.
	var led := {}
	for office: Variant in scenario.get("offices", []):
		if not office is Dictionary or not office.get("site") is Array: continue
		var key := _key(office.site)
		var state: Variant = _read(str(initial.get(key, "")))
		var residents: Array = state.get("residents", []) if state is Dictionary and state.get("residents") is Array else []
		var owner := int(state.get("settlement", {}).get("owner_faction", -1)) if state is Dictionary and state.get("settlement") is Dictionary else -1
		if owner < 0 and not residents.is_empty(): owner = int(residents[0].get("faction_id", -1))
		var faction_name := str(factions.get(owner, {}).get("name", ""))
		sites[key] = {"kind": "settlement", "faction_id": owner, "faction": faction_name}
		var head := str(office.get("head", "")).strip_edges()
		if head.is_empty(): continue
		var role := "head" if led.has(owner) else "leader"
		led[owner] = true
		var title := ("%s首領（主聚落村長）" % faction_name) if role == "leader" else ("%s第二聚落村長" % faction_name)
		result.append({"name": head, "role": role, "title": title, "site": _pair(office.site), "cell": Vector2i(-1, -1),
			"faction_id": owner, "faction": faction_name, "people": residents.size()})
	# Teams: a band's first team gives its chief, every other team a captain.
	var first_team := {}
	for team: Variant in scenario.get("teams", []):
		if not team is Dictionary or not team.get("site") is Array or not team.get("members") is Array or team.members.is_empty(): continue
		var faction_id := int(team.get("faction_id", -1))
		var faction: Dictionary = factions.get(faction_id, {})
		var faction_name := str(faction.get("name", ""))
		var key := _key(team.site)
		var bandit := str(faction.get("kind", "npc")) == "bandit"
		if bandit and not sites.has(key): sites[key] = {"kind": "lair", "faction_id": faction_id, "faction": faction_name}
		var captain := str(team.members[0].get("name", "")).strip_edges()
		if captain.is_empty(): continue
		var role := "chief" if bandit and not first_team.has(faction_id) else "captain"
		first_team[faction_id] = true
		var title := ("%s寨主" % faction_name) if role == "chief" else ("%s%s" % [faction_name, "駐軍軍官" if team.members.size() > 6 else "民兵隊長"])
		result.append({"name": captain, "role": role, "title": title, "site": _pair(team.site),
			"cell": _pair(team.get("cell", [-1, -1])), "faction_id": faction_id, "faction": faction_name, "people": team.members.size()})
	# A settlement head stands in his own house; the birth's start cell is a team cell of his Site (the militia's).
	for row: Dictionary in result:
		if row.cell.x >= 0: continue
		for other: Dictionary in result:
			if other.site == row.site and other.cell.x >= 0:
				row.cell = other.cell
				break
	result = result.filter(func(row: Dictionary) -> bool: return row.cell.x >= 0)
	var order := {"leader": 0, "head": 1, "chief": 2, "captain": 3}
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(order[a.role]) != int(order[b.role]): return int(order[a.role]) < int(order[b.role])
		if int(a.faction_id) != int(b.faction_id): return int(a.faction_id) < int(b.faction_id)
		return str(a.name) < str(b.name))
	return {"ok": true, "people": result, "sites": sites}

## The row of `name` in `package_path`'s people, or {}.
static func find(package_path: String, name: String) -> Dictionary:
	var listed := people(package_path)
	if not listed.get("ok", false): return {}
	for row: Dictionary in listed.people:
		if str(row.name) == name: return row
	return {}
