//! The Escape key (KEY_ESC) is the default for exiting the main loop of the library.
//! Any assignments to it will be ignored.

const std = @import("std");
const ev = @import("evdev");
const BindKey = @This();
const log = std.log.scoped(.BindKey);

pub const events = ev.events;

/// Codes for keyboard keys and other buttons.
/// (Including mouse buttons).
///
/// The mouse uses .BTN_
pub const key = events.KEY;

/// Codes for relative positioning.
/// Useful for manipulating the mouse.
pub const rel = events.REL;
pub const EventType = ev.EventType;
pub const EventCode = events.EventCode;

pub const value = enum(i32) {
    release = ev.event_values.key.release,
    press = ev.event_values.key.press,
    hold = ev.event_values.key.hold,
};

/// The amount of time (in milliseconds) to wait before
/// grabbing the input from the keyboard.
///
/// Calls std.time.sleep;
pub var grab_delay: u64 = 250;

exit_key: key = .KEY_ESC,

input: std.fs.File,
evdev: ev,
uidev: ev.UInput,
uifd: std.fs.File,
binds: std.AutoArrayHashMap(key, Bind),

/// Subject to a delay to give time to let
/// the user release any keys pressed when grabbing.
///
/// See grab_delay
grab: bool = false,

const open_flags: std.fs.File.OpenFlags = .{
    .mode = .read_write,
    .lock_nonblocking = true,
};

pub fn init(allocator: std.mem.Allocator, input_id: ?[]const u8) !BindKey {
    const stdout_w = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_w);
    const stdout = bw.writer();

    const stdin = std.io.getStdIn().reader();

    var ret: BindKey = .{
        .input = undefined,
        .evdev = undefined,
        .uidev = undefined,
        .uifd = try std.fs.openFileAbsolute("/dev/uinput", .{ .mode = .read_write }),
        .binds = undefined,
    };

    var inputdir = try std.fs.openDirAbsolute("/dev/input/by-id", .{
        .iterate = true,
    });
    defer inputdir.close();

    if (input_id) |iid| {
        ret.input = try inputdir.openFile(iid, open_flags);
    } else {
        var possible_inputs = std.AutoArrayHashMap(u32, []const u8).init(allocator);
        defer {
            for (possible_inputs.values()) |v| {
                allocator.free(v);
            }
            possible_inputs.deinit();
        }

        var iter = inputdir.iterate();
        var index: u32 = 1;
        while (try iter.next()) |et| {
            // if (std.mem.endsWith(u8, et.name, "kbd")) {
            defer index += 1;
            const name_clone = try allocator.dupe(u8, et.name);
            try possible_inputs.put(index, name_clone);
            // }
        }

        var input_buffer = std.ArrayList(u8).init(allocator);
        defer input_buffer.deinit();

        var pi_iter = possible_inputs.iterator();
        sl: while (true) {
            while (pi_iter.next()) |e| {
                try stdout.print("{d: >2}. {s}\n", .{
                    e.key_ptr.*,
                    e.value_ptr.*,
                });
            }
            try stdout.print("\nSelect an input device (\"q\" to exit): ", .{});
            try bw.flush();

            try stdin.streamUntilDelimiter(input_buffer.writer(), '\n', 4096);
            defer input_buffer.clearAndFree();

            const isolated = std.mem.trim(u8, input_buffer.items, &std.ascii.whitespace);
            if (isolated[0] == 'q') std.process.exit(0);

            const num = std.fmt.parseUnsigned(u32, isolated, 10) catch |err| switch (err) {
                else => {
                    log.err("Invalid Input. Positive Numbers only.", .{});
                    continue :sl;
                },
            };

            const selected = possible_inputs.get(num) orelse {
                log.err("Input out of range of possible inputs.", .{});
                continue :sl;
            };

            ret.input = try inputdir.openFile(selected, open_flags);
            break :sl;
        }
    }

    ret.evdev = try ev.init(ret.input.handle);
    ret.uidev = try ev.UInput.init(ret.evdev.evdev, ret.uifd);
    ret.binds = std.AutoArrayHashMap(key, Bind).init(allocator);

    return ret;
}

/// Closes the file descriptor
pub fn deinit(self: *BindKey) void {
    defer self.input.close();
    defer self.evdev.deinit();
    // Crashes (unreachable) ; .BADF
    // defer self.uifd.close();
    defer self.uidev.deinit();
    defer self.binds.deinit();
}

/// code: the keycode of the key to send. See key.
/// valu: .press, .hold, .release. See value.
pub fn send(self: *BindKey, code: EventCode, val: i32) !void {
    const newevent: ev.InputEvent = .{
        .ev = undefined,
        .type = @as(EventType, code),
        .code = code,
        .value = val,
    };
    try self.uidev.writeEvent(newevent);
}

pub const Bind = struct {
    /// Keycode of target key. See key.
    key: key,
    runtype: RunType = .{ .single = .press },

    /// Pointer to a context struct that will be
    /// passed into `.callback` as an argument.
    context: ?*anyopaque,

    /// Used for looping binds.
    /// Untouched when `.runtype` is `.single`
    timer: ?std.time.Timer = null,

    /// Function to run when detecting a keyboard input
    callback: *const fn (?*anyopaque) anyerror!void,

    /// Tracks the state of `.key` for the `.loop` RunType
    /// Should not be touched.
    state: bool = false,

    /// A workaround for not having async yet.
    thread: ?std.Thread = null,

    pub const RunType = union(enum) {
        /// The delay in milliseconds.
        loop: u64,

        /// Like `.loop`, but keeps running
        /// until `Bind.key` is pressed again.
        toggle: u64,

        /// The triggering event. See value.
        single: value,
    };

    pub fn run(self: Bind) anyerror!void {
        try self.callback(self.context);
    }
};

pub fn register(self: *BindKey, bind: *Bind) !void {
    switch (bind.runtype) {
        .loop, .toggle => {
            if (bind.timer == null) return error.LoopBindWithoutTimer;
        },
        else => {},
    }

    try self.binds.putNoClobber(bind.key, bind.*);
}

pub fn unregister(self: *BindKey, bind: *Bind) !void {
    if (!self.binds.swapRemove(bind.key)) {
        return error.FailedToUnregisterBind;
    }
}

pub fn loop(self: *BindKey) !void {
    log.info("BindKey loop started. Press ESC to exit.", .{});
    var event: ev.InputEvent = undefined;
    if (self.grab) {
        std.time.sleep(std.time.ns_per_ms * grab_delay);
        try self.evdev.grab(.grab);
    }
    defer self.evdev.grab(.ungrab) catch unreachable;
    ol: while (true) {
        const result_code = self.evdev.nextEvent(.normal, &event) catch continue;
        if (result_code != .success) {
            try self.send(event.code, event.value);
            continue :ol;
        }
        switch (event.code) {
            .key => |ek| sb: {
                if (ek == self.exit_key) break :ol;
                if (self.binds.getPtr(ek)) |bind| {
                    if (ek != bind.key) break :sb;
                    switch (bind.runtype) {
                        .single => |v| {
                            if (event.value == @intFromEnum(v)) {
                                try bind.run();
                            }
                        },
                        .loop => |delay| {

                            // On Press
                            if (event.value == @intFromEnum(value.press)) {
                                log.info("Starting Loop on {}", .{bind.key});
                                bind.timer.?.reset();
                                bind.state = true;
                                bind.thread = try std.Thread.spawn(.{}, looper, .{ bind, delay });
                                bind.thread.?.detach();
                                bind.thread = null;
                                try bind.run();
                            }

                            // On Release
                            if (event.value == @intFromEnum(value.release)) {
                                log.info("Ending Loop on {}", .{bind.key});
                                bind.state = false;
                            }
                        },
                        .toggle => |delay| {
                            // On Press
                            if (event.value == @intFromEnum(value.press)) {
                                if (bind.state) {
                                    log.info("Ending Toggle Loop on {}", .{bind.key});
                                    bind.state = false;
                                } else {
                                    log.info("Starting Toggle Loop on {}", .{bind.key});
                                    bind.timer.?.reset();
                                    bind.state = true;
                                    bind.thread = try std.Thread.spawn(.{}, looper, .{ bind, delay });
                                    bind.thread.?.detach();
                                    bind.thread = null;
                                    try bind.run();
                                }
                            }
                        },
                    }
                    continue :ol;
                }
            },
            else => {},
        }

        if (event.code == .rel and event.code.rel == .WHEEL_HI_RES) continue :ol;
        // log.info("Loop: Default passthrough. {any} {any}", .{ event.code, event.value });
        try self.send(event.code, event.value);
    }
}
fn looper(b: *Bind, ms: u64) !void {
    while (b.state) {
        if (b.timer.?.read() >= std.time.ns_per_ms * ms) {
            b.timer.?.reset();
            try b.run();
        }
    }
}
