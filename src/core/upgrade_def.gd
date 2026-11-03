class_name UpgradeDef
extends RefCounted

## One upgrade from data/upgrades.json: which stat it changes and how.
## `title` is the name shown to the player.

var id := ""
var title := ""
var stat := ""
var kind := ""
var message := ""
var has_message := false
var controls: Array = []
var has_controls := false


static func from_raw(upgrade_id: String, raw: Dictionary) -> UpgradeDef:
	var out := UpgradeDef.new()
	out.id = upgrade_id
	out.title = String(raw.get("name", upgrade_id))
	out.stat = String(raw.get("stat", ""))
	out.kind = String(raw.get("kind", ""))
	out.has_message = raw.has("message")
	out.message = String(raw.get("message", ""))
	out.has_controls = raw.has("controls")
	if raw.get("controls") is Array:
		out.controls = (raw["controls"] as Array).duplicate()
	return out
