extends Area2D

# Projectile properties
var direction: int = 1  # 1 = right, -1 = left
var speed: float = 200.0
var damage: int = 10
var target_group: String = ""

# How long the projectile exists before auto-destroying
@export var LIFETIME: float = 1.5  # Reduced from 5.0 to 2.0 seconds
@export var FADE_DURATION: float = 0.5  # How long the fade-out animation takes

# Cached references
@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var lifetime_timer: Timer = $LifetimeTimer

func _ready() -> void:
	
	# Set up auto-destroy timer
	lifetime_timer = Timer.new()
	add_child(lifetime_timer)
	lifetime_timer.wait_time = LIFETIME
	lifetime_timer.one_shot = true
	lifetime_timer.timeout.connect(_on_lifetime_expired)
	lifetime_timer.start()

func _process(delta: float) -> void:
	# Move in the specified direction
	position.x += direction * speed * delta
	
	# Optional: Rotate the sprite based on direction
	if direction < 0:
		sprite.flip_h = true

# Initialize the projectile with necessary properties
func initialize(dir: int, spd: float, dmg: int, target: String) -> void:
	direction = dir
	speed = spd
	damage = dmg
	target_group = target
	
	# Update appearance based on direction
	if direction < 0:
		sprite.flip_h = true

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group(target_group) and body.has_method("take_damage"):
		# Apply damage
		body.take_damage(damage)
		
		# Apply knockback if possible
		if body.has_method("apply_knockback"):
			var knockback_force = Vector2(direction * 200, -150)
			body.apply_knockback(knockback_force)
		
		# Destroy the projectile
		queue_free()
	elif not body.is_in_group("ENEMIES"):
		# Hit something else (like terrain), destroy the projectile
		start_disappear_animation()

func _on_area_entered(area: Area2D) -> void:
	var parent = area.get_parent()
	
	if parent and parent.is_in_group(target_group):
		# Check if area or its parent can take damage
		if area.has_method("take_damage"):
			area.take_damage(damage)
		elif parent.has_method("take_damage"):
			parent.take_damage(damage)
			
		# Apply knockback if possible
		if parent.has_method("apply_knockback"):
			var knockback_force = Vector2(direction * 200, -150)
			parent.apply_knockback(knockback_force)
			
		# Destroy the projectile
		queue_free()

# Called when the lifetime expires
func _on_lifetime_expired() -> void:
	start_disappear_animation()

# Start the fade-out animation
func start_disappear_animation() -> void:
	# Disable collision to prevent further interactions
	collision_shape.set_deferred("disabled", true)
	
	# Stop the projectile movement
	speed = 0
	
	# Create a tween for the fade-out effect
	var tween = create_tween()
	tween.tween_property(sprite, "modulate:a", 0.0, FADE_DURATION)
	tween.tween_callback(queue_free)
