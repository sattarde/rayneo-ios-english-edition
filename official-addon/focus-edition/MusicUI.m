#import "MusicPlayer.h"
#import "ResearchUI.h"
#import "MusicAPI.h"
#import "SpotifyAPI.h"
#import <CoreImage/CoreImage.h>

@interface TMMusicPanel:UITableViewController<UISearchBarDelegate>
@property UIImageView *art;
@property UISegmentedControl *sourceSegment,*pageMode;
@property UIStackView *playerStack,*discoveryStack;
@property UIView *controlWrap,*timelineWrap,*spotifyCard;
@property BOOL showDisplaySettings;
@property UILabel *songLabel,*artistLabel,*stateLabel,*lyricLabel,*bridgeLabel,*timeLabel;
@property UIButton *playButton,*loginButton,*spotifyConnectBtn,*spotifyClientBtn;
@property UISlider *progress;
@property UISegmentedControl *displayMode;
@property UISwitch *glassesSwitch;
@property NSArray *results;
@property NSTimer *refreshTimer;
@property NSUInteger searchTicket;
@property UIImage *lastCover;
@end

@interface TMLoginPanel:UIViewController
@property UIImageView *qr;
@property UILabel *note;
@property NSTimer *timer;
@property NSString *key;
@property NSDate *expiry;
@property BOOL checking;
@end

@implementation TMLoginPanel
- (void)viewDidLoad{
 [super viewDidLoad];self.title=@"NetEase Login";self.view.backgroundColor=UIColor.systemBackgroundColor;
 _qr=[UIImageView new];_qr.contentMode=UIViewContentModeScaleAspectFit;
 _note=[UILabel new];_note.numberOfLines=0;_note.textAlignment=NSTextAlignmentCenter;_note.text=@"Obtaining QR code...\nPlease use NetEase Cloud App to scan the code and confirm. The login state is only saved in the local keychain.";
 UIStackView *stack=[[UIStackView alloc]initWithArrangedSubviews:@[_qr,_note]];stack.axis=UILayoutConstraintAxisVertical;stack.spacing=24;stack.translatesAutoresizingMaskIntoConstraints=NO;
 [self.view addSubview:stack];
 [NSLayoutConstraint activateConstraints:@[[stack.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:28],[stack.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-28],[stack.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:36],[_qr.heightAnchor constraintEqualToConstant:280]]];
 __weak typeof(self) weak=self;
 [[TMMusicAPI shared]request:@"/api/login/qrcode/unikey" payload:@{@"type":@3} eapi:YES done:^(NSDictionary *j,NSString *error){
  TMLoginPanel *s=weak;if(!s)return;
  id key=j[@"unikey"];if(![key isKindOfClass:NSString.class]&&[j[@"data"]isKindOfClass:NSDictionary.class])key=j[@"data"][@"unikey"];
  if(error||![key isKindOfClass:NSString.class]){s.note.text=error?:@"Failed to obtain the QR code, please return and try again.";return;}
  s.key=key;s.expiry=[NSDate dateWithTimeIntervalSinceNow:120];
  NSString *url=[@"https://music.163.com/login?codekey=" stringByAppendingString:[key stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet]];
  CIFilter *f=[CIFilter filterWithName:@"CIQRCodeGenerator"];[f setValue:[url dataUsingEncoding:NSUTF8StringEncoding] forKey:@"inputMessage"];
  CIImage *image=[f.outputImage imageByApplyingTransform:CGAffineTransformMakeScale(8,8)];
  CGImageRef cg=[[CIContext contextWithOptions:nil]createCGImage:image fromRect:image.extent];
  if(cg){s.qr.image=[UIImage imageWithCGImage:cg];CGImageRelease(cg);}
  s.note.text=@"Please use NetEase Music to scan the code to confirm that the\nQR code is valid for two minutes; your password will not be read.";
  s.timer=[NSTimer scheduledTimerWithTimeInterval:3 repeats:YES block:^(NSTimer *t){[weak check];}];
 }];
}
- (void)check{
 if(_checking)return;
 if([_expiry timeIntervalSinceNow]<=0){[_timer invalidate];_note.text=@"The QR code has expired, please go back and try again.";return;}
 _checking=YES;__weak typeof(self) weak=self;
 [[TMMusicAPI shared]request:@"/api/login/qrcode/client/login" payload:@{@"key":_key,@"type":@3} eapi:YES done:^(NSDictionary *j,NSString *error){
  TMLoginPanel *s=weak;if(!s)return;s.checking=NO;
  NSInteger code=[j[@"code"]integerValue];
  if(code==803){[s.timer invalidate];s.note.text=TMMusicAPI.shared.hasLogin?@"Already logged in, return to the Music page to use it":@"Confirmed, but not saved login status, please try again";}
  else if(code==800){[s.timer invalidate];s.note.text=@"QR code has expired";}
  else if(code==802)s.note.text=@"The code has been scanned, please confirm on NetEase Cloud";
  else if(error)s.note.text=error;
 }];
}
- (void)viewDidDisappear:(BOOL)animated{[super viewDidDisappear:animated];[_timer invalidate];_timer=nil;}
@end

static UILabel *Label(CGFloat size,UIFontWeight weight){
 UILabel *l=[UILabel new];
 l.font=[[UIFontMetrics metricsForTextStyle:UIFontTextStyleBody] scaledFontForFont:[UIFont systemFontOfSize:size weight:weight]];
 l.adjustsFontForContentSizeCategory=YES;l.textColor=UIColor.labelColor;l.numberOfLines=0;
 return l;
}

static UIButton *Button(NSString *title,NSString *symbol,id target,SEL action){
 UIButton *b=[UIButton buttonWithType:UIButtonTypeSystem];
 UIButtonConfiguration *c=[UIButtonConfiguration plainButtonConfiguration];
 c.title=title;c.image=symbol?[UIImage systemImageNamed:symbol]:nil;
 c.baseForegroundColor=TIOInk();
 c.preferredSymbolConfigurationForImage=[UIImageSymbolConfiguration configurationWithPointSize:23 weight:UIImageSymbolWeightMedium];
 c.imagePadding=8;b.configuration=c;
 [b addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
 return b;
}

static UIView *Inset(UIStackView *stack,CGFloat inset,UIColor *color){
 UIView *v=[UIView new];v.backgroundColor=color;v.layer.cornerRadius=22;v.layer.cornerCurve=kCACornerCurveContinuous;
 stack.translatesAutoresizingMaskIntoConstraints=NO;[v addSubview:stack];
 [NSLayoutConstraint activateConstraints:@[
  [stack.leadingAnchor constraintEqualToAnchor:v.leadingAnchor constant:inset],
  [stack.trailingAnchor constraintEqualToAnchor:v.trailingAnchor constant:-inset],
  [stack.topAnchor constraintEqualToAnchor:v.topAnchor constant:inset],
  [stack.bottomAnchor constraintEqualToAnchor:v.bottomAnchor constant:-inset]
 ]];
 return v;
}

static UIImage *IdleCover(void){
 UIGraphicsImageRendererFormat *f=[UIGraphicsImageRendererFormat defaultFormat];f.scale=1;
 return [[[UIGraphicsImageRenderer alloc]initWithSize:CGSizeMake(320,320) format:f]imageWithActions:^(UIGraphicsImageRendererContext *r){
  CGContextRef c=r.CGContext;CGColorSpaceRef cs=CGColorSpaceCreateDeviceRGB();
  CGFloat colors[]={.11,.11,.13,1,.05,.05,.06,1};
  CGGradientRef g=CGGradientCreateWithColorComponents(cs,colors,NULL,2);
  CGContextDrawLinearGradient(c,g,CGPointZero,CGPointMake(320,320),0);
  CGGradientRelease(g);CGColorSpaceRelease(cs);
  for(int i=0;i<8;i++){
   [[UIColor colorWithWhite:.85 alpha:.035]setStroke];
   UIBezierPath *p=[UIBezierPath bezierPathWithOvalInRect:CGRectMake(34+i*8,34+i*8,252-i*16,252-i*16)];
   p.lineWidth=1;[p stroke];
  }
  UIImage *note=[UIImage systemImageNamed:@"waveform" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:64 weight:UIImageSymbolWeightLight]];
  [[note imageWithTintColor:[UIColor colorWithRed:.11 green:.73 blue:.33 alpha:1] renderingMode:UIImageRenderingModeAlwaysOriginal]drawInRect:CGRectMake(128,122,64,76)];
  [@"S P O T I F Y   /   T U R B O" drawAtPoint:CGPointMake(68,276) withAttributes:@{NSFontAttributeName:[UIFont systemFontOfSize:13 weight:UIFontWeightMedium],NSForegroundColorAttributeName:[UIColor colorWithWhite:.65 alpha:1]}];
 }];
}

@implementation TMMusicPanel

- (void)viewDidLoad{
 [super viewDidLoad];
 self.title=@"Spotify HUD";
 self.hidesBottomBarWhenPushed=YES;
 self.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;
 self.tableView.backgroundColor=TIOPaper();
 self.tableView.separatorStyle=UITableViewCellSeparatorStyleNone;
 self.tableView.tintColor=TIOAccent();

 UINavigationBarAppearance *appearance=[UINavigationBarAppearance new];
 [appearance configureWithDefaultBackground];
 appearance.backgroundColor=[TIOPaper()colorWithAlphaComponent:.25];
 appearance.shadowColor=UIColor.clearColor;
 appearance.titleTextAttributes=@{NSForegroundColorAttributeName:TIOInk(),NSFontAttributeName:[UIFont systemFontOfSize:17 weight:UIFontWeightSemibold]};
 self.navigationItem.standardAppearance=appearance;
 self.navigationItem.scrollEdgeAppearance=appearance;
 self.navigationItem.compactAppearance=appearance;

 UIBarButtonItem *more=[[UIBarButtonItem alloc]initWithImage:[UIImage systemImageNamed:@"ellipsis.circle"] style:UIBarButtonItemStylePlain target:self action:@selector(more)];
 UIBarButtonItem *account=[[UIBarButtonItem alloc]initWithImage:[UIImage systemImageNamed:@"person.crop.circle"] style:UIBarButtonItemStylePlain target:self action:@selector(login)];
 more.tintColor=account.tintColor=TIOInk();
 more.accessibilityLabel=@"Music options";
 account.accessibilityLabel=@"Account status";
 self.navigationItem.rightBarButtonItems=@[more,account];

 // Source Segment: Spotify (Live HUD) vs NetEase / Demo
 _sourceSegment=[[UISegmentedControl alloc]initWithItems:@[@"Spotify (Live HUD)",@"NetEase / Demo"]];
 _sourceSegment.selectedSegmentIndex=(TMPlayer.shared.source==TMMusicSourceSpotify?0:1);
 [_sourceSegment addTarget:self action:@selector(sourceChanged) forControlEvents:UIControlEventValueChanged];
 _sourceSegment.backgroundColor=UIColor.tertiarySystemFillColor;
 _sourceSegment.selectedSegmentTintColor=UIColor.secondarySystemGroupedBackgroundColor;

 // Page Mode for NetEase: Now Playing vs Discover
 _pageMode=[[UISegmentedControl alloc]initWithItems:@[@"Now Playing",@"Discover Music"]];
 _pageMode.selectedSegmentIndex=0;
 [_pageMode addTarget:self action:@selector(pageModeChanged) forControlEvents:UIControlEventValueChanged];
 _pageMode.accessibilityIdentifier=@"music-page-mode";
 _pageMode.hidden=(TMPlayer.shared.source==TMMusicSourceSpotify);

 UISearchBar *search=[UISearchBar new];
 search.placeholder=@"Search for music";
 search.delegate=self;
 search.searchBarStyle=UISearchBarStyleMinimal;
 search.searchTextField.font=[UIFont systemFontOfSize:14];
 self.tableView.keyboardDismissMode=UIScrollViewKeyboardDismissModeOnDrag;

 UILabel *eyebrow=Label(10,UIFontWeightSemibold);
 eyebrow.text=@"T U R B O  I O   /   M U S I C   H U D";
 eyebrow.textColor=UIColor.secondaryLabelColor;
 eyebrow.textAlignment=NSTextAlignmentCenter;

 // Album Art
 _art=[UIImageView new];
 _art.contentMode=UIViewContentModeScaleAspectFill;
 _art.clipsToBounds=YES;
 _art.layer.cornerRadius=16;
 _art.layer.cornerCurve=kCACornerCurveContinuous;
 _art.image=TIOArtwork(@"music")?:IdleCover();
 _art.translatesAutoresizingMaskIntoConstraints=NO;
 UIView *artWrap=[UIView new];
 [artWrap addSubview:_art];
 [NSLayoutConstraint activateConstraints:@[
  [_art.centerXAnchor constraintEqualToAnchor:artWrap.centerXAnchor],
  [_art.topAnchor constraintEqualToAnchor:artWrap.topAnchor constant:4],
  [_art.bottomAnchor constraintEqualToAnchor:artWrap.bottomAnchor constant:-4],
  [_art.widthAnchor constraintEqualToAnchor:_art.heightAnchor],
  [_art.heightAnchor constraintEqualToConstant:232]
 ]];

 // Song metadata
 _songLabel=Label(24,UIFontWeightMedium);
 _songLabel.numberOfLines=1;
 _songLabel.lineBreakMode=NSLineBreakByTruncatingTail;
 _songLabel.textAlignment=NSTextAlignmentCenter;

 _artistLabel=Label(14,UIFontWeightRegular);
 _artistLabel.textColor=UIColor.secondaryLabelColor;
 _artistLabel.numberOfLines=1;
 _artistLabel.textAlignment=NSTextAlignmentCenter;

 UIStackView *metadata=[[UIStackView alloc]initWithArrangedSubviews:@[_songLabel,_artistLabel]];
 metadata.axis=UILayoutConstraintAxisVertical;
 metadata.spacing=5;

 // Spotify Connect Card (shown when Spotify not connected)
 UIImageView *spIcon=[[UIImageView alloc]initWithImage:[UIImage systemImageNamed:@"waveform.circle.fill"]];
 spIcon.tintColor=[UIColor colorWithRed:.11 green:.73 blue:.33 alpha:1];
 spIcon.contentMode=UIViewContentModeScaleAspectFit;
 [spIcon.heightAnchor constraintEqualToConstant:36].active=YES;

 UILabel *spTitle=Label(16,UIFontWeightSemibold);
 spTitle.text=@"Connect Your Spotify Account";
 spTitle.textAlignment=NSTextAlignmentCenter;

 UILabel *spDesc=Label(13,UIFontWeightRegular);
 spDesc.text=@"Sync rotating cover art and synced lyrics directly to your RayNeo iO glasses HUD. Control tracks using your glasses temple wheel and tap.";
 spDesc.textColor=UIColor.secondaryLabelColor;
 spDesc.textAlignment=NSTextAlignmentCenter;

 _spotifyConnectBtn=[UIButton buttonWithType:UIButtonTypeSystem];
 UIButtonConfiguration *scfg=[UIButtonConfiguration filledButtonConfiguration];
 scfg.title=@"Connect with Spotify";
 scfg.image=[UIImage systemImageNamed:@"link"];
 scfg.imagePadding=8;
 scfg.baseBackgroundColor=[UIColor colorWithRed:.11 green:.73 blue:.33 alpha:1];
 scfg.baseForegroundColor=UIColor.whiteColor;
 scfg.cornerStyle=UIButtonConfigurationCornerStyleCapsule;
 _spotifyConnectBtn.configuration=scfg;
 [_spotifyConnectBtn addTarget:self action:@selector(connectSpotify) forControlEvents:UIControlEventTouchUpInside];
 [_spotifyConnectBtn.heightAnchor constraintEqualToConstant:46].active=YES;

 _spotifyClientBtn=[UIButton buttonWithType:UIButtonTypeSystem];
 _spotifyClientBtn.titleLabel.font=[UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
 [_spotifyClientBtn setTitle:[NSString stringWithFormat:@"Client ID: %@… (Edit)", [SpotifyAPI.shared.clientId substringToIndex:MIN((NSUInteger)8,SpotifyAPI.shared.clientId.length)]] forState:UIControlStateNormal];
 [_spotifyClientBtn setTitleColor:UIColor.tertiaryLabelColor forState:UIControlStateNormal];
 [_spotifyClientBtn addTarget:self action:@selector(configureClientId) forControlEvents:UIControlEventTouchUpInside];

 UIStackView *spStack=[[UIStackView alloc]initWithArrangedSubviews:@[spIcon,spTitle,spDesc,_spotifyConnectBtn,_spotifyClientBtn]];
 spStack.axis=UILayoutConstraintAxisVertical;
 spStack.spacing=12;
 spStack.alignment=UIStackViewAlignmentCenter;
 _spotifyCard=Inset(spStack,16,UIColor.secondarySystemGroupedBackgroundColor);

 // Lyrics Label (3-line synchronized rolling display)
 _lyricLabel=Label(17,UIFontWeightMedium);
 _lyricLabel.textColor=TIOAccent();
 _lyricLabel.textAlignment=NSTextAlignmentCenter;
 _lyricLabel.numberOfLines=3;
 [_lyricLabel.heightAnchor constraintGreaterThanOrEqualToConstant:76].active=YES;

 // Timeline
 _progress=[UISlider new];
 _progress.minimumTrackTintColor=[UIColor colorWithRed:.11 green:.73 blue:.33 alpha:1];
 _progress.maximumTrackTintColor=UIColor.separatorColor;
 UIGraphicsImageRenderer *thumb=[[UIGraphicsImageRenderer alloc]initWithSize:CGSizeMake(10,10)];
 UIImage *dot=[thumb imageWithActions:^(UIGraphicsImageRendererContext *r){
  [UIColor.whiteColor setFill];
  [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(0,0,10,10)]fill];
 }];
 [_progress setThumbImage:dot forState:UIControlStateNormal];
 [_progress addTarget:self action:@selector(seek) forControlEvents:UIControlEventTouchUpInside|UIControlEventTouchUpOutside];

 _timeLabel=Label(11,UIFontWeightRegular);
 _timeLabel.font=[UIFont monospacedDigitSystemFontOfSize:11 weight:UIFontWeightRegular];
 _timeLabel.textColor=UIColor.secondaryLabelColor;
 _timeLabel.textAlignment=NSTextAlignmentCenter;

 UIStackView *timeline=[[UIStackView alloc]initWithArrangedSubviews:@[_progress,_timeLabel]];
 timeline.axis=UILayoutConstraintAxisVertical;
 timeline.spacing=-4;
 _timelineWrap=timeline;

 // Controls
 _playButton=Button(@"",@"play.fill",self,@selector(toggle));
 UIButtonConfiguration *play=_playButton.configuration;
 play.baseForegroundColor=TIOPaper();
 play.background.backgroundColor=[UIColor colorWithRed:.11 green:.73 blue:.33 alpha:1];
 play.background.cornerRadius=32;
 _playButton.configuration=play;
 _playButton.accessibilityLabel=@"Play / Pause";

 UIButton *previous=Button(@"",@"backward.end.fill",self,@selector(previous));
 UIButton *next=Button(@"",@"forward.end.fill",self,@selector(next));
 previous.accessibilityLabel=@"Previous";
 next.accessibilityLabel=@"Next";

 UIStackView *controls=[[UIStackView alloc]initWithArrangedSubviews:@[previous,_playButton,next]];
 controls.alignment=UIStackViewAlignmentCenter;
 controls.distribution=UIStackViewDistributionEqualSpacing;
 _controlWrap=Inset(controls,8,nil);
 [_playButton.widthAnchor constraintEqualToConstant:64].active=YES;
 [_playButton.heightAnchor constraintEqualToConstant:64].active=YES;
 [previous.widthAnchor constraintEqualToConstant:64].active=YES;
 [next.widthAnchor constraintEqualToConstant:64].active=YES;

 // Glasses HUD Card
 _glassesSwitch=[UISwitch new];
 _glassesSwitch.on=TMPlayer.shared.glasses;
 _glassesSwitch.onTintColor=[UIColor colorWithRed:.11 green:.73 blue:.33 alpha:1];
 [_glassesSwitch addTarget:self action:@selector(glassesChanged) forControlEvents:UIControlEventValueChanged];

 UILabel *caption=Label(15,UIFontWeightSemibold);
 caption.text=@"Glasses HUD";

 UIImageView *glass=[[UIImageView alloc]initWithImage:[UIImage systemImageNamed:@"eyeglasses"]];
 glass.tintColor=TIOInk();
 glass.contentMode=UIViewContentModeScaleAspectFit;
 [glass.widthAnchor constraintEqualToConstant:24].active=YES;

 UIStackView *switchRow=[[UIStackView alloc]initWithArrangedSubviews:@[glass,caption,_glassesSwitch]];
 switchRow.alignment=UIStackViewAlignmentCenter;
 switchRow.spacing=10;

 _displayMode=[[UISegmentedControl alloc]initWithItems:@[@"Always On",@"30 Seconds",@"1 Minute"]];
 _displayMode.selectedSegmentIndex=TMPlayer.shared.mode;
 _displayMode.backgroundColor=UIColor.tertiarySystemFillColor;
 _displayMode.selectedSegmentTintColor=UIColor.secondarySystemGroupedBackgroundColor;
 [_displayMode addTarget:self action:@selector(modeChanged) forControlEvents:UIControlEventValueChanged];

 UIButton *durationButton=Button(@"Display duration",@"chevron.down",self,@selector(toggleDisplaySettings));
 durationButton.contentHorizontalAlignment=UIControlContentHorizontalAlignmentLeading;
 _displayMode.hidden=YES;

 _bridgeLabel=Label(11,UIFontWeightRegular);
 _bridgeLabel.textColor=UIColor.secondaryLabelColor;
 _bridgeLabel.numberOfLines=2;

 UIStackView *cardStack=[[UIStackView alloc]initWithArrangedSubviews:@[switchRow,durationButton,_displayMode,_bridgeLabel]];
 cardStack.axis=UILayoutConstraintAxisVertical;
 cardStack.spacing=12;
 UIView *card=Inset(cardStack,16,UIColor.secondarySystemGroupedBackgroundColor);

 _stateLabel=Label(11,UIFontWeightRegular);
 _stateLabel.textColor=UIColor.secondaryLabelColor;
 _stateLabel.textAlignment=NSTextAlignmentCenter;
 _stateLabel.hidden=YES;

 _playerStack=[[UIStackView alloc]initWithArrangedSubviews:@[artWrap,metadata,_spotifyCard,_lyricLabel,_timelineWrap,_controlWrap,card,_stateLabel]];
 _playerStack.axis=UILayoutConstraintAxisVertical;
 _playerStack.spacing=14;

 UILabel *searchNote=Label(14,UIFontWeightRegular);
 searchNote.text=@"Search for a song, or open Playlists from the upper right menu.\nYou can try content you have permission to play without logging in.";
 searchNote.textColor=UIColor.secondaryLabelColor;

 _discoveryStack=[[UIStackView alloc]initWithArrangedSubviews:@[search,searchNote]];
 _discoveryStack.axis=UILayoutConstraintAxisVertical;
 _discoveryStack.spacing=16;
 _discoveryStack.hidden=YES;

 UIStackView *stack=[[UIStackView alloc]initWithArrangedSubviews:@[eyebrow,_sourceSegment,_pageMode,_playerStack,_discoveryStack]];
 stack.axis=UILayoutConstraintAxisVertical;
 stack.spacing=18;
 stack.translatesAutoresizingMaskIntoConstraints=NO;

 UIView *header=[UIView new];
 [header addSubview:stack];
 [NSLayoutConstraint activateConstraints:@[
  [stack.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:24],
  [stack.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-24],
  [stack.topAnchor constraintEqualToAnchor:header.topAnchor constant:4],
  [stack.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-24]
 ]];

 self.tableView.tableHeaderView=header;
 [self sourceChanged];
 [self refresh];
}

- (void)viewDidLayoutSubviews{
 [super viewDidLayoutSubviews];
 UIView *h=self.tableView.tableHeaderView;
 CGFloat width=self.tableView.bounds.size.width;
 CGSize s=[h systemLayoutSizeFittingSize:CGSizeMake(width,0) withHorizontalFittingPriority:UILayoutPriorityRequired verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
 if(fabs(h.frame.size.height-s.height)>1||h.frame.size.width!=width){
  h.frame=CGRectMake(0,0,width,s.height);
  self.tableView.tableHeaderView=h;
 }
}

- (void)viewWillAppear:(BOOL)animated{
 [super viewWillAppear:animated];
 __weak typeof(self) weak=self;
 _refreshTimer=[NSTimer scheduledTimerWithTimeInterval:.35 repeats:YES block:^(NSTimer *t){[weak refresh];}];
}

- (void)viewDidDisappear:(BOOL)animated{
 [super viewDidDisappear:animated];
 [_refreshTimer invalidate];
 _refreshTimer=nil;
}

- (void)sourceChanged{
 TMPlayer.shared.source=(_sourceSegment.selectedSegmentIndex==0)?TMMusicSourceSpotify:TMMusicSourceNetEase;
 BOOL isSpotify=(TMPlayer.shared.source==TMMusicSourceSpotify);
 self.title=isSpotify?@"Spotify HUD":@"NetEase Music";
 _pageMode.hidden=isSpotify;
 if(isSpotify){
  _playerStack.hidden=NO;
  _discoveryStack.hidden=YES;
 }else{
  [self pageModeChanged];
 }
 [self.tableView reloadData];
 [self refresh];
 [self.view setNeedsLayout];
}

- (void)refresh{
 TMPlayer *p=TMPlayer.shared;
 BOOL isSpotify=(p.source==TMMusicSourceSpotify);
 BOOL spotifyAuth=SpotifyAPI.shared.hasAuth;

 if(isSpotify){
  _sourceSegment.selectedSegmentIndex=0;
  _pageMode.hidden=YES;
  _spotifyCard.hidden=spotifyAuth;
  _timelineWrap.hidden=!spotifyAuth;
  _controlWrap.hidden=!spotifyAuth;

  if(!spotifyAuth){
   _songLabel.text=@"Spotify Disconnected";
   _artistLabel.text=@"Connect account below to enable Glasses HUD";
   _lyricLabel.attributedText=nil;
   _lyricLabel.text=@"Connect Spotify to display synced lyrics on your glasses.";
  }else{
   SpotifyTrack *t=SpotifyAPI.shared.currentTrack;
   if(t&&t.name.length){
    _songLabel.text=t.name;
    _artistLabel.text=t.artist.length?(t.deviceName.length?[NSString stringWithFormat:@"%@ • %@",t.artist,t.deviceName]:t.artist):@"Spotify";
   }else{
    _songLabel.text=@"Spotify Ready";
    _artistLabel.text=@"Play any song in the Spotify app to sync HUD";
   }
  }
 }else{
  _sourceSegment.selectedSegmentIndex=1;
  _pageMode.hidden=NO;
  _spotifyCard.hidden=YES;
  _timelineWrap.hidden=NO;
  _controlWrap.hidden=NO;

  _songLabel.text=p.song[@"name"]?:@"Listen to music, view lyrics";
  _artistLabel.text=p.song[@"artist"]?:@"Choose a song and start your Music journey";
 }

 UIImage *cover=p.cover;
 if(_lastCover!=cover){
  _lastCover=cover;
  _art.image=cover?:TIOArtwork(@"music")?:IdleCover();
 }

 _stateLabel.text=p.status;
 BOOL steady=[p.status isEqual:@"Playing"]||[p.status isEqual:@"Paused"]||(!isSpotify&&!p.song);
 _stateLabel.hidden=steady;

 _bridgeLabel.text=p.glasses?p.bridgeStatus:@"Sync cover & lyrics to glasses (Item 8 · Display Test)";
 _glassesSwitch.on=p.glasses;
 _displayMode.enabled=p.glasses;
 _displayMode.alpha=p.glasses?1:.5;

 double pos=p.position;
 double dur=p.duration;
 _timeLabel.text=[NSString stringWithFormat:@"%02ld:%02ld  /  %02ld:%02ld",(long)pos/60,(long)pos%60,(long)dur/60,(long)dur%60];

 if(!_progress.tracking){
  _progress.maximumValue=MAX(1,dur);
  _progress.value=pos;
 }

 UIButtonConfiguration *c=_playButton.configuration;
 c.title=@"";
 c.image=[UIImage systemImageNamed:p.playing?@"pause.fill":@"play.fill"];
 _playButton.configuration=c;
 _playButton.accessibilityLabel=p.playing?@"Pause":@"Play";

 NSArray *lyrics=p.lyrics;
 if(lyrics.count>0){
  NSInteger current=-1;
  for(NSUInteger i=0;i<lyrics.count;i++){
   if([lyrics[i][@"ms"]doubleValue]>pos*1000.0)break;
   current=(NSInteger)i;
  }
  if(current>=0){
   NSMutableAttributedString *text=[NSMutableAttributedString new];
   for(NSInteger i=MAX(0,current-1);i<MIN((NSInteger)lyrics.count,current+2);i++){
    if(text.length)[text appendAttributedString:[[NSAttributedString alloc]initWithString:@"\n"]];
    NSDictionary *attrs=@{
     NSForegroundColorAttributeName:(i==current)?TIOInk():UIColor.secondaryLabelColor,
     NSFontAttributeName:[UIFont systemFontOfSize:(i==current)?17:14 weight:(i==current)?UIFontWeightMedium:UIFontWeightRegular]
    };
    [text appendAttributedString:[[NSAttributedString alloc]initWithString:lyrics[i][@"text"]?:@"" attributes:attrs]];
   }
   _lyricLabel.attributedText=text;
  }else{
   _lyricLabel.attributedText=nil;
   _lyricLabel.text=isSpotify?@"Melody flowing…":@"Let the melody flow slowly";
  }
 }else if(isSpotify&&spotifyAuth){
  _lyricLabel.attributedText=nil;
  _lyricLabel.text=@"Searching for synced lyrics…";
 }

 [_spotifyClientBtn setTitle:[NSString stringWithFormat:@"Client ID: %@… (Edit)", [SpotifyAPI.shared.clientId substringToIndex:MIN((NSUInteger)8,SpotifyAPI.shared.clientId.length)]] forState:UIControlStateNormal];
 [self.view setNeedsLayout];
}

- (void)pageModeChanged{
 _playerStack.hidden=_pageMode.selectedSegmentIndex==1;
 _discoveryStack.hidden=!_playerStack.hidden;
 [self.tableView reloadData];
 [self.view setNeedsLayout];
}

- (void)toggleDisplaySettings{
 _showDisplaySettings=!_showDisplaySettings;
 _displayMode.hidden=!_showDisplaySettings;
 [self.view setNeedsLayout];
}

- (void)connectSpotify{
 __weak typeof(self) weak=self;
 [SpotifyAPI.shared startOAuthFromViewController:self completion:^(BOOL success, NSString * _Nullable error){
  dispatch_async(dispatch_get_main_queue(), ^{
   TMMusicPanel *s=weak;if(!s)return;
   if(!success){
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Spotify Connection" message:error?:@"Authentication was canceled or failed." preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [s presentViewController:a animated:YES completion:nil];
   }else{
    [SpotifyAPI.shared startPolling];
    [s refresh];
   }
  });
 }];
}

- (void)configureClientId{
 UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Spotify Client ID" message:@"Enter your Spotify Developer Client ID (Redirect URI: rayneo.venus.app://callback)" preferredStyle:UIAlertControllerStyleAlert];
 [a addTextFieldWithConfigurationHandler:^(UITextField *f){
  f.text=SpotifyAPI.shared.clientId;
  f.placeholder=@"Client ID";
  f.clearButtonMode=UITextFieldViewModeWhileEditing;
 }];
 [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
 [a addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){
  NSString *cid=[a.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  if(cid.length){
   SpotifyAPI.shared.clientId=cid;
  }
  [self refresh];
 }]];
 [self presentViewController:a animated:YES completion:nil];
}

- (void)more{
 UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Music Options" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
 __weak typeof(self) weak=self;
 [a addAction:[UIAlertAction actionWithTitle:@"Display to Glasses HUD" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){[weak showGlasses];}]];
 [a addAction:[UIAlertAction actionWithTitle:@"Close Glasses Screen" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){[weak hideGlasses];}]];
 [a addAction:[UIAlertAction actionWithTitle:@"Play Local Test Track (Offline Demo)" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){[weak demo];}]];
 if(TMPlayer.shared.source==TMMusicSourceSpotify){
  [a addAction:[UIAlertAction actionWithTitle:@"Configure Spotify Client ID" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){[weak configureClientId];}]];
 }else{
  [a addAction:[UIAlertAction actionWithTitle:@"Open NetEase Playlists" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){[weak playlist];}]];
 }
 [a addAction:[UIAlertAction actionWithTitle:@"Diagnostics & Status" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){
  TMMusicPanel *s=weak;if(!s)return;
  UIAlertController *d=[UIAlertController alertControllerWithTitle:@"Music Diagnostics" message:[NSString stringWithFormat:@"Player Status: %@\n\nBridge Status: %@",TMPlayer.shared.status,TMPlayer.shared.bridgeStatus] preferredStyle:UIAlertControllerStyleAlert];
  [d addAction:[UIAlertAction actionWithTitle:@"Done" style:UIAlertActionStyleCancel handler:nil]];
  [s presentViewController:d animated:YES completion:nil];
 }]];
 [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
 a.popoverPresentationController.barButtonItem=self.navigationItem.rightBarButtonItems.firstObject;
 [self presentViewController:a animated:YES completion:nil];
}

- (void)toggle{[TMPlayer.shared play:!TMPlayer.shared.playing];}
- (void)previous{[TMPlayer.shared step:-1];}
- (void)next{[TMPlayer.shared step:1];}
- (void)seek{[TMPlayer.shared seek:_progress.value];}
- (void)demo{[TMPlayer.shared demo];}
- (void)modeChanged{TMPlayer.shared.mode=_displayMode.selectedSegmentIndex;}
- (void)glassesChanged{TMPlayer.shared.glasses=_glassesSwitch.on;}
- (void)showGlasses{[TMPlayer.shared showOnGlasses];}
- (void)hideGlasses{[TMPlayer.shared hideGlasses];}

- (void)login{
 if(TMPlayer.shared.source==TMMusicSourceSpotify){
  if(!SpotifyAPI.shared.hasAuth){
   [self connectSpotify];
   return;
  }
  UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Spotify Account" message:[NSString stringWithFormat:@"Connected to Spotify Web API\nClient ID: %@",SpotifyAPI.shared.clientId] preferredStyle:UIAlertControllerStyleAlert];
  __weak typeof(self) weak=self;
  [a addAction:[UIAlertAction actionWithTitle:@"Configure Client ID" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){[weak configureClientId];}]];
  [a addAction:[UIAlertAction actionWithTitle:@"Disconnect / Log Out" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x){
   [SpotifyAPI.shared logout];
   [weak refresh];
  }]];
  [a addAction:[UIAlertAction actionWithTitle:@"Done" style:UIAlertActionStyleCancel handler:nil]];
  [self presentViewController:a animated:YES completion:nil];
  return;
 }

 if(!TMMusicAPI.shared.hasLogin){
  [self.navigationController pushViewController:[TMLoginPanel new] animated:YES];
  return;
 }
 UIAlertController *a=[UIAlertController alertControllerWithTitle:@"NetEase Cloud Account" message:@"Logged in, credentials saved in local keychain." preferredStyle:UIAlertControllerStyleAlert];
 [a addAction:[UIAlertAction actionWithTitle:@"Close" style:UIAlertActionStyleCancel handler:nil]];
 [a addAction:[UIAlertAction actionWithTitle:@"Log out of Account" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x){
  [TMPlayer.shared play:NO];
  [TMMusicAPI.shared logout];
  [self refresh];
 }]];
 [self presentViewController:a animated:YES completion:nil];
}

- (void)playlist{
 UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Open NetEase Playlists" message:@"Enter the Playlist ID (the ID in the share link)." preferredStyle:UIAlertControllerStyleAlert];
 [a addTextFieldWithConfigurationHandler:^(UITextField *f){f.placeholder=@"Playlist ID";f.keyboardType=UIKeyboardTypeNumberPad;}];
 [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
 [a addAction:[UIAlertAction actionWithTitle:@"Open" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){
  long long n=a.textFields.firstObject.text.longLongValue;
  if(n<=0)return;
  [self load:@"/api/v6/playlist/detail" payload:@{@"id":@(n),@"n":@100,@"s":@8} eapi:YES];
 }]];
 [self presentViewController:a animated:YES completion:nil];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar{
 [searchBar resignFirstResponder];
 NSString *s=[searchBar.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
 if(s.length)[self load:@"/api/cloudsearch/pc" payload:@{@"s":s,@"type":@1,@"limit":@30,@"offset":@0,@"total":@YES} eapi:NO];
}

- (void)load:(NSString *)path payload:(NSDictionary *)payload eapi:(BOOL)eapi{
 NSUInteger ticket=++_searchTicket;
 self.navigationItem.prompt=@"Loading…";
 __weak typeof(self) weak=self;
 [TMMusicAPI.shared request:path payload:payload eapi:eapi done:^(NSDictionary *j,NSString *err){
  TMMusicPanel *s=weak;if(!s||s.searchTicket!=ticket)return;
  id parent=j[eapi?@"playlist":@"result"];
  id list=[parent isKindOfClass:NSDictionary.class]?parent[eapi?@"tracks":@"songs"]:nil;
  NSMutableArray *valid=[NSMutableArray new];
  if([list isKindOfClass:NSArray.class])for(id row in list)if([row isKindOfClass:NSDictionary.class])[valid addObject:row];
  s.results=valid;
  s.pageMode.selectedSegmentIndex=1;
  [s pageModeChanged];
  s.navigationItem.prompt=err?:[NSString stringWithFormat:@"%lu songs · Select song below",(unsigned long)s.results.count];
  [s.tableView reloadData];
  if(s.results.count)[s.tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]atScrollPosition:UITableViewScrollPositionTop animated:YES];
 }];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section{
 return (TMPlayer.shared.source==TMMusicSourceNetEase && _pageMode.selectedSegmentIndex==1)?_results.count:0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)ip{
 UITableViewCell *c=[tableView dequeueReusableCellWithIdentifier:@"song"]?:[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"song"];
 id s=_results[ip.row];
 c.textLabel.text=[s[@"name"]isKindOfClass:NSString.class]?s[@"name"]:@"song";
 NSArray *ar=[s[@"ar"]isKindOfClass:NSArray.class]?s[@"ar"]:@[];
 NSMutableArray *names=[NSMutableArray new];
 for(id a in ar)if([a[@"name"]isKindOfClass:NSString.class])[names addObject:a[@"name"]];
 c.detailTextLabel.text=[names componentsJoinedByString:@" / "];
 c.imageView.image=[UIImage systemImageNamed:@"music.note"];
 c.imageView.tintColor=TIOAccent();
 c.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
 c.backgroundColor=UIColor.secondarySystemGroupedBackgroundColor;
 return c;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)ip{return 64;}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)ip{
 [tableView deselectRowAtIndexPath:ip animated:YES];
 [TMPlayer.shared playSong:_results[ip.row] queue:_results];
 self.pageMode.selectedSegmentIndex=0;
 [self pageModeChanged];
 [tableView setContentOffset:CGPointMake(0,-tableView.adjustedContentInset.top) animated:YES];
}

@end

UIViewController *TMMusicController(void){
 return [[TMMusicPanel alloc]initWithStyle:UITableViewStyleInsetGrouped];
}
