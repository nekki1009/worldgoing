extends RefCounted
## 開始遊戲效能 P1-5 (project library perf/start-game-perf-plan.md §4): the loading screen while a world opens.
## Opening a world runs on the main thread for tens of seconds. At each start-chain stage (every PerfTrace.mark, which
## forwards here whether or not --perf-trace is on) this redraws a plain progress screen and lets the window manager run,
## so the window keeps showing where the opening is instead of freezing or turning "not responding".
## - It draws through its own canvas item with RenderingServer calls, never a Control: a Control's redraw waits for the
##   next frame, and RenderingServer.force_draw only presents what is already recorded. Node processing never runs.
## - It changes nothing in the world and reads nothing from it. Real renderer only; headless it does nothing.

## Stage -> user text, in start-chain order; the bar shows the share of the listed stages already passed.
const STAGES := [
	["open_begin", "讀取地理資料"], ["manifest_done", "讀取地理資料"], ["open_map", "打開起點"],
	["site_opened", "打開起點"], ["init_site_opened", "誕生人物"], ["init_population", "安置人物"],
	["slot_attach_begin", "寫入存檔"], ["prepared", "確認起點"], ["committed", "鋪設地形"],
	["bind_displayed", "還原隊伍"], ["crowd_validate_begin", "檢查群眾"], ["crowd_contacts_ready", "準備人物外觀"],
	["bind_armies", "建立群眾"], ["bind_controller", "建立群眾"], ["crowd_body", "準備人物"],
	["bind_owners_begin", "還原歸屬"], ["bound", "完成世界"], ["finished", "完成世界"], ["open_done", "即將進入"],
	["settled", "即將進入"],
]
const MIN_REDRAW_MSEC := 120
const BACKGROUND := Color(0.05, 0.08, 0.09)
const BAR_BACK := Color(0.16, 0.22, 0.24)
const BAR := Color("8fb59a")
const TEXT := Color("e8e0cc")
const DIM := Color("9fb0a8")

static var _layer: CanvasLayer
static var _item := RID()
static var _title := ""
static var _detail := ""
static var _fraction := 0.0
static var _bodies := 0
static var _last_draw_msec := -1000000
static var draws := 0 # Screens presented since the last begin (diagnostics and the acceptance test).
static var last_detail := "" # The stage text last shown.

static func available() -> bool:
	return DisplayServer.get_name() != "headless"

static func active() -> bool:
	return is_instance_valid(_layer) and _item.is_valid()

## Shows the screen over `host` (the Lab). Frees with the host; finish() ends it at once.
static func begin(host: Node, title: String) -> void:
	finish()
	if not available() or not is_instance_valid(host) or not host.is_inside_tree(): return
	_layer = CanvasLayer.new()
	_layer.name = "StartProgress"
	_layer.layer = 127
	host.add_child(_layer)
	_item = RenderingServer.canvas_item_create()
	RenderingServer.canvas_item_set_parent(_item, _layer.get_canvas())
	_title = title
	_detail = ""
	_fraction = 0.0
	_bodies = 0
	_last_draw_msec = -1000000
	draws = 0
	last_detail = ""
	_present(true)

static func finish() -> void:
	if _item.is_valid(): RenderingServer.free_rid(_item)
	_item = RID()
	if is_instance_valid(_layer): _layer.queue_free()
	_layer = null

## One start-chain stage passed (called from PerfTrace.mark). Unknown stages only keep the window alive.
static func stage(name: String) -> void:
	if not active(): return
	if name == "crowd_body":
		_bodies += 1
	for index: int in range(STAGES.size()):
		if STAGES[index][0] != name: continue
		_detail = STAGES[index][1] if name != "crowd_body" else "%s（%d）" % [STAGES[index][1], _bodies]
		_fraction = maxf(_fraction, float(index + 1) / float(STAGES.size() + 1))
		break
	_present(false)

static func _present(force: bool) -> void:
	DisplayServer.force_process_and_drop_events()
	var now := Time.get_ticks_msec()
	if not force and now - _last_draw_msec < MIN_REDRAW_MSEC: return
	_last_draw_msec = now
	var size := Vector2(DisplayServer.window_get_size())
	var viewport := _layer.get_viewport()
	if viewport != null: size = viewport.get_visible_rect().size
	RenderingServer.canvas_item_clear(_item)
	RenderingServer.canvas_item_add_rect(_item, Rect2(Vector2.ZERO, size), BACKGROUND)
	var font: Font = ThemeDB.fallback_font
	var scale := clampf(size.y / 1080.0, 0.6, 2.0)
	var title_size := roundi(34 * scale)
	var detail_size := roundi(20 * scale)
	var center_y := size.y * 0.5
	font.draw_string(_item, Vector2(0.0, center_y - 40.0 * scale), _title, HORIZONTAL_ALIGNMENT_CENTER, size.x, title_size, TEXT)
	var bar := Rect2(size.x * 0.3, center_y, size.x * 0.4, 10.0 * scale)
	RenderingServer.canvas_item_add_rect(_item, bar, BAR_BACK)
	RenderingServer.canvas_item_add_rect(_item, Rect2(bar.position, Vector2(bar.size.x * _fraction, bar.size.y)), BAR)
	if not _detail.is_empty():
		font.draw_string(_item, Vector2(0.0, center_y + 50.0 * scale), _detail, HORIZONTAL_ALIGNMENT_CENTER, size.x, detail_size, DIM)
	RenderingServer.force_draw(true, 0.0)
	draws += 1
	last_detail = _detail
