class_name SiteEquipmentOrders
extends RefCounted
## Pure national requirements plus one actual-holder transaction provider.
## SitePersonActions owns all timing, cancellation and post-contact submission.

const CrowdOwner = preload("res://scripts/terrain_lab/crowd_person_owner.gd")
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Visual = preload("res://scripts/ui/human_character_3d_editor.gd")
const CULTURES := {"chinese": "中式", "japanese": "日式", "western": "西式"}
const Technology = preload("res://scripts/terrain_lab/site_technology.gd")
const Settlement = preload("res://scripts/terrain_lab/site_settlement.gd")
const Stockpiles = preload("res://scripts/terrain_lab/site_stockpiles.gd")
const RansomData = preload("res://scripts/terrain_lab/site_ransom_data.gd")
const Succession = preload("res://scripts/terrain_lab/site_succession.gd")
const NATION_OPERATIONS_VERSION := 1
const NATION_OPERATIONS_MAX := 128
const NATION_PUBLIC_VERSION := 2
const PUBLIC_TECHNOLOGIES := ["N02", "N03", "N06", "N07", "N08", "N09", "N10", "N11", "N12"]
const PUBLIC_DUTIES := {"N02": "nation.labor", "N03": "nation.relief", "N06": "nation.public_works", "N07": "nation.education",
	"N08": "nation.transport", "N09": "nation.finance", "N10": "nation.administration", "N11": "nation.arsenal", "N12": "nation.fleet"}
const PUBLIC_BINDINGS := {"N02": ["labor_register", "road_build"], "N03": ["aid_order"], "N06": ["house_build", "public_works"], "N07": ["funded_course"],
	"N08": ["public_route"], "N09": ["tax"], "N10": ["mandate", "road_build"], "N11": ["ballista_build", "iron_armor", "arsenal"], "N12": ["fleet"]}

var lab: Variant
var _actions_ref: WeakRef
var actions: Variant:
	get: return _actions_ref.get_ref() if _actions_ref != null else null
	set(value): _actions_ref = weakref(value) if value != null else null
var equipment_apply_guard: Callable # (original person_id, final slot->item ID map), pure.
var equipment_team_apply_guard: Callable # (person_id, final slots) -> result with full appearance; pure.
var equipment_team_external_duty_guard: Callable # (person_id) -> bool; original work/delivery/vehicle owners.
var equipment_dye_guard: Callable # (person_id, requested dye changes), pure.
var nation_build_request: Callable # Original Settlement blueprint + bounded source + WorkTeam; (nation_id, order_id, order, preview).
var nation_course_request: Callable # Original PA single teacher/student job; (nation_id, order_id, teacher, student, technology_id).
var nation_route_query: Callable # Original Region registered route projection; (route_id, destination_site, vehicle_id, driver_id, destination_holder).
var nation_route_request: Callable # Original Controller/Region travel; (nation_id, order_id, order).
var nation_owner_receipt_query: Callable # Pure ORIGINAL owner receipt lookup; (binding, target_id, event_id), never an acceptance bool.
var nation_arsenal_request: Callable # Original Runtime yard/workshop paid order; (nation_id, order_id, order, preview).

func init(owner: Variant, person_actions: RefCounted) -> void:
	lab = owner
	actions = person_actions
	actions.equipment_orders = self
	if actions.has_method("_rebind_scope_technology_sources") and is_same(actions.lab, lab): actions._rebind_scope_technology_sources()
	# No nation, membership, office or gear is created as a side effect.

func set_nation_culture(requester_id: int, nation_id: String, culture: String) -> Dictionary:
	var nation: Dictionary = lab.terrain.site.get("equipment_nations", {}).get(nation_id, {})
	if not _nation_duty_ok(requester_id, nation, "nation.culture"):
		return _nation_refusal(requester_id, nation, "nation.culture", "只有本國清醒自由的真實軍事首長可首次設定國家裝備文化")
	if not CULTURES.has(culture):
		return Runtime.fail("INVALID", "國家裝備文化須為中式、日式或西式")
	if nation.has("culture"):
		return Runtime.fail("NO_CHANGE" if nation.culture == culture else "CULTURE_FIXED", "本國裝備文化已固定；不更改現役裝備或持物")
	for standard: Dictionary in nation.standards.values():
		if not _slots_match_culture(standard.slots, lab.terrain.site.item_definitions, culture):
			return Runtime.fail("CULTURE_MISMATCH", "既有標準或替代物含其他文化；請先明確修訂標準，再固定國家文化，原物品未改")
	nation.culture = culture
	return Runtime.ok("本國裝備文化已固定為%s；材質可混搭，原持物及現役裝備未變" % CULTURES[culture])

func _can_set_standard(requester_id: int, nation: Dictionary) -> bool:
	return _nation_duty_ok(requester_id, nation, "nation.equip_standard")

func _nation_person_ok(nation: Dictionary, person_id: int) -> bool:
	var person: Dictionary = lab._combat_target(person_id)
	if is_remote_organization_person(lab.terrain.site, person_id): return false
	if nation.is_empty() or not _member(nation, person_id) or person.is_empty() or float(person.hp) <= 0.0:
		return false
	return person.owner.combat_can_act(int(person.unit)) if int(person.unit) >= 0 else person.owner.can_act()

## Nation offices (OFFICE_POSITIONS_AND_DUTIES_PLAN 6.3). A record without
## `offices` is a legacy record: its military_head keeps all three equipment
## duties and the head seat is vacant; it is migrated on its first head appointment.
## A versioned record made before a later duty existed gains that duty's vacant
## seat (head acting, plan 3.2) here, on every path, as the Region paths already
## do: stored with one revision step, or on a copy when read_only.
static func nation_offices(nation: Dictionary, read_only: bool = false) -> Dictionary:
	if nation.has("offices"):
		if not nation.offices is Dictionary or read_only and not SiteOffices.validate(nation.offices, "nation"): return {}
		var current: Dictionary = nation.offices
		if read_only and (int(current.get("version", SiteOffices.VERSION)) < SiteOffices.VERSION or not _catalog_complete(current)): current = current.duplicate(true)
		SiteOffices.upgrade(current)
		if SiteOffices.ensure_catalog(current, "nation") and not read_only:
			current.revision = mini(SiteOffices.MAX_SEQ, int(current.revision) + 1)
		return current
	return SiteOffices.legacy_nation_offices(int(nation.get("military_head", -1)))

static func _catalog_complete(offices: Dictionary) -> bool:
	for duty_id: String in SiteOffices.duty_ids("nation"):
		if not offices.duties.has(duty_id): return false
	return true

## Read-only derivation for existing callers; never stored beside offices.
static func military_head(nation: Dictionary) -> int:
	if not nation.has("offices"): return int(nation.get("military_head", -1))
	var offices: Dictionary = nation.offices
	var holder := int(SiteOffices.position(offices, str(offices.duties.get("nation.equip_standard", ""))).get("holder", -1))
	return holder if holder > 0 else int(SiteOffices.head_position(offices).get("holder", -1))

static func office_holders(nation: Dictionary) -> Array[int]:
	var result: Array[int] = []
	for seat: Dictionary in nation_offices(nation).positions:
		if int(seat.holder) > 0: result.append(int(seat.holder))
	return result

func nation_head_executor(nation: Dictionary, read_only: bool = false) -> int:
	var head := int(SiteOffices.head_position(nation_offices(nation, read_only)).get("holder", -1))
	return head if head > 0 and _nation_person_ok(nation, head) else -1

func nation_duty_resolve(nation: Dictionary, duty_id: String, read_only: bool = false) -> Dictionary:
	return SiteOffices.resolve(nation_offices(nation, read_only), duty_id, nation_head_executor(nation, read_only),
		func(person_id: int) -> bool: return _nation_person_ok(nation, person_id))

func _nation_duty_ok(requester_id: int, nation: Dictionary, duty_id: String, read_only: bool = false) -> bool:
	if nation.is_empty() or requester_id <= 0: return false
	var resolved := nation_duty_resolve(nation, duty_id, read_only)
	return bool(resolved.ok) and int(resolved.decider) == requester_id

func _nation_refusal(requester_id: int, nation: Dictionary, duty_id: String, legacy_message: String) -> Dictionary:
	if nation.is_empty() or not nation.has("offices"): return Runtime.fail("NO_AUTHORITY", legacy_message)
	return SiteOffices.refusal(nation_duty_resolve(nation, duty_id), requester_id, nation.offices)

## Scenario-explicit head setting (B0 "succession defined elsewhere"); not a
## player or AI path. Migrates a legacy record without changing who holds the
## three equipment duties.
func appoint_nation_head(nation_id: String, person_id: int) -> Dictionary:
	var nation: Dictionary = lab.terrain.site.get("equipment_nations", {}).get(nation_id, {})
	if nation.is_empty() or person_id <= 0 or not _member(nation, person_id):
		return Runtime.fail("NO_TARGET", "元首須是本國真實國民")
	var offices := nation_offices(nation).duplicate(true)
	SiteOffices.ensure_catalog(offices, "nation") # A migrated legacy record is stored complete (same single revision step).
	var seat := SiteOffices.position_of(offices, person_id)
	if not seat.is_empty() and not bool(seat.head):
		return Runtime.fail("DUPLICATE_HOLDER", "同一人在同一組織最多擔任一個職位；請先由人事方案卸任")
	SiteOffices.head_position(offices).holder = person_id
	offices.revision = int(offices.revision) + 1
	nation.erase("military_head")
	nation.offices = offices
	return Runtime.ok("已設定元首", {"revision": int(offices.revision)})

## Organization adjustment is the head's own, non-delegable power (3.5).
func apply_nation_office_plan(requester_id: int, nation_id: String, expected_revision: int, ops: Array) -> Dictionary:
	var nation: Dictionary = lab.terrain.site.get("equipment_nations", {}).get(nation_id, {})
	if nation.is_empty() or not nation.has("offices") or requester_id != nation_head_executor(nation):
		return Runtime.fail("NO_AUTHORITY", "只有清醒自由的本國元首可調整國家職位")
	var result := SiteOffices.apply_plan(nation.offices, "nation", expected_revision, ops,
		func(person_id: int, _office_class: String) -> bool: return _member(nation, person_id))
	if not bool(result.ok): return result
	nation.offices = result.offices
	return Runtime.ok("已套用國家人事方案", {"revision": int(nation.offices.revision), "refs": result.refs})

func set_nation_duty_ai(requester_id: int, nation_id: String, enabled: bool) -> Dictionary:
	var nation: Dictionary = lab.terrain.site.get("equipment_nations", {}).get(nation_id, {})
	if nation.is_empty() or not nation.has("offices") or requester_id != nation_head_executor(nation):
		return Runtime.fail("NO_AUTHORITY", "職責 AI 開關屬元首的組織設定")
	nation.offices.duty_ai = enabled
	return Runtime.ok("已%s國家職責 AI" % ("開啟" if enabled else "關閉"))

## R4b-1 (OFFICE R4): the 贖務官 (nation.ransom) binds the nation's own treasury to one
## complete warehouse it owns. Binding only: no coin moves, nothing is paid or released.
func bind_nation_treasury(requester_id: int, nation_id: String, feature_id: String) -> Dictionary:
	var nation: Dictionary = lab.terrain.site.get("equipment_nations", {}).get(nation_id, {})
	if nation.is_empty() or not nation.has("offices"): return Runtime.fail("NO_TARGET", "須為已建立職位的正式國家")
	var resolved: Dictionary = nation_duty_resolve(nation, "nation.ransom", true)
	if not bool(resolved.ok) or int(resolved.decider) != requester_id: return SiteOffices.refusal(resolved, requester_id, nation.offices)
	var candidate: Dictionary = RansomData.bind_candidate(lab.terrain.site, nation_id, nation, feature_id)
	if not bool(candidate.ok): return Runtime.fail(str(candidate.code), "國庫綁定未通過，原狀未變")
	nation_offices(nation) # Stores the complete seat list (one revision step) only after authority is proven.
	nation.ransom_data = candidate.nation.ransom_data
	lab.terrain.site.stockpiles[feature_id].nation_id = nation_id
	return Runtime.ok("已綁定本國國庫；硬幣仍在原倉，未付款", {"feature_id": feature_id})

## R4b-1: the 贖務官 sets the per-person / daily / reserve ceilings. Numbers only.
func set_nation_ransom_policy(requester_id: int, nation_id: String, per_person: int, daily: int, reserve: int) -> Dictionary:
	var nation: Dictionary = lab.terrain.site.get("equipment_nations", {}).get(nation_id, {})
	if nation.is_empty() or not nation.has("offices"): return Runtime.fail("NO_TARGET", "須為已建立職位的正式國家")
	var resolved: Dictionary = nation_duty_resolve(nation, "nation.ransom", true)
	if not bool(resolved.ok) or int(resolved.decider) != requester_id: return SiteOffices.refusal(resolved, requester_id, nation.offices)
	var candidate: Dictionary = RansomData.policy_candidate(lab.terrain.site, nation_id, nation, per_person, daily, reserve)
	if not bool(candidate.ok): return Runtime.fail(str(candidate.code), "國庫政策未通過，原狀未變")
	nation_offices(nation)
	nation.ransom_data = candidate.nation.ransom_data
	return Runtime.ok("已更新贖金政策上限", {"per_person": per_person, "daily": daily, "reserve": reserve})


## R4b-2: the 贖務官 authorizes (or revokes) payer-side ransom spending for the nation's own bound treasury.
## Authorization only; coin stays in the warehouse and no captive is released.
func authorize_nation_ransom(requester_id: int, nation_id: String, authorized: bool) -> Dictionary:
	var nation: Dictionary = lab.terrain.site.get("equipment_nations", {}).get(nation_id, {})
	if nation.is_empty() or not nation.has("offices"): return Runtime.fail("NO_TARGET", "須為已建立職位的正式國家")
	var resolved: Dictionary = nation_duty_resolve(nation, "nation.ransom", true)
	if not bool(resolved.ok) or int(resolved.decider) != requester_id: return SiteOffices.refusal(resolved, requester_id, nation.offices)
	var candidate: Dictionary = RansomData.authorize_candidate(lab.terrain.site, nation_id, nation, requester_id, authorized)
	if not bool(candidate.ok): return Runtime.fail(str(candidate.code), "國庫授權未通過，原狀未變")
	nation_offices(nation)
	nation.ransom_data = candidate.nation.ransom_data
	return Runtime.ok("已%s本國贖金付款授權；未付款、未移動硬幣、未解除拘押" % ("授權" if authorized else "撤銷"), {"authorized": authorized})


## R5 S1: the head executor designates the nation's heir. Data only: no holder changes, no transfer.
func designate_nation_heir(requester_id: int, nation_id: String, person_id: int) -> Dictionary:
	var nation: Dictionary = lab.terrain.site.get("equipment_nations", {}).get(nation_id, {})
	if nation.is_empty() or not nation.has("offices") or requester_id != nation_head_executor(nation, true):
		return Runtime.fail("NO_AUTHORITY", "只有清醒自由的本國元首可指定繼承人")
	var head_seat: Dictionary = SiteOffices.head_position(nation.offices)
	if head_seat.is_empty(): return Runtime.fail("NO_TARGET", "元首職位不存在")
	var seat_ids: Array = [str(head_seat.id)]
	var members := {}
	for member: Variant in nation.members: members[int(member)] = true
	var record: Dictionary = nation.get("succession", Succession.empty_record())
	var candidate: Dictionary = Succession.designate(record, str(head_seat.id), person_id, seat_ids, members, int(head_seat.get("holder", -1)), func(identity: int) -> bool: return _nation_person_ok(nation, identity))
	if not bool(candidate.ok): return Runtime.fail(str(candidate.code), "繼承人指定未通過；原狀未變")
	nation_offices(nation)
	nation.offices.revision = mini(SiteOffices.MAX_SEQ, int(nation.offices.revision) + 1)
	nation.succession = candidate.record
	return Runtime.ok("已指定繼承人", {"person_id": person_id})

func set_standard(requester_id: int, nation_id: String, standard_id: String, display_name: String, slots: Dictionary, dyes: Variant = null) -> Dictionary:
	var nation: Dictionary = lab.terrain.site.get("equipment_nations", {}).get(nation_id, {})
	if not _can_set_standard(requester_id, nation):
		return _nation_refusal(requester_id, nation, "nation.equip_standard", "只有本國清醒自由的真實軍事首長可改標準；玩家或隊長不自動有權")
	var normalized := slots.duplicate(true)
	for slot: Variant in normalized:
		if normalized[slot] is Dictionary and not normalized[slot].has("alternatives"):
			normalized[slot]["alternatives"] = [] # Default means no substitution, never a random fallback.
	if not _valid_key(nation_id) or not _valid_key(standard_id) or display_name.is_empty() or display_name.length() > 128 or not _valid_slots(normalized, lab.terrain.site.item_definitions):
		return Runtime.fail("INVALID", "標準名称／同槽位物品定義或替代清單不合法")
	if nation.has("culture") and not _slots_match_culture(normalized, lab.terrain.site.item_definitions, str(nation.culture)):
		return Runtime.fail("CULTURE_MISMATCH", "主要裝備與全部替代物須符合本國固定文化；材質不受限制，原標準未改")
	var previous: Dictionary = nation.standards.get(standard_id, {})
	var palette: Variant = previous.get("equipment_dyes", {}) if dyes == null else dyes
	var player_head: bool = bool(actions._person(requester_id, false).get("player", false))
	# NPC choice happens once when authoring a new standard, never on load/control change.
	if dyes == null and previous.is_empty() and not player_head:
		palette = npc_palette_id(nation_id.hash())
	if palette is String:
		if not Runtime.EquipmentDye.PRESETS.has(palette):
			return Runtime.fail("INVALID", "未知的十六組配色")
		palette = Runtime.EquipmentDye.PRESETS[palette].colors
	if not Runtime.EquipmentDye.valid_dyes(palette):
		return Runtime.fail("INVALID", "國別五部位配色")
	if dyes != null and not player_head and not _is_preset(palette):
		return Runtime.fail("INVALID", "NPC 首長從十六組配色選用；玩家首長可自由配色")
	var revision := int(previous.get("revision", 0)) + 1
	if revision >= 2147483647:
		return Runtime.fail("INVALID", "標準提交版本已達上限")
	nation.standards[standard_id] = {"name": display_name, "revision": revision, "slots": normalized}
	if not palette.is_empty():
		nation.standards[standard_id].equipment_dyes = palette.duplicate()
	return Runtime.ok("已更新未來領裝需求；現役實装未變")

func dye_person(requester_id: int, identity: int, changes: Dictionary) -> Dictionary:
	var crowd_guard: Dictionary = actions.crowd_action_guard([requester_id, identity])
	if not crowd_guard.ok:
		return crowd_guard
	if actions.is_busy(identity) or actions.is_busy(requester_id):
		return Runtime.fail("BUSY", "先完成或取消原人物換裝／作業")
	var person: Dictionary = actions._person(identity)
	var ready := _ready(person)
	if not ready.ok:
		return ready
	var requester: Dictionary = actions._person(requester_id)
	if not _ready(requester).ok:
		return Runtime.fail("NO_AUTHORITY", "染色操作者須可行動")
	var authorized := requester_id == identity and bool(person.player)
	for nation: Dictionary in lab.terrain.site.get("equipment_nations", {}).values():
		if _member(nation, identity) and _nation_duty_ok(requester_id, nation, "nation.dye"):
			authorized = true
	if not authorized:
		return Runtime.fail("NO_AUTHORITY", "限原玩家本人，或本國軍事首長套用本國人物配色")
	if not bool(requester.player) and not _npc_dyes_allowed(requester_id, person, changes):
		return Runtime.fail("INVALID", "NPC 須套用完整預設或本國已保存的標準配色")
	var version := int(person.holder.version)
	var checked := Runtime.dye_equipment(lab.terrain, person.holder, changes, version, true)
	if not checked.ok:
		return checked
	if not equipment_dye_guard.is_valid() or not actions.equipment_changed.is_valid():
		return Runtime.fail("UNSUPPORTED", "染色呈現尚未接入")
	checked = equipment_dye_guard.call(identity, changes)
	if not checked.ok:
		return checked
	var result := Runtime.dye_equipment(lab.terrain, person.holder, changes, version)
	if result.ok:
		actions.equipment_changed.call(identity)
	return result

func apply_standard_dyes(requester_id: int, identity: int, nation_id: String, standard_id: String) -> Dictionary:
	var standard := _standard(identity, nation_id, standard_id)
	if standard.is_empty() or not standard.has("equipment_dyes"):
		return Runtime.fail("NO_TARGET", "沒有此國別配色")
	var person: Dictionary = actions._person(identity)
	if person.is_empty():
		return Runtime.fail("NO_TARGET")
	return dye_person(requester_id, identity, _equipped_dyes(person, standard.equipment_dyes))

static func npc_palette_id(selection: int) -> String:
	return str(Runtime.EquipmentDye.PRESETS.keys()[posmod(selection, Runtime.EquipmentDye.PRESETS.size())])

static func _is_preset(colors: Dictionary) -> bool:
	for preset: Dictionary in Runtime.EquipmentDye.PRESETS.values():
		if colors == preset.colors: return true
	return false

func _npc_dyes_allowed(requester_id: int, person: Dictionary, changes: Dictionary) -> bool:
	for preset: Dictionary in Runtime.EquipmentDye.PRESETS.values():
		if changes == _equipped_dyes(person, preset.colors): return true
	# Retain player-authored standards after succession; this is application, not new authorship.
	for nation: Dictionary in lab.terrain.site.get("equipment_nations", {}).values():
		if _member(nation, int(person.person_id)) and _nation_duty_ok(requester_id, nation, "nation.dye"):
			for standard: Dictionary in nation.standards.values():
				if standard.has("equipment_dyes") and changes == _equipped_dyes(person, standard.equipment_dyes): return true
	return false

static func _equipped_dyes(person: Dictionary, colors: Dictionary) -> Dictionary:
	var changes := {}
	for slot: String in colors:
		if person.holder.equipped.has(slot): changes[slot] = colors[slot]
	return changes

func begin_issue(identity: int, nation_id: String, standard_id: String) -> Dictionary:
	return actions.begin_equipment(identity, {"mode": "issue", "nation_id": nation_id, "standard_id": standard_id})

func begin_team_issue(team: TerrainArmy, requester_id: int, representative_id: int, nation_id: String, standard_id: String, include_player: bool = false, selected_ids: Array[int] = [], simulate_npc_commander: bool = false) -> Dictionary:
	return actions.begin_team_equipment(team, requester_id, representative_id, nation_id, standard_id, include_player, selected_ids, simulate_npc_commander)

func begin_personal(identity: int, slot: String, item_id: String) -> Dictionary:
	return actions.begin_equipment(identity, {"mode": "personal", "slot": slot, "item_id": item_id})

func nation_grants_cape(identity: int) -> bool:
	for nation: Dictionary in lab.terrain.site.get("equipment_nations", {}).values():
		if military_head(nation) == identity and _member(nation, identity):
			return true
	return false

static func _team_grants_cape(team: TerrainArmy, index: int) -> bool:
	return team.combat_enabled and team.is_member(index) and not team.member_gone(index) and \
		rank_grants_cape(index, team.formal_commander, team.officer_service, team.officer_order)

static func rank_grants_cape(index: int, formal: int, _service: Array, officers: Array) -> bool:
	# Temporary command authority is not an appointment or an end of service.
	# R1b: the cape follows the captaincy and the 武官 succession order; a 文官
	# post (cadre in service only) never grants it (v2 plan §3.5).
	return index >= 0 and (index == formal or officers.has(index))

func cape_role_allowed(identity: int) -> bool:
	var person: Dictionary = actions._person(identity, false)
	if person.is_empty() or float(person.hp) <= 0.0:
		return false
	if nation_grants_cape(identity):
		return true
	if person.owner is CrowdOwner:
		return person.owner.cape_role_allowed(int(person.unit))
	if int(person.unit) >= 0 and person.owner.military_role(int(person.unit)) == "officer": return true
	if int(person.unit) < 0 and person.owner is TerrainTestCharacter and person.owner.military_role == "officer": return true
	if int(person.unit) >= 0:
		return _team_grants_cape(person.owner, int(person.unit))
	# Original actors can hold PLAYER_MEMBER in an Army. Control and remembered
	# command abilities themselves confer no office or clothing permission.
	for team: TerrainArmy in lab.combat_armies:
		if _team_grants_cape(team, team.index_for_identity(identity)):
			return true
	return false

func cape_wear_guard(identity: int, equipped: Dictionary) -> Dictionary:
	if equipped.has("cape") and not cape_role_allowed(identity):
		return Runtime.fail("CAPE_ROLE_RESTRICTED", "披風僅限具資格軍官、在任幹部、正式隊長或本國軍事首長；控制人物或歷史能力不授予資格")
	return Runtime.ok()

func retire_capes(identities: Array[int], preview: bool = false) -> Dictionary:
	# Explicit initialization/personnel reconciliation, not a clothing getter or
	# a player action. Keep every real item in the same original holder/backpack.
	var pending: Array[Dictionary] = []
	var seen := {}
	for identity: int in identities:
		if seen.has(identity): continue
		seen[identity] = true
		var person: Dictionary = actions._person(identity)
		if person.is_empty(): return Runtime.fail("NO_TARGET", "披風原持有人資料未就緒")
		if not person.holder.equipped.has("cape"): continue
		var planned: Dictionary = person.holder.equipped.duplicate()
		planned.erase("cape")
		var order := {"mode": "retire_cape", "person_id": identity, "person_version": int(person.holder.version),
			"before": person.holder.equipped.duplicate(), "planned": planned, "take": [], "return": []}
		var checked := check(order)
		if not checked.ok: return checked
		pending.append(order)
	if not preview:
		# No yields or transfers between preflight and commit; each order still
		# rechecks its original version, capacity and strict visual admission.
		for order: Dictionary in pending:
			var result := commit(order)
			assert(result.ok)
	return Runtime.ok("披風保留在本人行囊；原物品、所有權及染色未變")

func prepare(identity: int, request: Dictionary) -> Dictionary:
	var person: Dictionary = actions._person(identity)
	var ready := _ready(person)
	if not ready.ok:
		return ready
	var mode := str(request.get("mode", ""))
	var before: Dictionary = person.holder.equipped.duplicate()
	var planned := before.duplicate()
	var order := {"mode": mode, "person_id": identity, "person_version": int(person.holder.version),
		"before": before, "planned": planned, "take": [], "return": []}
	var military_products: Array[String] = []
	if request.has("military_production_id"):
		if mode != "issue" or not request.military_production_id is String: return Runtime.fail("INVALID")
		var nation: Dictionary = lab.terrain.site.get("equipment_nations", {}).get(str(request.get("nation_id", "")), {})
		if not nation.has("technology_operations") or not valid_nation_operation_record(nation.technology_operations, lab.terrain.site.item_definitions, {}): return Runtime.fail("STALE_ORDER")
		var production: Dictionary = nation.technology_operations.orders.get(request.military_production_id, {})
		if production.is_empty() or production.status != "complete" or int(production.recipient_id) != identity or production.standard_id != request.get("standard_id"): return Runtime.fail("STALE_ORDER")
		military_products = _military_order_products(production)
		if military_products.size() != 1: return Runtime.fail("MATERIALS")
		order.military_production_id = request.military_production_id
	if mode == "personal":
		if not bool(person.player):
			return Runtime.fail("NO_AUTHORITY", "個人自由換装只接受原玩家本人合法持物")
		var slot := str(request.get("slot", ""))
		var identity_to_wear := str(request.get("item_id", ""))
		if slot.is_empty() or slot.length() > 64:
			return Runtime.fail("INVALID", "裝備槽")
		if not identity_to_wear.is_empty():
			if not person.holder.item_ids.has(identity_to_wear) or person.holder.equipped.values().has(identity_to_wear):
				return Runtime.fail("NO_TARGET", "只能穿戴本人實際持有且尚未穿戴的物品")
			var definition := _held_definition(identity_to_wear, str(person.holder.holder))
			if definition.is_empty() or str(definition.slot) != slot:
				return Runtime.fail("INVALID", "物品不屬於本人或槽位不合")
		planned.erase(slot)
		if not identity_to_wear.is_empty():
			planned[slot] = identity_to_wear
	elif mode == "issue":
		var nation_id := str(request.get("nation_id", ""))
		var standard_id := str(request.get("standard_id", ""))
		var standard := _standard(identity, nation_id, standard_id)
		if standard.is_empty():
			return Runtime.fail("NO_AUTHORITY", "缺少本人真實國別或該國正式標準")
		if not _at_depot(person):
			return Runtime.fail("UNREACHABLE", "本人須停止於原補給點相鄰可達格")
		var depot: Dictionary = lab.terrain.site.depot_items
		order.merge({"nation_id": nation_id, "standard_id": standard_id,
			"standard_revision": int(standard.revision), "depot_version": int(depot.version)})
		for slot: String in standard.slots:
			var requirement: Dictionary = standard.slots[slot]
			var candidates: Array = [str(requirement.definition)] + requirement.alternatives
			var selected := ""
			for definition_id: String in candidates:
				var current_id := str(before.get(slot, ""))
				if not current_id.is_empty() and (slot != "weapon" or military_products.is_empty()) and str(lab.terrain.site.item_records.get(current_id, {}).get("definition", "")) == definition_id:
					selected = current_id
					break
				for item_id: String in depot.item_ids:
					if slot == "weapon" and not military_products.is_empty() and not military_products.has(item_id): continue
					var record: Dictionary = lab.terrain.site.item_records.get(item_id, {})
					if str(record.get("definition", "")) == definition_id and str(record.get("holder", "")) == "depot" and not order.take.has(item_id):
						selected = item_id
						break
				if not selected.is_empty():
					break
			if selected.is_empty():
				return Runtime.fail("MATERIALS", "缺少標準槽位 %s；原裝全部保留，不發模板物品" % slot)
			if selected != str(before.get(slot, "")):
				order.take.append(selected)
				if before.has(slot):
					order["return"].append(str(before[slot]))
				planned[slot] = selected
	else:
		return Runtime.fail("INVALID", "領裝模式")
	var cape_guard := cape_wear_guard(identity, planned)
	if not cape_guard.ok:
		return cape_guard
	if planned == before:
		return Runtime.fail("NO_CHANGE", "原實装已符合本次要求")
	var checked := check(order)
	if str(checked.get("code", "")) == "ATLAS_REQUIRED":
		checked.order = order # Same validated request; no new selection after preparation.
	return Runtime.ok("可執行原人物換裝", {"order": order}) if checked.ok else checked

func prepare_team_issue(team: TerrainArmy, requester_id: int, representative_id: int, nation_id: String, standard_id: String, include_player: bool = false, selected_ids: Array[int] = [], simulate_npc_commander: bool = false) -> Dictionary:
	if simulate_npc_commander and not nation_id.begins_with("trial_team_"):
		return Runtime.fail("NO_AUTHORITY", "NPC 指揮模擬僅限明示的測試國別")
	var context := _team_issue_context(team, requester_id, representative_id, include_player, selected_ids, {}, simulate_npc_commander)
	if not context.ok: return context
	var target_ids: Array[int] = context.target_ids
	var standard := _standard(target_ids[0], nation_id, standard_id)
	if standard.is_empty(): return Runtime.fail("NO_AUTHORITY", "目標未全數屬於本國，或該國沒有正式標準")
	var nation: Dictionary = lab.terrain.site.equipment_nations[nation_id]
	var culture := str(nation.get("culture", ""))
	if not _slots_match_culture(standard.slots, lab.terrain.site.item_definitions, culture):
		return Runtime.fail("CULTURE_REQUIRED" if culture.is_empty() else "CULTURE_MISMATCH", "先由原軍事首長設定本國裝備文化")
	var depot: Dictionary = lab.terrain.site.depot_items
	if not Runtime._item_holder_shape(depot) or str(depot.holder) != "depot":
		return Runtime.fail("INVALID", "原補給點持物資料不合法")
	var representative: Dictionary = actions._person(representative_id)
	var requester: Dictionary = actions._person(requester_id)
	var order := {"mode": "team_issue", "terrain": lab.terrain, "site_state": lab.terrain.site,
		"team": team, "team_id": int(team.team_id), "requester_id": requester_id,
		"controlled_id": int(lab.controlled_person_id()),
		"requester_owner": requester.owner, "requester_body": requester.body,
		"requester_cell": lab.terrain.index(requester.cell), "requester_hit": int(requester.hit),
		"representative_id": representative_id, "include_player": include_player,
		"simulate_npc_commander": simulate_npc_commander,
		"representative_owner": representative.owner, "representative_body": representative.body,
		"representative_holder": representative.holder, "representative_cargo": representative.cargo,
		"representative_cell": lab.terrain.index(representative.cell), "representative_hit": int(representative.hit),
		"representative_version": int(representative.holder.version),
		"roster_ids": context.roster_ids, "target_ids": target_ids.duplicate(),
		"nation_id": nation_id, "nation_ref": nation, "standard_id": standard_id,
		"standard_ref": standard, "standard_revision": int(standard.revision),
		"standard_slots": standard.slots.duplicate(true), "culture": culture,
		"depot_holder": depot, "depot_stock": lab.terrain.site.inventory,
		"depot_stock_before": lab.terrain.site.inventory.duplicate(true),
		"records_owner": lab.terrain.site.item_records, "definitions_owner": lab.terrain.site.item_definitions,
		"depot_version": int(depot.version), "depot_ids": depot.item_ids.duplicate(),
		"entries": [], "take": [], "return": [], "records": {}}
	var assigned := {}
	var missing: Array[Dictionary] = []
	for identity: int in target_ids:
		var person: Dictionary = actions._person(identity)
		var before: Dictionary = person.holder.equipped.duplicate()
		var entry := {"person_id": identity, "owner": person.owner, "body": person.body,
			"holder": person.holder, "cargo": person.cargo, "holder_version": int(person.holder.version),
			"holder_ids": person.holder.item_ids.duplicate(), "cargo_before": person.cargo.duplicate(true),
			"cell": lab.terrain.index(person.cell), "hit": int(person.hit),
			"before": before, "planned": before.duplicate(), "take": [], "return": []}
		order.entries.append(entry)
		for slot: String in standard.slots:
			var requirement: Dictionary = standard.slots[slot]
			var candidates: Array = [str(requirement.definition)] + requirement.alternatives
			var current := str(before.get(slot, ""))
			var current_definition := _held_definition(current, str(person.holder.holder)) if not current.is_empty() else {}
			if not current_definition.is_empty() and str(current_definition.slot) == slot and candidates.has(str(lab.terrain.site.item_records[current].definition)):
				if assigned.has(current): return Runtime.fail("INVALID", "同一原物品被兩人重複穿戴")
				assigned[current] = true
			else:
				missing.append({"entry": entry, "slot": slot, "candidates": candidates})
	# Reserve all already compliant real equipment before assigning any depot item.
	var shortages: Array[String] = []
	for needed: Dictionary in missing:
		var chosen := ""
		for definition_id: String in needed.candidates:
			for item_id: String in depot.item_ids:
				if assigned.has(item_id): continue
				var definition := _held_definition(item_id, "depot")
				if not definition.is_empty() and str(lab.terrain.site.item_records[item_id].definition) == definition_id:
					chosen = item_id
					break
			if not chosen.is_empty(): break
		if chosen.is_empty():
			shortages.append("#%d %s" % [int(needed.entry.person_id), str(needed.slot)])
			continue
		assigned[chosen] = true
		needed.entry.planned[needed.slot] = chosen
		needed.entry.take.append(chosen)
		order.take.append(chosen)
		if needed.entry.before.has(needed.slot):
			var old_id := str(needed.entry.before[needed.slot])
			needed.entry["return"].append(old_id)
			order["return"].append(old_id)
	if not shortages.is_empty():
		var missing_result := Runtime.fail("MATERIALS", "缺少原實物：%s；全隊原裝保留" % ", ".join(shortages))
		missing_result.missing = shortages
		return missing_result
	var changed_ids: Array[int] = []
	for entry: Dictionary in order.entries:
		if entry.planned != entry.before: changed_ids.append(int(entry.person_id))
	if changed_ids.is_empty(): return Runtime.fail("NO_CHANGE", "全隊原實裝已符合本次標準")
	for entry: Dictionary in order.entries:
		for item_id: String in entry.before.values() + entry.planned.values():
			order.records[item_id] = lab.terrain.site.item_records.get(item_id, {}).duplicate(true)
	var checked := check_team_issue(order)
	if not checked.ok and str(checked.get("code", "")) != "ATLAS_REQUIRED": return checked
	checked.order = order
	checked.target_ids = target_ids.duplicate()
	checked.changed_ids = changed_ids
	checked.take_count = order.take.size()
	checked.return_count = order["return"].size()
	return checked

## F08: cancelling a team re-equip job re-checks the canceller now. The current
## controlled person may cancel it if they hold 整隊領裝 for that team now (or act
## for its head), or if they are the representative aborting their own job. A
## window left over after a handover, a control change or a Site switch cannot
## cancel someone else's job.
func cancel_team_issue(requester_id: int, representative_id: int) -> Dictionary:
	var job: Dictionary = actions.job_for(representative_id)
	if job.is_empty() or str(job.get("kind", "")) != "equipment" or str(job.get("order", {}).get("mode", "")) != "team_issue":
		return Runtime.fail("NO_TARGET", "沒有此代表的整隊換裝作業")
	if requester_id != lab.controlled_person_id():
		return Runtime.fail("NO_AUTHORITY", "只有目前受控人物可取消整隊換裝")
	if requester_id != representative_id:
		var team: Variant = job.order.get("team")
		if not team is TerrainArmy or not is_instance_valid(team) or not lab.combat_armies.has(team) or not is_same(team.data, lab.terrain) \
			or not is_same(job.order.get("terrain"), lab.terrain):
			return Runtime.fail("NO_TARGET", "原隊伍或 Site 已失效")
		var refused: Dictionary = team.duty_authority("team.equip", requester_id)
		if not refused.is_empty(): return refused
	return actions.cancel(representative_id)

func _team_issue_context(team: TerrainArmy, requester_id: int, representative_id: int, include_player: bool, selected_ids: Array[int], order: Dictionary = {}, simulate_npc_commander: bool = false) -> Dictionary:
	if not is_instance_valid(lab) or team == null or not is_instance_valid(team) or not lab.combat_armies.has(team) or not team.combat_enabled or not is_same(team.data, lab.terrain):
		return Runtime.fail("NO_TARGET", "原隊伍或 Site 已失效")
	if bool(lab.terrain.site.get("paused", false)) or lab is Node and lab.is_inside_tree() and lab.get_tree().paused or float(lab.terrain.site.get("combat_left", 0.0)) > 0.0:
		return Runtime.fail("BUSY", "暫停或交戰中不能整隊領裝")
	if team.combat_order != TerrainArmy.CombatOrder.HOLD or team.moving_member_count() > 0 or lab is TerrainLab and is_instance_valid(lab.site_controller) and not lab.site_controller._team_stopped(team):
		return Runtime.fail("BUSY", "原隊伍須 HOLD 並全員停止")
	var requester_index := team.index_for_identity(requester_id)
	var npc_trial: bool = simulate_npc_commander and requester_id != lab.controlled_person_id() and not actions._person(requester_id, false).is_empty()
	if (requester_id != lab.controlled_person_id() and not npc_trial) or requester_index < 0:
		return Runtime.fail("NO_AUTHORITY", "只有目前受控的原隊合格指揮者可下整隊領裝令")
	# Plan 5.1/5.2: authority is checked when the job is accepted. Re-checks of an
	# accepted job (order given) keep every body/stock/roster guard but no longer
	# require the original requester to still hold 整隊領裝 after a handover.
	if order.is_empty():
		var refused: Dictionary = team.duty_authority("team.equip", requester_id)
		if not refused.is_empty():
			return refused
	var representative_index := team.index_for_identity(representative_id)
	var representative: Dictionary = actions._person(representative_id)
	if not team.is_member(representative_index) or representative.is_empty() or not _team_person_present(team, representative_index, representative) or not _ready(representative).ok or not _at_depot(representative):
		return Runtime.fail("UNREACHABLE", "領裝代表須是原隊可行動成員，停止於營地相鄰可達格")
	if not equipment_team_external_duty_guard.is_valid() or not equipment_team_apply_guard.is_valid():
		return Runtime.fail("UNSUPPORTED", "整隊外部職務／實裝預檢尚未接入")
	var requester: Dictionary = actions._person(requester_id)
	if requester.is_empty() or not _ready(requester).ok or equipment_team_external_duty_guard.call(requester_id) or actions.equipment_conflict(requester_id, order):
		return Runtime.fail("BUSY", "原指揮者須清醒自由、停止且無其他作業")
	var roster_ids: Array[int] = []
	for index: int in team.command_members(): roster_ids.append(team.combat_identity(index))
	if not order.is_empty() and (roster_ids != order.roster_ids or int(team.team_id) != int(order.team_id)):
		return Runtime.fail("STALE_SOURCE", "原隊名冊或隊伍已改變")
	var target_ids: Array[int] = []
	if selected_ids.is_empty():
		for index: int in team.command_members():
			var identity := team.combat_identity(index)
			if identity != lab.controlled_person_id() or include_player:
				target_ids.append(identity)
	else:
		target_ids = selected_ids.duplicate()
	if target_ids.is_empty(): return Runtime.fail("NO_TARGET", "請選原隊伍成員")
	var seen := {}
	for identity: int in target_ids:
		var index := team.index_for_identity(identity)
		if seen.has(identity) or not roster_ids.has(identity) or not team.is_member(index) or team.member_gone(index) or identity == lab.controlled_person_id() and not include_player:
			return Runtime.fail("INVALID_MEMBER", "重複、已離隊或未明確納入的原人物")
		seen[identity] = true
		var person: Dictionary = actions._person(identity)
		if person.is_empty() or int(person.faction) != team.faction_id or not is_same(person.owner.data, lab.terrain) or not _team_person_present(team, index, person) or not _ready(person).ok:
			return Runtime.fail("BUSY", "#%d 不在原指揮在場範圍，或已移動、失能、受擊、工作" % identity)
		if equipment_team_external_duty_guard.call(identity) or actions.equipment_conflict(identity, order):
			return Runtime.fail("BUSY", "#%d 已有採集、交糧、車輛或其他人物作業" % identity)
	if equipment_team_external_duty_guard.call(representative_id) or actions.equipment_conflict(representative_id, order):
		return Runtime.fail("BUSY", "領裝代表已有其他原人物作業")
	return Runtime.ok("原隊伍與代表有效", {"target_ids": target_ids, "roster_ids": roster_ids})

## F06: representatives and ordinary members are checked as present, able team
## members within the formation radius, not as officers.
func _team_person_present(team: TerrainArmy, index: int, person: Dictionary) -> bool:
	return team.command_reference_valid and team._member_can_serve(index) and team.command_reference.distance_to(Vector2(person.cell)) <= team.command_radius + 2.0

func check_team_issue(order: Dictionary) -> Dictionary:
	if str(order.get("mode", "")) != "team_issue" or not is_instance_valid(lab) or not is_same(lab.terrain, order.get("terrain")) or not is_same(lab.terrain.site, order.get("site_state")):
		return Runtime.fail("STALE_SOURCE", "原 Site 已離開；整隊原裝未改")
	if bool(order.get("simulate_npc_commander", false)) and not str(order.get("nation_id", "")).begins_with("trial_team_"):
		return Runtime.fail("NO_AUTHORITY", "NPC 指揮模擬僅限明示的測試國別")
	if actions.has_active_issue(order): return Runtime.fail("BUSY", "同一營地已有另一份未完成領裝作業")
	if int(order.get("controlled_id", -1)) != int(lab.controlled_person_id()):
		return Runtime.fail("STALE_SOURCE", "控制人物已切換；整隊原裝保留")
	var team: TerrainArmy = order.team
	var context := _team_issue_context(team, int(order.requester_id), int(order.representative_id), bool(order.include_player), order.target_ids, order, bool(order.get("simulate_npc_commander", false)))
	if not context.ok: return context
	if context.target_ids.size() != order.entries.size() or context.target_ids != order.target_ids:
		return Runtime.fail("STALE_SOURCE", "整隊原目標已變更")
	var requester: Dictionary = actions._person(int(order.requester_id))
	if not is_same(requester.owner, order.requester_owner) or not is_same(requester.body, order.requester_body) or lab.terrain.index(requester.cell) != int(order.requester_cell) or int(requester.hit) != int(order.requester_hit):
		return Runtime.fail("INTERRUPTED", "原指揮者受擊、移動或已替換")
	var representative: Dictionary = actions._person(int(order.representative_id))
	if not is_same(representative.owner, order.representative_owner) or not is_same(representative.body, order.representative_body) or not is_same(representative.holder, order.representative_holder) or not is_same(representative.cargo, order.representative_cargo) or lab.terrain.index(representative.cell) != int(order.representative_cell) or int(representative.hit) != int(order.representative_hit) or int(representative.holder.version) != int(order.representative_version):
		return Runtime.fail("STALE_SOURCE", "原領裝代表已改變")
	var nation: Dictionary = lab.terrain.site.get("equipment_nations", {}).get(str(order.nation_id), {})
	var standard: Dictionary = _standard(int(order.target_ids[0]), str(order.nation_id), str(order.standard_id))
	if nation.is_empty() or not is_same(nation, order.nation_ref) or standard.is_empty() or not is_same(standard, order.standard_ref) or int(standard.revision) != int(order.standard_revision) or standard.slots != order.standard_slots or str(nation.get("culture", "")) != str(order.culture):
		return Runtime.fail("STALE_SOURCE", "原國別或標準已變更；請重新預覽")
	if not _slots_match_culture(standard.slots, lab.terrain.site.item_definitions, str(order.culture)):
		return Runtime.fail("CULTURE_MISMATCH", "原國別文化與標準不符")
	var depot: Dictionary = lab.terrain.site.depot_items
	if not Runtime._item_holder_shape(depot) or str(depot.holder) != "depot":
		return Runtime.fail("INVALID", "原補給點持物資料不合法")
	if not is_same(depot, order.depot_holder) or not is_same(lab.terrain.site.inventory, order.depot_stock) or lab.terrain.site.inventory != order.depot_stock_before or not is_same(lab.terrain.site.item_records, order.records_owner) or not is_same(lab.terrain.site.item_definitions, order.definitions_owner) or int(depot.version) != int(order.depot_version) or depot.item_ids != order.depot_ids or int(depot.version) >= 2147483646:
		return Runtime.fail("STALE_SOURCE", "原補給點持物或版本已變更")
	if not actions.equipment_changed.is_valid(): return Runtime.fail("UNSUPPORTED", "原裝備呈現刷新尚未接入")
	var all_take: Array = []
	var all_return: Array = []
	var seen_equipped := {}
	var proposed := {}
	var recipes := {}
	var missing_recipes := {}
	var appearances: Array[Dictionary] = []
	for entry: Dictionary in order.entries:
		var identity := int(entry.person_id)
		if not context.target_ids.has(identity) or _standard(identity, str(order.nation_id), str(order.standard_id)).is_empty():
			return Runtime.fail("NO_AUTHORITY", "原人物國籍或名冊已變更")
		var person: Dictionary = actions._person(identity)
		if person.is_empty() or not is_same(person.owner, entry.owner) or not is_same(person.body, entry.body) or not is_same(person.holder, entry.holder) or not is_same(person.cargo, entry.cargo) or lab.terrain.index(person.cell) != int(entry.cell) or int(person.hit) != int(entry.hit):
			return Runtime.fail("INTERRUPTED", "#%d 原人物受擊、移動或持物已替換" % identity)
		if int(person.holder.version) != int(entry.holder_version) or person.holder.item_ids != entry.holder_ids or person.holder.equipped != entry.before or person.cargo != entry.cargo_before or int(person.holder.version) >= 2147483646:
			return Runtime.fail("STALE_SOURCE", "#%d 原人物持物或貨物已變更" % identity)
		for slot: String in standard.slots:
			var chosen := str(entry.planned.get(slot, ""))
			var record: Dictionary = lab.terrain.site.item_records.get(chosen, {})
			var requirements: Dictionary = standard.slots[slot]
			if chosen.is_empty() or str(record.get("definition", "")) not in [str(requirements.definition)] + requirements.alternatives:
				return Runtime.fail("INVALID", "#%d 的標準槽位無合法原實物" % identity)
		for slot: String in entry.planned:
			var item_id := str(entry.planned[slot])
			var owner_key := "depot" if entry.take.has(item_id) else str(person.holder.holder)
			var definition := _held_definition(item_id, owner_key)
			if seen_equipped.has(item_id) or definition.is_empty() or str(definition.slot) != slot:
				return Runtime.fail("INVALID", "全隊同件重號或同槽位原物品失效")
			if standard.slots.has(slot):
				var actual_culture := definition_culture(definition)
				if not actual_culture.is_empty() and actual_culture != str(order.culture):
					return Runtime.fail("CULTURE_MISMATCH", "#%d 實物文化與國別不同" % identity)
			elif entry.before.get(slot) != item_id:
				return Runtime.fail("INVALID", "非標準槽位不得在領裝時更改")
			if entry.before.get(slot) != item_id and not entry.take.has(item_id):
				return Runtime.fail("INVALID", "新裝未列入原庫存分配")
			seen_equipped[item_id] = true
		for slot: String in entry.before:
			if entry.before[slot] != entry.planned.get(slot, "") and not entry["return"].has(str(entry.before[slot])):
				return Runtime.fail("INVALID", "舊裝未列入原退庫分配")
		for item_id: String in entry.take:
			if all_take.has(item_id) or not depot.item_ids.has(item_id) or _held_definition(item_id, "depot").is_empty():
				return Runtime.fail("MATERIALS", "原庫存實物已失效或重複領取")
			all_take.append(item_id)
		for item_id: String in entry["return"]:
			if all_return.has(item_id) or not person.holder.item_ids.has(item_id) or _held_definition(item_id, str(person.holder.holder)).is_empty():
				return Runtime.fail("STALE_SOURCE", "原退庫實物已失效或重複")
			all_return.append(item_id)
		var held_count: int = person.holder.item_ids.size() - entry["return"].size() + entry.take.size()
		if Runtime.inventory_size(person.cargo) + held_count - entry.planned.size() + Runtime.opened_food(lab.terrain.site, person.holder) > Runtime.CARRY_CAPACITY:
			return Runtime.fail("STORAGE_FULL", "#%d 換裝後行囊超過容量" % identity)
		var cape_guard := cape_wear_guard(identity, entry.planned)
		if not cape_guard.ok: return cape_guard
		if entry.planned != entry.before:
			var admission: Dictionary = equipment_team_apply_guard.call(identity, entry.planned)
			if not admission.ok and str(admission.get("code", "")) != "ATLAS_REQUIRED": return admission
			var appearance: Dictionary = admission.get("appearance", {})
			if appearance.is_empty(): return Runtime.fail("UNSUPPORTED", "整隊預檢未提供完整原人物外觀")
			proposed[identity] = appearance
			var recipe_key := TerrainArmy.EquipmentAtlas._mixed_key(appearance)
			if recipe_key.is_empty(): return Runtime.fail("UNSUPPORTED", "整隊原人物幾何配方不可用")
			recipes[recipe_key] = true
			if str(admission.get("code", "")) == "ATLAS_REQUIRED":
				var plan := TerrainArmy.EquipmentAtlas.mixed_plan(appearance)
				if plan.is_empty(): return Runtime.fail("UNSUPPORTED", "整隊完整圖集配方不可用")
				if not missing_recipes.has(str(plan.key)):
					missing_recipes[str(plan.key)] = true
					appearances.append(appearance)
	if all_take != order.take or all_return != order["return"]:
		return Runtime.fail("INVALID", "整隊原物品分配已改變")
	for item_id: String in order.records:
		if lab.terrain.site.item_records.get(item_id, {}) != order.records[item_id]:
			return Runtime.fail("STALE_SOURCE", "原實物定義、染色或持有人已變更")
	var after_size: int = Runtime.carried_size(lab.terrain.site.inventory, depot) + all_return.size() - all_take.size()
	if after_size > int(lab.terrain.site.capacity):
		return Runtime.fail("STORAGE_FULL", "原補給點無法容納整批退裝")
	var troop_guard := team.team_troop_equipment_guard(proposed)
	if not troop_guard.ok: return troop_guard
	if not appearances.is_empty():
		var pending := Runtime.fail("ATLAS_REQUIRED", "整隊須先準備共用圖集")
		pending.merge({"appearances": appearances, "recipe_count": recipes.size()})
		return pending
	return Runtime.ok("整隊全部原實物與最終兵種可提交", {"appearances": [], "recipe_count": recipes.size()})

func commit_team_issue(order: Dictionary) -> Dictionary:
	var prepared: Dictionary = prepare_team_equipment_change(order)
	if not prepared.ok: return prepared
	publish_team_equipment_change(prepared)
	return prepared.result


func check(order: Dictionary) -> Dictionary:
	var person: Dictionary = actions._person(int(order.person_id))
	var retirement := str(order.mode) == "retire_cape"
	var ready := Runtime.ok() if retirement and not person.is_empty() else _ready(person)
	if not ready.ok:
		return ready
	if int(person.holder.version) != int(order.person_version) or person.holder.equipped != order.before:
		return Runtime.fail("STALE_SOURCE", "本人的實際裝備已變更")
	if int(person.holder.version) >= 2147483646:
		return Runtime.fail("INVALID", "人物物品提交版本已用盡")
	if str(order.mode) not in ["issue", "personal", "retire_cape"] or str(order.mode) == "personal" and not bool(person.player):
		return Runtime.fail("NO_AUTHORITY", "個人換裝僅限原玩家本人")
	if retirement:
		var uncaped: Dictionary = order.before.duplicate()
		uncaped.erase("cape")
		if not order.before.has("cape") or order.planned != uncaped or not order.take.is_empty() or not order["return"].is_empty():
			return Runtime.fail("INVALID", "職務卸裝只可將原披風收回本人行囊")
	var cape_guard := cape_wear_guard(int(order.person_id), order.planned)
	if not cape_guard.ok:
		return cape_guard
	if not equipment_apply_guard.is_valid() or not actions.equipment_changed.is_valid():
		return Runtime.fail("UNSUPPORTED", "尚未接好該實裝組合的外觀／命中預檢")
	var issue_culture := ""
	var issue_slots := {}
	if str(order.mode) == "issue":
		var standard := _standard(int(order.person_id), str(order.nation_id), str(order.standard_id))
		if standard.is_empty() or int(standard.revision) != int(order.standard_revision):
			return Runtime.fail("NO_AUTHORITY", "國別或本次標準版本已改變，請重新領裝")
		var culture := str(lab.terrain.site.equipment_nations[str(order.nation_id)].get("culture", ""))
		if not _slots_match_culture(standard.slots, lab.terrain.site.item_definitions, culture):
			return Runtime.fail("CULTURE_REQUIRED" if culture.is_empty() else "CULTURE_MISMATCH", "領裝標準須符合本國固定文化；未設定時請由原軍事首長明確選擇，原裝與持物保留")
		issue_culture = culture
		issue_slots = standard.slots
		if not _at_depot(person):
			return Runtime.fail("UNREACHABLE")
		var depot: Dictionary = lab.terrain.site.depot_items
		if int(depot.version) != int(order.depot_version):
			return Runtime.fail("STALE_SOURCE", "原庫存物品已變更")
		if int(depot.version) >= 2147483646:
			return Runtime.fail("INVALID", "原庫存提交版本已用盡")
		for identity: String in order.take:
			if not depot.item_ids.has(identity) or _held_definition(identity, "depot").is_empty():
				return Runtime.fail("MATERIALS", "本次原實物已不在補給點")
		for identity: String in order["return"]:
			if not person.holder.item_ids.has(identity) or _held_definition(identity, str(person.holder.holder)).is_empty():
				return Runtime.fail("STALE_SOURCE", "退庫原物不再屬於本人")
		var after_size: int = Runtime.carried_size(lab.terrain.site.inventory, depot) + order["return"].size() - order.take.size()
		if after_size > int(lab.terrain.site.capacity):
			return Runtime.fail("STORAGE_FULL", "原補給點無法容納整批退裝")
	var seen := {}
	for slot: String in order.planned:
		var identity := str(order.planned[slot])
		var expected_owner := "depot" if order.take.has(identity) else str(person.holder.holder)
		var definition := _held_definition(identity, expected_owner)
		if seen.has(identity) or definition.is_empty() or str(definition.slot) != slot:
			return Runtime.fail("INVALID", "裝備唯一所有權／同槽位引用失效")
		if issue_slots.has(slot):
			var actual_culture := definition_culture(definition)
			if not actual_culture.is_empty() and actual_culture != issue_culture:
				return Runtime.fail("CULTURE_MISMATCH", "本次領取的原實物文化已不符合國別；原裝與持物保留")
		seen[identity] = true
	var held_count: int = person.holder.item_ids.size() - order["return"].size() + order.take.size()
	if Runtime.inventory_size(person.cargo) + held_count - order.planned.size() + Runtime.opened_food(lab.terrain.site, person.holder) > Runtime.CARRY_CAPACITY:
		return Runtime.fail("STORAGE_FULL", "卸下後超過本人的二十件行囊")
	var applied: Dictionary = equipment_apply_guard.call(int(order.person_id), order.planned)
	if not applied.ok: return applied
	var military := _military_issue_check(order)
	return military if not military.ok else applied

func commit(order: Dictionary) -> Dictionary:
	var prepared: Dictionary = prepare_equipment_change(order)
	if not prepared.ok: return prepared
	publish_equipment_change(prepared)
	return prepared.result


func _ready(person: Dictionary) -> Dictionary:
	if person.is_empty() or not actions._ready(person) or float(lab.terrain.site.get("combat_left", 0.0)) > 0.0:
		return Runtime.fail("BUSY", "換装須原人物清醒自由、停止、無其他作業且已脫戰")
	return Runtime.ok()

func _at_depot(person: Dictionary) -> bool:
	return lab.terrain.site.has("depot_cell") and actions._adjacent(person.cell, lab.terrain.cell_from_index(int(lab.terrain.site.depot_cell)))

func _standard(identity: int, nation_id: String, standard_id: String) -> Dictionary:
	var nation: Dictionary = lab.terrain.site.get("equipment_nations", {}).get(nation_id, {})
	if nation.is_empty() or not _member(nation, identity):
		return {}
	return nation.get("standards", {}).get(standard_id, {})

func _held_definition(identity: String, owner_key: String) -> Dictionary:
	var record: Dictionary = lab.terrain.site.item_records.get(identity, {})
	var definition_id := str(record.get("definition", ""))
	var definition: Dictionary = lab.terrain.site.item_definitions.get(definition_id, {})
	return definition if str(record.get("holder", "")) == owner_key and valid_definition(definition_id, definition) else {}

static func _member(nation: Dictionary, identity: int) -> bool:
	for member_id: Variant in nation.get("members", []):
		if int(member_id) == identity:
			return true
	return false

static func _valid_slots(slots: Dictionary, definitions: Dictionary) -> bool:
	if slots.is_empty() or slots.size() > Runtime.EQUIPMENT_SLOTS.size():
		return false
	for slot: Variant in slots:
		var requirement: Variant = slots[slot]
		if not (slot is String or slot is StringName) or str(slot) not in Runtime.EQUIPMENT_SLOTS or not requirement is Dictionary or requirement.size() != 2 or not requirement.get("definition") is String or not requirement.get("alternatives") is Array:
			return false
		var seen := {}
		for definition_id: Variant in [requirement.definition] + requirement.alternatives:
			if not definition_id is String or seen.has(definition_id) or not definitions.has(definition_id) or not valid_definition(definition_id, definitions[definition_id]) or str(definitions[definition_id].slot) != str(slot):
				return false
			seen[definition_id] = true
	return true

static func definition_culture(definition: Dictionary) -> String:
	# Editor metadata is authoritative; materials, labels and asset names are not culture.
	# Existing untagged weapons/underlayers have no cultural constraint here.
	for slot: Dictionary in Visual.PART_SLOTS:
		if str(slot.id) == str(definition.get("slot", "")):
			for option: Dictionary in slot.options:
				if str(option.id) == str(definition.get("asset", "")):
					return str(option.get("culture", ""))
	return ""

static func _slots_match_culture(slots: Dictionary, definitions: Dictionary, culture: String) -> bool:
	if not culture.is_empty() and not CULTURES.has(culture): return false
	for requirement: Dictionary in slots.values():
		for identity: String in [str(requirement.definition)] + requirement.alternatives:
			var actual := definition_culture(definitions.get(identity, {}))
			if not actual.is_empty() and actual != culture: return false
	return true

## Optional display name of an equipment nation: 1..32 characters.
static func valid_nation_name(value: Variant) -> bool:
	return value is String and not str(value).is_empty() and str(value).length() <= 32

static func valid_nations(value: Variant, definitions: Dictionary, known_people: Dictionary, state: Dictionary = {}) -> bool:
	if not value is Dictionary or not valid_organization_refs(state):
		return false
	var remote: Dictionary = state.get("organization_refs", {}).get("remote_people", {})
	var operation_people := known_people.duplicate()
	for identity: String in remote: operation_people[int(identity)] = true
	var assigned := {}
	var faction_nations := {}
	for nation_id: Variant in value:
		var nation: Variant = value[nation_id]
		if not nation_id is String or not _valid_key(nation_id) or not nation is Dictionary or nation.size() != 3 + int(nation.has("culture")) + int(nation.has("technology")) + int(nation.has("technology_operations")) + int(nation.has("ransom_data")) + int(nation.has("faction_version")) + int(nation.has("faction_id")) + int(nation.has("name")) + int(nation.has("succession")) or not nation.get("members") is Array or not nation.get("standards") is Dictionary:
			return false
		if not RegionFactionQuery.nation_schema(nation, nation_id): return false
		if nation.has("name") and not valid_nation_name(nation.get("name")): return false
		if nation.has("faction_id"):
			var faction: int = int(nation.faction_id)
			var stable: Variant = state.get("travel_identity", {}).get("refs", {}).get("nation", {}).get(nation_id)
			if faction_nations.has(faction) or not RegionFactionQuery.ref_valid(stable, "nation"): return false
			faction_nations[faction] = true
			var head: int = int(SiteOffices.head_position(nation_offices(nation, true)).get("holder", -1))
			if head > 0 and _faction_person(state, head) != faction: return false
		if nation.has("technology") and not Technology.valid_scope_record(nation.technology, "nation"): return false
		if nation.has("technology_operations") and not nation.has("technology"): return false
		if nation.has("technology_operations") and not valid_nation_operation_record(nation.technology_operations, definitions, operation_people): return false
		if nation.has("culture") and (not nation.culture is String or not CULTURES.has(nation.culture)):
			return false
		if nation.has("offices"):
			# Versioned record: military_head is derived, never stored beside offices.
			if nation.has("military_head") or not SiteOffices.validate(nation.offices, "nation"):
				return false
			for seat: Dictionary in nation.offices.positions:
				if int(seat.holder) > 0 and not _member(nation, int(seat.holder)): return false
		elif not _integer(nation.get("military_head")) or int(nation.military_head) == 1000000000 or not _member(nation, int(nation.military_head)):
			return false
		if nation.has("succession"):
			if not nation.has("offices") or not nation.offices is Dictionary: return false
			var seat_ids: Array = []
			for seat: Dictionary in nation.offices.positions:
				if bool(seat.head): seat_ids.append(str(seat.id))
			var member_set := {}
			for member: Variant in nation.members: member_set[int(member)] = true
			if not Succession.valid_record(nation.succession, seat_ids, member_set): return false
		for identity: Variant in nation.members:
			if not _integer(identity) or int(identity) == 1000000000 or not known_people.has(int(identity)) and not remote.has(str(int(identity))) or assigned.has(int(identity)):
				return false
			assigned[int(identity)] = nation_id
		for standard_id: Variant in nation.standards:
			var standard: Variant = nation.standards[standard_id]
			if not standard_id is String or not _valid_key(standard_id) or not standard is Dictionary or standard.size() != 3 + int(standard.has("equipment_dyes")) or not standard.get("name") is String or standard.name.is_empty() or standard.name.length() > 128 or not _integer(standard.get("revision")) or not standard.get("slots") is Dictionary or not _valid_slots(standard.slots, definitions) or not Runtime.EquipmentDye.valid_dyes(standard.get("equipment_dyes", {})):
				return false
			if nation.has("culture") and not _slots_match_culture(standard.slots, definitions, nation.culture):
				return false
	return RansomData.valid_nations(value, state)

static func _integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value)) and float(value) >= 1.0 and float(value) < 2147483647.0

static func _valid_key(value: String) -> bool:
	if value.is_empty() or value.length() > 32:
		return false
	for character: String in value:
		if not character in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-":
			return false
	return true

static func valid_definition(identity: String, definition: Variant) -> bool:
	if not Runtime.valid_item_definition(identity, definition) or str(definition.slot) not in Runtime.EQUIPMENT_SLOTS or str(definition.asset) == "none":
		return false
	for slot: Dictionary in Visual.PART_SLOTS:
		if str(slot.id) == str(definition.slot):
			for option: Dictionary in slot.options:
				if str(option.id) == str(definition.asset):
					return true
	return false

# National technology commands stay on the ORIGINAL nation record and holders.
# These do not advance time or mint knowledge/products. Runtime owns production
# and PersonActions owns issue timing and its post-contact atomic exchange.
static func empty_nation_operations() -> Dictionary:
	return {"version": NATION_OPERATIONS_VERSION, "next_seq": 1, "specs": {}, "certificates": {}, "orders": {}}

static func _operation_key(value: Variant) -> bool:
	if not value is String or str(value).is_empty() or str(value).length() > 96: return false
	for character: String in value:
		if not character in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-.:":
			return false
	return true

static func _operation_person(value: Variant, people: Dictionary) -> bool:
	return Technology.integer(value, 1) and int(value) != 1000000000 and (people.is_empty() or people.has(int(value)))

static func _operation_stack(value: Variant, allow_zero: bool = false) -> bool:
	if not value is Dictionary: return false
	for resource: Variant in value:
		if not resource is String or not Runtime.Env.ITEM_NAMES.has(resource) or not Technology.integer(value[resource], 0 if allow_zero else 1, 1000000): return false
	return true

func _nation_operation_context(requester_id: int, nation_id: String, duty_id: String, technology_id: String, binding_id: String = "", read_only: bool = false) -> Dictionary:
	var nation: Dictionary = lab.terrain.site.get("equipment_nations", {}).get(nation_id, {})
	if not _nation_duty_ok(requester_id, nation, duty_id, read_only):
		if read_only: return SiteOffices.refusal(nation_duty_resolve(nation, duty_id, true), requester_id, nation_offices(nation, true))
		return _nation_refusal(requester_id, nation, duty_id, "新增制度須由原國家該職責的合法行使者明示安排")
	if not Technology.valid_scope_record(nation.get("technology"), "nation"):
		return Runtime.fail("UNKNOWN_TECHNOLOGY", "本國尚無合法制度科技紀錄")
	if str(nation.technology.holder_site_id) != str(lab.terrain.site.id): return Runtime.fail("STALE_SCOPE")
	if not Technology.scope_known(nation.technology, technology_id):
		var project := Technology.active_project(nation.technology)
		var reference: Dictionary = project.get("executor", {})
		var phase := Technology.scope_next_phase(project, reference)
		if binding_id.is_empty() or not Technology.valid_ref(reference) or reference.site_id != str(lab.terrain.site.id) \
			or not _nation_person_ok(nation, int(reference.person_id)) \
			or not Technology.scope_operation_trial(nation.technology, "nation", technology_id, str(phase.get("id", "")), binding_id, reference):
			return Runtime.fail("UNKNOWN_TECHNOLOGY", "僅本次原具名、有限、當前研究階段可試行新操作")
	if nation.has("technology_operations") and not valid_nation_operation_record(nation.technology_operations, lab.terrain.site.item_definitions, {}):
		return Runtime.fail("CORRUPT_STATE", "原國家操作欄位非法")
	if nation.has("technology_operations") and (not _nation_order_scope_valid(nation, nation_id, str(lab.terrain.site.id)) or not _site_operation_claims_valid(lab.terrain.site)):
		return Runtime.fail("CORRUPT_STATE", "原Site／國家／具名用途不可互借同意或真收據")
	return Runtime.ok("", {"nation": nation})

func _nation_operation_candidate(nation: Dictionary) -> Dictionary:
	return nation.technology_operations.duplicate(true) if nation.has("technology_operations") else empty_nation_operations()

func _original_stock_transport() -> Variant:
	return lab.site_controller.vehicles if lab.site_controller != null else null

func _procurement_destination(requester_id: int, feature_id: String) -> Dictionary:
	var person: Dictionary = actions._person(requester_id)
	var feature: Dictionary = lab.terrain.site.get("features", {}).get(feature_id, {})
	var stock := Stockpiles.stock_endpoint(lab.terrain, feature_id)
	if person.is_empty() or feature.is_empty() or stock.is_empty() or str(feature.kind) != "warehouse" \
		or not Runtime.feature_usable(feature) or int(stock.faction) != int(person.faction):
		return Runtime.fail("NO_TARGET", "採購接收處須為已存在、可用、同管理方的原倉庫")
	return Runtime.ok("", {"stock": stock})

## N01 has a real specification, bounded batches and explicit same-slot
## definitions/substitutes; this never edits the existing equipment standard.
func publish_procurement_spec(requester_id: int, nation_id: String, spec_id: String, display_name: String, destination_feature_id: String, resource_limits: Dictionary, item_requirements: Dictionary, expected_revision: int = 0) -> Dictionary:
	if requester_id != int(lab.controlled_person_id()): return Runtime.fail("NO_AUTHORITY", "新具名制度命令須由當前受控原職責行使者明示")
	var checked := _nation_operation_context(requester_id, nation_id, "nation.procurement", "N01", "procurement")
	if not checked.ok: return checked
	if not _operation_key(spec_id) or display_name.is_empty() or display_name.length() > 128: return Runtime.fail("INVALID", "採購規格名稱／ID")
	var destination := _procurement_destination(requester_id, destination_feature_id)
	if not destination.ok: return destination
	var candidate := _nation_operation_candidate(checked.nation)
	var previous: Dictionary = candidate.specs.get(spec_id, {})
	if int(previous.get("revision", 0)) != expected_revision or expected_revision >= 2147483646: return Runtime.fail("STALE_SPEC")
	var spec := {"revision": expected_revision + 1, "authorizer_id": requester_id, "name": display_name,
		"destination_feature_id": destination_feature_id, "resources": resource_limits.duplicate(true),
		"items": item_requirements.duplicate(true), "receipts": []}
	if not previous.is_empty():
		if not previous.receipts.is_empty() and (previous.resources != spec.resources or previous.items != spec.items or previous.destination_feature_id != destination_feature_id):
			return Runtime.fail("BUSY", "已交貨規格只能由現任者重新核准；新規格須另立ID，歷史和額度不清零")
		spec.receipts = previous.receipts.duplicate(true)
		if previous.has("tech_trial"): spec.tech_trial = previous.tech_trial.duplicate(true)
	candidate.specs[spec_id] = spec
	if not valid_nation_operation_record(candidate, lab.terrain.site.item_definitions, {}): return Runtime.fail("INVALID", "批量／總量或真物品定義替代規格非法")
	_publish_nation_operations(checked.nation, candidate)
	return Runtime.ok("已發布獨立採購規格，現役裝備及既有配裝標準未變", {"spec_id": spec_id, "revision": spec.revision})

static func _procurement_received(spec: Dictionary, definitions: Dictionary) -> Dictionary:
	var resources: Dictionary = {}
	var items: Dictionary = {}
	for receipt: Dictionary in spec.receipts:
		Runtime.add_items(resources, receipt.resources)
		for definition_id: String in receipt.items.values():
			var slot := str(definitions.get(definition_id, {}).get("slot", ""))
			items[slot] = int(items.get(slot, 0)) + 1
	return {"resources": resources, "items": items}

## This uses the real controlled supplier's own original cargo and the original
## VehicleTransport transfer. There is no nation-wide depot or imaginary tax stock.
func accept_procurement_delivery(supplier_id: int, nation_id: String, spec_id: String, resources: Dictionary, item_ids: Array, source_version: int, destination_version: int, receipt_key: String) -> Dictionary:
	var nation: Dictionary = lab.terrain.site.get("equipment_nations", {}).get(nation_id, {})
	if not nation.has("technology_operations") or not valid_nation_operation_record(nation.technology_operations, lab.terrain.site.item_definitions, {}):
		return Runtime.fail("NO_TARGET", "缺少合法原採購規格")
	var spec: Dictionary = nation.technology_operations.specs.get(spec_id, {})
	if spec.is_empty(): return Runtime.fail("NO_TARGET")
	var checked := _nation_operation_context(int(spec.authorizer_id), nation_id, "nation.procurement", "N01", "procurement")
	if not checked.ok: return checked
	if supplier_id != int(lab.controlled_person_id()) or not _operation_key(receipt_key): return Runtime.fail("NO_AUTHORITY", "供料須當前受控原人明示交出自己的持物")
	var person: Dictionary = actions._person(supplier_id)
	if person.is_empty() or str(person.holder.holder) != "person:" + str(supplier_id): return Runtime.fail("STALE_SOURCE")
	if not Technology.scope_known(nation.technology, "N01"):
		var project := Technology.active_project(nation.technology)
		if project.executor != {"site_id": str(lab.terrain.site.id), "person_id": supplier_id}: return Runtime.fail("NO_AUTHORITY", "試行交貨必須由本次原具名試作者執行")
	var candidate := _nation_operation_candidate(nation)
	var next_spec: Dictionary = candidate.specs[spec_id]
	for receipt: Dictionary in next_spec.receipts:
		if receipt.id == receipt_key: return Runtime.fail("NO_CHANGE", "原交貨完成键已提交；不再扣料或計數")
	if not _operation_stack(resources) or not item_ids is Array or resources.is_empty() and item_ids.is_empty(): return Runtime.fail("INVALID")
	var delivered: Dictionary = {}
	for item_id: Variant in item_ids:
		if not item_id is String or delivered.has(item_id): return Runtime.fail("INVALID", "交貨原實物重複")
		var definition := _held_definition(str(item_id), str(person.holder.holder))
		if definition.is_empty(): return Runtime.fail("STALE_SOURCE")
		delivered[item_id] = str(lab.terrain.site.item_records[item_id].definition)
	next_spec.receipts.append({"id": receipt_key, "source_person_id": supplier_id, "resources": resources.duplicate(), "items": delivered})
	if not valid_nation_operation_record(candidate, lab.terrain.site.item_definitions, {}): return Runtime.fail("CAPACITY", "不符原批量、替代規格或累計交貨上限")
	var destination := _procurement_destination(int(spec.authorizer_id), str(spec.destination_feature_id))
	if not destination.ok: return destination
	var transport: Variant = _original_stock_transport()
	if transport == null: return Runtime.fail("UNSUPPORTED", "原裝卸入口尚未接入")
	var transfer: Dictionary = transport.prepare_transfer("person:" + str(supplier_id), "feature:" + str(spec.destination_feature_id), resources, item_ids, source_version, destination_version, supplier_id)
	if not transfer.ok: return transfer
	var research: Dictionary = actions.prepare_nation_procurement_delivery(nation_id, spec_id, next_spec, transfer)
	if not research.ok: return research
	if not valid_nation_operation_record(candidate, lab.terrain.site.item_definitions, {}): return Runtime.fail("INVALID_TECHNOLOGY")
	var stable := Runtime.validate_prepared_item_transfer(transfer)
	if not stable.ok: return stable
	# All original stock/contact/holder/CAS and research checks precede this tail.
	Runtime.publish_item_transfer(transfer)
	_publish_nation_operations(nation, candidate)
	actions.publish_nation_original_administration(research)
	return Runtime.ok("真物資已交原倉庫；採購規格額度及本次收據同次提交", {"receipt_key": receipt_key, "spec_id": spec_id})

static func _valid_procurement_spec(raw: Variant, definitions: Dictionary, people: Dictionary) -> bool:
	var fields := ["revision", "authorizer_id", "name", "destination_feature_id", "resources", "items", "receipts"]
	if raw is Dictionary and raw.has("tech_trial"): fields.append("tech_trial")
	if not Technology.keys(raw, fields) \
		or not Technology.integer(raw.revision, 1) or not _operation_person(raw.authorizer_id, people) or not raw.name is String or str(raw.name).is_empty() or str(raw.name).length() > 128 \
		or not _operation_key(raw.destination_feature_id) or not raw.resources is Dictionary or not raw.items is Dictionary or raw.resources.is_empty() and raw.items.is_empty() \
		or not raw.receipts is Array or raw.receipts.size() > NATION_OPERATIONS_MAX: return false
	if raw.has("tech_trial"):
		if not _valid_procurement_trial(raw.tech_trial) or raw.receipts.is_empty() or raw.receipts.size() > 2 or not raw.items.is_empty() or int(raw.authorizer_id) != int(raw.tech_trial.person.person_id): return false
		if not Technology.keys(raw.resources, ["wood", "grain"]): return false
		for resource: String in ["wood", "grain"]:
			if not Technology.keys(raw.resources[resource], ["batch", "total"]) or not Technology.integer(raw.resources[resource].total, 2, 2): return false
		for receipt: Variant in raw.receipts:
			if not Technology.keys(receipt, ["id", "source_person_id", "resources", "items"]) or receipt.source_person_id != raw.tech_trial.person.person_id or not Technology.material_equal(receipt.resources, {"wood": 1, "grain": 1}) or not receipt.items is Dictionary or not receipt.items.is_empty(): return false
	for resource: Variant in raw.resources:
		var limits: Variant = raw.resources[resource]
		if not resource is String or not Runtime.Env.ITEM_NAMES.has(resource) or not Technology.keys(limits, ["batch", "total"]) \
			or not Technology.integer(limits.batch, 1, 1000000) or not Technology.integer(limits.total, int(limits.batch), 1000000): return false
	var slots: Dictionary = {}
	for slot: Variant in raw.items:
		var requirement: Variant = raw.items[slot]
		if not slot is String or not Technology.keys(requirement, ["definition", "alternatives", "batch", "total"]) \
			or not Technology.integer(requirement.batch, 1, NATION_OPERATIONS_MAX) or not Technology.integer(requirement.total, int(requirement.batch), NATION_OPERATIONS_MAX):
			return false
		slots[slot] = {"definition": requirement.definition, "alternatives": requirement.alternatives}
	if not slots.is_empty() and not _valid_slots(slots, definitions): return false
	var seen: Dictionary = {}
	var seen_items: Dictionary = {}
	for receipt: Variant in raw.receipts:
		if not Technology.keys(receipt, ["id", "source_person_id", "resources", "items"]) or not _operation_key(receipt.id) or seen.has(receipt.id) \
			or not _operation_person(receipt.source_person_id, people) or not _operation_stack(receipt.resources) or not receipt.items is Dictionary \
			or receipt.resources.is_empty() and receipt.items.is_empty(): return false
		seen[receipt.id] = true
		for resource: String in receipt.resources:
			if not raw.resources.has(resource) or int(receipt.resources[resource]) > int(raw.resources[resource].batch): return false
		var counts: Dictionary = {}
		for item_id: Variant in receipt.items:
			var definition_id: Variant = receipt.items[item_id]
			if not item_id is String or not item_id.is_valid_int() or str(int(item_id)) != item_id or not Technology.integer(int(item_id), 1) \
				or seen_items.has(item_id) or not definition_id is String or not definitions.has(definition_id) or not valid_definition(definition_id, definitions[definition_id]): return false
			seen_items[item_id] = true
			var slot := str(definitions[definition_id].slot)
			if not raw.items.has(slot) or definition_id not in [raw.items[slot].definition] + raw.items[slot].alternatives: return false
			counts[slot] = int(counts.get(slot, 0)) + 1
		for slot: String in counts:
			if int(counts[slot]) > int(raw.items[slot].batch): return false
	var received := _procurement_received(raw, definitions)
	for resource: String in received.resources:
		if int(received.resources[resource]) > int(raw.resources[resource].total): return false
	for slot: String in received.items:
		if int(received.items[slot]) > int(raw.items[slot].total): return false
	return true

func _output_receipt(feature_id: String, receipt_id: int) -> Dictionary:
	var feature: Dictionary = lab.terrain.site.get("features", {}).get(feature_id, {})
	var output: Variant = feature.get("technology_output")
	if not output is Dictionary or not output.get("receipts") is Array: return {}
	for receipt: Variant in output.receipts:
		if _valid_output_receipt(receipt, str(lab.terrain.site.id), feature_id) and int(receipt.id) == receipt_id:
			return receipt
	return {}

static func _valid_output_receipt(raw: Variant, site_id: String, feature_id: String) -> bool:
	if not Technology.keys(raw, ["id", "site_id", "feature_id", "operator_id", "recipe_id", "resources", "item_ids", "work_seconds"]) \
		or not Technology.integer(raw.id, 1) or raw.site_id != site_id or raw.feature_id != feature_id \
		or not Technology.valid_ref({"site_id": raw.site_id, "person_id": raw.operator_id}) or not raw.recipe_id is String \
		or not _operation_stack(raw.resources) or not raw.item_ids is Array or not Technology.finite_number(raw.work_seconds, 0.000001): return false
	var seen := {}
	for item_id: Variant in raw.item_ids:
		if not item_id is String or not item_id.is_valid_int() or str(int(item_id)) != item_id or not Technology.integer(int(item_id), 1) or seen.has(item_id): return false
		seen[item_id] = true
	return not raw.resources.is_empty() or not raw.item_ids.is_empty()

static func _workshop_sample_matches(receipt: Dictionary, industry_id: String) -> bool:
	if industry_id == "S04": return receipt.recipe_id == "" and int(receipt.resources.get("tools", 0)) > 0 and receipt.item_ids.is_empty()
	if industry_id == "S05": return receipt.recipe_id == "wool_cloth" and int(receipt.resources.get("cloth", 0)) > 0 and receipt.item_ids.is_empty()
	return industry_id == "S07" and receipt.recipe_id == "bow" and receipt.resources.is_empty() and receipt.item_ids.size() == 1

func _workshop_context(feature_id: String, industry_id: String, operator_id: int) -> Dictionary:
	var feature: Dictionary = lab.terrain.site.get("features", {}).get(feature_id, {})
	var settlement := Settlement.record(lab.terrain)
	var status := Settlement.status(lab)
	var host := {"S04": "smithy", "S05": "weaver", "S07": "smithy"}
	if not host.has(industry_id) or feature.is_empty() or str(feature.get("kind", "")) != host[industry_id] \
		or not bool(status.effective) or not Runtime.feature_usable(feature) or str(feature.get("stage", "")) != "complete" \
		or not Settlement.feature_in_jurisdiction(lab.terrain, feature) or int(feature.get("owner_faction", -1)) != int(settlement.get("owner_faction", -2)) \
		or not Technology.scope_known(settlement.get("technology", {}), industry_id) or Runtime.feature_work_slots(lab.terrain, feature).is_empty():
		return Runtime.fail("NO_WORKSHOP", "原聚落中心／管轄／該產業／真工位尚不成立或已停效")
	var person: Dictionary = actions._person(operator_id)
	if person.is_empty() or float(person.hp) <= 0.0 or float(person.ko) > 0.0 or bool(person.captive) or int(person.faction) != int(feature.owner_faction):
		return Runtime.fail("NO_WORKER", "作坊須有目前可工作、同管理方的原操作員")
	var skills := {"S05": "F06", "S07": "F07"}
	if skills.has(industry_id) and not Technology.learned(actions._body_get(person, "technology"), str(skills[industry_id])): return Runtime.fail("NO_SKILL")
	return Runtime.ok("", {"feature": feature, "settlement_id": str(settlement.settlement_id), "person": person})

## N04 checks the ORIGINAL completed production receipt, not a purchased depot sample.
func certify_workshop(requester_id: int, nation_id: String, certificate_id: String, feature_id: String, industry_id: String, receipt_id: int, expected_revision: int = 0) -> Dictionary:
	if requester_id != int(lab.controlled_person_id()): return Runtime.fail("NO_AUTHORITY", "新具名制度命令須由當前受控原職責行使者明示")
	var checked := _nation_operation_context(requester_id, nation_id, "nation.workshop", "N04", "workshop_certificate")
	if not checked.ok: return checked
	if not _operation_key(certificate_id) or not Technology.integer(receipt_id, 1): return Runtime.fail("INVALID")
	var receipt := _output_receipt(feature_id, receipt_id)
	if receipt.is_empty(): return Runtime.fail("NO_RECEIPT", "須先完成本原作坊真批次")
	var workshop := _workshop_context(feature_id, industry_id, int(receipt.operator_id))
	if not workshop.ok: return workshop
	if not _workshop_sample_matches(receipt, industry_id):
		return Runtime.fail("SPEC_MISMATCH", "原作坊實績不屬所選產業")
	var candidate := _public_candidate(checked.nation)
	var previous: Dictionary = candidate.certificates.get(certificate_id, {})
	if int(previous.get("revision", 0)) != expected_revision or expected_revision >= 2147483646: return Runtime.fail("STALE_CERTIFICATE")
	candidate.certificates[certificate_id] = {"revision": expected_revision + 1, "authorizer_id": requester_id,
		"settlement_id": workshop.settlement_id, "feature_id": feature_id, "industry_id": industry_id,
		"operator_id": int(receipt.operator_id), "receipt_id": receipt_id, "accepted_receipt": receipt.duplicate(true), "status": "active", "reason": ""}
	if not valid_nation_operation_record(candidate, lab.terrain.site.item_definitions, {}): return Runtime.fail("INVALID")
	var research: Dictionary = actions.prepare_nation_workshop_administration(nation_id, certificate_id, candidate.certificates[certificate_id])
	if not research.ok: return research
	_publish_nation_operations(checked.nation, candidate)
	actions.publish_nation_original_administration(research)
	return Runtime.ok("已驗收本原作坊的真實出貨，保留具體範圍及可撤銷資格", {"certificate_id": certificate_id})

func revoke_workshop_certificate(requester_id: int, nation_id: String, certificate_id: String, expected_revision: int, reason: String) -> Dictionary:
	if requester_id != int(lab.controlled_person_id()): return Runtime.fail("NO_AUTHORITY", "新具名制度命令須由當前受控原職責行使者明示")
	var checked := _nation_operation_context(requester_id, nation_id, "nation.workshop", "N04", "workshop_certificate")
	if not checked.ok: return checked
	var candidate := _nation_operation_candidate(checked.nation)
	var certificate: Dictionary = candidate.certificates.get(certificate_id, {})
	if certificate.is_empty() or int(certificate.revision) != expected_revision or expected_revision >= 2147483646: return Runtime.fail("STALE_CERTIFICATE")
	if reason.is_empty() or reason.length() > 256: return Runtime.fail("INVALID", "撤銷須明列原因")
	certificate.status = "revoked"
	certificate.reason = reason
	certificate.revision = expected_revision + 1
	if not valid_nation_operation_record(candidate, lab.terrain.site.item_definitions, {}): return Runtime.fail("INVALID")
	_publish_nation_operations(checked.nation, candidate)
	return Runtime.ok("已撤銷原作坊資格；原產品與研究歷史保留")

func _certificate_context(nation: Dictionary, certificate_id: String, operator_id: int, read_only: bool = false) -> Dictionary:
	var certificate: Dictionary = nation.get("technology_operations", {}).get("certificates", {}).get(certificate_id, {})
	if certificate.is_empty() or certificate.status != "active": return Runtime.fail("STALE_CERTIFICATE", "原作坊資格不存在或已撤銷")
	if not _nation_duty_ok(int(certificate.authorizer_id), nation, "nation.workshop", read_only): return Runtime.fail("NO_AUTHORITY", "原驗收職責已改，須由現任者重新核准")
	var workshop := _workshop_context(str(certificate.feature_id), str(certificate.industry_id), operator_id)
	if not workshop.ok: return workshop
	var sample: Dictionary = certificate.get("accepted_receipt", {})
	if sample.is_empty(): sample = _output_receipt(str(certificate.feature_id), int(certificate.receipt_id)) # Exact legacy v1 only.
	if str(workshop.settlement_id) != str(certificate.settlement_id) or sample.is_empty() or int(sample.operator_id) != int(certificate.operator_id) \
		or not _workshop_sample_matches(sample, str(certificate.industry_id)): return Runtime.fail("STALE_CERTIFICATE")
	return Runtime.ok("", {"certificate": certificate, "workshop": workshop})
func request_military_production_order(requester_id: int, nation_id: String, certificate_id: String, operator_id: int, recipient_id: int, standard_id: String) -> Dictionary:
	if requester_id != int(lab.controlled_person_id()): return Runtime.fail("NO_AUTHORITY", "新具名制度命令須由當前受控原職責行使者明示")
	var checked := _nation_operation_context(requester_id, nation_id, "nation.production", "N05", "workshop_bow")
	if not checked.ok: return checked
	if not Technology.scope_known(checked.nation.technology, "N05"):
		var project := Technology.active_project(checked.nation.technology)
		if project.get("executor", {}).get("person_id") != operator_id or operator_id != recipient_id: return Runtime.fail("NO_AUTHORITY", "首次軍需研究須由本次同一原人真正造弓再領裝")
	var certificate := _certificate_context(checked.nation, certificate_id, operator_id)
	if not certificate.ok: return certificate
	if str(certificate.certificate.industry_id) != "S07": return Runtime.fail("SPEC_MISMATCH", "首批军需订单只沿真弓作坊")
	var standard := _standard(recipient_id, nation_id, standard_id)
	if standard.is_empty() or not standard.slots.has("weapon") or "weapon:bow_01" not in [standard.slots.weapon.definition] + standard.slots.weapon.alternatives:
		return Runtime.fail("SPEC_MISMATCH", "原領裝標準須明列真bow定義／替代，接收者須屬原國家")
	if not Runtime.FEATURE_RECIPES.get("smithy", {}).has("bow"): return Runtime.fail("UNSUPPORTED", "原smithy bow實物出貨配方尚未接入")
	var candidate := _public_candidate(checked.nation)
	if int(candidate.next_seq) >= 2147483646: return Runtime.fail("CAPACITY")
	var order_id := "production_" + str(int(candidate.next_seq))
	var consent: Dictionary = {}
	var response: Dictionary = actions._technology_military_consent_candidate(operator_id, _nation_order_purpose("N05", str(lab.terrain.site.id), nation_id, order_id))
	if not response.ok: return response
	consent = response.consent.duplicate(true)
	candidate.next_seq = int(candidate.next_seq) + 1
	candidate.orders[order_id] = {"revision": 1, "authorizer_id": requester_id, "certificate_id": certificate_id,
		"certificate_revision": int(certificate.certificate.revision), "feature_id": str(certificate.certificate.feature_id),
		"operator_id": operator_id, "recipient_id": recipient_id, "standard_id": standard_id, "standard_revision": int(standard.revision),
		"recipe_id": "bow", "max_batches": 1, "status": "awaiting_source", "source": {}, "receipt_ids": [], "accepted_receipts": [], "issued_item_ids": [], "reason": "", "work_consent": consent}
	if not valid_nation_operation_record(candidate, lab.terrain.site.item_definitions, {}): return Runtime.fail("INVALID")
	_publish_nation_operations(checked.nation, candidate)
	return Runtime.ok("已建立一批真弓生產／領裝訂單，尚未占人、扣料或自批來源", {"order_id": order_id})

func authorize_military_materials(grantor_id: int, nation_id: String, order_id: String, cap: Dictionary) -> Dictionary:
	var nation: Dictionary = lab.terrain.site.get("equipment_nations", {}).get(nation_id, {})
	var original: Dictionary = nation.get("technology_operations", {}).get("orders", {}).get(order_id, {})
	if original.is_empty() or original.status not in ["awaiting_source", "active"]: return Runtime.fail("NO_TARGET")
	var checked := _nation_operation_context(int(original.authorizer_id), nation_id, "nation.production", "N05", "workshop_bow")
	if not checked.ok: return checked
	if grantor_id != int(lab.controlled_person_id()): return Runtime.fail("NO_AUTHORITY", "只接受當前受控原人明示支出本人cargo")
	var person: Dictionary = actions._person(grantor_id)
	if person.is_empty() or not _ready(person).ok or not _operation_stack(cap) or cap.is_empty(): return Runtime.fail("INVALID")
	var candidate := _nation_operation_candidate(nation)
	var order: Dictionary = candidate.orders[order_id]
	var spent: Dictionary = {}
	if not order.source.is_empty():
		if int(order.source.person_id) != grantor_id or order.source.site_id != str(lab.terrain.site.id): return Runtime.fail("NO_AUTHORITY", "不能換人清零原來源累計支出")
		spent = order.source.spent.duplicate()
	order.source = {"site_id": str(lab.terrain.site.id), "person_id": grantor_id, "holder": "person:" + str(grantor_id), "status": "granted", "cap": cap.duplicate(), "spent": spent}
	order.status = "active"
	order.revision = int(order.revision) + 1
	if not valid_nation_operation_record(candidate, lab.terrain.site.item_definitions, {}): return Runtime.fail("INVALID", "只准一批原配方的有限上限，不能低於已交支出")
	_publish_nation_operations(nation, candidate)
	return Runtime.ok("本人已明示核准有限原材料用途；尚未移交或宣告營地國有")

func revoke_military_materials(grantor_id: int, nation_id: String, order_id: String) -> Dictionary:
	var nation: Dictionary = lab.terrain.site.get("equipment_nations", {}).get(nation_id, {})
	if not nation.has("technology_operations") or not valid_nation_operation_record(nation.technology_operations, lab.terrain.site.item_definitions, {}): return Runtime.fail("NO_TARGET")
	var candidate := _nation_operation_candidate(nation)
	var order: Dictionary = candidate.orders.get(order_id, {})
	if order.is_empty() or order.source.is_empty() or order.status not in ["awaiting_source", "active"]: return Runtime.fail("NO_TARGET")
	if grantor_id != int(lab.controlled_person_id()) or int(order.source.person_id) != grantor_id or actions._person(grantor_id).is_empty(): return Runtime.fail("NO_AUTHORITY")
	order.source.status = "revoked"
	order.revision = int(order.revision) + 1
	if not valid_nation_operation_record(candidate, lab.terrain.site.item_definitions, {}): return Runtime.fail("INVALID")
	_publish_nation_operations(nation, candidate)
	return Runtime.ok("本原來源已撤銷；已交原物資及累計支出保留，未完生产沿原守衛停用")

func supply_military_production(grantor_id: int, nation_id: String, order_id: String, resources: Dictionary, source_version: int, destination_version: int) -> Dictionary:
	var nation: Dictionary = lab.terrain.site.get("equipment_nations", {}).get(nation_id, {})
	if not nation.has("technology_operations") or not valid_nation_operation_record(nation.technology_operations, lab.terrain.site.item_definitions, {}): return Runtime.fail("NO_TARGET")
	var order: Dictionary = nation.technology_operations.orders.get(order_id, {})
	if order.is_empty() or order.source.is_empty() or order.source.status != "granted" or order.status != "active": return Runtime.fail("NO_BUDGET")
	if grantor_id != int(lab.controlled_person_id()) or int(order.source.person_id) != grantor_id or order.source.site_id != str(lab.terrain.site.id): return Runtime.fail("NO_AUTHORITY")
	var checked := _nation_operation_context(int(order.authorizer_id), nation_id, "nation.production", "N05", "workshop_bow")
	if not checked.ok: return checked
	var standard := _standard(int(order.recipient_id), nation_id, str(order.standard_id))
	if standard.is_empty() or int(standard.revision) != int(order.standard_revision) or not _nation_person_ok(nation, int(order.recipient_id)): return Runtime.fail("STALE_SPEC")
	var certificate := _certificate_context(nation, str(order.certificate_id), int(order.operator_id))
	if not certificate.ok or int(certificate.certificate.revision) != int(order.certificate_revision): return Runtime.fail("STALE_CERTIFICATE")
	var feature: Dictionary = certificate.workshop.feature
	if str(feature.get("supply_mode", "")) != "local" or Stockpiles.stock_endpoint(lab.terrain, str(order.feature_id)).is_empty(): return Runtime.fail("NO_SOURCE", "須先沿原入口啟用並指定該作坊現場供料")
	if not _operation_stack(resources) or resources.is_empty(): return Runtime.fail("INVALID")
	var candidate := _nation_operation_candidate(nation)
	Runtime.add_items(candidate.orders[order_id].source.spent, resources)
	if not valid_nation_operation_record(candidate, lab.terrain.site.item_definitions, {}): return Runtime.fail("NO_BUDGET", "超出原來源累計有限額度")
	var transport: Variant = _original_stock_transport()
	if transport == null: return Runtime.fail("UNSUPPORTED")
	var result: Dictionary = transport.transfer(str(order.source.holder), "feature:" + str(order.feature_id), resources, [], source_version, destination_version, grantor_id)
	if not result.ok: return result
	_publish_nation_operations(nation, candidate)
	return Runtime.ok("本人真材料已交原作坊；來源累計支出同次提交")

func military_order_admission(nation_id: String, order_id: String, feature_id: String, operator_id: int, inputs: Dictionary) -> Dictionary:
	var checked := military_work_preflight(nation_id, order_id)
	if not checked.ok: return checked
	var order: Dictionary = checked.order
	var feature: Dictionary = checked.feature
	if order.feature_id != feature_id or int(order.operator_id) != operator_id or feature.get("recipe_id") != "bow" \
		or not Technology.material_equal(inputs, Runtime.RANGED_RECIPES.bow.cost): return Runtime.fail("SPEC_MISMATCH")
	var at_slot := false
	for slot: Dictionary in Runtime.feature_work_slots(lab.terrain, feature):
		if lab.terrain.index(checked.person.cell) == int(slot.cell): at_slot = true
	if not at_slot: return Runtime.fail("UNREACHABLE", "原操作員須在本作坊真工位")
	return Runtime.ok("", {"order": order})

# _certificate_context receives optional read_only:bool=false as fourth arg;
# ONLY its original _nation_duty_ok(...,"nation.workshop") call forwards it.
# All former manual call sites retain their exact default behavior.
func prepare_military_output(nation_id: String, order_id: String, output_receipt: Dictionary) -> Dictionary:
	if not output_receipt.get("feature_id") is String or not _valid_output_receipt(output_receipt, str(lab.terrain.site.id), str(output_receipt.feature_id)) \
		or not _workshop_sample_matches(output_receipt, "S07"): return Runtime.fail("INVALID", "原出貨收據格式")
	var checked := military_order_admission(nation_id, order_id, str(output_receipt.feature_id), int(output_receipt.operator_id), Runtime.RANGED_RECIPES.bow.cost)
	if not checked.ok: return checked
	var nation: Dictionary = lab.terrain.site.equipment_nations[nation_id]
	var feature: Dictionary = lab.terrain.site.features[str(output_receipt.feature_id)]
	if int(feature.get("technology_output", {}).get("next_seq", -1)) != int(output_receipt.id) \
		or output_receipt.item_ids[0] != str(int(lab.terrain.site.next_item)): return Runtime.fail("STALE_SOURCE", "必須同一原批次與下一個原實物序號")
	var candidate := _nation_operation_candidate(nation)
	var order: Dictionary = candidate.orders[order_id]
	if order.receipt_ids.has(int(output_receipt.id)): return Runtime.fail("NO_CHANGE")
	order.receipt_ids.append(int(output_receipt.id))
	if int(candidate.version) == NATION_PUBLIC_VERSION: order.accepted_receipts.append(output_receipt.duplicate(true))
	order.status = "complete"
	order.revision = int(order.revision) + 1
	if not valid_nation_operation_record(candidate, lab.terrain.site.item_definitions, {}): return Runtime.fail("INVALID")
	if not _operations_candidate_claims_valid(nation_id, candidate): return Runtime.fail("REPLAY", "原出貨／實物已屬另一有限國家訂單")
	return Runtime.ok("", {"nation_ref": nation, "operations": candidate, "nation_id": nation_id, "order_id": order_id})

## Runtime calls only after all preflight and its original infallible product/
## receipt commit. No callback, authority decision or additional transaction here.
func publish_military_output(prepared: Dictionary) -> void:
	_publish_nation_operations(prepared.nation_ref, prepared.operations)

func renew_public_operation(requester_id: int, nation_id: String, order_id: String, expected_revision: int) -> Dictionary:
	if requester_id != int(lab.controlled_person_id()): return Runtime.fail("NO_AUTHORITY")
	var nation: Dictionary = lab.terrain.site.get("equipment_nations", {}).get(nation_id, {})
	if not nation.has("technology_operations") or not valid_nation_operation_record(nation.technology_operations, lab.terrain.site.item_definitions, {}): return Runtime.fail("CORRUPT_STATE")
	var original: Dictionary = nation.technology_operations.get("public_orders", {}).get(order_id, {})
	if original.is_empty() or original.status == "complete" or int(original.revision) != expected_revision: return Runtime.fail("STALE_ORDER")
	var binding_id: String = _public_first_binding(original)
	if original.tech_id in ["N02", "N10"] and original.receipts.size() == 1: binding_id = "road_build"
	elif original.tech_id == "N11" and original.receipts.size() == 1: binding_id = "arsenal"
	var context := _public_manual_context(requester_id, nation_id, str(original.tech_id), binding_id)
	if not context.ok: return context
	var candidate := _public_candidate(nation)
	var order: Dictionary = candidate.public_orders[order_id]
	if order.payload.has("consents"):
		var identities: Array = order.payload.get("person_ids", order.payload.get("worker_ids", []))
		if order.tech_id == "N10": identities = [int(order.payload.local_person_id)]
		elif order.tech_id == "N11": identities = [int(order.payload.operator_id)]
		var checked := _public_work_consents(identities, _public_purpose(order, order_id))
		if not checked.ok: return checked
		order.payload.consents = checked.consents
	if order.tech_id == "N10":
		if not _mandate_effective(original): return Runtime.fail("EXPIRED_MANDATE", "失效委任須新明示期限／現任聚落範圍，不借舊職位續命")
	if order.tech_id == "N12":
		var fleet := _fleet_context(nation, str(order.payload.corps_id), order.payload.ship_ids, requester_id)
		if not fleet.ok: return fleet
	order.authorizer_id = requester_id
	order.status = "active" if not order.receipts.is_empty() or not str(order.payload.get("feature_id", order.payload.get("target_id", ""))).is_empty() else "prepared"
	order.reason = ""
	order.revision = expected_revision + 1
	if not valid_nation_operation_record(candidate, lab.terrain.site.item_definitions, {}): return Runtime.fail("INVALID")
	_publish_nation_operations(nation, candidate)
	return Runtime.ok("現任者重新核准原單；原來源／支出／產品／收據與project引用保留")

func public_work_admission(nation_id: String, order_id: String, operator_id: int, target_id: String) -> Dictionary:
	var nation: Dictionary = lab.terrain.site.get("equipment_nations", {}).get(nation_id, {})
	if not nation.has("technology_operations") or not valid_nation_operation_record(nation.technology_operations, lab.terrain.site.item_definitions, {}): return Runtime.fail("CORRUPT_STATE")
	var order: Dictionary = nation.technology_operations.get("public_orders", {}).get(order_id, {})
	if order.is_empty() or order.tech_id not in ["N02", "N06", "N10", "N11"]: return Runtime.fail("NO_TARGET")
	var binding_id := "house_build" if order.tech_id == "N06" else "road_build"
	if order.tech_id == "N11": binding_id = "ballista_build" if order.payload.route == "siege" else "iron_armor"
	var context := _public_context(nation_id, order_id, binding_id)
	if not context.ok: return context
	var expected := "feature:" + str(order.payload.get("feature_id", ""))
	var identities: Array = order.payload.get("person_ids", order.payload.get("worker_ids", []))
	if order.tech_id == "N10":
		identities = [int(order.payload.local_person_id)]
		if not _mandate_effective(order): return Runtime.fail("EXPIRED_MANDATE")
	elif order.tech_id == "N11":
		identities = [int(order.payload.operator_id)]
		expected = str(order.payload.target_id)
	if not identities.has(operator_id) or expected != target_id: return Runtime.fail("NO_WORKER")
	if order.payload.has("source") and not _public_source_paid(order): return Runtime.fail("NO_BUDGET")
	var person: Dictionary = actions._person(operator_id)
	if person.is_empty() or float(person.hp) <= 0.0 or float(person.ko) > 0.0 or bool(person.captive): return Runtime.fail("NO_WORKER")
	return Runtime.ok("", {"order": order})

static func _validate_public_nation_orders(data: TerrainData, state: Dictionary, nation: Dictionary, _people: Dictionary, _receipt_lookup: Callable) -> Dictionary:
	var operations: Dictionary = nation.technology_operations
	var project_orders := {}
	for order_id: String in operations.public_orders:
		var order: Dictionary = operations.public_orders[order_id]
		var payload: Dictionary = order.payload
		if order.scope_site_id != str(state.id): return Runtime.fail("CORRUPT_SAVE", "原國家用途Site")
		if int(order.project_id) > 0:
			var found := false
			for project: Dictionary in nation.technology.projects:
				if int(project.id) == int(order.project_id) and project.tech_id == order.tech_id: found = true
			var purpose_key := str(order.tech_id) + ":" + str(int(order.project_id))
			if not found or project_orders.has(purpose_key): return Runtime.fail("CORRUPT_SAVE", "首次目的必須唯一原項目／原操作單")
			project_orders[purpose_key] = true
		# Accepted receipts are the bounded immutable history of this original
		# order. Effectiveness/current offices/hosts are checked by live admission.
		if payload.has("reserve_feature_id"):
			var reserve: Dictionary = state.features.get(str(payload.reserve_feature_id), {})
			if not reserve.is_empty() and (str(reserve.get("kind", "")) != "warehouse" or not state.get("stockpiles", {}).has(payload.reserve_feature_id)): return Runtime.fail("CORRUPT_SAVE", "有限原糧／材料儲引用")
		if payload.has("source") and not payload.source.is_empty() and payload.source.site_id != str(state.id): return Runtime.fail("CORRUPT_SAVE", "私人物資來源Site")
		if order.tech_id in ["N02", "N06", "N10"]:
			if not payload.feature_id.is_empty():
				var feature: Dictionary = state.features.get(str(payload.feature_id), {})
				if not feature.is_empty() and str(feature.get("kind", "")) != ("house" if order.tech_id == "N06" else "road"): return Runtime.fail("CORRUPT_SAVE", "本單原公共工程")
		elif order.tech_id == "N08":
			if payload.route_ref.source_site_id != str(state.id) or payload.route_ref.destination_site_id != payload.destination_site_id or payload.route_ref.route_id != payload.route_id: return Runtime.fail("CORRUPT_SAVE", "原公共跨地路線身分")
			for receipt: Dictionary in order.receipts:
				var expected_ref: Dictionary = state.get("travel_identity", {}).get("refs", {}).get("person", {}).get(str(int(payload.driver_id)), {})
				if expected_ref.is_empty() or receipt.operator_reference != expected_ref or int(receipt.source_operator_id) != int(payload.driver_id) \
					or receipt.transfer_token != payload.travel_token: return Runtime.fail("CORRUPT_SAVE", "公共運輸收據須引用同原 Source driver typed PersonRef／token")
			# Departure archive can remove the source vehicle; the original route
			# pin/token remains history and Region validates travel separately.
		elif order.tech_id == "N11":
			if payload.route == "armor":
				var host: Dictionary = state.features.get(str(payload.host_id), {})
				if not host.is_empty() and str(host.get("kind", "")) != "smithy": return Runtime.fail("CORRUPT_SAVE", "原甲冑作坊")
				for receipt: Dictionary in order.receipts:
					var item: Dictionary = state.get("item_records", {}).get(str(receipt.item_ids[0]), {})
					if not item.is_empty() and str(item.get("definition", "")) != "armor:armor_iron_01": return Runtime.fail("CORRUPT_SAVE", "甲冑收据必須是同原真鐵甲產品")
		elif order.tech_id == "N12":
			for identity: String in payload.ship_ids:
				var ship: Dictionary = state.get("vehicles", {}).get(identity, {})
				if not ship.is_empty() and not SiteVehicleTransport.is_ship(ship): return Runtime.fail("CORRUPT_SAVE", "原兩船種類")
			for identity: String in payload.steps:
				var step: Dictionary = payload.steps[identity]
				if int(step.from_cell) >= data.size.x * data.size.y or int(step.to_cell) >= data.size.x * data.size.y \
					or absi(data.cell_from_index(int(step.from_cell)).x - data.cell_from_index(int(step.to_cell)).x) + absi(data.cell_from_index(int(step.from_cell)).y - data.cell_from_index(int(step.to_cell)).y) != 1:
					return Runtime.fail("CORRUPT_SAVE", "原編制船步")
		for receipt: Dictionary in order.receipts:
			if order.tech_id in ["N03", "N09"]:
				var target: String = str(receipt.target_id)
				if order.tech_id == "N03":
					var accepted := false
					for identity: Variant in payload.recipient_ids:
						if target == "person:" + str(int(identity)) and int(receipt.operator_id) == int(identity): accepted = true
					if not accepted or not receipt.item_ids.is_empty(): return Runtime.fail("CORRUPT_SAVE", "原賑濟接收者／真糧")
				elif target != "feature:" + str(payload.reserve_feature_id) and target != "person:" + str(int(payload.recipient_id)): return Runtime.fail("CORRUPT_SAVE", "本單真徵收／支出")
				if payload.source.is_empty() or int(payload.source.spent.get("grain", 0)) < (4 if order.tech_id == "N03" else 1): return Runtime.fail("CORRUPT_SAVE", "原有限糧源尚未真交足")
			elif order.tech_id == "N12":
				var identity := str(receipt.target_id).trim_prefix("vehicle:")
				if receipt.target_id != "vehicle:" + identity or not payload.steps.has(identity) or int(receipt.operator_id) != int(payload.steps[identity].driver_id): return Runtime.fail("CORRUPT_SAVE", "本單原舵手船步")
			# Other exact7 histories were admitted against the true producer at
			# acceptance. A completed transient PA job is not a second save owner.
	return Runtime.ok()


func _military_order_products(order: Dictionary) -> Array[String]:
	var result: Array[String] = []
	if order.has("accepted_receipts"):
		for receipt: Dictionary in order.accepted_receipts:
			for item_id: String in receipt.item_ids:
				if not result.has(item_id): result.append(item_id)
		return result
	for receipt_id: Variant in order.receipt_ids:
		var receipt := _output_receipt(str(order.feature_id), int(receipt_id))
		for item_id: String in receipt.get("item_ids", []):
			if not result.has(item_id): result.append(item_id)
	return result

func begin_military_issue(requester_id: int, nation_id: String, order_id: String) -> Dictionary:
	if requester_id != int(lab.controlled_person_id()): return Runtime.fail("NO_AUTHORITY", "新具名制度命令須由當前受控原職責行使者明示")
	var nation: Dictionary = lab.terrain.site.get("equipment_nations", {}).get(nation_id, {})
	if not nation.has("technology_operations") or not valid_nation_operation_record(nation.technology_operations, lab.terrain.site.item_definitions, {}): return Runtime.fail("NO_TARGET")
	var order: Dictionary = nation.technology_operations.orders.get(order_id, {})
	if order.is_empty() or order.status != "complete": return Runtime.fail("NO_TARGET", "先完成真生產；已交付訂單不重發")
	var checked := _nation_operation_context(requester_id, nation_id, "nation.production", "N05", "issue_bow")
	if not checked.ok: return checked
	return actions.begin_equipment(int(order.recipient_id), {"mode": "issue", "nation_id": nation_id,
		"standard_id": str(order.standard_id), "military_production_id": order_id})

static func _valid_workshop_certificate(raw: Variant, people: Dictionary, retained: bool = false) -> bool:
	var fields := ["revision", "authorizer_id", "settlement_id", "feature_id", "industry_id", "operator_id", "receipt_id", "status", "reason"]
	if retained: fields.append("accepted_receipt")
	if not (Technology.keys(raw, fields) \
		and Technology.integer(raw.revision, 1) and _operation_person(raw.authorizer_id, people) and _operation_person(raw.operator_id, people) \
		and raw.settlement_id is String and not raw.settlement_id.is_empty() and raw.settlement_id.length() <= 96 \
		and _operation_key(raw.feature_id) and raw.industry_id in ["S04", "S05", "S07"] and Technology.integer(raw.receipt_id, 1) \
		and raw.status in ["active", "revoked"] and raw.reason is String and str(raw.reason).length() <= 256 \
		and (raw.reason.is_empty() if raw.status == "active" else not raw.reason.is_empty())): return false
	return not retained or raw.accepted_receipt is Dictionary \
		and _valid_output_receipt(raw.accepted_receipt, str(raw.accepted_receipt.get("site_id", "")), str(raw.feature_id)) \
		and int(raw.accepted_receipt.id) == int(raw.receipt_id) and int(raw.accepted_receipt.operator_id) == int(raw.operator_id) \
		and _workshop_sample_matches(raw.accepted_receipt, str(raw.industry_id))

static func _valid_military_source(raw: Variant, people: Dictionary) -> bool:
	if not Technology.keys(raw, ["site_id", "person_id", "holder", "status", "cap", "spent"]) or not Technology.valid_ref({"site_id": raw.site_id, "person_id": raw.person_id}) \
		or not _operation_person(raw.person_id, people) or raw.holder != "person:" + str(int(raw.person_id)) or raw.status not in ["granted", "revoked"] \
		or not _operation_stack(raw.cap) or raw.cap.is_empty() or not _operation_stack(raw.spent, true): return false
	var maximum: Dictionary = Runtime.RANGED_RECIPES.bow.cost
	for resource: String in raw.cap:
		if not maximum.has(resource) or int(raw.cap[resource]) > int(maximum[resource]): return false
	for resource: String in raw.spent:
		if not raw.cap.has(resource) or int(raw.spent[resource]) > int(raw.cap[resource]): return false
	return true

static func _valid_military_order(raw: Variant, certificates: Dictionary, people: Dictionary, retained: bool = false) -> bool:
	var fields := ["revision", "authorizer_id", "certificate_id", "certificate_revision", "feature_id", "operator_id", "recipient_id", "standard_id", "standard_revision", "recipe_id", "max_batches", "status", "source", "receipt_ids", "issued_item_ids", "reason", "work_consent"]
	if retained: fields.append("accepted_receipts")
	if not Technology.keys(raw, fields) \
		or not Technology.integer(raw.revision, 1) or not _operation_person(raw.authorizer_id, people) or not _operation_person(raw.operator_id, people) or not _operation_person(raw.recipient_id, people) \
		or not _operation_key(raw.certificate_id) or not certificates.has(raw.certificate_id) or not Technology.integer(raw.certificate_revision, 1) \
		or not _operation_key(raw.feature_id) or raw.feature_id != certificates[raw.certificate_id].feature_id or certificates[raw.certificate_id].industry_id != "S07" \
		or not _valid_key(str(raw.standard_id)) or not raw.standard_id is String or not Technology.integer(raw.standard_revision, 1) or raw.recipe_id != "bow" \
		or not Technology.integer(raw.max_batches, 1, 1) or raw.status not in ["awaiting_source", "active", "complete", "issued", "cancelled"] \
		or not raw.source is Dictionary or not raw.receipt_ids is Array or raw.receipt_ids.size() > 1 or not raw.issued_item_ids is Array or raw.issued_item_ids.size() > 1 \
		or not raw.reason is String or str(raw.reason).length() > 256 or not raw.work_consent is Dictionary: return false
	if not raw.source.is_empty() and not _valid_military_source(raw.source, people): return false
	if raw.status in ["active", "complete", "issued"] and raw.source.is_empty(): return false
	if raw.status in ["awaiting_source", "active"] and not raw.receipt_ids.is_empty(): return false
	if raw.status in ["complete", "issued"] and raw.receipt_ids.size() != 1: return false
	for receipt_id: Variant in raw.receipt_ids:
		if not Technology.integer(receipt_id, 1): return false
	if retained:
		if not raw.accepted_receipts is Array or raw.accepted_receipts.size() != raw.receipt_ids.size(): return false
		for index: int in range(raw.accepted_receipts.size()):
			var receipt: Variant = raw.accepted_receipts[index]
			if not receipt is Dictionary or not _valid_output_receipt(receipt, str(receipt.get("site_id", "")), str(raw.feature_id)) \
				or int(receipt.id) != int(raw.receipt_ids[index]) or int(receipt.operator_id) != int(raw.operator_id) \
				or not _workshop_sample_matches(receipt, "S07"): return false
	for item_id: Variant in raw.issued_item_ids:
		if not item_id is String or not item_id.is_valid_int() or str(int(item_id)) != item_id or not Technology.integer(int(item_id), 1): return false
	if raw.status == "issued" and raw.issued_item_ids.size() != 1 or raw.status != "issued" and not raw.issued_item_ids.is_empty(): return false
	if retained and not raw.issued_item_ids.is_empty() and raw.issued_item_ids != raw.accepted_receipts[0].item_ids: return false
	if not raw.receipt_ids.is_empty():
		if raw.source.is_empty(): return false
		for resource: String in Runtime.RANGED_RECIPES.bow.cost:
			if int(raw.source.spent.get(resource, 0)) < int(Runtime.RANGED_RECIPES.bow.cost[resource]): return false
	if not raw.work_consent.is_empty():
		var consent: Dictionary = raw.work_consent
		if not Technology.keys(consent, ["site_id", "team_id", "person_id", "purpose", "decider_id", "revision", "status"]) \
			or not Technology.valid_ref({"site_id": consent.site_id, "person_id": consent.person_id}) or not Technology.integer(consent.team_id, 1) or consent.person_id != raw.operator_id \
			or not consent.purpose is String or str(consent.purpose).is_empty() or not _operation_person(consent.decider_id, people) \
			or not Technology.integer(consent.revision, 0) or consent.status != "accepted": return false
	return true

static func valid_nation_operation_record(raw: Variant, definitions: Dictionary, people: Dictionary) -> bool:
	var extended := raw is Dictionary and Technology.integer(raw.get("version"), NATION_PUBLIC_VERSION, NATION_PUBLIC_VERSION)
	var fields := ["version", "next_seq", "specs", "certificates", "orders"]
	if extended: fields.append("public_orders")
	if not Technology.keys(raw, fields) or not (Technology.integer(raw.version, NATION_OPERATIONS_VERSION, NATION_OPERATIONS_VERSION) or extended) \
		or not Technology.integer(raw.next_seq, 1) or not raw.specs is Dictionary or not raw.certificates is Dictionary or not raw.orders is Dictionary \
		or raw.specs.size() > NATION_OPERATIONS_MAX or raw.certificates.size() > NATION_OPERATIONS_MAX or raw.orders.size() > NATION_OPERATIONS_MAX: return false
	if extended and (not raw.public_orders is Dictionary or raw.public_orders.size() > NATION_OPERATIONS_MAX): return false
	for identity: Variant in raw.specs:
		if not _operation_key(identity) or not _valid_procurement_spec(raw.specs[identity], definitions, people): return false
	for identity: Variant in raw.certificates:
		if not _operation_key(identity) or not _valid_workshop_certificate(raw.certificates[identity], people, extended): return false
	var receipts: Dictionary = {}
	for identity: Variant in raw.orders:
		if not identity is String or not str(identity).begins_with("production_"): return false
		var serial := str(identity).trim_prefix("production_")
		if not serial.is_valid_int() or str(int(serial)) != serial or not Technology.integer(int(serial), 1, int(raw.next_seq) - 1) \
			or not _valid_military_order(raw.orders[identity], raw.certificates, people, extended): return false
		var order: Dictionary = raw.orders[identity]
		if not order.work_consent.is_empty():
			if order.work_consent.purpose != "N05:" + str(identity) and (not extended or not _valid_nation_order_purpose(order.work_consent.purpose, "N05", str(order.work_consent.site_id), str(identity))): return false
		for receipt_id: Variant in order.receipt_ids:
			var key := str(order.feature_id) + ":" + str(int(receipt_id))
			if receipts.has(key): return false # The same original product cannot fulfil two orders.
			receipts[key] = true
	if extended:
		for identity: Variant in raw.public_orders:
			if not identity is String or not identity.begins_with("public_"): return false
			var serial := str(identity).trim_prefix("public_")
			if not serial.is_valid_int() or str(int(serial)) != serial or not Technology.integer(int(serial), 1, int(raw.next_seq) - 1) \
				or raw.orders.has("production_" + serial) or not _valid_public_order(raw.public_orders[identity], people, raw.public_orders, str(identity)): return false
			for receipt: Dictionary in raw.public_orders[identity].receipts:
				if receipts.has(receipt.id): return false
				receipts[receipt.id] = true
	return true

## SiteStore calls after original feature/holder/person validation. This only
## validates references and histories; effectiveness stays a live original query.
static func validate_nation_operations(_data: TerrainData, state: Dictionary, people: Dictionary, receipt_lookup: Callable = Callable()) -> Dictionary:
	if not state.get("equipment_nations", {}) is Dictionary or not state.get("features", {}) is Dictionary \
		or not state.get("item_definitions", {}) is Dictionary or not state.get("stockpiles", {}) is Dictionary or not valid_organization_refs(state): return Runtime.fail("CORRUPT_SAVE")
	people = people.duplicate()
	for identity: String in state.get("organization_refs", {}).get("remote_people", {}): people[int(identity)] = true
	for nation: Variant in state.get("equipment_nations", {}).values():
		if not nation is Dictionary: return Runtime.fail("CORRUPT_SAVE")
		if nation.has("technology") and (not Technology.valid_scope_record(nation.technology, "nation") or nation.technology.holder_site_id != str(state.get("id", ""))): return Runtime.fail("CORRUPT_SAVE", "原國家科技本地歸屬")
		if not nation.has("technology_operations"): continue
		if not nation.has("technology") or not Technology.valid_scope_record(nation.technology, "nation") or nation.technology.holder_site_id != str(state.id) \
			or not valid_nation_operation_record(nation.technology_operations, state.item_definitions, people): return Runtime.fail("CORRUPT_SAVE", "原國家科技／操作版本或本地歸屬")
		var operations: Dictionary = nation.technology_operations
		for spec: Dictionary in operations.specs.values():
			var feature: Dictionary = state.features.get(str(spec.destination_feature_id), {})
			if str(feature.get("kind", "")) != "warehouse" or not state.get("stockpiles", {}).has(spec.destination_feature_id): return Runtime.fail("CORRUPT_SAVE", "原採購倉庫引用")
		for certificate: Dictionary in operations.certificates.values():
			if int(operations.version) == NATION_PUBLIC_VERSION:
				if certificate.accepted_receipt.site_id != str(state.id): return Runtime.fail("CORRUPT_SAVE", "原驗收出貨Site")
				continue # The strict accepted body survives host removal/next output.
			var feature: Dictionary = state.features.get(str(certificate.feature_id), {})
			if feature.is_empty():
				if certificate.status == "revoked": continue # A revoked history need not keep a destroyed host.
				return Runtime.fail("CORRUPT_SAVE", "原作坊引用")
			if str(feature.get("kind", "")) != {"S04": "smithy", "S05": "weaver", "S07": "smithy"}[certificate.industry_id]: return Runtime.fail("CORRUPT_SAVE", "原作坊產業／host")
			var output: Variant = feature.get("technology_output")
			if not output is Dictionary or not output.get("receipts") is Array: return Runtime.fail("CORRUPT_SAVE", "原作坊出貨記錄")
			var found := false
			for receipt: Variant in output.receipts:
				if not _valid_output_receipt(receipt, str(state.id), str(certificate.feature_id)): return Runtime.fail("CORRUPT_SAVE")
				if int(receipt.id) == int(certificate.receipt_id) and int(receipt.operator_id) == int(certificate.operator_id) and _workshop_sample_matches(receipt, str(certificate.industry_id)): found = true
			if not found or str(certificate.settlement_id) != str(state.get("settlement", {}).get("settlement_id", "")): return Runtime.fail("CORRUPT_SAVE", "原作坊驗收實績／聚落身分")
		for order_id: String in operations.orders:
			var order: Dictionary = operations.orders[order_id]
			if int(operations.version) == NATION_OPERATIONS_VERSION and (not nation.standards.has(order.standard_id) or not _member(nation, int(order.recipient_id))): return Runtime.fail("CORRUPT_SAVE", "軍需標準／原接收國民")
			if not order.source.is_empty() and order.source.site_id != str(state.id): return Runtime.fail("CORRUPT_SAVE", "有限來源不在原Site")
			if int(operations.version) == NATION_PUBLIC_VERSION:
				for receipt: Dictionary in order.accepted_receipts:
					if receipt.site_id != str(state.id): return Runtime.fail("CORRUPT_SAVE", "原軍需出貨Site")
				continue # item_records/holder alone continue to own existing items.
			var feature: Dictionary = state.features.get(str(order.feature_id), {})
			if feature.is_empty():
				if order.status == "cancelled" and order.receipt_ids.is_empty(): continue
				return Runtime.fail("CORRUPT_SAVE", "軍需原作坊引用")
			var output: Variant = feature.get("technology_output", {})
			if not output is Dictionary or not output.get("receipts", []) is Array: return Runtime.fail("CORRUPT_SAVE")
			var products: Array = []
			for receipt_id: Variant in order.receipt_ids:
				var found := false
				for receipt: Variant in output.get("receipts", []):
					if not _valid_output_receipt(receipt, str(state.id), str(order.feature_id)): return Runtime.fail("CORRUPT_SAVE")
					if int(receipt.id) == int(receipt_id) and int(receipt.operator_id) == int(order.operator_id) and _workshop_sample_matches(receipt, "S07"):
						found = true
						products.append(receipt.item_ids[0])
				if not found: return Runtime.fail("CORRUPT_SAVE", "軍需完成必須引用同原作坊／操作者的真出貨")
			for item_id: String in order.issued_item_ids:
				if not products.has(item_id): return Runtime.fail("CORRUPT_SAVE", "軍需領裝不是本原出貨")
		if operations.has("public_orders"):
			var public_check := _validate_public_nation_orders(_data, state, nation, people, receipt_lookup)
			if not public_check.ok: return public_check
	if not _site_operation_claims_valid(state): return Runtime.fail("CORRUPT_SAVE", "同一原收據／產品／具名同意不可跨國重放")
	return Runtime.ok()

static func normalize_nation_operations(state: Dictionary) -> Dictionary:
	var nations: Variant = state.get("equipment_nations", {})
	if not nations is Dictionary or not state.get("item_definitions", {}) is Dictionary: return Runtime.fail("CORRUPT_STATE")
	for nation: Variant in nations.values():
		if not nation is Dictionary or nation.has("technology") and not Technology.valid_scope_record(nation.technology, "nation") \
			or nation.has("technology_operations") and not valid_nation_operation_record(nation.technology_operations, state.get("item_definitions", {}), {}): return Runtime.fail("CORRUPT_STATE")
	for nation: Dictionary in state.get("equipment_nations", {}).values():
		if nation.has("technology"): nation.technology = Technology.normalize_scope_record(nation.technology, "nation")
		if not nation.has("technology_operations"): continue
		var operations: Dictionary = nation.technology_operations
		operations.version = int(operations.version)
		operations.next_seq = int(operations.next_seq)
		for spec: Dictionary in operations.specs.values():
			spec.revision = int(spec.revision)
			spec.authorizer_id = int(spec.authorizer_id)
			for limits: Dictionary in spec.resources.values():
				limits.batch = int(limits.batch)
				limits.total = int(limits.total)
			for requirement: Dictionary in spec.items.values():
				requirement.batch = int(requirement.batch)
				requirement.total = int(requirement.total)
			for receipt: Dictionary in spec.receipts:
				receipt.source_person_id = int(receipt.source_person_id)
				for resource: String in receipt.resources: receipt.resources[resource] = int(receipt.resources[resource])
		for certificate: Dictionary in operations.certificates.values():
			for field: String in ["revision", "authorizer_id", "operator_id", "receipt_id"]: certificate[field] = int(certificate[field])
			if certificate.has("accepted_receipt"): _normalize_accepted_output(certificate.accepted_receipt)
		for order: Dictionary in operations.orders.values():
			for field: String in ["revision", "authorizer_id", "certificate_revision", "operator_id", "recipient_id", "standard_revision", "max_batches"]: order[field] = int(order[field])
			for index: int in range(order.receipt_ids.size()): order.receipt_ids[index] = int(order.receipt_ids[index])
			for receipt: Dictionary in order.get("accepted_receipts", []): _normalize_accepted_output(receipt)
			if not order.source.is_empty():
				order.source.person_id = int(order.source.person_id)
				for resource: String in order.source.cap: order.source.cap[resource] = int(order.source.cap[resource])
				for resource: String in order.source.spent: order.source.spent[resource] = int(order.source.spent[resource])
			if not order.work_consent.is_empty():
				for field: String in ["team_id", "person_id", "decider_id", "revision"]: order.work_consent[field] = int(order.work_consent[field])
		for order: Dictionary in operations.get("public_orders", {}).values(): _normalize_public_order(order)
	return Runtime.ok()

static func _normalize_accepted_output(receipt: Dictionary) -> void:
	receipt.id = int(receipt.id)
	receipt.operator_id = int(receipt.operator_id)
	receipt.work_seconds = float(receipt.work_seconds)
	for resource: String in receipt.resources: receipt.resources[resource] = int(receipt.resources[resource])

func _military_issue_check(order: Dictionary) -> Dictionary:
	if not order.has("military_production_id"): return Runtime.ok()
	var nation: Dictionary = lab.terrain.site.get("equipment_nations", {}).get(str(order.nation_id), {})
	if not nation.has("technology_operations") or not valid_nation_operation_record(nation.technology_operations, lab.terrain.site.item_definitions, {}): return Runtime.fail("STALE_ORDER")
	var production: Dictionary = nation.technology_operations.orders.get(str(order.military_production_id), {})
	if production.is_empty() or production.status != "complete" or int(production.recipient_id) != int(order.person_id) \
		or str(production.standard_id) != str(order.standard_id) or int(production.standard_revision) != int(order.standard_revision):
		return Runtime.fail("STALE_ORDER")
	if int(production.revision) >= 2147483646: return Runtime.fail("INVALID", "原訂單提交版本已用盡")
	var permitted := _nation_operation_context(int(production.authorizer_id), str(order.nation_id), "nation.production", "N05", "issue_bow")
	if not permitted.ok: return permitted
	var products := _military_order_products(production)
	if products.size() != 1 or production.issued_item_ids.has(products[0]) or not order.take.has(products[0]) \
		or order.planned.get("weapon") != products[0]: return Runtime.fail("MATERIALS", "本次原領裝只驗本訂單真弓，須先沿原装卸移交到營地")
	var standard := _standard(int(order.person_id), str(order.nation_id), str(order.standard_id))
	if standard.is_empty() or int(standard.revision) != int(production.standard_revision): return Runtime.fail("STALE_SPEC")
	return Runtime.ok("", {"production": production, "nation": nation, "product": products[0]})

func _publish_military_issue(checked: Dictionary) -> void:
	if not checked.has("production"): return
	checked.production.issued_item_ids.append(str(checked.product))
	checked.production.status = "issued"
	checked.production.revision = int(checked.production.revision) + 1

func renew_military_production_order(requester_id: int, nation_id: String, order_id: String, expected_revision: int) -> Dictionary:
	if requester_id != int(lab.controlled_person_id()): return Runtime.fail("NO_AUTHORITY", "新具名制度命令須由當前受控原職責行使者明示")
	var nation: Dictionary = lab.terrain.site.get("equipment_nations", {}).get(nation_id, {})
	if not nation.has("technology_operations") or not valid_nation_operation_record(nation.technology_operations, lab.terrain.site.item_definitions, {}): return Runtime.fail("NO_TARGET")
	var original: Dictionary = nation.technology_operations.orders.get(order_id, {})
	if original.is_empty() or original.status in ["issued", "cancelled"] or int(original.revision) != expected_revision or expected_revision >= 2147483646: return Runtime.fail("STALE_ORDER")
	var checked := _nation_operation_context(requester_id, nation_id, "nation.production", "N05", "issue_bow" if original.status == "complete" else "workshop_bow")
	if not checked.ok: return checked
	var certificate := _certificate_context(nation, str(original.certificate_id), int(original.operator_id))
	if not certificate.ok: return certificate
	var standard := _standard(int(original.recipient_id), nation_id, str(original.standard_id))
	if standard.is_empty() or not standard.slots.has("weapon") or "weapon:bow_01" not in [standard.slots.weapon.definition] + standard.slots.weapon.alternatives: return Runtime.fail("SPEC_MISMATCH")
	var candidate := _public_candidate(nation)
	var order: Dictionary = candidate.orders[order_id]
	if order.status != "complete":
		var team: Variant = actions._technology_team(actions._person(int(order.operator_id)))
		if team != null:
			if not team.has_method("technology_work_consent"): return Runtime.fail("UNSUPPORTED")
			var response: Dictionary = team.technology_work_consent(int(order.operator_id), _nation_order_purpose("N05", str(lab.terrain.site.id), nation_id, order_id), int(lab.controlled_person_id()))
			if not response.ok: return response
			order.work_consent = response.consent.duplicate(true)
		else: order.work_consent = {}
	order.authorizer_id = requester_id
	order.certificate_revision = int(certificate.certificate.revision)
	order.standard_revision = int(standard.revision)
	order.revision = expected_revision + 1
	if not valid_nation_operation_record(candidate, lab.terrain.site.item_definitions, {}): return Runtime.fail("INVALID")
	_publish_nation_operations(nation, candidate)
	return Runtime.ok("現任者已重新核准本原訂單；來源、累計支出、成品及收據保留")

func cancel_military_production_order(requester_id: int, nation_id: String, order_id: String, expected_revision: int, reason: String) -> Dictionary:
	if requester_id != int(lab.controlled_person_id()): return Runtime.fail("NO_AUTHORITY", "新具名制度命令須由當前受控原職責行使者明示")
	var nation: Dictionary = lab.terrain.site.get("equipment_nations", {}).get(nation_id, {})
	if not nation.has("technology_operations") or not valid_nation_operation_record(nation.technology_operations, lab.terrain.site.item_definitions, {}): return Runtime.fail("NO_TARGET")
	var original: Dictionary = nation.technology_operations.orders.get(order_id, {})
	if original.is_empty() or original.status in ["issued", "cancelled"] or int(original.revision) != expected_revision or expected_revision >= 2147483646: return Runtime.fail("STALE_ORDER")
	if not _nation_duty_ok(requester_id, nation, "nation.production"): return Runtime.fail("NO_AUTHORITY")
	if reason.is_empty() or reason.length() > 256: return Runtime.fail("INVALID")
	var feature: Dictionary = lab.terrain.site.get("features", {}).get(str(original.feature_id), {})
	if Runtime._feature_has_work(lab.terrain, str(original.feature_id)) or bool(feature.get("batch_paid", false)) or float(feature.get("production", 0.0)) > 0.0:
		return Runtime.fail("BUSY", "先沿原派工入口安全停止並完成／領出已付批次；不偷偷取消、退料或重置支出")
	var candidate := _nation_operation_candidate(nation)
	candidate.orders[order_id].status = "cancelled"
	candidate.orders[order_id].reason = reason
	candidate.orders[order_id].revision = expected_revision + 1
	if not valid_nation_operation_record(candidate, lab.terrain.site.item_definitions, {}): return Runtime.fail("INVALID")
	_publish_nation_operations(nation, candidate)
	return Runtime.ok("原訂單已取消；原現場物資、成品和支出歷史保留")

# v2 extends the SAME original nation operations; v1 remains an exact old packet.
# This is order/provenance data. Original people, cargo, jobs and clocks stay put.
func _public_candidate(nation: Dictionary) -> Dictionary:
	var candidate := _nation_operation_candidate(nation)
	if int(candidate.version) == NATION_OPERATIONS_VERSION:
		candidate.version = NATION_PUBLIC_VERSION
		candidate.public_orders = {}
		# Hydrate only evidence still present in its ORIGINAL producer. A missing
		# legacy witness leaves a strict-invalid candidate; never invent history.
		for certificate: Dictionary in candidate.certificates.values():
			var receipt := _output_receipt(str(certificate.feature_id), int(certificate.receipt_id))
			if not receipt.is_empty(): certificate.accepted_receipt = receipt.duplicate(true)
		for order: Dictionary in candidate.orders.values():
			order.accepted_receipts = []
			for receipt_id: Variant in order.receipt_ids:
				var receipt := _output_receipt(str(order.feature_id), int(receipt_id))
				if not receipt.is_empty(): order.accepted_receipts.append(receipt.duplicate(true))
	return candidate

static func _nation_order_purpose(tech_id: String, site_id: String, nation_id: String, order_id: String) -> String:
	return tech_id + ":" + JSON.stringify([site_id, nation_id, order_id])

static func _valid_nation_order_purpose(value: Variant, tech_id: String, site_id: String, order_id: String) -> bool:
	if not value is String or not value.begins_with(tech_id + ":"): return false
	var parsed: Variant = JSON.parse_string(value.trim_prefix(tech_id + ":"))
	return parsed is Array and parsed.size() == 3 and parsed[0] == site_id and _public_reference(parsed[1]) and parsed[2] == order_id \
		and value == _nation_order_purpose(tech_id, site_id, str(parsed[1]), order_id)

static func _public_purpose(order: Dictionary, order_id: String) -> String:
	return _nation_order_purpose(str(order.tech_id), str(order.scope_site_id), str(order.scope_nation_id), order_id)

static func _public_event_id(order: Dictionary, order_id: String, action: String, target: String) -> String:
	return JSON.stringify([str(order.scope_site_id), str(order.scope_nation_id), order_id, action, target])

static func _public_order_target(order: Dictionary, order_id: String) -> String:
	return "order:" + JSON.stringify([str(order.scope_site_id), str(order.scope_nation_id), order_id])

static func _nation_order_scope_valid(nation: Dictionary, nation_id: String, site_id: String) -> bool:
	var operations: Dictionary = nation.get("technology_operations", {})
	if not _procurement_trial_scope_valid(nation, nation_id, site_id): return false
	for order_id: String in operations.get("public_orders", {}):
		var order: Dictionary = operations.public_orders[order_id]
		if order.scope_nation_id != nation_id or order.scope_site_id != site_id: return false
	for order_id: String in operations.get("orders", {}):
		var consent: Dictionary = operations.orders[order_id].work_consent
		if consent.is_empty(): continue
		if consent.site_id != site_id or consent.purpose not in ["N05:" + order_id, _nation_order_purpose("N05", site_id, nation_id, order_id)]: return false
	return true

## Pure whole-original-Site claim check, including old unambiguous v1 consents.
## Separate newly executed transfers use nationally namespaced event IDs.
static func _site_operation_claims_valid(state: Dictionary) -> bool:
	if not state.get("equipment_nations", {}) is Dictionary or not state.get("item_definitions", {}) is Dictionary: return false
	var claims := {}
	var consent_claims := {}
	var product_claims := {}
	for nation_id: Variant in state.get("equipment_nations", {}):
		var raw: Variant = state.equipment_nations[nation_id]
		if not nation_id is String or not raw is Dictionary: return false
		var nation: Dictionary = raw
		if not nation.has("technology_operations"): continue
		if not valid_nation_operation_record(nation.technology_operations, state.get("item_definitions", {}), {}): return false
		if not _nation_order_scope_valid(nation, nation_id, str(state.get("id", ""))): return false
		var operations: Dictionary = nation.technology_operations
		for order_id: String in operations.orders:
			var order: Dictionary = operations.orders[order_id]
			for receipt_id: Variant in order.receipt_ids:
				var claim := JSON.stringify(["feature_output", str(state.id), str(order.feature_id), int(receipt_id)])
				if claims.has(claim): return false
				claims[claim] = true
			for receipt: Dictionary in order.get("accepted_receipts", []):
				for item_id: String in receipt.item_ids:
					var claimant := JSON.stringify([nation_id, order_id])
					if product_claims.has(item_id) and product_claims[item_id] != claimant: return false
					product_claims[item_id] = claimant
			if not order.work_consent.is_empty():
				var consent: Dictionary = order.work_consent
				var key := JSON.stringify([consent.site_id, consent.purpose, int(consent.team_id), int(consent.person_id), int(consent.decider_id), int(consent.revision)])
				if consent_claims.has(key): return false
				consent_claims[key] = true
		for order_id: String in operations.get("public_orders", {}):
			var order: Dictionary = operations.public_orders[order_id]
			for receipt: Dictionary in order.receipts:
				var claim := JSON.stringify(["owner_event", str(state.id), receipt.binding, receipt.target_id, receipt.id])
				if claims.has(claim): return false
				claims[claim] = true
				for item_id: String in receipt.item_ids:
					var claimant := JSON.stringify([nation_id, order_id])
					if product_claims.has(item_id) and product_claims[item_id] != claimant: return false
					product_claims[item_id] = claimant
	return true

func _operations_candidate_claims_valid(nation_id: String, operations: Dictionary) -> bool:
	var nations: Dictionary = lab.terrain.site.get("equipment_nations", {}).duplicate()
	var nation: Dictionary = nations.get(nation_id, {}).duplicate()
	nation.technology_operations = operations
	nations[nation_id] = nation
	return _site_operation_claims_valid({"id": str(lab.terrain.site.id), "item_definitions": lab.terrain.site.item_definitions, "equipment_nations": nations})

static func _public_reference(value: Variant, allow_empty: bool = false) -> bool:
	return value is String and str(value).length() <= 512 and (allow_empty or not str(value).is_empty())

# Loaded JSON numbers are floats and Array.has() compares types strictly:
# match a saved id list as integers.
static func _int_ids(raw: Variant) -> Array:
	var ids: Array = []
	if raw is Array:
		for value: Variant in raw:
			if value is int or value is float: ids.append(int(value))
	return ids

static func _valid_public_people(raw: Variant, people: Dictionary, minimum: int = 1, maximum: int = 6) -> bool:
	if not raw is Array or raw.size() < minimum or raw.size() > maximum: return false
	var seen := {}
	for identity: Variant in raw:
		if not _operation_person(identity, people) or int(identity) == 1000000000 or seen.has(int(identity)): return false
		seen[int(identity)] = true
	return true

static func _public_cost(tech_id: String, payload: Dictionary) -> Dictionary:
	match tech_id:
		"N03": return {"grain": 4}
		"N06": return {"wood": 8, "stone": 4}
		"N07": return {"grain": 2 * payload.get("student_ids", []).size()}
		"N08": return {"grain": 4}
		"N09": return {"grain": 1}
		"N11": return {"wood": 24, "iron": 12, "fiber": 10} if payload.get("route") == "siege" else {"iron": 4, "leather": 2, "charcoal": 2}
	return {}

static func _valid_public_source(raw: Variant, cost: Dictionary, people: Dictionary) -> bool:
	if not raw is Dictionary: return false
	if raw.is_empty(): return true
	if not Technology.keys(raw, ["site_id", "person_id", "holder", "status", "cap", "spent"]) \
		or not Technology.valid_ref({"site_id": raw.site_id, "person_id": raw.person_id}) or not _operation_person(raw.person_id, people) \
		or raw.holder != "person:" + str(int(raw.person_id)) or raw.status not in ["granted", "revoked"] \
		or not _operation_stack(raw.cap) or raw.cap.is_empty() or not _operation_stack(raw.spent, true): return false
	for resource: String in raw.cap:
		if not cost.has(resource) or int(raw.cap[resource]) > int(cost[resource]): return false
	for resource: String in raw.spent:
		if not raw.cap.has(resource) or int(raw.spent[resource]) > int(raw.cap[resource]): return false
	return true

static func _valid_public_consents(raw: Variant, identities: Array, purpose_id: String, site_id: String, people: Dictionary) -> bool:
	if not raw is Array or raw.size() > identities.size(): return false
	var seen := {}
	for consent: Variant in raw:
		if not Technology.keys(consent, ["site_id", "team_id", "person_id", "purpose", "decider_id", "revision", "status"]) \
			or consent.site_id != site_id or not _operation_person(consent.person_id, people) or not identities.has(int(consent.person_id)) \
			or seen.has(int(consent.person_id)) or not Technology.integer(consent.team_id, 1, 999999) \
			or not _operation_person(consent.decider_id, people) or not Technology.integer(consent.revision) \
			or consent.purpose != purpose_id or consent.status not in ["accepted", "revoked"]: return false
		seen[int(consent.person_id)] = true
	return true

static func _valid_public_payload(raw: Variant, tech_id: String, people: Dictionary, orders: Dictionary) -> bool:
	if not raw is Dictionary: return false
	match tech_id:
		"N02":
			return Technology.keys(raw, ["settlement_id", "person_ids", "consents", "feature_id"]) and _public_reference(raw.settlement_id) \
				and _valid_public_people(raw.person_ids, people) and raw.consents is Array and _public_reference(raw.feature_id, true)
		"N03":
			return Technology.keys(raw, ["reserve_feature_id", "source", "recipient_ids"]) and _operation_key(raw.reserve_feature_id) \
				and _valid_public_people(raw.recipient_ids, people, 2, 2) and _valid_public_source(raw.source, _public_cost(tech_id, raw), people)
		"N06":
			return Technology.keys(raw, ["settlement_id", "blueprint_id", "labor_order_id", "worker_ids", "consents", "reserve_feature_id", "source", "feature_id"]) \
				and _public_reference(raw.settlement_id) and _operation_key(raw.blueprint_id) and _public_reference(raw.labor_order_id) and orders.has(raw.labor_order_id) \
				and orders[raw.labor_order_id] is Dictionary and orders[raw.labor_order_id].get("tech_id") == "N02" and _valid_public_people(raw.worker_ids, people) and raw.consents is Array \
				and _operation_key(raw.reserve_feature_id) and _public_reference(raw.feature_id, true) and _valid_public_source(raw.source, _public_cost(tech_id, raw), people)
		"N07":
			return Technology.keys(raw, ["reserve_feature_id", "source", "teacher_id", "student_ids", "skill_id"]) and _operation_key(raw.reserve_feature_id) \
				and _operation_person(raw.teacher_id, people) and _valid_public_people(raw.student_ids, people, 1, 2) and not _int_ids(raw.student_ids).has(int(raw.teacher_id)) \
				and raw.skill_id is String and Technology.FAMILY_IDS.has(raw.skill_id) and _valid_public_source(raw.source, _public_cost(tech_id, raw), people)
		"N08":
			return Technology.keys(raw, ["reserve_feature_id", "source", "route_id", "destination_site_id", "destination_holder", "vehicle_id", "driver_id", "route_ref", "travel_token", "loaded"]) \
				and _operation_key(raw.reserve_feature_id) and _operation_key(raw.route_id) and _public_reference(raw.destination_site_id) and _public_reference(raw.destination_holder) \
				and _operation_key(raw.vehicle_id) and _operation_person(raw.driver_id, people) and _valid_public_route_ref(raw.route_ref) \
				and _public_reference(raw.travel_token, true) and raw.loaded is bool and _valid_public_source(raw.source, _public_cost(tech_id, raw), people)
		"N09":
			return Technology.keys(raw, ["reserve_feature_id", "source", "recipient_id"]) and _operation_key(raw.reserve_feature_id) \
				and _operation_person(raw.recipient_id, people) and _valid_public_source(raw.source, _public_cost(tech_id, raw), people)
		"N10":
			return Technology.keys(raw, ["settlement_id", "local_person_id", "office_revision", "expires_game_seconds", "clock_ref", "feature_id", "consents"]) \
				and _public_reference(raw.settlement_id) and _operation_person(raw.local_person_id, people) and Technology.integer(raw.office_revision) \
				and Technology.finite_number(raw.expires_game_seconds, 0.000001) and Technology.keys(raw.clock_ref, ["world_instance_id", "slot_id"]) \
				and _public_reference(raw.clock_ref.world_instance_id) and _public_reference(raw.clock_ref.slot_id) and _public_reference(raw.feature_id, true) and raw.consents is Array
		"N11":
			return Technology.keys(raw, ["settlement_id", "route", "host_id", "operator_id", "consents", "reserve_feature_id", "source", "target_id"]) \
				and _public_reference(raw.settlement_id) and raw.route in ["siege", "armor"] and _operation_key(raw.host_id) \
				and _operation_person(raw.operator_id, people) and raw.consents is Array and _operation_key(raw.reserve_feature_id) \
				and _public_reference(raw.target_id, true) and _valid_public_source(raw.source, _public_cost(tech_id, raw), people)
		"N12":
			if not Technology.keys(raw, ["corps_id", "ship_ids", "steps"]) or not _valid_key(str(raw.corps_id)) or not raw.corps_id is String \
				or not raw.ship_ids is Array or raw.ship_ids.size() != 2 or not raw.steps is Dictionary or raw.steps.size() > 2: return false
			if raw.ship_ids[0] == raw.ship_ids[1]: return false
			for identity: Variant in raw.ship_ids:
				if not _operation_key(identity): return false
			for identity: Variant in raw.steps:
				var step: Variant = raw.steps[identity]
				if not raw.ship_ids.has(identity) or not Technology.keys(step, ["from_cell", "to_cell", "driver_id", "accepted_revision"]) \
					or not Technology.integer(step.from_cell) or not Technology.integer(step.to_cell) or step.from_cell == step.to_cell \
					or not _operation_person(step.driver_id, people) or not Technology.integer(step.accepted_revision, 1): return false
			return true
	return false

static func _valid_public_route_ref(raw: Variant) -> bool:
	if not Technology.keys(raw, ["world_instance_id", "slot_id", "source_site_id", "destination_site_id", "route_id"]): return false
	for value: Variant in raw.values():
		if not _public_reference(value): return false
	return raw.source_site_id != raw.destination_site_id

static func _valid_public_order(raw: Variant, people: Dictionary, orders: Dictionary, order_id: String = "") -> bool:
	if not Technology.keys(raw, ["tech_id", "project_id", "revision", "authorizer_id", "status", "scope_site_id", "scope_nation_id", "payload", "receipts", "reason"]) \
		or not raw.tech_id is String or not PUBLIC_TECHNOLOGIES.has(raw.tech_id) or not Technology.integer(raw.revision, 1) \
		or not Technology.integer(raw.project_id) \
		or not _operation_person(raw.authorizer_id, people) or not _public_reference(raw.scope_site_id) or not _valid_key(str(raw.scope_nation_id)) or not raw.scope_nation_id is String or raw.status not in ["prepared", "active", "complete", "revoked"] \
		or not _valid_public_payload(raw.payload, str(raw.tech_id), people, orders) or not raw.receipts is Array or raw.receipts.size() > NATION_OPERATIONS_MAX \
		or not raw.reason is String or raw.reason.length() > 256 or (raw.status == "revoked" and raw.reason.is_empty()) \
		or (raw.status != "revoked" and not raw.reason.is_empty()): return false
	var identities: Array = []
	match str(raw.tech_id):
		"N02": identities = _int_ids(raw.payload.person_ids)
		"N06": identities = _int_ids(raw.payload.worker_ids)
		"N10": identities = [int(raw.payload.local_person_id)]
		"N11": identities = [int(raw.payload.operator_id)]
	if raw.payload.has("consents") and not _valid_public_consents(raw.payload.consents, identities, _public_purpose(raw, order_id), str(raw.scope_site_id), people): return false
	if raw.payload.has("source") and not raw.payload.source.is_empty() and raw.payload.source.site_id != raw.scope_site_id: return false
	var seen := {}
	var targets := {}
	var receipt_index := 0
	for receipt: Variant in raw.receipts:
		var receipt_fields := ["id", "site_id", "binding", "operator_id", "target_id", "work_seconds", "item_ids"]
		if raw.tech_id == "N08": receipt_fields.append_array(["source_operator_id", "operator_reference", "transfer_token"])
		if receipt is Dictionary and receipt.has("effective_seconds"): receipt_fields.append("effective_seconds")
		if not Technology.keys(receipt, receipt_fields) or not _public_reference(receipt.id) \
			or receipt.site_id != (raw.payload.destination_site_id if raw.tech_id == "N08" else raw.scope_site_id) or not public_receipt_effective_ok(receipt, str(receipt.get("binding", ""))) \
			or seen.has(receipt.id) or not receipt.binding is String or not PUBLIC_BINDINGS[str(raw.tech_id)].has(receipt.binding) \
			or not _operation_person(receipt.operator_id, {} if raw.tech_id == "N08" else people) or not _public_reference(receipt.target_id) or not receipt.item_ids is Array: return false
		if raw.tech_id == "N08" and (not _operation_person(receipt.source_operator_id, people) or not _portable_ref(receipt.operator_reference, "person") \
			or receipt.transfer_token != raw.payload.travel_token): return false
		var items := {}
		for identity: Variant in receipt.item_ids:
			if not identity is String or not identity.is_valid_int() or str(int(identity)) != identity or not Technology.integer(int(identity), 1) or items.has(identity): return false
			items[identity] = true
		if not _public_receipt_matches_order(raw, order_id, receipt, receipt_index): return false
		receipt_index += 1
		var target := str(receipt.binding) + ":" + str(receipt.target_id)
		if targets.has(target): return false
		seen[receipt.id] = true
		targets[target] = true
	if raw.status == "complete" and not _public_order_complete(raw): return false
	return true

## Same bounded target/participant contract for live candidates and save packets.
## Historical paid evidence remains legal after explicit source revocation.
static func _public_receipt_matches_order(order: Dictionary, order_id: String, receipt: Dictionary, index: int) -> bool:
	var payload: Dictionary = order.payload
	var target: String = str(receipt.target_id)
	var operator_id := int(receipt.operator_id)
	if payload.has("source"):
		if payload.source.is_empty(): return false
		var cost := _public_cost(str(order.tech_id), payload)
		for resource: String in cost:
			if int(payload.source.spent.get(resource, 0)) < int(cost[resource]): return false
	match str(order.tech_id):
		"N02", "N10":
			if index == 0:
				return receipt.binding == ("labor_register" if order.tech_id == "N02" else "mandate") and target == _public_order_target(order, order_id) and receipt.item_ids.is_empty()
			var workers: Array = _int_ids(payload.person_ids) if order.tech_id == "N02" else [int(payload.local_person_id)]
			return index == 1 and receipt.binding == "road_build" and not payload.feature_id.is_empty() and target == "feature:" + str(payload.feature_id) and workers.has(operator_id) and receipt.item_ids.is_empty()
		"N03":
			return index < 2 and receipt.binding == "aid_order" and _int_ids(payload.recipient_ids).has(operator_id) and target == "person:" + str(operator_id) and receipt.id == _public_event_id(order, order_id, "share", target) and receipt.item_ids.is_empty()
		"N06":
			return index == 0 and receipt.binding == "house_build" and not payload.feature_id.is_empty() and target == "feature:" + str(payload.feature_id) and _int_ids(payload.worker_ids).has(operator_id) and receipt.item_ids.is_empty()
		"N07":
			if index >= payload.student_ids.size() or receipt.binding != "funded_course" or operator_id != int(payload.teacher_id) or not receipt.item_ids.is_empty(): return false
			for identity: Variant in payload.student_ids:
				if target == "person:" + str(int(identity)): return receipt.id == _public_event_id(order, order_id, "lesson", str(int(identity)))
			return false
		"N08":
			return index == 0 and receipt.binding == "public_route" and payload.loaded and not payload.travel_token.is_empty() and target == payload.destination_holder and int(receipt.source_operator_id) == int(payload.driver_id) and receipt.transfer_token == payload.travel_token and receipt.item_ids.is_empty()
		"N09":
			return receipt.binding == "tax" and receipt.item_ids.is_empty() and ((index == 0 and target == "feature:" + str(payload.reserve_feature_id) and operator_id == int(payload.source.person_id) and receipt.id == _public_event_id(order, order_id, "tax_collect", str(payload.reserve_feature_id))) or (index == 1 and target == "person:" + str(int(payload.recipient_id)) and operator_id == int(payload.recipient_id) and receipt.id == _public_event_id(order, order_id, "share", target)))
		"N11":
			return index < 2 and not payload.target_id.is_empty() and target == payload.target_id and operator_id == int(payload.operator_id) and receipt.binding == ("arsenal" if index == 1 else ("ballista_build" if payload.route == "siege" else "iron_armor")) and (receipt.item_ids.is_empty() if payload.route == "siege" else receipt.item_ids.size() == 1)
		"N12":
			var ship_id := target.trim_prefix("vehicle:")
			return index < 2 and receipt.binding == "fleet" and target == "vehicle:" + ship_id and payload.steps.has(ship_id) and operator_id == int(payload.steps[ship_id].driver_id) and receipt.id == _public_event_id(order, order_id, "fleet", ship_id) and receipt.item_ids.is_empty()
	return false

# One receipt rule for the live check and the stored validator. An iron_armor
# receipt may carry effective_seconds (bounded by its physical work at the best
# workshop grade); otherwise, and for older receipts, work_seconds is compared.
static func public_receipt_effective_ok(receipt: Dictionary, binding_id: String) -> bool:
	if not Technology.finite_number(receipt.get("work_seconds")): return false
	var effective := float(receipt.work_seconds)
	if receipt.has("effective_seconds"):
		if binding_id != "iron_armor" or not Technology.finite_number(receipt.effective_seconds) or float(receipt.effective_seconds) < 0.0 \
			or float(receipt.effective_seconds) > float(receipt.work_seconds) * Runtime.max_building_productivity() * 1.000001 + 0.000001: return false
		effective = float(receipt.effective_seconds)
	return effective + 0.00000001 >= _public_receipt_seconds(binding_id)

static func _public_receipt_seconds(binding_id: String) -> float:
	match binding_id:
		"road_build": return 180.0
		"house_build", "iron_armor": return 900.0
		"ballista_build": return 5400.0
		"public_route", "aid_order", "tax", "fleet": return 0.0
	return 300.0

static func _public_order_complete(order: Dictionary) -> bool:
	var payload: Dictionary = order.payload
	match str(order.tech_id):
		"N02", "N10":
			return order.receipts.size() == 2 and order.receipts[0].binding == ("labor_register" if order.tech_id == "N02" else "mandate") and order.receipts[1].binding == "road_build"
		"N03": return _public_recipient_count(order) == 2
		"N06": return order.receipts.size() == 1 and order.receipts[0].binding == "house_build"
		"N07": return _public_recipient_count(order) == payload.student_ids.size()
		"N08": return order.receipts.size() == 1 and not payload.travel_token.is_empty() and payload.loaded
		"N09": return order.receipts.size() == 2 and order.receipts[0].target_id == "feature:" + str(payload.reserve_feature_id) and order.receipts[1].target_id == "person:" + str(int(payload.recipient_id))
		"N11": return order.receipts.size() == 2 and order.receipts[0].binding == ("ballista_build" if payload.route == "siege" else "iron_armor") and order.receipts[1].binding == "arsenal"
		"N12": return order.receipts.size() == 2 and payload.steps.size() == 2
	return false

static func _public_recipient_count(order: Dictionary) -> int:
	var expected: Array = order.payload.get("recipient_ids", order.payload.get("student_ids", []))
	var found := {}
	for receipt: Dictionary in order.receipts:
		for identity: Variant in expected:
			if receipt.target_id == "person:" + str(int(identity)): found[int(identity)] = true
	return found.size()

static func _normalize_public_order(order: Dictionary) -> void:
	order.revision = int(order.revision)
	order.project_id = int(order.project_id)
	order.authorizer_id = int(order.authorizer_id)
	var payload: Dictionary = order.payload
	for key: String in ["teacher_id", "driver_id", "recipient_id", "local_person_id", "office_revision", "operator_id"]:
		if payload.has(key): payload[key] = int(payload[key])
	if payload.has("expires_game_seconds"): payload.expires_game_seconds = float(payload.expires_game_seconds)
	for key: String in ["person_ids", "worker_ids", "student_ids", "recipient_ids"]:
		for index: int in range(payload.get(key, []).size()): payload[key][index] = int(payload[key][index])
	for consent: Dictionary in payload.get("consents", []):
		for key: String in ["team_id", "person_id", "decider_id", "revision"]: consent[key] = int(consent[key])
	if payload.has("source") and not payload.source.is_empty():
		payload.source.person_id = int(payload.source.person_id)
		for resource: String in payload.source.cap: payload.source.cap[resource] = int(payload.source.cap[resource])
		for resource: String in payload.source.spent: payload.source.spent[resource] = int(payload.source.spent[resource])
	for step: Dictionary in payload.get("steps", {}).values():
		for key: String in ["from_cell", "to_cell", "driver_id", "accepted_revision"]: step[key] = int(step[key])
	for receipt: Dictionary in order.receipts:
		receipt.operator_id = int(receipt.operator_id)
		if order.tech_id == "N08":
			receipt.source_operator_id = int(receipt.source_operator_id)
			receipt.operator_reference.lineage = int(receipt.operator_reference.lineage)
		receipt.work_seconds = float(receipt.work_seconds)
		if receipt.has("effective_seconds"): receipt.effective_seconds = float(receipt.effective_seconds)

func _public_context(nation_id: String, order_id: String, binding_id: String, read_only: bool = true) -> Dictionary:
	var nation: Dictionary = lab.terrain.site.get("equipment_nations", {}).get(nation_id, {})
	if not nation.has("technology_operations") or not valid_nation_operation_record(nation.technology_operations, lab.terrain.site.item_definitions, {}): return Runtime.fail("CORRUPT_STATE")
	var order: Dictionary = nation.technology_operations.get("public_orders", {}).get(order_id, {})
	if order.is_empty() or order.status in ["complete", "revoked"] or order.scope_site_id != str(lab.terrain.site.id) or order.scope_nation_id != nation_id: return Runtime.fail("STALE_ORDER")
	var context := _nation_operation_context(int(order.authorizer_id), nation_id, str(PUBLIC_DUTIES[str(order.tech_id)]), str(order.tech_id), binding_id, read_only)
	if not context.ok: return context
	if order.payload.has("settlement_id"):
		var settlement := Settlement.record(lab.terrain)
		if not bool(Settlement.status(lab).effective) or settlement.get("settlement_id") != order.payload.settlement_id: return Runtime.fail("STALE_SETTLEMENT")
	if order.payload.has("consents"):
		var identities: Array = order.payload.get("person_ids", order.payload.get("worker_ids", []))
		if order.tech_id == "N10": identities = [int(order.payload.local_person_id)]
		elif order.tech_id == "N11": identities = [int(order.payload.operator_id)]
		for identity: Variant in identities:
			if not actions._technology_consent_valid(int(identity), order.payload.consents, _public_purpose(order, order_id), {}, read_only, order): return Runtime.fail("NO_CONSENT")
	if order.tech_id == "N02":
		for identity: Variant in order.payload.person_ids:
			if not Settlement.residents(lab).has(int(identity)) or not _member(nation, int(identity)): return Runtime.fail("NO_RESIDENT")
	elif order.tech_id == "N06":
		var labor: Dictionary = nation.technology_operations.public_orders.get(str(order.payload.labor_order_id), {})
		if labor.is_empty() or labor.status == "revoked": return Runtime.fail("NO_LABOR")
		for identity: Variant in order.payload.worker_ids:
			if not labor.payload.person_ids.has(int(identity)) or not Settlement.residents(lab).has(int(identity)) or not _member(nation, int(identity)): return Runtime.fail("NO_LABOR")
	return Runtime.ok("", {"nation": nation, "order": order})

func _public_manual_context(requester_id: int, nation_id: String, tech_id: String, binding_id: String) -> Dictionary:
	if requester_id != int(lab.controlled_person_id()): return Runtime.fail("NO_AUTHORITY", "新具名制度命令須當前受控原職責行使者明示")
	var context := _nation_operation_context(requester_id, nation_id, str(PUBLIC_DUTIES.get(tech_id, "")), tech_id, binding_id)
	if context.ok: context.nation_id = nation_id
	return context

func _public_new_candidate(context: Dictionary, tech_id: String, payload: Dictionary) -> Dictionary:
	var candidate := _public_candidate(context.nation)
	if candidate.public_orders.size() >= NATION_OPERATIONS_MAX or int(candidate.next_seq) >= 2147483646: return Runtime.fail("CAPACITY")
	var project_id := 0 if Technology.scope_known(context.nation.technology, tech_id) else int(Technology.active_project(context.nation.technology).get("id", 0))
	if project_id > 0:
		for existing: Dictionary in candidate.public_orders.values():
			if existing.tech_id == tech_id and int(existing.project_id) == project_id: return Runtime.fail("EXISTING_ORDER", "本首次目的已有原單；重試／再核准沿同ID，不能清支出")
	var order_id := "public_" + str(int(candidate.next_seq))
	candidate.next_seq = int(candidate.next_seq) + 1
	candidate.public_orders[order_id] = {"tech_id": tech_id, "project_id": project_id, "revision": 1, "authorizer_id": int(context.requester_id),
		"status": "prepared", "scope_site_id": str(lab.terrain.site.id), "scope_nation_id": str(context.nation_id), "payload": payload.duplicate(true), "receipts": [], "reason": ""}
	return Runtime.ok("", {"operations": candidate, "order_id": order_id, "order": candidate.public_orders[order_id]})

func _public_publish_new(context: Dictionary, candidate: Dictionary) -> Dictionary:
	if not candidate.ok: return candidate
	if not valid_nation_operation_record(candidate.operations, lab.terrain.site.item_definitions, {}): return Runtime.fail("INVALID")
	_publish_nation_operations(context.nation, candidate.operations)
	return Runtime.ok("具名有限操作已登記；未替原人開工、未付材料或計研究秒", {"order_id": candidate.order_id})

func _public_work_consents(identities: Array, purpose_id: String) -> Dictionary:
	var consents: Array = []
	for identity: Variant in identities:
		var person: Dictionary = actions._person(int(identity))
		if person.is_empty() or not _ready(person).ok: return Runtime.fail("NO_WORKER")
		var team: Variant = actions._technology_team(person)
		if team == null: continue
		if not team.has_method("technology_work_consent"): return Runtime.fail("UNSUPPORTED")
		var response: Dictionary = team.technology_work_consent(int(identity), purpose_id, int(lab.controlled_person_id()))
		if not response.ok: return response
		consents.append(response.consent.duplicate(true))
	return Runtime.ok("", {"consents": consents})

func _public_settlement_context(requester_id: int) -> Dictionary:
	var settlement := Settlement.record(lab.terrain)
	var person: Dictionary = actions._person(requester_id)
	if not bool(Settlement.status(lab).effective) or person.is_empty() or int(person.faction) != int(settlement.owner_faction): return Runtime.fail("NO_SETTLEMENT")
	return Runtime.ok("", {"settlement": settlement})

func register_nation_labor(requester_id: int, nation_id: String, identities: Array[int]) -> Dictionary:
	var context := _public_manual_context(requester_id, nation_id, "N02", "labor_register")
	if not context.ok: return context
	var settlement := _public_settlement_context(requester_id)
	if not settlement.ok or not _valid_public_people(identities, {}): return Runtime.fail("NO_SETTLEMENT")
	var residents := Settlement.residents(lab)
	for identity: int in identities:
		if not residents.has(identity) or not _member(context.nation, identity): return Runtime.fail("NO_RESIDENT", "須是原登記居民及本國原人，不增加人口")
	context.requester_id = requester_id
	var candidate := _public_new_candidate(context, "N02", {"settlement_id": str(settlement.settlement.settlement_id), "person_ids": identities.duplicate(), "consents": [], "feature_id": ""})
	if not candidate.ok: return candidate
	var consent := _public_work_consents(identities, _public_purpose(candidate.order, str(candidate.order_id)))
	if not consent.ok: return consent
	candidate.order.payload.consents = consent.consents
	return _public_publish_new(context, candidate)

func request_aid_order(requester_id: int, nation_id: String, reserve_feature_id: String, recipient_ids: Array[int]) -> Dictionary:
	var context := _public_manual_context(requester_id, nation_id, "N03", "aid_order")
	if not context.ok: return context
	if not _valid_public_people(recipient_ids, {}, 2, 2): return Runtime.fail("INVALID")
	var reserve := _procurement_destination(requester_id, reserve_feature_id)
	if not reserve.ok: return reserve
	if not Technology.scope_known(Settlement.record(lab.terrain).get("technology", {}), "S06"): return Runtime.fail("NO_RESERVE", "須沿原聚落糧儲制度")
	for identity: int in recipient_ids:
		var person: Dictionary = actions._person(identity)
		if person.is_empty() or float(person.hp) <= 0.0 or int(person.faction) != int(reserve.stock.faction): return Runtime.fail("NO_RECIPIENT")
	context.requester_id = requester_id
	return _public_publish_new(context, _public_new_candidate(context, "N03", {"reserve_feature_id": reserve_feature_id, "source": {}, "recipient_ids": recipient_ids.duplicate()}))

func request_public_work_order(requester_id: int, nation_id: String, blueprint_id: String, labor_order_id: String, worker_ids: Array[int], reserve_feature_id: String) -> Dictionary:
	var context := _public_manual_context(requester_id, nation_id, "N06", "house_build")
	if not context.ok: return context
	var settlement := _public_settlement_context(requester_id)
	if not settlement.ok or not Technology.scope_known(settlement.settlement.get("technology", {}), "S09"): return Runtime.fail("NO_BLUEPRINT")
	var labor: Dictionary = context.nation.get("technology_operations", {}).get("public_orders", {}).get(labor_order_id, {})
	if labor.is_empty() or labor.tech_id != "N02" or labor.status == "revoked" or not _valid_public_people(worker_ids, {}): return Runtime.fail("NO_LABOR")
	for identity: int in worker_ids:
		if not labor.payload.person_ids.has(identity): return Runtime.fail("NO_LABOR")
	var reserve := _procurement_destination(requester_id, reserve_feature_id)
	if not reserve.ok: return reserve
	context.requester_id = requester_id
	var candidate := _public_new_candidate(context, "N06", {"settlement_id": str(settlement.settlement.settlement_id), "blueprint_id": blueprint_id, "labor_order_id": labor_order_id,
		"worker_ids": worker_ids.duplicate(), "consents": [], "reserve_feature_id": reserve_feature_id, "source": {}, "feature_id": ""})
	if not candidate.ok: return candidate
	var consent := _public_work_consents(worker_ids, _public_purpose(candidate.order, str(candidate.order_id)))
	if not consent.ok: return consent
	candidate.order.payload.consents = consent.consents
	return _public_publish_new(context, candidate)

func request_funded_course(requester_id: int, nation_id: String, reserve_feature_id: String, teacher_id: int, student_ids: Array[int], skill_id: String = "F07") -> Dictionary:
	var context := _public_manual_context(requester_id, nation_id, "N07", "funded_course")
	if not context.ok: return context
	var reserve := _procurement_destination(requester_id, reserve_feature_id)
	if not reserve.ok: return reserve
	var teacher: Dictionary = actions._person(teacher_id)
	if teacher.is_empty() or not _ready(teacher).ok or not Technology.learned(actions._body_get(teacher, "technology"), skill_id) or not actions._technology_member(teacher_id) \
		or not _valid_public_people(student_ids, {}, 1, 2) or student_ids.has(teacher_id): return Runtime.fail("NO_TEACHER")
	for identity: int in student_ids:
		var student: Dictionary = actions._person(identity)
		if student.is_empty() or not _ready(student).ok or not actions._technology_member(identity) or Technology.learned(actions._body_get(student, "technology"), skill_id): return Runtime.fail("NO_STUDENT")
	context.requester_id = requester_id
	return _public_publish_new(context, _public_new_candidate(context, "N07", {"reserve_feature_id": reserve_feature_id, "source": {}, "teacher_id": teacher_id, "student_ids": student_ids.duplicate(), "skill_id": skill_id}))

func declare_tax_source(requester_id: int, nation_id: String, reserve_feature_id: String, recipient_id: int) -> Dictionary:
	var context := _public_manual_context(requester_id, nation_id, "N09", "tax")
	if not context.ok: return context
	var reserve := _procurement_destination(requester_id, reserve_feature_id)
	if not reserve.ok: return reserve
	var person: Dictionary = actions._person(recipient_id)
	if person.is_empty() or float(person.hp) <= 0.0 or int(person.faction) != int(reserve.stock.faction): return Runtime.fail("NO_RECIPIENT")
	context.requester_id = requester_id
	return _public_publish_new(context, _public_new_candidate(context, "N09", {"reserve_feature_id": reserve_feature_id, "source": {}, "recipient_id": recipient_id}))

# A public order's first binding: N11 follows its route (as the arsenal and
# output paths do); every other node uses its first listed binding.
func _public_first_binding(order: Dictionary) -> String:
	if str(order.get("tech_id", "")) == "N11": return "ballista_build" if order.get("payload", {}).get("route") == "siege" else "iron_armor"
	return str(PUBLIC_BINDINGS[str(order.tech_id)][0])

func authorize_public_source(grantor_id: int, nation_id: String, order_id: String, cap: Dictionary) -> Dictionary:
	if grantor_id != int(lab.controlled_person_id()): return Runtime.fail("NO_AUTHORITY", "私人物資只能本人明示本單有限用途")
	var nation: Dictionary = lab.terrain.site.get("equipment_nations", {}).get(nation_id, {})
	if not nation.has("technology_operations") or not valid_nation_operation_record(nation.technology_operations, lab.terrain.site.item_definitions, {}): return Runtime.fail("CORRUPT_STATE")
	var order: Dictionary = nation.technology_operations.get("public_orders", {}).get(order_id, {})
	if order.is_empty() or not order.payload.has("source"): return Runtime.fail("NO_TARGET")
	var context := _public_context(nation_id, order_id, _public_first_binding(order))
	if not context.ok: return context
	var person: Dictionary = actions._person(grantor_id)
	if person.is_empty() or not _ready(person).ok: return Runtime.fail("BUSY")
	var previous: Dictionary = order.payload.source
	if not previous.is_empty() and int(previous.person_id) != grantor_id: return Runtime.fail("NO_AUTHORITY", "不得换来源重置歷史")
	if not previous.is_empty():
		for resource: String in previous.cap:
			if int(cap.get(resource, -1)) < int(previous.cap[resource]): return Runtime.fail("CAP_DECREASE")
	var candidate := _public_candidate(nation)
	var source := {"site_id": str(lab.terrain.site.id), "person_id": grantor_id, "holder": "person:" + str(grantor_id),
		"status": "granted", "cap": cap.duplicate(), "spent": previous.get("spent", {}).duplicate()}
	candidate.public_orders[order_id].payload.source = source
	candidate.public_orders[order_id].revision = int(order.revision) + 1
	if not valid_nation_operation_record(candidate, lab.terrain.site.item_definitions, {}): return Runtime.fail("INVALID", "本單固定有限成本／原來源授權")
	_publish_nation_operations(nation, candidate)
	return Runtime.ok("本人明示本用途額度；尚未移物或宣告倉庫／營地國有")

func revoke_public_source(grantor_id: int, nation_id: String, order_id: String) -> Dictionary:
	if grantor_id != int(lab.controlled_person_id()): return Runtime.fail("NO_AUTHORITY")
	var nation: Dictionary = lab.terrain.site.get("equipment_nations", {}).get(nation_id, {})
	if not nation.has("technology_operations") or not valid_nation_operation_record(nation.technology_operations, lab.terrain.site.item_definitions, {}): return Runtime.fail("CORRUPT_STATE")
	var candidate := _public_candidate(nation)
	var order: Dictionary = candidate.public_orders.get(order_id, {})
	if order.is_empty() or order.status in ["complete", "revoked"] or not order.payload.has("source") or order.payload.source.is_empty() \
		or int(order.payload.source.person_id) != grantor_id: return Runtime.fail("NO_AUTHORITY")
	order.payload.source.status = "revoked"
	order.revision = int(order.revision) + 1
	if not valid_nation_operation_record(candidate, lab.terrain.site.item_definitions, {}): return Runtime.fail("INVALID")
	_publish_nation_operations(nation, candidate)
	return Runtime.ok("本私人物資來源撤銷；已移交實物及支出保留")

func fund_public_order(grantor_id: int, nation_id: String, order_id: String, resources: Dictionary, source_version: int, destination_version: int) -> Dictionary:
	if grantor_id != int(lab.controlled_person_id()): return Runtime.fail("NO_AUTHORITY")
	var nation: Dictionary = lab.terrain.site.get("equipment_nations", {}).get(nation_id, {})
	if not nation.has("technology_operations") or not valid_nation_operation_record(nation.technology_operations, lab.terrain.site.item_definitions, {}): return Runtime.fail("CORRUPT_STATE")
	var order: Dictionary = nation.technology_operations.get("public_orders", {}).get(order_id, {})
	if order.is_empty() or not order.payload.has("source") or order.payload.source.is_empty() or order.payload.source.status != "granted" \
		or int(order.payload.source.person_id) != grantor_id or not _operation_stack(resources) or resources.is_empty(): return Runtime.fail("NO_BUDGET")
	var context := _public_context(nation_id, order_id, _public_first_binding(order))
	if not context.ok: return context
	var reserve := _procurement_destination(int(order.authorizer_id), str(order.payload.reserve_feature_id))
	if not reserve.ok: return reserve
	var candidate := _public_candidate(nation)
	Runtime.add_items(candidate.public_orders[order_id].payload.source.spent, resources)
	if order.tech_id == "N09":
		if not order.receipts.is_empty() or resources != {"grain": 1}: return Runtime.fail("NO_CHANGE")
		candidate.public_orders[order_id].receipts.append({"id": _public_event_id(order, order_id, "tax_collect", str(order.payload.reserve_feature_id)), "site_id": str(order.scope_site_id), "binding": "tax", "operator_id": grantor_id, "target_id": "feature:" + str(order.payload.reserve_feature_id), "work_seconds": 0.0, "item_ids": []})
	candidate.public_orders[order_id].revision = int(order.revision) + 1
	if not valid_nation_operation_record(candidate, lab.terrain.site.item_definitions, {}): return Runtime.fail("NO_BUDGET")
	var transport: Variant = _original_stock_transport()
	if transport == null: return Runtime.fail("UNSUPPORTED")
	var transferred: Dictionary = transport.transfer(str(order.payload.source.holder), "feature:" + str(order.payload.reserve_feature_id), resources, [], source_version, destination_version, grantor_id)
	if not transferred.ok: return transferred
	_publish_nation_operations(nation, candidate)
	return Runtime.ok("本人的真物資已移交原倉庫；本用途支出同次記錄", {"order_id": order_id})

func _public_source_paid(order: Dictionary) -> bool:
	var source: Dictionary = order.payload.get("source", {})
	if source.is_empty() or source.status != "granted" or source.site_id != str(lab.terrain.site.id): return false
	for resource: String in _public_cost(str(order.tech_id), order.payload):
		if int(source.spent.get(resource, 0)) < int(_public_cost(str(order.tech_id), order.payload)[resource]): return false
	return true

func deliver_public_share(requester_id: int, nation_id: String, order_id: String, recipient_id: int, source_version: int, destination_version: int) -> Dictionary:
	if requester_id != int(lab.controlled_person_id()): return Runtime.fail("NO_AUTHORITY")
	var nation: Dictionary = lab.terrain.site.get("equipment_nations", {}).get(nation_id, {})
	if not nation.has("technology_operations") or not valid_nation_operation_record(nation.technology_operations, lab.terrain.site.item_definitions, {}): return Runtime.fail("CORRUPT_STATE")
	var order: Dictionary = nation.technology_operations.get("public_orders", {}).get(order_id, {})
	if order.is_empty() or order.tech_id not in ["N03", "N09"]: return Runtime.fail("NO_TARGET")
	var context := _public_context(nation_id, order_id, "aid_order" if order.tech_id == "N03" else "tax")
	if not context.ok: return context
	if not _public_source_paid(order): return Runtime.fail("NO_BUDGET")
	var recipient_ids: Array = order.payload.recipient_ids if order.tech_id == "N03" else [int(order.payload.recipient_id)]
	if not recipient_ids.has(recipient_id): return Runtime.fail("NO_RECIPIENT")
	var target_id := "person:" + str(recipient_id)
	for receipt: Dictionary in order.receipts:
		if receipt.target_id == target_id: return Runtime.fail("NO_CHANGE")
	var amount := 2 if order.tech_id == "N03" else 1
	var candidate := _public_candidate(nation)
	var next: Dictionary = candidate.public_orders[order_id]
	next.receipts.append({"id": _public_event_id(order, order_id, "share", target_id), "site_id": str(order.scope_site_id), "binding": "aid_order" if order.tech_id == "N03" else "tax", "operator_id": recipient_id, "target_id": target_id, "work_seconds": 0.0, "item_ids": []})
	next.status = "complete" if _public_order_complete(next) else "active"
	next.revision = int(order.revision) + 1
	if not valid_nation_operation_record(candidate, lab.terrain.site.item_definitions, {}): return Runtime.fail("INVALID")
	var transport: Variant = _original_stock_transport()
	if transport == null: return Runtime.fail("UNSUPPORTED")
	var transferred: Dictionary = transport.transfer("feature:" + str(order.payload.reserve_feature_id), target_id, {"grain": amount}, [], source_version, destination_version, requester_id)
	if not transferred.ok: return transferred
	_publish_nation_operations(nation, candidate)
	return Runtime.ok("原受助／支出接收者已實際取得指定原糧；保存本次唯一交付", {"complete": next.status == "complete", "order_id": order_id})

func begin_funded_course(requester_id: int, nation_id: String, order_id: String, student_id: int) -> Dictionary:
	if requester_id != int(lab.controlled_person_id()): return Runtime.fail("NO_AUTHORITY")
	var context := _public_context(nation_id, order_id, "funded_course")
	if not context.ok or context.order.tech_id != "N07": return context if not context.ok else Runtime.fail("NO_TARGET")
	var order: Dictionary = context.order
	if not _public_source_paid(order) or not order.payload.student_ids.has(student_id): return Runtime.fail("NO_BUDGET")
	for receipt: Dictionary in order.receipts:
		if receipt.target_id == "person:" + str(student_id): return Runtime.fail("NO_CHANGE")
	if not nation_course_request.is_valid(): return Runtime.fail("UNSUPPORTED", "原PA须接本名额一师一徒及成功尾段津貼預檢，不能用基本授課冒充已資助")
	return nation_course_request.call(nation_id, order_id, int(order.payload.teacher_id), student_id, str(order.payload.skill_id))

## PA calls before its original learned-person commit, with its ORIGINAL live job.
## A prepared transfer contains only original references and goes stale normally.
func prepare_funded_course_completion(nation_id: String, order_id: String, original_job: Dictionary, learned_person_candidate: Dictionary) -> Dictionary:
	if not Technology.finite_number(original_job.get("duration"), 300.0) or not Technology.finite_number(original_job.get("elapsed")) \
		or float(original_job.elapsed) + 0.00000001 < float(original_job.duration): return Runtime.fail("STALE_COURSE")
	var source: Dictionary = prepare_funded_course_source(nation_id, order_id, original_job)
	if not source.ok: return source
	if not Technology.learned(learned_person_candidate, str(source.order.payload.skill_id)): return Runtime.fail("STALE_COURSE")
	var candidate: Dictionary = _funded_course_operations_candidate(source)
	if candidate.is_empty(): return Runtime.fail("INVALID")
	return Runtime.ok("", {"nation_ref": source.nation_ref, "operations": candidate, "course_source": source,
		"learned_candidate": learned_person_candidate.duplicate(true), "published": false,
		"source": source.transfer.source, "source_cargo": source.transfer.source_cargo,
		"destination": source.transfer.destination, "destination_cargo": source.transfer.destination_cargo,
		"source_version": int(source.transfer.source_version), "destination_version": int(source.transfer.destination_version)})

## PA makes this its first actual commit after ALL original course/skill/native
## candidates pass. Once this succeeds it publishes learned state without failure.
func commit_funded_course_payment(prepared: Dictionary) -> Dictionary:
	var checked: Dictionary = validate_funded_course_payment(prepared)
	if not checked.ok: return checked
	publish_funded_course_payment(prepared)
	return Runtime.ok()

func authorize_public_transport_route(requester_id: int, nation_id: String, reserve_feature_id: String, route_id: String, destination_site_id: String, destination_holder: String, vehicle_id: String, driver_id: int) -> Dictionary:
	var context := _public_manual_context(requester_id, nation_id, "N08", "public_route")
	if not context.ok: return context
	var reserve := _procurement_destination(requester_id, reserve_feature_id)
	if not reserve.ok: return reserve
	if not nation_route_query.is_valid() or not nation_route_request.is_valid(): return Runtime.fail("UNSUPPORTED", "须接原Region真路线／原车船／行程与目的holder收货，不以本地装卸代跨地")
	var checked: Dictionary = nation_route_query.call(route_id, destination_site_id, vehicle_id, driver_id, destination_holder)
	if not checked.ok or not _valid_public_route_ref(checked.get("route_ref")): return checked if not checked.ok else Runtime.fail("INVALID_ROUTE")
	if checked.route_ref.source_site_id != str(lab.terrain.site.id) or checked.route_ref.destination_site_id != destination_site_id or checked.route_ref.route_id != route_id: return Runtime.fail("STALE_ROUTE")
	var transport: Variant = _original_stock_transport()
	var vehicle: Dictionary = transport.records().get(vehicle_id, {}) if transport != null else {}
	if vehicle.is_empty() or int(vehicle.get("operator_id", 0)) != driver_id: return Runtime.fail("NO_DRIVER")
	context.requester_id = requester_id
	return _public_publish_new(context, _public_new_candidate(context, "N08", {"reserve_feature_id": reserve_feature_id, "source": {}, "route_id": route_id,
		"destination_site_id": destination_site_id, "destination_holder": destination_holder, "vehicle_id": vehicle_id, "driver_id": driver_id,
		"route_ref": checked.route_ref.duplicate(true), "travel_token": "", "loaded": false}))

func load_public_route(requester_id: int, nation_id: String, order_id: String, source_version: int, destination_version: int) -> Dictionary:
	if requester_id != int(lab.controlled_person_id()): return Runtime.fail("NO_AUTHORITY")
	var context := _public_context(nation_id, order_id, "public_route")
	if not context.ok or context.order.tech_id != "N08": return context if not context.ok else Runtime.fail("NO_TARGET")
	var order: Dictionary = context.order
	if order.payload.loaded or not order.payload.travel_token.is_empty(): return Runtime.fail("NO_CHANGE")
	if not _public_source_paid(order): return Runtime.fail("NO_BUDGET")
	if lab.site_controller == null or lab.site_controller.region_slot == null or not lab.site_controller.has_method("prepare_nation_route_load"):
		return Runtime.fail("UNSUPPORTED", "須接原 Slot 的真 NPC 操作人裝車及本次四糧付款")
	var candidate := _public_candidate(context.nation)
	candidate.public_orders[order_id].payload.loaded = true
	candidate.public_orders[order_id].revision = int(order.revision) + 1
	if not valid_nation_operation_record(candidate, lab.terrain.site.item_definitions, {}): return Runtime.fail("INVALID")
	var prepared: Dictionary = lab.site_controller.prepare_nation_route_load(nation_id, order_id, order)
	if not prepared.ok: return prepared
	var slot: Variant = lab.site_controller.region_slot
	if int(prepared.transfer.source_version) != source_version or int(prepared.transfer.destination_version) != destination_version:
		slot.discard_nation_route_transfer_permit(prepared.permit)
		return Runtime.fail("STALE_SOURCE")
	var stable := Runtime.validate_prepared_item_transfer(prepared.transfer)
	if not stable.ok:
		slot.discard_nation_route_transfer_permit(prepared.permit)
		return stable
	var admitted: Dictionary = slot.validate_nation_route_transfer_permit(lab.site_controller.vehicles, prepared.permit,
		str(prepared.permit.source_holder), str(prepared.permit.destination_holder), {"grain": 4}, [], int(order.payload.driver_id))
	if not admitted.ok:
		slot.discard_nation_route_transfer_permit(prepared.permit)
		return admitted
	# No yields or fallible calls after the actual original material publication.
	var result := Runtime.publish_item_transfer(prepared.transfer)
	if not prepared.phase.payment.is_empty(): actions.publish_phase_payment(prepared.phase.payment)
	_publish_nation_operations(context.nation, candidate)
	slot.discard_nation_route_transfer_permit(prepared.permit)
	return Runtime.ok("本單真操作人已於原倉實際装四糧；同四糧 Scope 付款與 loaded 同次發布", {"source_version": result.source_version, "destination_version": result.destination_version})

func begin_public_route(requester_id: int, nation_id: String, order_id: String) -> Dictionary:
	if requester_id != int(lab.controlled_person_id()): return Runtime.fail("NO_AUTHORITY")
	var context := _public_context(nation_id, order_id, "public_route")
	if not context.ok or context.order.tech_id != "N08": return context if not context.ok else Runtime.fail("NO_TARGET")
	var order: Dictionary = context.order
	if not order.payload.loaded or not order.payload.travel_token.is_empty() or not _public_source_paid(order): return Runtime.fail("NO_BUDGET")
	if not nation_route_request.is_valid(): return Runtime.fail("UNSUPPORTED")
	# This original Region callback owns preflight, durable token and source
	# archive. It must publish this order's token in that SAME original commit.
	return nation_route_request.call(nation_id, order_id, order.duplicate(true))

func _original_world_seconds() -> float:
	var slot: Variant = lab.site_controller.region_slot if lab.site_controller != null else null
	if slot == null or not slot.control is Dictionary or not Technology.finite_number(slot.control.get("logical_game_seconds")): return -1.0
	return float(slot.control.logical_game_seconds)

func grant_settlement_mandate(requester_id: int, nation_id: String, local_person_id: int, expires_game_seconds: float) -> Dictionary:
	var context := _public_manual_context(requester_id, nation_id, "N10", "mandate")
	if not context.ok: return context
	var settlement := _public_settlement_context(requester_id)
	if not settlement.ok: return settlement
	var now := _original_world_seconds()
	if now < 0.0 or not Technology.finite_number(expires_game_seconds, now + 0.000001): return Runtime.fail("NO_WORLD_CLOCK", "委任期限须用原World/Region共同时间")
	# A mandate approves a bounded national task for the REAL current local
	# head. It never grants an office or overwrites original Settlement duties.
	if local_person_id != Settlement.head_executor(lab) or not _member(context.nation, local_person_id): return Runtime.fail("NO_LOCAL_AUTHORITY")
	context.requester_id = requester_id
	var candidate := _public_new_candidate(context, "N10", {"settlement_id": str(settlement.settlement.settlement_id), "local_person_id": local_person_id,
		"office_revision": int(Settlement.offices(lab).revision), "expires_game_seconds": expires_game_seconds,
		"clock_ref": {"world_instance_id": str(lab.site_controller.region_slot.pin.world_instance_id), "slot_id": str(lab.site_controller.region_slot.pin.slot_id)}, "feature_id": "", "consents": []})
	if not candidate.ok: return candidate
	var consent := _public_work_consents([local_person_id], _public_purpose(candidate.order, str(candidate.order_id)))
	if not consent.ok: return consent
	candidate.order.payload.consents = consent.consents
	return _public_publish_new(context, candidate)

func _mandate_effective(order: Dictionary, read_only: bool = false) -> bool:
	var now := _original_world_seconds()
	return order.tech_id == "N10" and order.status not in ["complete", "revoked"] and now >= 0.0 and now < float(order.payload.expires_game_seconds) \
		and order.payload.clock_ref.world_instance_id == str(lab.site_controller.region_slot.pin.world_instance_id) and order.payload.clock_ref.slot_id == str(lab.site_controller.region_slot.pin.slot_id) \
		and Settlement.record(lab.terrain).get("settlement_id") == order.payload.settlement_id and bool(Settlement.status(lab).effective) \
		and int(Settlement.offices(lab, read_only).get("revision", -1)) == int(order.payload.office_revision) and Settlement.head_executor(lab, read_only) == int(order.payload.local_person_id)

## A new explicit expiry renews the SAME purpose/order after revocation/expiry.
## Before work starts a new real local head may be selected; accepted work keeps
## its original worker binding and therefore requires that same current head.
func renew_settlement_mandate(requester_id: int, nation_id: String, order_id: String, expected_revision: int, local_person_id: int, expires_game_seconds: float) -> Dictionary:
	if requester_id != int(lab.controlled_person_id()): return Runtime.fail("NO_AUTHORITY")
	var nation: Dictionary = lab.terrain.site.get("equipment_nations", {}).get(nation_id, {})
	if not nation.has("technology_operations") or not valid_nation_operation_record(nation.technology_operations, lab.terrain.site.item_definitions, {}): return Runtime.fail("CORRUPT_STATE")
	var original: Dictionary = nation.technology_operations.get("public_orders", {}).get(order_id, {})
	if original.is_empty() or original.tech_id != "N10" or original.status == "complete" or int(original.revision) != expected_revision: return Runtime.fail("STALE_ORDER")
	var context := _public_manual_context(requester_id, nation_id, "N10", "road_build" if original.receipts.size() == 1 else "mandate")
	if not context.ok: return context
	var settlement := _public_settlement_context(requester_id)
	if not settlement.ok or settlement.settlement.settlement_id != original.payload.settlement_id: return Runtime.fail("STALE_SETTLEMENT")
	var now := _original_world_seconds()
	if now < 0.0 or not Technology.finite_number(expires_game_seconds, now + 0.000001): return Runtime.fail("NO_WORLD_CLOCK")
	if local_person_id != Settlement.head_executor(lab) or not _member(nation, local_person_id): return Runtime.fail("NO_LOCAL_AUTHORITY")
	if not original.payload.feature_id.is_empty() and local_person_id != int(original.payload.local_person_id): return Runtime.fail("BOUND_WORKER", "原已開工範圍須保留同原人物；先沿原工作owner處理交接")
	var consent := _public_work_consents([local_person_id], _public_purpose(original, order_id))
	if not consent.ok: return consent
	var candidate := _public_candidate(nation)
	var next: Dictionary = candidate.public_orders[order_id]
	next.authorizer_id = requester_id
	next.payload.local_person_id = local_person_id
	next.payload.office_revision = int(Settlement.offices(lab).revision)
	next.payload.expires_game_seconds = expires_game_seconds
	next.payload.clock_ref = {"world_instance_id": str(lab.site_controller.region_slot.pin.world_instance_id), "slot_id": str(lab.site_controller.region_slot.pin.slot_id)}
	next.payload.consents = consent.consents
	next.status = "active" if not next.receipts.is_empty() or not next.payload.feature_id.is_empty() else "prepared"
	next.reason = ""
	next.revision = expected_revision + 1
	if not valid_nation_operation_record(candidate, lab.terrain.site.item_definitions, {}): return Runtime.fail("INVALID")
	_publish_nation_operations(nation, candidate)
	return Runtime.ok("現任原地方職掌及新原World期限已明示再核；同項目／單號／真工作／歷史保留")

func revoke_public_operation(requester_id: int, nation_id: String, order_id: String, expected_revision: int, reason: String) -> Dictionary:
	if requester_id != int(lab.controlled_person_id()) or reason.is_empty() or reason.length() > 256: return Runtime.fail("NO_AUTHORITY")
	var nation: Dictionary = lab.terrain.site.get("equipment_nations", {}).get(nation_id, {})
	if not nation.has("technology_operations") or not valid_nation_operation_record(nation.technology_operations, lab.terrain.site.item_definitions, {}): return Runtime.fail("CORRUPT_STATE")
	var original: Dictionary = nation.technology_operations.get("public_orders", {}).get(order_id, {})
	if original.is_empty() or original.status in ["complete", "revoked"] or int(original.revision) != expected_revision \
		or not _nation_duty_ok(requester_id, nation, str(PUBLIC_DUTIES[str(original.tech_id)])): return Runtime.fail("NO_AUTHORITY")
	var candidate := _public_candidate(nation)
	candidate.public_orders[order_id].status = "revoked"
	candidate.public_orders[order_id].reason = reason
	candidate.public_orders[order_id].revision = expected_revision + 1
	if not valid_nation_operation_record(candidate, lab.terrain.site.item_definitions, {}): return Runtime.fail("INVALID")
	_publish_nation_operations(nation, candidate)
	return Runtime.ok("本具名用途已撤銷；真物資／已付工作／歷史不刪除，原job沿安全邊界停止")

## The original build owner must bind the predicted feature + genuine workers +
## original source payment and this prevalidated order in one no-yield commit.
func begin_nation_construction(requester_id: int, nation_id: String, order_id: String, cells: Array[int]) -> Dictionary:
	if requester_id != int(lab.controlled_person_id()): return Runtime.fail("NO_AUTHORITY")
	var nation: Dictionary = lab.terrain.site.get("equipment_nations", {}).get(nation_id, {})
	if not nation.has("technology_operations") or not valid_nation_operation_record(nation.technology_operations, lab.terrain.site.item_definitions, {}): return Runtime.fail("CORRUPT_STATE")
	var order: Dictionary = nation.technology_operations.get("public_orders", {}).get(order_id, {})
	if order.is_empty() or order.tech_id not in ["N02", "N06", "N10"]: return Runtime.fail("NO_TARGET")
	var binding_id := "house_build" if order.tech_id == "N06" else "road_build"
	var context := _public_context(nation_id, order_id, binding_id)
	if not context.ok: return context
	if order.tech_id == "N10":
		if not _mandate_effective(order) or requester_id != int(order.payload.local_person_id): return Runtime.fail("EXPIRED_MANDATE")
	elif requester_id != int(order.authorizer_id): return Runtime.fail("NO_AUTHORITY")
	if not order.payload.feature_id.is_empty(): return Runtime.fail("NO_CHANGE")
	if order.tech_id != "N06" and cells.size() != 1: return Runtime.fail("INVALID", "本次勞役／委任只限原一格道路")
	if order.tech_id == "N06" and not _public_source_paid(order): return Runtime.fail("NO_BUDGET")
	for index: int in cells:
		if index < 0 or index >= lab.terrain.size.x * lab.terrain.size.y or not Settlement.cell_in_jurisdiction(lab.terrain, lab.terrain.cell_from_index(index)): return Runtime.fail("NO_JURISDICTION")
	if not nation_build_request.is_valid(): return Runtime.fail("UNSUPPORTED", "原Settlement藍圖／Runtime有限支付／WorkTeam定向派工尚須接同次原提交")
	var candidate := _public_candidate(nation)
	var next: Dictionary = candidate.public_orders[order_id]
	next.payload.feature_id = str(int(lab.terrain.site.next_feature))
	next.status = "active"
	next.revision = int(order.revision) + 1
	if not valid_nation_operation_record(candidate, lab.terrain.site.item_definitions, {}): return Runtime.fail("INVALID")
	var request := {"cells": cells.duplicate(), "kind": "house" if order.tech_id == "N06" else "road", "requester_id": requester_id,
		"order": next.duplicate(true), "operations": candidate}
	var preview: Dictionary = nation_build_request.call(nation_id, order_id, request, true)
	if not preview.ok: return preview
	return nation_build_request.call(nation_id, order_id, request, false)

func request_arsenal_order(requester_id: int, nation_id: String, route: String, host_id: String, operator_id: int, reserve_feature_id: String) -> Dictionary:
	if route not in ["siege", "armor"]: return Runtime.fail("INVALID")
	var context := _public_manual_context(requester_id, nation_id, "N11", "ballista_build" if route == "siege" else "iron_armor")
	if not context.ok: return context
	var settlement := _public_settlement_context(requester_id)
	if not settlement.ok: return settlement
	if not Technology.scope_known(settlement.settlement.get("technology", {}), "S11" if route == "siege" else "S13"): return Runtime.fail("NO_INDUSTRY")
	var reserve := _procurement_destination(requester_id, reserve_feature_id)
	if not reserve.ok: return reserve
	var person: Dictionary = actions._person(operator_id)
	if person.is_empty() or not _ready(person).ok or int(person.faction) != int(settlement.settlement.owner_faction): return Runtime.fail("NO_WORKER")
	if route == "armor" and not Technology.learned(actions._body_get(person, "technology"), "F04"): return Runtime.fail("NO_SKILL")
	if not nation_arsenal_request.is_valid(): return Runtime.fail("UNSUPPORTED", "须先有原S11實際器械場或S13真甲冑作坊／原付料及實物出貨入口")
	context.requester_id = requester_id
	var candidate := _public_new_candidate(context, "N11", {"settlement_id": str(settlement.settlement.settlement_id), "route": route, "host_id": host_id, "operator_id": operator_id,
		"consents": [], "reserve_feature_id": reserve_feature_id, "source": {}, "target_id": ""})
	if not candidate.ok: return candidate
	var consent := _public_work_consents([operator_id], _public_purpose(candidate.order, str(candidate.order_id)))
	if not consent.ok: return consent
	candidate.order.payload.consents = consent.consents
	var preview: Dictionary = nation_arsenal_request.call(nation_id, str(candidate.order_id), candidate.order.duplicate(true), true)
	if not preview.ok: return preview
	return _public_publish_new(context, candidate)

func begin_arsenal_order(requester_id: int, nation_id: String, order_id: String, work_target: Dictionary = {}) -> Dictionary:
	if requester_id != int(lab.controlled_person_id()): return Runtime.fail("NO_AUTHORITY")
	var nation: Dictionary = lab.terrain.site.get("equipment_nations", {}).get(nation_id, {})
	if not nation.has("technology_operations") or not valid_nation_operation_record(nation.technology_operations, lab.terrain.site.item_definitions, {}): return Runtime.fail("CORRUPT_STATE")
	var order: Dictionary = nation.technology_operations.get("public_orders", {}).get(order_id, {})
	if order.is_empty() or order.tech_id != "N11": return Runtime.fail("NO_TARGET")
	var context := _public_context(nation_id, order_id, "ballista_build" if order.payload.route == "siege" else "iron_armor")
	if not context.ok: return context
	if requester_id != int(order.authorizer_id) or not _public_source_paid(order) or not order.payload.target_id.is_empty(): return Runtime.fail("NO_BUDGET")
	if not nation_arsenal_request.is_valid(): return Runtime.fail("UNSUPPORTED")
	# Runtime prepares actual target/order/worker/source before any payment,
	# and publishes them together in its original failure-free tail.
	if work_target.is_empty(): return nation_arsenal_request.call(nation_id, order_id, order.duplicate(true), false)
	return nation_arsenal_request.call(nation_id, order_id, order.duplicate(true), false, work_target)

func _original_team(team_id: int) -> Variant:
	for team: TerrainArmy in lab.combat_armies:
		if int(team.team_id) == team_id and team.data == lab.terrain and team.combat_enabled: return team
	return null

func _fleet_context(nation: Dictionary, corps_id: String, ship_ids: Array, requester_id: int, need_control: bool = true) -> Dictionary:
	var transport: Variant = _original_stock_transport()
	var relation: Dictionary = lab.terrain.site.get("corps", {}).get(corps_id, {})
	if transport == null or relation.is_empty() or int(relation.get("commander_person_id", -1)) != requester_id \
		or not _member(nation, requester_id) or ship_ids.size() != 2 or ship_ids[0] == ship_ids[1]: return Runtime.fail("NO_CORPS")
	for identity: Variant in ship_ids:
		var ship: Dictionary = transport.records().get(str(identity), {})
		if not SiteVehicleTransport.is_ship(ship) or not SiteVehicleTransport.ship_afloat(ship) or not relation.team_ids.has(int(ship.team_id)): return Runtime.fail("NO_SHIP")
		var team: Variant = _original_team(int(ship.team_id))
		var authority := Runtime.authorize_corps_reposition(lab.terrain, requester_id, team, lab._combat_target_in_site)
		if not authority.ok: return authority
		if not transport.ship_driver_ready(ship) or transport.ship_crew_count(ship) < int(SiteVehicleTransport.Ship.definition(str(ship.ship_type)).min_crew): return Runtime.fail("NO_CREW")
		if need_control and not transport._authorized(team, requester_id, int(ship.operator_id)): return Runtime.fail("NO_AUTHORITY", "原軍團隸屬不取代每船原舵手／隊指揮資格")
	return Runtime.ok("", {"transport": transport})

func request_fleet_order(requester_id: int, nation_id: String, corps_id: String, ship_ids: Array[String]) -> Dictionary:
	var context := _public_manual_context(requester_id, nation_id, "N12", "fleet")
	if not context.ok: return context
	if not Technology.scope_known(Settlement.record(lab.terrain).get("technology", {}), "S12"): return Runtime.fail("NO_SHIPYARD")
	var fleet := _fleet_context(context.nation, corps_id, ship_ids, requester_id)
	if not fleet.ok: return fleet
	for existing: Dictionary in context.nation.get("technology_operations", {}).get("public_orders", {}).values():
		if existing.tech_id != "N12" or existing.status in ["complete", "revoked"]: continue
		for identity: String in ship_ids:
			if existing.payload.ship_ids.has(identity): return Runtime.fail("BUSY", "原船已在另一具名未完成編制")
	context.requester_id = requester_id
	return _public_publish_new(context, _public_new_candidate(context, "N12", {"corps_id": corps_id, "ship_ids": ship_ids.duplicate(), "steps": {}}))

## Each real ship command is an independent original command. A refusal for
## another ship does not undo an already accepted physically running first one.
func command_fleet_ship(requester_id: int, nation_id: String, order_id: String, ship_id: String) -> Dictionary:
	if requester_id != int(lab.controlled_person_id()): return Runtime.fail("NO_AUTHORITY")
	var context := _public_context(nation_id, order_id, "fleet")
	if not context.ok or context.order.tech_id != "N12": return context if not context.ok else Runtime.fail("NO_TARGET")
	var order: Dictionary = context.order
	if not order.payload.ship_ids.has(ship_id) or order.payload.steps.has(ship_id): return Runtime.fail("NO_CHANGE")
	var fleet := _fleet_context(context.nation, str(order.payload.corps_id), order.payload.ship_ids, requester_id)
	if not fleet.ok: return fleet
	var ship: Dictionary = fleet.transport.records()[ship_id]
	if not ship.move.is_empty() or not ship.command.is_empty() or not fleet.transport.ship_job(ship_id).is_empty(): return Runtime.fail("BUSY")
	var from_cell := int(ship.cell)
	var destination: Vector2i = lab.terrain.cell_from_index(from_cell) + Vector2i(int(ship.facing[0]), int(ship.facing[1]))
	if not lab.terrain.contains(destination): return Runtime.fail("TERRAIN")
	var candidate := _public_candidate(context.nation)
	var next: Dictionary = candidate.public_orders[order_id]
	next.payload.steps[ship_id] = {"from_cell": from_cell, "to_cell": lab.terrain.index(destination), "driver_id": int(ship.operator_id), "accepted_revision": int(ship.revision)}
	next.status = "active"
	next.revision = int(order.revision) + 1
	if not valid_nation_operation_record(candidate, lab.terrain.site.item_definitions, {}): return Runtime.fail("INVALID")
	var result: Dictionary = fleet.transport.ship_order(ship_id, "forward", TerrainArmy.INVALID_CELL, requester_id)
	if not result.ok: return result
	_publish_nation_operations(context.nation, candidate)
	return Runtime.ok("原船真舵手已接受原整船一步；仍须物理完成及停船收据")

func accept_fleet_ship_stop(requester_id: int, nation_id: String, order_id: String, ship_id: String) -> Dictionary:
	if requester_id != int(lab.controlled_person_id()): return Runtime.fail("NO_AUTHORITY")
	var context := _public_context(nation_id, order_id, "fleet")
	if not context.ok or context.order.tech_id != "N12": return context if not context.ok else Runtime.fail("NO_TARGET")
	var order: Dictionary = context.order
	if not order.payload.steps.has(ship_id): return Runtime.fail("NO_COMMAND")
	for receipt: Dictionary in order.receipts:
		if receipt.target_id == "vehicle:" + ship_id: return Runtime.fail("NO_CHANGE")
	var fleet := _fleet_context(context.nation, str(order.payload.corps_id), order.payload.ship_ids, int(order.authorizer_id), false)
	if not fleet.ok: return fleet
	var ship: Dictionary = fleet.transport.records()[ship_id]
	var step: Dictionary = order.payload.steps[ship_id]
	if not ship.move.is_empty() or not ship.command.is_empty() or bool(ship.stop_pending) or int(ship.cell) != int(step.to_cell) \
		or int(ship.revision) <= int(step.accepted_revision) or int(ship.operator_id) != int(step.driver_id): return Runtime.fail("BUSY", "原舵手須完成本命令真船步並停止，不能用接受命令當到達")
	var candidate := _public_candidate(context.nation)
	var next: Dictionary = candidate.public_orders[order_id]
	next.receipts.append({"id": _public_event_id(order, order_id, "fleet", ship_id), "site_id": str(order.scope_site_id), "binding": "fleet", "operator_id": int(ship.operator_id), "target_id": "vehicle:" + ship_id, "work_seconds": 0.0, "item_ids": []})
	next.status = "complete" if _public_order_complete(next) else "active"
	next.revision = int(order.revision) + 1
	if not valid_nation_operation_record(candidate, lab.terrain.site.item_definitions, {}): return Runtime.fail("INVALID")
	_publish_nation_operations(context.nation, candidate)
	return Runtime.ok("此原船已真到本步終點且停穩；兩船完成才有本次編制實績", {"complete": next.status == "complete", "order_id": order_id})

## The original receipt owner supplies its immutable event; no caller-supplied
## 'success' flag, catalog status or ready vehicle can manufacture evidence.
func prepare_public_owner_receipt(nation_id: String, order_id: String, binding_id: String, target_id: String, event_id: String) -> Dictionary:
	var context := _public_context(nation_id, order_id, binding_id)
	if not context.ok: return context
	var order: Dictionary = context.order
	if not PUBLIC_BINDINGS[str(order.tech_id)].has(binding_id) or not nation_owner_receipt_query.is_valid(): return Runtime.fail("UNSUPPORTED", "原完成收据owner尚未接入")
	var queried: Dictionary = nation_owner_receipt_query.call(binding_id, target_id, event_id)
	if not queried.ok: return queried
	var receipt: Variant = queried.get("receipt")
	if not (Technology.keys(receipt, ["id", "site_id", "target_id", "operator_id", "binding", "work_seconds", "item_ids"]) \
		or Technology.keys(receipt, ["id", "site_id", "target_id", "operator_id", "binding", "work_seconds", "item_ids", "effective_seconds"])) \
		or receipt.id != event_id or receipt.site_id != str(lab.terrain.site.id) or receipt.target_id != target_id or receipt.binding != binding_id \
		or not _operation_person(receipt.operator_id, {}) or not Technology.finite_number(receipt.work_seconds) or not receipt.item_ids is Array: return Runtime.fail("INVALID_RECEIPT")
	match str(order.tech_id):
		"N02", "N10":
			if binding_id == "road_build":
				if target_id != "feature:" + str(order.payload.feature_id) or order.receipts.size() != 1: return Runtime.fail("STALE_ORDER")
				if order.tech_id == "N10" and not _mandate_effective(order): return Runtime.fail("EXPIRED_MANDATE")
			elif target_id != _public_order_target(order, order_id) or not order.receipts.is_empty(): return Runtime.fail("STALE_ORDER")
		"N06":
			if binding_id != "house_build" or target_id != "feature:" + str(order.payload.feature_id) or not _public_source_paid(order): return Runtime.fail("STALE_ORDER")
		"N08":
			if binding_id != "public_route" or target_id != str(order.payload.destination_holder) or order.payload.travel_token.is_empty() or not order.payload.loaded: return Runtime.fail("STALE_ROUTE")
		"N11":
			if target_id != str(order.payload.target_id) or target_id.is_empty() or not _public_source_paid(order): return Runtime.fail("STALE_ORDER")
			if binding_id == "arsenal" and order.receipts.size() != 1 or binding_id != "arsenal" and not order.receipts.is_empty(): return Runtime.fail("STALE_ORDER")
		_:
			return Runtime.fail("INVALID", "原physical transfer/PA课程/船步使用各自真提交入口")
	if not public_receipt_effective_ok(receipt, binding_id): return Runtime.fail("INCOMPLETE", "原有效工作未達本固定規則秒數")
	var candidate := _public_candidate(context.nation)
	var next: Dictionary = candidate.public_orders[order_id]
	for prior: Dictionary in next.receipts:
		if prior.id == event_id: return Runtime.fail("NO_CHANGE")
	next.receipts.append({"id": event_id, "site_id": str(receipt.site_id), "binding": binding_id, "operator_id": int(receipt.operator_id), "target_id": target_id, "work_seconds": float(receipt.work_seconds), "item_ids": receipt.item_ids.duplicate()})
	if receipt.has("effective_seconds"): next.receipts[next.receipts.size() - 1]["effective_seconds"] = float(receipt.effective_seconds)
	next.status = "complete" if _public_order_complete(next) else "active"
	next.revision = int(order.revision) + 1
	if not valid_nation_operation_record(candidate, lab.terrain.site.item_definitions, {}): return Runtime.fail("INVALID")
	if not _operations_candidate_claims_valid(nation_id, candidate): return Runtime.fail("REPLAY", "真原event／產品已用於另一國家或具名工單")
	return Runtime.ok("", {"nation_ref": context.nation, "operations": candidate, "complete": next.status == "complete"})

## The original owner calls after ALL original receipt/job/knowledge candidates
## are accepted and publishes this alongside its original successful commit.
func publish_public_owner_receipt(prepared: Dictionary) -> void:
	_publish_nation_operations(prepared.nation_ref, prepared.operations)

# Original national/corps membership references across Region travel. The source
# records remain the only organization authority when only a subset leaves.
static func _portable_ref(value: Variant, kind: String) -> bool:
	return value is Dictionary and value.size() == 3 and value.get("type") == kind and value.get("namespace") is String and not str(value.namespace).is_empty() and str(value.namespace).length() <= 256 and _integer(value.get("lineage"))

static func _portable_whole(value: Variant, low: int = 0, high: int = 2147483647) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value)) and float(value) >= float(low) and float(value) <= float(high)

static func _portable_key(reference: Dictionary) -> String:
	return JSON.stringify([reference.get("type"), reference.get("namespace"), int(reference.get("lineage", 0))])

static func _portable_empty() -> Dictionary:
	return {"version": 1, "remote_people": {}, "remote_teams": {}, "nation_memberships": [], "corps_memberships": []}

static func _portable_local(refs: Dictionary, reference: Dictionary) -> String:
	var wanted := _portable_key(reference)
	for local: String in refs:
		if refs[local] is Dictionary and _portable_key(refs[local]) == wanted: return local
	return ""

static func _portable_shape(value: Variant) -> bool:
	if not value is Dictionary or value.size() != 5 or not _integer(value.get("version")) or int(value.version) != 1 or not value.get("remote_people") is Dictionary or not value.get("remote_teams") is Dictionary or not value.get("nation_memberships") is Array or not value.get("corps_memberships") is Array: return false
	for pair: Array in [["remote_people", "person"], ["remote_teams", "team"]]:
		if value[pair[0]].size() > 65536: return false
		for local: Variant in value[pair[0]]:
			var entry: Variant = value[pair[0]][local]
			if not local is String or not str(local).is_valid_int() or str(int(local)) != local or not _integer(int(local)) or int(local) == 1000000000 or not entry is Dictionary or entry.size() != 3 or not _portable_ref(entry.get("reference"), pair[1]) or not entry.get("token") is String or str(entry.token).is_empty() or str(entry.token).length() > 256 or not _portable_whole(entry.get("faction_id")): return false
	var seen := {}
	if value.nation_memberships.size() > 65536 or value.corps_memberships.size() > 65536: return false
	for entry: Variant in value.nation_memberships:
		if not entry is Dictionary or entry.size() != 5 or not _portable_ref(entry.get("person"), "person") or not _portable_ref(entry.get("nation"), "nation") or not entry.get("source_site_id") is String or str(entry.source_site_id).is_empty() or not entry.get("source_nation_id") is String or not _valid_key(entry.source_nation_id) or not entry.get("office_ids") is Array or entry.office_ids.size() > 4096: return false
		var offices := {}
		for seat: Variant in entry.office_ids:
			if not seat is String or str(seat).is_empty() or str(seat).length() > 64 or offices.has(seat): return false
			offices[seat] = true
		var key := "nation:" + _portable_key(entry.person) + ":" + _portable_key(entry.nation)
		if seen.has(key): return false
		seen[key] = true
	for entry: Variant in value.corps_memberships:
		if not entry is Dictionary or entry.size() != 5 or not _portable_ref(entry.get("team"), "team") or not _portable_ref(entry.get("corps"), "corps") or not _portable_ref(entry.get("commander"), "person") or not entry.get("source_site_id") is String or str(entry.source_site_id).is_empty() or not entry.get("source_corps_id") is String or not _valid_key(entry.source_corps_id): return false
		var key := "corps:" + _portable_key(entry.team) + ":" + _portable_key(entry.corps)
		if seen.has(key): return false
		seen[key] = true
	return true

static func _portable_factions(state: Dictionary) -> Dictionary:
	var result := {"person": {}, "team": {}}
	for actor: Dictionary in state.get("actors", {}).values():
		result.person[str(int(actor.person_id))] = int(actor.faction_id)
	for army: Dictionary in state.get("armies", []):
		result.team[str(int(army.team_id))] = int(army.faction_id)
		for row: Dictionary in army.get("units", []): result.person[str(int(row.person_id))] = int(army.faction_id)
	return result

static func valid_organization_refs(state: Dictionary) -> bool:
	if not state.has("organization_refs"): return true
	var value: Variant = state.organization_refs
	if not _portable_shape(value): return false
	var identity: Variant = state.get("travel_identity", {})
	if not identity is Dictionary or not identity.get("refs") is Dictionary: return false
	var refs: Dictionary = identity.refs
	var factions := _portable_factions(state)
	var registered_people := {}
	var registered_teams := {}
	for nation: Dictionary in state.get("equipment_nations", {}).values():
		for member: Variant in nation.get("members", []): registered_people[str(int(member))] = true
	for corps: Dictionary in state.get("corps", {}).values():
		registered_people[str(int(corps.get("commander_person_id", -1)))] = true
		for team: Variant in corps.get("team_ids", []): registered_teams[str(int(team))] = true
	for pair: Array in [["remote_people", "person", registered_people], ["remote_teams", "team", registered_teams]]:
		for local: String in value[pair[0]]:
			var entry: Dictionary = value[pair[0]][local]
			if factions[pair[1]].has(local) or not pair[2].has(local) or not refs.get(pair[1], {}).has(local) or _portable_key(refs[pair[1]][local]) != _portable_key(entry.reference): return false
	for entry: Dictionary in value.nation_memberships:
		var local := _portable_local(refs.get("person", {}), entry.person)
		if local.is_empty() or not factions.person.has(local): return false
	for entry: Dictionary in value.corps_memberships:
		var team := _portable_local(refs.get("team", {}), entry.team)
		var commander := _portable_local(refs.get("person", {}), entry.commander)
		if not factions.team.has(team) and not factions.person.has(commander): return false
	return true

static func is_remote_organization_person(state: Dictionary, identity: int) -> bool:
	return state.get("organization_refs", {}).get("remote_people", {}).has(str(identity))

static func _portable_append(entries: Array, entry: Dictionary, fields: Array) -> void:
	for old: Dictionary in entries:
		var same := true
		for field: String in fields: same = same and _portable_key(old[field]) == _portable_key(entry[field])
		if same: return
	entries.append(entry.duplicate(true))

static func _portable_mark(remote: Dictionary, local: int, kind: String, token: String, identity: Dictionary, factions: Dictionary) -> bool:
	var key := str(local)
	var reference: Variant = identity.get("refs", {}).get(kind, {}).get(key)
	if not _portable_ref(reference, kind) or not factions[kind].has(key): return false
	remote[key] = {"reference": reference.duplicate(true), "token": token, "faction_id": int(factions[kind][key])}
	return true

# All candidates are detached. Caller uses the same selected original bodies,
# stable identity and transfer token as RegionTravel; it alone publishes them.
static func prepare_region_departure(state: Dictionary, movers: Dictionary, selected_teams: Dictionary, token: String, identity: Dictionary) -> Dictionary:
	if token.is_empty() or token.length() > 256 or not identity.get("refs") is Dictionary or not valid_organization_refs(state): return Runtime.fail("INVALID_ORGANIZATION_TRANSFER")
	var source_nations: Dictionary = state.get("equipment_nations", {}).duplicate(true)
	var source_corps: Dictionary = state.get("corps", {}).duplicate(true)
	var moving_nations := {}
	var moving_corps := {}
	var source: Dictionary = state.get("organization_refs", _portable_empty()).duplicate(true)
	var moving := _portable_empty()
	var factions := _portable_factions(state)
	var source_id := str(state.get("id", ""))
	if source_id.is_empty(): return Runtime.fail("INVALID_ORGANIZATION_TRANSFER")
	for person: Variant in movers:
		if not _integer(person) or int(person) == 1000000000 or not factions.person.has(str(int(person))) or not _portable_ref(identity.refs.get("person", {}).get(str(int(person))), "person"): return Runtime.fail("INVALID_ORGANIZATION_TRANSFER")
	for team: Variant in selected_teams:
		if not _integer(team) or not _portable_ref(identity.refs.get("team", {}).get(str(int(team))), "team"): return Runtime.fail("INVALID_ORGANIZATION_TRANSFER")
	# Forward existing foreign membership refs with their original person/team.
	for entry: Dictionary in source.nation_memberships.duplicate(true):
		var local := _portable_local(identity.refs.get("person", {}), entry.person)
		if not local.is_empty() and movers.has(int(local)):
			_portable_append(moving.nation_memberships, entry, ["person", "nation"])
			source.nation_memberships.erase(entry)
	for entry: Dictionary in source.corps_memberships.duplicate(true):
		var team := _portable_local(identity.refs.get("team", {}), entry.team)
		var commander := _portable_local(identity.refs.get("person", {}), entry.commander)
		if not team.is_empty() and selected_teams.has(int(team)) or not commander.is_empty() and movers.has(int(commander)):
			_portable_append(moving.corps_memberships, entry, ["team", "corps"])
			if (team.is_empty() or selected_teams.has(int(team))) and (commander.is_empty() or movers.has(int(commander))): source.corps_memberships.erase(entry)
	for nation_id: String in source_nations.keys():
		var nation: Dictionary = source_nations[nation_id]
		var touched := false
		var all_moving := true
		for member: Variant in nation.members:
			touched = touched or movers.has(int(member))
			all_moving = all_moving and movers.has(int(member))
		if not touched: continue
		if all_moving:
			if nation.has("ransom_data"):
				if not RansomData.valid_record(nation.ransom_data): return Runtime.fail("CORRUPT_STATE", "國庫資料版本／格式非法")
				if not nation.ransom_data.treasury.is_empty():
					return Runtime.fail("TREASURY_TRANSFER_UNSUPPORTED", "已綁國庫留在原 Site，須先由合法管理入口解除；本版不移轉國庫權威")
			moving_nations[nation_id] = nation
			source_nations.erase(nation_id)
			continue
		var nation_ref: Variant = identity.refs.get("nation", {}).get(nation_id)
		if not _portable_ref(nation_ref, "nation"): return Runtime.fail("INVALID_ORGANIZATION_TRANSFER")
		for member: Variant in nation.members:
			var person := int(member)
			if not movers.has(person): continue
			if not _portable_mark(source.remote_people, person, "person", token, identity, factions): return Runtime.fail("INVALID_ORGANIZATION_TRANSFER")
			var office_ids: Array[String] = []
			var original_offices: Dictionary = nation.get("offices", SiteOffices.legacy_nation_offices(int(nation.get("military_head", -1))))
			for seat: Dictionary in original_offices.positions:
				if int(seat.holder) == person: office_ids.append(str(seat.id))
			_portable_append(moving.nation_memberships, {"person": identity.refs.person[str(person)].duplicate(true), "nation": nation_ref.duplicate(true),
				"source_site_id": source_id, "source_nation_id": nation_id, "office_ids": office_ids}, ["person", "nation"])
	for corps_id: String in source_corps.keys():
		var corps: Dictionary = source_corps[corps_id]
		var commander := int(corps.commander_person_id)
		var touched := movers.has(commander)
		var all_moving := movers.has(commander)
		for team: Variant in corps.team_ids:
			touched = touched or selected_teams.has(int(team))
			all_moving = all_moving and selected_teams.has(int(team))
		if not touched: continue
		if all_moving:
			moving_corps[corps_id] = corps
			source_corps.erase(corps_id)
			continue
		var corps_ref: Variant = identity.refs.get("corps", {}).get(corps_id)
		var commander_ref: Variant = identity.refs.get("person", {}).get(str(commander))
		if not _portable_ref(corps_ref, "corps") or not _portable_ref(commander_ref, "person"): return Runtime.fail("INVALID_ORGANIZATION_TRANSFER")
		if movers.has(commander) and not _portable_mark(source.remote_people, commander, "person", token, identity, factions): return Runtime.fail("INVALID_ORGANIZATION_TRANSFER")
		for team: Variant in corps.team_ids:
			var team_id := int(team)
			if not selected_teams.has(team_id) and not movers.has(commander): continue
			var team_ref: Variant = identity.refs.get("team", {}).get(str(team_id))
			if not _portable_ref(team_ref, "team"): return Runtime.fail("INVALID_ORGANIZATION_TRANSFER")
			if selected_teams.has(team_id) and not _portable_mark(source.remote_teams, team_id, "team", token, identity, factions): return Runtime.fail("INVALID_ORGANIZATION_TRANSFER")
			_portable_append(moving.corps_memberships, {"team": team_ref.duplicate(true), "corps": corps_ref.duplicate(true), "commander": commander_ref.duplicate(true),
				"source_site_id": source_id, "source_corps_id": corps_id}, ["team", "corps"])
	return Runtime.ok("", {"source_nations": source_nations, "source_corps": source_corps, "moving_nations": moving_nations, "moving_corps": moving_corps,
		"source_refs": source, "moving_refs": moving})

# Arrival's mapping is the original RegionTravel receipt. No seat/member field
# is rewritten from a portable claim; a local original authority stays current.
static func prepare_region_arrival(destination: Dictionary, incoming: Dictionary, identity: Dictionary, mapping: Dictionary) -> Dictionary:
	if not _portable_shape(incoming) or not _portable_shape(destination.get("organization_refs", _portable_empty())) or not identity.get("refs") is Dictionary or not mapping.get("maps") is Dictionary or str(mapping.get("token", "")).is_empty(): return Runtime.fail("INVALID_ORGANIZATION_TRANSFER")
	if not incoming.remote_people.is_empty() or not incoming.remote_teams.is_empty(): return Runtime.fail("INVALID_ORGANIZATION_TRANSFER")
	var result: Dictionary = destination.get("organization_refs", _portable_empty()).duplicate(true)
	var destination_refs: Dictionary = destination.get("travel_identity", {}).get("refs", {})
	var arrived := {"person": {}, "team": {}}
	for kind: String in ["person", "team"]:
		for old: String in identity.refs.get(kind, {}):
			var reference: Dictionary = identity.refs[kind][old]
			if not _portable_ref(reference, kind) or not mapping.maps.get(kind, {}).has(old): return Runtime.fail("INVALID_ORGANIZATION_TRANSFER")
			var local := str(mapping.maps[kind][old])
			if not destination_refs.get(kind, {}).has(local) or _portable_key(destination_refs[kind][local]) != _portable_key(reference): return Runtime.fail("INVALID_ORGANIZATION_TRANSFER")
			arrived[kind][_portable_key(reference)] = local
	for pair: Array in [["remote_people", "person"], ["remote_teams", "team"]]:
		for local: String in result[pair[0]].keys():
			var reference: Dictionary = result[pair[0]][local].reference
			var key := _portable_key(reference)
			if not arrived[pair[1]].has(key): continue
			if str(arrived[pair[1]][key]) != local: return Runtime.fail("ORGANIZATION_MAPPING_CONFLICT")
			result[pair[0]].erase(local)
	for entry: Dictionary in incoming.nation_memberships:
		if not arrived.person.has(_portable_key(entry.person)): return Runtime.fail("INVALID_ORGANIZATION_TRANSFER")
		var local_nation := _portable_local(destination_refs.get("nation", {}), entry.nation)
		if not local_nation.is_empty() and destination.get("equipment_nations", {}).has(local_nation): continue
		_portable_append(result.nation_memberships, entry, ["person", "nation"])
	for entry: Dictionary in incoming.corps_memberships:
		if not arrived.team.has(_portable_key(entry.team)) and not arrived.person.has(_portable_key(entry.commander)): return Runtime.fail("INVALID_ORGANIZATION_TRANSFER")
		var local_corps := _portable_local(destination_refs.get("corps", {}), entry.corps)
		if not local_corps.is_empty() and destination.get("corps", {}).has(local_corps): continue
		_portable_append(result.corps_memberships, entry, ["team", "corps"])
	return Runtime.ok("", {"organization_refs": result})


func _arsenal_workshop_context(order: Dictionary) -> Dictionary:
	var payload: Dictionary = order.payload
	var feature: Dictionary = lab.terrain.site.features.get(str(payload.host_id), {})
	var settlement := Settlement.record(lab.terrain)
	var skill := "F04" if payload.route == "armor" else "F11"
	if payload.route != "armor":
		var runtime_script: Variant = Runtime
		if not runtime_script.has_method("technology_siege_yard_context"): return Runtime.fail("UNIMPLEMENTED", "原校場器械場查詢尚未接妥")
		var yard: Dictionary = runtime_script.call("technology_siege_yard_context", lab.terrain, str(payload.host_id), true)
		if not yard.ok: return yard
		if yard.get("work_eligible") != true or not is_same(yard.get("feature"), feature) or not is_same(yard.get("settlement"), settlement): return Runtime.fail("STALE_SOURCE")
	if feature.is_empty() or (payload.route == "armor" and str(feature.get("kind")) != "smithy") \
		or str(feature.get("stage")) != "complete" or not Runtime.feature_usable(feature) \
		or not bool(Settlement.status(lab).effective) or not Settlement.feature_in_jurisdiction(lab.terrain, feature) \
		or int(feature.get("owner_faction", -1)) != int(settlement.get("owner_faction", -2)) \
		or not Technology.scope_known(settlement.get("technology", {}), "S13" if payload.route == "armor" else "S11"): return Runtime.fail("NO_WORKSHOP")
	var person: Dictionary = actions._person(int(payload.operator_id))
	if person.is_empty() or float(person.hp) <= 0.0 or float(person.ko) > 0.0 or bool(person.captive) \
		or int(person.faction) != int(feature.owner_faction) or not Technology.learned(actions._body_get(person, "technology"), skill): return Runtime.fail("NO_WORKER")
	return Runtime.ok("", {"feature": feature, "person": person})

# APPEND; no request.operations/caller approval can serve as owner authority.

# APPEND; no request.operations/caller approval can serve as owner authority.

func prepare_equipment_change(order: Dictionary, source_only: bool = false) -> Dictionary:
	var source: Dictionary = _equipment_exchange_source(order)
	if not source.ok: return source
	var checked: Dictionary = check(order)
	if not checked.ok: return checked
	var stable: Dictionary = _equipment_exchange_source_valid(source)
	if not stable.ok: return stable
	var military: Dictionary = _military_issue_check(order)
	if not military.ok: return military
	var phase: Dictionary = {}
	if not source_only:
		var receipt: Dictionary = actions.prepare_nation_military_issue_receipt(order, military)
		if not receipt.ok: return receipt
		phase = receipt.phase
	var prepared: Dictionary = Runtime.ok("", {"source": source, "order": order, "military": military,
		"phase": phase, "source_only": source_only, "published": false,
		"result": Runtime.ok("原裝退回、新裝實際領取；沒有發放不存在的物品")})
	stable = _equipment_exchange_source_valid(source)
	return prepared if stable.ok else stable

func validate_equipment_change(prepared: Dictionary, require_completion: bool = true) -> Dictionary:
	if prepared.get("ok") != true or prepared.get("published") != false: return Runtime.fail("STALE_SOURCE")
	if require_completion and bool(prepared.get("source_only", true)): return Runtime.fail("SOURCE_ONLY")
	var source: Dictionary = prepared.get("source", {})
	if not is_same(prepared.get("order"), source.get("order")) or str(source.get("mode", "")) == "team_issue": return Runtime.fail("INVALID")
	if prepared.get("result") != Runtime.ok("原裝退回、新裝實際領取；沒有發放不存在的物品"): return Runtime.fail("INVALID")
	var stable: Dictionary = _equipment_exchange_source_valid(source)
	if not stable.ok: return stable
	var checked: Dictionary = check(source.order)
	if not checked.ok: return checked
	var military: Dictionary = _military_issue_check(source.order)
	if not military.ok: return military
	if military.has("production") != prepared.military.has("production"): return Runtime.fail("STALE_ORDER")
	if military.has("production") and (not is_same(military.production, prepared.military.production) or not is_same(military.nation, prepared.military.nation) or military.product != prepared.military.product): return Runtime.fail("STALE_ORDER")
	if bool(prepared.source_only):
		if not prepared.phase.is_empty(): return Runtime.fail("INVALID_RECEIPT")
	else:
		var receipt: Dictionary = actions.prepare_nation_military_issue_receipt(source.order, military)
		if not receipt.ok: return receipt
		if prepared.phase.is_empty() != receipt.phase.is_empty(): return Runtime.fail("INVALID_RECEIPT")
		if not prepared.phase.is_empty():
			var phase: Dictionary = prepared.phase
			var expected: Dictionary = receipt.phase
			if not is_same(phase.owner, expected.owner) or not is_same(phase.record, expected.record) or not is_same(phase.site_state, expected.site_state) \
				or not is_same(phase.person.body, expected.person.body) or phase.state != expected.state or phase.person_candidate != expected.person_candidate or phase.complete != expected.complete: return Runtime.fail("INVALID_RECEIPT")
	# Original visual/current-duty callbacks above precede every holder change.
	# Verify the same held endpoints again; no source-only proposal is completion.
	return _equipment_exchange_source_valid(source)

func publish_equipment_change(prepared: Dictionary) -> void:
	assert(prepared.ok and not prepared.published and not prepared.source_only)
	var source: Dictionary = prepared.source
	var order: Dictionary = source.order
	var holder: Dictionary = source.people[0].holder
	# The original synchronous swap is indivisible; two separate transfers would
	# wrongly reject an exchange that frees and fills capacity in the same tail.
	if str(order.mode) == "issue":
		var depot: Dictionary = source.depot
		for identity: String in order["return"]:
			holder.item_ids.erase(identity)
			depot.item_ids.append(identity)
			source.records[identity].holder = "depot"
		for identity: String in order.take:
			depot.item_ids.erase(identity)
			holder.item_ids.append(identity)
			source.records[identity].holder = str(holder.holder)
		depot.version = int(depot.version) + 1
	holder.equipped.clear()
	holder.equipped.merge(order.planned)
	holder.version = int(holder.version) + 1
	_publish_military_issue(prepared.military)
	if not prepared.phase.is_empty(): actions.publish_phase_receipt(prepared.phase)
	prepared.published = true
	# The original presentation observes only the fully committed owner graph.
	source.notification.call(int(order.person_id))

func prepare_team_equipment_change(order: Dictionary, source_only: bool = false) -> Dictionary:
	var source: Dictionary = _equipment_exchange_source(order)
	if not source.ok: return source
	var checked: Dictionary = check_team_issue(order)
	if not checked.ok: return checked
	var changed_ids: Array[int] = []
	for entry: Dictionary in order.entries:
		if entry.planned != entry.before: changed_ids.append(int(entry.person_id))
	var prepared: Dictionary = Runtime.ok("", {"source": source, "order": order,
		"source_only": source_only, "published": false,
		"result": Runtime.ok("整隊原實物已一次換裝；未生成物品", {"target_ids": order.target_ids.duplicate(), "changed_ids": changed_ids})})
	var stable: Dictionary = _equipment_exchange_source_valid(source)
	return prepared if stable.ok else stable

func validate_team_equipment_change(prepared: Dictionary, require_completion: bool = true) -> Dictionary:
	if prepared.get("ok") != true or prepared.get("published") != false: return Runtime.fail("STALE_SOURCE")
	if require_completion and bool(prepared.get("source_only", true)): return Runtime.fail("SOURCE_ONLY")
	var source: Dictionary = prepared.get("source", {})
	if not is_same(prepared.get("order"), source.get("order")) or str(source.get("mode", "")) != "team_issue": return Runtime.fail("INVALID")
	var stable: Dictionary = _equipment_exchange_source_valid(source)
	if not stable.ok: return stable
	var changed_ids: Array[int] = []
	for entry: Dictionary in source.order.entries:
		if entry.planned != entry.before: changed_ids.append(int(entry.person_id))
	if prepared.get("result") != Runtime.ok("整隊原實物已一次換裝；未生成物品", {"target_ids": source.order.target_ids.duplicate(), "changed_ids": changed_ids}): return Runtime.fail("INVALID")
	var checked: Dictionary = check_team_issue(source.order)
	if not checked.ok: return checked
	return _equipment_exchange_source_valid(source)

func publish_team_equipment_change(prepared: Dictionary) -> void:
	assert(prepared.ok and not prepared.published and not prepared.source_only)
	var source: Dictionary = prepared.source
	var order: Dictionary = source.order
	var depot: Dictionary = source.depot
	for entry: Dictionary in order.entries:
		if entry.planned == entry.before: continue
		var holder: Dictionary = entry.holder
		for item_id: String in entry["return"]:
			holder.item_ids.erase(item_id)
			depot.item_ids.append(item_id)
			source.records[item_id].holder = "depot"
		for item_id: String in entry.take:
			depot.item_ids.erase(item_id)
			holder.item_ids.append(item_id)
			source.records[item_id].holder = str(holder.holder)
		holder.equipped.clear()
		holder.equipped.merge(entry.planned)
		holder.version = int(holder.version) + 1
	depot.version = int(depot.version) + 1
	prepared.published = true
	for identity: int in prepared.result.changed_ids: source.notification.call(identity)

func _equipment_exchange_order_signature(order: Dictionary) -> Dictionary:
	var signature: Dictionary = order.duplicate(false)
	if str(order.get("mode", "")) == "team_issue":
		for key: String in ["terrain", "site_state", "team", "requester_owner", "requester_body", "representative_owner", "representative_body", "representative_holder", "representative_cargo", "nation_ref", "standard_ref", "depot_holder", "depot_stock", "records_owner", "definitions_owner"]: signature.erase(key)
		var entries: Array = []
		for entry: Dictionary in order.get("entries", []):
			var pure: Dictionary = entry.duplicate(false)
			for key: String in ["owner", "body", "holder", "cargo"]: pure.erase(key)
			entries.append(pure)
		signature.entries = entries
	return signature.duplicate(true)

func _equipment_exchange_source(order: Dictionary) -> Dictionary:
	if not is_instance_valid(lab) or actions == null or not is_same(actions.lab, lab): return Runtime.fail("STALE_SOURCE")
	var mode: String = str(order.get("mode", ""))
	if mode not in ["issue", "personal", "retire_cape", "team_issue"]: return Runtime.fail("INVALID")
	var identities: Array = order.get("target_ids", []).duplicate() if mode == "team_issue" else [int(order.get("person_id", -1))]
	if mode == "team_issue":
		for identity: int in [int(order.get("requester_id", -1)), int(order.get("representative_id", -1))]:
			if not identities.has(identity): identities.append(identity)
	if identities.is_empty(): return Runtime.fail("NO_TARGET")
	var source: Dictionary = Runtime.ok("", {"order": order, "mode": mode, "order_before": _equipment_exchange_order_signature(order),
		"lab": lab, "actions": actions, "terrain": lab.terrain, "site_state": lab.terrain.site, "people": [],
		"records": lab.terrain.site.item_records, "definitions": lab.terrain.site.item_definitions,
		"item_refs": {}, "item_before": {}, "definition_refs": {}, "definition_before": {},
		"depot": {}, "stock": {}, "stock_before": {}, "depot_before": {}, "standard": {}, "standard_before": {},
		"nation": {}, "military": {}, "notification": actions.equipment_changed})
	var item_ids: Array = []
	for identity: int in identities:
		var person: Dictionary = actions._person(identity)
		if person.is_empty(): return Runtime.fail("NO_TARGET")
		source.people.append({"person_id": identity, "owner": person.owner, "body": person.body, "holder": person.holder, "cargo": person.cargo,
			"cell": person.cell, "hit": int(person.hit), "holder_before": person.holder.duplicate(true), "cargo_before": person.cargo.duplicate(true)})
		for item_id: String in person.holder.item_ids:
			if not item_ids.has(item_id): item_ids.append(item_id)
	if mode in ["issue", "team_issue"]:
		source.depot = lab.terrain.site.depot_items
		source.stock = lab.terrain.site.inventory
		source.stock_before = source.stock.duplicate(true)
		source.depot_before = source.depot.duplicate(true)
		source.capacity = int(lab.terrain.site.capacity)
		for item_id: String in source.depot.item_ids:
			if not item_ids.has(item_id): item_ids.append(item_id)
		source.nation = lab.terrain.site.get("equipment_nations", {}).get(str(order.get("nation_id", "")), {})
		source.standard = _standard(int(identities[0]), str(order.get("nation_id", "")), str(order.get("standard_id", "")))
		source.standard_before = source.standard.duplicate(true)
		source.culture = str(source.nation.get("culture", ""))
	if order.has("military_production_id"):
		var military: Dictionary = _military_issue_check(order)
		if not military.ok: return military
		source.military = {"nation": military.nation, "production": military.production, "before": military.production.duplicate(true),
			"operations": military.nation.technology_operations, "technology": military.nation.technology,
			"technology_before": military.nation.technology.duplicate(true)}
	for item_id: String in item_ids:
		var record: Dictionary = source.records.get(item_id, {})
		var definition_id: String = str(record.get("definition", ""))
		var definition: Dictionary = source.definitions.get(definition_id, {})
		source.item_refs[item_id] = record
		source.item_before[item_id] = record.duplicate(true)
		source.definition_refs[definition_id] = definition
		source.definition_before[definition_id] = definition.duplicate(true)
	return source

func _equipment_exchange_source_valid(source: Dictionary) -> Dictionary:
	if not source.get("order") is Dictionary or not source.get("people") is Array or not source.get("military") is Dictionary: return Runtime.fail("INVALID")
	if source.get("ok") != true or not is_same(source.get("lab"), lab) or not is_instance_valid(lab) or actions == null \
		or not is_same(source.get("actions"), actions) or not is_same(actions.lab, lab) \
		or not is_same(source.get("terrain"), lab.terrain) or not is_same(source.get("site_state"), lab.terrain.site) \
		or not is_same(source.get("records"), lab.terrain.site.item_records) or not is_same(source.get("definitions"), lab.terrain.site.item_definitions) \
		or source.order_before != _equipment_exchange_order_signature(source.order) or source.notification != actions.equipment_changed or not source.notification.is_valid(): return Runtime.fail("STALE_SOURCE")
	if source.mode != str(source.order.get("mode", "")): return Runtime.fail("INVALID")
	var identities: Array = source.order.get("target_ids", []).duplicate() if source.mode == "team_issue" else [int(source.order.get("person_id", -1))]
	if source.mode == "team_issue":
		for identity: int in [int(source.order.get("requester_id", -1)), int(source.order.get("representative_id", -1))]:
			if not identities.has(identity): identities.append(identity)
	if source.people.size() != identities.size() or source.order.has("military_production_id") != (not source.military.is_empty()): return Runtime.fail("INVALID")
	for index: int in identities.size():
		if not source.people[index] is Dictionary or int(source.people[index].get("person_id", -1)) != int(identities[index]): return Runtime.fail("INVALID")
	for held: Dictionary in source.people:
		var person: Dictionary = actions._person(int(held.person_id))
		if person.is_empty() or not is_same(person.owner, held.owner) or not is_same(person.body, held.body) \
			or not is_same(person.holder, held.holder) or not is_same(person.cargo, held.cargo) or person.cell != held.cell or int(person.hit) != int(held.hit) \
			or person.holder != held.holder_before or person.cargo != held.cargo_before: return Runtime.fail("STALE_SOURCE")
		# Original retirement may remove the cape from an existing incapacitated
		# body; every ordinary issue still uses the original readiness predicate.
		if source.mode != "retire_cape" and not _ready(person).ok: return Runtime.fail("BUSY")
	if source.mode in ["issue", "team_issue"]:
		if not is_same(source.depot, lab.terrain.site.depot_items) or not is_same(source.stock, lab.terrain.site.inventory) \
			or source.depot != source.depot_before or source.stock != source.stock_before or int(lab.terrain.site.capacity) != int(source.capacity): return Runtime.fail("STALE_SOURCE")
		var nation: Dictionary = lab.terrain.site.get("equipment_nations", {}).get(str(source.order.nation_id), {})
		var standard: Dictionary = _standard(int(source.people[0].person_id), str(source.order.nation_id), str(source.order.standard_id))
		if not is_same(nation, source.nation) or not is_same(standard, source.standard) or standard != source.standard_before or str(nation.get("culture", "")) != source.culture: return Runtime.fail("STALE_SPEC")
	if not source.military.is_empty():
		var held: Dictionary = source.military
		var nation: Dictionary = lab.terrain.site.get("equipment_nations", {}).get(str(source.order.nation_id), {})
		if not is_same(nation, held.nation) or not is_same(nation.get("technology_operations"), held.operations) \
			or not is_same(held.operations.orders.get(str(source.order.military_production_id)), held.production) or held.production != held.before \
			or not is_same(nation.get("technology"), held.technology) or held.technology != held.technology_before: return Runtime.fail("STALE_ORDER")
	# The descriptor must cover exactly the original order participants and
	# every real item referenced by these holders. Omitting a held snapshot
	# cannot turn an equal replacement into the original source object.
	var item_ids: Array = []
	for held: Dictionary in source.people:
		for item_id: String in held.holder.item_ids:
			if not item_ids.has(item_id): item_ids.append(item_id)
	if source.mode in ["issue", "team_issue"]:
		for item_id: String in source.depot.item_ids:
			if not item_ids.has(item_id): item_ids.append(item_id)
	if source.item_refs.size() != item_ids.size() or source.item_before.size() != item_ids.size(): return Runtime.fail("INVALID")
	var definition_ids: Array = []
	for item_id: String in item_ids:
		if not source.item_refs.has(item_id) or not source.item_before.has(item_id): return Runtime.fail("INVALID")
		var definition_id: String = str(source.records.get(item_id, {}).get("definition", ""))
		if not definition_ids.has(definition_id): definition_ids.append(definition_id)
	if source.definition_refs.size() != definition_ids.size() or source.definition_before.size() != definition_ids.size(): return Runtime.fail("INVALID")
	for definition_id: String in definition_ids:
		if not source.definition_refs.has(definition_id) or not source.definition_before.has(definition_id): return Runtime.fail("INVALID")
	for item_id: String in source.item_refs:
		if not is_same(source.records.get(item_id), source.item_refs[item_id]) or source.records.get(item_id) != source.item_before[item_id]: return Runtime.fail("STALE_SOURCE")
	for definition_id: String in source.definition_refs:
		if not is_same(source.definitions.get(definition_id), source.definition_refs[definition_id]) or source.definitions.get(definition_id) != source.definition_before[definition_id]: return Runtime.fail("STALE_SOURCE")
	return Runtime.ok()

func prepare_funded_course_source(nation_id: String, order_id: String, original_job: Dictionary) -> Dictionary:
	var context: Dictionary = _public_context(nation_id, order_id, "funded_course")
	if not context.ok or context.order.tech_id != "N07": return context if not context.ok else Runtime.fail("NO_TARGET")
	var order: Dictionary = context.order
	var teacher_id: int = int(order.payload.teacher_id)
	var student_id: int = int(original_job.get("target_id", -1))
	if not is_same(original_job, actions._jobs.get(str(teacher_id), {})) or original_job.get("kind") != "technology_lesson" \
		or original_job.get("nation_course_id") != order_id or original_job.get("nation_course_nation") != nation_id \
		or int(original_job.get("executor_id", -1)) != teacher_id or not order.payload.student_ids.has(student_id) \
		or not Technology.finite_number(original_job.get("duration"), 300.0) or not _public_source_paid(order): return Runtime.fail("STALE_COURSE")
	var lesson: Dictionary = actions._technology_lesson_context(original_job)
	if not lesson.ok: return lesson
	for receipt: Dictionary in order.receipts:
		if receipt.target_id == "person:" + str(student_id): return Runtime.fail("NO_CHANGE")
	var teacher: Dictionary = actions._person(teacher_id)
	var student: Dictionary = actions._person(student_id)
	var stock: Dictionary = Stockpiles.stock_endpoint(lab.terrain, str(order.payload.reserve_feature_id))
	if teacher.is_empty() or student.is_empty() or stock.is_empty() or teacher.cell != stock.cell \
		or int(teacher.faction) != int(stock.faction) or int(student.faction) != int(stock.faction) \
		or absi(teacher.cell.x - student.cell.x) + absi(teacher.cell.y - student.cell.y) > 1 \
		or Technology.learned(actions._body_get(student, "technology"), str(order.payload.skill_id)): return Runtime.fail("UNREACHABLE")
	var source: Dictionary = Runtime.ok("原有限糧儲／真師徒付款來源已純核", {"nation_id": nation_id, "order_id": order_id,
		"nation_ref": context.nation, "operations_ref": context.nation.technology_operations, "order": order,
		"order_before": order.duplicate(true), "job": original_job, "teacher_body": teacher.body, "student_body": student.body,
		"source": stock.holder, "source_cargo": stock.cargo, "destination": teacher.holder, "destination_cargo": teacher.cargo,
		"terrain": lab.terrain, "site_state": lab.terrain.site, "transfer": {}})
	source.transfer = Runtime.prepare_item_transfer(lab.terrain, stock.holder, stock.cargo, teacher.holder, teacher.cargo,
		{"grain": 2}, [], int(stock.holder.version), int(teacher.holder.version), Runtime.CARRY_CAPACITY)
	if not source.transfer.ok: return source.transfer
	var stable: Dictionary = validate_funded_course_source(source)
	return source if stable.ok else stable

func validate_funded_course_source(source: Dictionary) -> Dictionary:
	if source.get("ok") != true or not is_same(source.get("terrain"), lab.terrain) or not is_same(source.get("site_state"), lab.terrain.site): return Runtime.fail("STALE_SOURCE")
	var context: Dictionary = _public_context(str(source.get("nation_id", "")), str(source.get("order_id", "")), "funded_course")
	if not context.ok: return context
	var order: Dictionary = context.order
	if order.tech_id != "N07" or not is_same(context.nation, source.get("nation_ref")) \
		or not is_same(context.nation.technology_operations, source.get("operations_ref")) or not is_same(order, source.get("order")) \
		or order != source.get("order_before") or not _public_source_paid(order): return Runtime.fail("STALE_COURSE")
	var job: Dictionary = source.get("job", {})
	if not is_same(actions._jobs.get(str(int(order.payload.teacher_id)), {}), job) or job.get("kind") != "technology_lesson" \
		or job.get("nation_course_id") != source.order_id or job.get("nation_course_nation") != source.nation_id \
		or int(job.get("executor_id", -1)) != int(order.payload.teacher_id) or not order.payload.student_ids.has(int(job.get("target_id", -1))): return Runtime.fail("STALE_COURSE")
	var lesson: Dictionary = actions._technology_lesson_context(job)
	if not lesson.ok: return lesson
	var teacher: Dictionary = actions._person(int(job.executor_id))
	var student: Dictionary = actions._person(int(job.target_id))
	var stock: Dictionary = Stockpiles.stock_endpoint(lab.terrain, str(order.payload.reserve_feature_id))
	if teacher.is_empty() or student.is_empty() or stock.is_empty() or not is_same(teacher.body, source.teacher_body) \
		or not is_same(student.body, source.student_body) or teacher.cell != stock.cell \
		or int(teacher.faction) != int(stock.faction) or int(student.faction) != int(stock.faction) \
		or absi(teacher.cell.x - student.cell.x) + absi(teacher.cell.y - student.cell.y) > 1 \
		or not is_same(stock.holder, source.source) or not is_same(stock.cargo, source.source_cargo) \
		or not is_same(teacher.holder, source.destination) or not is_same(teacher.cargo, source.destination_cargo): return Runtime.fail("STALE_SOURCE")
	var transfer: Dictionary = source.get("transfer", {})
	if not is_same(transfer.get("source"), stock.holder) or not is_same(transfer.get("source_cargo"), stock.cargo) \
		or not is_same(transfer.get("destination"), teacher.holder) or not is_same(transfer.get("destination_cargo"), teacher.cargo) \
		or transfer.get("resources") != {"grain": 2} or not transfer.get("selected", {}).is_empty() \
		or int(transfer.get("capacity", -1)) != Runtime.CARRY_CAPACITY or bool(transfer.get("preserve_slots", true)): return Runtime.fail("INVALID")
	return Runtime.validate_prepared_item_transfer(transfer)

func _funded_course_operations_candidate(source: Dictionary) -> Dictionary:
	var candidate: Dictionary = _public_candidate(source.nation_ref)
	var order: Dictionary = source.order
	var next: Dictionary = candidate.public_orders[str(source.order_id)]
	next.receipts.append({"id": _public_event_id(order, str(source.order_id), "lesson", str(int(source.job.target_id))),
		"site_id": str(order.scope_site_id), "binding": "funded_course", "operator_id": int(source.job.executor_id),
		"target_id": "person:" + str(int(source.job.target_id)), "work_seconds": float(source.job.duration), "item_ids": []})
	next.status = "complete" if _public_order_complete(next) else "active"
	next.revision = int(order.revision) + 1
	return candidate if valid_nation_operation_record(candidate, lab.terrain.site.item_definitions, {}) else {}

func validate_funded_course_payment(prepared: Dictionary) -> Dictionary:
	if prepared.get("ok") != true or prepared.get("published") != false: return Runtime.fail("STALE_COURSE")
	var source: Dictionary = prepared.get("course_source", {})
	var checked: Dictionary = validate_funded_course_source(source)
	if not checked.ok: return checked
	var job: Dictionary = source.job
	if not is_same(prepared.get("nation_ref"), source.nation_ref) or not Technology.finite_number(job.get("duration"), 300.0) \
		or not Technology.finite_number(job.get("elapsed")) or float(job.elapsed) + 0.00000001 < float(job.duration) \
		or not Technology.learned(prepared.get("learned_candidate", {}), str(source.order.payload.skill_id)) \
		or prepared.get("operations") != _funded_course_operations_candidate(source): return Runtime.fail("STALE_COURSE")
	return Runtime.ok()

func publish_funded_course_payment(prepared: Dictionary) -> void:
	assert(prepared.ok and not prepared.published)
	# The current original transfer and Nops candidates have both passed; no
	# callback/rejection/yield can occur between the one stipend and its receipt.
	Runtime.publish_item_transfer(prepared.course_source.transfer)
	_publish_nation_operations(prepared.nation_ref, prepared.operations)
	prepared.published = true

func _publish_nation_operations(nation: Dictionary, candidate: Dictionary) -> void:
	if not nation.has("technology_operations"):
		nation.technology_operations = candidate
		return
	var original: Dictionary = nation.technology_operations
	assert(not is_same(original, candidate))
	var next := candidate.duplicate() # only the publication envelope
	for field: String in ["orders", "public_orders", "specs", "certificates"]:
		if not original.has(field) or not next.has(field): continue
		var original_orders: Dictionary = original[field]
		var next_orders: Dictionary = next[field].duplicate()
		for key: String in next_orders:
			if not original_orders.has(key): continue
			var old_order: Dictionary = original_orders[key]
			old_order.clear()
			old_order.merge(next_orders[key], true)
			next_orders[key] = old_order
		original_orders.clear()
		original_orders.merge(next_orders, true)
		next[field] = original_orders
	original.clear()
	original.merge(next, true)

func military_work_preflight(nation_id: String, order_id: String) -> Dictionary:
	var nation: Dictionary = lab.terrain.site.get("equipment_nations", {}).get(nation_id, {})
	var operations: Dictionary = nation.get("technology_operations", {})
	if not valid_nation_operation_record(operations, lab.terrain.site.item_definitions, {}): return Runtime.fail("CORRUPT_STATE")
	var order: Dictionary = operations.get("orders", {}).get(order_id, {})
	if order.is_empty() or order.get("status") != "active" or order.receipt_ids.size() >= int(order.max_batches): return Runtime.fail("STALE_ORDER")
	var checked := _nation_operation_context(int(order.authorizer_id), nation_id, "nation.production", "N05", "workshop_bow", true)
	if not checked.ok: return checked
	var certificate := _certificate_context(nation, str(order.certificate_id), int(order.operator_id), true)
	if not certificate.ok or int(certificate.certificate.revision) != int(order.certificate_revision): return Runtime.fail("STALE_CERTIFICATE")
	if certificate.certificate.industry_id != "S07" or certificate.certificate.feature_id != order.feature_id: return Runtime.fail("SPEC_MISMATCH")
	var standard := _standard(int(order.recipient_id), nation_id, str(order.standard_id))
	if standard.is_empty() or int(standard.revision) != int(order.standard_revision) or not _nation_person_ok(nation, int(order.recipient_id)): return Runtime.fail("STALE_SPEC")
	if not standard.slots.has("weapon") or "weapon:bow_01" not in [standard.slots.weapon.definition] + standard.slots.weapon.alternatives: return Runtime.fail("SPEC_MISMATCH")
	var feature: Dictionary = certificate.workshop.feature
	if not is_same(feature, lab.terrain.site.get("features", {}).get(str(order.feature_id))) or str(feature.get("supply_mode", "")) != "local": return Runtime.fail("STALE_SOURCE")
	if order.source.is_empty() or order.source.status != "granted" or order.source.site_id != str(lab.terrain.site.id): return Runtime.fail("NO_BUDGET")
	for resource: String in Runtime.RANGED_RECIPES.bow.cost:
		if int(order.source.spent.get(resource, 0)) < int(Runtime.RANGED_RECIPES.bow.cost[resource]) * (order.receipt_ids.size() + 1): return Runtime.fail("NO_BUDGET", "本批須有真有限來源移交實績")
	var person: Dictionary = certificate.workshop.person
	if not actions._technology_military_person_ready(person, order) or bool(lab.terrain.site.get("paused", false)) \
		or float(lab.terrain.site.get("combat_left", 0.0)) > 0.0: return Runtime.fail("BUSY")
	var consents: Array = [] if order.work_consent.is_empty() else [order.work_consent]
	var purpose := _nation_order_purpose("N05", str(lab.terrain.site.id), nation_id, order_id)
	if int(operations.version) == 1 and order.work_consent.get("purpose") == "N05:" + order_id: purpose = "N05:" + order_id
	var team: Variant = actions._technology_military_team(person)
	if team == null and not consents.is_empty() or not actions._technology_consent_valid(int(order.operator_id), consents, purpose, {}, true, order): return Runtime.fail("NO_CONSENT")
	if team != null:
		var authority_team: Variant = team
		if team is CrowdOwner:
			authority_team = team._command_owner(int(person.unit))
			if authority_team is TerrainTestCharacter: authority_team = actions._technology_team(person)
		if not authority_team is TerrainArmy: return Runtime.fail("NO_CONSENT")
		var current_duty: Dictionary = authority_team.duty_resolve_readonly("team.work", team)
		if int(order.work_consent.get("decider_id", -1)) != int(current_duty.get("decider", -1)) \
			or int(order.work_consent.get("revision", -1)) != int(current_duty.get("revision", -1)): return Runtime.fail("NO_CONSENT")
	return Runtime.ok("", {"nation": nation, "operations": operations, "order": order, "certificate": certificate.certificate,
		"feature": feature, "person": person, "team": team, "groups": [{"team": team, "person_ids": [int(order.operator_id)]}],
		"person_ids": [int(order.operator_id)], "requester_id": int(order.authorizer_id), "operation_ref": {"nation_id": nation_id, "order_id": order_id},
		"controlled_worker": int(order.operator_id) == int(lab.controlled_person_id())})

# REPLACE military_order_admission. Actual progress/output still requires the
# true selected recipe, actual exact materials and physical original work slot.

func prepare_public_owner_begin(nation_id: String, order_id: String, binding_id: String, target_id: String) -> Dictionary:
	var checked := public_work_preflight(nation_id, order_id, binding_id)
	if not checked.ok: return checked
	var order: Dictionary = checked.order
	var old_target := str(order.payload.target_id) if order.tech_id == "N11" else "feature:" + str(order.payload.feature_id)
	if old_target != ("" if order.tech_id == "N11" else "feature:"):
		return Runtime.fail("NO_CHANGE" if old_target == target_id else "STALE_TARGET")
	if not target_id.begins_with("feature:") and not target_id.begins_with("vehicle:"): return Runtime.fail("INVALID")
	var key := target_id.get_slice(":", 1)
	if not key.is_valid_int() or str(int(key)) != key or not Technology.integer(int(key), 1): return Runtime.fail("INVALID")
	if order.tech_id == "N11":
		if binding_id != ("iron_armor" if order.payload.route == "armor" else "ballista_build"): return Runtime.fail("INVALID")
		if order.payload.route == "armor":
			if target_id != "feature:" + str(order.payload.host_id): return Runtime.fail("NO_TARGET")
		elif target_id != "vehicle:" + str(int(lab.terrain.site.next_vehicle)): return Runtime.fail("STALE_TARGET")
	else:
		if binding_id != ("house_build" if order.tech_id == "N06" else "road_build") \
			or target_id != "feature:" + str(int(lab.terrain.site.next_feature)): return Runtime.fail("STALE_TARGET")
		if order.tech_id in ["N02", "N10"] and order.receipts.size() != 1: return Runtime.fail("INCOMPLETE", "先完成本單原行政工作；不能付料後才拒絕首張收據")
	if int(order.revision) >= 2147483646: return Runtime.fail("CAPACITY")
	var candidate := _public_candidate(checked.nation)
	var next: Dictionary = candidate.public_orders[order_id]
	if order.tech_id == "N11": next.payload.target_id = target_id
	else: next.payload.feature_id = key
	next.status = "active"
	next.revision = int(order.revision) + 1
	if not valid_nation_operation_record(candidate, lab.terrain.site.item_definitions, {}) \
		or not _operations_candidate_claims_valid(nation_id, candidate): return Runtime.fail("INVALID")
	return Runtime.ok("", {"terrain": lab.terrain, "site": lab.terrain.site, "nation_id": nation_id, "nation": checked.nation,
		"prior_operations": checked.nation.technology_operations, "prior_order": order, "order_id": order_id, "operations": candidate})

# APPEND; internal no-yield Runtime tail after all true owner candidates pass.

func publish_public_owner_begin(prepared: Dictionary) -> void:
	assert(prepared.ok and is_same(prepared.terrain, lab.terrain) and is_same(prepared.site, lab.terrain.site))
	assert(is_same(lab.terrain.site.equipment_nations.get(prepared.nation_id), prepared.nation))
	assert(is_same(prepared.nation.technology_operations, prepared.prior_operations) \
		and is_same(prepared.prior_operations.public_orders.get(prepared.order_id), prepared.prior_order))
	_publish_nation_operations(prepared.nation, prepared.operations)

# APPEND; ALL callers validate their full original candidates BEFORE this tail.
# Preserve existing owner references, not a stale witness or a second registry.

func public_work_preflight(nation_id: String, order_id: String, binding_id: String = "") -> Dictionary:
	if binding_id.is_empty():
		var raw: Dictionary = lab.terrain.site.get("equipment_nations", {}).get(nation_id, {})
		var selected: Dictionary = raw.get("technology_operations", {}).get("public_orders", {}).get(order_id, {})
		binding_id = "house_build" if selected.get("tech_id") == "N06" else "road_build"
		if selected.get("tech_id") == "N11": binding_id = "iron_armor" if selected.get("payload", {}).get("route") == "armor" else "ballista_build"
	var checked := _public_context(nation_id, order_id, binding_id, true)
	if not checked.ok: return checked
	var order: Dictionary = checked.order
	if order.tech_id not in ["N02", "N06", "N10", "N11"]: return Runtime.fail("NO_TARGET")
	if order.tech_id == "N10" and not _mandate_effective(order, true): return Runtime.fail("EXPIRED_MANDATE")
	if order.payload.has("source") and not _public_source_paid(order): return Runtime.fail("NO_BUDGET")
	if order.tech_id == "N11":
		var host := _arsenal_workshop_context(order)
		if not host.ok: return host
	var identities: Array = order.payload.get("person_ids", order.payload.get("worker_ids", []))
	if order.tech_id == "N10": identities = [int(order.payload.local_person_id)]
	elif order.tech_id == "N11": identities = [int(order.payload.operator_id)]
	var groups: Array[Dictionary] = []
	var person_ids: Array[int] = []
	for raw_id: Variant in identities:
		var person: Dictionary = actions._person(int(raw_id))
		if person.is_empty(): return Runtime.fail("NO_WORKER")
		if person.owner is CrowdPersonOwner and not person.owner.crowd_site.work_fatigue_work_start_ready(int(raw_id)): return Runtime.fail("BUSY")
		var team: Variant = person.owner if person.owner is CrowdPersonOwner else actions._technology_team(person)
		var found := false
		for group: Dictionary in groups:
			if is_same(group.team, team): group.person_ids.append(int(raw_id)); found = true; break
		if not found: groups.append({"team": team, "person_ids": [int(raw_id)]})
		person_ids.append(int(raw_id))
	checked.merge({"team": groups[0].team if groups.size() == 1 else null, "groups": groups, "person_ids": person_ids,
		"requester_id": int(order.payload.local_person_id) if order.tech_id == "N10" else int(order.authorizer_id),
		"operation_ref": {"nation_id": nation_id, "order_id": order_id}, "controlled_worker": person_ids.has(int(lab.controlled_person_id()))})
	return checked

# APPEND; concrete original S11/S13 host/worker gate for arsenal dispatch.

static func _procurement_trial_scope_valid(nation: Dictionary, nation_id: String, site_id: String) -> bool:
	for spec_id: String in nation.get("technology_operations", {}).get("specs", {}):
		var spec: Dictionary = nation.technology_operations.specs[spec_id]
		if not spec.has("tech_trial"): continue
		var token: Dictionary = spec.tech_trial
		if not _valid_procurement_trial(token) or token.scope_id != nation_id or token.person.site_id != site_id or int(token.epoch) != int(nation.get("technology", {}).get("epoch", -1)) \
			or token.target_id != "nation-procurement:" + JSON.stringify([site_id, nation_id, spec_id]) \
			or int(token.person.person_id) != int(spec.authorizer_id): return false
		var found := false
		for project: Dictionary in nation.get("technology", {}).get("projects", []):
			if int(project.id) != int(token.project_id): continue
			found = project.tech_id == "N01" and project.purpose == token.purpose and project.executor == token.person \
				and int(project.rules_version) == 2 and int(token.attempt) < int(project.next_attempt)
		if not found: return false
	return true

static func _valid_procurement_trial(raw: Variant) -> bool:
	return Technology.keys(raw, ["scope", "scope_id", "project_id", "epoch", "purpose", "tech_id", "phase_id", "attempt", "person", "binding", "target_id", "materials"]) \
		and raw.scope == "nation" and raw.scope_id is String and _operation_key(raw.scope_id) \
		and Technology.integer(raw.project_id, 1) and Technology.integer(raw.epoch, 1) and Technology.integer(raw.attempt, 1) \
		and raw.purpose is String and not raw.purpose.is_empty() and str(raw.purpose).length() <= 256 \
		and raw.tech_id == "N01" and raw.phase_id == "accept_two_named_procurement_deliveries" and raw.binding == "procurement" \
		and Technology.valid_ref(raw.person) and raw.target_id is String and str(raw.target_id).begins_with("nation-procurement:") \
		and Technology.material_equal(raw.materials, {"wood": 2, "grain": 2})

## F1a author/scenario binding candidate; no political appointment or guessed mapping.
static func prepare_faction_nation(state: Dictionary, nation_id: String, faction_id: int, original_nation: Dictionary = {}) -> Dictionary:
	if not _valid_key(nation_id) or nation_id.begins_with("trial_team_") or not RegionFactionQuery.whole(faction_id, 0, RegionFactionQuery.MAX_ID): return Runtime.fail("INVALID_FACTION_NATION")
	var candidate: Variant = state.duplicate(true)
	if not candidate.has("equipment_nations"): candidate.equipment_nations = {}
	if not original_nation.is_empty():
		if candidate.equipment_nations.has(nation_id): return Runtime.fail("CONFLICT")
		candidate.equipment_nations[nation_id] = original_nation.duplicate(true)
	var nation: Dictionary = candidate.equipment_nations.get(nation_id, {})
	if nation.is_empty() or nation.has("faction_id") or nation.has("faction_version"): return Runtime.fail("NO_TARGET")
	nation.faction_version = 1
	nation.faction_id = faction_id
	var identity: Variant = RegionTravel.prepare_identity(candidate)
	if not identity.ok: return identity
	candidate = identity.state
	var people: Variant = RegionTravel._body_records(candidate)
	if not valid_nations(candidate.equipment_nations, candidate.get("item_definitions", {}), people, candidate): return Runtime.fail("CORRUPT_SAVE", "original nation owner validation")
	return Runtime.ok("", {"state": candidate})

static func _faction_person(state: Dictionary, person_id: int) -> int:
	for actor: Dictionary in state.get("actors", {}).values():
		if int(actor.get("person_id", -1)) == person_id: return int(actor.get("faction_id", -1))
	for team: Dictionary in state.get("armies", []):
		for row: Dictionary in team.get("units", []):
			if int(row.get("person_id", -1)) == person_id: return int(team.get("faction_id", -1))
	return int(state.get("organization_refs", {}).get("remote_people", {}).get(str(person_id), {}).get("faction_id", -1))
