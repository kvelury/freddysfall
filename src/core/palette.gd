class_name Palette
extends RefCounted

## The two colours in the game besides white and black. Hud re-exports them as
## Hud.RED and Hud.GOLD; entities read them from here because Hud depends on
## GameState, which depends on the entities.

const RED := Color("d22b2b")
## Tokens are gold everywhere: in a room, flying, in a 3TM and in the HUD.
const GOLD := Color("f2c12e")
