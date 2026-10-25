#import "CC26.h"

@interface CCAPageIndicator () <UIGestureRecognizerDelegate>
@property (nonatomic, assign) BOOL dragging;
@property (nonatomic, assign) NSUInteger dragStartPage;
@property (nonatomic, assign) NSUInteger interactiveStartPage;
@property (nonatomic, assign) CGFloat interactiveProgress;
@property (nonatomic, assign) CGFloat interactiveTranslation;
@property (nonatomic, assign) CFTimeInterval interactiveBeganTime;
@property (nonatomic, assign) CFTimeInterval lastSampleTime;
@property (nonatomic, assign) CGFloat viscousProgress;
@property (nonatomic, assign) CGFloat previousRawProgress;
@property (nonatomic, assign) CGFloat filteredVelocity;
@property (nonatomic, assign) CGFloat jelloScaleX;
@property (nonatomic, assign) CGFloat jelloScaleY;
@property (nonatomic, assign) CGFloat heldScale;
@property (nonatomic, assign) CGFloat heldAlphaFactor;
@property (nonatomic, weak) UIView *savedCollectionView;
@property (nonatomic, assign) CGRect restHostFrame;
@property (nonatomic, assign) NSUInteger animationToken;
@property (nonatomic, strong) UIPanGestureRecognizer *panRecognizer;
@property (nonatomic, assign) CATransform3D baseCollectionSublayerTransform;
@property (nonatomic, assign) BOOL suspendedForLandscape;
@property (nonatomic, strong) UIPanGestureRecognizer *swipeRecognizer;
@property (nonatomic, weak) UIView *swipeHostView;
@property (nonatomic, assign) BOOL swiping;
@property (nonatomic, assign) BOOL settling;
@property (nonatomic, assign) NSUInteger swipeStartPage;
@property (nonatomic, assign) CGFloat swipeStartOffset;
@property (nonatomic, assign) CGFloat swipeOffset;
@end

static CGFloat CC26Rubber(CGFloat overshoot, CGFloat dim) {
    const CGFloat c = 0.55;
    return (1.0 - (1.0 / (overshoot * c / dim + 1.0))) * dim;
}

static CGFloat CC26RubberOffset(CGFloat raw, CGFloat minOff, CGFloat maxOff, CGFloat dim) {
    if (raw > maxOff) return maxOff + CC26Rubber(raw - maxOff, dim);
    if (raw < minOff) return minOff - CC26Rubber(minOff - raw, dim);
    return raw;
}

static void CC26NotifyPageActivated(UIView *collectionView, NSUInteger page) {
    if (!collectionView) return;
    if ((NSInteger)page == CC26ConnectivityPageIndex()) {
        CCAConnectivityPageView *conn = (CCAConnectivityPageView *)[collectionView viewWithTag:kConnectivityPageTag];
        if (conn) [conn refreshStates];
    }
}


#pragma mark - iOS 26 style module stretch

// While the page is dragged every module is stretched vertically and the ones that
// trail the motion lag behind the leading ones. On release (or when a page change is
// triggered by a tap) the modules spring back with a size bounce: they stretch and
// squash on themselves instead of just hopping in place. Everything is applied on
// the layers of the modules, never on the module collection, so it composes with the
// page slide that is already running on the collection's sublayerTransform.
static void CC26CollectStretchTargets(UIView *root, NSMutableArray<UIView *> *out, int depth) {
    if (!root || depth > 9) return;
    for (UIView *v in root.subviews) {
        NSString *n = NSStringFromClass(v.class);
        if ([n isEqualToString:@"CCUIContentModuleContainerView"] ||
            [n isEqualToString:@"CCAConnectivityTile"] ||
            v.tag == kMediaPlayerTag) {
            [out addObject:v];
            continue;
        }
        if (v.tag == kPageIndicatorTag || v.tag == kQuickAccessTag) continue;
        CC26CollectStretchTargets(v, out, depth + 1);
    }
}

// vertical position of a view inside its page, 0 (top) ... 1 (bottom); ignores transforms
static CGFloat CC26StretchPosition(UIView *v, UIView *collection) {
    CGFloat span = PageSpan();
    if (span < 1.0) return 0.5;
    CGFloat y = v.center.y;
    UIView *p = v.superview;
    int guard = 0;
    while (p && p != collection && guard++ < 12) {
        y += p.frame.origin.y - p.bounds.origin.y;
        p = p.superview;
    }
    CGFloat t = fmod(y, span) / span;
    if (t < 0.0) t += 1.0;
    return MIN(1.0, MAX(0.0, t));
}

// CC26StretchDrag runs on every touch-move of the page swipe (tens of times per drag on
// home-button devices, which lack the native paging notched devices get). Walking the whole
// view tree with NSStringFromClass on every single one of those calls was the main extra cost
// on button iPhones: cache the target list for the duration of one drag/settle instead.
static __weak UIView *sCC26StretchCacheCollection = nil;
static NSMutableArray<UIView *> *sCC26StretchCacheTargets = nil;

static void CC26StretchTargetsInvalidate(void) {
    sCC26StretchCacheCollection = nil;
    sCC26StretchCacheTargets = nil;
}

static NSArray<UIView *> *CC26StretchTargetsCached(UIView *collection) {
    if (collection && collection == sCC26StretchCacheCollection && sCC26StretchCacheTargets) {
        return sCC26StretchCacheTargets;
    }
    NSMutableArray<UIView *> *targets = [NSMutableArray array];
    CC26CollectStretchTargets(collection, targets, 0);
    sCC26StretchCacheCollection = collection;
    sCC26StretchCacheTargets = targets;
    return targets;
}

static void CC26StretchDrag(UIView *collection, CGFloat velocity) {
    if (!collection || !gBouncyAnimations) return;
    NSArray<UIView *> *targets = CC26StretchTargetsCached(collection);
    CGFloat v = MIN(4500.0, MAX(-4500.0, velocity));
    CGFloat mag = MIN(0.76, fabs(v) / 3200.0);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    for (UIView *t in targets) {
        CGFloat pos = CC26StretchPosition(t, collection);
        CGFloat lag = (v < 0.0) ? pos : (1.0 - pos);       // trailing modules lag more
        CGFloat ty = MIN(80.0, MAX(-80.0, -v * 0.0250 * lag));
        CGFloat sy = 1.0 + mag * (0.45 + 0.55 * (1.0 - lag));
        CATransform3D m = CATransform3DMakeTranslation(0.0, ty, 0.0);
        m = CATransform3DScale(m, 1.0 - (sy - 1.0) * 0.45, sy, 1.0);
        t.layer.transform = m;
    }
    [CATransaction commit];
}

// dir: +1 content moves up (next page), -1 content moves down, 0 unknown (use what is on screen)
static CGFloat gStretchAmpScale = 1.0;     // 1.0 = normal; finger swipe sets it higher
static CGFloat gStretchDampRatio = 0.0;    // 0 = default springs; >0 = fixed damping ratio (0.7 = tiny bounce)
static CGFloat gStretchSpeedScale = 1.0;   // 1.0 = normal; >1 = faster springs

static void CC26StretchSettleEx(UIView *collection, NSInteger dir, CGFloat vy, BOOL oneWay) {
    if (!collection || !gBouncyAnimations) return;
    NSArray<UIView *> *targets = CC26StretchTargetsCached(collection);
    CGFloat kick = oneWay ? 1.0 : MIN(1.0, MAX(0.75, fabs(vy) / 1800.0));
    CGFloat amp = (oneWay ? 3.0 : 1.0) * gStretchAmpScale;
    CGFloat spd = gStretchSpeedScale;   // opening is more exaggerated
    CFTimeInterval now = CACurrentMediaTime();
    for (UIView *t in targets) {
        CALayer *layer = t.layer;
        CALayer *pres = (CALayer *)layer.presentationLayer;
        CGFloat curTy = pres ? [[pres valueForKeyPath:@"transform.translation.y"] doubleValue] : 0.0;
        CGFloat curSy = pres ? [[pres valueForKeyPath:@"transform.scale.y"] doubleValue] : 1.0;
        CGFloat pos = CC26StretchPosition(t, collection);

        CGFloat curSx = pres ? [[pres valueForKeyPath:@"transform.scale.x"] doubleValue] : 1.0;
        CGFloat ty0 = curTy, sy0 = curSy, sx0 = curSx;
        CGFloat delay = 0.0;
        if (dir != 0) {
            CGFloat lag = (dir > 0) ? pos : (1.0 - pos);
            delay = (oneWay ? 0.018 : 0.040) * ((dir > 0) ? (1.0 - pos) : pos);     // leading modules start first
            if (fabs(curTy) < 1.0) ty0 = (CGFloat)dir * 92.0 * amp * kick * (0.35 + 0.65 * lag);
            if (curSy < 1.004) {
                sy0 = MIN(2.0, 1.0 + 0.30 * amp * kick) * (0.45 + 0.55 * (1.0 - lag));
                sx0 = MAX(0.78, 1.0 - 0.13 * amp * kick);
            }
        }
        if (fabs(ty0) < 0.5 && fabs(sy0 - 1.0) < 0.003) continue;

        [layer removeAnimationForKey:@"CC26StretchTY"];
        [layer removeAnimationForKey:@"CC26StretchSY"];
        [layer removeAnimationForKey:@"CC26StretchSX"];
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        layer.transform = CATransform3DIdentity;
        [CATransaction commit];

        CFTimeInterval begin = [layer convertTime:now fromLayer:nil] + delay;

        CASpringAnimation *ty = [CASpringAnimation animationWithKeyPath:@"transform.translation.y"];
        ty.mass = 1.0; ty.stiffness = (oneWay ? 260.0 : 106.0) * spd; ty.damping = (gStretchDampRatio > 0.0) ? gStretchDampRatio * 2.0 * sqrt(ty.stiffness) : (oneWay ? 32.0 : 6.8) * sqrt(spd); ty.initialVelocity = 0.0;
        ty.fromValue = @(ty0); ty.toValue = @0.0;
        ty.beginTime = begin; ty.fillMode = kCAFillModeBackwards;
        ty.duration = ty.settlingDuration;
        [layer addAnimation:ty forKey:@"CC26StretchTY"];

        CASpringAnimation *sy = [CASpringAnimation animationWithKeyPath:@"transform.scale.y"];
        sy.mass = 1.0; sy.stiffness = (oneWay ? 280.0 : 124.0) * spd; sy.damping = (gStretchDampRatio > 0.0) ? gStretchDampRatio * 2.0 * sqrt(sy.stiffness) : (oneWay ? 33.0 : 5.3) * sqrt(spd); sy.initialVelocity = 0.0;
        sy.fromValue = @(sy0); sy.toValue = @1.0;
        sy.beginTime = begin; sy.fillMode = kCAFillModeBackwards;
        sy.duration = sy.settlingDuration;
        [layer addAnimation:sy forKey:@"CC26StretchSY"];

        CASpringAnimation *sx = [CASpringAnimation animationWithKeyPath:@"transform.scale.x"];
        sx.mass = 1.0; sx.stiffness = (oneWay ? 280.0 : 132.0) * spd; sx.damping = (gStretchDampRatio > 0.0) ? gStretchDampRatio * 2.0 * sqrt(sx.stiffness) : (oneWay ? 33.0 : 8.5) * sqrt(spd); sx.initialVelocity = 0.0;
        sx.fromValue = @(sx0); sx.toValue = @1.0;
        sx.beginTime = begin; sx.fillMode = kCAFillModeBackwards;
        sx.duration = sx.settlingDuration;
        [layer addAnimation:sx forKey:@"CC26StretchSX"];
    }
}

static void CC26StretchSettle(UIView *collection, NSInteger dir, CGFloat vy) {
    CC26StretchSettleEx(collection, dir, vy, NO);
}

// Called when the Control Center starts to open. Face ID / notch iPhones pull it from the top
// (modules fall in: dir -1); home button iPhones pull it from the bottom (modules rise: dir +1).
void CC26PlayOpenStretch(UIViewController *overlay) {
    if (!gEnabled || !overlay) return;
    UIViewController *collection = ModuleCollection(overlay);
    if (!collection.view) return;
    BOOL fromTop = (CGRectGetHeight(UIScreen.mainScreen.bounds) >= 800.0);
    CC26StretchSettleEx(collection.view, fromTop ? -1 : 1, 2600.0, YES);   // one way only: no bounce back
}

static CGFloat gStretchLastOffset = 0.0;
static CFTimeInterval gStretchLastTime = 0.0;
static CGFloat gStretchVelocity = 0.0;

static BOOL CC26IndicatorIsLandscape(void) {
    CGSize size = UIScreen.mainScreen.bounds.size;
    return size.width > size.height;
}

// Candidate symbol names per page, best first. "music" is the Apple Music style note that
// ships in CC18.bundle/PrivateSymbols.bundle; the system "music.note" is only the fallback.
static NSArray<NSString *> *CC26IndicatorIconNamesForPage(NSUInteger index) {
    if (index == 0) return @[@"heart.fill"];
    if ((NSInteger)index == CC26MediaPageIndex()) return @[@"music", @"music.note"];
    if ((NSInteger)index == CC26ConnectivityPageIndex()) return @[@"antenna.radiowaves.left.and.right"];
    return @[@"circle.fill"];
}

static UIImage *CC26IndicatorSymbolForPage(NSUInteger index, CGFloat pointSize) {
    UIImage *image = nil;
    for (NSString *name in CC26IndicatorIconNamesForPage(index)) {
        image = CC26BundledSymbol(name, UIColor.whiteColor, NO);
        if (image) break;
    }
    if (!image) return nil;

    if (!image.symbolConfiguration) {
        UIImageSymbolConfiguration *cfg =
            [UIImageSymbolConfiguration configurationWithPointSize:pointSize
                                                            weight:UIImageSymbolWeightSemibold];
        image = [image imageByApplyingSymbolConfiguration:cfg] ?: image;
    }
    return [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

@implementation CCAPageIndicator

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = UIColor.clearColor;
        self.userInteractionEnabled = YES;
        self.currentPage = 0;
        self.pageCount = CC26PageCount();
        self.heldScale = 1.0;
        self.heldAlphaFactor = 1.0;
        self.jelloScaleX = 1.0;
        self.jelloScaleY = 1.0;
        self.baseCollectionSublayerTransform = CATransform3DIdentity;

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(scrubPan:)];
        pan.maximumNumberOfTouches = 1;
        pan.cancelsTouchesInView = YES;
        pan.delegate = self;
        [self addGestureRecognizer:pan];
        self.panRecognizer = pan;

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(deviceOrientationChanged:)
                                                     name:UIDeviceOrientationDidChangeNotification
                                                   object:nil];
    }
    return self;
}

- (void)deviceOrientationChanged:(NSNotification *)note {
    __weak CCAPageIndicator *weakSelf = self;
    for (NSNumber *delay in @[@0.05, @0.4, @0.9]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ [weakSelf syncLandscapeState]; });
    }
}

- (void)syncLandscapeState {
    BOOL landscape = CC26IndicatorIsLandscape();
    if (landscape == self.suspendedForLandscape) return;
    self.suspendedForLandscape = landscape;

    if (landscape) {
        if (self.panRecognizer.enabled) {
            self.panRecognizer.enabled = NO;
            self.panRecognizer.enabled = YES;
        }
        if (self.currentPage != 0 && self.overlay) {
            if (gExperimentalPagingEnabled) [self experimentalSetCurrentPage:0 forOverlay:self.overlay];
            else                            [self stableSetCurrentPage:0 forOverlay:self.overlay];
        }
        self.userInteractionEnabled = NO;
        self.hidden = YES;
    } else {
        self.hidden = NO;
        self.userInteractionEnabled = YES;
        [self captureCollectionBase];
        [self layoutButtons];
    }
}

- (void)setFrame:(CGRect)frame {
    [super setFrame:frame];
    [self syncLandscapeState];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    [self syncLandscapeState];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self syncLandscapeState];
}

- (BOOL)scrubbing {
    return self.scrubbingActive;
}

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

- (void)pulseCurrentButton {
    if (self.currentPage >= self.subviews.count) return;
    UIView *button = self.subviews[self.currentPage];
    [button.layer removeAnimationForKey:@"CC26IndicatorPulse"];
    CAKeyframeAnimation *pulse = [CAKeyframeAnimation animationWithKeyPath:@"transform.scale"];
    pulse.values = @[@1.0, @1.18, @0.95, @1.0];
    pulse.keyTimes = @[@0.0, @0.35, @0.72, @1.0];
    pulse.duration = 0.26;
    pulse.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
    [button.layer addAnimation:pulse forKey:@"CC26IndicatorPulse"];
}

- (void)setOverlay:(UIViewController *)overlay {
    _overlay = overlay;
    [self captureCollectionBase];
    [self rebuildButtons];
    [self syncLandscapeState];
}

- (void)captureCollectionBase {
    UIViewController *collection = ModuleCollection(self.overlay);
    if (!collection.view) return;
    if (self.transitionActive) return;

    CATransform3D current = collection.view.layer.sublayerTransform;
    CGFloat span = PageSpan();
    current.m42 += (CGFloat)gCurrentPage * span;
    current.m41 = 0.0;
    current.m43 = 0.0;

    self.baseCollectionSublayerTransform = current;
}

- (void)setPageCount:(NSUInteger)pageCount {
    if (pageCount == 0) pageCount = 1;
    if (_pageCount == pageCount && self.subviews.count == pageCount) return;
    _pageCount = pageCount;
    [self rebuildButtons];
}

- (void)rebuildButtons {
    while (self.subviews.count > self.pageCount) [self.subviews.lastObject removeFromSuperview];
    while (self.subviews.count < self.pageCount) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
        button.tintColor = UIColor.whiteColor;
        NSUInteger page = self.subviews.count;
        objc_setAssociatedObject(button, @selector(tapped:), @(page), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [button addTarget:self action:@selector(buttonTouchDown:) forControlEvents:UIControlEventTouchDown];
        [button addTarget:self action:@selector(buttonTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:button];
    }
    [self layoutButtons];
}

- (void)layoutButtons {
    [self layoutIndicatorsWithScrubbing:NO touchY:0.0];
}

- (void)layoutIndicatorsWithScrubbing:(BOOL)scrubbing touchY:(CGFloat)touchY {
    if (self.pageCount == 0) return;
    CGFloat overlayH = self.overlay ? CGRectGetHeight(self.overlay.view.bounds) : CGRectGetHeight(UIScreen.mainScreen.bounds);

    CGFloat step = scrubbing ? 58.0 : 39.0;
    CGFloat hostH = step * (CGFloat)self.pageCount;

    [CATransaction begin];
    [CATransaction setDisableActions:YES];

    if (scrubbing) {
        CGFloat rightEdge = CGRectGetMaxX(self.restHostFrame);
        if (rightEdge <= 0.0) rightEdge = CGRectGetMaxX(self.frame);
        CGFloat hostX = rightEdge - 58.0;
        CGFloat hostY = floor((overlayH - hostH) * 0.5);
        self.frame = CGRectMake(hostX, hostY, 58.0, hostH);
    }

    NSArray *buttons = self.subviews;
    NSUInteger count = buttons.count;
    NSUInteger index;
    for (index = 0; index < count; index++) {
        UIView *button = buttons[index];
        BOOL selected = ((NSInteger)index == (NSInteger)self.currentPage);

        if (scrubbing) {
            CGFloat centerY = ((CGFloat)index + 0.5) * step;
            CGFloat proximity = 1.0 - fabs(touchY - centerY) / 78.0;
            if (proximity < 0.0) proximity = 0.0;
            if (proximity > 1.0) proximity = 1.0;
            CGFloat scale = 1.18 + 1.68 * proximity + (selected ? 0.18 : 0.0);
            CGFloat rawSize = (index == 0 ? 16.0 : 12.0) * scale;
            CGFloat pointSize = rawSize < 38.0 ? rawSize : 38.0;
            CGFloat slideOut = 24.0 * proximity;
            CGFloat alpha = MIN(1.0, (selected ? 0.86 : 0.28) + 0.36 * proximity);
            CGFloat tintWhite = selected ? 1.0 : (0.12 + 0.72 * proximity);

            button.bounds = CGRectMake(0.0, 0.0, 58.0, step);
            button.center = CGPointMake(29.0 - slideOut, centerY);
            button.transform = CGAffineTransformIdentity;
            button.alpha = alpha;
            button.tintColor = [UIColor colorWithWhite:tintWhite alpha:1.0];

            UIButton *b = (UIButton *)button;
            UIImage *image = CC26IndicatorSymbolForPage(index, pointSize);
            if (image) [b setImage:image forState:UIControlStateNormal];
        } else {
            CGFloat y = (CGFloat)index * step;
            button.frame = CGRectMake(0.0, y, 42.0, step);
            button.transform = CGAffineTransformIdentity;

            UIButton *b = (UIButton *)button;
            CGFloat pointSize = (index == 0) ? 16.0 : 12.0;
            UIImage *image = CC26IndicatorSymbolForPage(index, pointSize);
            if (image) [b setImage:image forState:UIControlStateNormal];
            button.alpha = selected ? 1.0 : 0.72;
            button.tintColor = selected ? UIColor.whiteColor : [UIColor colorWithWhite:0.12 alpha:0.88];
        }
    }

    [CATransaction commit];
}

- (void)applyPageTransform {
    if (self.suspendedForLandscape) return;
    UIViewController *collection = ModuleCollection(self.overlay);
    if (!collection.view) return;

    CGFloat span = PageSpan();
    CGFloat pageOffset = -(CGFloat)self.currentPage * span + self.interactiveTranslation;

    CATransform3D target = CATransform3DTranslate(self.baseCollectionSublayerTransform, 0.0, pageOffset, 0.0);

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    collection.view.layer.sublayerTransform = target;
    if (self.scrubbingActive) {
        collection.view.layer.transform = CATransform3DMakeScale(self.jelloScaleX, self.jelloScaleY, 1.0);
        collection.view.alpha = self.heldAlphaFactor;
    } else {
        collection.view.layer.transform = CATransform3DIdentity;
        collection.view.alpha = 1.0;
    }
    [CATransaction commit];
}

- (void)beginInteractiveTransitionWithStartPage:(NSUInteger)startPage {
    if (self.suspendedForLandscape) return;
    if (!self.overlay) return;
    UIViewController *collection = ModuleCollection(self.overlay);
    if (!collection.view) return;

    self.restHostFrame = self.frame;

    self.transitionActive = YES;
    self.scrubbingActive = YES;
    self.dragging = NO;
    self.interactiveStartPage = MIN(startPage, self.pageCount - 1);
    self.currentPage = self.interactiveStartPage;
    gCurrentPage = (NSInteger)self.interactiveStartPage;
    self.interactiveProgress = (CGFloat)self.interactiveStartPage;
    self.interactiveTranslation = 0.0;
    self.interactiveBeganTime = CACurrentMediaTime();
    self.heldScale = 1.0;
    self.heldAlphaFactor = 1.0;
    self.viscousProgress = (CGFloat)self.interactiveStartPage;
    self.previousRawProgress = (CGFloat)self.interactiveStartPage;
    self.filteredVelocity = 0.0;
    self.jelloScaleX = 1.0;
    self.jelloScaleY = 1.0;
    self.lastSampleTime = CACurrentMediaTime();

    self.savedCollectionView = collection.view;

    CALayer *pres = (CALayer *)collection.view.layer.presentationLayer;
    if (pres) {
        collection.view.layer.sublayerTransform = pres.sublayerTransform;
        collection.view.layer.transform = pres.transform;
    }
    [collection.view.layer removeAllAnimations];
}

- (void)updateInteractiveTransitionWithProgress:(CGFloat)progress touchY:(CGFloat)touchY {
    if (!self.overlay || !self.transitionActive) return;

    UIViewController *collection = ModuleCollection(self.overlay);
    if (!collection.view) return;

    CGFloat maxProgress = (CGFloat)self.pageCount - 1.0;

    CGFloat physicsProgress = progress;
    if (progress < 0.0) physicsProgress = -log1p(-progress);
    else if (progress > maxProgress) physicsProgress = maxProgress + log1p(progress - maxProgress);

    NSUInteger previousCandidate = self.currentPage;

    CFTimeInterval now = CACurrentMediaTime();
    CGFloat dt = self.lastSampleTime > 0.0 ? (CGFloat)(now - self.lastSampleTime) : (1.0 / 60.0);
    dt = MIN(0.050, MAX(1.0 / 120.0, dt));

    CGFloat rawVelocity = (physicsProgress - self.previousRawProgress) / dt;
    rawVelocity = MIN(8.0, MAX(-8.0, rawVelocity));
    CGFloat velocityResponse = 1.0 - exp(-dt * 11.0);
    self.filteredVelocity += (rawVelocity - self.filteredVelocity) * velocityResponse;

    CGFloat dragResponse = 1.0 - exp(-dt * 9.0);
    self.viscousProgress += (physicsProgress - self.viscousProgress) * dragResponse;

    CGFloat visualProgress = self.viscousProgress;
    NSUInteger candidate = (NSUInteger)llround(MIN(maxProgress, MAX(0.0, visualProgress)));
    BOOL changedPage = (candidate != previousCandidate);
    if (changedPage) Haptic();
    CGFloat pageTension = physicsProgress - visualProgress;

    self.previousRawProgress = physicsProgress;
    self.lastSampleTime = now;
    self.interactiveProgress = MIN(maxProgress, MAX(0.0, progress));
    self.currentPage = candidate;
    gCurrentPage = (NSInteger)candidate;

    CGFloat overlayHeight = CGRectGetHeight(self.overlay.view.bounds);
    CGFloat scrubHostHeight = 58.0 * self.pageCount;
    CGFloat scrubHostMinY = floor((overlayHeight - scrubHostHeight) * 0.5);
    CGFloat fingerY = scrubHostMinY + touchY;

    CGFloat translationTarget = 0.0;
    BOOL endpointPull = NO;
    if (progress < 0.0) {
        CGFloat firstIconY = scrubHostMinY + 58.0 * 0.5;
        CGFloat upperLimitY = overlayHeight * 0.10;
        CGFloat pull = MIN(1.0, MAX(0.0, (firstIconY - fingerY) / MAX(1.0, firstIconY - upperLimitY)));
        CGFloat eased = 1.0 - pow(1.0 - pull, 1.35);
        translationTarget = -MIN(100.0, overlayHeight * 0.12) * eased;
        endpointPull = YES;
    } else if (progress > maxProgress) {
        CGFloat lastIconY = scrubHostMinY + ((CGFloat)self.pageCount - 0.5) * 58.0;
        CGFloat lowerLimitY = overlayHeight * 0.90;
        CGFloat pull = MIN(1.0, MAX(0.0, (fingerY - lastIconY) / MAX(1.0, lowerLimitY - lastIconY)));
        CGFloat eased = 1.0 - pow(1.0 - pull, 1.35);
        translationTarget = MIN(100.0, overlayHeight * 0.12) * eased;
        endpointPull = YES;
    } else {
        translationTarget = (visualProgress - (CGFloat)candidate) * 22.0;
    }

    if (endpointPull) {
        self.interactiveTranslation += (translationTarget - self.interactiveTranslation) * dragResponse;
    } else {
        self.interactiveTranslation = translationTarget;
    }

    CGFloat entrance = self.interactiveBeganTime > 0.0
        ? MIN(1.0, MAX(0.0, (CACurrentMediaTime() - self.interactiveBeganTime) / 0.26)) : 1.0;
    entrance = entrance * entrance * entrance * (entrance * (entrance * 6.0 - 15.0) + 10.0);
    self.heldScale = 1.0 - 0.30 * entrance;
    self.heldAlphaFactor = 1.0 - 0.30 * entrance;

    CGFloat jelloInput = self.filteredVelocity * 0.0030 + pageTension * 0.022;
    CGFloat jello = MIN(0.025, MAX(-0.025, jelloInput)) * entrance;
    self.jelloScaleX = (1.0 - jello * 0.42) * self.heldScale;
    self.jelloScaleY = (1.0 + jello) * self.heldScale;

    [self applyPageTransform];
    {
        CGFloat sv = self.filteredVelocity * -(PageSpan() * 0.35);
        CC26StretchDrag(collection.view, MIN(4500.0, MAX(-4500.0, sv)));
    }
    if (changedPage) {
        [CC26.shared syncModuleVisibilityForOverlay:self.overlay animated:YES];
        CCAMediaPlayerView *player = (CCAMediaPlayerView *)[collection.view viewWithTag:kMediaPlayerTag];
        if (player) {
            CGFloat targetAlpha = ((NSInteger)candidate == CC26MediaPageIndex()) ? 1.0 : 0.0;
            if (fabs(player.alpha - targetAlpha) > 0.01) {
                [UIView animateWithDuration:0.15 animations:^{ player.alpha = targetAlpha; }];
            }
        }

        CC26NotifyPageActivated(collection.view, candidate);
    }

    [self layoutIndicatorsWithScrubbing:YES touchY:touchY];
}

- (void)finishInteractiveTransitionWithTargetPage:(NSUInteger)targetPage {
    if (!self.overlay || !self.transitionActive) return;

    UIViewController *collection = ModuleCollection(self.overlay);
    if (!collection.view) return;

    NSUInteger target = MIN(targetPage, self.pageCount - 1);
    self.interactiveBeganTime = 0.0;
    self.scrubbingActive = NO;
    self.currentPage = target;
    gCurrentPage = (NSInteger)target;
    self.interactiveTranslation = 0.0;

    [CC26.shared syncModuleVisibilityForOverlay:self.overlay animated:YES];
    [CC26.shared applyHeaderMaterialHidden:((NSInteger)target == CC26MediaPageIndex()) forOverlay:self.overlay];
    [CC26.shared adjustStatusBarForOverlay:self.overlay];

    CCAMediaPlayerView *player = (CCAMediaPlayerView *)[collection.view viewWithTag:kMediaPlayerTag];
    if (player) {
        player.alpha = ((NSInteger)target == CC26MediaPageIndex()) ? 1.0 : 0.0;
        player.transform = CGAffineTransformIdentity;
    }

    CC26NotifyPageActivated(collection.view, target);

    CGFloat span = PageSpan();
    CATransform3D toSub = CATransform3DTranslate(self.baseCollectionSublayerTransform, 0.0, -(CGFloat)target * span, 0.0);

    CALayer *pres = (CALayer *)collection.view.layer.presentationLayer;
    CATransform3D fromSub = pres ? pres.sublayerTransform : collection.view.layer.sublayerTransform;
    CATransform3D fromTrans = pres ? pres.transform : collection.view.layer.transform;
    CGFloat fromAlpha = pres ? pres.opacity : collection.view.alpha;

    [collection.view.layer removeAnimationForKey:@"CC26AnimPageSlide"];
    [collection.view.layer removeAnimationForKey:@"CC26AnimScrubTransform"];
    [collection.view.layer removeAnimationForKey:@"CC26AnimScrubOpacity"];

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    collection.view.layer.sublayerTransform = toSub;
    collection.view.layer.transform = CATransform3DIdentity;
    collection.view.alpha = 1.0;
    [CATransaction commit];

    {
        NSInteger d = (NSInteger)target - (NSInteger)self.interactiveStartPage;
        CC26StretchSettle(collection.view, d > 0 ? 1 : (d < 0 ? -1 : 0), 1800.0);
    }

    CAMediaTimingFunction *curve = [CAMediaTimingFunction functionWithControlPoints:0.18 :0.88 :0.20 :1.0];

    CASpringAnimation *slide = [CASpringAnimation animationWithKeyPath:@"sublayerTransform"];
    slide.mass = 1.0;
    slide.stiffness = 122.0;
    slide.damping = CC26SpringCriticalDamping(122.0, 11.9);
    slide.initialVelocity = 0.0;
    slide.fromValue = [NSValue valueWithCATransform3D:fromSub];
    slide.toValue   = [NSValue valueWithCATransform3D:toSub];
    slide.duration = slide.settlingDuration;
    [collection.view.layer addAnimation:slide forKey:@"CC26AnimPageSlide"];

    CABasicAnimation *scale = [CABasicAnimation animationWithKeyPath:@"transform"];
    scale.fromValue = [NSValue valueWithCATransform3D:fromTrans];
    scale.toValue   = [NSValue valueWithCATransform3D:CATransform3DIdentity];
    scale.duration = 0.30;
    scale.timingFunction = curve;
    [collection.view.layer addAnimation:scale forKey:@"CC26AnimScrubTransform"];

    CABasicAnimation *fade = [CABasicAnimation animationWithKeyPath:@"opacity"];
    fade.fromValue = @(fromAlpha);
    fade.toValue = @1.0;
    fade.duration = 0.30;
    fade.timingFunction = curve;
    [collection.view.layer addAnimation:fade forKey:@"CC26AnimScrubOpacity"];

    [CC26.shared layoutPageIndicatorForOverlay:self.overlay];

    NSUInteger token = ++self.animationToken;
    __weak CCAPageIndicator *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.15 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        CCAPageIndicator *strongSelf = weakSelf;
        if (!strongSelf) return;
        if (strongSelf.animationToken != token) return;

        strongSelf.transitionActive = NO;
        strongSelf.scrubbingActive = NO;
        strongSelf.dragging = NO;
        strongSelf.savedCollectionView = nil;
        strongSelf.heldScale = 1.0;
        strongSelf.heldAlphaFactor = 1.0;
        strongSelf.jelloScaleX = 1.0;
        strongSelf.jelloScaleY = 1.0;
        strongSelf.viscousProgress = (CGFloat)target;
        strongSelf.filteredVelocity = 0.0;
        strongSelf.lastSampleTime = 0.0;

        gCurrentPage = (NSInteger)target;
        [strongSelf applyPageTransform];
        [strongSelf captureCollectionBase];
        [CC26.shared syncModuleVisibilityForOverlay:strongSelf.overlay animated:NO];
        [CC26.shared layoutPageIndicatorForOverlay:strongSelf.overlay];

        [strongSelf pulseCurrentButton];
    });
}

- (void)scrubPan:(UIPanGestureRecognizer *)gesture {
    if (!gExperimentalPagingEnabled) return;
    if (!self.overlay || !gPagingEnabled || self.pageCount <= 1) return;
    UIViewController *collection = ModuleCollection(self.overlay);
    if (!collection.view) return;

    CGFloat overlayH = CGRectGetHeight(self.overlay.view.bounds);
    CGFloat scrubStep = 58.0;
    CGFloat scrubHostH = scrubStep * (CGFloat)self.pageCount;
    CGFloat scrubHostMinY = floor((overlayH - scrubHostH) * 0.5);

    CGPoint location = [gesture locationInView:self.superview];
    CGFloat touchY = location.y - scrubHostMinY;
    CGFloat progress = (touchY - scrubStep * 0.5) / scrubStep;
    CGFloat maxProgress = (CGFloat)self.pageCount - 1.0;
    progress = MIN(maxProgress + 0.9, MAX(-0.9, progress));

    if (gesture.state == UIGestureRecognizerStateBegan) {
        CC26StretchTargetsInvalidate();
        self.dragging = YES;
        self.dragStartPage = self.currentPage;
        if (!self.transitionActive) {
            [self beginInteractiveTransitionWithStartPage:self.currentPage];
        }
        [self updateInteractiveTransitionWithProgress:progress touchY:touchY];

    } else if (gesture.state == UIGestureRecognizerStateChanged) {
        if (self.transitionActive) {
            [self updateInteractiveTransitionWithProgress:progress touchY:touchY];
        }

    } else if (gesture.state == UIGestureRecognizerStateEnded ||
               gesture.state == UIGestureRecognizerStateCancelled ||
               gesture.state == UIGestureRecognizerStateFailed) {
        if (self.transitionActive && self.scrubbingActive) {
            NSUInteger target;
            if (gesture.state == UIGestureRecognizerStateEnded) {
                target = (NSUInteger)llround(MIN(maxProgress, MAX(0.0, progress)));
            } else {
                target = self.dragStartPage;
            }
            [self finishInteractiveTransitionWithTargetPage:target];
        }
    }
}

- (void)buttonTouchDown:(UIButton *)sender {
    if (!gExperimentalPagingEnabled) return;
    if (!self.overlay || !gPagingEnabled || self.pageCount <= 1) return;
    UIViewController *collection = ModuleCollection(self.overlay);
    if (!collection.view) return;

    NSNumber *page = objc_getAssociatedObject(sender, @selector(tapped:));
    if (!page) return;
    NSUInteger targetPage = page.unsignedIntegerValue;

    if (self.transitionActive) {
        self.animationToken++;
        self.transitionActive = NO;
        self.scrubbingActive = NO;
    }

    [self beginInteractiveTransitionWithStartPage:self.currentPage];

    CGFloat touchY = ((CGFloat)targetPage + 0.5) * 58.0;
    [self updateInteractiveTransitionWithProgress:(CGFloat)targetPage touchY:touchY];
}

- (void)buttonTapped:(UIButton *)sender {
    if (!self.overlay || !gPagingEnabled) return;
    if (self.dragging) return;

    NSNumber *page = objc_getAssociatedObject(sender, @selector(tapped:));
    if (!page) return;
    NSUInteger targetPage = page.unsignedIntegerValue;

    if (self.transitionActive) {
        Haptic();
        [self finishInteractiveTransitionWithTargetPage:targetPage];
        return;
    }

    if (targetPage == self.currentPage) return;
    Haptic();
    [self setCurrentPage:targetPage forOverlay:self.overlay];
}

- (void)setCurrentPage:(NSUInteger)page forOverlay:(UIViewController *)overlay {
    if (self.suspendedForLandscape) return;
    if (gExperimentalPagingEnabled) {
        [self experimentalSetCurrentPage:page forOverlay:overlay];
    } else {
        [self stableSetCurrentPage:page forOverlay:overlay];
    }
}

- (void)stableSetCurrentPage:(NSUInteger)page forOverlay:(UIViewController *)overlay {
    if (page >= self.pageCount) return;
    if (page == self.currentPage) return;

    NSInteger stretchDir = ((NSInteger)page > (NSInteger)self.currentPage) ? 1 : -1;
    self.currentPage = page;
    gCurrentPage = (NSInteger)page;

    [CC26.shared applyHeaderMaterialHidden:((NSInteger)page == CC26MediaPageIndex()) forOverlay:overlay];
    [CC26.shared adjustStatusBarForOverlay:overlay];

    UIViewController *collection = ModuleCollection(overlay);
    if (!collection.view) return;
    CGFloat span = PageSpan();
    CC26StretchSettle(collection.view, stretchDir, 1800.0);

    CCAMediaPlayerView *player = (CCAMediaPlayerView *)[collection.view viewWithTag:kMediaPlayerTag];
    if (player) {
        if ((NSInteger)page == CC26MediaPageIndex()) [player fadeIn];
        else [player fadeOut];
    }

    CC26NotifyPageActivated(collection.view, page);

    [CC26.shared syncModuleVisibilityForOverlay:overlay animated:YES];

    CATransform3D target = collection.view.layer.sublayerTransform;
    target.m41 = 0.0;
    target.m42 = -(CGFloat)page * span;
    target.m43 = 0.0;

    gPageAnimating = YES;
    [UIView animateWithDuration:1.08 delay:0.0 usingSpringWithDamping:CC26SpringDamping(0.72) initialSpringVelocity:0.0
                        options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
        collection.view.layer.sublayerTransform = target;
    } completion:^(BOOL finished) {
        gPageAnimating = NO;
    }];

    [self layoutButtons];

    [self pulseCurrentButton];
}

- (void)experimentalSetCurrentPage:(NSUInteger)page forOverlay:(UIViewController *)overlay {
    if (page >= self.pageCount) return;
    if (self.transitionActive || self.scrubbingActive) return;
    if (page == self.currentPage) return;

    NSInteger stretchDir = ((NSInteger)page > (NSInteger)self.currentPage) ? 1 : -1;
    self.currentPage = page;
    gCurrentPage = (NSInteger)page;

    [CC26.shared applyHeaderMaterialHidden:((NSInteger)page == CC26MediaPageIndex()) forOverlay:overlay];
    [CC26.shared adjustStatusBarForOverlay:overlay];

    UIViewController *collection = ModuleCollection(overlay);
    if (!collection.view) return;
    CGFloat span = PageSpan();
    CC26StretchSettle(collection.view, stretchDir, 1800.0);

    CATransform3D toSub = CATransform3DTranslate(self.baseCollectionSublayerTransform, 0.0, -(CGFloat)page * span, 0.0);
    CALayer *pres = (CALayer *)collection.view.layer.presentationLayer;
    CATransform3D fromSub = pres ? pres.sublayerTransform : collection.view.layer.sublayerTransform;

    [collection.view.layer removeAnimationForKey:@"CC26AnimPageSlide"];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    collection.view.layer.sublayerTransform = toSub;
    [CATransaction commit];

    CASpringAnimation *slide = [CASpringAnimation animationWithKeyPath:@"sublayerTransform"];
    slide.mass = 1.0;
    slide.stiffness = 108.0;
    slide.damping = CC26SpringCriticalDamping(108.0, 11.2);
    slide.initialVelocity = 0.0;
    slide.fromValue = [NSValue valueWithCATransform3D:fromSub];
    slide.toValue   = [NSValue valueWithCATransform3D:toSub];
    slide.duration = slide.settlingDuration;
    [collection.view.layer addAnimation:slide forKey:@"CC26AnimPageSlide"];

    CCAMediaPlayerView *player = (CCAMediaPlayerView *)[collection.view viewWithTag:kMediaPlayerTag];
    if (player) {
        player.alpha = ((NSInteger)page == CC26MediaPageIndex()) ? 1.0 : 0.0;
        player.transform = CGAffineTransformIdentity;
    }

    CC26NotifyPageActivated(collection.view, page);

    [CC26.shared syncModuleVisibilityForOverlay:overlay animated:YES];
    [self layoutButtons];

    [self pulseCurrentButton];
}

#pragma mark - Swipe between pages (rubber band + spring)

- (void)installSwipeRecognizerOnView:(UIView *)view {
    if (!view) return;
    if (self.swipeRecognizer && self.swipeHostView == view) return;
    [self removeSwipeRecognizer];
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pageSwipePan:)];
    pan.maximumNumberOfTouches = 1;
    pan.delegate = self;
    [view addGestureRecognizer:pan];
    self.swipeRecognizer = pan;
    self.swipeHostView = view;
}

- (void)removeSwipeRecognizer {
    UIPanGestureRecognizer *pan = self.swipeRecognizer;
    if (pan) {
        pan.delegate = nil;
        [pan removeTarget:self action:NULL];
        [pan.view removeGestureRecognizer:pan];
    }
    self.swipeRecognizer = nil;
    self.swipeHostView = nil;
}

- (void)willMoveToSuperview:(UIView *)newSuperview {
    [super willMoveToSuperview:newSuperview];
    if (!newSuperview) [self removeSwipeRecognizer];
}

- (void)dealloc {
    [self removeSwipeRecognizer];
}

- (BOOL)swipeShouldReceiveTouch:(UITouch *)touch {
    if (!gEnabled || !gPagingEnabled || !gSwipePagingEnabled || self.pageCount <= 1) return NO;
    if (self.suspendedForLandscape || self.scrubbingActive) return NO;
    if (gCCAModuleExpanded || gEditModeActive) return NO;
    UIViewController *overlay = self.overlay;
    if (!overlay || !overlay.view || overlay.presentedViewController) return NO;

    UIView *host = overlay.view;
    CGPoint p = [touch locationInView:host];
    CGFloat h = CGRectGetHeight(host.bounds);
    // leave the top (quick access buttons) and the bottom edge (swipe up to dismiss) alone
    if (p.y < 60.0 || p.y > h - 110.0) return NO;

    for (UIView *v = touch.view; v && v != host; v = v.superview) {
        if (v == self) return NO;
        NSString *name = NSStringFromClass(v.class);
        if ([v isKindOfClass:UISlider.class] ||
            [name containsString:@"Slider"] ||
            [name containsString:@"Scrubber"] ||
            [name containsString:@"TimeControl"] ||
            [name containsString:@"VolumeControl"]) return NO;
    }
    return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    if (gestureRecognizer == self.swipeRecognizer) return [self swipeShouldReceiveTouch:touch];
    return YES;
}

- (void)setCollectionOffset:(CGFloat)offset {
    UIViewController *collection = ModuleCollection(self.overlay);
    if (!collection.view) return;
    CATransform3D t = CATransform3DTranslate(self.baseCollectionSublayerTransform, 0.0, offset, 0.0);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    collection.view.layer.sublayerTransform = t;
    [CATransaction commit];
}

- (void)swipeActivatePage:(NSUInteger)page {
    if (page == self.currentPage) return;
    UIViewController *overlay = self.overlay;
    UIViewController *collection = ModuleCollection(overlay);

    self.currentPage = page;
    gCurrentPage = (NSInteger)page;
    Haptic();

    [CC26.shared applyHeaderMaterialHidden:((NSInteger)page == CC26MediaPageIndex()) forOverlay:overlay];
    [CC26.shared adjustStatusBarForOverlay:overlay];
    [CC26.shared syncModuleVisibilityForOverlay:overlay animated:YES];

    if (collection.view) {
        CCAMediaPlayerView *player = (CCAMediaPlayerView *)[collection.view viewWithTag:kMediaPlayerTag];
        if (player) {
            CGFloat targetAlpha = ((NSInteger)page == CC26MediaPageIndex()) ? 1.0 : 0.0;
            if (fabs(player.alpha - targetAlpha) > 0.01) {
                [UIView animateWithDuration:0.18 animations:^{ player.alpha = targetAlpha; }];
            }
            player.transform = CGAffineTransformIdentity;
        }
        CC26NotifyPageActivated(collection.view, page);
    }
    [self layoutButtons];
}

- (void)beginPageSwipe {
    UIViewController *collection = ModuleCollection(self.overlay);
    if (!collection.view) return;
    CC26StretchTargetsInvalidate();
    CALayer *layer = collection.view.layer;
    CGFloat span = PageSpan();

    CGFloat startOffset = -(CGFloat)gCurrentPage * span;
    if (self.settling || self.transitionActive) {
        CALayer *pres = (CALayer *)layer.presentationLayer;
        CATransform3D cur = pres ? pres.sublayerTransform : layer.sublayerTransform;
        startOffset = cur.m42 - self.baseCollectionSublayerTransform.m42;
    }

    self.animationToken++;
    self.settling = NO;
    self.swiping = YES;
    self.transitionActive = YES;
    self.scrubbingActive = NO;
    self.interactiveTranslation = 0.0;
    gPagerScrubbing = YES;

    self.swipeStartPage = MIN((NSUInteger)MAX((NSInteger)0, (NSInteger)gCurrentPage), self.pageCount - 1);
    self.swipeStartOffset = startOffset;
    self.swipeOffset = startOffset;

    [layer removeAllAnimations];
    [self setCollectionOffset:startOffset];
    gStretchLastOffset = startOffset;
    gStretchLastTime = CACurrentMediaTime();
    gStretchVelocity = 0.0;
}

- (void)updatePageSwipeWithTranslation:(CGFloat)dy {
    CGFloat span = PageSpan();
    if (span < 1.0) return;
    CGFloat last = (CGFloat)self.pageCount - 1.0;
    CGFloat minOff = -last * span;
    CGFloat maxOff = 0.0;
    CGFloat dim = MAX(180.0, CGRectGetHeight(self.overlay.view.bounds) * 0.4);

    CGFloat offset = CC26RubberOffset(self.swipeStartOffset + dy, minOff, maxOff, dim);
    self.swipeOffset = offset;
    [self setCollectionOffset:offset];
    {
        CFTimeInterval now = CACurrentMediaTime();
        CGFloat dt = MIN(0.05, MAX(1.0 / 120.0, (CGFloat)(now - gStretchLastTime)));
        CGFloat raw = (offset - gStretchLastOffset) / dt;
        gStretchVelocity += (raw - gStretchVelocity) * 0.35;
        gStretchLastOffset = offset;
        gStretchLastTime = now;
        CC26StretchDrag(ModuleCollection(self.overlay).view, gStretchVelocity);
    }

    NSInteger candidate = (NSInteger)llround(-offset / span);
    candidate = MAX((NSInteger)0, MIN((NSInteger)self.pageCount - 1, candidate));
    [self swipeActivatePage:(NSUInteger)candidate];
}

- (void)endPageSwipeWithTranslation:(CGFloat)dy velocity:(CGFloat)vy cancelled:(BOOL)cancelled {
    CGFloat span = PageSpan();
    NSInteger last = (NSInteger)self.pageCount - 1;
    NSInteger target = (NSInteger)self.swipeStartPage;

    if (cancelled) {
        vy = 0.0;
    } else {
        CGFloat commit = MIN(span * 0.18, 110.0);
        if (vy < -450.0) target++;
        else if (vy > 450.0) target--;
        else if (dy < -commit) target++;
        else if (dy > commit) target--;
    }
    target = MAX((NSInteger)0, MIN(last, target));
    self.swiping = NO;
    [self settleToPage:(NSUInteger)target velocity:vy];
}

- (void)settleToPage:(NSUInteger)page velocity:(CGFloat)vy {
    UIViewController *collection = ModuleCollection(self.overlay);
    CGFloat span = PageSpan();
    if (!collection.view) {
        self.settling = NO;
        self.transitionActive = NO;
        gPagerScrubbing = NO;
        return;
    }

    CGFloat toOffset = -(CGFloat)page * span;
    CGFloat dist = toOffset - self.swipeOffset;
    CGFloat normalizedVelocity = fabs(dist) > 1.0 ? vy / dist : 0.0;
    normalizedVelocity = MIN(8.0, MAX(-2.0, normalizedVelocity));

    [self swipeActivatePage:page];

    NSUInteger token = ++self.animationToken;
    self.settling = YES;

    CALayer *layer = collection.view.layer;
    CATransform3D to = CATransform3DTranslate(self.baseCollectionSublayerTransform, 0.0, toOffset, 0.0);

    NSInteger stretchDir = (NSInteger)page - (NSInteger)self.swipeStartPage;
    stretchDir = stretchDir > 0 ? 1 : (stretchDir < 0 ? -1 : 0);
    gStretchAmpScale = 1.7;      // finger swipe: stretch a bit further
    gStretchSpeedScale = 2.0;    // finger swipe: faster springs
    gStretchDampRatio = 0.72;    // finger swipe: only a tiny bounce when it lands
    CC26StretchSettle(collection.view, stretchDir, vy);
    gStretchAmpScale = 1.0;
    gStretchSpeedScale = 1.0;
    gStretchDampRatio = 0.0;
    gStretchVelocity = 0.0;

    __weak CCAPageIndicator *weakSelf = self;
    [UIView animateWithDuration:0.70 delay:0.0 usingSpringWithDamping:CC26SpringDamping(0.86) initialSpringVelocity:CC26SpringVelocity(normalizedVelocity)
                        options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
        layer.sublayerTransform = to;
    } completion:^(BOOL finished) {
        [weakSelf finishSwipeSettleWithToken:token page:page];
    }];
}

- (void)finishSwipeSettleWithToken:(NSUInteger)token page:(NSUInteger)page {
    if (token != self.animationToken) return;
    self.settling = NO;
    self.swiping = NO;
    self.transitionActive = NO;
    self.scrubbingActive = NO;
    self.dragging = NO;
    self.interactiveTranslation = 0.0;
    self.currentPage = page;
    gCurrentPage = (NSInteger)page;
    gPagerScrubbing = NO;

    [self applyPageTransform];
    [self captureCollectionBase];
    [CC26.shared syncModuleVisibilityForOverlay:self.overlay animated:NO];
    [CC26.shared layoutPageIndicatorForOverlay:self.overlay];
    [self pulseCurrentButton];
}

- (void)pageSwipePan:(UIPanGestureRecognizer *)gesture {
    switch (gesture.state) {
        case UIGestureRecognizerStateBegan:
            if (self.suspendedForLandscape) return;
            [self beginPageSwipe];
            break;
        case UIGestureRecognizerStateChanged:
            if (self.swiping) [self updatePageSwipeWithTranslation:[gesture translationInView:gesture.view].y];
            break;
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled:
        case UIGestureRecognizerStateFailed:
            if (self.swiping) {
                [self endPageSwipeWithTranslation:[gesture translationInView:gesture.view].y
                                         velocity:[gesture velocityInView:gesture.view].y
                                        cancelled:(gesture.state != UIGestureRecognizerStateEnded)];
            }
            break;
        default:
            break;
    }
}

// The module area lives inside the Control Center's own scroll views, whose pan recognizers sit
// deeper in the hierarchy and would win every vertical drag (that is why only the indicator
// strip could be swiped). Make those scroll pans wait for our swipe to fail first.
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldBeRequiredToFailByGestureRecognizer:(UIGestureRecognizer *)other {
    if (gestureRecognizer != self.swipeRecognizer) return NO;
    if (![other isKindOfClass:UIPanGestureRecognizer.class]) return NO;
    UIView *ov = other.view;
    UIView *host = gestureRecognizer.view;
    if (!ov || !host || other == self.panRecognizer) return NO;
    if (ov == self || [ov isDescendantOfView:self]) return NO;       // the indicator keeps its own scrub
    return [ov isDescendantOfView:host] || [host isDescendantOfView:ov];
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if (gestureRecognizer == self.swipeRecognizer) {
        if (self.suspendedForLandscape || self.scrubbingActive) return NO;
        UIPanGestureRecognizer *swipe = (UIPanGestureRecognizer *)gestureRecognizer;
        CGPoint t = [swipe translationInView:swipe.view];
        return fabs(t.y) >= fabs(t.x);
    }
    if (self.suspendedForLandscape) return NO;
    if (!gExperimentalPagingEnabled) return NO;
    if (gestureRecognizer == self.panRecognizer) {
        if (!gPagingEnabled || self.pageCount <= 1) return NO;
        UIPanGestureRecognizer *pan = (UIPanGestureRecognizer *)gestureRecognizer;
        CGPoint velocity = [pan velocityInView:self];
        return fabs(velocity.y) > fabs(velocity.x);
    }
    return YES;
}

@end