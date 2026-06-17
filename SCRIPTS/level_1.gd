extends Node

var screen_size : Vector2i
var game_running : bool = false
@onready var ground = $LEVEL1_MAP_GROUND
var ground_segments = []  # Array to track all ground instances
var segment_count = 3  # Number of ground segments to use
var ground_width = 0  # Will be set based on ground's collision shape width

func _ready() -> void:
	screen_size = get_window().size
	game_running = true
	
	# Get the width of your ground segment
	var shape = ground.get_node("CollisionShape2D").shape
	ground_width = shape.size.x
	
	# Initialize with the original ground
	ground_segments.append(ground)
	
	# Create additional ground segments
	for i in range(1, segment_count):
		var new_ground = ground.duplicate()
		new_ground.position.x = ground.position.x + (ground_width * i)
		add_child(new_ground)
		ground_segments.append(new_ground)

func update_ground():
	# Use the camera's GLOBAL position to track movement correctly
	var camera_x = $LENI_SHORTSWORD/Camera2D.global_position.x
	var total_width = ground_width * segment_count
	
	# Reposition ground segments as needed
	for segment in ground_segments:
		# Calculate the distance from the segment to the camera
		var distance_to_camera = camera_x - segment.position.x
		
		# If the segment is too far behind the camera, move it ahead
		if distance_to_camera > ground_width * 1.5:  # Adjusted threshold for earlier repositioning
			segment.position.x += total_width
		
		# If the segment is too far ahead of the camera, move it behind
		elif -distance_to_camera > ground_width * 1.5:
			segment.position.x -= total_width

func _process(delta: float) -> void:
	if game_running:
		update_ground()
