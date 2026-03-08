const std = @import("std");
const raylib = @import("raylib"); const Display = @import("Display");
const Context = Display.Context;

const Client = @import("ZigClient");
const ZigClient = Client.ZigClient(Context);
const PhotoManager = Display.PhotoManager;

const url = "http://localhost:3000/";
const FULL_SCREEN = false;
var photo_available = true;
var connected = true;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var ctx = Context.init(allocator);
    defer ctx.deinit();

    var client = ZigClient.init(allocator, &ctx);
    defer client.deinit();

    var listener = try client.newEventListener();
    try initEvents(listener);

    try listener.startListening(url ++ "events?category=DISPLAY");
    defer listener.stopListening();

    var photo_manager = PhotoManager.init(.{
        .allocator = allocator,
        .url = url,
        .client = &client,
        .photo_dir = "photos",
        .ctx = &ctx,
    });
    defer photo_manager.deinit();

    var attempting = false;
    while(true) {
        if(!attempting) std.debug.print("Downloading Photo {}/7\n", .{photo_manager.photo_index});
        photo_manager.getNextPhoto() catch |err| switch(err){
            error.NotConnected => {
                attempting = true;
                continue;
            },
            else => return err,
        };
        attempting = false;
        std.debug.print("Photo Downloaded!\n", .{});
        std.Thread.sleep(std.time.ns_per_s * 0.5);
    }

    if(true) return;
    
    raylib.initWindow(800, 800, "Window");
    raylib.setTargetFPS(60);
    if(FULL_SCREEN) raylib.toggleFullscreen();
    defer{
        if(raylib.isWindowFullscreen()) raylib.toggleFullscreen();
        raylib.closeWindow(); 
    }    
//
//     var buf: [1024]u8 = undefined;
//     const shader_path = try std.fmt.bufPrintZ(&buf, "{s}/src/shaders/{s}", .{root_path, "Wave.frag"});
//     const shader = try raylib.loadShader(null, shader_path);
//     const time_loc = raylib.getShaderLocation(shader, "time");
//
//
    while(!raylib.windowShouldClose()) {

        raylib.beginDrawing(); 
        defer raylib.endDrawing();

        raylib.clearBackground(.ray_white);

        const screen_width = raylib.getRenderWidth();
        //const screen_height = raylib.getScreenHeight();
        const text = "Not Connected To Server";
        const text_width = raylib.measureText(text, 32);
        const start_x = @divTrunc(screen_width, 2) - @divTrunc(text_width, 2);

        raylib.drawText(text, start_x, 400, 32, .black);
    }
}
//         const time: f32 = @floatCast(raylib.getTime());
//         raylib.setShaderValue(shader, time_loc, &time, .float);
//
//         if(photo_handler.texture) |texture| {
//             const texture_dims = try photo_handler.getTextureSize();
//             raylib.beginShaderMode(shader);
//
//             raylib.drawTexturePro(
//                 texture, 
//                 .{ //Source Rectangle to read texture
//                     .x = 0,
//                     .y = 0,
//                     .width = @floatFromInt(texture.width),
//                     .height = @floatFromInt(texture.height),
//                 }, 
//                 .{ //Dest Rectangle to draw onto screen
//                     .x = texture_dims.pos.x,
//                     .y = texture_dims.pos.y,
//                     .width = texture_dims.width,
//                     .height = texture_dims.height,
//                 }, 
//                 .{.x = 0, .y = 0}, //origin point
//                 0, //rotation
//                 .white, //tint
//             );
//             raylib.endShaderMode();
//         }
//         else {
//             const screen_width = raylib.getRenderWidth();
//             //const screen_height = raylib.getScreenHeight();
//             const text = "No pictures loaded";
//             const text_width = raylib.measureText(text, 32);
//             const start_x = @divTrunc(screen_width, 2) 
//                 - @divTrunc(text_width, 2);
//
//             raylib.drawText(text, start_x, 400, 32, .black);
//         }
//     }
// }
//
//
fn initEvents(listener: *ZigClient.Listener) !void {
    try listener.newEvent(
        "data::connection_established",
        true,
        struct {
            fn onevent(event: *ZigClient.Event) !void {
                event.ctx.mutex.lock();
                defer event.ctx.mutex.unlock();
                event.ctx.setConnected(true);
            }
        }.onevent,
    );

    try listener.newEvent(
        "data::photos_available",
        false,
        struct {
            fn onevent(event: *ZigClient.Event) !void {
                event.ctx.mutex.lock();
                defer event.ctx.mutex.unlock();
                event.ctx.photos_available = true;
            }
        }.onevent,
    );

    try listener.newEvent(
        "data::no_photos_available",
        false,
        struct {
            fn onevent(event: *ZigClient.Event) !void {
                event.ctx.mutex.lock();
                defer event.ctx.mutex.unlock();
                event.ctx.photos_available = false;
            }
        }.onevent,
    );
}
