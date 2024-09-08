#import <Cocoa/Cocoa.h>
#import <gtk/gtk.h>
#import <objc/runtime.h>

@interface CustomWindow : NSWindow
@property(nonatomic, strong) NSView *gtkContainerView;
@end

@implementation CustomWindow

+ (void)load {
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    Class cls = objc_getClass("CustomWindow");
    if (!cls) {
      cls = objc_allocateClassPair([NSWindow class], "CustomWindow", 0);
      objc_registerClassPair(cls);
    }
  });
}

- (instancetype)initWithContentRect:(NSRect)contentRect
                          styleMask:(NSWindowStyleMask)style
                            backing:(NSBackingStoreType)bufferingType
                              defer:(BOOL)flag {
  self = [super
      initWithContentRect:contentRect
                styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                          NSWindowStyleMaskMiniaturizable |
                          NSWindowStyleMaskResizable
                  backing:bufferingType
                    defer:flag];
  if (self) {
    [self setTitlebarAppearsTransparent:YES];
    [self setTitleVisibility:NSWindowTitleHidden];
    [self setStyleMask:[self styleMask] | NSWindowStyleMaskFullSizeContentView];

    NSView *contentView = [self contentView];
    NSView *titlebarView = [[NSView alloc]
        initWithFrame:NSMakeRect(0, contentRect.size.height - 40,
                                 contentRect.size.width, 40)];
    [titlebarView setWantsLayer:YES];
    titlebarView.layer.backgroundColor =
        [NSColor colorWithRed:0.2 green:0.2 blue:0.2 alpha:1.0].CGColor;

    NSTextField *titleField = [[NSTextField alloc]
        initWithFrame:NSMakeRect(70, 10, contentRect.size.width - 140, 20)];
    [titleField setStringValue:@"Dynamite"];
    [titleField setBezeled:NO];
    [titleField setDrawsBackground:NO];
    [titleField setEditable:NO];
    [titleField setSelectable:NO];
    [titleField setTextColor:[NSColor whiteColor]];
    [titleField setAlignment:NSTextAlignmentCenter];
    [titlebarView addSubview:titleField];

    [contentView addSubview:titlebarView];

    self.gtkContainerView =
        [[NSView alloc] initWithFrame:NSMakeRect(0, 0, contentRect.size.width,
                                                 contentRect.size.height - 40)];
    [contentView addSubview:self.gtkContainerView];
  }
  return self;
}

@end

void *createCustomWindow(const char *title, int width, int height) {
  NSRect frame = NSMakeRect(100, 100, width, height);
  CustomWindow *window =
      [[CustomWindow alloc] initWithContentRect:frame
                                      styleMask:NSWindowStyleMaskTitled
                                        backing:NSBackingStoreBuffered
                                          defer:NO];
  [window makeKeyAndOrderFront:nil];
  return (__bridge_retained void *)window;
}

void embedGtkInWindow(void *windowPtr, GtkWidget *gtkWidget) {
  CustomWindow *window = (__bridge CustomWindow *)windowPtr;
  NSView *containerView = window.gtkContainerView;

  GtkWidget *gtkWindow = gtk_window_new();
  gtk_window_set_child(GTK_WINDOW(gtkWindow), gtkWidget);

  gtk_widget_set_visible(gtkWidget, TRUE);
  gtk_widget_set_visible(gtkWindow, TRUE);

  // Get the GtkNative from the GtkWidget
  GtkNative *native = gtk_widget_get_native(gtkWindow);

  if (native) {
    // Get the NSView from the GtkNative
    NSView *gtkView = (__bridge NSView *)gtk_native_get_surface(native);

    if (gtkView) {
      [gtkView setFrame:[containerView bounds]];
      [gtkView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
      [containerView addSubview:gtkView];
    }
  }

  // Resize the GTK widget to match the container view
  NSSize size = [containerView frame].size;
  gtk_widget_set_size_request(gtkWindow, size.width, size.height);
}
