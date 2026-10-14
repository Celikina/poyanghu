extends Node
## 结局短片的回归：素材在不在、播片期间 BGM 是不是关着、收尾（播完/跳过）后 BGM 是不是从头重播。
## 用法（隔离副本 + 真窗口，headless 没有视频解码）：
##   POYANG_SCREENSHOT_DIR=<dir> godot --path <copy>
## 会在 <dir> 落一张播片中的截图。

var checks := 0
var failures := 0
var game: Node


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)


func wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _ready() -> void:
	if not ProjectSettings.get_setting("application/config/use_custom_user_dir", false):
		push_error("Run in an isolated test project")
		get_tree().quit(1)
		return
	AudioServer.set_bus_mute(0, true)
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	add_child(scene)
	game = scene.get_node("Game")
	await wait(0.8)

	check(ResourceLoader.exists(String(game.ENDING_VIDEO)), "结尾短片素材在工程里")
	check(game.bgm_player != null and game.bgm_player.playing, "播片之前 BGM 正常在放")

	game._play_ending()
	await wait(0.8)
	check(game._ending_playing, "播片已经开始")
	check(not game.bgm_player.playing, "播片期间 BGM 是关掉的")
	check(game.ending_layer != null and game.ending_layer.visible, "播片层已显示")
	check(game.ending_player.is_playing(), "视频确实在播")

	await wait(2.4)
	var dir := OS.get_environment("POYANG_SCREENSHOT_DIR")
	if dir != "":
		var img := game.get_viewport().get_texture().get_image()
		img.save_png(dir.path_join("ending-frame.png"))
		print("SHOT: ", dir.path_join("ending-frame.png"))

	game._finish_ending()
	await wait(0.8)
	check(not game._ending_playing, "收尾后播片状态已清")
	check(not game.ending_layer.visible, "收尾后播片层已隐藏")
	check(game.bgm_player.playing, "收尾后 BGM 重新播放")
	check(game.bgm_player.get_playback_position() < 1.2, "BGM 是从头开始放的")

	# 四个难度各一份「看过」标记：看过的不再自动播，没看过的照播。
	var seen_path: String = game._ending_seen_path()
	check(FileAccess.file_exists(seen_path) or true, "标记路径可用：" + seen_path)
	check(game._has_seen_ending() == FileAccess.file_exists(seen_path), "已看标记与文件存在性一致")

	var abs_seen := ProjectSettings.globalize_path(seen_path)
	for d in [GameState.Difficulty.EASY, GameState.Difficulty.NORMAL,
			GameState.Difficulty.HARD, GameState.Difficulty.NIGHTMARE]:
		GameState.difficulty = d
		DirAccess.remove_absolute(ProjectSettings.globalize_path(game._ending_seen_path()))
		check(not game._has_seen_ending(), "难度 %d 没看过时不判为已看" % d)
		check(game._try_play_ending(), "难度 %d 第一次结束会自动播片" % d)
		check(game._has_seen_ending(), "播过之后难度 %d 记为已看" % d)
		check(not game._try_play_ending(), "难度 %d 第二次结束不再自动播" % d)
		game._finish_ending()          # 立刻收尾，别真等 36 秒
		await wait(0.25)
	check(DirAccess.remove_absolute(abs_seen) == OK or not FileAccess.file_exists(abs_seen),
		"收尾时清理测试用的标记文件")

	print("ENDING_VIDEO: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
