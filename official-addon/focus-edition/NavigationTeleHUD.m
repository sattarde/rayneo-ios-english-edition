#import "NavigationTeleHUD.h"
#import "NewsTeleprompter.h"
#import "NavigationCore.h"
#include <math.h>
NSString *TIONavTeleKey(NSDictionary *f){
    if(![f isKindOfClass:NSDictionary.class]||![f[@"phase"] isEqual:@"navigating"]||![f[@"mode"] isEqual:@"Simulated navigation · non-actual positioning"])return nil;
    for(NSString *k in @[@"turn",@"road",@"distance"])if(![f[k] isKindOfClass:NSString.class]||[f[k] lengthOfBytesUsingEncoding:NSUTF8StringEncoding]>240)return nil;
    id segment=f[@"segment"];if(![segment isKindOfClass:NSNumber.class]||CFGetTypeID((__bridge CFTypeRef)segment)==CFBooleanGetTypeID())return nil;
    double n=[segment doubleValue];if(!isfinite(n)||n<0||n>100000||n!=[segment integerValue])return nil;
    return [[NSString alloc]initWithData:[NSJSONSerialization dataWithJSONObject:@[segment,f[@"turn"],f[@"road"]] options:0 error:nil] encoding:NSUTF8StringEncoding];
}
NSString *TIONavTeleText(NSDictionary *f,NSUInteger sequence){
    if(!TIONavTeleKey(f)||!sequence||sequence>13)return nil;
    return [NSString stringWithFormat:@"AutoNavi simulated navigation %02lu\n%@\n%@\n Update time distance steering: %@\n Only updated when instructions change, non-real-time distance \n Please refer to the mobile map",(unsigned long)sequence,TIONavClip(f[@"turn"],120),TIONavClip(f[@"road"],150),TIONavClip(f[@"distance"],60)];
}
@implementation TIONavTeleHUD {
    BOOL _enabled,_owns,_starting,_waiting;
    NSNumber *_session;
    NSDictionary *_latest;
    NSString *_committed,*_pendingKey,*_note;
    NSTimeInterval _latestAt,_lastSent,_startedAt;
    NSUInteger _frames;
}
- (instancetype)init{if((self=[super init]))_note=@"Always-on guidance disabled; obtain manual teleprompter template first";return self;}
- (NSDictionary *)status{return @{@"version":@"nav-tele-v1",@"enabled":@(_enabled),@"owns":@(_owns),@"waiting":@(_waiting||_starting),@"frames":@(_frames),@"note":_note?:@""};}
- (BOOL)matches:(NSDictionary *)s{return _owns&&[s[@"navigation"] boolValue]&&[s[@"sessionEpoch"] isEqual:_session];}
- (BOOL)enable{
    NSDictionary *s=TIONewsTeleStatus();
    if(_enabled||_owns||[s[@"active"] boolValue]||![s[@"manualAvailable"] boolValue]){_note=@"Cannot be opened: Please end existing prompts first and obtain the official manual preparation/start/exit template";return NO;}
    _enabled=YES;_latest=nil;_committed=_pendingKey=nil;_frames=0;_waiting=_starting=NO;_note=@"Already enabled, waiting for Amap simulated route instructions";return YES;
}
- (void)stop:(NSString *)reason{
    NSDictionary *s=TIONewsTeleStatus();BOOL matched=[self matches:s];
    _enabled=NO;_owns=NO;_starting=_waiting=NO;_latest=nil;_session=nil;
    // Never stop another owner even if it is also a navigation/manual session.
    if(matched&&! [s[@"stopping"] boolValue])TIONewsTeleControl(6,120);
    _note=[NSString stringWithFormat:@"%@%@",reason?:@"Always on to guide stop",matched?@"; Requested to exit, lens closing needs confirmation":@""];
}
- (void)offer:(NSDictionary *)f at:(NSTimeInterval)now{
    if(!_enabled||!isfinite(now))return;
    if(!TIONavTeleKey(f)){[self stop:@"The route is temporarily unavailable/not a simulated route, and the old guidance will be discontinued."];return;}
    _latest=[f copy];_latestAt=now;
}
- (void)pumpAt:(NSTimeInterval)now{
    if(!_enabled||!isfinite(now))return;
    NSDictionary *s=TIONewsTeleStatus();
    if(_owns&&(![self matches:s]||[s[@"stopping"] boolValue]||[s[@"manualBlocked"] boolValue])){[self stop:@"The prompt has exited, timed out or is abnormal, and needs to be re-enabled manually."];return;}
    if(!_latest)return;
    if(now-_latestAt>15||now<_latestAt){[self stop:@"Amap's instructions have not been updated for more than 15 seconds, so the old instructions will be stopped."];return;}
    if(_owns&&now-_startedAt>=300){[self stop:@"The 5-minute simulation acceptance ends"];return;}
    NSString *key=TIONavTeleKey(_latest);
    if(!_owns){
        if(!TIOTeleNavigationPrepare(TIONavTeleText(_latest,1))){[self stop:@"Navigation draft preparation failed; no preemption or retry"];return;}
        s=TIONewsTeleStatus();_session=s[@"sessionEpoch"];_owns=YES;_starting=YES;_pendingKey=key;_lastSent=_startedAt=now;_frames=1;_note=@"The first frame is being prepared; manual display will automatically start after the manuscript is successfully received.";return;
    }
    if(_starting){
        if(![s[@"ready"] boolValue])return;
        if(![s[@"started"] boolValue]){if(!TIONewsTeleControl(3,120))[self stop:@"Navigation prompt startup failed"];return;}
        if(![s[@"playing"] boolValue]||[s[@"manualPending"] unsignedIntegerValue])return;
        _starting=NO;_committed=_pendingKey;_pendingKey=nil;_note=@"The always-on command has started; the transmission loading will appear when changing the manuscript.";
    }
    if(_waiting){
        if([s[@"replacing"] boolValue]||![s[@"ready"] boolValue])return;
        _waiting=NO;_committed=_pendingKey;_pendingKey=nil;_note=@"The new instruction has been received and confirmed; the actual lens effect needs to be verified";
    }
    if(![s[@"playing"] boolValue]){[self stop:@"The prompt has been paused and the navigation display update has been stopped."];return;}
    // One second slack relative to the transport's independent 15s guard.
    if([key isEqual:_committed]||now-_lastSent<16)return;
    if(_frames>=13){[self stop:@"The 13-frame acceptance limit for this round has been reached and updates will be stopped."];return;}
    if(!TIOTeleNavigationReplace(TIONavTeleText(_latest,_frames+1))){[self stop:@"The navigation draft has not been submitted. Stop updating and try again without looping."];return;}
    _frames++;_lastSent=now;_pendingKey=key;_waiting=YES;_note=@"Turn/road section changes, waiting for new draft receipt; merged and updated in progress";
}
@end
