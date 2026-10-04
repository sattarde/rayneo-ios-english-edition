#import "TDPhoneRun.h"
#include <math.h>
#include <sys/stat.h>
@implementation TDPhoneRun {
 TDPhoneStore *_store;NSURL *_root,*_reportDirectory;NSTimeInterval(^_clock)(void);
 BOOL(^_start)(uint32_t,uint32_t);void(^_stop)(void);BOOL _active;
 NSTimeInterval _began,_deadline,_lastReceipt,_lastSave;NSString *_reason,*_runID;
 NSMutableArray *_events;NSUInteger _droppedEvents,_revision;BOOL _received;
 dispatch_queue_t _writer;NSDictionary *_pending;BOOL _writing;NSString *_saveStatus;
}
- (instancetype)initWithStore:(TDPhoneStore *)store root:(NSURL *)root clock:(NSTimeInterval(^)(void))clock sendStart:(BOOL(^)(uint32_t,uint32_t))start sendStop:(void(^)(void))stop{
 if((self=[super init])){_store=store;_root=root;_clock=[clock copy];_start=[start copy];_stop=[stop copy];_events=[NSMutableArray new];_writer=dispatch_queue_create("io.turboio.diagnostics.archive",DISPATCH_QUEUE_SERIAL);_saveStatus=@"Not collected yet";}return self;
}
- (TDPhoneStore *)store{return _store;}
- (BOOL)active{return _active;}
- (NSURL *)reportDirectory{return _reportDirectory;}
- (NSString *)saveStatus{@synchronized(self){return _saveStatus;}}
- (NSTimeInterval)remaining{return _active?MAX(0,_deadline-_clock()):0;}
- (NSString *)status{
 if(_active)return !_received?@"Waiting for the first sample of glasses":(_clock()-_lastReceipt>5?@"Sampling temporarily interrupted · Unknown reason":@"Collecting · Can return to use other functions");
 NSDictionary *names=@{@"user_stop":@"Ended manually",@"lease_elapsed":@"Expires in 10 minutes · End of this round",@"first_sample_timeout":@"The first sample was not received for 10 seconds.",@"telemetry_silent":@"No new samples for 20 seconds · Unknown reason, ended",@"submit_failed":@"Collection request submission failed",@"transfer_failed":@"Diagnostic file transfer failure",@"probe_slow":@"Glasses stopped due to excessive sampling time",@"peer_context_changed":@"Device context change·Ended",@"archive_unavailable":@"Unable to create native report · Not started"};
 return names[_reason]?:@"Not started";
}
static BOOL Directory(NSURL *url){struct stat s;return url.isFileURL&&lstat(url.path.fileSystemRepresentation,&s)==0&&S_ISDIR(s.st_mode);}
- (BOOL)start{
 NSAssert(NSThread.isMainThread,@"main only");if(_active||!_clock||!_start||!isfinite(_clock()))return NO;
 NSFileManager *fm=NSFileManager.defaultManager;NSError *error=nil;
 if(!_root.isFileURL||![fm createDirectoryAtURL:_root withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:&error]||!Directory(_root)){_reason=@"archive_unavailable";return NO;}
 NSArray *entries=[fm contentsOfDirectoryAtURL:_root includingPropertiesForKeys:nil options:0 error:&error];
 if(!entries||entries.count>=100){_reason=@"archive_unavailable";return NO;} // bounded disk, never delete old reports automatically
 NSURL *next=[_root URLByAppendingPathComponent:NSUUID.UUID.UUIDString isDirectory:YES];
 if(![fm createDirectoryAtURL:next withIntermediateDirectories:NO attributes:@{NSFilePosixPermissions:@0700} error:&error]){_reason=@"archive_unavailable";return NO;}
 [next setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil];
 uint32_t sid;do{sid=arc4random();}while(!sid);
 if(![_store begin:sid]){[fm removeItemAtURL:next error:nil];return NO;}
 _reportDirectory=next;_runID=next.lastPathComponent;_reason=nil;_events=[NSMutableArray new];_droppedEvents=_revision=0;
 _began=_clock();_deadline=_began+600;_lastSave=_began;_lastReceipt=0;_received=NO;_active=YES;
 [self event:@"start_requested" fields:@{@"lease_ms":@600000}];[self checkpoint];
 if(!_start(sid,600000)){[self stop:@"submit_failed"];return NO;}return YES;
}
- (void)poll{
 NSAssert(NSThread.isMainThread,@"main only");if(!_active)return;NSTimeInterval now=_clock();
 if(now>=_deadline){[self stop:@"lease_elapsed"];return;}
 if(!_received&&now-_began>=10){[self stop:@"first_sample_timeout"];return;}
 if(_received&&now-_lastReceipt>=20){[self stop:@"telemetry_silent"];return;}
 if(now-_lastSave>=5)[self checkpoint];
}
- (BOOL)receive:(NSData *)packet device:(NSString *)device{
 NSAssert(NSThread.isMainThread,@"main only");[self poll];if(!_active||![_store receive:packet fromDevice:device])return NO;
 _lastReceipt=_clock();if(!_received){_received=YES;[self event:@"first_sample" fields:@{}];}
 if([_store.latest[@"probe_stopped_for_latency"]boolValue])[self stop:@"probe_slow"];
 else if(_lastReceipt-_lastSave>=5)[self checkpoint];return YES;
}
- (void)stop:(NSString *)reason{
 NSAssert(NSThread.isMainThread,@"main only");if(!_active)return;
 NSSet *allowed=[NSSet setWithArray:@[@"user_stop",@"lease_elapsed",@"first_sample_timeout",@"telemetry_silent",@"submit_failed",@"transfer_failed",@"probe_slow",@"peer_context_changed"]];
 _reason=[allowed containsObject:reason]?reason:@"user_stop";
 [self event:_reason fields:@{}];_active=NO;[_store end];if(_stop)_stop();[self checkpoint];
}
- (void)event:(NSString *)code fields:(NSDictionary *)fields{
 NSAssert(NSThread.isMainThread,@"main only");if(!_active)return;
 NSSet *events=[NSSet setWithArray:@[@"start_requested",@"first_sample",@"user_stop",@"lease_elapsed",@"first_sample_timeout",@"telemetry_silent",@"submit_failed",@"transfer_failed",@"probe_slow",@"peer_context_changed",@"app_background",@"app_foreground",@"music_reply",@"navigation_reply",@"file_submitted",@"file_finished",@"file_failed",@"peer_context_same",@"reply_rejected"]];
 if(![events containsObject:code])return;
 NSMutableDictionary *row=[@{@"event":code,@"phone_uptime_s":@(_clock()),@"elapsed_s":@(MAX(0,_clock()-_began)),@"wall_time_s":@(NSDate.date.timeIntervalSince1970)} mutableCopy];
 NSSet *keys=[NSSet setWithArray:@[@"lease_ms",@"event_code",@"result",@"active",@"awake",@"stale",@"success",@"sequence",@"mode"]];
 if([fields isKindOfClass:NSDictionary.class])for(NSString *key in keys){id value=fields[key];if([value isKindOfClass:NSNumber.class]&&isfinite([value doubleValue])&&fabs([value doubleValue])<=UINT32_MAX)row[key]=value;}
 if(_events.count==512){[_events removeObjectAtIndex:0];_droppedEvents++;}[_events addObject:row];
}
- (NSData *)reportJSON{
 NSMutableDictionary *r=[[NSJSONSerialization JSONObjectWithData:[_store reportJSON] options:NSJSONReadingMutableContainers error:nil]mutableCopy];
 r[@"phone_build"]=@"DIAGNOSTICS-PHONE-02";r[@"run_id"]=_runID?:@"";r[@"process_id"]=@(NSProcessInfo.processInfo.processIdentifier);
 r[@"requested_seconds"]=@600;r[@"active"]=@(_active);r[@"stop_reason"]=_reason?:NSNull.null;r[@"revision"]=@(_revision);
 r[@"updated_wall_time_s"]=@(NSDate.date.timeIntervalSince1970);r[@"events"]=[_events copy];r[@"events_dropped"]=@(_droppedEvents);
 r[@"evidence_note"]=@"The operation event comes from the verified protocol receipt and is not equal to the visual confirmation of the lens; sampling silence cannot be confirmed as Bluetooth disconnection. The last save status after shutdown/crash may be active and cannot be considered to be still running.";
 return [NSJSONSerialization dataWithJSONObject:r options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:nil];
}
- (NSString *)reportMarkdown{
 return [NSString stringWithFormat:@"%@\n## Automatically record \n\n running: %@; mobile version: DIAGNOSTICS-PHONE-02; process: %d; snapshot version: %lu. \n\n status: %@; stop reason: %@; event: %lu; event elimination: %lu. \n\n Full timeline in JSON. Agreement receipt does not equal visual confirmation of the lens; the reason for sampling silence may be unknown. The report is not a crash dump. \n",[_store reportMarkdown],_runID?:@"Not started",NSProcessInfo.processInfo.processIdentifier,(unsigned long)_revision,self.status,_reason?:@"not stopped yet",(unsigned long)_events.count,(unsigned long)_droppedEvents];
}
- (void)checkpoint{
 NSAssert(NSThread.isMainThread,@"main only");if(!_reportDirectory)return;_lastSave=_clock();_revision++;
 NSData *json=[self reportJSON],*md=[[self reportMarkdown]dataUsingEncoding:NSUTF8StringEncoding];
 if(!json||json.length>4*1024*1024||md.length>1024*1024){@synchronized(self){_saveStatus=@"Report limit exceeded·Save failed";}return;}
 NSDictionary *job=@{@"dir":_reportDirectory,@"json":json,@"md":md};
 // Ordered jobs are bounded by the ten-minute 5s cadence; coalesce only the same run.
 @synchronized(self){
  if(_pending&&![_pending[@"dir"]isEqual:_reportDirectory]){NSDictionary *old=_pending;dispatch_async(_writer,^{[self write:old];});}
  _pending=job;if(_writing)return;_writing=YES;
 }
 dispatch_async(_writer,^{for(;;){NSDictionary *next;@synchronized(self){next=self->_pending;self->_pending=nil;if(!next){self->_writing=NO;break;}}[self write:next];}});
}
- (void)write:(NSDictionary *)job{
 @autoreleasepool{NSURL *dir=job[@"dir"];NSFileManager *fm=NSFileManager.defaultManager;BOOL ok=Directory(_root)&&Directory(dir);
 for(NSString *name in @[@"json",@"md"]){if(!ok)break;NSURL *url=[dir URLByAppendingPathComponent:[@"diagnostics."stringByAppendingString:name]];
  ok=[job[name]writeToURL:url options:NSDataWritingAtomic|NSDataWritingFileProtectionCompleteUntilFirstUserAuthentication error:nil];
  if(ok)ok=[fm setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:url.path error:nil];}
 @synchronized(self){_saveStatus=ok?@"The report has been automatically saved to this computer":@"Auto-save failed·Can be shared manually";}
 }
}
- (void)waitForWrites{dispatch_sync(_writer,^{});}
@end
