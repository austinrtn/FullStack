const std = @import("std");
const raylib = @import("raylib");

pub const PhotoViewer = struct {
    const Self = @This();
    const Config = struct {
        fullscreen: bool = false,

        screen_width: i32 = 800,
        screen_height: i32 = 600,
        fps: i32 = 60,
    };

    fullscreen: bool = false,

    screen_width: i32 = 800,
    screen_height: i32 = 600,
    fps: i32 = 60,

    pub fn init(config: Config) Self {
        var self: Self = undefined; 

        inline for(std.meta.fields(Config)) |field| {
            const config_field = @field(config, field.name);
            @field(self, field.name) = config_field;
        }
        return self;
    }

    pub fn initWindow(self: *Self) !void {

    }
};
