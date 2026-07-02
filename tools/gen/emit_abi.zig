const std = @import("std");
const Schema = @import("Schema.zig");
const naming = @import("naming.zig");
const Writer = @import("Writer.zig");

pub fn run(a: std.mem.Allocator, s: Schema, out: *std.Io.Writer) !void {
    var w = Writer.init(out);
    try w.print("const c = @import(\"c\");\n", .{});
    try w.print("const test_helpers = @import(\"test_helpers\");\n", .{});

    try w.line("test \"abi struct ChainedStruct\" {{", .{});
    try w.line("    try test_helpers.expectStructAbi(ChainedStruct, c.WGPUChainedStruct);", .{});
    try w.line("}}", .{});
    for (s.structs) |st| {
        const p = naming.pascal(a, st.name);
        try w.line("test \"abi struct {s}\" {{", .{p});
        try w.line("    try test_helpers.expectStructAbi({s}, c.WGPU{s});", .{ p, p });
        try w.line("}}", .{});
    }
    for (s.callbacks) |cb| {
        const p = naming.pascal(a, cb.name);
        try w.line("test \"abi struct {s}CallbackInfo\" {{", .{p});
        try w.line("    try test_helpers.expectStructAbi({s}CallbackInfo, c.WGPU{s}CallbackInfo);", .{ p, p });
        try w.line("}}", .{});
    }

    for (s.enums) |en| {
        if (std.mem.eql(u8, en.name, "optional_bool")) continue;
        const p = naming.pascal(a, en.name);
        try w.line("test \"abi enum {s}\" {{", .{p});
        try w.line("    try std.testing.expectEqual(@sizeOf(c.WGPU{s}), @sizeOf({s}));", .{ p, p });
        try w.line("    try std.testing.expectEqual(@alignOf(c.WGPU{s}), @alignOf({s}));", .{ p, p });
        try w.line("}}", .{});
    }

    for (s.bitflags) |bf| {
        const p = naming.pascal(a, bf.name);
        try w.line("test \"abi bitflag {s}\" {{", .{p});
        try w.line("    try std.testing.expectEqual(@sizeOf(c.WGPU{s}), @sizeOf({s}));", .{ p, p });
        var zero_seen = false;
        for (bf.entries) |en| {
            const cname = naming.pascal(a, en.name);
            if (en.value == null and en.value_combination == null) {
                if (!zero_seen) {
                    zero_seen = true;
                    try w.line("    try test_helpers.expectValueAbi(c.WGPU{s}, c.WGPU{s}_{s}, @bitCast({s}{{}}));", .{ p, p, cname, p });
                } else {
                    try w.line("    try test_helpers.expectValueAbi(c.WGPU{s}, c.WGPU{s}_{s}, @bitCast({s}{{ .{s} = true }}));", .{ p, p, cname, p, naming.snake(a, en.name) });
                }
            } else {
                try w.line("    try test_helpers.expectValueAbi(c.WGPU{s}, c.WGPU{s}_{s}, @bitCast({s}.{s}));", .{ p, p, cname, p, naming.snake(a, en.name) });
            }
        }
        try w.line("}}", .{});
    }

    for (s.objects) |obj| {
        const op = naming.pascal(a, obj.name);
        if (obj.methods) |methods| for (methods) |m| {
            try emitFnTest(&w, a, op, naming.cSymbol(a, &.{ obj.name, m.name }));
        };
        if (obj.extended != true) {
            try emitFnTest(&w, a, op, naming.cSymbol(a, &.{ obj.name, "add_ref" }));
            try emitFnTest(&w, a, op, naming.cSymbol(a, &.{ obj.name, "release" }));
        }
    }
    for (s.structs) |st| {
        if (st.free_members == true)
            try emitFnTest(&w, a, naming.pascal(a, st.name), naming.cSymbol(a, &.{ st.name, "free_members" }));
    }
    for (s.functions) |f| {
        const c_name = naming.cSymbol(a, &.{f.name});
        try w.line("test \"abi fn {s}\" {{", .{c_name});
        try w.line("    try test_helpers.expectFnAbi(@TypeOf({s}), c.WGPUProc{s});", .{ c_name, c_name[4..] });
        try w.line("}}", .{});
    }
}

fn emitFnTest(w: *Writer, a: std.mem.Allocator, container: []const u8, c_name: []const u8) !void {
    _ = a;
    try w.line("test \"abi fn {s}\" {{", .{c_name});
    try w.line("    try test_helpers.expectFnAbi(@TypeOf({s}.{s}), c.WGPUProc{s});", .{ container, c_name, c_name[4..] });
    try w.line("}}", .{});
}
