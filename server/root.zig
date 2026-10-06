const std = @import("std");
const Io = std.Io;
const goose = @import("goose");

const Duration = Io.Duration;
const linux = std.os.linux;

const WORK_DUR = Duration.fromSeconds(45 * 60);
const BREAK_DUR = Duration.fromSeconds(10 * 60);
const ACK_DUR = Duration.fromSeconds(2 * 60);

pub const Notification = struct { title: [:0]const u8, body: [:0]const u8 };

pub const Effect = struct {
    quit: bool = false,
    timer_op: ?TimerOp = null,
    notify: ?Notification = null,

    const TimerOp = union(enum) {
        disarm,
        arm: linux.itimerspec,

        pub fn fromDuration(d: Duration) TimerOp {
            return .{ .arm = .{
                .it_value = .{ .sec = d.toSeconds(), .nsec = 0 },
                .it_interval = .{ .sec = 0, .nsec = 0 },
            } };
        }
        pub fn fromDurationRecurrent(d: Duration) TimerOp {
            return .{ .arm = .{
                .it_value = .{ .sec = d.toSeconds(), .nsec = 0 },
                .it_interval = .{ .sec = d.toSeconds(), .nsec = 0 },
            } };
        }
    };
};

pub const Cmd = enum {
    start_work,
    start_break,
    stop,
    ack,
    quit,
    dump_state,

    pub fn decode(msg: *goose.core.Message) ?Cmd {
        const cmds = std.StaticStringMap(Cmd).initComptime(.{
            .{ "StartWork", .start_work },
            .{ "StartBreak", .start_break },
            .{ "Stop", .stop },
            .{ "Ack", .ack },
            .{ "Quit", .quit },
            .{ "DumpState", .dump_state },
        });

        var path: [:0]const u8 = "";
        var interface: [:0]const u8 = "";
        var member: [:0]const u8 = "";
        for (msg.header.header_fields) |h| {
            switch (h.code) {
                .Invalid, .ErrorName => return null,
                .ReplySerial, .Sender, .Destination, .Signature, .UnixFds => {},
                .Path => path = h.value.Path,
                .Interface => interface = h.value.Interface,
                .Member => member = h.value.Member,
            }
        }
        if (!std.mem.eql(u8, path, "/org/JoeRoser/poke") or
            !std.mem.eql(u8, interface, "org.JoeRoser.poke")) return null;

        return cmds.get(member);
    }
};

pub const State = enum {
    none,
    work,
    work_ack,
    @"break",
    break_ack,

    pub fn applyCommand(self: *State, cmd: Cmd) Effect {
        switch (cmd) {
            .quit => return .{ .quit = true },
            .start_work => {
                self.* = .work;
                return .{
                    .timer_op = .fromDuration(WORK_DUR),
                    .notify = .{ .title = "Start Work", .body = std.fmt.comptimePrint("Starting timer. See you in {} mins", .{WORK_DUR.toSeconds() / 60}) },
                };
            },
            .start_break => {
                self.* = .@"break";
                return .{
                    .timer_op = .fromDuration(BREAK_DUR),
                    .notify = .{ .title = "Start Break", .body = "Go rest you hard worker" },
                };
            },
            .stop => {
                self.* = .none;
                return .{ .timer_op = .disarm };
            },
            .ack => switch (self.*) {
                .none, .work, .@"break" => return .{},
                .work_ack => {
                    self.* = .@"break";
                    return .{ .timer_op = .fromDuration(WORK_DUR) };
                },
                .break_ack => {
                    self.* = .work;
                    return .{ .timer_op = .fromDuration(BREAK_DUR) };
                },
            },
            .dump_state => unreachable,
        }
    }
    pub fn timerFired(self: *State) Effect {
        std.debug.assert(self.* != .none);
        switch (self.*) {
            .work => {
                self.* = .work_ack;
                return .{
                    .timer_op = .fromDurationRecurrent(ACK_DUR),
                    .notify = .{ .title = "Break Time!!", .body = "Worked long time" },
                };
            },
            .work_ack => return .{
                .notify = .{ .title = "TAKE A BREAK", .body = "STOP WORKING" },
            },
            .@"break" => {
                self.* = .break_ack;
                return .{
                    .timer_op = .fromDurationRecurrent(ACK_DUR),
                    .notify = .{ .title = "Back to Work!!", .body = "Time to start working again" },
                };
            },
            .break_ack => return .{
                .notify = .{ .title = "WORK TIME", .body = "GET BACK TO WORK" },
            },
            .none => unreachable,
        }
    }
};

const GStr = goose.core.value.GStr;
pub fn notify(alloc: std.mem.Allocator, conn: *goose.Connection, notif: Notification) !void {
    const Hint = union(enum) { byte: u8, boolean: bool };
    var hints = std.StringHashMap(Hint).init(alloc);
    defer hints.deinit();

    try hints.put("urgency", .{ .byte = 1 });
    try hints.put("transient", .{ .boolean = true });

    // const hints = std.StaticStringMap(Hint).initComptime(.{
    //     .{ "urgency", Hint{ .byte = 1 } },
    //     .{ "transient", Hint{ .boolean = true } },
    // });

    var body =
        try goose.message.BodyEncoder.encode(alloc, .{
            GStr{ .s = "Poke" },
            @as(u32, 0),
            GStr{ .s = "dialog-information" },
            GStr{ .s = notif.title },
            GStr{ .s = notif.body },
            @as([]GStr, &.{}),
            hints,
            @as(i32, 5000),
        });
    defer body.deinit();

    var msg = try conn.methodCall(
        "org.freedesktop.Notifications",
        "/org/freedesktop/Notifications",
        "org.freedesktop.Notifications",
        "Notify",
        "susssasa{sv}i",
        body.body(),
    );
    defer conn.freeMessage(&msg);

    if (msg.isError()) return error.NotifyFailed;
}
