@tool
class_name LLMInterface
# The intention of this class is to serve as a base class for any LLM API
# to be implemented in this plugin. It is mainly to have a clear definition
# of what properties or functions should be used by other classes.

const INVALID_RESPONSE := "[INVALID_RESPONSE]"

var model: String
var override_temperature: bool
var temperature: float


func get_full_response(body: PackedByteArray) -> Dictionary:
	var json := JSON.new()
	var parse_result := json.parse(body.get_string_from_utf8())
	if parse_result != OK:
		push_error("Failed to parse JSON in get_full_response: %s" % json.get_error_message())
		return {}
	var data = json.get_data()
	if typeof(data) == TYPE_DICTIONARY:
		return data
	else:
		push_error("Parsed JSON is not a Dictionary in get_full_response.")
		return {}


## All methods below should be overriden by child classes, see for example OllamaAPI

func send_get_models_request(http_request:HTTPRequest) -> bool:
	return false


func read_models_response(body:PackedByteArray) -> Array[String]:
	return [INVALID_RESPONSE]


func send_chat_request(http_request:HTTPRequest, content:Array) -> bool:
	return false


func read_response(body:PackedByteArray) -> String:
	return INVALID_RESPONSE
