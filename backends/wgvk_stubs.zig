//! Standard webgpu.h symbols that WGVK does not implement (yet). The test
//! binaries reference every binding, so the linker needs *something* for
//! these; calling one at runtime panics.
//!
//! Linked after libwgvk: if WGVK gains one of these symbols, the build fails
//! with a duplicate-symbol error — delete the stub here when that happens.

fn stub(comptime name: []const u8) fn () callconv(.c) noreturn {
    return struct {
        fn f() callconv(.c) noreturn {
            @panic(name ++ " is not implemented by the linked WebGPU implementation");
        }
    }.f;
}

comptime {
    for ([_][]const u8{
        "wgpuGetInstanceFeatures",
        "wgpuGetInstanceLimits",
        "wgpuHasInstanceFeature",
        "wgpuTextureGetTextureBindingViewDimension",
        "wgpuExternalTextureSetLabel",
        "wgpuComputePassEncoderSetImmediates",
        "wgpuRenderPassEncoderSetImmediates",
        "wgpuRenderBundleEncoderSetImmediates",
    }) |name| {
        @export(&stub(name), .{ .name = name });
    }
}
