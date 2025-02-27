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

    try zhexToBin(input_path_str, output_path_str);

    return std.process.cleanExit();
}

fn zhexToBin(input_path_str: []const u8, output_path_str: []const u8) !void {
    var input_file = try std.fs.cwd().openFile(input_path_str, .{});
    defer input_file.close();

    var output_file = try std.fs.cwd().createFile(output_path_str, .{ .read = true });
    defer output_file.close();

    var compiler = Compiler.init(.{ .file = output_file });

    compiler.feed(.{ .file = input_file }) catch |err| {
        switch (err) {
            error.OffsetAssertionIncorrect => {
                std.log.err("{s}:{}:{}: offset incorrect. expected: 0x{x}", .{
                    input_path_str,
                    compiler.tokenizer.line_number,
                    compiler.tokenizer.column_number,
                    compiler.output_pos,
                });
            },
            error.SyntaxError => {
                std.log.err("{s}:{}:{}: syntax error", .{
                    input_path_str,
                    compiler.tokenizer.line_number,
                    compiler.tokenizer.column_number,
                });
            },
            error.ByteValueMismatchAfterSeekBackward => {
                std.log.err("{s}:{}:{}: byte value mismatch after seek backward", .{
                    input_path_str,
                    compiler.tokenizer.line_number,
                    compiler.tokenizer.column_number,
                });
            },
            // Crash
            else => return err,
        }
        // "Clean" error.
        compiler.flush() catch {};
    };

    return compiler.flush();
}

fn eql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}
