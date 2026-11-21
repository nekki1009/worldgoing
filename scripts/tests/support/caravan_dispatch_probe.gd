extends RefCounted
## Test stand-in for site_caravan.gd (region_live_dispatch_test takes over its path): the daily hook and the evaluation
## hook call back into the probe instead of the real caravan rules.
static var on_dispatch: Callable = Callable()
static var calls: Array = []

static func dispatch(controller: Variant) -> Dictionary:
	if not on_dispatch.is_valid(): return {"reason": "probe_idle"}
	var result: Dictionary = on_dispatch.call(controller)
	calls.append(result)
	return result

static func evaluate(_slot: Variant, _lab: Variant) -> Dictionary:
	return {"turned": [], "home": []}
