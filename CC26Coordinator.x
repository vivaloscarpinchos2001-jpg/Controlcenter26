#import "CC26.h"

@implementation CCAQuickAccessHost
- (BOOL)respondsToSelector:(SEL)aSelector {
    if ([super respondsToSelector:aSelector]) return YES;
    return NO;
}
- (id)forwardingTargetForSelector:(SEL)aSelector { return nil; }
- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector {
    NSMethodSignature *sig = [super methodSignatureForSelector:aSelector];
    if (!sig) sig = [NSMethodSignature signatureWithObjCTypes:"v@:"];
    return sig;
}
- (void)forwardInvocation:(NSInvocation *)anInvocation { }

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (self.hidden || self.alpha <= 0.05 || !self.userInteractionEnabled) return nil;
    for (UIView *sub in self.subviews.reverseObjectEnumerator) {
        if (sub.hidden || sub.alpha <= 0.05 || !sub.userInteractionEnabled) continue;
        CGPoint p = [self convertPoint:point toView:sub];
        UIView *hit = [sub hitTest:p withEvent:event];
        if (hit) return hit;
    }
    return nil;
}
@end


@implementation CC26

+ (instancetype)shared {
    static CC26 *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [self new]; });
    return shared;
}

- (CGFloat)topInsetForOverlay:(UIViewController *)overlay {
    CGFloat safeTop = overlay.view.window.safeAreaInsets.top;
    if (safeTop < 1.0) safeTop = overlay.view.safeAreaInsets.top;
    return MAX(8.0, safeTop - 6.0);
}

- (UIButton *)makeRoundButtonWithSymbol:(NSString *)symbolName tag:(NSInteger)tag {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.tag = tag;
    button.tintColor = UIColor.whiteColor;
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightMedium];
    UIImage *image = [UIImage systemImageNamed:symbolName withConfiguration:config];
    [button setImage:image forState:UIControlStateNormal];
    button.imageView.contentMode = UIViewContentModeCenter;
    return button;
}

- (void)installOnOverlay:(UIViewController *)overlay {
    if (!gEnabled || !overlay.view) return;
    [self updateQuickAccessButtonsForOverlay:overlay];
    [self installPageIndicatorOnOverlay:overlay];
    [self syncModuleVisibilityForOverlay:overlay];
    [self applyHeaderMaterialHidden:(gCurrentPage == CC26MediaPageIndex()) forOverlay:overlay];
    [self adjustStatusBarForOverlay:overlay];

    UIViewController *collection = ModuleCollection(overlay);
    if ([collection.view isKindOfClass:UIScrollView.class]) {
        [self installConnectivityPageOnCollectionView:(UIScrollView *)collection.view];
    }
}

- (void)syncModuleVisibilityForOverlay:(UIViewController *)overlay {
    [self syncModuleVisibilityForOverlay:overlay animated:NO];
}

- (void)syncModuleVisibilityForOverlay:(UIViewController *)overlay animated:(BOOL)animated {
    BOOL notched = (CGRectGetHeight(UIScreen.mainScreen.bounds) >= 800.0);
    if (notched) return;

    UIViewController *collection = ModuleCollection(overlay);
    if (!collection.view) return;

    BOOL hide = (gCurrentPage != 0);
    CGFloat targetAlpha = hide ? 0.0 : 1.0;

    NSMutableArray<UIView *> *targets = [NSMutableArray array];
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:collection.view];
    while (queue.count) {
        UIView *v = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if ([NSStringFromClass(v.class) isEqualToString:@"CCUIContentModuleContainerView"]) {
            [targets addObject:v];
        }
        [queue addObjectsFromArray:v.subviews];
    }

    if (animated && targets.count) {
        [UIView animateWithDuration:0.35 delay:0.0
                            options:UIViewAnimationOptionCurveEaseInOut |
                                    UIViewAnimationOptionBeginFromCurrentState |
                                    UIViewAnimationOptionAllowUserInteraction
                         animations:^{
            for (UIView *v in targets) v.alpha = targetAlpha;
        } completion:nil];
    } else {
        for (UIView *v in targets) v.alpha = targetAlpha;
    }
}

- (void)restoreModuleVisibilityForOverlay:(UIViewController *)overlay {
    BOOL notched = (CGRectGetHeight(UIScreen.mainScreen.bounds) >= 800.0);
    if (notched) return;

    UIViewController *collection = ModuleCollection(overlay);
    if (!collection.view) return;

    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:collection.view];
    while (queue.count) {
        UIView *v = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if ([NSStringFromClass(v.class) isEqualToString:@"CCUIContentModuleContainerView"]) {
            v.alpha = 1.0;
        }
        [queue addObjectsFromArray:v.subviews];
    }
}

- (void)applyHeaderMaterialHidden:(BOOL)hidden forOverlay:(UIViewController *)overlay {
    BOOL notched = (CGRectGetHeight(UIScreen.mainScreen.bounds) >= 800.0);
    if (notched) return;
    if (!overlay.view) return;

    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:overlay.view];
    while (queue.count) {
        UIView *v = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if ([NSStringFromClass(v.class) isEqualToString:@"CCUIHeaderPocketView"]) {
            for (UIView *child in v.subviews) {
                if ([NSStringFromClass(child.class) isEqualToString:@"MTMaterialView"]) {
                    child.hidden = hidden;
                }
            }
        }
        [queue addObjectsFromArray:v.subviews];
    }
}

- (void)adjustStatusBarForOverlay:(UIViewController *)overlay {
    BOOL notched = (CGRectGetHeight(UIScreen.mainScreen.bounds) >= 800.0);
    if (notched) return;
    if (!overlay || !overlay.view) return;

    UIWindow *window = overlay.view.window;
    if (!window) return;
    if (window.hidden || window.alpha < 0.01) return;

    UIView *statusBar = nil;
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:window];
    while (queue.count) {
        UIView *v = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if ([NSStringFromClass(v.class) isEqualToString:@"UIStatusBar_Modern"]) {
            statusBar = v;
            break;
        }
        [queue addObjectsFromArray:v.subviews];
    }
    if (!statusBar) return;

    static void *kStatusBarBaseTransformKey = &kStatusBarBaseTransformKey;
    NSValue *storedBase = objc_getAssociatedObject(statusBar, kStatusBarBaseTransformKey);
    if (!storedBase) {
        if (!CGAffineTransformIsIdentity(statusBar.transform)) return;
        objc_setAssociatedObject(statusBar, kStatusBarBaseTransformKey,
                                 [NSValue valueWithCGAffineTransform:statusBar.transform],
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        storedBase = objc_getAssociatedObject(statusBar, kStatusBarBaseTransformKey);
    }
    CGAffineTransform base = storedBase.CGAffineTransformValue;

    CGFloat dy = (gCurrentPage == CC26MediaPageIndex()) ? -25.0 : 0.0;
    CGAffineTransform target = CGAffineTransformTranslate(base, 0, dy);

    if (CGAffineTransformEqualToTransform(statusBar.transform, target)) return;

    statusBar.layer.transform = CATransform3DMakeAffineTransform(target);
}

- (void)animateElementsInForOverlay:(UIViewController *)overlay {
    UIView *host = [overlay.view viewWithTag:kQuickAccessTag];
    UIView *indicator = [overlay.view viewWithTag:kPageIndicatorTag];

    if (host) {
        host.alpha = 0.0;
        host.transform = CGAffineTransformMakeScale(0.6, 0.6);
        [UIView animateWithDuration:0.45 delay:0.0 usingSpringWithDamping:CC26SpringDamping(0.7) initialSpringVelocity:CC26SpringVelocity(0.5) options:UIViewAnimationOptionCurveEaseOut animations:^{
            host.alpha = 1.0;
            host.transform = CGAffineTransformIdentity;
        } completion:nil];
    }
    if (indicator) {
        indicator.hidden = NO;
        indicator.alpha = 0.0;
        indicator.transform = CGAffineTransformIdentity;
        [UIView animateWithDuration:0.35 delay:0.05 options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction animations:^{
            indicator.alpha = 1.0;
        } completion:nil];
    }
}

- (void)animateElementsOutForOverlay:(UIViewController *)overlay {
    UIView *host = [overlay.view viewWithTag:kQuickAccessTag];
    UIView *indicator = [overlay.view viewWithTag:kPageIndicatorTag];

    [UIView animateWithDuration:0.2 animations:^{
        if (host) {
            host.alpha = 0.0;
            host.transform = CGAffineTransformMakeScale(0.6, 0.6);
        }
        if (indicator) {
            indicator.alpha = 0.0;
        }
    } completion:^(BOOL finished) {
        if (indicator) {
            indicator.hidden = YES;
            indicator.alpha = 1.0;
        }
    }];
}

- (void)updateQuickAccessButtonsForOverlay:(UIViewController *)overlay {
    UIView *host = [overlay.view viewWithTag:kQuickAccessTag];
    if (!host) {
        host = [[CCAQuickAccessHost alloc] initWithFrame:CGRectZero];
        host.tag = kQuickAccessTag;
        host.backgroundColor = UIColor.clearColor;
        host.userInteractionEnabled = YES;
        [overlay.view addSubview:host];
    }
    CGFloat top = [self topInsetForOverlay:overlay];
    host.frame = CGRectMake(0, top, CGRectGetWidth(overlay.view.bounds), 44);
    host.hidden = !gQuickAccessButtonsEnabled;

    UIButton *plus = [host viewWithTag:181001];
    if (!plus) {
        plus = [self makeRoundButtonWithSymbol:@"plus" tag:181001];
        [plus addTarget:self action:@selector(addPressed:) forControlEvents:UIControlEventTouchUpInside];
        [host addSubview:plus];
    }
    UIButton *power = [host viewWithTag:181002];
    if (!power) {
        power = [self makeRoundButtonWithSymbol:@"power" tag:181002];
        UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(powerPressed:)];
        hold.minimumPressDuration = 0.6;
        [power addGestureRecognizer:hold];
        [host addSubview:power];
    }
    CGFloat btnSize = 36;
    CGFloat margin = 22;
    plus.frame = CGRectMake(margin, (CGRectGetHeight(host.bounds) - btnSize) / 2, btnSize, btnSize);
    power.frame = CGRectMake(CGRectGetWidth(host.bounds) - margin - btnSize, (CGRectGetHeight(host.bounds) - btnSize) / 2, btnSize, btnSize);
    [overlay.view bringSubviewToFront:host];
}

- (void)addPressed:(UIButton *)sender {
    if (!gEnabled) return;
    Haptic();
    UIViewController *overlay = OverlayIn(UIApplication.sharedApplication.keyWindow.rootViewController);
    SEL sel = NSSelectorFromString(@"presentAddSheet");
    if (overlay && [overlay respondsToSelector:sel]) {
        ((void (*)(id, SEL))objc_msgSend)(overlay, sel);
    }
}

- (void)powerPressed:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    Haptic();
    Class factoryClass = NSClassFromString(@"SBUIPowerDownViewControllerFactory");
    SEL sel = NSSelectorFromString(@"newPowerDownViewController");
    if (![factoryClass respondsToSelector:sel]) return;
    UIViewController *power = ((id (*)(id, SEL))objc_msgSend)(factoryClass, sel);
    if (!power) return;
    UIViewController *presenter = OverlayIn(UIApplication.sharedApplication.keyWindow.rootViewController);
    if (!presenter || presenter.presentedViewController) return;
    power.modalPresentationStyle = UIModalPresentationFullScreen;
    [presenter presentViewController:power animated:YES completion:nil];
}

- (void)snapToFirstPageForOverlay:(UIViewController *)overlay {
    if (gCurrentPage == 0) return;
    gCurrentPage = 0;

    UIViewController *collection = ModuleCollection(overlay);
    if (!collection.view) return;

    CATransform3D t = collection.view.layer.sublayerTransform;
    t.m41 = 0.0;
    t.m42 = 0.0;
    t.m43 = 0.0;
    collection.view.layer.sublayerTransform = t;

    CCAMediaPlayerView *player = (CCAMediaPlayerView *)[collection.view viewWithTag:kMediaPlayerTag];
    if (player) player.alpha = 0.0;
}

- (void)installPageIndicatorOnOverlay:(UIViewController *)overlay {
    if (!gPagingEnabled) {
        [[overlay.view viewWithTag:kPageIndicatorTag] removeFromSuperview];
        return;
    }

    NSUInteger pageCount = CC26PageCount();
    if ((NSInteger)gCurrentPage >= (NSInteger)pageCount) {
        [self snapToFirstPageForOverlay:overlay];
    }

    CCAPageIndicator *indicator = (CCAPageIndicator *)[overlay.view viewWithTag:kPageIndicatorTag];
    if (!indicator) {
        indicator = [[CCAPageIndicator alloc] initWithFrame:CGRectZero];
        indicator.tag = kPageIndicatorTag;
        [overlay.view addSubview:indicator];
    }
    indicator.pageCount = pageCount;
    indicator.overlay = overlay;
    indicator.hidden = gCCAModuleExpanded;
    indicator.transform = CGAffineTransformIdentity;
    [indicator installSwipeRecognizerOnView:overlay.view];
    [self layoutPageIndicatorForOverlay:overlay];
    [overlay.view bringSubviewToFront:indicator];
}

- (void)layoutPageIndicatorForOverlay:(UIViewController *)overlay {
    CCAPageIndicator *indicator = (CCAPageIndicator *)[overlay.view viewWithTag:kPageIndicatorTag];
    if (!indicator) return;
    if (indicator.scrubbing)
return;
    CGFloat step = 39.0;
    CGFloat width = 42.0;
    CGFloat height = step * MAX((NSUInteger)1, indicator.pageCount);
    CGFloat screenRight = CGRectGetWidth(overlay.view.bounds);

    static void *kPagerRightEdgeKey = &kPagerRightEdgeKey;
    NSNumber *cachedEdge = objc_getAssociatedObject(indicator, kPagerRightEdgeKey);

    CGRect modules = CC26VisibleModuleBounds(overlay);
    CGFloat moduleRight = CGRectIsNull(modules) ? 0.0 : CGRectGetMaxX(modules);

    if ((gCurrentPage == 0 || !cachedEdge) && moduleRight > 0.0) {
        objc_setAssociatedObject(indicator, kPagerRightEdgeKey, @(moduleRight),
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        cachedEdge = @(moduleRight);
    }
    if (cachedEdge) moduleRight = cachedEdge.doubleValue;

    CGFloat centerX = moduleRight > 0.0 ? (moduleRight + screenRight) * 0.5 : screenRight - 21.0;
    indicator.frame = CGRectMake(centerX - width * 0.5,
                                 floor((CGRectGetHeight(overlay.view.bounds) - height) * 0.5),
                                 width, height);

    [indicator layoutButtons];
    [indicator captureCollectionBase];
}

- (void)installMediaPlayerOnCollectionView:(UIScrollView *)collectionView {
    if (!gEnabled || !gPagingEnabled) {
        [[collectionView viewWithTag:kMediaPlayerTag] removeFromSuperview];
        return;
    }
    CCAMediaPlayerView *player = (CCAMediaPlayerView *)[collectionView viewWithTag:kMediaPlayerTag];
    if (!player) {
        player = [[CCAMediaPlayerView alloc] initWithFrame:CGRectZero];
        player.tag = kMediaPlayerTag;
        player.alpha = 0.0;
        [collectionView addSubview:player];
    }
    [self layoutMediaPlayerForCollectionView:collectionView];
}

- (void)layoutMediaPlayerForCollectionView:(UIScrollView *)collectionView {
    CCAMediaPlayerView *player = (CCAMediaPlayerView *)[collectionView viewWithTag:kMediaPlayerTag];
    if (!player) return;

    CGRect screenBounds = [UIScreen mainScreen].bounds;
    CGFloat screenW = CGRectGetWidth(screenBounds);
    CGFloat screenH = CGRectGetHeight(screenBounds);
    CGFloat span = PageSpan();

    BOOL notched = (screenH >= 800.0);

    CGFloat minTop = notched ? 100.0 : 145.0;
    CGFloat bottomMargin = 20.0;
    CGFloat availableH = screenH - minTop - bottomMargin;

    CGFloat cardW = screenW * (notched ? 0.86 : 0.84);
    CGFloat aspect = 1.60;
    CGFloat cardH = cardW * aspect;
    if (cardH > availableH) {
        cardH = availableH;
        cardW = cardH / aspect;
    }

    CGFloat cardTopScreen = (screenH - cardH) * 0.5;
    if (cardTopScreen < minTop) cardTopScreen = minTop;

    CGFloat x = (screenW - cardW) * 0.5;

    CGFloat frameY;
    if (collectionView.window) {
        CGRect probe = CGRectMake(0, cardTopScreen, 0, 0);
        CGFloat localY = [collectionView convertRect:probe fromView:nil].origin.y;
        frameY = localY + span * (CGFloat)CC26MediaPageIndex();
    } else {
        frameY = span * (CGFloat)CC26MediaPageIndex() + cardTopScreen;
    }

    CGRect targetBounds = CGRectMake(0, 0, cardW, cardH);
    CGPoint targetCenter = CGPointMake(x + cardW * 0.5, frameY + cardH * 0.5);
    // same rectangle as the stock modules: top / side distances match the regular page, and the card
    // grows to the height of the grid (never beyond 1.9x its width) so it fits every screen
    CC26UpdateStockGrid(CC26OverlayForView(collectionView));
    CGRect grid = CC26StockGridRect();
    if (!CGRectIsNull(grid) && collectionView.window) {
        // iOS 26 card: same top as the stock modules and same size as the connectivity page
        // (451:808 layout scaled to the stock width, or to the free height on a short screen)
        CGFloat bottomMargin = collectionView.window.safeAreaInsets.bottom + (notched ? 30.0 : 24.0);
        CGFloat gridAvail = MAX(200.0, screenH - grid.origin.y - bottomMargin);
        CGFloat cardScale = MIN(grid.size.width / 451.0, gridAvail / 808.0);
        CGFloat gridCardH = floor(808.0 * cardScale);
        CGFloat gridCardW = floor(451.0 * cardScale);
        CGFloat gridTop = grid.origin.y;
        CGFloat gridLeft = grid.origin.x + floor((grid.size.width - gridCardW) * 0.5);
        CGPoint local = [collectionView convertRect:CGRectMake(gridLeft, gridTop, 0.0, 0.0) fromView:nil].origin;
        targetBounds = CGRectMake(0, 0, gridCardW, gridCardH);
        targetCenter = CGPointMake(local.x + gridCardW * 0.5,
                                   local.y + span * (CGFloat)CC26MediaPageIndex() + gridCardH * 0.5);
    }

    if (!CGRectEqualToRect(player.bounds, targetBounds)) {
        player.bounds = targetBounds;
    }
    if (!CGPointEqualToPoint(player.center, targetCenter)) {
        player.center = targetCenter;
    }
}

- (void)installConnectivityPageOnCollectionView:(UIScrollView *)collectionView {
    @try {
    if (!gEnabled || !gPagingEnabled || !gConnectivityPageEnabled) {
        [[collectionView viewWithTag:kConnectivityPageTag] removeFromSuperview];
        return;
    }
    CCAConnectivityPageView *page = (CCAConnectivityPageView *)[collectionView viewWithTag:kConnectivityPageTag];
    if (!page) {
        page = [[CCAConnectivityPageView alloc] initWithFrame:CGRectZero];
        page.tag = kConnectivityPageTag;
        [collectionView addSubview:page];
    }
    [self layoutConnectivityPageForCollectionView:collectionView];
    } @catch (__unused NSException *e) {}
}

- (void)layoutConnectivityPageForCollectionView:(UIScrollView *)collectionView {
    @try {
    CCAConnectivityPageView *page = (CCAConnectivityPageView *)[collectionView viewWithTag:kConnectivityPageTag];
    if (!page) return;

    if (!gEnabled || !gPagingEnabled || !gConnectivityPageEnabled) {
        [page removeFromSuperview];
        return;
    }

    CGRect screenBounds = UIScreen.mainScreen.bounds;
    CGFloat screenH = CGRectGetHeight(screenBounds);
    CGFloat span = PageSpan();
    BOOL notched = (screenH >= 800.0);

    // usable band: below the status bar (carrier / battery row) and above the bottom edge,
    // computed from the device's own safe area so it fits every resolution
    UIEdgeInsets safe = collectionView.window ? collectionView.window.safeAreaInsets : UIEdgeInsetsZero;
    CGFloat top = MAX(safe.top, 20.0) + (notched ? 56.0 : 66.0);
    CGFloat bottom = MAX(safe.bottom, 0.0) + (notched ? 30.0 : 24.0);
    CGFloat availH = MAX(200.0, screenH - top - bottom);

    CGFloat pageW = CGRectGetWidth(collectionView.bounds);
    if (pageW < 1.0) pageW = CGRectGetWidth(screenBounds);
    page.availableHeight = availH;
    CGFloat pageH = MIN(availH, [page preferredHeightForWidth:pageW]);

    CGFloat screenTop = top + floor((availH - pageH) * 0.5);

    CGFloat frameY;
    if (collectionView.window) {
        CGRect probe = CGRectMake(0.0, screenTop, 0.0, 0.0);
        CGFloat localY = [collectionView convertRect:probe fromView:nil].origin.y;
        frameY = localY + span * (CGFloat)CC26ConnectivityPageIndex();
    } else {
        frameY = span * (CGFloat)CC26ConnectivityPageIndex() + screenTop;
    }

    CGRect targetBounds = CGRectMake(0.0, 0.0, pageW, pageH);
    CGPoint targetCenter = CGPointMake(floor(pageW * 0.5), floor(frameY + pageH * 0.5));
    // fill the exact rectangle of the stock modules (same top / side / bottom distances)
    CC26UpdateStockGrid(CC26OverlayForView(collectionView));
    CGRect grid = CC26StockGridRect();
    BOOL useGrid = !CGRectIsNull(grid) && collectionView.window != nil;
    page.fitsGrid = useGrid;
    if (useGrid) {
        // iOS 26: same top and width as the stock modules, height of the full 451:808 layout
        // (shrunk uniformly when the screen is too short for it)
        CGFloat gridAvail = MAX(200.0, screenH - grid.origin.y - bottom);
        page.availableHeight = gridAvail;
        CGPoint local = [collectionView convertRect:CGRectMake(grid.origin.x, grid.origin.y, 0.0, 0.0) fromView:nil].origin;
        targetBounds = CGRectMake(0.0, 0.0, grid.size.width, gridAvail);
        targetCenter = CGPointMake(floor(local.x + grid.size.width * 0.5),
                                   floor(local.y + span * (CGFloat)CC26ConnectivityPageIndex() + gridAvail * 0.5));
    }
    if (!CGRectEqualToRect(page.bounds, targetBounds)) page.bounds = targetBounds;
    if (!CGPointEqualToPoint(page.center, targetCenter)) page.center = targetCenter;
    } @catch (__unused NSException *e) {}
}

@end
