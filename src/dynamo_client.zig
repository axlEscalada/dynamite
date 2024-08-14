const std = @import("std");
const http = std.http;
const json = std.json;
const ArrayList = std.ArrayList;
const DynamoDBScanRequest = @import("dynamo_types.zig").DynamoDBScanRequest;
const CreateTableRequest = @import("dynamo_types.zig").CreateTableRequest;
const ListTablesResponse = @import("dynamo_types.zig").ListTablesResponse;
const ScanResponse = @import("dynamo_types.zig").ScanResponse;
const DataValue = @import("dynamo_types.zig").DataValue;

pub const DynamoDbClient = struct {
    allocator: std.mem.Allocator,
    endpoint: []const u8,

    pub fn init(allocator: std.mem.Allocator, endpoint: []const u8) !DynamoDbClient {
        const owned_endpoint = try allocator.dupe(u8, endpoint);
        return DynamoDbClient{
            .allocator = allocator,
            .endpoint = owned_endpoint,
        };
    }

    pub fn deinit(self: *DynamoDbClient) void {
        self.allocator.free(self.endpoint);
    }

    // pub fn scanTable(self: *DynamoDbClient, table_name: []const u8) !ScanResponse {}

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

        _ = try self.sendRequest("POST", headers.items, json_str, null);
    }

    pub fn listTables(self: *DynamoDbClient) !ListTablesResponse {
        var headers = std.ArrayList(std.http.Header).init(self.allocator);
        defer headers.deinit();
        try headers.append(.{ .name = "Content-Type", .value = "application/json" });
        try headers.append(.{ .name = "X-Amz-Target", .value = "DynamoDB_20120810.ListTables" });

        const payload = .{
            .Limit = 100,
            .ExclusiveStartTableName = null,
        };

        const json_str = try json.stringifyAlloc(self.allocator, payload, .{});
        defer self.allocator.free(json_str);

        var response_buff = try self.allocator.alloc(u8, 4096);
        defer self.allocator.free(response_buff);
        const bytes_read = try self.sendRequest("POST", headers.items, json_str, response_buff);

        std.debug.print("response to parse response_buff[0..{d}]: {s}\n", .{ bytes_read, response_buff[0..bytes_read] });
        var parsed = try std.json.parseFromSlice(ListTablesResponse, self.allocator, response_buff[0..bytes_read], .{ .ignore_unknown_fields = true });
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

    fn sendRequest(self: *DynamoDbClient, comptime method: []const u8, headers: []http.Header, body: []const u8, response_buff: ?[]u8) !usize {
        var client = http.Client{ .allocator = self.allocator };
        defer client.deinit();
        const uri = try std.Uri.parse(self.endpoint);

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

        const status = request.response.status;
        if (status != .ok) {
            std.debug.print("Error: HTTP status {d}\n", .{@intFromEnum(status)});
            if (request.response.content_length) |len| {
                if (response_buff == null) {
                    const response_body = try self.allocator.alloc(u8, len);
                    defer self.allocator.free(response_body);
                    _ = try request.reader().readAll(response_body);
                    std.debug.print("Response body: {s}\n", .{response_body});
                } else {
                    var response_body = try self.allocator.alloc(u8, len);
                    defer self.allocator.free(response_body);
                    const bytes_read = try request.reader().readAll(response_body);
                    std.debug.print("Response body: {s}\n", .{response_body[0..bytes_read]});
                }
            }
            return error.HttpRequestFailed;
        } else if (status == .ok) {
            std.debug.print("Request succeeded\n", .{});

            if (request.response.content_length) |len| {
                if (response_buff == null) {
                    const response_body = try self.allocator.alloc(u8, len);
                    defer self.allocator.free(response_body);
                    _ = try request.reader().readAll(response_body);
                    std.debug.print("Null buff Response body: {s}\n", .{response_body});
                } else {
                    const bytes_read = try request.reader().readAll(response_buff.?);
                    std.debug.print("Response body: {s}\n", .{response_buff.?[0..bytes_read]});
                }
                return len;
            }
        }
        return 0;
    }
};

test "list tables" {
    const allocator = std.testing.allocator;
    var client = try DynamoDbClient.init(allocator, "http://localhost:4566");
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
