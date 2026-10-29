// Person / formation state import-export (SiteStore boundary) and complete save / load.
//
// Save format: a flat little-endian byte stream of every field that feeds the next step, written and
// read by the same field list (World::serialize), so the two can never drift apart. It is valid for the
// same build only (no versioning across builds). Flow fields are not stored: the goal cells, the
// build state and the request queue are, and built fields are rebuilt on load (the build is
// deterministic), so later movement is identical.
#include "crowd_core.hpp"

#include <algorithm>
#include <cstring>
#include <type_traits>
#include <unordered_map>
#include <unordered_set>
#include <limits>
#include <new>

namespace wg {

namespace {

struct Writer {
	std::vector<uint8_t> out;
	bool ok = true;
	static constexpr bool loading = false;
	void pod(const bool &v) { const uint8_t b = v ? 1 : 0; pod(b); }
	template <class T> void pod(const T &v) {
		static_assert(std::is_trivially_copyable<T>::value, "pod");
		const uint8_t *b = (const uint8_t *)&v;
		out.insert(out.end(), b, b + sizeof(T));
	}
	template <class T> void vec(const std::vector<T> &v) {
		uint64_t n = v.size();
		pod(n);
		if (n) { const uint8_t *b = (const uint8_t *)v.data(); out.insert(out.end(), b, b + n * sizeof(T)); }
	}
};

struct Reader {
	const std::vector<uint8_t> &in;
	size_t at = 0;
	bool ok = true;
	static constexpr bool loading = true;
	explicit Reader(const std::vector<uint8_t> &b) : in(b) {}
	void pod(bool &v) { uint8_t b = 0; pod(b); if (b > 1) { ok = false; return; } v = b != 0; }
	template <class T> void pod(T &v) {
		if (!ok || sizeof(T) > in.size() - at) { ok = false; return; }
		std::memcpy(&v, in.data() + at, sizeof(T));
		at += sizeof(T);
	}
	template <class T> void vec(std::vector<T> &v) {
		uint64_t n = 0;
		pod(n);
		if (!ok || n > 1048576 || n > (in.size() - at) / std::max<size_t>(1, sizeof(T))) { ok = false; return; }
		v.resize((size_t)n);
		if (n) std::memcpy(v.data(), in.data() + at, (size_t)n * sizeof(T));
		at += (size_t)n * sizeof(T);
	}
};

template <class Ar> bool count(Ar &ar, uint64_t n, size_t minimum, uint64_t cap) {
	if constexpr (Ar::loading) { if (!ar.ok || n > cap || n > (ar.in.size() - ar.at) / minimum) { ar.ok = false; return false; } }
	return ar.ok;
}
template <class Ar> void io_equip(Ar &ar, rules::Equip &e) {
	ar.pod(e.family); ar.pod(e.material); ar.pod(e.armor); ar.pod(e.shield);
}
template <class Ar> void io_config(Ar &ar, Config &c) {
	ar.pod(c.radius);
	ar.pod(c.wall_margin);
	ar.pod(c.march_speed);
	ar.pod(c.run_speed);
	ar.pod(c.max_turn_rate);
	ar.pod(c.engage_radius);
	ar.pod(c.reach);
	ar.pod(c.leash);
	ar.pod(c.encircle_cells);
	ar.pod(c.encircle_budget);
	ar.pod(c.ranged_keep);
	ar.pod(c.ranged_leash);
	ar.pod(c.ally_push);
	ar.pod(c.enemy_push);
	ar.pod(c.push_clamp);
	ar.pod(c.los_period);
	ar.pod(c.contact_period);
	ar.pod(c.los_max_cells);
	ar.pod(c.chunk);
	ar.pod(c.max_fields_per_step);
	ar.pod(c.ko_seconds);
	ar.pod(c.rescued_ko_seconds);
	ar.pod(c.bleed_per_game_hour);
	ar.pod(c.rescue_seek_cells);
	ar.pod(c.auto_capture);
	ar.pod(c.capture_seek_cells);
	ar.pod(c.speed);
	ar.pod(c.combat_grace);
	ar.pod(c.shot_grace);
	ar.pod(c.seed);
	ar.pod(c.ai);
}
template <class Ar> void io_projectile(Ar &ar, Projectile &p) {
	ar.pod(p.shooter); ar.pod(p.faction); ar.pod(p.shooter_id); ar.pod(p.shot_id);
	ar.pod(p.source.x); ar.pod(p.source.y); ar.pod(p.target.x); ar.pod(p.target.y); ar.pod(p.left); ar.pod(p.source_eye); ar.pod(p.goal_eye);
	ar.pod(p.stats.ability); ar.pod(p.stats.training); ar.pod(p.stats.fatigue); ar.pod(p.stats.skill); io_equip(ar, p.stats.equip);
}
// std::vector<bool>-free helpers for nested vectors
template <class Ar, class T> void nested(Ar &ar, std::vector<std::vector<T>> &v) {
	uint64_t n = v.size();
	ar.pod(n);
	if (!count(ar, n, sizeof(uint64_t), 65537)) return;
	if (Ar::loading) v.resize((size_t)n);
	for (auto &x : v) ar.vec(x);
}

template <class Ar> void io_formation(Ar &ar, Formation &f) {
	ar.pod(f.team); ar.pod(f.troop); ar.pod(f.order); ar.pod(f.cx); ar.pod(f.cy); ar.pod(f.facing);
	ar.pod(f.goal_x); ar.pod(f.goal_y); ar.pod(f.goal_facing); ar.pod(f.cols); ar.pod(f.spacing); ar.pod(f.field);
	ar.pod(f.arrived); ar.pod(f.los_goal); ar.pod(f.lag); ar.vec(f.members); ar.pod(f.roster); ar.pod(f.slot_count);
	ar.pod(f.compact_t);
	ar.pod(f.target_person); ar.pod(f.origin_x); ar.pod(f.origin_y); ar.pod(f.pursuit_left); ar.pod(f.order_delay);
	ar.pod(f.attacking); ar.pod(f.needs_attack_order);
	ar.pod(f.formal_cmd); ar.pod(f.acting_cmd); ar.pod(f.current_cmd); ar.vec(f.officer_order); ar.pod(f.command_dirty);
	ar.pod(f.ref_x); ar.pod(f.ref_y); ar.pod(f.ref_valid); ar.pod(f.rng);
	ar.pod(f.training); ar.pod(f.morale); ar.pod(f.rally_rest); ar.pod(f.routed); ar.pod(f.fatigue); ar.pod(f.fatigue_rest);
	ar.pod(f.fatigue_count); ar.pod(f.charged_this_step);
	ar.pod(f.contact_age); ar.pod(f.in_contact); ar.pod(f.threat); ar.pod(f.ai_enabled); ar.pod(f.ai_recovering);
	ar.pod(f.ai_order_cd); ar.pod(f.ai_chase_cd); ar.pod(f.ai_target); ar.pod(f.ai_status); ar.pod(f.encircle_t);
	ar.pod(f.commander_present); ar.pod(f.resupplying);
	ar.pod(f.no_orders); ar.pod(f.host_center); ar.pod(f.fully_fed); ar.pod(f.sustain_morale_delta);
	ar.pod(f.garrisoned);
	ar.pod(f.reslot_pending); ar.pod(f.rest_gx); ar.pod(f.rest_gy); ar.pod(f.rest_gf); ar.pod(f.rest_slots);
}
template <class Ar> void io_convoy(Ar &ar, Convoy &c) {
	ar.pod(c.id); ar.pod(c.x); ar.pod(c.y); ar.pod(c.facing);
	ar.pod(c.has_goal); ar.pod(c.gx); ar.pod(c.gy); ar.pod(c.gfacing); ar.pod(c.goal_cell); ar.pod(c.field);
	ar.vec(c.crew); ar.vec(c.body); ar.pod(c.body_stalled); ar.pod(c.stall_reason); // body_cells are derived on load (rebuild_convoy_bodies); stall_reason is saved so the reported pose matches after load
	// KW13: formation following (layout key, slot, wait counter, route region and route cost field, claimed cells)
	ar.pod(c.formation); ar.pod(c.key_gx); ar.pod(c.key_gy); ar.pod(c.key_q); ar.pod(c.key_slots); ar.pod(c.key_count);
	ar.pod(c.slot_index); ar.pod(c.blocked); ar.pod(c.no_slot); ar.pod(c.turn_to); ar.pod(c.move_to);
	ar.pod(c.plan_x0); ar.pod(c.plan_y0); ar.pod(c.plan_w); ar.pod(c.plan_h); ar.vec(c.plan_cost); ar.vec(c.claim);
}

} // namespace

template <class Ar> void World::serialize(Ar &ar) {
	const uint32_t magic = 0x3431574Bu; // "KW14": aboard soldiers (G1 S1 site boarding); KW13: convoy formation following (G4 OPUS); KW12: convoy stall_reason (G4 S4f); KW11: convoy body offsets, body_stalled, body-aware flow fields (G4 S2); KW10: logistics convoys (G4); KW09: released soldiers (G6.4 site exit); KW08: per-person post holder (R1b)
	uint32_t m = magic;
	ar.pod(m);
	if (Ar::loading && m != magic) { ar.ok = false; return; }
	io_config(ar, cfg);
	// terrain (static during a battle, stored so a save is self-contained)
	ar.pod(terrain.w); ar.pod(terrain.h);
	ar.vec(terrain.height); ar.vec(terrain.flags); ar.vec(terrain.ramp_edges); ar.vec(terrain.static_blocked);
	ar.vec(terrain.facility); ar.vec(terrain.edge_ok); ar.vec(terrain.base_height);
	// formations
	uint64_t nf = formations.size();
	ar.pod(nf);
	if (!count(ar, nf, 128, 65537)) return;
	if (Ar::loading) formations.resize((size_t)nf);
	for (auto &f : formations) io_formation(ar, f);
	// soldiers
	for (auto *v : {&px, &py, &nx, &ny, &vx, &vy, &face, &anim_t, &knock_dx, &knock_dy}) ar.vec(*v);
	ar.vec(rest_hold); ar.vec(rest_x); ar.vec(rest_y); ar.vec(rest_best); ar.vec(rest_t);
	for (auto *v : {&hp, &stun, &grace, &ko, &getup, &stagger, &exch_cd, &ranged_cd, &skill_cd, &knock_t, &act_t, &escape_t}) ar.vec(*v);
	for (auto *v : {&team, &state, &los_ok, &skill, &role, &captive, &present, &troop, &running, &near_enemy, &fire_blocked, &bandaged, &life_ck})
		ar.vec(*v);
	for (auto *v : {&form, &slot, &target, &cell, &enc_target, &rescue_of, &capture_of, &captor, &rescued_by_, &capturing_by_}) ar.vec(*v);
	ar.vec(prison_id); ar.vec(escort_goal); ar.vec(escort_mode);
	ar.vec(contact_revision);
	for (auto *v : {&host_ctl, &host_run, &host_engage}) ar.vec(*v);
	ar.vec(host_vx); ar.vec(host_vy);
	ar.vec(ammo);
	uint64_t neq = equip.size(); ar.pod(neq); if (!count(ar, neq, 4, 65536)) return;
	if (Ar::loading) equip.resize((size_t)neq); for (auto &e : equip) io_equip(ar, e);
	ar.vec(ability); ar.vec(person_id);
	ar.vec(military_role);
	ar.vec(post_holder);
	ar.vec(released);
	ar.vec(aboard); ar.vec(aboard_vehicle);
	ar.vec(events);
	uint64_t np = projectiles.size(); ar.pod(np); if (!count(ar, np, 65, 65536)) return;
	if (Ar::loading) projectiles.resize((size_t)np); for (auto &p : projectiles) io_projectile(ar, p);
	ar.vec(rescuers_); ar.vec(capturers_); ar.vec(captives_);
	// world clocks and counters
	ar.pod(tick); ar.pod(exchange_round); ar.pod(shot_serial); ar.pod(time);
	ar.pod(host_ranged_delegate); ar.pod(host_last_release_id);
	ar.pod(combat_left); ar.pod(game_dt); ar.pod(combat_mark); ar.pod(external_clock);
	ar.pod(stats);
	ar.vec(hostile_);
	// persistent private state read across steps
	ar.vec(slot_tx_); ar.vec(slot_ty_); ar.vec(slot_clip_);
	ar.vec(lag_acc_); ar.vec(lag_cnt_);
	ar.vec(attackers_); ar.pod(attackers_tick_); ar.vec(touch_);
	ar.vec(field_queue_);
	// flow fields: goal / use stamp / built flag; built ones are rebuilt on load
	uint64_t nfield = fields_.size();
	ar.pod(nfield);
	if (!count(ar, nfield, 9, 256)) return;
	if (Ar::loading) fields_.assign((size_t)nfield, FlowField{});
	for (auto &fl : fields_) {
		uint8_t built = fl.dir.empty() ? 0 : 1;
		ar.pod(fl.goal); ar.pod(fl.last_used); ar.pod(built); ar.pod(fl.body_aware);
		if (built > 1) { ar.ok = false; return; }
		if (Ar::loading) { fl.cost.clear(); fl.dir.clear(); if (built) fl.dir.push_back(1); /* marker, rebuilt below */ }
	}
	// G4 logistics convoys (KW10): id counter, per-soldier membership, then the records.
	ar.pod(convoy_serial);
	ar.vec(convoy_of);
	uint64_t nconvoy = convoys.size();
	ar.pod(nconvoy);
	if (!count(ar, nconvoy, 48, 256)) return;
	if (Ar::loading) convoys.resize((size_t)nconvoy);
	for (auto &cv : convoys) io_convoy(ar, cv);
}

std::vector<uint8_t> World::save() const {
	if (work_point_active_) return {}; // Same original unfinished point is unsaveable.
	if (!siege_compounds.empty()) return {};
	// Transient Site jobs are unsaveable while a step is still moving (a goal is set). An arrived, held housing or
	// siege step (G10, Nekki 2026-10-30 A: workers save at their station) is saved and restored as held.
	for (int i = 0; i < soldier_count(); ++i) if (escort_mode[i] >= 3 && !held_site_step(i)) return {};
	Writer w;
	const_cast<World *>(this)->serialize(w);
	return std::move(w.out);
}

bool World::validate(std::string *error, bool allow_site_jobs) const {
#define CHECK_VALID(c) do { if (!(c)) { if (error) *error = #c; return false; } } while (false)
	const size_t n = px.size(), nf = formations.size();
	CHECK_VALID(terrain.w > 0 && terrain.h > 0 && terrain.w <= 1024 && terrain.h <= 1024);
	const size_t cells = (size_t)terrain.w * terrain.h;
	CHECK_VALID(n <= 65536 && nf <= n + 1);
	for (auto *v : {&terrain.height, &terrain.flags, &terrain.ramp_edges, &terrain.static_blocked, &terrain.facility, &terrain.edge_ok}) CHECK_VALID(v->size() == cells);
	CHECK_VALID(terrain.base_height.empty() || terrain.base_height.size() == cells);
	for (uint8_t v : terrain.static_blocked) CHECK_VALID(v <= 1);
	for (uint8_t v : terrain.facility) CHECK_VALID(v <= 1);
	Terrain edges = terrain; edges.build_edges(); CHECK_VALID(edges.edge_ok == terrain.edge_ok);
	for (int v : {cfg.chunk, cfg.los_period, cfg.contact_period, cfg.los_max_cells, cfg.max_fields_per_step}) CHECK_VALID(v >= 1 && v <= 65536);
	CHECK_VALID(cfg.encircle_budget >= 0 && cfg.encircle_budget <= 65536);
	CHECK_VALID(cfg.wall_margin <= 0.5f);
	for (double v : {double(cfg.radius),double(cfg.march_speed),double(cfg.run_speed),double(cfg.reach),cfg.speed,cfg.ko_seconds,cfg.rescued_ko_seconds}) CHECK_VALID(std::isfinite(v) && v > 0 && v <= 1e9);
	for (double v : {double(cfg.wall_margin),double(cfg.max_turn_rate),double(cfg.engage_radius),double(cfg.leash),double(cfg.encircle_cells),double(cfg.ranged_keep),double(cfg.ranged_leash),double(cfg.ally_push),double(cfg.enemy_push),double(cfg.push_clamp),cfg.bleed_per_game_hour,double(cfg.rescue_seek_cells),double(cfg.capture_seek_cells),cfg.combat_grace,cfg.shot_grace}) CHECK_VALID(std::isfinite(v) && v >= 0 && v <= 1e9);
	CHECK_VALID(rest_hold.size() == n);
	for (uint8_t v : rest_hold) CHECK_VALID(v <= 1);
	for (auto *v : {&px,&py,&nx,&ny,&vx,&vy,&face,&anim_t,&knock_dx,&knock_dy,&host_vx,&host_vy,&slot_tx_,&slot_ty_,&slot_clip_,&rest_x,&rest_y,&rest_best,&rest_t}) {
		CHECK_VALID(v->size() == n); for (float x : *v) CHECK_VALID(std::isfinite(x));
	}
	for (auto *v : {&hp,&stun,&grace,&ko,&getup,&stagger,&exch_cd,&ranged_cd,&skill_cd,&knock_t,&act_t,&escape_t}) {
		CHECK_VALID(v->size() == n); for (double x : *v) CHECK_VALID(std::isfinite(x) && x >= 0);
	}
	for (auto *v : {&team,&state,&los_ok,&skill,&role,&captive,&present,&troop,&running,&near_enemy,&fire_blocked,&bandaged,&life_ck,&host_ctl,&host_run,&host_engage}) CHECK_VALID(v->size() == n);
	for (auto *v : {&los_ok,&captive,&present,&running,&near_enemy,&fire_blocked,&bandaged,&host_ctl,&host_run,&host_engage}) for (uint8_t x : *v) CHECK_VALID(x <= 1);
	for (auto *v : {&form,&slot,&target,&cell,&enc_target,&rescue_of,&capture_of,&captor,&rescued_by_,&capturing_by_}) CHECK_VALID(v->size() == n);
	CHECK_VALID(ammo.size() == n && equip.size() == n && ability.size() == n && person_id.size() == n && attackers_.size() == n);
	CHECK_VALID(military_role.size() == n);
	for (uint8_t value : military_role) CHECK_VALID(value <= 2);
	CHECK_VALID(post_holder.size() == n);
	for (uint8_t value : post_holder) CHECK_VALID(value <= 1);
	CHECK_VALID(released.size() == n);
	for (uint8_t value : released) CHECK_VALID(value <= 1);
	CHECK_VALID(aboard.size() == n && aboard_vehicle.size() == n);
	for (uint8_t value : aboard) CHECK_VALID(value <= 1);
	CHECK_VALID(prison_id.size() == n && escort_goal.size() == n && escort_mode.size() == n);
	CHECK_VALID(contact_revision.size() == n);
	if (allow_site_jobs) {
		CHECK_VALID(housing_attendance_cell.size() == n && siege_crew.size() == n && siege_member_group.size() == n && siege_step_source.size() == n);
		CHECK_VALID(siege_person_blocked.empty() || siege_person_blocked.size() == cells);
		CHECK_VALID(siege_wreck_exit.empty() || siege_wreck_exit.size() == n);
		for (uint8_t value : siege_crew) CHECK_VALID(value <= 1);
		for (uint8_t value : siege_person_blocked) CHECK_VALID(value <= 1);
		for (int value : housing_attendance_cell) CHECK_VALID(value >= -1 && value < (int)cells);
		CHECK_VALID(siege_serial >= 0 && siege_compounds.size() <= n);
	} else CHECK_VALID(siege_compounds.empty());
	CHECK_VALID(lag_acc_.size() == nf && lag_cnt_.size() == nf && touch_.size() == nf * nf);
	for (double x : lag_acc_) CHECK_VALID(std::isfinite(x) && x >= 0);
	for (int x : lag_cnt_) CHECK_VALID(x >= 0 && x <= (int)n);
	for (uint8_t x : touch_) CHECK_VALID(x <= 1);
	CHECK_VALID(hostile_.size() == 65536); for (uint8_t x : hostile_) CHECK_VALID(x <= 1);
	auto index = [&](int i) { return i >= -1 && i < (int)n; };
	auto xy = [&](double x, double y) { return std::isfinite(x) && std::isfinite(y) && x >= 0 && y >= 0 && x < terrain.w && y < terrain.h; };
	auto eq = [](const rules::Equip &e) { return e.family <= rules::F_SHOVEL && e.material <= rules::M_STEEL && e.armor <= rules::A_MINGGUANG; };
	std::unordered_set<int64_t> ids;
	int hosts = 0;
	for (size_t i = 0; i < n; ++i) {
		CHECK_VALID(form[i] >= 0 && form[i] < (int)nf && team[i] == formations[form[i]].team);
		CHECK_VALID(xy(px[i],py[i]) && xy(nx[i],ny[i]) && cell[i] >= 0 && cell[i] < (int)cells);
		CHECK_VALID(anim_t[i] >= 0); CHECK_VALID(slot_clip_[i] >= 0);
		CHECK_VALID(state[i] <= S_HOST && role[i] <= R_OFFICER && troop[i] <= T_CROSSBOW && skill[i] <= rules::SK_POWER && life_ck[i] <= 2 && eq(equip[i]));
		CHECK_VALID(person_id[i] >= 0 && ids.insert(person_id[i]).second);
		CHECK_VALID(prison_id[i] >= 0 && prison_id[i] <= 2147483647 && (allow_site_jobs ? escort_mode[i] <= 6 : (escort_mode[i] <= 2 || held_site_step((int)i))));
		CHECK_VALID(contact_revision[i] >= 0);
		CHECK_VALID(escort_goal[i] >= -1 && escort_goal[i] < (int)cells && (escort_mode[i] != 0 || escort_goal[i] == -1));
		CHECK_VALID(escort_mode[i] != 2 || escort_goal[i] >= 0);
		CHECK_VALID(escort_mode[i] == 0 || (prison_id[i] == 0 && (escort_mode[i] >= 3 || hp[i] > 0)));
		if (allow_site_jobs) {
			const int group = siege_member_group[i], source = siege_step_source[i];
			CHECK_VALID(group >= -1 && group < (int)siege_compounds.size());
			CHECK_VALID(source >= -1 && source < (int)cells);
			const uint8_t mode = escort_mode[i];
			if (mode == 3 || mode == 4) {
				CHECK_VALID(group == -1 && !siege_crew[i] && source == -1);
				CHECK_VALID(mode != 4 || escort_goal[i] >= 0);
			} else if (group < 0 && (mode == 5 || mode == 6)) {
				CHECK_VALID(mode != 6 || escort_goal[i] >= 0);
				if (escort_goal[i] >= 0) {
					CHECK_VALID(source >= 0);
					const int dx = escort_goal[i] % terrain.w - source % terrain.w, dy = escort_goal[i] / terrain.w - source / terrain.w;
					CHECK_VALID(std::abs(dx) + std::abs(dy) <= 1);
				} else CHECK_VALID(source == -1);
			} else if (group < 0) CHECK_VALID(source == -1);
			if (mode >= 3 && (mode & 1u)) CHECK_VALID(hp[i] > 0);
			if (siege_crew[i]) CHECK_VALID(mode == 0 || mode == 5 || mode == 6);
			if (!siege_wreck_exit.empty()) {
				const auto &exit = siege_wreck_exit[i]; CHECK_VALID(exit.size() <= 64);
				std::unordered_set<int> unique;
				for (int c : exit) CHECK_VALID(c >= 0 && c < (int)cells && !siege_person_blocked.empty() && siege_person_blocked[c] && unique.insert(c).second);
			}
		}
		if (escort_goal[i] >= 0) {
			const int dx = escort_goal[i] % terrain.w - int(std::floor(px[i]));
			const int dy = escort_goal[i] / terrain.w - int(std::floor(py[i]));
			CHECK_VALID(std::abs(dx) + std::abs(dy) <= 1);
			CHECK_VALID(terrain.walkable(escort_goal[i] % terrain.w, escort_goal[i] / terrain.w));
		}
		CHECK_VALID(prison_id[i] == 0 || (captive[i] && hp[i] > 0 && escort_mode[i] == 0 && escort_goal[i] == -1 && escape_t[i] == 0));
		for (int x : {target[i],enc_target[i],rescue_of[i],capture_of[i],captor[i],rescued_by_[i],capturing_by_[i]}) CHECK_VALID(index(x));
		for (int x : {int(ability[i].tactics),int(ability[i].leadership),int(ability[i].coach)}) CHECK_VALID(x >= -1 && x <= 100);
		hosts += host_ctl[i];
	}
	CHECK_VALID(hosts <= 1);
	if (allow_site_jobs) {
		std::vector<int> groups(n, -1);
		std::unordered_set<int64_t> tokens;
		std::unordered_set<int> compound_claims;
		for (size_t at = 0; at < siege_compounds.size(); ++at) {
			const auto &g = siege_compounds[at];
			CHECK_VALID(g.token > 0 && g.token <= siege_serial && tokens.insert(g.token).second);
			CHECK_VALID(!g.members.empty() && g.members.size() <= 16 && !g.claims.empty() && g.claims.size() <= 288 && g.claims.size() == g.heights.size());
			CHECK_VALID(std::isfinite(g.duration) && g.duration > 0 && g.duration <= 3600 && std::isfinite(g.elapsed) && g.elapsed >= 0 && g.elapsed <= g.duration);
			CHECK_VALID(!g.complete || g.aborted || g.elapsed == g.duration);
			CHECK_VALID(!g.aborted || (g.complete && g.cancelled && g.elapsed == 0));
			std::unordered_set<int> claims, destinations;
			for (size_t k = 0; k < g.claims.size(); ++k) {
				const int c = g.claims[k];
				CHECK_VALID(c >= 0 && c < (int)cells && claims.insert(c).second && compound_claims.insert(c).second);
				if (!g.aborted) CHECK_VALID(terrain.walkable(c % terrain.w, c / terrain.w) && terrain.height[c] == g.heights[k]);
			}
			for (const auto &m : g.members) {
				const int i = m.soldier;
				CHECK_VALID(i >= 0 && i < (int)n && groups[i] == -1 && person_id[i] == m.person && siege_member_group[i] == (int)at && siege_crew[i]);
				CHECK_VALID(m.from >= 0 && m.from < (int)cells && m.to >= 0 && m.to < (int)cells && claims.count(m.from) && claims.count(m.to) && destinations.insert(m.to).second);
				CHECK_VALID(std::abs(m.from % terrain.w - m.to % terrain.w) + std::abs(m.from / terrain.w - m.to / terrain.w) <= 1);
				CHECK_VALID(siege_step_source[i] == -1 && prison_id[i] == 0);
				if (g.aborted) {
					CHECK_VALID((escort_mode[i] == 0 || escort_mode[i] == 6) && escort_goal[i] == -1);
					CHECK_VALID(std::abs(px[i] - (m.from % terrain.w + .5f)) <= 1e-5f && std::abs(py[i] - (m.from / terrain.w + .5f)) <= 1e-5f);
				} else CHECK_VALID((escort_mode[i] == 5 || escort_mode[i] == 6) && escort_goal[i] == m.to);
				groups[i] = (int)at;
			}
		}
		for (size_t i = 0; i < n; ++i) CHECK_VALID(siege_member_group[i] == groups[i]);
	}
	for (auto *v : {&rescuers_,&capturers_,&captives_}) for (int i : *v) CHECK_VALID(i >= 0 && i < (int)n);
	CHECK_VALID(fields_.size() <= 256);
	std::vector<uint8_t> used(fields_.size(), 0), membership(n, 0);
	for (int f : field_queue_) { CHECK_VALID(f >= 0 && f < (int)fields_.size()); used[f] = 1; }
	for (size_t fi = 0; fi < nf; ++fi) {
		const auto &f = formations[fi];
		CHECK_VALID(f.team >= 0 && f.team <= 255 && f.troop <= T_CROSSBOW && f.order <= Order::RETURN && f.ai_status <= AI_WAIT_PATH);
		CHECK_VALID(f.cols >= 1 && f.cols <= 65536 && f.roster >= 0 && f.roster <= (int)n && f.slot_count >= 0 && f.slot_count <= (int)f.members.size());
		CHECK_VALID(f.fatigue_count >= 0 && f.fatigue_count <= (int)n);
		CHECK_VALID(xy(f.cx,f.cy) && xy(f.goal_x,f.goal_y) && xy(f.origin_x,f.origin_y));
		CHECK_VALID(std::isfinite(f.ref_x) && std::isfinite(f.ref_y) && (!f.ref_valid || xy(f.ref_x,f.ref_y)));
		CHECK_VALID(std::isfinite(f.facing) && std::isfinite(f.goal_facing) && std::isfinite(f.spacing) && f.spacing > 0 && f.spacing <= 1024);
		CHECK_VALID(std::isfinite(f.lag) && f.lag >= 0 && std::isfinite(f.sustain_morale_delta));
		for (double v : {f.compact_t,f.pursuit_left,f.order_delay,f.encircle_t}) CHECK_VALID(std::isfinite(v) && v > -1);
		for (double v : {f.training,f.morale,f.rally_rest,f.fatigue,f.fatigue_rest,f.contact_age,f.ai_order_cd,f.ai_chase_cd}) CHECK_VALID(std::isfinite(v) && v >= 0);
		CHECK_VALID(f.morale <= 100);
		CHECK_VALID(index(f.target_person) && index(f.ai_target));
		for (int i : {f.formal_cmd,f.acting_cmd,f.current_cmd}) CHECK_VALID(index(i) && (i < 0 || form[i] == (int)fi));
		for (int i : f.officer_order) CHECK_VALID(index(i) && (i < 0 || form[i] == (int)fi));
		if (f.garrisoned) CHECK_VALID(f.formal_cmd == -1 && f.acting_cmd == -1 && f.current_cmd == -1 && f.officer_order.empty() && !f.ai_enabled && !f.host_center && f.order == Order::HOLD && !f.attacking);
		std::unordered_set<int> slots;
		for (int i : f.members) {
			CHECK_VALID(i >= 0 && i < (int)n && form[i] == (int)fi && !membership[i]); membership[i] = 1;
			if (hp[i] > 0) { CHECK_VALID(slot[i] >= -1 && slot[i] < f.slot_count); if (slot[i] >= 0) CHECK_VALID(slots.insert(slot[i]).second); }
		}
		CHECK_VALID(f.field >= -1 && f.field < (int)fields_.size()); if (f.field >= 0) used[f.field] = 1;
	}
	for (size_t i = 0; i < n; ++i) CHECK_VALID(hp[i] <= 0 || membership[i] || released[i]);
	for (size_t i = 0; i < n; ++i) CHECK_VALID(!released[i] || (!membership[i] && !captive[i]));
	for (size_t k = 0; k < fields_.size(); ++k) {
		const auto &f = fields_[k]; CHECK_VALID(f.last_used <= tick);
		CHECK_VALID(f.goal >= -1 && f.goal < (int)cells);
		CHECK_VALID((!used[k] && f.dir.empty()) || f.goal >= 0);
	}
	for (const auto &p : projectiles) {
		CHECK_VALID(p.shooter >= 0 && p.shooter < (int)n && p.faction >= 0 && p.faction <= 255);
		CHECK_VALID(terrain.contains(p.source.x,p.source.y) && terrain.contains(p.target.x,p.target.y));
		for (double v : {p.left,p.source_eye,p.goal_eye,p.stats.ability,p.stats.training,p.stats.fatigue}) CHECK_VALID(std::isfinite(v) && v >= 0);
		CHECK_VALID(p.stats.skill <= rules::SK_POWER && eq(p.stats.equip));
	}
	for (const auto &e : events) {
		CHECK_VALID(e.kind < EV_COUNT && index(e.soldier) && e.formation >= -1 && e.formation < (int)nf && std::isfinite(e.time) && e.time >= 0);
		CHECK_VALID(std::isfinite(e.fatigue) && e.fatigue >= 0 && e.fatigue <= 100 && std::isfinite(e.fatigue_rest) && e.fatigue_rest >= 0 && e.fatigue_rest <= 30);
		if (e.kind == EV_DEATH) {
			CHECK_VALID(e.soldier >= 0 && e.formation == form[e.soldier] && e.person == person_id[e.soldier] && hp[e.soldier] <= 0);
		} else CHECK_VALID(e.fatigue == 0 && e.fatigue_rest == 0);
	}
	for (double v : {time,combat_left,game_dt,combat_mark}) CHECK_VALID(std::isfinite(v) && v >= 0);
	CHECK_VALID(convoy_of.size() == n && convoy_serial >= 0 && convoys.size() <= 256);
	{
		std::vector<uint8_t> owned(n, 0);
		std::unordered_set<int> convoy_ids;
		for (const auto &cv : convoys) {
			CHECK_VALID(cv.id > 0 && cv.id <= convoy_serial && convoy_ids.insert(cv.id).second);
			CHECK_VALID(xy(cv.x, cv.y) && std::isfinite(cv.facing) && terrain.walkable((int)cv.x, (int)cv.y));
			CHECK_VALID(std::isfinite(cv.gx) && std::isfinite(cv.gy) && std::isfinite(cv.gfacing));
			CHECK_VALID(cv.goal_cell >= -1 && cv.goal_cell < (int)cells && cv.field >= -1 && cv.field < (int)fields_.size());
			CHECK_VALID(!cv.has_goal || (xy(cv.gx, cv.gy) && cv.goal_cell == terrain.idx((int)cv.gx, (int)cv.gy)));
			CHECK_VALID(cv.crew.size() <= 64 && cv.body.size() <= 64);
			for (const auto &k : cv.crew) {
				CHECK_VALID(k.soldier >= 0 && k.soldier < (int)n && convoy_of[k.soldier] == cv.id && !owned[k.soldier]);
				CHECK_VALID(std::abs(k.ox) <= 8 && std::abs(k.oy) <= 8);
				owned[k.soldier] = 1;
			}
			// G4 S2 body: offsets are bounded, and the derived footprint at the current pose is the one installed
			for (const auto &o : cv.body) CHECK_VALID(std::abs(o.ox) <= 8 && std::abs(o.oy) <= 8);
			std::vector<int> derived;
			CHECK_VALID(convoy_footprint(cv, cv.x, cv.y, cv.facing, derived) && derived == cv.body_cells);
			for (int v : cv.body_cells) CHECK_VALID(terrain.walkable(v % terrain.w, v / terrain.w) && convoy_body_owner.size() == cells && convoy_body_owner[v] == cv.id);
			// G4 formation following: an attached convoy's crew are members of its formation; the route region is on the map
			CHECK_VALID(cv.formation >= -1 && cv.formation < (int)nf && cv.slot_index >= -1 && cv.blocked >= 0 && cv.key_q >= -1 && cv.key_q < 4);
			CHECK_VALID(std::isfinite(cv.key_gx) && std::isfinite(cv.key_gy) && cv.turn_to >= -1 && cv.turn_to < 4 && cv.move_to >= -1 && cv.move_to < (int)cells);
			if (cv.formation >= 0) for (const auto &k : cv.crew) CHECK_VALID(form[k.soldier] == cv.formation);
			CHECK_VALID(cv.plan_w >= 0 && cv.plan_h >= 0 && cv.plan_cost.size() == (size_t)cv.plan_w * (size_t)cv.plan_h * 4);
			CHECK_VALID(cv.plan_cost.empty() || (cv.plan_x0 >= 0 && cv.plan_y0 >= 0 && cv.plan_x0 + cv.plan_w <= terrain.w && cv.plan_y0 + cv.plan_h <= terrain.h));
			for (int v : cv.claim) CHECK_VALID(v >= 0 && v < (int)cells && convoy_claim_owner.size() == cells && convoy_claim_owner[v] == cv.id);
		}
		for (size_t i = 0; i < n; ++i) CHECK_VALID(convoy_of[i] == 0 ? !owned[i] : (owned[i] && convoy_ids.count(convoy_of[i]) == 1));
	}
	// G1 S1: an aboard soldier is a living member with no slot, no convoy crew role and a vehicle; nobody else is
	for (size_t i = 0; i < n; ++i) {
		if (aboard[i]) CHECK_VALID(aboard_vehicle[i] >= 0 && !released[i] && slot[i] < 0 && convoy_of[i] == 0);
		else CHECK_VALID(aboard_vehicle[i] == -1);
	}
	CHECK_VALID(exchange_round >= 0 && shot_serial >= 0);
	CHECK_VALID(host_last_release_id >= 0 && host_last_release_id <= INT32_MAX);
	CHECK_VALID(!host_ranged_delegate || projectiles.empty());
	return true;
#undef CHECK_VALID
}

void World::swap_state(World &o) {
	using std::swap;
	swap(cfg, o.cfg);
	swap(terrain, o.terrain);
	swap(formations, o.formations);
	swap(px, o.px);
	swap(py, o.py);
	swap(nx, o.nx);
	swap(ny, o.ny);
	swap(vx, o.vx);
	swap(vy, o.vy);
	swap(face, o.face);
	swap(anim_t, o.anim_t);
	swap(hp, o.hp);
	swap(stun, o.stun);
	swap(grace, o.grace);
	swap(ko, o.ko);
	swap(getup, o.getup);
	swap(stagger, o.stagger);
	swap(exch_cd, o.exch_cd);
	swap(ranged_cd, o.ranged_cd);
	swap(skill_cd, o.skill_cd);
	swap(knock_t, o.knock_t);
	swap(act_t, o.act_t);
	swap(escape_t, o.escape_t);
	swap(knock_dx, o.knock_dx);
	swap(rest_hold, o.rest_hold); swap(rest_x, o.rest_x); swap(rest_y, o.rest_y); swap(rest_best, o.rest_best); swap(rest_t, o.rest_t);
	swap(knock_dy, o.knock_dy);
	swap(team, o.team);
	swap(state, o.state);
	swap(los_ok, o.los_ok);
	swap(skill, o.skill);
	swap(role, o.role);
	swap(military_role, o.military_role);
	swap(post_holder, o.post_holder); swap(released, o.released); swap(aboard, o.aboard); swap(aboard_vehicle, o.aboard_vehicle);
	swap(captive, o.captive);
	swap(present, o.present);
	swap(troop, o.troop);
	swap(running, o.running);
	swap(near_enemy, o.near_enemy);
	swap(fire_blocked, o.fire_blocked);
	swap(bandaged, o.bandaged);
	swap(host_ctl, o.host_ctl);
	swap(host_run, o.host_run);
	swap(host_engage, o.host_engage);
	swap(host_vx, o.host_vx);
	swap(host_vy, o.host_vy);
	swap(form, o.form);
	swap(slot, o.slot);
	swap(target, o.target);
	swap(cell, o.cell);
	swap(enc_target, o.enc_target);
	swap(rescue_of, o.rescue_of);
	swap(capture_of, o.capture_of);
	swap(captor, o.captor);
	swap(prison_id, o.prison_id); swap(escort_goal, o.escort_goal); swap(escort_mode, o.escort_mode); swap(housing_attendance_cell, o.housing_attendance_cell);
	swap(contact_revision, o.contact_revision);
	swap(convoys, o.convoys); swap(convoy_of, o.convoy_of); swap(convoy_body_owner, o.convoy_body_owner); swap(convoy_serial, o.convoy_serial);
	swap(convoy_claim_owner, o.convoy_claim_owner);
	swap(siege_crew,o.siege_crew); swap(siege_member_group,o.siege_member_group); swap(siege_step_source,o.siege_step_source); swap(siege_compounds,o.siege_compounds); swap(siege_serial,o.siege_serial); swap(siege_person_blocked,o.siege_person_blocked); swap(siege_wreck_exit,o.siege_wreck_exit);
	swap(ammo, o.ammo);
	swap(equip, o.equip);
	swap(ability, o.ability);
	swap(person_id, o.person_id);
	swap(life_ck, o.life_ck);
	swap(events, o.events);
	swap(projectiles, o.projectiles);
	swap(tick, o.tick);
	swap(exchange_round, o.exchange_round);
	swap(shot_serial, o.shot_serial);
	swap(host_ranged_delegate,o.host_ranged_delegate); swap(host_last_release_id,o.host_last_release_id);
	swap(fire_visual,o.fire_visual);
	swap(action_motion,o.action_motion);
	swap(time, o.time);
	swap(combat_left, o.combat_left);
	swap(game_dt, o.game_dt);
	swap(combat_mark, o.combat_mark);
	swap(external_clock, o.external_clock);
	swap(stats, o.stats);
	swap(fields_, o.fields_);
	swap(field_queue_, o.field_queue_);
	swap(hostile_, o.hostile_);
	swap(slot_tx_, o.slot_tx_);
	swap(slot_ty_, o.slot_ty_);
	swap(slot_clip_, o.slot_clip_);
	swap(lag_acc_, o.lag_acc_);
	swap(lag_cnt_, o.lag_cnt_);
	swap(attackers_, o.attackers_);
	swap(attackers_tick_, o.attackers_tick_);
	swap(touch_, o.touch_);
	swap(rescued_by_, o.rescued_by_);
	swap(capturing_by_, o.capturing_by_);
	swap(rescuers_, o.rescuers_);
	swap(capturers_, o.capturers_);
	swap(captives_, o.captives_);
	swap(hash_start_, o.hash_start_);
	swap(hash_items_, o.hash_items_);
	swap(bw_, o.bw_);
	swap(bh_, o.bh_);
	swap(slot_faction_, o.slot_faction_);
	swap(block_count_, o.block_count_);
	swap(enemy_block_, o.enemy_block_);
	swap(idle_block_, o.idle_block_); swap(idle_ai_block_, o.idle_ai_block_);
	swap(kit,o.kit); swap(start_x,o.start_x); swap(start_y,o.start_y);
	swap(chunks_, o.chunks_);
	swap(pair_buf_, o.pair_buf_);
	swap(fire_buf_, o.fire_buf_);
	swap(illegal_buf_, o.illegal_buf_);
	swap(wake_buf_, o.wake_buf_);
	swap(getup_buf_, o.getup_buf_);
	swap(ex_acc_, o.ex_acc_);
	swap(vis_kind, o.vis_kind);
	swap(vis_t0, o.vis_t0);
	swap(finalized_, o.finalized_);

	for (int i = 0; i < 256; ++i) swap(faction_slot_[i], o.faction_slot_[i]);
	person_index_.clear(); pres.clear(); pres_time = -1;
	flight_cells_.clear(); held_.clear(); ex_participants_.clear(); quiet_contact_ = false;
}

bool World::load(const std::vector<uint8_t> &blob) {
	return load_impl(blob, nullptr, nullptr);
}

bool World::load(const std::vector<uint8_t> &blob, const std::vector<int> &blocked, const std::vector<int64_t> &wreck_exit) {
	return load_impl(blob, &blocked, &wreck_exit);
}

bool World::load_impl(const std::vector<uint8_t> &blob, const std::vector<int> *blocked, const std::vector<int64_t> *wreck_exit) {
	if (work_point_active_ || blob.empty() || blob.size() > 16 * 1024 * 1024) return false;
	try {
		World candidate(1); Reader r(blob); candidate.serialize(r);
		// convoy body cells are derived from the saved offsets, anchors and facings before validation checks them
		if (!r.ok || r.at != blob.size() || !candidate.rebuild_convoy_bodies() || !candidate.validate(nullptr, false)) return false;
		// Original Site navigation is restored only through this explicit prepare
		// overload, before rebuilding derived directions. Serialized field order,
		// queue, LOS observations and formation references remain untouched.
		if (blocked && (!wreck_exit || !candidate.install_siege_navigation(*blocked, *wreck_exit, false))) return false;
		const Stats saved_stats = candidate.stats;
		for (auto &fl : candidate.fields_) if (!fl.dir.empty()) { fl.dir.clear(); candidate.build_field(fl); }
		candidate.stats = saved_stats; // Restoring derived caches is not a simulated field-build event.
		candidate.rebuild_buffers();
		candidate.vis_kind.assign(candidate.soldier_count(), (uint8_t)V_IDLE); candidate.vis_t0.assign(candidate.soldier_count(), -1e9);
		candidate.fire_visual.assign(candidate.soldier_count(),0);
		candidate.kit.assign(candidate.soldier_count(),-1); candidate.start_x.assign(candidate.soldier_count(),NAN); candidate.start_y.assign(candidate.soldier_count(),NAN);
		candidate.bw_ = (candidate.terrain.w + 7) / 8; candidate.bh_ = (candidate.terrain.h + 7) / 8;
		candidate.build_faction_slots(); candidate.build_hash(); candidate.finalized_ = true;
		swap_state(candidate); return true;
	} catch (const std::bad_alloc &) { return false; } catch (const std::length_error &) { return false; }
}

int World::soldier_index(int64_t person) const {
	if (person < 0) return -1;
	if (person_index_.size() != person_id.size()) {
		person_index_.clear();
		for (int i = 0; i < (int)person_id.size(); ++i) person_index_[person_id[i]] = i;
	}
	auto it = person_index_.find(person);
	return it == person_index_.end() ? -1 : it->second;
}

// ---------------------------------------------------------------- SiteStore boundary
// Import happens after finalize() (which places the soldiers and builds the command structure from
// roles). It overwrites the rule state with the person's actual values; it is not a morale event.
void World::set_soldier_state(int i, const SoldierState &s) {
	Formation &f = formations[form[i]];
	bool was_alive = hp[i] > 0.0;
	hp[i] = std::max(0.0, s.hp);
	stun[i] = std::max(0.0, s.stun); grace[i] = std::max(0.0, s.grace);
	ko[i] = hp[i] > 0.0 ? std::max(0.0, s.ko) : 0.0;
	getup[i] = std::max(0.0, s.getup); stagger[i] = std::max(0.0, s.stagger);
	bandaged[i] = (uint8_t)(s.bandaged != 0);
	ammo[i] = (uint16_t)std::clamp(s.ammo, 0, 65535);
	if (s.tactics >= 0) {
		ability[i].tactics = (int16_t)std::clamp(s.tactics, 0, 100);
		ability[i].leadership = (int16_t)std::clamp(s.leadership, 0, 100);
		ability[i].coach = (int16_t)std::clamp(s.coach, 0, 100);
	} else {
		ability[i] = CommandAbility{};
	}
	bool now_alive = hp[i] > 0.0;
	if (was_alive && !now_alive) f.fatigue_count = std::max(0, f.fatigue_count - 1);
	if (!was_alive && now_alive) f.fatigue_count++;
	int g = s.captive ? soldier_index(s.captor_person) : -1;
	captive[i] = (uint8_t)(s.captive != 0 && now_alive);
	captor[i] = captive[i] ? g : -1;
	prison_id[i] = captive[i] ? std::max(int64_t(0), s.prison_id) : 0;
	escape_t[i] = prison_id[i] > 0 ? 0.0 : std::max(0.0, s.escape_t);
	if ((!now_alive || ko[i] > 0 || captive[i]) && controlled_step_pending(i)) { if (escort_mode[i] & 1u) ++escort_mode[i]; }
	else if (!now_alive || prison_id[i] > 0) { escort_mode[i] = 0; escort_goal[i] = -1; vx[i] = vy[i] = 0; }
	exch_cd[i] = std::max(0.0, s.exch_cd); ranged_cd[i] = std::max(0.0, s.ranged_cd); skill_cd[i] = std::max(0.0, s.skill_cd);
	knock_t[i] = std::max(0.0, s.knock_t); act_t[i] = std::max(0.0, s.act_t);
	if (s.role >= 0 && s.role <= R_OFFICER) role[i] = (uint8_t)s.role;
	if (siege_group(i) < 0 && !controlled_step_pending(i) && std::isfinite(s.x) && std::isfinite(s.y) && s.x >= 0 && s.y >= 0 && s.x < terrain.w && s.y < terrain.h) {
		px[i] = nx[i] = s.x; py[i] = ny[i] = s.y; cell[i] = terrain.idx((int)s.x, (int)s.y);
	}
	if (std::isfinite(s.facing)) face[i] = s.facing;
	if (captive[i] && std::find(captives_.begin(), captives_.end(), i) == captives_.end()) captives_.push_back(i);
	if (!captive[i]) captives_.erase(std::remove(captives_.begin(), captives_.end(), i), captives_.end());
	life_ck[i] = hp[i] <= 0.0 ? 2 : (ko[i] > 0.0 ? 1 : 0);
	f.command_dirty = true;
}

SoldierState World::get_soldier_state(int i) const {
	SoldierState s;
	s.hp = hp[i]; s.stun = stun[i]; s.grace = grace[i]; s.ko = ko[i]; s.getup = getup[i]; s.stagger = stagger[i];
	s.captive = captive[i];
	s.captor_person = captive[i] && captor[i] >= 0 ? person_id[captor[i]] : -1;
	s.prison_id = prison_id[i];
	s.bandaged = bandaged[i];
	s.ammo = ammo[i];
	s.escape_t = escape_t[i]; s.role = role[i]; s.x = px[i]; s.y = py[i]; s.facing = face[i];
	s.exch_cd = exch_cd[i]; s.ranged_cd = ranged_cd[i]; s.skill_cd = skill_cd[i]; s.knock_t = knock_t[i]; s.act_t = act_t[i];
	s.tactics = ability[i].tactics; s.leadership = ability[i].leadership; s.coach = ability[i].coach;
	return s;
}

void World::set_formation_state(int fi, const FormationState &s) {
	Formation &f = formations[fi];
	f.morale = std::clamp(s.morale, 0.0, 100.0);
	f.rally_rest = std::max(0.0, s.rally_rest);
	f.fatigue = std::clamp(s.fatigue, 0.0, rules::FATIGUE_LIMIT);
	f.fatigue_rest = std::max(0.0, s.fatigue_rest);
	f.training = std::max(s.training, 0.0);
	f.routed = s.routed != 0;
	f.needs_attack_order = s.needs_attack_order != 0;
	auto member = [&](int64_t p) { int i = soldier_index(p); return i >= 0 && form[i] == fi ? i : -1; };
	f.formal_cmd = member(s.formal_person);
	f.acting_cmd = member(s.acting_person);
	f.officer_order.clear();
	for (int64_t p : s.officer_persons) { int i = member(p); if (i >= 0) f.officer_order.push_back(i); }
	const bool full_state = s.order >= 0 && s.order <= (int)Order::RETURN;
	// A full import restores command refs; only a real step may select/generate a replacement.
	if (!full_state) {
		int prev = f.current_cmd;
		settle_command(f, fi);
		if (f.current_cmd != prev && !events.empty() && events.back().kind == EV_SUCCESSION) events.pop_back(); // import is not a succession
	}
	f.commander_present = s.commander_present != 0;
	if (full_state) {
		f.order = (Order)s.order; f.target_person = soldier_index(s.target_person);
		f.current_cmd = member(s.current_person);
		if (std::isfinite(s.cx) && std::isfinite(s.cy)) { f.cx = s.cx; f.cy = s.cy; }
		if (std::isfinite(s.facing)) f.facing = s.facing;
		if (std::isfinite(s.goal_x) && std::isfinite(s.goal_y)) set_goal(f, s.goal_x, s.goal_y);
		if (std::isfinite(s.goal_facing)) f.goal_facing = s.goal_facing;
		if (std::isfinite(s.origin_x) && std::isfinite(s.origin_y)) { f.origin_x = s.origin_x; f.origin_y = s.origin_y; }
		if (std::isfinite(s.ref_x) && std::isfinite(s.ref_y)) { f.ref_x = s.ref_x; f.ref_y = s.ref_y; }
		f.ref_valid = s.ref_valid != 0; f.resupplying = s.resupplying != 0;
		f.pursuit_left = s.pursuit_left; f.order_delay = s.order_delay; f.attacking = s.attacking != 0;
	}
	if (s.fatigue_count >= 0) f.fatigue_count = s.fatigue_count;
	if (s.ai_enabled >= 0) f.ai_enabled = s.ai_enabled != 0;
	if (s.no_orders >= 0) f.no_orders = s.no_orders != 0;
	if (s.host_center >= 0) f.host_center = s.host_center != 0;
	if (f.no_orders) f.ai_enabled = false;
	if (f.garrisoned) {
		f.formal_cmd = f.acting_cmd = f.current_cmd = -1;
		f.officer_order.clear(); f.ai_enabled = false; f.host_center = false;
		f.commander_present = false; f.attacking = false; f.needs_attack_order = true;
		f.order = Order::HOLD;
	}
	for (int i : f.members) life_ck[i] = hp[i] <= 0.0 ? 2 : (ko[i] > 0.0 ? 1 : 0);
}

FormationState World::get_formation_state(int fi) const {
	const Formation &f = formations[fi];
	FormationState s;
	s.morale = f.morale; s.rally_rest = f.rally_rest; s.fatigue = f.fatigue; s.fatigue_rest = f.fatigue_rest;
	s.training = f.training; s.routed = f.routed; s.needs_attack_order = f.needs_attack_order;
	s.commander_present = f.commander_present;
	s.current_person = f.current_cmd >= 0 ? person_id[f.current_cmd] : -1;
	s.target_person = f.target_person >= 0 ? person_id[f.target_person] : -1;
	s.fatigue_count = f.fatigue_count; s.order = (int)f.order; s.ai_enabled = f.ai_enabled; s.no_orders = f.no_orders; s.host_center = f.host_center;
	s.goal_x = f.goal_x; s.goal_y = f.goal_y; s.goal_facing = f.goal_facing; s.cx = f.cx; s.cy = f.cy; s.facing = f.facing;
	s.origin_x = f.origin_x; s.origin_y = f.origin_y; s.ref_x = f.ref_x; s.ref_y = f.ref_y; s.ref_valid = f.ref_valid;
	s.pursuit_left = f.pursuit_left; s.order_delay = f.order_delay; s.attacking = f.attacking; s.resupplying = f.resupplying;
	s.formal_person = f.formal_cmd >= 0 ? person_id[f.formal_cmd] : -1;
	s.acting_person = f.acting_cmd >= 0 ? person_id[f.acting_cmd] : -1;
	for (int i : f.officer_order) s.officer_persons.push_back(person_id[i]);
	return s;
}

} // namespace wg
