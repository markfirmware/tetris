const std = @import("std");
const os = std.os;
const assert = std.debug.assert;
const panic = std.debug.panic;
const warn = std.debug.warn;
const c = @import("c.zig");
const debug_gl = @import("debug_gl.zig");
use @import("math3d.zig");
const all_shaders = @import("all_shaders.zig");
const static_geometry = @import("static_geometry.zig");
const pieces = @import("pieces.zig");
const Piece = pieces.Piece;
const spritesheet = @import("spritesheet.zig");

const core_tetris = @import("coretetris.zig");
const Tetris = core_tetris.Tetris;
const Cell = core_tetris.Cell;
const Particle = core_tetris.Particle;

const Display = struct {
    window: *c.GLFWwindow,
    shaders: all_shaders.AllShaders,
    static_geometry: static_geometry.StaticGeometry,
    font: spritesheet.Spritesheet,
};

const font_png = @embedFile("../assets/font.png");

var tetris_state: Tetris = undefined;
var display_state: Display = undefined;

pub fn main() !void {
    const t = &tetris_state;
    const d = &display_state;
    core_tetris.setCallbacks(@ptrCast(*allowzero u64, d), t, drawParticle, drawText, fillRectMvp);

    _ = c.glfwSetErrorCallback(errorCallback);

    if (c.glfwInit() == c.GL_FALSE) {
        panic("GLFW init failure\n");
    }
    defer c.glfwTerminate();

    c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MAJOR, 3);
    c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MINOR, 2);
    c.glfwWindowHint(c.GLFW_OPENGL_FORWARD_COMPAT, c.GL_TRUE);
    c.glfwWindowHint(c.GLFW_OPENGL_DEBUG_CONTEXT, debug_gl.is_on);
    c.glfwWindowHint(c.GLFW_OPENGL_PROFILE, c.GLFW_OPENGL_CORE_PROFILE);
    c.glfwWindowHint(c.GLFW_DEPTH_BITS, 0);
    c.glfwWindowHint(c.GLFW_STENCIL_BITS, 8);
    c.glfwWindowHint(c.GLFW_RESIZABLE, c.GL_FALSE);

    var window = c.glfwCreateWindow(core_tetris.window_width, core_tetris.window_height, c"Tetris", null, null) orelse {
        panic("unable to create window\n");
    };
    defer c.glfwDestroyWindow(window);

    _ = c.glfwSetKeyCallback(window, keyCallback);
    c.glfwMakeContextCurrent(window);
    c.glfwSwapInterval(1);

    // create and bind exactly one vertex array per context and use
    // glVertexAttribPointer etc every frame.
    var vertex_array_object: c.GLuint = undefined;
    c.glGenVertexArrays(1, &vertex_array_object);
    c.glBindVertexArray(vertex_array_object);
    defer c.glDeleteVertexArrays(1, &vertex_array_object);

    var rand_seed: u32 = undefined;
    os.getRandomBytes(@ptrCast([*]u8, &rand_seed)[0..4]) catch {
        panic("unable to get random seed\n");
    };
    core_tetris.setRandomSeed(t, rand_seed);

    c.glfwGetFramebufferSize(window, &t.framebuffer_width, &t.framebuffer_height);
    assert(t.framebuffer_width >= core_tetris.window_width);
    assert(t.framebuffer_height >= core_tetris.window_height);

    d.window = window;

    d.shaders = try all_shaders.createAllShaders();
    defer d.shaders.destroy();

    d.static_geometry = static_geometry.createStaticGeometry();
    defer d.static_geometry.destroy();

    d.font = spritesheet.init(font_png, core_tetris.font_char_width, core_tetris.font_char_height) catch {
        panic("unable to read assets\n");
    };
    defer d.font.deinit();

    core_tetris.resetProjection(t);
    core_tetris.restartGame(t);

    c.glClearColor(0.0, 0.0, 0.0, 1.0);
    c.glEnable(c.GL_BLEND);
    c.glBlendFunc(c.GL_SRC_ALPHA, c.GL_ONE_MINUS_SRC_ALPHA);
    c.glPixelStorei(c.GL_UNPACK_ALIGNMENT, 1);

    c.glViewport(0, 0, t.framebuffer_width, t.framebuffer_height);
    c.glfwSetWindowUserPointer(window, @ptrCast(*c_void, t));

    debug_gl.assertNoError();

    const start_time = c.glfwGetTime();
    var prev_time = start_time;

    while (c.glfwWindowShouldClose(window) == c.GL_FALSE) {
        c.glClear(c.GL_COLOR_BUFFER_BIT | c.GL_DEPTH_BUFFER_BIT | c.GL_STENCIL_BUFFER_BIT);

        const now_time = c.glfwGetTime();
        const elapsed = now_time - prev_time;
        prev_time = now_time;

        core_tetris.nextFrame(t, elapsed);

        core_tetris.draw(t);
        c.glfwSwapBuffers(window);

        c.glfwPollEvents();
    }

    debug_gl.assertNoError();
}

extern fn errorCallback(err: c_int, description: [*c]const u8) void {
    panic("Error: {}\n", description);
}

extern fn keyCallback(window: ?*c.GLFWwindow, key: c_int, scancode: c_int, action: c_int, mods: c_int) void {
    if (action != c.GLFW_PRESS) return;
    const t = @ptrCast(*Tetris, @alignCast(@alignOf(Tetris), c.glfwGetWindowUserPointer(window).?));

    switch (key) {
        c.GLFW_KEY_ESCAPE => c.glfwSetWindowShouldClose(window, c.GL_TRUE),
        c.GLFW_KEY_SPACE => core_tetris.userDropCurPiece(t),
        c.GLFW_KEY_DOWN => core_tetris.userCurPieceFall(t),
        c.GLFW_KEY_LEFT => core_tetris.userMoveCurPiece(t, -1),
        c.GLFW_KEY_RIGHT => core_tetris.userMoveCurPiece(t, 1),
        c.GLFW_KEY_UP => core_tetris.userRotateCurPiece(t, 1),
        c.GLFW_KEY_LEFT_SHIFT, c.GLFW_KEY_RIGHT_SHIFT => core_tetris.userRotateCurPiece(t, -1),
        c.GLFW_KEY_R => core_tetris.restartGame(t),
        c.GLFW_KEY_P => core_tetris.userTogglePause(t),
        else => {},
    }
}

fn drawParticle(callback_user_pointer: *allowzero u64, t: *Tetris, p: Particle) void {
    const d = @ptrCast(*Display, callback_user_pointer);
    const model = mat4x4_identity.translateByVec(p.pos).rotate(p.angle, p.axis).scale(p.scale_w, p.scale_h, 0.0);

    const mvp = t.projection.mult(model);

    d.shaders.primitive.bind();
    d.shaders.primitive.setUniformVec4(d.shaders.primitive_uniform_color, p.color);
    d.shaders.primitive.setUniformMat4x4(d.shaders.primitive_uniform_mvp, mvp);

    c.glBindBuffer(c.GL_ARRAY_BUFFER, d.static_geometry.triangle_2d_vertex_buffer);
    c.glEnableVertexAttribArray(@intCast(c.GLuint, d.shaders.primitive_attrib_position));
    c.glVertexAttribPointer(@intCast(c.GLuint, d.shaders.primitive_attrib_position), 3, c.GL_FLOAT, c.GL_FALSE, 0, null);

    c.glDrawArrays(c.GL_TRIANGLE_STRIP, 0, 3);
}

fn drawText(callback_user_pointer: *allowzero u64, t: *Tetris, text: []const u8, left: i32, top: i32, size: f32) void {
    const d = @ptrCast(*Display, callback_user_pointer);
    for (text) |col, i| {
        if (col <= '~') {
            const char_left = @intToFloat(f32, left) + @intToFloat(f32, i * core_tetris.font_char_width) * size;
            const model = mat4x4_identity.translate(char_left, @intToFloat(f32, top), 0.0).scale(size, size, 0.0);
            const mvp = t.projection.mult(model);

            d.font.draw(d.shaders, col, mvp);
        } else {
            unreachable;
        }
    }
}

fn fillRectMvp(callback_user_pointer: *allowzero u64, t: *Tetris, color: Vec4, mvp: Mat4x4) void {
    const d = @ptrCast(*Display, callback_user_pointer);
    d.shaders.primitive.bind();
    d.shaders.primitive.setUniformVec4(d.shaders.primitive_uniform_color, color);
    d.shaders.primitive.setUniformMat4x4(d.shaders.primitive_uniform_mvp, mvp);

    c.glBindBuffer(c.GL_ARRAY_BUFFER, d.static_geometry.rect_2d_vertex_buffer);
    c.glEnableVertexAttribArray(@intCast(c.GLuint, d.shaders.primitive_attrib_position));
    c.glVertexAttribPointer(@intCast(c.GLuint, d.shaders.primitive_attrib_position), 3, c.GL_FLOAT, c.GL_FALSE, 0, null);

    c.glDrawArrays(c.GL_TRIANGLE_STRIP, 0, 4);
}
