extends CharacterBody2D

@export var VALUE: int = 5
@export var GRAVITY: float = 980.0
@export var COLLECTION_EFFECT_DURATION: float = 0.5

var collected := false

@onready var sprite := $AnimatedSprite2D
@onready var collision_shape := $CollisionShape2D
@onready var audio_player := $AudioStreamPlayer2D
@onready var pickup_area := $Area2D

signal coin_collected(value: int)

func _ready():
	sprite.play("PINK_COIN")
	pickup_area.body_entered.connect(_on_body_entered)  # or area_entered if your player is an Area2D
	
	# Add to COINS group for easy detection by COIN_COUNTER
	add_to_group("COINS")

func _physics_process(delta: float) -> void:
	if not collected:
		velocity.y += GRAVITY * delta
		move_and_slide()

func _on_body_entered(body: Node) -> void:
	if collected:
		return
	
	if body.is_in_group("PLAYER"):
		collected = true
		
		# Call collect_coin method on player if it exists
		if body.has_method("collect_coin"):
			body.call_deferred("collect_coin", VALUE)
		
		# Emit signal with coin value - this will be detected by the COIN_COUNTER
		coin_collected.emit(VALUE)
		print("Coin collected with value: ", VALUE)
		
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
	
	var sprite = null
	if has_node("Sprite2D"):
		sprite = $Sprite2D
	elif has_node("AnimatedSprite2D"):
		sprite = $AnimatedSprite2D
	
	if sprite:
		tween.parallel().tween_property(sprite, "rotation", sprite.rotation + PI * 1, 0.3)
	
	# When done, queue_free
	tween.tween_callback(func():
		queue_free()
	)
