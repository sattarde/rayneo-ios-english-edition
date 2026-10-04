#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, TMMusicSource) {
    TMMusicSourceSpotify = 0,
    TMMusicSourceNetEase = 1
};

FOUNDATION_EXPORT UIViewController *TMMusicController(void);
FOUNDATION_EXPORT BOOL TMMusicConsume(NSDictionary *);
FOUNDATION_EXPORT BOOL TMMusicPauseForOTA(void);
FOUNDATION_EXPORT void TMMusicPauseForVoice(void);

@interface TMPlayer : NSObject

+ (instancetype)shared;

@property (nonatomic) TMMusicSource source;
@property (nonatomic, readonly) NSDictionary *song;
@property (nonatomic, readonly) NSArray *lyrics;
@property (nonatomic, readonly) UIImage *cover;
@property (nonatomic, readonly) BOOL playing;
@property (nonatomic, readonly) double position, duration;
@property (nonatomic, readonly) NSString *status, *bridgeStatus;
@property (nonatomic) NSInteger mode;
@property (nonatomic) BOOL glasses;

- (void)playSong:(NSDictionary *)song queue:(NSArray *)queue;
- (void)play:(BOOL)value;
- (void)step:(NSInteger)delta;
- (void)seek:(double)seconds;
- (void)demo;
- (void)showOnGlasses;
- (void)hideGlasses;

@end
