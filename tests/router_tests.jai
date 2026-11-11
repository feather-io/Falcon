#import "Basic";
#import "String";
#import "Pool";
#load "../http.jai";
#load "../router.jai";

dummy_handler :: (req: *Request, res: *Response) {}

test_router_insert_and_find :: () {
    print("\n--- Running test_router_insert_and_find ---\n");
    router: Router;
    set_allocators(*router.pool);

    // Test 1: Insert into empty router
    router_insert(*router, "GET/", .{ .GET, dummy_handler });

    handler, found := router_find(*router, "GET/");
    assert(found, "GET/ should be found");
    assert(handler.type == .GET, "Handler should be GET");

    // Test 2: Insert that adds a completely new child from root
    router_insert(*router, "POST/upload", .{ .POST, dummy_handler });
    handler, found = router_find(*router, "POST/upload");
    assert(found, "POST/upload should be found");

    // Test 3: Insert that splits a node
    // Currently we have "GET/" and "POST/upload".
    // Let's insert "GET/ping"
    router_insert(*router, "GET/ping", .{ .GET, dummy_handler });
    handler, found = router_find(*router, "GET/ping");
    assert(found, "GET/ping should be found");

    // Re-verify GET/ still works after split
    handler, found = router_find(*router, "GET/");
    assert(found, "GET/ should still be found after split");

    // Test 4: Insert another branch that splits at the same level
    router_insert(*router, "GET/pong", .{ .GET, dummy_handler });
    handler, found = router_find(*router, "GET/pong");
    assert(found, "GET/pong should be found");

    // Test 5: Find a route that doesn't exist
    _, found = router_find(*router, "GET/pi");
    assert(!found, "GET/pi should not be found");

    _, found = router_find(*router, "DELETE/nonexistent");
    assert(!found, "DELETE/nonexistent should not be found");

    print("  -> Passed!\n");
}

test_router_print :: () {
    print("\n--- Running test_router_print ---\n");
    router: Router;
    set_allocators(*router.pool);

    // Testing empty print
    router_print(*router);

    // Testing populated print
    router_insert(*router, "GET/home", .{ .GET, dummy_handler });
    router_insert(*router, "GET/home/dashboard", .{ .GET, dummy_handler });
    router_print(*router);

    print("  -> Passed!\n");
}

test_res_helpers :: () {
    print("\n--- Running test_res_helpers ---\n");

    res: Response;

    // res_set_header
    res_set_header(*res, "Content-Type", "application/json");
    assert(res.headers.count == 1, "Header count should be 1");
    assert(res.headers[0].key == "Content-Type", "Key mismatch");
    assert(res.headers[0].value == "application/json", "Value mismatch");

    // res_send
    res_send(*res, "Hello World");
    assert(res.body_mode == .STATIC_STRING, "Body mode should be STATIC_STRING");
    assert(res.body_static == "Hello World", "Body static mismatch");

    // Test double send protection (should print warning and not change mode)
    res_send(*res, "Second Send");
    assert(res.body_static == "Hello World", "Body should not be overwritten");

    // res_get_builder
    res2: Response;
    builder := res_get_builder(*res2);
    assert(builder != null, "Builder should not be null");
    assert(res2.body_mode == .BUILDER, "Body mode should be BUILDER");

    // Test double builder request protection
    builder2 := res_get_builder(*res2);
    assert(builder2 == null, "Second builder request should return null");

    // Test builder after res_send
    res3: Response;
    res_send(*res3, "First send");
    builder3 := res_get_builder(*res3);
    assert(builder3 == null, "Builder request after send should return null");

    print("  -> Passed!\n");
}

test_get_method_str :: () {
    print("\n--- Running test_get_method_str ---\n");

    assert(get_method_str(.GET) == "GET", "GET mismatch");
    assert(get_method_str(.POST) == "POST", "POST mismatch");
    assert(get_method_str(.PUT) == "PUT", "PUT mismatch");
    assert(get_method_str(.DELETE) == "DELETE", "DELETE mismatch");
    assert(get_method_str(.PATCH) == "PATCH", "PATCH mismatch");
    assert(get_method_str(.OPTIONS) == "OPTIONS", "OPTIONS mismatch");
    assert(get_method_str(.HEAD) == "HEAD", "HEAD mismatch");
    assert(get_method_str(.TRACE) == "TRACE", "TRACE mismatch");
    assert(get_method_str(.CONNECT) == "CONNECT", "CONNECT mismatch");

    print("  -> Passed!\n");
}

test_router_dynamic_params :: () {
    print("\n--- Running test_router_dynamic_params ---\n");
    router: Router;
    set_allocators(*router.pool);

    // Register parameter routes
    router_insert(*router, "GET/users/:id", .{ .GET, dummy_handler });
    router_insert(*router, "GET/users/:id/posts/:post_id", .{ .GET, dummy_handler });
    router_insert(*router, "GET/users/profile", .{ .GET, dummy_handler });

    req: Request;

    // Test 1: Literal match takes precedence over PARAM
    req.params_count = 0;
    handler, found := router_find(*router, "GET/users/profile", *req);
    assert(found, "GET/users/profile should be found");
    assert(req.params_count == 0, "Profile should not capture params");

    // Test 2: Single PARAM extraction
    req.params_count = 0;
    handler, found = router_find(*router, "GET/users/42", *req);
    assert(found, "GET/users/42 should be found");
    assert(req.params_count == 1, "Should capture 1 param");
    assert(req_param(*req, "id") == "42", "id should be 42");

    // Test 3: Multiple PARAM extraction
    req.params_count = 0;
    handler, found = router_find(*router, "GET/users/7/posts/99", *req);
    assert(found, "GET/users/7/posts/99 should be found");
    assert(req.params_count == 2, "Should capture 2 params");
    assert(req_param(*req, "id") == "7", "id should be 7");
    assert(req_param(*req, "post_id") == "99", "post_id should be 99");

    // Test 4: Missing parameter segment
    req.params_count = 0;
    _, found = router_find(*router, "GET/users/", *req);
    assert(!found, "GET/users/ should fail (no id provided)");

    print("  -> Passed!\n");
}

test_router_wildcard :: () {
    print("\n--- Running test_router_wildcard ---\n");
    router: Router;
    set_allocators(*router.pool);

    router_insert(*router, "GET/static/*", .{ .GET, dummy_handler });
    router_insert(*router, "GET/static/favicon.ico", .{ .GET, dummy_handler });

    req: Request;

    // Test 1: Literal match wins
    handler, found := router_find(*router, "GET/static/favicon.ico", *req);
    assert(found, "GET/static/favicon.ico should be found");
    assert(req.wildcard == "", "favicon.ico should match literal, not wildcard");

    // Test 2: Wildcard match
    handler, found = router_find(*router, "GET/static/assets/logo.png", *req);
    assert(found, "Wildcard path should be found");
    assert(req.wildcard == "assets/logo.png", "Wildcard should capture rest of path");

    // Test 3: Wildcard matching empty (if it requires at least one char, wait, our implementation captures empty if it's there? Let's see: path remaining)
    handler, found = router_find(*router, "GET/static/", *req);
    assert(found, "Wildcard empty path should be found");
    assert(req.wildcard == "", "Wildcard empty capture");

    print("  -> Passed!\n");
}

test_req_query :: () {
    print("\n--- Running test_req_query ---\n");
    req: Request;

    // Test 1: Populated query string
    req.query_string = "q=falcon&limit=10&sort=asc";
    assert(req_query(*req, "q") == "falcon", "Should find q=falcon");
    assert(req_query(*req, "limit") == "10", "Should find limit=10");
    assert(req_query(*req, "sort") == "asc", "Should find sort=asc");

    // Test 2: Missing key
    assert(req_query(*req, "missing") == "", "Should return empty for missing key");
    assert(req_query(*req, "lim") == "", "Should not match prefix");

    // Test 3: Empty query string
    req.query_string = "";
    assert(req_query(*req, "q") == "", "Should handle empty query string");

    // Test 4: Single key
    req.query_string = "search=jai";
    assert(req_query(*req, "search") == "jai", "Should handle single key without &");

    // Test 5: Key at end
    req.query_string = "a=1&b=2";
    assert(req_query(*req, "b") == "2", "Should handle key at end");

    print("  -> Passed!\n");
}

test_url_decode :: () {
    print("\n--- Running test_url_decode ---\n");

    assert(url_decode("hello%20world") == "hello world", "Should decode %20 to space");
    assert(url_decode("John%26Doe") == "John&Doe", "Should decode %26 to &");
    assert(url_decode("hello+world") == "hello world", "Should decode + to space");
    assert(url_decode("no_encoding") == "no_encoding", "Should passthrough normal string");
    assert(url_decode("%GG") == "%GG", "Should handle invalid hex");
    assert(url_decode("") == "", "Should handle empty string");
    assert(url_decode("%2F") == "/", "Should decode %2F to /");

    print("  -> Passed!\n");
}

main :: () {
    print("Starting Falcon Router Tests...\n");
    test_router_insert_and_find();
    test_router_dynamic_params();
    test_router_wildcard();
    test_req_query();
    test_url_decode();
    test_router_print();
    test_res_helpers();
    test_get_method_str();
    print("\nAll router tests passed!\n");
}
