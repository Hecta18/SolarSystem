const std = @import("std");
const m = @import("math.zig");
const scene_mod = @import("scene.zig");
const Scene = scene_mod.Scene;
const Body = scene_mod.Body;
const V3 = m.V3;

pub const render_w: i32 = 480;
pub const render_h: i32 = 270;
pub const window_w: i32 = 1280;
pub const window_h: i32 = 720;

const fov: f32 = 60.0 * std.math.pi / 180.0;
const tan_half: f32 = @tan(fov * 0.5);
const aspect: f32 = @as(f32, @floatFromInt(render_w)) / @as(f32, @floatFromInt(render_h));
const near_plane: f32 = 0.08;
const world_up = m.v3(0.0, 1.0, 0.0);

pub const Frame = struct {
    pixels: []u32,
    depth: []f32,
};

pub const Camera = struct {
    pos: V3,
    forward: V3,
    right: V3,
    up: V3,
};

pub fn makeCamera(pos: V3, target: V3) Camera {
    const forward = m.normalize(target - pos);
    var right = m.normalize(m.cross(forward, world_up));
    if (m.length(right) < 1e-4) right = m.v3(1, 0, 0);
    const up = m.normalize(m.cross(right, forward));
    return .{ .pos = pos, .forward = forward, .right = right, .up = up };
}

const Vertex = struct {
    pos: V3,
    uv: [2]f32,
};

const Mesh = struct {
    verts: []Vertex,
    indices: []u32,
};

pub const LodSet = struct {
    meshes: [3]Mesh,

    pub fn init(allocator: std.mem.Allocator) !LodSet {
        return .{
            .meshes = .{
                try buildSphere(allocator, 12, 6),
                try buildSphere(allocator, 24, 12),
                try buildSphere(allocator, 48, 24),
            },
        };
    }

    pub fn deinit(self: *LodSet, allocator: std.mem.Allocator) void {
        for (&self.meshes) |*mesh| {
            allocator.free(mesh.verts);
            allocator.free(mesh.indices);
        }
    }
};

fn buildSphere(allocator: std.mem.Allocator, sectors: usize, stacks: usize) !Mesh {
    const vcount = (sectors + 1) * (stacks + 1);
    const icount = sectors * stacks * 6;
    const verts = try allocator.alloc(Vertex, vcount);
    const indices = try allocator.alloc(u32, icount);

    var y: usize = 0;
    while (y <= stacks) : (y += 1) {
        const v = @as(f32, @floatFromInt(y)) / @as(f32, @floatFromInt(stacks));
        const phi = v * std.math.pi;
        const dy = @cos(phi);
        const ring = @sin(phi);

        var x: usize = 0;
        while (x <= sectors) : (x += 1) {
            const u = @as(f32, @floatFromInt(x)) / @as(f32, @floatFromInt(sectors));
            const theta = u * 2.0 * std.math.pi;
            verts[y * (sectors + 1) + x] = .{
                .pos = m.v3(ring * @cos(theta), dy, ring * @sin(theta)),
                .uv = .{ u, v },
            };
        }
    }

    var i: usize = 0;
    var x: usize = 0;
    y = 0;
    while (y < stacks) : (y += 1) {
        x = 0;
        while (x < sectors) : (x += 1) {
            const a0 = y * (sectors + 1) + x;
            const a1 = a0 + 1;
            const a2 = a0 + sectors + 1;
            const a3 = a2 + 1;
            indices[i] = @intCast(a0);
            indices[i + 1] = @intCast(a1);
            indices[i + 2] = @intCast(a2);
            indices[i + 3] = @intCast(a1);
            indices[i + 4] = @intCast(a3);
            indices[i + 5] = @intCast(a2);
            i += 6;
        }
    }

    return .{ .verts = verts, .indices = indices };
}

const sky_size = 512;
const sky_pixels = sky_size * sky_size;

pub const Skybox = struct {
    faces: [6][sky_pixels]u32,

    pub fn init(self: *Skybox) void {
        const base = m.colorToU32(m.v3(0.004, 0.007, 0.018));
        for (&self.faces) |*face| {
            @memset(face, base);
        }

        var rng: u32 = 0x9e3779b9;
        var i: usize = 0;
        while (i < 2200) : (i += 1) {
            const z = nextRandom(&rng) * 2.0 - 1.0;
            const a = nextRandom(&rng) * 2.0 * std.math.pi;
            const r = @sqrt(@max(0.0, 1.0 - z * z));
            const dir = m.v3(r * @cos(a), z, r * @sin(a));
            const bright = 0.30 + std.math.pow(f32, nextRandom(&rng), 2.5) * 0.95;
            const warm = nextRandom(&rng);
            const color = m.mixColor(
                m.v3(0.62, 0.78, 1.0),
                m.v3(1.0, 0.86, 0.68),
                warm,
            ) * m.splat(bright);
            placeStar(self, dir, color);
        }

        // Banda de polvo estelar: estrellas más tenues agrupadas en un plano.
        const band = m.normalize(m.v3(0.35, 0.88, 0.32));
        i = 0;
        while (i < 650) : (i += 1) {
            const z = nextRandom(&rng) * 2.0 - 1.0;
            const a = nextRandom(&rng) * 2.0 * std.math.pi;
            const r = @sqrt(@max(0.0, 1.0 - z * z));
            const dir = m.v3(r * @cos(a), z, r * @sin(a));
            if (@abs(m.dot(dir, band)) > 0.14) continue;
            const bright = 0.12 + nextRandom(&rng) * 0.35;
            placeStar(self, dir, m.v3(0.55, 0.68, 0.95) * m.splat(bright));
        }
    }

    pub inline fn sample(self: *const Skybox, dir: V3) u32 {
        const fuv = dirToFaceUV(dir);
        const u = std.math.clamp(fuv.u * 0.5 + 0.5, 0.0, 0.9999);
        const v = std.math.clamp(fuv.v * 0.5 + 0.5, 0.0, 0.9999);
        const x: usize = @intFromFloat(u * @as(f32, sky_size));
        const y: usize = @intFromFloat(v * @as(f32, sky_size));
        return self.faces[fuv.face][y * sky_size + @min(x, sky_size - 1)];
    }
};

fn placeStar(sky: *Skybox, dir: V3, color: V3) void {
    const fuv = dirToFaceUV(dir);
    const u = std.math.clamp(fuv.u * 0.5 + 0.5, 0.0, 0.9999);
    const v = std.math.clamp(fuv.v * 0.5 + 0.5, 0.0, 0.9999);
    const x: usize = @intFromFloat(u * @as(f32, sky_size));
    const y: usize = @intFromFloat(v * @as(f32, sky_size));
    const idx = y * sky_size + @min(x, sky_size - 1);
    const value = m.colorToU32(color);
    if (brightness(value) > brightness(sky.faces[fuv.face][idx])) {
        sky.faces[fuv.face][idx] = value;
    }
}

fn brightness(c: u32) u32 {
    return (c & 0xff) + ((c >> 8) & 0xff) + ((c >> 16) & 0xff);
}

const FaceUV = struct {
    face: usize,
    u: f32,
    v: f32,
};

fn dirToFaceUV(dir: V3) FaceUV {
    const ax = @abs(dir[0]);
    const ay = @abs(dir[1]);
    const az = @abs(dir[2]);

    if (ax >= ay and ax >= az) {
        const inv = 1.0 / @max(ax, 1e-8);
        if (dir[0] >= 0.0) return .{ .face = 0, .u = -dir[2] * inv, .v = dir[1] * inv };
        return .{ .face = 1, .u = dir[2] * inv, .v = dir[1] * inv };
    } else if (ay >= az) {
        const inv = 1.0 / @max(ay, 1e-8);
        if (dir[1] >= 0.0) return .{ .face = 2, .u = dir[0] * inv, .v = dir[2] * inv };
        return .{ .face = 3, .u = dir[0] * inv, .v = -dir[2] * inv };
    } else {
        const inv = 1.0 / @max(az, 1e-8);
        if (dir[2] >= 0.0) return .{ .face = 4, .u = dir[0] * inv, .v = dir[1] * inv };
        return .{ .face = 5, .u = -dir[0] * inv, .v = dir[1] * inv };
    }
}

fn nextRandom(state: *u32) f32 {
    state.* ^= state.* << 13;
    state.* ^= state.* >> 17;
    state.* ^= state.* << 5;
    return @as(f32, @floatFromInt(state.* & 0x00ffffff)) / 16777215.0;
}

pub fn render(frame: *Frame, sky: *const Skybox, scene: *Scene, cam: *const Camera, lods: *const LodSet) void {
    drawSky(frame, sky, cam);
    @memset(frame.depth, 0.0);

    for (&scene.bodies) |*body| {
        const distance = @max(0.001, m.length(body.pos - cam.pos));
        const projected = body.radius / (distance * tan_half) * (@as(f32, @floatFromInt(render_h)) * 0.5);
        const lod_index: usize = if (projected > 70.0) 2 else if (projected > 22.0) 1 else 0;
        renderBody(frame, scene, cam, body, &lods.meshes[lod_index]);
    }
}

fn drawSky(frame: *Frame, sky: *const Skybox, cam: *const Camera) void {
    const width_f: f32 = @floatFromInt(render_w);
    const height_f: f32 = @floatFromInt(render_h);
    const step_x = 2.0 * tan_half * aspect / width_f;
    const step_vec = cam.right * m.splat(step_x);

    var y: usize = 0;
    while (y < @as(usize, @intCast(render_h))) : (y += 1) {
        const ndc_y = (1.0 - 2.0 * (@as(f32, @floatFromInt(y)) + 0.5) / height_f) * tan_half;
        const ndc_x = (-1.0 + 1.0 / width_f) * tan_half * aspect;
        var dir = cam.forward + cam.up * m.splat(ndc_y) + cam.right * m.splat(ndc_x);
        var x: usize = 0;
        while (x < @as(usize, @intCast(render_w))) : (x += 1) {
            frame.pixels[y * @as(usize, @intCast(render_w)) + x] = sky.sample(dir);
            dir += step_vec;
        }
    }
}

const ClipVert = struct {
    view: V3,
    world: V3,
    uv: [2]f32,
};

fn renderBody(frame: *Frame, scene: *const Scene, cam: *const Camera, body: *const Body, mesh: *const Mesh) void {
    const scale = m.splat(body.radius);
    var i: usize = 0;
    while (i < mesh.indices.len) : (i += 3) {
        const a = mesh.verts[mesh.indices[i]];
        const b = mesh.verts[mesh.indices[i + 1]];
        const c = mesh.verts[mesh.indices[i + 2]];

        const wa = body.pos + m.rotateY(a.pos * scale, body.spin);
        const wb = body.pos + m.rotateY(b.pos * scale, body.spin);
        const wc = body.pos + m.rotateY(c.pos * scale, body.spin);

        // Back-face culling: la normal de la cara debe apuntar hacia la cámara.
        const face_normal = m.cross(wb - wa, wc - wa);
        if (m.dot(face_normal, cam.pos - wa) <= 0.0) continue;

        const tri = [3]ClipVert{
            .{ .view = toView(wa, cam), .world = wa, .uv = a.uv },
            .{ .view = toView(wb, cam), .world = wb, .uv = b.uv },
            .{ .view = toView(wc, cam), .world = wc, .uv = c.uv },
        };

        var clipped: [4]ClipVert = undefined;
        const count = clipNear(tri, &clipped);
        if (count < 3) continue;

        var k: usize = 1;
        while (k + 1 < count) : (k += 1) {
            rasterTriangle(frame, scene, cam, body, clipped[0], clipped[k], clipped[k + 1]);
        }
    }
}

inline fn toView(world: V3, cam: *const Camera) V3 {
    const rel = world - cam.pos;
    return .{
        m.dot(rel, cam.right),
        m.dot(rel, cam.up),
        m.dot(rel, cam.forward),
    };
}

fn clipNear(input: [3]ClipVert, output: *[4]ClipVert) usize {
    var count: usize = 0;
    var prev = input[2];
    var prev_inside = prev.view[2] >= near_plane;

    var i: usize = 0;
    while (i < 3) : (i += 1) {
        const cur = input[i];
        const cur_inside = cur.view[2] >= near_plane;

        if (prev_inside != cur_inside) {
            const t = (near_plane - prev.view[2]) / (cur.view[2] - prev.view[2]);
            output[count] = clipLerp(prev, cur, t);
            output[count].view[2] = near_plane;
            count += 1;
        }
        if (cur_inside) {
            output[count] = cur;
            count += 1;
        }
        prev = cur;
        prev_inside = cur_inside;
    }
    return count;
}

inline fn clipLerp(a: ClipVert, b: ClipVert, t: f32) ClipVert {
    return .{
        .view = m.lerp(a.view, b.view, t),
        .world = m.lerp(a.world, b.world, t),
        .uv = .{
            a.uv[0] + (b.uv[0] - a.uv[0]) * t,
            a.uv[1] + (b.uv[1] - a.uv[1]) * t,
        },
    };
}

fn rasterTriangle(
    frame: *Frame,
    scene: *const Scene,
    cam: *const Camera,
    body: *const Body,
    va: ClipVert,
    vb: ClipVert,
    vc: ClipVert,
) void {
    const pa = project(va.view);
    var pb = project(vb.view);
    var pc = project(vc.view);

    const area = (pb.x - pa.x) * (pc.y - pa.y) - (pb.y - pa.y) * (pc.x - pa.x);
    if (@abs(area) < 0.0001) return;

    const a = va;
    var b = vb;
    var c = vc;
    if (area < 0.0) {
        const tmp_b = pb;
        pb = pc;
        pc = tmp_b;
        b = vc;
        c = vb;
    }

    const min_x = @max(0, @as(i32, @intFromFloat(@floor(@min(pa.x, @min(pb.x, pc.x))))));
    const max_x = @min(render_w - 1, @as(i32, @intFromFloat(@ceil(@max(pa.x, @max(pb.x, pc.x))))));
    const min_y = @max(0, @as(i32, @intFromFloat(@floor(@min(pa.y, @min(pb.y, pc.y))))));
    const max_y = @min(render_h - 1, @as(i32, @intFromFloat(@ceil(@max(pa.y, @max(pb.y, pc.y))))));
    if (min_x > max_x or min_y > max_y) return;

    const inv_area = 1.0 / @abs(area);
    const iza = pa.iz;
    const izb = pb.iz;
    const izc = pc.iz;

    // Coeficientes de las funciones de borde para avanzar incrementalmente.
    const e0a = pb.y - pc.y;
    const e0b = pc.x - pb.x;
    const e0c = pb.x * pc.y - pb.y * pc.x;
    const e1a = pc.y - pa.y;
    const e1b = pa.x - pc.x;
    const e1c = pc.x * pa.y - pc.y * pa.x;
    const e2a = pa.y - pb.y;
    const e2b = pb.x - pa.x;
    const e2c = pa.x * pb.y - pa.y * pb.x;

    const width: usize = @intCast(render_w);
    var py = min_y;
    while (py <= max_y) : (py += 1) {
        const fy = @as(f32, @floatFromInt(py)) + 0.5;
        const fx_start = @as(f32, @floatFromInt(min_x)) + 0.5;
        var e0 = e0a * fx_start + e0b * fy + e0c;
        var e1 = e1a * fx_start + e1b * fy + e1c;
        var e2 = e2a * fx_start + e2b * fy + e2c;

        var px = min_x;
        while (px <= max_x) : (px += 1) {
            if (e0 >= 0.0 and e1 >= 0.0 and e2 >= 0.0) {
                const bw0 = e0 * inv_area;
                const bw1 = e1 * inv_area;
                const bw2 = e2 * inv_area;
                const iz = bw0 * iza + bw1 * izb + bw2 * izc;
                const idx = @as(usize, @intCast(py)) * width + @as(usize, @intCast(px));

                if (iz > frame.depth[idx]) {
                    const inv_iz = 1.0 / iz;
                    const w0 = bw0 * iza;
                    const w1 = bw1 * izb;
                    const w2 = bw2 * izc;
                    const world = (a.world * m.splat(w0) + b.world * m.splat(w1) + c.world * m.splat(w2)) * m.splat(inv_iz);
                    const uv = [2]f32{
                        (a.uv[0] * w0 + b.uv[0] * w1 + c.uv[0] * w2) * inv_iz,
                        (a.uv[1] * w0 + b.uv[1] * w1 + c.uv[1] * w2) * inv_iz,
                    };
                    const normal = m.normalize(world - body.pos);
                    frame.pixels[idx] = scene.shade(body, uv, normal, world, cam.pos);
                    frame.depth[idx] = iz;
                }
            }
            e0 += e0a;
            e1 += e1a;
            e2 += e2a;
        }
    }
}

const Projected = struct {
    x: f32,
    y: f32,
    iz: f32,
};

inline fn project(view: V3) Projected {
    const iz = 1.0 / view[2];
    return .{
        .x = (view[0] * iz / (tan_half * aspect) * 0.5 + 0.5) * @as(f32, @floatFromInt(render_w)),
        .y = (0.5 - view[1] * iz / tan_half * 0.5) * @as(f32, @floatFromInt(render_h)),
        .iz = iz,
    };
}
