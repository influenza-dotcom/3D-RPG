class_name SkyTitle
extends Node3D

## A huge title card "drawn in the sky": a billboarded Label3D parked FAR in the direction the player is looking,
## so world geometry (the city skyline) OCCLUDES it -- it's a real depth-tested 3D object at sky distance -- while
## it stays big, readable, and tracks the view. It FADES IN at a cue time after the game-start song begins, so the
## title drop lands on a musical beat. SELF-ARMS on spawn (and the player also pings it when the intro song
## starts), so the cue always runs regardless of how the game started; reveals once it elapses. Flip
## test_show_immediately to preview it instantly while tuning.
##
## SETUP: drop ONE under the Game root. Tune cue_seconds BY EAR if it lands early/late (Spotify has a little start
## latency, and the cue counts from when the play command is issued, not the audible downbeat). sky_distance is
## auto-clamped just inside the camera's far plane so the title never gets clipped away.

## The title text (all-caps reads best as a sky title).
@export var text: String = "CYBER SUNDAY"
## Seconds after the intro song starts to reveal the title. 2:48 = 168s. Tune by ear.
@export var cue_seconds: float = 168.0
## Seconds the title takes to fade up from nothing.
@export var fade_in_time: float = 2.5
## Seconds the title HOLDS at full visibility before it fades back out and disappears.
@export var hold_seconds: float = 30.0
## Seconds the title takes to fade out at the end.
@export var fade_out_time: float = 2.5
## How far (m) ahead of the camera the title sits -- large, so it reads as sky distance and the skyline cuts across
## it. Auto-clamped to just inside the camera's far plane.
@export var sky_distance: float = 350.0
## On-screen size knobs (bump for bigger) + colour. The label sits at a constant distance, so its apparent size is
## steady. "CYBER SUNDAY" is WIDE -- if it overflows the screen, LOWER pixel_size (or raise sky_distance); if it
## looks tiny, raise pixel_size. Tune with test_show_immediately on.
@export var pixel_size: float = 0.25
@export var font_size: int = 256
@export var text_color: Color = Color.WHITE
## Vertical STRETCH -- 1 = normal, >1 = taller letters (a tall, imposing title), <1 = squashed. Width is unchanged.
@export var vertical_stretch: float = 1.5
## TESTING: reveal the title IMMEDIATELY (skip the ~2:48 cue) so you can see + size it without waiting. Turn OFF
## for the real timed drop.
@export var test_show_immediately: bool = false

var _label: Label3D = null
var _armed: bool = false
var _t: float = 0.0
var _shown_t: float = 0.0   ## seconds since the title was revealed -- drives fade-in -> hold -> fade-out
var _revealed: bool = false
var _done: bool = false     ## true once it has fully faded out -- stops further work

func _ready() -> void:
	add_to_group(&"sky_title")
	_label = Label3D.new()
	_label.text = text
	_label.font_size = font_size
	_label.pixel_size = pixel_size
	_label.outline_size = 0                                    # all-white, no outline
	_label.modulate = Color(text_color.r, text_color.g, text_color.b, 0.0)  # start fully transparent
	# Billboard OFF -- we orient it toward the camera MANUALLY each frame (matching the camera's basis) so a
	# non-uniform (vertical) scale survives, which Label3D's own billboard would drop.
	_label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	_label.double_sided = true
	_label.shaded = false                                      # flat full-bright, reads as a sky title
	_label.no_depth_test = false                               # KEEP depth test on, so the skyline occludes it
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_label)
	_label.visible = false
	arm()  # self-arm on spawn, so the cue runs even if nothing pings us (direct scene run / no Spotify / etc.)

## Start the cue countdown. Self-called on _ready (so the title works regardless of how the game started) and also
## pinged by the player when the intro song begins. Idempotent -- the first arm wins, so it counts from spawn.
func arm() -> void:
	if _armed:
		return
	_armed = true
	_t = 0.0

func _process(delta: float) -> void:
	if not _armed or _done:
		return
	if not _revealed:
		_t += delta
		if not test_show_immediately and _t < cue_seconds:
			return
		_revealed = true
		_label.visible = true
	# Park the title far ahead of the active camera (so it tracks where you look), kept inside the far plane.
	# Being a real 3D object at sky distance, closer geometry (the skyline) depth-occludes it.
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var cb := cam.global_transform.basis.orthonormalized()
	var dist := minf(sky_distance, cam.far * 0.9)
	# Face the camera by matching its basis (the label's +Z points back at the camera -> readable, not mirrored),
	# with the UP column scaled for the vertical STRETCH -> camera-facing AND taller. Parked far ahead (along the
	# camera's -Z) so the skyline depth-occludes it.
	_label.global_transform = Transform3D(Basis(cb.x, cb.y * vertical_stretch, cb.z), cam.global_position - cb.z * dist)
	# Lifecycle: fade IN -> HOLD (hold_seconds) -> fade OUT, then hide for good.
	_shown_t += delta
	var fi := maxf(fade_in_time, 0.001)
	var fo := maxf(fade_out_time, 0.001)
	var alpha := 1.0  # the HOLD level (between fade-in and fade-out)
	if _shown_t < fi:
		alpha = _shown_t / fi                                  # fading in
	elif _shown_t >= fi + hold_seconds + fo:
		alpha = 0.0                                            # done -> gone
		_done = true
		_label.visible = false
	elif _shown_t > fi + hold_seconds:
		alpha = 1.0 - (_shown_t - fi - hold_seconds) / fo      # fading out
	_label.modulate = Color(text_color.r, text_color.g, text_color.b, alpha)
