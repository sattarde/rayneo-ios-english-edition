#import "NavigationPlaces.h"
#import <MapKit/MapKit.h>
static NSString *const RecentKey=@"io.turboio.navigation.recent.v1";
@interface TIONavPlacePanel:UITableViewController<UISearchBarDelegate>
@property(copy) void(^selection)(NSDictionary *);
@property UISearchBar *bar;
@property UITextField *city;
@property UILabel *hint;
@property UIButton *submitButton;
@property UIStackView *headerStack;
@property NSArray<NSDictionary *> *places;
@property(nonatomic) BOOL searching;
@property NSUInteger generation;
@property MKLocalSearch *search;
@end
@implementation TIONavPlacePanel
- (void)recordSearch:(NSString *)phase code:(NSInteger)code count:(NSUInteger)count{
    NSString *dir=[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/TurboIOResearch/navigation"];
    [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:@{NSFileProtectionKey:NSFileProtectionCompleteUntilFirstUserAuthentication} error:nil];
    NSDictionary *value=@{@"version":@"navigation-interaction-v4",@"phase":phase,@"code":@(code),@"resultCount":@(count),@"time":@(NSDate.date.timeIntervalSince1970)};
    [[NSJSONSerialization dataWithJSONObject:value options:0 error:nil] writeToFile:[dir stringByAppendingPathComponent:@"search.json"] options:NSDataWritingAtomic|NSDataWritingFileProtectionCompleteUntilFirstUserAuthentication error:nil];
}
- (void)viewDidLoad{[super viewDidLoad];self.title=@"Search Destination";self.tableView.backgroundColor=UIColor.systemGroupedBackgroundColor;
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc]initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(close)];
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc]initWithTitle:@"Clear Recent" style:UIBarButtonItemStylePlain target:self action:@selector(clearRecent)];
    self.tableView.keyboardDismissMode=UIScrollViewKeyboardDismissModeOnDrag;
    UIView *header=[[UIView alloc]initWithFrame:CGRectMake(0,0,360,220)];self.bar=[UISearchBar new];self.bar.placeholder=@"Location, address, coffee shop…";self.bar.delegate=self;self.bar.searchBarStyle=UISearchBarStyleMinimal;self.bar.accessibilityIdentifier=@"navigation-place-query";self.bar.returnKeyType=UIReturnKeySearch;
    self.city=[UITextField new];self.city.placeholder=@"City (Optional, e.g. London, San Francisco)";self.city.borderStyle=UITextBorderStyleRoundedRect;self.city.clearButtonMode=UITextFieldViewModeWhileEditing;self.city.accessibilityIdentifier=@"navigation-search-city";
    [self.city addTarget:self action:@selector(cityChanged) forControlEvents:UIControlEventEditingChanged];[self.city addTarget:self action:@selector(submitSearch) forControlEvents:UIControlEventEditingDidEndOnExit];self.city.returnKeyType=UIReturnKeySearch;
    self.submitButton=[UIButton buttonWithType:UIButtonTypeSystem];UIButtonConfiguration *config=[UIButtonConfiguration filledButtonConfiguration];config.title=@"Search places";config.image=[UIImage systemImageNamed:@"magnifyingglass"];config.imagePadding=8;config.baseBackgroundColor=UIColor.systemTealColor;self.submitButton.configuration=config;self.submitButton.accessibilityIdentifier=@"navigation-search-submit";[self.submitButton.heightAnchor constraintGreaterThanOrEqualToConstant:44].active=YES;[self.submitButton addTarget:self action:@selector(submitSearch) forControlEvents:UIControlEventTouchUpInside];
    self.hint=[UILabel new];self.hint.text=@"Recently selected · Saved locally";self.hint.font=[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];self.hint.textColor=UIColor.secondaryLabelColor;self.hint.numberOfLines=2;
    UIStackView *s=[[UIStackView alloc]initWithArrangedSubviews:@[self.bar,self.city,self.submitButton,self.hint]];self.headerStack=s;s.axis=UILayoutConstraintAxisVertical;s.spacing=8;s.translatesAutoresizingMaskIntoConstraints=NO;[header addSubview:s];[NSLayoutConstraint activateConstraints:@[[s.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:16],[s.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-16],[s.topAnchor constraintEqualToAnchor:header.topAnchor constant:6],[s.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-12],[self.city.heightAnchor constraintGreaterThanOrEqualToConstant:38]]];self.tableView.tableHeaderView=header;self.hint.numberOfLines=0;
    self.places=TIONavRecentPlaces([NSUserDefaults.standardUserDefaults arrayForKey:RecentKey],nil);
}
- (void)viewDidLayoutSubviews{[super viewDidLayoutSubviews];UIView *h=self.tableView.tableHeaderView;CGFloat width=self.tableView.bounds.size.width;CGFloat height=MAX(210,[h systemLayoutSizeFittingSize:CGSizeMake(width,UILayoutFittingCompressedSize.height) withHorizontalFittingPriority:UILayoutPriorityRequired verticalFittingPriority:UILayoutPriorityFittingSizeLevel].height);if(fabs(h.frame.size.height-height)>1||fabs(h.frame.size.width-width)>1){h.frame=CGRectMake(0,0,width,height);self.tableView.tableHeaderView=h;}}
- (void)setSearching:(BOOL)searching{_searching=searching;UIButtonConfiguration *c=self.submitButton.configuration;c.title=searching?@"Cancel search":@"Search places";c.showsActivityIndicator=searching;self.submitButton.configuration=c;}
- (void)submitSearch{if(self.searching){[self cancelSearch];self.hint.text=@"The search has been cancelled.";return;}[self searchBarSearchButtonClicked:self.bar];}
- (void)cityChanged{[self searchBar:self.bar textDidChange:self.bar.text];}
- (void)cancelSearch{if(self.searching)[self recordSearch:@"cancelled" code:0 count:0];self.generation++;self.searching=NO;[self.search cancel];self.search=nil;}
- (void)close{[self cancelSearch];[self dismissViewControllerAnimated:YES completion:nil];}
- (void)viewDidDisappear:(BOOL)animated{[super viewDidDisappear:animated];[self cancelSearch];}
- (void)clearRecent{UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Clear recent places?" message:@"Only the destination history on this phone is cleared." preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];[a addAction:[UIAlertAction actionWithTitle:@"Clear" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x){[NSUserDefaults.standardUserDefaults removeObjectForKey:RecentKey];[self cancelSearch];self.places=@[];self.hint.text=@"Recent places cleared";[self.tableView reloadData];}]];[self presentViewController:a animated:YES completion:nil];}
- (void)searchBar:(UISearchBar *)bar textDidChange:(NSString *)text{[self cancelSearch];self.places=@[];self.hint.text=@"Type a place name or address, then tap Search.";if(!text.length){self.places=TIONavRecentPlaces([NSUserDefaults.standardUserDefaults arrayForKey:RecentKey],nil);self.hint.text=@"Recently selected · Saved locally";}[self.tableView reloadData];}
- (void)searchBarSearchButtonClicked:(UISearchBar *)bar{
    NSString *q=[bar.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];if(!q.length||q.length>120){self.hint.text=@"Please enter a location name of 1-120 characters";return;}[self.view endEditing:YES];[self cancelSearch];self.places=@[];[self.tableView reloadData];
    self.searching=YES;[self recordSearch:@"searching" code:0 count:0];self.hint.text=@"Searching for locations…";
    MKLocalSearchRequest *r=[MKLocalSearchRequest new];
    NSString *city=[self.city.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    r.naturalLanguageQuery=city.length?[NSString stringWithFormat:@"%@, %@",q,city]:q;
    self.search=[[MKLocalSearch alloc]initWithRequest:r];NSUInteger g=self.generation;__weak typeof(self) weak=self;
    [self.search startWithCompletionHandler:^(MKLocalSearchResponse *response,NSError *error){
        dispatch_async(dispatch_get_main_queue(),^{
            TIONavPlacePanel *s=weak;if(!s||s.generation!=g||!s.searching)return;
            s.searching=NO;s.search=nil;
            if(error||!response.mapItems.count){
                [s recordSearch:@"failed" code:error.code count:0];
                s.hint.text=error?[NSString stringWithFormat:@"Search failed: %@",error.localizedDescription]:@"No locations found. Try a different name.";
                [s.tableView reloadData];return;
            }
            NSMutableArray *rows=[NSMutableArray new];
            for(MKMapItem *item in response.mapItems){
                CLLocationCoordinate2D c=item.placemark.coordinate;
                NSString *name=item.name?:@"";
                NSString *addr=item.placemark.title.length?item.placemark.title:(item.placemark.thoroughfare.length?[NSString stringWithFormat:@"%@, %@",item.placemark.thoroughfare?:@"",item.placemark.locality?:@""]:[NSString stringWithFormat:@"%.5f, %.5f",c.latitude,c.longitude]);
                NSDictionary *p=TIONavPlace(@{@"name":name,@"address":addr,@"lat":@(c.latitude),@"lon":@(c.longitude)});
                if(p)[rows addObject:p];if(rows.count>=20)break;
            }
            s.places=rows;[s recordSearch:@"completed" code:0 count:rows.count];
            s.hint.text=rows.count?@"MapKit search results · Select destination:":@"No locations found";
            [s.tableView reloadData];
        });
    }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,15*NSEC_PER_SEC),dispatch_get_main_queue(),^{if(g==self.generation&&self.searching){[self cancelSearch];[self recordSearch:@"timeout" code:0 count:0];self.hint.text=@"The search timed out. Check network or tap on map to pick a point.";}});
}
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section{return self.places.count;}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)ip{UITableViewCell *c=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];NSDictionary *p=self.places[ip.row];c.textLabel.text=p[@"name"];c.textLabel.numberOfLines=2;c.detailTextLabel.text=p[@"address"];c.detailTextLabel.numberOfLines=3;c.imageView.image=[UIImage systemImageNamed:@"mappin.circle.fill"];c.imageView.tintColor=UIColor.systemTealColor;c.accessoryType=UITableViewCellAccessoryDisclosureIndicator;return c;}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)ip{NSDictionary *p=TIONavPlace(self.places[ip.row]);if(!p)return;[self cancelSearch];[NSUserDefaults.standardUserDefaults setObject:TIONavRecentPlaces([NSUserDefaults.standardUserDefaults arrayForKey:RecentKey],p) forKey:RecentKey];void(^callback)(NSDictionary *)=self.selection;[self dismissViewControllerAnimated:YES completion:^{if(callback)callback(p);}];}
@end
UIViewController *TIONavPlacePicker(void(^selection)(NSDictionary *)){TIONavPlacePanel *p=[[TIONavPlacePanel alloc]initWithStyle:UITableViewStyleInsetGrouped];p.selection=selection;return [[UINavigationController alloc]initWithRootViewController:p];}
