#import "WeReadAPI.h"
#import <Security/Security.h>
#import "WeReadCoverPolicy.h"
static NSDictionary *KeyQuery(void){return @{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,(__bridge id)kSecAttrService:@"TurboIOWeReadV1",(__bridge id)kSecAttrAccount:@"gateway"};}
NSString *TWAPIKey(void){NSMutableDictionary *q=[KeyQuery() mutableCopy];q[(__bridge id)kSecReturnData]=@YES;CFTypeRef d=NULL;if(SecItemCopyMatching((__bridge CFDictionaryRef)q,&d)!=errSecSuccess)return @"";return [[NSString alloc]initWithData:CFBridgingRelease(d) encoding:NSUTF8StringEncoding]?:@"";}
BOOL TWSetAPIKey(NSString *key){if(!key.length)return SecItemDelete((__bridge CFDictionaryRef)KeyQuery())==errSecSuccess;
 if(![key hasPrefix:@"wrk-"]||key.length>256||[key rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].location!=NSNotFound)return NO;
 NSData *d=[key dataUsingEncoding:NSUTF8StringEncoding];OSStatus s=SecItemUpdate((__bridge CFDictionaryRef)KeyQuery(),(__bridge CFDictionaryRef)@{(__bridge id)kSecValueData:d});if(s==errSecItemNotFound){NSMutableDictionary *q=[KeyQuery()mutableCopy];q[(__bridge id)kSecValueData]=d;q[(__bridge id)kSecAttrAccessible]=(__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;s=SecItemAdd((__bridge CFDictionaryRef)q,NULL);}return s==errSecSuccess;
}
@interface TWHTTP:NSObject<NSURLSessionDataDelegate>
@property NSURLSession *session;
@property NSMutableData *data;
@property NSUInteger limit;
@property BOOL cover;
@property unsigned redirects;
@property NSString *failure;
@property(copy) void(^done)(NSData *,NSString *);
@end
@implementation TWHTTP
- (void)URLSession:(NSURLSession *)s task:(NSURLSessionTask *)t willPerformHTTPRedirection:(NSHTTPURLResponse *)r newRequest:(NSURLRequest *)q completionHandler:(void(^)(NSURLRequest *))h{
 NSURL *safe=self.cover?TWCoverURL(q.URL.absoluteString):nil;
 if(safe&&self.redirects<3){self.redirects++;h([NSURLRequest requestWithURL:safe]);return;}
 self.failure=@"Redirect target not in cover whitelist";h(nil);
}
- (void)URLSession:(NSURLSession *)s dataTask:(NSURLSessionDataTask *)t didReceiveResponse:(NSURLResponse *)r completionHandler:(void(^)(NSURLSessionResponseDisposition))h{NSInteger status=[r isKindOfClass:NSHTTPURLResponse.class]?[(NSHTTPURLResponse *)r statusCode]:0;
 if(status!=200||r.expectedContentLength>(int64_t)self.limit){self.failure=status!=200?[NSString stringWithFormat:@"HTTP %ld",(long)status]:@"Image or response exceeds size limit";h(NSURLSessionResponseCancel);}else h(NSURLSessionResponseAllow);}
- (void)URLSession:(NSURLSession *)s dataTask:(NSURLSessionDataTask *)t didReceiveData:(NSData *)d{if(d.length>self.limit-self.data.length){self.failure=@"Response too large";[t cancel];return;}[self.data appendData:d];}
- (void)URLSession:(NSURLSession *)s task:(NSURLSessionTask *)t didCompleteWithError:(NSError *)e{NSString *failure=self.failure?: (e?[NSString stringWithFormat:@"Network error %ld",(long)e.code]:nil);void(^done)(NSData *,NSString *)=self.done;self.done=nil;[self.session finishTasksAndInvalidate];self.session=nil;if(done)done(failure?nil:self.data,failure);}
@end
static void Fetch(NSURLRequest *request,NSUInteger limit,BOOL cover,void(^done)(NSData *,NSString *)){TWHTTP *h=[TWHTTP new];h.limit=limit;h.cover=cover;h.data=[NSMutableData new];h.done=done;NSURLSessionConfiguration *c=NSURLSessionConfiguration.ephemeralSessionConfiguration;c.HTTPShouldSetCookies=NO;c.HTTPCookieStorage=nil;c.URLCache=nil;c.timeoutIntervalForRequest=25;c.timeoutIntervalForResource=35;h.session=[NSURLSession sessionWithConfiguration:c delegate:h delegateQueue:NSOperationQueue.mainQueue];[[h.session dataTaskWithRequest:request]resume];}
void TWRequest(NSString *path,NSDictionary *parameters,void(^done)(NSDictionary *,NSString *)){
 NSCAssert(NSThread.isMainThread,@"main");NSString *key=TWAPIKey();if(!key.length){done(nil,@"Please configure WeChat Reading Key first");return;}
 if(![@[@"/shelf/sync",@"/readdata/detail"]containsObject:path]){done(nil,@"Interface not enabled");return;}
 NSMutableDictionary *body=[parameters mutableCopy]?:[NSMutableDictionary new];body[@"api_name"]=path;body[@"skill_version"]=@"1.0.4";
 NSMutableURLRequest *r=[NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://i.weread.qq.com/api/agent/gateway"]];r.HTTPMethod=@"POST";r.HTTPBody=[NSJSONSerialization dataWithJSONObject:body options:0 error:nil];[r setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];[r setValue:[@"Bearer " stringByAppendingString:key]forHTTPHeaderField:@"Authorization"];
 Fetch(r,4*1024*1024,NO,^(NSData *d,NSString *error){if(error){done(nil,error);return;}id j=[NSJSONSerialization JSONObjectWithData:d options:0 error:nil];if(![j isKindOfClass:NSDictionary.class]){done(nil,@"The gateway return format is invalid");return;}if(j[@"upgrade_info"]){done(nil,@"WeChat Reading requires updating Skill, and the interface call has been suspended.");return;}if(j[@"errcode"]&&![j[@"errcode"]isEqual:@0]){done(nil,@"WeChat reading authentication or request failed, please check the configuration");return;}id data=j[@"data"];done([data isKindOfClass:NSDictionary.class]?data:j,nil);});
}
void TWCover(NSString *url,void(^done)(NSData *,NSString *)){NSURL *u=TWCoverURL(url);
 if(!u){done(nil,@"No cover or cover domain name is not allowed");return;}
 // This is a separate request. Never forward the API credential to the CDN.
 Fetch([NSURLRequest requestWithURL:u],TW_COVER_LIMIT,YES,done);
}
