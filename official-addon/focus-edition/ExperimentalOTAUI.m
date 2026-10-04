#import "ExperimentalOTAUI.h"
#import "ExperimentalOTA.h"
#import "ExperimentalOTAFeed.h"
#import "ExperimentalOTAGuard.h"
#import "ExperimentalOTAFlash.h"
#import "ResearchUI.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface TIOExperimentalOTAPage:UITableViewController<UIDocumentPickerDelegate>
@property(nonatomic,copy) NSString *statusText;
@property(nonatomic) BOOL busy;
@property(nonatomic,copy) NSString *directoryStatus;
@end
static NSURL *StoreDirectory(void){return [NSURL fileURLWithPath:[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/TurboIOPrivateAddon/ExperimentalOTA"] isDirectory:YES];}
@implementation TIOExperimentalOTAPage
- (void)viewDidLoad{
    [super viewDidLoad];self.title=@"TFP1 Firmware Update (FOCUS-04)";self.statusText=@"No ZIP selected. Will not send anything.";self.directoryStatus=@"Not checked.";TIOStyleResearchTable(self);
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc]initWithTitle:@"Refresh" style:UIBarButtonItemStylePlain target:self action:@selector(refresh)];
    NSURL *file=[StoreDirectory() URLByAppendingPathComponent:[TIOExperimentalOTASHA() stringByAppendingString:@".zip"]];
    if(![NSFileManager.defaultManager fileExistsAtPath:file.path]){
        NSURL *bundled=[NSBundle.mainBundle URLForResource:@"TurboWeReadCandidate" withExtension:@"zip"];
        if(bundled){self.busy=YES;self.statusText=@"Verifying built-in TFP1...";
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{NSError *e=nil;BOOL ok=TIOImportExperimentalOTA(bundled,StoreDirectory(),&e)!=nil;
                dispatch_async(dispatch_get_main_queue(),^{self.busy=NO;self.statusText=ok?@"TFP1 Candidate verified. Not authorized yet.":e.localizedDescription;[self.tableView reloadData];});});return;}
    }
    if([NSFileManager.defaultManager fileExistsAtPath:file.path]){self.busy=YES;self.statusText=@"Re-verifying saved TFP1...";dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{NSError *error=nil;BOOL ok=TIOReadExperimentalOTA(file,&error)!=nil;dispatch_async(dispatch_get_main_queue(),^{self.busy=NO;self.statusText=ok?@"TFP1 verified locally.\nNot sent to glasses yet.":@"Copy validation failed.";[self.tableView reloadData];});});}
}
- (void)refresh{TIORefreshExperimentalOTAReport();[self.tableView reloadData];}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView{return 4;}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section{return section==2&&TIOOTAFlashBuild()?5:(section==2&&TIOOTAPreparationBuild()?3:(section==0||section==3?2:1));}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section{return @[@"Local Package",@"Changes",@"Official Upgrade",@"Directory Check"][section];}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path{
    UITableViewCell *cell=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];TIOStyleResearchCell(cell);
    if(path.section==0&&path.row==0){cell.textLabel.text=self.busy?@"Verifying...":@"Select TFP1 ZIP";cell.detailTextLabel.text=@"Import from Files (SHA-256 verified)";cell.imageView.image=[UIImage systemImageNamed:@"doc.badge.plus"];cell.accessibilityIdentifier=@"experimental-ota-import";}
    else if(path.section==0){cell.textLabel.text=@"Local Status";cell.detailTextLabel.text=self.statusText;cell.accessibilityIdentifier=@"experimental-ota-status";}
    else if(path.section==1){cell.textLabel.text=@"AP Payload Modified";cell.detailTextLabel.text=@"Strix OS 1.0.4.12 TFP1. Adds Pomodoro timer, WeRead, Music apps. USE AT YOUR OWN RISK.";}
    else if(path.section==2){NSDictionary *feed=TIOExperimentalOTAFeedStatus(),*guard=TIOOTAGuardStatus();
        if(path.row==3){cell.textLabel.text=@"Start TFP1 Flash (Authorize)";cell.detailTextLabel.text=@"Tap this to authorize the OTA, then follow prompts.";cell.accessibilityIdentifier=@"experimental-ota-authorize-tfp1";}
        else if(path.row==4){cell.textLabel.text=@"Revoke Authorization";cell.detailTextLabel.text=@"Can only revoke before starting.";}
        else if(path.row==0&&TIOOTAFlashBuild()){NSDictionary *s=TIOOTAFlashStatus();cell.textLabel.text=@"DISPLAY TFP1";cell.detailTextLabel.text=[NSString stringWithFormat:@"Authorized: %@, Started: %@\nMatched: %@, Slices: %@\n%@",s[@"authorized"],s[@"started"],s[@"manifestMatched"],s[@"validatedSlices"],s[@"failure"]];}
        else if(path.row==1){cell.textLabel.text=@"Enable 15-min Download-Only Mode";cell.detailTextLabel.text=TIOOTAFlashBuild()?@"Provides fixed TFP1 download only; flashing requires separate confirmation.":@"Isolates firmware updates to local downloads only.";cell.accessibilityIdentifier=@"experimental-ota-prepare-only";}
        else if(path.row==2){cell.textLabel.text=@"Revoke Download Source";cell.detailTextLabel.text=@"Stops local update feed immediately.";cell.accessibilityIdentifier=@"experimental-ota-cancel";}
        else if(TIOOTAPreparationBuild()){cell.textLabel.text=@"PREPARE 02 · Flash Disabled";cell.detailTextLabel.text=[NSString stringWithFormat:@"Isolation hook: %@; %@ sends blocked \n Source open: %@ · Firmware Query %@ · App Query %@ · Download %@\n This is a Download Only build, there is no entry to release send isolation.",[guard[@"transportHookReady"] boolValue]?@"Installed":@"Not installed",guard[@"blockedCalls"],[feed[@"armed"] boolValue]?@"yes":@"no",feed[@"firmwareQueries"]?:@0,feed[@"appQueries"]?:@0,feed[@"downloadRequests"]?:@0];cell.accessibilityIdentifier=@"experimental-ota-preparation-status";}
        else{cell.textLabel.text=@"Flashing Gate Closed";cell.detailTextLabel.text=[feed[@"running"] boolValue]?[NSString stringWithFormat:@"The native upgrade source is started and only returns \"No updates\". %@ inquiries received. \n The cache and official host of the same version are yet to be accepted; compilation access control prohibits the provision of experimental packages. Not sent to glasses.",feed[@"queryCount"]]:@"The native upgrade source component has been compiled and the current package does not have experimental routing enabled. The official schedule is yet to be accepted. \n does not overwrite the official cache, does not modify the same version upgrade switch, and does not send it to the glasses.";cell.accessibilityIdentifier=@"experimental-ota-not-connected";}}
    else if(path.row==0){cell.textLabel.text=self.busy?@"Verifying...":@"Verify Extracted Directory";cell.detailTextLabel.text=@"Verify 14 files against manifest; stock package will not be treated as TFP1";cell.accessibilityIdentifier=@"experimental-ota-check-directory";}
    else{cell.textLabel.text=@"Directory Snapshot Status";cell.detailTextLabel.text=self.directoryStatus;cell.accessibilityIdentifier=@"experimental-ota-directory-status";}
    cell.selectionStyle=(((path.section==0||path.section==3)&&path.row==0)||(path.section==2&&path.row>0))&&!self.busy?UITableViewCellSelectionStyleDefault:UITableViewCellSelectionStyleNone;return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path{
    [tableView deselectRowAtIndexPath:path animated:YES];if(self.busy)return;
    if(path.section==2&&path.row==4&&TIOOTAFlashBuild()){self.statusText=TIOOTAFlashCancel()?@"Pending authorization revoked":@"Session in progress; keep connected and powered";[self refresh];return;}
    if(path.section==2&&path.row==3&&TIOOTAFlashBuild()){
        UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Authorize TFP1 Flash Session" message:@"Flashing custom firmware carries risk of bricking. Confirm battery is full and no other tasks are running. Type TFP1 to authorize, then go to the official firmware update screen to install." preferredStyle:UIAlertControllerStyleAlert];
        [a addTextFieldWithConfigurationHandler:^(UITextField *f){f.placeholder=@"TFP1";f.autocapitalizationType=UITextAutocapitalizationTypeAllCharacters;f.autocorrectionType=UITextAutocorrectionTypeNo;}];
        [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [a addAction:[UIAlertAction actionWithTitle:@"Authorize Flash" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x){
            if(![a.textFields.firstObject.text isEqual:@"TFP1"]){
                UIAlertController *err = [UIAlertController alertControllerWithTitle:@"Invalid Text" message:@"You must type TFP1 exactly." preferredStyle:UIAlertControllerStyleAlert];
                [err addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
                [self presentViewController:err animated:YES completion:nil];
                return;
            }
            NSError *e=nil;BOOL ok=TIOOTAFlashAuthorize(&e);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if(ok){
                    self.statusText=@"TFP1 authorized! Return to the official RayNeo firmware update page and tap \"Start Install\".";
                    UIAlertController *suc = [UIAlertController alertControllerWithTitle:@"Flash Authorized!" message:@"Authorization granted for 15 minutes.\n\nPlease return to the official RayNeo update page and tap 'Start Install'." preferredStyle:UIAlertControllerStyleAlert];
                    [suc addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                    [self presentViewController:suc animated:YES completion:nil];
                }else{
                    self.statusText=e.localizedDescription?:@"Authorization failed.";
                    UIAlertController *err = [UIAlertController alertControllerWithTitle:@"Cannot Authorize Yet" message:self.statusText preferredStyle:UIAlertControllerStyleAlert];
                    [err addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
                    [self presentViewController:err animated:YES completion:nil];
                }
                [self refresh];
            });
        }]];[self presentViewController:a animated:YES completion:nil];return;
    }
    if(path.section==2&&path.row==2){TIOCancelExperimentalOTAPreparation();[self refresh];return;}
    if(path.section==2&&path.row==1){UIAlertController *confirm=[UIAlertController alertControllerWithTitle:@"Download-Only Verification" message:@"Enable local TFP1 download feed for 15 minutes without flashing permissions." preferredStyle:UIAlertControllerStyleAlert];[confirm addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];[confirm addAction:[UIAlertAction actionWithTitle:@"Download Only" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){if([TIOOTAFlashStatus()[@"stage"] integerValue]!=0){self.statusText=@"There is already an authorization or sending session and cannot be opened as a Download Only acceptance; the session is not changed.";[self refresh];return;}NSError *e=nil;BOOL ok=TIOBeginExperimentalOTAPreparation(&e);self.statusText=ok?@"Source active. Check official update page to download.":e.localizedDescription;[self refresh];}]];[self presentViewController:confirm animated:YES completion:nil];return;}
    if(path.row!=0)return;
    if(path.section==3){self.busy=YES;self.directoryStatus=@"Verifying SHA-256 checksums...";[self.tableView reloadData];
        NSURL *directory=[NSURL fileURLWithPath:[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/ota/Strix_OS_1.0.4.12"] isDirectory:YES];
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{NSError *error=nil;NSDictionary *result=TIOCheckExperimentalOTADirectory(directory,&error);dispatch_async(dispatch_get_main_queue(),^{self.busy=NO;self.directoryStatus=result?@"At this time, all 15 members in Table of Contents are consistent with TFP1. \n is only a read snapshot and has not been bound to the official transfer session; it has not been sent and cannot be flashed yet.":error.localizedDescription;[self.tableView reloadData];});});return;}
    if(path.section!=0)return;
    UIDocumentPickerViewController *picker=[[UIDocumentPickerViewController alloc]initForOpeningContentTypes:@[UTTypeZIP] asCopy:YES];picker.allowsMultipleSelection=NO;picker.delegate=self;[self presentViewController:picker animated:YES completion:nil];
}
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls{
    if(self.busy||urls.count!=1)return;self.busy=YES;self.statusText=@"Verifying selected TFP1 SHA-256...";[self.tableView reloadData];
    NSURL *source=urls.firstObject;
    NSURL *directory=StoreDirectory();
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        BOOL access=[source startAccessingSecurityScopedResource];NSError *error=nil;NSDictionary *result=TIOImportExperimentalOTA(source,directory,&error);if(access)[source stopAccessingSecurityScopedResource];
        dispatch_async(dispatch_get_main_queue(),^{self.busy=NO;self.statusText=result?@"TFP1 complete file verification passed, and the extended local copy has been saved. \n has not been sent to the glasses and the installation has not started; returning to this page will not trigger the upgrade.":(error.localizedDescription?:@"Import failed.");[self.tableView reloadData];});
    });
}
@end
UIViewController *TIOExperimentalOTAController(void){return [[TIOExperimentalOTAPage alloc]initWithStyle:UITableViewStyleInsetGrouped];}
