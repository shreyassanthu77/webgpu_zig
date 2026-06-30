const std = @import("std");

bitflags: []const Bitflag,
enums: []const Enum,
structs: []const Struct,
objects: []const Object,
callbacks: []const Callback,
functions: []const Function,
constants: []const Constant,

pub const Constant = struct {
    name: []const u8,
    namespace: ?[]const u8 = null,
    doc: []const u8,
    value: Value,

    const Value = union(enum) {
        u64: u64,
        nan: f32,

        pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !Value {
            const name_token: std.json.Token = try source.nextAllocMax(allocator, .alloc_if_needed, options.max_value_len.?);
            switch (name_token) {
                .string => |s| {
                    if (std.mem.eql(u8, s, "usize_max")) {
                        return .{ .u64 = std.math.maxInt(usize) };
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

pub const Bitflag = struct {
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

pub const Enum = struct {
    name: []const u8,
    namespace: ?[]const u8 = null,
    doc: []const u8,
    extended: ?bool = null,
    entries: []const ?Entry,

    const Entry = struct {
        name: []const u8,
        namespace: ?[]const u8 = null,
        doc: []const u8,
        value: ?u64 = null,
    };
};

pub const Struct = struct {
    name: []const u8,
    namespace: ?[]const u8 = null,
    doc: []const u8,
    type: StructType,
    extends: ?[]const []const u8 = null,
    free_members: ?bool = null,
    members: ?[]const Parameter = null,

    const StructType = enum {
        extensible,
        extensible_callback_arg,
        extension,
        standalone,
    };
};

pub const Object = struct {
    name: []const u8,
    namespace: ?[]const u8 = null,
    doc: ?[]const u8 = null,
    extended: ?bool = null,
    methods: ?[]const Function = null,
};

pub const Callback = struct {
    name: []const u8,
    namespace: ?[]const u8 = null,
    doc: []const u8,
    style: []const u8,
    args: ?[]const Parameter = null,
};

pub const Function = struct {
    name: []const u8,
    namespace: ?[]const u8 = null,
    doc: []const u8,
    returns: ?ReturnType = null,
    callback: ?[]const u8 = null,
    args: ?[]const Parameter = null,
};

pub const ReturnType = struct {
    doc: []const u8,
    type: Type,
    optional: ?bool = null,
    passed_with_ownership: ?bool = null,
    pointer: ?Parameter.Pointer = null,
};

pub const Parameter = struct {
    name: []const u8,
    doc: []const u8,
    type: Type,
    passed_with_ownership: ?bool = null,
    pointer: ?Pointer = null,
    optional: ?bool = null,
    default: ?Default = null,

    pub const Pointer = enum {
        immutable,
        mutable,
    };

    pub const Default = union(enum) {
        string: []const u8,
        number: f64,
        boolean: bool,

        pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !Default {
            const name_token: std.json.Token = try source.nextAllocMax(allocator, .alloc_if_needed, options.max_value_len.?);
            switch (name_token) {
                .string => |s| {
                    return .{ .string = s };
                },
                .number => |n| {
                    return .{ .number = std.fmt.parseFloat(f64, n) catch return error.UnexpectedToken };
                },
                .true, .false => {
                    return .{ .boolean = name_token == .true };
                },
                else => return error.UnexpectedToken,
            }
            return error.UnexpectedToken;
        }
    };
};

pub const Type = union(enum) {
    c_void,
    bool,
    nullable_string,
    string_with_default_empty,
    out_string,
    uint16,
    uint32,
    uint64,
    usize,
    int16,
    int32,
    float32,
    nullable_float32,
    float64,
    float64_supertype,
    array: *const Type,
    @"enum": []const u8,
    @"struct": []const u8,
    object: []const u8,
    bitflag: []const u8,
    callback: []const u8,

    pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !Type {
        const name_token: std.json.Token = try source.nextAllocMax(allocator, .alloc_if_needed, options.max_value_len.?);
        switch (name_token) {
            .string, .allocated_string => |s| {
                return parse(allocator, s);
            },
            else => {
                std.log.err("unexpected type '{}'", .{name_token});
                return error.UnexpectedToken;
            },
        }
    }

    fn parse(allocator: std.mem.Allocator, ty: []const u8) !Type {
        if (std.mem.startsWith(u8, ty, "array<")) {
            const child_type = try allocator.create(Type);
            errdefer allocator.destroy(child_type);
            child_type.* = try parse(allocator, ty[6 .. ty.len - 1]);
            return .{ .array = child_type };
        } else if (std.mem.startsWith(u8, ty, "enum.")) {
            const child = ty[5..ty.len];
            if (std.mem.eql(u8, child, "optional_bool")) {
                return .{ .@"enum" = "Bool.Optional" };
            }
            return .{ .@"enum" = ty[5..ty.len] };
        } else if (std.mem.startsWith(u8, ty, "struct.")) {
            return .{ .@"struct" = ty[7..ty.len] };
        } else if (std.mem.startsWith(u8, ty, "object.")) {
            return .{ .object = ty[7..ty.len] };
        } else if (std.mem.startsWith(u8, ty, "bitflag.")) {
            return .{ .bitflag = ty[8..ty.len] };
        } else if (std.mem.startsWith(u8, ty, "callback.")) {
            return .{ .callback = ty[9..ty.len] };
        } else {
            const Tag = @typeInfo(Type).@"union".tag_type.?;
            const tag: Tag = std.meta.stringToEnum(Tag, ty) orelse {
                std.log.err("unexpected type '{s}'", .{ty});
                return error.UnexpectedToken;
            };
            return switch (tag) {
                .array,
                .@"enum",
                .@"struct",
                .object,
                .bitflag,
                .callback,
                => unreachable,
                inline else => |t| @unionInit(Type, @tagName(t), {}),
            };
        }
    }
};
