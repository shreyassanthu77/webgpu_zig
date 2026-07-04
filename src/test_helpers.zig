const std = @import("std");

pub fn expectStructAbi(comptime Zig: type, comptime C: type) !void {
    try std.testing.expectEqual(@sizeOf(C), @sizeOf(Zig));
    try std.testing.expectEqual(@alignOf(C), @alignOf(Zig));
    const zf = comptime std.meta.fieldNames(Zig);
    const cf = comptime std.meta.fieldNames(C);
    try std.testing.expectEqual(cf.len, zf.len);
    inline for (zf, cf) |z, cc| {
        try std.testing.expectEqual(@offsetOf(C, cc), @offsetOf(Zig, z));
    }
}

pub fn expectValueAbi(comptime C: type, expected: u64, actual: u64) !void {
    try std.testing.expectEqual(@sizeOf(C), @sizeOf(u64));
    try std.testing.expectEqual(expected, actual);
}

pub fn fnTypeFromCProc(comptime CProc: type) type {
    return switch (@typeInfo(CProc)) {
        .optional => |o| fnTypeFromCProc(o.child),
        .pointer => |p| p.child,
        .@"fn" => CProc,
        else => @compileError("expected C proc to be a function, function pointer, or optional function pointer"),
    };
}

pub fn expectTypeAbi(comptime Zig: type, comptime C: type) !void {
    if (Zig == void or C == void) {
        try std.testing.expect(Zig == void and C == void);
        return;
    }
    try std.testing.expectEqual(@sizeOf(C), @sizeOf(Zig));
    try std.testing.expectEqual(@alignOf(C), @alignOf(Zig));
}

pub fn expectFnAbi(comptime ZigFn: type, comptime CProc: type) !void {
    const CFn = fnTypeFromCProc(CProc);
    const z_fn = @typeInfo(ZigFn).@"fn";
    const c_fn = @typeInfo(CFn).@"fn";

    const is_new_zig = !@hasField(@TypeOf(z_fn), "calling_convention");

    const z_call_conv = if (is_new_zig) z_fn.attrs.@"callconv" else z_fn.calling_convention;
    const c_call_conv = if (is_new_zig) c_fn.attrs.@"callconv" else c_fn.calling_convention;
    try std.testing.expectEqual(c_call_conv, z_call_conv);

    const z_is_var_args = if (is_new_zig) z_fn.attrs.varargs else z_fn.is_var_args;
    const c_is_var_args = if (is_new_zig) c_fn.attrs.varargs else c_fn.is_var_args;
    try std.testing.expectEqual(c_is_var_args, z_is_var_args);

    try expectTypeAbi(z_fn.return_type orelse void, c_fn.return_type orelse void);

    const z_params = if (is_new_zig) z_fn.param_types else z_fn.params;
    const c_params = if (is_new_zig) c_fn.param_types else c_fn.params;
    try std.testing.expectEqual(c_params.len, z_params.len);

    inline for (z_params, c_params) |zp, cp| {
        if (is_new_zig) {
            try expectTypeAbi(zp.?, cp.?);
        } else {
            try expectTypeAbi(zp.type.?, cp.type.?);
        }
    }
}

pub fn refAllDeclsRecursive(comptime T: type) void {
    inline for (comptime std.meta.declarations(T)) |declaration| {
        const decl = if (@typeInfo(@TypeOf(declaration)) == .@"struct") declaration.name else declaration;
        if (@TypeOf(@field(T, decl)) == type) {
            switch (@typeInfo(@field(T, decl))) {
                .@"struct", .@"enum", .@"union", .@"opaque" => refAllDeclsRecursive(@field(T, decl)),
                else => {},
            }
        }
        _ = &@field(T, decl);
    }
}
