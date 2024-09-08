{pkgs ? import <nixpkgs> {}}: let
  # Create a custom GTK4 derivation that includes GDK Quartz backend
  gtk4WithQuartz = pkgs.gtk4.overrideAttrs (oldAttrs: {
    configureFlags =
      (oldAttrs.configureFlags or [])
      ++ [
        "--enable-quartz-backend"
      ];
  });
in
  pkgs.mkShell {
    buildInputs = with pkgs; [
      # GTK and its dependencies
      gtk4WithQuartz
      # gtk4
      glib
      pango
      cairo
      graphene
      gdk-pixbuf
      pkg-config
      gtk-mac-integration
      libadwaita
      darwin.apple_sdk.frameworks.Cocoa
    ];
    shellHook = ''
      unset NIX_CFLAGS_COMPILE
      unset NIX_LDFLAGS
      export PKG_CONFIG_PATH="${gtk4WithQuartz}/lib/pkgconfig:$PKG_CONFIG_PATH"
      export GTK_MAC_INTEGRATION_CFLAGS=$(pkg-config --cflags gtk-mac-integration-gtk4)
      export GTK_MAC_INTEGRATION_LIBS=$(pkg-config --libs gtk-mac-integration-gtk4)
    '';
  }
