const std = @import("std");
const Schema = @import("Schema.zig");
const ZigType = @import("ZigType.zig");
const naming = @import("naming.zig");

pub const Mode = enum { extern_, wrapper, forward, wrapper_call };

pub const Param = union(enum) {
    /// One-to-one parameter (also used to model `self`).
    scalar: struct { name: []const u8, ty: ZigType },
    /// A `WGPUStringView`, exposed to callers as a Zig slice.
    string: struct { name: []const u8, nullable: bool },
    /// A `count`/`data` pair, exposed to callers as one slice.
    slice: struct {
        count_name: []const u8,
        data_name: []const u8,
        elem: ZigType,
        is_const: bool,
        optional: bool,
    },
    /// A `ptr`/`size` byte payload, exposed to callers as a `[]u8`.
    bytes: struct { name: []const u8, size_name: []const u8, is_const: bool },
    /// The trailing `callback_info` of an async function (identical in all modes).
    callback_info: struct { ty_name: []const u8 },

    pub fn render(self: Param, w: *std.Io.Writer, mode: Mode) !void {
        switch (self) {
            .scalar => |s| switch (mode) {
                .forward, .wrapper_call => try w.writeAll(s.name),
                else => {
                    try w.print("{s}: ", .{s.name});
                    try s.ty.format(w);
                },
            },
            .string => |s| switch (mode) {
                .extern_ => try w.print("{s}: String", .{s.name}),
                .wrapper => try w.print("{s}: {s}", .{ s.name, if (s.nullable) "?[]const u8" else "[]const u8" }),
                .wrapper_call => try w.writeAll(s.name),
                .forward => if (s.nullable)
                    try w.print("if ({s}) |v| String.from(v) else String.NULL", .{s.name})
                else
                    try w.print("String.from({s})", .{s.name}),
            },
            .slice => |s| switch (mode) {
                .extern_ => {
                    try w.print("{s}: usize, {s}: ", .{ s.count_name, s.data_name });
                    try w.writeAll(if (s.optional) "?[*]" else "[*]");
                    if (s.is_const) try w.writeAll("const ");
                    try s.elem.format(w);
                },
                // An optional slice in C ("may be null") is just an empty slice in
                // Zig; only the extern side keeps the nullable pointer.
                .wrapper => {
                    try w.print("{s}: []", .{s.data_name});
                    if (s.is_const) try w.writeAll("const ");
                    try s.elem.format(w);
                },
                .wrapper_call => try w.writeAll(s.data_name),
                .forward => if (s.optional)
                    try w.print("{s}.len, if ({s}.len == 0) null else {s}.ptr", .{ s.data_name, s.data_name, s.data_name })
                else
                    try w.print("{s}.len, {s}.ptr", .{ s.data_name, s.data_name }),
            },
            .bytes => |b| switch (mode) {
                .extern_ => try w.print("{s}: *{s}anyopaque, {s}: usize", .{ b.name, if (b.is_const) "const " else "", b.size_name }),
                .wrapper => try w.print("{s}: []{s}u8", .{ b.name, if (b.is_const) "const " else "" }),
                .wrapper_call => try w.writeAll(b.name),
                .forward => try w.print("{s}.ptr, {s}.len", .{ b.name, b.name }),
            },
            .callback_info => |c| switch (mode) {
                .forward, .wrapper_call => try w.writeAll("callback_info"),
                else => try w.print("callback_info: {s}", .{c.ty_name}),
            },
        }
    }
};

pub fn renderList(params: []const Param, w: *std.Io.Writer, mode: Mode) !void {
    for (params, 0..) |p, i| {
        if (i != 0) try w.writeAll(", ");
        try p.render(w, mode);
    }
}

fn isString(ty: Schema.Type) bool {
    return ty == .nullable_string or ty == .string_with_default_empty or ty == .out_string;
}

fn isSizeName(name: []const u8) bool {
    return std.mem.eql(u8, name, "size") or std.mem.endsWith(u8, name, "_size");
}

/// Classify a raw schema parameter list into logical params. Does not include
/// `self` or the trailing `callback_info`; the caller prepends/appends those.
pub fn classify(a: std.mem.Allocator, args: []const Schema.Parameter) []Param {
    var out = std.ArrayList(Param).initCapacity(a, args.len) catch @panic("OOM");
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (isString(arg.type)) {
            out.append(a, .{ .string = .{
                .name = naming.snake(a, arg.name),
                .nullable = arg.type == .nullable_string,
            } }) catch @panic("OOM");
            continue;
        }

        if (arg.type == .array) {
            out.append(a, .{ .slice = .{
                .count_name = std.fmt.allocPrint(a, "{s}_count", .{naming.snake(a, arg.name)}) catch @panic("OOM"),
                .data_name = naming.snake(a, arg.name),
                .elem = ZigType.element(a, arg.type.array.*),
                .is_const = arg.pointer != .mutable,
                .optional = arg.optional orelse false,
            } }) catch @panic("OOM");
            continue;
        }

        // `ptr` + `size` byte payload.
        if (arg.type == .c_void and arg.pointer != null and i + 1 < args.len) {
            const next = args[i + 1];
            if (next.type == .usize and isSizeName(next.name)) {
                out.append(a, .{ .bytes = .{
                    .name = naming.snake(a, arg.name),
                    .size_name = naming.snake(a, next.name),
                    .is_const = arg.pointer.? == .immutable,
                } }) catch @panic("OOM");
                i += 1;
                continue;
            }
        }

        // `count` + `data` pair.
        if (arg.type == .usize and std.mem.endsWith(u8, arg.name, "_count") and i + 1 < args.len) {
            const d = args[i + 1];
            if (d.pointer != null and d.type != .array) {
                out.append(a, .{ .slice = .{
                    .count_name = naming.snake(a, arg.name),
                    .data_name = naming.snake(a, d.name),
                    .elem = ZigType.element(a, d.type),
                    .is_const = d.pointer != .mutable,
                    .optional = d.optional orelse false,
                } }) catch @panic("OOM");
                i += 1;
                continue;
            }
        }

        out.append(a, .{ .scalar = .{
            .name = naming.snake(a, arg.name),
            .ty = ZigType.resolve(a, arg.type, arg.pointer, arg.optional orelse false),
        } }) catch @panic("OOM");
    }
    return out.toOwnedSlice(a) catch @panic("OOM");
}

fn expectRender(a: std.mem.Allocator, p: Param, mode: Mode, want: []const u8) !void {
    var aw = std.Io.Writer.Allocating.init(a);
    defer aw.deinit();
    try p.render(&aw.writer, mode);
    try std.testing.expectEqualStrings(want, aw.written());
}

test "slice renders three ways" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const p: Param = .{ .slice = .{
        .count_name = "commands_count",
        .data_name = "commands",
        .elem = ZigType.opt(a, ZigType.ptr(a, .one, false, ZigType.named("CommandBuffer"))),
        .is_const = true,
        .optional = false,
    } };
    try expectRender(a, p, .extern_, "commands_count: usize, commands: [*]const ?*CommandBuffer");
    try expectRender(a, p, .wrapper, "commands: []const ?*CommandBuffer");
    try expectRender(a, p, .forward, "commands.len, commands.ptr");
}

test "optional slice renders as plain slice" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const p: Param = .{ .slice = .{
        .count_name = "futures_count",
        .data_name = "futures",
        .elem = ZigType.named("FutureWaitInfo"),
        .is_const = false,
        .optional = true,
    } };
    try expectRender(a, p, .extern_, "futures_count: usize, futures: ?[*]FutureWaitInfo");
    try expectRender(a, p, .wrapper, "futures: []FutureWaitInfo");
    try expectRender(a, p, .forward, "futures.len, if (futures.len == 0) null else futures.ptr");
}

test "string renders three ways" {
    const a = std.testing.allocator;
    const p: Param = .{ .string = .{ .name = "label", .nullable = false } };
    try expectRender(a, p, .extern_, "label: String");
    try expectRender(a, p, .wrapper, "label: []const u8");
    try expectRender(a, p, .forward, "String.from(label)");
}

test "bytes renders three ways" {
    const a = std.testing.allocator;
    const p: Param = .{ .bytes = .{ .name = "data", .size_name = "size", .is_const = true } };
    try expectRender(a, p, .extern_, "data: *const anyopaque, size: usize");
    try expectRender(a, p, .wrapper, "data: []const u8");
    try expectRender(a, p, .forward, "data.ptr, data.len");
}

test "classify groups count/data" {
    const a = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    const ar = arena.allocator();

    const cb = try ar.create(Schema.Type);
    cb.* = .{ .object = "command_buffer" };
    const args = [_]Schema.Parameter{
        .{ .name = "commands", .doc = "", .type = .{ .array = cb }, .pointer = .immutable },
    };
    const params = classify(ar, &args);
    try std.testing.expectEqual(@as(usize, 1), params.len);
    try std.testing.expect(params[0] == .slice);
    try expectRender(ar, params[0], .wrapper, "commands: []const ?*CommandBuffer");
}
