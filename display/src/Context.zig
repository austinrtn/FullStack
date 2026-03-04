const std = @import("std");

pub const Context = struct {
    // Add std.Thread.Mutex or use Atomic values in Context to
    // ensure thread saftey
    arena: std.heap.ArenaAllocator,
    mutex: std.Thread.Mutex = .{},

    stdout_buf: [4096]u8 = undefined,
    stdout: *std.io.Writer,
    photos_available: bool = false,

    pub fn init(allocator: std.mem.Allocator) @This() {
        var self: @This() = undefined;
        self.arena = std.heap.ArenaAllocator.init(allocator);
        self.stdout = std.fs.File.stdout().writer(&self.stdout_buf);
        return self;
    }

    pub fn deinit(self: *@This()) void {
        self.arena.deinit();
    }

    pub fn copyVal(self: *@This(), comptime field_name: []const u8, val: anytype) !void {
        const field_ref = &@field(self, field_name);
        const FieldType = @TypeOf(field_ref.*);

        if(FieldType != @TypeOf(val)) { @compileError("Value of field does not match value of parameter\n"); }
        field_ref.* = try self.arena.allocator().dupe(std.meta.Child(FieldType), val);
    }
};
