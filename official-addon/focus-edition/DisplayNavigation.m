#import "DisplayNavigation.h"
@implementation TDPNavFeed {
 TDPPhoneSession *_session;NSTimeInterval(^_clock)(void);NSData *(^_render)(NSDictionary *);
 NSDictionary *_latest,*_rendered;NSData *_pixels;NSString *_note;
 BOOL _active,_initialSent,_waiting,_settled;NSUInteger _offers,_batches,_packets;
 NSTimeInterval _lastOffer,_started,_nextBatch;
}
- (instancetype)initWithSession:(TDPPhoneSession *)s clock:(NSTimeInterval(^)(void))clock renderer:(NSData *(^)(NSDictionary *))render{
 if(!s||!clock||!render)return nil;if((self=[super init])){_session=s;_clock=[clock copy];_render=[render copy];_note=@"First open the Turbo Display on the glasses, then start the Amap simulation";}return self;
}
- (BOOL)active{return _active;}
- (NSDictionary *)status{return @{@"active":@(_active),@"note":_note?:@"",@"offers":@(_offers),@"batches":@(_batches),@"rectangles":@(_packets),@"ready":@(_session.ready),@"busy":@(_session.busy),@"baseline":@(_session.hasPixelBaseline),@"initial":@(_session.frameActive),@"chunks":@(_session.completedChunks),@"lastBatchSeconds":@(_session.deltaElapsed),@"lastBatchRects":@(_session.deltaTotal),@"revision":@(_session.revision)};}
static NSDictionary *Clean(NSDictionary *d){
 if(![d isKindOfClass:NSDictionary.class]||![d[@"phase"] isEqual:@"navigating"]||![d[@"simulated"] isEqual:@YES]||![d[@"icon"] isKindOfClass:NSNumber.class])return nil;
 NSMutableDictionary *out=[@{@"phase":@"navigating",@"simulated":@YES,@"icon":d[@"icon"]} mutableCopy];
 for(NSString *k in @[@"turn",@"distance",@"road"]){NSString *s=d[k];if(![s isKindOfClass:NSString.class]||s.length>256)return nil;out[k]=[s copy];}
 for(NSString *k in @[@"hudIcon",@"crossPixels"]){id data=d[k];if(data){if(![data isKindOfClass:NSData.class]||[data length]!=6400)return nil;out[k]=[data copy];}}return out;
}
- (BOOL)start:(NSDictionary *)frame{
 if(_active||_session.busy||!Clean(frame))return NO;
 _active=YES;_initialSent=_waiting=_settled=NO;_latest=_rendered=nil;_pixels=nil;_offers=_batches=_packets=0;_started=_clock();_nextBatch=0;
 [self offer:frame];[_session setForegroundActive:YES];
 if(![_session query]){[self stop:@"Query not started; check connection and file channel"];return NO;}
 _note=@"Querying SID; loading initial screen (~20s)";return YES;
}
- (void)offer:(NSDictionary *)frame{
 if(!_active)return;NSDictionary *next=Clean(frame);
 if(!next){[self stop:@"Navigation state changed; stopped sending, use glasses button to exit"];return;}
 _lastOffer=_clock();_offers++;if(![_latest isEqual:next]){_latest=next;_settled=NO;}
}
- (void)stop:(NSString *)reason{
 if(!_active)return;_active=NO;_latest=_rendered=nil;_pixels=nil;_waiting=NO;
 // An in-flight file cannot be presumed canceled. No new writes after stop.
 [_session setForegroundActive:NO];_note=reason?:@"Stopped updates; use glasses button to exit";
}
- (void)pump{
 if(!_active)return;NSTimeInterval now=_clock();
 if(now-_started>=180){[self stop:@"The 3-minute experiment is over; please use the physical keys on your glasses to exit."];return;}
 if(now-_lastOffer>15){[self stop:@"There is no new navigation callback for more than 15 seconds; stop sending, please look at the phone and exit the old screen of the glasses"];return;}
 [_session tick];
 if(_session.busy){if(!_session.ready&&!_session.frameActive&&!_session.deltaActive&&_initialSent)[self stop:@"The connection or transmission failed and has been stopped; please use the physical key to exit."];return;}
 // QUERY completion precedes KEEPALIVE by a bounded pacing gap.
 if(!_session.ready){if(!_initialSent&&_session.sessionID&&now-_started<12)return;[self stop:_session.state];return;}
 if(!_initialSent){
  _pixels=_render(_latest);_rendered=_latest;_settled=NO;
  if(_pixels.length!=65536||![_session sendFrame:_pixels]){[self stop:@"Initial canvas not started; does not automatically retry"];return;}
  _initialSent=YES;_note=@"The initial canvas is loading; only the latest navigation is retained during this period and is not queued.";return;
 }
 if(!_session.hasPixelBaseline){[self stop:@"The pixel baseline is invalid; updates have been stopped. Please exit the glasses page and reopen it."];return;}
 if(_waiting){_waiting=NO;_batches++;_packets+=_session.completedRects;_note=@"Amap simulation guidelines have been partially submitted; only the latest status is taken, not road safety navigation";}
 if(_settled||now<_nextBatch)return;
 if(![_rendered isEqual:_latest]){_pixels=_render(_latest);_rendered=_latest;}
 if(_pixels.length!=65536||![_session sendPartialPixels:_pixels]){[self stop:@"Partial update has not started or the quota is full; please check your phone and exit the glasses page"];return;}
 _nextBatch=now+0.5;
 if(_session.deltaActive)_waiting=YES;else _settled=YES;
}
@end
