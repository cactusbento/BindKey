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
    };

    const SpaceHello: bindkey.Bind = .{
        .key = bindkey.key.SPACE,
        .runtype = .single,
        .bindkey = &bk,
        .context = @ptrCast(&hwctx),
        .callback = helloWorld,
    };

    try bk.register(SpaceHello);

    try bk.loop();
}

const helloWorldCTX = struct {
    str: []const u8,
};

pub fn helloWorld(ctx: ?*anyopaque) !void {
    const c: *helloWorldCTX = @alignCast(@ptrCast(ctx.?));

    std.debug.print("Hello World! {s}\n", .{c.str});
}
