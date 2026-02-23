const std = @import("std");

const ClientState = enum {
    NOT_CONNECTED,
    NO_PHOTOS_AVAILABLE,
    SUCCESS,
};

/// Request URL extensions
const ServerPaths = struct {
    const downloadRandomPhoto = "/getRandomPhoto";
};

/// Responsible for connecting to server / downloading files
pub const HttpClient = struct {
    const Self = @This();
    const Config = struct {
        allocator: std.mem.Allocator,
        server_url: []const u8,
        photo_name: []const u8,
        photo_dir: *std.fs.Dir,
        stdout: *std.io.Writer
    };

    allocator: std.mem.Allocator,
    server_url: []const u8,
    photo_name: []const u8,
    photo_dir: *std.fs.Dir, // Directory where photos are stored 
    stdout: *std.io.Writer, // Writes output to user
    client: std.http.Client, //std lib tool for requests 
    state: ClientState = .NOT_CONNECTED,

    /// Create new instanceo of HTTPClient 
    pub fn init(config: Config) Self {
        const self: Self = .{
            .allocator = config.allocator,
            .server_url = config.server_url,
            .photo_name = config.photo_name,
            .photo_dir = config.photo_dir,
            .stdout = config.stdout,
            .client = std.http.Client{.allocator = config.allocator}
        };

        return self;
    }

    pub fn establishConnection(self: *Self) !void {
        // Here will create connection to listen to messages from server 
    }

    pub fn resetClient(self: *Self) void {
        self.client.deinit();
        self.client = std.http.Client{.allocator = self.allocator};
    }

    pub fn deinit(self: *Self) void {
        self.client.deinit();
    }

    /// Log message to console 
    fn log(self: *Self, comptime fmt: []const u8, args: anytype) !void{
        try self.stdout.print(fmt, args);
        try self.stdout.flush();
    }

    fn deleteRandomPhoto(self: *Self) !void {
        const exts = [_][]const u8{ ".jpg", ".jpeg", ".png", };

        for(exts) |ext| {
            var buf: [1024]u8 = undefined;
            const path = try  std.fmt.bufPrint(&buf, "{s}{s}", .{self.photo_name, ext});
            self.photo_dir.deleteFile(path) catch |err| switch(err) {
                error.FileNotFound => {}, 
                else => { return err; },
            };
        }
    }

    /// Request a random photo from the server and download locally
    pub fn downloadRandomPhoto(self: *Self) !void {

        try self.deleteRandomPhoto();
        const server_path = try std.fs.path.join(
            self.allocator, 
            &.{
                self.server_url, 
                ServerPaths.downloadRandomPhoto 
            }
        );
        defer self.allocator.free(server_path);

        const uri = try std.Uri.parse(server_path);

        // Init server request
        var req = try self.client.request(.GET, uri, .{});
        defer req.deinit();

        // Request random photo from server
        req.sendBodiless() catch return error.NoPhotosAvailable; 
        try self.log("Requested Random Photo From Server...\n", .{});

        // Recieve headers and store in buffer
        var redir_buf: [4096] u8 = undefined; 
        var res = req.receiveHead(&redir_buf) catch return error.NoPhotosAvailable; 

        if(res.head.status != .ok) return error.NoPhotosAvailable;

        try self.log("File Headers Downloaded! Parsing...\n", .{});

        // Create null placeholder for file extension 
        var file_ext: ?[]const u8 = null;
        var header_iter = res.head.iterateHeaders();

        // Parse headers from server requenst, specifically 'Content-Type'
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

        // Read the body / contents /file bytes of
        //  the data being send from server 
        const body = try res.reader(&.{}).allocRemaining(self.allocator, .unlimited);
        defer self.allocator.free(body);
        
        const file_path = try std.fmt.allocPrint(
            self.allocator, 
            "{s}{s}", 
            .{"RandomPhoto", file_ext.?}
        );
        defer self.allocator.free(file_path);

        // Create image file 
        try self.log("Saving File: {s}...\n", .{file_path}); 
        var img_file = try self.photo_dir.createFile(file_path, .{});
        defer img_file.close();

        var img_buf: [8192]u8 = undefined;
        var file_writer = img_file.writer(&img_buf);
        const fw = &file_writer.interface;

        try fw.writeAll(body);
        try fw.flush();

        try self.log("File saved!\n\n", .{});
    }
};
