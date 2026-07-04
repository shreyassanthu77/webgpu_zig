const std = @import("std");

pub fn overlay(b: *std.Build) ?std.Build.LazyPath {
    _ = b;
    return null;
}

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
        const lib: *std.Build.Step.Compile = try wgvk.buildLib(b, .{
            .target = target,
            .optimize = optimize,
            .use_vma = false,
            .enable_x11 = true,
            .enable_wayland = true,
        });

        module.linkLibrary(lib);
        module.linkLibrary(wgvk_stubs);

        switch (target.result.os.tag) {
            .macos => {
                if (b.lazyDependency("xcode_frameworks", .{})) |frameworks| {
                    module.addSystemFrameworkPath(frameworks.path("Frameworks"));
                    module.addSystemIncludePath(frameworks.path("include"));
                    module.addLibraryPath(frameworks.path("lib"));
                }
            },
            else => {},
        }
    }
}
