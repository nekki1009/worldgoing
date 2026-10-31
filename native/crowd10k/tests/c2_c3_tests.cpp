// C2/C3 contracts, malformed-state rejection and bounded deterministic mutation fuzz.
#ifdef _WIN32
#define NOMINMAX
#include <windows.h>
#undef small
#endif
#include "../src/crowd_core.hpp"
#include "../src/crowd_c_api.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <functional>
#include <fstream>
#include <iterator>
#include <limits>
#include <random>
#include <algorithm>
using namespace wg;
static int checks=0, failures=0;
#define REQUIRE(c) do { ++checks; if(!(c)) { ++failures; std::fprintf(stderr,"FAIL line %d: %s\n",__LINE__,#c); } } while(false)
namespace wg {
struct WorldTestAccess {
 static void corrupt(World &w,int which) {
  switch(which) {
  case 0:w.rescued_by_[0]=999;break;case 1:w.capturing_by_[0]=999;break;
  case 2:w.rescuers_.push_back(999);break;case 3:w.capturers_.push_back(999);break;case 4:w.captives_.push_back(999);break;
  case 5:w.slot_tx_.pop_back();break;case 6:w.slot_ty_.pop_back();break;case 7:w.slot_clip_[0]=NAN;break;
  case 8:w.lag_acc_.pop_back();break;case 9:w.lag_cnt_.pop_back();break;case 10:w.attackers_.pop_back();break;case 11:w.touch_.pop_back();break;
  case 12:w.hostile_.pop_back();break;
  case 13:w.fields_.push_back(FlowField{});w.fields_.back().goal=999;w.fields_.back().dir.push_back(1);break;
  case 14:w.field_queue_.push_back(999);break;
  case 15:w.fields_.push_back(FlowField{});w.field_queue_.push_back((int)w.fields_.size()-1);break;
  case 16:w.fields_.push_back(FlowField{});w.formations[0].field=(int)w.fields_.size()-1;break;
  }
 }
 static void compact(World &w) { for(auto &f:w.formations) w.compact_slots(f); }
 static bool line_clear(World &w,rules::Cell source,rules::Cell target) { std::vector<rules::Cell> cells;return w.ranged_line_clear(source,target,cells); }
 static bool friendly_clear(World &w,rules::Cell source,rules::Cell target,int faction) {w.build_hash();std::vector<rules::Cell> cells;return w.friendly_clear(source,target,faction,cells);}
 static void release_shot(World &w,int shooter,int target) {w.fire_buf_[0].push_back({shooter,target});w.ranged_commit();w.fire_buf_[0].clear();}
 static void arrive_shots(World &w,float seconds) {w.build_hash();w.projectiles_advance(seconds);}
};
}
static void setup(World &w,int count=5) {
 w.terrain.allocate(12,12);w.cfg.ai=false;w.cfg.auto_capture=false;w.cfg.bleed_per_game_hour=0;
 int a=w.add_formation(0,3.5f,5.5f,0,3,0.8f,T_MELEE,30);
 int b=w.add_formation(2,8.5f,5.5f,kPi,1,1,T_MELEE,30);
 rules::Equip eq;eq.family=rules::F_LONGSWORD;eq.material=rules::M_IRON;
 for(int i=0;i<count;++i) w.add_soldier(a,eq,i==0?R_CAPTAIN:R_REGULAR,100+i);
 w.add_soldier(b,eq,R_CAPTAIN,200);w.finalize();
 for(auto &f:w.formations) f.ai_enabled=false;
 w.combat_left=100;w.events.clear();
}
static void valid(const World &w) {
 std::string error;
 if(!w.validate(&error)) { std::fprintf(stderr,"INVALID: %s\n",error.c_str()); std::exit(3); }
}
static void step(World &w,float dt=1.f/30.f) { REQUIRE(w.step(dt));valid(w); }
static void continuation(World &w) {
 valid(w);World copy(1);REQUIRE(copy.load(w.save()));REQUIRE(copy.state_hash()==w.state_hash());
 for(int i=0;i<60;++i) {step(w);step(copy);} REQUIRE(copy.state_hash()==w.state_hash());
}
static void orders() {
 World w(1);setup(w);auto reject=[&](int expected,int f,int k,float x,float y,double a) {auto h=w.state_hash();REQUIRE(w.host_order(f,k,x,y,a)==expected);REQUIRE(w.state_hash()==h);};
 reject(BAD_FORMATION,-1,0,0,0,0);reject(BAD_FORMATION,999,0,0,0,0);
 w.formations[0].no_orders=true;w.formations[0].ai_enabled=true;reject(NO_ORDERS,0,99,0,0,0);
 w.formations[0].no_orders=false;reject(NOT_OWNER,0,99,0,0,0);w.formations[0].ai_enabled=false;
 reject(BAD_ARGS,0,99,0,0,0);reject(BAD_ARGS,0,1,NAN,0,0);reject(BAD_ARGS,0,2,0,0,INFINITY);reject(BAD_ARGS,0,1,4,4,1e300);
 reject(NOT_ROUTED,0,3,-50,0,0);reject(NO_TARGET,0,2,0,0,999);reject(NO_TARGET,0,4,0,0,-1);
 reject(BLOCKED,0,1,-1,5,0);w.terrain.static_blocked[w.terrain.idx(5,5)]=1;w.terrain.build_edges();reject(BLOCKED,0,1,5.5f,5.5f,0);
 for(int y=0;y<12;++y)w.terrain.static_blocked[w.terrain.idx(6,y)]=1;w.terrain.build_edges();reject(BLOCKED,0,1,10,5,0);
 w.formations[0].routed=true;reject(ROUTED,0,1,-1,5,0);reject(ROUTED,0,2,0,0,999);reject(ROUTED,0,4,0,0,999);
 REQUIRE(w.host_order(0,3,1,5,0)==OK);REQUIRE(w.host_order(0,0,0,0,0)==OK);
 for(float dt:{0.f,-1.f,1.f,INFINITY,NAN}) {auto h=w.state_hash();REQUIRE(!w.step(dt));REQUIRE(!w.step_clock(dt,1,0));REQUIRE(w.state_hash()==h);}
 auto h=w.state_hash();REQUIRE(!w.step_clock(.1f,NAN,0));REQUIRE(!w.step_clock(.1f,1,INFINITY));REQUIRE(w.state_hash()==h);
 // All corners and side midpoints still use clipped internal rout commands.
 for(auto p:std::vector<std::pair<float,float>>{{.5f,.5f},{11.5f,.5f},{.5f,11.5f},{11.5f,11.5f},{.5f,6.f},{11.5f,6.f},{6.f,.5f},{6.f,11.5f}}) {
  World z(1);setup(z,1);auto &f=z.formations[0];f.cx=f.goal_x=f.origin_x=p.first;f.cy=f.goal_y=f.origin_y=p.second;f.morale=10;
  step(z);REQUIRE(f.routed && z.stats.routs==1 && (f.order==Order::RETREAT || (f.order==Order::HOLD && f.arrived)));REQUIRE(f.goal_x>=0 && f.goal_x<12 && f.goal_y>=0 && f.goal_y<12);
 }
}
static void retreat_contract() {
 auto build=[](World &w,float ax,float ay,float ex,float ey,int obstacle) {
  w.terrain.allocate(32,32);w.cfg.ai=false;w.cfg.auto_capture=false;w.cfg.rescue_seek_cells=0;w.combat_left=1e9;
  if(obstacle==1)for(int y=0;y<32;++y)w.terrain.static_blocked[w.terrain.idx(10,y)]=1;
  if(obstacle==2)for(int y=14;y<=16;++y)for(int x=14;x<=16;++x)if(x!=15 || y!=15)w.terrain.static_blocked[w.terrain.idx(x,y)]=1;
  rules::Equip eq;
  int f=w.add_formation(0,ax,ay,0,1,1,T_MELEE,0),e=w.add_formation(1,ex,ey,kPi,1,1,T_MELEE,0);
  w.add_soldier(f,eq,R_CAPTAIN,1101);w.add_soldier(e,eq,R_CAPTAIN,2202);w.finalize();
  for(auto &q:w.formations)q.ai_enabled=false;
 };
 auto distance=[](const World&w){const auto&a=w.formations[0];const auto&b=w.formations[1];return std::hypot(a.cx-b.cx,a.cy-b.cy);};
 {World w(1);build(w,15.5f,16.5f,21.5f,16.5f,0);auto state=w.get_formation_state(0);state.routed=1;state.morale=10;w.set_formation_state(0,state);
  const float before=distance(w);const auto routs=w.stats.routs;w.events.clear();
  REQUIRE(w.host_order(0,3,21.5f,16.5f,0)==OK); // Host coordinates deliberately point toward the foe.
  REQUIRE(w.formations[0].goal_x<w.formations[0].cx && w.formations[0].order==Order::RETREAT);
  for(int n=0;n<300;++n)step(w);
  REQUIRE(distance(w)-before>=5);REQUIRE(w.stats.routs==routs);
  for(const Event&e:w.events)REQUIRE(e.kind!=EV_ROUT); // Re-ordering an already routed unit is not a second rout.
  const auto h=w.state_hash();REQUIRE(w.host_order(0,1,10,10,0)==ROUTED);REQUIRE(w.state_hash()==h);
  std::printf("RETREAT host distance_gain=%.6f goal=%.3f,%.3f\n",distance(w)-before,w.formations[0].goal_x,w.formations[0].goal_y);
 }
 int edge=0;
 for(auto p:std::vector<std::pair<float,float>>{{3.5f,3.5f},{28.5f,3.5f},{3.5f,28.5f},{28.5f,28.5f},{3.5f,16.5f},{28.5f,16.5f},{16.5f,3.5f},{16.5f,28.5f}}) {
  World w(1);build(w,p.first,p.second,16.5f,16.5f,0);const float before=distance(w);w.formations[0].morale=10;
  step(w);REQUIRE(w.formations[0].routed && w.formations[0].order==Order::RETREAT && w.stats.routs==1);
  REQUIRE(w.formations[0].goal_x>=.5f && w.formations[0].goal_x<=31.5f && w.formations[0].goal_y>=.5f && w.formations[0].goal_y<=31.5f);
  for(int n=1;n<300;++n)step(w);
  REQUIRE(distance(w)-before>=2.5f);REQUIRE(w.stats.illegal_step==0 && w.stats.illegal_cell==0);
  std::printf("RETREAT edge=%d distance_gain=%.6f final=%.3f,%.3f\n",edge++,distance(w)-before,w.formations[0].cx,w.formations[0].cy);
 }
 for(int obstacle:{1,2}) {
  World w(1);build(w,15.5f,obstacle==1?16.5f:15.5f,21.5f,16.5f,obstacle);const float before=distance(w);w.formations[0].morale=10;
  step(w);const auto &f=w.formations[0];REQUIRE(f.routed && w.stats.routs==1);
  REQUIRE(f.goal_x>=11.5f); // The destination must remain in the same reachable component.
  for(int n=1;n<300;++n)step(w);
  if(obstacle==1)REQUIRE(distance(w)-before>=3.5f);
  else REQUIRE(std::abs(distance(w)-before)<1e-6f && f.goal_x==15.5f && f.goal_y==15.5f && f.arrived && f.order==Order::HOLD);
  REQUIRE(w.stats.illegal_step==0 && w.stats.illegal_cell==0);
  std::printf("RETREAT obstacle=%d distance_gain=%.6f final=%.3f,%.3f goal=%.3f,%.3f\n",obstacle,distance(w)-before,f.cx,f.cy,f.goal_x,f.goal_y);
 }
}
static void c_api_order_codes() {
 World w(1);setup(w);
 auto check=[&](int expected,int f,int kind,float x,float y,double value){
  auto blob=w.save();auto before=w.state_hash();wg_crowd*c=wg_crowd_create(1,0);REQUIRE(c!=nullptr);if(!c)return;
  REQUIRE(wg_crowd_load(c,blob.data(),(int64_t)blob.size())==1);const auto cbefore=wg_crowd_state_hash(c);REQUIRE(cbefore==before);
  REQUIRE(w.host_order(f,kind,x,y,value)==expected);REQUIRE(wg_crowd_host_order(c,f,kind,x,y,value)==expected);
  REQUIRE(w.state_hash()==before && wg_crowd_state_hash(c)==cbefore);wg_crowd_destroy(c);
 };
 check(BAD_FORMATION,-1,0,0,0,0);check(BAD_FORMATION,INT_MAX,0,0,0,0);
 for(double target:{-1.0,(double)w.soldier_count(),(double)INT_MAX}){check(NO_TARGET,0,2,0,0,target);check(NO_TARGET,0,4,0,0,target);}
 for(float v:{NAN,INFINITY,-INFINITY}){check(BAD_ARGS,0,1,v,5,0);check(BAD_ARGS,0,1,5,v,0);check(BAD_ARGS,0,1,5,5,v);}
 check(BLOCKED,0,1,-1,5,0);check(BLOCKED,0,1,12,5,0);check(NOT_ROUTED,0,3,1,5,0);
 w.formations[0].morale=10;check(NOT_ROUTED,0,3,1,5,0);w.formations[0].morale=100;
 w.formations[0].ai_enabled=true;check(NOT_OWNER,0,0,0,0,0);w.formations[0].no_orders=true;check(NO_ORDERS,0,0,0,0,0);
 w.formations[0].ai_enabled=false;w.formations[0].no_orders=false;w.formations[0].routed=true;check(ROUTED,0,1,1,5,0);
 w.formations[0].routed=false;w.terrain.static_blocked[w.terrain.idx(5,5)]=1;w.terrain.build_edges();check(BLOCKED,0,1,5.5f,5.5f,0);
 World range_world(1);range_world.terrain.allocate(48,48);rules::Equip eq;
 int a=range_world.add_formation(0,4.5f,20.5f,0,1,1,T_MELEE,0),b=range_world.add_formation(1,30.5f,20.5f,kPi,1,1,T_MELEE,0);
 range_world.add_soldier(a,eq,R_CAPTAIN,7001);range_world.add_soldier(b,eq,R_CAPTAIN,7009);range_world.finalize();range_world.formations[a].ai_enabled=false;
 REQUIRE(w.load(range_world.save()));check(NO_TARGET,0,4,0,0,1); // A valid target 26 cells away is outside PURSUE range.
 std::printf("ORDER_C_API direct code/hash equivalence for complete malformed-index/coordinate/ownership matrix and PURSUE range\n");
}
static void imports_append_sustain() {
 World w(1);setup(w);
 rules::Equip swapped;swapped.family=rules::F_BOW;REQUIRE(w.set_soldier_equip(1,swapped));REQUIRE(w.troop[1]==T_BOW);
 swapped.family=rules::F_CROSSBOW;REQUIRE(w.set_soldier_equip(1,swapped));REQUIRE(w.troop[1]==T_CROSSBOW);
 swapped.family=rules::F_LONGSWORD;REQUIRE(w.set_soldier_equip(1,swapped));REQUIRE(w.troop[1]==T_MELEE);
 auto st=w.get_soldier_state(1);st.hp=77;st.stun=19;st.grace=1.5;st.ko=32;st.getup=.6;st.stagger=.4;st.escape_t=7;st.ammo=9;st.role=R_OFFICER;st.tactics=41;st.leadership=52;st.coach=63;st.x=4.25f;st.y=4.75f;st.facing=.8f;st.exch_cd=.3;st.ranged_cd=.7;st.skill_cd=9;st.knock_t=.1;st.act_t=2;
 w.set_soldier_state(1,st);auto out=w.get_soldier_state(1);
 REQUIRE(out.hp==77 && out.escape_t==7 && out.ammo==9 && out.role==R_OFFICER && out.x==4.25f && out.ranged_cd==.7 && out.coach==63);
 auto fs=w.get_formation_state(0);fs.morale=61;fs.fatigue=21;fs.fatigue_rest=8;fs.rally_rest=37;fs.training=140;fs.order=(int)Order::PURSUE;fs.target_person=200;fs.pursuit_left=11;fs.order_delay=-.01;fs.goal_x=8;fs.goal_y=5;fs.origin_x=2;fs.origin_y=3;fs.ai_enabled=0;
 w.set_formation_state(0,fs);auto fo=w.get_formation_state(0);REQUIRE(fo.training==140 && fo.order==(int)Order::PURSUE && fo.target_person==200 && fo.pursuit_left==11 && fo.order_delay==-.01 && fo.current_person==100);
 valid(w);const auto before=w.get_formation_state(0);const auto oldpos=w.px[0];
 int f=w.add_formation(7,9,9,0,1,1,T_MELEE,0);rules::Equip empty;int i=w.add_soldier(f,empty,R_CAPTAIN,9001);w.formations[f].no_orders=true;w.formations[f].host_center=true;w.formations[f].ai_enabled=false;
 REQUIRE(w.formations[f].slot_count==1 && w.formations[f].roster==1 && w.formations[f].fatigue_count==1 && w.cell[i]>=0);
 REQUIRE(w.px[0]==oldpos && w.formations[0].order==(Order)before.order);valid(w);
 World restored(1);REQUIRE(restored.load(w.save()));REQUIRE(restored.state_hash()==w.state_hash());
 w.set_host_control(0,true);w.set_host_control(i,true);REQUIRE(!w.host_ctl[0] && w.host_ctl[i]);
 w.host_input(i,.2f,0,false,false);step(w);REQUIRE(w.formations[0].order!=Order::HOLD);REQUIRE(w.host_order(f,0,0,0,0)==NO_ORDERS);
 continuation(w);
 for(int initially_routed:{0,1})for(int fed:{0,1}) {
  World z(1);setup(z,1);z.set_hostile(0,2,false);z.formations[0].morale=60;z.formations[0].routed=initially_routed!=0;z.formations[0].rally_rest=0;
  for(int n=0;n<120;++n) {REQUIRE(z.set_sustain_input(0,fed!=0,fed?0:-2.0/60));REQUIRE(z.step_clock(1.f/30,60,0));valid(z);}
  if(fed) REQUIRE(std::abs(z.formations[0].morale-70)<.001 && !z.formations[0].routed && z.formations[0].rally_rest==rules::RALLY_REST_SECONDS);
  else REQUIRE(std::abs(z.formations[0].morale-56)<.001 && z.formations[0].routed==(initially_routed!=0) && z.formations[0].rally_rest==0);
  std::printf("RALLY_CONTROL initially_routed=%d fully_fed=%d morale=%.9f rally_rest=%.9f\n",initially_routed,fed,z.formations[0].morale,z.formations[0].rally_rest);
  if(fed){REQUIRE(z.set_sustain_input(0,false,0));REQUIRE(z.step_clock(1.f/30,1,0));REQUIRE(z.formations[0].rally_rest==0);}
 }
}
static void append_after_death_roundtrip() {
 // D6: a new-faction heir is appended after the controlled person's death and
 // after a real path field has been built; loading is not another game event.
 for(int threads:{1,4}) {
  World w(threads);setup(w);w.set_hostile(0,2,false);w.set_host_control(0,true);
  REQUIRE(w.host_order(0,1,4.5f,8.5f,0)==OK);
  for(int t=0;t<20;++t)step(w);
  REQUIRE(w.stats.fields_built>0);REQUIRE(w.apply_environment_damage(0,200));step(w);
  int f=w.add_formation(7,9,9,0,1,1,T_MELEE,68);rules::Equip eq;
  int heir=w.add_soldier(f,eq,R_CAPTAIN,9001);auto sf=w.get_formation_state(f);
  sf.no_orders=1;sf.host_center=1;sf.ai_enabled=0;sf.fatigue=17;w.set_formation_state(f,sf);w.set_host_control(heir,true);
  valid(w);const auto blob=w.save();const auto hash=w.state_hash();const auto stats_before=w.stats;
  World copy(threads==1?4:1);REQUIRE(copy.load(blob));valid(copy);
  REQUIRE(copy.state_hash()==hash);REQUIRE(copy.stats.fields_built==stats_before.fields_built);REQUIRE(copy.save()==blob);
  REQUIRE(w.save()==blob); // No hidden source-side normalization to make the check pass.
  for(int t=0;t<120;++t){step(w);step(copy);REQUIRE(w.state_hash()==copy.state_hash());}
 }
}
static void replay_blob(const char *path,uint64_t expected) {
 std::ifstream in(path,std::ios::binary);REQUIRE(bool(in));if(!in)return;
 const std::vector<uint8_t> blob((std::istreambuf_iterator<char>(in)),std::istreambuf_iterator<char>());
 REQUIRE(!blob.empty() && blob.size()<=16*1024*1024);if(blob.empty() || blob.size()>16*1024*1024)return;
 World a(1),c(4);const bool a_loaded=a.load(blob),c_loaded=c.load(blob);REQUIRE(a_loaded && c_loaded);if(!a_loaded || !c_loaded)return;
 valid(a);valid(c);const auto again=a.save();size_t first=0;while(first<blob.size() && first<again.size() && blob[first]==again[first])++first;
 std::printf("D6_BLOB bytes=%zu first_difference=%lld fields_built=%llu hash=%llu\n",blob.size(),first==blob.size() && first==again.size()?-1LL:(long long)first,(unsigned long long)a.stats.fields_built,(unsigned long long)a.state_hash());
 REQUIRE(again==blob);REQUIRE(c.save()==blob);REQUIRE(a.state_hash()==c.state_hash());if(expected)REQUIRE(a.state_hash()==expected);
 for(int t=0;t<300;++t){step(a);step(c);REQUIRE(a.state_hash()==c.state_hash());}
 std::printf("D6_BLOB one_four_thread_continuation=300 hash=%llu\n",(unsigned long long)a.state_hash());
}
static void hunger() {
 // N=5, fixed eligible captain/leadership. Fourth mode is an actual N-1 roster.
 double loss[4]{}, reduction[4]{};
 for(int mode=0;mode<4;++mode) {
  World w(1);setup(w,mode==3?4:5);w.formations[0].morale=80;w.ability[0].leadership=100;
  if(mode==3)w.person_id[1]=104; // the roster is 100,104,102,103: A=101 was never deployed.
  if(mode==0 || mode==1)REQUIRE(w.apply_environment_damage(1,200));
  if(mode!=1)w.apply_contact(2,200,0);
  if(mode==2)REQUIRE(w.hp[1]>0 && w.life_ck[1]==0); // Required control: A is still alive.
  if(mode==0)REQUIRE(w.life_ck[1]==2 && w.life_ck[2]==0); // environment must not hide B's casualty.
  reduction[mode]=w.command_effect(0,1,.25);
  const int denominator=mode==2?5:4;
  const double expected=mode==1?0:40.0/denominator*(1-reduction[mode]);
  REQUIRE(w.step_clock(1.f/30,0,100));valid(w);loss[mode]=80-w.formations[0].morale;
  REQUIRE(std::abs(loss[mode]-expected)<1e-8);
  const int expected_deaths=mode==0?2:1;int deaths=0;
  for(const Event &e:w.events)if(e.kind==EV_DEATH)++deaths;
  REQUIRE(deaths==expected_deaths && w.stats.deaths==(uint64_t)expected_deaths);
  std::printf("HUNGER mode=%d N=%d denominator=%d reduction=%.9f loss=%.9f expected=%.9f deaths=%d\n",mode,mode==3?4:5,denominator,reduction[mode],loss[mode],expected,deaths);
 }
 REQUIRE(std::abs(loss[0]-loss[3])<1e-8 && loss[1]==0 && loss[0]>loss[2]);
 REQUIRE(reduction[0]==reduction[1] && reduction[1]==reduction[2] && reduction[2]==reduction[3]);
 World w(1);setup(w);auto st=w.get_soldier_state(1);st.captive=1;st.captor_person=200;st.bandaged=1;st.ko=100;w.set_soldier_state(1,st);w.events.clear();double clock=w.combat_left;
 REQUIRE(w.apply_environment_damage(1,1));REQUIRE(w.bandaged[1] && w.captive[1] && w.events.empty() && w.combat_left==clock);
 REQUIRE(w.apply_environment_damage(1,100));REQUIRE(w.hp[1]==0 && !w.captive[1] && w.stats.deaths==1 && w.events.size()==1 && w.events[0].kind==EV_DEATH && w.events[0].other==200 && w.life_ck[1]==2 && w.combat_left==clock);
 // Nonlethal environment damage leaves an active rescue alone.
 w.rescue_of[2]=3;w.act_t[2]=.75;REQUIRE(w.apply_environment_damage(2,1));REQUIRE(w.rescue_of[2]==3 && w.act_t[2]==.75);
}
static void death_fatigue_event_contract() {
 World w(1);setup(w,3);auto &f=w.formations[0];const int count=f.fatigue_count;
 f.fatigue=51.25;f.fatigue_rest=7.5;
 w.apply_contact(1,100,0);REQUIRE(w.hp[1]==0 && f.fatigue_count==count-1);
 REQUIRE(w.events.size()==1 && w.events[0].kind==EV_DEATH && w.events[0].person==101);
 REQUIRE(w.events[0].fatigue==51.25 && w.events[0].fatigue_rest==7.5);
 // Another real death in the same formation retains its own moment, not the later live pool.
 f.fatigue=61.5;f.fatigue_rest=11.25;
 REQUIRE(w.apply_siege_contact(2,100,35,0));
 REQUIRE(w.hp[2]==0 && f.fatigue_count==count-2 && w.events.size()==2);
 REQUIRE(w.events[0].fatigue==51.25 && w.events[0].fatigue_rest==7.5);
 REQUIRE(w.events[1].fatigue==61.5 && w.events[1].fatigue_rest==11.25);
 w.apply_contact(0,0,100);REQUIRE(w.events.size()==3 && w.events[2].kind==EV_KO);
 REQUIRE(w.events[2].fatigue==0 && w.events[2].fatigue_rest==0);valid(w);
 const auto bytes=w.save();const auto hash=w.state_hash();World loaded(1);
 REQUIRE(loaded.load(bytes) && loaded.save()==bytes && loaded.state_hash()==hash);
 REQUIRE(loaded.events[0].fatigue==51.25 && loaded.events[1].fatigue_rest==11.25);
 auto rejects=[&](int event,bool rest,double value) {
  World bad(1);REQUIRE(bad.load(bytes));
  if(rest)bad.events[event].fatigue_rest=value;else bad.events[event].fatigue=value;
  REQUIRE(!bad.validate());const auto original=loaded.save();const auto original_hash=loaded.state_hash();
  REQUIRE(!loaded.load(bad.save()));REQUIRE(loaded.save()==original && loaded.state_hash()==original_hash);
 };
 for(double value:{-1.0,100.0001,std::numeric_limits<double>::infinity(),std::numeric_limits<double>::quiet_NaN()})rejects(0,false,value);
 for(double value:{-1.0,30.0001,std::numeric_limits<double>::infinity(),std::numeric_limits<double>::quiet_NaN()})rejects(0,true,value);
 rejects(2,false,1);rejects(2,true,1);
 World changed(1);REQUIRE(changed.load(bytes));changed.events[0].fatigue=51.5;
 REQUIRE(changed.validate() && changed.state_hash()!=hash); // Both doubles feed the original hash.
 changed.events[0].fatigue=51.25;changed.events[0].fatigue_rest=8;
 REQUIRE(changed.validate() && changed.state_hash()!=hash);
 World wrong(1);REQUIRE(wrong.load(bytes));wrong.events[0].person=999;
 REQUIRE(!wrong.validate() && !loaded.load(wrong.save()) && loaded.state_hash()==hash);
 REQUIRE(wrong.load(bytes));wrong.events[0].formation=1;
 REQUIRE(!wrong.validate() && !loaded.load(wrong.save()) && loaded.state_hash()==hash);
 std::printf("DEATH_FATIGUE_EVENT_PASS ordinary + siege deaths, same-formation count, exact event values, pending-queue raw/hash roundtrip and atomic malformed rejection\n");
}
static void safe_load() {
 World base(1);setup(base);const auto bytes=base.save();World live(1);setup(live);auto hash=live.state_hash();
 int rejected_cases=0;
 auto bad=[&](const std::vector<uint8_t>&v) {REQUIRE(!live.load(v));REQUIRE(live.state_hash()==hash);++rejected_cases;};
 bad({});bad(std::vector<uint8_t>(bytes.begin(),bytes.begin()+bytes.size()/2));auto version=bytes;version[2]='9';bad(version);version[2]='0';version[3]='1';bad(version);
 auto corrupt=[&](const std::function<void(World&)>&f) {World z(1);REQUIRE(z.load(bytes));f(z);std::string why;REQUIRE(!z.validate(&why,false));std::printf("REJECT[%d] %s\n",rejected_cases+1,why.c_str());bad(z.save());};
 corrupt([](World&w){w.hp.pop_back();});corrupt([](World&w){w.terrain.w=13;});corrupt([](World&w){w.form[0]=-1;});
 for(int which=0;which<8;++which)corrupt([=](World&w){std::vector<int32_t>*v[]={&w.target,&w.captor,&w.rescue_of,&w.capture_of,&w.enc_target,&w.cell,&w.form,&w.slot};(*v[which])[0]=999;});
 for(int which=0;which<17;++which)corrupt([=](World&w){WorldTestAccess::corrupt(w,which);});
 corrupt([](World&w){w.formations[0].members.push_back(w.formations[1].members[0]);});corrupt([](World&w){w.formations[0].members.erase(w.formations[0].members.begin());});
 for(int which=0;which<5;++which)corrupt([=](World&w){int*v[]={&w.cfg.chunk,&w.cfg.los_period,&w.cfg.contact_period,&w.cfg.los_max_cells,&w.cfg.max_fields_per_step};*v[which]=0;});
 corrupt([](World&w){w.px[0]=NAN;});corrupt([](World&w){w.hp[0]=INFINITY;});corrupt([](World&w){w.cfg.radius=NAN;});corrupt([](World&w){w.state[0]=255;});corrupt([](World&w){w.captive[0]=2;});
 corrupt([](World&w){w.formations[0].cx=NAN;});corrupt([](World&w){w.formations[0].goal_x=12;});corrupt([](World&w){w.formations[0].morale=150;});
 corrupt([](World&w){w.terrain.edge_ok[0]|=1<<N;});corrupt([](World&w){w.team[0]=255;});corrupt([](World&w){w.formations[0].formal_cmd=w.formations[1].members[0];});
 for(int k=0;k<6;++k)corrupt([=](World&w){int*idx[]={&w.formations[0].formal_cmd,&w.formations[0].acting_cmd,&w.formations[0].current_cmd,&w.formations[0].target_person,&w.formations[0].ai_target,&w.formations[0].field};*idx[k]=999;});
 corrupt([](World&w){w.formations[0].officer_order.push_back(999);});
 corrupt([](World&w){w.formations[0].members.push_back(0);});corrupt([](World&w){w.slot[1]=w.slot[0];});
 corrupt([](World&w){w.role[0]=255;});corrupt([](World&w){w.troop[0]=255;});corrupt([](World&w){w.skill[0]=255;});
 corrupt([](World&w){w.formations[0].order=(Order)255;});corrupt([](World&w){w.formations[0].troop=(Troop)255;});corrupt([](World&w){w.formations[0].ai_status=(AIStatus)255;});
 corrupt([](World&w){w.equip[0].family=255;});corrupt([](World&w){w.equip[0].material=255;});corrupt([](World&w){w.equip[0].armor=255;});
 corrupt([](World&w){Event e;e.kind=255;w.events.push_back(e);});
 corrupt([](World&w){Projectile p;p.shooter=999;w.projectiles.push_back(p);});
 corrupt([](World&w){w.time=NAN;});corrupt([](World&w){w.game_dt=INFINITY;});corrupt([](World&w){w.combat_left=-1;});
 corrupt([](World&w){w.cfg.encircle_budget=-1;});
 corrupt([](World&w){w.prison_id.pop_back();});
 corrupt([](World&w){w.prison_id[0]=1;});
 corrupt([](World&w){w.escort_mode[0]=4;}); // G10: held 3/5 (no goal) is saveable; 4 without a goal is not
 corrupt([](World&w){w.escort_goal[0]=20;});
 corrupt([](World&w){w.contact_revision.pop_back();});
 corrupt([](World&w){w.contact_revision[0]=-1;});

 // This suite validates the persisted KW06 schema; live Site purposes use
 // the same validator with its public allow_site_jobs contract instead.
 // Forge real old custody bytes, never the empty controlled-job save result.
 {
  World custody(1);setup(custody,1);auto person=custody.get_soldier_state(0);person.x=3.5f;person.y=5.5f;custody.set_soldier_state(0,person);
  REQUIRE(custody.order_escort_step(0,0,custody.terrain.idx(4,5)));
  std::string why;REQUIRE(custody.validate(&why,false));const auto genuine=custody.save();REQUIRE(!genuine.empty());
  World old_copy(1);REQUIRE(old_copy.load(genuine));REQUIRE(old_copy.escort_mode[0]==1 && old_copy.escort_goal[0]==custody.escort_goal[0]);
  std::vector<uint8_t> marker;const uint64_t n=custody.soldier_count();
  auto append=[&](const auto &value){const auto *p=reinterpret_cast<const uint8_t *>(&value);marker.insert(marker.end(),p,p+sizeof(value));};
  append(n);for(auto value:custody.prison_id)append(value);append(n);for(auto value:custody.escort_goal)append(value);append(n);for(auto value:custody.escort_mode)append(value);
  size_t matches=0,offset=0;for(size_t k=0;k+marker.size()<=genuine.size();++k)if(!std::memcmp(genuine.data()+k,marker.data(),marker.size())){++matches;offset=k;}
  REQUIRE(matches==1);
  if(matches==1)for(uint8_t mode:{uint8_t(3),uint8_t(4),uint8_t(5),uint8_t(6)}) {
   auto forged=genuine;forged[offset+marker.size()-custody.escort_mode.size()]=mode;
   REQUIRE(forged.size()==genuine.size() && !forged.empty());bad(forged);
  }
 }
 // Real admitted live Housing/Siege stable and KO pending references remain
 // valid without weakening the separate persisted-schema rejection.
 for(int siege=0;siege<2;++siege) {
  World job(1);setup(job,1);auto person=job.get_soldier_state(0);person.x=3.5f;person.y=5.5f;job.set_soldier_state(0,person);
  const int here=job.terrain.idx(3,5),next=job.terrain.idx(4,5);std::string why;
  REQUIRE(siege?job.order_siege_step(0,here):job.order_housing_step(0,here));REQUIRE(job.escort_goal[0]==-1);
  // G10 (Nekki 2026-10-30 A): an arrived, held step is saved and restored as held.
  REQUIRE(job.validate(&why));REQUIRE(job.validate(&why,false));
  {const auto held=job.save();REQUIRE(!held.empty());World back(1);REQUIRE(back.load(held));
   REQUIRE(back.escort_mode[0]==job.escort_mode[0] && back.escort_goal[0]==-1 && back.state_hash()==job.state_hash());}
  if(siege)job.cancel_siege_step(0);else job.cancel_housing_step(0);
  REQUIRE(siege?job.order_siege_step(0,next):job.order_housing_step(0,next));job.apply_contact(0,0,rules::STUN_LIMIT);
  REQUIRE(job.ko[0]>0 && job.escort_goal[0]==next && job.escort_mode[0]==(siege?6:4));
  REQUIRE(job.validate(&why));REQUIRE(!job.validate(&why,false));REQUIRE(job.save().empty());
 }

 auto corrupt_bool=[&](const std::function<void(World&)>&toggle) { World z(1);REQUIRE(z.load(bytes));toggle(z);auto other=z.save();size_t changed=bytes.size();for(size_t k=0;k<bytes.size();++k)if(bytes[k]!=other[k]){changed=k;break;}REQUIRE(changed<bytes.size());other=bytes;other[changed]=2;bad(other); };
 corrupt_bool([](World&w){w.cfg.ai=!w.cfg.ai;});corrupt_bool([](World&w){w.formations[0].arrived=!w.formations[0].arrived;});corrupt_bool([](World&w){w.equip[0].shield=!w.equip[0].shield;});
 // Locate the first terrain byte by changing height only; preceding uint64 is its vector length.
 World z(1);REQUIRE(z.load(bytes));z.terrain.height[0]=7;auto shifted=z.save();size_t offset=0;while(offset<bytes.size() && bytes[offset]==shifted[offset])++offset;REQUIRE(offset>=8);shifted=bytes;for(size_t k=offset-8;k<offset;++k)shifted[k]=255;bad(shifted);
 // Legal dead-member retention/removal, repeated -1 slots, and the two expired timers.
 for(int compact=0;compact<2;++compact) {World q(1);setup(q);q.apply_contact(1,1000,0);q.ko[2]=100;q.ko[3]=100;auto captive=q.get_soldier_state(4);captive.captive=1;captive.captor_person=200;q.set_soldier_state(4,captive);if(compact)WorldTestAccess::compact(q);valid(q);continuation(q);}
 World q(1);setup(q);q.order_move(0,4,4,0);q.formations[0].order_delay=.001;step(q);REQUIRE(q.formations[0].order_delay<0);continuation(q);
 World r(1);setup(r);r.order_pursue(0,5);r.formations[0].pursuit_left=.001;step(r);REQUIRE(r.formations[0].pursuit_left<0);continuation(r);
 std::printf("MALFORMED cases=%d all_rejected_transactionally\n",rejected_cases);
}
static void prison_contract() {
 World w(1);w.cfg.chunk=1;setup(w,1);w.cfg.rescue_seek_cells=0;
 auto guard=w.get_soldier_state(0);guard.x=5.5f;guard.y=5.5f;w.set_soldier_state(0,guard);
 auto inmate=w.get_soldier_state(1);inmate.x=4.5f;inmate.y=4.5f;inmate.captive=1;inmate.captor_person=w.person_id[0];w.set_soldier_state(1,inmate);
 const int slot=w.terrain.idx(5,4),contact=w.terrain.idx(5,5);
 const Order original_order=w.formations[0].order;const float goal_x=w.formations[0].goal_x,goal_y=w.formations[0].goal_y;
 auto unchanged=w.state_hash();REQUIRE(!w.admit_prison(1,0,7,slot,contact));REQUIRE(w.state_hash()==unchanged);
 REQUIRE(w.order_escort_step(0,0,contact));REQUIRE(w.order_escort_step(1,0,slot));
 REQUIRE(w.step_clock(1.f/30,0,0));valid(w);
 REQUIRE(w.prison_id[1]==0 && w.px[1]>4.5f && w.px[1]<5.5f);
 unchanged=w.state_hash();REQUIRE(!w.admit_prison(1,0,7,slot,contact));REQUIRE(w.state_hash()==unchanged);
 World copy(4);REQUIRE(copy.load(w.save()));
 for(int frame=0;frame<90;++frame) {REQUIRE(w.step_clock(1.f/30,0,0));REQUIRE(copy.step_clock(1.f/30,0,0));valid(w);valid(copy);}
 REQUIRE(w.state_hash()==copy.state_hash() && w.escort_goal[1]==-1 && w.escort_mode[1]==1);
 REQUIRE(std::abs(w.px[1]-5.5f)<.02f && w.vx[1]==0 && w.vy[1]==0);
 REQUIRE(w.formations[0].order==original_order && w.formations[0].goal_x==goal_x && w.formations[0].goal_y==goal_y);
 REQUIRE(w.admit_prison(1,0,7,slot,contact));valid(w);
 REQUIRE(w.get_soldier_state(1).prison_id==7 && w.captive[1] && w.escort_mode[1]==0);
 const float x=w.px[1],y=w.py[1];const double hp=w.hp[1];
 w.cancel_escort(0);guard=w.get_soldier_state(0);guard.x=x-.1f;guard.y=y;w.set_soldier_state(0,guard);
 REQUIRE(copy.load(w.save()));
 for(int frame=0;frame<120;++frame) {REQUIRE(w.step_clock(1.f/30,.5,0));REQUIRE(copy.step_clock(1.f/30,.5,0));valid(w);valid(copy);}
 REQUIRE(w.state_hash()==copy.state_hash() && w.px[1]==x && w.py[1]==y && w.hp[1]==hp && w.captive[1] && w.escape_t[1]==0);
 guard=w.get_soldier_state(0);guard.x=5.5f;guard.y=5.5f;w.set_soldier_state(0,guard);w.vx[0]=w.vy[0]=0;
 unchanged=w.state_hash();REQUIRE(!w.release_prison(1,0,8,contact,contact));REQUIRE(w.state_hash()==unchanged);
 const auto event_count=w.events.size();REQUIRE(w.release_prison(1,0,7,contact,contact));
 REQUIRE(!w.captive[1] && w.prison_id[1]==0 && w.hp[1]==hp && w.px[1]==x && w.py[1]==y && w.events.size()==event_count);
 // Cancelling a submitted edge lets it finish in native before ordinary orders resume.
 REQUIRE(w.order_escort_step(0,0,w.terrain.idx(6,5)));REQUIRE(w.step_clock(1.f/30,0,0));w.cancel_escort(0);
 REQUIRE(w.escort_mode[0]==2 && w.escort_goal[0]>=0);REQUIRE(copy.load(w.save()));
 for(int frame=0;frame<90;++frame) {REQUIRE(w.step_clock(1.f/30,0,0));REQUIRE(copy.step_clock(1.f/30,0,0));}
 REQUIRE(w.escort_mode[0]==0 && w.escort_goal[0]==-1 && w.state_hash()==copy.state_hash());
 const auto revision=w.contact_revision[1];
 w.apply_contact(1,0,0);REQUIRE(w.contact_revision[1]==revision);
 w.apply_contact(1,0,1);REQUIRE(w.contact_revision[1]==revision+1);
 REQUIRE(copy.load(w.save()) && copy.contact_revision[1]==w.contact_revision[1] && copy.state_hash()==w.state_hash());
 // Death clears only the native custody mirror; Site still settles original belongings.
 inmate=w.get_soldier_state(1);inmate.captive=1;inmate.captor_person=w.person_id[0];inmate.prison_id=7;w.set_soldier_state(1,inmate);
 REQUIRE(w.apply_environment_damage(1,200));REQUIRE(w.prison_id[1]==0 && !w.captive[1]);valid(w);
 std::printf("PRISON_NATIVE_PASS real escort edge, final-contact admission, fixed original body, 60 game seconds confined, scoped release, 1/4 thread save continuation, cancelled edge, death\n");
}
static void building_geometry_contract() {
 Terrain t;t.allocate(16,16);t.base_height.assign(256,0);
 t.height[t.idx(5,7)]=1;t.height[t.idx(5,6)]=2;t.height[t.idx(5,5)]=2;t.height[t.idx(6,5)]=2;
 t.ramp_edges[t.idx(5,8)]|=1<<N;t.ramp_edges[t.idx(5,7)]|=(1<<S)|(1<<N);t.ramp_edges[t.idx(5,6)]|=1<<S;
 t.height[t.idx(4,7)]=1;t.ramp_edges[t.idx(5,7)]|=1<<(W+4);t.build_edges();
 REQUIRE(!t.edge(6,6,N) && t.edge(5,8,N) && t.edge(5,7,N) && t.edge(5,6,N) && t.edge(5,5,E));
 REQUIRE(!t.edge(5,7,W) && !t.edge(4,7,E));
 REQUIRE(t.visual_lift(5.5f,7.5f)==48 && t.visual_lift(5.5f,6.5f)==96 && t.visual_lift(6.5f,5.5f)==96);
 REQUIRE(t.visual_lift(5.5f,7.25f)==60);
 const int source=t.idx(2,3),goal=t.idx(10,3),wall=t.idx(3,3),middle=t.idx(6,3);
 t.height[source]=2;t.height[wall]=2;
 REQUIRE(t.shot_cell_clear(source,goal,wall) && t.shot_cell_clear(source,goal,middle));
 REQUIRE(t.shot_height(source,goal,middle)==2.0);
 t.static_blocked[middle]=1;REQUIRE(!t.shot_cell_clear(source,goal,middle));t.static_blocked[middle]=0;
 t.height[middle]=2;REQUIRE(!t.shot_cell_clear(source,goal,middle));
 REQUIRE(!t.shot_cell_clear(-1,goal,middle));

 World w(1);w.cfg.chunk=1;setup(w);w.terrain.base_height.assign(144,0);
 w.order_move(0,3.5f,9.5f,0);REQUIRE(w.formations[0].order==Order::MOVE);
 auto ids=w.person_id;auto positions_x=w.px,positions_y=w.py;auto ammo=w.ammo;auto hp=w.hp;
 auto order=w.formations[0].order;auto rng=w.formations[0].rng;auto goal_x=w.formations[0].goal_x,goal_y=w.formations[0].goal_y;
 Terrain closed=w.terrain;closed.static_blocked[closed.idx(6,9)]=1;
 World four(4);REQUIRE(four.load(w.save()));
 REQUIRE(w.update_terrain(closed) && four.update_terrain(closed) && w.state_hash()==four.state_hash());
 REQUIRE(!w.terrain.walkable(6,9) && w.person_id==ids && w.px==positions_x && w.py==positions_y && w.hp==hp && w.ammo==ammo);
 REQUIRE(w.formations[0].order==order && w.formations[0].goal_x==goal_x && w.formations[0].goal_y==goal_y && w.formations[0].rng==rng);
 Terrain opened=closed;opened.static_blocked[opened.idx(6,9)]=0;
 REQUIRE(w.update_terrain(opened) && four.update_terrain(opened) && w.state_hash()==four.state_hash());
 auto before=w.state_hash();Terrain occupied=opened;occupied.static_blocked[w.cell[0]]=1;
 REQUIRE(!w.update_terrain(occupied) && w.state_hash()==before);
 Terrain raised_body=opened;raised_body.height[w.cell[0]]=2;
 REQUIRE(!w.update_terrain(raised_body) && w.state_hash()==before);
 Terrain wrong=opened;wrong.base_height.pop_back();REQUIRE(!w.update_terrain(wrong) && w.state_hash()==before);
 // Build an empty support, then explicitly place the original test row on it.
 Terrain support=opened;support.height[support.idx(6,7)]=2;
 REQUIRE(w.update_terrain(support));
 auto body=w.get_soldier_state(1);body.x=6.5f;body.y=7.5f;body.ammo=23;w.set_soldier_state(1,body);
 const auto item_family=w.equip[1].family,item_material=w.equip[1].material;
 const auto hit_revision=w.contact_revision[1];const float px=w.px[1],py=w.py[1];
 const double old_hp=w.hp[1];order=w.formations[0].order;rng=w.formations[0].rng;
 REQUIRE(four.load(w.save()));
 REQUIRE(w.update_terrain(opened) && four.update_terrain(opened));
 REQUIRE(w.px[1]==px && w.py[1]==py && w.nx[1]==px && w.ny[1]==py && w.vx[1]==0 && w.vy[1]==0);
 REQUIRE(w.hp[1]==old_hp-30 && w.ko[1]>0 && w.contact_revision[1]==hit_revision+1);
 REQUIRE(w.person_id==ids && w.ammo[1]==23 && w.equip[1].family==item_family && w.equip[1].material==item_material);
 REQUIRE(w.formations[0].order==order && w.formations[0].rng==rng && w.formations[0].goal_x==goal_x && w.formations[0].goal_y==goal_y);
 REQUIRE(w.state_hash()==four.state_hash());valid(w);valid(four);
 World loaded(4);REQUIRE(loaded.load(w.save()) && loaded.state_hash()==w.state_hash());
 for(int frame=0;frame<60;++frame){REQUIRE(w.step_clock(1.f/30,0,0));REQUIRE(four.step_clock(1.f/30,0,0));REQUIRE(loaded.step_clock(1.f/30,0,0));}
 REQUIRE(w.state_hash()==four.state_hash() && w.state_hash()==loaded.state_hash());valid(w);valid(four);valid(loaded);

 // Real release captures eye heights. A later support collapse cannot bend the arrow into a low ally.
 World shot(1);shot.cfg.chunk=1;setup(shot,2);shot.terrain.base_height.assign(144,0);
 Terrain platform=shot.terrain;platform.height[platform.idx(1,5)]=2;platform.height[platform.idx(2,5)]=2;
 REQUIRE(shot.update_terrain(platform));
 auto archer=shot.get_soldier_state(0);archer.x=1.5f;archer.y=5.5f;archer.ammo=3;shot.set_soldier_state(0,archer);
 auto friend_body=shot.get_soldier_state(1);friend_body.x=3.5f;friend_body.y=5.5f;shot.set_soldier_state(1,friend_body);
 auto target=shot.get_soldier_state(2);target.x=10.5f;target.y=5.5f;shot.set_soldier_state(2,target);
 shot.equip[0].family=rules::F_BOW;
 while(rules::ranged_roll(shot.person_id[0],1,shot.person_id[2],shot.cfg.seed)>.01)++shot.cfg.seed;
 // A release ray may start on a raised floor, but never inside a blocked source cell.
 const int release_cell=shot.terrain.idx(1,5);
 shot.terrain.static_blocked[release_cell]=1;
 REQUIRE(!WorldTestAccess::line_clear(shot,{1,5},{10,5}));
 shot.terrain.static_blocked[release_cell]=0;
 const auto release_flags=shot.terrain.flags[release_cell];shot.terrain.flags[release_cell]=0;
 REQUIRE(!WorldTestAccess::line_clear(shot,{1,5},{10,5}));
 shot.terrain.flags[release_cell]=release_flags;
 REQUIRE(WorldTestAccess::line_clear(shot,{1,5},{10,5}) && WorldTestAccess::friendly_clear(shot,{1,5},{10,5},0));
 WorldTestAccess::release_shot(shot,0,2);
 REQUIRE(shot.projectiles.size()==1 && shot.ammo[0]==2 && shot.projectiles[0].source_eye==3 && shot.projectiles[0].goal_eye==1);
 const auto shot_id=shot.projectiles[0].shot_id;const auto source_id=shot.projectiles[0].shooter_id;
 Terrain fallen=platform;fallen.height[fallen.idx(1,5)]=0;fallen.height[fallen.idx(2,5)]=0;
 REQUIRE(shot.update_terrain(fallen));
 REQUIRE(shot.projectiles.size()==1 && shot.projectiles[0].source_eye==3 && shot.projectiles[0].goal_eye==1 && shot.projectiles[0].shot_id==shot_id && shot.projectiles[0].shooter_id==source_id);
 World shot_four(4);REQUIRE(shot_four.load(shot.save()));
 WorldTestAccess::arrive_shots(shot,10);WorldTestAccess::arrive_shots(shot_four,10);
 REQUIRE(shot.projectiles.empty() && shot.hp[1]==100 && shot.contact_revision[1]==0 && shot.hp[2]<100 && shot.contact_revision[2]>0);
 REQUIRE(shot.state_hash()==shot_four.state_hash());valid(shot);valid(shot_four);
 for(int frame=0;frame<30;++frame){REQUIRE(shot.step_clock(1.f/30,0,0));REQUIRE(shot_four.step_clock(1.f/30,0,0));}
 REQUIRE(shot.state_hash()==shot_four.state_hash());
 std::printf("BUILDING_NATIVE_PASS raised floors/stair reciprocal ramps/high-bit rails; transactional occupied gate updates; original-body collapse, IDs/equipment/order/RNG; frozen release heights over low ally; 1/4-thread saved continuation\n");
}
static void military_building_contract() {
 World w(1);setup(w,3);w.set_hostile(0,2,false);w.combat_left=0;
 for(int i=1;i<3;++i) REQUIRE(w.set_military_role(i,0));
 REQUIRE(w.set_military_role(0,1));REQUIRE(!w.set_military_role(1,3));
 auto &f=w.formations[0];f.training=12;f.fatigue=20;f.fatigue_rest=0;
 const auto ids=w.person_id;const auto hp=w.hp;const auto gear=w.equip;
 REQUIRE(w.set_garrisoned(0,true));REQUIRE(f.current_cmd==-1 && f.formal_cmd==-1 && f.officer_order.empty());
 const auto hash=w.state_hash();REQUIRE(w.host_order(0,1,9,9,0)==NO_ORDERS);REQUIRE(w.state_hash()==hash);
 w.order_move(0,9,9,0);REQUIRE(f.order==Order::HOLD);
 REQUIRE(!w.apply_training_state(0,12,20,0,13,21,0,true));
 World four(4);REQUIRE(four.load(w.save()));REQUIRE(four.state_hash()==w.state_hash());
 const auto x=w.px,y=w.py;
 for(int k=0;k<30;++k){REQUIRE(w.step_clock(1.f/30,1,0));REQUIRE(four.step_clock(1.f/30,1,0));}
 REQUIRE(w.px==x && w.py==y && w.hp==hp && w.person_id==ids && f.current_cmd==-1);
 REQUIRE(w.state_hash()==four.state_hash() && w.military_role[0]==1 && w.military_role[1]==0);
 REQUIRE(w.apply_environment_damage(1,17));REQUIRE(w.hp[1]==83);REQUIRE(w.person_id==ids && w.equip[1].family==gear[1].family);
 REQUIRE(w.set_garrisoned(0,false));step(w);REQUIRE(f.current_cmd==0);
 f.fatigue=20;f.fatigue_rest=0;f.training=12;w.combat_left=0;
 REQUIRE(w.set_sustain_input(0,true,0));
 REQUIRE(w.apply_training_state(0,12,20,0,12.01,20.01,0,true));
 REQUIRE(!w.apply_training_state(0,12,20,0,12.02,20.02,0,true)); // stale result cannot replay
 REQUIRE(w.step_clock(1.f/30,60,0));REQUIRE(f.fatigue==20.01 && f.fatigue_rest==0 && f.training==12.01);
 REQUIRE(w.step_clock(1.f/30,60,0));REQUIRE(f.fatigue<20.01 && f.fatigue_rest==30);
 World loaded(1);REQUIRE(loaded.load(w.save()) && loaded.state_hash()==w.state_hash());
 auto previous=loaded.state_hash();w.military_role[1]=9;REQUIRE(!loaded.load(w.save()) && loaded.state_hash()==previous);
 w.military_role[1]=0;REQUIRE(w.validate());
 std::printf("MILITARY_BUILDING_NATIVE_PASS qualification, garrison no orders, original people and damage, 1/4-thread save parity, training single fatigue step and stale replay rejection\n");
}
static void post_holder_contract() {
 // R1b + 2026-10-07: officers command only as captain or post holder (文官 or 武官).
 World w(1);w.terrain.allocate(12,12);w.cfg.ai=false;w.cfg.auto_capture=false;w.cfg.bleed_per_game_hour=0;
 int a=w.add_formation(0,3.5f,5.5f,0,3,0.8f,T_MELEE,30);int b=w.add_formation(2,8.5f,5.5f,kPi,1,1,T_MELEE,30);
 rules::Equip eq;eq.family=rules::F_LONGSWORD;eq.material=rules::M_IRON;
 for(int i=0;i<4;++i) w.add_soldier(a,eq,i==0?R_CAPTAIN:(i<3?R_OFFICER:R_REGULAR),100+i);
 w.add_soldier(b,eq,R_CAPTAIN,200);w.finalize();for(auto &f:w.formations) f.ai_enabled=false;w.combat_left=100;w.events.clear();
 for(int i=0;i<3;++i){REQUIRE(w.set_military_role(i,1));REQUIRE(w.post_holder[i]==1);} // standalone default stays legacy
 REQUIRE(w.set_military_role(3,0));
 for(int i=0;i<3;++i){w.ability[i].tactics=(int16_t)(10*(i+1));w.ability[i].leadership=0;w.ability[i].coach=0;}
 step(w);auto &f=w.formations[a];
 REQUIRE(w.command_eligible(0) && w.command_eligible(1) && w.command_eligible(2));
 const double all=w.command_effect(a,0,0.4);
 REQUIRE(w.set_post_holder(1,0) && w.set_post_holder(3,1) && !w.set_post_holder(1,2));
 REQUIRE(w.command_eligible(0) && !w.command_eligible(1) && w.command_eligible(2) && !w.command_eligible(3)); // soldier on a post: no command
 const double seated=w.command_effect(a,0,0.4);
 w.ability[1].tactics=0;REQUIRE(w.set_post_holder(1,1));REQUIRE(w.command_effect(a,0,0.4)==seated && seated<all);
 w.ability[1].tactics=20;REQUIRE(w.set_post_holder(1,0));
 World loaded(4);REQUIRE(loaded.load(w.save()) && loaded.state_hash()==w.state_hash() && loaded.post_holder==w.post_holder);
 w.hp[0]=0;step(w);REQUIRE(f.formal_cmd==2); // officer 1 is first in order but holds no post
 w.post_holder[1]=2;auto previous=loaded.state_hash();REQUIRE(!loaded.load(w.save()) && loaded.state_hash()==previous);
 w.post_holder[1]=0;REQUIRE(w.validate());
 std::printf("POST_HOLDER_NATIVE_PASS standalone default, captain or officer post holder commands, soldier post holder does not, effect sums seated only, succession skips unseated officer, save/load/validation\n");
}
// G5 S4 surrender (NEKKI 2026-10-30, revised): a trapped routed member surrenders and at once becomes a captive of the
// nearest hostile formation's nearest able member (guard room permitting). With no hostile formation it stays surrendered
// and is captured as soon as one appears. Thread counts 1 and 4 agree.
// Scenario (32 x 32): a walled 5 x 5 pocket (interior 4..8): team 0 routed, soldiers 0 (captain) and 1 (formation 0); team 1
// soldier 2 inside it (formation 1). Open ground: team 0 routed unit (formation 2, soldiers 3-5) retreats from team 1 soldier 6
// (formation 3) six cells east. Team 1 soldier 7 (formation 4) stands far north of the pocket.
static void surrender_world(World &w,bool hostile_on=true) {
 w.terrain.allocate(32,32);w.cfg.ai=false;w.cfg.auto_capture=false;w.cfg.rescue_seek_cells=0;w.cfg.bleed_per_game_hour=0;w.combat_left=1e9;
 for(int k=3;k<=9;++k){w.terrain.static_blocked[w.terrain.idx(3,k)]=1;w.terrain.static_blocked[w.terrain.idx(9,k)]=1;w.terrain.static_blocked[w.terrain.idx(k,3)]=1;w.terrain.static_blocked[w.terrain.idx(k,9)]=1;}
 w.terrain.build_edges();
 rules::Equip eq;eq.family=rules::F_LONGSWORD;eq.material=rules::M_IRON;
 int pocket=w.add_formation(0,6.5f,6.5f,0,2,0.8f,T_MELEE,30);
 int enemy_in=w.add_formation(1,6.5f,7.5f,kPi,1,1,T_MELEE,30);
 int open=w.add_formation(0,16.5f,16.5f,0,3,0.8f,T_MELEE,30);
 int enemy_out=w.add_formation(1,22.5f,16.5f,kPi,1,1,T_MELEE,30);
 int remote=w.add_formation(1,16.5f,2.5f,kPi,1,1,T_MELEE,30);
 for(int i=0;i<2;++i) w.add_soldier(pocket,eq,i==0?R_CAPTAIN:R_REGULAR,100+i);   // soldiers 0, 1
 w.add_soldier(enemy_in,eq,R_CAPTAIN,300);                                       // soldier 2
 for(int i=0;i<3;++i) w.add_soldier(open,eq,i==0?R_CAPTAIN:R_REGULAR,400+i);     // soldiers 3, 4, 5
 w.add_soldier(enemy_out,eq,R_CAPTAIN,500);                                      // soldier 6
 w.add_soldier(remote,eq,R_CAPTAIN,600);                                            // soldier 7
 w.finalize();
 for(auto &f:w.formations) f.ai_enabled=false;
 w.set_hostile(0,1,hostile_on);
 w.formations[pocket].morale=10;w.formations[open].morale=10;
 w.events.clear();
}
static void surrender_contract() {
 // A trapped routed pair is captured at once by the nearest enemy; the open-ground unit is neither surrendered nor captured.
 {
  World w(1);surrender_world(w);
  for(int n=0;n<200 && !(w.captive[0] && w.captive[1]);++n) step(w);
  REQUIRE(w.formations[0].routed);
  REQUIRE(w.captive[0]==1 && w.captive[1]==1);
  REQUIRE(w.captor[0]==2 && w.captor[1]==2);
  REQUIRE(!w.is_surrendered(0) && !w.is_surrendered(1));
  REQUIRE(!w.captive[2] && !w.captive[3] && !w.captive[4] && !w.captive[5] && !w.captive[6] && !w.captive[7]);
  REQUIRE(!w.is_surrendered(3) && !w.is_surrendered(4) && !w.is_surrendered(5));
  REQUIRE(!w.is_surrendered(2) && !w.is_surrendered(6));
  REQUIRE(w.stats.captures_done==2 && w.stats.captures_started==0);
  int captured_by_300=0;
  for(const Event &e:w.events) if(e.kind==EV_CAPTURED && (e.soldier==0 || e.soldier==1) && e.other==300) ++captured_by_300;
  REQUIRE(captured_by_300==2);
  REQUIRE(w.formations[2].cx<15.5f); // the open-ground unit keeps retreating away from team 1 soldier 6
  std::printf("SURRENDER_CAPTIVE captor=%d,%d captures_done=%d\n",(int)w.captor[0],(int)w.captor[1],(int)w.stats.captures_done);
  continuation(w);
 }
 // The captive follows its captor: when the captor walks, the captive keeps one cell behind it, as escorted captives do.
 {
  World w(1);surrender_world(w);
  for(int n=0;n<200 && !(w.captive[0] && w.captive[1]);++n) step(w);
  REQUIRE(w.captive[0]==1 && w.captor[0]==2);
  const float cx0=w.px[2], cy0=w.py[2], vx0=w.px[0], vy0=w.py[0];
  w.order_move(1,7.5f,5.5f,0);
  for(int n=0;n<240;++n) step(w);
  REQUIRE(w.captive[0]==1 && w.captor[0]==2);
  const float mdx=w.px[2]-cx0, mdy=w.py[2]-cy0;
  REQUIRE(mdx*mdx+mdy*mdy>0.25f);
  const float fx=w.px[0]-w.px[2], fy=w.py[0]-w.py[2];
  REQUIRE(fx*fx+fy*fy<=2.f*2.f); // NEKKI 2026-10-31: the point behind the captor is 1.5 cells (was 0.8; gap limit 1.6)
  REQUIRE(std::fabs(w.px[0]-vx0)+std::fabs(w.py[0]-vy0)>0.5f);
  std::printf("SURRENDER_FOLLOW captor_moved=%.3f captive_gap=%.3f\n",std::sqrt(mdx*mdx+mdy*mdy),std::sqrt(fx*fx+fy*fy));
 }
 // No hostile formation: the surrender holds (still, unhit, no command) until an enemy appears, then the enemy captures it.
 {
  World w(1);surrender_world(w,false);
  for(int n=0;n<200 && !(w.is_surrendered(0) && w.is_surrendered(1));++n) step(w);
  REQUIRE(w.is_surrendered(0) && w.is_surrendered(1));
  const double hp0=w.hp[0], hp1=w.hp[1];
  const float x0=w.px[0], y0=w.py[0], x1=w.px[1], y1=w.py[1];
  for(int n=0;n<150;++n) {
   step(w);
   REQUIRE(w.is_surrendered(0) && w.is_surrendered(1) && !w.captive[0] && !w.captive[1]);
   REQUIRE(w.hp[0]==hp0 && w.hp[1]==hp1 && !w.can_act(0) && !w.can_act(1));
   REQUIRE(std::fabs(w.px[0]-x0)<0.05f && std::fabs(w.py[0]-y0)<0.05f && std::fabs(w.px[1]-x1)<0.05f && std::fabs(w.py[1]-y1)<0.05f);
  }
  w.set_hostile(0,1,true);
  for(int n=0;n<120 && !(w.captive[0] && w.captive[1]);++n) step(w);
  REQUIRE(w.captive[0]==1 && w.captive[1]==1 && w.captor[0]==2 && w.captor[1]==2);
  REQUIRE(!w.is_surrendered(0) && !w.is_surrendered(1));
  REQUIRE(w.stats.captures_done==2);
 }
 // Guard room: a captor already holding GUARD_CAPACITY captives gives none, so the next formation with an able member takes it.
 {
  World w(1);surrender_world(w);
  for(int k:{3,4,5,6}) { auto st=w.get_soldier_state(k); st.captive=1; st.captor_person=300; st.escape_t=0; w.set_soldier_state(k,st); }
  int held=0;
  for(int k:{3,4,5,6}) held+=(w.captive[k] && w.captor[k]==2) ? 1 : 0;
  REQUIRE(held==4);
  for(int n=0;n<200 && !(w.captive[0] && w.captive[1]);++n) step(w);
  REQUIRE(w.captive[0]==1 && w.captive[1]==1);
  REQUIRE(w.captor[0]==7 && w.captor[1]==7);
  held=0;
  for(int k:{3,4,5,6}) held+=(w.captive[k] && w.captor[k]==2) ? 1 : 0;
  REQUIRE(held==4);
  continuation(w);
 }
 // Save and load mid-surrender and after the capture keep the hash; threads 1 and 4 agree step by step.
 {
  World w(1);surrender_world(w,false);
  for(int n=0;n<200 && !w.is_surrendered(0);++n) step(w);
  REQUIRE(w.is_surrendered(0));
  World c(1);REQUIRE(c.load(w.save()));REQUIRE(c.is_surrendered(0) && c.state_hash()==w.state_hash());
  continuation(w);
  w.set_hostile(0,1,true);
  for(int n=0;n<200 && !w.captive[0];++n) step(w);
  REQUIRE(w.captive[0]==1);
  World d(1);REQUIRE(d.load(w.save()));REQUIRE(d.captive[0]==1 && d.state_hash()==w.state_hash());
  continuation(w);
  World a(1),b(4);surrender_world(a);surrender_world(b);
  for(int n=0;n<200;++n){step(a);step(b);REQUIRE(a.state_hash()==b.state_hash());}
  REQUIRE(a.captive[0]==1 && b.captive[0]==1 && a.captor[0]==2);
 }
 // A surrendered member killed before anyone captures it loses the flag at once, and the state stays valid.
 {
  World k(1);surrender_world(k,false);
  for(int n=0;n<200 && !k.is_surrendered(0);++n) step(k);
  REQUIRE(k.is_surrendered(0));
  k.apply_contact(0,1000.0,0.0);
  REQUIRE(k.hp[0]==0.0 && !k.is_surrendered(0));
  valid(k);
  continuation(k);
 }
}

// NEKKI 2026-10-31: a field captive walks behind its captor (legal route, no wall crossing), stands when the captor dies,
// yields to an explicit escort order, never moves in a prison, and keeps 1/4-thread parity.
static void follow_world(World &w) {
 w.terrain.allocate(16,12);w.cfg.ai=false;w.cfg.auto_capture=false;w.cfg.rescue_seek_cells=0;w.cfg.bleed_per_game_hour=0;w.combat_left=1e9;w.cfg.chunk=1; // one soldier per chunk: the parity legs cross chunk boundaries
 rules::Equip eq;eq.family=rules::F_LONGSWORD;eq.material=rules::M_IRON;
 int guard_f=w.add_formation(0,4.5f,6.5f,0,1,1,T_MELEE,30);
 int prisoner_f=w.add_formation(1,3.5f,6.5f,0,1,1,T_MELEE,30);
 w.add_soldier(guard_f,eq,R_CAPTAIN,100);   // soldier 0: captor
 w.add_soldier(prisoner_f,eq,R_CAPTAIN,200); // soldier 1: captive
 w.finalize();
 for(auto &f:w.formations) f.ai_enabled=false;
 w.set_hostile(0,1,true);w.events.clear();
 auto captive=w.get_soldier_state(1);captive.x=3.5f;captive.y=6.5f;captive.captive=1;captive.captor_person=w.person_id[0];w.set_soldier_state(1,captive);
 auto guard=w.get_soldier_state(0);guard.x=4.5f;guard.y=6.5f;w.set_soldier_state(0,guard);
}
static void captive_follow_contract() {
 // Open ground: the captive trails 1.5 cells behind a walking captor, never beyond 2 cells, and stops when the captor stops.
 {
  World w(1);follow_world(w);
  w.order_move(0,14.5f,6.5f,0);
  float worst=0.f;
  for(int n=0;n<400;++n) {
   step(w);
   if(n>=30) { const float dx=w.px[0]-w.px[1], dy=w.py[0]-w.py[1]; worst=std::max(worst,std::sqrt(dx*dx+dy*dy)); }
  }
  REQUIRE(w.captive[1]==1 && w.captor[1]==0);
  REQUIRE(w.px[0]>12.f);            // the captor walked well east
  REQUIRE(worst<=2.f);              // stayed within 2 cells while it walked
  REQUIRE(w.px[1]>w.px[0]-2.f && w.px[1]<w.px[0]-.5f);
  const float stop_x=w.px[1],stop_y=w.py[1];
  for(int n=0;n<60;++n) step(w);
  REQUIRE(std::fabs(w.px[1]-stop_x)<.05f && std::fabs(w.py[1]-stop_y)<.05f); // captor stopped: captive stands
  REQUIRE(std::fabs(w.vx[1])<.01f && std::fabs(w.vy[1])<.01f);
  std::printf("CAPTIVE_FOLLOW worst_gap=%.3f captor_x=%.3f captive_x=%.3f\n",worst,w.px[0],w.px[1]);
  continuation(w);
 }
 // A wall with a gap at the bottom row: the captive goes around through legal cells, never through the wall.
 {
  World w(1);follow_world(w);
  for(int y=0;y<11;++y) w.terrain.static_blocked[w.terrain.idx(8,y)]=1;
  w.terrain.build_edges();
  auto guard=w.get_soldier_state(0);guard.x=10.5f;guard.y=6.5f;w.set_soldier_state(0,guard);
  w.order_move(0,10.5f,6.5f,0); // the captor walks round the gap itself; its formation slot would otherwise pull it through the wall
  bool through_wall=false;
  for(int n=0;n<600;++n) {
   step(w);
   const int cx=(int)std::floor(w.px[1]),cy=(int)std::floor(w.py[1]);
   if(cx==8 && cy<11) through_wall=true;
  }
  REQUIRE(!through_wall);
  REQUIRE(w.px[1]>8.f);                                     // went around to the captor's side
  REQUIRE(std::hypot(w.px[0]-w.px[1],w.py[0]-w.py[1])<=2.5f);
  std::printf("CAPTIVE_FOLLOW_GAP_ROUTE captive=(%.2f,%.2f) captor=(%.2f,%.2f)\n",w.px[1],w.py[1],w.px[0],w.py[0]);
  continuation(w);
 }
 // A closed wall: no legal route, so the captive waits on its own side and never enters the wall.
 {
  World w(1);follow_world(w);
  for(int y=0;y<12;++y) w.terrain.static_blocked[w.terrain.idx(8,y)]=1;
  w.terrain.build_edges();
  auto guard=w.get_soldier_state(0);guard.x=10.5f;guard.y=6.5f;w.set_soldier_state(0,guard);
  w.order_move(0,10.5f,6.5f,0);
  const float x0=w.px[1],y0=w.py[1];
  for(int n=0;n<300;++n) { step(w); REQUIRE(w.px[1]<8.f); }
  REQUIRE(std::fabs(w.px[1]-x0)<.1f && std::fabs(w.py[1]-y0)<.1f);
  continuation(w);
 }
 // Captor dies: the captive stands where it is (the existing escape and recapture rules are untouched).
 {
  World w(1);follow_world(w);
  for(int n=0;n<30;++n) step(w);
  w.apply_contact(0,1000.0,0.0);
  REQUIRE(!w.alive(0));
  step(w);
  const float x0=w.px[1],y0=w.py[1];
  for(int n=0;n<60;++n) step(w);
  REQUIRE(w.captive[1]==1);
  REQUIRE(std::fabs(w.px[1]-x0)<.02f && std::fabs(w.py[1]-y0)<.02f);
  continuation(w);
 }
 // An explicit escort order takes precedence: the captive walks to the ordered cell and does not drift behind the captor.
 {
  World w(1);follow_world(w);
  REQUIRE(w.order_escort_step(1,0,w.terrain.idx(3,5)));
  for(int n=0;n<60;++n) step(w);
  REQUIRE(w.escort_mode[1]==1 && w.escort_goal[1]==-1);
  REQUIRE(std::fabs(w.px[1]-3.5f)<.05f && std::fabs(w.py[1]-5.5f)<.05f);
  continuation(w);
 }
 // A prisoner is a stationary body: no follow while confined, even with a moving captor.
 {
  World w(1);follow_world(w);
  auto inmate=w.get_soldier_state(1);inmate.captive=1;inmate.captor_person=w.person_id[0];inmate.prison_id=7;w.set_soldier_state(1,inmate);
  const float x0=w.px[1],y0=w.py[1];
  w.order_move(0,14.5f,6.5f,0);
  for(int n=0;n<120;++n) { step(w); REQUIRE(w.px[1]==x0 && w.py[1]==y0); }
  REQUIRE(w.prison_id[1]==7);
  continuation(w);
 }
 // 1, 2 and 4 threads agree step by step through a walk, a stop and a mid-walk save/load.
 {
  World a(1),b(2),d(4);follow_world(a);follow_world(b);follow_world(d);
  a.order_move(0,14.5f,6.5f,0);b.order_move(0,14.5f,6.5f,0);d.order_move(0,14.5f,6.5f,0);
  for(int n=0;n<200;++n) { step(a);step(b);step(d);REQUIRE(a.state_hash()==b.state_hash());REQUIRE(a.state_hash()==d.state_hash()); if(n==100){World c(1);REQUIRE(c.load(a.save()));REQUIRE(c.state_hash()==a.state_hash());} }
  REQUIRE(a.captive[1]==1 && b.captive[1]==1 && d.captive[1]==1);
  continuation(a);
 }
}

static void fuzz() {
 World base(1);setup(base,1);auto blob=base.save();World numeric(1);REQUIRE(numeric.load(blob));numeric.hp[0]=77;auto mod=numeric.save();size_t hp_offset=0;while(hp_offset<blob.size() && blob[hp_offset]==mod[hp_offset])++hp_offset;
 // Find the complete double containing the changed byte using the uniquely known 100.0 bytes.
 double hundred=100;size_t start=hp_offset;for(size_t k=hp_offset>7?hp_offset-7:0;k<=hp_offset;++k)if(k+8<=blob.size() && std::memcmp(blob.data()+k,&hundred,8)==0){start=k;break;}
 std::mt19937 rng(581);int accepted=0,rejected=0;
 for(int k=0;k<2000;++k) {
  auto b=blob;if(k%4==0){double hp=1+(rng()%990)/10.;std::memcpy(b.data()+start,&hp,8);}
  else if(k%4==1){b[rng()%b.size()]^=uint8_t(1+(rng()%255));}
  else if(k%4==2){b.resize(rng()%b.size());}
  else {b.insert(b.begin()+(rng()%b.size()),uint8_t(rng()));}
  World w(1);REQUIRE(w.load(blob));auto before=w.state_hash();
  if(w.load(b)){++accepted;valid(w);for(int t=0;t<300;++t){REQUIRE(w.step(1.f/30));valid(w);}}
  else{++rejected;REQUIRE(w.state_hash()==before);}
 }
 REQUIRE(accepted>0 && rejected>0);std::printf("FUZZ total=2000 accepted=%d rejected=%d continuation_steps=%d\n",accepted,rejected,accepted*300);
}
int main(int argc,char**argv) {
 #ifdef _WIN32
 SetErrorMode(SEM_FAILCRITICALERRORS | SEM_NOGPFAULTERRORBOX);
#endif
 setvbuf(stdout,nullptr,_IONBF,0);
 if(argc>1 && std::string(argv[1])=="--fuzz")fuzz();
 else if(argc>2 && std::string(argv[1])=="--replay")replay_blob(argv[2],argc>3?std::strtoull(argv[3],nullptr,10):0);
 else{orders();retreat_contract();c_api_order_codes();imports_append_sustain();append_after_death_roundtrip();hunger();death_fatigue_event_contract();safe_load();prison_contract();building_geometry_contract();military_building_contract();post_holder_contract();surrender_contract();captive_follow_contract();}
 std::printf("C2/C3 checks=%d failures=%d\n",checks,failures);return failures?1:0;
}
