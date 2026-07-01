const std = @import("std");
const Schema = @import("Schema.zig");
const ZigType = @import("ZigType.zig");
const params = @import("params.zig");
const naming = @import("naming.zig");
const Writer = @import("Writer.zig");

const Emit = @This();

a: std.mem.Allocator,
s: Schema,
w: *Writer,

pub fn run(a: std.mem.Allocator, s: Schema, out: *std.Io.Writer) !void {
    var w = Writer.init(out);
    var e = Emit{ .a = a, .s = s, .w = &w };
    try e.emitConstants();
    try e.emitBitflags();
    try e.emitEnums();
    try e.emitChainedStruct();
    try e.emitCallbacks();
    try e.emitCallbackInfos();
    try e.emitStructs();
    try e.emitObjects();
    try e.emitFunctions();
    try w.line("test {{", .{});
    try w.line("    std.testing.refAllDecls(@This());", .{});
    try w.line("}}", .{});
}

fn pascal(e: *Emit, s: []const u8) []const u8 {
    return naming.escape(e.a, naming.pascal(e.a, s));
}
fn camel(e: *Emit, s: []const u8) []const u8 {
    return naming.escape(e.a, naming.camel(e.a, s));
}
fn snake(e: *Emit, s: []const u8) []const u8 {
    return naming.snake(e.a, s);
}
fn entry(e: *Emit, s: []const u8) []const u8 {
    return naming.escape(e.a, naming.enumEntry(e.a, s));
}
fn infoName(e: *Emit, cb: []const u8) []const u8 {
    const local = if (std.mem.startsWith(u8, cb, "callback.")) cb[9..] else cb;
    return std.fmt.allocPrint(e.a, "{s}CallbackInfo", .{naming.pascal(e.a, local)}) catch @panic("OOM");
}
fn typeStr(e: *Emit, t: ZigType) []const u8 {
    return t.toString(e.a);
}

fn findBitflag(e: *Emit, name: []const u8) ?Schema.Bitflag {
    for (e.s.bitflags) |bf| if (std.mem.eql(u8, bf.name, name)) return bf;
    return null;
}
fn enumHasEntry(e: *Emit, enum_name: []const u8, entry_name: []const u8) bool {
    for (e.s.enums) |en| {
        if (!std.mem.eql(u8, en.name, enum_name)) continue;
        for (en.entries) |me| if (me) |en_entry| {
            if (std.mem.eql(u8, en_entry.name, entry_name)) return true;
        };
    }
    return false;
}
fn sTypeForStruct(e: *Emit, struct_name: []const u8) ?[]const u8 {
    for (e.s.enums) |en| {
        if (!std.mem.eql(u8, en.name, "s_type")) continue;
        for (en.entries) |me| if (me) |en_entry| {
            if (std.mem.eql(u8, en_entry.name, struct_name)) return en_entry.name;
        };
    }
    return null;
}

fn emitConstants(e: *Emit) !void {
    for (e.s.constants) |c| {
        try e.w.doc(c.doc);
        const val: []const u8 = switch (c.value) {
            .u64 => |v| std.fmt.allocPrint(e.a, "{d}", .{v}) catch @panic("OOM"),
            .max => |t| switch (t) {
                .usize => "std.math.maxInt(usize)",
                .u32 => "std.math.maxInt(u32)",
                .u64 => "std.math.maxInt(u64)",
            },
            .nan => "std.math.nan(f32)",
        };
        try e.w.line("pub const {s} = {s};", .{ e.snake(c.name), val });
        try e.w.blank();
    }
}

fn emitBitflags(e: *Emit) !void {
    for (e.s.bitflags) |bf| {
        std.debug.assert(bf.extended != true);
        try e.w.doc(bf.doc);
        try e.w.open("pub const {s} = packed struct(u64) {{", .{e.pascal(bf.name)});

        // The first "plain" entry (no value/combination) is the all-zero value; it
        // becomes a named `= .{}` constant, NOT bit 0. Every following plain entry
        // occupies the next bit. (The old generator gave bit 0 to this zero entry,
        // shifting every real flag by one — a real ABI bug the abi tests now catch.)
        var zero_entry: ?Schema.Bitflag.Entry = null;
        var bits: usize = 0;
        for (bf.entries) |en| {
            if (en.value != null or en.value_combination != null) continue;
            if (zero_entry == null) {
                zero_entry = en;
                continue;
            }
            try e.w.doc(en.doc);
            try e.w.line("{s}: bool = false,", .{e.snake(en.name)});
            bits += 1;
        }
        if (bits < 64) try e.w.line("_: u{d} = 0,", .{64 - bits});

        try e.w.blank();
        if (zero_entry) |z| {
            try e.w.doc(z.doc);
            try e.w.line("pub const {s}: @This() = .{{}};", .{e.snake(z.name)});
        }
        for (bf.entries) |en| {
            if (en.value) |v| {
                try e.w.doc(en.doc);
                try e.w.line("pub const {s}: @This() = @bitCast(@as(u64, 0x{x}));", .{ e.snake(en.name), v.u64 });
            } else if (en.value_combination) |combo| {
                try e.w.doc(en.doc);
                try e.w.open("pub const {s}: @This() = .{{", .{e.snake(en.name)});
                for (combo) |m| try e.w.line(".{s} = true,", .{e.snake(m)});
                try e.w.close("}};", .{});
            }
        }
        try e.w.close("}};", .{});
        try e.w.blank();
    }
}

fn emitEnums(e: *Emit) !void {
    for (e.s.enums) |en| {
        std.debug.assert(en.extended != true);
        if (std.mem.eql(u8, en.name, "optional_bool")) continue; // provided by the prelude

        try e.w.doc(en.doc);
        try e.w.open("pub const {s} = enum(u32) {{", .{e.pascal(en.name)});
        var idx: usize = 0;
        for (en.entries) |me| {
            if (me) |en_entry| {
                try e.w.doc(en_entry.doc);
                try e.w.line("{s} = 0x{x:0>8},", .{ e.entry(en_entry.name), en_entry.value orelse idx });
            }
            idx += 1;
        }
        try e.w.line("_,", .{});
        try e.w.close("}};", .{});
        try e.w.blank();
    }
}

fn emitChainedStruct(e: *Emit) !void {
    try e.w.open("pub const ChainedStruct = extern struct {{", .{});
    try e.w.line("next: ?*ChainedStruct = null,", .{});
    // No INIT default for sType in C; SType is non-exhaustive with no `undefined`
    // entry, so leave it required and let extension structs set it via `chain`.
    try e.w.line("s_type: SType,", .{});
    try e.w.close("}};", .{});
    try e.w.blank();
}

fn emitCallbacks(e: *Emit) !void {
    for (e.s.callbacks) |cb| {
        try e.w.doc(cb.doc);
        try e.w.open("pub const {s}Callback = *const fn (", .{e.pascal(cb.name)});
        if (cb.args) |args| for (args) |arg| {
            try e.w.doc(arg.doc);
            try e.w.line("{s}: {s},", .{ e.snake(arg.name), e.typeStr(e.rawType(arg.type, arg.pointer, arg.optional orelse false)) });
        };
        try e.w.line("userdata1: ?*anyopaque,", .{});
        try e.w.line("userdata2: ?*anyopaque,", .{});
        try e.w.close(") callconv(.c) void;", .{});
        try e.w.blank();
    }
}

fn emitCallbackInfos(e: *Emit) !void {
    for (e.s.callbacks) |cb| {
        try e.w.doc(cb.doc);
        try e.w.open("pub const {s}CallbackInfo = extern struct {{", .{e.pascal(cb.name)});
        try e.w.line("next_in_chain: ?*ChainedStruct = null,", .{});
        if (std.mem.eql(u8, cb.style, "callback_mode"))
            try e.w.line("mode: CallbackMode = .wait_any_only,", .{});
        try e.w.line("callback: ?{s}Callback = null,", .{e.pascal(cb.name)});
        try e.w.line("userdata1: ?*anyopaque = null,", .{});
        try e.w.line("userdata2: ?*anyopaque = null,", .{});
        try e.w.close("}};", .{});
        try e.w.blank();
    }
}

fn emitStructs(e: *Emit) !void {
    for (e.s.structs) |st| {
        try e.w.doc(st.doc);
        try e.w.open("pub const {s} = extern struct {{", .{e.pascal(st.name)});

        if (st.type == .extensible or st.type == .extensible_callback_arg) {
            try e.w.line("next_in_chain: ?*ChainedStruct = null,", .{});
            try e.w.blank();
        } else if (st.type == .extension) {
            if (e.sTypeForStruct(st.name)) |stn|
                try e.w.line("chain: ChainedStruct = .{{ .next = null, .s_type = .{s} }},", .{e.entry(stn)})
            else
                try e.w.line("chain: ChainedStruct = .{{ .next = null, .s_type = @enumFromInt(0) }},", .{});
            try e.w.blank();
        }

        if (st.members) |members| for (members) |m| {
            try e.w.doc(m.doc);
            if (m.type == .array) {
                const elem = ZigType.element(e.a, m.type.array.*);
                const data = ZigType.opt(e.a, ZigType.ptr(e.a, .many, m.pointer != .mutable, elem));
                try e.w.line("{s}_count: usize = 0,", .{e.snake(m.name)});
                try e.w.line("{s}: {s} = null,", .{ e.snake(m.name), e.typeStr(data) });
            } else {
                const ty = e.typeStr(ZigType.resolve(e.a, m.type, m.pointer, m.optional orelse false));
                if (e.memberDefault(m)) |def|
                    try e.w.line("{s}: {s} = {s},", .{ e.snake(m.name), ty, def })
                else
                    try e.w.line("{s}: {s},", .{ e.snake(m.name), ty });
            }
        };

        if (st.free_members == true) {
            try e.w.blank();
            const c_fn = naming.cSymbol(e.a, &.{ st.name, "free_members" });
            try e.w.line("extern fn {s}(self: @This()) void;", .{c_fn});
            try e.w.line("pub const free = {s};", .{c_fn});
        }

        if (st.type == .extension) if (st.extends) |parents| if (parents.len == 1) {
            try e.w.blank();
            try e.w.open("pub inline fn {s}(self: *const @This()) {s} {{", .{ e.camel(parents[0]), e.pascal(parents[0]) });
            try e.w.line("return .{{ .next_in_chain = @constCast(&self.chain) }};", .{});
            try e.w.close("}}", .{});
        };

        try e.w.close("}};", .{});
        try e.w.blank();
    }
}

fn emitObjects(e: *Emit) !void {
    for (e.s.objects) |obj| {
        try e.w.doc(obj.doc orelse "");
        try e.w.open("pub const {s} = opaque {{", .{e.pascal(obj.name)});

        const self_ty = std.fmt.allocPrint(e.a, "*{s}", .{e.pascal(obj.name)}) catch @panic("OOM");
        if (obj.methods) |methods| for (methods) |m| {
            const c_name = naming.cSymbol(e.a, &.{ obj.name, m.name });
            try e.emitFunctionLike(c_name, e.camel(m.name), m.doc, m.args, m.callback, m.returns, self_ty);
            try e.emitBufferSpecials(obj.name, m.name);
        };

        if (obj.extended != true) {
            const add_ref = naming.cSymbol(e.a, &.{ obj.name, "add_ref" });
            const release = naming.cSymbol(e.a, &.{ obj.name, "release" });
            try e.w.line("extern fn {s}(self: *@This()) void;", .{add_ref});
            try e.w.line("pub const addRef = {s};", .{add_ref});
            try e.w.blank();
            try e.w.line("extern fn {s}(self: *@This()) void;", .{release});
            try e.w.line("pub const release = {s};", .{release});
        }

        try e.w.close("}};", .{});
        try e.w.blank();
    }
}

fn emitFunctions(e: *Emit) !void {
    for (e.s.functions) |f| {
        const c_name = naming.cSymbol(e.a, &.{f.name});
        try e.emitFunctionLike(c_name, e.camel(f.name), f.doc, f.args, f.callback, f.returns, null);
    }
}

const Return = struct {
    extern_ty: []const u8,
    wrapper_ty: []const u8,
    into: bool, // wrap the extern call in `( ... ).into()`
};

fn returnInfo(e: *Emit, callback: ?[]const u8, returns: ?Schema.ReturnType) Return {
    if (callback != null) return .{ .extern_ty = "Future", .wrapper_ty = "Future", .into = false };
    const r = returns orelse return .{ .extern_ty = "void", .wrapper_ty = "void", .into = false };
    if (r.type == .bool) return .{ .extern_ty = "Bool", .wrapper_ty = "bool", .into = true };
    if (r.type == .@"enum" and std.mem.eql(u8, r.type.@"enum", "Bool.Optional"))
        return .{ .extern_ty = "Bool.Optional", .wrapper_ty = "?bool", .into = true };
    const ty = e.typeStr(ZigType.resolve(e.a, r.type, r.pointer, r.optional orelse false));
    return .{ .extern_ty = ty, .wrapper_ty = ty, .into = false };
}

fn emitFunctionLike(
    e: *Emit,
    c_name: []const u8,
    zig_name: []const u8,
    doc: []const u8,
    args: ?[]const Schema.Parameter,
    callback: ?[]const u8,
    returns: ?Schema.ReturnType,
    self_ty: ?[]const u8,
) !void {
    var list: std.ArrayList(params.Param) = .empty;
    if (self_ty) |st| try list.append(e.a, .{ .scalar = .{ .name = "self", .ty = ZigType.named(st) } });
    if (args) |a| try list.appendSlice(e.a, params.classify(e.a, a));
    if (callback) |cb| try list.append(e.a, .{ .callback_info = .{ .ty_name = e.infoName(cb) } });
    const all = list.items;

    const ret = e.returnInfo(callback, returns);

    try e.w.doc(doc);
    try e.w.line("extern fn {s}({s}) {s};", .{ c_name, e.renderList(all, .extern_), ret.extern_ty });

    try e.w.doc(doc);
    try e.w.open("pub inline fn {s}({s}) {s} {{", .{ zig_name, e.renderList(all, .wrapper), ret.wrapper_ty });
    if (ret.into)
        try e.w.line("return ({s}({s})).into();", .{ c_name, e.renderList(all, .forward) })
    else
        try e.w.line("return {s}({s});", .{ c_name, e.renderList(all, .forward) });
    try e.w.close("}}", .{});
    try e.w.blank();
}

fn emitBufferSpecials(e: *Emit, obj: []const u8, method: []const u8) !void {
    if (!std.mem.eql(u8, obj, "buffer")) return;
    if (std.mem.eql(u8, method, "get_mapped_range")) {
        try e.w.open("pub inline fn getMappedRangeSlice(self: *Buffer, offset: usize, size: usize) []u8 {{", .{});
        try e.w.line("return @as([*]u8, @ptrCast(wgpuBufferGetMappedRange(self, offset, size)))[0..size];", .{});
        try e.w.close("}}", .{});
        try e.w.blank();
    } else if (std.mem.eql(u8, method, "get_const_mapped_range")) {
        try e.w.open("pub inline fn getConstMappedRangeSlice(self: *Buffer, offset: usize, size: usize) []const u8 {{", .{});
        try e.w.line("return @as([*]const u8, @ptrCast(wgpuBufferGetConstMappedRange(self, offset, size)))[0..size];", .{});
        try e.w.close("}}", .{});
        try e.w.blank();
    }
}

fn renderList(e: *Emit, list: []const params.Param, mode: params.Mode) []const u8 {
    var aw = std.Io.Writer.Allocating.init(e.a);
    params.renderList(list, &aw.writer, mode) catch @panic("OOM");
    return aw.toOwnedSlice() catch @panic("OOM");
}

/// The raw (ABI-faithful) Zig type of a parameter as used in callbacks and
/// function-pointer typedefs — arrays become a single element pointer rather than
/// a slice pair.
fn rawType(e: *Emit, ty: Schema.Type, pointer: ?Schema.Parameter.Pointer, optional: bool) ZigType {
    if (ty == .array) return ZigType.resolve(e.a, ty.array.*, pointer, optional);
    return ZigType.resolve(e.a, ty, pointer, optional);
}

fn memberDefault(e: *Emit, m: Schema.Parameter) ?[]const u8 {
    const optional = m.optional orelse false;
    if (m.type == .array) return null;
    if (m.pointer != null) return if (optional) "null" else null;
    if (m.type == .object) return if (optional) "null" else null;
    if (m.type == .c_void) return "null";
    if (m.type == .callback) return std.fmt.allocPrint(e.a, "std.mem.zeroes({s})", .{e.infoName(m.type.callback)}) catch @panic("OOM");
    if (m.default) |def| return e.defaultExpr(m.type, def);
    return e.implicitDefault(m.type);
}

fn defaultExpr(e: *Emit, ty: Schema.Type, def: Schema.Parameter.Default) ?[]const u8 {
    switch (def) {
        .string => |s| {
            if (std.mem.startsWith(u8, s, "constant.")) return e.snake(s[9..]);
            if (std.mem.eql(u8, s, "zero")) {
                if (ty == .@"struct") return std.fmt.allocPrint(e.a, "std.mem.zeroes({s})", .{e.pascal(ty.@"struct")}) catch @panic("OOM");
                return null;
            }
            if (std.mem.eql(u8, s, "none")) return if (ty == .bitflag) ".{}" else null;
            if (ty == .bitflag) return e.bitflagDefault(ty.bitflag, s);
            if (ty == .@"enum") return std.fmt.allocPrint(e.a, ".{s}", .{e.entry(s)}) catch @panic("OOM");
            // Numeric literal given as a string (e.g. "0xFFFFFFFF") on an integer field.
            if (isIntType(ty) and looksNumeric(s)) return s;
            return null;
        },
        .number => |n| return std.fmt.allocPrint(e.a, "{d}", .{n}) catch @panic("OOM"),
        .boolean => |b| return if (ty == .bool) (if (b) "Bool.true" else "Bool.false") else null,
    }
}

fn bitflagDefault(e: *Emit, bitflag_name: []const u8, entry_name: []const u8) ?[]const u8 {
    const bf = e.findBitflag(bitflag_name) orelse return null;
    for (bf.entries) |en| {
        if (!std.mem.eql(u8, en.name, entry_name)) continue;
        if (en.value != null or en.value_combination != null)
            return std.fmt.allocPrint(e.a, "{s}.{s}", .{ e.pascal(bitflag_name), e.snake(entry_name) }) catch @panic("OOM");
        return std.fmt.allocPrint(e.a, ".{{ .{s} = true }}", .{e.snake(entry_name)}) catch @panic("OOM");
    }
    return null;
}

fn implicitDefault(e: *Emit, ty: Schema.Type) ?[]const u8 {
    return switch (ty) {
        .bool => "Bool.false",
        .uint16, .uint32, .uint64, .usize, .int16, .int32 => "0",
        .float32, .nullable_float32, .float64, .float64_supertype => "0",
        .nullable_string, .string_with_default_empty, .out_string => "String.NULL",
        .bitflag => ".{}",
        .@"enum" => |name| blk: {
            if (std.mem.eql(u8, name, "Bool.Optional")) break :blk ".false";
            if (e.enumHasEntry(name, "undefined")) break :blk ".undefined";
            break :blk null;
        },
        .@"struct" => |name| std.fmt.allocPrint(e.a, "std.mem.zeroes({s})", .{e.pascal(name)}) catch @panic("OOM"),
        .callback => |name| std.fmt.allocPrint(e.a, "std.mem.zeroes({s})", .{e.infoName(name)}) catch @panic("OOM"),
        .object, .c_void => "null",
        .array => null,
    };
}

fn isIntType(ty: Schema.Type) bool {
    return switch (ty) {
        .uint16, .uint32, .uint64, .usize, .int16, .int32 => true,
        else => false,
    };
}

fn looksNumeric(s: []const u8) bool {
    if (s.len == 0) return false;
    if (std.mem.startsWith(u8, s, "0x") or std.mem.startsWith(u8, s, "0X")) return true;
    for (s) |c| if (!std.ascii.isDigit(c)) return false;
    return true;
}
