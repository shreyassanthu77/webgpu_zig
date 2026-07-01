const std = @import("std");

pub const String = extern struct {
    data: [*c]const u8,
    length: usize,

    /// The null string view (`{ NULL, 0 }`), matching a zero-initialized
    /// `WGPUStringView`. Distinct from an empty-but-non-null string.
    pub const NULL: String = .{ .data = null, .length = 0 };

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

pub const Proc = *const fn () callconv(.c) void;

extern fn wgpuGetProcAddress(procName: String) Proc;
pub inline fn getProcAddress(procName: []const u8) Proc {
    return wgpuGetProcAddress(String.from(procName));
}
