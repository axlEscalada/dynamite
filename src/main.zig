const std = @import("std");
const c = @cImport({
    @cInclude("gtk/gtk.h");
});
const DynamoDbClient = @import("dynamo_client.zig").DynamoDbClient;
const DataValue = @import("dynamo_client.zig").DataValue;
const gtk = @import("gtk.zig");
const builtin = @import("builtin");
const ArrayList = std.ArrayList;
const StringHashMap = std.StringHashMap;
const AwsConfiguration = @import("dynamo_client.zig").Configuration;

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

var credentials: AwsConfiguration = undefined;
const URL_DYNAMO = "http://localhost:4566";
// const URL_DYNAMO = null;

fn activate(app: ?*c.GtkApplication, user_data: ?*anyopaque) callconv(.C) void {
    const region = std.posix.getenv("AWS_REGION");
    const access_key = std.posix.getenv("AWS_ACCESS_KEY_ID");
    const secret_access_key = std.posix.getenv("AWS_SECRET_ACCESS_KEY");
    const session_token = std.posix.getenv("AWS_SESSION_TOKEN");
    if (access_key) |ak| {
        std.debug.print("access_key {s}\n", .{ak});
    }
    if (session_token) |st| {
        std.debug.print("session {s}\n", .{st});
    }
    if (secret_access_key) |sc| {
        std.debug.print("secret {s}\n", .{sc});
    }

    if (region) |rg| {
        std.debug.print("region {s}", .{rg});
    }

    credentials = AwsConfiguration.init(region, access_key, secret_access_key, session_token);

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

    // Remove default titlebar
    // c.gtk_window_set_decorated(main_window.window, 0);

    // const header_bar = c.gtk_header_bar_new();
    // const title_label = c.gtk_label_new("Dynamite");
    // c.gtk_window_set_titlebar(gtk.GTK_WINDOW(@ptrCast(main_window.window)), header_bar);
    // c.gtk_header_bar_set_title_widget(gtk.GTK_HEADER_BAR(@ptrCast(header_bar)), title_label);
    // c.gtk_widget_add_css_class(@ptrCast(header_bar), "header");

    const main_box = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 10);
    c.gtk_widget_set_margin_start(@ptrCast(main_box), 10);
    c.gtk_widget_set_margin_end(@ptrCast(main_box), 10);
    c.gtk_widget_set_margin_top(@ptrCast(main_box), 10);
    c.gtk_widget_set_margin_bottom(@ptrCast(main_box), 10);

    //This view hold the tables listed on dynamo
    const scrolled_window = c.gtk_scrolled_window_new();
    c.gtk_scrolled_window_set_child(@ptrCast(scrolled_window), @alignCast(@ptrCast(main_window.list_box)));
    c.gtk_widget_set_vexpand(@ptrCast(scrolled_window), 1);

    const search_entry = c.gtk_search_entry_new();
    c.gtk_box_append(@ptrCast(main_box), @ptrCast(search_entry));

    c.gtk_list_box_set_filter_func(main_window.list_box, filterTableItems, search_entry, null);

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
    c.gtk_widget_add_css_class(@ptrCast(@alignCast(main_window.list_box)), "boxed-list");
    c.gtk_box_append(@ptrCast(create_box), @ptrCast(main_window.entry));
    c.gtk_box_append(@ptrCast(create_box), @alignCast(@ptrCast(main_window.label)));
    c.gtk_box_append(@ptrCast(create_box), @ptrCast(main_window.confirm_button));

    const table_scrolled_window = c.gtk_scrolled_window_new();
    c.gtk_scrolled_window_set_policy(@ptrCast(table_scrolled_window), c.GTK_POLICY_AUTOMATIC, c.GTK_POLICY_AUTOMATIC);

    const table_box = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 10);
    c.gtk_widget_set_margin_start(@ptrCast(table_box), 10);
    c.gtk_widget_set_margin_end(@ptrCast(table_box), 10);
    c.gtk_widget_set_margin_top(@ptrCast(table_box), 10);
    c.gtk_widget_set_margin_bottom(@ptrCast(table_box), 10);

    const table_name_label = c.gtk_label_new(null);
    c.gtk_box_append(@ptrCast(table_box), @ptrCast(table_name_label));

    const tree_view = c.gtk_tree_view_new();
    c.gtk_widget_add_css_class(@ptrCast(tree_view), "table-list");
    c.gtk_scrolled_window_set_child(@ptrCast(table_scrolled_window), @alignCast(@ptrCast(tree_view)));
    c.gtk_widget_set_vexpand(@ptrCast(table_scrolled_window), 1);
    c.gtk_box_append(@ptrCast(table_box), table_scrolled_window);

    _ = c.gtk_stack_add_named(main_window.stack, @ptrCast(main_box), "main");
    _ = c.gtk_stack_add_named(main_window.stack, @ptrCast(createViewWithBackButton(create_box)), "create");
    _ = c.gtk_stack_add_named(main_window.stack, @ptrCast(createViewWithBackButton(table_box)), "table");

    c.gtk_window_set_child(main_window.window, @alignCast(@ptrCast(main_window.stack)));

    _ = c.g_signal_connect_data(@ptrCast(main_window.create_button), "clicked", @ptrCast(&switchToCreateView), null, null, 0);
    _ = c.g_signal_connect_data(@ptrCast(main_window.confirm_button), "clicked", @ptrCast(&createTable), null, null, 0);
    // c.gtk_list_box_set_activate_on_single_click(main_window.list_box, 0);
    const table_view_data = global_allocator.create(TableViewData) catch |e| {
        std.log.err("Error creating TableViewData: {any}\n", .{e});
        return;
    };
    table_view_data.* = .{
        .tree_view = @ptrCast(tree_view),
        .table_name_label = @ptrCast(table_name_label),
    };
    _ = c.g_signal_connect_data(@ptrCast(main_window.list_box), "row-activated", @ptrCast(&switchToTableView), @ptrCast(table_view_data), null, c.G_CONNECT_AFTER);
    _ = c.g_signal_connect_data(@ptrCast(search_entry), "search-changed", @ptrCast(&searchEntryChanged), main_window.list_box, null, c.G_CONNECT_AFTER);

    var dynamo_client = DynamoDbClient.init(global_allocator, URL_DYNAMO, credentials) catch |e| {
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
        c.gtk_label_set_xalign(@ptrCast(list_item), 0.0);
        c.gtk_widget_set_halign(@ptrCast(list_item), c.GTK_ALIGN_START);
        c.gtk_list_box_insert(@ptrCast(main_window.list_box), list_item, -1);

        c.gtk_widget_show(list_item);
    }

    c.gtk_widget_show(@ptrCast(main_window.window));
}

fn filterTableItems(row: ?*c.GtkListBoxRow, user_data: ?*anyopaque) callconv(.C) c_int {
    const search_entry = @as(*c.GtkSearchEntry, @alignCast(@ptrCast(user_data)));
    const search_text = c.gtk_editable_get_text(@ptrCast(search_entry));

    const label = c.gtk_list_box_row_get_child(row);
    const item_text = c.gtk_label_get_text(@ptrCast(label));

    if (caseInsensitiveContains(item_text, search_text)) {
        return 1; // Show the item
    } else return 0; // Hide the item
}

fn caseInsensitiveContains(haystack: [*c]const u8, needle: [*c]const u8) bool {
    const haystack_lower = c.g_utf8_strdown(haystack, -1);
    defer c.g_free(haystack_lower);
    const needle_lower = c.g_utf8_strdown(needle, -1);
    defer c.g_free(needle_lower);

    var haystack_ptr = haystack_lower;
    const needle_len = c.g_utf8_strlen(needle_lower, -1);
    const haystack_len = c.g_utf8_strlen(haystack_lower, -1);

    var i: c.glong = 0;
    while (i <= haystack_len - needle_len) : (i += 1) {
        const substring = c.g_utf8_substring(haystack_ptr, 0, needle_len);
        defer c.g_free(substring);

        if (std.mem.eql(u8, std.mem.span(substring), std.mem.span(needle_lower))) {
            return true;
        }

        haystack_ptr = c.g_utf8_find_next_char(haystack_ptr, null);
    }

    return false;
}

fn searchEntryChanged(search_entry: *c.GtkSearchEntry, list_box: *c.GtkListBox) callconv(.C) void {
    _ = search_entry;
    c.gtk_list_box_invalidate_filter(list_box);
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

const TableViewData = struct {
    tree_view: *c.GtkTreeView,
    table_name_label: *c.GtkLabel,
};

fn switchToTableView(
    list_box: *c.GtkListBox,
    row: *c.GtkListBoxRow,
    user_data: ?*anyopaque,
) callconv(.C) void {
    _ = list_box;
    const data = @as(*TableViewData, @ptrCast(@alignCast(user_data)));
    const tree_view = data.tree_view;
    const table_name_label = data.table_name_label;
    var dynamo_client = DynamoDbClient.init(global_allocator, URL_DYNAMO, credentials) catch |e| {
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
    c.gtk_label_set_text(@ptrCast(table_name_label), table);
    // updateHeaderBoxTitle(main_window.stack.?, "table", table);

    var arena_allocator = std.heap.ArenaAllocator.init(global_allocator);
    defer arena_allocator.deinit();
    const response = dynamo_client.scanTable(arena_allocator.allocator(), []const u8, table) catch |err| {
        std.debug.print("Error scanning table: {}\n", .{err});
        return;
    };

    std.debug.print("Response: {s}\n", .{response.Items});
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var columnNames = ArrayList([]const u8).init(allocator);
    var rows = ArrayList(StringHashMap([]const u8)).init(allocator);

    for (response.Items) |json_str| {
        var json_tree = std.json.parseFromSlice(std.json.Value, allocator, json_str, .{}) catch |err| {
            std.log.err("Error parsing JSON: {any}\n", .{err});
            return;
        };
        defer json_tree.deinit();

        const root = json_tree.value;
        if (root != .object) continue;

        var r = StringHashMap([]const u8).init(allocator);

        var it = root.object.iterator();
        while (it.next()) |entry| {
            const key = entry.key_ptr.*;
            const value = entry.value_ptr.*;

            if (value != .object or !value.object.contains("S")) continue;

            const s_value = value.object.get("S").?.string;
            r.put(key, s_value) catch |err| {
                std.log.err("Error adding value: {any}\n", .{err});
                return;
            };

            if (!contains(columnNames, key)) {
                columnNames.append(key) catch |err| {
                    std.log.err("Error adding column name: {any}\n", .{err});
                    return;
                };
            }
        }

        rows.append(r) catch |err| {
            std.log.err("Error adding row: {any}\n", .{err});
            return;
        };
    }

    populateDetailTreeView(@ptrCast(tree_view), columnNames.items, rows.items) catch |e| {
        std.log.err("Error while populating column {any}\n", .{e});
        return;
    };

    c.gtk_stack_set_visible_child_name(main_window.stack, "table");
    //workaround for macOS
    if (builtin.target.os.tag == .macos) {
        gtk.proccessPendingEvents();
    }
}

fn contains(list: std.ArrayList([]const u8), item: []const u8) bool {
    for (list.items) |element| {
        if (std.mem.eql(u8, element, item)) {
            return true;
        }
    }
    return false;
}

fn populateDetailTreeView(tree_widget: ?*c.GtkWidget, column_names: [][]const u8, data: []StringHashMap([]const u8)) !void {
    const tree_view: *c.GtkTreeView = @alignCast(@ptrCast(tree_widget));
    c.gtk_widget_add_css_class(@ptrCast(tree_view), "table-list");
    c.gtk_tree_view_set_grid_lines(tree_view, c.GTK_TREE_VIEW_GRID_LINES_BOTH);
    const current_list = @as(?*c.GtkListStore, @alignCast(@ptrCast(c.gtk_tree_view_get_model(tree_view))));
    if (current_list) |list| {
        std.debug.print("Clearing list\n", .{});
        _ = c.gtk_list_store_clear(list);
    }

    while (c.gtk_tree_view_get_column(tree_view, 0)) |column| {
        _ = c.gtk_tree_view_remove_column(tree_view, column);
    }

    const col_types = try global_allocator.alloc(c.GType, column_names.len);
    defer global_allocator.free(col_types);
    for (col_types) |*col_type| {
        col_type.* = c.G_TYPE_STRING;
    }
    const n_columns = @as(c_int, @intCast(column_names.len));
    const list_store = c.gtk_list_store_newv(n_columns, col_types.ptr);

    for (column_names, 0..) |name, i| {
        addTextColumn(tree_view, name, @as(c_int, @intCast(i)));
    }

    var iter: c.GtkTreeIter = undefined;
    for (data) |row| {
        _ = c.gtk_list_store_append(list_store, &iter);
        for (column_names, 0..) |column, i| {
            const value = row.get(column) orelse "";
            std.debug.print("Column {s} Value: {s}\n", .{ column, value });
            const c_string = try global_allocator.dupeZ(u8, value);
            defer global_allocator.free(c_string);

            _ = c.gtk_list_store_set(list_store, &iter, @as(c_int, @intCast(i)), c_string.ptr, @as(c_int, -1));
        }
    }
    c.gtk_tree_view_set_model(tree_view, @ptrCast(list_store));
}

fn updateHeaderBoxTitle(stack: *c.GtkStack, view_name: [*:0]const u8, new_title: [*:0]const u8) void {
    const view = c.gtk_stack_get_child_by_name(stack, view_name);
    if (view == null) return;

    const main_box = c.gtk_widget_get_first_child(@ptrCast(view));
    if (main_box == null) return;

    const header_box = c.gtk_widget_get_first_child(main_box);
    if (header_box == null) return;

    var header_box_title = c.gtk_widget_get_first_child(header_box);
    header_box_title = c.gtk_widget_get_next_sibling(header_box_title);

    const widget_type = c.G_OBJECT_TYPE(header_box_title);
    if (c.g_type_is_a(widget_type, c.gtk_label_get_type()) != 0) {
        c.gtk_label_set_text(@ptrCast(header_box_title), new_title);
    }
}

fn createViewWithBackButton(content: ?*c.GtkWidget) *c.GtkWidget {
    const main_box = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 0);
    const header_box = c.gtk_box_new(c.GTK_ORIENTATION_HORIZONTAL, 0);
    c.gtk_widget_set_margin_start(@ptrCast(header_box), 0);
    c.gtk_widget_set_margin_top(@ptrCast(header_box), 10);
    c.gtk_widget_set_margin_bottom(@ptrCast(header_box), 0);

    const back_button = createBackMainButton();
    const header_box_title = c.gtk_label_new("Replace with title");
    c.gtk_widget_set_hexpand(@ptrCast(header_box_title), 1);
    c.gtk_label_set_xalign(@ptrCast(header_box_title), 0.5);

    const spacer = c.gtk_box_new(c.GTK_ORIENTATION_HORIZONTAL, 0);
    c.gtk_widget_set_hexpand(@ptrCast(spacer), 0);

    c.gtk_box_append(@ptrCast(header_box), @ptrCast(back_button));
    c.gtk_box_append(@ptrCast(header_box), @ptrCast(header_box_title));
    c.gtk_box_append(@ptrCast(header_box), @ptrCast(spacer));

    c.gtk_box_set_homogeneous(@ptrCast(header_box), 1);
    c.gtk_box_append(@ptrCast(main_box), @ptrCast(header_box));

    if (content) |widget| {
        c.gtk_box_append(@ptrCast(main_box), widget);
    }

    return main_box;
}

fn createBackMainButton() *c.GtkWidget {
    const back_button = c.gtk_button_new_from_icon_name("go-previous-symbolic");
    // c.gtk_widget_add_css_class(@ptrCast(back_button), "back-button");
    c.gtk_widget_add_css_class(@ptrCast(back_button), "raised");
    c.gtk_widget_set_halign(@ptrCast(back_button), c.GTK_ALIGN_START);
    c.gtk_widget_set_valign(@ptrCast(back_button), c.GTK_ALIGN_START);
    c.gtk_widget_set_margin_start(@ptrCast(back_button), 10);
    c.gtk_widget_set_margin_top(@ptrCast(back_button), 0);
    _ = c.g_signal_connect_data(@ptrCast(back_button), "clicked", @ptrCast(&switchToMainView), null, null, 0);
    return back_button;
}

fn loadCss() void {
    const css_data = @embedFile("css/style.css");
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
    _ = user_data;
    _ = button;

    // updateHeaderBoxTitle(main_window.stack.?, "create", "Create Table");
    const buffer = c.gtk_entry_get_buffer(main_window.entry);
    const text = c.gtk_entry_buffer_get_text(buffer);
    if (text != null and c.gtk_entry_buffer_get_length(buffer) > 0) {
        const table_name = std.mem.span(text);

        var dynamo_client = DynamoDbClient.init(global_allocator, URL_DYNAMO, credentials) catch |e| {
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

        c.gtk_label_set_text(main_window.label, "Table created successfully");

        c.gtk_list_box_remove_all(main_window.list_box);
        var tables = dynamo_client.listTables() catch |e| {
            std.debug.print("Error listing tables {}", .{e});
            return;
        };
        defer tables.deinit(global_allocator);

        for (tables.TableNames.items) |table| {
            const c_table_name = global_allocator.dupeZ(u8, table) catch |e| {
                std.debug.print("Error duplicating table name: {}\n", .{e});
                return;
            };
            defer global_allocator.free(c_table_name);
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
//
//     defer item.deinit();
//     try item.put("id", .{ .data_type = .S, .value = "3" });
//     try item.put("name", .{ .data_type = .S, .value = "axl" });
//     try item.put("email", .{ .data_type = .S, .value = "axl@gmail.com" });
//
//     try client.putItem("Users", item);
//     std.debug.print("Item inserted successfully\n", .{});
// }
