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

        // const url = try self.getUrl("getNextPhoto", "index");
        // defer self.allocator.free(url);
        //
        // var res = try self.client.get(url, .{});
        // defer res.deinit();

    }

    fn getUrl(self: *Self, path: []const u8, query: ?[]const u8) ![]const u8{
        if(query) |qry| { return try std.fmt.allocPrint(self.allocator, "{s}/{s}?{s}=", .{self.url, path, qry}); }
        else { return try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{self.url, path}); }
    }
};
