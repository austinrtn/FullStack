const std = @import("std");
const PhaseTool = @import("./PhaseTool.zig").PhaseTool;

/// Request URL extensions
const ServerPaths = struct {
    const LISTEN = "/events?category=DISPLAY";
    const DOWNLOAD_RANDOM_PHOTO = "/getRandomPhoto";
};

/// Responsible for connecting to server / downloading files
pub fn HttpClient(comptime CtxType: type) type{
    return struct {
    const Self = @This();
    const T = HttpClient(CtxType);

    pub const EventPkg = struct {
        ctx: *CtxType, 
        client: *HttpClient(CtxType),
        std_out: *std.io.Writer,
    };

    pub const Event = struct {
        msg: []const u8,
        onEvent: *const fn(_: *@This(), pkg: *EventPkg) anyerror!void,
    };

    const Config = struct {
        allocator: std.mem.Allocator,
        server_url: []const u8,
        photo_name: []const u8,
        photo_dir: *std.fs.Dir,
        stdout: *std.io.Writer,
        ctx: *CtxType,
    };

    allocator: std.mem.Allocator,
    server_url: []const u8,
    photo_name: []const u8,

    photo_dir: *std.fs.Dir, // Directory where photos are stored 
    stdout: *std.io.Writer, // Writes output to user
    client: std.http.Client, //std lib tool for requests 
                             //
    connected: bool = false,
    photos_available: bool = false,
    listening: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),

    ctx: *CtxType,
    event_listener_req: ?std.http.Client.Request = null,
    event_listener_thread: ?std.Thread = null,
    events: std.ArrayList(Event) = .{},

    /// Create new instanceo of HTTPClient 
    pub fn init(config: Config) Self {
        const self: Self = .{
            .allocator = config.allocator,
            .server_url = config.server_url,
            .photo_name = config.photo_name,
            .photo_dir = config.photo_dir,
            .stdout = config.stdout,
            .client = std.http.Client{.allocator = config.allocator},
            .ctx = config.ctx,
        };

        return self;
    }

    pub fn deinit(self: *Self) void {
        if(self.isListening()) {
            self.stopListening();
            @panic("Must call HttpClient.stopListening after calling HttpClient.startListening()");
        }

        if(self.event_listener_req) |*req| req.deinit(); 
        self.events.deinit(self.allocator);
        self.client.deinit();
    }

    pub fn resetClient(self: *Self) void {
        self.client.deinit();
        self.client = std.http.Client{.allocator = self.allocator};
    }

    /// Log message to console 
    fn log(self: *Self, comptime fmt: []const u8, args: anytype) !void {
        try self.stdout.print(fmt, args);
        try self.stdout.flush();
    }

    pub fn newEvent(
        self: *Self, 
        eventMsg: []const u8, 
        comptime onEvent: *const fn(event: *Event, pkg: *EventPkg) anyerror!void )!void {

        const event = Event{
            .msg = eventMsg, 
            .onEvent = onEvent,
        };

        try self.events.append(self.allocator, event);
    }

    pub fn eventListener(self: *Self) !void {
        const server_path = try std.fs.path.join(
            self.allocator, 
            &.{
                self.server_url, 
                ServerPaths.LISTEN,
            }
        );
        defer self.allocator.free(server_path);
        
        const uri = try std.Uri.parse(server_path);

        var response: ?std.http.Client.Response = null;
        var res_buf: [4096]u8 = undefined;
        var redir_buf: [4096]u8 = undefined;
        var res_reader: ?*std.io.Reader = null;

        self.setIsListening(true);
        while(true) {
            if(!self.isListening()) break;

            if(!self.connected or self.event_listener_req == null or response == null) {
                if(self.client.request(.GET, uri, .{})) 
                    |req| { self.event_listener_req = req; }
                else |err| switch(err) {
                    error.ConnectionRefused => { 
                        self.connected = false; 
                        self.event_listener_req = null; 
                    },
                    else => { return err; }
                }

                if(self.event_listener_req) |*req| {
                    req.sendBodiless() catch continue;
                    if(req.receiveHead(&redir_buf)) |res| { 
                        response = res; 
                    } 
                    else |err| switch (err) {
                        error.ConnectionRefused, error.HttpConnectionClosing => {
                            self.connected = false;
                            req.deinit();
                            self.event_listener_req = null;
                        },
                        else => { return err; }
                    }

                    if(response) |*res| {
                        if(res.head.status == .ok) self.connected = true else continue;
                        res_reader = res.reader(&res_buf);
                    } else continue; 
                } else continue;
            }

            if(!self.connected) continue;
            while (res_reader.?.takeDelimiterInclusive('\n')) |line| {
                if(!self.isListening()) break;
                if(line.len == 0) continue;

                for(self.events.items) |*event| {
                    if(!std.mem.eql(u8, event.msg, line)) continue;
                    var pkg = EventPkg{.client = self, .ctx = self.ctx, .std_out = self.stdout};
                    try event.onEvent(event, &pkg);
                }

            } else |err| switch(err) {
                error.EndOfStream, error.ReadFailed => { self.connected = false; }, 
                else => { return err; }
            }
        }
    }

    pub fn startListening(self: *Self) !void {
        if(self.isListening()) @panic("HttpClient is already listening!  Call HttpClient.stopListening()");

        self.setIsListening(true);
        self.event_listener_thread = try std.Thread.spawn(.{}, HttpClient(CtxType).eventListener, .{self}); 
    }

    pub fn stopListening(self: *Self) void {
        self.setIsListening(false);
        if(self.event_listener_req) |*req| {
            if(req.connection) |conn| {
                const stream = conn.stream_reader.getStream().handle;
                std.posix.shutdown(stream, .recv) catch {};
            }
        }
        if(self.event_listener_thread) |thread| { thread.join(); }
        if(self.event_listener_req) |*req| { req.deinit(); }

        self.event_listener_req = null;
        self.event_listener_thread = null;
    }

    fn isListening(self: *Self) bool {
        return self.listening.load(.acquire);
    }

    fn setIsListening(self: *Self, val: bool) void {
        self.listening.store(val, .release);
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

    fn printR(self: *Self, comptime fmt: []const u8, args: anytype) !void {
        const str = fmt ++ "\r";
        try self.stdout.print("\x1B[2K\r", .{});
        try self.stdout.print(str, args);
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

};}
