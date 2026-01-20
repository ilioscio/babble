const std = @import("std");

const LISTEN_PORT: u16 = 8080;
const LISTEN_ADDR = "127.0.0.1";
const MAX_OUTPUT_WORDS: usize = 2000; // Security limit

const HTTP_HEADER = "HTTP/1.1 200 OK\r\nContent-Type: text/plain; charset=utf-8\r\nConnection: close\r\n\r\n";

// Bigram key for the Markov model
const WordPair = struct {
    w1: []const u8,
    w2: []const u8,
};

// Custom hash context for WordPair keys
const WordPairContext = struct {
    pub fn hash(self: @This(), key: WordPair) u64 {
        _ = self;
        var h = std.hash.Wyhash.init(0);
        h.update(key.w1);
        h.update(key.w2);
        return h.final();
    }

    pub fn eql(self: @This(), a: WordPair, b: WordPair) bool {
        _ = self;
        return std.mem.eql(u8, a.w1, b.w1) and std.mem.eql(u8, a.w2, b.w2);
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // Parse arguments: babble <word_count> <input_file>
    if (args.len < 3) {
        std.debug.print("Usage: {s} <word_count> <input_file>\n", .{args[0]});
        std.debug.print("  word_count: number of words to generate (max {d})\n", .{MAX_OUTPUT_WORDS});
        return error.InvalidArguments;
    }

    const output_word_count = std.fmt.parseInt(usize, args[1], 10) catch {
        std.debug.print("Error: '{s}' is not a valid number\n", .{args[1]});
        return error.InvalidWordCount;
    };

    if (output_word_count == 0 or output_word_count > MAX_OUTPUT_WORDS) {
        std.debug.print("Error: word_count must be between 1 and {d}\n", .{MAX_OUTPUT_WORDS});
        return error.InvalidWordCount;
    }

    // Load corpus into memory (only disk I/O happens here)
    const file_contents = try std.fs.cwd().readFileAlloc(allocator, args[2], std.math.maxInt(usize));
    defer allocator.free(file_contents);

    // Tokenize into words (slices pointing into file_contents)
    var words: std.ArrayList([]const u8) = .{};
    defer words.deinit(allocator);

    var splitter = std.mem.tokenizeAny(u8, file_contents, " \t\n\r");
    while (splitter.next()) |word| {
        try words.append(allocator, word);
    }

    if (words.items.len < 3) return error.NotEnoughWords;

    // Build Markov model: (w1, w2) -> [possible next words]
    var possibles = std.HashMap(
        WordPair,
        std.ArrayList([]const u8),
        WordPairContext,
        std.hash_map.default_max_load_percentage,
    ).init(allocator);
    defer {
        var it = possibles.valueIterator();
        while (it.next()) |value_ptr| {
            value_ptr.deinit(allocator);
        }
        possibles.deinit();
    }

    for (0..words.items.len - 2) |i| {
        const pair = WordPair{ .w1 = words.items[i], .w2 = words.items[i + 1] };
        const result = try possibles.getOrPut(pair);
        if (!result.found_existing) {
            result.value_ptr.* = .{};
        }
        try result.value_ptr.append(allocator, words.items[i + 2]);
    }

    // Collect capitalized starting pairs for natural sentence starts
    var starting_pairs: std.ArrayList(WordPair) = .{};
    defer starting_pairs.deinit(allocator);

    var key_iter = possibles.keyIterator();
    while (key_iter.next()) |key_ptr| {
        const pair = key_ptr.*;
        if (pair.w1.len > 0 and std.ascii.isUpper(pair.w1[0])) {
            try starting_pairs.append(allocator, pair);
        }
    }

    if (starting_pairs.items.len == 0) return error.NoCapitalizedPairs;

    // Initialize RNG
    var prng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp()));
    const random = prng.random();

    // Start TCP server
    const address = try std.net.Address.parseIp4(LISTEN_ADDR, LISTEN_PORT);
    var server = try address.listen(.{});
    defer server.deinit();

    std.debug.print("Listening on {s}:{d} (generating {d} words per request)\n", .{ LISTEN_ADDR, LISTEN_PORT, output_word_count });

    // Accept loop - all operations from memory, no disk I/O
    while (true) {
        const conn = try server.accept();
        defer conn.stream.close();

        // Drain incoming HTTP request (read until end of headers)
        var request_buf: [4096]u8 = undefined;
        _ = conn.stream.read(&request_buf) catch {};

        var output: std.ArrayList(u8) = .{};
        defer output.deinit(allocator);

        // Pick random starting pair
        const start_idx = random.intRangeLessThan(usize, 0, starting_pairs.items.len);
        var w1 = starting_pairs.items[start_idx].w1;
        var w2 = starting_pairs.items[start_idx].w2;

        try output.appendSlice(allocator, w1);
        try output.append(allocator, ' ');
        try output.appendSlice(allocator, w2);

        // Generate text via Markov chain walk
        for (0..output_word_count) |_| {
            const pair = WordPair{ .w1 = w1, .w2 = w2 };
            if (possibles.get(pair)) |next_words| {
                const idx = random.intRangeLessThan(usize, 0, next_words.items.len);
                const picked = next_words.items[idx];

                try output.append(allocator, ' ');
                try output.appendSlice(allocator, picked);

                w1 = w2;
                w2 = picked;
            } else {
                break;
            }
        }

        try conn.stream.writeAll(HTTP_HEADER);
        try conn.stream.writeAll(output.items);
    }
}
