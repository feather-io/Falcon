#import "Basic";
#import,dir "..";

main :: () {
    PORT : u16 = 8080;

    print("====================================================\n");
    print(" 🦅 Falcon Benchmark Server\n");
    print(" Listening on: http://127.0.0.1:%\n", PORT);
    print(" Benchmark with:\n");
    print("   wrk -t4 -c100 -d10s http://127.0.0.1:%/\n", PORT);
    print("====================================================\n");

    // Ultra-low overhead plaintext endpoint for maximum throughput testing
    falcon_get("/", (req: *Request, res: *Response) {
        res_send(res, "OK");
    });

    options: Falcon_Options;
    // Disable per-request terminal logs for benchmarking to prevent stdout bottlenecks
    options.do_logging = false;
    options.print_registered_routes = false;

    falcon_listen_and_serve(PORT, options);
}
