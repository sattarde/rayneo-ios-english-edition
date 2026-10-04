#import "Profile.h"
static NSUserDefaults *Store(void){return [[NSUserDefaults alloc]initWithSuiteName:@"io.turboio.official-profile"];}
NSDictionary *TIOValidatedProfile(NSDictionary *value){
    if(![value isKindOfClass:NSDictionary.class])return nil;
    NSDictionary *limits=@{@"name":@80,@"identity":@500,@"preferences":@2000};
    for(id key in value)if(!limits[key])return nil;
    NSMutableDictionary *result=[NSMutableDictionary new];
    for(NSString *key in limits){id raw=value[key]?:@"";if(![raw isKindOfClass:NSString.class]||[raw length]>[limits[key] unsignedIntegerValue])return nil;
        NSMutableCharacterSet *invalid=[NSCharacterSet.controlCharacterSet mutableCopy];[invalid removeCharactersInString:@"\n\t"];
        if([raw rangeOfCharacterFromSet:invalid].location!=NSNotFound)return nil;
        result[key]=[raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    }return result;
}
NSDictionary *TIOProfile(void){return TIOValidatedProfile([Store() dictionaryForKey:@"profile"])?:@{@"name":@"",@"identity":@"",@"preferences":@""};}
BOOL TIOSaveProfile(NSDictionary *value){NSDictionary *valid=TIOValidatedProfile(value);if(!valid)return NO;[Store() setObject:valid forKey:@"profile"];return YES;}
NSString *TIOProfilePrompt(NSDictionary *value){NSDictionary *p=TIOValidatedProfile(value);if(!p)return @"";NSMutableArray *lines=[NSMutableArray new];
    if([p[@"name"] length])[lines addObject:[@"User wishes to be addressed as:" stringByAppendingString:p[@"name"]]];
    if([p[@"identity"] length])[lines addObject:[@"Identity and background provided by the user:" stringByAppendingString:p[@"identity"]]];
    if([p[@"preferences"] length])[lines addObject:[@"User-set answer preferences:" stringByAppendingString:p[@"preferences"]]];
    return [lines componentsJoinedByString:@"\n"];
}
