// Pure queries over the original roster and full per-member cursor projection.
// Included after movement_core.inc; no owner mutation or retained person data.
MValue mp_float(double number_value) {
    MValue result; destroy(result.ptr()); from_float(result.ptr(), &number_value); return result;
}
bool mp_step(const MTerrain &terrain, MCell from, MCell to) {
    for (int d = 0; d < 4; ++d) if (to - from == mdirections[d]) return terrain.step(from, to, d);
    return false;
}
void call_movement_roster(void *mode, GDExtensionClassInstancePtr instance,
        const GDExtensionConstVariantPtr *args, GDExtensionInt argc,
        GDExtensionVariantPtr result, GDExtensionCallError *error) {
    *error = {GDEXTENSION_CALL_OK, 0, 0}; reset_variant(result, DICT);
    if (argc != 5 || type_of(args[0]) != ARRAY || type_of(args[1]) != ARRAY ||
            type_of(args[2]) != DICT || type_of(args[3]) != INT || type_of(args[4]) != V2I) return;
    const int64_t operation = mint(args[3]), count = msize(args[0]);
    if (operation < 0 || operation > 2 || count != msize(args[1]) || count > 100000) return;
    HotStore *store = mode == &movement_hot_marker ? static_cast<HotStore *>(instance) : nullptr;
    if (store && hot_row_count(store) != count) return;
    MValue ids(ARRAY), occupancy(DICT); int64_t sum_x = 0, sum_y = 0, admitted = 0;
    for (int64_t i = 0; i < count; ++i) {
        void *row = const_cast<void *>(mat(args[0], i)); const void *cell_value = mat(args[1], i);
        if (type_of(row) != DICT || type_of(cell_value) != V2I) return;
        ReadField exited(row, SITE_EXITED, store, i);
        bool exited_flag;
        if (!optional_bool(exited.get(), exited_flag)) return;
        if (exited_flag) continue;
        const MCell cell = mxy(cell_value); ReadField identity(row, PERSON_ID);
        if (!identity.get() || type_of(identity.get()) != INT) return;
        if (operation == 2) {
            const void *owner = mget(args[2], MValue(cell_value));
            if (owner && type_of(owner) != INT) return;
            if (owner && mint(owner) == i) mput(occupancy.ptr(), MValue(identity.get()), MValue(cell_value));
            continue;
        }
        bool valid = true;
        const bool active = mmember(row, store, i, valid) && mcan_act(row, store, i, valid);
        const void *dead = mget(row, "dead");
        if (!valid || (dead && type_of(dead) != BOOL)) return;
        if (!active || mbool(dead)) continue;
        if (operation == 0) mappend(ids.ptr(), MValue(identity.get()));
        sum_x += cell.x; sum_y += cell.y; ++admitted;
    }
    if (operation == 0) mput(result, "value", ids);
    else if (operation == 2) mput(result, "value", occupancy);
    else {
        const MCell center = admitted ? MCell{static_cast<int32_t>(std::round(double(sum_x) / double(admitted))),
            static_cast<int32_t>(std::round(double(sum_y) / double(admitted)))} : mxy(args[4]);
        mput(result, "value", mcell(center));
    }
}

void call_movement_projection(void *, GDExtensionClassInstancePtr,
        const GDExtensionConstVariantPtr *args, GDExtensionInt argc,
        GDExtensionVariantPtr result, GDExtensionCallError *error) {
    *error = {GDEXTENSION_CALL_OK, 0, 0}; reset_variant(result, DICT);
    if (argc != 5 || type_of(args[0]) != OBJECT || type_of(args[1]) != ARRAY ||
            type_of(args[2]) != DICT || type_of(args[3]) != ARRAY || type_of(args[4]) != BOOL) return;
    MTerrain terrain; if (!terrain.load(args[3])) return;
    MProperties plan(args[0]); const void *path = plan.get("macro_path");
    const int64_t path_size = msize(path), current = mint(plan.get("macro_cursor")), count = msize(args[1]);
    if (path_size < 1 || path_size > 100000 || current < 0 || current >= path_size || count > 100000) return;
    for (int64_t k = 0; k < path_size; ++k) if (type_of(mat(path, k)) != V2I || !terrain.inside(mxy(mat(path, k)))) return;
    constexpr const char *fields[] = {"member_checkpoint_cell", "member_checkpoint_path_k", "member_checkpoint_best_k",
        "member_observed_path_s", "member_best_path_s", "member_observed_path_k", "member_best_path_k", "member_projected_path_k"};
    MValue maps[8];
    for (int index = 0; index < 8; ++index) {
        const void *original = plan.get(fields[index]); if (!original || type_of(original) != DICT) return;
        maps[index] = mcall(original, "duplicate"); if (type_of(maps[index].ptr()) != DICT) return;
    }
    for (const char *field : {"pre_route_staging_slots", "member_transit_slots", "member_path_s", "member_paths"})
        if (type_of(plan.get(field)) != DICT) return;
    const int64_t max_search = std::min(path_size - 1, current + 3), phase = mint(plan.get("phase"));
    const bool same_projection = mbool(args[4]); MValue flow(ARRAY); std::unordered_set<int64_t> seen;
    for (int64_t index = 0; index < count; ++index) {
        const void *id_value = mat(args[1], index); if (!id_value || type_of(id_value) != INT || !seen.insert(mint(id_value)).second) return;
        MValue id(id_value); const void *cell_value = mget(args[2], id); if (!cell_value) continue;
        if (type_of(cell_value) != V2I) return;
        const MCell cell = mxy(cell_value), checkpoint = mxy(mget(maps[0].ptr(), id)); double observed = 0.0;
        const void *prior_observed = mget(maps[3].ptr(), id);
        if ((phase == 0 || phase == 1) && same_projection && cell == checkpoint && prior_observed) observed = mnum(prior_observed);
        else {
            const int64_t previous = mint(mget(maps[5].ptr(), id));
            if (previous < 0 || previous >= path_size) return;
            const int64_t lower = std::max(int64_t(0), std::min(previous - 8, current - 4));
            const int64_t upper = std::min(path_size - 1, std::max(max_search, previous + 4));
            int64_t best_k = previous; int best_distance = 999999;
            const auto scan = [&](int64_t begin, int64_t end) {
                for (int64_t k = begin; k <= end; ++k) {
                    const int distance = mdistance(mxy(mat(path, k)), cell);
                    if (distance < best_distance && distance <= 3) { best_distance = distance; best_k = k; }
                }
            };
            scan(lower, upper);
            if (best_distance > 3) scan(0, std::min(path_size - 1, max_search + 4));
            if (best_distance > 3) best_k = std::min(previous, current);
            const bool near = best_distance == 0 || (best_distance == 1 && mp_step(terrain, cell, mxy(mat(path, best_k))));
            if (checkpoint == MCell{}) {
                mput(maps[0].ptr(), id, MValue(cell_value));
                mput(maps[1].ptr(), id, MValue(near ? best_k : int64_t(0)));
                mput(maps[2].ptr(), id, MValue(mget(maps[1].ptr(), id)));
            } else if (cell != checkpoint) {
                mput(maps[0].ptr(), id, MValue(cell_value));
                if (near && mp_step(terrain, checkpoint, cell)) {
                    const int64_t next = std::min(best_k, mint(mget(maps[1].ptr(), id)) + 1);
                    mput(maps[1].ptr(), id, MValue(next));
                    mput(maps[2].ptr(), id, MValue(std::max(mint(mget(maps[2].ptr(), id)), next)));
                }
            }
            observed = double(best_k);
            const bool staging = mget(plan.get("pre_route_staging_slots"), id) != nullptr;
            const MCell slot = mxy(mget(plan.get("member_transit_slots"), id));
            const double assigned = mnum(mget(plan.get("member_path_s"), id), -1.0);
            if (!staging && slot != MCell{} && assigned >= 0.0) {
                if (cell == slot) observed = std::max(observed, assigned);
                else if (const void *route = mget(plan.get("member_paths"), id)) {
                    if (type_of(route) != ARRAY) return;
                    const int64_t length = msize(route);
                    if (length >= 1 && mxy(mat(route, 0)) == cell && mxy(mat(route, length - 1)) == slot)
                        observed = std::max(observed, assigned - double(length - 1));
                }
            }
        }
        if (!std::isfinite(observed)) return;
        observed = std::max(0.0, std::min(observed, double(path_size - 1)));
        const int64_t observed_k = static_cast<int64_t>(std::floor(observed));
        mput(maps[3].ptr(), id, mp_float(observed));
        mput(maps[4].ptr(), id, mp_float(std::max(mnum(mget(maps[4].ptr(), id), observed), observed)));
        mput(maps[5].ptr(), id, MValue(observed_k));
        mput(maps[6].ptr(), id, MValue(std::max(mint(mget(maps[6].ptr(), id)), observed_k)));
        mput(maps[7].ptr(), id, MValue(observed_k)); mappend(flow.ptr(), MValue(observed_k));
    }
    // Publish only after every row passed validation; GDScript applies once.
    for (int index = 0; index < 8; ++index) mput(result, fields[index], maps[index]);
    mput(result, "flow_projected_k", flow);
}
