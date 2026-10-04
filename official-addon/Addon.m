#import <UIKit/UIKit.h>
#import <Security/Security.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import "Core.h"
#import "NavigationUI.h"
#import "Profile.h"
#import "ProfileUI.h"
#import "RecordingExports.h"
#import "RecordingText.h"
#import "AlwaysOnAudio.h"
#import "WebSearch.h"
#import "TodoRuntime.h"
#import "TodoProtocol.h"
#import "NewsReader.h"
#if TIO_MUSIC
#import "music/MusicPlayer.h"
#endif
#import "PrivateBootstrap.h"
#import "ResearchCatalog.h"
#if TIO_LOCAL_TRANSLATION
#import "local-translation/LocalTranslationEntry.h"
#endif
#import "ResearchUI.h"
#import "VoiceTTS.h"
#if TIO_NATIVE_NAV
#import "DisplayPhoneUI.h"
#endif
#if TIO_OTA_RESEARCH_ENABLED
#import "ExperimentalOTAUI.h"
#import "ExperimentalOTAFeed.h"
#endif
#import "HomeTabBridge.h"
#import "KnowledgeUI.h"
#import "KnowledgeClient.h"

#ifndef TIO_TARGET_BUNDLE_ID
#define TIO_TARGET_BUNDLE_ID "com.rayneo.venus.pub"
#endif
static NSString *const TargetBundle=@TIO_TARGET_BUNDLE_ID;

// No Frida, inline patching, device credentials or official token access.
static NSString *const Domain=@"io.turboio.official-private-addon";
static NSUserDefaults *Prefs;
static TIOTranscriptArchive *Archive;
static dispatch_queue_t ArchiveQueue;
static NSString *Diagnostic=@"Waiting for events";
static BOOL HooksReady=NO;
static UIButton *Entry;
static void (*OriginalAsr)(id,SEL,id,BOOL,id);
static void (*OriginalNlp)(id,SEL,id);
static void (*OriginalComplete)(id,SEL);
static void (*OriginalAlwaysOn)(id,SEL,id);
static void (*OriginalAudioStart)(id,SEL);
static BOOL VoiceExitReady=NO;
static NSUInteger CompletionEvents;
static TIOVoiceTTS *VoiceTTS;

static NSDictionary *KeyQuery(NSString *host) {return @{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,(__bridge id)kSecAttrService:Domain,(__bridge id)kSecAttrAccount:host};}
static NSString *ReadKey(NSString *host) {
    NSMutableDictionary *q=[KeyQuery(host) mutableCopy];q[(__bridge id)kSecReturnData]=@YES;
    CFTypeRef out=NULL; if(SecItemCopyMatching((__bridge CFDictionaryRef)q,&out)!=errSecSuccess)return @"";
    return [[NSString alloc]initWithData:CFBridgingRelease(out) encoding:NSUTF8StringEncoding]?:@"";
}
static BOOL TTSOn(void){return [Prefs boolForKey:@"ttsEnabled"]&&([[Prefs stringForKey:@"ttsEngine"] isEqual:@"local"]||ReadKey(TIOVoiceTTSService()).length>0);}
static BOOL StoreKey(NSString *host,NSString *key) {
    NSDictionary *q=KeyQuery(host);
    if(!key.length){OSStatus s=SecItemDelete((__bridge CFDictionaryRef)q);return s==errSecSuccess||s==errSecItemNotFound;}
    NSDictionary *attrs=@{(__bridge id)kSecValueData:[key dataUsingEncoding:NSUTF8StringEncoding],(__bridge id)kSecAttrAccessible:(__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly};
    OSStatus result=SecItemUpdate((__bridge CFDictionaryRef)q,(__bridge CFDictionaryRef)attrs);
    if(result==errSecItemNotFound){NSMutableDictionary *all=[q mutableCopy];[all addEntriesFromDictionary:attrs];result=SecItemAdd((__bridge CFDictionaryRef)all,NULL);}
    return result==errSecSuccess;
}
static void ImportPrivateBootstrap(void){
    // Source release: configure credentials in the app's Keychain UI only.
    // Never import keys from a distributable application resource.
}
static id Get(id obj,NSString *key) {if(!obj)return nil;@try{return [obj valueForKey:key];}@catch(NSException *e){return nil;}}
static NSString *String(id obj) {return [obj isKindOfClass:NSString.class]?obj:@"";}
static UIViewController *TopController(void) {
    UIWindow *window=nil;
    for(UIScene *scene in UIApplication.sharedApplication.connectedScenes) if(scene.activationState==UISceneActivationStateForegroundActive && [scene isKindOfClass:UIWindowScene.class]) {
        for(UIWindow *w in ((UIWindowScene *)scene).windows) if(w.isKeyWindow){window=w;break;}
    }
    // Official Flutter 1.0.2 uses the legacy application window lifecycle.
    if(!window){for(UIWindow *w in UIApplication.sharedApplication.windows)if(w.isKeyWindow){window=w;break;}}
    UIViewController *c=window.rootViewController;while(c.presentedViewController)c=c.presentedViewController;return c;
}
static void Alert(NSString *title,NSString *message) {
    dispatch_async(dispatch_get_main_queue(),^{UIViewController *top=TopController();if(!top)return;UIAlertController *a=[UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];[top presentViewController:a animated:YES completion:nil];});
}

@interface TIORequest : TIOWebChatRequest
@property(nonatomic,copy) NSArray<NSDictionary *> *history;
- (void)startQuestion:(NSString *)question;
@end
@implementation TIORequest
- (void)startQuestion:(NSString *)question {
    NSString *endpoint=[Prefs stringForKey:@"endpoint"]?:@"",*model=[Prefs stringForKey:@"model"]?:@"";
    NSURL *url=TIOValidateEndpoint(endpoint); NSString *key=ReadKey(endpoint);
    NSDictionary *payload=TIOChatRequestWithHistory(model,question,_history?:@[]);
    if(!url||!payload||!key.length){if(self.update)self.update(@"",YES,@"Please configure a valid HTTPS endpoint, model name, and API key first.");return;}
    // Optional provider extension, sent only when explicitly selected by user.
    NSMutableDictionary *body=[payload mutableCopy];if([Prefs boolForKey:@"deepseekDisableThinking"])body[@"thinking"]=@{@"type":@"disabled"};
    NSString *searchKey=([Prefs boolForKey:@"tinyfishEnabled"]||self.newsMode)?ReadKey(@"https://api.search.tinyfish.ai"):@"";
    TIOImportKnowledgeConnection();if(!self.newsMode&&TIOKnowledgeEnabled()){TIOKnowledgeClient *client=[TIOKnowledgeClient new];self.cancelKnowledge=^{[client cancel];};self.knowledgeQuery=^(NSDictionary *input,BOOL statusOnly,void(^done)(NSDictionary *)){void(^completion)(NSDictionary *,NSString *)=^(NSDictionary *j,NSString *e){done(j?:@{@"status":@"failed"});};if(statusOnly)[client refreshLast:completion];else [client query:input completion:completion];};}
    [self startEndpoint:url key:key payload:body searchKey:searchKey];
}
@end

@interface TIOController : NSObject
@property(nonatomic) TIORequest *request;
@property(nonatomic) NSUInteger generation;
@property(nonatomic,weak) id listener;
@property(nonatomic) NSString *asr;
@property(nonatomic) NSString *sid;
@property(nonatomic) id responseTemplate;
@property(nonatomic) NSString *emitted;
@property(nonatomic) BOOL ownsTurn;
@property(nonatomic) BOOL started;
@property(nonatomic) BOOL responseDone;
@property(nonatomic) NSMutableSet<NSString *> *seenFinals;
@property(nonatomic) NSString *captureEpoch;
@property(nonatomic) TIOConversationHistory *history;
@property(nonatomic,copy) NSString *requestQuestion;
@property(nonatomic) BOOL voiceExited;
@property(nonatomic) TIOTodoTurnGate *taskGate;
@property(nonatomic,copy) NSString *officialTTSAnswer;
@property(nonatomic) BOOL officialTTSActive;
- (BOOL)exitVoice;
@end
static TIOController *Controller;

static id CopyResponse(id source,NSString *answer,BOOL final) {
    // Only use the observed wrapper class. Do not call guessed Swift addresses.
    Class cls=NSClassFromString(@"RayNeoNlpResultWrapper");if(!cls||![source isKindOfClass:cls])return nil;
    id copy=[cls new];
    @try {
        for(NSString *field in @[@"sub",@"dialogId",@"sessionId",@"domain",@"intent",@"round",@"query",@"spoken",@"answer",@"finished",@"offline",@"command",@"hasNextRound",@"rawData"]) {id v=[source valueForKey:field];if(v)[copy setValue:v forKey:field];}
        [copy setValue:answer forKey:@"answer"];[copy setValue:@"" forKey:@"spoken"];[copy setValue:@(final) forKey:@"finished"];
    }@catch(NSException *e){return nil;}
    return copy;
}
@implementation TIOController
- (instancetype)init {if((self=[super init])){_seenFinals=[NSMutableSet set];_captureEpoch=NSUUID.UUID.UUIDString;_history=[TIOConversationHistory new];_taskGate=[TIOTodoTurnGate new];}return self;}
- (void)cancel {++_generation;[_request cancel];_request=nil;_ownsTurn=NO;_started=NO;_responseDone=NO;_responseTemplate=nil;_emitted=@"";_officialTTSAnswer=@"";_officialTTSActive=NO;[VoiceTTS cancel];}
- (BOOL)exitVoice {
    if(!VoiceExitReady)return NO;
    Class cls=NSClassFromString(@"rayneo_venus_sdk_plugin.VoiceAssistantHelper");
    id helper=((id(*)(id,SEL))objc_msgSend)(cls,NSSelectorFromString(@"shared"));
    if(!helper)return NO;
    // Cancel our stream before asking the official workflow to stop, so a late
    // network delta cannot re-open the page. New audio start releases this gate.
    [self cancel];_voiceExited=YES;_asr=@"";_sid=@"";
    ((void(*)(id,SEL))objc_msgSend)(helper,NSSelectorFromString(@"stopWorkflow"));
    Diagnostic=@"Voice exit invoked; waiting for glasses confirmation";
    return YES;
}
- (void)acceptAsr:(NSString *)text finished:(BOOL)final session:(NSString *)sid listener:(id)listener {
    if(![Prefs integerForKey:@"mode"]||!text.length)return;
    if(!final){if(_ownsTurn&&_started){[self cancel];}_asr=text;return;}
    NSString *identity=[NSString stringWithFormat:@"%@|%@",sid,text];if([_seenFinals containsObject:identity])return;
    if(_seenFinals.count>=256)[_seenFinals removeAllObjects];[_seenFinals addObject:identity];
    [self cancel];[_taskGate beginTurn];_listener=listener;_asr=text;_sid=sid;
    // Do not seize an unknown response shape. Wait for an eligible official template.
    Diagnostic=@"ASR final received; waiting for official chat template";
}
- (void)emitText:(NSString *)text done:(BOOL)done error:(NSString *)error generation:(NSUInteger)gen {
    if(gen!=_generation||!_ownsTurn||_responseDone||!_listener)return;
    if(error)text=[(_emitted?:@"") stringByAppendingFormat:@"\n[%@]",error];
    NSString *delta=TIOAppendDelta(_emitted?:@"",text);
    if(!delta){
        // Close an owned turn even if a provider rewrites a previous chunk.
        // Keep ownership until the next turn so late official chunks stay suppressed.
        [_request cancel];_request=nil;_responseDone=YES;
        id failure=CopyResponse(_responseTemplate,@"\n[Stream format changed; turn stopped.]",YES);
        if(failure)OriginalNlp(_listener,NSSelectorFromString(@"onNlpResult:"),failure);
        OriginalComplete(_listener,NSSelectorFromString(@"onResponseComplete"));
        Diagnostic=@"Model output is not delta stream; error cleanup submitted";return;
    }
    if(delta.length||done){id wrapper=CopyResponse(_responseTemplate,delta,done);if(!wrapper){[_request cancel];_request=nil;_responseDone=YES;OriginalComplete(_listener,NSSelectorFromString(@"onResponseComplete"));Diagnostic=@"Response template copy failed; cleanup submitted";return;}OriginalNlp(_listener,NSSelectorFromString(@"onNlpResult:"),wrapper);_emitted=[text copy];if(TTSOn()&&!error)[VoiceTTS appendFullText:text finished:done];}
    if(done){_responseDone=YES;if(!error&&_request&&text.length)[_history appendQuestion:_requestQuestion answer:text];Diagnostic=error?@"Custom response failed; error cleanup submitted":@"Custom response completed; finished official turn";OriginalComplete(_listener,NSSelectorFromString(@"onResponseComplete"));}
}
- (BOOL)receiveNlp:(id)response listener:(id)listener {
    NSString *domain=String(Get(response,@"domain")),*intent=String(Get(response,@"intent")),*sub=String(Get(response,@"sub"));
    BOOL offline=[Get(response,@"offline") boolValue];
    // Metadata whitelist: no question, answer, rawData, IDs or tokens in diagnostics.
    NSCharacterSet *allowed=[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.-"];
    NSString *(^safe)(NSString *)=^NSString *(NSString *s){return s.length<64&&[s rangeOfCharacterFromSet:allowed.invertedSet].location==NSNotFound?s:@"(other)";};
    Diagnostic=[NSString stringWithFormat:@"NLP domain=%@ / intent=%@ / sub=%@ / offline=%d",safe(domain),safe(intent),safe(sub),offline];
    id command=Get(response,@"command");
    if([_taskGate observeDomain:domain intent:intent command:String(Get(command,@"name")) params:Get(command,@"params") session:String(Get(response,@"sessionId")) expectedSession:_sid?:@"" sameListener:listener==_listener]){
        // Invalidate in-flight private deltas before forwarding the official
        // command. Keep subsequent acknowledgement and completion official too.
        [self cancel];Diagnostic=@"Official todo handled turn; custom response cancelled";
    }
    if(_taskGate.official)return NO;
    BOOL eligible=TIOIsEligibleChat(domain,intent,sub,offline,Get(response,@"command")!=nil);
    if(eligible)
        [Prefs setObject:@"chat" forKey:@"verifiedChatDomain"];
    if(![Prefs integerForKey:@"mode"]||listener!=_listener||!_asr.length||offline)return NO;
    NSString *sid=String(Get(response,@"sessionId"));if(_sid.length&&sid.length&&![_sid isEqual:sid])return NO;
    // Exact chat-domain allowlist must be confirmed on the current phone. Skill commands are never replaced.
    NSString *approved=[Prefs stringForKey:@"verifiedChatDomain"];
    if(!approved.length||![domain isEqual:approved]||!eligible)return NO;
    if(_ownsTurn)return YES;
    _responseTemplate=response;_ownsTurn=YES;_started=YES;_emitted=@"";NSUInteger gen=_generation;
    if([Prefs integerForKey:@"mode"]==1){
        NSString *test=[@"Custom Model Test " stringByAppendingString:[NSUUID.UUID.UUIDString substringToIndex:6]];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{[self emitText:test done:YES error:nil generation:gen];});
    }else{
        _request=[TIORequest new];__weak typeof(self) weakSelf=self;
        TIOTodoSetChatContext(listener,response);
        _request.createTodo=^(NSString *title,void (^completion)(NSDictionary *result)){TIOTodoCreateFromTool(title,completion);};
        _requestQuestion=[_asr copy];_request.history=[_history snapshot];
        _request.update=^(NSString *text,BOOL done,NSString *error){[weakSelf emitText:text done:done error:error generation:gen];};
        [_request startQuestion:_asr];
    }
    return YES;
}
- (id)observeOfficialVoice:(id)response {
    if(!TTSOn()||!TIOIsEligibleChat(String(Get(response,@"domain")),String(Get(response,@"intent")),String(Get(response,@"sub")),[Get(response,@"offline") boolValue],Get(response,@"command")!=nil))return response;
    NSString *answer=String(Get(response,@"answer"));if(!answer.length)return response;
    if(!_officialTTSActive){_officialTTSActive=YES;_officialTTSAnswer=@"";[VoiceTTS beginTurn];}
    NSString *prior=_officialTTSAnswer?:@"";
    NSString *full=[answer hasPrefix:prior]?answer:([prior hasPrefix:answer]?prior:[prior stringByAppendingString:answer]);
    _officialTTSAnswer=full;
    [VoiceTTS appendFullText:full finished:[Get(response,@"finished") boolValue]];
    // Suppress duplicate spoken text only for the eligible chat response.
    return String(Get(response,@"spoken")).length?(CopyResponse(response,answer,[Get(response,@"finished") boolValue])?:response):response;
}
- (void)completeOfficialVoice {
    if(_officialTTSActive&&_officialTTSAnswer.length)[VoiceTTS appendFullText:_officialTTSAnswer finished:YES];
    _officialTTSActive=NO;_officialTTSAnswer=@"";
}
@end

static void AsrHook(id self,SEL cmd,id text,BOOL final,id sid) {
    NSString *copy=String(text),*session=String(sid);
    void (^work)(void)=^{
        if(final&&[Prefs boolForKey:@"voiceExitCommands"]&&TIOIsVoiceExitCommand(copy)&&[Controller exitVoice])return;
        if(Controller.voiceExited)return;
        // The official app may reopen its microphone after the answer. Cancel
        // playback only when new recognized user speech arrives.
        if(copy.length&&[Prefs boolForKey:@"ttsEnabled"])[VoiceTTS cancel];
        OriginalAsr(self,cmd,text,final,sid);
        [Controller acceptAsr:copy finished:final session:session listener:self];
    };
    if(NSThread.isMainThread)work();else dispatch_async(dispatch_get_main_queue(),work);
}
static void AudioStartHook(id self,SEL cmd) {
    void (^work)(void)=^{
#if TIO_MUSIC
        TMMusicPauseForVoice();
#endif
        Controller.voiceExited=NO;[Controller.taskGate beginTurn];OriginalAudioStart(self,cmd);};
    if(NSThread.isMainThread)work();else dispatch_async(dispatch_get_main_queue(),work);
}
static void NlpHook(id self,SEL cmd,id value) {
    // Route decisions on the main queue to serialize ASR, cancellation and stream completion.
    void (^work)(void)=^{if(Controller.voiceExited)return;if(TIOTodoIsToolDispatching()){OriginalNlp(self,cmd,value);return;}TIOTodoObserveNlp(self,value);if(![Controller receiveNlp:value listener:self])OriginalNlp(self,cmd,[Controller observeOfficialVoice:value]);};
    if(NSThread.isMainThread)work();else dispatch_async(dispatch_get_main_queue(),work);
}
static void CompleteHook(id self,SEL cmd) {
    void (^work)(void)=^{CompletionEvents++;if(Controller.voiceExited)return;[Controller completeOfficialVoice];if(![Prefs integerForKey:@"mode"]||!(Controller.listener==self&&Controller.ownsTurn))OriginalComplete(self,cmd);};
    if(NSThread.isMainThread)work();else dispatch_async(dispatch_get_main_queue(),work);
}
static void AlwaysOnHook(id self,SEL cmd,id value) {
    OriginalAlwaysOn(self,cmd,value);
    if(![Prefs boolForKey:@"captureFinalText"]||![Get(value,@"finish") boolValue])return;
    NSString *text=String(Get(value,@"text")),*round=String(Get(value,@"roundId"));
    id r=Get(value,@"role");NSString *role=[r respondsToSelector:@selector(stringValue)]?[r stringValue]:String(r);
    NSString *identity=round.length?[NSString stringWithFormat:@"%@:%@",Controller.captureEpoch,round]:@"";
    dispatch_async(ArchiveQueue,^{NSError *error=nil;BOOL ok=[Archive recordText:text round:identity role:role at:NSDate.date error:&error];dispatch_async(dispatch_get_main_queue(),^{Diagnostic=ok?@"Final transcript saved to local archive":@"Archive failed; official data unchanged";});});
}

@interface TIOPanel : UITableViewController
@property(nonatomic) TIORequest *testRequest;
@property(nonatomic,copy) NSString *page;
@property(nonatomic) NSArray<NSDictionary *> *sections;
- (void)directTestTinyFish:(NSString *)searchKey;
- (void)llmTestSearch;
- (void)showModelTools;
@end
@implementation TIOPanel
- (void)viewDidLoad {[super viewDidLoad];self.page=self.page?:@"model";self.sections=TIOResearchSections(self.page);self.title=[@{@"model":@"AI & Model",@"library":@"Tools & Library",@"diagnostics":@"Diagnostics"} objectForKey:self.page];TIOStyleResearchTable(self);}
- (void)viewWillAppear:(BOOL)animated{[super viewWillAppear:animated];[self.tableView reloadData];}
- (void)viewDidAppear:(BOOL)animated{[super viewDidAppear:animated];[NSNotificationCenter.defaultCenter removeObserver:self name:@"TIOResearchClosed" object:nil];[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(cancelPanelTest) name:@"TIOResearchClosed" object:nil];}
- (void)cancelPanelTest{[_testRequest cancel];_testRequest=nil;}
- (void)dealloc{[NSNotificationCenter.defaultCenter removeObserver:self];[_testRequest cancel];}
- (void)close {[_testRequest cancel];[self dismissViewControllerAnimated:YES completion:nil];}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView{return self.sections.count;}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section{return [self.sections[section][@"rows"] count];}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section{return self.sections[section][@"title"];}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if(section==0&&[self.page isEqual:@"model"])return [TIOSelectedAgent() isEqual:@"Codex"]?@"Codex · Read-only knowledge query, see status in Knowledge.":@"Current Agent has no connected executor; changing selection will not launch tasks.";
    if(section==0)return [@{@"model":@"TURBO IO · Select response mode, manage custom models and search.",@"library":@"Centralized audio and transcript management; sharing creates copies.",@"diagnostics":@"Manual tests and protocol status."} objectForKey:self.page];
    if(section!=self.sections.count-1)return nil;
    if([self.page isEqual:@"model"])return @"Official ASR retained. Speech is read out via iOS device TTS by default; cloud TTS available as option. Only plays when glasses Bluetooth audio is connected. History keeps last 50 successful messages.";
    if([self.page isEqual:@"library"])return @"Saving must be explicitly enabled. No recordings are auto-uploaded. Lifelog only contains text captured after enabling.";
    return @"Tests require manual trigger. API success does not guarantee glasses display. Closing HUD only closes UI, background features continue.";
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)ip {
    NSDictionary *r=self.sections[ip.section][@"rows"][ip.row];NSInteger section=[r[@"section"] integerValue],row=[r[@"row"] integerValue];
    UITableViewCell *c=section>=0?[self legacyCell:tableView at:[NSIndexPath indexPathForRow:row inSection:section]]:[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    c.textLabel.text=r[@"title"];c.textLabel.numberOfLines=0;c.textLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody];c.textLabel.adjustsFontForContentSizeCategory=YES;c.detailTextLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];c.detailTextLabel.adjustsFontForContentSizeCategory=YES;c.detailTextLabel.numberOfLines=0;c.detailTextLabel.textColor=UIColor.secondaryLabelColor;c.imageView.image=[UIImage systemImageNamed:r[@"icon"]];c.imageView.tintColor=UIColor.systemIndigoColor;
    c.accessibilityIdentifier=[@"research-" stringByAppendingString:r[@"key"]];c.contentView.directionalLayoutMargins=NSDirectionalEdgeInsetsMake(15,16,15,16);
    if([r[@"key"] isEqual:@"agent"]){__weak typeof(self) weak=self;c.accessoryView=TIOAgentPicker(^{[weak.tableView reloadData];});c.detailTextLabel.text=[TIOSelectedAgent() isEqual:@"Codex"]?@"Mac · Local Knowledge":@"No executor connected";}
    if([r[@"key"] isEqual:@"knowledge"])c.detailTextLabel.text=@"WeChat Archives · Project Docs · Notes";
    if([r[@"key"] isEqual:@"tts"]){c.detailTextLabel.text=@"Official/Custom Model · Bluetooth Audio";
        UISwitch *s=[UISwitch new];s.on=[Prefs boolForKey:@"ttsEnabled"];[s addTarget:self action:@selector(ttsToggle:) forControlEvents:UIControlEventValueChanged];c.accessoryView=s;}
    if([r[@"key"] isEqual:@"ttsEngine"])c.detailTextLabel.text=[[Prefs stringForKey:@"ttsEngine"] isEqual:@"local"]?@"iOS Local Voice · No Key · Default":@"Aliyun Flash TTS · Cloud";
    if([r[@"key"] isEqual:@"ttsKey"])c.detailTextLabel.text=ReadKey(TIOVoiceTTSService()).length?@"Saved in Keychain":@"Endpoint and Key needed for Cloud mode";
    if([r[@"key"] isEqual:@"ttsTest"]){c.detailTextLabel.text=[NSString stringWithFormat:@"Sample · %@",VoiceTTS.status?:@"Ready"];
        UIButton *button=[UIButton buttonWithType:UIButtonTypeSystem];[button setTitle:@"Play" forState:UIControlStateNormal];
        button.accessibilityIdentifier=@"research-tts-play-button";button.frame=CGRectMake(0,0,58,44);
        [button addTarget:self action:@selector(testTTS) forControlEvents:UIControlEventTouchUpInside];c.accessoryView=button;}
    if(!c.accessoryView)c.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
    if([r[@"key"] isEqual:@"mode"]){c.detailTextLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleTitle3];c.detailTextLabel.textColor=UIColor.labelColor;}
    if([r[@"key"] isEqual:@"history"])c.detailTextLabel.text=[c.detailTextLabel.text stringByAppendingString:@" · Tap to manage & clear"];
    if(section==-1)c.detailTextLabel.text=@[@"Local Audio / TXT / Markdown · AirDrop & Files",@"Import or paste transcript, send to model",@"Export Markdown or organize saved text",@"View and share audio copies once enabled"][row];
    if([r[@"key"] isEqual:@"navigation"])c.detailTextLabel.text=@"Search / Map Pin / Simulation → Glasses HUD";
    if([r[@"key"] isEqual:@"archive"])c.detailTextLabel.text=@"Export Markdown & JSON at once";
    if([r[@"key"] isEqual:@"capture"])c.detailTextLabel.text=@"Save subsequent recognized text without mic activation";
    if([r[@"key"] isEqual:@"status"])c.accessoryType=UITableViewCellAccessoryNone;
    return c;
}
- (UITableViewCell *)legacyCell:(UITableView *)tableView at:(NSIndexPath *)ip {
    UITableViewCell *c=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];c.detailTextLabel.numberOfLines=0;
    if(ip.section==0){
        c.textLabel.text=@[@"Select Response Model",@"Configure Custom API",@"Test API (Synthetic Prompt)",@"DeepSeek: Disable Thinking",@"Chat History (Tap to Clear)",@"View System Prompt",@"Voice Exit Commands",@"Web Search · TinyFish",@"Configure TinyFish Key",@"Test Web Search",@"Todo Protocol",@"Model Tools",@"AI News Feed"][ip.row];
        if(ip.row==12)c.detailTextLabel.text=@"Default AI · TinyFish · Teleprompter Reader · No Mic";
        if(ip.row==11){
            BOOL searchOn=[Prefs boolForKey:@"tinyfishEnabled"]&&ReadKey(@"https://api.search.tinyfish.ai").length>0;
            c.detailTextLabel.text=[NSString stringWithFormat:@"web_search: %@ · create_todo: Active · knowledge: %@",searchOn?@"Enabled":@"Disabled",TIOKnowledgeEnabled()?@"Enabled":@"Optional (Off)"];
        }
        if(ip.row==0){NSInteger m=[Prefs integerForKey:@"mode"];c.detailTextLabel.text=@[@"RayNeo Official",@"Random String (No API)",@"Custom OpenAI Compatible"][MAX(0,MIN(m,2))];}
        if(ip.row==1)c.detailTextLabel.text=[Prefs stringForKey:@"model"]?:@"Not configured (no default key)";
        if(ip.row==3){UISwitch *s=[UISwitch new];s.on=[Prefs boolForKey:@"deepseekDisableThinking"];[s addTarget:self action:@selector(thinking:) forControlEvents:UIControlEventValueChanged];c.accessoryView=s;}
        if(ip.row==4)c.detailTextLabel.text=[NSString stringWithFormat:@"%lu / 50 items · Process memory · Successful turns only",(unsigned long)[Controller.history snapshot].count];
        if(ip.row==5)c.detailTextLabel.text=[TIOProfilePrompt(TIOProfile()) length]?@"Customized · Takes effect next turn":@"No identity set · Tap to edit profile and prompt";
        if(ip.row==6){c.detailTextLabel.text=VoiceExitReady?@"Dismiss / Close / Never mind; full phrase match":@"Voice exit hook unavailable in this version";UISwitch *s=[UISwitch new];s.on=[Prefs boolForKey:@"voiceExitCommands"];s.enabled=VoiceExitReady;[s addTarget:self action:@selector(voiceExit:) forControlEvents:UIControlEventValueChanged];c.accessoryView=s;}
        if(ip.row==7){c.detailTextLabel.text=@"Called on-demand · Public web only · Max 2 queries";UISwitch *s=[UISwitch new];s.on=[Prefs boolForKey:@"tinyfishEnabled"];[s addTarget:self action:@selector(searchToggle:) forControlEvents:UIControlEventValueChanged];c.accessoryView=s;}
        if(ip.row==8)c.detailTextLabel.text=ReadKey(@"https://api.search.tinyfish.ai").length?@"Saved in iOS Keychain":@"Not configured";
        if(ip.row==9)c.detailTextLabel.text=@"No chat history sent · Shows search count";
    }else if(ip.section==1){c.textLabel.text=ip.row==0?@"Bypass Save Final Text":@"Export Markdown / JSON";if(ip.row==0){UISwitch *s=[UISwitch new];s.on=[Prefs boolForKey:@"captureFinalText"];[s addTarget:self action:@selector(capture:) forControlEvents:UIControlEventValueChanged];c.accessoryView=s;}}
    else{c.textLabel.text=HooksReady?@"Hooks Verified":@"Hooks Inactive: Version Mismatch";c.detailTextLabel.text=[Diagnostic stringByAppendingFormat:@"\nOfficial completion callback: %lu; Voice exit: %@",(unsigned long)CompletionEvents,VoiceExitReady?@"Ready":@"Unavailable"];}
    return c;
}
- (void)thinking:(UISwitch *)sender {[Prefs setBool:sender.on forKey:@"deepseekDisableThinking"];}
- (void)ttsToggle:(UISwitch *)sender {
    if(sender.on&&![[Prefs stringForKey:@"ttsEngine"] isEqual:@"local"]&&!ReadKey(TIOVoiceTTSService()).length){sender.on=NO;Alert(@"Configure Cloud TTS First",@"Aliyun Flash mode requires an API key; local device voice does not.");return;}
    [Prefs setBool:sender.on forKey:@"ttsEnabled"];if(!sender.on)[VoiceTTS cancel];
    [self.tableView reloadData];
}
- (void)configureTTSEngine {
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Speech Readout Engine" message:@"Reads out chat answers. Default uses iOS device voice (no key required)." preferredStyle:UIAlertControllerStyleActionSheet];
    [a addAction:[UIAlertAction actionWithTitle:@"Device Local Voice · Default, No Key" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){[Prefs setObject:@"local" forKey:@"ttsEngine"];[Prefs setBool:YES forKey:@"ttsEnabled"];VoiceTTS.localMode=YES;[self.tableView reloadData];}]];
    [a addAction:[UIAlertAction actionWithTitle:@"Aliyun Flash · Cloud Streaming" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){
        if(!ReadKey(TIOVoiceTTSService()).length){Alert(@"No Cloud Key",@"Configure Aliyun TTS key first, or continue using device voice.");return;}
        [Prefs setObject:@"cloud" forKey:@"ttsEngine"];[Prefs setBool:YES forKey:@"ttsEnabled"];VoiceTTS.localMode=NO;[self.tableView reloadData];}]];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView=self.view;a.popoverPresentationController.sourceRect=CGRectMake(self.view.bounds.size.width/2,100,1,1);
    [self presentViewController:a animated:YES completion:nil];
}
- (void)configureTTS {
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Aliyun Flash TTS" message:@"Optional cloud voice. Enter WebSocket endpoint and API key." preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *f){f.placeholder=@"wss://…/api-ws/v1/inference";f.text=TIOVoiceTTSService();f.keyboardType=UIKeyboardTypeURL;f.autocapitalizationType=UITextAutocapitalizationTypeNone;f.autocorrectionType=UITextAutocorrectionTypeNo;}];
    [a addTextFieldWithConfigurationHandler:^(UITextField *f){f.placeholder=@"TTS API Key";f.secureTextEntry=YES;f.autocapitalizationType=UITextAutocapitalizationTypeNone;f.autocorrectionType=UITextAutocorrectionTypeNo;}];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){
        NSString *endpoint=a.textFields[0].text?:@"",*key=a.textFields[1].text?:@"";a.textFields[1].text=@"";
        if(!TIOVoiceTTSServiceURLValid(endpoint)||!([key hasPrefix:@"sk-"]||!key.length)||key.length>1024||[key rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].location!=NSNotFound){Alert(@"Not Saved",@"Valid wss endpoint and API key required.");return;}
        if(key.length&&!StoreKey(endpoint,key)){Alert(@"Not Saved",@"Keychain write failed.");return;}
        if(!ReadKey(endpoint).length){Alert(@"Not Saved",@"No key configured for this endpoint.");return;}
        [VoiceTTS cancel];[Prefs setObject:endpoint forKey:@"ttsEndpoint"];[self.tableView reloadData];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Delete Cloud Key" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x){[VoiceTTS cancel];StoreKey(TIOVoiceTTSService(),@"");[Prefs setObject:@"local" forKey:@"ttsEngine"];VoiceTTS.localMode=YES;[self.tableView reloadData];}]];
    [self presentViewController:a animated:YES completion:nil];
}
- (void)testTTS {
    if(!TTSOn()){Alert(@"Please Enable First",@"Turn on 'Synchronous Speech' switch first.");return;}
    [VoiceTTS beginTurn];[VoiceTTS appendFullText:@"RayNeo HUD voice test. Audio readout is working." finished:YES];
    [self.tableView reloadData];
    __weak typeof(self) weak=self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,3*NSEC_PER_SEC),dispatch_get_main_queue(),^{[weak.tableView reloadData];});
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,8*NSEC_PER_SEC),dispatch_get_main_queue(),^{[weak.tableView reloadData];});
}
- (void)voiceExit:(UISwitch *)sender {[Prefs setBool:sender.on forKey:@"voiceExitCommands"];}
- (void)searchToggle:(UISwitch *)sender {
    if(sender.on&&!ReadKey(@"https://api.search.tinyfish.ai").length){
        sender.on=NO;
        Alert(@"Configure Search First",@"TinyFish API key required. Tap 'Search API Configuration' below.");
        return;
    }
    [Prefs setBool:sender.on forKey:@"tinyfishEnabled"];
    [Controller cancel];
    [self.tableView reloadData];
}

- (void)directTestTinyFish:(NSString *)searchKey {
    if(!searchKey.length){
        Alert(@"No Search Key",@"Please enter or configure a TinyFish API key first.");
        return;
    }
    NSURLComponents *u=[NSURLComponents componentsWithString:@"https://api.search.tinyfish.ai"];
    u.queryItems=@[[NSURLQueryItem queryItemWithName:@"query" value:@"RayNeo glasses"]];
    NSMutableURLRequest *req=[NSMutableURLRequest requestWithURL:u.URL];
    req.timeoutInterval=15;
    [req setValue:searchKey forHTTPHeaderField:@"X-API-Key"];
    [req setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    
    NSURLSession *session=[NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration ephemeralSessionConfiguration]];
    [[session dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *error){
        dispatch_async(dispatch_get_main_queue(),^{
            if(error){
                Alert(@"TinyFish Connection Failed",[NSString stringWithFormat:@"Network error: %@",error.localizedDescription]);
                return;
            }
            NSHTTPURLResponse *http=(NSHTTPURLResponse *)response;
            if(http.statusCode==401){
                Alert(@"TinyFish Authentication Failed",@"HTTP 401: Invalid API Key.\nPlease verify your TinyFish API key in 'Search API Configuration'.");
                return;
            }
            if(http.statusCode!=200){
                NSString *respBody=[[NSString alloc]initWithData:data encoding:NSUTF8StringEncoding];
                Alert(@"TinyFish Error",[NSString stringWithFormat:@"HTTP Status: %ld\n\n%@",(long)http.statusCode,respBody?:@"Unknown error"]);
                return;
            }
            NSDictionary *results=TIOWebSearchResults(data);
            NSArray *items=results[@"results"];
            if(items.count>0){
                NSDictionary *first=items[0];
                NSString *msg=[NSString stringWithFormat:
                    @"✅ TinyFish Search Working!\n\n"
                    @"Status: HTTP 200 OK\n"
                    @"Query: 'RayNeo glasses'\n"
                    @"Results found: %lu\n\n"
                    @"Top result:\n%@\n%@\n\n"
                    @"Snippet:\n%@",
                    (unsigned long)items.count,
                    first[@"title"]?:@"",
                    first[@"url"]?:@"",
                    first[@"snippet"]?:@""];
                Alert(@"Web Search Test Succeeded",msg);
            }else{
                Alert(@"TinyFish Connected",@"HTTP 200 OK: Connected successfully to TinyFish Search, but 0 results returned for 'RayNeo glasses'.");
            }
        });
    }] resume];
}

- (void)configureSearch {
    NSString *existingKey=ReadKey(@"https://api.search.tinyfish.ai");
    NSString *mask=existingKey.length>8?
        [NSString stringWithFormat:@"Key configured: %@...%@\nEnter a new key to update, or tap 'Test Saved Key'.",
            [existingKey substringToIndex:MIN(existingKey.length,6)],
            [existingKey substringFromIndex:MAX(0,(NSInteger)existingKey.length-4)]]:
        @"When enabled, queries TinyFish for live web data. Key stored securely in Keychain.";
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"TinyFish Search Configuration" message:mask preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *f){
        f.placeholder=@"TinyFish API Key (e.g. sk-tinyfish-...)";
        f.secureTextEntry=YES;
        f.autocapitalizationType=UITextAutocapitalizationTypeNone;
        f.autocorrectionType=UITextAutocorrectionTypeNo;
    }];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weak=self;
    [a addAction:[UIAlertAction actionWithTitle:@"Save & Enable" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){
        NSString *raw=a.textFields[0].text?:@"";
        NSString *key=[raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if(key.length>0){
            if(key.length<8||[key rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].location!=NSNotFound){
                Alert(@"Not Saved",@"Key must be at least 8 characters with no whitespace.");
                return;
            }
            if(!StoreKey(@"https://api.search.tinyfish.ai",key)){
                Alert(@"Not Saved",@"Keychain write failed.");
                return;
            }
        }else if(!ReadKey(@"https://api.search.tinyfish.ai").length){
            Alert(@"Not Saved",@"Please enter an API key.");
            return;
        }
        [Controller cancel];
        [Prefs setBool:YES forKey:@"tinyfishEnabled"];
        [weak.tableView reloadData];
        [weak directTestTinyFish:ReadKey(@"https://api.search.tinyfish.ai")];
    }]];
    if(existingKey.length>0){
        [a addAction:[UIAlertAction actionWithTitle:@"Test Saved Key" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){
            [weak directTestTinyFish:existingKey];
        }]];
    }
    [a addAction:[UIAlertAction actionWithTitle:@"Remove Search Key" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x){
        [Controller cancel];
        [Prefs setBool:NO forKey:@"tinyfishEnabled"];
        BOOL ok=StoreKey(@"https://api.search.tinyfish.ai",@"");
        [weak.tableView reloadData];
        if(!ok) Alert(@"Not Removed",@"Keychain error; search disabled.");
        else Alert(@"Removed",@"TinyFish search key removed and web search disabled.");
    }]];
    [self presentViewController:a animated:YES completion:nil];
}
- (void)testSearch {
    NSString *searchKey=ReadKey(@"https://api.search.tinyfish.ai");
    if(![Prefs boolForKey:@"tinyfishEnabled"]||!searchKey.length){
        Alert(@"Not Enabled",@"Please configure and enable TinyFish search first in 'Search API Configuration'.");
        return;
    }
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Test Web Search" message:@"Select test mode:" preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weak=self;
    [a addAction:[UIAlertAction actionWithTitle:@"1. Test TinyFish API Directly" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){
        [weak directTestTinyFish:searchKey];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"2. Test Full AI Model + Web Search Flow" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){
        [weak llmTestSearch];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView=self.view;
    a.popoverPresentationController.sourceRect=CGRectMake(self.view.bounds.size.width/2,100,1,1);
    [self presentViewController:a animated:YES completion:nil];
}

- (void)llmTestSearch {
    [_testRequest cancel];
    _testRequest=[TIORequest new];
    __weak typeof(self) weak=self;
    _testRequest.update=^(NSString *text,BOOL done,NSString *error){
        if(done){
            typeof(self) strong=weak;
            Alert(@"AI Model Search Result",[NSString stringWithFormat:@"Search requests invoked: %lu\n\n%@",(unsigned long)strong.testRequest.searchCount,error?:text]);
        }
    };
    [_testRequest startQuestion:@"Please search the web for the latest RayNeo glasses news and explain in two sentences with official source URL."];
}

- (void)showModelTools {
    BOOL searchOn=[Prefs boolForKey:@"tinyfishEnabled"]&&ReadKey(@"https://api.search.tinyfish.ai").length>0;
    BOOL knowledgeOn=TIOKnowledgeEnabled();
    NSInteger mode=[Prefs integerForKey:@"mode"];
    NSString *modeName=mode==2?@"Custom Model (Active)":(mode==1?@"Random String":@"RayNeo Official (Tools Inactive)");
    
    NSString *msg=[NSString stringWithFormat:
        @"Response Mode: %@\n\n"
        @"1. Web Search (web_search):\n"
        @"%@\n\n"
        @"2. RayNeo To-Do (create_todo):\n"
        @"✅ Enabled · Voice to-do creation for glasses.\n\n"
        @"3. Local Knowledge Base (knowledge_query):\n"
        @"%@\n\n"
        @"💡 Note: AI tools are called when 'Custom Model (Experimental)' mode is active.",
        modeName,
        searchOn?@"✅ Enabled · Powered by TinyFish live search.":@"❌ Disabled · Turn on 'Enable Web Search' & configure TinyFish key.",
        knowledgeOn?@"✅ Enabled · Connected to Mac Codex.":@"⚪ Disabled (Optional) · For private Mac documents only. Not required for web search."
    ];
    Alert(@"Available Model Tools",msg);
}
- (void)capture:(UISwitch *)sender {
    if(!sender.on){[Prefs setBool:NO forKey:@"captureFinalText"];return;}
    sender.on=NO;
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Save Lifelog Text?" message:@"Saves recognized text locally to the addon directory. Does not upload to any server." preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Enable Local Saving" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){Controller.captureEpoch=NSUUID.UUID.UUIDString;[Prefs setBool:YES forKey:@"captureFinalText"];[self.tableView reloadData];}]];[self presentViewController:a animated:YES completion:nil];
}
- (void)configure {
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Custom Model Endpoint" message:@"Enter full HTTPS /chat/completions URL. Keys are stored securely in your iOS Keychain." preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *f){f.placeholder=@"https://…/v1/chat/completions";f.text=[Prefs stringForKey:@"endpoint"];f.keyboardType=UIKeyboardTypeURL;f.autocapitalizationType=UITextAutocapitalizationTypeNone;f.autocorrectionType=UITextAutocorrectionTypeNo;}];
    [a addTextFieldWithConfigurationHandler:^(UITextField *f){f.placeholder=@"Model Name (e.g. gemini-1.5-flash)";f.text=[Prefs stringForKey:@"model"];f.autocapitalizationType=UITextAutocapitalizationTypeNone;f.autocorrectionType=UITextAutocorrectionTypeNo;}];
    [a addTextFieldWithConfigurationHandler:^(UITextField *f){f.placeholder=@"API Key (e.g. AIzaSy...)";f.secureTextEntry=YES;f.autocapitalizationType=UITextAutocapitalizationTypeNone;f.autocorrectionType=UITextAutocorrectionTypeNo;}];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){NSString *url=a.textFields[0].text?:@"",*model=a.textFields[1].text?:@"",*key=a.textFields[2].text?:@"";NSURL *valid=TIOValidateEndpoint(url);if(!valid||!TIOChatRequest(model,@"test")){Alert(@"Not Saved",@"Valid HTTPS /chat/completions URL and model name required.");return;}url=valid.absoluteString;if(key.length&&!StoreKey(url,key)){Alert(@"Not Saved",@"Keychain write failed.");return;}[Controller cancel];if(![[Prefs stringForKey:@"endpoint"] isEqual:url]||![[Prefs stringForKey:@"model"] isEqual:model])[Controller.history clear];[Prefs setInteger:0 forKey:@"mode"];[Prefs setObject:url forKey:@"endpoint"];[Prefs setObject:model forKey:@"model"];[self.tableView reloadData];}]];[self presentViewController:a animated:YES completion:nil];
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)ip {
    NSDictionary *r=self.sections[ip.section][@"rows"][ip.row];[tableView deselectRowAtIndexPath:ip animated:YES];
    if([r[@"key"] isEqual:@"agent"])return;
#if TIO_MUSIC
    if([r[@"key"] isEqual:@"music"]){[self.navigationController pushViewController:TMMusicController() animated:YES];return;}
#endif
#if TIO_LOCAL_TRANSLATION
    if([r[@"key"] isEqual:@"localTranslation"]){TIOOpenLocalTranslation(self);return;}
#endif
    if([r[@"key"] isEqual:@"knowledge"]){TIOOpenKnowledge(self);return;}
    if([r[@"key"] isEqual:@"ttsEngine"]){[self configureTTSEngine];return;}
    if([r[@"key"] isEqual:@"ttsKey"]){[self configureTTS];return;}
    if([r[@"key"] isEqual:@"ttsTest"]){[self testTTS];return;}
    if([r[@"key"] isEqual:@"navigation"]){[self.navigationController pushViewController:TIONavigationController() animated:YES];return;}
#if TIO_OTA_RESEARCH_ENABLED
    #if TIO_NATIVE_NAV
    if([r[@"key"] isEqual:@"displayPhone"]){[self.navigationController pushViewController:TDPPhoneController() animated:YES];return;}
    #endif
    if([r[@"key"] isEqual:@"experimentalOTA"]){[self.navigationController pushViewController:TIOExperimentalOTAController() animated:YES];return;}
#endif
    if([@[@"thinking",@"search",@"exit",@"capture",@"tts"] containsObject:r[@"key"]])return;
    NSInteger section=[r[@"section"] integerValue],row=[r[@"row"] integerValue];
    if(section>=0){[self legacySelect:tableView at:[NSIndexPath indexPathForRow:row inSection:section]];return;}
    Class cls=NSClassFromString(@[@"TIORecordingExportsPanel",@"TIORecordingTextPanel",@"TIOLifelogExportsPanel",@"TIOAlwaysOnAudioPanel"][row]);
    UIViewController *p=[cls isSubclassOfClass:UITableViewController.class]?[(UITableViewController *)[cls alloc]initWithStyle:UITableViewStyleInsetGrouped]:[cls new];if(p)[self.navigationController pushViewController:p animated:YES];
}
- (void)legacySelect:(UITableView *)tableView at:(NSIndexPath *)ip {
    if(ip.section==0&&ip.row==0){
        UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Response Model" message:@"Selecting experimental takeover sends transcribed queries to your configured model service." preferredStyle:UIAlertControllerStyleActionSheet];
        NSArray *titles=@[@"RayNeo Official",@"Random String (No API)",@"Custom Model (Experimental)"];
        for(NSInteger i=0;i<3;i++){[a addAction:[UIAlertAction actionWithTitle:titles[i] style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){[Controller cancel];[Prefs setInteger:i forKey:@"mode"];if(i)[Prefs setObject:@"chat" forKey:@"verifiedChatDomain"];[self.tableView reloadData];}]];}
        [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];a.popoverPresentationController.sourceView=self.view;a.popoverPresentationController.sourceRect=CGRectMake(self.view.bounds.size.width/2,100,1,1);[self presentViewController:a animated:YES completion:nil];
    }else if(ip.section==0&&ip.row==1)[self configure];
    else if(ip.section==0&&ip.row==8)[self configureSearch];
    else if(ip.section==0&&ip.row==9)[self testSearch];
    else if(ip.section==0&&ip.row==10)TIOOpenTodoRuntime(self);
    else if(ip.section==0&&ip.row==12)TIOOpenNewsReader(self);
    else if(ip.section==0&&ip.row==11)[self showModelTools];
    else if(ip.section==0&&ip.row==4){UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Clear Context History?" message:@"Only clears conversation memory in this addon; does not affect official chat history." preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];[a addAction:[UIAlertAction actionWithTitle:@"Clear" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x){[Controller cancel];[Controller.history clear];[Prefs setInteger:0 forKey:@"mode"];[self.tableView reloadData];}]];[self presentViewController:a animated:YES completion:nil];}
    else if(ip.section==0&&ip.row==5)TIOOpenProfile(self);
    else if(ip.section==0&&ip.row==2){[_testRequest cancel];_testRequest=[TIORequest new];__weak typeof(self) weakSelf=self;_testRequest.update=^(NSString *text,BOOL done,NSString *error){if(done){Alert(error?@"API Test Failed":@"API Test Result",error?:text);weakSelf.testRequest=nil;}};[_testRequest startQuestion:@"Reply strictly: API test successful."];
    }else if(ip.section==1&&ip.row==1){dispatch_async(ArchiveQueue,^{NSError *error=nil;NSArray *urls=[Archive exportAt:NSDate.date error:&error];dispatch_async(dispatch_get_main_queue(),^{if(!urls){Alert(@"No Files",error.localizedDescription?:@"Export failed.");return;}UIActivityViewController *sheet=[[UIActivityViewController alloc]initWithActivityItems:urls applicationActivities:nil];sheet.popoverPresentationController.sourceView=self.view;sheet.popoverPresentationController.sourceRect=CGRectMake(self.view.bounds.size.width/2,100,1,1);[self presentViewController:sheet animated:YES completion:nil];});});}
    else if(ip.section==2)[self.tableView reloadData];
}
@end

// Simulator-only host uses these same UIKit controllers, no official binary,
// credentials, hardware hooks or network-backed model service.
#if TIO_UI_PREVIEW
UITabBarController *TIOCreateResearchPreview(void){
    Prefs=[[NSUserDefaults alloc]initWithSuiteName:@"io.turboio.research.preview"];
    [Prefs registerDefaults:@{@"mode":@0,@"voiceExitCommands":@YES,@"ttsEnabled":@YES,@"ttsEngine":@"local"}];
    VoiceTTS=[[TIOVoiceTTS alloc]initWithKeyProvider:^{return @"";}];
    VoiceTTS.localMode=YES;
    Controller=[TIOController new];Diagnostic=@"UI Preview: Glasses not connected, official library not loaded";
    ArchiveQueue=dispatch_queue_create("io.turboio.preview.archive",DISPATCH_QUEUE_SERIAL);
    Archive=[[TIOTranscriptArchive alloc]initWithDirectory:[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"ResearchPreview"]]];
    TIONewsConfigure(^TIONewsCancel(NSString *prompt,void (^done)(NSString *,NSString *)){
        __block BOOL cancelled=NO;dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{if(!cancelled)done(@"Preview Sample\n\nThis is synthetic content, not real news. Offline preview.",nil);});return [^{cancelled=YES;} copy];
    });
    NSMutableArray *pages=[NSMutableArray new];for(NSString *key in @[@"model",@"library",@"diagnostics"]){TIOPanel *p=[[TIOPanel alloc]initWithStyle:UITableViewStyleInsetGrouped];p.page=key;[pages addObject:p];}
    return TIOCreateResearchTabs(@[pages[0],TIONewsReaderController(),pages[1],pages[2]]);
}
#endif

@interface TIOEntryTarget : NSObject
+ (void)show;
@end
@implementation TIOEntryTarget
+ (void)show {UIViewController *top=TopController();if(!top||top.tabBarController.view.tag==7920||top.view.tag==7920)return;static UITabBarController *shell;
    if(!shell){NSMutableArray *pages=[NSMutableArray new];for(NSString *key in @[@"model",@"library",@"diagnostics"]){TIOPanel *p=[[TIOPanel alloc]initWithStyle:UITableViewStyleInsetGrouped];p.page=key;[pages addObject:p];}shell=TIOCreateResearchTabs(@[pages[0],TIONewsReaderController(),pages[1],pages[2]]);}
    for(UINavigationController *nav in shell.viewControllers)[nav popToRootViewControllerAnimated:NO];Entry.hidden=YES;[top presentViewController:shell animated:YES completion:nil];}
@end

static BOOL Signature(Class cls,NSString *name,NSUInteger argc,const char *returnType,NSArray<NSString *> *types) {
    Method m=class_getInstanceMethod(cls,NSSelectorFromString(name));if(!m||method_getNumberOfArguments(m)!=argc)return NO;
    char *r=method_copyReturnType(m);BOOL ok=r&&r[0]==returnType[0];free(r);
    for(NSUInteger i=2;i<argc;i++){char *t=method_copyArgumentType(m,(unsigned)i);NSString *allowed=types[i-2];if(!t||![allowed containsString:[NSString stringWithFormat:@"%c",t[0]]])ok=NO;free(t);}return ok;
}
#import "HostCompatibility.h"
static BOOL VersionMatches(void) {
    if(![NSBundle.mainBundle.bundleIdentifier isEqual:TargetBundle])return NO;
    const struct mach_header *h=NULL;
    const char *executable=NSBundle.mainBundle.executablePath.fileSystemRepresentation;
    for(uint32_t i=0;i<_dyld_image_count();i++){const char *name=_dyld_get_image_name(i);if(name&&executable&&strcmp(name,executable)==0){h=_dyld_get_image_header(i);break;}}
    return TIOHostImageMatches(h,NSBundle.mainBundle.infoDictionary);
}
static void AddEntry(void) {
    UIViewController *top=TopController();UIWindow *window=top.view.window;if(!window)return;
    if(top.tabBarController.view.tag==7920||top.view.tag==7920){Entry.hidden=YES;return;}
    if(!Entry){Entry=[UIButton buttonWithType:UIButtonTypeSystem];[Entry setTitle:@"HUD" forState:UIControlStateNormal];Entry.accessibilityLabel=@"RayNeo HUD Addon";Entry.backgroundColor=UIColor.systemIndigoColor;[Entry setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];Entry.layer.cornerRadius=20;[Entry addTarget:TIOEntryTarget.class action:@selector(show) forControlEvents:UIControlEventTouchUpInside];}
    Entry.hidden=NO;Entry.frame=CGRectMake(window.bounds.size.width-66,window.safeAreaInsets.top+80,54,40);[window addSubview:Entry];
    if(VersionMatches())TIOStartHomeTabBridge(Entry,^{[TIOEntryTarget show];});
}
__attribute__((constructor)) static void Load(void) {
    // Do not message Foundation/UIKit or create an ObjC autorelease pool under
    // the remote loader lock. All setup runs on main after scheduling via C API.
    dispatch_async(dispatch_get_main_queue(),^{
        @autoreleasepool {
            if(![NSBundle.mainBundle.bundleIdentifier isEqual:TargetBundle])return;
#if TIO_OTA_RESEARCH_ENABLED
            TIOStartExperimentalOTAFeedIfMarked();
#endif
            Prefs=[[NSUserDefaults alloc]initWithSuiteName:Domain];
            [Prefs registerDefaults:@{@"voiceExitCommands":@YES,@"ttsEnabled":@YES,@"ttsEngine":@"local"}];
            Controller=[TIOController new];
            ImportPrivateBootstrap();
            VoiceTTS=[[TIOVoiceTTS alloc]initWithKeyProvider:^{return ReadKey(TIOVoiceTTSService());}];
            VoiceTTS.localMode=[[Prefs stringForKey:@"ttsEngine"] isEqual:@"local"];
            TIONewsConfigure(^TIONewsCancel(NSString *prompt,void (^completion)(NSString *,NSString *)){
                TIORequest *request=[TIORequest new];request.newsMode=YES;request.history=@[];
                request.update=^(NSString *text,BOOL done,NSString *error){if(done)completion(text,error);};
                // Start next turn so even immediate config errors do not race
                // assignment of the cancellation handle in the news controller.
                __block BOOL cancelled=NO;dispatch_async(dispatch_get_main_queue(),^{if(!cancelled)[request startQuestion:prompt];});
                return [^{cancelled=YES;[request cancel];} copy];
            });
            // Research rows are explicit routes now, not a chain of table hooks.
            [Prefs registerDefaults:@{@"voiceExitCommands":@YES,@"ttsEnabled":@YES,@"ttsEngine":@"local",@"verifiedChatDomain":@"chat"}];
            // Do not automatically resume text capture after relaunch/crash.
            [Prefs setBool:NO forKey:@"captureFinalText"];
            if(![Prefs stringForKey:@"verifiedChatDomain"])[Prefs setObject:@"chat" forKey:@"verifiedChatDomain"];
            NSURL *library=[NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
            Archive=[[TIOTranscriptArchive alloc]initWithDirectory:[library URLByAppendingPathComponent:@"TurboIOPrivateAddon" isDirectory:YES]];ArchiveQueue=dispatch_queue_create("io.turboio.private.archive",DISPATCH_QUEUE_SERIAL);
            Class voice=NSClassFromString(@"rayneo_venus_sdk_plugin.AiResultListenerBridge"),ao=NSClassFromString(@"rayneo_venus_sdk_plugin.AlwaysOnResultListenerBridge");
            BOOL valid=VersionMatches()&&Signature(voice,@"onAsrResult:isFinish:sessionId:",5,"v",@[@"@",@"Bc",@"@"])&&Signature(voice,@"onNlpResult:",3,"v",@[@"@"])&&Signature(voice,@"onResponseComplete",2,"v",@[])&&Signature(ao,@"onAlwaysOnResponse:",3,"v",@[@"@"]);
            if(valid){OriginalAsr=(void *)method_setImplementation(class_getInstanceMethod(voice,NSSelectorFromString(@"onAsrResult:isFinish:sessionId:")),(IMP)AsrHook);OriginalNlp=(void *)method_setImplementation(class_getInstanceMethod(voice,NSSelectorFromString(@"onNlpResult:")),(IMP)NlpHook);OriginalComplete=(void *)method_setImplementation(class_getInstanceMethod(voice,NSSelectorFromString(@"onResponseComplete")),(IMP)CompleteHook);OriginalAlwaysOn=(void *)method_setImplementation(class_getInstanceMethod(ao,NSSelectorFromString(@"onAlwaysOnResponse:")),(IMP)AlwaysOnHook);HooksReady=YES;Diagnostic=@"ObjC callback signatures verified; waiting for events";}else Diagnostic=@"Version or ABI mismatch: no callbacks modified";
            Class helper=NSClassFromString(@"rayneo_venus_sdk_plugin.VoiceAssistantHelper");
            VoiceExitReady=valid&&Signature(object_getClass(helper),@"shared",2,"@",@[])&&Signature(helper,@"stopWorkflow",2,"v",@[])&&Signature(voice,@"onAudioRecordStart",2,"v",@[]);
            if(VoiceExitReady)OriginalAudioStart=(void *)method_setImplementation(class_getInstanceMethod(voice,NSSelectorFromString(@"onAudioRecordStart")),(IMP)AudioStartHook);
            if(valid)TIOInstallTodoRuntime();
            NSMutableString *loadInfo=[NSMutableString stringWithFormat:@"setup reached; hooks=%d; version=%d; voiceClass=%d; alwaysOnClass=%d\n",valid,VersionMatches(),voice!=Nil,ao!=Nil];
            [loadInfo appendFormat:@"bundle=%@; version=%@; build=%@\n",NSBundle.mainBundle.bundleIdentifier,[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"],[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleVersion"]];
            for(uint32_t i=0;i<_dyld_image_count();i++){const char *name=_dyld_get_image_name(i);if(name&&[[NSString stringWithUTF8String:name].lastPathComponent isEqual:@"Runner"]){const struct mach_header *h=_dyld_get_image_header(i);[loadInfo appendFormat:@"Runner image index=%u magic=%x\n",i,h->magic];}}
            for(NSString *sel in @[@"onAsrResult:isFinish:sessionId:",@"onNlpResult:",@"onResponseComplete",@"onAlwaysOnResponse:"]){Method m=class_getInstanceMethod([sel isEqual:@"onAlwaysOnResponse:"]?ao:voice,NSSelectorFromString(sel));[loadInfo appendFormat:@"%@ %s\n",sel,m?method_getTypeEncoding(m):"missing"];}
            [loadInfo writeToFile:[NSTemporaryDirectory() stringByAppendingPathComponent:@"TurboIOPrivateAddon-load.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
            [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){AddEntry();}];
            [NSNotificationCenter.defaultCenter addObserverForName:@"TIOResearchClosed" object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){AddEntry();}];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(),^{AddEntry();});
        }
    });
}
