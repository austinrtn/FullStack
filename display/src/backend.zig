const std = @import("std");
const Httplib = @import("./HttpClient.zig");
const HttpClient = Httplib.HttpClient(Context);

const Context = struct { established: bool = false};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var stdout_buf: [4096]u8 = undefined;
    var writer = std.fs.File.stdout().writer(&stdout_buf);
    const stdout = &writer.interface;

    var ctx = Context{};
    std.debug.print("Established: {}\n", .{ctx.established});
    var client = HttpClient.init(.{
        .allocator = allocator, 
        .stdout = stdout,
        .ctx = &ctx, 
    });
    defer client.deinit();

    var listener = try client.newEventListener();

    try listener.newEvent(
        "data::connection_established",
        struct {fn func(event: *HttpClient.Event) !void {
            event.ctx.established = true;
            try event.stdout.writeAll("Dick And Balls!\n");
            try event.stdout.flush();
        }}.func,
    );

    try listener.startListening("http://localhost:3000/events?category=DISPLAY");
    defer listener.stopListening();
    std.Thread.sleep(std.time.ns_per_s * 1); 
    std.debug.print("Established: {}\n", .{ctx.established});

    while(true) {
        var req = client.get("http://localhost:3000/test", .{}) catch |err| switch(err){ else => {continue;} };
        defer req.deinit();

        try stdout.print("{s}\n", .{req.body});
        try stdout.flush();
        break;
    }
}
