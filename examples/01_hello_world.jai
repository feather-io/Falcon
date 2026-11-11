#import "Basic";
#import,dir "..";

main :: () {
    print("============================================\n");
    print(" 🦅 Falcon HTTP Server: Hello World\n");
    print(" Listening on: http://127.0.0.1:8080\n");
    print(" Test with:    curl http://127.0.0.1:8080/\n");
    print(" Press Ctrl+C to stop.\n");
    print("============================================\n");

    // Register a simple GET route
    falcon_get("/", (req: *Request, res: *Response) {
        res_set_header(res, "X-Powered-By", "Falcon/Jai");
        res_send(res, "Hello, World! Greetings from Falcon.\n");
    });

    // Start server on port 8080
    options: Falcon_Options;
    options.print_registered_routes = true;
    falcon_listen_and_serve(8080, options);
}
