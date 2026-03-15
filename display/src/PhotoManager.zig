const std = @import("std");
const Display = @import("Display");
const Context = @import("Context.zig").Context;
const ZigClient = @import("ZigClient").ZigClient(Context);

pub const PhotoManager = struct {
    const Self = @This();
    const ErrorCode = enum{ invalid_index, index_overflow, other };

    const Config = struct {
        allocator: std.mem.Allocator,
        client: *ZigClient,

        url: []const u8,
        photo_dir: []const u8,
        max_dir_len: usize = 5,
        ctx: *Context,
    };

    allocator: std.mem.Allocator, 
    client: *ZigClient,

    url: []const u8,
    photo_dir: []const u8,
    max_dir_len: usize, 

    photo_index: usize = 0,
    ctx: *Context,

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

    pub fn deinit(self: *Self) void {
        _ = self;
    }

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

    fn getUrl(self: *Self, path: []const u8, query: ?[]const u8) ![]const u8{
        if(query) |qry| { return try std.fmt.allocPrint(self.allocator, "{s}/{s}?{s}=", .{self.url, path, qry}); }
        else { return try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{self.url, path}); }
    }
};
