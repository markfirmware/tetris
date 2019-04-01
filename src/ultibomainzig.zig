const std = @import("std");
const os = std.os;
const assert = std.debug.assert;
const panic = std.debug.panic;
use @import("math3d.zig");
const ultibo = @cImport({
    @cInclude("ultibo/platform.h");
});
const usrlnd = @cImport({
    @cInclude("sys/types.h");
    @cInclude("bcm_host.h");
    @cInclude("vmcs_host/vc_cecservice.h");
});

const core_tetris = @import("coretetris.zig");
const Tetris = core_tetris.Tetris;
const Cell = core_tetris.Cell;
const Particle = core_tetris.Particle;

var tetris_state: Tetris = undefined;

export fn mainzig(argc: u32, argv: [*][*]u8) i32 {
    if (work(argc, argv)) {
        return 0;
    }
    else |err| {
        return @errorToInt(err);
    }
}

var window: u32 = undefined;

fn work(argc: u32, argv: [*][*]u8) void {
    for (argv[0..argc]) |arg, i| {
        warn("zig command line argument {} is {s}", i + 1, arg);
    }

    const t = &tetris_state;
    core_tetris.setCallbacks(@ptrCast(*u64, t), t, drawParticle, drawText, fillRectMvp);

//  c.glfwGetFramebufferSize(window, &t.framebuffer_width, &t.framebuffer_height);
    var console = ultibo.console_device_get_default();
    const POSITION_LEFT = 3;
    window = ultibo.graphics_window_create(console, POSITION_LEFT);
    t.framebuffer_width = core_tetris.window_width;
    t.framebuffer_height = core_tetris.window_height;
    assert(t.framebuffer_width >= core_tetris.window_width);
    assert(t.framebuffer_height >= core_tetris.window_height);
//  sleep(5.0);
    warn("ready {} {}", t.framebuffer_width, t.framebuffer_height);

    var rand_seed: u32 = 0;
//  os.getRandomBytes(@ptrCast([*]u8, &rand_seed)[0..4]) catch {
//      panic("unable to get random seed\n");
//  };
    core_tetris.setRandomSeed(t, rand_seed);

    core_tetris.resetProjection(t);
    core_tetris.restartGame(t);

    const start_time = getTime();
    var prev_time = start_time;

    while (true) {
        _ = ultibo.graphics_window_clear(window);

        const now_time = getTime();
        const elapsed = now_time - prev_time;
        prev_time = now_time;

        core_tetris.nextFrame(t, elapsed);

        core_tetris.draw(t);
        pollKeyboard(t);
        sleep(0.1);
    }
}

fn sleep(seconds: f64) void {
    const milliseconds = @floatToInt(u32, seconds * 1000.0);
    const start = ultibo.get_tick_count();
    while (ultibo.get_tick_count() -% start < milliseconds) {
    }
}

fn initializeHdmiCec() void {
    if (ultibo.board_get_type() != ultibo.BOARD_TYPE_QEMUVPB) {
        usrlnd.bcm_host_init();
        _ = usrlnd.vc_cec_set_passive(1);
        usrlnd.vc_cec_register_callback(cecCallback, @intToPtr(*c_void, 0));
        _ = usrlnd.vc_cec_register_all;
        _ = usrlnd.vc_cec_set_osd_name(c"zig!\x00");
    }
}

extern fn cecCallback(data: ?*c_void, reason: u32, p1: u32, p2: u32, p3: u32, p4: u32) void {
    const userControl = (p1 >> 16) & 0xff;

    switch (reason & 0xffff) {
        usrlnd.VC_CEC_BUTTON_PRESSED => warn("CEC: 0x{X} pressed", userControl),
        usrlnd.VC_CEC_BUTTON_RELEASE => warn("CEC: 0x{X} released", userControl),
        else => warn("cecCallback reason 0x{X} p1 0x{X} p2 0x{X} p3 0x{X} p4 0x{X}", reason, p1, p2, p3, p4),
    }
}

fn pollKeyboard(t: *Tetris) void {
    var key: u8 = undefined;
    if (ultibo.console_peek_key(&key, null)) {
        if (ultibo.console_get_key(&key, null)) {
            if (key == 0) {
                _ = ultibo.console_get_key(&key, null);
                switch (key) {
                    75 => key = 'a',
                    77 => key = 's',
                    72 => key = 'w',
                    80 => key = 'z',
                    else => {
                        warn("unrecognized key scan code {}", key);
                        return;
                    },
                }
            }
            switch (key) {
                27 => quit(),
                ' ' => core_tetris.userDropCurPiece(t),
                'z' => core_tetris.userCurPieceFall(t),
                'a' => core_tetris.userMoveCurPiece(t, -1),
                's' => core_tetris.userMoveCurPiece(t, 1),
                'w' => core_tetris.userRotateCurPiece(t, 1),
                'W' => core_tetris.userRotateCurPiece(t, -1),
                'r' => core_tetris.restartGame(t),
                'p' => core_tetris.userTogglePause(t),
                else => warn("unrecognized key {}", key),
            }
        }
    }
}

fn getTime() f64 {
    return @intToFloat(f64, ultibo.get_tick_count()) / 1000.0;
}

var warnBuf: [1024]u8 = undefined;
fn warn(comptime fmt: []const u8, args: ...) void {
    if (std.fmt.bufPrint(&warnBuf, fmt ++ "\n\x00", args)) |warning| {
        var count: u32 = undefined;
        ultibo.logging_output(warning.ptr);
    }
    else |_| {
    }
}

fn quit() void {
//  os.exit(0);
    warn("exit qemu - not yet implemented");
}

fn drawParticle(callback_user_pointer: *allowzero u64, t: *Tetris, p: Particle) void {
    warn("drawParticle");
    const model = mat4x4_identity.translateByVec(p.pos).rotate(p.angle, p.axis).scale(p.scale_w, p.scale_h, 0.0);

    const mvp = t.projection.mult(model);
//  fillRectMvp(callback_user_pointer, t, color, mvp);
}

fn drawText(callback_user_pointer: *allowzero u64, t: *Tetris, text: []const u8, left: i32, top: i32, size: f32) void {
//  for (text) |col, i| {
//      if (col <= '~') {
//          const char_left = @intToFloat(f32, left) + @intToFloat(f32, i * core_tetris.font_char_width) * size;
//          const model = mat4x4_identity.translate(char_left, @intToFloat(f32, top), 0.0).scale(size, size, 0.0);
//          const mvp = t.projection.mult(model);
//          d.font.draw(d.shaders, col, mvp);
//      } else {
//          unreachable;
//      }
//  }
}

var unit_2d_rectangle = Mat4x4{ .data = [][4]f32{
    []f32{ 0.0, 1.0, 1.0, 0.0 },
    []f32{ 0.0, 0.0, 1.0, 1.0 },
    []f32{ 0.0, 0.0, 0.0, 0.0 },
    []f32{ 1.0, 1.0, 1.0, 1.0 },
} };

var block: Mat4x4 = undefined;
fn at(row: usize, col: usize) i32 {
    var scaled = @floatToInt(i32, 125.0 * (block.data[row][col]));
    if (row == 1) {
        scaled *= -1;
    }
    return scaled + 150;
}

fn colorComponentToU8(x: Vec4, index: usize) u32 {
    return @floatToInt(u32, 255.0 * x.data[index]);
}

fn fillRectMvp(callback_user_pointer: *allowzero u64, t: *Tetris, color: Vec4, mvp: Mat4x4) void {
    block = mvp.mult(unit_2d_rectangle);
    _ = ultibo.graphics_window_draw_block(window, at(0, 0), at(1, 0), at(0, 2), at(1, 2), encodeColor(color));
}

fn encodeColor(color: Vec4) u32 {
    var rgb: u32 = 0;
    rgb = rgb << 8 | @floatToInt(u8, 255.0 * color.data[3] * color.data[0]);
    rgb = rgb << 8 | @floatToInt(u8, 255.0 * color.data[3] * color.data[1]);
    rgb = rgb << 8 | @floatToInt(u8, 255.0 * color.data[3] * color.data[2]);
    return rgb;
}
