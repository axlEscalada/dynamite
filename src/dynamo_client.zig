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

pub const Credentials = struct {
    region: ?[:0]const u8,
    access_key: ?[:0]const u8,
    secret_access_key: ?[:0]const u8,
    session_token: ?[:0]const u8,
};

pub const DynamoDbClient = struct {
    allocator: std.mem.Allocator,
    endpoint: []const u8,
    region: []const u8,
    access_key_id: []const u8,
    secret_access_key: []const u8,

    pub fn init(allocator: std.mem.Allocator, endpoint: ?[]const u8, credentials: Credentials) !DynamoDbClient {
        const owned_region = blk: {
            if (credentials.region) |region| {
                break :blk try allocator.dupe(u8, region);
            }
            const region_from_sts = try getRegionFromSts(allocator, credentials.access_key.?[0..credentials.access_key.?.len], credentials.secret_access_key.?[0..credentials.secret_access_key.?.len], credentials.session_token.?[0..credentials.session_token.?.len]);
            break :blk region_from_sts;
        };
        const owned_endpoint: []const u8 = blk: {
            if (endpoint) |endpt| {
                break :blk try allocator.dupe(u8, endpt);
            }
            const endpoint_from_region = try std.fmt.allocPrint(allocator, "https://dynamodb.{s}.amazonaws.com", .{owned_region});
            break :blk endpoint_from_region;
        };
        const owned_access_key = try allocator.dupe(u8, credentials.access_key);
        const owned_secret_key = try allocator.dupe(u8, credentials.secret_access_key);
        return DynamoDbClient{
            .allocator = allocator,
            .endpoint = owned_endpoint,
            .region = owned_region,
            .access_key_id = owned_access_key,
            .secret_access_key = owned_secret_key,
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

        _ = try self.sendRequest("POST", headers.items, json_str, null_writer);
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
        const body = try json.stringifyAlloc(self.allocator, payload, .{});
        defer self.allocator.free(body);

        const uri = std.Uri.parse(self.endpoint);
        const timestamp = getIso8601Timestamp();
        const date = timestamp[0..8];
        const canonical_request = try self.createCanonicalRequest("POST", uri.path, headers, body, timestamp);
        const string_to_sign = try self.createStringToSign(date, self.region, "dynamodb", canonical_request);
        const signature = try self.calculateSignature(date, self.region, "dynamodb", string_to_sign);

        try headers.append(.{ .name = "Authorization", .value = try std.fmt.allocPrint(self.allocator, "AWS4-HMAC-SHA256 Credential={s}/{s}/{s}/dynamodb/aws4_request, SignedHeaders=host;x-amz-date, Signature={s}", .{ self.access_key_id, date, self.region, signature }) });

        var writer = std.ArrayList(u8).init(self.allocator);
        defer writer.deinit();

        const bytes_read = try self.sendRequest("POST", headers.items, json_str, writer.writer());

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

    fn sendRequest(self: *DynamoDbClient, comptime method: []const u8, headers: []http.Header, body: []const u8, writer: anytype) !usize {
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

    fn getRegionFromSts(allocator: std.mem.Allocator, access_key_id: []const u8, secret_access_key: []const u8, session_token: []const u8) ![]const u8 {
        const sts_endpoint = "https://sts.amazonaws.com";
        var client = http.Client{ .allocator = allocator };
        defer client.deinit();

        const uri = try std.Uri.parse(sts_endpoint);
        var server_header: [1024]u8 = undefined;

        const timestamp = try getIso8601Timestamp();
        const date = timestamp[0..8];

        const body = "Action=GetCallerIdentity&Version=2011-06-15";

        var headers = std.ArrayList(http.Header).init(allocator);
        defer headers.deinit();

        try headers.append(.{ .name = "Host", .value = uri.host.? });
        try headers.append(.{ .name = "X-Amz-Date", .value = timestamp });
        try headers.append(.{ .name = "X-Amz-Security-Token", .value = session_token });
        try headers.append(.{ .name = "Content-Type", .value = "application/x-www-form-urlencoded" });

        const canonical_request = try createCanonicalRequest(allocator, "POST", "/", headers.items, body, timestamp);
        const string_to_sign = try createStringToSign(allocator, date, "us-east-1", "sts", canonical_request);
        const signature = try calculateSignature(allocator, secret_access_key, date, "us-east-1", "sts", string_to_sign);

        const auth_header = try std.fmt.allocPrint(allocator, "AWS4-HMAC-SHA256 Credential={s}/{s}/us-east-1/sts/aws4_request, SignedHeaders=content-type;host;x-amz-date;x-amz-security-token, Signature={s}", .{ access_key_id, date, signature });
        defer allocator.free(auth_header);

        try headers.append(.{ .name = "Authorization", .value = auth_header });

        var request = try client.open(.POST, uri, .{ .server_header_buffer = &server_header, .extra_headers = headers.items });
        defer request.deinit();

        try request.send();
        try request.finish();
        try request.wait();

        var response_body = std.ArrayList(u8).init(allocator);
        defer response_body.deinit();
        try request.reader().readAllArrayList(&response_body, 4096);

        const parsed = try json.parseFromSlice(std.json.Value, allocator, response_body.items, .{});
        defer parsed.deinit();

        const arn = parsed.value.object.get("GetCallerIdentityResult").?.object.get("Arn").?.string;
        const region = std.mem.split(u8, arn, ":").skip(3).next().?;

        return try allocator.dupe(u8, region);
    }

    fn createCanonicalRequest(self: *DynamoDbClient, method: []const u8, path: []const u8, headers: []http.Header, body: []const u8, timestamp: []const u8) ![]u8 {
        _ = headers;
        var canonical_headers = std.ArrayList(u8).init(self.allocator);
        defer canonical_headers.deinit();

        try canonical_headers.appendSlice("host:");
        try canonical_headers.appendSlice(self.endpoint);
        try canonical_headers.appendSlice("\n");
        try canonical_headers.appendSlice("x-amz-date:");
        try canonical_headers.appendSlice(timestamp);
        try canonical_headers.appendSlice("\n");

        const payload_hash = try self.hashSha256(body);

        const canonical_request = try std.fmt.allocPrint(self.allocator, "{s}\n{s}\n\n{s}\nhost;x-amz-date\n{s}", .{
            method,
            path,
            canonical_headers.items,
            payload_hash,
        });

        return canonical_request;
    }

    fn createStringToSign(self: *DynamoDbClient, date: []const u8, region: []const u8, service: []const u8, canonical_request: []const u8) ![]u8 {
        const hashed_canonical_request = try self.hashSha256(canonical_request);

        return try std.fmt.allocPrint(self.allocator, "AWS4-HMAC-SHA256\n{s}T000000Z\n{s}/{s}/{s}/aws4_request\n{s}", .{
            date,
            date,
            region,
            service,
            hashed_canonical_request,
        });
    }

    fn calculateSignature(self: *DynamoDbClient, date: []const u8, region: []const u8, service: []const u8, string_to_sign: []const u8) ![]u8 {
        const k_date = try self.hmacSha256("AWS4" ++ self.secret_access_key, date);
        const k_region = try self.hmacSha256(k_date, region);
        const k_service = try self.hmacSha256(k_region, service);
        const k_signing = try self.hmacSha256(k_service, "aws4_request");

        const signature = try self.hmacSha256(k_signing, string_to_sign);
        return try std.fmt.allocPrint(self.allocator, "{x}", .{std.fmt.fmtSliceHexLower(signature)});
    }

    // fn getIso8601Timestamp() ![]const u8 {
    //     const now = std.time.timestamp();
    //     var buf: [20]u8 = undefined;
    //     return try std.fmt.bufPrint(&buf, "{d:0>4}{d:0>2}{d:0>2}T{d:0>2}{d:0>2}{d:0>2}Z", .{
    //         std.time.year(now),
    //         std.time.month(now),
    //         std.time.day(now),
    //         std.time.hour(now),
    //         std.time.minute(now),
    //         std.time.second(now),
    //     });
    // }

    fn getIso8601Timestamp() ![]const u8 {
        var buffer: [20]u8 = undefined;
        const timestamp = std.time.timestamp();
        const epoch_seconds = @as(u64, @intCast(@max(timestamp, 0)));

        var ts = std.time.epoch.EpochSeconds{ .secs = epoch_seconds };
        const epoch_day = ts.getEpochDay();
        const day_seconds = ts.getDaySeconds();

        const year = std.time.epoch.getEpochYear(epoch_day);
        const month_day = std.time.epoch.getYearDay(year, epoch_day);
        const month = @as(u8, @intCast(month_day.month));
        const day = @as(u8, @intCast(month_day.day_index + 1));

        const hours = @as(u8, @intCast(day_seconds / std.time.s_per_hour));
        const minutes = @as(u8, @intCast((day_seconds % std.time.s_per_hour) / std.time.s_per_min));
        const seconds = @as(u8, @intCast(day_seconds % std.time.s_per_min));

        const len = try std.fmt.bufPrint(&buffer, "{d:0>4}{d:0>2}{d:0>2}T{d:0>2}{d:0>2}{d:0>2}Z", .{
            year,
            month,
            day,
            hours,
            minutes,
            seconds,
        });

        // return try self.allocator.dupe(u8, len);
        return len;
    }

    fn hashSha256(self: *DynamoDbClient, data: []const u8) ![]u8 {
        var hash: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(data, &hash, .{});
        return try std.fmt.allocPrint(self.allocator, "{x}", .{std.fmt.fmtSliceHexLower(&hash)});
    }

    fn hmacSha256(self: *DynamoDbClient, key: []const u8, data: []const u8) ![]u8 {
        _ = self;
        var out: [32]u8 = undefined;
        var h = std.crypto.auth.hmac.sha2.HmacSha256.init(key);
        h.update(data);
        h.final(&out);
        return out[0..];
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
