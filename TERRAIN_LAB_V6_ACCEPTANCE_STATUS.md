# Terrain Lab V6 implementation / acceptance

## Final acceptance — 2026-09-11

**Implementation and functional/visual acceptance are complete under the approved V6 semantics. Performance measurement is complete, but seven Army CPU P95 comparison targets are NOT met. This is not an all-performance-targets PASS.** S0–S4 no longer have unexecuted required behavior, matrix or visual cases. Earlier partial checkpoints below are historical and do not describe the final runtime.

Final runtime SHA256: `e04f5ed4012c3361fa65ba24b52b727cd05e7fa526ced1e945d18f4ca9b15877`. TerrainLab UI SHA256: `137ac1b6ad89715a4449a021e0e2a56b0de7cb12faa5ea78629b62f8aa1fff24`. All final behavior, visuals and performance used this unchanged runtime. Exact test hashes, arguments, result/log paths, capture hashes, full performance fields and retained failures are in [TERRAIN_LAB_V6_FINAL_RUNS.json](TERRAIN_LAB_V6_FINAL_RUNS.json).

### Delivered behavior and ownership

- Open ground: 100 real army members share one-cell same-direction WALK batches, with the captain inside the formation. Rear RUN catch-up holds new collective advances, not in-flight actions; recovered members return to WALK.
- Local mouths: the captain uses ordinary admission and protected middle order. Early arrivals clear the exit and receive nearby; every feasible intermediate platform has an actual connected 100-person rally before onward movement. Proven insufficient small platforms remain continuous passage groups.
- Curved terraces use the explicitly approved same-direction subsets, not mixed-direction atomic transactions. Actual legal edges, physical connectivity, front/rear guards and guide-span limits remain checked.
- EDGE targets the formation front; FOLLOW uses the front's distance to PLAYER. Final ordinary slots and the captain's interior slot are distinct from intermediate activity goals. New commands drain existing movement before the latest request activates.
- TerrainArmy remains the sole movement/owner/claim owner; TerrainData remains the legal-edge authority. Node2D terrain, the existing captain presenter and 99 baked-atlas followers remain. No new per-soldier Nodes, combat system, World/Region/Site subsystem, speed changes or search-budget increases were added.
- UI now says `Army: formation march to map edge` and separately displays the command front goal, guide, captain local slot, local formation count, legal lag, runners, guards and passage clearing.

### Final-source functional coverage

There are **119 successful headless runs** (118 distinct file/argument combinations; one default F01 command was repeated after adding explicit deadline reporting). The retained original 30Hz F01/20-second failure is not included in those passes.

| Suite | Successful runs | Coverage |
| --- | ---: | --- |
| Formation advance | 19 | G01–G10, full/subset/parallel atomic cases, future binding ownership, bends/return, receiving EF/FE handoffs; G01 at all three dt schedules |
| Width/transactions | 32 | W01–W05, F02/F03, Q01–Q06 branches, M01/M02, X01, eight MOVE/captain swap/follower swap/push EF/FE handoffs |
| Entrance clearance | 14 | E01–E04, E07–E12, flat/ramp terminal boundaries, capacity and initial downstream exemptions |
| Passage | 3 | P0, E05_TURN and M01_SMALL_PLATFORM |
| Formation smoke | 6 | Default/alternating old-deadline passes, plus all three explicit V6-budget schedules |
| Captain route | 3 | C01/C02 shared-route checks at 60Hz, 30Hz and alternating dt |
| Complete legacy army | 3 | Original army suite, ramp and multilevel E06 physical crossing/clearance at all three dt schedules |
| D01 + generated terrain | 39 | D01 ×3 plus **36/36** generated combinations: terraced/rocky × seeds 12345/12346/24680 × EDGE/FOLLOW × 60Hz/30Hz/alternating 1/120–1/40 |

The matrix did not discard a difficult seed. Successful full-route cases verify physical crossings/clearings, actual complete intermediate rallies, final 99 fixed ordinary slots plus protected captain, unique ownership/claims, legal edges, command-goal stability, five stable seconds and bounded searches. A local `99/99` is not accepted as command completion.

| D01 schedule | Complete input seconds | Stable end seconds | Actual rallies | Run |
| --- | ---: | ---: | ---: | --- |
| 60Hz | 458.9 | 463.9 | 5 | `20260911_010755_961` |
| 30Hz | 472.3 | 477.3 | 5 | `20260911_010838_178` |
| Alternating | 458.9 | 463.9 | 5 | `20260911_010917_311` |

All five ordinary crossing and clearing counters are 99. Captain crossing ordinals, including the captain, are `[42,22,40,49,47]`; the GPU metadata stores the corresponding number of preceding ordinary soldiers `[41,21,39,48,46]`. Final front is `(99,75)` and captain is `(95,75)`. D01 observed maxima are structure 256/input frame, local 3072/input frame and push 512/input frame; no simulation time was dropped. Production limits remain structure 256/input frame, four local requests ×1024 per simulation tick, push 512/tick, at most two simulation ticks/frame.

### GPU inspection — 11 cases, 100 images

All listed cases exited 0 and all 100 newly written PNGs were inspected. Captures and per-frame metadata are in `.visual_captures/terrain_lab/v6/e04f5ed4012c/`. Transaction inspection used read-only zoom sheets of every sample plus full-frame checks; original PNGs were not edited.

| Case | Images | Run | Evidence |
| --- | ---: | --- | --- |
| G01 | 7 | `20260911_012425_376` | Real deployment, continuous rectangular collective movement, captain inside, final stable 5s |
| G02 | 11 | `20260911_012638_082` | 91 checked frames; two actual rear RUN members, front hold, return to WALK, collective movement resumes |
| G08_BEND | 8 | `20260911_012806_550` | Controlled curved-terrace snapshot; 2,217 commits, 20 captain edges; independent front/rear minima 48/41; local turn, not final command completion |
| D01, 30Hz | 6 | `20260911_012939_148` | Protected captain crossing, early receiving, full middle rally, resumed collective movement, actual final egress at 465.6s, final stable at 477.2s |
| E01 | 4 | `20260911_013303_610` | Flat-mouth captain/receiving/complete egress/final stability |
| E02 | 4 | `20260911_013405_393` | Reciprocal ramp with the same physical middle-order and clearing checks |
| V_MOVE | 12 | `20260911_013512_940` | 97 frames, original unit 1 edge completed without rewind |
| V_FOLLOWER_SWAP | 12 | `20260911_013847_916` | 97 frames, both reciprocal edges commit, owners remain unique |
| V_PUSH | 12 | `20260911_013947_035` | 97 frames, empty-end-first commit order `[4,3,2,1]` |
| V_HANDOFF | 12 | `20260911_014255_008` | Original blocker completes; clean activation boundary at frame 18; only the latest command's new work follows |
| V_CAPTAIN_SWAP | 12 | `20260911_014359_056` | 97 frames, captain/follower reciprocal commit, no ground-position rewind |

Nine cases used visual-test hash `1f4b4020ddfc671a2e33d4be886f7b5d3a8bf66ad5ab5c5bf14b03ce569c34a7`. The final V_HANDOFF and V_CAPTAIN_SWAP used `a083f56aac6f6742dd330e3c089f0fe53d3b80d35ddc66cf5ac031545c00c37f`. The only intervening test change checks OLD transaction cleanup at the exact activation boundary, then rejects stale command epochs during later frames; previously it incorrectly demanded no NEW FOLLOW pushes at 1.6s. Other case branches and runtime were unchanged. The failed earlier assertion remains recorded.

### Measured performance — complete, with CPU target misses

Godot **4.6.2**, i5-14400F / RTX 5060, Forward+ D3D12, 2560×1440, vsync disabled, unlimited frame rate, production HUD enabled. Each stage has 60 warmup frames and approximately **3 seconds of actual render-delta sampling** after preparation. The wrapper and its child use affinity `0xFFF`; no other process or global setting was changed. Controlled flat/catch-up/receiving/turn fixtures are explicitly distinguished from unchanged-D01 replay in the JSON. This is not a long-duration benchmark or a claim about Godot 4.7.

| Activity | Samples | Frame P95 / P99 ms | Frame max ms | Army CPU P95 ms | Physical member commits | S/L/P expansion maxima |
| --- | ---: | --- | ---: | ---: | ---: | --- |
| Flat full batch | 500 | 6.999 / 8.593 | 15.660 | 0.789 | 1000 | 0/0/0 |
| Rear catch-up | 462 | 8.053 / 10.503 | 17.909 | 0.841 | 706 | 0/0/0 |
| Single-mouth receiving | 478 | 8.223 / 10.085 | 18.967 | **2.386** | 149 | 0/93/12 |
| Curved local turn | 326 | 11.757 / 17.388 | 24.511 | **2.925** | 811 | 256/0/0 |
| D01 full batch | 374 | 9.257 / 10.723 | 16.178 | 0.864 | 1000 | 0/0/0 |
| Gate 1 | 350 | 10.517 / 11.799 | 21.693 | **2.146** | 98 | 0/11/6 |
| Gate 2 | 360 | 10.492 / 13.662 | 22.897 | **2.146** | 89 | 0/62/66 |
| Gate 3 | 365 | 10.207 / 12.584 | 21.790 | **2.190** | 149 | 0/14/7 |
| Gate 4 | 363 | 10.008 / 11.352 | 22.718 | **2.203** | 158 | 0/16/6 |
| Gate 5 | 363 | 10.421 / 13.402 | 21.052 | **2.283** | 177 | 0/96/3 |
| Final regroup/onward batch | 360 | 9.757 / 17.158 | 34.167 | 0.870 | 1000 | 0/0/0 |

All 11 frame P95/P99 results meet the 16.7/25ms comparison targets; **7/11 CPU P95 results miss 2ms**. Every sample has zero >50ms frames and zero dropped input time, with approximately 3.0 simulated seconds. Exact input/sim values, CPU P99/max, physical gate deltas and phase-specific percentiles remain in `.godot-temp/terrain_v6_performance/e04f5ed4012c/*.json` and the ledger. Catch-up has 50 rear-RUN, 45 local-WALK and 367 whole-batch samples; turn has 292 local-turn and 34 whole-batch samples. These are measured activity samples, not idle-only speed claims. Individual gate throughput during each short sample is not a whole-route average.

### Retained timing tradeoffs and failed attempts

- D01 uses the predeclared **503 input-second V6 budget**, not the old 180s scout model. All three schedules meet V6 and miss V5. Five mandatory full-team rallies intentionally remove the old inter-platform pipelining; MOVE=0.24s, RUN=0.18s and SIM_STEP=0.10s remain unchanged.
- F01 completes at 16.0s for 60Hz/alternating and 20.9s for 30Hz. Original 30Hz/20s run `20260911_010407_571` remains **FAIL**. Explicit `--v6-budget` uses `0.30*L + 20 + initial_structural_work/(256*input_hz)`, frozen before physical replay: L=17, structural work=71940, deadlines 29.78359375/34.4671875s. Three V6-budget schedules pass; default old 20s was not silently enlarged.
- Captain-swap capture `20260911_013719_370` remains **TIMEOUT** at its 40s wall allowance. First capture took 32.9s; seven files were produced before termination. After diagnostic inspection, the bounded capture allowance became 55s; the complete final run passed in 31.198s. This changes no simulation deadline.
- V_HANDOFF `20260911_014044_841` remains **FAIL** for the late/global-empty assertion. The corrected test passes at the exact clean handoff boundary, preserving the original edge, unstarted-tail cancellation, claims/locks and per-frame ownership checks. Later pending pushes are explicitly logged with the new command epoch 5.
- Editor startup `20260911_015305_282` remains **TIMEOUT** at 15s. A distinct full-import check, `--headless --editor --import`, completed in **30.691s / exit 0** (`20260911_015523_757`), including script-class and editor-layout completion. No parse/script/assertion errors were reported. Root-certificate messages are retained as environment noise on exit-0 runs, not hidden.
- Older runtime failures, counterexamples and the earlier 60Hz GPU timeout are historical evidence. They remain in their logs and the ledger; none was retroactively converted to PASS.

### Reproduction and handoff boundary

Use the canonical runner and Godot path in the ledger from this project root. Headless test shape is `-Mode headless -GodotArguments @('--script','res://scripts/tests/<file>','--',<args>)`; omit the delimiter when there are no args. Visual cases use `-Mode visual` with `terrain_lab_army_visual_test.gd -- --case=<case>` (D01 additionally `--30hz`). Performance uses `terrain_lab_default_edge_performance_test.gd -- --stage=<stage> --30hz`. Editor completion uses `-Mode headless -TimeoutSeconds 50 -GodotArguments @('--editor','--import')`. Exact per-run commands, exit codes and durations are preserved rather than inferred from PASS labels.

No files were staged or committed. Existing unrelated worktree changes were preserved. No unattended validation process, automation or subagent remains. The implementation is limited to the terrain lab; no combat-protection guarantee, long-duration performance claim or full-game acceptance is implied. Further CPU optimization is a measured follow-up, not an unexecuted functional test.

## Historical verification checkpoint — 2026-09-11 00:57

Final-source verification is in progress on runtime `e04f5ed4012c3361fa65ba24b52b727cd05e7fa526ced1e945d18f4ca9b15877`. **49 current-source headless runs have passed**, including G01–G10 focused cases, both bend counterexamples, all eight MOVE/captain-swap/follower-swap/push command handoffs, W01–W05 and the complete width/transaction contract suite. Logs are indexed by source and arguments in the final run ledger being assembled; this is not yet the full generated-matrix acceptance.

The earlier `f9e7455` runtime ultimately passed all **36/36** generated combinations and standalone D01 at all three dt patterns. Subsequent legacy regressions exposed zero-gate final-layout ownership, true five-wide passage handling, near-PLAYER footprint protection, per-unit completion of batch members and idle/no-command route planning bugs; these were corrected. Those historical 36 passes must not be relabeled as current-source results.

Runtime `a97fb54e4097` passed the complete legacy army suite, the 91-frame two-rear RUN→WALK GPU sequence, and a full 30Hz D01 GPU replay (472.2 input seconds plus five stable seconds). All 11 rear-catch-up images and six D01 milestones were inspected. The 60Hz GPU run hit its 50-second process limit and remains a timeout, not PASS. An intermediate capture labelled all-exit-clear used an early gate-cell-vacated condition; the test now also requires runtime egress completion before that capture, pending its final-source rerun.

Actual GPU activity measurements on `a97fb54e4097` used RTX 5060 / i5-14400F / Godot 4.6.2 / Forward+ D3D12 / 2560×1440 / vsync disabled / production HUD enabled. Frame P95/P99 met 16.7/25ms in the ten sampled activities; passage/receiving/turn Army CPU P95 was 2.35–2.70ms, above the 2ms comparison target. A diagnostic found 93 summary scans in 30 simulation ticks. Current `e04f5ed4` removes unchanged-target redundant scans (no speed/budget changes); receiving CPU P95 measured 2.386ms, frame P95/P99 8.223/10.085ms, 478 samples, 149 physical commits, zero dropped time. Other activities and visuals must be rerun on this final source; no all-targets PASS is claimed.

Remaining: current-source full legacy army/entrance/passage/smoke/route cases, G01 other dt patterns, D01×3 and generated36, GPU motion/transaction/milestone sequences and inspection, final same-source performance table, editor scan and final evidence ledger. No files staged or committed; unrelated working-tree changes preserved.

## Historical verification checkpoint — 2026-09-10 23:41

Work continues; **full V6 acceptance is not complete**. Runtime `f9e745539e8deefac3f63d18266769311c64734ffc880930d8c5e965cff397e2`, generated test `885898a70aaf40ad689dd8e2b6491b8d1593cc11ab3bbb7b0990ecb6b2bf6147` have passed **24/36 generated cases**: both EDGE/FOLLOW, all three seeds (12345, 12346, 24680), both terraced/rocky presets, at 60Hz and 30Hz. Each full-route PASS includes all required physical crossings/clearings, an actual 100-person witness for each feasible intermediate rally, fixed final slots, stable command goal/revision, and five stable seconds. No seed was excluded. The twelve alternating-dt cases, current-source standalone D01, complete legacy/transaction regressions, final GPU sequence and activity performance matrix remain to be verified.

Current improvements include compact initial assembly, receiving twenty guards before filling both halves farthest-first, future-only receiving binding repair that preserves physical transit owners/claims, bounded geometric bend selection, correct final-facing publication, near-exit reuse of a proven final layout, side-offset boundary layouts, and command-level FOLLOW footprint feasibility before publishing its stable goal. Final local movement retains the downstream passage restrictions.

One current-source 60Hz terraced-24680 FOLLOW attempt (`20260910_233559_833`) hit the **50-second process timeout**, not the simulation deadline, and remains a recorded failed run. No validation process remained afterward. Following read-only environment checks, only the verification wrapper's processor affinity was set to `0xFFF`; its child used the same canonical runner, project, executable, arguments and source. The rerun (`20260910_233913_493`) exited 0 in 37.056 wall seconds, completing at 434.0 input seconds plus 5.017 stable seconds. Later pinned runs must not be presented as directly comparable wall-time performance measurements against earlier default-affinity runs. Other apps and global settings were untouched.

The dated 20:40 section and tables below are **historical**, not the current source version or current acceptance status.

## Historical checkpoint — 20:40

2026-09-10 20:40. **PARTIAL IMPLEMENTATION — approved same-direction subsets are implemented; D01 still FAILS. S2–S4 are not complete.** Do not describe this as full V6 acceptance. V5 and earlier V6 runs below are historical evidence, not substitutes for the current-source results.

## Current retained version

| File | SHA256 |
| --- | --- |
| `scripts/terrain_lab/terrain_army.gd` | `d4b70b64d3e90c97f1531736a057b2232b9ba7a0e95442b5875d4f35d4009caf` |
| `scripts/terrain_lab/terrain_lab.gd` | `137ac1b6ad89715a4449a021e0e2a56b0de7cb12faa5ea78629b62f8aa1fff24` |
| `scripts/tests/terrain_army_formation_advance_test.gd` | `3be9ae25bb7ecccf6af9ffed1f2392190ee5df046c31ed49577fbe624ada0006` |
| `scripts/tests/terrain_army_default_edge_test.gd` | `22b7875db94b335d299afad6206b29082cb231c83523b1db2d42417329a8ae1a` |
| `scripts/tests/terrain_lab_army_visual_test.gd` | `d175791389f6f9e95421d656f40bfb6caf2a923a196aec089437d604fc49acd2` |

All runs in the next table use this exact runtime. Each run has `result.json`, `stdout.log`, `stderr.log`, and `combined.log` under `.godot-temp/godot_verify/<run>/`. Durations are runner wall seconds, not game input seconds. Every PASS row exited 0 without script/parse/assertion errors. No FPS or activity CPU percentile result is implied.

| Current-source case | Result / exit | Run | Wall seconds | Actual evidence boundary |
| --- | --- | --- | --- | --- |
| G01 | PASS / 0 | `20260910_203220_925` | 3.415 | 100-person open march; 22.6 input seconds plus stable 5 seconds |
| G02 | PASS / 0 | `20260910_203225_519` | 1.602 | Lagging members RUN, then collective movement resumes |
| G03 | PASS / 0 | `20260910_203228_292` | 1.824 | Waiting more than 5 seconds does not permanently disable catch-up RUN |
| G04 | PASS / 0 | `20260910_203231_306` | 1.578 | Full-body atomic vacate, external claims and command handoff |
| G04_SUBSET | PASS / 0 | `20260910_203234_027` | 1.571 | Four real members, excluding captain; unrelated occupant, duplicate IDs, NPC and foreign claim rejected; latest-command handoff completes all four |
| G05 | PASS / 0 | `20260910_203247_041` | 7.752 | 100 crossed and cleared; captain 41st; complete at 97.0 input seconds |
| G06 | PASS / 0 | `20260910_203255_947` | 13.849 | Both gates 100/100; actual middle rally and resumed collective movement; 195.3 input seconds |
| G07_MEDIUM | PASS / 0 | `20260910_203356_597` | 5.349 | Straight five-wide opening, 11 narrow collective steps, then width 10 and stable 5 seconds |
| G08 | PASS / 0 | `20260910_203403_110` | 5.542 | Open-field 90-degree command change; 36 new collective steps, stable 5 seconds |
| G08_RETURN | PASS / 0 | `20260910_203409_813` | 6.565 | Open-field 180-degree change; 62 new collective steps, stable 5 seconds |
| G09 | PASS / 0 | `20260910_203417_523` | 3.678 | Front at `(99,50)`, captain at `(95,50)`, all 99 final members settled |
| G08_BEND | PASS / 0 | `20260910_203154_266` | 3.780 | Controlled third-platform snapshot: 1,006 legal member commits and 15 captain edges in 10 seconds; independent front/rear minima 45/47; 100-member connectivity through at most one legal empty-cell gap; fixed guide span 32 |
| G08_BEND_FOURTH | PASS / 0 | `20260910_203422_342` | 3.864 | Controlled fourth-platform snapshot with freshly initialized guide: 1,065 commits, 12 captain edges, front/rear minima 45/46, fixed span 29; not a full D01 or stale-guide replay |
| W01–W05 / release | PASS / 0 | `20260910_203928_848` | 1.694 | Existing width, transaction-release and large-dt accounting checks |
| Passage P0 | PASS / 0 | `20260910_203931_759` | 1.604 | Generic FOLLOW cannot falsely complete an exit rally |
| M01_SMALL_PLATFORM | PASS / 0 | `20260910_203934_587` | 8.808 | Two necessary narrow edges, ordinary counters 99/99, captain middle order, complete 97.5 seconds plus stable 5 seconds |
| E11_CAPACITY | PASS / 0 | `20260910_203944_682` | 2.100 | 60-cell destination rejects a 100-person army; no scout/partial admission |
| G01 GPU | PASS / 0; 7 images inspected | `20260910_203441_902` | 26.417 | 31 per-frame interpolation checks; 10x10 body and protected captain; final stable 5 seconds; actual HUD counts |
| G08_BEND GPU | PASS / 0 for this local case; 8 images inspected | `20260910_203522_264` | 24.308 | Same controlled third-platform snapshot, physical guards/connectivity, 31 continuous ground-position checks, HUD count oracle; command intentionally not complete |
| Editor startup | PASS / 0, limited scan | `20260910_203547_794` | 5.441 | `--headless --editor --quit-after 2`; no parse/script errors, but `Scan thread aborted` means this is not a completed whole-project import scan |
| D01 | **FAIL / 1** | `20260910_203729_565` | 47.642 | Predeclared 503 input-second deadline missed; three actual full-team rallies, not five; process did not time out |

Current canonical runner: `C:/Users/Nekki/.codex/skills/godot-runtime-verify/scripts/verify_godot.ps1`, run from the project root with `-GodotExecutable C:/Users/Nekki/Godot_v4.6.2-stable_mono_win64/Godot_v4.6.2-stable_mono_win64_console.exe`. Godot reports `4.6.2.stable.mono.official.71f334935`.

- G cases: `-Mode headless -GodotArguments @('--script','res://scripts/tests/terrain_army_formation_advance_test.gd','--','--case=G04_SUBSET')`, substituting the case.
- D01: `-Mode headless -TimeoutSeconds 50 -GodotArguments @('--script','res://scripts/tests/terrain_army_default_edge_test.gd')`. The process allowance is separate from, and does not change, the 503 input-second acceptance deadline.
- GPU: `-Mode visual -TimeoutSeconds 35 -GodotArguments @('--script','res://scripts/tests/terrain_lab_army_visual_test.gd','--','--case=G08_BEND')`, or G01. Actual renderer: D3D12 Forward+, NVIDIA GeForce RTX 5060.
- Legacy rows use the named test file and case above: width/release = `terrain_army_width_transaction_test.gd` without arguments; P0 / M01 = `terrain_army_passage_test.gd`; capacity = `terrain_army_entrance_clearance_test.gd -- --case=E11_CAPACITY`.

All processes were bounded foreground runs. No background task, subagent, timer substitute, stage or commit was created. The root-certificate warning remains environment noise on exit-0 checks. The failed D01 also reports cleanup leaks and six resources still in use; it is not a clean run.

## Implemented since the 18:57 approval

- The existing move/owner/claim boundary now accepts a same-direction subset during local turns. All participant IDs, sources, legal edges, claims, external occupancy and destination owners are checked before starting and again before atomic commit. Only participating sources are removed. Every member retains the existing interpolation and physical commit accounting; an excluded captain is not moved. Different directions are never committed as one transaction.
- A published local intent is completed before another shape is planned. An in-flight subset drains before the latest command is activated; unstarted old intents do not survive that activation. Ordinary move/swap/push handling and individual gate admission retain their owners.
- Bend proposals use one legal shared route branch and its projected progress, with a fixed per-platform guide-span limit. They preserve at least 20 front and 20 rear members and reject a body detached by more than one legal empty-cell gap. Detaching bridge moves are held while other legal members may move. Full intermediate rallies still require all 100 physically adjacent and connected, not this looser moving-body test.
- Large-turn guide rebasing is allowed only after at least six units of actual legal goal-distance progress since the prior guide origin. It preserves the platform span and changes no physical cell or claim. The full D01 remains too slow despite this bounded recovery.
- Held approach tickets may move closer within a safe queue-depth floor. They still cannot enter ahead of earlier required guards, push earlier ticket holders aside, or use a push as a shortcut past the hold.
- After an atomic commit enters planning, the cached HUD summary is refreshed at the simulation boundary. GPU checks compare the displayed settled count to actual cells, targets and in-flight states. Rendering/HUD reads cannot trigger navigation searches or mutate ownership.

The original runtime failed the new subset-interface counterexample (`20260910_185957_980`). A later local-turn version passed guard/edge checks but visually left unit 51 at `(33,56)` while the body moved away. The added independent physical-connectivity oracle failed that version (`20260910_201529_624`); the current version passes it. These are retained failures, not retroactively relabeled passes.

Current images are under `.visual_captures/terrain_lab/v6/d4b70b64d3e9/`: G01 has six march frames plus `G01_final_100_settled.png`; G08_BEND has its initial snapshot, six turn frames and `G08_BEND_after_ten_seconds_not_command_complete.png`. All 15 freshly written PNGs were inspected. The former large detached tail gap is gone in this local sequence; the terrain-constrained narrow rear is still visible. This is not five-gate visual acceptance or a claim that the full long-route body is now satisfactory. Earlier image versions were not overwritten.

## Unresolved D01 and required next checks

First actionable current-source failure: `default EDGE missed declared 503-second deadline: frame=-1 status=PLANNING | bounded route, passage and formation analysis assembled=99`.

Actual full-team rally witnesses occurred at 114.7, 215.4 and 355.0 input seconds. At 500 seconds the captain was `(28,64)`, and ordinary crossing counters were `[99,99,99,0,0]`; the fourth and fifth mouths had not been crossed. A local `99/99` while planning is not the final destination and cannot count as command completion. The fourth-platform bent march consumed substantial bounded proposal work (1,547,608 cumulative structural expansions at 500 seconds). Reducing that work and eliminating low-value repeated shears is the next focused implementation task; it must not discard the rear, remove captain guards, merge physically adequate rally platforms, or enlarge the deadline.

The D01 no-progress clock now exempts only the initial bounded planning phase. After physical marching begins, only actual commits refresh it; guide replanning does not. Its 503-second full-route ceiling and physical gate/rally oracles remain unchanged.

Still required: full D01 completion with all five actual rallies; its other dt schedules and 36 generated terrain/dt combinations; full G10 in-flight handoff matrix; all remaining legacy E/F/Q/M/X/C regressions; long-corridor and multiple-turn visual acceptance; GPU catch-up and all transaction sequences; real active CPU/frame-time percentile measurements. The 17 targeted headless passes, 2 limited GPU passes and editor startup check do not close S2–S4. No files have been staged or committed; unrelated working-tree changes remain untouched.

## Historical 18:20 retained version and checks

The following records describe the pre-subset version, not the current runtime. At 18:20 the unapproved serial-turn trial had been removed and these hashes were retained.

| File | SHA256 |
| --- | --- |
| `scripts/terrain_lab/terrain_army.gd` | `ec15b47d2df05c920a04926edb2bf7d6ac85938b8dc9e3b15a4a8d3e5134136f` |
| `scripts/terrain_lab/terrain_lab.gd` | `137ac1b6ad89715a4449a021e0e2a56b0de7cb12faa5ea78629b62f8aa1fff24` |
| `scripts/tests/terrain_army_formation_advance_test.gd` | `1bf6d7456d674907e05d1e55d8935d5aa33011392bd903f57f1951e4e97cd099` |
| `scripts/tests/terrain_army_default_edge_test.gd` | `d1d80d466a4dd0664fc42b6f0c712d1c99de63e91788c78ecf945e3e53538c8c` |
| `scripts/tests/terrain_lab_army_visual_test.gd` | `db28f91cb4219324c54fd0066b14243de9d7420a249eca65991d3aa9be45f0d7` |

All rows below used that exact runtime. Logs, exit code and environment records are under `.godot-temp/godot_verify/<run>/result.json`, `stdout.log` and `stderr.log`. Durations are real runner seconds, not game input time.

| Case | Result / exit | Run | Duration | Evidence boundary |
| --- | --- | --- | --- | --- |
| G01 | PASS / 0 | `20260910_181357_914` | 3.256 s | 100-person open march; 22.6 input s to complete, then stable 5 s |
| G02 | PASS / 0 | `20260910_181402_254` | 1.505 s | Rear RUN and collective movement resumes |
| G03 | PASS / 0 | `20260910_181404_824` | 1.788 s | More than 5 s waiting does not disable RUN after release |
| G04 | PASS / 0 | `20260910_181407_674` | 1.406 s | Same-direction atomic movement and command handoff checks |
| G05 | PASS / 0 | `20260910_181417_006` | 7.601 s | 100 crossed/cleared; captain 41st; complete at 105.8 input s |
| G06 | PASS / 0 | `20260910_181425_654` | 12.404 s | Both gates 100/100; physical middle rally and resumed collective movement; 196.8 input s |
| G07_MEDIUM | PASS / 0 | `20260910_181750_366` | 4.926 s | Straight five-wide opening, 11 narrow collective steps; not a bent terrace |
| G08 | PASS / 0 | `20260910_181756_362` | 5.115 s | Open-field 90-degree target change, 36 new collective steps and stable 5 s |
| G08_RETURN | PASS / 0 | `20260910_181802_548` | 5.858 s | Open-field 180-degree target change, 62 new collective steps and stable 5 s |
| G09 | PASS / 0 | `20260910_181809_471` | 3.345 s | Front reaches `(99,50)` while captain remains at `(95,50)` |
| G01 GPU | PASS / 0; seven images inspected | `20260910_181601_475` | 24.460 s | Actual D3D12 / RTX 5060 rendering, 31 per-frame position checks and final stable 5 s |
| D01 | **FAIL / 1** | `20260910_180416_564` | 36.548 s | Exceeded the predeclared 503 input s; receiving at fourth group, 72/99 local slots; not all five rallies completed |

Canonical runner: `C:/Users/Nekki/.codex/skills/godot-runtime-verify/scripts/verify_godot.ps1`, from the project root, with `-GodotExecutable C:/Users/Nekki/Godot_v4.6.2-stable_mono_win64/Godot_v4.6.2-stable_mono_win64_console.exe`, `-Mode headless`, and `-GodotArguments @('--script','res://scripts/tests/terrain_army_formation_advance_test.gd','--','--case=G01')`; substitute the selected case. D01 uses `terrain_army_default_edge_test.gd` without case arguments, with a 45-second process bound. GPU uses `-Mode visual` and `terrain_lab_army_visual_test.gd -- --case=G01`. Godot reports `4.6.2.stable.mono.official.71f334935`.

First actionable D01 error: `default EDGE missed declared 503-second deadline: frame=-1 status=LOCAL_PASSAGE / RECEIVING | group 4-4 | local settled 72/99 | legal lag 10 (unknown 0) assembled=72`. This was an assertion failure, not a process timeout. The root-certificate warning is environment noise on the exit-0 passes. D01 also reports cleanup leaks after its failed assertion; it is not a clean run.

Current GPU outputs are in `.visual_captures/terrain_lab/v6/ec15b47d2df0/`: `G01_march_frame_00.png`, `06`, `12`, `18`, `24`, `30`, `G01_final_100_settled.png` and `G01_metadata.json`. All seven were freshly written and visually inspected: the body stays rectangular, the captain is inside, and front goal / guide / captain local slot are distinct. The old S1 images were not overwritten. The unimplemented GPU G02 alias was removed rather than letting an ordinary G01 replay impersonate catch-up evidence. Frame/CPU P95/P99 are **not measured by this capture**.

## Historical design question, subsequently approved

D01 now independently witnesses every actual 100-person rally, so a connected bent platform cannot be silently merged away. Its rigid receiving footprint cannot follow every subsequent curved terrace. Current fallback starts individual approach too far from the next mouth, and the protected captain waits remotely while front guards traverse the long leg. Outlet layouts also still need validation on the remaining groups.

A trial one-edge downhill local reshape preserved legal moves, owner/claim safety and a connected intended body after detached-branch rejection. However, serial source-vacating chains made repeated bends too slow; the final trial still had only two gates completed at 503 s. That entire trial, its flag and scheduler branches were removed, restoring the exact `ec15b47d2df0...` runtime before the passes above. It is not left enabled or presented as a fix.

**At 18:20 this was proposed, not implemented:** permit a bounded same-direction *subset* of the army to share the existing atomic move/claim boundary while rounding a terrace, with unrelated occupants excluded and physical gate admission remaining individual. The user approved this change at 18:57; the current implementation and limited acceptance are recorded above. That approval did not authorize mixed-direction transactions, relaxed captain order, teleportation, or an increased failed deadline.

Still outstanding: D01's five physical rallies and completion, bent-corridor acceptance, G10's full handoff matrix, all legacy W/E/F/Q/M/X/C cases on this source, 36 generated terrain/dt combinations, catch-up/passages/turn/transaction GPU sequences, and real activity performance. These remain required before full V6 completion.

## Predeclared timing budget (before intermediate-group implementation)

MOVE=0.24 s, RUN=0.18 s and simulation=0.10 s are unchanged. A WALK edge commits after three fixed steps (0.30 s). With the existing individual owner/vacate rule, a one-cell throat admits a new person every two committed edges (0.60 s). The single-gate V6 counterexample replay confirms that interval; captain is now the 41st crossing, not a scout.

For a route of L edges and K mandatory full-team rally groups, use this engineering deadline before testing a new grouped route:

`T = 0.30 * L + 0.60 * 99 * K + 20 * (K + 1) + structural_work / (256 * input_hz)`

- L and K must come from the published terrain route and proven legal rally layouts, never be chosen from the measured finish time.
- The 20 s per setup/rally allowance covers a 10x10 body's 18-edge diameter (5.4 s), two bounded route service rounds for 100 members (5.0 s), a ten-member vacancy chain (3.0 s), and scheduling/identity repair margin (6.6 s).
- Structural work is charged from actual completed pre-movement planning, once; replanning cannot keep extending the deadline. This is an explicit planning allowance, not a physical-progress exemption.
- The old D01/generated 180 s and F01 20 s results are retained as V5 references. A V6 miss is not converted to PASS by silently increasing those constants. Report measured time against both the old deadline and this predeclared budget.
- Full-team grouping deliberately removes inter-group pipelining. Five one-cell groups alone require about 297 s of admission intervals, before travel and regrouping; the previous 180 s target cannot in general coexist with five mandatory full-team regroups.
- The five-second local no-progress failure and all owner/claim/legal-edge checks still apply. Expected external waiting is recorded separately.

## Historical S0–S3 evidence boundary (not current-source closure)

- S0: old flat march failed captain coverage at 8 s (0 guards ahead / 99 behind); old single gate crossed captain first.
- S1: open 100-person collective WALK, lagging RUN, >5 s blocked/released RUN, in-flight batch command handoff, and formation-front EDGE have targeted headless passes. This is not yet the final-source matrix.
- S1 GPU: seven newly rendered flat-march images plus per-frame owner/claim, stable-offset and ground-position checks; inspected middle-of-step and settled images show a 10x10 body with the captain inside.
- S2: single gate G05 and large-platform G06 have 100-person physical crossing/clearance, captain middle-order, receiving RUN, actual middle rally and resumed collective steps. Narrower rectangular layouts are now considered on intermediate platforms. Small-platform and initial downstream exemption regressions have earlier targeted passes; rerun on the final source is still required.
- D01 targeted replay: source `5d5061d55864b7a596683f257c7130053f7bddd6baeef53a650a49465392d208`, run `20260910_171751_212`, headless exit 0. Completion 418.0 input seconds + stable 5 seconds; five physical/runtime ordinary-soldier counters all 99; front `(99,75)`, captain in the interior final slot. Predeclared 503 s budget met; V5 180 s reference missed. The old log label `V5_PASS` has not yet been renamed and does not imply unchanged V5 captain semantics. Captain per-gate order, actual intermediate-layout witnesses, other dt sequences and GPU remain to be strengthened.
- D01 fix evidence: the shared guide now searches legal whole-footprint translations on each platform, using the same 256/frame budget and existing consumable route. Near receiving layouts use legal exit distances and retain a wider body within the six-cell local reform radius; front guards are assigned first, with each half filled far-to-near. Exit-clear vacancy chains receive priority over unrelated shorter upstream pushes.
- The five-second receiving oracle now counts a new best fixed-goal approach or a new directed physical edge in an active outlet vacancy chain. Remote movement, interpolation and repeating the same directed edge do not refresh it. Initial bounded planning is classified separately. Checks still run through public `advance_frame`; gate accounting is evaluated at fixed-step commits while ownership remains checked every input frame.
- E11 capacity: source `38f12eadbbe094954fc895b6959d85df4773189db2716a495f805697213898ea`, run `20260910_171933_417`, headless exit 0. Available 60 receiving cells, requires 100; zero partial admissions, no captain scout, no residual moves/claims. The conflicting old assertion that captain must arrive despite insufficient capacity was replaced.
- Later S2/S3 targeted checks: terminal flat branch now puts an ordinary front soldier at the sole boundary with the captain inside; 29.2 s plus stable 5 s (`20260910_173024_801`). Terminal height-change capacity rejection also passed without any partial scout admission. E03 flat boundary passed at 116.9 s. G08 90-degree and 180-degree command turns passed with physical front/rear coverage and stable completion. These runs precede subsequent source changes.
- A five-wide flat opening now supports a real five-column collective body before expanding back to ten columns; targeted G07_MEDIUM passed with 11 narrow collective steps and 5 s stability (`20260910_174038_448`). This is not a claim for every medium-width bent corridor.
- HUD now separates front goal, guide and captain activity slot. Catch-up uses cached legal routes or a bounded short-path verification; an unknown distance is explicit rather than treating a wall-adjacent goal as caught up.
- Stronger D01 validation exposed that the earlier 418 s run only regrouped at three of five platforms. That run is **not full V6 acceptance**. Two bent platforms now have a connected-layout fallback, but current D01 still fails the stronger progress/deadline checks while receiving orientation is being corrected. Do not claim D01 closure or silently extend its predeclared 503 s budget.
- Full regression matrix, final-source GPU and activity performance remain outstanding. This is not acceptance closure.

No files have been staged or committed. Do not mark the V6 plan complete until S2–S4 finish.
