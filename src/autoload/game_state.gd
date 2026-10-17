extends Node

signal room_changed(room_id: String)
signal visited_changed

var current_room_id := ""
var visited := {}
## Imprint upgrades. v1 reads these but does not place platforms yet.
var abilities := {
	"imprint_width": 2,
	"imprint_duration": 4.0,
	"imprint_max_active": 1,
	"imprint_effects": [],
}


func visit(room_id: String) -> void:
	current_room_id = room_id
	var is_new := not visited.has(room_id)
	visited[room_id] = true
	room_changed.emit(room_id)
	if is_new:
		visited_changed.emit()
