#import "Socket";

#if OS == .MACOS || OS == .LINUX {
    #import "POSIX";
}

// Everything related to the HTTP/1.1 protocol
#load "http.jai";
#load "router.jai";
#import "Feather";


#add_context client_fd: Socket;
#add_context listen_fd: Socket;

Falcon_Options :: struct {
    do_logging := true;
    print_registered_routes := false;
}

Falcon_Server :: struct {
    router: Router;
}

// Register a handler for an HTTP GET request on `path`.
//
// Lazily initializes the global `Falcon_Server` instance if it has not been
// created yet. The method name is prepended to `path` before insertion so that
// routes with identical paths but different HTTP methods occupy completely
// separate branches of the Radix Tree, yielding O(K) method+path routing
// (where K is the length of the key, not the number of registered routes).
// For example, `/users` becomes the key `"GET/users"` in the tree.
falcon_get :: (path: string, handler: Falcon_Handler) {
    init_falcon_server_if_needed();
    radix_path := tprint("%%", get_method_str(.GET), path);
    router_insert(*fs.router, radix_path, .{ .GET, handler });
}

// Register a handler for an HTTP POST request on `path`.
falcon_post :: (path: string, handler: Falcon_Handler) {
    init_falcon_server_if_needed();
    radix_path := tprint("%%", get_method_str(.POST), path);
    router_insert(*fs.router, radix_path, .{ .POST, handler });
}

// Register a handler for an HTTP PUT request on `path`.
falcon_put :: (path: string, handler: Falcon_Handler) {
    init_falcon_server_if_needed();
    radix_path := tprint("%%", get_method_str(.PUT), path);
    router_insert(*fs.router, radix_path, .{ .PUT, handler });
}

// Register a handler for an HTTP DELETE request on `path`.
falcon_delete :: (path: string, handler: Falcon_Handler) {
    init_falcon_server_if_needed();
    radix_path := tprint("%%", get_method_str(.DELETE), path);
    router_insert(*fs.router, radix_path, .{ .DELETE, handler });
}

// Register a handler for an HTTP PATCH request on `path`.
falcon_patch :: (path: string, handler: Falcon_Handler) {
    init_falcon_server_if_needed();
    radix_path := tprint("%%", get_method_str(.PATCH), path);
    router_insert(*fs.router, radix_path, .{ .PATCH, handler });
}

// Register a handler for an HTTP OPTIONS request on `path`.
falcon_options :: (path: string, handler: Falcon_Handler) {
    init_falcon_server_if_needed();
    radix_path := tprint("%%", get_method_str(.OPTIONS), path);
    router_insert(*fs.router, radix_path, .{ .OPTIONS, handler });
}

// Register a handler for an HTTP HEAD request on `path`.
falcon_head :: (path: string, handler: Falcon_Handler) {
    init_falcon_server_if_needed();
    radix_path := tprint("%%", get_method_str(.HEAD), path);
    router_insert(*fs.router, radix_path, .{ .HEAD, handler });
}

// Register a handler for an HTTP TRACE request on `path`.
falcon_trace :: (path: string, handler: Falcon_Handler) {
    init_falcon_server_if_needed();
    radix_path := tprint("%%", get_method_str(.TRACE), path);
    router_insert(*fs.router, radix_path, .{ .TRACE, handler });
}

// Register a handler for an HTTP CONNECT request on `path`.
falcon_connect :: (path: string, handler: Falcon_Handler) {
    init_falcon_server_if_needed();
    radix_path := tprint("%%", get_method_str(.CONNECT), path);
    router_insert(*fs.router, radix_path, .{ .CONNECT, handler });
}

// Bind to `port`, start the Feather runtime, and block until the server shuts down.
//
// The accept loop is driven by a `Feather_Acceptor` - a **stackless Future**.
// Unlike connection fibers (which each receive a full 512 KB fiber stack so they
// can suspend mid-handler), the acceptor never needs to yield at an arbitrary
// point: it only ever waits for the OS to signal that a new TCP connection is
// ready. A stackless Future is therefore the right primitive here - it runs its
// `poll` callback directly on the reactor thread, avoiding the overhead of a
// dedicated fiber stack for work that is purely I/O-event driven.
//
// Every accepted connection is handed off to `connection_fiber_fn`, which runs
// on its own fiber so that blocking reads inside the handler do not stall the
// reactor.
falcon_listen_and_serve :: (port: u16 = 80, options: Falcon_Options = .{}) -> Error {
    Runtime_Context = context;

    // we will start handling SIGINT signal for graceful shutdown of the server
    action_signint: sigaction_t;
    // clear junk memory in signal mask
    sigemptyset(*action_signint.sa_mask);
    action_signint.sa_handler = handle_sigint;
    sigaction(SIGINT, *action_signint, null);

    // Initializing feather and falcon resources.
    init_falcon_server_if_needed();
    feather_main();
    defer falcon_shutdown();

    if options.print_registered_routes router_print(*fs.router);

    // Stackless acceptor: no fiber stack is allocated for this Future.
    // It only polls `accept_async` and immediately delegates real work to fibers.
    acceptor_fut := New(Feather_Acceptor);
    lis, err := setup_tcp_listener(port);
    if err.kind != .NONE return err;
    acceptor_fut.listener = lis;
    acceptor_fut.poll = acceptor_poll_fn;

    spawn_injected(acceptor_fut);

    feather_run(*Keep_Polling);

    return ERR_NONE;
}

// Release all resources owned by Falcon and tear down the Feather runtime.
falcon_shutdown :: () {
    feather_destroy();

    release(*fs.router.pool);
    free(fs);
}


// --
#scope_module

fs: *Falcon_Server;

// used for graceful shutdown only
Runtime_Context: type_of(context);
Keep_Polling := true;

handle_sigint :: (sig: s32) #c_call {
    push_context Runtime_Context {
        Keep_Polling = false;
    }
}

Feather_Acceptor :: struct {
    #as using base: Future;
    listener: TcpListener;
    // Monotonically incrementing counter used for round-robin reactor selection.
    next_reactor: s32;
}

// Poll for incoming TCP connections and dispatch each one to a connection fiber.
//
// **Round-robin load balancing**: `next_reactor % reactors.count` spreads
// accepted connections evenly across all worker threads. Because `next_reactor`
// is private to this single acceptor Future (which itself runs on one reactor),
// the increment requires no atomic or lock - the acceptor is the only writer.
//
// When `accept_async` returns `.PENDING`, the OS has no connection queued yet;
// returning `.PENDING` here suspends the Future and returns control to the
// reactor, which will re-poll once `epoll`/`kqueue` signals readability on the
// listener socket.
acceptor_poll_fn :: (base: *Future) -> Poll_State {
    self := cast(*Feather_Acceptor) base;
    while true {
        stream, status := accept_async(*self.listener);
        if status == {
            case .PENDING; return .PENDING;
            case .READY; {
                new_ctx := context;
                new_ctx.client_fd = stream.fd;

                // Round-robin load balancing across all reactors
                new_ctx.reactor_index = self.next_reactor % cast(s32) context.feather.reactors.count;
                self.next_reactor += 1;

                push_context new_ctx {
                    fiber_spawn_injected(connection_fiber_fn);
                }
            }
            case; {
                return .ERROR;
            }
        }
    }
    return .PENDING;
}

// Manage the full lifecycle of a single HTTP/1.1 connection: read, parse, route, respond.
//
// **Zero-heap-allocation strategy for typical requests**
// Each request context is backed by a 64 KB `Temporary_Storage` buffer that
// lives directly on the fiber's stack. Because Feather pre-allocates 512 KB
// per fiber, this consumes only 64 KB of already-reserved memory - no `malloc`
// call is issued. For the ~99 % of requests whose combined headers and body fit
// inside 64 KB, the entire request is handled without touching the heap.
// For the rare request that overflows (e.g., a large file upload),
// `Temporary_Storage` automatically allocates an overflow page on the heap.
// The `defer reset_temporary_storage` at the top of the per-request block
// frees those overflow pages the instant the response is sent.
//
// **Content-Length-driven body reading**
// HTTP/1.1 framing requires the server to read exactly `Content-Length` bytes
// as the body. The first `stream_read` call captures whatever the OS already
// buffered alongside the headers (common for small POST bodies). The subsequent
// loop issues additional `stream_read` calls in 4 KB chunks until
// `bytes_so_far == content_length`, ensuring correctness for bodies that span
// multiple TCP segments.
//
// **Two-write response strategy (CPU vs. memory trade-off)**
// The response is flushed in two separate `stream_write` calls: one for the
// headers and one for the body. This avoids copying the entire response body
// into a single contiguous buffer just so that headers can be prepended.
// For large response bodies (e.g., a multi-megabyte JSON payload or static
// file), the savings are significant - the body bytes are written directly
// from wherever they already live (`body_static` or the builder's pages).
// The trade-off is one additional syscall per response; the memory win almost
// always outweighs the syscall cost at typical payload sizes.
connection_fiber_fn :: () {
    fd := context.client_fd;
    stream: TcpStream;
    stream.fd = fd;
    defer {
        shutdown(stream.fd, .RDWR);
        close(stream.fd);
    }

    buffer: [4096] u8;

    while true {
        bytes_read, err := stream_read(*stream, buffer);
        if err.kind != .NONE || bytes_read == 0 {
            break; // Client closed connection or error occurred
        }

        // Here is the exact math of what's happening under the hood:
        // In  Feather2/fiber.jai , the default  stack_size  for a new fiber is 512KB ( 524288  bytes).
        // When the fiber starts, that entire 512KB chunk of memory is allocated for it.

        // When you declare  ts_data: [65536] u8;  inside  connection_fiber_fn , it just bumps the stack
        // pointer up by 64KB.

        // - You still only allocated 512KB total for the fiber.
        // - 64KB of it is now being actively used as the temporary storage buffer.
        // - The remaining 448KB is left over for your regular local variables and function calls.
        //
        // ----- Thinking about reducing this 64KB stack buffer later...
        // Instead of hoarding 64KB on the stack, we reduce it to 4KB or 8KB ( [4096] u8 ).
        // - Why it's smart: 99% of typical HTTP requests (headers, paths, and small JSON bodies) fit
        // perfectly within 4KB. For these, the server operates with zero heap allocations.
        // - The fallback: For the 1% of requests that are massive (e.g., a file upload or a huge database
        // query response), Jai's  Temporary_Storage  is smart enough to dynamically allocate a temporary
        // "overflow page" on the heap. When the request finishes, our  defer  cleans it up instantly. You
        // get the best of both worlds: zero-alloc for normal traffic, and perfect safety for edge cases,
        // while barely touching your fiber's call stack.
        Basic :: #import "Basic";
        ts: Basic.Temporary_Storage_Paged_Alloc;
        ts_data: [65536] u8; // 64KB stack buffer for temp storage
        ts.data = ts_data.data;
        ts.size = ts_data.count;

        req_ctx := context;
        req_ctx.temporary_storage = cast(*Temporary_Storage) *ts;
        req_ctx.allocator = temp;
        push_context req_ctx {
            // By resetting the whole temp storage on defer, we clean up any overflow pages
            // if the request exceeded our 64KB stack buffer.
            defer Basic.reset_temporary_storage(context.temporary_storage);

            raw: string;
            raw.data = buffer.data;
            raw.count = bytes_read;

            // TODO : handle malformed request parsing
            request := parse_request(raw);

            if request.content_length > MAX_BODY_SIZE {
                write_413(*stream);
                break;
            }

            body_builder: String_Builder;
            body_builder.allocator = temp;
            append(*body_builder, request.http_body);

            bytes_so_far := request.http_body.count;

            chunk_buf: [4096] u8;
            while bytes_so_far < request.content_length {
                remaining := request.content_length - bytes_so_far;
                to_read   := min(remaining, chunk_buf.count);

                chunk_slice: [] u8;
                chunk_slice.data  = chunk_buf.data;
                chunk_slice.count = to_read;

                chunk_bytes_read, err_chunk := stream_read(*stream, chunk_slice);
                if err_chunk.kind != .NONE || chunk_bytes_read == 0 {
                    break;
                }

                chunk_str: string;
                chunk_str.data = chunk_buf.data;
                chunk_str.count = chunk_bytes_read;
                append(*body_builder, chunk_str);

                bytes_so_far += chunk_bytes_read;
            }

            full_body := builder_to_string(*body_builder);
            hreq : Request = .{ path = request.path, headers = request.headers, query_string = request.query_string };
            handler_info, found := router_find(*fs.router, tprint("%%", request.method, request.path), *hreq);

            if !found || request.method != get_method_str(handler_info.type) {
                err_404 := write_404(*stream);
                if err_404.kind != .NONE {
                    break;
                }
            } else {
                hreq.body = full_body;
                hresp : Response = .{};

                // execture the handler funtion given by the caller
                handler_info.fn(*hreq, *hresp);

                // post-processing response -- header addition
                header_builder: String_Builder;
                header_builder.allocator = temp;

                // defaults to 200 OK
                append(*header_builder, get_status_line(hresp.status_code));

                // decide the Content-Type
                has_content_type := false;
                for h: hresp.headers {
                    if h.key == "Content-Type"  has_content_type = true;
                    print_to_builder(*header_builder, "%: %\r\n", h.key, h.value);
                }
                if !has_content_type {
                    append(*header_builder, "Content-Type: text/plain\r\n");
                }

                // decide Content-Length, if it's a static string we take body_static.count
                // else builder length
                body_length: s64 = 0;
                if hresp.body_mode == .STATIC_STRING {
                    body_length = hresp.body_static.count;
                } else if hresp.body_mode == .BUILDER {
                    body_length = builder_string_length(*hresp.body_builder);
                }
                print_to_builder(*header_builder, "Content-Length: %\r\n\r\n", body_length);

                // TRADE-OFF: CPU Time vs. Memory Allocation
                // here we are doing 2 write calls to socket, one for headers and
                // one for body. If we have a massive response we don't have to copy the entire
                // response byte-by-byte into that new buffer just so the headers can sit at the front!

                // write response to sock stream
                header_str := builder_to_string(*header_builder);
                err_header := stream_write(*stream, cast([] u8) header_str);
                if err_header.kind != .NONE {
                    break;
                }

                // header is written to the sock stream, time to write the body.
                if request.method != "HEAD" {
                    if hresp.body_mode == .STATIC_STRING {
                        stream_write(*stream, cast([] u8) hresp.body_static);
                    } else if hresp.body_mode == .BUILDER {
                        body_str := builder_to_string(*hresp.body_builder);
                        stream_write(*stream, cast([] u8) body_str);
                    }
                }
            }
        }
    }
}

init_falcon_server_if_needed :: () {
    if !fs {
        fs = New(Falcon_Server);
        set_allocators(*fs.router.pool);
    }
}

// Respond with 404 Not Found when no registered route matches the request.
write_404 :: (stream: *TcpStream) -> Error {
    builder: String_Builder;
    builder.allocator = temp;

    // TODO: adding the status code and the name here needs to be implemented
    append(*builder, get_status_line(.NOT_FOUND));
    // TODO: content type needs to be implemented
    append(*builder, "Content-Type: text/plain\r\n");
    print_to_builder(*builder, "Content-Length: %\r\n\r\n", 0);

    response := builder_to_string(*builder);

    return stream_write(stream, xx response);
}

// 1 MB hard cap on request bodies. Clients that exceed this limit receive a
// 413 Payload Too Large response and the connection is closed immediately.
//
// Without this guard, a malicious or buggy client could send an arbitrarily
// large `Content-Length` and cause the server to buffer gigabytes of data,
// exhausting heap memory and crashing the process.
MAX_BODY_SIZE :: 1 * 1024 * 1024; // 1 MB

// Respond with 413 Payload Too Large when the declared `Content-Length` exceeds `MAX_BODY_SIZE`.
//
// Close the connection after sending so the client cannot pipeline further
// requests on a connection that has already been rejected.
write_413 :: (stream: *TcpStream) -> Error {
    builder: String_Builder;
    builder.allocator = temp;

    append(*builder, get_status_line(.PAYLOAD_TOO_LARGE));
    append(*builder, "Content-Type: text/plain\r\n");
    print_to_builder(*builder, "Content-Length: %\r\n\r\n", 0);

    response := builder_to_string(*builder);

    return stream_write(stream, xx response);
}
