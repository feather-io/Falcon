# Falcon

A high-performance, asynchronous HTTP/1.1 web server and client framework for the Jai programming language, built on the [Feather](https://github.com/feather-io/Feather) runtime.

Falcon gives you the developer ergonomics of Express or Go's `net/http` clean, synchronous-looking request handlers without callback hell or `async`/`await` colored functions while running on a non-blocking, multi-core work-stealing event loop.


## Highlights

- **Zero-Heap Request Lifecycle:** Normal requests (headers, query params, path parsing, and response buffers) are served using a 64KB `Temporary_Storage` buffer residing
directly on the fiber's stack. No `malloc`/`free` calls touch the hot path.
- **Hybrid Concurrency:**
  - Connection acceptor runs as a lightweight, zero-stack **Future**.
  - Client connections run on dedicated **Fibers**, allowing handlers to perform blocking reads/writes and sleep cooperatively.
- **Two-Write Response Optimization:** Headers and response bodies are flushed in two targeted socket writes. Eliminates copying large response payloads into intermediate buffers just to prepend header strings.
- **Built-in Async HTTP Client:** Comes with `falcon_fetch()`, an asynchronous HTTP client that transparently yields fibers on socket I/O.

## Quickstart

### 1. Minimal HTTP Server

```jai
#import "Basic";
#import "Falcon";

main :: () {
    // 1. Register routes
    falcon_get("/", (req: *Request, res: *Response) {
        res_send(res, "Hello from Falcon!\n");
    });

    // 2. Dynamic routing with path parameters
    falcon_get("/users/:id", (req: *Request, res: *Response) {
        user_id := req_param(req, "id");
        body    := tprint("User Profile: %\n", user_id);
        res_send(res, body);
    });

    // 3. Query string parsing
    falcon_get("/search", (req: *Request, res: *Response) {
        query := req_query(req, "q");
        body  := tprint("Search results for: %\n", query);
        res_send(res, body);
    });

    // 4. POST route with JSON body
    falcon_post("/api/echo", (req: *Request, res: *Response) {
        res_set_header(res, "Content-Type", "application/json");
        res_send(res, req.body);
    });

    print("🦅 Falcon server starting on http://127.0.0.1:8080\n");

    // Starts Feather and serves requests across all CPU cores
    falcon_listen_and_serve(8080);
}
```

Compile and run:

```jai
jai main.jai && ./main
```

### 2. Built-in Async HTTP Client (falcon_fetch)

Make outbound HTTP requests without blocking OS worker threads:

```jai
#import "Basic";
#import "Falcon";

main :: () {
    feather_block_on(() {
        res, err := falcon_fetch("http://httpbin.org/get");
        if err.kind != .NONE {
            print("Fetch failed: %\n", err);
            return;
        }

        print("Status: %\n", res.status_code);
        print("Body:\n%\n", res.body);
    });
}
```

## Architecture & Zero-Allocation Strategy

```
  Incoming TCP Connection
          │
          ▼
  [Feather_Acceptor (Stackless Future)]
          │
          ▼ (Round-robin across Reactors)
  [Connection Fiber (512 KB Stack)]
          │
          ├── Stack Bump: 64 KB Temporary_Storage buffer allocated on fiber stack
          ├── Parse Request Line & Headers (Zero-copy string slices)
          ├── Match Radix Tree Router: O(K) lookup (K = path length)
          ├── Execute Falcon_Handler(req, res)
          ├── Flush Headers & Body (Two-write strategy)
          └── defer reset_temporary_storage (Stack pointer resets; zero heap churn)
### The 64 KB Stack Buffer Trick
```


URL decoding is applied automatically: Accessing `/search?q=hello%20world` via `req_query(req, "q")` returns "hello world" allocated on temporary storage.


## Cloning & Setup

Falcon relies on the Feather asynchronous engine as a Git submodule:

1. Clone Falcon with submodules

```sh
git clone --recurse-submodules git@github.com:feather-io/Falcon.git
cd falcon
```

2. Assemble Feather's low-level context switch object (one-time setup)

```sh
cd modules/Feather/asm
as -o fiber_swap_arm64.o fiber_swap_arm64.s
ar rcs fiber_swap_arm64.a fiber_swap_arm64.o
cd ../../../
```

## Roadmap & Current Limitations

Falcon is experimental and evolving rapidly. Current areas of focus:

- [ ] HTTP Chunked Transfer Encoding: Streaming incoming bodies and outgoing responses
(Transfer-Encoding: chunked).
- [ ] Streaming Header Parser: Incremental state-machine parser for requests whose headers
span multiple TCP segments.
- [ ] TLS / HTTPS: Native OpenSSL or mbedTLS integration for secure endpoints.
- [ ] Connection Deadlines: Idle keep-alive and slow-read connection timeouts.

## License

MIT License. Crafted for the Jai programming language community. Clone. Use. Enjoy.

Developed on `Version: beta 0.2.030, built on 2 July 2026.`
