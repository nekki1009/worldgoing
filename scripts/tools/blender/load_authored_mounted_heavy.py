"""Load the two editable mounted actions for existing rig/morph baking owners."""
from pathlib import Path
import bpy

ROOT = Path(__file__).resolve().parents[3]
NAMES = ('ride_heavy', 'ride_guard_break')


def load_mounted_actions(armature, is_female=False):
    """Append actions only. Caller controls active action, bone modes and NLA.

    For sampling these quaternion curves, mute the rig's old NLA tracks and
    set pose bones to QUATERNION. Restore the original modes afterwards if
    sampling old Euler actions. Never re-export old clips to integrate these.
    """
    sex = 'female' if is_female else 'male'
    source = ROOT / f'assets/characters/human/q35/equipment_matrix/mounted_actions_{sex}.blend'
    assert not any(bpy.data.actions.get(name) for name in NAMES), 'Mounted actions already loaded'
    with bpy.data.libraries.load(str(source), link=False) as (available, loaded):
        assert set(NAMES) <= set(available.actions), source
        loaded.actions = list(NAMES)
    actions = {action.name: action for action in loaded.actions}
    assert set(actions) == set(NAMES)
    for action in actions.values():
        for curve in action.fcurves:
            if curve.data_path.startswith('pose.bones['):
                name = curve.data_path.split('"')[1]
                assert name in armature.pose.bones, (action.name, name)
        action.use_fake_user = True
    return actions
