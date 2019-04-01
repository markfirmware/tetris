const std = @import("std");
const builtin = @import("builtin");
const Builder = std.build.Builder;
const LibExeObjStep = std.build.LibExeObjStep;
const RunStep = std.build.RunStep;
const Step = std.build.Step;

pub fn build(b: *Builder) !void {
    const zip_file_name = try s(b, "{}-{}.zip", repo_name, version);
    defer b.allocator.free(zip_file_name);

    const clean = try bash(b, "rm -rf lib/ release/ zig-cache/ ultibomainzig.h errors.log *.a *.elf *.img *.o *.zip");
    namedTask(b, &clean.step, "clean", "remove output files");

    const arch = builtin.Arch{ .arm = builtin.Arch.Arm32.v7 };
    const zigmain = b.addObject("ultibomainzig", "src/ultibomainzig.zig");
    zigmain.setOutputDir("zig-cache");
    zigmain.setTarget(arch, .freestanding, .gnueabihf);
    zigmain.addIncludeDir("subtree/ultibohub/API/include");
    zigmain.addIncludeDir("subtree/ultibohub/API/include");
    zigmain.addIncludeDir("subtree/ultibohub/Userland");
    zigmain.addIncludeDir("subtree/ultibohub/Userland/host_applications/ultibo/libs/bcm_host/include");
    zigmain.addIncludeDir("subtree/ultibohub/Userland/interface");
    zigmain.addIncludeDir("subtree/ultibohub/Userland/interface/vcos/ultibo");
    zigmain.addIncludeDir("subtree/ultibohub/Userland/interface/vmcs_host/ultibo");
    zigmain.addIncludeDir("subtree/ultibohub/Userland/middleware/dlloader");
    zigmain.addIncludeDir("/usr/lib/gcc/arm-none-eabi");
    zigmain.addIncludeDir("/usr/gcc-arm-none-eabi-8-2018-q4-major/arm-none-eabi/include");
    zigmain.step.dependOn(&clean.step);

    const kernels = b.step("kernels", "build kernel images for all rpi models");
    const programName = "ultibomainpas";
    for (configs) |config, i| {
        var ultibo_kernel = try config.buildKernel(b, zigmain, programName);
        kernels.dependOn(&ultibo_kernel.step);
//      if (i == 1) {
//          b.default_step.dependOn(&ultibo_kernel.step);
//      }
    }

    const ultibo_qemu = try configs[0].buildKernel(b, zigmain, programName);
    namedTask(b, &ultibo_qemu.step, "ultibo-qemu", "build ultibo kernel image for qemu");

    const play_ultibo_qemu = b.addSystemCommand([][]const u8 {
        "qemu-system-arm",
        "-kernel", "kernel-qemuvpb.img",
        "-append", "\"NETWORK0_IP_CONFIG=STATIC NETWORK0_IP_ADDRESS=10.0.2.15 NETWORK0_IP_NETMASK=255.255.255.0 NETWORK0_IP_GATEWAY=10.0.2.2\"",
        "-machine", "versatilepb",
        "-cpu", "cortex-a8",
        "-m", "256M",
        "-net", "nic", "-net", "user,hostfwd=tcp::5080-:80",
        "-serial", "stdio",
    });
    play_ultibo_qemu.step.dependOn(&ultibo_qemu.step);
    namedTask(b, &play_ultibo_qemu.step, "play-ultibo-qemu", "play ultibo qemu kernel");

    const client = b.addExecutable("client", "src/client.zig");
    client.step.dependOn(&clean.step);
    client.linkSystemLibrary("c");
//  namedTask(b, &client.step, "client", "build client that runs qemu");

    const run_client = client.run();
    run_client.step.dependOn(&client.step);
    run_client.step.dependOn(&ultibo_qemu.step);
//  namedTask(b, &run_client.step, "run-client", "run client");

    const release_message = try bash(b, "mkdir -p release/ && echo \"{} {}\" >> release/release-message.md && echo >> release/release-message.md && cat release-message.md >> release/release-message.md", repo_name, version);

    const zip = try bash(b, "mkdir -p release/ && cp -a *.img firmware/* config.txt cmdline.txt release/ && zip -jqr {} release/", zip_file_name);
    zip.step.dependOn(kernels);
    zip.step.dependOn(&release_message.step);
    namedTask(b, &zip.step, "release", "create release zip file");

    const upload = try bash(b, "hub release create --draft -F release/release-message.md -a {} {} && echo && echo this is an unpublished draft release", zip_file_name, version);
    upload.step.dependOn(&zip.step);
    namedTask(b, &upload.step, "upload-draft-release", "upload draft github release");
}

const gcc_arm = "/usr/gcc-arm-none-eabi-8-2018-q4-major";
const repo_name = "tetris";
const version = "v20190401";

const Config = struct {
    conf: []const u8,
    lower: []const u8,
    arch: []const u8,
    arch2: []const u8,
    proc: []const u8,
    kernel: []const u8,
    pub fn buildKernel (it: Config, b: *Builder, zigmain: *LibExeObjStep, programName: []const u8) !*RunStep {
        const home = try std.os.getEnvVarOwned(b.allocator, "HOME");
        defer b.allocator.free(home);
        const bin = try s(b, "{}/ultibo/core/fpc/bin", home);
        defer b.allocator.free(bin);
        const rtl = try s(b, "{}/ultibo/core/source/rtl", home);
        defer b.allocator.free(rtl);
        const base = try s(b, "{}/ultibo/core/fpc", home);
        defer b.allocator.free(base);
        const fpc = try bash(b, "PATH={}:{}/bin:$PATH fpc -dBUILD_{} -B -O2 -Tultibo -Parm -Cp{} -Wp{} -Fi{}/ultibo/extras -Fi{}/ultibo/core -Fl{}/units/{}-ultibo/lib/vc4 @{}/{}.CFG src/{}.pas >& errors.log", bin, gcc_arm, it.conf, it.arch, it.proc, rtl, rtl, base, it.arch2, bin, it.conf, programName);
        fpc.step.dependOn(&zigmain.step);
        const rename = try bash(b, "mv {} kernel-{}.img", it.kernel, it.lower);
        rename.step.dependOn(&fpc.step);
        return rename;
    }
};

const configs = []Config {
    Config {
        .conf = "QEMUVPB",
        .lower = "qemuvpb",
        .arch = "ARMV7a",
        .arch2 = "armv7",
        .proc = "QEMUVPB",
        .kernel = "kernel.bin",
    },
    Config {
        .conf = "RPI",
        .lower = "rpi",
        .arch = "ARMV6",
        .arch2 = "armv6",
        .proc = "RPIB",
        .kernel = "kernel.img",
    },
    Config {
        .conf = "RPI2",
        .lower = "rpi2",
        .arch = "ARMV7a",
        .arch2 = "armv7",
        .proc = "RPI2B",
        .kernel = "kernel7.img",
    },
    Config {
        .conf = "RPI3",
        .lower = "rpi3",
        .arch = "ARMV7a",
        .arch2 = "armv7",
        .proc = "RPI3B",
        .kernel = "kernel7.img",
    },
};

fn bash(b: *Builder, comptime fmt: []const u8, args: ...) !*RunStep {
    var command = try std.fmt.allocPrint(b.allocator, fmt, args);
    defer b.allocator.free(command);
    return b.addSystemCommand([][]const u8 {
        "bash", "-c", command,
    });
}

fn s(b: *Builder, comptime fmt: []const u8, args: ...) ![]const u8 {
    return std.fmt.allocPrint(b.allocator, fmt, args);
}

fn namedTask(b: *Builder, step: *Step, name: []const u8, help: []const u8) void {
    const new_step = b.step(name, help);
    new_step.dependOn(step);
}
