const std = @import("std");
const builtin = @import("builtin");
const zdt = @import("zdt");
const ziggy = @import("ziggy");
const kf = @import("known-folders");
const args = @import("args.zig");

const version = std.SemanticVersion.parse("0.5.0") catch unreachable;

pub const std_options: std.Options = .{
    .logFn = coloredLog,
};

fn coloredLog(
    comptime message_level: std.log.Level,
    comptime scope: @TypeOf(.enum_literal),
    comptime format: []const u8,
    arguments: anytype,
) void {
    const level_txt = comptime switch (builtin.os.tag) {
        .windows, .wasi => std.log.Level.asText(message_level),
        else => switch (message_level) {
            .err => "\x1b[31;1merror\x1b[m",
            .warn => "\x1b[33;1mwarning\x1b[m",
            .info => "\x1b[34;1minfo\x1b[m",
            .debug => "\x1b[36;1mdebug\x1b[m",
        },
    };
    const scope_prefix = (if (scope != .default) "@" ++ @tagName(scope) else "") ++ ": ";
    const stderr = std.io.getStdErr().writer();
    var bw = std.io.bufferedWriter(stderr);
    const writer = bw.writer();

    std.debug.lockStdErr();
    defer std.debug.unlockStdErr();
    nosuspend {
        writer.print(level_txt ++ scope_prefix ++ format ++ "\n", arguments) catch return;
        bw.flush() catch return;
    }
}

// TODO: make this store its arena allocator?
const Config = struct {
    env_map: std.process.EnvMap,
    calendar: []const []const u8,
    calendar_path: []const u8,
    language: []const u8,
    editor: []const u8,
    header: bool,
    past: i64,
    future: u64,
    yesterday: []const u8,
    today: []const u8,
    tomorrow: []const u8,
    special: []const u8,
    mondayfirst: bool,
    arena: std.heap.ArenaAllocator,

    const Ziggy = struct {
        calendar: ?[]const u8 = null,
        language: ?[]const u8 = null,
        editor: ?[]const u8 = null,
        header: bool = true,
        past: i64 = -1,
        future: u64 = 14,
        yesterday: []const u8 = "yesterday",
        today: []const u8 = "\x1b[1mtoday",
        tomorrow: []const u8 = "tomorrow",
        special: []const u8 = "special",
        mondayfirst: bool = false,
    };

    // TODO: merge with init
    fn default(allocator: std.mem.Allocator, env_map: std.process.EnvMap) !Config {
        const data_folder = try kf.getPath(allocator, .data) orelse
            return error.EnvironmentVariableNotFound;
        defer allocator.free(data_folder);
        var arena = std.heap.ArenaAllocator.init(allocator);
        return .{
            .env_map = env_map,
            .calendar = undefined,
            .calendar_path = try std.fs.path.join(
                arena.allocator(),
                &[_][]const u8{ data_folder, "quand", "calendar" },
            ),
            .language = env_map.get("LANG") orelse "en_US.UTF-8",
            .editor = env_map.get("EDITOR") orelse "vi",
            .header = true,
            .past = -1,
            .future = 14,
            .yesterday = "yesterday",
            .today = "\x1b[1mtoday",
            .tomorrow = "tomorrow",
            .special = "special",
            .mondayfirst = false,
            .arena = arena,
        };
    }

    /// fetchCalendar must be called after init
    pub fn init(allocator: std.mem.Allocator) !Config {
        var arena = std.heap.ArenaAllocator.init(allocator);
        const env_map = try std.process.getEnvMap(allocator);

        const config_folder = try kf.getPath(allocator, .local_configuration) orelse
            return error.EnvironmentVariableNotFound;
        defer allocator.free(config_folder);
        const config_path = try std.fs.path.join(
            allocator,
            &[_][]const u8{ config_folder, "quand", "config.ziggy" },
        );
        defer allocator.free(config_path);
        const cwd = std.fs.cwd();
        const config_file = cwd.openFile(config_path, .{}) catch |err| switch (err) {
            error.FileNotFound => {
                const config_file = try cwd.createFile(config_path, .{});
                defer config_file.close();
                var bw = std.io.bufferedWriter(config_file.writer());
                try ziggy.stringify(Config.Ziggy{}, .{
                    .whitespace = .tab,
                    .emit_null_fields = true,
                    .omit_top_level_curly = true,
                }, bw.writer());
                try bw.flush();

                return Config.default(allocator, env_map);
            },
            else => return err,
        };
        defer config_file.close();

        const config_file_content = try config_file.readToEndAllocOptions(allocator, 4096, null, @alignOf(u8), 0);
        defer allocator.free(config_file_content);

        var diag: ziggy.Diagnostic = .{ .path = config_path };
        const ziggy_config = ziggy.parseLeaky(Config.Ziggy, arena.allocator(), config_file_content, .{
            .diagnostic = &diag,
            .copy_strings = .always,
        }) catch |err| {
            std.log.err("{}", .{diag});
            return err;
        };

        const calendar_path = path: {
            if (ziggy_config.calendar) |path| {
                break :path path;
            } else {
                const data_folder = try kf.getPath(allocator, .data) orelse
                    return error.EnvironmentVariableNotFound;
                defer allocator.free(data_folder);
                break :path try std.fs.path.join(
                    arena.allocator(),
                    &[_][]const u8{ data_folder, "quand", "calendar" },
                );
            }
        };

        return .{
            .env_map = env_map,
            .calendar = undefined,
            .calendar_path = calendar_path,
            .language = ziggy_config.language orelse env_map.get("LANG") orelse "en_US.UTF-8",
            .editor = ziggy_config.editor orelse env_map.get("EDITOR") orelse "vi",
            .header = ziggy_config.header,
            .past = ziggy_config.past,
            .future = ziggy_config.future,
            .yesterday = ziggy_config.yesterday,
            .today = ziggy_config.today,
            .tomorrow = ziggy_config.tomorrow,
            .special = ziggy_config.special,
            .mondayfirst = ziggy_config.mondayfirst,
            .arena = arena,
        };
    }

    pub fn deinit(self: *Config) void {
        self.env_map.deinit();
        self.arena.deinit();
    }

    pub fn fetchCalendar(self: *Config) !void {
        const allocator = self.arena.allocator();
        const file = std.fs.cwd().openFile(self.calendar_path, .{}) catch |err| switch (err) {
            error.FileNotFound => std.zig.fatal("Calendar file `{s}` not found", .{self.calendar_path}),
            else => return err,
        };
        defer file.close();
        var br = std.io.bufferedReader(file.reader());
        const reader = br.reader();
        var lines: std.ArrayListUnmanaged([]const u8) = .{};
        while (try reader.readUntilDelimiterOrEofAlloc(allocator, '\n', 4096)) |line| {
            try lines.append(allocator, line);
        }

        std.mem.sort([]const u8, lines.items, {}, struct {
            fn lessThan(_: void, lhs: []const u8, rhs: []const u8) bool {
                return std.mem.order(u8, lhs, rhs) == .lt;
            }
        }.lessThan);

        self.calendar = try lines.toOwnedSlice(allocator);
    }
};

fn makePattern(
    comptime fmt: []const u8,
    allocator: std.mem.Allocator,
    date: zdt.Datetime,
) ![]const u8 {
    var al = std.ArrayList(u8).init(allocator);
    try date.toString(fmt, al.writer());
    return al.toOwnedSlice();
}

// TODO: tokenize instead of using std.mem.startsWith...
// no allocation + allow for more complex patterns
fn printDate(
    allocator: std.mem.Allocator,
    date: zdt.Datetime,
    config: Config,
    writer: anytype,
    arg: ?[]const u8,
) !void {
    const pattern1 = try makePattern("%Y %m %d", allocator, date);
    defer allocator.free(pattern1);
    const pattern2 = try makePattern("* %m %d", allocator, date);
    defer allocator.free(pattern2);
    const pattern3 = try makePattern("* * %d", allocator, date);
    defer allocator.free(pattern3);
    const pattern4 = date.weekday().shortName();
    const day_name = arg orelse pattern4;

    for (config.calendar) |line| {
        // TODO: print {s: <12} doesn't work because of the color codes
        if (std.mem.startsWith(u8, line, pattern1)) {
            try writer.print("{s: <12}\x1b[m {s}\n", .{ day_name, line });
        } else if (std.mem.startsWith(u8, line, pattern2)) {
            try writer.print("{s: <12}\x1b[m {s}\n", .{ day_name, line["* ".len..] });
        } else if (std.mem.startsWith(u8, line, pattern3)) {
            try writer.print("{s: <12}\x1b[m {s}\n", .{ day_name, line["* * ".len..] });
        } else if (std.mem.startsWith(u8, line, pattern4)) {
            try writer.print("{s: <12}\x1b[m {s}\n", .{ day_name, line[pattern4.len..] });
        }
    }
}

fn printSpecial(config: Config, writer: anytype) !void {
    const pattern = "* * *";
    for (config.calendar) |line| {
        if (std.mem.startsWith(u8, line, pattern)) {
            try writer.print("{s}\x1b[m{s}\n", .{ config.special, line[pattern.len..] });
        }
    }
}

// TODO: no, make it a builtin
fn spawnCalendar(allocator: std.mem.Allocator, config: *Config, writer: anytype, n: []const u8) !void {
    try config.env_map.put("LC_ALL", config.language);
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "cal", if (config.mondayfirst) "-m" else "-s", "-n", n },
        .env_map = &config.env_map,
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    switch (result.term) {
        .Exited => |status| if (status != 0) {
            const stderr = std.io.getStdErr().writer();
            try stderr.writeAll(result.stderr);
            std.process.exit(status);
        },
        inline .Signal, .Stopped, .Unknown => |code| std.debug.panic("cal failed: {} ({d})\n", .{
            std.meta.activeTag(result.term),
            code,
        }),
    }
    try writer.writeAll(result.stderr);
    try writer.writeAll(result.stdout);
}

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    const use_gpa = builtin.mode == .Debug;
    const allocator = if (use_gpa)
        gpa.allocator()
        // We would prefer to use raw libc allocator here, but cannot
        // use it if it won't support the alignment we need.
    else if (@alignOf(std.c.max_align_t) < @max(@alignOf(i128), std.atomic.cache_line))
        std.heap.c_allocator
    else
        std.heap.raw_c_allocator;
    defer if (use_gpa) {
        _ = gpa.deinit();
    };

    var config = try Config.init(allocator);
    defer config.deinit();

    const stdout = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout);
    defer bw.flush() catch {};
    const writer = bw.writer();

    const Options = struct {
        calendar: ?[]const u8 = null,
        date: ?[]const u8 = null,
        past: ?i32 = null,
        future: ?u32 = null,
        help: ?void = null,
        version: ?void = null,

        pub const shorthands = .{
            .c = "calendar",
            .d = "date",
            .p = "past",
            .f = "future",
            .h = "help",
            .v = "version",
        };

        pub const Command = union(enum) {
            edit,
            cal,

            pub const shorthands = .{
                .e = "edit",
                .c = "cal",
            };
        };

        pub const help = .{
            .usage = "[command] [options]",
            // .description = "a simple calendar",
            .commands = .{
                .edit = "Edit the calendar file",
                .cal = "Display a calendar with 1 or the given months",
            },
            .options = .{
                .calendar = "Temporarily change the calendar file",
                .date = "Output events for a specific date, format: YYYY-MM-DD",
                .past = "Temporarily change the number of past days",
                .future = "Temporarily change the number of future days",
                .help = "Print this help message",
                .version = "Print version information",
            },
        };
    };
    const cli = try args.parse(Options, allocator, .log);
    defer cli.deinit();

    if (false and builtin.mode == .Debug) {
        cli.dump();
    }

    // TODO: error: Short command line options are not supported.
    // if (cli.verb == null or cli.verb.? != .cal) {
    //     for (cli.positionals) |arg| {
    //         std.log.warn("Unknown argument: {s}", .{arg});
    //     }
    // }

    if (cli.options.help) |_| {
        try cli.printHelp(writer);
        try writer.writeAll(
            \\
            \\Have a look at the man page for more information about the configuration.
            \\
        );
        return;
    } else if (cli.options.version) |_| {
        try writer.print("quand {}\n", .{version});
        return;
    } else if (cli.verb) |verb| {
        switch (verb) {
            .edit => return std.process.execv(allocator, &[_][]const u8{ config.editor, config.calendar_path }),
            .cal => {
                const arg = if (cli.positionals.len > 0) cli.positionals[0] else "1";
                return spawnCalendar(allocator, &config, writer, arg);
            },
        }
    }

    if (cli.options.calendar) |calendar_path_arg| {
        config.calendar_path = calendar_path_arg;
    }
    if (cli.options.date) |date| {
        _ = date;
        unreachable; // TODO
    }
    if (cli.options.past) |past| {
        config.past = if (past > 0) -past else past;
    }
    if (cli.options.future) |future| {
        config.future = future;
    }

    try config.fetchCalendar();

    // TODO: store tz and now in Config?
    var tz = if (config.env_map.get("TZ")) |tz_str|
        try zdt.Timezone.fromTzdata(tz_str, allocator)
    else
        try zdt.Timezone.tzLocal(allocator);
    defer tz.deinit();

    const now = try zdt.Datetime.now(tz);

    if (config.header) {
        try now.toString("%a %b %e %I:%M:%S %P %:Z %Y\n\n", writer);
    }

    while (config.past < -1) : (config.past += 1) {
        const date = try now.add(.{ .__sec = config.past * std.time.s_per_day });
        try printDate(allocator, date, config, writer, null);
    }

    if (config.past == -1) {
        const date = try now.sub(.{ .__sec = std.time.s_per_day });
        try printDate(allocator, date, config, writer, config.yesterday);
    }

    try printDate(allocator, now, config, writer, config.today);

    if (config.future >= 1) {
        const date = try now.add(.{ .__sec = std.time.s_per_day });
        try printDate(allocator, date, config, writer, config.tomorrow);
    }

    var n: i64 = 2;
    while (config.future > 1) : (config.future -= 1) {
        const date = try now.add(.{ .__sec = n * std.time.s_per_day });
        try printDate(allocator, date, config, writer, null);
        n += 1;
    }

    try printSpecial(config, writer);
}
