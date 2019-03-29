const std = @import("std");
const Builder = std.build.Builder;
const RunStep = std.build.RunStep;

pub fn build(b: *Builder) !void {
    const zipFileName = try s(b, "{}-{}.zip", repoName, version);
    defer b.allocator.free(zipFileName);

    const clean_command = try bash(b, "rm -rf lib/ release/ zig-cache/ errors.log {} *.o *.a *.elf *.img", zipFileName);
    const clean = b.step("clean", "remove output files");
    clean.dependOn(&clean_command.step);

    const zigmain = b.addSystemCommand([][]const u8 {
        "zig", "build-obj", "-target", "armv7-freestanding-gnueabihf",
        "-isystem", "subtree/ultibohub/API/include",
        "-isystem", "subtree/ultibohub/Userland",
        "-isystem", "subtree/ultibohub/Userland/host_applications/ultibo/libs/bcm_host/include",
        "-isystem", "subtree/ultibohub/Userland/interface",
        "-isystem", "subtree/ultibohub/Userland/interface/vcos/ultibo",
        "-isystem", "subtree/ultibohub/Userland/interface/vmcs_host/ultibo",
        "-isystem", "subtree/ultibohub/Userland/middleware/dlloader",
        "-isystem", "/usr/lib/gcc/arm-none-eabi",
        "-isystem", "/usr/gcc-arm-none-eabi-8-2018-q4-major/arm-none-eabi/include",
        "src/ultibomainzig.zig"
    });
    zigmain.step.dependOn(clean);

    const kernels = b.step("kernels", "build kernel images for all rpi models");
    const programName = "ultibomainpas";
    for (configs) |config, i| {
        var ultibomain = try config.fpcCommands(b, zigmain, programName);
        kernels.dependOn(&ultibomain.step);
        if (i == 1) {
//          b.default_step.dependOn(&ultibomain.step);
        }
    }

    const build_ultibo_qemu = b.step("ultibo-qemu", "build ultibo kernel image for qemu");
    var ultibomain = try configs[0].fpcCommands(b, zigmain, programName);
    build_ultibo_qemu.dependOn(&ultibomain.step);

    const play_ultibo_qemu_command = b.addSystemCommand([][]const u8 {
        "qemu-system-arm",
        "-kernel", "kernel-qemuvpb.img",
        "-append", "\"NETWORK0_IP_CONFIG=STATIC NETWORK0_IP_ADDRESS=10.0.2.15 NETWORK0_IP_NETMASK=255.255.255.0 NETWORK0_IP_GATEWAY=10.0.2.2\"",
        "-machine", "versatilepb",
        "-cpu", "cortex-a8",
        "-m", "256M",
        "-net", "nic", "-net", "user,hostfwd=tcp::5080-:80",
        "-serial", "stdio",
    });
    play_ultibo_qemu_command.step.dependOn(build_ultibo_qemu);

    const play_ultibo_qemu = b.step("play-ultibo-qemu", "play ultibo qemu kernel");
    play_ultibo_qemu.dependOn(&play_ultibo_qemu_command.step);

    const build_client_command = b.addSystemCommand([][]const u8 {
        "zig", "build-exe", "--library", "c", "client.zig"
    });
    build_client_command.step.dependOn(clean);

    const build_client = b.step("client", "build client");
    build_client.dependOn(&build_client_command.step);

    const run_client_command = b.addSystemCommand([][]const u8 {
        "./client",
    });
    run_client_command.step.dependOn(build_client);
    run_client_command.step.dependOn(build_ultibo_qemu);

    const run_client = b.step("run-client", "run client");
    run_client.dependOn(&run_client_command.step);

    const release_message_command = try bash(b, "mkdir -p release/ && echo \"{} {}\" >> release/release-message.md && echo >> release/release-message.md && cat release-message.md >> release/release-message.md", repoName, version);

    const zip_command = try bash(b, "mkdir -p release/ && cp -a *.img firmware/* config.txt cmdline.txt release/ && zip -jqr {} release/", zipFileName);
    zip_command.step.dependOn(kernels);
    zip_command.step.dependOn(&release_message_command.step);

    const create_release = b.step("create-release", "create release zip file");
    create_release.dependOn(&zip_command.step);

    const upload_command = try bash(b, "hub release create --draft -F release/release-message.md -a {} {} && echo && echo this is an unpublished draft release", zipFileName, version);
    upload_command.step.dependOn(create_release);

    const upload_release = b.step("upload-draft-release", "upload draft github release");
    upload_release.dependOn(&upload_command.step);
}

const gcc_arm = "/usr/gcc-arm-none-eabi-8-2018-q4-major";
const repoName = "zig-on-rpi-using-ultibo";
const version = "v20190319";

const Config = struct {
    conf: []const u8,
    lower: []const u8,
    arch: []const u8,
    arch2: []const u8,
    proc: []const u8,
    kernel: []const u8,
    pub fn fpcCommands (it: Config, b: *Builder, zigmain: *RunStep, programName: []const u8) !*RunStep {
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
