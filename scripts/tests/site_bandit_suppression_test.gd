extends SceneTree
## 官方剿匪 stage 1 (Nekki 2026-11-22 B; site_bandit_suppression.gd, region_bandit.gd), pure data. Checks:
## - the expedition choice: a band at heat >= 50 whose lair is within 2 Sites; the hottest, then the nearest, then the lowest
##   id; the largest team of two or more; refused when the team is under 1.5x the band's people, when no band is in
##   reach or hot enough, when the faction sent one in the last 30 days;
## - the band table keeps `pursued` {faction: day} and `attacked_day` through validated registry commits (String keys),
##   the faction's last expedition is read across bands, and a broken `pursued` row is refused;
## - an official attack raises heat by 20 and keeps the latest day.
## Output: SITE_BANDIT_SUPPRESSION_PASS on success; quit(1) on any failure.
const Suppression = preload("res://scripts/terrain_lab/site_bandit_suppression.gd")
const Bandit = preload("res://scripts/region_lab/region_bandit.gd")

var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _ok(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_BANDIT_SUPPRESSION OK ", checks, ": ", message)
		return true
	push_error("SITE_BANDIT_SUPPRESSION_FAIL: %s %s" % [message, str(detail)])
	quit(1)
	return false

func _person(lineage: int) -> Dictionary:
	return {"type": "person", "namespace": "suppression_test", "lineage": lineage}

func _run() -> void:
	var here := "atlas:10:10"
	var teams := [{"team_id": 4, "size": 6}, {"team_id": 3, "size": 9}, {"team_id": 5, "size": 9}, {"team_id": 6, "size": 1}]
	var near := {"band": 20, "heat": 60, "lair_site": "atlas:11:10", "members": 6}
	var hotter := {"band": 21, "heat": 80, "lair_site": "atlas:12:12", "members": 5}
	var far := {"band": 22, "heat": 99, "lair_site": "atlas:13:10", "members": 1}
	var cool := {"band": 23, "heat": 49, "lair_site": "atlas:10:11", "members": 1}
	var picked := Suppression.choose(here, teams, [near, hotter, far, cool], -1, 100)
	if not _ok(int(picked.get("band", -1)) == 21 and int(picked.get("team_id", -1)) == 3 and str(picked.get("lair_site", "")) == "atlas:12:12", "the hottest band in reach, the largest team (lowest id on a tie)", picked): return
	var tie := Suppression.choose(here, teams, [near, {"band": 19, "heat": 60, "lair_site": "atlas:10:12", "members": 2}], -1, 100)
	if not _ok(int(tie.get("band", -1)) == 20, "on equal heat the nearer lair wins", tie): return
	if not _ok(str(Suppression.choose(here, teams, [far, cool], -1, 100).get("reason", "")) == "NO_BAND", "a lair 3 Sites away or a band under heat 50 is never pursued"): return
	var weak := Suppression.choose(here, [{"team_id": 4, "size": 8}], [{"band": 20, "heat": 60, "lair_site": "atlas:11:10", "members": 6}], -1, 100)
	if not _ok(str(weak.get("reason", "")) == "TOO_WEAK", "8 people do not go against 6 (needs 1.5x = 9)", weak): return
	if not _ok(int(Suppression.choose(here, [{"team_id": 4, "size": 9}], [near], -1, 100).get("team_id", -1)) == 4, "9 people go against 6"): return
	if not _ok(str(Suppression.choose(here, [{"team_id": 6, "size": 1}], [near], -1, 100).get("reason", "")) == "NO_TEAM", "a one-person team is no expedition"): return
	if not _ok(str(Suppression.choose(here, teams, [near], 71, 100).get("reason", "")) == "COOLDOWN" and Suppression.choose(here, teams, [near], 70, 100).has("band"),
		"one expedition per faction every 30 days"): return
	# Registry data: pursued / attacked_day through validated commits.
	var reg: Dictionary = {"version": 1, "revision": 0, "next_faction_id": 1, "migration_complete": true, "entries": {}, "coverage": {"complete": false, "sources": [], "counts": null}}
	var made: Dictionary = RegionFactionQuery.allocate(reg, 0, 0.0, {"name": "官", "kind": "npc", "leader_ref": _person(1)})
	reg = made.registry
	var lawful := int(made.faction_id)
	made = RegionFactionQuery.allocate(reg, int(reg.revision), 0.0, {"name": "匪", "kind": "bandit", "leader_ref": _person(2), "bandit": {"heat": 60}})
	reg = made.registry
	var band := int(made.faction_id)
	made = RegionFactionQuery.allocate(reg, int(reg.revision), 0.0, {"name": "寇", "kind": "bandit", "leader_ref": _person(3), "bandit": {"heat": 60}})
	reg = made.registry
	var other := int(made.faction_id)
	if not _ok(Suppression.last_expedition(reg, lawful) == -1, "no expedition yet"): return
	var marked: Dictionary = Bandit.pursued(reg, band, lawful, 40, 10.0)
	if not _ok(marked.ok and int(RegionFactionQuery.bandit_of(marked.registry, band).pursued[str(lawful)]) == 40, "an expedition day is kept in the band's table", marked): return
	marked = Bandit.pursued(marked.registry, other, lawful, 75, 10.0)
	if not _ok(marked.ok and Suppression.last_expedition(marked.registry, lawful) == 75, "the faction's last expedition is the latest over all bands", marked): return
	if not _ok(RegionFactionQuery.validate(marked.registry, 10.0).ok, "the registry with pursued rows validates", RegionFactionQuery.validate(marked.registry, 10.0)): return
	var hit: Dictionary = Bandit.attacked(marked.registry, band, 41, 10.0)
	if not _ok(hit.ok and int(RegionFactionQuery.bandit_of(hit.registry, band).heat) == 80 and int(RegionFactionQuery.bandit_of(hit.registry, band).attacked_day) == 41, "an official attack: heat 60 -> 80, attacked day 41", hit): return
	hit = Bandit.attacked(hit.registry, band, 39, 10.0)
	if not _ok(hit.ok and int(RegionFactionQuery.bandit_of(hit.registry, band).attacked_day) == 41 and int(RegionFactionQuery.bandit_of(hit.registry, band).heat) == 100, "an older attack day never replaces a later one (heat still rises)", hit): return
	var broken: Dictionary = hit.registry.duplicate(true)
	broken.entries[str(band)].bandit["pursued"] = {"x": 3}
	if not _ok(not RegionFactionQuery.validate(broken, 10.0).ok, "a pursued row with a non-numeric faction is refused"): return
	print("SITE_BANDIT_SUPPRESSION_PASS: ", checks, " checks")
	quit(0)
