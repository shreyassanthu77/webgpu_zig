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

/// Result of a synchronous (`...Sync`) wrapper around an async webgpu operation.
/// `ok` holds the operation's payload; `err` holds the failing status and its
/// message. Wait failures (from `waitAny`) are reported via the outer
/// `error{WaitFailed}` on the `...Sync` function, not here.
pub fn Result(comptime Stat: type, comptime Payload: type) type {
    return union(enum) {
        ok: Payload,
        err: struct { status: Stat, message: []const u8 },

        /// Returns the payload on success, or `error.WebGpuFailed` otherwise.
        /// Use a `switch` on the union directly if you need the status/message.
        pub fn unwrap(self: @This()) error{WebGpuFailed}!Payload {
            return switch (self) {
                .ok => |v| v,
                .err => error.WebGpuFailed,
            };
        }
    };
}

/// Copies a callback message (only valid during the callback) into a
/// thread-local buffer so it can outlive the callback. The returned slice is
/// valid until the next `...Sync` call on the same thread.
threadlocal var sync_msg_buf: [1024]u8 = undefined;
pub fn copyMessage(s: String) []const u8 {
    const src = s.into();
    const n = @min(src.len, sync_msg_buf.len);
    @memcpy(sync_msg_buf[0..n], src[0..n]);
    return sync_msg_buf[0..n];
}

pub const Proc = *const fn () callconv(.c) void;

extern fn wgpuGetProcAddress(procName: String) Proc;
pub inline fn getProcAddress(procName: []const u8) Proc {
    return wgpuGetProcAddress(String.from(procName));
}
