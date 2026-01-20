const std = @import("std");

pub fn main() !void {
    std.debug.print("babble - Markov chain text generator\n", .{});
    std.debug.print("Usage: babble <num_words> < input.txt\n", .{});
}
