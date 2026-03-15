const std = @import("std");

pub const Context = struct {
    const Self = @This();
    impl: struct {
        arena: std.heap.ArenaAllocator,
        connection_established: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
        photos_available: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    },
    stdout: Stdout,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .impl = .{
                .arena = std.heap.ArenaAllocator.init(allocator),
            },
            .stdout = Stdout.init(),
        };
    }

    pub fn deinit(self: *Self) void {
        self.impl.arena.deinit();
    }

    pub fn isConnected(self: *Self) bool {
        return self.impl.connection_established.load(.acquire);
    }

    pub fn setConnected(self: *Self, connection_established: bool) void {
        self.impl.connection_established.store(connection_established, .release);
    }

    pub fn isPhotosAvailable(self: *Self) bool {
        return self.impl.photos_available.load(.acquire);
    }

    pub fn setPhotosAvailable(self: *Self, photos_available: bool) void {
        self.impl.photos_available.store(photos_available,.release);
    }

};

const Stdout = struct {
    const Self = @This();
    impl: struct {
        mutex: std.Thread.Mutex = .{},
        buf: [4096]u8 = undefined,
        stdout: std.fs.File.Writer = undefined,
    },

    fn init() Self {
        var self = Self{.impl = .{}};
        self.impl.stdout = std.fs.File.stdout().writer(&self.impl.buf);
        return self;
    }

    pub fn print(self: *@This(), comptime fmt: []const u8, args: anytype) !void {
        self.impl.mutex.lock();
        defer self.impl.mutex.unlock();
        try self.impl.stdout.interface.print(fmt, args);
    }

    pub fn flush(self: *@This()) !void {
        self.impl.mutex.lock();
        defer self.impl.mutex.unlock();
        try self.impl.stdout.interface.flush();
    }

    pub fn printAndFlush(self: *@This(), comptime fmt: []const u8, args: anytype) !void {
        self.impl.mutex.lock();
        defer self.impl.mutex.unlock();
        try self.impl.stdout.interface.print(fmt, args);
        try self.impl.stdout.interface.flush();
    }
};
