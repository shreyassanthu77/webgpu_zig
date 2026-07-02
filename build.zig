const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const make_local_copy = b.option(
        bool,
        "make-local-copy",
        "Generate a local copy of the bindings.zig file",
    ) orelse false;
    // hide abi tests behind a flag so WGVK wont get pulled in
    // when a user imports webgpu_zig as a library
    const enable_abi_tests = b.option(
        bool,
        "abi-tests",
        "Enable ABI tests",
    ) orelse false;

    const bindings_gen = BindingsGen.init(b);

    const bindings_file = bindings_gen.generateBindings(false);
    const webgpu_mod = b.addModule("webgpu", .{
        .root_source_file = bindings_file,
        .target = target,
        .optimize = optimize,
    });

    if (make_local_copy) {
        const usf = b.addUpdateSourceFiles();
        usf.addCopyFileToSource(bindings_file, "src/bindings.zig");
        b.getInstallStep().dependOn(&usf.step);
    }

    const docs_step = b.step("docs", "Generate docs");
    const docs_lib = b.addLibrary(.{
        .name = "webgpu-docs",
        .root_module = webgpu_mod,
    });
    docs_step.dependOn(&b.addInstallDirectory(.{
        .source_dir = docs_lib.getEmittedDocs(),
        .install_subdir = "docs",
        .install_dir = .prefix,
    }).step);

    const check_step = b.step("check", "Build everything without running tests");
    const test_step = b.step("test", "Run all tests");

    const wgvk_stubs = b.addLibrary(.{
        .name = "wgvk-stubs",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/wgvk_stubs.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const test_bindings_file = bindings_gen.generateBindings(true);
    const webgpu_h_mod = b.addTranslateC(.{
        .root_source_file = bindings_gen.upstream.path("webgpu.h"),
        .target = target,
        .optimize = optimize,
    }).createModule();
    inline for ([_]?struct { []const u8, std.Build.LazyPath }{
        .{ "gen-unit-tests", b.path("tools/gen/tests.zig") },
        .{ "prelude", b.path("src/prelude_test.zig") },
        if (enable_abi_tests) .{ "webgpu", test_bindings_file } else null,
    }) |maybe_test_file| {
        if (maybe_test_file) |test_file| {
            const test_exe = b.addTest(.{
                .name = test_file.@"0",
                .root_module = b.createModule(.{
                    .root_source_file = test_file.@"1",
                    .target = target,
                    .optimize = optimize,
                    .imports = &.{
                        .{ .name = "c", .module = webgpu_h_mod },
                    },
                }),
                .use_llvm = true, // TODO: remove once the native backend is fixed
            });
            const run_test_exe = b.addRunArtifact(test_exe);
            test_step.dependOn(&run_test_exe.step);
            check_step.dependOn(&test_exe.step);

            if (enable_abi_tests) if (b.lazyDependency("WGVK", .{
                .target = target,
                .optimize = optimize,
            })) |wgvk| {
                test_exe.root_module.linkLibrary(wgvk.artifact("wgvk"));
                test_exe.root_module.linkLibrary(wgvk_stubs);
            };
        }
    }
}

const BindingsGen = struct {
    b: *std.Build,
    upstream: *std.Build.Dependency,
    webgpu_json: std.Build.LazyPath,
    bindings_generator: *std.Build.Step.Compile,

    pub fn init(b: *std.Build) BindingsGen {
        const upstream = b.dependency("webgpu-headers-upstream", .{});
        const webgpu_json = upstream.path("webgpu.json");

        const bindings_generator = b.addExecutable(.{
            .name = "gen-bindings",
            .root_module = b.createModule(.{
                .root_source_file = b.path("tools/gen/main.zig"),
                .target = b.graph.host,
                .optimize = .Debug,
            }),
        });

        return .{
            .b = b,
            .upstream = upstream,
            .webgpu_json = webgpu_json,
            .bindings_generator = bindings_generator,
        };
    }

    pub fn generateBindings(
        self: *const BindingsGen,
        enable_abi_tests: bool,
    ) std.Build.LazyPath {
        const b = self.b;
        const run_bindings_generator = b.addRunArtifact(self.bindings_generator);
        run_bindings_generator.has_side_effects = true;
        if (enable_abi_tests) run_bindings_generator.addArg("--abi-checks");
        run_bindings_generator.addFileArg(self.webgpu_json);
        const bindings_file = run_bindings_generator.addOutputFileArg("bindings.zig");
        run_bindings_generator.addFileArg(b.path("src/prelude.zig"));

        return bindings_file;
    }
};
