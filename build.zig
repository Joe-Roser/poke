const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const goose_m = b.dependency("goose", .{});
    const goose = goose_m.module("goose");

    const server = b.addExecutable(.{
        .name = "poke_server",
        .root_module = b.createModule(.{
            .root_source_file = b.path("server/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "goose", .module = goose }},
        }),
    });
    b.installArtifact(server);

    const ctl = b.addExecutable(.{
        .name = "poke",
        .root_module = b.createModule(.{
            .root_source_file = b.path("ctl/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "goose", .module = goose }},
        }),
    });
    b.installArtifact(ctl);

    { // zig build release
        const release_server = b.addExecutable(.{
            .name = "poke_server",
            .root_module = b.createModule(.{
                .root_source_file = b.path("server/main.zig"),
                .target = target,
                .optimize = .ReleaseFast,
                .imports = &.{.{ .name = "goose", .module = goose }},
            }),
        });
        const install_release_server = b.addInstallArtifact(release_server, .{
            .dest_dir = .{ .override = .{ .custom = "release" } },
        });

        const release_ctl = b.addExecutable(.{
            .name = "poke",
            .root_module = b.createModule(.{
                .root_source_file = b.path("ctl/main.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{.{ .name = "goose", .module = goose }},
            }),
        });
        const install_release_ctl = b.addInstallArtifact(release_ctl, .{
            .dest_dir = .{ .override = .{ .custom = "release" } },
        });

        const release_step = b.step("release", "build a ReleaseFast binary into zig-out/release");
        release_step.dependOn(&install_release_server.step);
        release_step.dependOn(&install_release_ctl.step);
    }
}
