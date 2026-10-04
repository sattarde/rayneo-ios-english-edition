#import "TDPhoneUI.h"
@interface TDPanel:UITableViewController
@property(nonatomic,strong) TDPhoneRun *run;
@property(nonatomic,strong) NSTimer *timer;
@end
static NSArray *Rows(void){return @[
 @[@"lv_configured_bytes",@"LVGL Configured Size",@"B"],@[@"lv_used_bytes",@"LVGL Current Usage",@"B"],@[@"lv_peak_bytes",@"LVGL historical peak",@"B"],
 @[@"lv_free_bytes",@"LVGL Free Memory",@"B"],@[@"lv_largest_free_bytes",@"LVGL Largest Free Block",@"B"],
 @[@"system_arena_bytes",@"System Heap Total Size",@"B"],@[@"system_used_bytes",@"System Heap Usage",@"B"],@[@"system_peak_bytes",@"System heap peak",@"B"],@[@"system_free_bytes",@"System heap free amount",@"B"],@[@"system_largest_free_bytes",@"System maximum free block",@"B"],
 @[@"instrumented_owned_bytes",@"Instrumented Extension Alloc",@"B"],@[@"instrumented_owned_peak_bytes",@"Instrumented Peak Alloc",@"B"],
 @[@"allocation_failures",@"Allocation Failures",@"Second-rate"],@[@"rx_packets",@"RX Packets",@"Bag"],@[@"rx_bytes",@"RX Bytes",@"B"],@[@"rx_max_ms",@"Maximum time required for receiving and processing",@"ms"],
 @[@"render_submissions",@"Render Submissions (Not FPS)",@"Second-rate"],@[@"render_max_ms",@"Render Max Duration",@"ms"],@[@"errors",@"Extension Errors count",@"Second-rate"]];}
@implementation TDPanel
- (void)viewDidLoad{[super viewDidLoad];self.title=@"Glasses Runtime Status · Auto Log";
 self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc]initWithBarButtonSystemItem:UIBarButtonSystemItemAction target:self action:@selector(share)];
 UILabel *intro=[[UILabel alloc]initWithFrame:CGRectMake(20,0,320,130)];intro.numberOfLines=0;intro.font=[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];intro.textColor=UIColor.secondaryLabelColor;
 intro.text=@"PHONE 02 · Automatically records for 10 minutes after being turned on, and can return to Music/Navigation for normal use. Save natively every 5 seconds, no need to export; no lyrics, dialogue or keys saved. System hangs may interrupt the return, and unknown reasons will be recorded truthfully; there will be no automatic reconnection or renewal.";
 UIView *header=[[UIView alloc]initWithFrame:CGRectMake(0,0,360,130)];intro.autoresizingMask=UIViewAutoresizingFlexibleWidth;[header addSubview:intro];self.tableView.tableHeaderView=header;
}
- (void)viewWillAppear:(BOOL)animated{[super viewWillAppear:animated];__weak typeof(self) weak=self;self.timer=[NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *t){(void)t;[weak refresh];}];}
- (void)viewWillDisappear:(BOOL)animated{[super viewWillDisappear:animated];[self.timer invalidate];self.timer=nil;[self.run checkpoint];}
- (void)refresh{
 [self.run poll];
 [self.tableView reloadData];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView{(void)tableView;return 3;}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section{(void)tableView;return section==0?3:section==1?Rows().count:3;}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section{(void)tableView;return @[@"collection",@"Resources and time",@"diagnostic completeness"][section];}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath{
 (void)tableView;UITableViewCell *c=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];c.selectionStyle=UITableViewCellSelectionStyleNone;c.detailTextLabel.textColor=UIColor.secondaryLabelColor;
 if(indexPath.section==0){if(indexPath.row==0){c.textLabel.text=@"Auto Record for 10 Minutes";UISwitch *s=[UISwitch new];s.on=self.run.active;[s addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventValueChanged];c.accessoryView=s;}else if(indexPath.row==1){c.textLabel.text=self.run.status;c.textLabel.numberOfLines=2;c.detailTextLabel.text=[NSString stringWithFormat:@"%lu items recorded · %.0f seconds remaining",(unsigned long)self.run.store.count,self.run.remaining];}else{c.textLabel.text=self.run.saveStatus;c.detailTextLabel.text=@"Each round is saved independently · Up to 100 rounds without overwriting old reports";}}
 else if(indexPath.section==1){NSArray *r=Rows()[indexPath.row];id value=self.run.store.latest[@"metrics"][r[0]];c.textLabel.text=r[1];c.detailTextLabel.text=(!value||value==NSNull.null)?@"Not tested":[NSString stringWithFormat:@"%@ %@",value,r[2]];}
 else{NSString *key=@[@"probe_ms",@"ring_overwritten",@"sequence"][indexPath.row];c.textLabel.text=@[@"This sampling time takes (milliseconds)",@"Glasses event ring coverage number",@"Latest sampling serial number"][indexPath.row];id v=self.run.store.latest[key];c.detailTextLabel.text=v?[v description]:@"Not tested";}
 return c;
}
- (void)toggle:(UISwitch *)sender{
 if(sender.on){if(![self.run start])sender.on=NO;}else [self.run stop:@"user_stop"];[self refresh];
}
- (void)share{
 if(!self.run.reportDirectory){UIAlertController *a=[UIAlertController alertControllerWithTitle:@"No Reports Yet" message:@"After the collection is turned on, the sampling or failure reasons will be automatically saved." preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];[self presentViewController:a animated:YES completion:nil];return;}
 NSURL *dir=[[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES]URLByAppendingPathComponent:[@"TurboDiagnostics-" stringByAppendingString:NSUUID.UUID.UUIDString] isDirectory:YES];NSFileManager *fm=NSFileManager.defaultManager;NSError *error=nil;
 if(![fm createDirectoryAtURL:dir withIntermediateDirectories:NO attributes:@{NSFilePosixPermissions:@0700} error:&error])return;
 NSURL *json=[dir URLByAppendingPathComponent:@"diagnostics.json"],*md=[dir URLByAppendingPathComponent:@"diagnostics.md"];
 if(![[self.run reportJSON]writeToURL:json options:NSDataWritingWithoutOverwriting error:&error]||![[self.run reportMarkdown]writeToURL:md atomically:YES encoding:NSUTF8StringEncoding error:&error]){[fm removeItemAtURL:dir error:nil];return;}
 for(NSURL *f in @[json,md])[fm setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:f.path error:nil];
 UIActivityViewController *a=[[UIActivityViewController alloc]initWithActivityItems:@[json,md] applicationActivities:nil];a.popoverPresentationController.barButtonItem=self.navigationItem.rightBarButtonItem;
 a.completionWithItemsHandler=^(UIActivityType type,BOOL completed,NSArray *items,NSError *failure){(void)type;(void)completed;(void)items;(void)failure;[fm removeItemAtURL:dir error:nil];};[self presentViewController:a animated:YES completion:nil];
}
@end
UIViewController *TDPhoneController(TDPhoneRun *run){
 TDPanel *p=[[TDPanel alloc]initWithStyle:UITableViewStyleInsetGrouped];p.run=run;return p;
}
