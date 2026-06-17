extends CharacterBody2D

# Constants - Use @export for easy adjustments in the Inspector
@export var WALK_SPEED: float = 200.0
@export var RUN_SPEED: float = 350.0
@export var JUMP_VELOCITY: float = -550.0
@export var GRAVITY: float = 980.0
@export var MAX_HEALTH: int = 200
@export var ATTACK_DAMAGE: int = 100
@export var INVINCIBILITY_DURATION: float = 0.1
@export var KNOCKBACK_FORCE: Vector2 = Vector2(200, -150)
@export var KNOCKBACK_RECOVERY_SPEED: float = 500.0
@export var REGEN_ANIMATION_DURATION: float = 0.6  # Duration for regen animation
@export var REGEN_EFFECT_SCENE: PackedScene  # Reference to the regeneration effect scene
@export var BLOOD_EFFECT_SCENE: PackedScene  # Reference to the blood effect scene

# Signals for integration with other systems
signal health_changed(new_health: int, max_health: int)
signal player_died()

# Member variables
var health: int = MAX_HEALTH
var can_move := true
var facing_direction: int = 1
var invincibility_time: float = 0.0
var knockback_velocity: Vector2 = Vector2.ZERO
var is_knocked_back: bool = false
var is_regenerating: bool = false  # Track if regeneration animation is playing
var current_regen_effect = null  # Reference to current regeneration effect instance
var current_blood_effect = null  # Reference to current blood effect instance

# State management with clear names
enum PlayerState {IDLE, WALKING, RUNNING, JUMPING, ATTACKING, HURT, DEAD, REGENERATING}
var current_state: int = PlayerState.IDLE
var previous_state: int = PlayerState.IDLE  # Store previous state for returning after regeneration

# Cached node references
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var attack_hitbox: Area2D = $AttackHitbox
@onready var right_hitbox: CollisionShape2D = $AttackHitbox/RightHitbox
@onready var left_hitbox: CollisionShape2D = $AttackHitbox/LeftHitbox
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var jump_sfx: AudioStreamPlayer2D = $JumpSFX
@onready var run_sfx: AudioStreamPlayer2D = $RunSFX
@onready var walk_sfx: AudioStreamPlayer2D = $WalkSFX
@onready var slash_sfx: AudioStreamPlayer2D = $SlashSFX
@onready var hurt_sfx: AudioStreamPlayer2D = $HurtSFX



func _ready() -> void:
	# Add to player group for enemy targeting
	add_to_group("PLAYER")
	
	# Configure hitbox
	_configure_hitboxes(false)
	
	# Emit initial health
	health_changed.emit(health, MAX_HEALTH)

func _physics_process(delta: float) -> void:
	# Skip controls if dead
	if current_state == PlayerState.DEAD:
		return
		
	# Handle invincibility timer
	_process_invincibility(delta)
	
	if not can_move:
		# Still allow IDLE animation update
		sprite.play("IDLE")
		if run_sfx.playing:
			run_sfx.stop()
		if walk_sfx.playing:
			walk_sfx.stop()
		
		return
	
	# Apply gravity when in air
	if not is_on_floor():
		velocity.y += GRAVITY * delta
		# Ensure jumping state is set whenever in air (unless attacking, hurt or dead)
		if current_state != PlayerState.ATTACKING and current_state != PlayerState.HURT and current_state != PlayerState.DEAD:
			current_state = PlayerState.JUMPING

	# Process knockback if active
	if is_knocked_back:
		_process_knockback(delta)
	else:
		# Process player input and state - NOW ALLOWING INPUT DURING REGENERATION
		_handle_attack_input()
		_handle_movement_input()
	
	# Update any active regeneration effect position to follow player
	_update_regen_effect_position()
	
	_update_animation()
	
	# Apply movement
	move_and_slide()

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
		if current_state == PlayerState.HURT:
			if not is_on_floor():
				current_state = PlayerState.JUMPING
			else:
				current_state = PlayerState.IDLE

func _process_invincibility(delta: float) -> void:
	if invincibility_time > 0:
		invincibility_time -= delta

func _handle_attack_input() -> void:
	# Only allow attacks if not already attacking or in a restricted state
	if Input.is_action_just_pressed("ATTACK") and current_state != PlayerState.ATTACKING and current_state != PlayerState.HURT and current_state != PlayerState.DEAD:
		_perform_attack()

func _perform_attack() -> void:
	current_state = PlayerState.ATTACKING
	# Play slash sound effect
	if slash_sfx and slash_sfx.stream:
		slash_sfx.play()
	sprite.play("ATTACK")
	
	# Enable the appropriate hitbox based on facing direction
	_configure_hitboxes(true)
	
	# Wait for animation to complete before returning to normal state
	await sprite.animation_finished
	
	# Disable hitboxes after attack
	_configure_hitboxes(false)
	
	# Return to appropriate state if not interrupted by another state
	if current_state == PlayerState.ATTACKING:
		# Check if player is in air or on ground for correct state transition
		if not is_on_floor():
			current_state = PlayerState.JUMPING
		else:
			current_state = PlayerState.IDLE

func _configure_hitboxes(enabled: bool) -> void:
	attack_hitbox.monitoring = enabled
	attack_hitbox.monitorable = enabled
	
	if enabled:
		right_hitbox.disabled = facing_direction < 0
		left_hitbox.disabled = facing_direction > 0
	else:
		right_hitbox.disabled = true
		left_hitbox.disabled = true

func _handle_movement_input() -> void:
	# Skip movement processing during certain states
	if current_state == PlayerState.ATTACKING:
		velocity.x = move_toward(velocity.x, 0, WALK_SPEED)
		return
		  
	# Handle jump input
	if Input.is_action_just_pressed("JUMP") and is_on_floor() and current_state != PlayerState.DEAD:
		velocity.y = JUMP_VELOCITY
		# Play jump sound effect
		if jump_sfx and jump_sfx.stream:
			jump_sfx.play()
		current_state = PlayerState.JUMPING
	
	# Calculate horizontal movement
	var direction := Input.get_axis("WALK_LEFT", "WALK_RIGHT")
	var is_running := Input.is_action_pressed("RUN") and current_state != PlayerState.ATTACKING and current_state != PlayerState.HURT
	
	if direction != 0:
		facing_direction = 1 if direction > 0 else -1
		sprite.flip_h = facing_direction < 0
		
		# Set state and speed
		var current_speed := RUN_SPEED if is_running else WALK_SPEED
		velocity.x = direction * current_speed
		
		# Only change to walking/running if on floor
		if is_on_floor() and current_state != PlayerState.HURT and current_state != PlayerState.ATTACKING:
			current_state = PlayerState.RUNNING if is_running else PlayerState.WALKING
	else:
		velocity.x = move_toward(velocity.x, 0, WALK_SPEED)
		if is_on_floor() and current_state != PlayerState.HURT and current_state != PlayerState.ATTACKING:
			current_state = PlayerState.IDLE

func _update_animation() -> void:
	match current_state:
		PlayerState.IDLE:
			sprite.play("IDLE")
			# Stop movement sounds when idle
			if run_sfx.playing:
				run_sfx.stop()
			if walk_sfx.playing:
				walk_sfx.stop()
		PlayerState.WALKING:
			# Play walk sound if not already playing
			if not walk_sfx.playing:
				walk_sfx.play()
			sprite.play("WALK")
			# Stop run sound if playing
			if run_sfx.playing:
				run_sfx.stop()
		PlayerState.RUNNING:
			if not run_sfx.playing:
				run_sfx.play()
			sprite.play("RUN")
			# Stop walk sound if playing
			if walk_sfx.playing:
				walk_sfx.stop()
		PlayerState.JUMPING:
			sprite.play("JUMP")
			# Stop movement sounds when jumping
			if run_sfx.playing:
				run_sfx.stop()
			if walk_sfx.playing:
				walk_sfx.stop()
		PlayerState.HURT:
			if not hurt_sfx.playing:
				hurt_sfx.play()
			sprite.play("HURT")
			# Stop movement sounds when hurt
			if run_sfx.playing:
				run_sfx.stop()
			if walk_sfx.playing:
				walk_sfx.stop()
		PlayerState.REGENERATING:
			sprite.play("IDLE")
			if run_sfx.playing:
				run_sfx.stop()
			if walk_sfx.playing:
				walk_sfx.stop()
		PlayerState.ATTACKING:
			pass
		PlayerState.DEAD:
			pass

# Signal handlers for hitbox interactions
func _on_attack_hitbox_body_entered(body: Node2D) -> void:
	if body == self:
		return

	if body.is_in_group("ENEMIES") and body.has_method("take_damage"):
		body.take_damage(ATTACK_DAMAGE)
		
		# Apply knockback to enemy if it has velocity
		if body is CharacterBody2D:
			# Check if the enemy can handle directed knockback
			if body.has_method("apply_knockback"):
				body.apply_knockback(Vector2(facing_direction * KNOCKBACK_FORCE.x, KNOCKBACK_FORCE.y))
			else:
				# Legacy fallback
				body.velocity.x = facing_direction * KNOCKBACK_FORCE.x
				body.velocity.y = KNOCKBACK_FORCE.y

func _on_attack_hitbox_area_entered(area: Area2D) -> void:
	if area.get_parent() == self:
		return

	var target = null
	
	# Direct damage method on area
	if area.has_method("take_damage"):
		area.take_damage(ATTACK_DAMAGE)
		target = area
	# Damage method on parent
	elif area.get_parent() and area.get_parent().has_method("take_damage") and area.get_parent().is_in_group("ENEMIES"):
		area.get_parent().take_damage(ATTACK_DAMAGE)
		target = area.get_parent()
		
	# Apply knockback if target is valid
	if target and target is CharacterBody2D:
		if target.has_method("apply_knockback"):
			target.apply_knockback(Vector2(facing_direction * KNOCKBACK_FORCE.x, KNOCKBACK_FORCE.y))
		else:
			# Legacy fallback
			target.velocity.x = facing_direction * KNOCKBACK_FORCE.x
			target.velocity.y = KNOCKBACK_FORCE.y

func take_damage(damage: int) -> void:
	# Prevent damage during invincibility or regeneration
	if current_state == PlayerState.DEAD or invincibility_time > 0 or current_state == PlayerState.REGENERATING:
		return
		
	health -= damage
	invincibility_time = INVINCIBILITY_DURATION
	
	# Emit signal for UI updates
	health_changed.emit(health, MAX_HEALTH)
	
	if health <= 0:
		die()
	else:
		show_hurt()

# UPDATE THE show_hurt() FUNCTION (replace the existing function):
func show_hurt() -> void:
	current_state = PlayerState.HURT

	# Apply proper horizontal + vertical knockback
	apply_knockback(Vector2(-facing_direction * 200, -150))

	# Flash effect during hurt animation
	var tween = create_tween()
	tween.set_loops(2)
	tween.tween_property(sprite, "modulate:a", 0.5, 0.1)
	tween.tween_property(sprite, "modulate:a", 1.0, 0.1)
	
	# Play blood effect
	_play_blood_effect()

# ADD THIS NEW FUNCTION (add anywhere in the script):
func _play_blood_effect() -> void:
	# Instantiate the blood effect scene if provided
	if BLOOD_EFFECT_SCENE:
		# Remove any existing blood effect
		if current_blood_effect:
			current_blood_effect.queue_free()
		
		# Create the new effect 
		current_blood_effect = BLOOD_EFFECT_SCENE.instantiate()
	
		# Make the effect a child of the player so it moves with the player
		get_tree().get_root().add_child(current_blood_effect)
		
		# Reset the position to be centered (local coordinates since it's a child)
		current_blood_effect.position = Vector2.ZERO
		
		# Ensure it appears above the player sprite
		if current_blood_effect.z_index <= 0:
			current_blood_effect.z_index = 1
		
		# Make it face the same direction as the player
		if current_blood_effect.has_node("AnimatedSprite2D"):
			var effect_sprite = current_blood_effect.get_node("AnimatedSprite2D")
			effect_sprite.flip_h = sprite.flip_h
		
		# If it's a CharacterBody2D, disable physics and collision
		if current_blood_effect is CharacterBody2D:
			# Disable gravity and collision response
			current_blood_effect.set_physics_process(false)
			
			# Disable collision shape
			if current_blood_effect.has_node("CollisionShape2D"):
				var collision = current_blood_effect.get_node("CollisionShape2D")
				collision.set_deferred("disabled", true)
		
		# Play the animation if it has one
		if current_blood_effect.has_node("AnimatedSprite2D"):
			var anim_sprite = current_blood_effect.get_node("AnimatedSprite2D")
			# Check if the animation exists
			if anim_sprite.sprite_frames.has_animation("BLOOD"):
				anim_sprite.play("BLOOD")
			# Fall back to the first available animation if BLOOD doesn't exist
			elif anim_sprite.sprite_frames.get_animation_names().size() > 0:
				anim_sprite.play(anim_sprite.sprite_frames.get_animation_names()[0])
			
			# Connect to animation finished signal to clean up
			if not anim_sprite.animation_finished.is_connected(_on_blood_effect_finished):
				anim_sprite.animation_finished.connect(_on_blood_effect_finished)

# ADD THIS NEW FUNCTION (add anywhere in the script):
func _on_blood_effect_finished() -> void:
	# Clean up the blood effect when animation finishes
	if current_blood_effect:
		current_blood_effect.queue_free()
		current_blood_effect = null
	
func apply_knockback(knockback_force: Vector2) -> void:
	is_knocked_back = true
	knockback_velocity = knockback_force
	
	# Ensure minimum vertical force for better visual feedback
	if abs(knockback_velocity.y) < 50:
		knockback_velocity.y = -150
	
func die() -> void:
	current_state = PlayerState.DEAD
	velocity = Vector2.ZERO
	sprite.play("DEATH")
	
	# Disable collisions
	collision_shape.set_deferred("disabled", true)
	_configure_hitboxes(false)
	
	await sprite.animation_finished
	
	# Emit death signal for game manager to handle
	player_died.emit()

func collect_coin(value: int = 1) -> void:
	print("Player collected a coin worth ", value, " points!")

func restore_health(amount: int) -> void:
	# Don't regenerate if already at max health or dead
	if health >= MAX_HEALTH or current_state == PlayerState.DEAD:
		return
		
	# Ensure we don't go above MAX_HEALTH
	var old_health = health
	health = min(health + amount, MAX_HEALTH)
	
	# Only emit signal and play effect if health actually changed
	if health != old_health:
		health_changed.emit(health, MAX_HEALTH)
		_play_regeneration_animation()

func _play_regeneration_animation() -> void:
	# If already regenerating, clear any existing effects first
	if is_regenerating:
		# Kill any active tweens
		get_tree().create_tween().kill() # This ensures all tweens owned by this node are killed
		
		# Remove existing effect
		if current_regen_effect:
			current_regen_effect.queue_free()
			current_regen_effect = null
	else:
		# Save the previous state to return to it after regeneration
		previous_state = current_state
	
	# Change to regenerating state
	current_state = PlayerState.REGENERATING
	is_regenerating = true
	
	# Store original values to ensure we always return to them
	var original_scale = Vector2(1.0, 1.0) # Use default scale values
	var original_color = Color(1.0, 1.0, 1.0, 1.0) # Use default color values
	
	# Create a small scale pop effect with a new tween
	var scale_tween = create_tween()
	scale_tween.tween_property(self, "scale", original_scale * 1.1, 0.15).set_ease(Tween.EASE_OUT)
	scale_tween.tween_property(self, "scale", original_scale, 0.15).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BOUNCE)
	
	# Add green tint when regenerating with a new tween
	var color_tween = create_tween()
	# Tween to green tint
	color_tween.tween_property(sprite, "modulate", Color(0.7, 1.2, 0.7, 1.0), 0.2)
	# Hold the green tint for a moment
	color_tween.tween_interval(0.2)
	# Tween back to original color
	color_tween.tween_property(sprite, "modulate", original_color, 0.2)
	
	# Instantiate the regeneration effect scene if provided
	if REGEN_EFFECT_SCENE:
		# Remove any existing effect
		if current_regen_effect:
			current_regen_effect.queue_free()
		
		# Create the new effect 
		current_regen_effect = REGEN_EFFECT_SCENE.instantiate()
		
		# Make the effect a child of the player so it moves with the player
		add_child(current_regen_effect)
		
		# Reset the position to be centered (local coordinates since it's a child)
		current_regen_effect.global_position = global_position
		
		# Ensure it appears above the player sprite
		if current_regen_effect.z_index <= 0:
			current_regen_effect.z_index = 1
		
		# Make it face the same direction as the player
		if current_regen_effect.has_node("AnimatedSprite2D"):
			var effect_sprite = current_regen_effect.get_node("AnimatedSprite2D")
			effect_sprite.flip_h = sprite.flip_h
		
		# If it's a CharacterBody2D, disable physics and collision
		if current_regen_effect is CharacterBody2D:
			# Disable gravity and collision response
			current_regen_effect.set_physics_process(false)
			
			# Disable collision shape
			if current_regen_effect.has_node("CollisionShape2D"):
				var collision = current_regen_effect.get_node("CollisionShape2D")
				collision.set_deferred("disabled", true)
		
		# Play the animation if it has one
		if current_regen_effect.has_node("AnimatedSprite2D"):
			var anim_sprite = current_regen_effect.get_node("AnimatedSprite2D")
			# Check if the animation exists
			if anim_sprite.sprite_frames.has_animation("REGENERATE"):
				anim_sprite.play("REGENERATE")
			# Fall back to the first available animation if REGENERATE doesn't exist
			elif anim_sprite.sprite_frames.get_animation_names().size() > 0:
				anim_sprite.play(anim_sprite.sprite_frames.get_animation_names()[0])
	
	# Wait for the regeneration animation duration
	await get_tree().create_timer(REGEN_ANIMATION_DURATION).timeout
	
	# Clean up the effect when done
	if current_regen_effect:
		current_regen_effect.queue_free()
		current_regen_effect = null
	
	# Always ensure we return to normal state, scale, and color
	current_state = previous_state
	is_regenerating = false
	scale = original_scale
	sprite.modulate = original_color

# Add a new function to update the position of any active regeneration effect
func _update_regen_effect_position() -> void:
	if current_regen_effect:
		# Make the effect follow the player
		current_regen_effect.global_position = global_position
		
		# Keep the effect matching the player's direction
		if current_regen_effect.has_node("AnimatedSprite2D"):
			var effect_sprite = current_regen_effect.get_node("AnimatedSprite2D")
			effect_sprite.flip_h = sprite.flip_h
	
	if current_blood_effect:
		# Make the blood effect follow the player
		current_blood_effect.global_position = global_position + Vector2(0, 40)

		# Keep the effect matching the player's direction
		if current_blood_effect.has_node("AnimatedSprite2D"):
			var effect_sprite = current_blood_effect.get_node("AnimatedSprite2D")
			effect_sprite.flip_h = sprite.flip_h
