// Native navigation workspace. Included inside TIONavigationPanel implementation.
- (UILabel *)navLabel:(NSString *)text size:(CGFloat)size weight:(UIFontWeight)weight{
    UILabel *l=[UILabel new];l.text=text;l.numberOfLines=0;l.font=[UIFont systemFontOfSize:size weight:weight];l.adjustsFontForContentSizeCategory=YES;return l;
}
- (UIStackView *)navCard{
    UIStackView *s=[UIStackView new];s.axis=UILayoutConstraintAxisVertical;s.spacing=12;s.layoutMargins=UIEdgeInsetsMake(16,16,16,16);s.layoutMarginsRelativeArrangement=YES;s.backgroundColor=UIColor.secondarySystemGroupedBackgroundColor;s.layer.cornerRadius=20;[self.stack addArrangedSubview:s];return s;
}
- (UIButton *)navAction:(NSString *)title icon:(NSString *)icon selector:(SEL)sel primary:(BOOL)primary{
    UIButton *b=[UIButton buttonWithType:UIButtonTypeSystem];UIButtonConfiguration *c=primary?[UIButtonConfiguration filledButtonConfiguration]:[UIButtonConfiguration tintedButtonConfiguration];c.title=title;c.image=[UIImage systemImageNamed:icon withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:17 weight:UIImageSymbolWeightMedium]];c.imagePadding=6;c.baseBackgroundColor=UIColor.systemTealColor;c.baseForegroundColor=primary?UIColor.whiteColor:UIColor.systemTealColor;c.cornerStyle=UIButtonConfigurationCornerStyleLarge;c.contentInsets=NSDirectionalEdgeInsetsMake(12,8,12,8);c.titleTextAttributesTransformer=^NSDictionary *(NSDictionary *a){NSMutableDictionary *m=[a mutableCopy];m[NSFontAttributeName]=[UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];return m;};b.configuration=c;[b addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];[b.heightAnchor constraintGreaterThanOrEqualToConstant:48].active=YES;return b;
}
- (void)buildWorkspace{
    for(UIView *v in self.stack.arrangedSubviews.copy){[self.stack removeArrangedSubview:v];[v removeFromSuperview];}
    self.title=@"Navigation";self.note=@"Search for destination or tap map to set pin. Sim start can be configured separately. Plan route, then begin.";self.stack.spacing=14;self.scroll.keyboardDismissMode=UIScrollViewKeyboardDismissModeOnDrag;self.scroll.delaysContentTouches=NO;
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc]initWithImage:[UIImage systemImageNamed:@"ellipsis.circle"] style:UIBarButtonItemStylePlain target:self action:@selector(navigationMore)];self.navigationItem.rightBarButtonItem.accessibilityIdentifier=@"navigation-more";
    UILabel *eyebrow=[self navLabel:@"TURBO IO  /  GOOGLE MAPS & RAYNEO HUD" size:12 weight:UIFontWeightSemibold];eyebrow.textColor=UIColor.secondaryLabelColor;[self.stack addArrangedSubview:eyebrow];
    self.searchButton=[self navAction:@"Where to? Search place or address" icon:@"magnifyingglass" selector:@selector(searchPlaces) primary:NO];self.searchButton.accessibilityIdentifier=@"navigation-search";[self.stack addArrangedSubview:self.searchButton];
    self.transportMode=[[UISegmentedControl alloc]initWithItems:TIONavigationModeTitles()];self.transportMode.selectedSegmentIndex=TIONavigationWalk;self.transportMode.accessibilityIdentifier=@"navigation-transport-mode";[self.transportMode addTarget:self action:@selector(transportModeChanged) forControlEvents:UIControlEventValueChanged];[self.stack addArrangedSubview:self.transportMode];
    self.mapPickRole=[[UISegmentedControl alloc]initWithItems:@[@"Destination",@"Sim Start"]];self.mapPickRole.selectedSegmentIndex=0;self.mapPickRole.accessibilityIdentifier=@"navigation-pick-role";[self.mapPickRole addTarget:self action:@selector(pickRoleChanged) forControlEvents:UIControlEventValueChanged];[self.stack addArrangedSubview:self.mapPickRole];
    self.mapHost=[UIView new];self.mapHost.backgroundColor=UIColor.secondarySystemGroupedBackgroundColor;self.mapHost.layer.cornerRadius=22;self.mapHost.clipsToBounds=YES;self.mapHeight=[self.mapHost.heightAnchor constraintEqualToConstant:240];self.mapHeight.active=YES;[self.stack addArrangedSubview:self.mapHost];
    self.mapHint=[self navLabel:@"Map Ready\n\nGoogle Maps & Apple MapKit\nTap Open Map or Search" size:16 weight:UIFontWeightMedium];self.mapHint.textAlignment=NSTextAlignmentCenter;self.mapHint.textColor=UIColor.secondaryLabelColor;self.mapHint.translatesAutoresizingMaskIntoConstraints=NO;[self.mapHost addSubview:self.mapHint];[NSLayoutConstraint activateConstraints:@[[self.mapHint.leadingAnchor constraintEqualToAnchor:self.mapHost.leadingAnchor constant:24],[self.mapHint.trailingAnchor constraintEqualToAnchor:self.mapHost.trailingAnchor constant:-24],[self.mapHint.centerYAnchor constraintEqualToAnchor:self.mapHost.centerYAnchor]]];
    self.mapCrosshair=[[UIImageView alloc]initWithImage:[UIImage systemImageNamed:@"scope"]];self.mapCrosshair.tintColor=UIColor.systemTealColor;self.mapCrosshair.translatesAutoresizingMaskIntoConstraints=NO;[self.mapHost addSubview:self.mapCrosshair];self.originHint=[self navLabel:@"  Tap map to select destination  " size:11 weight:UIFontWeightSemibold];self.originHint.backgroundColor=UIColor.secondarySystemGroupedBackgroundColor;self.originHint.layer.cornerRadius=8;self.originHint.clipsToBounds=YES;self.originHint.translatesAutoresizingMaskIntoConstraints=NO;[self.mapHost addSubview:self.originHint];[NSLayoutConstraint activateConstraints:@[[self.mapCrosshair.centerXAnchor constraintEqualToAnchor:self.mapHost.centerXAnchor],[self.mapCrosshair.centerYAnchor constraintEqualToAnchor:self.mapHost.centerYAnchor],[self.mapCrosshair.widthAnchor constraintEqualToConstant:24],[self.mapCrosshair.heightAnchor constraintEqualToConstant:24],[self.originHint.centerXAnchor constraintEqualToAnchor:self.mapHost.centerXAnchor],[self.originHint.topAnchor constraintEqualToAnchor:self.mapHost.topAnchor constant:8]]];
    UIStackView *mapActions=[[UIStackView alloc]initWithArrangedSubviews:@[[self navAction:@"Open Map" icon:@"map" selector:@selector(consent) primary:NO],[self navAction:@"My Location" icon:@"location" selector:@selector(locateMe) primary:NO],[self navAction:@"Overview" icon:@"arrow.up.left.and.arrow.down.right" selector:@selector(routeOverview) primary:NO]]];mapActions.axis=UILayoutConstraintAxisHorizontal;mapActions.spacing=6;mapActions.distribution=UIStackViewDistributionFillEqually;[self.stack addArrangedSubview:mapActions];
    self.centerButton=[self navAction:@"Set Center as Destination" icon:@"mappin.and.ellipse" selector:@selector(selectMapCenter) primary:NO];self.centerButton.accessibilityIdentifier=@"navigation-select-center";[self.stack addArrangedSubview:self.centerButton];
    self.mapCrosshair.image=[UIImage systemImageNamed:@"scope"];self.mapCrosshair.isAccessibilityElement=NO;
    self.zoomInButton=[self mapZoomButton:@"plus" action:@selector(zoomIn) label:@"Zoom In" identifier:@"navigation-zoom-in"];
    self.zoomOutButton=[self mapZoomButton:@"minus" action:@selector(zoomOut) label:@"Zoom Out" identifier:@"navigation-zoom-out"];
    UIStackView *zoom=[[UIStackView alloc]initWithArrangedSubviews:@[self.zoomInButton,self.zoomOutButton]];zoom.axis=UILayoutConstraintAxisVertical;zoom.spacing=2;zoom.translatesAutoresizingMaskIntoConstraints=NO;[self.mapHost addSubview:zoom];[NSLayoutConstraint activateConstraints:@[[zoom.trailingAnchor constraintEqualToAnchor:self.mapHost.trailingAnchor constant:-8],[zoom.bottomAnchor constraintEqualToAnchor:self.mapHost.bottomAnchor constant:-28]]];
    self.routeCard=[self navCard];self.destinationLabel=[self navLabel:@"Choose Destination" size:21 weight:UIFontWeightSemibold];self.destinationLabel.accessibilityIdentifier=@"navigation-destination";[self.routeCard addArrangedSubview:self.destinationLabel];
    self.routeSummary=[self navLabel:@"Tap map or search to choose destination" size:14 weight:UIFontWeightRegular];self.routeSummary.textColor=UIColor.secondaryLabelColor;[self.routeCard addArrangedSubview:self.routeSummary];
    self.travelMode=[[UISegmentedControl alloc]initWithItems:@[@"Simulation",@"Live GPS"]];self.travelMode.selectedSegmentIndex=0;self.travelMode.accessibilityIdentifier=@"navigation-mode";[self.travelMode addTarget:self action:@selector(modeChanged) forControlEvents:UIControlEventValueChanged];[self.routeCard addArrangedSubview:self.travelMode];
    self.startLabel=[self navLabel:@"Sim Start: Select after opening map" size:13 weight:UIFontWeightMedium];self.startLabel.accessibilityIdentifier=@"navigation-start-point";[self.routeCard addArrangedSubview:self.startLabel];
    self.briefLabel=[self navLabel:@"Sim start saved independently." size:12 weight:UIFontWeightRegular];self.briefLabel.textColor=UIColor.secondaryLabelColor;[self.routeCard addArrangedSubview:self.briefLabel];
    UIStackView *actions=[UIStackView new];actions.axis=UILayoutConstraintAxisHorizontal;actions.spacing=10;actions.distribution=UIStackViewDistributionFillEqually;self.planButton=[self navAction:@"Plan Route" icon:@"point.topleft.down.curvedto.point.bottomright.up" selector:@selector(planRoute) primary:NO];self.planButton.accessibilityIdentifier=@"navigation-plan";self.beginButton=[self navAction:@"Start Simulation" icon:@"play.fill" selector:@selector(beginRoute) primary:YES];self.beginButton.accessibilityIdentifier=@"navigation-begin";[actions addArrangedSubview:self.planButton];[actions addArrangedSubview:self.beginButton];[self.routeCard addArrangedSubview:actions];
    self.lensCard=[self navCard];[self.lensCard addArrangedSubview:[self navLabel:@"Glasses HUD" size:18 weight:UIFontWeightSemibold]];
    self.lensStatus=[self navLabel:@"No navigation sent to glasses yet" size:12 weight:UIFontWeightRegular];self.lensStatus.textColor=UIColor.secondaryLabelColor;self.lensStatus.accessibilityIdentifier=@"navigation-lens-status";[self.lensCard addArrangedSubview:self.lensStatus];
    self.hudLabel=[self navLabel:@"Waiting for navigation" size:19 weight:UIFontWeightMedium];self.hudLabel.textAlignment=NSTextAlignmentCenter;self.hudLabel.textColor=[UIColor colorWithRed:0.28 green:1 blue:0.42 alpha:1];self.hudLabel.backgroundColor=[UIColor colorWithWhite:0.035 alpha:1];self.hudLabel.layer.cornerRadius=14;self.hudLabel.clipsToBounds=YES;self.hudLabel.accessibilityIdentifier=@"navigation-hud";[self.hudLabel.heightAnchor constraintGreaterThanOrEqualToConstant:165].active=YES;[self.lensCard addArrangedSubview:self.hudLabel];
    UILabel *preview=[self navLabel:@"HUD text preview. Formatting rendered by glasses." size:11 weight:UIFontWeightRegular];preview.textColor=UIColor.secondaryLabelColor;[self.lensCard addArrangedSubview:preview];
    self.lensButton=[self navAction:@"Enable Glasses Subtitles" icon:@"eyeglasses" selector:@selector(toggleLens) primary:NO];self.lensButton.accessibilityIdentifier=@"navigation-subtitle-enable";[self.lensCard addArrangedSubview:self.lensButton];
    self.stopButton=[self navAction:@"Stop Navigation" icon:@"stop.fill" selector:@selector(stopUser) primary:YES];UIButtonConfiguration *stopConfig=self.stopButton.configuration;stopConfig.baseBackgroundColor=UIColor.systemRedColor;self.stopButton.configuration=stopConfig;self.stopButton.accessibilityIdentifier=@"navigation-stop";self.stopButton.translatesAutoresizingMaskIntoConstraints=NO;[self.view addSubview:self.stopButton];[NSLayoutConstraint activateConstraints:@[[self.stopButton.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:16],[self.stopButton.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-16],[self.stopButton.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-8]]];
    UILabel *foot=[self navLabel:@"Supports Walking, Cycling, and Driving routes with Google Maps. Keep phone in foreground for live navigation. Do not operate while driving." size:12 weight:UIFontWeightRegular];foot.textColor=UIColor.secondaryLabelColor;[self.stack addArrangedSubview:foot];
}
- (void)refreshWorkspace{
    if(!self.planButton)return;BOOL running=self.active&&!self.planning&&!self.routeReady;
    self.searchButton.enabled=YES;self.travelMode.enabled=!self.active||self.routeReady;self.planButton.enabled=!self.active&&self.hasDestination&&self.initialized;self.beginButton.enabled=self.routeReady;
    self.title=[NSString stringWithFormat:@"%@ Navigation",TIONavigationModeTitle(self.selectedTransport)?:@""];self.transportMode.enabled=TIONavigationMayChangeMode(self.active,self.routeReady);
    UIButtonConfiguration *begin=self.beginButton.configuration;begin.title=self.travelMode.selectedSegmentIndex==0?@"Start Simulation":[NSString stringWithFormat:@"Start %@",TIONavigationModeTitle(self.selectedTransport)];self.beginButton.configuration=begin;
    self.briefLabel.text=self.note?:@"";self.stopButton.hidden=!self.active&&![self.subtitleHUD.status[@"enabled"] boolValue];
    self.scroll.contentInset=UIEdgeInsetsMake(0,0,self.stopButton.hidden?0:68,0);self.scroll.verticalScrollIndicatorInsets=self.scroll.contentInset;self.mapHeight.constant=running?180:240;
    BOOL picking=!self.active||self.routeReady;BOOL sim=self.travelMode.selectedSegmentIndex==0;
    self.originHint.hidden=self.mapCrosshair.hidden=!self.initialized||!picking;self.mapPickRole.hidden=!sim||!picking;self.mapPickRole.enabled=self.initialized;self.centerButton.hidden=!picking;self.centerButton.enabled=self.initialized;
    BOOL origin=sim&&self.mapPickRole.selectedSegmentIndex==1;self.originHint.text=origin?@"  Tap map to select sim start  ":@"  Tap map to select destination  ";UIButtonConfiguration *center=self.centerButton.configuration;center.title=origin?@"Set Center as Sim Start":@"Set Center as Destination";self.centerButton.configuration=center;
    self.startLabel.text=sim?(self.hasSimulationStart?[NSString stringWithFormat:@"Sim Start: %@\n%.5f, %.5f",self.simulationStartName?:@"Map Pin",self.simulationStart.latitude,self.simulationStart.longitude]:@"Sim Start: Select after opening map"):@"Start: Current iPhone Location";
    self.zoomInButton.hidden=self.zoomOutButton.hidden=!self.initialized;
    self.travelMode.hidden=running;self.planButton.superview.hidden=running;
    NSUInteger desired=running?2:self.stack.arrangedSubviews.count-2;if([self.stack.arrangedSubviews indexOfObject:self.lensCard]!=desired){[self.stack removeArrangedSubview:self.lensCard];[self.lensCard removeFromSuperview];[self.stack insertArrangedSubview:self.lensCard atIndex:running?2:self.stack.arrangedSubviews.count-1];}
    if(running)self.routeSummary.text=self.display[@"summary"]?:@"Navigating";
    if(!self.active&&!self.hasDestination)self.routeSummary.text=@"Search place or tap map to set destination";
    NSDictionary *s=self.subtitleHUD.status,*runtime=TIOSubtitleNavigationStatus();BOOL on=[s[@"enabled"] boolValue];
    UIButtonConfiguration *lens=self.lensButton.configuration;lens.title=on?@"Stop Glasses HUD (Keep Phone Nav)":@"Enable Glasses Subtitles";self.lensButton.configuration=lens;
    self.lensButton.enabled=on||[self canStartSubtitle];
    self.lensStatus.text=on?[NSString stringWithFormat:@"%@ · Submitted %@ frames to glasses",s[@"note"],s[@"frames"]]:[NSString stringWithFormat:@"%@\n%@",s[@"note"]?:@"Not streaming",[runtime[@"available"] boolValue]?@"Ready to stream turns to RayNeo glasses":@"Awaiting glasses connection"];
    if(!running)self.hudLabel.text=self.planning?@"Planning route…":self.routeReady?@"Route ready\nTap start for guidance":@"Waiting for guidance\n\nTurn · Distance · Road";
}
- (void)modeChanged{if(![self prepareForSelection])return;self.mapPickRole.selectedSegmentIndex=0;self.routeSummary.text=@"No route planned";self.note=self.travelMode.selectedSegmentIndex==0?@"Sim start saved separately: switch to 'Sim Start' then tap map.":@"Live navigation uses phone GPS. Glasses HUD streams turn-by-turn.";[self refresh];}
- (void)transportModeChanged{
    NSInteger mode=self.transportMode.selectedSegmentIndex;if(!TIONavigationModeTitle(mode)||!TIONavigationMayChangeMode(self.active,self.routeReady)){self.transportMode.selectedSegmentIndex=self.selectedTransport;[self alert:@"End Current Navigation First" message:@"End active navigation before changing travel mode."] ;return;}
    if(![self prepareForSelection])return;self.selectedTransport=mode;self.routeReady=NO;self.routeSummary.text=@"Travel mode changed; please re-plan";
    if(self.routeLine){[self.map removeOverlay:self.routeLine];self.routeLine=nil;}
    self.note=[NSString stringWithFormat:@"Switched to %@. Start/destination kept; recalculating. Test with simulation first. Do not operate while driving.",TIONavigationModeTitle(mode)];[self refresh];
}
- (void)planRoute{if(self.travelMode.selectedSegmentIndex==0)[self startSimulation];else [self startWalking];}
- (void)toggleLens{if([self.subtitleHUD.status[@"enabled"] boolValue]){[self.subtitleHUD stop:@"User stopped glasses HUD, phone navigation continues"];[self refresh];}else [self enableSubtitleHUD];}
- (UIButton *)mapZoomButton:(NSString *)symbol action:(SEL)action label:(NSString *)label identifier:(NSString *)identifier{
    UIButton *b=[UIButton buttonWithType:UIButtonTypeSystem];[b setImage:[UIImage systemImageNamed:symbol] forState:UIControlStateNormal];b.backgroundColor=UIColor.secondarySystemGroupedBackgroundColor;b.tintColor=UIColor.labelColor;b.layer.cornerRadius=10;b.accessibilityLabel=label;b.accessibilityIdentifier=identifier;[b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];[NSLayoutConstraint activateConstraints:@[[b.widthAnchor constraintEqualToConstant:44],[b.heightAnchor constraintEqualToConstant:44]]];return b;
}
- (BOOL)prepareForSelection{
    if(self.active&&!self.routeReady){[self alert:@"End Current Navigation First" message:@"Tap 'Stop Navigation' before changing points."] ;return NO;}
    if(self.routeReady)[self halt];return YES;
}
- (void)pickRoleChanged{self.note=self.mapPickRole.selectedSegmentIndex==1?@"Tap map to set simulation start point.":@"Tap map or search above to choose destination.";[self refresh];}
- (void)selectSimulationStart:(CLLocationCoordinate2D)c name:(NSString *)name{
    if(!TIONavCoordinate(c.latitude,c.longitude)||![self prepareForSelection])return;self.simulationStart=c;self.hasSimulationStart=YES;self.simulationStartName=name;self.routeSummary.text=@"Start point updated; please re-plan route";
    if(self.startPin)[self.map removeAnnotation:self.startPin];self.startPin=[MKPointAnnotation new];self.startPin.coordinate=c;self.startPin.title=@"Sim Start";[self.map addAnnotation:self.startPin];if(self.routeLine){[self.map removeOverlay:self.routeLine];self.routeLine=nil;}
    self.note=@"Sim start point set. Tap map to select destination.";[self refresh];
}
- (void)selectMapCoordinate:(CLLocationCoordinate2D)c{
    if(!TIONavCoordinate(c.latitude,c.longitude)||![self prepareForSelection])return;
    if(self.travelMode.selectedSegmentIndex==0&&self.mapPickRole.selectedSegmentIndex==1)[self selectSimulationStart:c name:@"Map Pin"];
    else [self selectPlace:@{@"name":@"Map Pin",@"address":[NSString stringWithFormat:@"Coordinates %.5f, %.5f",c.latitude,c.longitude],@"lat":@(c.latitude),@"lon":@(c.longitude)}];
}
- (void)selectMapCenter{
    if(!self.initialized){self.pendingMapAction=@"selectMapCenter";[self openMap];return;}[self selectMapCoordinate:self.map.centerCoordinate];
}
- (void)zoomIn{
    if(self.initialized){
        MKCoordinateRegion r=self.map.region;
        r.span.latitudeDelta/=2.0;
        r.span.longitudeDelta/=2.0;
        [self.map setRegion:r animated:YES];
    }
}
- (void)zoomOut{
    if(self.initialized){
        MKCoordinateRegion r=self.map.region;
        r.span.latitudeDelta=MIN(180.0,r.span.latitudeDelta*2.0);
        r.span.longitudeDelta=MIN(360.0,r.span.longitudeDelta*2.0);
        [self.map setRegion:r animated:YES];
    }
}
- (void)searchPlaces{
    if(![self prepareForSelection])return;
    if(!self.initialized){self.pendingMapAction=@"searchPlaces";[self openMap];return;}
    __weak typeof(self) weak=self;UIViewController *picker=TIONavPlacePicker(^(NSDictionary *p){if(!weak.active)[weak selectPlace:p];});picker.modalPresentationStyle=UIModalPresentationPageSheet;picker.sheetPresentationController.detents=@[UISheetPresentationControllerDetent.largeDetent];picker.sheetPresentationController.prefersGrabberVisible=YES;[self presentViewController:picker animated:YES completion:nil];
}
- (void)continueMapAction:(NSUInteger)attempt{
    if(!self.pendingMapAction.length)return;if(!self.view.window||self.active){self.pendingMapAction=nil;return;}
    if(self.presentedViewController){if(attempt<15)dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC/10),dispatch_get_main_queue(),^{[self continueMapAction:attempt+1];});else{self.pendingMapAction=nil;self.note=@"Map ready; tap search or map pin to proceed";[self refresh];}return;}
    NSString *action=self.pendingMapAction;self.pendingMapAction=nil;if([@[@"searchPlaces",@"locateMe",@"demoRoute",@"selectMapCenter"] containsObject:action])[self performSelector:NSSelectorFromString(action)];
}
- (void)selectPlace:(NSDictionary *)value{
    NSDictionary *p=TIONavPlace(value);if(!p||![self prepareForSelection])return;self.destination=CLLocationCoordinate2DMake([p[@"lat"] doubleValue],[p[@"lon"] doubleValue]);self.hasDestination=YES;self.destinationName=p[@"name"];self.destinationLabel.text=[@"Destination · " stringByAppendingString:self.destinationName];self.routeSummary.text=p[@"address"];self.note=@"Destination selected. Check points then tap 'Plan Route'.";
    if(self.pin)[self.map removeAnnotation:self.pin];self.pin=[MKPointAnnotation new];self.pin.coordinate=self.destination;self.pin.title=self.destinationName;[self.map addAnnotation:self.pin];[self.map setCenterCoordinate:self.destination animated:YES];if(self.routeLine){[self.map removeOverlay:self.routeLine];self.routeLine=nil;}
    [self refresh];UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification,@"Destination selected");
}
- (void)routeOverview{
    if(self.routeLine)[self.map setVisibleMapRect:self.routeLine.boundingMapRect edgePadding:UIEdgeInsetsMake(35,30,35,30) animated:YES];else if(self.hasDestination)[self.map setCenterCoordinate:self.destination animated:YES];else [self openMap];
}
- (void)locateMe{
    if(![self prepareForSelection])return;if(!self.initialized){self.pendingMapAction=@"locateMe";[self openMap];return;}CLAuthorizationStatus a=self.permission.authorizationStatus;if(a==kCLAuthorizationStatusNotDetermined){[self.permission requestWhenInUseAuthorization];self.note=@"Tap 'My Location' again after granting permission";[self refresh];return;}if(a==kCLAuthorizationStatusDenied||a==kCLAuthorizationStatusRestricted){[self alert:@"Location Denied" message:@"Enable location in iOS Settings, or use simulation."] ;return;}self.locating=YES;NSUInteger g=++self.locationGeneration;self.map.showsUserLocation=YES;self.note=@"Locating, please wait…";[self refresh];[self.permission startUpdatingLocation];dispatch_after(dispatch_time(DISPATCH_TIME_NOW,15*NSEC_PER_SEC),dispatch_get_main_queue(),^{if(self.locating&&g==self.locationGeneration){self.locating=NO;if(!self.active)self.map.showsUserLocation=NO;self.note=@"Could not obtain accurate location; try in an open area";[self refresh];}});
}
- (void)demoRoute{
    if(![self prepareForSelection])return;if(!self.initialized){self.pendingMapAction=@"demoRoute";[self openMap];return;}[self selectPlace:@{@"name":@"Big Ben & Westminster",@"address":@"London SW1A 0AA, United Kingdom",@"lat":@51.500729,@"lon":@-0.124625}];self.travelMode.selectedSegmentIndex=0;[self selectSimulationStart:CLLocationCoordinate2DMake(51.5074,-0.1278) name:@"Trafalgar Square"];[self.map setCenterCoordinate:self.simulationStart animated:NO];self.note=@"Demo route ready (London). Tap Plan Route → Start Simulation.";[self refresh];
}
- (void)showDiagnostic{[self refresh];[self alert:@"Navigation Status · v3" message:self.statusLabel.text];}
- (void)navigationMore{
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Navigation Settings & Diagnostics" message:@"Options and diagnostics." preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray *items=@[@[@"Subtitle Format & Exit Check",@"subtitleCheck"],@[@"Demo Route (London)",@"demoRoute"],@[@"Route Details",@"routeDetails"],@[@"Refresh Connection",@"refreshConnection"],@[@"Diagnostics",@"showDiagnostic"],@[@"Google Maps Key Settings",@"configureKey"],@[@"Alternative HUD Modes",@"fallbackMenu"]];
    for(NSArray *item in items)[a addAction:[UIAlertAction actionWithTitle:item[0] style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){[self performSelector:NSSelectorFromString(item[1])];}]];[a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];a.popoverPresentationController.barButtonItem=self.navigationItem.rightBarButtonItem;[self presentViewController:a animated:YES completion:nil];
}
- (void)fallbackMenu{
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Alternative HUD Modes · Experimental" message:@"Select fallback display channel for glasses. Stop active subtitles before switching." preferredStyle:UIAlertControllerStyleActionSheet];for(NSArray *item in @[@[@"Manual Teleprompter Check",@"manualHUD"],@[@"Teleprompter Navigation",@"enableTeleHUD"],@[@"Test Notification",@"testNotice"],@[@"Turn Notification Alerts",@"enableNotices"],@[@"Dashboard Widget",@"enableGlasses"],@[@"Offline Display Fixture",@"startFixture"]])[a addAction:[UIAlertAction actionWithTitle:item[0] style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){[self performSelector:NSSelectorFromString(item[1])];}]];[a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];a.popoverPresentationController.barButtonItem=self.navigationItem.rightBarButtonItem;[self presentViewController:a animated:YES completion:nil];
}
- (void)routeDetails{
    if(!self.routeSteps.count){[self alert:@"No Route" message:@"Select a destination and plan a route first."];return;}
    NSMutableArray *lines=[NSMutableArray new];for(NSUInteger i=0;i<self.routeSteps.count;i++){NSDictionary *s=self.routeSteps[i];[lines addObject:[NSString stringWithFormat:@"%lu. %@ · %ld m",(unsigned long)i+1,s[@"road"],(long)[s[@"distance"] integerValue]]];if(lines.count>=40)break;}[self alert:@"Route Steps (Max 40)" message:[lines componentsJoinedByString:@"\n"]];
}
