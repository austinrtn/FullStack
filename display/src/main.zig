const std = @import("std");

const Client = struct {
    const Self = @This();
    server: []const u8,
    client: std.http.Client = undefined,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, server: []const u8) Self {
        var self: Self = .{
            .allocator = allocator,
            .server = server,
        };

        self.client = std.http.Client{.allocator = allocator};
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.client.deinit();
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var args = std.process.args();
    defer args.deinit();
    _ = args.next();

    const server = args.next() orelse return error.NoServerURL;

    var client = Client.init(allocator, server);
    defer client.deinit();

    std.debug.print("{s}", .{client.server});
}

