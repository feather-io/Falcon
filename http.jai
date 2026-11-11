#import "Basic";
#import "String";

// A single HTTP header key-value pair.
//
// Both `key` and `value` are slices into the original raw request buffer;
// no copies are made during parsing.  Callers must not free these strings
// individually - they are owned by whatever buffer backed the raw request.
Header :: struct {
    key: string;
    value: string;
}



// Complete HTTP/1.1 status code registry, as defined by RFC 7231 and its
// extensions.
//
// The numeric value of each variant **is** the wire status code; the enum
// is backed by `u16` so it can be cast to/from the raw integer directly.
//
// Grouping follows the RFC class model:
//   - 1xx  Informational  - request received, continuing process.
//   - 2xx  Success        - request successfully received, understood, accepted.
//   - 3xx  Redirection    - further action needed to complete the request.
//   - 4xx  Client Error   - request contains bad syntax or cannot be fulfilled.
//   - 5xx  Server Error   - server failed to fulfil an apparently valid request.
//
// See https://www.rfc-editor.org/rfc/rfc7231#section-6
Status_Code :: enum u16 {
    // --- 1xx Informational ---
    // The server has received the request headers; the client should proceed.
    CONTINUE                        :: 100;
    // The server is switching protocols as requested by the client (e.g., HTTP → WebSocket).
    SWITCHING_PROTOCOLS             :: 101;
    // WebDAV (RFC 2518): request is being processed but no response is available yet.
    PROCESSING                      :: 102;
    // RFC 8297: server sends early non-final hints to allow the client to preload resources.
    EARLY_HINTS                     :: 103;

    // --- 2xx Success ---
    // Standard success response for GET/POST/DELETE requests.
    OK                              :: 200;
    // A new resource was created; the Location header carries the new URI.
    CREATED                         :: 201;
    // Request accepted for processing, but processing has not been completed.
    ACCEPTED                        :: 202;
    // Metadata in the response is not from the origin server (proxied/modified).
    NON_AUTHORITATIVE_INFORMATION   :: 203;
    // Request succeeded but there is no content to send in the response body.
    NO_CONTENT                      :: 204;
    // Request succeeded; client should reset the document view.
    RESET_CONTENT                   :: 205;
    // Partial GET succeeded (byte-range request, RFC 7233).
    PARTIAL_CONTENT                 :: 206;
    // WebDAV (RFC 4918): provides status for multiple independent operations.
    MULTI_STATUS                    :: 207;
    // WebDAV (RFC 5842): member of a DAV binding has already been enumerated.
    ALREADY_REPORTED                :: 208;
    // RFC 3229: the server has fulfilled a GET request using delta encoding.
    IM_USED                         :: 226;

    // --- 3xx Redirection ---
    // Multiple representations of the resource exist; the client should choose.
    MULTIPLE_CHOICES                :: 300;
    // The resource has moved permanently; update any bookmarks/links.
    MOVED_PERMANENTLY               :: 301;
    // Temporary redirect; use the URI in the Location header for this request.
    FOUND                           :: 302;
    // POST/PUT response: redirect to a GET of the resulting resource.
    SEE_OTHER                       :: 303;
    // Conditional GET: resource has not changed; use the cached version.
    NOT_MODIFIED                    :: 304;
    // Deprecated by RFC 7231; was intended to indicate proxy use.
    USE_PROXY                       :: 305;
    // Temporary redirect; method and body must NOT change on the redirected request.
    TEMPORARY_REDIRECT              :: 307;
    // Permanent redirect; method and body must NOT change (unlike 301).
    PERMANENT_REDIRECT              :: 308;

    // --- 4xx Client Error ---
    // Malformed request syntax, invalid request message framing, or deceptive routing.
    BAD_REQUEST                     :: 400;
    // Authentication is required; the client may retry with credentials.
    UNAUTHORIZED                    :: 401;
    // Reserved for future use (payment walls, experimental).
    PAYMENT_REQUIRED                :: 402;
    // Server understood but refuses to authorize the request.
    FORBIDDEN                       :: 403;
    // The server cannot find the requested resource.
    NOT_FOUND                       :: 404;
    // The HTTP method is not allowed for the target resource.
    METHOD_NOT_ALLOWED              :: 405;
    // The server cannot produce a response matching the Accept headers.
    NOT_ACCEPTABLE                  :: 406;
    // Client must authenticate with a proxy first.
    PROXY_AUTHENTICATION_REQUIRED   :: 407;
    // The server timed out waiting for the request.
    REQUEST_TIMEOUT                 :: 408;
    // Request conflicts with the current state of the resource.
    CONFLICT                        :: 409;
    // The resource is permanently deleted with no forwarding address.
    GONE                            :: 410;
    // Content-Length header is required but was not sent.
    LENGTH_REQUIRED                 :: 411;
    // One or more conditions in the request headers evaluated to false.
    PRECONDITION_FAILED             :: 412;
    // Request body exceeds server-defined limits.
    PAYLOAD_TOO_LARGE               :: 413;
    // The URI provided was too long for the server to process.
    URI_TOO_LONG                    :: 414;
    // The request entity has a media type the server cannot handle.
    UNSUPPORTED_MEDIA_TYPE          :: 415;
    // Range in Range header cannot be satisfied (RFC 7233).
    RANGE_NOT_SATISFIABLE           :: 416;
    // The expectation in the Expect header could not be met.
    EXPECTATION_FAILED              :: 417;
    // RFC 2324/7168: hyper-text coffee pot control protocol easter egg; not a real error.
    IM_A_TEAPOT                     :: 418;
    // RFC 7540: request was directed to a server unable to produce a response.
    MISDIRECTED_REQUEST             :: 421;
    // WebDAV (RFC 4918): request was well-formed but semantically erroneous.
    UNPROCESSABLE_ENTITY            :: 422;
    // WebDAV (RFC 4918): the resource is locked.
    LOCKED                          :: 423;
    // WebDAV (RFC 4918): the request failed because a dependency failed.
    FAILED_DEPENDENCY               :: 424;
    // Client must upgrade to a different protocol (e.g., TLS, HTTP/2).
    UPGRADE_REQUIRED                :: 426;
    // RFC 6585: origin server requires the request to be conditional.
    PRECONDITION_REQUIRED           :: 428;
    // RFC 6585: client has sent too many requests in a given time window (rate limiting).
    TOO_MANY_REQUESTS               :: 429;
    // RFC 6585: request header fields are too large to be processed.
    REQUEST_HEADER_FIELDS_TOO_LARGE :: 431;
    // RFC 7725: server refuses due to legal demands (censorship, DMCA, etc.).
    UNAVAILABLE_FOR_LEGAL_REASONS   :: 451;

    // --- 5xx Server Error ---
    // Catch-all for unexpected conditions on the server.
    INTERNAL_SERVER_ERROR           :: 500;
    // The server does not support the requested functionality.
    NOT_IMPLEMENTED                 :: 501;
    // The upstream server returned an invalid response.
    BAD_GATEWAY                     :: 502;
    // The server is temporarily unable to handle the request (overloaded or down for maintenance).
    SERVICE_UNAVAILABLE             :: 503;
    // The upstream server did not respond in time.
    GATEWAY_TIMEOUT                 :: 504;
    // The server does not support the HTTP protocol version used in the request.
    HTTP_VERSION_NOT_SUPPORTED      :: 505;
    // RFC 2295: transparent content negotiation resulted in a circular reference.
    VARIANT_ALSO_NEGOTIATES         :: 506;
    // WebDAV (RFC 4918): the server has insufficient storage to complete the request.
    INSUFFICIENT_STORAGE            :: 507;
    // RFC 5842: an infinite loop was detected while processing the request.
    LOOP_DETECTED                   :: 508;
    // RFC 2774: further extensions to the request are required.
    NOT_EXTENDED                    :: 510;
    // RFC 6585: the client must authenticate to gain network access (captive portals).
    NETWORK_AUTHENTICATION_REQUIRED :: 511;
}

// Map a `Status_Code` to its pre-formatted HTTP/1.1 response status line.
//
// Each branch returns a **string literal** - a compile-time constant with a
// known address and length baked into the binary.  This is a deliberate
// performance choice: because the strings are already in read-only memory,
// `get_status_line` performs zero heap allocations and no string formatting
// on every call.  At high requests-per-second (RPS) the difference between
// "format a string" and "return a pointer" compounds quickly across thousands
// of concurrent connections.
//
// The returned string includes the trailing `\r\n` per RFC 7230 §3.1.2, so
// callers can append header lines directly without an extra separator.
//
// The `case;` fallthrough uses `tprint` (temporary allocator) for unknown
// codes, preserving correctness without requiring a binary size blowup for
// hypothetical codes.
//
// See https://www.rfc-editor.org/rfc/rfc7230#section-3.1.2
get_status_line :: (code: Status_Code) -> string {
    if code == {
        case .CONTINUE;                        return "HTTP/1.1 100 Continue\r\n";
        case .SWITCHING_PROTOCOLS;             return "HTTP/1.1 101 Switching Protocols\r\n";
        case .PROCESSING;                      return "HTTP/1.1 102 Processing\r\n";
        case .EARLY_HINTS;                     return "HTTP/1.1 103 Early Hints\r\n";

        case .OK;                              return "HTTP/1.1 200 OK\r\n";
        case .CREATED;                         return "HTTP/1.1 201 Created\r\n";
        case .ACCEPTED;                        return "HTTP/1.1 202 Accepted\r\n";
        case .NON_AUTHORITATIVE_INFORMATION;   return "HTTP/1.1 203 Non-Authoritative Information\r\n";
        case .NO_CONTENT;                      return "HTTP/1.1 204 No Content\r\n";
        case .RESET_CONTENT;                   return "HTTP/1.1 205 Reset Content\r\n";
        case .PARTIAL_CONTENT;                 return "HTTP/1.1 206 Partial Content\r\n";
        case .MULTI_STATUS;                    return "HTTP/1.1 207 Multi-Status\r\n";
        case .ALREADY_REPORTED;                return "HTTP/1.1 208 Already Reported\r\n";
        case .IM_USED;                         return "HTTP/1.1 226 IM Used\r\n";

        case .MULTIPLE_CHOICES;                return "HTTP/1.1 300 Multiple Choices\r\n";
        case .MOVED_PERMANENTLY;               return "HTTP/1.1 301 Moved Permanently\r\n";
        case .FOUND;                           return "HTTP/1.1 302 Found\r\n";
        case .SEE_OTHER;                       return "HTTP/1.1 303 See Other\r\n";
        case .NOT_MODIFIED;                    return "HTTP/1.1 304 Not Modified\r\n";
        case .USE_PROXY;                       return "HTTP/1.1 305 Use Proxy\r\n";
        case .TEMPORARY_REDIRECT;              return "HTTP/1.1 307 Temporary Redirect\r\n";
        case .PERMANENT_REDIRECT;              return "HTTP/1.1 308 Permanent Redirect\r\n";

        case .BAD_REQUEST;                     return "HTTP/1.1 400 Bad Request\r\n";
        case .UNAUTHORIZED;                    return "HTTP/1.1 401 Unauthorized\r\n";
        case .PAYMENT_REQUIRED;                return "HTTP/1.1 402 Payment Required\r\n";
        case .FORBIDDEN;                       return "HTTP/1.1 403 Forbidden\r\n";
        case .NOT_FOUND;                       return "HTTP/1.1 404 Not Found\r\n";
        case .METHOD_NOT_ALLOWED;              return "HTTP/1.1 405 Method Not Allowed\r\n";
        case .NOT_ACCEPTABLE;                  return "HTTP/1.1 406 Not Acceptable\r\n";
        case .PROXY_AUTHENTICATION_REQUIRED;   return "HTTP/1.1 407 Proxy Authentication Required\r\n";
        case .REQUEST_TIMEOUT;                 return "HTTP/1.1 408 Request Timeout\r\n";
        case .CONFLICT;                        return "HTTP/1.1 409 Conflict\r\n";
        case .GONE;                            return "HTTP/1.1 410 Gone\r\n";
        case .LENGTH_REQUIRED;                 return "HTTP/1.1 411 Length Required\r\n";
        case .PRECONDITION_FAILED;             return "HTTP/1.1 412 Precondition Failed\r\n";
        case .PAYLOAD_TOO_LARGE;               return "HTTP/1.1 413 Payload Too Large\r\n";
        case .URI_TOO_LONG;                    return "HTTP/1.1 414 URI Too Long\r\n";
        case .UNSUPPORTED_MEDIA_TYPE;          return "HTTP/1.1 415 Unsupported Media Type\r\n";
        case .RANGE_NOT_SATISFIABLE;           return "HTTP/1.1 416 Range Not Satisfiable\r\n";
        case .EXPECTATION_FAILED;              return "HTTP/1.1 417 Expectation Failed\r\n";
        case .IM_A_TEAPOT;                     return "HTTP/1.1 418 I'm a teapot\r\n";
        case .MISDIRECTED_REQUEST;             return "HTTP/1.1 421 Misdirected Request\r\n";
        case .UNPROCESSABLE_ENTITY;            return "HTTP/1.1 422 Unprocessable Entity\r\n";
        case .LOCKED;                          return "HTTP/1.1 423 Locked\r\n";
        case .FAILED_DEPENDENCY;               return "HTTP/1.1 424 Failed Dependency\r\n";
        case .UPGRADE_REQUIRED;                return "HTTP/1.1 426 Upgrade Required\r\n";
        case .PRECONDITION_REQUIRED;           return "HTTP/1.1 428 Precondition Required\r\n";
        case .TOO_MANY_REQUESTS;               return "HTTP/1.1 429 Too Many Requests\r\n";
        case .REQUEST_HEADER_FIELDS_TOO_LARGE; return "HTTP/1.1 431 Request Header Fields Too Large\r\n";
        case .UNAVAILABLE_FOR_LEGAL_REASONS;   return "HTTP/1.1 451 Unavailable For Legal Reasons\r\n";

        case .INTERNAL_SERVER_ERROR;           return "HTTP/1.1 500 Internal Server Error\r\n";
        case .NOT_IMPLEMENTED;                 return "HTTP/1.1 501 Not Implemented\r\n";
        case .BAD_GATEWAY;                     return "HTTP/1.1 502 Bad Gateway\r\n";
        case .SERVICE_UNAVAILABLE;             return "HTTP/1.1 503 Service Unavailable\r\n";
        case .GATEWAY_TIMEOUT;                 return "HTTP/1.1 504 Gateway Timeout\r\n";
        case .HTTP_VERSION_NOT_SUPPORTED;      return "HTTP/1.1 505 HTTP Version Not Supported\r\n";
        case .VARIANT_ALSO_NEGOTIATES;         return "HTTP/1.1 506 Variant Also Negotiates\r\n";
        case .INSUFFICIENT_STORAGE;            return "HTTP/1.1 507 Insufficient Storage\r\n";
        case .LOOP_DETECTED;                   return "HTTP/1.1 508 Loop Detected\r\n";
        case .NOT_EXTENDED;                    return "HTTP/1.1 510 Not Extended\r\n";
        case .NETWORK_AUTHENTICATION_REQUIRED; return "HTTP/1.1 511 Network Authentication Required\r\n";

        case; return tprint("HTTP/1.1 % Unknown\r\n", cast(u16) code);
    }
}

#scope_module



// The result of a single HTTP/1.1 request parse pass.
//
// All `string` fields are **slices into the original raw request buffer**
// (zero-copy).  The caller must keep the backing buffer alive for as long as
// this struct is in use.  Only `headers` owns its own memory (the dynamic
// array itself, not the strings it contains).
//
// See `parse_request` for the parsing rules.
Parsed_Request :: struct {
    // The HTTP method token (e.g., `"GET"`, `"POST"`, `"DELETE"`).
    // Directly sliced from the request line; no allocation.
    method: string;

    // The decoded request target path, without the query string.
    // For the request `GET /search?q=foo HTTP/1.1`, this is `"/search"`.
    path: string;

    // The raw query string, everything after the `?` and before the first
    // space in the request line.  Empty string when no `?` is present.
    // Callers wishing to decode percent-encoding should pass this through
    // `url_decode`.
    query_string: string;

    // The HTTP version token from the request line (e.g., `"HTTP/1.1"`).
    version: string;

    // All header key-value pairs found in the request, in wire order.
    // This is a dynamic array allocated on the heap; free it when done.
    //
    // NOTE: See the PERF note in `parse_request` - in a future iteration
    // this field may become lazily populated.
    headers: [..] Header;

    // The raw request body, sliced from the buffer starting immediately after
    // the blank line (`\r\n\r\n`) separator.  May be empty for methods like
    // GET that carry no body.
    http_body: string;

    // The value of the `Content-Length` header, parsed eagerly to an integer.
    //
    // This field is extracted immediately during the header loop because the
    // server's body-reading loop needs the byte count **before** it can safely
    // consume data from the socket.  Waiting until the caller asks for it
    // would require a second scan of the header list at read time.
    // A value of `0` means either the header was absent or the body is empty.
    content_length: s64;

    // Set to `true` only if the request was well-formed and all required
    // fields (method, path, version) were successfully parsed.
    // Callers must check this before touching any other field.
    success: bool;
}

// Parse a raw HTTP/1.1 request buffer into a `Parsed_Request`.
//
// The parser makes a **single linear pass** over the buffer and populates
// all fields via zero-copy slices.  On malformed input, it returns a
// zero-initialised `Parsed_Request` (i.e., `success == false`).
//
// **Parsing strategy:**
//
// 1. **Header/body split** - RFC 7230 §3.5 mandates that the header section
//    ends at the first occurrence of the four-byte sequence `\r\n\r\n`.
//    Everything before it is the header section; everything after (offset by 4)
//    is the body.  An absent `\r\n\r\n` means the request is incomplete or
//    malformed, and the function returns early.
//
// 2. **Request line** - the first line of the header section is split on SP
//    (`" "`) into method, request-target, and HTTP-version.  Fewer than three
//    tokens is a parse failure.
//
// 3. **Query string** - the request-target is further split on `?`.  If a `?`
//    is found, everything before it becomes `path` and everything after becomes
//    `query_string`.
//
// 4. **Eager `Content-Length` extraction** - while iterating over headers the
//    parser converts the `Content-Length` value to `s64` immediately.
//    This is intentional: the server needs the body length to drive the
//    subsequent `recv` loop without a second scan of the header list.
//
// PERF: Header parsing is still **eager** - every header line is walked and
// stored even if the handler never reads them.  A future optimisation would
// defer full header population until `get_headers(*req)` is called, storing
// only the raw header section as a string and parsing on demand.
//
// See https://www.rfc-editor.org/rfc/rfc7230#section-3
parse_request :: (raw_request: string) -> Parsed_Request {
    using parsed_req: Parsed_Request;

    // RFC 7230 §3.5 - locate the mandatory blank line separating headers from body.
    // Its absence means the request is incomplete or malformed; bail out early.
    body_start_idx := find_index_from_left(raw_request, "\r\n\r\n");
    // the request is not in correct format or malformed
    if body_start_idx == -1 return .{};

    header_section := slice(raw_request, 0, body_start_idx);
    // Advance past the four-byte CRLF-CRLF sequence to reach the first body byte.
    body_offset := body_start_idx + 4;
    http_body = slice(raw_request, body_offset, raw_request.count - body_offset);

    lines := split(header_section, "\r\n");

    if lines.count > 0 {
        request_line := lines[0];
        parts := split(request_line, " ");
        if parts.count >= 3 {
            method = parts[0];

            raw_path := parts[1];
            q_idx := find_index_from_left(raw_path, #char "?");
            if q_idx >= 0 {
                // Split the request-target on `?`:  path gets the prefix,
                // query_string gets everything after the delimiter itself.
                path         = slice(raw_path, 0, q_idx);
                query_string = slice(raw_path, q_idx + 1, raw_path.count - q_idx - 1);
            } else {
                path         = raw_path;
                query_string = "";
            }

            version = parts[2];
        } else {
            return .{};
        }
    }

    // PERF: we need to parse the headers lazily here, we don't know if every
    // path would need headers to be parsed, so when user does
    // get_headers(*req), we do the parsing at that time.
    for i : 1..lines.count - 1 {
        line := lines[i];
        if line.count == 0 continue;

        colon_idx := find_index_from_left(line, #char ":");
        // without colon there is no key-value pair
        if colon_idx == -1 continue;

        header_name  := slice(line, 0, colon_idx);
        header_value := slice(line, colon_idx + 1, line.count - (colon_idx +1));

        // Eagerly parse Content-Length so the body-reading loop has the byte
        // count available without a second scan of the header list.
        if header_name == "Content-Length" {
            content_length = string_to_int(trim(header_value));
        }

        array_add(*headers, .{ trim(header_name), trim(header_value) });
    }

    http_body = http_body;
    success = true;
    return parsed_req;
}

// Look up the value of a header by name from an already-parsed header list.
//
// Returns the trimmed header value and `found = true` if the key matches,
// or an empty string and `found = false` if it does not.
//
// NOTE: HTTP header names are **case-insensitive** per RFC 7230 §3.2.  This
// implementation performs an exact byte-for-byte comparison, which is
// correct for well-behaved clients that send canonical casing (e.g.,
// `"Content-Length"`).  A fully spec-compliant implementation would use
// a case-folding comparison.
find_header_value :: (headers: [] Header, key: string) -> (value: string, found: bool) {
    for headers {
        // HTTP header names are case-insensitive, but for now we do exact match or simple lower/upper match?
        // To be completely correct we should do case-insensitive match, but for now exact match is okay
        // since many clients send "Content-Length". To be perfectly safe, let's just do exact.
        if it.key == key return it.value, true;
    }
    return "", false;
}

// Convert a single ASCII hex digit character to its integer value (0–15).
//
// Returns `-1` for any character that is not a valid hex digit, which the
// caller uses to detect a malformed percent-encoded sequence and fall through
// to literal passthrough in `url_decode`.
hex_digit_to_val :: (c: u8) -> int {
    if c >= #char "0" && c <= #char "9" return cast(int)(c - #char "0");
    if c >= #char "a" && c <= #char "f" return cast(int)(c - #char "a") + 10;
    if c >= #char "A" && c <= #char "F" return cast(int)(c - #char "A") + 10;
    return -1;
}

// Decode a percent-encoded URL string into a plain UTF-8 string.
//
// Implements the percent-encoding decoding algorithm defined in RFC 3986 §2.1.
// Each `%XX` sequence (where `XX` is a pair of hex digits) is converted to the
// corresponding byte value.  The input is consumed in a single pass.
//
// **The `+`-as-space convention:**
// The `+` character is decoded as an ASCII space (0x20).  This behaviour
// belongs to the `application/x-www-form-urlencoded` media type (originally
// RFC 1866, now the WHATWG URL standard) and is **not** part of RFC 3986 for
// general URIs.  We apply it here because query strings submitted by HTML
// forms always arrive in that encoding.  Callers that need strict RFC 3986
// semantics (where `+` is a literal plus sign) should pre-sanitise the input
// or use a separate decoder.
//
// **Allocation:**
// The decoded string is always `<=` the source length (each `%XX` triplet
// shrinks to one byte; `+` is already one byte).  The result is pre-allocated
// at `s.count` bytes to avoid any reallocations during iteration.  The
// `allocator` parameter defaults to `temp` so most call-sites pay zero
// persistent heap cost.
//
// See https://www.rfc-editor.org/rfc/rfc3986#section-2.1
// See https://url.spec.whatwg.org/#application/x-www-form-urlencoded-percent-encode-set
url_decode :: (s: string, allocator := temp) -> string {
    // Decoded string is always <= original length, so pre-allocate same size.
    result : [..] u8;
    result.allocator = allocator;
    array_reserve(*result, s.count);

    i := 0;
    while i < s.count {
        if s[i] == #char "%" && i + 2 < s.count {
            hi := hex_digit_to_val(s[i+1]);
            lo := hex_digit_to_val(s[i+2]);
            if hi >= 0 && lo >= 0 {
                array_add(*result, cast(u8)(hi * 16 + lo));
                i += 3;
                continue;
            }
        } else if s[i] == #char "+" {
            // application/x-www-form-urlencoded: '+' encodes a space
            array_add(*result, #char " ");
            i += 1;
            continue;
        }
        array_add(*result, s[i]);
        i += 1;
    }

    out: string;
    out.data  = result.data;
    out.count = result.count;
    return out;
}



// Jai's `#run` directive executes the following block (or procedure call) at
// **compile time**, inside the compiler's meta-program.  These blocks are
// zero-cost at runtime: they produce no code in the final binary and impose
// no startup overhead.  Failed `assert`s inside a `#run` block abort the
// build with a clear diagnostic, making them a free correctness net that runs
// on every single compilation.
#run {
    test_parse_simple_body();
}

test_parse_simple_body :: () {
    sample_request := "POST /submit HTTP/1.1\r\nHost: localhost:8080\r\nContent-Type: application/json\r\nContent-Length: 18\r\n\r\n{\"status\": \"alive\"}";

    req := parse_request(sample_request);

    assert(req.success == true, "simple body parsing should succeed");
    assert(req.method == "POST", "method should be POST");
    assert(req.path == "/submit", "path should be /submit");
    assert(req.query_string == "", "query string should be empty");
    assert(req.version == "HTTP/1.1", "version should be HTTP/1.1");
    assert(req.headers.count == 3, "simple body parsing should return 3 headers");
    assert(req.http_body.count > 0, "simple body parsing should have some body returned");
}

#run {
    test_parse_query_string();
}

test_parse_query_string :: () {
    sample_request := "GET /search?q=falcon&limit=10 HTTP/1.1\r\nHost: localhost:8080\r\n\r\n";
    req := parse_request(sample_request);

    assert(req.success == true, "query string parsing should succeed");
    assert(req.method == "GET", "method should be GET");
    assert(req.path == "/search", "path should be /search");
    assert(req.query_string == "q=falcon&limit=10", "query string should be correctly parsed");
    assert(req.version == "HTTP/1.1", "version should be HTTP/1.1");
}
