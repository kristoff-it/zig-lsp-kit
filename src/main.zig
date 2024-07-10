const std = @import("std");
const builtin = @import("builtin");

const Server = @import("Server.zig");
const Transport = @import("Transport.zig");

pub fn main() !void {
    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = general_purpose_allocator.deinit();

    const allocator = switch (builtin.cpu.arch) {
        .wasm32 => std.heap.wasm_allocator,
        else => general_purpose_allocator.allocator(),
    };

    var transport = Transport.init(
        std.io.getStdIn().reader(),
        std.io.getStdOut().writer(),
    );
    transport.message_tracing = false;

    const server = try Server.create(allocator, &transport);
    defer server.destroy();

    try server.loop();

    if (server.status == .exiting_failure) {
        if (builtin.mode == .Debug) {
            // make sure that GeneralPurposeAllocator.deinit gets run to detect leaks
            return;
        } else {
            std.process.exit(1);
        }
    }
}
