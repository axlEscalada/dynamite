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
// const GLOBAL_ENDPOINT = "dynamodb.amazonaws.com";
const GLOBAL_ENDPOINT = "dynamodb.us-east-1.amazonaws.com";
const DEFAULT_REGION = "us-east-1";

pub fn signRequest(
    allocator: std.mem.Allocator,
    method: []const u8,
    uri: []const u8,
    query_string: []const u8,
    payload: []const u8,
    access_key: []const u8,
    secret_key: []const u8,
    session_token: []const u8,
    date_time: ?DateTime,
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

    var payload_hash: [32]u8 = undefined;
    crypto.hash.sha2.Sha256.hash(payload, &payload_hash, .{});
    const payload_hash_hex = try allocator.alloc(u8, 64);
    // defer allocator.free(payload_hash_hex);
    _ = try std.fmt.bufPrint(payload_hash_hex, "{s}", .{std.fmt.fmtSliceHexLower(&payload_hash)});
    // std.debug.print("Payload hash: {s}\n", .{payload_hash_hex});

    // Step 1: Create the canonical request
    const canonical_request = try createCanonicalRequest(allocator, method, uri, query_string, payload_hash_hex, GLOBAL_ENDPOINT, datetime, session_token);
    // defer allocator.free(canonical_request);
    // std.debug.print("Canonical req: \n {s}\n", .{canonical_request});
    // std.debug.print("END\n", .{});

    // Step 2: Create the string to sign
    const string_to_sign = try createStringToSign(allocator, datetime, canonical_request);
    // defer allocator.free(string_to_sign);
    // std.debug.print("String to sign: {s}\n", .{string_to_sign});

    // Step 3: Calculate the signature
    const signature = try calculateSignature(allocator, secret_key, date, string_to_sign);
    // defer allocator.free(signature);
    // std.debug.print("Signature: {s}\n", .{signature});

    // Step 4: Create the authorization header
    const auth_header = try createAuthorizationHeader(allocator, access_key, date, signature);
    // defer allocator.free(auth_header);

    var headers = try allocator.alloc(std.http.Header, 5);
    headers[0] = .{ .name = try allocator.dupe(u8, "Host"), .value = try allocator.dupe(u8, GLOBAL_ENDPOINT) };
    headers[1] = .{ .name = try allocator.dupe(u8, "x-amz-date"), .value = try allocator.dupe(u8, datetime) };
    headers[2] = .{ .name = try allocator.dupe(u8, "x-amz-security-token"), .value = try allocator.dupe(u8, if (session_token.len > 0) session_token else " ") };
    headers[3] = .{ .name = try allocator.dupe(u8, "x-amz-content-sha256"), .value = try allocator.dupe(u8, payload_hash_hex) };
    headers[4] = .{ .name = try allocator.dupe(u8, "authorization"), .value = try allocator.dupe(u8, auth_header) };

    for (headers) |entry| {
        std.debug.print("Adding header: {s}: {s}\n", .{ entry.name, entry.value });
        std.debug.print("Header name ptr: 0x{x}, value ptr: 0x{x}\n", .{ @intFromPtr(entry.name.ptr), @intFromPtr(entry.value.ptr) });
    }

    return headers;
}

fn createCanonicalRequest(
    allocator: std.mem.Allocator,
    method: []const u8,
    uri: []const u8,
    query_string: []const u8,
    payload_hash_hex: []const u8,
    host: []const u8,
    datetime: []const u8,
    session_token: []const u8,
) ![]u8 {
    var canonical = std.ArrayList(u8).init(allocator);
    // defer canonical.deinit();

    try canonical.appendSlice(method);
    try canonical.appendSlice("\n");
    try canonical.appendSlice(uri);
    try canonical.appendSlice("\n");
    try canonical.appendSlice(query_string);
    try canonical.appendSlice("\n");

    // Canonical headers (in alphabetical order, lowercase)
    try canonical.appendSlice("content-type:application/x-amz-json-1.0\n");
    try canonical.appendSlice("host:");
    try canonical.appendSlice(host);
    try canonical.appendSlice("\n");
    try canonical.appendSlice("x-amz-content-sha256:");
    try canonical.appendSlice(payload_hash_hex);
    try canonical.appendSlice("\n");
    try canonical.appendSlice("x-amz-date:");
    try canonical.appendSlice(datetime);
    try canonical.appendSlice("\n");
    try canonical.appendSlice("x-amz-security-token:");
    try canonical.appendSlice(session_token);
    try canonical.appendSlice("\n");
    try canonical.appendSlice("x-amz-target:DynamoDB_20120810.ListTables\n");
    try canonical.appendSlice("\n");

    // Signed headers (in alphabetical order, lowercase)
    try canonical.appendSlice("content-type;host;x-amz-content-sha256;x-amz-date;x-amz-security-token;x-amz-target\n");

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
    // std.debug.print("Key: {any}\n", .{k_date});

    const k_region = try hmacSha256(allocator, k_date, DEFAULT_REGION);
    defer allocator.free(k_region);
    // std.debug.print("Key: {any}\n", .{k_region});

    const k_service = try hmacSha256(allocator, k_region, SERVICE);
    defer allocator.free(k_service);
    // std.debug.print("Key: {any}\n", .{k_service});

    const k_signing = try hmacSha256(allocator, k_service, AWS4_REQUEST);
    defer allocator.free(k_signing);
    // std.debug.print("Key: {any}\n", .{k_signing});

    const signature = try hmacSha256(allocator, k_signing, string_to_sign);
    defer allocator.free(signature);
    // std.debug.print("Key: {any}\n", .{signature});

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
    std.debug.print("Auth header ptr: 0x{x}, len: {}\n", .{ @intFromPtr(result.ptr), result.len });

    return result;
}

// fn createAuthorizationHeader(
//     allocator: std.mem.Allocator,
//     access_key: []const u8,
//     date: []const u8,
//     signature: []const u8,
// ) ![]u8 {
//     const credential_scope = try fmt.allocPrint(allocator, "{s}/{s}/{s}/{s}", .{
//         date,
//         DEFAULT_REGION,
//         SERVICE,
//         AWS4_REQUEST,
//     });
//     defer allocator.free(credential_scope);
//
//     // Update the SignedHeaders to include all headers that are part of the signature
//     const signed_headers = "content-type;host;x-amz-content-sha256;x-amz-date;x-amz-security-token;x-amz-target";
//
//     return fmt.allocPrint(allocator, "{s} Credential={s}/{s}, SignedHeaders={s}, Signature={s}", .{ AWS4_HMAC_SHA256, access_key, credential_scope, signed_headers, signature });
// }

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
    const headers = try signRequest(allocator, method, uri, query_string, payload, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_SESSION_TOKEN, date);
    defer allocator.free(headers);

    for (headers) |header| {
        std.debug.print("{s}: {s}\n", .{ header.name, header.value });
    }
}
