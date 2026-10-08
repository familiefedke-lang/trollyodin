package main

import "core:math"
import rl "vendor:raylib"
import "vendor:raylib/rlgl"

SCREEN_W :: 1280
SCREEN_H :: 800
PANEL_W :: 260

Shape :: enum {
	Sphere,
	Cube,
	Triangle,
}

State :: struct {
	shape:       Shape,
	yaw:         f32, // degrees
	pitch:       f32, // degrees
	dist:        f32,
	fov:         f32, // degrees
	dolly_k:     f32, // dist * tan(fov/2), kept constant when dolly zoom locked
	dolly_lock:  bool,
	ortho:       bool,
	wireframe:   bool,
	show_horizon: bool,
	show_grid:   bool,
	distortion:  f32,
	obj_rot:     [3]f32, // degrees x, y, z
}

default_state :: proc() -> State {
	s := State {
		shape        = .Cube,
		yaw          = 35,
		pitch        = 15,
		dist         = 8,
		fov          = 45,
		show_horizon = true,
		show_grid    = true,
		wireframe    = true,
	}
	s.dolly_k = s.dist * math.tan(s.fov * math.RAD_PER_DEG * 0.5)
	return s
}

FRAG :: `#version 330
in vec2 fragTexCoord;
in vec4 fragColor;
out vec4 finalColor;
uniform sampler2D texture0;
uniform float distortion;
void main() {
	vec2 uv = fragTexCoord * 2.0 - 1.0;
	float r2 = dot(uv, uv);
	vec2 d = uv * (1.0 + distortion * r2);
	// keep the picture filled for barrel distortion
	if (distortion > 0.0) { d /= (1.0 + distortion); }
	vec2 t = d * 0.5 + 0.5;
	if (t.x < 0.0 || t.x > 1.0 || t.y < 0.0 || t.y > 1.0) {
		finalColor = vec4(0.1, 0.1, 0.12, 1.0);
	} else {
		finalColor = texture(texture0, t) * fragColor;
	}
}`

draw_tetra :: proc(c: rl.Color, wire: bool) {
	h: f32 = 1.5
	r: f32 = 1.5
	a := rl.Vector3{0, h, 0}
	b := rl.Vector3{r, -h * 0.5, 0}
	cc := rl.Vector3{-r * 0.5, -h * 0.5, r * 0.866}
	d := rl.Vector3{-r * 0.5, -h * 0.5, -r * 0.866}
	faces := [4][3]rl.Vector3{{a, b, cc}, {a, cc, d}, {a, d, b}, {b, d, cc}}
	for f in faces {
		rl.DrawTriangle3D(f[0], f[1], f[2], c)
		rl.DrawTriangle3D(f[0], f[2], f[1], c)
		if wire {
			rl.DrawLine3D(f[0], f[1], rl.BLACK)
			rl.DrawLine3D(f[1], f[2], rl.BLACK)
			rl.DrawLine3D(f[2], f[0], rl.BLACK)
		}
	}
}

draw_shape :: proc(s: State) {
	rlgl.PushMatrix()
	rlgl.Rotatef(s.obj_rot.x, 1, 0, 0)
	rlgl.Rotatef(s.obj_rot.y, 0, 1, 0)
	rlgl.Rotatef(s.obj_rot.z, 0, 0, 1)
	fill := rl.Color{200, 120, 90, 255}
	switch s.shape {
	case .Sphere:
		rl.DrawSphere({0, 0, 0}, 1.5, fill)
		if s.wireframe {
			rl.DrawSphereWires({0, 0, 0}, 1.52, 16, 24, rl.BLACK)
		}
	case .Cube:
		rl.DrawCube({0, 0, 0}, 2.5, 2.5, 2.5, fill)
		if s.wireframe {
			rl.DrawCubeWires({0, 0, 0}, 2.5, 2.5, 2.5, rl.BLACK)
		}
	case .Triangle:
		draw_tetra(fill, s.wireframe)
	}
	rlgl.PopMatrix()
}

make_camera :: proc(s: State) -> rl.Camera3D {
	yaw := s.yaw * math.RAD_PER_DEG
	pitch := s.pitch * math.RAD_PER_DEG
	pos := rl.Vector3 {
		s.dist * math.cos(pitch) * math.sin(yaw),
		s.dist * math.sin(pitch),
		s.dist * math.cos(pitch) * math.cos(yaw),
	}
	cam := rl.Camera3D {
		position   = pos,
		target     = {0, 0, 0},
		up         = {0, 1, 0},
		fovy       = s.fov,
		projection = .PERSPECTIVE,
	}
	if s.ortho {
		// orthographic fovy is the visible world height
		cam.projection = .ORTHOGRAPHIC
		cam.fovy = 2 * s.dolly_k
	}
	return cam
}

// Screen Y of the horizon (eye level). Returns false if not visible/valid.
horizon_y :: proc(cam: rl.Camera3D, w, h: i32) -> (f32, bool) {
	if cam.projection == .ORTHOGRAPHIC {
		return 0, false
	}
	fwd := rl.Vector3Normalize(cam.target - cam.position)
	flat := rl.Vector3{fwd.x, 0, fwd.z}
	if rl.Vector3Length(flat) < 1e-4 {
		return 0, false // looking straight up/down
	}
	flat = rl.Vector3Normalize(flat)
	p := cam.position + flat * 10000
	sp := rl.GetWorldToScreen(p, cam)
	return sp.y, true
}

main :: proc() {
	rl.SetConfigFlags({.MSAA_4X_HINT})
	rl.InitWindow(SCREEN_W, SCREEN_H, "trollyodin - perspective study")
	defer rl.CloseWindow()
	rl.SetTargetFPS(60)

	view_w: i32 = SCREEN_W - PANEL_W
	view_h: i32 = SCREEN_H
	target := rl.LoadRenderTexture(view_w, view_h)
	defer rl.UnloadRenderTexture(target)
	shader := rl.LoadShaderFromMemory(nil, FRAG)
	defer rl.UnloadShader(shader)
	dist_loc := rl.GetShaderLocation(shader, "distortion")

	s := default_state()

	for !rl.WindowShouldClose() {
		mouse := rl.GetMousePosition()
		in_view := mouse.x > PANEL_W

		if in_view {
			if rl.IsMouseButtonDown(.LEFT) {
				d := rl.GetMouseDelta()
				s.yaw -= d.x * 0.4
				s.pitch = clamp(s.pitch + d.y * 0.4, -89, 89)
			}
			if rl.IsMouseButtonDown(.RIGHT) {
				d := rl.GetMouseDelta()
				s.obj_rot.y += d.x * 0.4
				s.obj_rot.x += d.y * 0.4
			}
			wheel := rl.GetMouseWheelMove()
			if wheel != 0 && !s.dolly_lock {
				s.dist = clamp(s.dist * (1 - wheel * 0.08), 2.5, 60)
			}
		}
		if rl.IsKeyPressed(.R) {
			s = default_state()
		}

		// dolly zoom: distance follows FOV to keep subject size
		half := clamp(s.fov, 5, 120) * math.RAD_PER_DEG * 0.5
		if s.dolly_lock {
			s.dist = s.dolly_k / math.tan(half)
		} else {
			s.dolly_k = s.dist * math.tan(half)
		}

		cam := make_camera(s)

		rl.BeginTextureMode(target)
		rl.ClearBackground({235, 235, 240, 255})
		rl.BeginMode3D(cam)
		if s.show_grid {
			rl.DrawGrid(40, 1)
		}
		draw_shape(s)
		rl.EndMode3D()
		rl.EndTextureMode()

		rl.BeginDrawing()
		rl.ClearBackground(rl.DARKGRAY)

		dist_val := s.distortion
		rl.SetShaderValue(shader, dist_loc, &dist_val, .FLOAT)
		rl.BeginShaderMode(shader)
		rl.DrawTextureRec(
			target.texture,
			{0, 0, f32(view_w), -f32(view_h)},
			{PANEL_W, 0},
			rl.WHITE,
		)
		rl.EndShaderMode()

		if s.show_horizon {
			if hy, ok := horizon_y(cam, view_w, view_h); ok {
				y := i32(hy)
				if y >= 0 && y < view_h {
					rl.DrawLine(PANEL_W, y, SCREEN_W, y, rl.RED)
					rl.DrawText("horizon", SCREEN_W - 80, y - 16, 14, rl.RED)
				}
			}
		}

		draw_gui(&s)
		rl.EndDrawing()
	}
}

draw_gui :: proc(s: ^State) {
	rl.DrawRectangle(0, 0, PANEL_W, SCREEN_H, {245, 245, 245, 255})
	rl.GuiLabel({10, 10, 240, 20}, "Form")
	if rl.GuiButton({10, 32, 75, 28}, "Sphere") != 0 { s.shape = .Sphere }
	if rl.GuiButton({92, 32, 75, 28}, "Cube") != 0 { s.shape = .Cube }
	if rl.GuiButton({174, 32, 75, 28}, "Triangle") != 0 { s.shape = .Triangle }

	rl.GuiLabel({10, 75, 240, 20}, "Camera")
	rl.GuiSliderBar({70, 98, 140, 20}, "FOV", rl.TextFormat("%.0f", s.fov), &s.fov, 10, 120)
	if s.dolly_lock {
		rl.GuiLabel({10, 124, 240, 20}, rl.TextFormat("Distance %.1f (locked)", s.dist))
	} else {
		rl.GuiSliderBar({70, 124, 140, 20}, "Dist", rl.TextFormat("%.1f", s.dist), &s.dist, 2.5, 60)
	}
	rl.GuiSliderBar({70, 150, 140, 20}, "Yaw", rl.TextFormat("%.0f", s.yaw), &s.yaw, -180, 180)
	rl.GuiSliderBar({70, 176, 140, 20}, "Pitch", rl.TextFormat("%.0f", s.pitch), &s.pitch, -89, 89)
	rl.GuiSliderBar({70, 202, 140, 20}, "Distort", rl.TextFormat("%.2f", s.distortion), &s.distortion, -0.6, 0.8)

	rl.GuiCheckBox({10, 235, 20, 20}, "Dolly zoom (keep size)", &s.dolly_lock)
	rl.GuiCheckBox({10, 262, 20, 20}, "Orthographic", &s.ortho)
	rl.GuiCheckBox({10, 289, 20, 20}, "Horizon line", &s.show_horizon)
	rl.GuiCheckBox({10, 316, 20, 20}, "Ground grid", &s.show_grid)
	rl.GuiCheckBox({10, 343, 20, 20}, "Wireframe", &s.wireframe)

	rl.GuiLabel({10, 375, 240, 20}, "Object rotation")
	rl.GuiSliderBar({70, 398, 140, 20}, "X", rl.TextFormat("%.0f", s.obj_rot.x), &s.obj_rot.x, -180, 180)
	rl.GuiSliderBar({70, 424, 140, 20}, "Y", rl.TextFormat("%.0f", s.obj_rot.y), &s.obj_rot.y, -180, 180)
	rl.GuiSliderBar({70, 450, 140, 20}, "Z", rl.TextFormat("%.0f", s.obj_rot.z), &s.obj_rot.z, -180, 180)

	if rl.GuiButton({10, 490, 240, 28}, "Reset (R)") != 0 {
		s^ = default_state()
	}
	rl.GuiLabel({10, 540, 240, 60}, "LMB drag: orbit\nRMB drag: rotate form\nWheel: dolly")
}
