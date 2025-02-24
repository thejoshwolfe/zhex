output_stream: StreamSource,
buffered_output: std.io.BufferedWriter(0x1000, StreamSource.Writer),
output_pos: u64 = 0,
at_start_of_line: bool = true,

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

    while (true) {
        switch (try tokenizer.next()) {
            .byte => |b| try self.writeByte(b),
            .byte2 => |bytes| try self.writeAll(&bytes),
            .byte4 => |bytes| try self.writeAll(&bytes),
            .byte8 => |bytes| try self.writeAll(&bytes),
            .offset_assertion => |value| {
                if (!self.at_start_of_line) return error.SyntaxError;
                try self.assertOffset(value);
                switch (try tokenizer.next()) {
                    .eof => {},
                    .newline => continue,
                    else => return error.SyntaxError,
                }
            },
            .newline => {
                self.at_start_of_line = true;
                continue;
            },
            .eof => break,
        }
        self.at_start_of_line = false;
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

test "basic" {
    var output_buffer: [255]u8 = undefined;
    var output_fixed_buffer_stream = std.io.fixedBufferStream(&output_buffer);
    var compiler = Compiler.init(.{ .buffer = &output_fixed_buffer_stream });

    try compiler.feedString("48 65 6c 6c 6f");
    try compiler.flush();
    try std.testing.expectEqualSlices(u8, "Hello", output_fixed_buffer_stream.getWritten());

    try compiler.feedString("20776f726c640a");
    try compiler.flush();
    try std.testing.expectEqualSlices(u8, "Hello world\n", output_fixed_buffer_stream.getWritten());
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
