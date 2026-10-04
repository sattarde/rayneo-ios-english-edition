#import "SubtitleHUDCore.h"
static BOOL Var(const uint8_t *b,NSUInteger n,NSUInteger *p,uint64_t *v){*v=0;for(unsigned i=0;i<10;i++){if(*p>=n)return NO;uint8_t x=b[(*p)++];if(i==9&&(x&254))return NO;*v|=(uint64_t)(x&127)<<(i*7);if(!(x&128))return YES;}return NO;}
NSData *TIOSubtitlePacket(NSUInteger type,NSDictionary *j){
    if(![@[@3,@5,@7] containsObject:@(type)]||![j isKindOfClass:NSDictionary.class])return nil;
    NSData *d=[NSJSONSerialization dataWithJSONObject:j options:0 error:nil];if(!d||d.length>4096)return nil;
    uint8_t h[]={8,1,16,(uint8_t)type,26};NSMutableData *p=[NSMutableData dataWithBytes:h length:5];NSUInteger n=d.length;
    do{uint8_t x=n&127;n>>=7;if(n)x|=128;[p appendBytes:&x length:1];}while(n);[p appendData:d];return p;
}
NSDictionary *TIOSubtitleEnvelope(NSData *d){
    if(![d isKindOfClass:NSData.class]||!d.length||d.length>262144)return nil;
    const uint8_t *b=d.bytes;NSUInteger p=0;uint64_t version=0,type=0,binary=0;NSData *json=nil;NSMutableSet *seen=[NSMutableSet new];
    while(p<d.length){uint64_t k=0,v=0;if(!Var(b,d.length,&p,&k))return nil;uint64_t tag=k>>3,wire=k&7;
        if(tag<1||tag>4||[seen containsObject:@(tag)])return nil;[seen addObject:@(tag)];
        if(tag<3){if(wire||!Var(b,d.length,&p,&v))return nil;if(tag==1)version=v;else type=v;}
        else{if(wire!=2||!Var(b,d.length,&p,&v)||v>d.length-p)return nil;if(tag==3)json=[d subdataWithRange:NSMakeRange(p,(NSUInteger)v)];else binary=v;p+=(NSUInteger)v;}}
    if(version!=1||![seen containsObject:@2])return nil;
    id j=json.length?[NSJSONSerialization JSONObjectWithData:json options:0 error:nil]:nil;
    // Keep type/binary length even when audio is not JSON. Never retain audio bytes.
    return @{@"type":@(type),@"json":[j isKindOfClass:NSDictionary.class]?j:@{},@"binaryBytes":@(binary)};
}
NSDictionary *TIOSubtitleStopContract(NSDictionary *j,NSString *sid){
    if(![j isKindOfClass:NSDictionary.class]||![sid isKindOfClass:NSString.class]||!sid.length||![j[@"sid"] isKindOfClass:NSString.class]||![j[@"sid"] length])return nil;
    NSSet *keys=[NSSet setWithArray:j.allKeys];if(![keys isEqual:[NSSet setWithArray:@[@"sid",@"reason_code",@"text"]]])return nil;
    id reason=j[@"reason_code"];
    if(![reason isKindOfClass:NSNumber.class]||CFGetTypeID((__bridge CFTypeRef)reason)==CFBooleanGetTypeID()||![reason isEqual:@10]||![j[@"text"] isEqual:@""])return nil;
    return @{@"sid":sid,@"reason_code":@10,@"text":@""};
}
@implementation TIOSubtitleTrial { NSDictionary *_stop; BOOL _navigation; }
- (BOOL)navigation{return _navigation;}
- (instancetype)init{if((self=[super init])){_phase=@"idle";_note=@"Waiting for official preview and exit sample";}return self;}
- (BOOL)active{return [@[@"starting",@"ready",@"stopping",@"uncertain"] containsObject:self.phase];}
- (void)mark:(NSString *)phase note:(NSString *)note{self.phase=phase;self.note=note;if(self.changed)self.changed();}
- (BOOL)startWithPreview:(NSDictionary *)preview stop:(NSDictionary *)stop now:(NSTimeInterval)now{
    if(self.active||!self.send||![preview isKindOfClass:NSDictionary.class]||![stop isKindOfClass:NSDictionary.class]||![preview[@"scope"] isEqual:@"temporary"]||![preview[@"config"] isKindOfClass:NSDictionary.class]||![preview[@"config"][@"is_display"] isEqual:@YES]||[preview[@"force"] boolValue]||![preview[@"sid"] isKindOfClass:NSString.class]||![stop[@"sid"] isEqual:preview[@"sid"]])return NO;
    _navigation=NO;_stop=[stop copy];self.sid=[NSUUID.UUID.UUIDString.lowercaseString stringByReplacingOccurrencesOfString:@"-" withString:@""];self.began=now;self.deadline=now+10;self.frame=0;self.audioPackets=0;self.lastText=0;
    NSMutableDictionary *j=[preview mutableCopy];j[@"sid"]=self.sid;j[@"scope"]=@"temporary";j[@"force"]=@NO;
    [self mark:@"starting" note:@"Temporary preview submitted, waiting for matching SID ACK; no nav text sent yet"];
    if(!self.send(7,j)){[self stop:@"Preview submission failed, outcome unknown" now:now];return NO;}return YES;
}
- (BOOL)nextAt:(NSTimeInterval)now{
    if(_navigation||![self.phase isEqual:@"ready"]||self.frame>=3||(self.frame&&now-self.lastText<3)||now-self.began>=240)return NO;
    NSArray *frames=@[@"Nav Display Test 7392\nTurn right 80m ahead",@"Nav Display Test 9264\nTurn right 60m ahead",@"Nav Display Test 3815\nTurn right 35m ahead"];
    // Firmware parseDisplayText + mode3 renderer. status0 deliberately tests a
    // changing partial sentence, not final-history accumulation or ASR startup.
    NSDictionary *j=@{@"sid":self.sid,@"mode":@3,@"status":@0,@"content":@{@"source_transcript":frames[self.frame]}};
    self.lastText=now;self.frame++;
    if(!self.send(5,j)){[self stop:@"Text submission failed" now:now];return NO;}
    [self mark:@"ready" note:[NSString stringWithFormat:@"Section %lu submitted (not glasses ACK); check overwrite/append, loading, and display",(unsigned long)self.frame]];return YES;
}
- (BOOL)startNavigationWithPreview:(NSDictionary *)p stop:(NSDictionary *)s now:(NSTimeInterval)now{
    if(![self startWithPreview:p stop:s now:now])return NO;_navigation=YES;return YES;
}
- (BOOL)sendNavigationText:(NSString *)text now:(NSTimeInterval)now{
    if(!_navigation||![self.phase isEqual:@"ready"]||self.frame>=1000||now-self.began>=3600||(self.frame&&now-self.lastText<2.5)||![text isKindOfClass:NSString.class]||!text.length||[text lengthOfBytesUsingEncoding:NSUTF8StringEncoding]>384)return NO;
    self.lastText=now;self.frame++;
    if(!self.send(5,@{@"sid":self.sid,@"mode":@3,@"status":@0,@"content":@{@"source_transcript":text}})){[self stop:@"Navigation text submission failed" now:now];return NO;}
    [self mark:@"ready" note:@"Navigation text submitted to glasses"];return YES;
}
- (void)receive:(NSDictionary *)e now:(NSTimeInterval)now{
    if(!self.active)return;
    if([e[@"type"] isEqual:@4]){self.audioPackets++;[self stop:@"Subtitle audio message appeared on same device; stopped display-only experiment" now:now];if(self.changed)self.changed();return;}
    NSDictionary *j=e[@"json"];if(![j[@"sid"] isEqual:self.sid])return;
    if([e[@"type"] isEqual:@8]&&[self.phase isEqual:@"starting"]){
        id code=j[@"code"];BOOL ok=[code isKindOfClass:NSNumber.class]&&CFGetTypeID((__bridge CFTypeRef)code)!=CFBooleanGetTypeID()&&([code isEqual:@1]||[code isEqual:@2]);
        if(ok)[self mark:@"ready" note:@"Matching SID setting ACK received; sending A does not guarantee visible text or no audio capture"];
        else [self stop:@"Preview ACK rejected or unknown format; not pre-empting" now:now];
    }
    // Keep an inbound type3 as evidence only until its direction/semantics are
    // verified. Never declare clean exit merely because send() returned success.
    if([e[@"type"] isEqual:@3]){[self stop:@"Received matching SID stop message; please confirm glasses exited" now:now];}
}
- (void)stop:(NSString *)reason now:(NSTimeInterval)now{
    if(!self.active)return;
    self.deadline=now+8;
    NSMutableDictionary *j=[_stop mutableCopy];j[@"sid"]=self.sid;
    if(_stop&&self.send)self.send(3,j);
    [self mark:@"idle" note:reason?:@"Subtitle session stopped"];
    self.sid=nil;
}
- (void)tick:(NSTimeInterval)now{
    if([self.phase isEqual:@"starting"]&&now>=self.deadline)[self stop:@"No matching config ACK after 10s" now:now];
    if([self.phase isEqual:@"ready"]&&now-self.began>=3600)[self stop:@"1-hour safety timeout reached" now:now];
}
@end
