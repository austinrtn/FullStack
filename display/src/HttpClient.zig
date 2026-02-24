const std = @import("std");

const messages = struct {
    noPhotosAvailable: struct {
        str: []const u8 = "no_photos_available",
        pub fn func(_: @This(), client: *HttpClient) void {
            client.photos_available = false;
        }
    } = .{},

    photosAvailable: struct {
        str: []const u8 = "photos_available", 
        pub fn func(_: @This(), client: *HttpClient) void {
            client.photos_available = true;
        }
    } = .{}
}{};

/// Request URL extensions
const ServerPaths = struct {
    const ESTABLISH_CONNECTION = "/events?category=display";
    const DOWNLOAD_RANDOM_PHOTO = "/getRandomPhoto";
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
    connected: bool = false,
    photos_available: bool = false,


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

    pub fn establishConnection(self: *Self) !void {
        const server_path = try std.fs.path.join(
            self.allocator, 
            &.{
                self.server_url, 
                ServerPaths.ESTABLISH_CONNECTION,
            }
        );
        defer self.allocator.free(server_path);
        
        const uri = try std.Uri.parse(server_path);

        var request: ?std.http.Client.Request = null;
        var response: ?std.http.Client.Response = null;
        var res_buf: [4096]u8 = undefined;
        var redir_buf: [4096]u8 = undefined;
        var res_reader: ?*std.io.Reader = null;
        defer if(request) |*req| req.deinit();
       
        const tool = struct {
            fn print(str: []const u8) void {
                std.debug.print("Made it to phase: {s}\n", .{str}); 
            } 
        };
        while(true) {
            if(!self.connected or request == null or response == null) {
                tool.print("Inner loop");       
                if(self.client.request(.GET, uri, .{})) 
                    |req| { request = req; }
                else |err| switch(err) {
                    error.ConnectionRefused => { 
                        self.connected = false; 
                        request = null; 
                    },
                    else => { return err; }
                }

                tool.print("Req success"); 
                if(request) |*req| {
                    tool.print("Inner req");
                    if(req.receiveHead(&redir_buf)) 
                        |res| { response = res; } 
                    else |err| switch (err) {
                        error.ConnectionRefused => {
                            self.connected = false;
                        },
                        else => { return err; }
                    }


                    try req.sendBodiless();
                    tool.print("After Response");

                    if(response) |*res| {
                        tool.print("Has Response");
                        if(res.head.status == .ok) self.connected = true else continue;
                        res_reader = res.reader(&res_buf);
                    } else continue; 
                } else continue;
            }

            if(!self.connected) continue;
            tool.print("COnnected");
            while (res_reader.?.takeDelimiterInclusive('\n')) |line| {
                if(line.len == 0) continue;
                const trimmed = std.mem.trimRight(u8, line, "\n");
                const stripped = std.mem.trimLeft(u8, trimmed, "data::");

                try self.stdout.print("Status: {}\r", .{self.connected});
                inline for(std.meta.fields(@TypeOf(messages))) |field| {
                    const msg = @field(messages, field.name);
                    if(std.mem.eql(u8, stripped, msg.str)) { msg.func(self); }
                }

                try self.stdout.print("Status: {}\r", .{self.connected});
                try self.stdout.flush();

            } else |err| switch(err) {
                error.EndOfStream, error.ReadFailed => { self.connected = false; }, 
                else => { return err; }
            }
        }
    }

    /// Request a random photo from the server and download locally
    pub fn downloadRandomPhoto(self: *Self) !void {

        try self.deleteRandomPhoto();
        const server_path = try std.fs.path.join(
            self.allocator, 
            &.{
                self.server_url, 
                ServerPaths.DOWNLOAD_RANDOM_PHOTO,
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
        // available headers: Content-Type, X-File-Name, Date, Trasnfer-Encoding
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
