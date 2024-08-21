const std = @import("std");

pub const DateTime = struct {
    year: u32,
    month: u8,
    day: u8,
    hour: u8,
    minute: u8,
    second: u8,

    pub fn now() DateTime {
        const timestamp = std.time.timestamp();
        std.debug.print("test time {d}\n", .{timestamp});
        const epoch_seconds = @as(u64, @intCast(@max(timestamp, 0)));
        std.debug.print("epoch_seconds: {d}\n", .{epoch_seconds});

        var ts = std.time.epoch.EpochSeconds{ .secs = epoch_seconds };
        const epoch_day = ts.getEpochDay();
        const year_day = epoch_day.calculateYearDay();
        const day_seconds = @as(u32, @intCast(ts.secs % std.time.s_per_day));

        const month_day = year_day.calculateMonthDay();
        std.debug.print("epoch_day: {any}\n", .{epoch_day});
        std.debug.print("day_seconds: {any}\n", .{day_seconds});
        std.debug.print("day: {d} year: {d}\n", .{ year_day.day, year_day.year });
        std.debug.print("Month: {d} day: {d}\n", .{ month_day.month.numeric(), month_day.day_index });

        const yd = epoch_day.calculateYearDay();
        const md = yd.calculateMonthDay();
        const year = yd.year;
        const month = md.month.numeric();
        const day = md.day_index;

        // Calculate hour, minute, and second
        const hour: u8 = @intCast(day_seconds / std.time.s_per_hour);
        const minute: u8 = @intCast((day_seconds % std.time.s_per_hour) / std.time.s_per_min);
        const second: u8 = @intCast(day_seconds % std.time.s_per_min);
        return DateTime{ .year = year, .month = month, .day = day, .hour = hour, .minute = minute, .second = second };
    }
};

test "test time" {
    const timestamp = std.time.timestamp();
    std.debug.print("test time {d}\n", .{timestamp});
    const epoch_seconds = @as(u64, @intCast(@max(timestamp, 0)));
    std.debug.print("epoch_seconds: {d}\n", .{epoch_seconds});

    var ts = std.time.epoch.EpochSeconds{ .secs = epoch_seconds };
    const epoch_day = ts.getEpochDay();
    const year_day = epoch_day.calculateYearDay();
    const day_seconds = @as(u32, @intCast(ts.secs % std.time.s_per_day));

    const month_day = year_day.calculateMonthDay();
    std.debug.print("epoch_day: {any}\n", .{epoch_day});
    std.debug.print("day_seconds: {any}\n", .{day_seconds});
    std.debug.print("day: {d} year: {d}\n", .{ year_day.day, year_day.year });
    std.debug.print("Month: {d} day: {d}\n", .{ month_day.month.numeric(), month_day.day_index });

    const yd = epoch_day.calculateYearDay();
    const md = yd.calculateMonthDay();
    const year = yd.year;
    const month = md.month.numeric();
    const day = md.day_index;

    // Calculate hour, minute, and second
    const hour = day_seconds / std.time.s_per_hour;
    const minute = (day_seconds % std.time.s_per_hour) / std.time.s_per_min;
    const second = day_seconds % std.time.s_per_min;

    // Print the result
    std.debug.print("Year: {}, Month: {}, Day: {}, Hour: {}, Minute: {}, Second: {}\n", .{ year, month, day, hour, minute, second });
    const now = DateTime.now();
    std.debug.print("Year: {}, Month: {}, Day: {}, Hour: {}, Minute: {}, Second: {}\n", .{ now.year, now.month, now.day, now.hour, now.minute, now.second });
}
