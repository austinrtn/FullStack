const std = @import("std");
const raylib = @import("raylib");
const Context = @import("./Context.zig").Context;

const PhotoCtx = struct {
    mutex: std.Thread.Mutex = .{},

    photo_dir_name: []const u8 = "photos",
    photo_dir: std.fs.Dir = undefined, 
    dir_index: usize = 0,
    texture: ?raylib.Texture2D = null, 
};

pub const PhotoViewer = struct {
    const Self = @This();
    const Config = struct {
        allocator: std.mem.Allocator,
        fullscreen: bool = false,

        screen_width: i32 = 800,
        screen_height: i32 = 600,
        fps: i32 = 60,
    };

    allocator: std.mem.Allocator,
    fullscreen: bool = false,
    screen_width: i32 = 800,
    screen_height: i32 = 600,
    fps: i32 = 60,

    impl: PhotoCtx = .{},
    do: bool = false,

    pub fn init(config: Config) !Self {
        var self = Self{
            .allocator = config.allocator,
            .fullscreen = config.fullscreen,
            .screen_width = config.screen_width,
            .screen_height = config.screen_height,
            .fps = config.fps,
        };

        self.impl.photo_dir = try std.fs.cwd().openDir(self.impl.photo_dir_name, .{});
        return self;
    }

    pub fn deinit(self: *Self) void {
        if(raylib.isWindowReady()) {
            if(raylib.isWindowFullscreen()) raylib.toggleFullscreen();
            raylib.closeWindow();
        }

        self.impl.photo_dir.close();
    }

    pub fn initWindow(self: *Self) void {
        raylib.initWindow(self.screen_width, self.screen_height, "Window");
        raylib.setTargetFPS(self.fps);
        if(self.fullscreen) raylib.toggleFullscreen();
    }

    pub fn loop(self: *Self) !void {
        self.do = true;
        var thread = try std.Thread.spawn(
            .{.allocator = self.allocator}, 
            updateFiles,
            .{self}
        );

        while(!raylib.windowShouldClose()) {
            self.render();
        }

        self.do = false;
        thread.join();
    } 

    pub fn updateFiles(self: *Self) !void {
        while(self.updating_files) {

        }
    }

    pub fn render(self: *Self) void {
        raylib.beginDrawing(); 
        defer raylib.endDrawing();

        raylib.clearBackground(.ray_white);

        if(self.impl.texture != null) {
            self.drawImg();
        }
        else {
            self.drawNoImgText();
        }

    }

    fn loadNextImg() void {

    }

    fn drawImg(self: *Self) void {
        const texture = self.impl.texture orelse unreachable;
        const texture_dims = self.getTextureSize() catch unreachable;

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
    }

    fn drawNoImgText(_: *Self) void {
        const screen_width = raylib.getRenderWidth();
        const screen_height = @divTrunc(raylib.getRenderHeight(), 2);
        const text = "No pictures loaded";
        const text_width = raylib.measureText(text, 32);
        const start_x = @divTrunc(screen_width, 2) 
            - @divTrunc(text_width, 2);

        raylib.drawText(text, start_x, screen_height, 32, .black);
    }

    pub fn getTextureSize(self: *Self) !struct {
            pos: raylib.Vector2,
            width: f32,
            height: f32,
        } {
            // Since this function is only to be called if a texture
            // exists, the program should crash if texture is null
            const texture = self.impl.texture orelse return error.NoTextureLoaded;        

            const screen_width: f32 = @floatFromInt(raylib.getRenderWidth());
            const screen_height: f32 = @floatFromInt(raylib.getRenderHeight());

            const texture_width: f32 = @floatFromInt(texture.width);
            const texture_height: f32 = @floatFromInt(texture.height);

            const min_size: f32 = 250.0;
            const max_size: f32 = 350.0;
            const scale = blk: {
                if((texture_width <= max_size and texture_height <= max_size) and
                    (texture_width >= min_size and texture_height >= min_size)) {
                    break :blk 1;
                }

                const w_scale = max_size / texture_width;
                const h_scale = max_size / texture_height;

                if(w_scale < h_scale) { break :blk w_scale; }
                else { break :blk h_scale; }
            };

            const fmt_width: f32 = texture_width * scale;
            const fmt_height: f32 = texture_height * scale;

            const pos: raylib.Vector2 = blk: {
                const x = (screen_width / 2) - (fmt_width / 2);
                const y = (screen_height / 2) - (fmt_height / 2);

                break :blk .{.x = x, .y = y};
            };
            return .{.pos = pos, .width = fmt_width, .height = fmt_height};
        }
};
