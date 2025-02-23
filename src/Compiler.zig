output_stream: StreamSource,
buffered_output: std.io.BufferedWriter(0x1000, StreamSource.Writer),
output_pos: u64 = 0,

const std = @import("std");
const StreamSource = @import("./stream_source.zig").StreamSource;
const Compiler = @This();
const Tokenizer = @import("./Tokenizer.zig");

pub const max_line_length = 0x1000;

pub fn init(output_stream: StreamSource) Compiler {
    return .{
        .output_stream = output_stream,
        .buffered_output = .{ .unbuffered_writer = output_stream.writer() },
    };
}

pub fn feedString(self: *Compiler, input: []const u8) !void {
    var fbs = std.io.fixedBufferStream(input);
    return self.feed(.{ .const_buffer = &fbs });
}
pub fn feed(self: *Compiler, input_stream: StreamSource) !void {
    var tokenizer = Tokenizer{ .input_stream = input_stream };
    var at_start_of_line = true;

    while (true) {
        switch (try tokenizer.next()) {
            .byte => |b| try self.writeByte(b),
            .byte2 => |bytes| try self.writeAll(&bytes),
            .byte4 => |bytes| try self.writeAll(&bytes),
            .byte8 => |bytes| try self.writeAll(&bytes),
            .offset_assertion => |value| {
                if (!at_start_of_line) return error.SyntaxError;
                try self.assertOffset(value);
                switch (try tokenizer.next()) {
                    .eof => {},
                    .newline => continue,
                    else => return error.SyntaxError,
                }
            },
            .newline => {
                at_start_of_line = true;
                continue;
            },
            .eof => break,
        }
        at_start_of_line = false;
    }
}

pub fn flush(self: *Compiler) !void {
    try self.buffered_output.flush();
}

pub fn assertOffset(self: *const Compiler, offset: u64) !void {
    if (offset != self.output_pos) return error.OffsetAssertionIncorrect;
}

fn writeByte(self: *Compiler, b: u8) !void {
    try self.buffered_output.writer().writeByte(b);
    self.output_pos += 1;
}
fn writeAll(self: *Compiler, bytes: []const u8) !void {
    try self.buffered_output.writer().writeAll(bytes);
    self.output_pos += bytes.len;
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
    var compiler = Compiler.init(.{ .buffer = &output_fixed_buffer_stream });

    try compiler.feedString("48 65 6c 6c 6f 0a");
    try compiler.flush();

    try std.testing.expectEqualSlices(u8, "Hello\n", output_fixed_buffer_stream.getWritten());
}

test "offset assertion" {
    var output_buffer: [255]u8 = undefined;
    var output_fixed_buffer_stream = std.io.fixedBufferStream(&output_buffer);
    var compiler = Compiler.init(.{ .buffer = &output_fixed_buffer_stream });

    try compiler.feedString(
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
