{pkgs ? import <nixpkgs> {}}:
pkgs.mkShell {
  buildInputs = with pkgs; [
    # GTK and its dependencies
    gtk4
    glib
    pango
    cairo
    graphene
    gdk-pixbuf

    # Development tools
    pkg-config
    gnumake
    gdb
    valgrind

    # Optional: GCC for any C compilation needs
    gcc
    awscli2
  ];

  shellHook = ''
    echo "GTK development environment loaded"
    echo "Zig version: $(zig version)"
    echo "GTK4 version: $(pkg-config --modversion gtk4)"
  '';

  # Set up PKG_CONFIG_PATH to find GTK
  # PKG_CONFIG_PATH = "${pkgs.gtk4}/lib/pkgconfig";
}
