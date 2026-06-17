extends TextureProgressBar

# Constants for visual effects and behavior
const SMOOTH_HEALTH_SPEED: float = 0.15
const FLASH_INTENSITY: float = 2.0
const FLASH_DURATION: float = 0.3
const DAMAGE_SHAKE_AMOUNT: float = 3.0
const HEALTH_DELAY: float = -20.0  # Delay displayed health by 10 points

# Member variables
var enemy: CharacterBody2D
var displayed_value: float
var actual_enemy_health: float

func _ready():
	# Wait one frame to ensure everything is ready
	await get_tree().process_frame
	
	# Get enemy reference
	enemy = get_enemy_reference()
	if enemy:
		# Setup health values
		max_value = enemy.MAX_HEALTH
		actual_enemy_health = float(enemy.health)
		# Initialize displayed value with 10-point delay
		displayed_value = max(0.0, actual_enemy_health - HEALTH_DELAY)
		value = displayed_value
		
		# Connect signal
		enemy.enemy_damaged.connect(_on_enemy_health_changed)
		
		# Ensure health bar is visible immediately
		modulate.a = 1.0
		
		# Debug: Print initial values
		print("Health Bar - Initial setup:")
		print("  Actual enemy health: ", actual_enemy_health)
		print("  Displayed health: ", displayed_value)
		print("  MAX_HEALTH: ", enemy.MAX_HEALTH)
	else:
		push_error("EnemyHealthBar: Could not find enemy reference!")

func _process(delta):
	if enemy and is_instance_valid(enemy):
		# Update actual enemy health
		actual_enemy_health = float(enemy.health)
		
		# Calculate target displayed value (actual health minus delay)
		var target_displayed = max(0.0, actual_enemy_health - HEALTH_DELAY)
		
		# Smooth interpolation towards the delayed target
		displayed_value = lerp(displayed_value, target_displayed, SMOOTH_HEALTH_SPEED)
		value = displayed_value
		
		# Debug: Print values occasionally
		if randf() < 0.1:
			print("Health Bar - Current state:")
			print("  Actual enemy health: ", actual_enemy_health)
			print("  Target displayed: ", target_displayed)
			print("  Current displayed: ", displayed_value)
			print("  Health bar value: ", value)
	else:
		# If enemy is destroyed, hide the health bar
		modulate.a = move_toward(modulate.a, 0.0, 0.1)
		if modulate.a <= 0.01:
			queue_free()

func get_enemy_reference() -> CharacterBody2D:
	# Get parent (should be the enemy this health bar is attached to)
	var parent = get_parent()
	if parent is CharacterBody2D and parent.is_in_group("ENEMIES"):
		return parent
		
	# Alternative: Find by group and proximity
	var enemies = get_tree().get_nodes_in_group("ENEMIES")
	if enemies.size() > 0:
		var closest_enemy = null
		var closest_distance = INF
		var my_position = global_position
		
		for enemy in enemies:
			var distance = my_position.distance_to(enemy.global_position)
			if distance < closest_distance:
				closest_distance = distance
				closest_enemy = enemy
				
		if closest_distance < 100:  # Only if reasonably close
			return closest_enemy as CharacterBody2D
			
	return null

func _on_enemy_health_changed(damage_amount: int):
	if enemy and is_instance_valid(enemy):
		# Update actual health
		actual_enemy_health = float(enemy.health)
		
		print("Health changed - Damage: ", damage_amount)
		print("  New actual health: ", actual_enemy_health)
		print("  Current displayed: ", displayed_value)
		
		# Calculate health percentage for visual effects
		var health_percentage = actual_enemy_health / float(enemy.MAX_HEALTH)
		
		# Only show critical effects when displayed health is critical
		var displayed_percentage = displayed_value / float(enemy.MAX_HEALTH)
		if displayed_percentage <= 0.2:
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
