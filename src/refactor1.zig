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

const ZigFile = struct {
    const Self = @This();

    lines: ArrayList([] const u8),
    map: AutoHashMap([]const u8, usize),
    path: []const u8,

    pub fn init(path: []const u8) Self {
        var self: Self = undefined;
        self.path = path;
        self.lines = ArrayList([] const u8).init(pool);
        self.map  = AutoHashMap([]const u8, usize).init(pool);
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.lines.deinit();
        self.map.deinit();
    }

    pub fn append(self: *Self, s: []const u8) !void {
        if (s.len == 0 and self.lines.len >= 1 and self.lines.at(self.lines.len - 1).len == 0) {
            return;
        } else {
            try self.lines.append(try mem.dupe(pool, u8, s));
        }
    }

    pub fn removeTrailingBlanks(self: *Self) void {
        if (self.lines.at(self.lines.len - 1).len == 0) {
            _ = self.lines.pop();
        }
    }

    pub fn setTopName(self: *Self, name: []const u8) !void {
        _ = try self.map.put(name, self.lines.len - 1);
    }

    pub fn write(self: *Self) !void {
        const f = try os.File.openWrite(self.path);
        defer f.close();
        var lines1 = self.lines.iterator();
        while (lines1.next()) |line| {
            try f.write(line);
            try f.write("\n");
        }
    }
};

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

    var out1 = ZigFile.init("src/" ++ out1_name);
    var out2 = ZigFile.init("src/" ++ out2_name);

    try out1.append(try mprintf("use @import(\"{}\");", out2_name));

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
                            try out1.append("");
                        }
                    }
                }
            }
        }
        if (retain) {
            try out1.append(line);
            if (top_name) |name| {
                try out1.setTopName(name);
            }
        } else {
            if (first.id == std.zig.Token.Id.Keyword_use) {
                try out2.append(try mprintf("pub {}", line));
            } else {
                try out2.append(line);
                if (top_name) |name| {
                    try out2.setTopName(name);
                }
            }
        }
        if (top_level) {
            retain = retain and line[0] != '}';
        }
    }

    out1.removeTrailingBlanks();
    out2.removeTrailingBlanks();

    const args = []const []const u8 { "zig", "build", build_out1_step_name };
    while (true) {
        try out1.write();
        try out2.write();

        var compile = try os.ChildProcess.exec(pool, args, null, null, 100 * 1024);
        var errors = mem.separate(compile.stderr, "\n");
        if (errors.next()) |error_line| {
            if (mem.indexOf(u8, error_line, "error:")) |_| {
                if (mem.indexOf(u8, error_line, "use of undeclared identifier")) |_| {
                    var file: *ZigFile = undefined;
                    if (mem.startsWith(u8, error_line[mem.lastIndexOf(u8, error_line, "/").? + 1 ..], out1_name)) {
                        file = &out2;
                        var quotes = mem.separate(error_line, "'");
                        _ = quotes.next();
                        var identifier = quotes.next().?;
                        if (file.map.get(identifier)) |line_number| {
//                          pool.free(file.lines..at(line_number.value));
                            file.lines.set(line_number.value, try mprintf("pub {}", file.lines.at(line_number.value)));
                            warn("undeclared {} found at {}\n", identifier, line_number.value);
                        } else {
                            warn("undeclared {} could not be found\n", identifier);
                            break;
                        }
                    } else {
                        file = &out1;
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
