// NativeNavStubs.m — Safe no-op stubs for native navigation/display symbols
// that the focus-edition references but which live in firmware-research modules.
// These stubs allow building the phone-side features (music, reading, focus,
// new UI) without pulling in any firmware OTA or glasses-side flash code.
// The native glasses apps won't work without matching firmware, but all
// phone-side features function normally.

#import <Foundation/Foundation.h>

// --- DisplayDiagnostics stubs ---
// TDPDiagConfigure: sets up a diagnostic log file for display transport events
// TDPDiagRecord: records a diagnostic event with key-value pairs
// Without real implementation, diagnostics are simply not collected.

void TDPDiagConfigure(NSURL *file) {
    // No-op: diagnostics disabled in stub build
}

void TDPDiagRecord(NSString *event, NSDictionary *values) {
    // No-op: diagnostics disabled in stub build
}

// --- NativeNavigation stubs ---
// TNVDecodeReply: decodes a glasses-side native navigation reply packet
// TNVPauseForOTA: checks if native nav session is idle (safe to flash)
// Without real implementation, native nav features report "not available".

typedef struct { int type; int code; } TNReply;

_Bool TNVDecodeReply(NSDictionary *event, TNReply *out) {
    return 0; // No native nav session — nothing to decode
}

_Bool TNVPauseForOTA(void) {
    return 1; // Always safe — no native nav session running
}
