const std = @import("std");

pub fn link(
    b: *std.Build,
    module: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) void {
    const dependency_name = getDependencyName(b, target, optimize);
    const has_dependency = for (b.available_deps) |dep| {
        const dep_name, _ = dep;
        if (std.mem.eql(u8, dep_name, dependency_name)) break true;
    } else false;
    if (!has_dependency) panic("wgpu-native is not available for this target", .{});

    if (b.lazyDependency(dependency_name, .{})) |wgpu_native| {
        const lib_path = wgpu_native.path(if (target.result.os.tag == .windows and target.result.abi == .msvc)
            "lib/wgpu_native.lib"
        else
            "lib/libwgpu_native.a");
        module.addObjectFile(lib_path);
        module.link_libc = true;

        if (target.result.abi == .gnu) {
            module.linkSystemLibrary("unwind", .{ .needed = true });
        }
    }
    switch (target.result.os.tag) {
        .windows => {
            module.linkSystemLibrary("ws2_32", .{ .needed = true });
            module.linkSystemLibrary("userenv", .{ .needed = true });
        },
        .macos => {
            module.linkSystemLibrary("objc", .{ .needed = true });
            module.linkFramework("Foundation", .{});
            module.linkFramework("Metal", .{});
            module.linkFramework("QuartzCore", .{});

            if (b.lazyDependency("xcode_frameworks", .{})) |frameworks| {
                module.addSystemFrameworkPath(frameworks.path("Frameworks"));
                module.addSystemIncludePath(frameworks.path("include"));
                module.addLibraryPath(frameworks.path("lib"));
            }
        },
        else => {},
    }
}

fn getDependencyName(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) []const u8 {
    const t = target.result;
    const os = t.os.tag;
    const arch = t.cpu.arch;
    const abi = t.abi;
    const is_android = abi.isAndroid();

    const os_part = switch (os) {
        .windows => "windows",
        .linux => if (is_android) "android" else "linux",
        .macos => "macos",
        .ios => "ios",
        else => panic("wgpu-native: unsupported OS {}", .{os}),
    };

    const arch_part = switch (arch) {
        .aarch64 => "-aarch64",
        .arm => if (is_android) "-armv7" else panic("wgpu-native: armv7 is only supported on Android", .{}),
        .x86 => if (is_android or os == .windows)
            "-i686"
        else
            panic("wgpu-native: x86 is only supported on Windows and Android", .{}),
        .x86_64 => "-x86_64",
        else => panic("wgpu-native: unsupported architecture {}", .{arch}),
    };

    const abi_part = switch (abi) {
        .none => switch (os) {
            .ios, .macos => "",
            else => panic("wgpu-native: please specify an ABI", .{}),
        },
        .gnu => switch (os) {
            .windows => if (arch == .x86_64)
                "-gnu"
            else
                panic("wgpu-native: gnu is only supported on Windows x86_64", .{}),
            .linux => "",
            else => panic("wgpu-native: gnu is only supported on Windows and Linux", .{}),
        },
        .msvc => switch (os) {
            .windows => "-msvc",
            else => panic("wgpu-native: msvc is only supported on Windows", .{}),
        },
        .simulator => switch (os) {
            .ios => "-simulator",
            else => panic("wgpu-native: simulator is only supported on iOS", .{}),
        },
        .android, .androideabi => "",
        else => panic("wgpu-native: unsupported ABI {}", .{abi}),
    };

    const opt_part = switch (optimize) {
        .Debug => "-debug",
        else => "-release",
    };

    return b.fmt("wgpu-{s}{s}{s}{s}", .{
        os_part,
        arch_part,
        abi_part,
        opt_part,
    });
}

fn panic(comptime fmt: []const u8, args: anytype) noreturn {
    @branchHint(.cold);
    std.log.err(fmt, args);
    std.process.exit(1);
}
