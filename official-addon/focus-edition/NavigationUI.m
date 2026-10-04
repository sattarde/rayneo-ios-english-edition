#import "NavigationUI.h"
#import "ResearchUI.h"
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
#import "NavigationRoadNetwork.h"
#import "NavigationRoadNetwork.inc"
#import <CoreLocation/CoreLocation.h>
#import <MapKit/MapKit.h>
#import <Security/Security.h>
#include <math.h>
#if TIO_DISPLAY_PHONE
#import "DisplayPhoneUI.h"
#import "NativeNavigationUI.h"
#import "NativeNavigation.h"
#import "DisplayHUDRenderer.h"
#endif

static NSInteger IconForStep(MKRouteStep *step){
    if(!step) return 9;
    NSString *inst=step.instructions.lowercaseString?:@"";
    if([inst containsString:@"arrive"]||[inst containsString:@"destination"]) return 15;
    if([inst containsString:@"roundabout"]) return 11;
    if([inst containsString:@"u-turn"]) return 8;
    if([inst containsString:@"sharp left"]) return 6;
    if([inst containsString:@"sharp right"]) return 7;
    if([inst containsString:@"slight left"]||[inst containsString:@"bear left"]) return 4;
    if([inst containsString:@"slight right"]||[inst containsString:@"bear right"]) return 5;
    if([inst containsString:@"left"]) return 2;
    if([inst containsString:@"right"]) return 3;
    return 9;
}

@interface TIONavigationPanel:UIViewController<CLLocationManagerDelegate,MKMapViewDelegate>
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
@property BOOL showLegacyDisplay;
@property NSMutableArray<UIView *> *legacyDisplayViews;
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
@property MKMapView *map;
@property MKPointAnnotation *pin;
@property MKPointAnnotation *startPin;
@property MKPolyline *routeLine;
@property MKRoute *currentRoute;
@property NSArray<MKRouteStep *> *routeSteps;
@property NSUInteger currentStepIndex;
@property NSUInteger currentPointIndex;
@property NSArray<CLLocation *> *allRoutePoints;
@property NSTimer *simTimer;
@property dispatch_source_t simDispatchTimer;
@property NSArray *cachedNavPoints;
@property NSUInteger lastMiniMapPtIdx, lastMiniMapStepIdx;
@property CLLocationCoordinate2D lastMapUserCoord;
@property double lastMapHeading;
@property NSArray *cachedMapRoads;
@property NSArray *cachedLocalCoords;
@property NSArray *cachedManeuverCoord;
#if TIO_DISPLAY_PHONE
@property UIButton *tdpButton;
@property UILabel *tdpStatus;
@property UIImageView *tdpPreview;
@property NSData *hudIconPixels,*crossPixels;
@property NSInteger hudIconType;
@property NSTimeInterval crossReceived;
@property NSUInteger crossReceivedCount,iconReceivedCount;
#endif
@end

@implementation TIONavigationPanel
- (UIButton *)button:(NSString *)title action:(SEL)action identifier:(NSString *)identifier{
    UIButton *b=[UIButton buttonWithType:UIButtonTypeSystem];b.configuration=[UIButtonConfiguration tintedButtonConfiguration];[b setTitle:title forState:UIControlStateNormal];b.accessibilityIdentifier=identifier;[b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];[self.stack addArrangedSubview:b];return b;
}
- (void)viewDidLoad{
    [super viewDidLoad];self.title=@"Navigation HUD";self.view.backgroundColor=TIOPaper();self.view.tintColor=TIOAccent();self.note=@"Apple MapKit navigation with glasses HUD. Select a destination or tap the map to begin.";self.teleHUD=[TIONavTeleHUD new];self.subtitleHUD=[TIONavSubtitleHUD new];
    self.scroll=[UIScrollView new];self.scroll.translatesAutoresizingMaskIntoConstraints=NO;[self.view addSubview:self.scroll];
    self.stack=[UIStackView new];self.stack.axis=UILayoutConstraintAxisVertical;self.stack.spacing=12;self.stack.translatesAutoresizingMaskIntoConstraints=NO;[self.scroll addSubview:self.stack];
    [NSLayoutConstraint activateConstraints:@[[self.scroll.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor],[self.scroll.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor],[self.scroll.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],[self.scroll.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],[self.stack.leadingAnchor constraintEqualToAnchor:self.scroll.contentLayoutGuide.leadingAnchor constant:16],[self.stack.trailingAnchor constraintEqualToAnchor:self.scroll.contentLayoutGuide.trailingAnchor constant:-16],[self.stack.topAnchor constraintEqualToAnchor:self.scroll.contentLayoutGuide.topAnchor constant:16],[self.stack.bottomAnchor constraintEqualToAnchor:self.scroll.contentLayoutGuide.bottomAnchor constant:-24],[self.stack.widthAnchor constraintEqualToAnchor:self.scroll.frameLayoutGuide.widthAnchor constant:-32]]];
    self.statusLabel=[UILabel new];
    [self buildWorkspace];
    self.permission=[CLLocationManager new];self.permission.delegate=self;self.navigationBackgroundTask=UIBackgroundTaskInvalid;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refresh) name:@"TIONavigationChanged" object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(stopUser) name:@"TIOResearchClosed" object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(background) name:UIApplicationDidEnterBackgroundNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(background) name:UIApplicationWillResignActiveNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(navigationForeground) name:UIApplicationDidBecomeActiveNotification object:nil];
    self.display=TIONavDisplay(@"stopped",0,@"",-1,-1,-1,NO);[self refresh];
}
- (void)viewWillAppear:(BOOL)animated{
    [super viewWillAppear:animated];
    if(!self.timer){
        __weak typeof(self) weak=self;
        self.timer=[NSTimer timerWithTimeInterval:1 repeats:YES block:^(NSTimer *t){[weak tick];}];
        [[NSRunLoop mainRunLoop] addTimer:self.timer forMode:NSRunLoopCommonModes];
    }
    [self refresh];
}
- (void)viewDidDisappear:(BOOL)animated{
    [super viewDidDisappear:animated];self.pendingMapAction=nil;
    if(UIApplication.sharedApplication.applicationState!=UIApplicationStateActive&&!self.isMovingFromParentViewController&&!self.isBeingDismissed&&!self.navigationController.isBeingDismissed)return;
    [self stopUser];[self.timer invalidate];self.timer=nil;
}
- (void)dealloc{
    if(self.navigationBackgroundTask!=UIBackgroundTaskInvalid)[UIApplication.sharedApplication endBackgroundTask:self.navigationBackgroundTask];
    [self.subtitleHUD stop:@"Navigation page has been destroyed"];[self.teleHUD stop:@"Navigation page has been destroyed"];
    if(self.simDispatchTimer){dispatch_source_cancel(self.simDispatchTimer);self.simDispatchTimer=nil;}
    [self.timer invalidate];[self.simTimer invalidate];
    [NSNotificationCenter.defaultCenter removeObserver:self];
}
- (void)refresh{
    if(!NSThread.isMainThread){dispatch_async(dispatch_get_main_queue(),^{[self refresh];});return;}
    NSDictionary *s=TIONavTransportStatus();
    self.statusLabel.text=[NSString stringWithFormat:@"%@\nMapKit Engine · Glasses Stream Ready\nNotification: %@\nConnection: %@",self.note?:@"",s[@"noticeNote"]?:@"",s[@"note"]?:@""];
    self.hudLabel.text=[NSString stringWithFormat:@"%@\n\n%@  %@\n%@\n%@",self.display[@"mode"]?:@"",self.display[@"turn"]?:@"",self.display[@"distance"]?:@"",self.display[@"road"]?:@"",self.display[@"summary"]?:@""];
    [self refreshWorkspace];
}
- (void)setFrame:(NSDictionary *)frame{
    self.display=frame;TIONavOfferDisplay(frame);
    [self.teleHUD offer:frame at:NSProcessInfo.processInfo.systemUptime];
    [self.subtitleHUD offer:frame at:NSProcessInfo.processInfo.systemUptime];
#if TIO_DISPLAY_PHONE
    TDPPhoneNavigationOffer([self displayHUDFrame]);[self refreshDisplayHUD];
#endif
    [self refresh];
}
- (void)tick{
#if TIO_DISPLAY_PHONE
    TDPPhoneNavigationPump();[self refreshDisplayHUD];
#endif
    TIONavPump();[self.subtitleHUD pumpAt:NSProcessInfo.processInfo.systemUptime];[self.teleHUD pumpAt:NSProcessInfo.processInfo.systemUptime];
    if(self.fixture&&self.active){
        self.fixtureStep++;NSArray *icons=@[@9,@2,@3,@4,@15];NSUInteger i=MIN(self.fixtureStep/4,4);
        [self setFrame:TIONavDisplay(i==4?@"arrived":@"navigating",[icons[i] integerValue],@"Simulated Street",MAX(0,160-(NSInteger)self.fixtureStep*10),850,720,YES)];
        if(i==4){self.fixture=NO;self.active=NO;self.note=@"Offline fixture finished";[self refresh];}
    }
}
- (void)alert:(NSString *)title message:(NSString *)message{
    UIAlertController *a=[UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}
- (void)consent{[self openMap];}
- (void)openMap{
    if(!self.initialized){
        self.initialized=YES;
        self.map=[MKMapView new];self.map.delegate=self;self.map.showsUserLocation=YES;self.map.translatesAutoresizingMaskIntoConstraints=NO;
        UITapGestureRecognizer *tap=[[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(mapTapped:)];
        [self.map addGestureRecognizer:tap];
        [self.mapHost insertSubview:self.map atIndex:0];
        [NSLayoutConstraint activateConstraints:@[
            [self.map.leadingAnchor constraintEqualToAnchor:self.mapHost.leadingAnchor],
            [self.map.trailingAnchor constraintEqualToAnchor:self.mapHost.trailingAnchor],
            [self.map.topAnchor constraintEqualToAnchor:self.mapHost.topAnchor],
            [self.map.bottomAnchor constraintEqualToAnchor:self.mapHost.bottomAnchor]
        ]];
        self.mapHint.hidden=YES;
        [self.permission requestWhenInUseAuthorization];
        [self.permission startUpdatingLocation];
        [self.permission startUpdatingHeading];
        if(self.permission.location){
            [self.map setRegion:MKCoordinateRegionMakeWithDistance(self.permission.location.coordinate,1500,1500) animated:NO];
            [self selectSimulationStart:self.permission.location.coordinate name:@"Current Location"];
        }
    }
    self.note=@"MapKit ready. Tap map or search to choose destination.";
    [self refresh];[self continueMapAction:0];
}
- (void)mapTapped:(UITapGestureRecognizer *)g{
    if(g.state!=UIGestureRecognizerStateEnded)return;
    CGPoint pt=[g locationInView:self.map];
    CLLocationCoordinate2D c=[self.map convertPoint:pt toCoordinateFromView:self.map];
    [self selectMapCoordinate:c];
}
- (void)planRoute{
    if(!self.initialized){[self openMap];return;}
    if(!self.hasDestination){[self alert:@"Choose Destination First" message:@"Search for a location or tap on the map to drop a pin."];return;}
    
    CLLocationCoordinate2D startCoord;
    if(self.permission.location&&TIONavCoordinate(self.permission.location.coordinate.latitude,self.permission.location.coordinate.longitude)){
        // Real GPS is available — always use current real location as start!
        startCoord=self.permission.location.coordinate;
    }else if(self.hasSimulationStart&&TIONavCoordinate(self.simulationStart.latitude,self.simulationStart.longitude)){
        // Verify custom simulation start is in the same region (<150km)
        CLLocation *sLoc=[[CLLocation alloc]initWithLatitude:self.simulationStart.latitude longitude:self.simulationStart.longitude];
        CLLocation *dLoc=[[CLLocation alloc]initWithLatitude:self.destination.latitude longitude:self.destination.longitude];
        if([sLoc distanceFromLocation:dLoc]<150000.0){
            startCoord=self.simulationStart;
        }else{
            startCoord=CLLocationCoordinate2DMake(self.destination.latitude+0.006,self.destination.longitude+0.006);
            [self selectSimulationStart:startCoord name:@"Sim Start (~800m)"];
        }
    }else{
        // No GPS and no custom start — offset by ~800m from destination
        startCoord=CLLocationCoordinate2DMake(self.destination.latitude+0.006,self.destination.longitude+0.006);
        [self selectSimulationStart:startCoord name:@"Sim Start (~800m)"];
    }
    
    // Safety check: if start is too close to destination (<50m), offset it slightly
    CLLocation *sLoc=[[CLLocation alloc]initWithLatitude:startCoord.latitude longitude:startCoord.longitude];
    CLLocation *dLoc=[[CLLocation alloc]initWithLatitude:self.destination.latitude longitude:self.destination.longitude];
    if([sLoc distanceFromLocation:dLoc]<50.0){
        startCoord=CLLocationCoordinate2DMake(self.destination.latitude+0.006,self.destination.longitude+0.006);
        [self selectSimulationStart:startCoord name:@"Sim Start (~800m)"];
    }
    
    self.planning=YES;self.routeReady=NO;self.active=YES;self.simulated=(self.travelMode.selectedSegmentIndex==0);
    self.note=@"Calculating route with Apple MapKit…";
    [self setFrame:TIONavDisplay(@"planning",0,@"",-1,-1,-1,self.simulated)];[self refresh];
    
    MKDirectionsRequest *req=[MKDirectionsRequest new];
    req.source=[[MKMapItem alloc]initWithPlacemark:[[MKPlacemark alloc]initWithCoordinate:startCoord]];
    req.destination=[[MKMapItem alloc]initWithPlacemark:[[MKPlacemark alloc]initWithCoordinate:self.destination]];
    if(self.selectedTransport==TIONavigationDrive) req.transportType=MKDirectionsTransportTypeAutomobile;
    else if(self.selectedTransport==TIONavigationRide){
        if(@available(iOS 14.0, *)) req.transportType=MKDirectionsTransportTypeCycling;
        else req.transportType=MKDirectionsTransportTypeWalking;
    } else req.transportType=MKDirectionsTransportTypeWalking;
    
    MKDirections *dir=[[MKDirections alloc]initWithRequest:req];__weak typeof(self) weak=self;
    [dir calculateDirectionsWithCompletionHandler:^(MKDirectionsResponse *res,NSError *err){
        dispatch_async(dispatch_get_main_queue(),^{
            TIONavigationPanel *s=weak;if(!s)return;
            if((err||!res.routes.count)&&s.selectedTransport==TIONavigationRide&&req.transportType!=MKDirectionsTransportTypeWalking){
                // Cycling directions may be unsupported in this region; fall back to walking route
                MKDirectionsRequest *fallback=[MKDirectionsRequest new];
                fallback.source=req.source;fallback.destination=req.destination;
                fallback.transportType=MKDirectionsTransportTypeWalking;
                MKDirections *fbDir=[[MKDirections alloc]initWithRequest:fallback];
                [fbDir calculateDirectionsWithCompletionHandler:^(MKDirectionsResponse *fbRes,NSError *fbErr){
                    dispatch_async(dispatch_get_main_queue(),^{
                        TIONavigationPanel *s2=weak;if(!s2)return;
                        s2.planning=NO;
                        if(fbErr||!fbRes.routes.count){
                            [s2 fail:fbErr?[NSString stringWithFormat:@"Route calculation failed: %@",fbErr.localizedDescription]:@"No route found between these locations."];
                            return;
                        }
                        s2.note=@"Cycling unavailable in this area; walking route loaded.";
                        [s2 applyCalculatedRoute:fbRes.routes.firstObject];
                    });
                }];
                return;
            }
            s.planning=NO;
            if(err||!res.routes.count){
                [s fail:err?[NSString stringWithFormat:@"Route calculation failed: %@",err.localizedDescription]:@"No route found between these locations."];
                return;
            }
            [s applyCalculatedRoute:res.routes.firstObject];
        });
    }];
}
- (void)applyCalculatedRoute:(MKRoute *)route{
    self.currentRoute=route;self.routeSteps=route.steps;self.currentStepIndex=0;self.currentPointIndex=0;self.routeReady=YES;
    
    // Extract and densify route points to ~20 meter spacing for smooth simulation
    NSUInteger count=route.polyline.pointCount;
    CLLocationCoordinate2D *coords=malloc(sizeof(CLLocationCoordinate2D)*count);
    [route.polyline getCoordinates:coords range:NSMakeRange(0,count)];
    NSMutableArray *pts=[NSMutableArray new];
    for(NSUInteger i=0;i<count;i++){
        CLLocation *curr=[[CLLocation alloc]initWithLatitude:coords[i].latitude longitude:coords[i].longitude];
        if(pts.count>0){
            CLLocation *prev=pts.lastObject;
            CLLocationDistance d=[curr distanceFromLocation:prev];
            if(d>25.0){
                NSUInteger steps=(NSUInteger)ceil(d/20.0);
                for(NSUInteger sub=1;sub<steps;sub++){
                    double f=(double)sub/(double)steps;
                    double lat=prev.coordinate.latitude+(curr.coordinate.latitude-prev.coordinate.latitude)*f;
                    double lon=prev.coordinate.longitude+(curr.coordinate.longitude-prev.coordinate.longitude)*f;
                    [pts addObject:[[CLLocation alloc]initWithLatitude:lat longitude:lon]];
                }
            }
        }
        [pts addObject:curr];
    }
    free(coords);
    self.allRoutePoints=pts;
    
    if(self.routeLine)[self.map removeOverlay:self.routeLine];
    self.routeLine=route.polyline;
    [self.map addOverlay:self.routeLine];
    [self.map setVisibleMapRect:route.polyline.boundingMapRect edgePadding:UIEdgeInsetsMake(40,40,40,40) animated:YES];
    self.routeSummary.text=[NSString stringWithFormat:@"%.1f km · %ld min via %@",route.distance/1000.0,(long)ceil(route.expectedTravelTime/60.0),route.name.length?route.name:@"Fastest Route"];
    
    if(self.simulated){
        // In simulation mode, immediately start movement!
        [self beginRoute];
    }else{
        self.note=self.note?:@"Route calculated. Tap 'Start Navigation' to follow live GPS.";
        [self updateTelemetryForLocation:pts.firstObject pointIndex:0];
        [self refresh];
    }
}
- (void)beginRoute{
    if(!self.routeReady||!self.allRoutePoints.count){
        [self planRoute];
        return;
    }
    self.routeReady=NO;self.active=YES;self.navigationStarted=YES;self.lastInfo=NSProcessInfo.processInfo.systemUptime;
    self.backgroundLocationEnabled=YES;
    
    @try {
        self.permission.desiredAccuracy=kCLLocationAccuracyBestForNavigation;
        self.permission.distanceFilter=kCLDistanceFilterNone;
        self.permission.activityType=CLActivityTypeAutomotiveNavigation;
        self.permission.allowsBackgroundLocationUpdates=YES;
        self.permission.pausesLocationUpdatesAutomatically=NO;
        if(@available(iOS 11.0, *)){
            self.permission.showsBackgroundLocationIndicator=YES;
        }
    } @catch(NSException *e){}
    
    UIApplication.sharedApplication.idleTimerDisabled=YES;
    [self.permission startUpdatingLocation];
    
    if(self.simulated){
        self.note=@"Simulation active. Glasses HUD streams turn-by-turn.";
        [self startSimulationTimer];
    }else{
        self.note=@"Live navigation active. Following phone GPS.";
    }
    [self refresh];
}
- (void)startSimulationTimer{
    [self.simTimer invalidate];self.simTimer=nil;
    if(self.simDispatchTimer){dispatch_source_cancel(self.simDispatchTimer);self.simDispatchTimer=nil;}
    self.currentPointIndex=0;self.currentStepIndex=0;__weak typeof(self) weak=self;
    
    self.simDispatchTimer=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_main_queue());
    dispatch_source_set_timer(self.simDispatchTimer,dispatch_time(DISPATCH_TIME_NOW,800*NSEC_PER_MSEC),800*NSEC_PER_MSEC,50*NSEC_PER_MSEC);
    dispatch_source_set_event_handler(self.simDispatchTimer,^{
        [weak simTick];
    });
    dispatch_resume(self.simDispatchTimer);
    
    self.simTimer=[NSTimer timerWithTimeInterval:0.8 repeats:YES block:^(NSTimer *t){[weak simTick];}];
    [[NSRunLoop mainRunLoop] addTimer:self.simTimer forMode:NSRunLoopCommonModes];
}
- (void)simTick{
    if(!self.active||!self.allRoutePoints.count){
        if(self.simDispatchTimer){dispatch_source_cancel(self.simDispatchTimer);self.simDispatchTimer=nil;}
        [self.simTimer invalidate];self.simTimer=nil;return;
    }
    if(self.currentPointIndex<self.allRoutePoints.count-1){
        self.currentPointIndex++;
    }else{
        if(self.simDispatchTimer){dispatch_source_cancel(self.simDispatchTimer);self.simDispatchTimer=nil;}
        [self.simTimer invalidate];self.simTimer=nil;
        [self setFrame:TIONavDisplay(@"arrived",15,@"Destination",0,0,0,YES)];
        self.note=@"Arrived at destination!";[self refresh];return;
    }
    CLLocation *curr=self.allRoutePoints[self.currentPointIndex];
    [self updateTelemetryForLocation:curr pointIndex:self.currentPointIndex];
}
- (NSArray *)localCoordinatesFromIndex:(NSUInteger)idx maxDistance:(double)maxDist{
    if(!self.allRoutePoints.count)return @[];
    NSMutableArray *out=[NSMutableArray new];double acc=0;
    NSUInteger start = (idx >= 3) ? (idx - 3) : 0;
    CLLocation *prev=self.allRoutePoints[start];
    [out addObject:@[@(prev.coordinate.latitude),@(prev.coordinate.longitude)]];
    for(NSUInteger i=start+1; i<self.allRoutePoints.count && out.count<40; i++){
        CLLocation *curr=self.allRoutePoints[i];acc+=[curr distanceFromLocation:prev];
        [out addObject:@[@(curr.coordinate.latitude),@(curr.coordinate.longitude)]];
        prev=curr;
        if(i > idx && acc>=maxDist)break;
    }
    return out;
}
- (void)updateTelemetryForLocation:(CLLocation *)curr pointIndex:(NSUInteger)ptIdx{
    if(!self.allRoutePoints.count||!self.routeSteps.count)return;
    double heading=0;
    if(!self.simulated && curr.course >= 0 && curr.speed > 1.2){
        heading = curr.course;
    } else if(!self.simulated && self.permission.heading && self.permission.heading.headingAccuracy > 0){
        heading = self.permission.heading.trueHeading >= 0 ? self.permission.heading.trueHeading : self.permission.heading.magneticHeading;
    } else if(ptIdx<self.allRoutePoints.count-1){
        CLLocation *next=self.allRoutePoints[ptIdx+1];
        double dLon=(next.coordinate.longitude-curr.coordinate.longitude)*M_PI/180.0;
        double y=sin(dLon)*cos(next.coordinate.latitude*M_PI/180.0);
        double x=cos(curr.coordinate.latitude*M_PI/180.0)*sin(next.coordinate.latitude*M_PI/180.0)-sin(curr.coordinate.latitude*M_PI/180.0)*cos(next.coordinate.latitude*M_PI/180.0)*cos(dLon);
        heading=atan2(y,x)*180.0/M_PI;if(heading<0)heading+=360.0;
    }
    MKRouteStep *step=self.routeSteps.firstObject;NSInteger stepIdx=self.currentStepIndex;double distToManeuver=100;
    CLLocationCoordinate2D maneuverCoord = CLLocationCoordinate2DMake(0, 0);
    while(stepIdx<(NSInteger)self.routeSteps.count){
        MKRouteStep *s=self.routeSteps[stepIdx];
        if(s.instructions.length&&![s.instructions isEqualToString:@"Depart"]){
            step=s;NSUInteger sc=s.polyline.pointCount;
            if(sc>0){
                CLLocationCoordinate2D se;[s.polyline getCoordinates:&se range:NSMakeRange(sc-1,1)];
                maneuverCoord = se;
                CLLocation *sl=[[CLLocation alloc]initWithLatitude:se.latitude longitude:se.longitude];
                distToManeuver=[curr distanceFromLocation:sl];
                if(distToManeuver<25.0&&stepIdx+1<(NSInteger)self.routeSteps.count){
                    stepIdx++;continue;
                }
            }
            break;
        }
        stepIdx++;
    }
    self.currentStepIndex=stepIdx;
    CLLocation *destLoc=self.allRoutePoints.lastObject;
    double remainingMeters=[curr distanceFromLocation:destLoc];
    double speed=(self.selectedTransport==TIONavigationDrive)?12.0:1.4;
    double remainingSeconds=remainingMeters/speed;
    NSInteger icon=IconForStep(step);
    NSString *road=step.instructions.length?step.instructions:@"Follow Path";
    // Quantize distance to avoid fractional jitter and tile churn:
    NSInteger rawDist = (NSInteger)lround(distToManeuver);
    NSInteger quantizedDist;
    if(rawDist >= 200) quantizedDist = (rawDist / 20) * 20;
    else if(rawDist >= 50) quantizedDist = (rawDist / 10) * 10;
    else quantizedDist = MAX(0, ((rawDist + 2) / 5) * 5);
    
    // Quantize remaining summary so Tier 3 stays completely static between 50m blocks:
    NSInteger quantizedRemaining = ((NSInteger)lround(remainingMeters) / 50) * 50;
    NSInteger quantizedSeconds = ((NSInteger)lround(remainingSeconds) / 60) * 60;

    // Check if the mini-map needs to recalculate/redraw:
    // Quantize heading to 6-degree steps to eliminate fractional jitter:
    double mapHeading = round(heading / 6.0) * 6.0;
    CLLocation *lastMapLoc = [[CLLocation alloc] initWithLatitude:self.lastMapUserCoord.latitude longitude:self.lastMapUserCoord.longitude];
    double mapDistMoved = [curr distanceFromLocation:lastMapLoc];
    BOOL mapDirty = (self.lastMapUserCoord.latitude == 0 && self.lastMapUserCoord.longitude == 0) ||
                    mapDistMoved >= 18.0 ||
                    fabs(mapHeading - self.lastMapHeading) >= 6.0 ||
                    self.currentStepIndex != self.lastMiniMapStepIdx;
    
    if(mapDirty){
        self.lastMapUserCoord = curr.coordinate;
        self.lastMapHeading = mapHeading;
        self.cachedLocalCoords = [self localCoordinatesFromIndex:ptIdx maxDistance:350.0];
        self.cachedMapRoads = [[TIONavRoadNetwork sharedNetwork] segmentsNear:curr.coordinate];
        self.lastMiniMapStepIdx = self.currentStepIndex;
        if(CLLocationCoordinate2DIsValid(maneuverCoord) && (maneuverCoord.latitude != 0 || maneuverCoord.longitude != 0)){
            self.cachedManeuverCoord = @[ @(maneuverCoord.latitude), @(maneuverCoord.longitude) ];
        } else {
            self.cachedManeuverCoord = nil;
        }
        
        NSDictionary *norm = TNVNormalizeCoordinates(self.cachedLocalCoords);
        if(norm[@"navPoints"]) self.cachedNavPoints = norm[@"navPoints"];
        self.lastMiniMapPtIdx = ptIdx;
    }
    
    // Request surrounding road network from Overpass in background
    [[TIONavRoadNetwork sharedNetwork] updateForCoordinate:curr.coordinate];
    
    NSMutableDictionary *frame=[TIONavDisplay(@"navigating",icon,road,quantizedDist,quantizedRemaining,quantizedSeconds,self.simulated) mutableCopy];
    frame[@"remainingMeters"]=@(quantizedRemaining);
    frame[@"remainingSeconds"]=@(quantizedSeconds);
    if(self.cachedNavPoints)frame[@"navPoints"]=self.cachedNavPoints;
    frame[@"navHeading"]=@((unsigned)lround(mapHeading));

    // Even Realities G2 vector wireframe map telemetry (stable & jitter-free):
    frame[@"userCoord"] = @[ @(self.lastMapUserCoord.latitude), @(self.lastMapUserCoord.longitude) ];
    frame[@"heading"] = @(self.lastMapHeading);
    if(self.cachedLocalCoords) frame[@"routeCoords"] = self.cachedLocalCoords;
    if(self.cachedManeuverCoord) frame[@"maneuverCoord"] = self.cachedManeuverCoord;
    if(self.cachedMapRoads.count > 0) frame[@"roadSegments"] = self.cachedMapRoads;
    
    self.lastInfo=NSProcessInfo.processInfo.systemUptime;self.staleShown=NO;
    [self setFrame:frame];
    [self.map setCenterCoordinate:curr.coordinate animated:YES];
}
- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations{
    CLLocation *loc=locations.lastObject;if(!loc||loc.horizontalAccuracy<0||loc.horizontalAccuracy>150)return;
    if(self.locating){self.locating=NO;[self.map setCenterCoordinate:loc.coordinate animated:YES];self.note=@"Location acquired.";[self refresh];return;}
    if(!self.active||self.simulated||!self.allRoutePoints.count)return;
    NSUInteger closest=0;double minDist=DBL_MAX;
    for(NSUInteger i=0;i<self.allRoutePoints.count;i++){
        double d=[loc distanceFromLocation:self.allRoutePoints[i]];
        if(d<minDist){minDist=d;closest=i;}
    }
    self.currentPointIndex=closest;
    [self updateTelemetryForLocation:loc pointIndex:closest];
}
- (void)locationManager:(CLLocationManager *)manager didUpdateHeading:(CLHeading *)newHeading{
    if(!newHeading || newHeading.headingAccuracy < 0 || !self.active || self.simulated || !self.allRoutePoints.count) return;
    if(self.currentPointIndex < self.allRoutePoints.count){
        CLLocation *curr = self.allRoutePoints[self.currentPointIndex];
        [self updateTelemetryForLocation:curr pointIndex:self.currentPointIndex];
    }
}
- (MKOverlayRenderer *)mapView:(MKMapView *)map rendererForOverlay:(id<MKOverlay>)overlay{
    if([overlay isKindOfClass:MKPolyline.class]){
        MKPolylineRenderer *r=[[MKPolylineRenderer alloc]initWithPolyline:(MKPolyline *)overlay];
        r.lineWidth=6;r.strokeColor=[UIColor colorWithRed:0.15 green:0.8 blue:0.4 alpha:0.9];return r;
    }
    return nil;
}
- (MKAnnotationView *)mapView:(MKMapView *)map viewForAnnotation:(id<MKAnnotation>)annotation{
    if([annotation isKindOfClass:MKUserLocation.class])return nil;
    MKMarkerAnnotationView *v=(MKMarkerAnnotationView *)[map dequeueReusableAnnotationViewWithIdentifier:@"navpin"];
    if(!v)v=[[MKMarkerAnnotationView alloc]initWithAnnotation:annotation reuseIdentifier:@"navpin"];else v.annotation=annotation;
    if(annotation==self.startPin){v.markerTintColor=UIColor.systemBlueColor;v.glyphImage=[UIImage systemImageNamed:@"play.fill"];}
    else{v.markerTintColor=UIColor.systemRedColor;v.glyphImage=[UIImage systemImageNamed:@"mappin"];}
    return v;
}
- (void)routeDetails{
    if(!self.routeSteps.count){[self alert:@"No Route" message:@"Choose destination and plan route first."];return;}
    NSMutableArray *lines=[NSMutableArray new];
    for(MKRouteStep *s in self.routeSteps){
        if(!s.instructions.length)continue;
        [lines addObject:[NSString stringWithFormat:@"%lu. %@ (%.0f m)",(unsigned long)lines.count+1,s.instructions,s.distance]];
        if(lines.count>=30)break;
    }
    [self alert:@"Route Steps" message:[lines componentsJoinedByString:@"\n"]];
}
- (void)fail:(NSString *)message{[self halt];self.note=message;[self setFrame:TIONavDisplay(@"error",0,@"",-1,-1,-1,self.simulated)];}
- (void)halt{
    if(self.simDispatchTimer){dispatch_source_cancel(self.simDispatchTimer);self.simDispatchTimer=nil;}
    [self.simTimer invalidate];self.simTimer=nil;
    UIApplication.sharedApplication.idleTimerDisabled=NO;
    self.navigationStarted=NO;self.backgroundLocationEnabled=NO;[self endNavigationBackgroundTask];
#if TIO_DISPLAY_PHONE
    TDPPhoneNavigationStop();self.hudIconPixels=nil;self.hudIconType=0;self.crossPixels=nil;
#endif
    [self.subtitleHUD stop:@"Navigation stopped"];[self.teleHUD stop:@"Navigation stopped"];
    self.generation++;self.locationGeneration++;self.locating=NO;
    [self.permission stopUpdatingLocation];
    self.routeReady=NO;self.active=NO;self.planning=NO;self.fixture=NO;self.rerouting=NO;
    self.cachedNavPoints=nil;self.lastMiniMapPtIdx=0;self.lastMiniMapStepIdx=0;
    if(self.routeLine){[self.map removeOverlay:self.routeLine];self.routeLine=nil;}
}
- (void)stopUser{[self halt];TIONavEnableNotices(NO);self.note=@"Navigation stopped.";self.routeSummary.text=@"Navigation ended · Plan a new route";self.display=TIONavDisplay(@"stopped",0,@"",-1,-1,-1,self.simulated);TIONavEnableDisplay(NO);[self refresh];}
#include "NavigationBackground.inc"
- (void)startFixture{[self halt];self.active=YES;self.fixture=YES;self.simulated=YES;self.fixtureStep=0;self.note=@"Offline fixture running";[self setFrame:TIONavDisplay(@"navigating",9,@"Simulated Avenue",160,850,720,YES)];}
- (void)startWalking{[self planRoute];}
- (void)startSimulation{[self planRoute];}
- (void)refreshConnection{TIONavRefreshConnection();[self refresh];}
- (void)subtitleCheck{[self stopUser];[self.navigationController pushViewController:TIOSubtitleHUDController() animated:YES];}
- (BOOL)canStartSubtitle{
#if TIO_DISPLAY_PHONE
    if([TDPPhoneNavigationStatus()[@"active"] boolValue])return NO;
#endif
    NSDictionary *transport=TIONavTransportStatus();
    return self.active&&self.simulated&&!self.fixture&&!self.planning&&!self.rerouting&&NSProcessInfo.processInfo.systemUptime-self.lastInfo<=15&&TIONavSubtitleText(self.display)&&![TIONewsTeleStatus()[@"active"] boolValue]&&![self.teleHUD.status[@"enabled"] boolValue]&&![transport[@"enabled"] boolValue]&&![transport[@"pending"] boolValue]&&![transport[@"noticePending"] boolValue]&&![transport[@"notices"] boolValue];
}
- (void)enableSubtitleHUD{
    if(![self canStartSubtitle]){[self alert:@"Start Navigation First" message:@"Calculate a route first, then enable subtitles."];return;}
    if(![TIOSubtitleNavigationStatus()[@"available"] boolValue]){[self alert:@"Subtitle Channel Not Ready" message:@"Verify glasses connection."];return;}
    [self.subtitleHUD startWithFrame:self.display at:NSProcessInfo.processInfo.systemUptime];[self refresh];
}
- (void)manualHUD{[self stopUser];[self.navigationController pushViewController:TIOManualHUDController() animated:YES];}
- (BOOL)subtitleBlocksOtherDisplay{
#if TIO_DISPLAY_PHONE
    if([TDPPhoneNavigationStatus()[@"active"] boolValue]){[self alert:@"Stop native HUD first." message:@"Stop Glasses HUD before switching channels."];return YES;}
#endif
    return NO;
}
- (void)enableTeleHUD{if([self subtitleBlocksOtherDisplay])return;TIONavEnableNotices(NO);TIONavEnableDisplay(NO);if([self.teleHUD enable]){[self.teleHUD offer:self.display at:NSProcessInfo.processInfo.systemUptime];[self.teleHUD pumpAt:NSProcessInfo.processInfo.systemUptime];}[self refresh];}
- (void)testNotice{if([self subtitleBlocksOtherDisplay])return;[self.teleHUD stop:@"Switch to notification testing"];TIONavTestNotice();[self refresh];}
- (void)enableNotices{if([self subtitleBlocksOtherDisplay])return;[self.teleHUD stop:@"Switch to automatic notifications"];TIONavEnableNotices(YES);TIONavOfferDisplay(self.display);TIONavPump();[self refresh];}
- (void)enableGlasses{if([self subtitleBlocksOtherDisplay])return;TIONavEnableDisplay(YES);TIONavOfferDisplay(self.display);TIONavPump();[self refresh];}
#include "NavigationDisplayHUD.inc"
#include "NavigationWorkspace.inc"
@end
UIViewController *TIONavigationController(void){return [TIONavigationPanel new];}
