// Build against the ORIGINAL crowd_core with the isolated candidate fragments
// merged. This is a real World owner/step test, not a duplicate fatigue solver.
#include "../src/crowd_core.hpp"
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <limits>

using namespace wg;
static int checks = 0, failures = 0;
#define CHECK(c,msg) do { ++checks; if (!(c)) { ++failures; std::fprintf(stderr,"FAIL %d: %s\n",__LINE__,msg); } } while (false)
static void close(double actual, double expected, const char *message) {
	CHECK(std::isfinite(actual) && std::abs(actual-expected)<1e-8,message);
}
static constexpr float action_seconds = 1.f/30.f;

struct Fixture {
	World w{1};
	Fixture() {
		w.terrain.allocate(48,48);
		w.cfg.ai=false;w.cfg.auto_capture=false;w.cfg.rescue_seek_cells=0;w.cfg.bleed_per_game_hour=0;
		const int first=w.add_formation(0,10.5f,10.5f,0,3,1,T_MELEE,0);
		const int idle=w.add_formation(0,40.5f,40.5f,0,1,1,T_MELEE,0);
		rules::Equip equip;equip.family=rules::F_LONGSWORD;equip.material=rules::M_IRON;
		for(int i=0;i<3;++i) w.add_soldier(first,equip,i==0?R_CAPTAIN:R_REGULAR,101+i);
		w.add_soldier(idle,equip,R_CAPTAIN,201);
		w.finalize();
		for(auto &formation:w.formations) formation.ai_enabled=false;
		w.order_hold(first);w.order_hold(idle);
		w.formations[first].fatigue=40;w.formations[first].fatigue_rest=12;
		w.formations[idle].fatigue=60;w.formations[idle].fatigue_rest=30;
		CHECK(w.formations[first].fatigue_count==3,"original living formation count");
	}
};

static World::WorkFatigueState packet(const World &w,int fi,double work,double run) {
	const auto &f=w.formations[fi];
	World::WorkFatigueState p;
	p.formation=fi;p.before_count=f.fatigue_count;p.before_fatigue=f.fatigue;p.before_rest=f.fatigue_rest;
	p.work_seconds=work;p.run_seconds=run;
	p.fatigue=std::min(rules::FATIGUE_LIMIT,f.fatigue+(work*(10.0/3600.0)+run*rules::FATIGUE_RUN_RATE)/std::max(1,f.fatigue_count));
	p.rest=0;
	return p;
}

static void actual_shared_step() {
	Fixture fixture;auto &w=fixture.w;
	w.running[2]=1;
	const auto snapshot=w.work_fatigue_state(0);
	CHECK(snapshot.size()==5 && snapshot[0]==w.tick && snapshot[1]==0 && snapshot[2]==40 && snapshot[3]==12 && snapshot[4]==3,"getter reads actual tick and original hot pool");
	const auto runners=w.work_fatigue_runners(0);
	CHECK(runners==std::vector<int64_t>({2,103}),"getter returns original native RUN body/identity");
	const auto p=packet(w,0,120,60); // two true workers + one original runner, same pool.
	const auto old_tick=w.tick;const double old_time=w.time;
	CHECK(w.step_clock_work_plan(action_seconds,60,0,old_tick,{p}),"one original shared step accepts whole-pool CAS");
	close(w.formations[0].fatigue,42.11111111111111,"work+RUN charged once, including both original workers");
	close(w.formations[0].fatigue_rest,0,"actual work clears original rest delay");
	close(w.formations[1].fatigue,60-1.0/3.0,"uncovered idle pool retains original recovery");
	CHECK(w.tick==old_tick+1 && w.time>old_time && w.external_clock && w.game_dt==60,"same original tick/action/game clock advances once");
	CHECK(!w.formations[0].charged_this_step,"same original fatigue pass consumes active marker");
	const auto before=w.save();
	CHECK(!w.step_clock_work_plan(action_seconds,60,0,old_tick,{p}) && w.save()==before,"same prior tick cannot replay effort or advance clock");
	w.running[2]=1;
	const double admitted=w.formations[0].fatigue;
	CHECK(w.step_clock(action_seconds,60,0),"ordinary next original step still works");
	close(w.formations[0].fatigue,admitted+2,"plan did not install a persistent RUN delegate");
}

static void rejection_is_atomic() {
	Fixture fixture;auto &w=fixture.w;
	w.running[2]=1;
	const auto valid=packet(w,0,120,60);
	const auto original=w.save();
	CHECK(w.validate_step_clock_work_plan(action_seconds,60,0,w.tick,{valid}) && w.save()==original,"readonly whole-plan preflight admits actual original pools without mutating any World/clock state");
	CHECK(w.validate_step_clock_work_plan(action_seconds,60,0,w.tick,{valid}) && w.save()==original,"readonly preflight can repeat without a pending ticket or second owner");
	auto reject=[&](const std::vector<World::WorkFatigueState> &plan,const char *message) {
		CHECK(!w.validate_step_clock_work_plan(action_seconds,60,0,w.tick,plan) && w.save()==original,"readonly preflight uses same atomic rejection guards before host costs/progress");
		CHECK(!w.step_clock_work_plan(action_seconds,60,0,w.tick,plan) && w.save()==original,message);
	};
	auto bad=valid;bad.before_fatigue+=1;reject({bad},"stale fatigue CAS leaves original World unchanged");
	bad=valid;bad.before_rest+=1;reject({bad},"stale rest CAS leaves original World unchanged");
	bad=valid;--bad.before_count;reject({bad},"changed original membership denominator is rejected");
	bad=valid;bad.work_seconds=-1;reject({bad},"negative effort is rejected before state");
	bad=valid;bad.work_seconds=std::numeric_limits<double>::infinity();reject({bad},"nonfinite effort is rejected before state");
	bad=packet(w,0,120,0);reject({bad},"omitted actual native RUN is rejected rather than undercharging");
	bad=packet(w,0,121,60);reject({bad},"more activity than original people can perform is rejected");
	bad=valid;bad.fatigue-=.1;reject({bad},"planner result must match original actual-effort rates");
	bad=valid;bad.rest=30;reject({bad},"positive effort cannot grant rest recovery");
	reject({valid,valid},"duplicate original formation cannot be charged twice");
	auto other=packet(w,1,60,0);other.before_rest=0;
	reject({valid,other},"later pool CAS failure cannot partly publish earlier pool");
	reject({packet(w,1,60,0),valid},"noncanonical formation order is rejected atomically");
	CHECK(!w.step_clock_work_plan(action_seconds,std::numeric_limits<double>::quiet_NaN(),0,w.tick,{valid}) && w.save()==original,"invalid original game clock leaves whole state unchanged");
	CHECK(!w.step_clock_work_plan(action_seconds,0,0,w.tick,{valid}) && w.save()==original,"zero endpoint cannot replay positive work");
}

static void partial_effort_endpoints_and_persistence() {
	Fixture fixture;auto &w=fixture.w;
	w.formations[0].fatigue=79.9;
	// A true REST/completion prefix can stop both course participants before
	// the enclosing game interval ends; no work is charged in its suffix.
	auto p=packet(w,0,108,0);
	CHECK(w.step_clock_work_plan(action_seconds,60,0,w.tick,{p}),"partial actual worker seconds are accepted");
	close(w.formations[0].fatigue,80,"original 80 endpoint uses actual person seconds, not full 60*2");
	const auto bytes=w.save();World restored(1);
	CHECK(restored.load(bytes) && restored.state_hash()==w.state_hash(),"original World save roundtrip retains committed pool without a second ledger");
	CHECK(restored.work_fatigue_state(0)==w.work_fatigue_state(0),"restored query reads same original hot pool/tick");
	Fixture empty,legacy;
	CHECK(empty.w.step_clock_work_plan(action_seconds,60,0,empty.w.tick,{}) && legacy.w.step_clock(action_seconds,60,0),"empty plan retains ordinary original step");
	CHECK(empty.w.state_hash()==legacy.w.state_hash(),"empty plan is exactly ordinary native behavior");
	Fixture both;
	const auto first=packet(both.w,0,60,0),second=packet(both.w,1,60,0);
	CHECK(both.w.step_clock_work_plan(action_seconds,60,0,both.w.tick,{first,second}),"two original pools publish through one native step");
	close(both.w.formations[0].fatigue,40+1.0/18.0,"first denominator remains original count3");
	close(both.w.formations[1].fatigue,60+1.0/6.0,"second denominator remains original count1");
}

static void original_station_rest_release() {
	Fixture fixture;auto &w=fixture.w;
	w.formations[0].fatigue=80;w.formations[0].fatigue_rest=30;
	// Actual native arrived-station state retained by original WorkTeam.
	w.escort_mode[1]=5;w.escort_goal[1]=-1;
	CHECK(w.step_clock(action_seconds,60,0),"original native REST step with retained station hold");
	close(w.formations[0].fatigue,80,"nonzero original escort mode prevents all-pool rest recovery");
	close(w.formations[0].fatigue_rest,0,"retained station hold resets original rest delay");
	w.cancel_siege_step(1);
	CHECK(w.escort_mode[1]==0,"original arrived-work cancellation releases the native busy state");
	w.formations[0].fatigue_rest=30;
	CHECK(w.step_clock(action_seconds,60,0),"original REST resumes after actual station cancellation");
	close(w.formations[0].fatigue,80-1.0/3.0,"original safe recovery works once no real activity remains");
}

static void actual_native_rest_endpoints() {
	Fixture fixture;auto &w=fixture.w;
	w.formations[0].fatigue=80;w.formations[0].fatigue_rest=12;
	const auto original=w.save();
	close(w.work_fatigue_rest_limit(0,50,100000,0),18,"readonly native limit clips original remaining30 rest delay");
	CHECK(w.save()==original,"rest query does not consume original inputs or mutate clocks/HP/pool");
	CHECK(w.step_clock(action_seconds,18,0),"true original World consumes clipped rest-delay interval");
	close(w.formations[0].fatigue,80,"original delay has no free recovery");
	const double to50=w.work_fatigue_rest_limit(0,50,100000,0);
	close(to50,5400,"native original recovery reaches exact50 boundary");
	CHECK(w.step_clock(action_seconds,to50,0),"true original World consumes native50 prefix");
	close(w.formations[0].fatigue,50,"native boundary is exact without estimated rate or tiny-segment drift");
	Fixture housing;auto &h=housing.w;
	CHECK(h.step_clock(action_seconds,0,0),"original zero-time phase initializes current grid for true housing eligibility");
	h.formations[0].fatigue=80;h.formations[0].fatigue_rest=30;
	for(int i:h.formations[0].members) CHECK(h.set_housing_attendance_input(i,h.cell[i]),"original housing attendance accepted actual body/cell");
	CHECK(h.set_housing_recovery_input(0,1.25),"original housing multiplier input accepted");
	close(h.work_fatigue_rest_limit(0,50,100000,0),4320,"native query uses exact original qualified housing bonus");
	CHECK(h.step_clock(action_seconds,4320,0),"original World consumes qualified boosted rest");
	close(h.formations[0].fatigue,50,"boosted50 endpoint matches actual original fatigue stage");
	Fixture held;auto &b=held.w;b.formations[0].fatigue=80;b.formations[0].fatigue_rest=30;
	b.escort_mode[1]=5;b.escort_goal[1]=-1;
	close(b.work_fatigue_rest_limit(0,50,100000,0),100000,"actual original busy work station does not claim a recovery endpoint");
	b.cancel_siege_step(1);
	close(b.work_fatigue_rest_limit(0,50,100000,0),5400,"true original station cancellation restores exact recovery endpoint");
	b.running[1]=1;
	close(b.work_fatigue_rest_limit(0,50,100000,0),100000,"true current native RUN suppresses idle endpoint");
	CHECK(std::isnan(b.work_fatigue_rest_limit(0,-1,100000,0)),"invalid recovery target is rejected finitely");
}

int main() {
	actual_shared_step();rejection_is_atomic();partial_effort_endpoints_and_persistence();original_station_rest_release();actual_native_rest_endpoints();
	std::printf("NATIVE_WORK_FATIGUE_PLAN_%s checks=%d failures=%d; actual World pools, original shared step, CAS batch, RUN once, uncovered recovery, true partial effort, replay and save parity; no Lab/full-provider acceptance\n",failures?"FAIL":"PASS",checks,failures);
	return failures?1:0;
}
