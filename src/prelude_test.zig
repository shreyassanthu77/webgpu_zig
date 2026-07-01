const std = @import("std");

const prelude = @import("prelude.zig");
const c = @import("c");

test "String" {
    const Str = prelude.String;
    try std.testing.expectEqualStrings("hello", Str.from("hello").into());
    try std.testing.expectEqualStrings("", Str.from("").into());
    try std.testing.expectEqualStrings("", std.mem.zeroes(Str).into());
    try std.testing.expectEqualStrings("", (Str{ .data = null, .length = 200 }).into());
    try std.testing.expectEqualStrings("", (Str{ .data = "somthing", .length = 0 }).into());

    try std.testing.expectEqual(@sizeOf(c.WGPUStringView), @sizeOf(Str));
    try std.testing.expectEqual(@alignOf(c.WGPUStringView), @alignOf(Str));
    try std.testing.expectEqual(@offsetOf(c.WGPUStringView, "data"), @offsetOf(Str, "data"));
    try std.testing.expectEqual(@offsetOf(c.WGPUStringView, "length"), @offsetOf(Str, "length"));
}

test "Bool" {
    const Bool = prelude.Bool;

    try std.testing.expectEqual(Bool.true, Bool.from(true));
    try std.testing.expectEqual(Bool.false, Bool.from(false));

    try std.testing.expectEqual(true, Bool.true.into());
    try std.testing.expectEqual(false, Bool.false.into());

    try std.testing.expectEqual(Bool.Optional.true, Bool.Optional.from(true));
    try std.testing.expectEqual(Bool.Optional.false, Bool.Optional.from(false));
    try std.testing.expectEqual(Bool.Optional.undefined, Bool.Optional.from(null));

    try std.testing.expectEqual(true, Bool.Optional.true.into());
    try std.testing.expectEqual(false, Bool.Optional.false.into());
    try std.testing.expectEqual(null, Bool.Optional.undefined.into());

    try std.testing.expectEqual(true, Bool.Optional.true.truthy());
    try std.testing.expectEqual(false, Bool.Optional.false.truthy());
    try std.testing.expectEqual(false, Bool.Optional.undefined.truthy());

    try std.testing.expectEqual(@sizeOf(c.WGPUBool), @sizeOf(Bool));
    try std.testing.expectEqual(@alignOf(c.WGPUBool), @alignOf(Bool));
    try std.testing.expectEqual(@sizeOf(c.WGPUOptionalBool), @sizeOf(Bool.Optional));
    try std.testing.expectEqual(@alignOf(c.WGPUOptionalBool), @alignOf(Bool.Optional));
}
