const std = @import("std");
const log = std.log.scoped(.gen_bindings);

const Schema = @import("schema.zig");

fn generateBindings(gpa: std.mem.Allocator, bindings_json_str: []const u8, writer: *std.Io.Writer) !void {
    const json_res = try std.json.parseFromSlice(Schema, gpa, bindings_json_str, .{
        .duplicate_field_behavior = .@"error",
        .ignore_unknown_fields = true,
    });
    defer json_res.deinit();
    const json = json_res.value;

    var arena_alloc = std.heap.ArenaAllocator.init(gpa);
    defer arena_alloc.deinit();
    const arena = arena_alloc.allocator();

    var gen = Generator{
        .arena = arena,
        .json = json,
        .writer = writer,
    };

    try gen.emitConstants();
    try gen.emitBitflags();
    try gen.emitEnums();
    try gen.emitChainedStruct();
    try gen.emitCallbacks();
    try gen.emitCallbackInfos();
    try gen.emitStructs();
    try gen.emitObjects();
    try gen.emitFunctions();
    try gen.emitTestBlock();
}

const Generator = struct {
    arena: std.mem.Allocator,
    json: Schema,
    writer: *std.Io.Writer,

    // --- lookups ---

    fn findBitflag(self: *const Generator, name: []const u8) ?Schema.Bitflag {
        for (self.json.bitflags) |bf| {
            if (std.mem.eql(u8, bf.name, name)) return bf;
        }
        return null;
    }

    fn findEnum(self: *const Generator, name: []const u8) ?Schema.Enum {
        for (self.json.enums) |en| {
            if (std.mem.eql(u8, en.name, name)) return en;
        }
        return null;
    }

    fn findStruct(self: *const Generator, name: []const u8) ?Schema.Struct {
        for (self.json.structs) |st| {
            if (std.mem.eql(u8, st.name, name)) return st;
        }
        return null;
    }

    fn enumHasEntry(self: *const Generator, enum_name: []const u8, entry_name: []const u8) bool {
        const en = self.findEnum(enum_name) orelse return false;
        for (en.entries) |maybe_entry| {
            if (maybe_entry) |entry| {
                if (std.mem.eql(u8, entry.name, entry_name)) return true;
            }
        }
        return false;
    }

    /// Find the SType enum value name that matches a given struct name.
    fn findSTypeForStruct(self: *const Generator, struct_name: []const u8) ?[]const u8 {
        const s_type_enum = self.findEnum("s_type") orelse return null;
        for (s_type_enum.entries) |maybe_entry| {
            if (maybe_entry) |entry| {
                if (std.mem.eql(u8, entry.name, struct_name)) return entry.name;
            }
        }
        return null;
    }

    // --- naming helpers ---

    fn pascalName(self: *const Generator, name: []const u8) []const u8 {
        return zid(self.arena, formatCase(self.arena, name, .pascal));
    }

    fn snakeName(self: *const Generator, name: []const u8) []const u8 {
        return zid(self.arena, formatCase(self.arena, name, .snake));
    }

    fn camelName(self: *const Generator, name: []const u8) []const u8 {
        return zid(self.arena, formatCase(self.arena, name, .camel));
    }

    fn mixedSnakeName(self: *const Generator, name: []const u8) []const u8 {
        return zid(self.arena, formatCase(self.arena, name, .mixed_snake));
    }

    /// C function name: wgpu{Pascal(Object)}{Pascal(Method)}
    fn cMethodName(self: *const Generator, object_name: []const u8, method_name: []const u8) []const u8 {
        return std.fmt.allocPrint(self.arena, "wgpu{s}{s}", .{
            formatCase(self.arena, object_name, .pascal),
            formatCase(self.arena, method_name, .pascal),
        }) catch @panic("OOM");
    }

    /// C function name for globals: wgpu{Pascal(Name)}
    fn cGlobalName(self: *const Generator, name: []const u8) []const u8 {
        return std.fmt.allocPrint(self.arena, "wgpu{s}", .{
            formatCase(self.arena, name, .pascal),
        }) catch @panic("OOM");
    }

    // --- type helpers ---

    /// Zig type for a base type (no pointer wrapping).
    fn baseType(self: *const Generator, ty: Schema.Type) []const u8 {
        return switch (ty) {
            .c_void => "anyopaque",
            .bool => "Bool",
            .nullable_string, .string_with_default_empty, .out_string => "String",
            .uint16 => "u16",
            .uint32 => "u32",
            .uint64 => "u64",
            .usize => "usize",
            .int16 => "i16",
            .int32 => "i32",
            .float32, .nullable_float32 => "f32",
            .float64, .float64_supertype => "f64",
            .array => |child| std.fmt.allocPrint(self.arena, "[*]const {s}", .{self.baseType(child.*)}) catch @panic("OOM"),
            .@"enum" => |child| self.pascalName(child),
            .@"struct" => |child| self.pascalName(child),
            .object => |child| std.fmt.allocPrint(self.arena, "{s}", .{self.pascalName(child)}) catch @panic("OOM"),
            .bitflag => |child| self.pascalName(child),
            .callback => |child| std.fmt.allocPrint(self.arena, "{s}CallbackInfo", .{self.pascalName(child)}) catch @panic("OOM"),
        };
    }

    /// Zig type for a struct member (may include pointer wrapping).
    fn memberType(self: *const Generator, param: Schema.Parameter) []const u8 {
        const base = self.baseType(param.type);
        return self.applyPointer(base, param.type, param.pointer, param.optional orelse false);
    }

    /// Zig type for a function/callback parameter.
    fn paramType(self: *const Generator, param: Schema.Parameter) []const u8 {
        if (param.type == .array) {
            const child_base = self.baseType(param.type.array.*);
            const ptr = self.applyPointer(child_base, param.type.array.*, param.pointer, param.optional orelse false);
            return ptr;
        }
        const base = self.baseType(param.type);
        return self.applyPointer(base, param.type, param.pointer, param.optional orelse false);
    }

    /// Zig type for a return type.
    fn returnType(self: *const Generator, ret: Schema.ReturnType) []const u8 {
        const base = self.baseType(ret.type);
        return self.applyPointer(base, ret.type, ret.pointer, ret.optional orelse false);
    }

    /// Apply pointer semantics: immutable→const, mutable→mut, optional→nullable.
    fn applyPointer(self: *const Generator, base: []const u8, ty: Schema.Type, pointer: ?Schema.Parameter.Pointer, optional: bool) []const u8 {
        const is_object = ty == .object;
        const is_c_void = ty == .c_void;

        if (pointer) |ptr| {
            const mut = ptr == .mutable;
            if (is_object) {
                // pointer to object handle: *const ?*T or *?*T (handle itself may be null)
                if (mut) {
                    if (optional) {
                        return std.fmt.allocPrint(self.arena, "?*?*{s}", .{base}) catch @panic("OOM");
                    } else {
                        return std.fmt.allocPrint(self.arena, "*?*{s}", .{base}) catch @panic("OOM");
                    }
                } else {
                    if (optional) {
                        return std.fmt.allocPrint(self.arena, "?*const ?*{s}", .{base}) catch @panic("OOM");
                    } else {
                        return std.fmt.allocPrint(self.arena, "*const ?*{s}", .{base}) catch @panic("OOM");
                    }
                }
            }
            if (mut) {
                if (optional) {
                    return std.fmt.allocPrint(self.arena, "?*{s}", .{base}) catch @panic("OOM");
                } else {
                    return std.fmt.allocPrint(self.arena, "*{s}", .{base}) catch @panic("OOM");
                }
            } else {
                if (optional) {
                    return std.fmt.allocPrint(self.arena, "?*const {s}", .{base}) catch @panic("OOM");
                } else {
                    return std.fmt.allocPrint(self.arena, "*const {s}", .{base}) catch @panic("OOM");
                }
            }
        }

        // No pointer field — objects are already pointers in C.
        if (is_object) {
            if (optional) {
                return std.fmt.allocPrint(self.arena, "?*{s}", .{base}) catch @panic("OOM");
            } else {
                return std.fmt.allocPrint(self.arena, "*{s}", .{base}) catch @panic("OOM");
            }
        }

        // c_void without pointer shouldn't normally happen for params, but handle it.
        if (is_c_void) {
            return std.fmt.allocPrint(self.arena, "?*{s}", .{base}) catch @panic("OOM");
        }

        return base;
    }

    /// Default value expression for a struct member, or null if no default.
    fn memberDefault(self: *const Generator, param: Schema.Parameter) ?[]const u8 {
        const optional = param.optional orelse false;

        // Arrays are handled separately in emitStructs (always nullable, default null).
        if (param.type == .array) return null;

        // Optional pointers/objects default to null. Non-optional ones have no default.
        if (param.pointer != null) {
            if (optional) return "null";
            return null;
        }
        if (param.type == .object) {
            if (optional) return "null";
            return null;
        }

        // c_void (non-pointer) — shouldn't happen in structs.
        if (param.type == .c_void) return "null";

        // Callbacks default to zero-init.
        if (param.type == .callback) {
            const info_name = std.fmt.allocPrint(self.arena, "{s}CallbackInfo", .{self.pascalName(param.type.callback)}) catch @panic("OOM");
            return std.fmt.allocPrint(self.arena, "std.mem.zeroes({s})", .{info_name}) catch @panic("OOM");
        }

        // Explicit default from JSON.
        if (param.default) |def| {
            return self.defaultValueExpr(param.type, def);
        }

        // Implicit defaults (matching C INIT macros).
        return self.implicitDefault(param.type);
    }

    fn defaultValueExpr(self: *const Generator, ty: Schema.Type, def: Schema.Parameter.Default) ?[]const u8 {
        switch (def) {
            .string => |s| {
                // constant.* → reference the constant by name
                if (std.mem.startsWith(u8, s, "constant.")) {
                    return self.snakeName(s[9..]);
                }
                // "zero" for structs
                if (std.mem.eql(u8, s, "zero")) {
                    if (ty == .@"struct") {
                        const struct_name = self.pascalName(ty.@"struct");
                        return std.fmt.allocPrint(self.arena, "std.mem.zeroes({s})", .{struct_name}) catch @panic("OOM");
                    }
                    return null;
                }
                // "none" for bitflags
                if (std.mem.eql(u8, s, "none")) {
                    if (ty == .bitflag) return ".{}";
                    return null;
                }
                // Named enum/bitflag value
                if (ty == .bitflag) {
                    return self.bitflagDefaultExpr(ty.bitflag, s);
                }
                if (ty == .@"enum") {
                    return std.fmt.allocPrint(self.arena, ".{s}", .{self.mixedSnakeName(s)}) catch @panic("OOM");
                }
                return null;
            },
            .number => |n| {
                return std.fmt.allocPrint(self.arena, "{d}", .{n}) catch @panic("OOM");
            },
            .boolean => |b| {
                if (ty == .bool) {
                    return if (b) "Bool.true" else "Bool.false";
                }
                return null;
            },
        }
    }

    /// Bitflag default: look up the entry to determine if it's a named const or a field.
    fn bitflagDefaultExpr(self: *const Generator, bitflag_name: []const u8, entry_name: []const u8) ?[]const u8 {
        const bf = self.findBitflag(bitflag_name) orelse return null;
        for (bf.entries) |entry| {
            if (std.mem.eql(u8, entry.name, entry_name)) {
                if (entry.value != null or entry.value_combination != null) {
                    // It's a pub const inside the bitflag struct.
                    const type_name = self.pascalName(bitflag_name);
                    return std.fmt.allocPrint(self.arena, "{s}.{s}", .{type_name, self.snakeName(entry_name)}) catch @panic("OOM");
                } else {
                    // It's a plain bool field.
                    return std.fmt.allocPrint(self.arena, ".{{ .{s} = true }}", .{self.snakeName(entry_name)}) catch @panic("OOM");
                }
            }
        }
        return null;
    }

    /// Implicit default (when JSON doesn't specify one but C INIT macro does).
    fn implicitDefault(self: *const Generator, ty: Schema.Type) ?[]const u8 {
        switch (ty) {
            .bool => return "Bool.false",
            .uint16, .uint32, .uint64, .usize, .int16, .int32 => return "0",
            .float32, .nullable_float32, .float64, .float64_supertype => return "0",
            .nullable_string, .string_with_default_empty, .out_string => return "std.mem.zeroes(String)",
            .bitflag => return ".{}",
            .@"enum" => |name| {
                // Bool.Optional (from enum.optional_bool) is defined in the prelude,
                // not in the JSON enums. C INIT uses WGPU_FALSE (0) = .false.
                if (std.mem.eql(u8, name, "Bool.Optional")) {
                    return ".false";
                }
                if (self.enumHasEntry(name, "undefined")) {
                    return std.fmt.allocPrint(self.arena, ".{s}", .{self.mixedSnakeName("undefined")}) catch @panic("OOM");
                }
                return null;
            },
            .@"struct" => |name| {
                const struct_name = self.pascalName(name);
                return std.fmt.allocPrint(self.arena, "std.mem.zeroes({s})", .{struct_name}) catch @panic("OOM");
            },
            .callback => {
                const info_name = std.fmt.allocPrint(self.arena, "{s}CallbackInfo", .{self.pascalName(ty.callback)}) catch @panic("OOM");
                return std.fmt.allocPrint(self.arena, "std.mem.zeroes({s})", .{info_name}) catch @panic("OOM");
            },
            .object, .c_void => return "null",
            .array => return null,
        }
    }

    // --- emitters ---

    fn emitConstants(self: *const Generator) !void {
        for (self.json.constants) |c| {
            try self.writer.writeAll(splitJoinNl(self.arena, c.doc, "\n/// ", "/// "));
            const val: []const u8 = switch (c.value) {
                .u64 => |v| std.fmt.allocPrint(self.arena, "{d}", .{v}) catch @panic("OOM"),
                .nan => "std.math.nan(f32)",
            };
            try self.writer.print("pub const {s} = {s};\n\n", .{ self.snakeName(c.name), val });
        }
    }

    fn emitBitflags(self: *const Generator) !void {
        for (self.json.bitflags) |bitflag| {
            _ = self.arena;
            std.debug.assert(bitflag.extended != true);

            try self.writer.writeAll(splitJoinNl(self.arena, bitflag.doc, "\n/// ", "/// "));
            try self.writer.print("pub const {s} = packed struct(u32) {{\n", .{self.pascalName(bitflag.name)});
            var idx: usize = 0;
            var has_combi_or_custom = false;
            for (bitflag.entries) |entry| {
                if (entry.value != null or entry.value_combination != null) {
                    has_combi_or_custom = true;
                } else {
                    try self.writer.writeAll(splitJoinNl(self.arena, entry.doc, "\n    /// ", "    /// "));
                    try self.writer.print("    {s}: bool = false,\n", .{self.snakeName(entry.name)});
                    idx += 1;
                }
            }

            const rest = 32 - idx;
            if (rest > 0) try self.writer.print("    _: u{d} = 0,\n", .{rest});

            if (has_combi_or_custom) try self.writer.print("\n", .{});

            for (bitflag.entries) |entry| {
                if (entry.value) |value| {
                    try self.writer.writeAll(splitJoinNl(self.arena, entry.doc, "\n    /// ", "    /// "));
                    try self.writer.print("    pub const {s}: @This() = @bitCast(@as(u32, 0x{x:>8})),\n", .{
                        self.snakeName(entry.name),
                        value.u64,
                    });
                } else if (entry.value_combination) |combi| {
                    try self.writer.writeAll(splitJoinNl(self.arena, entry.doc, "\n    /// ", "    /// "));
                    try self.writer.print("    pub const {s}: @This() = .{{\n", .{self.snakeName(entry.name)});
                    for (combi) |name| {
                        try self.writer.print("        .{s} = true,\n", .{self.snakeName(name)});
                    }
                    try self.writer.print("    }};\n", .{});
                }
            }

            try self.writer.print("}};\n\n", .{});
        }
    }

    fn emitEnums(self: *const Generator) !void {
        for (self.json.enums) |enum_| {
            std.debug.assert(enum_.extended != true);

            // special cased in prelude
            if (std.mem.eql(u8, enum_.name, "optional_bool")) continue;

            try self.writer.writeAll(splitJoinNl(self.arena, enum_.doc, "\n/// ", "/// "));
            try self.writer.print("pub const {s} = enum(u32) {{\n", .{self.pascalName(enum_.name)});
            var idx: usize = 0;
            for (enum_.entries) |maybe_entry| {
                if (maybe_entry) |entry| {
                    try self.writer.writeAll(splitJoinNl(self.arena, entry.doc, "\n    /// ", "    /// "));
                    try self.writer.print("    {s} = 0x{x:0>8},\n", .{
                        self.mixedSnakeName(entry.name),
                        entry.value orelse idx,
                    });
                }
                idx += 1;
            }
            try self.writer.print("    _,\n", .{});
            try self.writer.print("}};\n\n", .{});
        }
    }

    fn emitChainedStruct(self: *const Generator) !void {
        try self.writer.print("pub const ChainedStruct = extern struct {{\n", .{});
        try self.writer.print("    next: ?*ChainedStruct = null,\n", .{});
        try self.writer.print("    s_type: SType = .{s},\n", .{self.mixedSnakeName("undefined")});
        try self.writer.print("}};\n\n", .{});
    }

    fn emitCallbacks(self: *const Generator) !void {
        for (self.json.callbacks) |cb| {
            try self.writer.writeAll(splitJoinNl(self.arena, cb.doc, "\n/// ", "/// "));
            try self.writer.print("pub const {s}Callback = *const fn (\n", .{self.pascalName(cb.name)});

            if (cb.args) |args| {
                for (args) |arg| {
                    const ty = self.paramType(arg);
                    try self.writer.writeAll(splitJoinNl(self.arena, arg.doc, "\n    /// ", "    /// "));
                    try self.writer.print("    {s}: {s},\n", .{ self.snakeName(arg.name), ty });
                }
            }

            try self.writer.print("    userdata1: ?*anyopaque,\n", .{});
            try self.writer.print("    userdata2: ?*anyopaque,\n", .{});
            try self.writer.print(") callconv(.c) void;\n\n", .{});
        }
    }

    fn emitCallbackInfos(self: *const Generator) !void {
        for (self.json.callbacks) |cb| {
            const info_name = std.fmt.allocPrint(self.arena, "{s}CallbackInfo", .{self.pascalName(cb.name)}) catch @panic("OOM");
            try self.writer.writeAll(splitJoinNl(self.arena, cb.doc, "\n/// ", "/// "));
            try self.writer.print("pub const {s} = extern struct {{\n", .{info_name});
            try self.writer.print("    next_in_chain: ?*ChainedStruct = null,\n", .{});

            const has_mode = std.mem.eql(u8, cb.style, "callback_mode");
            if (has_mode) {
                try self.writer.print("    mode: CallbackMode = .{s},\n", .{self.mixedSnakeName("wait_any_only")});
            }

            try self.writer.print("    callback: ?{s}Callback = null,\n", .{self.pascalName(cb.name)});
            try self.writer.print("    userdata1: ?*anyopaque = null,\n", .{});
            try self.writer.print("    userdata2: ?*anyopaque = null,\n", .{});
            try self.writer.print("}};\n\n", .{});
        }
    }

    fn emitStructs(self: *const Generator) !void {
        for (self.json.structs) |st| {
            try self.writer.writeAll(splitJoinNl(self.arena, st.doc, "\n/// ", "/// "));
            try self.writer.print("pub const {s} = extern struct {{\n", .{self.pascalName(st.name)});

            // Extensible structs get next_in_chain.
            if (st.type == .extensible or st.type == .extensible_callback_arg) {
                try self.writer.print("    next_in_chain: ?*ChainedStruct = null,\n\n", .{});
            }

            // Extension structs get chain (with auto-detected sType default).
            if (st.type == .extension) {
                const s_type_name = self.findSTypeForStruct(st.name);
                if (s_type_name) |stn| {
                    try self.writer.print("    chain: ChainedStruct = .{{ .next = null, .s_type = .{s} }},\n\n", .{self.mixedSnakeName(stn)});
                } else {
                    try self.writer.print("    chain: ChainedStruct = .{{ .next = null, .s_type = .{s} }},\n\n", .{self.mixedSnakeName("undefined")});
                }
            }

            if (st.members) |members| {
                for (members) |member| {
                    try self.writer.writeAll(splitJoinNl(self.arena, member.doc, "\n    /// ", "    /// "));

                    if (member.type == .array) {
                        // Emit count field then data field.
                        const count_field = std.fmt.allocPrint(self.arena, "{s}_count", .{self.snakeName(member.name)}) catch @panic("OOM");
                        try self.writer.print("    {s}: usize = 0,\n", .{count_field});

                        // Array data is always nullable (NULL when count is 0).
                        const child_base = self.baseType(member.type.array.*);
                        const data_type = self.applyPointer(child_base, member.type.array.*, member.pointer, true);
                        const data_field = self.snakeName(member.name);
                        try self.writer.print("    {s}: {s} = null,\n", .{ data_field, data_type });
                    } else {
                        const field_type = self.memberType(member);
                        const field_name = self.snakeName(member.name);
                        if (self.memberDefault(member)) |default| {
                            try self.writer.print("    {s}: {s} = {s},\n", .{ field_name, field_type, default });
                        } else {
                            try self.writer.print("    {s}: {s},\n", .{ field_name, field_type });
                        }
                    }
                }
            }

            if (st.free_members == true) {
                if (st.members != null and st.members.?.len > 0) try self.writer.print("\n", .{});
                const c_fn = self.cGlobalName(std.fmt.allocPrint(self.arena, "{s}_free_members", .{st.name}) catch @panic("OOM"));
                try self.writer.print("    extern fn {s}(self: @This()) void;\n", .{c_fn});
                try self.writer.print("    pub const free = {s};\n", .{c_fn});
            }

            try self.writer.print("}};\n\n", .{});
        }
    }

    fn emitObjects(self: *const Generator) !void {
        for (self.json.objects) |obj| {
            try self.writer.writeAll(splitJoinNl(self.arena, obj.doc orelse "", "\n/// ", "/// "));
            try self.writer.print("pub const {s} = opaque {{\n", .{self.pascalName(obj.name)});

            const obj_name = self.pascalName(obj.name);

            if (obj.methods) |methods| {
                for (methods) |method| {
                    try self.emitMethod(obj_name, method);
                }
            }

            // Auto-add add_ref and release for non-extended objects.
            if (obj.extended != true) {
                try self.emitAddRefRelease(obj_name);
            }

            try self.writer.print("}};\n\n", .{});
        }
    }

    const Role = enum { plain, array, count, data, string, payload, payload_size };

    /// True when the parameter type is one of the C `WGPUString` variants.
    fn isStringType(ty: Schema.Type) bool {
        return ty == .nullable_string or ty == .string_with_default_empty or ty == .out_string;
    }

    /// True when the string variant represents a nullable C string (data may be NULL).
    fn isNullableString(ty: Schema.Type) bool {
        return ty == .nullable_string;
    }

    /// True when the usize param name belongs to a payload+size pair (`size` or `<x>_size`).
    fn isSizeName(name: []const u8) bool {
        return std.mem.eql(u8, name, "size") or std.mem.endsWith(u8, name, "_size");
    }

    /// Returns the underlying ABI type if `returns` is Bool-like (i.e. `Bool` or
    /// `Bool.Optional`), else null. Used to decide whether the inline wrapper should
    /// convert the extern's `Bool`/`Bool.Optional` return into a `bool`/`?bool`.
    fn boolReturnType(returns: ?Schema.ReturnType) ?Schema.Type {
        const r = returns orelse return null;
        if (r.type == .bool) return r.type;
        if (r.type == .@"enum" and std.mem.eql(u8, r.type.@"enum", "Bool.Optional")) return r.type;
        return null;
    }

    /// Element type of a slice, given the child element's `Type`.
    /// Objects become nullable handles (`?*T`); everything else uses its base Zig type.
    fn sliceElem(self: *const Generator, child: Schema.Type) []const u8 {
        return switch (child) {
            .object => |o| std.fmt.allocPrint(self.arena, "?*{s}", .{self.pascalName(o)}) catch @panic("OOM"),
            else => self.baseType(child),
        };
    }

    /// Extern data-pointer type for an array pair: `[*]const T`, `[*]T`, `?[*]const T`, `?[*]T`.
    fn externDataType(self: *const Generator, pointer: ?Schema.Parameter.Pointer, optional: bool, elem: []const u8) []const u8 {
        const is_const = pointer == null or pointer.? == .immutable;
        const prefix = if (optional) "?[*]" else "[*]";
        const cnst = if (is_const) "const " else "";
        return std.fmt.allocPrint(self.arena, "{s}{s}{s}", .{ prefix, cnst, elem }) catch @panic("OOM");
    }

    /// Zig slice type for an array pair: `[]const T`, `[]T`, `?[]const T`, `?[]T`.
    fn sliceType(self: *const Generator, pointer: ?Schema.Parameter.Pointer, optional: bool, elem: []const u8) []const u8 {
        const is_const = pointer == null or pointer.? == .immutable;
        const prefix = if (optional) "?[]" else "[]";
        const cnst = if (is_const) "const " else "";
        return std.fmt.allocPrint(self.arena, "{s}{s}{s}", .{ prefix, cnst, elem }) catch @panic("OOM");
    }

    /// Emits an extern fn plus either a `pub inline fn` wrapper (when the function takes a
    /// count+array pair) or a `pub const name = extern_fn` alias (otherwise).
    /// `indent` is the indentation prefix ("" for globals, "    " for object methods).
    /// `self_type` is null for global functions, or `*ObjectName` for methods.
    fn emitFunctionLike(
        self: *const Generator,
        indent: []const u8,
        c_name: []const u8,
        zig_name: []const u8,
        doc: []const u8,
        args: ?[]const Schema.Parameter,
        callback: ?[]const u8,
        returns: ?Schema.ReturnType,
        self_type: ?[]const u8,
    ) !void {
        const all_args = args orelse &[_]Schema.Parameter{};
        const n = all_args.len;

        // Classify each arg's role: plain, array (self-paired), or count/data pair.
        var roles = try self.arena.alloc(Role, n);
        for (roles) |*r| r.* = .plain;
        {
            var i: usize = 0;
            while (i < n) : (i += 1) {
                const arg = all_args[i];
                if (isStringType(arg.type)) {
                    roles[i] = .string;
                    continue;
                }
                if (arg.type == .array) {
                    roles[i] = .array;
                    continue;
                }
                // payload + size pair: c_void pointer followed by a usize named `size`/`<x>_size`.
                if (arg.type == .c_void and arg.pointer != null and i + 1 < n) {
                    const next = all_args[i + 1];
                    if (next.type == .usize and isSizeName(next.name)) {
                        roles[i] = .payload;
                        roles[i + 1] = .payload_size;
                        i += 1; // skip the size arg
                        continue;
                    }
                }
                if (arg.type == .usize and std.mem.endsWith(u8, arg.name, "_count") and i + 1 < n) {
                    const next = all_args[i + 1];
                    if (next.pointer != null and next.type != .array) {
                        roles[i] = .count;
                        roles[i + 1] = .data;
                        i += 1; // skip the data arg
                        continue;
                    }
                }
            }
        }

        const has_pair = blk: {
            for (roles) |r| if (r == .array or r == .count or r == .string or r == .payload) break :blk true;
            break :blk false;
        };
        const has_bool_ret = callback == null and boolReturnType(returns) != null;
        const needs_wrapper = has_pair or has_bool_ret;

        // Doc comment.
        const doc_sep = std.fmt.allocPrint(self.arena, "\n{s}/// ", .{indent}) catch @panic("OOM");
        const doc_pfx = std.fmt.allocPrint(self.arena, "{s}/// ", .{indent}) catch @panic("OOM");
        try self.writer.writeAll(splitJoinNl(self.arena, doc, doc_sep, doc_pfx));

        // Return type as emitted in the extern fn signature (Bool stays Bool here).
        const extern_ret: []const u8 = blk: {
            if (callback != null) break :blk "Future";
            if (returns) |r| break :blk self.returnType(r);
            break :blk "void";
        };
        // Return type as emitted in the inline wrapper signature — Bool → bool, Bool.Optional → ?bool.
        const wrapper_ret: []const u8 = blk: {
            if (callback != null) break :blk "Future";
            if (returns) |r| {
                if (r.type == .bool) break :blk "bool";
                if (r.type == .@"enum" and std.mem.eql(u8, r.type.@"enum", "Bool.Optional")) break :blk "?bool";
                break :blk self.returnType(r);
            }
            break :blk "void";
        };

        // CallbackInfo type, if async.
        var cb_info_type: ?[]const u8 = null;
        if (callback) |cb_name| {
            const cb_local = if (std.mem.startsWith(u8, cb_name, "callback.")) cb_name[9..] else cb_name;
            cb_info_type = std.fmt.allocPrint(self.arena, "{s}CallbackInfo", .{self.pascalName(cb_local)}) catch @panic("OOM");
        }

        // --- extern fn signature ---
        try self.writer.print("{s}extern fn {s}(", .{ indent, c_name });
        var first = true;
        if (self_type) |st| {
            try self.writer.print("self: {s}", .{st});
            first = false;
        }
        {
            var j: usize = 0;
            while (j < n) : (j += 1) {
                switch (roles[j]) {
                    .data => {},
                    .string => {
                        const arg = all_args[j];
                        if (!first) try self.writer.print(", ", .{});
                        try self.writer.print("{s}: String", .{self.snakeName(arg.name)});
                        first = false;
                    },
                    .array => {
                        const arg = all_args[j];
                        const count_name = std.fmt.allocPrint(self.arena, "{s}_count", .{self.snakeName(arg.name)}) catch @panic("OOM");
                        if (!first) try self.writer.print(", ", .{});
                        try self.writer.print("{s}: usize", .{count_name});
                        first = false;
                        const elem = self.sliceElem(arg.type.array.*);
                        const dt = self.externDataType(arg.pointer, arg.optional orelse false, elem);
                        try self.writer.print(", {s}: {s}", .{ self.snakeName(arg.name), dt });
                    },
                    .count => {
                        const c_arg = all_args[j];
                        if (!first) try self.writer.print(", ", .{});
                        try self.writer.print("{s}: usize", .{self.snakeName(c_arg.name)});
                        first = false;
                        const d_arg = all_args[j + 1];
                        const elem = self.sliceElem(d_arg.type);
                        const dt = self.externDataType(d_arg.pointer, d_arg.optional orelse false, elem);
                        try self.writer.print(", {s}: {s}", .{ self.snakeName(d_arg.name), dt });
                        j += 1; // skip the data arg
                    },
                    .payload => {
                        const arg = all_args[j];
                        if (!first) try self.writer.print(", ", .{});
                        const is_const = arg.pointer.? == .immutable;
                        const cnst = if (is_const) "const " else "";
                        try self.writer.print("{s}: [*]{s}anyopaque", .{ self.snakeName(arg.name), cnst });
                        first = false;
                        // Emit the matching size param after.
                        const sz_arg = all_args[j + 1];
                        try self.writer.print(", {s}: usize", .{self.snakeName(sz_arg.name)});
                        j += 1; // skip the size arg
                    },
                    .payload_size => {}, // handled by .payload
                    .plain => {
                        const arg = all_args[j];
                        const ty = self.paramType(arg);
                        if (!first) try self.writer.print(", ", .{});
                        try self.writer.print("{s}: {s}", .{ self.snakeName(arg.name), ty });
                        first = false;
                    },
                }
            }
        }
        if (cb_info_type) |ct| {
            if (!first) try self.writer.print(", ", .{});
            try self.writer.print("callback_info: {s}", .{ct});
            first = false;
        }
        try self.writer.print(") {s};\n", .{extern_ret});

        // --- pub const alias when there are no array/string/payload args and no Bool return ---
        if (!needs_wrapper) {
            try self.writer.print("{s}pub const {s} = {s};\n\n", .{ indent, zig_name, c_name });
            return;
        }

        // --- pub inline fn wrapper ---
        try self.writer.print("{s}pub inline fn {s}(", .{ indent, zig_name });
        first = true;
        if (self_type) |st| {
            try self.writer.print("self: {s}", .{st});
            first = false;
        }
        {
            var j: usize = 0;
            while (j < n) : (j += 1) {
                switch (roles[j]) {
                    .data => {},
                    .string => {
                        const arg = all_args[j];
                        const st: []const u8 = if (isNullableString(arg.type)) "?[]const u8" else "[]const u8";
                        if (!first) try self.writer.print(", ", .{});
                        try self.writer.print("{s}: {s}", .{ self.snakeName(arg.name), st });
                        first = false;
                    },
                    .array => {
                        const arg = all_args[j];
                        const elem = self.sliceElem(arg.type.array.*);
                        const st = self.sliceType(arg.pointer, arg.optional orelse false, elem);
                        if (!first) try self.writer.print(", ", .{});
                        try self.writer.print("{s}: {s}", .{ self.snakeName(arg.name), st });
                        first = false;
                    },
                    .count => {
                        const d_arg = all_args[j + 1];
                        const elem = self.sliceElem(d_arg.type);
                        const st = self.sliceType(d_arg.pointer, d_arg.optional orelse false, elem);
                        if (!first) try self.writer.print(", ", .{});
                        try self.writer.print("{s}: {s}", .{ self.snakeName(d_arg.name), st });
                        first = false;
                        j += 1; // skip the data arg
                    },
                    .payload => {
                        const arg = all_args[j];
                        const is_const = arg.pointer.? == .immutable;
                        const cnst = if (is_const) "const " else "";
                        if (!first) try self.writer.print(", ", .{});
                        try self.writer.print("{s}: []{s}anyopaque", .{ self.snakeName(arg.name), cnst });
                        first = false;
                        j += 1; // skip the size arg (folded into the slice)
                    },
                    .payload_size => {}, // handled by .payload
                    .plain => {
                        const arg = all_args[j];
                        const ty = self.paramType(arg);
                        if (!first) try self.writer.print(", ", .{});
                        try self.writer.print("{s}: {s}", .{ self.snakeName(arg.name), ty });
                        first = false;
                    },
                }
            }
        }
        if (cb_info_type) |ct| {
            if (!first) try self.writer.print(", ", .{});
            try self.writer.print("callback_info: {s}", .{ct});
            first = false;
        }
        try self.writer.print(") {s} {{\n", .{wrapper_ret});

        // inline body: forward to extern fn, unwrapping slices into .len/.ptr pairs.
        // For Bool-like returns, wrap the call in `( ... ).into()` to convert to bool/?bool.
        if (has_bool_ret) {
            try self.writer.print("{s}    return ({s}(", .{ indent, c_name });
        } else {
            try self.writer.print("{s}    return {s}(", .{ indent, c_name });
        }
        first = true;
        if (self_type != null) {
            try self.writer.print("self", .{});
            first = false;
        }
        {
            var j: usize = 0;
            while (j < n) : (j += 1) {
                switch (roles[j]) {
                    .data => {},
                    .string => {
                        const arg = all_args[j];
                        const name = self.snakeName(arg.name);
                        if (!first) try self.writer.print(", ", .{});
                        if (isNullableString(arg.type)) {
                            try self.writer.print("if ({s}) |s| String.from(s) else .{{ .data = null, .length = 0 }}", .{name});
                        } else {
                            try self.writer.print("String.from({s})", .{name});
                        }
                        first = false;
                    },
                    .array => {
                        const arg = all_args[j];
                        const name = self.snakeName(arg.name);
                        if (!first) try self.writer.print(", ", .{});
                        if (arg.optional orelse false) {
                            try self.writer.print("if ({s}) |s| s.len else 0, if ({s}) |s| s.ptr else null", .{ name, name });
                        } else {
                            try self.writer.print("{s}.len, {s}.ptr", .{ name, name });
                        }
                        first = false;
                    },
                    .count => {
                        const d_arg = all_args[j + 1];
                        const name = self.snakeName(d_arg.name);
                        if (!first) try self.writer.print(", ", .{});
                        if (d_arg.optional orelse false) {
                            try self.writer.print("if ({s}) |s| s.len else 0, if ({s}) |s| s.ptr else null", .{ name, name });
                        } else {
                            try self.writer.print("{s}.len, {s}.ptr", .{ name, name });
                        }
                        first = false;
                        j += 1; // skip the data arg
                    },
                    .payload => {
                        const arg = all_args[j];
                        const name = self.snakeName(arg.name);
                        if (!first) try self.writer.print(", ", .{});
                        try self.writer.print("{s}.ptr, {s}.len", .{ name, name });
                        first = false;
                        j += 1; // skip the size arg
                    },
                    .payload_size => {}, // handled by .payload
                    .plain => {
                        const arg = all_args[j];
                        if (!first) try self.writer.print(", ", .{});
                        try self.writer.print("{s}", .{self.snakeName(arg.name)});
                        first = false;
                    },
                }
            }
        }
        if (cb_info_type != null) {
            if (!first) try self.writer.print(", ", .{});
            try self.writer.print("callback_info", .{});
            first = false;
        }
        if (has_bool_ret) {
            try self.writer.print(")).into();\n{s}}}\n\n", .{indent});
        } else {
            try self.writer.print(");\n{s}}}\n\n", .{indent});
        }
    }

    fn emitMethod(self: *const Generator, obj_name: []const u8, method: Schema.Function) !void {
        const c_name = self.cMethodName(obj_name, method.name);
        const zig_name = self.camelName(method.name);
        const self_type = std.fmt.allocPrint(self.arena, "*{s}", .{obj_name}) catch @panic("OOM");
        try self.emitFunctionLike("    ", c_name, zig_name, method.doc, method.args, method.callback, method.returns, self_type);

        // Buffer.getMappedRange / getConstMappedRange: also emit slice-returning variants
        // that cast the raw *anyopaque to a [u8]/[]const u8 of the requested size.
        if (std.mem.eql(u8, obj_name, "Buffer")) {
            if (std.mem.eql(u8, method.name, "get_mapped_range")) {
                try self.writer.print(
                    "    pub inline fn getMappedRangeSlice(self: *Buffer, offset: usize, size: usize) []u8 {{\n" ++
                    "        return @as([*]u8, @ptrCast(@alignCast(wgpuBufferGetMappedRange(self, offset, size))))[0..size];\n" ++
                    "    }}\n\n",
                    .{},
                );
            } else if (std.mem.eql(u8, method.name, "get_const_mapped_range")) {
                try self.writer.print(
                    "    pub inline fn getConstMappedRangeSlice(self: *Buffer, offset: usize, size: usize) []const u8 {{\n" ++
                    "        return @as([*]const u8, @ptrCast(@alignCast(wgpuBufferGetConstMappedRange(self, offset, size))))[0..size];\n" ++
                    "    }}\n\n",
                    .{},
                );
            }
        }
    }

    fn emitAddRefRelease(self: *const Generator, obj_name: []const u8) !void {
        const add_ref_c = self.cMethodName(obj_name, "add_ref");
        const release_c = self.cMethodName(obj_name, "release");

        try self.writer.print("    extern fn {s}(self: *@This()) void;\n", .{add_ref_c});
        try self.writer.print("    pub const addRef = {s};\n\n", .{add_ref_c});
        try self.writer.print("    extern fn {s}(self: *@This()) void;\n", .{release_c});
        try self.writer.print("    pub const release = {s};\n", .{release_c});
    }

    fn emitFunctions(self: *const Generator) !void {
        for (self.json.functions) |func| {
            const c_name = self.cGlobalName(func.name);
            const zig_name = self.camelName(func.name);
            try self.emitFunctionLike("", c_name, zig_name, func.doc, func.args, func.callback, func.returns, null);
        }
    }

    /// Emits a `test` block that references every generated top-level decl via
    /// `std.testing.refAllDecls(@This())`. This forces type-level analysis of all
    /// declarations (catches undeclared identifiers, bad type refs, etc.) — the same
    /// level of coverage `refAllDecls` provides in any Zig project.
    fn emitTestBlock(self: *const Generator) !void {
        try self.writer.writeAll("\ntest {\n    std.testing.refAllDecls(@This());\n}\n");
    }
};

const Case = enum {
    camel,
    pascal,
    snake,
    mixed_snake,
};
fn formatCase(allocator: std.mem.Allocator, str: []const u8, case: Case) []const u8 {
    if (case == .snake) return str;
    var it = std.mem.splitScalar(u8, str, '_');
    var result = std.ArrayList(u8).initCapacity(allocator, str.len) catch @panic("OOM");

    var capitalize = case == .pascal;
    var prev_len: usize = 0;
    while (it.next()) |part| {
        if (part.len == 0) continue;

        if (case == .mixed_snake) {
            if (prev_len > 1) result.appendSliceAssumeCapacity("_");
        }

        const i = result.items.len;
        result.appendSliceAssumeCapacity(part);
        if (capitalize) result.items[i] = std.ascii.toUpper(part[0]);

        capitalize = case != .mixed_snake;
        prev_len = part.len;
    }
    return result.toOwnedSlice(allocator) catch @panic("OOM");
}

fn splitJoinNl(allocator: std.mem.Allocator, str: []const u8, new_separator: []const u8, prefix: ?[]const u8) []const u8 {
    const trimmed = std.mem.trim(u8, str, " \r\n");
    if (trimmed.len == 0 or std.mem.eql(u8, trimmed, "TODO")) return "";

    var it = std.mem.splitAny(u8, trimmed, "\r\n");
    // assumes most comments are about 6 lines
    var result = std.ArrayList(u8).initCapacity(allocator, str.len + 5 * new_separator.len) catch @panic("OOM");

    if (prefix) |p| result.appendSliceAssumeCapacity(p);
    if (it.next()) |line| result.appendSliceAssumeCapacity(line);
    while (it.next()) |line| {
        result.appendSlice(allocator, new_separator) catch @panic("OOM");
        result.appendSlice(allocator, line) catch @panic("OOM");
    }
    result.appendSlice(allocator, "\n") catch @panic("OOM");
    return result.toOwnedSlice(allocator) catch @panic("OOM");
}

const zig_kws = std.StaticStringMap(void).initComptime(&.{
    .{"align"},
    .{"allowzero"},
    .{"and"},
    .{"anytype"},
    .{"asm"},
    .{"async"},
    .{"await"},
    .{"break"},
    .{"callconv"},
    .{"catch"},
    .{"comptime"},
    .{"const"},
    .{"continue"},
    .{"defer"},
    .{"else"},
    .{"enum"},
    .{"errdefer"},
    .{"error"},
    .{"export"},
    .{"extern"},
    .{"false"},
    .{"fn"},
    .{"for"},
    .{"if"},
    .{"inline"},
    .{"linksection"},
    .{"noalias"},
    .{"noinline"},
    .{"nosuspend"},
    .{"null"},
    .{"opaque"},
    .{"or"},
    .{"pub"},
    .{"resume"},
    .{"return"},
    .{"struct"},
    .{"suspend"},
    .{"switch"},
    .{"test"},
    .{"threadlocal"},
    .{"true"},
    .{"try"},
    // .{"undefined"},
    .{"union"},
    .{"usingnamespace"},
    .{"var"},
    .{"volatile"},
    .{"while"},
});
/// Escapes a string if it is a zig keyword or starts with a digit.
fn zid(allocator: std.mem.Allocator, str: []const u8) []const u8 {
    const should_escape = zig_kws.has(str) or std.ascii.isDigit(str[0]);
    if (!should_escape) return str;
    return std.fmt.allocPrint(allocator, "@\"{s}\"", .{str}) catch @panic("OOM");
}

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    var args = try init.minimal.args.iterateAllocator(arena);
    defer args.deinit();
    _ = args.skip();

    const usage =
        \\
        \\Usage: zig run gen-bindings.zig <bindings_json_path> <output_path> <prelude_path>
    ;
    const bindings_json_path = args.next() orelse {
        std.log.err("No bindings_json_path provided" ++ usage, .{});
        std.process.exit(1);
    };
    const output_path = args.next() orelse {
        std.log.err("No output_path provided" ++ usage, .{});
        std.process.exit(1);
    };
    const prelude_path = args.next() orelse {
        std.log.err("No prelude_path provided" ++ usage, .{});
        std.process.exit(1);
    };

    const bindings_json_str = try std.Io.Dir.cwd().readFileAlloc(init.io, bindings_json_path, init.gpa, .unlimited);
    defer init.gpa.free(bindings_json_str);

    const output_file = try std.Io.Dir.cwd().createFile(init.io, output_path, .{
        .truncate = true,
        .read = false,
    });
    defer output_file.close(init.io);

    const prelude_file = try std.Io.Dir.cwd().openFile(init.io, prelude_path, .{});
    defer prelude_file.close(init.io);

    var prelude_file_reader_buffer: [4096]u8 = undefined;
    var prelude_file_reader = prelude_file.reader(init.io, &prelude_file_reader_buffer);

    var output_file_writer_buffer: [4096]u8 = undefined;
    var output_file_writer = output_file.writer(init.io, &output_file_writer_buffer);
    if (output_file_writer.interface.sendFileAll(&prelude_file_reader, .unlimited)) |_| {} else |err| switch (err) {
        error.ReadFailed => {
            if (output_file_writer.err.? != error.Unimplemented) return err;
            _ = try output_file_writer.interface.sendFileReadingAll(&prelude_file_reader, .unlimited);
        },
        else => return err,
    }
    try output_file_writer.interface.writeAll("\n");

    try generateBindings(init.gpa, bindings_json_str, &output_file_writer.interface);
    try output_file_writer.flush();
}
