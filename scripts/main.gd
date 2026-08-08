extends Node2D

@onready var navigation_controller: NavigationController = $NavigationController
@onready var debug_ui: DebugUI = $DebugUI
@onready var current_map_root: Node2D = $CurrentMapRoot

func _ready() -> void:
	navigation_controller.setup(current_map_root)
	navigation_controller.debug_state_changed.connect(debug_ui.update_state)
	navigation_controller.start()
