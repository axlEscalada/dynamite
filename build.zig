const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addStaticLibrary(.{
        .name = "dynamodb-client",
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // This declares intent for the library to be installed into the standard
    // location when the user invokes the "install" step (the default step when
    // running `zig build`).
    b.installArtifact(lib);

    const exe = b.addExecutable(.{
        .name = "dynamodb-client",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    const zig_objc_dep = b.dependency("zig-objc", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("objc", zig_objc_dep.module("objc"));

    exe.linkSystemLibrary("gtk4");
    exe.linkSystemLibrary("glib-2.0");
    exe.linkSystemLibrary("gobject-2.0");
    exe.linkSystemLibrary("objc");
    exe.linkFramework("Cocoa");
    exe.linkFramework("Foundation");
    exe.linkFramework("AppKit");
    // exe.linkSystemLibrary("libadwaita-1");
    exe.linkLibC();

    // Add GTK4 package
    exe.addIncludePath(b.path("src"));
    exe.addIncludePath(b.path("gtk-4.0"));
    exe.addIncludePath(b.path("glib-2.0"));
    exe.addIncludePath(b.path("glib-2.0/include"));
    exe.addIncludePath(b.path("cairo"));
    exe.addIncludePath(b.path("pango-1.0"));
    exe.addIncludePath(b.path("harfbuzz"));
    exe.addIncludePath(b.path("gdk-pixbuf-2.0"));
    exe.addIncludePath(b.path("graphene-1.0"));

    const gtk_flags = [_][]const u8{
        "-I/nix/store/4c0qywz3jnrsfmqlii6lj3wmj5jnvflg-gtk4-4.14.3-dev/include/gtk-4.0",
        "-I/nix/store/4c0qywz3jnrsfmqlii6lj3wmj5jnvflg-gtk4-4.14.3-dev/include/glib-2.0",
        "-I/nix/store/4c0qywz3jnrsfmqlii6lj3wmj5jnvflg-gtk4-4.14.3-dev/lib/glib-2.0/include",
        "-I/nix/store/4c0qywz3jnrsfmqlii6lj3wmj5jnvflg-gtk4-4.14.3-dev/include/cairo",
        "-I/nix/store/4c0qywz3jnrsfmqlii6lj3wmj5jnvflg-gtk4-4.14.3-dev/include/pango-1.0",
        "-I/nix/store/4c0qywz3jnrsfmqlii6lj3wmj5jnvflg-gtk4-4.14.3-dev/include/harfbuzz",
        "-I/nix/store/4c0qywz3jnrsfmqlii6lj3wmj5jnvflg-gtk4-4.14.3-dev/include/gdk-pixbuf-2.0",
        "-I/nix/store/4c0qywz3jnrsfmqlii6lj3wmj5jnvflg-gtk4-4.14.3-dev/include/graphene-1.0",
        "-I/nix/store/4c0qywz3jnrsfmqlii6lj3wmj5jnvflg-gtk4-4.14.3-dev/include/gdk-4.0",
    };

    const objc_flags = [_][]const u8{ "-x", "objective-c", "-fobjc-arc" };
    exe.addCSourceFile(.{ .file = b.path("src/cocoa_titlebar.m"), .flags = &(objc_flags ++ gtk_flags) });

    // exe.addCSourceFile(.{ .file = b.path("src/cocoa_titlebar.m"), .flags = &[_][]const u8{
    //     "-framework",                        "Cocoa",
    //     "-fobjc-arc",                        "-I/usr/local/include/gtk-4.0",
    //     "-I/usr/local/include/glib-2.0",     "-I/usr/local/lib/glib-2.0/include",
    //     "-I/usr/local/include/cairo",        "-I/usr/local/include/pango-1.0",
    //     "-I/usr/local/include/harfbuzz",     "-I/usr/local/include/gdk-pixbuf-2.0",
    //     "-I/usr/local/include/graphene-1.0", "-Isrc",
    // } });

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(exe);

    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd = b.addRunArtifact(exe);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const lib_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
    test_step.dependOn(&run_exe_unit_tests.step);
}
