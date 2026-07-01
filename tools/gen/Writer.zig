const std = @import("std");

const Writer = @This();

w: *std.Io.Writer,
depth: usize = 0,

pub fn init(w: *std.Io.Writer) Writer {
    return .{ .w = w };
}

fn indent(self: *Writer) !void {
    for (0..self.depth) |_| try self.w.writeAll("    ");
}

pub fn print(self: *Writer, comptime fmt: []const u8, args: anytype) !void {
    try self.w.print(fmt, args);
}

pub fn line(self: *Writer, comptime fmt: []const u8, args: anytype) !void {
    try self.indent();
    try self.w.print(fmt ++ "\n", args);
}

pub fn blank(self: *Writer) !void {
    try self.w.writeAll("\n");
}

/// Emit an indented line, then increase indentation by one level.
pub fn open(self: *Writer, comptime fmt: []const u8, args: anytype) !void {
    try self.line(fmt, args);
    self.depth += 1;
}

/// Decrease indentation by one level, then emit an indented line.
pub fn close(self: *Writer, comptime fmt: []const u8, args: anytype) !void {
    self.depth -= 1;
    try self.line(fmt, args);
}

/// One `///` per source line at the current indent. Blank input or the upstream
/// `TODO` placeholder emit nothing.
pub fn doc(self: *Writer, text: []const u8) !void {
    const trimmed = std.mem.trim(u8, text, " \r\n");
    if (trimmed.len == 0 or std.mem.eql(u8, trimmed, "TODO")) return;

    var it = std.mem.splitAny(u8, trimmed, "\r\n");
    while (it.next()) |raw| {
        const l = std.mem.trimEnd(u8, raw, " \r");
        try self.indent();
        try self.w.print("/// {s}\n", .{l});
    }
}
