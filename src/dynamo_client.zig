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
const GLOBAL_ENDPOINT = "https://dynamodb.us-east-1.amazonaws.com";

pub const Credentials = struct {
    region: ?[:0]const u8,
    access_key: [:0]const u8,
    secret_access_key: [:0]const u8,
    session_token: [:0]const u8,
};

pub const DynamoDbClient = struct {
    allocator: std.mem.Allocator,
    endpoint: []const u8,
    credentials: Credentials,

    pub fn init(allocator: std.mem.Allocator, endpoint: ?[]const u8, credentials: Credentials) !DynamoDbClient {
        // const owned_region = blk: {
        //     if (credentials.region) |region| {
        //         break :blk try allocator.dupe(u8, region);
        //     }
        //     const region_from_sts = try getRegionFromSts(
        //         allocator,
        //         credentials.access_key.?[0..credentials.access_key.?.len],
        //         credentials.secret_access_key.?[0..credentials.secret_access_key.?.len],
        //         credentials.session_token.?[0..credentials.session_token.?.len],
        //     );
        //     break :blk region_from_sts;
        // };
        // const owned_endpoint: []const u8 = blk: {
        //     if (endpoint) |endpt| {
        //         break :blk try allocator.dupe(u8, endpt);
        //     }
        //     const endpoint_from_region = try std.fmt.allocPrint(allocator, "https://dynamodb.{s}.amazonaws.com", .{owned_region});
        //     break :blk endpoint_from_region;
        // };
        // const owned_access_key = try allocator.dupe(u8, credentials.access_key.?);
        // const owned_secret_key = try allocator.dupe(u8, credentials.secret_access_key.?);
        const owned_endpoint: []const u8 = blk: {
            if (endpoint) |endpt| {
                break :blk try allocator.dupe(u8, endpt);
            }
            break :blk GLOBAL_ENDPOINT;
        };

        return DynamoDbClient{
            .allocator = allocator,
            .endpoint = owned_endpoint,
            .credentials = credentials,
            // .region = owned_region,
            // .access_key_id = owned_access_key,
            // .secret_access_key = owned_secret_key,
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
        const sign_headers = try dynamo_signature.signRequest(allocator, "POST", "/", "", writer.items, self.credentials.access_key, self.credentials.secret_access_key, self.credentials.session_token, null);
        try headers.appendSlice(sign_headers);

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

        const sign_headers = try dynamo_signature.signRequest(self.allocator, "POST", "/", "", json_str, self.credentials.access_key, self.credentials.secret_access_key, self.credentials.session_token, null);
        try headers.appendSlice(sign_headers);

        _ = try self.sendRequest("POST", headers.items, json_str, null_writer);
    }
    pub fn list(self: *DynamoDbClient) !void {
        _ = self;
        // @setAlignStack(16);

        // var arena = std.heap.ArenaAllocator.init(self.allocator);
        // defer arena.deinit();
        // const arena_allocator = arena.allocator();
        // _ = arena_allocator;

        std.debug.print("Before try block\n", .{});
        // ... (rest of the function) ...
        std.debug.print("After try block\n", .{});
        // var headers = std.ArrayList(std.http.Header).init(arena_allocator);
        //
        // try headers.append(.{ .name = "Content-Type", .value = "application/x-amz-json-1.0" });
        // try headers.append(.{ .name = "X-Amz-Target", .value = "DynamoDB_20120810.ListTables" });
        //
        // const payload = .{
        //     .Limit = 100,
        //     .ExclusiveStartTableName = null,
        // };
        // const body = try json.stringifyAlloc(arena_allocator, payload, .{});
        // defer arena_allocator.free(body);

        std.debug.print("Before signRequest\n", .{});
        // const sign_headers = try dynamo_signature.signRequest(arena_allocator, "POST", "/", "", body, self.credentials.access_key, self.credentials.secret_access_key, self.credentials.session_token, null);
        //
        // std.debug.print("Number of signed headers: {}\n", .{sign_headers.len});
        // for (sign_headers, 0..) |header, i| {
        //     std.debug.print("Signed Header {}: {s}: {s}\n", .{ i, header.name, header.value });
        //     std.debug.print("Signed Header {} name ptr: 0x{x}, value ptr: 0x{x}\n", .{ i, @intFromPtr(header.name.ptr), @intFromPtr(header.value.ptr) });
        // }
        //
        // try headers.appendSlice(sign_headers);

        // std.debug.print("Total headers after append: {}\n", .{headers.items.len});
        // std.debug.print("Headers ptr: 0x{x}\n", .{@intFromPtr(headers.items.ptr)});
        // for (headers.items, 0..) |header, i| {
        //     std.debug.print("Total Header {}: {s}: {s}\n", .{ i, header.name, header.value });
        //     std.debug.print("Total Header {} name ptr: 0x{x}, value ptr: 0x{x}\n", .{ i, @intFromPtr(header.name.ptr), @intFromPtr(header.value.ptr) });
        // }

        // std.debug.print("After signRequest\n", .{});
        //
        // var writer = std.ArrayList(u8).init(arena_allocator);
        //
        // std.debug.print("Before sendRequest\n", .{});
        // const bytes_read = try self.sendRequest("POST", headers.items, body, writer.writer());
        // std.debug.print("After sendRequest\n", .{});
        //
        // std.debug.print("response to parse response_buff[0..{d}]: {s}\n", .{ bytes_read, writer.items });
        std.debug.print("End of list function\n", .{});
        std.debug.print("End of list function\n", .{});
        const sentinel: u64 = 0xDEADBEEFDEADBEEF;
        std.debug.print("Sentinel value: 0x{x}\n", .{sentinel});
    }

    // pub fn list(self: *DynamoDbClient) !void {
    //     var headers = std.ArrayList(std.http.Header).init(self.allocator);
    //     // defer headers.deinit();
    //
    //     try headers.append(.{ .name = "Content-Type", .value = "application/x-amz-json-1.0" });
    //     try headers.append(.{ .name = "X-Amz-Target", .value = "DynamoDB_20120810.ListTables" });
    //
    //     const payload = .{
    //         .Limit = 100,
    //         .ExclusiveStartTableName = null,
    //     };
    //
    //     const body = try json.stringifyAlloc(self.allocator, payload, .{});
    //     // defer self.allocator.free(body);
    //
    //     std.debug.print("Before signRequest\n", .{});
    //     const sign_headers = try dynamo_signature.signRequest(self.allocator, "POST", "/", "", body, self.credentials.access_key, self.credentials.secret_access_key, self.credentials.session_token, null);
    //     // defer self.allocator.free(sign_headers);
    //
    //     std.debug.print("Number of headers: {}\n", .{sign_headers.len});
    //     for (sign_headers, 0..) |header, i| {
    //         std.debug.print("Header {}: {s}: {s}\n", .{ i, header.name, header.value });
    //         std.debug.print("Header {} name ptr: 0x{x}, value ptr: 0x{x}\n", .{ i, @intFromPtr(header.name.ptr), @intFromPtr(header.value.ptr) });
    //     }
    //     std.debug.print("After signRequest\n", .{});
    //
    //     try headers.appendSlice(sign_headers);
    //
    //     var writer = std.ArrayList(u8).init(self.allocator);
    //     // defer writer.deinit();
    //
    //     std.debug.print("Before sendRequest\n", .{});
    //     const bytes_read = try self.sendRequest("POST", headers.items, body, writer.writer());
    //     std.debug.print("After sendRequest\n", .{});
    //
    //     std.debug.print("response to parse response_buff[0..{d}]: {s}\n", .{ bytes_read, writer.items });
    //     std.debug.print("End of list function\n", .{});
    // }

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
        const sign_headers = try dynamo_signature.signRequest(self.allocator, "POST", "/", "", body, self.credentials.access_key, self.credentials.secret_access_key, self.credentials.session_token, null);
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
        _ = self;
        _ = method;
        _ = headers;
        errdefer |err| {
            std.debug.print("Error in sendRequest: {}\n", .{err});
        }
        std.debug.print("BODY: {s}\n", .{body});
        std.debug.print("HEADERS: \n", .{});
        // for (headers) |header| {
        //     std.debug.print("{s}: {s}\n", .{ header.name, header.value });
        // }
        std.debug.print("END HEADERS\n", .{});
        // var client = http.Client{ .allocator = self.allocator };
        // defer client.deinit();
        // const uri = try std.Uri.parse(self.endpoint);
        // std.debug.print("endpoint: {s}\n", .{self.endpoint});
        // std.debug.print("uri: {s}\n", .{uri});
        //
        // const server_header = try self.allocator.alloc(u8, 4096);
        // defer self.allocator.free(server_header);
        //
        // var request = try client.open(@field(http.Method, method), uri, .{ .server_header_buffer = server_header, .extra_headers = headers });
        // defer request.deinit();
        // std.debug.print("server_header: {s}\n", .{server_header});
        // std.debug.print("body: {s}\n", .{body});
        //
        // request.transfer_encoding = .{ .content_length = body.len };
        // request.keep_alive = true;
        // try request.send();
        // try request.writeAll(body);
        //
        // try request.finish();
        // try request.wait();

        // Print response status
        // const status = request.response.status;

        // std.debug.print("Response status: {}\n", .{status});

        // Print response headers
        std.debug.print("Response headers:\n", .{});
        // const header_it = request.response.parser.;
        // for (header_it) |header| {
        //     std.debug.print("{s}: {s}\n", .{ header.name, header.value });
        // }

        // Check for content length
        // if (request.response.content_length) |content_length| {
        //     std.debug.print("Content-Length: {d}\n", .{content_length});
        // } else {
        //     std.debug.print("Content-Length not provided\n", .{});
        // }

        // const BUFFER_SIZE = 4096;
        // var buffer: [BUFFER_SIZE]u8 = undefined;
        // if (status != .ok) {
        //     std.debug.print("Error: HTTP status {d}\n", .{@intFromEnum(status)});
        //     return error.HttpRequestFailed;
        // }
        // if (request.response.transfer_encoding == .chunked) {
        //     std.debug.print("Response is using chunked encoding\n", .{});
        //     // Implement chunked reading here
        // }

        const total_bytes: usize = 0;
        _ = writer;
        // var buffer = try self.allocator.alloc(u8, 4096000);
        // defer self.allocator.free(buffer);
        //
        // while (true) {
        //     const bytes_read = try request.reader().read(buffer);
        //     if (bytes_read == 0) break;
        //     try writer.writeAll(buffer[0..bytes_read]);
        //     total_bytes += bytes_read;
        // }
        //
        // std.debug.print("Request succeeded\n", .{});
        return total_bytes;
        // while (true) {
        //     const bytes_read = try request.reader().read(buffer);
        //     if (bytes_read == 0) break;
        //     try writer.writeAll(buffer[0..bytes_read]);
        //     total_bytes += bytes_read;
        // }
        // if (status != .ok) {
        //     std.debug.print("Error: HTTP status {d}\n", .{@intFromEnum(status)});
        //     return error.HttpRequestFailed;
        // }
        // std.debug.print("Request succeeded\n", .{});
        // return total_bytes;
    }

    // fn getRegionFromSts(allocator: std.mem.Allocator, access_key_id: []const u8, secret_access_key: []const u8, session_token: []const u8) ![]const u8 {
    //     const sts_endpoint = "https://sts.amazonaws.com";
    //     var client = http.Client{ .allocator = allocator };
    //     defer client.deinit();
    //
    //     const uri = try std.Uri.parse(sts_endpoint);
    //     var server_header: [1024]u8 = undefined;
    //
    //     const timestamp = try getIso8601Timestamp(allocator);
    //     const date = timestamp[0..8];
    //
    //     std.debug.print("date {s}\n", .{date});
    //
    //     const body = "Action=GetCallerIdentity&Version=2011-06-15";
    //
    //     var headers = std.ArrayList(http.Header).init(allocator);
    //     defer headers.deinit();
    //
    //     try headers.append(.{ .name = "Host", .value = uri.host.?.percent_encoded });
    //     // try headers.append(.{ .name = "Host", .value = sts_endpoint });
    //     try headers.append(.{ .name = "X-Amz-Date", .value = timestamp });
    //     try headers.append(.{ .name = "X-Amz-Security-Token", .value = session_token });
    //     try headers.append(.{ .name = "Content-Type", .value = "application/x-www-form-urlencoded" });
    //
    //     for (headers.items) |h| {
    //         std.debug.print("name: {s} value: {s}\n", .{ h.name, h.value });
    //     }
    //
    //     const canonical_request = try createCanonicalRequest(allocator, sts_endpoint, "POST", "/", headers.items, body, timestamp);
    //     std.debug.print("canonical_request {s}\n", .{canonical_request});
    //     const string_to_sign = try createStringToSign(allocator, date, "us-east-1", "sts", canonical_request);
    //     const signature = try calculateSignature(allocator, date, "us-east-1", "sts", string_to_sign, secret_access_key);
    //
    //     const auth_header = try std.fmt.allocPrint(allocator, "AWS4-HMAC-SHA256 Credential={s}/{s}/us-east-1/sts/aws4_request, SignedHeaders=content-type;host;x-amz-date;x-amz-security-token, Signature={s}", .{ access_key_id, date, signature });
    //     defer allocator.free(auth_header);
    //
    //     std.debug.print("Auth header {s}\n", .{auth_header});
    //
    //     try headers.append(.{ .name = "Authorization", .value = auth_header });
    //
    //     var request = try client.open(.POST, uri, .{ .server_header_buffer = &server_header, .extra_headers = headers.items });
    //     defer request.deinit();
    //
    //     try request.send();
    //     try request.finish();
    //     try request.wait();
    //
    //     var response_body = std.ArrayList(u8).init(allocator);
    //     defer response_body.deinit();
    //     try request.reader().readAllArrayList(&response_body, 4096);
    //
    //     const parsed = try json.parseFromSlice(std.json.Value, allocator, response_body.items, .{});
    //     defer parsed.deinit();
    //
    //     const arn = parsed.value.object.get("GetCallerIdentityResult").?.object.get("Arn").?.string;
    //     // const region = std.mem.splitScalar(u8, arn, ':').skip(3).next().?;
    //     var itr = std.mem.splitScalar(u8, arn, ':');
    //     var idx: usize = 0;
    //     const region = blk: {
    //         while (itr.next()) |part| {
    //             if (idx == 3) {
    //                 break :blk part;
    //             }
    //             idx += 1;
    //         }
    //         return error.MissingRegion;
    //     };
    //
    //     return try allocator.dupe(u8, region);
    // }

    // fn createCanonicalRequest(allocator: std.mem.Allocator, endpoint: []const u8, method: []const u8, path: []const u8, headers: []http.Header, body: []const u8, timestamp: []const u8) ![]u8 {
    //     _ = headers;
    //     var canonical_headers = std.ArrayList(u8).init(allocator);
    //     defer canonical_headers.deinit();
    //
    //     try canonical_headers.appendSlice("host:");
    //     try canonical_headers.appendSlice(endpoint);
    //     try canonical_headers.appendSlice("\n");
    //     try canonical_headers.appendSlice("x-amz-date:");
    //     try canonical_headers.appendSlice(timestamp);
    //     try canonical_headers.appendSlice("\n");
    //
    //     const payload_hash = try hashSha256(allocator, body);
    //
    //     const canonical_request = try std.fmt.allocPrint(allocator, "{s}\n{s}\n\n{s}\nhost;x-amz-date\n{s}", .{
    //         method,
    //         path,
    //         canonical_headers.items,
    //         payload_hash,
    //     });
    //     std.debug.print("canonical_request {s}\n", .{canonical_request});
    //
    //     return canonical_request;
    // }
    //
    // fn createStringToSign(allocator: std.mem.Allocator, date: []const u8, region: []const u8, service: []const u8, canonical_request: []const u8) ![]u8 {
    //     const hashed_canonical_request = try hashSha256(allocator, canonical_request);
    //
    //     return try std.fmt.allocPrint(allocator, "AWS4-HMAC-SHA256\n{s}T000000Z\n{s}/{s}/{s}/aws4_request\n{s}", .{
    //         date,
    //         date,
    //         region,
    //         service,
    //         hashed_canonical_request,
    //     });
    // }
    //
    // fn calculateSignature(allocator: std.mem.Allocator, date: []const u8, region: []const u8, service: []const u8, string_to_sign: []const u8, secret_access_key: []const u8) ![]u8 {
    //     const k_str = try std.fmt.allocPrint(allocator, "AWS4{s}", .{secret_access_key});
    //     const k_date = try hmacSha256(k_str, date);
    //     const k_region = try hmacSha256(k_date, region);
    //     const k_service = try hmacSha256(k_region, service);
    //     const k_signing = try hmacSha256(k_service, "aws4_request");
    //
    //     const signature = try hmacSha256(k_signing, string_to_sign);
    //     return try std.fmt.allocPrint(allocator, "{x}", .{std.fmt.fmtSliceHexLower(signature)});
    // }
    //
    // fn getIso8601Timestamp(allocator: std.mem.Allocator) ![]const u8 {
    //     var buffer: [20]u8 = undefined;
    //     const date_now = DateTime.now();
    //
    //     const len = try std.fmt.bufPrint(&buffer, "{d:0>4}{d:0>2}{d:0>2}T{d:0>2}{d:0>2}{d:0>2}Z", .{
    //         date_now.year,
    //         date_now.month,
    //         date_now.day,
    //         date_now.hour,
    //         date_now.minute,
    //         date_now.second,
    //     });
    //
    //     return try allocator.dupe(u8, len);
    // }
    //
    // fn hashSha256(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
    //     var hash: [32]u8 = undefined;
    //     std.crypto.hash.sha2.Sha256.hash(data, &hash, .{});
    //     return try std.fmt.allocPrint(allocator, "{x}", .{std.fmt.fmtSliceHexLower(&hash)});
    // }
    //
    // fn hmacSha256(key: []const u8, data: []const u8) ![]u8 {
    //     var out: [32]u8 = undefined;
    //     var h = std.crypto.auth.hmac.sha2.HmacSha256.init(key);
    //     h.update(data);
    //     h.final(&out);
    //     return out[0..];
    // }
};

pub fn panic(msg: []const u8, error_return_trace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    @setCold(true);
    std.debug.print("PANIC: {s}\n", .{msg});
    if (error_return_trace) |trace| {
        std.debug.dumpStackTrace(trace.*);
    }
    if (ret_addr) |addr| {
        std.debug.print("Return address: 0x{x}\n", .{addr});
    }
    std.os.exit(1);
}

test "list tables" {
    // const allocator = std.testing.allocator;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        switch (leaked) {
            .leak => std.debug.print("Memory leak detected!\n", .{}),
            .ok => {},
        }
    }
    const allocator = gpa.allocator();
    // var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    // defer arena.deinit();
    // const allocator = arena.allocator();
    // var client = try DynamoDbClient.init(allocator, "http://localhost:4566");
    const AWS_ACCESS_KEY_ID = "ASIAQJLWAM3K3LKOEF5T";
    const AWS_SECRET_ACCESS_KEY = "FBHS7Ko6no4qJvl37VfrpHIxgiGSj4rBQ2agAaMO";
    const AWS_SESSION_TOKEN = "IQoJb3JpZ2luX2VjEJD//////////wEaCXVzLWVhc3QtMSJIMEYCIQDepgQQtwVvpKlKpAWXPz2Nob9lXZy81yovsXAGb3gkugIhAMmRZYShGoWNRgtg5UtpOihdpBHM0Ewq/P1XJjV3PkCkKqEDCJn//////////wEQAxoMMDIwMTExNzE0MDA1IgxqdpnCVTA0QeH5GPUq9QLKMxt+kwgpaP8aA3VkqgNZPch2qZZP80pf2eruQ2RlIttX1s8NqmU3aE03wYwZPNGPERQesVMJwrVPmbaWB6rNWgl2/z7J0x7ofhzEKfW5f2gdNt1xN88P3bO64U0GQatai4PLpfpMM0dowZq65rtj109ExOiLD3riygYmb8KcQvyLH6GCDmocRYLF3pgq7rlWicYnGSMuSHdfkD9fPe6RTeMFepztKhw0AWIcH0NqjTQO4oYBf7DdehB5pC3yee58cd1cvnfkw2qkiFdEXa67mDAz7yicP5//BbZ5Mq7xXnkbva5v8JwqwrwjKJdoLOSUmswkmns3qvO/dQC8ETHUbdfCpC+aYJOu1Bxki35W9W8iSqaSAoJggqarwtBBoN8yTWhmSspy6yVqCGDipO5G3YxyOnJ1wwRbgU3L5l+9aHrLy04Yx+OJNMo6wMq7sWGRnfo6R3CF56ZIPe0hY/aKTTIC+FyuPdHMAjc9f2j6qxAVw/S0MLeen7YGOqUBLjlRGE8i+8jmClkPsd4Cv7ol8tNFKsu0Tf3H3U8BHhwIPlN/Go/J2PfqpO0R8c5vUDQYG49zmsDX6RubncfgOaAizef444xFqwptvvQbh+MuwSZa4CiMuE7OngdjHVTo+6IOT1oUiofsygk5MpaQPTXtt8D27C1Lo1HyjNQxzDjoeMUT811nwjr/5rNzMMBdyccy8AZCn2zt1N1kWFRl23gwkudT";
    const credentials = Credentials{
        .region = "us-east-1",
        .access_key = AWS_ACCESS_KEY_ID,
        .secret_access_key = AWS_SECRET_ACCESS_KEY,
        .session_token = AWS_SESSION_TOKEN,
    };
    var client = try DynamoDbClient.init(allocator, null, credentials);
    defer client.deinit();

    // var tables = try client.listTables();
    // defer tables.deinit(allocator);
    try client.list();

    // std.debug.print("Tables: {any}\n", .{tables});
    //
    // for (tables.TableNames.items) |table_name| {
    //     std.debug.print("Table: {s}\n", .{table_name});
    // }
    //
    // if (tables.LastEvaluatedTableName) |last_table| {
    //     std.debug.print("Last evaluated table: {s}\n", .{last_table});
    // }
}
