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
