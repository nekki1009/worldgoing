// Exchange-mode combat: readiness, adjacent exchange rounds, ranged fire / flight / arrival,
// stun / KO / wake / get-up, rescue (D72), capture / escort / escape (institutions sec.6).
#include "crowd_core.hpp"

#include <algorithm>
#include <cstdio>

namespace wg {

using namespace rules;

// ---------------------------------------------------------------- readiness (TerrainArmy.exchange_ready / exchange_initiates)
bool World::exchange_ready(int i) const {
	if (!can_act(i) || is_siege_crew(i) || escort_mode[i] >= 3 || stagger[i] > 0.0 || exch_cd[i] > 0.0 || rescue_of[i] >= 0 || capture_of[i] >= 0 || knock_t[i] > 0.0)
		return false;
	const Formation &f = formations[form[i]];
	return !(f.routed && f.order != Order::HOLD);
}

bool World::initiates(int i, bool melee) const {
	if (formations[form[i]].garrisoned || is_siege_crew(i) || escort_mode[i] >= 3) return false;
	if (host_ctl[i]) return host_engage[i] != 0; // the player's own wish to fight
	const Formation &f = formations[form[i]];
	if (f.routed) return false;
	switch (f.order) {
	case Order::MOVE: return melee; // move encounter: the pair itself requires adjacency
	case Order::HOLD: return melee && f.needs_attack_order && rescue_of[i] < 0 && capture_of[i] < 0; // D50 self-defence
	case Order::ATTACK:
	case Order::PURSUE: return f.attacking && f.current_cmd >= 0 && !f.needs_attack_order;
	default: return false;
	}
}

ExStats World::ex_stats(int i) const {
	const Formation &f = formations[form[i]];
	ExStats s;
	s.ability = TROOP_COMBAT_ABILITY;
	s.training = f.training;
	s.fatigue = f.fatigue;
	s.morale = f.morale;
	s.armorbonus = armor_bonus(equip[i]);
	s.facility = (cell[i] >= 0 && terrain.facility[cell[i]]) ? 10.0 : 0.0;
	s.skill = skill[i];
	s.equip = equip[i];
	return s;
}

void World::activate_skill(int i, uint8_t s) {
	if (!can_act(i) || skill_cd[i] > 0.0 || skill[i] != SK_NONE) return;
	skill[i] = s;
}

int World::enemy_sectors(int i) const {
	int mask = 0;
	int cx = (int)px[i], cy = (int)py[i];
	const float r2 = cfg.reach * cfg.reach;
	for (int yy = std::max(0, cy - 2); yy <= std::min(terrain.h - 1, cy + 2); ++yy)
		for (int xx = std::max(0, cx - 2); xx <= std::min(terrain.w - 1, cx + 2); ++xx) {
			int c = terrain.idx(xx, yy);
			for (int k = hash_start_[c]; k < hash_start_[c + 1]; ++k) {
				int j = hash_items_[k];
				if (!hostile(team[i], team[j]) || !can_act(j)) continue;
				float dx = px[j] - px[i], dy = py[j] - py[i];
				if (dx * dx + dy * dy > r2 || !los(px[i], py[i], px[j], py[j])) continue;
				int q = std::fabs(dx) >= std::fabs(dy) ? (dx > 0 ? 1 : 3) : (dy > 0 ? 2 : 0);
				mask |= 1 << q;
			}
		}
	int count = 0;
	for (int q = 0; q < 4; ++q) count += (mask >> q) & 1;
	return count;
}

// ---------------------------------------------------------------- contact result (TerrainArmy.apply_unit_contact)
void World::cancel_actions_involving(int i) {
	auto cancel_rescue = [&](int r) {
		int p = rescue_of[r];
		if (p < 0) return;
		rescue_of[r] = -1; act_t[r] = 0;
		if (rescued_by_[p] == r) rescued_by_[p] = -1;
		stats.rescues_cancelled++;
	};
	auto cancel_capture = [&](int g) {
		int t = capture_of[g];
		if (t < 0) return;
		capture_of[g] = -1; act_t[g] = 0;
		if (capturing_by_[t] == g) capturing_by_[t] = -1;
		stats.captures_cancelled++;
	};
	cancel_rescue(i);
	if (rescued_by_[i] >= 0) cancel_rescue(rescued_by_[i]);
	cancel_capture(i);
	if (capturing_by_[i] >= 0) cancel_capture(capturing_by_[i]);
}

void World::apply_contact(int i, double hp_loss, double stun_add, bool environmental) {
	if (hp[i] <= 0.0) return;
	Formation &f = formations[form[i]];
	bool effective = !environmental && (hp_loss > 0.0 || stun_add > 0.0);
	if (effective) {
		contact_revision[i] = contact_revision[i] == INT64_MAX ? 0 : contact_revision[i] + 1;
		// An impact interrupts custody work without altering the original position.
		if (controlled_step_pending(i)) { if (escort_mode[i] & 1u) ++escort_mode[i]; }
		else { escort_mode[i] = 0; escort_goal[i] = -1; }
	}
	if (effective || hp_loss >= hp[i]) cancel_actions_involving(i);
	hp[i] = std::max(0.0, hp[i] - hp_loss);
	if (!environmental && hp_loss > 0.0 && ko[i] > 0.0) bandaged[i] = 0; // a new wound reopens bleeding
	f.command_dirty = true;
	if (stun_add > 0.0) {
		stun[i] += stun_add;
		grace[i] = STUN_GRACE;
		if (ko[i] > 0.0) ko[i] = cfg.ko_seconds; // D72: a new effective impact only resets the wait
	}
	if (effective && !quiet_contact_) mark_combat(cfg.combat_grace); // bleeding out is not a combat event
	if (hp[i] <= 0.0 || (ko[i] <= 0.0 && stun[i] >= STUN_LIMIT)) {
		// a knockback committed this round still carries the falling body one cell (terrain_army keeps the move)
		stagger[i] = 0; enc_target[i] = -1; getup[i] = 0;
		if (hp[i] <= 0.0) {
			knock_t[i] = 0;
			ko[i] = 0.0;
			stats.deaths++;
			f.fatigue_count = std::max(0, f.fatigue_count - 1);
			push_event(EV_DEATH, i, captive[i] ? captor[i] : -1);
			set_visual(i, V_DOWN);
			if (captive[i]) { captive[i] = 0; captor[i] = -1; }
			prison_id[i] = 0;
			if (!controlled_step_pending(i)) { escort_goal[i] = -1; escort_mode[i] = 0; }
		} else {
			ko[i] = cfg.ko_seconds;
			bandaged[i] = 0;
			stats.kos++;
			push_event(EV_KO, i, -1);
			set_visual(i, V_DOWN);
		}
	}
}

void World::push_event(EventKind k, int soldier, int other_soldier) {
	Event e;
	e.kind = (uint8_t)k;
	e.soldier = soldier;
	e.formation = soldier >= 0 ? form[soldier] : -1;
	e.person = soldier >= 0 ? person_id[soldier] : -1;
	e.other = other_soldier >= 0 ? person_id[other_soldier] : -1;
	e.time = time;
	if (k == EV_DEATH) {
		const Formation &f = formations[e.formation];
		e.fatigue = f.fatigue;
		e.fatigue_rest = f.fatigue_rest;
	}
	events.push_back(e);
	if (k==EV_DEATH && work_point_active_) {
		const auto &p=work_point_pools_[e.formation];
		work_point_deaths_.push_back({events.size()-1,e.formation,e.person,p.native_charge,e.fatigue,e.fatigue_rest,e.fatigue,e.fatigue_rest});
	}
}


bool World::apply_siege_contact(int i, double hp_loss, double stun_add, double stagger_seconds) {
	if (i < 0 || i >= soldier_count() || !std::isfinite(hp_loss) || !std::isfinite(stun_add) || !std::isfinite(stagger_seconds)
	    || hp_loss < 0 || stun_add < 0 || stagger_seconds < 0) return false;
	if (!alive(i)) return true;
	apply_contact(i, hp_loss, stun_add); // Original revision, interruptions, KO/death and combat marks.
	if (hp[i] > 0.0 && ko[i] <= 0.0 && getup[i] <= 0.0 && hp_loss > 0.0) {
		set_visual(i, V_HIT);
		if (rescue_of[i] >= 0) cancel_actions_involving(i);
		stagger[i] = std::max(stagger[i], stagger_seconds);
	}
	return true; // Siege preserves the original brace skill; it provides no siege reduction.
}

bool World::apply_environment_damage(int i, double amount) {
	if (i < 0 || i >= soldier_count() || !std::isfinite(amount) || amount < 0) return false;
	if (!alive(i) || amount == 0) return true;
	if (amount < hp[i]) { hp[i] -= amount; return true; }
	const bool quiet = quiet_contact_; quiet_contact_ = true;
	apply_contact(i, amount, 0); quiet_contact_ = quiet;
	life_ck[i] = 2; // Hunger is not a combat casualty; do not suppress anybody else's checkpoint.
	return true;
}

// ---------------------------------------------------------------- timers (parallel, self only)
void World::timers_stage(float dt, double gdt, int ch) {
	const int n = soldier_count();
	const int a = ch * cfg.chunk, b = std::min(n, a + cfg.chunk);
	auto &woke = wake_buf_[ch];
	auto &rose = getup_buf_[ch];
	woke.clear(); rose.clear();
	for (int i = a; i < b; ++i) {
		stagger[i] = std::max(0.0, stagger[i] - dt);
		exch_cd[i] = exch_cd[i] - dt <= 0.000000001 ? 0.0 : exch_cd[i] - dt;
		ranged_cd[i] = std::max(0.0, ranged_cd[i] - dt);
		skill_cd[i] = std::max(0.0, skill_cd[i] - dt);
		knock_t[i] = std::max(0.0, knock_t[i] - dt);
		if (hp[i] <= 0.0) continue;
		if (ko[i] > 0.0) {
			ko[i] -= gdt; // KO wait is game time (prepare_combat: ko -= game_seconds)
			if (ko[i] <= 0.0) { // D72 natural wake: stun 30, restart the decay wait, 2.2 s get-up; HP unchanged
				ko[i] = 0.0; stun[i] = WAKE_STUN; grace[i] = STUN_GRACE; getup[i] = GETUP_SECONDS; bandaged[i] = 0;
				woke.push_back(i);
			}
			continue;
		}
		if (getup[i] > 0.0) { getup[i] = std::max(0.0, getup[i] - dt); if (getup[i] <= 0.0) rose.push_back(i); }
		if (rescue_of[i] >= 0) continue; // a rescuing row skips stun decay (prepare_combat `continue`)
		double decay = std::max(0.0, (double)dt - grace[i]);
		grace[i] = std::max(0.0, grace[i] - dt);
		stun[i] = std::max(0.0, stun[i] - decay * STUN_RECOVERY);
	}
}

// ---------------------------------------------------------------- exchange round (terrain_lab._resolve_exchanges)
void World::exchange_collect(int ch) {
	const int n = soldier_count();
	const int a = ch * cfg.chunk, b = std::min(n, a + cfg.chunk);
	auto &out = pair_buf_[ch];
	out.clear();
	const float r2 = cfg.reach * cfg.reach;
	for (int i = a; i < b; ++i) {
		if (!can_receive(i)) continue;
		const uint16_t *eb = enemy_blocks(team[i]);
		int x = (int)px[i], y = (int)py[i];
		if (!eb[(y >> 3) * bw_ + (x >> 3)]) {
			bool any = false; // neighbour blocks
			int bx = x >> 3, by = y >> 3;
			for (int yy = std::max(0, by - 1); yy <= std::min(bh_ - 1, by + 1) && !any; ++yy)
				for (int xx = std::max(0, bx - 1); xx <= std::min(bw_ - 1, bx + 1); ++xx)
					if (eb[yy * bw_ + xx]) { any = true; break; }
			if (!any) continue;
		}
		bool ri = exchange_ready(i) && initiates(i, true);
		for (int yy = std::max(0, y - 2); yy <= std::min(terrain.h - 1, y + 2); ++yy)
			for (int xx = std::max(0, x - 2); xx <= std::min(terrain.w - 1, x + 2); ++xx) {
				int c = terrain.idx(xx, yy);
				for (int k = hash_start_[c]; k < hash_start_[c + 1]; ++k) {
					int j = hash_items_[k];
					if (j <= i || !hostile(team[i], team[j]) || !can_receive(j)) continue; // each unordered pair once (lower index)
					float dx = px[j] - px[i], dy = py[j] - py[i];
					if (dx * dx + dy * dy > r2) continue;
					if (!ri && !(exchange_ready(j) && initiates(j, true))) continue; // peaceful neighbours do not duel
					if (!los(px[i], py[i], px[j], py[j])) continue;                   // can_attack_across
					ExStats sa = ex_stats(i), sb = ex_stats(j);
					double roll = exchange_roll(person_id[i], person_id[j], exchange_round, cfg.seed);
					out.push_back({i, j, exchange_result(sa, sb, roll)});
				}
			}
	}
}

void World::exchange_round_run() {
	++exchange_round;
	stats.rounds++;
	// Automatic skills for command-ability holders in a viable pair (TerrainLab._exchange_context).
	const float r2 = cfg.reach * cfg.reach;
	for (auto &f : formations)
		for (int i : f.members) {
			if (!ability[i].has() || !can_receive(i) || skill[i] != SK_NONE || skill_cd[i] > 0) continue;
			bool viable = false;
			int cx = (int)px[i], cy = (int)py[i];
			for (int yy = std::max(0, cy - 2); yy <= std::min(terrain.h - 1, cy + 2) && !viable; ++yy)
				for (int xx = std::max(0, cx - 2); xx <= std::min(terrain.w - 1, cx + 2) && !viable; ++xx) {
					int c = terrain.idx(xx, yy);
					for (int k = hash_start_[c]; k < hash_start_[c + 1]; ++k) {
						int j = hash_items_[k];
						if (!hostile(team[i], team[j]) || !can_receive(j)) continue;
						float dx = px[j] - px[i], dy = py[j] - py[i];
						if (dx * dx + dy * dy > r2 || !los(px[i], py[i], px[j], py[j])) continue;
						if ((exchange_ready(i) && initiates(i, true)) || (exchange_ready(j) && initiates(j, true))) { viable = true; break; }
					}
				}
			if (viable) activate_skill(i, enemy_sectors(i) >= 2 ? SK_BRACE : SK_POWER);
		}
	pool_.run(chunks_, [&](int ch) { exchange_collect(ch); });
	// Merge: every edge used pre-resolution stats; each person pays / receives one merged outcome.
	ex_participants_.clear();
	auto side = [&](int i, int other, double hp_v, double stun_v, double fat, double stag, bool knock, int rank, double margin) {
		ExAcc &e = ex_acc_[i];
		if (!e.in) { e = ExAcc{}; e.in = true; ex_participants_.push_back(i); }
		e.hp += hp_v; e.stun += stun_v; e.fat += fat; e.stag = std::max(e.stag, stag);
		e.knock = e.knock || knock;
		e.count++; if (rank == 2) { e.losses++; if (knock || margin >= EXCHANGE_BIG_MARGIN) e.big_losses++; } else if (rank == 1) e.draws++; else if (margin >= EXCHANGE_BIG_MARGIN) e.big_wins++;
		bool better = e.r_other < 0;
		if (!better) {
			if (knock != e.r_knock) better = knock;
			else if (rank != e.r_rank) better = rank > e.r_rank;
			else if (hp_v != e.r_hp) better = hp_v > e.r_hp;
			else if (margin != e.r_margin) better = margin > e.r_margin;
			else better = person_id[other] < person_id[e.r_other];
		}
		if (better) { e.r_other = other; e.r_knock = knock; e.r_rank = rank; e.r_hp = hp_v; e.r_margin = margin; }
	};
	for (int ch = 0; ch < chunks_; ++ch)
		for (auto &p : pair_buf_[ch]) {
			const ExResult &r = p.r;
			stats.pairs++;
			if (r.kind == EX_DRAW) stats.draws++; else if (r.kind == EX_SMALL) stats.small++; else stats.big++;
			double stag_a = r.winner == -1 ? r.stagger : (r.winner == 0 ? r.hold : 0.0);
			double stag_b = r.winner == 1 ? r.stagger : (r.winner == 0 ? r.hold : 0.0);
			int rank_a = r.winner == 0 ? 1 : (r.winner == -1 ? 2 : 0), rank_b = r.winner == 0 ? 1 : (r.winner == 1 ? 2 : 0);
			double m = std::fabs(r.margin);
			side(p.a, p.b, r.hp_a, r.stun_a, r.fatigue_a, stag_a, r.winner == -1 && r.knockback, rank_a, m);
			side(p.b, p.a, r.hp_b, r.stun_b, r.fatigue_b, stag_b, r.winner == 1 && r.knockback, rank_b, m);
			formations[form[p.a]].contact_age = 0;
			formations[form[p.b]].contact_age = 0;
		}
	std::sort(ex_participants_.begin(), ex_participants_.end());
	if (!ex_participants_.empty()) mark_combat(cfg.combat_grace); // exchange_batch_prepare: combat_event(10)
	// Phase "prepare": costs and skills for every participant on the pre-death roster (fatigue divisor),
	// cooldowns, rescue cancel. Phase "knockback" for every participant. Phase "contact" (HP / stun /
	// death / KO) for every participant. (terrain_lab._resolve_exchanges batch phases)
	for (int i : ex_participants_) {
		ExAcc &e = ex_acc_[i];
		if (e.fat > 0) charge(i, e.fat);
		if (exch_cd[i] > 0.000000001) stats.cooldown_violations++;
		exch_cd[i] = EXCHANGE_ROUND_SECONDS;
		if (skill[i] != SK_NONE) { skill_cd[i] = EXCHANGE_SKILL_COOLDOWN; skill[i] = SK_NONE; stats.skills_used++; }
		if (rescue_of[i] >= 0) cancel_actions_involving(i); // a draw / win also stops helping
	}
	for (int i : ex_participants_) {
		ExAcc &e = ex_acc_[i];
		int o = e.r_other;
		if (o >= 0) face[i] = std::atan2(py[o] - py[i], px[o] - px[i]);
		double prev = stagger[i]; // previous stagger survives a knockback (max(previous, new))
		if (e.knock && o >= 0) {  // big loss: pushed one cell away from the reaction opponent
			float dx = px[i] - px[o], dy = py[i] - py[o], d = std::sqrt(dx * dx + dy * dy);
			if (d < 1e-4f) { dx = -std::cos(face[i]); dy = -std::sin(face[i]); d = 1; }
			knock_dx[i] = dx / d * 4.0f; knock_dy[i] = dy / d * 4.0f; knock_t[i] = 0.25;
			stats.knockbacks++;
		}
		if (e.stag > 0) stagger[i] = std::max(prev, e.stag);
	}
	for (int i : ex_participants_) {
		ExAcc &e = ex_acc_[i];
		// presentation (terrain_lab batch outcome): all won -> attack (big -> jump heavy); a single draw -> guard;
		// otherwise loser -> hit (big loss -> knockback)
		const bool all_won = e.losses == 0 && e.draws == 0;
		if (all_won) set_visual(i, e.big_wins > 0 ? V_ATTACK_HEAVY : V_ATTACK);
		else if (e.count == 1 && e.draws == 1) set_visual(i, V_GUARD);
		else set_visual(i, e.big_losses > 0 || e.knock ? V_KNOCKBACK : V_HIT);
		apply_contact(i, e.hp, e.stun);
		e.in = false;
	}
}

// ---------------------------------------------------------------- ranged (terrain_lab._resolve_ranged_fire / arrival)
bool World::begin_structure_strike(int i, int target_cell) {
	if (i < 0 || i >= soldier_count() || target_cell < 0 || target_cell >= terrain.w * terrain.h || !exchange_ready(i) || escort_mode[i] != 0 || equip[i].family == F_NONE || equip[i].family == F_BOW || equip[i].family == F_CROSSBOW) return false;
	const int dx = target_cell % terrain.w - int(px[i]), dy = target_cell / terrain.w - int(py[i]);
	if (std::abs(dx) + std::abs(dy) != 1 || vx[i] * vx[i] + vy[i] * vy[i] > 1e-6f) return false;
	face[i] = std::atan2(float(dy), float(dx));
	exch_cd[i] = EXCHANGE_ROUND_SECONDS;
	stagger[i] = std::max(stagger[i], EXCHANGE_ROUND_SECONDS);
	charge(i, EXCHANGE_FATIGUE);
	set_visual(i, V_ATTACK);
	mark_combat(10.);
	return true;
}

bool World::ranged_line_clear(Cell s, Cell g, std::vector<Cell> &cells) const {
	if (!terrain.walkable(s.x, s.y) || !terrain.contains(g.x, g.y)) return false;
	ranged_cells(s, g, cells);
	if (cells.empty()) return false;
	for (const auto &c : cells) {
		if (!terrain.contains(c.x, c.y) || !terrain.shot_cell_clear(terrain.idx(s.x, s.y), terrain.idx(g.x, g.y), terrain.idx(c.x, c.y))) return false;
	}
	return true;
}

bool World::friendly_clear(Cell s, Cell g, int faction, std::vector<Cell> &cells) const {
	ranged_cells(s, g, cells);
	for (auto &c : cells) {
		if (!terrain.contains(c.x, c.y)) continue;
		int ci = terrain.idx(c.x, c.y);
		double z = terrain.shot_height(terrain.idx(s.x, s.y), terrain.idx(g.x, g.y), ci);
		if (z < terrain.height[ci] || z > terrain.height[ci] + 1.5) continue;
		for (int k = hash_start_[ci]; k < hash_start_[ci + 1]; ++k)
			if (hp[hash_items_[k]] > 0.0 && !hostile(faction, team[hash_items_[k]])) return false; // living or unconscious friend / ally (not those just killed)
	}
	return true;
}

void World::ranged_decide(int ch) {
	const int n = soldier_count();
	const int a = ch * cfg.chunk, b = std::min(n, a + cfg.chunk);
	auto &out = fire_buf_[ch];
	out.clear();
	std::vector<Cell> tmp;
	tmp.reserve(32);
	for (int i = a; i < b; ++i) {
		if (troop[i] == T_MELEE || ammo[i] == 0 || ranged_cd[i] > 0.0 || !exchange_ready(i)) continue;
		if (!initiates(i, false)) continue;
		RangedProfile prof = ranged_profile(equip[i]);
		if (!prof.valid) continue;
		const uint16_t *eb = enemy_blocks(team[i]);
		Cell sc{(int)px[i], (int)py[i]};
		int bx = sc.x >> 3, by = sc.y >> 3, br = (int)std::ceil(prof.range / 8.0) + 1;
		bool any = false;
		for (int yy = std::max(0, by - br); yy <= std::min(bh_ - 1, by + br) && !any; ++yy)
			for (int xx = std::max(0, bx - br); xx <= std::min(bw_ - 1, bx + br); ++xx)
				if (eb[yy * bw_ + xx]) { any = true; break; }
		if (!any) { fire_blocked[i] = 0; continue; }
		int ri = (int)std::ceil(prof.range);
		double r2 = prof.range * prof.range;
		int best = -1;
		double nearest = 1e30;
		bool close_threat = false, friend_blocked = false;
		for (int yy = std::max(0, sc.y - ri); yy <= std::min(terrain.h - 1, sc.y + ri) && !close_threat; ++yy)
			for (int xx = std::max(0, sc.x - ri); xx <= std::min(terrain.w - 1, sc.x + ri) && !close_threat; ++xx) {
				int c = terrain.idx(xx, yy);
				for (int k = hash_start_[c]; k < hash_start_[c + 1]; ++k) {
					int j = hash_items_[k];
					if (!hostile(team[i], team[j]) || !can_act(j)) continue;
					int ox = xx - sc.x, oy = yy - sc.y;
					double d2 = (double)(ox * ox + oy * oy);
					if (d2 > std::max(1.0, r2)) continue;
					float fx = px[j] - px[i], fy = py[j] - py[i];
					bool cell_adjacent = std::abs(ox) + std::abs(oy) <= 1 && (d2 == 0 || terrain.attack_across(sc.x, sc.y, xx, yy));
					if (cell_adjacent || (fx * fx + fy * fy <= cfg.reach * cfg.reach && los(px[i], py[i], px[j], py[j]))) {
						close_threat = true; // a nearby opponent forces close combat
						break;
					}
					if (d2 <= 1.0 || d2 > nearest || (d2 == nearest && best >= 0 && person_id[j] > person_id[best])) continue;
					if (!friendly_clear(sc, {xx, yy}, team[i], tmp)) { friend_blocked = true; continue; }
					if (ranged_line_clear(sc, {xx, yy}, tmp)) { best = j; nearest = d2; }
				}
			}
		fire_blocked[i] = (uint8_t)(!close_threat && best < 0 && friend_blocked); // own-index write only
		if (!close_threat && best >= 0) out.push_back({i, best});
	}
}

void World::ranged_commit() {
	if (host_ranged_delegate) return;
	for (int ch = 0; ch < chunks_; ++ch)
		for (auto &req : fire_buf_[ch]) {
			int i = req.shooter, j = req.target;
			if (!exchange_ready(i) || ammo[i] == 0 || ranged_cd[i] > 0.0) continue;
			if (ability[i].has()) activate_skill(i, SK_POWER);
			const Formation &f = formations[form[i]];
			RangedProfile prof = ranged_profile(equip[i]);
			Projectile p;
			p.shooter = i; p.faction = team[i]; p.shooter_id = person_id[i];
			p.source = {(int)px[i], (int)py[i]};
			p.target = {(int)px[j], (int)py[j]};
			p.source_eye = terrain.height[terrain.idx(p.source.x, p.source.y)] + 1.;
			p.goal_eye = terrain.height[terrain.idx(p.target.x, p.target.y)] + 1.;
			p.stats.ability = TROOP_COMBAT_ABILITY; p.stats.training = f.training; p.stats.fatigue = f.fatigue;
			p.stats.skill = skill[i]; p.stats.equip = equip[i];
			int ox = p.target.x - p.source.x, oy = p.target.y - p.source.y;
			double dist = std::sqrt((double)(ox * ox + oy * oy));
			p.left = dist / prof.speed;
			p.shot_id = ++shot_serial;
			ammo[i]--;                        // deducted at release, never refunded
			charge(i, 1.0);                   // shot fatigue +1 (shared pool)
			if (skill[i] == SK_POWER) { skill[i] = SK_NONE; skill_cd[i] = EXCHANGE_SKILL_COOLDOWN; stats.skills_used++; }
			face[i] = std::atan2((float)oy, (float)ox);
			stagger[i] = std::max(stagger[i], prof.hold);
			ranged_cd[i] = prof.cooldown;
			projectiles.push_back(p);
			stats.shots++;
			mark_combat(cfg.shot_grace); // ranged_fire: combat_event(12)
			push_event(EV_SHOT, i, -1);
			set_visual(i, V_SHOOT);
		}
}

void World::projectiles_advance(float dt) {
	if (host_ranged_delegate) return;
	bool any_due = false;
	for (auto &p : projectiles) { p.left = std::max(0.0, p.left - dt); if (p.left <= 1e-9) any_due = true; }
	if (!any_due) return;
	// one occupancy snapshot for every arrival of this step: the hash built after this step's movement
	std::vector<Cell> cells;
	size_t w = 0;
	for (size_t k = 0; k < projectiles.size(); ++k) {
		Projectile &p = projectiles[k];
		if (p.left > 1e-9) { projectiles[w++] = p; continue; }
		ranged_cells(p.source, p.target, cells);
		bool blocked = false;
		int tgt = -1;
		const int source = terrain.idx(p.source.x, p.source.y), goal = terrain.idx(p.target.x, p.target.y);
		for (const auto &c : cells) {
			if (!terrain.contains(c.x, c.y)) { blocked = true; break; }
			int ci = terrain.idx(c.x, c.y);
			if (!terrain.shot_cell_clear(source, goal, ci, p.source_eye, p.goal_eye)) { blocked = true; break; }
			double z = terrain.shot_height(source, goal, ci, p.source_eye, p.goal_eye);
			if (z < terrain.height[ci] || z > terrain.height[ci] + 1.5) continue;
			for (int q = hash_start_[ci]; q < hash_start_[ci + 1]; ++q) {
				int j = hash_items_[q];
				if (person_id[j] != p.shooter_id) { tgt = j; break; }
			}
			if (tgt >= 0) break;
		}
		if (tgt < 0) { if (blocked) stats.blocked++; else stats.empty++; continue; }
		RangedDefense d;
		d.moving = vx[tgt] * vx[tgt] + vy[tgt] * vy[tgt] > 0.25f;
		d.shield = equip[tgt].shield;
		d.armor_stab = armor_profile(equip[tgt]).stab;
		d.facility = terrain.facility[terrain.idx((int)px[tgt], (int)py[tgt])] != 0;
		d.skill = skill[tgt];
		d.equip = equip[tgt];
		int ox = p.target.x - p.source.x, oy = p.target.y - p.source.y;
		double roll = ranged_roll(p.shooter_id, p.shot_id, person_id[tgt], cfg.seed);
		RangedResult r = ranged_result(p.stats, d, std::sqrt((double)(ox * ox + oy * oy)), roll);
		if (skill[tgt] == SK_BRACE) { skill[tgt] = SK_NONE; skill_cd[tgt] = EXCHANGE_SKILL_COOLDOWN; stats.skills_used++; }
		if (r.kind == R_HIT) stats.hits++; else if (r.kind == R_GRAZE) stats.grazes++; else stats.misses++;
		if (r.kind != R_MISS && !hostile(p.faction, team[tgt])) stats.friendly_hits++;
		apply_contact(tgt, r.hp, r.stun);
		if (hp[tgt] > 0.0 && ko[tgt] <= 0.0 && getup[tgt] <= 0.0 && r.hp > 0.0) {
			set_visual(tgt, V_HIT);
			if (rescue_of[tgt] >= 0) cancel_actions_involving(tgt);
			stagger[tgt] = std::max(stagger[tgt], r.stagger);
		}
	}
	projectiles.resize(w);
}

// ---------------------------------------------------------------- actions: rescue / capture / escape (serial)
bool World::order_capture(int g, int t) {
	if (g < 0 || t < 0 || g >= soldier_count() || t >= soldier_count() || !can_act(g) || (escort_mode[g] != 0 || is_siege_crew(g)) || hp[t] <= 0.0 || ko[t] <= 0.0 || captive[t] || !hostile(team[g], team[t])) return false;
	if (capture_of[g] >= 0 || rescue_of[g] >= 0 || capturing_by_[t] >= 0) return false;
	float dx = px[t] - px[g], dy = py[t] - py[g];
	if (dx * dx + dy * dy > 1.3f * 1.3f) return false;
	int held = 0;
	for (int c : captives_) if (captive[c] && prison_id[c] == 0 && captor[c] == g) ++held;
	if (held >= GUARD_CAPACITY) return false;
	capture_of[g] = t; act_t[g] = 0; capturing_by_[t] = g;
	capturers_.push_back(g);
	stats.captures_started++;
	return true;
}

// SiteCaptiveEscort supplies one edge of its original order. Native keeps the
// position, collision resolution and committed movement; no host teleport.
bool World::order_escort_step(int i, int g, int destination) {
	const int n = soldier_count(), cells = terrain.w * terrain.h;
	if (i < 0 || i >= n || g < 0 || g >= n || destination < 0 || destination >= cells || !can_act(g)) return false;
	if (escort_mode[i] >= 3 || escort_mode[g] >= 3 || is_siege_crew(i) || is_siege_crew(g) || siege_group(i) >= 0 || siege_group(g) >= 0) return false;
	if (hp[i] <= 0 || ko[i] > 0 || getup[i] > 0 || stagger[i] > 0 || prison_id[i] != 0) return false;
	if ((captive[i] && captor[i] != g) || (!captive[i] && i != g) || rescue_of[i] >= 0 || capture_of[i] >= 0) return false;
	if (escort_goal[i] >= 0) return escort_mode[i] == 1 && escort_goal[i] == destination;
	const int x = int(std::floor(px[i])), y = int(std::floor(py[i]));
	const int gx = destination % terrain.w, gy = destination / terrain.w;
	const int dx = gx - x, dy = gy - y;
	if (!terrain.walkable(gx, gy) || !siege_person_cell(i,terrain.idx(x,y),destination) || std::abs(dx) + std::abs(dy) > 1) return false;
	if ((dx || dy) && !terrain.edge(x, y, dx > 0 ? E : dx < 0 ? W : dy > 0 ? S : N)) return false;
	if (captive[i]) {
		const float rx = float(gx) + .5f - px[g], ry = float(gy) + .5f - py[g];
		if (rx * rx + ry * ry > 16.f) return false;
	}
	for (int j = 0; j < n; ++j) {
		if (j == i || hp[j] <= 0) continue;
		if ((int(std::floor(px[j])) == gx && int(std::floor(py[j])) == gy) || (escort_mode[j] && escort_goal[j] == destination)) return false;
	}
	escort_goal[i] = (dx == 0 && dy == 0 && vx[i] * vx[i] + vy[i] * vy[i] <= 1e-6f
		&& std::abs(px[i] - (float(gx) + .5f)) <= 1e-5f && std::abs(py[i] - (float(gy) + .5f)) <= 1e-5f) ? -1 : destination;
	escort_mode[i] = 1;
	return true;
}

void World::cancel_escort(int i) {
	if (i < 0 || i >= soldier_count()) return;
	if (escort_mode[i] >= 3 || is_siege_crew(i) || siege_group(i) >= 0) return;
	escort_mode[i] = escort_goal[i] >= 0 ? 2 : 0;
}

// One original adjacent commitment for Site person jobs. Housing and siege share
// these existing goal/mode arrays and the ordinary soldier motion phase.
bool World::order_controlled_step(int i, int destination, ControlledStepKind kind) {
	const auto mode = static_cast<uint8_t>(kind);
	const int n = soldier_count(), cells = terrain.w * terrain.h;
	if ((mode != 3 && mode != 5) || i < 0 || i >= n || destination < 0 || destination >= cells || !can_act(i)) return false;
	const Formation &f = formations[form[i]];
	if ((mode == 3 ? f.order != Order::HOLD : f.order == Order::RETREAT) || f.garrisoned || f.routed || prison_id[i] != 0 || stagger[i] > 0 || knock_t[i] > 0 || rescue_of[i] >= 0 || capture_of[i] >= 0) return false;
	if (siege_group(i) >= 0 || siege_claims_cell(destination,i) || (mode == 3 && is_siege_crew(i))) return false;
	if (escort_mode[i] != 0 && escort_mode[i] != mode) return false;
	if (escort_goal[i] >= 0) return escort_mode[i] == mode && escort_goal[i] == destination;
	const int x = int(std::floor(px[i])), y = int(std::floor(py[i]));
	const int gx = destination % terrain.w, gy = destination / terrain.w;
	const int dx = gx - x, dy = gy - y;
	if (!terrain.walkable(gx, gy) || !siege_person_cell(i,terrain.idx(x,y),destination) || std::abs(dx) + std::abs(dy) > 1) return false;
	if ((dx || dy) && !terrain.edge(x, y, dx > 0 ? E : dx < 0 ? W : dy > 0 ? S : N)) return false;
	for (int j = 0; j < n; ++j) {
		if (j == i) continue;
		if ((hp[j] > 0 && int(std::floor(px[j])) == gx && int(std::floor(py[j])) == gy) || (escort_mode[j] && escort_goal[j] == destination)) return false;
	}
	escort_goal[i] = (dx == 0 && dy == 0 && vx[i] * vx[i] + vy[i] * vy[i] <= 1e-6f
		&& std::abs(px[i] - (float(gx) + .5f)) <= 1e-5f && std::abs(py[i] - (float(gy) + .5f)) <= 1e-5f) ? -1 : destination;
	if(mode==5) { if(siege_step_source.size()!=px.size())siege_step_source.assign(px.size(),-1); siege_step_source[i]=escort_goal[i]<0?-1:terrain.idx(x,y); }
	escort_mode[i] = mode;
	return true;
}

void World::cancel_controlled_step(int i, ControlledStepKind kind) {
	const auto mode = static_cast<uint8_t>(kind);
	if ((mode != 3 && mode != 5) || i < 0 || i >= soldier_count() || (escort_mode[i] != mode && escort_mode[i] != mode + 1)) return;
	if (siege_group(i)>=0) { cancel_siege_compound(siege_compounds[siege_group(i)].token); return; }
	escort_mode[i] = escort_goal[i] >= 0 ? mode + 1 : 0;
}

bool World::admit_prison(int i, int g, int64_t prison, int slot_cell, int contact_cell) {
	const int n = soldier_count(), cells = terrain.w * terrain.h;
	if (i < 0 || i >= n || g < 0 || g >= n || i == g || prison <= 0 || prison > 2147483647) return false;
	if (!captive[i] || prison_id[i] != 0 || captor[i] != g || hp[i] <= 0 || ko[i] > 0 || getup[i] > 0 || !can_act(g)) return false;
	if (slot_cell < 0 || slot_cell >= cells || contact_cell < 0 || contact_cell >= cells || escort_goal[i] >= 0 || escort_goal[g] >= 0) return false;
	const int x = slot_cell % terrain.w, y = slot_cell / terrain.w;
	const int gx = contact_cell % terrain.w, gy = contact_cell / terrain.w, dx = gx - x, dy = gy - y;
	if (std::abs(dx) + std::abs(dy) != 1 || !terrain.edge(x, y, dx > 0 ? E : dx < 0 ? W : dy > 0 ? S : N)) return false;
	if (int(std::floor(px[i])) != x || int(std::floor(py[i])) != y || int(std::floor(px[g])) != gx || int(std::floor(py[g])) != gy) return false;
	if (vx[i] * vx[i] + vy[i] * vy[i] > 1e-6f || vx[g] * vx[g] + vy[g] * vy[g] > 1e-6f) return false;
	for (int j = 0; j < n; ++j) if (j != i && hp[j] > 0 && ((int(std::floor(px[j])) == x && int(std::floor(py[j])) == y) || (escort_mode[j] && escort_goal[j] == slot_cell))) return false;
	prison_id[i] = prison; escape_t[i] = 0; escort_mode[i] = 0; escort_goal[i] = -1;
	vx[i] = vy[i] = 0; nx[i] = px[i]; ny[i] = py[i];
	return true;
}

bool World::release_prison(int i, int executor, int64_t prison, int contact_cell, int exit_cell) {
	const int n = soldier_count(), cells = terrain.w * terrain.h;
	if (i < 0 || i >= n || executor < 0 || executor >= n || i == executor || prison <= 0 || prison_id[i] != prison || !captive[i] || hp[i] <= 0 || !can_act(executor)) return false;
	if (contact_cell < 0 || contact_cell >= cells || exit_cell < 0 || exit_cell >= cells || escort_goal[executor] >= 0) return false;
	const int x = int(std::floor(px[i])), y = int(std::floor(py[i]));
	const int gx = contact_cell % terrain.w, gy = contact_cell / terrain.w, dx = gx - x, dy = gy - y;
	if (std::abs(dx) + std::abs(dy) != 1 || !terrain.edge(x, y, dx > 0 ? E : dx < 0 ? W : dy > 0 ? S : N)) return false;
	if (int(std::floor(px[executor])) != gx || int(std::floor(py[executor])) != gy || !terrain.walkable(exit_cell % terrain.w, exit_cell / terrain.w)) return false;
	if (vx[executor] * vx[executor] + vy[executor] * vy[executor] > 1e-6f) return false;
	for (int j = 0; j < n; ++j) if (j != i && j != executor && hp[j] > 0 && ((int(std::floor(px[j])) == exit_cell % terrain.w && int(std::floor(py[j])) == exit_cell / terrain.w) || (escort_mode[j] && escort_goal[j] == exit_cell))) return false;
	// The synchronous Site action commits the original relationship and meals.
	// Do not emit EV_ESCAPED and replay the same supply transfer a second time.
	prison_id[i] = 0; captive[i] = 0; captor[i] = -1; escape_t[i] = 0;
	escort_mode[i] = 0; escort_goal[i] = -1; target[i] = -1; enc_target[i] = -1;
	captives_.erase(std::remove(captives_.begin(), captives_.end(), i), captives_.end());
	formations[form[i]].command_dirty = true;
	return true;
}

// Prefilter for rescue / auto-capture searches: where are the soldiers who could start one?
// (same conditions as the searches below, minus the per-target checks)
void World::build_idle_blocks() {
	for (auto &b : idle_block_) std::fill(b.begin(), b.end(), 0);
	for (auto &b : idle_ai_block_) std::fill(b.begin(), b.end(), 0);
	const int n = soldier_count();
	for (int r = 0; r < n; ++r) {
		if (!can_act(r) || (escort_mode[r] != 0 || is_siege_crew(r)) || stagger[r] > 0 || rescue_of[r] >= 0 || capture_of[r] >= 0 || target[r] >= 0 || state[r] != S_SLOT) continue;
		const Formation &F = formations[form[r]];
		if (F.order != Order::HOLD || F.routed) continue;
		int s = faction_slot_[team[r]];
		size_t b = (size_t)(((int)py[r] >> 3) * bw_ + ((int)px[r] >> 3));
		idle_block_[s][b]++;
		if (F.ai_enabled) idle_ai_block_[s][b]++;
	}
}

bool World::idle_near(const std::vector<uint16_t> &blocks, float x, float y, float r) const {
	int x0 = std::max(0, (int)(x - r) >> 3), x1 = std::min(bw_ - 1, (int)(x + r) >> 3);
	int y0 = std::max(0, (int)(y - r) >> 3), y1 = std::min(bh_ - 1, (int)(y + r) >> 3);
	for (int yy = y0; yy <= y1; ++yy)
		for (int xx = x0; xx <= x1; ++xx)
			if (blocks[(size_t)yy * bw_ + xx]) return true;
	return false;
}

void World::rescue_stage(float dt) {
	build_idle_blocks();
	// rescue progress (D72: 4 action seconds, both stopped, adjacent; shortens the wait to <= 1 game hour)
	size_t w = 0;
	for (int r : rescuers_) {
		int p = rescue_of[r];
		if (p < 0) continue;
		float dx = px[r] - px[p], dy = py[r] - py[p];
		// "stopped": the rescuer holds still (S_RESCUE zeroes its own motion); only crowd pushes move it
		float lim = std::max(1.5f, cfg.rescue_seek_cells + 2.f);
		bool ok = can_act(r) && hp[p] > 0.0 && ko[p] > 0.0 && !captive[p] && dx * dx + dy * dy <= lim * lim;
		if (!ok) { cancel_actions_involving(r); continue; }
		if (dx * dx + dy * dy <= 1.5f * 1.5f) act_t[r] += dt; // the 4 s count only while adjacent and stopped
		if (act_t[r] >= RESCUE_SECONDS) {
			ko[p] = std::min(ko[p], cfg.rescued_ko_seconds);
			bandaged[p] = 1; // rescue stops the bleeding (2026-09-29)
			stats.bandaged++;
			rescue_of[r] = -1; act_t[r] = 0; rescued_by_[p] = -1;
			stats.rescues_done++;
			push_event(EV_RESCUED, p, r);
			continue;
		}
		rescuers_[w++] = r;
	}
	rescuers_.resize(w);
	// start rescues: HOLD, not routed, idle member with no enemy target; adjacent unconscious team-mate
	for (size_t fi = 0; fi < formations.size(); ++fi) {
		Formation &f = formations[fi];
		if ((tick + (uint32_t)fi) % 15 != 0 || f.order != Order::HOLD || f.routed || f.garrisoned) continue;
		for (int p : f.members) {
			if (hp[p] <= 0.0 || ko[p] <= 0.0 || (bandaged[p] && ko[p] <= cfg.rescued_ko_seconds) || captive[p] || rescued_by_[p] >= 0) continue;
			int best = -1;
			float reach_r = std::max(1.3f, cfg.rescue_seek_cells);
			if (!idle_near(idle_block_[faction_slot_[team[p]]], px[p], py[p], reach_r)) continue;
			float bd = reach_r * reach_r;
			int rr = (int)std::ceil(reach_r);
			int cx = (int)px[p], cy = (int)py[p];
			for (int yy = std::max(0, cy - rr); yy <= std::min(terrain.h - 1, cy + rr); ++yy)
				for (int xx = std::max(0, cx - rr); xx <= std::min(terrain.w - 1, cx + rr); ++xx) {
					int c = terrain.idx(xx, yy);
					for (int k = hash_start_[c]; k < hash_start_[c + 1]; ++k) {
						int r = hash_items_[k];
						if (form[r] != (int)fi || r == p || !can_act(r) || (escort_mode[r] != 0 || is_siege_crew(r)) || stagger[r] > 0 || rescue_of[r] >= 0 || capture_of[r] >= 0 ||
						    target[r] >= 0 || state[r] != S_SLOT)
							continue;
						float dx = px[r] - px[p], dy = py[r] - py[p], d2 = dx * dx + dy * dy;
						if (d2 > 1.3f * 1.3f && !los(px[r], py[r], px[p], py[p])) {
							// Keep ordinary walking/LOS and capture admission unchanged.
							// An original fallen occupant is already within the existing
							// rescue reach; its own retained wreck is not a terrain wall.
							const int rc = terrain.idx((int)px[r], (int)py[r]);
							const int pc = terrain.idx((int)px[p], (int)py[p]);
							if (d2 > 1.5f * 1.5f || !siege_route_cell(rc) || siege_route_cell(pc) ||
							    terrain.height[rc] != terrain.height[pc] || (size_t)p >= siege_wreck_exit.size()) continue;
							const auto &domain = siege_wreck_exit[p];
							if (std::find(domain.begin(), domain.end(), pc) == domain.end() ||
							    !los(px[r], py[r], px[p], py[p], &domain)) continue;
						}
						if (d2 < bd || (d2 == bd && r < best)) { bd = d2; best = r; }
					}
				}
			if (best >= 0) {
				rescue_of[best] = p; act_t[best] = 0; rescued_by_[p] = best;
				rescuers_.push_back(best);
				stats.rescues_started++;
			}
		}
	}
}

// Person actions and captive escort run on game time at the sustain point (terrain_lab._advance_fatigue:
// person_actions.advance(game_seconds), captive_escort.advance(game_seconds)).
void World::person_actions_stage(double gdt) {
	build_idle_blocks();
	// auto-capture (2026-09-29 user decision): an idle member of an AI formation in HOLD (not routed, no
	// enemy target) walks up to capture_seek_cells to an unconscious enemy that is not captive and not
	// already being captured; the 4 s adjacent action is the same as an explicit order. Rescue of own
	// wounded is decided first in the same step, so a free soldier helps friends before taking prisoners.
	if (cfg.auto_capture && cfg.capture_seek_cells > 0.f) {
		const int n = soldier_count();
		bool held_built = false;
		for (int t = (int)((15u - tick % 15u) % 15u); t < n; t += 15) {
			if (hp[t] <= 0.0 || ko[t] <= 0.0 || captive[t] || capturing_by_[t] >= 0) continue;
			if (!held_built) {
				held_.assign((size_t)n, 0);
				for (int c : captives_) if (captive[c] && prison_id[c] == 0 && hp[c] > 0.0 && captor[c] >= 0) held_[captor[c]]++;
				held_built = true;
			}
			const float reach_r = std::max(1.3f, cfg.capture_seek_cells);
			bool any_guard = false;
			for (size_t k = 0; k < slot_faction_.size() && !any_guard; ++k)
				if (hostile(slot_faction_[k], team[t])) any_guard = idle_near(idle_ai_block_[k], px[t], py[t], reach_r);
			if (!any_guard) continue;
			float bd = reach_r * reach_r;
			int best = -1, rr = (int)std::ceil(reach_r);
			int cx = (int)px[t], cy = (int)py[t];
			for (int yy = std::max(0, cy - rr); yy <= std::min(terrain.h - 1, cy + rr); ++yy)
				for (int xx = std::max(0, cx - rr); xx <= std::min(terrain.w - 1, cx + rr); ++xx) {
					int c = terrain.idx(xx, yy);
					for (int k = hash_start_[c]; k < hash_start_[c + 1]; ++k) {
						int r = hash_items_[k];
						if (!hostile(team[r], team[t]) || !can_act(r) || (escort_mode[r] != 0 || is_siege_crew(r)) || stagger[r] > 0 || rescue_of[r] >= 0 || capture_of[r] >= 0 ||
						    target[r] >= 0 || state[r] != S_SLOT || held_[r] >= GUARD_CAPACITY)
							continue;
						const Formation &F = formations[form[r]];
						if (!F.ai_enabled || F.order != Order::HOLD || F.routed) continue;
						float dx = px[r] - px[t], dy = py[r] - py[t], d2 = dx * dx + dy * dy;
						if (d2 > bd || (d2 == bd && r > best && best >= 0)) continue;
						if (d2 > 1.3f * 1.3f && !los(px[r], py[r], px[t], py[t])) continue;
						bd = d2; best = r;
					}
				}
			if (best >= 0) {
				capture_of[best] = t; act_t[best] = 0; capturing_by_[t] = best;
				capturers_.push_back(best);
				stats.captures_started++;
				stats.captures_auto++;
			}
		}
	}
	// capture progress (inst. sec.6: 4 s, adjacent, stopped; the target stays unconscious)
	size_t w = 0;
	for (int g : capturers_) {
		int t = capture_of[g];
		if (t < 0) continue;
		float dx = px[g] - px[t], dy = py[g] - py[t];
		float lim = std::max(1.5f, cfg.capture_seek_cells + 2.f);
		bool ok = can_act(g) && hp[t] > 0.0 && ko[t] > 0.0 && !captive[t] && dx * dx + dy * dy <= lim * lim;
		if (!ok) { cancel_actions_involving(g); continue; }
		if (dx * dx + dy * dy <= 1.5f * 1.5f) act_t[g] += gdt; // the 4 s count only while adjacent and stopped
		if (act_t[g] >= CAPTURE_SECONDS) {
			captive[t] = 1; captor[t] = g; escape_t[t] = 0;
			capture_of[g] = -1; act_t[g] = 0; capturing_by_[t] = -1;
			if (rescued_by_[t] >= 0) cancel_actions_involving(rescued_by_[t]);
			captives_.push_back(t);
			formations[form[t]].command_dirty = true;
			enc_target[t] = -1; target[t] = -1;
			stats.captures_done++;
			push_event(EV_CAPTURED, t, g);
			continue;
		}
		capturers_[w++] = g;
	}
	capturers_.resize(w);
	// escape: awake captive, no effective guard within 4 cells and no near threat for 30 s
	w = 0;
	for (int c : captives_) {
		if (!captive[c] || hp[c] <= 0.0) continue;
		if (prison_id[c] > 0) { escape_t[c] = 0; captives_[w++] = c; continue; }
		if (ko[c] > 0.0 || getup[c] > 0.0) { escape_t[c] = 0; captives_[w++] = c; continue; }
		int g = captor[c];
		bool guarded = false;
		if (g >= 0 && can_act(g) && hostile(team[g], team[c])) {
			float dx = px[g] - px[c], dy = py[g] - py[c];
			guarded = dx * dx + dy * dy <= GUARD_CELLS * GUARD_CELLS;
		}
		bool threat = false;
		const uint16_t *eb = enemy_blocks(team[c]);
		int bx = (int)px[c] >> 3, by = (int)py[c] >> 3;
		for (int yy = std::max(0, by - 1); yy <= std::min(bh_ - 1, by + 1) && !threat; ++yy)
			for (int xx = std::max(0, bx - 1); xx <= std::min(bw_ - 1, bx + 1); ++xx)
				if (eb[yy * bw_ + xx]) { threat = true; break; }
		if (guarded || threat) escape_t[c] = 0;
		else escape_t[c] += gdt; // 30 game seconds (captive_escort.advance(game_seconds))
		if (escape_t[c] >= ESCAPE_SECONDS) {
			captive[c] = 0; captor[c] = -1; escape_t[c] = 0;
			escort_goal[c] = -1; escort_mode[c] = 0;
			formations[form[c]].command_dirty = true;
			stats.escapes++;
			push_event(EV_ESCAPED, c, -1);
			continue;
		}
		captives_[w++] = c;
	}
	captives_.resize(w);
}

// ---------------------------------------------------------------- bleeding (2026-09-29 user decision)
// Unconscious, not rescued and not captive: -25 HP per game hour until death. Bleeding is not an
// "effective hit": it does not cancel a rescue in progress or reset the KO wait. Death by bleeding is
// a death for morale (-40 x n / living roster) like any other.
void World::bleed_stage(double gdt) {
	const double loss = cfg.bleed_per_game_hour / 3600.0 * gdt;
	if (loss <= 0.0) return;
	const int n = soldier_count();
	for (int i = 0; i < n; ++i) {
		if (hp[i] <= 0.0 || ko[i] <= 0.0 || captive[i] || bandaged[i]) continue;
		if (hp[i] > loss) { hp[i] -= loss; continue; }
		stats.bled_deaths++;
		quiet_contact_ = true;
		apply_contact(i, hp[i], 0.0);
		quiet_contact_ = false;
	}
}

// Candidate host bridge on the ORIGINAL World. No flight or fuel is created here.
bool World::set_host_ranged_delegate(bool enabled) {
	if (!projectiles.empty()) return false; // Existing paid legacy arrows must settle.
	host_ranged_delegate = enabled;
	for (auto &requests : fire_buf_) requests.clear(); // Derived decisions only.
	return true;
}

bool World::commit_host_ranged(int i, int expected_ammo, int mode, int64_t release_id,
		int target_x, int target_y, bool auto_power, rules::RangedShooter &receipt) {
	// The caller owns its current mode/order/holder stamp and admission capacity.
	// The selected original cargo item is projected into the existing ammo scalar.
	if (work_point_finish_ready_ || !host_ranged_delegate || i < 0 || i >= soldier_count() || !projectiles.empty()
	    || release_id <= host_last_release_id || release_id > INT32_MAX || mode < 0 || mode > 1
	    || expected_ammo <= 0 || expected_ammo > 65535 || ammo[i] != expected_ammo
	    || !terrain.contains(target_x,target_y) || !exchange_ready(i) || ranged_cd[i] > 1e-9)
		return false;
	const Formation &f = formations[form[i]];
	const auto profile = rules::ranged_profile(equip[i]);
	const int sx = int(std::floor(px[i])), sy = int(std::floor(py[i]));
	if (!profile.valid || (mode == 1 && equip[i].family != rules::F_BOW)
	    || f.routed || f.order == Order::MOVE || f.order == Order::RETREAT || f.order == Order::RETURN
	    || !terrain.walkable(sx,sy)) return false; // A structure aim point may be blocked.
	const int dx = target_x-sx, dy = target_y-sy;
	const double distance = std::hypot(double(dx),double(dy));
	if (distance <= 1.0 || distance > profile.range) return false;
	// Every rejection precedes original skill/fatigue/cooldown/ammo mutation.
	if (auto_power && ability[i].has()) activate_skill(i,rules::SK_POWER);
	receipt.ability = rules::TROOP_COMBAT_ABILITY;
	receipt.training = f.training; receipt.fatigue = f.fatigue;
	receipt.skill = skill[i]; receipt.equip = equip[i];
	--ammo[i];
	charge(i,1.0);
	if (skill[i] == rules::SK_POWER) { skill[i]=rules::SK_NONE; skill_cd[i]=rules::EXCHANGE_SKILL_COOLDOWN; ++stats.skills_used; }
	face[i]=std::atan2(float(dy),float(dx));
	stagger[i]=std::max(stagger[i],profile.hold); ranged_cd[i]=profile.cooldown;
	host_last_release_id=release_id; // Receipt watermark supplied by the sole Lab sequence.
	++stats.shots; mark_combat(cfg.shot_grace); push_event(EV_SHOT,i,-1); set_visual(i,V_SHOOT);
	return true; // Host now publishes its matching cargo debit and ONE Lab paid flight.
}

bool World::apply_host_projectile_contact(int i, double hp_loss, double stun_add, double stagger_seconds) {
	if (!host_ranged_delegate || i < 0 || i >= soldier_count() || !std::isfinite(hp_loss)
	    || !std::isfinite(stun_add) || !std::isfinite(stagger_seconds)
	    || hp_loss < 0 || stun_add < 0 || stagger_seconds < 0) return false;
	if (!alive(i)) return true;
	if (skill[i] == rules::SK_BRACE) { skill[i]=rules::SK_NONE; skill_cd[i]=rules::EXCHANGE_SKILL_COOLDOWN; ++stats.skills_used; }
	// Reuse original hit revision, interruptions, KO/death and hit presentation.
	return apply_siege_contact(i,hp_loss,stun_add,stagger_seconds);
}

bool World::apply_fire_exposure_damage(int i, double hp_loss) {
	if (!host_ranged_delegate || i < 0 || i >= soldier_count() || !std::isfinite(hp_loss) || hp_loss < 0) return false;
	if (!alive(i) || hp_loss == 0) return true;
	apply_contact(i,hp_loss,0.0,true); // Original environmental semantics, combat casualty checkpoint retained.
	return true;
}

bool World::set_fire_visual_rows(const std::vector<int> &indices, const std::vector<uint8_t> &flags) {
	if (indices.size()!=flags.size() || indices.size()>size_t(soldier_count())) return false;
	std::unordered_map<int,bool> seen;
	for (size_t k=0;k<indices.size();++k)
		if (indices[k]<0 || indices[k]>=soldier_count() || flags[k]>2 || !seen.emplace(indices[k],true).second) return false;
	if (fire_visual.size()!=size_t(soldier_count())) fire_visual.assign(soldier_count(),0);
	for (size_t k=0;k<indices.size();++k) fire_visual[indices[k]]=flags[k];
	return true; // Derived original 12-float atlas channel; no material/Transform owner.
}

} // namespace wg
