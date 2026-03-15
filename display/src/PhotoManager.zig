const std = @import("std");
const Display = @import("Display");
const Context = @import("Context.zig").Context;
const ZigClient = @import("ZigClient").ZigClient(Context);

/// Manages fetching photos from the server and writing them to disk.
pub const PhotoManager = struct {
    const Self = @This();

    const ErrorCode = enum { invalid_index, index_overflow, other };

    /// Configuration used to initialize a `PhotoManager`.
    const Config = struct {
        /// Allocator used for URL construction and HTTP responses.
        allocator: std.mem.Allocator,
        /// HTTP client used to fetch photos.
        client: *ZigClient,
        /// Base URL of the photo server.
        url: []const u8,
        /// Path to the local directory where photos are saved.
        photo_dir: []const u8,
        /// Maximum number of photos to keep in the directory.
        max_dir_len: usize = 10,
        /// Shared connection context.
        ctx: *Context,
    };

    /// Allocator used for URL construction and HTTP responses.
    allocator: std.mem.Allocator,
    /// HTTP client used to fetch photos.
    client: *ZigClient,
    /// Base URL of the photo server.
    url: []const u8,
    /// Path to the local directory where photos are saved.
    photo_dir: []const u8,
    /// Maximum number of photos to keep in the directory.
    max_dir_len: usize,
    /// Index of the next photo to fetch.
    photo_index: usize = 0,
    /// Shared connection context.
    ctx: *Context,

    /// Initializes a `PhotoManager` from the given config.
    pub fn init(config: Config) Self {
        const self = Self{
            .allocator = config.allocator,
            .client = config.client,
            .url = config.url,
            .photo_dir = config.photo_dir,
            .ctx = config.ctx,
            .max_dir_len = config.max_dir_len,
        };
        return self;
    }

    /// Cleans up resources held by this `PhotoManager`.
    pub fn deinit(self: *Self) void {
        _ = self;
    }

    /// Fetches the next photo from the server and writes it to the photos directory.
    /// Increments `photo_index` on success.
    /// Returns `error.NotConnected` if the context reports no active connection.
    pub fn getNextPhoto(self: *Self) !void {
        const ctx = self.ctx;
        if(!ctx.isConnected()) {
            return error.NotConnected;
        }

        const url_base = try self.getUrl("getNextPhoto", "idx");
        defer self.allocator.free(url_base);

        const url = try std.fmt.allocPrint(self.allocator, "{s}{}", .{url_base, self.photo_index});
        defer self.allocator.free(url);

        var res = try self.client.get(url, .{});
        defer res.deinit();

        const error_code = res.getHeader("X-Error-Code") orelse null;
        if(error_code) |err_code| {
            const err = std.meta.stringToEnum(ErrorCode, err_code) orelse .other;
            switch(err) {
                .invalid_index => return error.InvalidIndex,
                .index_overflow => { return error.IndexOverflow; },
                .other => {
                    std.debug.print("HTTP Error: {s} | Msg: {s}\n", .{ @tagName(res.status), err_code});
                    return error.BadRequest;
                },
            }
        }

        var photos = try std.fs.cwd().openDir("./photos", .{});
        defer photos.close();
        const file_name = res.getHeader("X-File-Name") orelse return error.NoFileName;

        var pic_buf: [4096]u8 = undefined;
        var pic_file = try photos.createFile(file_name, .{});
        defer pic_file.close();
        var pic_writer = pic_file.writer(&pic_buf);
        const w = &pic_writer.interface;

        try w.print("{s}", .{res.body});
        try w.flush();

        self.photo_index += 1;
    }

    /// Fills the photos directory by repeatedly calling `getNextPhoto` up to `max_dir_len` times.
    /// Resets `photo_index` to 0 if the server signals index overflow.
    pub fn fillDir(self: *Self) !void {
        for(0..self.max_dir_len) |_| {
            self.getNextPhoto() catch |err| switch(err) {
                error.IndexOverflow => {
                    self.photo_index = 0;
                    break;
                },
                else => return err,
            };
        }
    }

    /// Builds a full request URL from a path and optional query key.
    /// Caller owns the returned slice.
    fn getUrl(self: *Self, path: []const u8, query: ?[]const u8) ![]const u8{
        if(query) |qry| { return try std.fmt.allocPrint(self.allocator, "{s}/{s}?{s}=", .{self.url, path, qry}); }
        else { return try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{self.url, path}); }
    }
};
