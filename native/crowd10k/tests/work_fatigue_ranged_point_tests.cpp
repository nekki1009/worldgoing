// Real original World discrete ranged cost + same-pool work/CAS coupling.
// This does NOT prove the TerrainLab point merge or P5 contact classification.
#include "../src/crowd_core.hpp"
#include <algorithm>
#include <cmath>
#include <cstdio>
using namespace wg;
static int checks=0, failures=0;
#define CHECK(c,msg) do { ++checks; if(!(c)){++failures;std::fprintf(stderr,"FAIL %d: %s\n",__LINE__,msg);} } while(false)
static void near(double a,double b,const char *message) { CHECK(std::isfinite(a)&&std::abs(a-b)<1e-8,message); }
static constexpr float action=1.f/30.f;
struct Fixture {
	World w{1};
	Fixture() {
		w.terrain.allocate(30,30);w.cfg.ai=false;w.cfg.auto_capture=false;w.cfg.rescue_seek_cells=0;
		w.cfg.bleed_per_game_hour=0;w.combat_left=30;
		rules::Equip bow;bow.family=rules::F_BOW;bow.material=rules::M_IRON;
		rules::Equip sword;sword.family=rules::F_LONGSWORD;sword.material=rules::M_IRON;
		const int fi=w.add_formation(0,10.5f,10.5f,0,3,1,T_BOW,0);
		w.add_soldier(fi,bow,R_CAPTAIN,101,3);
		w.add_soldier(fi,sword,R_REGULAR,102,0);w.add_soldier(fi,sword,R_REGULAR,103,0);
		w.finalize();w.formations[fi].ai_enabled=false;w.order_hold(fi);
		w.px[0]=w.nx[0]=10.5f;w.py[0]=w.ny[0]=10.5f;
		w.formations[fi].fatigue=40;w.formations[fi].fatigue_rest=12;
		CHECK(w.set_host_ranged_delegate(true),"original host ranged owner selected");
	}
};
static World::WorkFatigueState packet(const World &w,double effort) {
	const auto &f=w.formations[0];World::WorkFatigueState p;
	p.formation=0;p.before_count=f.fatigue_count;p.before_fatigue=f.fatigue;p.before_rest=f.fatigue_rest;
	p.work_seconds=effort;p.run_seconds=0;p.fatigue=std::min(rules::FATIGUE_LIMIT,f.fatigue+effort*(10.0/3600.0)/f.fatigue_count);p.rest=0;
	return p;
}
static void unsafe_midinterval_is_detectable_before_host_cost() {
	Fixture f;auto &w=f.w;const auto p=packet(w,120);const auto tick=w.tick;
	CHECK(w.validate_step_clock_work_plan(action,60,30,tick,{p}),"two held workers admit original source pool");
	rules::RangedShooter shot;
	CHECK(w.commit_host_ranged(0,3,0,1,16,10,false,shot),"third original same-pool person pays a true shot");
	near(w.formations[0].fatigue,40+1.0/3.0,"one native shot pulses the actual shared pool");
	const auto paid=w.save();
	CHECK(!w.validate_step_clock_work_plan(action,60,30,tick,{p})&&w.save()==paid,"readonly final gate rejects stale work BEFORE host material debit");
	CHECK(!w.step_clock_work_plan(action,60,30,tick,{p})&&w.save()==paid&&w.tick==tick,"old packet cannot pretend completed after a native shot");
}
static void start_point_then_snapshot() {
	Fixture f;auto &w=f.w;rules::RangedShooter shot;
	CHECK(w.commit_host_ranged(0,3,0,1,16,10,false,shot),"due start-point release happens before snapshot");
	const auto p=packet(w,120);
	CHECK(w.validate_step_clock_work_plan(action,60,30,w.tick,{p}),"fresh snapshot admits both original workers after the shot");
	CHECK(w.step_clock_work_plan(action,60,30,w.tick,{p}),"original work interval publishes once");
	near(w.formations[0].fatigue,40+1.0/3.0+120*(10.0/3600.0)/3,"true shot and worker effort each charged once");
	CHECK(w.ammo[0]==2&&w.stats.shots==1,"native work does not pay ammo or duplicate release");
}
static void completed_point_then_next_snapshot() {
	Fixture f;auto &w=f.w;const auto p=packet(w,120);
	CHECK(w.validate_step_clock_work_plan(action,60,30,w.tick,{p})&&w.step_clock_work_plan(action,60,30,w.tick,{p}),"completed interval consumes shared work before point shot");
	near(w.formations[0].fatigue,40+120*(10.0/3600.0)/3,"completed interval has only its true workers");
	rules::RangedShooter shot;
	CHECK(w.commit_host_ranged(0,3,0,1,16,10,false,shot),"completed point has one original atomic release");
	near(shot.fatigue,p.fatigue,"actual shooter receipt uses completed original fatigue");
	near(w.formations[0].fatigue,p.fatigue+1.0/3.0,"completed point charges original pool once");
	const auto paid=w.save();
	CHECK(!w.commit_host_ranged(0,2,0,1,16,10,false,shot)&&w.save()==paid,"same release ID re-entry pays zero");
	const auto next=packet(w,60);
	CHECK(w.validate_step_clock_work_plan(action,60,30,w.tick,{next})&&w.step_clock_work_plan(action,60,30,w.tick,{next}),"next interval snapshots real post-point fatigue");
	near(w.formations[0].fatigue,p.fatigue+1.0/3.0+60*(10.0/3600.0)/3,"next original interval does not re-bill point shot");
}
static void rejected_release_costs_zero() {
	Fixture f;auto &w=f.w;const auto p=packet(w,120);const auto before=w.save();rules::RangedShooter shot;
	CHECK(!w.commit_host_ranged(0,2,0,1,16,10,true,shot)&&w.save()==before,"stale actual ammo fails before skill/fatigue/cost");
	CHECK(w.validate_step_clock_work_plan(action,60,30,w.tick,{p})&&w.step_clock_work_plan(action,60,30,w.tick,{p}),"failed release leaves original work packet valid");
	near(w.formations[0].fatigue,p.fatigue,"failed release contributes zero effort");
}
int main() {
	unsafe_midinterval_is_detectable_before_host_cost();start_point_then_snapshot();completed_point_then_next_snapshot();rejected_release_costs_zero();
	std::printf("WORK_FATIGUE_RANGED_POINT_%s checks=%d failures=%d; original World only, no Lab/P5 proof\n",failures?"FAIL":"PASS",checks,failures);
	return failures?1:0;
}
