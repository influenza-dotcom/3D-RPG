extends Node
## GameState — the live run's RESPAWN point (and, layered on next, the autosaved progression profile).
## Dark Souls style: on death you're brought back to LIFE at the last bonfire — the world is NOT reset
## (enemies stay as they are, nothing reloads). The Player seeds this with its spawn on first _ready; a
## Bonfire overrides it on rest; Player._respawn_at_checkpoint reads it on death.

var has_respawn: bool = false
var respawn_position: Vector3 = Vector3.ZERO
var respawn_yaw: float = 0.0  ## body yaw (radians) the player faces on respawn

## Set the point a death brings the player back to (a bonfire, or the player's initial spawn).
func set_respawn(position: Vector3, yaw: float) -> void:
	respawn_position = position
	respawn_yaw = yaw
	has_respawn = true

## Forget the respawn point (a fresh game).
func clear() -> void:
	has_respawn = false
	respawn_position = Vector3.ZERO
	respawn_yaw = 0.0
