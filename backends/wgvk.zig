const std = @import("std");

pub fn link(
    BuildZig: type,
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
    if (b.lazyImport(BuildZig, "WGVK")) |wgvk| {
        const lib = try wgvk.buildLib(b, .{
            .target = target,
            .optimize = optimize,
            .use_vma = false,
            .enable_x11 = true,
            .enable_wayland = true,
        });

        module.linkLibrary(lib);
        module.linkLibrary(wgvk_stubs);
    }
}
