extends KinematicBody2D

# -----------------------------------------------------------------------------
# Imports
# -----------------------------------------------------------------------------

# Resources
const SmokeEmitterResource : PackedScene = preload("res://Scenes/Branches/SmokeEmitter.tscn")

# Data Structures
const Direction : Dictionary = Global.Direction

# Constants
const PIXELS_PER_TILE : int = Global.PIXELS_PER_TILE
const GRAVITY : int = Global.GRAVITY

# -----------------------------------------------------------------------------
# Data Structures
# -----------------------------------------------------------------------------

# todo: probably refactor to Global.Direction later, and rename current
#       Global.Direction to Global.Facing. Also fill in with diagonals, Back or
#       Left/Right instead of Back/Forward
enum HunterSkillDirection {
	Neutral,
	Up,
	Forward,
	Down
}

enum LandingType {
	# Values are fall distance thresholds, in pixels
	Normal = 0,
	# Higher landings force a brief recovery state under certain conditions,
	# whilst lerping motion[.x] to 0 over its duration
	High = 3 * PIXELS_PER_TILE, # Dropkicks only
	VeryHigh = 8 * PIXELS_PER_TILE # Any fall
}

# -----------------------------------------------------------------------------
# Constants
# -----------------------------------------------------------------------------

const MOVE_SPEED : int = 6 * PIXELS_PER_TILE

const JUMP_STRENGTH : int = -200
const NUM_JUMPS : int = 2 # Including first grounded jump

#const ACCELERATION_GLITCH_EDGE_THRESHOLD : int = 3 # Corner Boost and Acceleration Glitch
#const ACCELERATION_GLITCH_INITIATE_FRAMES : int = 60 # Acceleration Glitch

# todo:
# Refactor these to X_DISTANCE, X_TIME, and X_DRAG/X_LERP? So we can backdash/slide
# into a wall and keep animation for X_TIME (with motion.x at 0)
# Can also reuse $Timers.LandingTimer as general-purpose animation lock timer
const BACKDASH_FORCE : int = 180
const BACKDASH_DRAG : int = 6
const DROPKICK_Y_VELOCITY : int = 20 * PIXELS_PER_TILE
const DIAGONAL_DROPKICK_X_VELOCITY : int = 15 * PIXELS_PER_TILE
const SLIDE_FORCE : int = 240
const SLIDE_DRAG : int = 8

# -----------------------------------------------------------------------------
# Properties
# -----------------------------------------------------------------------------

# Player State
var facing : int = Direction.Right

var is_crouching : bool
var is_falling : bool
var is_jumping : bool
var is_moving : bool
var is_running : bool
var is_taunting : bool

# Player State - Locking input/animation, until the action/event completes
var is_animation_locked : bool # special flag, combining the following flags (OR):
var is_attacking : bool
var is_backdashing : bool
var is_dropkicking : bool
var is_dropkicking_diagonally : bool
var is_hurt : bool
var is_recovering_from_hard_landing : bool
var is_sliding : bool

# Action Eligibility
var can_attack : bool
var can_backdash : bool
var can_crouch : bool
var can_dropkick : bool
var can_jump : bool
var can_move : bool
var can_slide : bool
var can_taunt : bool
var can_turn : bool

# Computed Properties

var motion := Vector2()

var jumps_remaining : int = 0
var last_jump_peak_y : float
var diagonal_dropkick_x_multiplier : float # When using left analog stick to aim

var last_attack_was_during_backdash : bool # We can only backdash once during stationary attack spam
var was_crouching_last_frame : bool
var was_on_floor_last_frame : bool
var was_running_last_frame : bool

# -----------------------------------------------------------------------------
# Lifecycle Methods
# -----------------------------------------------------------------------------

func _ready() -> void:
	last_jump_peak_y = position.y # reset

	$Weapon.hide()

	$Timers/LandingTimer.connect("timeout", self, "on_landing_timer_timeout");

	$Weapon/Animator.connect("frame_changed", self, "on_weapon_animation_frame_changed")
	$Weapon/Animator.connect("animation_finished", self, "on_weapon_animation_finished")


func _physics_process(delta : float) -> void:
	handle_input()
	update_motion(delta)
	update_flags()
	update_animation()
	update_weapon()

	was_crouching_last_frame = is_crouching
	was_on_floor_last_frame = is_on_floor()
	was_running_last_frame = is_running


func handle_input() -> void:
	# Horizontal movement
	if is_crouching and not is_sliding:
		motion.x = 0

#		if Input.is_action_pressed("game_move_left"):
#			if can_turn:
#				facing = Direction.Left
#		elif Input.is_action_pressed("game_move_right"):
#			if can_turn:
#				facing = Direction.Right

	elif not is_backdashing and not is_dropkicking and not is_sliding and not is_recovering_from_hard_landing:
		if can_move:
			if Input.is_action_pressed("game_move_left"):
#				if can_turn:
#					# Turn around while running
#					if is_running and facing == Direction.Right:
#						emit_smoke(1, 0, 0, 20)
#
#					facing = Direction.Left

				motion.x = -MOVE_SPEED

			elif Input.is_action_pressed("game_move_right"):
#				if can_turn:
#					# Turn around while running
#					if is_running and facing == Direction.Left:
#						emit_smoke(1, 180, 0, 20)
#
#					facing = Direction.Right

				motion.x = MOVE_SPEED

			else:
				motion.x = 0

				# Stop running
				if was_running_last_frame:
					emit_smoke(1, 0 if facing == Direction.Right else 180, 0, 20)

		else:
			motion.x = 0

	# Movement (Left Analog / D-pad)
	var horizontal_move = Input.get_action_strength("game_move_right") - Input.get_action_strength("game_move_left")

	if horizontal_move != 0:
		var direction = sign(horizontal_move)
		action_turn(direction)
		action_move(horizontal_move)

	# Move Camera (Right Analog)
	# todo

	# Open Game Menu
	# Open Phrase/Emote Menu

	# Jump (A)
	if Input.is_action_just_pressed("game_jump"):
		action_jump()

		# Dropkick/Slide (Down + A)
		if Input.is_action_pressed("game_crouch"):
			action_dropkick()
			action_slide()

	# Attack 1 (X)
	if Input.is_action_just_pressed("game_attack1"):
		action_attack(1)

	# Attack 2 (Y)
#	if Input.is_action_just_pressed("game_attack2"):
#		action_attack(2)

	# Hunter Skills (B)
#	if Input.is_action_just_pressed("game_hunter_skill"):
#		var hunter_skill_direction : int
#
#		if Input.is_action_pressed("game_taunt"):
#			hunter_skill_direction = HunterSkillDirection.Up
#		elif Input.is_action_pressed("game_move_left") or Input.is_action_pressed("game_move_right"):
#			hunter_skill_direction = HunterSkillDirection.Forward
#		elif Input.is_action_pressed("game_crouch"):
#			hunter_skill_direction = HunterSkillDirection.Down
#		else:
#			hunter_skill_direction = HunterSkillDirection.Neutral
#
#		action_hunter_skill(hunter_skill_direction)

	# Backdash (LB)
	if Input.is_action_just_pressed("game_backdash"):
		action_backdash()

	# Personal Skill (RB)
#	if Input.is_action_pressed("game_personal_skill"):
#		action_personal_skill()

	# Use Item (LT)
	# todo

	# Confirm Action (RT)
	# todo

	# Unused (L3)

	# Adjust Camera Zoom (R3)
	# todo

	# Martial Arts
	# todo

	# todo: weapon-specific techniques, eg:
	# - dagger: fwd [neutral] fwd + attack
	# - katana: down down+fwd fwd + attack (aka QCF)
	# - greatsword: up up+fwd fwd + attack
	# should probably go in action_attack()


func update_motion(delta : float) -> void:
	# Dropkick
	if is_dropkicking:
		motion.y = DROPKICK_Y_VELOCITY

		if is_dropkicking_diagonally:
			motion.x = DIAGONAL_DROPKICK_X_VELOCITY * diagonal_dropkick_x_multiplier * facing

	else:
		motion.y += GRAVITY

		# Check for early jump key release while jumping
		if motion.y < 0 and Input.is_action_just_released("game_jump"):
			motion.y /= 4

	# Backdash
	if is_backdashing:
		motion.x += BACKDASH_DRAG * facing

		# Check when to end backdash
		if (facing == Direction.Left and motion.x < 0) or (facing == Direction.Right and motion.x > 0):
			motion.x = 0
			is_backdashing = false

	# Crouching
#	elif is_crouching and not is_sliding:
#		motion.x = 0

	# Slide
	elif is_sliding:
		motion.x -= SLIDE_DRAG * facing

		# Check when to end slide
		if (facing == Direction.Left and motion.x > 0) or (facing == Direction.Right and motion.x < 0):
			motion.x = 0
			is_sliding = false

	# Hard landing recovery
	elif is_recovering_from_hard_landing:
		if motion.x != 0:
			motion = motion.linear_interpolate(Vector2.ZERO, ($Timers/LandingTimer.wait_time - $Timers/LandingTimer.time_left) / $Timers/LandingTimer.wait_time)

	# Apply physics and update position
	motion = move_and_slide(motion, Vector2.UP)

	# Stop backdash/slide when hitting a wall
	if motion.x == 0:
		is_backdashing = false
		is_sliding = false

	# Stop backdash/slide/land recovery when falling off a ledge
	if (is_backdashing or is_sliding or is_recovering_from_hard_landing) and motion.y > 0:
		is_backdashing = false
		is_sliding = false
		is_recovering_from_hard_landing = false

	# Landing resets
	if is_on_floor() and not was_on_floor_last_frame:
		var fall_distance = position.y - last_jump_peak_y

		on_land(fall_distance)

	# Update jump peak
	if not is_on_floor() and position.y < last_jump_peak_y:
		last_jump_peak_y = position.y


func update_flags() -> void:
	is_moving = motion.x != 0
	is_running = is_moving and is_on_floor()
	is_jumping = motion.y < 0
	is_falling = motion.y > 0

	is_crouching = (Input.is_action_pressed("game_crouch") and can_crouch) \
			or (is_attacking and was_crouching_last_frame)

	is_taunting = Input.is_action_pressed("game_taunt") \
			and can_taunt

	is_animation_locked = is_attacking \
			or is_backdashing \
			or is_dropkicking \
			or is_hurt \
			or is_recovering_from_hard_landing \
			or is_sliding

	can_turn = not is_animation_locked

	can_move = not is_animation_locked \
			and not is_crouching \
			and not is_taunting \
			or (is_attacking and not is_on_floor())

	can_crouch = (not is_animation_locked \
					or (is_attacking and is_crouching) \
					or is_backdashing \
					or is_sliding \
				) \
			and is_on_floor()

	can_taunt = not is_animation_locked \
			and is_on_floor()

	can_jump = (not is_animation_locked or is_backdashing) \
			and (is_on_floor() or jumps_remaining > 0) \
			and not is_crouching

	can_attack = not is_animation_locked \
			or is_backdashing

	can_backdash = (not is_animation_locked \
				or (is_attacking and not last_attack_was_during_backdash) \
			) \
			and is_on_floor() \
			and not is_crouching

	can_dropkick = not is_animation_locked \
			and not is_on_floor() \
			and jumps_remaining == 0

	can_slide = not is_animation_locked \
			and is_crouching


func update_animation() -> void:
	$Animator.flip_h = true if facing == Direction.Left else false

	# State-locked animations
	if is_attacking:
		if is_crouching:
			$Animator.play("AttackCrouch")
		else:
			$Animator.play("Attack")

	elif is_backdashing:
		$Animator.play("Backdash")

	elif is_dropkicking:
		if is_dropkicking_diagonally:
			$Animator.play("JumpkickDiagonal")
		else:
			$Animator.play("Jumpkick")

	elif is_recovering_from_hard_landing:
		$Animator.play("Crouch")

	elif is_sliding:
		$Animator.play("Slide")

	# Non state-locked animations
	else:
		if is_crouching:
			$Animator.play("Crouch")
		elif is_taunting:
			$Animator.play("Taunt")
		elif is_jumping:
			$Animator.play("Stand")
		elif is_falling:
			$Animator.play("Fall")
		elif is_running:
			$Animator.play("Walk")
		else:
			$Animator.play("Stand")


func update_weapon() -> void:
	var weapon_area_x_offset : int = 25
	var weapon_area_y_stand : int = -4
	var weapon_area_y_crouch : int = 3

	var weapon_animation_x_offset : int = 6
	var weapon_animation_y_stand : int = 0
	var weapon_animation_y_crouch : int = 7

	$Weapon/Area2D.position.x = weapon_area_x_offset if facing == Direction.Right else -weapon_area_x_offset
	$Weapon/Area2D.position.y = weapon_area_y_crouch if is_crouching else weapon_area_y_stand

	$Weapon/Animator.position.x = weapon_animation_x_offset if facing == Direction.Right else -weapon_animation_x_offset
	$Weapon/Animator.position.y = weapon_animation_y_crouch if is_crouching else weapon_animation_y_stand
	$Weapon/Animator.flip_h = true if facing == Direction.Left else false

# -----------------------------------------------------------------------------
# User Action Methods
# -----------------------------------------------------------------------------

func action_turn(direction : int) -> void:
	if not can_turn:
		return

	facing = direction


func action_move(horizontal_move : int) -> void:
	if not can_move:
		return

	var direction : int = sign(horizontal_move)

	# todo: impl
	pass


func action_jump() -> void:
	if not can_jump:
		return

	motion.y = JUMP_STRENGTH

	jumps_remaining -= 1
	last_jump_peak_y = position.y # reset


func action_attack(weapon : int) -> void:
	if not can_attack:
		return

	is_attacking = true

	if is_backdashing:
		last_attack_was_during_backdash = true
		is_backdashing = false

	$Animator.frame = 0
	$Weapon/Animator.frame = 0
	$Weapon/Animator.play("Leather Whip")
	$Weapon.show()


func action_backdash() -> void:
	if not can_backdash:
		return

	is_backdashing = true
	motion.x = -BACKDASH_FORCE * facing

	# Backdash-cancel technique
	if not last_attack_was_during_backdash and is_attacking:# and not is_crouching: (shouldnt be needed here)
		stop_attacking()


func action_dropkick() -> void:
	if not can_dropkick:
		return

	is_dropkicking = true

	# Reset jump peak to skillfully allow negating hard landings
	last_jump_peak_y = position.y

	if Input.is_action_pressed("game_move_left") or Input.is_action_pressed("game_move_right"):
		var strength : float = abs(Input.get_action_strength("game_move_right") - Input.get_action_strength("game_move_left"))

		is_dropkicking_diagonally = true
		diagonal_dropkick_x_multiplier = strength


func action_slide() -> void:
	if not can_slide:
		return

	is_sliding = true
	motion.x = SLIDE_FORCE * facing

# -----------------------------------------------------------------------------
# Events
# -----------------------------------------------------------------------------

func on_land(fall_distance : float) -> void:
	# Check corner boost glitch
#	if is_dropkicking_diagonally and eligible_for_corner_boost_glitch():
#		pass

	if fall_distance >= LandingType.VeryHigh:
		trigger_landing_recovery_state()
		emit_smoke(5, 270, 90, 30)

	elif fall_distance >= LandingType.High and is_dropkicking:
		trigger_landing_recovery_state()
		emit_smoke(3, 270, 90, 20)

	else:
		emit_smoke(1, 90, 0, 0)

	# Reset jump counters
	jumps_remaining = NUM_JUMPS
	last_jump_peak_y = position.y

	# Cancel attack
	if is_attacking:
		stop_attacking()

	# Cancel dropkick
	if is_dropkicking:
		is_dropkicking = false
		is_dropkicking_diagonally = false

# -----------------------------------------------------------------------------
# Connected Signal Methods
# -----------------------------------------------------------------------------

func on_weapon_animation_frame_changed() -> void:
	# Check for damage
	if $Weapon/Animator.frame >= 2:
		var overlapping_bodies = $Weapon/Area2D.get_overlapping_bodies()

		#print(overlapping_bodies)


func on_weapon_animation_finished() -> void:
	stop_attacking()


func on_landing_timer_timeout() -> void:
	is_recovering_from_hard_landing = false

# -----------------------------------------------------------------------------
# Helper Methods
# -----------------------------------------------------------------------------

func stop_attacking() -> void:
	is_attacking = false
	last_attack_was_during_backdash = false # reset

	$Weapon.hide()
	$Weapon/Animator.stop()


func emit_smoke(num_particles : int, direction : int = 90, spread : int = 0, initial_velocity : int = 20) -> void:
	var emitter = SmokeEmitterResource.instance() as Particles2D
	emitter.emitting = true
	emitter.amount = num_particles
	emitter.rotation_degrees = direction

	var material = emitter.process_material as ParticlesMaterial
	material.spread = spread
	material.initial_velocity = initial_velocity

	# while slide/backdash: (emit some particles for the duration over time)
		# lifetime = duration of slide/backdash? needs slide/backdash refactor first
		# explosiveness = 0 (spread out particles over time)

	$Emitters.add_child(emitter)


func trigger_landing_recovery_state() -> void:
	is_recovering_from_hard_landing = true

	$Timers/LandingTimer.start()
