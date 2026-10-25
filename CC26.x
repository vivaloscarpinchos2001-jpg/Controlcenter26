#import "CC26.h"

const NSInteger CC26TagConnectivityCluster = 18005;
const NSInteger CC26TagMediaButtonMaterial = 18009;
const NSInteger kPageIndicatorTag = 181030;
const NSInteger kQuickAccessTag = 181000;
const NSInteger kMediaPlayerTag = 181040;
const NSInteger kConnectivityPageTag = 181060;

const void *CC26KeyCompactRadius = &CC26KeyCompactRadius;
const void *CC26KeyMediaMode = &CC26KeyMediaMode;
const void *CC26KeyMiniGlyphBaseSize = &CC26KeyMiniGlyphBaseSize;

static const CFStringRef kPrefsDomain = CFSTR("com.controlcenter26.preferences");
NSString *const kReloadNotification = @"com.controlcenter26/ReloadPrefs";

BOOL gEnabled = YES;
BOOL gQuickAccessButtonsEnabled = YES;
BOOL gPagingEnabled = YES;
BOOL gHapticsEnabled = YES;
BOOL gExperimentalPagingEnabled = YES;
BOOL gPageAnimating = NO;
BOOL gCCAModuleExpanded = NO;
BOOL gCircularModulesEnabled = YES;
BOOL gConnectivityPageEnabled = YES;
BOOL gConnectivityGlassEnabled = YES;
BOOL gBouncyAnimations = YES;
BOOL gIOS26Icons = YES;
BOOL gMenu26 = YES;
BOOL gSwipePagingEnabled = YES;
NSInteger gCurrentPage = 0;

// live grid size: 67 / 12 until the compact patch (tweak.xm, CC26ApplyCompactGrid) updates them
CGFloat gCC26GridCell = 67.0;
CGFloat gCC26GridGap = 12.0;

static NSUInteger const kGridRows = 8;
static CGFloat const kGridCell = 67.0;
static CGFloat const kGridGap = 12.0;
#define kGridStep (kGridCell + kGridGap)
#define kPageSpan (kGridRows * kGridStep)

CGFloat calculatedRadius(CGRect visibleRect, CGFloat radius) {
    CGFloat width  = visibleRect.size.width;
    CGFloat height = visibleRect.size.height;

    if (CGSizeEqualToSize(visibleRect.size, [UIScreen mainScreen].bounds.size) ||
        width <= 60 || height <= 60) {
        return radius;
    }

    if (gCircularModulesEnabled) {
        CGFloat minimum = MIN(width, height);
        CGFloat r       = minimum * 0.5;
        if (minimum >= 76.0) r = MIN(r, 38.0);
        return floor(r);
    }

    if (height >= 300 && height <= 400 && width >= 100 && width <= 200) {
        return radius;
    }
    if ((fabs(width - height) < 1.0 || width >= 250) && height <= 76) {
        return floor(MIN(width, height) / 2.0);
    }
    {
        CGFloat m = MIN(width, height);
        if (m >= 130.0 && m <= 200.0 && fabs(width - height) < 14.0) return floor(m * 0.19);
    }
    return 25;
}

static BOOL PrefBool(NSString *key, BOOL fallback) {
    Boolean valid = false;
    Boolean value = CFPreferencesGetAppBooleanValue((__bridge CFStringRef)key, kPrefsDomain, &valid);
    return valid ? (BOOL)value : fallback;
}

void LoadPrefs(void) {
    CFPreferencesAppSynchronize(kPrefsDomain);
    gEnabled                     = PrefBool(@"Enabled", YES);
    gQuickAccessButtonsEnabled   = PrefBool(@"QuickAccessButtonsEnabled", YES);
    gPagingEnabled               = PrefBool(@"PagingEnabled", YES);
    gHapticsEnabled              = PrefBool(@"HapticsEnabled", YES);
    gExperimentalPagingEnabled   = PrefBool(@"ExperimentalPaging", NO);
    gEditModeEnabled             = PrefBool(@"EditModeEnabled", NO);
    gCircularModulesEnabled      = YES;   // full iOS 26: not configurable
    gConnectivityPageEnabled     = PrefBool(@"ConnectivityPageEnabled", YES);
    gConnectivityGlassEnabled    = PrefBool(@"ConnectivityGlass", YES);
    gSwipePagingEnabled          = PrefBool(@"SwipePaging", YES);
    gBouncyAnimations            = YES;
    gIOS26Icons                  = YES;
    gMenu26                      = YES;
    if (!gEditModeEnabled) gEditModeActive = NO;
}

// Bouncy animations switch: the springs of the tweak keep their timing but lose the overshoot.
CGFloat CC26SpringDamping(CGFloat damping) { return gBouncyAnimations ? damping : 1.0; }
CGFloat CC26SpringVelocity(CGFloat velocity) { return gBouncyAnimations ? velocity : 0.0; }
CGFloat CC26SpringCriticalDamping(CGFloat stiffness, CGFloat bouncyDamping) {
    return gBouncyAnimations ? bouncyDamping : 2.0 * sqrt(stiffness);
}

void Haptic(void) {
    if (!gHapticsEnabled) return;
    UIImpactFeedbackGenerator *g = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [g prepare];
    [g impactOccurred];
}

CGFloat PageSpan(void) {
    CGSize size = UIScreen.mainScreen.bounds.size;
    BOOL landscape = size.width > size.height;
    CGFloat screenH = size.height;

    NSUInteger gridRows = landscape ? 4 : 8;
    CGFloat step = gCC26GridCell + gCC26GridGap;
    CGFloat pageSpan = (CGFloat)gridRows * step;

    CGFloat extra = screenH - pageSpan;
    NSUInteger spacerRows = extra > step * 0.35 ? (NSUInteger)ceil(extra / step) : 0;
    return (CGFloat)(gridRows + spacerRows) * step;
}

NSInteger CC26ConnectivityPageIndex(void) {
    return gConnectivityPageEnabled ? 1 : -1;
}

NSInteger CC26MediaPageIndex(void) {
    return gConnectivityPageEnabled ? 2 : 1;
}

NSUInteger CC26PageCount(void) {
    return 2 + (gConnectivityPageEnabled ? 1 : 0);
}

UIViewController *CC26OverlayForView(UIView *view) {
    UIResponder *responder = view;
    while (responder) {
        if ([responder isKindOfClass:UIViewController.class] &&
            [NSStringFromClass(responder.class) containsString:@"ControlCenterOverlayViewController"]) {
            return (UIViewController *)responder;
        }
        responder = responder.nextResponder;
    }
    return OverlayIn(UIApplication.sharedApplication.keyWindow.rootViewController);
}

UIViewController *OverlayIn(UIViewController *root) {
    if (!root) return nil;
    NSString *name = NSStringFromClass(root.class);
    if ([name containsString:@"ControlCenterOverlayViewController"] ||
        [name isEqualToString:@"CCUIModularControlCenterOverlayViewController"]) return root;
    for (UIViewController *child in root.childViewControllers) {
        UIViewController *found = OverlayIn(child);
        if (found) return found;
    }
    if (root.presentedViewController) return OverlayIn(root.presentedViewController);
    return nil;
}

BOOL IsModuleController(UIViewController *controller) {
    return [NSStringFromClass(controller.class) containsString:@"ContentModuleContainerViewController"];
}

BOOL IsConnectivityController(UIViewController *controller) {
    return [NSStringFromClass(controller.class) isEqualToString:@"CCUIConnectivityModuleViewController"];
}

NSArray<UIViewController *> *ModuleControllers(UIViewController *root) {
    if (!root) return @[];
    NSMutableArray *result = [NSMutableArray array];
    NSMutableArray *queue = [NSMutableArray arrayWithObject:root];
    while (queue.count) {
        UIViewController *candidate = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if (candidate != root && IsModuleController(candidate)) [result addObject:candidate];
        [queue addObjectsFromArray:candidate.childViewControllers];
    }
    return result;
}

UIViewController *ModuleCollection(UIViewController *overlay) {
    NSMutableArray *queue = [NSMutableArray arrayWithObject:overlay];
    while (queue.count) {
        UIViewController *candidate = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if ([NSStringFromClass(candidate.class) containsString:@"ModuleCollectionViewController"]) return candidate;
        [queue addObjectsFromArray:candidate.childViewControllers];
    }
    return nil;
}

UIViewController *ConnectivityChild(UIViewController *controller, NSString *className) {
    NSMutableArray *queue = [NSMutableArray arrayWithArray:controller.childViewControllers];
    while (queue.count) {
        UIViewController *candidate = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if ([NSStringFromClass(candidate.class) isEqualToString:className]) return candidate;
        [queue addObjectsFromArray:candidate.childViewControllers];
    }
    return nil;
}

UIView *CC26ViewIvar(id object, const char *name) {
    if (!object) return nil;
    Ivar ivar = class_getInstanceVariable(object_getClass(object), name);
    if (!ivar) return nil;
    id value = object_getIvar(object, ivar);
    return [value isKindOfClass:UIView.class] ? value : nil;
}

UIView *CC26ModuleAncestor(UIView *view) {
    for (UIView *ancestor = view.superview; ancestor; ancestor = ancestor.superview) {
        if ([NSStringFromClass(ancestor.class) isEqualToString:@"CCUIContentModuleContainerView"]) return ancestor;
    }
    return nil;
}

CGFloat CC26ModuleCornerRadius(CGSize size) {
    CGFloat minimum = MIN(size.width, size.height);
    if (minimum <= 0.0) return 0.0;

    if (gCircularModulesEnabled) {
        CGFloat r = minimum * 0.5;
        if (minimum >= 76.0) r = MIN(r, 38.0);
        return floor(r);
    }

    BOOL oneByOne = fabs(size.width - size.height) <= 3.0 && minimum <= 76.0;
    return oneByOne ? minimum * 0.5 : MIN(32.0, MAX(22.0, minimum * 0.5 - 6.0));
}

// Corner radius of the connectivity page tiles / detail panel.
//  - square cards (Wi-Fi, AirDrop, Cellular, Bluetooth) and the detail panel: 25 in both modes
//  - pills (Airplane, Hotspot, VPN): fully round with "Circular Modules" on, squarer (iOS 18
//    module radius) with it off
CGFloat CC26ConnectivityTileRadius(CGSize size, BOOL pill) {
    CGFloat minimum = MIN(size.width, size.height);
    if (minimum <= 0.0) return 0.0;
    if (!pill) return MIN(25.0, floor(minimum * 0.5));
    if (gCircularModulesEnabled) return floor(minimum * 0.5);
    return MIN(20.0, floor(minimum * 0.5));
}

CGFloat CC26RadiusForModule(UIView *module) {
    if (!module) return 0.0;
    CGFloat width = CGRectGetWidth(module.bounds), height = CGRectGetHeight(module.bounds);
    NSNumber *cached = objc_getAssociatedObject(module, CC26KeyCompactRadius);
    if (width > 0.0 && height > 0.0 && width < 190.0 && height < 190.0) {
        CGFloat radius = CC26ModuleCornerRadius(module.bounds.size);
        objc_setAssociatedObject(module, CC26KeyCompactRadius, @(radius), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return radius;
    }
    return cached ? cached.doubleValue : CC26ModuleCornerRadius(module.bounds.size);
}

UIView *CC26Ancestor(UIView *view, NSString *className) {
    for (; view; view = view.superview) if ([NSStringFromClass(view.class) isEqualToString:className]) return view;
    return nil;
}

NSString *CC26MediaMode(UIView *view) {
    UIView *nowPlaying = CC26Ancestor(view, @"MRUNowPlayingView");
    if (!nowPlaying || !CC26Ancestor(nowPlaying, @"CCUIContentModuleContentContainerView")) return nil;
    @try {
        NSInteger layout = [[nowPlaying valueForKey:@"_layout"] integerValue];
        if (layout == 1 || layout == 2) return nil;
    } @catch (__unused NSException *exception) {}
    if (CGRectGetWidth(nowPlaying.bounds) >= 230.0) return nil;
    NSString *mode = objc_getAssociatedObject(nowPlaying, CC26KeyMediaMode);
    if (mode) return mode;
    return @"compact";
}

NSArray *CC26MediaMaterialFilters(UIView *view) {
    UIView *nowPlaying = CC26Ancestor(view, @"MRUNowPlayingView");
    UIView *transport = CC26ViewIvar(nowPlaying, "_transportControlsView");
    for (UIView *candidate in transport.subviews) {
        if (![candidate isKindOfClass:NSClassFromString(@"MRUTransportButton")] || candidate.alpha < 0.99) continue;
        BOOL hasPackage = NO;
        for (UIView *child in candidate.subviews) if ([NSStringFromClass(child.class) isEqualToString:@"MRUCAPackageView"] && !CGRectIsEmpty(child.bounds)) { hasPackage = YES; break; }
        if (!hasPackage) continue;
        for (CALayer *layer in candidate.layer.sublayers) {
            NSArray *filters = layer.filters;
            if (filters.count == 1 && [filters.description containsString:@"vibrantDark"]) return filters;
        }
    }
    return nil;
}

void CC26ResizeMediaRoutingGlyph(UIView *button) {
    if (!CC26Ancestor(button, @"MRUNowPlayingHeaderView") || !CC26MediaMode(button)) return;
    CGFloat side = MIN(CGRectGetWidth(button.bounds), CGRectGetHeight(button.bounds));
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithArray:button.subviews];
    while (queue.count) {
        UIView *child = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if ([child isKindOfClass:UIImageView.class] && !child.hidden && ((UIImageView *)child).image) {
            UIImageView *glyph = (UIImageView *)child;
            CGSize imageSize = glyph.image.size;
            CGFloat scale = side * (26.0 / 54.0) / MAX(imageSize.width, imageSize.height);
            CGRect target = CGRectMake((side - imageSize.width * scale) * 0.5, (side - imageSize.height * scale) * 0.5, imageSize.width * scale, imageSize.height * scale);
            glyph.contentMode = UIViewContentModeScaleAspectFit;
            child.frame = [button convertRect:target toView:child.superview];
        }
        [queue addObjectsFromArray:child.subviews];
    }
}

void CC26ConfigureMedia(UIView *view) {
    NSString *mode = CC26MediaMode(view);
    UIView *artwork = CC26ViewIvar(view, "_artworkView"), *header = CC26ViewIvar(view, "_headerView");
    UIView *time = CC26ViewIvar(view, "_timeControlsView"), *transport = CC26ViewIvar(view, "_transportControlsView"), *volume = CC26ViewIvar(view, "_volumeControlsView");
    UIView *wrapper = CC26Ancestor(view, @"MRUControlCenterView");
    if (!mode) {
        if (!objc_getAssociatedObject(view, CC26KeyMediaMode)) return;
        objc_setAssociatedObject(view, CC26KeyMediaMode, nil, OBJC_ASSOCIATION_COPY_NONATOMIC);
        for (UIView *item in @[CC26ViewIvar(wrapper, "_routingButton") ?: (id)NSNull.null, CC26ViewIvar(wrapper, "_moreButton") ?: (id)NSNull.null, time ?: (id)NSNull.null, volume ?: (id)NSNull.null]) {
            if ((id)item != NSNull.null) { item.hidden = NO; item.alpha = 1.0; }
        }
        if (artwork) { artwork.backgroundColor = UIColor.clearColor; artwork.layer.cornerRadius = 0.0; artwork.layer.masksToBounds = NO; }
        return;
    }
    objc_setAssociatedObject(view, CC26KeyMediaMode, mode, OBJC_ASSOCIATION_COPY_NONATOMIC);
    if (!header || !transport) return;
    CGFloat width = CGRectGetWidth(view.bounds);
    CGRect artworkFrame = CGRectMake(14, 14, 50, 50);
    UIView *module = CC26ModuleAncestor(view);
    CGFloat artworkInset = MIN(CGRectGetMinX(artworkFrame), CGRectGetMinY(artworkFrame));
    CGFloat artworkRadius = MAX(0.0, CC26RadiusForModule(module) - artworkInset) * 0.75;
    [UIView performWithoutAnimation:^{
        view.clipsToBounds = YES;
        header.frame = view.bounds;
        for (UIView *item in @[CC26ViewIvar(wrapper, "_routingButton") ?: (id)NSNull.null, CC26ViewIvar(wrapper, "_moreButton") ?: (id)NSNull.null]) if ((id)item != NSNull.null) item.hidden = YES;
        if (artwork) { artwork.frame = artworkFrame; artwork.hidden = NO; artwork.alpha = 1.0; artwork.backgroundColor = UIColor.clearColor; artwork.layer.cornerRadius = artworkRadius; artwork.layer.cornerCurve = kCACornerCurveContinuous; artwork.layer.masksToBounds = YES; }
        transport.frame = CGRectMake(floor((width - 110.0) * 0.5), 102, 110, 44); transport.hidden = NO; transport.alpha = 1.0;
        if (time) { time.hidden = YES; time.alpha = 0; }
        if (volume) { volume.hidden = YES; volume.alpha = 0; }
    }];
}

UIViewController *CC26ConnectivityChild(UIViewController *controller, NSString *className) {
    NSMutableArray<UIViewController *> *queue = [NSMutableArray arrayWithArray:controller.childViewControllers];
    while (queue.count) {
        UIViewController *candidate = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if ([NSStringFromClass(candidate.class) isEqualToString:className]) return candidate;
        [queue addObjectsFromArray:candidate.childViewControllers];
    }
    return nil;
}

UIView *CC26ModuleMaterial(void) {
    Class materialClass = NSClassFromString(@"MTMaterialView");
    SEL factory = NSSelectorFromString(@"materialViewWithRecipe:");
    if ([materialClass respondsToSelector:factory]) return ((id (*)(id, SEL, long long))objc_msgSend)(materialClass, factory, 4);
    return [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialDark]];
}

NSArray *CC26ConnectivityVibrantFilters(UIView *root) {
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:root];
    while (queue.count) {
        UIView *view = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if ([NSStringFromClass(view.class) isEqualToString:@"CCUIRoundButton"]) {
            NSArray *filters = view.subviews.firstObject.layer.filters;
            if (filters.count) return filters;
        }
        [queue addObjectsFromArray:view.subviews];
    }
    return nil;
}

void CC26ScaleMiniGlyphs(UIView *root, CGFloat scale) {
    if (!root) return;
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithArray:root.subviews];
    NSMutableArray<UIView *> *packages = [NSMutableArray array];
    NSMutableArray<UIView *> *images = [NSMutableArray array];
    while (queue.count) {
        UIView *view = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if ([NSStringFromClass(view.class) isEqualToString:@"CCUICAPackageView"]) [packages addObject:view];
        else if ([view isKindOfClass:UIImageView.class] && ((UIImageView *)view).image && !CC26Ancestor(view, @"CCUICAPackageView")) [images addObject:view];
        [queue addObjectsFromArray:view.subviews];
    }
    for (UIView *view in packages) view.transform = CGAffineTransformMakeScale(scale, scale);
    for (UIView *view in images) {
        NSValue *stored = objc_getAssociatedObject(view, CC26KeyMiniGlyphBaseSize);
        CGSize base = stored ? stored.CGSizeValue : view.frame.size;
        if (!stored) objc_setAssociatedObject(view, CC26KeyMiniGlyphBaseSize, [NSValue valueWithCGSize:base], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        CGPoint center = view.center;
        view.transform = CGAffineTransformIdentity;
        view.bounds = CGRectMake(0.0, 0.0, base.width * scale, base.height * scale);
        view.center = center;
    }
}

UIImage *CC26BundledSymbol(NSString *name, UIColor *color, BOOL hierarchical) {
    static NSBundle *bundle, *privateBundle;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *path = @"/var/jb/Library/Application Support/CC18/CC18.bundle";
        if (![NSFileManager.defaultManager fileExistsAtPath:path]) path = @"/Library/Application Support/CC18/CC18.bundle";
        bundle = [NSBundle bundleWithPath:path];
        // the private symbols (the Apple Music note, ...) ship with this tweak; the CC18 copy is the fallback
        NSArray<NSString *> *privatePaths = @[
            @"/var/jb/Library/Application Support/ControlCenter26/PrivateSymbols.bundle",
            @"/Library/Application Support/ControlCenter26/PrivateSymbols.bundle",
            [path stringByAppendingPathComponent:@"PrivateSymbols.bundle"],
        ];
        for (NSString *candidate in privatePaths) {
            if ([NSFileManager.defaultManager fileExistsAtPath:candidate]) {
                privateBundle = [NSBundle bundleWithPath:candidate];
                break;
            }
        }
    });
    BOOL privateSymbol = [name isEqualToString:@"calculator.fill"] || [name isEqualToString:@"music"] || [name isEqualToString:@"network.connected.to.line.below.fill"];
    UIImage *image = [UIImage imageNamed:name inBundle:privateSymbol ? privateBundle : bundle compatibleWithTraitCollection:nil];
    if (!image) image = [UIImage systemImageNamed:name];
    if (hierarchical) image = [image imageByApplyingSymbolConfiguration:[UIImageSymbolConfiguration configurationWithHierarchicalColor:color]];
    if (!hierarchical) image = [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    return image;
}


// ---------------------------------------------------------------------------
// iOS 26 glyphs drawn straight from the SF Symbols SVG exports (Semibold weight, interpolated
// between the Regular and Black masters). They live in the dylib, so they do not depend on
// CC18.bundle. Op codes: 0 = move, 1 = line, 2 = cubic curve, 3 = close.
// ---------------------------------------------------------------------------
static const CGFloat kCC26SVG_wifi[] = {0.f, 10.205f, -42.324f, 2.f, 12.705f, -39.795f, 16.494f, -40.244f, 19.600f, -42.998f, 2.f, 28.574f, -50.977f, 39.717f, -55.098f, 52.109f, -55.098f, 2.f, 64.473f, -55.098f, 75.674f, -50.918f, 84.619f, -42.998f, 2.f, 87.695f, -40.244f, 91.484f, -39.854f, 94.014f, -42.354f, 2.f, 96.562f, -44.951f, 96.855f, -48.779f, 94.277f, -51.455f, 2.f, 84.414f, -61.514f, 68.457f, -68.232f, 52.109f, -68.232f, 2.f, 35.762f, -68.232f, 19.775f, -61.484f, 9.941f, -51.426f, 2.f, 7.334f, -48.779f, 7.627f, -44.951f, 10.205f, -42.324f, 3.f, 0.f, 26.113f, -26.602f, 2.f, 29.219f, -23.643f, 32.822f, -24.629f, 35.508f, -26.758f, 2.f, 40.117f, -30.273f, 46.094f, -32.529f, 52.109f, -32.500f, 2.f, 58.125f, -32.529f, 64.102f, -30.244f, 68.711f, -26.729f, 2.f, 71.367f, -24.629f, 75.059f, -23.701f, 78.135f, -26.660f, 2.f, 80.830f, -29.287f, 81.240f, -33.496f, 78.242f, -36.074f, 2.f, 71.777f, -41.602f, 62.305f, -45.273f, 52.109f, -45.273f, 2.f, 41.885f, -45.273f, 32.412f, -41.602f, 25.977f, -36.074f, 2.f, 23.213f, -33.701f, 23.037f, -29.609f, 26.113f, -26.602f, 3.f, 0.f, 47.764f, -4.912f, 2.f, 50.645f, -2.217f, 53.564f, -2.217f, 56.436f, -4.912f, 1.f, 62.422f, -10.674f, 2.f, 65.186f, -13.359f, 65.791f, -16.650f, 62.754f, -19.102f, 2.f, 59.873f, -21.416f, 56.094f, -22.852f, 52.129f, -22.852f, 2.f, 48.145f, -22.852f, 44.395f, -21.436f, 41.504f, -19.072f, 2.f, 38.447f, -16.650f, 39.062f, -13.311f, 41.846f, -10.654f, 3.f};
static const CGFloat kCC26SVG_cellularbars[] = {0.f, 106.934f, 0.000f, 2.f, 112.676f, 0.000f, 117.354f, -4.648f, 117.354f, -10.449f, 1.f, 117.354f, -60.059f, 2.f, 117.354f, -65.859f, 112.676f, -70.508f, 106.934f, -70.508f, 2.f, 101.162f, -70.508f, 96.514f, -65.859f, 96.514f, -60.059f, 1.f, 96.514f, -10.449f, 2.f, 96.514f, -4.648f, 101.162f, 0.000f, 106.934f, 0.000f, 3.f, 0.f, 78.027f, 0.000f, 2.f, 83.770f, 0.000f, 88.447f, -4.648f, 88.447f, -10.449f, 1.f, 88.447f, -44.180f, 2.f, 88.447f, -49.951f, 83.770f, -54.629f, 78.027f, -54.629f, 2.f, 72.256f, -54.629f, 67.578f, -49.951f, 67.578f, -44.180f, 1.f, 67.578f, -10.449f, 2.f, 67.578f, -4.619f, 72.256f, 0.000f, 78.027f, 0.000f, 3.f, 0.f, 49.121f, 0.000f, 2.f, 54.863f, 0.000f, 59.541f, -4.648f, 59.541f, -10.449f, 1.f, 59.541f, -29.678f, 2.f, 59.541f, -35.449f, 54.863f, -40.127f, 49.121f, -40.127f, 2.f, 43.350f, -40.127f, 38.672f, -35.449f, 38.672f, -29.678f, 1.f, 38.672f, -10.449f, 2.f, 38.672f, -4.678f, 43.350f, 0.000f, 49.121f, 0.000f, 3.f, 0.f, 20.215f, 0.000f, 2.f, 25.957f, 0.000f, 30.605f, -4.648f, 30.605f, -10.449f, 1.f, 30.605f, -17.744f, 2.f, 30.605f, -23.486f, 25.957f, -28.135f, 20.215f, -28.135f, 2.f, 14.443f, -28.135f, 9.766f, -23.486f, 9.766f, -17.744f, 1.f, 9.766f, -10.449f, 2.f, 9.766f, -4.648f, 14.443f, 0.000f, 20.215f, 0.000f, 3.f};
static const CGFloat kCC26SVG_personalhotspot[] = {0.f, 57.412f, -2.061f, 1.f, 82.744f, -2.061f, 2.f, 96.631f, -2.061f, 106.485f, -11.875f, 106.485f, -25.850f, 2.f, 106.485f, -39.062f, 97.686f, -48.584f, 84.971f, -49.521f, 1.f, 84.629f, -49.521f, 2.f, 85.117f, -46.670f, 85.137f, -43.076f, 84.766f, -40.254f, 1.f, 84.941f, -40.254f, 2.f, 92.119f, -39.199f, 96.963f, -33.574f, 96.963f, -25.850f, 2.f, 96.963f, -17.139f, 90.908f, -11.123f, 82.305f, -11.123f, 1.f, 57.852f, -11.123f, 2.f, 49.248f, -11.123f, 43.193f, -17.139f, 43.193f, -25.850f, 2.f, 43.193f, -34.541f, 49.268f, -40.605f, 57.852f, -40.605f, 1.f, 63.721f, -40.605f, 2.f, 64.980f, -42.949f, 65.146f, -46.875f, 63.223f, -49.668f, 1.f, 57.412f, -49.668f, 2.f, 43.525f, -49.668f, 33.672f, -39.854f, 33.672f, -25.850f, 2.f, 33.672f, -11.875f, 43.525f, -2.061f, 57.412f, -2.061f, 3.f, 0.f, 55.908f, -20.449f, 2.f, 69.824f, -20.449f, 79.678f, -30.264f, 79.678f, -44.268f, 2.f, 79.678f, -58.242f, 69.824f, -68.057f, 55.908f, -68.057f, 1.f, 30.605f, -68.057f, 2.f, 16.689f, -68.057f, 6.836f, -58.242f, 6.836f, -44.268f, 2.f, 6.836f, -31.025f, 15.664f, -21.533f, 28.379f, -20.625f, 1.f, 28.691f, -20.625f, 2.f, 28.184f, -23.652f, 28.203f, -27.373f, 28.525f, -29.863f, 1.f, 28.350f, -29.863f, 2.f, 21.182f, -30.918f, 16.387f, -36.494f, 16.387f, -44.268f, 2.f, 16.387f, -52.930f, 22.432f, -58.994f, 31.045f, -58.994f, 1.f, 55.469f, -58.994f, 2.f, 64.082f, -58.994f, 70.127f, -52.930f, 70.127f, -44.268f, 2.f, 70.127f, -35.527f, 64.102f, -29.512f, 55.469f, -29.512f, 1.f, 49.639f, -29.512f, 2.f, 48.115f, -26.895f, 48.359f, -22.979f, 50.068f, -20.449f, 3.f};
static const CGFloat kCC26SVG_network[] = {0.f, 14.541f, -52.080f, 2.f, 23.545f, -41.397f, 36.904f, -35.186f, 50.967f, -35.215f, 2.f, 62.451f, -35.215f, 73.506f, -39.326f, 82.178f, -46.865f, 1.f, 79.189f, -52.744f, 2.f, 71.475f, -45.479f, 61.533f, -41.504f, 50.967f, -41.504f, 2.f, 37.617f, -41.504f, 25.332f, -47.764f, 17.490f, -58.643f, 3.f, 0.f, 10.078f, -30.234f, 2.f, 30.117f, -12.783f, 59.102f, -9.590f, 82.324f, -22.148f, 1.f, 82.041f, -29.336f, 2.f, 59.883f, -15.527f, 30.850f, -18.770f, 11.816f, -37.178f, 3.f, 0.f, 29.463f, -3.828f, 1.f, 36.943f, -2.236f, 2.f, 33.730f, -9.414f, 32.061f, -17.139f, 32.031f, -25.039f, 2.f, 31.885f, -43.135f, 40.176f, -60.059f, 54.590f, -71.172f, 1.f, 48.037f, -73.926f, 2.f, 33.750f, -61.670f, 25.596f, -43.799f, 25.742f, -25.039f, 2.f, 25.771f, -17.842f, 27.002f, -10.732f, 29.463f, -3.828f, 3.f, 0.f, 55.186f, -0.039f, 1.f, 61.025f, -2.705f, 2.f, 53.613f, -12.715f, 49.600f, -24.727f, 49.600f, -37.197f, 2.f, 49.600f, -48.867f, 53.047f, -60.098f, 59.609f, -69.590f, 1.f, 53.457f, -71.719f, 2.f, 46.826f, -61.426f, 43.291f, -49.443f, 43.291f, -37.197f, 2.f, 43.291f, -23.809f, 47.393f, -10.928f, 55.186f, -0.039f, 3.f, 0.f, 77.090f, -13.975f, 1.f, 81.406f, -18.740f, 2.f, 68.340f, -25.996f, 60.322f, -39.551f, 60.293f, -54.443f, 2.f, 60.293f, -59.648f, 61.260f, -64.863f, 63.232f, -69.834f, 1.f, 57.197f, -71.514f, 2.f, 55.059f, -66.104f, 54.004f, -60.361f, 54.004f, -54.443f, 2.f, 54.033f, -37.822f, 62.754f, -22.490f, 77.090f, -13.975f, 3.f, 0.f, 31.270f, -35.654f, 2.f, 35.039f, -35.654f, 38.145f, -38.730f, 38.145f, -42.529f, 2.f, 38.145f, -46.299f, 35.039f, -49.404f, 31.270f, -49.404f, 2.f, 27.471f, -49.404f, 24.375f, -46.299f, 24.375f, -42.529f, 2.f, 24.375f, -38.730f, 27.471f, -35.654f, 31.270f, -35.654f, 3.f, 0.f, 60.771f, -32.578f, 2.f, 64.580f, -32.578f, 67.676f, -35.654f, 67.676f, -39.512f, 2.f, 67.676f, -43.320f, 64.580f, -46.416f, 60.771f, -46.416f, 2.f, 56.914f, -46.416f, 53.838f, -43.320f, 53.838f, -39.512f, 2.f, 53.838f, -35.654f, 56.914f, -32.578f, 60.771f, -32.578f, 3.f, 0.f, 49.170f, -11.211f, 2.f, 52.978f, -11.211f, 56.055f, -14.307f, 56.055f, -18.145f, 2.f, 56.055f, -21.973f, 52.959f, -25.068f, 49.170f, -25.068f, 2.f, 45.293f, -25.068f, 42.168f, -21.973f, 42.168f, -18.145f, 2.f, 42.168f, -14.307f, 45.293f, -11.211f, 49.170f, -11.211f, 3.f, 0.f, 47.275f, 5.186f, 2.f, 69.619f, 5.186f, 87.744f, -12.910f, 87.744f, -35.254f, 2.f, 87.744f, -57.598f, 69.619f, -75.693f, 47.275f, -75.693f, 2.f, 24.961f, -75.693f, 6.836f, -57.598f, 6.836f, -35.254f, 2.f, 6.836f, -12.910f, 24.961f, 5.186f, 47.275f, 5.186f, 3.f, 0.f, 47.275f, -2.627f, 2.f, 29.277f, -2.627f, 14.678f, -17.256f, 14.678f, -35.254f, 2.f, 14.678f, -53.252f, 29.277f, -67.881f, 47.275f, -67.881f, 2.f, 65.273f, -67.881f, 79.902f, -53.252f, 79.902f, -35.254f, 2.f, 79.902f, -17.256f, 65.273f, -2.627f, 47.275f, -2.627f, 3.f};

static UIImage *CC26DrawSVGSymbol(const CGFloat *ops, size_t count, CGFloat pointSize) {
    CGMutablePathRef path = CGPathCreateMutable();
    for (size_t i = 0; i < count;) {
        int op = (int)ops[i++];
        if (op == 0) { CGPathMoveToPoint(path, NULL, ops[i], ops[i + 1]); i += 2; }
        else if (op == 1) { CGPathAddLineToPoint(path, NULL, ops[i], ops[i + 1]); i += 2; }
        else if (op == 2) { CGPathAddCurveToPoint(path, NULL, ops[i], ops[i + 1], ops[i + 2], ops[i + 3], ops[i + 4], ops[i + 5]); i += 6; }
        else CGPathCloseSubpath(path);
    }
    // the SVG masters are typeset at 100pt
    CGFloat scale = pointSize / 100.0;
    CGRect box = CGPathGetPathBoundingBox(path);
    CGAffineTransform transform = CGAffineTransformMakeScale(scale, scale);
    transform = CGAffineTransformTranslate(transform, -CGRectGetMinX(box), -CGRectGetMinY(box));
    CGPathRef scaled = CGPathCreateCopyByTransformingPath(path, &transform);
    CGSize size = CGSizeMake(ceil(CGRectGetWidth(box) * scale), ceil(CGRectGetHeight(box) * scale));
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size format:format];
    UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        CGContextRef cg = context.CGContext;
        CGFloat dx = (size.width - CGRectGetWidth(box) * scale) * 0.5;
        CGFloat dy = (size.height - CGRectGetHeight(box) * scale) * 0.5;
        CGContextTranslateCTM(cg, dx, dy);
        CGContextSetFillColorWithColor(cg, UIColor.whiteColor.CGColor);
        CGContextAddPath(cg, scaled);
        CGContextFillPath(cg); // non-zero winding, same as SF Symbols
    }];
    CGPathRelease(scaled);
    CGPathRelease(path);
    return [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

// Returns the iOS 26 glyph for `name` at `pointSize`, or nil when the name has no SVG.
UIImage *CC26SVGSymbol(NSString *name, CGFloat pointSize) {
    const CGFloat *ops = NULL;
    size_t count = 0;
    if ([name isEqualToString:@"wifi"]) { ops = kCC26SVG_wifi; count = sizeof(kCC26SVG_wifi) / sizeof(CGFloat); }
    else if ([name isEqualToString:@"cellularbars"]) { ops = kCC26SVG_cellularbars; count = sizeof(kCC26SVG_cellularbars) / sizeof(CGFloat); }
    else if ([name isEqualToString:@"personalhotspot"]) { ops = kCC26SVG_personalhotspot; count = sizeof(kCC26SVG_personalhotspot) / sizeof(CGFloat); }
    else if ([name isEqualToString:@"network"] || [name isEqualToString:@"network.connected.to.line.below.fill"]) { ops = kCC26SVG_network; count = sizeof(kCC26SVG_network) / sizeof(CGFloat); }
    if (!ops) return nil;
    static NSMutableDictionary<NSString *, UIImage *> *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [NSMutableDictionary dictionary]; });
    NSString *key = [NSString stringWithFormat:@"%@@%.2f", name, pointSize];
    UIImage *image;
    @synchronized (cache) { image = cache[key]; }
    if (!image) {
        image = CC26DrawSVGSymbol(ops, count, pointSize);
        @synchronized (cache) { cache[key] = image; }
    }
    return image;
}

static const NSInteger kCC26EmbeddedPageTag = 181777;
static const NSInteger kCC26GlyphTag = 181778;

// Replaces the stock (iOS 16) glyph of a connectivity button with the symbol from CC18.bundle,
// falling back to the system symbol. The stock glyph is only hidden, never removed, so the
// original layout/state code keeps working.
static void CC26RestoreStockGlyph(UIView *buttonView) {
    UIImageView *glyph = (UIImageView *)[buttonView viewWithTag:kCC26GlyphTag];
    glyph.hidden = YES;
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithArray:buttonView.subviews];
    while (queue.count) {
        UIView *v = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if (v == glyph) continue;
        if ([NSStringFromClass(v.class) isEqualToString:@"CCUICAPackageView"] ||
            ([v isKindOfClass:UIImageView.class] && ((UIImageView *)v).image)) { v.hidden = NO; continue; }
        [queue addObjectsFromArray:v.subviews];
    }
}

// Visual box (in the package view's own coordinates) of the stock glyph, measured once from a
// rendering of its layers. The iOS 26 glyph is then centred on it and given the same size.
static const void *kCC26GlyphBoxKey = &kCC26GlyphBoxKey;

static CGRect CC26MeasureStockGlyph(UIView *package) {
    NSValue *cached = objc_getAssociatedObject(package, kCC26GlyphBoxKey);
    if (cached) return cached.CGRectValue;
    CGSize size = package.bounds.size;
    if (size.width < 4.0 || size.height < 4.0 || size.width > 400.0 || size.height > 400.0) return CGRectNull;
    BOOL wasHidden = package.hidden;
    package.hidden = NO;
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
    format.opaque = NO;
    format.scale = 2.0;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size format:format];
    UIImage *raw = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [package.layer renderInContext:context.CGContext];
    }];
    package.hidden = wasHidden;
    CGImageRef cg = raw.CGImage;
    if (!cg) return CGRectNull;
    size_t w = CGImageGetWidth(cg), h = CGImageGetHeight(cg);
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    NSMutableData *pixels = [NSMutableData dataWithLength:w * h * 4];
    CGContextRef ctx = CGBitmapContextCreate(pixels.mutableBytes, w, h, 8, w * 4, space, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    if (!ctx) return CGRectNull;
    CGContextDrawImage(ctx, CGRectMake(0, 0, w, h), cg);
    CGContextRelease(ctx);
    const uint8_t *p = pixels.bytes;
    size_t minX = w, minY = h, maxX = 0, maxY = 0;
    BOOL any = NO;
    for (size_t y = 0; y < h; y++) {
        for (size_t x = 0; x < w; x++) {
            if (p[(y * w + x) * 4 + 3] > 40) {
                any = YES;
                if (x < minX) minX = x;
                if (x > maxX) maxX = x;
                if (y < minY) minY = y;
                if (y > maxY) maxY = y;
            }
        }
    }
    if (!any) return CGRectNull;
    CGFloat scale = 2.0;
    CGRect box = CGRectMake(minX / scale, minY / scale, (maxX - minX + 1) / scale, (maxY - minY + 1) / scale);
    // a box that is the whole view means we measured a background, not a glyph
    if (box.size.width > size.width * 0.95 && box.size.height > size.height * 0.95) return CGRectNull;
    objc_setAssociatedObject(package, kCC26GlyphBoxKey, [NSValue valueWithCGRect:box], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return box;
}

static UIView *CC26FirstGlyphPackage(UIView *root, UIView *skip) {
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithArray:root.subviews];
    while (queue.count) {
        UIView *v = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if (v == skip) continue;
        if ([NSStringFromClass(v.class) isEqualToString:@"CCUICAPackageView"]) return v;
        [queue addObjectsFromArray:v.subviews];
    }
    return nil;
}

static void CC26ReplaceStockGlyph(UIView *buttonView, NSArray<NSString *> *names, CGFloat pointSize) {
    if (!buttonView) return;
    // "iOS 26 Icons" off: the natural iOS 16 glyph of the button
    // (the iOS 26 cellular-bars art is used in both modes; everything else is natural iOS 16 when off)
    if (!gIOS26Icons && ![names containsObject:@"cellularbars"]) { CC26RestoreStockGlyph(buttonView); return; }
    UIImageView *glyph = (UIImageView *)[buttonView viewWithTag:kCC26GlyphTag];

    // size and position of the stock glyph (centre of the button when it cannot be measured)
    UIView *package = CC26FirstGlyphPackage(buttonView, glyph);
    CGRect stockBox = package ? CC26MeasureStockGlyph(package) : CGRectNull;
    CGRect boxInButton = CGRectNull;
    if (!CGRectIsNull(stockBox)) boxInButton = [buttonView convertRect:stockBox fromView:package];

    UIImage *image = nil;
    for (NSString *name in names) {
        image = CC26SVGSymbol(name, pointSize) ?: CC26BundledSymbol(name, UIColor.whiteColor, NO);
        if (!image) continue;
        if (!CGRectIsNull(boxInButton) && CC26SVGSymbol(name, pointSize)) {
            // same visual size as the stock glyph
            CGFloat have = MAX(image.size.width, image.size.height);
            CGFloat want = MAX(boxInButton.size.width, boxInButton.size.height);
            if (have > 1.0 && want > 1.0) {
                UIImage *matched = CC26SVGSymbol(name, pointSize * want / have);
                if (matched) image = matched;
            }
        }
        break;
    }
    if (!image) { glyph.hidden = YES; return; }
    if (!image.symbolConfiguration) {
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:pointSize weight:UIImageSymbolWeightSemibold];
        image = [image imageByApplyingSymbolConfiguration:cfg] ?: image;
    }
    image = [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    if (!glyph) {
        glyph = [[UIImageView alloc] init];
        glyph.tag = kCC26GlyphTag;
        glyph.contentMode = UIViewContentModeCenter;
        glyph.userInteractionEnabled = NO;
        [buttonView addSubview:glyph];
    }
    glyph.hidden = NO;
    glyph.image = image;
    glyph.tintColor = UIColor.whiteColor;
    CGRect frame = buttonView.bounds;
    if (!CGRectIsNull(boxInButton)) {
        frame = CGRectOffset(frame, CGRectGetMidX(boxInButton) - CGRectGetMidX(buttonView.bounds),
                                    CGRectGetMidY(boxInButton) - CGRectGetMidY(buttonView.bounds));
    }
    glyph.frame = frame;
    [buttonView bringSubviewToFront:glyph];
    // hide the stock glyph only: anything as big as the button is its circle / background
    CGFloat limit = MIN(CGRectGetWidth(buttonView.bounds), CGRectGetHeight(buttonView.bounds)) * 0.9;
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithArray:buttonView.subviews];
    while (queue.count) {
        UIView *v = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if (v == glyph) continue;
        BOOL isGlyph = [NSStringFromClass(v.class) isEqualToString:@"CCUICAPackageView"] ||
                       ([v isKindOfClass:UIImageView.class] && ((UIImageView *)v).image);
        if (isGlyph) {
            if (MAX(CGRectGetWidth(v.bounds), CGRectGetHeight(v.bounds)) <= limit || [NSStringFromClass(v.class) isEqualToString:@"CCUICAPackageView"]) v.hidden = YES;
            continue;
        }
        [queue addObjectsFromArray:v.subviews];
    }
}

// Only the glyphs we have real iOS 26 artwork for are replaced (Wi-Fi, cellular, hotspot).
// Airplane, AirDrop and Bluetooth return nil on purpose: the stock glyph stays untouched
// instead of being swapped for a look-alike system symbol.
static NSArray<NSString *> *CC26StockGlyphNames(NSString *className) {
    if ([className containsString:@"Wifi"]) return @[@"wifi"];
    if ([className containsString:@"Cellular"]) return @[@"cellularbars"];
    if ([className containsString:@"Hotspot"]) return @[@"personalhotspot"];
    return nil;
}

static NSMutableArray<UIView *> *sCC26HiddenBox = nil;
static NSMutableArray<NSDictionary *> *sCC26SavedLayers = nil;
static __weak UIViewController *sCC26ExpandedController = nil;
static __weak UIView *sCC26ExpandedContainer = nil;

// remove the stock rounded box drawn by the layer itself (fill, filters, rim, shadow)
static void CC26ClearLayerChrome(UIView *v) {
    if (!v) return;
    for (NSDictionary *d in sCC26SavedLayers) if (d[@"v"] == v) return;
    CALayer *l = v.layer;
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    d[@"v"] = v;
    if (l.backgroundColor) d[@"bg"] = (__bridge id)l.backgroundColor;
    if (l.filters) d[@"f"] = l.filters;
    if (l.backgroundFilters) d[@"bf"] = l.backgroundFilters;
    d[@"bw"] = @(l.borderWidth);
    d[@"so"] = @(l.shadowOpacity);
    if (!sCC26SavedLayers) sCC26SavedLayers = [NSMutableArray array];
    [sCC26SavedLayers addObject:d];
    l.backgroundColor = nil;
    l.filters = nil;
    l.backgroundFilters = nil;
    l.borderWidth = 0.0;
    l.shadowOpacity = 0.0;
}


static NSMutableArray<CALayer *> *sCC26HiddenLayers = nil;
static NSTimer *sCC26HuntTimer = nil;
static BOOL sCC26DisabledTouches = NO;

static BOOL CC26LayerHasLiquidGlass(CALayer *l) {
    for (id f in l.filters) {
        NSString *t = nil;
        @try { t = [f valueForKey:@"type"]; } @catch (__unused NSException *e) {}
        if ([t isKindOfClass:NSString.class] && [t.lowercaseString containsString:@"liquidglass"]) return YES;
    }
    if ([NSStringFromClass(l.class) isEqualToString:@"CABackdropLayer"]) {
        NSString *g = nil;
        @try { g = [l valueForKey:@"groupName"]; } @catch (__unused NSException *e) {}
        if ([g isKindOfClass:NSString.class] && [g.lowercaseString containsString:@"liquidglass"]) return YES;
    }
    return NO;
}

// the stock (blur) material that draws the expanded module's rounded square
static BOOL CC26IsStockMaterial(UIView *v) {
    if ([v isKindOfClass:UIVisualEffectView.class]) return YES;
    const char *name = object_getClassName(v);
    return strstr(name, "MTMaterialView") != NULL || strstr(name, "ModuleBackground") != NULL ||
           strstr(name, "BackdropView") != NULL;
}

static BOOL CC26BigBox(CGSize s) {
    return s.width >= 200.0 && s.height >= 200.0 && s.width < CGRectGetWidth(UIScreen.mainScreen.bounds) * 0.95;
}

static void CC26HuntSubLayers(CALayer *layer, int depth) {
    if (depth > 4) return;
    for (CALayer *sub in layer.sublayers) {
        // our own page (and the detail panel inside it) keeps its glass
        id owner = sub.delegate;
        if ([owner isKindOfClass:UIView.class] && ((UIView *)owner).tag == kCC26EmbeddedPageTag) continue;
        if (!sub.hidden && CC26BigBox(sub.bounds.size) && CC26LayerHasLiquidGlass(sub)) {
            if (!sCC26HiddenLayers) sCC26HiddenLayers = [NSMutableArray array];
            [sCC26HiddenLayers addObject:sub];
            sub.hidden = YES;
            continue;
        }
        CC26HuntSubLayers(sub, depth + 1);
    }
}

// The big rounded box behind the expanded module is a liquid-glass layer (from LiquidAss).
// Hide any big liquid-glass view/layer that is not part of our own page.
static void CC26HuntExpandedGlass(void) {
    if (!gCCAModuleExpanded) return;
    for (UIWindow *window in UIApplication.sharedApplication.windows) {
        UIView *page = [window viewWithTag:kCC26EmbeddedPageTag];
        if (page.superview && page.superview.subviews.lastObject != page) [page.superview bringSubviewToFront:page];   // stock module must not sit above our buttons
        NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:window];
        int guard = 0;
        while (queue.count && guard++ < 3000) {
            UIView *v = queue.firstObject;
            [queue removeObjectAtIndex:0];
            if (v == page || v.hidden) continue;
            if (CC26BigBox(v.bounds.size) && (CC26LayerHasLiquidGlass(v.layer) || CC26IsStockMaterial(v))) {
                if (!sCC26HiddenBox) sCC26HiddenBox = [NSMutableArray array];
                [sCC26HiddenBox addObject:v];
                v.hidden = YES;
                continue;
            }
            CC26HuntSubLayers(v.layer, 0);
            [queue addObjectsFromArray:v.subviews];
        }
    }
}

static void CC26StartGlassHunt(void) {
    CC26HuntExpandedGlass();
    if (sCC26HuntTimer) return;
    // fast while the module opens (the stock glass shows up then), relaxed afterwards: the hunt
    // walks every view of every window, running it 20 times a second all the time made it laggy
    __block NSUInteger ticks = 0;
    sCC26HuntTimer = [NSTimer scheduledTimerWithTimeInterval:0.05 repeats:YES block:^(NSTimer *t) {
        if (!gCCAModuleExpanded) { [t invalidate]; sCC26HuntTimer = nil; return; }
        ticks++;
        if (ticks > 24 && ticks % 6 != 0) return;
        CC26HuntExpandedGlass();
    }];
}

static void CC26RestoreExpandedChrome(void) {
    [sCC26HuntTimer invalidate];
    sCC26HuntTimer = nil;
    for (CALayer *l in sCC26HiddenLayers) l.hidden = NO;
    sCC26HiddenLayers = nil;
    for (UIView *v in sCC26HiddenBox) v.hidden = NO;
    sCC26HiddenBox = nil;
    for (NSDictionary *d in sCC26SavedLayers) {
        UIView *v = d[@"v"];
        CALayer *l = v.layer;
        l.backgroundColor = d[@"bg"] ? (__bridge CGColorRef)d[@"bg"] : nil;
        l.filters = d[@"f"];
        l.backgroundFilters = d[@"bf"];
        l.borderWidth = [d[@"bw"] doubleValue];
        l.shadowOpacity = [d[@"so"] floatValue];
    }
    sCC26SavedLayers = nil;
    if (sCC26DisabledTouches) sCC26ExpandedContainer.userInteractionEnabled = YES;
    sCC26DisabledTouches = NO;
    sCC26ExpandedController = nil;
    sCC26ExpandedContainer = nil;
}

static void CC26HideChrome(UIView *v) {
    if (!v || v.hidden || v.tag == kCC26EmbeddedPageTag) return;
    if (!sCC26HiddenBox) sCC26HiddenBox = [NSMutableArray array];
    [sCC26HiddenBox addObject:v];
    v.hidden = YES;
}

// Hides everything the stock expanded module draws behind its buttons (the big rounded box):
// every sibling along the path from the module container down to the module content, plus the
// layer fill/filters/rim of those views. Our own page lives in the overlay, so it is untouched.
void CC26StripExpandedBackground(UIView *container) {
    UIViewController *controller = sCC26ExpandedController;
    if (!container || !controller || !gCCAModuleExpanded || container != sCC26ExpandedContainer) return;
    UIView *root = controller.view;
    if (!root) return;
    NSArray<NSString *> *names = @[@"CCUIConnectivityAirplaneViewController", @"CCUIConnectivityCellularDataViewController", @"CCUIConnectivityWifiViewController", @"CCUIConnectivityBluetoothViewController", @"CCUIConnectivityAirDropViewController", @"CCUIConnectivityHotspotViewController"];
    NSMutableArray<UIView *> *keep = [NSMutableArray array];
    for (NSString *n in names) { UIView *cv = CC26ConnectivityChild(controller, n).view; if (cv) [keep addObject:cv]; }
    UIView *cluster = [root viewWithTag:CC26TagConnectivityCluster];
    if (cluster) [keep addObject:cluster];

    UIView *cur = container;
    int guard = 0;
    while (cur && guard++ < 24) {
        CC26ClearLayerChrome(cur);
        if (cur == root) {
            for (UIView *s in cur.subviews) {
                BOOL needed = NO;
                for (UIView *k in keep) if (k == s || [k isDescendantOfView:s]) { needed = YES; break; }
                if (!needed) CC26HideChrome(s);
            }
            break;
        }
        UIView *next = nil;
        for (UIView *s in cur.subviews) {
            if (s == root || [root isDescendantOfView:s]) next = s;
            else CC26HideChrome(s);
        }
        cur = next;
    }
    // views above the container can still draw a dark square (fill / shadow) behind the page
    CGRect screen = UIScreen.mainScreen.bounds;
    UIView *up = container.superview;
    int guardUp = 0;
    while (up && guardUp++ < 8 && ![up isKindOfClass:UIWindow.class]) {
        BOOL smallerThanScreen = CGRectGetWidth(up.bounds) < CGRectGetWidth(screen) * 0.97 ||
                                 CGRectGetHeight(up.bounds) < CGRectGetHeight(screen) * 0.97;
        if (smallerThanScreen && up.tag != kCC26EmbeddedPageTag) CC26ClearLayerChrome(up);
        up = up.superview;
    }
}


static __weak UIView *sCC26EmbeddedPageRef = nil;

// The expanded module is presented in its own view hierarchy that sits ABOVE the overlay view,
// so a page added to the overlay is covered (and its touches swallowed). The page goes into the
// window of the expanded module instead: it is then the top-most view and gets every touch.
static UIView *CC26PageHost(UIViewController *controller) {
    UIView *container = CC26Ancestor(controller.view, @"CCUIContentModuleContainerView");
    UIWindow *window = container.window ?: controller.view.window;
    if (window) return window;
    UIViewController *overlay = CC26OverlayForView(controller.view);
    return overlay.view ?: controller.view;
}

static UIView *CC26EmbeddedHost(UIViewController *controller) {
    UIViewController *overlay = CC26OverlayForView(controller.view);
    return overlay.view ?: controller.view;
}

// YES when a liquid-glass layer that is not ours (tag 190001) lives inside `root`
static BOOL CC26SubtreeHasForeignGlass(UIView *root) {
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:root];
    int guard = 0;
    while (queue.count && guard++ < 80) {
        UIView *v = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if (v.tag == 190001) continue;
        if (v != root && CC26LayerHasLiquidGlass(v.layer)) return YES;
        for (CALayer *sub in v.layer.sublayers) {
            if (!sub.delegate && CC26LayerHasLiquidGlass(sub)) return YES;
        }
        [queue addObjectsFromArray:v.subviews];
    }
    return NO;
}

static void CC26RemoveGlass(UIView *host) {
    UIView *g = [host viewWithTag:190001];
    if (g) { g.layer.filters = nil; [g removeFromSuperview]; }
}

// While the connectivity module is expanded, every view that draws the stock rounded box (same
// size and centre as the expanded module, whatever its class) is hidden; restored on close.
static void CC26ExpandedChrome(UIViewController *controller, BOOL expanded) {
    if (!expanded) {
        CC26RestoreExpandedChrome();
        return;
    }
    UIView *host = CC26EmbeddedHost(controller);
    UIView *container = CC26Ancestor(controller.view, @"CCUIContentModuleContainerView") ?: controller.view;
    sCC26ExpandedController = controller;
    sCC26ExpandedContainer = container;
    CC26StripExpandedBackground(container);
    CC26StartGlassHunt();
    CGRect box = [container convertRect:container.bounds toView:host];
    if (CGRectGetWidth(box) < 150.0 || CGRectGetHeight(box) < 150.0) return;
    if (!sCC26HiddenBox) sCC26HiddenBox = [NSMutableArray array];
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithArray:host.subviews];
    int guard = 0;
    while (queue.count && guard++ < 400) {
        UIView *v = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if (v.tag == kCC26EmbeddedPageTag || v.hidden) continue;
        CGRect r = [v convertRect:v.bounds toView:host];
        BOOL sameBox = CGRectGetWidth(r) >= CGRectGetWidth(box) * 0.80 && CGRectGetWidth(r) <= CGRectGetWidth(box) * 1.15 &&
                       CGRectGetHeight(r) >= CGRectGetHeight(box) * 0.80 && CGRectGetHeight(r) <= CGRectGetHeight(box) * 1.15 &&
                       fabs(CGRectGetMidX(r) - CGRectGetMidX(box)) < 40.0 && fabs(CGRectGetMidY(r) - CGRectGetMidY(box)) < 40.0;
        if (sameBox) { [sCC26HiddenBox addObject:v]; v.hidden = YES; continue; }
        [queue addObjectsFromArray:v.subviews];
    }
}

// Called when the expanded module closes: remove our page and give the stock module back.
UIView *CC26ConnectivityShowFloatingDetail(UIView *host, NSString *kind, CGRect anchor);

// Long press on Wi-Fi / AirDrop / Bluetooth in the compact module opens the same detail
// sections as the expanded page (nearby networks, devices, AirDrop options).
static const NSInteger kCC26CompactHoldTag = 18006;
static void *kCC26CompactHoldKey = &kCC26CompactHoldKey;

// fires the real stock button of a connectivity child controller (same thing a tap does)
static void CC26FireStockButton(UIViewController *controller, NSString *className) {
    UIViewController *child = CC26ConnectivityChild(controller, className);
    if (!child || !child.isViewLoaded) return;
    UIControl *button = nil;
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:child.view];
    while (queue.count) {
        UIView *v = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if ([v isKindOfClass:UIControl.class]) { button = (UIControl *)v; break; }
        [queue addObjectsFromArray:v.subviews];
    }
    if (!button) return;
    BOOL fired = NO;
    NSMutableSet<NSString *> *sent = [NSMutableSet set];
    for (NSNumber *event in @[@(UIControlEventTouchUpInside), @(UIControlEventPrimaryActionTriggered)]) {
        for (id target in button.allTargets.allObjects) {
            if (target == NSNull.null) continue;
            for (NSString *action in [button actionsForTarget:target forControlEvent:(UIControlEvents)event.unsignedIntegerValue]) {
                NSString *key = [NSString stringWithFormat:@"%p:%@", target, action];
                if ([sent containsObject:key]) continue;
                [sent addObject:key];
                [button sendAction:NSSelectorFromString(action) to:target forEvent:nil];
                fired = YES;
            }
        }
    }
    if (!fired) {
        SEL fallback = NSSelectorFromString(@"buttonTapped:");
        if ([child respondsToSelector:fallback]) ((void (*)(id, SEL, id))objc_msgSend)(child, fallback, button);
    }
}

// ---------------------------------------------------------------------------
// Separate modules (Wi-Fi, Bluetooth, Airplane, ...). They never talk to the radios themselves:
// they read and press the very same stock iOS 16 buttons the connectivity module already owns, so
// they behave exactly like the original buttons.
// ---------------------------------------------------------------------------
static __weak UIViewController *sCC26StockConnectivity = nil;

void CC26RememberStockConnectivity(UIViewController *controller) { sCC26StockConnectivity = controller; }
UIViewController *CC26StockConnectivityForSplit(void) { return sCC26StockConnectivity; }

static NSString *CC26SplitClassForKind(NSInteger kind) {
    NSArray<NSString *> *names = @[@"CCUIConnectivityWifiViewController", @"CCUIConnectivityBluetoothViewController",
                                   @"CCUIConnectivityAirplaneViewController", @"CCUIConnectivityCellularDataViewController",
                                   @"CCUIConnectivityAirDropViewController", @"CCUIConnectivityHotspotViewController"];
    return (kind >= 0 && (NSUInteger)kind < names.count) ? names[(NSUInteger)kind] : nil;
}

int CC26SplitModuleState(NSInteger kind) {
    UIViewController *controller = sCC26StockConnectivity;
    NSString *className = CC26SplitClassForKind(kind);
    UIViewController *child = (controller && className) ? CC26ConnectivityChild(controller, className) : nil;
    if (!child || !child.isViewLoaded) return -1;
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:child.view];
    while (queue.count) {
        UIView *v = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if ([v isKindOfClass:UIControl.class]) return ((UIControl *)v).selected ? 1 : 0;
        [queue addObjectsFromArray:v.subviews];
    }
    return -1;
}

void CC26SplitModuleToggle(NSInteger kind) {
    UIViewController *controller = sCC26StockConnectivity;
    NSString *className = CC26SplitClassForKind(kind);
    if (controller && className) CC26FireStockButton(controller, className);
}

// "26 Menu" off: the long press goes to the stock iOS 16 button instead of our panel. The
// handlers of the stock long-press recognizers (button and its ancestors) are called directly.
BOOL CC26FireStockLongPress(UIViewController *controller, NSString *className) {
    UIViewController *child = CC26ConnectivityChild(controller, className);
    if (!child || !child.isViewLoaded) return NO;
    NSMutableArray<UIGestureRecognizer *> *recognizers = [NSMutableArray array];
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:child.view];
    int guardCount = 0;
    while (queue.count && guardCount++ < 60) {
        UIView *v = queue.firstObject;
        [queue removeObjectAtIndex:0];
        for (UIGestureRecognizer *g in v.gestureRecognizers) if ([g isKindOfClass:UILongPressGestureRecognizer.class]) [recognizers addObject:g];
        [queue addObjectsFromArray:v.subviews];
    }
    UIView *container = CC26Ancestor(child.view, @"CCUIContentModuleContainerView");
    for (UIView *up = child.view.superview; up; up = up.superview) {
        for (UIGestureRecognizer *g in up.gestureRecognizers) if ([g isKindOfClass:UILongPressGestureRecognizer.class]) [recognizers addObject:g];
        if (up == container) break;
    }
    BOOL fired = NO;
    for (UIGestureRecognizer *g in recognizers) {
        NSArray *targets = nil;
        @try { targets = [g valueForKey:@"_targets"]; } @catch (__unused NSException *e) {}
        for (id t in targets) {
            Ivar targetIvar = class_getInstanceVariable([t class], "_target");
            Ivar actionIvar = class_getInstanceVariable([t class], "_action");
            if (!targetIvar || !actionIvar) continue;
            id target = object_getIvar(t, targetIvar);
            SEL action = *(SEL *)((uint8_t *)(__bridge void *)t + ivar_getOffset(actionIvar));
            if (!target || !action || ![target respondsToSelector:action]) continue;
            SEL setState = NSSelectorFromString(@"setState:");
            if ([g respondsToSelector:setState]) ((void (*)(id, SEL, NSInteger))objc_msgSend)(g, setState, UIGestureRecognizerStateBegan);
            ((void (*)(id, SEL, id))objc_msgSend)(target, action, g);
            fired = YES;
        }
    }
    return fired;
}

// Transparent hit area over each button of the compact module: tap toggles the real radio,
// long press (Wi-Fi / AirDrop / Bluetooth) opens the detail section.
@interface CC26CompactHold : NSObject <UIGestureRecognizerDelegate>
@property (nonatomic, copy) NSString *kind;        // nil = tap only
@property (nonatomic, copy) NSString *className;
@property (nonatomic, weak) UIViewController *controller;
@end

@implementation CC26CompactHold
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)a shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)b { return NO; }
// "26 Menu" off: our long press never starts, so the stock one (the iOS 16 menu) keeps working
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)g {
    if ([g isKindOfClass:UILongPressGestureRecognizer.class]) return gMenu26;
    return YES;
}
- (void)tapped:(UITapGestureRecognizer *)g {
    UIViewController *c = self.controller;
    if (!c || gCCAModuleExpanded || g.state != UIGestureRecognizerStateRecognized) return;
    Haptic();
    CC26FireStockButton(c, self.className);
}
- (void)held:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan) return;
    UIViewController *c = self.controller;
    UIView *v = g.view;
    if (!c || !v || gCCAModuleExpanded || !self.kind) return;
    // stop the stock long press (expand) of the module for this touch
    UIView *container = CC26Ancestor(c.view, @"CCUIContentModuleContainerView");
    for (UIView *cur = v; cur; cur = cur.superview) {
        for (UIGestureRecognizer *other in [cur.gestureRecognizers copy]) {
            if (other != g && other.enabled) { other.enabled = NO; other.enabled = YES; }
        }
        if (cur == container) break;
    }
    Haptic();
    UIView *host = CC26EmbeddedHost(c);
    CC26ConnectivityShowFloatingDetail(host, self.kind, [v convertRect:v.bounds toView:host]);
}
@end

static UIView *CC26CompactHit(UIView *root, NSInteger index, CGRect frame, NSString *className, NSString *kind, UIViewController *controller) {
    NSInteger tag = kCC26CompactHoldTag + 1 + index;
    UIView *hit = [root viewWithTag:tag];
    if (!hit) {
        hit = [UIView new];
        hit.tag = tag;
        hit.backgroundColor = UIColor.clearColor;
        CC26CompactHold *target = [CC26CompactHold new];
        target.kind = kind;
        target.className = className;
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:target action:@selector(tapped:)];
        tap.delegate = target;
        [hit addGestureRecognizer:tap];
        if (kind) {
            UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc] initWithTarget:target action:@selector(held:)];
            hold.minimumPressDuration = 0.3;
            hold.delegate = target;
            [hit addGestureRecognizer:hold];
        }
        objc_setAssociatedObject(hit, kCC26CompactHoldKey, target, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [root addSubview:hit];
    }
    CC26CompactHold *target = objc_getAssociatedObject(hit, kCC26CompactHoldKey);
    target.controller = controller;
    hit.frame = frame;
    hit.userInteractionEnabled = YES;
    hit.hidden = NO;
    [root bringSubviewToFront:hit];
    return hit;
}

// Same rectangle as the music page card: the 451:808 layout on the stock module grid.
static CGRect CC26MediaCardRectInWindow(UIWindow *window) {
    CGRect screen = window.bounds;
    CGRect grid = CC26StockGridRect();
    if (CGRectIsNull(grid)) {
        CGFloat w = floor(CGRectGetWidth(screen) * 0.86);
        CGFloat h = MIN(floor(w * 1.8), CGRectGetHeight(screen) - 160.0);
        return CGRectMake(floor((CGRectGetWidth(screen) - w) * 0.5), 110.0, w, h);
    }
    BOOL notched = CGRectGetHeight(screen) >= 800.0;
    CGFloat bottomMargin = window.safeAreaInsets.bottom + (notched ? 30.0 : 24.0);
    CGFloat avail = MAX(200.0, CGRectGetHeight(screen) - grid.origin.y - bottomMargin);
    CGFloat scale = MIN(grid.size.width / 451.0, avail / 808.0);
    CGFloat w = floor(451.0 * scale), h = floor(808.0 * scale);
    return CGRectMake(grid.origin.x + floor((grid.size.width - w) * 0.5), grid.origin.y, w, h);
}

// Long press on the compact music module: the stock expanded view is replaced by the very same
// player as the music page (same size, same layout).
void CC26EmbedExpandedMediaIfNeeded(UIView *nowPlaying) {
    if (!gEnabled || !gCCAModuleExpanded || !nowPlaying.window) return;
    UIView *container = CC26Ancestor(nowPlaying, @"CCUIContentModuleContainerView");
    if (!container || CGRectGetWidth(container.bounds) < 240.0) return;   // still the compact card
    UIWindow *window = nowPlaying.window;
    UIResponder *responder = nowPlaying;
    while (responder && ![responder isKindOfClass:UIViewController.class]) responder = responder.nextResponder;
    UIViewController *controller = (UIViewController *)responder;
    if (!controller) return;
    CCAMediaPlayerView *player = (CCAMediaPlayerView *)(sCC26EmbeddedPageRef ?: [window viewWithTag:kCC26EmbeddedPageTag]);
    CGRect rect = CC26MediaCardRectInWindow(window);
    if (![player isKindOfClass:CCAMediaPlayerView.class]) {
        player = [[CCAMediaPlayerView alloc] initWithFrame:rect];
        player.embedded = YES;
        player.tag = kCC26EmbeddedPageTag;
        player.alpha = 0.0;
        [window addSubview:player];
        sCC26EmbeddedPageRef = player;
        [UIView animateWithDuration:0.22 animations:^{ player.alpha = 1.0; }];
    }
    player.frame = rect;
    sCC26ExpandedController = controller;
    sCC26ExpandedContainer = container;
    CC26StripExpandedBackground(container);
    CC26StartGlassHunt();
    [window bringSubviewToFront:player];
}

void CC26DismissEmbeddedConnectivity(UIViewController *overlay) {
    UIView *page = sCC26EmbeddedPageRef ?: [overlay.view viewWithTag:kCC26EmbeddedPageTag];
    sCC26EmbeddedPageRef = nil;
    CC26RestoreExpandedChrome();
    if (page) {
        [UIView animateWithDuration:0.16 animations:^{ page.alpha = 0.0; }
                         completion:^(BOOL f) { [page removeFromSuperview]; }];
    }
}

void CC26ConfigureConnectivity(UIViewController *controller) {
    CC26RememberStockConnectivity(controller);
    UIView *root = controller.view;
    CGFloat side = MIN(CGRectGetWidth(root.bounds), CGRectGetHeight(root.bounds));
    UIView *cluster = [root viewWithTag:CC26TagConnectivityCluster];
    NSArray<NSString *> *allClasses = @[@"CCUIConnectivityAirplaneViewController", @"CCUIConnectivityCellularDataViewController", @"CCUIConnectivityWifiViewController", @"CCUIConnectivityBluetoothViewController", @"CCUIConnectivityAirDropViewController", @"CCUIConnectivityHotspotViewController"];
    UIView *embeddedPage = sCC26EmbeddedPageRef ?: ([CC26EmbeddedHost(controller) viewWithTag:kCC26EmbeddedPageTag] ?: [root viewWithTag:kCC26EmbeddedPageTag]);
    if (side <= 0.0 || CGRectGetWidth(root.bounds) >= 190.0 || CGRectGetHeight(root.bounds) >= 190.0) {
        // expanded (long press): show the same layout as the Connectivity page
        cluster.hidden = YES;
        for (NSInteger i = 1; i <= 6; i++) [root viewWithTag:kCC26CompactHoldTag + i].hidden = YES;
        BOOL embed = gEnabled && side > 0.0;
        CCAConnectivityPageView *page = (CCAConnectivityPageView *)embeddedPage;
        if (embed) {
            BOOL fresh = (page == nil);
            if (fresh) {
                page = [[CCAConnectivityPageView alloc] initWithFrame:root.bounds];
                page.tag = kCC26EmbeddedPageTag;
                page.embedded = YES;
                page.hostController = controller;
                [CC26PageHost(controller) addSubview:page];
                sCC26EmbeddedPageRef = page;
            }
            {
                UIView *host = page.superview ?: CC26PageHost(controller);
                CGRect hb = host.bounds;
                CGFloat pw = floor(CGRectGetWidth(hb) * 0.80) + 24.0;
                CGFloat ph = MIN(CC26ConnectivityExpandedHeightForWidth(pw), CGRectGetHeight(hb) - 110.0);
                CGRect rr = [root convertRect:root.bounds toView:host];
                CGFloat cy = MIN(MAX(CGRectGetMidY(rr), 70.0 + ph * 0.5), CGRectGetHeight(hb) - 40.0 - ph * 0.5);
                page.frame = CGRectMake(floor((CGRectGetWidth(hb) - pw) * 0.5), floor(cy - ph * 0.5), pw, ph);
            }
            page.clipsToBounds = NO;
            CC26ExpandedChrome(controller, YES);
            __weak UIViewController *weakC = controller;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (weakC && gCCAModuleExpanded) CC26ExpandedChrome(weakC, YES);
            });
            [page.superview bringSubviewToFront:page];
            for (NSString *name in allClasses) {
                UIView *view = CC26ConnectivityChild(controller, name).view;
                view.alpha = 0.0;
                view.userInteractionEnabled = NO;
                CC26RemoveGlass(view);
                CC26ScaleMiniGlyphs(view, 1.0);
            }
            if (fresh) {
                [page layoutIfNeeded];
                [page refreshStates];
                [page playStretchIn];
            }
            return;
        }
        [embeddedPage removeFromSuperview];
        CC26ExpandedChrome(controller, NO);
        for (NSString *name in allClasses) {
            UIView *view = CC26ConnectivityChild(controller, name).view;
            view.hidden = NO;
            view.alpha = 1.0;
            view.userInteractionEnabled = YES;
            view.transform = CGAffineTransformIdentity;
            CC26ScaleMiniGlyphs(view, 1.0);
        }
        return;
    }
    [embeddedPage removeFromSuperview];
    CC26ExpandedChrome(controller, NO);
    // ===== SPACING OF THE ROUND BUTTONS (edit these two numbers) =====
    CGFloat kBigGapFactor  = 0.10;   // space between airplane / AirDrop / Wi-Fi (was 0.055). Higher = more space, smaller circles
    CGFloat kMiniGapFactor = 0.14;    // space between the 4 small icons, as a fraction of a big circle (was ~0.04)
    // ==================================================================
    CGFloat inset = MAX(6.0, round(side * 0.103));
    CGFloat gap = MAX(4.0, round(side * kBigGapFactor));
    CGFloat cell = floor((side - inset * 2.0 - gap) * 0.5);
    CGFloat originX = round((CGRectGetWidth(root.bounds) - (cell * 2.0 + gap)) * 0.5);
    CGFloat originY = round((CGRectGetHeight(root.bounds) - (cell * 2.0 + gap)) * 0.5);
    CGRect topLeft = CGRectMake(originX, originY, cell, cell);
    CGRect topRight = CGRectMake(originX + cell + gap, originY, cell, cell);
    CGRect bottomLeft = CGRectMake(originX, originY + cell + gap, cell, cell);
    CGRect bottomRight = CGRectMake(originX + cell + gap, originY + cell + gap, cell, cell);

    NSDictionary<NSString *, NSValue *> *visible = @{
        @"CCUIConnectivityAirplaneViewController": [NSValue valueWithCGRect:topLeft],
        @"CCUIConnectivityWifiViewController": [NSValue valueWithCGRect:bottomLeft],
        @"CCUIConnectivityAirDropViewController": [NSValue valueWithCGRect:topRight]
    };
    for (NSString *name in visible) {
        UIView *view = CC26ConnectivityChild(controller, name).view;
        view.frame = visible[name].CGRectValue;
        view.hidden = NO;
        view.alpha = 1.0;
        view.userInteractionEnabled = YES;
        CC26ReplaceStockGlyph(view, CC26StockGlyphNames(name), cell * 0.40);
    }
    CGFloat naturalMiniCell = floor(cell * 0.444);
    CGFloat naturalMiniGap = cell - naturalMiniCell * 2.0;
    (void)naturalMiniGap;
    CGFloat requestedMiniGap = MAX(3.0, round(cell * kMiniGapFactor));
    CGFloat miniCell = floor((cell - requestedMiniGap) * 0.5);
    CGFloat miniGap = cell - miniCell * 2.0;
    if (!cluster) {
        cluster = [[UIView alloc] initWithFrame:bottomRight];
        cluster.tag = CC26TagConnectivityCluster;
        cluster.userInteractionEnabled = NO;
        // candidate names per tile, best (iOS 26 look, from CC18.bundle) first
        NSArray<NSArray<NSString *> *> *symbols = @[
            @[@"cellularbars"],
            @[@"bluetooth"],
            @[@"personalhotspot"],
            @[@"network"]
        ];
        NSArray<UIColor *> *colors = @[
            [UIColor colorWithRed:0.26 green:0.66 blue:1.0 alpha:0.48],
            [UIColor colorWithRed:0.36 green:0.20 blue:1.0 alpha:1.0],
            [UIColor.whiteColor colorWithAlphaComponent:0.30],
            [UIColor.whiteColor colorWithAlphaComponent:0.30]
        ];
        for (NSUInteger index = 0; index < symbols.count; index++) {
            UIView *tile = [UIView new];
            tile.backgroundColor = [colors[index] colorWithAlphaComponent:index == 1 ? 0.85 : 0.18];
            if (index == 3) {
                UIView *backing = [UIView new];
                backing.tag = 2;
                backing.backgroundColor = UIColor.whiteColor;
                backing.hidden = YES;
                backing.userInteractionEnabled = NO;
                [tile addSubview:backing];
            }
            UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration configurationWithPointSize:9.0 weight:UIImageSymbolWeightSemibold];
            UIImage *symbolImage = nil;
            for (NSString *symbolName in symbols[index]) {
                symbolImage = CC26SVGSymbol(symbolName, miniCell * 0.66) ?: CC26BundledSymbol(symbolName, UIColor.whiteColor, NO);
                if (symbolImage) break;
            }
            if (symbolImage && !symbolImage.symbolConfiguration) symbolImage = [symbolImage imageByApplyingSymbolConfiguration:configuration] ?: symbolImage;
            UIImageView *icon = [[UIImageView alloc] initWithImage:symbolImage];
            icon.tag = 1;
            icon.contentMode = UIViewContentModeCenter;
            icon.tintColor = colors[index];
            [tile addSubview:icon];
            if (index < 3) tile.hidden = YES;
            [cluster addSubview:tile];
        }
        [root addSubview:cluster];
    }
    cluster.hidden = NO;
    cluster.frame = bottomRight;
    [cluster.subviews enumerateObjectsUsingBlock:^(UIView *tile, NSUInteger index, __unused BOOL *stop) {
        CGFloat x = (index % 2) * (miniCell + miniGap), y = (index / 2) * (miniCell + miniGap);
        tile.frame = CGRectMake(x, y, miniCell, miniCell);
        tile.layer.cornerRadius = miniCell * 0.5;
        tile.layer.masksToBounds = YES;
        [tile viewWithTag:1].frame = tile.bounds;
        [tile viewWithTag:2].frame = tile.bounds;
        tile.hidden = index < 3;
    }];
    UIView *vpnTile = cluster.subviews.lastObject;
    UIView *vpnBacking = [vpnTile viewWithTag:2];
    {
        // the VPN tile has no stock glyph: iOS 26 artwork, or the plain system symbol when "iOS 26 Icons" is off
        UIImage *vpnImage = gIOS26Icons ? CC26SVGSymbol(@"network", miniCell * 0.66) : nil;
        if (!vpnImage) {
            UIImageSymbolConfiguration *vpnCfg = [UIImageSymbolConfiguration configurationWithPointSize:miniCell * 0.46 weight:UIImageSymbolWeightSemibold];
            vpnImage = [UIImage systemImageNamed:@"network" withConfiguration:vpnCfg];
        }
        UIImageView *vpnIcon = (UIImageView *)[vpnTile viewWithTag:1];
        if ([vpnIcon isKindOfClass:UIImageView.class] && vpnImage) vpnIcon.image = [vpnImage imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    }
    NSArray *vibrantFilters = CC26ConnectivityVibrantFilters(root);
    if (vibrantFilters.count) { vpnBacking.layer.filters = vibrantFilters; vpnBacking.hidden = NO; }
    vpnTile.backgroundColor = UIColor.clearColor;
    ((UIImageView *)[vpnTile viewWithTag:1]).tintColor = UIColor.whiteColor;
    [root bringSubviewToFront:cluster];
    NSArray<NSString *> *miniClasses = @[@"CCUIConnectivityCellularDataViewController", @"CCUIConnectivityBluetoothViewController", @"CCUIConnectivityHotspotViewController"];
    NSUInteger slot = 0;
    for (NSString *className in miniClasses) {
        UIViewController *child = CC26ConnectivityChild(controller, className);
        UIView *view = child.view;
        if (!view) continue;
        view.hidden = NO;
        view.alpha = 1.0;
        view.userInteractionEnabled = NO;
        view.transform = CGAffineTransformIdentity;
        view.bounds = CGRectMake(0.0, 0.0, cell, cell);
        view.center = CGPointMake(CGRectGetMinX(bottomRight) + (slot % 2) * (miniCell + miniGap) + miniCell * 0.5,
            CGRectGetMinY(bottomRight) + (slot / 2) * (miniCell + miniGap) + miniCell * 0.5);
        view.transform = CGAffineTransformMakeScale(miniCell / cell, miniCell / cell);
        CC26ScaleMiniGlyphs(view, 1.2);
        // the stock view is scaled down by miniCell/cell, so the glyph is drawn bigger in its own
        // coordinates to end up at the on-screen size we want
        CC26ReplaceStockGlyph(view, CC26StockGlyphNames(className), (miniCell * 0.60) / (miniCell / cell));
        [root bringSubviewToFront:view];
        slot++;
    }
    {
        // transparent hit areas (tap = real toggle, long press = detail section)
        CGFloat step = miniCell + miniGap;
        CC26CompactHit(root, 1, topLeft, @"CCUIConnectivityAirplaneViewController", nil, controller);
        CC26CompactHit(root, 2, topRight, @"CCUIConnectivityAirDropViewController", @"airdrop", controller);
        CC26CompactHit(root, 3, bottomLeft, @"CCUIConnectivityWifiViewController", @"wifi", controller);
        CC26CompactHit(root, 4, CGRectMake(CGRectGetMinX(bottomRight), CGRectGetMinY(bottomRight), miniCell, miniCell), @"CCUIConnectivityCellularDataViewController", nil, controller);
        CC26CompactHit(root, 5, CGRectMake(CGRectGetMinX(bottomRight) + step, CGRectGetMinY(bottomRight), miniCell, miniCell), @"CCUIConnectivityBluetoothViewController", @"bluetooth", controller);
        CC26CompactHit(root, 6, CGRectMake(CGRectGetMinX(bottomRight), CGRectGetMinY(bottomRight) + step, miniCell, miniCell), @"CCUIConnectivityHotspotViewController", nil, controller);
    }
    vpnTile.frame = CGRectMake((slot % 2) * (miniCell + miniGap), (slot / 2) * (miniCell + miniGap), miniCell, miniCell);
    [cluster bringSubviewToFront:vpnTile];

    // Liquid glass only on the buttons of this module, sized/rounded to each one so it
    // follows them exactly (the glass is a subview, so it moves with its button).
    for (NSString *name in allClasses) {
        UIView *view = CC26ConnectivityChild(controller, name).view;
        if (!view || view.hidden || view.alpha < 0.01) continue;
        // if the stock button already got a liquid glass from LiquidAss, ours would sit on top of
        // it (doubled glass: the glyph looks stuck on a second disc), so only add it when missing
        if (CC26SubtreeHasForeignGlass(view)) { CC26RemoveGlass(view); continue; }
        CGFloat dia = MIN(CGRectGetWidth(view.bounds), CGRectGetHeight(view.bounds));
        @try { CC26LIQApplyGlass(view, dia * 0.5); } @catch (__unused NSException *e) {}
    }
    @try { CC26LIQApplyGlass(vpnTile, miniCell * 0.5); } @catch (__unused NSException *e) {}
}

static CGRect sCC26StockGrid;
static BOOL sCC26StockGridValid = NO;

CGRect CC26StockGridRect(void) { return sCC26StockGridValid ? sCC26StockGrid : CGRectNull; }

// The pages (connectivity, media) are laid out on the exact rectangle the stock modules occupy on
// page 0, so the distance to the status row, to the screen edges and to the page icons is the same
// as for the regular modules on every device. Measured only while the modules are at rest.
void CC26UpdateStockGrid(UIViewController *overlay) {
    if (!overlay.isViewLoaded) return;
    CGRect screen = UIScreen.mainScreen.bounds;
    CGRect bounds = CGRectNull;
    NSUInteger count = 0;
    NSMutableArray<UIViewController *> *queue = [NSMutableArray arrayWithArray:overlay.childViewControllers];
    while (queue.count) {
        UIViewController *controller = queue.firstObject;
        [queue removeObjectAtIndex:0];
        [queue addObjectsFromArray:controller.childViewControllers];
        if (![NSStringFromClass(controller.class) containsString:@"ContentModuleContainerViewController"]) continue;
        UIView *v = controller.view;
        if (!v || v.hidden || v.alpha < 0.99) continue;
        BOOL still = YES;
        for (UIView *s = v; s && s != overlay.view.superview; s = s.superview) {
            CALayer *pres = (CALayer *)s.layer.presentationLayer;
            if (!CGAffineTransformIsIdentity(s.transform) || (pres && !CATransform3DIsIdentity(pres.transform))) { still = NO; break; }
        }
        if (!still) continue;
        CGRect frame = [v convertRect:v.bounds toView:nil];
        if (!CGRectIntersectsRect(frame, screen)) continue;
        bounds = CGRectIsNull(bounds) ? frame : CGRectUnion(bounds, frame);
        count++;
    }
    if (count < 4 || CGRectIsNull(bounds)) return;
    CGFloat w = CGRectGetWidth(bounds), h = CGRectGetHeight(bounds);
    if (w < screen.size.width * 0.75 || w > screen.size.width) return;
    if (h < screen.size.height * 0.45 || CGRectGetMinY(bounds) < 40.0 || CGRectGetMaxY(bounds) > screen.size.height) return;
    sCC26StockGrid = bounds;
    sCC26StockGridValid = YES;
}

CGRect CC26VisibleModuleBounds(UIViewController *overlay) {
    CGRect bounds = CGRectNull;
    NSMutableArray<UIViewController *> *queue = [NSMutableArray arrayWithArray:overlay.childViewControllers];
    while (queue.count) {
        UIViewController *controller = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if ([NSStringFromClass(controller.class) containsString:@"ContentModuleContainerViewController"] &&
            !controller.view.hidden && controller.view.alpha > 0.01) {
            CGRect frame = [controller.view convertRect:controller.view.bounds toView:overlay.view];
            if (CGRectIntersectsRect(frame, overlay.view.bounds)) bounds = CGRectIsNull(bounds) ? frame : CGRectUnion(bounds, frame);
        }
        [queue addObjectsFromArray:controller.childViewControllers];
    }
    return bounds;
}