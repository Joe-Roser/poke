const std = @import("std");
const builtin = @import("builtin");

const root = @import("root.zig");
const goose = @import("goose");
const Epoll = @import("Epoll.zig");
const TimerFd = @import("TimerFd.zig");
const log = @import("log.zig");

const Io = std.Io;

// Logging
pub const std_options: std.Options = .{
    .logFn = log.fileLog,
};

pub fn main(init: std.process.Init) !void {
    var io_instance = Io.Threaded.init_single_threaded;
    const io = io_instance.io();

    log.openLogFile(io, init.arena.allocator(), init.environ_map) catch |e| {
        log.log_file = Io.File.stdout();
        std.log.err("Error initialising logger: {s}", .{@errorName(e)});
    };
    defer log.log_file.close(io);
    log.log_io = io;

    var epoll = try Epoll.init(.{});
    defer epoll.deinit();

    var conn = try goose.Connection.init(init.gpa, .Session, init.io, init.environ_map);
    try conn.requestName("org.JoeRoser.poke");
    defer conn.close();

    var timer = try TimerFd.init(.MONOTONIC, .{ .NONBLOCK = true });

    try epoll.add(conn.__inner_sock.socket.handle, Epoll.IN, .{ .u32 = 0 });
    try epoll.add(timer.fd, Epoll.IN, .{ .u32 = 1 });

    var state = root.State.none;

    var events: [1]Epoll.Event = undefined;
    while (true) {
        _ = init.arena.reset(.retain_capacity);

        _ = try epoll.wait(&events, -1);
        switch (events[0].data.u32) {
            0 => { // Connection
                var msg = try conn.readNextMessage();
                defer conn.freeMessage(&msg);
                errdefer conn.sendError(msg, "org.JoeRoser.poke.InternalError", "An internal error happened") catch {}; // TODO: Improve this

                const cmd = root.Cmd.decode(&msg) orelse {
                    try conn.sendError(msg, "org.JoeRoser.poke.BadMsg", "Message was malformed or not applicable"); // TODO: Improve this
                    std.log.info("Bad Message: {f}", .{msg});
                    continue;
                };
                std.log.info("Received cmd: {any}", .{cmd});

                if (cmd == .dump_state) {
                    const i = (try timer.getValue()).it_value.sec;
                    try conn.sendReply(msg, try .encode(init.arena.allocator(), .{
                        goose.core.value.GStr{ .s = @tagName(state) },
                        i,
                    }));
                    continue;
                }
                const effect = state.applyCommand(cmd);

                if (effect.quit) {
                    try conn.sendReply(msg, try .encode(init.arena.allocator(), .{}));
                    return;
                }
                if (effect.notify) |m| try root.notify(init.arena.allocator(), &conn, m);
                if (effect.timer_op) |t| switch (t) {
                    .arm => |spec| try timer.set(&spec, null),
                    .disarm => _ = try timer.stop(),
                };
                try conn.sendReply(msg, try .encode(init.arena.allocator(), .{}));
            },
            1 => {
                std.log.info("Timer finished in state {s}", .{@tagName(state)});
                _ = try timer.read();
                const effect = state.timerFired();

                std.debug.assert(!effect.quit);
                if (effect.notify) |m| try root.notify(init.arena.allocator(), &conn, m);
                if (effect.timer_op) |t| switch (t) {
                    .arm => |spec| try timer.set(&spec, null),
                    .disarm => unreachable,
                };
            },
            else => unreachable,
        }
    }
}
