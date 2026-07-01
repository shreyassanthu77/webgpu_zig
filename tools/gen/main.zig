const std = @import("std");
const Schema = @import("Schema.zig");
const emit = @import("emit.zig");
const emit_abi = @import("emit_abi.zig");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const arena = init.arena.allocator();

    var args = try init.minimal.args.iterateAllocator(arena);
    defer args.deinit();
    _ = args.skip();

    const usage = "\nUsage: gen-bindings [--abi-checks] <webgpu.json> <out.zig> <prelude.zig>";

    var abi_checks = false;
    var first = args.next() orelse fail("missing <webgpu.json>" ++ usage);
    if (std.mem.eql(u8, first, "--abi-checks")) {
        abi_checks = true;
        first = args.next() orelse fail("missing <webgpu.json>" ++ usage);
    }
    const json_path = first;
    const out_path = args.next() orelse fail("missing <out.zig>" ++ usage);
    const prelude_path = args.next() orelse fail("missing <prelude.zig>" ++ usage);

    const json_src = try std.Io.Dir.cwd().readFileAlloc(init.io, json_path, gpa, .unlimited);
    defer gpa.free(json_src);

    const parsed = try std.json.parseFromSlice(Schema, gpa, json_src, .{
        .duplicate_field_behavior = .@"error",
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();

    const prelude_src = try std.Io.Dir.cwd().readFileAlloc(init.io, prelude_path, gpa, .unlimited);
    defer gpa.free(prelude_src);

    const out_file = try std.Io.Dir.cwd().createFile(init.io, out_path, .{ .truncate = true });
    defer out_file.close(init.io);

    var buf: [4096]u8 = undefined;
    var fw = out_file.writer(init.io, &buf);
    const w = &fw.interface;

    try w.writeAll(prelude_src);
    try w.writeAll("\n");
    try emit.run(arena, parsed.value, w);
    if (abi_checks) try emit_abi.run(arena, parsed.value, w);

    try w.flush();
}

fn fail(msg: []const u8) noreturn {
    std.log.err("{s}", .{msg});
    std.process.exit(1);
}
