// crowd10k GDExtension binding: one Godot class "ArmyCrowd" (RefCounted) owning one wg::World.
//
// Same raw public C interface as native/army_idle (vendored gdextension_interface.h from Godot 4.7.2),
// no godot-cpp. Every call is synchronous on the calling thread; World::step uses the core's own worker
// threads internally and never calls back into Godot. Arguments are Packed arrays or scalars; nothing
// is exchanged per soldier through Variant.
#include "../../army_idle/vendor/gdextension_interface.h"
#include "../src/crowd_core.hpp"
#include "build_id.h"

#include <algorithm>
#include <cmath>
#include <chrono>
#include <cstring>
#include <initializer_list>
#include <memory>
#include <vector>

namespace {

constexpr auto STRING = GDEXTENSION_VARIANT_TYPE_STRING;
constexpr auto NIL = GDEXTENSION_VARIANT_TYPE_NIL;
constexpr auto BOOL = GDEXTENSION_VARIANT_TYPE_BOOL;
constexpr auto INT = GDEXTENSION_VARIANT_TYPE_INT;
constexpr auto FLOAT = GDEXTENSION_VARIANT_TYPE_FLOAT;
constexpr auto BYTES = GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY;
constexpr auto INTS = GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY;
constexpr auto LONGS = GDEXTENSION_VARIANT_TYPE_PACKED_INT64_ARRAY;
constexpr auto FLOATS = GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT32_ARRAY;
constexpr auto DOUBLES = GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT64_ARRAY;
struct alignas(8) TextStorage { unsigned char bytes[8]; };
static_assert(sizeof(void *) == 8, "x64 only");

GDExtensionClassLibraryPtr library;
GDExtensionInterfaceVariantGetType type_of;
GDExtensionInterfaceVariantDestroy destroy;
GDExtensionInterfaceVariantConstruct variant_construct;
GDExtensionInterfaceClassdbConstructObject2 construct_object;
GDExtensionInterfaceObjectSetInstance set_instance;
GDExtensionInterfaceClassdbRegisterExtensionClass4 register_class;
GDExtensionInterfaceClassdbUnregisterExtensionClass unregister_class;
GDExtensionInterfaceClassdbRegisterExtensionClassMethod register_method;
GDExtensionInterfaceStringNameNewWithLatin1Chars make_name;
GDExtensionInterfaceStringNewWithLatin1Chars make_string;
GDExtensionInterfacePackedByteArrayOperatorIndex bytes_write;
GDExtensionInterfacePackedByteArrayOperatorIndexConst bytes_read;
GDExtensionInterfacePackedInt32ArrayOperatorIndexConst ints_read;
GDExtensionInterfacePackedInt32ArrayOperatorIndex ints_write;
GDExtensionInterfacePackedFloat32ArrayOperatorIndexConst floats_read;
GDExtensionInterfacePackedInt64ArrayOperatorIndex longs_write;
GDExtensionInterfacePackedInt64ArrayOperatorIndexConst longs_read;
GDExtensionInterfacePackedFloat32ArrayOperatorIndex floats_write;
GDExtensionInterfacePackedFloat64ArrayOperatorIndex doubles_write;
GDExtensionInterfacePackedFloat64ArrayOperatorIndexConst doubles_read;
GDExtensionVariantGetInternalPtrFunc internal[GDEXTENSION_VARIANT_TYPE_VARIANT_MAX];
GDExtensionVariantFromTypeConstructorFunc from_int, from_float, from_bool, from_string;
GDExtensionPtrDestructor destroy_string, destroy_name;
GDExtensionPtrBuiltInMethod size_bytes, size_ints, size_longs, size_floats, size_doubles, resize_bytes, resize_ints, resize_longs, resize_floats, resize_doubles;
TextStorage class_name, parent_name, empty_name, empty_string;

struct Crowd {
	std::unique_ptr<wg::World> w;
	std::vector<float> render, rows, bounds;
	std::vector<int32_t> spans;
	double last_rows_ms = 0;
	double last_step_ms = 0, last_pack_ms = 0;
};

// ---------------------------------------------------------------- variant helpers
int64_t packed_size(GDExtensionPtrBuiltInMethod m, void *v) { int64_t n = 0; m(v, nullptr, &n, 0); return n; }
void packed_resize(GDExtensionPtrBuiltInMethod m, void *v, int64_t n) { const void *a[] = {&n}; int64_t e = 0; m(v, a, &e, 1); }
void reset(void *v, GDExtensionVariantType t) { destroy(v); GDExtensionCallError e{}; variant_construct(t, v, nullptr, 0, &e); }
bool arg_int(const void *v, int64_t &out) {
	auto t = type_of(const_cast<void *>(v));
	if (t == INT) { out = *static_cast<int64_t *>(internal[INT](const_cast<void *>(v))); return true; }
	if (t == BOOL) { out = *static_cast<GDExtensionBool *>(internal[BOOL](const_cast<void *>(v))) ? 1 : 0; return true; }
	return false;
}
bool arg_num(const void *v, double &out) {
	auto t = type_of(const_cast<void *>(v));
	if (t == FLOAT) { out = *static_cast<double *>(internal[FLOAT](const_cast<void *>(v))); return true; }
	if (t == INT) { out = (double)*static_cast<int64_t *>(internal[INT](const_cast<void *>(v))); return true; }
	return false;
}
void *arg_packed(const void *v, GDExtensionVariantType t) {
	if (type_of(const_cast<void *>(v)) != t) return nullptr;
	return internal[t](const_cast<void *>(v));
}
void ret_int(void *r, int64_t v) { destroy(r); from_int(r, &v); }
void ret_bool(void *r, bool v) { GDExtensionBool b = v; destroy(r); from_bool(r, &b); }
void ret_float(void *r, double v) { destroy(r); from_float(r, &v); }
void bad_args(GDExtensionCallError *e, int expected) { *e = {GDEXTENSION_CALL_ERROR_INVALID_ARGUMENT, 0, expected}; }

#define CALL_ARGS void *, GDExtensionClassInstancePtr inst, const GDExtensionConstVariantPtr *a, GDExtensionInt n, GDExtensionVariantPtr r, GDExtensionCallError *e
#define SELF auto *self = static_cast<Crowd *>(inst); *e = {GDEXTENSION_CALL_OK, 0, 0}; (void)a
#define NEED(k) if (n != (k)) { *e = {n < (k) ? GDEXTENSION_CALL_ERROR_TOO_FEW_ARGUMENTS : GDEXTENSION_CALL_ERROR_TOO_MANY_ARGUMENTS, 0, (k)}; return; }
#define WORLD if (!self->w) { ret_bool(r, false); return; } wg::World &w = *self->w

// ---------------------------------------------------------------- methods
// setup(threads: int, seed: int) -> bool : a fresh World (discards the previous one)
void m_setup(CALL_ARGS) {
	SELF; NEED(2);
	int64_t threads, seed;
	if (!arg_int(a[0], threads) || !arg_int(a[1], seed)) return bad_args(e, 0);
	self->w = std::make_unique<wg::World>((int)std::clamp<int64_t>(threads, 1, 64));
	self->w->cfg.seed = seed;
	ret_bool(r, true);
}
// set_terrain(w, h, height_levels, flags, ramp_edges, static_blocked, facility) -> bool
// TerrainData layout; static_blocked / facility may be empty.
void m_set_terrain(CALL_ARGS) {
	SELF; NEED(7); WORLD;
	int64_t W, H;
	if (!arg_int(a[0], W) || !arg_int(a[1], H) || W <= 0 || H <= 0 || W > 1024 || H > 1024) return bad_args(e, 0);
	void *p[5];
	for (int k = 0; k < 5; ++k) if (!(p[k] = arg_packed(a[2 + k], BYTES))) return bad_args(e, 2 + k);
	const int64_t cells = W * H;
	for (int k = 0; k < 3; ++k) if (packed_size(size_bytes, p[k]) != cells) { ret_bool(r, false); return; }
	for (int k = 3; k < 5; ++k) { int64_t s = packed_size(size_bytes, p[k]); if (s != 0 && s != cells) { ret_bool(r, false); return; } }
	wg::Terrain t;
	t.allocate((int)W, (int)H);
	std::memcpy(t.height.data(), bytes_read(p[0], 0), (size_t)cells);
	std::memcpy(t.flags.data(), bytes_read(p[1], 0), (size_t)cells);
	std::memcpy(t.ramp_edges.data(), bytes_read(p[2], 0), (size_t)cells);
	if (packed_size(size_bytes, p[3])) std::memcpy(t.static_blocked.data(), bytes_read(p[3], 0), (size_t)cells);
	if (packed_size(size_bytes, p[4])) std::memcpy(t.facility.data(), bytes_read(p[4], 0), (size_t)cells);
	t.base_height = w.terrain.base_height.size() == (size_t)cells ? w.terrain.base_height : t.height;
	ret_bool(r, w.update_terrain(std::move(t)));
}
void m_set_natural_heights(CALL_ARGS) {
	SELF; NEED(1); WORLD;
	void *p = arg_packed(a[0], BYTES);
	if (!p) return bad_args(e, 0);
	const int64_t count = (int64_t)w.terrain.w * w.terrain.h;
	if (packed_size(size_bytes, p) != count) { ret_bool(r, false); return; }
	w.terrain.base_height.assign(bytes_read(p, 0), bytes_read(p, 0) + count);
	ret_bool(r, true);
}
void m_terrain_state(CALL_ARGS) {
	SELF; NEED(0); WORLD;
	auto data = w.terrain_state();
	reset(r, BYTES); void *buf = internal[BYTES](r);
	packed_resize(resize_bytes, buf, (int64_t)data.size());
	if (!data.empty()) std::memcpy(bytes_write(buf, 0), data.data(), data.size());
}
void m_occupancy_mask(CALL_ARGS) {
	SELF; NEED(1); WORLD;
	void *p = arg_packed(a[0], LONGS);
	if (!p) return bad_args(e, 0);
	std::vector<int64_t> ignored;
	for (int64_t k = 0; k < packed_size(size_longs, p); ++k) ignored.push_back(*longs_read(p, k));
	auto data = w.occupancy_mask(ignored);
	reset(r, BYTES); void *buf = internal[BYTES](r);
	packed_resize(resize_bytes, buf, (int64_t)data.size());
	if (!data.empty()) std::memcpy(bytes_write(buf, 0), data.data(), data.size());
}
void m_charge_custody_work(CALL_ARGS) {
	SELF; NEED(2); WORLD; int64_t i; double seconds;
	if (!arg_int(a[0], i) || !arg_num(a[1], seconds)) return bad_args(e, 0);
	ret_bool(r, w.charge_custody_work((int)i, seconds));
}
void m_begin_structure_strike(CALL_ARGS) {
	SELF; NEED(2); WORLD; int64_t i, cell;
	if (!arg_int(a[0], i) || !arg_int(a[1], cell)) return bad_args(e, 0);
	ret_bool(r, w.begin_structure_strike((int)i, (int)cell));
}
// add_formation(team, cx, cy, facing, cols, spacing, troop, training) -> int
void m_add_formation(CALL_ARGS) {
	SELF; NEED(8); WORLD;
	int64_t team, cols, troop; double cx, cy, facing, spacing, training;
	if (!arg_int(a[0], team) || !arg_num(a[1], cx) || !arg_num(a[2], cy) || !arg_num(a[3], facing) || !arg_int(a[4], cols) ||
	    !arg_num(a[5], spacing) || !arg_int(a[6], troop) || !arg_num(a[7], training) || team < 0 || team > 255 || troop < 0 || troop > 2)
		return bad_args(e, 0);
	ret_int(r, w.add_formation((int)team, (float)cx, (float)cy, (float)facing, (int)std::max<int64_t>(1, cols), (float)spacing, (wg::Troop)troop, training));
}
// add_soldiers(formation, person_ids: PackedInt64Array, equip: PackedInt32Array, roles: PackedByteArray, ammo: PackedInt32Array) -> int
// equip = family | material << 8 | armor << 16 | shield << 24. Returns the first soldier index, -1 on bad input.
void m_add_soldiers(CALL_ARGS) {
	SELF; NEED(5); WORLD;
	int64_t f;
	if (!arg_int(a[0], f)) return bad_args(e, 0);
	void *ids = arg_packed(a[1], LONGS), *eq = arg_packed(a[2], INTS), *roles = arg_packed(a[3], BYTES), *ammo = arg_packed(a[4], INTS);
	if (!ids || !eq || !roles || !ammo) return bad_args(e, 1);
	const int64_t m = packed_size(size_longs, ids);
	if (f < 0 || f >= (int64_t)w.formations.size() || m <= 0 || packed_size(size_ints, eq) != m || packed_size(size_bytes, roles) != m ||
	    packed_size(size_ints, ammo) != m) { ret_int(r, -1); return; }
	int first = -1;
	for (int64_t k = 0; k < m; ++k) {
		int32_t code = *ints_read(eq, k);
		wg::rules::Equip q;
		q.family = (uint8_t)(code & 255); q.material = (uint8_t)((code >> 8) & 255); q.armor = (uint8_t)((code >> 16) & 255); q.shield = ((code >> 24) & 1) != 0;
		uint8_t role = *bytes_read(roles, k);
		int32_t am = std::clamp(*ints_read(ammo, k), 0, 65535);
		int i = w.add_soldier((int)f, q, (wg::Role)std::min<uint8_t>(role, 2), *longs_read(ids, k), (uint16_t)am);
		if (first < 0) first = i;
	}
	ret_int(r, first);
}
void m_finalize(CALL_ARGS) { SELF; NEED(0); WORLD; w.finalize(); ret_bool(r, true); }
// set_hostile(faction_a, faction_b, hostile: bool)
void m_set_hostile(CALL_ARGS) {
	SELF; NEED(3); WORLD; int64_t x, y, h;
	if (!arg_int(a[0], x) || !arg_int(a[1], y) || !arg_int(a[2], h)) return bad_args(e, 0);
	w.set_hostile((int)x, (int)y, h != 0); ret_bool(r, true);
}
// set_order_owner(formation, ai_owned: bool)
void m_set_owner(CALL_ARGS) {
	SELF; NEED(2); WORLD; int64_t f, o;
	if (!arg_int(a[0], f) || !arg_int(a[1], o) || f < 0 || f >= (int64_t)w.formations.size()) return bad_args(e, 0);
	if ((w.formations[f].no_orders || w.formations[f].garrisoned) && o) { ret_bool(r,false); return; }
	w.formations[f].ai_enabled = o != 0; ret_bool(r, true);
}
// set_ai(enabled: bool)
void m_set_ai(CALL_ARGS) { SELF; NEED(1); WORLD; int64_t v; if (!arg_int(a[0], v)) return bad_args(e, 0); w.cfg.ai = v != 0; ret_bool(r, true); }
// order: existing public kinds HOLD0 MOVE1 ATTACK2 RETREAT3 PURSUE4; CAV-4a kinds CHARGE-to-point5 (gx, gy), RALLY6,
// CHARGE-to-enemy-formation7 (x = formation index); exact result codes 0..10 (9 NO_COMMANDER, 10 NOT_CAVALRY).
void m_order(CALL_ARGS) {
	SELF; NEED(5); if (!self->w) { ret_int(r, wg::BAD_FORMATION); return; } auto &w=*self->w;
	int64_t f,kind; double gx,gy,x;
	if (!arg_int(a[0],f) || !arg_int(a[1],kind) || !arg_num(a[2],gx) || !arg_num(a[3],gy) || !arg_num(a[4],x)) { ret_int(r,wg::BAD_ARGS); return; }
	if(f<0 || f>=(int64_t)w.formations.size()) { ret_int(r,wg::BAD_FORMATION); return; }
	ret_int(r,w.host_order((int)f,kind<0 || kind>7 ? -1 : (int)kind,(float)gx,(float)gy,x));
}
// step(dt) : internal Site clock. step_clock(dt, game_seconds, combat_left) : host clock.
void m_step(CALL_ARGS) {
	SELF; NEED(1); WORLD; double dt;
	if (!arg_num(a[0], dt) || !(dt > 0 && dt < 1)) return bad_args(e, 0);
	auto t0 = std::chrono::steady_clock::now();
	const bool ok = w.step((float)dt);
	self->last_step_ms = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count();
	ret_bool(r, ok);
}
void m_step_clock(CALL_ARGS) {
	SELF; NEED(3); WORLD; double dt, gs, cl;
	if (!arg_num(a[0], dt) || !arg_num(a[1], gs) || !arg_num(a[2], cl) || !(dt > 0 && dt < 1)) return bad_args(e, 0);
	auto t0 = std::chrono::steady_clock::now();
	const bool ok = w.step_clock((float)dt, gs, cl);
	self->last_step_ms = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count();
	ret_bool(r, ok);
}
// pack_render(cell_pixels, capacity) -> PackedFloat32Array of capacity * 12 floats (2D MultiMesh, transform + custom),
// living soldiers y-sorted first, the rest zero (invisible). custom = (state, frame 0-7, faction, direction 0-7).
void m_pack(CALL_ARGS) {
	SELF; NEED(2); WORLD; double px; int64_t cap;
	if (!arg_num(a[0], px) || !arg_int(a[1], cap) || cap < 0 || cap > 200000) return bad_args(e, 0);
	auto t0 = std::chrono::steady_clock::now();
	int m = w.pack_render(self->render, (float)px);
	reset(r, FLOATS);
	void *buf = internal[FLOATS](r);
	packed_resize(resize_floats, buf, cap * 12);
	if (cap > 0) {
		float *dst = floats_write(buf, 0);
		size_t live = (size_t)std::min<int64_t>(m, cap) * 12;
		std::memcpy(dst, self->render.data(), live * sizeof(float));
		std::memset(dst + live, 0, ((size_t)cap * 12 - live) * sizeof(float));
	}
	self->last_pack_ms = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count();
}
// Original 4-INT event packet: kind, person, other person, formation.
void pack_events(const wg::World &w, void *r) {
	reset(r, LONGS);
	void *buf = internal[LONGS](r);
	packed_resize(resize_longs, buf, (int64_t)w.events.size() * 4);
	for (size_t k = 0; k < w.events.size(); ++k) {
		const wg::Event &v = w.events[k];
		*longs_write(buf, (int64_t)k * 4 + 0) = v.kind;
		*longs_write(buf, (int64_t)k * 4 + 1) = v.person;
		*longs_write(buf, (int64_t)k * 4 + 2) = v.other;
		*longs_write(buf, (int64_t)k * 4 + 3) = v.formation;
	}
}
void m_peek_events(CALL_ARGS) {
	SELF; NEED(0); WORLD;
	pack_events(w, r); // Pure read; no measure(), step or queue mutation.
}
void m_event_fatigue(CALL_ARGS) {
	SELF; NEED(0); WORLD;
	reset(r, DOUBLES);
	void *buf = internal[DOUBLES](r);
	packed_resize(resize_doubles, buf, (int64_t)w.events.size() * 2);
	for (size_t k = 0; k < w.events.size(); ++k) {
		*doubles_write(buf, (int64_t)k * 2) = w.events[k].fatigue;
		*doubles_write(buf, (int64_t)k * 2 + 1) = w.events[k].fatigue_rest;
	}
}
// drain_events() keeps the existing 4-INT ABI and queue-clearing semantics.
void m_events(CALL_ARGS) {
	SELF; NEED(0); WORLD;
	if (w.work_point_state()[0]!=0) { reset(r,LONGS); return; } // Original point receipts are not final yet.
	pack_events(w, r);
	w.events.clear();
}
// stats() -> PackedFloat64Array (layout: see STAT_NAMES in the GDScript side)
void m_stats(CALL_ARGS) {
	SELF; NEED(0); WORLD;
	w.measure();
	const wg::Stats &s = w.stats;
	const wg::PhaseTimes &p = w.last;
	int routed = 0; for (auto &f : w.formations) routed += f.routed ? 1 : 0;
	const double v[] = {
		(double)w.soldier_count(), (double)s.alive, (double)s.down, (double)s.captive, (double)s.fighting, (double)s.engaging, (double)routed,
		(double)s.deaths, (double)s.bled_deaths, (double)s.kos, (double)s.pairs, (double)s.shots, (double)s.rescues_done, (double)s.captures_done,
		(double)s.illegal_cell, (double)s.illegal_step, (double)s.cooldown_violations, (double)s.deep_overlap_pairs,
		self->last_step_ms, self->last_pack_ms, p.hash, p.fields, p.command, p.ai, p.formation, p.contact, p.soldier, p.timers,
		p.exchange, p.ranged, p.actions, p.fatigue, p.compact, w.combat_left, w.game_dt, w.time, (double)w.tick,
		(double)s.routs, (double)s.escapes, (double)s.wakes};
	reset(r, DOUBLES);
	void *buf = internal[DOUBLES](r);
	const int64_t cnt = (int64_t)(sizeof(v) / sizeof(v[0]));
	packed_resize(resize_doubles, buf, cnt);
	std::memcpy(doubles_write(buf, 0), v, sizeof(v));
}
// Panel-only counts. Keep stats() as the explicit spatial/overlap diagnostic.
// This query reads the same live fields as measure(), without changing scratch or counters.
void m_hud_stats(CALL_ARGS) {
	SELF; NEED(0); WORLD;
	int alive = 0, down = 0, captive = 0;
	for (int i = 0; i < w.soldier_count(); ++i) {
		if (!w.alive(i)) continue;
		++alive;
		if (w.ko[i] > 0) ++down;
		if (w.captive[i]) ++captive;
	}
	const double v[] = {double(w.soldier_count()), double(alive), double(down), double(w.stats.deaths),
		double(captive), double(w.stats.pairs), double(w.stats.illegal_cell), double(w.stats.illegal_step)};
	reset(r, DOUBLES);
	void *buf = internal[DOUBLES](r);
	packed_resize(resize_doubles, buf, 8);
	std::memcpy(doubles_write(buf, 0), v, sizeof(v));
}
void m_count(CALL_ARGS) { SELF; NEED(0); WORLD; ret_int(r, w.soldier_count()); }
void m_hash(CALL_ARGS) { SELF; NEED(0); WORLD; ret_int(r, (int64_t)w.state_hash()); }
// save() -> PackedByteArray ; load(bytes) -> bool
void m_save(CALL_ARGS) {
	SELF; NEED(0); WORLD;
	std::vector<uint8_t> b = w.save();
	reset(r, BYTES);
	void *buf = internal[BYTES](r);
	packed_resize(resize_bytes, buf, (int64_t)b.size());
	if (!b.empty()) std::memcpy(bytes_write(buf, 0), b.data(), b.size());
}
void m_load(CALL_ARGS) {
	SELF; NEED(1);
	void *p = arg_packed(a[0], BYTES);
	if (!p) return bad_args(e, 0);
	if (!self->w) self->w = std::make_unique<wg::World>(4);
	int64_t sz = packed_size(size_bytes, p);
	if (sz <= 0 || sz > 16 * 1024 * 1024) { ret_bool(r,false); return; }
	std::vector<uint8_t> b((size_t)sz);
	if (sz) std::memcpy(b.data(), bytes_read(p, 0), (size_t)sz);
	ret_bool(r, self->w->load(b));
}

// ---------------------------------------------------------------- atlas presentation (P2b)
void m_load_with_siege_navigation(CALL_ARGS) {
	SELF; NEED(3);
	void *bytes = arg_packed(a[0], BYTES), *blocked = arg_packed(a[1], INTS), *exits = arg_packed(a[2], LONGS);
	if (!bytes || !blocked || !exits) { ret_bool(r, false); return; }
	const int64_t size = packed_size(size_bytes, bytes), count = packed_size(size_ints, blocked), extra = packed_size(size_longs, exits);
	if (size <= 0 || size > 16 * 1024 * 1024 || count < 0 || count > 1024 * 1024 || extra < 0 || extra % 3 || extra > int64_t(65536) * 64 * 3) { ret_bool(r, false); return; }
	std::vector<uint8_t> blob((size_t)size); std::memcpy(blob.data(), bytes_read(bytes, 0), (size_t)size);
	std::vector<int> cells; if (count) cells.assign(ints_read(blocked, 0), ints_read(blocked, 0) + count);
	std::vector<int64_t> people; if (extra) people.assign(longs_read(exits, 0), longs_read(exits, 0) + extra);
	if (!self->w) self->w = std::make_unique<wg::World>(4);
	ret_bool(r, self->w->load(blob, cells, people));
}

void m_render_clear(CALL_ARGS) { SELF; NEED(0); WORLD; w.render_tracks.clear(); w.render_kits.clear(); ret_bool(r, true); }
// render_add_track(sequence, duration, loop, times: PackedFloat32Array, anchors_xy: PackedFloat32Array, map: PackedFloat32Array, map_step) -> int
void m_render_add_track(CALL_ARGS) {
	SELF; NEED(7); WORLD;
	int64_t seq, loop; double dur, step;
	if (!arg_int(a[0], seq) || !arg_num(a[1], dur) || !arg_int(a[2], loop) || !arg_num(a[6], step)) return bad_args(e, 0);
	void *times = arg_packed(a[3], FLOATS), *anch = arg_packed(a[4], FLOATS), *map = arg_packed(a[5], FLOATS);
	if (!times || !anch || !map) return bad_args(e, 3);
	const int64_t nt = packed_size(size_floats, times);
	if (nt <= 0 || nt > 256 || packed_size(size_floats, anch) != nt * 2) { ret_int(r, -1); return; }
	wg::RenderTrack t;
	t.sequence = (int)seq; t.duration = (float)dur; t.loop = loop != 0; t.map_step = (float)step;
	const float *pt = floats_read(times, 0), *pa = floats_read(anch, 0);
	for (int64_t k = 0; k < nt; ++k) { t.times.push_back(pt[k]); t.ax.push_back(pa[2 * k]); t.ay.push_back(pa[2 * k + 1]); }
	const int64_t nm = packed_size(size_floats, map);
	if (nm > 0) { const float *pm = floats_read(map, 0); t.map.assign(pm, pm + nm); }
	w.render_tracks.push_back(std::move(t));
	ret_int(r, (int64_t)w.render_tracks.size() - 1);
}
// render_add_kit(page, palette, scale, tracks: PackedInt32Array(V_COUNT * 4: slot-major, dirs up/right/down/left)) -> int
void m_render_add_kit(CALL_ARGS) {
	SELF; NEED(4); WORLD;
	int64_t page, pal; double scale;
	if (!arg_int(a[0], page) || !arg_int(a[1], pal) || !arg_num(a[2], scale)) return bad_args(e, 0);
	void *tr = arg_packed(a[3], INTS);
	if (!tr || packed_size(size_ints, tr) != wg::V_COUNT * 4) { ret_int(r, -1); return; }
	wg::RenderKit k;
	k.page = (int)page; k.palette = (int)pal; k.scale = (float)scale;
	for (int s = 0; s < wg::V_COUNT; ++s)
		for (int d = 0; d < 4; ++d) {
			int v = *ints_read(tr, s * 4 + d);
			k.track[s][d] = (v >= 0 && v < (int)w.render_tracks.size()) ? v : -1;
		}
	w.render_kits.push_back(k);
	ret_int(r, (int64_t)w.render_kits.size() - 1);
}
// render_set_kits(kits: PackedInt32Array, one per soldier; -1 = not drawn)
void m_render_set_kits(CALL_ARGS) {
	SELF; NEED(1); WORLD;
	void *k = arg_packed(a[0], INTS);
	if (!k || packed_size(size_ints, k) != w.soldier_count()) { ret_bool(r, false); return; }
	for (int i = 0; i < w.soldier_count(); ++i) w.kit[i] = (int16_t)std::clamp(*ints_read(k, i), -1, 32767);
	ret_bool(r, true);
}
// render_set_windows(PackedFloat32Array V_COUNT action seconds per visual slot)
void m_render_set_windows(CALL_ARGS) {
	SELF; NEED(1); WORLD;
	void *v = arg_packed(a[0], FLOATS);
	if (!v || packed_size(size_floats, v) != wg::V_COUNT) { ret_bool(r, false); return; }
	for (int s = 0; s < wg::V_COUNT; ++s) w.vis_window[s] = *floats_read(v, s);
	ret_bool(r, true);
}
// pack_rows(cell_pixels) -> PackedFloat32Array in draw order, groups padded to capacity; then row_spans()
// (stride 6: row, page or -1 for an actor, start or actor index, count, capacity, group key) / row_bounds()
void m_pack_rows(CALL_ARGS) {
	SELF; NEED(1); WORLD; double px;
	if (!arg_num(a[0], px)) return bad_args(e, 0);
	auto t0 = std::chrono::steady_clock::now();
	w.pack_rows(self->rows, self->spans, self->bounds, (float)px);
	reset(r, FLOATS);
	void *buf = internal[FLOATS](r);
	packed_resize(resize_floats, buf, (int64_t)self->rows.size());
	if (!self->rows.empty()) std::memcpy(floats_write(buf, 0), self->rows.data(), self->rows.size() * sizeof(float));
	self->last_rows_ms = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count();
}
// pack_frame(cell_pixels, frame_seconds): pack_rows with the host's frame time driving the presentation
// filter (smoothing of drawn positions, pose and direction hysteresis) at the screen's rate
void m_pack_frame(CALL_ARGS) {
	SELF; NEED(2); WORLD; double px, dt;
	if (!arg_num(a[0], px) || !arg_num(a[1], dt)) return bad_args(e, 0);
	auto t0 = std::chrono::steady_clock::now();
	w.render_frame_dt = (float)std::max(0.0, dt);
	w.pack_rows(self->rows, self->spans, self->bounds, (float)px);
	reset(r, FLOATS);
	void *buf = internal[FLOATS](r);
	packed_resize(resize_floats, buf, (int64_t)self->rows.size());
	if (!self->rows.empty()) std::memcpy(floats_write(buf, 0), self->rows.data(), self->rows.size() * sizeof(float));
	self->last_rows_ms = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count();
}
// render_set_filter(bool): presentation filter on (default) / off (raw simulated positions and poses)
void m_render_set_filter(CALL_ARGS) {
	SELF; NEED(1); WORLD; int64_t on;
	if (!arg_int(a[0], on)) return bad_args(e, 0);
	w.render_filter = on != 0;
	ret_bool(r, true);
}
void m_row_spans(CALL_ARGS) {
	SELF; NEED(0); WORLD; (void)w;
	reset(r, INTS);
	void *buf = internal[INTS](r);
	packed_resize(resize_ints, buf, (int64_t)self->spans.size());
	if (!self->spans.empty()) std::memcpy(ints_write(buf, 0), self->spans.data(), self->spans.size() * sizeof(int32_t));
}
void m_row_bounds(CALL_ARGS) {
	SELF; NEED(0); WORLD; (void)w;
	reset(r, FLOATS);
	void *buf = internal[FLOATS](r);
	packed_resize(resize_floats, buf, (int64_t)self->bounds.size());
	if (!self->bounds.empty()) std::memcpy(floats_write(buf, 0), self->bounds.data(), self->bounds.size() * sizeof(float));
}
// row_grounds() -> PackedFloat32Array: ground x, y per packed slot of the last pack_rows (verification only)
void m_row_grounds(CALL_ARGS) {
	SELF; NEED(0); WORLD;
	reset(r, FLOATS);
	void *buf = internal[FLOATS](r);
	packed_resize(resize_floats, buf, (int64_t)w.render_grounds.size());
	if (!w.render_grounds.empty()) std::memcpy(floats_write(buf, 0), w.render_grounds.data(), w.render_grounds.size() * sizeof(float));
}
// render_set_actors(PackedFloat32Array ground x, y in pixels per host actor: player, live captain Sprites)
void m_render_set_actors(CALL_ARGS) {
	SELF; NEED(1); WORLD;
	void *v = arg_packed(a[0], FLOATS);
	if (!v) return bad_args(e, 0);
	const int64_t k = packed_size(size_floats, v);
	if (k % 2 != 0 || k > 2 * 4096) { ret_bool(r, false); return; }
	w.render_actors.assign((size_t)k, 0.f);
	if (k) std::memcpy(w.render_actors.data(), floats_read(v, 0), (size_t)k * sizeof(float));
	ret_bool(r, true);
}
// render_set_bands(int 1..15): ground-y slices per 64-px row (1 = one group per (row, page) like P2b)
void m_render_set_bands(CALL_ARGS) {
	SELF; NEED(1); WORLD; int64_t b;
	if (!arg_int(a[0], b)) return bad_args(e, 0);
	if (b < 1 || b > 15) { ret_bool(r, false); return; }
	w.render_bands = (int)b;
	ret_bool(r, true);
}
// set_blockers(PackedFloat32Array x, y, radius triples in cells): host blockers for the next steps
void m_set_blockers(CALL_ARGS) {
	SELF; NEED(1); WORLD;
	void *v = arg_packed(a[0], FLOATS);
	if (!v) return bad_args(e, 0);
	const int64_t k = packed_size(size_floats, v);
	if (k % 3 != 0 || k > 3 * 1024) { ret_bool(r, false); return; }
	w.blockers.clear();
	for (int64_t q = 0; q < k; q += 3) {
		const float x = *floats_read(v, q), y = *floats_read(v, q + 1), rad = *floats_read(v, q + 2);
		if (!std::isfinite(x) || !std::isfinite(y) || !(rad > 0.f) || rad > 8.f) { w.blockers.clear(); ret_bool(r, false); return; }
		w.blockers.push_back({x, y, rad});
	}
	ret_bool(r, true);
}
// standing_near(x, y, r) -> int: conscious, free soldiers within r cells (the host's cell_blocker query)
void m_standing_near(CALL_ARGS) {
	SELF; NEED(3); WORLD; double x, y, rad;
	if (!arg_num(a[0], x) || !arg_num(a[1], y) || !arg_num(a[2], rad)) return bad_args(e, 0);
	ret_int(r, w.standing_near((float)x, (float)y, (float)rad));
}
// set_host_control(soldier, bool): the player is this crowd soldier; his wishes come from host_input
void m_set_host_control(CALL_ARGS) {
	SELF; NEED(2); WORLD; int64_t i, on;
	if (!arg_int(a[0], i) || !arg_int(a[1], on)) return bad_args(e, 0);
	if (i < 0 || i >= w.soldier_count()) { ret_bool(r, false); return; }
	w.set_host_control((int)i, on != 0);
	ret_bool(r, true);
}
// host_input(soldier, wish_vx, wish_vy (cells / s), run, engage)
void m_host_input(CALL_ARGS) {
	SELF; NEED(5); WORLD; int64_t i, run, eng; double vx, vy;
	if (!arg_int(a[0], i) || !arg_num(a[1], vx) || !arg_num(a[2], vy) || !arg_int(a[3], run) || !arg_int(a[4], eng)) return bad_args(e, 0);
	if (i < 0 || i >= w.soldier_count() || !w.host_ctl[(size_t)i]) { ret_bool(r, false); return; }
	w.host_input((int)i, (float)vx, (float)vy, run != 0, eng != 0);
	ret_bool(r, true);
}
// soldier_view(soldier) -> PackedFloat32Array: drawn ground x, y (pixels, after the presentation filter of
// the last pack), shown direction (0 up, 1 right, 2 down, 3 left), visual slot, slot age (s), hp, ko,
// state, captive, simulated x, y (cells), face (rad), melee target (-1 none), faction, stun
void m_soldier_view(CALL_ARGS) {
	SELF; NEED(1); WORLD; int64_t i;
	if (!arg_int(a[0], i)) return bad_args(e, 0);
	reset(r, FLOATS);
	if (i < 0 || i >= w.soldier_count()) return;
	void *buf = internal[FLOATS](r);
	packed_resize(resize_floats, buf, 15);
	const size_t k = (size_t)i;
	const bool have = k < w.pres.size() && w.pres[k].ok;
	const float v[15] = {have ? w.pres[k].x : 0.f, have ? w.pres[k].y : 0.f, have ? (float)w.pres[k].shown_dir : 2.f,
		have ? (float)w.pres[k].slot : 0.f, have ? w.pres[k].age : 0.f, (float)w.hp[k], (float)w.ko[k], (float)w.state[k],
		(float)w.captive[k], w.px[k], w.py[k], w.face[k], (float)w.target[k], (float)w.team[k], (float)w.stun[k]};
	std::memcpy(floats_write(buf, 0), v, sizeof(v));
}
// nearest_enemy(soldier, radius) -> int: nearest able hostile soldier within radius cells, -1 if none
void m_nearest_enemy(CALL_ARGS) {
	SELF; NEED(2); WORLD; int64_t i; double rad;
	if (!arg_int(a[0], i) || !arg_num(a[1], rad)) return bad_args(e, 0);
	ret_int(r, w.nearest_hostile((int)i, (float)rad));
}
// combat_mark() -> float: the largest combat_event duration raised by the last step (host clock: forward it
// to SiteRuntime.mark_combat)
void m_combat_mark(CALL_ARGS) { SELF; NEED(0); WORLD; double m = w.combat_mark; destroy(r); from_float(r, &m); }
// set_start_positions(first_soldier, PackedFloat32Array x, y in cells): where soldiers stand at finalize
// (the Site's deployment cells); call before finalize
void m_set_start_positions(CALL_ARGS) {
	SELF; NEED(2); WORLD; int64_t first;
	if (!arg_int(a[0], first)) return bad_args(e, 0);
	void *v = arg_packed(a[1], FLOATS);
	if (!v) return bad_args(e, 1);
	const int64_t k = packed_size(size_floats, v);
	if (first < 0 || k % 2 != 0 || first + k / 2 > w.soldier_count()) { ret_bool(r, false); return; }
	for (int64_t q = 0; q < k / 2; ++q) {
		w.start_x[(size_t)(first + q)] = *floats_read(v, 2 * q);
		w.start_y[(size_t)(first + q)] = *floats_read(v, 2 * q + 1);
	}
	ret_bool(r, true);
}
void m_rows_ms(CALL_ARGS) { SELF; NEED(0); WORLD; (void)w; destroy(r); from_float(r, &self->last_rows_ms); }

// C2/C3 state boundary: scalar data in doubles; all identities stay int64.
void return_doubles(void *r, const std::vector<double> &v) {
	reset(r,DOUBLES); void *buf=internal[DOUBLES](r); packed_resize(resize_doubles,buf,(int64_t)v.size());
	if(!v.empty()) std::memcpy(doubles_write(buf,0),v.data(),v.size()*sizeof(double));
}
void return_longs(void *r, const std::vector<int64_t> &v) {
	reset(r,LONGS); void *buf=internal[LONGS](r); packed_resize(resize_longs,buf,(int64_t)v.size());
	if(!v.empty()) std::memcpy(longs_write(buf,0),v.data(),v.size()*sizeof(int64_t));
}
void m_get_soldier_state(CALL_ARGS) {
	SELF; NEED(1); WORLD; int64_t i;
	if(!arg_int(a[0],i) || i<0 || i>=w.soldier_count()) { return_doubles(r,{}); return; }
	auto v=w.get_soldier_state((int)i);
	return_doubles(r,{v.hp,v.stun,v.grace,v.ko,v.getup,v.stagger,double(v.captive),double(v.bandaged),double(v.ammo),double(v.tactics),double(v.leadership),double(v.coach),v.escape_t,double(v.role),v.x,v.y,v.facing,v.exch_cd,v.ranged_cd,v.skill_cd,v.knock_t,v.act_t,w.vx[i],w.vy[i],double(w.state[i]),double(w.vis_kind[i]),std::max(0.0,w.time-w.vis_t0[i])});
}
// Native-index order, three doubles per person: hp, ko, captive. No retained host copy.
void m_get_life_states(CALL_ARGS) {
	SELF; NEED(0); WORLD;
	reset(r, DOUBLES);
	void *buf = internal[DOUBLES](r);
	const int count = w.soldier_count();
	packed_resize(resize_doubles, buf, int64_t(count) * 3);
	if (!count) return;
	double *dst = doubles_write(buf, 0);
	for (int i = 0; i < count; ++i) {
		dst[i * 3] = w.hp[i];
		dst[i * 3 + 1] = w.ko[i];
		dst[i * 3 + 2] = double(w.captive[i]);
	}
}
void m_soldier_refs(CALL_ARGS) {
	SELF; NEED(1); WORLD; int64_t i;
	if(!arg_int(a[0],i) || i<0 || i>=w.soldier_count()) { return_longs(r,{}); return; }
	return_longs(r,{w.person_id[i],w.get_soldier_state((int)i).captor_person,w.prison_id[i]});
}
void m_set_soldier_state(CALL_ARGS) {
	SELF; NEED(3); WORLD; int64_t i;
	void *data=arg_packed(a[1],DOUBLES),*refs=arg_packed(a[2],LONGS);
	if(!arg_int(a[0],i) || i<0 || i>=w.soldier_count() || !data || !refs || packed_size(size_doubles,data)<22 || (packed_size(size_longs,refs)!=2 && packed_size(size_longs,refs)!=3)) { ret_bool(r,false); return; }
	const double *v=doubles_read(data,0); const int64_t *ids=longs_read(refs,0);
	for(int k=0;k<22;++k) if(!std::isfinite(v[k])) { ret_bool(r,false); return; }
	if(ids[0]!=w.person_id[i] || (ids[1]!=-1 && w.soldier_index(ids[1])<0)) { ret_bool(r,false); return; }
	const int64_t prison = packed_size(size_longs,refs) == 3 ? ids[2] : w.prison_id[i];
	if(prison<0 || prison>2147483647 || (prison>0 && (v[6]!=1 || v[0]<=0))) { ret_bool(r,false); return; }
	for(int k: {0,1,2,3,4,5,12,17,18,19,20,21}) if(v[k]<0) { ret_bool(r,false); return; }
	for(int k: {6,7}) if(v[k]!=0 && v[k]!=1) { ret_bool(r,false); return; }
	for(int k: {8,9,10,11,13}) if(v[k]!=std::floor(v[k])) { ret_bool(r,false); return; }
	if(v[8]<0 || v[8]>65535 || v[13]<0 || v[13]>2 || v[14]<0 || v[15]<0 || v[14]>=w.terrain.w || v[15]>=w.terrain.h || std::abs(v[16])>1e9) { ret_bool(r,false); return; }
	for(int k: {9,10,11}) if(v[k]<-1 || v[k]>100) { ret_bool(r,false); return; }
	wg::SoldierState q;
	q.hp=v[0];q.stun=v[1];q.grace=v[2];q.ko=v[3];q.getup=v[4];q.stagger=v[5];q.captive=(int)v[6];q.bandaged=(int)v[7];q.ammo=(int)v[8];q.tactics=(int)v[9];q.leadership=(int)v[10];q.coach=(int)v[11];q.escape_t=v[12];q.role=(int)v[13];q.x=(float)v[14];q.y=(float)v[15];q.facing=(float)v[16];q.exch_cd=v[17];q.ranged_cd=v[18];q.skill_cd=v[19];q.knock_t=v[20];q.act_t=v[21];q.captor_person=ids[1];
	q.prison_id=prison;
	w.set_soldier_state((int)i,q); ret_bool(r,true);
}
void m_set_contact_revision(CALL_ARGS) {
	SELF; NEED(2); WORLD; int64_t i, revision;
	if (!arg_int(a[0], i) || !arg_int(a[1], revision) || i < 0 || i >= w.soldier_count()) { ret_bool(r, false); return; }
	ret_bool(r, w.set_contact_revision((int)i, revision));
}
void m_contact_revision(CALL_ARGS) {
	SELF; NEED(1); WORLD; int64_t i;
	if (!arg_int(a[0], i) || i < 0 || i >= w.soldier_count()) return bad_args(e, 0);
	ret_int(r, w.contact_revision[(size_t)i]);
}
void m_escort_state(CALL_ARGS) {
	SELF; NEED(1); WORLD; int64_t i;
	if(!arg_int(a[0],i) || i<0 || i>=w.soldier_count()) { return_longs(r,{}); return; }
	return_longs(r,{w.escort_mode[i],w.escort_goal[i]});
}
// Cell commitments for grid crew approach; the ordinary crowd radius mask is
// deliberately kept separate so adjacent legal operator stations stay usable.
// Bulk read/input projections avoid a Variant round trip for each native person.
void m_siege_ground_cells(CALL_ARGS) {
	SELF; NEED(0); WORLD;
	std::vector<int64_t> values;values.reserve(size_t(w.soldier_count())*3);
	for(int i=0;i<w.soldier_count();++i)values.insert(values.end(),{i,w.person_id[i],w.terrain.idx((int)w.px[i],(int)w.py[i])});
	return_longs(r,values);
}
void m_set_siege_crew_members(CALL_ARGS) {
	SELF; NEED(1); WORLD;void *input=arg_packed(a[0],INTS);
	if(!input){ret_bool(r,false);return;}
	const int64_t count=packed_size(size_ints,input);if(count>w.soldier_count()){ret_bool(r,false);return;}
	std::vector<uint8_t> assigned(w.soldier_count(),0);
	for(int64_t k=0;k<count;++k){const int i=ints_read(input,k)[0];if(i<0 || i>=w.soldier_count() || assigned[i]){ret_bool(r,false);return;}assigned[i]=1;}
	for(int i=0;i<w.soldier_count();++i) {
		if((assigned[i]!=0)==w.is_siege_crew(i))continue;
		if(!assigned[i] && (w.siege_group(i)>=0 || (w.escort_mode[i]>=5 && w.escort_goal[i]>=0))){ret_bool(r,false);return;}
		if(assigned[i] && (!w.can_act(i) || (w.escort_mode[i]!=0 && w.escort_mode[i]!=5) || w.rescue_of[i]>=0 || w.capture_of[i]>=0 || w.prison_id[i]!=0 || w.is_convoy_crew(i))){ret_bool(r,false);return;}
	}
	w.siege_crew.swap(assigned); // assigned now retains the previous crew membership.
	for(int i=0;i<w.soldier_count();++i)if(assigned[i] && !w.siege_crew[i] && w.escort_mode[i]==5 && w.escort_goal[i]<0)w.escort_mode[i]=0;
	ret_bool(r,true);
}


void m_siege_occupancy_mask(CALL_ARGS) {
	SELF; NEED(1); WORLD; void *input=arg_packed(a[0],LONGS);
	if(!input){ret_bool(r,false);return;}
	const int64_t count=packed_size(size_longs,input);
	if(count>w.soldier_count()){ret_bool(r,false);return;}
	std::vector<int64_t> ignored;if(count)ignored.assign(longs_read(input,0),longs_read(input,0)+count);
	std::vector<uint8_t> mask(size_t(w.terrain.w)*w.terrain.h,0);
	for(int i=0;i<w.soldier_count();++i) {
		if(std::find(ignored.begin(),ignored.end(),w.person_id[i])!=ignored.end())continue;
		const int source=w.terrain.idx((int)w.px[i],(int)w.py[i]);mask[source]=1;
		if(i<(int)w.siege_step_source.size() && w.siege_step_source[i]>=0)mask[w.siege_step_source[i]]=1;
		if(w.escort_goal[i]>=0)mask[w.escort_goal[i]]=1;
	}
	for(const auto &g:w.siege_compounds) {
		bool skip=true;for(const auto &m:g.members)if(std::find(ignored.begin(),ignored.end(),m.person)==ignored.end()){skip=false;break;}
		if(!skip)for(int c:g.claims)mask[c]=1;
	}
	reset(r,BYTES);void *out=internal[BYTES](r);packed_resize(resize_bytes,out,(int64_t)mask.size());
	if(!mask.empty())std::memcpy(bytes_write(out,0),mask.data(),mask.size());
}

void m_set_siege_crew(CALL_ARGS) {
	SELF; NEED(2); WORLD; int64_t i,v;
	ret_bool(r,arg_int(a[0],i) && arg_int(a[1],v) && i>=0 && i<w.soldier_count() && (v==0 || v==1) && w.set_siege_crew((int)i,v!=0));
}
// G4 logistics convoys. Refusals return 0 / false / an empty array and change nothing.
bool arg_i32(const void *v, int &out) {
	int64_t x = 0;
	if (!arg_int(v, x) || x < -2147483647LL - 1 || x > 2147483647LL) return false;
	out = (int)x;
	return true;
}
void m_add_convoy(CALL_ARGS) {
	SELF; NEED(3); WORLD;
	double ax = 0, ay = 0, facing = 0;
	if (!arg_num(a[0], ax) || !arg_num(a[1], ay) || !arg_num(a[2], facing)) { ret_int(r, 0); return; }
	ret_int(r, w.add_convoy((float)ax, (float)ay, (float)facing));
}
void m_convoy_set_crew(CALL_ARGS) {
	SELF; NEED(5); WORLD;
	int id = 0, soldier = 0, ox = 0, oy = 0;
	int64_t assigned = 0;
	if (!arg_i32(a[0], id) || !arg_i32(a[1], soldier) || !arg_i32(a[2], ox) || !arg_i32(a[3], oy) || !arg_int(a[4], assigned)) { ret_bool(r, false); return; }
	ret_bool(r, w.convoy_set_crew(id, soldier, ox, oy, assigned != 0));
}
void m_convoy_order_goal(CALL_ARGS) {
	SELF; NEED(4); WORLD;
	int id = 0;
	double gx = 0, gy = 0, gfacing = 0;
	if (!arg_i32(a[0], id) || !arg_num(a[1], gx) || !arg_num(a[2], gy) || !arg_num(a[3], gfacing)) { ret_bool(r, false); return; }
	ret_bool(r, w.convoy_order_goal(id, (float)gx, (float)gy, (float)gfacing));
}
void m_convoy_set_body(CALL_ARGS) {
	SELF; NEED(2); WORLD;
	int id = 0;
	void *cells = arg_packed(a[1], INTS);
	if (!arg_i32(a[0], id) || !cells) { ret_bool(r, false); return; }
	const int64_t count = packed_size(size_ints, cells);
	if (count > 64) { ret_bool(r, false); return; }
	std::vector<int> footprint;
	footprint.reserve((size_t)count);
	for (int64_t k = 0; k < count; ++k) footprint.push_back((int)ints_read(cells, k)[0]);
	ret_bool(r, w.convoy_set_body(id, footprint));
}
void m_convoy_state(CALL_ARGS) {
	SELF; NEED(1); WORLD;
	int id = 0;
	wg::ConvoyState s;
	if (!arg_i32(a[0], id) || !w.convoy_state(id, s)) { return_doubles(r, {}); return; }
	return_doubles(r, {s.x, s.y, s.facing, double(s.moving), double(s.complete), double(s.stalled), double(s.reason)});
}
void return_ints(void *r, const std::vector<int32_t> &v); // defined with the other packed returns below
void m_convoy_body(CALL_ARGS) {
	SELF; NEED(1); WORLD;
	int id = 0;
	std::vector<int> cells;
	if (!arg_i32(a[0], id) || !w.convoy_body_at(id, cells)) { return_ints(r, {}); return; }
	std::vector<int32_t> out(cells.begin(), cells.end());
	return_ints(r, out);
}
// Crew soldier indices as doubles (exact for indices); empty when the convoy is unknown.
void m_convoy_crew(CALL_ARGS) {
	SELF; NEED(1); WORLD;
	int id = 0;
	if (!arg_i32(a[0], id)) { return_doubles(r, {}); return; }
	std::vector<double> crew;
	for (int soldier : w.convoy_crew_soldiers(id)) crew.push_back(double(soldier));
	return_doubles(r, crew);
}
void m_convoy_remove(CALL_ARGS) {
	SELF; NEED(1); WORLD;
	int id = 0;
	ret_bool(r, arg_i32(a[0], id) && w.convoy_remove(id));
}
// G4 formation following: attach (every crew member must be a member of the formation), detach, and the attached
// formation (-1 detached, -2 unknown convoy). An explicit convoy_order_goal also detaches.
void m_convoy_attach_formation(CALL_ARGS) {
	SELF; NEED(2); WORLD;
	int id = 0, formation = 0;
	ret_bool(r, arg_i32(a[0], id) && arg_i32(a[1], formation) && w.convoy_attach_formation(id, formation));
}
void m_convoy_detach_formation(CALL_ARGS) {
	SELF; NEED(1); WORLD;
	int id = 0;
	ret_bool(r, arg_i32(a[0], id) && w.convoy_detach_formation(id));
}
void m_convoy_formation(CALL_ARGS) {
	SELF; NEED(1); WORLD;
	int id = 0;
	ret_int(r, arg_i32(a[0], id) ? w.convoy_formation(id) : -2);
}
// Diagnostics, read-only: a soldier's slot target [slot index, x, y, clip], empty when unknown; and every claimed cell
// as [cell, owner convoy, ...].
void m_soldier_slot_target(CALL_ARGS) {
	SELF; NEED(1); WORLD;
	int i = 0, s = -1;
	float x = 0.f, y = 0.f, clip = 1.f;
	if (!arg_i32(a[0], i) || !w.slot_target(i, s, x, y, clip)) { return_doubles(r, {}); return; }
	return_doubles(r, {double(s), double(x), double(y), double(clip)});
}
void m_convoy_claim_cells(CALL_ARGS) {
	SELF; NEED(0); WORLD;
	std::vector<int32_t> out;
	for (size_t v = 0; v < w.convoy_claim_owner.size(); ++v) if (w.convoy_claim_owner[v] != 0) { out.push_back((int32_t)v); out.push_back(w.convoy_claim_owner[v]); }
	return_ints(r, out);
}
// Diagnostics, read-only: [has_goal, goal x, goal y, goal facing, goal cell, formation, slot index, blocked stages,
// no_slot, reason]; empty when the convoy is unknown.
void m_convoy_goal(CALL_ARGS) {
	SELF; NEED(1); WORLD;
	int id = 0;
	wg::ConvoyState s;
	if (!arg_i32(a[0], id) || !w.convoy_state(id, s)) { return_doubles(r, {}); return; }
	for (const auto &c : w.convoys) if (c.id == id) {
		return_doubles(r, {double(c.has_goal), c.gx, c.gy, c.gfacing, double(c.goal_cell), double(c.formation), double(c.slot_index), double(c.blocked), double(c.no_slot), double(s.reason)});
		return;
	}
	return_doubles(r, {});
}
void m_begin_siege_compound(CALL_ARGS) {
	SELF; NEED(5); WORLD;
	void *people=arg_packed(a[0],LONGS),*source=arg_packed(a[1],INTS),*target=arg_packed(a[2],INTS),*sweep=arg_packed(a[3],INTS);
	double duration;
	if (!people || !source || !target || !sweep || !arg_num(a[4],duration)) { ret_int(r,0); return; }
	const int64_t count=packed_size(size_longs,people),ns=packed_size(size_ints,source),nt=packed_size(size_ints,target),nw=packed_size(size_ints,sweep);
	if (count<4 || count>64 || count%4 || ns<1 || ns>64 || nt!=ns || nw<1 || nw>256) { ret_int(r,0); return; }
	const int64_t *p=longs_read(people,0);
	std::vector<wg::World::SiegeMember> members;
	for (int64_t k=0;k<count;k+=4) {
		if (p[k]<0 || p[k]>=w.soldier_count() || p[k+1]<0 || p[k+2]<0 || p[k+2]>=w.terrain.w*w.terrain.h || p[k+3]<0 || p[k+3]>=w.terrain.w*w.terrain.h) { ret_int(r,0); return; }
		members.push_back({(int)p[k],p[k+1],(int)p[k+2],(int)p[k+3]});
	}
	std::vector<int> from(ints_read(source,0),ints_read(source,0)+ns),to(ints_read(target,0),ints_read(target,0)+nt),swept(ints_read(sweep,0),ints_read(sweep,0)+nw);
	ret_int(r,w.begin_siege_compound(members,from,to,swept,duration));
}
void m_siege_compound_state(CALL_ARGS) {
	SELF; NEED(1); WORLD; int64_t token;
	if (!arg_int(a[0],token)) { return_doubles(r,{}); return; }
	const auto *g=w.siege_compound_state(token);
	if (!g) { return_doubles(r,{}); return; }
	return_doubles(r,{g->elapsed,g->duration,double(g->cancelled),double(g->complete),double(g->aborted)});
}
void m_siege_person_state(CALL_ARGS) {
	SELF; NEED(1); WORLD; int64_t i;
	if (!arg_int(a[0],i) || i<0 || i>=w.soldier_count()) { return_longs(r,{}); return; }
	const int group=w.siege_group((int)i);
	if (group<0) { const int source=i<(int64_t)w.siege_step_source.size()?w.siege_step_source[i]:-1;return_longs(r,{w.is_siege_crew((int)i)?1:0,w.escort_mode[i],w.escort_goal[i],0,source,w.escort_goal[i],0,0}); return; }
	const auto &g=w.siege_compounds[group];
	for (const auto &m:g.members) if (m.soldier==i) { return_longs(r,{w.is_siege_crew((int)i)?1:0,w.escort_mode[i],w.escort_goal[i],g.token,m.from,m.to,g.complete?1:0,g.aborted?1:0}); return; }
	return_longs(r,{});
}
void m_cancel_siege_compound(CALL_ARGS) {
	SELF; NEED(1); WORLD; int64_t token;
	ret_bool(r,arg_int(a[0],token) && w.cancel_siege_compound(token));
}
void m_settle_siege_compound(CALL_ARGS) {
	SELF; NEED(1); WORLD; int64_t token;
	ret_bool(r,arg_int(a[0],token) && w.settle_siege_compound(token));
}
void m_siege_busy(CALL_ARGS) {
	SELF; NEED(0); WORLD;
	bool busy=!w.siege_compounds.empty();
	for (size_t i=0;i<w.escort_mode.size();++i) if (w.escort_mode[i]>=5 && w.escort_goal[i]>=0) busy=true;
	ret_bool(r,busy);
}
void m_set_siege_navigation(CALL_ARGS) {
	SELF; NEED(2); WORLD;
	void *blocked=arg_packed(a[0],INTS),*exits=arg_packed(a[1],LONGS);
	if(!blocked || !exits){ret_bool(r,false);return;}
	const int64_t count=packed_size(size_ints,blocked),extra=packed_size(size_longs,exits);
	if(count>w.terrain.w*w.terrain.h || extra%3 || extra>int64_t(w.soldier_count())*64*3){ret_bool(r,false);return;}
	std::vector<int> cells;if(count)cells.assign(ints_read(blocked,0),ints_read(blocked,0)+count);
	std::vector<int64_t> people;if(extra)people.assign(longs_read(exits,0),longs_read(exits,0)+extra);
	ret_bool(r,w.set_siege_navigation(cells,people));
}

void m_order_housing_step(CALL_ARGS) {
	SELF; NEED(2); WORLD; int64_t i,d;
	if (!arg_int(a[0],i) || !arg_int(a[1],d) || i<0 || i>=w.soldier_count() || d<0 || d>=w.terrain.w*w.terrain.h) { ret_bool(r,false); return; }
	ret_bool(r,w.order_housing_step((int)i,(int)d));
}
void m_order_siege_step(CALL_ARGS) {
	SELF; NEED(2); WORLD; int64_t i,d;
	if (!arg_int(a[0],i) || !arg_int(a[1],d) || i<0 || i>=w.soldier_count() || d<0 || d>=w.terrain.w*w.terrain.h) { ret_bool(r,false); return; }
	ret_bool(r,w.order_siege_step((int)i,(int)d));
}
void m_cancel_housing_step(CALL_ARGS) {
	SELF; NEED(1); WORLD; int64_t i;
	if (!arg_int(a[0],i) || i<0 || i>=w.soldier_count()) { ret_bool(r,false); return; }
	w.cancel_housing_step((int)i); ret_bool(r,true);
}
void m_cancel_siege_step(CALL_ARGS) {
	SELF; NEED(1); WORLD; int64_t i;
	if (!arg_int(a[0],i) || i<0 || i>=w.soldier_count()) { ret_bool(r,false); return; }
	w.cancel_siege_step((int)i); ret_bool(r,true);
}
void m_order_escort_step(CALL_ARGS) {
	SELF; NEED(3); WORLD; int64_t i,g,d;
	if(!arg_int(a[0],i) || !arg_int(a[1],g) || !arg_int(a[2],d) || i<0 || i>=w.soldier_count() || g<0 || g>=w.soldier_count() || d<0 || d>=w.terrain.w*w.terrain.h) { ret_bool(r,false); return; }
	ret_bool(r,w.order_escort_step((int)i,(int)g,(int)d));
}
void m_cancel_escort(CALL_ARGS) {
	SELF; NEED(1); WORLD; int64_t i;
	if(!arg_int(a[0],i) || i<0 || i>=w.soldier_count()) { ret_bool(r,false); return; }
	w.cancel_escort((int)i); ret_bool(r,true);
}
void m_admit_prison(CALL_ARGS) {
	SELF; NEED(5); WORLD; int64_t i,g,p,s,c;
	if(!arg_int(a[0],i) || !arg_int(a[1],g) || !arg_int(a[2],p) || !arg_int(a[3],s) || !arg_int(a[4],c) || i<0 || i>=w.soldier_count() || g<0 || g>=w.soldier_count() || s<0 || s>=w.terrain.w*w.terrain.h || c<0 || c>=w.terrain.w*w.terrain.h) { ret_bool(r,false); return; }
	ret_bool(r,w.admit_prison((int)i,(int)g,p,(int)s,(int)c));
}
void m_release_prison(CALL_ARGS) {
	SELF; NEED(5); WORLD; int64_t i,g,p,c,x;
	if(!arg_int(a[0],i) || !arg_int(a[1],g) || !arg_int(a[2],p) || !arg_int(a[3],c) || !arg_int(a[4],x) || i<0 || i>=w.soldier_count() || g<0 || g>=w.soldier_count() || c<0 || c>=w.terrain.w*w.terrain.h || x<0 || x>=w.terrain.w*w.terrain.h) { ret_bool(r,false); return; }
	ret_bool(r,w.release_prison((int)i,(int)g,p,(int)c,(int)x));
}
// Merge beside ORIGINAL m_step_clock / m_formation_state implementations.
void m_work_fatigue_state(CALL_ARGS) {
	SELF; NEED(1); WORLD; int64_t f;
	if (!arg_int(a[0],f) || f<0 || f>=(int64_t)w.formations.size()) { return_doubles(r,{}); return; }
	return_doubles(r,w.work_fatigue_state((int)f));
}
void m_work_fatigue_runners(CALL_ARGS) {
	SELF; NEED(1); WORLD; int64_t f;
	if (!arg_int(a[0],f) || f<0 || f>=(int64_t)w.formations.size()) { return_longs(r,{}); return; }
	return_longs(r,w.work_fatigue_runners((int)f));
}
void m_work_fatigue_rest_limit(CALL_ARGS) {
	SELF; NEED(4); WORLD; int64_t f; double target,maximum,cl;
	if (!arg_int(a[0],f) || f<0 || f>=(int64_t)w.formations.size() || !arg_num(a[1],target) ||
		!arg_num(a[2],maximum) || !arg_num(a[3],cl)) { ret_float(r,NAN); return; }
	ret_float(r,w.work_fatigue_rest_limit((int)f,target,maximum,cl));
}
bool read_work_fatigue_plan(const wg::World &w, GDExtensionConstVariantPtr value,
	std::vector<wg::World::WorkFatigueState> &plan) {
	void *packed=arg_packed(value,DOUBLES);
	if (!packed) return false;
	const int64_t count=packed_size(size_doubles,packed);
	if (count%8 || count/8>(int64_t)w.formations.size()) return false;
	const double *values=count ? doubles_read(packed,0) : nullptr;
	plan.reserve((size_t)(count/8));
	for (int64_t k=0;k<count;k+=8) {
		for (int j=0;j<8;++j) if (!std::isfinite(values[k+j])) return false;
		if (values[k]<0 || values[k]>=(double)w.formations.size() || values[k]!=std::floor(values[k]) ||
			values[k+3]<=0 || values[k+3]>w.soldier_count() || values[k+3]!=std::floor(values[k+3])) return false;
		wg::World::WorkFatigueState p;
		p.formation=(int)values[k];p.before_fatigue=values[k+1];p.before_rest=values[k+2];p.before_count=(int)values[k+3];
		p.work_seconds=values[k+4];p.run_seconds=values[k+5];p.fatigue=values[k+6];p.rest=values[k+7];
		plan.push_back(p);
	}
	return true;
}

static bool read_work_training_plan(wg::World &w, GDExtensionConstVariantPtr value, std::vector<wg::World::WorkTrainingState> &plan) {
    void *packed=arg_packed(value,DOUBLES); if(!packed) return false;
    const int64_t count=packed_size(size_doubles,packed); if(count%5 || count/5>(int64_t)w.formations.size()) return false;
    const double *values=count?doubles_read(packed,0):nullptr; plan.reserve((size_t)(count/5));
    for(int64_t k=0;k<count;k+=5) {
        for(int j=0;j<5;++j) if(!std::isfinite(values[k+j])) return false;
        if(values[k]<0 || values[k]>=double(w.formations.size()) || values[k]!=std::floor(values[k])) return false;
        wg::World::WorkTrainingState t; t.formation=(int)values[k]; t.before_training=values[k+1];
        t.training=values[k+2]; t.effort_seconds=values[k+3]; t.productive_seconds=values[k+4]; plan.push_back(t);
    }
    return true;
}
void m_work_training_start_ready(CALL_ARGS) {
    SELF; NEED(2); WORLD; int64_t fi; double combat;
    if(n!=2 || !arg_int(a[0],fi) || !arg_num(a[1],combat) || fi<0 || fi>=(int64_t)w.formations.size()) { ret_bool(r,false); return; }
    ret_bool(r,w.work_training_start_ready((int)fi,combat));
}
void m_validate_work_point_training_plan(CALL_ARGS) {
    SELF; NEED(2); WORLD; int64_t tick; std::vector<wg::World::WorkTrainingState> plan;
    if(n!=2 || !arg_int(a[0],tick) || tick<0 || tick>0xffffffffLL || !read_work_training_plan(w,a[1],plan)) { ret_bool(r,false); return; }
    ret_bool(r,w.validate_work_point_training_plan((uint32_t)tick,plan));
}
void m_prepare_work_point_training_plan(CALL_ARGS) {
    SELF; NEED(2); WORLD; int64_t tick; std::vector<wg::World::WorkTrainingState> plan;
    if(n!=2 || !arg_int(a[0],tick) || tick<0 || tick>0xffffffffLL || !read_work_training_plan(w,a[1],plan)) { ret_bool(r,false); return; }
    ret_bool(r,w.prepare_work_point_training_plan((uint32_t)tick,plan));
}

void m_step_clock_work_point(CALL_ARGS) {
    SELF; NEED(5); WORLD; double dt,gs,cl; int64_t tick; std::vector<wg::World::WorkFatigueState> plan;
    if(n!=5 || !arg_num(a[0],dt) || !arg_num(a[1],gs) || !arg_num(a[2],cl) ||
       !arg_int(a[3],tick) || tick<0 || tick>0xffffffffLL || !read_work_fatigue_plan(w,a[4],plan)) { ret_bool(r,false); return; }
    ret_bool(r,w.step_clock_work_point((float)dt,gs,cl,(uint32_t)tick,plan));
}
void m_validate_work_point_finish(CALL_ARGS) {
    SELF; NEED(2); WORLD; int64_t tick; std::vector<wg::World::WorkFatigueState> plan;
    if(n!=2 || !arg_int(a[0],tick) || tick<0 || tick>0xffffffffLL || !read_work_fatigue_plan(w,a[1],plan)) { ret_bool(r,false); return; }
    ret_bool(r,w.validate_work_point_finish((uint32_t)tick,plan));
}
void m_prepare_work_point_finish(CALL_ARGS) {
    SELF; NEED(2); WORLD; int64_t tick; std::vector<wg::World::WorkFatigueState> plan;
    if(n!=2 || !arg_int(a[0],tick) || tick<0 || tick>0xffffffffLL || !read_work_fatigue_plan(w,a[1],plan)) { ret_bool(r,false); return; }
    ret_bool(r,w.prepare_work_point_finish((uint32_t)tick,plan));
}
void m_publish_work_point_finish(CALL_ARGS) { SELF; NEED(0); WORLD; w.publish_work_point_finish(); ret_bool(r,true); }
void m_work_point_state(CALL_ARGS) { SELF; NEED(0); WORLD; return_doubles(r,w.work_point_state()); }
void m_work_fatigue_run_upper(CALL_ARGS) { SELF; NEED(0); WORLD; return_longs(r,w.work_fatigue_run_upper()); }
void m_work_point_runners(CALL_ARGS) { SELF; NEED(0); WORLD; return_longs(r,w.work_point_runners()); }

void m_validate_step_clock_work_plan(CALL_ARGS) {
	SELF; NEED(5); WORLD; double dt,gs,cl; int64_t tick;
	std::vector<wg::World::WorkFatigueState> plan;
	if (!arg_num(a[0],dt) || !(dt>0 && dt<1) || !arg_num(a[1],gs) || !arg_num(a[2],cl) ||
		!arg_int(a[3],tick) || tick<0 || tick>0xffffffffLL || !read_work_fatigue_plan(w,a[4],plan)) { ret_bool(r,false); return; }
	ret_bool(r,w.validate_step_clock_work_plan((float)dt,gs,cl,(uint32_t)tick,plan));
}
void m_validate_step_clock_work_plan_after_host_ranged(CALL_ARGS) {
	SELF; NEED(7); WORLD; double dt,gs,cl; int64_t tick;
	std::vector<wg::World::WorkFatigueState> plan;
	void *input=arg_packed(a[5],LONGS),*projection=arg_packed(a[6],DOUBLES);
	if(!arg_num(a[0],dt)||!(dt>0&&dt<1)||!arg_num(a[1],gs)||!arg_num(a[2],cl)||
		!arg_int(a[3],tick)||tick<0||tick>0xffffffffLL||!read_work_fatigue_plan(w,a[4],plan)||!input||!projection){ret_bool(r,false);return;}
	const int64_t release_size=packed_size(size_longs,input),p=packed_size(size_doubles,projection);
	if(release_size<0||release_size%6!=0||release_size/6>w.soldier_count()||p!=release_size/6*10){ret_bool(r,false);return;}
	std::vector<int64_t> releases; std::vector<double> preview;
	if(release_size) releases.assign(longs_read(input,0),longs_read(input,0)+release_size);
	if(p) preview.assign(doubles_read(projection,0),doubles_read(projection,0)+p);
	ret_bool(r,w.validate_step_clock_work_plan_after_host_ranged((float)dt,gs,cl,(uint32_t)tick,plan,releases,preview));
}
void m_step_clock_work_plan(CALL_ARGS) {
	SELF; NEED(5); WORLD; double dt,gs,cl; int64_t tick;
	std::vector<wg::World::WorkFatigueState> plan;
	if (!arg_num(a[0],dt) || !(dt>0 && dt<1) || !arg_num(a[1],gs) || !arg_num(a[2],cl) ||
		!arg_int(a[3],tick) || tick<0 || tick>0xffffffffLL || !read_work_fatigue_plan(w,a[4],plan)) { ret_bool(r,false); return; }
	auto started=std::chrono::steady_clock::now();
	const bool ok=w.step_clock_work_plan((float)dt,gs,cl,(uint32_t)tick,plan);
	self->last_step_ms=std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-started).count();
	ret_bool(r,ok);
}

void m_get_formation_state(CALL_ARGS) {
	SELF; NEED(1); WORLD; int64_t i;
	if(!arg_int(a[0],i) || i<0 || i>=(int64_t)w.formations.size()) { return_doubles(r,{}); return; }
	const auto &f=w.formations[i];
	return_doubles(r,{f.morale,f.rally_rest,f.fatigue,f.fatigue_rest,f.training,double(f.routed),double(f.needs_attack_order),double(f.commander_present),double(f.fatigue_count),double(f.order),f.goal_x,f.goal_y,f.goal_facing,f.pursuit_left,f.origin_x,f.origin_y,double(f.ai_enabled),f.cx,f.cy,f.facing,double(f.no_orders),f.order_delay,double(f.attacking),f.ref_x,f.ref_y,double(f.ref_valid),double(f.resupplying),double(f.host_center)});
}
void m_formation_refs(CALL_ARGS) {
	SELF; NEED(1); WORLD; int64_t i;
	if(!arg_int(a[0],i) || i<0 || i>=(int64_t)w.formations.size()) { return_longs(r,{}); return; }
	const auto f=w.get_formation_state((int)i); std::vector<int64_t> refs{f.formal_person,f.acting_person,f.current_person,f.target_person};
	refs.insert(refs.end(),f.officer_persons.begin(),f.officer_persons.end()); return_longs(r,refs);
}
// ORDSERIAL: order_serials(formation) -> [order_serial, ranged_order_serial] (empty: no such formation);
// set_order_serials(formation, order_serial, ranged_order_serial) -> World::set_order_serials.
void m_order_serials(CALL_ARGS) {
	SELF; NEED(1); WORLD; int64_t i;
	if(!arg_int(a[0],i) || i<0 || i>=(int64_t)w.formations.size()) { return_longs(r,{}); return; }
	return_longs(r,{w.formations[i].order_serial,w.formations[i].ranged_order_serial});
}
void m_set_order_serials(CALL_ARGS) {
	SELF; NEED(3); WORLD; int64_t i,order,ranged;
	ret_bool(r,arg_int(a[0],i) && arg_int(a[1],order) && arg_int(a[2],ranged) && i>=0 && i<(int64_t)w.formations.size()
		&& w.set_order_serials((int)i,order,ranged));
}
void m_set_formation_state(CALL_ARGS) {
	SELF; NEED(3); WORLD; int64_t i;
	void *data=arg_packed(a[1],DOUBLES),*refs=arg_packed(a[2],LONGS);
	if(!arg_int(a[0],i) || i<0 || i>=(int64_t)w.formations.size() || !data || !refs || packed_size(size_doubles,data)<28 || packed_size(size_longs,refs)<4 || packed_size(size_longs,refs)>w.soldier_count()+4) { ret_bool(r,false); return; }
	const double *v=doubles_read(data,0); const int64_t *ids=longs_read(refs,0);
	for(int k=0;k<28;++k) if(!std::isfinite(v[k]) || ((k==12 || k==19 || k==23 || k==24) && !std::isfinite((float)v[k]))) { ret_bool(r,false); return; }
	for(int k: {0,1,2,3,4,8}) if(v[k]<0) { ret_bool(r,false); return; }
	for(int k: {5,6,7,16,20,22,25,26,27}) if(v[k]!=0 && v[k]!=1) { ret_bool(r,false); return; }
	if(v[0]>100 || v[8]>w.soldier_count() || v[8]!=std::floor(v[8]) || v[9]<0 || v[9]>5 || v[9]!=std::floor(v[9]) || v[13]<=-1 || v[21]<=-1) { ret_bool(r,false); return; }
	for(int k: {10,14,17}) if(v[k]<0 || v[k]>=w.terrain.w || v[k+1]<0 || v[k+1]>=w.terrain.h) { ret_bool(r,false); return; }
	if(v[25] && (v[23]<0 || v[23]>=w.terrain.w || v[24]<0 || v[24]>=w.terrain.h)) { ret_bool(r,false); return; }
	for(int64_t k=0;k<packed_size(size_longs,refs);++k) {
		const int j=w.soldier_index(ids[k]); if(ids[k]!=-1 && (j<0 || (k!=3 && w.form[j]!=(int)i))) { ret_bool(r,false); return; }
	}
	wg::FormationState q;
	q.morale=v[0];q.rally_rest=v[1];q.fatigue=v[2];q.fatigue_rest=v[3];q.training=v[4];q.routed=(int)v[5];q.needs_attack_order=(int)v[6];q.commander_present=(int)v[7];q.fatigue_count=(int)v[8];q.order=(int)v[9];q.goal_x=(float)v[10];q.goal_y=(float)v[11];q.goal_facing=(float)v[12];q.pursuit_left=v[13];q.origin_x=(float)v[14];q.origin_y=(float)v[15];q.ai_enabled=(int)v[16];q.cx=(float)v[17];q.cy=(float)v[18];q.facing=(float)v[19];q.no_orders=(int)v[20];q.order_delay=v[21];q.attacking=(int)v[22];q.ref_x=(float)v[23];q.ref_y=(float)v[24];q.ref_valid=(int)v[25];q.resupplying=(int)v[26];q.host_center=(int)v[27];
	q.formal_person=ids[0];q.acting_person=ids[1];q.current_person=ids[2];q.target_person=ids[3];
	for(int64_t k=4;k<packed_size(size_longs,refs);++k) if(ids[k]>=0) q.officer_persons.push_back(ids[k]);
	w.set_formation_state((int)i,q);ret_bool(r,true);
}
void m_set_soldier_equip(CALL_ARGS) {
	SELF; NEED(2); WORLD; int64_t i,code;
	if(!arg_int(a[0],i) || !arg_int(a[1],code) || i<0 || i>=w.soldier_count() || code<0 || code>0x0105ffff) { ret_bool(r,false);return; }
	wg::rules::Equip eq{uint8_t(code&255),uint8_t((code>>8)&255),uint8_t((code>>16)&255),((code>>24)&255)!=0};
	if(eq.family>wg::rules::F_SHOVEL || eq.material>wg::rules::M_STEEL || eq.armor>wg::rules::A_MINGGUANG || ((code>>24)&255)>1) { ret_bool(r,false);return; }
	ret_bool(r,w.set_soldier_equip((int)i,eq));
}
void m_set_soldier_ammo(CALL_ARGS) {
	SELF; NEED(2); WORLD; int64_t i,am;
	if(!arg_int(a[0],i) || !arg_int(a[1],am) || i<0 || i>=w.soldier_count() || am<0 || am>65535) { ret_bool(r,false);return; }
	w.ammo[i]=(uint16_t)am;ret_bool(r,true);
}
void m_set_sustain_input(CALL_ARGS) {
	SELF; NEED(3); WORLD; int64_t f,fed;double d;
	if(!arg_int(a[0],f) || !arg_int(a[1],fed) || !arg_num(a[2],d) || f<0 || f>=(int64_t)w.formations.size()) { ret_bool(r,false);return; }
	ret_bool(r,w.set_sustain_input((int)f,fed!=0,d));
}
void m_set_garrisoned(CALL_ARGS) {
	SELF; NEED(2); WORLD; int64_t f,v;
	ret_bool(r,arg_int(a[0],f) && arg_int(a[1],v) && (v==0 || v==1) && w.set_garrisoned((int)f,v!=0));
}
void m_set_housing_attendance_input(CALL_ARGS) {
	SELF; NEED(2); WORLD; int64_t i,d;
	if (!arg_int(a[0],i) || !arg_int(a[1],d) || i<0 || i>=w.soldier_count() || d < -1 || d>=w.terrain.w*w.terrain.h) { ret_bool(r,false); return; }
	ret_bool(r,w.set_housing_attendance_input((int)i,(int)d));
}
void m_set_housing_recovery_input(CALL_ARGS) {
	SELF; NEED(2); WORLD; int64_t f; double multiplier;
	if (!arg_int(a[0],f) || f<0 || f>=(int)w.formations.size()) { ret_bool(r,false); return; }
	if (!arg_num(a[1],multiplier)) { w.set_housing_recovery_input((int)f,1.0); ret_bool(r,false); return; }
	ret_bool(r,w.set_housing_recovery_input((int)f,multiplier));
}
void m_set_recovery_input(CALL_ARGS) {
	SELF; NEED(2); WORLD; int64_t f; double multiplier;
	if (!arg_int(a[0],f) || f < 0 || f >= (int64_t)w.formations.size()) { ret_bool(r,false); return; }
	if (!arg_num(a[1],multiplier)) { w.set_recovery_input((int)f,1.0); ret_bool(r,false); return; }
	ret_bool(r,w.set_recovery_input((int)f,multiplier));
}
void m_set_fire_safe_rest_input(CALL_ARGS) {
	SELF; NEED(2); WORLD; int64_t f, safe;
	if (!arg_int(a[0],f) || f < 0 || f >= (int64_t)w.formations.size()
		|| !arg_int(a[1],safe) || (safe != 0 && safe != 1)) { ret_bool(r,false); return; }
	ret_bool(r,w.set_fire_safe_rest_input((int)f,safe != 0));
}
// G7b: set_formation_shape(formation, offsets: PackedFloat32Array of (lateral, back) pairs; empty clears) -> bool
void m_set_formation_shape(CALL_ARGS) {
	SELF; NEED(2); WORLD; int64_t f;
	if (!arg_int(a[0], f)) return bad_args(e, 0);
	void *p = arg_packed(a[1], FLOATS);
	if (!p) return bad_args(e, 1);
	const int64_t count = packed_size(size_floats, p);
	if (f < 0 || f >= (int64_t)w.formations.size() || count < 0 || count > 2 * (int64_t)wg::World::MAX_SHAPE_SLOTS) { ret_bool(r, false); return; }
	std::vector<float> offsets((size_t)count);
	for (int64_t k = 0; k < count; ++k) offsets[(size_t)k] = *floats_read(p, k);
	ret_bool(r, w.set_formation_shape((int)f, offsets));
}
// G7b: get_formation_shape(formation) -> number of preset slots (pairs); 0 for none or a bad id
void m_get_formation_shape(CALL_ARGS) {
	SELF; NEED(1); WORLD; int64_t f;
	ret_int(r, arg_int(a[0], f) && f >= 0 && f < (int64_t)w.formations.size() ? (int64_t)(w.formations[f].shape.size() / 2) : 0);
}
void m_get_garrisoned(CALL_ARGS) {
	SELF; NEED(1); WORLD; int64_t f;
	ret_bool(r,arg_int(a[0],f) && f>=0 && f<(int64_t)w.formations.size() && w.formations[f].garrisoned);
}
void m_set_military_role(CALL_ARGS) {
	SELF; NEED(2); WORLD; int64_t i,v;
	ret_bool(r,arg_int(a[0],i) && arg_int(a[1],v) && w.set_military_role((int)i,(int)v));
}
void m_get_military_role(CALL_ARGS) {
	SELF; NEED(1); WORLD; int64_t i;
	ret_int(r,arg_int(a[0],i) && i>=0 && i<w.soldier_count() ? w.military_role[i] : -1);
}
void m_set_post_holder(CALL_ARGS) {
	SELF; NEED(2); WORLD; int64_t i,v;
	ret_bool(r,arg_int(a[0],i) && arg_int(a[1],v) && w.set_post_holder((int)i,(int)v));
}
void m_get_post_holder(CALL_ARGS) {
	SELF; NEED(1); WORLD; int64_t i;
	ret_int(r,arg_int(a[0],i) && i>=0 && i<w.soldier_count() ? w.post_holder[i] : -1);
}
void m_get_soldier_presence(CALL_ARGS) {
	SELF; NEED(1); WORLD; int64_t i;
	ret_bool(r,arg_int(a[0],i) && i>=0 && i<w.soldier_count() && w.present[i]);
}
void m_apply_training_state(CALL_ARGS) {
	SELF; NEED(8); WORLD; int64_t f,worked; double v[6];
	if (!arg_int(a[0],f) || !arg_int(a[7],worked) || (worked!=0 && worked!=1)) { ret_bool(r,false); return; }
	for (int k=0;k<6;++k) if (!arg_num(a[k+1],v[k])) { ret_bool(r,false); return; }
	ret_bool(r,w.apply_training_state((int)f,v[0],v[1],v[2],v[3],v[4],v[5],worked!=0));
}

void m_apply_siege_contact(CALL_ARGS) {
	SELF; NEED(4); WORLD; int64_t i; double hp, stun, stagger;
	if (!arg_int(a[0],i) || i<0 || i>=w.soldier_count() || !arg_num(a[1],hp) || !arg_num(a[2],stun) || !arg_num(a[3],stagger)) { ret_bool(r,false); return; }
	ret_bool(r, w.apply_siege_contact((int)i,hp,stun,stagger));
}
// set_aboard_melee_pairs(pairs: PackedInt32Array flat [a, b, ...]) -> bool: host hull contacts for the next step only.
void m_set_aboard_melee_pairs(CALL_ARGS) {
	SELF; NEED(1); WORLD;
	void *k = arg_packed(a[0], INTS);
	if (!k) { ret_bool(r, false); return; }
	const int64_t count = packed_size(size_ints, k);
	std::vector<int> flat; flat.reserve((size_t)count);
	for (int64_t q = 0; q < count; ++q) flat.push_back((int)*ints_read(k, q));
	ret_bool(r, w.set_aboard_melee_pairs(flat));
}
void m_apply_melee_contact(CALL_ARGS) {
	SELF; NEED(3); WORLD; int64_t i; double hp, stun;
	if (!arg_int(a[0],i) || i<0 || i>=w.soldier_count() || !arg_num(a[1],hp) || !arg_num(a[2],stun)) { ret_bool(r,false); return; }
	ret_bool(r, w.apply_melee_contact((int)i,hp,stun));
}
void m_charge_exchange_fatigue(CALL_ARGS) {
	SELF; NEED(2); WORLD; int64_t i; double amount;
	if (!arg_int(a[0],i) || i<0 || i>=w.soldier_count() || !arg_num(a[1],amount)) { ret_bool(r,false); return; }
	ret_bool(r, w.charge_exchange_fatigue((int)i,amount));
}
void m_site_person_exit_ready(CALL_ARGS) {
	SELF; NEED(1); WORLD; int64_t i;
	ret_bool(r, arg_int(a[0],i) && i>=0 && i<w.soldier_count() && w.site_person_exit_ready((int)i));
}
// [hp, fatigue, fatigue_rest, ammo, cell_x, cell_y, x, y]; an empty array refuses (nothing released)
void m_site_person_release(CALL_ARGS) {
	SELF; NEED(1); WORLD; int64_t i;
	wg::SitePersonRelease rel;
	if (!arg_int(a[0],i) || i<0 || i>=w.soldier_count() || !w.site_person_release((int)i,rel)) { return_doubles(r,{}); return; }
	return_doubles(r,{rel.hp, rel.fatigue, rel.fatigue_rest, double(rel.ammo), double(rel.cell_x), double(rel.cell_y), rel.x, rel.y});
}
// SHIPSEA sea departure: the exit gate and release of a soldier aboard `vehicle`; same array as site_person_release.
void m_site_person_exit_ready_aboard(CALL_ARGS) {
	SELF; NEED(2); WORLD; int64_t i, vehicle;
	ret_bool(r, arg_int(a[0],i) && arg_int(a[1],vehicle) && i>=0 && i<w.soldier_count() && vehicle>=0 && vehicle<=INT32_MAX && w.site_person_exit_ready_aboard((int)i,(int)vehicle));
}
void m_site_person_release_aboard(CALL_ARGS) {
	SELF; NEED(2); WORLD; int64_t i, vehicle;
	wg::SitePersonRelease rel;
	if (!arg_int(a[0],i) || !arg_int(a[1],vehicle) || i<0 || i>=w.soldier_count() || vehicle<0 || vehicle>INT32_MAX || !w.site_person_release_aboard((int)i,(int)vehicle,rel)) { return_doubles(r,{}); return; }
	return_doubles(r,{rel.hp, rel.fatigue, rel.fatigue_rest, double(rel.ammo), double(rel.cell_x), double(rel.cell_y), rel.x, rel.y});
}
// Decision A2 on crowd: release of a dead soldier; same array as site_person_release, empty on refusal.
void m_site_person_release_dead(CALL_ARGS) {
	SELF; NEED(1); WORLD; int64_t i;
	wg::SitePersonRelease rel;
	if (!arg_int(a[0],i) || i<0 || i>=w.soldier_count() || !w.site_person_release_dead((int)i,rel)) { return_doubles(r,{}); return; }
	return_doubles(r,{rel.hp, rel.fatigue, rel.fatigue_rest, double(rel.ammo), double(rel.cell_x), double(rel.cell_y), rel.x, rel.y});
}
// A person returning to a Site they left: the released slot carrying their id takes an unused placeholder id.
void m_site_person_retag_released(CALL_ARGS) {
	SELF; NEED(2); WORLD; int64_t i, placeholder;
	ret_bool(r, arg_int(a[0],i) && arg_int(a[1],placeholder) && i>=0 && i<w.soldier_count() && w.site_person_retag_released((int)i,placeholder));
}
// A formation everyone left starts over in place: site_formation_reuse(formation, faction, cx, cy, facing, cols, spacing,
// troop, training) -> bool, the arguments of add_formation after the formation index.
void m_site_formation_reuse(CALL_ARGS) {
	SELF; NEED(9); WORLD;
	int64_t f, team, cols, troop; double cx, cy, facing, spacing, training;
	if (!arg_int(a[0], f) || !arg_int(a[1], team) || !arg_num(a[2], cx) || !arg_num(a[3], cy) || !arg_num(a[4], facing) || !arg_int(a[5], cols) ||
	    !arg_num(a[6], spacing) || !arg_int(a[7], troop) || !arg_num(a[8], training) || f < 0 || f >= (int64_t)w.formations.size() ||
	    team < 0 || team > 255 || troop < 0 || troop > 2) { ret_bool(r, false); return; }
	ret_bool(r, w.site_formation_reuse((int)f, (int)team, (float)cx, (float)cy, (float)facing, (int)std::max<int64_t>(1, cols), (float)spacing, (wg::Troop)troop, training));
}
// A person returning to a Site they left: site_person_readmit(soldier, formation, packed_equip, role, ammo) -> bool.
// The released slot is a fresh soldier of the formation again; the slot index, person id and ability are kept.
void m_site_person_readmit(CALL_ARGS) {
	SELF; NEED(5); WORLD; int64_t i, f, code, role, am;
	if (!arg_int(a[0],i) || !arg_int(a[1],f) || !arg_int(a[2],code) || !arg_int(a[3],role) || !arg_int(a[4],am)
			|| i<0 || i>=w.soldier_count() || f<0 || f>=(int64_t)w.formations.size() || role<0 || role>2 || am<0 || am>65535) { ret_bool(r,false); return; }
	wg::rules::Equip q;
	q.family = (uint8_t)(code & 255); q.material = (uint8_t)((code >> 8) & 255); q.armor = (uint8_t)((code >> 16) & 255); q.shield = ((code >> 24) & 1) != 0;
	ret_bool(r, w.site_person_readmit((int)i,(int)f,q,(wg::Role)role,(uint16_t)am));
}
// G1 S1 aboard. Refusals return false / an empty array and change nothing. site_person_aboard: [aboard, vehicle].
void m_site_person_board(CALL_ARGS) {
	SELF; NEED(2); WORLD; int64_t i, vehicle;
	ret_bool(r, arg_int(a[0],i) && arg_int(a[1],vehicle) && i>=0 && i<w.soldier_count() && vehicle>=0 && vehicle<=INT32_MAX && w.site_person_board((int)i,(int)vehicle));
}
void m_site_person_land(CALL_ARGS) {
	SELF; NEED(3); WORLD; int64_t i; double x = 0, y = 0;
	ret_bool(r, arg_int(a[0],i) && arg_num(a[1],x) && arg_num(a[2],y) && i>=0 && i<w.soldier_count() && w.site_person_land((int)i,x,y));
}
void m_site_person_set_deck(CALL_ARGS) {
	SELF; NEED(3); WORLD; int64_t i; double x = 0, y = 0;
	ret_bool(r, arg_int(a[0],i) && arg_num(a[1],x) && arg_num(a[2],y) && i>=0 && i<w.soldier_count() && w.site_person_set_deck((int)i,x,y));
}
void m_site_person_retarget_aboard(CALL_ARGS) {
	SELF; NEED(2); WORLD; int64_t i, vehicle;
	ret_bool(r, arg_int(a[0],i) && arg_int(a[1],vehicle) && i>=0 && i<w.soldier_count() && vehicle>=0 && vehicle<=INT32_MAX && w.site_person_retarget_aboard((int)i,(int)vehicle));
}
void m_site_person_aboard(CALL_ARGS) {
	SELF; NEED(1); WORLD; int64_t i;
	if (!arg_int(a[0],i) || i<0 || i>=w.soldier_count()) { return_doubles(r,{}); return; }
	return_doubles(r,{double(w.aboard[i]), double(w.aboard_vehicle[i])});
}
// G5 S1 absent / return / move_member. Refusals return false and change nothing. site_person_absent_state: [absent, kind].
void m_site_person_absent(CALL_ARGS) {
	SELF; NEED(2); WORLD; int64_t i, kind;
	ret_bool(r, arg_int(a[0],i) && arg_int(a[1],kind) && i>=0 && i<w.soldier_count() && kind>=1 && kind<=4 && w.site_person_absent((int)i,(int)kind));
}
void m_site_person_return(CALL_ARGS) {
	SELF; NEED(4); WORLD; int64_t i, formation; double x = 0, y = 0;
	ret_bool(r, arg_int(a[0],i) && arg_int(a[1],formation) && arg_num(a[2],x) && arg_num(a[3],y) && i>=0 && i<w.soldier_count() && formation>=0 && formation<=INT32_MAX && w.site_person_return((int)i,(int)formation,x,y));
}
void m_move_member(CALL_ARGS) {
	SELF; NEED(2); WORLD; int64_t i, to;
	ret_bool(r, arg_int(a[0],i) && arg_int(a[1],to) && i>=0 && i<w.soldier_count() && to>=0 && to<=INT32_MAX && w.move_member((int)i,(int)to));
}
// NEKKI 2026-10-30 persuasion: captive of another team joins to_formation as a normal member. Refusals change nothing.
void m_transfer_member(CALL_ARGS) {
	SELF; NEED(2); WORLD; int64_t i, to;
	ret_bool(r, arg_int(a[0],i) && arg_int(a[1],to) && i>=0 && i<w.soldier_count() && to>=0 && to<=INT32_MAX && w.transfer_member((int)i,(int)to));
}
// NEKKI 2026-11-05 combat records: the person who last landed an effective blow on soldier i (-1 unknown).
void m_last_striker(CALL_ARGS) {
	SELF; NEED(1); WORLD; int64_t i;
	ret_int(r, arg_int(a[0],i) && i>=0 && i<w.soldier_count() ? w.last_striker((int)i) : -1);
}
// NEKKI 2026-11-04 joining in person: an awake free member leaves for another team's formation. Refusals change nothing.
void m_leave_member(CALL_ARGS) {
	SELF; NEED(2); WORLD; int64_t i, to;
	ret_bool(r, arg_int(a[0],i) && arg_int(a[1],to) && i>=0 && i<w.soldier_count() && to>=0 && to<=INT32_MAX && w.leave_member((int)i,(int)to));
}
void m_site_person_absent_state(CALL_ARGS) {
	SELF; NEED(1); WORLD; int64_t i;
	if (!arg_int(a[0],i) || i<0 || i>=w.soldier_count()) { return_doubles(r,{}); return; }
	return_doubles(r,{double(w.absent[i]), double(w.absent_kind[i])});
}
// G5 S4: soldier_surrendered(soldier) -> bool; set_soldier_surrendered(soldier, on) -> bool (refusal changes nothing).
void m_soldier_surrendered(CALL_ARGS) {
	SELF; NEED(1); WORLD; int64_t i;
	ret_bool(r, arg_int(a[0],i) && i>=0 && i<w.soldier_count() && w.is_surrendered((int)i));
}
void m_set_soldier_surrendered(CALL_ARGS) {
	SELF; NEED(2); WORLD; int64_t i, on;
	ret_bool(r, arg_int(a[0],i) && arg_int(a[1],on) && i>=0 && i<w.soldier_count() && w.set_surrendered((int)i, on != 0));
}
// CAV-1: soldier_mounted(soldier) -> bool; set_soldier_mounted(soldier, on) -> bool (refusal changes nothing).
void m_soldier_mounted(CALL_ARGS) {
	SELF; NEED(1); WORLD; int64_t i;
	ret_bool(r, arg_int(a[0],i) && i>=0 && i<w.soldier_count() && w.is_mounted((int)i));
}
void m_set_soldier_mounted(CALL_ARGS) {
	SELF; NEED(2); WORLD; int64_t i, on;
	ret_bool(r, arg_int(a[0],i) && arg_int(a[1],on) && i>=0 && i<w.soldier_count() && w.set_mounted((int)i, on != 0));
}
// CAV-2: cav_stats() -> [contacts, falls, dismounts, stops, shocks]: the charge outcome counters of this crowd (reporting).
void m_cav_stats(CALL_ARGS) {
	SELF; NEED(0); WORLD;
	const wg::Stats &st = w.stats;
	const double v[] = {(double)st.cav_contacts, (double)st.cav_falls, (double)st.cav_dismounts, (double)st.cav_stops, (double)st.cav_shocks};
	reset(r, DOUBLES);
	void *buf = internal[DOUBLES](r);
	packed_resize(resize_doubles, buf, (int64_t)(sizeof(v) / sizeof(v[0])));
	std::memcpy(doubles_write(buf, 0), v, sizeof(v));
}
// CAV-2: soldier_charge(soldier) -> [charging, straight_seconds, penetrations_this_charge, distinct_recent_victims].
void m_soldier_charge(CALL_ARGS) {
	SELF; NEED(1); WORLD; int64_t i;
	if (!arg_int(a[0],i) || i<0 || i>=w.soldier_count()) { reset(r, DOUBLES); return; }
	const double v[] = {w.charge_state((int)i) ? 1.0 : 0.0, w.charge_straight_seconds((int)i), (double)w.charge_hits((int)i), (double)w.cav_distinct_victims((int)i)};
	reset(r, DOUBLES);
	void *buf = internal[DOUBLES](r);
	packed_resize(resize_doubles, buf, (int64_t)(sizeof(v) / sizeof(v[0])));
	std::memcpy(doubles_write(buf, 0), v, sizeof(v));
}
void m_charge_siege_round(CALL_ARGS) {
	SELF; NEED(2); WORLD; double amount;
	void *p = arg_packed(a[0],INTS);
	if (!p || !arg_num(a[1],amount)) { ret_bool(r,false); return; }
	const int64_t count=packed_size(size_ints,p);
	if (count <= 0 || count > w.soldier_count()) { ret_bool(r,false); return; }
	const int32_t *values=ints_read(p,0);
	const std::vector<int> members(values,values+count);
	ret_bool(r,w.charge_siege_round(members,amount));
}
void m_charge_siege_work(CALL_ARGS) {
	SELF; NEED(2); WORLD; int64_t i; double seconds;
	if (!arg_int(a[0],i) || i<0 || i>=w.soldier_count() || !arg_num(a[1],seconds)) { ret_bool(r,false); return; }
	ret_bool(r,w.charge_siege_work((int)i,seconds));
}
void m_contact_pose_state(CALL_ARGS) {
	SELF; NEED(1); WORLD; int64_t i;
	reset(r,DOUBLES);
	if (!arg_int(a[0],i) || i<0 || i>=w.soldier_count()) return;
	const float speed=std::hypot(w.vx[i],w.vy[i]);
	const int movement=speed>0.3f ? (speed>w.cfg.march_speed*1.2f ? 2 : 1) : 0;
	int slot; double age; w.contact_pose((int)i,movement,slot,age);
	const double values[2]={double(slot),age};
	void *p=internal[DOUBLES](r); packed_resize(resize_doubles,p,2);
	std::memcpy(doubles_write(p,0),values,sizeof(values));
}

void m_apply_environment_damage(CALL_ARGS) {
	SELF; NEED(2); WORLD; int64_t i;double d;
	if(!arg_int(a[0],i) || !arg_num(a[1],d) || i<0 || i>=w.soldier_count()) { ret_bool(r,false);return; }
	ret_bool(r,w.apply_environment_damage((int)i,d));
}
void m_order_owner(CALL_ARGS) { SELF; NEED(1); WORLD; int64_t i; ret_bool(r,arg_int(a[0],i) && i>=0 && i<(int64_t)w.formations.size() && w.formations[i].ai_enabled); }
void m_fire_host_protocol(CALL_ARGS) { SELF; NEED(0); WORLD; (void)w; ret_int(r,1); }
void m_set_host_ranged_delegate(CALL_ARGS) {
	SELF; NEED(1); WORLD; int64_t enabled;
	ret_bool(r,arg_int(a[0],enabled) && (enabled==0 || enabled==1) && w.set_host_ranged_delegate(enabled!=0));
}
void m_preview_host_ranged_batch(CALL_ARGS) {
	SELF; NEED(1); WORLD; reset(r,DOUBLES);
	void *input=arg_packed(a[0],LONGS);
	if (!input) return;
	const int64_t count=packed_size(size_longs,input);
	if (count<=0 || count%6!=0 || count/6>w.soldier_count()) return;
	std::vector<int64_t> releases(longs_read(input,0),longs_read(input,0)+count);
	return_doubles(r,w.preview_host_ranged_batch(releases));
}
void m_commit_host_ranged(CALL_ARGS) {
	SELF; NEED(7); WORLD; reset(r,DOUBLES);
	int64_t i,ammo,mode,id,x,y,power;
	if (!arg_int(a[0],i) || !arg_int(a[1],ammo) || !arg_int(a[2],mode) || !arg_int(a[3],id)
	    || !arg_int(a[4],x) || !arg_int(a[5],y) || !arg_int(a[6],power)
	    || i<0 || i>=w.soldier_count() || ammo<1 || ammo>65535 || mode<0 || mode>1
	    || x<0 || x>=w.terrain.w || y<0 || y>=w.terrain.h || (power!=0 && power!=1)) return;
	wg::rules::RangedShooter receipt;
	if (!w.commit_host_ranged(int(i),int(ammo),int(mode),id,int(x),int(y),power!=0,receipt)) return;
	return_doubles(r,{receipt.ability,receipt.training,receipt.fatigue,double(receipt.skill),double(w.ammo[i])});
}
void m_apply_host_projectile_contact(CALL_ARGS) {
	SELF; NEED(4); WORLD; int64_t i; double hp,stun,stagger;
	ret_bool(r,arg_int(a[0],i) && i>=0 && i<w.soldier_count() && arg_num(a[1],hp)
		&& arg_num(a[2],stun) && arg_num(a[3],stagger) && w.apply_host_projectile_contact(int(i),hp,stun,stagger));
}
void m_apply_fire_exposure_damage(CALL_ARGS) {
	SELF; NEED(2); WORLD; int64_t i; double hp;
	ret_bool(r,arg_int(a[0],i) && i>=0 && i<w.soldier_count() && arg_num(a[1],hp) && w.apply_fire_exposure_damage(int(i),hp));
}
void m_set_fire_visual_rows(CALL_ARGS) {
	SELF; NEED(2); WORLD;
	void *rows=arg_packed(a[0],INTS), *flags=arg_packed(a[1],BYTES);
	if (!rows || !flags || packed_size(size_ints,rows)!=packed_size(size_bytes,flags)) { ret_bool(r,false); return; }
	const int64_t count=packed_size(size_ints,rows);
	if (count>w.soldier_count()) { ret_bool(r,false); return; }
	std::vector<int> indices; std::vector<uint8_t> values;
	for (int64_t k=0;k<count;++k) { indices.push_back(*ints_read(rows,k)); values.push_back(*bytes_read(flags,k)); }
	ret_bool(r,w.set_fire_visual_rows(indices,values));
}
void m_fire_motion_segment(CALL_ARGS) {
	SELF; NEED(1); WORLD; reset(r,DOUBLES); int64_t i;
	if (!arg_int(a[0],i) || i<0 || i>=w.soldier_count()) return;
	const wg::MotionSegment segment=w.motion_segment(int(i));
	return_doubles(r,{segment.from_x,segment.from_y,segment.to_x,segment.to_y});
}

void m_has_projectiles(CALL_ARGS) { SELF; NEED(0); WORLD; ret_bool(r,!w.projectiles.empty()); }
void m_validate(CALL_ARGS) { SELF; NEED(0); WORLD; ret_bool(r,w.validate()); }
// state_hash_parts() -> the running state hash at each section end (diagnostics: which section two worlds differ in)
void m_hash_parts(CALL_ARGS) { SELF; NEED(0); WORLD; std::vector<int64_t> marks; w.state_hash(&marks); return_longs(r, marks); }
void m_person_ids(CALL_ARGS) { SELF; NEED(0); WORLD; return_longs(r,w.person_id); }
void m_soldier_index(CALL_ARGS) { SELF; NEED(1); WORLD; int64_t id; ret_int(r,arg_int(a[0],id) ? w.soldier_index(id) : -1); }
void m_blob_person_ids(CALL_ARGS) {
	SELF; NEED(1); void *v=arg_packed(a[0],BYTES); (void)self;
	if(!v) { return_longs(r,{});return; } const int64_t len=packed_size(size_bytes,v);
	if(len<=0 || len>16*1024*1024) { return_longs(r,{});return; }
	wg::World tmp(1); const uint8_t *bytes=bytes_read(v,0); const std::vector<uint8_t> blob(bytes,bytes+len);
	if(!tmp.load(blob)) { return_longs(r,{});return; } return_longs(r,tmp.person_id);
}
void return_ints(void *r,const std::vector<int32_t>&v) {
	reset(r,INTS);void *buf=internal[INTS](r);packed_resize(resize_ints,buf,(int64_t)v.size());
	if(!v.empty())std::memcpy(ints_write(buf,0),v.data(),v.size()*sizeof(int32_t));
}
void m_memberships(CALL_ARGS) {
	SELF;NEED(0);WORLD;std::vector<int32_t> v;v.reserve((size_t)w.soldier_count()*3);
	for(int i=0;i<w.soldier_count();++i){v.push_back(w.form[i]);v.push_back(w.team[i]);v.push_back(w.troop[i]);}return_ints(r,v);
}
void m_formation_count(CALL_ARGS) {SELF;NEED(0);WORLD;ret_int(r,(int64_t)w.formations.size());}
void m_formation_info(CALL_ARGS) {
	SELF;NEED(1);WORLD;int64_t i;
	if(!arg_int(a[0],i) || i<0 || i>=(int64_t)w.formations.size()){return_ints(r,{});return;}
	const auto &f=w.formations[i];return_ints(r,{f.team,(int)f.troop,(int)f.no_orders,(int)f.host_center,f.roster});
}
void m_build_id(CALL_ARGS) {
	SELF; NEED(0); (void)self; TextStorage id; make_string(&id,WG_CROWD_BUILD_ID);
	destroy(r); from_string(r,&id); destroy_string(&id);
}

// validate_reason() -> "" when the world validates, else the first failed validation check (diagnostics)
void m_validate_reason(CALL_ARGS) {
	SELF; NEED(0); WORLD; std::string error; const bool valid = w.validate(&error);
	TextStorage text; make_string(&text, valid ? "" : (error.empty() ? "invalid" : error.c_str()));
	destroy(r); from_string(r, &text); destroy_string(&text);
}

// ---------------------------------------------------------------- class registration
GDExtensionObjectPtr create(void *, GDExtensionBool) {
	GDExtensionObjectPtr object = construct_object(&parent_name);
	set_instance(object, &class_name, new Crowd());
	return object;
}
void free_instance(void *, GDExtensionClassInstancePtr p) { delete static_cast<Crowd *>(p); }

struct ArgSpec { GDExtensionVariantType type; const char *name; };
void add_method(const char *name, GDExtensionClassMethodCall fn, std::initializer_list<ArgSpec> args, GDExtensionVariantType ret) {
	TextStorage method_name, arg_names[10];
	GDExtensionPropertyInfo infos[10];
	GDExtensionClassMethodArgumentMetadata meta[10]{};
	make_name(&method_name, name, false);
	int k = 0;
	for (const ArgSpec &s : args) {
		make_name(&arg_names[k], s.name, false);
		infos[k] = {s.type, &arg_names[k], &empty_name, 0, &empty_string, 6};
		++k;
	}
	GDExtensionPropertyInfo ret_info{ret, &empty_name, &empty_name, 0, &empty_string, 6};
	GDExtensionClassMethodInfo info{};
	info.name = &method_name;
	info.call_func = fn;
	info.method_flags = GDEXTENSION_METHOD_FLAG_NORMAL;
	info.has_return_value = ret != NIL;
	info.return_value_info = &ret_info;
	info.argument_count = (uint32_t)k;
	info.arguments_info = infos;
	info.arguments_metadata = meta;
	register_method(library, &class_name, &info);
	for (int q = 0; q < k; ++q) destroy_name(&arg_names[q]);
	destroy_name(&method_name);
}

void initialize(void *, GDExtensionInitializationLevel level) {
	if (level != GDEXTENSION_INITIALIZATION_SCENE) return;
	make_name(&class_name, "ArmyCrowd", false);
	make_name(&parent_name, "RefCounted", false);
	make_name(&empty_name, "", false);
	make_string(&empty_string, "");
	GDExtensionClassCreationInfo4 info{};
	info.is_exposed = true;
	info.create_instance_func = create;
	info.free_instance_func = free_instance;
	register_class(library, &class_name, &parent_name, &info);
	add_method("setup", m_setup, {{INT, "threads"}, {INT, "seed"}}, BOOL);
	add_method("set_terrain", m_set_terrain, {{INT, "width"}, {INT, "height"}, {BYTES, "height_levels"}, {BYTES, "flags"}, {BYTES, "ramp_edges"},
	                                          {BYTES, "static_blocked"}, {BYTES, "facility"}}, BOOL);
	add_method("add_formation", m_add_formation, {{INT, "faction"}, {FLOAT, "cx"}, {FLOAT, "cy"}, {FLOAT, "facing"}, {INT, "cols"},
	                                              {FLOAT, "spacing"}, {INT, "troop"}, {FLOAT, "training"}}, INT);
	add_method("set_natural_heights", m_set_natural_heights, {{BYTES, "heights"}}, BOOL);
	add_method("terrain_state", m_terrain_state, {}, BYTES);
	add_method("get_occupancy_mask", m_occupancy_mask, {{LONGS, "ignored_person_ids"}}, BYTES);
	add_method("charge_custody_work", m_charge_custody_work, {{INT, "soldier"}, {FLOAT, "game_seconds"}}, BOOL);
	add_method("begin_structure_strike", m_begin_structure_strike, {{INT, "soldier"}, {INT, "target_cell"}}, BOOL);
	add_method("add_soldiers", m_add_soldiers, {{INT, "formation"}, {LONGS, "person_ids"}, {INTS, "equip"}, {BYTES, "roles"}, {INTS, "ammo"}}, INT);
	add_method("finalize", m_finalize, {}, BOOL);
	add_method("set_hostile", m_set_hostile, {{INT, "faction_a"}, {INT, "faction_b"}, {BOOL, "hostile"}}, BOOL);
	add_method("set_order_owner", m_set_owner, {{INT, "formation"}, {BOOL, "ai_owned"}}, BOOL);
	add_method("set_ai", m_set_ai, {{BOOL, "enabled"}}, BOOL);
	add_method("order", m_order, {{INT, "formation"}, {INT, "kind"}, {FLOAT, "gx"}, {FLOAT, "gy"}, {FLOAT, "facing_or_target"}}, INT);
	add_method("step", m_step, {{FLOAT, "dt"}}, BOOL);
	add_method("step_clock", m_step_clock, {{FLOAT, "dt"}, {FLOAT, "game_seconds"}, {FLOAT, "combat_left"}}, BOOL);
	add_method("step_clock_work_point", m_step_clock_work_point, {{FLOAT,"dt"},{FLOAT,"game_seconds"},{FLOAT,"combat_left"},{INT,"expected_tick"},{DOUBLES,"pools"}}, BOOL);
	add_method("validate_work_point_finish", m_validate_work_point_finish, {{INT,"expected_begin_tick"},{DOUBLES,"pools"}}, BOOL);
	add_method("prepare_work_point_finish", m_prepare_work_point_finish, {{INT,"expected_begin_tick"},{DOUBLES,"pools"}}, BOOL);
	add_method("publish_work_point_finish", m_publish_work_point_finish, {}, BOOL);
	add_method("work_point_state", m_work_point_state, {}, DOUBLES);
	add_method("work_fatigue_run_upper", m_work_fatigue_run_upper, {}, LONGS);
	add_method("work_point_runners", m_work_point_runners, {}, LONGS);
	add_method("work_training_start_ready", m_work_training_start_ready, {{INT,"formation"},{FLOAT,"combat_left_now"}}, BOOL);
	add_method("validate_work_point_training_plan", m_validate_work_point_training_plan, {{INT,"expected_begin_tick"},{DOUBLES,"training"}}, BOOL);
	add_method("prepare_work_point_training_plan", m_prepare_work_point_training_plan, {{INT,"expected_begin_tick"},{DOUBLES,"training"}}, BOOL);
	add_method("work_fatigue_state", m_work_fatigue_state, {{INT,"formation"}}, DOUBLES);
	add_method("work_fatigue_runners", m_work_fatigue_runners, {{INT,"formation"}}, LONGS);
	add_method("work_fatigue_rest_limit", m_work_fatigue_rest_limit, {{INT,"formation"},{FLOAT,"target"},{FLOAT,"maximum"},{FLOAT,"combat_left"}}, FLOAT);
	add_method("step_clock_work_plan", m_step_clock_work_plan, {{FLOAT,"dt"},{FLOAT,"game_seconds"},{FLOAT,"combat_left"},{INT,"expected_tick"},{DOUBLES,"pools"}}, BOOL);
	add_method("validate_step_clock_work_plan", m_validate_step_clock_work_plan, {{FLOAT,"dt"},{FLOAT,"game_seconds"},{FLOAT,"combat_left"},{INT,"expected_tick"},{DOUBLES,"pools"}}, BOOL);
	add_method("validate_step_clock_work_plan_after_host_ranged",m_validate_step_clock_work_plan_after_host_ranged,{{FLOAT,"dt"},{FLOAT,"game_seconds"},{FLOAT,"combat_left"},{INT,"expected_tick"},{DOUBLES,"pools"},{LONGS,"releases"},{DOUBLES,"preview"}},BOOL);
	add_method("pack_render", m_pack, {{FLOAT, "cell_pixels"}, {INT, "capacity"}}, FLOATS);
	add_method("peek_events", m_peek_events, {}, LONGS);
	add_method("event_fatigue", m_event_fatigue, {}, DOUBLES);
	add_method("drain_events", m_events, {}, LONGS);
	add_method("stats", m_stats, {}, DOUBLES);
	add_method("hud_stats", m_hud_stats, {}, DOUBLES);
	add_method("soldier_count", m_count, {}, INT);
	add_method("state_hash", m_hash, {}, INT);
	add_method("state_hash_parts", m_hash_parts, {}, LONGS);
	add_method("save_state", m_save, {}, BYTES);
	add_method("load_state", m_load, {{BYTES, "data"}}, BOOL);
	add_method("load_state_with_siege_navigation", m_load_with_siege_navigation, {{BYTES, "data"}, {INTS, "blocked"}, {LONGS, "wreck_exit"}}, BOOL);
	add_method("get_soldier_state", m_get_soldier_state, {{INT,"soldier"}}, DOUBLES);
	add_method("get_life_states", m_get_life_states, {}, DOUBLES);
	add_method("soldier_refs", m_soldier_refs, {{INT,"soldier"}}, LONGS);
	add_method("set_soldier_state", m_set_soldier_state, {{INT,"soldier"},{DOUBLES,"values"},{LONGS,"refs"}}, BOOL);
	add_method("escort_state", m_escort_state, {{INT,"soldier"}}, LONGS);
	add_method("contact_revision", m_contact_revision, {{INT,"soldier"}}, INT);
	add_method("set_contact_revision", m_set_contact_revision, {{INT,"soldier"},{INT,"revision"}}, BOOL);
	add_method("controlled_step_state", m_escort_state, {{INT,"soldier"}}, LONGS);
	add_method("siege_ground_cells",m_siege_ground_cells,{},LONGS);
	add_method("set_siege_crew_members",m_set_siege_crew_members,{{INTS,"soldier_indices"}},BOOL);
	add_method("set_siege_crew",m_set_siege_crew,{{INT,"soldier"},{BOOL,"assigned"}},BOOL);
	add_method("begin_siege_compound",m_begin_siege_compound,{{LONGS,"members"},{INTS,"source_body"},{INTS,"target_body"},{INTS,"sweep"},{FLOAT,"duration"}},INT);
	add_method("siege_compound_state",m_siege_compound_state,{{INT,"token"}},DOUBLES);
	add_method("siege_person_state",m_siege_person_state,{{INT,"soldier"}},LONGS);
	add_method("cancel_siege_compound",m_cancel_siege_compound,{{INT,"token"}},BOOL);
	add_method("settle_siege_compound",m_settle_siege_compound,{{INT,"token"}},BOOL);
	add_method("siege_busy",m_siege_busy,{},BOOL);
	add_method("siege_occupancy_mask",m_siege_occupancy_mask,{{LONGS,"ignored_person_ids"}},BYTES);
	add_method("set_siege_navigation",m_set_siege_navigation,{{INTS,"blocked"},{LONGS,"wreck_exit"}},BOOL);
	add_method("order_housing_step", m_order_housing_step, {{INT,"soldier"},{INT,"destination_cell"}}, BOOL);
	add_method("cancel_housing_step", m_cancel_housing_step, {{INT,"soldier"}}, BOOL);
	add_method("order_siege_step", m_order_siege_step, {{INT,"soldier"},{INT,"destination_cell"}}, BOOL);
	add_method("cancel_siege_step", m_cancel_siege_step, {{INT,"soldier"}}, BOOL);
	add_method("order_escort_step", m_order_escort_step, {{INT,"soldier"},{INT,"guard"},{INT,"destination_cell"}}, BOOL);
	add_method("cancel_escort", m_cancel_escort, {{INT,"soldier"}}, BOOL);
	add_method("admit_prison", m_admit_prison, {{INT,"soldier"},{INT,"guard"},{INT,"prison_id"},{INT,"slot_cell"},{INT,"contact_cell"}}, BOOL);
	add_method("release_prison", m_release_prison, {{INT,"soldier"},{INT,"executor"},{INT,"prison_id"},{INT,"contact_cell"},{INT,"exit_cell"}}, BOOL);
	add_method("get_formation_state", m_get_formation_state, {{INT,"formation"}}, DOUBLES);
	add_method("formation_refs", m_formation_refs, {{INT,"formation"}}, LONGS);
	add_method("set_formation_state", m_set_formation_state, {{INT,"formation"},{DOUBLES,"values"},{LONGS,"refs"}}, BOOL);
	add_method("order_serials", m_order_serials, {{INT,"formation"}}, LONGS);
	add_method("set_order_serials", m_set_order_serials, {{INT,"formation"},{INT,"order_serial"},{INT,"ranged_order_serial"}}, BOOL);
	add_method("set_garrisoned", m_set_garrisoned, {{INT,"formation"},{INT,"enabled"}}, BOOL);
	add_method("get_garrisoned", m_get_garrisoned, {{INT,"formation"}}, BOOL);
	add_method("set_formation_shape", m_set_formation_shape, {{INT,"formation"},{FLOATS,"offsets"}}, BOOL);
	add_method("get_formation_shape", m_get_formation_shape, {{INT,"formation"}}, INT);
	add_method("set_military_role", m_set_military_role, {{INT,"soldier"},{INT,"role"}}, BOOL);
	add_method("get_military_role", m_get_military_role, {{INT,"soldier"}}, INT);
	add_method("set_post_holder", m_set_post_holder, {{INT,"soldier"},{INT,"value"}}, BOOL);
	add_method("get_post_holder", m_get_post_holder, {{INT,"soldier"}}, INT);
	add_method("get_soldier_presence", m_get_soldier_presence, {{INT,"soldier"}}, BOOL);
	add_method("apply_training_state", m_apply_training_state, {{INT,"formation"},{FLOAT,"before_training"},{FLOAT,"before_fatigue"},{FLOAT,"before_rest"},{FLOAT,"training"},{FLOAT,"fatigue"},{FLOAT,"rest"},{INT,"worked"}}, BOOL);
	add_method("set_soldier_equip", m_set_soldier_equip, {{INT,"soldier"},{INT,"packed_equip"}}, BOOL);
	add_method("set_soldier_ammo", m_set_soldier_ammo, {{INT,"soldier"},{INT,"ammo"}}, BOOL);
	add_method("set_sustain_input", m_set_sustain_input, {{INT,"formation"},{BOOL,"fully_fed"},{FLOAT,"morale_delta"}}, BOOL);
	add_method("set_housing_attendance_input", m_set_housing_attendance_input, {{INT,"soldier"},{INT,"home_cell"}}, BOOL);
	add_method("set_housing_recovery_input", m_set_housing_recovery_input, {{INT,"formation"},{FLOAT,"multiplier"}}, BOOL);
	add_method("set_recovery_input", m_set_recovery_input, {{INT,"formation"},{FLOAT,"multiplier"}}, BOOL);
	add_method("set_fire_safe_rest_input", m_set_fire_safe_rest_input, {{INT,"formation"},{BOOL,"safe"}}, BOOL);
	add_method("apply_siege_contact",m_apply_siege_contact,{{INT,"soldier"},{FLOAT,"hp_loss"},{FLOAT,"stun_add"},{FLOAT,"stagger"}},BOOL);
	add_method("apply_melee_contact",m_apply_melee_contact,{{INT,"soldier"},{FLOAT,"hp_loss"},{FLOAT,"stun_add"}},BOOL);
	add_method("set_aboard_melee_pairs", m_set_aboard_melee_pairs, {{INTS, "pairs"}}, BOOL);
	add_method("charge_exchange_fatigue",m_charge_exchange_fatigue,{{INT,"soldier"},{FLOAT,"amount"}},BOOL);
	add_method("site_person_exit_ready",m_site_person_exit_ready,{{INT,"soldier"}},BOOL);
	add_method("site_person_release",m_site_person_release,{{INT,"soldier"}},DOUBLES);
	add_method("site_person_exit_ready_aboard",m_site_person_exit_ready_aboard,{{INT,"soldier"},{INT,"vehicle"}},BOOL);
	add_method("site_person_release_aboard",m_site_person_release_aboard,{{INT,"soldier"},{INT,"vehicle"}},DOUBLES);
	add_method("site_person_release_dead",m_site_person_release_dead,{{INT,"soldier"}},DOUBLES);
	add_method("site_person_retag_released",m_site_person_retag_released,{{INT,"soldier"},{INT,"placeholder"}},BOOL);
	add_method("site_person_readmit",m_site_person_readmit,{{INT,"soldier"},{INT,"formation"},{INT,"packed_equip"},{INT,"role"},{INT,"ammo"}},BOOL);
	add_method("site_formation_reuse",m_site_formation_reuse,{{INT,"formation"},{INT,"faction"},{FLOAT,"cx"},{FLOAT,"cy"},{FLOAT,"facing"},{INT,"cols"},{FLOAT,"spacing"},{INT,"troop"},{FLOAT,"training"}},BOOL);
	add_method("site_person_board",m_site_person_board,{{INT,"soldier"},{INT,"vehicle"}},BOOL);
	add_method("site_person_land",m_site_person_land,{{INT,"soldier"},{FLOAT,"x"},{FLOAT,"y"}},BOOL);
	add_method("site_person_set_deck",m_site_person_set_deck,{{INT,"soldier"},{FLOAT,"x"},{FLOAT,"y"}},BOOL);
	add_method("site_person_retarget_aboard",m_site_person_retarget_aboard,{{INT,"soldier"},{INT,"vehicle"}},BOOL);
	add_method("site_person_aboard",m_site_person_aboard,{{INT,"soldier"}},DOUBLES);
	add_method("site_person_absent",m_site_person_absent,{{INT,"soldier"},{INT,"kind"}},BOOL);
	add_method("site_person_return",m_site_person_return,{{INT,"soldier"},{INT,"formation"},{FLOAT,"x"},{FLOAT,"y"}},BOOL);
	add_method("move_member",m_move_member,{{INT,"soldier"},{INT,"to_formation"}},BOOL);
	add_method("transfer_member",m_transfer_member,{{INT,"soldier"},{INT,"to_formation"}},BOOL);
	add_method("leave_member",m_leave_member,{{INT,"soldier"},{INT,"to_formation"}},BOOL);
	add_method("last_striker",m_last_striker,{{INT,"soldier"}},INT);
	add_method("site_person_absent_state",m_site_person_absent_state,{{INT,"soldier"}},DOUBLES);
	add_method("soldier_surrendered",m_soldier_surrendered,{{INT,"soldier"}},BOOL);
	add_method("set_soldier_surrendered",m_set_soldier_surrendered,{{INT,"soldier"},{INT,"on"}},BOOL);
	add_method("soldier_mounted",m_soldier_mounted,{{INT,"soldier"}},BOOL);
	add_method("set_soldier_mounted",m_set_soldier_mounted,{{INT,"soldier"},{INT,"on"}},BOOL);
	add_method("cav_stats",m_cav_stats,{},DOUBLES);
	add_method("soldier_charge",m_soldier_charge,{{INT,"soldier"}},DOUBLES);
	add_method("add_convoy", m_add_convoy, {{FLOAT,"anchor_x"},{FLOAT,"anchor_y"},{FLOAT,"facing"}}, INT);
	add_method("convoy_set_crew", m_convoy_set_crew, {{INT,"convoy"},{INT,"soldier"},{INT,"offset_x"},{INT,"offset_y"},{BOOL,"assigned"}}, BOOL);
	add_method("convoy_order_goal", m_convoy_order_goal, {{INT,"convoy"},{FLOAT,"goal_x"},{FLOAT,"goal_y"},{FLOAT,"goal_facing"}}, BOOL);
	add_method("convoy_set_body", m_convoy_set_body, {{INT,"convoy"},{INTS,"cells"}}, BOOL);
	add_method("convoy_crew", m_convoy_crew, {{INT,"convoy"}}, DOUBLES);
	add_method("convoy_state", m_convoy_state, {{INT,"convoy"}}, DOUBLES);
	add_method("convoy_body", m_convoy_body, {{INT,"convoy"}}, INTS);
	add_method("convoy_remove", m_convoy_remove, {{INT,"convoy"}}, BOOL);
	add_method("convoy_attach_formation", m_convoy_attach_formation, {{INT,"convoy"},{INT,"formation"}}, BOOL);
	add_method("convoy_detach_formation", m_convoy_detach_formation, {{INT,"convoy"}}, BOOL);
	add_method("convoy_formation", m_convoy_formation, {{INT,"convoy"}}, INT);
	add_method("convoy_goal", m_convoy_goal, {{INT,"convoy"}}, DOUBLES);
	add_method("soldier_slot_target", m_soldier_slot_target, {{INT,"soldier"}}, DOUBLES);
	add_method("convoy_claim_cells", m_convoy_claim_cells, {}, INTS);
	add_method("charge_siege_round",m_charge_siege_round,{{INTS,"members"},{FLOAT,"per_person"}},BOOL);
	add_method("charge_siege_work",m_charge_siege_work,{{INT,"soldier"},{FLOAT,"game_seconds"}},BOOL);
	add_method("contact_pose_state",m_contact_pose_state,{{INT,"soldier"}},DOUBLES);
	add_method("apply_environment_damage", m_apply_environment_damage, {{INT,"soldier"},{FLOAT,"amount"}}, BOOL);
	add_method("order_owner", m_order_owner, {{INT,"formation"}}, BOOL);
	add_method("fire_host_protocol",m_fire_host_protocol,{},INT);
	add_method("set_host_ranged_delegate",m_set_host_ranged_delegate,{{BOOL,"enabled"}},BOOL);
	add_method("preview_host_ranged_batch",m_preview_host_ranged_batch,{{LONGS,"releases"}},DOUBLES);
	add_method("commit_host_ranged",m_commit_host_ranged,{{INT,"soldier"},{INT,"expected_ammo"},{INT,"mode"},{INT,"release_id"},{INT,"target_x"},{INT,"target_y"},{BOOL,"auto_power"}},DOUBLES);
	add_method("apply_host_projectile_contact",m_apply_host_projectile_contact,{{INT,"soldier"},{FLOAT,"hp"},{FLOAT,"stun"},{FLOAT,"stagger"}},BOOL);
	add_method("apply_fire_exposure_damage",m_apply_fire_exposure_damage,{{INT,"soldier"},{FLOAT,"hp"}},BOOL);
	add_method("set_fire_visual_rows",m_set_fire_visual_rows,{{INTS,"soldiers"},{BYTES,"flags"}},BOOL);
	add_method("fire_motion_segment",m_fire_motion_segment,{{INT,"soldier"}},DOUBLES);
	add_method("has_projectiles", m_has_projectiles, {}, BOOL);
	add_method("validate", m_validate, {}, BOOL);
	add_method("validate_reason", m_validate_reason, {}, STRING);
	add_method("person_ids", m_person_ids, {}, LONGS);
	add_method("person_ground_cells", m_siege_ground_cells, {}, LONGS);
	add_method("soldier_index", m_soldier_index, {{INT,"person_id"}}, INT);
	add_method("blob_person_ids", m_blob_person_ids, {{BYTES,"blob"}}, LONGS);
	add_method("memberships",m_memberships,{},INTS);
	add_method("formation_count",m_formation_count,{},INT);
	add_method("formation_info",m_formation_info,{{INT,"formation"}},INTS);
	add_method("build_id", m_build_id, {}, STRING);
	add_method("render_clear", m_render_clear, {}, BOOL);
	add_method("render_add_track", m_render_add_track, {{INT, "sequence"}, {FLOAT, "duration"}, {BOOL, "loop"}, {FLOATS, "times"},
	                                                    {FLOATS, "anchors_xy"}, {FLOATS, "time_map"}, {FLOAT, "map_step"}}, INT);
	add_method("render_add_kit", m_render_add_kit, {{INT, "page"}, {INT, "palette"}, {FLOAT, "scale"}, {INTS, "tracks"}}, INT);
	add_method("render_set_kits", m_render_set_kits, {{INTS, "kits"}}, BOOL);
	add_method("render_set_windows", m_render_set_windows, {{FLOATS, "windows"}}, BOOL);
	add_method("pack_rows", m_pack_rows, {{FLOAT, "cell_pixels"}}, FLOATS);
	add_method("row_spans", m_row_spans, {}, INTS);
	add_method("row_bounds", m_row_bounds, {}, FLOATS);
	add_method("last_rows_ms", m_rows_ms, {}, FLOAT);
	add_method("row_grounds", m_row_grounds, {}, FLOATS);
	add_method("set_host_control", m_set_host_control, {{INT, "soldier"}, {BOOL, "enabled"}}, BOOL);
	add_method("host_input", m_host_input, {{INT, "soldier"}, {FLOAT, "wish_vx"}, {FLOAT, "wish_vy"}, {BOOL, "run"}, {BOOL, "engage"}}, BOOL);
	add_method("soldier_view", m_soldier_view, {{INT, "soldier"}}, FLOATS);
	add_method("nearest_enemy", m_nearest_enemy, {{INT, "soldier"}, {FLOAT, "radius"}}, INT);
	add_method("combat_mark", m_combat_mark, {}, FLOAT);
	add_method("set_start_positions", m_set_start_positions, {{INT, "first_soldier"}, {FLOATS, "xy"}}, BOOL);
	add_method("set_blockers", m_set_blockers, {{FLOATS, "blockers_xyr"}}, BOOL);
	add_method("standing_near", m_standing_near, {{FLOAT, "x"}, {FLOAT, "y"}, {FLOAT, "radius"}}, INT);
	add_method("pack_frame", m_pack_frame, {{FLOAT, "cell_pixels"}, {FLOAT, "frame_seconds"}}, FLOATS);
	add_method("render_set_filter", m_render_set_filter, {{BOOL, "enabled"}}, BOOL);
	add_method("render_set_actors", m_render_set_actors, {{FLOATS, "grounds_xy"}}, BOOL);
	add_method("render_set_bands", m_render_set_bands, {{INT, "bands"}}, BOOL);
}
void deinitialize(void *, GDExtensionInitializationLevel level) {
	if (level != GDEXTENSION_INITIALIZATION_SCENE) return;
	unregister_class(library, &class_name);
	destroy_string(&empty_string);
	destroy_name(&empty_name);
	destroy_name(&parent_name);
	destroy_name(&class_name);
}

} // namespace

#ifdef _WIN32
#define CROWD10K_EXPORT __declspec(dllexport)
#else
#define CROWD10K_EXPORT __attribute__((visibility("default")))
#endif
extern "C" CROWD10K_EXPORT GDExtensionBool crowd10k_init(GDExtensionInterfaceGetProcAddress get, GDExtensionClassLibraryPtr lib,
                                                              GDExtensionInitialization *init) {
	library = lib;
#define LOAD(variable, api_type, name) variable = reinterpret_cast<api_type>(get(name)); if (!variable) return false
	LOAD(type_of, GDExtensionInterfaceVariantGetType, "variant_get_type");
	LOAD(destroy, GDExtensionInterfaceVariantDestroy, "variant_destroy");
	LOAD(variant_construct, GDExtensionInterfaceVariantConstruct, "variant_construct");
	LOAD(construct_object, GDExtensionInterfaceClassdbConstructObject2, "classdb_construct_object2");
	LOAD(set_instance, GDExtensionInterfaceObjectSetInstance, "object_set_instance");
	LOAD(register_class, GDExtensionInterfaceClassdbRegisterExtensionClass4, "classdb_register_extension_class4");
	LOAD(unregister_class, GDExtensionInterfaceClassdbUnregisterExtensionClass, "classdb_unregister_extension_class");
	LOAD(register_method, GDExtensionInterfaceClassdbRegisterExtensionClassMethod, "classdb_register_extension_class_method");
	LOAD(make_name, GDExtensionInterfaceStringNameNewWithLatin1Chars, "string_name_new_with_latin1_chars");
	LOAD(make_string, GDExtensionInterfaceStringNewWithLatin1Chars, "string_new_with_latin1_chars");
	LOAD(bytes_write, GDExtensionInterfacePackedByteArrayOperatorIndex, "packed_byte_array_operator_index");
	LOAD(bytes_read, GDExtensionInterfacePackedByteArrayOperatorIndexConst, "packed_byte_array_operator_index_const");
	LOAD(ints_read, GDExtensionInterfacePackedInt32ArrayOperatorIndexConst, "packed_int32_array_operator_index_const");
	LOAD(ints_write, GDExtensionInterfacePackedInt32ArrayOperatorIndex, "packed_int32_array_operator_index");
	LOAD(floats_read, GDExtensionInterfacePackedFloat32ArrayOperatorIndexConst, "packed_float32_array_operator_index_const");
	LOAD(longs_write, GDExtensionInterfacePackedInt64ArrayOperatorIndex, "packed_int64_array_operator_index");
	LOAD(longs_read, GDExtensionInterfacePackedInt64ArrayOperatorIndexConst, "packed_int64_array_operator_index_const");
	LOAD(floats_write, GDExtensionInterfacePackedFloat32ArrayOperatorIndex, "packed_float32_array_operator_index");
	LOAD(doubles_write, GDExtensionInterfacePackedFloat64ArrayOperatorIndex, "packed_float64_array_operator_index");
	LOAD(doubles_read, GDExtensionInterfacePackedFloat64ArrayOperatorIndexConst, "packed_float64_array_operator_index_const");
	GDExtensionInterfaceGetVariantGetInternalPtrFunc get_internal;
	GDExtensionInterfaceGetVariantFromTypeConstructor get_constructor;
	GDExtensionInterfaceVariantGetPtrDestructor get_destructor;
	GDExtensionInterfaceVariantGetPtrBuiltinMethod get_method;
	LOAD(get_internal, GDExtensionInterfaceGetVariantGetInternalPtrFunc, "variant_get_ptr_internal_getter");
	LOAD(get_constructor, GDExtensionInterfaceGetVariantFromTypeConstructor, "get_variant_from_type_constructor");
	LOAD(get_destructor, GDExtensionInterfaceVariantGetPtrDestructor, "variant_get_ptr_destructor");
	LOAD(get_method, GDExtensionInterfaceVariantGetPtrBuiltinMethod, "variant_get_ptr_builtin_method");
#undef LOAD
	for (auto t : {BOOL, INT, FLOAT, BYTES, INTS, LONGS, FLOATS, DOUBLES}) {
		internal[t] = get_internal(t);
		if (!internal[t]) return false;
	}
	from_int = get_constructor(INT); from_float = get_constructor(FLOAT); from_bool = get_constructor(BOOL); from_string = get_constructor(STRING);
	destroy_string = get_destructor(GDEXTENSION_VARIANT_TYPE_STRING);
	destroy_name = get_destructor(GDEXTENSION_VARIANT_TYPE_STRING_NAME);
	auto builtin = [&](GDExtensionVariantType type, const char *name, int64_t hash) {
		TextStorage m;
		make_name(&m, name, false);
		auto fn = get_method(type, &m, hash);
		destroy_name(&m);
		return fn;
	};
	// hashes as used by native/army_idle for the same 4.7.2 API
	size_bytes = builtin(BYTES, "size", 3173160232);
	size_ints = builtin(INTS, "size", 3173160232);
	size_longs = builtin(LONGS, "size", 3173160232);
	size_floats = builtin(FLOATS, "size", 3173160232);
	size_doubles = builtin(DOUBLES, "size", 3173160232);
	resize_ints = builtin(INTS, "resize", 848867239);
	resize_bytes = builtin(BYTES, "resize", 848867239);
	resize_longs = builtin(LONGS, "resize", 848867239);
	resize_floats = builtin(FLOATS, "resize", 848867239);
	resize_doubles = builtin(DOUBLES, "resize", 848867239);
	if (!from_string || !size_doubles || !from_int || !from_float || !from_bool || !destroy_string || !destroy_name || !size_bytes || !size_ints || !size_longs || !size_floats || !resize_ints ||
	    !resize_bytes || !resize_longs || !resize_floats || !resize_doubles)
		return false;
	init->minimum_initialization_level = GDEXTENSION_INITIALIZATION_SCENE;
	init->userdata = nullptr;
	init->initialize = initialize;
	init->deinitialize = deinitialize;
	return true;
}
