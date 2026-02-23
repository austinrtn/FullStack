const std = @import("std");
const raylib = @import("raylib");
const HttpClient = @import("HttpClient.zig").HttpClient;
const PhotoHandler = @import("PhotoHandler.zig").PhotoHandler;
const FULL_SCREEN = false;

var photo_available = true;
var connected = true;

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

    var photo_dir = try std.fs.cwd().openDir(photo_path, .{.iterate = true});
    defer photo_dir.close();

    var stdout_buf: [4096]u8 = undefined;
    var stdout = std.fs.File.stdout().writer(&stdout_buf);
    const writer = &stdout.interface;

    var client = HttpClient.init(.{
        .allocator = allocator,
        .server_url = server_url,
        .photo_name = photo_name,
        .photo_dir = &photo_dir,
        .stdout = writer,
    });
    defer client.deinit();

    raylib.initWindow(800, 800, "Window");
    raylib.setTargetFPS(60);
    if(FULL_SCREEN) raylib.toggleFullscreen();
    defer{
        if(raylib.isWindowFullscreen()) raylib.toggleFullscreen();
        raylib.closeWindow(); 
    }    

    var photo_handler = PhotoHandler.init(.{.allocator = allocator, .photo_dir = &photo_dir, .photo_dir_path = photo_path});
    defer photo_handler.deinit();

    var buf: [1024]u8 = undefined;
    const shader_path = try std.fmt.bufPrintZ(&buf, "{s}/src/shaders/{s}", .{root_path, "Wave.frag"});
    const shader = try raylib.loadShader(null, shader_path);
    const time_loc = raylib.getShaderLocation(shader, "time");

    photo_available = true;
    connected = true;
    client.downloadRandomPhoto() catch |err| switch(err){
        error.NoPhotosAvailable => {
            photo_handler.texture = null;
            photo_available = false;
        },
        error.ConnectionRefused => {
            connected = false;
        },
        else => { return err; },
    };

    if(photo_available) try photo_handler.loadNextTexture();

    var timer = try std.time.Timer.start();
    while(!raylib.windowShouldClose()) {
        try runTimer(&timer, &client, &photo_handler);

        raylib.beginDrawing(); 
        defer raylib.endDrawing();

        raylib.clearBackground(.ray_white);

        if(!connected) {
            const screen_width = raylib.getRenderWidth();
            //const screen_height = raylib.getScreenHeight();
            const text = "Not Connected To Server";
            const text_width = raylib.measureText(text, 32);
            const start_x = @divTrunc(screen_width, 2) 
                - @divTrunc(text_width, 2);

            raylib.drawText(text, start_x, 400, 32, .black);
            continue;
        }

        const time: f32 = @floatCast(raylib.getTime());
        raylib.setShaderValue(shader, time_loc, &time, .float);

        if(photo_handler.texture) |texture| {
            const texture_dims = try photo_handler.getTextureSize();
            raylib.beginShaderMode(shader);

            raylib.drawTexturePro(
                texture, 
                .{ //Source Rectangle to read texture
                    .x = 0,
                    .y = 0,
                    .width = @floatFromInt(texture.width),
                    .height = @floatFromInt(texture.height),
                }, 
                .{ //Dest Rectangle to draw onto screen
                    .x = texture_dims.pos.x,
                    .y = texture_dims.pos.y,
                    .width = texture_dims.width,
                    .height = texture_dims.height,
                }, 
                .{.x = 0, .y = 0}, //origin point
                0, //rotation
                .white, //tint
            );
            raylib.endShaderMode();
        }
        else {
            const screen_width = raylib.getRenderWidth();
            //const screen_height = raylib.getScreenHeight();
            const text = "No pictures loaded";
            const text_width = raylib.measureText(text, 32);
            const start_x = @divTrunc(screen_width, 2) 
                - @divTrunc(text_width, 2);

            raylib.drawText(text, start_x, 400, 32, .black);
        }
    }
}

fn runTimer(timer: *std.time.Timer, client: *HttpClient, photo_handler: *PhotoHandler) !void {
    const elapsed = timer.read();

    if(elapsed >= (3 * std.time.ns_per_s)) {
        timer.reset();
        var caught_err = false; 

        connected = true;
        photo_available = true;

        client.downloadRandomPhoto() catch |err| switch(err){
            error.ConnectionRefused => {
                connected = false;
                caught_err = true;
            },
            error.NoPhotosAvailable => {
                photo_handler.texture = null;
                client.resetClient();
                photo_available = false;

                caught_err = true;
            }, 
            else => {return err;},
        };

        if(caught_err) return;

        try photo_handler.loadNextTexture();
    }
}

