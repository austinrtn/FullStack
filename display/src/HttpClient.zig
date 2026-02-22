const std = @import("std");

const ServerPaths = struct {
    const downloadRandomPhoto = "/getRandomPhoto";
};

pub const HttpClient = struct {
    const Self = @This();

    server_url: []const u8,
    allocator: std.mem.Allocator,
    photo_dir: *std.fs.Dir,
    stdout: *std.io.Writer,

    client: std.http.Client = undefined,

    pub fn init(allocator: std.mem.Allocator, photo_dir: *std.fs.Dir, server_url: []const u8, stdout: *std.io.Writer) !Self {
        var self: Self = .{
            .allocator = allocator,
            .server_url = server_url,
            .stdout = stdout,
            .photo_dir = photo_dir,
        };


        self.client = std.http.Client{.allocator = allocator};

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.client.deinit();
    }

    pub fn log(self: *Self, comptime fmt: []const u8, args: anytype) !void{
        try self.stdout.print(fmt, args);
        try self.stdout.flush();
    }

    pub fn downloadRandomPhoto(self: *Self) !void {
        try self.log("Resquesting Random Photo From Server...\n", .{});

        var res_writer = std.io.Writer.Allocating.init(self.allocator);
        defer res_writer.deinit();

        const server_path = try std.fs.path.join(
            self.allocator, 
            &.{
                self.server_url, 
                ServerPaths.downloadRandomPhoto 
            }
        );
        defer self.allocator.free(server_path);

        const uri = try std.Uri.parse(server_path);

        var req = try self.client.request(.GET, uri, .{});
        defer req.deinit();
        try req.sendBodiless();

        var redir_buf: [4096] u8 = undefined; 
        var res = try req.receiveHead(&redir_buf);

        try self.log("File Contents Downloaded! Parsing Headers...\n", .{});

        var file_ext: ?[]const u8 = null;
        var header_iter = res.head.iterateHeaders();

        // Avaialbe headers: Content-Type, X-File-Name, Date, Trasnfer-Encoding
        // Content-Type values: 'image/jpeg', 'image/png'
        while(header_iter.next()) |header| {
            if(std.mem.eql(u8, header.name, "Content-Type")) {
                if(std.mem.eql(u8, header.value, "image/jpeg")) {
                    file_ext = ".jpg";
                } else if(std.mem.eql(u8, header.value, "image/png")) {
                    file_ext = ".png";
                }
            }
        }
       
        if(file_ext == null) return error.NoContentTypeHeaderFound; 

        const body = try res.reader(&.{}).allocRemaining(self.allocator, .unlimited);
        defer self.allocator.free(body);
        
        const file_name = try std.fmt.allocPrint(
            self.allocator, 
            "{s}{s}", 
            .{"RandomPhoto", file_ext.?}
        );
        defer self.allocator.free(file_name);

        try self.log("Saving File: {s}...\n", .{file_name}); 
        var img_file = try self.photo_dir.createFile(file_name, .{});
        defer img_file.close();

        var img_buf: [8192]u8 = undefined;
        var file_writer = img_file.writer(&img_buf);
        const fw = &file_writer.interface;

        try fw.writeAll(body);
        try fw.flush();

        try self.log("File saved!\n\n", .{});
    }
};
