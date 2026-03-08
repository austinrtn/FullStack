const std = @import("std");
const Display = @import("Display");
const Context = @import("Context.zig").Context;
const ZigClient = @import("ZigClient").ZigClient(Context);

pub const PhotoManager = struct {
    const Self = @This();

    const Config = struct {
        allocator: std.mem.Allocator,
        client: *ZigClient,

        url: []const u8,
        photo_dir: []const u8,
        max_queue_len: usize = 5,
        ctx: *Context,
    };

    allocator: std.mem.Allocator, 
    client: *ZigClient,

    url: []const u8,
    photo_dir: []const u8,
    max_queue_len: usize,  
    photo_queue: std.ArrayList([]const u8) = .{},
    photo_index: usize = 0,
    ctx: *Context,

    pub fn init(config: Config) Self {
        const self = Self{
            .allocator = config.allocator,
            .client = config.client,
            .max_queue_len = config.max_queue_len,
            .url = config.url,  
            .photo_dir = config.photo_dir,
            .ctx = config.ctx,
        };
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.photo_queue.deinit(self.allocator);
    }

    pub fn getNextPhoto(self: *Self) !void {
        const ctx = self.ctx;
        if(!ctx.isConnected()) {
            return error.NotConnected;
        }

        const url = try self.getUrl("getNextPhoto", "idx");
        defer self.allocator.free(url);

        var res = try self.client.get(url, .{});
        defer res.deinit();

        if(res.status == .bad_request) {
            const ErrorCode = enum{invalid_index, negative_index};
            const error_code = res.getHeader("X-Error-Code") orelse return error.BadRequest;

            const err = std.meta.stringToEnum(ErrorCode, error_code) orelse return error.BadRequest;
            switch(err) {
                .invalid_index => return error.InvalidIndex,
                .negative_index => return error.NegativeIndex,
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
    }

    fn getUrl(self: *Self, path: []const u8, query: ?[]const u8) ![]const u8{
        if(query) |qry| { return try std.fmt.allocPrint(self.allocator, "{s}/{s}?{s}=", .{self.url, path, qry}); }
        else { return try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{self.url, path}); }
    }
};
