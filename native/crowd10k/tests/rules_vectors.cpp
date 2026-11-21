// Reads rule test vectors on stdin (tools/gd_reference.py), prints the C++ port's results.
#include "../src/rules.hpp"

#include <cstdio>
#include <iostream>
#include <sstream>
#include <string>

using namespace wg::rules;

static ExStats read_person(std::istringstream &in, Equip &e) {
	ExStats p;
	double skill, fam, mat, armor, shield;
	in >> p.ability >> p.training >> p.morale >> p.fatigue >> p.armorbonus >> p.facility >> skill >> fam >> mat >> armor >> shield;
	p.skill = (uint8_t)skill;
	e.family = (uint8_t)fam; e.material = (uint8_t)mat; e.armor = (uint8_t)armor; e.shield = shield != 0;
	p.equip = e;
	return p;
}

int main() {
	std::string line;
	std::vector<Cell> cells;
	while (std::getline(std::cin, line)) {
		if (line.empty()) continue;
		std::istringstream in(line);
		char k;
		in >> k;
		if (k == 'X') {
			Equip ea, eb;
			ExStats a = read_person(in, ea), b = read_person(in, eb);
			double roll; in >> roll;
			ExResult r = exchange_result(a, b, roll);
			std::printf("X %d %d %.17g %.17g %.17g %.17g %.17g %.17g %d %.17g %.17g %.17g\n", r.winner, (int)r.kind, r.hp_a, r.hp_b,
			            r.stun_a, r.stun_b, r.stagger, r.hold, (int)r.knockback, r.fatigue_a, r.fatigue_b, r.margin);
		} else if (k == 'R') {
			Equip es, ed;
			ExStats s = read_person(in, es), d = read_person(in, ed);
			double moving, facility, dist, roll;
			in >> moving >> facility >> dist >> roll;
			RangedShooter sh; sh.ability = s.ability; sh.training = s.training; sh.fatigue = s.fatigue; sh.skill = s.skill; sh.equip = es;
			RangedDefense df; df.moving = moving != 0; df.shield = ed.shield; df.facility = facility != 0;
			df.armor_stab = armor_profile(ed).stab; df.skill = d.skill; df.equip = ed;
			RangedResult r = ranged_result(sh, df, dist, roll);
			std::printf("R %d %.17g %.17g %.17g %.17g\n", (int)r.kind, r.hp, r.stun, r.stagger, r.chance);
		} else if (k == 'C') {
			int sx, sy, gx, gy; in >> sx >> sy >> gx >> gy;
			ranged_cells({sx, sy}, {gx, gy}, cells);
			std::printf("C");
			for (auto &c : cells) std::printf(" %d %d", c.x, c.y);
			std::printf("\n");
		} else if (k == 'N') {
			long long a, b, rnd, seed; in >> a >> b >> rnd >> seed;
			std::printf("N %.17g %.17g\n", exchange_roll(a, b, rnd, seed), ranged_roll(a, rnd, b, seed));
		} else if (k == 'D') {
			double v, cap; in >> v >> cap;
			std::printf("D %.17g\n", diminishing(v, cap));
		}
	}
	return 0;
}
