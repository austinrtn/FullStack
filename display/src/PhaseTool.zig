
const std = @import("std");

const PhaseMarker = struct {
    phase: []const u8,
    line: u32, 
    reached: bool = false,
};

pub const PhaseTool = struct {
    allocator: std.mem.Allocator,
    phases: std.StringHashMap(PhaseMarker) = undefined,

    pub fn init(allocator: std.mem.Allocator) @This() {
        return @This(){
            .allocator = allocator,
            .phases = std.StringHashMap(PhaseMarker).init(allocator),
        };
    }

    pub fn setPhase(self: *@This(), phase: []const u8, line: u32) !void {
        if(self.phases.get(phase) != null) return; 
        const phase_marker = PhaseMarker{ .phase = phase, .line = line, .reached = true };
        try self.phases.put(phase, phase_marker);
    }

    pub fn setAndPrint(self: *@This(), phase: []const u8, line: u32) !void {
        if(self.phases.get(phase) != null) return; 

        const phase_marker = PhaseMarker{ .phase = phase, .line = line, .reached = true };
        try self.phases.put(phase, phase_marker);

        std.debug.print(
            "Phase: {s} | Line: {} \n", 
            .{ phase, line }, 
        );
    }

    pub fn printResults(self: *@This()) void {
        var iter = self.phases.keyIterator(); 

        while(iter.next()) |key| {
            const phase_marker = self.phases.get(key.*) orelse return;
            std.debug.print(
                "Phase: {s} | Line: {} \n", 
                .{ phase_marker.phase, phase_marker.line }, 
            );
        }
    }

    pub fn deinit(self: *@This()) void {
        self.phases.deinit();
    }

};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var phase_tool = PhaseTool.init(allocator);
    defer {
        phase_tool.printResults();
        phase_tool.deinit();
    }

    try phase_tool.setPhase("Phase 1", 0);
    try phase_tool.setPhase("Phase 2", 0);
}
