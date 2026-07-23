#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^ZoidSafariExtensionStateHandler)(BOOL enabled, BOOL available);

FOUNDATION_EXPORT void ZoidGetSafariExtensionState(
  NSString *extensionIdentifier,
  ZoidSafariExtensionStateHandler handler
);

NS_ASSUME_NONNULL_END
