const std = @import("std");

pub fn link(
    b: *std.Build,
    module: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) void {
    const wgvk_stubs = b.addLibrary(.{
        .name = "wgvk-stubs",
        .root_module = b.createModule(.{
            .root_source_file = b.path("backends/wgvk_stubs.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    if (b.lazyDependency("WGVK", .{
        .target = target,
        .optimize = optimize,
    })) |wgvk| {
        module.linkLibrary(wgvk.artifact("wgvk"));
        module.linkLibrary(wgvk_stubs);
    }
}
