Falcon
-------

A blazing fast HTTP client and server module written on top of [Feather](https://github.com/feather-io/Feather) for Jai. To read more about how and why it is was created, read this detailed blog post. Also check out this demo game written with Falcon.

Falcon is in active development for my game and server needs, and would not recommend anyone to use it on production as the API will keep changing and versioned release is not planned until I think it is stable enough to version it. Although, you can try Falcon on your local machine and for your side projects and let drop me a feedback or file an issue here.

Here are some things that Falcon cannot do (for now):

- TLS (Can be handled by a Reverse Proxy)
- Connection Idle Timeouts & Keep-Alive
- Different Types of Request Body Parsing (You should parse on your own)
- Chunked Request Transfer is not supported
