const std = @import("std");
const raylib = @import("raylib");
const HttpClient = @import("HttpClient.zig").HttpClient;

var timer: std.time.Timer = undefined;
var client: HttpClient = undefined;
var photo_dir: std.fs.Dir = undefined;
var texture: ?raylib.Texture2D = null;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var args = std.process.args();
    defer args.deinit();
    _ = args.next();

    const root_path = args.next() orelse return error.NoRootPath;
    const server_url = args.next() orelse return error.NoServerURL;

    const photo_path = try std.fmt.allocPrint(allocator, "{s}/photos", .{root_path});
    defer allocator.free(photo_path);
    photo_dir = try std.fs.cwd().openDir(photo_path, .{.iterate = true});

    var stdout_buf: [4096]u8 = undefined;
    var stdout = std.fs.File.stdout().writer(&stdout_buf);
    const writer = &stdout.interface;

    client = try HttpClient.init(allocator, &photo_dir, server_url, writer);
    defer client.deinit();

    timer = try std.time.Timer.start();

    raylib.initWindow(800, 800, "Window");
    defer raylib.closeWindow();
    try client.downloadRandomPhoto();
    while(true) {
        raylib.beginDrawing(); 
        defer raylib.endDrawing();

        raylib.clearBackground(.ray_white);

        if(texture) |t| {
            raylib.drawTexture(t, 0, 0, .white);
        }
        else {
            const text = "No pictures loaded";
            const text_width = raylib.measureText(text, 32);
            const start_x = @divTrunc(raylib.getScreenWidth(), 2) 
                - @divTrunc(text_width, 2);

            raylib.drawText(text, start_x, 400, 32, .black);
        }
    }
}

fn downloadPhoto() !void {
    const elapsed = timer.read();
    if(elapsed >= (3 * std.time.ns_per_s)) {
        try client.downloadRandomPhoto();
        timer.reset();
    }
}

fn getTexture() !?[]const u8{
    return try photo_dir.iterate().next();
}
