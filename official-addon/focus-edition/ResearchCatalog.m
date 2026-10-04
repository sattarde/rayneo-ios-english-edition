#import "ResearchCatalog.h"
static NSDictionary *Row(NSString *key,NSString *title,NSString *icon,NSInteger section,NSInteger row){return @{@"key":key,@"title":title,@"icon":icon,@"section":@(section),@"row":@(row)};}
NSArray<NSDictionary *> *LegacySections(NSString *page){
    if([page isEqual:@"model"])return @[
        @{@"title":@"Translation & Subtitles",@"rows":@[Row(@"localTranslation",@"Apple / Hy-MT2 Local Translation",@"character.bubble",-2,22)]},
        @{@"title":@"Agent Controls",@"rows":@[Row(@"agent",@"Execute Agent",@"cpu",-2,0),Row(@"knowledge",@"Knowledge Base & Sources",@"books.vertical",-2,1)]},
        @{@"title":@"Response Mode",@"rows":@[Row(@"mode",@"Response Mode",@"square.stack.3d.up",0,0)]},
        @{@"title":@"Custom Model",@"rows":@[Row(@"api",@"API Endpoint & Key",@"cube",0,1),Row(@"thinking",@"Disable Deep Thinking",@"bolt",0,3)]},
        @{@"title":@"Voice TTS",@"rows":@[Row(@"tts",@"Synchronous Speech",@"waveform.circle",-2,13),Row(@"ttsEngine",@"TTS Engine",@"slider.horizontal.3",-2,16),Row(@"ttsKey",@"Aliyun Flash TTS Key",@"key",-2,14),Row(@"ttsTest",@"Play Test Voice",@"play.circle",-2,15)]},
        @{@"title":@"Web & Tools",@"rows":@[Row(@"search",@"Enable Web Search",@"globe",0,7),Row(@"searchKey",@"Search Service Config",@"key",0,8),Row(@"tools",@"Model Tools",@"wrench.and.screwdriver",0,11)]},
        @{@"title":@"Context & Voice",@"rows":@[Row(@"exit",@"Voice Exit Commands",@"waveform",0,6),Row(@"prompt",@"System Prompt",@"text.bubble",0,5),Row(@"history",@"Conversation History",@"clock.arrow.circlepath",0,4)]}];
    if([page isEqual:@"library"])return @[
        @{@"title":@"Reading",@"rows":@[Row(@"weread",@"WeRead · Menu Item 11",@"books.vertical",-2,21)]},
        @{@"title":@"Music",@"rows":@[Row(@"music",@"NetEase Music · Menu Item 10",@"music.note",-2,20)]},
        @{@"title":@"Recordings",@"rows":@[Row(@"recordings",@"Recordings & File Sharing",@"waveform",-1,0),Row(@"summary",@"Transcript Summaries",@"text.badge.star",-1,1)]},
        @{@"title":@"Lifelog",@"rows":@[Row(@"lifelogText",@"Saved Notes & Text",@"doc.text",-1,2),Row(@"lifelogAudio",@"Audio Notes & Sharing",@"waveform.circle",-1,3),Row(@"capture",@"Capture Final Text",@"square.and.arrow.down",1,0),Row(@"archive",@"Export Text Archive",@"square.and.arrow.up",1,1)]},
        @{@"title":@"Navigation",@"rows":@[Row(@"navigation",@"Walk / Cycle / Drive Navigation",@"location.north.line",-2,4)]}];
    if([page isEqual:@"diagnostics"])return @[
        @{@"title":@"Diagnostics",@"rows":@[Row(@"diagnosticsRuntime",@"Glasses Runtime Status · TDG1",@"gauge.with.dots.needle.67percent",-2,21)]},
        @{@"title":@"Navigation Display",@"rows":@[Row(@"subtitleHUD",@"Subtitle Navigation HUD",@"text.bubble",-2,5)]},
        @{@"title":@"Runtime Status",@"rows":@[Row(@"status",@"Adapters & Callbacks",@"checkmark.shield",2,0),Row(@"glassesLog",@"Glasses Logs · Device Only",@"doc.text.magnifyingglass",-2,3)]},
        @{@"title":@"Manual Tests",@"rows":@[Row(@"a2ui",@"Custom UI Verification",@"rectangle.3.group",-2,2),Row(@"apiTest",@"Test Model API",@"bubble.left.and.bubble.right",0,2),Row(@"searchTest",@"Test Web Search",@"globe",0,9),Row(@"todoTest",@"Todo Protocol Verification",@"checklist",0,10)]},
        @{@"title":@"Firmware Research",@"rows":@[
#if TIO_IMAGE_RX_LAB
#if TIO_DISPLAY_PHONE
        Row(@"displayPhone",@"Display Mirroring · PHONE 06",@"rectangle.connected.to.line.below",-2,8),
#endif
        Row(@"imageRXLab",@"Image Transfer Lab · FIX 01",@"photo",-2,7),
#endif
#if TIO_DISPLAY_FLASH
        Row(@"experimentalOTA",@"TFP1 Pomodoro Firmware",@"shippingbox",-2,6)]}];
#else
        Row(@"experimentalOTA",@"Experimental Firmware",@"shippingbox",-2,6)]}];
#endif
    return @[];
}

NSArray<NSDictionary *> *TIOResearchSections(NSString *page){
 NSMutableDictionary *lookup=[NSMutableDictionary new];for(NSString *p in @[@"model",@"library",@"diagnostics"])for(NSDictionary *section in LegacySections(p))for(NSDictionary *r in section[@"rows"])lookup[r[@"key"]]=r;
 NSArray *groups=nil;
 if([page isEqual:@"model"])groups=@[@[@"Daily Chat",@"mode",@"tts",@"search"],@[@"Model & API",@"api",@"thinking"],@[@"Voice Settings",@"ttsEngine",@"ttsTest",@"ttsKey",@"exit"],@[@"Agent & Tools",@"agent",@"knowledge",@"tools",@"searchKey"],@[@"Prompt & Memory",@"prompt",@"history"]];
 if([page isEqual:@"library"])groups=@[@[@"Apps",@"music",@"weread",@"navigation",@"localTranslation",@"recordings"],@[@"Text Summaries",@"summary"],@[@"Lifelog",@"lifelogText",@"lifelogAudio",@"capture",@"archive"]];
 if([page isEqual:@"diagnostics"])groups=@[@[@"Logs",@"diagnosticsRuntime",@"glassesLog",@"status"],@[@"Protocol Experiments",@"subtitleHUD",@"a2ui",@"apiTest",@"searchTest",@"todoTest"],@[@"Display",@"displayPhone",@"imageRXLab"],@[@"Experimental OTA · HIGH RISK",@"experimentalOTA"]];
 if(!groups)return @[];NSMutableArray *sections=[NSMutableArray new];NSDictionary *names=@{@"music":@"Music",@"weread":@"WeRead",@"navigation":@"Navigation",@"localTranslation":@"Translation & Subtitles",@"recordings":@"Recordings & Sharing"};
 for(NSArray *group in groups){NSMutableArray *rows=[NSMutableArray new];for(NSUInteger i=1;i<group.count;i++){NSDictionary *r=lookup[group[i]];if(r){NSMutableDictionary *m=[r mutableCopy];if(names[group[i]])m[@"title"]=names[group[i]];[rows addObject:m];}}if(rows.count)[sections addObject:@{@"title":group[0],@"rows":rows}];}return sections;
}
