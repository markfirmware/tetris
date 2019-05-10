const Builder = @import("std").build.Builder;
const builtin = @import("builtin");

pub fn build(b: *Builder) void {
    const mode = b.standardReleaseOptions();
    const windows = b.option(bool, "windows", "create windows build") orelse false;

    var exe = b.addExecutable("tetris", "src/main.zig");
    exe.setBuildMode(mode);

    if (windows) {
        exe.setTarget(builtin.Arch.x86_64, builtin.Os.windows, builtin.Abi.gnu);
    }

    exe.linkSystemLibrary("c");
    exe.linkSystemLibrary("m");
    exe.linkSystemLibrary("glfw");
    exe.linkSystemLibrary("epoxy");
    exe.linkSystemLibrary("png");
    exe.linkSystemLibrary("z");

    b.default_step.dependOn(&exe.step);

    b.installArtifact(exe);

    const play = b.step("play", "Play the game");
    const run = exe.run();
    play.dependOn(&run.step);

    build1(b, windows);

    refactor1(b, windows);
}

pub fn build1(b: *Builder, windows: var) void {
    const mode = b.standardReleaseOptions();

    var exe = b.addExecutable("tetris1", "src/main1.zig");
    exe.setBuildMode(mode);

    if (windows) {
        exe.setTarget(builtin.Arch.x86_64, builtin.Os.windows, builtin.Abi.gnu);
    }

    exe.linkSystemLibrary("c");
    exe.linkSystemLibrary("m");
    exe.linkSystemLibrary("glfw");
    exe.linkSystemLibrary("epoxy");
    exe.linkSystemLibrary("png");
    exe.linkSystemLibrary("z");

    //b.default_step.dependOn(&exe.step);
    const build1_step = b.step("main1", "Build the main1 refactoring");
    build1_step.dependOn(&exe.step);

    b.installArtifact(exe);

    const play = b.step("play-main1", "Play the main1 refactoring");
    const run = exe.run();
    play.dependOn(&run.step);
}

pub fn refactor1(b: *Builder, windows: var) void {
    const mode = b.standardReleaseOptions();

    var exe = b.addExecutable("refactor1", "src/refactor1.zig");
    exe.setBuildMode(mode);

    if (windows) {
        exe.setTarget(builtin.Arch.x86_64, builtin.Os.windows, builtin.Abi.gnu);
    }

    exe.linkSystemLibrary("c");

    const build1_step = b.step("refactor1", "Build the refactoring script");
    build1_step.dependOn(&exe.step);

    b.installArtifact(exe);

    const create = b.step("create-main1", "Create the main1 refactoring");
    create.dependOn(&exe.run().step);
}
