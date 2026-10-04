// Included in TIONavigationPanel; never changes the host's Bluetooth lifecycle.
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
- (void)expireNavigationBackgroundTask:(NSUInteger)epoch {
    if(epoch!=self.backgroundEpoch || self.navigationBackgroundTask==UIBackgroundTaskInvalid)return;
    [self stopUser];
    self.note=@"Background test time for simulation expired. Restart after returning to foreground.";
    [self refresh];
}
- (void)background {
    TIONavBackgroundAction action=TIONavBackgroundPolicy(self.navigationStarted,self.fixture,self.simulated,self.backgroundLocationEnabled,[self navigationLocationAuthorized]);
    if(action==TIONavBackgroundIdle)return;
    if(action==TIONavBackgroundStop){[self stopUser];self.note=@"Background navigation criteria not met; stopped. Check location permissions.";[self refresh];return;}
    if(action==TIONavBackgroundLocation){self.note=@"Live navigation running in background. Keep app running in background.";[self refresh];return;}
    if(self.navigationBackgroundTask!=UIBackgroundTaskInvalid)return;
    NSUInteger epoch=++self.backgroundEpoch;__weak typeof(self) weak=self;
    self.navigationBackgroundTask=[UIApplication.sharedApplication beginBackgroundTaskWithName:@"TurboIO navigation simulation handoff" expirationHandler:^{[weak expireNavigationBackgroundTask:epoch];}];
    if(self.navigationBackgroundTask==UIBackgroundTaskInvalid){[self stopUser];self.note=@"System did not grant background time for simulation; test in foreground.";[self refresh];return;}
    self.note=@"Short background test for simulation active (max 25s); use authorized live route for sustained lock screen navigation.";[self refresh];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,25*NSEC_PER_SEC),dispatch_get_main_queue(),^{[weak expireNavigationBackgroundTask:epoch];});
}
- (void)navigationForeground {
    [self endNavigationBackgroundTask];
    if(self.navigationStarted&&!self.simulated&&![self navigationLocationAuthorized]){[self stopUser];self.note=@"Location permission revoked; navigation stopped.";}
    else if(self.navigationStarted)self.note=self.simulated?@"Simulation continuing (foreground)":@"Live navigation continuing; background and lock screen supported.";
    [self refresh];
}
- (void)locationManagerDidChangeAuthorization:(CLLocationManager *)manager {
    if(manager!=self.permission)return;
    if(self.navigationStarted&&!self.simulated&&![self navigationLocationAuthorized]){
        [self stopUser];self.note=@"Location permission revoked; navigation stopped.";[self refresh];
    }
}
