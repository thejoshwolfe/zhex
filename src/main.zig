const std = @import("std");

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const StreamSource = @import("./stream_source.zig").StreamSource;

const ZhexCompiler = @import("./ZhexCompiler.zig");

fn usage() !void {
    std.log.err(
        \\usage: INPUT.zhex OUTPUT.something
    , .{});
    return error.Usage;
}

const max_line_length = 0x1000;

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

fn zhexToBin(allocator: Allocator, input_file: std.fs.File, output_file: std.fs.File) !void {
    var buffered_reader = std.io.bufferedReader(input_file.reader());
    const input = buffered_reader.reader().any();

    var compiler = ZhexCompiler.init(.{ .file = output_file });

    var line_buffer = try ArrayList(u8).initCapacity(allocator, max_line_length);
    defer line_buffer.deinit();
    while (try readLine(input, &line_buffer)) |line| {
        try compiler.handleLine(line);
    }

    return compiler.flush();
}

fn readLine(input: std.io.AnyReader, line_buffer: *ArrayList(u8)) !?[]const u8 {
    line_buffer.clearRetainingCapacity();
    input.streamUntilDelimiter(line_buffer.writer(), '\n', max_line_length) catch |err| switch (err) {
        error.EndOfStream => {}, // Effectively the same as finding the delimiter.
        error.StreamTooLong => return error.LineTooLong,
        else => |e| return e,
    };
    const line = line_buffer.items;
    if (line.len == 0) return null;
    return line;
}

fn eql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}
