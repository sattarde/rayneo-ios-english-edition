#import "NewsPresentation.h"
unsigned TIONewsPlaybackCommand(NSDictionary *s){if(![s[@"ready"] boolValue]||[s[@"stopping"] boolValue])return 0;return [s[@"playing"] boolValue]?4:([s[@"started"] boolValue]?5:3);}
NSDictionary *TIONewsPresentation(NSDictionary *s,BOOL busy,NSUInteger characters){
    NSString *title,*detail;BOOL available=[s[@"available"] boolValue],active=[s[@"active"] boolValue];
    if([s[@"stopping"] boolValue]){title=@"Exiting glasses reading";detail=@"Waiting for glasses confirmation; do not re-send.";}
    else if(active){title=[s[@"playing"] boolValue]?@"Glasses reading in progress":([s[@"ready"] boolValue]?@"Article ready":@"Transferring article");detail=s[@"state"]?:@"Waiting for glasses confirmation";}
    else if(!available){title=@"Waiting for connection or setup";detail=@"Confirm official app is connected to glasses. Saved configurations restore automatically.\n\nFirst setup: choose a short article, prepare, start, and exit once in steady mode. Saved after full receipt.";}
    else if([s[@"automaticInitialization"] boolValue]){title=@"Prepares teleprompter on send";detail=@"Built-in steady config loaded. After sending, waits for glasses file confirmation before starting playback.";}
    else if([s[@"templateSaveError"] length]){title=@"Ready for session, config not saved";detail=[NSString stringWithFormat:@"%@. Article can be sent, but restart recovery not ready.",s[@"templateSaveError"]];}
    else {title=@"Teleprompter ready";detail=[s[@"templateSaved"] boolValue]?@"Configuration saved; restores automatically after restart.":@"Ready to send article. Initialized status does not guarantee active link.";}
    return @{@"title":title,@"detail":detail,@"needsPreparation":@(!available&&!active),@"canFetch":@(!busy&&!active),@"canSend":@(available&&!active&&!busy&&characters>0),@"canPlay":@(!busy&&TIONewsPlaybackCommand(s)!=0),@"canStop":@(active&&!([s[@"stopping"] boolValue])),@"canTest":@(available&&!active&&!busy)};
}
