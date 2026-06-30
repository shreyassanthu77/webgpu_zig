const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const upstream = b.dependency("webgpu-headers-upstream", .{});
    const webgpu_json = upstream.path("webgpu.json");

    const bindings_generator = b.addExecutable(.{
        .name = "gen-bindings",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/gen-bindings.zig"),
            .target = b.graph.host,
            .optimize = .Debug,
        }),
    });
    const run_bindings_generator = b.addRunArtifact(bindings_generator);
    run_bindings_generator.has_side_effects = true;
    run_bindings_generator.addFileArg(webgpu_json);
    run_bindings_generator.addFileArg(b.path("src/bindings.zig"));
    // const bindings_file = run_bindings_generator.addOutputFileArg("bindings.zig");
    run_bindings_generator.addFileArg(b.path("src/prelude.zig"));

    const bindings = b.addModule("bindings", .{
        // .root_source_file = bindings_file,
        .root_source_file = b.path("src/bindings.zig"),
        .target = target,
        .optimize = optimize,
    });

    const bindings_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/test-bindings.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "webgpu", .module = bindings },
            },
        }),
    });
    bindings_test.step.dependOn(&run_bindings_generator.step);

    const test_step = b.step("test", "Run all tests");
    const run_bindings_test = b.addRunArtifact(bindings_test);
    test_step.dependOn(&run_bindings_test.step);

    const check_step = b.step("check", "Run all tests");
    check_step.dependOn(&bindings_test.step);
}
