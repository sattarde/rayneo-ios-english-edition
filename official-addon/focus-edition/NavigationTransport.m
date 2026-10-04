#import "NavigationTransport.h"
#import "NavigationCore.h"
#import "A2UIProbe.h"
#import "ProtocolContext.h"
#import <UIKit/UIKit.h>
#import <objc/message.h>
// Main-thread only. Separate owner and request state from the existing A2UI probe.
static __weak id NavPlugin;
static NSDictionary *NavRoute;
static NSString *NavDevice,*NavOwner,*NavOperation,*NavNote=@"Read glasses connection before enabling card";
static NSTimeInterval NavLease,NavDeadline,NavBaselineAt;
static uint32_t NavSequence;
static BOOL NavSending,NavEnabled,NavRemove,NavUncertain;
static NSUInteger AfterBaseline;
static TIONavQueue *NavQueue;
static BOOL NoticeEnabled,NoticeWaiting;
static NSString *NoticeUID,*NoticeKey,*NoticeNote=@"Notice mode disabled · Does not alter official notification settings";
static NSDictionary *NoticeLatest;
static NSTimeInterval NoticeDeadline,NoticeNext;
static void PumpNotice(void);
static id Value(id o,NSString *k){@try{return [o valueForKey:k];}@catch(NSException *e){return nil;}}
static NSData *Bytes(id o){if([o isKindOfClass:NSData.class])return o;id d=Value(o,@"data");return [d isKindOfClass:NSData.class]?d:nil;}
static NSTimeInterval Now(void){return NSProcessInfo.processInfo.systemUptime;}
static void Change(NSString *s){NavNote=s;[NSNotificationCenter.defaultCenter postNotificationName:@"TIONavigationChanged" object:nil];}
static void NoticeChange(NSString *s){
    NoticeNote=s;
    // Private metadata only: no device ID, road, coordinates, message text or keys.
    NSString *dir=[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/TurboIOResearch/navigation"];
    [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:@{NSFileProtectionKey:NSFileProtectionCompleteUntilFirstUserAuthentication} error:nil];
    NSDictionary *report=@{@"version":@"nav-notice-v1",@"time":@(NSDate.date.timeIntervalSince1970),@"note":s,@"uid":NoticeUID?:@"",@"waiting":@(NoticeWaiting),@"enabled":@(NoticeEnabled)};
    [[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:nil] writeToFile:[dir stringByAppendingPathComponent:@"notification-status.json"] options:NSDataWritingAtomic error:nil];
    [NSNotificationCenter.defaultCenter postNotificationName:@"TIONavigationChanged" object:nil];
}
static NSString *OwnerKey(void){return [@"io.turboio.navigation.owner." stringByAppendingString:NavDevice?:@""];}
void TIONavObserveCall(id plugin,NSString *method,NSDictionary *args){
    if(NavSending||![method isEqual:@"rayneonet_sendMessage"]||![args[@"deviceId"] isKindOfClass:NSString.class])return;
    TIOProtocolObserveCall(plugin,method,args);
    NSString *d=args[@"deviceId"];if(!d.length)return;
    if(![NavDevice isEqual:d]){TIONavEnableNotices(NO);NoticeKey=nil;NavEnabled=NO;NavRemove=NO;NavSequence=0;NavBaselineAt=0;NavUncertain=NO;NavQueue=[TIONavQueue new];NavDevice=d;NSString *owner=[NSUserDefaults.standardUserDefaults stringForKey:OwnerKey()];NavOwner=TIOA2UIUninstall(owner)?owner:nil;Change(@"Device observed, please read connection baseline");}
    NavPlugin=plugin;NavLease=Now();NSMutableDictionary *r=[args mutableCopy];[r removeObjectForKey:@"payload"];NavRoute=r;
}
static BOOL Send(NSDictionary *json,NSString *op){
    BOOL query=[op isEqual:@"query"];
    if(!NavPlugin&&TIOProtocolPlugin())TIONavObserveCall(TIOProtocolPlugin(),@"rayneonet_sendMessage",TIOProtocolRoute(15));
    if(!NSThread.isMainThread||NavSequence||!NavPlugin||!NavRoute||!NavDevice||![TIOProtocolDevice() isEqual:NavDevice]||(!query&&Now()-NavLease>120))return NO;
    if(!NavEnabled&&UIApplication.sharedApplication.applicationState!=UIApplicationStateActive)return NO;
    Class typed=NSClassFromString(@"FlutterStandardTypedData"),call=NSClassFromString(@"FlutterMethodCall");SEL mk=NSSelectorFromString(@"methodCallWithMethodName:arguments:"),td=NSSelectorFromString(@"typedDataWithBytes:"),handle=NSSelectorFromString(@"handleMethodCall:result:");
    if(![typed respondsToSelector:td]||![call respondsToSelector:mk]||![NavPlugin respondsToSelector:handle])return NO;
    uint32_t seq=arc4random_uniform(0x10000000)+0x60000000;NSData *p=TIOA2UIPacket(18,seq,json);if(!p)return NO;
    NSMutableDictionary *args=[NavRoute mutableCopy];args[@"businessId"]=@15;args[@"payload"]=((id(*)(id,SEL,id))objc_msgSend)(typed,td,p);id c=((id(*)(id,SEL,id,id))objc_msgSend)(call,mk,@"rayneonet_sendMessage",args);
    NavSequence=seq;NavOperation=op;NavDeadline=Now()+12;NavSending=YES;
    @try{((void(*)(id,SEL,id,id))objc_msgSend)(NavPlugin,handle,c,[^(id result){/* RNLink submission is not a lens ACK. Never log payloads or route coordinates. */} copy]);}
    @catch(NSException *e){NavSequence=0;NavUncertain=YES;NavEnabled=NO;[NavQueue acknowledge:NO];Change(@"Transmission abnormal, result unknown; please re-read the connection, do not rely on the old guidance of the lens");}
    NavSending=NO;return NavSequence!=0;
}
void TIONavRefreshConnection(void){
    if(NavSequence){Change(@"Previous request pending, please try again later");return;}
    TIONavEnableNotices(NO);
    NavEnabled=NO;NavBaselineAt=0;
    if(!Send(@{@"cmd":@"dashboard_config",@"payload":@{@"version":@1,@"value":@0}},@"query"))Change(@"Unread: Please go back to the official homepage to confirm the glasses connection and keep your mobile phone in the foreground");
    else Change(@"Reading dashboard baseline, waiting for glasses to send back");
}
static BOOL AutoBaseline(NSUInteger action){
    if(NavSequence){Change(@"Waiting for connection receipt, please wait");return NO;}
    TIONavRefreshConnection();if(NavSequence){AfterBaseline=action;return YES;}return NO;
}
void TIONavObserveEvent(NSDictionary *event){
    if(![event[@"eventType"] isEqual:@"messageReceived"])return;
    NSDictionary *m=event[@"message"];if(![m isKindOfClass:NSDictionary.class]||![m[@"deviceId"] isEqual:NavDevice])return;
    if([m[@"businessId"] isEqual:@21]){
        NSDictionary *wire=TIOA2UIDecode(Bytes(m[@"payload"])),*j=wire[@"json"];
        if(![wire[@"type"] isEqual:@3]||!NoticeUID||![j[@"notificationUID"] isEqual:NoticeUID])return;
        NSNumber *state=j[@"state"];if(![state isKindOfClass:NSNumber.class]||CFGetTypeID((__bridge CFTypeRef)state)==CFBooleanGetTypeID()||state.doubleValue!=state.integerValue)return;
        NoticeWaiting=NO;NavLease=Now();NSInteger n=state.integerValue;
        NSString *label=@{@0:@"Idle (does not mean read)",@1:@"Displaying or interval, need to check the lens",@2:@"Not wearing",@3:@"Do not disturb",@4:@"Used by other glasses functions"}[state]?:@"unknown status";
        if(n<0||n>1){NoticeEnabled=NO;NoticeLatest=nil;}
        NoticeChange([NSString stringWithFormat:@"Same UID return: %@ (%ld) %@",label,(long)n,(n<0||n>1)?@";Automatic reminder paused":@""]);return;
    }
    if(![m[@"businessId"] isEqual:@15])return;
    NSDictionary *e=TIOA2UIDecode(Bytes(m[@"payload"]));if(![e[@"type"] isEqual:@19]||!NavSequence)return;
    NSDictionary *j=e[@"json"];uint32_t seq=[e[@"sequence"] unsignedIntValue];
    if([NavOperation isEqual:@"query"]&&[j[@"cmd"] isEqual:@"dashboard_config"]&&(seq==NavSequence||seq==0)){
        id payload=j[@"payload"],body=[payload isKindOfClass:NSDictionary.class]?payload[@"data"]:nil;
        if([body isKindOfClass:NSString.class])body=[NSJSONSerialization JSONObjectWithData:[body dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
        if(![body isKindOfClass:NSDictionary.class]||![body[@"widgets_v2"] isKindOfClass:NSArray.class])return;
        for(id row in body[@"widgets_v2"])if([row isKindOfClass:NSDictionary.class]&&[row[@"id"] isEqual:NavOwner]&&![row[@"type"] isEqual:@"a2ui"]){NavSequence=0;NavUncertain=YES;Change(@"The ownership record conflicts with the device card type and modification is refused.");return;}
        NavSequence=0;NavLease=Now();NavBaselineAt=Now();NavUncertain=NO;[NavQueue reset];NSUInteger next=AfterBaseline;AfterBaseline=0;Change(@"Baseline received; navigation card can be enabled. Please open it manually in the glasses dashboard");if(next==1)TIONavEnableDisplay(YES);else if(next==2)TIONavEnableNotices(YES);else if(next==3)TIONavTestNotice();return;
    }
    if(seq!=NavSequence||[NavOperation isEqual:@"query"]||![j[@"code"] isKindOfClass:NSNumber.class]||CFGetTypeID((__bridge CFTypeRef)j[@"code"])==CFBooleanGetTypeID())return;
    BOOL ok=[j[@"code"] integerValue]==0;NSString *op=NavOperation;NavSequence=0;NavLease=Now();
    if([op isEqual:@"update"])[NavQueue acknowledge:ok];
    if(ok){if([op isEqual:@"remove"]){NavRemove=NO;Change(@"The glasses have been confirmed to uninstall the navigation card; lens confirmation is required, and other cards have not been modified.");}else Change(@"Navigation card update confirmed for glasses; lens visibility still needs to be confirmed");}
    else {NavEnabled=NO;NavRemove=NO;NavUncertain=YES;Change([NSString stringWithFormat:@"Glasses rejected (code=%ld); stop sending, please re-read the connection",(long)[j[@"code"] integerValue]]);}
}
void TIONavEnableDisplay(BOOL enabled){
    if(!enabled){AfterBaseline=0;NavEnabled=NO;NavRemove=NavOwner.length>0;[NavQueue offer:nil];TIONavPump();return;}
    if(NavUncertain||NavSequence||!NavBaselineAt||Now()-NavBaselineAt>120||Now()-NavLease>120){AutoBaseline(1);return;}
    TIONavEnableNotices(NO);
    if(!NavOwner){NavOwner=[@"turbo_ui_nav_" stringByAppendingString:[NSUUID.UUID.UUIDString.lowercaseString stringByReplacingOccurrencesOfString:@"-" withString:@""]];[NSUserDefaults.standardUserDefaults setObject:NavOwner forKey:OwnerKey()];}
    if(!NavQueue)NavQueue=[TIONavQueue new];[NavQueue reset];NavRemove=NO;NavEnabled=YES;Change(@"The card is enabled, waiting for the next navigation data");
}
void TIONavOfferDisplay(NSDictionary *display){if(NavEnabled)[NavQueue offer:display];if(NoticeEnabled)NoticeLatest=TIONavNoticeKey(display)?[display copy]:nil;}
void TIONavPump(void){
    PumpNotice();
    if(NavSequence){if(Now()<NavDeadline)return;NavSequence=0;NavEnabled=NO;NavUncertain=YES;[NavQueue acknowledge:NO];Change(@"No matching receipt for 12 seconds, the result is unknown; stop sending, please read the connection again. Old cards may still be in glasses");return;}
    if(NavUncertain)return;
    if(NavRemove){if(Send(TIOA2UIUninstall(NavOwner),@"remove"))Change(@"Uninstalling this navigation card");else {NavRemove=NO;Change(@"Unable to send for cleaning; navigation has stopped, the old card may still be in the glasses, please reconnect to the front desk before cleaning");}return;}
    if(!NavEnabled)return;
    if((!NavEnabled&&UIApplication.sharedApplication.applicationState!=UIApplicationStateActive)||Now()-NavLease>120){NavEnabled=NO;Change(@"Display update has been suspended: please keep the phone in the foreground and re-read the connection, do not rely on the old card");return;}
    NSDictionary *d=[NavQueue takeAt:Now()];if(d&&!Send(TIONavInstall(NavOwner,d),@"update")){[NavQueue acknowledge:NO];NavEnabled=NO;NavUncertain=YES;Change(@"Failed to send update; lens output paused, please re-read the connection");}
}
NSDictionary *TIONavTransportStatus(void){return @{@"note":NavNote?:@"",@"noticeNote":NoticeNote?:@"",@"notices":@(NoticeEnabled),@"noticePending":@(NoticeWaiting),@"noticeUID":NoticeUID?:@"",@"enabled":@(NavEnabled),@"pending":@(NavSequence!=0),@"uncertain":@(NavUncertain),@"hasOwner":@(NavOwner.length>0)};}
static BOOL NoticeReady(void){return NSThread.isMainThread&&NavPlugin&&NavRoute&&[TIOProtocolDevice() isEqual:NavDevice]&&NavBaselineAt&&!NavSequence&&!NavUncertain&&Now()-NavLease<120;}
static BOOL SendNotice(NSDictionary *frame){
    if(!NoticeReady()||NoticeWaiting||Now()<NoticeNext)return NO;
    Class typed=NSClassFromString(@"FlutterStandardTypedData"),call=NSClassFromString(@"FlutterMethodCall");SEL td=NSSelectorFromString(@"typedDataWithBytes:"),mk=NSSelectorFromString(@"methodCallWithMethodName:arguments:"),handle=NSSelectorFromString(@"handleMethodCall:result:");
    if(![typed respondsToSelector:td]||![call respondsToSelector:mk]||![NavPlugin respondsToSelector:handle])return NO;
    NSString *uid=[NSString stringWithFormat:@"%u",arc4random_uniform(INT32_MAX-1)+1];NSData *data=TIOA2UIPacket(2,0,TIONavNotice(uid,frame,NSDate.date));if(!data)return NO;
    NSMutableDictionary *args=[NavRoute mutableCopy];args[@"businessId"]=@21;args[@"payload"]=((id(*)(id,SEL,id))objc_msgSend)(typed,td,data);id c=((id(*)(id,SEL,id,id))objc_msgSend)(call,mk,@"rayneonet_sendMessage",args);
    NoticeUID=uid;NoticeWaiting=YES;NoticeDeadline=Now()+8;NoticeNext=Now()+35;NoticeKey=TIONavNoticeKey(frame);NavSending=YES;
    NoticeChange(@"Navigation notification submitted, waiting for same UID status (8 seconds); not lens display confirmation");
    @try{((void(*)(id,SEL,id,id))objc_msgSend)(NavPlugin,handle,c,[^(id result){
        BOOL error=[result isKindOfClass:NSDictionary.class]&&[result[@"success"] isEqual:@NO];
        error=error||[NSStringFromClass([result class]) containsString:@"FlutterError"];
        if(error)dispatch_async(dispatch_get_main_queue(),^{if(![NoticeUID isEqual:uid])return;NoticeWaiting=NO;NoticeEnabled=NO;NoticeLatest=nil;NoticeChange(@"SDK refuses to submit, automatic reminder has stopped; does not automatically retry");});
    } copy]);}
    @catch(NSException *e){NoticeWaiting=NO;NoticeEnabled=NO;NoticeLatest=nil;NoticeChange(@"The notification is sent abnormally and the result is unknown; it has been stopped and will not be automatically retried.");}
    NavSending=NO;return YES;
}
void TIONavEnableNotices(BOOL enabled){
    if(!enabled){AfterBaseline=0;NoticeEnabled=NO;NoticeWaiting=NO;NoticeLatest=nil;NoticeUID=nil;NoticeChange(@"Automatic notifications have been stopped; submitted notifications are closed according to the official duration and other notifications are not cleared");return;}
    if(!NoticeReady()){if(AutoBaseline(2))NoticeChange(@"Automatically read the connection baseline and enable notifications upon success");return;}
    if(NavEnabled){TIONavEnableDisplay(NO);NoticeChange(@"Requested to clear navigation card; wait until receipt is received before enabling notifications");return;}
    if(NoticeWaiting){NoticeChange(@"Previous post Still waiting for glasses status, please try again later");return;}
    NoticeEnabled=YES;NoticeKey=nil;NoticeLatest=nil;NoticeChange(@"Automatic reminder is turned on: turning/approaching intersection/abnormality/arrival, at least 35 seconds interval; do not change the official notification settings");
}
void TIONavTestNotice(void){
    if(!NoticeReady()){if(AutoBaseline(3))NoticeChange(@"Automatically read the connection baseline and send this test after success");return;}
    if(NoticeWaiting||Now()<NoticeNext){NoticeChange(@"The test was not sent: please wait for the end of the previous one, and the sending interval is at least 35 seconds.");return;}
    NSDictionary *d=TIONavDisplay(@"navigating",3,@"Notification channel test 7392",80,500,360,YES);
    if(!SendNotice(d))NoticeChange(@"Test not submitted: Current channel is unavailable");
}
static void PumpNotice(void){
    if(NoticeWaiting&&Now()>=NoticeDeadline){NoticeWaiting=NO;NoticeEnabled=NO;NoticeLatest=nil;NoticeUID=nil;NoticeChange(@"If the same UID is not sent back for 8 seconds, it will show unconfirmed; stop automatic reminder and will not automatically resend.");return;}
    if(!NoticeEnabled)return;
    if(!NoticeReady()){if(NavSequence)return;TIONavEnableNotices(NO);NoticeChange(@"The foreground/connection baseline has expired; stop automatic reminders, please read the connection again");return;}
    NSString *key=TIONavNoticeKey(NoticeLatest);if(key&&![key isEqual:NoticeKey]&&!NoticeWaiting&&Now()>=NoticeNext){if(!SendNotice(NoticeLatest)){TIONavEnableNotices(NO);NoticeChange(@"Currently unable to send, automatic reminder has been stopped");}}
}
