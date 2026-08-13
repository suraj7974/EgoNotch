// EgoNotch MediaRemote adapter.
//
// macOS 15.4+ gates the MediaRemote now-playing API behind a private Apple
// entitlement, but grants access to Apple platform binaries. This dylib is
// therefore never loaded by EgoNotch itself: the app spawns
//   /usr/bin/perl -e 'DynaLoader::dl_load_file(...)'
// and the constructor below runs inside perl (an Apple-signed, non-library-
// validated platform binary), where MediaRemote answers.
//
// Modes (env EGO_MRA_MODE):
//   "stream"  — register for now-playing notifications, print one JSON object
//               per line on stdout for every change, run forever.
//   "command" — send MRMediaRemoteSendCommand(EGO_MRA_CMD), then exit.

#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <libproc.h>

typedef void (*MRRegisterForNowPlayingNotificationsFn)(dispatch_queue_t);
typedef void (*MRGetNowPlayingInfoFn)(dispatch_queue_t, void (^)(CFDictionaryRef));
typedef void (*MRGetIsPlayingFn)(dispatch_queue_t, void (^)(Boolean));
typedef void (*MRGetPIDFn)(dispatch_queue_t, void (^)(int));
typedef Boolean (*MRSendCommandFn)(int, id);

static MRGetNowPlayingInfoFn gGetInfo;
static MRGetIsPlayingFn gGetIsPlaying;
static MRGetPIDFn gGetPID;
static NSString *gLastArtworkHash;

static void emit(NSDictionary *dict) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:dict options:0 error:nil];
    if (!data) return;
    fwrite(data.bytes, 1, data.length, stdout);
    fputc('\n', stdout);
    fflush(stdout);
}

static NSString *appNameForPID(int pid) {
    if (pid <= 0) return nil;
    char path[PROC_PIDPATHINFO_MAXSIZE] = {0};
    if (proc_pidpath(pid, path, sizeof(path)) <= 0) return nil;
    NSString *p = [NSString stringWithUTF8String:path];
    // ".../Spotify.app/Contents/MacOS/Spotify" -> "Spotify"
    for (NSString *comp in [p.pathComponents reverseObjectEnumerator]) {
        if ([comp hasSuffix:@".app"]) return comp.stringByDeletingPathExtension;
    }
    return p.lastPathComponent;
}

// Each getter emits its own partial message when (if) its callback fires —
// no chaining, so a getter that never answers (no media session) can't block
// the others. The Swift side merges parts field-wise.
static void publishNowPlaying(void) {
    gGetInfo(dispatch_get_main_queue(), ^(CFDictionaryRef infoRef) {
        NSDictionary *info = (__bridge NSDictionary *)infoRef;
        NSMutableDictionary *out = [NSMutableDictionary dictionary];
        out[@"type"] = @"now_playing";
        out[@"hasInfo"] = @(info.count > 0);

        id v;
        if ((v = info[@"kMRMediaRemoteNowPlayingInfoTitle"])) out[@"title"] = v;
        if ((v = info[@"kMRMediaRemoteNowPlayingInfoArtist"])) out[@"artist"] = v;
        if ((v = info[@"kMRMediaRemoteNowPlayingInfoAlbum"])) out[@"album"] = v;
        if ((v = info[@"kMRMediaRemoteNowPlayingInfoDuration"])) out[@"duration"] = v;
        if ((v = info[@"kMRMediaRemoteNowPlayingInfoElapsedTime"])) out[@"elapsed"] = v;
        if ((v = info[@"kMRMediaRemoteNowPlayingInfoPlaybackRate"])) out[@"rate"] = v;
        NSDate *ts = info[@"kMRMediaRemoteNowPlayingInfoTimestamp"];
        if ([ts isKindOfClass:[NSDate class]]) out[@"timestamp"] = @(ts.timeIntervalSince1970);

        NSData *artwork = info[@"kMRMediaRemoteNowPlayingInfoArtworkData"];
        if ([artwork isKindOfClass:[NSData class]] && artwork.length > 0) {
            // Cheap change detection so we don't base64 ~200KB on every tick.
            NSString *hash = [NSString stringWithFormat:@"%lu-%lu",
                              (unsigned long)artwork.length, (unsigned long)artwork.hash];
            if ([hash isEqualToString:gLastArtworkHash]) {
                out[@"artworkUnchanged"] = @YES;
            } else {
                gLastArtworkHash = hash;
                out[@"artworkB64"] = [artwork base64EncodedStringWithOptions:0];
            }
        } else {
            // No art in this snapshot: forget the hash so the next track's
            // artwork is re-sent in full even if it hashes the same slot.
            gLastArtworkHash = nil;
        }
        emit(out);
    });

    gGetIsPlaying(dispatch_get_main_queue(), ^(Boolean playing) {
        emit(@{ @"type": @"playing", @"playing": @(playing) });
    });

    if (gGetPID) {
        gGetPID(dispatch_get_main_queue(), ^(int pid) {
            NSString *app = appNameForPID(pid);
            emit(@{ @"type": @"app", @"app": app ?: @"" });
        });
    }
}

__attribute__((constructor))
static void ego_mra_main(void) {
    @autoreleasepool {
        const char *modeC = getenv("EGO_MRA_MODE");
        NSString *mode = modeC ? [NSString stringWithUTF8String:modeC] : @"stream";

        void *mr = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote",
                          RTLD_NOW);
        if (!mr) {
            emit(@{ @"type": @"error", @"message": @"dlopen MediaRemote failed" });
            exit(2);
        }

        MRSendCommandFn sendCommand = (MRSendCommandFn)dlsym(mr, "MRMediaRemoteSendCommand");
        MRRegisterForNowPlayingNotificationsFn registerFn =
            (MRRegisterForNowPlayingNotificationsFn)dlsym(mr, "MRMediaRemoteRegisterForNowPlayingNotifications");
        gGetInfo = (MRGetNowPlayingInfoFn)dlsym(mr, "MRMediaRemoteGetNowPlayingInfo");
        gGetIsPlaying = (MRGetIsPlayingFn)dlsym(mr, "MRMediaRemoteGetNowPlayingApplicationIsPlaying");
        gGetPID = (MRGetPIDFn)dlsym(mr, "MRMediaRemoteGetNowPlayingApplicationPID");

        if ([mode isEqualToString:@"command"]) {
            const char *cmdC = getenv("EGO_MRA_CMD");
            if (!sendCommand || !cmdC) exit(3);
            sendCommand(atoi(cmdC), nil);
            // Give the XPC message time to leave the process.
            CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.3, false);
            exit(0);
        }

        if (!gGetInfo || !gGetIsPlaying || !registerFn) {
            emit(@{ @"type": @"error", @"message": @"MediaRemote symbols missing" });
            exit(4);
        }

        registerFn(dispatch_get_main_queue());

        NSArray<NSString *> *names = @[
            @"kMRMediaRemoteNowPlayingInfoDidChangeNotification",
            @"kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
            @"kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
        ];
        for (NSString *name in names) {
            [[NSNotificationCenter defaultCenter]
                addObserverForName:name object:nil queue:[NSOperationQueue mainQueue]
                        usingBlock:^(NSNotification *note) { publishNowPlaying(); }];
        }

        emit(@{ @"type": @"ready" });
        publishNowPlaying();          // initial state
        CFRunLoopRun();               // never returns; perl hosts us forever
    }
}
