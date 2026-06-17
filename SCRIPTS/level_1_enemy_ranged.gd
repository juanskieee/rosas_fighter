extends CharacterBody2D

# Constants - Use @export for easy adjustments in the Inspector
@export var WALK_SPEED: float = 90.0
@export var RUN_SPEED: float = 150.0
@export var GRAVITY: float = 980.0
@export var SHOOTING_RANGE: float = 600.0         # Range at which enemy will stop and shoot
@export var IDEAL_RANGE: float = 600.0            # Enemy tries to maintain this distance
@export var TOO_CLOSE_RANGE: float = 550.0        # Enemy backs away if player closer than this
@export var DETECTION_RANGE: float = 800.0        # Range at which enemy detects player
@export var SHOOT_COOLDOWN: float = 2.0           # Time between shots
@export var KNOCKBACK_RECOVERY_SPEED: float = 500.0
@export var MAX_HEALTH: int = 100
@export var PROJECTILE_DAMAGE: int = 20
@export var PROJECTILE_SPEED: float = 300.0
@export var PROJECTILE_FADE_DURATION: float = 0.5 # Time for fade-out animation (in seconds)
@export var COIN_DROP_CHANCE: float = 0.75
@export var LUGAW_DROP_CHANCE: float = 1.0
@export var BLOOD_EFFECT_DURATION: float = 0.3  # Duration for blood effect animation
@export var BLOOD_EFFECT_SCENE: PackedScene  # Reference to the blood effect scene

# Projectile scene path - set this in the inspector
@export var projectile_scene_path: String = "res://SCENES/LEVEL1_ENEMY_RANGE_PROJECTILE.tscn"

# Member variables
var health: int = MAX_HEALTH
var facing_direction: int = 1
var is_shooting: bool = false
var is_hurt: bool = false
var is_dead: bool = false
var shoot_timer: float = 0.0
var knockback_velocity: Vector2 = Vector2.ZERO
var is_knocked_back: bool = false
var player = null
var current_blood_effect = null  # Reference to current blood effect instance

# Cached node references for better performance
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
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
		
	# Update shoot cooldown
	if shoot_timer > 0:
		shoot_timer -= delta
	
	# Update any active blood effect position to follow enemy
	_update_blood_effect_position()
	
	# Process different states
	if is_knocked_back:
		_process_knockback(delta)
	elif is_shooting:
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
	
	# Player direction (for shooting and approaching)
	facing_direction = 1 if direction > 0 else -1
	
	# Determine action based on distance
	if distance < DETECTION_RANGE:
		if distance < SHOOTING_RANGE and shoot_timer <= 0:
			# Stop and shoot
			perform_shoot()
			# When shooting, always face the player
			sprite.flip_h = facing_direction < 0
		elif distance < TOO_CLOSE_RANGE:
			# Too close, back away
			velocity.x = -facing_direction * RUN_SPEED
			if not is_hurt:
				sprite.play("RUN")
				# When backing away, show enemy facing AWAY from player (retreating)
				sprite.flip_h = facing_direction > 0
		elif distance > IDEAL_RANGE:
			# Too far, move closer
			velocity.x = facing_direction * WALK_SPEED
			if not is_hurt:
				sprite.play("WALK")
				# When approaching, face the player
				sprite.flip_h = facing_direction < 0
		else:
			# In ideal range, stop and prepare to shoot
			velocity.x = 0
			if not is_hurt:
				sprite.play("IDLE")
				# When idle, face the player
				sprite.flip_h = facing_direction < 0
	else:
		# Player out of detection range
		velocity.x = 0
		if not is_hurt:
			sprite.play("IDLE")
			# When idle, face the player if detected before
			sprite.flip_h = facing_direction < 0

func perform_shoot() -> void:
	is_shooting = true
	velocity.x = 0
	
	# Disconnect any existing connections to avoid issues
	if sprite.is_connected("frame_changed", _on_frame_changed):
		sprite.frame_changed.disconnect(_on_frame_changed)
	
	# Connect to the frame_changed signal
	sprite.frame_changed.connect(_on_frame_changed)
	
	# Play the shooting animation
	sprite.play("SHOOT")
	
	# Wait for animation to complete
	await sprite.animation_finished
	
	# Disconnect the signal after the animation is done
	if sprite.is_connected("frame_changed", _on_frame_changed):
		sprite.frame_changed.disconnect(_on_frame_changed)
	
	# Reset state and start cooldown
	is_shooting = false
	shoot_timer = SHOOT_COOLDOWN
	
func _on_frame_changed() -> void:
	# Check if we're at the middle frame to shoot
	var frame_count = sprite.sprite_frames.get_frame_count("SHOOT")
	var shoot_frame = int(frame_count / 2)
	
	# Check if we're in the shooting animation and at the right frame
	if sprite.animation == "SHOOT" and sprite.frame == shoot_frame:
		spawn_projectile()

func spawn_projectile() -> void:	
	# Load the projectile scene
	var projectile_scene = load(projectile_scene_path)
	if projectile_scene == null:
		push_error("Failed to load projectile scene at path: " + projectile_scene_path)
		return
		
	var projectile = projectile_scene.instantiate()
	
	# Add to scene
	get_tree().current_scene.add_child(projectile)
	
	# Position projectile (adjust this offset based on your sprite)
	var spawn_offset = Vector2(20 * facing_direction, -10)
	projectile.global_position = global_position + spawn_offset
	
	# Configure projectile
	if projectile.has_method("initialize"):
		projectile.initialize(
			facing_direction, 
			PROJECTILE_SPEED, 
			PROJECTILE_DAMAGE, 
			"PLAYER"  # Target group
		)
	
	if "FADE_DURATION" in projectile:
		projectile.FADE_DURATION = PROJECTILE_FADE_DURATION

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
