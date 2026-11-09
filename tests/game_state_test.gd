extends TestCase

## GameState's progression rules on their own, with no world: visiting rooms,
## grants and their lines, the token cap, health pips, spending and refilling
## hearts, dev loadouts, and the snapshot being a copy. Each change is checked
## with the signals it sends, since the HUD, map and power popup act on them.

var _state: Node
var _counts := {}
var _granted: Array[String] = []
var _rooms: Array[String] = []


func _initialize() -> void:
	_state = root.get_node("GameState")
	_state.reset()
	for name in ["visited_changed", "abilities_changed", "tokens_changed", "health_changed"]:
		_counts[name] = 0
		_state.connect(name, func() -> void: _counts[name] += 1)
	_state.room_changed.connect(func(id: String) -> void: _rooms.append(id))
	_state.upgrade_granted.connect(func(id: String) -> void: _granted.append(id))

	_visits()
	_grants()
	_tokens()
	_health()
	_loadout()
	_snapshot()
	_state.reset()
	finish("GAME STATE")


func _visits() -> void:
	_zero()
	_state.visit("2")
	_state.visit("2")
	_state.visit("3")
	check(_rooms == ["2", "2", "3"] and _state.current_room_id == "3", "every visit says the room (%s)" % [_rooms])
	check(_counts["visited_changed"] == 2 and _state.visited.keys() == ["2", "3"], "only a room not seen before changes the visited set (%d)" % _counts["visited_changed"])


func _grants() -> void:
	_zero()
	var pickup := _def("pickup", "p1", {"upgrade": "double_jump", "value": "1"})
	var line: String = _state.collect(pickup)
	check(_state.has_flag("pickup:p1") and _state.abilities.air_jumps == 1, "collecting a pickup remembers it and applies its upgrade")
	check(line == Upgrades.get_def("double_jump").message, "and returns the upgrade's message (%s)" % line)
	check(_counts["abilities_changed"] == 1 and _granted == ["double_jump"], "it changes the abilities once and names the upgrade granted")

	_zero()
	_state.grant("double_jump", "1")
	check(_counts["abilities_changed"] == 0 and _state.abilities.air_jumps == 1, "granting what is already held changes no ability")

	_zero()
	line = _state.grant("tongue_cooldown", "0.03")
	check(is_equal_approx(_state.abilities.tongue_cooldown, 0.03) and _counts["abilities_changed"] == 1, "a min upgrade with a value written as text lowers the stat")
	check(line == "Lash Cooldown +1", "an upgrade with no message says its name +1 (%s)" % line)
	_state.grant("tongue_cooldown", "0.5")
	check(is_equal_approx(_state.abilities.tongue_cooldown, 0.03), "a worse one later takes nothing away")


func _tokens() -> void:
	_state.reset()
	_zero()
	for i in GameState.TOKEN_CAP:
		check(_state.take_token(_def("token", "t%d" % i)), "token %d is taken" % i)
	check(_state.tokens == GameState.TOKEN_CAP and _state.tokens_full() and _counts["tokens_changed"] == GameState.TOKEN_CAP, "a full pocket holds the cap, one signal each")
	check(not _state.take_token(_def("token", "extra")), "a token past the cap is refused")
	check(not _state.has_flag("token:extra") and _state.tokens == GameState.TOKEN_CAP and _counts["tokens_changed"] == GameState.TOKEN_CAP, "and it is left in the room: no flag, no count, no signal")
	for i in GameState.TOKEN_CAP + 2:
		_state.spend_token()
	check(_state.tokens == 0 and not _state.tokens_full(), "spending past empty stops at zero")
	check(_state.has_flag("token:t0"), "a spent token stays taken")


func _health() -> void:
	_state.reset()
	_zero()
	check(_state.health == GameState.BASE_HEALTH and _state.max_health == GameState.BASE_HEALTH, "a new game has the base heart")
	_state.take_health(_def("health", "h1"))
	check(_state.has_flag("health:h1") and _state.health == GameState.BASE_HEALTH + 1 and _state.max_health == GameState.BASE_HEALTH + 1 and _counts["health_changed"] == 1, "a pip adds a full heart to the frame")
	_state.machine_prize(_def("machine", "m1", {"prize": "health"}))
	check(_state.health == GameState.BASE_HEALTH + 2 and _state.max_health == GameState.BASE_HEALTH + 2 and _state.flags.size() == 1, "a health 3TM adds one too, with no pickup flag")

	_zero()
	for i in 5:
		_state.spend_health()
	check(_state.health == 0 and _state.max_health == GameState.BASE_HEALTH + 2 and _counts["health_changed"] == 5, "deaths empty hearts to zero and the frame keeps its length")
	_zero()
	_state.refill_health()
	check(_state.health == GameState.BASE_HEALTH + 2 and _counts["health_changed"] == 1, "a save room fills every heart")
	_state.refill_health()
	check(_counts["health_changed"] == 1, "refilling full hearts sends nothing")


func _loadout() -> void:
	_state.reset()
	_zero()
	var abilities := Abilities.new()
	abilities.tongue_unlocked = true
	_state.set_loadout({"abilities": abilities.to_dict(), "tokens": 2, "health": 4, "max_health": 2})
	check(_state.abilities.tongue_unlocked and _state.tokens == 2 and _state.health == 4, "a loadout sets powers, tokens and health exactly")
	check(_state.max_health == 4, "the frame is never shorter than the hearts held (%d)" % _state.max_health)
	check(_counts["abilities_changed"] == 1 and _counts["tokens_changed"] == 1 and _counts["health_changed"] == 1, "and it tells the HUD and the player once each")
	_state.set_loadout({"abilities": {}, "tokens": 0, "health": 0})
	check(_state.health == 0 and _state.max_health == GameState.BASE_HEALTH and not _state.abilities.tongue_unlocked, "a loadout with no hearts keeps the base frame and drops unlisted powers")


func _snapshot() -> void:
	_state.reset()
	_state.visit("2")
	_state.set_flag("token:t1")
	_state.set_machine_fill("m1", 2)
	var held: Progression = _state.snapshot()
	_state.visit("3")
	_state.set_flag("pickup:p1")
	_state.set_machine_fill("m1", 3)
	_state.grant("double_jump", "1")
	check(held.visited.keys() == ["2"] and held.flags.keys() == ["token:t1"] and held.machines["m1"] == 2 and held.abilities.air_jumps == 0, "a snapshot is a copy that later play does not change")
	_zero()
	_state.restore(held)
	check(not _state.visited.has("3") and not _state.has_flag("pickup:p1") and _state.machines["m1"] == 2 and _state.abilities.air_jumps == 0, "restoring it puts the progression back")
	check(_counts["visited_changed"] == 1 and _counts["abilities_changed"] == 1 and _counts["tokens_changed"] == 1 and _counts["health_changed"] == 1, "and refreshes everything that shows it")
	_state.set_flag("save:s1")
	check(not held.flags.has("save:s1"), "the restored state does not share the snapshot's lists")
	_state.reset()
	check(_state.visited.is_empty() and _state.flags.is_empty() and _state.machines.is_empty() and _state.tokens == 0 and _state.abilities.to_dict() == Abilities.new().to_dict(), "reset is a new game")


func _zero() -> void:
	for name in _counts:
		_counts[name] = 0
	_granted.clear()
	_rooms.clear()


func _def(type: String, id: String, props := {}) -> EntityDef:
	var out := EntityDef.new()
	out.type = type
	out.id = id
	out.props = props
	return out
