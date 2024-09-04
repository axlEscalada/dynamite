const std = @import("std");
const crypto = std.crypto;
const fmt = std.fmt;
const mem = std.mem;
const time = std.time;
const testing = std.testing;
const DateTime = @import("date_time.zig").DateTime;
const AWS4_HMAC_SHA256 = "AWS4-HMAC-SHA256";
const AWS4_REQUEST = "aws4_request";
const SERVICE = "dynamodb";
const DEFAULT_REGION = "us-east-1";

pub fn signRequest(
    allocator: std.mem.Allocator,
    method: []const u8,
    uri: []const u8,
    query_string: []const u8,
    payload: []const u8,
    access_key: []const u8,
    secret_key: []const u8,
    session_token: ?[]const u8,
    date_time: ?DateTime,
    append_headers: []std.http.Header,
    endpoint: []const u8,
) ![]std.http.Header {
    const now = blk: {
        if (date_time) |d| {
            break :blk d;
        } else break :blk DateTime.now();
    };
    const date = try formatDate(allocator, now);
    // defer allocator.free(date);
    const datetime = try formatDatetime(allocator, now);
    // defer allocator.free(datetime);
    const ur = try std.Uri.parse(endpoint);

    var payload_hash: [32]u8 = undefined;
    crypto.hash.sha2.Sha256.hash(payload, &payload_hash, .{});
    const payload_hash_hex = try allocator.alloc(u8, 64);
    // defer allocator.free(payload_hash_hex);
    _ = try std.fmt.bufPrint(payload_hash_hex, "{s}", .{std.fmt.fmtSliceHexLower(&payload_hash)});
    std.debug.print("Payload hash: {s}\n", .{payload_hash_hex});
    var headers_to_sign = std.ArrayList(std.http.Header).init(allocator);
    // defer headers_to_sign.deinit();
    for (append_headers) |header| {
        try headers_to_sign.append(header);
    }
    std.debug.print("uri host: {s}\n", .{ur.host.?.percent_encoded});
    const host = blk: {
        if (ur.port) |port| {
            break :blk try std.fmt.allocPrint(allocator, "{s}:{d}", .{ ur.host.?.percent_encoded, port });
        }
        break :blk try allocator.dupe(u8, ur.host.?.percent_encoded);
    };
    try headers_to_sign.append(.{ .name = try allocator.dupe(u8, "Host"), .value = try allocator.dupe(u8, host) });
    try headers_to_sign.append(.{ .name = try allocator.dupe(u8, "x-amz-date"), .value = try allocator.dupe(u8, datetime) });
    if (session_token) |st| {
        try headers_to_sign.append(.{ .name = try allocator.dupe(u8, "x-amz-security-token"), .value = try allocator.dupe(u8, st) });
        std.debug.print("Adding session token: {s}\n", .{st});
    } else {
        std.debug.print("No session token\n", .{});
    }
    try headers_to_sign.append(.{ .name = try allocator.dupe(u8, "x-amz-content-sha256"), .value = try allocator.dupe(u8, payload_hash_hex) });

    // Step 1: Create the canonical request
    const canonical_request = try createCanonicalRequest(allocator, method, uri, query_string, payload_hash_hex, ur.host.?.percent_encoded, datetime, session_token, headers_to_sign.items);
    // defer allocator.free(canonical_request);
    std.debug.print("Canonical req: \n {s}\n", .{canonical_request});
    std.debug.print("END\n", .{});

    // Step 2: Create the string to sign
    const string_to_sign = try createStringToSign(allocator, datetime, canonical_request);
    // defer allocator.free(string_to_sign);
    std.debug.print("String to sign: {s}\n", .{string_to_sign});

    // Step 3: Calculate the signature
    const signature = try calculateSignature(allocator, secret_key, date, string_to_sign);
    // defer allocator.free(signature);
    std.debug.print("Signature: {s}\n", .{signature});

    // Step 4: Create the authorization header
    const auth_header = try createAuthorizationHeader(allocator, access_key, date, signature);
    // defer allocator.free(auth_header);

    var headers = std.ArrayList(std.http.Header).init(allocator);
    // Here 'host' is not necessary because is added by http library and can cause conflicts have this header deuplicated
    try headers.append(.{ .name = try allocator.dupe(u8, "x-amz-date"), .value = try allocator.dupe(u8, datetime) });
    if (session_token) |st| {
        try headers.append(.{ .name = try allocator.dupe(u8, "x-amz-security-token"), .value = try allocator.dupe(u8, st) });
    }
    try headers.append(.{ .name = try allocator.dupe(u8, "x-amz-content-sha256"), .value = try allocator.dupe(u8, payload_hash_hex) });
    try headers.append(.{ .name = try allocator.dupe(u8, "authorization"), .value = try allocator.dupe(u8, auth_header) });
    return headers.items;
}

fn sortByName(context: void, a: std.http.Header, b: std.http.Header) bool {
    _ = context;
    return std.ascii.lessThanIgnoreCase(a.name, b.name);
}

fn createCanonicalRequest(
    allocator: std.mem.Allocator,
    method: []const u8,
    uri: []const u8,
    query_string: []const u8,
    payload_hash_hex: []const u8,
    host: []const u8,
    datetime: []const u8,
    session_token: ?[]const u8,
    headers_to_sign: []std.http.Header,
) ![]u8 {
    _ = host;
    _ = datetime;
    var canonical = std.ArrayList(u8).init(allocator);
    // defer canonical.deinit();

    try canonical.appendSlice(method);
    try canonical.appendSlice("\n");
    try canonical.appendSlice(uri);
    try canonical.appendSlice("\n");
    try canonical.appendSlice(query_string);
    try canonical.appendSlice("\n");

    std.mem.sort(std.http.Header, headers_to_sign, {}, sortByName);
    for (headers_to_sign) |header| {
        const buffer_name = try allocator.alloc(u8, header.name.len);
        _ = std.ascii.lowerString(buffer_name, header.name);
        std.debug.print("appending: {s}:{s} \n", .{ buffer_name, header.value });
        try canonical.appendSlice(buffer_name);
        try canonical.appendSlice(":");
        try canonical.appendSlice(header.value);
        try canonical.appendSlice("\n");
    }

    // Signed headers (in alphabetical order, lowercase)
    try canonical.appendSlice("\n");
    if (session_token) |st| {
        _ = st;
        try canonical.appendSlice("content-type;host;x-amz-content-sha256;x-amz-date;x-amz-security-token;x-amz-target\n");
    } else {
        try canonical.appendSlice("content-type;host;x-amz-content-sha256;x-amz-date;x-amz-target\n");
    }

    try canonical.appendSlice(payload_hash_hex);

    return canonical.toOwnedSlice();
}

fn createStringToSign(
    allocator: std.mem.Allocator,
    datetime: []const u8,
    canonical_request: []const u8,
) ![]u8 {
    var string_to_sign = std.ArrayList(u8).init(allocator);
    // defer string_to_sign.deinit();

    try string_to_sign.appendSlice(AWS4_HMAC_SHA256);
    try string_to_sign.appendSlice("\n");
    try string_to_sign.appendSlice(datetime);
    try string_to_sign.appendSlice("\n");

    const scope = try fmt.allocPrint(allocator, "{s}/{s}/{s}/{s}", .{
        datetime[0..8],
        DEFAULT_REGION,
        SERVICE,
        AWS4_REQUEST,
    });
    // defer allocator.free(scope);
    try string_to_sign.appendSlice(scope);
    try string_to_sign.appendSlice("\n");

    std.debug.print("Canonical req: \n {s}\n", .{canonical_request});
    std.debug.print("END\n", .{});
    var hash: [32]u8 = undefined;
    crypto.hash.sha2.Sha256.hash(canonical_request, &hash, .{});
    const hash_hex = try allocator.alloc(u8, 64);
    // defer allocator.free(hash_hex);
    _ = try fmt.bufPrint(hash_hex, "{s}", .{fmt.fmtSliceHexLower(&hash)});
    try string_to_sign.appendSlice(hash_hex);

    return string_to_sign.toOwnedSlice();
}

fn calculateSignature(
    allocator: std.mem.Allocator,
    secret_key: []const u8,
    date: []const u8,
    string_to_sign: []const u8,
) ![]u8 {
    const k_secret = try std.fmt.allocPrint(allocator, "AWS4{s}", .{secret_key});
    const k_date = try hmacSha256(allocator, k_secret, date);
    defer allocator.free(k_date);
    std.debug.print("Key: {any}\n", .{k_date});

    const k_region = try hmacSha256(allocator, k_date, DEFAULT_REGION);
    defer allocator.free(k_region);
    std.debug.print("Key: {any}\n", .{k_region});

    const k_service = try hmacSha256(allocator, k_region, SERVICE);
    defer allocator.free(k_service);
    std.debug.print("Key: {any}\n", .{k_service});

    const k_signing = try hmacSha256(allocator, k_service, AWS4_REQUEST);
    defer allocator.free(k_signing);
    std.debug.print("Key: {any}\n", .{k_signing});

    const signature = try hmacSha256(allocator, k_signing, string_to_sign);
    defer allocator.free(signature);
    std.debug.print("Key: {any}\n", .{signature});

    const signature_hex = try allocator.alloc(u8, 64);
    _ = try fmt.bufPrint(signature_hex, "{s}", .{fmt.fmtSliceHexLower(signature)});

    return signature_hex;
}

fn createAuthorizationHeader(
    allocator: std.mem.Allocator,
    access_key: []const u8,
    date: []const u8,
    signature: []const u8,
) ![]u8 {
    const credential_scope = try fmt.allocPrint(allocator, "{s}/{s}/{s}/{s}", .{
        date,
        DEFAULT_REGION,
        SERVICE,
        AWS4_REQUEST,
    });
    // defer allocator.free(credential_scope);

    const signed_headers = "content-type;host;x-amz-content-sha256;x-amz-date;x-amz-security-token;x-amz-target";

    const result = try fmt.allocPrint(allocator, "{s} Credential={s}/{s}, SignedHeaders={s}, Signature={s}", .{ AWS4_HMAC_SHA256, access_key, credential_scope, signed_headers, signature });

    std.debug.print("Auth header: {s}\n", .{result});

    return result;
}

fn hmacSha256(allocator: std.mem.Allocator, key: []const u8, data: []const u8) ![]u8 {
    var hmac = crypto.auth.hmac.sha2.HmacSha256.init(key);
    hmac.update(data);
    var out: [32]u8 = undefined;
    hmac.final(&out);
    return allocator.dupe(u8, &out);
}

fn formatDate(allocator: std.mem.Allocator, date: DateTime) ![]u8 {
    return fmt.allocPrint(allocator, "{d:0>4}{d:0>2}{d:0>2}", .{
        date.year,
        date.month,
        date.day,
    });
}

fn formatDatetime(allocator: std.mem.Allocator, date: DateTime) ![]u8 {
    return fmt.allocPrint(allocator, "{d:0>4}{d:0>2}{d:0>2}T{d:0>2}{d:0>2}{d:0>2}Z", .{
        date.year,
        date.month,
        date.day,
        date.hour,
        date.minute,
        date.second,
    });
}

test "Test DynamoDB request signing without region" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const method = "POST";
    const uri = "/";
    const query_string = "";
    const payload = "{}";
    const AWS_ACCESS_KEY_ID = "";
    const AWS_SECRET_ACCESS_KEY = "";
    const AWS_SESSION_TOKEN = "";
    const date = DateTime{
        .year = 2024,
        .month = 8,
        .day = 22,
        .hour = 13,
        .minute = 30,
        .second = 5,
    };
    var append_headers = std.ArrayList(std.http.Header).init(std.testing.allocator);
    defer append_headers.deinit();
    try append_headers.append(.{ .name = "Content-Type", .value = "application/x-amz-json-1.0" });
    try append_headers.append(.{ .name = "X-Amz-Target", .value = "DynamoDB_20120810.ListTables" });

    const headers = try signRequest(allocator, method, uri, query_string, payload, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_SESSION_TOKEN, date, append_headers.items, "localhost:4566");
    defer allocator.free(headers);

    for (headers) |header| {
        std.debug.print("{s}: {s}\n", .{ header.name, header.value });
    }
}
