#import "FocusBridge.h"
#import "FocusTransport.h"
#import "ProtocolContext.h"
#import "focus.h"
#import <objc/message.h>
extern NSDictionary *TIOOTAFlashStatus(void) __attribute__((weak_import));
NSDictionary *TFDecodeReply(NSDictionary *e){if(![e isKindOfClass:NSDictionary.class]||![e[@"eventType"]isEqual:@"messageReceived"])return nil;NSDictionary *m=e[@"message"];if(![m isKindOfClass:NSDictionary.class]||![m[@"businessId"]isEqual:@15])return nil;NSData *d=m[@"payload"];if(![d isKindOfClass:NSData.class]||d.length<7||d.length>512)return nil;const uint8_t *p=d.bytes;const uint8_t prefix[]={8,1,16,6,26};if(memcmp(p,prefix,5)||!(p[5]&128)||(p[6]&128)||d.length!=7+(p[5]&127)+(p[6]<<7))return nil;
 id j=[NSJSONSerialization JSONObjectWithData:[d subdataWithRange:NSMakeRange(7,d.length-7)] options:0 error:nil];if(![j isKindOfClass:NSDictionary.class]||![j[@"cmd"]isEqual:@"turbo_focus_v1"]||![j[@"payload"]isKindOfClass:NSDictionary.class])return nil;NSString *hex=j[@"payload"][@"data"];if(![hex isKindOfClass:NSString.class]||hex.length!=128)return nil;uint8_t raw[64];for(unsigned i=0;i<64;i++){unsigned v=0;for(unsigned k=0;k<2;k++){unichar c=[hex characterAtIndex:i*2+k];unsigned n=c>='0'&&c<='9'?c-'0':c>='a'&&c<='f'?c-'a'+10:16;if(n>15)return nil;v=v*16+n;}raw[i]=v;}
 if(memcmp(raw,"TFA1",4)||raw[4]!=1||raw[5]>TF_NO_SESSION||raw[6]>TF_STOPPED||(raw[7]&~3)||tf_u32(raw+60)!=tf_crc(raw,60))return nil;for(unsigned i=48;i<60;i++)if(raw[i])return nil;if(tf_u32(raw+20)>7200000||tf_u32(raw+24)>7200||tf_u32(raw+28)>2)return nil;
 return @{@"result":@(raw[5]),@"status":@(raw[6]),@"pending":@((raw[7]&1)!=0),@"peek":@((raw[7]&2)!=0),@"sid":@(tf_u32(raw+8)),@"seq":@(tf_u32(raw+12)),@"revision":@(tf_u32(raw+16)),@"remainingMS":@(tf_u32(raw+20)),@"duration":@(tf_u32(raw+24)),@"phase":@(tf_u32(raw+28)),@"completed":@(tf_u32(raw+32)),@"completion":@(tf_u32(raw+36)),@"requestSID":@(tf_u32(raw+40)),@"notified":@(tf_u32(raw+44))};
}
@implementation TFFocusBridge{
 TFTransport *_transport;NSString *_peer,*_task,*_native,*_note;NSData *_packet;NSDictionary *_snapshot;NSMutableArray *_early;
 uint32_t _sequence,_requestSID,_op,_result,_pendingOp,_pendingSID;BOOL _submitted,_ack,_fileDone;NSTimeInterval _deadline,_received,_queried;NSTimer *_timer;
}
+ (instancetype)shared{static TFFocusBridge *b;static dispatch_once_t once;dispatch_once(&once,^{b=[self new];});return b;}
- (NSDictionary *)snapshot{return _snapshot;}
- (NSString *)note{return _note?:@"Glasses standalone timer · Requires TFP1 firmware";}
- (BOOL)busy{return _packet!=nil;}
- (BOOL)ready{return _snapshot&&[_peer isEqual:TIOProtocolDevice()]&&NSProcessInfo.processInfo.systemUptime-_received<20;}
- (double)remaining{double left=[_snapshot[@"remainingMS"]doubleValue]/1000;if([_snapshot[@"status"]unsignedIntValue]==TF_RUNNING)left-=MAX(0,NSProcessInfo.processInfo.systemUptime-_received);return MAX(0,left);}
- (void)fail:(NSString *)reason{_pendingOp=_pendingSID=0;_packet=nil;_task=_native=nil;_early=nil;_transport=nil;_snapshot=nil;_note=reason;/* Uncertain native spool ownership: do not unlink. */}
- (BOOL)setup{NSString *peer=TIOProtocolDevice();if(!peer.length){_note=@"Glasses not connected; active timer continues on glasses";return NO;}if(_transport&&[_peer isEqual:peer])return YES;
 _peer=[peer copy];_snapshot=nil;NSString *pinned=_peer;NSURL *root=[NSURL fileURLWithPath:[NSHomeDirectory()stringByAppendingPathComponent:@"Library/Application Support/TurboIOPrivateAddon/FocusTFP1"]];
 _transport=[[TFTransport alloc]initWithRoot:root device:_peer currentDevice:^{return TIOProtocolDevice();} call:^BOOL(NSString *method,NSDictionary *args,void(^done)(id)){if(![pinned isEqual:TIOProtocolDevice()])return NO;id plugin=TIOProtocolPlugin();Class cls=NSClassFromString(@"FlutterMethodCall");SEL make=NSSelectorFromString(@"methodCallWithMethodName:arguments:"),handle=NSSelectorFromString(@"handleMethodCall:result:");if(!plugin||![cls respondsToSelector:make]||![plugin respondsToSelector:handle])return NO;@try{id call=((id(*)(id,SEL,id,id))objc_msgSend)(cls,make,method,args);((void(*)(id,SEL,id,id))objc_msgSend)(plugin,handle,call,[done copy]);return YES;}@catch(NSException *e){return NO;}}];
 if(!_timer){__weak typeof(self) w=self;_timer=[NSTimer timerWithTimeInterval:1 repeats:YES block:^(NSTimer *t){[w pump];}];[NSRunLoop.mainRunLoop addTimer:_timer forMode:NSRunLoopCommonModes];}return YES;
}
- (void)query{[self perform:TF_QUERY seconds:0 phase:0];}
- (void)perform:(unsigned)op seconds:(unsigned)seconds phase:(unsigned)phase{NSAssert(NSThread.isMainThread,@"main only");
 if(TIOOTAFlashStatus&&[TIOOTAFlashStatus()[@"stage"]unsignedIntegerValue]!=0){_pendingOp=_pendingSID=0;_note=@"While the protection is being upgraded, the Tomato command will not be sent for the time being. Please wait until the glasses upgrade is completed and return to the homepage before reopening the app; you can also long press on the glasses to stop.";return;}
 if(self.busy){
  if(op==TF_STOP&&_op==TF_QUERY){_pendingOp=TF_STOP;_pendingSID=[_snapshot[@"sid"]unsignedIntValue];_note=@"Stop glasses timing after refreshing...";}
  else if(op!=TF_QUERY)_note=@"Previous command pending, please wait";
  return;
 }
 if(![self setup])return;
 if(op!=TF_QUERY&&!self.ready){
  /* Only STOP may continue after a fresh query. Never silently start a timer.
   * A known session must match; a peer change or failed query drops intent. */
  if(op==TF_STOP){_pendingOp=TF_STOP;_pendingSID=[_snapshot[@"sid"]unsignedIntValue];}
  [self query];if(self.busy)_note=op==TF_STOP?@"Stop glasses timing after refreshing...":@"Refresh the glasses timing status first, and then operate to avoid overwriting the existing focus.";return;
 }
 uint32_t sid=[_snapshot[@"sid"]unsignedIntValue];if(op==TF_START){uint64_t last=[NSUserDefaults.standardUserDefaults doubleForKey:@"TurboFocusLastSID"],fresh=MAX(MAX(last+1,(uint64_t)NSDate.date.timeIntervalSince1970),(uint64_t)sid+1);if(fresh>UINT32_MAX){_note=@"Session number exhausted";return;}sid=(uint32_t)fresh;[NSUserDefaults.standardUserDefaults setDouble:sid forKey:@"TurboFocusLastSID"];}
 _sequence=MAX(_sequence,[NSUserDefaults.standardUserDefaults integerForKey:@"TurboFocusCommandSequence"]);
 if(_sequence==UINT32_MAX){_note=@"The control sequence number has been exhausted";return;}
 TFCommand c={.op=op,.sid=op==TF_QUERY?0:sid,.seq=++_sequence,.revision=op==TF_QUERY?0:[_snapshot[@"revision"]unsignedIntValue],.seconds=seconds,.phase=phase};uint8_t b[64];if(!tf_encode(b,sizeof b,&c)){_note=@"Invalid Pomodoro parameter";return;}
 [NSUserDefaults.standardUserDefaults setInteger:_sequence forKey:@"TurboFocusCommandSequence"];
 _packet=[NSData dataWithBytes:b length:64];_task=NSUUID.UUID.UUIDString;_native=nil;_early=[NSMutableArray new];_submitted=_ack=_fileDone=NO;_result=TF_OK;_requestSID=c.sid;_op=op;_deadline=NSProcessInfo.processInfo.systemUptime+12;_queried=NSProcessInfo.processInfo.systemUptime;_note=@"Waiting for glasses confirmation…";NSString *task=_task;__weak typeof(self) w=self;
 [_transport send:_packet task:task submitted:^(BOOL ok,NSString *native){TFFocusBridge *s=w;if(!s||![task isEqual:s->_task])return;if(!ok){[s fail:@"Tomato command submission failed; glasses status not confirmed"];return;}s->_submitted=YES;s->_native=native;NSArray *early=s->_early;s->_early=nil;for(NSDictionary *e in early)[s consume:e];[s finish];}];
}
- (void)finish{if(!_packet||!_submitted||!_ack||!_fileDone)return;unsigned op=_op,result=_result,pending=_pendingOp,sid=_pendingSID;_pendingOp=_pendingSID=0;[_transport cleanup:_task];_packet=nil;_task=_native=nil;_early=nil;_note=result==TF_OK?(op==TF_STOP?@"The glasses have been confirmed to stop timing":@"Glasses confirmed · Screen pause and disconnection will not end the timer"):[NSString stringWithFormat:@"Glasses rejected (%u), this operation was not performed",result];
 if(pending==TF_STOP&&op==TF_QUERY&&result==TF_OK){
  if(sid&&sid!=[_snapshot[@"sid"]unsignedIntValue]){_note=@"The glasses have switched to another round of timing, please confirm before ending.";return;}
  unsigned status=[_snapshot[@"status"]unsignedIntValue];if(status==TF_IDLE||status==TF_STOPPED){_note=@"Glasses currently has no active timings";return;}
  [self perform:TF_STOP seconds:0 phase:0];
 }
}
- (void)pump{if(_peer&&![_peer isEqual:TIOProtocolDevice()]){[self fail:@"Connection changes; refreshed after reconnection, subject to glasses status"];return;}NSTimeInterval now=NSProcessInfo.processInfo.systemUptime;if(_packet&&now>=_deadline){[self fail:@"Timeout waiting for the glasses receipt; please confirm that TFP1 has been flashed and do not start again."];return;}unsigned status=[_snapshot[@"status"]unsignedIntValue];if(!_packet&&_snapshot&&(status==TF_RUNNING||status==TF_PAUSED)&&now-_received>=12&&now-_queried>=12)[self query];}
- (BOOL)consume:(NSDictionary *)e{if(![e isKindOfClass:NSDictionary.class])return NO;NSString *type=e[@"eventType"];if([@[@"fileShareSuccess",@"fileShareFailed"]containsObject:type]){if(!_packet||![e[@"device"]isKindOfClass:NSDictionary.class]||![e[@"device"][@"id"]isEqual:_peer]||![e[@"role"]isEqual:@"sender"])return NO;if(!_native){if(_early.count<8)[_early addObject:e];return NO;}if(![e[@"taskId"]isEqual:_native])return NO;if([type isEqual:@"fileShareFailed"]){[self fail:@"Tomato command transfer failed"];return YES;}if(![e[@"fileName"]isEqual:@"turbo-focus.tfp"])return NO;_fileDone=YES;[self finish];return YES;}
 NSDictionary *q=TFDecodeReply(e);if(!q)return NO;if(!_peer.length)[self setup];if(![e[@"message"][@"deviceId"]isEqual:_peer]||![_peer isEqual:TIOProtocolDevice()])return YES;
 BOOL matching=_packet&&[q[@"seq"]unsignedIntValue]==_sequence&&[q[@"requestSID"]unsignedIntValue]==_requestSID;
 BOOL update=!_snapshot||[q[@"revision"]unsignedIntValue]>=[_snapshot[@"revision"]unsignedIntValue]||(matching&&_op==TF_QUERY);
 if(update){_snapshot=q;_received=NSProcessInfo.processInfo.systemUptime;}
 if(!matching)return YES;
 _result=[q[@"result"]unsignedIntValue];
 if(_result!=TF_OK){_note=[NSString stringWithFormat:@"Glasses rejected (%@); status has been refreshed, please check if there is a timer",q[@"result"]];_ack=YES;[self finish];return YES;}
 _ack=YES;[self finish];return YES;
}
@end
BOOL TFFocusConsume(NSDictionary *e){return [TFFocusBridge.shared consume:e];}
BOOL TFFocusIdleForOTA(void){TFFocusBridge *b=TFFocusBridge.shared;unsigned s=[b.snapshot[@"status"]unsignedIntValue];return !b.busy&&s!=TF_RUNNING&&s!=TF_PAUSED;}
