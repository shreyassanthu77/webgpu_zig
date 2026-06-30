const std = @import("std");

bitflags: []const Bitflag,

const Bitflag = struct {
    name: []const u8,
    namespace: ?[]const u8 = null,
    doc: []const u8,
    extended: ?bool = null,
    entries: []const Entry,

    const Entry = struct {
        name: []const u8,
        namespace: ?[]const u8 = null,
        doc: []const u8,
        value: ?Value = null,
        value_combination: ?[]const []const u8 = null,

        const Value = union(enum) {
            u64: u64,
            nan: f32,

            pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !Value {
                const name_token: std.json.Token = try source.nextAllocMax(allocator, .alloc_if_needed, options.max_value_len.?);
                switch (name_token) {
                    .string => |s| {
                        if (std.mem.eql(u8, s, "usize_max")) {
                            return .{ .u64 = std.math.maxInt(u64) };
                        } else if (std.mem.eql(u8, s, "uint32_max")) {
                            return .{ .u64 = std.math.maxInt(u32) };
                        } else if (std.mem.eql(u8, s, "uint64_max")) {
                            return .{ .u64 = std.math.maxInt(u64) };
                        } else if (std.mem.eql(u8, s, "nan")) {
                            return .{ .nan = std.zig.c_translation.builtins.nanf("") };
                        } else {
                            return error.UnexpectedToken;
                        }
                    },
                    .number => |n| {
                        const value = std.fmt.parseInt(u64, n, 10) catch return error.UnexpectedToken;
                        return .{ .u64 = value };
                    },
                    else => return error.UnexpectedToken,
                }
            }
        };
    };
};
