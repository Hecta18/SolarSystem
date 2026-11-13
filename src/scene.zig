const std = @import("std");
const m = @import("math.zig");
const V3 = m.V3;

pub const tex_w = 64;
pub const tex_h = 32;
pub const body_count = 6;
pub const sun_index = 0;

pub const Shader = enum {
    sun,
    mercury,
    venus,
    earth,
    mars,
    jupiter,
};

pub const Body = struct {
    name: []const u8,
    shader: Shader,
    radius: f32,
    orbit_radius: f32,
    orbit_speed: f32,
    spin_speed: f32,
    angle: f32,
    spin: f32,
    pos: V3,
    tex: [tex_w * tex_h]u32,
    tint: V3,
};

pub const Scene = struct {
    bodies: [body_count]Body,
    time: f32,

    pub fn init(self: *Scene) void {
        self.time = 0.0;
        self.bodies = .{
            .{
                .name = "Sol",
                .shader = .sun,
                .radius = 3.6,
                .orbit_radius = 0.0,
                .orbit_speed = 0.0,
                .spin_speed = 0.08,
                .angle = 0.0,
                .spin = 0.0,
                .pos = m.v3(0, 0, 0),
                .tex = paintTexture(.sun, 0x51a7c3d1),
                .tint = m.v3(1.0, 0.72, 0.20),
            },
            .{
                .name = "Mercurio",
                .shader = .mercury,
                .radius = 0.85,
                .orbit_radius = 12.0,
                .orbit_speed = 0.55,
                .spin_speed = 0.35,
                .angle = 1.1,
                .spin = 0.3,
                .pos = m.v3(0, 0, 0),
                .tex = paintTexture(.mercury, 0x8f31b2c4),
                .tint = m.v3(0.62, 0.60, 0.57),
            },
            .{
                .name = "Venus",
                .shader = .venus,
                .radius = 1.30,
                .orbit_radius = 18.5,
                .orbit_speed = 0.37,
                .spin_speed = 0.18,
                .angle = 3.0,
                .spin = 1.0,
                .pos = m.v3(0, 0, 0),
                .tex = paintTexture(.venus, 0x2e6d94a1),
                .tint = m.v3(0.93, 0.72, 0.40),
            },
            .{
                .name = "Tierra",
                .shader = .earth,
                .radius = 1.45,
                .orbit_radius = 25.5,
                .orbit_speed = 0.27,
                .spin_speed = 0.55,
                .angle = 5.2,
                .spin = 2.1,
                .pos = m.v3(0, 0, 0),
                .tex = paintTexture(.earth, 0xb04c27e1),
                .tint = m.v3(0.28, 0.55, 0.90),
            },
            .{
                .name = "Marte",
                .shader = .mars,
                .radius = 1.05,
                .orbit_radius = 33.0,
                .orbit_speed = 0.20,
                .spin_speed = 0.50,
                .angle = 0.2,
                .spin = 0.7,
                .pos = m.v3(0, 0, 0),
                .tex = paintTexture(.mars, 0x77c1a35e),
                .tint = m.v3(0.78, 0.32, 0.16),
            },
            .{
                .name = "Jupiter",
                .shader = .jupiter,
                .radius = 2.60,
                .orbit_radius = 45.0,
                .orbit_speed = 0.11,
                .spin_speed = 0.75,
                .angle = 2.1,
                .spin = 4.0,
                .pos = m.v3(0, 0, 0),
                .tex = paintTexture(.jupiter, 0x19d4e6f3),
                .tint = m.v3(0.82, 0.63, 0.43),
            },
        };

        for (self.bodies[1..]) |*body| {
            body.pos = m.v3(
                @cos(body.angle) * body.orbit_radius,
                0.0,
                @sin(body.angle) * body.orbit_radius,
            );
        }
    }

    pub fn update(self: *Scene, dt: f32) void {
        self.time += dt;
        for (self.bodies[1..]) |*body| {
            body.angle += body.orbit_speed * dt;
            body.spin += body.spin_speed * dt;
            body.pos = m.v3(
                @cos(body.angle) * body.orbit_radius,
                0.0,
                @sin(body.angle) * body.orbit_radius,
            );
        }
        self.bodies[sun_index].spin += self.bodies[sun_index].spin_speed * dt;
    }

    pub fn focusPos(self: *const Scene, index: usize) V3 {
        return self.bodies[index].pos;
    }

    pub fn focusRadius(self: *const Scene, index: usize) f32 {
        return self.bodies[index].radius;
    }

    pub fn bodyName(self: *const Scene, index: usize) []const u8 {
        return self.bodies[index].name;
    }

    /// Shader por cuerpo. Cada planeta usa una rama distinta: no es solo un
    /// cambio de color, sino una alteración propia de UV/luz/atmósfera.
    pub fn shade(
        self: *const Scene,
        body: *const Body,
        uv: [2]f32,
        normal: V3,
        world: V3,
        cam_pos: V3,
    ) u32 {
        const base = sampleTex(&body.tex, uv);

        if (body.shader == .sun) {
            const pulse = 0.88 + 0.12 * @sin(self.time * 2.7 + uv[0] * 9.0 + uv[1] * 6.0);
            const hot = m.mixColor(base, m.v3(1.0, 0.94, 0.70), 0.35);
            return m.colorToU32(hot * m.splat(1.15 * pulse));
        }

        const light_dir = m.normalize(-world);
        const view_dir = m.normalize(cam_pos - world);
        const distance = m.length(world);
        const attenuation = 1.0 / (1.0 + 0.00018 * distance * distance);
        const ndotl = @max(m.dot(normal, light_dir), 0.0);
        const ambient = 0.22;
        const lit = ambient + ndotl * 1.25 * attenuation;

        switch (body.shader) {
            .mercury => {
                // Relieve de cráteres: el ruido oscurece los bordes y resalta
                // el terminador duro del planeta sin atmósfera.
                const crater = 1.0 - 0.30 * @abs(fbm(uv[0] * 30.0, uv[1] * 60.0, 11, 3) * 2.0 - 1.0);
                const color = base * m.splat(lit * crater);
                return m.colorToU32(color);
            },
            .venus => {
                // Nubes animadas que se desplazan lentamente alrededor del
                // planeta, con una neblina emisiva muy suave.
                const swirl = m.v3(
                    m.fract(uv[0] + self.time * 0.010 + @sin(uv[1] * 10.0) * 0.006),
                    uv[1],
                    0.0,
                );
                const cloud = sampleTex(&body.tex, .{ swirl[0], swirl[1] });
                const haze = base * m.splat(0.10);
                return m.colorToU32(cloud * m.splat(lit) + haze);
            },
            .earth => {
                // Atmósfera Fresnel azul + brillo especular en el océano.
                const fresnel = std.math.pow(f32, 1.0 - @max(m.dot(normal, view_dir), 0.0), 3.0);
                const atmo = m.v3(0.16, 0.48, 1.0) * m.splat(fresnel * (0.20 + 0.80 * ndotl));
                const half = m.normalize(light_dir + view_dir);
                const spec = std.math.pow(f32, @max(m.dot(normal, half), 0.0), 28.0) * 0.55 * ndotl;
                return m.colorToU32(base * m.splat(lit) + atmo + m.splat(spec));
            },
            .mars => {
                // Polvo animado que se mezcla con la iluminación y suaviza el
                // terminador del desierto marciano.
                const dust = (fbm(uv[0] * 14.0 + self.time * 0.02, uv[1] * 26.0, 23, 3) - 0.5) * 0.22;
                const haze = m.v3(0.52, 0.20, 0.08) * m.splat(@max(dust, 0.0) * ndotl);
                return m.colorToU32(base * m.splat(lit) + haze);
            },
            .jupiter => {
                // Bandas que ondulan con el tiempo y un resplandor cálido en
                // la Gran Mancha Roja.
                const warp_u = uv[0] + @sin(uv[1] * 22.0 + self.time * 0.35) * 0.015;
                const warp_v = uv[1] + @sin(uv[0] * 12.0 + self.time * 0.22) * 0.008;
                const bands = sampleTex(&body.tex, .{ warp_u, warp_v });
                const spot_du = wrapDelta(uv[0], 0.70);
                const spot = @max(0.0, 1.0 - @sqrt((spot_du * spot_du) / 0.006 + ((uv[1] - 0.62) * (uv[1] - 0.62)) / 0.0025));
                const glow = m.v3(0.55, 0.12, 0.05) * m.splat(spot * 0.25 * ndotl);
                return m.colorToU32(bands * m.splat(lit) + glow);
            },
            else => return m.colorToU32(base * m.splat(lit)),
        }
    }
};

fn wrapDelta(a: f32, b: f32) f32 {
    var d = a - b;
    if (d > 0.5) d -= 1.0;
    if (d < -0.5) d += 1.0;
    return d;
}

pub fn sampleTex(tex: *const [tex_w * tex_h]u32, uv: [2]f32) V3 {
    // Filtrado bilineal barato: suaviza la textura sin necesitar mipmaps.
    const u = m.fract(uv[0]) * @as(f32, tex_w) - 0.5;
    const v = std.math.clamp(uv[1], 0.0, 1.0) * (@as(f32, tex_h) - 1.0);
    const fx = @floor(u);
    const fy = @floor(v);
    const tx = u - fx;
    const ty = v - fy;

    const ix: i32 = @intFromFloat(fx);
    const iy: i32 = @intFromFloat(fy);
    const x0: usize = @intCast(@mod(ix, @as(i32, tex_w)));
    const x1: usize = @intCast(@mod(ix + 1, @as(i32, tex_w)));
    const y0: usize = @intCast(std.math.clamp(iy, 0, tex_h - 1));
    const y1: usize = @intCast(std.math.clamp(iy + 1, 0, tex_h - 1));

    const c00 = m.u32ToColor(tex[y0 * tex_w + x0]);
    const c10 = m.u32ToColor(tex[y0 * tex_w + x1]);
    const c01 = m.u32ToColor(tex[y1 * tex_w + x0]);
    const c11 = m.u32ToColor(tex[y1 * tex_w + x1]);
    return m.lerp(m.lerp(c00, c10, tx), m.lerp(c01, c11, tx), ty);
}

fn paintTexture(shader: Shader, seed: u32) [tex_w * tex_h]u32 {
    var out: [tex_w * tex_h]u32 = undefined;
    const width_f: f32 = @floatFromInt(tex_w);
    const height_f: f32 = @floatFromInt(tex_h);

    var y: usize = 0;
    while (y < tex_h) : (y += 1) {
        const v = (@as(f32, @floatFromInt(y)) + 0.5) / height_f;
        var x: usize = 0;
        while (x < tex_w) : (x += 1) {
            const u = (@as(f32, @floatFromInt(x)) + 0.5) / width_f;
            out[y * tex_w + x] = m.colorToU32(textureColor(shader, u, v, seed));
        }
    }
    return out;
}

fn textureColor(shader: Shader, u: f32, v: f32, seed: u32) V3 {
    const lat = @abs(v - 0.5) * 2.0;

    return switch (shader) {
        .sun => blk: {
            const n = fbm(u * 15.0, v * 15.0, seed, 5);
            const detail = fbm(u * 38.0, v * 38.0, seed + 9, 3);
            const heat = m.clamp01(n * 0.72 + detail * 0.38);
            const c1 = m.v3(1.0, 0.18, 0.008);
            const c2 = m.v3(1.0, 0.62, 0.035);
            const c3 = m.v3(1.0, 0.96, 0.66);
            const a = m.mixColor(c1, c2, heat);
            break :blk m.mixColor(a, c3, std.math.pow(f32, heat, 2.6) * 0.85);
        },
        .mercury => blk: {
            const n = fbm(u * 13.0, v * 26.0, seed, 5);
            const ridge = @abs(fbm(u * 28.0, v * 56.0, seed + 3, 3) * 2.0 - 1.0);
            const shade = 0.32 + n * 0.50 - ridge * 0.14;
            break :blk m.v3(shade * 1.00, shade * 0.97, shade * 0.92);
        },
        .venus => blk: {
            const swirl = fbm(u * 4.0 + @sin(v * 12.0) * 0.45, v * 6.0, seed, 4);
            const bands = 0.5 + 0.5 * @sin(v * std.math.pi * 7.0 + swirl * 5.0);
            const c1 = m.v3(0.55, 0.32, 0.12);
            const c2 = m.v3(0.98, 0.82, 0.48);
            const c3 = m.v3(0.99, 0.93, 0.72);
            break :blk m.mixColor(m.mixColor(c1, c2, bands), c3, swirl * 0.35);
        },
        .earth => blk: {
            const n = fbm(u * 6.0, v * 12.0, seed, 5);
            const detail = fbm(u * 20.0, v * 40.0, seed + 7, 3);
            const land = n + detail * 0.22;
            const ocean_deep = m.v3(0.02, 0.12, 0.40);
            const ocean_shallow = m.v3(0.04, 0.36, 0.68);
            const grass = m.v3(0.14, 0.48, 0.16);
            const desert = m.v3(0.68, 0.54, 0.26);
            const rock = m.v3(0.36, 0.30, 0.23);
            var c = m.mixColor(ocean_deep, ocean_shallow, m.clamp01(n * 1.6));
            if (land > 0.55) {
                const biome = fbm(u * 3.0 + 4.0, v * 8.0, seed + 19, 3);
                c = m.mixColor(grass, desert, m.clamp01(biome * 1.4));
                c = m.mixColor(c, rock, m.clamp01((land - 0.62) * 3.0));
            }
            if (lat > 0.84) {
                const ice = m.smoothstep((lat - 0.84) / 0.16);
                c = m.mixColor(c, m.v3(0.92, 0.96, 1.0), ice);
            }
            const clouds = fbm(u * 9.0 + 3.0, v * 18.0, seed + 41, 4);
            if (clouds > 0.61) {
                c = m.mixColor(c, m.v3(0.96, 0.98, 1.0), m.clamp01((clouds - 0.61) * 3.0) * 0.55);
            }
            break :blk c;
        },
        .mars => blk: {
            const n = fbm(u * 8.0, v * 16.0, seed, 5);
            const dark = fbm(u * 4.0 + 7.0, v * 9.0, seed + 13, 3);
            var c = m.mixColor(m.v3(0.45, 0.15, 0.06), m.v3(0.85, 0.38, 0.16), n);
            c = m.mixColor(c, m.v3(0.22, 0.10, 0.055), m.clamp01((dark - 0.55) * 2.0) * 0.55);
            if (lat > 0.86) {
                const ice = m.smoothstep((lat - 0.86) / 0.14);
                c = m.mixColor(c, m.v3(0.94, 0.90, 0.84), ice);
            }
            break :blk c;
        },
        .jupiter => blk: {
            const turb = fbm(u * 4.0, v * 10.0, seed, 4);
            const band = 0.5 + 0.5 * @sin(v * std.math.pi * 10.0 + turb * 2.6);
            const c1 = m.v3(0.42, 0.24, 0.12);
            const c2 = m.v3(0.96, 0.80, 0.56);
            const c3 = m.v3(1.0, 0.95, 0.82);
            var c = m.mixColor(c1, c2, band);
            c = m.mixColor(c, c3, m.clamp01(fbm(u * 12.0, v * 20.0, seed + 5, 3) - 0.35));
            const du = wrapDelta(u, 0.70);
            const spot_d = @sqrt((du * du) / 0.008 + ((v - 0.62) * (v - 0.62)) / 0.0035);
            if (spot_d < 1.0) {
                c = m.mixColor(c, m.v3(0.66, 0.16, 0.08), 1.0 - spot_d);
            }
            break :blk c;
        },
    };
}

fn hash2(x: i32, y: i32, seed: u32) u32 {
    var h: u32 = @as(u32, @bitCast(x)) *% 374761393;
    h +%= @as(u32, @bitCast(y)) *% 668265263;
    h +%= seed *% 2246822519;
    h = (h ^ (h >> 13)) *% 1274126177;
    return h ^ (h >> 16);
}

fn rand01(x: i32, y: i32, seed: u32) f32 {
    return @as(f32, @floatFromInt(hash2(x, y, seed) & 0x00ffffff)) / 16777215.0;
}

fn valueNoise(x: f32, y: f32, seed: u32) f32 {
    const xi = @floor(x);
    const yi = @floor(y);
    const xf = x - xi;
    const yf = y - yi;
    const u = xf * xf * (3.0 - 2.0 * xf);
    const v = yf * yf * (3.0 - 2.0 * yf);
    const x0: i32 = @intFromFloat(xi);
    const y0: i32 = @intFromFloat(yi);
    const a = rand01(x0, y0, seed);
    const b = rand01(x0 + 1, y0, seed);
    const c = rand01(x0, y0 + 1, seed);
    const d = rand01(x0 + 1, y0 + 1, seed);
    return (a + (b - a) * u) * (1.0 - v) + (c + (d - c) * u) * v;
}

fn fbm(x: f32, y: f32, seed: u32, octaves: u32) f32 {
    var value: f32 = 0.0;
    var amplitude: f32 = 0.5;
    var frequency: f32 = 1.0;
    var norm: f32 = 0.0;
    var i: u32 = 0;
    while (i < octaves) : (i += 1) {
        value += valueNoise(x * frequency, y * frequency, seed +% i *% 1013) * amplitude;
        norm += amplitude;
        amplitude *= 0.5;
        frequency *= 2.0;
    }
    return value / norm;
}
