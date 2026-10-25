#import "CC26.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <math.h>

#ifdef __cplusplus
extern "C" {
#endif
BOOL CC26LIQIsActive(void);
id CC26LIQBuildGlassFilter(void);
#ifdef __cplusplus
}
#endif

typedef struct CCUILayoutSize  { NSUInteger width;  NSUInteger height; } CCUILayoutSize;
typedef struct CCUILayoutPoint { NSUInteger x;      NSUInteger y;      } CCUILayoutPoint;
typedef struct CCUILayoutRect  { CCUILayoutPoint origin; CCUILayoutSize size; } CCUILayoutRect;
typedef struct { NSUInteger c, r, w, h; } CC26Rect;

static NSUInteger kCC26Cols = 4;
static NSUInteger kCC26Rows = 8;
static NSUInteger gCC26EditEpoch = 0;
static CFTimeInterval gEditModeEnteredAt = 0;
static NSInteger gCC26LastPresentationState = 1;
static CGFloat    kCC26Cell = 67.0;
static CGFloat    kCC26gap  = 12.0;
static CGFloat    kCC26Step = 79.0;

BOOL gEditModeEnabled = NO;
BOOL gEditModeActive  = NO;

static NSMutableDictionary<NSString *, NSArray<NSNumber *> *> *gEditOrigins;
static NSMutableDictionary<NSString *, NSArray<NSNumber *> *> *gEditSizes;
static NSMutableDictionary<NSString *, NSArray<NSNumber *> *> *gEditBaseSizes;

static NSString *gCC26PendingResizeID = nil;
static CCUILayoutSize gCC26PendingResizeSize = {0, 0};
static NSTimeInterval gCC26PendingResizeLastTouch = 0;

static Class kClsCCUIButtonModuleView;
static Class kClsCCUICAPackageView;
static Class kClsCABackdropLayer;

static const NSInteger kCC26BorderTag       = 182000;
static const NSInteger kCC26RemoveTag       = 182001;
static const NSInteger kCC26ResizeTag       = 182002;
static const NSInteger kCC26HintTag         = 182003;
static const NSInteger kCC26ProxyTag        = 182004;
static const NSInteger kCC26ResetTag        = 182005;
static const NSInteger kCC26ShieldTag       = 182006;
static const NSInteger kCC26ProxyShadowTag  = 182007;

static const void *kCC26BorderKey   = &kCC26BorderKey;
static const void *kCC26RemoveKey   = &kCC26RemoveKey;
static const void *kCC26ResizeKey   = &kCC26ResizeKey;
static const void *kCC26PresKey     = &kCC26PresKey;
static const void *kCC26MidKey      = &kCC26MidKey;
static const void *kCC26StartSzKey  = &kCC26StartSzKey;
static const void *kCC26GestKey     = &kCC26GestKey;
static const void *kCC26DragSrcKey  = &kCC26DragSrcKey;
static const void *kCC26DragProxyKey= &kCC26DragProxyKey;
static const void *kCC26DragGrabKey = &kCC26DragGrabKey;
static const void *kCC26OwnGestureKey = &kCC26OwnGestureKey;
static const void *kCC26DisabledGesturesKey = &kCC26DisabledGesturesKey;
static const void *kCC26ResizedSetKey = &kCC26ResizedSetKey;
static const void *kCC26LastCellKey     = &kCC26LastCellKey;
static const void *kCC26OrigLayoutKey   = &kCC26OrigLayoutKey;
static const void *kCC26LastRadiusKey   = &kCC26LastRadiusKey;
static const void *kCC26LastPresKey     = &kCC26LastPresKey;
static const void *kCC26OrigRadiiKey    = &kCC26OrigRadiiKey;
static const void *kCC26LandscapeCleanKey = &kCC26LandscapeCleanKey;
static const void *kCC26IconPinKey = &kCC26IconPinKey;
static const CGFloat kCC26BorderWidth = 4.0;
static const CGFloat kCC26BorderInset = 3.5;
static CFTimeInterval gCC26RotationQuietUntil = 0;

static NSString *CC26Mid(UIViewController *vc);
static CGRect CC26VisibleFrame(UIViewController *m, UIViewController *overlay);
static UIViewController *CC26ModuleAtPoint(CGPoint pt, UIViewController *overlay);
static CGPoint CC26GridBase(UIViewController *overlay);
static NSUInteger CC26VisibleRowCap(UIViewController *ov);
static NSArray<NSNumber *> *CC26KnownBaseSize(NSString *mid);
static void CC26EnsureBaseSize(UIViewController *m, UIViewController *ov);
static void CC26EffectiveSize(NSString *mid, NSUInteger *w, NSUInteger *h);
static void CC26PresentationSize(NSString *mid, NSUInteger *w, NSUInteger *h);
static BOOL CC26ModuleSupportsResizing(NSString *mid);
static CCUILayoutSize CC26ResizeCandidate(NSString *mid, NSUInteger startW, NSUInteger startH, CGPoint translation);
static BOOL CC26SizeAllowed(NSUInteger w, NSUInteger h);
static BOOL CC26DragSizeAllowedForModule(NSString *mid, NSUInteger w, NSUInteger h);
static NSString *CC26PrettyNameForModule(UIViewController *m);
static BOOL CC26RectsOverlap(CC26Rect a, CC26Rect b);
static BOOL CC26FindFreeCellFor(NSDictionary<NSString *, NSValue *> *occupied,
                                NSUInteger preferCol, NSUInteger preferRow,
                                NSUInteger w, NSUInteger h,
                                NSUInteger maxRow,
                                NSUInteger *outCol, NSUInteger *outRow);
static id CC26SettingsProvider(void);
static NSArray<NSString *> *CC26ProviderOrderedIdentifiers(void);
static UIView *CC26ModuleButtonView(UIView *moduleView);
static NSArray<UIView *> *CC26CompactGlyphHosts(UIView *view);
static void CC26LayoutModuleIcon(UIViewController *m);
static void CC26RestoreModuleIcon(UIViewController *m);
static CGFloat CC26RadiusForSize(NSUInteger w, NSUInteger h);
static void CC26ApplyRadiusToModule(UIViewController *m);
static void CC26RefreshPresentation(UIViewController *m, UIViewController *ov);
static BOOL CC26WasResizedFromOneByOne(NSString *mid);
static void CC26ApplyChrome(UIViewController *m, UIViewController *ov);
static void CC26StripChrome(UIViewController *m);
static void CC26RestoreModuleRadius(UIViewController *m);
static void CC26InstallGestures(UIViewController *ov);
static BOOL CC26EditAllowed(void);
static BOOL CC26IsLandscape(void);
static void CC26TearDownModule(UIViewController *m);
static void CC26TearDownAllModules(UIViewController *ov);
static void CC26ScheduleRotationRefresh(void);

static void CC26InitCachedClasses(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        kClsCCUIButtonModuleView = NSClassFromString(@"CCUIButtonModuleView");
        kClsCCUICAPackageView    = NSClassFromString(@"CCUICAPackageView");
        kClsCABackdropLayer      = NSClassFromString(@"CABackdropLayer");
    });
}

static void CC26EnsureStore(void) {
    if (!gEditOrigins) {
        CFPropertyListRef v = CFPreferencesCopyAppValue(CFSTR("EditGridOrigins"), CFSTR("com.controlcenter26.preferences"));
        gEditOrigins = [(__bridge NSDictionary *)v mutableCopy] ?: [NSMutableDictionary dictionary];
        if (v) CFRelease(v);
    }
    if (!gEditSizes) {
        CFPropertyListRef v = CFPreferencesCopyAppValue(CFSTR("EditGridSizes"), CFSTR("com.controlcenter26.preferences"));
        gEditSizes = [(__bridge NSDictionary *)v mutableCopy] ?: [NSMutableDictionary dictionary];
        if (v) CFRelease(v);
    }
    if (!gEditBaseSizes) {
        CFPropertyListRef v = CFPreferencesCopyAppValue(CFSTR("EditBaseSizes"), CFSTR("com.controlcenter26.preferences"));
        gEditBaseSizes = [(__bridge NSDictionary *)v mutableCopy] ?: [NSMutableDictionary dictionary];
        if (v) CFRelease(v);
    }
}

static void CC26SaveStore(void) {
    CC26EnsureStore();
    CFPreferencesSetAppValue(CFSTR("EditGridOrigins"), (__bridge CFPropertyListRef)[gEditOrigins copy], CFSTR("com.controlcenter26.preferences"));
    CFPreferencesSetAppValue(CFSTR("EditGridSizes"),   (__bridge CFPropertyListRef)[gEditSizes copy],   CFSTR("com.controlcenter26.preferences"));
    CFPreferencesSetAppValue(CFSTR("EditBaseSizes"),   (__bridge CFPropertyListRef)[gEditBaseSizes copy], CFSTR("com.controlcenter26.preferences"));
    CFPreferencesAppSynchronize(CFSTR("com.controlcenter26.preferences"));
}

static BOOL CC26IsNotchedDevice(void) {
    UIWindow *w = UIApplication.sharedApplication.keyWindow;
    if (w && w.safeAreaInsets.bottom >= 1.0) return YES;
    return NO;
}

static BOOL CC26IsLandscape(void) {
    UIWindow *win = UIApplication.sharedApplication.keyWindow;
    if (win) {
        CGSize sz = win.bounds.size;
        if (sz.width > 1.0 && sz.height > 1.0) return sz.width > sz.height;
    }
    CGSize sz = UIScreen.mainScreen.bounds.size;
    return sz.width > sz.height;
}

static BOOL CC26IsNonNotchedDevice(void) {
    CGSize size = UIScreen.mainScreen.bounds.size;
    if (MAX(size.width, size.height) >= 800.0) return NO;
    UIWindow *window = UIApplication.sharedApplication.keyWindow;
    if (window && window.safeAreaInsets.bottom >= 1.0) return NO;
    return YES;
}

static void CC26RefreshGridConstants(void) {
    BOOL landscape = CC26IsLandscape();
    kCC26Cols = landscape ? 8 : 4;
    kCC26Rows = landscape ? 4 : 8;
    kCC26Cell = 67.0;
    kCC26gap  = 12.0;
    kCC26Step = kCC26Cell + kCC26gap;
}

static BOOL CC26EditAllowed(void) {
    if (!gEnabled || !gEditModeEnabled) return NO;
    if (CC26IsLandscape()) return NO;
    return YES;
}

static NSString *CC26GridKey(NSString *mid) {
    if (!mid.length) return mid;
    return CC26IsLandscape() ? [@"L|" stringByAppendingString:mid]
                            : [@"P|" stringByAppendingString:mid];
}

static NSArray<NSNumber *> *CC26GetOrigin(NSString *mid) {
    if (!mid.length) return nil;
    CC26EnsureStore();
    NSString *key = CC26GridKey(mid);
    NSArray<NSNumber *> *v = gEditOrigins[key];
    if (v) return v;
    if (!CC26IsLandscape()) return gEditOrigins[mid];
    return nil;
}

static void CC26SetOrigin(NSString *mid, NSArray<NSNumber *> *value) {
    if (!mid.length) return;
    CC26EnsureStore();
    NSString *key = CC26GridKey(mid);
    if (value) gEditOrigins[key] = value;
    else       [gEditOrigins removeObjectForKey:key];
}

static void CC26InvalidateOtherOrientationOriginForModule(NSString *mid) {
    if (!mid.length) return;
    CC26EnsureStore();
    BOOL landscape = CC26IsLandscape();
    NSString *otherPrefix = landscape ? @"P|" : @"L|";
    NSString *key = [otherPrefix stringByAppendingString:mid];
    [gEditOrigins removeObjectForKey:key];
    if (!landscape) {
        [gEditOrigins removeObjectForKey:mid];
    }
}

static NSArray<NSNumber *> *CC26SourceOriginForRotation(NSString *mid, BOOL toLandscape) {
    if (!mid.length) return nil;
    NSString *fromPrefix = toLandscape ? @"P|" : @"L|";
    NSArray *v = gEditOrigins[[fromPrefix stringByAppendingString:mid]];
    if (v) return v;
    if (toLandscape) return gEditOrigins[mid];
    return nil;
}

static NSArray<NSNumber *> *CC26TargetOriginForRotation(NSString *mid, BOOL toLandscape) {
    if (!mid.length) return nil;
    NSString *toPrefix = toLandscape ? @"L|" : @"P|";
    return gEditOrigins[[toPrefix stringByAppendingString:mid]];
}

static void CC26MigrateMissingOrigins(UIViewController *ov) {
    if (!ov) return;
    CC26EnsureStore();
    CC26RefreshGridConstants();

    BOOL toLandscape = CC26IsLandscape();
    NSUInteger fromCols = toLandscape ? 4 : 8;
    NSUInteger fromRows = toLandscape ? 8 : 4;
    NSUInteger toCols   = toLandscape ? 8 : 4;
    NSUInteger toRows   = toLandscape ? 4 : 8;
    NSString *toPrefix = toLandscape ? @"L|" : @"P|";

    NSMutableArray<NSDictionary *> *toMigrate = [NSMutableArray array];
    NSMutableArray<NSString *>     *already   = [NSMutableArray array];

    for (UIViewController *m in ModuleControllers(ov)) {
        NSString *mid = CC26Mid(m);
        if (!mid.length) continue;

        if (CC26TargetOriginForRotation(mid, toLandscape)) {
            [already addObject:mid];
            continue;
        }
        NSArray<NSNumber *> *src = CC26SourceOriginForRotation(mid, toLandscape);
        if (src.count < 2) continue;

        NSUInteger c = src[0].unsignedIntegerValue;
        NSUInteger a = src[1].unsignedIntegerValue;
        NSUInteger page = a / fromRows;
        NSUInteger r    = a % fromRows;

        NSUInteger w = 1, h = 1;
        NSArray<NSNumber *> *sz = gEditSizes[mid];
        if (sz.count < 2) sz = gEditBaseSizes[mid];
        if (sz.count >= 2) {
            w = sz[0].unsignedIntegerValue;
            h = sz[1].unsignedIntegerValue;
        }
        if (w > toCols) w = toCols;
        if (h > toRows) h = toRows;
        if (!CC26DragSizeAllowedForModule(mid, w, h)) { w = 1; h = 1; }

        [toMigrate addObject:@{
            @"mid":  mid,
            @"c":    @(c),
            @"r":    @(r),
            @"page": @(page),
            @"w":    @(w),
            @"h":    @(h),
        }];
    }

    if (!toMigrate.count) return;

    [toMigrate sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        for (NSString *k in @[@"page", @"r", @"c"]) {
            NSInteger va = [a[k] integerValue];
            NSInteger vb = [b[k] integerValue];
            if (va != vb) return va < vb ? NSOrderedAscending : NSOrderedDescending;
        }
        return [a[@"mid"] compare:b[@"mid"]];
    }];

    NSMutableDictionary<NSNumber *, NSMutableDictionary<NSString *, NSValue *> *> *pages =
        [NSMutableDictionary dictionary];

    for (NSString *mid in already) {
        NSArray<NSNumber *> *o = CC26TargetOriginForRotation(mid, toLandscape);
        if (o.count < 2) continue;
        NSUInteger c = o[0].unsignedIntegerValue;
        NSUInteger a = o[1].unsignedIntegerValue;
        NSUInteger page = a / toRows;
        NSUInteger r    = a % toRows;

        NSUInteger w = 1, h = 1;
        NSArray<NSNumber *> *sz = gEditSizes[mid];
        if (sz.count < 2) sz = gEditBaseSizes[mid];
        if (sz.count >= 2) {
            w = sz[0].unsignedIntegerValue;
            h = sz[1].unsignedIntegerValue;
        }
        if (w > toCols) w = toCols;
        if (h > toRows) h = toRows;

        NSMutableDictionary *map = pages[@(page)];
        if (!map) { map = [NSMutableDictionary dictionary]; pages[@(page)] = map; }
        CC26Rect pr = {c, r, w, h};
        map[mid] = [NSValue value:&pr withObjCType:@encode(CC26Rect)];
    }

    for (NSDictionary *e in toMigrate) {
        NSString *mid = e[@"mid"];
        NSUInteger srcC = [e[@"c"]    unsignedIntegerValue];
        NSUInteger srcR = [e[@"r"]    unsignedIntegerValue];
        NSUInteger page = [e[@"page"] unsignedIntegerValue];
        NSUInteger w    = [e[@"w"]    unsignedIntegerValue];
        NSUInteger h    = [e[@"h"]    unsignedIntegerValue];

        NSUInteger prefC = (NSUInteger)llround(((double)srcC / (double)fromCols) * (double)toCols);
        NSUInteger prefR = (NSUInteger)llround(((double)srcR / (double)fromRows) * (double)toRows);
        if (prefC + w > toCols) prefC = (toCols >= w) ? (toCols - w) : 0;
        if (prefR + h > toRows) prefR = (toRows >= h) ? (toRows - h) : 0;

        NSMutableDictionary<NSString *, NSValue *> *placed = pages[@(page)];
        if (!placed) { placed = [NSMutableDictionary dictionary]; pages[@(page)] = placed; }

        NSUInteger maxRow = (toRows >= h) ? (toRows - h) : 0;
        NSUInteger outC = prefC, outR = prefR;
        BOOL ok = CC26FindFreeCellFor(placed, prefC, prefR, w, h, maxRow, &outC, &outR);

        if (!ok) {
            NSUInteger p = page + 1;
            while (p < 8) {
                NSMutableDictionary *next = pages[@(p)];
                if (!next) { next = [NSMutableDictionary dictionary]; pages[@(p)] = next; }
                if (CC26FindFreeCellFor(next, 0, 0, w, h, maxRow, &outC, &outR)) {
                    placed = next; page = p; ok = YES; break;
                }
                p++;
            }
        }
        if (!ok) continue;

        CC26Rect pr = {outC, outR, w, h};
        placed[mid] = [NSValue value:&pr withObjCType:@encode(CC26Rect)];
        gEditOrigins[[toPrefix stringByAppendingString:mid]] =
            @[@(outC), @(page * toRows + outR)];
    }

    CC26SaveStore();
}

static NSString *CC26Mid(UIViewController *vc) {
    if (!vc) return nil;
    for (NSString *key in @[@"moduleIdentifier", @"_moduleIdentifier"]) {
        @try { id v = [vc valueForKey:key];
            if ([v isKindOfClass:NSString.class] && [v length]) return v; }
        @catch (__unused NSException *e) {}
    }
    return nil;
}

static CGRect CC26VisibleFrame(UIViewController *m, UIViewController *overlay) {
    if (!m.view || !overlay.view) return CGRectZero;
    CGRect f = [m.view convertRect:m.view.bounds toView:overlay.view];
    UIViewController *col = ModuleCollection(overlay);
    if (col.view) {
        CATransform3D sub = col.view.layer.sublayerTransform;
        f.origin.x += sub.m41;
        f.origin.y += sub.m42;
    }
    return f;
}

static UIViewController *CC26ModuleAtPoint(CGPoint pt, UIViewController *overlay) {
    UIViewController *best = nil;
    CGFloat bestD = CGFLOAT_MAX;
    for (UIViewController *m in ModuleControllers(overlay)) {
        CGRect f = CC26VisibleFrame(m, overlay);
        if (CGRectIsEmpty(f)) continue;
        if (CGRectContainsPoint(f, pt)) {
            CGFloat d = hypot(CGRectGetMidX(f) - pt.x, CGRectGetMidY(f) - pt.y);
            if (d < bestD) { bestD = d; best = m; }
        }
    }
    return best;
}

static CGPoint CC26GridBase(UIViewController *overlay) {
    CC26RefreshGridConstants();
    CC26EnsureStore();
    CGFloat bx = CGFLOAT_MAX, by = CGFLOAT_MAX;
    NSUInteger page = (NSUInteger)gCurrentPage;
    for (UIViewController *m in ModuleControllers(overlay)) {
        NSString *mid = CC26Mid(m);
        if (!mid.length) continue;
        NSArray<NSNumber *> *o = CC26GetOrigin(mid);
        if (o.count < 2) continue;
        NSUInteger c = o[0].unsignedIntegerValue;
        NSUInteger a = o[1].unsignedIntegerValue;
        if (a / kCC26Rows != page) continue;
        NSUInteger lr = a % kCC26Rows;
        CGRect f = CC26VisibleFrame(m, overlay);
        if (CGRectIsEmpty(f)) continue;
        CGFloat x = CGRectGetMinX(f) - (CGFloat)c * kCC26Step;
        CGFloat y = CGRectGetMinY(f) - (CGFloat)lr * kCC26Step;
        if (x < bx) bx = x;
        if (y < by) by = y;
    }
    if (bx == CGFLOAT_MAX) {
        CGFloat w = CGRectGetWidth(overlay.view.bounds);
        CGFloat gw = kCC26Cols * kCC26Cell + (kCC26Cols - 1) * kCC26gap;
        bx = (w - gw) * 0.5;
        by = 100.0;
    }
    return CGPointMake(bx, by);
}

static NSUInteger CC26VisibleRowCap(UIViewController *ov) {
    if (!ov || !ov.view) return kCC26Rows - 1;
    CGPoint base = CC26GridBase(ov);
    CGFloat overlayH = CGRectGetHeight(ov.view.bounds);
    CGFloat safeBottom = ov.view.safeAreaInsets.bottom;
    if (safeBottom < 1.0) safeBottom = 20.0;
    CGFloat usableBottom = overlayH - safeBottom - 8.0;
    CGFloat usableH = usableBottom - base.y;
    if (usableH < kCC26Step) return 0;
    NSInteger rows = (NSInteger)floor(usableH / kCC26Step);
    if (rows <= 0) rows = 1;
    NSUInteger cap = (NSUInteger)MAX(0, MIN((NSInteger)kCC26Rows - 1, rows - 1));
    return cap;
}

static NSArray<NSNumber *> *CC26KnownBaseSize(NSString *mid) {
    if (!mid.length) return nil;
    NSString *lower = mid.lowercaseString;
    NSArray<NSArray<NSString *> *> *entries = @[
        @[@"control-center.connectivitymodule", @"2", @"2"],
        @[@"connectivitymodule", @"2", @"2"],
        @[@"mediaremote.controlcenter.nowplaying", @"2", @"2"],
        @[@"mediaremote.controlcenter.audio", @"1", @"2"],
        @[@"control-center.displaymodule", @"1", @"2"],
        @[@"control-center.focusui", @"2", @"1"],
        @[@"focusui", @"2", @"1"],
        @[@"donotdisturb", @"2", @"1"],
    ];
    for (NSArray *entry in entries) {
        if ([lower containsString:entry[0]]) {
            return @[@([entry[1] integerValue]), @([entry[2] integerValue])];
        }
    }
    return nil;
}

static void CC26EnsureBaseSize(UIViewController *m, UIViewController *ov) {
    NSString *mid = CC26Mid(m);
    if (!mid.length) return;

    NSArray<NSNumber *> *known = CC26KnownBaseSize(mid);
    if (known.count == 2) {
        if (![gEditBaseSizes[mid] isEqualToArray:known]) {
            gEditBaseSizes[mid] = known;
            CC26SaveStore();
        }
        return;
    }

    if (gEditSizes[mid]) {
        if (![gEditBaseSizes[mid] isEqualToArray:@[@1, @1]]) {
            gEditBaseSizes[mid] = @[@1, @1];
            CC26SaveStore();
        }
        return;
    }

    NSArray<NSNumber *> *existing = gEditBaseSizes[mid];
    if (existing.count >= 2 &&
        (existing[0].integerValue != 1 || existing[1].integerValue != 1)) {
        gEditBaseSizes[mid] = @[@1, @1];
        CC26SaveStore();
        return;
    }
    if (existing) return;

    CGRect f = CC26VisibleFrame(m, ov);
    if (CGRectIsEmpty(f)) return;
    NSUInteger w = (NSUInteger)MAX(1, MIN((NSInteger)kCC26Cols, (NSInteger)llround((CGRectGetWidth(f) + kCC26gap) / kCC26Step)));
    NSUInteger h = (NSUInteger)MAX(1, MIN((NSInteger)kCC26Rows, (NSInteger)llround((CGRectGetHeight(f) + kCC26gap) / kCC26Step)));
    gEditBaseSizes[mid] = @[@(w), @(h)];
    CC26SaveStore();
}

static void CC26EffectiveSize(NSString *mid, NSUInteger *w, NSUInteger *h) {
    CC26EnsureStore();
    NSArray<NSNumber *> *s = gEditSizes[mid];
    if (!s) s = gEditBaseSizes[mid];
    *w = s.count >= 2 ? s[0].unsignedIntegerValue : 1;
    *h = s.count >= 2 ? s[1].unsignedIntegerValue : 1;
}

static void CC26PresentationSize(NSString *mid, NSUInteger *w, NSUInteger *h) {
    if (gCC26PendingResizeID && [gCC26PendingResizeID isEqualToString:mid] &&
        gCC26PendingResizeSize.width && gCC26PendingResizeSize.height) {
        *w = gCC26PendingResizeSize.width;
        *h = gCC26PendingResizeSize.height;
        return;
    }
    CC26EffectiveSize(mid, w, h);
}

typedef struct { NSTimeInterval duration; CGFloat c1x, c1y, c2x, c2y; } CC26AnimSpec;

static CC26AnimSpec CC26ResizeSpec(void) {
    if (gExperimentalPagingEnabled) return (CC26AnimSpec){0.58, 0.32, 0.72, 0.0, 1.0};
    return (CC26AnimSpec){0.25, 0.25, 0.10, 0.25, 1.0};
}

static CAMediaTimingFunction *CC26ResizeTiming(CC26AnimSpec sp) {
    return [CAMediaTimingFunction functionWithControlPoints:(float)sp.c1x :(float)sp.c1y :(float)sp.c2x :(float)sp.c2y];
}

static BOOL CC26AnimationsAllowed(void) {
    return CACurrentMediaTime() >= gCC26RotationQuietUntil;
}

static BOOL CC26ModuleSupportsResizing(NSString *mid) {
    if (!mid.length) return NO;
    NSString *lower = mid.lowercaseString;
    if ([lower isEqualToString:@"com.apple.control-center.displaymodule"]) return NO;
    if ([lower containsString:@"mediaremote.controlcenter.audio"]) return NO;   // only the now-playing module resizes
    if ([lower isEqualToString:@"com.apple.control-center.connectivitymodule"]) return NO;
    if ([lower containsString:@"connectivitymodule"]) return NO;
    NSArray<NSNumber *> *base = gEditBaseSizes[mid];
    if (!base) base = CC26KnownBaseSize(mid);
    if (base.count < 2) return NO;
    NSUInteger w = base[0].unsignedIntegerValue;
    NSUInteger h = base[1].unsignedIntegerValue;
    if (w == 1 && h == 1) return YES;
    if (w == 2 && h == 2) return YES;
    return NO;
}

static BOOL CC26SizeAllowed(NSUInteger w, NSUInteger h) {
    if (w == 0 || h == 0) return NO;
    if (w > kCC26Cols || h > kCC26Rows) return NO;
    if (w > 4 || h > 4) return NO;
    if (w == 1 && h == 2) return NO;
    if (h == 1 && w == 3) return NO;
    if (h == 1 && w == 4) return NO;
    return YES;
}

static BOOL CC26DragSizeAllowedForModule(NSString *mid, NSUInteger w, NSUInteger h) {
    if (CC26SizeAllowed(w, h)) return YES;
    if (CC26ModuleSupportsResizing(mid)) return NO;
    NSUInteger bw = 1, bh = 1;
    CC26EffectiveSize(mid, &bw, &bh);
    return (w == bw && h == bh);
}

static CCUILayoutSize CC26ResizeCandidate(NSString *mid, NSUInteger startW, NSUInteger startH, CGPoint translation) {
    NSInteger dc = (NSInteger)floor(translation.x / kCC26Step + 0.5);
    NSInteger dr = (NSInteger)floor(translation.y / kCC26Step + 0.5);
    NSInteger nw = MAX(1, MIN(4, (NSInteger)startW + dc));
    NSInteger nh = MAX(1, MIN(4, (NSInteger)startH + dr));
    return (CCUILayoutSize){(NSUInteger)nw, (NSUInteger)nh};
}

static NSString *CC26BundleDisplayName(NSBundle *bundle) {
    if (!bundle) return nil;
    static NSSet<NSString *> *ignored = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        ignored = [NSSet setWithArray:@[
            @"ControlCenter", @"ControlCenterSettings", @"ControlCenterUIKit",
            @"ControlCenterServices", @"ControlCenterUI", @"ControlCenterSettingsBundles",
            @"CCSupport", @"SpringBoard", @"Preferences", @"UIKit", @"Foundation"]];
    });
    NSString *name = [bundle objectForInfoDictionaryKey:@"CFBundleDisplayName"];
    if (!name.length) name = [bundle objectForInfoDictionaryKey:@"CFBundleName"];
    if (!name.length) return nil;
    if ([ignored containsObject:name]) return nil;
    return name;
}

static NSString *CC26PrettyNameForModule(UIViewController *m) {
    if (!m) return @"Control";

    NSString *mid = CC26Mid(m);
    NSString *lower = mid.lowercaseString;

    if ([lower containsString:@"screencapture"]) return @"Screen Recording";
    if ([lower containsString:@"control-center.displaymodule"] ||
        [lower isEqualToString:@"displaymodule"]) return @"Brightness";
    if ([lower containsString:@"controlcenter.audio"]) return @"Volume";
    if ([lower containsString:@"accessibility"]) return @"Accessibility Shortcuts";

    id contentModule = nil;
    @try { contentModule = [m valueForKey:@"module"]; } @catch (__unused NSException *e) {}
    for (NSString *key in @[@"displayName", @"title"]) {
        @try {
            id v = [contentModule valueForKey:key];
            if ([v isKindOfClass:NSString.class] && [v length]) return v;
        } @catch (__unused NSException *e) {}
    }

    id prov = CC26SettingsProvider();
    if (prov) {
        id meta = nil;
        SEL metaSel = NSSelectorFromString(@"moduleMetadataForModuleIdentifier:");
        if ([prov respondsToSelector:metaSel]) {
            meta = ((id (*)(id, SEL, id))objc_msgSend)(prov, metaSel, mid);
        }
        if (!meta) {
            @try {
                NSDictionary *all = [prov valueForKey:@"moduleMetadata"];
                if ([all isKindOfClass:NSDictionary.class]) meta = all[mid];
            } @catch (__unused NSException *e) {}
        }
        for (NSString *key in @[@"displayName", @"name", @"title", @"localizedName"]) {
            @try {
                id v = [meta valueForKey:key];
                if ([v isKindOfClass:NSString.class] && [v length]) return v;
            } @catch (__unused NSException *e) {}
        }
        NSURL *bundleURL = nil;
        NSString *bundlePath = nil;
        @try { id v = [meta valueForKey:@"bundleURL"];
            if ([v isKindOfClass:NSURL.class]) bundleURL = v; } @catch (__unused NSException *e) {}
        @try { id v = [meta valueForKey:@"bundlePath"];
            if ([v isKindOfClass:NSString.class]) bundlePath = v; } @catch (__unused NSException *e) {}
        NSBundle *bundle = bundleURL ? [NSBundle bundleWithURL:bundleURL]
                      : bundlePath ? [NSBundle bundleWithPath:bundlePath] : nil;
        NSString *metaBundleName = CC26BundleDisplayName(bundle);
        if (metaBundleName.length) return metaBundleName;
    }

    if (contentModule) {
        NSString *classBundleName = CC26BundleDisplayName([NSBundle bundleForClass:[contentModule class]]);
        if (classBundleName.length) return classBundleName;
    }

    NSString *label = m.view.accessibilityLabel;
    if (label.length) return label;
    UIView *pres = objc_getAssociatedObject(m.view, kCC26PresKey);
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithArray:m.view.subviews];
    while (queue.count) {
        UIView *v = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if (pres && v == pres) continue;
        if (v.accessibilityLabel.length) { label = v.accessibilityLabel; break; }
        [queue addObjectsFromArray:v.subviews];
    }
    if (label.length) return label;

    if (!mid.length) return @"Control";
    NSString *last = [mid componentsSeparatedByString:@"."].lastObject;
    if ([last hasSuffix:@"Module"] && last.length > 6) last = [last substringToIndex:last.length - 6];
    if (!last.length) return @"Control";
    NSMutableString *result = [NSMutableString string];
    for (NSUInteger i = 0; i < last.length; i++) {
        unichar c = [last characterAtIndex:i];
        if (i > 0 && [[NSCharacterSet uppercaseLetterCharacterSet] characterIsMember:c]) {
            [result appendString:@" "];
        }
        [result appendFormat:@"%C", c];
    }
    return result.length ? result : @"Control";
}

static BOOL CC26RectsOverlap(CC26Rect a, CC26Rect b) {
    return (a.c < b.c + b.w && b.c < a.c + a.w &&
            a.r < b.r + b.h && b.r < a.r + a.h);
}

static BOOL CC26FindFreeCellFor(NSDictionary<NSString *, NSValue *> *occupied,
                                NSUInteger preferCol, NSUInteger preferRow,
                                NSUInteger w, NSUInteger h,
                                NSUInteger maxRow,
                                NSUInteger *outCol, NSUInteger *outRow) {
    if (w == 0 || h == 0 || w > kCC26Cols || h > kCC26Rows) return NO;
    NSInteger maxC = (NSInteger)kCC26Cols - (NSInteger)w;
    NSInteger maxR = MIN((NSInteger)maxRow, (NSInteger)kCC26Rows - (NSInteger)h);
    if (maxC < 0 || maxR < 0) return NO;

    BOOL found = NO;
    NSInteger bestScore = NSIntegerMax;
    NSUInteger bestCol = 0, bestRow = 0;

    for (NSInteger r = 0; r <= maxR; r++) {
        for (NSInteger c = 0; c <= maxC; c++) {
            CC26Rect t = {(NSUInteger)c, (NSUInteger)r, w, h};
            BOOL ok = YES;
            for (NSValue *v in occupied.allValues) {
                CC26Rect o = {};
                [v getValue:&o];
                if (CC26RectsOverlap(t, o)) { ok = NO; break; }
            }
            if (!ok) continue;
            NSInteger dx = c - (NSInteger)preferCol;
            NSInteger dy = r - (NSInteger)preferRow;
            NSInteger score = labs((long)dx) + labs((long)dy);
            if (score < bestScore ||
                (score == bestScore && (r < (NSInteger)bestRow ||
                 (r == (NSInteger)bestRow && c < (NSInteger)bestCol)))) {
                bestScore = score;
                bestCol = (NSUInteger)c;
                bestRow = (NSUInteger)r;
                found = YES;
            }
        }
    }
    if (found) { *outCol = bestCol; *outRow = bestRow; }
    return found;
}

static id CC26SettingsProvider(void) {
    Class c = NSClassFromString(@"CCSModuleSettingsProvider");
    SEL s = NSSelectorFromString(@"sharedProvider");
    return (c && [c respondsToSelector:s]) ? ((id (*)(id, SEL))objc_msgSend)(c, s) : nil;
}

static NSArray<NSString *> *CC26ProviderOrderedIdentifiers(void) {
    id prov = CC26SettingsProvider();
    SEL sel = NSSelectorFromString(@"orderedUserEnabledModuleIdentifiers");
    if (!prov || ![prov respondsToSelector:sel]) return nil;
    id list = ((id (*)(id, SEL))objc_msgSend)(prov, sel);
    return [list isKindOfClass:NSArray.class] ? (NSArray<NSString *> *)list : nil;
}

static UIView *CC26ModuleButtonView(UIView *moduleView) {
    if (!moduleView) return moduleView;
    if (kClsCCUIButtonModuleView && [moduleView isKindOfClass:kClsCCUIButtonModuleView]) return moduleView;
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithArray:moduleView.subviews];
    while (queue.count) {
        UIView *v = queue.lastObject;
        [queue removeLastObject];
        if (kClsCCUIButtonModuleView && [v isKindOfClass:kClsCCUIButtonModuleView]) return v;
        if (v.subviews.count) [queue addObjectsFromArray:v.subviews];
    }
    return moduleView;
}

static NSArray<UIView *> *CC26CompactGlyphHosts(UIView *view) {
    if (!view) return @[];
    NSMutableArray<UIView *> *hosts = [NSMutableArray array];
    for (NSString *key in @[@"_glyphImageView", @"glyphImageView", @"_glyphPackageView", @"glyphPackageView"]) {
        @try {
            id cand = [view valueForKey:key];
            if ([cand isKindOfClass:UIView.class] && ![hosts containsObject:cand]) [hosts addObject:cand];
        } @catch (__unused NSException *e) {}
    }
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithArray:view.subviews];
    while (queue.count) {
        UIView *v = queue.lastObject;
        [queue removeLastObject];
        BOOL hit = kClsCCUICAPackageView && [v isKindOfClass:kClsCCUICAPackageView];
        if (!hit) {
            NSString *cls = NSStringFromClass(v.class);
            hit = [cls isEqualToString:@"CCUICAPackageView"] || [cls containsString:@"CAPackage"];
        }
        if (!hit && [v isKindOfClass:UIImageView.class]) {
            UIImageView *iv = (UIImageView *)v;
            CGFloat mn = MIN(CGRectGetWidth(v.bounds), CGRectGetHeight(v.bounds));
            hit = iv.image != nil && mn >= 16.0 && !v.hidden && v.alpha > 0.01;
        }
        if (hit && ![hosts containsObject:v]) [hosts addObject:v];
        if (v.subviews.count) [queue addObjectsFromArray:v.subviews];
    }
    return hosts;
}

static BOOL CC26IsGeometryKeyPath(NSString *keyPath) {
    return [keyPath hasPrefix:@"position"] ||
           [keyPath hasPrefix:@"bounds"] ||
           [keyPath hasPrefix:@"transform"] ||
           [keyPath hasPrefix:@"anchorPoint"];
}

static BOOL CC26ViewIsPinnedGlyph(UIView *view) {
    BOOL glyphSeen = NO;
    UIView *a = view;
    for (NSUInteger i = 0; a && i < 8; i++, a = a.superview) {
        if (objc_getAssociatedObject(a, kCC26IconPinKey)) return glyphSeen;
        NSString *cls = NSStringFromClass(a.class);
        if ([a isKindOfClass:UIImageView.class] || [cls containsString:@"CAPackage"]) glyphSeen = YES;
    }
    return NO;
}

static BOOL CC26ShouldBlockGlyphAnimation(CALayer *layer, CAAnimation *anim) {
    if (![anim isKindOfClass:CAPropertyAnimation.class]) return NO;
    if (!CC26IsGeometryKeyPath(((CAPropertyAnimation *)anim).keyPath)) return NO;
    CALayer *l = layer;
    for (NSUInteger i = 0; l && i < 8; i++, l = l.superlayer) {
        id d = l.delegate;
        if ([d isKindOfClass:UIView.class]) return CC26ViewIsPinnedGlyph((UIView *)d);
    }
    return NO;
}

static void CC26LayoutModuleIcon(UIViewController *m) {
    if (!m || !m.view) return;
    UIView *buttonView = CC26ModuleButtonView(m.view);
    NSArray<UIView *> *glyphs = CC26CompactGlyphHosts(buttonView);
    CGPoint targetInButton = CGPointMake(kCC26Cell * 0.5, kCC26Cell * 0.5);
    objc_setAssociatedObject(buttonView, kCC26IconPinKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    for (UIView *glyph in glyphs) {
        UIView *host = glyph.superview;
        if (!host) continue;
        CGPoint target = [buttonView convertPoint:targetInButton toView:host];

        [UIView performWithoutAnimation:^{
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            for (NSString *k in [glyph.layer.animationKeys copy]) {
                CAAnimation *a = [glyph.layer animationForKey:k];
                if ([a isKindOfClass:CAPropertyAnimation.class] &&
                    CC26IsGeometryKeyPath(((CAPropertyAnimation *)a).keyPath)) {
                    [glyph.layer removeAnimationForKey:k];
                }
            }
            glyph.layer.transform = CATransform3DIdentity;
            glyph.center = target;
            [CATransaction commit];
        }];
    }
}

static void CC26RestoreModuleIcon(UIViewController *m) {
    if (!m || !m.view) return;
    UIView *buttonView = CC26ModuleButtonView(m.view);
    NSArray<UIView *> *glyphs = CC26CompactGlyphHosts(buttonView);
    for (UIView *glyph in glyphs) {
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        [glyph.layer removeAnimationForKey:@"cc26.glide"];
        glyph.transform = CGAffineTransformIdentity;
        [CATransaction commit];
    }
}

static CGFloat CC26RadiusForSize(NSUInteger w, NSUInteger h) {
    if (w == 0 || h == 0) return 22.0;

    CGFloat widthPt  = (CGFloat)w * kCC26Cell + ((CGFloat)w - 1.0) * kCC26gap;
    CGFloat heightPt = (CGFloat)h * kCC26Cell + ((CGFloat)h - 1.0) * kCC26gap;
    if (widthPt <= 0.0 || heightPt <= 0.0) return 22.0;

    return calculatedRadius(CGRectMake(0.0, 0.0, widthPt, heightPt), 22.0);
}

static void CC26RememberLayerState(UIView *v, NSMapTable<UIView *, NSDictionary *> *table) {
    if (!v || [table objectForKey:v]) return;
    [table setObject:@{ @"r":     @(v.layer.cornerRadius),
                        @"curve": v.layer.cornerCurve ?: kCACornerCurveCircular,
                        @"mask":  @(v.layer.masksToBounds) }
              forKey:v];
}

static BOOL CC26ModuleIsExpanded(UIViewController *m) {
    if (gCCAModuleExpanded) return YES;
    SEL sel = NSSelectorFromString(@"isExpanded");
    if ([m respondsToSelector:sel] && ((BOOL (*)(id, SEL))objc_msgSend)(m, sel)) return YES;
    UIView *root = m.view;
    if (!root) return NO;
    CGSize ms = root.bounds.size;

    NSString *mid = CC26Mid(m);
    if (mid.length && ms.width > 1.0 && ms.height > 1.0) {
        NSUInteger w = 1, h = 1;
        CC26PresentationSize(mid, &w, &h);
        CGFloat ew = (CGFloat)w * kCC26Cell + ((CGFloat)w - 1.0) * kCC26gap;
        CGFloat eh = (CGFloat)h * kCC26Cell + ((CGFloat)h - 1.0) * kCC26gap;
        if (ms.width > ew * 1.35 + 8.0 || ms.height > eh * 1.35 + 8.0) return YES;
    }

    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithArray:root.subviews];
    NSUInteger visited = 0;
    while (queue.count && visited++ < 80) {
        UIView *v = queue.lastObject;
        [queue removeLastObject];
        NSString *cls = NSStringFromClass(v.class);
        if (([cls containsString:@"CCUIContentModuleContentContainer"] || [cls containsString:@"SliderView"]) &&
            (CGRectGetWidth(v.bounds) > ms.width + 14.0 || CGRectGetHeight(v.bounds) > ms.height + 14.0)) {
            return YES;
        }
        [queue addObjectsFromArray:v.subviews];
    }
    return NO;
}

static void CC26SetRadius(CALayer *layer, CGFloat radius, BOOL animate) {
    CGFloat from = radius;
    if (animate) {
        CALayer *pl = layer.presentationLayer;
        from = pl ? pl.cornerRadius : layer.cornerRadius;
    }
    layer.cornerRadius = radius;
    layer.cornerCurve = kCACornerCurveContinuous;
    layer.masksToBounds = YES;
    CABasicAnimation *running = (CABasicAnimation *)[layer animationForKey:@"cc26.radius"];
    BOOL sameGoal = running && [running.toValue isKindOfClass:NSNumber.class] &&
                    fabs([running.toValue doubleValue] - radius) < 0.01;
    if (animate && !sameGoal && fabs(from - radius) > 0.5) {
        CC26AnimSpec sp = CC26ResizeSpec();
        CABasicAnimation *a = [CABasicAnimation animationWithKeyPath:@"cornerRadius"];
        a.fromValue = @(from);
        a.toValue = @(radius);
        a.duration = sp.duration;
        a.timingFunction = CC26ResizeTiming(sp);
        [layer addAnimation:a forKey:@"cc26.radius"];
    }
}

static void CC26RunMaybeWithoutAnimation(void (^block)(void)) {
    if (CACurrentMediaTime() < gCC26RotationQuietUntil) {
        [UIView performWithoutAnimation:^{
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            block();
            [CATransaction commit];
        }];
    } else {
        block();
    }
}

static void CC26ApplyRadiusToModule(UIViewController *m) {
    if (!m || !m.view) return;
    if (CC26IsLandscape()) return;
    objc_setAssociatedObject(m.view, kCC26LandscapeCleanKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    NSString *mid = CC26Mid(m);
    if (!mid.length) return;

    if (CC26ModuleIsExpanded(m)) {
        if (objc_getAssociatedObject(m.view, kCC26LastRadiusKey)) CC26RestoreModuleRadius(m);
        return;
    }

    NSUInteger w = 1, h = 1;
    CC26EffectiveSize(mid, &w, &h);
    CGFloat radius = CC26RadiusForSize(w, h);

    CGSize moduleSize = m.view.bounds.size;
    if (moduleSize.width < 1.0 || moduleSize.height < 1.0) return;

    NSValue *last = objc_getAssociatedObject(m.view, kCC26LastRadiusKey);
    BOOL animateRadius = last != nil && CC26AnimationsAllowed();
    BOOL resizeSettling = gCC26PendingResizeID != nil ||
                          (CACurrentMediaTime() - gCC26PendingResizeLastTouch) < 1.4;
    if (last && !resizeSettling) {
        NSMapTable<UIView *, NSDictionary *> *styled = objc_getAssociatedObject(m.view, kCC26OrigRadiiKey);
        for (UIView *v in styled.keyEnumerator.allObjects) {
            if (!v.window || !v.layer.masksToBounds) continue;
            BOOL sameSizeAsModule = fabs(CGRectGetWidth(v.bounds) - moduleSize.width) < 8.0 &&
                                    fabs(CGRectGetHeight(v.bounds) - moduleSize.height) < 8.0;
            if (sameSizeAsModule && fabs(v.layer.cornerRadius - radius) > 0.5) {
                last = nil;
                break;
            }
        }
    }
    if (last && !resizeSettling) {
        CGSize ls = last.CGSizeValue;
        if (fabs(ls.width  - moduleSize.width)  < 0.5 &&
            fabs(ls.height - moduleSize.height) < 0.5 &&
            fabs(m.view.layer.cornerRadius - radius) < 0.5) {
            return;
        }
    }
    objc_setAssociatedObject(m.view, kCC26LastRadiusKey,
                             [NSValue valueWithCGSize:moduleSize],
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    NSMapTable<UIView *, NSDictionary *> *orig = objc_getAssociatedObject(m.view, kCC26OrigRadiiKey);
    if (!orig) {
        orig = [NSMapTable weakToStrongObjectsMapTable];
        objc_setAssociatedObject(m.view, kCC26OrigRadiiKey, orig, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    CC26RunMaybeWithoutAnimation(^{
        CC26RememberLayerState(m.view, orig);
        CC26SetRadius(m.view.layer, radius, animateRadius);

        UIView *buttonView = CC26ModuleButtonView(m.view);
        if (buttonView) {
            CC26RememberLayerState(buttonView, orig);
            CC26SetRadius(buttonView.layer, radius, animateRadius);
        }

        NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithArray:m.view.subviews];
        while (queue.count) {
            UIView *v = queue.lastObject;
            [queue removeLastObject];
            BOOL isPillName = (kClsCCUIButtonModuleView && [v isKindOfClass:kClsCCUIButtonModuleView]);
            if (!isPillName) {
                NSString *cls = NSStringFromClass(v.class);
                isPillName = [cls containsString:@"CCUIButtonModuleView"] ||
                             [cls containsString:@"CCUIContentModuleContentContainer"];
            }
            CGFloat vw = CGRectGetWidth(v.bounds);
            CGFloat vh = CGRectGetHeight(v.bounds);
            BOOL fills = (fabs(vw - moduleSize.width)  < 8.0) &&
                         (fabs(vh - moduleSize.height) < 8.0);
            if (isPillName || fills) {
                CC26RememberLayerState(v, orig);
                CC26SetRadius(v.layer, radius, animateRadius);
            }
            if (v.subviews.count) [queue addObjectsFromArray:v.subviews];
        }
    });
}

static void CC26RestoreModuleRadius(UIViewController *m) {
    if (!m || !m.view) return;
    objc_setAssociatedObject(m.view, kCC26LastRadiusKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NSMapTable<UIView *, NSDictionary *> *orig = objc_getAssociatedObject(m.view, kCC26OrigRadiiKey);
    if (!orig) return;

    [UIView performWithoutAnimation:^{
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        for (UIView *v in orig.keyEnumerator.allObjects) {
            NSDictionary *st = [orig objectForKey:v];
            if (!st) continue;
            CGFloat vw = CGRectGetWidth(v.bounds);
            CGFloat vh = CGRectGetHeight(v.bounds);
            BOOL smallSquare = vw > 1.0 && vh > 1.0 && fabs(vw - vh) < 1.5 && MIN(vw, vh) <= 76.0;
            if (smallSquare) {
                v.layer.cornerRadius = MIN(vw, vh) * 0.5;
                v.layer.cornerCurve  = kCACornerCurveContinuous;
            } else {
                v.layer.cornerRadius = [st[@"r"] doubleValue];
                v.layer.cornerCurve  = st[@"curve"] ?: kCACornerCurveCircular;
            }
            v.layer.masksToBounds = [st[@"mask"] boolValue];
        }
        [CATransaction commit];
    }];
}

static void CC26TearDownModule(UIViewController *m) {
    if (!m || !m.view) return;
    UIView *view = m.view;
    CGSize sz = view.bounds.size;
    NSValue *done = objc_getAssociatedObject(view, kCC26LandscapeCleanKey);
    if (done && fabs(done.CGSizeValue.width  - sz.width)  < 0.5 &&
                fabs(done.CGSizeValue.height - sz.height) < 0.5) return;
    objc_setAssociatedObject(view, kCC26LandscapeCleanKey, [NSValue valueWithCGSize:sz],
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    [UIView performWithoutAnimation:^{
        [CATransaction begin];
        [CATransaction setDisableActions:YES];

        UIView *pres = objc_getAssociatedObject(view, kCC26PresKey);
        [pres removeFromSuperview];
        objc_setAssociatedObject(view, kCC26PresKey,     nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(view, kCC26LastPresKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        CC26StripChrome(m);
        CC26RestoreModuleIcon(m);
        CC26RestoreModuleRadius(m);

        [CC26ModuleButtonView(view) setNeedsLayout];

        [CATransaction commit];
    }];
}

static void CC26TearDownAllModules(UIViewController *ov) {
    if (!ov) return;
    for (UIViewController *m in ModuleControllers(ov)) CC26TearDownModule(m);
}

static BOOL CC26WasResizedFromOneByOne(NSString *mid) {
    if (!mid.length) return NO;

    NSUInteger curW = 1, curH = 1;
    CC26PresentationSize(mid, &curW, &curH);
    if (curW == 1 && curH == 1) return NO;

    NSArray<NSNumber *> *known = CC26KnownBaseSize(mid);
    if (known.count >= 2) {
        return (known[0].integerValue == 1 && known[1].integerValue == 1);
    }

    NSMutableSet<NSString *> *resized = objc_getAssociatedObject(UIApplication.sharedApplication, kCC26ResizedSetKey);
    if ([resized containsObject:mid]) return YES;

    if (gEditSizes[mid]) return YES;

    NSArray<NSNumber *> *base = gEditBaseSizes[mid];
    if (base.count >= 2) {
        return (base[0].integerValue == 1 && base[1].integerValue == 1);
    }
    return NO;
}

static UIViewPropertyAnimator *CC26BezierAnimator(NSTimeInterval duration,
                                                 CGFloat c1x, CGFloat c1y,
                                                 CGFloat c2x, CGFloat c2y) {
    UICubicTimingParameters *timing =
        [[UICubicTimingParameters alloc] initWithControlPoint1:CGPointMake(c1x, c1y)
                                                controlPoint2:CGPointMake(c2x, c2y)];
    UIViewPropertyAnimator *a = [[UIViewPropertyAnimator alloc] initWithDuration:duration
                                                                timingParameters:timing];
    a.interruptible = YES;
    a.userInteractionEnabled = YES;
    return a;
}

static UIView *CC26MakeBorder(void) {
    UIView *v = [UIView new];
    v.userInteractionEnabled = NO;
    v.backgroundColor = UIColor.clearColor;
    v.layer.cornerCurve = kCACornerCurveContinuous;
    v.layer.masksToBounds = NO;
    
    v.layer.borderColor = [UIColor colorWithWhite:0.75 alpha:0.35].CGColor;
    
    v.layer.borderWidth = kCC26BorderWidth;
    v.layer.shadowColor = UIColor.blackColor.CGColor;
    v.layer.shadowOpacity = 0.08;
    v.layer.shadowRadius = 3.0;
    v.layer.shadowOffset = CGSizeZero;

    CABasicAnimation *pulse = [CABasicAnimation animationWithKeyPath:@"opacity"];
    pulse.fromValue = @0.85;
    pulse.toValue = @1.0;
    pulse.duration = 1.6;
    pulse.autoreverses = YES;
    pulse.repeatCount = HUGE_VALF;
    pulse.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [v.layer addAnimation:pulse forKey:@"CC26EditPulse"];
    return v;
}

static UIButton *CC26MakeRemoveButton(NSString *mid) {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.tag = kCC26RemoveTag;
    b.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.94];
    b.frame = CGRectMake(0, 0, 30, 30);
    b.layer.cornerRadius = 15.0;
    b.layer.cornerCurve = kCACornerCurveContinuous;
    b.layer.masksToBounds = NO;
    b.layer.shadowColor = UIColor.blackColor.CGColor;
    b.layer.shadowOpacity = 0.14;
    b.layer.shadowRadius = 4.0;
    b.layer.shadowOffset = CGSizeMake(0, 1);

    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration
        configurationWithPointSize:15 weight:UIImageSymbolWeightBold];
    UIImageView *icon = [[UIImageView alloc]
        initWithImage:[UIImage systemImageNamed:@"minus" withConfiguration:cfg]];
    icon.tintColor = [UIColor colorWithWhite:0.10 alpha:0.85];
    icon.contentMode = UIViewContentModeCenter;
    icon.userInteractionEnabled = NO;
    icon.frame = b.bounds;
    icon.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [b addSubview:icon];

    objc_setAssociatedObject(b, kCC26MidKey, mid, OBJC_ASSOCIATION_COPY_NONATOMIC);
    return b;
}

static UIButton *CC26MakeResizeButton(NSString *mid) {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.tag = kCC26ResizeTag;
    b.backgroundColor = UIColor.clearColor;
    b.frame = CGRectMake(0, 0, 42, 42);

    UIBezierPath *cornerPath = [UIBezierPath bezierPath];
    [cornerPath moveToPoint:CGPointMake(20.29, 40.01)];
    [cornerPath addCurveToPoint:CGPointMake(40.01, 20.29)
                  controlPoint1:CGPointMake(31.20, 40.01)
                  controlPoint2:CGPointMake(40.01, 31.20)];

    UIVisualEffectView *material = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialLight]];
    material.frame = b.bounds;
    material.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    material.userInteractionEnabled = NO;
    CAShapeLayer *materialMask = [CAShapeLayer layer];
    materialMask.path = cornerPath.CGPath;
    materialMask.fillColor = UIColor.clearColor.CGColor;
    materialMask.strokeColor = UIColor.blackColor.CGColor;
    materialMask.lineWidth = 12.0;
    materialMask.lineCap = kCALineCapRound;
    materialMask.lineJoin = kCALineJoinRound;
    material.layer.mask = materialMask;
    [b addSubview:material];

    CAShapeLayer *pill = [CAShapeLayer layer];
    pill.path = cornerPath.CGPath;
    pill.fillColor = UIColor.clearColor.CGColor;
    pill.strokeColor = [UIColor.whiteColor colorWithAlphaComponent:0.82].CGColor;
    pill.lineWidth = 12.5;
    pill.lineCap = kCALineCapRound;
    pill.lineJoin = kCALineJoinRound;
    [b.layer addSublayer:pill];

    objc_setAssociatedObject(b, kCC26MidKey, mid, OBJC_ASSOCIATION_COPY_NONATOMIC);
    return b;
}

static UIButton *CC26MakeResetButton(void) {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.tag = kCC26ResetTag;
    b.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.90];
    b.layer.cornerRadius = 20.0;
    b.layer.cornerCurve = kCACornerCurveContinuous;
    b.layer.masksToBounds = YES;

    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:14 weight:UIImageSymbolWeightSemibold];
    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"arrow.counterclockwise" withConfiguration:cfg]];
    icon.tintColor = UIColor.whiteColor;
    icon.contentMode = UIViewContentModeScaleAspectFit;
    icon.userInteractionEnabled = NO;
    icon.tag = 9001;

    UILabel *label = [[UILabel alloc] init];
    label.text = @"Reset Layout";
    label.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    label.textColor = UIColor.whiteColor;
    label.userInteractionEnabled = NO;
    label.tag = 9002;

    CGSize textSize = [label sizeThatFits:CGSizeMake(300, 20)];
    CGFloat iconSide = 18.0;
    CGFloat gap = 7.0;
    CGFloat padX = 16.0;
    CGFloat height = 40.0;
    CGFloat width = padX + iconSide + gap + textSize.width + padX;

    b.bounds = CGRectMake(0, 0, width, height);
    icon.frame = CGRectMake(padX, (height - iconSide) * 0.5, iconSide, iconSide);
    label.frame = CGRectMake(padX + iconSide + gap, 0, textSize.width, height);
    [b addSubview:icon];
    [b addSubview:label];
    return b;
}

static void CC26AnimateChromeEntry(UIView *chrome) {
    if (!chrome) return;
    chrome.transform = CGAffineTransformMakeScale(0.82, 0.82);
    UIViewPropertyAnimator *anim = CC26BezierAnimator(0.45, 0.32, 0.72, 0.0, 1.0);
    [anim addAnimations:^{
        chrome.transform = CGAffineTransformIdentity;
    }];
    [anim startAnimation];
}

static void CC26AnimateChromeEntryDelayed(UIView *chrome, NSTimeInterval delay) {
    if (!chrome) return;
    chrome.transform = CGAffineTransformMakeScale(0.4, 0.4);
    chrome.alpha = 0.0;
    UIViewPropertyAnimator *anim = CC26BezierAnimator(0.42, 0.32, 0.72, 0.0, 1.0);
    [anim addAnimations:^{
        chrome.transform = CGAffineTransformIdentity;
        chrome.alpha = 1.0;
    }];
    [anim startAnimationAfterDelay:delay];
}

@interface CC26EditShield : UIView
@end

@implementation CC26EditShield
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (self.hidden || self.alpha < 0.01 || !self.userInteractionEnabled) return nil;
    return self;
}
@end

@interface CC26LiveGlassProxyView : UIView
@end

@implementation CC26LiveGlassProxyView
+ (Class)layerClass {
    return kClsCABackdropLayer ?: [CALayer class];
}
@end

static UIImage *CC26SnapshotContentOnly(UIView *src, BOOL liquidassActive) {
    CGSize sz = src.bounds.size;
    if (sz.width < 1 || sz.height < 1) return nil;

    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:sz];

    if (!liquidassActive) {
        return [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
            [src drawViewHierarchyInRect:CGRectMake(0, 0, sz.width, sz.height)
                     afterScreenUpdates:NO];
        }];
    }

    NSMutableArray<UIView *> *hidden = [NSMutableArray array];
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithArray:src.subviews];
    while (queue.count) {
        UIView *v = queue.lastObject;
        [queue removeLastObject];
        BOOL isMaterial = (kClsCABackdropLayer && [v.layer isKindOfClass:kClsCABackdropLayer]);
        if (!isMaterial) {
            NSString *cls = NSStringFromClass(v.class);
            isMaterial = [cls containsString:@"MTMaterial"] ||
                         [cls containsString:@"MaterialView"] ||
                         [cls containsString:@"Backdrop"] ||
                         [v isKindOfClass:UIVisualEffectView.class];
        }
        if (isMaterial) {
            if (!v.hidden && v.alpha > 0.01) {
                v.hidden = YES;
                [hidden addObject:v];
            }
        } else {
            if (v.subviews.count) [queue addObjectsFromArray:v.subviews];
        }
    }

    UIColor *savedBg = src.backgroundColor;
    src.backgroundColor = UIColor.clearColor;

    UIImage *result = [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [src drawViewHierarchyInRect:CGRectMake(0, 0, sz.width, sz.height)
                 afterScreenUpdates:YES];
    }];

    for (UIView *v in hidden) v.hidden = NO;
    src.backgroundColor = savedBg;
    return result;
}

static void CC26BringChromeToFront(UIViewController *ov) {
    if (!ov || !ov.view) return;
    UIView *shield = [ov.view viewWithTag:kCC26ShieldTag];
    if (shield) [ov.view bringSubviewToFront:shield];
    for (UIViewController *m in ModuleControllers(ov)) {
        UIButton *rm = objc_getAssociatedObject(m.view, kCC26RemoveKey);
        UIButton *rz = objc_getAssociatedObject(m.view, kCC26ResizeKey);
        if (rm) [ov.view bringSubviewToFront:rm];
        if (rz) [ov.view bringSubviewToFront:rz];
        UIView *pr = objc_getAssociatedObject(m.view, kCC26PresKey);
        if (pr) [ov.view bringSubviewToFront:pr];
    }
    UIView *rp = [ov.view viewWithTag:kCC26ResetTag];
    if (rp) [ov.view bringSubviewToFront:rp];
}

static UIView *CC26ModuleMoverView(UIViewController *m, UIViewController *col) {
    UIView *v = m.view;
    if (!v) return nil;
    UIView *stop = col.view;
    if (!stop) return v;
    UIView *cur = v;
    while (cur.superview && cur.superview != stop) cur = cur.superview;
    return cur.superview == stop ? cur : v;
}

static NSDictionary<NSString *, NSValue *> *CC26CaptureModuleFrames(UIViewController *ov, NSString *excludeMid) {
    NSMutableDictionary<NSString *, NSValue *> *frames = [NSMutableDictionary dictionary];
    for (UIViewController *m in ModuleControllers(ov)) {
        NSString *mid = CC26Mid(m);
        if (!mid.length || [mid isEqualToString:excludeMid]) continue;
        CGRect f = CC26VisibleFrame(m, ov);
        if (CGRectIsEmpty(f)) continue;
        frames[mid] = [NSValue valueWithCGRect:f];
    }
    return frames;
}

static BOOL CC26SlideModules(UIViewController *ov, NSDictionary<NSString *, NSValue *> *oldFrames) {
    if (!ov || !oldFrames.count || !CC26AnimationsAllowed()) return NO;
    UIViewController *col = ModuleCollection(ov);
    CC26AnimSpec sp = CC26ResizeSpec();
    BOOL started = NO;
    for (UIViewController *m in ModuleControllers(ov)) {
        NSString *mid = CC26Mid(m);
        NSValue *oldValue = mid.length ? oldFrames[mid] : nil;
        if (!oldValue) continue;
        CGRect oldF = oldValue.CGRectValue;
        CGRect newF = CC26VisibleFrame(m, ov);
        if (CGRectIsEmpty(newF)) continue;
        CGFloat dx = oldF.origin.x - newF.origin.x;
        CGFloat dy = oldF.origin.y - newF.origin.y;
        if (hypot(dx, dy) < 0.5) continue;

        UIView *mover = CC26ModuleMoverView(m, col);
        if (!mover) continue;
        if ([mover.layer animationForKey:@"position"]) continue;

        CABasicAnimation *running = (CABasicAnimation *)[mover.layer animationForKey:@"cc26.slide"];
        if (running && [running.fromValue isKindOfClass:NSValue.class]) {
            CGPoint rf = [running.fromValue CGPointValue];
            if (hypot(rf.x - dx, rf.y - dy) < 0.5) continue;
        }

        CABasicAnimation *slide = [CABasicAnimation animationWithKeyPath:@"position"];
        slide.additive = YES;
        slide.fromValue = [NSValue valueWithCGPoint:CGPointMake(dx, dy)];
        slide.toValue = [NSValue valueWithCGPoint:CGPointZero];
        slide.duration = sp.duration;
        slide.timingFunction = CC26ResizeTiming(sp);
        [mover.layer addAnimation:slide forKey:@"cc26.slide"];
        started = YES;
    }
    return started;
}

static void CC26AnimateChromeRefreshExcluding(UIViewController *ov, NSString *excludeMid) {
    if (!ov || !ov.view || !gEditModeActive) return;
    CC26AnimSpec sp = CC26ResizeSpec();
    UIViewPropertyAnimator *anim = CC26BezierAnimator(sp.duration, sp.c1x, sp.c1y, sp.c2x, sp.c2y);
    [anim addAnimations:^{
        for (UIViewController *m in ModuleControllers(ov)) {
            if (excludeMid.length && [CC26Mid(m) isEqualToString:excludeMid]) continue;
            CC26ApplyChrome(m, ov);
        }
    }];
    [anim startAnimation];
    CC26BringChromeToFront(ov);
}

static void CC26AnimateChromeRefresh(UIViewController *ov) {
    CC26AnimateChromeRefreshExcluding(ov, nil);
}

static void CC26AdjustStatusBar(UIViewController *ov) {
    if (!ov) return;
    CC26 *cc26 = [CC26 shared];
    if ([cc26 respondsToSelector:@selector(adjustStatusBarForOverlay:)]) {
        [cc26 adjustStatusBarForOverlay:ov];
    }
}

static void CC26SettleEditLayoutEx(UIViewController *ov, BOOL refreshChrome) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!gEditModeActive) return;
        if (refreshChrome) CC26AnimateChromeRefresh(ov);
        CC26AdjustStatusBar(ov);
    });
    static const double delays[] = { 0.30, 0.65 };
    for (size_t i = 0; i < sizeof(delays) / sizeof(delays[0]); i++) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delays[i] * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (!gEditModeActive) return;
            CC26AdjustStatusBar(ov);
        });
    }
}

static void CC26SettleEditLayout(UIViewController *ov) {
    CC26SettleEditLayoutEx(ov, YES);
}

static void CC26ForceExitEdit(UIViewController *ov) {
    gEditModeActive = NO;
    gCC26EditEpoch++;
    gCC26PendingResizeID = nil;
    gCC26PendingResizeSize = (CCUILayoutSize){0, 0};
    gCC26PendingResizeLastTouch = 0;
    if (!ov || !ov.view) return;
    for (UIViewController *m in ModuleControllers(ov)) CC26StripChrome(m);
    [[ov.view viewWithTag:kCC26ShieldTag] removeFromSuperview];
    [[ov.view viewWithTag:kCC26ResetTag] removeFromSuperview];
    [[ov.view viewWithTag:kCC26HintTag] removeFromSuperview];
    NSArray<UIGestureRecognizer *> *disabled = objc_getAssociatedObject(ov, kCC26DisabledGesturesKey);
    for (UIGestureRecognizer *gr in disabled) gr.enabled = YES;
    objc_setAssociatedObject(ov, kCC26DisabledGesturesKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UIView *ind = [ov.view viewWithTag:kPageIndicatorTag];
    ind.userInteractionEnabled = YES;
    ind.alpha = 1.0;
}

@interface CC26EditProxy : NSObject <UIGestureRecognizerDelegate>
+ (instancetype)shared;
- (void)bgHold:(UILongPressGestureRecognizer *)g;
- (void)shieldPan:(UIGestureRecognizer *)g;
- (void)shieldTap:(UITapGestureRecognizer *)g;
- (void)resizePan:(UIPanGestureRecognizer *)g;
- (void)removeTap:(UIButton *)b;
- (void)resetTap:(UIButton *)b;
- (void)exitEditOn:(UIViewController *)ov;
- (void)compactGridAfterRemoval:(UIViewController *)ov;
- (void)relayout:(UIViewController *)ov;
- (BOOL)computeArrangementForMid:(NSString *)mid
                             col:(NSUInteger)col
                             row:(NSUInteger)row
                               w:(NSUInteger)w
                               h:(NSUInteger)h
                         overlay:(UIViewController *)ov;
- (void)commitResize:(NSString *)mid w:(NSUInteger)w h:(NSUInteger)h overlay:(UIViewController *)ov;
@end

@implementation CC26EditProxy
+ (instancetype)shared {
    static CC26EditProxy *s; static dispatch_once_t o;
    dispatch_once(&o, ^{ s = [self new]; });
    return s;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldReceiveTouch:(UITouch *)touch {
    if (!CC26EditAllowed()) return NO;
    UIViewController *ov = OverlayIn(UIApplication.sharedApplication.keyWindow.rootViewController);
    if (!ov) return NO;
    if (g.view != ov.view) return YES;
    if ([g isKindOfClass:UILongPressGestureRecognizer.class]) {
        UIView *v = touch.view;
        while (v) {
            for (UIViewController *m in ModuleControllers(ov)) {
                if (m.view == v) return NO;
            }
            if (v == ov.view) break;
            v = v.superview;
        }
    }
    return YES;
}

- (void)bgHold:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan) return;
    if (!CC26EditAllowed()) return;
    CC26RefreshGridConstants();
    UIViewController *ov = OverlayIn(UIApplication.sharedApplication.keyWindow.rootViewController);
    if (!ov) return;

    if (gEditModeActive) {
    if ([ov.view viewWithTag:kCC26ShieldTag].superview) return;
    CC26ForceExitEdit(ov);
    return;
    }

    CGPoint lp = [g locationInView:ov.view];
    if (CC26ModuleAtPoint(lp, ov)) return;

    gEditModeActive = YES;
    gCC26EditEpoch++;
    gEditModeEnteredAt = CACurrentMediaTime();
    gCC26PendingResizeID = nil;
    gCC26PendingResizeSize = (CCUILayoutSize){0, 0};
    gCC26PendingResizeLastTouch = 0;
    if (gHapticsEnabled) Haptic();

    for (UIViewController *m in ModuleControllers(ov)) {
        CC26EnsureBaseSize(m, ov);
        CC26ApplyRadiusToModule(m);
    }

    CC26EditShield *shield = (CC26EditShield *)[ov.view viewWithTag:kCC26ShieldTag];
    if (!shield) {
        shield = [[CC26EditShield alloc] initWithFrame:ov.view.bounds];
        shield.tag = kCC26ShieldTag;
        shield.backgroundColor = UIColor.clearColor;
        shield.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        shield.userInteractionEnabled = YES;

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(shieldPan:)];
        pan.maximumNumberOfTouches = 1;
        pan.cancelsTouchesInView = YES;

        UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(shieldPan:)];
        hold.minimumPressDuration = 0.22;
        hold.allowableMovement = 12.0;
        hold.cancelsTouchesInView = YES;

        [pan requireGestureRecognizerToFail:hold];

        [shield addGestureRecognizer:pan];
        [shield addGestureRecognizer:hold];

        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(shieldTap:)];
        tap.cancelsTouchesInView = NO;
        [shield addGestureRecognizer:tap];

        [ov.view addSubview:shield];
    } else if (shield.superview != ov.view) {
        [shield removeFromSuperview];
        [ov.view addSubview:shield];
    }
    shield.hidden = NO;
    shield.frame = ov.view.bounds;

    NSMutableArray<UIGestureRecognizer *> *disabled = [NSMutableArray array];
    UIView *walk = ov.view.superview;
    while (walk) {
        for (UIGestureRecognizer *gr in walk.gestureRecognizers) {
            if (!gr.enabled) continue;
            if ([gr isKindOfClass:UIPanGestureRecognizer.class] ||
                [gr isKindOfClass:UIPinchGestureRecognizer.class] ||
                [gr isKindOfClass:UISwipeGestureRecognizer.class]) {
                gr.enabled = NO;
                [disabled addObject:gr];
            }
        }
        walk = walk.superview;
    }
    objc_setAssociatedObject(ov, kCC26DisabledGesturesKey, disabled, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    for (UIViewController *m in ModuleControllers(ov)) CC26ApplyChrome(m, ov);

    UIButton *reset = (UIButton *)[ov.view viewWithTag:kCC26ResetTag];
    if (!reset) {
        reset = CC26MakeResetButton();
        [reset addTarget:self action:@selector(resetTap:) forControlEvents:UIControlEventTouchUpInside];
        [ov.view addSubview:reset];
    }
    CGFloat safeTop = ov.view.safeAreaInsets.top;
    if (safeTop < 1.0) safeTop = 20.0;
    reset.center = CGPointMake(CGRectGetMidX(ov.view.bounds), safeTop + 32.0);
    reset.alpha = 0.0;
    reset.transform = CGAffineTransformMakeTranslation(0, -8);
    UIViewPropertyAnimator *resetAnim = CC26BezierAnimator(0.32, 0.32, 0.72, 0.0, 1.0);
    [resetAnim addAnimations:^{
        reset.alpha = 1.0;
        reset.transform = CGAffineTransformIdentity;
    }];
    [resetAnim startAnimationAfterDelay:0.05];
    [ov.view bringSubviewToFront:reset];

    UIView *ind = [ov.view viewWithTag:kPageIndicatorTag];
    ind.userInteractionEnabled = NO;
    [UIView animateWithDuration:0.2 animations:^{ ind.alpha = 0.0; }];
}

- (void)shieldTap:(UITapGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateRecognized) return;
    if (!gEditModeActive) return;
    UIViewController *ov = OverlayIn(UIApplication.sharedApplication.keyWindow.rootViewController);
    if (!ov) return;
    CGPoint pt = [g locationInView:ov.view];
    if (CC26ModuleAtPoint(pt, ov)) return;
    [self exitEditOn:ov];
}

- (void)exitEditOn:(UIViewController *)ov {
    if (!gEditModeActive) return;
    gEditModeActive = NO;
    gCC26EditEpoch++;
    NSUInteger epochAtExit = gCC26EditEpoch;
    gCC26PendingResizeID = nil;
    gCC26PendingResizeSize = (CCUILayoutSize){0, 0};
    gCC26PendingResizeLastTouch = 0;
    if (gHapticsEnabled) Haptic();

    NSMutableArray<UIView *> *chromeViews = [NSMutableArray array];
    for (UIViewController *m in ModuleControllers(ov)) {
        UIView *v = m.view;
        if (!v) continue;
        UIView *b = objc_getAssociatedObject(v, kCC26BorderKey);
        UIButton *rm = objc_getAssociatedObject(v, kCC26RemoveKey);
        UIButton *rz = objc_getAssociatedObject(v, kCC26ResizeKey);
        if (b) [chromeViews addObject:b];
        if (rm) [chromeViews addObject:rm];
        if (rz) [chromeViews addObject:rz];
        objc_setAssociatedObject(CC26ModuleButtonView(v), kCC26IconPinKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(v, kCC26BorderKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(v, kCC26RemoveKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(v, kCC26ResizeKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (chromeViews.count) {
        UIViewPropertyAnimator *exitAnim = CC26BezierAnimator(0.24, 0.4, 0.0, 0.2, 1.0);
        [exitAnim addAnimations:^{
            for (UIView *v in chromeViews) {
                v.alpha = 0.0;
                v.transform = CGAffineTransformMakeScale(0.85, 0.85);
            }
        }];
        [exitAnim addCompletion:^(__unused UIViewAnimatingPosition pos) {
            if (epochAtExit != gCC26EditEpoch) return;
            for (UIView *v in chromeViews) [v removeFromSuperview];
        }];
        [exitAnim startAnimation];
    }

    UIView *shield = [ov.view viewWithTag:kCC26ShieldTag];
    [shield removeFromSuperview];

    NSArray<UIGestureRecognizer *> *disabled = objc_getAssociatedObject(ov, kCC26DisabledGesturesKey);
    for (UIGestureRecognizer *gr in disabled) gr.enabled = YES;
    objc_setAssociatedObject(ov, kCC26DisabledGesturesKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    UIView *reset = [ov.view viewWithTag:kCC26ResetTag];
    reset.tag = 0;
    UIViewPropertyAnimator *resetOut = CC26BezierAnimator(0.2, 0.4, 0.0, 0.2, 1.0);
    [resetOut addAnimations:^{
        reset.alpha = 0.0;
        reset.transform = CGAffineTransformMakeTranslation(0, -8);
    }];
    [resetOut addCompletion:^(__unused UIViewAnimatingPosition pos) {
        if (epochAtExit != gCC26EditEpoch) return;
        [reset removeFromSuperview];
    }];
    [resetOut startAnimation];

    [[ov.view viewWithTag:kCC26HintTag] removeFromSuperview];

    UIView *ind = [ov.view viewWithTag:kPageIndicatorTag];
    ind.userInteractionEnabled = YES;
    [UIView animateWithDuration:0.2 animations:^{ ind.alpha = 1.0; }];
}

- (BOOL)computeArrangementForMid:(NSString *)mid
                             col:(NSUInteger)col
                             row:(NSUInteger)row
                               w:(NSUInteger)w
                               h:(NSUInteger)h
                         overlay:(UIViewController *)ov {
    CC26EnsureStore();
    NSUInteger page = (NSUInteger)gCurrentPage;

    if (!CC26DragSizeAllowedForModule(mid, w, h)) return NO;

    NSArray<NSNumber *> *oldO = CC26GetOrigin(mid);
    if (oldO.count < 2) return NO;
    NSUInteger oldCol = oldO[0].unsignedIntegerValue;
    NSUInteger oldAbs = oldO[1].unsignedIntegerValue;
    NSUInteger oldRow = oldAbs % kCC26Rows;

    NSUInteger oldW = 1, oldH = 1;
    CC26EffectiveSize(mid, &oldW, &oldH);
    if (oldCol == col && oldRow == row && (oldAbs / kCC26Rows) == page &&
        oldW == w && oldH == h) {
        return NO;
    }

    NSMutableDictionary<NSString *, NSValue *> *snapshot = [NSMutableDictionary dictionary];
    for (UIViewController *m in ModuleControllers(ov)) {
        NSString *oid = CC26Mid(m);
        if (!oid.length || [oid isEqualToString:mid]) continue;
        NSArray<NSNumber *> *o = CC26GetOrigin(oid);
        if (o.count < 2) continue;
        NSUInteger oc = o[0].unsignedIntegerValue;
        NSUInteger oa = o[1].unsignedIntegerValue;
        if (oa / kCC26Rows != page) continue;
        NSUInteger orow = oa % kCC26Rows;
        NSUInteger ow = 1, oh = 1;
        CC26EffectiveSize(oid, &ow, &oh);
        CC26Rect r = {oc, orow, ow, oh};
        snapshot[oid] = [NSValue value:&r withObjCType:@encode(CC26Rect)];
    }

    NSMutableDictionary<NSString *, NSValue *> *placed = [NSMutableDictionary dictionaryWithDictionary:snapshot];
    CC26Rect targetRect = {col, row, w, h};
    placed[mid] = [NSValue value:&targetRect withObjCType:@encode(CC26Rect)];

    NSMutableArray<NSString *> *colliders = [NSMutableArray array];
    for (NSString *oid in snapshot) {
        CC26Rect other = {};
        [snapshot[oid] getValue:&other];
        if (CC26RectsOverlap(targetRect, other)) [colliders addObject:oid];
    }

    [colliders sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        CC26Rect ra = {}, rb = {};
        [snapshot[a] getValue:&ra];
        [snapshot[b] getValue:&rb];
        if (ra.r != rb.r) return ra.r < rb.r ? NSOrderedAscending : NSOrderedDescending;
        if (ra.c != rb.c) return ra.c < rb.c ? NSOrderedAscending : NSOrderedDescending;
        return [a compare:b];
    }];

    NSUInteger visibleCap = CC26VisibleRowCap(ov);

    for (NSString *oid in colliders) {
        CC26Rect orig = {};
        [snapshot[oid] getValue:&orig];
        [placed removeObjectForKey:oid];
        NSUInteger maxTopRow = (visibleCap + 1 >= orig.h) ? (visibleCap - orig.h + 1) : 0;
        NSUInteger newC = 0, newR = 0;
        if (!CC26FindFreeCellFor(placed, orig.c, orig.r, orig.w, orig.h, maxTopRow, &newC, &newR)) {
            return NO;
        }
        CC26Rect np = {newC, newR, orig.w, orig.h};
        placed[oid] = [NSValue value:&np withObjCType:@encode(CC26Rect)];
    }

    for (NSString *oid in placed) {
        CC26Rect r = {};
        [placed[oid] getValue:&r];
        CC26SetOrigin(oid, @[@(r.c), @(page * kCC26Rows + r.r)]);
    }
    return YES;
}

- (void)shieldPan:(UIGestureRecognizer *)g {
    if (!CC26EditAllowed()) return;
    UIViewController *ov = OverlayIn(UIApplication.sharedApplication.keyWindow.rootViewController);
    if (!ov) return;
    CC26RefreshGridConstants();

    if (g.state == UIGestureRecognizerStateBegan) {
        CGPoint pt = [g locationInView:ov.view];
        UIViewController *src = CC26ModuleAtPoint(pt, ov);
        if (!src) return;
        NSString *mid = CC26Mid(src);
        if (!mid.length) return;

        CGRect vis = CC26VisibleFrame(src, ov);
        CGPoint grab = CGPointMake(pt.x - CGRectGetMinX(vis), pt.y - CGRectGetMinY(vis));

        UIView *shadow = [[UIView alloc] initWithFrame:vis];
        shadow.tag = kCC26ProxyShadowTag;
        shadow.userInteractionEnabled = NO;
        shadow.backgroundColor = UIColor.clearColor;
        shadow.layer.shadowColor = UIColor.blackColor.CGColor;
        shadow.layer.shadowOpacity = 0.35;
        shadow.layer.shadowRadius = 16.0;
        shadow.layer.shadowOffset = CGSizeMake(0, 8);
        shadow.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:shadow.bounds
                                                            cornerRadius:src.view.layer.cornerRadius].CGPath;
        [ov.view addSubview:shadow];

        BOOL liquidassActive = CC26LIQIsActive();
        CGFloat proxyRadius = src.view.layer.cornerRadius;

        UIView *proxy;
        if (liquidassActive) {
            proxy = [[CC26LiveGlassProxyView alloc] initWithFrame:shadow.bounds];
        } else {
            proxy = [[UIView alloc] initWithFrame:shadow.bounds];
        }
        proxy.tag = kCC26ProxyTag;
        proxy.userInteractionEnabled = NO;
        proxy.layer.cornerRadius = proxyRadius;
        proxy.layer.cornerCurve = kCACornerCurveContinuous;
        proxy.layer.masksToBounds = YES;

        if (liquidassActive) {
            proxy.backgroundColor = UIColor.clearColor;
            if (kClsCABackdropLayer && [proxy.layer isKindOfClass:kClsCABackdropLayer]) {
                [proxy.layer setValue:@NO  forKey:@"layerUsesCoreImageFilters"];
                [proxy.layer setValue:@YES forKey:@"windowServerAware"];
                [proxy.layer setValue:@"dylv.liquidglass.sharedGroup" forKey:@"groupName"];
                [proxy.layer setValue:@"dylv.liquidglass" forKey:@"groupNamespace"];
                [proxy.layer setValue:@(0.5) forKey:@"scale"];
                id glassFilter = CC26LIQBuildGlassFilter();
                if (glassFilter) proxy.layer.filters = @[glassFilter];
            }
        } else {
            proxy.backgroundColor = [UIColor colorWithWhite:0.2 alpha:0.6];
        }

        UIImage *snapImage = CC26SnapshotContentOnly(src.view, liquidassActive);
        if (snapImage) {
            UIImageView *snap = [[UIImageView alloc] initWithImage:snapImage];
            snap.frame = proxy.bounds;
            snap.contentMode = UIViewContentModeScaleToFill;
            snap.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            [proxy addSubview:snap];
        }
        [shadow addSubview:proxy];

        UIView *pres = objc_getAssociatedObject(src.view, kCC26PresKey);
        [UIView animateWithDuration:0.12
                              delay:0.0
                            options:UIViewAnimationOptionCurveEaseOut |
                                    UIViewAnimationOptionBeginFromCurrentState |
                                    UIViewAnimationOptionAllowUserInteraction
                         animations:^{
            src.view.alpha = 0.0;
            pres.alpha = 0.0;
        } completion:nil];
        for (UIViewController *m in ModuleControllers(ov)) CC26StripChrome(m);

        NSDictionary *origLayout = [gEditOrigins copy] ?: @{};
        objc_setAssociatedObject(g, kCC26OrigLayoutKey, origLayout, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        objc_setAssociatedObject(g, kCC26LastCellKey, @[@(NSIntegerMax), @(NSIntegerMax)], OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        objc_setAssociatedObject(g, kCC26DragSrcKey,   src,    OBJC_ASSOCIATION_ASSIGN);
        objc_setAssociatedObject(g, kCC26DragProxyKey, shadow, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(g, kCC26DragGrabKey,  [NSValue valueWithCGPoint:grab], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (gHapticsEnabled) Haptic();

    } else if (g.state == UIGestureRecognizerStateChanged) {
        UIViewController *src = objc_getAssociatedObject(g, kCC26DragSrcKey);
        UIView *shadow = objc_getAssociatedObject(g, kCC26DragProxyKey);
        NSValue *gv = objc_getAssociatedObject(g, kCC26DragGrabKey);
        if (!src || !shadow || !gv) return;
        CGPoint grab = gv.CGPointValue;
        CGPoint pt = [g locationInView:ov.view];
        NSString *mid = CC26Mid(src);
        NSUInteger w = 1, h = 1;
        CC26EffectiveSize(mid, &w, &h);
        CGPoint base = CC26GridBase(ov);

        CGRect f = shadow.frame;
        f.origin = CGPointMake(pt.x - grab.x, pt.y - grab.y);
        shadow.frame = f;

        NSInteger col = (NSInteger)lround((CGRectGetMinX(f) - base.x) / kCC26Step);
        NSInteger row = (NSInteger)lround((CGRectGetMinY(f) - base.y) / kCC26Step);
        col = MAX(0, MIN((NSInteger)kCC26Cols - (NSInteger)w, col));
        NSUInteger cap = CC26VisibleRowCap(ov);
        NSInteger maxRow = MAX(0, (NSInteger)cap - (NSInteger)h + 1);
        row = MAX(0, MIN(maxRow, row));

        NSArray<NSNumber *> *last = objc_getAssociatedObject(g, kCC26LastCellKey);
        if (!last ||
            [last[0] integerValue] != col ||
            [last[1] integerValue] != row) {
            objc_setAssociatedObject(g, kCC26LastCellKey, @[@(col), @(row)], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            if ([self computeArrangementForMid:mid
                                          col:(NSUInteger)col
                                          row:(NSUInteger)row
                                            w:w h:h
                                      overlay:ov]) {
                [self relayout:ov];
            }
        }

    } else if (g.state == UIGestureRecognizerStateEnded ||
               g.state == UIGestureRecognizerStateCancelled ||
               g.state == UIGestureRecognizerStateFailed) {
        UIViewController *src = objc_getAssociatedObject(g, kCC26DragSrcKey);
        UIView *shadow = objc_getAssociatedObject(g, kCC26DragProxyKey);
        __block UIViewController *heldSrc = src;

        if (g.state != UIGestureRecognizerStateEnded) {
            NSDictionary *origLayout = objc_getAssociatedObject(g, kCC26OrigLayoutKey);
            if (origLayout) {
                CC26EnsureStore();
                [gEditOrigins removeAllObjects];
                [gEditOrigins addEntriesFromDictionary:origLayout];
                CC26SaveStore();
                [self relayout:ov];
            }
        } else {
            CC26SaveStore();
        }

        if (shadow) {
            [shadow removeFromSuperview];
        }
        NSUInteger epochAtDragEnd = gCC26EditEpoch;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.06 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (epochAtDragEnd != gCC26EditEpoch) return;
            if (!gEditModeActive) return;
            UIViewController *releaseSrc = heldSrc;
            if (releaseSrc) {
                UIView *pres = objc_getAssociatedObject(releaseSrc.view, kCC26PresKey);
                [UIView animateWithDuration:0.18
                                      delay:0.0
                                    options:UIViewAnimationOptionCurveEaseOut |
                                            UIViewAnimationOptionBeginFromCurrentState |
                                            UIViewAnimationOptionAllowUserInteraction
                                 animations:^{
                    releaseSrc.view.alpha = 1.0;
                    pres.alpha = 1.0;
                } completion:nil];
            }
            for (UIViewController *m in ModuleControllers(ov)) {
                CC26ApplyRadiusToModule(m);
                CC26ApplyChrome(m, ov);
                CC26RefreshPresentation(m, ov);
            }
            UIView *shield = [ov.view viewWithTag:kCC26ShieldTag];
            if (shield) [ov.view bringSubviewToFront:shield];
            for (UIViewController *m in ModuleControllers(ov)) {
                UIButton *rm = objc_getAssociatedObject(m.view, kCC26RemoveKey);
                UIButton *rz = objc_getAssociatedObject(m.view, kCC26ResizeKey);
                if (rm) [ov.view bringSubviewToFront:rm];
                if (rz) [ov.view bringSubviewToFront:rz];
                UIView *pr = objc_getAssociatedObject(m.view, kCC26PresKey);
                if (pr) [ov.view bringSubviewToFront:pr];
            }
            UIView *rp = [ov.view viewWithTag:kCC26ResetTag];
            if (rp) [ov.view bringSubviewToFront:rp];
        });

        objc_setAssociatedObject(g, kCC26DragSrcKey,   nil, OBJC_ASSOCIATION_ASSIGN);
        objc_setAssociatedObject(g, kCC26DragProxyKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(g, kCC26DragGrabKey,  nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(g, kCC26LastCellKey,  nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(g, kCC26OrigLayoutKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

- (void)compactGridAfterRemoval:(UIViewController *)ov {
    CC26EnsureStore();
    NSUInteger page = (NSUInteger)gCurrentPage;
    NSUInteger cap  = CC26VisibleRowCap(ov);

    NSMutableDictionary<NSString *, NSValue *> *placed = [NSMutableDictionary dictionary];
    NSMutableArray<NSDictionary *> *entries = [NSMutableArray array];

    for (UIViewController *m in ModuleControllers(ov)) {
        NSString *mid = CC26Mid(m);
        if (!mid.length) continue;
        NSArray<NSNumber *> *o = CC26GetOrigin(mid);
        if (o.count < 2) continue;
        NSUInteger abs = o[1].unsignedIntegerValue;
        if (abs / kCC26Rows != page) continue;

        NSUInteger w = 1, h = 1;
        CC26EffectiveSize(mid, &w, &h);
        NSUInteger c = o[0].unsignedIntegerValue;
        NSUInteger r = abs % kCC26Rows;

        CC26Rect rect = {c, r, w, h};
        placed[mid] = [NSValue value:&rect withObjCType:@encode(CC26Rect)];
        [entries addObject:@{@"mid":mid, @"c":@(c), @"r":@(r), @"w":@(w), @"h":@(h)}];
    }

    [entries sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSInteger ar = [a[@"r"] integerValue], br = [b[@"r"] integerValue];
        if (ar != br) return ar < br ? NSOrderedAscending : NSOrderedDescending;
        NSInteger ac = [a[@"c"] integerValue], bc = [b[@"c"] integerValue];
        return ac < bc ? NSOrderedAscending : (ac > bc ? NSOrderedDescending : NSOrderedSame);
    }];

    for (NSDictionary *e in entries) {
        NSString *mid = e[@"mid"];
        NSUInteger w = [e[@"w"] unsignedIntegerValue];
        NSUInteger h = [e[@"h"] unsignedIntegerValue];
        NSInteger oc = [e[@"c"] integerValue];
        NSInteger orr = [e[@"r"] integerValue];

        [placed removeObjectForKey:mid];

        NSInteger maxC = (NSInteger)kCC26Cols - (NSInteger)w;
        NSInteger maxR = (NSInteger)MIN(cap, kCC26Rows - 1) - (NSInteger)h + 1;
        NSInteger bestC = oc, bestR = orr;
        NSInteger bestScore = NSIntegerMax;
        BOOL found = NO;

        for (NSInteger r = 0; r <= maxR; r++) {
            for (NSInteger c = 0; c <= maxC; c++) {
                if (r > orr) continue;
                if (r == orr && c >= oc) continue;

                CC26Rect t = {(NSUInteger)c, (NSUInteger)r, w, h};
                BOOL ok = YES;
                for (NSValue *v in placed.allValues) {
                    CC26Rect o = {};
                    [v getValue:&o];
                    if (CC26RectsOverlap(t, o)) { ok = NO; break; }
                }
                if (!ok) continue;

                NSInteger score = r * (NSInteger)kCC26Cols + c;
                if (score < bestScore) {
                    bestScore = score;
                    bestC = c;
                    bestR = r;
                    found = YES;
                }
            }
        }

        CC26Rect rect = {(NSUInteger)bestC, (NSUInteger)bestR, w, h};
        placed[mid] = [NSValue value:&rect withObjCType:@encode(CC26Rect)];
        if (found) {
            CC26SetOrigin(mid, @[@(bestC), @(page * kCC26Rows + bestR)]);
        }
    }
    CC26SaveStore();
}

- (void)relayout:(UIViewController *)ov {
    UIViewController *col = ModuleCollection(ov);
    if (!col) return;

    SEL providerSel = NSSelectorFromString(@"_activePositionProvider");
    id provider = [col respondsToSelector:providerSel]
        ? ((id (*)(id, SEL))objc_msgSend)(col, providerSel) : nil;
    SEL regenSel = NSSelectorFromString(@"regenerateRectsWithOrderedIdentifiers:orderedSizes:");
    if (provider && [provider respondsToSelector:regenSel]) {
        NSMutableArray<NSString *> *ids = [NSMutableArray array];
        NSMutableArray<NSValue *> *sizes = [NSMutableArray array];
        for (UIViewController *m in ModuleControllers(ov)) {
            NSString *mid = CC26Mid(m);
            if (!mid.length) continue;
            NSUInteger w = 1, h = 1;
            CC26EffectiveSize(mid, &w, &h);
            CCUILayoutSize sz = {w, h};
            [ids addObject:mid];
            [sizes addObject:[NSValue value:&sz withObjCType:@encode(CCUILayoutSize)]];
        }
        if (ids.count) {
            ((void (*)(id, SEL, id, id))objc_msgSend)(provider, regenSel, ids, sizes);
        }
    }

    for (UIViewController *m in ModuleControllers(ov)) [m.view setNeedsLayout];
    [col.view setNeedsLayout];

    void (^fixups)(void) = ^{
        for (UIViewController *m in ModuleControllers(ov)) {
            UIView *superview = m.view.superview;
            if (!superview || superview == col.view) continue;
            NSString *sn = NSStringFromClass(superview.class);
            if (![sn containsString:@"ContentModuleContainer"] &&
                ![sn containsString:@"ModuleWrapper"]) continue;
            CGRect target = superview.bounds;
            if (!CGRectEqualToRect(m.view.bounds, target)) {
                m.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
                m.view.frame = target;
            }
        }
        for (UIViewController *m in ModuleControllers(ov)) CC26ApplyRadiusToModule(m);
    };

    if (gExperimentalPagingEnabled) {
        UIViewPropertyAnimator *relayout = CC26BezierAnimator(0.58, 0.32, 0.72, 0.0, 1.0);
        [relayout addAnimations:^{
            for (UIViewController *m in ModuleControllers(ov)) [m.view layoutIfNeeded];
            [col.view layoutIfNeeded];
        }];
        [relayout addCompletion:^(UIViewAnimatingPosition finalPosition) {
            if (finalPosition != UIViewAnimatingPositionEnd) return;
            fixups();
        }];
        [relayout startAnimation];
    } else {
        [UIView performWithoutAnimation:^{
            for (UIViewController *m in ModuleControllers(ov)) [m.view layoutIfNeeded];
            [col.view layoutIfNeeded];
        }];
        fixups();
    }
}

- (void)resizePan:(UIPanGestureRecognizer *)g {
    if (!CC26EditAllowed()) return;
    UIButton *btn = (UIButton *)g.view;
    NSString *mid = objc_getAssociatedObject(btn, kCC26MidKey);
    if (!mid.length) return;
    CC26RefreshGridConstants();
    gCC26PendingResizeLastTouch = CACurrentMediaTime();
    UIViewController *ov = OverlayIn(UIApplication.sharedApplication.keyWindow.rootViewController);
    if (!ov) return;

    if (g.state == UIGestureRecognizerStateBegan) {
        CC26EnsureStore();
        NSUInteger sw = 1, sh = 1;
        CC26EffectiveSize(mid, &sw, &sh);
        objc_setAssociatedObject(g, kCC26StartSzKey, @[@(sw), @(sh)], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        gCC26PendingResizeID = [mid copy];
        gCC26PendingResizeSize = (CCUILayoutSize){sw, sh};
        if (gHapticsEnabled) Haptic();

    } else if (g.state == UIGestureRecognizerStateChanged) {
        NSArray<NSNumber *> *s = objc_getAssociatedObject(g, kCC26StartSzKey);
        if (s.count < 2) return;
        NSUInteger sw = s[0].unsignedIntegerValue, sh = s[1].unsignedIntegerValue;
        CGPoint t = [g translationInView:ov.view];
        CCUILayoutSize next = CC26ResizeCandidate(mid, sw, sh, t);
        if (!CC26SizeAllowed(next.width, next.height)) {
            next = gCC26PendingResizeSize;
        }
        if (next.width != gCC26PendingResizeSize.width ||
            next.height != gCC26PendingResizeSize.height) {
            gCC26PendingResizeSize = next;

            NSArray<NSNumber *> *cur = CC26GetOrigin(mid);
            if (cur.count >= 2) {
                NSUInteger cCol = cur[0].unsignedIntegerValue;
                NSUInteger cAbs = cur[1].unsignedIntegerValue;
                NSUInteger cRow = cAbs % kCC26Rows;
                [self computeArrangementForMid:mid
                                           col:cCol
                                           row:cRow
                                             w:next.width
                                             h:next.height
                                       overlay:ov];
            }

            [self relayout:ov];
            CC26SettleEditLayout(ov);
        }

    } else if (g.state == UIGestureRecognizerStateEnded ||
               g.state == UIGestureRecognizerStateCancelled ||
               g.state == UIGestureRecognizerStateFailed) {
        CCUILayoutSize p = gCC26PendingResizeSize;
        gCC26PendingResizeID = nil;
        gCC26PendingResizeSize = (CCUILayoutSize){0, 0};
        if (g.state == UIGestureRecognizerStateEnded && p.width && p.height &&
            CC26SizeAllowed(p.width, p.height)) {
            [self commitResize:mid w:p.width h:p.height overlay:ov];
        }
        objc_setAssociatedObject(g, kCC26StartSzKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [self relayout:ov];
        CC26SettleEditLayout(ov);
        NSUInteger epochAtResizeEnd = gCC26EditEpoch;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.30 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (epochAtResizeEnd != gCC26EditEpoch) return;
            if (!gEditModeActive) return;
            for (UIViewController *m in ModuleControllers(ov)) {
                CC26ApplyRadiusToModule(m);
                CC26ApplyChrome(m, ov);
                CC26RefreshPresentation(m, ov);
            }
            UIView *shield = [ov.view viewWithTag:kCC26ShieldTag];
            if (shield) [ov.view bringSubviewToFront:shield];
            for (UIViewController *m in ModuleControllers(ov)) {
                UIButton *rm = objc_getAssociatedObject(m.view, kCC26RemoveKey);
                UIButton *rz = objc_getAssociatedObject(m.view, kCC26ResizeKey);
                if (rm) [ov.view bringSubviewToFront:rm];
                if (rz) [ov.view bringSubviewToFront:rz];
                UIView *pr = objc_getAssociatedObject(m.view, kCC26PresKey);
                if (pr) [ov.view bringSubviewToFront:pr];
            }
            UIView *rp = [ov.view viewWithTag:kCC26ResetTag];
            if (rp) [ov.view bringSubviewToFront:rp];
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.62 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (epochAtResizeEnd != gCC26EditEpoch) return;
            if (!gEditModeActive) return;
            for (UIViewController *m in ModuleControllers(ov)) {
                CC26ApplyRadiusToModule(m);
                CC26RefreshPresentation(m, ov);
            }
        });
    }
}

- (void)commitResize:(NSString *)mid w:(NSUInteger)w h:(NSUInteger)h overlay:(UIViewController *)ov {
    CC26EnsureStore();
    if (!CC26SizeAllowed(w, h)) return;

    NSArray<NSNumber *> *o = CC26GetOrigin(mid);
    if (o.count < 2) return;
    NSUInteger col = o[0].unsignedIntegerValue;
    NSUInteger absRow = o[1].unsignedIntegerValue;
    NSUInteger page = absRow / kCC26Rows;
    NSUInteger row = absRow % kCC26Rows;
    if (col + w > kCC26Cols) w = kCC26Cols - col;
    if (row + h > kCC26Rows) h = kCC26Rows - row;
    if (!CC26SizeAllowed(w, h)) return;

    NSUInteger capR = CC26VisibleRowCap(ov);

    NSMutableDictionary<NSString *, NSValue *> *snapshot = [NSMutableDictionary dictionary];
    for (UIViewController *m in ModuleControllers(ov)) {
        NSString *oid = CC26Mid(m);
        if (!oid.length || [oid isEqualToString:mid]) continue;
        NSArray<NSNumber *> *oo = CC26GetOrigin(oid);
        if (oo.count < 2) continue;
        NSUInteger oc = oo[0].unsignedIntegerValue;
        NSUInteger oa = oo[1].unsignedIntegerValue;
        if (oa / kCC26Rows != page) continue;
        NSUInteger orow = oa % kCC26Rows;
        NSUInteger ow = 1, oh = 1;
        CC26EffectiveSize(oid, &ow, &oh);
        CC26Rect r = {oc, orow, ow, oh};
        snapshot[oid] = [NSValue value:&r withObjCType:@encode(CC26Rect)];
    }

    BOOL resolved = NO;

    if (row + h <= capR + 1) {
        CC26Rect targetRect = {col, row, w, h};

        NSMutableDictionary<NSString *, NSValue *> *placed =
            [NSMutableDictionary dictionaryWithDictionary:snapshot];

        NSMutableArray<NSString *> *colliders = [NSMutableArray array];
        for (NSString *oid in snapshot) {
            CC26Rect other = {};
            [snapshot[oid] getValue:&other];
            if (CC26RectsOverlap(targetRect, other)) [colliders addObject:oid];
        }
        for (NSString *oid in colliders) [placed removeObjectForKey:oid];
        placed[mid] = [NSValue value:&targetRect withObjCType:@encode(CC26Rect)];

        [colliders sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
            CC26Rect ra = {}, rb = {};
            [snapshot[a] getValue:&ra];
            [snapshot[b] getValue:&rb];
            if (ra.r != rb.r) return ra.r < rb.r ? NSOrderedAscending : NSOrderedDescending;
            if (ra.c != rb.c) return ra.c < rb.c ? NSOrderedAscending : NSOrderedDescending;
            return [a compare:b];
        }];

        BOOL allFit = YES;
        for (NSString *oid in colliders) {
            CC26Rect orig = {};
            [snapshot[oid] getValue:&orig];
            NSUInteger cMaxRow = (capR + 1 >= orig.h) ? (capR - orig.h + 1) : 0;
            NSUInteger nc = 0, nr = 0;
            if (!CC26FindFreeCellFor(placed, orig.c, orig.r, orig.w, orig.h, cMaxRow, &nc, &nr)) {
                allFit = NO;
                break;
            }
            CC26Rect np = {nc, nr, orig.w, orig.h};
            placed[oid] = [NSValue value:&np withObjCType:@encode(CC26Rect)];
        }

        if (allFit) {
            resolved = YES;
            gEditSizes[mid] = @[@(w), @(h)];
            for (NSString *oid in placed) {
                CC26Rect r = {};
                [placed[oid] getValue:&r];
                CC26SetOrigin(oid, @[@(r.c), @(page * kCC26Rows + r.r)]);
            }
        }
    }

    if (!resolved) {
        NSMutableDictionary<NSString *, NSValue *> *placed =
            [NSMutableDictionary dictionaryWithDictionary:snapshot];
        NSUInteger cMaxRow = (capR + 1 >= h) ? (capR - h + 1) : 0;
        NSUInteger newCol = 0, newRow = 0;
        if (!CC26FindFreeCellFor(placed, col, row, w, h, cMaxRow, &newCol, &newRow)) return;
        gEditSizes[mid]   = @[@(w), @(h)];
        CC26SetOrigin(mid, @[@(newCol), @(page * kCC26Rows + newRow)]);
    }

    CC26InvalidateOtherOrientationOriginForModule(mid);
    CC26SaveStore();

    NSMutableSet<NSString *> *resized = objc_getAssociatedObject(UIApplication.sharedApplication, kCC26ResizedSetKey);
    if (!resized) {
        resized = [NSMutableSet set];
        objc_setAssociatedObject(UIApplication.sharedApplication, kCC26ResizedSetKey, resized, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [resized addObject:mid];

    for (UIViewController *m in ModuleControllers(ov)) {
        if (![CC26Mid(m) isEqualToString:mid]) continue;
        id contentModule = nil;
        @try { contentModule = [m valueForKey:@"module"]; } @catch (__unused NSException *e) {}
        id ctx = nil;
        @try { ctx = [contentModule valueForKey:@"contentModuleContext"]; } @catch (__unused NSException *e) {}
        if ([ctx respondsToSelector:NSSelectorFromString(@"requestLayoutSizeUpdate")]) {
            ((void (*)(id, SEL))objc_msgSend)(ctx, NSSelectorFromString(@"requestLayoutSizeUpdate"));
        }
        break;
    }
}

- (void)removeTap:(UIButton *)b {
    if (!gEditModeActive) return;
    NSString *mid = objc_getAssociatedObject(b, kCC26MidKey);
    if (!mid.length) return;
    if (gHapticsEnabled) Haptic();

    UIViewController *ov = OverlayIn(UIApplication.sharedApplication.keyWindow.rootViewController);
    if (!ov) return;

    UIViewController *victim = nil;
    for (UIViewController *m in ModuleControllers(ov)) {
        if ([CC26Mid(m) isEqualToString:mid]) { victim = m; break; }
    }
    UIView   *victimBorder = victim ? objc_getAssociatedObject(victim.view, kCC26BorderKey) : nil;
    UIButton *victimRM     = victim ? objc_getAssociatedObject(victim.view, kCC26RemoveKey) : nil;
    UIButton *victimRZ     = victim ? objc_getAssociatedObject(victim.view, kCC26ResizeKey) : nil;

    if (victim) {
        [UIView animateWithDuration:0.24
                              delay:0.0
                            options:UIViewAnimationOptionCurveEaseIn |
                                    UIViewAnimationOptionBeginFromCurrentState |
                                    UIViewAnimationOptionAllowUserInteraction
                         animations:^{
            CGAffineTransform s = CGAffineTransformMakeScale(0.35, 0.35);
            victim.view.transform   = s;  victim.view.alpha   = 0.0;
            victimBorder.transform  = s;  victimBorder.alpha  = 0.0;
            victimRM.transform      = s;  victimRM.alpha      = 0.0;
            victimRZ.transform      = s;  victimRZ.alpha      = 0.0;
        } completion:nil];
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.24 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        id prov = CC26SettingsProvider();
        SEL get = NSSelectorFromString(@"orderedUserEnabledModuleIdentifiers");
        SEL set = NSSelectorFromString(@"setAndSaveOrderedUserEnabledModuleIdentifiers:");

        NSUInteger visibleCount = 0;
        for (UIViewController *m in ModuleControllers(ov)) {
            if (CC26Mid(m).length) visibleCount++;
        }
        NSArray *enabledNow = [prov respondsToSelector:get] ? ((id (*)(id, SEL))objc_msgSend)(prov, get) : nil;
        NSUInteger enabledCount = [enabledNow isKindOfClass:NSArray.class] ? enabledNow.count : 0;
        BOOL slide = CC26IsNonNotchedDevice() && (visibleCount == 12 || enabledCount == 12);
        NSDictionary<NSString *, NSValue *> *oldFrames = slide ? CC26CaptureModuleFrames(ov, mid) : nil;

        if ([prov respondsToSelector:get] && [prov respondsToSelector:set]) {
            NSArray *ids = ((id (*)(id, SEL))objc_msgSend)(prov, get);
            NSMutableArray *mut = [ids mutableCopy];
            [mut removeObject:mid];
            ((void (*)(id, SEL, id))objc_msgSend)(prov, set, mut);
        }

        CC26EnsureStore();
        CC26SetOrigin(mid, nil);
        [gEditSizes removeObjectForKey:mid];
        CC26InvalidateOtherOrientationOriginForModule(mid);
        CC26SaveStore();

        if (victim) CC26StripChrome(victim);
        [victimBorder removeFromSuperview];
        [victimRM removeFromSuperview];
        [victimRZ removeFromSuperview];

        [self compactGridAfterRemoval:ov];
        [self relayout:ov];

        NSTimeInterval settleDelay = 0.45;
        if (slide) {
            CC26SlideModules(ov, oldFrames);
            CC26AnimateChromeRefreshExcluding(ov, mid);
            CC26SettleEditLayoutEx(ov, NO);
            CFTimeInterval startedAt = CACurrentMediaTime();
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!gEditModeActive) return;
                if (CACurrentMediaTime() - startedAt > 0.1) return;
                if (CC26SlideModules(ov, oldFrames)) CC26AnimateChromeRefreshExcluding(ov, mid);
            });
            settleDelay = MAX(settleDelay, CC26ResizeSpec().duration + 0.08);
        } else {
            CC26SettleEditLayout(ov);
        }

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(settleDelay * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (!gEditModeActive) return;
            for (UIViewController *m in ModuleControllers(ov)) {
                CC26ApplyRadiusToModule(m);
                CC26ApplyChrome(m, ov);
                CC26RefreshPresentation(m, ov);
            }
            UIView *shield = [ov.view viewWithTag:kCC26ShieldTag];
            if (shield) [ov.view bringSubviewToFront:shield];
            for (UIViewController *m in ModuleControllers(ov)) {
                UIButton *rm = objc_getAssociatedObject(m.view, kCC26RemoveKey);
                UIButton *rz = objc_getAssociatedObject(m.view, kCC26ResizeKey);
                if (rm) [ov.view bringSubviewToFront:rm];
                if (rz) [ov.view bringSubviewToFront:rz];
                UIView *pr = objc_getAssociatedObject(m.view, kCC26PresKey);
                if (pr) [ov.view bringSubviewToFront:pr];
            }
            UIView *rp = [ov.view viewWithTag:kCC26ResetTag];
            if (rp) [ov.view bringSubviewToFront:rp];
        });
    });
}

- (void)resetTap:(UIButton *)b {
    if (!gEditModeActive) return;
    CC26RefreshGridConstants();
    gCC26EditEpoch++;
    NSUInteger epochAtReset = gCC26EditEpoch;
    gEditModeEnteredAt = CACurrentMediaTime();
    gCC26PendingResizeID = nil;
    gCC26PendingResizeSize = (CCUILayoutSize){0, 0};
    gCC26PendingResizeLastTouch = 0;
    if (gHapticsEnabled) {
        UIImpactFeedbackGenerator *gen = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
        [gen prepare];
        [gen impactOccurred];
    }

    UIViewController *ov = OverlayIn(UIApplication.sharedApplication.keyWindow.rootViewController);
    if (!ov) return;

    for (UIViewController *m in ModuleControllers(ov)) {
        CC26EnsureBaseSize(m, ov);
    }

    NSArray<NSString *> *ordered = CC26ProviderOrderedIdentifiers();

    CC26EnsureStore();
    NSString *prefix = CC26IsLandscape() ? @"L|" : @"P|";
    for (NSString *key in [gEditOrigins.allKeys copy]) {
        if ([key hasPrefix:prefix]) [gEditOrigins removeObjectForKey:key];
    }
    [gEditSizes removeAllObjects];

    NSMutableDictionary<NSString *, NSValue *> *placed = [NSMutableDictionary dictionary];

    NSMutableArray<NSString *> *ids = [NSMutableArray array];
    if (ordered.count) [ids addObjectsFromArray:ordered];
    for (UIViewController *m in ModuleControllers(ov)) {
        NSString *mid = CC26Mid(m);
        if (!mid.length) continue;
        if (![ids containsObject:mid]) [ids addObject:mid];
    }

    NSUInteger perPage = kCC26Rows;
    for (NSString *mid in ids) {
        NSArray<NSNumber *> *base = gEditBaseSizes[mid];
        if (base.count < 2) base = CC26KnownBaseSize(mid);
        if (base.count < 2) continue;
        NSUInteger w = base[0].unsignedIntegerValue;
        NSUInteger h = base[1].unsignedIntegerValue;
        if (w == 0 || h == 0 || w > kCC26Cols || h > kCC26Rows) continue;

        BOOL found = NO;
        for (NSUInteger page = 0; page < 4 && !found; page++) {
            NSUInteger maxR = kCC26Rows - h;
            NSUInteger maxC = kCC26Cols - w;
            for (NSUInteger r = 0; r <= maxR && !found; r++) {
                for (NSUInteger c = 0; c <= maxC; c++) {
                    CC26Rect t = {c, r, w, h};
                    BOOL ok = YES;
                    for (NSValue *v in placed.allValues) {
                        CC26Rect o = {};
                        [v getValue:&o];
                        if (CC26RectsOverlap(t, o)) { ok = NO; break; }
                    }
                    if (!ok) continue;
                    CC26Rect copy = t;
                    placed[mid] = [NSValue value:&copy withObjCType:@encode(CC26Rect)];
                    CC26SetOrigin(mid, @[@(c), @(page * perPage + r)]);
                    found = YES;
                    break;
                }
            }
        }
    }
    CC26SaveStore();

    for (UIViewController *m in ModuleControllers(ov)) CC26StripChrome(m);
    UIView *hint = [ov.view viewWithTag:kCC26HintTag];
    hint.hidden = YES;

    [UIView animateWithDuration:0.10 animations:^{
        b.transform = CGAffineTransformMakeScale(0.94, 0.94);
    } completion:^(__unused BOOL f) {
        [UIView animateWithDuration:0.18 delay:0.0
                            options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState
                         animations:^{ b.transform = CGAffineTransformIdentity; }
                         completion:nil];
    }];

    [self relayout:ov];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (epochAtReset != gCC26EditEpoch) return;
        if (!gEditModeActive) return;
        for (UIViewController *m in ModuleControllers(ov)) {
            CC26ApplyRadiusToModule(m);
            CC26ApplyChrome(m, ov);
            CC26RefreshPresentation(m, ov);
        }
        UIView *shield = [ov.view viewWithTag:kCC26ShieldTag];
        if (shield) [ov.view bringSubviewToFront:shield];
        for (UIViewController *m in ModuleControllers(ov)) {
            UIButton *rm = objc_getAssociatedObject(m.view, kCC26RemoveKey);
            UIButton *rz = objc_getAssociatedObject(m.view, kCC26ResizeKey);
            if (rm) [ov.view bringSubviewToFront:rm];
            if (rz) [ov.view bringSubviewToFront:rz];
            UIView *pr = objc_getAssociatedObject(m.view, kCC26PresKey);
            if (pr) [ov.view bringSubviewToFront:pr];
        }
        [ov.view bringSubviewToFront:b];
    });
}

@end

static void CC26RefreshPresentationImpl(UIViewController *m, UIViewController *ov) {
    if (!m || !m.view) return;
    NSString *mid = CC26Mid(m);
    if (!mid.length) return;

    CC26EnsureStore();
    CC26EnsureBaseSize(m, ov);

    if (CC26ModuleIsExpanded(m)) return;

    NSUInteger curW = 1, curH = 1;
    CC26PresentationSize(mid, &curW, &curH);

    UIView *buttonView = CC26ModuleButtonView(m.view);
    if (!buttonView) return;

    BOOL animate = CC26AnimationsAllowed();
    NSUInteger radiusW = 1, radiusH = 1;
    CC26EffectiveSize(mid, &radiusW, &radiusH);
    CGFloat radius = CC26RadiusForSize(radiusW, radiusH);
    CC26SetRadius(buttonView.layer, radius, animate && objc_getAssociatedObject(m.view, kCC26LastRadiusKey) != nil);

    BOOL isResizedFromOneByOne = CC26WasResizedFromOneByOne(mid);

    UIView *pres = objc_getAssociatedObject(m.view, kCC26PresKey);
    if (!isResizedFromOneByOne) {
        if (pres) {
            objc_setAssociatedObject(m.view, kCC26PresKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            if (animate && pres.superview) {
                [UIView animateWithDuration:0.15
                                      delay:0.0
                                    options:UIViewAnimationOptionBeginFromCurrentState |
                                            UIViewAnimationOptionAllowUserInteraction
                                 animations:^{ pres.alpha = 0.0; }
                                 completion:^(__unused BOOL finished) { [pres removeFromSuperview]; }];
            } else {
                [pres removeFromSuperview];
            }
        }
        objc_setAssociatedObject(m.view, kCC26LastPresKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        CC26RestoreModuleIcon(m);
        return;
    }

    CC26LayoutModuleIcon(m);

    NSString *newText = CC26PrettyNameForModule(m);
    CGSize bvSize = buttonView.bounds.size;
    NSUInteger sig = 1469598103934665603ULL;
    sig = (sig ^ (NSUInteger)llround(bvSize.width))  * 1099511628211ULL;
    sig = (sig ^ (NSUInteger)llround(bvSize.height)) * 1099511628211ULL;
    sig = (sig ^ curW) * 1099511628211ULL;
    sig = (sig ^ curH) * 1099511628211ULL;
    sig = (sig ^ (NSUInteger)newText.hash) * 1099511628211ULL;

    NSNumber *lastSig = objc_getAssociatedObject(m.view, kCC26LastPresKey);
    if (lastSig && lastSig.unsignedIntegerValue == sig &&
        pres && pres.superview == buttonView) {
        return;
    }
    objc_setAssociatedObject(m.view, kCC26LastPresKey, @(sig), OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    UILabel *titleLabel = nil;
    BOOL created = (!pres || pres.superview != buttonView);
    if (created) {
        [pres removeFromSuperview];
        pres = [[UIView alloc] initWithFrame:buttonView.bounds];
        pres.userInteractionEnabled = NO;
        pres.backgroundColor = UIColor.clearColor;
        pres.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        pres.clipsToBounds = YES;
        pres.alpha = animate ? 0.0 : 1.0;

        titleLabel = [[UILabel alloc] init];
        titleLabel.tag = 9001;
        titleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
        titleLabel.textColor = UIColor.whiteColor;
        titleLabel.numberOfLines = 2;
        titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        titleLabel.textAlignment = NSTextAlignmentLeft;
        [pres addSubview:titleLabel];

        objc_setAssociatedObject(m.view, kCC26PresKey, pres, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [buttonView addSubview:pres];
    } else {
        titleLabel = (UILabel *)[pres viewWithTag:9001];
    }

    if (created) {
        [UIView performWithoutAnimation:^{ pres.frame = buttonView.bounds; }];
    } else {
        pres.frame = buttonView.bounds;
    }
    pres.hidden = NO;

    titleLabel.text = newText;

    CGFloat W = CGRectGetWidth(pres.bounds);
    CGFloat H = CGRectGetHeight(pres.bounds);
    CGFloat lineHeight = 14.3333;
    CGFloat textW;
    CGFloat textX;
    CGFloat iconCenterY = H * 0.5;
    if (curW > 1 && curH == 1) {
        textX = kCC26Cell - 10.0;
        iconCenterY = H * 0.5;
        textW = MAX(0.0, W - textX - 12.0);
    } else {
        textX = curW > 1 ? 21.0 : 10.0;
        textW = MAX(0.0, W - textX - (curW > 1 ? 24.0 : 10.0));
    }
    CGSize measured = [titleLabel.text boundingRectWithSize:CGSizeMake(textW, lineHeight * 2.0)
                                                    options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                                                 attributes:@{NSFontAttributeName: titleLabel.font}
                                                    context:nil].size;
    CGFloat titleH = measured.height > lineHeight + 1.0 ? lineHeight * 2.0 : lineHeight;

    CGFloat top;
    if (curW > 1 && curH == 1) {
        top = iconCenterY - titleH * 0.5;
        if (top < 4.0) top = 4.0;
        if (top > H - titleH - 4.0) top = H - titleH - 4.0;
    } else {
        top = MAX(kCC26Cell + 7.0, H - 17.3333 - titleH);
    }
    CGRect labelFrame = CGRectMake(textX, top, textW, titleH);
    if (created) {
        [UIView performWithoutAnimation:^{ titleLabel.frame = labelFrame; }];
    } else {
        titleLabel.frame = labelFrame;
    }
    [buttonView bringSubviewToFront:pres];
    [pres bringSubviewToFront:titleLabel];

    if (created && animate) {
        [UIView animateWithDuration:0.22
                              delay:0.08
                            options:UIViewAnimationOptionBeginFromCurrentState |
                                    UIViewAnimationOptionAllowUserInteraction
                         animations:^{ pres.alpha = 1.0; }
                         completion:nil];
    }
}

static void CC26RefreshPresentation(UIViewController *m, UIViewController *ov) {
    if (!m || !m.view) return;
    if (CC26IsLandscape()) return;
    objc_setAssociatedObject(m.view, kCC26LandscapeCleanKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    CC26RunMaybeWithoutAnimation(^{ CC26RefreshPresentationImpl(m, ov); });
}

static void CC26ApplyChrome(UIViewController *m, UIViewController *ov) {
    if (!gEditModeActive) return;
    if (CC26IsLandscape()) return;
    UIView *view = m.view;
    if (!view) return;
    NSString *mid = CC26Mid(m);
    if (!mid.length) return;
    CGRect vis = CC26VisibleFrame(m, ov);
    if (CGRectIsEmpty(vis)) return;

    CC26ApplyRadiusToModule(m);

    CGFloat radius = view.layer.cornerRadius;
    if (radius < 1.0) radius = MIN(CGRectGetWidth(vis), CGRectGetHeight(vis)) * 0.5;

    UIView *border = objc_getAssociatedObject(view, kCC26BorderKey);
    BOOL borderIsNew = (border == nil);
    if (borderIsNew) {
        border = CC26MakeBorder();
        objc_setAssociatedObject(view, kCC26BorderKey, border, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [ov.view addSubview:border];

    border.frame = CGRectInset(vis, -kCC26BorderInset, -kCC26BorderInset);
    CGFloat anchorRadius = radius;
    if (anchorRadius < 1.0) {
        anchorRadius = MIN(CGRectGetWidth(vis), CGRectGetHeight(vis)) * 0.5;
    }
    border.layer.cornerRadius = anchorRadius + kCC26BorderInset;
    border.hidden = NO;
    if (borderIsNew) CC26AnimateChromeEntry(border);

    UIButton *rm = objc_getAssociatedObject(view, kCC26RemoveKey);
    BOOL rmIsNew = (rm == nil);
    if (rmIsNew) {
        rm = CC26MakeRemoveButton(mid);
        [rm addTarget:[CC26EditProxy shared] action:@selector(removeTap:) forControlEvents:UIControlEventTouchUpInside];
        objc_setAssociatedObject(view, kCC26RemoveKey, rm, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [ov.view addSubview:rm];
    }
    CGFloat rmSize = 30.0;
    rm.frame = CGRectMake(vis.origin.x - 8.0, vis.origin.y - 8.0, rmSize, rmSize);
    rm.hidden = NO;
    if (rmIsNew) CC26AnimateChromeEntryDelayed(rm, 0.04);

    BOOL supportsResize = CC26ModuleSupportsResizing(mid);
    objc_setAssociatedObject(CC26ModuleButtonView(view), kCC26IconPinKey,
                             supportsResize ? @YES : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UIButton *rz = objc_getAssociatedObject(view, kCC26ResizeKey);
    if (supportsResize) {
        BOOL rzIsNew = (rz == nil);
        if (rzIsNew) {
            rz = CC26MakeResizeButton(mid);
            objc_setAssociatedObject(view, kCC26ResizeKey, rz, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            UIPanGestureRecognizer *rp = [[UIPanGestureRecognizer alloc] initWithTarget:[CC26EditProxy shared] action:@selector(resizePan:)];
            rp.maximumNumberOfTouches = 1;
            rp.cancelsTouchesInView = YES;
            [rz addGestureRecognizer:rp];
            [ov.view addSubview:rz];
        }
        CGFloat rzSize = 42.0;
        CGFloat rzOverhang = 2.0;
        rz.frame = CGRectMake(CGRectGetMaxX(vis) - rzSize + rzOverhang,
                              CGRectGetMaxY(vis) - rzSize + rzOverhang,
                              rzSize, rzSize);
        rz.hidden = NO;
        if (rzIsNew) CC26AnimateChromeEntryDelayed(rz, 0.04);
    } else if (rz) {
        [rz removeFromSuperview];
        objc_setAssociatedObject(view, kCC26ResizeKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    CC26RefreshPresentation(m, ov);
}

static void CC26StripChrome(UIViewController *m) {
    UIView *view = m.view;
    if (!view) return;
    objc_setAssociatedObject(CC26ModuleButtonView(view), kCC26IconPinKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [objc_getAssociatedObject(view, kCC26BorderKey) removeFromSuperview];
    [objc_getAssociatedObject(view, kCC26RemoveKey) removeFromSuperview];
    [objc_getAssociatedObject(view, kCC26ResizeKey) removeFromSuperview];
    objc_setAssociatedObject(view, kCC26BorderKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(view, kCC26RemoveKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(view, kCC26ResizeKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void CC26InstallGestures(UIViewController *ov) {
    if (!ov.view) return;
    if (objc_getAssociatedObject(ov, kCC26GestKey)) return;
    objc_setAssociatedObject(ov, kCC26GestKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc]
        initWithTarget:[CC26EditProxy shared] action:@selector(bgHold:)];
    hold.minimumPressDuration = 0.55;
    hold.cancelsTouchesInView = NO;
    hold.delegate = [CC26EditProxy shared];
    objc_setAssociatedObject(hold, kCC26OwnGestureKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [ov.view addGestureRecognizer:hold];
}

%hook CCUIModuleCollectionViewController

- (CCUILayoutRect)layoutView:(id)layoutView layoutRectForSubview:(UIView *)subview {
    CCUILayoutRect r = %orig;
    if (!CC26EditAllowed()) return r;
    CC26RefreshGridConstants();

    NSDictionary *containers = nil;
    @try { containers = [(id)self valueForKey:@"moduleContainerViewByIdentifier"]; }
    @catch (__unused NSException *e) {}
    __block NSString *mid = nil;
    [containers enumerateKeysAndObjectsUsingBlock:^(NSString *key, id value, BOOL *stop) {
        UIView *cand = [value isKindOfClass:UIView.class] ? value
                    : ([value respondsToSelector:@selector(view)] ? [value view] : nil);
        if (cand == subview) { mid = key; *stop = YES; }
    }];
    if (!mid.length) return r;

    CC26EnsureStore();

    CC26MigrateMissingOrigins(OverlayIn(UIApplication.sharedApplication.keyWindow.rootViewController));

    if (!CC26GetOrigin(mid) && !gEditOrigins[mid]) {
        CC26SetOrigin(mid, @[@(r.origin.x), @(r.origin.y)]);
    }

    NSArray<NSNumber *> *sz = gEditSizes[mid];
    if (sz.count >= 2) {
        CCUILayoutSize s = { sz[0].unsignedIntegerValue, sz[1].unsignedIntegerValue };
        r.size = s;
    }

    BOOL pendingFresh = gCC26PendingResizeID &&
                        [mid isEqualToString:gCC26PendingResizeID] &&
                        gCC26PendingResizeSize.width &&
                        gCC26PendingResizeSize.height &&
                        (CACurrentMediaTime() - gCC26PendingResizeLastTouch) < 3.0;
    if (pendingFresh) {
        r.size = gCC26PendingResizeSize;
    }

    NSArray<NSNumber *> *o = CC26GetOrigin(mid);
    if (!o) o = gEditOrigins[mid];
    if (o.count >= 2) {
        CCUILayoutPoint p = { o[0].unsignedIntegerValue, o[1].unsignedIntegerValue };
        r.origin = p;
    }
    return r;
}

- (CCUILayoutSize)moduleLayoutSizeForContentModuleContext:(id)context forOrientation:(NSInteger)orientation {
    CCUILayoutSize s = %orig;
    if (!CC26EditAllowed()) return s;
    NSString *mid = nil;
    if ([context respondsToSelector:@selector(moduleIdentifier)]) {
        mid = ((id (*)(id, SEL))objc_msgSend)(context, @selector(moduleIdentifier));
    }
    if (!mid.length) return s;
    CC26EnsureStore();

    NSArray<NSNumber *> *sz = gEditSizes[mid];
    if (sz.count >= 2) {
        CCUILayoutSize ns = { sz[0].unsignedIntegerValue, sz[1].unsignedIntegerValue };
        s = ns;
    }

    BOOL pendingFresh = gCC26PendingResizeID &&
                        [mid isEqualToString:gCC26PendingResizeID] &&
                        gCC26PendingResizeSize.width &&
                        gCC26PendingResizeSize.height &&
                        (CACurrentMediaTime() - gCC26PendingResizeLastTouch) < 3.0;
    if (pendingFresh) {
        s = gCC26PendingResizeSize;
    }
    return s;
}

%end

%hook CALayer

- (void)addAnimation:(CAAnimation *)anim forKey:(NSString *)key {
    if (gEditModeActive && CC26ShouldBlockGlyphAnimation((CALayer *)self, anim)) return;
    %orig;
}

%end

%hook UIViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (!CC26IsControlCenterClass(self)) return;
    if (!CC26EditAllowed()) return;
    if ([NSStringFromClass(self.class) containsString:@"ControlCenterOverlayViewController"]) {
        CC26RefreshGridConstants();
        CC26InstallGestures((UIViewController *)self);
    }
}

- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    if (!gEditModeActive || !CC26IsControlCenterClass(self)) return;
    if ([NSStringFromClass(self.class) containsString:@"ControlCenterOverlayViewController"]) {
        [[CC26EditProxy shared] exitEditOn:(UIViewController *)self];
    }
}
%end

%hook CCUIContentModuleContainerViewController

- (void)viewDidLayoutSubviews {
    %orig;
    if (!CC26EditAllowed()) {
        if (CC26IsLandscape()) CC26TearDownModule((UIViewController *)self);
        return;
    }
    UIViewController *ov = OverlayIn(UIApplication.sharedApplication.keyWindow.rootViewController);
    if (!ov) return;
    UIViewController *module = (UIViewController *)self;

    CC26ApplyRadiusToModule(module);
    CC26RefreshPresentation(module, ov);
}

%end

%hook CCUIButtonModuleView

- (void)layoutSubviews {
    %orig;
    if (gEnabled) {
        // The active/highlighted fill (e.g. Flashlight turning white) can be added or resized
        // after the container's own layout pass already squared its corners, leaving the stock
        // rounder corner showing through at the four corners for a frame or more. Re-square the
        // container right after every layout of the button itself, in and out of edit mode.
        UIView *moduleContainer = CC26Ancestor((UIView *)(id)self, @"CCUIContentModuleContainerView");
        CC26SquareCornersForContainer(moduleContainer);
    }
    BOOL landscape = CC26IsLandscape();
    if (!landscape && !CC26EditAllowed()) return;
    UIResponder *r = (UIResponder *)(id)self;
    UIViewController *module = nil;
    while (r) {
        if ([r isKindOfClass:UIViewController.class] &&
            [NSStringFromClass(((UIViewController *)r).class) containsString:@"ContentModuleContainerViewController"]) {
            module = (UIViewController *)r;
            break;
        }
        r = r.nextResponder;
    }
    if (!module) return;
    if (landscape) { CC26TearDownModule(module); return; }
    UIViewController *ov = OverlayIn(UIApplication.sharedApplication.keyWindow.rootViewController);
    if (!ov) return;

    CC26ApplyRadiusToModule(module);
    CC26RefreshPresentation(module, ov);
}

%end

%hook CCUIModularControlCenterOverlayViewController

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    %orig;
    gCC26RotationQuietUntil = CACurrentMediaTime() + 1.0;
    if (size.width > size.height) {
        UIViewController *ov = (UIViewController *)self;
        if (gEditModeActive) [[CC26EditProxy shared] exitEditOn:ov];
        CC26TearDownAllModules(ov);
    }
    [coordinator animateAlongsideTransition:nil
                                 completion:^(__unused id<UIViewControllerTransitionCoordinatorContext> ctx) {
        CC26ScheduleRotationRefresh();
    }];
}

- (void)setPresentationState:(NSInteger)state {
    %orig;
    if (state == 1) return;
    if (!gEditModeActive) return;
    if (CACurrentMediaTime() - gEditModeEnteredAt < 1.0) return;
    [[CC26EditProxy shared] exitEditOn:(UIViewController *)self];
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (CC26IsLandscape()) {
        CC26TearDownAllModules((UIViewController *)self);
        return;
    }
    if (!CC26EditAllowed()) return;
    UIViewController *ov = (UIViewController *)self;
    if (!ov.view) return;

    CC26RefreshGridConstants();

    for (NSInteger i = 0; i < 8; i++) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                     (int64_t)(i * 0.12 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            UIViewController *o2 = OverlayIn(UIApplication.sharedApplication.keyWindow.rootViewController);
            if (!o2) return;
            if (!CC26EditAllowed()) return;
            for (UIViewController *m in ModuleControllers(o2)) {
                CC26ApplyRadiusToModule(m);
                CC26RefreshPresentation(m, o2);
            }
        });
    }
}

%end

static void CC26PostRotationRefresh(void) {
    UIViewController *ov = OverlayIn(UIApplication.sharedApplication.keyWindow.rootViewController);
    if (!ov) return;
    if (CC26IsLandscape()) {
        if (gEditModeActive) [[CC26EditProxy shared] exitEditOn:ov];
        CC26TearDownAllModules(ov);
        return;
    }
    if (!CC26EditAllowed()) return;
    CC26RefreshGridConstants();
    for (UIViewController *m in ModuleControllers(ov)) {
        if (!m.view) continue;
        objc_setAssociatedObject(m.view, kCC26LastPresKey,   nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(m.view, kCC26LastRadiusKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        CC26ApplyRadiusToModule(m);
        CC26RefreshPresentation(m, ov);
    }
}

static void CC26ScheduleRotationRefresh(void) {
    gCC26RotationQuietUntil = CACurrentMediaTime() + 1.0;
    static const double delays[] = { 0.0, 0.15, 0.45, 0.90 };
    for (size_t i = 0; i < sizeof(delays) / sizeof(delays[0]); i++) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delays[i] * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ CC26PostRotationRefresh(); });
    }
}

static void CC26EditReload(__unused CFNotificationCenterRef c,
                          __unused void *o, __unused CFStringRef n,
                          __unused const void *obj,
                          __unused CFDictionaryRef u) {
    if (!gEditModeEnabled && gEditModeActive) {
        UIViewController *ov = OverlayIn(UIApplication.sharedApplication.keyWindow.rootViewController);
        if (ov) [[CC26EditProxy shared] exitEditOn:ov];
    }
}

%ctor {
    @autoreleasepool {
        CC26InitCachedClasses();
        %init(_ungrouped);
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        NULL, CC26EditReload,
                                        (__bridge CFStringRef)kReloadNotification,
                                        NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);

        [[NSNotificationCenter defaultCenter] addObserverForName:UIDeviceOrientationDidChangeNotification
                                                          object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(__unused NSNotification *note) {
            UIDeviceOrientation o = UIDevice.currentDevice.orientation;
            if (!UIDeviceOrientationIsPortrait(o) && !UIDeviceOrientationIsLandscape(o)) return;
            dispatch_async(dispatch_get_main_queue(), ^{
                if (CC26IsLandscape() && gEditModeActive) {
                    UIViewController *ov = OverlayIn(UIApplication.sharedApplication.keyWindow.rootViewController);
                    if (ov) [[CC26EditProxy shared] exitEditOn:ov];
                }
                CC26ScheduleRotationRefresh();
            });
        }];
    }
}
