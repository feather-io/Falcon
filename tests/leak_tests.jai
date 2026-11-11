#import "Basic"()(MEMORY_DEBUGGER=true);
#import "Thread";
#import "Socket";
#import "String";
#import,dir "..";

#if OS == .MACOS || OS == .LINUX {
    #import "POSIX";
}

SERVER_PORT :: 8080;
NUM_REQUESTS :: 1000;

main :: () {
    print("Starting Falcon Leak Test...\n");

    // Start the server in a background thread
    server_thread: Thread;
    thread_init(*server_thread, server_thread_proc);
    thread_start(*server_thread);

    // Wait a brief moment for the server to bind and start listening
    sleep_milliseconds(100);

    print("Server started. Sending % requests...\n", NUM_REQUESTS);

    // Run the HTTP client
    run_client();

    print("Finished sending requests. Waiting for server to process...\n");
    sleep_milliseconds(100); // Give server a moment to finish writing responses

    // Ideally we would cleanly shut down the server here, but for a leak test
    // we can just report memory leaks from the main thread.
    // Any heap allocations made during request processing that were not freed
    // will show up here.

    print("\n--- MEMORY LEAK REPORT ---\n");
    report_memory_leaks();
    print("--------------------------\n");
    print("If the report is empty, there are 0 heap memory leaks!\n");

    // TODO: To get a perfectly clean (0 bytes) memory leak report, we need to implement
    // a graceful shutdown mechanism for Falcon. Instead of hard exiting here, we should:
    // 1. Signal the server thread to stop accepting new connections (e.g. keep_polling = false)
    // 2. Wait for the server thread to finish via thread_wait()
    // 3. This will allow `defer falcon_shutdown()` and `feather_destroy()` to run, freeing the baseline memory.

    // Hard exit since the server thread is still blocking on accept
    exit(0);
}

server_thread_proc :: (t: *Thread) -> s64 {
    falcon_get("/ping", (req: *Request, res: *Response) {
        res_set_header(res, "X-Custom-Header", "Feather-Powered");
        res_send(res, "pong");
    });

    falcon_get("/build", (req: *Request, res: *Response) {
        res_set_header(res, "Content-Type", "text/html");
        builder := res_get_builder(res);
        if builder {
            append(builder, "<h1>Hello from Falcon Builder!</h1>");
            append(builder, "<p>Streaming chunks inline...</p>");
        }
    });

    falcon_post("/upload", (req: *Request, res: *Response) {
        res_send(res, tprint("Received body of size % bytes", req.body.count));
    });

    err := falcon_listen_and_serve(SERVER_PORT);
    if err.kind != .NONE {
        print("Server failed to start: %\n", err);
    }
    return 0;
}

run_client :: () {
    // 1. Send normal GET requests
    for i: 1..NUM_REQUESTS {
        sock := socket(AF_INET, .SOCK_STREAM, 0);
        if sock == INVALID_SOCKET break;

        addr: sockaddr_in;
        addr.sin_family = AF_INET;
        addr.sin_port = htons(SERVER_PORT);
        addr.sin_addr.s_addr = 0x0100007f; // 127.0.0.1
        if connect(sock, cast(*sockaddr)*addr, size_of(sockaddr_in)) != 0 {
            #if OS == .MACOS || OS == .LINUX { close(sock); }
            break;
        }

        req_str: string;
        if i % 2 == 0 {
            req_str = "GET /build HTTP/1.1\r\nHost: localhost\r\n\r\n";
        } else {
            req_str = "GET /ping HTTP/1.1\r\nHost: localhost\r\n\r\n";
        }
        send(sock, req_str.data, cast(u64) req_str.count, 0);

        buf: [4096] u8;
        bytes := recv(sock, buf.data, cast(u64) buf.count, 0);
        #if OS == .MACOS || OS == .LINUX { close(sock); }

        if i % 200 == 0 {
            print("  ... % GET requests completed\n", i);
        }
    }

    // 2. Test Body Streaming (8KB payload)
    {
        print("Testing Request Body Streaming (8KB)...\n");
        sock := socket(AF_INET, .SOCK_STREAM, 0);
        addr: sockaddr_in; addr.sin_family = AF_INET; addr.sin_port = htons(SERVER_PORT); addr.sin_addr.s_addr = 0x0100007f;
        connect(sock, cast(*sockaddr)*addr, size_of(sockaddr_in));

        // 8192 > 4096 buffer size, so it will force the stream_read loop
        payload := "POST /upload HTTP/1.1\r\nHost: localhost\r\nContent-Length: 8192\r\n\r\n";
        send(sock, payload.data, cast(u64) payload.count, 0);

        // send 8192 bytes of "A"
        big_body: [8192] u8;
        for i: 0..8191 big_body[i] = #char "A";
        send(sock, big_body.data, cast(u64) big_body.count, 0);

        buf: [1024] u8;
        bytes := recv(sock, buf.data, cast(u64) buf.count, 0);
        res_str := to_string(buf.data, bytes);
        if contains(res_str, "Received body of size 8192 bytes") {
            print("  -> 8KB streaming SUCCESS!\n");
        } else {
            print("  -> 8KB streaming FAILED! Response: %\n", res_str);
        }
        #if OS == .MACOS || OS == .LINUX { close(sock); }
    }

    // 3. Test 413 Payload Too Large (2MB payload metadata)
    {
        print("Testing 413 Payload Too Large (2MB request)...\n");
        sock := socket(AF_INET, .SOCK_STREAM, 0);
        addr: sockaddr_in; addr.sin_family = AF_INET; addr.sin_port = htons(SERVER_PORT); addr.sin_addr.s_addr = 0x0100007f;
        connect(sock, cast(*sockaddr)*addr, size_of(sockaddr_in));

        payload := "POST /upload HTTP/1.1\r\nHost: localhost\r\nContent-Length: 2097152\r\n\r\n";
        send(sock, payload.data, cast(u64) payload.count, 0);

        buf: [1024] u8;
        bytes := recv(sock, buf.data, cast(u64) buf.count, 0);
        res_str := to_string(buf.data, bytes);
        if contains(res_str, "413 Payload Too Large") {
            print("  -> 413 check SUCCESS!\n");
        } else {
            print("  -> 413 check FAILED! Response: %\n", res_str);
        }
        #if OS == .MACOS || OS == .LINUX { close(sock); }
    }
}
