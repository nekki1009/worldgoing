// Tactical AI (port of scripts/terrain_lab/site_army_ai.gd, REVIEW_SECONDS 0.5) and the
// post-contact encirclement review (exchange v1, 2026-09-14 / 09-15).
#include "crowd_core.hpp"

#include <algorithm>

namespace wg {

using namespace rules;

static constexpr double HOLD_RATIO = 0.65, RESUME_RATIO = 0.90, THREAT_DISTANCE = 12.0, ORDER_DELAY = 2.0,
                        FAILED_RETRY = 3.0, REVIEW = 0.5;

struct Summary {
	int team = 0, count = 0, ready = 0;
	double power = 0, hp_sum = 0, health = 0, fatigue = 0, morale = 100, ready_fraction = 0, range = 0;
	bool ammo_empty = false, recovering = false;
	int minx = 1 << 30, miny = 1 << 30, maxx = -(1 << 30), maxy = -(1 << 30);
	Order order = Order::HOLD;
};

static double gap(const Summary &a, const Summary &b) {
	int dx = std::max(0, std::max(b.minx - a.maxx, a.minx - b.maxx));
	int dy = std::max(0, std::max(b.miny - a.maxy, a.miny - b.maxy));
	return std::sqrt((double)(dx * dx + dy * dy));
}

void World::issue(Formation &f, int fi, Order o, float gx, float gy, int tgt) {
	bool ok = true;
	switch (o) {
	case Order::HOLD: order_hold(fi); break;
	case Order::ATTACK: order_attack(fi, tgt); break;
	case Order::PURSUE: order_pursue(fi, tgt); break;
	case Order::MOVE: {
		int cx = (int)gx, cy = (int)gy;
		ok = terrain.contains(cx, cy) && terrain.walkable(cx, cy);
		if (ok) {
			float dx = gx - f.cx, dy = gy - f.cy;
			order_move(fi, gx, gy, (dx * dx + dy * dy) > 1e-4f ? std::atan2(dy, dx) : f.facing);
		}
		break;
	}
	default: ok = false;
	}
	f.ai_order_cd = ok ? ORDER_DELAY : FAILED_RETRY;
	if (ok) stats.ai_orders++;
}

void World::ai_review() {
	const size_t F = formations.size();
	std::vector<Summary> sum(F);
	// touching: an able member within reach of an able enemy member (legal line) this review
	std::fill(touch_.begin(), touch_.end(), 0);
	const int n = soldier_count();
	const float r2 = cfg.reach * cfg.reach;
	for (int i = 0; i < n; ++i) {
		int t = target[i];
		if (t < 0 || !can_act(i) || !can_act(t)) continue;
		float dx = px[t] - px[i], dy = py[t] - py[i];
		if (dx * dx + dy * dy <= r2) touch_[(size_t)form[i] * F + form[t]] = touch_[(size_t)form[t] * F + form[i]] = 1;
	}
	for (size_t fi = 0; fi < F; ++fi) {
		Formation &f = formations[fi];
		Summary &s = sum[fi];
		s.team = f.team; s.order = f.order; s.recovering = f.ai_recovering;
		s.count = f.roster;
		int ranged_count = 0, supplied = 0;
		double range = 0;
		for (int i : f.members) {
			if (!can_act(i)) continue;
			ExStats st; st.ability = 50.0; st.training = f.training; st.morale = f.morale; st.fatigue = f.fatigue;
			double score = exchange_score(st);
			double h = clampd(hp[i], 0.0, 100.0);
			s.power += h / 100.0 * std::max(0.1, score / 50.0);
			s.hp_sum += h;
			s.ready++;
			int cx = (int)px[i], cy = (int)py[i];
			s.minx = std::min(s.minx, cx); s.miny = std::min(s.miny, cy);
			s.maxx = std::max(s.maxx, cx); s.maxy = std::max(s.maxy, cy);
			if (troop[i] != T_MELEE) {
				++ranged_count;
				double r = ranged_profile(equip[i]).range;
				range = range <= 0 ? r : std::min(range, r);
				if (ammo[i] > 0) ++supplied;
			}
		}
		if (ranged_count * 2 <= s.ready) range = 0; // a ranged captain does not make archers of a melee block
		s.range = range;
		s.ammo_empty = range > 0 && supplied == 0;
		s.ready_fraction = (double)s.ready / std::max(1, s.count);
		s.health = s.hp_sum / (100.0 * std::max(1, s.ready));
		s.fatigue = f.fatigue;
		s.morale = f.morale;
	}
	for (size_t fi = 0; fi < F; ++fi) {
		Formation &f = formations[fi];
		if (!f.ai_enabled || !cfg.ai || f.garrisoned) continue;
		f.ai_order_cd = std::max(0.0, f.ai_order_cd - REVIEW);
		f.ai_chase_cd = std::max(0.0, f.ai_chase_cd - REVIEW);
		const Summary &own = sum[fi];
		if (!command_eligible(f.current_cmd) || own.ready == 0) { f.ai_status = AI_NO_COMMAND; f.ai_target = -1; continue; }
		int nearest = -1;
		double distance = 1e30, support = 0;
		bool contact = false;
		std::vector<int> enemies;
		for (size_t o = 0; o < F; ++o) {
			if (o == fi || sum[o].ready == 0) continue;
			double g = gap(own, sum[o]);
			if (!hostile(sum[o].team, own.team)) { if (g <= THREAT_DISTANCE) support += sum[o].power * 0.5; continue; }
			enemies.push_back((int)o);
			bool touching = touch_[fi * F + o] != 0;
			if ((touching && !contact) || (touching == contact && g < distance)) { distance = g; nearest = (int)o; contact = touching; }
		}
		if (f.routed) { f.ai_recovering = true; f.ai_status = AI_ROUTED; continue; }
		if (f.order == Order::RETURN || f.order == Order::RETREAT) {
			f.ai_status = AI_RETURNING; f.ai_chase_cd = std::max(10.0, f.ai_chase_cd); continue;
		}
		if (nearest < 0) {
			f.ai_target = -1;
			if (f.order != Order::HOLD) issue(f, (int)fi, Order::HOLD, 0, 0, -1);
			if (own.health >= 0.6 && own.fatigue <= 50 && own.morale >= 45 && own.ready_fraction >= 0.6 && !own.ammo_empty)
				f.ai_recovering = false;
			f.ai_status = AI_IDLE;
			continue;
		}
		// nearest able person of the nearest enemy group to our command reference
		const Formation &ef = formations[nearest];
		float rx = f.ref_valid ? f.ref_x : f.cx, ry = f.ref_valid ? f.ref_y : f.cy;
		int tgt = -1;
		float bd = 1e30f;
		bool prev_in_group = false;
		for (int j : ef.members) {
			if (!can_act(j)) continue;
			if (j == f.ai_target) prev_in_group = true;
			float dx = px[j] - rx, dy = py[j] - ry, d2 = dx * dx + dy * dy;
			if (d2 < bd || (d2 == bd && tgt >= 0 && person_id[j] < person_id[tgt])) { bd = d2; tgt = j; }
		}
		if (f.order != Order::MOVE) f.ai_target = tgt;
		double pressure = sum[nearest].power;
		for (int o : enemies)
			if (o != nearest && gap(own, sum[o]) <= std::min(THREAT_DISTANCE, distance + 4.0))
				pressure += sum[o].power * (touch_[fi * F + o] ? 1.0 : 0.5);
		double ratio = (own.power + support) / std::max(0.1, pressure);
		bool weakened = own.health < 0.35 || own.ready_fraction < 0.45 || own.fatigue >= 80.0 || own.morale < 25.0 || own.ammo_empty;
		bool outmatched = ratio < HOLD_RATIO;
		if (weakened || (outmatched && distance <= THREAT_DISTANCE)) {
			if (!f.ai_recovering) f.ai_order_cd = 0;
			f.ai_recovering = true;
		}
		if (f.ai_recovering) {
			bool recovered = ratio >= RESUME_RATIO && own.health >= 0.6 && own.ready_fraction >= 0.6 && own.fatigue <= 50 &&
			                 own.morale >= 45 && !own.ammo_empty;
			if (recovered && distance > 4.0) f.ai_recovering = false;
			else {
				f.ai_target = tgt;
				if (f.order != Order::HOLD) issue(f, (int)fi, Order::HOLD, 0, 0, -1);
				f.ai_status = AI_RECOVER;
				continue;
			}
		}
		if (outmatched) { if (f.order != Order::HOLD) issue(f, (int)fi, Order::HOLD, 0, 0, -1); f.ai_status = AI_OUTMATCHED; continue; }
		if (f.order == Order::PURSUE) { f.ai_target = f.target_person; f.ai_status = AI_PURSUE; continue; }
		float tdx = px[tgt] + 0.f - rx, tdy = py[tgt] - ry;
		if (f.ai_order_cd <= 0 && f.ai_chase_cd <= 0 && (sum[nearest].order == Order::RETREAT || sum[nearest].recovering) &&
		    ratio >= 1.35 && own.fatigue <= 50 && tdx * tdx + tdy * tdy < 20.f * 20.f) {
			issue(f, (int)fi, Order::PURSUE, 0, 0, tgt);
			f.ai_target = tgt; f.ai_chase_cd = 30.0; f.ai_status = AI_PURSUE;
			continue;
		}
		// CAV-4a: a mostly mounted formation charges an enemy formation it is not yet in contact with; the formation layer then
		// cycles FORM / CHARGE / RALLY by itself while the order lasts. In contact the usual engagement below applies.
		if (cavalry_formation((int)fi) && charge_commander_ok((int)fi)) {
			if (f.order == Order::RALLY) { f.ai_status = AI_CHARGE; continue; } // a host rally runs to its end first
			if (f.order == Order::CHARGE) { if (f.charge_stage != CS_NONE) f.charge_target_form = nearest; f.ai_target = tgt; f.ai_status = AI_CHARGE; continue; }
			if (!contact && distance <= cav::CHARGE_RANGE && f.ai_order_cd <= 0) {
				if (order_charge((int)fi, 0.f, 0.f, nearest)) { f.ai_order_cd = ORDER_DELAY; stats.ai_orders++; f.ai_target = tgt; f.ai_status = AI_CHARGE; continue; }
				f.ai_order_cd = FAILED_RETRY;
			}
		}
		if (contact || (own.range > 0 && distance <= own.range - 1.0)) {
			if (f.order != Order::ATTACK) issue(f, (int)fi, Order::ATTACK, 0, 0, tgt);
			else if (f.target_person < 0 || !can_act(f.target_person)) f.target_person = tgt;
			f.ai_target = tgt; f.ai_status = AI_ENGAGE;
			continue;
		}
		if (f.order == Order::MOVE && !f.arrived) {
			float gx = f.goal_x - px[tgt], gy = f.goal_y - py[tgt];
			if ((prev_in_group && gx * gx + gy * gy <= 64.f) || f.ai_order_cd > 0) { f.ai_status = AI_APPROACH; continue; }
		}
		if (f.ai_order_cd > 0) continue;
		// _try_approach: MOVE next to the target, trying radius 1..3 on the side facing us, at most 4 attempts
		int tcx = (int)px[tgt], tcy = (int)py[tgt];
		int towx = (int)std::floor(rx) - tcx, towy = (int)std::floor(ry) - tcy;
		std::vector<std::pair<int, int>> dirs{{1, 0}, {0, 1}, {-1, 0}, {0, -1}};
		std::stable_sort(dirs.begin(), dirs.end(), [&](const std::pair<int, int> &a, const std::pair<int, int> &b) {
			return a.first * towx + a.second * towy > b.first * towx + b.second * towy;
		});
		int attempts = 0;
		bool issued = false;
		for (int radius = 1; radius < 4 && !issued && attempts < 4; ++radius)
			for (auto &d : dirs) {
				int cx = tcx + d.first * radius, cy = tcy + d.second * radius;
				if (!terrain.contains(cx, cy) || !terrain.walkable(cx, cy)) continue;
				++attempts;
				issue(f, (int)fi, Order::MOVE, (float)cx + 0.5f, (float)cy + 0.5f, -1);
				if (f.order == Order::MOVE) { issued = true; break; }
				if (attempts >= 4) break;
			}
		if (issued) { f.ai_target = tgt; f.ai_status = AI_APPROACH; }
		else { f.ai_order_cd = FAILED_RETRY; f.ai_status = AI_WAIT_PATH; }
	}
}

void World::refresh_attackers() {
	if (attackers_tick_ == tick) return;
	attackers_tick_ = tick;
	std::fill(attackers_.begin(), attackers_.end(), 0);
	const int n = soldier_count();
	const float r2 = cfg.reach * cfg.reach * 1.44f;
	for (int i = 0; i < n; ++i) {
		if (!can_act(i)) continue;
		int e = enc_target[i];
		if (e >= 0) { attackers_[e]++; continue; }
		int t = target[i];
		if (t < 0) continue;
		float dx = px[t] - px[i], dy = py[t] - py[i];
		if (dx * dx + dy * dy <= r2) attackers_[t]++;
	}
}

void World::encircle_review(Formation &f, int fi) {
	(void)fi;
	bool active = (f.order == Order::ATTACK || f.order == Order::PURSUE) && f.attacking && f.current_cmd >= 0 && !f.needs_attack_order &&
	              !f.routed && f.contact_age < 1.0;
	const float lim = cfg.encircle_cells + 2.f;
	for (int i : f.members) {
		int e = enc_target[i];
		if (e < 0) continue;
		float dx = px[e] - px[i], dy = py[e] - py[i];
		if (!active || !can_act(e) || dx * dx + dy * dy > lim * lim) enc_target[i] = -1;
	}
	if (!active || f.troop != T_MELEE) return;
	refresh_attackers();
	int budget = cfg.encircle_budget;
	const float r2 = cfg.reach * cfg.reach;
	const int ri = (int)std::ceil(cfg.encircle_cells);
	const float R2 = cfg.encircle_cells * cfg.encircle_cells;
	for (int i : f.members) {
		if (budget == 0) break;
		if (troop[i] != T_MELEE || !can_act(i) || is_crewed(i) || escort_mode[i] >= 3 || enc_target[i] >= 0 || stagger[i] > 0 || rescue_of[i] >= 0 || capture_of[i] >= 0) continue;
		int t = target[i];
		if (t >= 0) {
			float dx = px[t] - px[i], dy = py[t] - py[i];
			if (dx * dx + dy * dy <= r2) continue; // already in contact: front rank holds (D73)
		}
		int best = -1;
		if (t >= 0 && can_act(t) && attackers_[t] < 3) best = t;
		else {
			float bd = R2 + 1;
			int x = (int)px[i], y = (int)py[i];
			for (int yy = std::max(0, y - ri); yy <= std::min(terrain.h - 1, y + ri); ++yy)
				for (int xx = std::max(0, x - ri); xx <= std::min(terrain.w - 1, x + ri); ++xx) {
					int c = terrain.idx(xx, yy);
					for (int k = hash_start_[c]; k < hash_start_[c + 1]; ++k) {
						int j = hash_items_[k];
						if (!hostile(team[i], team[j]) || !can_act(j) || attackers_[j] >= 3) continue;
						float dx = px[j] - px[i], dy = py[j] - py[i], d2 = dx * dx + dy * dy;
						if (d2 > R2) continue;
						if (d2 < bd || (d2 == bd && best >= 0 && person_id[j] < person_id[best])) { bd = d2; best = j; }
					}
				}
		}
		if (best < 0) continue;
		enc_target[i] = best;
		attackers_[best]++;
		--budget;
		stats.encircle_assigned++;
	}
}

} // namespace wg
