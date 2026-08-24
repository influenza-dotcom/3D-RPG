class_name PlayerLeanSettings
extends Resource

## Global tuning for LEANING — the Deus Ex / Cruelty Squad corner-peek. Edit in the inspector on
## GameSettings.player_lean (resources/tuning/PlayerLeanSettings.tres); never hardcode these at the seam.
## The behaviour lives in scripts/player/lean.gd (the `Lean` drop-in under the Player).
##
## WHAT A LEAN IS, AND WHAT IT DELIBERATELY IS NOT:
##   * It is a HEAD-RIG shift. Holding the lean action slides the camera rig sideways and rolls it into the
##     lean, so you can look — and shoot, since the aim ray starts at the camera — round a corner.
##   * It is NOT a body move. The CharacterBody3D capsule never moves, so a lean can't push you through
##     geometry, desync the navmesh, or change the shape an NPC's fire has to hit. You expose your VIEW,
##     not your hitbox. Don't "fix" that by moving the collider — every movement system on the Player
##     assumes the capsule is where the body is.
##   * It is NOT free of the world: max_offset is clamped every frame by a sideways shape-cast
##     (probe_radius / probe_margin / probe_collision_mask) so the camera stops short of a wall instead
##     of poking the near clip plane through it.

@export_group("Pose")
## Master switch. Off = the lean actions do nothing and the head rests centred (Q then falls back to its
## contextual verb alone — Takedown/Pet; E does nothing at all, since Interact lives on F).
@export var enabled: bool = true
## How far the head rig slides sideways at FULL lean, in metres. This is the whole peek distance — bigger
## leans further round the corner and puts more of your view past cover. Clamped down by the wall probe.
@export_range(0.0, 1.5, 0.01) var max_offset: float = 0.45
## Camera ROLL at full lean, in degrees — the head-tilt that sells the peek. Rolls INTO the lean, matching
## the sign convention the strafe tilt already uses (CameraEffects). Set 0 for a pure sideways slide.
## ⭐Honours the SAME accessibility toggle as the strafe roll (Options → Accessibility → "Camera Tilt"):
## with tilt off you still get the positional peek, just no rolled horizon. Motion comfort, one switch.
@export_range(0.0, 45.0, 0.5) var max_roll_deg: float = 12.0
## How fast the lean eases in/out, in units of lean-fraction per second (the Crouch.lerp_speed idiom —
## move_toward, so it's a constant rate, not an exponential ease). Higher = a snappier peek.
@export var lerp_speed: float = 8.0

@export_group("Wall Probe")
## Radius (m) of the sphere shape-cast that measures sideways clearance. Roughly "how much room the head
## needs": too small and the camera's near plane clips the corner it's peeking past, too large and you
## can't lean in a doorway. Should be at least the camera's near distance.
@export_range(0.05, 0.6, 0.01) var probe_radius: float = 0.22
## Extra clearance (m) kept between the probe and whatever it hits, so a full lean stops a hand's width
## short of the wall rather than flush against it.
@export_range(0.0, 0.5, 0.01) var probe_margin: float = 0.1
## Physics layers the clearance probe collides with. Default layer 1 = the WORLD (the func_godot brush
## geometry and level colliders) ONLY, so a passing NPC or a physics prop never snaps your lean back —
## leaning is stopped by architecture, not by traffic.
@export_flags_3d_physics var probe_collision_mask: int = 1

@export_group("Gates")
## Allow leaning while airborne. OFF by design: a mid-air peek reads as a camera glitch, and the lean is a
## slow, deliberate cover verb — you plant, then peek. Turn on for a floatier, more arcade feel.
##
## ⭐This gate is SOFT — going airborne eases the lean out and eases it straight back on landing, and never
## drops your hold on the key. It has to be: EVERY shipped weapon applies `WeaponData.self_knockback` to the
## shooter on fire (`attack.gd`), which lands in `explosion_velocity` → `velocity`, so any shot aimed even
## slightly DOWNWARD shoves you up and un-grounds you for a few frames. A hard gate here meant one trigger
## pull killed the lean until you released the key — i.e. you could not shoot and lean at the same time.
@export var allow_airborne: bool = false
## Grace window (seconds) after last touching the floor during which you still count as grounded for the lean
## — the coyote-time idiom, applied to peeking. Sized to absorb a weapon's recoil hop and a stair-seam blip
## without a visible dip; a real jump or fall outruns it and the lean eases out as intended. 0 disables it.
@export_range(0.0, 1.0, 0.01) var ground_grace: float = 0.35
