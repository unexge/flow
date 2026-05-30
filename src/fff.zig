const std = @import("std");
const log = @import("log");

const c = @cImport({
    @cInclude("fff.h");
});

const Self = @This();

handle: ?*anyopaque,
arena: std.mem.Allocator,

logger: log.Logger,

pub fn init(arena: std.mem.Allocator) !Self {
    const logger = log.logger("fff");
    const res = c.fff_create_instance2(
        ".", // base_path
        "", // frecency_db_path
        "", // history_db_path
        false, // use_unsafe_no_lock (deprecated)
        true, // enable_mmap_cache
        true, // enable_content_indexing
        false, // watch
        false, // ai_mode
        "", // log_file_path
        "", // log_level
        0, // cache_budget_max_files (0 = auto)
        0, // cache_budget_max_bytes (0 = auto)
        0, // cache_budget_max_file_size (0 = auto)
    );
    defer c.fff_free_result(res);

    if (!res.*.success) {
        logger.print("failed to initialise: {s}", .{res.*.@"error"});
        return error.FailedToInitialise;
    }

    const handle = res.*.handle;
    errdefer c.fff_destroy(handle);

    logger.print("initialised", .{});

    return .{
        .handle = handle,
        .arena = arena,
        .logger = logger,
    };
}

pub fn deinit(self: *Self) void {
    c.fff_destroy(self.handle);
    self.logger.print("deinitiliased", .{});
}

pub fn search(self: *Self, query: []const u8) !SearchResult {
    const query_c = try self.arena.dupeZ(u8, query);
    defer self.arena.free(query_c);

    const res = c.fff_live_grep(self.handle, query_c, 0, 0, 5, true, 0, 10, 0, 0, 0, false);
    defer c.fff_free_result(res);
    if (!res.*.success) {
        self.logger.print("failed to search: {s}", .{res.*.@"error"});
        return error.FailedToSearch;
    }

    const handle: *c.FffGrepResult = @ptrCast(@alignCast(res.*.handle));
    defer c.fff_free_grep_result(handle);

    var search_res: SearchResult = .{
        .count = handle.count,
        .matches = try self.arena.alloc(Match, handle.count),
    };
    self.logger.print("Found {d} matches for query {s}", .{ handle.count, query });

    for (0..handle.count) |i| {
        const item = c.fff_grep_result_get_match(handle, @intCast(i)) orelse continue;
        search_res.matches[i] = .{
            .path = try self.arena.dupe(u8, std.mem.span(item.*.relative_path)),
            .line_content = try self.arena.dupe(u8, std.mem.span(item.*.line_content)),
            .begin_line = item.*.line_number,
            .begin_pos = item.*.match_ranges.*.start,
            .end_line = item.*.line_number,
            .end_pos = item.*.match_ranges.*.end,
        };
    }

    return search_res;
}

const SearchResult = struct {
    count: usize,
    matches: []Match,
};

const Match = struct {
    path: []const u8,
    line_content: []const u8,
    begin_line: usize,
    begin_pos: usize,
    end_line: usize,
    end_pos: usize,
};
