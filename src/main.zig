const std = @import("std");
const c = @cImport({
    @cInclude("gtk/gtk.h");
});
const DynamoDbClient = @import("dynamo_client.zig").DynamoDbClient;
const DataValue = @import("dynamo_client.zig").DataValue;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var global_allocator: std.mem.Allocator = undefined;

var click_count: u32 = 0;

const MainWindow = struct {
    window: ?*c.GtkWindow,
    stack: ?*c.GtkStack,
    list_box: ?*c.GtkListBox,
    create_button: ?*c.GtkButton,
    entry: ?*c.GtkEntry,
    confirm_button: ?*c.GtkButton,
    back_button: ?*c.GtkButton,
    label: ?*c.GtkLabel,
};

var main_window: MainWindow = undefined;

fn activate(app: ?*c.GtkApplication, user_data: ?*anyopaque) callconv(.C) void {
    _ = user_data;

    main_window = MainWindow{
        .window = @ptrCast(c.gtk_application_window_new(app)),
        .stack = @ptrCast(c.gtk_stack_new()),
        .list_box = @ptrCast(c.gtk_list_box_new()),
        .create_button = @ptrCast(c.gtk_button_new_with_label("Create Table")),
        .entry = @ptrCast(c.gtk_entry_new()),
        .confirm_button = @ptrCast(c.gtk_button_new_with_label("Create")),
        .back_button = @ptrCast(c.gtk_button_new_with_label("Back")),
        .label = @ptrCast(c.gtk_label_new(null)),
    };

    c.gtk_window_set_title(main_window.window, "Dynamite");
    c.gtk_window_set_default_size(main_window.window, 300, 400);
    c.gtk_entry_set_placeholder_text(main_window.entry, "Insert table name...");

    const main_box = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 10);
    c.gtk_widget_set_margin_start(@ptrCast(main_box), 10);
    c.gtk_widget_set_margin_end(@ptrCast(main_box), 10);
    c.gtk_widget_set_margin_top(@ptrCast(main_box), 10);
    c.gtk_widget_set_margin_bottom(@ptrCast(main_box), 10);

    const scrolled_window = c.gtk_scrolled_window_new();
    c.gtk_scrolled_window_set_child(@ptrCast(scrolled_window), @alignCast(@ptrCast(main_window.list_box)));
    c.gtk_widget_set_vexpand(@ptrCast(scrolled_window), 1);

    c.gtk_box_append(@ptrCast(main_box), @ptrCast(scrolled_window));
    c.gtk_widget_set_margin_top(@ptrCast(main_window.create_button), 10);
    c.gtk_box_append(@ptrCast(main_box), @ptrCast(main_window.create_button));

    const create_box = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 10);
    c.gtk_widget_set_margin_start(@ptrCast(create_box), 10);
    c.gtk_widget_set_margin_end(@ptrCast(create_box), 10);
    c.gtk_widget_set_margin_top(@ptrCast(create_box), 10);
    c.gtk_widget_set_margin_bottom(@ptrCast(create_box), 10);

    c.gtk_box_append(@ptrCast(create_box), @ptrCast(main_window.entry));
    c.gtk_box_append(@ptrCast(create_box), @alignCast(@ptrCast(main_window.label)));
    c.gtk_box_append(@ptrCast(create_box), @ptrCast(main_window.confirm_button));
    c.gtk_box_append(@ptrCast(create_box), @ptrCast(main_window.back_button));

    _ = c.gtk_stack_add_named(main_window.stack, @ptrCast(main_box), "main");
    _ = c.gtk_stack_add_named(main_window.stack, @ptrCast(create_box), "create");

    c.gtk_window_set_child(main_window.window, @alignCast(@ptrCast(main_window.stack)));

    _ = c.g_signal_connect_data(@ptrCast(main_window.create_button), "clicked", @ptrCast(&switchToCreateView), null, null, 0);
    _ = c.g_signal_connect_data(@ptrCast(main_window.confirm_button), "clicked", @ptrCast(&createTable), null, null, 0);
    _ = c.g_signal_connect_data(@ptrCast(main_window.back_button), "clicked", @ptrCast(&switchToMainView), null, null, 0);

    var dynamo_client = DynamoDbClient.init(global_allocator, "http://localhost:4566") catch |e| {
        std.debug.print("Error creating DynamoDbClient: {}\n", .{e});
        return;
    };
    defer dynamo_client.deinit();

    c.gtk_list_box_remove_all(@ptrCast(main_window.list_box));
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
        c.gtk_list_box_insert(@ptrCast(main_window.list_box), list_item, -1);

        c.gtk_widget_show(list_item);
    }

    c.gtk_widget_show(@ptrCast(main_window.window));
}

fn switchToCreateView(button: ?*c.GtkButton, user_data: ?*anyopaque) callconv(.C) void {
    _ = button;
    _ = user_data;
    c.gtk_stack_set_visible_child_name(main_window.stack, "create");
}

fn switchToMainView(button: ?*c.GtkButton, user_data: ?*anyopaque) callconv(.C) void {
    _ = button;
    _ = user_data;
    c.gtk_stack_set_visible_child_name(main_window.stack, "main");
}

fn createTable(button: ?*c.GtkWidget, user_data: ?*anyopaque) callconv(.C) void {
    std.debug.print("Open create table window\n", .{});
    _ = user_data;
    _ = button;
    std.debug.print("Button clicked\n", .{});

    const buffer = c.gtk_entry_get_buffer(main_window.entry);
    const text = c.gtk_entry_buffer_get_text(buffer);
    if (text != null and c.gtk_entry_buffer_get_length(buffer) > 0) {
        const table_name = std.mem.span(text);
        std.debug.print("Entered text: {s}\n", .{table_name});

        var dynamo_client = DynamoDbClient.init(global_allocator, "http://localhost:4566") catch |e| {
            std.debug.print("Error creating DynamoDbClient: {}\n", .{e});
            c.gtk_label_set_text(main_window.label, "Error creating DynamoDbClient");
            return;
        };
        defer dynamo_client.deinit();

        dynamo_client.createTable(table_name, "id") catch |e| {
            std.debug.print("Error creating table: {}\n", .{e});
            c.gtk_label_set_text(main_window.label, "Error creating table");
            return;
        };

        std.debug.print("Table created successfully\n", .{});
        c.gtk_label_set_text(main_window.label, "Table created successfully");

        c.gtk_list_box_remove_all(main_window.list_box);
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
            c.gtk_list_box_insert(main_window.list_box, list_item, -1);

            // Make sure the new item is visible
            c.gtk_widget_show(list_item);
        }
        c.gtk_entry_buffer_set_text(buffer, "", 0);
    } else {
        std.debug.print("No text entered\n", .{});
        c.gtk_label_set_text(main_window.label, "No table name entered");
    }

    // const table_name = c.gtk_entry_buffer_get_text(c.gtk_entry_get_buffer(main_window.entry));
    // std.debug.print("Creating table: {s}\n", .{table_name});
    //
    //
    // const list_item = c.gtk_label_new(table_name);
    // c.gtk_list_box_append(main_window.list_box, @ptrCast(list_item));

    c.gtk_entry_buffer_set_text(c.gtk_entry_get_buffer(main_window.entry), "", 0);
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
