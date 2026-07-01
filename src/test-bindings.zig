const std = @import("std");

comptime {
    _ = @import("prelude.zig");
    _ = @import("webgpu");
}

const wgpu = @import("webgpu");

test "chain: extension auto-converts to parent descriptor" {
    // Canonical use case: build a Wayland surface source extension on the stack,
    // convert it to a parent SurfaceDescriptor, and pass `&desc` to
    // `Instance.createSurface`. The converter returns the parent struct by value
    // (with `next_in_chain` already wired to point at this extension's `chain`),
    // so users no longer write `.{ .next_in_chain = @ptrCast(@alignCast(&x.chain)) }`
    // by hand.
    var display: u32 = 0;
    var surface: u32 = 0;
    var wayland = wgpu.SurfaceSourceWaylandSurface{
        .display = &display,
        .surface = &surface,
    };

    var desc = wayland.surfaceDescriptor();
    _ = &desc;

    // next_in_chain must point back at the extension's chain field.
    try std.testing.expect(desc.next_in_chain != null);
    try std.testing.expectEqual(
        &wayland.chain,
        @as(*wgpu.ChainedStruct, @ptrCast(@alignCast(@constCast(desc.next_in_chain.?)))),
    );
    try std.testing.expectEqual(wgpu.SType.surface_source_wayland_surface, wayland.chain.s_type);

    // The returned value is the parent struct type — comptime type check.
    comptime std.debug.assert(@TypeOf(desc) == wgpu.SurfaceDescriptor);
}

test "chain: extension converter preserves chain link to a sibling" {
    // Chain more than one extension by manually setting `.chain.next` — the
    // converter doesn't touch `chain.next`, so any pre-set sibling link survives.
    var display: u32 = 0;
    var surface: u32 = 0;
    var wayland = wgpu.SurfaceSourceWaylandSurface{
        .display = &display,
        .surface = &surface,
    };

    var xcb_connection: u32 = 0;
    var xcb = wgpu.SurfaceSourceXCBWindow{
        .connection = &xcb_connection,
    };
    wayland.chain.next = @ptrCast(@alignCast(&xcb.chain));

    var desc = wayland.surfaceDescriptor();
    _ = &desc;
    try std.testing.expectEqual(
        @as(?*wgpu.ChainedStruct, @ptrCast(@alignCast(&xcb.chain))),
        wayland.chain.next,
    );
    // The descriptor still just points at `wayland.chain`; the sibling is reached
    // by traversing `chain.next` at runtime — consistent with WebGPU chain semantics.
    try std.testing.expectEqual(
        @as(*wgpu.ChainedStruct, @ptrCast(@alignCast(@constCast(desc.next_in_chain.?)))),
        &wayland.chain,
    );
}