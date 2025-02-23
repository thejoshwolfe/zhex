input_stream: StreamSource,
next_byte: ?u8 = null,

const std = @import("std");
const StreamSource = @import("./stream_source.zig").StreamSource;
const Tokenizer = @This();

pub fn next(self: *Tokenizer) !Token {
    while (true) {
        const c = self.readByte() catch |err| switch (err) {
            error.EndOfStream => return .eof,
            else => |e| return e,
        };
        switch (c) {
            // Newline
            '\n' => return .newline,
            // Skip whitespace
            ' ' => continue,
            // Comment until newline
            ';' => while (true) {
                const b = self.readByte() catch |err| switch (err) {
                    error.EndOfStream => return .eof,
                    else => |e| return e,
                };
                if (b == '\n') return .newline;
            },

            // Offset assertion
            ':' => {
                try self.expectBytes("0x");
                const value = try self.readHexInt();
                return .{ .offset_assertion = value };
            },

            '0'...'9', 'A'...'F', 'a'...'f' => {
                const c2 = try self.readByte();

                // Little endian literal
                if (c == '0' and c2 == 'x') {
                    var buf: [16]u8 = undefined;
                    const slice = buf[0..try self.readHexIntSlice(&buf)];
                    switch (slice.len) {
                        2 => return .{ .byte = std.fmt.parseInt(u8, slice, 16) catch unreachable },
                        4 => {
                            var token = Token{ .byte2 = undefined };
                            std.mem.writeInt(u16, &token.byte2, std.fmt.parseInt(u16, slice, 16) catch unreachable, .little);
                            return token;
                        },
                        8 => {
                            var token = Token{ .byte4 = undefined };
                            std.mem.writeInt(u32, &token.byte4, std.fmt.parseInt(u32, slice, 16) catch unreachable, .little);
                            return token;
                        },
                        16 => {
                            var token = Token{ .byte8 = undefined };
                            std.mem.writeInt(u64, &token.byte8, std.fmt.parseInt(u64, slice, 16) catch unreachable, .little);
                            return token;
                        },
                        else => return error.SyntaxError,
                    }
                }

                // Byte literal
                switch (c2) {
                    '0'...'9', 'A'...'F', 'a'...'f' => {
                        const buf = [2]u8{ c, c2 };
                        return .{ .byte = std.fmt.parseInt(u8, &buf, 16) catch unreachable };
                    },
                    else => {},
                }

                return error.SyntaxError;
            },
            else => return error.SyntaxError,
        }
    }
}

fn expectBytes(self: *Tokenizer, bytes: []const u8) !void {
    for (bytes) |b| {
        if (b != try self.readByte()) return error.SyntaxError;
    }
}

fn readByte(self: *Tokenizer) !u8 {
    if (self.next_byte) |b| {
        self.next_byte = null;
        return b;
    }
    return self.input_stream.reader().readByte();
}

fn readHexInt(self: *Tokenizer) !u64 {
    var buf: [16]u8 = undefined;
    const slice = buf[0..try self.readHexIntSlice(&buf)];
    return std.fmt.parseInt(u64, slice, 16) catch unreachable;
}
fn readHexIntSlice(self: *Tokenizer, buf: *[16]u8) !usize {
    for (buf, 0..) |*ptr, i| {
        const b = try self.readByte();
        switch (b) {
            '0'...'9', 'A'...'F', 'a'...'f' => ptr.* = b,
            else => {
                self.next_byte = b;
                return i;
            },
        }
    }
    return buf.len;
}

pub const Token = union(enum) {
    byte: u8,
    byte2: [2]u8,
    byte4: [4]u8,
    byte8: [8]u8,
    newline,
    offset_assertion: u64,
    eof,
};
