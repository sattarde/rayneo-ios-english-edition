#import "TodoRuntime.h"
#if TIO_NATIVE_NAV
#import "DisplayPhoneUI.h"
#import "ImageUploadTransport.h"
#endif
#if TIO_OTA_RESEARCH_ENABLED
#import "ExperimentalOTAFlash.h"
#import "ExperimentalOTAGuard.h"
#endif
#import "ProtocolContext.h"
#import "NavigationTransport.h"
#import "SubtitleHUD.h"
#import "TodoProtocol.h"
#import "NewsReader.h"
#import "NewsTeleprompter.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

// Only observed public ObjC callbacks. No Dart pointer invocation or cloud tokens.
static void (*PriorMethod)(id,SEL,id,id);
static void (*PriorSend)(id,SEL,id,id,id);
static NSDictionary *Snapshot,*Baseline;
static NSString *Device,*TestTitle,*TestWire,*TestDevice,*State=@"No official todo list observed yet";
static NSTimeInterval SnapshotAt,TemplateAt;
static id Template;
static __weak id Listener;
static BOOL Installed,Busy,PhysicalComplete,Injecting;
static NSUInteger Snapshots,TaskEvents,PhysicalEvents;
static id ChatContext;
static __weak id ChatListener;
static NSTimeInterval ChatAt;
static BOOL ToolOperation,ToolDispatching;
static void (^ToolCompletion)(NSDictionary *);
static NSString *const UnresolvedKey=@"io.turboio.todo.unresolvedSubmission";
static void CompleteTool(NSString *status){void (^done)(NSDictionary *)=[ToolCompletion copy];ToolCompletion=nil;if(done)done(@{@"status":status});}
BOOL TIOTodoIsToolDispatching(void){return ToolDispatching;}
void TIOTodoSetChatContext(id listener,id response){ChatListener=listener;ChatContext=response;ChatAt=[NSDate.date timeIntervalSince1970];}
static id Get(id o,NSString *k){@try{return [o valueForKey:k];}@catch(NSException *e){return nil;}}
static NSData *Data(id v){if([v isKindOfClass:NSData.class])return v;if([NSStringFromClass([v class]) isEqual:@"FlutterStandardTypedData"]){id d=Get(v,@"data");if([d isKindOfClass:NSData.class])return d;}return nil;}
static NSString *Text(id o){return [o isKindOfClass:NSString.class]?o:@"";}
static NSDictionary *Task(id params){if(![params isKindOfClass:NSDictionary.class])return nil;id t=params[@"task"];if([t isKindOfClass:NSString.class]&&[t length]<65536)t=[NSJSONSerialization JSONObjectWithData:[t dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];return [t isKindOfClass:NSDictionary.class]?t:nil;}
static BOOL Sign(Method m,NSUInteger n){if(!m||method_getNumberOfArguments(m)!=n)return NO;char *r=method_copyReturnType(m);BOOL ok=r&&r[0]=='v';free(r);for(NSUInteger i=2;i<n;i++){char *t=method_copyArgumentType(m,(unsigned)i);ok=ok&&t&&t[0]=='@';free(t);}return ok;}
static void SaveEvidence(void){
    // No official transcript or unrelated tasks. Only the named test and metadata.
    NSMutableDictionary *row=[@{@"state":State?:@"",@"snapshots":@(Snapshots),@"taskEvents":@(TaskEvents),@"physicalEvents":@(PhysicalEvents),@"testTitle":TestTitle?:@"",@"testWireId":TestWire?:@"",@"physicalComplete":@(PhysicalComplete),@"time":@([NSDate.date timeIntervalSince1970])} mutableCopy];
    row[@"toolOperation"]=@(ToolOperation);if(ToolOperation){row[@"testTitle"]=@"";row[@"testWireId"]=@"";} // No user task contents/IDs in diagnostic file.
    NSString *dir=[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/TurboIOPrivateAddon"];
    [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil];
    NSURL *url=[NSURL fileURLWithPath:[dir stringByAppendingPathComponent:@"todo-runtime-test.json"]];NSData *data=[NSJSONSerialization dataWithJSONObject:row options:0 error:nil];[data writeToURL:url options:NSDataWritingAtomic error:nil];[NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:url.path error:nil];
}
static void ObserveSnapshot(NSDictionary *args){
    if(![args isKindOfClass:NSDictionary.class]||![args[@"businessId"] isEqual:@22])return;NSDictionary *s=TIOTodoSnapshot(Data(args[@"payload"]));
    NSString *device=Text(args[@"deviceId"]);if(!s||!device.length||device.length>200)return;
    Snapshots++;BOOL full=[s[@"isLastBatch"] boolValue]&&[s[@"total"] unsignedIntegerValue]==[s[@"items"] count];
    if(!full){Snapshot=nil;State=@"Received batch list; not used as full baseline";SaveEvidence();return;}
    if(Busy){if(![device isEqual:TestDevice]){Busy=NO;State=@"Device changed; test stopped";if(ToolOperation)CompleteTool(@"unknown");}
        else{NSDictionary *candidate=TIOTodoNewCandidate(Baseline,s,TestTitle);if(candidate){TestWire=candidate[@"wireId"];Busy=NO;State=@"New unique item appeared with matched wire ID";if(ToolOperation){[NSUserDefaults.standardUserDefaults removeObjectForKey:UnresolvedKey];[NSUserDefaults.standardUserDefaults synchronize];CompleteTool(@"created");}}}
    }
    Snapshot=s;Device=device;SnapshotAt=[NSDate.date timeIntervalSince1970];
    if(!Busy&&!TestWire.length)State=Template?@"Official list and template ready; can test creation":@"Full official baseline acquired; awaiting voice template";SaveEvidence();
}
static void MethodHook(id self,SEL cmd,id call,id result){
#if TIO_OTA_RESEARCH_ENABLED
    if(TIOOTAFlashBlockCall(call)){if(result)((void(^)(id))result)(@{@"success":@NO,@"message":@"Turbo IO experimental transfer gate: not authorized or packet mismatch"});return;}
#endif
    {NSString *method=Get(call,@"method");id args=Get(call,@"arguments");if([args isKindOfClass:NSDictionary.class]){void(^work)(void)=^{TIOProtocolObserveCall(self,method,args);TIONewsTeleObserveCall(self,method,args);TIONavObserveCall(self,method,args);TIOSubtitleObserveCall(self,method,args);};if(NSThread.isMainThread)work();else dispatch_async(dispatch_get_main_queue(),work);}}
    if([Get(call,@"method") isEqual:@"rayneonet_sendMessage"]){id args=Get(call,@"arguments");if([args isKindOfClass:NSDictionary.class]&&[args[@"businessId"] isEqual:@22]){void (^work)(void)=^{ObserveSnapshot(args);};if(NSThread.isMainThread)work();else dispatch_async(dispatch_get_main_queue(),work);}}
    id args=Get(call,@"arguments");
    if([Get(call,@"method") isEqual:@"rayneonet_sendFile"]&&[args isKindOfClass:NSDictionary.class]&&result){
        void(^original)(id)=result;
        PriorMethod(self,cmd,call,[^(id response){dispatch_async(dispatch_get_main_queue(),^{TIONewsTeleObserveFileResult(args,response);});original(response);} copy]);
    }else PriorMethod(self,cmd,call,result);
}
static void Send(id self,SEL cmd,NSString *channel,NSData *message,id reply){
    if([channel isKindOfClass:NSString.class]&&[channel.lowercaseString containsString:@"rayneonet"]&&message.length<262144){
        Class cls=NSClassFromString(@"FlutterStandardMethodCodec");
        @try{if([cls respondsToSelector:@selector(sharedInstance)]){id codec=((id(*)(id,SEL))objc_msgSend)(cls,@selector(sharedInstance));id event=((id(*)(id,SEL,id))objc_msgSend)(codec,NSSelectorFromString(@"decodeEnvelope:"),message);
#if TIO_NATIVE_NAV
            if(TIOImageUploadRouteFileEvent(event, ^BOOL(NSDictionary *e){return TDPPhoneConsumeEvent(e);}, ^(BOOL owned){
                if(owned){if(reply)((void(^)(NSData *))reply)(nil);}else PriorSend(self,cmd,channel,message,reply);
            }))return;
#endif
            if([event isKindOfClass:NSDictionary.class]&&[event[@"eventType"] isEqual:@"messageReceived"]&&[event[@"message"] isKindOfClass:NSDictionary.class]){
                NSMutableDictionary *e=[event mutableCopy],*m=[event[@"message"] mutableCopy];NSData *data=Data(m[@"payload"]);if(data)m[@"payload"]=data;e[@"message"]=m;NSDictionary *physical=TIOTodoPhysicalStatus(e);
#if TIO_OTA_RESEARCH_ENABLED
                TIOOTAFlashObserveEvent(e);
#if TIO_NATIVE_NAV
                if(TDPPhoneRouteReply(e,^(BOOL owned){if(owned){if(reply)((void(^)(NSData *))reply)(nil);}else PriorSend(self,cmd,channel,message,reply);}))return;
#endif
#endif
                dispatch_async(dispatch_get_main_queue(),^{TIOProtocolObserveEvent(e);TIONewsTeleObserveEvent(e);TIONavObserveEvent(e);TIOSubtitleObserveEvent(e);});
                if(physical)dispatch_async(dispatch_get_main_queue(),^{PhysicalEvents++;if(TestWire.length&&[physical[@"wireId"] isEqual:TestWire]&&[physical[@"deviceId"] isEqual:TestDevice]){PhysicalComplete=[physical[@"status"] isEqual:@1];State=PhysicalComplete?@"Received glasses completion event for this test item":@"Received glasses incomplete event for this test item";SaveEvidence();}});
            }
        }}@catch(NSException *e){}
    }PriorSend(self,cmd,channel,message,reply);
}
void TIOTodoObserveNlp(id listener,id response){
    if(Injecting||!Installed||![Get(response,@"domain") isEqual:@"task"]||![Get(response,@"intent") isEqual:@"create_task"]||![Get(response,@"finished") boolValue]||[Get(response,@"offline") boolValue])return;
    TaskEvents++;id command=Get(response,@"command"),params=Get(command,@"params");
    if(![Get(command,@"name") isEqual:@"create_task"]||!TIOTodoCreateIntent(@"task",@"create_task",params)){State=@"Official callback received but parameter schema mismatch";SaveEvidence();return;}
    Template=response;Listener=listener;TemplateAt=[NSDate.date timeIntervalSince1970];State=@"Official template acquired; ready for one test run";SaveEvidence();
}
NSDictionary *TIOTodoRuntimeStatus(void){return @{@"installed":@(Installed),@"snapshots":@(Snapshots),@"taskEvents":@(TaskEvents),@"physicalEvents":@(PhysicalEvents),@"hasBaseline":@(Snapshot!=nil),@"hasTemplate":@(Template!=nil&&Listener!=nil),@"busy":@(Busy),@"state":State?:@"",@"testTitle":TestTitle?:@"",@"hasWireId":@(TestWire.length>0),@"physicalComplete":@(PhysicalComplete)};}
void TIOTodoCreateFromTool(NSString *title,void (^completion)(NSDictionary *result)){
    if(!NSThread.isMainThread||!completion)return;
    NSDictionary *valid=TIOTodoCreateIntent(@"task",@"create_task",@{@"task":@{@"content":title?:@""}});
    if(!valid||Busy||[NSUserDefaults.standardUserDefaults boolForKey:UnresolvedKey]||(TestTitle.length&&!TestWire.length)){completion(@{@"status":@"rejected"});return;}
    NSTimeInterval now=[NSDate.date timeIntervalSince1970];
    if(!Installed||!Snapshot||now-SnapshotAt>120||!ChatContext||!ChatListener||now-ChatAt>120){completion(@{@"status":@"not_ready"});return;}
    title=valid[@"title"];for(NSDictionary *item in Snapshot[@"items"])if([item[@"title"] isEqual:title]){completion(@{@"status":@"rejected"});return;}
    Class rc=NSClassFromString(@"RayNeoNlpResultWrapper"),cc=NSClassFromString(@"NlpCommandWrapper");
    if(![ChatContext isKindOfClass:rc]||!cc){completion(@{@"status":@"not_ready"});return;}
    id response=[rc new],command=[cc new];
    @try{
        // Current live chat supplies correlation fields. Routing constants and
        // JSON-text params.task are from official 1.0.2 observations (v4 probe,
        // plus live successful create-intent parsing). The outer installation
        // is version/UUID guarded. No old task dates or old session IDs reused.
        for(NSString *key in @[@"sub",@"dialogId",@"sessionId",@"domain",@"intent",@"round",@"query",@"spoken",@"answer",@"finished",@"offline",@"hasNextRound",@"rawData"]){id value=Get(ChatContext,key);if(value)[response setValue:value forKey:key];}
        [response setValue:@"task" forKey:@"domain"];[response setValue:@"create_task" forKey:@"intent"];[response setValue:@"workflow" forKey:@"sub"];[response setValue:@YES forKey:@"hasNextRound"];
        NSDictionary *task=@{@"content":title};NSString *inner=[[NSString alloc]initWithData:[NSJSONSerialization dataWithJSONObject:task options:0 error:nil] encoding:NSUTF8StringEncoding];
        [command setValue:@"create_task" forKey:@"name"];[command setValue:@{@"task":inner} forKey:@"params"];[command setValue:NSUUID.UUID.UUIDString forKey:@"commandRequestId"];[command setValue:@{} forKey:@"otherState"];
        [response setValue:command forKey:@"command"];[response setValue:@YES forKey:@"finished"];[response setValue:@NO forKey:@"offline"];[response setValue:@"" forKey:@"answer"];[response setValue:@"" forKey:@"spoken"];[response setValue:@"" forKey:@"rawData"];
    }@catch(NSException *e){completion(@{@"status":@"not_ready"});return;}
    // Crash/restart cannot silently retry an uncertain native submission.
    [NSUserDefaults.standardUserDefaults setBool:YES forKey:UnresolvedKey];if(![NSUserDefaults.standardUserDefaults synchronize]){completion(@{@"status":@"rejected"});return;}
    Baseline=Snapshot;TestDevice=Device;TestTitle=[title copy];TestWire=nil;PhysicalComplete=NO;ToolOperation=YES;ToolCompletion=[completion copy];Busy=YES;
    State=@"create_todo invoked; awaiting real list update";SaveEvidence();
    ToolDispatching=YES;Injecting=YES;
    @try{((void(*)(id,SEL,id))objc_msgSend)(ChatListener,NSSelectorFromString(@"onNlpResult:"),response);}
    @catch(NSException *e){Busy=NO;State=@"create_todo invocation exception";CompleteTool(@"unknown");SaveEvidence();}
    @finally{ToolDispatching=NO;Injecting=NO;}
    NSString *operationTitle=TestTitle;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,25*NSEC_PER_SEC),dispatch_get_main_queue(),^{if(Busy&&ToolOperation&&TestTitle==operationTitle){Busy=NO;State=@"create_todo timeout without unique new ID";CompleteTool(@"unknown");SaveEvidence();}});
}
NSString *TIOTodoCreateTestTask(void){
    if(!NSThread.isMainThread||!Installed)return @"Todo observation entry not ready.";
    if(Busy||TestTitle.length)return @"A test has already been submitted in this session.";
    NSTimeInterval now=[NSDate.date timeIntervalSince1970];
    if(!Snapshot||now-SnapshotAt>120||!Template||!Listener||now-TemplateAt>120)return @"Please create a test todo by voice on your glasses first, then return here within 2 minutes.";
    NSString *title=[@"Turbo Bridge Test " stringByAppendingString:[NSUUID.UUID.UUIDString substringToIndex:6]];
    id sourceCommand=Get(Template,@"command");NSDictionary *sourceParams=Get(sourceCommand,@"params"),*task=Task(sourceParams);
    if(!task||!TIOTodoCreateIntent(@"task",@"create_task",sourceParams))return @"Parameter schema mismatch; not called.";
    Class responseClass=NSClassFromString(@"RayNeoNlpResultWrapper"),commandClass=NSClassFromString(@"NlpCommandWrapper");if(![Template isKindOfClass:responseClass]||![sourceCommand isKindOfClass:commandClass])return @"Official wrapper type mismatch.";
    id response=[responseClass new],command=[commandClass new];if(!response||!command)return @"Cannot construct official wrapper; not called.";
    @try{
        for(NSString *field in @[@"sub",@"dialogId",@"sessionId",@"domain",@"intent",@"round",@"query",@"spoken",@"answer",@"finished",@"offline",@"hasNextRound",@"rawData"]){id value=Get(Template,field);if(value)[response setValue:value forKey:field];}
        NSMutableDictionary *inner=[task mutableCopy];inner[@"content"]=title;NSMutableDictionary *params=[sourceParams mutableCopy];
        params[@"task"]=[sourceParams[@"task"] isKindOfClass:NSString.class]?[[NSString alloc]initWithData:[NSJSONSerialization dataWithJSONObject:inner options:0 error:nil] encoding:NSUTF8StringEncoding]:inner;
        [command setValue:@"create_task" forKey:@"name"];[command setValue:params forKey:@"params"];[command setValue:NSUUID.UUID.UUIDString forKey:@"commandRequestId"];[command setValue:Get(sourceCommand,@"otherState")?:@{} forKey:@"otherState"];
        [response setValue:command forKey:@"command"];[response setValue:[@"Create todo: " stringByAppendingString:title] forKey:@"query"];[response setValue:@"" forKey:@"answer"];[response setValue:@"" forKey:@"spoken"];
    }@catch(NSException *e){return @"Wrapper properties mismatch; not called.";}
    Baseline=Snapshot;TestDevice=Device;TestTitle=title;Busy=YES;State=@"Submitted official callback; awaiting real list update";SaveEvidence();
    // The currently installed listener goes through the existing Addon hook;
    // task domain remains official. No standalone SDK or Bluetooth list rewrite.
    Injecting=YES;
    @try{((void(*)(id,SEL,id))objc_msgSend)(Listener,NSSelectorFromString(@"onNlpResult:"),response);}
    @catch(NSException *e){Busy=NO;State=@"Official callback invocation error";SaveEvidence();}
    @finally{Injecting=NO;}
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,25*NSEC_PER_SEC),dispatch_get_main_queue(),^{if(Busy){Busy=NO;State=@"No new unique item observed within 25s";SaveEvidence();}});
    return [@"Submitted: " stringByAppendingString:title];
}
void TIOInstallTodoRuntime(void){
    if(Installed)return;Method method=class_getInstanceMethod(NSClassFromString(@"rayneo_venus_sdk_plugin.RayneoNetPluginBridge"),NSSelectorFromString(@"handleMethodCall:result:"));Method send=class_getInstanceMethod(NSClassFromString(@"FlutterEngine"),NSSelectorFromString(@"sendOnChannel:message:binaryReply:"));
    if(!Sign(method,4)||!Sign(send,5)){State=@"Observation method signature mismatch; not installed";return;}
    PriorMethod=(void *)method_setImplementation(method,(IMP)MethodHook);PriorSend=(void *)method_setImplementation(send,(IMP)Send);Installed=YES;
#if TIO_OTA_RESEARCH_ENABLED
    TIOOTARecordTransportHookReady();
#endif
}
@interface TIOTodoRuntimePanel:UITableViewController @end
@implementation TIOTodoRuntimePanel
- (void)viewDidLoad{[super viewDidLoad];self.title=@"Todo Protocol Diagnostics";self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc]initWithTitle:@"Refresh" style:UIBarButtonItemStylePlain target:self action:@selector(refresh)];}
- (void)refresh{[self.tableView reloadData];}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s{return 2;}
- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s{return @"Only tests official persistence entry point. Does not overwrite glasses task list. Does not auto-retry. Baseline is kept in process memory only.";}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip{UITableViewCell *c=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];c.detailTextLabel.numberOfLines=0;NSDictionary *s=TIOTodoRuntimeStatus();c.textLabel.text=ip.row?@"Create Bridge Test Todo":s[@"state"];c.textLabel.numberOfLines=0;c.detailTextLabel.text=ip.row?@"Uses official template; no unverified calls":[NSString stringWithFormat:@"Snapshots: %@ · Add Callbacks: %@ · Physical Events: %@\n%@\nWire ID: %@ · Completed: %@",s[@"snapshots"],s[@"taskEvents"],s[@"physicalEvents"],s[@"testTitle"],[s[@"hasWireId"] boolValue]?@"Matched":@"Not matched",[s[@"physicalComplete"] boolValue]?@"Yes":@"No"];return c;}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip{[t deselectRowAtIndexPath:ip animated:YES];if(!ip.row){[self refresh];return;}UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Create Test Todo?" message:@"Attempts to create a test todo with random ID via official flow. Will not touch other tasks or auto-retry." preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];[a addAction:[UIAlertAction actionWithTitle:@"Create Test Todo" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){NSString *result=TIOTodoCreateTestTask();UIAlertController *b=[UIAlertController alertControllerWithTitle:@"Submission Status" message:result preferredStyle:UIAlertControllerStyleAlert];[b addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];[self presentViewController:b animated:YES completion:nil];[self refresh];}]];[self presentViewController:a animated:YES completion:nil];}
@end
void TIOOpenTodoRuntime(id parent){if([parent isKindOfClass:UIViewController.class])[[(UIViewController *)parent navigationController] pushViewController:[[TIOTodoRuntimePanel alloc]initWithStyle:UITableViewStyleInsetGrouped] animated:YES];}
