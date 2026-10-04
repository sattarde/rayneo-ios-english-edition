#import <UIKit/UIKit.h>
#import <Security/Security.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <objc/runtime.h>
#import "RecordingText.h"
#import "ResearchUI.h"

static NSString *const TextDomain=@"io.turboio.official-private-addon";
static NSUserDefaults *TextPrefs(void){return [[NSUserDefaults alloc]initWithSuiteName:TextDomain];}
static NSURL *TextEndpoint(NSString *s){NSURLComponents *c=[NSURLComponents componentsWithString:s];return [c.scheme.lowercaseString isEqual:@"https"]&&c.host.length&&!c.user&&!c.password&&!c.query&&!c.fragment&&[c.path hasSuffix:@"/chat/completions"]?c.URL:nil;}
static NSString *TextKey(NSString *endpoint){
    NSDictionary *q=@{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,(__bridge id)kSecAttrService:TextDomain,(__bridge id)kSecAttrAccount:endpoint,(__bridge id)kSecReturnData:@YES};
    CFTypeRef result=NULL;if(SecItemCopyMatching((__bridge CFDictionaryRef)q,&result)!=errSecSuccess)return @"";
    return [[NSString alloc]initWithData:CFBridgingRelease(result) encoding:NSUTF8StringEncoding]?:@"";
}
static void TextAlert(UIViewController *vc,NSString *message){UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Recording and recording" message:message preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];[vc presentViewController:a animated:YES completion:nil];}
static NSURL *SaveText(NSString *name,NSString *text){
    // Only independent extension documents; never modify official transcripts.
    NSURL *root=[[NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject URLByAppendingPathComponent:@"TurboIOPrivateNotes"];
    NSNumber *link=nil;[root getResourceValue:&link forKey:NSURLIsSymbolicLinkKey error:nil];if(link.boolValue)return nil;
    NSURL *dir=[root URLByAppendingPathComponent:NSUUID.UUID.UUIDString];NSError *error=nil;
    if(![NSFileManager.defaultManager createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700,NSFileProtectionKey:NSFileProtectionCompleteUntilFirstUserAuthentication} error:&error])return nil;
    NSURL *file=[dir URLByAppendingPathComponent:name];if(![text writeToURL:file atomically:YES encoding:NSUTF8StringEncoding error:&error])return nil;
    [NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions:@0600,NSFileProtectionKey:NSFileProtectionCompleteUntilFirstUserAuthentication} ofItemAtPath:file.path error:nil];return file;
}
static void ShareText(UIViewController *vc,NSURL *file){if(!file){TextAlert(vc,@"Unable to write to a separate file, the original record remains unchanged.");return;}UIActivityViewController *s=[[UIActivityViewController alloc]initWithActivityItems:@[file] applicationActivities:nil];s.popoverPresentationController.sourceView=vc.view;s.popoverPresentationController.sourceRect=CGRectMake(vc.view.bounds.size.width/2,100,1,1);[vc presentViewController:s animated:YES completion:nil];}

@interface TIORecordingSummaryJob:NSObject<NSURLSessionDataDelegate>
@property(nonatomic) NSURLSession *session;
@property(nonatomic) NSMutableData *received;
@property(nonatomic) NSArray<NSString *> *chunks;
@property(nonatomic) NSMutableArray<NSString *> *answers;
@property(nonatomic) NSString *endpoint,*model,*key;
@property(nonatomic) BOOL disableThinking,ended;
@property(nonatomic,copy) void (^progress)(NSUInteger,NSUInteger);
@property(nonatomic,copy) void (^complete)(NSString *,NSString *);
- (void)start;
- (void)cancel;
@end
@implementation TIORecordingSummaryJob
- (void)finish:(NSString *)error{if(self.ended)return;self.ended=YES;[self.session invalidateAndCancel];self.session=nil;self.key=@"";
    NSString *text=nil;if(!error){NSMutableString *out=[NSMutableString stringWithFormat:@"# Organize your own models \n\n Model: %@\n\n Source: Transcribed text confirmed by the user; retain the official ASR. There are a total of %lu segments, all processed. The following is organized paragraph by paragraph and does not pretend to be a comprehensive conclusion of the full text; the action items are only suggestions and no to-dos are automatically created. \n\n",self.model,(unsigned long)self.answers.count];for(NSUInteger i=0;i<self.answers.count;i++)[out appendFormat:@"## Section %lu \n\n%@\n\n",(unsigned long)i+1,self.answers[i]];text=out;}
    void (^done)(NSString *,NSString *)=self.complete;self.complete=nil;self.progress=nil;if(done)done(text,error);
}
- (void)next{if(self.ended)return;if(self.answers.count==self.chunks.count){[self finish:nil];return;}self.received=[NSMutableData new];
    NSDictionary *body=TIORecordingSummaryPayload(self.model,self.chunks[self.answers.count],self.disableThinking);if(!body){[self finish:@"The text segmentation or model configuration is invalid and the sending is not continued."];return;}
    NSMutableURLRequest *r=[NSMutableURLRequest requestWithURL:TextEndpoint(self.endpoint)];r.HTTPMethod=@"POST";r.timeoutInterval=120;[r setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];[r setValue:@"application/json" forHTTPHeaderField:@"Accept"];[r setValue:[@"Bearer " stringByAppendingString:self.key] forHTTPHeaderField:@"Authorization"];r.HTTPBody=[NSJSONSerialization dataWithJSONObject:body options:0 error:nil];if(self.progress)self.progress(self.answers.count+1,self.chunks.count);[[self.session dataTaskWithRequest:r] resume];
}
- (void)start{if(!self.chunks.count||!TextEndpoint(self.endpoint)||!self.key.length){[self finish:@"Please configure your own model address, model and key in the research menu first."];return;}self.answers=[NSMutableArray new];NSURLSessionConfiguration *c=NSURLSessionConfiguration.ephemeralSessionConfiguration;c.HTTPCookieStorage=nil;c.URLCredentialStorage=nil;c.URLCache=nil;c.timeoutIntervalForResource=180;self.session=[NSURLSession sessionWithConfiguration:c delegate:self delegateQueue:NSOperationQueue.mainQueue];[self next];}
- (void)URLSession:(NSURLSession *)s task:(NSURLSessionTask *)t willPerformHTTPRedirection:(NSHTTPURLResponse *)r newRequest:(NSURLRequest *)req completionHandler:(void (^)(NSURLRequest *))cb{cb(nil);[self finish:@"The service returns a redirect without carrying the Key."];}
- (void)URLSession:(NSURLSession *)s dataTask:(NSURLSessionDataTask *)t didReceiveResponse:(NSURLResponse *)r completionHandler:(void (^)(NSURLSessionResponseDisposition))cb{NSInteger code=[r isKindOfClass:NSHTTPURLResponse.class]?((NSHTTPURLResponse *)r).statusCode:0;if(code!=200||r.expectedContentLength>2*1024*1024||![r.MIMEType.lowercaseString isEqual:@"application/json"]){cb(NSURLSessionResponseCancel);[self finish:[NSString stringWithFormat:@"The service did not return valid JSON (HTTP %ld). Not Saved error text; original transcription unchanged.",(long)code]];}else cb(NSURLSessionResponseAllow);}
- (void)URLSession:(NSURLSession *)s dataTask:(NSURLSessionDataTask *)t didReceiveData:(NSData *)d{if(self.ended)return;if(self.received.length+d.length>2*1024*1024){[self finish:@"Model response exceeds size limit."];return;}[self.received appendData:d];}
- (void)URLSession:(NSURLSession *)s task:(NSURLSessionTask *)t didCompleteWithError:(NSError *)error{if(self.ended)return;if(error){[self finish:@"The connection failed or timed out, and this sorting has not been completed. The original transcription is retained and can be retried manually."];return;}NSString *answer=TIORecordingSummaryAnswer([NSJSONSerialization JSONObjectWithData:self.received options:0 error:nil]);if(!answer){[self finish:@"The model did not end completely, returned empty content or non-text results; the half-summary was not saved as successful."];return;}[self.answers addObject:answer];[self next];}
- (void)cancel{self.ended=YES;self.complete=nil;self.progress=nil;self.key=@"";[self.session invalidateAndCancel];self.session=nil;}
@end

@interface TIORecordingTextPanel:UIViewController<UIDocumentPickerDelegate,UITextViewDelegate>
@property(nonatomic) UITextView *editor;
@property(nonatomic) UILabel *info;
@property(nonatomic) NSString *initialText;
@property(nonatomic) TIORecordingSummaryJob *job;
@property(nonatomic) NSURL *resultFile;
@property(nonatomic) UIButton *runButton,*shareButton,*cancelButton;
@end
@implementation TIORecordingTextPanel
- (void)viewDidLoad{[super viewDidLoad];self.title=@"Transcript Summaries";self.view.backgroundColor=TIOPaper();
    self.info=[UILabel new];self.info.text=@"Keep the official ASR. Import or paste the complete transcription, and only upload the text after confirmation; official content will not be overwritten.";self.info.numberOfLines=0;self.info.font=[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    self.editor=[UITextView new];self.editor.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody];self.editor.text=self.initialText?:@"";
    UIButton *run=[UIButton buttonWithType:UIButtonTypeSystem];[run setTitle:@"Summarize with Current Model" forState:UIControlStateNormal];[run addTarget:self action:@selector(confirm) forControlEvents:UIControlEventTouchUpInside];
    UIButton *share=[UIButton buttonWithType:UIButtonTypeSystem];[share setTitle:@"Share Summary Markdown" forState:UIControlStateNormal];[share addTarget:self action:@selector(shareResult) forControlEvents:UIControlEventTouchUpInside];
    UIButton *cancel=[UIButton buttonWithType:UIButtonTypeSystem];[cancel setTitle:@"Cancel Summary" forState:UIControlStateNormal];[cancel addTarget:self action:@selector(cancelJob) forControlEvents:UIControlEventTouchUpInside];
    self.runButton=run;self.shareButton=share;self.cancelButton=cancel;self.editor.delegate=self;[self updateActions];
    self.info.adjustsFontForContentSizeCategory=YES;self.info.textColor=UIColor.secondaryLabelColor;self.editor.adjustsFontForContentSizeCategory=YES;self.editor.textColor=TIOInk();self.editor.backgroundColor=[TIOInk()colorWithAlphaComponent:.05];self.editor.layer.cornerRadius=16;self.editor.textContainerInset=UIEdgeInsetsMake(14,12,14,12);self.editor.accessibilityLabel=@"Completely transcribed text";
    self.view.backgroundColor=TIOPaper();
    run.configuration=UIButtonConfiguration.filledButtonConfiguration;share.configuration=UIButtonConfiguration.tintedButtonConfiguration;cancel.configuration=UIButtonConfiguration.plainButtonConfiguration;
    for(UIButton *b in @[run,share,cancel]){UIButtonConfiguration *config=b.configuration;config.contentInsets=NSDirectionalEdgeInsetsMake(12,16,12,16);b.configuration=config;b.titleLabel.adjustsFontForContentSizeCategory=YES;}
    UIScrollView *scroll=[UIScrollView new];scroll.translatesAutoresizingMaskIntoConstraints=NO;scroll.keyboardDismissMode=UIScrollViewKeyboardDismissModeInteractive;[self.view addSubview:scroll];
    TIOStyleAction(run,YES,NO);TIOStyleAction(share,NO,NO);TIOStyleAction(cancel,NO,YES);UIStackView *stack=[[UIStackView alloc]initWithArrangedSubviews:@[self.info,self.editor,run,share,cancel]];stack.axis=UILayoutConstraintAxisVertical;stack.spacing=12;stack.translatesAutoresizingMaskIntoConstraints=NO;[scroll addSubview:stack];
    NSLayoutConstraint *preferredBottom=[scroll.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor];preferredBottom.priority=UILayoutPriorityDefaultHigh;
    [NSLayoutConstraint activateConstraints:@[[scroll.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],[scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],[scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],[scroll.bottomAnchor constraintLessThanOrEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],[scroll.bottomAnchor constraintLessThanOrEqualToAnchor:self.view.keyboardLayoutGuide.topAnchor],preferredBottom,[stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:16],[stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:20],[stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-20],[stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-16],[stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-40],[self.editor.heightAnchor constraintEqualToConstant:260]]];
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc]initWithTitle:@"Import Text" style:UIBarButtonItemStylePlain target:self action:@selector(importText)];
}
- (void)viewDidDisappear:(BOOL)animated{[super viewDidDisappear:animated];if(!self.presentedViewController)[self cancelJob];}
- (void)updateActions{self.runButton.enabled=!self.job&&[self.editor.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length>0;self.shareButton.enabled=self.resultFile!=nil&&!self.job;self.cancelButton.hidden=self.job==nil;}
- (void)textViewDidChange:(UITextView *)textView{[self updateActions];}
- (void)dealloc{[_job cancel];}
- (void)cancelJob{if(!self.job)return;[self.job cancel];self.job=nil;self.editor.editable=YES;self.info.text=@"This time has been cancelled. The original recording, transcription and previously saved arrangement results remain unchanged.";[self updateActions];}
- (void)importText{if(self.job)return;UIDocumentPickerViewController *p=[[UIDocumentPickerViewController alloc]initForOpeningContentTypes:@[UTTypePlainText,[UTType typeWithFilenameExtension:@"md"]?:UTTypeText] asCopy:YES];p.delegate=self;[self presentViewController:p animated:YES completion:nil];}
- (void)documentPicker:(UIDocumentPickerViewController *)p didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls{NSURL *file=urls.firstObject;if(!file)return;NSNumber *bytes=nil;[file getResourceValue:&bytes forKey:NSURLFileSizeKey error:nil];NSString *text=bytes&&bytes.unsignedLongLongValue<=2*1024*1024?[NSString stringWithContentsOfURL:file encoding:NSUTF8StringEncoding error:nil]:nil;if(!TIORecordingTextChunks(text)){TextAlert(self,@"Requires non-empty UTF-8 TXT/MD, up to 300,000 characters / 2 MB; full text will not be silently truncated.");return;}self.editor.text=text;[self updateActions];self.info.text=@"Native text has been imported but has not been uploaded. Please check whether it is a complete transcription.";}
- (void)confirm{if(self.job)return;NSArray *chunks=TIORecordingTextChunks(self.editor.text);if(!chunks){TextAlert(self,@"Start by importing or pasting the full transcription, up to 300,000 characters. Do not automatically read the clipboard or treat a few paragraphs on the screen as full text.");return;}
    NSUserDefaults *prefs=TextPrefs();NSString *endpoint=[prefs stringForKey:@"endpoint"]?:@"",*model=[prefs stringForKey:@"model"]?:@"";
    if(!TextEndpoint(endpoint)||!TIORecordingSummaryPayload(model,chunks[0],NO)){TextAlert(self,@"Please configure a valid custom model in Research menu first interface.");return;}
    NSString *source=[self.editor.text copy];BOOL thinking=[prefs boolForKey:@"deepseekDisableThinking"];
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Send Transcript Text?" message:[NSString stringWithFormat:@"Service: %@\n Model: %@\n%lu Character, %lu Segment sequential processing, charges may apply. Only this text will be sent, no audio, chat history or official credentials will be sent. The original text is retained and independent Markdown is generated.",TextEndpoint(endpoint).host,model,(unsigned long)source.length,(unsigned long)chunks.count] preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weak=self;[a addAction:[UIAlertAction actionWithTitle:@"Confirm Summary" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){typeof(self) self=weak;if(!self)return;NSString *key=TextKey(endpoint);if(!key.length){TextAlert(self,@"The current service has no own Key available and no text was sent.");return;}
        TIORecordingSummaryJob *job=[TIORecordingSummaryJob new];self.job=job;job.endpoint=endpoint;job.model=model;job.key=key;job.chunks=chunks;job.disableThinking=thinking;self.editor.editable=NO;self.resultFile=nil;
        [self updateActions];job.progress=^(NSUInteger i,NSUInteger n){weak.info.text=[NSString stringWithFormat:@"Organizing section %lu / %lu... Can be canceled; leaving this page will stop.",(unsigned long)i,(unsigned long)n];};
        job.complete=^(NSString *answer,NSString *error){typeof(self) self=weak;if(!self)return;self.job=nil;self.editor.editable=YES;[self updateActions];if(error){self.info.text=error;return;}
            NSString *document=[answer stringByAppendingFormat:@"\n---\n\n# Input transcription (leave as is) \n\n%@\n",source];self.resultFile=SaveText(@"Recording arrangement.md",document);self.info.text=self.resultFile?@"All sections have been organized and saved in native Markdown (including the original input text). Click Share to AirDrop/Save to File.":@"The model is organized, but the local save fails. The content remains below, please copy and save.";self.editor.text=document;[self updateActions];
        };[job start];}]];[self presentViewController:a animated:YES completion:nil];
}
- (void)shareResult{if(!self.resultFile){TextAlert(self,@"No complete summary results for this session.");return;}ShareText(self,self.resultFile);}
@end

// Reads only the extension-owned final-text archive, never the official Isar/Hive store.
static NSString *CapturedLifelogText(void){
    NSURL *url=[NSURL fileURLWithPath:[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/TurboIOPrivateAddon/final-transcripts.json"]];NSNumber *size=nil,*link=nil;[url getResourceValue:&size forKey:NSURLFileSizeKey error:nil];[url getResourceValue:&link forKey:NSURLIsSymbolicLinkKey error:nil];if(link.boolValue||!size||size.unsignedLongLongValue>32*1024*1024)return nil;
    id rows=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:url]?:NSData.data options:0 error:nil];if(![rows isKindOfClass:NSArray.class]||![rows count]||[rows count]>20000)return nil;
    NSMutableString *text=[NSMutableString stringWithString:@"# The saved text of Quantian Zhiji\n\n only contains the final text received after enabling extended saving, not the complete history or original audio. The time is the reception time of the mobile phone. \n\n"];
    for(id r in rows){if(![r isKindOfClass:NSDictionary.class]||![r[@"text"] isKindOfClass:NSString.class]||![r[@"at"] isKindOfClass:NSString.class])return nil;[text appendFormat:@"## %@\n\n%@\n\n",r[@"at"],r[@"text"]];}return text;
}
@interface TIOLifelogExportsPanel:UITableViewController
@end
@implementation TIOLifelogExportsPanel
- (void)viewDidLoad{[super viewDidLoad];self.title=@"Saved Lifelog Notes";TIOStyleResearchTable(self);self.tableView.tableHeaderView=TIOFeatureHeader(@"written down fragments",@"Only display the saved content of the extension and do not pretend to be the full history.",@"reading");}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s{return 2;}
- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s{return @"It only contains the final text received after opening the save on the \"Information\" page, and does not represent the full official history. To save and share audio, please return to the information page to open it directly.";}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip{UITableViewCell *c=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];TIOStyleResearchCell(c);c.textLabel.text=@[@"Export saved text to Markdown",@"Organize saved text with your own models",@"Original audio export (not connected yet)"][ip.row];c.detailTextLabel.numberOfLines=0;c.detailTextLabel.text=@[@"Local independent copy · AirDrop / Store to file",@"Preview the range first and then confirm sending the text",@"Waiting for confirmation that the official cache file is associated with the session"][ip.row];if(ip.row==2){c.textLabel.textColor=UIColor.secondaryLabelColor;c.selectionStyle=UITableViewCellSelectionStyleNone;}else c.accessoryType=UITableViewCellAccessoryDisclosureIndicator;return c;}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip{[t deselectRowAtIndexPath:ip animated:YES];if(ip.row==2)return;dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{NSString *text=CapturedLifelogText();NSURL *file=ip.row==0&&text?SaveText(@"All-day wisdom.md",text):nil;dispatch_async(dispatch_get_main_queue(),^{if(!text){TextAlert(self,@"There is no final text for the extended save yet. First enable bypass saving in the research menu, and then use the official All-Tian Wisdom Record; old history cannot be automatically exported yet.");return;}if(ip.row==0)ShareText(self,file);else {TIORecordingTextPanel *p=[TIORecordingTextPanel new];p.initialText=text;[self.navigationController pushViewController:p animated:YES];}});});}
@end
