const c = @cImport({
    @cInclude("gtk/gtk.h");
});

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
