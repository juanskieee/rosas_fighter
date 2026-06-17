extends CanvasLayer

# Variable to track current coin count
var coin_count: int = 0

# Reference to the Label to display the count
@onready var coin_label: Label = $Label

func _ready() -> void:
	# Initialize the label with starting value
	update_display()
	
	# Connect to existing coins in the scene
	connect_to_existing_coins()
	
	# Connect to the tree to automatically handle coins added during gameplay
	get_tree().node_added.connect(_on_node_added)

func connect_to_existing_coins() -> void:
	# Find all coins in the scene tree and connect to their signals
	var coins = get_tree().get_nodes_in_group("COINS")
	for coin in coins:
		if coin.has_signal("coin_collected") and not coin.is_connected("coin_collected", increment_coins):
			coin.coin_collected.connect(increment_coins)
			print("Connected existing coin: ", coin.name, " to coin counter")

func _on_node_added(node: Node) -> void:
	# When a new node is added to the scene tree
	if node.is_in_group("COINS"):
		# Wait one frame to ensure the node is properly set up
		await get_tree().process_frame
		
		# Connect the new coin to the coin counter
		if node.has_signal("coin_collected") and not node.is_connected("coin_collected", increment_coins):
			node.coin_collected.connect(increment_coins)
			print("Connected new coin: ", node.name, " to coin counter")

# Called when a coin is collected
func increment_coins(value: int = 1) -> void:
	coin_count += value
	update_display()
	print("Coins collected: ", coin_count)

# Updates the label text
func update_display() -> void:
	if coin_label:
		coin_label.text = str(coin_count)
	else:
		push_warning("Coin label not found in COIN_COUNTER")

# Public method to get current coin count
func get_coin_count() -> int:
	return coin_count
