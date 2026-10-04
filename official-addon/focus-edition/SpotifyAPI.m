#import "SpotifyAPI.h"
#import "MusicAPI.h"
#import "music.h"
#import <AuthenticationServices/AuthenticationServices.h>
#import <CommonCrypto/CommonCrypto.h>
#import <Security/Security.h>
#import <ImageIO/ImageIO.h>

@implementation SpotifyTrack
@end

@interface SpotifyAuthAnchor : NSObject <ASWebAuthenticationPresentationContextProviding>
@property (nonatomic, weak) UIWindow *window;
@end

@implementation SpotifyAuthAnchor
- (ASPresentationAnchor)presentationAnchorForWebAuthenticationSession:(ASWebAuthenticationSession *)session {
    return self.window ?: UIApplication.sharedApplication.windows.firstObject;
}
@end

@interface SpotifyAPI ()
@property (nonatomic, copy) NSString *accessToken;
@property (nonatomic, copy) NSString *refreshToken;
@property (nonatomic, strong) NSDate *tokenExpiry;
@property (nonatomic, strong) NSTimer *pollTimer;
@property (nonatomic, strong) SpotifyTrack *currentTrack;
@property (nonatomic, strong) UIImage *currentCover;
@property (nonatomic, strong) NSData *currentCoverGray;
@property (nonatomic, strong) NSArray<NSDictionary *> *currentLyrics;
@property (nonatomic, copy) NSString *statusNote;
@property (nonatomic, strong) SpotifyAuthAnchor *authAnchor;
@property (nonatomic, strong) ASWebAuthenticationSession *authSession;
@property (nonatomic) BOOL isRefreshing;
@property (nonatomic) NSUInteger downloadTicket;
@end

static NSString *const kDefaultSpotifyClientId = @"";
static NSString *const kDefaultSpotifyClientSecret = @"";
static NSString *const kSpotifyRedirectUri = @"rayneo.venus.app://callback";
static NSString *const kSpotifyServiceKey = @"TurboIOSpotifyTokensV2";

static NSString *Base64URL(NSData *data) {
    NSString *b64 = [data base64EncodedStringWithOptions:0];
    b64 = [b64 stringByReplacingOccurrencesOfString:@"+" withString:@"-"];
    b64 = [b64 stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    b64 = [b64 stringByReplacingOccurrencesOfString:@"=" withString:@""];
    return b64;
}

static NSData *SpotifyGray(UIImage *image) {
    if (!image.CGImage) return nil;
    NSMutableData *d = [NSMutableData dataWithLength:TM_COVER_BYTES];
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceGray();
    CGContextRef ctx = CGBitmapContextCreate(d.mutableBytes, 144, 144, 8, 144, cs, kCGImageAlphaNone);
    CGColorSpaceRelease(cs);
    if (!ctx) return nil;
    CGContextSetInterpolationQuality(ctx, kCGInterpolationHigh);
    CGContextDrawImage(ctx, CGRectMake(0, 0, 144, 144), image.CGImage);
    CGContextRelease(ctx);
    return d;
}

@implementation SpotifyAPI

+ (instancetype)shared {
    static SpotifyAPI *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [self new]; });
    return s;
}

- (instancetype)init {
    if ((self = [super init])) {
        _statusNote = @"Not connected to Spotify";
        [self loadTokensFromKeychain];
    }
    return self;
}

- (NSString *)clientId {
    NSString *cid = [NSUserDefaults.standardUserDefaults stringForKey:@"TurboIOSpotifyClientID"];
    return (cid.length > 0) ? cid : kDefaultSpotifyClientId;
}

- (void)setClientId:(NSString *)clientId {
    if (clientId.length > 0) {
        [NSUserDefaults.standardUserDefaults setObject:clientId forKey:@"TurboIOSpotifyClientID"];
    } else {
        [NSUserDefaults.standardUserDefaults removeObjectForKey:@"TurboIOSpotifyClientID"];
    }
}

- (NSString *)clientSecret {
    NSString *sec = [NSUserDefaults.standardUserDefaults stringForKey:@"TurboIOSpotifyClientSecret"];
    return (sec.length > 0) ? sec : kDefaultSpotifyClientSecret;
}

- (void)setClientSecret:(NSString *)clientSecret {
    if (clientSecret.length > 0) {
        [NSUserDefaults.standardUserDefaults setObject:clientSecret forKey:@"TurboIOSpotifyClientSecret"];
    } else {
        [NSUserDefaults.standardUserDefaults removeObjectForKey:@"TurboIOSpotifyClientSecret"];
    }
}

- (BOOL)hasAuth {
    return self.refreshToken.length > 0 || (self.accessToken.length > 0 && [self.tokenExpiry timeIntervalSinceNow] > 0);
}

- (BOOL)isPolling {
    return _pollTimer != nil;
}

#pragma mark - Keychain Storage

- (NSDictionary *)keyQuery {
    return @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: kSpotifyServiceKey,
        (__bridge id)kSecAttrAccount: @"spotify_pkce_tokens"
    };
}

- (void)loadTokensFromKeychain {
    NSMutableDictionary *q = [self.keyQuery mutableCopy];
    q[(__bridge id)kSecReturnData] = @YES;
    CFTypeRef dataRef = NULL;
    if (SecItemCopyMatching((__bridge CFDictionaryRef)q, &dataRef) == errSecSuccess) {
        NSData *data = CFBridgingRelease(dataRef);
        NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if ([dict isKindOfClass:NSDictionary.class]) {
            self.accessToken = dict[@"access_token"];
            self.refreshToken = dict[@"refresh_token"];
            double expiry = [dict[@"expiry"] doubleValue];
            if (expiry > 0) self.tokenExpiry = [NSDate dateWithTimeIntervalSince1970:expiry];
            if (self.hasAuth) {
                _statusNote = @"Spotify connected (idle)";
            }
        }
    }
}

- (void)saveTokensToKeychain {
    NSMutableDictionary *dict = [NSMutableDictionary new];
    if (self.accessToken.length) dict[@"access_token"] = self.accessToken;
    if (self.refreshToken.length) dict[@"refresh_token"] = self.refreshToken;
    if (self.tokenExpiry) dict[@"expiry"] = @([self.tokenExpiry timeIntervalSince1970]);
    
    NSData *data = [NSJSONSerialization dataWithJSONObject:dict options:0 error:nil];
    if (!data) return;
    
    NSDictionary *q = [self.keyQuery copy];
    OSStatus st = SecItemUpdate((__bridge CFDictionaryRef)q, (__bridge CFDictionaryRef)@{(__bridge id)kSecValueData: data});
    if (st == errSecItemNotFound) {
        NSMutableDictionary *insert = [q mutableCopy];
        insert[(__bridge id)kSecValueData] = data;
        insert[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;
        SecItemAdd((__bridge CFDictionaryRef)insert, NULL);
    }
}

- (void)logout {
    [self stopPolling];
    self.accessToken = nil;
    self.refreshToken = nil;
    self.tokenExpiry = nil;
    self.currentTrack = nil;
    self.currentCover = nil;
    self.currentCoverGray = nil;
    self.currentLyrics = @[];
    _statusNote = @"Logged out of Spotify";
    SecItemDelete((__bridge CFDictionaryRef)[self.keyQuery copy]);
    if (self.onStatusChanged) self.onStatusChanged(_statusNote);
    if (self.onTrackChanged) self.onTrackChanged(nil);
}

#pragma mark - OAuth 2.0 PKCE

- (void)startOAuthFromViewController:(UIViewController *)vc completion:(void(^)(BOOL success, NSString * _Nullable error))completion {
    // 1. Generate code verifier
    uint8_t randomBytes[32];
    if (SecRandomCopyBytes(kSecRandomDefault, sizeof(randomBytes), randomBytes) != errSecSuccess) {
        for (int i = 0; i < 32; i++) randomBytes[i] = (uint8_t)arc4random_uniform(256);
    }
    NSString *verifier = Base64URL([NSData dataWithBytes:randomBytes length:sizeof(randomBytes)]);
    
    // 2. Generate code challenge = Base64URL(SHA256(verifier))
    NSData *vData = [verifier dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char sha[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(vData.bytes, (CC_LONG)vData.length, sha);
    NSString *challenge = Base64URL([NSData dataWithBytes:sha length:sizeof(sha)]);
    
    // 3. Build Auth URL
    NSString *scopes = @"user-read-playback-state user-modify-playback-state user-read-currently-playing";
    NSString *escapedScopes = [scopes stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet];
    NSString *escapedRedirect = [kSpotifyRedirectUri stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet];
    NSString *urlString = [NSString stringWithFormat:
        @"https://accounts.spotify.com/authorize?client_id=%@&response_type=code&redirect_uri=%@&code_challenge_method=S256&code_challenge=%@&scope=%@",
        self.clientId, escapedRedirect, challenge, escapedScopes];
    NSURL *authURL = [NSURL URLWithString:urlString];
    
    // 4. Present ASWebAuthenticationSession
    self.authAnchor = [SpotifyAuthAnchor new];
    self.authAnchor.window = vc.view.window;
    
    __weak typeof(self) weakSelf = self;
    self.authSession = [[ASWebAuthenticationSession alloc] initWithURL:authURL callbackURLScheme:@"rayneo.venus.app" completionHandler:^(NSURL * _Nullable callbackURL, NSError * _Nullable err) {
        weakSelf.authSession = nil;
        if (err || !callbackURL) {
            if (completion) completion(NO, err.localizedDescription ?: @"Authentication was canceled.");
            return;
        }
        
        // Parse code
        NSURLComponents *comp = [NSURLComponents componentsWithURL:callbackURL resolvingAgainstBaseURL:NO];
        NSString *code = nil;
        for (NSURLQueryItem *item in comp.queryItems) {
            if ([item.name isEqual:@"code"]) { code = item.value; break; }
        }
        if (!code.length) {
            if (completion) completion(NO, @"No authorization code returned from Spotify.");
            return;
        }
        
        // Exchange code for token
        [weakSelf exchangeCode:code verifier:verifier completion:completion];
    }];
    self.authSession.presentationContextProvider = self.authAnchor;
    self.authSession.prefersEphemeralWebBrowserSession = NO;
    [self.authSession start];
}

- (void)exchangeCode:(NSString *)code verifier:(NSString *)verifier completion:(void(^)(BOOL, NSString *))completion {
    NSURL *url = [NSURL URLWithString:@"https://accounts.spotify.com/api/token"];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"POST";
    [req setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
    if (self.clientSecret.length > 0) {
        NSString *authStr = [NSString stringWithFormat:@"%@:%@", self.clientId, self.clientSecret];
        NSData *authData = [authStr dataUsingEncoding:NSUTF8StringEncoding];
        NSString *b64 = [authData base64EncodedStringWithOptions:0];
        [req setValue:[NSString stringWithFormat:@"Basic %@", b64] forHTTPHeaderField:@"Authorization"];
    }
    
    NSString *body = [NSString stringWithFormat:
        @"grant_type=authorization_code&code=%@&redirect_uri=%@&client_id=%@&code_verifier=%@",
        [code stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet],
        [kSpotifyRedirectUri stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet],
        [self.clientId stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet],
        [verifier stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet]];
    req.HTTPBody = [body dataUsingEncoding:NSUTF8StringEncoding];
    
    __weak typeof(self) weakSelf = self;
    [[NSURLSession.sharedSession dataTaskWithRequest:req completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
        if (e || !d) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(NO, e.localizedDescription ?: @"Token exchange network error");
            });
            return;
        }
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:d options:0 error:nil];
        NSString *access = json[@"access_token"];
        NSString *refresh = json[@"refresh_token"];
        double expiresIn = [json[@"expires_in"] doubleValue];
        
        if (!access.length) {
            NSString *desc = json[@"error_description"] ?: json[@"error"] ?: @"Token response invalid";
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(NO, desc);
            });
            return;
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            weakSelf.accessToken = access;
            if (refresh.length) weakSelf.refreshToken = refresh;
            weakSelf.tokenExpiry = [NSDate dateWithTimeIntervalSinceNow:MAX(60, expiresIn - 60)];
            [weakSelf saveTokensToKeychain];
            weakSelf.statusNote = @"Spotify connected";
            [weakSelf startPolling];
            if (completion) completion(YES, nil);
            if (weakSelf.onStatusChanged) weakSelf.onStatusChanged(weakSelf.statusNote);
        });
    }] resume];
}

- (void)ensureValidToken:(void(^)(BOOL success))completion {
    if (self.accessToken.length && [self.tokenExpiry timeIntervalSinceNow] > 60) {
        if (completion) completion(YES);
        return;
    }
    if (!self.refreshToken.length) {
        if (completion) completion(NO);
        return;
    }
    if (self.isRefreshing) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            [self ensureValidToken:completion];
        });
        return;
    }
    self.isRefreshing = YES;
    
    NSURL *url = [NSURL URLWithString:@"https://accounts.spotify.com/api/token"];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"POST";
    [req setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
    if (self.clientSecret.length > 0) {
        NSString *authStr = [NSString stringWithFormat:@"%@:%@", self.clientId, self.clientSecret];
        NSData *authData = [authStr dataUsingEncoding:NSUTF8StringEncoding];
        NSString *b64 = [authData base64EncodedStringWithOptions:0];
        [req setValue:[NSString stringWithFormat:@"Basic %@", b64] forHTTPHeaderField:@"Authorization"];
    }
    NSString *body = [NSString stringWithFormat:
        @"grant_type=refresh_token&refresh_token=%@&client_id=%@",
        [self.refreshToken stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet],
        [self.clientId stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet]];
    req.HTTPBody = [body dataUsingEncoding:NSUTF8StringEncoding];
    
    __weak typeof(self) weakSelf = self;
    [[NSURLSession.sharedSession dataTaskWithRequest:req completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
        weakSelf.isRefreshing = NO;
        if (e || !d) {
            dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(NO); });
            return;
        }
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:d options:0 error:nil];
        NSString *newAccess = json[@"access_token"];
        NSString *newRefresh = json[@"refresh_token"];
        double expiresIn = [json[@"expires_in"] doubleValue];
        if (!newAccess.length) {
            dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(NO); });
            return;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            weakSelf.accessToken = newAccess;
            if (newRefresh.length) weakSelf.refreshToken = newRefresh;
            weakSelf.tokenExpiry = [NSDate dateWithTimeIntervalSinceNow:MAX(60, expiresIn - 60)];
            [weakSelf saveTokensToKeychain];
            if (completion) completion(YES);
        });
    }] resume];
}

#pragma mark - Player Polling

- (void)startPolling {
    [self stopPolling];
    [self poll];
    __weak typeof(self) weakSelf = self;
    _pollTimer = [NSTimer scheduledTimerWithTimeInterval:1.5 repeats:YES block:^(NSTimer * _Nonnull t) {
        [weakSelf poll];
    }];
}

- (void)stopPolling {
    [_pollTimer invalidate];
    _pollTimer = nil;
}

- (void)poll {
    if (!self.hasAuth) return;
    __weak typeof(self) weakSelf = self;
    [self ensureValidToken:^(BOOL ok) {
        if (!ok) return;
        NSURL *url = [NSURL URLWithString:@"https://api.spotify.com/v1/me/player"];
        NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
        [req setValue:[NSString stringWithFormat:@"Bearer %@", weakSelf.accessToken] forHTTPHeaderField:@"Authorization"];
        
        [[NSURLSession.sharedSession dataTaskWithRequest:req completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
            NSHTTPURLResponse *http = (NSHTTPURLResponse *)r;
            if (http.statusCode == 204 || !d.length) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    weakSelf.statusNote = @"Spotify is idle (no active player)";
                    if (weakSelf.onStatusChanged) weakSelf.onStatusChanged(weakSelf.statusNote);
                });
                return;
            }
            if (http.statusCode != 200) return;
            
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:d options:0 error:nil];
            if (![json isKindOfClass:NSDictionary.class]) return;
            
            NSDictionary *item = json[@"item"];
            if (![item isKindOfClass:NSDictionary.class]) return;
            
            NSString *tid = item[@"id"];
            NSString *title = item[@"name"] ?: @"";
            NSMutableArray *artists = [NSMutableArray new];
            for (NSDictionary *a in item[@"artists"] ?: @[]) {
                if (a[@"name"]) [artists addObject:a[@"name"]];
            }
            NSString *artist = [artists componentsJoinedByString:@", "] ?: @"";
            double dur = [item[@"duration_ms"] doubleValue];
            double prog = [json[@"progress_ms"] doubleValue];
            BOOL playing = [json[@"is_playing"] boolValue];
            NSString *dev = json[@"device"][@"name"] ?: @"Spotify Device";
            
            // Cover URL (pick 300x300 or first)
            NSArray *images = item[@"album"][@"images"] ?: @[];
            NSString *coverUrl = nil;
            if (images.count > 1 && images[1][@"url"]) coverUrl = images[1][@"url"];
            else if (images.count > 0 && images[0][@"url"]) coverUrl = images[0][@"url"];
            
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf handlePolledTrackId:tid
                                        title:title
                                       artist:artist
                                        album:item[@"album"][@"name"] ?: @""
                                     coverURL:coverUrl
                                   durationMs:dur
                                   progressMs:prog
                                    isPlaying:playing
                                   deviceName:dev];
            });
        }] resume];
    }];
}

- (void)handlePolledTrackId:(NSString *)tid
                      title:(NSString *)title
                     artist:(NSString *)artist
                      album:(NSString *)album
                   coverURL:(NSString *)coverUrl
                 durationMs:(double)duration
                 progressMs:(double)progress
                  isPlaying:(BOOL)isPlaying
                 deviceName:(NSString *)device {
    BOOL isNewTrack = !self.currentTrack || ![self.currentTrack.trackId isEqual:tid];
    
    SpotifyTrack *t = [SpotifyTrack new];
    t.trackId = tid;
    t.name = title;
    t.artist = artist;
    t.album = album;
    t.coverURL = coverUrl;
    t.durationMs = duration;
    t.progressMs = progress;
    t.isPlaying = isPlaying;
    t.deviceName = device;
    self.currentTrack = t;
    
    self.statusNote = [NSString stringWithFormat:@"%@ on %@", isPlaying ? @"Playing" : @"Paused", device];
    if (self.onStatusChanged) self.onStatusChanged(self.statusNote);
    
    if (isNewTrack) {
        NSUInteger ticket = ++_downloadTicket;
        self.currentLyrics = @[];
        self.currentCover = nil;
        self.currentCoverGray = nil;
        
        // 1. Fetch Lyrics from LRCLIB
        [self fetchLyricsForTitle:title artist:artist ticket:ticket];
        
        // 2. Fetch Album Art
        if (coverUrl.length) {
            [self fetchCoverForURL:[NSURL URLWithString:coverUrl] ticket:ticket];
        }
        
        if (self.onTrackChanged) self.onTrackChanged(t);
    } else {
        if (self.onPlaybackStateChanged) self.onPlaybackStateChanged(isPlaying, progress / 1000.0);
    }
}

- (void)fetchLyricsForTitle:(NSString *)title artist:(NSString *)artist ticket:(NSUInteger)ticket {
    NSString *cleanTitle = [title stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet];
    NSString *cleanArtist = [artist stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet];
    NSString *query = [NSString stringWithFormat:@"https://lrclib.net/api/get?track_name=%@&artist_name=%@", cleanTitle, cleanArtist];
    
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:query]];
    [req setValue:@"RayNeo-Glasses-HUD/1.0" forHTTPHeaderField:@"User-Agent"];
    
    __weak typeof(self) weakSelf = self;
    [[NSURLSession.sharedSession dataTaskWithRequest:req completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
        if (ticket != weakSelf.downloadTicket) return;
        NSArray<NSDictionary *> *rows = nil;
        if (d.length) {
            NSDictionary *j = [NSJSONSerialization JSONObjectWithData:d options:0 error:nil];
            NSString *lrc = j[@"syncedLyrics"];
            if ([lrc isKindOfClass:NSString.class] && lrc.length) {
                rows = TMParseLRC(lrc);
            }
        }
        if (!rows.count) {
            rows = @[@{@"ms": @0, @"text": [NSString stringWithFormat:@"%@ · %@", title, artist]}];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (ticket != weakSelf.downloadTicket) return;
            weakSelf.currentLyrics = rows;
            if (weakSelf.onTrackChanged) weakSelf.onTrackChanged(weakSelf.currentTrack);
        });
    }] resume];
}

- (void)fetchCoverForURL:(NSURL *)url ticket:(NSUInteger)ticket {
    __weak typeof(self) weakSelf = self;
    [[NSURLSession.sharedSession dataTaskWithURL:url completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
        if (ticket != weakSelf.downloadTicket || !d.length) return;
        UIImage *raw = [UIImage imageWithData:d];
        if (!raw) return;
        NSData *gray = SpotifyGray(raw);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (ticket != weakSelf.downloadTicket) return;
            weakSelf.currentCover = raw;
            weakSelf.currentCoverGray = gray;
            if (weakSelf.onTrackChanged) weakSelf.onTrackChanged(weakSelf.currentTrack);
        });
    }] resume];
}

#pragma mark - Playback Controls

- (void)sendPlayerCommand:(NSString *)endpoint method:(NSString *)method body:(nullable NSDictionary *)body completion:(nullable void(^)(BOOL))completion {
    __weak typeof(self) weakSelf = self;
    [self ensureValidToken:^(BOOL ok) {
        if (!ok) { if (completion) completion(NO); return; }
        NSURL *url = [NSURL URLWithString:[@"https://api.spotify.com/v1/me/player/" stringByAppendingString:endpoint]];
        NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
        req.HTTPMethod = method;
        [req setValue:[NSString stringWithFormat:@"Bearer %@", weakSelf.accessToken] forHTTPHeaderField:@"Authorization"];
        if (body) {
            [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
            req.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
        }
        [[NSURLSession.sharedSession dataTaskWithRequest:req completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
            NSHTTPURLResponse *http = (NSHTTPURLResponse *)r;
            BOOL success = (http.statusCode >= 200 && http.statusCode < 300);
            dispatch_async(dispatch_get_main_queue(), ^{
                // Poll immediately after a command to update state fast
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [weakSelf poll];
                });
                if (completion) completion(success);
            });
        }] resume];
    }];
}

- (void)playWithCompletion:(void(^)(BOOL))completion {
    [self sendPlayerCommand:@"play" method:@"PUT" body:nil completion:completion];
}

- (void)pauseWithCompletion:(void(^)(BOOL))completion {
    [self sendPlayerCommand:@"pause" method:@"PUT" body:nil completion:completion];
}

- (void)nextTrackWithCompletion:(void(^)(BOOL))completion {
    [self sendPlayerCommand:@"next" method:@"POST" body:nil completion:completion];
}

- (void)previousTrackWithCompletion:(void(^)(BOOL))completion {
    [self sendPlayerCommand:@"previous" method:@"POST" body:nil completion:completion];
}

- (void)seekToSeconds:(double)seconds completion:(void(^)(BOOL))completion {
    long ms = (long)(seconds * 1000.0);
    NSString *endpoint = [NSString stringWithFormat:@"seek?position_ms=%ld", ms];
    [self sendPlayerCommand:endpoint method:@"PUT" body:nil completion:completion];
}

@end
