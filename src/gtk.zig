const c = @cImport({
    @cInclude("gtk/gtk.h");
});
const std = @import("std");

pub fn GTK_TYPE_HEADER_BAR() c.GType {
    return c.gtk_header_bar_get_type();
}

pub fn GTK_TYPE_WINDOW() c.GType {
    return c.gtk_window_get_type();
}

pub fn GTK_WINDOW(ip: *c.GTypeInstance) *c.GtkWindow {
    return @as(*c.GtkWindow, @ptrCast(c.g_type_check_instance_cast(ip, GTK_TYPE_WINDOW())));
}

pub fn GTK_HEADER_BAR(ip: *c.GTypeInstance) *c.GtkHeaderBar {
    return @as(*c.GtkHeaderBar, @ptrCast(c.g_type_check_instance_cast(ip, GTK_TYPE_HEADER_BAR())));
}

//workaround for macos that is not drawing a box in the stack when "row-selected" is signaled until the mouse is moved, the selection
//with the keyboard is working though.
//Based on this test function:
//c.gtk_test_widget_wait_for_draw(@ptrCast(main_window.window));
pub fn proccessPendingEvents() void {
    var iteration_count: usize = 0;
    while (c.g_main_context_iteration(null, @as(c.gboolean, 0)) != 0) {
        iteration_count += 1;

        // Get the current source
        const current_source = c.g_main_current_source();
        if (current_source != null) {
            const source_id = c.g_source_get_id(current_source);
            const source_name = c.g_source_get_name(current_source);

            std.debug.print("Iteration {d}: Processing source ID: {d}, Name: {s}\n", .{ iteration_count, source_id, if (source_name != null) std.mem.span(source_name.?) else "Unknown" });

            // Additional logging for specific source types
            if (c.g_source_get_context(current_source) != null) {
                std.debug.print("  - Source has an associated GMainContext\n", .{});
            }

            const priority = c.g_source_get_priority(current_source);
            std.debug.print("  - Priority: {d}\n", .{priority});

            if (c.g_source_is_destroyed(current_source) != 0) {
                std.debug.print("  - Source is marked as destroyed\n", .{});
            }
        } else {
            std.debug.print("Iteration {d}: No current source available\n", .{iteration_count});
        }
    }
    std.debug.print("Total iterations: {d}\n", .{iteration_count});
}

pub fn handyFuncGetType(item: *c.GtkWidget) void {
    const widget_type = c.G_OBJECT_TYPE(item);
    const type_name = c.g_type_name(widget_type);
    std.debug.print("Widget type: {s}\n", .{type_name});

    var text_c: ?[*:0]const u8 = null;
    if (c.g_type_is_a(widget_type, c.gtk_tree_view_get_type()) != 0) {
        std.debug.print("TreeView detected\n", .{});
    } else if (c.g_type_is_a(widget_type, c.gtk_label_get_type()) != 0) {
        text_c = c.gtk_label_get_text(@ptrCast(item));
    } else if (c.g_type_is_a(widget_type, c.gtk_button_get_type()) != 0) {
        text_c = c.gtk_button_get_label(@ptrCast(item));
    } else if (c.g_type_is_a(widget_type, c.gtk_entry_get_type()) != 0) {
        text_c = c.gtk_editable_get_text(@ptrCast(item));
    } else {
        std.debug.print("Unsupported widget type: {s}\n", .{type_name});
        return;
    }
}
