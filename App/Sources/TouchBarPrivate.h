#import <AppKit/AppKit.h>

// Private DFRFoundation / NSTouchBar APIs (undocumented).
// Same class of APIs used by BetterTouchTool, MTMR, etc.
// Not App Store-safe; macOS updates can break these without notice.

extern void DFRElementSetControlStripPresenceForIdentifier(NSTouchBarItemIdentifier identifier, BOOL presence);
extern void DFRSystemModalShowsCloseBoxWhenFrontMost(BOOL show);

@interface NSTouchBarItem (TouchBarChatPrivate)
+ (void)addSystemTrayItem:(NSTouchBarItem *)item;
@end

@interface NSTouchBar (TouchBarChatPrivate)
+ (void)presentSystemModalTouchBar:(NSTouchBar *)touchBar
                         placement:(long long)placement
         systemTrayItemIdentifier:(NSTouchBarItemIdentifier)identifier;
+ (void)minimizeSystemModalTouchBar:(NSTouchBar *)touchBar;
@end
