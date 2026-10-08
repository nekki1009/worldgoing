class_name SiteTechnologyPolicy
extends RefCounted
## Pure projections only. RegionEntry / RegionSaveSlot retain the world policy;
## original work owners check actual people, trials and costs before committing.

const VERSION := 1
const RULES_VERSION := 1
const CATEGORIES := ["F04", "F06", "F11", "F12"]

static func _fail(code: String, message: String) -> Dictionary:
	return {"ok": false, "code": code, "message": message}

static func _categories(raw: Variant) -> Dictionary:
	if not raw is Array or raw.size() > CATEGORIES.size():
		return _fail("INVALID_TECH_POLICY", "門檻類別須為四類內的明示清單")
	var result: Array[String] = []
	for value: Variant in raw:
		if not value is String or value not in CATEGORIES or result.has(value):
			return _fail("INVALID_TECH_POLICY", "門檻類別非法或重複")
		result.append(value)
	result.sort()
	return {"ok": true, "categories": result}

static func _one(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == 1.0

static func validate(raw: Variant) -> Dictionary:
	if not raw is Dictionary or raw.size() != 3 or not raw.has("version") or not raw.has("rules_version") or not raw.has("categories"):
		return _fail("INVALID_TECH_POLICY", "新格式世界的固定門檻政策缺欄位或欄位非法")
	if not _one(raw.version) or not _one(raw.rules_version):
		return _fail("TECH_POLICY_VERSION", "世界门檻政策或規則版本不支援")
	var checked := _categories(raw.categories)
	if not checked.ok: return checked
	return {"ok": true, "policy": {"version": VERSION, "rules_version": RULES_VERSION, "categories": checked.categories}}

static func new_policy(admitted_categories: Variant = []) -> Dictionary:
	# Caller supplies only classes whose actual research / acquisition / save /
	# starting-artisan tests passed. This helper never admits a release itself.
	var checked := _categories(admitted_categories)
	if not checked.ok: return checked
	return {"ok": true, "policy": {"version": VERSION, "rules_version": RULES_VERSION, "categories": checked.categories}}

static func candidate(record: Variant, legacy_format: bool = false) -> Dictionary:
	# The owner validates its outer format. Field presence is checked here so an
	# existing null / malformed policy cannot be mistaken for a legacy absence.
	if not record is Dictionary: return _fail("INVALID_TECH_POLICY", "原世界政策容器非法")
	if not record.has("technology_policy"):
		if not legacy_format: return _fail("MISSING_TECH_POLICY", "新格式世界缺少固定門檻政策")
		var empty := new_policy()
		empty["legacy"] = true
		return empty
	var checked := validate(record.technology_policy)
	if checked.ok: checked["legacy"] = false
	return checked

static func same_candidate(left: Variant, right: Variant, left_legacy: bool = false, right_legacy: bool = false) -> Dictionary:
	var a := candidate(left, left_legacy)
	if not a.ok: return a
	var b := candidate(right, right_legacy)
	if not b.ok: return b
	if a.policy != b.policy: return _fail("TECH_POLICY_CONFLICT", "原世界、存檔槽與 Site 的固定門檻政策不同")
	return {"ok": true, "policy": a.policy.duplicate(true)}

static func recipe_category(feature_kind: String, recipe_id: String) -> String:
	if feature_kind == "smelter" and recipe_id == "steel" or feature_kind == "smithy" and recipe_id == "steel_tools": return "F04"
	if feature_kind == "weaver" and recipe_id == "wool_cloth": return "F06"
	return ""

static func siege_category(kind: String, action: String = "construct") -> String:
	# Original vehicle owner must first verify the real build / repair record;
	# accepting a caller-supplied "repair" name is not a reconstruction bypass.
	if action != "construct": return ""
	if kind == "siege_tower": return "F11"
	if kind == "counterweight_trebuchet": return "F12"
	return ""

static func gate(raw: Variant, category: String) -> Dictionary:
	var checked := validate(raw)
	if not checked.ok: return checked
	if not category.is_empty() and category not in CATEGORIES: return _fail("INVALID_TECH_CATEGORY", "未知門檻類別")
	return {"ok": true, "policy": checked.policy,
		"category": category, "gated": not category.is_empty() and checked.policy.categories.has(category)}
