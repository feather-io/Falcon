#import "Basic";
#import,dir "..";

main :: () {
    print("============================================\n");
    print(" 🦅 Falcon HTTP Server: REST API\n");
    print(" Listening on: http://127.0.0.1:8080\n");
    print(" Endpoints:\n");
    print("   GET    /api/users\n");
    print("   GET    /api/users/:id\n");
    print("   POST   /api/users\n");
    print("   DELETE /api/users/:id\n");
    print(" Press Ctrl+C to stop.\n");
    print("============================================\n");

    // 1. GET /api/users (Demonstrates query parameters: /api/users?role=admin)
    falcon_get("/api/users", (req: *Request, res: *Response) {
        role := req_query(req, "role");
        if role.count == 0  role = "all";

        json_payload := tprint("{\"status\": \"success\", \"filter\": \"%\", \"users\": [{\"id\": 1, \"name\": \"Alice\"}, {\"id\": 2, \"name\": \"Bob\"}]}\n", role);

        res_set_header(res, "Content-Type", "application/json");
        res_send(res, json_payload);
    });

    // 2. GET /api/users/:id (Demonstrates path parameter extraction)
    falcon_get("/api/users/:id", (req: *Request, res: *Response) {
        id := req_param(req, "id");

        if id == "404" {
            res.status_code = .NOT_FOUND;
            res_set_header(res, "Content-Type", "application/json");
            res_send(res, "{\"error\": \"User not found\"}\n");
            return;
        }

        json_payload := tprint("{\"id\": %, \"name\": \"User %\", \"role\": \"developer\"}\n", id, id);
        res_set_header(res, "Content-Type", "application/json");
        res_send(res, json_payload);
    });

    // 3. POST /api/users (Demonstrates reading request body)
    falcon_post("/api/users", (req: *Request, res: *Response) {
        res.status_code = .CREATED;
        res_set_header(res, "Content-Type", "application/json");

        response_body := tprint("{\"message\": \"User created successfully\", \"received_body\": %}\n", req.body);
        res_send(res, response_body);
    });

    // 4. DELETE /api/users/:id
    falcon_delete("/api/users/:id", (req: *Request, res: *Response) {
        id := req_param(req, "id");
        res_set_header(res, "Content-Type", "application/json");
        res_send(res, tprint("{\"message\": \"User % deleted\"}\n", id));
    });

    options: Falcon_Options;
    options.print_registered_routes = true;
    falcon_listen_and_serve(8080, options);
}
