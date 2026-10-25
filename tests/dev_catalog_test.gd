extends SceneTree

## The extension contract, exact edits, and separate named-loadout persistence.

const TEMP := "user://dev_catalog_test.json"
var _ok := true


func _initialize() -> void:
	_check(DevCatalog.problems().is_empty(), "all current upgrades have dev controls")
	var definitions := Upgrades.all().duplicate(true)
	definitions["forgotten"] = {"name": "Future power", "stat": "imprint_width", "kind": "max"}
	_check(not DevCatalog.problems(definitions).is_empty(), "a new upgrade without dev metadata fails coverage")
	definitions["forgotten"]["dev"] = {"type": "int", "min": 1, "step": 1}
	_check(DevCatalog.problems(definitions).is_empty() and DevCatalog.controls(definitions)["imprint_width"]["type"] == "int", "registered upgrades generate controls without a new widget")
	var stats: Array = Abilities.STATS.duplicate()
	stats.append("future_stat")
	_check(not DevCatalog.problems({}, stats).is_empty(), "an unregistered ability stat fails coverage")
	var state: Node = root.get_node("GameState")
	_check(DevCatalog.RESOURCES["tokens"]["max"] == state.TOKEN_CAP, "dev token bounds match the gameplay cap")
	var ability := Abilities.new()
	for property in ability.get_property_list():
		if property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			var key: String = property["name"]
			_check(Abilities.STATS.has(key) and ability.to_dict().has(key), "ability property %s is registered and serialized" % key)
			var changed := Abilities.new()
			var value: Variant = changed.get(key)
			if value is bool:
				value = not value
			elif value is int or value is float:
				value += 1
			elif value is Array:
				value.append("serialization_fixture")
			changed.set(key, value)
			_check(Abilities.from_dict(changed.to_dict()).get(key) == value, "ability %s round-trips a nondefault value" % key)
	var sample := DevCatalog.defaults()
	sample["abilities"]["imprint_width"] = 5
	_check(DevCatalog.validate(sample).is_empty() and Abilities.from_dict(sample["abilities"]).imprint_width == 5, "registered values serialize and deserialize")
	for invalid in [-1, 0, 1.5, INF, NAN, "5", true]:
		sample["abilities"]["imprint_width"] = invalid
		_check(not DevCatalog.validate(sample).is_empty(), "reject invalid width %s" % str(invalid))
	sample = DevCatalog.defaults()
	sample["tokens"] = 4
	_check(not DevCatalog.validate(sample).is_empty(), "tokens cannot exceed the real cap")
	sample = DevCatalog.defaults()
	sample["abilities"]["imprint_effects"] = ["bounce"]
	_check(not DevCatalog.validate(sample).is_empty(), "stored effect names cannot pretend bounce is implemented")
	var restored := DevCatalog.reconcile({"abilities": {"old_power": 1, "imprint_effects": ["bounce"], "imprint_width": 5}})
	_check(restored["error"].is_empty() and restored["warnings"].size() == 2 and restored["loadout"]["abilities"]["imprint_duration"] == 2.5, "old loadouts get defaults and visible removed-feature warnings")
	var progression := {"flags": ["pickup:keep"], "machines": {"m": 2}}
	var merged := DevCatalog.with_loadout(progression, restored["loadout"])
	merged["machines"]["m"] = 3
	_check(progression["machines"]["m"] == 2 and merged["flags"] == ["pickup:keep"], "snapshot overlays deep-copy progression")
	_store()
	for path in [TEMP, TEMP + ".tmp"]:
		DirAccess.remove_absolute(path)
	print("DEV CATALOG %s" % ("pass" if _ok else "fail"))
	quit(0 if _ok else 1)


func _store() -> void:
	DirAccess.remove_absolute(TEMP)
	var store := DevLoadouts.new()
	store.path = TEMP
	store.read()
	var powers := DevCatalog.defaults()
	powers["health"] = 3
	_check(store.put("Basic", powers).is_empty(), "save a named loadout")
	powers["health"] = 9
	_check(store.entries["Basic"]["health"] == 3, "saved values share no mutable state")
	_check(not store.put("Basic", powers).is_empty(), "creating a duplicate name fails")
	_check(store.put("Basic", powers, true).is_empty(), "explicit update replaces a loadout")
	var again := DevLoadouts.new()
	again.path = TEMP
	again.read()
	_check(again.error.is_empty() and again.entries["Basic"]["health"] == 9, "loadouts survive reload")
	_check(again.rename("Basic", "Wide").is_empty() and again.entries.has("Wide") and not again.entries.has("Basic"), "rename persists")
	_check(again.remove("Wide").is_empty() and again.entries.is_empty(), "delete persists")
	for data in ["{bad", '{"version":99,"loadouts":{}}']:
		var file := FileAccess.open(TEMP, FileAccess.WRITE)
		file.store_string(data)
		file.close()
		again.read()
		_check(not again.error.is_empty() and not again.put("New", powers).is_empty() and FileAccess.get_file_as_string(TEMP) == data, "damaged or newer store is not overwritten")
	var unwritable := DevLoadouts.new()
	unwritable.path = "user://missing_dev_test_directory/loadouts.json"
	_check(not unwritable.put("Fail", powers).is_empty() and unwritable.entries.is_empty(), "write failure keeps in-memory entries unchanged")


func _check(condition: bool, label: String) -> void:
	print(("ok   " if condition else "FAIL ") + label)
	_ok = condition and _ok
