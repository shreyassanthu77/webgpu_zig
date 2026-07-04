const std = @import("std");
const naming = @import("naming.zig");
const Schema = @import("Schema.zig");

const ZigType = @This();

tag: union(enum) {
    named: []const u8,
    optional: *const ZigType,
    pointer: struct {
        size: enum { one, many },
        is_const: bool,
        child: *const ZigType,
    },
},

pub fn format(self: ZigType, w: *std.Io.Writer) !void {
    switch (self.tag) {
        .named => |n| try w.writeAll(n),
        .optional => |c| {
            try w.writeByte('?');
            try c.format(w);
        },
        .pointer => |p| {
            try w.writeAll(if (p.size == .many) "[*]" else "*");
            if (p.is_const) try w.writeAll("const ");
            try p.child.format(w);
        },
    }
}

pub fn toString(self: ZigType, a: std.mem.Allocator) []const u8 {
    var aw = std.Io.Writer.Allocating.init(a);
    self.format(&aw.writer) catch @panic("OOM");
    return aw.toOwnedSlice() catch @panic("OOM");
}

pub fn named(name: []const u8) ZigType {
    return .{ .tag = .{ .named = name } };
}

fn box(a: std.mem.Allocator, t: ZigType) *const ZigType {
    const p = a.create(ZigType) catch @panic("OOM");
    p.* = t;
    return p;
}

pub fn opt(a: std.mem.Allocator, child: ZigType) ZigType {
    return .{ .tag = .{ .optional = box(a, child) } };
}

pub fn ptr(a: std.mem.Allocator, size: enum { one, many }, is_const: bool, child: ZigType) ZigType {
    return .{ .tag = .{ .pointer = .{
        .size = if (size == .many) .many else .one,
        .is_const = is_const,
        .child = box(a, child),
    } } };
}

/// Object handles resolve to a bare `*Name`; `resolve` applies outer wrapping.
/// Arrays are lowered as slice pairs by the caller, not here.
pub fn base(a: std.mem.Allocator, ty: Schema.Type) ZigType {
    return switch (ty) {
        .c_void => named("anyopaque"),
        .bool => named("Bool"),
        .u8 => named("u8"),
        .nullable_string, .string_with_default_empty, .out_string => named("String"),
        .uint16 => named("u16"),
        .uint32 => named("u32"),
        .uint64 => named("u64"),
        .usize => named("usize"),
        .int16 => named("i16"),
        .int32 => named("i32"),
        .float32, .nullable_float32 => named("f32"),
        .float64, .float64_supertype => named("f64"),
        .@"enum" => |n| named(naming.pascal(a, n)),
        .@"struct" => |n| named(naming.pascal(a, n)),
        .bitflag => |n| named(naming.pascal(a, n)),
        .object => |n| named(naming.pascal(a, n)),
        .callback => |n| named(std.fmt.allocPrint(a, "{s}CallbackInfo", .{naming.pascal(a, n)}) catch @panic("OOM")),
        .raw_callback => |n| named(std.fmt.allocPrint(a, "{s}Callback", .{naming.pascal(a, n)}) catch @panic("OOM")),
        .array => unreachable, // arrays are lowered as slices/pairs by the caller
    };
}

/// The Zig element type of an array/slice member. Object elements become
/// nullable handles (`?*Name`); everything else is its plain base type.
pub fn element(a: std.mem.Allocator, ty: Schema.Type) ZigType {
    return switch (ty) {
        .object => |n| opt(a, ptr(a, .one, false, named(naming.pascal(a, n)))),
        else => base(a, ty),
    };
}

/// Resolve a single (non-array) schema type together with its pointer/optional
/// flags into the concrete Zig type used in signatures and struct fields.
pub fn resolve(a: std.mem.Allocator, ty: Schema.Type, pointer: ?Schema.Parameter.Pointer, optional: bool) ZigType {
    if (ty == .object) {
        const handle_name = base(a, ty); // Name
        if (pointer) |p| {
            // pointer to a (nullable) handle: `*const ?*Name` / `*?*Name` / `?*...`
            const inner = opt(a, ptr(a, .one, false, handle_name));
            const t = ptr(a, .one, p == .immutable, inner);
            return if (optional) opt(a, t) else t;
        }
        // bare handle: `*Name` / `?*Name`
        const t = ptr(a, .one, false, handle_name);
        return if (optional) opt(a, t) else t;
    }

    const b = base(a, ty);
    if (pointer) |p| {
        const t = ptr(a, .one, p == .immutable, b);
        return if (optional) opt(a, t) else t;
    }
    if (ty == .c_void) return opt(a, ptr(a, .one, false, b)); // `?*anyopaque`
    return b;
}

test resolve {
    const a = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    const ar = arena.allocator();

    inline for (.{
        .{ Schema.Type{ .uint32 = {} }, null, false, "u32" },
        .{ Schema.Type{ .uint32 = {} }, .immutable, false, "*const u32" },
        .{ Schema.Type{ .uint32 = {} }, .mutable, true, "?*u32" },
        .{ Schema.Type{ .object = "adapter" }, null, false, "*Adapter" },
        .{ Schema.Type{ .object = "adapter" }, null, true, "?*Adapter" },
        .{ Schema.Type{ .object = "adapter" }, .immutable, false, "*const ?*Adapter" },
        .{ Schema.Type{ .object = "device" }, .mutable, false, "*?*Device" },
        .{ Schema.Type{ .c_void = {} }, null, false, "?*anyopaque" },
        .{ Schema.Type{ .@"struct" = "extent_3D" }, .immutable, true, "?*const Extent3D" },
    }) |c| {
        const t = resolve(ar, c[0], c[1], c[2]);
        const got = t.toString(ar);
        try std.testing.expectEqualStrings(c[3], got);
    }
}
