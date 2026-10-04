#import "MusicPlayer.h"
#import "MusicAPI.h"
#import "MusicBridge.h"
#import "SpotifyAPI.h"
#import "NativeNavigationUI.h"
#import "DisplayPhoneUI.h"
#import "ExperimentalOTAFlash.h"
#import "music.h"
#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>
#import <ImageIO/ImageIO.h>

static NSString *String(id v){return [v isKindOfClass:NSString.class]?v:@"";}
static NSDictionary *Song(id value){if(![value isKindOfClass:NSDictionary.class]||![value[@"id"]isKindOfClass:NSNumber.class])return nil;id album=value[@"al"]?:value[@"album"];if(![album isKindOfClass:NSDictionary.class])album=@{};id artists=value[@"ar"]?:value[@"artists"];NSMutableArray *names=[NSMutableArray new];if([artists isKindOfClass:NSArray.class])for(id a in artists)if([a isKindOfClass:NSDictionary.class]&&String(a[@"name"]).length)[names addObject:a[@"name"]];return @{@"id":value[@"id"],@"name":String(value[@"name"]),@"artist":String(value[@"artist"]).length?value[@"artist"]:[names componentsJoinedByString:@" / "],@"cover":String(value[@"cover"]).length?value[@"cover"]:String(album[@"picUrl"]),@"duration":@([value[@"dt"]?:value[@"duration"] doubleValue])};}
static NSURL *MediaURL(NSString *s){NSURLComponents *c=[NSURLComponents componentsWithString:s];NSString *h=c.host.lowercaseString;if(!h||!( [h hasSuffix:@".126.net"]||[h hasSuffix:@".163.com"]||[h isEqual:@"music.163.com"])||c.user||c.password)return nil;if([c.scheme isEqual:@"http"])c.scheme=@"https";return [c.scheme isEqual:@"https"]?c.URL:nil;}
static NSData *Gray(UIImage *image){if(!image.CGImage)return nil;NSMutableData *d=[NSMutableData dataWithLength:TM_COVER_BYTES];CGColorSpaceRef cs=CGColorSpaceCreateDeviceGray();CGContextRef ctx=CGBitmapContextCreate(d.mutableBytes,144,144,8,144,cs,kCGImageAlphaNone);CGColorSpaceRelease(cs);if(!ctx)return nil;CGContextSetInterpolationQuality(ctx,kCGInterpolationHigh);CGContextDrawImage(ctx,CGRectMake(0,0,144,144),image.CGImage);CGContextRelease(ctx);return d;}

@implementation TMPlayer{
 AVPlayer *_player;id _timeObserver;NSArray *_queue,*_lyrics;NSDictionary *_song;UIImage *_cover;NSData *_gray;NSString *_status;TMMusicBridge *_bridge;NSTimer *_timer;
 NSUInteger _ticket,_sentTicket;uint32_t _request;BOOL _glasses;NSInteger _mode;double _duration;id _endObserver;BOOL _wantsPlay;
 TMMusicSource _source;
}

+ (instancetype)shared{static TMPlayer *p;static dispatch_once_t once;dispatch_once(&once,^{p=[self new];});return p;}

- (instancetype)init{if((self=[super init])){
 _player=[AVPlayer new];_bridge=[TMMusicBridge new];
 _mode=[NSUserDefaults.standardUserDefaults integerForKey:@"TurboMusicDisplayModeV1"];_mode=MAX(0,MIN(2,_mode));
 _glasses=[NSUserDefaults.standardUserDefaults boolForKey:@"TurboMusicGlassesV1"];
 if([NSUserDefaults.standardUserDefaults objectForKey:@"TurboMusicSourceV2"]!=nil){
  _source=(TMMusicSource)[NSUserDefaults.standardUserDefaults integerForKey:@"TurboMusicSourceV2"];
 }else{
  _source=TMMusicSourceSpotify; // Default to Spotify!
 }
 _status=_source==TMMusicSourceSpotify?@"Spotify Controller ready":@"Search for songs, or play the local verification song first";

 __weak typeof(self) weak=self;
 _bridge.snapshot=^NSDictionary *{
  TMPlayer *s=weak;if(!s)return @{};
  if(s->_source==TMMusicSourceSpotify){
   SpotifyTrack *t=SpotifyAPI.shared.currentTrack;
   if(!t)return @{@"title":@"",@"artist":@"",@"position":@0,@"duration":@0,@"playing":@NO,@"mode":@(s.mode),@"request":@(s->_request)};
   return @{@"title":t.name?:@"",@"artist":t.artist?:@"",@"position":@((uint32_t)(t.progressMs)),@"duration":@((uint32_t)(t.durationMs)),@"playing":@(t.isPlaying),@"mode":@(s.mode),@"request":@(s->_request)};
  }
  return @{@"title":s.song[@"name"]?:@"",@"artist":s.song[@"artist"]?:@"",@"position":@((uint32_t)(s.position*1000)),@"duration":@((uint32_t)(s.duration*1000)),@"playing":@(s.playing),@"mode":@(s.mode),@"request":@(s->_request)};
 };

 _bridge.command=^(NSDictionary *q){
  TMPlayer *s=weak;if(!s)return;
  unsigned e=[q[@"event"]unsignedIntValue];
  s->_request=[q[@"request"]unsignedIntValue];
  if(e==TM_VIEW_CLOSED)return;
  if(s->_source==TMMusicSourceSpotify){
   if(e==TM_PLAY)[SpotifyAPI.shared playWithCompletion:nil];
   else if(e==TM_PAUSE)[SpotifyAPI.shared pauseWithCompletion:nil];
   else if(e==TM_NEXT)[SpotifyAPI.shared nextTrackWithCompletion:nil];
   else if(e==TM_PREV)[SpotifyAPI.shared previousTrackWithCompletion:nil];
   else if(e==TM_RESUME){
    s->_glasses=YES;
    [NSUserDefaults.standardUserDefaults setBool:YES forKey:@"TurboMusicGlassesV1"];
    if(SpotifyAPI.shared.hasAuth&&SpotifyAPI.shared.currentTrack){
     [SpotifyAPI.shared playWithCompletion:nil];
     [s showOnGlasses];
    }else if(SpotifyAPI.shared.hasAuth){
     [SpotifyAPI.shared playWithCompletion:nil];
     [SpotifyAPI.shared startPolling];
    }else{
     [s demo];
    }
   }
   return;
  }
  if(e==TM_RESUME){s->_glasses=YES;[NSUserDefaults.standardUserDefaults setBool:YES forKey:@"TurboMusicGlassesV1"];if(s->_song){[s play:YES];[s showOnGlasses];}else {NSDictionary *last=[NSUserDefaults.standardUserDefaults dictionaryForKey:@"TurboMusicLastSongV1"];if(last){[s playSong:last queue:@[last]];}else [s demo];}return;}
  if(e==TM_PLAY)[s play:YES];else if(e==TM_PAUSE)[s play:NO];else if(e==TM_NEXT)[s step:1];else if(e==TM_PREV)[s step:-1];
 };

 _timer=[NSTimer scheduledTimerWithTimeInterval:.15 repeats:YES block:^(NSTimer *t){TMPlayer *s=weak;if(s)[s->_bridge pump];}];
 _timeObserver=[_player addPeriodicTimeObserverForInterval:CMTimeMakeWithSeconds(.25,600) queue:dispatch_get_main_queue() usingBlock:^(CMTime time){TMPlayer *s=weak;if(s&&s.source==TMMusicSourceNetEase)[s refresh];}];
 [_player addObserver:self forKeyPath:@"timeControlStatus" options:0 context:NULL];[_player addObserver:self forKeyPath:@"currentItem.status" options:0 context:NULL];
 [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(interrupt:) name:AVAudioSessionInterruptionNotification object:nil];
 [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(route:) name:AVAudioSessionRouteChangeNotification object:nil];

 MPRemoteCommandCenter *r=MPRemoteCommandCenter.sharedCommandCenter;
 [r.playCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e){dispatch_async(dispatch_get_main_queue(),^{[weak play:YES];});return MPRemoteCommandHandlerStatusSuccess;}];
 [r.pauseCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e){dispatch_async(dispatch_get_main_queue(),^{[weak play:NO];});return MPRemoteCommandHandlerStatusSuccess;}];
 [r.nextTrackCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e){dispatch_async(dispatch_get_main_queue(),^{[weak step:1];});return MPRemoteCommandHandlerStatusSuccess;}];
 [r.previousTrackCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e){dispatch_async(dispatch_get_main_queue(),^{[weak step:-1];});return MPRemoteCommandHandlerStatusSuccess;}];

 // Wire Spotify Callbacks
 SpotifyAPI.shared.onTrackChanged=^(SpotifyTrack * _Nullable track){
  TMPlayer *s=weak;if(!s||s->_source!=TMMusicSourceSpotify)return;
  if(track&&s->_glasses){
   s->_sentTicket=0;
   [s->_bridge openWithCover:SpotifyAPI.shared.currentCoverGray lyrics:SpotifyAPI.shared.currentLyrics];
  }
  [s refresh];
 };
 SpotifyAPI.shared.onPlaybackStateChanged=^(BOOL isPlaying, double positionSec){
  TMPlayer *s=weak;if(!s||s->_source!=TMMusicSourceSpotify)return;
  [s->_bridge changed];
  [s refresh];
 };
 SpotifyAPI.shared.onStatusChanged=^(NSString *status){
  TMPlayer *s=weak;if(!s||s->_source!=TMMusicSourceSpotify)return;
  [s refresh];
 };

 if(_source==TMMusicSourceSpotify&&SpotifyAPI.shared.hasAuth){
  [SpotifyAPI.shared startPolling];
 }
 }return self;}

- (TMMusicSource)source{return _source;}
- (void)setSource:(TMMusicSource)source{
 if(_source==source)return;
 if(_source==TMMusicSourceNetEase&&self.playing)[self play:NO];
 _source=source;
 [NSUserDefaults.standardUserDefaults setInteger:source forKey:@"TurboMusicSourceV2"];
 if(_source==TMMusicSourceSpotify){
  [SpotifyAPI.shared startPolling];
  if(_glasses&&SpotifyAPI.shared.currentTrack)[self showOnGlasses];
 }else{
  [SpotifyAPI.shared stopPolling];
  if(_glasses&&_song)[self showOnGlasses];
 }
 [self refresh];
}

- (NSDictionary *)song{
 if(_source==TMMusicSourceSpotify){
  SpotifyTrack *t=SpotifyAPI.shared.currentTrack;
  if(!t)return nil;
  return @{@"id":t.trackId?:@"",@"name":t.name?:@"",@"artist":t.artist?:@"",@"cover":t.coverURL?:@"",@"duration":@(t.durationMs)};
 }
 return _song;
}

- (NSArray *)lyrics{
 if(_source==TMMusicSourceSpotify)return SpotifyAPI.shared.currentLyrics?:@[];
 return _lyrics?:@[];
}

- (UIImage *)cover{
 if(_source==TMMusicSourceSpotify)return SpotifyAPI.shared.currentCover;
 return _cover;
}

- (BOOL)playing{
 if(_source==TMMusicSourceSpotify)return SpotifyAPI.shared.currentTrack.isPlaying;
 return _player.timeControlStatus==AVPlayerTimeControlStatusPlaying;
}

- (double)position{
 if(_source==TMMusicSourceSpotify)return SpotifyAPI.shared.currentTrack.progressMs/1000.0;
 double n=CMTimeGetSeconds(_player.currentTime);return isfinite(n)?MAX(0,n):0;
}

- (double)duration{
 if(_source==TMMusicSourceSpotify)return SpotifyAPI.shared.currentTrack.durationMs/1000.0;
 double n=CMTimeGetSeconds(_player.currentItem.duration);return isfinite(n)&&n>0?n:_duration;
}

- (NSString *)status{
 if(_source==TMMusicSourceSpotify)return SpotifyAPI.shared.statusNote?:@"";
 return _status?:@"";
}

- (NSString *)bridgeStatus{
 if([TDPPhoneMusicStatus()[@"active"] boolValue]){
  return TDPPhoneMusicStatus()[@"note"];
 }
 return _bridge.note;
}
- (NSInteger)mode{return _mode;}- (void)setMode:(NSInteger)m{_mode=MAX(0,MIN(2,m));[NSUserDefaults.standardUserDefaults setInteger:_mode forKey:@"TurboMusicDisplayModeV1"];}
- (BOOL)glasses{return _glasses;}- (void)setGlasses:(BOOL)v{_glasses=v;[NSUserDefaults.standardUserDefaults setBool:v forKey:@"TurboMusicGlassesV1"];if(v)[self showOnGlasses];else [_bridge close];}

- (void)observeValueForKeyPath:(NSString *)k ofObject:(id)object change:(NSDictionary *)change context:(void *)context{
 if(_source!=TMMusicSourceNetEase)return;
 if(_player.currentItem.status==AVPlayerItemStatusFailed){_status=@"Playback failed: Media expired, re-select song.";_wantsPlay=NO;}
 else if(_player.timeControlStatus==AVPlayerTimeControlStatusWaitingToPlayAtSpecifiedRate)_status=@"Buffering (lyric clock paused)";
 else if(self.playing)_status=@"Playing";
 [_bridge changed];[self refresh];
}

- (void)interrupt:(NSNotification *)n{if(_source==TMMusicSourceNetEase&&[n.userInfo[AVAudioSessionInterruptionTypeKey]unsignedIntegerValue]==AVAudioSessionInterruptionTypeBegan){[self play:NO];_status=@"Audio interrupted by other tasks.";}}
- (void)route:(NSNotification *)n{if(_source==TMMusicSourceNetEase&&[n.userInfo[AVAudioSessionRouteChangeReasonKey]unsignedIntegerValue]==AVAudioSessionRouteChangeReasonOldDeviceUnavailable){[self play:NO];_status=@"Audio device disconnected, paused";}}

- (void)play:(BOOL)v{
 if(_source==TMMusicSourceSpotify){
  if(v)[SpotifyAPI.shared playWithCompletion:nil];
  else [SpotifyAPI.shared pauseWithCompletion:nil];
  return;
 }
 if(!v){_wantsPlay=NO;[_player pause];_status=@"Paused";[self refresh];return;}
 if(!_player.currentItem){_status=@"Please select a song first";return;}
 NSError *error=nil;AVAudioSession *audio=AVAudioSession.sharedInstance;
 if(![audio setCategory:AVAudioSessionCategoryPlayback mode:AVAudioSessionModeDefault options:0 error:&error]||![audio setActive:YES error:&error]){_status=@"Unable to obtain audio output";return;}
 _wantsPlay=YES;[_player play];
}

- (void)seek:(double)s{
 if(_source==TMMusicSourceSpotify){
  [SpotifyAPI.shared seekToSeconds:s completion:nil];
  return;
 }
 if(!isfinite(s)||!_player.currentItem)return;
 [_player seekToTime:CMTimeMakeWithSeconds(MAX(0,MIN(self.duration,s)),600) toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:^(BOOL done){dispatch_async(dispatch_get_main_queue(),^{[self->_bridge changed];});}];
}

- (void)step:(NSInteger)d{
 if(_source==TMMusicSourceSpotify){
  if(d>0)[SpotifyAPI.shared nextTrackWithCompletion:nil];
  else [SpotifyAPI.shared previousTrackWithCompletion:nil];
  return;
 }
 if(!_queue.count)return;
 NSUInteger index=[_queue indexOfObjectPassingTest:^BOOL(id v,NSUInteger i,BOOL *stop){return [v[@"id"]isEqual:self->_song[@"id"]];}];
 if(index==NSNotFound)index=0;
 NSInteger next=((NSInteger)index+d+(NSInteger)_queue.count)%(NSInteger)_queue.count;
 [self playSong:_queue[next] queue:_queue];
}

- (void)refresh{
 NSDictionary *s=self.song;if(!s)return;
 NSMutableDictionary *now=[@{MPMediaItemPropertyTitle:s[@"name"]?:@"",MPMediaItemPropertyArtist:s[@"artist"]?:@"",MPMediaItemPropertyPlaybackDuration:@(self.duration),MPNowPlayingInfoPropertyElapsedPlaybackTime:@(self.position),MPNowPlayingInfoPropertyPlaybackRate:@(self.playing?1:0)}mutableCopy];
 if(self.cover){UIImage *im=self.cover;now[MPMediaItemPropertyArtwork]=[[MPMediaItemArtwork alloc]initWithBoundsSize:im.size requestHandler:^UIImage *(CGSize sz){return im;}];}
 MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo=now;
}

- (void)installURL:(NSURL *)url ticket:(NSUInteger)ticket{
 if(_source!=TMMusicSourceNetEase||ticket!=_ticket)return;
 if(_endObserver)[NSNotificationCenter.defaultCenter removeObserver:_endObserver];
 AVPlayerItem *item=[AVPlayerItem playerItemWithURL:url];
 [_player replaceCurrentItemWithPlayerItem:item];
 __weak typeof(self) weak=self;
 _endObserver=[NSNotificationCenter.defaultCenter addObserverForName:AVPlayerItemDidPlayToEndTimeNotification object:item queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){
  TMPlayer *s=weak;if(!s||ticket!=s->_ticket)return;
  if(s->_queue.count>1)[s step:1];else [s play:NO];
 }];
 [self play:YES];if(_glasses)[self showOnGlasses];
}

- (void)playSong:(NSDictionary *)value queue:(NSArray *)queue{
 if(_source==TMMusicSourceSpotify){
  [self setSource:TMMusicSourceNetEase];
 }
 NSDictionary *s=Song(value);if(!s)return;
 NSUInteger ticket=++_ticket;[_player pause];_song=s;
 NSMutableArray *q=[NSMutableArray new];for(id v in queue){id x=Song(v);if(x)[q addObject:x];}
 _queue=q.count?q:@[s];_duration=[s[@"duration"]doubleValue]/1000;_cover=nil;_gray=nil;_lyrics=@[];
 _status=@"Obtaining playback address";[NSUserDefaults.standardUserDefaults setObject:s forKey:@"TurboMusicLastSongV1"];
 [[TMMusicAPI shared]request:@"/api/song/enhance/player/url/v1" payload:@{@"ids":[NSString stringWithFormat:@"[%@]",s[@"id"]],@"level":@"standard",@"encodeType":@"aac"} eapi:YES done:^(NSDictionary *j,NSString *err){
  if(ticket!=self->_ticket)return;NSArray *a=[j[@"data"]isKindOfClass:NSArray.class]?j[@"data"]:@[];NSDictionary *v=[a.firstObject isKindOfClass:NSDictionary.class]?a.firstObject:@{};NSURL *url=MediaURL(String(v[@"url"]));
  if(err||!url){self->_status=err?:@"Song not available";return;}
  self->_status=@"Playing";[self installURL:url ticket:ticket];
 }];
 [[TMMusicAPI shared]request:@"/api/song/lyric" payload:@{@"id":s[@"id"],@"lv":@-1,@"kv":@-1,@"tv":@-1} eapi:NO done:^(NSDictionary *j,NSString *err){
  if(ticket!=self->_ticket)return;id l=[j[@"lrc"]isKindOfClass:NSDictionary.class]?j[@"lrc"]:@{};
  self->_lyrics=TMParseLRC(String(l[@"lyric"]));
  if(!self->_lyrics.count)self->_lyrics=@[@{@"ms":@0,@"text":err?@"Failed to obtain lyrics":@"Pure Music"}];
  [self->_bridge assetsCover:nil lyrics:self->_lyrics];
 }];
 NSURL *cover=MediaURL(s[@"cover"]);if(cover){[[NSURLSession.sharedSession dataTaskWithURL:cover completionHandler:^(NSData *d,NSURLResponse *r,NSError *e){
  if(e||d.length>8*1024*1024)return;CGImageSourceRef source=CGImageSourceCreateWithData((__bridge CFDataRef)d,NULL);if(!source)return;
  CGImageRef image=CGImageSourceCreateThumbnailAtIndex(source,0,(__bridge CFDictionaryRef)@{(__bridge id)kCGImageSourceCreateThumbnailFromImageAlways:@YES,(__bridge id)kCGImageSourceThumbnailMaxPixelSize:@360,(__bridge id)kCGImageSourceCreateThumbnailWithTransform:@YES});CFRelease(source);
  UIImage *im=image?[UIImage imageWithCGImage:image]:nil;if(image)CGImageRelease(image);NSData *gray=Gray(im);
  dispatch_async(dispatch_get_main_queue(),^{if(ticket!=self->_ticket)return;self->_cover=im;self->_gray=gray;[self->_bridge assetsCover:gray lyrics:nil];});
 }]resume];}
}

- (void)showOnGlasses{
 if(!TNVPauseForOTA()||[TIOOTAFlashStatus()[@"stage"]unsignedIntegerValue]){
  _status=@"Navigation or firmware transfer is active; please stop it first";
  return;
 }
 if(_source==TMMusicSourceSpotify){
  SpotifyTrack *t=SpotifyAPI.shared.currentTrack;
  if(!t)return;
  [_bridge openWithCover:SpotifyAPI.shared.currentCoverGray lyrics:SpotifyAPI.shared.currentLyrics];
  return;
 }
 if(!_song)return;
 if(_sentTicket==_ticket&&_bridge.active)[_bridge reopen];
 else{_sentTicket=_ticket;[_bridge openWithCover:_gray lyrics:_lyrics];}
}

- (void)hideGlasses{
 TDPPhoneMusicStop();
 [_bridge close];
}

- (void)demo{
 [self setSource:TMMusicSourceNetEase];
 NSUInteger ticket=++_ticket;_song=@{@"id":@0,@"name":@"Night Flight · Local Test 7392",@"artist":@"Turbo Lab·Synthesized test tone",@"duration":@90000};_queue=@[];_duration=90;
 _lyrics=@[@{@"ms":@0,@"text":@"Music screen verification 7392"},@{@"ms":@5000,@"text":@"The city lights gradually fade away"},@{@"ms":@10000,@"text":@"Slowly move forward along the starlight"},@{@"ms":@15000,@"text":@"Let the evening breeze take me to tomorrow"},@{@"ms":@25000,@"text":@"Knob to switch songs·Button to play and pause"},@{@"ms":@35000,@"text":@"Close the screen and continue the music"},@{@"ms":@55000,@"text":@"Mobile phone drag progress, Lyrics Sync"},@{@"ms":@75000,@"text":@"Verification ended 8642"}];
 UIGraphicsImageRendererFormat *f=[UIGraphicsImageRendererFormat defaultFormat];f.scale=1;
 _cover=[[[UIGraphicsImageRenderer alloc]initWithSize:CGSizeMake(288,288) format:f]imageWithActions:^(UIGraphicsImageRendererContext *c){
  [[UIColor colorWithRed:.12 green:.09 blue:.07 alpha:1]setFill];UIRectFill(CGRectMake(0,0,288,288));
  [[UIColor colorWithRed:1 green:.47 blue:.16 alpha:1]setFill];[[UIBezierPath bezierPathWithOvalInRect:CGRectMake(44,30,200,200)]fill];
  [@"TURBO LAB" drawAtPoint:CGPointMake(58,247) withAttributes:@{NSFontAttributeName:[UIFont monospacedSystemFontOfSize:22 weight:UIFontWeightMedium],NSForegroundColorAttributeName:UIColor.whiteColor}];
 }];
 _gray=Gray(_cover);
 NSURL *url=[NSURL fileURLWithPath:[NSTemporaryDirectory()stringByAppendingPathComponent:@"turbo-music-original-test.wav"]];
 dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
  NSUInteger samples=22050*90;NSMutableData *wav=[NSMutableData dataWithLength:44+samples*2];uint8_t *b=wav.mutableBytes;
  memcpy(b,"RIFF",4);uint32_t size=(uint32_t)wav.length-8;memcpy(b+4,&size,4);memcpy(b+8,"WAVEfmt ",8);
  uint32_t fmt=16,rate=22050,bytes=44100;uint16_t pcm=1,channels=1,align=2,bits=16;
  memcpy(b+16,&fmt,4);memcpy(b+20,&pcm,2);memcpy(b+22,&channels,2);memcpy(b+24,&rate,4);memcpy(b+28,&bytes,4);
  memcpy(b+32,&align,2);memcpy(b+34,&bits,2);memcpy(b+36,"data",4);size=(uint32_t)samples*2;memcpy(b+40,&size,4);
  int16_t *out=(void *)(b+44);for(NSUInteger i=0;i<samples;i++){double t=(double)i/22050,beat=fmod(t,.5),freq=220*pow(2,((int)t%4)*2.0/12);out[i]=(int16_t)(1800*sin(2*M_PI*freq*t)*exp(-beat*7));}
  [wav writeToURL:url options:NSDataWritingAtomic error:nil];
  dispatch_async(dispatch_get_main_queue(),^{[self installURL:url ticket:ticket];});
 });
}

- (BOOL)consume:(NSDictionary *)e{return [_bridge consume:e];}
- (BOOL)otaIdle{return !_bridge.busy&&!_bridge.active;}
- (void)pauseForVoice{if(self.playing){[self play:NO];_status=@"Voice session started, music paused";}}
@end

BOOL TMMusicConsume(NSDictionary *e){return [[TMPlayer shared]consume:e];}
BOOL TMMusicPauseForOTA(void){return [[TMPlayer shared]otaIdle];}
void TMMusicPauseForVoice(void){[[TMPlayer shared]pauseForVoice];}
