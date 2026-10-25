#import "CC26.h"
BOOL gPagerScrubbing = NO;

// Real fix for the "semi square" 2x2 modules: UIKit/CoreAnimation draw the radius that is
// STORED on the layer, not the one a getter hook returns, and the stock code re-sets it on
// every layout. So the radius is replaced at the moment it is written.
static BOOL CC26LayerInSquareModule(CALayer *layer, CGFloat *outRadius) {
    CGSize sz = layer.bounds.size;
    CGFloat m = MIN(sz.width, sz.height);
    if (m < 130.0 || m > 200.0 || fabs(sz.width - sz.height) >= 14.0) return NO;
    id d = layer.delegate;
    if (![d isKindOfClass:UIView.class]) d = layer.superlayer.delegate;
    UIView *v = [d isKindOfClass:UIView.class] ? (UIView *)d : nil;
    int guard = 0;
    while (v && guard++ < 7) {
        if ([NSStringFromClass(v.class) isEqualToString:@"CCUIContentModuleContainerView"]) {
            if (outRadius) *outRadius = floor(m * 0.19);
            return YES;
        }
        v = v.superview;
    }
    return NO;
}

%hook CALayer
- (CGFloat)cornerRadius {
    CGFloat radius = %orig;
    if (!gEnabled) return radius;   // this getter runs for every CALayer in SpringBoard, not just ours: bail out first
    static Class buttonModuleViewClass;
    static dispatch_once_t buttonModuleOnce;
    dispatch_once(&buttonModuleOnce, ^{ buttonModuleViewClass = NSClassFromString(@"CCUIButtonModuleView"); });
    if (buttonModuleViewClass && [self.superlayer.delegate isKindOfClass:buttonModuleViewClass]) {
        radius = calculatedRadius(self.visibleRect, radius);
    }
    return radius;
}
%end

%hook CALayer
- (void)setCornerRadius:(CGFloat)radius {
    CGFloat squared = 0.0;
    if (gEnabled && radius > 12.0 && CC26LayerInSquareModule(self, &squared)) radius = squared;
    %orig(radius);
}
%end

// while the Control Center opens the stock code ANIMATES cornerRadius with explicit values
// (that is the original round corner you could see at the start): rewrite those values too
static BOOL CC26LayerRadiusByAncestry(CALayer *layer, CGFloat *outRadius) {
    int guard = 0;
    for (CALayer *l = layer; l && guard++ < 10; l = l.superlayer) {
        id d = l.delegate;
        if ([d isKindOfClass:UIView.class] &&
            [NSStringFromClass([d class]) isEqualToString:@"CCUIContentModuleContainerView"]) {
            CGSize sz = ((UIView *)d).bounds.size;
            CGFloat m = MIN(sz.width, sz.height);
            if (m < 130.0 || m > 200.0 || fabs(sz.width - sz.height) >= 14.0) return NO;
            if (outRadius) *outRadius = floor(m * 0.19);
            return YES;
        }
    }
    return NO;
}

%hook CALayer
- (void)addAnimation:(CAAnimation *)anim forKey:(NSString *)key {
    if (gEnabled && [anim isKindOfClass:CABasicAnimation.class] &&
        [((CABasicAnimation *)anim).keyPath isEqualToString:@"cornerRadius"]) {
        CGFloat squared = 0.0;
        if (CC26LayerRadiusByAncestry(self, &squared)) {
            CABasicAnimation *fixed = [(CABasicAnimation *)anim copy];
            if (fixed.fromValue) fixed.fromValue = @(squared);
            if (fixed.toValue) fixed.toValue = @(squared);
            if (fixed.byValue) fixed.byValue = nil;
            anim = fixed;
        }
    }
    %orig(anim, key);
}
%end

// the layer can get its size AFTER its radius was written: square it the moment it gets a size
%hook CALayer
- (void)setBounds:(CGRect)bounds {
    %orig(bounds);
    CGFloat m = MIN(bounds.size.width, bounds.size.height);
    if (!gEnabled || m < 130.0 || m > 200.0 || fabs(bounds.size.width - bounds.size.height) >= 14.0) return;
    CGFloat squared = 0.0;
    if (self.cornerRadius > 12.0 && CC26LayerInSquareModule(self, &squared)) self.cornerRadius = squared;
}
%end

%hook MTMaterialLayer
- (void)setCornerRadius:(CGFloat)radius {
    CGFloat squared = 0.0;
    if (gEnabled && radius > 12.0 && CC26LayerInSquareModule(self, &squared)) radius = squared;
    %orig(radius);
}
- (CGFloat)cornerRadius {
    CGFloat radius = %orig;
    if (!gEnabled) return radius;   // MTMaterialLayer is the material/blur layer for the WHOLE OS
                                     // (icons, folders, widgets, status bar, app switcher...), so this
                                     // getter fires constantly outside Control Center too: bail out first
    NSString *recipe = self.recipeName;
    if ([recipe isEqualToString:@"modules"] || [recipe isEqualToString:@"moduleFill.highlight.generatedRecipe"]) {
        radius = calculatedRadius(self.visibleRect, radius);
    }
    return radius;
}
%end

static void CC26SquareCornersWalk(UIView *v, CGSize size, CGFloat r, int depth) {
    if (depth > 4) return;
    for (UIView *sub in v.subviews) {
        CGSize ss = sub.bounds.size;
        if (fabs(ss.width - size.width) < 2.0 && fabs(ss.height - size.height) < 2.0 &&
            sub.layer.cornerRadius > 0.5 && fabs(sub.layer.cornerRadius - r) > 0.5) {
            sub.layer.cornerRadius = r;
            sub.layer.cornerCurve = kCACornerCurveContinuous;
        }
        CC26SquareCornersWalk(sub, size, r, depth + 1);
    }
    for (CALayer *l in v.layer.sublayers) {
        CGSize ls = l.bounds.size;
        if (fabs(ls.width - size.width) < 2.0 && fabs(ls.height - size.height) < 2.0 &&
            l.cornerRadius > 0.5 && fabs(l.cornerRadius - r) > 0.5) {
            l.cornerRadius = r;
            l.cornerCurve = kCACornerCurveContinuous;
        }
    }
}

// any layer of the module that covers (almost) the whole module and is rounder than wanted,
// at any depth: this is what catches the music module, whose clip lives deeper than the others
static void CC26SquareLayerTree(CALayer *layer, CGSize size, CGFloat r, int depth) {
    if (depth > 9) return;
    for (CALayer *l in layer.sublayers) {
        CGSize ls = l.bounds.size;
        if (ls.width >= size.width * 0.85 && ls.height >= size.height * 0.85 &&
            ls.width <= size.width * 1.1 && ls.height <= size.height * 1.1 &&
            l.cornerRadius > r + 0.5) {
            l.cornerRadius = r;
            l.cornerCurve = kCACornerCurveContinuous;
        }
        CC26SquareLayerTree(l, size, r, depth + 1);
    }
}

void CC26SquareCornersForContainer(UIView *v) {
    if (!v || gCCAModuleExpanded) return;
    CGSize sz = v.bounds.size;
    CGFloat m = MIN(sz.width, sz.height);
    if (m < 130.0 || m > 200.0 || fabs(sz.width - sz.height) >= 14.0) return;
    CGFloat r = floor(m * 0.19);
    CC26SquareCornersWalk(v, sz, r, 0);
    CC26SquareLayerTree(v.layer, sz, r, 0);
    if (v.layer.cornerRadius > 0.5 && fabs(v.layer.cornerRadius - r) > 0.5) v.layer.cornerRadius = r;
}

// iOS 26 modules are "semi square" (radius about 20% of the side), the stock ones are rounder
static void CC26SquareCorners(UIView *collection) {
    if (gCCAModuleExpanded) return;
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:collection];
    int guard = 0;
    while (queue.count && guard++ < 400) {
        UIView *v = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if ([NSStringFromClass(v.class) isEqualToString:@"CCUIContentModuleContainerView"]) {
            CC26SquareCornersForContainer(v);
            continue;
        }
        [queue addObjectsFromArray:v.subviews];
    }
}

@interface CCUIContentModuleContainerView : UIView @end

// square the module on its very first layout / when it enters the window, before it is drawn
%hook CCUIContentModuleContainerView
- (void)layoutSubviews {
    %orig;
    CC26SquareCornersForContainer((UIView *)self);
    if (gCCAModuleExpanded) CC26StripExpandedBackground((UIView *)self);
}
- (void)didMoveToWindow {
    %orig;
    CC26SquareCornersForContainer((UIView *)self);
}
%end

// ===== CONTROL CENTER SIZE (same mechanism and ratios as CCAster) =====
// CCUILayoutOptions holds the real module cell size and the gap between modules; both are scaled
// from whatever the device natively uses, so button iPhones (small screen) and gesture iPhones
// each get their own proportional result. Lower numbers = smaller Control Center.
static CGFloat const kCC26CellScale = 67.0 / 69.0;   // CCAster: 0.971 (module size)
static CGFloat const kCC26GapScale  = 12.0 / 15.0;   // CCAster: 0.80  (space between modules)

static void CC26ApplyCompactGrid(id layoutOptions) {
    if (!gEnabled || !layoutOptions) return;
    Ivar spacingIvar = class_getInstanceVariable([layoutOptions class], "_itemSpacing");
    Ivar edgeIvar = class_getInstanceVariable([layoutOptions class], "_itemEdgeSize");
    if (!spacingIvar || !edgeIvar) return;
    uint8_t *bytes = (uint8_t *)(__bridge void *)layoutOptions;
    CGFloat nativeGap = *((CGFloat *)(bytes + ivar_getOffset(spacingIvar)));
    CGFloat nativeCell = *((CGFloat *)(bytes + ivar_getOffset(edgeIvar)));
    BOOL alreadyPatched = fabs(nativeCell - gCC26GridCell) < 0.5 && fabs(nativeGap - gCC26GridGap) < 0.5;
    if (!alreadyPatched) {
        if (nativeCell > 1.0) gCC26GridCell = round(nativeCell * kCC26CellScale);
        if (nativeGap > 1.0) gCC26GridGap = round(nativeGap * kCC26GapScale);
    }
    *((CGFloat *)(bytes + ivar_getOffset(spacingIvar))) = gCC26GridGap;
    *((CGFloat *)(bytes + ivar_getOffset(edgeIvar))) = gCC26GridCell;
}
// Centers the module grid horizontally ON THE SCREEN (the stock layout leaves it glued to the left when the
// cells are smaller). It is measured in screen coordinates and re-applied after every layout pass
// (collection view, collection VC and overlay), because CCUI re-lays the modules out in several places.
static void CC26CenterModules(UIView *collection) {
    if (!collection || !collection.window) return;
    NSMutableArray<UIView *> *mods = [NSMutableArray array];
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:collection];
    int guard = 0;
    while (queue.count && guard++ < 300) {
        UIView *v = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if ([NSStringFromClass(v.class) isEqualToString:@"CCUIContentModuleContainerView"]) { [mods addObject:v]; continue; }
        [queue addObjectsFromArray:v.subviews];
    }
    if (mods.count < 2) return;
    CGFloat minX = CGFLOAT_MAX, maxX = -CGFLOAT_MAX;
    for (UIView *m in mods) {
        CGRect r = [m convertRect:m.bounds toView:nil];
        if (CGRectGetWidth(r) < 20.0) continue;
        minX = MIN(minX, CGRectGetMinX(r));
        maxX = MAX(maxX, CGRectGetMaxX(r));
    }
    if (minX > maxX) return;
    CGFloat dx = round((CGRectGetWidth(UIScreen.mainScreen.bounds) - (minX + maxX)) * 0.5);
    if (fabs(dx) < 1.0 || fabs(dx) > 60.0) return;
    for (UIView *m in mods) m.center = CGPointMake(m.center.x + dx, m.center.y);
}

%hook CCUIModuleCollectionView
- (instancetype)initWithFrame:(CGRect)frame layoutOptions:(id)layoutOptions {
    CC26ApplyCompactGrid(layoutOptions);
    id result = %orig;
    @try { CC26ApplyCompactGrid([(id)result valueForKey:@"layoutOptions"]); } @catch (__unused NSException *e) {}
    return result;
}
- (void)didMoveToWindow {
    %orig;
    if (!gEnabled) return;
    if (self.window) {
        [CC26.shared installMediaPlayerOnCollectionView:(UIScrollView *)self];
        [CC26.shared installConnectivityPageOnCollectionView:(UIScrollView *)self];
    }
}

- (void)layoutSubviews {
    static void *kCC26InLayoutKey = &kCC26InLayoutKey;

    if (objc_getAssociatedObject(self, kCC26InLayoutKey)) {
        %orig;
        return;
    }

    objc_setAssociatedObject(self, kCC26InLayoutKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    %orig;
    if (!gEnabled) {
        objc_setAssociatedObject(self, kCC26InLayoutKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }

    UIScrollView *scroll = (UIScrollView *)(id)self;

    // CC26CenterModules and CC26SquareCorners each walk the whole module tree; layoutSubviews
    // can fire many times a second while dragging/paging, so during a burst of identical-size
    // passes the two sweeps are capped at ~30/s instead of running on every single one. Any
    // real change (size, or a module appearing/disappearing) still runs them immediately, and
    // the per-module hooks (flashlight toggling, the music card, ...) square their own corner
    // right away regardless, so this only skips redundant repeats of the same full sweep.
    static CGRect sCC26LastSweepBounds;
    static CFTimeInterval sCC26LastSweepTime;
    CGRect bounds = self.bounds;
    CFTimeInterval now = CACurrentMediaTime();
    BOOL dueForSweep = !CGRectEqualToRect(bounds, sCC26LastSweepBounds) || (now - sCC26LastSweepTime) > (1.0 / 30.0);
    if (dueForSweep) {
        sCC26LastSweepBounds = bounds;
        sCC26LastSweepTime = now;
        CC26CenterModules(self);
        CC26SquareCorners(self);
    }
    [CC26.shared layoutMediaPlayerForCollectionView:scroll];
    [CC26.shared layoutConnectivityPageForCollectionView:scroll];

    if (fabs(scroll.contentOffset.x) > 0.25 || fabs(scroll.contentOffset.y) > 0.25) {
        [scroll setContentOffset:CGPointZero animated:NO];
    }

    BOOL notched = (CGRectGetHeight(UIScreen.mainScreen.bounds) >= 800.0);
    if (!notched && !gPagerScrubbing) {
        CGFloat span = PageSpan();
        if (span > 0.0) {
            CATransform3D t = self.layer.sublayerTransform;
            CGFloat expected = -(CGFloat)gCurrentPage * span;
            if (fabs(t.m42 - expected) > 0.5) {
                t.m41 = 0.0;
                t.m42 = expected;
                t.m43 = 0.0;
                self.layer.sublayerTransform = t;
            }
        }
    }

    objc_setAssociatedObject(self, kCC26InLayoutKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
%end

@interface CCUIConnectivityModuleViewController : UIViewController @end

// Long press: make the expanded connectivity module tall enough for the Connectivity page layout.
%hook CCUIConnectivityModuleViewController
- (CGFloat)preferredExpandedContentHeight {
    CGFloat original = %orig;
    if (!gEnabled) return original;
    UIViewController *controller = (UIViewController *)(id)self;
    CGRect grid = CC26VisibleModuleBounds(CC26OverlayForView(controller.view));
    CGSize screen = UIScreen.mainScreen.bounds.size;
    (void)grid;
    CGFloat width = floor(screen.width * 0.80) + 24.0;   // iOS 26: tiles are ~80% of the screen wide
    CGFloat wanted = CC26ConnectivityExpandedHeightForWidth(width);
    return MAX(original, MIN(wanted, floor(screen.height * 0.86)));
}
%end

%hook CCUIModularControlCenterOverlayViewController
- (void)moduleCollectionViewController:(id)collection willOpenExpandedModule:(id)module {
    gCCAModuleExpanded = YES;
    UIViewController *overlay = (UIViewController *)(id)self;
    UIView *indicator = [overlay.view viewWithTag:kPageIndicatorTag];
    [UIView animateWithDuration:0.2 animations:^{
        indicator.alpha = 0.0;
    } completion:^(BOOL finished) {
        indicator.hidden = YES;
    }];
    %orig;
    (void)collection; (void)module;
}

- (void)moduleCollectionViewController:(id)collection didCloseExpandedModule:(id)module {
    %orig;
    gCCAModuleExpanded = NO;
    UIViewController *overlay = (UIViewController *)(id)self;
    CC26DismissEmbeddedConnectivity(overlay);
    dispatch_async(dispatch_get_main_queue(), ^{
        [CC26.shared layoutPageIndicatorForOverlay:overlay];
        [CC26.shared installPageIndicatorOnOverlay:overlay];
        UIView *indicator = [overlay.view viewWithTag:kPageIndicatorTag];
        indicator.hidden = NO;
        indicator.alpha = 0.0;
        indicator.transform = CGAffineTransformIdentity;
        [UIView animateWithDuration:0.35 delay:0.05 options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction animations:^{
            indicator.alpha = 1.0;
        } completion:nil];
    });
    (void)collection; (void)module;
}

- (void)setPresentationState:(NSInteger)state {
    %orig;
    UIViewController *overlay = (UIViewController *)(id)self;
    if (!overlay.view) return;

    static void *kLastPresentationStateKey = &kLastPresentationStateKey;
    NSNumber *lastState = objc_getAssociatedObject(overlay, kLastPresentationStateKey);
    BOOL stateChanged = !lastState || lastState.integerValue != state;
    objc_setAssociatedObject(overlay, kLastPresentationStateKey, @(state), OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    BOOL notched = (CGRectGetHeight(UIScreen.mainScreen.bounds) >= 800.0);
    CCAMediaPlayerView *player = (CCAMediaPlayerView *)[overlay.view viewWithTag:kMediaPlayerTag];

    UIView *connectivityPage = [ModuleCollection(overlay).view viewWithTag:kConnectivityPageTag];
    if (state == 1) {
        if (connectivityPage) { [connectivityPage.layer removeAnimationForKey:@"cc26PageFade"]; connectivityPage.hidden = NO; connectivityPage.alpha = 1.0; }
        if (!notched) {
            UIViewController *collection = ModuleCollection(overlay);
            if (collection && collection.view) {
                CGFloat span = PageSpan();
                if (span > 0.0) {
                    CATransform3D t = collection.view.layer.sublayerTransform;
                    t.m41 = 0.0;
                    t.m42 = -(CGFloat)gCurrentPage * span;
                    t.m43 = 0.0;
                    collection.view.layer.sublayerTransform = t;
                }
            }
        }

        [CC26.shared updateQuickAccessButtonsForOverlay:overlay];
        [CC26.shared installPageIndicatorOnOverlay:overlay];
        [CC26.shared animateElementsInForOverlay:overlay];
        [CC26.shared adjustStatusBarForOverlay:overlay];
        [CC26.shared syncModuleVisibilityForOverlay:overlay];
        [CC26.shared applyHeaderMaterialHidden:(gCurrentPage == CC26MediaPageIndex()) forOverlay:overlay];

        // stretch-and-bounce on open: modules arrive from the edge the Control Center comes from
        if (stateChanged) {
            dispatch_async(dispatch_get_main_queue(), ^{ CC26PlayOpenStretch(overlay); });
        }

        if (player && stateChanged) {
            [player resetForPresentation];
            if (notched && gCurrentPage == CC26MediaPageIndex()) [player fadeIn];
        }
    } else if (state == 3) {
        [CC26.shared animateElementsOutForOverlay:overlay];
        // leaving from another page must not flash the connectivity page while everything slides
        // back, and leaving from the connectivity page must not leave it hanging over the
        // home screen: hide it right away / fade it with the dismissal
        if (connectivityPage) {
            if (gCurrentPage != CC26ConnectivityPageIndex()) {
                connectivityPage.alpha = 0.0;
            } else {
                [UIView animateWithDuration:0.18 delay:0.0 options:UIViewAnimationOptionCurveEaseIn | UIViewAnimationOptionBeginFromCurrentState
                                 animations:^{ connectivityPage.alpha = 0.0; } completion:nil];
            }
        }

        if (player && stateChanged && gCurrentPage == CC26MediaPageIndex() && notched) {
            [player fadeOut];
        }

        NSInteger savedPage = gCurrentPage;
        gCurrentPage = 0;
        [CC26.shared adjustStatusBarForOverlay:overlay];
        gCurrentPage = savedPage;
    }
}

- (void)viewDidLayoutSubviews {
    static void *kCC26InOverlayLayoutKey = &kCC26InOverlayLayoutKey;
    if (objc_getAssociatedObject(self, kCC26InOverlayLayoutKey)) {
        %orig;
        return;
    }
    objc_setAssociatedObject(self, kCC26InOverlayLayoutKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    %orig;
    if (gEnabled) {
        UIViewController *overlay = (UIViewController *)(id)self;
        [CC26.shared layoutPageIndicatorForOverlay:overlay];
        [CC26.shared adjustStatusBarForOverlay:overlay];
        CC26CenterModules(ModuleCollection(overlay).view);
        dispatch_async(dispatch_get_main_queue(), ^{ CC26CenterModules(ModuleCollection(overlay).view); });
    }

    objc_setAssociatedObject(self, kCC26InOverlayLayoutKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
%end

%hook MRUNowPlayingView
- (void)layoutSubviews {
    %orig;
    if (!gEnabled) return;
    CC26ConfigureMedia((UIView *)(id)self);
    CC26EmbedExpandedMediaIfNeeded((UIView *)(id)self);
    // the music module re-writes its own radius on layout: square it again right after
    UIView *moduleContainer = CC26Ancestor((UIView *)(id)self, @"CCUIContentModuleContainerView");
    CC26SquareCornersForContainer(moduleContainer);
    dispatch_async(dispatch_get_main_queue(), ^{ CC26SquareCornersForContainer(moduleContainer); });
}
%end

%hook MRUArtworkView
- (void)layoutSubviews {
    %orig;
    if (!gEnabled) return;
    UIView *view = (UIView *)(id)self;
    if (!CC26MediaMode(view)) return;
    CGFloat radius = view.layer.cornerRadius;
    for (UIView *child in view.subviews) {
        if (fabs(CGRectGetWidth(child.bounds) - CGRectGetWidth(view.bounds)) > 1.0 ||
            fabs(CGRectGetHeight(child.bounds) - CGRectGetHeight(view.bounds)) > 1.0) continue;
        child.layer.cornerRadius = radius;
        child.layer.cornerCurve = kCACornerCurveContinuous;
        child.layer.masksToBounds = YES;
    }
    UIView *backing = view.subviews.firstObject;
    NSArray *filters = CC26MediaMaterialFilters(view);
    if (backing && filters.count) { backing.backgroundColor = UIColor.whiteColor; backing.layer.filters = filters; }
}
%end

%hook MRUNowPlayingHeaderView
- (void)layoutSubviews {
    %orig;
    if (!gEnabled) return;
    UIView *view = (UIView *)(id)self;
    NSString *mode = CC26MediaMode(view);
    if (!mode) return;

    UIView *routing = CC26ViewIvar(self, "_routingButton");
    UIView *label = CC26ViewIvar(self, "_labelView");
    UIView *headerTransport = CC26ViewIvar(self, "_transportButton");

    CGFloat width = CGRectGetWidth(view.bounds);
    CGFloat side = 40.0;

    UIView *nowPlaying = CC26Ancestor(view, @"MRUNowPlayingView");
    UIView *artwork = CC26ViewIvar(nowPlaying, "_artworkView");
    UIView *transport = CC26ViewIvar(nowPlaying, "_transportControlsView");

    NSArray *filters = CC26MediaMaterialFilters(view);
    CGFloat labelHeight = 34.0;
    CGFloat labelY = (artwork && transport ? (CGRectGetMaxY(artwork.frame) + CGRectGetMinY(transport.frame) - labelHeight) * 0.5 : 64.0) + 6.5;

    CGRect routingFrame = CGRectMake(width - 54, 14, side, side);
    CGRect labelFrame = CGRectMake(14, labelY, width - 28, labelHeight);

    [UIView performWithoutAnimation:^{
        if (headerTransport) headerTransport.hidden = YES;

        if (routing) {
            routing.frame = routingFrame;
            routing.hidden = NO;
            routing.alpha = 1;
            routing.backgroundColor = UIColor.clearColor;
            routing.tintColor = UIColor.whiteColor;
            routing.layer.filters = nil;
            routing.layer.cornerRadius = side / 2;
            routing.layer.masksToBounds = YES;

            UIView *material = [routing viewWithTag:CC26TagMediaButtonMaterial];
            if (!material) {
                material = [UIView new];
                material.tag = CC26TagMediaButtonMaterial;
                material.userInteractionEnabled = NO;
                [routing insertSubview:material atIndex:0];
            }
            material.frame = routing.bounds;
            if (filters.count) {
                material.backgroundColor = UIColor.whiteColor;
                material.layer.filters = filters;
            } else {
                material.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.16];
                material.layer.filters = nil;
            }
            material.layer.cornerRadius = side / 2;
            material.layer.masksToBounds = YES;

            CC26ResizeMediaRoutingGlyph(routing);
        }

        if (label) {
            label.frame = labelFrame;
            label.hidden = NO;
            label.alpha = 1;
        }
    }];
}
%end

%hook MRUNowPlayingLabelView
- (void)layoutSubviews {
    %orig;
    if (!gEnabled) return;

    UIView *view = (UIView *)self;
    if (!CC26MediaMode(view)) return;

    UIView *title       = CC26ViewIvar(self, "_titleMarqueeView")       ?: CC26ViewIvar(self, "_titleLabel");
    UIView *subtitle    = CC26ViewIvar(self, "_subtitleMarqueeView")    ?: CC26ViewIvar(self, "_subtitleLabel");
    UIView *placeholder = CC26ViewIvar(self, "_placeholderMarqueeView");
    NSArray *filters    = CC26MediaMaterialFilters(view);

    view.layer.filters = nil;
    CC26ViewIvar(self, "_routeLabel").hidden = YES;

    if ([self respondsToSelector:@selector(setTextAlignment:)]) {
        ((void (*)(id, SEL, NSInteger))objc_msgSend)(self, @selector(setTextAlignment:), NSTextAlignmentLeft);
    }

    for (UIView *line in @[title ?: (id)NSNull.null,
                           subtitle ?: (id)NSNull.null,
                           placeholder ?: (id)NSNull.null]) {
        if ((id)line == NSNull.null) continue;
        if ([line respondsToSelector:@selector(setTextAlignment:)]) {
            ((void (*)(id, SEL, NSInteger))objc_msgSend)(line, @selector(setTextAlignment:), NSTextAlignmentLeft);
        }
        NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:line];
        while (queue.count) {
            UIView *child = queue.firstObject;
            [queue removeObjectAtIndex:0];
            if ([child isKindOfClass:UILabel.class] && filters.count) {
                ((UILabel *)child).textColor = UIColor.whiteColor;
                child.layer.filters = filters;
            }
            [queue addObjectsFromArray:child.subviews];
        }
    }

    if (placeholder && !placeholder.hidden) {
        CGFloat height = CGRectGetHeight(placeholder.bounds);
        placeholder.frame = CGRectMake(0.0,
                                       floor((CGRectGetHeight(view.bounds) - height) * 0.5),
                                       CGRectGetWidth(view.bounds),
                                       height);
    }

    if (!title || !subtitle) return;

    CGFloat width = CGRectGetWidth(view.bounds);
    CGFloat start = MAX(0, (CGRectGetHeight(view.bounds) - 31) / 2);

    title.frame    = CGRectMake(0, start,      width, 16);
    subtitle.frame = CGRectMake(0, start + 17, width, 14);

    for (UIView *line in @[title, subtitle]) {
        line.alpha = 1;
        NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithArray:line.subviews];
        while (queue.count) {
            UIView *child = queue.firstObject;
            [queue removeObjectAtIndex:0];
            if ([child isKindOfClass:UILabel.class]) {
                ((UILabel *)child).font = [UIFont systemFontOfSize:13
                                                          weight:(line == title
                                                                  ? UIFontWeightSemibold
                                                                  : UIFontWeightRegular)];
                ((UILabel *)child).textAlignment = NSTextAlignmentLeft;
            }
            [queue addObjectsFromArray:child.subviews];
        }
    }
}
%end

%hook MRUTransportButton
- (void)layoutSubviews {
    %orig;
    if (!gEnabled) return;
    CC26ResizeMediaRoutingGlyph((UIView *)(id)self);
}
%end

%hook MRUNowPlayingTransportControlsView
- (void)layoutSubviews {
    %orig;
    if (!gEnabled) return;
    UIView *view = (UIView *)(id)self;
    NSString *mode = CC26MediaMode(view);
    if (!mode) return;

    UIView *left = CC26ViewIvar(self, "_leftButton");
    UIView *center = CC26ViewIvar(self, "_centerButton");
    UIView *right = CC26ViewIvar(self, "_rightButton");

    if (!left || !center || !right) return;

    CGFloat width = CGRectGetWidth(view.bounds);
    CGFloat y = CGRectGetHeight(view.bounds) / 2;
    CGFloat spacing = width * 0.32;

    left.hidden = NO;
    center.center = CGPointMake(width / 2, y);
    left.center = CGPointMake(width / 2 - spacing, y);
    right.center = CGPointMake(width / 2 + spacing, y);

    CC26ViewIvar(self, "_leadingButton").hidden = YES;
    CC26ViewIvar(self, "_routingButton").hidden = YES;
}
%end

%hook UIViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (!CC26IsControlCenterClass(self)) return;
    if (gEnabled && [NSStringFromClass(self.class) containsString:@"ControlCenterOverlayViewController"]) {
        [CC26.shared installOnOverlay:(UIViewController *)self];
    }
}
- (void)viewDidLayoutSubviews {
    if (!CC26IsControlCenterClass(self)) {
        %orig;
        return;
    }
    static void *kCC26InVCLayoutKey = &kCC26InVCLayoutKey;
    if (objc_getAssociatedObject(self, kCC26InVCLayoutKey)) {
        %orig;
        return;
    }
    objc_setAssociatedObject(self, kCC26InVCLayoutKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    %orig;
    if (gEnabled && [NSStringFromClass(self.class) containsString:@"ControlCenterOverlayViewController"]) {
        [CC26.shared updateQuickAccessButtonsForOverlay:(UIViewController *)self];
        [CC26.shared layoutPageIndicatorForOverlay:(UIViewController *)self];
    }
    if (gEnabled && [NSStringFromClass(self.class) isEqualToString:@"CCUIModuleCollectionViewController"]) {
        CC26CenterModules(self.view);
    }
    if ([NSStringFromClass(self.class) isEqualToString:@"CCUIConnectivityModuleViewController"]) {
        CC26ConfigureConnectivity((UIViewController *)(id)self);
    }

    objc_setAssociatedObject(self, kCC26InVCLayoutKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
%end

%hook CCUISliderModuleViewController
- (void)viewDidLayoutSubviews {
    %orig;
    if (!gEnabled) return;

    UIViewController *vc = (UIViewController *)self;
    NSString *className = NSStringFromClass(vc.class);
    UIColor *tintColor = nil;

    if ([className containsString:@"Brightness"]) {
        tintColor = [UIColor colorWithRed:1.0 green:0.85 blue:0.0 alpha:1.0];
    } else if ([className containsString:@"Volume"]) {
        tintColor = [UIColor colorWithRed:0.0 green:0.8 blue:1.0 alpha:1.0];
    }

    if (tintColor) {
        for (UIView *sub in vc.view.subviews) {
            if ([sub isKindOfClass:[UISlider class]]) {
                UISlider *slider = (UISlider *)sub;
                slider.tintColor = tintColor;
                slider.minimumTrackTintColor = tintColor;
            }
            if ([NSStringFromClass(sub.class) containsString:@"Slider"]) {
                sub.tintColor = tintColor;
                for (UIView *child in sub.subviews) {
                    child.tintColor = tintColor;
                }
            }
        }
    }
}
%end

static void PrefsChanged(__unused CFNotificationCenterRef center, __unused void *observer, __unused CFStringRef name, __unused const void *object, __unused CFDictionaryRef userInfo) {
    LoadPrefs();
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *overlay = OverlayIn(UIApplication.sharedApplication.keyWindow.rootViewController);
        if (overlay) [CC26.shared installOnOverlay:overlay];
    });
}

%ctor {
    @autoreleasepool {
        LoadPrefs();
        %init(_ungrouped);
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, PrefsChanged,
                                        (__bridge CFStringRef)kReloadNotification, NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
    }
}