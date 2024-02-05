const std = @import("std");
const bindkey = @import("bindkey");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var bk = try bindkey.init(allocator, null);
    defer bk.deinit();

    bk.grab = true;

    var hwctx: helloWorldCTX = .{
        .str = "BAA!",
        .bkctx = &bk,
    };

    const SpaceHello: bindkey.Bind = .{
        .key = bindkey.keys.SPACE,
        .runtype = .single,
        .context = @ptrCast(&hwctx),
        .callback = helloWorld,
    };

    var zeroctx: zeroCTX = .{
        .bkctx = &bk,
    };

    const Zero: bindkey.Bind = .{
        .key = bindkey.keys.@"0",
        .runtype = .single,
        .context = @ptrCast(&zeroctx),
        .callback = zero,
    };

    try bk.register(SpaceHello);
    try bk.register(Zero);

    try bk.unregister(SpaceHello);

    try bk.loop();
}

const helloWorldCTX = struct {
    str: []const u8,
    bkctx: *bindkey,
};

pub fn helloWorld(ctx: ?*anyopaque) !void {
    const c: *helloWorldCTX = @alignCast(@ptrCast(ctx.?));
    std.debug.print("Hello World! {s}\n", .{c.str});
}

const zeroCTX = struct {
    bkctx: *bindkey,
};

pub fn zero(ctx: ?*anyopaque) !void {
    const c: *zeroCTX = @alignCast(@ptrCast(ctx.?));
    std.debug.print("zero() sending KEY_SPACE\n", .{});
    try c.bkctx.send(bindkey.keys.SPACE, bindkey.value.press);
    try c.bkctx.send(bindkey.keys.SPACE, bindkey.value.release);
}
