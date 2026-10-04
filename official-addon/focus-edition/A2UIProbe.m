#import "A2UIProbe.h"
#import <UIKit/UIKit.h>
#import <objc/message.h>
// All state transitions run on main. Passive observation never sends a packet.
static __weak id Plugin;
static NSDictionary *Route,*Baseline,*BeforeBaseline;
static NSString *Device,*Owned,*OwnedDevice,*Note=@"Connect glasses on official home page before reading baseline";
static NSTimeInterval RouteAt,BaselineAt;
static uint32_t PendingSequence;
static NSString *PendingOperation;
static BOOL Injecting,ReadRequested,TextAccepted;
static NSMutableArray *Trace;
static id Get(id o,NSString *key){@try{return [o valueForKey:key];}@catch(NSException *e){return nil;}}
static NSData *Bytes(id o){if([o isKindOfClass:NSData.class])return o;id d=Get(o,@"data");return [d isKindOfClass:NSData.class]?d:nil;}
static NSString *Dir(void){NSString *p=[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/TurboIOPrivateAddon/A2UIProbe"];[NSFileManager.defaultManager createDirectoryAtPath:p withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil];return p;}
static void Save(NSString *name,id object){NSData *d=[NSJSONSerialization dataWithJSONObject:object options:NSJSONWritingSortedKeys error:nil];NSString *p=[Dir() stringByAppendingPathComponent:name];[d writeToFile:p options:NSDataWritingAtomic error:nil];[NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions:@0600,NSFileProtectionKey:NSFileProtectionCompleteUntilFirstUserAuthentication} ofItemAtPath:p error:nil];}
static void Changed(NSString *event,NSDictionary *values){
    if(!Trace)Trace=[NSMutableArray new];NSMutableDictionary *r=[values mutableCopy]?:[NSMutableDictionary new];r[@"event"]=event;r[@"time"]=@(NSDate.date.timeIntervalSince1970);[Trace addObject:r];if(Trace.count>60)[Trace removeObjectAtIndex:0];
    Save(@"status.json",@{@"state":Note,@"trace":Trace,@"hasBaseline":@(Baseline!=nil),@"ownedId":Owned?:@"",@"pendingSequence":@(PendingSequence),@"displayVerified":@NO});
    [NSNotificationCenter.defaultCenter postNotificationName:@"TIOA2UIChanged" object:nil];
}
static void LoadOwner(void){if(Owned)return;NSDictionary *o=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:[Dir() stringByAppendingPathComponent:@"owner.json"]]?:NSData.data options:0 error:nil];if(TIOA2UIUninstall(o[@"id"])&&[o[@"device"] isKindOfClass:NSString.class]){Owned=o[@"id"];OwnedDevice=o[@"device"];NSDictionary *saved=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:[Dir() stringByAppendingPathComponent:@"before-components.json"]]?:NSData.data options:0 error:nil];if([saved[@"device"] isEqual:OwnedDevice]&&[saved[@"id"] isEqual:Owned]&&TIOA2UIBaselinePreservesOthers(saved[@"baseline"],saved[@"baseline"],Owned))BeforeBaseline=saved[@"baseline"];} }
static BOOL CanSend(BOOL query){return TIOA2UITransportAllowed(query,Plugin&&Route&&Device.length,UIApplication.sharedApplication.applicationState==UIApplicationStateActive,NSDate.date.timeIntervalSince1970-RouteAt,PendingSequence!=0);}
static BOOL Ready(void){return CanSend(NO);}
void TIOA2UIObserveCall(id plugin,NSString *method,NSDictionary *args){
    if(Injecting||![method isEqual:@"rayneonet_sendMessage"]||![args[@"businessId"] isEqual:@15]||![args[@"deviceId"] isKindOfClass:NSString.class])return;
    NSDictionary *e=TIOA2UIDecode(Bytes(args[@"payload"]));if(!e)return;
    NSString *device=args[@"deviceId"];if(Device&&![Device isEqual:device]){Route=nil;Baseline=nil;TextAccepted=NO;ReadRequested=NO;PendingSequence=0;Note=@"Connection target changes, please re-read the baseline";}
    Device=device;Plugin=plugin;RouteAt=NSDate.date.timeIntervalSince1970;
    NSMutableDictionary *r=[args mutableCopy];[r removeObjectForKey:@"payload"];Route=r;
    // No outgoing/incoming official content is saved by passive observation.
}
static BOOL Send(NSDictionary *json,NSString *operation){
    if(![operation isEqual:@"query"]&&(!OwnedDevice||![OwnedDevice isEqual:Device])){Note=@"Not sent: test card belongs to different glasses";Changed(@"device_mismatch",@{});return NO;}
    if(!CanSend([operation isEqual:@"query"])||!json){Note=@"Not sent: connect on official home page first; refresh baseline before write";Changed(@"not_sent",@{});return NO;}
    if(![operation isEqual:@"query"]&&(!Baseline||NSDate.date.timeIntervalSince1970-BaselineAt>=120)){Note=@"Not sent: The baseline has expired during the confirmation period, please re-read the baseline";Changed(@"stale_baseline",@{});return NO;}
    uint32_t seq=arc4random_uniform(0x3fffffff)+0x40000000;
    NSData *packet=TIOA2UIPacket(18,seq,json);Class typed=NSClassFromString(@"FlutterStandardTypedData"),callClass=NSClassFromString(@"FlutterMethodCall");SEL typedSEL=NSSelectorFromString(@"typedDataWithBytes:"),make=NSSelectorFromString(@"methodCallWithMethodName:arguments:"),handle=NSSelectorFromString(@"handleMethodCall:result:");
    if(!packet||![typed respondsToSelector:typedSEL]||![callClass respondsToSelector:make]||![Plugin respondsToSelector:handle]){Note=@"Not sent: The current host lacks the expected communication interface or the test package is invalid";Changed(@"host_unavailable",@{});return NO;}
    if(![operation isEqual:@"query"]&&![operation isEqual:@"uninstall"]&&!BeforeBaseline){
        if(!TIOA2UIBaselinePreservesOthers(Baseline,Baseline,Owned)){Note=@"Not sent: baseline structure could not be safely verified";Changed(@"invalid_baseline",@{});return NO;}
        BeforeBaseline=Baseline;Save(@"before-components.json",@{@"device":Device,@"id":Owned,@"baseline":BeforeBaseline});
    }
    NSMutableDictionary *args=[Route mutableCopy];args[@"payload"]=((id(*)(id,SEL,id))objc_msgSend)(typed,typedSEL,packet);args[@"businessId"]=@15;
    id call=((id(*)(id,SEL,id,id))objc_msgSend)(callClass,make,@"rayneonet_sendMessage",args);
    PendingSequence=seq;PendingOperation=operation;Note=@"Test packet submitted, waiting for matching sequence receipt";
    Save([NSString stringWithFormat:@"request-%u.json",seq],@{@"businessId":@15,@"type":@18,@"sequence":@(seq),@"json":json});Changed(@"submit",@{@"sequence":@(seq),@"operation":operation,@"bytes":@(packet.length)});
    Injecting=YES;@try{((void(*)(id,SEL,id,id))objc_msgSend)(Plugin,handle,call,[^(id result){dispatch_async(dispatch_get_main_queue(),^{BOOL success=[result isKindOfClass:NSDictionary.class]&&[result[@"success"] isEqual:@YES];Changed(@"transport_callback",@{@"sequence":@(seq),@"successField":@(success),@"resultClass":NSStringFromClass([result class])?:@"nil"});});} copy]);}@catch(NSException *e){PendingSequence=0;ReadRequested=NO;Note=@"The sending call throws an exception; do not repeat the installation, please read the configuration and check first.";Changed(@"exception",@{});}Injecting=NO;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,20*NSEC_PER_SEC),dispatch_get_main_queue(),^{if(PendingSequence==seq){PendingSequence=0;ReadRequested=NO;Note=@"If no matching receipt is received within 20 seconds, the result is unknown; no automatic retransmission will be performed. Refresh the baseline first, then decide to clean";Changed(@"timeout",@{@"sequence":@(seq)});}});return YES;
}
void TIOA2UIObserveEvent(NSDictionary *event){
    if(![event[@"eventType"] isEqual:@"messageReceived"])return;NSDictionary *m=event[@"message"];
    if(![m isKindOfClass:NSDictionary.class]||![m[@"businessId"] isEqual:@15]||![m[@"deviceId"] isEqual:Device])return;
    NSDictionary *e=TIOA2UIDecode(Bytes(m[@"payload"]));if(![e[@"type"] isEqual:@19])return;NSDictionary *j=e[@"json"];
    if(ReadRequested&&[j[@"cmd"] isEqual:@"dashboard_config"]){
        id payload=j[@"payload"];id body=[payload isKindOfClass:NSDictionary.class]?payload[@"data"]:nil;if([body isKindOfClass:NSString.class])body=[NSJSONSerialization JSONObjectWithData:[body dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
        if([body isKindOfClass:NSDictionary.class]&&[body[@"widgets_v2"] isKindOfClass:NSArray.class]){Baseline=body;BaselineAt=NSDate.date.timeIntervalSince1970;RouteAt=BaselineAt;ReadRequested=NO;PendingSequence=0;Save(@"dashboard-baseline.json",body);BOOL found=NO;for(id row in body[@"widgets_v2"])if([row isKindOfClass:NSDictionary.class]&&[row[@"id"] isEqual:Owned])found=YES;
            Note=found?@"Config includes test card. Scroll glasses dashboard to verify.":@"Dashboard baseline saved; independent text test card ready to install.";
            if(BeforeBaseline&&[OwnedDevice isEqual:Device]){
                BOOL preserved=TIOA2UIBaselinePreservesOthers(BeforeBaseline,body,Owned);
                Note=[Note stringByAppendingString:preserved?@" · other card configs unchanged":@" · warning: other card configs changed"];
                Changed(@"other_widgets_check",@{@"preserved":@(preserved),@"containsOwned":@(found)});
            }
            Changed(@"config_snapshot",@{@"count":@([body[@"widgets_v2"] count]),@"containsOwned":@(found)});}return;
    }
    uint32_t seq=[e[@"sequence"] unsignedIntValue];if(!PendingSequence||seq!=PendingSequence||[PendingOperation isEqual:@"query"])return;
    // Management response is {code,err_msg,data}, not legacy {cmd,payload.value}.
    if(![j[@"code"] isKindOfClass:NSNumber.class]||CFGetTypeID((__bridge CFTypeRef)j[@"code"])==CFBooleanGetTypeID())return;
    Save([NSString stringWithFormat:@"response-%u.json",seq],e);NSInteger code=[j[@"code"] integerValue];
    if(code==0){if([PendingOperation isEqual:@"uninstall"])TextAccepted=NO;else if([PendingOperation isEqual:@"text"]||[PendingOperation isEqual:@"layout"])TextAccepted=YES;Note=[PendingOperation isEqual:@"uninstall"]?@"The glasses are confirmed to be uninstalled successfully. Please read the baseline to verify that the test card has been removed.":@"Glasses return code=0; please go to the dashboard to view the test content, which does not mean it has been displayed.";}
    else Note=[NSString stringWithFormat:@"Glasses rejected: code=%ld, %@. No auto-retry",(long)code,[j[@"err_msg"] isKindOfClass:NSString.class]?j[@"err_msg"]:@"No error description"];
    PendingSequence=0;Changed(@"device_response",@{@"sequence":@(seq),@"code":@(code),@"operation":PendingOperation?:@""});
}
@interface TIOA2UIPanel:UITableViewController @end
@implementation TIOA2UIPanel
- (void)viewDidLoad{[super viewDidLoad];self.title=@"Custom UI Verification";LoadOwner();[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refresh) name:@"TIOA2UIChanged" object:nil];}
- (void)dealloc{[NSNotificationCenter.defaultCenter removeObserver:self];}
- (void)refresh{[self.tableView reloadData];}
- (NSInteger)tableView:(UITableView *)v numberOfRowsInSection:(NSInteger)s{return 9;}
- (NSString *)tableView:(UITableView *)v titleForFooterInSection:(NSInteger)s{return @"Only test cards owned by this tool are added/uninstalled, full kanban coverage is not sent, refresh subscriptions or sensors are not enabled, and firmware is not changed. Installation receipt ≠ lenses visible. Exiting the page will not delete the test card, you can come back and uninstall it manually.";}
- (UITableViewCell *)tableView:(UITableView *)v cellForRowAtIndexPath:(NSIndexPath *)p{UITableViewCell *c=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];c.textLabel.text=@[@"Current status · COMPONENTS 01",@"1·Read the dashboard baseline",@"2 · Install text card 7392",@"3 · Update typesetting card 8642",@"4 · Uninstall this test card",@"5 · Bar Chart 6111",@"6 · Line chart 6222",@"7 · Single-child container 6333",@"8 · Three-line list 6444"][p.row];c.textLabel.numberOfLines=0;c.detailTextLabel.numberOfLines=0;if(p.row==0)c.detailTextLabel.text=[NSString stringWithFormat:@"%@\n Official sending context: %@",Note,Ready()?@"Available":@"Waiting for official homepage communication"];if(p.row==2)c.detailTextLabel.text=@"Single line of text to verify dynamic component entry";if(p.row==3)c.detailTextLabel.text=@"Only test after you see 7392: title, divider, icon, horizontal and vertical alignment";if(p.row>=5)c.detailTextLabel.text=@"The static format has been verified, but the lenses have not been verified. Replace the same test card; read the baseline first and test one item at a time.";c.accessibilityIdentifier=[NSString stringWithFormat:@"a2ui-probe-%ld",(long)p.row];return c;}
- (void)tableView:(UITableView *)v didSelectRowAtIndexPath:(NSIndexPath *)p{[v deselectRowAtIndexPath:p animated:YES];if(p.row==0){[self refresh];return;}if(p.row==1){if(PendingSequence){Note=@"The last request is still waiting for a receipt, up to 20 seconds; no repeated sending";[self refresh];return;}ReadRequested=YES;if(!Send(@{@"cmd":@"dashboard_config",@"payload":@{@"version":@1,@"value":@0}},@"query"))ReadRequested=NO;return;}
    LoadOwner();if(!Ready()||PendingSequence){Note=@"Confirm connection on official home page before reading baseline";[self refresh];return;}
    if(OwnedDevice&&![OwnedDevice isEqual:Device]){Note=@"Test card belongs to different glasses; cross-device denied";[self refresh];return;}
    if(p.row!=4){if(!Baseline||NSDate.date.timeIntervalSince1970-BaselineAt>=120){Note=@"Read the latest dashboard baseline first (within two minutes)";[self refresh];return;}if(p.row!=2&&!TextAccepted){Note=@"Complete text card installation and lens confirmation first";[self refresh];return;}
        if(!Owned){Owned=[@"turbo_ui_" stringByAppendingString:[NSUUID.UUID.UUIDString.lowercaseString stringByReplacingOccurrencesOfString:@"-" withString:@""]];OwnedDevice=Device;Save(@"owner.json",@{@"id":Owned,@"device":Device});}
    }else if(!Owned){Note=@"No test card created by this tool; uninstall not performed";[self refresh];return;}
    NSString *operation=@[@"",@"query",@"text",@"layout",@"uninstall",@"bar",@"line",@"card",@"list"][p.row];
    UIAlertController *a=[UIAlertController alertControllerWithTitle:p.row==4?@"Uninstall Test Card?":p.row==2?@"Add a custom text card?":@"Already seen the text baseline, continue to single test?" message:@"Only operate the test ID recorded by this tool and do not delete other cards. The test may be rejected by the current firmware; if it fails, it will not be automatically retried. To restore the text card, click item 2, and to clean up, click item 4." preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];[a addAction:[UIAlertAction actionWithTitle:@"Execute tests" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){Send([operation isEqual:@"uninstall"]?TIOA2UIUninstall(Owned):TIOA2UIFixtureInstall(Owned,operation),operation);}]];[self presentViewController:a animated:YES completion:nil];
}
@end
UIViewController *TIOA2UIController(void){return [[TIOA2UIPanel alloc]initWithStyle:UITableViewStyleInsetGrouped];}
