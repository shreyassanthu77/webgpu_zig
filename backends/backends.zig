const std = @import("std");
pub const wgvk = @import("wgvk.zig");

pub const Backend = enum { wgvk, none };

pub fn link(
    b: *std.Build,
    module: *std.Build.Module,
    backend: Backend,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) void {
    switch (backend) {
        .wgvk => wgvk.link(b, module, target, optimize),
        .none => {},
    }
}
