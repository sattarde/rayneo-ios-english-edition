#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SpotifyTrack : NSObject
@property (nonatomic, copy) NSString *trackId;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *artist;
@property (nonatomic, copy) NSString *album;
@property (nonatomic, copy) NSString *coverURL;
@property (nonatomic) double durationMs;
@property (nonatomic) double progressMs;
@property (nonatomic) BOOL isPlaying;
@property (nonatomic, copy) NSString *deviceName;
@end

@interface SpotifyAPI : NSObject

+ (instancetype)shared;

@property (nonatomic, copy) NSString *clientId;
@property (nonatomic, copy) NSString *clientSecret;
@property (nonatomic, readonly) BOOL hasAuth;
@property (nonatomic, readonly) BOOL isPolling;
@property (nonatomic, readonly, nullable) SpotifyTrack *currentTrack;
@property (nonatomic, readonly, nullable) UIImage *currentCover;
@property (nonatomic, readonly, nullable) NSData *currentCoverGray;
@property (nonatomic, readonly) NSArray<NSDictionary *> *currentLyrics;
@property (nonatomic, readonly) NSString *statusNote;

// Callbacks
@property (nonatomic, copy, nullable) void(^onTrackChanged)(SpotifyTrack * _Nullable track);
@property (nonatomic, copy, nullable) void(^onPlaybackStateChanged)(BOOL isPlaying, double positionSec);
@property (nonatomic, copy, nullable) void(^onStatusChanged)(NSString *status);

- (void)startOAuthFromViewController:(UIViewController *)vc completion:(void(^)(BOOL success, NSString * _Nullable error))completion;
- (void)logout;

- (void)startPolling;
- (void)stopPolling;

- (void)playWithCompletion:(nullable void(^)(BOOL ok))completion;
- (void)pauseWithCompletion:(nullable void(^)(BOOL ok))completion;
- (void)nextTrackWithCompletion:(nullable void(^)(BOOL ok))completion;
- (void)previousTrackWithCompletion:(nullable void(^)(BOOL ok))completion;
- (void)seekToSeconds:(double)seconds completion:(nullable void(^)(BOOL ok))completion;

@end

NS_ASSUME_NONNULL_END
