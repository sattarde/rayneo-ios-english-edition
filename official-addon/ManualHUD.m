#import "ManualHUD.h"
#import "NewsTeleprompter.h"
#import "ResearchUI.h"
@interface TIOManualHUDPanel:UITableViewController
@property NSTimer *timer;
@property NSString *note;
@property NSTimeInterval started;
@end
@implementation TIOManualHUDPanel
- (void)viewDidLoad{[super viewDidLoad];self.title=@"Manual Teleprompter HUD v2";TIOStyleResearchTable(self);self.note=@"Acquire official manual teleprompter sample first and exit, then send custom text. After seeing 7392 you can test manuscript B; do not select smart follow.";[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refresh) name:@"TIONewsTeleChanged" object:nil];[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(stopOwned) name:UIApplicationWillResignActiveNotification object:nil];[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(stopOwned) name:@"TIOResearchClosed" object:nil];}
- (void)viewWillAppear:(BOOL)a{[super viewWillAppear:a];__weak typeof(self) w=self;if(!self.timer)self.timer=[NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *t){[w refresh];}];[self refresh];}
- (void)viewDidDisappear:(BOOL)a{[super viewDidDisappear:a];if(self.isMovingFromParentViewController||self.navigationController.isBeingDismissed||self.tabBarController.isBeingDismissed)[self stopOwned];[self.timer invalidate];self.timer=nil;}
- (void)dealloc{[self.timer invalidate];[NSNotificationCenter.defaultCenter removeObserver:self];}
- (void)refresh{NSDictionary *s=TIONewsTeleStatus();if([s[@"manual"] boolValue]&&[s[@"playing"] boolValue]){if(!self.started)self.started=NSProcessInfo.processInfo.systemUptime;}else self.started=0;if(self.isViewLoaded&&self.view.window)[self.tableView reloadData];}
- (void)stopOwned{if([TIONewsTeleStatus()[@"manual"] boolValue])TIONewsTeleControl(6,120);self.note=@"Requested exit for manual manuscript; other manuscripts unmodified. If exit ACK times out, use physical button on glasses.";[self refresh];}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s{return 10;}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip{
    NSDictionary *s=TIONewsTeleStatus();UITableViewCell *c=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];c.textLabel.numberOfLines=0;c.detailTextLabel.numberOfLines=0;
    NSArray *titles=@[@"Current Test Status",@"Return to Official App to Sample Manual Mode",@"1 · Send 3-section Fixed Test Script",@"2 · Start Manual HUD (No Auto-scroll)",@"Preload Paragraph · 7392",@"Preload Paragraph · 8642",@"Preload Paragraph · 5173",@"Exit Current HUD Test",@"3 · Replace Text B · 9264",@"4 · Replace Text C · 3815"];
    c.textLabel.text=titles[ip.row];c.accessibilityIdentifier=[NSString stringWithFormat:@"manual-hud-%ld",(long)ip.row];BOOL manual=[s[@"manual"] boolValue],pending=[s[@"manualPending"] unsignedIntegerValue]!=0;
    BOOL controllable=manual&&[s[@"playing"] boolValue]&&[s[@"ready"] boolValue]&&!pending&&![s[@"manualBlocked"] boolValue]&&![s[@"replacing"] boolValue]&&![s[@"stopping"] boolValue];
    BOOL enabled=ip.row==1||(ip.row==2&&[s[@"manualAvailable"] boolValue]&&![s[@"active"] boolValue])||(ip.row==3&&manual&&[s[@"ready"] boolValue]&&![s[@"started"] boolValue]&&!pending&&! [s[@"manualBlocked"] boolValue])||(ip.row>=4&&ip.row<=6&&controllable&&[s[@"revision"] unsignedIntegerValue]==0)||(ip.row==7&&manual&&![s[@"stopping"] boolValue])||(ip.row==8&&controllable&&[s[@"revision"] unsignedIntegerValue]==0)||(ip.row==9&&controllable&&[s[@"revision"] unsignedIntegerValue]==1);
    if(ip.row==0){c.detailTextLabel.text=[NSString stringWithFormat:@"%@\n%@\nManual Template: %@ · Same Device Audio Packets: %@\nTimer after start ACK: %ld s (not proof of glasses display)\nPending control: %@ · Replace revision: %@ · Transferring: %@",self.note?:@"",s[@"state"],[s[@"manualAvailable"] boolValue]?@"Ready":@"Not ready",s[@"audioPackets"],self.started?(long)(NSProcessInfo.processInfo.systemUptime-self.started):0,s[@"manualPending"],s[@"revision"],[s[@"replacing"] boolValue]?@"Yes":@"No"];}
    else if(ip.row==2)c.detailTextLabel.text=@"No internet, no GPS, not real navigation. Creates dedicated script without overwriting originals. Requires ACK before start.";
    else if(ip.row==3)c.detailTextLabel.text=@"Once 7392 is visible, replace text can be tested. 5-min timeout auto-requests exit; leaving screen or locking phone also requests exit.";
    else if(ip.row>=4&&ip.row<=6)c.detailTextLabel.text=@"Sends UTF-8 byte boundary offset. Verify jump only by physical glasses display.";
    else if(ip.row==8)c.detailTextLabel.text=@"Same test script ID, transmits new text; no exit or restart sent. Observe 9264, screen flash, or stale content. 20s timeout requests exit.";
    else if(ip.row==9)c.detailTextLabel.text=@"Only tap after seeing B without anomalies. Second replace is 3815; max 2 times, no loop. Tap Exit if abnormal.";
    c.textLabel.textColor=enabled?UIColor.labelColor:UIColor.secondaryLabelColor;c.selectionStyle=enabled?UITableViewCellSelectionStyleDefault:UITableViewCellSelectionStyleNone;c.userInteractionEnabled=enabled||ip.row==0;return c;
}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip{[t deselectRowAtIndexPath:ip animated:YES];BOOL ok=NO;if(ip.row==1){[self stopOwned];TIOCloseResearch(self);return;}if(ip.row==2)ok=TIOTeleManualPrepare();if(ip.row==3)ok=TIONewsTeleControl(3,120);if(ip.row>=4&&ip.row<=6)ok=TIOTeleManualSeek(ip.row-4);if(ip.row==7){[self stopOwned];return;}if(ip.row==8||ip.row==9)ok=TIOTeleManualReplace();self.note=ok?@"Request submitted, observe glasses; status telemetry saved to local diagnostics.":@"Not submitted: check manual sample, active session, and pending ACK state.";[self refresh];}
@end
UIViewController *TIOManualHUDController(void){return [[TIOManualHUDPanel alloc]initWithStyle:UITableViewStyleInsetGrouped];}
