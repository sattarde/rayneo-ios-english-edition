#import "ProfileUI.h"
#import "Profile.h"
@interface TIOProfilePanel:UIViewController
@property(nonatomic) UITextField *nameField,*identityField;
@property(nonatomic) UITextView *preferences;
@end
@implementation TIOProfilePanel
- (void)viewDidLoad{[super viewDidLoad];self.title=@"Profile & Prompts";self.view.backgroundColor=UIColor.systemGroupedBackgroundColor;
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc]initWithTitle:@"Save" style:UIBarButtonItemStyleDone target:self action:@selector(save)];
    UIScrollView *scroll=[UIScrollView new];scroll.translatesAutoresizingMaskIntoConstraints=NO;scroll.keyboardDismissMode=UIScrollViewKeyboardDismissModeInteractive;[self.view addSubview:scroll];
    UIStackView *stack=[UIStackView new];stack.axis=UILayoutConstraintAxisVertical;stack.spacing=14;stack.translatesAutoresizingMaskIntoConstraints=NO;[scroll addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[[scroll.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],[scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],[scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],[scroll.bottomAnchor constraintEqualToAnchor:self.view.keyboardLayoutGuide.topAnchor],[stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:20],[stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:20],[stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-20],[stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-24],[stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-40]]];
    NSDictionary *p=TIOProfile();NSArray *labels=@[@"Name (Up to 80 chars)",@"Identity & Background (Up to 500 chars)",@"Response Preferences / Custom Prompts (Up to 2000 chars)"];
    for(NSUInteger i=0;i<3;i++){UILabel *label=[UILabel new];label.text=labels[i];label.font=[UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];[stack addArrangedSubview:label];
        if(i<2){UITextField *field=[UITextField new];field.borderStyle=UITextBorderStyleRoundedRect;field.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody];field.text=p[i?@"identity":@"name"];field.placeholder=i?@"e.g. Software developer interested in AI":@"How you want AI to address you";[field.heightAnchor constraintGreaterThanOrEqualToConstant:48].active=YES;[stack addArrangedSubview:field];if(i)self.identityField=field;else self.nameField=field;}
        else{self.preferences=[UITextView new];self.preferences.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody];self.preferences.backgroundColor=UIColor.secondarySystemGroupedBackgroundColor;self.preferences.layer.cornerRadius=12;self.preferences.textContainerInset=UIEdgeInsetsMake(12,12,12,12);self.preferences.text=p[@"preferences"];[self.preferences.heightAnchor constraintEqualToConstant:200].active=YES;[stack addArrangedSubview:self.preferences];}
    }
    UILabel *note=[UILabel new];note.numberOfLines=0;note.font=[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];note.textColor=UIColor.secondaryLabelColor;note.text=@"Default is empty. Saved profiles take effect on next custom model query; does not modify official model.\nStored locally on device and sent with queries to your model provider.";[stack addArrangedSubview:note];
}
- (void)save{BOOL ok=TIOSaveProfile(@{@"name":self.nameField.text?:@"",@"identity":self.identityField.text?:@"",@"preferences":self.preferences.text?:@""});if(ok){[self.view endEditing:YES];[self.navigationController popViewControllerAnimated:YES];}else{UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Not Saved" message:@"Please check length and remove control characters." preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];[self presentViewController:a animated:YES completion:nil];}}
@end
void TIOOpenProfile(UIViewController *host){[host.navigationController pushViewController:[TIOProfilePanel new] animated:YES];}
