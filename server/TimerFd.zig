const std = @import("std");
const linux = std.os.linux;

const TimerFd = @This();

fd: std.posix.fd_t,

pub fn init(clockid: linux.timerfd_clockid_t, flags: linux.TFD) !TimerFd {
    const r = linux.timerfd_create(clockid, flags);
    if (std.posix.errno(r) != .SUCCESS) return error.Failed;
    return .{
        .fd = @intCast(r),
    };
}

pub fn set(self: *TimerFd, new_value: *const linux.itimerspec, old_value: ?*linux.itimerspec) !void {
    const r = linux.timerfd_settime(self.fd, .{}, new_value, old_value);
    if (std.posix.errno(r) != .SUCCESS) return error.Failed;
}
pub fn stop(self: *TimerFd) !linux.itimerspec {
    const new_value: linux.itimerspec = .{
        .it_value = .{ .sec = 0, .nsec = 0 },
        .it_interval = .{ .sec = 0, .nsec = 0 },
    };
    var old_value: linux.itimerspec = undefined;

    try self.set(&new_value, &old_value);

    return old_value;
}
pub fn read(self: *TimerFd) !void {
    var rbuf: [8]u8 = undefined;
    const r = linux.read(self.fd, &rbuf, rbuf.len);
    if (std.posix.errno(r) != .SUCCESS) return error.Failed;
}
pub fn getValue(self: *TimerFd) !linux.itimerspec {
    var old_value: linux.itimerspec = undefined;
    const r = linux.timerfd_gettime(self.fd, &old_value);

    if (std.posix.errno(r) != .SUCCESS) return error.Failed;
    return old_value;
}
