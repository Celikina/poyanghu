extends Node
const Art := preload("res://scripts/pixel_card_art.gd")
const TIERS := ["basic", "effective", "deep"]
const EXPECTED := {
	"water_control": [[0, 0], [5, 2], [9, 0]],
	"veg_restore": [[9, 1], [13, 1], [16, 0]],
	"submerged_planting": [[9, 0], [14, 0], [29, 0]],
	"seed_bank": [[11, 2], [17, 1], [23, 0]],
	"invasive_clear": [[3, 0], [6, 1], [10, 0]],
	"water_replenish": [[0, 0], [4, 1], [7, 0]],
	"floodplain_diversion": [[3, 1], [4, 1], [7, 1]],
	"wetland_restore": [[6, 1], [11, 2], [12, 0]],
	"floating_island": [[0, 0], [4, 1], [6, 0]],
	"habitat_protect": [[0, 0], [3, 2], [4, 0]],
	"eco_brand": [[0, 0], [0, 0], [4, 0]],
	"grazing_ban": [[3, 2], [6, 0], [11, 0]],
	"eco_jobs": [[3, 0], [6, 1], [9, 0]],
	"eco_resettle": [[11, 2], [13, 1], [20, 0]],
	"migration_corridor": [[0, 0], [4, 1], [6, 0]],
	"obstruction_clear": [[7, 0], [10, 0], [16, 0]],
	"lake_chief": [[0, 0], [0, 0], [5, 0]],
	"sand_mining": [[2, 0], [4, 0], [7, 0]],
	"eco_water_scheduling": [[0, 0], [3, 2], [5, 2]],
	"preseason_drawdown": [[6, 2], [8, 2], [13, 1]],
	"riparian_buffer": [[0, 0], [3, 1], [5, 1]],
	"crab_control_replanting": [[8, 1], [14, 1], [25, 0]],
	"waterbird_food_supply": [[0, 0], [3, 2], [4, 2]],
}
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func fixture(state: Node) -> void:
	state.reset_game()
	state.difficulty = 0
	state.turn = 1
	state.funds = 500
	state.turn_budget = 500
	state.metrics = {"water_level": 50, "vegetation": 35, "water_quality": 50, "fish": 50, "birds": 50, "community": 80}
	state._is_settlement_preview = true
func _ready() -> void:
	if not ProjectSettings.get_setting("application/config/use_custom_user_dir", false):
		push_error("Card balance tests require an isolated user directory")
		get_tree().quit(1)
		return
	AudioServer.set_bus_mute(0, true)
	Talents.reset_all()
	var state = load("res://scripts/game_state.gd").new()
	for id in EXPECTED:
		for i in TIERS.size():
			var tier: String = TIERS[i]
			var expected: Array = EXPECTED[id][i]
			var card: Dictionary = state.card_by_id(id)
			var entries: Array = card.tiers[tier].effects.filter(func(e): return e.metric == "vegetation")
			if expected[0] == 0:
				check(entries.is_empty(), "%s/%s keeps no vegetation effect" % [id, tier])
			else:
				check(entries.size() == 1 and entries[0].delta == expected[0] and entries[0].delay == expected[1], "%s/%s exact vegetation amount and original delay" % [id, tier])
			for dispatched in [false, true]:
				fixture(state)
				var cost: int = state.tier_cost(id, tier)
				check(state.execute_action(id, tier, dispatched), "%s/%s executes" % [id, tier])
				check(state.funds == 500 - (0 if dispatched else cost), "%s/%s original payment rule" % [id, tier])
				check(state.metrics.vegetation == 35 + (expected[0] if expected[1] == 0 else 0), "%s/%s immediate gain matches tier" % [id, tier])
				if expected[1] > 0:
					var pending: Array = state.effects_queue.filter(func(e): return e.metric == "vegetation")
					check(pending.size() == 1 and pending[0].delta == expected[0] and pending[0].remaining == expected[1], "%s/%s delayed gain matches preview" % [id, tier])
					for step in int(expected[1]):
						state.advance_effects()
						check(state.metrics.vegetation == 35 + (expected[0] if step == int(expected[1]) - 1 else 0), "%s/%s gain arrives on original turn" % [id, tier])
	for card in GameState.ACTION_CARDS:
		check(not card.name.contains("(") and not card.name.contains("（"), "%s canonical main title" % card.id)
		check(Art.face_glyph_scale(card.name, card.category) == 4, "%s uniform normal action title size" % card.id)
		var fresh: Image = Art.dispatch_texture(card, false).get_image()
		var baked: Image = Art.dispatch_texture(card).get_image()
		fresh.convert(Image.FORMAT_RGBA8)
		baked.convert(Image.FORMAT_RGBA8)
		check(fresh.get_data() == baked.get_data(), "%s dispatch baked face matches current main title" % card.id)
	for old_title in ["生态补水(引江济湖)", "生态补水（引江济湖）", "生态补水（引江（济湖））"]:
		check(Art.display_title(old_title) == "生态补水", "Old title removes whole parenthetical annotation")
		check(Art.texture(old_title, "40").get_image().get_data() == Art.texture("生态补水", "40").get_image().get_data(), "Legacy title renders as normal-size main name")
	for card in GameState.KNOWLEDGE_CARDS.values():
		var plan: Dictionary = Art.face_photo_plan(card.name)
		check(plan.scale == Art.FACE_SCALE, "%s uniform knowledge title size" % card.name)
		check("".join(plan.name_lines) == card.name, "%s full knowledge name retained" % card.name)
		check(plan.side == 246 and plan.photo_x == 79 and Art.FACE_PHOTO_TOP == 175, "%s unchanged photo area" % card.name)
		var bottom: int = plan.name_top + 16 * plan.scale + (plan.lines - 1) * Art.FACE_NAME_INDENT * plan.scale + plan.scale
		check(bottom <= 510, "%s text and shadow clear photo and footer" % card.name)
	state.free()
	print("CARD_BALANCE: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)
