const std = @import("std");
const HttpClient = @import("HttpClient.zig").HttpClient;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var args = std.process.args();
    defer args.deinit();
    _ = args.next();

    const rootPath = args.next() orelse return error.NoRootPath;
    const server_url = args.next() orelse return error.NoServerURL;

    var stdout_buf: [4096]u8 = undefined;
    var stdout = std.fs.File.stdout().writer(&stdout_buf);
    const writer = &stdout.interface;

    var client = try HttpClient.init(allocator, rootPath, server_url, writer);
    defer client.deinit();

    try client.downloadRandomPhoto();
}

