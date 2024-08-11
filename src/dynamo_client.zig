const std = @import("std");
const http = std.http;
const json = std.json;

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

        try self.sendRequest("POST", headers.items, json_str);
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

        try self.sendRequest("POST", headers.items, json_str.items);
    }

    fn sendRequest(self: *DynamoDbClient, comptime method: []const u8, headers: []http.Header, body: []const u8) !void {
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
                const response_body = try self.allocator.alloc(u8, len);
                defer self.allocator.free(response_body);
                _ = try request.reader().readAll(response_body);
                std.debug.print("Response body: {s}\n", .{response_body});
            }
            return error.HttpRequestFailed;
        }
    }
};
