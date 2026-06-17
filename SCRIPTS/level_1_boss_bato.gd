extends CharacterBody2D

# Constants - Use @export for easy adjustments in the Inspector
@export var WALK_SPEED: float = 150
@export var GRAVITY: float = 980.0
@export var ATTACK_RANGE: float = 150
@export var DETECTION_RANGE: float = 900
@export var ATTACK_COOLDOWN: float = 0.5
@export var KNOCKBACK_RECOVERY_SPEED: float = 500.0
@export var MAX_HEALTH: int = 300
@export var ATTACK_DAMAGE: int = 5

# Boss-specific parameters
@export var SCREEN_SHAKE_INTENSITY: float = 10.0
@export var SCREEN_SHAKE_DURATION: float = 0.2
@export var WALK_SHAKE_FREQUENCY: float = 0.3  # How often to shake while walking
@export var ENRAGE_THRESHOLD: float = 0.3  # Health percentage to enter enraged state

# Counter-attack parameters
@export var HIT_THRESHOLD: int = 3  # Number of hits before counter-attacking
@export var COUNTER_KNOCKBACK_FORCE: float = 700.0  # Force to knock back player when counter-attacking
@export var COUNTER_COOLDOWN: float = 8.0  # Time between counter-attacks
@export var HIT_REGISTER_WINDOW: float = 1.5  # Time window for registering combo hits
@export var melee_enemy: String = "res://SCENES/LEVEL1_ENEMY_MELEE.tscn"
@export var range_enemy: String = "res://SCENES/LEVEL1_ENEMY_RANGED.tscn"
@export var MAX_SPAWNED_ENEMIES: int = 3  # Maximum number of enemies to spawn per counter

# Member variables
var can_move := true
var health: int = MAX_HEALTH
var facing_direction: int = 1
var is_attacking: bool = false
var is_hurt: bool = false
var is_dead: bool = false
var attack_timer: float = 0.0
var knockback_velocity: Vector2 = Vector2.ZERO
var is_knocked_back: bool = false
var player = null

# Boss state variables
var current_phase: int = 1  # 1 = Normal, 2 = Angry (50% health), 3 = Enraged (30% health)
var walk_shake_timer: float = 0.0
var is_enraged: bool = false

# Counter-attack variables - IMPROVED
var hit_counter: int = 0
var combo_timer: float = 0.0  # Timer to track combo window
var counter_timer: float = 0.0
var is_casting: bool = false
var is_invincible: bool = false
var hit_flash_active: bool = false  # Control variable for hit flashing
var hit_registered: bool = false  # Flag to prevent multiple hit registrations in a single frame

# Visual feedback variables
var hit_number_label = null
var last_hit_time: float = 0.0

# Screen shake variables
var shake_intensity: float = 0.0
var shake_duration: float = 0.0
var shake_timer: float = 0.0
var camera_node: Camera2D = null
var initial_camera_offset: Vector2 = Vector2.ZERO

# Cached node references for better performance
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var attack_hitbox: Area2D = $AttackHitbox
@onready var right_hitbox: CollisionShape2D = $AttackHitbox/RightHitbox
@onready var left_hitbox: CollisionShape2D = $AttackHitbox/LeftHitbox
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

# Signal for game events
signal enemy_died
signal enemy_damaged(amount: int)
signal boss_phase_changed(new_phase: int)
signal boss_spawned_enemy(enemy_type: String)
signal boss_hit_counted(current_hits: int, threshold: int)  # New signal for hit counter UI

func _ready() -> void:
	# Initialize state
	sprite.play("IDLE")
	health = MAX_HEALTH
	hit_counter = 0
	counter_timer = 0.0
	combo_timer = 0.0
	
	# Add to enemies group for player targeting
	add_to_group("ENEMIES")
	add_to_group("BOSSES")  # Special group for bosses
	
	# Configure hitbox
	_configure_hitboxes(false)
	
	# Find player on start
	player = get_tree().get_first_node_in_group("PLAYER")
	
	# Set up timer to periodically try to find player if needed
	_setup_player_search_timer()
	
	# Create a hit counter visual feedback label
	_create_hit_counter_label()
	
	# Find camera - look in the scene tree first
	camera_node = get_viewport().get_camera_2d()
	if not camera_node:
		# Try to find by name in the scene tree
		camera_node = get_node_or_null("/root/LEVEL1/Camera2D")
	if not camera_node:
		# Last resort - look for any Camera2D in the scene
		var cameras = get_tree().get_nodes_in_group("Camera2D")
		if cameras.size() > 0:
			camera_node = cameras[0]
	
	# Store initial offset if camera found
	if camera_node:
		initial_camera_offset = camera_node.offset
		
	# Verify if we have the CAST animation, otherwise log a warning
	if not sprite.sprite_frames.has_animation("CAST"):
		print("Warning: CAST animation not found for boss. Will use ATTACK animation instead.")

func _create_hit_counter_label() -> void:
	# Create a label for hit counter feedback
	hit_number_label = Label.new()
	hit_number_label.visible = false
	hit_number_label.z_index = 10  # Make sure it's visible above other elements
	add_child(hit_number_label)
	
	# Style the label
	hit_number_label.add_theme_color_override("font_color", Color(1, 0, 0))
	hit_number_label.add_theme_font_size_override("font_size", 24)
	
func set_can_move(value: bool):
	can_move = value

func _setup_player_search_timer() -> void:
	var timer = Timer.new()
	add_child(timer)
	timer.wait_time = 1.0
	timer.one_shot = false
	timer.timeout.connect(func(): 
		if player == null:
			player = get_tree().get_first_node_in_group("PLAYER")
	)
	timer.start()

func _physics_process(delta: float) -> void:
	if is_dead:
		return

	# Process screen shake if active
	if shake_timer > 0:
		_process_screen_shake(delta)
		
	if not can_move:
		# Still allow animation updates if needed
		sprite.play("IDLE")
		return
		
	# Apply gravity when in air
	if not is_on_floor():
		velocity.y += GRAVITY * delta
		
	# Update attack cooldown
	if attack_timer > 0:
		attack_timer -= delta
	
	# Update counter cooldown
	if counter_timer > 0:
		counter_timer -= delta
	
	# Update combo timer for hit counting
	if combo_timer > 0:
		combo_timer -= delta
		if combo_timer <= 0 and hit_counter > 0 and hit_counter < HIT_THRESHOLD:
			# Reset hit counter if combo window expires without reaching threshold
			_reset_hit_counter()
	
	# Reset hit registration flag on each frame
	hit_registered = false
	
	# Update walk shake timer
	if velocity.x != 0 and is_on_floor():
		walk_shake_timer += delta
		if walk_shake_timer >= WALK_SHAKE_FREQUENCY:
			walk_shake_timer = 0.0
			_trigger_walk_shake()
	
	# Process different states
	if is_knocked_back:
		_process_knockback(delta)
	elif is_casting or is_attacking:
		# Keep the boss in place while casting or attacking
		velocity.x = 0
		move_and_slide()
	else:
		_process_ai()
		move_and_slide()

func _process_screen_shake(delta: float) -> void:
	if camera_node == null:
		return
		
	shake_timer -= delta
	
	if shake_timer > 0:
		# Calculate shake intensity based on remaining time
		var current_intensity = shake_intensity * (shake_timer / shake_duration)
		
		# Create random offset for camera
		var offset = Vector2(
			randf_range(-current_intensity, current_intensity),
			randf_range(-current_intensity, current_intensity)
		)
		
		# Apply offset to camera
		camera_node.offset = initial_camera_offset + offset
	else:
		# Reset camera position when shake is done
		camera_node.offset = initial_camera_offset
		shake_timer = 0.0

func _trigger_screen_shake(intensity: float, duration: float) -> void:
	# Set up screen shake parameters
	shake_intensity = intensity * _get_phase_multiplier()
	shake_duration = duration
	shake_timer = duration

func _trigger_walk_shake() -> void:
	# Trigger screen shake when boss walks
	var intensity = SCREEN_SHAKE_INTENSITY * 0.5 * _get_phase_multiplier()
	_trigger_screen_shake(intensity, SCREEN_SHAKE_DURATION)

func _process_knockback(delta: float) -> void:
	# Apply knockback velocity with gradual reduction
	if abs(knockback_velocity.x) > 0:
		knockback_velocity.x = move_toward(knockback_velocity.x, 0, KNOCKBACK_RECOVERY_SPEED * delta)
	
	if abs(knockback_velocity.y) > 0:
		knockback_velocity.y += GRAVITY * delta
		
	velocity = knockback_velocity
	
	# Return to normal movement when knockback velocity is negligible
	if abs(knockback_velocity.x) < 5 and is_on_floor():
		is_knocked_back = false
	
	move_and_slide()

func _process_ai() -> void:
	# Try to find player if not already found
	if player == null:
		player = get_tree().get_first_node_in_group("PLAYER")
		if player == null:
			# No player found, just idle
			velocity.x = 0
			if not is_hurt:
				sprite.play("IDLE")
			return
	
	# Calculate distance to player and direction
	var distance = global_position.distance_to(player.global_position)
	var direction = player.global_position.x - global_position.x
	facing_direction = 1 if direction > 0 else -1
	
	# Update sprite direction and apply phase effects
	sprite.flip_h = facing_direction < 0
	_apply_phase_effects()
	
	# Determine action based on distance and phase
	if distance < ATTACK_RANGE and attack_timer <= 0:
		perform_attack()
	elif distance < DETECTION_RANGE * _get_detection_multiplier():
		var speed = WALK_SPEED * _get_speed_multiplier()
		velocity.x = facing_direction * speed
		if not is_hurt:
			sprite.play("WALK")
	else:
		velocity.x = 0
		if not is_hurt:
			sprite.play("IDLE")

func _get_phase_multiplier() -> float:
	# Get a multiplier that scales with boss phase
	match current_phase:
		1: return 1.0
		2: return 1.1
		3: return 1.1
	return 1.0

func _get_speed_multiplier() -> float:
	# Get speed multiplier that scales with boss phase
	match current_phase:
		1: return 1.0
		2: return 1.3
		3: return 1.6
	return 1.0

func _get_detection_multiplier() -> float:
	# Get detection range multiplier that scales with boss phase
	match current_phase:
		1: return 1.0
		2: return 1.2
		3: return 1.5
	return 1.0

# New function to adjust hit threshold based on phase
func _get_hit_threshold() -> int:
	match current_phase:
		1: return HIT_THRESHOLD  # Normal threshold in phase 1
		2: return max(2, HIT_THRESHOLD - 1)  # One fewer hit needed in phase 2
		3: return max(1, HIT_THRESHOLD - 2)  # Two fewer hits needed in phase 3
	return HIT_THRESHOLD

func _apply_phase_effects() -> void:
	# Change sprite modulation based on phase
	match current_phase:
		1:
			sprite.modulate = Color.WHITE
		2:
			# Slightly red tint when angry
			sprite.modulate = Color(1.2, 0.9, 0.9)
		3:
			# Stronger red tint when enraged
			sprite.modulate = Color(1.4, 0.7, 0.7)

func _check_phase_change() -> void:
	var health_percentage = float(health) / float(MAX_HEALTH)
	var new_phase = current_phase
	
	if health_percentage <= ENRAGE_THRESHOLD and current_phase < 3:
		new_phase = 3
		is_enraged = true
	elif health_percentage <= 0.5 and current_phase < 2:
		new_phase = 2
	
	if new_phase != current_phase:
		current_phase = new_phase
		boss_phase_changed.emit(current_phase)
		
		# Trigger special effects when changing phase
		var shake_intensity = SCREEN_SHAKE_INTENSITY * 2.0
		_trigger_screen_shake(shake_intensity, 0.5)
		
		# Brief pause for dramatic effect
		var tween = create_tween()
		tween.tween_interval(0.3)

func _configure_hitboxes(enabled: bool) -> void:
	# Use set_deferred to safely change properties
	attack_hitbox.set_deferred("monitoring", enabled)
	attack_hitbox.set_deferred("monitorable", enabled)
	
	# Configure appropriate shapes based on facing direction
	if enabled:
		right_hitbox.set_deferred("disabled", facing_direction < 0)
		left_hitbox.set_deferred("disabled", facing_direction > 0)
	else:
		right_hitbox.set_deferred("disabled", true)
		left_hitbox.set_deferred("disabled", true)

func perform_attack() -> void:
	is_attacking = true
	velocity.x = 0
	sprite.play("ATTACK")
	
	# Enhanced attack effects based on phase
	var attack_intensity = SCREEN_SHAKE_INTENSITY * _get_phase_multiplier()
	_trigger_screen_shake(attack_intensity, 0.3)
	
	# Speed up animation in later phases
	var animation_speed = 1.0 + (current_phase - 1) * 0.3
	sprite.speed_scale = animation_speed
	
	# Enable hitbox with correct shape
	_configure_hitboxes(true)
	
	await sprite.animation_finished
	
	# Reset animation speed
	sprite.speed_scale = 1.0
	
	# Disable everything after attack
	_configure_hitboxes(false)
	
	is_attacking = false
	
	# Reduced cooldown in later phases
	var cooldown = ATTACK_COOLDOWN / _get_phase_multiplier()
	attack_timer = cooldown

func take_damage(damage: int) -> void:
	# Avoid processing damage if dead, invincible, or already hit this frame
	if is_dead or is_invincible or hit_registered:
		return
	
	# Mark that we've registered a hit this frame
	hit_registered = true
	
	# Apply damage
	health -= damage
	enemy_damaged.emit(damage)
	
	# Record the hit time for combo tracking
	last_hit_time = Time.get_ticks_msec() / 1000.0
	
	# Increment hit counter and refresh combo window
	_increment_hit_counter()
	
	# Check for phase change
	_check_phase_change()
	
	# Trigger screen shake when taking damage
	var shake_intensity = SCREEN_SHAKE_INTENSITY * 0.8
	_trigger_screen_shake(shake_intensity, 0.15)
	
	if health <= 0:
		die()
	else:
		show_hurt()

func _increment_hit_counter() -> void:
	# Start or refresh the combo timer
	combo_timer = HIT_REGISTER_WINDOW
	
	# Increment hit counter
	hit_counter += 1
	
	# Show visual feedback for hit
	_show_hit_counter_feedback()
	
	# Emit signal for UI updates
	boss_hit_counted.emit(hit_counter, _get_hit_threshold())
	
	# Check if we should counter attack
	if hit_counter >= _get_hit_threshold() and counter_timer <= 0 and not is_casting and not is_attacking:
		# Schedule counter attack
		call_deferred("perform_counter_attack")

func _show_hit_counter_feedback() -> void:
	if hit_number_label:
		# Position the label above the boss
		hit_number_label.position = Vector2(0, -80)
		
		# Set text based on hit counter and threshold
		hit_number_label.text = str(hit_counter) + "/" + str(_get_hit_threshold())
		
		# Make visible
		hit_number_label.visible = true
		
		# Set color based on how close to threshold
		var progress = float(hit_counter) / float(_get_hit_threshold())
		hit_number_label.add_theme_color_override("font_color", Color(1.0, 1.0 - progress, 1.0 - progress))
		
		# Create fade animation
		var tween = create_tween()
		tween.tween_property(hit_number_label, "modulate:a", 0.0, 0.7)
		tween.tween_callback(func(): hit_number_label.visible = false)
	
	# Flash the boss with a color based on hit counter
	if not hit_flash_active:
		hit_flash_active = true
		var flash_color = Color(1.5, 0.5, 0.5, 1.0)
		
		# More intense flash as hits accumulate
		flash_color.r += hit_counter * 0.1
		
		var tween = create_tween()
		tween.tween_property(sprite, "modulate", flash_color, 0.05)
		tween.tween_property(sprite, "modulate", _get_phase_color(), 0.1)
		tween.tween_callback(func(): hit_flash_active = false)

func _get_phase_color() -> Color:
	# Return color based on current phase
	match current_phase:
		1: return Color.WHITE
		2: return Color(1.2, 0.9, 0.9)
		3: return Color(1.4, 0.7, 0.7)
	return Color.WHITE

func _reset_hit_counter() -> void:
	# Reset hit counter and related variables
	hit_counter = 0
	combo_timer = 0.0
	
	# Emit signal with reset counter
	boss_hit_counted.emit(hit_counter, _get_hit_threshold())
	
	if hit_number_label:
		# Show reset feedback
		hit_number_label.text = "RESET"
		hit_number_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		hit_number_label.visible = true
		
		var tween = create_tween()
		tween.tween_property(hit_number_label, "modulate:a", 0.0, 0.7)
		tween.tween_callback(func(): hit_number_label.visible = false)

func perform_counter_attack() -> void:
	if player == null or is_dead:
		return
	
	# Reset counter and start cooldown
	hit_counter = 0
	combo_timer = 0.0
	counter_timer = COUNTER_COOLDOWN
	
	# Set state
	is_casting = true
	is_invincible = true
	velocity.x = 0
	
	# Play casting animation - use ATTACK if CAST doesn't exist
	if sprite.sprite_frames.has_animation("CAST"):
		sprite.play("CAST")
	else:
		sprite.play("ATTACK")  # Fallback to ATTACK animation
	
	# Knockback player with high force
	if player.has_method("apply_knockback"):
		var knockback_direction = -1 if player.global_position.x < global_position.x else 1
		var knockback_force = Vector2(knockback_direction * COUNTER_KNOCKBACK_FORCE * _get_phase_multiplier(), -200)
		player.call_deferred("apply_knockback", knockback_force)
	
	# Enhanced cast effects
	var cast_intensity = SCREEN_SHAKE_INTENSITY * 1.5 * _get_phase_multiplier()
	_trigger_screen_shake(cast_intensity, 0.5)
	
	# Visual effect during cast
	var tween = create_tween()
	tween.tween_property(sprite, "modulate", Color(1.5, 1.5, 0.5), 0.2)  # Yellow flash for counter
	tween.tween_property(sprite, "modulate", _get_phase_color(), 0.3)
	
	# Show counter attack feedback
	if hit_number_label:
		hit_number_label.text = "COUNTER!"
		hit_number_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.0))
		hit_number_label.visible = true
		
		var label_tween = create_tween()
		label_tween.tween_property(hit_number_label, "modulate:a", 0.0, 1.0)
		label_tween.tween_callback(func(): hit_number_label.visible = false)
	
	# Wait for animation to complete before spawning
	await sprite.animation_finished
	
	# Spawn enemies based on phase
	spawn_enemies()
	
	# Reset state after counter attack
	is_casting = false
	is_invincible = false
	
	# Emit signal with reset counter
	boss_hit_counted.emit(hit_counter, _get_hit_threshold())

func spawn_enemies() -> void:
	if is_dead:
		return

	# Always try to spawn up to MAX_SPAWNED_ENEMIES
	var spawn_count = MAX_SPAWNED_ENEMIES

	for i in range(spawn_count):
		# Select scene path using Python‐style ternary
		var scene_path = melee_enemy if (i % 2 == 0) else range_enemy
		var packed_scene: PackedScene = load(scene_path)
		if not packed_scene:
			push_warning("Failed to load enemy scene: %s" % scene_path)
			continue

		var enemy_instance = packed_scene.instantiate()

		# Spread them out: -150, +150, -300, +300, etc.
		var direction = -1 if (i % 2 == 0) else 1
		var x_off = 150 * direction * (i + 1)
		enemy_instance.global_position = global_position + Vector2(x_off, 0)

		get_tree().current_scene.add_child(enemy_instance)
		boss_spawned_enemy.emit(scene_path)

func apply_knockback(knockback_force: Vector2) -> void:
	# No knockback when invincible
	if is_invincible:
		return
		
	# Reduce knockback in later phases (boss becomes more stable)
	var phase_resistance = 1.0 - (current_phase - 1) * 0.2
	knockback_force *= phase_resistance
	
	# Apply knockback with both horizontal and vertical force
	is_knocked_back = true
	knockback_velocity = knockback_force
	
	# Ensure minimum horizontal force based on source direction
	if abs(knockback_velocity.x) < 100:
		# Get direction from knockback_force's sign
		var direction = 1 if knockback_velocity.x > 0 else -1
		knockback_velocity.x = direction * 100
	
	# Ensure minimum vertical force for better visual feedback
	if abs(knockback_velocity.y) < 100:
		knockback_velocity.y = -150

func show_hurt() -> void:
	is_hurt = true
	sprite.play("HURT")
	
	# Flash effect during hurt animation
	var tween = create_tween()
	tween.set_loops(2)
	tween.tween_property(sprite, "modulate:a", 0.5, 0.1)
	tween.tween_property(sprite, "modulate:a", 1.0, 0.1)
	
	# Allow animation to complete
	await sprite.animation_finished
	
	is_hurt = false
	
func die() -> void:
	is_dead = true
	velocity = Vector2.ZERO
	sprite.play("DEATH")
	
	# Big screen shake on death
	_trigger_screen_shake(SCREEN_SHAKE_INTENSITY * 3, 1.0)
	
	# Death flash effect
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(sprite, "modulate", Color.WHITE * 2, 0.2)
	tween.tween_property(sprite, "modulate", Color.WHITE, 0.5)
	
	# Disable collisions safely
	collision_shape.set_deferred("disabled", true)
	_configure_hitboxes(false)
	
	# Wait for death animation
	await sprite.animation_finished
	
	# Emit signal before removing
	enemy_died.emit()
	queue_free()

func _on_attack_hitbox_body_entered(body: Node2D) -> void:
	if body == self:
		return
		
	if body.is_in_group("PLAYER") and body.has_method("take_damage"):
		# Increased damage in later phases
		var damage = ATTACK_DAMAGE * _get_phase_multiplier()
		body.call_deferred("take_damage", int(damage))
		
		# Apply knockback to player if they have the method
		if body.has_method("apply_knockback"):
			var knockback_direction = -1 if body.global_position.x < global_position.x else 1
			var knockback_multiplier = _get_phase_multiplier()
			var knockback_force = Vector2(knockback_direction * 200 * knockback_multiplier, -150 * knockback_multiplier)
			body.call_deferred("apply_knockback", knockback_force)

func _on_attack_hitbox_area_entered(area: Area2D) -> void:
	if area.get_parent() == self:
		return
		
	# Check if area's parent is player
	var parent = area.get_parent()
	if parent and parent.is_in_group("PLAYER"):
		# Increased damage in later phases
		var damage = ATTACK_DAMAGE * _get_phase_multiplier()
		
		if area.has_method("take_damage"):
			area.call_deferred("take_damage", int(damage))
		elif parent.has_method("take_damage"):
			parent.call_deferred("take_damage", int(damage))
			
		# Apply knockback to player if they have the method
		if parent.has_method("apply_knockback"):
			var knockback_direction = -1 if parent.global_position.x < global_position.x else 1
			var knockback_multiplier = _get_phase_multiplier()
			var knockback_force = Vector2(knockback_direction * 200 * knockback_multiplier, -150 * knockback_multiplier)
			parent.call_deferred("apply_knockback", knockback_force)

# Additional boss methods for monitoring
func get_health_percentage() -> float:
	return float(health) / float(MAX_HEALTH)

func get_current_phase() -> int:
	return current_phase

func is_boss_enraged() -> bool:
	return is_enraged

func get_hit_counter() -> int:
	return hit_counter

func get_counter_cooldown() -> float:
	return counter_timer
