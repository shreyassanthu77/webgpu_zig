const std = @import("std");
const wgvk = @import("wgvk.zig");
const wgpu_native = @import("wgpu-native.zig");

pub const Backend = enum {
    none,
    wgvk,
    wgpu_native,
};

pub fn headerPath(
    b: *std.Build,
    backend: Backend,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) ?std.Build.LazyPath {
    return switch (backend) {
        .none => null,
        .wgvk => null,
        .wgpu_native => wgpu_native.headerPath(b, target, optimize),
    };
}

pub fn overlay(b: *std.Build, backend: Backend) ?std.Build.LazyPath {
    return switch (backend) {
        .none => null,
        .wgvk => wgvk.overlay(b),
        .wgpu_native => wgpu_native.overlay(b),
    };
}

pub fn link(
    BuildZig: type,
    b: *std.Build,
    module: *std.Build.Module,
    backend: Backend,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) void {
    switch (backend) {
        .none => {},
        .wgvk => wgvk.link(BuildZig, b, module, target, optimize),
        .wgpu_native => wgpu_native.link(b, module, target, optimize),
    }
}
