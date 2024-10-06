{pkgs ? import <nixpkgs> {}}:
pkgs.mkShell {
  buildInputs = with pkgs; [
    # GTK and its dependencies
    libadwaita
    gtk4
    glib
    pango
    cairo
    graphene
    gdk-pixbuf
    pkg-config
    gtk-mac-integration
    sqlite
    darwin.apple_sdk.frameworks.Cocoa
  ];
  shellHook = ''
    unset NIX_CFLAGS_COMPILE
    unset NIX_LDFLAGS
    export GTK_MAC_INTEGRATION_CFLAGS=$(pkg-config --cflags gtk-mac-integration-gtk4)
    export GTK_MAC_INTEGRATION_LIBS=$(pkg-config --libs gtk-mac-integration-gtk4)
  '';
}
