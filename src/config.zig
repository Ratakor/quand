const std = @import("std");
const Allocator = std.mem.Allocator;

const ParseError = Allocator.Error;

pub fn Managed(comptime T: type) type {
    return struct {
        arena: *std.heap.ArenaAllocator,
        value: T,

        pub fn deinit(self: @This()) void {
            const allocator = self.arena.child_allocator;
            self.arena.deinit();
            allocator.destroy(self.arena);
        }
    };
}

pub const Scanner = struct {
    state: State = .value,
    string_is_object_key: bool = false,
    stack: std.BitStack,
    input: []const u8,
    cursor: usize = 0,
    is_end_of_input: bool = false,
    diagnostics: ?*Diagnostics = null,

    pub const State = enum {
        value,
        post_value,

        object_start,
        object_post_comma,

        array_start,

        number_minus,
        number_leading_zero,
        number_int,
        number_post_dot,
        number_frac,
        number_post_e,
        number_post_e_sign,
        number_exp,

        string,
        string_backslash,
        string_backslash_u,
        string_backslash_u_1,
        string_backslash_u_2,
        string_backslash_u_3,
        string_surrogate_half,
        string_surrogate_half_backslash,
        string_surrogate_half_backslash_u,
        string_surrogate_half_backslash_u_1,
        string_surrogate_half_backslash_u_2,
        string_surrogate_half_backslash_u_3,

        // From http://unicode.org/mail-arch/unicode-ml/y2003-m02/att-0467/01-The_Algorithm_to_Valide_an_UTF-8_String
        string_utf8_last_byte, // State A
        string_utf8_second_to_last_byte, // State B
        string_utf8_second_to_last_byte_guard_against_overlong, // State C
        string_utf8_second_to_last_byte_guard_against_surrogate_half, // State D
        string_utf8_third_to_last_byte, // State E
        string_utf8_third_to_last_byte_guard_against_overlong, // State F
        string_utf8_third_to_last_byte_guard_against_too_large, // State G

        literal_t,
        literal_tr,
        literal_tru,
        literal_f,
        literal_fa,
        literal_fal,
        literal_fals,
        literal_n,
        literal_nu,
        literal_nul,
    };

    pub const Token = union(enum) {
        object_begin,
        object_end,
        array_begin,
        array_end,

        true,
        false,
        null,

        number: []const u8,
        partial_number: []const u8,
        allocated_number: []u8,

        string: []const u8,
        partial_string: []const u8,
        partial_string_escaped_1: [1]u8,
        partial_string_escaped_2: [2]u8,
        partial_string_escaped_3: [3]u8,
        partial_string_escaped_4: [4]u8,
        allocated_string: []u8,

        end_of_document,

        pub const Type = enum {
            object_begin,
            object_end,
            array_begin,
            array_end,
            true,
            false,
            null,
            number,
            string,
            end_of_document,
        };
    };

    pub const Diagnostics = struct {
        line_number: u64 = 1,
        /// Start just "before" the input buffer to get a 1-based column for line 1.
        line_start_cursor: usize = @as(usize, @bitCast(@as(isize, -1))),
        total_bytes_before_current_input: u64 = 0,
        cursor_pointer: *const usize = undefined,

        /// Starts at 1.
        pub fn getLine(self: *const @This()) u64 {
            return self.line_number;
        }
        /// Starts at 1.
        pub fn getColumn(self: *const @This()) u64 {
            return self.cursor_pointer.* -% self.line_start_cursor;
        }
        /// Starts at 0. Measures the byte offset since the start of the input.
        pub fn getByteOffset(self: *const @This()) u64 {
            return self.total_bytes_before_current_input + self.cursor_pointer.*;
        }
    };

    const object_mode = 0;
    const array_mode = 1;

    pub fn initCompleteInput(allocator: Allocator, complete_input: []const u8) Scanner {
        return .{
            .input = complete_input,
            .is_end_of_input = true,
            .stack = std.BitStack.init(allocator),
        };
    }

    pub fn deinit(self: *Scanner) void {
        _ = self;
    }

    pub fn next(self: *Scanner) !Token {
        state_loop: while (true) {
            switch(self.state) {
                .value => {
                    switch (try self.skipWhitespaceExpectByte()) {
                        // Object, Array
                        '{' => {
                            try self.stack.push(object_mode);
                            self.cursor += 1;
                            self.state  = .object_start;
                            return .object_begin;
                        },
                        '[' => {
                            try self.stack.push(array_mode);
                            self.cursor += 1;
                            self.state = .array_start;
                            return .array_begin;
                        },

                        // String
                        '"' => {
                            self.cursor += 1;
                            self.value_start = self.cursor;
                            self.state = .string;
                            continue :state_loop;
                        },

                        // Number
                        '1'...'9' => {
                            self.value_start = self.cursor;
                            self.cursor += 1;
                            self.state = .number_int;
                            continue :state_loop;
                        },
                        '0' => {
                            self.value_start = self.cursor;
                            self.cursor += 1;
                            self.state = .number_leading_zero;
                            continue :state_loop;
                        },
                        '-' => {
                            self.value_start = self.cursor;
                            self.cursor += 1;
                            self.state = .number_minus;
                            continue :state_loop;
                        },

                        // literal values
                        't' => {
                            self.cursor += 1;
                            self.state = .literal_t;
                            continue :state_loop;
                        },
                        'f' => {
                            self.cursor += 1;
                            self.state = .literal_f;
                            continue :state_loop;
                        },
                        'n' => {
                            self.cursor += 1;
                            self.state = .literal_n;
                            continue :state_loop;
                        },

                        else => return error.SyntaxError,
                    }
                },
            }
        }
    }

    fn expectByte(self: *const Scanner) !u8 {
        if (self.cursor < self.input.len) {
            return self.input[self.cursor];
        }
        // No byte.
        if (self.is_end_of_input) return error.UnexpectedEndOfInput;
        return error.BufferUnderrun;
    }

    fn skipWhitespace(self: *Scanner) void {
        while (self.cursor < self.input.len) : (self.cursor += 1) {
            switch (self.input[self.cursor]) {
                // Whitespace
                ' ', '\t', '\r' => continue,
                '\n' => {
                    if (self.diagnostics) |diag| {
                        diag.line_number += 1;
                        // This will count the newline itself,
                        // which means a straight-forward subtraction will give a 1-based column number.
                        diag.line_start_cursor = self.cursor;
                    }
                    continue;
                },
                else => return,
            }
        }
    }

    fn skipWhitespaceExpectByte(self: *@This()) !u8 {
        self.skipWhitespace();
        return self.expectByte();
    }
};

pub fn parseFromSlice(
    comptime T: type,
    allocator: Allocator,
    s: []const u8,
) ParseError!Managed(T) {
    var scanner: Scanner = .{ .input = s };
    defer scanner.deinit();

    return parseFromTokenSource(T, allocator, &scanner);
}

pub fn parseFromSliceLeaky(
    comptime T: type,
    allocator: Allocator,
    s: []const u8,
) ParseError!T {
    var scanner: Scanner = .{ .input = s };
    defer scanner.deinit();

    return parseFromTokenSourceLeaky(T, allocator, &scanner);
}

pub fn parseFromTokenSource(
    comptime T: type,
    allocator: Allocator,
    scanner_or_reader: anytype,
) ParseError!Managed(T) {
    var parsed: Managed(T) = .{
        .arena = try allocator.create(std.heap.ArenaAllocator),
        .value = undefined,
    };
    errdefer allocator.destroy(parsed.arena);
    parsed.arena.* = std.heap.ArenaAllocator.init(allocator);
    errdefer parsed.arena.deinit();

    parsed.value = try parseFromTokenSourceLeaky(T, parsed.arena.allocator(), scanner_or_reader);

    return parsed;
}

pub fn parseFromTokenSourceLeaky(
    comptime T: type,
    allocator: Allocator,
    scanner_or_reader: anytype,
) ParseError!T {
    const value = try innerParse(T, allocator, scanner_or_reader);
    return value;
}

pub fn innerParse(
    comptime T: type,
    allocator: Allocator,
    source: Scanner,
) ParseError!T {
    switch (@typeInfo(T)) {
        // .Bool => {
        //     return switch (try source.next()) {
        //     };
        // },
        .Struct => |info| {
            if (info.is_tuple) {
                // TODO: array begin [
                var r: T = undefined;
                inline for (0..info.fields.len) |i| {
                    r[i] = try innerParse(info.fields[i].type, allocator, source);
                }
                // TODO: array end ]
                return r;
            }

            if (std.meta.hasFn(T, "configParse")) {
                return T.configParse(allocator, source);
            }

            // TODO: object begin { (need to keep track of depth)

            var r: T = undefined;
            var fields_seen = [_]bool{false} ** info.fields.len;

            while (true) {
            }


        },
    }
}


test {
    const Config = struct {
        a: i32 = 0,
        b: bool,
        c: []const u8 = "",
    };

    const source =
        \\a = 1
        \\b = true
        \\c = "hello"
    ;

    const parsed = try parseFromSlice(Config, std.testing.allocator, source);
    defer parsed.deinit();

    std.testing.expectEqualDeep(
        Config{ .a = 1, .b = true, .c = "hello" },
        parsed.value,
    );
}

test {
    const Config = struct {
        a: bool,
    };
    const unknown_key = parseFromSlice(Config, std.testing.allocator, "b = true");
    const wrong_value = parseFromSlice(Config, std.testing.allocator, "a = 0");
    const missing_value = parseFromSlice(Config, std.testing.allocator, "");
    // std.testing.expectError(
    _ = unknown_key;
    _ = wrong_value;
    _ = missing_value;
}
