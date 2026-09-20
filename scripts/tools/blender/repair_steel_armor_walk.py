"""Apply the existing fitted iron-armor correction to its authored steel clones.

Original steel materials, IDs and UVs stay on their own objects. Iron meshes
are read-only reference evidence, never replaced or repaired a second time.
"""
import bpy
from author_chinese_leather_mingguang import Fitting
from repair_iron_armor_walk import repair_chinese, repair_western, mesh_signature


def repair_steel(arm, sex):
    fit = Fitting(arm, sex)
    western, measured = repair_western(fit, 'Armor_Western_Steel_01')
    chinese, topology = repair_chinese(fit, 'Armor_Chinese_Steel_01')
    changed = western+chinese
    # These are explicit authored clones, not a material-dependent new model.
    # Equal final geometry/weights to the already reviewed iron siblings is
    # checked separately from steel's own material and per-face UV invariants.
    for obj in changed:
        source_name = obj.name.replace('Armor_Chinese_Steel_01','Armor_Iron_01').replace(
            'Armor_Western_Steel_01','Armor_Western_Iron_01')
        assert obj.get('cultural_source_mesh') == source_name, obj.name
        source = bpy.data.objects[source_name]
        assert len(obj.data.vertices) == len(source.data.vertices), obj.name
        assert [g.name for g in obj.vertex_groups] == [g.name for g in source.vertex_groups]
        for a,b in zip(obj.data.vertices,source.data.vertices):
            assert (a.co-b.co).length < 1e-6, (obj.name,a.index)
            assert [(g.group,g.weight) for g in a.groups] == [(g.group,g.weight) for g in b.groups]
    return {'changed':{o.name:mesh_signature(o) for o in changed},
            'topology_changed':topology,'western_measurements':measured,
            'geometry_and_weights_equal_reviewed_iron':True}
