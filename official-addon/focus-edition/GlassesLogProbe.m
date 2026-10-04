#import "GlassesLogProbe.h"
#import "GlassesLogGate.h"
#import "GlassesLogContract.h"
#import "A2UIProbe.h"
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <CommonCrypto/CommonDigest.h>
static __weak id Plugin;
static NSDictionary *Route;
static NSString *Device,*Note=@"No logs requested yet. Keep glasses connected.";
static NSURL *Archive;
static NSTimeInterval RouteAt,Started;
static BOOL Copying,Restoring;
static __thread void *OwnCall;
static id Get(id o,NSString *k){@try{return [o valueForKey:k];}@catch(NSException *e){return nil;}}
static NSData *Bytes(id o){if([o isKindOfClass:NSData.class])return o;id d=Get(o,@"data");return [d isKindOfClass:NSData.class]?d:nil;}
static NSURL *Directory(void){NSURL *u=[[NSURL fileURLWithPath:NSHomeDirectory()] URLByAppendingPathComponent:@"Library/Application Support/TurboIOPrivateAddon/GlassesLogProbe" isDirectory:YES];
 [NSFileManager.defaultManager createDirectoryAtURL:u withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil];[u setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil];return u.URLByResolvingSymlinksInPath;}
static BOOL Save(NSString *name,NSDictionary *data){NSURL *u=[Directory() URLByAppendingPathComponent:name];NSData *b=[NSJSONSerialization dataWithJSONObject:data options:NSJSONWritingSortedKeys error:nil];BOOL ok=b&&[b writeToURL:u options:NSDataWritingAtomic error:nil];if(ok)[NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions:@0600,NSFileProtectionKey:NSFileProtectionCompleteUntilFirstUserAuthentication} ofItemAtPath:u.path error:nil];return ok;}
static TIOGlassesLogGate *Gate(void){static TIOGlassesLogGate *g;static dispatch_once_t once;dispatch_once(&once,^{NSData *b=[NSData dataWithContentsOfURL:[Directory() URLByAppendingPathComponent:@"owner.json"]];id s=b?[NSJSONSerialization JSONObjectWithData:b options:0 error:nil]:nil;g=[[TIOGlassesLogGate alloc]initWithSnapshot:s];});return g;}
static void Changed(NSString *note,NSDictionary *extra){dispatch_async(dispatch_get_main_queue(),^{Note=note;NSMutableDictionary *s=[extra mutableCopy]?:[NSMutableDictionary new];s[@"state"]=note;s[@"time"]=@(NSDate.date.timeIntervalSince1970);s[@"archiveSaved"]=@(Archive!=nil);s[@"runtimeVersion"]=@"log-local-v2";if(Archive)s[@"savedName"]=Archive.lastPathComponent;Save(@"status.json",s);[NSNotificationCenter.defaultCenter postNotificationName:@"TIOGlassesLogChanged" object:nil];});}
static NSString *SHA(NSData *b){if(!b.length)return nil;unsigned char h[CC_SHA256_DIGEST_LENGTH];CC_SHA256(b.bytes,(CC_LONG)b.length,h);NSMutableString *s=[NSMutableString new];for(unsigned i=0;i<sizeof(h);i++)[s appendFormat:@"%02x",h[i]];return s;}
static void Restore(void){
 if(Archive||Restoring||Copying)return;Restoring=YES;NSURL *dir=Directory();NSDictionary *owner=Gate().snapshot;
 dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
   NSData *raw=[NSData dataWithContentsOfURL:[dir URLByAppendingPathComponent:@"archive.json"]];id receipt=raw?[NSJSONSerialization JSONObjectWithData:raw options:0 error:nil]:nil;
   NSURL *valid=nil;BOOL recovered=NO;
   if([receipt isKindOfClass:NSDictionary.class]){id name=receipt[@"savedName"],bytes=receipt[@"bytes"],hash=receipt[@"sha256"];
     BOOL named=[name isKindOfClass:NSString.class]&&[name isEqual:[name lastPathComponent]]&&[name hasPrefix:@"research-"]&&[name hasSuffix:@".tar.lz4"];
     BOOL matched=owner.count&&[receipt[@"device"] isEqual:owner[@"device"]]&&TIOGlassesLogTaskID(receipt[@"task"]);
     if(named&&matched&&[bytes isKindOfClass:NSNumber.class]&&[bytes unsignedLongLongValue]>0&&[bytes unsignedLongLongValue]<=32*1024*1024&&[hash isKindOfClass:NSString.class]){
       NSURL *u=[dir URLByAppendingPathComponent:name];NSDictionary *candidate=@{@"fileName":name,@"filePath":u.path};u=TIOGlassesLogLocalURL(candidate,[NSURL fileURLWithPath:NSHomeDirectory()],32*1024*1024);
       NSData *b=u?[NSData dataWithContentsOfURL:u options:NSDataReadingMappedIfSafe error:nil]:nil;
       if(b.length==[bytes unsignedLongLongValue]&&[SHA(b) isEqual:hash]){valid=u;recovered=[receipt[@"source"] isEqual:@"mac-recovered-v1"];}
     }
   }
   dispatch_async(dispatch_get_main_queue(),^{Restoring=NO;
     if(valid&&[Gate() reconcileRecoveredTask:receipt[@"task"] device:receipt[@"device"]]&&Save(@"owner.json",Gate().snapshot)){
       Archive=valid;[NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions:@0600,NSFileProtectionKey:NSFileProtectionCompleteUntilFirstUserAuthentication} ofItemAtPath:valid.path error:nil];[valid setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil];
       Changed(recovered?@"Recovered initial log copy, ready to share; SHA-256 verified.":@"Recovered local log copy, ready to share; SHA-256 verified.",@{@"recoveredFromMac":@(recovered),@"bytes":receipt[@"bytes"]});
     }else Changed(raw?@"Archive recovery credential exists but verification failed; not re-collected.":owner.count?@"Historical task detected; no verifiable copy yet.":@"Not collected yet. First confirm the official glasses connection and then request it again.",@{@"restoreFailed":@(raw!=nil)});
   });
 });
}
void TIOGlassesLogObserveCall(id plugin,NSString *method,NSDictionary *args){
 if(!NSThread.isMainThread||![method isEqual:@"rayneonet_sendMessage"]||![args[@"businessId"] isEqual:@15]||![args[@"deviceId"] isKindOfClass:NSString.class]||!TIOA2UIDecode(Bytes(args[@"payload"])))return;
 Device=args[@"deviceId"];Plugin=plugin;NSMutableDictionary *r=[args mutableCopy];[r removeObjectForKey:@"payload"];Route=r;RouteAt=NSDate.date.timeIntervalSince1970;
}
BOOL TIOGlassesLogBlockCall(id call){
 if((__bridge void *)call==OwnCall)return NO;id args=Get(call,@"arguments");
 if(![Get(call,@"method") isEqual:@"rayneonet_sendMessage"]||![args isKindOfClass:NSDictionary.class]||![args[@"businessId"] isEqual:@11])return NO;
 NSDictionary *pb=TIOA2UIDecode(Bytes(args[@"payload"]));return [pb[@"type"] isEqual:@16]&&[Gate() ownsRequestForDevice:args[@"deviceId"]];
}
BOOL TIOGlassesLogConsumeEvent(NSDictionary *event){
 // Synchronous decision before Flutter delivery, not a late async observer.
 NSDictionary *decision;@synchronized(Gate()){NSDictionary *before=Gate().snapshot;decision=[Gate() accept:event];if(![decision[@"consume"] boolValue])return NO;if(![before isEqual:Gate().snapshot])Save(@"owner.json",Gate().snapshot);}
 NSDictionary *candidate=decision[@"candidate"],*ack=decision[@"ack"];
 dispatch_async(dispatch_get_main_queue(),^{
   if(ack)Changed(@"Intercepted glasses log task receipt; waiting for matching UUID archive.",@{@"ackStatus":ack[@"status"],@"hasTaskID":@([ack[@"taskID"] length]>0)});
   if([decision[@"awaitingAck"] boolValue])Changed(@"Archive event preceded receipt: isolated, waiting for UUID match.",@{});
   if([decision[@"mismatch"] boolValue])Changed(@"Log event mismatch: isolated, no retry.",@{});
   if(!candidate||Copying||Archive)return;
   if(!TIOGlassesLogWindowValid(Started,NSDate.date.timeIntervalSince1970,UIApplication.sharedApplication.applicationState==UIApplicationStateActive,YES)){Changed(@"Late or background file events have been isolated and not copied; the original file is retained and the task result is unknown",@{});return;}
   Copying=YES;NSURL *dir=Directory(),*home=[NSURL fileURLWithPath:NSHomeDirectory()];
   dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
     NSURL *copy=TIOGlassesLogCopy(candidate,home,dir,32*1024*1024);NSMutableDictionary *meta=[NSMutableDictionary new];
     if(copy){[NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions:@0600,NSFileProtectionKey:NSFileProtectionCompleteUntilFirstUserAuthentication} ofItemAtPath:copy.path error:nil];[copy setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil];
       NSData *b=[NSData dataWithContentsOfURL:copy options:NSDataReadingMappedIfSafe error:nil];if(b.length){unsigned char hash[CC_SHA256_DIGEST_LENGTH];CC_SHA256(b.bytes,(CC_LONG)b.length,hash);NSMutableString *hex=[NSMutableString new];for(unsigned i=0;i<sizeof(hash);i++)[hex appendFormat:@"%02x",hash[i]];meta[@"bytes"]=@(b.length);meta[@"sha256"]=hex;}else{meta[@"hashReadFailed"]=@YES;}
       meta[@"savedName"]=copy.lastPathComponent;meta[@"formatVerified"]=@NO;
     }
     dispatch_async(dispatch_get_main_queue(),^{Copying=NO;Archive=copy;if(copy&&meta[@"sha256"]){NSMutableDictionary *receipt=[meta mutableCopy];receipt[@"device"]=Gate().snapshot[@"device"];receipt[@"task"]=Gate().snapshot[@"task"];receipt[@"source"]=@"native-receiver";Save(@"archive.json",receipt);}Changed(copy?@"A copy of the independent log has been saved; the original has not been deleted and this module has not been uploaded. Compression format to be verified by Mac":@"Archive path/file verification failed, Not Saved; original file not deleted, not retried",meta);});
   });
 });return YES;
}
static BOOL Ready(void){return Plugin&&Route&&Device.length&&UIApplication.sharedApplication.applicationState==UIApplicationStateActive&&NSDate.date.timeIntervalSince1970-RouteAt>=0&&NSDate.date.timeIntervalSince1970-RouteAt<120&&!Gate().snapshot.count;}
static void Start(void){
 if(Archive){Changed(@"Session log saved, ready to share.",@{});return;}
 if(Gate().snapshot.count){Changed(@"Session task created, not duplicate sent.",@{@"alreadyArmed":@YES});return;}
 if(!Ready()){Changed(@"Not sent: no recent official communication. Confirm connection on official home page.",@{@"notSubmitted":@YES});return;}
 Class typed=NSClassFromString(@"FlutterStandardTypedData"),cls=NSClassFromString(@"FlutterMethodCall");SEL make=NSSelectorFromString(@"methodCallWithMethodName:arguments:"),bytes=NSSelectorFromString(@"typedDataWithBytes:"),handle=NSSelectorFromString(@"handleMethodCall:result:");
 if(![typed respondsToSelector:bytes]||![cls respondsToSelector:make]||![Plugin respondsToSelector:handle]){Changed(@"Not sent: official transport ABI not available",@{});return;}
 uint32_t seq=arc4random_uniform(0x3fffffff)+1;NSData *packet=TIOA2UIPacket(16,seq,@{@"cmd":@"start_log_task",@"payload":@{@"value":@0,@"mode":@0,@"data":@""}});
 NSMutableDictionary *a=[Route mutableCopy];a[@"businessId"]=@11;a[@"payload"]=((id(*)(id,SEL,id))objc_msgSend)(typed,bytes,packet);id call=((id(*)(id,SEL,id,id))objc_msgSend)(cls,make,@"rayneonet_sendMessage",a);
 if(![Gate() beginForDevice:Device]||!Save(@"owner.json",Gate().snapshot)){Changed(@"Not sent: cannot establish persistent isolation record.",@{});return;}
 Started=NSDate.date.timeIntervalSince1970;Changed(@"Requested glasses log once; 180s receive window, no auto-retry.",@{@"sequence":@(seq)});
 OwnCall=(__bridge void *)call;@try{((void(*)(id,SEL,id,id))objc_msgSend)(Plugin,handle,call,[^(id r){BOOL accepted=[r isKindOfClass:NSDictionary.class]&&[r[@"success"] isEqual:@YES];Changed(accepted?@"SDK received the request, still requires glasses receipt and archiving":@"The SDK callback is not confirmed as successful and the result is unknown; no retry and isolation is retained.",@{@"transportAccepted":@(accepted)});} copy]);}@catch(NSException *e){Changed(@"Send call exception, result unknown; isolated and retained, no retry",@{});}@finally{OwnCall=NULL;}
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,180*NSEC_PER_SEC),dispatch_get_main_queue(),^{if(!Archive&&!Copying)Changed(@"Not Saved archived in 180 seconds, the result is unknown. The glasses task has not been canceled; late events will continue to be isolated and will not be retried.",@{});});
}
@interface TIOGlassesLogPanel:UITableViewController @end
@implementation TIOGlassesLogPanel
- (void)viewDidLoad{[super viewDidLoad];self.title=@"Glasses Logs · Device Only";[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refresh) name:@"TIOGlassesLogChanged" object:nil];Restore();}
- (void)dealloc{[NSNotificationCenter.defaultCenter removeObserver:self];}
- (void)refresh{[self.tableView reloadData];}
- (NSInteger)tableView:(UITableView *)v numberOfRowsInSection:(NSInteger)s{return 3;}
- (UITableViewCell *)tableView:(UITableView *)v cellForRowAtIndexPath:(NSIndexPath *)p{UITableViewCell *c=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];c.textLabel.text=@[@"Current status · log-local-v2",@"Request a glasses log",@"Share a saved copy"][p.row];c.textLabel.numberOfLines=c.detailTextLabel.numberOfLines=0;c.accessibilityIdentifier=[NSString stringWithFormat:@"glasses-log-%ld",(long)p.row];if(p.row==0)c.detailTextLabel.text=[NSString stringWithFormat:@"%@\nSending context: %@\nTask record: %@",Note,Ready()?@"Available":@"Not available",Gate().snapshot.count?@"Established (preserved across reboots)":@"Not created"];return c;}
- (NSString *)tableView:(UITableView *)v titleForFooterInSection:(NSInteger)s{return @"Investigate log paths only. Before testing, please turn off the Internet on your mobile phone but keep Bluetooth, and end the recording/prompt/conversation; do not click on official feedback or log upload at the same time. Isolation only covers this log event and is not a full-App network firewall. The task is only allowed once, and timeout does not mean that the glasses stop. Quarantine records are retained across reboots. New official log tasks are released after all matching files are collected; when the results are unknown, repeated packaging is still prevented and other businesses are not affected.";}
- (void)tableView:(UITableView *)v didSelectRowAtIndexPath:(NSIndexPath *)p{[v deselectRowAtIndexPath:p animated:YES];if(!p.row){[self refresh];return;}if(p.row==2){if(!Archive){Restore();return;}UIActivityViewController *a=[[UIActivityViewController alloc]initWithActivityItems:@[Archive] applicationActivities:nil];a.popoverPresentationController.sourceView=self.view;a.popoverPresentationController.sourceRect=CGRectMake(20,100,1,1);[self presentViewController:a animated:YES completion:nil];return;}
 UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Device-Only Log Verification?" message:@"First turn off the mobile Internet, keep Bluetooth, and end other glasses tasks. This action causes Glass to generate a log archive; which may contain private information. The extension accepts this task, does not call upload, does not automatically decompress, and does not delete the original. Please do not operate the official log feedback before recovery." preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];[a addAction:[UIAlertAction actionWithTitle:@"The Internet has been disconnected, start again" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){Start();}]];[self presentViewController:a animated:YES completion:nil];
}
@end
UIViewController *TIOGlassesLogController(void){return [[TIOGlassesLogPanel alloc]initWithStyle:UITableViewStyleInsetGrouped];}
