#import "NewsPresentation.h"
unsigned TIONewsPlaybackCommand(NSDictionary *s){if(![s[@"ready"] boolValue]||[s[@"stopping"] boolValue])return 0;return [s[@"playing"] boolValue]?4:([s[@"started"] boolValue]?5:3);}
NSDictionary *TIONewsPresentation(NSDictionary *s,BOOL busy,NSUInteger characters){
    NSString *title,*detail;BOOL available=[s[@"available"] boolValue],active=[s[@"active"] boolValue];
    if([s[@"stopping"] boolValue]){title=@"Exiting Glasses Teleprompter";detail=@"Awaiting glasses confirmation; do not resend.";}
    else if(active){title=[s[@"playing"] boolValue]?@"Reading on Glasses":([s[@"ready"] boolValue]?@"Article Ready":@"Transferring Article");detail=s[@"state"]?:@"Awaiting glasses confirmation";}
    else if(!available){title=@"Prepare Teleprompter First";detail=@"1  In official app, open a short note and choose steady scroll.\n2  Start and confirm scrolling on glasses, then exit.\n3  Return to News tab and send article.\n\nRequired once after app restart. Full text readable on phone anytime.";}
    else {title=@"Teleprompter Ready";detail=@"Ready to send this batch of news to glasses.";}
    return @{@"title":title,@"detail":detail,@"needsPreparation":@(!available&&!active),@"canFetch":@(!busy&&!active),@"canSend":@(available&&!active&&!busy&&characters>0),@"canPlay":@(!busy&&TIONewsPlaybackCommand(s)!=0),@"canStop":@(active&&!([s[@"stopping"] boolValue])),@"canTest":@(available&&!active&&!busy)};
}
