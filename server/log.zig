//! const log = @import("log.zig");
//! pub const std_options: std.Options = .{
//!     .logFn = log.fileLog,
//! };
//!
//!    // In main before calling log
//!     log.openLogFile(io, init.arena.allocator(), init.environ_map) catch |e| {
//!         log.log_file = Io.File.stdout();
//!         std.log.err("Error initialising logger: {s}", .{@errorName(e)});
//!     };
//!     defer log.log_file.close(io);
//!     log.log_io = io;

const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;

pub var log_file: Io.File = undefined;
pub var log_io: Io = undefined;

fn fileLog(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    const file = log_file;
    const prefix = "[" ++ comptime level.asText() ++ "] (" ++ @tagName(scope) ++ "): ";

    var buf: [1024]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, prefix ++ format ++ "\n", args) catch return;
    var writer = file.writer(log_io, &.{});
    writer.interface.writeAll(msg) catch {};
}

pub fn openLogFile(io: Io, alloc: std.mem.Allocator, env: *std.process.Environ.Map) !void {
    if (builtin.mode == .Debug) {
        log_file = Io.File.stdout();
        return;
    }
    const path = blk: {
        if (env.get("XDG_DATA_HOME")) |d| break :blk d;
        if (env.get("HOME")) |d| {
            break :blk try std.fs.path.join(alloc, &.{ d, ".local", "share" });
        }
        return error.NoDataDir;
    };
    var d = try Io.Dir.openDirAbsolute(io, path, .{});
    log_file = try d.createFile(io, "poke.log", .{ .truncate = true });
}
