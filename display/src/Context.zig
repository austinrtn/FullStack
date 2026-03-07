const std = @import("std");

pub const Context = struct {
    impl: struct {
        arena: std.heap.ArenaAllocator,
        connection_established: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    },
    mutex: std.Thread.Mutex = .{},
    stdout: Stdout,
    photos_available: bool = false,

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .impl = .{
                .arena = std.heap.ArenaAllocator.init(allocator),
            },
            .stdout = Stdout.init(),
        };
    }

    pub fn deinit(self: *@This()) void {
        self.impl.arena.deinit();
    }

    pub fn copyVal(self: *@This(), comptime field_name: []const u8, val: anytype) !void {
        const field_ref = &@field(self, field_name);
        const FieldType = @TypeOf(field_ref.*);

        if(FieldType != @TypeOf(val)) { @compileError("Value of field does not match value of parameter\n"); }
        field_ref.* = try self.impl.arena.allocator().dupe(std.meta.Child(FieldType), val);
    }

    pub fn isConnected(self: *@This()) bool {
        return self.impl.connection_established.load(.acquire);
    }

    pub fn setConnected(self: *@This(), connection_established: bool) void {
        self.impl.connection_established.store(connection_established, .release);
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
