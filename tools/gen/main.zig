const std = @import("std");
const Schema = @import("Schema.zig");
const emit = @import("emit.zig");
const emit_abi = @import("emit_abi.zig");
const merge = @import("merge.zig");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const arena = init.arena.allocator();

    var args = try init.minimal.args.iterateAllocator(arena);
    defer args.deinit();
    _ = args.skip();

    const usage = "\nUsage: gen-bindings [--abi-checks] <webgpu.json> [<extensions.json>] <out.zig> <prelude.zig>";

    var abi_checks = false;
    var first = args.next() orelse fail("missing <webgpu.json>" ++ usage);
    if (std.mem.eql(u8, first, "--abi-checks")) {
        abi_checks = true;
        first = args.next() orelse fail("missing <webgpu.json>" ++ usage);
    }

    var positional: std.ArrayList([]const u8) = .empty;
    try positional.append(arena, first);
    while (args.next()) |arg| try positional.append(arena, arg);

    const json_path: []const u8 = positional.items[0];
    const overlay_path: ?[]const u8 = switch (positional.items.len) {
        3 => null,
        4 => positional.items[1],
        else => fail(usage),
    };
    const out_path: []const u8 = switch (positional.items.len) {
        3 => positional.items[1],
        4 => positional.items[2],
        else => unreachable,
    };
    const prelude_path: []const u8 = switch (positional.items.len) {
        3 => positional.items[2],
        4 => positional.items[3],
        else => unreachable,
    };

    const json_src = try std.Io.Dir.cwd().readFileAlloc(init.io, json_path, gpa, .unlimited);
    defer gpa.free(json_src);

    const parsed = try std.json.parseFromSlice(Schema, gpa, json_src, .{
        .duplicate_field_behavior = .@"error",
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();

    var schema = parsed.value;

    var overlay_parsed: ?std.json.Parsed(Schema) = null;
    defer if (overlay_parsed) |op| op.deinit();

    var overlay_src: ?[]u8 = null;
    defer if (overlay_src) |src| gpa.free(src);

    if (overlay_path) |ov_path| {
        overlay_src = try std.Io.Dir.cwd().readFileAlloc(init.io, ov_path, gpa, .unlimited);

        overlay_parsed = try std.json.parseFromSlice(Schema, gpa, overlay_src.?, .{
            .duplicate_field_behavior = .@"error",
            .ignore_unknown_fields = true,
        });

        schema = try merge.merge(arena, schema, overlay_parsed.?.value);
    }

    const prelude_src = try std.Io.Dir.cwd().readFileAlloc(init.io, prelude_path, gpa, .unlimited);
    defer gpa.free(prelude_src);

    const out_file = try std.Io.Dir.cwd().createFile(init.io, out_path, .{ .truncate = true });
    defer out_file.close(init.io);

    var buf: [4096]u8 = undefined;
    var fw = out_file.writer(init.io, &buf);
    const w = &fw.interface;

    try w.writeAll(prelude_src);
    try w.writeAll("\n");
    try emit.run(arena, schema, w);
    if (abi_checks) try emit_abi.run(arena, schema, w);

    try w.flush();
}

fn fail(msg: []const u8) noreturn {
    std.log.err("{s}", .{msg});
    std.process.exit(1);
}
