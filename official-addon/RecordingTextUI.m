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
static void TextAlert(UIViewController *vc,NSString *message){UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Recordings & AI Notes" message:message preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];[vc presentViewController:a animated:YES completion:nil];}
static NSURL *SaveText(NSString *name,NSString *text){
    // Only independent extension documents; never modify official transcripts.
    NSURL *root=[[NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject URLByAppendingPathComponent:@"TurboIOPrivateNotes"];
    NSNumber *link=nil;[root getResourceValue:&link forKey:NSURLIsSymbolicLinkKey error:nil];if(link.boolValue)return nil;
    NSURL *dir=[root URLByAppendingPathComponent:NSUUID.UUID.UUIDString];NSError *error=nil;
    if(![NSFileManager.defaultManager createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700,NSFileProtectionKey:NSFileProtectionCompleteUntilFirstUserAuthentication} error:&error])return nil;
    NSURL *file=[dir URLByAppendingPathComponent:name];if(![text writeToURL:file atomically:YES encoding:NSUTF8StringEncoding error:&error])return nil;
    [NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions:@0600,NSFileProtectionKey:NSFileProtectionCompleteUntilFirstUserAuthentication} ofItemAtPath:file.path error:nil];return file;
}
static void ShareText(UIViewController *vc,NSURL *file){if(!file){TextAlert(vc,@"Unable to write file; original records unchanged.");return;}UIActivityViewController *s=[[UIActivityViewController alloc]initWithActivityItems:@[file] applicationActivities:nil];s.popoverPresentationController.sourceView=vc.view;s.popoverPresentationController.sourceRect=CGRectMake(vc.view.bounds.size.width/2,100,1,1);[vc presentViewController:s animated:YES completion:nil];}

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
    NSString *text=nil;if(!error){NSMutableString *out=[NSMutableString stringWithFormat:@"# Custom Model Summary\n\nModel: %@\n\nSource: User transcript; official ASR retained. %lu chunks processed. Suggested action items only; no tasks automatically created.\n\n",self.model,(unsigned long)self.answers.count];for(NSUInteger i=0;i<self.answers.count;i++)[out appendFormat:@"## Chunk %lu\n\n%@\n\n",(unsigned long)i+1,self.answers[i]];text=out;}
    void (^done)(NSString *,NSString *)=self.complete;self.complete=nil;self.progress=nil;if(done)done(text,error);
}
- (void)next{if(self.ended)return;if(self.answers.count==self.chunks.count){[self finish:nil];return;}self.received=[NSMutableData new];
    NSDictionary *body=TIORecordingSummaryPayload(self.model,self.chunks[self.answers.count],self.disableThinking);if(!body){[self finish:@"Invalid chunk or model configuration; stopping."];return;}
    NSMutableURLRequest *r=[NSMutableURLRequest requestWithURL:TextEndpoint(self.endpoint)];r.HTTPMethod=@"POST";r.timeoutInterval=120;[r setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];[r setValue:@"application/json" forHTTPHeaderField:@"Accept"];[r setValue:[@"Bearer " stringByAppendingString:self.key] forHTTPHeaderField:@"Authorization"];r.HTTPBody=[NSJSONSerialization dataWithJSONObject:body options:0 error:nil];if(self.progress)self.progress(self.answers.count+1,self.chunks.count);[[self.session dataTaskWithRequest:r] resume];
}
- (void)start{if(!self.chunks.count||!TextEndpoint(self.endpoint)||!self.key.length){[self finish:@"Configure custom model endpoint, model name, and API key in settings first."];return;}self.answers=[NSMutableArray new];NSURLSessionConfiguration *c=NSURLSessionConfiguration.ephemeralSessionConfiguration;c.HTTPCookieStorage=nil;c.URLCredentialStorage=nil;c.URLCache=nil;c.timeoutIntervalForResource=180;self.session=[NSURLSession sessionWithConfiguration:c delegate:self delegateQueue:NSOperationQueue.mainQueue];[self next];}
- (void)URLSession:(NSURLSession *)s task:(NSURLSessionTask *)t willPerformHTTPRedirection:(NSHTTPURLResponse *)r newRequest:(NSURLRequest *)req completionHandler:(void (^)(NSURLRequest *))cb{cb(nil);[self finish:@"Service redirected; request cancelled."];}
- (void)URLSession:(NSURLSession *)s dataTask:(NSURLSessionDataTask *)t didReceiveResponse:(NSURLResponse *)r completionHandler:(void (^)(NSURLSessionResponseDisposition))cb{NSInteger code=[r isKindOfClass:NSHTTPURLResponse.class]?((NSHTTPURLResponse *)r).statusCode:0;if(code!=200||r.expectedContentLength>2*1024*1024||![r.MIMEType.lowercaseString isEqual:@"application/json"]){cb(NSURLSessionResponseCancel);[self finish:[NSString stringWithFormat:@"Service returned HTTP %ld; invalid JSON.",(long)code]];}else cb(NSURLSessionResponseAllow);}
- (void)URLSession:(NSURLSession *)s dataTask:(NSURLSessionDataTask *)t didReceiveData:(NSData *)d{if(self.ended)return;if(self.received.length+d.length>2*1024*1024){[self finish:@"Model response exceeds size limit."];return;}[self.received appendData:d];}
- (void)URLSession:(NSURLSession *)s task:(NSURLSessionTask *)t didCompleteWithError:(NSError *)error{if(self.ended)return;if(error){[self finish:@"Connection failed or timed out. Original transcript retained."];return;}NSString *answer=TIORecordingSummaryAnswer([NSJSONSerialization JSONObjectWithData:self.received options:0 error:nil]);if(!answer){[self finish:@"Model returned empty or non-text response."];return;}[self.answers addObject:answer];[self next];}
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
- (void)viewDidLoad{[super viewDidLoad];self.title=@"Transcript Summarization";self.view.backgroundColor=UIColor.systemBackgroundColor;
    self.info=[UILabel new];self.info.text=@"Official ASR retained. Import or paste transcript; text only, does not overwrite official content.";self.info.numberOfLines=0;self.info.font=[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    self.editor=[UITextView new];self.editor.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody];self.editor.text=self.initialText?:@"";
    UIButton *run=[UIButton buttonWithType:UIButtonTypeSystem];[run setTitle:@"Summarize with Custom Model" forState:UIControlStateNormal];[run addTarget:self action:@selector(confirm) forControlEvents:UIControlEventTouchUpInside];
    UIButton *share=[UIButton buttonWithType:UIButtonTypeSystem];[share setTitle:@"Share Summary Markdown" forState:UIControlStateNormal];[share addTarget:self action:@selector(shareResult) forControlEvents:UIControlEventTouchUpInside];
    UIButton *cancel=[UIButton buttonWithType:UIButtonTypeSystem];[cancel setTitle:@"Cancel Summarization" forState:UIControlStateNormal];[cancel addTarget:self action:@selector(cancelJob) forControlEvents:UIControlEventTouchUpInside];
    self.runButton=run;self.shareButton=share;self.cancelButton=cancel;self.editor.delegate=self;[self updateActions];
    self.info.adjustsFontForContentSizeCategory=YES;self.info.textColor=UIColor.secondaryLabelColor;self.editor.adjustsFontForContentSizeCategory=YES;self.editor.backgroundColor=UIColor.secondarySystemGroupedBackgroundColor;self.editor.layer.cornerRadius=16;self.editor.textContainerInset=UIEdgeInsetsMake(14,12,14,12);self.editor.accessibilityLabel=@"Full transcript text";
    self.view.backgroundColor=UIColor.systemGroupedBackgroundColor;
    run.configuration=UIButtonConfiguration.filledButtonConfiguration;share.configuration=UIButtonConfiguration.tintedButtonConfiguration;cancel.configuration=UIButtonConfiguration.plainButtonConfiguration;
    for(UIButton *b in @[run,share,cancel]){UIButtonConfiguration *config=b.configuration;config.contentInsets=NSDirectionalEdgeInsetsMake(12,16,12,16);b.configuration=config;b.titleLabel.adjustsFontForContentSizeCategory=YES;}
    UIScrollView *scroll=[UIScrollView new];scroll.translatesAutoresizingMaskIntoConstraints=NO;scroll.keyboardDismissMode=UIScrollViewKeyboardDismissModeInteractive;[self.view addSubview:scroll];
    UIStackView *stack=[[UIStackView alloc]initWithArrangedSubviews:@[self.info,self.editor,run,share,cancel]];stack.axis=UILayoutConstraintAxisVertical;stack.spacing=12;stack.translatesAutoresizingMaskIntoConstraints=NO;[scroll addSubview:stack];
    NSLayoutConstraint *preferredBottom=[scroll.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor];preferredBottom.priority=UILayoutPriorityDefaultHigh;
    [NSLayoutConstraint activateConstraints:@[[scroll.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],[scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],[scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],[scroll.bottomAnchor constraintLessThanOrEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],[scroll.bottomAnchor constraintLessThanOrEqualToAnchor:self.view.keyboardLayoutGuide.topAnchor],preferredBottom,[stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:16],[stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:20],[stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-20],[stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-16],[stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-40],[self.editor.heightAnchor constraintEqualToConstant:260]]];
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc]initWithTitle:@"Import Text" style:UIBarButtonItemStylePlain target:self action:@selector(importText)];
}
- (void)viewDidDisappear:(BOOL)animated{[super viewDidDisappear:animated];if(!self.presentedViewController)[self cancelJob];}
- (void)updateActions{self.runButton.enabled=!self.job&&[self.editor.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length>0;self.shareButton.enabled=self.resultFile!=nil&&!self.job;self.cancelButton.hidden=self.job==nil;}
- (void)textViewDidChange:(UITextView *)textView{[self updateActions];}
- (void)dealloc{[_job cancel];}
- (void)cancelJob{if(!self.job)return;[self.job cancel];self.job=nil;self.editor.editable=YES;self.info.text=@"Cancelled. Original recording and transcripts are unchanged.";[self updateActions];}
- (void)importText{if(self.job)return;UIDocumentPickerViewController *p=[[UIDocumentPickerViewController alloc]initForOpeningContentTypes:@[UTTypePlainText,[UTType typeWithFilenameExtension:@"md"]?:UTTypeText] asCopy:YES];p.delegate=self;[self presentViewController:p animated:YES completion:nil];}
- (void)documentPicker:(UIDocumentPickerViewController *)p didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls{NSURL *file=urls.firstObject;if(!file)return;NSNumber *bytes=nil;[file getResourceValue:&bytes forKey:NSURLFileSizeKey error:nil];NSString *text=bytes&&bytes.unsignedLongLongValue<=2*1024*1024?[NSString stringWithContentsOfURL:file encoding:NSUTF8StringEncoding error:nil]:nil;if(!TIORecordingTextChunks(text)){TextAlert(self,@"Requires non-empty UTF-8 TXT/MD (up to 300k chars / 2MB).");return;}self.editor.text=text;[self updateActions];self.info.text=@"Text imported. Please verify completeness before summarizing.";}
- (void)confirm{if(self.job)return;NSArray *chunks=TIORecordingTextChunks(self.editor.text);if(!chunks){TextAlert(self,@"Please import or paste full transcript (up to 300k chars).");return;}
    NSUserDefaults *prefs=TextPrefs();NSString *endpoint=[prefs stringForKey:@"endpoint"]?:@"",*model=[prefs stringForKey:@"model"]?:@"";
    if(!TextEndpoint(endpoint)||!TIORecordingSummaryPayload(model,chunks[0],NO)){TextAlert(self,@"Please configure a valid custom model endpoint first.");return;}
    NSString *source=[self.editor.text copy];BOOL thinking=[prefs boolForKey:@"deepseekDisableThinking"];
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Send Transcript for Summary?" message:[NSString stringWithFormat:@"Endpoint: %@\nModel: %@\n%lu characters, %lu chunks processed sequentially. Only this text is sent; no audio or official credentials.",TextEndpoint(endpoint).host,model,(unsigned long)source.length,(unsigned long)chunks.count] preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weak=self;[a addAction:[UIAlertAction actionWithTitle:@"Confirm & Summarize" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){typeof(self) self=weak;if(!self)return;NSString *key=TextKey(endpoint);if(!key.length){TextAlert(self,@"No API key found for this endpoint. Text not sent.");return;}
        TIORecordingSummaryJob *job=[TIORecordingSummaryJob new];self.job=job;job.endpoint=endpoint;job.model=model;job.key=key;job.chunks=chunks;job.disableThinking=thinking;self.editor.editable=NO;self.resultFile=nil;
        [self updateActions];job.progress=^(NSUInteger i,NSUInteger n){weak.info.text=[NSString stringWithFormat:@"Summarizing chunk %lu of %lu... Tap cancel or leave to stop.",(unsigned long)i,(unsigned long)n];};
        job.complete=^(NSString *answer,NSString *error){typeof(self) self=weak;if(!self)return;self.job=nil;self.editor.editable=YES;[self updateActions];if(error){self.info.text=error;return;}
            NSString *document=[answer stringByAppendingFormat:@"\n---\n\n# Input Transcript (Original)\n\n%@\n",source];self.resultFile=SaveText(@"TranscriptSummary.md",document);self.info.text=self.resultFile?@"All chunks summarized and saved as local Markdown. Tap Share to AirDrop or save to Files.":@"Model summarization complete, but saving failed. Content is available below.";self.editor.text=document;[self updateActions];
        };[job start];}]];[self presentViewController:a animated:YES completion:nil];
}
- (void)shareResult{if(!self.resultFile){TextAlert(self,@"No completed summary available.");return;}ShareText(self,self.resultFile);}
@end

// Reads only the extension-owned final-text archive, never the official Isar/Hive store.
static NSString *CapturedLifelogText(void){
    NSURL *url=[NSURL fileURLWithPath:[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/TurboIOPrivateAddon/final-transcripts.json"]];NSNumber *size=nil,*link=nil;[url getResourceValue:&size forKey:NSURLFileSizeKey error:nil];[url getResourceValue:&link forKey:NSURLIsSymbolicLinkKey error:nil];if(link.boolValue||!size||size.unsignedLongLongValue>32*1024*1024)return nil;
    id rows=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:url]?:NSData.data options:0 error:nil];if(![rows isKindOfClass:NSArray.class]||![rows count]||[rows count]>20000)return nil;
    NSMutableString *text=[NSMutableString stringWithString:@"# Saved AI Notes Text\n\nOnly includes text captured after enabling saving in the addon. Times reflect phone receipt.\n\n"];
    for(id r in rows){if(![r isKindOfClass:NSDictionary.class]||![r[@"text"] isKindOfClass:NSString.class]||![r[@"at"] isKindOfClass:NSString.class])return nil;[text appendFormat:@"## %@\n\n%@\n\n",r[@"at"],r[@"text"]];}return text;
}
@interface TIOLifelogExportsPanel:UITableViewController
@end
@implementation TIOLifelogExportsPanel
- (void)viewDidLoad{[super viewDidLoad];self.title=@"Saved Lifelog Text";TIOStyleResearchTable(self);}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s{return 2;}
- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s{return @"Only includes text captured after enabling saving in the Library tab. To share audio, open Audio Sharing.";}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip{UITableViewCell *c=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];TIOStyleResearchCell(c);c.textLabel.text=@[@"Export Saved Text Markdown",@"Summarize Saved Text with Model",@"Original Audio Export (Pending)"][ip.row];c.detailTextLabel.numberOfLines=0;c.detailTextLabel.text=@[@"Local copy · AirDrop / Save to Files",@"Preview range then confirm send",@"Awaiting official audio file mapping"][ip.row];if(ip.row==2){c.textLabel.textColor=UIColor.secondaryLabelColor;c.selectionStyle=UITableViewCellSelectionStyleNone;}else c.accessoryType=UITableViewCellAccessoryDisclosureIndicator;return c;}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip{[t deselectRowAtIndexPath:ip animated:YES];if(ip.row==2)return;dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{NSString *text=CapturedLifelogText();NSURL *file=ip.row==0&&text?SaveText(@"Lifelog.md",text):nil;dispatch_async(dispatch_get_main_queue(),^{if(!text){TextAlert(self,@"No saved text found. Enable text capture in Library first, then use official AI Notes.");return;}if(ip.row==0)ShareText(self,file);else {TIORecordingTextPanel *p=[TIORecordingTextPanel new];p.initialText=text;[self.navigationController pushViewController:p animated:YES];}});});}
@end
