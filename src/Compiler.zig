tokenizer: Tokenizer,
at_start_of_line: bool = true,

output_stream: StreamSource,
buffered_output: std.io.BufferedWriter(0x1000, StreamSource.Writer),
// Track this to support offset assertions without requiring the output stream be seekable.
output_pos: u64 = 0,

// After seeking backward, only assert matching contents until this offset instead of overwriting.
resume_output_pos: ?u64 = null,
// After seeking backward, this buffers reading while asserting overlapping contents.
buffered_output_reader: std.io.BufferedReader(0x1000, StreamSource.Reader),

const std = @import("std");
const assert = std.debug.assert;
const StreamSource = @import("./stream_source.zig").StreamSource;
const Compiler = @This();
const Tokenizer = @import("./Tokenizer.zig");

pub fn init(output_stream: StreamSource) Compiler {
    return .{
        .tokenizer = .{ .input_stream = undefined },
        .output_stream = output_stream,
        .buffered_output = .{ .unbuffered_writer = output_stream.writer() },
        .buffered_output_reader = .{ .unbuffered_reader = output_stream.reader() },
    };
}

pub fn feedString(self: *Compiler, input: []const u8) !void {
    var fbs = std.io.fixedBufferStream(input);
    return self.feed(.{ .const_buffer = &fbs });
}
pub fn feed(self: *Compiler, input_stream: StreamSource) !void {
    self.tokenizer.input_stream = input_stream;

    while (true) {
        switch (try self.tokenizer.next()) {
            .byte => |b| try self.writeByte(b),
            .byte2 => |bytes| try self.writeAll(&bytes),
            .byte4 => |bytes| try self.writeAll(&bytes),
            .byte8 => |bytes| try self.writeAll(&bytes),
            .offset_assertion => |value| {
                if (!self.at_start_of_line) return error.SyntaxError;
                try self.assertOffset(value);
                switch (try self.tokenizer.next()) {
                    .eof => {},
                    .newline => continue,
                    else => return error.SyntaxError,
                }
            },
            .seek_backward => |offset| {
                try self.buffered_output.flush();
                const pos = try self.output_stream.getPos();
                if (pos != self.output_pos) return error.OutputFileSeekingIsBroken;
                const new_pos = std.math.sub(u64, pos, offset) catch return error.SeekBackwardTooFar;
                try self.output_stream.seekTo(new_pos);
                self.output_pos = new_pos;
                self.resume_output_pos = pos;
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
    if (self.resume_output_pos) |future_pos| {
        if (b != try self.buffered_output_reader.reader().readByte()) return error.ByteValueMismatchAfterSeekBackward;
        if (future_pos == self.output_pos + 1) {
            // We're caught up.
            try self.doneRetreading();
        }
    } else {
        try self.buffered_output.writer().writeByte(b);
    }
    self.output_pos += 1;
}
fn writeAll(self: *Compiler, bytes: []const u8) !void {
    var cursor: usize = 0;
    if (self.resume_output_pos) |future_pos| {
        // Read and assert the retread bytes.
        const retread_len = @min(bytes.len, future_pos - self.output_pos);
        var buf: [8]u8 = undefined;
        const buffer = buf[0..retread_len]; // assumes this function is called with sufficiently small slices.
        try self.buffered_output_reader.reader().readNoEof(buffer);
        while (cursor < retread_len) : (cursor += 1) {
            if (buffer[cursor] != bytes[cursor]) return error.ByteValueMismatchAfterSeekBackward;
        }

        if (self.output_pos + retread_len == future_pos) {
            // We're caught up.
            try self.doneRetreading();
        }
    }
    if (cursor < bytes.len) {
        try self.buffered_output.writer().writeAll(bytes[cursor..]);
    }
    self.output_pos += bytes.len;
}

fn doneRetreading(self: *Compiler) !void {
    assert(self.resume_output_pos.? == try self.output_stream.getPos());
    self.buffered_output_reader.start = 0;
    self.buffered_output_reader.end = 0;
    self.resume_output_pos = null;
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
