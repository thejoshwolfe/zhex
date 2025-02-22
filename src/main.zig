const std = @import("std");

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

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

    var buffered_output = std.io.bufferedWriter(output_file.writer());
    const output = buffered_output.writer().any();

    var compiler = ZhexCompiler.init(output);

    var line_buffer = ArrayList(u8).init(allocator);
    defer line_buffer.deinit();
    while (try readLine(input, &line_buffer)) |line| {
        try compiler.handleLine(line);
    }

    return buffered_output.flush();
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

const ZhexCompiler = struct {
    output: std.io.AnyWriter,

    pub fn init(output: std.io.AnyWriter) ZhexCompiler {
        return .{
            .output = output,
        };
    }

    pub fn handleLine(self: *ZhexCompiler, _line: []const u8) !void {
        var line = _line;
        // Skip leading whitespace.
        while (line.len > 0 and line[0] == ' ') line = line[1..];
        if (line.len == 0 or startsWith(line, ";")) {
            // Blank or comment.
        } else if (startsWith(line, ":0x")) {
            @panic("TODO: offset assertion");
        } else {
            // Values
            try self.handleValues(line);
        }
    }

    fn handleValues(self: *ZhexCompiler, _line: []const u8) !void {
        var line = _line;
        mainLoop: while (line.len > 0) {
            while (line[0] == ' ') {
                line = line[1..];
                continue :mainLoop;
            }
            if (line.len < 2) return error.SyntaxError;
            if (line[0] == '"') {
                @panic("TODO: string values");
            } else if (startsWith(line, "0x")) {
                @panic("TODO: little endian hex values");
            } else {
                const nibbles = line[0..2];
                const value = (try nibbleFromHex(nibbles[0]) << 4) | (try nibbleFromHex(nibbles[1]));
                try self.output.writeByte(value);
                line = line[2..];
            }
        }
    }
};

fn nibbleFromHex(c: u8) !u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'A'...'F' => c - 'A',
        'a'...'f' => c - 'a',
        else => return error.SyntaxError,
    };
}

fn eql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}
fn startsWith(haystack: []const u8, needle: []const u8) bool {
    return std.mem.startsWith(u8, haystack, needle);
}
