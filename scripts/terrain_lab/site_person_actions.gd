class_name SitePersonActions
extends RefCounted
## Commands reference original people and sparse holders; no surrogate bodies.
## advance() is before contact/life settlement; only settle_after_contacts commits.

const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Fatigue = preload("res://scripts/terrain_lab/person_fatigue.gd")
const LOOSE_BASE_SECONDS := 2.0
const LOOSE_ITEM_SECONDS := 0.2
const REMOVE_SECONDS := 5.0
const BIND_SECONDS := 4.0
const GUARD_CAPACITY := 4
const GUARD_STEPS := 4
const RANSOM_RATIONS := 100
const RANSOM_SECONDS := 10.0
const ESCAPE_SECONDS := 30.0
const FOODS := ["fish", "meat", "wild_food", "grain"]

var lab: Variant
var equipment_removal_guard: Callable # (person_id, item_ids) -> typed result; pure.
var equipment_changed: Callable # (person_id); synchronous original visual/hit update.
var opened_food_pool: Callable # (person_id) -> the original private food pool, or empty.
var opened_food_commit: Callable # (person_id, amount, original pool); infallible after checks.
var captivity_change_guard: Callable # (target_id, captor_id, capturing) -> pure result.
var captivity_supply_commit: Callable # Same arguments; fully prevalidated, no failure/yield.
var captivity_changed: Callable # Same arguments; prepared commit must not fail/yield.
var ransom_exchange_query: Callable # (payer, captive, representative) -> original inventories/owners/revisions.
var ransom_exchange_committed: Callable # (query); only synchronous owner revision notification.
var equipment_orders: Variant # Thin rules provider; this remains the only job clock.
var _results: Array[Dictionary] = []
var _jobs: Dictionary = {} # Active commands are transient; save_guard refuses them.

func init(owner: Variant) -> void:
	lab = owner
	_jobs.clear()
	_results.clear()
	# Explicit new/legacy-empty initialization; keep original captivity records.
	if not lab.terrain.site.has("captivity"):
		lab.terrain.site["captivity"] = {}

func is_busy(identity: int) -> bool:
	return _jobs.has(str(identity))

func save_guard() -> Dictionary:
	return Runtime.ok() if _jobs.is_empty() else Runtime.fail("BUSY", "人物作業未完成；完成或取消後再保存")

func job_for(identity: int) -> Dictionary:
	return _jobs.get(str(identity), {}).duplicate(true)

func is_working(identity: int) -> bool:
	var job: Dictionary = _jobs.get(str(identity), {})
	return not job.is_empty() and str(job.paused).is_empty()

func is_guarding(identity: int) -> bool:
	for entry: Dictionary in lab.terrain.site.captivity.values():
		if int(entry.guard_id) == identity:
			return true
	return false

func has_effective_guard(identity: int) -> bool:
	var person := _person(identity)
	var entry: Dictionary = lab.terrain.site.captivity.get(str(identity), {})
	if person.is_empty() or entry.is_empty():
		return false
	var guard := _person(int(entry.guard_id), false)
	if guard.is_empty() or (not bool(guard.player) and bool(_body_get(guard, "work_resting"))):
		return false
	var capable: bool = guard.owner.combat_can_act(int(guard.unit)) if int(guard.unit) >= 0 else guard.owner.can_act()
	return capable and int(guard.faction) == int(entry.captor_faction) and _within_guard_range(guard.cell, person.cell)

func cancel(identity: int) -> Dictionary:
	if not is_busy(identity):
		return Runtime.fail("NO_TARGET", "沒有未完成的人物作業")
	_jobs.erase(str(identity))
	return Runtime.ok("已取消；未完成批次沒有轉移物品")

func lootable(executor_id: int, source_kind: String, source_id: String) -> Dictionary:
	var executor := _person(executor_id)
	var source := _source(source_kind, source_id)
	var check := _loot_context(executor, source)
	if not check.ok:
		return check
	# Copies for a read-only panel, never adopted as inventory owners.
	return Runtime.ok("目前實際持有物", {"resources": source.cargo.duplicate(),
		"item_ids": source.holder.item_ids.duplicate(), "equipped": source.holder.equipped.duplicate(),
		"version": int(source.holder.version)})

func begin_loot(executor_id: int, source_kind: String, source_id: String, resources: Dictionary, item_ids: Array, open_amount: float = 0.0) -> Dictionary:
	if is_busy(executor_id):
		return Runtime.fail("BUSY", "先完成或取消原人物作業")
	var executor := _person(executor_id)
	var source := _source(source_kind, source_id)
	var check := _loot_context(executor, source)
	if not check.ok:
		return check
	check = _selection(executor, source, resources, item_ids, open_amount)
	if not check.ok:
		return check
	var worn := false
	for identity: String in item_ids:
		worn = worn or source.holder.equipped.values().has(identity)
	if worn and (item_ids.size() != 1 or not resources.is_empty() or open_amount > 0.0):
		return Runtime.fail("INVALID", "穿戴物品每批只能卸下一件，不混合散物")
	check = _removal_guard(source, item_ids)
	if not check.ok:
		return check
	var job := _new_job(executor, "loot", int(source.get("person_id", 0)))
	job.merge({"source_kind": source_kind, "source_id": source_id,
		"source_version": int(source.holder.version), "destination_version": int(executor.holder.version),
		"source_holder": source.holder, "source_cargo": source.cargo,
		"destination_holder": executor.holder, "destination_cargo": executor.cargo,
		"open_amount": open_amount, "source_open": float(source.holder.get("open_rations", 0.0)),
		"destination_pool": opened_food_pool.call(executor_id) if open_amount > 0.0 else {},
		"resources": resources.duplicate(), "item_ids": item_ids.duplicate(),
		"source_cell": lab.terrain.index(source.cell), "target_hit": int(source.get("hit", -1)),
		"duration": REMOVE_SECONDS if worn else LOOSE_BASE_SECONDS + LOOSE_ITEM_SECONDS * (Runtime.inventory_size(resources) + item_ids.size() + open_amount)})
	_jobs[str(executor_id)] = job
	return Runtime.ok("開始搜刮；完成前物品仍在來源", {"seconds": job.duration})

func begin_capture(executor_id: int, target_id: int, guard_id: int) -> Dictionary:
	return _begin_binding(executor_id, target_id, guard_id, true)

func begin_unbind(executor_id: int, target_id: int) -> Dictionary:
	return _begin_binding(executor_id, target_id, -1, false)

func begin_equipment(identity: int, request: Dictionary) -> Dictionary:
	if is_busy(identity):
		return Runtime.fail("BUSY")
	if equipment_orders == null:
		return Runtime.fail("UNSUPPORTED", "尚未接入實際領裝規則")
	var prepared: Dictionary = equipment_orders.prepare(identity, request)
	if not prepared.ok:
		return prepared
	var job := _new_job(_person(identity), "equipment", identity)
	job.merge({"duration": 5.0, "order": prepared.order})
	_jobs[str(identity)] = job
	return Runtime.ok("開始換裝；完成前保留原實裝", {"seconds": 5.0})

func begin_ranged_craft(identity: int, recipe: String) -> Dictionary:
	if is_busy(identity) or bool(lab.terrain.site.get("paused", false)):
		return Runtime.fail("BUSY", "先完成或取消原人物作業，暫停時不能開始")
	var executor := _person(identity)
	var check := _ranged_craft_context(executor)
	if not check.ok:
		return check
	check = Runtime.ranged_craft(lab.terrain, recipe, identity, true)
	if not check.ok:
		return check
	var job := _new_job(executor, "ranged_craft", identity)
	job.merge({"recipe": recipe, "duration": float(Runtime.RANGED_RECIPES[recipe].duration),
		"terrain": lab.terrain, "site_state": lab.terrain.site,
		"executor_holder": executor.holder, "executor_cargo": executor.cargo, "executor_version": int(executor.holder.version),
		"depot_holder": lab.terrain.site.depot_items, "depot_stock": lab.terrain.site.inventory})
	_jobs[str(identity)] = job
	return Runtime.ok("開始營地手作；完成才扣原材料並入庫", {"seconds": job.duration})

func begin_escape(identity: int) -> Dictionary:
	if is_busy(identity):
		return Runtime.fail("BUSY")
	var person := _person(identity)
	var check := _escape_context(person)
	if not check.ok:
		return check
	var job := _new_job(person, "escape", identity)
	job.merge({"duration": ESCAPE_SECONDS, "captivity": lab.terrain.site.captivity[str(identity)].duplicate(),
		"source_version": int(person.holder.version)})
	_jobs[str(identity)] = job
	return Runtime.ok("開始尋找逃脫機會；連續三十秒無有效看守且無威脅才解開")

func begin_ransom(payer_id: int, target_id: int, representative_id: int) -> Dictionary:
	if is_busy(payer_id):
		return Runtime.fail("BUSY")
	var payer := _person(payer_id)
	var target := _person(target_id)
	var representative := _person(representative_id)
	var query := _ransom_context(payer, target, representative)
	if not query.ok:
		return query
	var items := {}
	var left := RANSOM_RATIONS
	for food: String in FOODS:
		var quantity := mini(left, int(query.source.get(food, 0)))
		if quantity > 0:
			items[food] = quantity
		left -= quantity
	if left > 0:
		return Runtime.fail("MATERIALS", "原付款庫存不足一百日份")
	var job := _new_job(payer, "ransom", target_id)
	job.merge({"duration": RANSOM_SECONDS, "representative_id": representative_id,
		"representative_cell": lab.terrain.index(representative.cell), "representative_hit": int(representative.hit),
		"source_owner": str(query.source_owner), "destination_owner": str(query.destination_owner),
		"source_revision": int(query.source_revision), "destination_revision": int(query.destination_revision),
		"source_stock": query.source.duplicate(), "resources": items,
		"captivity": lab.terrain.site.captivity[str(target_id)].duplicate(), "source_version": int(target.holder.version)})
	_jobs[str(payer_id)] = job
	return Runtime.ok("開始交付一百實物日份贖回；完成前不扣糧", {"seconds": RANSOM_SECONDS})

func _begin_binding(executor_id: int, target_id: int, guard_id: int, capturing: bool) -> Dictionary:
	if is_busy(executor_id):
		return Runtime.fail("BUSY", "先完成或取消原人物作業")
	var executor := _person(executor_id)
	var target := _person(target_id)
	var check := _binding_context(executor, target, guard_id, capturing)
	if not check.ok:
		return check
	var job := _new_job(executor, "capture" if capturing else "unbind", target_id)
	job.merge({"guard_id": guard_id, "duration": BIND_SECONDS,
		"source_version": int(target.holder.version), "target_hit": int(target.hit),
		"source_cell": lab.terrain.index(target.cell)})
	_jobs[str(executor_id)] = job
	return Runtime.ok("開始拘束" if capturing else "開始解綁", {"seconds": BIND_SECONDS})

func _new_job(executor: Dictionary, kind: String, target_id: int) -> Dictionary:
	return {"version": 1, "kind": kind, "executor_id": int(executor.person_id), "target_id": target_id,
		"executor_cell": lab.terrain.index(executor.cell), "executor_hit": int(executor.hit),
		"elapsed": 0.0, "paused": ""}

func advance(seconds: float) -> Dictionary:
	var handled := {}
	if not is_finite(seconds) or seconds <= 0.0 or bool(lab.terrain.site.get("paused", false)):
		return {"handled_seconds": handled}
	var threats := {}
	for key: String in _jobs.keys():
		var job: Dictionary = _jobs[key]
		var check := _job_context(job)
		if not check.ok:
			_finish(key, check)
			continue
		var executor := _person(int(job.executor_id))
		if str(job.kind) == "escape":
			if int(executor.hit) != int(job.executor_hit) or _escape_blocked(executor, threats):
				job.elapsed = 0.0
				job.paused = "WATCHED"
				job.executor_hit = int(executor.hit)
			else:
				job.paused = ""
				job.elapsed = minf(ESCAPE_SECONDS, float(job.elapsed) + seconds)
			continue
		var work := seconds
		var fatigue := float(_body_get(executor, "fatigue"))
		if not bool(executor.player):
			var resting := Fatigue.needs_work_rest(fatigue, bool(_body_get(executor, "work_resting")))
			_body_set(executor, "work_resting", resting)
			if _threat(executor, threats):
				job.paused = "THREAT"
				job.elapsed = 0.0 # This batch must be continuous; completed earlier batches stand.
				continue
			if resting:
				job.paused = "REST"
				continue
			work = minf(work, maxf(0.0, Fatigue.WORK_REST_AT - fatigue) / Fatigue.WORK_RATE)
		job.paused = ""
		var remaining := maxf(0.0, float(job.duration) - float(job.elapsed))
		# Loot and handcraft share work productivity; binding retains its confirmed clock.
		var productive_work := str(job.kind) in ["loot", "ranged_craft"]
		var productive := Fatigue.work_seconds(fatigue, work) if productive_work else work
		if productive > remaining:
			# Monotone shared fatigue integral: find actual effort, not an entire long frame.
			var low := 0.0
			var high := work
			for iteration: int in 32:
				var middle := (low + high) * 0.5
				var output := Fatigue.work_seconds(fatigue, middle) if productive_work else middle
				if output < remaining:
					low = middle
				else:
					high = middle
			work = high
			productive = remaining
		job.elapsed = minf(float(job.duration), float(job.elapsed) + productive)
		var state := Fatigue.advance(fatigue, float(_body_get(executor, "fatigue_rest")), work, Fatigue.WORK_RATE, false)
		_body_set(executor, "fatigue", state[0])
		_body_set(executor, "fatigue_rest", state[1])
		handled[int(job.executor_id)] = work
		if not bool(executor.player) and state[0] >= Fatigue.WORK_REST_AT - 0.000000001:
			_body_set(executor, "fatigue", Fatigue.WORK_REST_AT)
			_body_set(executor, "work_resting", true)
			if float(job.elapsed) < float(job.duration) - 0.00000001:
				job.paused = "REST"
	return {"handled_seconds": handled}

func settle_after_contacts() -> Array[Dictionary]:
	if bool(lab.terrain.site.get("paused", false)):
		return [] # A completed pending batch does not commit behind a paused scene.
	# Stable original IDs are the sole tie-break; every later submission rechecks.
	var keys: Array = _jobs.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return int(a) < int(b))
	for key: String in keys:
		var job: Dictionary = _jobs[key]
		var check := _job_context(job)
		if check.ok and str(job.kind) == "escape":
			var person := _person(int(job.executor_id))
			if int(person.hit) != int(job.executor_hit) or _escape_blocked(person, {}):
				job.elapsed = 0.0
				job.paused = "WATCHED"
				job.executor_hit = int(person.hit)
		elif check.ok:
			var executor := _person(int(job.executor_id))
			if not bool(executor.player) and _threat(executor, {}):
				job.elapsed = 0.0
				job.paused = "THREAT" # A new contact/wake threat wins the completion boundary.
		if not check.ok:
			_finish(key, check)
		elif str(job.paused).is_empty() and float(job.elapsed) >= float(job.duration) - 0.00000001:
			_finish(key, _commit(job))
	var results := _results
	_results = []
	return results

func _finish(key: String, result: Dictionary) -> void:
	_jobs.erase(key)
	result["executor_id"] = int(key)
	_results.append(result)

func _commit(job: Dictionary) -> Dictionary:
	var executor := _person(int(job.executor_id))
	if str(job.kind) == "ranged_craft":
		return Runtime.ranged_craft(lab.terrain, str(job.recipe), int(job.executor_id))
	if str(job.kind) == "equipment":
		return equipment_orders.commit(job.order)
	if str(job.kind) == "loot":
		var source := _source(str(job.source_kind), str(job.source_id))
		var result := Runtime.ok()
		if not job.resources.is_empty() or not job.item_ids.is_empty():
			result = Runtime.transfer_items(lab.terrain, source.holder, source.cargo, executor.holder, executor.cargo,
				job.resources, job.item_ids, int(job.source_version), int(job.destination_version))
		elif float(job.open_amount) > 0.0:
			source.holder.version = int(source.holder.version) + 1
			executor.holder.version = int(executor.holder.version) + 1
		if result.ok:
			if float(job.open_amount) > 0.0:
				source.holder.open_rations = float(source.holder.open_rations) - float(job.open_amount)
				opened_food_commit.call(int(executor.person_id), float(job.open_amount), job.destination_pool)
			if str(job.source_kind) == "ground" and source.holder.item_ids.is_empty() and Runtime.inventory_size(source.cargo) == 0:
				Runtime.clear_empty_ground_loot(lab.terrain, str(job.source_id))
			var original_owner := int(source.get("person_id", source.holder.get("original_owner", 0)))
			if original_owner > 0 and equipment_changed.is_valid():
				equipment_changed.call(original_owner)
			if equipment_changed.is_valid():
				equipment_changed.call(int(executor.person_id))
		return result
	var target := _person(int(job.target_id))
	if str(job.kind) == "ransom":
		var query := _ransom_context(executor, target, _person(int(job.representative_id)))
		if not query.ok:
			return query
		# Both original owners have been checked. No callback/yield until both move.
		Runtime.add_items(query.source, job.resources, -1)
		for resource: String in query.source.keys():
			if int(query.source[resource]) == 0:
				query.source.erase(resource)
		Runtime.add_items(query.destination, job.resources)
		ransom_exchange_committed.call(query)
	var capturing := str(job.kind) == "capture"
	var captor_id := int(job.executor_id) if capturing else int(lab.terrain.site.captivity[str(job.target_id)].captor_id)
	var container := ""
	if capturing:
		var sealed := _sealed_selection(target)
		if not sealed.item_ids.is_empty() or not sealed.resources.is_empty():
			var result := Runtime.leave_ground_loot(lab.terrain, target.holder, target.cargo, int(job.target_id), target.cell,
				"sealed", sealed.resources, sealed.item_ids, int(job.source_version))
			if not result.ok:
				return result
			container = str(result.container_id)
		lab.terrain.site.captivity[str(job.target_id)] = {"version": 1, "captor_id": captor_id,
			"guard_id": int(job.guard_id), "captor_faction": int(executor.faction), "sealed_container": container}
	else:
		lab.terrain.site.captivity.erase(str(job.target_id))
	_body_set(target, "captive", capturing)
	# Binding is an original-holder state transition even if there was no gear.
	# It invalidates older simultaneous body requests without another person ledger.
	target.holder.version = int(target.holder.version) + 1
	captivity_supply_commit.call(int(job.target_id), captor_id, capturing)
	if equipment_changed.is_valid():
		equipment_changed.call(int(job.target_id))
	captivity_changed.call(int(job.target_id), captor_id, capturing)
	return Runtime.ok("已拘束；封存物留在原地" if capturing else "已解綁；生命與昏迷不變", {"container_id": container})

func _job_context(job: Dictionary) -> Dictionary:
	if str(job.kind) == "ranged_craft" and (not is_same(lab.terrain, job.terrain) or not is_same(lab.terrain.site, job.site_state)):
		return Runtime.fail("STALE_SOURCE", "原營地／Site 已切換，手作未扣材料")
	var executor := _person(int(job.executor_id))
	if str(job.kind) == "escape":
		var check := _escape_context(executor)
		if not check.ok:
			return check
		if lab.terrain.index(executor.cell) != int(job.executor_cell):
			return Runtime.fail("INTERRUPTED", "逃脫者移動")
		if lab.terrain.site.captivity.get(str(job.target_id), {}) != job.captivity or int(executor.holder.version) != int(job.source_version):
			return Runtime.fail("STALE_SOURCE")
		return Runtime.ok()
	if executor.is_empty() or int(executor.hit) != int(job.executor_hit) or lab.terrain.index(executor.cell) != int(job.executor_cell):
		return Runtime.fail("INTERRUPTED", "執行者受擊、移動或已不存在")
	if str(job.kind) == "ranged_craft":
		var check := _ranged_craft_context(executor)
		if not check.ok:
			return check
		if not is_same(executor.holder, job.executor_holder) or not is_same(executor.cargo, job.executor_cargo) \
			or int(executor.holder.version) != int(job.executor_version) \
			or not is_same(lab.terrain.site.depot_items, job.depot_holder) or not is_same(lab.terrain.site.inventory, job.depot_stock):
			return Runtime.fail("STALE_SOURCE", "原人物或營地持物已切換，手作未扣材料")
		return Runtime.ranged_craft(lab.terrain, str(job.recipe), int(job.executor_id), true)
	if str(job.kind) == "equipment":
		return equipment_orders.check(job.order) if equipment_orders != null else Runtime.fail("UNSUPPORTED")
	if str(job.kind) == "loot":
		var source := _source(str(job.source_kind), str(job.source_id))
		var check := _loot_context(executor, source)
		if not check.ok:
			return check
		if int(source.holder.version) != int(job.source_version) or int(executor.holder.version) != int(job.destination_version):
			return Runtime.fail("STALE_SOURCE")
		if not is_same(source.holder, job.source_holder) or not is_same(source.cargo, job.source_cargo) or not is_same(executor.holder, job.destination_holder) or not is_same(executor.cargo, job.destination_cargo):
			return Runtime.fail("STALE_SOURCE", "原持物資料已被替換")
		if float(job.open_amount) > 0.0:
			var pool: Dictionary = opened_food_pool.call(int(executor.person_id))
			if float(source.holder.get("open_rations", 0.0)) != float(job.source_open) or (not pool.is_empty() or not job.destination_pool.is_empty()) and not is_same(pool, job.destination_pool):
				return Runtime.fail("STALE_SOURCE", "開封口糧來源或私人餐份持有人已變更")
		if lab.terrain.index(source.cell) != int(job.source_cell) or int(source.get("hit", -1)) != int(job.target_hit):
			return Runtime.fail("INTERRUPTED", "搜身目標受擊或移動")
		check = _selection(executor, source, job.resources, job.item_ids, float(job.open_amount))
		return check if not check.ok else _removal_guard(source, job.item_ids)
	var target := _person(int(job.target_id))
	if str(job.kind) == "ransom":
		var representative := _person(int(job.representative_id))
		var query := _ransom_context(executor, target, representative)
		if not query.ok:
			return query
		if int(representative.hit) != int(job.representative_hit) or lab.terrain.index(representative.cell) != int(job.representative_cell):
			return Runtime.fail("INTERRUPTED", "拘押代表受擊或移動")
		if str(query.source_owner) != str(job.source_owner) or str(query.destination_owner) != str(job.destination_owner) or int(query.source_revision) != int(job.source_revision) or int(query.destination_revision) != int(job.destination_revision):
			return Runtime.fail("STALE_SOURCE")
		if query.source != job.source_stock or not Runtime.can_pay(query.source, job.resources):
			return Runtime.fail("STALE_SOURCE", "付款庫存已被供餐消耗或變更")
		if lab.terrain.site.captivity.get(str(job.target_id), {}) != job.captivity or int(target.holder.version) != int(job.source_version):
			return Runtime.fail("STALE_SOURCE")
		return Runtime.ok()
	if target.is_empty() or int(target.hit) != int(job.target_hit) or lab.terrain.index(target.cell) != int(job.source_cell):
		return Runtime.fail("INTERRUPTED", "目標受擊、移動或已不存在")
	if int(target.holder.version) != int(job.source_version):
		return Runtime.fail("STALE_SOURCE")
	return _binding_context(executor, target, int(job.guard_id), str(job.kind) == "capture")

func _ranged_craft_context(executor: Dictionary) -> Dictionary:
	var depot := _source("depot", "depot")
	if depot.is_empty() or not _ready(executor) or not _adjacent(executor.cell, depot.cell) or float(lab.terrain.site.get("combat_left", 0.0)) > 0.0:
		return Runtime.fail("BUSY", "手作須脫戰、清醒自由、停止於營地相鄰合法格且無其他作業")
	return Runtime.ok()

func _loot_context(executor: Dictionary, source: Dictionary) -> Dictionary:
	if source.is_empty():
		return Runtime.fail("NO_TARGET", "來源不存在或尚未初始化實際持物")
	if not _ready(executor) or not _adjacent(executor.cell, source.cell):
		return Runtime.fail("BUSY", "須清醒自由、停止於相鄰可達格且沒有其他作業")
	if source.has("person_id"):
		if bool(source.player) or float(source.hp) <= 0.0 or float(source.ko) <= 0.0 or bool(source.captive) or bool(source.moving):
			return Runtime.fail("NO_TARGET", "只可搜身已停止的存活昏迷 NPC；死亡請重新選遺物")
	return Runtime.ok()

func _selection(executor: Dictionary, source: Dictionary, resources: Dictionary, item_ids: Array, open_amount: float = 0.0) -> Dictionary:
	if int(executor.holder.version) >= 2147483646 or int(source.holder.version) >= 2147483646:
		return Runtime.fail("STALE_SOURCE", "原持物提交版本已用盡，未取物")
	if not is_finite(open_amount) or open_amount < 0.0 or open_amount > Runtime.CARRY_CAPACITY:
		return Runtime.fail("INVALID", "開封口糧數量")
	if not Runtime._resource_stack(resources, false) or (resources.is_empty() and item_ids.is_empty() and open_amount <= 0.0):
		return Runtime.fail("INVALID", "請選正整數資源或實際物品")
	if open_amount > 0.0 and (source.has("person_id") or not opened_food_pool.is_valid() or not opened_food_commit.is_valid() or float(source.holder.get("open_rations", 0.0)) < open_amount):
		return Runtime.fail("EMPTY", "請選原地面容器的實際開封口糧")
	if not Runtime.can_pay(source.cargo, resources):
		return Runtime.fail("EMPTY")
	var selected := {}
	for identity: Variant in item_ids:
		if not identity is String or selected.has(identity) or not source.holder.item_ids.has(identity):
			return Runtime.fail("INVALID", "不存在或重複物品")
		var record: Dictionary = lab.terrain.site.item_records.get(identity, {})
		if str(record.get("holder", "")) != str(source.holder.holder):
			return Runtime.fail("STALE_SOURCE")
		selected[identity] = true
	if Runtime.carried_load(lab.terrain.site, executor.cargo, executor.holder) + Runtime.inventory_size(resources) + item_ids.size() + open_amount > Runtime.CARRY_CAPACITY:
		return Runtime.fail("STORAGE_FULL")
	return Runtime.ok()

func _removal_guard(source: Dictionary, item_ids: Array) -> Dictionary:
	var owner_id := int(source.get("person_id", 0))
	if owner_id <= 0 and str(source.holder.get("kind", "")) == "remains":
		for identity: String in item_ids:
			if source.holder.equipped.values().has(identity):
				owner_id = int(source.holder.original_owner)
	if owner_id <= 0 or item_ids.is_empty():
		return Runtime.ok()
	if not equipment_removal_guard.is_valid() or not equipment_changed.is_valid():
		return Runtime.fail("UNSUPPORTED", "尚未接好原人物實裝／命中更新")
	return equipment_removal_guard.call(owner_id, item_ids)

func _binding_context(executor: Dictionary, target: Dictionary, guard_id: int, capturing: bool) -> Dictionary:
	if not _ready(executor, capturing) or target.is_empty() or float(target.hp) <= 0.0 or bool(target.moving) or not _adjacent(executor.cell, target.cell):
		return Runtime.fail("BUSY", "雙方須存活、停止並相鄰可達")
	if capturing:
		if float(target.ko) <= 0.0 or bool(target.captive) or lab.terrain.site.captivity.has(str(target.person_id)):
			return Runtime.fail("NO_TARGET", "目標須昏迷且尚未被俘")
		var guard := _person(guard_id, false)
		if not _ready(guard, true) or (not bool(guard.player) and bool(_body_get(guard, "work_resting"))) or int(guard.faction) != int(executor.faction) or not _within_guard_range(guard.cell, target.cell):
			return Runtime.fail("GUARD", "需要同拘押方清醒自由、四步合法路程內的看守")
		var count := 0
		for entry: Dictionary in lab.terrain.site.captivity.values():
			count += int(int(entry.guard_id) == guard_id)
		if count >= GUARD_CAPACITY or (guard_id != int(executor.person_id) and is_busy(guard_id)):
			return Runtime.fail("GUARD", "看守已滿四人或有其他作業")
		var sealed := _sealed_selection(target)
		var equipment_check := _removal_guard(target, sealed.item_ids)
		if not equipment_check.ok:
			return equipment_check
	else:
		if not bool(target.captive) or not lab.terrain.site.captivity.has(str(target.person_id)) or int(target.faction) != int(executor.faction):
			return Runtime.fail("NO_TARGET", "外部解綁只適用原友方俘虜")
	if not captivity_change_guard.is_valid() or not captivity_supply_commit.is_valid() or not captivity_changed.is_valid():
		return Runtime.fail("UNSUPPORTED", "尚未接好原人物拘押／供養提交")
	var captor_id := int(executor.person_id) if capturing else int(lab.terrain.site.captivity[str(target.person_id)].captor_id)
	return captivity_change_guard.call(int(target.person_id), captor_id, capturing)

func _escape_context(person: Dictionary) -> Dictionary:
	if person.is_empty() or float(person.hp) <= 0.0 or float(person.ko) > 0.0 or not bool(person.captive) or bool(person.moving) or not lab.terrain.site.captivity.has(str(person.person_id)):
		return Runtime.fail("BUSY", "只有原清醒俘虜能自行逃脫；死亡或失能優先")
	if not captivity_change_guard.is_valid() or not captivity_supply_commit.is_valid() or not captivity_changed.is_valid():
		return Runtime.fail("UNSUPPORTED")
	return captivity_change_guard.call(int(person.person_id), int(lab.terrain.site.captivity[str(person.person_id)].captor_id), false)

func _escape_blocked(person: Dictionary, candidates: Dictionary) -> bool:
	return has_effective_guard(int(person.person_id)) or _threat(person, candidates)

func _ransom_context(payer: Dictionary, target: Dictionary, representative: Dictionary) -> Dictionary:
	if not _ready(payer) or not _ready(representative, true) or target.is_empty() or float(target.hp) <= 0.0 or not bool(target.captive) or not lab.terrain.site.captivity.has(str(target.person_id)):
		return Runtime.fail("BUSY", "須由雙方清醒自由的實際代表交付")
	if is_busy(int(representative.person_id)):
		return Runtime.fail("BUSY", "拘押代表已有其他未完成作業")
	if int(payer.faction) != int(target.faction) or int(representative.faction) != int(lab.terrain.site.captivity[str(target.person_id)].captor_faction) or not _adjacent(payer.cell, representative.cell):
		return Runtime.fail("AUTHORITY", "友方付款代表與拘押方代表須相鄰可達")
	if not ransom_exchange_query.is_valid() or not ransom_exchange_committed.is_valid() or not captivity_change_guard.is_valid() or not captivity_supply_commit.is_valid() or not captivity_changed.is_valid():
		return Runtime.fail("UNSUPPORTED")
	var check: Dictionary = captivity_change_guard.call(int(target.person_id), int(lab.terrain.site.captivity[str(target.person_id)].captor_id), false)
	if not check.ok:
		return check
	var query: Dictionary = ransom_exchange_query.call(int(payer.person_id), int(target.person_id), int(representative.person_id))
	if not query.ok:
		return query
	if not query.get("source") is Dictionary or not query.get("destination") is Dictionary or is_same(query.source, query.destination) or str(query.get("source_owner", "")).is_empty() or str(query.get("destination_owner", "")).is_empty() or str(query.source_owner) == str(query.destination_owner):
		return Runtime.fail("INVALID", "贖回須使用兩個不同的原實物庫存")
	if not Runtime._resource_stack(query.source) or not Runtime._resource_stack(query.destination) or not query.get("source_revision") is int or not query.get("destination_revision") is int or int(query.source_revision) < 0 or int(query.destination_revision) < 0:
		return Runtime.fail("INVALID", "原實物庫存或提交版本不合法")
	return query

func _sealed_selection(target: Dictionary) -> Dictionary:
	var ids: Array = []
	for identity: String in target.holder.item_ids:
		var record: Dictionary = lab.terrain.site.item_records[identity]
		var definition: Dictionary = lab.terrain.site.item_definitions[str(record.definition)]
		if str(definition.slot) in ["weapon", "shield"]:
			ids.append(identity)
	var resources := {}
	for ammunition: String in ["arrow", "bolt"]:
		if int(target.cargo.get(ammunition, 0)) > 0:
			resources[ammunition] = int(target.cargo[ammunition])
	return {"resources": resources, "item_ids": ids}

func _source(kind: String, identity: String) -> Dictionary:
	if kind == "person":
		return _person(int(identity)) if identity.is_valid_int() and str(int(identity)) == identity else {}
	if kind == "depot" and identity == "depot":
		var depot: Dictionary = lab.terrain.site.get("depot_items", {})
		if not Runtime._item_holder_shape(depot) or str(depot.holder) != "depot" or not lab.terrain.site.get("inventory") is Dictionary or not lab.terrain.site.has("depot_cell"):
			return {}
		return {"holder": depot, "cargo": lab.terrain.site.inventory, "cell": lab.terrain.cell_from_index(int(lab.terrain.site.depot_cell))}
	if kind != "ground":
		return {}
	var holder: Dictionary = lab.terrain.site.get("ground_loot", {}).get(identity, {})
	if holder.is_empty():
		return {}
	return {"holder": holder, "cargo": holder.cargo, "cell": lab.terrain.cell_from_index(int(holder.cell))}

func _person(identity: int, require_items: bool = true) -> Dictionary:
	var person: Dictionary = lab._combat_target(identity)
	if person.is_empty():
		return {}
	var owner: Variant = person.owner
	var unit := int(person.unit)
	var body: Variant = owner.combat_units[unit] if unit >= 0 else owner
	var holder: Variant = body.get("item_state")
	if require_items and (not holder is Dictionary or not Runtime._item_holder_shape(holder)):
		return {}
	var cargo: Dictionary = {}
	if unit >= 0:
		if not body.get("cargo") is Dictionary:
			if require_items:
				return {}
		else:
			cargo = body.cargo
	elif owner == lab.character:
		cargo = lab.terrain.site.manual.cargo
	elif owner == lab.npc:
		cargo = lab.terrain.site.worker.cargo
	else:
		return {} # An original owner must explicitly expose its real cargo.
	person.merge({"body": body, "holder": holder, "cargo": cargo, "person_id": identity,
		"ko": float(body.get("ko") if unit >= 0 else body.knockout_left), "captive": bool(body.get("captive")),
		"faction": int(owner.faction_id), "player": identity == (int(lab.controlled_person_id()) if lab.has_method("controlled_person_id") else int(lab.character.person_id)),
		"moving": owner.moving_to[unit] != Vector2i(-1, -1) if unit >= 0 else owner.is_moving(),
		"hit": int(body.get("hit_revision", 0)) if unit >= 0 else int(owner._received_effective_hit)})
	return person

func _ready(person: Dictionary, allow_guard: bool = false) -> bool:
	if person.is_empty() or float(person.hp) <= 0.0 or float(person.ko) > 0.0 or bool(person.captive) or bool(person.moving):
		return false
	if float(_body_get(person, "exchange_stagger")) > 0.0:
		return false # Action eligibility reads the original lock, not a render-only hit pose.
	if not allow_guard and is_guarding(int(person.person_id)):
		return false
	for entry: Dictionary in lab.terrain.site.get("team_supply", {}).values():
		var delivery: Dictionary = entry.get("delivery", {})
		if not delivery.is_empty() and int(person.person_id) in [int(delivery.get("player_id", -1)), int(delivery.get("representative_id", -1))]:
			return false
	if int(person.unit) >= 0:
		return person.owner.combat_can_act(int(person.unit)) and not bool(person.body.attack) and str(person.body.pose) == "idle" and person.body.get("work_task", {}).is_empty()
	var actor: Variant = person.owner
	if not actor.can_act() or actor.action_time > 0.0 or actor.guarding or actor.guard_transition_left > 0.0 or actor.guard_break_left > 0.0 or actor._rescue_left > 0.0:
		return false
	if actor == lab.npc and (int(actor.command) != 0 or not actor._path.is_empty()):
		return false # Do not steal an already queued original NPC movement command.
	var activity: Dictionary = lab.terrain.site.manual if actor == lab.character else lab.terrain.site.worker
	if not str(activity.get("target", "")).is_empty():
		return false
	return true

func _adjacent(from: Vector2i, to: Vector2i) -> bool:
	return absi(from.x - to.x) + absi(from.y - to.y) == 1 and lab.terrain.can_step(from, to)

func _within_guard_range(from: Vector2i, to: Vector2i) -> bool:
	if from == to or absi(from.x - to.x) + absi(from.y - to.y) > GUARD_STEPS:
		return false
	# Query only during an explicit capture command, not each idle guard per frame.
	var path: Array[Vector2i] = lab.terrain.path_between(from, to, func(cell: Vector2i) -> bool:
		return absi(from.x - cell.x) + absi(from.y - cell.y) > GUARD_STEPS)
	return not path.is_empty() and path.size() <= GUARD_STEPS

func _threat(person: Dictionary, candidates: Dictionary) -> bool:
	return bool(lab._fatigue_threat(person.cell, int(person.faction), person.owner, int(person.unit), candidates))

func _body_get(person: Dictionary, field: String) -> Variant:
	if person.body is Dictionary:
		return person.body.get(field, false if field == "work_resting" else 0.0)
	return person.body.get(field)

func _body_set(person: Dictionary, field: String, value: Variant) -> void:
	if person.body is Dictionary:
		person.body[field] = value
	else:
		person.body.set(field, value)
