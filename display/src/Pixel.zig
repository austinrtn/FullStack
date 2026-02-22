const std = @import("std");
const raylib = @import("raylib");

pub const Pixel = struct {
    color: raylib.color, 
    pos: raylib.Vector2, 
    vel: raylib.Vector2 = .{.x = 0, .y = 0},

    pub fn init(color: raylib.Color, pos: raylib.Vector2) @This() {
        return .{
            .color = color,
            .pos = pos,
        };      
    }
};

