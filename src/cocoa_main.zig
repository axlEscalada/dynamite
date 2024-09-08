const std = @import("std");
const c = @cImport({
    @cInclude("gtk/gtk.h");
    @cInclude("cocoa_titlebar.h");
});

fn activate(app: *c.GtkApplication, user_data: ?*anyopaque) callconv(.C) void {
    _ = user_data;

    const window = c.gtk_application_window_new(app);
    c.gtk_window_set_title(@ptrCast(window), "Dynamite");
    c.gtk_window_set_default_size(@ptrCast(window), 800, 600);

    const main_box = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 0);
    c.gtk_widget_set_margin_start(main_box, 10);
    c.gtk_widget_set_margin_end(main_box, 10);
    c.gtk_widget_set_margin_top(main_box, 10);
    c.gtk_widget_set_margin_bottom(main_box, 10);

    const header_bar = c.gtk_header_bar_new();
    c.gtk_header_bar_set_show_title_buttons(@ptrCast(header_bar), 1);
    c.gtk_window_set_titlebar(@ptrCast(window), header_bar);

    const search_entry = c.gtk_search_entry_new();
    c.gtk_widget_set_hexpand(search_entry, 1);
    c.gtk_header_bar_pack_start(@ptrCast(header_bar), search_entry);

    const scroll_window = c.gtk_scrolled_window_new();
    c.gtk_widget_set_vexpand(scroll_window, 1);
    c.gtk_box_append(@ptrCast(main_box), scroll_window);

    const list_box = c.gtk_list_box_new();
    c.gtk_widget_add_css_class(list_box, "boxed-list");
    c.gtk_scrolled_window_set_child(@ptrCast(scroll_window), list_box);

    const items = [_][*c]const u8{
        "events-local-table",
        "fake-time-local-table",
        "pomigration-local-table",
        "pricing-local-table",
        "resources-local-table",
        "snapshots-local-table",
    };

    for (items) |item| {
        const row = c.gtk_list_box_row_new();
        const label = c.gtk_label_new(item);
        c.gtk_widget_set_margin_start(label, 5);
        c.gtk_widget_set_margin_end(label, 5);
        c.gtk_widget_set_margin_top(label, 5);
        c.gtk_widget_set_margin_bottom(label, 5);
        c.gtk_widget_set_halign(label, c.GTK_ALIGN_START);
        c.gtk_list_box_row_set_child(@ptrCast(row), label);
        c.gtk_list_box_insert(@ptrCast(list_box), row, -1);
    }

    c.gtk_window_set_child(@ptrCast(window), main_box);
    c.gtk_widget_show(window);
}

pub fn main() !void {
    const app = c.gtk_application_new("org.gtk.example", c.G_APPLICATION_FLAGS_NONE);
    defer c.g_object_unref(app);

    _ = c.g_signal_connect_data(app, "activate", @ptrCast(&activate), null, null, 0);

    const status = c.g_application_run(@ptrCast(app), 0, null);
    std.process.exit(@intCast(status));
}
