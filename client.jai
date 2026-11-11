// Configuration options for an HTTP fetch request.
//
// Allows customization of the HTTP method, injection of custom headers,
// and attachment of a raw byte payload for POST/PUT requests.
Fetch_Options :: struct {
    // The HTTP method to use. Defaults to `GET`.
    method:  HTTP_Method = .GET;
    // An array of custom headers to append to the request.
    headers: [] Header;
    // The raw binary payload to send in the HTTP body.
    body:    [] u8;
}

// The parsed result of an HTTP fetch request.
//
// This struct encapsulates the entire HTTP response lifecycle. It contains the
// status code, parsed headers, and the full body payload as a string.
Fetch_Response :: struct {
    // The HTTP status code (e.g., 200, 404).
    status_code:   int;
    // The string representation of the status (e.g., "OK", "Not Found").
    reason_phrase: string;
    // The parsed HTTP headers returned by the server.
    headers:       [..] Header;
    // The raw body payload returned by the server.
    body:          string;

    // Legacy boolean success flag.
    // TODO: Deprecate in favor of the unified `Error` struct approach.
    success:       bool;
    // Legacy error message string.
    // TODO: Deprecate in favor of the unified `Error` struct approach.
    error_message: string;
}



// Execute an asynchronous HTTP request and return the parsed response.
//
// This is the primary entry point for the Falcon HTTP client.
//
// **Architecture**: This function acts as the central orchestrator. It parses the URL,
// performs a DNS resolution (which currently halts the OS thread-see `get_ip_from_host`),
// establishes a TCP connection, dispatches the constructed HTTP payload, and continuously reads
// from the socket until EOF.
//
// Feather aims for "Transparent Asynchrony", if this function is called inside a fiber,
// all the underlying `stream_connect`, `stream_write`, and `stream_read` calls will seamlessly
// yield the fiber instead of blocking the thread.
falcon_fetch :: (url: string, options: Fetch_Options = .{}) -> (Fetch_Response, Error) {
    res: Fetch_Response;

    parsed_url, err_parse := parse_url(url);
    guard(err_parse);

    addr, err_dns := get_ip_from_host(parsed_url.host, parsed_url.port);
    guard(err_dns);

    stream, err_conn := stream_connect(*addr);
    guard(err_conn);
    defer close_stream(*stream);

    req_str := build_request_string(parsed_url, options);

    req_slice: [] u8;
    req_slice.data = req_str.data;
    req_slice.count = req_str.count;

    err_write := stream_write(*stream, req_slice);
    guard(err_write);

    builder: String_Builder;
    init_string_builder(*builder);

    buffer: [4096] u8;
    // Read the response stream continuously until the server closes the connection (EOF).
    while true {
        buf_slice: [] u8;
        buf_slice.data = buffer.data;
        buf_slice.count = buffer.count;

        bytes_read, err_read := stream_read(*stream, buf_slice);
        guard(err_read);
        if bytes_read == 0 break; // EOF
        append(*builder, buffer.data, bytes_read);
    }

    raw_resp := builder_to_string(*builder);
    parsed, err_resp := parse_fetch_response(raw_resp);
    guard(err_resp);

    return parsed, ERR_NONE;
}



// A structured representation of a Uniform Resource Locator.
Parsed_Url :: struct {
    // The protocol scheme (e.g., "http", "https").
    scheme: string;
    // The domain name or IP address.
    host:   string;
    // The network port (defaults to 80 for HTTP and 443 for HTTPS).
    port:   u16;
    // The hierarchical path (e.g., "/api/v1/users").
    path:   string;
    // The query string parameters.
    query:  string;
}

// Parse a raw string URL into its constituent components.
//
// This extracts the scheme, host, port, path, and query parameters.
parse_url :: (url: string) -> (Parsed_Url, Error) {
    res: Parsed_Url;
    res.port = 80; // Default

    remainder := url;
    if starts_with(remainder, "http://") {
        res.scheme = "http";
        advance(*remainder, 7);
    } else if starts_with(remainder, "https://") {
        res.scheme = "https";
        res.port = 443;
        advance(*remainder, 8);
    } else {
        res.scheme = "http";
    }

    // Split at first '/'
    host_port_str: string;
    path_query_str: string;
    slash_idx := find_index_from_left(remainder, #char "/");
    if slash_idx != -1 {
        host_port_str = slice(remainder, 0, slash_idx);
        path_query_str = slice(remainder, slash_idx, remainder.count - slash_idx);
    } else {
        host_port_str = remainder;
        path_query_str = "/";
    }

    // Parse host and port
    colon_idx := find_index_from_left(host_port_str, #char ":");
    if colon_idx != -1 {
        res.host = slice(host_port_str, 0, colon_idx);
        port_str := slice(host_port_str, colon_idx + 1, host_port_str.count - colon_idx - 1);
        port_val, success := string_to_int(port_str);
        if success then res.port = cast(u16) port_val;
    } else {
        res.host = host_port_str;
    }

    // Parse path and query
    q_idx := find_index_from_left(path_query_str, #char "?");
    if q_idx != -1 {
        res.path = slice(path_query_str, 0, q_idx);
        res.query = slice(path_query_str, q_idx + 1, path_query_str.count - q_idx - 1);
    } else {
        res.path = path_query_str;
        res.query = "";
    }

    if res.host.count == 0 {
        return res, ERR_URL_PARSE;
    }

    return res, ERR_NONE;
}



// Resolve a hostname string to an IPv4 socket address.
//
// **Architecture Warning**: This currently relies on the POSIX `getaddrinfo` system call,
// which is strictly blocking and cannot be yielded by the Feather async reactor. Calling this
// will stall the underlying worker thread until DNS resolution completes.
//
// TODO: Implement or integrate a native asynchronous DNS resolver to prevent thread starvation.
get_ip_from_host :: (host: string, port: u16) -> (sockaddr_in, Error) {
    addr: sockaddr_in;
    addr.sin_family = AF_INET;
    addr.sin_port = htons(port);

    host_c := temp_c_string(host);
    hints: addrinfo;
    hints.ai_family = AF_INET;
    hints.ai_socktype = .SOCK_STREAM;

    result: *addrinfo;
    if getaddrinfo(host_c, null, *hints, *result) != 0 {
        return addr, ERR_DNS_RESOLUTION;
    }
    defer freeaddrinfo(result);

    if result != null {
        addr_in := cast(*sockaddr_in) result.ai_addr;
        addr.sin_addr = addr_in.sin_addr;
        return addr, ERR_NONE;
    }

    return addr, ERR_DNS_RESOLUTION;
}



// Construct the raw HTTP/1.1 request payload as a string.
//
// This serializes the method, path, headers, and body into a contiguous buffer
// formatted strictly according to the HTTP/1.1 specification.
//
// See [RFC 7230](https://datatracker.ietf.org/doc/html/rfc7230).
build_request_string :: (url: Parsed_Url, options: Fetch_Options) -> string {
    builder: String_Builder;
    init_string_builder(*builder);
    builder.allocator = temp;

    method_str := get_method_str(options.method);

    path_and_query := url.path;
    if !path_and_query {
        path_and_query = "/";
    }
    if url.query {
        print_to_builder(*builder, "% %?% HTTP/1.1\r\n", method_str, path_and_query, url.query);
    } else {
        print_to_builder(*builder, "% % HTTP/1.1\r\n", method_str, path_and_query);
    }

    print_to_builder(*builder, "Host: %\r\n", url.host);
    print_to_builder(*builder, "Connection: close\r\n");
    print_to_builder(*builder, "User-Agent: Falcon/1.0\r\n");

    if options.body.count > 0 {
        print_to_builder(*builder, "Content-Length: %\r\n", options.body.count);
    }

    for options.headers {
        print_to_builder(*builder, "%: %\r\n", it.key, it.value);
    }

    print_to_builder(*builder, "\r\n");

    if options.body.count > 0 {
        append(*builder, options.body.data, options.body.count);
    }

    return builder_to_string(*builder);
}

// Parse the raw bytes of an HTTP response into a structured `Fetch_Response`.
//
// This separates the headers from the body by searching for the `\r\n\r\n` boundary,
// parses the status line, and extracts all key-value header pairs.
parse_fetch_response :: (raw: string) -> (Fetch_Response, Error) {
    res: Fetch_Response;

    body_start_idx := find_index_from_left(raw, "\r\n\r\n");
    if body_start_idx == -1 {
        return res, ERR_MALFORMED_RESP;
    }

    header_section := slice(raw, 0, body_start_idx);
    body_offset := body_start_idx + 4;
    res.body = slice(raw, body_offset, raw.count - body_offset);

    lines := split(header_section, "\r\n");
    if lines.count == 0 {
        return res, ERR_MALFORMED_RESP;
    }

    status_line := lines[0];
    parts := split(status_line, " ");
    if parts.count >= 2 {
        code, ok := string_to_int(parts[1]);
        if ok {
            res.status_code = code;
        }
        if parts.count >= 3 {
            res.reason_phrase = parts[2]; // Might be truncated if reason has spaces, but good enough
        }
    } else {
        return res, ERR_MALFORMED_RESP;
    }

    for i: 1..lines.count - 1 {
        line := lines[i];
        if line.count == 0 continue;

        colon_idx := find_index_from_left(line, #char ":");
        if colon_idx == -1 continue;

        key := slice(line, 0, colon_idx);
        val := slice(line, colon_idx + 1, line.count - colon_idx - 1);
        array_add(*res.headers, .{ trim(key), trim(val) });
    }

    res.success = true;
    return res, ERR_NONE;
}
