const std = @import("std");
const wgvk = @import("wgvk.zig");
const wgpu_native = @import("wgpu-native.zig");

pub const Backend = enum {
    none,
    wgvk,
    wgpu_native,
};

pub fn link(
    b: *std.Build,
    module: *std.Build.Module,
    backend: Backend,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) void {
    switch (backend) {
        .none => {},
        .wgvk => wgvk.link(b, module, target, optimize),
        .wgpu_native => wgpu_native.link(b, module, target, optimize),
    }
}
