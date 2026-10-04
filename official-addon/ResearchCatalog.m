#import "ResearchCatalog.h"
static NSDictionary *Row(NSString *key,NSString *title,NSString *icon,NSInteger section,NSInteger row){return @{@"key":key,@"title":title,@"icon":icon,@"section":@(section),@"row":@(row)};}
NSArray<NSDictionary *> *TIOResearchSections(NSString *page){
    if([page isEqual:@"model"])return @[
        @{@"title":@"Custom Agents Control",@"rows":@[Row(@"agent",@"Execute Agent",@"cpu",-2,0),Row(@"knowledge",@"Knowledge Base & Sources",@"books.vertical",-2,1)]},
        @{@"title":@"Response Mode",@"rows":@[Row(@"mode",@"Current Mode",@"square.stack.3d.up",0,0)]},
        @{@"title":@"Custom Model",@"rows":@[Row(@"api",@"Endpoint & API Key",@"cube",0,1),Row(@"thinking",@"Disable Deep Thinking",@"bolt",0,3)]},
        @{@"title":@"Web & Tools",@"rows":@[Row(@"search",@"Enable Web Search",@"globe",0,7),Row(@"searchKey",@"Search API Configuration",@"key",0,8),Row(@"tools",@"Available Model Tools",@"wrench.and.screwdriver",0,11)]},
        @{@"title":@"Voice & Context",@"rows":@[Row(@"exit",@"Voice Exit Commands",@"waveform",0,6),Row(@"prompt",@"User Profile & System Prompt",@"text.bubble",0,5),Row(@"history",@"Conversation History",@"clock.arrow.circlepath",0,4)]},
        @{@"title":@"Glasses Voice TTS · Experimental",@"rows":@[Row(@"tts",@"Synchronous Speech",@"waveform.circle",-2,13),Row(@"ttsEngine",@"TTS Engine",@"slider.horizontal.3",-2,16),Row(@"ttsKey",@"Aliyun Flash TTS Key",@"key",-2,14),Row(@"ttsTest",@"Play Test Voice",@"play.circle",-2,15)]}];
    if([page isEqual:@"library"])return @[
#if TIO_LOCAL_TRANSLATION
        @{@"title":@"Offline Subtitles & Translation · iOS 18+",@"rows":@[Row(@"localTranslation",@"Apple / Hy-MT2 Translation",@"character.bubble",-2,21)]},
#endif
#if TIO_MUSIC
        @{@"title":@"Music Player",@"rows":@[Row(@"music",@"NetEase Music · Menu Item",@"music.note",-2,20)]},
#endif
        @{@"title":@"Maps & Glasses Navigation",@"rows":@[Row(@"navigation",@"Walk / Cycle / Drive Navigation",@"map",-3,0)]},
        @{@"title":@"Recordings & Summaries",@"rows":@[Row(@"recordings",@"Recordings & File Sharing",@"waveform",-1,0),Row(@"summary",@"Transcript Summaries",@"text.badge.star",-1,1)]},
        @{@"title":@"Lifelog",@"rows":@[Row(@"lifelogText",@"Saved Text",@"doc.text",-1,2),Row(@"lifelogAudio",@"Audio Sharing",@"waveform.circle",-1,3),Row(@"capture",@"Capture Final Recognized Text",@"square.and.arrow.down",1,0),Row(@"archive",@"Export Archive",@"square.and.arrow.up",1,1)]}];
    if([page isEqual:@"diagnostics"])return @[
#if TIO_OTA_RESEARCH_ENABLED
#if TIO_MUSIC
        @{@"title":@"TMU1 Research Firmware · High Risk",@"rows":@[Row(@"experimentalOTA",@"TMU1 Music Firmware",@"exclamationmark.shield",-4,0),Row(@"displayPhone",@"Turbo Display · Image Test",@"rectangle.connected.to.line.below",-4,1)]},
#elif TIO_NATIVE_NAV
        @{@"title":@"TNV1 Research Firmware · High Risk",@"rows":@[Row(@"experimentalOTA",@"TNV1 Navigation Firmware",@"exclamationmark.shield",-4,0),Row(@"displayPhone",@"Turbo Display · Image Test",@"rectangle.connected.to.line.below",-4,1)]},
#else
        @{@"title":@"High Risk Firmware Experiments",@"rows":@[Row(@"experimentalOTA",@"R3 Experimental Firmware",@"exclamationmark.shield",-4,0)]},
#endif
#endif
        @{@"title":@"System Status",@"rows":@[Row(@"status",@"Adapters & Hooks",@"checkmark.shield",2,0)]},
        @{@"title":@"Manual Diagnostics",@"rows":@[Row(@"apiTest",@"Test LLM API",@"bubble.left.and.bubble.right",0,2),Row(@"searchTest",@"Test Web Search",@"globe",0,9),Row(@"todoTest",@"Test Todo Protocol",@"checklist",0,10)]}];
    return @[];
}
