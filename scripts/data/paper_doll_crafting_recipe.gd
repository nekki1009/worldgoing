extends Resource

## A small, data-only recipe used by the paper-doll Asset Lab.
##
## The lab currently has no inventory/equipment gameplay owner, so this
## Resource deliberately does not mutate GameSession or consume anything.  It
## records the canonical world-resource costs and exposes a pure `can_craft`
## query for the future economy domain to reuse.

const RESOURCE_ORDER: Array[String] = [
	"forest",
	"grass",
	"iron_ore",
	"stone_ore",
	"silver_ore",
	"gold_ore",
	"fruit_tree",
]

@export var recipe_id: StringName = &""
@export var output_visual_id: StringName = &""
@export var display_name: String = ""
@export var required_resources: Dictionary = {}

static func make_recipe(
		p_recipe_id: StringName,
		p_output_visual_id: StringName,
		p_display_name: String,
		p_required_resources: Dictionary
	) -> Resource:
	var result := new()
	result.recipe_id = p_recipe_id
	result.output_visual_id = p_output_visual_id
	result.display_name = p_display_name
	result.required_resources = p_required_resources.duplicate(true)
	return result

func validation_issues(output_visual: PaperDollLayerVisual) -> PackedStringArray:
	var issues: PackedStringArray = []
	if recipe_id.is_empty():
		issues.append("crafting recipe has an empty id")
	if output_visual_id.is_empty():
		issues.append("%s: crafting recipe has no output visual" % recipe_id)
	if output_visual == null:
		issues.append("%s: output visual is missing" % recipe_id)
	else:
		if output_visual.render_layer not in [
			PaperDollLayerVisual.RenderLayer.ARMOR,
			PaperDollLayerVisual.RenderLayer.HELMET,
		]:
			issues.append("%s: output must be armor or helmet" % recipe_id)
		if output_visual.resolve(PaperDollLayerVisual.Gender.MALE, false) == null \
				or output_visual.resolve(PaperDollLayerVisual.Gender.MALE, true) == null \
				or output_visual.resolve(PaperDollLayerVisual.Gender.FEMALE, false) == null \
				or output_visual.resolve(PaperDollLayerVisual.Gender.FEMALE, true) == null:
			issues.append("%s: output has no complete male/female on-foot/mounted visual" % recipe_id)
	for raw_key: Variant in required_resources.keys():
		var key := str(raw_key)
		var amount := int(required_resources[raw_key])
		if key not in RESOURCE_ORDER:
			issues.append("%s: non-canonical resource '%s'" % [recipe_id, key])
		if amount <= 0:
			issues.append("%s: resource '%s' must have a positive amount" % [recipe_id, key])
	if required_resources.is_empty():
		issues.append("%s: crafting recipe has no resource requirements" % recipe_id)
	return issues

## Pure affordability check.  `available_resources` may use String or
## StringName keys; missing entries are treated as zero.
func can_craft(available_resources: Dictionary) -> bool:
	for raw_key: Variant in required_resources.keys():
		var key := str(raw_key)
		var available: int = int(available_resources.get(raw_key, available_resources.get(key, 0)))
		if available < int(required_resources[raw_key]):
			return false
	return true

func requirements_text() -> String:
	var keys: Array[String] = []
	for raw_key: Variant in required_resources.keys():
		keys.append(str(raw_key))
	keys.sort_custom(_resource_less)
	var parts: PackedStringArray = []
	for key: String in keys:
		parts.append("%s x%d" % [_resource_display_name(key), int(required_resources[key])])
	return ", ".join(parts)

static func _resource_less(left: String, right: String) -> bool:
	var left_index: int = RESOURCE_ORDER.find(left)
	var right_index: int = RESOURCE_ORDER.find(right)
	if left_index < 0:
		left_index = RESOURCE_ORDER.size()
	if right_index < 0:
		right_index = RESOURCE_ORDER.size()
	return left_index < right_index if left_index != right_index else left < right

static func _resource_display_name(resource_id: String) -> String:
	match resource_id:
		"forest":
			return "forest"
		"grass":
			return "grass"
		"iron_ore":
			return "iron ore"
		"stone_ore":
			return "stone ore"
		"silver_ore":
			return "silver ore"
		"gold_ore":
			return "gold ore"
		"fruit_tree":
			return "fruit tree"
		_:
			return resource_id.replace("_", " ")
