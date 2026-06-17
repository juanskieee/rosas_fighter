extends TextureProgressBar

# Constants for visual effects and behavior
const SMOOTH_HEALTH_SPEED: float = 0.15
const FLASH_INTENSITY: float = 2.0
const FLASH_DURATION: float = 0.3
const DAMAGE_SHAKE_AMOUNT: float = 3.0

# Member variables
var player: CharacterBody2D
var displayed_value: float
var actual_player_health: float

func _ready():
	# Wait one frame to ensure everything is ready
	await get_tree().process_frame
	
	# Get player reference
	player = get_player_reference()
	if player:
		# Setup health values
		max_value = player.MAX_HEALTH
		actual_player_health = float(player.health)
		displayed_value = actual_player_health
		value = displayed_value
		
		# Connect signal
		player.health_changed.connect(_on_player_health_changed)
		
		# Ensure health bar is visible immediately
		modulate.a = 1.0
		
		# Debug: Print initial values
		print("Health Bar - Initial setup:")
		print("  Actual player health: ", actual_player_health)
		print("  Displayed health: ", displayed_value)
		print("  MAX_HEALTH: ", player.MAX_HEALTH)
	else:
		push_error("PlayerHealthBar: Could not find player reference!")

func _process(delta):
	if player and is_instance_valid(player):
		# Update actual player health
		actual_player_health = float(player.health)
		
		# Smooth interpolation towards the actual health
		displayed_value = lerp(displayed_value, actual_player_health, SMOOTH_HEALTH_SPEED)
		value = displayed_value
		
		# Debug: Print values occasionally
		if randf() < 0.01:
			print("Health Bar - Current state:")
			print("  Actual player health: ", actual_player_health)
			print("  Current displayed: ", displayed_value)
			print("  Health bar value: ", value)
	else:
		# If player is destroyed, hide the health bar
		modulate.a = move_toward(modulate.a, 0.0, 0.1)
		if modulate.a <= 0.01:
			queue_free()

func get_player_reference() -> CharacterBody2D:
	# Get parent if it's the player
	var parent = get_parent()
	if parent is CharacterBody2D and parent.is_in_group("PLAYER"):
		return parent
		
	# Alternative: Find player in the scene
	var players = get_tree().get_nodes_in_group("PLAYER")
	if players.size() > 0:
		return players[0] as CharacterBody2D
			
	return null

func _on_player_health_changed(new_health: int, max_health: int):
	if player and is_instance_valid(player):
		# Update max health
		max_value = max_health
		
		# Update actual health
		actual_player_health = float(new_health)
		
		print("Health changed - New health: ", new_health)
		print("  Current displayed: ", displayed_value)
		
		# Calculate health percentage for visual effects
		var health_percentage = actual_player_health / float(max_health)
		
		# Only show critical effects when health is critical
		if health_percentage <= 0.2:
			start_critical_pulse()
		else:
			self_modulate = Color(1.0, 1.0, 1.0)  # Always white except for critical
			
		flash_damage()
		shake_bar()

# Damage flash effect
func flash_damage():
	var original_modulate = self_modulate
	self_modulate = Color(FLASH_INTENSITY, FLASH_INTENSITY, FLASH_INTENSITY, 1.0)
	var tween = create_tween()
	tween.tween_property(self, "self_modulate", original_modulate, FLASH_DURATION)
	
	var original_scale = scale
	scale = original_scale * 0.95
	var scale_tween = create_tween()
	scale_tween.tween_property(self, "scale", original_scale * 1.1, 0.1)
	scale_tween.tween_property(self, "scale", original_scale, 0.15).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BOUNCE)

# Shake effect on damage
func shake_bar():
	var shake_tween = create_tween()
	var original_position = position
	shake_tween.tween_property(self, "position", original_position + Vector2(DAMAGE_SHAKE_AMOUNT, 0), 0.05)
	shake_tween.tween_property(self, "position", original_position + Vector2(-DAMAGE_SHAKE_AMOUNT, 0), 0.05)
	shake_tween.tween_property(self, "position", original_position + Vector2(DAMAGE_SHAKE_AMOUNT * 0.5, 0), 0.05)
	shake_tween.tween_property(self, "position", original_position, 0.05)

# Critical health pulsing
func start_critical_pulse():
	var existing_tween = get_meta("pulse_tween") if has_meta("pulse_tween") else null
	if existing_tween and existing_tween.is_valid():
		existing_tween.kill()
	
	self_modulate = Color(1.0, 0.2, 0.2)
	var pulse_tween = create_tween()
	pulse_tween.set_loops()
	pulse_tween.tween_property(self, "self_modulate:a", 0.7, 0.5)
	pulse_tween.tween_property(self, "self_modulate:a", 1.0, 0.5)
	set_meta("pulse_tween", pulse_tween)
