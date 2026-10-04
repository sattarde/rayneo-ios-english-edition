#import "A2UIProbe.h"
// Small, explicit subset recovered from Strix OS 1.0.3.15. Not a general UI SDK.
static void Var(NSMutableData *d,uint64_t n){do{uint8_t b=n&127;n>>=7;if(n)b|=128;[d appendBytes:&b length:1];}while(n);}
static BOOL Read(const uint8_t *b,NSUInteger size,NSUInteger *at,uint64_t *v){*v=0;for(unsigned i=0;i<10;i++){if(*at>=size)return NO;uint8_t x=b[(*at)++];if(i==9&&(x&254))return NO;*v|=(uint64_t)(x&127)<<(i*7);if(!(x&128))return YES;}return NO;}
static BOOL ID(NSString *s){return [s isKindOfClass:NSString.class]&&[s hasPrefix:@"turbo_ui_"]&&s.length<=63&&s.length>9&&[s rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyz0123456789_"].invertedSet].location==NSNotFound;}
BOOL TIOA2UITransportAllowed(BOOL query,BOOL context,BOOL active,NSTimeInterval age,BOOL pending){return context&&active&&!pending&&(query||(age>=0&&age<120));}
NSData *TIOA2UIPacket(uint32_t type,uint32_t sequence,NSDictionary *json){
    if(!type||![json isKindOfClass:NSDictionary.class]||![NSJSONSerialization isValidJSONObject:json])return nil;
    NSData *j=[NSJSONSerialization dataWithJSONObject:json options:NSJSONWritingSortedKeys error:nil];if(!j.length||j.length>7500)return nil;
    NSMutableData *d=[NSMutableData new];Var(d,8);Var(d,1);Var(d,16);Var(d,type);Var(d,26);Var(d,j.length);[d appendData:j];if(sequence){Var(d,40);Var(d,sequence);}return d.length<=8192?d:nil;
}
NSDictionary *TIOA2UIDecode(NSData *data){
    if(![data isKindOfClass:NSData.class]||!data.length||data.length>8192)return nil;
    NSUInteger at=0;const uint8_t *b=data.bytes;NSMutableSet *seen=[NSMutableSet new];uint64_t version=0,type=0,sequence=0,mode=0;NSData *j=nil;
    while(at<data.length){uint64_t k,n;if(!Read(b,data.length,&at,&k)||!(k>>3)||(k>>3)>6)return nil;unsigned field=(unsigned)(k>>3),wire=k&7;if([seen containsObject:@(field)])return nil;[seen addObject:@(field)];
        if(field==3||field==4){if(wire!=2||!Read(b,data.length,&at,&n)||n>data.length-at)return nil;if(field==4&&n)return nil;if(field==3)j=[data subdataWithRange:NSMakeRange(at,(NSUInteger)n)];at+=(NSUInteger)n;}
        else{if(wire||!Read(b,data.length,&at,&n)||n>UINT32_MAX)return nil;if(field==1)version=n;if(field==2)type=n;if(field==5)sequence=n;if(field==6)mode=n;}}
    if(version!=1||!type||!j.length)return nil;id obj=[NSJSONSerialization JSONObjectWithData:j options:0 error:nil];return [obj isKindOfClass:NSDictionary.class]?@{@"type":@(type),@"sequence":@(sequence),@"mode":@(mode),@"json":obj}:nil;
}
NSDictionary *TIOA2UIInstall(NSString *identifier,BOOL layout){
    if(!ID(identifier))return nil;
    NSArray *components=layout?@[
        @{@"id":@"root",@"component":@"Column",@"children":@[@"title",@"line",@"content"],@"align":@"stretch"},
        @{@"id":@"title",@"component":@"Text",@"text":@"Turbo IO Custom Layout 8642",@"variant":@"h3"},
        @{@"id":@"line",@"component":@"Divider",@"axis":@"horizontal"},
        @{@"id":@"content",@"component":@"Row",@"children":@[@"icon",@"body"],@"align":@"center"},
        @{@"id":@"icon",@"component":@"Icon",@"name":@"sunny"},
        @{@"id":@"body",@"component":@"Text",@"text":@"Icon + Horizontal Text\nSecond Line Verification 8642",@"variant":@"body"}]:@[@{@"id":@"root",@"component":@"Text",@"text":@"Turbo IO Custom UI 7392",@"variant":@"body"}];
    NSDictionary *extra=@{@"widgetId":identifier,@"name":@"Turbo IO UI Test",@"uiContent":@{@"createSurface":@{@"surfaceId":identifier,@"catalogId":@"https://rayneo.com/a2ui/catalogs/glasses-base/v1/catalog.json"},@"updateComponents":@{@"surfaceId":identifier,@"components":components}}};
    NSString *text=[[NSString alloc]initWithData:[NSJSONSerialization dataWithJSONObject:extra options:NSJSONWritingSortedKeys error:nil] encoding:NSUTF8StringEncoding];
    return @{@"cmd":@"widget_install",@"payload":@{@"data":@{@"type":@"a2ui",@"id":identifier,@"name":@"Turbo IO UI Test",@"extras":text}}};
}
NSDictionary *TIOA2UIUninstall(NSString *identifier){return ID(identifier)?@{@"cmd":@"widget_uninstall",@"payload":@{@"data":@{@"id":identifier}}}:nil;}
