using Godot;
using System;
using System.Collections.Generic;
using GArray = Godot.Collections.Array;
using GDict = Godot.Collections.Dictionary;

// Private acceleration of TerrainLab's existing post-advance contact batch.
// No actors, terrain, time, HP, RNG, or animation state is owned here.
public partial class compiled_contact_query : RefCounted
{
    private sealed class Target
    {
        public Vector2[][] Body = Array.Empty<Vector2[]>(), Shield = Array.Empty<Vector2[]>(), Parry = Array.Empty<Vector2[]>();
        public Rect2 Bounds;
        public Vector2 Ground;
        public double Radius;
        public long Team, Identity, Faction;
        public int Unit;
        public bool Army, Enabled;
        public Variant Owner;
    }

    private sealed class Sweep
    {
        public Vector2[] Before = Array.Empty<Vector2>(), Shape = Array.Empty<Vector2>(), Full = Array.Empty<Vector2>();
        public Rect2 Bounds;
        // Eight original bisections only visit dyadic multiples of 1/256.
        public Vector2[]?[]? Partials;
    }

    private sealed class Hit
    {
        public double Fraction;
        public int Body;
        public Vector2 Point;
        public bool Shield;
        public string Kind = "body";
    }

    private Target[] _targets = Array.Empty<Target>();
    private RefCounted? _sortBridge;

    private RefCounted SortBridge()
    {
        if (_sortBridge != null) return _sortBridge;
        // GodotSharp Array does not expose native sort_custom. Keep the exact
        // original engine sort through this tiny pure-data bridge instead of
        // replacing its behaviour with .NET sorting for a non-transitive tie rule.
        var script = new GDScript { SourceCode = "extends RefCounted\nfunc sort_contacts(values: Array, comparer: Callable) -> void:\n\tvalues.sort_custom(comparer)\n" };
        if (script.Reload() != Error.Ok)
            throw new ArgumentException("Cannot initialize original native contact sorting.");
        _sortBridge = (RefCounted)script.Call("new").AsGodotObject();
        return _sortBridge;
    }

    // Rows are in original Army/team/index order followed by original Actors.
    // Required: body/shield/parry (Array[PackedVector2Array]), bounds, identity,
    // faction. Army rows additionally have team_key, target_unit, ground,
    // anchor_radius. Optional target is the original owner reference, never a copy.
    // Conversion makes a private geometry snapshot once, not once per attacker.
    public GDict SetTargets(GArray rows)
    {
        _targets = Array.Empty<Target>(); // Invalid input must not retain an old step.
        try
        {
            var targets = new Target[rows.Count];
            for (int i = 0; i < rows.Count; i++)
            {
                var row = rows[i].AsGodotDictionary();
                var unit = row.ContainsKey("target_unit") ? row["target_unit"].AsInt32() : -1;
                bool army = row.ContainsKey("is_army") ? row["is_army"].AsBool() : unit >= 0;
                targets[i] = new Target
                {
                    Body = ReadShapes(row["body"].AsGodotArray()),
                    Shield = ReadShapes(row["shield"].AsGodotArray()),
                    Parry = ReadShapes(row["parry"].AsGodotArray()),
                    Bounds = row["bounds"].AsRect2(),
                    Identity = row["identity"].AsInt64(),
                    Faction = row["faction"].AsInt64(),
                    Team = army ? row["team_key"].AsInt64() : -1,
                    Unit = unit,
                    Army = army,
                    Ground = army ? row["ground"].AsVector2() : Vector2.Zero,
                    Radius = army ? row["anchor_radius"].AsDouble() : 256.0,
                    Enabled = !row.ContainsKey("enabled") || row["enabled"].AsBool(),
                    Owner = row.ContainsKey("target") ? row["target"] : default,
                };
            }
            _targets = targets;
            return new GDict { ["ok"] = true, ["target_count"] = targets.Length };
        }
        catch (Exception error) when (error is ArgumentException || error is InvalidCastException || error is KeyNotFoundException)
        {
            return Failure(error.Message);
        }
    }

    public void ClearTargets() => _targets = Array.Empty<Target>();

    // Jobs: previous/current, source_position, source_team_key, source_unit,
    // terrain_clear (PackedByteArray, one original terrain_line_clear result per
    // target). Optional ranged, strict_order, actor_bounds (default true),
    // excluded (original identity-key Dictionary), candidate_indices (original
    // ordered PackedInt32Array). No callbacks into game state during execution.
    // Returns {ok, results: Array[Array[Dictionary]]}; each result is a complete
    // original hit list, not damage/HP application or a reordered attack batch.
    public GDict RunBatch(GArray jobs)
    {
        var results = new GArray();
        try
        {
            foreach (Variant value in jobs)
                results.Add(RunJob(value.AsGodotDictionary()));
            return new GDict { ["ok"] = true, ["results"] = results };
        }
        catch (Exception error) when (error is ArgumentException || error is InvalidCastException || error is KeyNotFoundException || error is IndexOutOfRangeException)
        {
            results.Dispose();
            return Failure(error.Message);
        }
    }

    private GArray RunJob(GDict job)
    {
        var current = ReadShapes(job["current"].AsGodotArray());
        var hits = new GArray();
        if (current.Length == 0)
            return hits;
        if (current[0].Length == 0)
            throw new ArgumentException("The original current[0] must contain a vertex.");
        var previous = ReadShapes(job["previous"].AsGodotArray());
        var position = job["source_position"].AsVector2();
        long sourceTeam = job["source_team_key"].AsInt64();
        int sourceUnit = job["source_unit"].AsInt32();
        var terrain = job["terrain_clear"].AsByteArray();
        if (terrain.Length != _targets.Length)
            throw new ArgumentException("terrain_clear must match the current target snapshot.");
        bool ranged = job.ContainsKey("ranged") && job["ranged"].AsBool();
        bool strict = job.ContainsKey("strict_order") && job["strict_order"].AsBool();
        bool actorBounds = !job.ContainsKey("actor_bounds") || job["actor_bounds"].AsBool();
        int[]? candidates = job.ContainsKey("candidate_indices") ? job["candidate_indices"].AsInt32Array() : null;
        var excluded = new HashSet<long>();
        if (job.ContainsKey("excluded"))
            foreach (Variant identity in job["excluded"].AsGodotDictionary().Keys)
                excluded.Add(identity.AsInt64());

        var sweeps = PrepareSweeps(previous, current);
        var bounds = new Rect2(current[0][0], Vector2.Zero);
        foreach (var shape in previous)
            foreach (var vertex in shape)
                bounds = bounds.Expand(vertex);
        foreach (var shape in current)
            foreach (var vertex in shape)
                bounds = bounds.Expand(vertex);
        var anchors = bounds.Grow(256.0f);
        bounds = bounds.Grow(0.001f);
        bool finiteSweep = FiniteMap(bounds.Position) && FiniteMap(bounds.End);
        int count = candidates?.Length ?? _targets.Length;
        // Keep BOTH native sorts. Original _collect_army_contacts sorts armies,
        // then _collect_unit_contacts appends Actors and sorts the combined list.
        // The old approximate comparator is not transitive: List.Sort or a
        // single final sort can change the result even with the same comparator.
        Callable? comparer = null;
        for (int phase = 0; phase < 2; phase++)
        {
            for (int n = 0; n < count; n++)
            {
                int index = candidates == null ? n : candidates[n];
                var target = _targets[index];
                if (target.Army != (phase == 0) || !target.Enabled)
                    continue;
                if (target.Army)
                {
                    if (target.Team == sourceTeam && target.Unit == sourceUnit)
                        continue;
                    if (target.Unit != 0)
                    {
                        if (!anchors.HasPoint(target.Ground))
                            continue;
                        if (target.Radius < 256.0 && finiteSweep && FiniteMap(target.Ground) && !bounds.Grow((float)target.Radius).HasPoint(target.Ground))
                            continue;
                    }
                }
                if (excluded.Contains(target.Identity))
                    continue;
                if (target.Army)
                {
                    if (!bounds.Intersects(target.Bounds, true) || terrain[index] == 0)
                        continue;
                }
                else if (actorBounds)
                {
                    bool overlaps = false;
                    foreach (var sweep in sweeps)
                    {
                        if (sweep.Bounds.Intersects(target.Bounds, true))
                        {
                            overlaps = true;
                            break;
                        }
                    }
                    if (!overlaps)
                        continue;
                }
                var hit = PersonContact(sweeps, target.Body, target.Shield);
                if (!ranged)
                {
                    var parry = Contact(sweeps, target.Parry);
                    if (parry != null && (hit == null || parry.Fraction <= hit.Fraction))
                    {
                        hit = parry;
                        hit.Shield = true;
                        hit.Kind = "parry";
                    }
                }
                if (hit == null || (!target.Army && terrain[index] == 0))
                    continue;
                var result = new GDict
                {
                    ["fraction"] = hit.Fraction,
                    ["body"] = hit.Body,
                    ["point"] = hit.Point,
                    ["shield"] = hit.Shield,
                    ["block_kind"] = hit.Kind,
                };
                if (target.Owner.VariantType != Variant.Type.Nil)
                    result["target"] = target.Owner;
                if (target.Army)
                    result["target_unit"] = target.Unit;
                result["identity"] = target.Identity;
                result["faction"] = target.Faction;
                result["distance"] = (double)position.DistanceSquaredTo(hit.Point);
                hits.Add(result);
            }
            // Native sorting cannot invoke a comparator or change order for
            // zero/one element. Keep both original sorts when there is a choice.
            if (hits.Count > 1)
            {
                comparer ??= Callable.From<Variant, Variant, bool>((a, b) => Precedes(a.AsGodotDictionary(), b.AsGodotDictionary(), strict));
                SortBridge().Call("sort_contacts", hits, comparer.Value);
            }
        }
        return hits;
    }

    private static Sweep[] PrepareSweeps(Vector2[][] previous, Vector2[][] current)
    {
        var result = new Sweep[current.Length];
        for (int i = 0; i < current.Length; i++)
        {
            var shape = current[i];
            var before = i < previous.Length ? previous[i] : shape;
            var vertices = new Vector2[before.Length + shape.Length];
            before.CopyTo(vertices, 0);
            shape.CopyTo(vertices, before.Length);
            var full = Geometry2D.ConvexHull(vertices);
            result[i] = new Sweep { Before = before, Shape = shape, Full = full, Bounds = PolygonBounds(full).Grow(0.001f) };
        }
        return result;
    }

    private static Hit? PersonContact(Sweep[] sweeps, Vector2[][] bodies, Vector2[][] shields)
    {
        var body = Contact(sweeps, bodies);
        var shield = Contact(sweeps, shields);
        bool blocked = shield != null && (body == null || shield.Fraction <= body.Fraction);
        var hit = blocked ? shield : body;
        if (hit != null)
        {
            hit.Shield = blocked;
            hit.Kind = blocked ? "shield" : "body";
        }
        return hit;
    }

    private static Hit? Contact(Sweep[] sweeps, Vector2[][] bodies)
    {
        Hit? best = null;
        foreach (var sweep in sweeps)
        {
            for (int bodyIndex = 0; bodyIndex < bodies.Length; bodyIndex++)
            {
                var body = bodies[bodyIndex];
                if (!sweep.Bounds.Intersects(PolygonBounds(body), true))
                    continue;
                var intersection = FirstIntersection(sweep.Full, body);
                if (intersection == null)
                    continue;
                double fraction = 0.0;
                if (sweep.Before.Length == sweep.Shape.Length && FirstIntersection(sweep.Before, body) == null)
                {
                    var partials = sweep.Partials ??= new Vector2[256][];
                    double low = 0.0, high = 1.0;
                    for (int refinement = 0; refinement < 8; refinement++)
                    {
                        double middle = (low + high) * 0.5;
                        int key = (int)(middle * 256.0);
                        var partial = partials[key];
                        if (partial == null)
                        {
                            var vertices = new Vector2[sweep.Before.Length + sweep.Shape.Length];
                            sweep.Before.CopyTo(vertices, 0);
                            for (int vertex = 0; vertex < sweep.Shape.Length; vertex++)
                                vertices[sweep.Before.Length + vertex] = sweep.Before[vertex].Lerp(sweep.Shape[vertex], (float)middle);
                            partial = Geometry2D.ConvexHull(vertices);
                            partials[key] = partial;
                        }
                        var partialIntersection = FirstIntersection(partial, body);
                        if (partialIntersection == null)
                            low = middle;
                        else
                        {
                            high = middle;
                            intersection = partialIntersection;
                        }
                    }
                    fraction = high;
                }
                if (best != null && fraction >= best.Fraction)
                    continue;
                var point = Vector2.Zero;
                foreach (var vertex in intersection)
                    point += vertex;
                point /= intersection.Length;
                best = new Hit { Fraction = fraction, Body = bodyIndex, Point = point };
                if (fraction == 0.0)
                    return best;
            }
        }
        return best;
    }

    private static Vector2[]? FirstIntersection(Vector2[] a, Vector2[] b)
    {
        var intersections = Geometry2D.IntersectPolygons(a, b);
        return intersections.Count == 0 ? null : intersections[0];
    }

    private static Rect2 PolygonBounds(Vector2[] shape)
    {
        if (shape.Length == 0)
            return new Rect2();
        var result = new Rect2(shape[0], Vector2.Zero);
        foreach (var point in shape)
            result = result.Expand(point);
        return result;
    }

    private static bool Precedes(GDict a, GDict b, bool strict)
    {
        double af = a["fraction"].AsDouble(), bf = b["fraction"].AsDouble();
        double ad = a["distance"].AsDouble(), bd = b["distance"].AsDouble();
        if (!strict)
        {
            if (!EqualApprox(af, bf)) return af < bf;
            if (!EqualApprox(ad, bd)) return ad < bd;
        }
        else
        {
            if (double.IsNaN(af) != double.IsNaN(bf)) return !double.IsNaN(af);
            if (!double.IsNaN(af) && af != bf) return af < bf;
            if (double.IsNaN(ad) != double.IsNaN(bd)) return !double.IsNaN(ad);
            if (!double.IsNaN(ad) && ad != bd) return ad < bd;
        }
        return a["identity"].AsInt64() < b["identity"].AsInt64();
    }

    // GDScript calls core/math/math_funcs.h's double overload (CMP_EPSILON),
    // not GodotSharp Mathf.IsEqualApprox(double), which uses EpsilonD instead.
    private static bool EqualApprox(double a, double b)
    {
        if (a == b) return true;
        double tolerance = 0.00001 * Math.Abs(a);
        if (tolerance < 0.00001) tolerance = 0.00001;
        return Math.Abs(a - b) < tolerance;
    }

    private static bool FiniteMap(Vector2 point) => point.IsFinite() && Math.Max(Math.Abs(point.X), Math.Abs(point.Y)) <= 16384.0;

    private static Vector2[][] ReadShapes(GArray shapes)
    {
        var result = new Vector2[shapes.Count][];
        for (int i = 0; i < shapes.Count; i++)
            result[i] = shapes[i].AsVector2Array();
        return result;
    }

    private static GDict Failure(string message) => new GDict { ["ok"] = false, ["code"] = "INVALID_CONTACT_BATCH", ["message"] = message };
}
