const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const diffz = b.dependency("diffz", .{});

    const module = b.addModule(
        "lsp",
        .{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "diffz", .module = diffz.module("diffz") },
            },
        },
    );

    const lsp_codegen = b.dependency("lsp_codegen", .{});
    module.addImport("lsp", lsp_codegen.module("lsp"));
}
