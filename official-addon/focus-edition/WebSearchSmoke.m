// Native Mac smoke test of the EXACT Foundation implementation linked on iOS.
// Reads credentials as JSON on stdin. Never stores or logs them.
#import "WebSearch.h"
#import "Core.h"
int main(void){@autoreleasepool{
    NSData *data=[NSFileHandle.fileHandleWithStandardInput readDataToEndOfFile];
    NSDictionary *keys=[NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if(![keys isKindOfClass:NSDictionary.class]||![keys[@"deepseek"] isKindOfClass:NSString.class]||![keys[@"tinyfish"] isKindOfClass:NSString.class])return 2;
    NSString *q=NSProcessInfo.processInfo.environment[@"TIO_SMOKE_QUESTION"]?:@"Please actually search the official address of TinyFish Search API online, use a Chinese description and attach the official source URL.";
    NSMutableDictionary *payload=[TIOChatRequest(@"deepseek-flash",q) mutableCopy];payload[@"thinking"]=@{@"type":@"disabled"};
    __block BOOL ended=NO,failed=NO;__block NSUInteger updates=0;__block NSString *last=@"";NSDate *start=NSDate.date;
    TIOWebChatRequest *r=[TIOWebChatRequest new];__weak TIOWebChatRequest *weak=r;
    r.update=^(NSString *text,BOOL done,NSString *error){if(last.length&&![text hasPrefix:last])abort();last=text;updates++;if(done){ended=YES;failed=error!=nil;NSDictionary *out=@{@"done":@YES,@"searchCount":@(weak.searchCount),@"elapsedMs":@((NSInteger)(-[start timeIntervalSinceNow]*1000)),@"updates":@(updates),@"answer":text,@"error":error?:NSNull.null};NSString *safe=[[NSString alloc]initWithData:[NSJSONSerialization dataWithJSONObject:out options:0 error:nil] encoding:NSUTF8StringEncoding];for(NSString *k in @[@"deepseek",@"tinyfish"])if([keys[k] length])safe=[safe stringByReplacingOccurrencesOfString:keys[k] withString:@"[REDACTED]"];puts(safe.UTF8String);}};
    [r startEndpoint:[NSURL URLWithString:@"https://api.deepseek.com/chat/completions"] key:keys[@"deepseek"] payload:payload searchKey:keys[@"tinyfish"]];
    while(!ended&&-[start timeIntervalSinceNow]<125)[NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    if(!ended)[r cancel];return ended&&!failed?0:1;
}}
