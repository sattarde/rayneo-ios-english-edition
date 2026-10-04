#import "DisplayPhoneSession.h"
#import "DisplayPhoneUI.h"
#import "display_client.h"
#import "display_carrier.h"
#import "DisplayDiagnostics.h"
#import "DisplayDelta.h"
static uint32_t Read32(const uint8_t *p){return p[0]|((uint32_t)p[1]<<8)|((uint32_t)p[2]<<16)|((uint32_t)p[3]<<24);}
@implementation TDPPhoneSession {
 NSString *_device,*_state,*_task,*_nativeTask; NSMutableSet *_ownedTasks,*_nativeTasks;
 NSMutableArray *_earlyFiles;
 NSTimeInterval(^_clock)(void); TDPSend _sender; TDPDisplayReplyObserver *_observer;
 NSData *_packet,*_frame; NSTimeInterval _deadline,_nextSend,_renewAt,_frameDeadline,_frameStarted,_frameEnded;
 uint32_t _counter,_tx,_base; NSUInteger _offset,_chunkLength,_completedChunks;
 BOOL _fileBusy,_apAck,_foreground,_needsRenew,_pumpQueued,_hasFrameTiming; TDPReply _ack;
 NSMutableData *_knownPixels;NSData *_deltaTarget;TDPDeltaPlan _delta;
 uint32_t _baselineSID,_baselineRevision;unsigned _deltaIndex;
 NSTimeInterval _deltaStarted,_deltaEnded,_deltaDeadline,_packetStarted;BOOL _hasDeltaTiming;
}
- (instancetype)initWithDevice:(NSString *)device clock:(NSTimeInterval(^)(void))clock sender:(TDPSend)sender {
 if(!device.length||!clock||!sender)return nil;
 if((self=[super init])){_device=[device copy];_clock=[clock copy];_sender=[sender copy];_ownedTasks=[NSMutableSet new];_nativeTasks=[NSMutableSet new];_earlyFiles=[NSMutableArray new];
 _observer=[[TDPDisplayReplyObserver alloc]initWithDevice:device clock:clock];_counter=arc4random_uniform(UINT32_MAX/2)+1;_tx=_counter;_state=@"Waiting for query TDP1; judging firmware capabilities with real receipts";}
 return self;
}
- (NSString *)state{return _state;}
- (BOOL)ready{return _observer.ready&&!_needsRenew;}
- (BOOL)busy{return _packet||_fileBusy||_frame!=nil||_deltaTarget!=nil;}
- (uint32_t)sessionID{return _observer.sessionID;}
- (uint32_t)revision{return _observer.revision;}
- (NSUInteger)completedChunks{return _completedChunks;}
- (BOOL)frameActive{return _frame!=nil;}
- (NSTimeInterval)frameElapsed{return _hasFrameTiming?MAX(0,(_frame?_clock():_frameEnded)-_frameStarted):0;}
- (BOOL)deltaActive{return _deltaTarget!=nil;}
- (BOOL)hasPixelBaseline{return self.ready&&_knownPixels.length==TDP_PIXELS&&_baselineSID==self.sessionID&&_baselineRevision==self.revision;}
- (NSData *)knownPixels{return [_knownPixels copy];}
- (NSUInteger)deltaTotal{return _delta.count;}
- (NSUInteger)completedRects{return _deltaIndex;}
- (NSTimeInterval)deltaElapsed{return _hasDeltaTiming?MAX(0,(_deltaTarget?_clock():_deltaEnded)-_deltaStarted):0;}
- (void)publish:(NSString *)s{_state=[s copy];TDPDiagRecord(@"state",@{@"packet":@(_packet!=nil),@"fileBusy":@(_fileBusy),@"apAck":@(_apAck),@"ready":@(self.ready),@"sid":@(self.sessionID),@"revision":@(self.revision),@"foreground":@(_foreground)});if(self.changed)self.changed();}
- (uint32_t)request{if(_counter==UINT32_MAX)return 0;return ++_counter;}
- (void)fail:(NSString *)s{
 if(_frame){_frameEnded=_clock();TDPDiagRecord(@"frame_stop",@{@"chunks":@(_completedChunks),@"elapsedMs":@((uint64_t)(self.frameElapsed*1000))});}
 if(_deltaTarget){_deltaEnded=_clock();TDPDiagRecord(@"delta_stop",@{@"chunks":@(_deltaIndex),@"elapsedMs":@((uint64_t)(self.deltaElapsed*1000))});}
 _packet=nil;_frame=nil;_deltaTarget=nil;_knownPixels=nil;_needsRenew=NO;
 _fileBusy=NO;
 [_ownedTasks removeAllObjects];
 [_nativeTasks removeAllObjects];
 [_observer disconnected];
 [self publish:s];
}
// At most one queued wake; never recursively enter the SDK from its callback.
// tick rechecks foreground, packet/file ownership and frame deadline.
- (void)queueFramePump {
 if(_pumpQueued||(!_frame&&!_deltaTarget)||!_foreground)return;_pumpQueued=YES;
 __weak typeof(self) weak=self;
 dispatch_async(dispatch_get_main_queue(),^{TDPPhoneSession *s=weak;if(!s)return;s->_pumpQueued=NO;[s tick];});
}
- (void)disconnect{
 NSAssert(NSThread.isMainThread,@"main only");
 _foreground=NO;
 _fileBusy=NO;
 [_ownedTasks removeAllObjects];
 [_nativeTasks removeAllObjects];
 [self fail:@"The connection has expired; waiting to be requeried. Files whose end is not confirmed will not be resent."];
}
- (BOOL)send:(NSData *)packet query:(BOOL)query {
 if(!packet||_packet||_fileBusy||_ownedTasks.count>=512||!_foreground)return NO;
 const uint8_t *b=packet.bytes;
 if(!query&&![_observer expectRequest:Read32(b+12) session:Read32(b+8)])return NO;
 _packet=[packet copy];_task=NSUUID.UUID.UUIDString;_nativeTask=nil;[_earlyFiles removeAllObjects];[_ownedTasks addObject:_task];_fileBusy=YES;_apAck=NO;_packetStarted=_clock();_deadline=_packetStarted+5;
 NSString *task=_task;__weak typeof(self) weak=self;
 TDPDiagRecord(@"send",@{@"op":@(b[5]),@"bytes":@(packet.length),@"request":@(Read32(b+12))});
 [self publish:_frame?[NSString stringWithFormat:@"Frame %lu / 139 blocks · %.1f s; waiting for ACKs",(unsigned long)_completedChunks,self.frameElapsed]:@"Submitting via mobile phone; waiting for the final status of the document and the receipt of the glasses agreement"];
 _sender(_packet,task,^(BOOL submitted,NSString *nativeTask){
  NSAssert(NSThread.isMainThread,@"main only");TDPPhoneSession *s=weak;
  if(!s||![s->_task isEqual:task]||s->_nativeTask)return;
  BOOL valid=submitted&&[nativeTask isKindOfClass:NSString.class]&&nativeTask.length>0&&nativeTask.length<=256&&![s->_nativeTasks containsObject:nativeTask];
  TDPDiagRecord(@"task_bound",@{@"success":@(valid),@"taskMatch":@([task isEqual:nativeTask])});
  // SDK rejection is not proof that a queued file never started.
  if(!valid){[s->_earlyFiles removeAllObjects];[s fail:@"Task ID not confirmed: keep task, check file receipts"];return;}
  s->_nativeTask=[nativeTask copy];[s->_nativeTasks addObject:nativeTask];
  NSArray *early=[s->_earlyFiles copy];[s->_earlyFiles removeAllObjects];
  for(NSDictionary *event in early)[s consumeEvent:event];
 });return YES;
}
- (BOOL)query {
 NSAssert(NSThread.isMainThread,@"main only");
 TDPDiagRecord(@"query",@{@"busy":@(self.busy),@"foreground":@(_foreground)});
 if(self.busy||!_foreground||_ownedTasks.count>=512)return NO;
 _knownPixels=nil;[_observer disconnected];_needsRenew=YES;NSData *p=[_observer makeQuery];
 if(![self send:p query:YES]){[self fail:@"Query not submitted"];return NO;}return YES;
}
- (BOOL)control:(unsigned)op {
 uint8_t p[32];size_t n=tdp_client_control(p,sizeof p,op,_observer.sessionID,[self request],_observer.revision);
 return n&&[self send:[NSData dataWithBytes:p length:n] query:NO];
}
- (BOOL)closePage {if(self.busy||!self.ready)return NO;return [self control:TDP_CLOSE];}
- (BOOL)sendTestRect {
 if(self.busy||!self.ready||_clock()<_nextSend)return NO;
 uint8_t pixels[400],p[512];for(unsigned y=0;y<20;y++)for(unsigned x=0;x<20;x++)pixels[y*20+x]=(x==y||x+y==19)?255:60;
 size_t n=tdp_client_rect(p,sizeof p,self.sessionID,[self request],self.revision,4,4,20,20,pixels,sizeof pixels);
 return n&&[self send:[NSData dataWithBytes:p length:n] query:NO];
}
- (BOOL)sendFrame:(NSData *)gray {
 if(self.busy||!self.ready||!_foreground||gray.length!=TDP_PIXELS||_tx==UINT32_MAX||_ownedTasks.count>368)return NO;
 _frame=[gray copy];_base=self.revision;_tx++;_offset=0;_completedChunks=0;_frameStarted=_clock();_frameEnded=0;_hasFrameTiming=YES;_frameDeadline=_frameStarted+25;
 TDPDiagRecord(@"frame_start",@{@"bytes":@(gray.length),@"chunks":@0,@"revision":@(self.revision)});
 uint8_t p[512];size_t n=tdp_client_begin(p,sizeof p,self.sessionID,[self request],_base,_tx,tdp_crc(gray.bytes,gray.length));
 if(!n||![self send:[NSData dataWithBytes:p length:n] query:NO]){[self fail:@"The entire frame has not been submitted and has been stopped; requery and try again."];return NO;}return YES;
}
- (BOOL)sendChangedPixels:(NSData *)gray {return [self sendPixels:gray partial:NO];}
- (BOOL)sendPartialPixels:(NSData *)gray {return [self sendPixels:gray partial:YES];}
- (BOOL)sendPixels:(NSData *)gray partial:(BOOL)partial {
 if(self.busy||!_foreground)return NO;
 if(!self.hasPixelBaseline){[self publish:@"No confirmed pixel baseline; first query and successfully send the full canvas once. Do not guess the old picture after reconnecting/requerying"];return NO;}
 TDPDeltaPlan plan;int result=partial?tdp_delta_batch(_knownPixels.bytes,_knownPixels.length,gray.bytes,gray.length,TDP_DELTA_LIMIT,&plan):tdp_delta_plan(_knownPixels.bytes,_knownPixels.length,gray.bytes,gray.length,&plan);
 if(partial&&result==1)result=0;
 if(result){[self publish:result==1?@"More than 64 small areas have changed; it has not been sent this time, please manually select the entire image to update":@"The canvas is invalid; not sent this time"];return NO;}
 if(!plan.count){_delta=plan;_deltaIndex=0;_deltaStarted=_deltaEnded=_clock();_hasDeltaTiming=YES;[self publish:@"The picture does not change and no Bluetooth data is sent."];return YES;}
 if(_ownedTasks.count+plan.count>512){[self publish:@"The file quota for this session is insufficient and partial update has not been started."];return NO;}
 _delta=plan;_deltaIndex=0;_deltaTarget=[gray copy];_deltaStarted=_clock();_deltaEnded=0;_hasDeltaTiming=YES;_deltaDeadline=_deltaStarted+10;
 TDPDiagRecord(@"delta_start",@{@"chunks":@(plan.count),@"bytes":@(plan.pixels+40*plan.count),@"revision":@(self.revision)});
 [self nextDeltaPacket];return _deltaTarget!=nil;
}
- (void)nextDeltaPacket {
 if(!_deltaTarget||_deltaIndex>=_delta.count)return;
 if(_clock()>=_deltaDeadline){[self fail:@"The partial update took more than 10 seconds and has stopped; the picture may only be partially updated and the baseline needs to be rebuilt."];return;}
 TDPDeltaRect r=_delta.rects[_deltaIndex];uint8_t pixels[512],p[576];
 for(unsigned row=0;row<r.h;row++)memcpy(pixels+row*r.w,(const uint8_t *)_deltaTarget.bytes+(r.y+row)*512+r.x,r.w);
 size_t n=tdp_client_rect(p,sizeof p,self.sessionID,[self request],self.revision,r.x,r.y,r.w,r.h,pixels,r.w*r.h);
 if(!n||![self send:[NSData dataWithBytes:p length:n] query:NO])[self fail:@"Local update not committed; stopped and cleared pixel baseline"];
}
- (void)nextFramePacket {
 uint8_t p[512];size_t n=0;
 if(_clock()>=_frameDeadline){[self fail:@"The entire frame timed out and was not sent further; the glasses transaction was discarded after timeout. Try again after querying again"];return;}
 if(_offset<TDP_PIXELS){_chunkLength=MIN((NSUInteger)_observer.maxPixelsPerPacket,TDP_PIXELS-_offset);
 n=tdp_client_chunk(p,sizeof p,self.sessionID,[self request],_base,_tx,(uint32_t)_offset,(const uint8_t *)_frame.bytes+_offset,_chunkLength);
 }else n=tdp_client_finish(p,sizeof p,TDP_FRAME_COMMIT,self.sessionID,[self request],_base,_tx);
 if(!n||![self send:[NSData dataWithBytes:p length:n] query:NO])[self fail:@"Unable to continue framing; stopped, no resubmission"];
}
- (void)finishIfComplete {
 if(!_packet||_fileBusy||!_apAck)return;
 // The file ACK can be the last callback. Do not let a late file terminal
 // bypass the deadlines already enforced for AP replies and timer wakes.
 if((_deltaTarget&&_clock()>=_deltaDeadline)||(_frame&&_clock()>=_frameDeadline)||_clock()>=_deadline){[self fail:@"Timed out on double receipt completion; result unknown, clears pixel baseline and does not continue sending"];return;}
 NSData *finished=_packet;unsigned op=((const uint8_t *)finished.bytes)[5];_packet=nil;
 if(_task){[_ownedTasks removeObject:_task];_task=nil;}
 TDPDiagRecord(@"packet_complete",@{@"op":@(op),@"bytes":@(finished.length),@"elapsedMs":@((uint64_t)((_clock()-_packetStarted)*1000))});
 // File ownership AND AP acceptance are proven above. No artificial frame gap.
 _nextSend=_clock()+((_frame||_deltaTarget)?0:0.15);
 if(op==TDP_QUERY){_needsRenew=YES;[self publish:@"Real SID received; wait for lease renewal receipt before allowing drawing"];return;}
 if(op==TDP_CLOSE){[self fail:@"Glasses returns CLOSED; page close receipt received"];return;}
 if(op==TDP_KEEPALIVE){_needsRenew=NO;_renewAt=_clock()+30;[self publish:@"Session verified and renewed; test graph can be sent"];return;}
 if(op==TDP_FRAME_CHUNK){_offset+=_chunkLength;_completedChunks++;}
 if(op==TDP_FRAME_COMMIT){_knownPixels=[_frame mutableCopy];_baselineSID=self.sessionID;_baselineRevision=self.revision;}
 if(op==TDP_RECT){
  const uint8_t *b=finished.bytes;unsigned x=b[32]|(b[33]<<8),y=b[34]|(b[35]<<8),w=b[36]|(b[37]<<8),h=b[38]|(b[39]<<8);
  if(_knownPixels.length==TDP_PIXELS&&_baselineSID==self.sessionID&&_baselineRevision==Read32(b+16)){
   for(unsigned row=0;row<h;row++)memcpy((uint8_t *)_knownPixels.mutableBytes+(y+row)*512+x,b+40+row*w,w);
   _baselineRevision=self.revision;
  }else _knownPixels=nil;
  if(_deltaTarget){
   _deltaIndex++;
   if(_deltaIndex==_delta.count){_deltaEnded=_clock();_deltaTarget=nil;_renewAt=_clock()+30;
    TDPDiagRecord(@"delta_complete",@{@"chunks":@(_deltaIndex),@"elapsedMs":@((uint64_t)(self.deltaElapsed*1000)),@"revision":@(self.revision)});
    [self publish:[NSString stringWithFormat:@"Partial update %u block completed · %.2f seconds; lens effect to be confirmed",_deltaIndex,self.deltaElapsed]];
   }else{[self publish:[NSString stringWithFormat:@"Partial update %u / %u; keep the unchanged picture",_deltaIndex,_delta.count]];[self queueFramePump];}
   return;
  }
 }
 if(op==TDP_FRAME_COMMIT||op==TDP_RECT){
  if(_frame){_frameEnded=_clock();TDPDiagRecord(@"frame_complete",@{@"chunks":@(_completedChunks),@"elapsedMs":@((uint64_t)(self.frameElapsed*1000)),@"revision":@(self.revision)});}
  _frame=nil;_renewAt=_clock()+30;[self publish:op==TDP_FRAME_COMMIT?[NSString stringWithFormat:@"139 blocks of the entire frame have been submitted · %.1f seconds; UI_SUBMITTED, the lens effect needs to be confirmed",self.frameElapsed]:@"Glasses return UI_SUBMITTED; drawing has been submitted, the lens effect still needs to be confirmed"];
 }else{[self publish:[NSString stringWithFormat:@"Framing: %lu / 139 blocks; picture not yet submitted",(unsigned long)_completedChunks]];[self queueFramePump];}
}
- (BOOL)consumeEvent:(NSDictionary *)event {
 NSAssert(NSThread.isMainThread,@"main only");if(![event isKindOfClass:NSDictionary.class])return NO;
 NSString *type=event[@"eventType"];
 if([type isEqual:@"fileShareSuccess"]||[type isEqual:@"fileShareFailed"]){
  id peer=[event[@"device"] isKindOfClass:NSDictionary.class]?event[@"device"][@"id"]:nil;
  TDPDiagRecord(@"file_match",@{@"deviceMatch":@([peer isEqual:_device]),@"taskMatch":@([event[@"taskId"] isEqual:_nativeTask]),@"nameMatch":@([event[@"fileName"] isEqual:@"turbo-display.tdp"]),@"role":@([event[@"role"] isEqual:@"sender"]?1:0),@"success":@([type isEqual:@"fileShareSuccess"])});
  if(![peer isEqual:_device]||![event[@"role"] isEqual:@"sender"])return NO;
  id nativeID=event[@"taskId"];if(![nativeID isKindOfClass:NSString.class]||![nativeID length]||[nativeID length]>256)return NO;
  if([type isEqual:@"fileShareSuccess"]&&![event[@"fileName"] isEqual:@"turbo-display.tdp"])return NO;
  if(!_nativeTask&&_fileBusy){
   // Bounded metadata-only staging: never infer ownership from the filename.
   // Replay only after this invocation returns its exact SDK-generated task ID.
   if(_earlyFiles.count<8){[_earlyFiles addObject:@{@"eventType":type,@"device":@{@"id":_device},@"role":@"sender",@"taskId":[nativeID copy],@"fileName":[type isEqual:@"fileShareSuccess"]?@"turbo-display.tdp":@""}];}
   return NO;
  }
  if(![nativeID isEqual:_nativeTask])return NO;
  if(!_fileBusy)return YES;_fileBusy=NO;
  if([type isEqual:@"fileShareFailed"]){[self fail:@"The file channel returns failed and has been stopped; the command to modify the screen will not be automatically retried."];return YES;}
  if(!_packet)[self publish:[_state stringByAppendingString:@";The file has ended and can be queried again after opening the page."]];
  else [self finishIfComplete];return YES;
 }
 NSDictionary *m=event[@"message"];if(![type isEqual:@"messageReceived"]||![m isKindOfClass:NSDictionary.class]||![m[@"deviceId"] isEqual:_device]||![m[@"businessId"] isEqual:@15]||![m[@"payload"] isKindOfClass:NSData.class])return NO;
 NSData *data=m[@"payload"];TDPReply r;if(!tdp_carrier_decode(15,data.bytes,data.length,&r))return NO;
 TDPDiagRecord(@"reply_match",@{@"packet":@(_packet!=nil),@"request":@(r.request),@"taskMatch":@(_packet&&r.request==Read32((const uint8_t *)_packet.bytes+12)),@"sid":@(r.sid),@"result":@(r.result)});
 if(!r.request){if(r.result==TDP_CLOSED&&r.sid==self.sessionID)[self fail:@"The glasses entity exits, stopping all sending"];
  else if(r.result==TDP_CAPS&&r.sid&&!self.busy&&!self.ready)[self publish:@"Received glasses opening page prompt; please click query to verify SID, drawing has not been authorized yet"];
  return YES;}
 if(!_packet||r.request!=Read32((const uint8_t *)_packet.bytes+12))return YES;
 if(_deltaTarget&&_clock()>=_deltaDeadline){[self fail:@"Partial update timeout; clear baseline, late receipt will not resume sending"];return YES;}
 if(_frame&&_clock()>=_frameDeadline){[self fail:@"The entire frame has timed out and has been stopped; late receipt does not trigger subsequent sending"];return YES;}
 if(_clock()>=_deadline){[self fail:@"Protocol receipt timed out, result unknown; transmission not continued"];return YES;}
 const uint8_t *p=_packet.bytes;unsigned op=p[5];uint32_t sid=Read32(p+8),rev=Read32(p+16);
 if(op!=TDP_QUERY&&r.sid!=sid&&!((r.result==TDP_NO_SESSION||r.result==TDP_CLOSED)&&r.sid==0))return YES;
 TDPResult expected=op==TDP_QUERY?TDP_CAPS:op==TDP_KEEPALIVE?TDP_ALIVE:op==TDP_CLOSE?TDP_CLOSED:(op==TDP_RECT||op==TDP_FRAME_COMMIT)?TDP_UI_SUBMITTED:TDP_STAGED;
 uint32_t expectedRev=rev+((op==TDP_RECT||op==TDP_FRAME_COMMIT)?1:0);
 if(r.result!=expected||(op!=TDP_QUERY&&r.revision!=expectedRev)){[self fail:r.result==TDP_NO_SESSION?@"The glasses display session is not open; please enter the Turbo Display SID page first and then query again":[NSString stringWithFormat:@"Glasses rejected: error code %u; stop and ask to requery",r.result]];return YES;}
 [_observer consumeEvent:event];
 if(op!=TDP_CLOSE&&!_observer.ready){[self fail:@"Capability receipts are incompatible; new display features are not enabled"];return YES;}
 _ack=r;_apAck=YES;[self finishIfComplete];return YES;
}
- (void)setForegroundActive:(BOOL)active {
 NSAssert(NSThread.isMainThread,@"main only");
 if(!active&&[TDPPhoneNavigationStatus()[@"active"] boolValue]){
  // Navigation HUD is actively streaming to glasses in standby/background; maintain active state!
  _foreground=YES;
  return;
 }
 _foreground=active;
 if(!active)[self fail:@"Sending and lease renewal have been suspended; you need to query again after returning, and the display will not be permanently occupied."];
}
- (void)tick {
 NSAssert(NSThread.isMainThread,@"main only");
 if(_deltaTarget&&_clock()>=_deltaDeadline){[self fail:@"Partial update timeout; the screen may be partially updated and will not be automatically retried."];return;}
 if(_frame&&_clock()>=_frameDeadline){[self fail:@"The entire frame has timed out and has been stopped; unterminated file interlocks are retained and will not be automatically retried."];return;}
 if(_packet&&_clock()>=_deadline){TDPDiagRecord(@"timeout",@{@"op":@(((const uint8_t *)_packet.bytes)[5]),@"fileBusy":@(_fileBusy),@"apAck":@(_apAck)});[self fail:[NSString stringWithFormat:@"Query/command timeout: file final status %@, AP receipt %@; result unknown, stopped. Diagnosis saved",_fileBusy?@"Not yet arrived":@"Arrived",_apAck?@"Arrived":@"Not yet arrived"]];return;}
 if(!_foreground||_packet||_fileBusy||_clock()<_nextSend)return;
 if(_needsRenew&&_observer.ready){if(![self control:TDP_KEEPALIVE])[self fail:@"The lease renewal has not been issued, please check again"];return;}
 if(_deltaTarget){[self nextDeltaPacket];return;}
 if(_frame){[self nextFramePacket];return;}
 if(self.ready&&_clock()>=_renewAt){if(![self control:TDP_KEEPALIVE])[self fail:@"The lease renewal has not been issued, please check again"];}
}
@end
