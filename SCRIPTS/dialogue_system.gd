extends CanvasLayer

# Configuration parameters
@export var text_speed := 0.05  # Text display speed
@export var auto_advance_delay := 2.0  # Time before auto-advancing to next line
@export var dialogue_box_path := "DialogueBox"
@export var speaker_label_path := "DialogueBox/SpeakerName"
@export var dialogue_text_path := "DialogueBox/DialogueText"
@export var continue_indicator_path := "DialogueBox/ContinueIndicator"

# Portrait paths - add these new export variables
@export var leni_portrait_path := "DialogueBox/Leni"
@export var bato_portrait_path := "DialogueBox/Bato"

# Vignette settings
@export var vignette_height := 100  # Height of top/bottom black bars
@export var vignette_fade_duration := 0.5  # How long fade in/out takes

# Entrance animation settings
@export var dialogue_fade_duration := 0.4  # How long dialogue box fades in
@export var portrait_fade_duration := 0.3  # How long portraits fade in
@export var entrance_delay := 0.2  # Delay between vignette and dialogue box

# Internal variables
var dialogue_lines := []
var current_line := 0
var text_displayed := false
var dialogue_running := false
var typing_in_progress := false  # Track if text is currently being typed

# Reference nodes
var dialogue_box
var speaker_label
var dialogue_text
var continue_indicator

# Portrait references - add these new variables
var leni_portrait
var bato_portrait

# Vignette references
var vignette_layer
var top_vignette
var bottom_vignette

# Signal for completion
signal dialogue_completed

func _ready():
	# Get references to nodes
	dialogue_box = get_node(dialogue_box_path)
	speaker_label = get_node(speaker_label_path)
	dialogue_text = get_node(dialogue_text_path)
	continue_indicator = get_node(continue_indicator_path)
	
	# Get portrait references
	leni_portrait = get_node(leni_portrait_path)
	bato_portrait = get_node(bato_portrait_path)
	
	# Create vignette bars
	create_vignette_bars()
	
	# Initially hide dialogue elements and make them transparent
	dialogue_box.visible = false
	dialogue_box.modulate.a = 0.0
	continue_indicator.visible = false
	
	# Initially hide all portraits and make them transparent
	hide_all_portraits()
	setup_portrait_transparency()
	
	# Initially hide vignette
	hide_vignette()

func hide_all_portraits():
	"""Hide all character portraits"""
	leni_portrait.visible = false
	bato_portrait.visible = false

func setup_portrait_transparency():
	"""Set up portraits to be transparent initially"""
	leni_portrait.modulate.a = 0.0
	bato_portrait.modulate.a = 0.0

func create_vignette_bars():
	"""Create the top and bottom black bars for cinematic effect"""
	# Create a separate CanvasLayer for vignette that's behind the dialogue
	vignette_layer = CanvasLayer.new()
	vignette_layer.name = "VignetteLayer"
	vignette_layer.layer = layer - 1  # Put it behind the dialogue layer
	get_tree().current_scene.add_child(vignette_layer)
	
	# Get screen size
	var screen_size = get_viewport().get_visible_rect().size
	
	# Create top vignette bar
	top_vignette = ColorRect.new()
	top_vignette.name = "TopVignette"
	top_vignette.color = Color.BLACK
	top_vignette.size = Vector2(screen_size.x, vignette_height)
	top_vignette.position = Vector2(0, 0)
	top_vignette.modulate.a = 0.0  # Start transparent
	vignette_layer.add_child(top_vignette)
	
	# Create bottom vignette bar
	bottom_vignette = ColorRect.new()
	bottom_vignette.name = "BottomVignette"
	bottom_vignette.color = Color.BLACK
	bottom_vignette.size = Vector2(screen_size.x, vignette_height)
	bottom_vignette.position = Vector2(0, screen_size.y - vignette_height)
	bottom_vignette.modulate.a = 0.0  # Start transparent
	vignette_layer.add_child(bottom_vignette)
	
	print("Vignette bars created on separate layer behind dialogue")

func show_vignette():
	"""Fade in the vignette bars"""
	if top_vignette and bottom_vignette:
		var tween = create_tween()
		tween.parallel().tween_property(top_vignette, "modulate:a", 1.0, vignette_fade_duration)
		tween.parallel().tween_property(bottom_vignette, "modulate:a", 1.0, vignette_fade_duration)
		print("Vignette bars fading in")

func hide_vignette():
	"""Fade out the vignette bars"""
	if top_vignette and bottom_vignette:
		var tween = create_tween()
		tween.parallel().tween_property(top_vignette, "modulate:a", 0.0, vignette_fade_duration)
		tween.parallel().tween_property(bottom_vignette, "modulate:a", 0.0, vignette_fade_duration)
		print("Vignette bars fading out")

func show_speaker_portrait(speaker_name: String):
	"""Show the portrait for the current speaker and hide others with smooth transition"""
	# First, fade out all portraits
	var fade_out_tween = create_tween()
	fade_out_tween.parallel().tween_property(leni_portrait, "modulate:a", 0.0, portrait_fade_duration * 0.5)
	fade_out_tween.parallel().tween_property(bato_portrait, "modulate:a", 0.0, portrait_fade_duration * 0.5)
	
	# Wait for fade out to complete
	await fade_out_tween.finished
	
	# Hide all portraits
	hide_all_portraits()
	
	# Show and fade in the appropriate portrait
	match speaker_name.to_lower():
		"leni":
			leni_portrait.visible = true
			var fade_in_tween = create_tween()
			fade_in_tween.tween_property(leni_portrait, "modulate:a", 1.0, portrait_fade_duration)
			print("Showing Leni portrait with fade")
		"bato":
			bato_portrait.visible = true
			var fade_in_tween = create_tween()
			fade_in_tween.tween_property(bato_portrait, "modulate:a", 1.0, portrait_fade_duration)
			print("Showing Bato portrait with fade")
		_:
			print("Unknown speaker: " + speaker_name + " - no portrait shown")

func set_dialogue(lines):
	dialogue_lines = lines
	current_line = 0
	start_dialogue()

func start_dialogue():
	if dialogue_lines.size() == 0:
		end_dialogue()
		return
	
	dialogue_running = true
	
	# Show vignette first
	show_vignette()
	
	# Wait for vignette to start appearing, then show dialogue box
	await get_tree().create_timer(entrance_delay).timeout
	
	# Fade in dialogue box smoothly
	dialogue_box.visible = true
	var dialogue_tween = create_tween()
	dialogue_tween.tween_property(dialogue_box, "modulate:a", 1.0, dialogue_fade_duration)
	
	# Wait for dialogue box to fade in before starting text
	await dialogue_tween.finished
	
	display_line()

func display_line():
	if current_line >= dialogue_lines.size():
		end_dialogue()
		return
	
	var line = dialogue_lines[current_line]
	speaker_label.text = line["speaker"]
	dialogue_text.text = ""
	
	# Show the appropriate portrait for the current speaker
	show_speaker_portrait(line["speaker"])
	
	# Hide continue indicator while typing
	continue_indicator.visible = false
	
	# Type out text
	text_displayed = false
	typing_in_progress = true
	var full_text = line["text"]
	
	for i in range(full_text.length()):
		# Check if typing was interrupted (line skipped)
		if not typing_in_progress:
			return
			
		dialogue_text.text = full_text.substr(0, i + 1)
		if has_node("TypeSound"):
			$TypeSound.play() # Optional: play typing sound
		await get_tree().create_timer(text_speed).timeout
	
	# Only set these if typing completed normally (wasn't interrupted)
	if typing_in_progress:
		text_displayed = true
		typing_in_progress = false
		continue_indicator.visible = true

func next_line():
	if typing_in_progress:
		# If text is still typing out, stop the typing and display it all immediately
		typing_in_progress = false  # This stops the typing loop
		dialogue_text.text = dialogue_lines[current_line]["text"]
		text_displayed = true
		continue_indicator.visible = true
		return
	
	current_line += 1
	if current_line < dialogue_lines.size():
		display_line()
	else:
		end_dialogue()

func end_dialogue():
	dialogue_running = false
	typing_in_progress = false  # Make sure to stop any ongoing typing
	
	# Smooth fade out sequence
	var exit_tween = create_tween()
	
	# Fade out dialogue box and portraits simultaneously
	exit_tween.parallel().tween_property(dialogue_box, "modulate:a", 0.0, dialogue_fade_duration)
	exit_tween.parallel().tween_property(leni_portrait, "modulate:a", 0.0, portrait_fade_duration)
	exit_tween.parallel().tween_property(bato_portrait, "modulate:a", 0.0, portrait_fade_duration)
	
	# Hide vignette
	hide_vignette()
	
	# Wait for everything to fade out
	await exit_tween.finished
	
	# Hide dialogue box after fade
	dialogue_box.visible = false
	hide_all_portraits()
	
	emit_signal("dialogue_completed")
	
	# Wait a bit more for vignette to fully fade
	await get_tree().create_timer(vignette_fade_duration * 0.5).timeout
	
	# Clean up vignette layer
	if vignette_layer and is_instance_valid(vignette_layer):
		vignette_layer.queue_free()
	
	queue_free()  # Remove dialogue instance when done

func _input(event):
	if !dialogue_running:
		return
		
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_SPACE or event.keycode == KEY_ENTER or event.keycode == KEY_E:
			next_line()
