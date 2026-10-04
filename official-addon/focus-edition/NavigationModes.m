#import "NavigationModes.h"

NSArray *TIONavigationModeTitles(void){return @[@"Walk",@"Cycle",@"Drive"];}
NSString *TIONavigationModeTitle(NSInteger mode){return mode>=0&&mode<3?TIONavigationModeTitles()[mode]:nil;}
Class TIONavigationManagerClass(NSInteger mode){(void)mode;return Nil;}
BOOL TIONavigationCalculate(id manager,NSInteger mode,BOOL simulated,id start,id end){(void)manager;(void)mode;(void)simulated;(void)start;(void)end;return YES;}
BOOL TIONavigationMayChangeMode(BOOL active,BOOL ready){return !active||ready;}
