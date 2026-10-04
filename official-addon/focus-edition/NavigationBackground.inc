// Included in TIONavigationPanel; maintains continuous navigation updates during screen standby/background.
- (BOOL)navigationLocationAuthorized {
    CLAuthorizationStatus s=self.permission.authorizationStatus;
    return s==kCLAuthorizationStatusAuthorizedAlways || s==kCLAuthorizationStatusAuthorizedWhenInUse;
}
- (BOOL)navigationLocationModeAvailable {
    id modes=[NSBundle.mainBundle objectForInfoDictionaryKey:@"UIBackgroundModes"];
    return [modes isKindOfClass:NSArray.class] && [modes containsObject:@"location"];
}
- (void)endNavigationBackgroundTask {
    self.backgroundEpoch++;
    UIBackgroundTaskIdentifier task=self.navigationBackgroundTask;
    self.navigationBackgroundTask=UIBackgroundTaskInvalid;
    if(task!=UIBackgroundTaskInvalid)[UIApplication.sharedApplication endBackgroundTask:task];
}
- (void)background {
    if(!self.navigationStarted && !self.active)return;
    self.backgroundLocationEnabled=YES;
    
    // Ensure background location updates remain active through standby
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
    [self.permission startUpdatingLocation];
    
#if TIO_DISPLAY_PHONE
    TDPPhoneStartKeepalive();
#endif
    
    // Maintain background task assertion
    if(self.navigationBackgroundTask==UIBackgroundTaskInvalid){
        __weak typeof(self) weak=self;
        self.navigationBackgroundTask=[UIApplication.sharedApplication beginBackgroundTaskWithName:@"RayNeoNavBackgroundHUD" expirationHandler:^{
            TIONavigationPanel *s=weak;if(!s)return;
            [s endNavigationBackgroundTask];
        }];
    }
    self.note=self.simulated?@"Background simulation active. Updating glasses HUD.":@"Background navigation active. Updating glasses HUD.";
    [self refresh];
}
- (void)navigationForeground {
    [self endNavigationBackgroundTask];
    if(self.active){
        UIApplication.sharedApplication.idleTimerDisabled=YES;
        self.note=self.simulated?@"Simulated navigation running.":@"Live navigation active.";
        [self refresh];
    }
}
- (void)locationManagerDidChangeAuthorization:(CLLocationManager *)manager {
    if(manager!=self.permission)return;
    if(self.active&&!self.simulated&&![self navigationLocationAuthorized]){
        [self stopUser];self.note=@"Location permission revoked. Navigation stopped.";[self refresh];
    }
}
