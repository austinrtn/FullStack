const std = @import("std");
const raylib = @import("raylib");

pub const PhotoHandler = struct {
    const Self = @This();
    const Config = struct {
        allocator: std.mem.Allocator,
        photo_dir_path: []const u8,
        photo_dir: *std.fs.Dir,
    };

    allocator: std.mem.Allocator,
    photo_dir_path: []const u8,
    photo_dir: *std.fs.Dir,

    texture: ?raylib.Texture2D = null,

    pub fn init(config: Config) Self {
        return Self{
           .allocator = config.allocator, 
           .photo_dir_path = config.photo_dir_path,
           .photo_dir = config.photo_dir,
        };
    }

    pub fn deinit(self: *Self) void {
        if(self.texture) |texture| raylib.unloadTexture(texture);
    }

    pub fn loadNextTexture(self: *Self) !void {
        if(self.texture) |texture| raylib.unloadTexture(texture);

        var dir_iterator = self.photo_dir.iterate();
        const file_entry = try dir_iterator.next();

        if(file_entry) |entry| {
            var path_buf: [1024]u8 = undefined ;
            const path = try std.fmt.bufPrintZ(&path_buf, "{s}/{s}", .{self.photo_dir_path, entry.name});

            self.texture = try raylib.loadTexture(path);
        } else {
            self.texture = null;
        }
    }

    pub fn getTextureSize(self: *Self) !struct {
        pos: raylib.Vector2,
        width: f32,
        height: f32,
    } {
        // Since this function is only to be called if a texture
        // exists, the program should crash if texture is null
        const texture = self.texture orelse return error.NoTextureLoaded;        

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

