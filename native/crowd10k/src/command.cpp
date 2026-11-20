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
	float hx = (float)(cols - 1) * 0.5f * slot_spacing(f), hy = (float)(rows - 1) * 0.5f * slot_spacing(f); // CAV-4a mounted layout
	float radius = std::max(8.f, std::sqrt(hx * hx + hy * hy) + 2.f);
	for (int i : f.members) {
		if (!can_act(i)) { present[i] = 0; continue; }
		// G1/G3: an aboard soldier counts as present (as on the grid, a commander who boards keeps command);
		// its deck point is not a formation position.
		if (is_aboard(i)) { present[i] = 1; continue; }
		float r = radius + (present[i] ? 2.f : 0.f);
		float dx = px[i] - f.ref_x, dy = py[i] - f.ref_y;
		present[i] = (uint8_t)(dx * dx + dy * dy <= r * r);
	}
}

int World::select_commander(Formation &f) {
	for (int i : f.officer_order)
		if (alive(i) && command_eligible(i)) return i;
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
	                                     [&](int i) { return !alive(i) || i == f.formal_cmd; }),
	                      f.officer_order.end());
	bool permanent_vacancy = f.formal_cmd < 0 || !alive(f.formal_cmd);
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

// G5 S4 surrender (NEKKI 2026-10-30 A). A routed member with no escape route surrenders, as the grid does when
// prepare_morale_retreat fails and morale_retreat_terrain_trapped holds (terrain_army.gd). Trap test, deterministic:
// walk the 8-direction legal edges (terrain.edge_ok) from the member's own cell. The member is trapped when no reachable
// cell lies kTrapRadius (6) or more cells away (Euclidean on cell offsets). Walled pockets and boxed units are trapped;
// open ground never is. The walk stays inside a 13 x 13 box, so its cost is bounded.
constexpr int kTrapRadius = 6;
bool World::retreat_trapped(int i) const {
	constexpr int R = kTrapRadius, W = 2 * R + 1;
	const int sx = (int)std::floor(px[i]), sy = (int)std::floor(py[i]);
	if (sx < 0 || sy < 0 || sx >= terrain.w || sy >= terrain.h) return false;
	uint8_t seen[W * W] = {};
	int qx[W * W], qy[W * W], head = 0, tail = 0;
	qx[tail] = 0; qy[tail] = 0; ++tail; seen[R * W + R] = 1;
	while (head < tail) {
		const int x = qx[head], y = qy[head]; ++head;
		const uint8_t edges = terrain.edge_ok[terrain.idx(sx + x, sy + y)];
		for (int dir = 0; dir < 8; ++dir) {
			if (!((edges >> dir) & 1)) continue;
			const int ox = x + DX[dir], oy = y + DY[dir];
			if (ox * ox + oy * oy >= R * R) return false; // open ground within reach: an escape route
			if (seen[(oy + R) * W + ox + R]) continue;
			seen[(oy + R) * W + ox + R] = 1; qx[tail] = ox; qy[tail] = oy; ++tail;
		}
	}
	return true;
}

// Checked every 15 steps per member (tick-staggered): a pure function of state, so thread counts cannot change it.
// NEKKI 2026-10-30: a trapped member surrenders and at once becomes a captive (settle_surrender). A surrendered member
// that found no captor is retried on the same 15-step stagger, in any formation (a rallied formation keeps its members).
void World::surrender_trapped(int fi) {
	std::vector<uint8_t> held; // captives per captor; built on first use in this call
	for (int i : formations[fi].members) {
		if ((tick + (uint32_t)i) % 15 != 0) continue;
		if (is_surrendered(i)) { settle_surrender(i, held); continue; }
		if (!formations[fi].routed || !can_act(i) || prison_id[i] != 0 || escort_mode[i] != 0 || rescue_of[i] >= 0 || capture_of[i] >= 0 ||
		    is_crewed(i) || siege_group(i) >= 0 || controlled_step_pending(i)) continue;
		if (retreat_trapped(i) && set_surrendered(i, true)) settle_surrender(i, held);
	}
}

// Captor for a surrendered member t: the hostile formation nearest t (distance from t to the formation centre, ties to
// the lower formation index) that has an able member with guard room; inside it, the nearest such member (ties to the
// lower person_id). A formation with no able member is passed over. Returns -1 when no hostile formation can supply one.
int World::surrender_captor(int t, const std::vector<uint8_t> &held) const {
	std::vector<std::pair<float, int>> by_formation;
	for (size_t fi = 0; fi < formations.size(); ++fi) {
		const Formation &f = formations[fi];
		if (f.members.empty() || !hostile(team[t], f.team)) continue;
		const float dx = f.cx - px[t], dy = f.cy - py[t];
		by_formation.push_back({dx * dx + dy * dy, (int)fi});
	}
	std::sort(by_formation.begin(), by_formation.end());
	for (const auto &entry : by_formation) {
		int best = -1;
		float best_d2 = 0.f;
		int64_t best_person = 0;
		for (int g : formations[entry.second].members) {
			if (!surrender_captor_able(g, t) || held[g] >= GUARD_CAPACITY) continue;
			const float dx = px[g] - px[t], dy = py[g] - py[t], d2 = dx * dx + dy * dy;
			if (best < 0 || d2 < best_d2 || (d2 == best_d2 && person_id[g] < best_person)) { best = g; best_d2 = d2; best_person = person_id[g]; }
		}
		if (best >= 0) return best;
	}
	return -1;
}

// A soldier that can take a surrendered prisoner: the same guard conditions as auto-capture, minus its idle requirement.
bool World::surrender_captor_able(int g, int t) const {
	return g != t && can_act(g) && hostile(team[g], team[t]) && escort_mode[g] == 0 && !is_crewed(g) && siege_group(g) < 0 &&
	       stagger[g] <= 0.0 && rescue_of[g] < 0 && capture_of[g] < 0 && prison_id[g] == 0;
}

// G5 S4 (NEKKI 2026-10-30): a surrendered member becomes a captive of its captor at once. The state is the one a completed
// capture leaves in person_actions_stage (captive, captor, escape timer, captives_, command, target, capture count and the
// capture event). A surrender with no captor stays surrendered and returns false. A dead member loses the flag.
// held: captives per captor, built here on first use (scratch, sized to the soldiers).
bool World::settle_surrender(int t, std::vector<uint8_t> &held) {
	if (!alive(t) || captive[t]) { surrendered[t] = 0; return false; }
	if (held.empty()) {
		held.assign((size_t)soldier_count(), 0);
		for (int c : captives_) if (captive[c] && prison_id[c] == 0 && alive(c) && captor[c] >= 0) held[captor[c]]++;
	}
	const int g = surrender_captor(t, held);
	if (g < 0) return false;
	cancel_actions_involving(t); // a rescue or capture aimed at t is cancelled, as the completed capture cancels its rescuer
	captive[t] = 1; captor[t] = g; escape_t[t] = 0; surrendered[t] = 0;
	captives_.push_back(t);
	formations[form[t]].command_dirty = true;
	enc_target[t] = -1; target[t] = -1;
	stats.captures_done++;
	push_event(EV_CAPTURED, t, g);
	held[g]++;
	return true;
}

bool World::set_surrendered(int i, bool on) {
	if (i < 0 || i >= soldier_count()) return false;
	if (!on) { surrendered[i] = 0; formations[form[i]].command_dirty = true; return true; }
	if (!alive(i) || ko[i] > 0.0 || getup[i] > 0.0 || captive[i] || prison_id[i] != 0 || escort_mode[i] != 0 || rescue_of[i] >= 0 ||
	    capture_of[i] >= 0 || is_crewed(i) || siege_group(i) >= 0) return false;
	surrendered[i] = 1;
	// Nobody keeps naming the surrendered soldier as a target (as site_person_absent does).
	for (int j = 0; j < soldier_count(); ++j) {
		if (target[j] == i) target[j] = -1;
		if (enc_target[j] == i) enc_target[j] = -1;
	}
	for (auto &g : formations) if (g.target_person == i) g.target_person = -1;
	target[i] = -1; enc_target[i] = -1; near_enemy[i] = 0; vx[i] = vy[i] = 0; nx[i] = px[i]; ny[i] = py[i];
	formations[form[i]].command_dirty = true;
	return true;
}

// _fatigue_threat / _exchange_rest_threat for every living, uncaptured member: an able hostile soldier
// within 8 steps (Manhattan, legality not re-checked: a superset), or the member's cell on the path
// of an arrow in flight.
bool World::team_threat(const Formation &f) const {
	const float R = 8.f;
	for (int i : f.members) {
		if (!alive(i) || captive[i]) continue;
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
		if (!alive(i) || captive[i]) continue;
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
		surrender_trapped((int)fi); // routed members are tested here; surrendered members are retried in any formation
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
	if (f.order != Order::HOLD || f.routed || f.garrisoned || is_crewed(i) || prison_id[i] != 0 || rescue_of[i] >= 0 || capture_of[i] >= 0) return false;
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

// ---------------------------------------------------------------- G6.4 site exit (travel departure)
// A soldier may leave the Site only when it is conscious and free, in a formation, not in a melee exchange and
// with no committed step (escort / custody / rescue / capture / siege / stagger / knockback). Host-controlled
// soldiers and captors are refused. Refusals change nothing.
bool World::site_person_exit_ready(int i) const {
	return exit_ready_checks(i, false);
}

// SHIPSEA: the same exit gate for a soldier aboard `vehicle`. Aboard is the required state of a sea departure, so it
// is accepted here (siege and convoy crew still refuse); every other guard is site_person_exit_ready's.
bool World::site_person_exit_ready_aboard(int i, int vehicle) const {
	if (i < 0 || i >= soldier_count() || vehicle < 0 || !is_aboard(i) || aboard_vehicle[i] != vehicle) return false;
	return exit_ready_checks(i, true);
}

bool World::exit_ready_checks(int i, bool aboard_ok) const {
	if (i < 0 || i >= soldier_count() || !can_act(i) || host_ctl[i]) return false;
	const int fi = form[i];
	if (fi < 0 || fi >= (int)formations.size()) return false;
	const std::vector<int> &members = formations[fi].members;
	if (std::find(members.begin(), members.end(), i) == members.end()) return false;
	if (escort_mode[i] != 0 || escort_goal[i] >= 0 || prison_id[i] != 0) return false;
	if (rescue_of[i] >= 0 || capture_of[i] >= 0 || siege_group(i) >= 0) return false;
	if (aboard_ok ? (is_siege_crew(i) || is_convoy_crew(i)) : is_crewed(i)) return false;
	if (stagger[i] > 0.0 || knock_t[i] > 0.0) return false;
	if (in_melee_exchange(i)) return false;
	for (int j = 0; j < soldier_count(); ++j)
		if (captive[j] && captor[j] == i) return false; // still holds a captive
	return true;
}

bool World::in_melee_exchange(int i) const {
	auto melee = [&](int j) { return state[j] == S_FIGHT || state[j] == S_ENGAGE || state[j] == S_ENCIRCLE; };
	if (melee(i) || enc_target[i] >= 0) return true;
	for (int j = 0; j < soldier_count(); ++j)
		if (j != i && (target[j] == i || enc_target[j] == i) && melee(j)) return true;
	return false;
}

// Removes a ready soldier from the live pool and its formation without reindexing any array: the soldier keeps
// its slot in every SoA array, is marked released (alive / can_act / render / hash / exchange / ranged all skip
// it), is dropped from formation members by compact_slots and loses its fatigue binding and roster place.
// Its hp, ammo and position are kept in the receipt; the flag is saved, so a reload keeps it released.
bool World::site_person_release(int i, SitePersonRelease &out) {
	if (work_point_active_ || work_point_finish_ready_ || !site_person_exit_ready(i)) return false;
	release_ready(i, out);
	return true;
}

// SHIPSEA: a soldier aboard `vehicle` leaves the Site with its vessel (sea departure). The aboard flag and vehicle are
// cleared first (a released soldier is not aboard), then the release is site_person_release's; the receipt position is
// the deck point the host last set (site_person_set_deck). Refuses (writes nothing) unless site_person_exit_ready_aboard.
bool World::site_person_release_aboard(int i, int vehicle, SitePersonRelease &out) {
	if (work_point_active_ || work_point_finish_ready_ || !site_person_exit_ready_aboard(i, vehicle)) return false;
	aboard[i] = 0; aboard_vehicle[i] = -1;
	release_ready(i, out);
	return true;
}

bool World::site_person_release_dead(int i, SitePersonRelease &out) {
	if (work_point_active_ || work_point_finish_ready_) return false;
	if (i < 0 || i >= soldier_count() || released[i] || hp[i] > 0.0 || captive[i] || is_aboard(i) || siege_group(i) >= 0) return false;
	const int fi = form[i];
	if (fi < 0 || fi >= (int)formations.size()) return false;
	const int pool = formations[fi].fatigue_count;
	release_ready(i, out);
	formations[fi].fatigue_count = pool; // the death already left the shared pool (combat.cpp); release_ready would count it twice
	return true;
}

bool World::site_person_retag_released(int i, int64_t placeholder) {
	if (i < 0 || i >= soldier_count() || !released[i] || placeholder < 0) return false;
	if (soldier_index(placeholder) >= 0) return false;
	person_id[i] = placeholder;
	person_index_.clear(); // rebuilt on the next lookup
	return true;
}

bool World::site_formation_reuse(int fi, int t, float cx, float cy, float facing, int cols, float spacing, Troop tr, double training) {
	if (!finalized_ || work_point_active_ || work_point_finish_ready_) return false;
	if (fi < 0 || fi >= (int)formations.size() || t < 0 || t > 255 || cols < 1 || tr > T_CROSSBOW) return false;
	if (!std::isfinite(cx) || !std::isfinite(cy) || !std::isfinite(facing) || !std::isfinite(spacing) || !std::isfinite(training)) return false;
	const Formation &old = formations[fi];
	if (old.roster != 0 || !old.members.empty()) return false;
	const int n = soldier_count();
	for (int i = 0; i < n; ++i) if (form[i] == fi && !released[i]) return false;
	// The same values add_formation gives a new formation; the index (and so the seed of its random stream) is its own.
	Formation f;
	f.team = t; f.cx = f.goal_x = f.origin_x = cx; f.cy = f.goal_y = f.origin_y = cy;
	f.facing = f.goal_facing = facing; f.cols = cols; f.spacing = spacing; f.troop = tr; f.training = training;
	f.rng = 0x9E3779B97F4A7C15ull ^ ((uint64_t)fi * 0xBF58476D1CE4E5B9ull) ^ (uint64_t)cfg.seed;
	formations[fi] = std::move(f);
	const size_t count = formations.size();
	if (touch_.size() == count * count) for (size_t k = 0; k < count; ++k) touch_[(size_t)fi * count + k] = touch_[k * count + (size_t)fi] = 0;
	if ((size_t)fi < lag_acc_.size()) lag_acc_[fi] = 0;
	if ((size_t)fi < lag_cnt_.size()) lag_cnt_[fi] = 0;
	if ((size_t)fi < work_point_pools_.size()) work_point_pools_[fi] = WorkPointPool{};
	build_faction_slots();
	return true;
}

bool World::site_person_readmit(int i, int fi, const rules::Equip &e, Role r, uint16_t ammo_count) {
	if (!finalized_ || work_point_active_ || work_point_finish_ready_) return false;
	if (i < 0 || i >= soldier_count() || !released[i] || fi < 0 || fi >= (int)formations.size()) return false;
	if (e.family > rules::F_SHOVEL || e.material > rules::M_STEEL || e.armor > rules::A_MINGGUANG) return false;
	// The formation it left keeps no reference to it (release_ready dropped its membership, roster place and officer entry).
	Formation &o = formations[form[i]];
	if (o.formal_cmd == i) o.formal_cmd = -1;
	if (o.acting_cmd == i) o.acting_cmd = -1;
	if (o.current_cmd == i) o.current_cmd = -1;
	if (o.target_person == i) o.target_person = -1;
	o.members.erase(std::remove(o.members.begin(), o.members.end(), i), o.members.end());
	o.officer_order.erase(std::remove(o.officer_order.begin(), o.officer_order.end(), i), o.officer_order.end());
	o.command_dirty = true;
	Formation &f = formations[fi];
	// Every per-soldier value add_soldier writes, in its order; ability and person_id are the person's own and stay.
	px[i] = nx[i] = f.cx; py[i] = ny[i] = f.cy; vx[i] = vy[i] = 0.f; face[i] = f.facing;
	anim_t[i] = 0.f;
	hp[i] = 100.0;
	for (auto *v : {&stun, &grace, &ko, &getup, &stagger, &exch_cd, &ranged_cd, &skill_cd, &knock_t, &act_t, &escape_t}) (*v)[i] = 0.0;
	knock_dx[i] = knock_dy[i] = 0.f;
	rest_hold[i] = 0; rest_x[i] = rest_y[i] = 0.f; rest_best[i] = 1e9f; rest_t[i] = 0.f;
	team[i] = (uint8_t)f.team; state[i] = S_SLOT; los_ok[i] = 1; skill[i] = (uint8_t)rules::SK_NONE;
	role[i] = (uint8_t)r; captive[i] = 0; present[i] = 1;
	troop[i] = (uint8_t)(e.family == rules::F_BOW ? T_BOW : e.family == rules::F_CROSSBOW ? T_CROSSBOW : T_MELEE);
	running[i] = 0; near_enemy[i] = 0; fire_blocked[i] = 0; bandaged[i] = 0;
	form[i] = fi; slot[i] = -1; target[i] = -1; cell[i] = -1; enc_target[i] = -1;
	rescue_of[i] = -1; capture_of[i] = -1; captor[i] = -1; life_ck[i] = 0;
	prison_id[i] = 0; escort_goal[i] = -1; escort_mode[i] = 0; housing_attendance_cell[i] = -1;
	melee_ability[i] = riding_ability[i] = ranged_ability[i] = (float)rules::TROOP_COMBAT_ABILITY; rescue_rate[i] = 1.f;
	contact_revision[i] = 0;
	siege_crew[i] = 0; siege_member_group[i] = -1; siege_step_source[i] = -1;
	if ((size_t)i < siege_wreck_exit.size()) siege_wreck_exit[i].clear();
	convoy_of[i] = 0;
	start_x[i] = NAN; start_y[i] = NAN;
	host_ctl[i] = 0; host_run[i] = 0; host_engage[i] = 0; host_vx[i] = host_vy[i] = 0.f;
	vis_kind[i] = (uint8_t)V_IDLE; vis_t0[i] = -1e9; kit[i] = -1;
	fire_visual[i] = 0;
	ammo[i] = ammo_count; equip[i] = e;
	military_role[i] = 1; post_holder[i] = 1;
	released[i] = 0;
	aboard[i] = 0; aboard_vehicle[i] = -1;
	absent[i] = 0; absent_kind[i] = 0; surrendered[i] = 0;
	mounted[i] = 0; cav_hits[i] = 0;
	for (int k = 0; k < cav::HEADING_WINDOW; ++k) cav_hist[(size_t)i * cav::HEADING_WINDOW + k] = 0.f;
	cav_hold[i] = 0.0; cav_down[i] = 0.0;
	for (int k = 0; k < cav::RECENT_VICTIMS; ++k) { cav_hit_who[(size_t)i * cav::RECENT_VICTIMS + k] = -1; cav_hit_t[(size_t)i * cav::RECENT_VICTIMS + k] = -1e9; }
	cav_spent[i] = 0;
	for (int j = 0; j < soldier_count(); ++j) { // nothing names the slot's previous stay
		if (target[j] == i) target[j] = -1;
		if (enc_target[j] == i) enc_target[j] = -1;
	}
	rescued_by_[i] = -1; capturing_by_[i] = -1; attackers_[i] = 0; slot_tx_[i] = f.cx; slot_ty_[i] = f.cy; slot_clip_[i] = 1.f;
	// Joins the formation as a soldier added to a finalized World does.
	f.members.push_back(i);
	f.roster++; f.fatigue_count++;
	if (r == R_CAPTAIN && f.formal_cmd < 0) f.formal_cmd = i;
	if (r == R_OFFICER && std::find(f.officer_order.begin(), f.officer_order.end(), i) == f.officer_order.end()) f.officer_order.push_back(i);
	if (r != R_REGULAR) ensure_ability(i, f);
	compact_slots(f); // the joining soldier takes the last soldier slot
	build_faction_slots(); build_hash();
	const size_t ev = events.size(); settle_command(f, fi); events.resize(ev);
	f.commander_present = f.current_cmd >= 0 && command_eligible(f.current_cmd);
	return true;
}

void World::release_ready(int i, SitePersonRelease &out) {
	Formation &f = formations[form[i]];
	out = SitePersonRelease{};
	out.hp = hp[i]; out.fatigue = f.fatigue; out.fatigue_rest = f.fatigue_rest; out.ammo = ammo[i];
	out.x = px[i]; out.y = py[i];
	out.cell_x = (int)px[i]; out.cell_y = (int)py[i];
	released[i] = 1;
	f.fatigue_count = std::max(0, f.fatigue_count - 1); // unbound from the shared pool, as a death is
	f.roster = std::max(0, f.roster - 1);               // leaves the formal roster; it is not a death
	for (int j = 0; j < soldier_count(); ++j) { // no order or exchange keeps naming the departed soldier
		if (target[j] == i) target[j] = -1;
		if (enc_target[j] == i) enc_target[j] = -1;
	}
	for (auto &g : formations) if (g.target_person == i) g.target_person = -1;
	f.officer_order.erase(std::remove(f.officer_order.begin(), f.officer_order.end(), i), f.officer_order.end());
	state[i] = S_SLOT; target[i] = -1; enc_target[i] = -1; near_enemy[i] = 0; running[i] = 0;
	vx[i] = vy[i] = 0; nx[i] = px[i]; ny[i] = py[i];
	cell[i] = terrain.idx(out.cell_x, out.cell_y);
	present[i] = 0;
	compact_slots(f); // drops the released soldier from members and renumbers the slots of the rest
	slot[i] = -1;
	f.command_dirty = true;
}

// ---------------------------------------------------------------- G1 S1 aboard (ship / vehicle)
// Board: a soldier that could leave the Site (site_person_exit_ready) goes aboard a vehicle. Unlike a release it stays
// alive, on the roster, fatigue-bound and in its formation's member list, as convoy crew do; it only gives up its slot
// (compact_slots) and loses every order, target and encounter that names it. Refusals change nothing.
bool World::site_person_board(int i, int vehicle) {
	if (work_point_active_ || work_point_finish_ready_ || vehicle < 0 || i < 0 || i >= soldier_count() || is_aboard(i)) return false;
	// A crowd person walks to a ship contact by host siege steps, and an arrived siege step stays held (mode 5, no goal).
	// Boarding ends that held step; a pending step (goal set) or any other escort still refuses.
	const uint8_t held_mode = escort_mode[i];
	const bool held_siege_step = held_mode == 5 && escort_goal[i] < 0;
	if (held_siege_step) escort_mode[i] = 0;
	if (!site_person_exit_ready(i)) { escort_mode[i] = held_mode; return false; }
	Formation &f = formations[form[i]];
	for (int j = 0; j < soldier_count(); ++j) {
		if (target[j] == i) target[j] = -1;
		if (enc_target[j] == i) enc_target[j] = -1;
	}
	for (auto &g : formations) if (g.target_person == i) g.target_person = -1;
	state[i] = S_SLOT; target[i] = -1; enc_target[i] = -1; near_enemy[i] = 0; running[i] = 0;
	vx[i] = vy[i] = 0; nx[i] = px[i]; ny[i] = py[i];
	aboard[i] = 1; aboard_vehicle[i] = vehicle;
	compact_slots(f); // the aboard soldier holds no soldier slot; the rest renumber
	f.command_dirty = true;
	return true;
}

// Land: an aboard living soldier steps onto a free walkable cell that no living non-aboard soldier and no convoy body
// occupies, and rejoins its formation (a soldier slot again, as convoy crew rejoin on release). Refusals change nothing.
// The cell a soldier may stand on after landing or returning: finite, inside the map, walkable, no convoy body and no
// other living non-aboard soldier (absent soldiers are not alive, so they hold no cell). Pure: changes nothing.
bool World::landing_cell(int i, double x, double y, float &fx, float &fy, int &cell_index) const {
	fx = (float)x; fy = (float)y;
	if (!std::isfinite(fx) || !std::isfinite(fy)) return false;
	const int cx = (int)std::floor(fx), cy = (int)std::floor(fy);
	if (!terrain.contains(cx, cy) || !terrain.walkable(cx, cy)) return false;
	const int c = terrain.idx(cx, cy);
	if (convoy_body_cell(c)) return false;
	for (int j = 0; j < soldier_count(); ++j) {
		if (j == i || !alive(j) || is_aboard(j)) continue;
		if ((int)std::floor(px[j]) == cx && (int)std::floor(py[j]) == cy) return false;
	}
	cell_index = c;
	return true;
}

bool World::site_person_land(int i, double x, double y) {
	if (work_point_active_ || work_point_finish_ready_ || !is_aboard(i) || !alive(i)) return false;
	float fx = 0, fy = 0;
	int c = -1;
	if (!landing_cell(i, x, y, fx, fy, c)) return false;
	aboard[i] = 0; aboard_vehicle[i] = -1;
	px[i] = nx[i] = fx; py[i] = ny[i] = fy;
	vx[i] = vy[i] = 0; cell[i] = c;
	Formation &f = formations[form[i]];
	compact_slots(f); // rejoin: the landed soldier takes a soldier slot again
	f.command_dirty = true;
	return true;
}

// Deck position of an aboard soldier, set by the host every tick (presentation and ranged origin). Nothing else reads it.
bool World::site_person_set_deck(int i, double x, double y) {
	if (!is_aboard(i)) return false;
	const float fx = (float)x, fy = (float)y;
	if (!std::isfinite(fx) || !std::isfinite(fy)) return false;
	const int cx = (int)std::floor(fx), cy = (int)std::floor(fy);
	if (!terrain.contains(cx, cy)) return false;
	px[i] = nx[i] = fx; py[i] = ny[i] = fy;
	cell[i] = terrain.idx(cx, cy);
	return true;
}

// Aboard to aboard: a ship-to-ship crossing changes the vehicle only.
bool World::site_person_retarget_aboard(int i, int vehicle) {
	if (!is_aboard(i) || vehicle < 0) return false;
	aboard_vehicle[i] = vehicle;
	return true;
}

// ---------------------------------------------------------------- G5 S1 absent / return / move_member (roster)
// Changes the formation of a living soldier (on the field or absent) and keeps both rosters honest: the leaving formation
// drops the member, its commander references, its officer order entry and one roster place and fatigue binding; the
// joining formation gains them. A soldier joining as a captain takes the formal command when there is none.
void World::reassign_formation(int i, int to) {
	const int from = form[i];
	Formation &o = formations[from];
	o.members.erase(std::remove(o.members.begin(), o.members.end(), i), o.members.end());
	o.officer_order.erase(std::remove(o.officer_order.begin(), o.officer_order.end(), i), o.officer_order.end());
	if (o.formal_cmd == i) o.formal_cmd = -1;
	if (o.acting_cmd == i) o.acting_cmd = -1;
	if (o.current_cmd == i) o.current_cmd = -1;
	if (o.target_person == i) o.target_person = -1;
	o.fatigue_count = std::max(0, o.fatigue_count - 1); // unbound from the old pool, as a departure is
	o.roster = std::max(0, o.roster - 1);
	slot[i] = -1;
	compact_slots(o); // renumbers the rest; the leaving soldier is no longer a member
	o.command_dirty = true;

	form[i] = to;
	Formation &n = formations[to];
	n.members.push_back(i);
	n.roster++; n.fatigue_count++;                      // bound to the new pool, as add_soldier binds a soldier
	if (role[i] == R_OFFICER && std::find(n.officer_order.begin(), n.officer_order.end(), i) == n.officer_order.end()) n.officer_order.push_back(i);
	if (role[i] == R_CAPTAIN && n.formal_cmd < 0) n.formal_cmd = i;
	if (role[i] != R_REGULAR) ensure_ability(i, n);
	slot[i] = -1;                                      // the joining soldier takes the last soldier slot
	compact_slots(n);
	n.command_dirty = true;
}

// Kinds: 1 detached, 2 left the Site, 3 (reserved by the host), 4 garrison, 5 at home inside a house (平民 C1c; the host
// still counts the person on its roster; not drawn, no collision, never a target).
bool World::site_person_absent(int i, int kind) {
	if (work_point_active_ || work_point_finish_ready_ || kind < 1 || kind > 5 || i < 0 || i >= soldier_count()) return false;
	if (is_absent(i) || is_aboard(i) || is_surrendered(i) || !site_person_exit_ready(i)) return false;
	Formation &f = formations[form[i]];
	absent[i] = 1; absent_kind[i] = (uint8_t)kind;
	for (int j = 0; j < soldier_count(); ++j) { // no order or exchange keeps naming the absent soldier
		if (target[j] == i) target[j] = -1;
		if (enc_target[j] == i) enc_target[j] = -1;
	}
	for (auto &g : formations) if (g.target_person == i) g.target_person = -1;
	f.officer_order.erase(std::remove(f.officer_order.begin(), f.officer_order.end(), i), f.officer_order.end());
	state[i] = S_SLOT; target[i] = -1; enc_target[i] = -1; near_enemy[i] = 0; running[i] = 0;
	vx[i] = vy[i] = 0; nx[i] = px[i]; ny[i] = py[i];
	present[i] = 0;
	compact_slots(f); // drops the absent soldier from members (it is not alive) and renumbers the rest
	slot[i] = -1;
	f.command_dirty = true;
	return true;
}

// Return: an absent living soldier lands on a free walkable cell (landing_cell, as site_person_land) of a formation of
// its team that is not garrisoned, and rejoins it. Its roster place and fatigue binding were kept while absent.
bool World::site_person_return(int i, int formation, double x, double y) {
	if (work_point_active_ || work_point_finish_ready_ || !is_absent(i) || is_aboard(i) || hp[i] <= 0.0 || released[i]) return false;
	if (formation < 0 || formation >= (int)formations.size()) return false;
	if (formations[formation].team != formations[form[i]].team || formations[formation].garrisoned) return false;
	float fx = 0, fy = 0;
	int c = -1;
	if (!landing_cell(i, x, y, fx, fy, c)) return false;
	absent[i] = 0; absent_kind[i] = 0;
	px[i] = nx[i] = fx; py[i] = ny[i] = fy; vx[i] = vy[i] = 0; cell[i] = c;
	state[i] = S_SLOT; target[i] = -1; enc_target[i] = -1; near_enemy[i] = 0; running[i] = 0;
	if (formation != form[i]) {
		reassign_formation(i, formation);
	} else {
		Formation &f = formations[formation];
		if (std::find(f.members.begin(), f.members.end(), i) == f.members.end()) f.members.push_back(i);
		slot[i] = -1;
		compact_slots(f);
		f.command_dirty = true;
	}
	return true;
}

// Move: a living soldier on the field or absent changes formation atomically. Refused: same formation, another team,
// dead or released, aboard, convoy crew, siege crew, and an on-field soldier into or out of a garrisoned formation
// (a garrisoned roster is held in barracks; its reserve is absent, not on the field).
bool World::move_member(int i, int to) {
	if (work_point_active_ || work_point_finish_ready_ || i < 0 || i >= soldier_count() || to < 0 || to >= (int)formations.size()) return false;
	const int from = form[i];
	if (from < 0 || from >= (int)formations.size() || from == to) return false;
	if (formations[from].team != formations[to].team) return false;
	if (hp[i] <= 0.0 || released[i] || is_aboard(i) || is_convoy_crew(i) || is_siege_crew(i)) return false;
	const bool on_field = !absent[i];
	if (on_field && (formations[from].garrisoned || formations[to].garrisoned)) return false;
	if (on_field) { // as site_person_absent: no order or exchange keeps naming a soldier that moves formation
		for (int j = 0; j < soldier_count(); ++j) {
			if (target[j] == i) target[j] = -1;
			if (enc_target[j] == i) enc_target[j] = -1;
		}
		state[i] = S_SLOT; target[i] = -1; enc_target[i] = -1; near_enemy[i] = 0; running[i] = 0;
		vx[i] = vy[i] = 0; nx[i] = px[i]; ny[i] = py[i];
	}
	for (auto &g : formations) if (g.target_person == i) g.target_person = -1;
	reassign_formation(i, to);
	return true;
}

// ---------------------------------------------------------------- persuasion transfer (NEKKI 2026-10-30, captive joins captor)
// Transfer: an awake captive on the field of one team becomes a normal living member of another team's formation. The
// captivity ends as a release ends it (captive, captor, escape timer, escort, captives_ and targets are cleared), the
// soldier takes the target team (team[] too, so hostility follows the new team) and the formation roster through
// reassign_formation, keeping position, hp, ammo, equipment, person id and absent / released flags (none set).
// Refusals change nothing: not captive, dead, knocked out, absent, aboard, released, convoy or siege crew, in a prison,
// under housing or siege escort, surrendered, same team, same formation, garrisoned target, bad ids.
bool World::transfer_member(int i, int to) {
	if (work_point_active_ || work_point_finish_ready_ || i < 0 || i >= soldier_count() || to < 0 || to >= (int)formations.size()) return false;
	const int from = form[i];
	if (from < 0 || from >= (int)formations.size() || from == to || formations[from].team == formations[to].team) return false;
	if (formations[to].garrisoned) return false;
	if (!captive[i] || !alive(i) || ko[i] > 0.0 || getup[i] > 0.0 || surrendered[i]) return false;
	if (is_absent(i) || is_aboard(i) || is_convoy_crew(i) || is_siege_crew(i) || prison_id[i] != 0) return false;
	if (escort_mode[i] == 3 || escort_mode[i] == 4 || escort_mode[i] == 5 || escort_mode[i] == 6) return false;
	cancel_actions_involving(i);
	captive[i] = 0; captor[i] = -1; escape_t[i] = 0;
	escort_mode[i] = 0; escort_goal[i] = -1;
	captives_.erase(std::remove(captives_.begin(), captives_.end(), i), captives_.end());
	reassign_formation(i, to);
	team[i] = (uint8_t)formations[to].team;
	state[i] = S_SLOT; target[i] = -1; enc_target[i] = -1; near_enemy[i] = 0; running[i] = 0;
	vx[i] = vy[i] = 0; nx[i] = px[i]; ny[i] = py[i];
	return true;
}

// Leave (NEKKI 2026-11-04, joining in person): an awake, free member on the field of one team becomes a normal member of
// another team's formation, as a captive does in transfer_member but without captivity. A cadre who will not follow his
// captain into another faction leaves this way for his own one-person team. Orders, exchanges and targets naming him are
// cleared as move_member clears them; the soldier takes the target team (team[] too, so hostility follows) and keeps
// position, hp, ammo, equipment and person id. Refusals change nothing: captive, dead, knocked out, getting up,
// surrendered, absent, aboard, released, convoy or siege crew, in a prison, under escort, same team, same formation,
// garrisoned source or target, bad ids.
bool World::leave_member(int i, int to) {
	if (work_point_active_ || work_point_finish_ready_ || i < 0 || i >= soldier_count() || to < 0 || to >= (int)formations.size()) return false;
	const int from = form[i];
	if (from < 0 || from >= (int)formations.size() || from == to || formations[from].team == formations[to].team) return false;
	if (formations[from].garrisoned || formations[to].garrisoned) return false;
	if (captive[i] || !alive(i) || ko[i] > 0.0 || getup[i] > 0.0 || surrendered[i] || released[i]) return false;
	if (is_absent(i) || is_aboard(i) || is_convoy_crew(i) || is_siege_crew(i) || prison_id[i] != 0 || escort_mode[i] != 0) return false;
	cancel_actions_involving(i);
	for (int j = 0; j < soldier_count(); ++j) {
		if (target[j] == i) target[j] = -1;
		if (enc_target[j] == i) enc_target[j] = -1;
	}
	for (auto &g : formations) if (g.target_person == i) g.target_person = -1;
	reassign_formation(i, to);
	team[i] = (uint8_t)formations[to].team;
	// Faction slots are built from soldiers' teams; a team whose formation was just added has none yet, so the per-slot
	// block tables must be rebuilt before the next step indexes them with this soldier's team.
	if (faction_slot_[team[i]] < 0) build_faction_slots();
	state[i] = S_SLOT; target[i] = -1; enc_target[i] = -1; near_enemy[i] = 0; running[i] = 0;
	vx[i] = vy[i] = 0; nx[i] = px[i]; ny[i] = py[i];
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

bool World::set_formation_shape(int fi, const std::vector<float> &offsets) {
	if (fi < 0 || fi >= (int)formations.size()) return false;
	if (offsets.size() % 2 != 0 || offsets.size() > 2 * (size_t)MAX_SHAPE_SLOTS) return false;
	for (float v : offsets) if (!std::isfinite(v) || std::fabs(v) > 64.f) return false;
	Formation &f = formations[fi];
	if (f.garrisoned) return false;
	f.shape = offsets;
	reslot_formation(f);
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
		for (int i : f.members) if (alive(i) && !can_act(i)) { garrison = 1.0; break; }
	}
	if (housing > 1.0) for (int i : f.members)
		if (alive(i) && (!can_act(i) || escort_mode[i] != 0 || housing_attendance_cell[i] < 0 || cell[i] != housing_attendance_cell[i] || (host_ctl[i] && (host_vx[i] != 0 || host_vy[i] != 0 || host_engage[i])))) { housing = 1.0; break; }
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
			busy |= vx[i] * vx[i] + vy[i] * vy[i] > 0.09f || rescue_of[i] >= 0 || capture_of[i] >= 0 || (escort_mode[i] != 0 && !siege_step_holding(i)) || stagger[i] > 0.0 || knock_t[i] > 0.0 ||
				state[i] == S_FIGHT || state[i] == S_ENGAGE || state[i] == S_ENCIRCLE || state[i] == S_RANGED;
			threat |= near_enemy[i] != 0;
		}
		busy |= getup[i] > 0.0 && !captive[i] && alive(i);
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
		if (vx[i] * vx[i] + vy[i] * vy[i] > 0.09f || rescue_of[i] >= 0 || capture_of[i] >= 0 || (escort_mode[i] != 0 && !siege_step_holding(i)) || stagger[i] > 0.0 || knock_t[i] > 0.0 ||
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
		for (int i : f.members) if (getup[i] > 0.0 && !captive[i] && alive(i)) { busy[fi] = 1; break; }
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
