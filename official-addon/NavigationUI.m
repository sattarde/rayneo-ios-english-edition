#import "NavigationUI.h"
#import "NavigationCore.h"
#import "NavigationModes.h"
#import "NavigationTransport.h"
#import "ManualHUD.h"
#import "NavigationTeleHUD.h"
#import "NavigationSubtitleHUD.h"
#import "SubtitleHUD.h"
#import "NewsTeleprompter.h"
#import "NavigationPlaces.h"
#import "NavigationBackground.h"
#import <CoreLocation/CoreLocation.h>
#import <Security/Security.h>
#import <MapKit/MapKit.h>

static NSString *const NavConsent=@"io.turboio.navigation.privacy.v1";
static NSString *const DefaultGoogleKey=@"";

static NSDictionary *KeyQuery(void){
    return @{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,
             (__bridge id)kSecAttrService:@"io.turboio.navigation",
             (__bridge id)kSecAttrAccount:@"google-maps-ios"};
}

static NSString *ReadNavKey(void){
    NSMutableDictionary *q=[KeyQuery() mutableCopy];
    q[(__bridge id)kSecReturnData]=@YES;
    CFTypeRef v=NULL;
    if(SecItemCopyMatching((__bridge CFDictionaryRef)q,&v)==errSecSuccess){
        NSString *s=[[NSString alloc]initWithData:CFBridgingRelease(v) encoding:NSUTF8StringEncoding];
        if(s.length>=20)return s;
    }
    return DefaultGoogleKey;
}

static BOOL ValidKey(NSString *s){
    return [s isKindOfClass:NSString.class]&&s.length>=20;
}

static BOOL WriteNavKey(NSString *s){
    if(!ValidKey(s))return NO;
    NSDictionary *a=@{(__bridge id)kSecValueData:[s dataUsingEncoding:NSUTF8StringEncoding],
                      (__bridge id)kSecAttrAccessible:(__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly};
    OSStatus r=SecItemUpdate((__bridge CFDictionaryRef)KeyQuery(),(__bridge CFDictionaryRef)a);
    if(r==errSecItemNotFound){
        NSMutableDictionary *q=[KeyQuery() mutableCopy];
        [q addEntriesFromDictionary:a];
        r=SecItemAdd((__bridge CFDictionaryRef)q,NULL);
    }
    return r==errSecSuccess;
}

static NSString *StripHTML(NSString *html){
    if(!html.length)return @"";
    NSRegularExpression *regex=[NSRegularExpression regularExpressionWithPattern:@"<[^>]+>" options:0 error:nil];
    return [regex stringByReplacingMatchesInString:html options:0 range:NSMakeRange(0,html.length) withTemplate:@""];
}

static NSInteger ManeuverToIcon(NSString *m, NSString *inst){
    NSString *lower=[NSString stringWithFormat:@"%@ %@", m?:@"", inst?:@""].lowercaseString;
    if([lower containsString:@"sharp-left"]||[lower containsString:@"sharp left"])return 6;
    if([lower containsString:@"sharp-right"]||[lower containsString:@"sharp right"])return 7;
    if([lower containsString:@"slight-left"]||[lower containsString:@"slight left"])return 4;
    if([lower containsString:@"slight-right"]||[lower containsString:@"slight right"])return 5;
    if([lower containsString:@"left"])return 2;
    if([lower containsString:@"right"])return 3;
    if([lower containsString:@"u-turn"]||[lower containsString:@"uturn"])return 8;
    if([lower containsString:@"roundabout"]||[lower containsString:@"rotary"])return 11;
    if([lower containsString:@"pedestrian"]||[lower containsString:@"crosswalk"])return 29;
    if([lower containsString:@"footbridge"]||[lower containsString:@"overpass"])return 30;
    if([lower containsString:@"underpass"])return 31;
    if([lower containsString:@"destination"]||[lower containsString:@"arrive"])return 15;
    return 9;
}

static NSString *IconToArrow(NSInteger icon){
    switch(icon){
        case 2:return @"↰";
        case 3:return @"↱";
        case 4:return @"↖";
        case 5:return @"↗";
        case 6:return @"↲";
        case 7:return @"↳";
        case 8:case 19:return @"↺";
        case 9:case 20:return @"⬆";
        case 11:case 17:return @"⟳";
        case 12:case 18:return @"⟳";
        case 15:return @"🏁";
        default:return @"⬆";
    }
}

static NSString *CleanRoad(NSString *r){
    if(!r.length)return @"Follow route";
    NSString *cleaned=r;
    if([cleaned hasPrefix:@"Onto "])cleaned=[cleaned substringFromIndex:5];
    NSRegularExpression *regex=[NSRegularExpression regularExpressionWithPattern:@"^(Walk|Head|Drive|Ride)\\s+(north|south|east|west|northeast|northwest|southeast|southwest)\\s+on\\s+" options:NSRegularExpressionCaseInsensitive error:nil];
    cleaned=[regex stringByReplacingMatchesInString:cleaned options:0 range:NSMakeRange(0,cleaned.length) withTemplate:@""];
    return cleaned.length?cleaned:r;
}

static NSArray<NSValue *> *DecodeGooglePolyline(NSString *encoded){
    NSMutableArray<NSValue *> *coords=[NSMutableArray new];
    NSUInteger len=encoded.length;
    NSUInteger index=0;
    NSInteger lat=0, lng=0;
    while(index<len){
        NSInteger b, shift=0, result=0;
        do{
            if(index>=len)break;
            b=[encoded characterAtIndex:index++]-63;
            result|=(b&0x1f)<<shift;
            shift+=5;
        }while(b>=0x20);
        NSInteger dlat=((result&1)?~(result>>1):(result>>1));
        lat+=dlat;
        
        shift=0;
        result=0;
        do{
            if(index>=len)break;
            b=[encoded characterAtIndex:index++]-63;
            result|=(b&0x1f)<<shift;
            shift+=5;
        }while(b>=0x20);
        NSInteger dlng=((result&1)?~(result>>1):(result>>1));
        lng+=dlng;
        
        CLLocationCoordinate2D c=CLLocationCoordinate2DMake(lat/1E5, lng/1E5);
        [coords addObject:[NSValue valueWithBytes:&c objCType:@encode(CLLocationCoordinate2D)]];
    }
    return coords;
}

@interface TIONavigationPanel:UIViewController<CLLocationManagerDelegate, MKMapViewDelegate>
@property UILabel *statusLabel,*hudLabel,*destinationLabel;
@property UIStackView *stack;
@property UIScrollView *scroll;
@property NSTimer *timer;
@property CLLocationManager *permission;
@property NSDictionary *display;
@property TIONavTeleHUD *teleHUD;
@property TIONavSubtitleHUD *subtitleHUD;
@property NSDictionary *lastSubtitleDiagnostic;
@property NSDictionary *lastTeleDiagnostic;
@property NSString *note;
@property BOOL initialized,active,planning,simulated,fixture,hasDestination,gpsWeak,staleShown,rerouting;
@property NSUInteger generation,fixtureStep;
@property NSTimeInterval lastInfo;
@property CLLocationCoordinate2D destination;
@property UIView *mapHost;
@property NSLayoutConstraint *mapHeight;
@property UIStackView *routeCard,*lensCard;
@property UILabel *routeSummary,*briefLabel,*lensStatus,*mapHint;
@property UILabel *originHint;
@property UILabel *startLabel;
@property UIImageView *mapCrosshair;
@property UIButton *centerButton,*zoomInButton,*zoomOutButton;
@property UISegmentedControl *mapPickRole;
@property NSString *pendingMapAction,*simulationStartName;
@property BOOL hasSimulationStart;
@property UIButton *planButton,*beginButton,*lensButton,*stopButton,*searchButton;
@property UISegmentedControl *travelMode;
@property UISegmentedControl *transportMode;
@property NSInteger selectedTransport,sessionTransport;
@property BOOL routeReady,locating;
@property BOOL navigationStarted,backgroundLocationEnabled;
@property UIBackgroundTaskIdentifier navigationBackgroundTask;
@property NSUInteger backgroundEpoch;
@property NSString *destinationName;
@property CLLocationCoordinate2D simulationStart;
@property NSUInteger locationGeneration;

// Apple MapKit & Google Directions
@property MKMapView *map;
@property MKPointAnnotation *pin;
@property MKPointAnnotation *startPin;
@property MKPolyline *routeLine;
@property NSArray<NSDictionary *> *routeSteps;
@property NSInteger totalRouteDistance;
@property NSInteger totalRouteDuration;
@property NSUInteger currentStepIndex;
@property NSTimer *simTimer;
@property dispatch_source_t keepAliveTimer;
@end

@implementation TIONavigationPanel
- (UIButton *)button:(NSString *)title action:(SEL)action identifier:(NSString *)identifier{
    UIButton *b=[UIButton buttonWithType:UIButtonTypeSystem];
    b.configuration=[UIButtonConfiguration tintedButtonConfiguration];
    [b setTitle:title forState:UIControlStateNormal];
    b.accessibilityIdentifier=identifier;
    [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [self.stack addArrangedSubview:b];
    return b;
}

- (void)viewDidLoad{
    [super viewDidLoad];
    self.title=@"Navigation";
    self.view.backgroundColor=UIColor.systemGroupedBackgroundColor;
    self.note=@"Google Maps Directions & Apple MapKit. Search destination, plan route, then stream to RayNeo HUD.";
    self.teleHUD=[TIONavTeleHUD new];
    self.subtitleHUD=[TIONavSubtitleHUD new];
    self.scroll=[UIScrollView new];
    self.scroll.translatesAutoresizingMaskIntoConstraints=NO;
    [self.view addSubview:self.scroll];
    self.stack=[UIStackView new];
    self.stack.axis=UILayoutConstraintAxisVertical;
    self.stack.spacing=12;
    self.stack.translatesAutoresizingMaskIntoConstraints=NO;
    [self.scroll addSubview:self.stack];
    [NSLayoutConstraint activateConstraints:@[
        [self.scroll.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor],
        [self.scroll.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor],
        [self.scroll.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.scroll.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
        [self.stack.leadingAnchor constraintEqualToAnchor:self.scroll.contentLayoutGuide.leadingAnchor constant:16],
        [self.stack.trailingAnchor constraintEqualToAnchor:self.scroll.contentLayoutGuide.trailingAnchor constant:-16],
        [self.stack.topAnchor constraintEqualToAnchor:self.scroll.contentLayoutGuide.topAnchor constant:16],
        [self.stack.bottomAnchor constraintEqualToAnchor:self.scroll.contentLayoutGuide.bottomAnchor constant:-24],
        [self.stack.widthAnchor constraintEqualToAnchor:self.scroll.frameLayoutGuide.widthAnchor constant:-32]
    ]];
    self.statusLabel=[UILabel new];
    [self buildWorkspace];
    self.permission=[CLLocationManager new];
    self.permission.delegate=self;
    self.navigationBackgroundTask=UIBackgroundTaskInvalid;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refresh) name:@"TIONavigationChanged" object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(stopUser) name:@"TIOResearchClosed" object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(background) name:UIApplicationDidEnterBackgroundNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(navigationForeground) name:UIApplicationDidBecomeActiveNotification object:nil];
    self.display=TIONavDisplay(@"stopped",0,@"",-1,-1,-1,NO);
    [self refresh];
}

- (void)viewWillAppear:(BOOL)animated{
    [super viewWillAppear:animated];
    if(!self.timer){
        __weak typeof(self) weak=self;
        self.timer=[NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *t){
            [weak tick];
        }];
    }
    [self refresh];
}

- (void)viewDidDisappear:(BOOL)animated{
    [super viewDidDisappear:animated];
    self.pendingMapAction=nil;
    if(UIApplication.sharedApplication.applicationState!=UIApplicationStateActive&&!self.isMovingFromParentViewController&&!self.isBeingDismissed&&!self.navigationController.isBeingDismissed)return;
    [self stopUser];
    [self.timer invalidate];
    self.timer=nil;
    [self.simTimer invalidate];
    self.simTimer=nil;
}

- (void)dealloc{
    [self stopKeepAliveTimer];
    if(self.navigationBackgroundTask!=UIBackgroundTaskInvalid)[UIApplication.sharedApplication endBackgroundTask:self.navigationBackgroundTask];
    [self.simTimer invalidate];
    [self.subtitleHUD stop:@"Navigation UI dismissed"];
    [self.teleHUD stop:@"Navigation UI dismissed"];
    [self.timer invalidate];
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)refresh{
    if(!NSThread.isMainThread){
        dispatch_async(dispatch_get_main_queue(),^{[self refresh];});
        return;
    }
    NSDictionary *s=TIONavTransportStatus(),*tele=self.teleHUD.status;
    self.statusLabel.text=[NSString stringWithFormat:@"%@\nTeleprompter: %@ · %lu frames\nNotices: %@\nLink/Card: %@\nKey: %@ · Provider: Google Maps + MapKit",
        self.note?:@"",
        tele[@"note"],
        (unsigned long)[tele[@"frames"] unsignedIntegerValue],
        s[@"noticeNote"],
        s[@"note"],
        ReadNavKey().length?@"Configured (Google)":@"Default Key Active"];
    NSDictionary *sub=self.subtitleHUD.status;
    self.statusLabel.text=[NSString stringWithFormat:@"Subtitles: %@ · %lu frames\n%@\n%@",
        sub[@"note"],
        (unsigned long)[sub[@"frames"] unsignedIntegerValue],
        TIOSubtitleNavigationStatus()[@"note"],
        self.statusLabel.text];
    if(![sub isEqual:self.lastSubtitleDiagnostic]){
        self.lastSubtitleDiagnostic=sub;
        NSString *dir=[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/TurboIOResearch/subtitle-hud"];
        [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:@{NSFileProtectionKey:NSFileProtectionCompleteUntilFirstUserAuthentication} error:nil];
        NSMutableDictionary *report=[sub mutableCopy];
        report[@"time"]=@(NSDate.date.timeIntervalSince1970);
        [[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:nil] writeToFile:[dir stringByAppendingPathComponent:@"navigation.json"] options:NSDataWritingAtomic error:nil];
    }
    NSString *turnDist = [self.display[@"distance"] length] ?
        [NSString stringWithFormat:@"%@ · %@", self.display[@"turn"]?:@"", self.display[@"distance"]] :
        (self.display[@"turn"]?:@"");
    self.hudLabel.text=[NSString stringWithFormat:@"%@\n%@\n%@\n%@",
        self.display[@"mode"]?:@"",
        turnDist,
        self.display[@"road"]?:@"",
        self.display[@"summary"]?:@""];
    [self refreshWorkspace];
    if(![tele isEqual:self.lastTeleDiagnostic]){
        self.lastTeleDiagnostic=tele;
        NSString *dir=[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/TurboIOPrivateAddon"];
        [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil];
        NSMutableDictionary *d=[tele mutableCopy];
        d[@"time"]=@([NSDate.date timeIntervalSince1970]);
        NSString *p=[dir stringByAppendingPathComponent:@"navigation-tele-diagnostic.json"];
        [[NSJSONSerialization dataWithJSONObject:d options:0 error:nil] writeToFile:p options:NSDataWritingAtomic error:nil];
        [NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:p error:nil];
    }
}

- (void)startKeepAliveTimer{
    [self stopKeepAliveTimer];
    self.keepAliveTimer=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    if(!self.keepAliveTimer)return;
    dispatch_source_set_timer(self.keepAliveTimer, dispatch_time(DISPATCH_TIME_NOW, 3.5*NSEC_PER_SEC), 3.5*NSEC_PER_SEC, 0.5*NSEC_PER_SEC);
    __weak typeof(self) weak=self;
    dispatch_source_set_event_handler(self.keepAliveTimer, ^{
        [weak keepAliveTick];
    });
    dispatch_resume(self.keepAliveTimer);
}

- (void)stopKeepAliveTimer{
    if(self.keepAliveTimer){
        dispatch_source_cancel(self.keepAliveTimer);
        self.keepAliveTimer=nil;
    }
}

- (void)keepAliveTick{
    if(!self.navigationStarted&&!self.active)return;
    NSTimeInterval now=NSProcessInfo.processInfo.systemUptime;
    if(self.navigationStarted){
        self.lastInfo=now;
    }
    [self.subtitleHUD pumpAt:now];
}

- (void)setFrame:(NSDictionary *)frame{
    self.display=frame;
    TIONavOfferDisplay(frame);
    NSTimeInterval now=NSProcessInfo.processInfo.systemUptime;
    [self.teleHUD offer:frame at:now];
    [self.subtitleHUD offer:frame at:now];
    [self.subtitleHUD pumpAt:now];
    [self refresh];
}

- (void)tick{
    TIONavPump();
    if(self.navigationStarted){
        self.lastInfo=NSProcessInfo.processInfo.systemUptime;
    }
    [self.subtitleHUD pumpAt:NSProcessInfo.processInfo.systemUptime];
    [self.teleHUD pumpAt:NSProcessInfo.processInfo.systemUptime];
    [self refresh];
    if(self.fixture&&self.active){
        self.fixtureStep++;
        NSArray *icons=@[@9,@2,@3,@29,@15];
        NSUInteger i=MIN(self.fixtureStep/4,4);
        NSMutableDictionary *f=[TIONavDisplay(i==4?@"arrived":@"navigating",[icons[i] integerValue],@"Test Route",MAX(0,160-(NSInteger)self.fixtureStep*10),850,720,YES) mutableCopy];
        f[@"arrow"]=IconToArrow([icons[i] integerValue]);
        f[@"nextTurn"]=(i<3)?[NSString stringWithFormat:@"Then: %@ Regent St",IconToArrow([icons[i+1] integerValue])]:@"Then: 🏁 Arrive at destination";
        f[@"eta"]=@"ETA 17:45";
        f[@"modeEmoji"]=@"🚶";
        [self setFrame:f];
        if(i==4){
            self.fixture=NO;
            self.active=NO;
            self.note=@"Offline fixture ended; stop to clear card";
            [self refresh];
        }
    }
    if(self.active&&!self.routeReady&&!self.fixture&&!self.planning&&!self.staleShown&&NSProcessInfo.processInfo.systemUptime-self.lastInfo>300){
        self.staleShown=YES;
        [self setFrame:TIONavDisplay(@"stale",0,@"",-1,-1,-1,self.simulated)];
    }
}

- (void)alert:(NSString *)title message:(NSString *)message{
    UIAlertController *a=[UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)configureKey{
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Google Maps API Key" message:@"Preconfigured with project key. You can enter a custom Google Maps key to override." preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *f){
        f.placeholder=@"Google Maps API Key";
        f.text=ReadNavKey();
        f.autocorrectionType=UITextAutocorrectionTypeNo;
        f.autocapitalizationType=UITextAutocapitalizationTypeNone;
    }];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){
        NSString *txt=[a.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if(txt.length){
            self.note=WriteNavKey(txt)?@"Google Maps key saved":@"Save failed; check key format";
        }else{
            SecItemDelete((__bridge CFDictionaryRef)KeyQuery());
            self.note=@"Reset to default Google Maps key";
        }
        [self refresh];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)consent{
    [self openMap];
}

- (void)refreshConnection{
    TIONavRefreshConnection();
    [self refresh];
}

- (void)subtitleCheck{
    [self stopUser];
    [self.navigationController pushViewController:TIOSubtitleHUDController() animated:YES];
}

- (BOOL)canStartSubtitle{
    if(!self.active&&!self.navigationStarted&&!self.routeReady)return NO;
    if(self.planning||self.rerouting)return NO;
    return YES;
}

- (void)enableSubtitleHUD{
    if(!self.navigationStarted&&self.routeReady){
        [self beginRoute];
    }
    if(!self.navigationStarted&&!self.active){
        [self alert:@"Start Navigation First" message:@"Please tap 'Start Walking' or 'Start Simulation' before enabling glasses subtitles."];
        return;
    }
    if(![TIOSubtitleNavigationStatus()[@"available"] boolValue]){
        [self alert:@"Glasses Not Ready" message:@"Check glasses Bluetooth connection in the official app."];
        return;
    }
    TIOSubtitleConfirmIdle();
    BOOL started=[self.subtitleHUD startWithFrame:self.display at:NSProcessInfo.processInfo.systemUptime];
    if(started){
        [self.subtitleHUD pumpAt:NSProcessInfo.processInfo.systemUptime];
        [self startKeepAliveTimer];
        self.note=@"Glasses subtitles enabled. Streaming navigation.";
    }else{
        self.note=@"Could not start subtitle stream; check glasses connection.";
    }
    [self refresh];
    [self.scroll setContentOffset:CGPointZero animated:YES];
}

- (void)manualHUD{
    [self stopUser];
    [self.navigationController pushViewController:TIOManualHUDController() animated:YES];
}

- (void)stopSubtitlesForChannelSwitch{
    [self.subtitleHUD stop:@"Switching display channel"];
    TIOSubtitleConfirmIdle();
}

- (void)enableTeleHUD{
    [self stopSubtitlesForChannelSwitch];
    if(!self.active&&!self.navigationStarted&&!self.routeReady){
        [self alert:@"Start Navigation First" message:@"Please plan and start navigation before enabling teleprompter HUD."];
        return;
    }
    NSDictionary *s=TIONewsTeleStatus();
    if(![s[@"manualAvailable"] boolValue]){
        [self alert:@"Teleprompter Template Required" message:@"The RayNeo teleprompter engine requires capturing the official teleprompter template first.\n\nTip: Recommended mode for turn-by-turn navigation is Glasses Subtitles, which streams directly to your glasses without needing templates."];
        return;
    }
    TIONavEnableNotices(NO);
    TIONavEnableDisplay(NO);
    if([self.teleHUD enable]){
        [self.teleHUD offer:self.display at:NSProcessInfo.processInfo.systemUptime];
        [self.teleHUD pumpAt:NSProcessInfo.processInfo.systemUptime];
        self.note=@"Teleprompter navigation enabled.";
    }
    [self refresh];
    [self.scroll setContentOffset:CGPointZero animated:YES];
}

- (void)testNotice{
    [self stopSubtitlesForChannelSwitch];
    [self.teleHUD stop:@"Switch to notification test"];
    TIONavTestNotice();
    [self refresh];
    [self.scroll setContentOffset:CGPointZero animated:YES];
}

- (void)enableNotices{
    [self stopSubtitlesForChannelSwitch];
    [self.teleHUD stop:@"Switch to auto notifications"];
    TIONavEnableNotices(YES);
    TIONavOfferDisplay(self.display);
    TIONavPump();
    [self refresh];
    [self.scroll setContentOffset:CGPointZero animated:YES];
}

- (void)enableGlasses{
    [self stopSubtitlesForChannelSwitch];
    [self.teleHUD stop:@"Switch to dashboard card"];
    TIONavEnableDisplay(YES);
    TIONavOfferDisplay(self.display);
    TIONavPump();
    self.note=@"Navigation widget installed. Check glasses dashboard.";
    [self refresh];
}

- (void)halt{
    self.navigationStarted=NO;
    self.backgroundLocationEnabled=NO;
    [self stopKeepAliveTimer];
    [self endNavigationBackgroundTask];
    [self.simTimer invalidate];
    self.simTimer=nil;
    [self.subtitleHUD stop:@"Navigation stopped"];
    [self.teleHUD stop:@"Navigation stopped"];
    self.generation++;
    self.locationGeneration++;
    self.locating=NO;
    @try {
        self.permission.allowsBackgroundLocationUpdates=NO;
        self.permission.showsBackgroundLocationIndicator=NO;
    } @catch (NSException *e) {}
    [self.permission stopUpdatingLocation];
    self.routeReady=NO;
    self.active=NO;
    self.planning=NO;
    self.fixture=NO;
    self.rerouting=NO;
    if(self.map)self.map.showsUserLocation=NO;
}

- (void)stopUser{
    [self halt];
    TIONavEnableNotices(NO);
    self.note=@"Navigation stopped. Glasses subtitles require physical exit if active.";
    self.routeSummary.text=@"Navigation ended · Plan route again";
    self.display=TIONavDisplay(@"stopped",0,@"",-1,-1,-1,self.simulated);
    TIONavEnableDisplay(NO);
    [self refresh];
}

#include "NavigationBackground.inc"

- (void)startFixture{
    [self halt];
    self.active=YES;
    self.fixture=YES;
    self.simulated=YES;
    self.fixtureStep=0;
    self.note=@"Offline fixture: simulating turns without GPS";
    NSMutableDictionary *f=[TIONavDisplay(@"navigating",9,@"Test Road",160,850,720,YES) mutableCopy];
    f[@"arrow"]=@"⬆";
    f[@"nextTurn"]=@"Then: ↱ Regent St";
    f[@"eta"]=@"ETA 17:45";
    f[@"modeEmoji"]=@"🚶";
    [self setFrame:f];
}

- (void)startWalking{
    [self start:NO];
}

- (void)startSimulation{
    [self start:YES];
}

- (void)openMap{
    if(!self.initialized){
        self.initialized=YES;
        self.map=[MKMapView new];
        self.map.delegate=self;
        self.map.showsUserLocation=YES;
        self.map.translatesAutoresizingMaskIntoConstraints=NO;
        [self.mapHost insertSubview:self.map atIndex:0];
        [NSLayoutConstraint activateConstraints:@[
            [self.map.leadingAnchor constraintEqualToAnchor:self.mapHost.leadingAnchor],
            [self.map.trailingAnchor constraintEqualToAnchor:self.mapHost.trailingAnchor],
            [self.map.topAnchor constraintEqualToAnchor:self.mapHost.topAnchor],
            [self.map.bottomAnchor constraintEqualToAnchor:self.mapHost.bottomAnchor]
        ]];
        self.mapHint.hidden=YES;
        
        CLLocationCoordinate2D defaultCenter=CLLocationCoordinate2DMake(51.5074, -0.1278);
        if(self.permission.location){
            defaultCenter=self.permission.location.coordinate;
        }
        self.map.region=MKCoordinateRegionMakeWithDistance(defaultCenter, 3000, 3000);
        
        UITapGestureRecognizer *tap=[[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(handleMapTap:)];
        [self.map addGestureRecognizer:tap];
    }
    if(!self.hasSimulationStart){
        [self selectSimulationStart:self.map.centerCoordinate name:@"Default Simulation Start (London)"];
    }
    self.note=@"Map ready. Search destination or tap map to place pin.";
    [self refresh];
    [self continueMapAction:0];
}

- (void)handleMapTap:(UITapGestureRecognizer *)g{
    if(!self.map)return;
    CGPoint p=[g locationInView:self.map];
    CLLocationCoordinate2D c=[self.map convertPoint:p toCoordinateFromView:self.map];
    [self selectMapCoordinate:c];
}

- (MKOverlayRenderer *)mapView:(MKMapView *)mapView rendererForOverlay:(id<MKOverlay>)overlay{
    if([overlay isKindOfClass:MKPolyline.class]){
        MKPolylineRenderer *r=[[MKPolylineRenderer alloc]initWithPolyline:(MKPolyline *)overlay];
        r.lineWidth=6.0;
        r.strokeColor=UIColor.systemIndigoColor;
        return r;
    }
    return [MKOverlayRenderer new];
}

- (void)start:(BOOL)sim{
    if(!self.initialized)[self openMap];
    if(self.active||self.planning){
        [self alert:@"Please Stop Active Navigation First" message:@"Prevents asynchronous route callbacks from colliding."];
        return;
    }
    if(!self.hasDestination){
        [self alert:@"Choose Destination First" message:@"Search destination or tap map to place pin."];
        return;
    }
    CLLocationCoordinate2D origin;
    if(sim){
        if(!self.hasSimulationStart){
            [self alert:@"Choose Simulation Start" message:@"Switch map mode to 'Sim Start' above and tap map."];
            return;
        }
        CLLocation *a=[[CLLocation alloc]initWithLatitude:self.simulationStart.latitude longitude:self.simulationStart.longitude];
        CLLocation *b=[[CLLocation alloc]initWithLatitude:self.destination.latitude longitude:self.destination.longitude];
        if([a distanceFromLocation:b]<25){
            [self alert:@"Start and Destination Too Close" message:@"Must be at least 25 meters apart."];
            return;
        }
        origin=self.simulationStart;
    }else{
        CLAuthorizationStatus auth=self.permission.authorizationStatus;
        if(auth==kCLAuthorizationStatusNotDetermined){
            [self.permission requestWhenInUseAuthorization];
            self.note=@"After granting location access, please calculate live route again.";
            [self refresh];
            return;
        }
        if(auth==kCLAuthorizationStatusDenied||auth==kCLAuthorizationStatusRestricted){
            [self alert:@"Location Access Not Authorized" message:@"Please enable location in iOS Settings, or use simulated navigation."];
            return;
        }
        CLLocation *loc=self.permission.location;
        if(!loc){
            [self.permission startUpdatingLocation];
            self.note=@"Acquiring GPS fix for route calculation... please retry in a few seconds.";
            [self refresh];
            return;
        }
        origin=loc.coordinate;
    }
    
    self.active=YES;
    self.planning=YES;
    self.simulated=sim;
    self.fixture=NO;
    self.gpsWeak=NO;
    self.staleShown=NO;
    NSUInteger generation=++self.generation;
    self.sessionTransport=self.selectedTransport;
    
    self.note=[NSString stringWithFormat:@"Calculating %@ %@ route with Google Maps...",
        TIONavigationModeTitle(self.sessionTransport),
        sim?@"simulated":@"live"];
    [self setFrame:TIONavDisplay(@"planning",0,@"",-1,-1,-1,sim)];
    
    NSString *modeStr=@"walking";
    if(self.sessionTransport==1)modeStr=@"bicycling";
    else if(self.sessionTransport==2)modeStr=@"driving";
    
    NSString *apiKey=ReadNavKey();
    NSString *urlStr=[NSString stringWithFormat:@"https://maps.googleapis.com/maps/api/directions/json?origin=%.6f,%.6f&destination=%.6f,%.6f&mode=%@&key=%@",
        origin.latitude,origin.longitude,self.destination.latitude,self.destination.longitude,modeStr,apiKey];
    NSURL *url=[NSURL URLWithString:urlStr];
    
    __weak typeof(self) weak=self;
    NSURLSessionDataTask *task=[[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error){
        dispatch_async(dispatch_get_main_queue(),^{
            __strong typeof(weak) self=weak;
            if(!self||self.generation!=generation||!self.active)return;
            if(error){
                [self fail:[NSString stringWithFormat:@"Google Directions error: %@",error.localizedDescription]];
                return;
            }
            if(!data.length){
                [self fail:@"Empty response from Google Directions API"];
                return;
            }
            NSError *jsonErr=nil;
            NSDictionary *json=[NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonErr];
            NSString *status=json[@"status"];
            if(![status isEqualToString:@"OK"]){
                NSString *errMsg=json[@"error_message"]?:status;
                [self fail:[NSString stringWithFormat:@"Google Directions: %@",errMsg]];
                return;
            }
            NSArray *routes=json[@"routes"];
            if(!routes.count){
                [self fail:@"No routes found for destination."];
                return;
            }
            NSDictionary *route=routes.firstObject;
            NSArray *legs=route[@"legs"];
            if(!legs.count){
                [self fail:@"No route legs found."];
                return;
            }
            NSDictionary *leg=legs.firstObject;
            self.totalRouteDistance=[leg[@"distance"][@"value"] integerValue];
            self.totalRouteDuration=[leg[@"duration"][@"value"] integerValue];
            
            NSMutableArray<NSDictionary *> *steps=[NSMutableArray new];
            NSArray *rawSteps=leg[@"steps"];
            for(NSDictionary *rawStep in rawSteps){
                NSInteger dist=[rawStep[@"distance"][@"value"] integerValue];
                NSInteger dur=[rawStep[@"duration"][@"value"] integerValue];
                NSString *html=rawStep[@"html_instructions"]?:@"";
                NSString *maneuver=rawStep[@"maneuver"]?:@"";
                NSString *cleanRoad=StripHTML(html);
                NSInteger icon=ManeuverToIcon(maneuver,cleanRoad);
                double sLat=[rawStep[@"start_location"][@"lat"] doubleValue];
                double sLng=[rawStep[@"start_location"][@"lng"] doubleValue];
                double eLat=[rawStep[@"end_location"][@"lat"] doubleValue];
                double eLng=[rawStep[@"end_location"][@"lng"] doubleValue];
                [steps addObject:@{
                    @"icon":@(icon),
                    @"road":cleanRoad,
                    @"distance":@(dist),
                    @"duration":@(dur),
                    @"startLat":@(sLat),
                    @"startLng":@(sLng),
                    @"endLat":@(eLat),
                    @"endLng":@(eLng)
                }];
            }
            self.routeSteps=steps;
            
            NSString *polyPoints=route[@"overview_polyline"][@"points"];
            if(polyPoints.length){
                [self drawGooglePolyline:polyPoints];
            }
            
            self.planning=NO;
            self.routeReady=YES;
            self.lastInfo=NSProcessInfo.processInfo.systemUptime;
            self.staleShown=NO;
            self.note=@"Route ready with Google Maps. Tap Start to begin.";
            self.routeSummary.text=[NSString stringWithFormat:@"%.1f km   ·   approx %ld min",
                self.totalRouteDistance/1000.0,
                (long)MAX(1,(self.totalRouteDuration+59)/60)];
            self.display=TIONavDisplay(@"ready",0,@"",-1,self.totalRouteDistance,self.totalRouteDuration,self.simulated);
            [self refresh];
        });
    }];
    [task resume];
}

- (void)fail:(NSString *)message{
    [self halt];
    self.note=message;
    [self setFrame:TIONavDisplay(@"error",0,@"",-1,-1,-1,self.simulated)];
}

- (void)drawGooglePolyline:(NSString *)encoded{
    NSArray<NSValue *> *coordsVal=DecodeGooglePolyline(encoded);
    if(coordsVal.count<2)return;
    CLLocationCoordinate2D *coords=malloc(sizeof(CLLocationCoordinate2D)*coordsVal.count);
    for(NSUInteger i=0;i<coordsVal.count;i++){
        [coordsVal[i] getValue:&coords[i]];
    }
    if(self.routeLine){
        [self.map removeOverlay:self.routeLine];
        self.routeLine=nil;
    }
    self.routeLine=[MKPolyline polylineWithCoordinates:coords count:coordsVal.count];
    free(coords);
    [self.map addOverlay:self.routeLine];
    [self.map setVisibleMapRect:self.routeLine.boundingMapRect edgePadding:UIEdgeInsetsMake(35,30,35,30) animated:YES];
}

- (void)beginRoute{
    if(!self.routeReady||!self.routeSteps.count)return;
    if(UIApplication.sharedApplication.applicationState!=UIApplicationStateActive){
        [self alert:@"Start in Foreground" message:@"New navigation sessions cannot start from the background."];
        return;
    }
    if(!self.simulated&&![self navigationLocationAuthorized]){
        [self alert:@"Location Permission Required" message:@"Please grant location permission to use live GPS navigation."];
        return;
    }
    self.routeReady=NO;
    self.navigationStarted=YES;
    self.currentStepIndex=0;
    self.lastInfo=NSProcessInfo.processInfo.systemUptime;
    self.backgroundLocationEnabled=!self.simulated&&[self navigationLocationModeAvailable]&&[self navigationLocationAuthorized];
    
    if(self.simulated){
        self.note=@"Simulation started. You can toggle glasses HUD separately.";
        [self startSimProgress];
    }else{
        self.note=self.backgroundLocationEnabled?
            @"Live navigation started; background and lock screen supported. Keep app running.":
            @"Live navigation started; running in foreground.";
        if(self.backgroundLocationEnabled){
            @try {
                self.permission.allowsBackgroundLocationUpdates=YES;
                self.permission.pausesLocationUpdatesAutomatically=NO;
                self.permission.showsBackgroundLocationIndicator=YES;
            } @catch (NSException *e) {}
        }
        self.permission.distanceFilter=kCLDistanceFilterNone;
        self.permission.desiredAccuracy=kCLLocationAccuracyBestForNavigation;
        self.permission.activityType=(self.selectedTransport==2)?CLActivityTypeAutomotiveNavigation:CLActivityTypeFitness;
        [self.permission startUpdatingLocation];
        self.map.showsUserLocation=YES;
        [self updateStepFrame:0];
    }
    [self startKeepAliveTimer];
    if(![self.subtitleHUD.status[@"enabled"] boolValue]&&[TIOSubtitleNavigationStatus()[@"available"] boolValue]){
        TIOSubtitleConfirmIdle();
        if([self.subtitleHUD startWithFrame:self.display at:NSProcessInfo.processInfo.systemUptime]){
            [self.subtitleHUD pumpAt:NSProcessInfo.processInfo.systemUptime];
        }
    }
    [self refresh];
}

- (void)startSimProgress{
    [self.simTimer invalidate];
    self.simTimer=nil;
    [self updateStepFrame:0];
    __weak typeof(self) weak=self;
    self.simTimer=[NSTimer scheduledTimerWithTimeInterval:5.0 repeats:YES block:^(NSTimer *t){
        [weak simStepTick];
    }];
}

- (void)simStepTick{
    if(!self.navigationStarted||!self.simulated){
        [self.simTimer invalidate];
        self.simTimer=nil;
        return;
    }
    self.currentStepIndex++;
    if(self.currentStepIndex>=self.routeSteps.count){
        [self.simTimer invalidate];
        self.simTimer=nil;
        [self userArrived];
        return;
    }
    [self updateStepFrame:self.currentStepIndex];
}

- (void)updateStepFrame:(NSUInteger)stepIdx{
    if(stepIdx>=self.routeSteps.count)return;
    NSDictionary *step=self.routeSteps[stepIdx];
    NSInteger icon=[step[@"icon"] integerValue];
    NSString *road=step[@"road"]?:@"";
    NSInteger dist=[step[@"distance"] integerValue];
    
    NSInteger remainDist=0;
    NSInteger remainTime=0;
    for(NSUInteger j=stepIdx;j<self.routeSteps.count;j++){
        remainDist+=[self.routeSteps[j][@"distance"] integerValue];
        remainTime+=[self.routeSteps[j][@"duration"] integerValue];
    }
    
    self.lastInfo=NSProcessInfo.processInfo.systemUptime;
    self.staleShown=NO;
    
    double lat=[step[@"startLat"] doubleValue];
    double lng=[step[@"startLng"] doubleValue];
    if(lat!=0&&lng!=0){
        [self.map setCenterCoordinate:CLLocationCoordinate2DMake(lat,lng) animated:YES];
    }
    
    NSMutableDictionary *frame=[TIONavDisplay(@"navigating",icon,road,dist,remainDist,remainTime,self.simulated) mutableCopy];
    frame[@"segment"]=@(stepIdx);
    frame[@"arrow"]=IconToArrow(icon);
    
    NSUInteger nextIdx=stepIdx+1;
    if(nextIdx<self.routeSteps.count){
        NSDictionary *nextStep=self.routeSteps[nextIdx];
        NSInteger nextIcon=[nextStep[@"icon"] integerValue];
        NSString *nextRoad=CleanRoad(nextStep[@"road"]?:@"");
        frame[@"nextTurn"]=[NSString stringWithFormat:@"Then: %@ %@", IconToArrow(nextIcon), nextRoad];
    }else{
        frame[@"nextTurn"]=@"Then: 🏁 Arrive at destination";
    }
    
    NSDate *etaDate=[NSDate dateWithTimeIntervalSinceNow:remainTime];
    NSDateFormatter *df=[NSDateFormatter new];
    df.dateFormat=@"HH:mm";
    frame[@"eta"]=[NSString stringWithFormat:@"ETA %@", [df stringFromDate:etaDate]];
    
    NSString *em=self.selectedTransport==1?@"🚴":(self.selectedTransport==2?@"🚗":@"🚶");
    frame[@"modeEmoji"]=em;
    
    [self setFrame:frame];
}

- (void)userArrived{
    [self halt];
    self.note=@"Arrived at destination. Navigation completed.";
    [self setFrame:TIONavDisplay(@"arrived",15,@"Arrived at destination",0,0,0,self.simulated)];
    NSUInteger g=self.generation;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,10*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        if(g==self.generation)TIONavEnableDisplay(NO);
    });
}

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations{
    CLLocation *loc=locations.lastObject;
    if(!loc)return;
    if(self.locating){
        self.locating=NO;
        [self.map setCenterCoordinate:loc.coordinate animated:YES];
        if(self.travelMode.selectedSegmentIndex==0)[self selectSimulationStart:loc.coordinate name:@"Current Location"];
        self.note=@"Location acquired.";
        [self refresh];
    }
    if(self.navigationStarted&&!self.simulated){
        [self updateLiveLocation:loc];
    }
}

- (void)updateLiveLocation:(CLLocation *)loc{
    if(!self.navigationStarted||self.simulated||!self.routeSteps.count)return;
    if(self.currentStepIndex>=self.routeSteps.count){
        [self userArrived];
        return;
    }
    NSDictionary *step=self.routeSteps[self.currentStepIndex];
    double endLat=[step[@"endLat"] doubleValue];
    double endLng=[step[@"endLng"] doubleValue];
    CLLocation *stepEnd=[[CLLocation alloc]initWithLatitude:endLat longitude:endLng];
    CLLocationDistance distToTurn=[loc distanceFromLocation:stepEnd];
    
    if(distToTurn<25.0){
        self.currentStepIndex++;
        if(self.currentStepIndex>=self.routeSteps.count){
            [self userArrived];
            return;
        }
        step=self.routeSteps[self.currentStepIndex];
        endLat=[step[@"endLat"] doubleValue];
        endLng=[step[@"endLng"] doubleValue];
        stepEnd=[[CLLocation alloc]initWithLatitude:endLat longitude:endLng];
        distToTurn=[loc distanceFromLocation:stepEnd];
    }
    
    NSInteger icon=[step[@"icon"] integerValue];
    NSString *road=step[@"road"]?:@"";
    
    NSInteger remainDist=(NSInteger)distToTurn;
    NSInteger remainTime=0;
    for(NSUInteger j=self.currentStepIndex+1;j<self.routeSteps.count;j++){
        remainDist+=[self.routeSteps[j][@"distance"] integerValue];
        remainTime+=[self.routeSteps[j][@"duration"] integerValue];
    }
    remainTime+=(NSInteger)(distToTurn/1.4);
    
    self.lastInfo=NSProcessInfo.processInfo.systemUptime;
    self.staleShown=NO;
    [self.map setCenterCoordinate:loc.coordinate animated:YES];
    
    NSMutableDictionary *frame=[TIONavDisplay(@"navigating",icon,road,(NSInteger)distToTurn,remainDist,remainTime,NO) mutableCopy];
    frame[@"segment"]=@(self.currentStepIndex);
    frame[@"arrow"]=IconToArrow(icon);
    
    NSUInteger nextIdx=self.currentStepIndex+1;
    if(nextIdx<self.routeSteps.count){
        NSDictionary *nextStep=self.routeSteps[nextIdx];
        NSInteger nextIcon=[nextStep[@"icon"] integerValue];
        NSString *nextRoad=CleanRoad(nextStep[@"road"]?:@"");
        frame[@"nextTurn"]=[NSString stringWithFormat:@"Then: %@ %@", IconToArrow(nextIcon), nextRoad];
    }else{
        frame[@"nextTurn"]=@"Then: 🏁 Arrive at destination";
    }
    
    NSDate *etaDate=[NSDate dateWithTimeIntervalSinceNow:remainTime];
    NSDateFormatter *df=[NSDateFormatter new];
    df.dateFormat=@"HH:mm";
    frame[@"eta"]=[NSString stringWithFormat:@"ETA %@", [df stringFromDate:etaDate]];
    
    NSString *em=self.selectedTransport==1?@"🚴":(self.selectedTransport==2?@"🚗":@"🚶");
    frame[@"modeEmoji"]=em;
    
    [self setFrame:frame];
}

#include "NavigationWorkspace.inc"
@end
UIViewController *TIONavigationController(void){return [TIONavigationPanel new];}
