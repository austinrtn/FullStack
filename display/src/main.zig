const std = @import("std");

const Client = struct {
    const Self = @This();

    server_url: []const u8,
    server_uri: std.Uri,
    allocator: std.mem.Allocator,

    client: std.http.Client = undefined,
    root_dir: std.fs.Dir = undefined,

    pub fn init(allocator: std.mem.Allocator, root_dir_path: []const u8, server_url: []const u8) !Self {
        const uri = std.Uri.parse(server_url);

        var self: Self = .{
            .allocator = allocator,
            .server_url = server_url,
            .server_uri = uri, 
        };

        self.root_dir = try std.fs.cwd().openDir(root_dir_path);
        self.client = std.http.Client{.allocator = allocator};

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.client.deinit();
        self.root_dir.close();
    }

    pub fn downloadRandomPhoto(self: *Self) !void {
        var res_writer = std.io.Writer.Allocating.init(self.allocator);
        defer res_writer.deinit();

        const res = try self.client.fetch(.{
            .method = .GET,  
            .location = self.server_uri,
            .response_writer = &res_writer.writer,
            .headers = .{ .accept_encoding = .{.override = "application/json"} },
        });
        try res_writer.writer.flush(); 

        if(res.status.class() == .success) {
            std.debug.print("{s}", .{res_writer.written()});
        }
        else {
            std.debug.print("Something went wrong", .{});
        }
        
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var args = std.process.args();
    defer args.deinit();
    _ = args.next();

    const rootPath = args.next() orelse return error.NoRootPath;
    const server_url = args.next() orelse return error.NoServerURL;

    var client = Client.init(allocator, rootPath, server_url);
    defer client.deinit();

}

