extends Node2D

func _on_dialogue_trigger_entered(body):
	# Check if the entering body is the player
	if body == player_ref and not dialogue_active:
		print("Player entered dialogue trigger area")
		# Start dialogue sequence
		start_dialogue_sequence()
		
# Configuration - adjust in Inspector
@export var initial_spawn_distance := 500.0
@export var spawn_margin := 1000.0  # Spawn ahead of camera
@export var min_y := 1
@export var max_y := 1
@export var wave_cooldown := 1.0  # Time between waves
@export var enemies_per_wave := [4, 5]
@export var boss_wave := 1
@export var enemy_spacing := 150.0  # Horizontal spacing between pre-spawned enemies
@export var next_waves_to_preload := 2  # How many future waves to preload
@export var max_ranged_enemies := 3  # Maximum number of ranged enemies per wave

# Enemy scenes - assign in Inspector
@export var melee_enemy: String = "res://SCENES/LEVEL1_ENEMY_MELEE.tscn"
@export var range_enemy: String = "res://SCENES/LEVEL1_ENEMY_RANGED.tscn"
@export var boss: String = "res://SCENES/LEVEL1_BOSS_BATO.tscn"
@export var dialogue_scene: String = "res://SCENES/DIALOGUE_SYSTEM.tscn"  # Dialogue system scene

# Internal state
var current_wave := 0
var enemies_alive := 0
var player_ref: Node2D
var camera_ref: Camera2D
var ground_ref: Node2D
var wave_active := false
var preloaded_waves := []  # Array of arrays containing preloaded waves
var enemy_scenes := {}  # Cache for loaded scenes
var boss_instance = null
var dialogue_active := false
var level_started := false
var player_original_position := Vector2.ZERO
var boss_despawn_position := Vector2.ZERO  # Store where boss despawned
var player_movement_disabled := false  # Track player movement state
var current_wave_enemies := []  # Track current wave enemies
var boss_fight_dialogue_active := false
var final_boss_instance = null
var boss_fight_dialogue_triggered := false

signal dialogue_completed

func start_level():
	print("Starting regular level sequence")
	level_started = true
	
	# Play a level start sound/effect if available
	if has_node("LevelStartSound"):
		$LevelStartSound.play()
	
	# Show level start UI notification if needed
	show_level_start_notification()
	
	# Clear any existing preloaded waves to prevent invisible enemies
	clear_all_preloaded_waves()
	
	# DON'T preload waves here - spawn them dynamically to avoid position conflicts
	# for i in range(next_waves_to_preload):
	#     preload_wave(i + 1)
	
	# Start first wave with a slight delay
	await get_tree().create_timer(2.0).timeout
	start_next_wave()

func clear_all_preloaded_waves():
	print("Clearing any existing preloaded waves")
	for wave in preloaded_waves:
		for enemy in wave:
			if is_instance_valid(enemy):
				enemy.queue_free()
	preloaded_waves.clear()

func show_level_start_notification():
	# Optional: Show "Level Start" or "Wave 1" notification
	# This is just a placeholder - implement based on your UI system
	print("LEVEL START NOTIFICATION WOULD APPEAR HERE")
	
	# Example of how you might implement this:
	# var notification = level_start_notification_scene.instantiate()
	# add_child(notification)
	# notification.show()

func _ready():
	player_ref = get_tree().get_first_node_in_group("PLAYER")
	camera_ref = player_ref.get_node("Camera2D")
	ground_ref = get_parent().get_node("LEVEL1_MAP_GROUND")
	
	# Store original player position
	player_original_position = player_ref.global_position
	
	# Preload enemy scenes to avoid loading during gameplay
	preload_enemy_scenes()
	
	# DON'T preload waves here - wait until level actually starts
	# for i in range(next_waves_to_preload):
	#     preload_wave(i + 1)
	
	# Start with dramatic boss entrance before dialogue
	create_boss_entrance()

func preload_enemy_scenes():
	# Cache enemy scenes to avoid loading during gameplay
	enemy_scenes["melee"] = load(melee_enemy)
	enemy_scenes["range"] = load(range_enemy)
	enemy_scenes["boss"] = load(boss)
	print("Enemy scenes preloaded")

func _process(delta):
	if not level_started:
		return
		
	# Update positions of all preloaded enemies to maintain distance from player
	for wave_index in range(preloaded_waves.size()):
		var wave = preloaded_waves[wave_index]
		for enemy_index in range(wave.size()):
			var enemy = wave[enemy_index]
			if is_instance_valid(enemy) and enemy.visible == false:  # Only move invisible preloaded enemies
				# Calculate base distance from boss despawn position or camera
				var base_x = boss_despawn_position.x if boss_despawn_position != Vector2.ZERO else camera_ref.global_position.x
				var target_x = base_x + spawn_margin + (wave_index * 300)
				# Add spacing between enemies
				target_x += enemy_index * enemy_spacing
				# Move towards target position (only X-axis)
				enemy.global_position.x = target_x

func disable_player_movement():
	player_movement_disabled = true
	if player_ref.has_method("set_can_move"):
		player_ref.set_can_move(false)
	else:
		# Instead of freezing the whole player, use a flag
		player_ref.set("can_move", false)
	print("Player movement disabled (input blocked, animation allowed)")

func enable_player_movement():
	player_movement_disabled = false
	if player_ref.has_method("set_can_move"):
		player_ref.set_can_move(true)
	else:
		player_ref.set("can_move", true)
	print("Player movement enabled (input unblocked)")

func create_boss_entrance():
	print("Creating dramatic boss entrance")
	
	# Disable player movement during entrance sequence
	disable_player_movement()
	
	# Spawn the boss far to the right of the player
	var spawn_x = player_ref.global_position.x + 1500  # Far to the right
	var spawn_y = ground_ref.global_position.y - 0
	
	boss_instance = enemy_scenes["boss"].instantiate()
	boss_instance.global_position = Vector2(spawn_x, spawn_y)
	
	# Disable boss detection during dialogue
	boss_instance.DETECTION_RANGE = 0
	print("Boss detection range set to 0 during dialogue")
	
	# Add a special variable to the boss to identify it's in entrance mode
	boss_instance.set_meta("in_entrance", true)
	
	# Disable boss AI/attacks temporarily
	if boss_instance.has_method("set_ai_enabled"):
		boss_instance.set_ai_enabled(false)
	else:
		# Fallback method - disable physics processing
		boss_instance.set_physics_process(false)
	
	add_child(boss_instance)
	
	# Create camera focus on boss with a short delay
	await camera_focus_on_boss()
	
	# Setup the boss in idle position and create dialogue trigger
	setup_boss_and_dialogue_trigger()

func camera_focus_on_boss():
	print("Camera focusing on boss")
	
	# Optional: Store original camera properties
	var original_position = camera_ref.global_position
	
	#Add delay BEFORE panning
	await get_tree().create_timer(1).timeout  # Add 1 second delay (adjust if needed)
	
	# Tween camera to focus on boss
	var tween = create_tween()
	tween.tween_property(camera_ref, "global_position", Vector2(boss_instance.global_position.x - 200, camera_ref.global_position.y), 1.0)
	
	# Wait for camera movement
	await tween.finished
	
	# Hold focus for dramatic effect
	await get_tree().create_timer(1.0).timeout
	
	# Return camera to player
	tween = create_tween()
	tween.tween_property(camera_ref, "global_position", original_position, 1.0)
	
	await tween.finished
	
	# Re-enable player movement after camera returns
	enable_player_movement()

func setup_boss_and_dialogue_trigger():
	print("Setting up boss in idle pose")
	
	# Set boss to idle animation since he doesn't move
	if boss_instance.has_method("play_animation"):
		boss_instance.play_animation("IDLE")
	elif boss_instance.has_node("AnimationPlayer"):
		boss_instance.get_node("AnimationPlayer").play("IDLE")
	elif boss_instance.has_node("AnimatedSprite2D"):
		boss_instance.get_node("AnimatedSprite2D").play("IDLE")
		print("Playing boss IDLE animation via AnimatedSprite2D")
	
	# Create a dialogue trigger area around the boss
	var trigger_area = Area2D.new()
	trigger_area.name = "DialogueTrigger"
	
	var collision_shape = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(1000, 200)  # Adjust size as needed
	collision_shape.shape = shape
	
	trigger_area.add_child(collision_shape)
	boss_instance.add_child(trigger_area)
	
	# Connect the trigger area to start dialogue when player enters
	trigger_area.body_entered.connect(_on_dialogue_trigger_entered)
	
	print("Dialogue trigger area set up near boss")

func _on_boss_defeated():
	# Handle boss defeat logic
	print("BOSS DEFEATED! LEVEL COMPLETE!")
	get_tree().paused = true

func freeze_characters():
	# Disable player movement
	disable_player_movement()
	

	# Disable boss movement (but keep animations running)
	if boss_instance.has_method("set_can_move"):
		boss_instance.set_can_move(false)
	else:
		# Use a flag instead of disabling physics
		boss_instance.set("can_move", false)
		print("Boss movement disabled (input blocked, animation allowed)")
	
	# Set both characters to IDLE animation
	# FIX: Force play idle animation and ensure it works
	if player_ref.has_method("play_animation"):
		player_ref.play_animation("IDLE")
	elif player_ref.has_node("AnimationPlayer"):
		player_ref.get_node("AnimationPlayer").play("IDLE")
	elif player_ref.has_node("AnimatedSprite2D"):
		player_ref.get_node("AnimatedSprite2D").play("IDLE")
		
	if boss_instance.has_method("play_animation"):
		boss_instance.play_animation("IDLE")
	elif boss_instance.has_node("AnimationPlayer"):
		var anim_player = boss_instance.get_node("AnimationPlayer")
		if anim_player:
			anim_player.play("IDLE")
			print("Playing boss IDLE animation via AnimationPlayer")
	elif boss_instance.has_node("AnimatedSprite2D"):
		var anim_sprite = boss_instance.get_node("AnimatedSprite2D")
		if anim_sprite:
			anim_sprite.play("IDLE")
			print("Playing boss IDLE animation via AnimatedSprite2D")
	
	print("Characters frozen and in IDLE animation for dialogue")

func _on_dialogue_completed():
	dialogue_active = false
	print("Dialogue sequence completed")
	
	# Have boss walk away
	boss_walk_away()

func start_dialogue_sequence():
	print("Starting dialogue sequence")
	
	# Boss is already in position and idle
	
	# Switch characters to idle animation and freeze them
	freeze_characters()
	
	# Make sure the boss exists
	if !is_instance_valid(boss_instance):
		print("ERROR: Boss instance not valid for dialogue!")
		return
		
	# Disable boss detection during dialogue
	boss_instance.DETECTION_RANGE = 0
	print("Boss detection range set to 0 during dialogue")
	
	# Add dialogue mode metadata if not already there
	if !boss_instance.has_meta("in_dialogue"):
		boss_instance.set_meta("in_dialogue", true)
	
	# Remove entrance metadata if present
	if boss_instance.has_meta("in_entrance"):
		boss_instance.remove_meta("in_entrance")
	
	# Start dialogue sequence
	start_dialogue()

func unfreeze_characters():
	# Re-enable player movement
	enable_player_movement()
	
	# Re-enable boss movement
	if boss_instance.has_method("set_can_move"):
		boss_instance.set_can_move(true)
	else:
		boss_instance.set("can_move", true)
		print("Boss movement re-enabled")

	# Re-enable animations if needed
	if player_ref.has_method("set_animation_enabled"):
		player_ref.set_animation_enabled(true)
	
	# Boss movement will be handled by its walk_away method
	print("Player unfrozen after dialogue")

func boss_walk_away():
	print("Boss walking away")
	# Restore detection range in case it's needed again
	boss_instance.DETECTION_RANGE = 1000
	print("Boss detection range restored for walk-away or next phase")
	
	# Keep player frozen during boss exit
	disable_player_movement()
	
	# Boss should always exit to the right
	var walk_direction = 1  # Right
	
	# Set boss facing direction based on walk direction
	boss_instance.scale.x = -abs(boss_instance.scale.x) * walk_direction
	
	# Play walking animation
	if boss_instance.has_method("play_animation"):
		boss_instance.play_animation("WALK")
	elif boss_instance.has_node("AnimationPlayer"):
		var anim_player = boss_instance.get_node("AnimationPlayer")
		if anim_player:
			anim_player.play("WALK")
			print("Playing boss WALK animation for exit")
	elif boss_instance.has_node("AnimatedSprite2D"):
		var anim_sprite = boss_instance.get_node("AnimatedSprite2D")
		if anim_sprite:
			anim_sprite.play("WALK")
			print("Playing boss WALK animation via AnimatedSprite2D for exit")
	
	# Remove dialogue metadata
	if boss_instance.has_meta("in_dialogue"):
		boss_instance.remove_meta("in_dialogue")
	
	# If boss has a walk away method, call it
	if boss_instance.has_method("walk_away"):
		boss_instance.walk_away()
		# Wait for boss to finish walking away
		await get_tree().create_timer(3.0).timeout
	else:
		# Manual walk away implementation
		var original_position = boss_instance.global_position
		var target_position = Vector2(original_position.x + 800, original_position.y)
		
		# Store boss despawn position for enemy spawning
		boss_despawn_position = target_position
		
		# Ensure the boss can move
		if boss_instance.has_method("set_can_move"):
			boss_instance.set_can_move(true)
		else:
			boss_instance.set_physics_process(true)
		
		# Create tween for walking animation
		var tween = create_tween()
		tween.tween_property(boss_instance, "global_position", target_position, 3.0)
		
		# Wait for walking animation to complete
		await tween.finished
		
		# Remove the boss instance
		boss_instance.queue_free()
	
	# Now unfreeze player and start level
	enable_player_movement()
	
	# Start level after boss leaves
	await get_tree().create_timer(1.0).timeout
	start_level()

func preload_wave(wave_number):
	print("Preloading wave " + str(wave_number))
	
	# Skip preload if beyond boss wave
	if wave_number > boss_wave:
		return
		
	var wave_enemies = []
	var enemies_to_spawn = enemies_per_wave[min(wave_number-1, enemies_per_wave.size()-1)]
	
	# Determine enemy types for this wave
	var enemy_types = []
	var range_count = 0
	
	# First, determine how many ranged enemies we'll have (random but capped)
	var desired_ranged = randi() % (max_ranged_enemies + 1)
	
	# Create a list of enemy types in random order
	for i in range(enemies_to_spawn):
		if range_count < desired_ranged:
			enemy_types.append("range")
			range_count += 1
		else:
			enemy_types.append("melee")
	
	# Shuffle the enemy types to randomize positions
	enemy_types.shuffle()
	
	# Now spawn the enemies in the randomized order
	for i in range(enemies_to_spawn):
		var enemy_type = enemy_types[i]
		# Use boss despawn position as reference if available, otherwise use camera
		var base_x = boss_despawn_position.x if boss_despawn_position != Vector2.ZERO else camera_ref.global_position.x
		var spawn_x = base_x + spawn_margin + (i * enemy_spacing)
		var spawn_y = ground_ref.global_position.y - randf_range(min_y, max_y)
		
		var enemy = enemy_scenes[enemy_type].instantiate()
		enemy.global_position = Vector2(spawn_x, spawn_y)
		
		if enemy.has_signal("enemy_died"):
			enemy.enemy_died.connect(_on_enemy_died)
		
		# Make enemy invisible and completely inactive until wave starts
		enemy.visible = false
		enemy.set_process(false)
		enemy.set_physics_process(false)
		
		# If enemy has additional disable methods, use them
		if enemy.has_method("set_monitoring"):
			enemy.set_monitoring(false)
		if enemy.has_method("set_monitorable"):
			enemy.set_monitorable(false)
		
		add_child(enemy)
		wave_enemies.append(enemy)
	
	preloaded_waves.append(wave_enemies)
	print("Wave " + str(wave_number) + " preloaded with " + str(enemies_to_spawn - range_count) + " melee and " + str(range_count) + " ranged enemies in randomized order")

func start_next_wave():
	current_wave += 1
	print("Starting Wave " + str(current_wave))
	
	# Handle boss wave
	if current_wave > boss_wave:
		spawn_final_boss()
		return
	
	wave_active = true
	enemies_alive = 0  # Reset counter
	
	# Instead of using preloaded waves, spawn enemies directly for each wave
	# This prevents position conflicts and invisible enemies
	spawn_wave_enemies()
	
	print("Wave " + str(current_wave) + " started with " + str(enemies_alive) + " enemies")

func spawn_wave_enemies():
	# Spawn enemies directly for the current wave to avoid position conflicts
	var enemies_to_spawn = enemies_per_wave[min(current_wave-1, enemies_per_wave.size()-1)]
	
	# Determine enemy types for this wave with randomization
	var enemy_types = []
	var range_count = 0
	
	# First, determine how many ranged enemies we'll have (random but capped)
	var desired_ranged = randi() % (max_ranged_enemies + 1)
	
	# Create a list of enemy types in random order
	for i in range(enemies_to_spawn):
		if range_count < desired_ranged:
			enemy_types.append("range")
			range_count += 1
		else:
			enemy_types.append("melee")
	
	# Shuffle the enemy types to randomize positions
	enemy_types.shuffle()
	
	# FIXED: Always base spawn position on camera + spawn_margin
	var base_x = camera_ref.global_position.x + spawn_margin
	print("Spawning wave " + str(current_wave) + " at camera position + margin: " + str(base_x))
	
	# Clear current wave tracking array
	current_wave_enemies.clear()
	
	# Now spawn the enemies in the randomized order
	for i in range(enemies_to_spawn):
		var enemy_type = enemy_types[i]
		var spawn_x = base_x + (i * enemy_spacing)
		var spawn_y = ground_ref.global_position.y - randf_range(min_y, max_y)
		
		var enemy = enemy_scenes[enemy_type].instantiate()
		enemy.global_position = Vector2(spawn_x, spawn_y)
		
		# Track this enemy for current wave
		current_wave_enemies.append(enemy)
		
		if enemy.has_signal("enemy_died"):
			enemy.enemy_died.connect(_on_enemy_died)
		
		# Enemy should be visible and active immediately
		enemy.visible = true
		
		add_child(enemy)
		enemies_alive += 1
	
	print("Wave " + str(current_wave) + " spawned with " + str(enemies_to_spawn - range_count) + " melee and " + str(range_count) + " ranged enemies")
	print("All enemies spawned at camera position + " + str(spawn_margin) + " pixels ahead")

func spawn_final_boss():
	print("Spawning final boss!")
	
	# Always use camera position + spawn margin for final boss
	var spawn_x = camera_ref.global_position.x + spawn_margin
	var spawn_y = ground_ref.global_position.y - 150
	
	final_boss_instance = enemy_scenes["boss"].instantiate()
	final_boss_instance.global_position = Vector2(spawn_x, spawn_y)
	
	# Disable boss detection during entrance
	final_boss_instance.DETECTION_RANGE = 0
	print("Final boss detection range set to 0 during entrance")
	
	# Add entrance metadata
	final_boss_instance.set_meta("in_boss_entrance", true)
	
	# Disable boss AI/attacks temporarily
	if final_boss_instance.has_method("set_ai_enabled"):
		final_boss_instance.set_ai_enabled(false)
	else:
		final_boss_instance.set_physics_process(false)
	
	if final_boss_instance.has_signal("enemy_died"):
		final_boss_instance.enemy_died.connect(_on_boss_defeated)
	
	add_child(final_boss_instance)
	
	# Set boss to idle animation
	if final_boss_instance.has_method("play_animation"):
		final_boss_instance.play_animation("IDLE")
	elif final_boss_instance.has_node("AnimationPlayer"):
		final_boss_instance.get_node("AnimationPlayer").play("IDLE")
	elif final_boss_instance.has_node("AnimatedSprite2D"):
		final_boss_instance.get_node("AnimatedSprite2D").play("IDLE")
	
	# Create dialogue trigger for boss fight
	setup_boss_fight_dialogue_trigger()
	
	print("Final boss added to scene with dialogue trigger at position: " + str(final_boss_instance.global_position))
func setup_boss_fight_dialogue_trigger():
	print("Setting up boss fight dialogue trigger")
	
	# Create a dialogue trigger area around the boss
	var trigger_area = Area2D.new()
	trigger_area.name = "BossFightDialogueTrigger"
	
	var collision_shape = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(1200, 300)  # Larger area for boss fight
	collision_shape.shape = shape
	
	trigger_area.add_child(collision_shape)
	final_boss_instance.add_child(trigger_area)
	
	# Connect the trigger area to start boss fight dialogue
	trigger_area.body_entered.connect(_on_boss_fight_dialogue_trigger_entered)
	
	print("Boss fight dialogue trigger area set up")

# Add this new function
func _on_boss_fight_dialogue_trigger_entered(body):
	# Check if the entering body is the player and dialogue hasn't been triggered yet
	if body == player_ref and not boss_fight_dialogue_active and not boss_fight_dialogue_triggered:
		print("Player entered boss fight dialogue trigger area")
		boss_fight_dialogue_triggered = true
		# Start boss fight dialogue sequence
		start_boss_fight_dialogue_sequence()

# Add this new function
func start_boss_fight_dialogue_sequence():
	print("Starting boss fight dialogue sequence")
	
	boss_fight_dialogue_active = true
	
	# Freeze both characters
	freeze_characters_for_boss_fight()
	
	# Start boss fight dialogue
	start_boss_fight_dialogue()

# Add this new function
func freeze_characters_for_boss_fight():
	# Disable player movement
	disable_player_movement()
	
	# Disable boss movement but keep animations
	if final_boss_instance.has_method("set_can_move"):
		final_boss_instance.set_can_move(false)
	else:
		final_boss_instance.set("can_move", false)
	
	# Set both to IDLE animation
	if player_ref.has_method("play_animation"):
		player_ref.play_animation("IDLE")
	elif player_ref.has_node("AnimationPlayer"):
		player_ref.get_node("AnimationPlayer").play("IDLE")
	elif player_ref.has_node("AnimatedSprite2D"):
		player_ref.get_node("AnimatedSprite2D").play("IDLE")
		
	if final_boss_instance.has_method("play_animation"):
		final_boss_instance.play_animation("IDLE")
	elif final_boss_instance.has_node("AnimationPlayer"):
		var anim_player = final_boss_instance.get_node("AnimationPlayer")
		if anim_player:
			anim_player.play("IDLE")
	elif final_boss_instance.has_node("AnimatedSprite2D"):
		var anim_sprite = final_boss_instance.get_node("AnimatedSprite2D")
		if anim_sprite:
			anim_sprite.play("IDLE")
	
	print("Characters frozen for boss fight dialogue")

# Add this new function
func start_boss_fight_dialogue():
	print("Starting boss fight dialogue")
	
	# Instance dialogue system
	var dialogue_instance = load(dialogue_scene).instantiate()
	add_child(dialogue_instance)
	
	# Boss fight dialogue content
	var boss_fight_dialogue_lines = [
		{"speaker": "Bato", "text": "Impressive. You've defeated all my followers."},
		{"speaker": "Leni", "text": "I warned you this was a mistake."},
		{"speaker": "Bato", "text": "Perhaps... but now I get what I truly wanted."},
		{"speaker": "Leni", "text": "And what's that?"},
		{"speaker": "Bato", "text": "A fight with a worthy opponent. Just you and me."},
		{"speaker": "Leni", "text": "I don't want to hurt you, but I will if I have to."},
		{"speaker": "Bato", "text": "Good! That's the spirit I was hoping to see."},
		{"speaker": "Bato", "text": "Let's see what you're truly capable of!"}
	]
	
	# Send dialogue lines to dialogue system
	if dialogue_instance.has_method("set_dialogue"):
		dialogue_instance.set_dialogue(boss_fight_dialogue_lines)
	
	# Connect to dialogue finished signal
	if dialogue_instance.has_signal("dialogue_completed"):
		dialogue_instance.dialogue_completed.connect(_on_boss_fight_dialogue_completed)
	else:
		# Fallback timer
		await get_tree().create_timer(6.0).timeout
		_on_boss_fight_dialogue_completed()

# Add this new function
func _on_boss_fight_dialogue_completed():
	boss_fight_dialogue_active = false
	print("Boss fight dialogue sequence completed")
	
	# Enable boss for actual combat
	enable_boss_for_combat()
	
	# Enable player movement
	enable_player_movement()

# Add this new function
func enable_boss_for_combat():
	print("Enabling boss for combat")
	
	# Restore boss detection range
	final_boss_instance.DETECTION_RANGE = 9000
	
	# Remove entrance metadata
	if final_boss_instance.has_meta("in_boss_entrance"):
		final_boss_instance.remove_meta("in_boss_entrance")
	
	# Enable boss AI/attacks
	if final_boss_instance.has_method("set_ai_enabled"):
		final_boss_instance.set_ai_enabled(true)
	else:
		final_boss_instance.set_physics_process(true)
	
	# Enable boss movement
	if final_boss_instance.has_method("set_can_move"):
		final_boss_instance.set_can_move(true)
	else:
		final_boss_instance.set("can_move", true)
	
	# Remove the dialogue trigger to prevent re-triggering
	var trigger = final_boss_instance.get_node_or_null("BossFightDialogueTrigger")
	if trigger:
		trigger.queue_free()
	
	print("Boss combat enabled - fight begins!")
	
func _on_enemy_died():
	enemies_alive -= 1
	print("Enemy died! Remaining: " + str(enemies_alive))
	
	if enemies_alive <= 0 and wave_active:
		print("Wave completed!")
		wave_active = false
		await get_tree().create_timer(wave_cooldown).timeout
		start_next_wave()

func start_dialogue():
	dialogue_active = true
	print("Starting dialogue sequence")
	
	# Instance dialogue system
	var dialogue_instance = load(dialogue_scene).instantiate()
	add_child(dialogue_instance)
	
	# Set up dialogue content (customize this part based on your dialogue system)
	var dialogue_lines = [
		{"speaker": "Bato", "text": "So... you've finally arrived. I've been waiting for you."},
		{"speaker": "Leni", "text": "Who are you and what do you want?"},
		{"speaker": "Bato", "text": "They call me Bato. I've heard stories about your skills."},
		{"speaker": "Leni", "text": "Whatever you've heard, I'm not interested in fighting."},
		{"speaker": "Bato", "text": "Oh, but I am. I've been looking for a worthy opponent."},
		{"speaker": "Leni", "text": "Then why not just attack me now?"},
		{"speaker": "Bato", "text": "That would be too easy. I want to see how you handle my followers first."},
		{"speaker": "Bato", "text": "Defeat them, and I'll be waiting for you at the end."},
		{"speaker": "Leni", "text": "You're making a mistake."},
		{"speaker": "Bato", "text": "We'll see about that. Until we meet again..."}
	]
	
	# Send dialogue lines to dialogue system
	if dialogue_instance.has_method("set_dialogue"):
		dialogue_instance.set_dialogue(dialogue_lines)
	
	# Connect to dialogue finished signal
	if dialogue_instance.has_signal("dialogue_completed"):
		dialogue_instance.dialogue_completed.connect(_on_dialogue_completed)
	else:
		# If no signal available, use a timer as fallback
		await get_tree().create_timer(8.0).timeout
		_on_dialogue_completed()
