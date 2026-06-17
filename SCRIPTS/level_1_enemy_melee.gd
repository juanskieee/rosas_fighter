extends CharacterBody2D

# Constants - Use @export for easy adjustments in the Inspector
@export var WALK_SPEED: float = 120.0
@export var GRAVITY: float = 980.0
@export var ATTACK_RANGE: float = 100.0
@export var DETECTION_RANGE: float = 800.0
@export var ATTACK_COOLDOWN: float = 0.5
@export var KNOCKBACK_RECOVERY_SPEED: float = 500.0
@export var MAX_HEALTH: int = 150
@export var ATTACK_DAMAGE: int = 15
@export var COIN_DROP_CHANCE: float = 0.75
@export var LUGAW_DROP_CHANCE: float = 0.50
@export var BLOOD_EFFECT_DURATION: float = 0.3  # Duration for blood effect animation
@export var BLOOD_EFFECT_SCENE: PackedScene  # Reference to the blood effect scene

# Member variables
var health: int = MAX_HEALTH
var facing_direction: int = 1
var is_attacking: bool = false
var is_hurt: bool = false
var is_dead: bool = false
var attack_timer: float = 0.0
var knockback_velocity: Vector2 = Vector2.ZERO
var is_knocked_back: bool = false
var player = null
var current_blood_effect = null  # Reference to current blood effect instance

# Cached node references for better performance
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var attack_hitbox: Area2D = $AttackHitbox
@onready var right_hitbox: CollisionShape2D = $AttackHitbox/RightHitbox
@onready var left_hitbox: CollisionShape2D = $AttackHitbox/LeftHitbox
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var death_sfx: AudioStreamPlayer2D = $DeathSFX
@onready var pain_sfx: AudioStreamPlayer2D = $PainSFX

# Signal for game events
signal enemy_died
signal enemy_damaged(amount: int)

func _ready() -> void:
	# Initialize state
	sprite.play("IDLE")
	
	# Add to enemies group for player targeting
	add_to_group("ENEMIES")
	
	# Configure hitbox
	_configure_hitboxes(false)
	
	# Find player on start
	player = get_tree().get_first_node_in_group("PLAYER")
	
	# Set up timer to periodically try to find player if needed
	_setup_player_search_timer()
	
	# Load the blood effect scene if not assigned in editor
	if not BLOOD_EFFECT_SCENE:
		BLOOD_EFFECT_SCENE = load("res://SCENES/BLOODEFFECTS.tscn")

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
		
	# Apply gravity when in air
	if not is_on_floor():
		velocity.y += GRAVITY * delta
		
	# Update attack cooldown
	if attack_timer > 0:
		attack_timer -= delta
	
	# Update any active blood effect position to follow enemy
	_update_blood_effect_position()
	
	# Process different states
	if is_knocked_back:
		_process_knockback(delta)
	elif is_attacking:
		velocity.x = 0
		move_and_slide()
	else:
		_process_ai()
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
	
	# Update sprite direction
	sprite.flip_h = facing_direction < 0
	
	# Determine action based on distance
	if distance < ATTACK_RANGE and attack_timer <= 0:
		perform_attack()
	elif distance < DETECTION_RANGE:
		velocity.x = facing_direction * WALK_SPEED
		if not is_hurt:
			sprite.play("WALK")
	else:
		velocity.x = 0
		if not is_hurt:
			sprite.play("IDLE")

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
	
	# Enable hitbox with correct shape
	_configure_hitboxes(true)
	
	await sprite.animation_finished
	
	# Disable everything after attack
	_configure_hitboxes(false)
	
	is_attacking = false
	attack_timer = ATTACK_COOLDOWN

func take_damage(damage: int) -> void:
	if is_dead:
		return
		
	health -= damage
	enemy_damaged.emit(damage)
	
	if health <= 0:
		die()
	else:
		show_hurt()

func apply_knockback(knockback_force: Vector2) -> void:
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
	# Play pain sound effect
	if pain_sfx and pain_sfx.stream:
		pain_sfx.play()
	sprite.play("HURT")
	
	# Play blood effect animation
	_play_blood_effect()
	
	# Flash effect during hurt animation
	var tween = create_tween()
	tween.set_loops(2)
	tween.tween_property(sprite, "modulate:a", 0.5, 0.1)
	tween.tween_property(sprite, "modulate:a", 1.0, 0.1)
	
	# Allow animation to complete
	await sprite.animation_finished
	
	is_hurt = false

func _play_blood_effect() -> void:
	# Don't play blood effect if already dead
	if is_dead:
		return
		
	# Remove any existing blood effect first
	if current_blood_effect:
		current_blood_effect.queue_free()
		current_blood_effect = null
		
	# Instantiate the blood effect scene if available
	if BLOOD_EFFECT_SCENE:
		# Create the new effect 
		current_blood_effect = BLOOD_EFFECT_SCENE.instantiate()
		
		# Add it to the current scene, not as a child of the enemy
		get_tree().current_scene.add_child(current_blood_effect)
		
		# Position it in the middle of the enemy (slight vertical offset)
		current_blood_effect.global_position = global_position + Vector2(0, 40)
		
		# Ensure it appears above other sprites
		if current_blood_effect.z_index <= 0:
			current_blood_effect.z_index = 1
		
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
			elif anim_sprite.sprite_frames.has_animation("DEFAULT"):
				anim_sprite.play("DEFAULT")
			# Fall back to the first available animation if specific ones don't exist
			elif anim_sprite.sprite_frames.get_animation_names().size() > 0:
				anim_sprite.play(anim_sprite.sprite_frames.get_animation_names()[0])
		
		# Clean up the effect after duration
		await get_tree().create_timer(BLOOD_EFFECT_DURATION).timeout
		
		# Clean up the effect when done
		if current_blood_effect:
			current_blood_effect.queue_free()
			current_blood_effect = null

# Add a new function to update the position of any active blood effect
func _update_blood_effect_position() -> void:
	if current_blood_effect:
		# Make the blood effect follow the enemy's position
		current_blood_effect.global_position = global_position + Vector2(0, 40)
	
func die() -> void:
	is_dead = true
	velocity = Vector2.ZERO
	sprite.play("DEATH")
	
	# Play death sound effect
	if death_sfx and death_sfx.stream:
		death_sfx.play()
	
	# Clean up any active blood effect when dying
	if current_blood_effect:
		current_blood_effect.queue_free()
		current_blood_effect = null
	
	# Disable collisions
	collision_shape.set_deferred("disabled", true)
	
	# Handle loot drops
	_handle_loot_drops()
	
	# Wait for death animation
	await sprite.animation_finished
	
	# Emit signal before removing
	enemy_died.emit()
	queue_free()

# Add this new function to handle loot drops
func _handle_loot_drops() -> void:
	var rng = randf()
	
	# Drop coin with COIN_DROP_CHANCE probability
	if rng <= COIN_DROP_CHANCE:
		var coin_scene = load("res://SCENES/PINK_COIN.tscn")
		if coin_scene:
			var coin = coin_scene.instantiate()
			get_tree().current_scene.add_child(coin)
			coin.global_position = global_position
	
	# Independent roll for LUGAW (health regen) with LUGAW_DROP_CHANCE probability
	if randf() <= LUGAW_DROP_CHANCE:
		var lugaw_scene = load("res://SCENES/LUGAW_REGEN.tscn")
		if lugaw_scene:
			var lugaw = lugaw_scene.instantiate()
			get_tree().current_scene.add_child(lugaw)
			lugaw.global_position = global_position + Vector2(10, -20)  # Offset to avoid overlapping with coin

func _on_attack_hitbox_body_entered(body: Node2D) -> void:
	if body == self:
		return
		
	if body.is_in_group("PLAYER") and body.has_method("take_damage"):
		# Use call_deferred to safely call methods during signal processing
		body.call_deferred("take_damage", ATTACK_DAMAGE)
		
		# Apply knockback to player if they have the method
		if body.has_method("apply_knockback"):
			var knockback_direction = -1 if body.global_position.x < global_position.x else 1
			var knockback_force = Vector2(knockback_direction * 200, -150)
			body.call_deferred("apply_knockback", knockback_force)

func _on_attack_hitbox_area_entered(area: Area2D) -> void:
	if area.get_parent() == self:
		return
		
	# Check if area's parent is player
	var parent = area.get_parent()
	if parent and parent.is_in_group("PLAYER"):
		if area.has_method("take_damage"):
			area.call_deferred("take_damage", ATTACK_DAMAGE)
		elif parent.has_method("take_damage"):
			parent.call_deferred("take_damage", ATTACK_DAMAGE)
			
		# Apply knockback to player if they have the method
		if parent.has_method("apply_knockback"):
			var knockback_direction = -1 if parent.global_position.x < global_position.x else 1
			var knockback_force = Vector2(knockback_direction * 200, -150)
			parent.call_deferred("apply_knockback", knockback_force)
