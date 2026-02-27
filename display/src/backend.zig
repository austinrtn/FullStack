const std = @import("std");
const HttpClient = @import("./HttpClient.zig").HttpClient;

const Context = struct {
    hello: []const u8 = "world",
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var args = std.process.args();
    defer args.deinit();
    _ = args.next();

    const root_path = args.next() orelse return error.NoRootPath;
    const server_url = args.next() orelse return error.NoServerURL;
    const photo_name = args.next() orelse return error.NoPhotoName;
    const photo_dir_name = args.next() orelse return error.NoPhotoDir;

    const photo_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{root_path, photo_dir_name});
    defer allocator.free(photo_path);

    std.fs.cwd().makeDir(photo_path) catch |err| switch(err) {
        error.PathAlreadyExists => {},
        else => { return err; }
    };
    var photo_dir = try std.fs.cwd().openDir(photo_path, .{.iterate = true});
    defer photo_dir.close();

    var stdout_buf: [4096]u8 = undefined;
    var stdout = std.fs.File.stdout().writer(&stdout_buf);
    const writer = &stdout.interface;

    var ctx = Context{};

    const Client = HttpClient(Context);
    var client = Client.init(.{
        .allocator = allocator, 
        .server_url = server_url,
        .photo_name = photo_name,
        .photo_dir = &photo_dir,
        .stdout = writer,
        .ctx = &ctx,
    });
    defer client.deinit();

    try client.startListening();
    defer client.stopListening();

    
    try client.newEvent(
        "data::conection_established",
        &conn
    );
}

fn conn (event: *HttpClient(Context).Event, _: *HttpClient(Context).EventPkg) anyerror!void {
    std.debug.print("{s}\n", .{event.msg});
}
