class_name TokenKind
extends EntityKind


func type() -> String:
	return "token"


func touchable() -> bool:
	return true


func collectible() -> bool:
	return true


func allowed_in_save_room() -> bool:
	return true


func flag_for(def: EntityDef) -> String:
	return Token.flag_for(def)


func create(def: EntityDef, _fills: Dictionary) -> Node2D:
	return Token.new(def)


func solver_effect(_def: EntityDef, ledger: Dictionary) -> void:
	ledger["tokens"] = int(ledger["tokens"]) + 1


## A raised thing is collected where it is drawn, half a cell above its cell.
func touch_rect(def: EntityDef) -> Rect2:
	var area := super.touch_rect(def)
	return Rect2(area.position - Vector2(0.0, Token.RAISE), area.size)
