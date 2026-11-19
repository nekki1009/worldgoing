extends RefCounted
## Ten-axis personality packet shared by Actor state, Army rows, Crowd cold
## rows and SiteStore validation (NPC AI plan 4.1). A missing packet means
## every axis is neutral 50 and is never written back. Only the three
## military axes drive behaviour; the rest are stored until a system reads them.

const VERSION := 1
const NEUTRAL := 50
const AXES: Array[String] = ["risk", "casualty", "achievement", "ambition", "mercy", "thrift",
	"lawful", "diligence", "kinship", "innovation"]
## Value 100 reads as the first label, 0 as the second.
const LABELS := {
	"risk": ["勇猛", "謹慎"], "casualty": ["愛兵", "不惜損失"], "achievement": ["好功", "淡泊"],
	"ambition": ["野心", "安分"], "mercy": ["仁厚", "嚴酷"], "thrift": ["節儉", "慷慨"],
	"lawful": ["守法", "變通"], "diligence": ["勤勉", "安逸"], "kinship": ["重家族", "重國家"],
	"innovation": ["求新", "守舊"]}
const GROUPS := [["軍事", ["risk", "casualty", "achievement"]], ["為人", ["ambition", "mercy", "thrift"]],
	["處事", ["lawful", "diligence", "kinship", "innovation"]]]

static func neutral() -> Dictionary:
	var packet := {"version": VERSION}
	for axis: String in AXES: packet[axis] = NEUTRAL
	return packet

## Strict: exactly version + ten integer axes in 0..100. Never coerces a bad packet.
static func valid(packet: Variant) -> bool:
	if not packet is Dictionary or packet.size() != AXES.size() + 1: return false
	if not _integer(packet.get("version"), VERSION, VERSION): return false
	for axis: String in AXES:
		if not _integer(packet.get(axis), 0, 100): return false
	return true

static func normalized(packet: Dictionary) -> Dictionary:
	var result := {"version": VERSION}
	for axis: String in AXES: result[axis] = int(packet[axis])
	return result

static func is_neutral(packet: Dictionary) -> bool:
	for axis: String in AXES:
		if int(packet.get(axis, NEUTRAL)) != NEUTRAL: return false
	return true

## Sparse save form: empty when absent or entirely neutral.
static func saved(packet: Dictionary) -> Dictionary:
	return {} if packet.is_empty() or is_neutral(packet) else normalized(packet)

## Read side for decision makers: a missing packet is neutral.
static func read(packet: Variant) -> Dictionary:
	return normalized(packet) if valid(packet) else neutral()

static func _integer(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value)) \
		and float(value) >= low and float(value) <= high
