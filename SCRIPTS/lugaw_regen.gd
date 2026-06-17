extends CharacterBody2D

@export var HEALTH_RESTORE: int = 45
@export var GRAVITY: float = 980.0
@export var COLLECTION_EFFECT_DURATION: float = 0.5
@export var DROP_CHANCE: float = 1.0  # 30% chance to drop from enemies

var collected := false

@onready var sprite := $AnimatedSprite2D
@onready var collision_shape := $CollisionShape2D
@onready var audio_player := $AudioStreamPlayer2D
@onready var pickup_area := $Area2D

signal health_restored(amount: int)

func _ready():
	# Make sure the animation is playing
	if sprite.sprite_frames != null && sprite.sprite_frames.has_animation("LUGAW_REGEN"):
		sprite.play("LUGAW_REGEN")
	else:
		push_warning("Missing LUGAW_REGEN animation in AnimatedSprite2D")
		
	pickup_area.body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	if not collected:
		velocity.y += GRAVITY * delta
		move_and_slide()

func _on_body_entered(body: Node) -> void:
	if collected:
		return
	
	if body.is_in_group("PLAYER"):
		collected = true
		
		# Restore player health if the method exists
		if body.has_method("restore_health"):
			body.call_deferred("restore_health", HEALTH_RESTORE)
		
		# Emit signal for other systems (UI, sound effects, etc.)
		health_restored.emit(HEALTH_RESTORE)
		print("Health restored: ", HEALTH_RESTORE)
		
		_play_collection_animation()

func _play_collection_animation():
	$CollisionShape2D.set_deferred("disabled", true)

	# Play collection sound if available
	if audio_player and audio_player.stream:
		audio_player.play()

	var tween = create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
	
	# Pop scale-up quick
	tween.tween_property(self, "scale", Vector2(1.5, 1.5), 0.1)
	
	# Then shrink, move up and spin together
	tween.tween_property(self, "scale", Vector2(0.1, 0.1), 0.3)
	tween.parallel().tween_property(self, "position:y", position.y - 50, 0.3)
	
	var sprite_node = null
	if has_node("Sprite2D"):
		sprite_node = $Sprite2D
	elif has_node("AnimatedSprite2D"):
		sprite_node = $AnimatedSprite2D
	
	if sprite_node:
		tween.parallel().tween_property(sprite_node, "rotation", sprite_node.rotation + PI * 1, 0.3)
	
	# When done, queue_free
	tween.tween_callback(func():
		queue_free()
	)
