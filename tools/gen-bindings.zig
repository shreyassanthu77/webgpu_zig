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

    for (json.bitflags) |bitflag| {
        _ = arena_alloc.reset(.retain_capacity);
        std.debug.assert(bitflag.extended != true);

        try writer.writeAll(splitJoinNl(arena, bitflag.doc, "\n/// ", "/// "));
        try writer.print("pub const {s} = packed struct(u32) {{\n", .{formatCase(arena, bitflag.name, .pascal)});
        var idx: usize = 0;
        var has_combi_or_custom = false;
        for (bitflag.entries) |entry| {
            if (entry.value) |_| {
                // handle in the next loop
                has_combi_or_custom = true;
            } else if (entry.value_combination) |_| {
                // handled in the next loop
                has_combi_or_custom = true;
            } else {
                try writer.writeAll(splitJoinNl(arena, entry.doc, "\n    /// ", "    /// "));
                try writer.print("    {s}: bool = false,\n", .{
                    formatCase(arena, entry.name, .snake),
                });
                idx += 1;
            }
        }

        const rest = 32 - idx;
        if (rest > 0) try writer.print("    _: u{d} = 0,\n", .{rest});

        if (has_combi_or_custom) try writer.print("\n", .{});

        _ = arena_alloc.reset(.retain_capacity);
        for (bitflag.entries) |entry| {
            if (entry.value) |value| {
                try writer.writeAll(splitJoinNl(arena, entry.doc, "\n    /// ", "    /// "));
                try writer.print("    pub const {s}: @This() = @bitCast(@as(u32, 0x{x:>8})),\n", .{
                    formatCase(arena, entry.name, .snake),
                    value.u64,
                });
            } else if (entry.value_combination) |combi| {
                try writer.writeAll(splitJoinNl(arena, entry.doc, "\n    /// ", "    /// "));
                try writer.print("    pub const {s}: @This() = .{{\n", .{
                    formatCase(arena, entry.name, .snake),
                });
                for (combi) |name| {
                    try writer.print("        .{s} = true,\n", .{
                        formatCase(arena, name, .snake),
                    });
                }
                try writer.print("    }};\n", .{});
            } else {
                // already handled above
            }
        }

        try writer.print("}};\n\n", .{});
    }
}

const Case = enum {
    camel,
    pascal,
    snake,
};
fn formatCase(allocator: std.mem.Allocator, str: []const u8, case: Case) []const u8 {
    if (case == .snake) return str;
    var it = std.mem.splitScalar(u8, str, '_');
    var result = std.ArrayList(u8).initCapacity(allocator, str.len) catch @panic("OOM");

    var capitalize = case == .pascal;
    while (it.next()) |part| {
        const i = result.items.len;
        result.appendSliceAssumeCapacity(part);
        if (capitalize) result.items[i] = std.ascii.toUpper(part[0]);
        capitalize = true;
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
