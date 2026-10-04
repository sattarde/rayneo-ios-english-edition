#import "ManualHUD.h"
#import "NewsTeleprompter.h"
#import "ResearchUI.h"
@interface TIOManualHUDPanel:UITableViewController
@property NSTimer *timer;
@property NSString *note;
@property NSTimeInterval started;
@end
@implementation TIOManualHUDPanel
- (void)viewDidLoad{[super viewDidLoad];self.title=@"Manual always on · Draft change v2";TIOStyleResearchTable(self);self.note=@"First obtain the official manual mode sample and exit, then publish your own fixed draft. After seeing 7392, you can test draft change B; do not choose smart follow-up.";[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refresh) name:@"TIONewsTeleChanged" object:nil];[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(stopOwned) name:UIApplicationWillResignActiveNotification object:nil];[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(stopOwned) name:@"TIOResearchClosed" object:nil];}
- (void)viewWillAppear:(BOOL)a{[super viewWillAppear:a];__weak typeof(self) w=self;if(!self.timer)self.timer=[NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *t){[w refresh];}];[self refresh];}
- (void)viewDidDisappear:(BOOL)a{[super viewDidDisappear:a];if(self.isMovingFromParentViewController||self.navigationController.isBeingDismissed||self.tabBarController.isBeingDismissed)[self stopOwned];[self.timer invalidate];self.timer=nil;}
- (void)dealloc{[self.timer invalidate];[NSNotificationCenter.defaultCenter removeObserver:self];}
- (void)refresh{NSDictionary *s=TIONewsTeleStatus();if([s[@"manual"] boolValue]&&[s[@"playing"] boolValue]){if(!self.started)self.started=NSProcessInfo.processInfo.systemUptime;}else self.started=0;if(self.isViewLoaded&&self.view.window)[self.tableView reloadData];}
- (void)stopOwned{if([TIONewsTeleStatus()[@"manual"] boolValue])TIONewsTeleControl(6,120);self.note=@"You have requested to exit this manuscript and do not modify other manuscripts; if the exit receipt times out, please use the glasses button to exit.";[self refresh];}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s{return 10;}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip{
    NSDictionary *s=TIONewsTeleStatus();UITableViewCell *c=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];c.textLabel.numberOfLines=0;c.detailTextLabel.numberOfLines=0;
    NSArray *titles=@[@"Current test status",@"Go back to the official App to get manual mode samples",@"1·Send three fixed test drafts",@"2·Start manual constant light (no automatic scrolling)",@"Preload paragraph · 7392",@"Preload paragraph · 8642",@"Preload paragraph · 5173",@"Exit this always-on test",@"3 · Replace text B · 9264",@"4 · Replace text C · 3815"];
    c.textLabel.text=titles[ip.row];c.accessibilityIdentifier=[NSString stringWithFormat:@"manual-hud-%ld",(long)ip.row];BOOL manual=[s[@"manual"] boolValue],pending=[s[@"manualPending"] unsignedIntegerValue]!=0;
    BOOL controllable=manual&&[s[@"playing"] boolValue]&&[s[@"ready"] boolValue]&&!pending&&![s[@"manualBlocked"] boolValue]&&![s[@"replacing"] boolValue]&&![s[@"stopping"] boolValue];
    BOOL enabled=ip.row==1||(ip.row==2&&[s[@"manualAvailable"] boolValue]&&![s[@"active"] boolValue])||(ip.row==3&&manual&&[s[@"ready"] boolValue]&&![s[@"started"] boolValue]&&!pending&&! [s[@"manualBlocked"] boolValue])||(ip.row>=4&&ip.row<=6&&controllable&&[s[@"revision"] unsignedIntegerValue]==0)||(ip.row==7&&manual&&![s[@"stopping"] boolValue])||(ip.row==8&&controllable&&[s[@"revision"] unsignedIntegerValue]==0)||(ip.row==9&&controllable&&[s[@"revision"] unsignedIntegerValue]==1);
    if(ip.row==0){c.detailTextLabel.text=[NSString stringWithFormat:@"%@\n%@\n Manual template: %@ · Same device prompt audio package: %@\n Timing after start receipt: %ld seconds (not proof of lens bright screen) \n Waiting control: %@ · Draft change round: %@ · Transmitting: %@",self.note?:@"",s[@"state"],[s[@"manualAvailable"] boolValue]?@"All ready":@"Not all ready",s[@"audioPackets"],self.started?(long)(NSProcessInfo.processInfo.systemUptime-self.started):0,s[@"manualPending"],s[@"revision"],[s[@"replacing"] boolValue]?@"yes":@"no"];}
    else if(ip.row==2)c.detailTextLabel.text=@"No Internet connection, no positioning, no real navigation; create a new exclusive manuscript and do not overwrite the original manuscript. The process will only start after confirmation of receipt.";
    else if(ip.row==3)c.detailTextLabel.text=@"You can test the draft change when you see 7392, no need to wait another 3 minutes. Automatically request to exit 5 minutes after preparation; also request to exit when leaving this page or locking the screen.";
    else if(ip.row>=4&&ip.row<=6)c.detailTextLabel.text=@"Send UTF-8 byte boundary offset; only the actual lens check code is used to determine the success of the jump.";
    else if(ip.row==8)c.detailTextLabel.text=@"With the same test draft ID, re-input the new text; do not send exit or restart. Please observe 9264, splash screen, receiving page or old content stuck. The request exits after 20 seconds timeout.";
    else if(ip.row==9)c.detailTextLabel.text=@"Click only if you have seen B and there is no abnormality. The second time is replaced with 3815; up to two times, no looping, no real navigation. If there is an exception, please exit directly.";
    c.textLabel.textColor=enabled?UIColor.labelColor:UIColor.secondaryLabelColor;c.selectionStyle=enabled?UITableViewCellSelectionStyleDefault:UITableViewCellSelectionStyleNone;c.userInteractionEnabled=enabled||ip.row==0;return c;
}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip{[t deselectRowAtIndexPath:ip animated:YES];BOOL ok=NO;if(ip.row==1){[self stopOwned];TIOCloseResearch(self);return;}if(ip.row==2)ok=TIOTeleManualPrepare();if(ip.row==3)ok=TIONewsTeleControl(3,120);if(ip.row>=4&&ip.row<=6)ok=TIOTeleManualSeek(ip.row-4);if(ip.row==7){[self stopOwned];return;}if(ip.row==8||ip.row==9)ok=TIOTeleManualReplace();self.note=ok?@"The request has been submitted, please observe the lens at the same time; the status return is saved in the local diagnostic file.":@"Not submitted: Check manual samples, current session, and pending receipt status.";[self refresh];}
@end
UIViewController *TIOManualHUDController(void){return [[TIOManualHUDPanel alloc]initWithStyle:UITableViewStyleInsetGrouped];}
