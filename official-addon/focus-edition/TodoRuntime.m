#import "TodoRuntime.h"
#if TIO_IMAGE_RX_LAB
#import "ImageUploadUI.h"
#import "ImageUploadTransport.h"
#if TIO_DISPLAY_PHONE
#import "DisplayPhoneUI.h"
#import "DisplayDiagnostics.h"
#endif
#endif
#import "ProtocolContext.h"
#import "TodoProtocol.h"
#import "NewsReader.h"
#import "NewsTeleprompter.h"
#import "A2UIProbe.h"
#import "GlassesLogProbe.h"
#import "NavigationTransport.h"
#import "SubtitleHUD.h"
#import "ExperimentalOTAGuard.h"
#import "ExperimentalOTAFlash.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

// Only observed public ObjC callbacks. No Dart pointer invocation or cloud tokens.
static void (*PriorMethod)(id,SEL,id,id);
static void (*PriorSend)(id,SEL,id,id,id);
static NSDictionary *Snapshot,*Baseline;
static NSString *Device,*TestTitle,*TestWire,*TestDevice,*State=@"No official backlog observed yet";
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
static NSArray *LoadCompletedTasks(void){
    NSString *dir=[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/TurboIOPrivateAddon"];
    NSURL *url=[NSURL fileURLWithPath:[dir stringByAppendingPathComponent:@"todo-completed-tasks.json"]];
    NSData *data=[NSData dataWithContentsOfURL:url];
    if(!data.length)return @[];
    NSArray *arr=[NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return [arr isKindOfClass:NSArray.class]?arr:@[];
}
static void SaveEvidence(void);
static void RecordPhysicalCompletion(NSDictionary *physical){
    if(![physical isKindOfClass:NSDictionary.class])return;
    NSString *wireId=[NSString stringWithFormat:@"%@", physical[@"wireId"]?:@""];
    if(!wireId.length)return;
    NSInteger status=[physical[@"status"] integerValue];
    NSString *deviceId=Text(physical[@"deviceId"]);
    NSString *stamp=Text(physical[@"rawModifiedTime"]);

    NSString *matchedTitle=nil;
    if(Snapshot&&[Snapshot[@"items"] isKindOfClass:NSArray.class]){
        NSMutableArray *updatedItems=[NSMutableArray array];
        for(NSDictionary *item in Snapshot[@"items"]){
            NSMutableDictionary *mItem=[item mutableCopy];
            if([[NSString stringWithFormat:@"%@", mItem[@"wireId"]] isEqualToString:wireId]){
                matchedTitle=mItem[@"title"];
                mItem[@"status"]=@(status);
            }
            [updatedItems addObject:mItem];
        }
        NSMutableDictionary *newSnap=[Snapshot mutableCopy];
        newSnap[@"items"]=updatedItems;
        Snapshot=newSnap;
    }

    NSString *dir=[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/TurboIOPrivateAddon"];
    [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil];
    NSURL *completedURL=[NSURL fileURLWithPath:[dir stringByAppendingPathComponent:@"todo-completed-tasks.json"]];

    NSMutableArray *completedList=[NSMutableArray array];
    NSData *existingData=[NSData dataWithContentsOfURL:completedURL];
    if(existingData.length){
        NSArray *arr=[NSJSONSerialization JSONObjectWithData:existingData options:0 error:nil];
        if([arr isKindOfClass:NSArray.class])[completedList addObjectsFromArray:arr];
    }

    BOOL found=NO;
    for(NSUInteger i=0;i<completedList.count;i++){
        NSDictionary *entry=completedList[i];
        if([[NSString stringWithFormat:@"%@", entry[@"wireId"]] isEqualToString:wireId]){
            NSMutableDictionary *updatedEntry=[entry mutableCopy];
            updatedEntry[@"status"]=@(status);
            updatedEntry[@"completed"]=@(status==1);
            updatedEntry[@"lastUpdated"]=@([NSDate.date timeIntervalSince1970]);
            if(matchedTitle.length)updatedEntry[@"title"]=matchedTitle;
            completedList[i]=updatedEntry;
            found=YES;
            break;
        }
    }
    if(!found){
        NSString *taskTitle=matchedTitle.length?matchedTitle:[NSString stringWithFormat:@"Task #%@", wireId];
        [completedList insertObject:@{
            @"wireId":wireId,
            @"title":taskTitle,
            @"status":@(status),
            @"completed":@(status==1),
            @"completedAt":@([NSDate.date timeIntervalSince1970]),
            @"deviceId":deviceId?:@"",
            @"rawModifiedTime":stamp?:@""
        } atIndex:0];
    }

    NSData *outData=[NSJSONSerialization dataWithJSONObject:completedList options:NSJSONWritingPrettyPrinted error:nil];
    [outData writeToURL:completedURL options:NSDataWritingAtomic error:nil];
    [NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:completedURL.path error:nil];

    PhysicalComplete=(status==1);
    TestWire=wireId;
    TestTitle=matchedTitle?:[NSString stringWithFormat:@"Task #%@", wireId];
    if(status==1){
        State=[NSString stringWithFormat:@"Task '%@' marked COMPLETE via glasses tap (ID: %@)", TestTitle, wireId];
    } else {
        State=[NSString stringWithFormat:@"Task '%@' marked INCOMPLETE via glasses tap (ID: %@)", TestTitle, wireId];
    }
    SaveEvidence();
}
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
    if(!full){Snapshot=nil;State=@"Received batch list but did not treat it as full baseline";SaveEvidence();return;}
    if(Busy){if(![device isEqual:TestDevice]){Busy=NO;State=@"Device changed; test stopped, not bound";if(ToolOperation)CompleteTool(@"unknown");}
        else{NSDictionary *candidate=TIOTodoNewCandidate(Baseline,s,TestTitle);if(candidate){TestWire=candidate[@"wireId"];Busy=NO;State=@"The only new item appears in the official list, which has been associated with a real ID; lens acceptance is still required.";if(ToolOperation){[NSUserDefaults.standardUserDefaults removeObjectForKey:UnresolvedKey];[NSUserDefaults.standardUserDefaults synchronize];CompleteTool(@"created");}}}
    }
    Snapshot=s;Device=device;SnapshotAt=[NSDate.date timeIntervalSince1970];
    if(!Busy&&!TestWire.length)State=Template?@"The official list and new templates have been obtained; the creation entrance can be tested":@"The official full list baseline has been obtained; waiting for the official voice template to be added";SaveEvidence();
}
static void MethodHook(id self,SEL cmd,id call,id result){
    BOOL otaBlocked=TIOOTAFlashBlockCall(call);
#if TIO_DISPLAY_PHONE
    if([Get(call,@"method") isEqual:@"rayneonet_sendFile"])TDPDiagRecord(@"gate",@{@"blocked":@(otaBlocked),@"otaStage":TIOOTAFlashStatus()[@"stage"]?:@0});
#endif
    if(otaBlocked){if(result)((void(^)(id))result)(@{@"success":@NO,@"message":@"Turbo IO transfer gate: not authorized or packet mismatch"});return;}
    if(TIOOTABlockPreparationCall(call)){if(result)((void(^)(id))result)(@{@"success":@NO,@"message":@"Turbo IO OTA preparation only: outbound traffic blocked"});return;}
    if(TIOGlassesLogBlockCall(call)){if(result)((void(^)(id))result)(@{@"success":@NO,@"message":@"The local log research task is in isolation and has no repeated requests."});return;}
    {NSString *method=Get(call,@"method");id args=Get(call,@"arguments");if([args isKindOfClass:NSDictionary.class]){void(^work)(void)=^{TIOProtocolObserveCall(self,method,args);TIONewsTeleObserveCall(self,method,args);TIOA2UIObserveCall(self,method,args);TIOGlassesLogObserveCall(self,method,args);TIONavObserveCall(self,method,args);TIOSubtitleObserveCall(self,method,args);};if(NSThread.isMainThread)work();else dispatch_async(dispatch_get_main_queue(),work);}}
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
            if([event isKindOfClass:NSDictionary.class]){NSMutableDictionary *copy=[event mutableCopy];id original=copy[@"message"];if([original isKindOfClass:NSDictionary.class]){NSMutableDictionary *m=[original mutableCopy];NSData *data=Data(m[@"payload"]);if(data)m[@"payload"]=data;copy[@"message"]=m;}
#if TIO_DISPLAY_PHONE
                TDPDiagEnvelope(copy);
#endif
                if(TIOGlassesLogConsumeEvent(copy)){if(reply)((void(^)(NSData *))reply)(nil);return;}}
#if TIO_IMAGE_RX_LAB
            // File results are siblings of messageReceived, not business messages.
            // Only our exact sender task is consumed; foreign events keep Flutter's path.
            if(TIOImageUploadRouteFileEvent(event, ^BOOL(NSDictionary *e){
#if TIO_DISPLAY_PHONE
                if(TDPPhoneConsumeEvent(e))return YES;
#endif
                return TIOImageUploadLabConsumeFileEvent(e);}, ^(BOOL owned){
                if(owned){if(reply)((void(^)(NSData *))reply)(nil);}else PriorSend(self,cmd,channel,message,reply);
            }))return;
#endif
            if([event isKindOfClass:NSDictionary.class]&&[event[@"eventType"] isEqual:@"messageReceived"]&&[event[@"message"] isKindOfClass:NSDictionary.class]){
                NSMutableDictionary *e=[event mutableCopy],*m=[event[@"message"] mutableCopy];NSData *data=Data(m[@"payload"]);if(data)m[@"payload"]=data;e[@"message"]=m;TIOOTAFlashObserveEvent(e);NSDictionary *physical=TIOTodoPhysicalStatus(e);
#if TIO_DISPLAY_PHONE
                if(TDPPhoneRouteReply(e,^(BOOL owned){if(owned){if(reply)((void(^)(NSData *))reply)(nil);}else PriorSend(self,cmd,channel,message,reply);}))return;
#endif
                if([m[@"businessId"] isEqual:@20]){
                    // Own manuscripts live in TurboIO, not the official Dart
                    // repository. Let our state machine consume their replies
                    // before Flutter mistakes the unknown DID for a deleted doc.
                    // Foreign DID/device, list messages and unknown types pass.
                    void(^work)(void)=^{BOOL own=TIONewsTeleOwnsEvent(e);TIOProtocolObserveEvent(e);TIONewsTeleObserveEvent(e);TIOA2UIObserveEvent(e);TIONavObserveEvent(e);TIOSubtitleObserveEvent(e);if(own){if(reply)((void(^)(NSData *))reply)(nil);}else PriorSend(self,cmd,channel,message,reply);};
                    if(NSThread.isMainThread)work();else dispatch_async(dispatch_get_main_queue(),work);return;
                }
                dispatch_async(dispatch_get_main_queue(),^{TIOProtocolObserveEvent(e);TIONewsTeleObserveEvent(e);TIOA2UIObserveEvent(e);TIONavObserveEvent(e);TIOSubtitleObserveEvent(e);});
                if(physical)dispatch_async(dispatch_get_main_queue(),^{PhysicalEvents++;RecordPhysicalCompletion(physical);});
            }
        }}@catch(NSException *e){}
    }PriorSend(self,cmd,channel,message,reply);
}
void TIOTodoObserveNlp(id listener,id response){
    if(Injecting||!Installed||![Get(response,@"domain") isEqual:@"task"]||![Get(response,@"intent") isEqual:@"create_task"]||![Get(response,@"finished") boolValue]||[Get(response,@"offline") boolValue])return;
    TaskEvents++;id command=Get(response,@"command"),params=Get(command,@"params");
    if(![Get(command,@"name") isEqual:@"create_task"]||!TIOTodoCreateIntent(@"task",@"create_task",params)){State=@"The official new callback has been received, but the parameter shapes do not match; construction calls are prohibited";SaveEvidence();return;}
    Template=response;Listener=listener;TemplateAt=[NSDate.date timeIntervalSince1970];State=@"The real official new template has been obtained; a naming test can be performed";SaveEvidence();
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
    State=@"create_todo has called the official entrance; waiting for the real list and not claiming that the creation was successful";SaveEvidence();
    ToolDispatching=YES;Injecting=YES;
    @try{((void(*)(id,SEL,id))objc_msgSend)(ChatListener,NSSelectorFromString(@"onNlpResult:"),response);}
    @catch(NSException *e){Busy=NO;State=@"Create_todo call exception, the result is unknown; retry is prohibited";CompleteTool(@"unknown");SaveEvidence();}
    @finally{ToolDispatching=NO;Injecting=NO;}
    NSString *operationTitle=TestTitle;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,25*NSEC_PER_SEC),dispatch_get_main_queue(),^{if(Busy&&ToolOperation&&TestTitle==operationTitle){Busy=NO;State=@"create_todo does not confirm unique new ID, result unknown; retry prohibited";CompleteTool(@"unknown");SaveEvidence();}});
}
NSString *TIOTodoCreateTestTask(void){
    if(!NSThread.isMainThread||!Installed)return @"The pending observation portal is not ready.";
    if(Busy||TestTitle.length)return @"This process has already been submitted to testing once; it will not be automatically retried or re-created.";
    NSTimeInterval now=[NSDate.date timeIntervalSince1970];
    if(!Snapshot||now-SnapshotAt>120||!Template||!Listener||now-TemplateAt>120)return @"Please use Glass Voice to add a special test to-do first, and then return to this page within two minutes to test.";
    NSString *title=[@"Turbo bridge entry test" stringByAppendingString:[NSUUID.UUID.UUIDString substringToIndex:6]];
    id sourceCommand=Get(Template,@"command");NSDictionary *sourceParams=Get(sourceCommand,@"params"),*task=Task(sourceParams);
    if(!task||!TIOTodoCreateIntent(@"task",@"create_task",sourceParams))return @"Parameter shape mismatch, not called.";
    Class responseClass=NSClassFromString(@"RayNeoNlpResultWrapper"),commandClass=NSClassFromString(@"NlpCommandWrapper");if(![Template isKindOfClass:responseClass]||![sourceCommand isKindOfClass:commandClass])return @"Official packaging type does not match.";
    id response=[responseClass new],command=[commandClass new];if(!response||!command)return @"Unable to construct official wrapper, not called.";
    @try{
        for(NSString *field in @[@"sub",@"dialogId",@"sessionId",@"domain",@"intent",@"round",@"query",@"spoken",@"answer",@"finished",@"offline",@"hasNextRound",@"rawData"]){id value=Get(Template,field);if(value)[response setValue:value forKey:field];}
        NSMutableDictionary *inner=[task mutableCopy];inner[@"content"]=title;NSMutableDictionary *params=[sourceParams mutableCopy];
        params[@"task"]=[sourceParams[@"task"] isKindOfClass:NSString.class]?[[NSString alloc]initWithData:[NSJSONSerialization dataWithJSONObject:inner options:0 error:nil] encoding:NSUTF8StringEncoding]:inner;
        [command setValue:@"create_task" forKey:@"name"];[command setValue:params forKey:@"params"];[command setValue:NSUUID.UUID.UUIDString forKey:@"commandRequestId"];[command setValue:Get(sourceCommand,@"otherState")?:@{} forKey:@"otherState"];
        [response setValue:command forKey:@"command"];[response setValue:[@"Create to-do" stringByAppendingString:title] forKey:@"query"];[response setValue:@"" forKey:@"answer"];[response setValue:@"" forKey:@"spoken"];
    }@catch(NSException *e){return @"Wrapping properties mismatch, not called.";}
    Baseline=Snapshot;TestDevice=Device;TestTitle=title;Busy=YES;State=@"Only submit the official creation callback once; waiting for the official real list and ID, no success declared";SaveEvidence();
    // The currently installed listener goes through the existing Addon hook;
    // task domain remains official. No standalone SDK or Bluetooth list rewrite.
    Injecting=YES;
    @try{((void(*)(id,SEL,id))objc_msgSend)(Listener,NSSelectorFromString(@"onNlpResult:"),response);}
    @catch(NSException *e){Busy=NO;State=@"The official callback call is abnormal; the result is unknown and retry is prohibited.";SaveEvidence();}
    @finally{Injecting=NO;}
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,25*NSEC_PER_SEC),dispatch_get_main_queue(),^{if(Busy){Busy=NO;State=@"No unique new item observed within 25 seconds; result unknown, no automatic resend";SaveEvidence();}});
    return [@"Submitted:" stringByAppendingString:title];
}
void TIOInstallTodoRuntime(void){
    if(Installed)return;Method method=class_getInstanceMethod(NSClassFromString(@"rayneo_venus_sdk_plugin.RayneoNetPluginBridge"),NSSelectorFromString(@"handleMethodCall:result:"));Method send=class_getInstanceMethod(NSClassFromString(@"FlutterEngine"),NSSelectorFromString(@"sendOnChannel:message:binaryReply:"));
    if(!Sign(method,4)||!Sign(send,5)){State=@"Watch method signature mismatch, not installed";return;}
    PriorMethod=(void *)method_setImplementation(method,(IMP)MethodHook);PriorSend=(void *)method_setImplementation(send,(IMP)Send);Installed=YES;TIOOTARecordTransportHookReady();
}
@interface TIOTodoRuntimePanel:UITableViewController @end
@implementation TIOTodoRuntimePanel{
    NSArray *_completedTasks;
}
- (void)viewDidLoad{
    [super viewDidLoad];
    self.title=@"Todo Verification & Reverse Sync";
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc]initWithTitle:@"Refresh" style:UIBarButtonItemStylePlain target:self action:@selector(refresh)];
    [self loadTasks];
}
- (void)loadTasks{
    _completedTasks=LoadCompletedTasks();
    [self.tableView reloadData];
}
- (void)refresh{
    [self loadTasks];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView{
    return 3;
}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s{
    if(s==0) return 1;
    if(s==1) return MAX(1, (NSInteger)_completedTasks.count);
    return 1;
}
- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s{
    if(s==0) return @"Sync Status & Diagnostics";
    if(s==1) return [NSString stringWithFormat:@"Completed Tasks (Glasses Reverse Sync: %lu)", (unsigned long)_completedTasks.count];
    return @"Testing Actions";
}
- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s{
    if(s==0) return @"Tap temple on glasses to complete any to-do item. The glasses will send packet businessId: 22, status: 1 which is reverse-synced here.";
    if(s==1) return @"Tasks marked completed on glasses are saved locally in the companion database.";
    return @"Create dedicated test items through official NLP channel.";
}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip{
    UITableViewCell *c=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    c.detailTextLabel.numberOfLines=0;
    if(ip.section==0){
        NSDictionary *s=TIOTodoRuntimeStatus();
        c.textLabel.text=s[@"state"];
        c.textLabel.numberOfLines=0;
        c.detailTextLabel.text=[NSString stringWithFormat:@"Snapshots: %@ · Task Events: %@ · Temple Taps: %@\nMatched ID: %@ · Completed: %@",
            s[@"snapshots"], s[@"taskEvents"], s[@"physicalEvents"],
            [s[@"hasWireId"] boolValue]?s[@"testTitle"]:@"None",
            [s[@"physicalComplete"] boolValue]?@"YES":@"NO"];
        return c;
    }
    if(ip.section==1){
        if(!_completedTasks.count){
            c.textLabel.text=@"No completed tasks recorded yet";
            c.textLabel.textColor=UIColor.secondaryLabelColor;
            c.detailTextLabel.text=@"Open Item 3 (To-Do) on glasses and tap temple on an item to complete it.";
            return c;
        }
        NSDictionary *task=_completedTasks[ip.row];
        c.textLabel.text=[NSString stringWithFormat:@"✓ %@", task[@"title"]?:@"Unknown Task"];
        c.textLabel.textColor=UIColor.labelColor;
        NSDate *d=[NSDate dateWithTimeIntervalSince1970:[task[@"completedAt"] doubleValue]];
        NSDateFormatter *df=[NSDateFormatter new];
        df.dateStyle=NSDateFormatterShortStyle;
        df.timeStyle=NSDateFormatterMediumStyle;
        c.detailTextLabel.text=[NSString stringWithFormat:@"Wire ID: %@ · Status: %@ · Completed: %@",
            task[@"wireId"], [task[@"status"] isEqual:@1]?@"Completed":@"Active", [df stringFromDate:d]];
        return c;
    }
    c.textLabel.text=@"Create bridge test backlog item";
    c.detailTextLabel.text=@"Submits a test task via official voice template pipeline.";
    return c;
}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip{
    [t deselectRowAtIndexPath:ip animated:YES];
    if(ip.section==0){[self refresh];return;}
    if(ip.section==1&&_completedTasks.count){
        NSDictionary *task=_completedTasks[ip.row];
        UIAlertController *a=[UIAlertController alertControllerWithTitle:task[@"title"] message:[NSString stringWithFormat:@"Wire ID: %@\nStatus: %@\nDevice: %@", task[@"wireId"], [task[@"status"] isEqual:@1]?@"Completed (1)":@"Active (0)", task[@"deviceId"]?:@"Unknown"] preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:a animated:YES completion:nil];
        return;
    }
    if(ip.section==2){
        UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Create a dedicated test item?" message:@"An attempt will be made to add a randomly numbered test item through the official to-do process." preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [a addAction:[UIAlertAction actionWithTitle:@"Create test item" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){
            NSString *result=TIOTodoCreateTestTask();
            UIAlertController *b=[UIAlertController alertControllerWithTitle:@"Submit status" message:result preferredStyle:UIAlertControllerStyleAlert];
            [b addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
            [self presentViewController:b animated:YES completion:nil];
            [self refresh];
        }]];
        [self presentViewController:a animated:YES completion:nil];
    }
}
@end
void TIOOpenTodoRuntime(id parent){if([parent isKindOfClass:UIViewController.class])[[(UIViewController *)parent navigationController] pushViewController:[[TIOTodoRuntimePanel alloc]initWithStyle:UITableViewStyleInsetGrouped] animated:YES];}
