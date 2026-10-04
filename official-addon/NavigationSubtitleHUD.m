#import "NavigationSubtitleHUD.h"
#import "NavigationCore.h"
#import <math.h>

static NSString *CenterPad(NSString *text, NSUInteger targetWidth) {
    if (!text.length) return @"";
    if (text.length >= targetWidth) return text;
    NSUInteger pad = (targetWidth - text.length) / 2;
    NSString *spaces = [@"" stringByPaddingToLength:pad withString:@" " startingAtIndex:0];
    return [spaces stringByAppendingString:text];
}

static NSString *CleanRoad(NSString *r) {
    if (!r.length) return @"Follow route";
    NSString *cleaned = r;
    if ([cleaned hasPrefix:@"Onto "]) cleaned = [cleaned substringFromIndex:5];
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"^(Walk|Head|Drive|Ride)\\s+(north|south|east|west|northeast|northwest|southeast|southwest)\\s+on\\s+" options:NSRegularExpressionCaseInsensitive error:nil];
    cleaned = [regex stringByReplacingMatchesInString:cleaned options:0 range:NSMakeRange(0, cleaned.length) withTemplate:@""];
    return cleaned.length ? cleaned : r;
}

static NSString *CleanSummary(NSString *s) {
    if (!s.length) return @"";
    if ([s hasPrefix:@"Remaining "]) s = [s substringFromIndex:10];
    s = [s stringByReplacingOccurrencesOfString:@"approx " withString:@""];
    return s;
}

static NSString *CharClip(NSString *text, NSUInteger maxChars) {
    if (![text isKindOfClass:NSString.class] || !text.length) return @"";
    if (text.length <= maxChars) return text;
    __block NSUInteger count = 0;
    NSMutableString *result = [NSMutableString new];
    [text enumerateSubstringsInRange:NSMakeRange(0, text.length)
                             options:NSStringEnumerationByComposedCharacterSequences
                          usingBlock:^(NSString *substring, NSRange substringRange, NSRange enclosingRange, BOOL *stop) {
        if (count >= maxChars) {
            *stop = YES;
            return;
        }
        [result appendString:substring];
        count++;
    }];
    return result;
}

NSString *TIONavSubtitleText(NSDictionary *f){
    if(![f isKindOfClass:NSDictionary.class])return nil;
    NSString *phase=f[@"phase"];
    if(![phase isEqual:@"navigating"]&&![phase isEqual:@"ready"])return nil;
    
    NSString *turn=f[@"turn"]?:@"Continue";
    NSString *dist=f[@"distance"]?:@"";
    NSString *arrow=f[@"arrow"]?:@"";
    NSString *road=CleanRoad(f[@"road"]?:@"");
    NSString *nextTurn=f[@"nextTurn"];
    NSString *summary=CleanSummary(f[@"summary"]?:@"");
    NSString *eta=f[@"eta"]?:@"";
    NSString *modeEmoji=f[@"modeEmoji"]?:@"";
    
    // Line 1: Arrow + Maneuver + Step Distance (e.g. "⬆ Continue straight · 29 m")
    NSMutableString *line1 = [NSMutableString new];
    if (arrow.length > 0) {
        [line1 appendFormat:@"%@ ", arrow];
    }
    [line1 appendString:turn];
    if (dist.length > 0) {
        [line1 appendFormat:@" · %@", dist];
    }
    NSString *line1Str = CharClip(line1, 30);
    
    // Line 2: Next turn preview if available, else clean current road name (e.g. "Then: ↱ Turn right onto Acol Rd")
    NSString *line2Str = nextTurn.length > 0 ? CharClip(nextTurn, 32) : CharClip(road, 32);
    
    // Line 3: Mode Emoji + Trip Summary (Dist · Time) + Clock ETA (e.g. "🚶 2.5 km · 35 min · ETA 17:45")
    NSMutableString *line3 = [NSMutableString new];
    if (modeEmoji.length > 0) {
        [line3 appendFormat:@"%@ ", modeEmoji];
    }
    if (summary.length > 0) {
        [line3 appendString:summary];
    }
    if (eta.length > 0) {
        if (line3.length > 0) {
            [line3 appendFormat:@" · %@", eta];
        } else {
            [line3 appendString:eta];
        }
    }
    NSString *line3Str = CharClip(line3, 32);
    
    // Center padding with target width 28 chars
    NSUInteger w = 28;
    NSString *c1 = CenterPad(line1Str, w);
    NSString *c2 = CenterPad(line2Str, w);
    NSString *c3 = line3Str.length ? CenterPad(line3Str, w) : @"";
    
    if (c3.length > 0) {
        return [NSString stringWithFormat:@"%@\n%@\n%@", c1, c2, c3];
    } else {
        return [NSString stringWithFormat:@"%@\n%@", c1, c2];
    }
}

@implementation TIONavSubtitleHUD {
    BOOL _enabled;
    NSString *_sid,*_latest,*_sent,*_note;
    NSTimeInterval _latestAt,_began,_lastSent;
    NSUInteger _frames;
}

- (instancetype)init{if((self=[super init]))_note=@"Subtitle navigation not active";return self;}
- (NSDictionary *)status{return @{@"version":@"nav-subtitle-v1",@"enabled":@(_enabled),@"frames":@(_frames),@"note":_note?:@""};}

- (BOOL)startWithFrame:(NSDictionary *)frame at:(NSTimeInterval)now{
    NSString *text=TIONavSubtitleText(frame);
    if(_enabled||!text||!isfinite(now))return NO;
    NSString *sid=TIOSubtitleNavigationStart();
    if(!sid){
        _note=@"Not started: check glasses Bluetooth connection";
        return NO;
    }
    _sid=sid;_enabled=YES;_latest=text;_latestAt=_began=now;_sent=nil;_frames=0;_lastSent=0;
    _note=@"Streaming turn guidance to glasses";
    return YES;
}

- (void)offer:(NSDictionary *)frame at:(NSTimeInterval)now{
    if(!_enabled)return;
    NSString *text=TIONavSubtitleText(frame);
    if(!text||!isfinite(now)){return;}
    _latest=text;_latestAt=now;
}

- (void)pumpAt:(NSTimeInterval)now{
    if(!_enabled)return;
    NSDictionary *s=TIOSubtitleNavigationStatus();
    if(![s[@"sid"] isEqual:_sid]||![s[@"navigation"] boolValue]||![@[@"starting",@"ready"] containsObject:s[@"phase"]]){
        [self stop:@"Subtitle session ended"];
        return;
    }
    // Allow up to 600s (10 mins) between GPS updates
    if(!isfinite(now)||now<_latestAt||now-_latestAt>600){
        [self stop:@"Navigation paused or idle for 10 mins"];
        return;
    }
    if(now-_began>=14400||_frames>=5000){
        [self stop:@"4-hour navigation limit reached"];
        return;
    }
    if(![s[@"phase"] isEqual:@"ready"]||[s[@"pending"] boolValue])return;
    BOOL isUnchanged=[_latest isEqual:_sent];
    BOOL keepAliveNeeded=isUnchanged&&(_frames>0)&&(now-_lastSent>=5.0);
    if(isUnchanged&&!keepAliveNeeded)return;
    if(_frames&&now-_lastSent<2.8)return;
    if(!TIOSubtitleNavigationText(_sid,_latest)){
        [self stop:@"Text submission to glasses failed"];
        return;
    }
    _frames++;_sent=_latest;_lastSent=now;
    _note=@"Streaming guidance to glasses";
}

- (void)stop:(NSString *)reason{
    if(!_enabled)return;
    NSString *sid=_sid;
    _enabled=NO;_sid=nil;_latest=nil;
    TIOSubtitleNavigationStop(sid,reason);
    _note=[NSString stringWithFormat:@"%@; HUD subtitles stopped",reason?:@"Subtitle navigation stopped"];
}
@end
