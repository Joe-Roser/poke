const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;

const Config = struct { // TODO: Add more configs
    log_file_path: ?[]const u8 = null,
    work_mins: ?u32 = null,
    break_mins: ?u32 = null,
};

pub fn getConfigDir(env: *std.process.Environ.Map, alloc: std.mem.Allocator) ![]const u8 {
    if (env.get("XDG_CONFIG_HOME")) |d| return d;
    if (env.get("HOME")) |d| {
        return std.fs.path.join(alloc, &.{ d, ".local", "share" });
    }
    return error.NoConfigDir;
}

pub const Yaml = struct {
    src: []const u8,

    fn isWhitespace(c: u8) bool {
        return c == ' ' or c == '\n' or c == '\r' or c == '\t';
    }

    pub fn fill(self: *const Yaml) !Config {
        var seek: u32 = 0;
        var config: Config = .{};
        const info = @typeInfo(Config).@"struct";
        const fields = info.fields;

        while (true) {
            while (seek < self.src.len and isWhitespace(self.src[seek])) seek += 1;
            if (seek == self.src.len) break;
            const key_start = seek;

            while (seek < self.src.len and !isWhitespace(self.src[seek])) seek += 1;
            if (seek == self.src.len) return error.FmtError;
            const key_end = seek;

            if (seek == self.src.len or self.src[seek] != ' ') return error.FmtError;
            seek += 1;
            if (seek == self.src.len or self.src[seek] != '=') return error.FmtError;
            seek += 1;
            if (seek == self.src.len or self.src[seek] != ' ') return error.FmtError;
            seek += 1;

            const value_start = seek;

            while (seek < self.src.len and !isWhitespace(self.src[seek])) seek += 1;
            const value_end = seek;

            inline for (fields) |f| if (std.mem.eql(u8, f.name, self.src[key_start..key_end])) {
                @field(config, f.name) = try parseValue(f.type, self.src[value_start..value_end]);
            };
        }

        return config;
    }

    fn parseValue(comptime T: type, value: []const u8) !T {
        return switch (@typeInfo(T)) {
            .bool => if (std.mem.eql(u8, value, "true")) true else if (std.mem.eql(u8, value, "false"))
                false
            else
                error.InvalidValue,
            .int => try std.fmt.parseInt(T, value, 10),
            .float => try std.fmt.parseFloat(T, value),
            .pointer => |ptr| blk: {
                if (ptr.size == .slice and ptr.child == u8) {
                    break :blk value;
                }
                return error.UnsupportedType;
            },
            .optional => |opt| try parseValue(opt.child, value),
            .@"enum" => try std.meta.stringToEnum(T, value) orelse
                return error.InvalidValue,
            else => return error.UnsupportedType,
        };
    }
};

const testing = std.testing;
test "correctness" {
    const src =
        \\log_file_path = hellothere
        \\work_mins = 50
        \\badtest = klsdjf
    ;
    std.debug.print("\n", .{});
    const yaml = Yaml{ .src = src };
    const cfg = try yaml.fill();

    try testing.expectEqual(50, cfg.work_mins);
    try testing.expectEqual(null, cfg.break_mins);

    if (cfg.log_file_path) |f|
        try testing.expectEqualStrings("hellothere", f)
    else
        return error.NullPath;
}
