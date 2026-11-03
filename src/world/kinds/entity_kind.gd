class_name EntityKind
extends RefCounted

## One kind of thing a room legend can place. Adding a kind is a subclass and a
## line in Entities.KINDS: its schema, the flag it leaves, whether it is still
## in the room, the node it builds, the rect a body touches, and what the
## solver does when the player reaches it.


func type() -> String:
	return ""


func required() -> Array[String]:
	return []


func optional() -> Array[String]:
	return []


## Drawn across more than one cell (a platform, a spinner, a breakable wall).
func structural() -> bool:
	return false


func touchable() -> bool:
	return false


func collectible() -> bool:
	return false


func allowed_in_save_room() -> bool:
	return false


func flag_for(_def: EntityDef) -> String:
	return ""


func present(def: EntityDef, flags: Dictionary) -> bool:
	var key := flag_for(def)
	return key.is_empty() or not flags.has(key)


func create(_def: EntityDef, _fills: Dictionary) -> Node2D:
	return null


func touch_rect(def: EntityDef) -> Rect2:
	var centre := Grid.cell_center(def.cell)
	return Rect2(centre - Vector2(Pickup.HALF, Pickup.HALF), Vector2(Pickup.HALF, Pickup.HALF) * 2.0)


## What reaching this thing gives. Tokens and machines are counted; settle pays.
func solver_effect(_def: EntityDef, _ledger: Dictionary) -> void:
	pass


func problems(_def: EntityDef) -> Array[String]:
	return []
