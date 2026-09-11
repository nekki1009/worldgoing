class_name CharacterVisualState
extends RefCounted

## Runtime appearance and pose input shared by the editor and map presenter.
## Gameplay owns movement and combat; this object only describes what should
## be rendered for the current character.
var body_index: int = 0
var animation_id: StringName = &"idle"
var animation_time: float = 0.0
var playing: bool = true
var speed: float = 1.0
var yaw_degrees: float = 0.0
var mounted: bool = false
var combat_ready: bool = false
