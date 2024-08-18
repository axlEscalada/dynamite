const std = @import("std");
const Allocator = std.mem.Allocator;
const json = std.json;
const ArrayList = std.ArrayList;

pub const DynamoDBScanRequest = struct {
    TableName: []const u8,
    IndexName: ?[]const u8 = null,
    // AttributesToGet: ?[]const []const u8 = null,
    Limit: ?u32 = null,
    // Select: ?[]const u8 = null,
    // ScanFilter: ?std.StringHashMap(FilterCondition) = null,
    // ConditionalOperator: ?[]const u8 = null,
    // ExclusiveStartKey: ?std.StringHashMap(AttributeValue) = null,
    ReturnConsumedCapacity: ?[]const u8 = null,
    // TotalSegments: ?u32 = null,
    // Segment: ?u32 = null,
    // ProjectionExpression: ?[]const u8 = null,
    // FilterExpression: ?[]const u8 = null,
    // ExpressionAttributeNames: ?std.StringHashMap([]const u8) = null,
    // ExpressionAttributeValues: ?std.StringHashMap(AttributeValue) = null,
    // ConsistentRead: ?bool = null,
    //
    // pub const FilterCondition = struct {
    //     ComparisonOperator: []const u8,
    //     AttributeValueList: ?[]AttributeValue = null,
    // };
    //
    // pub const AttributeValue = union(enum) {
    //     S: []const u8,
    //     N: []const u8,
    //     B: []const u8,
    //     SS: []const []const u8,
    //     NS: []const []const u8,
    //     BS: []const []const u8,
    //     M: std.StringHashMap(AttributeValue),
    //     L: []AttributeValue,
    //     NULL: bool,
    //     BOOL: bool,
    // };
};

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

pub const ListTablesResponse = struct {
    TableNames: ArrayList([]const u8),
    LastEvaluatedTableName: ?[]const u8 = null,

    ///"Override" jsonParse, this is used by std.json when it read fields from the struct
    pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: json.ParseOptions) !ListTablesResponse {
        std.debug.print("parse options {any}\n", .{options});
        const ParsedResponse = struct {
            TableNames: [][]const u8,
            LastEvaluatedTableName: ?[]const u8 = null,
        };

        var parsed = try std.json.parseFromTokenSource(ParsedResponse, allocator, source, options);
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
        for (self.TableNames.items) |name| {
            allocator.free(name);
        }
        self.TableNames.deinit();
        if (self.LastEvaluatedTableName) |name| {
            allocator.free(name);
        }
    }

    pub fn copy(self: ListTablesResponse, allocator: std.mem.Allocator) !ListTablesResponse {
        var new_table_names = try ArrayList([]const u8).initCapacity(allocator, self.TableNames.items.len);
        errdefer new_table_names.deinit();

        for (self.TableNames.items) |name| {
            const new_name = try allocator.dupe(u8, name);
            errdefer allocator.free(new_name);
            try new_table_names.append(new_name);
        }

        var new_last_evaluated_table_name: ?[]const u8 = null;
        if (self.LastEvaluatedTableName) |last_name| {
            new_last_evaluated_table_name = try allocator.dupe(u8, last_name);
        }

        return ListTablesResponse{
            .TableNames = new_table_names,
            .LastEvaluatedTableName = new_last_evaluated_table_name,
        };
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

pub const DynamoDBAttributeValue = struct {
    value: union(enum) {
        S: []const u8,
        N: []const u8,
        BOOL: bool,
    },

    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        switch (self.value) {
            .S => allocator.free(self.value.S),
            .N => allocator.free(self.value.N),
            else => {},
        }
    }

    pub fn jsonParse(
        allocator: std.mem.Allocator,
        source: std.json.Value,
        options: std.json.ParseOptions,
    ) !@This() {
        _ = options;
        switch (source) {
            .object => |obj| {
                if (obj.get("S")) |s| {
                    return .{ .value = .{ .S = try allocator.dupe(u8, s.string) } };
                } else if (obj.get("N")) |n| {
                    return .{ .value = .{ .N = try allocator.dupe(u8, n.string) } };
                } else if (obj.get("BOOL")) |b| {
                    return .{ .value = .{ .BOOL = b.bool } };
                }
                return error.UnexpectedToken;
            },
            else => return error.UnexpectedToken,
        }
    }
};

pub fn ScanResponse(comptime T: type) type {
    return struct {
        const Self = @This();

        Items: []T,
        Count: usize,
        ScannedCount: usize,
        LastEvaluatedKey: ?std.StringHashMap(DynamoDBAttributeValue),

        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            allocator.free(self.Items);
            if (self.LastEvaluatedKey) |*key| {
                var it = key.iterator();
                while (it.next()) |entry| {
                    entry.value_ptr.deinit(allocator);
                }
                key.deinit();
            }
        }

        pub fn jsonParse(
            allocator: std.mem.Allocator,
            source: anytype,
            options: std.json.ParseOptions,
        ) !Self {
            var parsed = try std.json.parseFromTokenSource(std.json.Value, allocator, source, options);
            defer parsed.deinit();

            if (parsed.value != .object) return error.UnexpectedToken;

            var result: Self = undefined;

            if (parsed.value.object.get("Items")) |items_value| {
                if (items_value != .array) return error.UnexpectedToken;
                result.Items = try allocator.alloc(T, items_value.array.items.len);
                for (items_value.array.items, 0..) |item, i| {
                    if (item != .object) return error.UnexpectedToken;
                    result.Items[i] = try parseItem(T, allocator, item.object, options);
                }
            } else {
                return error.MissingField;
            }

            if (parsed.value.object.get("Count")) |count_value| {
                const rs = try std.json.parseFromValue(usize, allocator, count_value, options);
                result.Count = rs.value;
            } else {
                return error.MissingField;
            }

            if (parsed.value.object.get("ScannedCount")) |scanned_count_value| {
                std.debug.print("Scanned count {any}\n", .{scanned_count_value});
                const rs = try std.json.parseFromValue(usize, allocator, scanned_count_value, options);
                result.ScannedCount = rs.value;
            } else {
                return error.MissingField;
            }

            if (parsed.value.object.get("LastEvaluatedKey")) |last_key_value| {
                std.debug.print("Last value key {any}\n", .{last_key_value});
                if (last_key_value != .null) {
                    if (last_key_value != .object) return error.UnexpectedToken;
                    result.LastEvaluatedKey = std.StringHashMap(DynamoDBAttributeValue).init(allocator);
                    var it = last_key_value.object.iterator();
                    while (it.next()) |entry| {
                        try result.LastEvaluatedKey.?.put(entry.key_ptr.*, try DynamoDBAttributeValue.jsonParse(allocator, entry.value_ptr.*, options));
                    }
                }
            } else {
                result.LastEvaluatedKey = null;
            }

            return result;
        }

        fn parseItem(
            comptime ItemType: type,
            allocator: std.mem.Allocator,
            object: std.json.ObjectMap,
            options: std.json.ParseOptions,
        ) !ItemType {
            var result: ItemType = undefined;

            if (ItemType == []const u8) {
                var string_buffer = std.ArrayList(u8).init(allocator);
                defer string_buffer.deinit();
                const json_object = std.json.Value{ .object = object };
                const stringify_options = std.json.StringifyOptions{
                    .whitespace = .indent_2,
                    .emit_null_optional_fields = false,
                };
                try std.json.stringify(json_object, stringify_options, string_buffer.writer());

                std.debug.print("JSON string: {s}\n", .{string_buffer.items});
                return try allocator.dupe(u8, string_buffer.items);
            } else {
                inline for (std.meta.fields(ItemType)) |field| {
                    if (object.get(field.name)) |value| {
                        var attr = try DynamoDBAttributeValue.jsonParse(allocator, value, options);
                        defer attr.deinit(allocator);

                        @field(result, field.name) = switch (field.type) {
                            []const u8 => try allocator.dupe(u8, attr.value.S),
                            usize, u64, u32, u16, u8 => try std.fmt.parseInt(field.type, attr.value.N, 10),
                            bool => attr.value.BOOL,
                            else => @compileError("Unsupported field type: " ++ @typeName(field.type)),
                        };
                    } else {
                        return error.MissingField;
                    }
                }
            }

            return result;
        }
    };
}

test "deserialize scan response" {
    const json_string =
        \\{
        \\  "Items": [
        \\    {
        \\      "id": {"N": "1"},
        \\      "name": {"S": "Item 1"},
        \\      "is_active": {"BOOL": true}
        \\    },
        \\    {
        \\      "id": {"N": "2"},
        \\      "name": {"S": "Item 2"},
        \\      "is_active": {"BOOL": false}
        \\    }
        \\  ],
        \\  "Count": 2,
        \\  "ScannedCount": 2,
        \\  "LastEvaluatedKey": null
        \\}
    ;

    const MyItem = struct {
        id: u64,
        name: []const u8,
        is_active: bool,
    };
    const allocator = std.testing.allocator;

    var response = try std.json.parseFromSlice(ScanResponse(MyItem), allocator, json_string, .{ .ignore_unknown_fields = true });
    defer response.deinit();

    for (response.value.Items) |item| {
        std.debug.print("ID: {d}, Name: {s}, Active: {}\n", .{ item.id, item.name, item.is_active });
    }
}

test "deserialize scan response as string" {
    const json_string =
        \\{
        \\  "Items": [
        \\    {
        \\      "id": {"N": "1"},
        \\      "name": {"S": "Item 1"},
        \\      "is_active": {"BOOL": true}
        \\    },
        \\    {
        \\      "id": {"N": "2"},
        \\      "name": {"S": "Item 2"},
        \\      "is_active": {"BOOL": false}
        \\    }
        \\  ],
        \\  "Count": 2,
        \\  "ScannedCount": 2,
        \\  "LastEvaluatedKey": null
        \\}
    ;

    const allocator = std.testing.allocator;

    var response = try std.json.parseFromSlice(ScanResponse([]const u8), allocator, json_string, .{ .ignore_unknown_fields = true });
    defer response.deinit();

    const expected = [_][]const u8{
        \\    {
        \\      "id": {"N": "1"},
        \\      "name": {"S": "Item 1"},
        \\      "is_active": {"BOOL": true}
        \\    },
        ,
        \\    {
        \\      "id": {"N": "2"},
        \\      "name": {"S": "Item 2"},
        \\      "is_active": {"BOOL": false}
        \\    }
    };
    for (response.value.Items, 0..) |item, i| {
        std.debug.print("Item {s}", .{item});
        try std.testing.expectEqualStrings(expected[i], item);
    }
}

test "scan request" {
    const scan_request = DynamoDBScanRequest{
        .TableName = "MyTable",
        .Limit = 10,
        // .FilterExpression = "Age > :min_age",
        // .ExpressionAttributeValues = std.StringHashMap(DynamoDBScanRequest.AttributeValue).init(std.testing.allocator),
    };
    // defer scan_request.ExpressionAttributeValues.?.deinit();

    // try scan_request.ExpressionAttributeValues.?.put(":min_age", .{ .N = "18" });

    var json_string = std.ArrayList(u8).init(std.testing.allocator);
    defer json_string.deinit();

    try std.json.stringify(scan_request, .{ .emit_null_optional_fields = false }, json_string.writer());
    std.debug.print("JSON: {s}\n", .{json_string.items});
}

test "deserialize list tables response" {
    const response =
        \\{"TableNames": ["Albums", "Animals", "Countries"]}
    ;
    const parsed = try std.json.parseFromSlice(ListTablesResponse, std.heap.page_allocator, response, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });

    defer parsed.deinit();

    try std.testing.expectEqual(parsed.value.TableNames.items.len, 3);
    try std.testing.expectEqualStrings(parsed.value.TableNames.items[0], "Albums");
    try std.testing.expectEqual(parsed.value.LastEvaluatedTableName, null);
}
