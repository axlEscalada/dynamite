const std = @import("std");
const c = @cImport({
    @cInclude("gtk/gtk.h");
});
const DynamoDbClient = @import("dynamo_client.zig").DynamoDbClient;
const DataValue = @import("dynamo_client.zig").DataValue;
const gtk = @import("gtk.zig");
const builtin = @import("builtin");

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

const TableWindow = struct {
    tree_view: *c.GtkTreeView,
    list_store: *c.GtkListStore,
};

var main_window: MainWindow = undefined;

fn activate(app: ?*c.GtkApplication, user_data: ?*anyopaque) callconv(.C) void {
    _ = user_data;
    loadCss();

    //set gtk dark theme by default
    if (c.gtk_settings_get_default()) |settings| {
        _ = c.g_object_set(@ptrCast(settings), "gtk-application-prefer-dark-theme", @as(c.gboolean, 1), @as(?*anyopaque, null));
    }

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

    const header_bar = c.gtk_header_bar_new();
    const title_label = c.gtk_label_new("Dynamite");
    c.gtk_window_set_titlebar(gtk.GTK_WINDOW(@ptrCast(main_window.window)), header_bar);
    c.gtk_header_bar_set_title_widget(gtk.GTK_HEADER_BAR(@ptrCast(header_bar)), title_label);
    c.gtk_widget_add_css_class(@ptrCast(header_bar), "header");

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

    c.gtk_widget_add_css_class(@ptrCast(main_window.entry), "create-entry");
    c.gtk_widget_add_css_class(@ptrCast(main_window.confirm_button), "create-button");
    c.gtk_widget_add_css_class(@ptrCast(main_window.create_button), "create-button");
    c.gtk_box_append(@ptrCast(create_box), @ptrCast(main_window.entry));
    c.gtk_box_append(@ptrCast(create_box), @alignCast(@ptrCast(main_window.label)));
    c.gtk_box_append(@ptrCast(create_box), @ptrCast(main_window.confirm_button));

    const table_box = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 10);
    c.gtk_widget_set_margin_start(@ptrCast(table_box), 10);
    c.gtk_widget_set_margin_end(@ptrCast(table_box), 10);
    c.gtk_widget_set_margin_top(@ptrCast(table_box), 10);
    c.gtk_widget_set_margin_bottom(@ptrCast(table_box), 10);

    const tree_view = createEmptyDetailTreeView();
    if (tree_view == null) {
        std.debug.print("Failed to create detail tree view\n", .{});
        return;
    }
    c.gtk_box_append(@ptrCast(table_box), tree_view);

    _ = c.gtk_stack_add_named(main_window.stack, @ptrCast(main_box), "main");
    _ = c.gtk_stack_add_named(main_window.stack, @ptrCast(createViewWithBackButton(create_box)), "create");
    _ = c.gtk_stack_add_named(main_window.stack, @ptrCast(createViewWithBackButton(table_box)), "table");

    c.gtk_window_set_child(main_window.window, @alignCast(@ptrCast(main_window.stack)));

    _ = c.g_signal_connect_data(@ptrCast(main_window.create_button), "clicked", @ptrCast(&switchToCreateView), null, null, 0);
    _ = c.g_signal_connect_data(@ptrCast(main_window.confirm_button), "clicked", @ptrCast(&createTable), null, null, 0);
    // c.gtk_list_box_set_activate_on_single_click(main_window.list_box, 0);
    _ = c.g_signal_connect_data(@ptrCast(main_window.list_box), "row-activated", @ptrCast(&switchToTableView), @ptrCast(tree_view), null, c.G_CONNECT_AFTER);

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

fn createEmptyDetailTreeView() ?*c.GtkWidget {
    const list_store = c.gtk_list_store_new(1, c.G_TYPE_STRING);
    if (list_store == null) {
        std.debug.print("Failed to create list store\n", .{});
        return null;
    }

    const tree_view = c.gtk_tree_view_new_with_model(@ptrCast(list_store));
    if (tree_view == null) {
        std.debug.print("Failed to create tree view\n", .{});
        return null;
    }

    return tree_view;
}

fn addToggleColumn(tree_view: *c.GtkTreeView, title: [*c]const u8, column_id: c_int) void {
    std.debug.print("Toggle column \n", .{});
    const renderer = c.gtk_cell_renderer_toggle_new();
    const column = c.gtk_tree_view_column_new();
    c.gtk_tree_view_column_set_title(column, title);
    c.gtk_tree_view_column_pack_start(column, renderer, @as(c_int, 1));
    c.gtk_tree_view_column_add_attribute(column, renderer, "active", column_id);
    _ = c.gtk_tree_view_append_column(tree_view, column);
}

fn addTextColumn(tree_view: *c.GtkTreeView, title: []const u8, column_id: c_int) void {
    const c_title = global_allocator.dupeZ(u8, title) catch unreachable;
    defer global_allocator.free(c_title);
    std.debug.print("Text column \n", .{});
    const renderer = c.gtk_cell_renderer_text_new();
    const column = c.gtk_tree_view_column_new();
    c.gtk_tree_view_column_set_title(column, c_title);
    c.gtk_tree_view_column_pack_start(column, renderer, @as(c_int, 1));
    c.gtk_tree_view_column_add_attribute(column, renderer, "text", column_id);
    _ = c.gtk_tree_view_append_column(tree_view, column);
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

fn switchToTableView(
    list_box: *c.GtkListBox,
    row: *c.GtkListBoxRow,
    user_data: ?*anyopaque,
) callconv(.C) void {
    const tree_view = @as(?*c.GtkWidget, @alignCast(@ptrCast(user_data)));
    std.debug.print("Reach row func {any} row: {any}\n", .{ list_box, row });
    var dynamo_client = DynamoDbClient.init(global_allocator, "http://localhost:4566") catch |e| {
        std.debug.print("Error creating DynamoDbClient: {}\n", .{e});
        return;
    };
    defer dynamo_client.deinit();

    const item = c.gtk_list_box_row_get_child(row);
    if (item == null) {
        std.debug.print("Error: No child widget found in the row\n", .{});
        return;
    }

    const text_c = c.gtk_label_get_text(@as(*c.GtkLabel, @ptrCast(item)));

    const table = std.mem.span(text_c);

    const response = dynamo_client.scanTable([]const u8, table) catch |err| {
        std.debug.print("Error scanning table: {}\n", .{err});
        return;
    };
    // defer response.deinit(global_allocator);

    std.debug.print("Response: {s}\n", .{response.Items});
    var column_names = [_][]const u8{"Item"};
    populateDetailTreeView(tree_view, &column_names, response.Items) catch |e| {
        std.log.err("Error while populating column {any}\n", .{e});
        return;
    };

    c.gtk_stack_set_visible_child_name(main_window.stack, "table");
    //workaround for macOS
    if (builtin.target.os.tag == .macos) {
        gtk.proccessPendingEvents();
    }
}

const TableData = struct {
    headers: [][]const u8,
    data: []const [][]const u8,
};

fn populateDetailTreeView(tree_widget: ?*c.GtkWidget, column_names: [][]const u8, data: [][]const u8) !void {
    const tree_view: *c.GtkTreeView = @alignCast(@ptrCast(tree_widget));
    c.gtk_tree_view_set_grid_lines(tree_view, c.GTK_TREE_VIEW_GRID_LINES_HORIZONTAL);
    const list_store = @as(?*c.GtkListStore, @alignCast(@ptrCast(c.gtk_tree_view_get_model(tree_view))));

    //Clear columns
    var is_populated: c_int = 1;
    while (is_populated == 1) {
        const column: ?*c.GtkTreeViewColumn = c.gtk_tree_view_get_column(tree_view, 0);
        if (column) |co| {
            is_populated = c.gtk_tree_view_remove_column(tree_view, co);
        } else {
            is_populated = 0;
        }
    }

    _ = c.gtk_list_store_clear(list_store);

    for (column_names, 0..) |name, i| {
        addTextColumn(tree_view, name, @as(c_int, @intCast(i)));
    }

    var iter: c.GtkTreeIter = undefined;
    for (data) |row| {
        _ = c.gtk_list_store_append(list_store, &iter);
        const c_string = try global_allocator.dupeZ(u8, row);
        defer global_allocator.free(c_string);
        _ = c.gtk_list_store_set(list_store, &iter, //
            @as(c_int, 0), c_string.ptr, //
            @as(c_int, -1));
    }
}

fn createViewWithBackButton(content: ?*c.GtkWidget) *c.GtkWidget {
    const main_box = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 0);

    const header_box = c.gtk_box_new(c.GTK_ORIENTATION_HORIZONTAL, 0);
    c.gtk_widget_set_margin_start(@ptrCast(header_box), 10);
    c.gtk_widget_set_margin_top(@ptrCast(header_box), 10);
    c.gtk_widget_set_margin_bottom(@ptrCast(header_box), 10);

    const back_button = createBackMainButton();
    c.gtk_box_append(@ptrCast(header_box), @ptrCast(back_button));

    const spacer = c.gtk_box_new(c.GTK_ORIENTATION_HORIZONTAL, 0);
    c.gtk_widget_set_hexpand(@ptrCast(spacer), 1);
    c.gtk_box_append(@ptrCast(header_box), @ptrCast(spacer));

    c.gtk_box_append(@ptrCast(main_box), @ptrCast(header_box));

    if (content) |widget| {
        c.gtk_box_append(@ptrCast(main_box), widget);
    }

    return main_box;
}

fn createBackMainButton() *c.GtkWidget {
    const back_button = c.gtk_button_new_from_icon_name("go-previous-symbolic");
    c.gtk_widget_add_css_class(@ptrCast(back_button), "back-button");
    c.gtk_widget_set_halign(@ptrCast(back_button), c.GTK_ALIGN_START);
    c.gtk_widget_set_valign(@ptrCast(back_button), c.GTK_ALIGN_START);
    c.gtk_widget_set_margin_start(@ptrCast(back_button), 0);
    c.gtk_widget_set_margin_top(@ptrCast(back_button), 0);
    _ = c.g_signal_connect_data(@ptrCast(back_button), "clicked", @ptrCast(&switchToMainView), null, null, 0);
    return back_button;
}

fn loadCss() void {
    const css_data = @embedFile("css/style.css");
    std.debug.print("css_data: {s}\n", .{css_data});
    const css_provider = c.gtk_css_provider_new();
    c.gtk_css_provider_load_from_data(css_provider, css_data, -1);
    const display = c.gdk_display_get_default();
    if (display != null) {
        c.gtk_style_context_add_provider_for_display(display, @as(*c.GtkStyleProvider, @ptrCast(css_provider)), c.GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
        std.debug.print("CSS loaded and applied to display\n", .{});
    } else {
        std.debug.print("Error: Default display not available\n", .{});
    }
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

            c.gtk_widget_show(list_item);
        }
        c.gtk_entry_buffer_set_text(buffer, "", 0);
    } else {
        std.debug.print("No text entered\n", .{});
        c.gtk_label_set_text(main_window.label, "No table name entered");
    }

    c.gtk_entry_buffer_set_text(c.gtk_entry_get_buffer(main_window.entry), "", 0);
}

// fn handyFuncGetType() void {
// const widget_type = c.G_OBJECT_TYPE(item);
// const type_name = c.g_type_name(widget_type);
// std.debug.print("Widget type: {s}\n", .{type_name});
//
// var text_c: ?[*:0]const u8 = null;
//
// if (c.g_type_is_a(widget_type, c.gtk_label_get_type()) != 0) {
//     text_c = c.gtk_label_get_text(@ptrCast(item));
// } else if (c.g_type_is_a(widget_type, c.gtk_button_get_type()) != 0) {
//     text_c = c.gtk_button_get_label(@ptrCast(item));
// } else if (c.g_type_is_a(widget_type, c.gtk_entry_get_type()) != 0) {
//     text_c = c.gtk_editable_get_text(@ptrCast(item));
// } else {
//     std.debug.print("Unsupported widget type: {s}\n", .{type_name});
//     return;
// }
// }

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
