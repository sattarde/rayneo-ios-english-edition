#import "ImageUploadUI.h"
#if TIO_IMAGE_RX_LAB
#import "ImageUploadTransport.h"
#import "ProtocolContext.h"
static TIOImageUpload *LabClient;
static TIOImageUploadTransport *LabCarrier;
BOOL TIOImageUploadLabConsumeFileEvent(NSDictionary *event){
 if(![event isKindOfClass:NSDictionary.class]||![event[@"device"] isKindOfClass:NSDictionary.class]||
    ![TIOProtocolDevice() isEqual:event[@"device"][@"id"]])return NO;
 return [LabCarrier observeFileEvent:event client:LabClient];
}
#endif
#import <PhotosUI/PhotosUI.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <ImageIO/ImageIO.h>
// Downsample during decode on the phone; do not expand a full-resolution photo.
// Profile is shared by the phone encoder and AP parser; no large-PNG decoder.
static NSData *Luminance(NSURL *url){
 if(!url.isFileURL)return nil;
 NSDictionary *attr=[NSFileManager.defaultManager attributesOfItemAtPath:url.path error:nil];
 if(![attr[NSFileType] isEqual:NSFileTypeRegular]||[attr[NSFileSize] unsignedLongLongValue]>20*1024*1024)return nil;
 CGImageSourceRef source=CGImageSourceCreateWithURL((__bridge CFURLRef)url,(__bridge CFDictionaryRef)@{(__bridge NSString *)kCGImageSourceShouldCache:@NO});
 if(!source)return nil;
 CFStringRef type=CGImageSourceGetType(source);
 NSDictionary *props=CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source,0,NULL));
 uint64_t w=[props[(__bridge NSString *)kCGImagePropertyPixelWidth] unsignedLongLongValue],h=[props[(__bridge NSString *)kCGImagePropertyPixelHeight] unsignedLongLongValue];
 BOOL valid=type&&(CFEqual(type,CFSTR("public.png"))||CFEqual(type,CFSTR("public.jpeg")))&&CGImageSourceGetCount(source)==1&&w&&h&&w<=16000000&&h<=16000000&&w<=16000000/h;
 if(!valid){CFRelease(source);return nil;}
 CGImageRef thumb=CGImageSourceCreateThumbnailAtIndex(source,0,(__bridge CFDictionaryRef)@{(__bridge NSString *)kCGImageSourceCreateThumbnailFromImageAlways:@YES,(__bridge NSString *)kCGImageSourceCreateThumbnailWithTransform:@YES,(__bridge NSString *)kCGImageSourceThumbnailMaxPixelSize:@(TIO_W),(__bridge NSString *)kCGImageSourceShouldCacheImmediately:@YES});
 CFRelease(source);if(!thumb)return nil;
 NSMutableData *gray=[NSMutableData dataWithLength:TIO_PIXELS];CGColorSpaceRef space=CGColorSpaceCreateDeviceGray();
 CGContextRef ctx=CGBitmapContextCreate(gray.mutableBytes,TIO_W,TIO_H,8,TIO_W,space,(CGBitmapInfo)kCGImageAlphaNone);CGColorSpaceRelease(space);
 if(!ctx){CGImageRelease(thumb);return nil;}
 double sw=CGImageGetWidth(thumb),sh=CGImageGetHeight(thumb),s=fmin(TIO_W/sw,TIO_H/sh);
 CGContextSetGrayFillColor(ctx,0,1);CGContextFillRect(ctx,CGRectMake(0,0,TIO_W,TIO_H));CGContextSetInterpolationQuality(ctx,kCGInterpolationHigh);
 CGContextDrawImage(ctx,CGRectMake((TIO_W-sw*s)/2,(TIO_H-sh*s)/2,sw*s,sh*s),thumb);
 CGContextRelease(ctx);CGImageRelease(thumb);return gray;
}
@interface TIOImageUploadPage : UITableViewController<PHPickerViewControllerDelegate,UIDocumentPickerDelegate>
@property(nonatomic,strong) TIOImageUpload *client;
@property(nonatomic,strong) NSData *pixels;
@property(nonatomic,strong) UIImage *preview;
@property(nonatomic,copy) NSString *note;
@property(nonatomic) NSUInteger generation;
@property(nonatomic) BOOL loading;
@property(nonatomic,strong) NSTimer *timer;
@end
@implementation TIOImageUploadPage
- (void)viewDidLoad{
 [super viewDidLoad];self.title=@"Image Transfer Lab";self.note=@"Only local image selection and preview; original firmware and current R3 avatar firmware do not support reception. Requires new AP module and verified routing.";
 self.tableView.rowHeight=UITableViewAutomaticDimension;self.tableView.estimatedRowHeight=80;
 __weak typeof(self) weak=self;self.client.changed=^{[weak.tableView reloadData];};
 self.timer=[NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *t){[weak.client tick:NSProcessInfo.processInfo.systemUptime];}];
}
#if TIO_IMAGE_RX_LAB
- (void)armManualSession{
 if(!self.pixels){self.note=@"First select an image on your phone, and then open Turbo Image RX on your glasses; this will not waste the 120-second window of your glasses.";[self.tableView reloadData];return;}
 if(LabClient.task.length){self.note=@"In this experiment, only one submission is submitted each time the app is launched. Existing tasks will not be automatically resent; first confirm the completion and exit the glasses page, then restart the app for the next round.";[self.tableView reloadData];return;}
 NSString *device=TIOProtocolDevice();
 if(!device.length){self.note=@"There is no current official protocol object. Please confirm the connection on the official device page first; a second Bluetooth connection will not be created.";[self.tableView reloadData];return;}
 UIAlertController *a=[UIAlertController alertControllerWithTitle:@"N8 picture reception · human conversation" message:@"Only for new N8/N8W test firmware. Must see SID on glasses Turbo Image RX page; not supported by stock/R3. Click Send within 30 seconds after entering the current SID. There is a maximum of one file in this round. The receipt of the file by the SDK does not mean that the lens is displayed and requires manual acceptance. OTA will not be triggered." preferredStyle:UIAlertControllerStyleAlert];
 [a addTextFieldWithConfigurationHandler:^(UITextField *f){f.placeholder=@"Decimal SID displayed by glasses";f.keyboardType=UIKeyboardTypeNumberPad;}];
 [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
 __weak typeof(self) weak=self;
 [a addAction:[UIAlertAction actionWithTitle:@"SID has been seen, start this round" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){
  if(!weak)return;
  NSString *text=a.textFields.firstObject.text;NSCharacterSet *bad=[[NSCharacterSet characterSetWithCharactersInString:@"0123456789"] invertedSet];
  unsigned long long sid=text.longLongValue;
  if(!text.length||text.length>10||[text rangeOfCharacterFromSet:bad].location!=NSNotFound||!sid||sid>UINT32_MAX||![device isEqual:TIOProtocolDevice()]){weak.note=@"The SID is invalid or the device has been changed and is not turned on.";[weak.tableView reloadData];return;}
  NSURL *root=[NSURL fileURLWithPath:[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/TurboIOPrivateAddon/ImageRXLab"] isDirectory:YES];
  LabCarrier=TIOImageUploadOfficialTransport(root,device);
  TIOImageUploadTransport *carrier=LabCarrier;
  LabClient=[[TIOImageUpload alloc]initWithSender:^(NSData *packet,NSString *target,NSString *task,void(^submitted)(BOOL)){
   [carrier sendPacket:packet device:target task:task submitted:submitted];
  }];
  if(![LabClient authorizeDevice:device session:(uint32_t)sid at:NSProcessInfo.processInfo.systemUptime])return;
  weak.client=LabClient;LabClient.changed=^{[weak.tableView reloadData];};
  weak.note=@"The artificial SID experiment is enabled, please click Send within 30 seconds. Check whether the reception is successful. Look at the lens picture and #1, it will automatically show that ACK has not been connected yet.";[weak.tableView reloadData];
 }]];[self presentViewController:a animated:YES completion:nil];
}
#endif
- (void)dealloc{[_timer invalidate];}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s{return 6;}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)p{
 UITableViewCell *c=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
 c.textLabel.numberOfLines=c.detailTextLabel.numberOfLines=0;
 NSArray *titles=@[@"1 · Select from photos",@"Or select PNG / JPEG from file",[NSString stringWithFormat:@"2·Transmission preview (%d×%d)",TIO_W,TIO_H],@"3 · Send to glasses",@"Receive and display status",@"Original image decoding is another test"];
 c.textLabel.text=titles[p.row];
 if(p.row==2){c.imageView.image=self.preview;c.detailTextLabel.text=self.pixels?[NSString stringWithFormat:@"%d KiB grayscale pixels; scaled down to leave black edges. Protocol v%d needs to match the AP of this round.",TIO_PIXELS/1024,TIO_VERSION]:@"No picture selected yet";}
 if(p.row==3){BOOL ready=[self.client.state isEqual:@"ready"]||[self.client.state isEqual:@"render_submitted"];c.textLabel.textColor=(ready&&self.pixels&&!self.loading)?UIColor.systemBlueColor:UIColor.secondaryLabelColor;c.detailTextLabel.text=ready?@"Only send the current picture, do not start OTA, do not upload to the cloud":@"Waiting for authenticated AP image reception session; currently no blind sending";}
 if(p.row==4){NSString *state=self.client.state?:@"receiver_not_verified";NSString *detail=self.note?:@"";
  if([state isEqual:@"submission_failed"])detail=@"The mobile phone submission failed and the receipt of the glasses was not confirmed; the diagnosis has been saved. Please do not click send twice.";
  else if([state isEqual:@"file_failed"])detail=@"The official document channel failed to return and no confirmation was displayed. Please do not resend.";
  else if([state isEqual:@"timeout_result_unknown"])detail=@"Timed out while waiting for acknowledgment, result unknown; view lens #1 and pictures, will not automatically resend.";
  else if([state isEqual:@"file_received_waiting_renderer"])detail=@"File success acknowledgment received; no automatic ACK showing, please check lens picture and #1.";
  c.detailTextLabel.text=[NSString stringWithFormat:@"%@\n%@",state,detail];}
 if(p.row==5)c.detailTextLabel.text=@"The 256–1024 PNG ladder sample has been prepared for Mac; this page does not pass off mobile phone thumbnails for glasses large image capabilities.";
 return c;
}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)p{
 [t deselectRowAtIndexPath:p animated:YES];if(self.loading)return;
 if(p.row==0){PHPickerConfiguration *config=[[PHPickerConfiguration alloc]init];config.selectionLimit=1;config.filter=PHPickerFilter.imagesFilter;PHPickerViewController *picker=[[PHPickerViewController alloc]initWithConfiguration:config];picker.delegate=self;[self presentViewController:picker animated:YES completion:nil];}
 if(p.row==1){UIDocumentPickerViewController *picker=[[UIDocumentPickerViewController alloc]initForOpeningContentTypes:@[UTTypePNG,UTTypeJPEG] asCopy:YES];picker.delegate=self;[self presentViewController:picker animated:YES completion:nil];}
 if(p.row==3&&self.pixels){BOOL ok=[self.client sendLuminance:self.pixels at:NSProcessInfo.processInfo.systemUptime];self.note=ok?@"This picture has been submitted and is waiting for the independent receipt of the file and AP; if there is no receipt, it will not show success.":@"Not Sent: The receiving module is not verified, the session is unavailable, or there is already a task.";[t reloadData];}
}
- (void)accept:(NSURL *)url generation:(NSUInteger)generation{
 // Called on the provider/background queue while the temporary URL is valid.
 BOOL scoped=[url startAccessingSecurityScopedResource];NSData *pixels=Luminance(url);if(scoped)[url stopAccessingSecurityScopedResource];
 dispatch_async(dispatch_get_main_queue(),^{
  if(generation!=self.generation)return;self.loading=NO;self.pixels=pixels;self.preview=nil;
  if(pixels){CGColorSpaceRef color=CGColorSpaceCreateDeviceGray();CGDataProviderRef provider=CGDataProviderCreateWithCFData((__bridge CFDataRef)pixels);
   CGImageRef im=CGImageCreate(TIO_W,TIO_H,8,8,TIO_W,color,(CGBitmapInfo)kCGImageAlphaNone,provider,NULL,false,kCGRenderingIntentDefault);
   if(im){self.preview=[UIImage imageWithCGImage:im];CGImageRelease(im);}CGDataProviderRelease(provider);CGColorSpaceRelease(color);
  }
  self.note=pixels?@"Pixels have been generated on the mobile phone and uploaded without cloud; waiting for acceptance by the receiving module.":@"Image selection failed: Only single frame PNG/JPEG is supported, up to 16MP, 20 MiB.";
  [self.tableView reloadData];
 });
}
- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results{
 [picker dismissViewControllerAnimated:YES completion:nil];if(!results.count)return;
 self.loading=YES;NSUInteger generation=++self.generation;self.pixels=nil;self.preview=nil;[self.tableView reloadData];
 NSItemProvider *provider=results.firstObject.itemProvider;
 [provider loadFileRepresentationForTypeIdentifier:UTTypeImage.identifier completionHandler:^(NSURL *url,NSError *error){[self accept:url generation:generation];}];
}
- (void)documentPicker:(UIDocumentPickerViewController *)c didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls{
 if(!urls.count)return;self.loading=YES;NSUInteger generation=++self.generation;self.pixels=nil;self.preview=nil;[self.tableView reloadData];
 dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{[self accept:urls.firstObject generation:generation];});
}
@end
UIViewController *TIOImageUploadController(TIOImageUpload *client){TIOImageUploadPage *p=[[TIOImageUploadPage alloc]initWithStyle:UITableViewStyleInsetGrouped];p.client=client;return p;}
#if TIO_IMAGE_RX_LAB
UIViewController *TIOImageUploadLabController(void){
 TIOImageUploadPage *p=(id)TIOImageUploadController(LabClient);[p loadViewIfNeeded];
 p.note=@"R4 Image Transfer: select image, open Turbo Image RX on glasses, tap top right to enter SID.";
#if TIO_IMAGE_RX_WIDE
 p.title=@"N8W · Image Transfer FIX 01";
 p.note=@"N8W Wide Area: glasses canvas 540x180, image 512x128. Select image, open item 8 Turbo Image RX, enter SID. Finally look at lens #1 and the picture.";
#endif
 p.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc]initWithTitle:@"Enter SID" style:UIBarButtonItemStylePlain target:p action:@selector(armManualSession)];return p;
}
#endif
