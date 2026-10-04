#import "ProtocolContext.h"
#import "ExperimentalOTAFlash.h"
#import "MusicTransport.h"
#import "ReaderTransport.h"
#import "FocusTransport.h"
#import "TDTransport.h"
#import "ExperimentalOTA.h"
#import "ExperimentalOTAGuard.h"
#include <TargetConditionals.h>
#include <math.h>
#if TIO_IMAGE_RX_LAB
#import "ImageUploadTransport.h"
#if TIO_DISPLAY_PHONE
#import "DisplayPhoneTransport.h"
#if TIO_NATIVE_NAV
#import "TNVTransport.h"
#endif
#if TARGET_OS_IPHONE && TIO_DISPLAY_FLASH
#import "DisplayPhoneUI.h"
#endif
#endif
#endif
BOOL TIOOTAFileCallBlocked(NSString *method,BOOL scopedImage,NSUInteger stage){
    if(![method isKindOfClass:NSString.class])return YES;
    if([method isEqual:@"rayneonet_sendFile"]&&scopedImage&&stage==0)return NO;
    NSString *lower=method.lowercaseString;
    return [lower containsString:@"sendfile"]||[lower containsString:@"ota"]||[lower containsString:@"upgrade"];
}
static id Error(NSError **error,NSString *s){if(error)*error=[NSError errorWithDomain:@"TurboIO.OTAFlash" code:1 userInfo:@{NSLocalizedDescriptionKey:s}];return nil;}
static BOOL Number(id n,NSUInteger *out){
    if(![n isKindOfClass:NSNumber.class]||CFGetTypeID((__bridge CFTypeRef)n)==CFBooleanGetTypeID()||CFNumberIsFloatType((__bridge CFNumberRef)n)||[n longLongValue]<0)return NO;
    uint64_t v=[n unsignedLongLongValue];if(v>UINT32_MAX)return NO;*out=(NSUInteger)v;return YES;
}
static BOOL Var(const uint8_t *b,NSUInteger n,NSUInteger *at,uint64_t *v){*v=0;for(unsigned i=0;i<5;i++){if(*at>=n)return NO;uint8_t x=b[(*at)++];if(i==4&&(x&0xf0))return NO;*v|=(uint64_t)(x&127)<<(i*7);if(!(x&128))return i==0||x!=0;}return NO;}
NSDictionary *TIOOTAFrame(NSData *data){
    if(![data isKindOfClass:NSData.class]||data.length<4||data.length>65536)return nil;
    const uint8_t *b=data.bytes;NSUInteger at=0;unsigned seen=0;uint64_t version=0,type=0;NSData *json=[NSData data],*binary=[NSData data];
    while(at<data.length){uint64_t key,v;if(!Var(b,data.length,&at,&key))return nil;unsigned tag=(unsigned)(key>>3),wire=key&7;
        if(tag<1||tag>6||(seen&(1u<<tag)))return nil;seen|=1u<<tag;
        if(tag==3||tag==4){if(wire!=2||!Var(b,data.length,&at,&v)||v>data.length-at)return nil;if(tag==3)json=[data subdataWithRange:NSMakeRange(at,(NSUInteger)v)];else binary=[data subdataWithRange:NSMakeRange(at,(NSUInteger)v)];at+=(NSUInteger)v;}
        else{if(wire!=0||!Var(b,data.length,&at,&v))return nil;if(tag==1)version=v;if(tag==2)type=v;if(tag==6&&v!=0)return nil;}
    }
    if(version!=1||!type)return nil;
    id obj=json.length?[NSJSONSerialization JSONObjectWithData:json options:0 error:nil]:@{};
    if(![obj isKindOfClass:NSDictionary.class]&&![obj isKindOfClass:NSArray.class])return nil;
    return @{@"type":@(type),@"json":obj,@"binary":binary};
}
BOOL TIOPhoneOTAReadAllowed(NSData *data){
    NSDictionary *frame=TIOOTAFrame(data);NSUInteger type=[frame[@"type"] unsignedIntegerValue];
    return [@[@1,@2,@11] containsObject:@(type)]&&[frame[@"json"] isEqual:@{}]&&[frame[@"binary"] length]==0;
}
@implementation TIOOTAFlashGate{
    NSDictionary<NSString *,NSData *> *_files;NSArray *_manifest;NSString *_device,*_failure;
    NSTimeInterval _deadline,_lastSliceAt;NSUInteger _stage,_slices,_bytes;BOOL _versionSent,_manifestSent;
}
- (BOOL)prepareDirectory:(NSURL *)directory device:(NSString *)device uptime:(NSTimeInterval)now error:(NSError **)error{
    @synchronized(self){
        if(_stage==2&&_lastSliceAt>0&&now-_lastSliceAt>25){_stage=0;_files=nil;_manifest=nil;_device=nil;_deadline=0;_lastSliceAt=0;_failure=nil;}
        if(_stage||![device isKindOfClass:NSString.class]||!device.length||device.length>200||!isfinite(now)||now<0){Error(error,@"It is not currently authorizable or does not have a valid device; it is not open.");return NO;}
        NSDictionary *files=TIOCopyExperimentalOTAPayloads(directory,error);if(!files)return NO;
        id manifest=[NSJSONSerialization JSONObjectWithData:files[@"OtaFileInfo.json"] options:0 error:error];if(![manifest isKindOfClass:NSArray.class]||[manifest count]!=14)return NO;
        _files=files;_manifest=manifest;_device=[device copy];_deadline=now+900;_lastSliceAt=now;_stage=1;_failure=nil;return YES;
    }
}
- (BOOL)allows:(NSData *)payload device:(NSString *)device uptime:(NSTimeInterval)now{
    @synchronized(self){
        NSDictionary *f=TIOOTAFrame(payload);NSUInteger t=[f[@"type"] unsignedIntegerValue];id j=f[@"json"];NSData *binary=f[@"binary"];
        BOOL dict=[j isKindOfClass:NSDictionary.class],empty=dict&&[j count]==0&&!binary.length;
        // 1 = OS version, 2 = battery. Idle is 11, NOT 2: official 1.0.5
        // failure recovery sent msgType=11 on 2026-09-21 at 17:38:03.477.
        // Allow its empty read even after a blocked start so the official
        // recovery loop can establish that no glasses transfer is active.
        if((t==1||t==2||t==11)&&empty){
            if(_stage==2&&_lastSliceAt>0&&now-_lastSliceAt>25){_stage=0;_files=nil;_manifest=nil;_device=nil;_deadline=0;_lastSliceAt=0;_failure=nil;}
            return YES;
        }
        NSUInteger n=0;
        if(t==3&&dict&&[j count]==1&&Number(j[@"OtaSize"],&n)&&(n==9300019||n==9300053||n==9300112)&&!binary.length)return YES;
        if(!_stage){if(t==4)_failure=@"TFP1 trial flash has not been authorized; the start command has not been sent. Please complete the TFP1 risk confirmation on the experimental firmware page first.";return NO;}
        if(_stage==3||!isfinite(now)||now<0)return NO;
        if(_stage==1&&now>=_deadline){[self cancel];return NO;}
        BOOL ok=(!device.length && _device.length) || [device caseInsensitiveCompare:_device] == NSOrderedSame;
        if(t==4)ok=ok&&_stage==1&&dict&&[j count]==1&&Number(j[@"Mode"],&n)&&n==2&&!binary.length;
        else if(t==5)ok=ok&&_stage==2&&dict&&[j isEqual:@{@"OtaVersion":@"Strix OS 1.0.4.12"}]&&!binary.length;
        else if(t==6)ok=ok&&_stage==2&&_versionSent&&[j isKindOfClass:NSArray.class]&&[j isEqual:_manifest]&&!binary.length;
        else if(t==7){
            NSUInteger start=0,size=0;NSString *name=dict?j[@"Name"]:nil;NSData *file=[name isKindOfClass:NSString.class]?_files[name]:nil;
            ok=ok&&_stage==2&&_manifestSent&&dict&&[j count]==3&&file&&![name isEqual:@"OtaFileInfo.json"]&&Number(j[@"Start"],&start)&&Number(j[@"Size"],&size)&&size>0&&size<=51200&&start<file.length&&size<=file.length-start&&binary.length==size;
            if(ok)ok=memcmp(binary.bytes,(const uint8_t *)file.bytes+start,size)==0;
            if(ok){_slices++;_bytes+=size;_lastSliceAt=now;}
        }else ok=NO;
        if(!ok){_failure=@"Unexpected device, session, manifest or shard, send refused";if(_stage==2)_stage=3;return NO;}
        if(t==4){_stage=2;_lastSliceAt=now;}if(t==5)_versionSent=YES;if(t==6)_manifestSent=YES;return YES;
    }
}
- (BOOL)cancel{@synchronized(self){if(_stage==2&&_lastSliceAt>0&&NSProcessInfo.processInfo.systemUptime-_lastSliceAt<=25)return NO;_stage=0;_files=nil;_manifest=nil;_device=nil;_deadline=0;_lastSliceAt=0;_failure=nil;return YES;}}
- (NSDictionary *)status{@synchronized(self){if(_stage==2&&_lastSliceAt>0&&NSProcessInfo.processInfo.systemUptime-_lastSliceAt>25){_stage=0;_files=nil;_manifest=nil;_device=nil;_deadline=0;_lastSliceAt=0;_failure=nil;}return @{@"stage":@(_stage),@"authorized":@(_stage==1||_stage==2),@"started":@(_stage>=2),@"versionMatched":@(_versionSent),@"manifestMatched":@(_manifestSent),@"validatedSlices":@(_slices),@"validatedSliceBytes":@(_bytes),@"failure":_failure?:@"",@"runtimeValidated":@NO};}}
@end
BOOL TIOOTAFlashBuild(void){
#if TARGET_OS_IPHONE && TIO_OTA_FLASH_ENABLED
#if TIO_DISPLAY_FLASH
    // Compiled experimental builds must stay gated even if Info.plist is stale.
    // Authorization/feed still require the exact marker below.
    return YES;
#else
    return [[NSBundle.mainBundle objectForInfoDictionaryKey:@"TIOExperimentalOTAQueryRouting"] isEqual:@"ios105-tfp1-loopback-flash-gated"];
#endif
#else
    return NO;
#endif
}
static TIOOTAFlashGate *Gate;static NSString *ObservedDevice;static NSTimeInterval ObservedAt;
BOOL TIOOTAAutoUpdateDisabled(NSDictionary *preferences){
    if(![preferences isKindOfClass:NSDictionary.class])return NO;
    NSUInteger found=0;
    for(id key in preferences){if(![key isKindOfClass:NSString.class]||![key hasSuffix:@"_ota_firmware_auto_update"])continue;found++;
        id v=preferences[key];if([v isKindOfClass:NSString.class]){if(![v isEqual:@"false"])return NO;}
        else if(![v isKindOfClass:NSNumber.class]||CFGetTypeID((__bridge CFTypeRef)v)!=CFBooleanGetTypeID()||[v boolValue])return NO;
    }
    return found>0;
}
static TIOOTAFlashGate *Current(void){@synchronized(NSProcessInfo.processInfo){if(!Gate)Gate=[TIOOTAFlashGate new];return Gate;}}
BOOL TIOOTAFlashProtected(void){
#if TARGET_OS_IPHONE && TIO_DISPLAY_FLASH
    if(![[NSBundle.mainBundle objectForInfoDictionaryKey:@"TIOExperimentalOTAQueryRouting"] isEqual:@"ios105-tfp1-loopback-flash-gated"])return NO;
#endif
    return TIOOTAFlashBuild()&&[TIOOTAGuardStatus()[@"transportHookReady"] boolValue];
}
void TIOOTAFlashDisableAutoUpdateIfRequested(void){
    if(!TIOOTAFlashProtected()||![NSProcessInfo.processInfo.environment[@"TIO_OTA_DISABLE_AUTO_ONCE"] isEqual:@"DISABLE_FOR_PRIVATE_TFP1"])return;
    NSUserDefaults *p=NSUserDefaults.standardUserDefaults;NSMutableArray *keys=[NSMutableArray new];
    for(NSString *key in p.dictionaryRepresentation)if([key hasSuffix:@"_ota_firmware_auto_update"])[keys addObject:key];
    // Do not guess between accounts. The private pre-install preference backup
    // preserves the old value; no account identifiers are written to reports.
    if(keys.count!=1)return;id v=[p objectForKey:keys[0]];
    if([v isKindOfClass:NSString.class]&&([v isEqual:@"true"]||[v isEqual:@"false"]))[p setObject:@"false" forKey:keys[0]];
    else if([v isKindOfClass:NSNumber.class]&&CFGetTypeID((__bridge CFTypeRef)v)==CFBooleanGetTypeID())[p setBool:NO forKey:keys[0]];
    [p synchronize];
}
static id Get(id obj,NSString *key){@try{return [obj valueForKey:key];}@catch(NSException *e){return nil;}}
BOOL TIOOTAFlashBlockCall(id call){
    if(!TIOOTAFlashBuild())return NO;
    NSString *method=Get(call,@"method");NSDictionary *args=Get(call,@"arguments");
    if(![method isKindOfClass:NSString.class])return YES;
    if([method.lowercaseString containsString:@"disconnect"]||[method.lowercaseString containsString:@"unbind"]||[method.lowercaseString containsString:@"unpair"]){@synchronized(NSProcessInfo.processInfo){ObservedDevice=nil;ObservedAt=0;}[Current() cancel];}
    if([method isEqual:@"rayneonet_sendMessage"]){
        NSUInteger business=0;if(![args isKindOfClass:NSDictionary.class]||!Number(args[@"businessId"],&business))return YES;
        if(business!=9)return NO;
        id data=args[@"payload"];if(![data isKindOfClass:NSData.class])data=Get(data,@"data");
#if TIO_DISPLAY_PHONE && !TIO_DISPLAY_FLASH
        // Phone-only test package: no OTA mutation, even if an old gate was armed.
        return !TIOPhoneOTAReadAllowed(data);
#endif
        return ![Current() allows:data device:args[@"deviceId"] uptime:NSProcessInfo.processInfo.systemUptime];
    }
    // The pinned files path uses business 9 frames, never sendFile / ZIP mode.
    BOOL scopedImage=NO;
#if TIO_IMAGE_RX_LAB
    scopedImage=TIOImageUploadIsScopedCall(method,args);
#if TIO_DISPLAY_PHONE
    scopedImage=scopedImage||TDPPhoneIsScopedCall(method,args);
#if TIO_NATIVE_NAV
    scopedImage=scopedImage||TNVIsScopedCall(method,args)||TMIsScopedCall(method,args)||TWIsScopedCall(method,args)||TFIsScopedCall(method,args)||TDIsScopedCall(method,args);
#endif
#endif
#endif
    return TIOOTAFileCallBlocked(method,scopedImage,[[Current() status][@"stage"] unsignedIntegerValue]);
}
void TIOOTAFlashObserveEvent(NSDictionary *event){
    if(!TIOOTAFlashBuild()||![event[@"eventType"] isEqual:@"messageReceived"])return;
    NSDictionary *m=event[@"message"];NSUInteger business=0;if(![m isKindOfClass:NSDictionary.class]||!Number(m[@"businessId"],&business)||business!=9)return;
    NSDictionary *f=TIOOTAFrame(m[@"payload"]);id j=f[@"json"];
    if([f[@"type"] isEqual:@1]&&[j isKindOfClass:NSDictionary.class]&&[m[@"deviceId"] isKindOfClass:NSString.class]){
        @synchronized(NSProcessInfo.processInfo){ObservedDevice=[m[@"deviceId"] copy];ObservedAt=NSProcessInfo.processInfo.systemUptime;}
    }
}
BOOL TIOOTAFlashAuthorize(NSError **error){
    if(!TIOOTAFlashProtected()){Error(error,@"There is no test flash build and delivery protection; not open.");return NO;}
#if TARGET_OS_IPHONE && TIO_DISPLAY_FLASH
    if(!TDPPhonePauseForOTA()){Error(error,@"It shows that the file is still being transferred or the result is unknown, please wait for the final status; upgrade is not open. If the task cannot be completed, exit the display page and restart the app to check again.");return NO;}
#endif
    // Auto-disable auto update preference if present
    NSUserDefaults *p = NSUserDefaults.standardUserDefaults;
    for(NSString *k in p.dictionaryRepresentation) {
        if([k hasSuffix:@"_ota_firmware_auto_update"]) [p setBool:NO forKey:k];
    }
    [p setBool:NO forKey:@"venus_ota_firmware_auto_update"];

    NSString *device;NSTimeInterval at;@synchronized(NSProcessInfo.processInfo){device=ObservedDevice;at=ObservedAt;}
    if(!device.length) device = TIOProtocolDevice();
    NSTimeInterval now=NSProcessInfo.processInfo.systemUptime;
    if(!device.length){Error(error,@"Glasses not connected via Bluetooth. Please connect glasses first.");return NO;}
    NSURL *dir=[NSURL fileURLWithPath:[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/ota/Strix_OS_1.0.4.12"] isDirectory:YES];
    if(![NSFileManager.defaultManager fileExistsAtPath:dir.path]){
        Error(error,@"Firmware files not downloaded yet!\n\nPlease tap 'Enable 15-min Download-Only Mode' first, then open the official RayNeo screen to allow the app to download the local package.");
        return NO;
    }
    return [Current() prepareDirectory:dir device:device uptime:now error:error];
}
BOOL TIOOTAFlashCancel(void){return [Current() cancel];}
NSDictionary *TIOOTAFlashStatus(void){NSMutableDictionary *s=[[Current() status] mutableCopy];s[@"flashBuild"]=@(TIOOTAFlashBuild());s[@"automaticUpdateDisabled"]=@(TIOOTAAutoUpdateDisabled(NSUserDefaults.standardUserDefaults.dictionaryRepresentation));@synchronized(NSProcessInfo.processInfo){s[@"recentTargetVersionRead"]=@(ObservedDevice.length&&NSProcessInfo.processInfo.systemUptime-ObservedAt<=120);}return s;}
