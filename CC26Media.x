#import "CC26.h"

@interface CCAMediaPlayerView ()
@property (nonatomic, weak) UIView *cachedSampleView;
@property (nonatomic, strong) UIView *backingView;
@property (nonatomic, strong) UIView *blurView;
@property (nonatomic, strong) UIView *artworkContainer;
@property (nonatomic, strong) UIImageView *artworkView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *artistLabel;
@property (nonatomic, strong) UIView *progressTrack;
@property (nonatomic, strong) UIView *progressFill;
@property (nonatomic, assign) CGFloat progressPct;
@property (nonatomic, strong) UILabel *elapsedLabel;
@property (nonatomic, strong) UILabel *remainingLabel;
@property (nonatomic, strong) UIButton *prevButton;
@property (nonatomic, strong) UIButton *playPauseButton;
@property (nonatomic, strong) UIButton *nextButton;
@property (nonatomic, strong) UIView *airplayPill;
@property (nonatomic, strong) UIImageView *airplayIconView;
@property (nonatomic, strong) UILabel *airplayLabel;
@property (nonatomic, strong) NSTimer *refreshTimer;
@property (nonatomic, strong) CADisplayLink *mirrorLink;
@property (nonatomic, assign) BOOL isAnimatingIn;
@property (nonatomic, assign) BOOL isPlaying;
@property (nonatomic, strong) UIView *volumeTrack;
@property (nonatomic, strong) UIView *volumeFill;
@property (nonatomic, strong) UIImageView *decreaseVolumeIcon;
@property (nonatomic, strong) UIImageView *increaseVolumeIcon;
@property (nonatomic, strong) NSString *lastArtworkIdentifier;
- (UIView *)findSampleModuleView;
@end

static void (*MRMediaRemoteGetNowPlayingInfo)(dispatch_queue_t queue, void (^block)(CFDictionaryRef information)) = NULL;
static void (*MRMediaRemoteSendCommand)(int command, NSDictionary *userInfo) = NULL;

static void InitMediaRemote(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        void *handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY);
        if (handle) {
            MRMediaRemoteGetNowPlayingInfo = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo");
            MRMediaRemoteSendCommand = dlsym(handle, "MRMediaRemoteSendCommand");
        }
    });
}

@implementation CCAMediaPlayerView
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

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    self.backgroundColor = UIColor.clearColor;
    self.layer.cornerRadius = 22;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.layer.masksToBounds = YES;

    UIView *material = nil;
    Class MTMaterialViewClass = NSClassFromString(@"MTMaterialView");

    if ([MTMaterialViewClass respondsToSelector:NSSelectorFromString(@"materialViewWithRecipe:options:initialWeight:")]) {
        material = ((id (*)(id, SEL, long long, unsigned long long, double))objc_msgSend)(
            MTMaterialViewClass,
            NSSelectorFromString(@"materialViewWithRecipe:options:initialWeight:"),
            (long long)4,
            (unsigned long long)0,
            1.0
        );
    }
    if (!material && [MTMaterialViewClass respondsToSelector:NSSelectorFromString(@"materialViewWithRecipe:")]) {
        material = ((id (*)(id, SEL, long long))objc_msgSend)(MTMaterialViewClass, NSSelectorFromString(@"materialViewWithRecipe:"), (long long)4);
    }
    if (material && [material respondsToSelector:NSSelectorFromString(@"setWeight:")]) {
        ((void (*)(id, SEL, double))objc_msgSend)(material, NSSelectorFromString(@"setWeight:"), 1.0);
    }
    if (material && [material respondsToSelector:NSSelectorFromString(@"setGroupName:")]) {
        ((void (*)(id, SEL, id))objc_msgSend)(material, NSSelectorFromString(@"setGroupName:"), @"ccMediaPlayer");
    }
    if (!material) {
        UIVisualEffectView *fallback = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThickMaterialDark]];
        fallback.alpha = 0.92;
        material = fallback;
    }

    material.frame = self.bounds;
    material.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    material.userInteractionEnabled = NO;
    material.layer.cornerCurve = kCACornerCurveContinuous;
    material.layer.masksToBounds = YES;
    material.layer.cornerRadius = self.layer.cornerRadius;
    [self insertSubview:material atIndex:0];
    self.blurView = material;

    self.backingView = [[UIView alloc] init];
    self.backingView.backgroundColor = [UIColor secondarySystemBackgroundColor];
    self.backingView.alpha = 0.0;
    self.backingView.userInteractionEnabled = NO;
    self.backingView.layer.cornerCurve = kCACornerCurveContinuous;
    self.backingView.layer.masksToBounds = YES;
    [self insertSubview:self.backingView atIndex:0];

    self.artworkContainer = [UIView new];
    self.artworkContainer.layer.cornerCurve = kCACornerCurveContinuous;
    self.artworkContainer.layer.masksToBounds = YES;
    self.artworkContainer.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.08];
    [self addSubview:self.artworkContainer];

    self.artworkView = [[UIImageView alloc] init];
    self.artworkView.contentMode = UIViewContentModeScaleAspectFill;
    self.artworkView.clipsToBounds = YES;
    [self.artworkContainer addSubview:self.artworkView];

    self.titleLabel = [UILabel new];
    self.titleLabel.textColor = UIColor.whiteColor;
    self.titleLabel.textAlignment = NSTextAlignmentLeft;
    self.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [self addSubview:self.titleLabel];

    self.artistLabel = [UILabel new];
    self.artistLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.6];
    self.artistLabel.textAlignment = NSTextAlignmentLeft;
    self.artistLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [self addSubview:self.artistLabel];

    self.progressTrack = [[UIView alloc] init];
    self.progressTrack.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.18];
    self.progressTrack.layer.masksToBounds = YES;
    self.progressTrack.userInteractionEnabled = NO;
    [self addSubview:self.progressTrack];

    self.progressFill = [[UIView alloc] init];
    self.progressFill.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.85];
    self.progressFill.layer.masksToBounds = YES;
    self.progressFill.userInteractionEnabled = NO;
    [self.progressTrack addSubview:self.progressFill];

    self.elapsedLabel = [UILabel new];
    self.elapsedLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.55];
    self.elapsedLabel.text = @"0:00";
    self.elapsedLabel.textAlignment = NSTextAlignmentLeft;
    [self addSubview:self.elapsedLabel];

    self.remainingLabel = [UILabel new];
    self.remainingLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.55];
    self.remainingLabel.text = @"-0:00";
    self.remainingLabel.textAlignment = NSTextAlignmentRight;
    [self addSubview:self.remainingLabel];

    self.prevButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.prevButton.tintColor = UIColor.whiteColor;
    [self.prevButton addTarget:self action:@selector(prevTapped) forControlEvents:UIControlEventTouchUpInside];

    self.playPauseButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.playPauseButton.tintColor = UIColor.whiteColor;
    self.playPauseButton.backgroundColor = UIColor.clearColor;
    [self.playPauseButton addTarget:self action:@selector(playPauseTapped) forControlEvents:UIControlEventTouchUpInside];

    self.nextButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.nextButton.tintColor = UIColor.whiteColor;
    [self.nextButton addTarget:self action:@selector(nextTapped) forControlEvents:UIControlEventTouchUpInside];

    [self addSubview:self.prevButton];
    [self addSubview:self.playPauseButton];
    [self addSubview:self.nextButton];

    self.volumeTrack = [[UIView alloc] init];
    self.volumeTrack.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.18];
    self.volumeTrack.layer.masksToBounds = YES;
    self.volumeTrack.userInteractionEnabled = NO;
    [self addSubview:self.volumeTrack];

    self.volumeFill = [[UIView alloc] init];
    self.volumeFill.backgroundColor = UIColor.whiteColor;
    self.volumeFill.layer.masksToBounds = YES;
    self.volumeFill.userInteractionEnabled = NO;
    [self.volumeTrack addSubview:self.volumeFill];

    self.decreaseVolumeIcon = [[UIImageView alloc] init];
    self.decreaseVolumeIcon.contentMode = UIViewContentModeScaleAspectFit;
    self.decreaseVolumeIcon.tintColor = UIColor.whiteColor;
    [self addSubview:self.decreaseVolumeIcon];

    self.increaseVolumeIcon = [[UIImageView alloc] init];
    self.increaseVolumeIcon.contentMode = UIViewContentModeScaleAspectFit;
    self.increaseVolumeIcon.tintColor = UIColor.whiteColor;
    [self addSubview:self.increaseVolumeIcon];

    self.airplayPill = [UIView new];
    self.airplayPill.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.10];
    self.airplayPill.layer.masksToBounds = YES;
    [self addSubview:self.airplayPill];

    self.airplayIconView = [[UIImageView alloc] init];
    self.airplayIconView.contentMode = UIViewContentModeScaleAspectFit;
    self.airplayIconView.tintColor = UIColor.whiteColor;
    [self.airplayPill addSubview:self.airplayIconView];

    self.airplayLabel = [UILabel new];
    self.airplayLabel.textColor = UIColor.whiteColor;
    self.airplayLabel.textAlignment = NSTextAlignmentLeft;
    self.airplayLabel.text = @"AirPlay";
    [self.airplayPill addSubview:self.airplayLabel];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refresh) name:UIApplicationDidBecomeActiveNotification object:nil];

    __weak typeof(self) weakSelf = self;
    self.refreshTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *t) {
        UIWindow *w = weakSelf.window;
        if (!w || w.hidden || w.alpha < 0.01) return;   // nothing to refresh while hidden
        [weakSelf refresh];
    }];

    [self refresh];
}

- (void)dealloc {
    [self stopMirroring];
    [self.refreshTimer invalidate];
    self.refreshTimer = nil;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (self.window && !self.embedded) [self startMirroring];
    else [self stopMirroring];
}

- (void)startMirroring {
    if (self.mirrorLink) return;
    self.mirrorLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(mirrorTick)];
    [self.mirrorLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)stopMirroring {
    [self.mirrorLink invalidate];
    self.mirrorLink = nil;
}

- (void)mirrorTick {
    if (self.embedded) return;   // the expanded-module copy is placed by the tweak, not mirrored
    UIWindow *tickWindow = self.window;
    if (!tickWindow || tickWindow.hidden || tickWindow.alpha < 0.01) return;   // Control Center not on screen
    BOOL notched = (CGRectGetHeight(UIScreen.mainScreen.bounds) >= 800.0);
    if (self.isAnimatingIn && !notched) return;

    // findSampleModuleView walks the whole module collection; this runs every frame while
    // Control Center is open, so reuse the cached sample until it actually goes stale instead
    // of re-walking the tree on every tick (same result, much less work per frame).
    UIView *sample = self.cachedSampleView;
    if (!sample || !sample.window) {
        sample = [self findSampleModuleView];
        if (sample) self.cachedSampleView = sample;
    }
    if (!sample) return;

    CALayer *pres = (CALayer *)sample.layer.presentationLayer;
    if (!pres) return;

    CATransform3D pt = pres.transform;
    CGAffineTransform t = CGAffineTransformMake(pt.m11, pt.m12, pt.m21, pt.m22, pt.m41, pt.m42);

    CGAffineTransform cur = self.transform;
    if (fabs(t.tx - cur.tx) < 0.5 &&
        fabs(t.ty - cur.ty) < 0.5 &&
        fabs(t.a  - cur.a ) < 0.005 &&
        fabs(t.b  - cur.b ) < 0.005 &&
        fabs(t.c  - cur.c ) < 0.005 &&
        fabs(t.d  - cur.d ) < 0.005) {
        return;
    }

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.transform = t;
    [CATransaction commit];
}

- (void)resetForPresentation {
    [self.layer removeAllAnimations];
    self.isAnimatingIn = NO;
    self.transform = CGAffineTransformIdentity;
    BOOL notched = (CGRectGetHeight(UIScreen.mainScreen.bounds) >= 800.0);
    self.alpha = notched ? 0.0 : 1.0;
    self.cachedSampleView = nil;
    if (self.window) [self startMirroring];
    [self refresh];
}

- (void)fadeIn {
    BOOL notched = (CGRectGetHeight(UIScreen.mainScreen.bounds) >= 800.0);
    if (notched) {
        [self.layer removeAllAnimations];
        [UIView animateWithDuration:0.30
                              delay:0.0
                            options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState
                         animations:^{ self.alpha = 1.0; }
                         completion:nil];
        return;
    }
    self.isAnimatingIn = YES;
    [self.layer removeAllAnimations];
    self.alpha = 0.0;
    self.transform = CGAffineTransformMakeTranslation(0, 90);
    [UIView animateWithDuration:0.30 delay:0.0
         usingSpringWithDamping:CC26SpringDamping(0.85) initialSpringVelocity:CC26SpringVelocity(0.5)
                        options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
        self.alpha = 1.0;
        self.transform = CGAffineTransformIdentity;
    } completion:^(BOOL finished) {
        self.isAnimatingIn = NO;
    }];
}

- (void)fadeOut {
    [self.layer removeAllAnimations];
    [UIView animateWithDuration:0.30 delay:0.0
                        options:UIViewAnimationOptionCurveEaseIn | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        self.alpha = 0.0;
    } completion:nil];
}

- (void)setBackingVisible:(BOOL)visible {
}

- (void)slideOut {
    [self.layer removeAllAnimations];
    CGFloat screenH = CGRectGetHeight(UIScreen.mainScreen.bounds);
    [UIView animateWithDuration:0.30 delay:0.0
                        options:UIViewAnimationOptionCurveEaseIn | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        self.transform = CGAffineTransformMakeTranslation(0, screenH * 0.5);
    } completion:^(BOOL finished) {
        self.alpha = 0.0;
        self.transform = CGAffineTransformIdentity;
    }];
}

- (void)slideOffScreen {
    self.isAnimatingIn = YES;
    [self.layer removeAllAnimations];

    CGFloat screenH = CGRectGetHeight(UIScreen.mainScreen.bounds);

    [UIView animateWithDuration:0.35
                          delay:0.0
                        options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        self.transform = CGAffineTransformMakeTranslation(0, screenH);
        self.alpha = 0.0;
    } completion:^(BOOL finished) {
        self.isAnimatingIn = NO;
    }];
}

- (UIView *)findSampleModuleView {
    UIView *root = self;
    while (root && ![NSStringFromClass(root.class) isEqualToString:@"CCUIModuleCollectionView"]) {
        root = root.superview;
    }
    if (!root) return nil;

    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:root];
    while (queue.count) {
        UIView *v = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if (v != self &&
            [NSStringFromClass(v.class) isEqualToString:@"CCUIContentModuleContainerView"] &&
            !v.hidden && v.alpha > 0.01) {
            return v;
        }
        [queue addObjectsFromArray:v.subviews];
    }

    queue = [NSMutableArray arrayWithObject:root];
    while (queue.count) {
        UIView *v = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if (v != self &&
            [NSStringFromClass(v.class) isEqualToString:@"CCUIContentModuleContainerView"]) {
            CALayer *pres = (CALayer *)v.layer.presentationLayer;
            if (pres && !CATransform3DIsIdentity(pres.transform)) {
                return v;
            }
        }
        [queue addObjectsFromArray:v.subviews];
    }
    return nil;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = CGRectGetWidth(self.bounds);
    CGFloat h = CGRectGetHeight(self.bounds);
    if (w < 1.0 || h < 1.0) return;

    // iOS 26 style: the big media card is much rounder than a regular module (~15% of the width).
    // Every other layer (material, backing, glass) copies this radius, so only it is set here.
    CGFloat cardRadius = MIN(floor(MIN(w, h) * 0.5), floor(w * 0.115));
    if (fabs(self.layer.cornerRadius - cardRadius) > 0.5) self.layer.cornerRadius = cardRadius;
    self.layer.cornerCurve = kCACornerCurveContinuous;

    self.blurView.layer.cornerRadius = self.layer.cornerRadius;
    self.backingView.frame = self.bounds;
    self.backingView.layer.cornerRadius = self.layer.cornerRadius;

    CGFloat padding = w * 0.071;   // iOS 26: artwork, title and bars share the same side margin
    CGFloat contentW = w - padding * 2;

    CGFloat titleH = w * 0.070;
    CGFloat artistH = w * 0.050;
    CGFloat progressH = w * 0.012;
    CGFloat timeH = w * 0.040;
    CGFloat playSize = w * 0.155;
    CGFloat sideSize = w * 0.135;
    CGFloat airplayH = w * 0.085;

    CGFloat gapControlsVolume = w * 0.020;
    CGFloat volumeRowH = w * 0.055;
    CGFloat gapVolumeAirplay = w * 0.035;

    CGFloat gapArtTitle = w * 0.048;
    CGFloat gapTitleArtist = w * 0.004;
    CGFloat gapArtistProgress = w * 0.038;
    CGFloat gapProgressTime = w * 0.014;
    CGFloat gapTimeControls = w * 0.005;

    CGFloat nonArtH =
        padding + gapArtTitle + titleH + gapTitleArtist + artistH +
        gapArtistProgress + progressH + gapProgressTime + timeH +
        gapTimeControls + playSize + gapControlsVolume + volumeRowH +
        gapVolumeAirplay + airplayH + padding;

    // iOS 26 layout measured on a 451x808 card: every row sits at a fixed fraction of the card
    // height, so when the player is taller or shorter everything is spread / tightened with it
    CGFloat artSize = MIN(contentW, h * 0.482);
    if (artSize < w * 0.3) artSize = w * 0.3;

    CGFloat y = h * 0.041;
    CGFloat artX = (w - artSize) * 0.5;

    self.artworkContainer.frame = CGRectMake(artX, y, artSize, artSize);
    self.artworkContainer.layer.cornerRadius = artSize * 0.06;
    self.artworkView.frame = self.artworkContainer.bounds;
    y = h * 0.574 - titleH * 0.5;

    self.titleLabel.frame = CGRectMake(padding, y, contentW, titleH);
    self.titleLabel.font = [UIFont systemFontOfSize:w * 0.055 weight:UIFontWeightBold];
    y = h * 0.607 - artistH * 0.5;

    self.artistLabel.frame = CGRectMake(padding, y, contentW, artistH);
    self.artistLabel.font = [UIFont systemFontOfSize:w * 0.038 weight:UIFontWeightRegular];
    y = h * 0.662 - w * 0.011;

    CGFloat progressTrackH = w * 0.022;
    self.progressTrack.frame = CGRectMake(padding, y, contentW, progressTrackH);
    self.progressTrack.layer.cornerRadius = progressTrackH * 0.5;

    CGFloat pct = self.progressPct;
    if (pct < 0.0) pct = 0.0;
    if (pct > 1.0) pct = 1.0;
    self.progressFill.frame = CGRectMake(0, 0, contentW * pct, progressTrackH);
    self.progressFill.layer.cornerRadius = progressTrackH * 0.5;
    y = h * 0.694 - timeH * 0.5;

    self.elapsedLabel.frame = CGRectMake(padding, y, w * 0.28, timeH);
    self.remainingLabel.frame = CGRectMake(w - padding - w * 0.28, y, w * 0.28, timeH);
    self.elapsedLabel.font = [UIFont systemFontOfSize:w * 0.032 weight:UIFontWeightMedium];
    self.remainingLabel.font = [UIFont systemFontOfSize:w * 0.032 weight:UIFontWeightMedium];
    y = h * 0.769 - playSize * 0.5;

    CGFloat controlsGap = w * 0.055;
    CGFloat totalW = sideSize * 2 + playSize + controlsGap * 2;
    CGFloat controlsX = (w - totalW) * 0.5;

    self.prevButton.frame = CGRectMake(controlsX, y + (playSize - sideSize) * 0.5, sideSize, sideSize);
    self.playPauseButton.frame = CGRectMake(controlsX + sideSize + controlsGap, y, playSize, playSize);
    self.nextButton.frame = CGRectMake(controlsX + sideSize + controlsGap + playSize + controlsGap, y + (playSize - sideSize) * 0.5, sideSize, sideSize);
    y = h * 0.873 - volumeRowH * 0.5;

    CGFloat volIconSize = w * 0.085;
    CGFloat volIconGap = w * 0.035;
    CGFloat volumePadding = w * 0.075;
    self.decreaseVolumeIcon.frame = CGRectMake(volumePadding,
                                               y + (volumeRowH - volIconSize) * 0.5,
                                               volIconSize, volIconSize);
    self.increaseVolumeIcon.frame = CGRectMake(w - volumePadding - volIconSize,
                                               y + (volumeRowH - volIconSize) * 0.5,
                                               volIconSize, volIconSize);

    CGFloat trackX = volumePadding + volIconSize + volIconGap;
    CGFloat trackW = w - volumePadding * 2 - (volIconSize + volIconGap) * 2;
    CGFloat trackH = w * 0.022;
    CGFloat trackY = y + (volumeRowH - trackH) * 0.5;
    self.volumeTrack.frame = CGRectMake(trackX, trackY, trackW, trackH);
    self.volumeTrack.layer.cornerRadius = trackH * 0.5;

    float currentVolume = [[AVAudioSession sharedInstance] outputVolume];
    if (currentVolume < 0.0) currentVolume = 0.0;
    if (currentVolume > 1.0) currentVolume = 1.0;
    CGFloat fillW = trackW * currentVolume;
    self.volumeFill.frame = CGRectMake(0, 0, fillW, trackH);
    self.volumeFill.layer.cornerRadius = trackH * 0.5;

    UIImageSymbolConfiguration *volConfig = [UIImageSymbolConfiguration configurationWithPointSize:volIconSize * 0.85 weight:UIImageSymbolWeightMedium];
    self.decreaseVolumeIcon.image = [UIImage systemImageNamed:@"speaker.wave.1.fill" withConfiguration:volConfig];
    self.increaseVolumeIcon.image = [UIImage systemImageNamed:@"speaker.wave.3.fill" withConfiguration:volConfig];

    y = h * 0.934 - airplayH * 0.5;

    UIFont *airplayFont = [UIFont systemFontOfSize:w * 0.034 weight:UIFontWeightMedium];
    self.airplayLabel.font = airplayFont;
    CGSize labelFit = [self.airplayLabel sizeThatFits:CGSizeMake(contentW, airplayH)];
    CGFloat iconSize = airplayH * 0.55;
    CGFloat iconGap = w * 0.014;
    CGFloat hPad = airplayH * 0.36;
    CGFloat pillW = hPad + iconSize + iconGap + labelFit.width + hPad;
    if (pillW > contentW) pillW = contentW;
    CGFloat pillX = (w - pillW) * 0.5;

    self.airplayPill.frame = CGRectMake(pillX, y, pillW, airplayH);
    self.airplayPill.layer.cornerRadius = airplayH * 0.5;

    self.airplayIconView.frame = CGRectMake(hPad, (airplayH - iconSize) * 0.5, iconSize, iconSize);
    self.airplayLabel.frame = CGRectMake(hPad + iconSize + iconGap, 0, labelFit.width, airplayH);

    UIImageSymbolConfiguration *airplayConfig = [UIImageSymbolConfiguration configurationWithPointSize:iconSize * 0.95 weight:UIImageSymbolWeightSemibold];
    self.airplayIconView.image = [[UIImage systemImageNamed:@"airplayaudio"] imageByApplyingSymbolConfiguration:airplayConfig];

    UIImageSymbolConfiguration *sideConfig = [UIImageSymbolConfiguration configurationWithPointSize:w * 0.068 weight:UIImageSymbolWeightSemibold];
    UIImageSymbolConfiguration *playConfig = [UIImageSymbolConfiguration configurationWithPointSize:w * 0.098 weight:UIImageSymbolWeightSemibold];
    [self.prevButton setImage:[UIImage systemImageNamed:@"backward.fill" withConfiguration:sideConfig] forState:UIControlStateNormal];
    [self.nextButton setImage:[UIImage systemImageNamed:@"forward.fill" withConfiguration:sideConfig] forState:UIControlStateNormal];
    NSString *symbol = self.isPlaying ? @"pause.fill" : @"play.fill";
    [self.playPauseButton setImage:[UIImage systemImageNamed:symbol withConfiguration:playConfig] forState:UIControlStateNormal];
}

- (void)refresh {
    InitMediaRemote();
    if (!MRMediaRemoteGetNowPlayingInfo) return;

    __weak typeof(self) weakSelf = self;
    @try {
        MRMediaRemoteGetNowPlayingInfo(dispatch_get_main_queue(), ^(CFDictionaryRef info) {
            @try {
                __strong typeof(weakSelf) strongSelf = weakSelf;
                if (!strongSelf) return;

                if (!info) {
                    strongSelf.titleLabel.text = @"Not Playing";
                    strongSelf.artistLabel.text = @"";
                    strongSelf.progressPct = 0.0;
                    strongSelf.elapsedLabel.text = @"0:00";
                    strongSelf.remainingLabel.text = @"-0:00";
                    strongSelf.isPlaying = NO;
                    strongSelf.artworkView.contentMode = UIViewContentModeCenter;
                    strongSelf.artworkView.tintColor = [UIColor colorWithWhite:1.0 alpha:0.3];
                    strongSelf.artworkView.image = nil;
                    [strongSelf setNeedsLayout];
                    return;
                }

                NSDictionary *dict = (__bridge NSDictionary *)info;
                if (![dict isKindOfClass:NSDictionary.class]) return;

                id titleObj    = dict[@"kMRMediaRemoteNowPlayingInfoTitle"];
                id artistObj   = dict[@"kMRMediaRemoteNowPlayingInfoArtist"];
                id artworkObj  = dict[@"kMRMediaRemoteNowPlayingInfoArtworkData"];
                id elapsedObj  = dict[@"kMRMediaRemoteNowPlayingInfoElapsedTime"];
                id durationObj = dict[@"kMRMediaRemoteNowPlayingInfoDuration"];
                id rateObj     = dict[@"kMRMediaRemoteNowPlayingInfoPlaybackRate"];

                NSString *title  = [titleObj  isKindOfClass:NSString.class] ? titleObj  : nil;
                NSString *artist = [artistObj isKindOfClass:NSString.class] ? artistObj : nil;
                NSData  *artwork = [artworkObj isKindOfClass:NSData.class]  ? artworkObj : nil;
                double elapsed   = [elapsedObj  respondsToSelector:@selector(doubleValue)] ? [elapsedObj  doubleValue] : 0.0;
                double duration  = [durationObj respondsToSelector:@selector(doubleValue)] ? [durationObj doubleValue] : 0.0;
                double rate      = [rateObj     respondsToSelector:@selector(doubleValue)] ? [rateObj     doubleValue] : 0.0;

                strongSelf.titleLabel.text  = title.length  ? title  : @"Not Playing";
                strongSelf.artistLabel.text = artist.length ? artist : @"";
                strongSelf.isPlaying = rate > 0.0;

                if (elapsed > 0 && duration > 0) {
                    strongSelf.progressPct = elapsed / duration;
                    strongSelf.elapsedLabel.text   = [NSString stringWithFormat:@"%d:%02d", (int)elapsed / 60, (int)elapsed % 60];
                    double remaining = duration - elapsed;
                    strongSelf.remainingLabel.text = [NSString stringWithFormat:@"-%d:%02d", (int)remaining / 60, (int)remaining % 60];
                } else {
                    strongSelf.progressPct = 0.0;
                    strongSelf.elapsedLabel.text   = @"0:00";
                    strongSelf.remainingLabel.text = @"-0:00";
                }

                if (artwork) {
                    UIImage *img = [UIImage imageWithData:artwork];
                    if (img) {
                        strongSelf.artworkView.contentMode = UIViewContentModeScaleAspectFill;
                        strongSelf.artworkView.tintColor = nil;
                        strongSelf.artworkView.image = img;
                    }
                } else {
                    strongSelf.artworkView.contentMode = UIViewContentModeCenter;
                    strongSelf.artworkView.tintColor = [UIColor colorWithWhite:1.0 alpha:0.3];
                    strongSelf.artworkView.image = nil;
                }

                [strongSelf setNeedsLayout];
            } @catch (NSException *e) {
                NSLog(@"[CC26Media] refresh block exception: %@", e.reason);
            }
        });
    } @catch (NSException *e) {
        NSLog(@"[CC26Media] refresh call exception: %@", e.reason);
    }
}

- (void)prevTapped {
    InitMediaRemote();
    if (MRMediaRemoteSendCommand) MRMediaRemoteSendCommand(5, nil);
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [weakSelf refresh]; });
}

- (void)nextTapped {
    InitMediaRemote();
    if (MRMediaRemoteSendCommand) MRMediaRemoteSendCommand(4, nil);
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [weakSelf refresh]; });
}

- (void)playPauseTapped {
    InitMediaRemote();
    if (MRMediaRemoteSendCommand) MRMediaRemoteSendCommand(2, nil);
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [weakSelf refresh]; });
}
@end