class_name RegionPeerage
extends RefCounted
## Nobility ranks inside a faction (Nekki 2026-11-05, plan "勢力爵位與封地規劃").
## Pure candidates over the faction registry's optional `peerage` table; RegionSaveSlot owns publication.
## A record: {person_ref, faction_id, rank, liege_ref, granted_at}, keyed by RegionFactionQuery.ref_key(person_ref).
## - The head of a faction holds king or emperor with liege_ref null (one head record per faction).
## - Everyone else names one liege inside the same faction, of a strictly higher rank. Subordinates follow
##   the person, not the land: a lost fief keeps the rank. Teams follow their captain's liege (derived, not stored).
## - A head grants any rank below emperor; any other noble grants only ranks at least two steps below his own.
## - Fiefs are settlements whose head office the noble holds (Site data); this module only checks the minimum
##   fief levels a rank requires when it is granted. Falling below the minimum later never demotes (Nekki: 都照建議).
## "none" is an untitled sworn person (a joined captain, a retainer): it has a liege but grants nothing.
const RANKS := ["emperor", "king", "duke", "marquis", "count", "viscount", "baron", "none"]
const NAMES := {"emperor": "皇帝", "king": "王", "duke": "公爵", "marquis": "侯爵", "count": "伯爵", "viscount": "子爵", "baron": "男爵", "none": "無爵"}
const SUFFIX := {"emperor": "帝", "king": "王", "duke": "公", "marquis": "侯", "count": "伯", "viscount": "子", "baron": "男", "none": ""}
## Minimum fiefs: {settlement level, count}. Levels follow SiteRuntime.SETTLEMENT_HEAD_NAMES (2 村, 3 鄉, 4 鎮, 5 城).
const MIN_FIEFS := {"king": [5, 4], "duke": [5, 2], "marquis": [5, 1], "count": [4, 1], "viscount": [3, 1], "baron": [2, 1]}
const HEAD_RANKS := ["emperor", "king"]
const PersonPersonality = preload("res://scripts/terrain_lab/person_personality.gd")
const RECORD_FIELDS := ["person_ref", "faction_id", "rank", "liege_ref", "granted_at"]
## Viscount and above may accept a whole team joining in person.
const ACCEPT_JOIN_RANK := "viscount"

## Live people of a world are identified by the world's person allocator (RegionSaveSlot.person_reference), not by
## typed historical aliases. Their typed ref uses a world-scoped namespace so it never collides with alias lineages.
const WORLD_PERSON_NAMESPACE := "world_person:"

static func world_person_ref(world_instance_id: String, person_id: int) -> Dictionary:
	return {"type": "person", "namespace": WORLD_PERSON_NAMESPACE + world_instance_id, "lineage": person_id}

## The allocator person id behind a world person ref, or -1 for any other ref.
static func world_person_id(person_ref: Variant) -> int:
	if not RegionFactionQuery.ref_valid(person_ref, "person") or not str(person_ref.namespace).begins_with(WORLD_PERSON_NAMESPACE): return -1
	return int(person_ref.lineage)

static func fail(code: String, message: String = "") -> Dictionary:
	return {"ok": false, "code": code, "message": message}

static func rank_index(rank: Variant) -> int:
	return RANKS.find(rank) if rank is String else -1

## Lower index = higher rank.
static func outranks(a: String, b: String) -> bool:
	return rank_index(a) >= 0 and rank_index(b) >= 0 and rank_index(a) < rank_index(b)

static func key_of(person_ref: Dictionary) -> String:
	return RegionFactionQuery.ref_key(person_ref)

static func table(registry: Dictionary) -> Dictionary:
	var value: Variant = registry.get("peerage", {})
	return value if value is Dictionary else {}

static func record_of(registry: Dictionary, person_ref: Variant) -> Dictionary:
	if not RegionFactionQuery.ref_valid(person_ref, "person"): return {}
	return table(registry).get(key_of(person_ref), {})

static func canonical_ref(value: Variant) -> Variant:
	if not value is Dictionary: return value
	var copy: Dictionary = value.duplicate(true)
	if copy.get("lineage") is float: copy.lineage = int(copy.lineage)
	return copy

## JSON-loaded refs carry float lineages; one canonical int form keeps equality and digests stable.
static func canonical(peerage: Dictionary) -> Dictionary:
	var result := {}
	for key: Variant in peerage:
		var record: Variant = peerage[key]
		if not record is Dictionary:
			result[key] = record
			continue
		var copy: Dictionary = record.duplicate(true)
		copy.person_ref = canonical_ref(copy.get("person_ref"))
		copy.liege_ref = canonical_ref(copy.get("liege_ref"))
		if copy.get("faction_id") is float: copy.faction_id = int(copy.faction_id)
		if copy.get("granted_at") is int: copy.granted_at = float(copy.granted_at)
		if copy.get("fiefs") is Dictionary:
			for site_id: Variant in copy.fiefs:
				if copy.fiefs[site_id] is float: copy.fiefs[site_id] = int(copy.fiefs[site_id])
		result[key] = copy
	return result

static func same_ref(a: Variant, b: Variant) -> bool:
	return RegionFactionQuery.ref_valid(a, "person") and RegionFactionQuery.ref_valid(b, "person") and key_of(a) == key_of(b)

## May `granter` (a record) hand out `rank`? A head grants any lower rank; others need a two-step gap.
static func may_grant(granter: Dictionary, rank: String) -> bool:
	if rank_index(rank) < 0 or granter.is_empty(): return false
	# A head (king or emperor) may grant any rank below emperor, kings included: a king head needs a granted
	# king before he can proclaim himself emperor.
	if granter.liege_ref == null: return rank != "emperor"
	return rank_index(rank) - rank_index(str(granter.rank)) >= 2

## May `liege` (a record) hold a vassal of `rank`? Untitled sworn people need a liege who may accept joiners.
static func may_hold(liege: Dictionary, rank: String) -> bool:
	if rank == "none": return not liege.is_empty() and (liege.liege_ref == null or rank_index(str(liege.rank)) <= rank_index(ACCEPT_JOIN_RANK))
	return may_grant(liege, rank)

## `levels` = the settlement levels of every fief the person will hold.
static func meets_minimum(rank: String, levels: Array) -> bool:
	if not MIN_FIEFS.has(rank): return true
	var need: Array = MIN_FIEFS[rank]
	var count := 0
	for level: Variant in levels:
		if (level is int or level is float) and int(level) >= int(need[0]): count += 1
	return count >= int(need[1])

## Structural rules of the whole table against the registry's faction entries.
static func validate(peerage: Variant, registry: Dictionary, now: float) -> Dictionary:
	if not peerage is Dictionary: return fail("CORRUPT_SAVE", "peerage table")
	var heads := {}
	for key: Variant in peerage:
		var record: Variant = peerage[key]
		if not key is String or not record is Dictionary: return fail("CORRUPT_SAVE", "peerage record fields")
		var fields: Array = RECORD_FIELDS.duplicate()
		if record.has("fiefs"): fields.append("fiefs")
		if not RegionFactionQuery.keys(record, fields): return fail("CORRUPT_SAVE", "peerage record fields")
		if record.has("fiefs"):
			if not record.fiefs is Dictionary: return fail("CORRUPT_SAVE", "peerage fiefs")
			for site_id: Variant in record.fiefs:
				if not site_id is String or str(site_id).is_empty() or not RegionFactionQuery.whole(record.fiefs[site_id], 2, 5): return fail("CORRUPT_SAVE", "peerage fief level")
		if not RegionFactionQuery.ref_valid(record.person_ref, "person") or key_of(record.person_ref) != key: return fail("CORRUPT_SAVE", "peerage person ref")
		if rank_index(record.rank) < 0: return fail("CORRUPT_SAVE", "peerage rank")
		if not RegionFactionQuery.whole(record.faction_id, 0, RegionFactionQuery.MAX_ID) or int(record.faction_id) == RegionFactionQuery.NEUTRAL_FACTION_ID: return fail("CORRUPT_SAVE", "peerage faction")
		var entry: Dictionary = registry.get("entries", {}).get(str(int(record.faction_id)), {})
		if entry.get("status") != "active": return fail("CORRUPT_SAVE", "peerage faction not active")
		if not (record.granted_at is int or record.granted_at is float) or not is_finite(float(record.granted_at)) or float(record.granted_at) < 0.0 or float(record.granted_at) > now: return fail("CORRUPT_SAVE", "peerage time")
		if record.liege_ref == null:
			if record.rank not in HEAD_RANKS: return fail("CORRUPT_SAVE", "a liegeless noble must be the head")
			if entry.leader_ref != null and not same_ref(entry.leader_ref, record.person_ref): return fail("CORRUPT_SAVE", "head record is not the faction leader")
			if heads.has(str(int(record.faction_id))): return fail("CORRUPT_SAVE", "two heads in one faction")
			heads[str(int(record.faction_id))] = true
			continue
		if record.rank in HEAD_RANKS and record.rank == "emperor": return fail("CORRUPT_SAVE", "only a head is emperor")
		if not RegionFactionQuery.ref_valid(record.liege_ref, "person") or same_ref(record.liege_ref, record.person_ref): return fail("CORRUPT_SAVE", "peerage liege ref")
		var liege: Variant = peerage.get(key_of(record.liege_ref))
		if not liege is Dictionary or int(liege.get("faction_id", -1)) != int(record.faction_id): return fail("CORRUPT_SAVE", "liege outside the faction")
		if not may_hold(liege, str(record.rank)): return fail("CORRUPT_SAVE", "liege may not hold this vassal rank")
	return {"ok": true}

## The faction head's person ref from the registry. A nation-bound faction's head lives in the nation's
## offices (Site/party data), which the caller resolves itself.
static func head_of(registry: Dictionary, faction_id: int) -> Dictionary:
	var resolved: Dictionary = RegionFactionQuery.active(registry, faction_id)
	if not resolved.ok: return resolved
	if faction_id == RegionFactionQuery.NEUTRAL_FACTION_ID: return fail("NO_HEAD", "中立沒有首長")
	if resolved.entry.leader_ref != null: return {"ok": true, "faction_id": int(resolved.faction_id), "person_ref": canonical_ref(resolved.entry.leader_ref)}
	if resolved.entry.nation_ref != null: return {"ok": true, "faction_id": int(resolved.faction_id), "person_ref": null, "nation_ref": canonical_ref(resolved.entry.nation_ref)}
	return fail("NO_HEAD", "勢力沒有首長")

## The person's liege ref; null for a head or an untitled person.
static func liege_of(registry: Dictionary, person_ref: Variant) -> Variant:
	var record: Dictionary = record_of(registry, person_ref)
	return canonical_ref(record.liege_ref) if not record.is_empty() and record.liege_ref != null else null

## Liege chain from the person upwards, ending at the head (person excluded).
static func chain_of(registry: Dictionary, person_ref: Variant) -> Array:
	var chain: Array = []
	var current: Variant = liege_of(registry, person_ref)
	while current != null and chain.size() <= RANKS.size():
		chain.append(current)
		current = liege_of(registry, current)
	return chain

static func vassals_of(registry: Dictionary, person_ref: Variant) -> Array:
	var result: Array = []
	if not RegionFactionQuery.ref_valid(person_ref, "person"): return result
	for record: Dictionary in table(registry).values():
		if record.liege_ref != null and same_ref(record.liege_ref, person_ref): result.append(canonical_ref(record.person_ref))
	return result

static func may_accept_join(registry: Dictionary, person_ref: Variant) -> bool:
	var record: Dictionary = record_of(registry, person_ref)
	return not record.is_empty() and rank_index(str(record.rank)) <= rank_index(ACCEPT_JOIN_RANK)

## Title for display: fief name + suffix ("新竹侯"), or the rank name without a fief.
static func title(rank: String, fief_name: String = "") -> String:
	if rank_index(rank) < 0: return ""
	return fief_name + SUFFIX[rank] if not fief_name.strip_edges().is_empty() else NAMES[rank]

static func _candidate(registry: Dictionary) -> Dictionary:
	var candidate: Dictionary = registry.duplicate(true)
	candidate.peerage = canonical(table(candidate))
	candidate.revision = int(candidate.get("revision", 0)) + 1
	return candidate

static func _finish(candidate: Dictionary, now: float) -> Dictionary:
	var checked: Dictionary = RegionFactionQuery.validate(candidate, now)
	if not checked.ok: return checked
	return {"ok": true, "registry": candidate}

## The founder of a faction becomes its king.
static func crown_founder(registry: Dictionary, faction_id: int, person_ref: Dictionary, now: float) -> Dictionary:
	var head: Dictionary = head_of(registry, faction_id)
	if not head.ok: return head
	if not same_ref(head.get("person_ref"), person_ref): return fail("NOT_HEAD", "只有勢力首長能稱王")
	if not record_of(registry, person_ref).is_empty(): return fail("ALREADY_TITLED", "此人已有爵位")
	var candidate := _candidate(registry)
	candidate.peerage[key_of(person_ref)] = {"person_ref": canonical_ref(person_ref), "faction_id": faction_id, "rank": "king", "liege_ref": null, "granted_at": now}
	return _finish(candidate, now)

## A king head with at least one granted king under him may proclaim himself emperor.
static func proclaim_emperor(registry: Dictionary, person_ref: Dictionary, now: float) -> Dictionary:
	var record: Dictionary = record_of(registry, person_ref)
	if record.is_empty() or record.liege_ref != null or record.rank != "king": return fail("NOT_HEAD", "只有稱王的首長能稱帝")
	var kings := 0
	for vassal: Variant in vassals_of(registry, person_ref):
		if record_of(registry, vassal).get("rank") == "king": kings += 1
	if kings < 1: return fail("NEEDS_KING", "麾下至少要有一位受封的王才能稱帝")
	var candidate := _candidate(registry)
	candidate.peerage[key_of(person_ref)].rank = "emperor"
	return _finish(candidate, now)

## Grant (or promote to) `rank`. `fief_levels` = settlement levels of every fief the grantee will hold.
static func grant(registry: Dictionary, granter_ref: Dictionary, person_ref: Dictionary, rank: String, fief_levels: Array, now: float) -> Dictionary:
	var granter: Dictionary = record_of(registry, granter_ref)
	if granter.is_empty(): return fail("NOT_NOBLE", "授爵者沒有爵位")
	if same_ref(granter_ref, person_ref): return fail("SELF_GRANT", "不能授爵給自己")
	if rank == "none": return fail("NOT_PROMOTION", "無爵不是授予的爵位；投靠用宣誓效忠")
	if not may_grant(granter, rank): return fail("RANK_TOO_HIGH", "%s不能授予%s" % [NAMES[granter.rank], NAMES.get(rank, rank)])
	if not meets_minimum(rank, fief_levels): return fail("FIEF_MINIMUM", "%s至少要有 %d 座%s以上的封地" % [NAMES[rank], int(MIN_FIEFS[rank][1]), SiteRuntime.SETTLEMENT_HEAD_NAMES.get(int(MIN_FIEFS[rank][0]), "")])
	var existing: Dictionary = record_of(registry, person_ref)
	if not existing.is_empty():
		if int(existing.faction_id) != int(granter.faction_id): return fail("OTHER_FACTION", "此人屬於別的勢力")
		if existing.liege_ref == null: return fail("IS_HEAD", "不能授爵給首長")
		if not outranks(rank, str(existing.rank)): return fail("NOT_PROMOTION", "只能升爵，不能用授爵降等")
		if granter.liege_ref != null and not same_ref(existing.liege_ref, granter_ref): return fail("NOT_LIEGE", "只能升自己部下的爵")
		for vassal: Variant in vassals_of(registry, person_ref):
			if not outranks(rank, str(record_of(registry, vassal).rank)): return fail("RANK_TOO_HIGH", "部下的爵位不能高於上級")
	# A head promoting someone else's vassal keeps that liege when the liege may still hold the new rank.
	var liege: Variant = canonical_ref(granter_ref)
	if not existing.is_empty() and existing.liege_ref != null and may_grant(record_of(registry, existing.liege_ref), rank): liege = canonical_ref(existing.liege_ref)
	var candidate := _candidate(registry)
	candidate.peerage[key_of(person_ref)] = {"person_ref": canonical_ref(person_ref), "faction_id": int(granter.faction_id), "rank": rank, "liege_ref": liege, "granted_at": now}
	if existing.has("fiefs"): candidate.peerage[key_of(person_ref)]["fiefs"] = existing.fiefs.duplicate(true)
	return _finish(candidate, now)

## Remove the record of `person_ref` and hand its vassals to `successor` (a ref, or null for "the old liege").
static func _remove(candidate: Dictionary, person_ref: Dictionary, successor: Variant) -> void:
	var removed: Dictionary = candidate.peerage[key_of(person_ref)]
	var heir_ref: Variant = successor if successor != null else removed.liege_ref
	candidate.peerage.erase(key_of(person_ref))
	for key: String in candidate.peerage:
		var record: Dictionary = candidate.peerage[key]
		if record.liege_ref != null and same_ref(record.liege_ref, person_ref): record.liege_ref = canonical_ref(heir_ref)

## Revoke: the head may revoke anyone; a noble only what he granted. Vassals pass to the revoker.
static func revoke(registry: Dictionary, revoker_ref: Dictionary, person_ref: Dictionary, now: float) -> Dictionary:
	var revoker: Dictionary = record_of(registry, revoker_ref)
	var target: Dictionary = record_of(registry, person_ref)
	if revoker.is_empty() or target.is_empty() or int(revoker.faction_id) != int(target.faction_id): return fail("NOT_NOBLE", "雙方須是同勢力的貴族")
	if target.liege_ref == null: return fail("IS_HEAD", "不能削首長的爵")
	if revoker.liege_ref != null and not same_ref(target.liege_ref, revoker_ref): return fail("NOT_LIEGE", "只能削自己授出的爵")
	var candidate := _candidate(registry)
	_remove(candidate, person_ref, canonical_ref(revoker_ref))
	return _finish(candidate, now)

## Hereditary titles follow the family rule: `heir_ref` (from family succession) takes rank, liege and vassals.
## With no heir the record ends and its vassals pass to the old liege. A dead head's heir also becomes the
## faction leader; a faction left without heir keeps its leader ref for the caller's own vacancy rules.
static func inherit(registry: Dictionary, dead_ref: Dictionary, heir_ref: Variant, now: float) -> Dictionary:
	var dead: Dictionary = record_of(registry, dead_ref)
	if dead.is_empty(): return fail("NOT_NOBLE", "此人沒有爵位")
	var candidate := _candidate(registry)
	if heir_ref == null:
		if dead.liege_ref == null:
			# A head without heir: vassals stay, sworn to an empty head seat until the faction's vacancy rules fill it.
			return fail("HEAD_WITHOUT_HEIR", "首長無人繼承")
		_remove(candidate, dead_ref, null)
		return _finish(candidate, now)
	if not RegionFactionQuery.ref_valid(heir_ref, "person") or same_ref(heir_ref, dead_ref): return fail("INVALID_HEIR")
	var held: Dictionary = record_of(registry, heir_ref)
	if not held.is_empty() and int(held.faction_id) != int(dead.faction_id): return fail("OTHER_FACTION", "繼承人屬於別的勢力")
	# The heir keeps the higher of the two titles, with that title's own liege; both vassal sets follow the heir.
	var rank: String = str(dead.rank)
	var liege: Variant = dead.liege_ref
	if not held.is_empty() and not outranks(rank, str(held.rank)):
		rank = str(held.rank)
		liege = held.liege_ref
	if not held.is_empty(): _remove(candidate, heir_ref, canonical_ref(heir_ref))
	_remove(candidate, dead_ref, canonical_ref(heir_ref))
	candidate.peerage[key_of(heir_ref)] = {"person_ref": canonical_ref(heir_ref), "faction_id": int(dead.faction_id), "rank": rank, "liege_ref": canonical_ref(liege), "granted_at": now}
	# Fiefs are re-indexed from each Site's head seat; the heir keeps the ones he already held.
	if held.has("fiefs"): candidate.peerage[key_of(heir_ref)]["fiefs"] = held.fiefs.duplicate(true)
	if dead.liege_ref == null:
		var entry: Dictionary = candidate.entries[str(int(dead.faction_id))]
		if entry.leader_ref != null: entry.leader_ref = canonical_ref(heir_ref)
	return _finish(candidate, now)

## An untitled person swears fealty to `acceptor` (the head, or viscount and above) on joining in person.
static func swear(registry: Dictionary, acceptor_ref: Dictionary, person_ref: Dictionary, now: float) -> Dictionary:
	var acceptor: Dictionary = record_of(registry, acceptor_ref)
	if not may_hold(acceptor, "none"): return fail("NOT_ACCEPTOR", "只有首長或子爵以上的貴族能收投靠")
	if same_ref(acceptor_ref, person_ref): return fail("SELF_GRANT")
	if not record_of(registry, person_ref).is_empty(): return fail("ALREADY_SWORN", "此人已效忠某勢力")
	var candidate := _candidate(registry)
	candidate.peerage[key_of(person_ref)] = {"person_ref": canonical_ref(person_ref), "faction_id": int(acceptor.faction_id), "rank": "none", "liege_ref": canonical_ref(acceptor_ref), "granted_at": now}
	return _finish(candidate, now)

## --- Joining in person (Nekki 2026-11-05 03:28, formulas agreed) ---
const ACCEPT_THRESHOLD := 50.0
const FOLLOW_THRESHOLD := 55.0

## Personality distance 0..100: mean absolute difference over the ten axes (missing packet = neutral).
static func personality_distance(a: Variant, b: Variant) -> float:
	var left: Dictionary = PersonPersonality.read(a)
	var right: Dictionary = PersonPersonality.read(b)
	var total := 0.0
	for axis: String in PersonPersonality.AXES: total += absf(float(left[axis]) - float(right[axis]))
	return total / float(PersonPersonality.AXES.size())

## (100 - dist(official, player)) x 0.5 + official ambition x 0.3 + min(1, team size / faction people here) x 20; >= 50 accepts.
static func accept_score(official: Variant, player: Variant, team_size: int, faction_people_here: int) -> float:
	var ratio: float = 1.0 if faction_people_here <= 0 else minf(1.0, float(team_size) / float(faction_people_here))
	return (100.0 - personality_distance(official, player)) * 0.5 + float(PersonPersonality.read(official).ambition) * 0.3 + ratio * 20.0

## (100 - dist(cadre, acceptor)) x 0.6 + (100 - dist(cadre, player)) x 0.4; with no acceptor only the player counts (weight 1).
## >= 55 follows.
static func follow_score(cadre: Variant, acceptor: Variant, player: Variant) -> float:
	var to_player: float = 100.0 - personality_distance(cadre, player)
	if acceptor == null: return to_player
	return (100.0 - personality_distance(cadre, acceptor)) * 0.6 + to_player * 0.4

## --- Fiefs (step 3) ---
## A fief is a Site's settlement (level 2 村 .. 5 城) whose head seat a titled noble holds. The Site is the truth; each
## record keeps `fiefs` {site_id: level} as the world-wide index, reconciled from a Site whenever it is checkpointed.

static func fiefs_of(registry: Dictionary, person_ref: Variant) -> Dictionary:
	return record_of(registry, person_ref).get("fiefs", {})

static func fief_levels(registry: Dictionary, person_ref: Variant) -> Array:
	return fiefs_of(registry, person_ref).values()

## Re-index one Site: the site leaves every record, then joins the holder's record when the holder is sworn into the
## settlement's faction (titled or not: an untitled head's settlement counts toward his first title) and the settlement is at least a village. Returns {ok, registry, changed}.
static func reconcile_site(registry: Dictionary, site_id: String, level: int, holder_ref: Variant, owner_faction: int, now: float) -> Dictionary:
	if not registry.get("peerage") is Dictionary or site_id.is_empty(): return {"ok": true, "registry": registry, "changed": false}
	var candidate: Dictionary = registry.duplicate(true)
	candidate.peerage = canonical(candidate.peerage)
	var before: Dictionary = candidate.peerage.duplicate(true)
	for key: String in candidate.peerage:
		var record: Dictionary = candidate.peerage[key]
		if record.get("fiefs", {}).has(site_id):
			record.fiefs.erase(site_id)
			if record.fiefs.is_empty(): record.erase("fiefs")
	if level >= 2 and RegionFactionQuery.ref_valid(holder_ref, "person"):
		var holder: Variant = candidate.peerage.get(key_of(holder_ref))
		if holder is Dictionary and int(holder.faction_id) == owner_faction:
			var fiefs: Dictionary = holder.get("fiefs", {})
			fiefs[site_id] = mini(level, 5)
			holder["fiefs"] = fiefs
	if candidate.peerage == before: return {"ok": true, "registry": registry, "changed": false}
	candidate.revision = int(candidate.get("revision", 0)) + 1
	var checked: Dictionary = RegionFactionQuery.validate(candidate, now)
	if not checked.ok: return checked
	return {"ok": true, "registry": candidate, "changed": true}
