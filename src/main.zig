const std = @import("std");
const bindkey = @import("bindkey");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var bkn = try bindkey.init(allocator, null);
    defer if (bkn) |*b| b.deinit();
    const bk = &bkn.?;

    const SpaceHello: bindkey.Bind = .{
        .key = bindkey.key.SPACE,
        .runtype = .single,
        .bindkey = bk,
        .runFn = helloWorld,
    };

    try bk.register(SpaceHello);

    try bk.loop();
}

pub fn helloWorld() !void {
    std.debug.print("Hello World!\n", .{});
}
