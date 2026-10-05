extends Node2D

const RunModel = preload("res://game/scripts/state/run_state.gd")
const LocaleScript = preload("res://game/scripts/ui/game_locale.gd")
const FortressScript = preload("res://game/scripts/defense/fortress_world.gd")
const DungeonScript = preload("res://game/scripts/dungeon/dungeon_world.gd")
const AudioScript = preload("res://game/scripts/ui/demo_audio.gd")
const EffectsScript = preload("res://game/scripts/fx/pixel_effects.gd")
const PixelFontScript = preload("res://game/scripts/ui/pixel_font.gd")
const WaveLedgerScript = preload("res://game/scripts/defense/wave_ledger.gd")
const MonsterCatalogScript = preload("res://game/data/monsters/monster_catalog.gd")

var state: RunModel = RunModel.new()
var fortress: FortressScript
var dungeon: DungeonScript
var interface: CanvasLayer
var screen: Control
var modal: Control
var modal_kind: String = ""
var controls_return_to_pause: bool = false
var game_theme: Theme
var hud_labels: Array[Label] = []
var message_label: Label
var health_bar: ProgressBar
var rally_bar: ProgressBar
var rally_button: Button
var player_health: int = 100
var audio: Node
var effects: EffectsScript
var sound_button: Button
var selected_slot: int = 1
var view_phase: int = 0
var _quitting: bool = false
var _previous_auto_accept_quit: bool = true
var _quit_policy_registered: bool = false
var _hud_cache: Array = []
var _hud_texts: Array[String] = []
var _skill_cache: Array = []
var _skill_text: String = ""
var _message_seconds: float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_previous_auto_accept_quit = get_tree().auto_accept_quit
	get_tree().auto_accept_quit = false
	_quit_policy_registered = true
	LocaleScript.install()
	_register_input()
	game_theme = _create_theme()
	fortress = FortressScript.new()
	fortress.position = Vector2(24, 96)
	add_child(fortress)
	dungeon = DungeonScript.new()
	dungeon.position = Vector2(60, 132)
	add_child(dungeon)
	audio = AudioScript.new()
	add_child(audio)
	effects = EffectsScript.new()
	add_child(effects)
	dungeon.feedback_requested.connect(_on_feedback)
	fortress.feedback_requested.connect(_on_feedback)
	fortress.tower_selected.connect(_open_tower_modal)
	fortress.castle_damaged.connect(state.damage_castle)
	fortress.wave_completed.connect(state.finish_defense)
	dungeon.loot_collected.connect(state.collect_gold)
	dungeon.goal_key_collected.connect(state.take_goal_key)
	dungeon.sealed_chest_requested.connect(_open_sealed_modal)
	dungeon.exit_requested.connect(_exit_dungeon)
	dungeon.failed.connect(state.fail)
	dungeon.health_changed.connect(_health_changed)
	dungeon.message_requested.connect(_world_message)
	interface = CanvasLayer.new()
	add_child(interface)
	state.phase_changed.connect(_render_phase)
	state.changed.connect(_refresh_hud)
	_render_phase(state.Phase.TITLE)

func _register_input() -> void:
	var bindings: Dictionary = {"fb_move_left": KEY_A, "fb_move_right": KEY_D, "fb_move_up": KEY_W, "fb_move_down": KEY_S, "fb_sword": KEY_J, "fb_bow": KEY_K, "fb_interact": KEY_E}
	for action: String in bindings:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		var event: InputEventKey = InputEventKey.new()
		event.physical_keycode = bindings[action]
		if not InputMap.action_has_event(action, event):
			InputMap.action_add_event(action, event)
	for binding: Array in [["fb_sword", MOUSE_BUTTON_LEFT], ["fb_bow", MOUSE_BUTTON_RIGHT]]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = binding[1]
		if not InputMap.action_has_event(binding[0], event):
			InputMap.action_add_event(binding[0], event)

func _create_theme() -> Theme:
	var result: Theme = Theme.new()
	result.default_font = PixelFontScript.create()
	result.default_font_size = PixelFontScript.font_size(20)
	for kind: String in ["normal", "hover", "pressed", "disabled"]:
		var filename: String = {"normal": "button", "hover": "button_hover", "pressed": "button_pressed", "disabled": "button_disabled"}[kind]
		result.set_stylebox(kind, "Button", _tiny_style(filename))
	result.set_color("font_color", "Button", Color(0.10, 0.23, 0.25))
	result.set_color("font_hover_color", "Button", Color(0.06, 0.16, 0.18))
	result.set_color("font_pressed_color", "Button", Color(0.08, 0.18, 0.20))
	result.set_color("font_disabled_color", "Button", Color(0.36, 0.34, 0.29))
	result.set_color("font_color", "Label", Color(0.23, 0.19, 0.13))
	result.set_type_variation("PrimaryButton", "Button")
	for kind: String in ["normal", "hover", "pressed", "disabled"]:
		var filename: String = {"normal": "button", "hover": "button_hover", "pressed": "button_pressed", "disabled": "button_disabled"}[kind]
		var tint: Color = Color(0.43, 0.63, 0.67) if kind != "disabled" else Color(0.80, 0.80, 0.74)
		result.set_stylebox(kind, "PrimaryButton", _tiny_style(filename, tint))
	result.set_color("font_color", "PrimaryButton", Color(1, 0.97, 0.87))
	result.set_color("font_hover_color", "PrimaryButton", Color(1, 1, 0.95))
	result.set_color("font_pressed_color", "PrimaryButton", Color(1, 0.95, 0.79))
	result.set_color("font_disabled_color", "PrimaryButton", Color(0.36, 0.34, 0.29))
	return result

func _tiny_style(filename: String, modulation: Color = Color.WHITE) -> StyleBoxTexture:
	var style: StyleBoxTexture = StyleBoxTexture.new()
	style.texture = load("res://game/assets/tiny_swords_ui/" + filename + ".png")
	style.modulate_color = modulation
	style.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	style.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	for side: int in range(4):
		style.set_texture_margin(side, 16)
		style.set_content_margin(side, 10)
	return style

func _panel(parent: Node, rectangle: Rect2, color: Color = Color(0.055, 0.082, 0.105, 0.96)) -> Panel:
	var panel: Panel = Panel.new()
	panel.position = rectangle.position
	panel.size = rectangle.size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if rectangle.size == Vector2(1280, 720):
		var shade: StyleBoxFlat = StyleBoxFlat.new()
		shade.bg_color = color
		panel.add_theme_stylebox_override("panel", shade)
	else:
		var frame: StyleBoxTexture = _tiny_style("panel")
		frame.draw_center = false
		panel.add_theme_stylebox_override("panel", frame)
		var interior: Panel = Panel.new()
		interior.name = "PanelInterior"
		interior.position = Vector2(16, 16)
		interior.size = (rectangle.size - Vector2(32, 32)).max(Vector2.ZERO)
		interior.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var surface: StyleBoxFlat = StyleBoxFlat.new()
		surface.bg_color = Color(0.89, 0.85, 0.73)
		interior.add_theme_stylebox_override("panel", surface)
		panel.add_child(interior)
	parent.add_child(panel)
	return panel

func _label(parent: Node, key: String, rectangle: Rect2, font_size: int = 20, color: Color = Color(0.23, 0.19, 0.13)) -> Label:
	var label: Label = Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", PixelFontScript.font_size(font_size))
	label.add_theme_constant_override("line_spacing", 0)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	label.position = rectangle.position
	label.size = rectangle.size
	label.text = tr(key)
	label.size = rectangle.size
	return label

func _button(parent: Node, key: String, rectangle: Rect2, callback: Callable, node_name: String = "") -> Button:
	var button: Button = Button.new()
	button.text = tr(key)
	button.position = rectangle.position
	button.size = rectangle.size
	button.focus_mode = Control.FOCUS_NONE
	if key in ["UI_START_CAMPAIGN", "UI_ENTER_DUNGEON", "UI_START_DEFENSE", "UI_REPLAY", "UI_RETRY_ROUND", "UI_SEALED_ACCEPT", "UI_BUILD_TOWER", "UI_UPGRADE_TOWER", "UI_RALLY"]:
		button.theme_type_variation = "PrimaryButton"
	if not node_name.is_empty():
		button.name = node_name
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _render_phase(phase: int) -> void:
	view_phase = phase
	get_tree().paused = false
	if is_instance_valid(screen):
		interface.remove_child(screen)
		screen.queue_free()
	screen = Control.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.theme = game_theme
	interface.add_child(screen)
	modal = null
	modal_kind = ""
	controls_return_to_pause = false
	hud_labels.clear()
	_hud_cache = []
	_hud_texts.clear()
	_skill_cache = []
	_skill_text = ""
	_message_seconds = 0.0
	message_label = null
	health_bar = null
	rally_button = null
	rally_bar = null
	fortress.selected_tower = -1
	fortress.tower_selection_enabled = phase in [state.Phase.PREPARATION, state.Phase.SETTLEMENT]
	sound_button = null
	effects.clear()
	var phase_names: Array[String] = ["title", "preparation", "dungeon", "settlement", "defense", "complete", "failed"]
	audio.set_phase(phase_names[phase])
	fortress.running = phase == state.Phase.DEFENSE
	fortress.visible = phase != state.Phase.DUNGEON
	fortress.process_mode = Node.PROCESS_MODE_PAUSABLE if fortress.visible else Node.PROCESS_MODE_DISABLED
	dungeon.visible = phase == state.Phase.DUNGEON
	dungeon.process_mode = Node.PROCESS_MODE_PAUSABLE if dungeon.visible else Node.PROCESS_MODE_DISABLED
	if phase == state.Phase.TITLE:
		var title_towers: Array[int] = [1, 1, 1, 1, 0, 0]
		fortress.prepare(title_towers)
		_build_menu()
	elif phase in [state.Phase.COMPLETE, state.Phase.FAILED]:
		fortress.running = false
		_build_result(phase == state.Phase.COMPLETE)
	else:
		if phase in [state.Phase.PREPARATION, state.Phase.SETTLEMENT]:
			fortress.prepare(state.tower_levels)
			fortress.set_round_preview(state.round_index)
		_build_header(phase)
		if phase == state.Phase.DUNGEON:
			_build_dungeon_footer()
		else:
			_build_sidebar(phase)
	_refresh_hud()

func _build_menu() -> void:
	_panel(screen, Rect2(0, 0, 1280, 720), Color(0.025, 0.04, 0.075, 0.72))
	_panel(screen, Rect2(380, 104, 520, 486))
	var title: Label = _label(screen, "UI_TITLE", Rect2(402, 143, 476, 90), 58, Color(0.33, 0.19, 0.08))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var subtitle: Label = _label(screen, "UI_SUBTITLE", Rect2(398, 246, 484, 48), 22)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_button(screen, "UI_START_CAMPAIGN", Rect2(490, 316, 300, 54), start_campaign, "StartCampaign")
	_button(screen, "UI_CONTROLS", Rect2(490, 391, 300, 50), _open_controls)
	_button(screen, "UI_QUIT", Rect2(490, 466, 300, 50), _quit_game)
	_make_sound_button(Rect2(1102, 34, 132, 44))

func _build_header(phase: int) -> void:
	_panel(screen, Rect2(24, 20, 1232, 100))
	_label(screen, "UI_TITLE", Rect2(44, 31, 242, 40), 30, Color(0.33, 0.19, 0.08))
	if phase != state.Phase.SETTLEMENT:
		var phase_key: String = {state.Phase.PREPARATION: "UI_PREPARATION_TITLE", state.Phase.DUNGEON: "UI_DUNGEON_TITLE", state.Phase.DEFENSE: "UI_DEFENSE_TITLE"}[phase]
		var phase_label: Label = _label(screen, phase_key, Rect2(46, 77, 222, 25), 16, Color(0.36, 0.28, 0.15))
		if phase == state.Phase.DUNGEON:
			phase_label.text = tr("UI_ROUND") + " " + str(state.round_index) + "  " + tr("UI_DUNGEON_LEVEL_%d" % state.round_index)
	var icon_names: Array[String] = ["coin", "tower", "shield", "bell"]
	if phase == state.Phase.DUNGEON:
		icon_names = ["heart", "bag", "key", "bell"]
	for index: int in range(4):
		var icon: TextureRect = TextureRect.new()
		icon.name = "HudIcon" + str(index)
		icon.texture = load("res://game/assets/icons/" + icon_names[index] + ".png")
		icon.position = Vector2(282 + index * 196, 48)
		icon.size = Vector2(24, 24)
		icon.modulate = Color(0.4, 0.29, 0.12) if index != 0 or phase != state.Phase.DUNGEON else Color.WHITE
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		screen.add_child(icon)
		hud_labels.append(_label(screen, "", Rect2(312 + index * 196, 42, 164, 34), 17))
	health_bar = ProgressBar.new()
	var health_index: int = 0 if phase == state.Phase.DUNGEON else 2
	health_bar.name = "HealthBar"
	health_bar.position = Vector2(312 + health_index * 196, 86)
	health_bar.size = Vector2(164, 8)
	health_bar.max_value = 100
	health_bar.show_percentage = false
	var fill: StyleBoxFlat = StyleBoxFlat.new()
	fill.bg_color = Color(0.3, 0.78, 0.57)
	var track: StyleBoxFlat = StyleBoxFlat.new()
	track.bg_color = Color(0.22, 0.24, 0.21)
	health_bar.add_theme_stylebox_override("background", track)
	health_bar.add_theme_stylebox_override("fill", fill)
	screen.add_child(health_bar)
	_make_sound_button(Rect2(1064, 44, 84, 46))
	_button(screen, "UI_PAUSE", Rect2(1152, 44, 84, 46), _open_pause)

func _make_sound_button(rectangle: Rect2) -> void:
	sound_button = _button(screen, "UI_SOUND_ON", rectangle, _toggle_sound, "SoundToggle")
	sound_button.icon = load("res://game/assets/icons/sound.png")
	sound_button.add_theme_font_size_override("font_size", PixelFontScript.font_size(16))
	sound_button.tooltip_text = tr("UI_SOUND_TIP")
	_refresh_sound_button()

func _toggle_sound() -> void:
	audio.set_muted(not audio.get_muted())
	_refresh_sound_button()

func _refresh_sound_button() -> void:
	if is_instance_valid(sound_button):
		sound_button.text = tr("UI_SOUND_OFF" if audio.get_muted() else "UI_SOUND_ON")

func _build_sidebar(phase: int) -> void:
	var construction: bool = phase in [state.Phase.PREPARATION, state.Phase.SETTLEMENT]
	_panel(screen, Rect2(1000, 144, 254, 280 if construction else 542))
	var construction_key: String = "UI_FIRST_EXPEDITION_HINT" if phase == state.Phase.PREPARATION and state.completed_rounds == 0 and state.gold < state.balance.build_gold_cost else "UI_MAP_BUILD_HELP"
	message_label = _label(screen, construction_key if construction else "UI_DEFENSE_HELP", Rect2(1016, 158, 222, 70), 24)
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if construction:
		var repair: Button = _button(screen, "UI_REPAIR_CASTLE", Rect2(1016, 264, 220, 42), _repair_castle, "RepairCastle")
		repair.add_theme_font_size_override("font_size", PixelFontScript.font_size(16))
		repair.disabled = state.castle_hp >= state.balance.castle_max_hp
		_label(screen, "UI_REPAIR_COST", Rect2(1016, 312, 220, 28), 16).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var key: String = "UI_ENTER_DUNGEON" if phase == state.Phase.PREPARATION else "UI_START_DEFENSE"
		var action: Callable = enter_dungeon if phase == state.Phase.PREPARATION else begin_defense
		_button(screen, key, Rect2(1016, 360, 220, 44), action)
	else:
		message_label.size.y = 120
		message_label.text = tr("UI_DEFENSE_HELP")
		rally_button = _button(screen, "UI_RALLY", Rect2(1016, 310, 220, 60), func() -> void: fortress.activate_rally(), "RallySkill")
		rally_button.tooltip_text = tr("UI_RALLY_TIP") % [fortress.balance.firepower_boost_percent(), int(fortress.balance.rally_duration), int(fortress.balance.rally_cooldown)]
		rally_bar = ProgressBar.new()
		rally_bar.position = Vector2(1016, 382)
		rally_bar.size = Vector2(220, 12)
		rally_bar.max_value = fortress.balance.rally_cooldown
		rally_bar.show_percentage = false
		screen.add_child(rally_bar)
		var alarm_label: Label = _label(screen, "", Rect2(1016, 420, 222, 90), 16)
		alarm_label.text = tr("UI_ALARM_ACTIVE") % _alarm_enemy_description() if state.alarm else tr("UI_ALARM_SAFE")
		alarm_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var cost_backdrop: Panel = _panel(screen, Rect2(24, 664, 964, 44), Color(0.045, 0.065, 0.055, 0.96))
	cost_backdrop.name = "CostBackdrop"
	var footer: Label = _label(screen, "UI_BUILD_COST", Rect2(44, 674, 920, 24), 24, Color(0.23, 0.19, 0.13))
	footer.text = tr("UI_ROUTE_FIXED") if phase == state.Phase.DEFENSE else tr("UI_BUILD_COST") + "    |    " + tr("UI_UPGRADE_COST")

func _build_dungeon_footer() -> void:
	_panel(screen, Rect2(24, 620, 1232, 88))
	message_label = _label(screen, "UI_KEY_REQUIRED", Rect2(44, 632, 1026, 28), 24)
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label(screen, "UI_CONTROLS_DUNGEON_BRIEF", Rect2(44, 670, 1026, 28), 24, Color(0.38, 0.32, 0.24))
	_button(screen, "UI_ABANDON", Rect2(1096, 644, 142, 44), func() -> void: state.fail("expedition_abandoned"))

func _build_result(success: bool) -> void:
	_panel(screen, Rect2(0, 0, 1280, 720), Color(0.025, 0.04, 0.065, 0.8))
	_panel(screen, Rect2(334, 115, 612, 500))
	var title_key: String = "UI_CAMPAIGN_COMPLETE" if success else "UI_FAILURE_TITLE"
	var title: Label = _label(screen, title_key, Rect2(352, 151, 576, 70), 44, Color(0.33, 0.19, 0.08))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var key: String = "UI_CAMPAIGN_DONE" if success else "UI_FAILURE_" + state.failure_reason.to_upper()
	var reason: Label = _label(screen, key, Rect2(378, 234, 524, 68), 24)
	reason.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if success:
		var built: int = 0
		for level: int in state.tower_levels:
			if level > 0:
				built += 1
		var summary: Label = _label(screen, "", Rect2(378, 312, 524, 58), 24)
		summary.name = "RunSummary"
		summary.text = tr("UI_CASTLE_HP") + " " + str(state.castle_hp) + "    " + tr("UI_BANK_GOLD") + " " + str(state.gold) + "\n" + tr("UI_TOWERS_BUILT") + " " + str(built) + " / " + str(state.tower_levels.size())
		var notice: Label = _label(screen, "UI_CAMPAIGN_REPLAY_NOTICE", Rect2(378, 380, 524, 58), 24)
		notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var replay_action: Callable = start_campaign if success else retry_round
	_button(screen, "UI_REPLAY" if success else "UI_RETRY_ROUND", Rect2(466, 454, 348, 60), replay_action)
	_button(screen, "UI_MAIN_MENU", Rect2(466, 531, 348, 50), _show_main_menu)
	_make_sound_button(Rect2(1102, 34, 132, 44))

func _show_main_menu() -> void:
	state.return_to_title()

func _refresh_hud() -> void:
	if hud_labels.size() != 4:
		return
	var values: Array = [view_phase, TranslationServer.get_locale()]
	if view_phase == state.Phase.DUNGEON:
		values.append_array([player_health, state.bag_gold, state.has_goal_key, state.alarm])
	else:
		var built: int = 0
		for level: int in state.tower_levels:
			if level > 0:
				built += 1
		values.append_array([state.gold, built, state.tower_levels.size(), state.castle_hp, fortress.remaining_enemies() if view_phase == state.Phase.DEFENSE else state.round_index, state.balance.round_limit])
	if values != _hud_cache:
		_hud_cache = values
		if view_phase == state.Phase.DUNGEON:
			_hud_texts.assign([tr("UI_PLAYER_HP") + " " + str(player_health), tr("UI_BAG_GOLD") + " " + str(state.bag_gold), tr("UI_KEY_READY" if state.has_goal_key else "UI_KEY_MISSING"), tr("UI_ALARM_SHORT") if state.alarm else tr("UI_ALARM_SAFE")])
		else:
			_hud_texts.assign([tr("UI_BANK_GOLD") + " " + str(state.gold), tr("UI_TOWERS_BUILT") + " " + str(values[3]) + " / " + str(state.tower_levels.size()), tr("UI_CASTLE_HP") + " " + str(state.castle_hp), tr("UI_ENEMIES") + " " + str(values[6]) if view_phase == state.Phase.DEFENSE else tr("UI_ROUND") + " " + str(state.round_index) + " / " + str(state.balance.round_limit)])
	for index: int in range(4):
		if hud_labels[index].text != _hud_texts[index]:
			hud_labels[index].text = _hud_texts[index]
	if is_instance_valid(health_bar):
		var health: float = player_health if view_phase == state.Phase.DUNGEON else state.castle_hp
		if health_bar.value != health:
			health_bar.value = health

func _process(_delta: float) -> void:
	if view_phase == state.Phase.DUNGEON and not get_tree().paused and dungeon.can_process() and is_instance_valid(message_label):
		_message_seconds = maxf(0.0, _message_seconds - _delta)
		if _message_seconds <= 0.0:
			var hint: Dictionary = dungeon.get_interaction_hint(dungeon.player.position)
			var context_key: String = hint.get("key", "UI_MSG_KEY_FOUND" if state.has_goal_key else "UI_KEY_REQUIRED")
			var context_text: String = tr(context_key)
			if message_label.text != context_text:
				message_label.text = context_text
	if view_phase == state.Phase.DEFENSE:
		_refresh_hud()
		if is_instance_valid(rally_button):
			var disabled: bool = fortress.ledger.rally_cooldown_left > 0.0 or not fortress.running
			if rally_button.disabled != disabled:
				rally_button.disabled = disabled
			var skill_values: Array = [TranslationServer.get_locale(), fortress.rally_seconds > 0.0, ceili(fortress.ledger.rally_cooldown_left)]
			if skill_values != _skill_cache:
				_skill_cache = skill_values
				_skill_text = tr("UI_RALLY_ACTIVE") if fortress.rally_seconds > 0 else tr("UI_RALLY_COOLDOWN") % skill_values[2] if fortress.ledger.rally_cooldown_left > 0 else tr("UI_RALLY")
			if rally_button.text != _skill_text:
				rally_button.text = _skill_text
			if is_instance_valid(rally_bar):
				var progress: float = fortress.balance.rally_cooldown - fortress.ledger.rally_cooldown_left
				if rally_bar.value != progress:
					rally_bar.value = progress

func start_campaign() -> void:
	player_health = 100
	var was_preparing: bool = state.phase == state.Phase.PREPARATION
	state.start_campaign()
	if was_preparing:
		_render_phase(state.phase)

func enter_dungeon() -> void:
	if state.begin_dungeon():
		player_health = 100
		dungeon.reset_run(state.round_index - 1)

func _exit_dungeon() -> void:
	if not state.settle_loot():
		_world_message("UI_KEY_MISSING")
	else:
		fortress.prepare(state.tower_levels)
		fortress.set_round_preview(state.round_index)

func begin_defense() -> void:
	if state.start_defense():
		fortress.start_wave(state.alarm, state.tower_levels, state.round_index)

func retry_round() -> void:
	if state.phase != state.Phase.FAILED:
		return
	player_health = 100
	if state.retry_round():
		fortress.prepare(state.tower_levels)
		fortress.set_round_preview(state.round_index)

func _tower_action(slot: int) -> void:
	if slot < 0 or slot >= state.tower_levels.size():
		_world_message("UI_ERR_INVALID_SLOT")
		return
	var changed: bool = state.build_tower(slot) if state.tower_levels[slot] == 0 else state.upgrade_tower(slot)
	if changed:
		_render_phase(state.phase)
		fortress.emit_build_feedback(fortress.to_global(fortress.tower_points[slot]))
	else:
		_world_message("UI_RESOURCES_NOT_ENOUGH")

func _repair_castle() -> void:
	if not state.repair_castle():
		_world_message("UI_RESOURCES_NOT_ENOUGH")
	else:
		_render_phase(state.phase)
		fortress.emit_build_feedback(fortress.to_global(Vector2(780, 300)))

func _on_feedback(event: String, at: Vector2) -> void:
	audio.play_event(event)
	effects.spawn_effect(event, at)

func _health_changed(current: int, _maximum: int) -> void:
	player_health = current
	_refresh_hud()

func _world_message(key: String) -> void:
	if is_instance_valid(message_label):
		_message_seconds = 2.0
		if key in ["UI_MSG_SEAL_OPENED", "UI_SEALED_OPENED"]:
			message_label.text = tr(key) % [state.balance.sealed_chest_gold, _alarm_enemy_description()]
		elif key == "UI_ALARM_WARNING":
			message_label.text = tr(key) % _alarm_enemy_description()
		else:
			message_label.text = tr(key)

func _alarm_enemy_description() -> String:
	var kind: String = WaveLedgerScript.alarm_enemy_kind(state.round_index)
	var definition: Dictionary = MonsterCatalogScript.get_definition(kind)
	return "%d %s" % [WaveLedgerScript.alarm_enemy_count(state.round_index), tr(definition["name_key"])]

func _new_modal() -> Panel:
	if is_instance_valid(modal):
		modal.queue_free()
	modal = Control.new()
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.theme = game_theme
	screen.add_child(modal)
	var shade: Panel = _panel(modal, Rect2(0, 0, 1280, 720), Color(0.025, 0.035, 0.05, 0.84))
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	return _panel(modal, Rect2(332, 150, 616, 422))

func _open_tower_modal(slot: int) -> void:
	if state.phase not in [state.Phase.PREPARATION, state.Phase.SETTLEMENT] or slot < 0 or slot >= state.tower_levels.size():
		return
	if is_instance_valid(modal):
		return
	selected_slot = slot
	fortress.selected_tower = slot
	modal_kind = "tower"
	var panel: Panel = _new_modal()
	var title: Label = _label(panel, "", Rect2(28, 26, 550, 48), 36)
	title.text = tr("UI_TOWER_SITE_TITLE") % (slot + 1)
	var level: int = state.tower_levels[slot]
	var cost: int = state.balance.build_gold_cost if level == 0 else state.balance.upgrade_gold_cost
	var maximum: bool = level >= state.balance.tower_max_level
	var details: Label = _label(panel, "", Rect2(30, 96, 318, 80), 24)
	details.name = "TowerDetails"
	var current_damage: int = fortress.balance.tower_level_two_damage if level >= 2 else fortress.balance.tower_level_one_damage
	var current_rate: float = 1.0 / (fortress.balance.tower_level_two_interval if level >= 2 else fortress.balance.tower_level_one_interval)
	var next_damage: int = fortress.balance.tower_level_one_damage if level == 0 else fortress.balance.tower_level_two_damage
	var next_rate: float = 1.0 / (fortress.balance.tower_level_one_interval if level == 0 else fortress.balance.tower_level_two_interval)
	details.text = tr("UI_TOWER_SITE_STATS") % [level, int(fortress.balance.tower_range), current_damage]
	var comparison: Label = _label(panel, "", Rect2(30, 184, 318, 56), 24)
	comparison.name = "TowerComparison"
	comparison.text = tr("UI_TOWER_MAX") if maximum else tr("UI_TOWER_COMPARISON") % [0 if level == 0 else current_damage, next_damage, 0.0 if level == 0 else current_rate, next_rate]
	if not maximum:
		_label(panel, "", Rect2(30, 246, 318, 52), 24).text = tr("UI_TOWER_SITE_COST") % [cost, state.gold]
	var shortfall: Label = _label(panel, "", Rect2(32, 377, 550, 28), 24, Color(0.53, 0.23, 0.19))
	shortfall.name = "TowerShortfall"
	if not maximum and state.gold < cost:
		shortfall.text = tr("UI_TOWER_SHORTFALL") % (cost - state.gold)
	var preview_foot: Vector2 = Vector2(475, 244)
	for layer: Dictionary in fortress.get_tower_layers(slot):
		var preview: TextureRect = TextureRect.new()
		var atlas: AtlasTexture = AtlasTexture.new()
		atlas.atlas = fortress.textures[layer["texture_key"]]
		atlas.region = layer["source"]
		preview.texture = atlas
		preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		var destination: Rect2 = layer["destination"]
		preview.position = preview_foot + (destination.position - fortress.tower_points[slot]) * 0.75
		preview.size = destination.size.abs() * 0.75
		preview.flip_h = destination.size.x < 0.0
		preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(preview)
	var key: String = "UI_TOWER_MAX" if maximum else "UI_BUILD_TOWER" if level == 0 else "UI_UPGRADE_TOWER"
	var confirm: Button = _button(panel, key, Rect2(32, 304, 252, 62), _tower_action.bind(slot), "TowerConfirm")
	confirm.disabled = maximum or state.gold < cost
	_button(panel, "UI_CANCEL", Rect2(316, 304, 252, 62), _close_modal, "TowerCancel")
	fortress.queue_redraw()

func _open_sealed_modal() -> void:
	if state.phase != state.Phase.DUNGEON:
		return
	dungeon.process_mode = Node.PROCESS_MODE_DISABLED
	modal_kind = "sealed"
	var panel: Panel = _new_modal()
	_label(panel, "UI_SEALED_TITLE", Rect2(28, 28, 550, 70), 29)
	var description: Label = _label(panel, "", Rect2(30, 118, 550, 136), 24)
	description.name = "SealedDescription"
	description.text = tr("UI_SEALED_DESCRIPTION") % [state.balance.sealed_chest_gold, _alarm_enemy_description()]
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_button(panel, "UI_SEALED_ACCEPT", Rect2(32, 304, 252, 62), accept_sealed_chest)
	_button(panel, "UI_SEALED_DECLINE", Rect2(316, 304, 252, 62), _close_modal)

func accept_sealed_chest() -> void:
	if state.open_sealed_chest():
		dungeon.confirm_sealed_chest()
	_close_modal()

func _close_modal() -> void:
	if modal_kind == "controls" and controls_return_to_pause:
		controls_return_to_pause = false
		if is_instance_valid(modal):
			modal.queue_free()
		modal = null
		_open_pause()
		return
	get_tree().paused = false
	if is_instance_valid(modal):
		modal.queue_free()
	modal = null
	modal_kind = ""
	fortress.selected_tower = -1
	fortress.queue_redraw()
	if view_phase == state.Phase.DUNGEON:
		dungeon.process_mode = Node.PROCESS_MODE_PAUSABLE

func _open_pause() -> void:
	if is_instance_valid(modal) and modal.visible:
		return
	get_tree().paused = true
	modal_kind = "pause"
	var panel: Panel = _new_modal()
	_label(panel, "UI_PAUSE_TITLE", Rect2(34, 28, 542, 68), 36)
	_button(panel, "UI_RESUME", Rect2(96, 133, 420, 62), _close_modal)
	_button(panel, "UI_CONTROLS", Rect2(96, 220, 420, 62), _open_controls)
	_button(panel, "UI_MAIN_MENU", Rect2(96, 307, 420, 62), _show_main_menu)

func _open_controls() -> void:
	controls_return_to_pause = modal_kind == "pause"
	get_tree().paused = true
	modal_kind = "controls"
	var panel: Panel = _new_modal()
	panel.size = Vector2(616, 500)
	var interior: Panel = panel.get_node("PanelInterior") as Panel
	interior.size = panel.size - Vector2(32, 32)
	_label(panel, "UI_CONTROLS", Rect2(24, 18, 566, 56), 32)
	_label(panel, "UI_CONTROLS_DUNGEON", Rect2(28, 90, 552, 130), 19).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label(panel, "UI_CONTROLS_DEFENSE", Rect2(28, 228, 552, 136), 19).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_button(panel, "UI_BACK", Rect2(168, 411, 280, 55), _close_modal)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if is_instance_valid(modal):
			_close_modal()
		elif view_phase not in [state.Phase.TITLE, state.Phase.COMPLETE, state.Phase.FAILED]:
			_open_pause()
		get_viewport().set_input_as_handled()

func _quit_game() -> void:
	if _quitting or not is_inside_tree():
		return
	_quitting = true
	var tree: SceneTree = get_tree()
	fortress.running = false
	fortress.process_mode = Node.PROCESS_MODE_DISABLED
	dungeon.process_mode = Node.PROCESS_MODE_DISABLED
	effects.process_mode = Node.PROCESS_MODE_DISABLED
	interface.process_mode = Node.PROCESS_MODE_DISABLED
	audio.stop_all()
	audio.process_mode = Node.PROCESS_MODE_DISABLED
	set_process_unhandled_input(false)
	tree.paused = false
	await tree.process_frame
	await tree.process_frame
	await tree.create_timer(0.1, true, false, true).timeout
	tree.quit()

func _notification(what: int) -> void:
	if what == Node.NOTIFICATION_WM_CLOSE_REQUEST:
		_quit_game()

func _exit_tree() -> void:
	if _quit_policy_registered:
		var tree: SceneTree = get_tree()
		if tree != null:
			tree.auto_accept_quit = _previous_auto_accept_quit
		_quit_policy_registered = false
