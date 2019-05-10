const std = @import("std");
const mem = std.mem;
const os = std.os;
const allocPrint = std.fmt.allocPrint;
const bufPrint = std.fmt.bufPrint;
const warn = std.debug.warn;
const ArrayList = std.ArrayList;
const AutoHashMap = std.AutoHashMap;

const in_name = "main.zig";
const out1_name = "main1.zig";
const out2_name = "main2.zig";
const out1_ref = "main_file";
const build_out1_step_name = "main1";

const pool = std.heap.c_allocator;
fn mprintf(comptime format: []const u8, args: ...) ![] const u8 {
    return allocPrint(pool, format, args);
}

fn append(list: *ArrayList([] const u8), s: []const u8) !void {
    if (s.len == 0 and list.len >= 1 and list.at(list.len - 1).len == 0) {
        return;
    } else {
        try list.append(try mem.dupe(pool, u8, s));
    }
}

pub fn main() !void {
    const in = try std.io.readFileAlloc(pool, "src/" ++ in_name);
    defer pool.free(in);

    var retain_names = std.BufSet.init(pool);
    defer retain_names.deinit();
    try retain_names.put("drawParticle");
    try retain_names.put("drawText");
    try retain_names.put("errorCallback");
    try retain_names.put("fillRectMvp");
    try retain_names.put("keyCallback");
    try retain_names.put("main");

    var out1_list = ArrayList([] const u8).init(pool);
    var out2_list = ArrayList([] const u8).init(pool);

    var out1_map = AutoHashMap([]const u8, usize).init(pool);
    var out2_map = AutoHashMap([]const u8, usize).init(pool);

    try append(&out1_list, try mprintf("use @import(\"{}\");", out2_name));

    var lines = mem.separate(in, "\n");
    var retain = false;
    while (lines.next()) |line| {
        var top_level = line.len >= 1 and line[0] != ' ';
        var tokenizer = std.zig.Tokenizer.init(line);
        var top_name: ?[] const u8 = null;
        var first = tokenizer.next();
        if (top_level) {
            if (first.id == std.zig.Token.Id.Keyword_pub) {
                first = tokenizer.next();
            }
            if (first.id == std.zig.Token.Id.Keyword_extern) {
                first = tokenizer.next();
            }
            var name_token = tokenizer.next();
            top_name = line[name_token.start .. name_token.end];
            if (!retain) {
                if (top_name) |name| {
                    if (first.id == std.zig.Token.Id.Keyword_fn) {
                        if (retain_names.exists(name)) {
                            retain = true;   
                            try append(&out1_list, "");
                        }
                    }
                }
            }
        }
        if (retain) {
            try append(&out1_list, line);
            if (top_name) |name| {
                _ = try out1_map.put(name, out1_list.len - 1);
            }
        } else {
            if (first.id == std.zig.Token.Id.Keyword_use) {
                try append(&out2_list, try mprintf("pub {}", line));
            } else {
                try append(&out2_list, line);
                if (top_name) |name| {
                    _ = try out2_map.put(name, out2_list.len - 1);
                }
            }
        }
        if (top_level) {
            retain = retain and line[0] != '}';
        }
    }

    if (out1_list.at(out1_list.len - 1).len == 0) {
        _ = out1_list.pop();
    }

    if (out2_list.at(out2_list.len - 1).len == 0) {
        _ = out2_list.pop();
    }

    const args = []const []const u8 { "zig", "build", build_out1_step_name };
    while (true) {
        {
            const out1 = try os.File.openWrite("src/" ++ out1_name);
            defer out1.close();
            var lines1 = out1_list.iterator();
            while (lines1.next()) |line| {
                try out1.write(line);
                try out1.write("\n");
            }
        }

        {
            const out2 = try os.File.openWrite("src/" ++ out2_name);
            defer out2.close();
            var lines2 = out2_list.iterator();
            while (lines2.next()) |line| {
                try out2.write(line);
                try out2.write("\n");
            }
        }

        var compile = try os.ChildProcess.exec(pool, args, null, null, 100 * 1024);
        var errors = mem.separate(compile.stderr, "\n");
        if (errors.next()) |error_line| {
            if (mem.indexOf(u8, error_line, "error:")) |_| {
                if (mem.indexOf(u8, error_line, "use of undeclared identifier")) |_| {
                    var list: ArrayList([] const u8) = undefined;
                    var map: AutoHashMap([]const u8, usize) = undefined;
                    if (mem.startsWith(u8, error_line[mem.lastIndexOf(u8, error_line, "/").? + 1 ..], out1_name)) {
                        list = out2_list;
                        map = out2_map;
                        var quotes = mem.separate(error_line, "'");
                        _ = quotes.next();
                        var identifier = quotes.next().?;
                        if (map.get(identifier)) |line_number| {
//                          pool.free(list.at(line_number.value));
                            list.set(line_number.value, try mprintf("pub {}", list.at(line_number.value)));
                            warn("undeclared {} found at {}\n", identifier, line_number.value);
                        } else {
                            warn("undeclared {} could not be found\n", identifier);
                            break;
                        }
                    } else {
                        list = out1_list;
                        map = out1_map;
                        warn("tbd - resolve - use {} - {}\n", out1_ref, error_line);
                        break;
                    }
                } else {
                    warn("tbd - resolve - {}\n", error_line);
                    break;
                }
            } else {
                warn("unrecognized compiler output {}\n", error_line);
                break;
            }
        }
    }
}
