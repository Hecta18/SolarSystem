const std = @import("std");
const rl = @import("raylib");
const m = @import("math.zig");
const scene_mod = @import("scene.zig");
const render = @import("render.zig");
const V3 = m.V3;

const camera_height: f32 = 2.2;
const collision_margin: f32 = 1.5;
const min_zoom: f32 = 0.8;
const max_zoom: f32 = 180.0;
const yaw_speed: f32 = 1.6;

pub fn main(init: std.process.Init) !void {
    var args = try init.minimal.args.iterateAllocator(init.gpa);
    defer args.deinit();
    _ = args.next();
    const flag = args.next();
    var shot_path: ?[:0]const u8 = null;
    var shot_focus: usize = scene_mod.sun_index;
    var shot_distance: f32 = 0.0;
    var bench = false;
    if (flag) |f| {
        if (std.mem.eql(u8, f, "--shot")) {
            shot_path = args.next();
            if (args.next()) |focus_arg| shot_focus = std.fmt.parseInt(usize, focus_arg, 10) catch scene_mod.sun_index;
            if (args.next()) |distance_arg| shot_distance = std.fmt.parseFloat(f32, distance_arg) catch 0.0;
        } else if (std.mem.eql(u8, f, "--bench")) {
            bench = true;
            if (args.next()) |focus_arg| shot_focus = std.fmt.parseInt(usize, focus_arg, 10) catch scene_mod.sun_index;
        }
    }

    const allocator = std.heap.page_allocator;
    const pixel_count: usize = @intCast(render.render_w * render.render_h);
    const pixels = try allocator.alloc(u32, pixel_count);
    defer allocator.free(pixels);
    const depth = try allocator.alloc(f32, pixel_count);
    defer allocator.free(depth);

    var frame = render.Frame{ .pixels = pixels, .depth = depth };

    var scene: scene_mod.Scene = undefined;
    scene.init();

    const skybox = try allocator.create(render.Skybox);
    defer allocator.destroy(skybox);
    skybox.init();

    var lods = try render.LodSet.init(allocator);
    defer lods.deinit(allocator);

    if (bench) {
        shot_focus = @min(shot_focus, scene_mod.body_count - 1);
        const target = scene.focusPos(shot_focus);
        const shot_yaw = if (shot_focus == scene_mod.sun_index) 0.7 else sunlitYaw(&scene, shot_focus);
        const bench_distance = if (shot_focus == scene_mod.sun_index) 9.0 else @max(4.0, scene.focusRadius(shot_focus) * 2.5);
        const camera = render.makeCamera(desiredPosition(&scene, shot_focus, shot_yaw, bench_distance), target);
        const frames: usize = 600;
        for (0..frames) |_| {
            scene.update(1.0 / 60.0);
            render.render(&frame, skybox, &scene, &camera, &lods);
        }
        std.debug.print("Benchmark listo: {d} frames renderizados\n", .{frames});
        return;
    }

    if (shot_path) |path| {
        shot_focus = @min(shot_focus, scene_mod.body_count - 1);
        const target = scene.focusPos(shot_focus);
        const shot_yaw = if (shot_focus == scene_mod.sun_index) 0.7 else sunlitYaw(&scene, shot_focus);
        const view_distance = if (shot_distance > 0.0) shot_distance else defaultDistance(&scene, shot_focus);
        const camera = render.makeCamera(
            desiredPosition(&scene, shot_focus, shot_yaw, view_distance),
            target,
        );
        render.render(&frame, skybox, &scene, &camera, &lods);
        const shot_image = rl.Image{
            .data = @ptrCast(pixels.ptr),
            .width = render.render_w,
            .height = render.render_h,
            .mipmaps = 1,
            .format = .uncompressed_r8g8b8a8,
        };
        if (!rl.exportImage(shot_image, path)) return error.ExportFailed;
        std.debug.print("Captura escrita en {s}\n", .{path});
        return;
    }

    rl.setTraceLogLevel(.warning);
    rl.initWindow(render.window_w, render.window_h, "Sistema Solar - Renderer por Software");
    defer rl.closeWindow();

    if (!rl.isWindowReady()) {
        std.debug.print("No se pudo abrir la ventana. Se necesita un servidor grafico (WSLg/X11).\n", .{});
        return error.NoWindow;
    }

    rl.setTargetFPS(60);

    const image = rl.Image{
        .data = @ptrCast(pixels.ptr),
        .width = render.render_w,
        .height = render.render_h,
        .mipmaps = 1,
        .format = .uncompressed_r8g8b8a8,
    };
    const texture = try rl.loadTextureFromImage(image);
    defer rl.unloadTexture(texture);
    rl.setTextureFilter(texture, .bilinear);

    var focus: usize = scene_mod.sun_index;
    var yaw: f32 = 0.7;
    var distance: f32 = defaultDistance(&scene, focus);
    var cam_pos = desiredPosition(&scene, focus, yaw, distance);
    var transition_start = cam_pos;
    var transition_t: f32 = 1.0;
    var title_timer: f32 = 0.0;
    var title_buf: [160]u8 = undefined;

    while (!rl.windowShouldClose()) {
        const dt = rl.getFrameTime();
        scene.update(dt);

        if (rl.isKeyDown(.a)) yaw += yaw_speed * dt;
        if (rl.isKeyDown(.d)) yaw -= yaw_speed * dt;
        if (rl.isKeyDown(.w)) distance -= 24.0 * dt;
        if (rl.isKeyDown(.s)) distance += 24.0 * dt;

        if (rl.isMouseButtonDown(.left)) {
            const delta = rl.getMouseDelta();
            yaw -= delta.x * 0.006;
        }

        const wheel = rl.getMouseWheelMove();
        if (wheel != 0.0) distance *= 1.0 - wheel * 0.12;

        var next_focus = focus;
        if (rl.isKeyPressed(.one)) next_focus = 1;
        if (rl.isKeyPressed(.two)) next_focus = 2;
        if (rl.isKeyPressed(.three)) next_focus = 3;
        if (rl.isKeyPressed(.four)) next_focus = 4;
        if (rl.isKeyPressed(.five)) next_focus = 5;
        if (rl.isKeyPressed(.r)) next_focus = scene_mod.sun_index;

        if (next_focus != focus) {
            focus = next_focus;
            distance = defaultDistance(&scene, focus);
            if (focus != scene_mod.sun_index) yaw = sunlitYaw(&scene, focus);
            transition_start = cam_pos;
            transition_t = 0.0;
        }

        distance = std.math.clamp(distance, min_zoom, max_zoom);

        const target = scene.focusPos(focus);
        const desired = desiredPosition(&scene, focus, yaw, distance);

        if (transition_t < 1.0) {
            transition_t = @min(1.0, transition_t + dt * 2.2);
            cam_pos = m.lerp(transition_start, desired, m.smoothstep(transition_t));
        } else {
            cam_pos = desired;
        }

        cam_pos = resolveCollisions(&scene, cam_pos);
        const camera = render.makeCamera(cam_pos, target);

        render.render(&frame, skybox, &scene, &camera, &lods);

        rl.updateTexture(texture, pixels.ptr);
        rl.beginDrawing();
        rl.clearBackground(.black);

        // Raylib no expone una API publica para presentar un framebuffer de CPU
        // ya renderizado. UpdateTexture + DrawTexture se usan exclusivamente
        // para copiar la imagen terminada a la ventana; toda la escena se
        // rasteriza y sombrea a mano, pixel por pixel.
        rl.drawTexturePro(
            texture,
            .{ .x = 0, .y = 0, .width = @floatFromInt(render.render_w), .height = @floatFromInt(render.render_h) },
            .{ .x = 0, .y = 0, .width = @floatFromInt(render.window_w), .height = @floatFromInt(render.window_h) },
            .{ .x = 0, .y = 0 },
            0,
            .white,
        );
        rl.endDrawing();

        title_timer += dt;
        if (title_timer > 0.5) {
            title_timer = 0.0;
            const title = std.fmt.bufPrintZ(
                &title_buf,
                "Sistema Solar | {s} | {d} FPS | 1-5 viajar  A/D orbitar  rueda zoom",
                .{ scene.bodyName(focus), rl.getFPS() },
            ) catch "Sistema Solar";
            rl.setWindowTitle(title);
        }
    }
}

fn defaultDistance(scene: *const scene_mod.Scene, focus: usize) f32 {
    if (focus == scene_mod.sun_index) return 85.0;
    return @max(6.0, scene.focusRadius(focus) * 7.0 + 4.0);
}

/// Coloca la camara del lado iluminado del planeta al seleccionarlo, con un
/// desfase para que no quede exactamente entre el Sol y el cuerpo.
fn sunlitYaw(scene: *const scene_mod.Scene, focus: usize) f32 {
    const angle = scene.bodies[focus].angle;
    return std.math.atan2(-@cos(angle), -@sin(angle)) + 0.6;
}

fn desiredPosition(scene: *const scene_mod.Scene, focus: usize, yaw: f32, distance: f32) V3 {
    const center = scene.focusPos(focus);
    return center + m.v3(@sin(yaw) * distance, camera_height, @cos(yaw) * distance);
}

/// Colisiones solo en el plano XZ para conservar el movimiento en 2 ejes.
/// La altura de la camara queda fija; cuando su Y cae dentro de la esfera de
/// seguridad de un cuerpo, se calcula el radio horizontal minimo y se empuja
/// la camara hacia fuera.
fn resolveCollisions(scene: *const scene_mod.Scene, pos: V3) V3 {
    var result = pos;
    for (scene.bodies) |body| {
        const dy = result[1] - body.pos[1];
        const r = body.radius + collision_margin;
        if (@abs(dy) >= r) continue;

        const min_horizontal = @sqrt(r * r - dy * dy);
        const dx = result[0] - body.pos[0];
        const dz = result[2] - body.pos[2];
        const d = @sqrt(dx * dx + dz * dz);
        if (d >= min_horizontal) continue;

        if (d > 1e-5) {
            result[0] = body.pos[0] + dx / d * min_horizontal;
            result[2] = body.pos[2] + dz / d * min_horizontal;
        } else {
            result[0] = body.pos[0] + min_horizontal;
            result[2] = body.pos[2];
        }
    }
    return result;
}
