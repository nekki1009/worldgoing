extends SceneTree
## Nobility ranks (RegionPeerage) over the faction registry, pure data. Checks:
## - founding a faction with a leader crowns the founder king (head record, no liege);
## - grant rules: a head grants any rank below emperor, others only two steps down; fief minimums;
## - liege chain, vassals, who may accept a joining team, titles;
## - emperor needs a granted king; revoke hands vassals to the revoker; inheritance passes rank, liege,
##   vassals and the head seat; a JSON round trip keeps the registry valid and canonical;
## - corrupt tables (two heads, a liege in another faction, a vassal outranking its liege) are refused;
## - a registry without the optional peerage table stays valid.
## Output: REGION_PEERAGE_PASS on success; quit(1) on any failure.

var checks := 0
const NOW := 100.0

func _initialize() -> void:
	_run.call_deferred()

func _fail(message: String, detail: Variant = null) -> void:
	printerr("REGION_PEERAGE_FAIL: ", message, " ", str(detail))
	quit(1)

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("REGION_PEERAGE OK ", checks, ": ", message)
		return true
	_fail(message, detail)
	return false

func _person(lineage: int) -> Dictionary:
	return {"type": "person", "namespace": "peerage_test_world", "lineage": lineage}

func _empty() -> Dictionary:
	return {"version": 1, "revision": 0, "next_faction_id": 1, "migration_complete": true, "entries": {}, "coverage": {"complete": false, "sources": [], "counts": null}}

func _step(result: Dictionary, message: String) -> Dictionary:
	if not _check(result.get("ok", false), message, result): return {}
	return result.registry

func _refused(result: Dictionary, code: String, message: String) -> bool:
	return _check(not result.get("ok", true) and result.get("code") == code, message, result)

func _run() -> void:
	var A := _person(1)
	var B := _person(2)
	var C := _person(3)
	var D := _person(4)
	var E := _person(5)
	var F := _person(6)
	var G := _person(7)
	var H := _person(8)
	var X := _person(9)
	var empty := _empty()
	if not _check(RegionFactionQuery.validate(empty, NOW).ok, "a registry without the peerage table is valid"): return

	var founded: Dictionary = RegionFactionQuery.allocate(empty, 0, NOW, {"name": "甲國", "kind": "player", "leader_ref": A, "founded_at": 0.0})
	if not _check(founded.ok, "founding a faction with a leader succeeds", founded): return
	var fid: int = int(founded.faction_id)
	var reg: Dictionary = founded.registry
	var head: Dictionary = RegionPeerage.record_of(reg, A)
	if not _check(head.get("rank") == "king" and head.get("liege_ref") == null and int(head.faction_id) == fid, "the founder is crowned king, head of the faction", head): return
	var head_of: Dictionary = RegionPeerage.head_of(reg, fid)
	if not _check(head_of.ok and RegionPeerage.same_ref(head_of.person_ref, A), "head_of resolves the leader", head_of): return
	if not _refused(RegionPeerage.head_of(reg, RegionFactionQuery.NEUTRAL_FACTION_ID), "NO_HEAD", "neutral has no head"): return
	var other: Dictionary = RegionFactionQuery.allocate(reg, int(reg.revision), NOW, {"name": "乙國", "kind": "npc", "leader_ref": X, "founded_at": 0.0})
	if not _check(other.ok, "a second faction with its own king", other): return
	reg = other.registry
	var other_id: int = int(other.faction_id)

	if not _refused(RegionPeerage.grant(reg, A, B, "duke", [5], NOW), "FIEF_MINIMUM", "a duke needs two cities"): return
	reg = _step(RegionPeerage.grant(reg, A, B, "duke", [5, 5], NOW), "the king grants a duke with two cities")
	if reg.is_empty(): return
	if not _refused(RegionPeerage.grant(reg, B, D, "marquis", [5], NOW), "RANK_TOO_HIGH", "a duke cannot grant a marquis (one step down)"): return
	reg = _step(RegionPeerage.grant(reg, B, C, "count", [4, 2], NOW), "the duke grants a count (two steps down)")
	if reg.is_empty(): return
	reg = _step(RegionPeerage.grant(reg, B, D, "baron", [2], NOW), "the duke grants a baron")
	if reg.is_empty(): return
	if not _refused(RegionPeerage.grant(reg, C, E, "viscount", [3], NOW), "RANK_TOO_HIGH", "a count cannot grant a viscount"): return
	reg = _step(RegionPeerage.grant(reg, C, E, "baron", [2], NOW), "the count grants a baron")
	if reg.is_empty(): return
	if not _refused(RegionPeerage.grant(reg, E, F, "baron", [2], NOW), "RANK_TOO_HIGH", "a baron grants nothing"): return
	if not _refused(RegionPeerage.grant(reg, A, X, "duke", [5, 5], NOW), "OTHER_FACTION", "another faction's king cannot be granted a title here"): return

	var vassals: Array = RegionPeerage.vassals_of(reg, B)
	if not _check(vassals.size() == 2, "the duke has two vassals", vassals): return
	var chain: Array = RegionPeerage.chain_of(reg, E)
	if not _check(chain.size() == 3 and RegionPeerage.same_ref(chain[0], C) and RegionPeerage.same_ref(chain[1], B) and RegionPeerage.same_ref(chain[2], A), "the baron's liege chain runs count, duke, king", chain): return
	if not _check(RegionPeerage.may_accept_join(reg, A) and RegionPeerage.may_accept_join(reg, C) and not RegionPeerage.may_accept_join(reg, E) and not RegionPeerage.may_accept_join(reg, F), "viscount and above accept joiners; barons and untitled people do not"): return
	var live: Dictionary = RegionPeerage.world_person_ref("w1", 42)
	if not _check(RegionFactionQuery.ref_valid(live, "person") and RegionPeerage.world_person_id(live) == 42 and RegionPeerage.world_person_id(A) == -1, "a live world person ref round-trips to its allocator id"): return
	if not _check(RegionPeerage.title("marquis", "新竹") == "新竹侯" and RegionPeerage.title("count") == "伯爵" and RegionPeerage.title("king", "甲") == "甲王", "titles read fief + rank, or the rank name"): return

	if not _refused(RegionPeerage.proclaim_emperor(reg, A, NOW), "NEEDS_KING", "an emperor needs a granted king"): return
	reg = _step(RegionPeerage.grant(reg, A, F, "king", [5, 5, 5, 5], NOW), "the king head grants a king with four cities")
	if reg.is_empty(): return
	reg = _step(RegionPeerage.proclaim_emperor(reg, A, NOW), "with a king under him the head proclaims himself emperor")
	if reg.is_empty(): return
	if not _check(RegionPeerage.record_of(reg, A).rank == "emperor", "the head is emperor"): return
	if not _refused(RegionPeerage.grant(reg, F, G, "duke", [5, 5], NOW), "RANK_TOO_HIGH", "a granted king grants only marquis and below"): return

	reg = _step(RegionPeerage.grant(reg, A, C, "marquis", [5], NOW), "the emperor promotes the count to marquis")
	if reg.is_empty(): return
	if not _check(RegionPeerage.same_ref(RegionPeerage.liege_of(reg, C), A), "a duke may not hold a marquis, so the promoted marquis serves the emperor", RegionPeerage.liege_of(reg, C)): return
	reg = _step(RegionPeerage.grant(reg, A, E, "viscount", [3], NOW), "the emperor promotes the marquis' baron to viscount")
	if reg.is_empty(): return
	if not _check(RegionPeerage.same_ref(RegionPeerage.liege_of(reg, E), C), "the marquis may still hold a viscount, so the liege is kept", RegionPeerage.liege_of(reg, E)): return

	reg = _step(RegionPeerage.revoke(reg, B, D, NOW), "the duke revokes the baron he granted")
	if reg.is_empty(): return
	if not _check(RegionPeerage.record_of(reg, D).is_empty(), "the revoked baron is untitled"): return
	reg = _step(RegionPeerage.grant(reg, B, D, "viscount", [3], NOW), "the duke grants a viscount")
	if reg.is_empty(): return
	if not _refused(RegionPeerage.revoke(reg, D, B, NOW), "NOT_LIEGE", "a vassal cannot revoke his liege"): return
	reg = _step(RegionPeerage.revoke(reg, A, B, NOW), "the emperor revokes the duke")
	if reg.is_empty(): return
	if not _check(RegionPeerage.same_ref(RegionPeerage.liege_of(reg, D), A), "the duke's vassal now serves the emperor", RegionPeerage.liege_of(reg, D)): return

	reg = _step(RegionPeerage.inherit(reg, C, G, NOW), "the marquis dies and his heir inherits")
	if reg.is_empty(): return
	var heir: Dictionary = RegionPeerage.record_of(reg, G)
	if not _check(heir.get("rank") == "marquis" and RegionPeerage.same_ref(heir.liege_ref, A) and RegionPeerage.record_of(reg, C).is_empty(), "the heir holds the rank and liege", heir): return
	if not _check(RegionPeerage.same_ref(RegionPeerage.liege_of(reg, E), G), "the dead marquis' baron now serves the heir"): return
	reg = _step(RegionPeerage.inherit(reg, E, null, NOW), "a viscount dies without heir")
	if reg.is_empty(): return
	if not _check(RegionPeerage.record_of(reg, E).is_empty(), "the title ends without heir"): return
	if not _refused(RegionPeerage.inherit(reg, A, null, NOW), "HEAD_WITHOUT_HEIR", "a head without heir is left to the faction's vacancy rules"): return
	reg = _step(RegionPeerage.inherit(reg, A, H, NOW), "the emperor dies and his heir inherits the throne")
	if reg.is_empty(): return
	if not _check(RegionPeerage.record_of(reg, H).rank == "emperor" and RegionPeerage.record_of(reg, H).liege_ref == null and RegionPeerage.same_ref(reg.entries[str(fid)].leader_ref, H), "the heir is emperor and faction leader"): return
	if not _check(RegionPeerage.same_ref(RegionPeerage.liege_of(reg, G), H) and RegionPeerage.same_ref(RegionPeerage.liege_of(reg, F), H), "the dead emperor's vassals serve the heir"): return

	var parsed: Variant = JSON.parse_string(JSON.stringify(reg))
	if not _check(parsed is Dictionary and RegionFactionQuery.validate(parsed, NOW).ok, "the registry stays valid after a JSON round trip", parsed): return
	if not _check(RegionFactionQuery.canonical_registry(parsed).peerage == reg.peerage, "the canonical peerage after JSON equals the original"): return

	var corrupt: Dictionary = reg.duplicate(true)
	corrupt.peerage[RegionPeerage.key_of(G)].liege_ref = null
	corrupt.peerage[RegionPeerage.key_of(G)].rank = "king"
	if not _check(not RegionFactionQuery.validate(corrupt, NOW).ok, "a second liegeless head is refused"): return
	corrupt = reg.duplicate(true)
	corrupt.peerage[RegionPeerage.key_of(G)].liege_ref = X
	if not _check(not RegionFactionQuery.validate(corrupt, NOW).ok, "a liege in another faction is refused"): return
	corrupt = reg.duplicate(true)
	corrupt.peerage[RegionPeerage.key_of(G)].liege_ref = F
	corrupt.peerage[RegionPeerage.key_of(G)].rank = "duke"
	if not _check(not RegionFactionQuery.validate(corrupt, NOW).ok, "a duke under a granted king (one step) is refused"): return
	if not _check(int(other_id) != fid and RegionPeerage.record_of(reg, X).get("faction_id") == other_id, "the other faction keeps its own king"): return

	print("REGION_PEERAGE_PASS: ", checks, " checks; ranks, grants, minimums, emperor, revoke, inheritance and the registry round trip hold")
	quit(0)
