using Godot;
using System;
using System.Collections.Generic;
using System.Diagnostics;
using GArray = Godot.Collections.Array;
using GDictionary = Godot.Collections.Dictionary;

// One opt-in, sequential Source query island. The caller supplies only original
// cache misses in their original order; this class owns no person/time/cache.
public partial class compiled_contact_batch : RefCounted
{
    private compiled_contact_pose? _pose;
    private readonly List<compiled_contact_shapes> _views = new();
    private readonly List<int[]> _usedMorphs = new();
    private string[] _morphNames = Array.Empty<string>();
    private bool _compiled;
    private bool _poisoned;
    private bool _profileEnabled;
    private long _poseTicks, _geometryTicks, _armorTicks, _sampleCalls, _requestCount;

    // Test-only stage measurement; disabled during uninstrumented throughput runs.
    public void SetProfiling(bool enabled)
    {
        _profileEnabled = enabled;
        _poseTicks = _geometryTicks = _armorTicks = _sampleCalls = _requestCount = 0;
    }

    public GDictionary ReadProfile() => new()
    {
        ["pose_usec"] = _poseTicks * 1000000.0 / Stopwatch.Frequency,
        ["geometry_usec"] = _geometryTicks * 1000000.0 / Stopwatch.Frequency,
        ["armor_usec"] = _armorTicks * 1000000.0 / Stopwatch.Frequency,
        ["sample_calls"] = _sampleCalls, ["request_count"] = _requestCount
    };

    public GDictionary Compile(GDictionary poseDescriptor, GArray viewDescriptors)
    {
        Clear();
        try
        {
            if (viewDescriptors.Count == 0) throw new ArgumentException("At least one original view descriptor is required.");
            _morphNames = Read(poseDescriptor, "morph_names", Variant.Type.PackedStringArray).AsStringArray();
            var indices = new Dictionary<string, int>(StringComparer.Ordinal);
            for (int i = 0; i < _morphNames.Length; i++) indices.Add(_morphNames[i], i);
            var requiredMorphs = new bool[_morphNames.Length];
            for (int viewIndex = 0; viewIndex < viewDescriptors.Count; viewIndex++)
            {
                if (viewDescriptors[viewIndex].VariantType != Variant.Type.Dictionary)
                    throw new ArgumentException("view_descriptor_type:" + viewIndex);
                var descriptor = viewDescriptors[viewIndex].AsGodotDictionary();
                var names = Read(descriptor, "used_morph_names", Variant.Type.PackedStringArray).AsStringArray();
                var used = new List<int>();
                var seen = new HashSet<int>();
                foreach (string name in names)
                {
                    if (!indices.TryGetValue(name, out int morph))
                        throw new ArgumentException("unknown_view_morph:" + viewIndex + ":" + name);
                    requiredMorphs[morph] = true;
                    if (seen.Add(morph)) used.Add(morph);
                }
                var view = new compiled_contact_shapes();
                _views.Add(view); // Own it before Compile, including its failure path.
                var viewResult = view.Compile(descriptor);
                if (!Succeeded(viewResult)) throw new ArgumentException("view:" + viewIndex + ":" + Detail(viewResult));
                _usedMorphs.Add(used.ToArray());
            }
            // A fixed union across ALL registered views preserves A -> absent -> A
            // morph history. Never change the mask on individual view requests.
            var union = new List<int>();
            for (int morph = 0; morph < requiredMorphs.Length; morph++) if (requiredMorphs[morph]) union.Add(morph);
            using var maskedDescriptor = poseDescriptor.Duplicate();
            maskedDescriptor["required_morph_indices"] = union.ToArray();
            _pose = new compiled_contact_pose();
            var poseResult = _pose.Compile(maskedDescriptor);
            if (!Succeeded(poseResult)) throw new ArgumentException("pose: " + Detail(poseResult));
            _compiled = true;
            return new GDictionary
            {
                ["ok"] = true, ["view_count"] = _views.Count, ["morph_count"] = _morphNames.Length,
                ["morph_union_count"] = union.Count, ["tracks_raw"] = poseResult["tracks_raw"],
                ["tracks_original"] = poseResult["tracks_original"], ["tracks_retained"] = poseResult["tracks_retained"],
                ["track_counts_by_clip"] = poseResult["track_counts_by_clip"]
            };
        }
        catch (Exception error)
        {
            Clear();
            return Failure("batch_descriptor_rejected", error.Message);
        }
    }

    // Per request: view, clip, time, include_weapon. Optional morph_indices and
    // morph_values are original appearance/cloth writes immediately BEFORE seek;
    // the pose helper then applies the original clip-change/reset/track history.
    // Optional armor_queries are {point:Vector2, kind:String/StringName} in order.
    // Each result contains the original EvaluateBones fields, effective_time,
    // and (only when requested) armor:PackedVector2Array of protection results.
    public GDictionary SampleBatch(GArray requests)
    {
        if (!_compiled || _pose == null) return Failure("not_compiled", "Compile must succeed first.");
        if (_poisoned) return Failure("batch_poisoned", "A failed batch requires Reset or Compile before further sampling.");
        if (_profileEnabled) _sampleCalls++;
        var results = new GArray();
        int requestIndex = 0;
        try
        {
            for (; requestIndex < requests.Count; requestIndex++)
            {
                if (requests[requestIndex].VariantType != Variant.Type.Dictionary)
                    throw new ArgumentException("request_type");
                var request = requests[requestIndex].AsGodotDictionary();
                int viewIndex = Read(request, "view", Variant.Type.Int).AsInt32();
                if (viewIndex < 0 || viewIndex >= _views.Count) throw new ArgumentException("view_index");
                var clipValue = ReadName(request, "clip");
                var clip = new StringName(clipValue);
                double time = ReadNumber(request, "time");
                if (!double.IsFinite(time)) throw new ArgumentException("nonfinite_time");
                bool includeWeapon = Read(request, "include_weapon", Variant.Type.Bool).AsBool();

                bool updateMorphs = request.ContainsKey("morph_indices") || request.ContainsKey("morph_values");
                int[] morphIndices = updateMorphs ? Read(request, "morph_indices", Variant.Type.PackedInt32Array).AsInt32Array() : Array.Empty<int>();
                float[] morphValues = updateMorphs ? Read(request, "morph_values", Variant.Type.PackedFloat32Array).AsFloat32Array() : Array.Empty<float>();
                if (morphIndices.Length != morphValues.Length) throw new ArgumentException("morph_update_lengths");
                for (int i = 0; i < morphIndices.Length; i++)
                    if (morphIndices[i] < 0 || morphIndices[i] >= _morphNames.Length || !float.IsFinite(morphValues[i]))
                        throw new ArgumentException("morph_update_value");

                bool armorRequested = request.ContainsKey("armor_queries");
                var armorQueries = armorRequested ? Read(request, "armor_queries", Variant.Type.Array).AsGodotArray() : null;
                var armorPoints = new Vector2[armorQueries?.Count ?? 0];
                var armorKinds = new string[armorPoints.Length];
                for (int i = 0; i < armorPoints.Length; i++)
                {
                    if (armorQueries![i].VariantType != Variant.Type.Dictionary) throw new ArgumentException("armor_query_type");
                    var query = armorQueries[i].AsGodotDictionary();
                    armorPoints[i] = Read(query, "point", Variant.Type.Vector2).AsVector2();
                    if (!armorPoints[i].IsFinite()) throw new ArgumentException("armor_point_nonfinite");
                    armorKinds[i] = ReadName(query, "kind");
                }

                if (updateMorphs)
                {
                    var update = _pose.ApplyMorphUpdates(morphIndices, morphValues);
                    if (!Succeeded(update)) throw new InvalidOperationException("morph_update:" + Detail(update));
                }
                long stageStarted = _profileEnabled ? Stopwatch.GetTimestamp() : 0;
                if (!_pose.TrySamplePose(clip, time, out compiled_contact_pose.PoseFrame? frame, out string poseError))
                    throw new InvalidOperationException("pose:" + poseError);
                if (_profileEnabled) { _poseTicks += Stopwatch.GetTimestamp() - stageStarted; _requestCount++; }
                foreach (int morph in _usedMorphs[viewIndex])
                {
                    // Preserve TerrainWeaponCollision's actual native-bake gate.
                    // Never pretend a nonzero active geometry morph is zero.
                    if (Math.Abs((double)frame.Morphs[morph]) > 0.0001)
                        return Poison(results, requestIndex, "unsupported_geometry_morph", _morphNames[morph]);
                }
                var view = _views[viewIndex];
                stageStarted = _profileEnabled ? Stopwatch.GetTimestamp() : 0;
                var geometry = view.EvaluateBones(frame.Global, includeWeapon);
                if (_profileEnabled) _geometryTicks += Stopwatch.GetTimestamp() - stageStarted;
                if (!Succeeded(geometry)) throw new InvalidOperationException("geometry:" + Detail(geometry));
                geometry["effective_time"] = frame.EffectiveTime;
                if (armorRequested)
                {
                    stageStarted = _profileEnabled ? Stopwatch.GetTimestamp() : 0;
                    var protection = new Vector2[armorPoints.Length];
                    for (int i = 0; i < protection.Length; i++)
                    {
                        var armor = view.ArmorAtBones(frame.Global, armorPoints[i], armorKinds[i]);
                        if (!Succeeded(armor)) throw new InvalidOperationException("armor:" + Detail(armor));
                        protection[i] = armor["protection"].AsVector2();
                    }
                    geometry["armor"] = protection;
                    if (_profileEnabled) _armorTicks += Stopwatch.GetTimestamp() - stageStarted;
                }
                results.Add(geometry);
            }
            return new GDictionary { ["ok"] = true, ["results"] = results };
        }
        catch (Exception error)
        {
            return Poison(results, requestIndex, "batch_sample_rejected", error.Message);
        }
    }

    public GDictionary Reset()
    {
        if (!_compiled || _pose == null) return Failure("not_compiled", "Compile must succeed first.");
        var result = _pose.Reset();
        _poisoned = !Succeeded(result);
        return result;
    }

    public void Clear()
    {
        _compiled = false;
        _poisoned = false;
        SetProfiling(false);
        _pose?.Dispose();
        _pose = null;
        foreach (var view in _views) view.Dispose();
        _views.Clear();
        _usedMorphs.Clear();
        _morphNames = Array.Empty<string>();
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing) Clear();
        base.Dispose(disposing);
    }

    private GDictionary Poison(GArray partialResults, int requestIndex, string code, string error)
    {
        // Earlier requests may have advanced the one original pose history.
        // Drop the entire result prefix and forbid silent continuation/fallback.
        _poisoned = true;
        partialResults.Dispose();
        var result = Failure(code, error);
        result["failed_index"] = requestIndex;
        result["requires_reset"] = true;
        return result;
    }

    private static bool Succeeded(GDictionary result) => result.TryGetValue("ok", out Variant ok) && ok.VariantType == Variant.Type.Bool && ok.AsBool();
    private static string Detail(GDictionary result) => result.TryGetValue("error", out Variant error) ? error.AsString() : "helper_rejected";
    private static GDictionary Failure(string code, string error) => new() { ["ok"] = false, ["code"] = code, ["error"] = error };

    private static Variant Read(GDictionary value, string key, Variant.Type type)
    {
        if (!value.TryGetValue(key, out Variant field) || field.VariantType != type) throw new ArgumentException("field:" + key);
        return field;
    }

    private static string ReadName(GDictionary value, string key)
    {
        if (!value.TryGetValue(key, out Variant field) || (field.VariantType != Variant.Type.String && field.VariantType != Variant.Type.StringName))
            throw new ArgumentException("field:" + key);
        return field.AsString();
    }

    private static double ReadNumber(GDictionary value, string key)
    {
        if (!value.TryGetValue(key, out Variant field) || (field.VariantType != Variant.Type.Float && field.VariantType != Variant.Type.Int))
            throw new ArgumentException("field:" + key);
        return field.AsDouble();
    }
}
