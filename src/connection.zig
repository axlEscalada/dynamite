const std = @import("std");
const sqlite = @import("sqlite");
const builtin = @import("builtin");

const c = @cImport({
    @cInclude("sqlite3.h");
});

const Connection = struct {
    id: []const u8,
    name: []const u8,
    access_key: []const u8,
    secret_key: []const u8,
    session_token: ?[]const u8,
    region: ?[]const u8,
    url: []const u8,
};

pub const DbManager = struct {
    db: ?*c.sqlite3 = null,
    allocator: std.mem.Allocator,

    pub fn init(alloc: std.mem.Allocator) DbManager {
        return DbManager{
            .allocator = alloc,
        };
    }

    pub fn initDB(self: *DbManager) !void {
        const db_dir = try self.getDbPath();
        defer self.allocator.free(db_dir);

        std.fs.makeDirAbsolute(db_dir) catch |err| {
            if (err != error.PathAlreadyExists) return err;
        };

        const db_path = try std.fmt.allocPrint(self.allocator, "{s}/database.db", .{db_dir});
        defer self.allocator.free(db_path);

        std.debug.print("Using database path: {s}\n", .{db_path});

        const path_z = try self.allocator.dupeZ(u8, db_path);
        defer self.allocator.free(path_z);

        const flags: c_int = c.SQLITE_OPEN_READWRITE | c.SQLITE_OPEN_CREATE;

        const result = c.sqlite3_open_v2(path_z.ptr, &self.db, flags, null);
        if (result != c.SQLITE_OK) {
            const err_msg = if (self.db) |db|
                std.mem.span(c.sqlite3_errmsg(db))
            else
                "Could not allocate memory";

            std.debug.print("SQLite error ({d}): {s}\n", .{ result, err_msg });

            if (self.db) |db| {
                _ = c.sqlite3_close(db);
                self.db = null;
            }

            return error.SQLiteOpenError;
        }

        std.debug.print("Successfully opened database\n", .{});

        const query =
            \\CREATE TABLE IF NOT EXISTS connections (
            \\  id INTEGER PRIMARY KEY,
            \\  name TEXT NOT NULL,
            \\  access_key TEXT NOT NULL,
            \\  secret_key TEXT NOT NULL,
            \\  session_token TEXT,
            \\  region TEXT,
            \\  url TEXT
            \\);
        ;

        var err_msg: [*c]u8 = undefined;
        const exec_result = c.sqlite3_exec(self.db.?, query.ptr, null, null, &err_msg);

        if (exec_result != c.SQLITE_OK) {
            std.debug.print("SQL error: {s}\n", .{std.mem.span(err_msg)});
            c.sqlite3_free(err_msg);
            return error.SQLiteExecuteError;
        }

        std.debug.print("Database initialization complete\n", .{});
    }

    pub fn insertConnection(self: *DbManager, name: [*:0]const u8, access_key: [*:0]const u8, secret_key: [*:0]const u8, session_token: [*:0]const u8, region: [*:0]const u8, url: [*:0]const u8) !void {
        std.debug.print("name: {s} | access_key: {s} | secret_key: {s} | session_token: {s} | region: {s} | url: {s}\n", .{ name, access_key, secret_key, session_token, region, url });

        const query = "INSERT INTO connections (name, access_key, secret_key, session_token, region, url) VALUES (?, ?, ?, ?, ?, ?)";
        const stmt = blk: {
            var tmp: ?*c.sqlite3_stmt = undefined;
            const result = c.sqlite3_prepare_v3(
                self.db,
                query.ptr,
                @intCast(query.len),
                0,
                &tmp,
                null,
            );

            std.debug.print("Result status num: {any}\n", .{result});
            if (result != c.SQLITE_OK) {
                std.log.err("Error preparing query\n", .{});
                return;
            }
            break :blk tmp.?;
        };
        defer _ = c.sqlite3_finalize(stmt);

        if (c.sqlite3_bind_text(stmt, 1, name, -1, c.SQLITE_STATIC) != c.SQLITE_OK or
            c.sqlite3_bind_text(stmt, 2, access_key, -1, c.SQLITE_STATIC) != c.SQLITE_OK or
            c.sqlite3_bind_text(stmt, 3, secret_key, -1, c.SQLITE_STATIC) != c.SQLITE_OK or
            c.sqlite3_bind_text(stmt, 4, session_token, -1, c.SQLITE_STATIC) != c.SQLITE_OK or
            c.sqlite3_bind_text(stmt, 5, region, -1, c.SQLITE_STATIC) != c.SQLITE_OK or
            c.sqlite3_bind_text(stmt, 6, url, -1, c.SQLITE_STATIC) != c.SQLITE_OK)
        {
            return error.SQLiteBindError;
        }

        if (c.sqlite3_step(stmt) != c.SQLITE_DONE) {
            return error.SQLiteExecuteError;
        }
    }

    fn findConnections(self: DbManager) ![]Connection {
        const query = "SELECT id, name, access_key, secret_key, session_token, region, url FROM connections";
        const stmt = blk: {
            var tmp: ?*c.sqlite3_stmt = undefined;
            const result = c.sqlite3_prepare_v3(
                self.db,
                query.ptr,
                @intCast(query.len),
                0,
                &tmp,
                null,
            );

            if (result != c.SQLITE_OK) {
                std.log.err("Error preparing query\n", .{});
                return;
            }
            break :blk tmp.?;
        };
        defer _ = c.sqlite3_finalize(stmt);

        var connections = std.ArrayList(Connection).init(self.allocator);

        while (true) {
            const step_result = c.sqlite3_step(stmt);

            if (step_result == c.SQLITE_DONE) break;

            if (step_result != c.SQLITE_ROW) {
                const err_msg = c.sqlite3_errmsg(self.db.?);

                std.log.err("Error while retrieving connections: {s}", .{err_msg});
                return error.SQLiteStepError;
            }

            const id = c.sqlite3_column_int64(stmt.?, 0);

            const name_item = c.sqlite3_column_text(stmt.?, 1);
            const name = try self.allocator.dupe(u8, std.mem.span(name_item));

            const access_key_item = c.sqlite3_column_text(stmt.?, 2);
            const access_key = try self.allocator.dupe(u8, std.mem.span(access_key_item));

            const secret_key_item = c.sqlite3_column_text(stmt.?, 3);
            const secret_key = try self.allocator.dupe(u8, std.mem.span(secret_key_item));

            const session_token_item = c.sqlite3_column_text(stmt.?, 4);
            const session_token = try self.allocator.dupe(u8, std.mem.span(session_token_item));

            const region_item = c.sqlite3_column_text(stmt.?, 5);
            const region = try self.allocator.dupe(u8, std.mem.span(region_item));

            const url_item = c.sqlite3_column_text(stmt.?, 6);
            const url = try self.allocator.dupe(u8, std.mem.span(url_item));

            const connection = Connection{
                .id = id,
                .name = name,
                .access_key = access_key,
                .secret_key = secret_key,
                .session_token = session_token,
                .region = region,
                .url = url,
            };

            try connections.append(connection);
        }
        return try connections.toOwnedSlice();
    }

    fn getDbPath(self: *DbManager) ![]const u8 {
        return switch (builtin.target.os.tag) {
            .macos => {
                const home = std.posix.getenv("HOME") orelse return error.HomeNotFound;
                return try std.fmt.allocPrint(self.allocator, "{s}/Library/Application Support/Dynamite", .{home});
            },
            .linux => {
                const xdg_data = std.posix.getenv("XDG_DATA_HOME");
                if (xdg_data) |dir| {
                    return try std.fmt.allocPrint(self.allocator, "{s}/Dynamite", .{dir});
                }
                const home = std.posix.getenv("HOME") orelse return error.HomeNotFound;
                return try std.fmt.allocPrint(self.allocator, "{s}/.local/share/Dynamite", .{home});
            },
            else => return error.UnsupportedOS,
        };
    }
};
