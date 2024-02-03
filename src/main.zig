const std = @import("std");
const bindkey = @import("bindkey");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var bk = try bindkey.init(allocator, null);
    defer if (bk) |*b| b.deinit();
}
