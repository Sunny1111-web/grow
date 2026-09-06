extends SceneTree

const FFMPEG: String = "C:/Users/admin/AppData/Local/Microsoft/WinGet/Packages/Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe/ffmpeg-9.0.1-full_build/bin/ffmpeg.exe"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	game.save_root = "res://test-results/probe-process/saves"
	root.add_child(game)
	await process_frame
	game.start_new_game("apartment")
	await process_frame
	DisplayServer.window_set_position(Vector2i(0, 0))
	await process_frame
	await process_frame
	var origin: Vector2i = DisplayServer.window_get_position()
	var size: Vector2i = DisplayServer.window_get_size()
	print("origin=", origin, " size=", size, " screen=", DisplayServer.screen_get_size())
	DisplayServer.window_move_to_foreground()
	var args: PackedStringArray = [
		"-y", "-f", "gdigrab", "-framerate", "30",
		"-offset_x", str(origin.x), "-offset_y", str(origin.y),
		"-video_size", str(size.x), str(size.y), "-i", "desktop",
		"-t", "4", "-c:v", "libx264", "-preset", "veryfast", "-crf", "20",
		"-pix_fmt", "yuv420p", "D:/game/GameDev/Projects/Grow/build/gdigrab-probe2.mp4"]
	print("args=", " ".join(args))
	var pid: int = OS.create_process(FFMPEG, args)
	print("pid=", pid)
	await create_timer(8.0).timeout
	print("mp4_exists=", FileAccess.file_exists("D:/game/GameDev/Projects/Grow/build/gdigrab-probe2.mp4"))
	quit(0)
