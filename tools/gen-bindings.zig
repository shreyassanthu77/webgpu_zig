const std = @import("std");

fn generateBindings(gpa: std.mem.Allocator, bindings_json_str: []const u8, writer: *std.Io.Writer) !void {
    _ = .{ gpa, bindings_json_str, writer };
}

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    var args = try init.minimal.args.iterateAllocator(arena);
    defer args.deinit();
    _ = args.skip();

    const usage =
        \\
        \\Usage: zig run gen-bindings.zig <bindings_json_path> <output_path>
    ;
    const bindings_json_path = args.next() orelse {
        std.log.err("No bindings_json_path provided" ++ usage, .{});
        std.process.exit(1);
    };
    const output_path = args.next() orelse {
        std.log.err("No output_path provided" ++ usage, .{});
        std.process.exit(1);
    };

    const bindings_json_str = try std.Io.Dir.cwd().readFileAlloc(init.io, bindings_json_path, init.gpa, .unlimited);
    defer init.gpa.free(bindings_json_str);

    const output_file = try std.Io.Dir.cwd().createFile(init.io, output_path, .{
        .truncate = true,
        .read = false,
    });
    defer output_file.close(init.io);
    var output_file_writer_buffer: [4096]u8 = undefined;
    var output_file_writer = output_file.writer(init.io, &output_file_writer_buffer);
    try generateBindings(init.gpa, bindings_json_str, &output_file_writer.interface);
    try output_file_writer.flush();
}
