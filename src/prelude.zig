const std = @import("std");

pub const String = extern struct {
    data: [*c]const u8,
    length: usize,

    pub inline fn from(str: []const u8) String {
        return String{
            .data = @ptrCast(str.ptr),
            .length = str.len,
        };
    }

    pub fn into(self: String) []const u8 {
        if (self.length == 0 or self.data == null) return "";
        if (self.length == std.math.maxInt(usize)) return std.mem.span(self.data);
        return self.data[0..self.length];
    }
};

pub const Bool = enum(u32) {
    false = 0,
    true = 1,

    /// Converts a `bool` to a `Bool`
    pub inline fn from(value: bool) Bool {
        return @enumFromInt(@intFromBool(value));
    }

    /// Converts a `Bool` to a `bool`
    pub inline fn into(self: Bool) bool {
        return self == .true;
    }

    /// Converts a `Bool` to a `Bool.Optional`
    pub inline fn optional(self: Bool) Optional {
        return @enumFromInt(@intFromEnum(self));
    }

    pub const Optional = enum(u32) {
        false = 0,
        true = 1,
        undefined = 2,

        /// Converts a `?bool` to a `Bool.Optional`
        pub inline fn from(value: ?bool) Optional {
            return if (value) |v|
                @enumFromInt(@intFromBool(v))
            else
                .undefined;
        }

        /// Converts a `Bool.Optional` to a `?bool`
        pub inline fn into(self: Optional) ?bool {
            if (self == .undefined) return null;
            return self == .true;
        }

        /// **UNSAFE** in ReleaseFast builds
        /// Converts a `Bool.Optional` to a `bool`
        /// assumes that the value is not `.undefined`
        pub inline fn assert(self: Optional) bool {
            std.debug.assert(self != .undefined);
            return self == .true;
        }

        /// Converts a Bool.Optional to a `Bool`
        /// returns false if the value is `.undefined`
        pub inline fn truthy(self: Optional) bool {
            return self == .true;
        }
    };
};

test String {
    const Str = String;
    try std.testing.expectEqualStrings("hello", Str.from("hello").into());
    try std.testing.expectEqualStrings("", Str.from("").into());
    try std.testing.expectEqualStrings("", std.mem.zeroes(Str).into());
    try std.testing.expectEqualStrings("", (Str{ .data = null, .length = 200 }).into());
    try std.testing.expectEqualStrings("", (Str{ .data = "somthing", .length = 0 }).into());
}

test Bool {
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
}

pub const Proc = *const fn () callconv(.c) void;

extern fn wgpuGetProcAddress(procName: String) Proc;
pub inline fn getProcAddress(procName: []const u8) Proc {
    return wgpuGetProcAddress(String.from(procName));
}

test {
    _ = String;
    _ = Bool;
    _ = Proc;
}
