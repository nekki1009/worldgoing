extends RefCounted
## Payload/reference codec only. Original owners choose roots and apply the prepared values.
const Checkpoint = preload("res://scripts/terrain_lab/site_region_checkpoint.gd")
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const LIMIT := 100000
const VERSION: int = 2
const MAX_ATOM_BYTES: int = 33554432

static func capture(roots: Dictionary, references: Dictionary, context: Dictionary) -> Dictionary:
	var stamp := context.duplicate(true)
	stamp.erase("owners")
	var checked := Checkpoint.validate_context(stamp)
	if not checked.ok: return checked
	if not _valid_references(references): return Runtime.fail("INVALID_REGION_REFERENCE")
	var graph := {"nodes": [], "seen": [], "error": ""}
	var encoded := _encode(roots, references, graph, 0, false)
	if not str(graph.error).is_empty(): return Runtime.fail(str(graph.error))
	var snapshot: Dictionary = {"version": VERSION, "context": stamp, "root": encoded, "nodes": graph.nodes}
	return Runtime.ok("", {"state": snapshot, "snapshot": snapshot})

static func prepare_restore(snapshot: Variant, references: Dictionary, expected: Dictionary = {}) -> Dictionary:
	if not snapshot is Dictionary or snapshot.size() != 4 or not Checkpoint.integer(snapshot.get("version"), 1) or int(snapshot.version) not in [1, VERSION] or not snapshot.get("nodes") is Array or snapshot.nodes.size() > LIMIT:
		return Runtime.fail("INVALID_REGION_OWNER_SNAPSHOT")
	var checked := Checkpoint.validate_context(snapshot.get("context"), expected)
	if not checked.ok: return checked
	if not _valid_references(references): return Runtime.fail("INVALID_REGION_REFERENCE")
	var nodes: Array = snapshot.nodes
	if not _valid_value(snapshot.get("root"), nodes, references, false, int(snapshot.version)): return Runtime.fail("INVALID_REGION_OWNER_SNAPSHOT")
	for node: Variant in nodes:
		if not node is Dictionary or node.size() != 2 or str(node.get("kind", "")) not in ["dictionary", "array"] or not node.get("entries") is Array or node.entries.size() > LIMIT:
			return Runtime.fail("INVALID_REGION_OWNER_SNAPSHOT")
		for entry: Variant in node.entries:
			if node.kind == "dictionary":
				if not entry is Array or entry.size() != 2 or not _valid_value(entry[0], nodes, references, true, int(snapshot.version)) or not _valid_value(entry[1], nodes, references, false, int(snapshot.version)): return Runtime.fail("INVALID_REGION_OWNER_SNAPSHOT")
			elif not _valid_value(entry, nodes, references, false, int(snapshot.version)): return Runtime.fail("INVALID_REGION_OWNER_SNAPSHOT")
	# Allocate all payload containers before connecting aliases; no original owner is mutated.
	var decoded: Array = []
	for node: Dictionary in nodes: decoded.append({} if node.kind == "dictionary" else [])
	for index: int in nodes.size():
		var node: Dictionary = nodes[index]
		if node.kind == "dictionary":
			for pair: Array in node.entries:
				var key: Variant = _decode(pair[0], decoded, references)
				if decoded[index].has(key): return Runtime.fail("INVALID_REGION_OWNER_SNAPSHOT", "duplicate key")
				decoded[index][key] = _decode(pair[1], decoded, references)
		else:
			for entry: Dictionary in node.entries: decoded[index].append(_decode(entry, decoded, references))
	var roots: Variant = _decode(snapshot.root, decoded, references)
	if not roots is Dictionary: return Runtime.fail("INVALID_REGION_OWNER_SNAPSHOT")
	return Runtime.ok("", {"roots": roots, "context": checked.context, "owners_prepared": true,
		"effects_pending": not bool(checked.context.effects_complete), "zero_world_only": not bool(checked.context.effects_complete)})

## A live ration delivery job holds aliases of original stocks, bodies and owners.
## The Store saves only its recipe and removes exactly these fields, so a path
## through them never exists in a saved body. Each aliased value keeps the path
## of its actual home; a pool stored nowhere else stays a plain graph value.
const DELIVERY_ALIAS_FIELDS := ["source_owner", "receiver_owner", "source_body", "receiver_body", "source_cargo", "source_holder", "source_open"]

static func register_tree(references: Dictionary, prefix: String, value: Variant) -> void:
	# Deterministic original Site/body paths; this is a transient reference index, not stored state.
	_register_tree(references, prefix, value, [], [], 0)

static func register_person(references: Dictionary, identity: int, person: Dictionary) -> Dictionary:
	if identity <= 0 or person.is_empty() or int(person.get("person_id", identity)) != identity:
		return Runtime.fail("INVALID_REGION_PERSON_REFERENCE")
	for field: String in ["owner", "body", "holder", "cargo"]:
		var value: Variant = person.get(field)
		if value == null: continue
		if not _reference_value(value): return Runtime.fail("INVALID_REGION_PERSON_REFERENCE", field)
		references["person:" + str(identity) + ":" + field] = value
	return Runtime.ok()

static func _register_tree(references: Dictionary, prefix: String, value: Variant, path: Array, seen: Array, depth: int) -> void:
	if depth > 48 or not (value is Dictionary or value is Array): return
	for original: Variant in seen:
		if is_same(original, value): return
	seen.append(value)
	references[prefix + ":" + JSON.stringify(Checkpoint.wire(path))] = value
	if value is Dictionary:
		for key: Variant in value:
			if not Checkpoint.supported(key): continue
			if prefix == "site" and path.size() == 3 and str(path[0]) == "team_supply" and str(path[2]) == "delivery" and str(key) in DELIVERY_ALIAS_FIELDS: continue
			_register_tree(references, prefix, value[key], path + [key], seen, depth + 1)
	else:
		for index: int in value.size(): _register_tree(references, prefix, value[index], path + [index], seen, depth + 1)

static func _reference_value(value: Variant) -> bool:
	if value is Object: return is_instance_valid(value)
	if value is Callable: return value.is_valid()
	return value is Dictionary or value is Array

static func _valid_references(references: Dictionary) -> bool:
	if references.size() > LIMIT: return false
	for key: Variant in references:
		if not key is String or str(key).is_empty() or str(key).length() > 4096 or not _reference_value(references[key]): return false
	return true

static func _encode(value: Variant, references: Dictionary, graph: Dictionary, depth: int, allow_reference: bool = true) -> Dictionary:
	if depth > 48:
		graph["error"] = "REGION_OWNER_DEPTH"
		return {}
	if value is float and (value == INF or value == -INF): return {"kind": "infinity", "sign": 1 if value == INF else -1}
	if value is Callable and value.is_null(): return {"kind": "empty_callable"}
	if allow_reference and _reference_value(value):
		for key: String in references:
			if is_same(value, references[key]): return {"kind": "reference", "key": key, "type": typeof(value)}
	if value is Object or value is Callable or value is Signal:
		graph["error"] = "UNBOUND_REGION_REFERENCE"
		return {}
	if value is Dictionary or value is Array:
		for index: int in graph.seen.size():
			if is_same(graph.seen[index], value): return {"kind": "node", "index": index}
		if graph.nodes.size() >= LIMIT or value.size() > LIMIT:
			graph["error"] = "REGION_OWNER_LIMIT"
			return {}
		var index: int = graph.nodes.size()
		graph.seen.append(value)
		var node := {"kind": "dictionary" if value is Dictionary else "array", "entries": []}
		graph.nodes.append(node)
		if value is Dictionary:
			for key: Variant in value:
				if key == null or key is Object or key is Dictionary or key is Array or key is Callable or key is Signal or not Checkpoint.supported(key):
					graph["error"] = "INVALID_REGION_OWNER_KEY"
					return {}
				node.entries.append([_encode(key, references, graph, depth + 1), _encode(value[key], references, graph, depth + 1)])
		else:
			for entry: Variant in value: node.entries.append(_encode(entry, references, graph, depth + 1))
		return {"kind": "node", "index": index}
	if not Checkpoint.supported(value):
		graph["error"] = "UNSUPPORTED_REGION_OWNER_VALUE"
		return {}
	return {"kind": "atom", "bytes": Marshalls.raw_to_base64(var_to_bytes(value))}

static func _valid_value(value: Variant, nodes: Array, references: Dictionary, dictionary_key: bool = false, version: int = 1) -> bool:
	if not value is Dictionary: return false
	match str(value.get("kind", "")):
		"infinity": return not dictionary_key and value.size() == 2 and Checkpoint.integer(value.get("sign"), -1) and value.sign in [-1, 1]
		"empty_callable": return not dictionary_key and value.size() == 1
		"reference":
			return not dictionary_key and value.size() == 3 and value.get("key") is String and references.has(value.key) and Checkpoint.integer(value.get("type")) and typeof(references[value.key]) == int(value.type)
		"node":
			return not dictionary_key and value.size() == 2 and Checkpoint.integer(value.get("index")) and int(value.index) < nodes.size()
		"atom":
			if version != VERSION or not _valid_atom(value): return false
			return not dictionary_key or bytes_to_var(Marshalls.base64_to_raw(value["bytes"])) != null
		"value":
			if value.size() != 2 or not Checkpoint.valid_wire(value.get("wire")): return false
			var decoded: Variant = Checkpoint.unwire(value.wire)
			return not dictionary_key or decoded != null and not (decoded is Dictionary or decoded is Array)
	return false

static func _decode(value: Dictionary, nodes: Array, references: Dictionary) -> Variant:
	match str(value.kind):
		"infinity": return INF if int(value.sign) > 0 else -INF
		"empty_callable": return Callable()
		"reference": return references[value.key]
		"node": return nodes[int(value.index)]
		"atom": return bytes_to_var(Marshalls.base64_to_raw(value["bytes"]))
		"value": return Checkpoint.unwire(value.wire)
	return null
## Read one pure descriptor field before binding original object references.
## This never resolves a Node, holder or callable and never mutates any owner.
static func peek_values(snapshot: Variant, field: String, expected: Dictionary = {}) -> Dictionary:
	if not snapshot is Dictionary or snapshot.size() != 4 or not Checkpoint.integer(snapshot.get("version"), 1) or int(snapshot.version) not in [1, VERSION] or not snapshot.get("nodes") is Array or snapshot.nodes.size() > LIMIT:
		return Runtime.fail("INVALID_REGION_OWNER_SNAPSHOT")
	var checked := Checkpoint.validate_context(snapshot.get("context"), expected)
	if not checked.ok: return checked
	var root: Variant = snapshot.get("root")
	if not root is Dictionary or root.size() != 2 or root.get("kind") != "node" or not Checkpoint.integer(root.get("index")) or int(root.index) >= snapshot.nodes.size(): return Runtime.fail("INVALID_REGION_OWNER_SNAPSHOT")
	var node: Variant = snapshot.nodes[int(root.index)]
	if not node is Dictionary or node.size() != 2 or node.get("kind") != "dictionary" or not node.get("entries") is Array or node.entries.size() > LIMIT: return Runtime.fail("INVALID_REGION_OWNER_SNAPSHOT")
	var selected: Variant = null
	var budget := {"left": LIMIT}
	for pair: Variant in node.entries:
		if not pair is Array or pair.size() != 2: return Runtime.fail("INVALID_REGION_OWNER_SNAPSHOT")
		var key: Dictionary = _peek_value(pair[0], snapshot.nodes, [], 0, budget, int(snapshot.version))
		if not key.ok: return key
		if key.value == field:
			if selected != null: return Runtime.fail("INVALID_REGION_OWNER_SNAPSHOT")
			selected = pair[1]
	if selected == null: return Runtime.fail("MISSING_REGION_REFERENCE_VALUES")
	return _peek_value(selected, snapshot.nodes, [], 0, budget, int(snapshot.version))

static func _peek_value(value: Variant, nodes: Array, ancestors: Array, depth: int, budget: Dictionary, version: int = 1) -> Dictionary:
	budget["left"] = int(budget.left) - 1
	if depth > 48 or int(budget.left) < 0 or not value is Dictionary: return Runtime.fail("INVALID_REGION_REFERENCE_VALUES")
	if value.get("kind") == "atom":
		if version != VERSION or not _valid_atom(value): return Runtime.fail("INVALID_REGION_REFERENCE_VALUES")
		return Runtime.ok("", {"value": bytes_to_var(Marshalls.base64_to_raw(value["bytes"]))})
	if value.get("kind") == "value":
		if value.size() != 2 or not Checkpoint.valid_wire(value.get("wire")): return Runtime.fail("INVALID_REGION_REFERENCE_VALUES")
		return Runtime.ok("", {"value": Checkpoint.unwire(value.wire)})
	if value.size() != 2 or value.get("kind") != "node" or not Checkpoint.integer(value.get("index")) or int(value.index) >= nodes.size() or ancestors.has(int(value.index)):
		return Runtime.fail("INVALID_REGION_REFERENCE_VALUES")
	var node: Variant = nodes[int(value.index)]
	if not node is Dictionary or node.size() != 2 or node.get("kind") not in ["dictionary", "array"] or not node.get("entries") is Array or node.entries.size() > LIMIT:
		return Runtime.fail("INVALID_REGION_REFERENCE_VALUES")
	var next := ancestors + [int(value.index)]
	var result: Variant = {} if node.kind == "dictionary" else []
	for entry: Variant in node.entries:
		if node.kind == "dictionary":
			if not entry is Array or entry.size() != 2: return Runtime.fail("INVALID_REGION_REFERENCE_VALUES")
			var key: Dictionary = _peek_value(entry[0], nodes, next, depth + 1, budget, version)
			var item: Dictionary = _peek_value(entry[1], nodes, next, depth + 1, budget, version)
			if not key.ok or not item.ok or key.value == null or key.value is Array or key.value is Dictionary or result.has(key.value): return Runtime.fail("INVALID_REGION_REFERENCE_VALUES")
			result[key.value] = item.value
		else:
			var item: Dictionary = _peek_value(entry, nodes, next, depth + 1, budget, version)
			if not item.ok: return item
			result.append(item.value)
	return Runtime.ok("", {"value": result})
## Validate the entire graph and its original identity manifest without Nodes
## or holder copies. Symbolic values are used only for the caller's schema check.
static func validate_for_bind(snapshot: Variant, reference_validator: Callable, expected: Dictionary = {}) -> Dictionary:
	if not reference_validator.is_valid() or not snapshot is Dictionary or snapshot.size() != 4 or not Checkpoint.integer(snapshot.get("version"), 1) or int(snapshot.version) not in [1, VERSION] or not snapshot.get("nodes") is Array or snapshot.nodes.size() > LIMIT:
		return Runtime.fail("INVALID_REGION_OWNER_SNAPSHOT")
	var checked := Checkpoint.validate_context(snapshot.get("context"), expected)
	if not checked.ok: return checked
	var nodes: Array = snapshot.nodes
	var reference_types := {}
	if not _valid_bind_value(snapshot.get("root"), nodes, reference_validator, reference_types, false, int(snapshot.version)): return Runtime.fail("INVALID_REGION_OWNER_SNAPSHOT")
	for node: Variant in nodes:
		if not node is Dictionary or node.size() != 2 or node.get("kind") not in ["dictionary", "array"] or not node.get("entries") is Array or node.entries.size() > LIMIT:
			return Runtime.fail("INVALID_REGION_OWNER_SNAPSHOT")
		for entry: Variant in node.entries:
			if node.kind == "dictionary":
				if not entry is Array or entry.size() != 2 or not _valid_bind_value(entry[0], nodes, reference_validator, reference_types, true, int(snapshot.version)) or not _valid_bind_value(entry[1], nodes, reference_validator, reference_types, false, int(snapshot.version)): return Runtime.fail("INVALID_REGION_OWNER_SNAPSHOT")
			elif not _valid_bind_value(entry, nodes, reference_validator, reference_types, false, int(snapshot.version)): return Runtime.fail("INVALID_REGION_OWNER_SNAPSHOT")
	var decoded: Array = []
	for node: Dictionary in nodes: decoded.append({} if node.kind == "dictionary" else [])
	var symbols := {}
	for key: String in reference_types: symbols[key] = {"@region_reference": key, "type": int(reference_types[key])}
	for index: int in nodes.size():
		var node: Dictionary = nodes[index]
		if node.kind == "dictionary":
			for pair: Array in node.entries:
				var key: Variant = _decode(pair[0], decoded, symbols)
				if decoded[index].has(key): return Runtime.fail("INVALID_REGION_OWNER_SNAPSHOT")
				decoded[index][key] = _decode(pair[1], decoded, symbols)
		else:
			for entry: Dictionary in node.entries: decoded[index].append(_decode(entry, decoded, symbols))
	var roots: Variant = _decode(snapshot.root, decoded, symbols)
	if not roots is Dictionary: return Runtime.fail("INVALID_REGION_OWNER_SNAPSHOT")
	return Runtime.ok("", {"roots": roots, "context": checked.context, "reference_types": reference_types, "symbols": symbols,
		"graph_hash": Checkpoint.state_hash({"graph": snapshot}), "graph_prepared": true})

static func _valid_bind_value(value: Variant, nodes: Array, validator: Callable, reference_types: Dictionary, dictionary_key: bool = false, version: int = 1) -> bool:
	if not value is Dictionary: return false
	if value.get("kind") != "reference": return _valid_value(value, nodes, {}, dictionary_key, version)
	if dictionary_key or value.size() != 3 or not value.get("key") is String or not Checkpoint.integer(value.get("type")) or str(value.key).is_empty() or str(value.key).length() > 4096: return false
	var key := str(value.key)
	var kind := int(value.type)
	if reference_types.has(key) and int(reference_types[key]) != kind: return false
	var admitted: Variant = validator.call(key, kind)
	if not admitted is bool or not admitted: return false
	reference_types[key] = kind
	return true

static func _encode_bind_roots(value: Variant, graph: Dictionary, depth: int) -> Dictionary:
	if depth > 48:
		graph["error"] = "REGION_OWNER_DEPTH"
		return {}
	if value is Dictionary and value.size() == 2 and value.get("@region_reference") is String and Checkpoint.integer(value.get("type")):
		var kind := int(value.type)
		if kind not in [TYPE_OBJECT, TYPE_CALLABLE, TYPE_DICTIONARY, TYPE_ARRAY] or str(value["@region_reference"]).is_empty():
			graph["error"] = "INVALID_REGION_REFERENCE"
			return {}
		return {"kind": "reference", "key": str(value["@region_reference"]), "type": kind}
	if value is float and (value == INF or value == -INF): return {"kind": "infinity", "sign": 1 if value == INF else -1}
	if value is Callable and value.is_null(): return {"kind": "empty_callable"}
	if value is Object or value is Callable or value is Signal:
		graph["error"] = "UNBOUND_REGION_REFERENCE"
		return {}
	if value is Dictionary or value is Array:
		for index: int in graph.seen.size():
			if is_same(graph.seen[index], value): return {"kind": "node", "index": index}
		if graph.nodes.size() >= LIMIT or value.size() > LIMIT:
			graph["error"] = "REGION_OWNER_LIMIT"
			return {}
		var index: int = graph.nodes.size()
		graph.seen.append(value)
		var node := {"kind": "dictionary" if value is Dictionary else "array", "entries": []}
		graph.nodes.append(node)
		if value is Dictionary:
			for key: Variant in value:
				if key == null or key is Object or key is Dictionary or key is Array or key is Callable or key is Signal or not Checkpoint.supported(key):
					graph["error"] = "INVALID_REGION_OWNER_KEY"
					return {}
				node.entries.append([_encode_bind_roots(key, graph, depth + 1), _encode_bind_roots(value[key], graph, depth + 1)])
		else:
			for entry: Variant in value: node.entries.append(_encode_bind_roots(entry, graph, depth + 1))
		return {"kind": "node", "index": index}
	if not Checkpoint.supported(value):
		graph["error"] = "UNSUPPORTED_REGION_OWNER_VALUE"
		return {}
	return {"kind": "atom", "bytes": Marshalls.raw_to_base64(var_to_bytes(value))}

static func capture_bind_roots(roots: Dictionary, context: Dictionary) -> Dictionary:
	var checked := Checkpoint.validate_context(context)
	if not checked.ok: return checked
	var graph := {"nodes": [], "seen": [], "error": ""}
	var encoded := _encode_bind_roots(roots, graph, 0)
	if not str(graph.error).is_empty(): return Runtime.fail(str(graph.error))
	var snapshot: Dictionary = {"version": VERSION, "context": context.duplicate(true), "root": encoded, "nodes": graph.nodes}
	return Runtime.ok("", {"state": snapshot})

## v1 value/wire descriptors remain validated unchanged; v2 atoms avoid JSON numeric coercion.
static func _valid_atom(value: Dictionary) -> bool:
	if value.size() != 2 or value.get("kind") != "atom" or not value.get("bytes") is String or str(value["bytes"]).length() > 44739244: return false
	var raw: PackedByteArray = Marshalls.base64_to_raw(value["bytes"])
	if raw.size() < 4 or raw.size() > MAX_ATOM_BYTES or Marshalls.raw_to_base64(raw) != value["bytes"]: return false
	var kind: int = int(raw.decode_u32(0)) & 65535
	if kind in [TYPE_OBJECT, TYPE_CALLABLE, TYPE_SIGNAL, TYPE_DICTIONARY, TYPE_ARRAY]: return false
	# The no-object decoder and original supported-value guard both remain mandatory.
	var decoded: Variant = bytes_to_var(raw)
	return not (decoded is Dictionary or decoded is Array or decoded is Object or decoded is Callable or decoded is Signal) \
		and Checkpoint.supported(decoded) and var_to_bytes(decoded) == raw
