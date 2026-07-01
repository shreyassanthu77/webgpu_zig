const std = @import("std");

/// `get_mapped_range` -> `GetMappedRange`, `discrete_GPU` -> `DiscreteGPU`,
/// `BC4_R_unorm` -> `BC4RUnorm`, `CPU` -> `CPU`.
pub fn pascal(a: std.mem.Allocator, s: []const u8) []const u8 {
    var out = std.ArrayList(u8).initCapacity(a, s.len) catch @panic("OOM");
    var it = std.mem.splitScalar(u8, s, '_');
    while (it.next()) |part| {
        if (part.len == 0) continue;
        const i = out.items.len;
        out.appendSliceAssumeCapacity(part);
        out.items[i] = std.ascii.toUpper(part[0]);
    }
    return out.toOwnedSlice(a) catch @panic("OOM");
}

/// `get_mapped_range` -> `getMappedRange`. Like `pascal` but the first segment
/// keeps its original (lower) first byte.
pub fn camel(a: std.mem.Allocator, s: []const u8) []const u8 {
    var out = std.ArrayList(u8).initCapacity(a, s.len) catch @panic("OOM");
    var it = std.mem.splitScalar(u8, s, '_');
    var first = true;
    while (it.next()) |part| {
        if (part.len == 0) continue;
        const i = out.items.len;
        out.appendSliceAssumeCapacity(part);
        if (!first) out.items[i] = std.ascii.toUpper(part[0]);
        first = false;
    }
    return out.toOwnedSlice(a) catch @panic("OOM");
}

/// The casing used for enum entries. Segments are re-joined with `_`, but a
/// separator is only inserted when the *previous* segment was longer than one
/// byte, matching upstream: `unorm10__10__10__2` -> `unorm10_10_10_2`,
/// `BC4_R_unorm` -> `BC4_Runorm`.
pub fn enumEntry(a: std.mem.Allocator, s: []const u8) []const u8 {
    var out = std.ArrayList(u8).initCapacity(a, s.len) catch @panic("OOM");
    var it = std.mem.splitScalar(u8, s, '_');
    var prev_len: usize = 0;
    while (it.next()) |part| {
        if (part.len == 0) continue;
        if (prev_len > 1) out.appendSliceAssumeCapacity("_");
        out.appendSliceAssumeCapacity(part);
        prev_len = part.len;
    }
    return out.toOwnedSlice(a) catch @panic("OOM");
}

/// Escape a would-be identifier if it collides with a Zig keyword or starts with
/// a digit.
pub fn escape(a: std.mem.Allocator, s: []const u8) []const u8 {
    const needs = s.len == 0 or std.ascii.isDigit(s[0]) or keywords.has(s);
    if (!needs) return s;
    return std.fmt.allocPrint(a, "@\"{s}\"", .{s}) catch @panic("OOM");
}

pub fn snake(a: std.mem.Allocator, s: []const u8) []const u8 {
    return escape(a, s);
}

/// `wgpu` + PascalCase of each part, for C symbol names (`wgpuDeviceCreateBuffer`).
pub fn cSymbol(a: std.mem.Allocator, parts: []const []const u8) []const u8 {
    var out = std.ArrayList(u8).initCapacity(a, 8) catch @panic("OOM");
    out.appendSliceAssumeCapacity("wgpu");
    for (parts) |p| out.appendSlice(a, pascal(a, p)) catch @panic("OOM");
    return out.toOwnedSlice(a) catch @panic("OOM");
}

const keywords = std.StaticStringMap(void).initComptime(.{
    .{"addrspace"}, .{"align"},  .{"allowzero"},   .{"and"},         .{"anyframe"},
    .{"anytype"},   .{"asm"},    .{"async"},       .{"await"},       .{"break"},
    .{"callconv"},  .{"catch"},  .{"comptime"},    .{"const"},       .{"continue"},
    .{"defer"},     .{"else"},   .{"enum"},        .{"errdefer"},    .{"error"},
    .{"export"},    .{"extern"}, .{"false"},       .{"fn"},          .{"for"},
    .{"if"},        .{"inline"}, .{"linksection"}, .{"noalias"},     .{"noinline"},
    .{"nosuspend"}, .{"null"},   .{"opaque"},      .{"or"},          .{"orelse"},
    .{"packed"},    .{"pub"},    .{"resume"},      .{"return"},      .{"struct"},
    .{"suspend"},   .{"switch"}, .{"test"},        .{"threadlocal"}, .{"true"},
    .{"try"},       .{"union"},  .{"unreachable"}, .{"var"},         .{"volatile"},
    .{"while"},
});

test pascal {
    const a = std.testing.allocator;
    inline for (.{
        .{ "get_mapped_range", "GetMappedRange" },
        .{ "discrete_GPU", "DiscreteGPU" },
        .{ "BC4_R_unorm", "BC4RUnorm" },
        .{ "CPU", "CPU" },
        .{ "device", "Device" },
    }) |c| {
        const got = pascal(a, c[0]);
        defer a.free(got);
        try std.testing.expectEqualStrings(c[1], got);
    }
}

test camel {
    const a = std.testing.allocator;
    inline for (.{
        .{ "get_mapped_range", "getMappedRange" },
        .{ "submit", "submit" },
        .{ "request_adapter", "requestAdapter" },
    }) |c| {
        const got = camel(a, c[0]);
        defer a.free(got);
        try std.testing.expectEqualStrings(c[1], got);
    }
}

test enumEntry {
    const a = std.testing.allocator;
    inline for (.{
        .{ "discrete_GPU", "discrete_GPU" },
        .{ "shader_source_SPIRV", "shader_source_SPIRV" },
        .{ "BC4_R_unorm", "BC4_Runorm" },
        .{ "unorm10__10__10__2", "unorm10_10_10_2" },
        .{ "unorm8x4_B_G_R_A", "unorm8x4_BGRA" },
    }) |c| {
        const got = enumEntry(a, c[0]);
        defer a.free(got);
        try std.testing.expectEqualStrings(c[1], got);
    }
}

test escape {
    const a = std.testing.allocator;
    try std.testing.expectEqualStrings("device", escape(a, "device"));
    const kw = escape(a, "opaque");
    defer a.free(kw);
    try std.testing.expectEqualStrings("@\"opaque\"", kw);
    const dig = escape(a, "2d");
    defer a.free(dig);
    try std.testing.expectEqualStrings("@\"2d\"", dig);
}

test cSymbol {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const got = cSymbol(arena.allocator(), &.{ "device", "create_buffer" });
    try std.testing.expectEqualStrings("wgpuDeviceCreateBuffer", got);
}
