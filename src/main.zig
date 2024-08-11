const std = @import("std");
const c = @cImport({
    @cInclude("gtk/gtk.h");
});
const DynamoDbClient = @import("dynamo_client.zig").DynamoDbClient;
const DataValue = @import("dynamo_client.zig").DataValue;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var global_allocator: std.mem.Allocator = undefined;

var click_count: u32 = 0;

const AppWidgets = struct {
    list_box: *c.GtkListBox,
    entry: *c.GtkEntry,
    label: *c.GtkLabel,
};

fn activate(app: *c.GtkApplication, user_data: ?*anyopaque) callconv(.C) void {
    _ = user_data;

    std.debug.print("Activate function called\n", .{});
    if (c.gtk_init_check() == 0) {
        std.debug.print("Failed to initialize GTK\n", .{});
        return;
    }

    // Create a new window
    const window = c.gtk_application_window_new(app);
    if (window == null) {
        std.debug.print("Failed to create GtkApplicationWindow\n", .{});
        return;
    }

    c.gtk_window_set_title(@as(*c.GtkWindow, @ptrCast(window)), "GTK4 + Zig Example");
    c.gtk_window_set_default_size(@as(*c.GtkWindow, @ptrCast(window)), 300, 200);

    // Create a vertical box to hold the button and label
    const box = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 0);
    c.gtk_widget_set_margin_start(box, 10);
    c.gtk_widget_set_margin_end(box, 10);
    c.gtk_widget_set_margin_top(box, 10);
    c.gtk_widget_set_margin_bottom(box, 10);

    // Create a scrolled window to contain the list box
    const scrolled_window = c.gtk_scrolled_window_new();
    c.gtk_widget_set_vexpand(scrolled_window, 1);

    const list_box = c.gtk_list_box_new();
    c.gtk_scrolled_window_set_child(@as(*c.GtkScrolledWindow, @ptrCast(scrolled_window)), list_box);

    const entry = c.gtk_entry_new();
    c.gtk_entry_set_placeholder_text(@as(*c.GtkEntry, @ptrCast(entry)), "Insert table name...");
    c.gtk_widget_set_margin_start(entry, 10);
    c.gtk_widget_set_margin_end(entry, 10);
    c.gtk_widget_set_margin_top(entry, 10);
    c.gtk_widget_set_margin_bottom(entry, 10);

    // Create a button
    const button = c.gtk_button_new_with_label("Create table");
    c.gtk_widget_set_margin_start(button, 10);
    c.gtk_widget_set_margin_end(button, 10);
    c.gtk_widget_set_margin_top(button, 10);
    c.gtk_widget_set_margin_bottom(button, 10);

    // Create a label
    const label = c.gtk_label_new("Button not clicked yet");

    c.gtk_box_append(@as(*c.GtkBox, @ptrCast(box)), scrolled_window);
    c.gtk_widget_set_margin_start(label, 10);
    c.gtk_widget_set_margin_end(label, 10);
    c.gtk_widget_set_margin_bottom(label, 10);

    // c.gtk_box_append(@as(*c.GtkBox, @ptrCast(box)), text);
    c.gtk_box_append(@as(*c.GtkBox, @ptrCast(box)), entry);
    c.gtk_box_append(@as(*c.GtkBox, @ptrCast(box)), button);
    c.gtk_box_append(@as(*c.GtkBox, @ptrCast(box)), label);

    // Set the window's child to the box
    c.gtk_window_set_child(@as(*c.GtkWindow, @ptrCast(window)), box);

    const widgets = global_allocator.create(AppWidgets) catch unreachable;
    widgets.* = AppWidgets{
        .list_box = @as(*c.GtkListBox, @ptrCast(list_box)),
        .entry = @as(*c.GtkEntry, @ptrCast(entry)),
        .label = @as(*c.GtkLabel, @ptrCast(label)),
    };
    // Connect the "clicked" signal of the button to callback
    // This is called after GTK default handler (G_CONNECT_AFTER) with this we can access to "etry" gtk obejct
    _ = c.g_signal_connect_data(button, "clicked", @as(c.GCallback, @ptrCast(&button_clicked)), @ptrCast(widgets), null, c.G_CONNECT_AFTER);

    var dynamo_client = DynamoDbClient.init(global_allocator, "http://localhost:4566") catch |e| {
        std.debug.print("Error creating DynamoDbClient: {}\n", .{e});
        c.gtk_label_set_text(widgets.label, "Error creating DynamoDbClient");
        return;
    };
    var tables = dynamo_client.listTables() catch |e| {
        std.debug.print("Error listing tables {}", .{e});
        return;
    };
    defer tables.deinit(global_allocator);
    std.debug.print("Tables main {any}\n", .{tables});

    for (tables.TableNames.items) |table| {
        const c_table_name = global_allocator.dupeZ(u8, table) catch |e| {
            std.debug.print("Error duplicating table name: {}\n", .{e});
            return;
        };
        defer global_allocator.free(c_table_name);
        std.debug.print("Table name: {s} C table name: {s}\n", .{ table, c_table_name });
        const list_item = c.gtk_label_new(c_table_name);
        c.gtk_list_box_insert(widgets.list_box, list_item, -1);

        // Make sure the new item is visible
        c.gtk_widget_show(list_item);
    }

    c.gtk_window_present(@as(*c.GtkWindow, @ptrCast(window)));
}

fn button_clicked(button: *c.GtkButton, widgets: *AppWidgets) callconv(.C) void {
    _ = button;
    std.debug.print("Button clicked\n", .{});

    const buffer = c.gtk_entry_get_buffer(widgets.entry);
    const text = c.gtk_entry_buffer_get_text(buffer);
    if (text != null and c.gtk_entry_buffer_get_length(buffer) > 0) {
        const table_name = std.mem.span(text);
        std.debug.print("Entered text: {s}\n", .{table_name});

        var dynamo_client = DynamoDbClient.init(global_allocator, "http://localhost:4566") catch |e| {
            std.debug.print("Error creating DynamoDbClient: {}\n", .{e});
            c.gtk_label_set_text(widgets.label, "Error creating DynamoDbClient");
            return;
        };
        defer dynamo_client.deinit();

        dynamo_client.createTable(table_name, "id") catch |e| {
            std.debug.print("Error creating table: {}\n", .{e});
            c.gtk_label_set_text(widgets.label, "Error creating table");
            return;
        };

        std.debug.print("Table created successfully\n", .{});
        c.gtk_label_set_text(widgets.label, "Table created successfully");

        c.gtk_list_box_remove_all(widgets.list_box);
        var tables = dynamo_client.listTables() catch |e| {
            std.debug.print("Error listing tables {}", .{e});
            return;
        };
        defer tables.deinit(global_allocator);
        std.debug.print("Tables main {any}\n", .{tables});

        for (tables.TableNames.items) |table| {
            const c_table_name = global_allocator.dupeZ(u8, table) catch |e| {
                std.debug.print("Error duplicating table name: {}\n", .{e});
                return;
            };
            defer global_allocator.free(c_table_name);
            std.debug.print("Table name: {s} C table name: {s}\n", .{ table, c_table_name });
            const list_item = c.gtk_label_new(c_table_name);
            c.gtk_list_box_insert(widgets.list_box, list_item, -1);

            // Make sure the new item is visible
            c.gtk_widget_show(list_item);
        }
        c.gtk_entry_buffer_set_text(buffer, "", 0);
    } else {
        std.debug.print("No text entered\n", .{});
        c.gtk_label_set_text(widgets.label, "No table name entered");
    }
}
fn createNullTerminatedString(allocator: std.mem.Allocator, str: []const u8) ![:0]u8 {
    var null_terminated = try allocator.alloc(u8, str.len + 1);
    @memcpy(null_terminated[0..str.len], str);
    null_terminated[str.len] = 0;
    return null_terminated[0..str.len :0];
}

fn debug_handler(
    log_domain: [*c]const u8,
    log_level: c.GLogLevelFlags,
    message: [*c]const u8,
    user_data: ?*anyopaque,
) callconv(.C) void {
    _ = user_data;
    const level = switch (log_level) {
        c.G_LOG_LEVEL_ERROR => "ERROR",
        c.G_LOG_LEVEL_CRITICAL => "CRITICAL",
        c.G_LOG_LEVEL_WARNING => "WARNING",
        c.G_LOG_LEVEL_MESSAGE => "MESSAGE",
        c.G_LOG_LEVEL_INFO => "INFO",
        c.G_LOG_LEVEL_DEBUG => "DEBUG",
        else => "UNKNOWN",
    };
    std.debug.print("GTK [{s}] {s}: {s}\n", .{ level, log_domain, message });
}

pub fn main() !void {
    defer _ = gpa.deinit();
    global_allocator = gpa.allocator();
    std.debug.print("Starting application\n", .{});

    // Enable GTK debugging
    _ = c.g_setenv("G_MESSAGES_DEBUG", "all", 1);

    // Set up custom debug handler
    _ = c.g_log_set_handler("Gtk", c.G_LOG_LEVEL_MASK, debug_handler, null);
    _ = c.g_log_set_handler("GLib", c.G_LOG_LEVEL_MASK, debug_handler, null);
    _ = c.g_log_set_handler("Gdk", c.G_LOG_LEVEL_MASK, debug_handler, null);
    _ = c.g_log_set_handler("GObject", c.G_LOG_LEVEL_MASK, debug_handler, null);

    const app = c.gtk_application_new("com.example.GtkApplication", c.G_APPLICATION_FLAGS_NONE);
    if (app == null) {
        std.debug.print("Failed to create GtkApplication\n", .{});
        return error.GtkApplicationCreateFailed;
    }
    defer c.g_object_unref(app);

    _ = c.g_signal_connect_data(app, "activate", @as(c.GCallback, @ptrCast(&activate)), null, null, c.G_CONNECT_DEFAULT);

    std.debug.print("Signal connected\n", .{});

    std.debug.print("Running application\n", .{});

    const status = c.g_application_run(@as(*c.GApplication, @ptrCast(app)), 0, null);
    std.debug.print("Application exited with status: {}\n", .{status});
    if (status == 0) {
        return;
    } else {
        std.debug.print("Application exited with status: {}\n", .{status});
        return error.ApplicationRunFailed;
    }
}

// pub fn main() !void {
//     var gpa = std.heap.GeneralPurposeAllocator(.{}){};
//     defer _ = gpa.deinit();
//     const allocator = gpa.allocator();
//
//     var client = DynamoDbClient.init(allocator, "http://localhost:4566");
//
//     // Create a table
//     // try client.createTable("Dogs", "id");
//     // std.debug.print("Table created successfully\n", .{});
//
//     // Insert an item
//     var item = std.StringHashMap(DataValue).init(allocator);
//     defer item.deinit();
//     try item.put("id", .{ .data_type = .S, .value = "3" });
//     try item.put("name", .{ .data_type = .S, .value = "axl" });
//     try item.put("email", .{ .data_type = .S, .value = "axl@gmail.com" });
//
//     try client.putItem("Users", item);
//     std.debug.print("Item inserted successfully\n", .{});
// }
