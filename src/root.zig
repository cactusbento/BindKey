//! The Escape key (KEY_ESC) is reserved for exiting the main loop of the library.
//! Any assignments to it will be ignored.

const std = @import("std");
const ev = @import("evdev");
const BindKey = @This();
const log = std.log.scoped(.BindKey);

pub const key = ev.key;

/// The amount of time (in milliseconds) to wait before
/// grabbing the input from the keyboard.
///
/// Calls std.time.sleep;
pub var grab_delay: u64 = 250;

input: std.fs.File,
evdev: ev,
binds: std.ArrayList(Bind),

/// Subject to a delay to give time to let
/// the user release any keys pressed when grabbing.
///
/// See grab_delay
grab: bool = false,

pub fn init(allocator: std.mem.Allocator, input_id: ?[]const u8) !?BindKey {
    const stdout_w = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_w);
    const stdout = bw.writer();

    const stdin = std.io.getStdIn().reader();

    var ret: BindKey = .{
        .input = undefined,
        .evdev = undefined,
        .binds = undefined,
    };

    var inputdir = try std.fs.openDirAbsolute("/dev/input/by-id", .{
        .iterate = true,
    });
    defer inputdir.close();

    if (input_id) |iid| {
        ret.input = try inputdir.openFile(iid, .{ .mode = .read_write });
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
            if (std.mem.endsWith(u8, et.name, "kbd")) {
                defer index += 1;
                const name_clone = try allocator.dupe(u8, et.name);
                try possible_inputs.put(index, name_clone);
            }
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
            if (isolated[0] == 'q') return null;

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

            ret.input = try inputdir.openFile(selected, .{ .mode = .read_write });
            break :sl;
        }
    }

    ret.evdev = try ev.init(ret.input.handle);
    ret.binds = std.ArrayList(Bind).init(allocator);

    return ret;
}

/// Closes the file descriptor
pub fn deinit(self: *BindKey) void {
    defer self.input.close();
    defer self.evdev.deinit();
    defer self.binds.deinit();
}

pub const Bind = struct {
    bindkey: *BindKey,
    key: i32,
    runtype: RunType = .single,
    event: i32 = ev.event_values.key.press,
    context: ?*anyopaque,
    callback: *const fn (?*anyopaque) anyerror!void,

    pub const RunType = union(enum) {
        loop: u64,
        single,
    };

    pub fn run(self: Bind) anyerror!void {
        try self.callback(self.context);
    }
};

pub fn register(self: *BindKey, bind: Bind) !void {
    try self.binds.append(bind);
}

pub fn loop(self: *BindKey) !void {
    var event: ev.InputEvent = undefined;
    if (self.grab) {
        std.time.sleep(std.time.ns_per_ms * grab_delay);
        try self.evdev.grab(.grab);
    }
    defer self.evdev.grab(.ungrab) catch unreachable;
    while (true) {
        const result_code = self.evdev.nextEvent(.normal, &event) catch continue;
        if (result_code != .success or !std.mem.eql(u8, event.type, "EV_KEY")) continue;
        if (event.ev.code == key.ESC) break;

        for (self.binds.items) |bind| {
            switch (bind.runtype) {
                .single => {
                    if (event.ev.value == bind.event and
                        event.ev.code == bind.key)
                    {
                        try bind.run();
                    }
                },
                .loop => |_| {},
            }
        }
    }
}
