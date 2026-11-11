#import "Basic";
#import,dir "..";
#import,dir "../modules/Feather";

main :: () {
    print("============================================\n");
    print(" 🦅 Falcon Async HTTP Client Demo\n");
    print(" Performing non-blocking HTTP fetch requests\n");
    print("============================================\n\n");

    // falcon_fetch uses Feather async sockets under the hood,
    // so we run it inside feather_block_on (or inside a server fiber).
    feather_block_on(() {
        // 1. Simple GET request
        print("[1] Fetching http://example.com ...\n");
        res, err := falcon_fetch("http://example.com");
        if err.kind != .NONE {
            print("Fetch failed: %\n", err);
            return;
        }

        print("Response Code:   %\n", res.status_code);
        print("Reason Phrase:   %\n", res.reason_phrase);
        print("Response Length: % bytes\n", res.body.count);

        print("\n--- Response Headers ---\n");
        for h: res.headers {
            print("  %: %\n", h.key, h.value);
        }

        print("\n--- Body Preview (first 140 chars) ---\n");
        preview_len := min(res.body.count, 140);
        preview: string;
        preview.data = res.body.data;
        preview.count = preview_len;
        print("%...\n\n", preview);

        print("============================================\n");
        print("Client fetch completed successfully!\n");
        print("============================================\n");
    });
}
