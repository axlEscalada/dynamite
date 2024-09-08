#ifndef CUSTOM_WINDOW_H
#define CUSTOM_WINDOW_H

#include <gtk/gtk.h>

void *createCustomWindow(const char *title, int width, int height);
void embedGtkInWindow(void *window, GtkWidget *gtkWidget);

#endif // CUSTOM_WINDOW_H
