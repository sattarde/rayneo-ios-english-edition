#import "TDPhoneStore.h"
#import "diagnostics.h"
static NSArray<NSString *> *Names(void){return @[@"lv_configured_bytes",@"lv_used_bytes",@"lv_peak_bytes",@"lv_free_bytes",@"lv_largest_free_bytes",@"system_arena_bytes",@"system_used_bytes",@"system_peak_bytes",@"system_free_bytes",@"system_largest_free_bytes",@"instrumented_owned_bytes",@"instrumented_owned_peak_bytes",@"allocation_failures",@"rx_packets",@"rx_bytes",@"rx_max_ms",@"render_submissions",@"render_max_ms",@"errors"];}
@implementation TDPhoneStore {
 uint32_t _build,_session,_sequence,_tick;NSString *_device;BOOL _active;
 NSMutableArray<NSDictionary *> *_samples;NSUInteger _evicted,_gaps;
 NSTimeInterval _lastReceipt;
}
- (instancetype)initWithBuild:(uint32_t)build device:(NSString *)device{
 if((self=[super init])){_build=build;_device=[device copy];_samples=[NSMutableArray new];}return self;
}
- (BOOL)begin:(uint32_t)session{
 NSAssert(NSThread.isMainThread,@"main executor");if(!session||!_device.length||_active)return NO;
 _session=session;_sequence=_tick=0;_evicted=_gaps=0;_lastReceipt=0;[_samples removeAllObjects];_active=YES;return YES;
}
- (void)end{NSAssert(NSThread.isMainThread,@"main executor");_active=NO;}
- (BOOL)receive:(NSData *)packet fromDevice:(NSString *)device{
 NSAssert(NSThread.isMainThread,@"main executor");TDSample s;
 if(!_active||![device isEqual:_device]||![packet isKindOfClass:NSData.class]||!td_decode(packet.bytes,packet.length,&s)||s.build!=_build||s.session!=_session)return NO;
 if(_sequence){uint32_t ds=s.sequence-_sequence,dt=s.tick_ms-_tick;if(!ds||ds>=0x80000000u||dt>=0x80000000u)return NO;_gaps=MIN((uint64_t)UINT32_MAX,(uint64_t)_gaps+ds-1);}
 NSMutableDictionary *metrics=[NSMutableDictionary new];NSArray *names=Names();
 for(NSUInteger i=0;i<names.count;i++)metrics[names[i]]=(s.valid&(1u<<i))?@(s.values[i]):NSNull.null;
 NSDictionary *row=@{@"build":[NSString stringWithFormat:@"%08x",s.build],@"session":@(s.session),@"sequence":@(s.sequence),@"tick_ms":@(s.tick_ms),@"phone_received_uptime_s":@(NSProcessInfo.processInfo.systemUptime),@"phone_received_wall_time_s":@(NSDate.date.timeIntervalSince1970),@"probe_ms":@(s.probe_ms),@"metrics":metrics,@"ring_events":@(s.event_count),@"ring_overwritten":@(s.events_lost),@"probe_stopped_for_latency":@(s.flags==1)};
 if(_samples.count==600){[_samples removeObjectAtIndex:0];_evicted++;}
 [_samples addObject:row];_sequence=s.sequence;_tick=s.tick_ms;_lastReceipt=NSProcessInfo.processInfo.systemUptime;
 if(s.flags==1)_active=NO;return YES;
}
- (BOOL)active{return _active;}
- (NSUInteger)count{return _samples.count;}
- (NSTimeInterval)age{return _lastReceipt?MAX(0,NSProcessInfo.processInfo.systemUptime-_lastReceipt):INFINITY;}
- (NSDictionary *)latest{return _samples.lastObject;}
- (NSData *)reportJSON{
 NSDictionary *report=@{@"format":@"TurboIO-Diagnostics-1",@"samples":[_samples copy],@"count":@(_samples.count),@"sequence_gaps":@(_gaps),@"evicted_samples":@(_evicted),@"limitations":@[@"Unmeasured value is null, not 0",@"Number of submissions does not equal panel FPS",@"Session number is not a persistent startup count",@"This report does not contain a full crash dump, nor does it demonstrate that the logs are recoverable after a power outage"]};
 return [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:nil];
}
- (NSString *)reportMarkdown{
 NSMutableString *s=[NSMutableString stringWithFormat:@"# Turbo IO glasses diagnosis \n\n retained sampling: %lu; serial number gap: %lu; window elimination: %lu. \n\n",(unsigned long)_samples.count,(unsigned long)_gaps,(unsigned long)_evicted];
 NSDictionary *last=self.latest;if(!last){[s appendString:@"The glasses sample has not been received yet, so the resource margin cannot be determined. \n"];return s;}
 [s appendFormat:@"Firmware ID: %@; Session: %@; Latest serial number: %@. \n\n| Indicator | Value |\n| --- | ---: |\n",last[@"build"],last[@"session"],last[@"sequence"]];
 for(NSString *name in Names()){id v=last[@"metrics"][name];[s appendFormat:@"| %@ | %@ |\n",name,v==NSNull.null?@"Not tested":v];}
 [s appendString:@"\n Memory capacity is not currently allocable; render submission is not panel FPS. The session number is not a startup count. This report is not equivalent to a crash log; buffer drops/transmission gaps cannot be interpreted as a complete log. \n"];return s;
}
@end
