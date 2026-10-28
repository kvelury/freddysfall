# Handoff: in-game menus, pause, controls, power popups, title cards

_Updated 2026-10-27. Written as a build spec: implement exactly as written, and ask before deviating._

> **Status: built, not yet played by a person.** Built to this spec on branch `in-game-menus`. `tools/check.sh` (26 tests) and `tools/pixel_check.sh` pass. Deviations: the theme variation is `MenuItem` (`MenuButton` is a built-in Godot class); a room or dev test session shows a title card once per world and sets no `title:` flag (the dev tests assert empty flags); `Upgrades` also validates `controls` ids; the pixel check hides the new layers. The previous handoff (render at 640×360, PR #51) was built and merged.

## Goal

In the user's words:
- There should be a main menu when you start the game, with the title Freddy's Fall, and Start Game, selectable by mouse or arrow keys.
- A Controls section shows the game's controls on its own page, with a Back button to the main menu.
- Starting the game then works as it does now.
- Esc opens a pause menu: Resume, Controls (the same content), Back to main menu.
- A popup shows the controls each time the player gets a new power, and the player can dismiss it. It should be "a simple diagram of the button and what it does".
- A way to show title overlays, for the game's title card and later for significant new areas. The first one shows as soon as the player enters the room 7 shaft: "Freddy's Fall". It disappears when they hit the ground. That can be a countdown timed to match the landing.
- Share the dev menu's approach where it makes sense.

## Branch

Cut `in-game-menus` from the latest `origin/main` (`git fetch origin && git switch -c in-game-menus origin/main`). Ship it as one pull request.

`main` was at `4394132` (PR #52, GitHub Pages deploy) when this was written, with a clean tree. Every merge to `main` now redeploys https://kvelury.github.io/freddysfall/, so the menus go live when this PR merges.

## Decisions the user made (do not re-litigate)

| Question | Decision |
| --- | --- |
| Main menu items | With a save: **Continue**, **New Game**, **Controls**. With no save: **Start Game**, **Controls**. New Game asks "Erase your saved game and start over?" with **No** (the default) and **Yes**. |
| Title card frequency | **Once per save.** It is remembered in the save. A New Game shows it again. |
| Title card hide | **A fixed countdown** tuned to match a straight fall to the floor. It is not tied to landing. |
| Power popup | **The game pauses until the popup is dismissed.** It shows on every real grant of an upgrade that has controls (a 3TM or a pickup). It never shows for dev panel edits, loadouts, loads or retries. |
| Controls page content | **Only what the player has.** Move, Jump, Map, Map zoom and Pause always show. Double jump, Shoot and Imprint show once owned in the current game. From the main menu, where no game is loaded, only the base rows show. |
| Pause keys | **Esc and P** both open the pause menu and close it. |
| Look | **The dev panel's monochrome style:** black, 1px white borders, white text. The selected menu item is inverted (white box, black text). The title uses big text. Build one shared theme and have the dev panel use it too. |
| Launch arguments | (Agent decision; keep it.) `?room=`, `?dev=1`, `--room=` and `--dev` **skip the main menu** and boot straight into the world as they do today. This keeps `tools/snap.sh`, every test, and dev playtesting unchanged. `?new-game=1` erases the save and then **shows the menu**, which now offers "Start Game". |

## Facts measured from the code (2026-10-27, main at 4394132)

- **Boot:** the main scene is `res://src/world/world.tscn`. `World._ready` (`src/world/world.gd:54-98`) does all the booting: it reads launch arguments with `_launch_arg` (`world.gd:140-150`), calls `DevSession.configure`, handles `new_game`, `Save.load_game()` and `_place_in`.
- **Modal system to reuse:**
  - `World.acquire_modal(owner)` and `release_modal(owner)` (`world.gd:481-497`) pause the tree, with one owner at a time.
  - `gameplay_input_blocked()` (`world.gd:502`) holds gameplay input until the play keys are released.
  - Today's owners are `"map"` and `"dev"`.
  - The dev panel waits while `world.is_busy()` (door slides, deaths, save or 3TM animations) by queuing its open in `_process` (`src/ui/dev_panel.gd:52-55`). **Copy that pattern.** `_feed` uses `create_timer(..., true, true)`, which keeps running while paused, so pausing in the middle of an animation is unsafe.
- **UI layers:** each is a CanvasLayer with `scale = Vector2.ONE * Display.RENDER_SCALE` and `process_mode = PROCESS_MODE_ALWAYS`, laid out in 320×180 units (see `src/ui/toast.gd`). Current layers: MapOverlay 10, Toast 15, DebugOverlay 20, DevPanel 30. The font is the default `ThemeDB.fallback_font`; there are no font files.
- **The dev theme** is `DevPanel._theme()` (`src/ui/dev_panel.gd:169-198`). `_button` is at `dev_panel.gd:503`. The panel forces `Input.mouse_mode = MOUSE_MODE_VISIBLE` while open (`dev_panel.gd:57,102`), because Imprint hides the cursor (`src/imprint/imprint_tool.gd:248`). Today Esc is read only by the dev panel's `_input`, and only while it is open.
- **Input map** (`project.godot`):

  | Action | Keys |
  | --- | --- |
  | `move_left` | A, Left |
  | `move_right` | D, Right |
  | `move_down` | S, Down (not read by gameplay) |
  | `jump` | W, Up (holding it gives a higher jump) |
  | `shoot` | Space |
  | `map` | Tab, M (held) |
  | `map_zoom_in` | Up, W |
  | `map_zoom_out` | Down, S |
  | `imprint` | left mouse |
  | `debug` | F3 |

  There is no `pause` action yet.
- **Granting powers:**
  - `GameState.grant(id, text)` (`src/autoload/game_state.gd:56-63`) is called only by `collect()` (pickups) and `machine_prize()` (3TMs). Dev edits use `set_loadout`, and loads use `load_dict`. Both of those emit `abilities_changed`, so **do not** hook popups to `abilities_changed`.
  - World shows the returned line with `toast.show_text(...)` at `world.gd:221` (pickup) and `world.gd:327` (3TM, still `_busy`). `_busy = false` at `world.gd:330`.
  - In play today, double jump comes from `data/rooms/4.txt` (`r4_3tm`) and the gun from `data/rooms/9.txt` (`r9_3tm`). Imprint is never granted in play, only through dev tools, but it gets popup data anyway.
- **Room 7** (`data/rooms/7.txt`, `grid_pos` [0,2]) is 32×72 cells.
  - The shaft is columns 1-13. The top door is columns 5-12, entered from room 6's floor door, also columns 5-12.
  - The floor is row 71 (y=710). A ledge at columns 9-13, row 67, is 40 px higher.
  - `Door.crossing` puts the player about 20 px below the top edge, with the velocity they carried.
  - `_on_exit` (`world.gd:429`) calls `GameState.visit(dest)` at the start of the 0.5 s slide (`TRANSITION_TIME`), while the player is frozen. `_finish_transition` (`world.gd:458`) autosaves.
- **Fall physics** (`src/player/movement.tres`): gravity 740, fall scale 1.8 (1332 px/s²), apex scale 0.5 under 40 px/s, max fall 300 px/s, 60 ticks/s.
  - Estimate, not measured: from slide start to landing on the floor is about 0.5 + 2.3 to 2.5 s, so **about 2.8-3.0 s**. The build must measure it (see test 2).
- **Save:** the save is `user://save.json` and stores `GameState.to_dict()`. `flags` is an open set of strings that is saved as-is. The existing prefixes are `pickup:`, `token:`, `save:` and `health:`. A new `title:<room id>` prefix needs no save version change. `Save.enabled` is false in headless runs, and every write and read is skipped while `DevSession.isolated()`.
- **Tests** instantiate `world.tscn` directly with `start_override` (pattern: `tests/start_test.gd`). `tools/check.sh` lists 24 tests by hand.

## What to build

### 1. Shared pieces (new files; run `godot --headless --path . --import` after adding `class_name`s)

**`src/core/launch_args.gd`**, `class_name LaunchArgs`, static.
- Move `World._launch_arg` here, unchanged, as `static func value(name: String) -> String`.
- `world.gd` calls `LaunchArgs.value(...)`. Delete `_launch_arg` from `world.gd`.

**`src/core/scenes.gd`**, `class_name Scenes`, static.
- `static func swap(old: Node, next: Node) -> void`: remember `old.get_tree()`, `old.get_parent()` and whether `old` is `current_scene`. Then `old.free()`, set `tree.paused = false`, `parent.add_child(next)`, and set `current_scene = next` if `old` was.
- Callers use `call_deferred`, because they run from inside `old`'s own button handlers.
- This mirrors `DevSession._replace` (`src/dev/dev_session.gd:189-212`). **Do not** refactor `_replace` to use it.

**`src/ui/ui_theme.gd`**, `class_name UiTheme`.
- Move the body of `DevPanel._theme()` here **unchanged** as `static func build() -> Theme`. `DevPanel` calls `UiTheme.build()`. The dev panel must look identical.
- Add a type variation `"MenuButton"` (base `Button`):
  - `normal`: a black box with a 1px white border, margins as in the dev box.
  - `focus` and `hover`: white fill, white border, `font_focus_color` and `font_hover_color` black.
  - This is the inverted selection.
- Add `static func title_label(text: String, size := 24) -> Label`:
  - white text with a black outline (`outline_size` 4)
  - centred
  - `custom_minimum_size.x = 320`
  - used by the main menu and the title card

**`src/ui/menu_list.gd`**, `class_name MenuList extends VBoxContainer`.
- `func add_item(text: String, on_pick: Callable) -> Button` adds a Button with `theme_type_variation = "MenuButton"`, `custom_minimum_size.x = 96` and centred text. `mouse_entered` calls `grab_focus`, and `pressed` calls `on_pick`.
- `func focus_first()` focuses item 0. `func focus_item(i)` focuses item `i`.
- Arrow keys and Enter/Space come from Godot's built-in `ui_up`, `ui_down` and `ui_accept` on focused Buttons.
- MenuList also maps `jump` (W) to previous and `move_down` (S) to next. It reads them in `_unhandled_input`, only while `is_visible_in_tree()`, and marks the event handled.
- The list wraps around: set the first item's `focus_neighbor_top` to the last and the last's `focus_neighbor_bottom` to the first.

**`data/controls.json`** and **`src/core/controls.gd`** (`class_name Controls`, static, loaded once like `Upgrades`). One list feeds both the Controls page and the popups:
```json
[
  {"id": "move", "label": "Move", "actions": ["move_left", "move_right"]},
  {"id": "jump", "label": "Jump (hold to go higher)", "actions": ["jump"]},
  {"id": "double_jump", "label": "Jump again in the air", "actions": ["jump"], "needs": "air_jumps"},
  {"id": "shoot", "label": "Shoot the way you face", "actions": ["shoot"], "needs": "gun_unlocked"},
  {"id": "imprint", "label": "Place a platform at the cursor", "actions": ["imprint"], "needs": "imprint_unlocked"},
  {"id": "map", "label": "Map (hold)", "actions": ["map"]},
  {"id": "map_zoom", "label": "Zoom the map (while held)", "actions": ["map_zoom_in", "map_zoom_out"]},
  {"id": "pause", "label": "Pause", "actions": ["pause"]}
]
```
Functions:
- `rows() -> Array`
- `get_row(id) -> Dictionary`
- `problems() -> Array[String]`: unknown action, a `needs` that is not in `Abilities.STATS`, or a duplicate id
- `owned(row, abilities: Abilities) -> bool`: true when there is no `needs`, when `abilities` is non-null and the stat is truthy (int > 0 or bool true), and false when `abilities` is null and there is a `needs`
- `visible_rows(abilities: Abilities) -> Array` (`abilities` may be null)
- `key_groups(row) -> Array`: binding index 0 of every action, then binding index 1 of every action, so `move` → `[["A","D"],["Left","Right"]]`. Labels come from the InputMap:
  - `InputEventKey` → `OS.get_keycode_string(event.physical_keycode)`, then map `"Escape"` → `"Esc"`.
  - `InputEventMouseButton` with button 1 → `"MouseLeft"`.
  - Drop a group if it is empty.

**`src/ui/key_cap.gd`**, `class_name KeyCap extends Control`. It draws one key in UI units.
- Height 11, width `max(11, text width + 6)`.
- A black box with a 1px white border and the label in white at font size 8, centred.
- `"Left"`, `"Right"`, `"Up"` and `"Down"` draw a pixel arrow instead of text, with `PixelArt.rects()` (`src/core/pixel_art.gd:13`). Up arrow (rotate it for the others):
  ```
  ..#..
  .###.
  #####
  ```
- `"MouseLeft"` draws a 7×9 mouse with the left button filled, in a box 11 wide:
  ```
  .#####.
  ####..#
  ####..#
  ####..#
  #######
  #.....#
  #.....#
  #.....#
  .#####.
  ```
- **Do not** add these to `PixelShapes`. That file is the polygon baseline `pixel_check --shapes` works from. Keep them as consts in `key_cap.gd`.

**`src/ui/controls_view.gd`**, `class_name ControlsView extends VBoxContainer`.
- `func show_rows(rows: Array)` builds one HBox per row:
  - the key groups as KeyCaps, with a `/` Label between groups, in a 120-wide column that is right-aligned
  - an 8px gap
  - the row's `label` at font size 8
- The Controls page and the popup both use it.

### 2. Input

In `project.godot`, add a `pause` action bound to **Escape** and **P** (physical keycodes, the same shape as the other entries). Do not add `pause` to the held-keys list at `world.gd:506`.

### 3. Main menu: new main scene

**`src/ui/main_menu.tscn`** has a root `CanvasLayer` named `MainMenu` with the script `src/ui/main_menu.gd` (`class_name MainMenu`). Build everything in code, as the dev panel does.
- Set `layer = 0`, `scale = Vector2.ONE * Display.RENDER_SCALE` and `theme` from `UiTheme.build()` on a root Control.
- Children:
  - a black `ColorRect` sized 320×180
  - `UiTheme.title_label("Freddy's Fall", 24)` at y = 36
  - a `MenuList` centred at y ≈ 92
  - a footer Label at font size 8 and y = 166: `"↑↓ / W S choose · Enter select"`. Check the glyph renders. If the default font has no arrow, write `"Arrows / W S choose · Enter select"`.
- Set `project.godot` `run/main_scene="res://src/ui/main_menu.tscn"`.

**Boot routing** happens in `_ready`, only on the first menu of the process, using `static var _booted := false`:
```gdscript
if not _booted:
	_booted = true
	if not LaunchArgs.value("room").is_empty() or LaunchArgs.value("dev") == "1":
		# Test launches go straight in, exactly as before the menu existed.
		Scenes.swap.call_deferred(self, load(WORLD).instantiate())
		return
	DevSession.configure(false, false)
	if not LaunchArgs.value("new-game").is_empty():
		Save.erase()
		GameState.reset()
```
That world has `from_menu = false`, so World reads the launch arguments itself, as today. `DevSession.configure(false, false)` keeps `DevSession.available` (F2) working in debug builds when the game is started from the menu.

**Pages:**
- **Root.** Without a save (`Save.has_game()` is false) the items are `Start Game` and `Controls`. With a save they are `Continue`, `New Game` and `Controls`. Focus item 0.
- **New Game confirm.** The text "Erase your saved game and start over?" over the items `No` and `Yes`. Focus `No`. Esc or `ui_cancel` means No and returns to Root.
- **Controls.** A "Controls" heading, `ControlsView.show_rows(Controls.visible_rows(null))`, and a `MenuList` with one item, `Back`. Esc goes back too.

**Starting:**
```gdscript
func _start(fresh: bool) -> void:
	if fresh:
		Save.erase()
	GameState.reset()
	var world: Node = load(WORLD).instantiate()
	world.from_menu = true
	world.new_game = fresh
	Scenes.swap.call_deferred(self, world)
```
Continue calls `_start(false)`. New Game → Yes calls `_start(true)`. Start Game calls `_start(false)`: with no save, World starts in `start_room`, as today.

**`Save.has_game()`** is new, in `src/autoload/save.gd`: `return enabled and not DevSession.isolated() and FileAccess.file_exists(path)`. A file that cannot be read still counts. Continue then starts fresh, because `load_game` sets the file aside, as today.

**`World` changes** (`world.gd:54-98`):
- Add `var from_menu := false`, with a doc comment: built by the main menu, reads no launch arguments, and does not reconfigure DevSession.
- `requested`: when `from_menu`, use `start_override` only (empty), never `LaunchArgs.value("room")`.
- Skip `DevSession.configure(...)` when `from_menu`.
- The new-game test becomes `new_game or (not from_menu and not LaunchArgs.value("new-game").is_empty())`.
- Nothing else in the boot changes.

### 4. Pause menu

Add **`src/ui/pause_menu.gd`** (`class_name PauseMenu extends CanvasLayer`). Make it a child node `PauseMenu` in `world.tscn` with layer 25, `process_mode` ALWAYS, the UI scale, and the `UiTheme` theme.
- **Contents:**
  - a full-screen `ColorRect` in `Color(0, 0, 0, 0.6)`
  - a centred `PanelContainer`, about 140 wide, holding the "Paused" Label and a MenuList with `Resume`, `Controls` and `Main menu`
- **Controls page:** a second state inside the same panel. The panel widens to about 280. It holds `ControlsView.show_rows(Controls.visible_rows(GameState.abilities))` and the item `Back`.
- **`_unhandled_input`:** act only on `event.is_action_pressed("pause")` that is not an echo.
  - On the Controls page, go back to the list.
  - If the menu is open, `close()` (resume).
  - If it is closed and `_world.is_busy()`, set `_pending = true`.
  - Otherwise `open()`.
  - Mark the event handled.
  - `ui_cancel` (Esc) on the Controls page also means Back.
- **`open()`:**
  - Return early if `not _world.acquire_modal("pause")`. That means the map or dev panel holds the modal; do nothing and do not queue.
  - Remember `Input.mouse_mode`.
  - Show the menu and call `focus_first()`.
- **`_process`:**
  - If `_pending` and the world is neither busy nor modal, open the menu.
  - While open, force `Input.mouse_mode = MOUSE_MODE_VISIBLE`.
- **`close()`:** hide the menu, restore the remembered mouse mode, call `gui_release_focus()`, then `_world.release_modal("pause")`. The existing `_input_release` stops the Space or click that chose Resume from leaking into shoot or Imprint.
- **Main menu:** call `_world.leave_to_menu()`.

**`World.leave_to_menu()`** is new:
```gdscript
## Back to the main menu. Everything collected was saved when it was taken;
## this writes the resume point once more (skipped in a test session).
func leave_to_menu() -> void:
	save_now()
	DevSession.reset_to_normal()
	GameState.reset()
	Scenes.swap.call_deferred(self, load("res://src/ui/main_menu.tscn").instantiate())
```

**`DevSession.reset_to_normal()`** is new in `src/dev/dev_session.gd`. It sets `mode = Mode.NORMAL`, `bypass = false`, `classic_imprint = false`, `wall_strength_override = 0`, `retry_on_death = false`, `baseline = {}`, `loadout = {}`, `target = ""` and `replacing = false`. It **keeps `available`**, so a `?dev=1` player still has F2 after Continue. Leave `configure` and `_replace` as they are.

### 5. Power popup

Add **`src/ui/power_popup.gd`** (`class_name PowerPopup extends CanvasLayer`). Make it a node `PowerPopup` in `world.tscn` with layer 26, `process_mode` ALWAYS, the UI scale, and the theme.
- **Layout:** a centred PanelContainer, about 220 wide, containing:
  - "NEW POWER" at size 8
  - the upgrade's `name` at size 16
  - a `ControlsView` with the upgrade's control rows
  - "Enter / click to continue" at size 8
- **`open(upgrade_id) -> bool`:** return false unless `_world.acquire_modal("power")`. Then fill the panel, record `_opened_at = Time.get_ticks_msec()`, show it and force the cursor visible (restore it on close).
- **`_input(event)`** runs while open:
  - If less than `MIN_SHOW := 0.4` s have passed, consume the event and return.
  - Otherwise `ui_accept`, `pause`, `jump`, or a left mouse button press (not echo) calls `dismiss()`.
  - Mark the event handled.
- **`dismiss()`:** hide it and `release_modal("power")`. It is public so tests can call it.

**Triggering:**
- In `game_state.gd`, add `signal upgrade_granted(id: String)` and emit it in `grant()` after `abilities.apply`, always, even if the value did not change.
- In `data/upgrades.json`, add `"controls"` lists: `double_jump` gets `["double_jump"]`, `gun` gets `["shoot"]`, `imprint` gets `["imprint"]`. Keep every `"message"`; the toast still uses it if a popup is not shown.
- In `world.gd`:
  ```gdscript
  var _popups: Array[String] = []
  # _ready:
  GameState.upgrade_granted.connect(func(id: String) -> void:
  	if Upgrades.get_def(id).has("controls"):
  		_popups.append(id))
  # top of _physics_process, after the current == null check:
  if not _busy and not _popups.is_empty() and modal_owner.is_empty():
  	power_popup.open(_popups.pop_front())
  ```
- Replace `toast.show_text(GameState.collect(thing.def))` (`:221`) and `toast.show_text(GameState.machine_prize(machine.def))` (`:327`) with `_announce(...)`:
  ```gdscript
  ## A power with controls gets the popup instead of the toast line.
  func _announce(line: String) -> void:
  	if _popups.is_empty():
  		toast.show_text(line)
  ```
- Popups show in room and dev test sessions too, when the grant is a real pickup or 3TM. Dev panel edits never go through `grant()`.
- Do not persist a "seen" flag. A 3TM or pickup gives its upgrade once per save anyway.

### 6. Title cards

**Data:** in `data/world.json`, the room entry gains an optional `title`:
```json
{"id": "7", "grid_pos": [0, 2], "title": {"text": "Freddy's Fall", "hold": 2.1}}
```
`2.1` is a placeholder. Set it from the measurement in test 2.

**`WorldData`** (`src/autoload/world_data.gd`):
- Add `var titles := {}` (room id → `{"text": String, "hold": float}`).
- `_read_entry` parses `title`. Append an error to `errors` (so `tools/validate.sh` fails) when `title` is not a Dictionary, `text` is not a non-empty String, or `hold` is not a number > 0.
- Do **not** touch `RoomParser`, `RoomInfo`, or the room-file format. The solver and its cache never see titles.

Add **`src/ui/title_card.gd`** (`class_name TitleCard extends CanvasLayer`). Make it a node `TitleCard` in `world.tscn` with layer 5, which is under the map, toast, pause and popup. Leave `process_mode` at INHERIT so a pause freezes it.
- It holds one `UiTheme.title_label("", 24)` at y = 36, with `modulate.a = 0` and hidden.
- `const FADE_IN := 0.3` and `const FADE_OUT := 0.5`.
- `func show_title(text: String, hold: float)`: kill any running tween, set the text, show it, then `create_tween()` with `set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)`. Fade `modulate:a` from 0 to 1 over FADE_IN, `tween_interval(hold)`, fade to 0 over FADE_OUT, then hide.
- `func total(hold) -> float` returns `FADE_IN + hold + FADE_OUT`.
- It never blocks input and never takes a modal.

**Trigger** (`world.gd`):
```gdscript
## A room's title card, once per game: the flag is saved with the rest.
func _maybe_title(id: String) -> void:
	var title: Dictionary = WorldData.titles.get(id, {})
	var key := "title:" + id
	if title.is_empty() or GameState.has_flag(key):
		return
	GameState.flags[key] = true
	title_card.show_title(String(title["text"]), float(title["hold"]))
```
- Call it in `_on_exit` right after `GameState.visit(door.dest_id)`. The card appears as the slide starts; `_finish_transition` then autosaves the flag.
- Call it in `_place_in` when `not respawn`, so `?room=7` and `?room=6` sessions can see it.
- Room and dev test sessions reset GameState, so the card shows there every session and is never saved.
- Before using `title:` keys, grep for code that loops over `GameState.flags` and assumes a prefix (`grep -rn "flags" src`). `ExitRules` and `Entities.present` only look up exact keys, so they are fine.

**Timing:** card total = slide start to landing. The countdown starts at `_on_exit` and runs in physics time, so a pause mid-fall keeps it in sync. The reference path is from rest in room 6 at column 7, falling straight to room 7's floor. Entering over columns 9-12 lands on the ledge about 0.13 s sooner, which is accepted. Set `hold = measured − FADE_IN − FADE_OUT`, rounded to 0.05.

### 7. The dev panel

- Its only change is `_theme()` → `UiTheme.build()`.
- **Dev tools rule (AGENTS.md):** these are presentation features, not abilities or progression. State in the design doc's Dev playtesting section that they intentionally have no dev control, and why:
  - The title card replays in every `?room=6` / `?dev=1&room=6` session, because test sessions reset GameState.
  - Power popups appear on real grants in test sessions and never on dev edits.
  - `title:` flags are progression-neutral: `ExitRules` and the solver never read them.

## Tests (two new; `tools/check.sh` goes from 24 to 26)

Add both to `TESTS` in `tools/check.sh` and update its final message. Update the count in `AGENTS.md` (the commands table says "all 24 headless tests") and in README's test table. README still says "23", so fix that too.

**`tests/menu_test.gd`** (pattern: `tests/start_test.gd`; free every world and menu; a 90 s fail-safe):
1. **Controls data:**
   - `Controls.problems()` is empty.
   - Every upgrade `controls` id exists.
   - `key_groups(move)` is `[["A","D"],["Left","Right"]]`.
   - `key_groups(pause)` is `[["Esc"],["P"]]`.
   - `key_groups(imprint)` is `[["MouseLeft"]]`.
2. **Filtering:**
   - `visible_rows(null)` ids are `move, jump, map, map_zoom, pause`.
   - With `air_jumps = 1` and `gun_unlocked = true`, it adds `double_jump` and `shoot`.
3. **Main menu:**
   - Set `MainMenu._booted = true`, instantiate the scene, and wait a frame.
   - With `Save.enabled = false`, the items are `["Start Game","Controls"]`.
   - With `Save.enabled = true` and `Save.path = "user://menu_test_save.json"` written, the items are `["Continue","New Game","Controls"]`. Restore `enabled` and `path`, and delete the file after.
   - New Game shows the confirm with No focused, and Esc returns.
   - Controls → Back returns.
   - Start Game: after two frames `current_scene` is a World with `from_menu == true`.
4. **Pause** (world `start_override = "2"`):
   - A `pause` action event (`InputEventAction` or an Esc key event to `_unhandled_input`) opens it: `paused`, `modal_owner == "pause"`.
   - A second press resumes.
   - P works the same.
   - With `world._busy = true` the press queues, and it opens a frame after `_busy = false`.
   - With the dev panel open, P does not open it.
   - Main menu: after two frames `current_scene` is a MainMenu, the tree is not paused, `DevSession.mode == NORMAL`, and `GameState.abilities.air_jumps == 0`.
5. **Popup:**
   - In a world, `GameState.grant("double_jump", "1")`, then one physics frame: the popup is open, the tree is paused, and the toast label is not visible.
   - `dismiss()` unpauses.
   - `grant("gun_cooldown", "0.5")` gives no popup.
   - `DevSession.apply(...)` raising `air_jumps` gives no popup.
   - Input within 0.4 s does not dismiss.

**`tests/title_card_test.gd`:**
1. `WorldData.titles["7"].text == "Freddy's Fall"`. Feeding bad `title` values through `_read_entry` (or a small static parse helper you extract) gives errors.
2. **Timing:**
   - World `start_override = "6"`. Place the player at rest at room 6 local (75, 165) with no input. Follow `tests/shaft_test.gd` for stepping physics.
   - Count physics ticks from the tick `GameState.current_room_id` becomes `"7"` to the first tick `player.is_on_floor()`.
   - Print the measured seconds, then assert `abs(TitleCard.total(hold) − measured) <= 0.1`.
   - Assert the card is visible on the entry tick, hidden within 6 ticks after landing, and that `GameState.has_flag("title:7")`.
3. Going back to room 6 and dropping again shows no card.
4. `acquire_modal("test")` and 30 frames leave `modulate.a` unchanged, so pause freezes the card. Release it after.

**Existing tests:** a test that feeds a 3TM with an upgrade (likely `machine_test`, `token_test`, `double_jump_test`, `gun_test`) will now see the popup pause the tree and may time out. Fix each one by asserting the popup opened, then calling `world.power_popup.dismiss()`. Do **not** disable the popups in tests. Every other test must pass unchanged. If a gameplay test needs any other change, stop and ask.

## Docs (same PR)

- **`docs/design/game-design.md`:**
  - A new "Menus, pause and overlays" part of the Implementation reference: the boot routing, the modal owners `"pause"` and `"power"`, the layers, `data/controls.json`, world.json `title`, and the `title:` flags.
  - A Decision log entry with the decisions table above.
  - The dev-tools exemption line (section 7).
  - The status table row.
- **`README.md`:**
  - controls (Esc/P pause)
  - the main scene is now the menu, and `?room=` / `?dev=1` skip it
  - the code-map entries for the new files
  - world.json `title`
  - the test count
- **`AGENTS.md`:** the test count is 26, and a note that `--room` / `--dev` launches skip the main menu.
- **`docs/testing-checklist.md`** (the user plays these):
  - the main menu by mouse, arrows and W/S
  - Continue vs Start Game
  - New Game confirm
  - Controls/Back
  - Esc and P pause, and resume without a stray shot or Imprint
  - the pause Controls page shows only owned powers
  - Main menu → Continue resumes at the last save machine
  - the double jump and gun popups (room 4 and 9 3TMs) pause the game and dismiss
  - the room 7 title card shows on the first drop, fades as Freddy lands, and does not show again after a reload
  - all of it in the browser (`?new-game=1` included)

## Must not change

- **The `world.tscn` boot when it is instantiated directly** (`from_menu = false`). All 24 existing tests, `tools/snap.sh`, `tests/pixel_grid.gd` and the dev session rebuilds rely on it.
- **`DevSession.configure` and `_replace`.** A dev rebuild must never go through the menu.
- **Save format and `VERSION`.** `title:` keys go in `flags`; no migration.
- **The room-file format, RoomParser, solver and solver cache.**
- **The dev panel's appearance.** `UiTheme.build()` returns what `_theme()` did.
- **The Imprint rule, movement numbers and the existing gameplay tests.**

## Dead ends and rejected alternatives

- **Hooking popups to `GameState.abilities_changed`.** It also fires on save loads, `reset()`, dev loadout edits and dev rebuilds, so popups would show at boot and on every F2 change. Use the new `upgrade_granted` signal from `grant()`.
- **A `title:` header in the room file.** The header parser only accepts `exits:`, `trap:` and `legend:` (`src/world/room_parser.gd:400-447`). A new key would reach RoomInfo and the solver cache for something that is pure presentation. Titles go in `world.json`.
- **Opening the pause menu while `world.is_busy()`.** `_feed` and the save machine use timers that run while paused (`create_timer(..., true, true)`), so the animation would continue under the menu. Queue the open instead, as the dev panel does.
- **Making `?room=` / `?dev=1` go through the menu.** That would break `tools/snap.sh`, dev playtesting and the boot-probe in `dev_session_test`.

## Open questions for the user

None. Every design choice is in the decisions table. If something comes up that the table does not cover, ask.

## Verify

```sh
godot --headless --path . --import
tools/check.sh          # 26 tests, validation without cache, web export
tools/pixel_check.sh    # must still print PIXEL pass (world drawing unchanged)
tools/build_web.sh && tools/serve.sh
```

| Check | What to look for |
| --- | --- |
| `title_card_test` output | It prints the measured fall in seconds, and `hold` in world.json matches it |
| `http://localhost:8060/` | The menu shows first. Mouse hover and click work, and so do arrows and W/S with Enter. |
| `http://localhost:8060/?room=7` | Straight into room 7, no menu, and the title card shows |
| `http://localhost:8060/?dev=1&room=4` | Feeding the 3TM shows the double jump popup. Raising air jumps in the F2 dev panel does not. |
| Esc during a door slide | The pause opens when the slide ends, not in the middle of it |
| Pause → Main menu → Continue | Back at the last save machine, with everything still collected |

Do not playtest in the cloud. The user plays the web build on their own machine.

## Session log
- 2026-10-27: Wrote the menus, pause, controls, popups and title cards spec. Decisions are from the user Q&A in this session.
- 2026-10-27: Built to this spec on `in-game-menus`; see the status note at the top for the deviations.
