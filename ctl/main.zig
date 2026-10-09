const std = @import("std");
const goose = @import("goose");

var out_buf: [1024]u8 = undefined;
var err_buf: [1024]u8 = undefined;

const usage_fmt =
    \\Expected:
    \\{s} [cmd]
    \\where cmd is one of the following:
    \\  work - Start the work timer
    \\  break - Start the break timer
    \\  ack - Acknoledge a notification
    \\  stop - Stop the timers
    \\  quit - Close poke
    \\  logs - Print the log file
    \\  inspect - See poke state
    \\
;

const Cmd = enum {
    work,
    @"break",
    ack,
    stop,
    quit,
    inspect,
    logs,

    fn toMethodName(self: Cmd) [:0]const u8 {
        return switch (self) {
            .work => "StartWork",
            .@"break" => "StartBreak",
            .ack => "Ack",
            .stop => "Stop",
            .quit => "Quit",
            .inspect => "DumpState",
            .logs => unreachable,
        };
    }
};

pub fn main(init: std.process.Init) !void {
    const stdout = std.Io.File.stdout();
    var stdout_w = stdout.writer(init.io, &out_buf);
    const w = &stdout_w.interface;

    const stderr = std.Io.File.stderr();
    var stderr_w = stderr.writer(init.io, &err_buf);

    var it = init.minimal.args.iterate();
    const appname = it.next() orelse unreachable;
    const cmd_str = it.next() orelse {
        try stderr_w.interface.print(usage_fmt, .{appname});
        try stderr_w.interface.flush();
        std.process.exit(1);
    };
    if (it.next()) |_| {
        try stderr_w.interface.print("Error - Too many args\n" ++ usage_fmt, .{appname});
        try stderr_w.interface.flush();
        std.process.exit(1);
    }

    const cmd = std.meta.stringToEnum(Cmd, cmd_str) orelse {
        try stderr_w.interface.print("Error - Command not recognised\n" ++ usage_fmt, .{appname});
        try stderr_w.interface.flush();
        std.process.exit(1);
    };

    if (cmd == .logs) {
        const arena = init.arena.allocator();
        defer _ = init.arena.reset(.retain_capacity);
        const path = blk: {
            if (init.environ_map.get("XDG_DATA_HOME")) |d| break :blk d;
            if (init.environ_map.get("HOME")) |d| {
                break :blk try std.fs.path.join(arena, &.{ d, ".local", "share" });
            }
            try stderr_w.interface.print("Error - No log file location. Please set $XDG_DATA_HOME or $HOME", .{});
            return;
        };
        var d = try std.Io.Dir.openDirAbsolute(init.io, path, .{});
        defer d.close(init.io);
        var log_file = try d.openFile(init.io, "poke.log", .{});
        defer log_file.close(init.io);
        var reader = log_file.reader(init.io, &.{});
        _ = try reader.interface.streamRemaining(w);
        // const n = try reader.interface.stream(w, .unlimited);

        try w.flush();

        return;
    }

    var conn = try goose.Connection.init(init.gpa, .Session, init.io, init.environ_map);

    const ret = try inner_main(w, &stderr_w.interface, cmd, &conn, init.gpa);

    conn.close();
    try stderr_w.interface.flush();
    try w.flush();

    std.process.exit(ret);
}
fn inner_main(stdout: *std.Io.Writer, stderr: *std.Io.Writer, cmd: Cmd, conn: *goose.Connection, alloc: std.mem.Allocator) !u8 {
    if (!(checkServer(conn, alloc) catch false)) {
        try stderr.print("Cannot open poke dbus connection\n", .{});
        return 1;
    }

    var body = try goose.message.BodyEncoder.encode(alloc, .{});
    defer body.deinit();

    var reply = try conn.methodCall("org.JoeRoser.poke", "/org/JoeRoser/poke", "org.JoeRoser.poke", cmd.toMethodName(), "", body.body());
    defer conn.freeMessage(&reply);

    if (cmd == .inspect) {
        var r = std.Io.Reader.fixed(reply.body);
        const n = try r.takeInt(u32, reply.header.endianess);

        const state = try r.take(n);
        std.debug.assert((try r.takeByte()) == 0);
        r.seek = std.mem.alignForward(usize, r.seek, 8);
        const secsLeft = try r.takeInt(i64, reply.header.endianess);

        try stdout.print("state: {s} - timer: {}s\n", .{ state, secsLeft });
    }

    return 0;
}
fn checkServer(conn: *goose.Connection, alloc: std.mem.Allocator) !bool {
    var body = try goose.message.BodyEncoder.encode(alloc, .{goose.core.value.GStr{ .s = "org.JoeRoser.poke" }});
    defer body.deinit();

    var reply = try conn.methodCall("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "NameHasOwner", "s", body.body());
    defer conn.freeMessage(&reply);

    if (reply.isError()) return error.ReplyError;

    if (reply.body.len != 4) return error.BadRetVal;
    var tmp_r = std.Io.Reader.fixed(reply.body);
    const ret = try tmp_r.takeInt(u32, reply.header.endianess);

    std.debug.assert(ret <= 1);
    return ret == 1;
}
