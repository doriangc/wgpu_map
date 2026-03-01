const std = @import("std");
const proto_vector_tile = @import("proto/vector_tile.pb.zig");

pub fn readTile(allocator: std.mem.Allocator, path: []const u8) !void {
    const file = std.fs.cwd().openFile(path, .{}) catch {
        std.log.info("Failed to open file: {s}\n", .{path});
        return;
    };
    defer file.close();

    const file_size = file.getEndPos() catch {
        std.log.info("Failed to get file size: {s}\n", .{path});
        return;
    };

    const buffer = allocator.alloc(u8, file_size) catch {
        std.log.info("Failed to allocate buffer for file: {s}\n", .{path});
        return;
    };
    defer allocator.free(buffer);

    _ = file.readAll(buffer) catch {
        std.log.info("Failed to read file: {s}\n", .{path});
        return;
    };

    var tile = try proto_vector_tile.Tile.decode(buffer, allocator);
    defer tile.deinit();

    const xy = struct {
        x: i16,
        y: i16,
    };

    const Points = struct {
        points: std.ArrayList(xy),
    };

    const LineString = struct {
        points: std.ArrayList(xy),
    };

    const Polygon = struct {
        exterior_points: std.ArrayList(xy),
        interior_rings: std.ArrayList(std.ArrayList(xy)),
    };

    const Shape = union(enum) {
        points: Points,
        line_string: LineString,
        polygon: Polygon,
    };

    for (tile.layers.items) |layer| {
        const name = layer.name.getSlice();
        const count = layer.features.items.len;
        std.debug.print("Layer: {s} | Features: {d} | version: {d}\n", .{ name, count, layer.version });

        var features = std.ArrayList(Shape).init(allocator);

        // Each feature has a geometry 'command' list
        for (layer.features.items) |feature| {
            const geom_type = feature.type orelse .UNKNOWN;

            var current_feature = switch (geom_type) {
                .POINT => Shape{ .points = Points{ .points = std.ArrayList(xy).init(allocator) } },
                .LINESTRING => Shape{ .line_string = LineString{ .points = std.ArrayList(xy).init(allocator) } },
                .POLYGON => Shape{ .polygon = Polygon{
                    .exterior_points = std.ArrayList(xy).init(allocator),
                    .interior_rings = std.ArrayList(std.ArrayList(xy)).init(allocator),
                } },
                else => continue, // Skip unknown geometry types
            };

            std.debug.print("  Feature ID: {d} | Type: {d} | Geometry Commands: {d}\n", .{ feature.id orelse 0, geom_type, feature.geometry.items.len });

            for (0..feature.tags.items.len / 2) |tag_idx| {
                const key_idx = feature.tags.items[tag_idx * 2];
                const value_idx = feature.tags.items[tag_idx * 2 + 1];

                const key = layer.keys.items[key_idx].getSlice();
                const value =
                    if (layer.values.items[value_idx].string_value) |str_val| str_val.getSlice() else "N/A";

                std.debug.print("    Tag: Key={s}, Value={s}\n", .{ key, value });
            }

            const Command = enum(u32) {
                MoveTo = 1,
                LineTo = 2,
                ClosePath = 7,
            };

            var current_parameter_count = 0;
            var current_command: Command = undefined;
            var current_command_count = 0;
            var parameters_accumulator = std.ArrayList(i32).init(allocator);

            for (feature.geometry.items) |cmd| {
                if (current_parameter_count == 0) {
                    const cmd_id: Command = @enumFromInt(cmd & 0x7); // lower 3 bits
                    const cmd_count = cmd >> 3; // upper bits

                    current_command = cmd_id;
                    current_command_count = cmd_count;

                    current_parameter_count = switch (cmd_id) {
                        .MoveTo => 2 * cmd_count,
                        .LineTo => 2 * cmd_count,
                        .ClosePath => 0,
                        else => unreachable,
                    };
                } else {
                    const value = ((cmd >> 1) ^ (-(cmd & 1)));
                    try parameters_accumulator.append(value);
                    current_parameter_count -= 1;
                }

                // Current command is complete
                if (current_parameter_count == 0) {
                    // Process the accumulated parameters for the current command
                    switch (current_command) {
                        .MoveTo, .LineTo => {
                            for (0..current_command_count) |i| {
                                const x = parameters_accumulator.items[i * 2];
                                const y = parameters_accumulator.items[i * 2 + 1];
                                const point = xy{ .x = x, .y = y };

                                switch (current_feature) {
                                    .points => current_feature.points.points.append(point) catch {},
                                    .line_string => current_feature.line_string.points.append(point) catch {},
                                    .polygon => current_feature.polygon.moveTo(point),
                                    else => unreachable,
                                }
                            }
                        },
                        .ClosePath => {
                            // Handle ClosePath if needed
                        },
                        else => unreachable,
                    }

                    parameters_accumulator.clear();
                }
            }

            try features.append(current_feature);
        }
    }
}
