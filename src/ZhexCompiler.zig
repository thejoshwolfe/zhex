output_stream: StreamSource,
buffered_output: std.io.BufferedWriter(0x1000, StreamSource.Writer),
output_pos: u64 = 0,

const std = @import("std");
const StreamSource = @import("./stream_source.zig").StreamSource;
const ZhexCompiler = @This();

pub const max_line_length = 0x1000;

pub fn init(output_stream: StreamSource) ZhexCompiler {
    return .{
        .output_stream = output_stream,
        .buffered_output = .{ .unbuffered_writer = output_stream.writer() },
    };
}

pub fn handleString(self: *ZhexCompiler, input: []const u8) !void {
    var cursor: usize = 0;
    while (std.mem.indexOfScalarPos(u8, input, cursor, '\n')) |end| {
        const line = input[cursor..end];
        if (line.len > max_line_length) return error.LineTooLong;
        try self.handleLine(line);
        cursor = end + 1;
    }
    const line = input[cursor..];
    if (line.len > max_line_length) return error.LineTooLong;
    try self.handleLine(line);
}

pub fn handleLine(self: *ZhexCompiler, _line: []const u8) !void {
    var line = _line;
    mainLoop: while (line.len > 0) {
        while (line[0] == ' ') {
            line = line[1..];
            continue :mainLoop;
        }
        if (line.len == 0) return;
        if (line[0] == ';') return; // Skip the rest of the comment
        // Everything after this requires at least 2 chars.
        if (line.len < 2) return error.SyntaxError;

        if (line[0] == ':') {
            if (!startsWith(line, ":0x")) return error.SyntaxError;
            const start = ":0x".len;
            const end = std.mem.indexOfAnyPos(u8, line, start, " ;") orelse line.len;
            const offset = try std.fmt.parseInt(u64, line[start..end], 16); // TODO: should not accept '_'
            line = line[end..];

            try self.assertOffset(offset);
        } else if (line[0] == '"') {
            @panic("TODO: string values");
        } else if (startsWith(line, "0x")) {
            @panic("TODO: little endian hex values");
        } else {
            const nibbles = line[0..2];
            const value = (try nibbleFromHex(nibbles[0]) << 4) | (try nibbleFromHex(nibbles[1]));
            try self.writeByte(value);
            line = line[2..];
        }
    }
}

pub fn flush(self: *ZhexCompiler) !void {
    try self.buffered_output.flush();
}

pub fn assertOffset(self: *const ZhexCompiler, offset: u64) !void {
    if (offset != self.output_pos) return error.OffsetAssertionIncorrect;
}

fn writeByte(self: *ZhexCompiler, b: u8) !void {
    try self.buffered_output.writer().writeByte(b);
    self.output_pos += 1;
}

fn nibbleFromHex(c: u8) !u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'A'...'F' => 10 + c - 'A',
        'a'...'f' => 10 + c - 'a',
        else => return error.SyntaxError,
    };
}

fn startsWith(haystack: []const u8, needle: []const u8) bool {
    return std.mem.startsWith(u8, haystack, needle);
}

test "basic" {
    var output_buffer: [255]u8 = undefined;
    var output_fixed_buffer_stream = std.io.fixedBufferStream(&output_buffer);
    var compiler = ZhexCompiler.init(.{ .buffer = &output_fixed_buffer_stream });

    try compiler.handleLine("48 65 6c 6c 6f 0a");
    try compiler.flush();

    try std.testing.expectEqualSlices(u8, "Hello\n", output_fixed_buffer_stream.getWritten());
}

test "offset assertion" {
    var output_buffer: [255]u8 = undefined;
    var output_fixed_buffer_stream = std.io.fixedBufferStream(&output_buffer);
    var compiler = ZhexCompiler.init(.{ .buffer = &output_fixed_buffer_stream });

    try compiler.handleString(
        \\:0x0
        \\48 65 6c 6c
        \\:0x4 ;
        \\6f 0a
        \\:0x6;
    );
    try compiler.assertOffset(0x6);
    try compiler.flush();

    try std.testing.expectEqualSlices(u8, "Hello\n", output_fixed_buffer_stream.getWritten());
}
