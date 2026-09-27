class_name NPC
extends Actor
## Computer-controlled character.
## Orders: guard (stay near home), hold, follow (a leader), move,
## attack_move (march somewhere and fight everything hostile on the way),
## escort (walk next to a caravan), wander.

var order := "guard"
var home := Vector3.ZERO
var order_target := Vector3.ZERO
var leader = null
var leader_uid := ""
var escort = null
var escort_cid := -1
var escort_offset := Vector3.ZERO
var is_soldier := true
var army := false        # belongs to the Villain player's army
var transient := false   # raiders & intruders: removed when far away and idle
var perception := 26.0
var target = null

var _flee_from = null
var _think_t := 0.0
var _wander_t := 0.0
var _wander_point := Vector3.ZERO
var _stuck_t := 0.0
var _detour_t := 0.0
var _detour_sign := 1.0
var _dist_to_player := 0.0
var _far_idle_t := 0.0
var _slow := false
var _path: Array = []
var _path_goal := Vector3(INF, INF, INF)
var _repath_t := 0.0


func _ready() -> void:
	super._ready()
	if role in ["merchant", "healer", "commander", "recruiter"]:
		add_to_group("interactable")
	if home == Vector3.ZERO:
		home = global_position
	_think_t = randf() * 0.5


func _brain(delta: float) -> void:
	_think_t -= delta
	if _think_t <= 0.0:
		_think_t = randf_range(0.35, 0.6)
		_think()
	move_dir = Vector3.ZERO
	sprinting = false
	_slow = false
	if target != null and (not is_instance_valid(target) or target.dead):
		target = null
	if target != null:
		_combat()
	elif _flee_from != null and is_instance_valid(_flee_from) and not _flee_from.dead:
		var away: Vector3 = global_position - _flee_from.global_position
		away.y = 0.0
		move_dir = away.normalized()
		sprinting = true
		face_yaw = atan2(-move_dir.x, -move_dir.z)
	else:
		_follow_orders(delta)
	_avoid_obstacles(delta)
	if _slow:
		move_dir *= 0.45


func _think() -> void:
	var p = Game.player
	_dist_to_player = global_position.distance_to(p.global_position) if p != null and is_instance_valid(p) else 9999.0
	if is_soldier:
		if target == null or randf() < 0.25:
			var t = _find_enemy(perception)
			if t != null:
				target = t
	else:
		_flee_from = _find_enemy(12.0)
	if transient and target == null and _dist_to_player > 230.0:
		_far_idle_t += 0.5
		if _far_idle_t > 60.0:
			queue_free()
	else:
		_far_idle_t = 0.0


func _find_enemy(radius: float):
	var best = null
	var bd := radius
	for a in get_tree().get_nodes_in_group("actors"):
		if a == self:
			continue
		var d := global_position.distance_to(a.global_position)
		if d < bd and Game.are_hostile(self, a):
			best = a
			bd = d
	return best


func _combat() -> void:
	var to: Vector3 = target.global_position - global_position
	to.y = 0.0
	var d := to.length()
	if d > perception * 2.0:
		target = null
		return
	var dir := to / maxf(d, 0.001)
	face_yaw = atan2(-dir.x, -dir.z)
	if can_shoot() and d > 4.0:
		if d > 28.0:
			move_dir = dir
		elif attack_cd <= 0.0:
			var aim: Vector3 = target.global_position + Vector3(randf_range(-0.4, 0.4), 1.2 + randf_range(-0.3, 0.4), randf_range(-0.4, 0.4))
			shoot_at(aim)
		return
	var reach: float = 1.6 + (target.model_scale - 1.0) * 0.5
	if d > reach:
		if d > 6.0:
			# go around walls (e.g. through the palace gate) when needed
			_travel(target.global_position, reach)
			face_yaw = atan2(-move_dir.x, -move_dir.z) if move_dir != Vector3.ZERO else face_yaw
		else:
			move_dir = dir
		sprinting = d > 6.0 and mobility() == "walk"
	else:
		try_attack()


func _follow_orders(delta: float) -> void:
	match order:
		"hold":
			pass
		"follow":
			if leader == null or not is_instance_valid(leader) or leader.dead:
				order = "guard"
				home = global_position
				return
			var slot := _formation_slot()
			var goal: Vector3 = leader.global_position + slot
			if not _go_to(goal, 2.0):
				sprinting = global_position.distance_to(goal) > 8.0 and mobility() == "walk"
		"move", "attack_move":
			if _travel(order_target, 7.0):
				order = "guard"
				home = order_target
		"escort":
			if escort == null or not is_instance_valid(escort):
				order = "guard"
				home = global_position
				return
			var goal: Vector3 = escort.global_transform * escort_offset
			if not _go_to(goal, 1.2):
				sprinting = global_position.distance_to(goal) > 6.0
		_:
			var r := 10.0 if order == "guard" else 30.0
			if global_position.distance_to(home) > r + 5.0:
				_travel(home, 3.0)
				return
			if role in ["merchant", "healer", "recruiter"]:
				return
			_wander_t -= delta
			if _wander_t <= 0.0:
				_wander_t = randf_range(3.0, 8.0)
				if randf() < 0.5:
					_wander_point = global_position
				else:
					var a := randf() * TAU
					_wander_point = home + Vector3(cos(a), 0, sin(a)) * randf_range(0.0, r)
			if not _go_to(_wander_point, 1.0):
				_slow = true


func _formation_slot() -> Vector3:
	var idx := absi(get_instance_id()) % 8
	var a := idx * TAU / 8.0
	return Vector3(cos(a), 0, sin(a)) * (2.5 + (idx % 2) * 1.5)


## Like _go_to, but long trips follow the road graph (and leave walled
## places through their gates).
func _travel(point: Vector3, tolerance: float) -> bool:
	_repath_t -= get_physics_process_delta_time()
	if point.distance_to(_path_goal) > 1.0 and (_repath_t <= 0.0 or _path.is_empty()):
		_repath_t = 0.6
		_path_goal = point
		_path = Game.world.find_path(global_position, point) if Game.world else [point]
	if _path.is_empty():
		_path = [point]
	_path[-1] = point
	while _path.size() > 1:
		var to: Vector3 = _path[0] - global_position
		to.y = 0.0
		if to.length() > 4.0:
			break
		_path.pop_front()
	if _path.size() <= 1:
		return _go_to(point, tolerance)
	_go_to(_path[0], 1.0)
	return false


func _go_to(point: Vector3, tolerance: float) -> bool:
	var to := point - global_position
	to.y = 0.0
	var d := to.length()
	if d <= tolerance:
		return true
	move_dir = to / d
	face_yaw = atan2(-move_dir.x, -move_dir.z)
	return false


func _avoid_obstacles(delta: float) -> void:
	if move_dir == Vector3.ZERO:
		_stuck_t = 0.0
		return
	if _detour_t > 0.0:
		_detour_t -= delta
		move_dir = move_dir.rotated(Vector3.UP, _detour_sign * 1.2)
		return
	var real := get_real_velocity()
	real.y = 0.0
	if real.length() < speed() * 0.25:
		_stuck_t += delta
		if _stuck_t > 0.6:
			_stuck_t = 0.0
			_detour_t = randf_range(0.6, 1.3)
			_detour_sign = 1.0 if randf() < 0.5 else -1.0
			want_jump = true
	else:
		_stuck_t = 0.0


func _on_attacked(attacker) -> void:
	if not is_soldier:
		_flee_from = attacker
		return
	if target == null or randf() < 0.5:
		target = attacker
	# call nearby friends for help
	for a in get_tree().get_nodes_in_group("actors"):
		if a == self or a.is_player or a.faction != faction or a == attacker:
			continue
		if a.global_position.distance_to(global_position) < 18.0:
			a.aggro[attacker.get_instance_id()] = Time.get_ticks_msec()
			if a.is_soldier and a.target == null:
				a.target = attacker


# --- interaction (merchants, healers, commander, recruiter) ---------------

func interact_position() -> Vector3:
	return global_position + Vector3(0, 1, 0)


func can_interact(p) -> bool:
	if dead or Game.are_hostile(self, p):
		return false
	match role:
		"merchant", "healer":
			return true
		"commander":
			return p.faction == Factions.EMPIRE and faction == Factions.EMPIRE
		"recruiter":
			return p.faction == Factions.VILLAIN and faction == Factions.VILLAIN
	return false


func interact_text(_p) -> String:
	match role:
		"merchant":
			return "E: Trade with %s" % display_name
		"healer":
			return "E: Ask %s for treatment" % display_name
		"commander":
			return "E: Report to %s" % display_name
		"recruiter":
			return "E: Recruit soldiers"
	return ""


func interact(_p) -> void:
	match role:
		"merchant":
			Game.hud.open_shop(self)
		"healer":
			Game.hud.open_healer(self)
		"commander":
			Game.hud.open_commander(self)
		"recruiter":
			Game.hud.open_recruit(self)


# --- save / load ----------------------------------------------------------

func to_dict() -> Dictionary:
	var d := super.to_dict()
	d["order"] = order
	d["home"] = [home.x, home.y, home.z]
	d["order_target"] = [order_target.x, order_target.y, order_target.z]
	d["leader_uid"] = leader.uid if leader != null and is_instance_valid(leader) else ""
	d["escort_cid"] = escort.cid if escort != null and is_instance_valid(escort) else -1
	d["escort_offset"] = [escort_offset.x, escort_offset.y, escort_offset.z]
	d["soldier"] = is_soldier
	d["army"] = army
	d["transient"] = transient
	return d


func from_dict(d: Dictionary) -> void:
	super.from_dict(d)
	order = str(d.get("order", "guard"))
	var h: Array = d.get("home", [0, 0, 0])
	home = Vector3(h[0], h[1], h[2])
	var t: Array = d.get("order_target", [0, 0, 0])
	order_target = Vector3(t[0], t[1], t[2])
	leader_uid = str(d.get("leader_uid", ""))
	escort_cid = int(d.get("escort_cid", -1))
	var o: Array = d.get("escort_offset", [0, 0, 0])
	escort_offset = Vector3(o[0], o[1], o[2])
	is_soldier = bool(d.get("soldier", true))
	army = bool(d.get("army", false))
	transient = bool(d.get("transient", false))
