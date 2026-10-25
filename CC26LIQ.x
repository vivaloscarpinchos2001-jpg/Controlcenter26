#import "CC26.h"
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>
#import <objc/runtime.h>
#include <stdio.h>
#include <stdarg.h>
#include <string.h>
#include <notify.h>
#include <mach-o/dyld.h>

static NSString * const kCC26LIQPrefsDomain       = @"dylv.liquidassprefs";
static NSString * const kCC26LIQReloadNote        = @"dylv.liquidassprefs/Reload";
static NSString * const kCC26LIQGroupName         = @"dylv.liquidglass.sharedGroup";
static NSString * const kCC26LIQControlCenterType = @"dylv.liquidglass.cc.r2";
static const NSInteger  kCC26LIQGlassTag          = 190001;

static NSString *sCC26LIQActiveFilterType = nil;
static BOOL      sCC26LIQLiquidassFound = NO;
static BOOL      sCC26LIQLoggedProbe = NO;

#ifdef __cplusplus
extern "C" {
#endif
BOOL CC26LIQIsActive(void);
id CC26LIQBuildGlassFilter(void);
#ifdef __cplusplus
}
#endif

typedef id (*CC26LIQFilterFactoryFn)(Class, SEL, NSString *);

static void CC26LIQLog(const char *fmt, ...) __attribute__((format(printf, 1, 2)));
static void CC26LIQLog(const char *fmt, ...) {
    FILE *f = fopen("/var/mobile/Library/Accessibility/liquidglass.log", "a");
    if (!f) return;
    fputs("[CC26LIQ] ", f);
    va_list ap;
    va_start(ap, fmt);
    vfprintf(f, fmt, ap);
    va_end(ap);
    fputc('\n', f);
    fclose(f);
}

// Called on every layout of every glass host, so the (synchronizing) prefs read is cached for a
// second: it used to hit the preferences daemon dozens of times per layout pass.
static CFAbsoluteTime sCC26LIQEnabledCheckedAt = 0.0;
static BOOL sCC26LIQEnabledCached = YES;

static BOOL CC26LIQControlCenterEnabled(void) {
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (sCC26LIQEnabledCheckedAt > 0.0 && now - sCC26LIQEnabledCheckedAt < 1.0) return sCC26LIQEnabledCached;
    sCC26LIQEnabledCheckedAt = now;
    CFPreferencesAppSynchronize((__bridge CFStringRef)kCC26LIQPrefsDomain);
    Boolean valid = false;
    Boolean value = CFPreferencesGetAppBooleanValue(
        CFSTR("ControlCenter.Enabled"),
        (__bridge CFStringRef)kCC26LIQPrefsDomain,
        &valid);
    sCC26LIQEnabledCached = valid ? (BOOL)value : YES;
    return sCC26LIQEnabledCached;
}

static BOOL CC26LIQContainsCI(const char *haystack, const char *needle) {
    if (!haystack || !needle) return NO;
    size_t hn = strlen(haystack);
    size_t nn = strlen(needle);
    if (nn == 0 || nn > hn) return NO;
    for (size_t i = 0; i + nn <= hn; i++) {
        size_t j = 0;
        for (; j < nn; j++) {
            char a = haystack[i + j];
            char b = needle[j];
            if (a >= 'A' && a <= 'Z') a += 32;
            if (b >= 'A' && b <= 'Z') b += 32;
            if (a != b) break;
        }
        if (j == nn) return YES;
    }
    return NO;
}

static CFAbsoluteTime sCC26LIQProbedAt = 0.0;

static BOOL CC26LIQProbeLiquidass(void) {
    if (sCC26LIQLiquidassFound) return YES;
    // without LiquidAss this ran a dyld scan + two directory listings on EVERY call (every layout
    // of every glass host, SpringBoard-wide): remember the negative result for a while
    CFAbsoluteTime probeNow = CFAbsoluteTimeGetCurrent();
    if (sCC26LIQProbedAt > 0.0 && probeNow - sCC26LIQProbedAt < 30.0) return NO;
    sCC26LIQProbedAt = probeNow;

    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        if (!name) continue;
        if (CC26LIQContainsCI(name, "liquid") || CC26LIQContainsCI(name, "dylv")) {
            sCC26LIQLiquidassFound = YES;
            if (!sCC26LIQLoggedProbe) {
                sCC26LIQLoggedProbe = YES;
                CC26LIQLog("Liquidass found (dyld): %s", name);
            }
            return YES;
        }
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray<NSString *> *roots = @[
        @"/var/jb/Library/MobileSubstrate/DynamicLibraries",
        @"/Library/MobileSubstrate/DynamicLibraries",
    ];
    for (NSString *root in roots) {
        NSArray<NSString *> *files = [fm contentsOfDirectoryAtPath:root error:nil];
        for (NSString *file in files) {
            const char *n = file.UTF8String;
            if (CC26LIQContainsCI(n, "liquid") || CC26LIQContainsCI(n, "dylv")) {
                sCC26LIQLiquidassFound = YES;
                if (!sCC26LIQLoggedProbe) {
                    sCC26LIQLoggedProbe = YES;
                    CC26LIQLog("Liquidass found (disk): %s", n);
                }
                return YES;
            }
        }
    }
    return NO;
}

static BOOL CC26LIQShouldGlass(void) {
    if (!CC26LIQProbeLiquidass()) return NO;
    return CC26LIQControlCenterEnabled();
}

static id CC26LIQMakeFilter(NSString *typeName) {
    Class filterCls = NSClassFromString(@"CAFilter");
    if (!filterCls) return nil;
    SEL factorySel = NSSelectorFromString(@"filterWithType:");
    if (![filterCls respondsToSelector:factorySel]) return nil;
    CC26LIQFilterFactoryFn factory = (CC26LIQFilterFactoryFn)objc_msgSend;
    return factory(filterCls, factorySel, typeName);
}

#ifdef __cplusplus
extern "C" {
#endif

BOOL CC26LIQIsActive(void) {
    return CC26LIQShouldGlass();
}

id CC26LIQBuildGlassFilter(void) {
    if (!CC26LIQShouldGlass()) return nil;
    return CC26LIQMakeFilter(kCC26LIQControlCenterType);
}

#ifdef __cplusplus
}
#endif

@interface CC26LIQGlassView : UIView
@property (nonatomic, assign) CGFloat glassCornerRadius;
- (instancetype)initWithFrame:(CGRect)frame cornerRadius:(CGFloat)radius;
- (void)applyGlassFilter;
- (void)forceReapply;
@end

@interface CC26LIQGlassView ()
- (BOOL)filterIsLive;
@end

@implementation CC26LIQGlassView

+ (Class)layerClass {
    Class backdropCls = NSClassFromString(@"CABackdropLayer");
    return backdropCls ?: [CALayer class];
}

- (instancetype)initWithFrame:(CGRect)frame cornerRadius:(CGFloat)radius {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    _glassCornerRadius = radius;
    self.userInteractionEnabled = NO;
    self.backgroundColor = UIColor.clearColor;
    self.opaque = NO;
    self.layer.cornerRadius = radius;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.layer.masksToBounds = YES;
    [self applyGlassFilter];
    return self;
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    [self applyGlassFilter];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.layer.cornerRadius = self.glassCornerRadius;
    [self applyGlassFilter];
}

- (BOOL)filterIsLive {
    NSArray *filters = self.layer.filters;
    if (filters.count != 1 || !sCC26LIQActiveFilterType) return NO;
    NSString *type = nil;
    @try { type = [filters[0] valueForKey:@"type"]; } @catch (...) {}
    return type.length && [type isEqualToString:sCC26LIQActiveFilterType];
}

- (void)applyGlassFilter {
    CALayer *layer = self.layer;
    Class backdropCls = NSClassFromString(@"CABackdropLayer");
    if (!backdropCls || ![layer isKindOfClass:backdropCls]) return;

    if (!CC26LIQShouldGlass()) {
        if (layer.filters.count) layer.filters = nil;
        sCC26LIQActiveFilterType = nil;
        return;
    }
    if ([self filterIsLive]) return;

    @try {
        [layer setValue:@NO  forKey:@"layerUsesCoreImageFilters"];
        [layer setValue:@YES forKey:@"windowServerAware"];
        if (![layer valueForKey:@"groupName"]) {
            [layer setValue:kCC26LIQGroupName forKey:@"groupName"];
        }
        [layer setValue:@"dylv.liquidglass" forKey:@"groupNamespace"];
        [layer setValue:@(0.5) forKey:@"scale"];

        NSString *previous = sCC26LIQActiveFilterType;
        id glassFilter = CC26LIQMakeFilter(kCC26LIQControlCenterType);
        if (glassFilter) {
            sCC26LIQActiveFilterType = kCC26LIQControlCenterType;
            if (![previous isEqualToString:kCC26LIQControlCenterType]) {
                CC26LIQLog("active filter = %s", kCC26LIQControlCenterType.UTF8String);
            }
            layer.filters = @[glassFilter];
            return;
        }

        if (previous) CC26LIQLog("ControlCenter filter unavailable");
        sCC26LIQActiveFilterType = nil;
    } @catch (NSException *e) {
        CC26LIQLog("applyGlassFilter exception: %s", e.reason.UTF8String);
    }
}

- (void)forceReapply {
    self.layer.filters = nil;
    [self applyGlassFilter];
}

@end

static void CC26LIQRestoreBlur(UIView *mediaPlayer) {
    if (!mediaPlayer) return;
    @try {
        UIView *blur = [mediaPlayer valueForKey:@"blurView"];
        if ([blur isKindOfClass:UIView.class]) blur.hidden = NO;
    } @catch (...) {}
}

static CC26LIQGlassView *CC26LIQInstallGlass(UIView *host, CGFloat radius) {
    if (!host) return nil;

    CC26LIQGlassView *glass = (CC26LIQGlassView *)[host viewWithTag:kCC26LIQGlassTag];

    if (!CC26LIQShouldGlass()) {
        if (glass) {
            glass.layer.filters = nil;
            glass.hidden = YES;
        }
        return nil;
    }

    if (!glass) {
        glass = [[CC26LIQGlassView alloc] initWithFrame:host.bounds cornerRadius:radius];
        glass.tag = kCC26LIQGlassTag;
        glass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [host insertSubview:glass atIndex:0];
    }
    glass.hidden = NO;
    glass.frame = host.bounds;
    glass.glassCornerRadius = radius;
    if (![glass filterIsLive]) [glass forceReapply];
    [host sendSubviewToBack:glass];
    return glass;
}

#ifdef __cplusplus
extern "C" {
#endif
// Used by the connectivity page tiles: installs the LiquidAss glass behind `host`.
// Returns YES only when the glass filter is live (caller should then hide its own blur).
// Rebuilds the glass filter of `host` (call after its size changed so the edge/specular match).
void CC26LIQRefreshGlass(UIView *host) {
    CC26LIQGlassView *glass = (CC26LIQGlassView *)[host viewWithTag:kCC26LIQGlassTag];
    if ([glass isKindOfClass:CC26LIQGlassView.class]) [glass forceReapply];
}

BOOL CC26LIQApplyGlass(UIView *host, CGFloat radius) {
    CC26LIQGlassView *glass = CC26LIQInstallGlass(host, radius);
    return glass && [glass filterIsLive];
}
#ifdef __cplusplus
}
#endif

static void CC26LIQRemoveAllGlass(void) {
    UIViewController *overlay =
        OverlayIn(UIApplication.sharedApplication.keyWindow.rootViewController);
    if (!overlay) return;

    NSMutableArray<UIView *> *all = [NSMutableArray arrayWithObject:overlay.view];
    while (all.count) {
        UIView *v = all.firstObject;
        [all removeObjectAtIndex:0];
        CC26LIQGlassView *g = (CC26LIQGlassView *)[v viewWithTag:kCC26LIQGlassTag];
        if (g) {
            g.layer.filters = nil;
            [g removeFromSuperview];
        }
        [all addObjectsFromArray:v.subviews];
    }

    CC26LIQRestoreBlur([overlay.view viewWithTag:kMediaPlayerTag]);
    sCC26LIQActiveFilterType = nil;
}

%hook CCAMediaPlayerView
- (void)layoutSubviews {
    %orig;

    if (!CC26LIQShouldGlass()) {
        CC26LIQRestoreBlur(self);
        CC26LIQGlassView *stale = (CC26LIQGlassView *)[self viewWithTag:kCC26LIQGlassTag];
        if (stale) {
            stale.layer.filters = nil;
            [stale removeFromSuperview];
        }
        return;
    }

    CC26LIQGlassView *glass = CC26LIQInstallGlass(self, self.layer.cornerRadius);
    if (!glass) return;
    if ([glass filterIsLive]) {
        @try {
            UIView *blur = [self valueForKey:@"blurView"];
            if ([blur isKindOfClass:UIView.class]) blur.hidden = YES;
        } @catch (...) {}
    }
}
%end

static void CC26LIQReapplyAll(void) {
    UIViewController *overlay =
        OverlayIn(UIApplication.sharedApplication.keyWindow.rootViewController);
    if (!overlay) return;

    UIView *mediaPlayer = [overlay.view viewWithTag:kMediaPlayerTag];
    if (!mediaPlayer) return;

    CC26LIQGlassView *glass = (CC26LIQGlassView *)[mediaPlayer viewWithTag:kCC26LIQGlassTag];
    if (glass) [glass forceReapply];

    [mediaPlayer setNeedsLayout];
}

static void CC26LIQScheduleReapply(void) {
    for (NSNumber *delay in @[ @1.5, @3.0, @5.0, @8.0, @12.0 ]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                     (int64_t)(delay.doubleValue * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (CC26LIQProbeLiquidass()) {
                CC26LIQReapplyAll();
            } else {
                CC26LIQRemoveAllGlass();
            }
        });
    }
}

static void CC26LIQPrefsReloadCallback(CFNotificationCenterRef center,
                                       void *observer,
                                       CFStringRef name,
                                       const void *object,
                                       CFDictionaryRef userInfo) {
    (void)center; (void)observer; (void)name; (void)object; (void)userInfo;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!CC26LIQProbeLiquidass()) {
            CC26LIQRemoveAllGlass();
            return;
        }
        CC26LIQReapplyAll();
    });
}

%ctor {
    @autoreleasepool {
        CC26LIQLog("CC26LIQ loaded");

        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL,
            CC26LIQPrefsReloadCallback,
            (__bridge CFStringRef)kCC26LIQReloadNote,
            NULL,
            CFNotificationSuspensionBehaviorCoalesce);

        CC26LIQScheduleReapply();
    }
}