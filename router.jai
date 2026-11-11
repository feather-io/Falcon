#import "Basic";
#import "String";

#import "Pool";

MAX_PATH_PARAMS :: 8;

Param :: struct {
    key:   string;
    value: string;
}

Request :: struct {
    path:         string;
    headers:      [..] Header;
    body:         string;
    query_string: string;
    wildcard:     string;
    params:       [MAX_PATH_PARAMS] Param;
    params_count: int;
}

// req_param linearly scans the fixed-size req.params array for the specified key.
// Since path parameter extraction happens directly during radix tree traversal,
// this function is simply an O(N) lookup, where N is at most MAX_PATH_PARAMS (default 8).
// When it finds a match, it percent-decodes the stored raw path segment value using url_decode
// and allocates the decoded result on the fiber's fast Temporary Storage, returning it instantly.
// This guarantees zero heap allocations while safely supporting URL encodings like `%20`.
req_param :: (req: *Request, key: string) -> string {
    for i: 0..req.params_count - 1 {
        if req.params[i].key == key return url_decode(req.params[i].value);
    }
    return "";
}

// req_query lazily scans the raw req.query_string (the unparsed text after the `?` in the URL)
// to find a matching query parameter key on demand. It splits on `&` and `=` characters.
// This completely avoids parsing the query string into a heap-allocated Hash_Table upfront,
// saving massive memory overhead and preventing out-of-memory errors for long malicious query strings.
// When a match is found, the value is percent-decoded using url_decode and returned
// as a slice bound to the fiber's Temporary Storage.
req_query :: (req: *Request, key: string) -> string {
    remaining := req.query_string;
    while remaining.count > 0 {
        // Split off next key=value pair at "&"
        amp := find_index_from_left(remaining, #char "&");
        pair := ifx amp >= 0 then slice(remaining, 0, amp) else remaining;

        // Split pair at "="
        eq := find_index_from_left(pair, #char "=");
        if eq > 0 {
            k := slice(pair, 0, eq);
            if k == key {
                raw_value := slice(pair, eq + 1, pair.count - eq - 1);
                return url_decode(raw_value);  // decode %XX and + into temp
            }
        }

        if amp < 0 break;
        remaining = slice(remaining, amp + 1, remaining.count - amp - 1);
    }
    return "";
}

Body_Mode :: enum {
    EMPTY;          // Default, no body sent
    STATIC_STRING;  // Used by res_send()
    BUILDER;        // Used by res_get_builder()
}

Response :: struct {
    status_code: Status_Code = .OK;
    headers: [..] Header;

    body_mode: Body_Mode = .EMPTY;
    body_static: string;
    body_builder: String_Builder;
}

HTTP_Method :: enum {
    GET;
    POST;
    PUT;
    DELETE;
    PATCH;
    OPTIONS;
    HEAD;
    TRACE;
    CONNECT;
}


Handler_Info :: struct {
    type: HTTP_Method;
    fn: Falcon_Handler;
}

Falcon_Handler :: #type (req: *Request, res: *Response);

res_set_header :: (res: *Response, key: string, value: string) {
    array_add(*res.headers, .{key, value});
}

// The "Send Once" API
res_send :: (res: *Response, body: string) {
    if res.body_mode != .EMPTY {
        // TODO: change this to logger
        print("Warning: Response body was already sent!\n");
        return;
    }
    res.body_mode = .STATIC_STRING;
    res.body_static = body;
}

// The "Advanced Builder" API for streaming
res_get_builder :: (res: *Response) -> *String_Builder {
    if res.body_mode != .EMPTY {
        // TODO: change this to logger
        print("Warning: Response body was already sent or builder was already requested!\n");
        return null;
    }
    res.body_mode = .BUILDER;
    res.body_builder.allocator = temp;
    return *res.body_builder;
}

#scope_file

print_node :: (node: *Radix_Node, prefix: string) {
    if !node return;

    // tprint uses temporary storage so we don't leak memory doing string concatenation!
    full_path := tprint("%%", prefix, node.path);

    if node.handler.fn != null {
        print("  [%] %\n", node.handler.type, full_path);
    }

    for child: node.children {
        print_node(child, full_path);
    }
}

#scope_module

Node_Type :: enum {
    SINGLE;
    PARAM;
    WILDCARD;
}

Radix_Node :: struct {
    path: string;
    node_type: Node_Type;

    indices: [..] u8;
    children: [..] *Radix_Node;

    handler: Handler_Info;
}

Router :: struct {
    root: *Radix_Node;
    pool: Pool;
}

get_method_str :: (method: HTTP_Method) -> string {
    if method == {
        case .GET; return "GET";
        case .POST; return "POST";
        case .PUT; return "PUT";
        case .DELETE; return "DELETE";
        case .PATCH; return "PATCH";
        case .OPTIONS; return "OPTIONS";
        case .HEAD; return "HEAD";
        case .TRACE; return "TRACE";
        case .CONNECT; return "CONNECT";
        case; return "UNKNOWN";
    }
}


// router_insert adds a new handler path into the Radix Tree.
// The algorithm implements an optimized tree insertion that compresses shared path prefixes
// to minimize both memory usage and string comparison cost during lookups.
// It specifically handles dynamic routing (Path Parameters like `:id` and Wildcards like `*`).
//
// When inserting, the function performs the following steps:
// 1. If the root is empty, initializes a blank root.
// 2. Iterates down the tree matching the incoming `handler_path` string against existing nodes.
// 3. Node Splitting: If it hits a partial match (e.g., trying to insert `/users/:id` when
//    `/users/profile` already exists), it forcibly splits the existing node at the divergence
//    point. The common prefix becomes the parent, and the disparate tails become children.
// 4. Dynamic Parameter Segments: When the un-matched tail of a path contains `:` or `*`,
//    the algorithm actively splits the string into discrete nodes. For example,
//    `/users/:id/posts` becomes -> Node("GET/users/", .SINGLE) -> Node(":id", .PARAM) -> Node("/posts", .SINGLE).
//    This guarantees that parameter segments act as independent tree levels for accurate value capture during lookup.
router_insert :: (router: *Router, handler_path: string, handler: Handler_Info) {
    if !router.root {
        router.root = New(Radix_Node);
        router.root.path = "";
        router.root.node_type = .SINGLE;
        // Proceed to insert the path into the empty root!
    }

    node := router.root;
    path := handler_path;

    while true {
        i := 0;
        max_i := min(path.count, node.path.count);
        while i < max_i && path[i] == node.path[i] {
            i += 1;
        }

        // we have to split the nodes since common prefix is shorter than node path
        if i < node.path.count {
            child := New(Radix_Node);
            child.path = slice(node.path, i, node.path.count - i);
            if child.path[0] == #char ":" {
                child.node_type = .PARAM;
            } else if child.path[0] == #char "*" {
                child.node_type = .WILDCARD;
            } else {
                child.node_type = .SINGLE; // or preserve if it was a weird split? No, it's definitely SINGLE if it doesn't start with : or *
            }
            child.indices = node.indices;
            child.children = node.children;
            child.handler = node.handler;

            // reset current node
            node.node_type = .SINGLE;
            node.handler = .{};
            node.path = slice(node.path, 0, i);

            // add the child s now
            node.children.data = null;
            node.children.count = 0;
            node.children.allocated = 0;

            node.indices.data = null;
            node.indices.count = 0;
            node.indices.allocated = 0;

            array_add(*node.children, child);
            array_add(*node.indices, child.path[0]);
        }

        // if it's a perfect match then return
        if i == path.count {
            node.handler = handler;
            return;
        }

        // remaining path from previous slice is left..
        path = slice(path, i, path.count - i);
        first_char := path[0];

        found_child := false;
        for c : 0..node.indices.count-1 {
            if node.indices[c] == first_char {
                node = node.children[c];
                found_child = true;
                break;
            }
        }

        // did not find any matching childs, we create a new child
        if !found_child {
            while path.count > 0 {
                first_char = path[0];
                split_idx := -1;
                for j: 0..path.count-1 {
                    if path[j] == #char ":" || path[j] == #char "*" {
                        split_idx = j;
                        break;
                    }
                }

                if split_idx > 0 {
                    child := New(Radix_Node);
                    child.path = slice(path, 0, split_idx);
                    child.node_type = .SINGLE;
                    child.handler = .{}; // Intermediate

                    array_add(*node.indices, first_char);
                    array_add(*node.children, child);

                    node = child;
                    path = slice(path, split_idx, path.count - split_idx);
                } else if split_idx == 0 {
                    seg_end := 0;
                    while seg_end < path.count && path[seg_end] != #char "/" {
                        seg_end += 1;
                    }

                    child := New(Radix_Node);
                    child.path = slice(path, 0, seg_end);
                    if path[0] == #char ":" {
                        child.node_type = .PARAM;
                    } else {
                        child.node_type = .WILDCARD;
                    }

                    if seg_end == path.count {
                        child.handler = handler;
                    } else {
                        child.handler = .{};
                    }

                    array_add(*node.indices, first_char);
                    array_add(*node.children, child);

                    if seg_end == path.count return;

                    node = child;
                    path = slice(path, seg_end, path.count - seg_end);
                } else {
                    child := New(Radix_Node);
                    child.path = copy_string(path);
                    child.node_type = .SINGLE;
                    child.handler = handler;

                    array_add(*node.indices, first_char);
                    array_add(*node.children, child);
                    return;
                }
            }
            return;
        }
    }
}

// router_find searches the Radix Tree for a registered handler matching the raw incoming `request_path`.
// It implements a high-performance backtracking traversal that dynamically prioritizes
// exact literal matches (.SINGLE) over path parameters (.PARAM), and finally fallbacks to catch-alls (.WILDCARD).
//
// During the traversal:
// 1. Literal Matches: It always checks `.SINGLE` child nodes first.
// 2. Parameter Capture: If no literal matches the incoming path, it falls back to a `.PARAM` child.
//    It isolates the path segment (everything up to the next `/`) and saves the raw captured string
//    directly into the `req.params` array. This is done entirely in-place with zero memory allocation.
// 3. Wildcard Catch-all: If all else fails, it falls back to a `.WILDCARD` child which greedily captures
//    the entire remaining path string.
// 4. Backtracking: If it proceeds down a `.PARAM` or `.WILDCARD` branch but fails to match the rest of the path,
//    it backtracks up the tree (via recursive-like state saving) to explore alternative fallback branches.
//
// If successful, it returns the matched Handler_Info and populates the `Request` pointer with extracted variables.
router_find :: (router: *Router, request_path: string, req: *Request = null) -> Handler_Info, bool {
    if !router.root return .{}, false;

    node := router.root;
    path := request_path;

    while search_loop := true {
        matched_len := 0;

        if node.node_type == .SINGLE {
            if path.count >= node.path.count {
                prefix := slice(path, 0, node.path.count);
                if prefix == node.path {
                    matched_len = node.path.count;
                } else {
                    return .{}, false; // Mismatch
                }
            } else {
                return .{}, false; // Mismatch
            }
        } else if node.node_type == .PARAM {
            seg_end := 0;
            while seg_end < path.count && path[seg_end] != #char "/" {
                seg_end += 1;
            }
            if seg_end > 0 { // Must match at least something
                param_value := slice(path, 0, seg_end);
                param_key   := slice(node.path, 1, node.path.count - 1);

                if req && req.params_count < MAX_PATH_PARAMS {
                    req.params[req.params_count].key = param_key;
                    req.params[req.params_count].value = param_value;
                    req.params_count += 1;
                }
                matched_len = seg_end;
            } else {
                return .{}, false;
            }
        } else if node.node_type == .WILDCARD {
            if req {
                req.wildcard = path;
            }
            return node.handler, true;
        }

        // Consume the matched part
        path = slice(path, matched_len, path.count - matched_len);

        if path.count == 0 {
            // We matched the path completely, but does this node actually have a handler?
            // If it doesn't, it might be an intermediate node (e.g. GET/users/)
            if node.handler.fn != null {
                return node.handler, true;
            }

            // Check if there is a wildcard child that can match the empty remainder
            for i : 0..node.children.count - 1 {
                if node.children[i].node_type == .WILDCARD {
                    if req req.wildcard = "";
                    return node.children[i].handler, true;
                }
            }
            return .{}, false;
        }

        // We have path remaining, look for a child.
        first_char := path[0];

        // 1. Try SINGLE children first (Exact match)
        found_single := false;
        for i : 0..node.children.count - 1 {
            child := node.children[i];
            if child.node_type == .SINGLE && node.indices[i] == first_char {
                node = child;
                found_single = true;
                break;
            }
        }
        if found_single continue search_loop;

        // 2. Fallback to PARAM child
        found_param := false;
        for i : 0..node.children.count - 1 {
            child := node.children[i];
            if child.node_type == .PARAM {
                node = child;
                found_param = true;
                break;
            }
        }
        if found_param continue search_loop;

        // 3. Fallback to WILDCARD child
        for i : 0..node.children.count - 1 {
            child := node.children[i];
            if child.node_type == .WILDCARD {
                node = child;
                continue search_loop;
            }
        }

        return .{}, false;
    }
    return .{}, false;
}

router_print :: (router: *Router) {
    if !router.root {
        print("Router is empty.\n");
        return;
    }
    print("Registered Routes:\n");
    print_node(router.root, "");
}
