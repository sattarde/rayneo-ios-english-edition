#import "DisplayPhoneUI.h"
#import "SpotifyAPI.h"
#import "MusicPlayer.h"
#import "ReaderUI.h"
#import "FocusBridge.h"
#import "ReaderBridge.h"
#import "MusicBridge.h"
#import "TDPhoneBridge.h"
#import "TDPhoneReply.h"
#import "DisplayPhoneSession.h"
#import "DisplayPhoneTransport.h"
#import "DisplayDiagnostics.h"
#import "DisplayNavigation.h"
#import "DisplayHUDRenderer.h"
#import "NativeNavigationUI.h"
#import "NativeNavigation.h"
#import "ExperimentalOTAFlash.h"
#import "display_carrier.h"
#import "ProtocolContext.h"
#import "ImageUploadUI.h"
#import <objc/message.h>
#import <ImageIO/ImageIO.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <AVFAudio/AVFAudio.h>
#import <CoreLocation/CoreLocation.h>

static AVAudioPlayer *NavAudioKeepalive = nil;
static CLLocationManager *NavLocationKeepalive = nil;
static BOOL NavHUDActive;
static BOOL MusicHUDActive;

static void StartBackgroundKeepalive(void){
 @try {
  if(!NavAudioKeepalive || !NavAudioKeepalive.isPlaying){
   AVAudioSession *session = [AVAudioSession sharedInstance];
   NSError *err = nil;
   [session setCategory:AVAudioSessionCategoryPlayback
            withOptions:AVAudioSessionCategoryOptionMixWithOthers
                  error:&err];
   [session setActive:YES error:&err];
   
   static BOOL interruptionObserved = NO;
   if(!interruptionObserved){
    interruptionObserved = YES;
    [NSNotificationCenter.defaultCenter addObserverForName:AVAudioSessionInterruptionNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){
     NSNumber *type = n.userInfo[AVAudioSessionInterruptionTypeKey];
     if([type unsignedIntegerValue] == AVAudioSessionInterruptionTypeEnded){
      @try {
       [[AVAudioSession sharedInstance] setActive:YES error:nil];
       [NavAudioKeepalive play];
      } @catch(NSException *e){}
     }
    }];
   }
   
   NSMutableData *data = [NSMutableData dataWithCapacity:8044];
   const uint32_t sampleRate = 8000;
   const uint32_t numSamples = 8000;
   const uint32_t dataSize = numSamples;
   const uint32_t fileSize = 36 + dataSize;
   
   [data appendBytes:"RIFF" length:4];
   [data appendBytes:&fileSize length:4];
   [data appendBytes:"WAVEfmt " length:8];
   uint32_t subchunk1Size = 16;
   uint16_t audioFormat = 1;
   uint16_t numChannels = 1;
   uint32_t byteRate = sampleRate;
   uint16_t blockAlign = 1;
   uint16_t bitsPerSample = 8;
   [data appendBytes:&subchunk1Size length:4];
   [data appendBytes:&audioFormat length:2];
   [data appendBytes:&numChannels length:2];
   [data appendBytes:&sampleRate length:4];
   [data appendBytes:&byteRate length:4];
   [data appendBytes:&blockAlign length:2];
   [data appendBytes:&bitsPerSample length:2];
   [data appendBytes:"data" length:4];
   [data appendBytes:&dataSize length:4];
   uint8_t silence[8000];
   memset(silence, 128, sizeof(silence));
   [data appendBytes:silence length:sizeof(silence)];
   
   NavAudioKeepalive = [[AVAudioPlayer alloc] initWithData:data error:&err];
   NavAudioKeepalive.numberOfLoops = -1;
   NavAudioKeepalive.volume = 0.01;
   [NavAudioKeepalive play];
  }
 } @catch (NSException *e) {}
 
 @try {
  if(!NavLocationKeepalive){
   NavLocationKeepalive = [CLLocationManager new];
   NavLocationKeepalive.desiredAccuracy = kCLLocationAccuracyBestForNavigation;
   NavLocationKeepalive.distanceFilter = kCLDistanceFilterNone;
   NavLocationKeepalive.activityType = CLActivityTypeAutomotiveNavigation;
   NavLocationKeepalive.pausesLocationUpdatesAutomatically = NO;
   if([NavLocationKeepalive respondsToSelector:@selector(setAllowsBackgroundLocationUpdates:)]){
    NavLocationKeepalive.allowsBackgroundLocationUpdates = YES;
   }
   if(@available(iOS 11.0, *)){
    NavLocationKeepalive.showsBackgroundLocationIndicator = YES;
   }
  }
  [NavLocationKeepalive startUpdatingLocation];
 } @catch(NSException *e){}
}

void TDPPhoneStartKeepalive(void){
 StartBackgroundKeepalive();
}

static void StopBackgroundKeepalive(void){
 if(NavHUDActive || MusicHUDActive) return;
 if(NavAudioKeepalive){
  [NavAudioKeepalive stop];
  NavAudioKeepalive = nil;
  @try {
   [[AVAudioSession sharedInstance] setActive:NO
                                 withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation
                                       error:nil];
  } @catch (NSException *e) {}
 }
 if(NavLocationKeepalive){
  @try {
   [NavLocationKeepalive stopUpdatingLocation];
  } @catch(NSException *e){}
 }
}

static TDPPhoneSession *Session;
static TDPPhoneTransport *Transport;
static TDPNavFeed *NavFeed;
BOOL TDPPhonePauseForOTA(void){
 if(!NSThread.isMainThread||!TFFocusIdleForOTA()||Session.busy||NavFeed.active||!TNVPauseForOTA()||!TDDiagnosticsPauseForOTA()||!TMMusicPauseForOTA()||!TWReaderPauseForOTA())return NO;
 [Session setForegroundActive:NO];return YES;
}
static NSString *Peer;
static BOOL PeerInvalidated;
static void CheckPeer(void){if(!PeerInvalidated&&Peer&&![TIOProtocolDevice() isEqual:Peer]){PeerInvalidated=YES;[Session disconnect];}}
BOOL TDPPhoneConsumeEvent(NSDictionary *e){
 NSCAssert(NSThread.isMainThread,@"main only");
 CheckPeer();
 if(TDDiagnosticsConsume(e))return YES;
 if(TFFocusConsume(e))return YES;
 if(TWReaderConsume(e))return YES;
 if(TMMusicConsume(e))return YES;
 if(TNVConsume(e))return YES;
 return [Session consumeEvent:e];
}
BOOL TDPPhoneRouteReply(NSDictionary *event,void(^completion)(BOOL)){
 if(![event isKindOfClass:NSDictionary.class]||![event[@"eventType"] isEqual:@"messageReceived"])return NO;
 NSDictionary *m=event[@"message"];if(![m isKindOfClass:NSDictionary.class]||![m[@"businessId"] isEqual:@15]||![m[@"payload"] isKindOfClass:NSData.class])return NO;
 NSData *data=m[@"payload"];TDPReply r;if(!TFDecodeReply(event)&&!TDPhoneReply(event)&&!TWDecodeReply(event,NULL)&&!TMMusicReply(event,NULL)&&!TNVDecodeReply(event,NULL)&&!tdp_carrier_decode(15,data.bytes,data.length,&r))return NO;
 NSDictionary *snapshot=[event copy];void(^work)(void)=^{completion(TDPPhoneConsumeEvent(snapshot));};
 if(NSThread.isMainThread)work();else dispatch_async(dispatch_get_main_queue(),work);return YES;
}
static BOOL Setup(void){
 if(!TNVPauseForOTA()||!TDDiagnosticsPauseForOTA()||!TMMusicPauseForOTA()||!TWReaderPauseForOTA())return NO;
 NSString *device=TIOProtocolDevice();if(!device.length)return NO;
 if(Session&&[Peer isEqual:device]){PeerInvalidated=NO;return YES;}
 if(Session.busy)return NO; // Never discard uncertain native-file ownership.
 Peer=[device copy];PeerInvalidated=NO;NSString *pinned=Peer;
 // Separate bounded experiment spool. Preserve prior builds' uncertain files.
 NSURL *root=[NSURL fileURLWithPath:[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/TurboIOPrivateAddon/DisplayTDP1-PHONE06"] isDirectory:YES];
 Transport=[[TDPPhoneTransport alloc]initWithRoot:root device:pinned currentDevice:^{return TIOProtocolDevice();} call:^BOOL(NSString *method,NSDictionary *args,void(^result)(id)){
  if(!NSThread.isMainThread||![TIOProtocolDevice() isEqual:pinned])return NO;
  id plugin=TIOProtocolPlugin();Class cls=NSClassFromString(@"FlutterMethodCall");SEL make=NSSelectorFromString(@"methodCallWithMethodName:arguments:"),handle=NSSelectorFromString(@"handleMethodCall:result:");
  if(!plugin||![cls respondsToSelector:make]||![plugin respondsToSelector:handle])return NO;
  @try{id call=((id(*)(id,SEL,id,id))objc_msgSend)(cls,make,method,args);((void(*)(id,SEL,id,id))objc_msgSend)(plugin,handle,call,[result copy]);return YES;}@catch(NSException *e){return NO;}
 }];
 TDPPhoneTransport *carrier=Transport;
 Session=[[TDPPhoneSession alloc]initWithDevice:pinned clock:^{return NSProcessInfo.processInfo.systemUptime;} sender:^(NSData *p,NSString *task,TDPSubmitted done){[carrier send:p task:task submitted:done];}];return Session!=nil;
}
static UIImage *NavigationImage(BOOL left,unsigned meters){
 UIGraphicsImageRendererFormat *f=[UIGraphicsImageRendererFormat defaultFormat];f.scale=1;f.opaque=YES;
 return [[[UIGraphicsImageRenderer alloc]initWithSize:CGSizeMake(512,128) format:f] imageWithActions:^(UIGraphicsImageRendererContext *r){
  [UIColor.blackColor setFill];UIRectFill(CGRectMake(0,0,512,128));[UIColor.whiteColor setStroke];
  UIBezierPath *arrow=[UIBezierPath bezierPath];[arrow moveToPoint:CGPointMake(45,100)];[arrow addLineToPoint:CGPointMake(45,46)];[arrow addLineToPoint:CGPointMake(left?14:82,46)];[arrow moveToPoint:CGPointMake(left?30:66,30)];[arrow addLineToPoint:CGPointMake(left?14:82,46)];[arrow addLineToPoint:CGPointMake(left?30:66,62)];arrow.lineWidth=7;arrow.lineJoinStyle=kCGLineJoinRound;[arrow stroke];
  [[NSString stringWithFormat:@"%u meters",meters] drawAtPoint:CGPointMake(102,5) withAttributes:@{NSFontAttributeName:[UIFont boldSystemFontOfSize:42],NSForegroundColorAttributeName:UIColor.whiteColor}];
  [(left?@"Turn Left · Test Street":@"Turn Right · Test Street") drawAtPoint:CGPointMake(103,59) withAttributes:@{NSFontAttributeName:[UIFont systemFontOfSize:23 weight:UIFontWeightMedium],NSForegroundColorAttributeName:UIColor.whiteColor}];
  [@"TURBO IO · Local Layout Sample 7392" drawAtPoint:CGPointMake(103,100) withAttributes:@{NSFontAttributeName:[UIFont systemFontOfSize:13],NSForegroundColorAttributeName:UIColor.lightGrayColor}];
  [[UIColor colorWithWhite:0.3 alpha:1] setStroke];UIBezierPath *map=[UIBezierPath bezierPathWithRoundedRect:CGRectMake(396,8,108,112) cornerRadius:8];map.lineWidth=2;[map stroke];
  UIBezierPath *streets=[UIBezierPath bezierPath];for(int i=0;i<3;i++){[streets moveToPoint:CGPointMake(404,30+i*30)];[streets addLineToPoint:CGPointMake(496,30+i*30)];[streets moveToPoint:CGPointMake(414+i*32,16)];[streets addLineToPoint:CGPointMake(414+i*32,111)];}streets.lineWidth=1;[streets stroke];
  [UIColor.whiteColor setStroke];UIBezierPath *route=[UIBezierPath bezierPath];[route moveToPoint:CGPointMake(445,106)];[route addLineToPoint:CGPointMake(445,60)];[route addLineToPoint:CGPointMake(left?407:491,60)];route.lineWidth=4;[route stroke];
 }];
}
static NSData *Gray(UIImage *image){
 if(!image.CGImage)return nil;NSMutableData *p=[NSMutableData dataWithLength:TDP_PIXELS];CGColorSpaceRef cs=CGColorSpaceCreateDeviceGray();
 CGContextRef ctx=CGBitmapContextCreate(p.mutableBytes,512,128,8,512,cs,kCGImageAlphaNone);CGColorSpaceRelease(cs);if(!ctx)return nil;
 CGContextDrawImage(ctx,CGRectMake(0,0,512,128),image.CGImage);CGContextRelease(ctx);return p;
}
static UIImage *GrayPreview(NSData *data){
 if(data.length!=TDP_PIXELS)return nil;CGColorSpaceRef color=CGColorSpaceCreateDeviceGray();CGDataProviderRef provider=CGDataProviderCreateWithCFData((__bridge CFDataRef)data);
 CGImageRef im=CGImageCreate(512,128,8,8,512,color,kCGImageAlphaNone,provider,NULL,false,kCGRenderingIntentDefault);UIImage *image=im?[UIImage imageWithCGImage:im]:nil;
 if(im)CGImageRelease(im);CGDataProviderRelease(provider);CGColorSpaceRelease(color);return image;
}
static void SaveNavStatus(void){
 if(!NavFeed)return;NSMutableDictionary *d=[NavFeed.status mutableCopy];d[@"build"]=@"NAVIGATION-PHONE-01";d[@"timestamp"]=@(NSDate.date.timeIntervalSince1970);
 NSString *path=[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/TurboIOPrivateAddon/display-navigation-status.json"];
 [[NSJSONSerialization dataWithJSONObject:d options:NSJSONWritingSortedKeys error:nil] writeToFile:path options:NSDataWritingAtomic error:nil];[NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:path error:nil];
}

// ─── TDP1 Live Navigation HUD ─────────────────────────────────────────────
// Bypasses broken TNV1 entirely. Renders 512×128 wireframe images from MapKit
// navigation telemetry and streams them to glasses via TDP1 (Item 7 / 显示测试).
static BOOL NavHUDInitialSent;
static NSDictionary *NavHUDLatest;  // Latest navigation frame offered
static NSData *NavHUDLastPixels;    // Last sent pixels for delta comparison
static NSUInteger NavHUDCount;      // Frames successfully sent
static NSString *NavHUDNote;
static NSTimer *NavHUDTimer;
static dispatch_source_t NavHUDDispatchTimer;
static NSTimeInterval NavHUDStartTime;
static NSTimeInterval NavHUDLastDeltaTime;
static UIBackgroundTaskIdentifier NavHUDBackgroundTask = 0;

static void EndNavHUDBackgroundTask(void){
 if(NavHUDBackgroundTask != UIBackgroundTaskInvalid){
  UIBackgroundTaskIdentifier t = NavHUDBackgroundTask;
  NavHUDBackgroundTask = UIBackgroundTaskInvalid;
  [UIApplication.sharedApplication endBackgroundTask:t];
 }
}

static void AssertNavHUDBackgroundTask(void){
 if(!NavHUDActive) return;
 if(NavHUDBackgroundTask == UIBackgroundTaskInvalid){
  NavHUDBackgroundTask = [UIApplication.sharedApplication beginBackgroundTaskWithName:@"io.turboio.navhud" expirationHandler:^{
   EndNavHUDBackgroundTask();
   if(NavHUDActive){
    AssertNavHUDBackgroundTask();
   }
  }];
 }
}

// Draw a turn arrow icon into the given rect based on the icon code
static void DrawTurnArrow(NSInteger icon,CGRect rect){
 [UIColor.whiteColor setStroke];[UIColor.whiteColor setFill];
 UIBezierPath *arrow=[UIBezierPath bezierPath];
 CGFloat cx=CGRectGetMidX(rect),cy=CGRectGetMidY(rect),w=rect.size.width,h=rect.size.height;
 CGFloat top=rect.origin.y+h*0.1,bot=rect.origin.y+h*0.85,mid=cy;
 CGFloat left=rect.origin.x+w*0.15,right=rect.origin.x+w*0.85;
 switch(icon){
  case 2: // Left
   [arrow moveToPoint:CGPointMake(cx,bot)];[arrow addLineToPoint:CGPointMake(cx,mid)];
   [arrow addLineToPoint:CGPointMake(left,mid)];
   arrow.lineWidth=6;arrow.lineJoinStyle=kCGLineJoinRound;arrow.lineCapStyle=kCGLineCapRound;[arrow stroke];
   {UIBezierPath *head=[UIBezierPath bezierPath];[head moveToPoint:CGPointMake(left+w*0.18,mid-h*0.15)];[head addLineToPoint:CGPointMake(left,mid)];[head addLineToPoint:CGPointMake(left+w*0.18,mid+h*0.15)];head.lineWidth=6;head.lineJoinStyle=kCGLineJoinRound;head.lineCapStyle=kCGLineCapRound;[head stroke];}
   break;
  case 3: // Right
   [arrow moveToPoint:CGPointMake(cx,bot)];[arrow addLineToPoint:CGPointMake(cx,mid)];
   [arrow addLineToPoint:CGPointMake(right,mid)];
   arrow.lineWidth=6;arrow.lineJoinStyle=kCGLineJoinRound;arrow.lineCapStyle=kCGLineCapRound;[arrow stroke];
   {UIBezierPath *head=[UIBezierPath bezierPath];[head moveToPoint:CGPointMake(right-w*0.18,mid-h*0.15)];[head addLineToPoint:CGPointMake(right,mid)];[head addLineToPoint:CGPointMake(right-w*0.18,mid+h*0.15)];head.lineWidth=6;head.lineJoinStyle=kCGLineJoinRound;head.lineCapStyle=kCGLineCapRound;[head stroke];}
   break;
  case 4: // Slight left
   [arrow moveToPoint:CGPointMake(cx,bot)];[arrow addLineToPoint:CGPointMake(cx,mid)];
   [arrow addLineToPoint:CGPointMake(left+w*0.08,top+h*0.1)];
   arrow.lineWidth=6;arrow.lineJoinStyle=kCGLineJoinRound;arrow.lineCapStyle=kCGLineCapRound;[arrow stroke];
   {UIBezierPath *head=[UIBezierPath bezierPath];CGFloat tx=left+w*0.08,ty=top+h*0.1;[head moveToPoint:CGPointMake(tx+w*0.12,ty)];[head addLineToPoint:CGPointMake(tx,ty)];[head addLineToPoint:CGPointMake(tx,ty+h*0.18)];head.lineWidth=6;head.lineJoinStyle=kCGLineJoinRound;head.lineCapStyle=kCGLineCapRound;[head stroke];}
   break;
  case 5: // Slight right
   [arrow moveToPoint:CGPointMake(cx,bot)];[arrow addLineToPoint:CGPointMake(cx,mid)];
   [arrow addLineToPoint:CGPointMake(right-w*0.08,top+h*0.1)];
   arrow.lineWidth=6;arrow.lineJoinStyle=kCGLineJoinRound;arrow.lineCapStyle=kCGLineCapRound;[arrow stroke];
   {UIBezierPath *head=[UIBezierPath bezierPath];CGFloat tx=right-w*0.08,ty=top+h*0.1;[head moveToPoint:CGPointMake(tx-w*0.12,ty)];[head addLineToPoint:CGPointMake(tx,ty)];[head addLineToPoint:CGPointMake(tx,ty+h*0.18)];head.lineWidth=6;head.lineJoinStyle=kCGLineJoinRound;head.lineCapStyle=kCGLineCapRound;[head stroke];}
   break;
  case 6: // Sharp left
   [arrow moveToPoint:CGPointMake(cx,bot)];[arrow addLineToPoint:CGPointMake(cx,mid)];
   [arrow addLineToPoint:CGPointMake(left,bot)];
   arrow.lineWidth=6;arrow.lineJoinStyle=kCGLineJoinRound;arrow.lineCapStyle=kCGLineCapRound;[arrow stroke];
   {UIBezierPath *head=[UIBezierPath bezierPath];[head moveToPoint:CGPointMake(left+w*0.16,bot-h*0.15)];[head addLineToPoint:CGPointMake(left,bot)];[head addLineToPoint:CGPointMake(left+w*0.22,bot+h*0.02)];head.lineWidth=6;head.lineJoinStyle=kCGLineJoinRound;head.lineCapStyle=kCGLineCapRound;[head stroke];}
   break;
  case 7: // Sharp right
   [arrow moveToPoint:CGPointMake(cx,bot)];[arrow addLineToPoint:CGPointMake(cx,mid)];
   [arrow addLineToPoint:CGPointMake(right,bot)];
   arrow.lineWidth=6;arrow.lineJoinStyle=kCGLineJoinRound;arrow.lineCapStyle=kCGLineCapRound;[arrow stroke];
   {UIBezierPath *head=[UIBezierPath bezierPath];[head moveToPoint:CGPointMake(right-w*0.16,bot-h*0.15)];[head addLineToPoint:CGPointMake(right,bot)];[head addLineToPoint:CGPointMake(right-w*0.22,bot+h*0.02)];head.lineWidth=6;head.lineJoinStyle=kCGLineJoinRound;head.lineCapStyle=kCGLineCapRound;[head stroke];}
   break;
  case 8:case 19: // U-turn
   [arrow moveToPoint:CGPointMake(cx+w*0.1,bot)];[arrow addLineToPoint:CGPointMake(cx+w*0.1,top+h*0.2)];
   [arrow addCurveToPoint:CGPointMake(cx-w*0.1,top+h*0.2) controlPoint1:CGPointMake(cx+w*0.1,top) controlPoint2:CGPointMake(cx-w*0.1,top)];
   [arrow addLineToPoint:CGPointMake(cx-w*0.1,mid)];
   arrow.lineWidth=6;arrow.lineJoinStyle=kCGLineJoinRound;arrow.lineCapStyle=kCGLineCapRound;[arrow stroke];
   {UIBezierPath *head=[UIBezierPath bezierPath];CGFloat bx=cx-w*0.1;[head moveToPoint:CGPointMake(bx-w*0.1,mid-h*0.12)];[head addLineToPoint:CGPointMake(bx,mid)];[head addLineToPoint:CGPointMake(bx+w*0.1,mid-h*0.12)];head.lineWidth=6;head.lineJoinStyle=kCGLineJoinRound;head.lineCapStyle=kCGLineCapRound;[head stroke];}
   break;
  case 11:case 12:case 17:case 18: // Roundabout
   {UIBezierPath *circ=[UIBezierPath bezierPathWithOvalInRect:CGRectMake(cx-w*0.2,cy-w*0.2,w*0.4,w*0.4)];circ.lineWidth=5;[circ stroke];}
   [arrow moveToPoint:CGPointMake(cx,cy+w*0.2)];[arrow addLineToPoint:CGPointMake(cx,bot)];
   arrow.lineWidth=6;arrow.lineCapStyle=kCGLineCapRound;[arrow stroke];
   break;
  case 15: // Arrive / destination
   {UIBezierPath *flag=[UIBezierPath bezierPath];[flag moveToPoint:CGPointMake(cx,bot)];[flag addLineToPoint:CGPointMake(cx,top)];flag.lineWidth=5;flag.lineCapStyle=kCGLineCapRound;[flag stroke];}
   {UIBezierPath *pennant=[UIBezierPath bezierPath];[pennant moveToPoint:CGPointMake(cx,top)];[pennant addLineToPoint:CGPointMake(cx+w*0.3,top+h*0.15)];[pennant addLineToPoint:CGPointMake(cx,top+h*0.3)];[pennant closePath];[pennant fill];}
   break;
  default: // Straight / unknown → up arrow
   [arrow moveToPoint:CGPointMake(cx,bot)];[arrow addLineToPoint:CGPointMake(cx,top)];
   arrow.lineWidth=6;arrow.lineCapStyle=kCGLineCapRound;[arrow stroke];
   {UIBezierPath *head=[UIBezierPath bezierPath];[head moveToPoint:CGPointMake(cx-w*0.2,top+h*0.18)];[head addLineToPoint:CGPointMake(cx,top)];[head addLineToPoint:CGPointMake(cx+w*0.2,top+h*0.18)];head.lineWidth=6;head.lineJoinStyle=kCGLineJoinRound;head.lineCapStyle=kCGLineCapRound;[head stroke];}
 }
}

// Render a 512×128 wireframe navigation image from a live navigation frame dictionary
UIImage *TDPPhoneNavigationRender(NSDictionary *frame);
static inline UIImage *DynamicNavigationImage(NSDictionary *frame){ return TDPPhoneNavigationRender(frame); }
UIImage *TDPPhoneNavigationRender(NSDictionary *frame){
 if(!frame) return nil;
 UIGraphicsImageRendererFormat *f=[UIGraphicsImageRendererFormat defaultFormat];f.scale=1;f.opaque=YES;
 return [[[UIGraphicsImageRenderer alloc]initWithSize:CGSizeMake(512,128) format:f] imageWithActions:^(UIGraphicsImageRendererContext *r){
  // Black background
  [UIColor.blackColor setFill];UIRectFill(CGRectMake(0,0,512,128));
  
  // Turn arrow icon — left column (90×110 box)
  NSInteger icon=[frame[@"icon"] integerValue];
  DrawTurnArrow(icon,CGRectMake(4,6,86,110));
  
  // Distance text — large, top of text area
  NSString *dist=frame[@"distance"]?:@"";
  NSMutableParagraphStyle *ps=[NSMutableParagraphStyle new];ps.lineBreakMode=NSLineBreakByTruncatingTail;
  [dist drawInRect:CGRectMake(96,2,296,46) withAttributes:@{NSFontAttributeName:[UIFont boldSystemFontOfSize:38],NSForegroundColorAttributeName:UIColor.whiteColor,NSParagraphStyleAttributeName:ps}];
  
  // Road / instruction — medium text
  NSString *road=frame[@"road"]?:@"";
  [road drawInRect:CGRectMake(96,48,296,30) withAttributes:@{NSFontAttributeName:[UIFont systemFontOfSize:21 weight:UIFontWeightMedium],NSForegroundColorAttributeName:UIColor.whiteColor,NSParagraphStyleAttributeName:ps}];
  
  // Turn instruction
  NSString *turn=frame[@"turn"]?:@"";
  [[UIColor colorWithWhite:0.85 alpha:1] setFill];
  [turn drawInRect:CGRectMake(96,80,296,22) withAttributes:@{NSFontAttributeName:[UIFont systemFontOfSize:16 weight:UIFontWeightRegular],NSForegroundColorAttributeName:[UIColor colorWithWhite:0.85 alpha:1],NSParagraphStyleAttributeName:ps}];
  
  // Remaining summary line
  NSString *summary=frame[@"summary"]?:@"";
  [summary drawInRect:CGRectMake(96,106,296,18) withAttributes:@{NSFontAttributeName:[UIFont systemFontOfSize:12],NSForegroundColorAttributeName:[UIColor colorWithWhite:0.6 alpha:1],NSParagraphStyleAttributeName:ps}];

  // Mini-map wireframe — Even Realities G2 vector HUD style (112×116 box)
  CGRect mapBox = CGRectMake(394, 6, 112, 116);
  [[UIColor colorWithWhite:0.22 alpha:1.0] setStroke];
  UIBezierPath *border = [UIBezierPath bezierPathWithRoundedRect:mapBox cornerRadius:8];
  border.lineWidth = 1.5;
  [border stroke];
  
  CGContextRef ctx = UIGraphicsGetCurrentContext();
  CGContextSaveGState(ctx);
  [border addClip];
  
  NSArray *userCoord = frame[@"userCoord"];
  if([userCoord isKindOfClass:NSArray.class] && userCoord.count == 2){
      double uLat = [userCoord[0] doubleValue];
      double uLon = [userCoord[1] doubleValue];
      double heading = [frame[@"heading"] doubleValue];
      
      CGFloat anchorX = mapBox.origin.x + mapBox.size.width * 0.50; // 450
      CGFloat anchorY = mapBox.origin.y + mapBox.size.height * 0.68; // 85
      CGFloat pxPerMeter = 0.22; // ~340m ahead
      
      double cosLat = cos(uLat * M_PI / 180.0);
      if(fabs(cosLat) < 0.01) cosLat = 0.01;
      double metersPerDegLon = 111320.0 * cosLat;
      double hRad = heading * M_PI / 180.0;
      double cosH = cos(hRad);
      double sinH = sin(hRad);
      
      CGPoint (^projectCoord)(double, double) = ^CGPoint(double lat, double lon){
          double dLatM = (lat - uLat) * 111320.0;
          double dLonM = (lon - uLon) * metersPerDegLon;
          double fwd = dLatM * cosH + dLonM * sinH;
          double rgt = dLonM * cosH - dLatM * sinH;
          return CGPointMake(anchorX + (CGFloat)(rgt * pxPerMeter),
                             anchorY - (CGFloat)(fwd * pxPerMeter));
      };
      
      // Layer 1: Surrounding Street Network (OpenStreetMap wireframe)
      NSArray *roadSegments = frame[@"roadSegments"];
      if([roadSegments isKindOfClass:NSArray.class] && roadSegments.count > 0){
          [[UIColor colorWithWhite:0.32 alpha:1.0] setStroke];
          for(NSArray *seg in roadSegments){
              if(![seg isKindOfClass:NSArray.class] || seg.count < 2) continue;
              UIBezierPath *rp = [UIBezierPath bezierPath];
              rp.lineWidth = 1.0;
              rp.lineJoinStyle = kCGLineJoinRound;
              rp.lineCapStyle = kCGLineCapRound;
              BOOL first = YES;
              for(NSArray *pt in seg){
                  if(![pt isKindOfClass:NSArray.class] || pt.count != 2) continue;
                  CGPoint p = projectCoord([pt[0] doubleValue], [pt[1] doubleValue]);
                  if(first){ [rp moveToPoint:p]; first = NO; }
                  else { [rp addLineToPoint:p]; }
              }
              [rp stroke];
          }
      } else {
          // Subtle fallback orientation grid
          [[UIColor colorWithWhite:0.18 alpha:1.0] setStroke];
          UIBezierPath *grid = [UIBezierPath bezierPath];
          grid.lineWidth = 1.0;
          for(int i = -3; i <= 3; i++){
              CGFloat dy = anchorY - (CGFloat)(i * 60.0 * pxPerMeter);
              [grid moveToPoint:CGPointMake(mapBox.origin.x, dy)];
              [grid addLineToPoint:CGPointMake(mapBox.origin.x + mapBox.size.width, dy)];
          }
          [grid stroke];
      }
      
      // Layer 2: Active Navigation Route (Bold High-Contrast Path)
      NSArray *routeCoords = frame[@"routeCoords"];
      if([routeCoords isKindOfClass:NSArray.class] && routeCoords.count >= 2){
          [UIColor.whiteColor setStroke];
          UIBezierPath *rp = [UIBezierPath bezierPath];
          rp.lineWidth = 3.5;
          rp.lineJoinStyle = kCGLineJoinRound;
          rp.lineCapStyle = kCGLineCapRound;
          BOOL first = YES;
          for(NSArray *pt in routeCoords){
              if(![pt isKindOfClass:NSArray.class] || pt.count != 2) continue;
              CGPoint p = projectCoord([pt[0] doubleValue], [pt[1] doubleValue]);
              if(first){ [rp moveToPoint:p]; first = NO; }
              else { [rp addLineToPoint:p]; }
          }
          [rp stroke];
      }
      
      // Layer 3: Upcoming Turn Maneuver Target Ring
      NSArray *maneuverCoord = frame[@"maneuverCoord"];
      if([maneuverCoord isKindOfClass:NSArray.class] && maneuverCoord.count == 2){
          CGPoint mp = projectCoord([maneuverCoord[0] doubleValue], [maneuverCoord[1] doubleValue]);
          if(CGRectContainsPoint(mapBox, mp)){
              UIBezierPath *ring = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(mp.x - 5, mp.y - 5, 10, 10)];
              [[UIColor colorWithWhite:0.95 alpha:1.0] setStroke];
              ring.lineWidth = 2.0;
              [ring stroke];
          }
      }
      
      // Layer 4: Directional Vehicle Cursor (Chevron pointing straight UP)
      UIBezierPath *cursor = [UIBezierPath bezierPath];
      [cursor moveToPoint:CGPointMake(anchorX, anchorY - 8)];
      [cursor addLineToPoint:CGPointMake(anchorX + 6, anchorY + 6)];
      [cursor addLineToPoint:CGPointMake(anchorX, anchorY + 3)];
      [cursor addLineToPoint:CGPointMake(anchorX - 6, anchorY + 6)];
      [cursor closePath];
      [[UIColor whiteColor] setFill];
      [cursor fill];
      [[UIColor blackColor] setStroke];
      cursor.lineWidth = 1.0;
      [cursor stroke];
      
      // HUD Compass Badge (Cardinal direction at top-left)
      static NSString *const cardinals[] = {@"N", @"NE", @"E", @"SE", @"S", @"SW", @"W", @"NW"};
      int cIdx = (int)lround(heading / 45.0) % 8;
      if(cIdx < 0) cIdx += 8;
      NSString *cardinalStr = cardinals[cIdx];
      [cardinalStr drawInRect:CGRectMake(mapBox.origin.x + 5, mapBox.origin.y + 3, 26, 14) withAttributes:@{
          NSFontAttributeName:[UIFont boldSystemFontOfSize:10],
          NSForegroundColorAttributeName:[UIColor colorWithWhite:0.8 alpha:1.0]
      }];
      
      // Distance Horizon Badge (Scale at top-right)
      [@"300m" drawInRect:CGRectMake(mapBox.origin.x + mapBox.size.width - 32, mapBox.origin.y + 3, 28, 14) withAttributes:@{
          NSFontAttributeName:[UIFont systemFontOfSize:9 weight:UIFontWeightMedium],
          NSForegroundColorAttributeName:[UIColor colorWithWhite:0.55 alpha:1.0]
      }];
      
  } else if([frame[@"navPoints"] isKindOfClass:NSArray.class] && [frame[@"navPoints"] count] >= 2){
      // Legacy fallback
      NSArray *navPoints = frame[@"navPoints"];
      CGFloat ox=mapBox.origin.x+4,oy=mapBox.origin.y+4,mw=mapBox.size.width-8,mh=mapBox.size.height-8;
      double minX=1023,maxX=0,minY=1023,maxY=0;
      for(NSArray *pt in navPoints){
          if(![pt isKindOfClass:NSArray.class]||pt.count!=2)continue;
          double px=[pt[0] doubleValue],py=[pt[1] doubleValue];
          minX=MIN(minX,px);maxX=MAX(maxX,px);minY=MIN(minY,py);maxY=MAX(maxY,py);
      }
      double spanX=MAX(maxX-minX,1),spanY=MAX(maxY-minY,1);
      double scale=MIN(mw/spanX,mh/spanY)*0.85;
      double centerX=(minX+maxX)/2,centerY=(minY+maxY)/2;
      [UIColor.whiteColor setStroke];
      UIBezierPath *route=[UIBezierPath bezierPath];route.lineWidth=3;route.lineJoinStyle=kCGLineJoinRound;route.lineCapStyle=kCGLineCapRound;
      BOOL first=YES;
      for(NSArray *pt in navPoints){
          if(![pt isKindOfClass:NSArray.class]||pt.count!=2)continue;
          double px=[pt[0] doubleValue],py=[pt[1] doubleValue];
          CGFloat sx=ox+mw/2+(px-centerX)*scale;CGFloat sy=oy+mh/2+(py-centerY)*scale;
          if(first){[route moveToPoint:CGPointMake(sx,sy)];first=NO;}
          else [route addLineToPoint:CGPointMake(sx,sy)];
      }
      [route stroke];
      if(navPoints.count>=1){
          NSArray *firstPt=navPoints[0];
          if([firstPt isKindOfClass:NSArray.class]&&firstPt.count==2){
              double px=[firstPt[0] doubleValue],py=[firstPt[1] doubleValue];
              CGFloat sx=ox+mw/2+(px-centerX)*scale,sy=oy+mh/2+(py-centerY)*scale;
              UIBezierPath *dot=[UIBezierPath bezierPathWithOvalInRect:CGRectMake(sx-4,sy-4,8,8)];[dot fill];
          }
      }
  } else {
      // Offline idle grid
      [[UIColor colorWithWhite:0.25 alpha:1] setStroke];
      UIBezierPath *streets=[UIBezierPath bezierPath];
      for(int i=0;i<3;i++){[streets moveToPoint:CGPointMake(404,30+i*30)];[streets addLineToPoint:CGPointMake(496,30+i*30)];[streets moveToPoint:CGPointMake(414+i*32,16)];[streets addLineToPoint:CGPointMake(414+i*32,111)];}
      streets.lineWidth=1;[streets stroke];
  }
  
  CGContextRestoreGState(ctx);
 }];
}

BOOL TDPPhoneNavigationStart(NSDictionary *frame){
 NSCAssert(NSThread.isMainThread,@"main only");
 if(NavFeed.active||Session.busy)return NO;
 [[TMPlayer shared] hideGlasses];
 [Session setForegroundActive:NO];
 BOOL ok=TNVStart(frame);
 if(ok){
  NavHUDActive=YES;
  AssertNavHUDBackgroundTask();
  StartBackgroundKeepalive();
 }
 return ok;
}

void TDPPhoneNavigationOffer(NSDictionary *frame){
 TNVOffer(frame);
}

void TDPPhoneNavigationPump(void){
 if(NavHUDActive)AssertNavHUDBackgroundTask();
 TNVPump();
}

void TDPPhoneNavigationStop(void){
 NavHUDActive=NO;
 EndNavHUDBackgroundTask();
 TNVStop();
 StopBackgroundKeepalive();
}

NSDictionary *TDPPhoneNavigationStatus(void){
 return TNVStatus();
}

// ─── TDP1 Live Music & Spotify HUD ─────────────────────────────────────────
// Renders live Spotify / Music album cover, track, artist, progress, and 3-row
// synchronized scrolling lyrics into a 512×128 image streamed directly to Item 8 (Display Test).
static BOOL MusicHUDInitialSent;
static NSUInteger MusicHUDCount;
static NSString *MusicHUDNote;
static NSTimer *MusicHUDTimer;
static dispatch_source_t MusicHUDDispatchTimer;
static NSTimeInterval MusicHUDStartTime;
static NSTimeInterval MusicHUDLastDeltaTime;

static UIImage *DynamicMusicImage(void){
    UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat defaultFormat];
    fmt.scale = 1.0;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(512, 128) format:fmt];
    
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctxRef){
        CGContextRef ctx = ctxRef.CGContext;
        
        // Background: pure black
        [[UIColor blackColor] setFill];
        CGContextFillRect(ctx, CGRectMake(0, 0, 512, 128));
        
        // Extract current track information
        NSString *title = @"RayNeo Music";
        NSString *artist = @"Ready";
        UIImage *cover = nil;
        NSArray *lyrics = nil;
        double progressMs = 0;
        double durationMs = 0;
        BOOL isPlaying = NO;
        
        SpotifyTrack *st = SpotifyAPI.shared.currentTrack;
        if(st){
            title = st.name.length ? st.name : @"Unknown Track";
            artist = st.artist.length ? st.artist : @"Unknown Artist";
            cover = SpotifyAPI.shared.currentCover;
            lyrics = SpotifyAPI.shared.currentLyrics;
            progressMs = st.progressMs;
            durationMs = st.durationMs;
            isPlaying = st.isPlaying;
        } else if(TMPlayer.shared.song){
            NSDictionary *s = TMPlayer.shared.song;
            title = [s[@"name"] isKindOfClass:NSString.class] && [s[@"name"] length] ? s[@"name"] : @"Unknown Track";
            artist = [s[@"artist"] isKindOfClass:NSString.class] && [s[@"artist"] length] ? s[@"artist"] : @"Unknown Artist";
            cover = TMPlayer.shared.cover;
            lyrics = TMPlayer.shared.lyrics;
            progressMs = TMPlayer.shared.position * 1000.0;
            durationMs = TMPlayer.shared.duration * 1000.0;
            isPlaying = TMPlayer.shared.playing;
        }
        
        // ── 1. Left: Circular Album Art (108x108 at x:10, y:10) ──
        CGRect coverRect = CGRectMake(10, 10, 108, 108);
        CGContextSaveGState(ctx);
        UIBezierPath *coverClip = [UIBezierPath bezierPathWithOvalInRect:coverRect];
        [coverClip addClip];
        
        if(cover){
            [cover drawInRect:coverRect];
        } else {
            // Vinyl Record Art
            [[UIColor colorWithWhite:0.12 alpha:1.0] setFill];
            CGContextFillRect(ctx, coverRect);
            [[UIColor colorWithWhite:0.25 alpha:1.0] setStroke];
            for(int r = 18; r < 50; r += 7){
                UIBezierPath *groove = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(64 - r, 64 - r, r * 2, r * 2)];
                groove.lineWidth = 1.0;
                [groove stroke];
            }
            [[UIColor colorWithWhite:0.85 alpha:1.0] setFill];
            UIBezierPath *center = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(52, 52, 24, 24)];
            [center fill];
            [[UIColor blackColor] setFill];
            UIBezierPath *hole = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(60, 60, 8, 8)];
            [hole fill];
        }
        CGContextRestoreGState(ctx);
        
        // Border ring around album art
        [[UIColor colorWithWhite:0.6 alpha:1.0] setStroke];
        UIBezierPath *coverBorder = [UIBezierPath bezierPathWithOvalInRect:coverRect];
        coverBorder.lineWidth = 1.5;
        [coverBorder stroke];
        
        // Progress arc around album art
        if(durationMs > 0){
            double progressFraction = MIN(1.0, MAX(0.0, progressMs / durationMs));
            CGFloat startAngle = -M_PI_2;
            CGFloat endAngle = startAngle + (CGFloat)(progressFraction * 2.0 * M_PI);
            UIBezierPath *progressArc = [UIBezierPath bezierPathWithArcCenter:CGPointMake(64, 64)
                                                                      radius:56
                                                                  startAngle:startAngle
                                                                    endAngle:endAngle
                                                                   clockwise:YES];
            [[UIColor whiteColor] setStroke];
            progressArc.lineWidth = 2.5;
            progressArc.lineCapStyle = kCGLineCapRound;
            [progressArc stroke];
        }
        
        // ── 2. Top-Right: Track Title & Artist & Time ──
        NSMutableParagraphStyle *style = [NSMutableParagraphStyle new];
        style.lineBreakMode = NSLineBreakByTruncatingTail;
        
        // Track Title (bold 15pt)
        [title drawInRect:CGRectMake(130, 8, 275, 20) withAttributes:@{
            NSFontAttributeName:[UIFont boldSystemFontOfSize:15],
            NSForegroundColorAttributeName:UIColor.whiteColor,
            NSParagraphStyleAttributeName:style
        }];
        
        // Artist Name (12pt light gray)
        [artist drawInRect:CGRectMake(130, 28, 275, 16) withAttributes:@{
            NSFontAttributeName:[UIFont systemFontOfSize:12 weight:UIFontWeightMedium],
            NSForegroundColorAttributeName:[UIColor colorWithWhite:0.7 alpha:1.0],
            NSParagraphStyleAttributeName:style
        }];
        
        // Time Stamp (top-right)
        NSString *timeStr;
        if(isPlaying && durationMs > 0){
            int curSec = (int)(progressMs / 1000.0);
            int totSec = (int)(durationMs / 1000.0);
            timeStr = [NSString stringWithFormat:@"%02d:%02d/%02d:%02d", curSec/60, curSec%60, totSec/60, totSec%60];
        } else if(!isPlaying && st){
            timeStr = @"PAUSED";
        } else {
            timeStr = @"SPOTIFY";
        }
        NSMutableParagraphStyle *rightStyle = [NSMutableParagraphStyle new];
        rightStyle.alignment = NSTextAlignmentRight;
        [timeStr drawInRect:CGRectMake(405, 8, 97, 16) withAttributes:@{
            NSFontAttributeName:[UIFont monospacedDigitSystemFontOfSize:11 weight:UIFontWeightMedium],
            NSForegroundColorAttributeName:isPlaying ? [UIColor colorWithWhite:0.75 alpha:1.0] : [UIColor colorWithRed:1.0 green:0.7 blue:0.2 alpha:1.0],
            NSParagraphStyleAttributeName:rightStyle
        }];
        
        // Thin separator line
        [[UIColor colorWithWhite:0.25 alpha:1.0] setStroke];
        UIBezierPath *div = [UIBezierPath bezierPath];
        [div moveToPoint:CGPointMake(130, 47)];
        [div addLineToPoint:CGPointMake(502, 47)];
        div.lineWidth = 0.5;
        [div stroke];
        
        // ── 3. Bottom-Right: 3 Synchronized Lyric Lines ──
        if(lyrics.count > 0){
            NSInteger activeIdx = -1;
            for(NSInteger i = 0; i < (NSInteger)lyrics.count; i++){
                double ms = [lyrics[i][@"ms"] doubleValue];
                if(ms <= progressMs + 350){
                    activeIdx = i;
                } else {
                    break;
                }
            }
            if(activeIdx < 0) activeIdx = 0;
            
            // Row 1: Previous lyric (dim)
            if(activeIdx > 0){
                NSString *prevText = lyrics[activeIdx - 1][@"text"] ?: @"";
                [prevText drawInRect:CGRectMake(130, 51, 372, 17) withAttributes:@{
                    NSFontAttributeName:[UIFont systemFontOfSize:11 weight:UIFontWeightRegular],
                    NSForegroundColorAttributeName:[UIColor colorWithWhite:0.4 alpha:1.0],
                    NSParagraphStyleAttributeName:style
                }];
            }
            
            // Row 2: Current active lyric (bright bold white)
            NSString *currText = lyrics[activeIdx][@"text"] ?: @"";
            [currText drawInRect:CGRectMake(130, 71, 372, 26) withAttributes:@{
                NSFontAttributeName:[UIFont boldSystemFontOfSize:16],
                NSForegroundColorAttributeName:UIColor.whiteColor,
                NSParagraphStyleAttributeName:style
            }];
            
            // Row 3: Next lyric (dim)
            if(activeIdx + 1 < (NSInteger)lyrics.count){
                NSString *nextText = lyrics[activeIdx + 1][@"text"] ?: @"";
                [nextText drawInRect:CGRectMake(130, 101, 372, 17) withAttributes:@{
                    NSFontAttributeName:[UIFont systemFontOfSize:11 weight:UIFontWeightRegular],
                    NSForegroundColorAttributeName:[UIColor colorWithWhite:0.4 alpha:1.0],
                    NSParagraphStyleAttributeName:style
                }];
            }
        } else {
            NSString *msg = isPlaying ? @"♫ Playing on Spotify · Live HUD Active" : @"♫ Music Paused · Tap Play to Resume";
            [msg drawInRect:CGRectMake(130, 70, 372, 22) withAttributes:@{
                NSFontAttributeName:[UIFont systemFontOfSize:13 weight:UIFontWeightMedium],
                NSForegroundColorAttributeName:[UIColor colorWithWhite:0.7 alpha:1.0],
                NSParagraphStyleAttributeName:style
            }];
            [@"Open Item 8 (显示测试 / Display Test) on glasses" drawInRect:CGRectMake(130, 96, 372, 18) withAttributes:@{
                NSFontAttributeName:[UIFont systemFontOfSize:11 weight:UIFontWeightRegular],
                NSForegroundColorAttributeName:[UIColor colorWithWhite:0.45 alpha:1.0],
                NSParagraphStyleAttributeName:style
            }];
        }
    }];
}

void TDPPhoneMusicPump(void){
    if(!MusicHUDActive) return;
    CheckPeer();
    [Session tick];
    
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    
    // Phase 1: Wait for session handshake
    if(!Session.ready){
        if(Session.busy){
            MusicHUDNote = Session.state ?: @"Verifying glasses session...";
            return;
        }
        if(now - MusicHUDStartTime > 3.0 && now - MusicHUDStartTime < 25.0){
            [Session setForegroundActive:YES];
            [Session query];
            MusicHUDNote = @"Waiting for Item 8 on glasses to respond...";
        } else if(now - MusicHUDStartTime >= 25.0){
            MusicHUDNote = @"Connection timeout. Please tap Item 8 on glasses.";
        }
        return;
    }
    
    // Phase 2: Send initial full frame
    if(!MusicHUDInitialSent){
        if(Session.busy){
            if(Session.frameActive){
                NSUInteger chunks = Session.completedChunks;
                MusicHUDNote = [NSString stringWithFormat:@"Sending Music HUD: %lu/139 blocks (%.0f%%)...",
                               (unsigned long)chunks, (double)chunks * 100.0 / 139.0];
            } else {
                MusicHUDNote = Session.state ?: @"Preparing Music HUD...";
            }
            return;
        }
        
        UIImage *img = DynamicMusicImage();
        NSData *pixels = Gray(img);
        if(pixels.length != TDP_PIXELS) return;
        
        BOOL ok = [Session sendFrame:pixels];
        if(ok){
            MusicHUDInitialSent = YES;
            MusicHUDNote = @"Sending full Music HUD (~15s)...";
        } else {
            MusicHUDNote = @"Failed to send canvas. Retrying...";
        }
        return;
    }
    
    // Phase 3: Wait for initial full frame transmission to complete
    if(Session.frameActive){
        NSUInteger chunks = Session.completedChunks;
        MusicHUDNote = [NSString stringWithFormat:@"Transferring HUD: %lu/139 blocks (%.0f%%)...",
                       (unsigned long)chunks, (double)chunks * 100.0 / 139.0];
        return;
    }
    
    // Phase 4: Baseline established, send differential delta updates
    if(!Session.hasPixelBaseline){
        MusicHUDNote = Session.state ?: @"Establishing pixel baseline...";
        return;
    }
    
    if(Session.busy) return;
    
    if(now - MusicHUDLastDeltaTime < 1.0) return;
    
    UIImage *img = DynamicMusicImage();
    NSData *pixels = Gray(img);
    if(pixels.length != TDP_PIXELS) return;
    
    NSData *known = Session.knownPixels;
    if(known && [pixels isEqualToData:known]) return;
    
    BOOL ok = [Session sendPartialPixels:pixels];
    if(ok){
        MusicHUDLastDeltaTime = now;
        MusicHUDCount++;
        MusicHUDNote = [NSString stringWithFormat:@"Live Music HUD Active · Update #%lu", (unsigned long)MusicHUDCount];
    }
}

BOOL TDPPhoneMusicStart(void){
    NSCAssert(NSThread.isMainThread, @"main only");
    if(MusicHUDActive) return YES;
    if(NavHUDActive) TDPPhoneNavigationStop();
    
    if(!Setup()){
        if(!TIOProtocolDevice().length) MusicHUDNote = @"Glasses not connected via Bluetooth.";
        else MusicHUDNote = @"Channel busy · Please wait a moment and tap Start again.";
        return NO;
    }
    
    NSURL *spoolRoot = [NSURL fileURLWithPath:[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/TurboIOPrivateAddon/DisplayTDP1-PHONE06"] isDirectory:YES];
    NSArray *spoolItems = [NSFileManager.defaultManager contentsOfDirectoryAtURL:spoolRoot includingPropertiesForKeys:nil options:0 error:nil];
    for(NSURL *u in spoolItems) [NSFileManager.defaultManager removeItemAtURL:u error:nil];
    
    [Session disconnect];
    [Session setForegroundActive:YES];
    
    MusicHUDActive = YES;
    MusicHUDInitialSent = NO;
    MusicHUDCount = 0;
    MusicHUDStartTime = NSProcessInfo.processInfo.systemUptime;
    MusicHUDLastDeltaTime = 0;
    
    BOOL ok = [Session query];
    MusicHUDNote = ok ? @"Connecting to glasses (Item 8 · Display Test)..." : @"Querying glasses... Make sure Item 8 is open.";
    
    StartBackgroundKeepalive();
    
    if(MusicHUDDispatchTimer){ dispatch_source_cancel(MusicHUDDispatchTimer); MusicHUDDispatchTimer = nil; }
    MusicHUDDispatchTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(MusicHUDDispatchTimer, dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC), 100 * NSEC_PER_MSEC, 20 * NSEC_PER_MSEC);
    dispatch_source_set_event_handler(MusicHUDDispatchTimer, ^{
        TDPPhoneMusicPump();
    });
    dispatch_resume(MusicHUDDispatchTimer);
    
    [MusicHUDTimer invalidate];
    MusicHUDTimer = [NSTimer timerWithTimeInterval:0.1 repeats:YES block:^(NSTimer *t){
        TDPPhoneMusicPump();
    }];
    [[NSRunLoop mainRunLoop] addTimer:MusicHUDTimer forMode:NSRunLoopCommonModes];
    return YES;
}

void TDPPhoneMusicStop(void){
    MusicHUDActive = NO;
    MusicHUDInitialSent = NO;
    MusicHUDCount = 0;
    MusicHUDLastDeltaTime = 0;
    if(MusicHUDDispatchTimer){
        dispatch_source_cancel(MusicHUDDispatchTimer);
        MusicHUDDispatchTimer = nil;
    }
    [MusicHUDTimer invalidate];
    MusicHUDTimer = nil;
    StopBackgroundKeepalive();
    if(Session) [Session disconnect];
    MusicHUDNote = @"Music HUD stopped";
}

NSDictionary *TDPPhoneMusicStatus(void){
    return @{
        @"active":@(MusicHUDActive),
        @"busy":@(Session.busy),
        @"note":MusicHUDNote ?: @"Open Item 8 (Display Test) on glasses, then toggle Glasses HUD",
        @"snapshots":@(MusicHUDCount),
        @"ready":@(Session.ready),
        @"chunks":@(Session.completedChunks),
        @"baseline":@(Session.hasPixelBaseline)
    };
}

UIImage *TDPPhoneMusicRender(void){
    return DynamicMusicImage();
}
@interface TDPPhonePage:UITableViewController<UIDocumentPickerDelegate>
@property(nonatomic,strong) UIImage *preview;
@property(nonatomic,strong) NSData *pixels;
@property(nonatomic,strong) NSTimer *timer;
@property(nonatomic,copy) NSString *note;
@property(nonatomic) BOOL visible,loading,left;
@property(nonatomic) BOOL refreshPending;
@property(nonatomic) NSTimeInterval lastRefresh;
@property(nonatomic) unsigned meters;
@end
@implementation TDPPhonePage
- (void)viewDidLoad{
 [super viewDidLoad];self.title=@"Display Mirroring · PHONE 06";self.tableView.rowHeight=UITableViewAutomaticDimension;self.tableView.estimatedRowHeight=76;
 TDPDiagConfigure([NSURL fileURLWithPath:[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/TurboIOPrivateAddon/display-phone-diagnostics.json"]]);
 self.note=@"TDP1 image test preserved. Native navigation starts from Navigation tab.";
 self.meters=80;self.preview=NavigationImage(NO,self.meters);self.pixels=Gray(self.preview);
 [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(suspend) name:UIApplicationWillResignActiveNotification object:nil];
 [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(resume) name:UIApplicationDidBecomeActiveNotification object:nil];
 __weak typeof(self) weak=self;
 self.timer=[NSTimer scheduledTimerWithTimeInterval:0.05 repeats:YES block:^(NSTimer *t){
  TDPPhonePage *s=weak;if(!s)return;
  CheckPeer();[Session tick];[s refreshStatusIfDue];
 }];
 [self bind];
}
- (void)bind{__weak typeof(self) weak=self;Session.changed=^{TDPPhonePage *s=weak;if(!s)return;s.note=Session.state;s.refreshPending=YES;[s refreshStatusIfDue];};}
- (void)refreshStatusIfDue {
 if(!self.refreshPending)return;
 NSTimeInterval now=NSProcessInfo.processInfo.systemUptime;
 if(Session.busy&&now-self.lastRefresh<0.25)return;
 self.refreshPending=NO;self.lastRefresh=now;[self.tableView reloadData];[self saveStatus];
}
- (void)viewDidAppear:(BOOL)animated{[super viewDidAppear:animated];self.visible=YES;[self resume];[self saveStatus];}
- (void)viewWillDisappear:(BOOL)animated{[super viewWillDisappear:animated];self.visible=NO;if(!NavHUDActive)[self suspend];}
- (void)suspend{if(!NavHUDActive)[Session setForegroundActive:NO];}
- (void)resume{if(self.visible&&UIApplication.sharedApplication.applicationState==UIApplicationStateActive)[Session setForegroundActive:YES];}
- (void)dealloc{[_timer invalidate];[NSNotificationCenter.defaultCenter removeObserver:self];}
- (void)saveStatus{
 NSString *root=[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/TurboIOPrivateAddon"];
 [NSFileManager.defaultManager createDirectoryAtPath:root withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil];
 NSDictionary *d=@{@"build":@"NAVIGATION-PHONE-01",@"timestamp":@(NSDate.date.timeIntervalSince1970),@"pid":@(NSProcessInfo.processInfo.processIdentifier),@"otaStage":TIOOTAFlashStatus()[@"stage"]?:@0,@"state":Session.state?:@"not_queried",@"ready":@(Session.ready),@"busy":@(Session.busy),@"sid":@(Session.sessionID),@"revision":@(Session.revision),@"chunks":@(Session.completedChunks),@"frameActive":@(Session.frameActive),@"frameElapsed":@(Session.frameElapsed),@"deltaActive":@(Session.deltaActive),@"deltaTotal":@(Session.deltaTotal),@"deltaCompleted":@(Session.completedRects),@"deltaElapsed":@(Session.deltaElapsed),@"pixelBaseline":@(Session.hasPixelBaseline),@"firmwareDetection":@"query-reply-only",@"physicalDisplayVerified":@NO};
 NSString *path=[root stringByAppendingPathComponent:@"display-phone-status.json"];
 [[NSJSONSerialization dataWithJSONObject:d options:NSJSONWritingSortedKeys error:nil] writeToFile:path options:NSDataWritingAtomic error:nil];
 [NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:path error:nil];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)t{return 4;}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s{return s==0?2:s==1?4:s==2?3:4;}
- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s{return @[@"Connections and capabilities · Authentic receipt required",@"Mobile phone drawing · No changes to glasses firmware",@"Test and Exit",@"Low latency experiment·Transmit only changing areas"][s];}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip{
 UITableViewCell *c=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];c.textLabel.numberOfLines=c.detailTextLabel.numberOfLines=0;c.detailTextLabel.textColor=UIColor.secondaryLabelColor;
 if(ip.section==0){c.textLabel.text=ip.row?@"1 · Query glasses SID":@"DISPLAY PHONE 06 · Diagnosis";c.detailTextLabel.text=ip.row?@"First enter the Turbo Display SID page on the glasses. Only query once, stop if no matching receipt is found within 5 seconds; do not guess the firmware version based on old prompts.":self.note;c.imageView.image=[UIImage systemImageNamed:ip.row?@"antenna.radiowaves.left.and.right":@"checkmark.shield"];}
 if(ip.section==1){NSArray *titles=@[@"Navigation layout · Native preview",@"Example of switching left turn/right turn",@"Select PNG/JPEG/HEIC from file",@"2 · Send full canvas (64 KiB)"];c.textLabel.text=titles[ip.row];
  if(ip.row==0){
   c.textLabel.text=nil;c.detailTextLabel.text=nil;UIImageView *v=[[UIImageView alloc]initWithImage:self.preview];v.contentMode=UIViewContentModeScaleAspectFit;v.backgroundColor=UIColor.blackColor;v.layer.cornerRadius=10;v.clipsToBounds=YES;
   UILabel *label=[UILabel new];label.text=@"512×128 grayscale · Mobile phone layout preview \n Arrow / Distance / Road name / Indicative mini map \n is not real-time navigation, nor is it a screenshot of glasses";label.numberOfLines=0;label.font=[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];label.textColor=UIColor.secondaryLabelColor;
   UIStackView *stack=[[UIStackView alloc]initWithArrangedSubviews:@[v,label]];stack.axis=UILayoutConstraintAxisVertical;stack.spacing=10;stack.translatesAutoresizingMaskIntoConstraints=NO;[c.contentView addSubview:stack];
   [NSLayoutConstraint activateConstraints:@[[stack.leadingAnchor constraintEqualToAnchor:c.contentView.leadingAnchor constant:16],[stack.trailingAnchor constraintEqualToAnchor:c.contentView.trailingAnchor constant:-16],[stack.topAnchor constraintEqualToAnchor:c.contentView.topAnchor constant:16],[stack.bottomAnchor constraintEqualToAnchor:c.contentView.bottomAnchor constant:-16],[v.heightAnchor constraintEqualToAnchor:v.widthAnchor multiplier:0.25]]];
  }
  else if(ip.row==3)c.detailTextLabel.text=@"A single frame is 139 blocks; the previous real machine was about 20 seconds. The screen will be changed after complete verification, and it will stop if it is not completed within 25 seconds. A local update baseline is established after the first send.";
  else c.detailTextLabel.text=self.loading?@"Decoding locally...":@"Only modify the mobile preview and do not automatically send it";
 }
 if(ip.section==2){c.textLabel.text=@[@"3 · Send 20×20 test tokens",@"Close glasses test page",@"Return to N8W old version image transfer"][ip.row];c.detailTextLabel.text=ip.row==0?Session.state?:@"Not yet queried":ip.row==1?@"The session needs to be valid and there are no tasks in progress; exiting the mobile page will stop the lease renewal, and there is no guarantee that the lens will be closed immediately.":@"Retain FIX 01, use artificial SID; no new firmware required";}
 if(ip.section==3){
  c.textLabel.text=@[@"4 · Distance 80 / 60 meters switching and local transmission",@"5 · Turn left and right to switch and send locally",@"6 · Resend the same picture (should be zero transmission)",@"Pixel baseline and local transmission state"][ip.row];
  c.detailTextLabel.text=ip.row==3?[NSString stringWithFormat:@"Baseline %@ · %lu/%lu Block · %.2f Seconds \n%@",Session.hasPixelBaseline?@"Confirmed":@"invalid",(unsigned long)Session.completedRects,(unsigned long)Session.deltaTotal,Session.deltaElapsed,Session.state?:@"Not queried"]:@"First, successfully send a complete navigation example image before clicking this item. Only differences are sent, up to 32 blocks; it is not real-time navigation and does not automatically and continuously send.";
 }
 BOOL action=!(ip.section==0&&ip.row==0)&&!(ip.section==1&&ip.row==0)&&!(ip.section==3&&ip.row==3);if(action){c.textLabel.textColor=UIColor.systemBlueColor;c.accessoryType=UITableViewCellAccessoryDisclosureIndicator;}return c;
}
- (void)result:(BOOL)ok {if(!ok){self.note=Session.state?:@"Not sent: Please connect and enter the glasses Turbo Display page first, and then query the SID.";[self.tableView reloadData];} [self saveStatus];}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)p{
 [t deselectRowAtIndexPath:p animated:YES];if(self.loading)return;
 if(p.section==0&&p.row==1){if(!Setup()){self.note=@"There is no current official connection, or the results of old tasks are unknown. Please confirm the connection on the official device page, a second Bluetooth connection will not be created.";[t reloadData];return;}[self bind];[self resume];[self result:[Session query]];}
 if(p.section==1&&p.row==1){self.left=!self.left;self.preview=NavigationImage(self.left,self.meters);self.pixels=Gray(self.preview);[t reloadData];}
 if(p.section==1&&p.row==2){UIDocumentPickerViewController *c=[[UIDocumentPickerViewController alloc]initForOpeningContentTypes:@[UTTypePNG,UTTypeJPEG,UTTypeHEIC] asCopy:YES];c.delegate=self;[self presentViewController:c animated:YES completion:nil];}
 if(p.section==1&&p.row==3){if(!Session.ready||Session.busy){[self result:NO];return;}
  UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Send native canvas?" message:@"It will only be sent to the currently paired glasses, and will not be uploaded to the cloud or firmware flashed. The actual file throughput is yet to be verified, and will not be blindly resent after timeout." preferredStyle:UIAlertControllerStyleAlert];
  [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];__weak typeof(self) weak=self;
  [a addAction:[UIAlertAction actionWithTitle:@"send" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){[weak result:[Session sendFrame:weak.pixels]];}]];[self presentViewController:a animated:YES completion:nil];
 }
 if(p.section==2&&p.row==0)[self result:[Session sendTestRect]];
 if(p.section==2&&p.row==1)[self result:[Session closePage]];
 if(p.section==2&&p.row==2)[self.navigationController pushViewController:TIOImageUploadLabController() animated:YES];
 if(p.section==3&&p.row<3){
  BOOL left=p.row==1?!self.left:self.left;unsigned meters=p.row==0?(self.meters==80?60:80):self.meters;
  UIImage *preview=p.row==2?self.preview:NavigationImage(left,meters);NSData *pixels=p.row==2?self.pixels:Gray(preview);
  BOOL ok=[Session sendChangedPixels:pixels];if(ok){self.left=left;self.meters=meters;self.preview=preview;self.pixels=pixels;[t reloadData];}[self result:ok];
 }
}
- (void)documentPicker:(UIDocumentPickerViewController *)c didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls{
 NSURL *url=urls.firstObject;if(!url)return;self.loading=YES;[self.tableView reloadData];
 dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
  BOOL scoped=[url startAccessingSecurityScopedResource];UIImage *im=nil;NSDictionary *attrs=[NSFileManager.defaultManager attributesOfItemAtPath:url.path error:nil];
  if([attrs[NSFileType] isEqual:NSFileTypeRegular]&&[attrs[NSFileSize] unsignedLongLongValue]<=20*1024*1024){
   CGImageSourceRef src=CGImageSourceCreateWithURL((__bridge CFURLRef)url,(__bridge CFDictionaryRef)@{(__bridge NSString *)kCGImageSourceShouldCache:@NO});
   if(src){CFStringRef type=CGImageSourceGetType(src);BOOL allowed=type&&(CFEqual(type,CFSTR("public.png"))||CFEqual(type,CFSTR("public.jpeg"))||CFEqual(type,CFSTR("public.heic")));
    NSDictionary *props=CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(src,0,NULL));uint64_t w=[props[(__bridge NSString *)kCGImagePropertyPixelWidth] unsignedLongLongValue],h=[props[(__bridge NSString *)kCGImagePropertyPixelHeight] unsignedLongLongValue];
    if(allowed&&w&&h&&w<=16000000&&h<=16000000&&w<=16000000/h&&CGImageSourceGetCount(src)==1){
     CGImageRef thumb=CGImageSourceCreateThumbnailAtIndex(src,0,(__bridge CFDictionaryRef)@{(__bridge NSString *)kCGImageSourceCreateThumbnailFromImageAlways:@YES,(__bridge NSString *)kCGImageSourceCreateThumbnailWithTransform:@YES,(__bridge NSString *)kCGImageSourceThumbnailMaxPixelSize:@512});
     if(thumb){UIImage *small=[UIImage imageWithCGImage:thumb];UIGraphicsImageRendererFormat *f=[UIGraphicsImageRendererFormat defaultFormat];f.scale=1;f.opaque=YES;
      im=[[[UIGraphicsImageRenderer alloc]initWithSize:CGSizeMake(512,128) format:f] imageWithActions:^(UIGraphicsImageRendererContext *r){[UIColor.blackColor setFill];UIRectFill(CGRectMake(0,0,512,128));CGFloat s=MIN(512/small.size.width,128/small.size.height);[small drawInRect:CGRectMake((512-small.size.width*s)/2,(128-small.size.height*s)/2,small.size.width*s,small.size.height*s)];}];CGImageRelease(thumb);
     }
    }CFRelease(src);
   }
  }
  if(scoped)[url stopAccessingSecurityScopedResource];NSData *gray=Gray(im);
  dispatch_async(dispatch_get_main_queue(),^{self.loading=NO;if(gray){self.preview=GrayPreview(gray);self.pixels=gray;self.note=@"The thumbnail has been localized and has not been sent.";}else self.note=@"The file is unavailable or exceeds the limit: Please download it to the device in the File App first. Single frame PNG/JPEG/HEIC, 16MP/20MiB is limited.";[self.tableView reloadData];});
 });
}
@end
UIViewController *TDPPhoneController(void){return [[TDPPhonePage alloc]initWithStyle:UITableViewStyleInsetGrouped];}
