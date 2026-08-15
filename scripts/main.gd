extends Node2D

const CHARACTER_CREATOR_SCENE: PackedScene = preload("res://scenes/ui/CharacterCreator.tscn")

@onready var navigation_controller: NavigationController = $NavigationController
@onready var debug_ui: DebugUI = $DebugUI
@onready var current_map_root: Node2D = $CurrentMapRoot

var character_creator: CharacterCreator
var _navigation_input_was_enabled: bool = true

func _ready() -> void:
	navigation_controller.setup(current_map_root)
	navigation_controller.debug_state_changed.connect(debug_ui.update_state)
	debug_ui.character_creator_requested.connect(_open_character_creator)
	navigation_controller.start()

func _open_character_creator() -> void:
	if character_creator == null:
		character_creator = CHARACTER_CREATOR_SCENE.instantiate() as CharacterCreator
		add_child(character_creator)
		character_creator.closed.connect(_on_character_creator_closed)
	if character_creator.is_open():
		return
	_navigation_input_was_enabled = navigation_controller.is_processing_unhandled_input()
	navigation_controller.set_process_unhandled_input(false)
	character_creator.open(PaperDollCatalog.create_art_gate1_catalog())

func _on_character_creator_closed() -> void:
	navigation_controller.set_process_unhandled_input(_navigation_input_was_enabled)
