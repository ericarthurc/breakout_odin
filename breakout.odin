package breakout

import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:math/rand"
import rl "vendor:raylib"

WINDOW_HEIGHT :: 960
WINDOW_WIDTH :: 960
SCREEN_SIZE :: 320
PADDLE_WIDTH :: 50
PADDLE_HEIGHT :: 6
PADDLE_POS_Y :: SCREEN_SIZE - 40
PADDLE_SPEED :: 300
BALL_SPEED :: 280
BALL_RADIUS :: 4
BALL_START_Y :: 160
REFLECTION_STRENGTH :: 0.95
NUM_BLOCKS_X :: 10
NUM_BLOCKS_Y :: 8
BLOCK_WIDTH :: 28
BLOCK_HEIGHT :: 10
BLOCK_MAX_STATES :: 6
POWERUP_FALL_SPEED :: 100

ASSET_FOLDER_PATH :: "assets/"

Block_Color :: enum {
	Yellow,
	Green,
	Orange,
	Red,
	Blue,
	Purple,
	None,
}

block_value_colors := [BLOCK_MAX_STATES]Block_Color{.None, .Blue, .Green, .Yellow, .Orange, .Red}

block_color_values := [Block_Color]rl.Color {
	.Yellow = {248, 255, 2, 255},
	.Green  = {0, 219, 1, 255},
	.Orange = {225, 130, 19, 255},
	.Red    = {242, 39, 33, 255},
	.Blue   = {0, 146, 192, 255},
	.Purple = {198, 10, 153, 255},
	.None   = rl.WHITE,
}

// TODO
// currently scoring off the block color
// will probably want to score off the value of the int in [][]
block_color_score := [Block_Color]int {
	.Red    = 6,
	.Orange = 5,
	.Yellow = 4,
	.Green  = 3,
	.Blue   = 2,
	.Purple = 1,
	.None   = 0,
}

Block_State :: struct {
	value:         int,
	is_special:    bool,
	special_count: int,
}

show_fps: bool
// blocks: [NUM_BLOCKS_X][NUM_BLOCKS_Y]bool
blocks: [NUM_BLOCKS_X][NUM_BLOCKS_Y]Block_State
paddle_pos_x: f32
ball_pos: rl.Vector2
ball_dir: rl.Vector2
started: bool
paused: bool
game_over: bool
score: int
accumulated_time: f32
previous_ball_pos: rl.Vector2
previous_paddle_pos_x: f32
special_blocks: [dynamic]rl.Rectangle

restart :: proc() {
	paddle_pos_x = SCREEN_SIZE / 2 - PADDLE_WIDTH / 2
	previous_paddle_pos_x = paddle_pos_x
	ball_pos = {SCREEN_SIZE / 2, BALL_START_Y}
	previous_ball_pos = ball_pos
	started = false
	paused = false
	game_over = false
	score = 0

	clear(&special_blocks)

	for x in 0 ..< NUM_BLOCKS_X {
		for y in 0 ..< NUM_BLOCKS_Y {
			blocks[x][y] = generate_blocks_randomly()
		}
	}
}

// TODO
generate_blocks_randomly :: proc() -> Block_State {

	block_value_temp := math.max(1, rand.int_max(BLOCK_MAX_STATES))

	is_special_temp := false
	special_count_temp := 0
	if rand.int_max(100) >= 99 {
		is_special_temp = true
		special_count_temp = rand.int_max(block_value_temp) + 1
	}

	return {
		value = block_value_temp,
		is_special = is_special_temp,
		special_count = special_count_temp,
	}

}

reflect :: proc(dir, normal: rl.Vector2) -> rl.Vector2 {
	new_direction := linalg.reflect(dir, linalg.normalize(normal))
	return linalg.normalize(new_direction)
}

calc_block_rect :: proc(x, y: int) -> rl.Rectangle {
	return {f32(20 + x * BLOCK_WIDTH), f32(40 + y * BLOCK_HEIGHT), BLOCK_WIDTH, BLOCK_HEIGHT}
}

block_exists :: proc(x, y: int) -> bool {
	if x < 0 || y < 0 || x >= NUM_BLOCKS_X || y >= NUM_BLOCKS_Y {
		return false
	}

	return blocks[x][y].value != 0
}

main :: proc() {
	// Initialization
	// ----------------------------------------------------------------------------------
	// set VSYNC on
	rl.SetConfigFlags({.VSYNC_HINT})
	// init window
	rl.InitWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "Breakout!")
	// init sound device
	rl.InitAudioDevice()
	// set upper framerate limit
	rl.SetTargetFPS(400)

	// load textures
	background_texture := rl.LoadTexture(ASSET_FOLDER_PATH + "background.png")
	ball_texture := rl.LoadTexture(ASSET_FOLDER_PATH + "ball.png")
	paddle_texture := rl.LoadTexture(ASSET_FOLDER_PATH + "paddle.png")

	// load audios
	hit_block_sound := rl.LoadSound(ASSET_FOLDER_PATH + "hit_block.wav")
	hit_paddle_sound := rl.LoadSound(ASSET_FOLDER_PATH + "hit_paddle.wav")
	game_over_sound := rl.LoadSound(ASSET_FOLDER_PATH + "game_over.wav")

	// load fonts
	// game_font := rl.LoadFontEx("cascadiacode.ttf", 32, nil, 1024)

	// set the inital game state
	restart()

	// Game loop
	// ----------------------------------------------------------------------------------
	for !rl.WindowShouldClose() {
		// Update 
		// ------------------------------------------------------------------------------
		DT :: 1.0 / 60.0 // 16 ms, 0.016 s

		if !started {

			if rl.IsKeyPressed(.R) {
				restart()
			}

			ball_pos = {
				SCREEN_SIZE / 2 + f32(math.cos(rl.GetTime()) * SCREEN_SIZE / 2.5),
				BALL_START_Y,
			}

			previous_ball_pos = ball_pos

			if rl.IsKeyPressed(.SPACE) {
				paddle_middle := rl.Vector2{paddle_pos_x + PADDLE_WIDTH / 2, PADDLE_POS_Y}
				ball_to_paddle := paddle_middle - ball_pos
				ball_dir = linalg.normalize0(ball_to_paddle)
				started = true
			}

		} else if game_over {
			if rl.IsKeyPressed(.SPACE) {
				restart()
			}
		} else if paused {
			accumulated_time = 0

			if rl.IsKeyPressed(.P) {
				paused = false
			}

			if rl.IsKeyPressed(.R) {
				restart()
			}

		} else {
			if rl.IsKeyPressed(.R) {restart()}

			// dt = rl.GetFrameTime()
			accumulated_time += rl.GetFrameTime()

			if rl.IsKeyPressed(.P) {paused = true}
		}

		if rl.IsKeyPressed(.F1) {show_fps = !show_fps}

		for accumulated_time >= DT {
			previous_ball_pos = ball_pos
			previous_paddle_pos_x = paddle_pos_x

			ball_pos += ball_dir * BALL_SPEED * DT

			if ball_pos.x + BALL_RADIUS > SCREEN_SIZE {
				ball_pos.x = SCREEN_SIZE - BALL_RADIUS
				ball_dir = reflect(ball_dir, {-1, 0})
			}

			if ball_pos.x - BALL_RADIUS < 0 {
				ball_pos.x = BALL_RADIUS
				ball_dir = reflect(ball_dir, {1, 0})
			}

			if ball_pos.y - BALL_RADIUS < 0 {
				ball_pos.y = BALL_RADIUS
				ball_dir = reflect(ball_dir, {0, 1})
			}

			if !game_over && ball_pos.y > SCREEN_SIZE + BALL_RADIUS * 6 {
				game_over = true
				rl.PlaySound(game_over_sound)
			}

			paddle_mov_velocity: f32

			if rl.IsKeyDown(.LEFT) {
				paddle_mov_velocity -= PADDLE_SPEED
			}

			if rl.IsKeyDown(.RIGHT) {
				paddle_mov_velocity += PADDLE_SPEED
			}

			paddle_pos_x += paddle_mov_velocity * DT
			paddle_pos_x = clamp(paddle_pos_x, 0, SCREEN_SIZE - PADDLE_WIDTH)

			paddle_rect := rl.Rectangle{paddle_pos_x, PADDLE_POS_Y, PADDLE_WIDTH, PADDLE_HEIGHT}


			// check for special blocks and start moving them downward
			for &v, i in special_blocks {
				if rl.CheckCollisionRecs(v, paddle_rect) {
					fmt.println("POWER UP HIT PADDLE")
					special_blocks[i] = pop(&special_blocks)
					break
				}


				v.y += POWERUP_FALL_SPEED * DT

				if !game_over && v.y > SCREEN_SIZE {
					special_blocks[i] = pop(&special_blocks)
				}
			}

			// check for collision between the ball and the paddle
			if rl.CheckCollisionCircleRec(ball_pos, BALL_RADIUS, paddle_rect) {
				if previous_ball_pos.y > 0 {
					offset := ball_pos.x - (paddle_rect.x + paddle_rect.width / 2)
					normalized_offset := offset / (paddle_rect.width / 2)
					ball_dir = linalg.normalize0(
						rl.Vector2{normalized_offset * REFLECTION_STRENGTH, -1},
					)
					ball_pos.y = paddle_rect.y - BALL_RADIUS

					rl.PlaySound(hit_paddle_sound)
				}
			}

			// check for collision with the ball and blocks
			block_x_loop: for x in 0 ..< NUM_BLOCKS_X {
				for y in 0 ..< NUM_BLOCKS_Y {
					if blocks[x][y].value == 0 {
						continue
					}

					block_rect := calc_block_rect(x, y)

					if rl.CheckCollisionCircleRec(ball_pos, BALL_RADIUS, block_rect) {
						collision_normal: rl.Vector2

						if previous_ball_pos.y < block_rect.y {
							collision_normal += {0, -1}
						}

						if previous_ball_pos.y > block_rect.y + block_rect.height {
							collision_normal += {0, 1}
						}

						if previous_ball_pos.x < block_rect.x {
							collision_normal += {-1, 0}
						}

						if previous_ball_pos.x > block_rect.x + block_rect.width {
							collision_normal += {1, 0}
						}

						if block_exists(x + int(collision_normal.x), y) {
							collision_normal.x = 0
						}

						if block_exists(x, y + int(collision_normal.y)) {
							collision_normal.y = 0
						}

						if collision_normal != 0 {
							ball_dir = reflect(ball_dir, collision_normal)
						}

						if blocks[x][y].value == 5 {
							append(&special_blocks, calc_block_rect(x, y))
						}

						blocks[x][y].value -= 1
						row_color := block_value_colors[blocks[x][y].value]
						score += block_color_score[row_color]
						rl.SetSoundPitch(hit_block_sound, rand.float32_range(0.8, 1.2))
						rl.PlaySound(hit_block_sound)
						break block_x_loop
					}
				}
			}

			accumulated_time -= DT
		}

		blend := accumulated_time / DT
		ball_render_pos := math.lerp(previous_ball_pos, ball_pos, blend)
		paddle_render_pos_x := math.lerp(previous_paddle_pos_x, paddle_pos_x, blend)


		// Draw
		// ------------------------------------------------------------------------------
		rl.BeginDrawing()
		// rl.ClearBackground({150, 190, 220, 255})
		rl.ClearBackground({0, 0, 0, 255})
		rl.DrawTexture(background_texture, 0, 0, rl.WHITE)

		camera := rl.Camera2D {
			zoom = f32(rl.GetScreenHeight() / SCREEN_SIZE),
		}

		rl.BeginMode2D(camera)

		// rl.DrawRectangleRec(paddle_rect, {50, 150, 90, 255})
		rl.DrawTextureV(paddle_texture, {paddle_render_pos_x, PADDLE_POS_Y}, rl.WHITE)


		// rl.DrawCircleV(ball_pos, BALL_RADIUS, {200, 90, 20, 255})
		rl.DrawTextureV(ball_texture, ball_render_pos - {BALL_RADIUS, BALL_RADIUS}, rl.WHITE)


		for x in 0 ..< NUM_BLOCKS_X {
			for y in 0 ..< NUM_BLOCKS_Y {
				if blocks[x][y].value == 0 {
					continue
				}

				block_rect := calc_block_rect(x, y)

				top_left := rl.Vector2{block_rect.x, block_rect.y}

				top_right := rl.Vector2{block_rect.x + block_rect.width, block_rect.y}

				bottom_left := rl.Vector2{block_rect.x, block_rect.height + block_rect.y}

				bottom_right := rl.Vector2 {
					block_rect.x + block_rect.width,
					block_rect.height + block_rect.y,
				}

				// rl.DrawRectangleRec(block_rect, block_color_values[row_colors[y]])
				rl.DrawRectangleRec(
					block_rect,
					block_color_values[block_value_colors[blocks[x][y].value]],
				)
				rl.DrawLineEx(top_left, top_right, 1, {0, 0, 0, 255})
				rl.DrawLineEx(top_left, bottom_left, 1, {0, 0, 0, 255})
				rl.DrawLineEx(top_right, bottom_right, 1, {0, 0, 0, 255})
				rl.DrawLineEx(bottom_left, bottom_right, 1, {0, 0, 0, 255})

			}
		}

		for v, i in special_blocks {
			rl.DrawRectangleRec(v, rl.BEIGE)
		}

		if show_fps {
			fps_text := fmt.ctprintf("FPS: %v", rl.GetFPS())
			rl.DrawText(fps_text, 5, 0, 0, rl.WHITE)
			// rl.DrawTextEx(game_font, fps_text, 5, 5, 0, rl.WHITE)
		}


		if paused {
			start_text := fmt.ctprint("PAUSED")
			start_text_width := rl.MeasureText(start_text, 15)
			rl.DrawText(
				start_text,
				SCREEN_SIZE / 2 - start_text_width / 2,
				BALL_START_Y - 30,
				15,
				rl.WHITE,
			)
		}

		score_text := fmt.ctprintf("Score: %v", score)
		rl.DrawText(score_text, 5, 10, 1, rl.WHITE)

		if !started {
			start_text := fmt.ctprint("Start: SPACE")
			start_text_width := rl.MeasureText(start_text, 15)
			rl.DrawText(
				start_text,
				SCREEN_SIZE / 2 - start_text_width / 2,
				BALL_START_Y - 30,
				15,
				rl.WHITE,
			)
		}

		if game_over {
			game_over_text := fmt.ctprintf("Score: %v. Reset: SPACE", score)
			game_over_text_width := rl.MeasureText(game_over_text, 15)
			rl.DrawText(
				game_over_text,
				SCREEN_SIZE / 2 - game_over_text_width / 2,
				BALL_START_Y - 30,
				15,
				rl.WHITE,
			)
		}

		rl.EndMode2D()
		rl.EndDrawing()

		free_all(context.temp_allocator)
	}
	// De-Initialization
	// ----------------------------------------------------------------------------------

	delete(special_blocks)

	// rl.UnloadFont(game_font)
	rl.CloseAudioDevice()
	rl.CloseWindow()
}
