const std = @import("std");

pub const V3 = @Vector(3, f32);

pub inline fn v3(x: f32, y: f32, z: f32) V3 {
    return .{ x, y, z };
}

pub inline fn splat(value: f32) V3 {
    return @splat(value);
}

pub inline fn dot(a: V3, b: V3) f32 {
    return @reduce(.Add, a * b);
}

pub inline fn cross(a: V3, b: V3) V3 {
    return .{
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    };
}

pub inline fn length(a: V3) f32 {
    return @sqrt(dot(a, a));
}

pub inline fn normalize(a: V3) V3 {
    const len = length(a);
    return if (len > 1e-8) a / splat(len) else v3(0, 0, 0);
}

pub inline fn lerp(a: V3, b: V3, t: f32) V3 {
    return a + (b - a) * splat(t);
}

pub inline fn clamp01(x: f32) f32 {
    return @min(1.0, @max(0.0, x));
}

pub inline fn smoothstep(t: f32) f32 {
    const x = clamp01(t);
    return x * x * (3.0 - 2.0 * x);
}

pub inline fn rotateY(p: V3, angle: f32) V3 {
    const c = @cos(angle);
    const s = @sin(angle);
    return .{ p[0] * c + p[2] * s, p[1], -p[0] * s + p[2] * c };
}

pub inline fn fract(x: f32) f32 {
    return x - @floor(x);
}

pub inline fn mixColor(a: V3, b: V3, t: f32) V3 {
    return lerp(a, b, clamp01(t));
}

pub inline fn colorToU32(c: V3) u32 {
    const r: u32 = @intFromFloat(std.math.clamp(c[0], 0.0, 1.0) * 255.0 + 0.5);
    const g: u32 = @intFromFloat(std.math.clamp(c[1], 0.0, 1.0) * 255.0 + 0.5);
    const b: u32 = @intFromFloat(std.math.clamp(c[2], 0.0, 1.0) * 255.0 + 0.5);
    return r | (g << 8) | (b << 16) | 0xff000000;
}

pub inline fn u32ToColor(c: u32) V3 {
    return .{
        @as(f32, @floatFromInt(c & 0xff)) / 255.0,
        @as(f32, @floatFromInt((c >> 8) & 0xff)) / 255.0,
        @as(f32, @floatFromInt((c >> 16) & 0xff)) / 255.0,
    };
}
