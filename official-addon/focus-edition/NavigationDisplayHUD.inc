// Included inside TIONavigationPanel. Renders MapKit navigation wireframes to
// glasses via TDP1 (Item 8 / Display Test). No special firmware required.
#if TIO_DISPLAY_PHONE
- (NSDictionary *)displayHUDFrame{return self.display;}
- (BOOL)canStartDisplayHUD{
 NSDictionary *t=TIONavTransportStatus();
 return self.active&&!self.routeReady&&!self.fixture&&!self.planning&&!self.rerouting&&!self.gpsWeak&&NSProcessInfo.processInfo.systemUptime-self.lastInfo<=15&&[self.display[@"phase"] isEqual:@"navigating"]&&![self.subtitleHUD.status[@"enabled"] boolValue]&&[TIOSubtitleNavigationStatus()[@"phase"] isEqual:@"idle"]&&![self.teleHUD.status[@"enabled"] boolValue]&&![TIONewsTeleStatus()[@"active"] boolValue]&&![t[@"enabled"] boolValue]&&![t[@"pending"] boolValue]&&![t[@"notices"] boolValue]&&![t[@"noticePending"] boolValue];
}
- (void)buildDisplayHUD{
 UILabel *title=[self navLabel:@"Glasses Native Navigation · TNV1" size:16 weight:UIFontWeightSemibold];[self.lensCard addArrangedSubview:title];
 UILabel *guide=[self navLabel:@"1. Plan route → Start simulation or live navigation\n2. Tap 'Start Glasses HUD' below (or open Item 9 · Nav on glasses)\n3. Phone sends compact 328-byte TNV1 packets to open and update the native Nav screen on your RayNeo iO glasses." size:12 weight:UIFontWeightRegular];guide.textColor=UIColor.secondaryLabelColor;guide.hidden=YES;__weak UILabel *weakGuide=guide;
 [self.lensCard addArrangedSubview:TIOFoldHeader(@"How it works",NO,^{weakGuide.hidden=!weakGuide.hidden;})];[self.lensCard addArrangedSubview:guide];
 UIStackView *row=[UIStackView new];UILabel *label=[self navLabel:@"Always-On Navigation Display" size:13 weight:UIFontWeightRegular];UISwitch *toggle=[UISwitch new];toggle.on=TNVAlways();[toggle addTarget:self action:@selector(nativeNavAlwaysChanged:) forControlEvents:UIControlEventValueChanged];[row addArrangedSubview:label];[row addArrangedSubview:toggle];[self.lensCard addArrangedSubview:row];
 self.tdpPreview=[UIImageView new];self.tdpPreview.contentMode=UIViewContentModeScaleAspectFit;self.tdpPreview.backgroundColor=UIColor.blackColor;self.tdpPreview.clipsToBounds=YES;self.tdpPreview.layer.cornerRadius=10;[self.tdpPreview.heightAnchor constraintEqualToAnchor:self.tdpPreview.widthAnchor multiplier:0.25].active=YES;[self.lensCard addArrangedSubview:self.tdpPreview];
 self.tdpStatus=[self navLabel:@"Ready · Tap Start Glasses HUD or open Nav on glasses." size:12 weight:UIFontWeightRegular];self.tdpStatus.accessibilityIdentifier=@"navigation-tdp-status";[self.lensCard addArrangedSubview:self.tdpStatus];
 self.tdpButton=[self navAction:@"Start Glasses HUD" icon:@"arrow.triangle.turn.up.right.diamond" selector:@selector(toggleDisplayHUD) primary:YES];self.tdpButton.accessibilityIdentifier=@"navigation-tdp-enable";[self.lensCard addArrangedSubview:self.tdpButton];
}
- (void)nativeNavAlwaysChanged:(UISwitch *)sender{TNVSetAlways(sender.on);}
- (void)refreshDisplayHUD{
 if(!self.tdpButton)return;NSDictionary *s=TDPPhoneNavigationStatus();BOOL on=[s[@"active"] boolValue];
 UIButtonConfiguration *c=self.tdpButton.configuration;c.title=on?@"Stop Glasses HUD":@"Start Glasses HUD";self.tdpButton.configuration=c;self.tdpButton.enabled=on||[self canStartDisplayHUD];
 self.tdpStatus.text=[NSString stringWithFormat:@"%@\nConfirmed snapshots: %@ · %@",s[@"note"]?:@"",s[@"snapshots"]?:@0,TNVAlways()?@"Always On":@"Sleep after 60s idle"];
 if(on&&self.display){
  self.tdpPreview.hidden=NO;
  self.tdpPreview.image=[self glassesMirrorPreview];
 } else {
  self.tdpPreview.hidden=YES;
 }
}
- (UIImage *)glassesMirrorPreview{
    return TDPPhoneNavigationRender(self.display);
}
- (void)toggleDisplayHUD{
 if([TDPPhoneNavigationStatus()[@"active"] boolValue]){TDPPhoneNavigationStop();[self refreshDisplayHUD];return;}
 if(![self canStartDisplayHUD]){[self alert:@"Start Navigation First" message:@"Plan a route and start simulation or live navigation first. Turn-by-turn guidance must be active."];return;}
 NSUInteger g=self.generation;UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Start Native Glasses Navigation?" message:@"Opens the native Nav screen (Item 9) on your RayNeo iO glasses and streams compact TNV1 turn-by-turn updates." preferredStyle:UIAlertControllerStyleAlert];
 [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
 [a addAction:[UIAlertAction actionWithTitle:@"Confirm & Start" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){
  if(g!=self.generation||![self canStartDisplayHUD])return;
  BOOL ok=TDPPhoneNavigationStart([self displayHUDFrame]);
  if(!ok)[self alert:@"HUD Not Started" message:@"Verify glasses Bluetooth connection and ensure no other file transfer is active."];
  [self refreshDisplayHUD];
 }]];
 [self presentViewController:a animated:YES completion:nil];
}
#endif
