#import "Basic";
#import "String";
#import "Socket";
#if OS == .MACOS || OS == .LINUX {
    #import "POSIX";
}

#load "../module.jai"; 


test_parse_url :: () {
    print("\n--- Running test_parse_url ---\n");
    
    res, ok := parse_url("http://example.com");
    assert(ok.kind == .NONE);
    assert(res.scheme == "http");
    assert(res.host == "example.com");
    assert(res.port == 80);
    assert(res.path == "/");
    assert(res.query == "");
    
    res, ok = parse_url("https://api.github.com:8443/repos?q=test");
    assert(ok.kind == .NONE);
    assert(res.scheme == "https");
    assert(res.host == "api.github.com");
    assert(res.port == 8443);
    assert(res.path == "/repos");
    assert(res.query == "q=test");
    
    print("test_parse_url passed!\n");
}

test_build_request :: () {
    print("\n--- Running test_build_request ---\n");
    
    url, _ := parse_url("http://example.com/api/v1?token=123");
    opts: Fetch_Options;
    opts.method = .POST;
    opts.body = cast([] u8) "Hello World";
    
    h1: Header; h1.key = "Content-Type"; h1.value = "text/plain";
    opts.headers = .[h1];
    
    req_str := build_request_string(url, opts);
    assert(contains(req_str, "POST /api/v1?token=123 HTTP/1.1\r\n"), "Method/Path mismatch");
    assert(contains(req_str, "Host: example.com\r\n"), "Host mismatch");
    assert(contains(req_str, "Content-Length: 11\r\n"), "Content-Length mismatch");
    assert(contains(req_str, "Content-Type: text/plain\r\n"), "Header mismatch");
    assert(ends_with(req_str, "Hello World"), "Body mismatch");
    
    print("test_build_request passed!\n");
}

test_parse_response :: () {
    print("\n--- Running test_parse_response ---\n");
    
    raw := "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: 4\r\n\r\nCiao";
    res, ok := parse_fetch_response(raw);
    
    assert(ok.kind == .NONE);
    assert(res.status_code == 200);
    assert(res.reason_phrase == "OK");
    assert(res.headers.count == 2);
    assert(res.headers[0].key == "Content-Type");
    assert(res.headers[0].value == "text/html");
    assert(res.body == "Ciao");
    
    print("test_parse_response passed!\n");
}

test_falcon_fetch_sync :: () {
    print("\n--- Running test_falcon_fetch_sync ---\n");
    
    // example.com redirects or answers on 80.
    res := falcon_fetch("http://example.com", .{});
    if !res.success print("Blocking fetch failed: %\n", res.error_message);
    assert(res.success, "Blocking fetch should succeed");
    assert(res.status_code == 200, "Should get 200 OK");
    assert(res.body.count > 0, "Should have a body");
    assert(contains(res.body, "Example Domain"), "Body should contain Example Domain");
    
    print("test_falcon_fetch_sync passed!\n");
}

test_falcon_fetch_async :: () {
    print("\n--- Running test_falcon_fetch_async ---\n");
    
    // We run inside a fiber!
    res := falcon_fetch("http://example.com", .{});
    if !res.success print("Async fetch failed: %\n", res.error_message);
    assert(res.success, "Async fetch should succeed");
    assert(res.status_code == 200, "Should get 200 OK");
    assert(res.body.count > 0, "Should have a body");
    assert(contains(res.body, "Example Domain"), "Body should contain Example Domain");
    
    print("test_falcon_fetch_async passed!\n");
    // Exit to stop the block_on reactor
    exit(0);
}

main :: () {
    test_parse_url();
    test_build_request();
    test_parse_response();
    test_falcon_fetch_sync();
    
    print("\n--- Starting Feather for async fetch test ---\n");
    feather_block_on(test_falcon_fetch_async, 2);
    print("test_falcon_fetch_async passed!\n");
    
    print("\nAll client tests passed successfully!\n");
}
