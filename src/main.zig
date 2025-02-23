const std = @import("std");

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const StreamSource = @import("./stream_source.zig").StreamSource;

const Compiler = @import("./Compiler.zig");

fn usage() !void {
    std.log.err(
        \\usage: INPUT.zhex OUTPUT.something
    , .{});
    return error.Usage;
}

pub fn main() !void {
    var gpa_instance = std.heap.GeneralPurposeAllocator(.{}).init;
    defer _ = gpa_instance.deinit();
    const allocator = gpa_instance.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    _ = args.next() orelse return usage();
    const input_path_str = args.next() orelse return usage();
    if (eql(input_path_str, "-h") or
        eql(input_path_str, "--help")) return usage();
    const output_path_str = args.next() orelse return usage();
    if (args.next() != null) return usage();

    var input_file = try std.fs.cwd().openFile(input_path_str, .{});
    defer input_file.close();

    var output_file = try std.fs.cwd().createFile(output_path_str, .{});
    defer output_file.close();

    try zhexToBin(allocator, input_file, output_file);

    return std.process.cleanExit();
}

fn zhexToBin(input_file: std.fs.File, output_file: std.fs.File) !void {
    var compiler = Compiler.init(.{ .file = output_file });

    try compiler.feed(.{ .file = input_file });

    return compiler.flush();
}

fn eql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}
