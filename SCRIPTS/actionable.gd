extends Area2D

@export var dialogue_resources: DialogueResource
@export var dialogue_start: String = "start"

# Signal for when player enters/exits the area
signal player_entered
signal player_exited

# Variable to track if player is in the area
var is_player_in_area: bool = false
var dialogue_already_shown: bool = false

func _ready() -> void:
	# Connect the built-in area signals
	connect("body_entered", _on_body_entered)
	connect("body_exited", _on_body_exited)

func _on_body_entered(body: Node2D) -> void:
	# Check if the entering body is the player
	if body.is_in_group("PLAYER"):
		is_player_in_area = true
		player_entered.emit()
		
		# Automatically show dialogue when player enters area
		# Only if dialogue hasn't been shown already
		if not dialogue_already_shown:
			action()

func _on_body_exited(body: Node2D) -> void:
	# Check if the exiting body is the player
	if body.is_in_group("PLAYER"):
		is_player_in_area = false
		player_exited.emit()
		
		# Reset dialogue shown flag when player exits
		# This allows dialogue to show again when re-entering
		dialogue_already_shown = false

func action() -> void:
	DialogueManager.show_example_dialogue_balloon(dialogue_resources, dialogue_start)
	dialogue_already_shown = true
