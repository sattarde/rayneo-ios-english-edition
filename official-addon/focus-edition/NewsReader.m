#import "NewsReader.h"
#import "NewsTeleprompter.h"
#import "NewsPresentation.h"
#import "ResearchUI.h"
#import "NewsSpeed.h"
#import "NewsArchive.h"
#import <UIKit/UIKit.h>
static TIONewsFetch Fetch;
static void NewsAlert(UIViewController *owner,NSString *title,NSString *message){
    UIAlertController *a=[UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [owner presentViewController:a animated:YES completion:nil];
}
@interface TIONewsArticle:UIViewController
@property(nonatomic,copy) NSString *body;
@property(nonatomic,copy) NSString *(^sendNews)(void);
@end
@implementation TIONewsArticle
- (void)viewDidLoad{
    [super viewDidLoad];self.title=@"Loaded · Full Article";
    UITextView *text=[UITextView new];text.editable=NO;text.dataDetectorTypes=UIDataDetectorTypeLink;text.text=self.body;text.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody];text.adjustsFontForContentSizeCategory=YES;text.backgroundColor=TIOPaper();text.textColor=TIOInk();text.tintColor=TIOAccent();text.textContainerInset=UIEdgeInsetsMake(20,18,24,18);text.accessibilityIdentifier=@"news-loaded-body";self.view=text;
    UIBarButtonItem *send=[[UIBarButtonItem alloc]initWithTitle:@"Send to Glasses" style:UIBarButtonItemStylePlain target:self action:@selector(sendToGlasses)];send.accessibilityIdentifier=@"news-loaded-send";self.navigationItem.rightBarButtonItem=send;
}
- (void)sendToGlasses{NSString *message=self.sendNews?self.sendNews():@"News page closed. Please return and re-open.";NewsAlert(self,@"Send Status",message);}
@end
@interface TIONewsLibrary:UITableViewController
@property NSArray *items;
@property(nonatomic,copy) BOOL(^choose)(NSDictionary *);
@end
@implementation TIONewsLibrary
- (void)viewDidLoad{[super viewDidLoad];self.title=@"Saved News";TIOStyleResearchTable(self);self.items=TIONewsArchiveList();self.tableView.tableHeaderView=TIOFeatureHeader(self.items.count?@"Continue Reading":@"No Saved Articles",@"Articles are saved locally and preserved on exit.",@"reading");}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s{return self.items.count;}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip{NSDictionary *r=self.items[ip.row];UITableViewCell *c=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];NSDateFormatter *f=[NSDateFormatter new];f.dateFormat=@"MM-dd HH:mm";c.textLabel.text=[NSString stringWithFormat:@"%@ · %@",r[@"topic"],[f stringFromDate:[NSDate dateWithTimeIntervalSince1970:[r[@"createdAt"] doubleValue]]]];c.detailTextLabel.text=[NSString stringWithFormat:@"%@ chars · Reading offset %@ bytes · Tap to load",r[@"characters"],r[@"offset"]];c.detailTextLabel.numberOfLines=0;c.accessoryType=UITableViewCellAccessoryDisclosureIndicator;return c;}
- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s{return @"Full text saved locally. Load to view or re-send from beginning.";}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip{
    [t deselectRowAtIndexPath:ip animated:YES];
    NSDictionary *r=ip.row<self.items.count?TIONewsArchiveLoad(self.items[ip.row][@"id"]):nil;
    if(!r){NewsAlert(self,@"Unable to Load Article",@"Local article cannot be read. Please return and try again.");return;}
    if(!self.choose||!self.choose(r))NewsAlert(self,@"Article Not Opened",@"News page closed. Please return and try again.");
}
@end
@interface TIONewsReader:UITableViewController
@property(nonatomic) BOOL enabled,busy,autoStart,showDetails,refreshQueued;
@property NSMutableIndexSet *expanded;
@property(nonatomic) NSUInteger generation;
@property(nonatomic) NSInteger speed;
@property(nonatomic) NSString *topic,*text,*status;
@property(nonatomic) NSTimer *refresh;
@property(nonatomic,copy) TIONewsCancel cancelFetch;
@property(nonatomic) NSString *archiveID,*readingArchiveID;
@property(nonatomic) NSUInteger savedCount,readOffset;
@property(nonatomic) NSTimeInterval progressSavedAt;
@end
static TIONewsReader *Reader;
void TIONewsConfigure(TIONewsFetch fetch){Fetch=[fetch copy];}
@implementation TIONewsReader
- (instancetype)init{if((self=[super initWithStyle:UITableViewStyleInsetGrouped])){_topic=TIONewsTopic([NSUserDefaults.standardUserDefaults stringForKey:@"io.turboio.news.topic"])?:@"AI";_status=@"Off · TinyFish fetches news, teleprompter reads steadily";_text=@"";_speed=TIONewsLoadSpeed(NSUserDefaults.standardUserDefaults);if(![NSUserDefaults.standardUserDefaults boolForKey:@"io.turboio.news.legacyImported"]){TIONewsArchiveImportLegacy();[NSUserDefaults.standardUserDefaults setBool:YES forKey:@"io.turboio.news.legacyImported"];}NSArray *saved=TIONewsArchiveList();_savedCount=saved.count;NSString *last=[NSUserDefaults.standardUserDefaults stringForKey:@"io.turboio.news.lastArchive"];NSDictionary *r=TIONewsArchiveLoad(last)?:TIONewsArchiveLoad(saved.firstObject[@"id"]);if(r){_text=r[@"text"];_archiveID=r[@"id"];_status=@"Restored local article; ready to view or re-send";}[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(teleChanged) name:@"TIONewsTeleChanged" object:nil];}return self;}
- (void)viewDidLoad{[super viewDidLoad];self.title=@"News";self.expanded=[NSMutableIndexSet indexSetWithIndex:1];TIOStyleResearchTable(self);self.tableView.tableHeaderView=TIOFeatureHeader(@"Essential News First",@"Select a topic, save locally, then send to glasses.",@"news");}
- (void)viewWillAppear:(BOOL)animated{[super viewWillAppear:animated];[self.tableView reloadData];}
- (void)teleChanged{NSDictionary *s=TIONewsTeleStatus();if([s[@"active"]boolValue])[self.expanded addIndex:2];if(_readingArchiveID.length){BOOL active=[s[@"active"] boolValue];if(active)_readOffset=[s[@"offset"] unsignedIntegerValue];NSTimeInterval now=NSProcessInfo.processInfo.systemUptime;if(!active||now-_progressSavedAt>=3){TIONewsArchiveProgress(_readingArchiveID,_readOffset);_progressSavedAt=now;}if(!active)_readingArchiveID=nil;}if(_autoStart&&[s[@"ready"] boolValue]){_autoStart=NO;TIONewsTeleControl(3,_speed);}if(_autoStart&&![s[@"active"] boolValue]){_autoStart=NO;_status=s[@"state"];}if(!_refreshQueued){_refreshQueued=YES;dispatch_after(dispatch_time(DISPATCH_TIME_NOW,200*NSEC_PER_MSEC),dispatch_get_main_queue(),^{self.refreshQueued=NO;if(self.isViewLoaded&&self.view.window)[self.tableView reloadData];});}}
- (void)stop{_enabled=NO;_busy=NO;_autoStart=NO;++_generation;if(_cancelFetch)_cancelFetch();_cancelFetch=nil;[_refresh invalidate];_refresh=nil;TIONewsTeleControl(6,_speed);_status=@"Stopped news updates; teleprompter exit requested, text kept";[self.tableView reloadData];}
- (void)toggle:(UISwitch *)sender{if(sender.on){_enabled=YES;[self fetch];}else [self stop];}
- (void)fetch{
    __weak typeof(self) timerOwner=self;
    // Enabling automatic updates during a manually-started reading must still
    // schedule the next cycle; never show an enabled switch without a timer.
    if(_enabled&&!_refresh)_refresh=[NSTimer scheduledTimerWithTimeInterval:600 repeats:YES block:^(NSTimer *t){if(![TIONewsTeleStatus()[@"active"] boolValue])[timerOwner fetch];}];
    if(_busy)return;if([TIONewsTeleStatus()[@"active"] boolValue]){_status=_enabled?@"Auto update on; fetches in next cycle after current exit":@"Please exit current teleprompter session before updating";[self.tableView reloadData];return;}
    if(!Fetch){[self stop];_status=@"News service not configured";return;}_busy=YES;NSUInteger token=++_generation;_status=@"Searching news via TinyFish…";[self.tableView reloadData];__weak typeof(self) weak=self;
    _cancelFetch=Fetch(TIONewsPrompt(_topic,NSDate.date),^(NSString *text,NSString *error){typeof(self) self=weak;if(!self||token!=self.generation)return;self.busy=NO;self.cancelFetch=nil;
        if(error){self.status=error;[self.tableView reloadData];return;}
        if(!TIONewsPages(text).count){self.status=@"News is empty or exceeds 12,000 characters";[self.tableView reloadData];return;}
        self.text=[text stringByReplacingOccurrencesOfString:@"Searching web…" withString:@""];if(![self saveCurrentNews]){self.status=@"News fetched, but local save failed or limit reached.";[self.tableView reloadData];return;}if([TIONewsTeleStatus()[@"available"] boolValue]){self.status=@"News saved, preparing teleprompter";[self prepare];}else{self.status=@"News saved locally; connect glasses before sending.";[self.tableView reloadData];}
    });
}
- (void)prepare{
    if(!_text.length){_status=@"Please fetch news first or use synthetic test";[self.tableView reloadData];return;}
    NSString *body=TIONewsManuscript(_text);
    if(_busy||![TIONewsPresentation(TIONewsTeleStatus(),_busy,_text.length)[@"canSend"] boolValue])return;
    if(![self saveCurrentNews]){_status=@"Local save failed; phone text still viewable";[self.tableView reloadData];return;}
    _autoStart=YES;_readingArchiveID=_archiveID;_readOffset=0;
    if(!TIONewsTelePrepare(body,_speed)){_autoStart=NO;_readingArchiveID=nil;_status=@"Article readable on phone; teleprompter not ready";}
    else _status=@"Article transfer requested; starts after confirmation";[self.tableView reloadData];
}
- (BOOL)saveCurrentNews{NSDictionary *existing=TIONewsArchiveLoad(_archiveID);NSDictionary *r=[existing[@"text"] isEqual:_text]?existing:TIONewsArchiveSave(_topic,_text);if(!r)return NO;_archiveID=r[@"id"];_savedCount=TIONewsArchiveList().count;[NSUserDefaults.standardUserDefaults setObject:_archiveID forKey:@"io.turboio.news.lastArchive"];return YES;}
- (void)showCurrentArticleInNavigation:(UINavigationController *)navigation{
    TIONewsArticle *article=[TIONewsArticle new];article.body=_text;
    // Capture the displayed article, not mutable Reader text which an automatic
    // refresh could replace while this detail remains visible.
    NSString *body=[_text copy],*ident=[_archiveID copy];__weak typeof(self) weak=self;
    article.sendNews=^NSString *{
        typeof(self) self=weak;if(!self)return @"News page closed. Please return and try again.";
        NSDictionary *s=TIONewsTeleStatus();
        if(self.busy)return @"Fetching another batch, please wait.";
        if([s[@"active"] boolValue])return @"Teleprompter active; tap 'Stop & Exit' before sending this.";
        if(![s[@"available"] boolValue])return @"Glasses not connected; text saved, try again after connecting.";
        self.text=body;self.archiveID=ident;[self prepare];return self.status?:@"Please return to News tab to view send status.";
    };
    [navigation pushViewController:article animated:YES];
}
- (NSArray *)rows{BOOL needs=[TIONewsPresentation(TIONewsTeleStatus(),_busy,_text.length)[@"needsPreparation"] boolValue];return @[needs?@[@8,@10]:@[@8],@[@1,@2],@[@3,@4,@5,@6,@7,@13],@[@0],_showDetails?@[@11,@12,@9]:@[@11]];}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)t{return self.rows.count;}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s{if(s==0&&![self.expanded containsIndex:s])return 1;return [self.expanded containsIndex:s]?[self.rows[s] count]:0;}
- (UIView *)tableView:(UITableView *)t viewForHeaderInSection:(NSInteger)s{__weak typeof(self) w=self;return TIOFoldHeader(@[@"Connection Status",@"Topic",@"Reading & Saved Articles",@"Auto Updates",@"Diagnostics"][s],[self.expanded containsIndex:s],^{if([w.expanded containsIndex:s])[w.expanded removeIndex:s];else [w.expanded addIndex:s];[w.tableView reloadData];});}
- (CGFloat)tableView:(UITableView *)t heightForHeaderInSection:(NSInteger)s{return 54;}
- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s{if(![self.expanded containsIndex:s]||s==1)return nil;if(s==3)return @"Attempts updates every 10 min. Tap 'Exit & Stop' to stop teleprompter.";return nil;}
- (BOOL)enabledRow:(NSInteger)row{NSDictionary *s=TIONewsTeleStatus(),*p=TIONewsPresentation(s,_busy,_text.length);if(row==2)return [p[@"canFetch"] boolValue];if(row==3)return [p[@"canSend"] boolValue];if(row==4)return [p[@"canPlay"] boolValue];if(row==5)return [p[@"canStop"] boolValue]||_busy||_enabled;if(row==6)return ![s[@"active"] boolValue]||[s[@"ready"] boolValue];if(row==7)return _text.length>0;if(row==9)return [p[@"canTest"] boolValue];if(row==13)return _savedCount>0&&!_busy&&![s[@"active"] boolValue];return YES;}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip{
    NSInteger row=[self.rows[ip.section][ip.row] integerValue];NSDictionary *s=TIONewsTeleStatus(),*p=TIONewsPresentation(s,_busy,_text.length);UITableViewCell *c=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];c.detailTextLabel.numberOfLines=0;c.textLabel.numberOfLines=0;c.textLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody];c.detailTextLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];c.textLabel.adjustsFontForContentSizeCategory=c.detailTextLabel.adjustsFontForContentSizeCategory=YES;c.detailTextLabel.textColor=UIColor.secondaryLabelColor;c.accessoryType=UITableViewCellAccessoryDisclosureIndicator;c.contentView.directionalLayoutMargins=NSDirectionalEdgeInsetsMake(14,16,14,16);c.accessibilityIdentifier=[NSString stringWithFormat:@"news-action-%ld",(long)row];
    c.textLabel.text=@[@"Auto Update & Send",[@"Topic · " stringByAppendingString:_topic],_busy?@"Fetching…":([s[@"available"] boolValue]?@"Fetch News & Send":@"Fetch News"),@"Send to Glasses",[s[@"playing"] boolValue]?@"Pause Reading":@"Start / Resume Reading",@"Exit & Stop",@"Scroll Speed",@"View Full Text & Sources",p[@"title"],@"Synthetic Test Article (Offline)",@"Return to Official App to Prepare",_showDetails?@"Hide Experimental Tools":@"Show Experimental Tools",@"Protocol Details",@"Saved News"][row];
    if(row==0){UISwitch *v=[UISwitch new];v.on=_enabled;v.enabled=!_busy||_enabled;v.accessibilityLabel=@"Auto Update & Send News";[v addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventValueChanged];c.accessoryView=v;c.detailTextLabel.text=@"Manual fetch does not toggle this switch";}
    if(row==2){c.detailTextLabel.text=_status;c.imageView.image=[UIImage systemImageNamed:@"arrow.clockwise"];}
    if(row==3){c.detailTextLabel.text=[p[@"canSend"] boolValue]?@"Starts automatically after acknowledgment":@"Requires fetched news, ready teleprompter, and no active article";c.imageView.image=[UIImage systemImageNamed:@"paperplane"];}
    if(row==4)c.imageView.image=[UIImage systemImageNamed:[s[@"playing"] boolValue]?@"pause.circle":@"play.circle"];
    if(row==5){c.imageView.image=[UIImage systemImageNamed:@"stop.circle"];c.textLabel.textColor=UIColor.systemRedColor;}
    if(row==6)c.detailTextLabel.text=[NSString stringWithFormat:@"%ld%@ · Customizable, remembered automatically",(long)_speed,_speed>360?@" (High Speed Experimental)":@""];
    if(row==7)c.detailTextLabel.text=_text.length?[NSString stringWithFormat:@"%lu chars · Source links kept on phone",(unsigned long)_text.length]:@"No news yet; fetch content first";
    if(row==13){c.detailTextLabel.text=[NSString stringWithFormat:@"%lu articles · Saved locally, re-open and send anytime",(unsigned long)_savedCount];c.imageView.image=[UIImage systemImageNamed:@"books.vertical"];}
    if(row==8){c.textLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];c.detailTextLabel.text=![self.expanded containsIndex:0]&&[p[@"needsPreparation"]boolValue]?@"Connection status & initial setup instructions; tap above to expand.":p[@"detail"];c.accessoryType=UITableViewCellAccessoryNone;c.selectionStyle=UITableViewCellSelectionStyleNone;if([p[@"needsPreparation"] boolValue])c.backgroundColor=[UIColor.systemOrangeColor colorWithAlphaComponent:0.10];}
    if(row==12){c.detailTextLabel.text=[NSString stringWithFormat:@"%@\nReady to transmit: %@ · Response: %@ · Byte offset: %@",s[@"state"],[s[@"available"] boolValue]?@"Yes":@"No",s[@"prepareReplies"],s[@"offset"]];c.accessoryType=UITableViewCellAccessoryNone;}
    BOOL enabled=[self enabledRow:row];c.textLabel.textColor=enabled?(row==5?UIColor.systemRedColor:UIColor.labelColor):UIColor.tertiaryLabelColor;c.imageView.tintColor=enabled?UIColor.systemIndigoColor:UIColor.tertiaryLabelColor;if(!enabled){c.accessoryType=UITableViewCellAccessoryNone;c.selectionStyle=UITableViewCellSelectionStyleNone;c.accessibilityTraits|=UIAccessibilityTraitNotEnabled;}return c;
}
- (void)editTopic{UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Topic" message:@"Enter public news topics only; do not enter personal data or keys." preferredStyle:UIAlertControllerStyleAlert];[a addTextFieldWithConfigurationHandler:^(UITextField *f){f.text=self.topic;}];[a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];[a addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){NSString *s=TIONewsTopic(a.textFields.firstObject.text);if(!s)return;[self stop];self.topic=s;self.text=@"";[NSUserDefaults.standardUserDefaults setObject:s forKey:@"io.turboio.news.topic"];[self.tableView reloadData];}]];[self presentViewController:a animated:YES completion:nil];}
- (void)applySpeed:(NSInteger)value{
    if(!TIONewsSaveSpeed(NSUserDefaults.standardUserDefaults,value))return;
    _speed=value;NSDictionary *s=TIONewsTeleStatus();
    BOOL submitted=[s[@"ready"] boolValue]&&![s[@"stopping"] boolValue]&&![s[@"manual"] boolValue]&&TIONewsTeleControl(7,value);
    _status=[NSString stringWithFormat:@"Speed %ld saved; %@",(long)value,submitted?@"Submitted to glasses, actual speed determined by glasses":@"Will be used on next send"];
    [self.tableView reloadData];
}
- (void)editCustomSpeed{
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Custom Scroll Speed" message:@"Enter integer 60–1200. Higher values scroll faster." preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *f){f.text=[NSString stringWithFormat:@"%ld",(long)self.speed];f.keyboardType=UIKeyboardTypeNumberPad;f.placeholder=@"e.g. 480 or 600";f.accessibilityLabel=@"Custom News Scroll Speed";[f addTarget:self action:@selector(customSpeedChanged:) forControlEvents:UIControlEventEditingChanged];}];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    __weak UIAlertController *weakAlert=a;UIAlertAction *save=[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){NSNumber *n=TIONewsSpeedInput(weakAlert.textFields.firstObject.text);if(n)[self applySpeed:n.integerValue];}];save.enabled=TIONewsSpeedInput(a.textFields.firstObject.text)!=nil;[a addAction:save];[self presentViewController:a animated:YES completion:nil];
}
- (void)customSpeedChanged:(UITextField *)field{UIAlertController *a=(id)self.presentedViewController;if([a isKindOfClass:UIAlertController.class])a.actions.lastObject.enabled=TIONewsSpeedInput(field.text)!=nil;}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip{
    [t deselectRowAtIndexPath:ip animated:YES];
    NSInteger row=[self.rows[ip.section][ip.row] integerValue];if(![self enabledRow:row])return;ip=[NSIndexPath indexPathForRow:row inSection:0];
    if(row==10){TIOCloseResearch(self);return;}
    if(row==11){_showDetails=!_showDetails;[self.tableView reloadData];return;}
    if(row==13){TIONewsLibrary *library=[[TIONewsLibrary alloc]initWithStyle:UITableViewStyleInsetGrouped];__weak typeof(self) weak=self;__weak UINavigationController *navigation=self.navigationController;library.choose=^BOOL(NSDictionary *r){typeof(self) self=weak;UINavigationController *nav=navigation;if(!self||!nav)return NO;self.text=r[@"text"];self.archiveID=r[@"id"];[NSUserDefaults.standardUserDefaults setObject:self.archiveID forKey:@"io.turboio.news.lastArchive"];self.status=@"Loaded local news; tap send to transmit to glasses";[self.tableView reloadData];[self showCurrentArticleInNavigation:nav];return YES;};[self.navigationController pushViewController:library animated:YES];return;}
    if(ip.row==1)[self editTopic];if(ip.row==2)[self fetch];if(ip.row==3)[self prepare];
    if(ip.row==4){_autoStart=NO;unsigned command=TIONewsPlaybackCommand(TIONewsTeleStatus());if(command)TIONewsTeleControl(command,_speed);}
    if(ip.row==5)[self stop];
    if(ip.row==6)[self editCustomSpeed];
    if(ip.row==7)[self showCurrentArticleInNavigation:self.navigationController];
    if(ip.row==8)[self.tableView reloadData];
    if(ip.row==9){if(_busy||[TIONewsTeleStatus()[@"active"] boolValue])return;_text=[NSString stringWithFormat:@"News Teleprompter Test %@\nThis is a synthetic test article, not live news.\nPart 1: Verify full text display and steady scrolling.\nPart 2: Verify pause, resume, and exit.\nPart 3: No live captions or audio capture started.\nTest complete, checksum 7392.",[NSUUID.UUID.UUIDString substringToIndex:4]];[self prepare];}
}
@end
void TIOOpenNewsReader(id parent){
    if(![parent isKindOfClass:UIViewController.class])return;UIViewController *source=parent;
    // The news singleton is already owned by its tab. Never reparent it into
    // the model tab, which breaks the flat detail navigation and back route.
    for(UIViewController *v in source.tabBarController.viewControllers){
        if([v isKindOfClass:UINavigationController.class]&&[[(UINavigationController *)v viewControllers].firstObject isKindOfClass:TIONewsReader.class]){source.tabBarController.selectedViewController=v;[(UINavigationController *)v popToRootViewControllerAnimated:NO];return;}
    }
    [source.navigationController pushViewController:[TIONewsReader new] animated:YES];
}
id TIONewsReaderController(void){if(!Reader)Reader=[TIONewsReader new];return Reader;}
