#import "NavigationCore.h"
#import "A2UIProbe.h"
#include <math.h>
BOOL TIONavCoordinate(double lat,double lon){return isfinite(lat)&&isfinite(lon)&&lat>=-90&&lat<=90&&lon>=-180&&lon<=180;}
NSString *TIONavClip(NSString *text,NSUInteger limit){
    if(![text isKindOfClass:NSString.class])return @"";
    NSMutableString *out=[NSMutableString new];__block NSUInteger used=0;
    [text enumerateSubstringsInRange:NSMakeRange(0,text.length) options:NSStringEnumerationByComposedCharacterSequences usingBlock:^(NSString *s,NSRange r,NSRange all,BOOL *stop){NSUInteger n=[s lengthOfBytesUsingEncoding:NSUTF8StringEncoding];if(used+n>limit){*stop=YES;return;}[out appendString:s];used+=n;}];return out;
}
NSString *TIONavTurn(NSInteger icon){
    // AMapNaviIconType, pinned 11.2.100. Unknown values never imply straight ahead.
    switch(icon){case 2:return @"Turn Left Ahead";case 3:return @"Turn Right Ahead";case 4:return @"Bear Left Ahead";case 5:return @"Bear Right Ahead";case 6:return @"Sharp Left Ahead";case 7:return @"Sharp Right Ahead";case 8:case 19:return @"U-turn ahead";case 9:case 20:return @"Continue straight";case 10:return @"Arrive at Waypoint";case 11:case 17:return @"Enter Roundabout";case 12:case 18:return @"Leave Roundabout";case 15:return @"Arrive at Destination";case 29:return @"through crosswalk";case 30:return @"via overpass";case 31:return @"through underground passage";default:return @"Please see mobile phone guidelines";}
}
static NSString *Distance(NSInteger meters){if(meters<0)return @"Distance Updating";if(meters>=1000)return [NSString stringWithFormat:@"%.1f kilometers",meters/1000.0];NSInteger rounded=meters<50?meters:(meters/10)*10;return [NSString stringWithFormat:@"%ld meters",(long)rounded];}
NSDictionary *TIONavDisplay(NSString *phase,NSInteger icon,NSString *road,NSInteger distance,NSInteger remaining,NSInteger seconds,BOOL sim){
    NSDictionary *titles=@{@"planning":@"Planning Route",@"rerouting":@"Re-routing",@"weak":@"Weak GPS Signal",@"stale":@"Guidance Updating",@"arrived":@"Destination reached",@"stopped":@"Navigation has stopped",@"error":@"Navigation is currently unavailable"};
    BOOL running=[phase isEqual:@"navigating"];NSString *title=running?TIONavTurn(icon):(titles[phase]?:@"Please check your phone");
    NSString *detail=running?(road.length?[@"Enter" stringByAppendingString:road]:@"Follow road signs and signals"):@"Please check your mobile phone and do not rely on old guidance";
    NSString *summary=running?[NSString stringWithFormat:@"Remaining %@ · %@",Distance(remaining),seconds>=0?[NSString stringWithFormat:@"About %ld minutes",(long)MAX(1,(NSInteger)ceil(seconds/60.0))]:@"Time to be updated"]:@"";
    return @{@"phase":phase?:@"unknown",@"meters":@(distance),@"icon":@(icon),@"simulated":@(sim),@"mode":sim?@"Simulated navigation · non-actual positioning":@"Real-time navigation·Amap",@"turn":title,@"distance":running?Distance(distance):@"",@"road":TIONavClip(detail,210),@"summary":summary};
}
NSString *TIONavNoticeKey(NSDictionary *d){
    if(![d isKindOfClass:NSDictionary.class])return nil;
    NSString *phase=d[@"phase"];
    if(![@[@"navigating",@"rerouting",@"weak",@"stale",@"arrived",@"error"] containsObject:phase])return nil;
    for(NSString *k in @[@"mode",@"turn",@"distance",@"road",@"summary"])if(![d[k] isKindOfClass:NSString.class])return nil;
    if(![d[@"meters"] isKindOfClass:NSNumber.class])return nil;
    NSInteger m=[d[@"meters"] integerValue],bucket=m<0?-1:m<=20?20:m<=50?50:m<=100?100:m<=200?200:1000;
    return [[NSString alloc]initWithData:[NSJSONSerialization dataWithJSONObject:@[phase,d[@"turn"],d[@"road"],d[@"mode"],@(bucket)] options:0 error:nil] encoding:NSUTF8StringEncoding];
}
NSDictionary *TIONavNotice(NSString *uid,NSDictionary *d,NSDate *date){
    if(![uid isKindOfClass:NSString.class]||uid.longLongValue<=0||uid.longLongValue>INT32_MAX||![[NSString stringWithFormat:@"%lld",uid.longLongValue] isEqual:uid]||!TIONavNoticeKey(d)||!date||!isfinite(date.timeIntervalSince1970))return nil;
    NSDateFormatter *f=[NSDateFormatter new];f.locale=[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];f.calendar=[[NSCalendar alloc]initWithCalendarIdentifier:NSCalendarIdentifierGregorian];f.timeZone=NSTimeZone.localTimeZone;f.dateFormat=@"yyyy-MM-dd'T'HH:mm:ss.SSS";
    return @{@"notificationUID":uid,@"appId":@"com.yunlong.rayneo.companion",@"appName":@"Turbo IO",@"title":TIONavClip([@"Navigation ·" stringByAppendingString:d[@"turn"]],180),@"subtitle":@"",@"content":TIONavClip([NSString stringWithFormat:@"%@ %@\n%@\n%@",d[@"mode"],d[@"distance"],d[@"road"],d[@"summary"]],600),@"timestamp":[f stringFromDate:date],@"category":@0,@"reply":@NO,@"type":@1};
}
NSDictionary *TIONavInstall(NSString *identifier,NSDictionary *display){
    if(!TIOA2UIUninstall(identifier)||![display isKindOfClass:NSDictionary.class])return nil;
    for(NSString *k in @[@"mode",@"turn",@"distance",@"road",@"summary"])if(![display[k] isKindOfClass:NSString.class]||[display[k] lengthOfBytesUsingEncoding:NSUTF8StringEncoding]>240)return nil;
    NSMutableArray *c=[NSMutableArray arrayWithArray:@[
        @{@"id":@"root",@"component":@"Column",@"children":@[@"mode",@"heading",@"road",@"line",@"summary"],@"align":@"stretch"},
        @{@"id":@"heading",@"component":@"Row",@"children":@[@"turn",@"distance"],@"justify":@"spaceBetween",@"align":@"center"},
        @{@"id":@"line",@"component":@"Divider",@"axis":@"horizontal"}]];
    for(NSString *k in @[@"mode",@"turn",@"distance",@"road",@"summary"])[c addObject:@{@"id":k,@"component":@"Text",@"text":display[k],@"variant":[k isEqual:@"distance"]?@"h3":[k isEqual:@"turn"]?@"h5":[k isEqual:@"mode"]?@"caption":@"body"}];
    NSDictionary *e=@{@"widgetId":identifier,@"name":@"Turbo IO Navigation",@"uiContent":@{@"createSurface":@{@"surfaceId":identifier,@"catalogId":@"https://rayneo.com/a2ui/catalogs/glasses-base/v1/catalog.json"},@"updateComponents":@{@"surfaceId":identifier,@"components":c}}};
    NSString *extra=[[NSString alloc]initWithData:[NSJSONSerialization dataWithJSONObject:e options:NSJSONWritingSortedKeys error:nil] encoding:NSUTF8StringEncoding];
    return @{@"cmd":@"widget_install",@"payload":@{@"data":@{@"type":@"a2ui",@"id":identifier,@"name":@"Turbo IO Navigation",@"extras":extra}}};
}
@implementation TIONavQueue {NSDictionary *_latest,*_inflight,*_committed;NSTimeInterval _sentAt;BOOL _blocked,_hasSent;}
- (NSDictionary *)latest{return _latest;}- (NSDictionary *)inflight{return _inflight;}- (BOOL)blocked{return _blocked;}
- (void)offer:(NSDictionary *)d{_latest=[d copy];}
- (NSDictionary *)takeAt:(NSTimeInterval)now{if(_blocked||_inflight||!_latest||(_hasSent&&now-_sentAt<1)||[_latest isEqual:_committed])return nil;_inflight=_latest;_sentAt=now;_hasSent=YES;return _inflight;}
- (void)acknowledge:(BOOL)ok{if(!_inflight)return;if(ok)_committed=_inflight;else _blocked=YES;_inflight=nil;}
- (void)reset{_latest=nil;_inflight=nil;_committed=nil;_blocked=NO;_hasSent=NO;_sentAt=0;}
@end
