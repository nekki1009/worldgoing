using Godot;
using System;
using System.Collections.Generic;
using GArray = Godot.Collections.Array;
using GDictionary = Godot.Collections.Dictionary;

// Private opt-in companion to TerrainWeaponCollision. Inputs are snapshots of
// its original mesh, skin, camera and first-head-fit data, never another asset.
public partial class compiled_contact_shapes : RefCounted
{
    private sealed class Surface
    {
        public Vector3[] Vertices = Array.Empty<Vector3>();
        public int[] Bones = Array.Empty<int>();
        public float[] Weights = Array.Empty<float>();
        public int[] Indices = Array.Empty<int>();
        public int Rigid = -1;
    }
    private sealed class Part
    {
        public Transform3D World;
        public int[] BindBones = Array.Empty<int>();
        public Transform3D[] BindPoses = Array.Empty<Transform3D>();
        public int[] UsedBindings = Array.Empty<int>();
        public Surface[] Surfaces = Array.Empty<Surface>();
        public int VertexCount;
    }
    private sealed class Armor
    {
        public Part[] Parts = Array.Empty<Part>();
        public GDictionary Profile = new();
    }
    private Transform3D _skeletonWorld, _cameraWorld, _meshProjection;
    private Transform2D _sprite;
    private Projection _projection;
    private Vector2 _viewport;
    private Vector3 _cameraRight;
    private Vector2[] _ring = Array.Empty<Vector2>();
    private (int A, int B, float Radius)[] _limbs = Array.Empty<(int, int, float)>();
    private int _head, _shoulder, _knee, _foot;
    private Aabb _headBounds;
    private bool _hasHead, _unarmed, _ranged, _parrying, _compiled;
    private Part[] _weapons = Array.Empty<Part>(), _shields = Array.Empty<Part>(), _parry = Array.Empty<Part>();
    private Armor[] _armor = Array.Empty<Armor>();

    public GDictionary Compile(GDictionary descriptor)
    {
        _compiled = false;
        try
        {
            if (descriptor["schema"].AsInt32() != 1 || descriptor["aim_weight"].AsDouble() != 0)
                return Fail("Only schema 1, unaimed snapshots are admitted.");
            _skeletonWorld = descriptor["skeleton_world"].AsTransform3D();
            _cameraWorld = descriptor["camera_world"].AsTransform3D();
            _meshProjection = descriptor["mesh_projection"].AsTransform3D();
            _sprite = descriptor["sprite"].AsTransform2D();
            _projection = descriptor["projection"].AsProjection();
            _viewport = descriptor["viewport"].AsVector2();
            _cameraRight = descriptor["camera_right"].AsVector3();
            _ring = descriptor["capsule_ring"].AsVector2Array();
            var limbs = descriptor["limbs"].AsGodotArray();
            _limbs = new (int, int, float)[limbs.Count];
            for (int i = 0; i < limbs.Count; i++)
            {
                var limb = limbs[i].AsGodotArray();
                _limbs[i] = (limb[0].AsInt32(), limb[1].AsInt32(), (float)limb[2].AsDouble());
            }
            _head = descriptor["head"].AsInt32();
            _shoulder = descriptor["shoulder"].AsInt32();
            _knee = descriptor["knee"].AsInt32();
            _foot = descriptor["foot"].AsInt32();
            _hasHead = descriptor["has_head"].AsBool();
            _headBounds = descriptor["head_bounds"].AsAabb();
            string clip = descriptor["weapon_clip"].AsString();
            _unarmed = clip == "attack_unarmed";
            _ranged = clip is "attack_bow" or "attack_crossbow";
            _parrying = descriptor["parrying"].AsBool();
            _weapons = ReadParts(descriptor["weapons"].AsGodotArray());
            _shields = ReadParts(descriptor["shields"].AsGodotArray());
            _parry = ReadParts(descriptor["parry"].AsGodotArray());
            var armor = descriptor["armor"].AsGodotArray();
            _armor = new Armor[armor.Count];
            for (int i = 0; i < armor.Count; i++)
            {
                var row = armor[i].AsGodotDictionary();
                _armor[i] = new Armor { Parts = ReadParts(row["parts"].AsGodotArray()), Profile = row["profile"].AsGodotDictionary().Duplicate() };
            }
            _compiled = true;
            return new GDictionary { ["ok"] = true };
        }
        catch (Exception error) { return Fail(error.Message); }
    }

    private static Part[] ReadParts(GArray rows)
    {
        var result = new Part[rows.Count];
        for (int i = 0; i < rows.Count; i++)
        {
            var row = rows[i].AsGodotDictionary();
            if (row["nonzero_morph"].AsBool()) throw new ArgumentException("Active mesh morph requires native bake; not admitted.");
            var binds = row["bind_poses"].AsGodotArray();
            var part = new Part { World = row["world"].AsTransform3D(), BindBones = row["bind_bones"].AsInt32Array(), BindPoses = new Transform3D[binds.Count] };
            if (part.BindBones.Length != binds.Count) throw new ArgumentException("Mismatched skin bindings.");
            for (int j = 0; j < binds.Count; j++) part.BindPoses[j] = binds[j].AsTransform3D();
            var surfaces = row["surfaces"].AsGodotArray();
            part.Surfaces = new Surface[surfaces.Count];
            for (int j = 0; j < surfaces.Count; j++)
            {
                var raw = surfaces[j].AsGodotDictionary();
                var surface = new Surface { Vertices = raw["vertices"].AsVector3Array(), Bones = raw["bones"].AsInt32Array(), Weights = raw["weights"].AsFloat32Array(), Indices = raw["indices"].AsInt32Array() };
                int count = surface.Vertices.Length;
                if (surface.Bones.Length != surface.Weights.Length || (count > 0 && surface.Bones.Length % count != 0)) throw new ArgumentException("Malformed skin surface.");
                int influences = count == 0 ? 0 : surface.Bones.Length / count;
                int rigid = -1;
                for (int v = 0; v < count && influences > 0; v++)
                {
                    int assigned = -1;
                    for (int k = 0; k < influences; k++)
                    {
                        int offset = v * influences + k;
                        if (surface.Bones[offset] < 0 || surface.Bones[offset] >= binds.Count) throw new ArgumentException("Skin binding out of range.");
                        if (surface.Weights[offset] == 0) continue;
                        if (surface.Weights[offset] != 1 || assigned >= 0) { assigned = -2; break; }
                        assigned = surface.Bones[offset];
                    }
                    if (assigned < 0 || (rigid >= 0 && assigned != rigid)) { rigid = -2; break; }
                    rigid = assigned;
                }
                surface.Rigid = rigid;
                foreach (int index in surface.Indices) if (index < 0 || index >= count) throw new ArgumentException("Mesh index out of range.");
                part.Surfaces[j] = surface;
                part.VertexCount = checked(part.VertexCount + count);
            }
            // The original rigid path evaluates only its one binding. Retain
            // every referenced slot for nonrigid surfaces, including zero weights,
            // because those multiplications are part of the exact scalar order.
            var used = new bool[part.BindBones.Length];
            foreach (Surface surface in part.Surfaces)
            {
                if (surface.Rigid >= 0) used[surface.Rigid] = true;
                else foreach (int binding in surface.Bones) used[binding] = true;
            }
            var required = new List<int>();
            for (int binding = 0; binding < used.Length; binding++) if (used[binding]) required.Add(binding);
            part.UsedBindings = required.ToArray();
            result[i] = part;
        }
        return result;
    }

    public GDictionary Evaluate(GArray globalPoses, bool includeWeapon = true)
        => EvaluateBones(ReadBones(globalPoses), includeWeapon);

    // The opt-in Source integration keeps native AnimationPlayer/aim/history.
    // Read its completed pose here instead of marshaling bones through GDScript.
    public GDictionary EvaluateNative(Skeleton3D skeleton, bool includeWeapon = true)
    {
        try { return EvaluateBones(ReadNativeBones(skeleton), includeWeapon); }
        catch (Exception error) { return Fail(error.Message); }
    }

    public GDictionary ArmorAtNative(Skeleton3D skeleton, Vector2 point, string kind)
    {
        try { return ArmorAtBones(ReadNativeBones(skeleton), point, kind); }
        catch (Exception error) { return Fail(error.Message); }
    }

    private static Transform3D[] ReadNativeBones(Skeleton3D skeleton)
    {
        if (!GodotObject.IsInstanceValid(skeleton)) throw new ArgumentException("Native skeleton is unavailable.");
        var bones = new Transform3D[skeleton.GetBoneCount()];
        for (int i = 0; i < bones.Length; i++) bones[i] = skeleton.GetBoneGlobalPose(i);
        return bones;
    }

    public void Clear()
    {
        _compiled = false;
        _weapons = _shields = _parry = Array.Empty<Part>();
        foreach (Armor armor in _armor) armor?.Profile.Dispose();
        _armor = Array.Empty<Armor>();
        _limbs = Array.Empty<(int, int, float)>();
        _ring = Array.Empty<Vector2>();
    }

    // Source drops many bounded views before shutdown. Dispose its owned C#
    // wrapper explicitly instead of leaving finalizers to outlive Godot Mono.
    public void ReleaseOwned() => Dispose();

    protected override void Dispose(bool disposing)
    {
        if (disposing) Clear();
        base.Dispose(disposing);
    }

    internal GDictionary EvaluateBones(Transform3D[] bones, bool includeWeapon = true)
    {
        if (!_compiled) return Fail("Not compiled.");
        try
        {
            var body = new List<Vector2[]>(_limbs.Length);
            foreach (var limb in _limbs)
            {
                if (limb.A < 0 || limb.B < 0) continue;
                Vector3 start = (_skeletonWorld * bones[limb.A].Origin);
                Vector3 end = (_skeletonWorld * bones[limb.B].Origin);
                Vector2 centre = Project(start);
                float radius = centre.DistanceTo(Project(start + _cameraRight * limb.Radius));
                body.Add(Capsule(centre, Project(end), radius));
            }
            if (_hasHead && _head >= 0 && body.Count > 1)
            {
                Transform3D world = _skeletonWorld * bones[_head];
                var points = new Vector2[8];
                for (int i = 0; i < points.Length; i++) points[i] = Project(world * _headBounds.GetEndpoint(i));
                body[1] = Geometry2D.ConvexHull(points);
            }
            var shields = Shapes(_shields, bones);
            var parry = shields.Count == 0 && _parrying && !_unarmed && !_ranged ? Shapes(_parry, bones) : new List<Vector2[]>();
            bool first = true;
            Rect2 bounds = new();
            // Head replacement is complete before the original body/shield/parry
            // bounds order. Marshal each final hull only once, after this read.
            foreach (List<Vector2[]> shapes in new[] { body, shields, parry })
                foreach (Vector2[] shape in shapes)
                    foreach (Vector2 point in shape)
                    { if (first) { bounds = new Rect2(point, Vector2.Zero); first = false; } else bounds = bounds.Expand(point); }
            var result = new GDictionary { ["ok"] = true, ["body"] = WriteShapes(body), ["shield"] = WriteShapes(shields), ["parry"] = WriteShapes(parry), ["hurt_bounds"] = bounds,
                ["shoulder"] = Project(_skeletonWorld * bones[_shoulder].Origin) };
            if (includeWeapon)
            {
                var weapon = _ranged ? new List<Vector2[]>() : Shapes(_weapons, bones);
                if (_unarmed)
                {
                    weapon = new List<Vector2[]>();
                    if (_knee >= 0 && _foot >= 0) weapon.Add(Capsule(Project(_skeletonWorld * bones[_knee].Origin), Project(_skeletonWorld * bones[_foot].Origin), 3));
                }
                result["weapon"] = WriteShapes(weapon);
            }
            return result;
        }
        catch (Exception error) { return Fail(error.Message); }
    }

    public GDictionary ArmorAt(GArray globalPoses, Vector2 point, string kind)
        => ArmorAtBones(ReadBones(globalPoses), point, kind);

    internal GDictionary ArmorAtBones(Transform3D[] bones, Vector2 point, string kind)
    {
        if (!_compiled) return Fail("Not compiled.");
        Vector2 protection = Vector2.Zero;
        foreach (Armor armor in _armor)
        {
            bool covered = false;
            foreach (Part part in armor.Parts)
            {
                var palettes = Palette(part, bones);
                foreach (Surface surface in part.Surfaces)
                {
                    var points = new Vector2[surface.Vertices.Length];
                    Points(part, surface, palettes, points, 0);
                    int count = surface.Indices.Length == 0 ? points.Length : surface.Indices.Length;
                    var triangle = new Vector2[3];
                    for (int i = 0; i < count - 2; i += 3)
                    {
                        for (int k = 0; k < 3; k++) triangle[k] = points[surface.Indices.Length == 0 ? i + k : surface.Indices[i + k]];
                        if (Geometry2D.IsPointInPolygon(point, triangle)) { covered = true; break; }
                    }
                    if (covered) break;
                }
                if (covered) break;
            }
            if (covered) protection += new Vector2(armor.Profile.TryGetValue(kind, out Variant amount) ? (float)amount.AsDouble() : 0, (float)armor.Profile["cushion"].AsDouble());
        }
        return new GDictionary { ["ok"] = true, ["protection"] = protection };
    }

    private static Transform3D[] ReadBones(GArray raw)
    {
        var result = new Transform3D[raw.Count];
        for (int i = 0; i < raw.Count; i++) result[i] = raw[i].AsTransform3D();
        return result;
    }
    private Transform3D[] Palette(Part part, Transform3D[] bones)
    {
        var result = new Transform3D[part.BindBones.Length];
        foreach (int i in part.UsedBindings) result[i] = part.BindBones[i] >= 0 ? _skeletonWorld * bones[part.BindBones[i]] * part.BindPoses[i] : part.World;
        return result;
    }
    private List<Vector2[]> Shapes(Part[] parts, Transform3D[] bones)
    {
        var result = new List<Vector2[]>(parts.Length);
        foreach (Part part in parts)
        {
            var palette = Palette(part, bones);
            var points = new Vector2[part.VertexCount];
            int offset = 0;
            foreach (Surface surface in part.Surfaces)
            {
                Points(part, surface, palette, points, offset);
                offset += surface.Vertices.Length;
            }
            if (points.Length >= 3) result.Add(Geometry2D.ConvexHull(points));
        }
        return result;
    }
    private static GArray WriteShapes(List<Vector2[]> shapes)
    {
        var result = new GArray();
        foreach (Vector2[] shape in shapes) result.Add(shape);
        return result;
    }
    private void Points(Part part, Surface surface, Transform3D[] palette, Vector2[] result, int offset)
    {
        int count = surface.Vertices.Length;
        int influences = count == 0 ? 0 : surface.Bones.Length / count;
        for (int i = 0; i < count; i++)
        {
            Vector3 point;
            if (palette.Length == 0 || influences == 0) point = part.World * surface.Vertices[i];
            else if (surface.Rigid >= 0) point = palette[surface.Rigid] * surface.Vertices[i];
            else
            {
                point = Vector3.Zero;
                for (int k = 0; k < influences; k++)
                {
                    int index = i * influences + k;
                    point += (palette[surface.Bones[index]] * surface.Vertices[i]) * surface.Weights[index];
                }
            }
            Vector3 projected = _meshProjection * point;
            result[offset + i] = _sprite * new Vector2(projected.X, projected.Y);
        }
    }
    private Vector2 Project(Vector3 point)
    {
        // Camera3D::unproject_position uses orthonormal xform_inv, not an
        // affine-inverse precomputed matrix (which changes operation ordering).
        Vector3 cameraPoint = (point - _cameraWorld.Origin) * _cameraWorld.Basis;
        Vector4 clip = _projection * new Vector4(cameraPoint.X, cameraPoint.Y, cameraPoint.Z, 1);
        Vector3 normal = new Vector3(clip.X, clip.Y, clip.Z) / clip.W;
        Vector2 screen = new((float)((normal.X * 0.5 + 0.5) * _viewport.X), (float)((-normal.Y * 0.5 + 0.5) * _viewport.Y));
        return _sprite * (screen - _viewport * 0.5f);
    }
    private Vector2[] Capsule(Vector2 start, Vector2 end, float radius)
    {
        var points = new Vector2[_ring.Length * 2];
        for (int i = 0; i < _ring.Length; i++) { Vector2 offset = _ring[i] * radius; points[i * 2] = start + offset; points[i * 2 + 1] = end + offset; }
        return Geometry2D.ConvexHull(points);
    }
    private static GDictionary Fail(string error) => new() { ["ok"] = false, ["error"] = error };
}
