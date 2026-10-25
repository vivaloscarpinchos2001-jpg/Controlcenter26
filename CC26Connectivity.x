#import "CC26.h"
#import <CFNetwork/CFNetwork.h>

// ---------------------------------------------------------------------------
// Connectivity page (iOS 18 / iOS 26 layout, matches the reference video):
//
//   [ Airplane Mode            ]   pill
//   [ Wi-Fi   ] [ AirDrop    ]     cards
//   [ Cellular] [ Bluetooth  ]     cards
//   [ Personal Hotspot         ]   pill
//   [ VPN                      ]   pill (read-only)
//
// Nothing here reimplements radio logic. Each tile looks up the real
// CCUIConnectivity*ViewController that lives inside the stock Connectivity
// module, reads its button's selected state and fires the button's own
// actions when tapped. The tiles use the LiquidAss glass when it is installed
// (same filter the media page uses) and fall back to the module material.
// ---------------------------------------------------------------------------

UIView *CC26ConnectivityShowDetail(UIView *page, NSString *kind, CGRect frame);

static UIViewController *CC26FindConnectivityController(UIViewController *overlay) {
    if (!overlay) return nil;
    NSMutableArray<UIViewController *> *queue = [NSMutableArray arrayWithArray:overlay.childViewControllers];
    while (queue.count) {
        UIViewController *candidate = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if (IsConnectivityController(candidate)) return candidate;
        [queue addObjectsFromArray:candidate.childViewControllers];
    }
    return nil;
}

static UIControl *CC26ConnectivityButton(UIViewController *child) {
    if (!child || !child.isViewLoaded) return nil;
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:child.view];
    while (queue.count) {
        UIView *view = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if ([view isKindOfClass:UIControl.class]) return (UIControl *)view;
        [queue addObjectsFromArray:view.subviews];
    }
    return nil;
}

// iOS 26 artwork (SVG / CC18.bundle). With "iOS 26 Icons" off the tiles use the plain
// iOS 16 system symbols instead.
static NSString *CC26TileSystemName(NSString *name) {
    NSDictionary<NSString *, NSString *> *map = @{
        @"wifi": @"wifi",
        @"cellularbars": @"antenna.radiowaves.left.and.right",
        @"personalhotspot": @"link",
        @"network": @"network",
        @"airdrop": @"airdrop",
        @"bluetooth": @"wave.3.right",
        @"airplane": @"airplane",
    };
    return map[name] ?: name;
}

static UIImage *CC26TileSymbol(NSArray<NSString *> *names, CGFloat pointSize) {
    for (NSString *name in names) {
        UIImage *image = nil;
        if (gIOS26Icons || [name isEqualToString:@"cellularbars"]) {
            image = CC26SVGSymbol(name, pointSize) ?: CC26BundledSymbol(name, UIColor.whiteColor, NO);
        } else {
            UIImageSymbolConfiguration *plain =
                [UIImageSymbolConfiguration configurationWithPointSize:pointSize weight:UIImageSymbolWeightSemibold];
            image = [UIImage systemImageNamed:CC26TileSystemName(name) withConfiguration:plain];
        }
        if (!image) continue;
        if (!image.symbolConfiguration) {
            UIImageSymbolConfiguration *cfg =
                [UIImageSymbolConfiguration configurationWithPointSize:pointSize weight:UIImageSymbolWeightSemibold];
            image = [image imageByApplyingSymbolConfiguration:cfg] ?: image;
        }
        return [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    }
    return nil;
}

// VPN has no controller in the iOS 16 connectivity module, so we only read it:
// an active VPN adds a tun/ppp/ipsec interface to the scoped proxy settings.
static BOOL CC26VPNActive(void) {
    static CFAbsoluteTime lastCheck = 0.0;
    static BOOL cached = NO;
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (now - lastCheck < 2.0) return cached;
    lastCheck = now;
    BOOL active = NO;
    @try {
        CFDictionaryRef settings = CFNetworkCopySystemProxySettings();
        if (settings) {
            NSDictionary *scoped = ((__bridge NSDictionary *)settings)[@"__SCOPED__"];
            if ([scoped isKindOfClass:NSDictionary.class]) {
                for (NSString *key in scoped.allKeys) {
                    if ([key hasPrefix:@"tap"] || [key hasPrefix:@"tun"] || [key hasPrefix:@"utun"] ||
                        [key hasPrefix:@"ppp"] || [key hasPrefix:@"ipsec"]) { active = YES; break; }
                }
            }
            CFRelease(settings);
        }
    } @catch (__unused NSException *e) {}
    cached = active;
    return active;
}

#pragma mark - Stock iOS 16 glyphs (AirDrop / Bluetooth)

// AirDrop and Bluetooth have no iOS 26 artwork yet and no system symbol that matches, so the tiles
// reuse the exact glyph of the stock iOS 16 buttons (the ones the small module shows). The stock
// glyph is a Core Animation package: it is rendered once into a template image and cached.
UIViewController *CC26StockConnectivityForSplit(void);
static NSMutableDictionary<NSString *, UIImage *> *sCC26StockGlyphCache;

static UIView *CC26FindGlyphView(UIView *root) {
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithArray:root.subviews];
    UIView *imageFallback = nil;
    while (queue.count) {
        UIView *view = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if (view.tag == 181778) continue;   // our own replacement glyph
        if ([NSStringFromClass(view.class) isEqualToString:@"CCUICAPackageView"]) return view;
        if (!imageFallback && [view isKindOfClass:UIImageView.class] && ((UIImageView *)view).image) imageFallback = view;
        [queue addObjectsFromArray:view.subviews];
    }
    return imageFallback;
}

// crops to the visible pixels and scales so the longest side is maxDim points; nil when blank
static UIImage *CC26TrimmedTemplate(UIImage *source, CGFloat maxDim) {
    CGImageRef cg = source.CGImage;
    if (!cg) return nil;
    size_t w = CGImageGetWidth(cg), h = CGImageGetHeight(cg);
    if (w == 0 || h == 0 || w > 2000 || h > 2000) return nil;
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    NSMutableData *pixels = [NSMutableData dataWithLength:w * h * 4];
    CGContextRef ctx = CGBitmapContextCreate(pixels.mutableBytes, w, h, 8, w * 4, space,
                                             kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    if (!ctx) return nil;
    CGContextDrawImage(ctx, CGRectMake(0, 0, w, h), cg);
    CGContextRelease(ctx);
    const uint8_t *p = pixels.bytes;
    size_t minX = w, minY = h, maxX = 0, maxY = 0;
    BOOL any = NO;
    for (size_t y = 0; y < h; y++) {
        for (size_t xx = 0; xx < w; xx++) {
            if (p[(y * w + xx) * 4 + 3] > 12) {
                any = YES;
                if (xx < minX) minX = xx;
                if (xx > maxX) maxX = xx;
                if (y < minY) minY = y;
                if (y > maxY) maxY = y;
            }
        }
    }
    if (!any) return nil;
    CGRect crop = CGRectMake(minX, minY, maxX - minX + 1, maxY - minY + 1);
    CGImageRef cropped = CGImageCreateWithImageInRect(cg, crop);
    if (!cropped) return nil;
    CGFloat scale = source.scale > 0.0 ? source.scale : UIScreen.mainScreen.scale;
    CGSize natural = CGSizeMake(crop.size.width / scale, crop.size.height / scale);
    CGFloat factor = maxDim / MAX(natural.width, natural.height);
    CGSize target = CGSizeMake(ceil(natural.width * factor), ceil(natural.height * factor));
    UIImage *trimmed = [UIImage imageWithCGImage:cropped scale:scale orientation:UIImageOrientationUp];
    CGImageRelease(cropped);
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:target format:format];
    UIImage *scaled = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [trimmed drawInRect:CGRectMake(0, 0, target.width, target.height)];
    }];
    return [scaled imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

static UIImage *CC26StockGlyphImage(UIViewController *child, NSString *key, CGFloat maxDim) {
    if (!sCC26StockGlyphCache) sCC26StockGlyphCache = [NSMutableDictionary dictionary];
    UIImage *cached = sCC26StockGlyphCache[key];
    if (cached) return cached;
    if (!child || !child.isViewLoaded) return nil;
    UIView *glyph = CC26FindGlyphView(child.view);
    if (!glyph) return nil;
    UIImage *result = nil;
    if ([glyph isKindOfClass:UIImageView.class]) {
        UIImage *image = ((UIImageView *)glyph).image;
        if (image) {
            CGSize size = image.size;
            result = [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
            if (size.width < 1.0 || size.height < 1.0) result = nil;
        }
    } else {
        CGSize size = glyph.bounds.size;
        if (size.width < 4.0 || size.height < 4.0) return nil;
        UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
        format.opaque = NO;
        UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size format:format];
        UIImage *raw = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
            [glyph.layer renderInContext:context.CGContext];
        }];
        result = CC26TrimmedTemplate(raw, maxDim);
    }
    if (result) sCC26StockGlyphCache[key] = result;
    return result;
}

// Glyph for the separate modules: the same art the tiles use (iOS 26 SVG / the stock glyph).
UIImage *CC26SplitModuleGlyph(NSInteger kind, CGFloat pointSize) {
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:pointSize weight:UIImageSymbolWeightSemibold];
    UIImage *image = nil;
    switch (kind) {
        case 0: image = gIOS26Icons ? CC26SVGSymbol(@"wifi", pointSize) : nil;
                if (!image) image = [UIImage systemImageNamed:@"wifi" withConfiguration:cfg]; break;
        case 2: image = [UIImage systemImageNamed:@"airplane" withConfiguration:cfg]; break;
        case 3: image = CC26SVGSymbol(@"cellularbars", pointSize); break;
        case 5: image = gIOS26Icons ? CC26SVGSymbol(@"personalhotspot", pointSize) : nil;
                if (!image) image = [UIImage systemImageNamed:@"link" withConfiguration:cfg]; break;
        case 1:
        case 4: {
            NSString *className = kind == 1 ? @"CCUIConnectivityBluetoothViewController" : @"CCUIConnectivityAirDropViewController";
            UIViewController *stock = CC26StockConnectivityForSplit();
            image = CC26StockGlyphImage(stock ? CC26ConnectivityChild(stock, className) : nil, className, pointSize * 1.1);
            if (!image) image = [UIImage systemImageNamed:(kind == 1 ? @"wave.3.right" : @"airdrop") withConfiguration:cfg];
            break;
        }
    }
    return [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

#pragma mark - Tile

typedef NS_ENUM(NSInteger, CCAConnectivityTileStyle) {
    CCAConnectivityTileStyleCard = 0,
    CCAConnectivityTileStylePill = 1,
};

@interface CCAConnectivityTile : UIControl
@property (nonatomic, copy) NSString *controllerName;   // nil = read-only (VPN)
@property (nonatomic, copy) NSString *offText;
@property (nonatomic, copy) NSString *onText;
@property (nonatomic, assign) CCAConnectivityTileStyle style;
@property (nonatomic, assign) BOOL showsChevron;
@property (nonatomic, strong) UIColor *activeColor;
@property (nonatomic, strong) UIView *materialView;
@property (nonatomic, strong) UIView *iconBackground;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, assign) BOOL stateOn;
@property (nonatomic, assign) BOOL stateAvailable;
@property (nonatomic, assign) CGSize lastGlassSize;
@property (nonatomic, assign) BOOL applyingGlass;
@property (nonatomic, assign) BOOL glassLive;
@property (nonatomic, copy) NSArray<NSString *> *symbolNames;
@property (nonatomic, assign) BOOL iconsAre26;
@property (nonatomic, assign) CGFloat lastGlassRadius;
@property (nonatomic, assign) BOOL usesStockGlyph;
@property (nonatomic, assign) CFAbsoluteTime lastGlyphAttempt;
- (void)adoptStockGlyphFromController:(UIViewController *)child;
- (instancetype)initWithSpec:(NSDictionary *)spec;
- (void)applyStateOn:(BOOL)on available:(BOOL)available animated:(BOOL)animated;
@end

@implementation CCAConnectivityTile

- (instancetype)initWithSpec:(NSDictionary *)spec {
    if ((self = [super initWithFrame:CGRectZero])) {
        self.controllerName = spec[@"c"];
        self.offText = spec[@"off"];
        self.onText = spec[@"on"];
        self.style = [spec[@"pill"] boolValue] ? CCAConnectivityTileStylePill : CCAConnectivityTileStyleCard;
        self.showsChevron = [spec[@"chevron"] boolValue];
        self.activeColor = spec[@"k"];
        self.clipsToBounds = YES;
        self.layer.cornerCurve = kCACornerCurveContinuous;

        UIView *material = CC26ModuleMaterial();
        material.userInteractionEnabled = NO;
        [self addSubview:material];
        self.materialView = material;

        UIView *iconBg = [UIView new];
        iconBg.userInteractionEnabled = NO;
        [self addSubview:iconBg];
        self.iconBackground = iconBg;

        self.symbolNames = spec[@"s"];
        self.iconsAre26 = gIOS26Icons;
        UIImageView *icon = [[UIImageView alloc] initWithImage:CC26TileSymbol(spec[@"s"], 22.0)];
        icon.contentMode = UIViewContentModeCenter;
        icon.tintColor = UIColor.whiteColor;
        icon.userInteractionEnabled = NO;
        [self addSubview:icon];
        self.iconView = icon;

        UILabel *titleLabel = [UILabel new];
        titleLabel.text = spec[@"t"];
        titleLabel.textColor = UIColor.whiteColor;
        titleLabel.font = [UIFont systemFontOfSize:15.5 weight:UIFontWeightSemibold];
        titleLabel.adjustsFontSizeToFitWidth = YES;
        titleLabel.minimumScaleFactor = 0.75;
        titleLabel.userInteractionEnabled = NO;
        [self addSubview:titleLabel];
        self.titleLabel = titleLabel;

        UILabel *statusLabel = [UILabel new];
        statusLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.66];
        statusLabel.font = [UIFont systemFontOfSize:13.5 weight:UIFontWeightMedium];
        statusLabel.userInteractionEnabled = NO;
        [self addSubview:statusLabel];
        self.statusLabel = statusLabel;

        if (!self.controllerName && ![spec[@"vpn"] boolValue]) self.userInteractionEnabled = NO;
        if ([spec[@"vpn"] boolValue]) self.userInteractionEnabled = NO;

        [self applyStateOn:NO available:YES animated:NO];
    }
    return self;
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (self.window) [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = CGRectGetWidth(self.bounds);
    CGFloat h = CGRectGetHeight(self.bounds);
    BOOL pill = (self.style == CCAConnectivityTileStylePill);
    CGFloat k = pill ? h / 96.0 : h / 215.0;   // reference px -> pt

    // corner radius: cards fixed, pills follow "Circular Modules"
    CGFloat radius = CC26ConnectivityTileRadius(self.bounds.size, pill);
    self.layer.cornerRadius = radius;
    self.materialView.frame = self.bounds;
    self.materialView.layer.cornerRadius = radius;
    self.materialView.layer.cornerCurve = kCACornerCurveContinuous;

    // iOS 26 Icons switch: swap the artwork live
    if (!self.usesStockGlyph && self.iconsAre26 != gIOS26Icons) {
        self.iconsAre26 = gIOS26Icons;
        UIImage *swapped = CC26TileSymbol(self.symbolNames, 22.0);
        if (swapped) self.iconView.image = swapped;
    }

    // same material as the regular modules (and the media page): the module material, replaced
    // by the LiquidAss glass when that tweak is installed. No fill, rim or sheen of our own.
    // The glass is applied only when the size/radius changes (and never re-entrantly):
    // installing it reorders subviews, which would otherwise re-trigger layout forever.
    if (!self.applyingGlass && self.bounds.size.width > 4.0) {
        BOOL resized = !CGSizeEqualToSize(self.bounds.size, self.lastGlassSize) || fabs(radius - self.lastGlassRadius) > 0.5;
        if (resized || !self.glassLive) {
            self.applyingGlass = YES;
            self.lastGlassSize = self.bounds.size;
            self.lastGlassRadius = radius;
            BOOL live = NO;
            @try { live = CC26LIQApplyGlass(self, radius); } @catch (__unused NSException *e) { live = NO; }
            // the glass computes its edge / specular from its size: rebuild it when the tile changed size
            if (live && resized) @try { CC26LIQRefreshGlass(self); } @catch (__unused NSException *e) {}
    self.glassLive = live;
            self.applyingGlass = NO;
        }
    }
    self.materialView.hidden = self.glassLive;
    self.layer.backgroundColor = nil;
    self.layer.borderWidth = 0.0;

    CGFloat d = floor(63.0 * k);
    CGFloat pad = floor(20.0 * k);
    CGFloat iconY = pill ? floor((h - d) * 0.5) : floor(21.0 * k);
    self.iconBackground.frame = CGRectMake(pad, iconY, d, d);
    self.iconBackground.layer.cornerRadius = d * 0.5;
    self.iconView.frame = self.iconBackground.frame;

    if (pill) {
        CGFloat tx = floor(95.0 * k);
        CGFloat tw = MAX(10.0, w - tx - pad);
        self.titleLabel.frame = CGRectMake(tx, floor(h * 0.5 - 12.0 * k - 10.0), tw, 20.0);
        self.statusLabel.frame = CGRectMake(tx, floor(h * 0.5 + 14.0 * k - 9.0), tw, 18.0);
    } else {
        CGFloat tx = floor(26.0 * k);
        CGFloat tw = MAX(10.0, w - tx - floor(14.0 * k));
        self.titleLabel.frame = CGRectMake(tx, floor(h * (142.0 / 215.0)), tw, 20.0);
        self.statusLabel.frame = CGRectMake(tx, floor(h * (169.0 / 215.0)), tw, 18.0);
    }
}

// AirDrop / Bluetooth: the exact iOS 16 stock glyph, in both icon modes
- (void)adoptStockGlyphFromController:(UIViewController *)child {
    if (self.usesStockGlyph) return;
    NSString *name = self.controllerName ?: @"";
    if (![name containsString:@"Bluetooth"] && ![name containsString:@"AirDrop"]) return;
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (now - self.lastGlyphAttempt < 2.0) return;   // do not re-render the stock glyph every refresh
    self.lastGlyphAttempt = now;
    UIImage *image = CC26StockGlyphImage(child, name, 24.0);
    if (!image) return;
    self.usesStockGlyph = YES;
    self.iconView.image = image;
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    CGFloat pressed = (self.style == CCAConnectivityTileStylePill) ? 0.97 : 0.95;
    CGFloat s = highlighted ? pressed : 1.0;
    [UIView animateWithDuration:highlighted ? 0.18 : 0.6
                          delay:0.0
         usingSpringWithDamping:highlighted ? 0.9 : CC26SpringDamping(0.42)
          initialSpringVelocity:highlighted ? 0.0 : CC26SpringVelocity(6.0)
                        options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{ self.transform = CGAffineTransformMakeScale(s, s); }
                     completion:nil];
}

- (void)updateStatusText {
    NSString *text = !self.stateAvailable ? @"Unavailable" : (self.stateOn ? self.onText : self.offText);
    if (!self.showsChevron || !self.stateAvailable) {
        self.statusLabel.text = text;
        return;
    }
    NSMutableAttributedString *attributed = [[NSMutableAttributedString alloc] initWithString:[text stringByAppendingString:@" "]];
    UIImageSymbolConfiguration *cfg =
        [UIImageSymbolConfiguration configurationWithPointSize:10.0 weight:UIImageSymbolWeightSemibold];
    UIImage *chevron = [UIImage systemImageNamed:@"chevron.up.chevron.down" withConfiguration:cfg];
    if (chevron) {
        NSTextAttachment *attachment = [NSTextAttachment new];
        attachment.image = [chevron imageWithTintColor:[UIColor colorWithWhite:1.0 alpha:0.66]
                                         renderingMode:UIImageRenderingModeAlwaysOriginal];
        [attributed appendAttributedString:[NSAttributedString attributedStringWithAttachment:attachment]];
    }
    self.statusLabel.attributedText = attributed;
}

- (void)applyStateOn:(BOOL)on available:(BOOL)available animated:(BOOL)animated {
    BOOL changed = (on != self.stateOn) || (available != self.stateAvailable);
    self.stateOn = on;
    self.stateAvailable = available;
    [self updateStatusText];

    UIColor *circle = (on && available && self.activeColor)
        ? self.activeColor
        : [UIColor colorWithWhite:1.0 alpha:0.24];
    void (^apply)(void) = ^{
        self.iconBackground.backgroundColor = circle;
        self.alpha = available ? 1.0 : 0.5;
    };
    if (animated && changed) {
        [UIView animateWithDuration:0.3 delay:0.0
                            options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState
                         animations:apply completion:nil];
    } else {
        apply();
    }
}

@end

#pragma mark - Page

// reference layout, in px of the 576px wide reference screenshot (content is 451px wide)
static const CGFloat kRefW = 451.0;
static const CGFloat kRefH = 808.0;

@interface CCAConnectivityPageView ()
@property (nonatomic, strong) NSArray<CCAConnectivityTile *> *tiles;
@property (nonatomic, strong) NSTimer *timer;
@end

@implementation CCAConnectivityPageView

// The stock Control Center walks the subviews of the module collection and sends them
// module-only selectors (e.g. -c2AnimationContainerView). Like the other custom pages of
// this tweak, swallow anything we don't implement and answer nil instead of crashing.
- (BOOL)respondsToSelector:(SEL)aSelector {
    if ([super respondsToSelector:aSelector]) return YES;
    return NO;
}
- (id)forwardingTargetForSelector:(SEL)aSelector { return nil; }
- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector {
    NSMethodSignature *sig = [super methodSignatureForSelector:aSelector];
    if (!sig) sig = [NSMethodSignature signatureWithObjCTypes:"@@:"];
    return sig;
}
- (void)forwardInvocation:(NSInvocation *)anInvocation {
    id nilValue = nil;
    if (anInvocation.methodSignature.methodReturnLength == sizeof(id)) {
        [anInvocation setReturnValue:&nilValue];
    }
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = UIColor.clearColor;
        self.userInteractionEnabled = YES;

        UIColor *orange = [UIColor colorWithRed:1.00 green:0.62 blue:0.04 alpha:1.0];
        UIColor *green  = [UIColor colorWithRed:0.20 green:0.78 blue:0.35 alpha:1.0];
        UIColor *blue   = [UIColor colorWithRed:0.04 green:0.52 blue:1.00 alpha:1.0];

        NSArray<NSDictionary *> *spec = @[
            @{@"t": @"Airplane Mode", @"c": @"CCUIConnectivityAirplaneViewController",
              @"s": @[@"airplane"], @"k": orange, @"pill": @YES, @"off": @"Off", @"on": @"On"},
            @{@"t": @"Wi-Fi", @"c": @"CCUIConnectivityWifiViewController",
              @"s": @[@"wifi"], @"k": blue, @"chevron": @YES, @"off": @"Off", @"on": @"On"},
            @{@"t": @"AirDrop", @"c": @"CCUIConnectivityAirDropViewController",
              @"s": @[@"airdrop"], @"k": blue, @"chevron": @YES,
              @"off": @"Receiving Off", @"on": @"Receiving On"},
            @{@"t": @"Cellular Data", @"c": @"CCUIConnectivityCellularDataViewController",
              @"s": @[@"cellularbars"], @"k": green, @"off": @"Off", @"on": @"On"},
            @{@"t": @"Bluetooth", @"c": @"CCUIConnectivityBluetoothViewController",
              @"s": @[@"bluetooth"], @"k": blue, @"chevron": @YES, @"off": @"Off", @"on": @"On"},
            @{@"t": @"Personal Hotspot", @"c": @"CCUIConnectivityHotspotViewController",
              @"s": @[@"personalhotspot"], @"k": green, @"pill": @YES, @"off": @"Off", @"on": @"On"},
            @{@"t": @"VPN", @"vpn": @YES,
              @"s": @[@"network"], @"k": blue, @"pill": @YES,
              @"off": @"Off", @"on": @"Connected"},
        ];

        NSMutableArray<CCAConnectivityTile *> *tiles = [NSMutableArray array];
        for (NSDictionary *item in spec) {
            CCAConnectivityTile *tile = [[CCAConnectivityTile alloc] initWithSpec:item];
            if (tile.controllerName) {
                [tile addTarget:self action:@selector(tileTapped:) forControlEvents:UIControlEventTouchUpInside];
                if (tile.showsChevron) {
                    // long press: Wi-Fi networks / Bluetooth devices / AirDrop options
                    UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(tileHeld:)];
                    hold.minimumPressDuration = 0.4;
                    [tile addGestureRecognizer:hold];
                }
            }
            [self addSubview:tile];
            [tiles addObject:tile];
        }
        self.tiles = tiles;
    }
    return self;
}

- (void)dealloc {
    [self.timer invalidate];
}

CGFloat CC26ConnectivityExpandedHeightForWidth(CGFloat width) {
    const CGFloat pad = 12.0;
    return ceil((width - pad * 2.0) / kRefW * kRefH + pad * 2.0);
}

- (CGFloat)contentWidthForWidth:(CGFloat)width {
    if (self.embedded) {
        const CGFloat pad = 12.0;
        // fit the module WIDTH (like iOS 26: about 80% of the screen). The stock box is shorter
        // than that, so the layout may overflow it; the box background is hidden meanwhile.
        CGFloat byWidth = width - pad * 2.0;
        CGFloat screenH = CGRectGetHeight(UIScreen.mainScreen.bounds);
        CGFloat byScreen = (screenH - 110.0 - pad * 2.0) / kRefH * kRefW;   // never taller than the screen
        return floor(MAX(1.0, MIN(byWidth, byScreen)));
    }
    if (self.fitsGrid) {   // stock module width, uniformly shrunk when the screen is too short
        CGFloat fit = floor(width);
        if (self.availableHeight > 100.0) fit = MIN(fit, floor(self.availableHeight / kRefH * kRefW));
        return fit;
    }
    // width of the real module grid (same one page 0 uses); ratio fallback if unknown
    CGRect grid = CC26VisibleModuleBounds(CC26OverlayForView(self));
    CGFloat w = CGRectIsNull(grid) ? 0.0 : CGRectGetWidth(grid);
    CGFloat contentW = (w > 100.0 && w < width) ? floor(w) : floor(width * 0.785);
    // never taller than the band under the status bar: shrink the whole layout instead
    if (self.availableHeight > 100.0) {
        contentW = MIN(contentW, floor(self.availableHeight / kRefH * kRefW));
    }
    return contentW;
}

- (CGFloat)preferredHeightForWidth:(CGFloat)width {
    return ceil([self contentWidthForWidth:width] / kRefW * kRefH);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = CGRectGetWidth(self.bounds);
    CGFloat contentW = [self contentWidthForWidth:w];
    CGFloat k = contentW / kRefW;
    CGFloat x0 = floor((w - contentW) * 0.5);
    CGFloat y0 = self.embedded ? floor((CGRectGetHeight(self.bounds) - contentW / kRefW * kRefH) * 0.5) : 0.0;
    CGFloat ky = k;                                      // same scale both ways: nothing gets squashed
    if (!self.embedded && self.fitsGrid) y0 = 0.0;      // starts at the stock top, like iOS 26

    // {x, y, w, h} in reference px, same order as the spec above
    static const CGFloat frames[7][4] = {
        {  0,   0, 451,  96},   // Airplane
        {  0, 118, 214, 215},   // Wi-Fi
        {237, 118, 214, 215},   // AirDrop
        {  0, 356, 214, 215},   // Cellular
        {237, 356, 214, 215},   // Bluetooth
        {  0, 593, 451,  97},   // Hotspot
        {  0, 711, 451,  97},   // VPN
    };
    [self.tiles enumerateObjectsUsingBlock:^(CCAConnectivityTile *tile, NSUInteger index, BOOL *stop) {
        if (index >= 7) return;
        CGRect frame = CGRectMake(x0 + floor(frames[index][0] * k), y0 + floor(frames[index][1] * ky),
                                  floor(frames[index][2] * k), floor(frames[index][3] * ky));
        // bounds/center (not frame) so a tile mid-bounce keeps its transform
        tile.bounds = CGRectMake(0.0, 0.0, frame.size.width, frame.size.height);
        tile.center = CGPointMake(CGRectGetMidX(frame), CGRectGetMidY(frame));
    }];
}

#pragma mark Stretch

// iOS 26 style arrival: tiles stretch vertically, bottom rows first, then settle
// with a spring that overshoots the *size* of the tile (not its position).
- (void)playStretchIn {
    NSUInteger n = self.tiles.count;
    if (!gBouncyAnimations) {
        // bounce off: plain fade, no stretch
        for (CCAConnectivityTile *tile in self.tiles) {
            tile.transform = CGAffineTransformIdentity;
            tile.alpha = 0.0;
            [UIView animateWithDuration:0.22 delay:0.0
                                options:UIViewAnimationOptionAllowUserInteraction
                             animations:^{ tile.alpha = tile.stateAvailable ? 1.0 : 0.5; }
                             completion:nil];
        }
        return;
    }
    for (NSUInteger i = 0; i < n; i++) {
        CCAConnectivityTile *tile = self.tiles[i];
        NSUInteger rank = n - 1 - i;                       // bottom first
        tile.layer.anchorPoint = CGPointMake(0.5, 0.5);
        tile.transform = CGAffineTransformMake(0.94, 0, 0, 1.22, 0, 38.0);
        tile.alpha = 0.0;
        [UIView animateWithDuration:0.62 delay:0.035 * rank
             usingSpringWithDamping:0.58 initialSpringVelocity:0.0
                            options:UIViewAnimationOptionAllowUserInteraction
                         animations:^{ tile.transform = CGAffineTransformIdentity; }
                         completion:nil];
        [UIView animateWithDuration:0.22 delay:0.035 * rank
                            options:UIViewAnimationOptionAllowUserInteraction
                         animations:^{ tile.alpha = tile.stateAvailable ? 1.0 : 0.5; }
                         completion:nil];
    }
}

#pragma mark State

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (self.window) [self startTimer];
    else [self stopTimer];
}

- (void)startTimer {
    if (self.timer) return;
    __weak CCAConnectivityPageView *weakSelf = self;
    self.timer = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *timer) {
        CCAConnectivityPageView *strongSelf = weakSelf;
        if (!strongSelf) { [timer invalidate]; return; }
        UIWindow *window = strongSelf.window;
        if (!window || window.hidden || window.alpha < 0.01) return;
        if (!strongSelf.embedded && (gCurrentPage != CC26ConnectivityPageIndex() || gCCAModuleExpanded)) return;
        [strongSelf refreshStatesAnimated:YES];
    }];
}

- (void)stopTimer {
    [self.timer invalidate];
    self.timer = nil;
}

- (UIViewController *)connectivityController {
    if (self.hostController) return self.hostController;
    return CC26FindConnectivityController(CC26OverlayForView(self));
}

- (void)refreshStatesAnimated:(BOOL)animated {
    @try {
    UIViewController *connectivity = [self connectivityController];
    for (CCAConnectivityTile *tile in self.tiles) {
        if (!tile.controllerName) {   // VPN
            [tile applyStateOn:CC26VPNActive() available:YES animated:animated];
            continue;
        }
        UIControl *button = connectivity
            ? CC26ConnectivityButton(CC26ConnectivityChild(connectivity, tile.controllerName))
            : nil;
        [tile applyStateOn:(button && button.selected) available:(button != nil) animated:animated];
        if (connectivity && !tile.usesStockGlyph) {
            [tile adoptStockGlyphFromController:CC26ConnectivityChild(connectivity, tile.controllerName)];
        }
    }
    } @catch (__unused NSException *e) {}
}

- (void)refreshStates {
    [self refreshStatesAnimated:NO];
}

#pragma mark Actions

- (void)tileHeld:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    CCAConnectivityTile *tile = (CCAConnectivityTile *)gesture.view;
    NSString *name = tile.controllerName ?: @"";
    NSString *kind = [name containsString:@"Wifi"] ? @"wifi" : ([name containsString:@"Bluetooth"] ? @"bluetooth" : ([name containsString:@"AirDrop"] ? @"airdrop" : nil));
    if (!kind || !self.tiles.count) return;
    Haptic();
    if (!gMenu26) {   // iOS 18 mode: the stock iOS 16 menu instead of our panel
        UIViewController *stockController = self.hostController ?: [self connectivityController];
        CC26FireStockLongPress(stockController, name);
        return;
    }
    CC26ConnectivityShowDetail(self, kind, tile.frame);   // the menu grows out of the pressed tile
}

- (void)tileTapped:(CCAConnectivityTile *)tile {
    if (!tile.stateAvailable) return;
    UIViewController *connectivity = [self connectivityController];
    UIViewController *child = connectivity ? CC26ConnectivityChild(connectivity, tile.controllerName) : nil;
    UIControl *button = CC26ConnectivityButton(child);
    if (!button) return;

    Haptic();

    BOOL fired = NO;
    NSMutableSet<NSString *> *sent = [NSMutableSet set];
    NSArray<NSNumber *> *events = @[@(UIControlEventTouchUpInside), @(UIControlEventPrimaryActionTriggered)];
    for (id target in button.allTargets.allObjects) {
        if (target == NSNull.null) continue;
        for (NSNumber *event in events) {
            NSArray<NSString *> *actions = [button actionsForTarget:target forControlEvent:(UIControlEvents)event.unsignedIntegerValue];
            for (NSString *action in actions) {
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
        if ([child respondsToSelector:fallback]) {
            ((void (*)(id, SEL, id))objc_msgSend)(child, fallback, button);
            fired = YES;
        }
    }
    if (!fired) return;

    // optimistic flip, then confirm with the real state
    [tile applyStateOn:!tile.stateOn available:YES animated:YES];
    __weak CCAConnectivityPageView *weakSelf = self;
    for (NSNumber *delay in @[@0.35, @1.0]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ [weakSelf refreshStatesAnimated:YES]; });
    }
}

@end
