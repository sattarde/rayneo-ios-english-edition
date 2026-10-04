#import <UIKit/UIKit.h>
UIViewController *TDPPhoneController(void);
BOOL TDPPhoneConsumeEvent(NSDictionary *event);
BOOL TDPPhoneRouteReply(NSDictionary *event,void(^completion)(BOOL));
// Main-thread-only: do not authorize OTA over an uncertain file task.
BOOL TDPPhonePauseForOTA(void);
BOOL TDPPhoneNavigationStart(NSDictionary *frame);
void TDPPhoneNavigationOffer(NSDictionary *frame);
void TDPPhoneNavigationPump(void);
void TDPPhoneNavigationStop(void);
NSDictionary *TDPPhoneNavigationStatus(void);
UIImage *TDPPhoneNavigationRender(NSDictionary *frame);
void TDPPhoneStartKeepalive(void);
BOOL TDPPhoneMusicStart(void);
void TDPPhoneMusicStop(void);
NSDictionary *TDPPhoneMusicStatus(void);
UIImage *TDPPhoneMusicRender(void);
