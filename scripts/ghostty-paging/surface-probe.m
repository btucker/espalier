#import <TargetConditionals.h>
#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#define PROBE_PLATFORM "UIKit"
#else
#import <AppKit/AppKit.h>
#define PROBE_PLATFORM "AppKit"
#endif
#include <ghostty.h>
#include <assert.h>
#include <stdio.h>

extern bool graftty_probe_surface_snapshot_ready(ghostty_surface_t, const uint8_t *, size_t);
extern int graftty_probe_surface_snapshot_next(ghostty_surface_t, size_t *);
extern size_t graftty_probe_surface_snapshot_offset(ghostty_surface_t);
extern bool graftty_probe_surface_grid_matches(ghostty_surface_t, uint16_t, uint16_t);

static void wait_grid(ghostty_app_t app, ghostty_surface_t surface, uint16_t cols, uint16_t rows) {
    for (int i = 0; i < 200; i++) {
        ghostty_app_tick(app);
        if (graftty_probe_surface_grid_matches(surface, cols, rows)) return;
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
    assert(!"timed out waiting for the terminal grid");
}

static void wakeup(void *data) { (void)data; }
static bool action(ghostty_app_t app, ghostty_target_s target, ghostty_action_s event) {
    (void)app; (void)target; (void)event; return false;
}
static void output(void *data, const uint8_t *bytes, size_t len) {
    (void)data; (void)bytes; (void)len;
}
static ghostty_clipboard_read_result_e read_clipboard(void *data, ghostty_clipboard_e clipboard,
    void *state, const char *const *mimes, size_t count, bool prompt) {
    (void)data; (void)clipboard; (void)state; (void)mimes; (void)count; (void)prompt;
    return GHOSTTY_CLIPBOARD_READ_UNAVAILABLE;
}
static void confirm_clipboard(void *data, const ghostty_clipboard_confirm_s *confirm,
    void *state, ghostty_clipboard_request_e request) {
    (void)data; (void)confirm; (void)state; (void)request;
}
static void write_clipboard(void *data, ghostty_clipboard_e clipboard,
    const ghostty_clipboard_content_s *content, size_t count, bool confirm) {
    (void)data; (void)clipboard; (void)content; (void)count; (void)confirm;
}

static int run_probe(int argc, char **argv, NSData *snapshot) {
    @autoreleasepool {
        assert(snapshot.length > 0);
        assert(ghostty_init(argc, argv) == 0);
#if !TARGET_OS_IPHONE
        [NSApplication sharedApplication];
#endif
        for (int scenario = 0; scenario < 6; scenario++) {
            const bool needs_recovery = scenario >= 2 && scenario <= 4;
#if TARGET_OS_IPHONE
            UIWindow *window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
            window.rootViewController = [UIViewController new];
            UIView *view = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 800, 480)];
            [window.rootViewController.view addSubview:view];
            [window makeKeyAndVisible];
#else
            NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 800, 480)
                styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
            NSView *view = window.contentView;
            view.wantsLayer = YES;
            window.title = @"Graftty snapshot renderer experiment";
#endif
            ghostty_config_t config = ghostty_config_new();
            ghostty_config_finalize(config);
            ghostty_runtime_config_s runtime = {
                .wakeup_cb = wakeup, .action_cb = action, .read_clipboard_cb = read_clipboard,
                .confirm_read_clipboard_cb = confirm_clipboard, .write_clipboard_cb = write_clipboard,
            };
            ghostty_app_t app = ghostty_app_new(&runtime, config);
            assert(app);
            ghostty_surface_config_s options = ghostty_surface_config_new();
#if TARGET_OS_IPHONE
            options.platform_tag = GHOSTTY_PLATFORM_IOS;
            options.platform.ios.uiview = (__bridge void *)view;
#else
            options.platform_tag = GHOSTTY_PLATFORM_MACOS;
            options.platform.macos.nsview = (__bridge void *)view;
#endif
            options.backend = GHOSTTY_SURFACE_IO_BACKEND_HOST_MANAGED;
            options.receive_buffer = output;
            ghostty_surface_t surface = ghostty_surface_new(app, &options);
            assert(surface);
            ghostty_surface_set_size(surface, 800, 480);
            ghostty_surface_size_s size = ghostty_surface_size(surface);
            const uint32_t width = 800 + (80 - size.columns) * size.cell_width_px;
            const uint32_t height = 480 + (24 - size.rows) * size.cell_height_px;
#if TARGET_OS_IPHONE
            view.frame = CGRectMake(0, 0, width, height);
#else
            [window setContentSize:NSMakeSize(width, height)];
#endif
            ghostty_surface_set_size(surface, width, height);
#if !TARGET_OS_IPHONE
            [window orderFront:nil];
#endif
            wait_grid(app, surface, 80, 24);
            // A truncated READY must leave the original surface usable.
            assert(!graftty_probe_surface_snapshot_ready(surface, snapshot.bytes, 16));
            assert(graftty_probe_surface_snapshot_ready(surface, snapshot.bytes, snapshot.length));
            // This experiment supports exactly one install per fresh surface.
            assert(!graftty_probe_surface_snapshot_ready(surface, snapshot.bytes, snapshot.length));
            const char *live = "msurface-live-output\r\n";
            ghostty_surface_write_buffer(surface, (const uint8_t *)live, strlen(live));
            for (int i = 0; i < 20; i++) {
                ghostty_app_tick(app);
                ghostty_surface_draw(surface);
                [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
            }
            ghostty_selection_s selection = {
                .top_left = {.tag = GHOSTTY_POINT_SCREEN, .coord = GHOSTTY_POINT_COORD_TOP_LEFT},
                .bottom_right = {.tag = GHOSTTY_POINT_SCREEN, .coord = GHOSTTY_POINT_COORD_BOTTOM_RIGHT},
            };
            ghostty_text_s text = {0};
            assert(ghostty_surface_read_text(surface, selection, &text));
            assert(text.text && strstr(text.text, "surface-live-output"));
            assert(strstr(text.text, "row-099999"));
            assert(!strstr(text.text, "row-000000"));
            ghostty_surface_free_text(surface, &text);
            ghostty_text_s selected_before = {0}, anchor_before = {0};
            ghostty_selection_s anchor_range = {
                .top_left = {.tag = GHOSTTY_POINT_VIEWPORT, .coord = GHOSTTY_POINT_COORD_EXACT},
                .bottom_right = {.tag = GHOSTTY_POINT_VIEWPORT, .coord = GHOSTTY_POINT_COORD_EXACT, .x = 9},
            };
            size_t pages = 0, applied = 0;
            if (scenario == 4) {
                assert(graftty_probe_surface_snapshot_next(surface, &applied) == 1 && applied > 0);
                pages++;
            }
            if (scenario == 0 || scenario == 4) {
                assert(ghostty_surface_binding_action(surface, "scroll_to_top", strlen("scroll_to_top")));
                assert(ghostty_surface_binding_action(surface, "select_all", strlen("select_all")));
                // Scroll actions are queued to Ghostty's I/O thread. Observe the
                // requested viewport before taking an anchor or fetching pages.
                ghostty_selection_s first_row = anchor_range;
                first_row.top_left.tag = GHOSTTY_POINT_SCREEN;
                first_row.bottom_right.tag = GHOSTTY_POINT_SCREEN;
                ghostty_text_s expected_top = {0};
                assert(ghostty_surface_read_text(surface, first_row, &expected_top));
                bool at_top = false;
                for (int i = 0; i < 200; i++) {
                    ghostty_app_tick(app);
                    ghostty_text_s current_top = {0};
                    assert(ghostty_surface_read_text(surface, anchor_range, &current_top));
                    at_top = current_top.text_len == expected_top.text_len &&
                        memcmp(current_top.text, expected_top.text, current_top.text_len) == 0;
                    ghostty_surface_free_text(surface, &current_top);
                    if (at_top) break;
                    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
                }
                ghostty_surface_free_text(surface, &expected_top);
                assert(at_top);
                assert(ghostty_surface_read_selection(surface, &selected_before));
                assert(ghostty_surface_read_text(surface, anchor_range, &anchor_before));
                assert(anchor_before.text_len == 10);
            }
            if (scenario == 1) {
                const char *alternate = "\x1b[?1049halt-screen";
                ghostty_surface_write_buffer(surface, (const uint8_t *)alternate, strlen(alternate));
            } else if (needs_recovery) {
                ghostty_surface_set_size(surface, width - 40 * size.cell_width_px, height);
                wait_grid(app, surface, 40, 24);
                if (scenario == 3) {
                    // No history call sees the intermediate width. Checking
                    // only current columns would accept stale pages again.
                    ghostty_surface_set_size(surface, width, height);
                    wait_grid(app, surface, 80, 24);
                }
            } else if (scenario == 5) {
                ghostty_surface_set_size(surface, width, height + 4 * size.cell_height_px);
                wait_grid(app, surface, 80, 28);
            }
            const size_t offset_before = graftty_probe_surface_snapshot_offset(surface);
            assert(offset_before < snapshot.length);
            int status;
            while ((status = graftty_probe_surface_snapshot_next(surface, &applied)) == 1) {
                assert(!needs_recovery && applied > 0);
                pages++;
                ghostty_app_tick(app);
                ghostty_surface_draw(surface);
            }
            if (needs_recovery) {
                assert(status == 2 && applied == 0);
                assert(pages == (scenario == 4 ? 1 : 0));
                // Retrying cannot consume the old cursor or turn recovery
                // into completion. Live output remains independently usable.
                for (int retry = 0; retry < 3; retry++) {
                    assert(graftty_probe_surface_snapshot_next(surface, &applied) == 2 && applied == 0);
                    // Only the first call may read HISTORY's 10-byte record
                    // header and 6-byte payload. It never reads the PAGE.
                    const size_t manifest_bytes = scenario == 4 ? 0 : 16;
                    assert(graftty_probe_surface_snapshot_offset(surface) == offset_before + manifest_bytes);
                }
            } else {
                assert(status == 0 && pages > 1);
                assert(graftty_probe_surface_snapshot_next(surface, &applied) == 0 && applied == 0);
                if (scenario == 5) {
                    ghostty_surface_set_size(surface, width - 40 * size.cell_width_px, height);
                    wait_grid(app, surface, 40, 24);
                    assert(graftty_probe_surface_snapshot_next(surface, &applied) == 0 && applied == 0);
                }
            }
            if (scenario == 0 || scenario == 4) {
                ghostty_text_s after = {0};
                assert(ghostty_surface_read_selection(surface, &after));
                assert(after.text_len == selected_before.text_len);
                assert(memcmp(after.text, selected_before.text, after.text_len) == 0);
                ghostty_surface_free_text(surface, &after);
                assert(ghostty_surface_read_text(surface, anchor_range, &after));
                assert(after.text_len == anchor_before.text_len);
                assert(memcmp(after.text, anchor_before.text, after.text_len) == 0);
                ghostty_surface_free_text(surface, &after);
                ghostty_surface_free_text(surface, &anchor_before);
                ghostty_surface_free_text(surface, &selected_before);
            }
            if (scenario == 1) {
                const char *primary = "\x1b[?1049l";
                ghostty_surface_write_buffer(surface, (const uint8_t *)primary, strlen(primary));
            } else if (needs_recovery) {
                const char *continued = "after-resize\r\n";
                ghostty_surface_write_buffer(surface, (const uint8_t *)continued, strlen(continued));
            }
            assert(ghostty_surface_read_text(surface, selection, &text));
            const char *cursor = text.text;
            if (!needs_recovery) {
                for (int row = 0; row < 100000; row++) {
                    char expected[32];
                    snprintf(expected, sizeof(expected), "row-%06d\n", row);
                    assert(strncmp(cursor, expected, strlen(expected)) == 0);
                    cursor += strlen(expected);
                }
                assert(strncmp(cursor, "surface-live-output", strlen("surface-live-output")) == 0);
                cursor += strlen("surface-live-output");
                while (*cursor) assert(*cursor++ == '\n');
            } else {
                assert(strstr(text.text, "surface-live-output"));
                assert(strstr(text.text, "after-resize"));
                assert(!strstr(text.text, "row-000000"));
            }
            ghostty_surface_free_text(surface, &text);
            ghostty_surface_free(surface);
            ghostty_app_free(app);
            ghostty_config_free(config);
#if TARGET_OS_IPHONE
            window.hidden = YES;
#else
            [window orderOut:nil];
#endif
            printf(PROBE_PLATFORM " snapshot surface: scenario=%d pages=%zu READY/live/draw/destroy PASS%s\n",
                scenario, pages, needs_recovery ? "; recovery required without consuming pending pages" : "; all 100000 rows in order");
        }
    }
    return 0;
}

#if TARGET_OS_IPHONE
static int probe_argc;
static char **probe_argv;

@interface ProbeAppDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow *window;
@end

@implementation ProbeAppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    (void)application; (void)options;
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [UIViewController new];
    [self.window makeKeyAndVisible];
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *path = [[NSBundle mainBundle] pathForResource:@"surface-fixture" ofType:@"bin"];
        NSData *snapshot = [NSData dataWithContentsOfFile:path];
        exit(run_probe(probe_argc, probe_argv, snapshot));
    });
    return YES;
}
@end

int main(int argc, char **argv) {
    probe_argc = argc;
    probe_argv = argv;
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(ProbeAppDelegate.class));
    }
}
#else
int main(int argc, char **argv) {
    @autoreleasepool {
        assert(argc == 2);
        NSData *snapshot = [NSData dataWithContentsOfFile:[NSString stringWithUTF8String:argv[1]]];
        return run_probe(argc, argv, snapshot);
    }
}
#endif
