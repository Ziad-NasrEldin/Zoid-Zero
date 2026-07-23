#import "ZoidSafariBridge.h"
#import <SafariServices/SafariServices.h>

void ZoidGetSafariExtensionState(
  NSString *extensionIdentifier,
  ZoidSafariExtensionStateHandler handler
) {
  [SFSafariExtensionManager
    getStateOfSafariExtensionWithIdentifier:extensionIdentifier
    completionHandler:^(SFSafariExtensionState *state, NSError *error) {
      handler(state.enabled, state != nil && error == nil);
    }];
}
