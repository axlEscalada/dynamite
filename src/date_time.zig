const std = @import("std");

test "test time" {
    const timestamp = std.time.timestamp();
    std.debug.print("test time {d}\n", .{timestamp});
    const epoch_seconds = @as(u64, @intCast(@max(timestamp, 0)));
    std.debug.print("epoch_seconds: {d}\n", .{epoch_seconds});

    var ts = std.time.epoch.EpochSeconds{ .secs = epoch_seconds };
    const epoch_day = ts.getEpochDay();
    const day_seconds = ts.getDaySeconds();
    std.debug.print("epoch_day: {any}\n", .{epoch_day});
    std.debug.print("day_seconds: {any}\n", .{day_seconds});
}
