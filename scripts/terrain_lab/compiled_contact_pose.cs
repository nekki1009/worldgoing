using Godot;
using System;
using System.Collections.Generic;
using System.Diagnostics.CodeAnalysis;
using GDictionary = Godot.Collections.Dictionary;
using GArray = Godot.Collections.Array;

// Experimental, single-source collision-pose evaluator. Compile snapshots resources;
// evaluation never reads a Node. This is NOT an AnimationPlayer replacement: only
// one full-weight, forward external seek, no capture/crossfade/root-motion/modifiers.
// Equipment/IK and admission of the complete Source query history belong to callers.
public partial class compiled_contact_pose : RefCounted
{
    internal sealed class PoseFrame
    {
        internal Vector3[] Positions;
        internal Quaternion[] Rotations;
        internal Vector3[] Scales;
        internal float[] Morphs;
        internal Transform3D[] Local;
        internal Transform3D[] Global;
        internal double EffectiveTime;

        internal PoseFrame(Vector3[] positions, Quaternion[] rotations, Vector3[] scales, float[] morphs)
        {
            Positions = (Vector3[])positions.Clone();
            Rotations = (Quaternion[])rotations.Clone();
            Scales = (Vector3[])scales.Clone();
            Morphs = (float[])morphs.Clone();
            Local = new Transform3D[positions.Length];
            Global = new Transform3D[positions.Length];
        }
    }

    private sealed class Clip
    {
        internal Animation Animation = null!;
        internal int[] Bones = Array.Empty<int>();
        internal int[] Morphs = Array.Empty<int>();
        internal int[] Tracks = Array.Empty<int>();
        internal Animation.TrackType[] Types = Array.Empty<Animation.TrackType>();
        internal bool[] ActiveBones = Array.Empty<bool>();
        internal int[] MixerMorphs = Array.Empty<int>();
    }

    private readonly Dictionary<string, Clip> _clips = new(StringComparer.Ordinal);
    private int[] _parents = Array.Empty<int>();
    private int[] _order = Array.Empty<int>();
    private int[] _channels = Array.Empty<int>();
    private int[] _resetMorphs = Array.Empty<int>();
    private int[] _sampleMorphs = Array.Empty<int>();
    private Transform3D[] _rest = Array.Empty<Transform3D>();
    private Vector3[] _mixerPositions = Array.Empty<Vector3>();
    private Quaternion[] _mixerRotations = Array.Empty<Quaternion>();
    private Vector3[] _mixerScales = Array.Empty<Vector3>();
    private float[] _mixerMorphs = Array.Empty<float>();
    private bool[] _morphChannels = Array.Empty<bool>();
    private PoseFrame? _initial;
    private PoseFrame? _state;
    private string _initialClip = "";
    private string _currentClip = "";
    private float _motionScale = 1.0f;
    private bool _deterministic;

    public GDictionary Compile(GDictionary descriptor)
    {
        Clear();
        if (descriptor == null) return Failure("descriptor_rejected", "null_descriptor");
        try
        {
            Require(Read(descriptor, "schema_version", Variant.Type.Int).AsInt32() == 1, "schema_version");
            string[] names = Read(descriptor, "bone_names", Variant.Type.PackedStringArray).AsStringArray();
            Require(names.Length > 0 && names.Length <= 512, "bone_count");
            Require(new HashSet<string>(names, StringComparer.Ordinal).Count == names.Length, "duplicate_bone_name");
            _parents = Read(descriptor, "parents", Variant.Type.PackedInt32Array).AsInt32Array();
            _rest = Transforms(Read(descriptor, "rest", Variant.Type.Array).AsGodotArray());
            Vector3[] positions = Read(descriptor, "initial_positions", Variant.Type.PackedVector3Array).AsVector3Array();
            Quaternion[] rotations = Quaternions(Read(descriptor, "initial_rotations", Variant.Type.Array).AsGodotArray());
            Vector3[] scales = Read(descriptor, "initial_scales", Variant.Type.PackedVector3Array).AsVector3Array();
            string[] morphNames = Read(descriptor, "morph_names", Variant.Type.PackedStringArray).AsStringArray();
            float[] morphs = Read(descriptor, "initial_morphs", Variant.Type.PackedFloat32Array).AsFloat32Array();
            Require(morphNames.Length == morphs.Length && morphs.Length <= 4096, "morph_count");
            Require(new HashSet<string>(morphNames, StringComparer.Ordinal).Count == morphNames.Length, "duplicate_morph_name");
            _mixerPositions = Read(descriptor, "mixer_positions", Variant.Type.PackedVector3Array).AsVector3Array();
            _mixerRotations = Quaternions(Read(descriptor, "mixer_rotations", Variant.Type.Array).AsGodotArray());
            _mixerScales = Read(descriptor, "mixer_scales", Variant.Type.PackedVector3Array).AsVector3Array();
            _mixerMorphs = Read(descriptor, "mixer_morphs", Variant.Type.PackedFloat32Array).AsFloat32Array();
            _morphChannels = new bool[morphs.Length];
            foreach (int index in Read(descriptor, "mixer_morph_channels", Variant.Type.PackedInt32Array).AsInt32Array())
            {
                Require(index >= 0 && index < morphs.Length, "mixer_morph_channel_index");
                _morphChannels[index] = true;
            }
            _channels = Read(descriptor, "mixer_channels", Variant.Type.PackedInt32Array).AsInt32Array();
            _resetMorphs = Read(descriptor, "reset_morphs", Variant.Type.PackedInt32Array).AsInt32Array();
            _motionScale = Number(descriptor, "motion_scale");
            _deterministic = Read(descriptor, "mixer_deterministic", Variant.Type.Bool).AsBool();
            Require(descriptor.TryGetValue("initial_clip", out Variant initialClip), "field:initial_clip");
            Require(initialClip.VariantType == Variant.Type.String || initialClip.VariantType == Variant.Type.StringName, "initial_clip");
            _initialClip = initialClip.AsString();
            int count = names.Length;
            Require(_parents.Length == count && _rest.Length == count && positions.Length == count && rotations.Length == count && scales.Length == count, "initial_bone_lengths");
            Require(_mixerPositions.Length == count && _mixerRotations.Length == count && _mixerScales.Length == count && _channels.Length == count, "mixer_bone_lengths");
            Require(_mixerMorphs.Length == morphs.Length && float.IsFinite(_motionScale) && _motionScale > 0.0f, "mixer_values");
            for (int i = 0; i < count; i++)
            {
                Require(_parents[i] >= -1 && _parents[i] < count && _parents[i] != i, "parent_index");
                Require(_channels[i] >= 0 && _channels[i] <= 7, "mixer_channels");
                Require(_rest[i].IsFinite() && positions[i].IsFinite() && scales[i].IsFinite() && rotations[i].IsFinite() && rotations[i].LengthSquared() > 0.0f, "initial_bone_nonfinite");
                Require(_mixerPositions[i].IsFinite() && _mixerScales[i].IsFinite() && _mixerRotations[i].IsFinite() && _mixerRotations[i].IsNormalized(), "mixer_bone_nonfinite_or_rotation");
            }
            foreach (int index in _resetMorphs) Require(index >= 0 && index < morphs.Length, "reset_morph_index");
            for (int i = 0; i < morphs.Length; i++) Require(float.IsFinite(morphs[i]) && float.IsFinite(_mixerMorphs[i]), "morph_nonfinite");
            // Optional fixed collision closure. Missing means the full oracle;
            // an explicit empty array means no morph is observable by any view.
            // Preserve original indices/storage and validate every original track.
            // Only the private evaluation lists are pruned, never Animation tracks.
            bool morphMasked = descriptor.ContainsKey("required_morph_indices");
            bool[] requiredMorphs = new bool[morphs.Length];
            if (morphMasked)
            {
                foreach (int index in Read(descriptor, "required_morph_indices", Variant.Type.PackedInt32Array).AsInt32Array())
                {
                    Require(index >= 0 && index < morphs.Length, "required_morph_index");
                    requiredMorphs[index] = true;
                }
            }
            else Array.Fill(requiredMorphs, true);
            List<int> sampleMorphs = new();
            for (int i = 0; i < requiredMorphs.Length; i++) if (requiredMorphs[i]) sampleMorphs.Add(i);
            _sampleMorphs = sampleMorphs.ToArray();
            List<int> resetMorphs = new();
            foreach (int index in _resetMorphs) if (requiredMorphs[index]) resetMorphs.Add(index);
            _resetMorphs = resetMorphs.ToArray();
            _order = ParentOrder(_parents);
            GDictionary sourceClips = Read(descriptor, "clips", Variant.Type.Dictionary).AsGodotDictionary();
            Require(sourceClips.Count > 0 && sourceClips.Count <= 128, "clip_count");
            int tracksRaw = 0;
            int tracksOriginal = 0;
            int tracksRetained = 0;
            GDictionary trackCounts = new();
            foreach (KeyValuePair<Variant, Variant> pair in sourceClips)
            {
                Require(pair.Key.VariantType == Variant.Type.String || pair.Key.VariantType == Variant.Type.StringName, "clip_name_type");
                Require(pair.Value.VariantType == Variant.Type.Dictionary, "clip_descriptor");
                string name = pair.Key.AsString();
                Require(name.Length > 0 && !_clips.ContainsKey(name), "duplicate_or_empty_clip");
                GDictionary value = pair.Value.AsGodotDictionary();
                Animation? original = Read(value, "animation", Variant.Type.Object).AsGodotObject() as Animation;
                Require(original != null && GodotObject.IsInstanceValid(original), "animation_resource");
                // Own the duplicate even if validation below fails; Clear releases it.
                Clip clip = new() { Animation = original.Duplicate(true) as Animation ?? throw new ArgumentException("animation_duplicate") };
                _clips.Add(name, clip);
                Require(clip.Animation != null && clip.Animation.GetScript().VariantType == Variant.Type.Nil, "scripted_animation");
                int tracks = clip.Animation.GetTrackCount();
                Require(tracks <= 8192 && double.IsFinite(clip.Animation.Length) && clip.Animation.Length > 0.0, "animation_size_or_length");
                clip.Bones = Read(value, "track_bones", Variant.Type.PackedInt32Array).AsInt32Array();
                clip.Morphs = Read(value, "track_morphs", Variant.Type.PackedInt32Array).AsInt32Array();
                Require(clip.Bones.Length == tracks && clip.Morphs.Length == tracks, "track_mapping_lengths");
                int[] ignored = Read(value, "ignore_tracks", Variant.Type.PackedInt32Array).AsInt32Array();
                HashSet<int> ignore = new(ignored);
                foreach (int track in ignore) Require(track >= 0 && track < tracks, "ignore_track_index");
                clip.ActiveBones = new bool[count];
                bool[] activeMorphs = new bool[morphs.Length];
                clip.Types = new Animation.TrackType[tracks];
                List<int> admitted = new();
                HashSet<(int, Animation.TrackType)> boneChannels = new();
                HashSet<int> morphChannels = new();
                int originalCount = 0;
                int originalMorphCount = 0;
                int retainedMorphCount = 0;
                for (int track = 0; track < tracks; track++)
                {
                    int bone = clip.Bones[track];
                    int morph = clip.Morphs[track];
                    Require(bone >= -1 && bone < count && morph >= -1 && morph < morphs.Length && (bone < 0 || morph < 0), "track_mapping_index");
                    if (!clip.Animation.TrackIsEnabled(track)) continue;
                    if (ignore.Contains(track))
                    {
                        Require(bone < 0 && morph < 0, "ignored_mapped_track");
                        continue; // Exporter must explicitly establish collision irrelevance.
                    }
                    Animation.TrackType type = clip.Animation.TrackGetType(track);
                    clip.Types[track] = type;
                    int channel = type == Animation.TrackType.Position3D ? 1 : type == Animation.TrackType.Rotation3D ? 2 : type == Animation.TrackType.Scale3D ? 4 : 0;
                    Require(clip.Animation.TrackGetKeyCount(track) > 0, "empty_enabled_track");
                    if (channel != 0)
                    {
                        Require(bone >= 0 && morph < 0 && (_channels[bone] & channel) != 0, "unmapped_bone_track");
                        Require(boneChannels.Add((bone, type)), "duplicate_bone_channel");
                        clip.ActiveBones[bone] = true;
                    }
                    else
                    {
                        Require(type == Animation.TrackType.BlendShape && morph >= 0 && bone < 0 && _morphChannels[morph], "unsupported_track:" + type);
                        Require(morphChannels.Add(morph), "duplicate_morph_channel");
                        activeMorphs[morph] = true;
                        originalMorphCount++;
                    }
                    originalCount++;
                    if (morph >= 0 && !requiredMorphs[morph]) continue;
                    if (morph >= 0) retainedMorphCount++;
                    admitted.Add(track);
                }
                clip.Tracks = admitted.ToArray();
                List<int> mixerMorphs = new();
                foreach (int morph in _sampleMorphs)
                    if ((_deterministic && _morphChannels[morph]) || activeMorphs[morph]) mixerMorphs.Add(morph);
                clip.MixerMorphs = mixerMorphs.ToArray();
                tracksRaw += tracks;
                tracksOriginal += originalCount;
                tracksRetained += clip.Tracks.Length;
                trackCounts[name] = new GDictionary
                {
                    ["raw"] = tracks, ["original"] = originalCount, ["retained"] = clip.Tracks.Length,
                    ["morph_original"] = originalMorphCount, ["morph_retained"] = retainedMorphCount
                };
            }
            _initial = new PoseFrame(positions, rotations, scales, morphs);
            Reset();
            return new GDictionary
            {
                ["ok"] = true, ["bone_count"] = count, ["morph_count"] = morphs.Length, ["clip_count"] = _clips.Count,
                ["morph_masked"] = morphMasked, ["morph_union_count"] = _sampleMorphs.Length,
                ["required_morph_indices"] = _sampleMorphs, ["tracks_raw"] = tracksRaw,
                ["tracks_original"] = tracksOriginal, ["tracks_retained"] = tracksRetained,
                ["track_counts_by_clip"] = trackCounts
            };
        }
        catch (Exception error) when (error is ArgumentException || error is InvalidOperationException || error is KeyNotFoundException || error is InvalidCastException)
        {
            Clear();
            return Failure("descriptor_rejected", error.Message);
        }
    }

    public GDictionary Reset()
    {
        if (_initial == null) return Failure("not_compiled", "Compile must succeed first.");
        _state = new PoseFrame(_initial.Positions, _initial.Rotations, _initial.Scales, _initial.Morphs);
        _currentClip = _initialClip;
        return new GDictionary { ["ok"] = true };
    }

    public GDictionary ApplyMorphUpdates(int[] indices, float[] values)
    {
        if (_state == null) return Failure("not_compiled", "Compile must succeed first.");
        if (indices == null || values == null || indices.Length != values.Length) return Failure("morph_update_lengths", "Indices and values must have equal lengths.");
        for (int i = 0; i < indices.Length; i++)
            if (indices[i] < 0 || indices[i] >= _state.Morphs.Length || !float.IsFinite(values[i])) return Failure("morph_update_value", "Invalid morph index or value.");
        for (int i = 0; i < indices.Length; i++) _state.Morphs[indices[i]] = values[i];
        return new GDictionary { ["ok"] = true };
    }

    public GDictionary Sample(StringName clip, double time)
    {
        if (!TrySamplePose(clip, time, out PoseFrame? frame, out string error)) return Failure("sample_rejected", error);
        return new GDictionary
        {
            ["ok"] = true, ["effective_time"] = frame.EffectiveTime,
            ["positions"] = frame.Positions, ["rotations"] = new Godot.Collections.Array<Quaternion>(frame.Rotations),
            ["scales"] = frame.Scales, ["morphs"] = frame.Morphs,
            ["local"] = new Godot.Collections.Array<Transform3D>(frame.Local),
            ["global"] = new Godot.Collections.Array<Transform3D>(frame.Global)
        };
    }

    // Call synchronously in original Source request order. The returned arrays are
    // owned by this result and must be treated as read-only by the collision stage.
    // ponytail: one transactional result allocation per pose; pool only after the
    // full-pipeline measurement proves this is significant, never share scratch.
    internal bool TrySamplePose(StringName clipName, double time, [NotNullWhen(true)] out PoseFrame? frame, out string error)
    {
        frame = null;
        error = "";
        string name = clipName.ToString();
        if (_state == null || !_clips.TryGetValue(name, out Clip? clip)) { error = "unknown_clip_or_not_compiled"; return false; }
        if (!double.IsFinite(time)) { error = "nonfinite_time"; return false; }
        PoseFrame next = new(_state.Positions, _state.Rotations, _state.Scales, _state.Morphs);
        if (name != _currentClip)
        {
            Array.Copy(_mixerPositions, next.Positions, _parents.Length);
            Array.Copy(_mixerRotations, next.Rotations, _parents.Length);
            Array.Copy(_mixerScales, next.Scales, _parents.Length);
            foreach (int index in _resetMorphs) next.Morphs[index] = 0.0f;
        }
        for (int bone = 0; bone < _parents.Length; bone++)
        {
            if (!_deterministic && !clip.ActiveBones[bone]) continue;
            if ((_channels[bone] & 1) != 0) next.Positions[bone] = _mixerPositions[bone];
            if ((_channels[bone] & 2) != 0) next.Rotations[bone] = _mixerRotations[bone];
            if ((_channels[bone] & 4) != 0) next.Scales[bone] = _mixerScales[bone];
        }
        foreach (int morph in clip.MixerMorphs) next.Morphs[morph] = _mixerMorphs[morph];
        next.EffectiveTime = SeekTime(clip.Animation, time);
        int activeTrack = -1;
        int activeBone = -1;
        string stage = "tracks";
        try
        {
            foreach (int track in clip.Tracks)
            {
                int bone = clip.Bones[track];
                activeTrack = track;
                activeBone = bone;
                switch (clip.Types[track])
                {
                    case Animation.TrackType.Position3D:
                        Vector3 position = clip.Animation.PositionTrackInterpolate(track, next.EffectiveTime, false) * _motionScale;
                        next.Positions[bone] += position - _mixerPositions[bone];
                        break;
                    case Animation.TrackType.Rotation3D:
                        Quaternion rotation = clip.Animation.RotationTrackInterpolate(track, next.EffectiveTime, false);
                        // Animation::interpolate_via_rest, full weight. Do not
                        // replace rest * inverse(rest) with identity: float bits differ.
                        Quaternion rest = _mixerRotations[bone];
                        Quaternion inverseRest = new(-rest.X, -rest.Y, -rest.Z, rest.W);
                        next.Rotations[bone] = (next.Rotations[bone] * NativeSlerp(Quaternion.Identity, inverseRest * rotation, 1.0f)).Normalized();
                        break;
                    case Animation.TrackType.Scale3D:
                        next.Scales[bone] += clip.Animation.ScaleTrackInterpolate(track, next.EffectiveTime, false) - _mixerScales[bone];
                        break;
                    case Animation.TrackType.BlendShape:
                        int morph = clip.Morphs[track];
                        next.Morphs[morph] += clip.Animation.BlendShapeTrackInterpolate(track, next.EffectiveTime, false) - _mixerMorphs[morph];
                        break;
                }
            }
            stage = "hierarchy";
            activeTrack = -1;
            foreach (int bone in _order)
            {
                activeBone = bone;
                if (!next.Positions[bone].IsFinite() || !next.Rotations[bone].IsFinite() || next.Rotations[bone].LengthSquared() == 0.0f || !next.Scales[bone].IsFinite())
                    throw new InvalidOperationException("nonfinite_pose");
                // Skeleton3D's pose is absolute-local in Godot 4 (not rest * pose).
                // set_quaternion_scale is rotation * diagonal, not world scaling.
                Basis basis = new Basis(next.Rotations[bone]) * Basis.FromScale(next.Scales[bone]);
                next.Local[bone] = new Transform3D(basis, next.Positions[bone]);
                // Keep the root identity multiplication too; it affects signed zero.
                next.Global[bone] = (_parents[bone] < 0 ? Transform3D.Identity : next.Global[_parents[bone]]) * next.Local[bone];
                if (!next.Global[bone].IsFinite()) throw new InvalidOperationException("nonfinite_global_pose");
            }
            foreach (int morph in _sampleMorphs) if (!float.IsFinite(next.Morphs[morph])) throw new InvalidOperationException("nonfinite_morph:" + morph);
        }
        catch (Exception exception) when (exception is ArgumentException || exception is InvalidOperationException)
        {
            error = $"clip={name}, time={time:R}, effective_time={next.EffectiveTime:R}, stage={stage}, track={activeTrack}, bone={activeBone}: {exception.Message}";
            return false; // No partial pose/history commit on failure.
        }
        _state = next;
        _currentClip = name;
        frame = next;
        return true;
    }

    private static Quaternion NativeSlerp(Quaternion from, Quaternion to, float weight)
    {
        // Godot 4.6.2 core/math/quaternion.cpp, Quaternion::slerp. GodotSharp's
        // DEBUG guard uses its tighter normalization test and rejects legal native
        // rest.inverse() * sampled_rotation intermediates. Do not normalize them.
        // Native CMP_EPSILON is 0.00001f, not GodotSharp.Mathf.Epsilon. In the
        // first sine, native 1.0 promotes the entire argument/division to double.
        float cosine = from.Dot(to);
        Quaternion destination = to;
        if (cosine < 0.0f)
        {
            cosine = -cosine;
            destination = -to;
        }
        float scale0;
        float scale1;
        if (1.0f - cosine > 0.00001f)
        {
            float omega = MathF.Acos(cosine);
            float sine = MathF.Sin(omega);
            scale0 = (float)(Math.Sin((1.0 - weight) * omega) / sine);
            scale1 = MathF.Sin(weight * omega) / sine;
        }
        else
        {
            scale0 = 1.0f - weight;
            scale1 = weight;
        }
        return new Quaternion(
            scale0 * from.X + scale1 * destination.X,
            scale0 * from.Y + scale1 * destination.Y,
            scale0 * from.Z + scale1 * destination.Z,
            scale0 * from.W + scale1 * destination.W);
    }

    private static double SeekTime(Animation animation, double time)
    {
        // AnimationPlayer::_process_playback_data, external seek with zero delta,
        // full clip interval and forward speed. Curves keep their native loop wrap.
        double length = animation.Length;
        if (animation.LoopMode == Animation.LoopModeEnum.Linear) return Mathf.PosMod(time, length);
        if (animation.LoopMode == Animation.LoopModeEnum.Pingpong) return Mathf.PingPong(time, length);
        if (time < 0.0 && !NativeTimeEqual(time, 0.0)) time = 0.0;
        if (time > length && !NativeTimeEqual(time, length)) time = length;
        if (NativeTimeEqual(time, length)) time = length;
        return time;
    }

    // Native AnimationPlayer uses Math::is_equal_approx(double), whose
    // CMP_EPSILON is 1e-5; GodotSharp's double epsilon is instead 1e-14.
    // Preserve the engine's edge snap, not a new animation-time quantization.
    private static bool NativeTimeEqual(double left, double right)
        => left == right || Math.Abs(left - right) < Math.Max(0.00001 * Math.Abs(left), 0.00001);

    public void Clear()
    {
        foreach (Clip clip in _clips.Values) clip.Animation?.Dispose();
        _clips.Clear();
        _initial = null;
        _state = null;
        _initialClip = _currentClip = "";
        _parents = _order = _channels = _resetMorphs = _sampleMorphs = Array.Empty<int>();
        _rest = Array.Empty<Transform3D>();
        _mixerPositions = _mixerScales = Array.Empty<Vector3>();
        _mixerRotations = Array.Empty<Quaternion>();
        _mixerMorphs = Array.Empty<float>();
        _morphChannels = Array.Empty<bool>();
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing) Clear();
        base.Dispose(disposing);
    }

    private static int[] ParentOrder(int[] parents)
    {
        List<int> order = new(parents.Length);
        byte[] visited = new byte[parents.Length];
        void Visit(int bone)
        {
            if (visited[bone] == 2) return;
            Require(visited[bone] == 0, "cyclic_parents");
            visited[bone] = 1;
            if (parents[bone] >= 0) Visit(parents[bone]);
            visited[bone] = 2;
            order.Add(bone);
        }
        for (int bone = 0; bone < parents.Length; bone++) Visit(bone);
        return order.ToArray();
    }

    private static Quaternion[] Quaternions(GArray values)
    {
        Quaternion[] result = new Quaternion[values.Count];
        for (int i = 0; i < result.Length; i++) { Require(values[i].VariantType == Variant.Type.Quaternion, "quaternion_type"); result[i] = values[i].AsQuaternion(); }
        return result;
    }

    private static Transform3D[] Transforms(GArray values)
    {
        Transform3D[] result = new Transform3D[values.Count];
        for (int i = 0; i < result.Length; i++) { Require(values[i].VariantType == Variant.Type.Transform3D, "transform_type"); result[i] = values[i].AsTransform3D(); }
        return result;
    }

    private static Variant Read(GDictionary descriptor, string key, Variant.Type type)
    {
        Require(descriptor.TryGetValue(key, out Variant value) && value.VariantType == type, "field:" + key);
        return value;
    }

    private static float Number(GDictionary descriptor, string key)
    {
        Require(descriptor.TryGetValue(key, out Variant value) && (value.VariantType == Variant.Type.Float || value.VariantType == Variant.Type.Int), "field:" + key);
        return value.AsSingle();
    }

    private static void Require([DoesNotReturnIf(false)] bool condition, string error)
    {
        if (!condition) throw new ArgumentException(error);
    }

    private static GDictionary Failure(string code, string detail) => new() { ["ok"] = false, ["code"] = code, ["error"] = detail };
}
