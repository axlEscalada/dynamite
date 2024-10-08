const std = @import("std");
const http = std.http;
const json = std.json;
const ArrayList = std.ArrayList;
const DynamoDBScanRequest = @import("dynamo_types.zig").DynamoDBScanRequest;
const CreateTableRequest = @import("dynamo_types.zig").CreateTableRequest;
const ListTablesResponse = @import("dynamo_types.zig").ListTablesResponse;
const ScanResponse = @import("dynamo_types.zig").ScanResponse;
const DataValue = @import("dynamo_types.zig").DataValue;
const null_writer = std.io.null_writer;
const DateTime = @import("date_time.zig").DateTime;
const dynamo_signature = @import("dynamo_signature.zig");
const DEFAULT_ENDPOINT = "https://dynamodb.us-east-1.amazonaws.com";
const GLOBAL_ENDPOINT = "https://dynamodb.{s}.amazonaws.com";
const DEFAULT_REGION = "us-east-1";

pub const Configuration = struct {
    region: []const u8,
    access_key: []const u8,
    secret_access_key: []const u8,
    session_token: ?[]const u8,

    pub fn init(region: ?[]const u8, access_key: ?[]const u8, secret_access_key: ?[]const u8, session_token: ?[]const u8) Configuration {
        return Configuration{
            .region = region orelse DEFAULT_REGION,
            .access_key = access_key orelse "",
            .secret_access_key = secret_access_key orelse "",
            .session_token = session_token,
        };
    }
};

pub const DynamoDbClient = struct {
    allocator: std.mem.Allocator,
    endpoint: []const u8,
    credentials: Configuration,

    pub fn init(allocator: std.mem.Allocator, endpoint: ?[]const u8, credentials: Configuration) !DynamoDbClient {
        const owned_endpoint: []const u8 = blk: {
            if (endpoint) |endpt| {
                break :blk try allocator.dupe(u8, endpt);
            }
            break :blk std.fmt.allocPrint(allocator, GLOBAL_ENDPOINT, .{credentials.region}) catch |e| {
                std.log.err("Error allocating endpoint {}\n", .{e});
                return e;
            };
        };

        std.debug.print("endpoint: {s}\n", .{owned_endpoint});

        return DynamoDbClient{
            .allocator = allocator,
            .endpoint = owned_endpoint,
            .credentials = credentials,
        };
    }

    pub fn deinit(self: *DynamoDbClient) void {
        self.allocator.free(self.endpoint);
    }

    pub fn scanTable(self: *DynamoDbClient, allocator: std.mem.Allocator, comptime T: type, table_name: []const u8) !ScanResponse(T) {
        var headers = std.ArrayList(std.http.Header).init(self.allocator);
        defer headers.deinit();
        try headers.append(.{ .name = "Content-Type", .value = "application/json" });
        try headers.append(.{ .name = "X-Amz-Target", .value = "DynamoDB_20120810.Scan" });

        const scan_request = DynamoDBScanRequest{
            .TableName = table_name,
            .Limit = 10,
        };

        var json_string = std.ArrayList(u8).init(self.allocator);
        defer json_string.deinit();

        try std.json.stringify(scan_request, .{ .emit_null_optional_fields = false }, json_string.writer());

        var writer = std.ArrayList(u8).init(allocator);
        defer writer.deinit();

        const sign_headers = try dynamo_signature.signRequest(allocator, "POST", "/", "", json_string.items, self.credentials.access_key, self.credentials.secret_access_key, self.credentials.session_token, null, headers.items, self.endpoint);
        try headers.appendSlice(sign_headers);

        const bytes_read = try self.sendRequest("POST", headers.items, json_string.items, writer.writer());

        std.debug.print("response to parse response_buff[0..{d}]: {s}\n", .{ bytes_read, writer.items });
        const parsed = try std.json.parseFromSlice(ScanResponse(T), allocator, writer.items, .{ .ignore_unknown_fields = true });
        defer parsed.deinit();

        return parsed.value;
    }

    pub fn createTable(self: *DynamoDbClient, table_name: []const u8, key_name: []const u8) !void {
        std.debug.print("allocator {any}\n", .{self.allocator});
        var headers = std.ArrayList(std.http.Header).init(self.allocator);
        defer headers.deinit();
        try headers.append(.{ .name = "Content-Type", .value = "application/json" });
        try headers.append(.{ .name = "X-Amz-Target", .value = "DynamoDB_20120810.CreateTable" });

        var request = try CreateTableRequest.init(self.allocator, table_name, key_name);
        defer request.deinit(self.allocator);

        const json_str = try json.stringifyAlloc(self.allocator, &request, .{});
        defer self.allocator.free(json_str);

        const sign_headers = try dynamo_signature.signRequest(self.allocator, "POST", "/", "", json_str, self.credentials.access_key, self.credentials.secret_access_key, self.credentials.session_token, null, headers.items, self.endpoint);
        try headers.appendSlice(sign_headers);

        _ = try self.sendRequest("POST", headers.items, json_str, null_writer);
    }

    pub fn listTables(self: *DynamoDbClient) !ListTablesResponse {
        var headers = std.ArrayList(std.http.Header).init(self.allocator);
        defer headers.deinit();
        try headers.append(.{ .name = "Content-Type", .value = "application/x-amz-json-1.0" });
        try headers.append(.{ .name = "X-Amz-Target", .value = "DynamoDB_20120810.ListTables" });

        const payload = .{
            .Limit = 100,
            .ExclusiveStartTableName = null,
        };
        const body = try json.stringifyAlloc(self.allocator, payload, .{});
        defer self.allocator.free(body);
        var arena_allocator = std.heap.ArenaAllocator.init(self.allocator);
        defer arena_allocator.deinit();

        const sign_headers = try dynamo_signature.signRequest(arena_allocator.allocator(), "POST", "/", "", body, self.credentials.access_key, self.credentials.secret_access_key, self.credentials.session_token, null, headers.items, self.endpoint);
        try headers.appendSlice(sign_headers);

        var writer = std.ArrayList(u8).init(self.allocator);
        defer writer.deinit();

        const bytes_read = try self.sendRequest("POST", headers.items, body, writer.writer());

        std.debug.print("response to parse response_buff[0..{d}]: {s}\n", .{ bytes_read, writer.items });
        var parsed = try std.json.parseFromSlice(ListTablesResponse, self.allocator, writer.items, .{ .ignore_unknown_fields = true });
        defer parsed.deinit();

        return try parsed.value.copy(self.allocator);
    }

    pub fn putItem(self: *DynamoDbClient, table_name: []const u8, item: std.StringHashMap(DataValue)) !void {
        var headers = std.ArrayList(http.Header).init(self.allocator);
        try headers.append(.{ .name = "Content-Type", .value = "application/json" });
        try headers.append(.{ .name = "X-Amz-Target", .value = "DynamoDB_20120810.PutItem" });
        defer headers.deinit();

        var json_str = std.ArrayList(u8).init(self.allocator);
        defer json_str.deinit();

        try json_str.appendSlice("{\"TableName\":\"");
        try json_str.appendSlice(table_name);
        try json_str.appendSlice("\",\"Item\":{");

        var it = item.iterator();
        var first = true;
        while (it.next()) |entry| {
            if (!first) {
                try json_str.appendSlice(",");
            }
            first = false;
            try json_str.appendSlice("\"");
            try json_str.appendSlice(entry.key_ptr.*);
            const data_type_enum = @tagName(entry.value_ptr.*.data_type);
            try json_str.appendSlice("\":{\"");
            try json_str.appendSlice(data_type_enum);
            try json_str.appendSlice("\":\"");
            try json_str.appendSlice(entry.value_ptr.*.value);
            try json_str.appendSlice("\"}");
        }

        try json_str.appendSlice("}}");

        _ = try self.sendRequest("POST", headers.items, json_str.items, null);
    }

    fn dumpMemory(ptr: [*]const u8, len: usize) void {
        std.debug.print("Memory dump at 0x{x}:\n", .{@ptrFromInt(ptr)});
        for (0..len) |i| {
            if (i % 16 == 0 and i != 0) std.debug.print("\n", .{});
            std.debug.print("{x:0>2} ", .{ptr[i]});
        }
        std.debug.print("\n", .{});
    }

    fn sendRequest(self: *DynamoDbClient, comptime method: []const u8, headers: []http.Header, body: []const u8, writer: anytype) !usize {
        var client = http.Client{ .allocator = self.allocator };
        defer client.deinit();
        const uri = try std.Uri.parse(self.endpoint);
        for (headers) |header| {
            std.debug.print("Header: {s}:{s}\n", .{ header.name, header.value });
        }

        var server_header: [1024]u8 = undefined;
        var request = try client.open(@field(http.Method, method), uri, .{ .server_header_buffer = &server_header, .extra_headers = headers });
        defer request.deinit();
        std.debug.print("server_header: {s}\n", .{server_header});
        std.debug.print("body: {s}\n", .{body});

        request.transfer_encoding = .{ .content_length = body.len };
        try request.send();
        try request.writeAll(body);

        try request.finish();
        try request.wait();

        const BUFFER_SIZE = 4096;
        var buffer: [BUFFER_SIZE]u8 = undefined;

        const status = request.response.status;
        var total_bytes: usize = 0;

        while (true) {
            const bytes_read = try request.reader().read(&buffer);
            if (bytes_read == 0) break;
            try writer.writeAll(buffer[0..bytes_read]);
            total_bytes += bytes_read;
        }
        if (status != .ok) {
            std.debug.print("Error: HTTP status {d}\n", .{@intFromEnum(status)});
            return error.HttpRequestFailed;
        }
        std.debug.print("Request succeeded\n", .{});
        return total_bytes;
    }
};

test "list tables" {
    const allocator = std.testing.allocator;
    const arena = std.heap.ArenaAllocator.init(allocator);
    arena.deinit();

    const AWS_ACCESS_KEY_ID = "test";
    const AWS_SECRET_ACCESS_KEY = "test";
    const AWS_SESSION_TOKEN: ?[]const u8 = null;
    const credentials = Configuration.init("us-east-1", AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_SESSION_TOKEN);
    var client = try DynamoDbClient.init(allocator, "http://localhost:4566", credentials);
    defer client.deinit();

    var tables = try client.listTables();
    defer tables.deinit(allocator);

    std.debug.print("Tables: {any}\n", .{tables});

    for (tables.TableNames.items) |table_name| {
        std.debug.print("Table: {s}\n", .{table_name});
    }

    if (tables.LastEvaluatedTableName) |last_table| {
        std.debug.print("Last evaluated table: {s}\n", .{last_table});
    }
}
