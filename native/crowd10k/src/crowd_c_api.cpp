#include "crowd_c_api.h"
#include "crowd_core.hpp"

#include <algorithm>
#include <cstring>
#include <vector>

struct wg_crowd {
	explicit wg_crowd(int threads) : world(threads) {}
	wg::World world;
	std::vector<float> render;
};

extern "C" {

wg_crowd *wg_crowd_create(int threads, int64_t seed) {
	wg_crowd *c = new wg_crowd(threads < 1 ? 1 : threads);
	c->world.cfg.seed = seed;
	return c;
}
void wg_crowd_destroy(wg_crowd *c) { delete c; }
void wg_crowd_set_ai(wg_crowd *c, int enabled) { c->world.cfg.ai = enabled != 0; }
void wg_crowd_set_hostile(wg_crowd *c, int a, int b, int h) { c->world.set_hostile(a, b, h != 0); }
void wg_crowd_set_wounded_rules(wg_crowd *c, float rescue_seek, int auto_capture, float capture_seek) {
	c->world.cfg.rescue_seek_cells = rescue_seek; c->world.cfg.auto_capture = auto_capture != 0; c->world.cfg.capture_seek_cells = capture_seek;
}

void wg_crowd_set_terrain(wg_crowd *c, int w, int h, const uint8_t *height_levels, const uint8_t *flags,
                          const uint8_t *ramp_edges, const uint8_t *static_blocked, const uint8_t *facility) {
	wg::Terrain t;
	t.allocate(w, h);
	const size_t n = (size_t)w * h;
	std::memcpy(t.height.data(), height_levels, n);
	std::memcpy(t.flags.data(), flags, n);
	std::memcpy(t.ramp_edges.data(), ramp_edges, n);
	if (static_blocked) std::memcpy(t.static_blocked.data(), static_blocked, n);
	if (facility) std::memcpy(t.facility.data(), facility, n);
	t.base_height = c->world.terrain.base_height.size() == n ? c->world.terrain.base_height : t.height;
	c->world.update_terrain(std::move(t));
}

int wg_crowd_add_formation(wg_crowd *c, int team, float cx, float cy, float facing, int cols, float spacing, int troop,
                           double training) {
	return c->world.add_formation(team, cx, cy, facing, cols, spacing, (wg::Troop)troop, training);
}
int wg_crowd_add_soldier(wg_crowd *c, int formation, int64_t person_id, int family, int material, int armor, int shield,
                         int role, int ammo) {
	wg::rules::Equip e;
	e.family = (uint8_t)family; e.material = (uint8_t)material; e.armor = (uint8_t)armor; e.shield = shield != 0;
	return c->world.add_soldier(formation, e, (wg::Role)role, person_id, (uint16_t)std::clamp(ammo, 0, 65535));
}
void wg_crowd_finalize(wg_crowd *c) { c->world.finalize(); }

void wg_crowd_set_order_owner(wg_crowd *c, int f, int ai_owned) { if (c && f >= 0 && f < (int)c->world.formations.size()) c->world.formations[f].ai_enabled = ai_owned != 0 && !c->world.formations[f].no_orders; }
int wg_crowd_host_order(wg_crowd *c, int f, int kind, float gx, float gy, double x) { return c ? c->world.host_order(f,kind,gx,gy,x) : WG_BAD_FORMATION; }
int wg_crowd_order_move(wg_crowd *c,int f,float x,float y,float facing) { return wg_crowd_host_order(c,f,1,x,y,facing); }
int wg_crowd_order_attack(wg_crowd *c,int f,int t) { return wg_crowd_host_order(c,f,2,0,0,t); }
int wg_crowd_order_hold(wg_crowd *c,int f) { return wg_crowd_host_order(c,f,0,0,0,0); }
int wg_crowd_order_pursue(wg_crowd *c,int f,int t) { return wg_crowd_host_order(c,f,4,0,0,t); }
int wg_crowd_order_retreat(wg_crowd *c,int f,float x,float y) { return wg_crowd_host_order(c,f,3,x,y,0); }
int wg_crowd_order_charge(wg_crowd *c,int f,float x,float y) { return wg_crowd_host_order(c,f,5,x,y,0); }
int wg_crowd_order_charge_formation(wg_crowd *c,int f,int enemy) { return wg_crowd_host_order(c,f,7,0,0,enemy); }
int wg_crowd_order_rally(wg_crowd *c,int f) { return wg_crowd_host_order(c,f,6,0,0,0); }
int wg_crowd_order_capture(wg_crowd *c,int g,int t) {
	if (!c || g < 0 || g >= c->world.soldier_count()) return WG_BAD_FORMATION;
	const auto &f=c->world.formations[c->world.form[g]];
	if(f.no_orders) return WG_NO_ORDERS; if(f.ai_enabled) return WG_NOT_OWNER;
	if(t<0 || t>=c->world.soldier_count()) return WG_NO_TARGET;
	return c->world.order_capture(g,t) ? WG_OK : WG_NO_TARGET;
}
int wg_crowd_step(wg_crowd *c,float dt) { return c && c->world.step(dt) ? 1 : 0; }
int wg_crowd_step_clock(wg_crowd *c,float dt,double gs,double cl) { return c && c->world.step_clock(dt,gs,cl) ? 1 : 0; }
int wg_crowd_validate(const wg_crowd *c) { return c && c->world.validate() ? 1 : 0; }
int wg_crowd_set_sustain_input(wg_crowd *c,int f,int fed,double d) { return c && c->world.set_sustain_input(f,fed!=0,d) ? 1 : 0; }
int wg_crowd_set_recovery_input(wg_crowd *c,int f,double multiplier) { return c && c->world.set_recovery_input(f,multiplier) ? 1 : 0; }
int wg_crowd_set_housing_recovery_input(wg_crowd *c,int f,double multiplier) { return c && c->world.set_housing_recovery_input(f,multiplier) ? 1 : 0; }
int wg_crowd_order_controlled_step(wg_crowd *c,int person,int destination,int kind) { return c && (kind == 3 || kind == 5) && c->world.order_controlled_step(person,destination,static_cast<wg::World::ControlledStepKind>(kind)) ? 1 : 0; }
void wg_crowd_cancel_controlled_step(wg_crowd *c,int person,int kind) { if (c && (kind == 3 || kind == 5)) c->world.cancel_controlled_step(person,static_cast<wg::World::ControlledStepKind>(kind)); }
int wg_crowd_apply_environment_damage(wg_crowd *c,int i,double d) { return c && c->world.apply_environment_damage(i,d) ? 1 : 0; }
int wg_crowd_apply_melee_contact(wg_crowd *c,int i,double hp_loss,double stun_add) { return c && c->world.apply_melee_contact(i,hp_loss,stun_add) ? 1 : 0; }
int wg_crowd_charge_exchange_fatigue(wg_crowd *c,int i,double amount) { return c && c->world.charge_exchange_fatigue(i,amount) ? 1 : 0; }
int wg_crowd_add_convoy(wg_crowd *c,float ax,float ay,float facing) { return c ? c->world.add_convoy(ax,ay,facing) : 0; }
int wg_crowd_convoy_set_crew(wg_crowd *c,int id,int soldier,int ox,int oy,int assigned) { return c && c->world.convoy_set_crew(id,soldier,ox,oy,assigned!=0) ? 1 : 0; }
int wg_crowd_convoy_order_goal(wg_crowd *c,int id,float gx,float gy,float gfacing) { return c && c->world.convoy_order_goal(id,gx,gy,gfacing) ? 1 : 0; }
int wg_crowd_convoy_set_body(wg_crowd *c,int id,const int32_t *cells,int count) {
	if (!c || count < 0 || (count > 0 && !cells)) return 0;
	return c->world.convoy_set_body(id,std::vector<int>(cells,cells+count)) ? 1 : 0;
}
int wg_crowd_convoy_state(const wg_crowd *c,int id,double *out) {
	wg::ConvoyState s;
	if (!c || !out || !c->world.convoy_state(id,s)) return 0;
	out[0]=s.x; out[1]=s.y; out[2]=s.facing; out[3]=s.moving; out[4]=s.complete; out[5]=s.stalled; out[6]=s.reason;
	return 1;
}
int wg_crowd_convoy_remove(wg_crowd *c,int id) { return c && c->world.convoy_remove(id) ? 1 : 0; }
int wg_crowd_convoy_attach_formation(wg_crowd *c,int id,int formation) { return c && c->world.convoy_attach_formation(id,formation) ? 1 : 0; }
int wg_crowd_convoy_detach_formation(wg_crowd *c,int id) { return c && c->world.convoy_detach_formation(id) ? 1 : 0; }
int wg_crowd_convoy_formation(const wg_crowd *c,int id) { return c ? c->world.convoy_formation(id) : -2; }
int wg_crowd_site_person_exit_ready(const wg_crowd *c,int i) { return c && c->world.site_person_exit_ready(i) ? 1 : 0; }
int wg_crowd_site_person_board(wg_crowd *c,int i,int vehicle) {
	return c && i>=0 && i<c->world.soldier_count() && c->world.site_person_board(i,vehicle) ? 1 : 0;
}
int wg_crowd_site_person_land(wg_crowd *c,int i,double x,double y) {
	return c && i>=0 && i<c->world.soldier_count() && c->world.site_person_land(i,x,y) ? 1 : 0;
}
int wg_crowd_site_person_set_deck(wg_crowd *c,int i,double x,double y) {
	return c && i>=0 && i<c->world.soldier_count() && c->world.site_person_set_deck(i,x,y) ? 1 : 0;
}
int wg_crowd_site_person_retarget_aboard(wg_crowd *c,int i,int vehicle) {
	return c && i>=0 && i<c->world.soldier_count() && c->world.site_person_retarget_aboard(i,vehicle) ? 1 : 0;
}
int wg_crowd_site_person_aboard(const wg_crowd *c,int i,double *out) {
	if (!c || !out || i<0 || i>=c->world.soldier_count()) return 0;
	out[0] = c->world.is_aboard(i) ? 1.0 : 0.0; out[1] = static_cast<double>(c->world.aboard_vehicle[i]);
	return 1;
}
int wg_crowd_site_person_absent(wg_crowd *c,int i,int kind) {
	return c && i>=0 && i<c->world.soldier_count() && c->world.site_person_absent(i,kind) ? 1 : 0;
}
int wg_crowd_site_person_return(wg_crowd *c,int i,int formation,double x,double y) {
	return c && i>=0 && i<c->world.soldier_count() && c->world.site_person_return(i,formation,x,y) ? 1 : 0;
}
int wg_crowd_move_member(wg_crowd *c,int i,int to_formation) {
	return c && i>=0 && i<c->world.soldier_count() && c->world.move_member(i,to_formation) ? 1 : 0;
}
int wg_crowd_transfer_member(wg_crowd *c,int i,int to_formation) {
	return c && i>=0 && i<c->world.soldier_count() && c->world.transfer_member(i,to_formation) ? 1 : 0;
}
int wg_crowd_leave_member(wg_crowd *c,int i,int to_formation) {
	return c && i>=0 && i<c->world.soldier_count() && c->world.leave_member(i,to_formation) ? 1 : 0;
}
int wg_crowd_site_person_absent_state(const wg_crowd *c,int i,double *out) {
	if (!c || !out || i<0 || i>=c->world.soldier_count()) return 0;
	out[0] = c->world.is_absent(i) ? 1.0 : 0.0; out[1] = static_cast<double>(c->world.absent_kind[i]);
	return 1;
}
int wg_crowd_soldier_surrendered(const wg_crowd *c,int i,double *out) {
	if (!c || !out || i<0 || i>=c->world.soldier_count()) return 0;
	out[0] = c->world.is_surrendered(i) ? 1.0 : 0.0;
	return 1;
}
int wg_crowd_set_soldier_surrendered(wg_crowd *c,int i,int on) {
	return c && i>=0 && i<c->world.soldier_count() && c->world.set_surrendered(i, on != 0) ? 1 : 0;
}
int wg_crowd_soldier_mounted(const wg_crowd *c,int i,double *out) {
	if (!c || !out || i<0 || i>=c->world.soldier_count()) return 0;
	out[0] = c->world.is_mounted(i) ? 1.0 : 0.0;
	return 1;
}
int wg_crowd_soldier_charge(const wg_crowd *c,int i,double *out) {
	if (!c || !out || i<0 || i>=c->world.soldier_count()) return 0;
	out[0] = c->world.charge_state(i) ? 1.0 : 0.0;
	out[1] = c->world.charge_straight_seconds(i);
	out[2] = (double)c->world.charge_hits(i);
	out[3] = (double)c->world.cav_distinct_victims(i);
	return 1;
}
int wg_crowd_set_soldier_mounted(wg_crowd *c,int i,int on) {
	return c && i>=0 && i<c->world.soldier_count() && c->world.set_mounted(i, on != 0) ? 1 : 0;
}
int wg_crowd_site_person_release(wg_crowd *c,int i,double *out) {
	wg::SitePersonRelease r;
	if (!c || !out || !c->world.site_person_release(i,r)) return 0;
	out[0] = r.hp; out[1] = r.fatigue; out[2] = r.fatigue_rest; out[3] = static_cast<double>(r.ammo);
	out[4] = static_cast<double>(r.cell_x); out[5] = static_cast<double>(r.cell_y); out[6] = r.x; out[7] = r.y;
	return 1;
}
int wg_crowd_site_person_exit_ready_aboard(const wg_crowd *c,int i,int vehicle) { return c && c->world.site_person_exit_ready_aboard(i,vehicle) ? 1 : 0; }
int wg_crowd_site_person_release_aboard(wg_crowd *c,int i,int vehicle,double *out) {
	wg::SitePersonRelease r;
	if (!c || !out || !c->world.site_person_release_aboard(i,vehicle,r)) return 0;
	out[0] = r.hp; out[1] = r.fatigue; out[2] = r.fatigue_rest; out[3] = static_cast<double>(r.ammo);
	out[4] = static_cast<double>(r.cell_x); out[5] = static_cast<double>(r.cell_y); out[6] = r.x; out[7] = r.y;
	return 1;
}
int wg_crowd_has_projectiles(const wg_crowd *c) { return c && !c->world.projectiles.empty() ? 1 : 0; }
double wg_crowd_combat_mark(const wg_crowd *c) { return c->world.combat_mark; }
double wg_crowd_combat_left(const wg_crowd *c) { return c->world.combat_left; }

int wg_crowd_drain_events(wg_crowd *c, int *kind, int64_t *person, int64_t *other, int *formation, double *time, int capacity) {
	auto &ev = c->world.events;
	int m = std::min<int>((int)ev.size(), std::max(0, capacity));
	for (int k = 0; k < m; ++k) {
		if (kind) kind[k] = ev[k].kind;
		if (person) person[k] = ev[k].person;
		if (other) other[k] = ev[k].other;
		if (formation) formation[k] = ev[k].formation;
		if (time) time[k] = ev[k].time;
	}
	ev.erase(ev.begin(), ev.begin() + m);
	return m;
}

void wg_crowd_set_soldier_state(wg_crowd *c, int i, const wg_soldier_state *s) {
	wg::SoldierState t;
	t.hp = s->hp; t.stun = s->stun; t.grace = s->grace; t.ko = s->ko; t.getup = s->getup; t.stagger = s->stagger;
	t.captive = s->captive; t.captor_person = s->captor_person; t.bandaged = s->bandaged; t.ammo = s->ammo;
	t.tactics = s->tactics; t.leadership = s->leadership; t.coach = s->coach;
	t.escape_t = s->escape_t; t.exch_cd = s->exch_cd; t.ranged_cd = s->ranged_cd; t.skill_cd = s->skill_cd; t.knock_t = s->knock_t; t.act_t = s->act_t; t.role = s->role; t.x = s->x; t.y = s->y; t.facing = s->facing;
	c->world.set_soldier_state(i, t);
}
void wg_crowd_get_soldier_state(const wg_crowd *c, int i, wg_soldier_state *s) {
	wg::SoldierState t = c->world.get_soldier_state(i);
	s->hp = t.hp; s->stun = t.stun; s->grace = t.grace; s->ko = t.ko; s->getup = t.getup; s->stagger = t.stagger;
	s->captive = t.captive; s->captor_person = t.captor_person; s->bandaged = t.bandaged; s->ammo = t.ammo;
	s->tactics = t.tactics; s->leadership = t.leadership; s->coach = t.coach;
	s->escape_t = t.escape_t; s->exch_cd = t.exch_cd; s->ranged_cd = t.ranged_cd; s->skill_cd = t.skill_cd; s->knock_t = t.knock_t; s->act_t = t.act_t; s->role = t.role; s->x = t.x; s->y = t.y; s->facing = t.facing;
}
void wg_crowd_set_formation_state(wg_crowd *c, int f, const wg_formation_state *s) {
	wg::FormationState t;
	t.morale = s->morale; t.rally_rest = s->rally_rest; t.fatigue = s->fatigue; t.fatigue_rest = s->fatigue_rest; t.training = s->training;
	t.routed = s->routed; t.needs_attack_order = s->needs_attack_order; t.commander_present = s->commander_present;
	t.formal_person = s->formal_person; t.acting_person = s->acting_person;
	t.current_person = s->current_person; t.target_person = s->target_person; t.fatigue_count = s->fatigue_count; t.order = s->order; t.ai_enabled = s->ai_enabled; t.no_orders = s->no_orders; t.host_center = s->host_center; t.goal_x = s->goal_x; t.goal_y = s->goal_y; t.goal_facing = s->goal_facing; t.cx = s->cx; t.cy = s->cy; t.facing = s->facing; t.origin_x = s->origin_x; t.origin_y = s->origin_y; t.ref_x = s->ref_x; t.ref_y = s->ref_y; t.pursuit_left = s->pursuit_left; t.order_delay = s->order_delay; t.attacking = s->attacking; t.ref_valid = s->ref_valid; t.resupplying = s->resupplying;
	for (int k = 0; k < std::clamp(s->officer_count, 0, 16); ++k) t.officer_persons.push_back(s->officers[k]);
	c->world.set_formation_state(f, t);
}
void wg_crowd_get_formation_state(const wg_crowd *c, int f, wg_formation_state *s) {
	wg::FormationState t = c->world.get_formation_state(f);
	s->morale = t.morale; s->rally_rest = t.rally_rest; s->fatigue = t.fatigue; s->fatigue_rest = t.fatigue_rest; s->training = t.training;
	s->routed = t.routed; s->needs_attack_order = t.needs_attack_order; s->commander_present = t.commander_present;
	s->formal_person = t.formal_person; s->acting_person = t.acting_person;
	s->current_person = t.current_person; s->target_person = t.target_person; s->fatigue_count = t.fatigue_count; s->order = t.order; s->ai_enabled = t.ai_enabled; s->no_orders = t.no_orders; s->host_center = t.host_center; s->goal_x = t.goal_x; s->goal_y = t.goal_y; s->goal_facing = t.goal_facing; s->cx = t.cx; s->cy = t.cy; s->facing = t.facing; s->origin_x = t.origin_x; s->origin_y = t.origin_y; s->ref_x = t.ref_x; s->ref_y = t.ref_y; s->pursuit_left = t.pursuit_left; s->order_delay = t.order_delay; s->attacking = t.attacking; s->ref_valid = t.ref_valid; s->resupplying = t.resupplying;
	s->officer_count = (int)std::min<size_t>(16, t.officer_persons.size());
	for (int k = 0; k < s->officer_count; ++k) s->officers[k] = t.officer_persons[k];
}
int wg_crowd_get_order_serials(const wg_crowd *c, int f, int64_t *order_serial, int64_t *ranged_order_serial) {
	if (!c || !order_serial || !ranged_order_serial || f < 0 || f >= (int)c->world.formations.size()) return 0;
	*order_serial = c->world.formations[f].order_serial; *ranged_order_serial = c->world.formations[f].ranged_order_serial;
	return 1;
}
int wg_crowd_set_order_serials(wg_crowd *c, int f, int64_t order_serial, int64_t ranged_order_serial) {
	return c && c->world.set_order_serials(f, order_serial, ranged_order_serial) ? 1 : 0;
}
int wg_crowd_get_officers(const wg_crowd *c,int f,int64_t *ids,int cap) {
	if(!c || f<0 || f>=(int)c->world.formations.size()) return -1;
	const auto v=c->world.get_formation_state(f).officer_persons;
	if(ids) for(int k=0;k<std::min(cap,(int)v.size());++k) ids[k]=v[k]; return (int)v.size();
}
int wg_crowd_set_officers(wg_crowd *c,int f,const int64_t *ids,int count) {
	if(!c || f<0 || f>=(int)c->world.formations.size() || count<0 || count>c->world.soldier_count() || (count && !ids)) return 0;
	std::vector<int> out; for(int k=0;k<count;++k) { int i=c->world.soldier_index(ids[k]); if(i<0 || c->world.form[i]!=f) return 0; out.push_back(i); }
	c->world.formations[f].officer_order=std::move(out); return 1;
}
int wg_crowd_set_soldier_equip(wg_crowd *c,int i,int family,int material,int armor,int shield) {
	if(!c || i<0 || i>=c->world.soldier_count() || family<0 || family>wg::rules::F_SHOVEL || material<0 || material>wg::rules::M_STEEL || armor<0 || armor>wg::rules::A_MINGGUANG || shield<0 || shield>1) return 0;
	return c->world.set_soldier_equip(i,{(uint8_t)family,(uint8_t)material,(uint8_t)armor,shield!=0}) ? 1 : 0;
}
int wg_crowd_set_soldier_ammo(wg_crowd *c,int i,int amount) {
	if(!c || i<0 || i>=c->world.soldier_count() || amount<0 || amount>65535) return 0;
	c->world.ammo[i]=(uint16_t)amount; return 1;
}
int wg_crowd_soldier_index(const wg_crowd *c, int64_t p) { return c->world.soldier_index(p); }

int64_t wg_crowd_save(const wg_crowd *c, uint8_t *out, int64_t capacity) {
	std::vector<uint8_t> b = c->world.save();
	if (out && capacity >= (int64_t)b.size()) std::memcpy(out, b.data(), b.size());
	return (int64_t)b.size();
}
int wg_crowd_load(wg_crowd *c, const uint8_t *data, int64_t size) {
	if (!c || !data || size <= 0 || size > 16 * 1024 * 1024) return 0;
	std::vector<uint8_t> b(data, data + size);
	return c->world.load(b) ? 1 : 0;
}

int wg_crowd_pack_render(wg_crowd *c, float *out, int capacity, float cell_pixels) {
	int m = c->world.pack_render(c->render, cell_pixels);
	m = std::min(m, capacity);
	std::memcpy(out, c->render.data(), (size_t)m * 12 * sizeof(float));
	return m;
}

int wg_crowd_soldier_count(const wg_crowd *c) { return c->world.soldier_count(); }
void wg_crowd_get_soldier(const wg_crowd *c, int i, float *x, float *y, double *hp, double *stun, double *ko, int *captive,
                          int *state, int *target) {
	const wg::World &w = c->world;
	if (x) *x = w.px[i];
	if (y) *y = w.py[i];
	if (hp) *hp = w.hp[i];
	if (stun) *stun = w.stun[i];
	if (ko) *ko = w.ko[i];
	if (captive) *captive = w.captive[i];
	if (state) *state = w.state[i];
	if (target) *target = w.target[i];
}
void wg_crowd_apply_contact(wg_crowd *c, int i, double hp_loss, double stun_add) { c->world.apply_contact(i, hp_loss, stun_add); }
void wg_crowd_get_formation(const wg_crowd *c, int f, double *morale, double *fatigue, int *routed, int *commander, int *order) {
	const wg::Formation &F = c->world.formations[f];
	if (morale) *morale = F.morale;
	if (fatigue) *fatigue = F.fatigue;
	if (routed) *routed = F.routed;
	if (commander) *commander = F.current_cmd;
	if (order) *order = (int)F.order;
}
uint64_t wg_crowd_state_hash(const wg_crowd *c) { return c->world.state_hash(); }

} // extern "C"
