extends Control
## 選現成人物 v1 (Nekki 2026-11-27 「清單加地圖」): the map beside the list. Draws the scenario's area of Taiwan, one square
## per Site coloured by the overview class (the menu background palette), with a mark for every settlement (circle),
## lair (triangle) and the scenario's start (diamond); the picked Site is outlined. A click on a Site with people emits
## site_clicked. Read-only decoration over the package data ScenarioPeople.people() returned.

signal site_clicked(site: Vector2i)

const SUMMARY := "res://assets/region_lab/earth_tw_tm2_121_v1_r4/summary.u8"
const SUMMARY_ORIGIN := Vector2i(200, 11800) # manifest.json summary.site_origin
const SUMMARY_SIZE := Vector2i(1900, 2400) # summary.size; rows run north to south
const MARGIN := 1 # Sites shown around the scenario's people
const CLASS_COLORS := {1: Color(0.10, 0.27, 0.40), 2: Color(0.39, 0.57, 0.34), 3: Color(0.27, 0.63, 0.72), 4: Color(0.73, 0.73, 0.48)}
const OTHER_COLOR := Color(0.28, 0.23, 0.32)

var sites: Dictionary = {} # "x:y" -> {kind, faction_id, faction}
var counts: Dictionary = {} # "x:y" -> people to pick there
var picked := Vector2i(-1, -1)
var _low := Vector2i.ZERO
var _high := Vector2i.ZERO
var _classes: Dictionary = {} # "x:y" -> overview class

func show_sites(site_rows: Dictionary, people: Array) -> void:
	sites = site_rows.duplicate(true)
	counts = {}
	for row: Dictionary in people:
		var key := "%d:%d" % [row.site.x, row.site.y]
		counts[key] = int(counts.get(key, 0)) + 1
	var first := true
	for key: String in sites:
		var parts := key.split(":")
		var at := Vector2i(int(parts[0]), int(parts[1]))
		if first:
			_low = at
			_high = at
			first = false
		_low = Vector2i(mini(_low.x, at.x), mini(_low.y, at.y))
		_high = Vector2i(maxi(_high.x, at.x), maxi(_high.y, at.y))
	_low -= Vector2i(MARGIN, MARGIN)
	_high += Vector2i(MARGIN, MARGIN)
	_read_classes()
	queue_redraw()

func pick(site: Vector2i) -> void:
	picked = site
	queue_redraw()

func _read_classes() -> void:
	_classes = {}
	var file := FileAccess.open(SUMMARY, FileAccess.READ)
	if file == null or file.get_length() != SUMMARY_SIZE.x * SUMMARY_SIZE.y: return
	for y: int in range(_low.y, _high.y + 1):
		for x: int in range(_low.x, _high.x + 1):
			var px := x - SUMMARY_ORIGIN.x
			var py := SUMMARY_SIZE.y - 1 - (y - SUMMARY_ORIGIN.y)
			if px < 0 or py < 0 or px >= SUMMARY_SIZE.x or py >= SUMMARY_SIZE.y: continue
			file.seek(py * SUMMARY_SIZE.x + px)
			_classes["%d:%d" % [x, y]] = file.get_8()
	file.close()

## The square of one Site and its side, fitted into this control (north up).
func _cell() -> float:
	var span := _high - _low + Vector2i.ONE
	if span.x <= 0 or span.y <= 0: return 0.0
	return minf(size.x / float(span.x), size.y / float(span.y))

func _rect_of(site: Vector2i) -> Rect2:
	var side := _cell()
	var span := _high - _low + Vector2i.ONE
	var offset := (size - Vector2(span) * side) * 0.5
	return Rect2(offset + Vector2(site.x - _low.x, _high.y - site.y) * side, Vector2(side, side))

func site_at(point: Vector2) -> Vector2i:
	var side := _cell()
	if side <= 0.0: return Vector2i(-1, -1)
	var span := _high - _low + Vector2i.ONE
	var offset := (size - Vector2(span) * side) * 0.5
	var local := (point - offset) / side
	if local.x < 0 or local.y < 0 or local.x >= span.x or local.y >= span.y: return Vector2i(-1, -1)
	return Vector2i(_low.x + int(local.x), _high.y - int(local.y))

func _draw() -> void:
	if sites.is_empty(): return
	for y: int in range(_low.y, _high.y + 1):
		for x: int in range(_low.x, _high.x + 1):
			var key := "%d:%d" % [x, y]
			draw_rect(_rect_of(Vector2i(x, y)).grow(-0.5), CLASS_COLORS.get(int(_classes.get(key, 0)), OTHER_COLOR))
	for key: String in sites:
		var parts := key.split(":")
		var at := Vector2i(int(parts[0]), int(parts[1]))
		var rect := _rect_of(at)
		var centre := rect.get_center()
		var radius := rect.size.x * 0.28
		var kind := str(sites[key].get("kind", ""))
		var shade := Color(0.96, 0.92, 0.78) if counts.has(key) else Color(0.6, 0.6, 0.6)
		if kind == "settlement": draw_circle(centre, radius, shade)
		elif kind == "lair": draw_colored_polygon(PackedVector2Array([centre + Vector2(0, -radius), centre + Vector2(radius, radius * 0.8), centre + Vector2(-radius, radius * 0.8)]), Color(0.85, 0.32, 0.27) if counts.has(key) else shade)
		elif kind == "start": draw_colored_polygon(PackedVector2Array([centre + Vector2(0, -radius), centre + Vector2(radius, 0), centre + Vector2(0, radius), centre + Vector2(-radius, 0)]), Color(0.55, 0.75, 0.95))
	if picked.x >= 0: draw_rect(_rect_of(picked).grow(-1.0), Color(1.0, 0.85, 0.2), false, maxf(2.0, _cell() * 0.08))

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var site := site_at(event.position)
		if site.x >= 0 and counts.has("%d:%d" % [site.x, site.y]):
			pick(site)
			site_clicked.emit(site)
			accept_event()
