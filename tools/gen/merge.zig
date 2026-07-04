const std = @import("std");
const Schema = @import("Schema.zig");

pub fn merge(arena: std.mem.Allocator, base: Schema, overlay: Schema) !Schema {
    var result = base;
    result.enums = try mergeEnums(arena, base.enums, overlay.enums);
    result.bitflags = try mergeBitflags(arena, base.bitflags, overlay.bitflags);
    result.objects = try mergeObjects(arena, base.objects, overlay.objects);
    result.structs = try concat(Schema.Struct, arena, base.structs, overlay.structs);
    result.callbacks = try concat(Schema.Callback, arena, base.callbacks, overlay.callbacks);
    result.functions = try concat(Schema.Function, arena, base.functions, overlay.functions);
    result.constants = try concat(Schema.Constant, arena, base.constants, overlay.constants);
    return result;
}

fn concat(
    comptime T: type,
    arena: std.mem.Allocator,
    base: []const T,
    overlay: []const T,
) ![]const T {
    var out = std.ArrayList(T).initCapacity(arena, base.len + overlay.len) catch @panic("OOM");
    for (base) |item| out.append(arena, item) catch @panic("OOM");
    for (overlay) |item| {
        if (findByName(T, base, item.name)) |_| {
            std.log.err("merge: duplicate '{s}' — overlays may only add new {s}", .{ item.name, @typeName(T) });
            return error.DuplicateName;
        }
        out.append(arena, item) catch @panic("OOM");
    }
    return out.toOwnedSlice(arena) catch @panic("OOM");
}

fn findByName(comptime T: type, slice: []const T, name: []const u8) ?T {
    for (slice) |item| if (std.mem.eql(u8, item.name, name)) return item;
    return null;
}

fn mergeEnums(arena: std.mem.Allocator, base: []const Schema.Enum, overlay: []const Schema.Enum) ![]const Schema.Enum {
    var out = std.ArrayList(Schema.Enum).initCapacity(arena, base.len + overlay.len) catch @panic("OOM");
    for (base) |en| out.append(arena, en) catch @panic("OOM");

    for (overlay) |ov| {
        if (findIndex(Schema.Enum, out.items, ov.name)) |idx| {
            out.items[idx].entries = try appendEntries(arena, out.items[idx].entries, ov.entries);
        } else {
            out.append(arena, ov) catch @panic("OOM");
        }
    }
    return out.toOwnedSlice(arena) catch @panic("OOM");
}

fn mergeBitflags(arena: std.mem.Allocator, base: []const Schema.Bitflag, overlay: []const Schema.Bitflag) ![]const Schema.Bitflag {
    var out = std.ArrayList(Schema.Bitflag).initCapacity(arena, base.len + overlay.len) catch @panic("OOM");
    for (base) |bf| out.append(arena, bf) catch @panic("OOM");

    for (overlay) |ov| {
        if (findIndex(Schema.Bitflag, out.items, ov.name)) |idx| {
            out.items[idx].entries = try appendBitflagEntries(arena, out.items[idx].entries, ov.entries);
        } else {
            out.append(arena, ov) catch @panic("OOM");
        }
    }
    return out.toOwnedSlice(arena) catch @panic("OOM");
}

fn mergeObjects(arena: std.mem.Allocator, base: []const Schema.Object, overlay: []const Schema.Object) ![]const Schema.Object {
    var out = std.ArrayList(Schema.Object).initCapacity(arena, base.len + overlay.len) catch @panic("OOM");
    for (base) |obj| out.append(arena, obj) catch @panic("OOM");

    for (overlay) |ov| {
        if (findIndex(Schema.Object, out.items, ov.name)) |idx| {
            if (ov.methods) |ov_methods| {
                const existing = out.items[idx].methods orelse &[_]Schema.Function{};
                const merged = try arena.alloc(Schema.Function, existing.len + ov_methods.len);
                @memcpy(merged[0..existing.len], existing);
                @memcpy(merged[existing.len..], ov_methods);
                out.items[idx].methods = merged;
            }
        } else {
            out.append(arena, ov) catch @panic("OOM");
        }
    }
    return out.toOwnedSlice(arena) catch @panic("OOM");
}

fn appendEntries(arena: std.mem.Allocator, base: []const ?Schema.Enum.Entry, overlay: []const ?Schema.Enum.Entry) ![]const ?Schema.Enum.Entry {
    var out = std.ArrayList(?Schema.Enum.Entry).initCapacity(arena, base.len + overlay.len) catch @panic("OOM");
    for (base) |e| out.append(arena, e) catch @panic("OOM");
    for (overlay) |e| out.append(arena, e) catch @panic("OOM");
    return out.toOwnedSlice(arena) catch @panic("OOM");
}

fn appendBitflagEntries(arena: std.mem.Allocator, base: []const Schema.Bitflag.Entry, overlay: []const Schema.Bitflag.Entry) ![]const Schema.Bitflag.Entry {
    var out = std.ArrayList(Schema.Bitflag.Entry).initCapacity(arena, base.len + overlay.len) catch @panic("OOM");
    for (base) |e| out.append(arena, e) catch @panic("OOM");
    for (overlay) |e| out.append(arena, e) catch @panic("OOM");
    return out.toOwnedSlice(arena) catch @panic("OOM");
}

fn findIndex(comptime T: type, slice: []const T, name: []const u8) ?usize {
    for (slice, 0..) |item, i| if (std.mem.eql(u8, item.name, name)) return i;
    return null;
}
