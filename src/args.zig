//! Forked from https://github.com/ikskuh/zig-args/commit/1df15086e5d1b245acedadbec03440bb37871e5e
//!
//! MIT License
//!
//! Copyright (c) 2020 Felix Queißner
//! Copyright (c) 2024 Ratakor
//!
//! Permission is hereby granted, free of charge, to any person obtaining a copy
//! of this software and associated documentation files (the "Software"), to deal
//! in the Software without restriction, including without limitation the rights
//! to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//! copies of the Software, and to permit persons to whom the Software is
//! furnished to do so, subject to the following conditions:
//!
//! The above copyright notice and this permission notice shall be included in all
//! copies or substantial portions of the Software.
//!
//! THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//! IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//! FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//! AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//! LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//! OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//! SOFTWARE.

// TODO: generate completions https://github.com/ikskuh/zig-args/issues/1
// TODO: mutually exclusive options https://github.com/ikskuh/zig-args/issues/15
// TODO: --[no-]option https://github.com/ikskuh/zig-args/issues/54
// TODO: support multiple values per option https://github.com/ikskuh/zig-args/issues/8
// TODO: support shorthands for subcommands

// TODO: Required arguments https://github.com/ikskuh/zig-args/pull/30

// Fixed https://github.com/ikskuh/zig-args/issues/58

const std = @import("std");

/// Parses arguments for the given specification and the current process.
/// - `Config` is the configuration of the arguments.
/// - `allocator` is the allocator that is used to allocate all required memory
/// - `error_handling` defines how parser errors will be handled.
pub fn parse(
    comptime Config: type,
    allocator: std.mem.Allocator,
    comptime error_handling: ErrorHandling,
) !ParseResult(Config) {
    // Use argsWithAllocator for portability.
    // All data allocated by the ArgIterator is freed at the end of the function.
    // Data returned to the user is always duplicated using the allocator.
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    const executable_name = args.next() orelse {
        try error_handling.process(error.NoExecutableName, Error{
            .option = "",
            .kind = .missing_executable_name,
        });

        // we do not assume any more arguments appear here anyways...
        return error.NoExecutableName;
    };

    var result = try parseWithIterator(Config, &args, allocator, error_handling);

    result.executable_name = try result.arena.allocator().dupeZ(u8, executable_name);

    return result;
}

/// Parses arguments for the given specification.
/// - `Generic` is the configuration of the arguments.
/// - `args_iterator` is a pointer to an std.process.ArgIterator that will yield the command line arguments.
/// - `allocator` is the allocator that is used to allocate all required memory
/// - `error_handling` defines how parser errors will be handled.
///
/// Note that `.executable_name` in the result will not be set!
pub fn parseWithIterator(
    comptime Config: type,
    args_iterator: anytype,
    allocator: std.mem.Allocator,
    comptime error_handling: ErrorHandling,
) !ParseResult(Config) {
    var result: ParseResult(Config) = .{
        .arena = std.heap.ArenaAllocator.init(allocator),
        .options = Config{},
        .verb = if (SubCmd(Config) != null) null else {}, // no verb by default
        .positionals = undefined,
        .executable_name = undefined, // set by parseForCurrentProcess
    };
    errdefer result.arena.deinit();
    var result_arena_allocator = result.arena.allocator();

    var arglist = std.ArrayList([:0]const u8).init(allocator);
    defer arglist.deinit();

    var last_error: ?anyerror = null;

    while (args_iterator.next()) |item| {
        if (std.mem.startsWith(u8, item, "--")) {
            if (std.mem.eql(u8, item, "--")) {
                // double hyphen is considered 'everything from here now is positional'
                result.raw_start_index = arglist.items.len;
                break;
            }

            const Pair = struct {
                name: []const u8,
                value: ?[]const u8,
            };

            const pair = if (std.mem.indexOf(u8, item, "=")) |index|
                Pair{
                    .name = item[2..index],
                    .value = item[index + 1 ..],
                }
            else
                Pair{
                    .name = item[2..],
                    .value = null,
                };

            var found = false;
            inline for (std.meta.fields(Config)) |fld| {
                if (std.mem.eql(u8, pair.name, fld.name)) {
                    try parseOption(Config, result_arena_allocator, &result.options, args_iterator, error_handling, &last_error, fld.name, pair.value);
                    found = true;
                }
            }

            if (SubCmd(Config)) |Verb| {
                if (result.verb) |*verb| {
                    if (!found) {
                        const Tag = std.meta.Tag(Verb);
                        inline for (std.meta.fields(Verb)) |verb_info| {
                            if (verb.* == @field(Tag, verb_info.name)) {
                                if (comptime canHaveFieldsAndIsNotZeroSized(verb_info.type)) {
                                    inline for (std.meta.fields(verb_info.type)) |fld| {
                                        if (std.mem.eql(u8, pair.name, fld.name)) {
                                            try parseOption(
                                                verb_info.type,
                                                result_arena_allocator,
                                                &@field(verb.*, verb_info.name),
                                                args_iterator,
                                                error_handling,
                                                &last_error,
                                                fld.name,
                                                pair.value,
                                            );
                                            found = true;
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            if (!found) {
                last_error = error.EncounteredUnknownArgument;
                try error_handling.process(error.EncounteredUnknownArgument, Error{
                    .option = pair.name,
                    .kind = .unknown,
                });
            }
        } else if (std.mem.startsWith(u8, item, "-")) {
            if (std.mem.eql(u8, item, "-")) {
                // single hyphen is considered a positional argument
                try arglist.append(try result_arena_allocator.dupeZ(u8, item));
            } else {
                var any_shorthands = false;
                for (item[1..], 0..) |char, index| {
                    var option_name = [2]u8{ '-', char };
                    var found = false;
                    if (@hasDecl(Config, "shorthands")) {
                        any_shorthands = true;
                        inline for (std.meta.fields(@TypeOf(Config.shorthands))) |fld| {
                            if (fld.name.len != 1)
                                @compileError("All shorthand fields must be exactly one character long!");
                            if (fld.name[0] == char) {
                                const real_name = @field(Config.shorthands, fld.name);
                                const real_fld_type = @TypeOf(@field(result.options, real_name));

                                // -2 because we stripped of the "-" at the beginning
                                if (requiresArg(real_fld_type) and index != item.len - 2) {
                                    last_error = error.EncounteredUnexpectedArgument;
                                    try error_handling.process(error.EncounteredUnexpectedArgument, Error{
                                        .option = &option_name,
                                        .kind = .invalid_placement,
                                    });
                                } else {
                                    try parseOption(Config, result_arena_allocator, &result.options, args_iterator, error_handling, &last_error, real_name, null);
                                }

                                found = true;
                            }
                        }
                    }

                    if (SubCmd(Config)) |Verb| {
                        if (result.verb) |*verb| {
                            if (!found) {
                                const Tag = std.meta.Tag(Verb);
                                inline for (std.meta.fields(Verb)) |verb_info| {
                                    const VerbType = verb_info.type;
                                    if (comptime canHaveFieldsAndIsNotZeroSized(VerbType)) {
                                        if (verb.* == @field(Tag, verb_info.name)) {
                                            const target_value = &@field(verb.*, verb_info.name);
                                            if (@hasDecl(VerbType, "shorthands")) {
                                                any_shorthands = true;
                                                inline for (std.meta.fields(@TypeOf(VerbType.shorthands))) |fld| {
                                                    if (fld.name.len != 1)
                                                        @compileError("All shorthand fields must be exactly one character long!");
                                                    if (fld.name[0] == char) {
                                                        const real_name = @field(VerbType.shorthands, fld.name);
                                                        const real_fld_type = @TypeOf(@field(target_value.*, real_name));

                                                        // -2 because we stripped of the "-" at the beginning
                                                        if (requiresArg(real_fld_type) and index != item.len - 2) {
                                                            last_error = error.EncounteredUnexpectedArgument;
                                                            try error_handling.process(error.EncounteredUnexpectedArgument, Error{
                                                                .option = &option_name,
                                                                .kind = .invalid_placement,
                                                            });
                                                        } else {
                                                            try parseOption(VerbType, result_arena_allocator, target_value, args_iterator, error_handling, &last_error, real_name, null);
                                                        }
                                                        last_error = null; // we need to reset that error here, as it was set previously
                                                        found = true;
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    if (!found) {
                        last_error = error.EncounteredUnknownArgument;
                        try error_handling.process(error.EncounteredUnknownArgument, Error{
                            .option = &option_name,
                            .kind = .unknown,
                        });
                    }
                }
                if (!any_shorthands) {
                    try error_handling.process(error.EncounteredUnsupportedArgument, Error{
                        .option = item,
                        .kind = .unsupported,
                    });
                }
            }
        } else {
            if (SubCmd(Config)) |Verb| {
                if (result.verb == null) {
                    inline for (std.meta.fields(Verb)) |fld| {
                        if (std.mem.eql(u8, item, fld.name)) {
                            // found active verb, default-initialize it
                            result.verb = @unionInit(Verb, fld.name, fld.type{});
                        }
                    }

                    if (result.verb == null) {
                        try error_handling.process(error.EncounteredUnknownVerb, Error{
                            .option = "verb",
                            .kind = .unsupported,
                        });
                    }

                    continue;
                }
            }

            try arglist.append(try result_arena_allocator.dupeZ(u8, item));
        }
    }

    if (last_error != null)
        return error.InvalidArguments;

    // This will consume the rest of the arguments as positional ones.
    // Only executes when the above loop is broken.
    while (args_iterator.next()) |item| {
        try arglist.append(try result_arena_allocator.dupeZ(u8, item));
    }

    result.positionals = try arglist.toOwnedSlice();
    return result;
}

fn canHaveFieldsAndIsNotZeroSized(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .Struct, .Union, .Enum, .ErrorSet => @sizeOf(T) != 0,
        else => false,
    };
}

fn SubCmd(comptime Config: type) ?type {
    if (@hasDecl(Config, "Command")) {
        return Config.Command;
    } else {
        return null;
    }
}

/// The return type of the argument parser.
pub fn ParseResult(comptime Config: type) type {
    if (@typeInfo(Config) != .Struct) {
        @compileError("Config must be a struct");
    }

    if (SubCmd(Config)) |Command| {
        const ti = @typeInfo(Command);
        if (ti != .Union or ti.Union.tag_type == null)
            @compileError("Command must be a tagged union");
    }

    return struct {
        const Self = @This();

        /// Exports the type of options.
        pub const Options = Config;
        pub const Commands = SubCmd(Config) orelse void;

        arena: std.heap.ArenaAllocator,

        /// The options with either default or set values.
        options: Options,

        /// The verb that was parsed or `null` if no first positional was provided.
        /// Is `void` when verb parsing is disabled
        verb: if (SubCmd(Config)) |Command| ?Command else void,

        /// The positional arguments that were passed to the process.
        positionals: [][:0]const u8,

        // The index of the first "raw arg", meaning the first arg after "--"
        raw_start_index: ?usize = null,

        /// Name of the executable file (or args[0])
        executable_name: [:0]const u8,

        pub const help_format = formatHelp(Config);

        pub fn deinit(self: Self) void {
            self.arena.child_allocator.free(self.positionals);
            self.arena.deinit();
        }

        /// help.usage: The usage string that will be printed after the executable name.
        /// help.description: A description of the program.
        /// help.commands: A list of commands that are available.
        /// help.options: A list of options that are available.
        /// help.max_width: The maximum width of the help text.
        /// help.indent: The indentation that is used for the commands and options.
        /// help.indent2: The indentation that is used for the descriptions of the commands and options.
        /// ```
        /// Usage: {executable_name} {help.usage}
        ///
        /// {help.description}
        ///
        /// Commands:
        /// {help.commands}
        ///
        /// Options:
        /// {help.options}
        /// ```
        pub fn printHelp(self: Self, writer: anytype) @TypeOf(writer).Error!void {
            try writer.print(help_format, .{self.executable_name});
            // return printHelpInternal(Generic, self.executable_name, writer);
        }

        pub fn dump(self: Self) void {
            std.debug.print("executable name: {?s}\n", .{self.executable_name});

            std.debug.print("Options:\n", .{});
            inline for (std.meta.fields(Config)) |fld| {
                const value = @field(self.options, fld.name);
                std.debug.print("\t{s}: {any}\n", .{ fld.name, value });
            }

            if (SubCmd(Config)) |_| {
                if (self.verb) |verb| {
                    std.debug.print("Verb: {any}\n", .{verb});
                }
            }

            std.debug.print("Positionals:\n", .{});
            for (self.positionals) |pos| {
                std.debug.print("\t'{s}'\n", .{pos});
            }
        }
    };
}

/// Returns true if the given type requires an argument to be parsed.
fn requiresArg(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .Optional => |opt| requiresArg(opt.child),
        .Int, .Float, .Enum, .Struct, .Union, .Pointer => true,
        .Bool, .Void => false,
        else => @compileError(@typeName(T) ++ " is not a supported argument type!"),
    };
}

/// Parses a boolean option.
fn parseBoolean(str: []const u8) error{NotABooleanValue}!bool {
    return switch (str.len) {
        1 => switch (str[0]) {
            'y', 'Y', 't', 'T' => true,
            'n', 'N', 'f', 'F' => false,
            else => error.NotABooleanValue,
        },
        2 => if (std.ascii.eqlIgnoreCase("no", str)) false else error.NotABooleanValue,
        3 => if (std.ascii.eqlIgnoreCase("yes", str)) true else error.NotABooleanValue,
        4 => if (std.ascii.eqlIgnoreCase("true", str)) true else error.NotABooleanValue,
        5 => if (std.ascii.eqlIgnoreCase("false", str)) false else error.NotABooleanValue,
        else => error.NotABooleanValue,
    };
}

/// Parses an int option.
fn parseInt(comptime T: type, str: []const u8) !T {
    var buf = str;
    var multiplier: T = 1;

    if (buf.len != 0) {
        var base1024 = false;
        if (std.ascii.toLower(buf[buf.len - 1]) == 'i') { //ki vs k for instance
            buf.len -= 1;
            base1024 = true;
        }
        if (buf.len != 0) {
            const pow: u3 = switch (buf[buf.len - 1]) {
                'k', 'K' => 1, //kilo
                'm', 'M' => 2, //mega
                'g', 'G' => 3, //giga
                't', 'T' => 4, //tera
                'p', 'P' => 5, //peta
                else => 0,
            };

            if (pow != 0) {
                buf.len -= 1;

                if (comptime std.math.maxInt(T) < 1024)
                    return error.Overflow;
                const base: T = if (base1024) 1024 else 1000;
                multiplier = try std.math.powi(T, base, @as(T, @intCast(pow)));
            }
        }
    }

    const ret: T = switch (@typeInfo(T).Int.signedness) {
        .signed => try std.fmt.parseInt(T, buf, 0),
        .unsigned => try std.fmt.parseUnsigned(T, buf, 0),
    };

    return try std.math.mul(T, ret, multiplier);
}

/// Converts an argument value to the target type.
fn convertArgumentValue(comptime T: type, allocator: std.mem.Allocator, textInput: []const u8) !T {
    switch (@typeInfo(T)) {
        .Optional => |opt| return try convertArgumentValue(opt.child, allocator, textInput),
        .Bool => if (textInput.len > 0)
            return try parseBoolean(textInput)
        else
            return true, // boolean options are always true
        .Int => return try parseInt(T, textInput),
        .Float => return try std.fmt.parseFloat(T, textInput),
        .Enum => {
            if (@hasDecl(T, "parse")) {
                return try T.parse(textInput);
            } else {
                return std.meta.stringToEnum(T, textInput) orelse return error.InvalidEnumeration;
            }
        },
        .Struct, .Union => {
            if (@hasDecl(T, "parse")) {
                return try T.parse(textInput);
            } else {
                @compileError(@typeName(T) ++ " has no public visible `fn parse([]const u8) !T`!");
            }
        },
        .Pointer => |ptr| switch (ptr.size) {
            .Slice => {
                if (ptr.child != u8) {
                    @compileError(@typeName(T) ++ " is not a supported pointer type, only slices of u8 are supported");
                }

                // If the type contains a sentinel dupe the text input to a new buffer.
                // This is equivalent to allocator.dupeZ but works with any sentinel.
                if (comptime std.meta.sentinel(T)) |sentinel| {
                    const data = try allocator.alloc(u8, textInput.len + 1);
                    @memcpy(data[0..textInput.len], textInput);
                    data[textInput.len] = sentinel;

                    return data[0..textInput.len :sentinel];
                }

                // Otherwise the type is []const u8 so just return the text input.
                return textInput;
            },
            else => @compileError(@typeName(T) ++ " is not a supported pointer type!"),
        },
        .Void => if (textInput.len == 0) return {} else return error.InvalidValue,
        else => @compileError(@typeName(T) ++ " is not a supported argument type!"),
    }
}

/// Parses an option value into the correct type.
fn parseOption(
    comptime Spec: type,
    arena: std.mem.Allocator,
    target_struct: *Spec,
    args: anytype,
    comptime error_handling: ErrorHandling,
    last_error: *?anyerror,
    /// The name of the option that is currently parsed.
    comptime name: []const u8,
    /// Optional pre-defined value for options that use `--foo=bar`
    value: ?[]const u8,
) !void {
    const field_type = @TypeOf(@field(target_struct, name));

    const final_value = if (value) |val| blk: {
        // use the literal value
        const res = try arena.dupeZ(u8, val);
        break :blk res;
    } else if (requiresArg(field_type)) blk: {
        // fetch from parser
        const val = args.next();
        if (val == null or std.mem.eql(u8, val.?, "--")) {
            last_error.* = error.MissingArgument;
            try error_handling.process(error.MissingArgument, Error{
                .option = "--" ++ name,
                .kind = .missing_argument,
            });
            return;
        }

        const res = try arena.dupeZ(u8, val.?);
        break :blk res;
    } else blk: {
        // argument is "empty"
        break :blk "";
    };

    @field(target_struct, name) = convertArgumentValue(field_type, arena, final_value) catch |err| {
        last_error.* = err;
        try error_handling.process(err, Error{
            .option = "--" ++ name,
            .kind = .{ .invalid_value = final_value },
        });
        // we couldn't parse the value, so we return a undefined value as we have signalled an
        // error and won't return this anyways.
        return;
    };
}

/// A collection of errors that were encountered while parsing arguments.
pub const ErrorCollection = struct {
    allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator.State = .{},
    list: std.ArrayListUnmanaged(Error) = .{},

    pub fn deinit(self: *ErrorCollection) void {
        self.list.deinit(self.allocator);
        self.arena.promote(self.allocator).deinit();
        self.* = undefined;
    }

    /// Returns the current enumeration of errors.
    pub fn errors(self: ErrorCollection) []const Error {
        return self.list.items;
    }

    /// Appends an error to the collection
    fn insert(self: *ErrorCollection, err: Error) std.mem.Allocator.Error!void {
        const arena = self.arena.promote(self.allocator).allocator();
        const dupe: Error = .{
            .option = try arena.dupe(u8, err.option),
            .kind = switch (err.kind) {
                .invalid_value => |v| .{ .invalid_value = try arena.dupe(u8, v) },
                .unknown,
                .out_of_memory,
                .unsupported,
                .invalid_placement,
                .missing_argument,
                .missing_executable_name,
                .unknown_verb,
                => err.kind,
            },
        };
        try self.list.append(self.allocator, dupe);
    }
};

/// An argument parsing error.
pub const Error = struct {
    /// The option that yielded the error
    option: []const u8,

    /// The kind of error, might include additional information
    kind: Kind,

    pub fn format(
        self: @This(),
        comptime fmt: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) @TypeOf(writer).Error!void {
        if (fmt.len != 0) {
            std.fmt.invalidFmtError(fmt, self);
        }
        switch (self.kind) {
            .unknown => try writer.print("Unknown option {s}", .{self.option}),
            .invalid_value => |value| try writer.print("Invalid value '{s}' for option {s}", .{ value, self.option }),
            .out_of_memory => try writer.print("Out of memory while parsing option {s}", .{self.option}),
            .unsupported => try writer.writeAll("Short command line options are not supported."),
            .invalid_placement => try writer.writeAll("An option with argument must be the last option for short command line options."),
            .missing_argument => try writer.print("Missing argument for option {s}", .{self.option}),

            .missing_executable_name => try writer.writeAll("Failed to get executable name from the argument list!"),
            .unknown_verb => try writer.print("Unknown verb '{s}'.", .{self.option}),
        }
    }

    pub const Kind = union(enum) {
        /// When the argument itself is unknown
        unknown,

        /// When the parsing of an argument value failed
        invalid_value: []const u8,

        /// When the parsing of an argument value triggered a out of memory error
        out_of_memory,

        /// When the argument is a short argument and no shorthands are enabled
        unsupported, // TODO: should be unknown most of the times

        /// Can only happen when a shorthand for an option requires an argument, but is followed by more shorthands.
        invalid_placement,

        /// An option was passed that requires an argument, but the option was passed last.
        missing_argument,

        /// This error has an empty option name and can only happen when parsing the argument list for a process.
        missing_executable_name,

        /// This error has the verb as an option name and will happen when a verb is provided that is not known.
        unknown_verb,
    };
};

/// The error handling method that should be used.
pub const ErrorHandling = union(enum) {
    /// Do not print or process any errors, just
    /// return a fitting error on the first argument mismatch.
    silent,

    /// Print errors to stderr and return `error.InvalidArguments` on errors.
    print,

    /// Output errors with std.log.err and return `error.InvalidArguments` on errors.
    log,

    /// Collect errors into the error collection and return
    /// `error.InvalidArguments` when any error was encountered.
    collect: *ErrorCollection, // TODO: can't be comptime

    /// Forwards the parsing error to a functionm
    forward: fn (err: Error) anyerror!void,

    /// Processes an error with the given handling method.
    fn process(comptime self: ErrorHandling, src_error: anytype, err: Error) !void {
        if (@typeInfo(@TypeOf(src_error)) != .ErrorSet) {
            @compileError("src_error must be a error union!");
        }
        switch (self) {
            .silent => return src_error,
            .print => try std.io.getStdErr().writer().print("{}\n", .{err}),
            .log => std.log.err("{}", .{err}),
            .collect => |collection| try collection.insert(err),
            .forward => |func| try func(err),
        }
    }
};

const ComptimeStringBuilder = struct {
    items: []const u8 = &[_]u8{},

    pub fn append(comptime self: *ComptimeStringBuilder, comptime items: []const u8) void {
        self.items = self.items ++ items;
    }

    pub fn remove(comptime self: *ComptimeStringBuilder, count: comptime_int) void {
        self.items = self.items[0 .. self.items.len - count];
    }
};

fn formatHelp(comptime Config: type) []const u8 {
    @setEvalBranchQuota(5_000);

    if (!@inComptime()) {
        @compileError("formatHelp must be called at comptime");
    }

    if (!@hasDecl(Config, "help")) {
        @compileError("Missing help declaration in Config");
    }

    var sb: ComptimeStringBuilder = .{};

    const help = Config.help;
    const Help = @TypeOf(help);

    // if (!@hasField(Help, "name")) {
    //     @compileError("Missing name field in help declaration");
    // }
    // sb.append("Usage: " ++ help.name);
    sb.append("Usage: {s}");

    if (@hasField(Help, "usage")) {
        // TODO: support max_width
        //       we can't if we don't know the length of the executable name
        sb.append(" ");
        sb.append(help.usage);
    }

    sb.append("\n\n");

    if (@hasField(Help, "description")) {
        if (@hasField(Help, "max_width")) {
            var words = std.mem.splitScalar(u8, help.description, ' ');
            var pos = 0;
            while (words.next()) |word| {
                if (pos + word.len > help.max_width) {
                    sb.append("\n");
                    pos = 0;
                }
                sb.append(word ++ " ");
                pos += word.len + 1;
            }
            sb.remove(1);
            sb.append("\n\n");
        } else {
            sb.append(help.description ++ "\n\n");
        }
    }

    const indent = if (@hasField(Help, "indent"))
        switch (@typeInfo(@TypeOf(help.indent))) {
            .ComptimeInt => " " ** help.indent,
            .EnumLiteral => switch (help.indent) {
                .tab => "\t",
                else => @compileError("indent must be a positive integer or .tab"),
            },
            else => @compileError("indent must be a positive integer or .tab"),
        }
    else
        " " ** 2;

    const indent2 = if (@hasField(Help, "indent2"))
        switch (@typeInfo(@TypeOf(help.indent2))) {
            .ComptimeInt => " " ** help.indent2,
            // tab doesn't render well as indent2
            else => @compileError("indent2 must be a positive integer"),
        }
    else
        " " ** 4;

    // TODO: add an options to have align command and option descriptions?

    if (@hasField(Help, "commands")) {
        sb.append("Commands:\n");
        const Command = SubCmd(Config) orelse @compileError("Missing Command declaration in Config");
        const fields = std.meta.fields(Command);
        const commands = help.commands;
        comptime var padding = 0;
        comptime for (fields) |field| {
            if (!@hasField(@TypeOf(commands), field.name)) {
                @compileError("Missing command in help declaration: " ++ field.name);
            }
            if (field.name.len > padding) {
                padding = field.name.len;
            }
        };
        // TODO: add support for shorthands
        const newline_offset = padding + indent2.len;

        inline for (fields) |field| {
            sb.append(indent);
            // TODO: shorthands
            sb.append(field.name);
            sb.append(" " ** (padding - field.name.len));
            if (@hasField(Help, "max_width")) {
                var words = std.mem.splitScalar(u8, @field(help.commands, field.name), ' ');
                var pos = indent.len + newline_offset;
                if (words.next()) |word| {
                    sb.append(indent2);
                    sb.append(word);
                    pos += word.len;
                }
                while (words.next()) |word| {
                    if (pos + word.len > help.max_width) {
                        sb.append("\n" ++ indent ++ (" " ** newline_offset) ++ word);
                        pos = indent.len + newline_offset + word.len;
                    } else {
                        sb.append(" " ++ word);
                        pos += word.len + 1;
                    }
                }
                sb.append("\n");
            } else {
                sb.append(indent2);
                sb.append(@field(help.commands, field.name));
                sb.append("\n");
            }
        }
        sb.append("\n");
    }

    if (@hasField(Help, "options")) {
        sb.append("Options:\n");
        const fields = std.meta.fields(Config);
        const options = help.options;
        comptime var padding = 0;
        comptime for (fields) |field| {
            if (!@hasField(@TypeOf(options), field.name)) {
                @compileError("Missing option in help declaration: " ++ field.name);
            }
            if (field.name.len > padding) {
                padding = field.name.len;
            }
        };
        const newline_offset = (if (@hasDecl(Config, "shorthands")) "-x, ".len else 0) + "--".len + padding + indent2.len;

        inline for (fields) |field| {
            sb.append(indent);
            if (@hasDecl(Config, "shorthands")) {
                inline for (comptime std.meta.fieldNames(@TypeOf(Config.shorthands))) |shorthand| {
                    const option = @field(Config.shorthands, shorthand);
                    if (comptime std.mem.eql(u8, option, field.name)) {
                        sb.append("-" ++ shorthand ++ ", ");
                        break;
                    }
                } else {
                    sb.append(" " ** "-x, ".len);
                }
            }
            sb.append("--" ++ field.name);
            sb.append(" " ** (padding - field.name.len));
            if (@hasField(Help, "max_width")) {
                var words = std.mem.splitScalar(u8, @field(options, field.name), ' ');
                var pos = indent.len + newline_offset;
                if (words.next()) |word| {
                    sb.append(indent2);
                    sb.append(word);
                    pos += word.len;
                }
                while (words.next()) |word| {
                    if (pos + word.len > help.max_width) {
                        sb.append("\n" ++ indent ++ (" " ** newline_offset) ++ word);
                        pos = indent.len + newline_offset + word.len;
                    } else {
                        sb.append(" " ++ word);
                        pos += word.len + 1;
                    }
                }
                sb.append("\n");
            } else {
                sb.append(indent2);
                sb.append(@field(options, field.name));
                sb.append("\n");
            }
        }
    }

    return sb.items;
}

test {
    std.testing.refAllDecls(@This());
}

test "parseInt" {
    const tst = std.testing;

    try tst.expectEqual(@as(i32, 50), try parseInt(i32, "50"));
    try tst.expectEqual(@as(i32, 6000), try parseInt(i32, "6k"));
    try tst.expectEqual(@as(u32, 2048), try parseInt(u32, "0x2KI"));
    try tst.expectEqual(@as(i8, 0), try parseInt(i8, "0"));
    try tst.expectEqual(@as(usize, 10_000_000_000), try parseInt(usize, "0xAg"));
    try tst.expectError(error.Overflow, parseInt(i2, "1m"));
    try tst.expectError(error.Overflow, parseInt(u16, "1Ti"));
}

test "ErrorCollection" {
    var option_buf = "option".*;
    var invalid_buf = "invalid".*;

    var ec = ErrorCollection.init(std.testing.allocator);
    defer ec.deinit();

    try ec.insert(Error{
        .option = &option_buf,
        .kind = .{ .invalid_value = &invalid_buf },
    });

    option_buf = undefined;
    invalid_buf = undefined;

    try std.testing.expectEqualStrings("option", ec.errors()[0].option);
    try std.testing.expectEqualStrings("invalid", ec.errors()[0].kind.invalid_value);
}

const TestIterator = struct {
    sequence: []const [:0]const u8,
    index: usize = 0,

    pub fn init(items: []const [:0]const u8) TestIterator {
        return TestIterator{ .sequence = items };
    }

    pub fn next(self: *@This()) ?[:0]const u8 {
        if (self.index >= self.sequence.len)
            return null;
        const result = self.sequence[self.index];
        self.index += 1;
        return result;
    }
};

const TestEnum = enum { default, special, slow, fast };

const TestGenericOptions = struct {
    output: ?[]const u8 = null,
    @"with-offset": bool = false,
    @"with-hexdump": bool = false,
    @"intermix-source": bool = false,
    numberOfBytes: ?i32 = null,
    signed_number: ?i64 = null,
    unsigned_number: ?u64 = null,
    mode: TestEnum = .default,

    // This declares short-hand options for single hyphen
    pub const shorthands = .{
        .S = "intermix-source",
        .b = "with-hexdump",
        .O = "with-offset",
        .o = "output",
    };
};

const TestGenericOptionsWithVerb = struct {
    output: ?[]const u8 = null,
    @"with-offset": bool = false,
    @"with-hexdump": bool = false,
    @"intermix-source": bool = false,
    numberOfBytes: ?i32 = null,
    signed_number: ?i64 = null,
    unsigned_number: ?u64 = null,
    mode: TestEnum = .default,

    // This declares short-hand options for single hyphen
    pub const shorthands = .{
        .S = "intermix-source",
        .b = "with-hexdump",
        .O = "with-offset",
        .o = "output",
    };

    pub const Command = union(enum) {
        magic: MagicOptions,
        booze: BoozeOptions,

        const MagicOptions = struct { invoke: bool = false };
        const BoozeOptions = struct {
            cocktail: bool = false,
            longdrink: bool = false,

            pub const shorthands = .{
                .c = "cocktail",
                .l = "longdrink",
            };
        };
    };
};

test "basic parsing (no verbs)" {
    var tit = TestIterator.init(&[_][:0]const u8{
        "--output",
        "foobar",
        "--with-offset",
        "--numberOfBytes",
        "-250",
        "--unsigned_number",
        "0xFF00FF",
        "positional 1",
        "--mode",
        "special",
        "positional 2",
    });
    var args = try parseWithIterator(TestGenericOptions, &tit, std.testing.allocator, .print);
    defer args.deinit();

    // try std.testing.expectEqual(@as(?[:0]const u8, null), args.executable_name);
    try std.testing.expect(void == @TypeOf(args.verb));
    try std.testing.expectEqual(@as(usize, 2), args.positionals.len);
    try std.testing.expectEqualStrings("positional 1", args.positionals[0]);
    try std.testing.expectEqualStrings("positional 2", args.positionals[1]);

    try std.testing.expectEqualStrings("foobar", args.options.output.?);

    try std.testing.expectEqual(@as(?i32, -250), args.options.numberOfBytes);
    try std.testing.expectEqual(@as(?u64, 0xFF00FF), args.options.unsigned_number);
    try std.testing.expectEqual(TestEnum.special, args.options.mode);

    try std.testing.expectEqual(@as(?i64, null), args.options.signed_number);

    try std.testing.expectEqual(true, args.options.@"with-offset");
    try std.testing.expectEqual(false, args.options.@"with-hexdump");
    try std.testing.expectEqual(false, args.options.@"intermix-source");
}

test "shorthand parsing (no verbs)" {
    var tit = TestIterator.init(&[_][:0]const u8{
        "-o",
        "foobar",
        "-O",
        "--numberOfBytes",
        "-250",
        "--unsigned_number",
        "0xFF00FF",
        "positional 1",
        "--mode",
        "special",
        "positional 2",
    });
    var args = try parseWithIterator(TestGenericOptions, &tit, std.testing.allocator, .print);
    defer args.deinit();

    // try std.testing.expectEqual(@as(?[:0]const u8, null), args.executable_name);
    try std.testing.expect(void == @TypeOf(args.verb));
    try std.testing.expectEqual(@as(usize, 2), args.positionals.len);
    try std.testing.expectEqualStrings("positional 1", args.positionals[0]);
    try std.testing.expectEqualStrings("positional 2", args.positionals[1]);

    try std.testing.expectEqualStrings("foobar", args.options.output.?);

    try std.testing.expectEqual(@as(?i32, -250), args.options.numberOfBytes);
    try std.testing.expectEqual(@as(?u64, 0xFF00FF), args.options.unsigned_number);
    try std.testing.expectEqual(TestEnum.special, args.options.mode);

    try std.testing.expectEqual(@as(?i64, null), args.options.signed_number);

    try std.testing.expectEqual(true, args.options.@"with-offset");
    try std.testing.expectEqual(false, args.options.@"with-hexdump");
    try std.testing.expectEqual(false, args.options.@"intermix-source");
}

test "basic parsing (with verbs)" {
    var tit = TestIterator.init(&[_][:0]const u8{
        "--output", // non-verb options can come before or after verb
        "foobar",
        "booze", // verb
        "--with-offset",
        "--numberOfBytes",
        "-250",
        "--unsigned_number",
        "0xFF00FF",
        "positional 1",
        "--mode",
        "special",
        "positional 2",
        "--cocktail",
    });
    var args = try parseWithIterator(TestGenericOptionsWithVerb, &tit, std.testing.allocator, .print);
    defer args.deinit();

    // try std.testing.expectEqual(@as(?[:0]const u8, null), args.executable_name);
    try std.testing.expect(?TestGenericOptionsWithVerb.Command == @TypeOf(args.verb));
    try std.testing.expectEqual(@as(usize, 2), args.positionals.len);
    try std.testing.expectEqualStrings("positional 1", args.positionals[0]);
    try std.testing.expectEqualStrings("positional 2", args.positionals[1]);

    try std.testing.expectEqualStrings("foobar", args.options.output.?);

    try std.testing.expectEqual(@as(?i32, -250), args.options.numberOfBytes);
    try std.testing.expectEqual(@as(?u64, 0xFF00FF), args.options.unsigned_number);
    try std.testing.expectEqual(TestEnum.special, args.options.mode);

    try std.testing.expectEqual(@as(?i64, null), args.options.signed_number);

    try std.testing.expectEqual(true, args.options.@"with-offset");
    try std.testing.expectEqual(false, args.options.@"with-hexdump");
    try std.testing.expectEqual(false, args.options.@"intermix-source");

    try std.testing.expect(args.verb.? == .booze);

    const booze = args.verb.?.booze;

    try std.testing.expectEqual(true, booze.cocktail);
    try std.testing.expectEqual(false, booze.longdrink);
}

test "shorthand parsing (with verbs)" {
    var tit = TestIterator.init(&[_][:0]const u8{
        "booze", // verb
        "-o",
        "foobar",
        "-O",
        "--numberOfBytes",
        "-250",
        "--unsigned_number",
        "0xFF00FF",
        "positional 1",
        "--mode",
        "special",
        "positional 2",
        "-c", // --cocktail
    });
    var args = try parseWithIterator(TestGenericOptionsWithVerb, &tit, std.testing.allocator, .print);
    defer args.deinit();

    // try std.testing.expectEqual(@as(?[:0]const u8, null), args.executable_name);
    try std.testing.expect(?TestGenericOptionsWithVerb.Command == @TypeOf(args.verb));
    try std.testing.expectEqual(@as(usize, 2), args.positionals.len);
    try std.testing.expectEqualStrings("positional 1", args.positionals[0]);
    try std.testing.expectEqualStrings("positional 2", args.positionals[1]);

    try std.testing.expectEqualStrings("foobar", args.options.output.?);

    try std.testing.expectEqual(@as(?i32, -250), args.options.numberOfBytes);
    try std.testing.expectEqual(@as(?u64, 0xFF00FF), args.options.unsigned_number);
    try std.testing.expectEqual(TestEnum.special, args.options.mode);

    try std.testing.expectEqual(@as(?i64, null), args.options.signed_number);

    try std.testing.expectEqual(true, args.options.@"with-offset");
    try std.testing.expectEqual(false, args.options.@"with-hexdump");
    try std.testing.expectEqual(false, args.options.@"intermix-source");

    try std.testing.expect(args.verb.? == .booze);

    const booze = args.verb.?.booze;

    try std.testing.expectEqual(true, booze.cocktail);
    try std.testing.expectEqual(false, booze.longdrink);
}

test "strings with sentinel" {
    var tit = TestIterator.init(&[_][:0]const u8{
        "--output",
        "foobar",
    });
    var args = try parseWithIterator(
        struct {
            output: ?[:0]const u8 = null,
        },
        &tit,
        std.testing.allocator,
        .print,
    );
    defer args.deinit();

    // try std.testing.expectEqual(@as(?[:0]const u8, null), args.executable_name);
    try std.testing.expect(void == @TypeOf(args.verb));
    try std.testing.expectEqual(@as(usize, 0), args.positionals.len);

    try std.testing.expectEqualStrings("foobar", args.options.output.?);
}

test "option argument --" {
    var tit = TestIterator.init(&[_][:0]const u8{
        "--output",
        "--",
    });

    try std.testing.expectError(error.MissingArgument, parseWithIterator(
        struct {
            output: ?[:0]const u8 = null,
        },
        &tit,
        std.testing.allocator,
        .silent,
    ));
}

test "index of raw indicator --" {
    var tit = TestIterator.init(&[_][:0]const u8{ "stdin", "-", "--", "not-stdin", "-", "--" });

    var args = try parseWithIterator(
        struct {},
        &tit,
        std.testing.allocator,
        .print,
    );
    defer args.deinit();

    try std.testing.expectEqual(args.raw_start_index, 2);
    try std.testing.expectEqual(args.positionals.len, 5);
}

test "full help" {
    const Options = struct {
        boolflag: bool = false,
        stringflag: []const u8 = "hello",

        pub const shorthands = .{
            .b = "boolflag",
        };

        pub const help = .{
            .name = "test", // TODO
            .usage = "[--boolflag] [--stringflag]",
            .description = "testing tool",
            .options = .{
                .boolflag = "a boolean flag",
                .stringflag = "a string flag",
            },
            .indent = .tab,
        };
    };

    const expected =
        \\Usage: {s} [--boolflag] [--stringflag]
        \\
        \\testing tool
        \\
        \\Options:
        \\	-b, --boolflag      a boolean flag
        \\	    --stringflag    a string flag
        \\
    ;

    try std.testing.expectEqualStrings(expected, comptime formatHelp(Options));
}

test "help with no usage summary" {
    const Options = struct {
        boolflag: bool = false,
        stringflag: []const u8 = "hello",

        pub const shorthands = .{
            .b = "boolflag",
        };

        pub const help = .{
            .description = "testing tool",
            .options = .{
                .boolflag = "a boolean flag",
                .stringflag = "a string flag",
            },
        };
    };

    const expected =
        \\Usage: {s}
        \\
        \\testing tool
        \\
        \\Options:
        \\  -b, --boolflag      a boolean flag
        \\      --stringflag    a string flag
        \\
    ;

    try std.testing.expectEqualStrings(expected, comptime formatHelp(Options));
}

test "help with wrapping" {
    const Options = struct {
        boolflag: bool = false,
        stringflag: []const u8 = "hello",

        pub const shorthands = .{
            .b = "boolflag",
        };

        pub const help = .{
            .description = "testing tool",
            .options = .{
                .boolflag = "a boolean flag with a pretty long description about booleans",
                .stringflag = "a string flag with another long description about strings",
            },
            .max_width = 50,
        };
    };

    const expected =
        \\Usage: {s}
        \\
        \\testing tool
        \\
        \\Options:
        \\  -b, --boolflag      a boolean flag with a pretty
        \\                      long description about
        \\                      booleans
        \\      --stringflag    a string flag with another
        \\                      long description about
        \\                      strings
        \\
    ;

    try std.testing.expectEqualStrings(expected, comptime formatHelp(Options));
}
