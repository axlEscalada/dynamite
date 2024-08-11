const std = @import("std");
const http = std.http;
const json = std.json;
const ArrayList = std.ArrayList;

pub const KeySchemaElement = struct {
    AttributeName: [:0]const u8,
    KeyType: [:0]const u8,
};

pub const AttributeDefinition = struct {
    AttributeName: [:0]const u8,
    AttributeType: [:0]const u8,
};

pub const ProvisionedThroughput = struct {
    ReadCapacityUnits: u64,
    WriteCapacityUnits: u64,
};

pub const CreateTableRequest = struct {
    TableName: [:0]const u8,
    KeySchema: []const KeySchemaElement,
    AttributeDefinitions: []const AttributeDefinition,
    ProvisionedThroughput: ProvisionedThroughput,

    pub fn init(allocator: std.mem.Allocator, table_name: []const u8, key_name: []const u8) !CreateTableRequest {
        const table_name_sentinel = try allocator.dupeZ(u8, table_name);
        errdefer allocator.free(table_name_sentinel);

        const key_name_sentinel = try allocator.dupeZ(u8, key_name);
        errdefer allocator.free(key_name_sentinel);

        var key_schema = try allocator.alloc(KeySchemaElement, 1);
        errdefer allocator.free(key_schema);
        key_schema[0] = .{ .AttributeName = key_name_sentinel, .KeyType = try allocator.dupeZ(u8, "HASH") };

        var attribute_definitions = try allocator.alloc(AttributeDefinition, 1);
        errdefer allocator.free(attribute_definitions);
        attribute_definitions[0] = .{ .AttributeName = key_name_sentinel, .AttributeType = try allocator.dupeZ(u8, "S") };

        return CreateTableRequest{
            .TableName = table_name_sentinel,
            .KeySchema = key_schema,
            .AttributeDefinitions = attribute_definitions,
            .ProvisionedThroughput = .{
                .ReadCapacityUnits = 5,
                .WriteCapacityUnits = 5,
            },
        };
    }

    pub fn deinit(self: *CreateTableRequest, allocator: std.mem.Allocator) void {
        allocator.free(self.TableName);
        if (self.KeySchema.len > 0) {
            allocator.free(self.KeySchema[0].KeyType);
        }
        allocator.free(self.KeySchema);
        if (self.AttributeDefinitions.len > 0) {
            allocator.free(self.AttributeDefinitions[0].AttributeType);
            allocator.free(self.AttributeDefinitions[0].AttributeName);
        }
        allocator.free(self.AttributeDefinitions);
    }
};

const ListTablesResponse = struct {
    // TableNames: [][]const u8,
    TableNames: ArrayList([]const u8),
    LastEvaluatedTableName: ?[]const u8 = null,

    pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: json.ParseOptions) !ListTablesResponse {
        std.debug.print("parse options {any}\n", .{options});
        const ParsedResponse = struct {
            TableNames: [][]const u8,
            LastEvaluatedTableName: ?[]const u8 = null,
        };

        var parsed = try std.json.parseFromTokenSource(ParsedResponse, allocator, source, options);
        // var parsed = try std.json.parseFromTokenSource(ParsedResponse, allocator, source, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
        defer parsed.deinit();
        var table_names = ArrayList([]const u8).init(allocator);
        errdefer {
            for (table_names.items) |name| {
                allocator.free(name);
            }
            table_names.deinit();
        }

        try table_names.ensureTotalCapacity(parsed.value.TableNames.len);

        for (parsed.value.TableNames) |name| {
            const duped_name = try allocator.dupe(u8, name);
            try table_names.append(duped_name);
        }

        var last_evaluated_table_name: ?[]const u8 = null;
        if (parsed.value.LastEvaluatedTableName) |last_name| {
            last_evaluated_table_name = try allocator.dupe(u8, last_name);
        }

        return ListTablesResponse{
            .TableNames = table_names,
            .LastEvaluatedTableName = last_evaluated_table_name,
        };
    }

    pub fn deinit(self: *ListTablesResponse, allocator: std.mem.Allocator) void {
        std.debug.print("Deinitializing ListTablesResponse\n", .{});
        std.debug.print("TableNames length: {d}\n", .{self.TableNames.items.len});
        // for (self.TableNames.items, 0..) |name, i| {
        //     std.debug.print("Freeing table name {d}: {s}\n", .{ i, name });
        //     allocator.free(name);
        // }
        self.TableNames.deinit();
        if (self.LastEvaluatedTableName) |name| {
            std.debug.print("Freeing LastEvaluatedTableName: {s}\n", .{name});
            allocator.free(name);
        }
        std.debug.print("ListTablesResponse deinitialized\n", .{});
    }

    //
    // pub fn deinit(self: *ListTablesResponse, allocator: std.mem.Allocator) void {
    //     std.debug.print("Deinitializing ListTablesResponse\n", .{});
    //     std.debug.print("TableNames length: {d}\n", .{self.TableNames.len});
    //     for (self.TableNames, 0..) |name, i| {
    //         std.debug.print("Freeing table name {d}: {s}\n", .{ i, name });
    //         allocator.free(name);
    //     }
    //     std.debug.print("Freeing TableNames slice\n", .{});
    //     allocator.free(self.TableNames);
    //     if (self.LastEvaluatedTableName) |name| {
    //         std.debug.print("Freeing LastEvaluatedTableName: {s}\n", .{name});
    //         allocator.free(name);
    //     }
    //     std.debug.print("ListTablesResponse deinitialized\n", .{});
    // }
    // pub fn deinit(self: *ListTablesResponse, allocator: std.mem.Allocator) void {
    //     allocator.free(self.TableNames);
    //     if (self.LastEvaluatedTableName) |name| {
    //         allocator.free(name);
    //     }
    // }
};

const Item = struct { S: [:0]const u8 };

const DataType = enum {
    S,
    N,
    B,
    BOOL,
    NULL,
    M,
    L,
    SS,
    NS,
    BS,
};

pub const DataValue = struct {
    value: []const u8,
    data_type: DataType,
};

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
            .Limit = 100, // You can adjust this value as needed
            .ExclusiveStartTableName = null, // Start from the beginning
        };

        const json_str = try json.stringifyAlloc(self.allocator, payload, .{});
        defer self.allocator.free(json_str);

        // var response_buff: [1024]u8 = undefined;
        var response_buff = try self.allocator.alloc(u8, 4096);
        defer self.allocator.free(response_buff);
        const bytes_read = try self.sendRequest("POST", headers.items, json_str, response_buff);

        std.debug.print("response to parse response_buff[0..{d}]: {s}\n", .{ bytes_read, response_buff[0..bytes_read] });
        // var stream = json.Scanner.init(response_buff[0..bytes_read]);
        // const response = try std.json.parse(ListTablesResponse, &stream, .{
        //     .allocator = self.allocator,
        //     .ignore_unknown_fields = true,
        // });
        const response = try std.json.parseFromSlice(ListTablesResponse, self.allocator, response_buff[0..bytes_read], .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
        std.debug.print("Parsed {any}\n", .{response});
        return response.value;
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
                    // var response_body = try self.allocator.alloc(u8, len);
                    // defer self.allocator.free(response_body);
                    const bytes_read = try request.reader().readAll(response_buff.?);
                    std.debug.print("Response body: {s}\n", .{response_buff.?[0..bytes_read]});
                }
                return len;
            }
        }
        return 0;
    }
};

test "parse list tables" {
    const response =
        \\{"TableNames": ["Albums", "Animals", "Countries"]}
    ;
    const parsed = try std.json.parseFromSlice(ListTablesResponse, std.heap.page_allocator, response, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });

    defer parsed.deinit();

    try std.testing.expectEqual(parsed.value.TableNames.items.len, 3);
    try std.testing.expectEqualStrings(parsed.value.TableNames.items[0], "Albums");
    try std.testing.expectEqual(parsed.value.LastEvaluatedTableName, null);
}

test "list tables" {
    const allocator = std.testing.allocator;
    var client = try DynamoDbClient.init(allocator, "http://localhost:4566");
    defer client.deinit();

    var tables = try client.listTables();
    defer tables.deinit(allocator);

    // Now you can safely use the tables data
    std.debug.print("Tables: {any}\n", .{tables});

    for (tables.TableNames.items) |table_name| {
        std.debug.print("Table: {s}\n", .{table_name});
    }

    if (tables.LastEvaluatedTableName) |last_table| {
        std.debug.print("Last evaluated table: {s}\n", .{last_table});
    }
}
