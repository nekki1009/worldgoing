// Command presence (D46/D56), succession (D18, D35-D40, D47-D48, D57), command effects (D44/D77),
// team morale and rout / rally (institutions sec.4, D27/D28), shared fatigue (2026-09-15).
#include "crowd_core.hpp"

#include <algorithm>

namespace wg {

using namespace rules;

static uint64_t next_rng(uint64_t &s) {
	s ^= s << 13; s ^= s >> 7; s ^= s << 17;
	return s;
}

double World::command_effect(int fi, int kind, double cap) const {
	const Formation &f = formations[fi];
	double total = 0;
	for (int i : f.members) {
		if (!ability[i].has() || !command_eligible(i)) continue;
		total += kind == 0 ? ability[i].tactics : (kind == 1 ? ability[i].leadership : ability[i].coach);
	}
	return diminishing(total, cap);
}

void World::ensure_ability(int i, Formation &f) {
	if (ability[i].has()) return;
	ability[i].tactics = (int16_t)(next_rng(f.rng) % 101);   // D60: uniform 0-100, generated once
	ability[i].leadership = (int16_t)(next_rng(f.rng) % 101);
	ability[i].coach = (int16_t)(next_rng(f.rng) % 101);
}

void World::refresh_presence(Formation &f) {
	// D56: reference from actual positions of living, uncaptured members; radius = slot envelope + 2, >= 8;
	// already-present members get +2 hysteresis. Dead / unconscious / captive are never present.
	double sx = 0, sy = 0;
	int cnt = 0;
	for (int i : f.members)
		if (can_act(i)) { sx += px[i]; sy += py[i]; ++cnt; }
	if (cnt == 0) {
		f.ref_valid = false;
		for (int i : f.members) present[i] = 0;
		return;
	}
	float mx = (float)(sx / cnt), my = (float)(sy / cnt);
	int best = -1;
	float bd = 1e30f;
	for (int i : f.members) {
		if (!can_act(i)) continue;
		float dx = px[i] - mx, dy = py[i] - my, d2 = dx * dx + dy * dy;
		if (d2 < bd || (d2 == bd && best >= 0 && person_id[i] < person_id[best])) { bd = d2; best = i; }
	}
	f.ref_x = px[best]; f.ref_y = py[best]; f.ref_valid = true;
	int m = std::max(1, (int)f.members.size());
	int cols = std::max(1, std::min(f.cols, m)), rows = (m + cols - 1) / cols;
	float hx = (float)(cols - 1) * 0.5f * f.spacing, hy = (float)(rows - 1) * 0.5f * f.spacing;
	float radius = std::max(8.f, std::sqrt(hx * hx + hy * hy) + 2.f);
	for (int i : f.members) {
		if (!can_act(i)) { present[i] = 0; continue; }
		float r = radius + (present[i] ? 2.f : 0.f);
		float dx = px[i] - f.ref_x, dy = py[i] - f.ref_y;
		present[i] = (uint8_t)(dx * dx + dy * dy <= r * r);
	}
}

int World::select_commander(Formation &f) {
	for (int i : f.officer_order)
		if (hp[i] > 0.0 && command_eligible(i)) return i;
	std::vector<int> cand;
	for (int i : f.members)
		if (command_eligible(i)) cand.push_back(i);
	if (cand.empty()) return -1;
	std::sort(cand.begin(), cand.end(), [&](int a, int b) { return person_id[a] < person_id[b]; });
	return cand[next_rng(f.rng) % cand.size()]; // D60: equal probability among eligible members
}

void World::settle_command(Formation &f, int fi) {
	f.command_dirty = false;
	refresh_presence(f);
	if (f.garrisoned) {
		f.formal_cmd = f.acting_cmd = f.current_cmd = -1;
		f.officer_order.clear(); f.commander_present = false;
		f.attacking = false; f.needs_attack_order = true;
		return;
	}
	int old_current = f.current_cmd;
	// officer order drops the dead and the formal commander (TerrainArmy._sync_officer_order)
	f.officer_order.erase(std::remove_if(f.officer_order.begin(), f.officer_order.end(),
	                                     [&](int i) { return hp[i] <= 0.0 || i == f.formal_cmd; }),
	                      f.officer_order.end());
	bool permanent_vacancy = f.formal_cmd < 0 || hp[f.formal_cmd] <= 0.0;
	if (permanent_vacancy) {                                      // D40: eligible acting commander is promoted
		f.formal_cmd = command_eligible(f.acting_cmd) ? f.acting_cmd : select_commander(f);
		f.acting_cmd = -1;
		f.current_cmd = f.formal_cmd;
	} else if (command_eligible(f.formal_cmd)) {                  // D39: the original commander resumes
		f.current_cmd = f.formal_cmd;
		f.acting_cmd = -1;
	} else {                                                      // D39 / D47: acting (re)selected
		if (!command_eligible(f.acting_cmd)) f.acting_cmd = select_commander(f);
		f.current_cmd = f.acting_cmd;
	}
	if (f.current_cmd >= 0) {
		ensure_ability(f.current_cmd, f);
		f.officer_order.erase(std::remove(f.officer_order.begin(), f.officer_order.end(), f.formal_cmd), f.officer_order.end());
		if (old_current != f.current_cmd && (old_current >= 0 || tick > 0)) {
			stats.successions++;
			push_event(EV_SUCCESSION, f.current_cmd, old_current);
		}
	} else {
		// D48 / D49 (terrain_army.gd settle_combat_command): no eligible person -> the formation holds
		// (a retreat keeps going), drops its goal and pursuit, stops offensive and needs a new order (D50).
		// The -10 morale for the interruption is taken by the next life observation (Sustain.combat_event).
		f.needs_attack_order = true;
		f.attacking = false;
		for (int i : f.members) enc_target[i] = -1;
		if (f.order != Order::RETREAT && f.order != Order::HOLD) {
			f.order = Order::HOLD;
			f.goal_x = f.cx; f.goal_y = f.cy; f.arrived = true;
			f.target_person = -1; f.pursuit_left = 0;
		}
		if (old_current >= 0) push_event(EV_COMMAND_LOST, -1, old_current), events.back().formation = fi;
	}
}

// site_controller._observe_team_life + Sustain.combat_event (institutions sec.4). Runs at the sustain
// point of the step, comparing each member with the checkpoint of the previous observation:
// death = was not dead, now dead; KO = was conscious, now unconscious (KO then death in one step is
// one death). Denominator: checkpoint members not dead, captives and the unconscious included.
// A qualified commander that disappeared since the last observation adds the one-time -10.
void World::observe_life(Formation &f, int fi) {
	int deaths = 0, kos = 0, before = 0;
	for (int i : f.members) {
		uint8_t old = life_ck[i];
		before += old != 2;
		uint8_t now = hp[i] <= 0.0 ? 2 : (ko[i] > 0.0 ? 1 : 0);
		deaths += now == 2 && old != 2;
		kos += now == 1 && old == 0;
	}
	bool qualified = f.current_cmd >= 0 && command_eligible(f.current_cmd);
	if (before > 0 && (deaths > 0 || kos > 0 || f.commander_present != qualified)) {
		double lead = command_effect(fi, 1, 0.25); // D77 leadership: up to 25 % less combat morale loss (read after the casualties)
		double loss = (MORALE_DEATH * deaths + MORALE_KO * kos) / (double)before;
		if (f.commander_present && !qualified) { loss += MORALE_COMMAND_LOSS; stats.command_losses++; }
		f.morale = std::max(0.0, f.morale - loss * (1.0 - lead));
	}
	f.commander_present = qualified;
	for (int i : f.members) life_ck[i] = hp[i] <= 0.0 ? 2 : (ko[i] > 0.0 ? 1 : 0);
}

void World::begin_rout(Formation &f, int fi) {
	f.routed = true;
	f.rally_rest = 0;
	stats.routs++;
	push_event(EV_ROUT, -1, -1); events.back().formation = fi;
	retreat_away(fi);
}

void World::retreat_away(int fi) {
	Formation &f = formations[fi];
	// Both automatic rout and a host's RETREAT use this same nearest-enemy direction.
	float ex = 0, ey = 0, bd = 1e30f;
	for (auto &o : formations) {
		if (!hostile(o.team, f.team) || o.members.empty()) continue;
		float dx = o.cx - f.cx, dy = o.cy - f.cy, d2 = dx * dx + dy * dy;
		if (d2 < bd) { bd = d2; ex = o.cx; ey = o.cy; }
	}
	float dx = f.cx - ex, dy = f.cy - ey, d = std::sqrt(dx * dx + dy * dy);
	if (bd >= 1e29f || d < 1e-3f) { dx = -std::cos(f.facing); dy = -std::sin(f.facing); d = 1; }
	float gx = std::clamp(f.cx + dx / d * 25.f, 0.5f, (float)terrain.w - 0.5f);
	float gy = std::clamp(f.cy + dy / d * 25.f, 0.5f, (float)terrain.h - 0.5f);
	// The clipped point may be behind an impassable wall. Stay in the current reachable
	// component and fall back to its closest cell; a fully enclosed unit holds its cell.
	const int start = terrain.idx((int)f.cx, (int)f.cy), goal = terrain.idx((int)gx, (int)gy);
	std::vector<uint8_t> seen(terrain.edge_ok.size(), 0);
	std::vector<int> queue{start}; seen[start] = 1;
	for (size_t k = 0; k < queue.size() && !seen[goal]; ++k) {
		const int c = queue[k];
		for (int dir = 0; dir < 8; ++dir) if ((terrain.edge_ok[c] >> dir) & 1) {
			const int q = c + DY[dir] * terrain.w + DX[dir];
			if (!seen[q]) { seen[q] = 1; queue.push_back(q); }
		}
	}
	if (!seen[goal]) {
		int best = start; float best_distance = 1e30f;
		for (int c : queue) {
			float qx = (float)(c % terrain.w) + 0.5f, qy = (float)(c / terrain.w) + 0.5f;
			float qdx = qx - gx, qdy = qy - gy, distance = qdx * qdx + qdy * qdy;
			if (distance < best_distance) { best = c; best_distance = distance; }
		}
		gx = (float)(best % terrain.w) + 0.5f; gy = (float)(best / terrain.w) + 0.5f;
	}
	order_retreat(fi, gx, gy);
}

// _fatigue_threat / _exchange_rest_threat for every living, uncaptured member: an able hostile soldier
// within 8 steps (Manhattan, legality not re-checked: a superset), or the member's cell on the path
// of an arrow in flight.
bool World::team_threat(const Formation &f) const {
	const float R = 8.f;
	for (int i : f.members) {
		if (hp[i] <= 0.0 || captive[i]) continue;
		int x = (int)px[i], y = (int)py[i];
		if (!flight_cells_.empty() && flight_cells_[terrain.idx(x, y)]) return true;
		if (!idle_near(enemy_block_[faction_slot_[team[i]]], px[i], py[i], R)) continue;
		for (int yy = std::max(0, y - 8); yy <= std::min(terrain.h - 1, y + 8); ++yy) {
			int rx = 8 - std::abs(yy - y);
			for (int xx = std::max(0, x - rx); xx <= std::min(terrain.w - 1, x + rx); ++xx) {
				int c = terrain.idx(xx, yy);
				for (int k = hash_start_[c]; k < hash_start_[c + 1]; ++k) {
					int j = hash_items_[k];
					if (can_act(j) && hostile(team[i], team[j])) return true;
				}
			}
		}
	}
	return false;
}

// site_controller._team_stopped: HOLD, and no free member moving, stepping, rescuing or getting up
bool World::team_stopped(const Formation &f) const {
	if (f.order != Order::HOLD) return false;
	for (int i : f.members) {
		if (hp[i] <= 0.0 || captive[i]) continue;
		if (vx[i] * vx[i] + vy[i] * vy[i] > 0.09f || rescue_of[i] >= 0 || capture_of[i] >= 0 || getup[i] > 0.0 || knock_t[i] > 0.0) return false;
	}
	return true;
}

// Sustain pass (game time, before AI): morale observation, rout, resupply +5 / game hour when safe and
// stopped (food assumed sufficient in the prototype), rally after 30 continuous game minutes at >= 50.
void World::sustain_stage(double gdt) {
	build_flight_cells();
	for (size_t fi = 0; fi < formations.size(); ++fi) {
		Formation &f = formations[fi];
		if (f.members.empty()) continue;
		// contacts applied between steps (host damage) settle first, as they would at the end of a step
		if (f.command_dirty) settle_command(f, (int)fi);
		observe_life(f, (int)fi);
		
		f.morale = std::clamp(f.morale + f.sustain_morale_delta, 0.0, 100.0);
		f.sustain_morale_delta = 0;
		if (!f.routed && f.morale <= MORALE_ROUT && !f.no_orders) begin_rout(f, (int)fi);
		bool ok = f.fully_fed && team_stopped(f) && !team_threat(f);
		f.resupplying = ok;
		if (ok) f.morale = std::min(100.0, f.morale + MORALE_RESUPPLY_PER_HOUR / 3600.0 * gdt);
		// Original Site sustain records safe fed rest even before a rout, capped at 30 minutes.
		f.rally_rest = ok ? std::min(RALLY_REST_SECONDS, f.rally_rest + gdt) : 0.0;
		if (f.routed) {
			if (f.rally_rest >= RALLY_REST_SECONDS && f.morale >= MORALE_RALLY) {
				f.routed = false; f.needs_attack_order = true;
				push_event(EV_RALLY, -1, -1); events.back().formation = (int)fi;
			}
		}
	}
}

// End of the step (terrain_lab: settle_combat_command after contacts). Contacts, wakes, get-up ends,
// captures and escapes mark a formation dirty; continuous movement re-checks presence every 15 steps.
void World::command_stage(float) {
	for (size_t fi = 0; fi < formations.size(); ++fi) {
		Formation &f = formations[fi];
		if (f.members.empty()) continue;
		if (f.command_dirty || (tick + (uint32_t)fi) % 15 == 0) settle_command(f, (int)fi);
	}
}

// ---------------------------------------------------------------- fatigue (shared pool)
void World::charge(int i, double amount) {
	Formation &f = formations[form[i]];
	const double n = std::max(1, f.fatigue_count);
	if (work_point_active_ && !work_point_finish_ready_ && work_point_pools_[form[i]].base_captured)
		work_point_pools_[form[i]].native_charge += amount / n;
	f.fatigue = clampd(f.fatigue + amount / n, 0.0, FATIGUE_LIMIT);
	f.fatigue_rest = 0;
	f.charged_this_step = true;
}


bool World::charge_siege_round(const std::vector<int> &members, double per_person) {
	if (work_point_finish_ready_) return false; // Native final admission precedes all original point costs.
	if (members.empty() || !std::isfinite(per_person) || per_person < 0) return false;
	int formation = -1;
	for (size_t k = 0; k < members.size(); ++k) {
		const int i = members[k];
		if (i < 0 || i >= soldier_count() || !can_act(i) || !present[i] || !siege_crew[i]) return false;
		if (formation < 0) formation = form[i];
		if (formation != form[i] || std::find(members.begin(), members.begin() + k, i) != members.begin() + k) return false;
	}
	const double total = per_person * double(members.size());
	if (!std::isfinite(total)) return false;
	if (total > 0) charge(members.front(), total);
	return true;
}

// Site ladder/construction workers are actual settled original people.
// The caller validates the original work task; World guards hot action/order
// state and remains the sole formation fatigue owner.
bool World::charge_siege_work(int i, double seconds) {
	if (work_point_finish_ready_) return false; // Native final admission precedes all original point costs.
	if (i < 0 || i >= soldier_count() || !std::isfinite(seconds) || seconds < 0 || !can_act(i) || !present[i]) return false;
	const Formation &f = formations[form[i]];
	if (f.order != Order::HOLD || f.routed || f.garrisoned || is_siege_crew(i) || prison_id[i] != 0 || rescue_of[i] >= 0 || capture_of[i] >= 0) return false;
	if ((escort_mode[i] != 0 && escort_mode[i] != 5) || escort_goal[i] >= 0 || siege_group(i) >= 0 ||
		vx[i] * vx[i] + vy[i] * vy[i] > 1e-6f || stagger[i] > 0 || knock_t[i] > 0 || act_t[i] > 0 || exch_cd[i] > 0 || ranged_cd[i] > 0 || skill_cd[i] > 0) return false;
	const double amount = seconds * (10.0 / 3600.0); // original PersonFatigue.WORK_RATE
	if (!std::isfinite(amount)) return false;
	if (amount > 0) charge(i, amount);
	return true;
}

// Exchange fatigue of an original melee hit or round. Dead members stay listed but are unbound
// from the pool (GDScript PersonFatigue.unbind), so they are a no-op that succeeds.
bool World::charge_exchange_fatigue(int i, double amount) {
	if (work_point_finish_ready_) return false; // Native final admission precedes all original point costs.
	if (i < 0 || i >= soldier_count() || !std::isfinite(amount) || amount < 0) return false;
	const int fi = form[i];
	if (fi < 0 || fi >= (int)formations.size()) return false;
	const std::vector<int> &members = formations[fi].members;
	if (std::find(members.begin(), members.end(), i) == members.end()) return false;
	if (!alive(i)) return true;
	if (amount > 0) charge(i, amount);
	return true;
}

bool World::charge_custody_work(int i, double seconds) {
	if (work_point_finish_ready_) return false; // Native final admission precedes all original point costs.
	if (i < 0 || i >= soldier_count() || !can_act(i) || escort_mode[i] != 1 || !std::isfinite(seconds) || seconds < 0) return false;
	charge(i, seconds * 10.0 / 3600.0);
	return true;
}

bool World::set_military_role(int i, int value) {
	if (i < 0 || i >= soldier_count() || value < 0 || value > 2) return false;
	military_role[i] = (uint8_t)value;
	formations[form[i]].command_dirty = true;
	return true;
}

bool World::set_post_holder(int i, int value) {
	if (i < 0 || i >= soldier_count() || value < 0 || value > 1) return false;
	post_holder[i] = (uint8_t)value;
	formations[form[i]].command_dirty = true;
	return true;
}

bool World::set_garrisoned(int fi, bool enabled) {
	if (fi < 0 || fi >= (int)formations.size()) return false;
	Formation &f = formations[fi];
	if (enabled) {
		for (int i : f.members) if (vx[i] != 0 || vy[i] != 0 || escort_mode[i] != 0 || rescue_of[i] >= 0 || capture_of[i] >= 0) return false;
		order_hold(fi);
		f.ai_enabled = false; f.host_center = false;
		f.formal_cmd = f.acting_cmd = f.current_cmd = -1;
		f.officer_order.clear(); f.commander_present = false;
		f.needs_attack_order = true;
	}
	f.garrisoned = enabled; f.command_dirty = true;
	return true;
}

bool World::training_start_ready(int fi, double combat_now, bool fresh_inputs) const {
    if(fi<0 || fi>=(int)formations.size() || !std::isfinite(combat_now) || combat_now<0) return false;
    const auto &f=formations[fi];
    if(f.garrisoned || f.routed || f.order!=Order::HOLD || !command_eligible(f.current_cmd) ||
       combat_now>0 || !f.fully_fed || team_threat(f)) return false;
    for(int i:f.members) if(can_act(i)) {
        if(running[i] || vx[i]*vx[i]+vy[i]*vy[i]>.09f || rescue_of[i]>=0 || capture_of[i]>=0 ||
           escort_mode[i] || stagger[i]>0 || knock_t[i]>0) return false;
        if(fresh_inputs && host_ctl[i] && (host_vx[i]*host_vx[i]+host_vy[i]*host_vy[i]>.000001f || host_engage[i])) return false;
    }
    return true;
}

bool World::work_training_start_ready(int fi, double combat_now) const {
    return !work_point_active_ && training_start_ready(fi,combat_now,true);
}

bool World::apply_training_state(int fi, double before_training, double before_fatigue, double before_rest,
                                 double training, double fatigue, double rest, bool worked) {
	if (fi < 0 || fi >= (int)formations.size()) return false;
	Formation &f = formations[fi];
	for (double v : {before_training,before_fatigue,before_rest,training,fatigue,rest}) if (!std::isfinite(v)) return false;
	if (f.training != before_training || f.fatigue != before_fatigue || f.fatigue_rest != before_rest ||
	    training < f.training || training > std::max(1000.0,f.training) || fatigue < 0 || fatigue > 100 || rest < 0 || rest > FATIGUE_REST_DELAY ||
	    work_point_active_ || !training_start_ready(fi,combat_left,false)) return false;
	f.training = training; f.fatigue = fatigue; f.fatigue_rest = rest;
	f.charged_this_step = f.charged_this_step || worked;
	return true;
}

bool World::set_recovery_input(int fi, double multiplier) {
	if (fi < 0 || fi >= (int)formations.size()) return false;
	Formation &f = formations[fi];
	f.recovery_multiplier = 1.0; // A rejected replacement must not retain a previous bonus.
	if (!std::isfinite(multiplier) || multiplier < 1.0 || multiplier > 1.25 || (multiplier > 1.0 && !f.garrisoned)) return false;
	f.recovery_multiplier = multiplier;
	return true;
}

bool World::set_housing_attendance_input(int i, int destination) {
	if (i < 0 || i >= soldier_count() || housing_attendance_cell.size() != px.size()) return false;
	housing_attendance_cell[i] = -1;
	if (destination < 0) return destination == -1;
	if (destination >= terrain.w * terrain.h || !can_act(i) || escort_mode[i] != 0 || rescue_of[i] >= 0 || capture_of[i] >= 0 || stagger[i] > 0 || knock_t[i] > 0 || vx[i]*vx[i]+vy[i]*vy[i] > 1e-6f) return false;
	const Formation &f = formations[form[i]];
	if (f.order != Order::HOLD || f.garrisoned || f.routed || cell[i] != destination || !terrain.walkable(destination % terrain.w, destination / terrain.w)) return false;
	housing_attendance_cell[i] = destination;
	return true;
}

bool World::set_housing_recovery_input(int fi, double multiplier) {
	if (fi < 0 || fi >= (int)formations.size()) return false;
	Formation &f = formations[fi];
	f.housing_recovery_multiplier = 1.0;
	if (!std::isfinite(multiplier) || multiplier < 1.0 || multiplier > 1.25) return false;
	f.housing_recovery_multiplier = multiplier;
	return true;
}

bool World::set_fire_safe_rest_input(int fi, bool safe) {
	if (fi < 0 || fi >= (int)formations.size()) return false;
	formations[fi].host_fire_rest_safe = safe;
	return true;
}

// terrain_lab._advance_team_fatigue (game time). Running effort charges the shared pool; recovery needs
// the whole team safe: nothing charged since the last pass, nobody running or moving, HOLD, the Site
// combat clock at 0, every free member idle (no rescue / capture / get-up / stagger), no threat.
double World::fatigue_recovery_multiplier(int fi, double garrison, double housing) const {
	const Formation &f = formations[fi];
	if (garrison > 1.0) {
		if (!f.garrisoned) garrison = 1.0;
		for (int i : f.members) if (hp[i] > 0.0 && !can_act(i)) { garrison = 1.0; break; }
	}
	if (housing > 1.0) for (int i : f.members)
		if (hp[i] > 0.0 && (!can_act(i) || escort_mode[i] != 0 || housing_attendance_cell[i] < 0 || cell[i] != housing_attendance_cell[i] || (host_ctl[i] && (host_vx[i] != 0 || host_vy[i] != 0 || host_engage[i])))) { housing = 1.0; break; }
	return std::max(garrison, housing);
}

bool World::safe_fatigue_rest(int fi, bool busy, bool threat, bool fire_safe, double combat_now) const {
	const Formation &f = formations[fi];
	return !f.charged_this_step && !busy && f.order == Order::HOLD && (combat_now <= 0.0 || fire_safe) && !threat &&
		(f.fatigue <= 0.0 || !team_threat(f));
}

double World::work_fatigue_rest_limit(int fi, double target, double maximum, double combat_now) const {
	if (fi < 0 || fi >= (int)formations.size() || !std::isfinite(target) || target < 0 || target > FATIGUE_LIMIT ||
		!std::isfinite(maximum) || maximum <= 0 || !std::isfinite(combat_now) || combat_now < 0) return NAN;
	const Formation &f = formations[fi];
	if (f.fatigue <= target) return maximum;
	bool busy = false, threat = false;
	for (int i : f.members) {
		if (can_act(i)) {
			if (running[i]) return maximum;
			busy |= vx[i] * vx[i] + vy[i] * vy[i] > 0.09f || rescue_of[i] >= 0 || capture_of[i] >= 0 || escort_mode[i] != 0 || stagger[i] > 0.0 || knock_t[i] > 0.0 ||
				state[i] == S_FIGHT || state[i] == S_ENGAGE || state[i] == S_ENCIRCLE || state[i] == S_RANGED;
			threat |= near_enemy[i] != 0;
		}
		busy |= getup[i] > 0.0 && !captive[i] && hp[i] > 0.0;
	}
	if (!safe_fatigue_rest(fi, busy, threat, f.host_fire_rest_safe, combat_now)) return maximum;
	const double delay = std::max(0.0, FATIGUE_REST_DELAY - f.fatigue_rest);
	const double recovery = (f.fatigue - target) / (FATIGUE_RECOVERY_RATE * fatigue_recovery_multiplier(fi, f.recovery_multiplier, f.housing_recovery_multiplier));
	return std::min(maximum, delay > 0.0 ? delay : recovery);
}

void World::fatigue_stage(double gdt, const std::vector<WorkFatigueState> *work_plan) {
	const int n = soldier_count();
	static thread_local std::vector<int> runners, busy, threat, fight;
	fight.assign(formations.size(), 0);
	runners.assign(formations.size(), 0);
	busy.assign(formations.size(), 0);
	threat.assign(formations.size(), 0);
	for (int i = 0; i < n; ++i) {
		if (!can_act(i)) continue;
		int fi = form[i];
		runners[fi] += running[i];
		if (vx[i] * vx[i] + vy[i] * vy[i] > 0.09f || rescue_of[i] >= 0 || capture_of[i] >= 0 || escort_mode[i] != 0 || stagger[i] > 0.0 || knock_t[i] > 0.0 ||
		    state[i] == S_FIGHT || state[i] == S_ENGAGE || state[i] == S_ENCIRCLE || state[i] == S_RANGED)
			busy[fi] = 1;
		threat[fi] |= near_enemy[i];
		fight[fi] |= state[i] == S_FIGHT;
	}
	size_t work_index = 0; // Call-local original pool allocation.
	for (size_t fi = 0; fi < formations.size(); ++fi) {
		Formation &f = formations[fi];
		double recovery_multiplier = fatigue_recovery_multiplier((int)fi, f.recovery_multiplier, f.housing_recovery_multiplier);
		f.recovery_multiplier = 1.0; // Consume even on a zero-time or unsafe step.
		f.housing_recovery_multiplier = 1.0; // Consume even for zero-time/unsafe phases.
		f.threat = threat[fi] != 0;
		f.in_contact = fight[fi] != 0;
		const bool host_fire_rest_safe = f.host_fire_rest_safe;
		f.host_fire_rest_safe = false;
		for (int i : f.members) if (getup[i] > 0.0 && !captive[i] && hp[i] > 0.0) { busy[fi] = 1; break; }
		if (gdt <= 0.0) { f.charged_this_step = false; continue; }
		const WorkFatigueState *covered = nullptr;
		if (work_plan && work_index < work_plan->size() && (*work_plan)[work_index].formation == (int)fi)
			covered = &(*work_plan)[work_index++];
		if (covered) {
			f.fatigue = covered->fatigue;
			f.fatigue_rest = covered->rest;
		} else if (runners[fi] > 0) {
			double nn = std::max(1, f.fatigue_count);
			f.fatigue = clampd(f.fatigue + FATIGUE_RUN_RATE * gdt * runners[fi] / nn, 0.0, FATIGUE_LIMIT);
			f.fatigue_rest = 0;
		} else {
			bool safe = safe_fatigue_rest((int)fi, busy[fi] != 0, f.threat, host_fire_rest_safe, combat_left);
			if (!safe) f.fatigue_rest = 0;
			else {
				double recovering = std::max(0.0, gdt - std::max(0.0, FATIGUE_REST_DELAY - f.fatigue_rest));
				f.fatigue = std::max(0.0, f.fatigue - recovering * FATIGUE_RECOVERY_RATE * recovery_multiplier);
				f.fatigue_rest = std::min(FATIGUE_REST_DELAY, f.fatigue_rest + gdt);
			}
		}
		if (work_point_active_) {
			auto &point=work_point_pools_[fi];
			point.native_base_fatigue=f.fatigue; point.native_base_rest=f.fatigue_rest;
			point.base_captured=true;
		}
		f.charged_this_step = false; // shared.active = false after the pass
	}
}

} // namespace wg
