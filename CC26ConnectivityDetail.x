#import "CC26.h"
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <objc/message.h>
#import <objc/runtime.h>

// ---------------------------------------------------------------------------
// Detail sections of the Connectivity page (long press on Wi-Fi / Bluetooth / AirDrop):
//   Wi-Fi      -> nearby networks (MobileWiFi scan)
//   Bluetooth  -> paired devices (BluetoothManager), tap to connect / disconnect
//   AirDrop    -> Receiving Off / Contacts Only / Everyone (SFAirDropDiscoveryController)
//
// Everything private is looked up at runtime (dlopen / dlsym / NSClassFromString) and every
// call is guarded, so a missing symbol on some iOS version only leaves a section empty and
// can never take SpringBoard down.
// ---------------------------------------------------------------------------

static const NSInteger kCCADetailTag = 187001;

#pragma mark - MobileWiFi

typedef void *CCAWFRef;
typedef CCAWFRef (*CCAWFManagerCreate)(CFAllocatorRef, CFOptionFlags);
typedef void (*CCAWFManagerSchedule)(CCAWFRef, CFRunLoopRef, CFStringRef);
typedef CFArrayRef (*CCAWFCopyArray)(CCAWFRef);
typedef CCAWFRef (*CCAWFCopyCurrent)(CCAWFRef);
typedef CFStringRef (*CCAWFNetworkSSID)(CCAWFRef);
typedef CFTypeRef (*CCAWFNetworkProp)(CCAWFRef, CFStringRef);
typedef void (*CCAWFScanCallback)(CCAWFRef, CFArrayRef, CFErrorRef, void *);
typedef int (*CCAWFScan)(CCAWFRef, CFDictionaryRef, CCAWFScanCallback, void *);

static CCAWFRef sCCAWFManager = NULL;
static void (^sCCAScanDone)(NSArray<NSDictionary *> *) = nil;

static void *CCAWFSym(const char *name) {
    static void *handle = NULL;
    if (!handle) handle = dlopen("/System/Library/PrivateFrameworks/MobileWiFi.framework/MobileWiFi", RTLD_LAZY);
    return handle ? dlsym(handle, name) : NULL;
}

static NSDictionary *CCAWFDescribe(CCAWFRef network, BOOL current) {
    CCAWFNetworkSSID getSSID = (CCAWFNetworkSSID)CCAWFSym("WiFiNetworkGetSSID");
    CCAWFNetworkProp getProp = (CCAWFNetworkProp)CCAWFSym("WiFiNetworkGetProperty");
    if (!network || !getSSID) return nil;
    NSString *ssid = (__bridge NSString *)getSSID(network);
    if (![ssid isKindOfClass:NSString.class] || !ssid.length) return nil;
    NSInteger rssi = -100;
    BOOL secured = NO;
    if (getProp) {
        CFTypeRef value = getProp(network, CFSTR("RSSI"));
        if (value && CFGetTypeID(value) == CFNumberGetTypeID()) {
            int r = 0;
            CFNumberGetValue((CFNumberRef)value, kCFNumberIntType, &r);
            rssi = r;
        }
        for (NSString *key in @[@"RSN_IE", @"WPA_IE", @"WEP", @"IsSecure"]) {
            CFTypeRef p = getProp(network, (__bridge CFStringRef)key);
            if (p) { secured = YES; break; }
        }
    }
    return @{@"ssid": [ssid copy], @"rssi": @(rssi), @"secured": @(secured), @"current": @(current)};
}

static void CCAWFScanFinished(CCAWFRef device, CFArrayRef results, CFErrorRef error, void *ctx) {
    NSMutableArray<NSDictionary *> *found = [NSMutableArray array];
    @try {
        if (results) {
            for (CFIndex i = 0; i < CFArrayGetCount(results); i++) {
                NSDictionary *d = CCAWFDescribe((CCAWFRef)CFArrayGetValueAtIndex(results, i), NO);
                if (d) [found addObject:d];
            }
        }
    } @catch (__unused NSException *e) {}
    dispatch_async(dispatch_get_main_queue(), ^{
        void (^done)(NSArray<NSDictionary *> *) = sCCAScanDone;
        sCCAScanDone = nil;
        if (done) done(found);
    });
}

// calls `done` once on the main queue with the nearby networks (current one first)
static void CCAScanWiFi(void (^done)(NSArray<NSDictionary *> *)) {
    CCAWFManagerCreate create = (CCAWFManagerCreate)CCAWFSym("WiFiManagerClientCreate");
    CCAWFCopyArray copyDevices = (CCAWFCopyArray)CCAWFSym("WiFiManagerClientCopyDevices");
    CCAWFCopyCurrent copyCurrent = (CCAWFCopyCurrent)CCAWFSym("WiFiDeviceClientCopyCurrentNetwork");
    CCAWFScan scan = (CCAWFScan)CCAWFSym("WiFiDeviceClientScanAsync");
    if (!create || !copyDevices || !scan) { done(@[]); return; }

    if (!sCCAWFManager) {
        sCCAWFManager = create(kCFAllocatorDefault, 0);
        CCAWFManagerSchedule schedule = (CCAWFManagerSchedule)CCAWFSym("WiFiManagerClientScheduleWithRunLoop");
        if (sCCAWFManager && schedule) schedule(sCCAWFManager, CFRunLoopGetMain(), kCFRunLoopDefaultMode);
    }
    if (!sCCAWFManager) { done(@[]); return; }

    CFArrayRef devices = copyDevices(sCCAWFManager);
    if (!devices || CFArrayGetCount(devices) == 0) {
        if (devices) CFRelease(devices);
        done(@[]);
        return;
    }
    CCAWFRef device = (CCAWFRef)CFArrayGetValueAtIndex(devices, 0);

    __block NSDictionary *current = nil;
    if (copyCurrent) {
        CCAWFRef net = copyCurrent(device);
        if (net) {
            current = CCAWFDescribe(net, YES);
            CFRelease(net);
        }
    }

    __block BOOL finished = NO;
    void (^finish)(NSArray<NSDictionary *> *) = ^(NSArray<NSDictionary *> *found) {
        if (finished) return;
        finished = YES;
        NSMutableArray<NSDictionary *> *all = [NSMutableArray array];
        NSMutableSet<NSString *> *seen = [NSMutableSet set];
        if (current) { [all addObject:current]; [seen addObject:current[@"ssid"]]; }
        NSArray *sorted = [found sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
            return [b[@"rssi"] compare:a[@"rssi"]];
        }];
        for (NSDictionary *d in sorted) {
            if ([seen containsObject:d[@"ssid"]]) continue;
            [seen addObject:d[@"ssid"]];
            [all addObject:d];
        }
        done(all);
    };
    sCCAScanDone = finish;
    int rc = -1;
    @try { rc = scan(device, (__bridge CFDictionaryRef)@{}, CCAWFScanFinished, NULL); } @catch (__unused NSException *e) {}
    CFRelease(devices);
    if (rc != 0 && rc != -1) { /* some versions return a non-zero handle: still wait */ }
    if (rc == -1) { sCCAScanDone = nil; finish(@[]); return; }
    // never wait forever
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(7.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!finished) { sCCAScanDone = nil; finish(@[]); }
    });
}

#pragma mark - Bluetooth / AirDrop

static id CCABluetoothManager(void) {
    static BOOL loaded = NO;
    if (!loaded) {
        loaded = YES;
        dlopen("/System/Library/PrivateFrameworks/BluetoothManager.framework/BluetoothManager", RTLD_LAZY);
    }
    Class cls = NSClassFromString(@"BluetoothManager");
    SEL sel = NSSelectorFromString(@"sharedInstance");
    if (!cls || ![cls respondsToSelector:sel]) return nil;
    return ((id (*)(Class, SEL))objc_msgSend)(cls, sel);
}

static id CCAAirDropController(void) {
    static id controller = nil;
    if (controller) return controller;
    dlopen("/System/Library/PrivateFrameworks/Sharing.framework/Sharing", RTLD_LAZY);
    Class cls = NSClassFromString(@"SFAirDropDiscoveryController");
    if (!cls) return nil;
    @try { controller = [[cls alloc] init]; } @catch (__unused NSException *e) { controller = nil; }
    return controller;
}

static void CCAOpenSettings(NSString *root) {
    NSURL *url = [NSURL URLWithString:[@"prefs:root=" stringByAppendingString:root]];
    Class ws = NSClassFromString(@"LSApplicationWorkspace");
    id workspace = (ws && [ws respondsToSelector:NSSelectorFromString(@"defaultWorkspace")])
        ? ((id (*)(Class, SEL))objc_msgSend)(ws, NSSelectorFromString(@"defaultWorkspace")) : nil;
    SEL open = NSSelectorFromString(@"openSensitiveURL:withOptions:");
    @try {
        if (workspace && [workspace respondsToSelector:open]) {
            ((BOOL (*)(id, SEL, id, id))objc_msgSend)(workspace, open, url, nil);
            return;
        }
        [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
    } @catch (__unused NSException *e) {}
}

#pragma mark - Row

// iOS 26 menu row: dark text on the light glass, optional Wi-Fi glyph (with a lock badge when
// the network is secured) and a checkmark for the current one.
static UIColor *CCAMenuText(void) {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *t) {
        return t.userInterfaceStyle == UIUserInterfaceStyleDark ? [UIColor colorWithWhite:1.0 alpha:0.96] : [UIColor colorWithWhite:0.08 alpha:1.0];
    }];
}
static UIColor *CCAMenuSubText(void) {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *t) {
        return t.userInterfaceStyle == UIUserInterfaceStyleDark ? [UIColor colorWithWhite:1.0 alpha:0.55] : [UIColor colorWithWhite:0.0 alpha:0.46];
    }];
}
static UIColor *CCAMenuSeparator(void) {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *t) {
        return t.userInterfaceStyle == UIUserInterfaceStyleDark ? [UIColor colorWithWhite:1.0 alpha:0.16] : [UIColor colorWithWhite:0.0 alpha:0.14];
    }];
}
static UIColor *CCAMenuHighlight(void) {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *t) {
        return t.userInterfaceStyle == UIUserInterfaceStyleDark ? [UIColor colorWithWhite:1.0 alpha:0.12] : [UIColor colorWithWhite:0.0 alpha:0.08];
    }];
}

@interface CCADetailRow : UIControl
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subLabel;
@property (nonatomic, strong) UIImageView *trailing;
@property (nonatomic, strong) UIImageView *leading;
@property (nonatomic, strong) UIImageView *lockBadge;
@property (nonatomic, assign) BOOL hasLeading;
- (void)setLeadingSymbol:(NSString *)symbol locked:(BOOL)locked;
- (CGFloat)heightForWidth:(CGFloat)width;
@end

@implementation CCADetailRow
- (instancetype)initWithTitle:(NSString *)title sub:(NSString *)sub trailing:(NSString *)symbol {
    if ((self = [super initWithFrame:CGRectZero])) {
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.titleLabel = [UILabel new];
        self.titleLabel.text = title;
        self.titleLabel.textColor = CCAMenuText();
        self.titleLabel.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightMedium];
        self.titleLabel.numberOfLines = 2;
        self.titleLabel.userInteractionEnabled = NO;
        [self addSubview:self.titleLabel];
        self.subLabel = [UILabel new];
        self.subLabel.text = sub;
        self.subLabel.textColor = CCAMenuSubText();
        self.subLabel.font = [UIFont systemFontOfSize:12.5 weight:UIFontWeightMedium];
        self.subLabel.userInteractionEnabled = NO;
        [self addSubview:self.subLabel];
        self.trailing = [UIImageView new];
        self.trailing.tintColor = CCAMenuText();
        self.trailing.contentMode = UIViewContentModeCenter;
        self.trailing.userInteractionEnabled = NO;
        if (symbol.length) {
            self.trailing.image = [UIImage systemImageNamed:symbol
                withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:15.0 weight:UIImageSymbolWeightSemibold]];
        }
        [self addSubview:self.trailing];
    }
    return self;
}
- (void)setLeadingSymbol:(NSString *)symbol locked:(BOOL)locked {
    self.hasLeading = symbol.length > 0;
    if (!self.hasLeading) { [self.leading removeFromSuperview]; [self.lockBadge removeFromSuperview]; return; }
    if (!self.leading) {
        self.leading = [UIImageView new];
        self.leading.tintColor = CCAMenuText();
        self.leading.contentMode = UIViewContentModeCenter;
        self.leading.userInteractionEnabled = NO;
        [self addSubview:self.leading];
        self.lockBadge = [UIImageView new];
        self.lockBadge.tintColor = CCAMenuText();
        self.lockBadge.contentMode = UIViewContentModeCenter;
        self.lockBadge.userInteractionEnabled = NO;
        [self addSubview:self.lockBadge];
    }
    // the iOS 26 Wi-Fi glyph (SVG) when it is available, the system one otherwise
    UIImage *glyph = CC26SVGSymbol(symbol, 19.0) ?: [UIImage systemImageNamed:symbol
        withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:16.0 weight:UIImageSymbolWeightSemibold]];
    self.leading.image = [glyph imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    self.lockBadge.image = locked ? [UIImage systemImageNamed:@"lock.fill"
        withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:7.0 weight:UIImageSymbolWeightBold]] : nil;
}
- (CGFloat)textWidthForWidth:(CGFloat)width {
    return width - (self.hasLeading ? 60.0 : 20.0) - (self.trailing.image ? 38.0 : 14.0);
}
- (CGFloat)heightForWidth:(CGFloat)width {
    CGFloat tw = [self textWidthForWidth:width];
    CGRect box = [self.titleLabel.text boundingRectWithSize:CGSizeMake(tw, 60.0)
        options:NSStringDrawingUsesLineFragmentOrigin attributes:@{NSFontAttributeName: self.titleLabel.font} context:nil];
    CGFloat text = MIN(ceil(CGRectGetHeight(box)), 44.0);
    if (self.subLabel.text.length) text += 16.0;
    return MAX(44.0, text + 22.0);
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = CGRectGetWidth(self.bounds), h = CGRectGetHeight(self.bounds);
    self.trailing.frame = CGRectMake(w - 38.0, 0, 28.0, h);
    CGFloat x = self.hasLeading ? 56.0 : 18.0;
    CGFloat tw = [self textWidthForWidth:w];
    if (self.hasLeading) {
        self.leading.frame = CGRectMake(14.0, (h - 28.0) * 0.5, 28.0, 28.0);
        self.lockBadge.frame = CGRectMake(33.0, (h - 28.0) * 0.5 + 17.0, 10.0, 10.0);
    }
    CGFloat subH = self.subLabel.text.length ? 16.0 : 0.0;
    CGRect box = [self.titleLabel.text boundingRectWithSize:CGSizeMake(tw, 60.0)
        options:NSStringDrawingUsesLineFragmentOrigin attributes:@{NSFontAttributeName: self.titleLabel.font} context:nil];
    CGFloat th = MIN(ceil(CGRectGetHeight(box)), 44.0);
    CGFloat top = (h - th - subH) * 0.5;
    self.titleLabel.frame = CGRectMake(x, top, tw, th);
    self.subLabel.frame = subH > 0.0 ? CGRectMake(x, top + th, tw, subH) : CGRectZero;
}
- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    self.backgroundColor = highlighted ? CCAMenuHighlight() : UIColor.clearColor;
}
@end

#pragma mark - Panel

@interface CCADetailPanel : UIView
@property (nonatomic, strong) UIView *materialView;
@property (nonatomic, assign) CGSize lastGlassSize;
@property (nonatomic, assign) BOOL applyingGlass;
@property (nonatomic, assign) BOOL glassLive;
@property (nonatomic, copy) NSString *kind;            // wifi / bluetooth / airdrop
@property (nonatomic, copy) void (^onClose)(void);
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIScrollView *scroll;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, assign) NSInteger generation;
@property (nonatomic, strong) NSArray<UIView *> *rowViews;
@property (nonatomic, strong) UIView *separator;
@property (nonatomic, assign) CGFloat baseTop;       // final top edge (host coordinates)
@property (nonatomic, assign) CGFloat maxHeight;
@property (nonatomic, assign) BOOL closing;
- (instancetype)initWithKind:(NSString *)kind frame:(CGRect)frame onClose:(void (^)(void))onClose;
@end

@implementation CCADetailPanel

- (instancetype)initWithKind:(NSString *)kind frame:(CGRect)frame onClose:(void (^)(void))onClose {
    if ((self = [super initWithFrame:frame])) {
        self.kind = kind;
        self.onClose = onClose;
        self.tag = kCCADetailTag;
        self.clipsToBounds = YES;
        self.overrideUserInterfaceStyle = UIScreen.mainScreen.traitCollection.userInterfaceStyle;   // the overlay is always dark: follow the system
        self.baseTop = CGRectGetMinY(frame);
        self.maxHeight = CGRectGetHeight(frame);
        self.layer.cornerRadius = CC26ConnectivityTileRadius(frame.size, NO);
        self.layer.cornerCurve = kCACornerCurveContinuous;

        // iOS 26 menu: light frosted glass (LiquidAss glass when it is installed, which replaces
        // the blur) with a faint white lift so the dark text always reads
        UIVisualEffectView *blur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterial]];
        blur.frame = self.bounds;
        blur.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        blur.userInteractionEnabled = NO;
        [self addSubview:blur];
        self.materialView = blur;
        UIView *lift = [[UIView alloc] initWithFrame:self.bounds];
        lift.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        lift.backgroundColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *t) {
            return t.userInterfaceStyle == UIUserInterfaceStyleDark ? [UIColor colorWithWhite:0.0 alpha:0.10] : [UIColor colorWithWhite:1.0 alpha:0.20];
        }];
        lift.userInteractionEnabled = NO;
        [self addSubview:lift];

        self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
        self.spinner.color = CCAMenuSubText();
        self.spinner.hidesWhenStopped = YES;
        self.spinner.center = CGPointMake(CGRectGetWidth(frame) - 28.0, 28.0);
        self.spinner.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
        [self addSubview:self.spinner];

        self.scroll = [[UIScrollView alloc] initWithFrame:self.bounds];
        self.scroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.scroll.alwaysBounceVertical = NO;
        self.scroll.showsVerticalScrollIndicator = NO;
        [self addSubview:self.scroll];

        [self reload];
    }
    return self;
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (!self.window || self.applyingGlass || self.lastGlassSize.width > 0.0) return;
    self.applyingGlass = YES;
    CGFloat radius = CC26ConnectivityTileRadius(self.bounds.size, NO);
    BOOL live = NO;
    @try { live = CC26LIQApplyGlass(self, radius); } @catch (__unused NSException *e) { live = NO; }
    self.glassLive = live;
    self.lastGlassSize = self.bounds.size;
    self.materialView.hidden = live;
    self.applyingGlass = NO;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat radius = CC26ConnectivityTileRadius(self.bounds.size, NO);
    if (fabs(self.layer.cornerRadius - radius) > 0.5) {
        self.layer.cornerRadius = radius;
        self.materialView.layer.cornerRadius = radius;
    }
}

- (void)closePanel {
    if (self.closing) return;
    self.closing = YES;
    void (^close)(void) = self.onClose;
    self.generation++;
    [UIView animateWithDuration:0.2 animations:^{
        self.alpha = 0.0;
        self.transform = CGAffineTransformConcat(CGAffineTransformMakeScale(0.9, 0.9), CGAffineTransformMakeTranslation(0.0, -6.0));
    } completion:^(BOOL finished) {
        [self removeFromSuperview];
        if (close) close();
    }];
}

// the panel hugs its rows: height follows the content up to maxHeight (transform-safe: bounds/center)
- (void)fitHeight:(CGFloat)contentHeight animated:(BOOL)animated {
    CGFloat host = CGRectGetHeight(self.superview.bounds);
    CGFloat h = MIN(contentHeight, self.maxHeight);
    CGFloat top = host > 0.0 ? MIN(self.baseTop, host - h - 24.0) : self.baseTop;
    top = MAX(top, 12.0);
    CGFloat w = CGRectGetWidth(self.bounds);
    CGPoint center = CGPointMake(self.center.x, top + h * 0.5);
    void (^apply)(void) = ^{ self.bounds = CGRectMake(0, 0, w, h); self.center = center; };
    if (animated && self.superview) {
        [UIView animateWithDuration:0.4 delay:0.0 usingSpringWithDamping:CC26SpringDamping(0.82) initialSpringVelocity:0.0
                            options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState
                         animations:apply completion:nil];
    } else apply();
}

- (void)setRows:(NSArray<CCADetailRow *> *)rows footer:(NSString *)footerRoot {
    for (UIView *v in self.rowViews) [v removeFromSuperview];
    [self.separator removeFromSuperview];
    CGFloat w = CGRectGetWidth(self.bounds) - 16.0, y = 8.0;
    for (CCADetailRow *row in rows) {
        CGFloat h = [row heightForWidth:w];
        row.frame = CGRectMake(8.0, y, w, h);
        row.layer.cornerRadius = 16.0;
        [self.scroll addSubview:row];
        y += h;
    }
    NSMutableArray<UIView *> *all = [rows mutableCopy];
    if (footerRoot.length) {
        y += 4.0;
        self.separator = [[UIView alloc] initWithFrame:CGRectMake(18.0, y, CGRectGetWidth(self.bounds) - 36.0, 1.0 / UIScreen.mainScreen.scale)];
        self.separator.backgroundColor = CCAMenuSeparator();
        [self.scroll addSubview:self.separator];
        y += 4.0;
        NSString *title = [footerRoot isEqualToString:@"WIFI"] ? @"Wi-Fi Settings…" : [NSString stringWithFormat:@"%@ Settings…", footerRoot];
        CCADetailRow *settings = [[CCADetailRow alloc] initWithTitle:title sub:nil trailing:nil];
        [settings addAction:[UIAction actionWithHandler:^(__kindof UIAction *a) { CCAOpenSettings(footerRoot); }]
           forControlEvents:UIControlEventTouchUpInside];
        CGFloat h = [settings heightForWidth:w];
        settings.frame = CGRectMake(8.0, y, w, h);
        settings.layer.cornerRadius = 16.0;
        [self.scroll addSubview:settings];
        [all addObject:settings];
        y += h;
    }
    y += 8.0;
    self.rowViews = [all copy];
    self.scroll.contentSize = CGSizeMake(CGRectGetWidth(self.bounds), y);
    self.scroll.alwaysBounceVertical = (y > self.maxHeight);
    [self fitHeight:y animated:(self.rowViews.count > 1)];
}

- (CCADetailRow *)infoRow:(NSString *)text {
    CCADetailRow *row = [[CCADetailRow alloc] initWithTitle:text sub:nil trailing:nil];
    row.titleLabel.textColor = CCAMenuSubText();
    row.userInteractionEnabled = NO;
    return row;
}

- (void)reload {
    NSInteger gen = ++self.generation;
    __weak CCADetailPanel *weakSelf = self;
    if ([self.kind isEqualToString:@"wifi"]) {
        [self.spinner startAnimating];
        [self setRows:@[[self infoRow:@"Searching for networks…"]] footer:nil];
        CCAScanWiFi(^(NSArray<NSDictionary *> *networks) {
            CCADetailPanel *panel = weakSelf;
            if (!panel || panel.generation != gen) return;
            [panel.spinner stopAnimating];
            NSMutableArray<CCADetailRow *> *rows = [NSMutableArray array];
            for (NSDictionary *n in networks) {
                BOOL current = [n[@"current"] boolValue];
                CCADetailRow *row = [[CCADetailRow alloc] initWithTitle:n[@"ssid"] sub:nil trailing:current ? @"checkmark" : nil];
                [row setLeadingSymbol:@"wifi" locked:[n[@"secured"] boolValue]];
                [row addAction:[UIAction actionWithHandler:^(__kindof UIAction *a) { CCAOpenSettings(@"WIFI"); }]
              forControlEvents:UIControlEventTouchUpInside];
                [rows addObject:row];
            }
            if (!rows.count) [rows addObject:[panel infoRow:@"No networks found"]];
            [panel setRows:rows footer:@"WIFI"];
        });
    } else if ([self.kind isEqualToString:@"bluetooth"]) {
        id manager = CCABluetoothManager();
        NSArray *devices = nil;
        @try {
            SEL sel = NSSelectorFromString(@"pairedDevices");
            if (manager && [manager respondsToSelector:sel]) devices = ((id (*)(id, SEL))objc_msgSend)(manager, sel);
        } @catch (__unused NSException *e) {}
        NSMutableArray<CCADetailRow *> *rows = [NSMutableArray array];
        for (id device in devices) {
            NSString *name = nil;
            BOOL connected = NO;
            @try {
                if ([device respondsToSelector:NSSelectorFromString(@"name")]) name = [device valueForKey:@"name"];
                if ([device respondsToSelector:NSSelectorFromString(@"connected")]) connected = ((BOOL (*)(id, SEL))objc_msgSend)(device, NSSelectorFromString(@"connected"));
            } @catch (__unused NSException *e) {}
            if (![name isKindOfClass:NSString.class] || !name.length) continue;
            CCADetailRow *row = [[CCADetailRow alloc] initWithTitle:name sub:connected ? @"Connected" : @"Not Connected" trailing:connected ? @"checkmark" : nil];
            [row addAction:[UIAction actionWithHandler:^(__kindof UIAction *a) {
                @try {
                    SEL sel = NSSelectorFromString(connected ? @"disconnect" : @"connect");
                    if ([device respondsToSelector:sel]) ((void (*)(id, SEL))objc_msgSend)(device, sel);
                } @catch (__unused NSException *e) {}
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [weakSelf reload]; });
            }] forControlEvents:UIControlEventTouchUpInside];
            [rows addObject:row];
        }
        if (!rows.count) [rows addObject:[self infoRow:@"No paired devices"]];
        [self setRows:rows footer:@"Bluetooth"];
    } else {
        id controller = CCAAirDropController();
        NSInteger mode = -1;
        @try {
            SEL get = NSSelectorFromString(@"discoverableMode");
            if (controller && [controller respondsToSelector:get]) mode = ((NSInteger (*)(id, SEL))objc_msgSend)(controller, get);
        } @catch (__unused NSException *e) {}
        NSArray<NSString *> *titles = @[@"Receiving Off", @"Contacts Only", @"Everyone for 10 Minutes"];
        NSMutableArray<CCADetailRow *> *rows = [NSMutableArray array];
        for (NSInteger i = 0; i < 3; i++) {
            CCADetailRow *row = [[CCADetailRow alloc] initWithTitle:titles[i] sub:nil trailing:(mode == i) ? @"checkmark" : nil];
            [row addAction:[UIAction actionWithHandler:^(__kindof UIAction *a) {
                @try {
                    SEL set = NSSelectorFromString(@"setDiscoverableMode:");
                    if (controller && [controller respondsToSelector:set]) ((void (*)(id, SEL, NSInteger))objc_msgSend)(controller, set, i);
                } @catch (__unused NSException *e) {}
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [weakSelf reload]; });
            }] forControlEvents:UIControlEventTouchUpInside];
            [rows addObject:row];
        }
        [self setRows:rows footer:nil];
    }
}

@end

// iOS 26 menu: a light glass panel that grows out of the pressed tile (`anchor`, in the
// coordinates of `container`), with a soft dim behind it; a tap outside closes it.
static UIView *CCAShowMenu(UIView *container, NSString *kind, CGRect anchor) {
    if (!container) return nil;
    [[container viewWithTag:kCCADetailTag + 1] removeFromSuperview];
    [[container viewWithTag:kCCADetailTag] removeFromSuperview];
    CGFloat W = CGRectGetWidth(container.bounds), H = CGRectGetHeight(container.bounds);
    CGFloat pw = MAX(210.0, floor(CGRectGetWidth(UIScreen.mainScreen.bounds) * 0.62));
    pw = MIN(pw, W - 24.0);
    CGFloat left = MIN(MAX(CGRectGetMinX(anchor), 12.0), W - pw - 12.0);
    CGFloat top = MAX(CGRectGetMinY(anchor), 12.0);
    CGFloat maxH = MAX(160.0, MIN(H - top - 24.0, floor(H * 0.78)));
    CGRect start = CGRectMake(left, top, pw, MIN(maxH, 120.0));

    UIView *dim = [[UIView alloc] initWithFrame:container.bounds];
    dim.tag = kCCADetailTag + 1;
    dim.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    dim.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.16];
    dim.alpha = 0.0;
    [container addSubview:dim];

    __weak UIView *weakDim = dim;
    CCADetailPanel *panel = [[CCADetailPanel alloc] initWithKind:kind frame:start onClose:^{ [weakDim removeFromSuperview]; }];
    panel.maxHeight = maxH;
    panel.baseTop = top;
    [container addSubview:panel];
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:panel action:@selector(closePanel)];
    [dim addGestureRecognizer:tap];

    // grow from the tile: start small, centred on it
    CGPoint from = CGPointMake(CGRectGetMidX(anchor), CGRectGetMidY(anchor));
    CGPoint to = panel.center;
    panel.alpha = 0.0;
    panel.transform = CGAffineTransformConcat(CGAffineTransformMakeScale(0.25, 0.25),
                                              CGAffineTransformMakeTranslation(from.x - to.x, from.y - to.y));
    [UIView animateWithDuration:0.5 delay:0.0 usingSpringWithDamping:CC26SpringDamping(0.76) initialSpringVelocity:CC26SpringVelocity(0.6)
                        options:UIViewAnimationOptionAllowUserInteraction
                     animations:^{ dim.alpha = 1.0; panel.alpha = 1.0; panel.transform = CGAffineTransformIdentity; } completion:nil];
    return panel;
}

// long press on a tile of the page (anchor = that tile, in the page's coordinates)
UIView *CC26ConnectivityShowDetail(UIView *page, NSString *kind, CGRect anchor) {
    return CCAShowMenu(page, kind, anchor);
}

// compact module: same menu over the overlay, anchored on the held button
UIView *CC26ConnectivityShowFloatingDetail(UIView *host, NSString *kind, CGRect anchor) {
    return CCAShowMenu(host, kind, anchor);
}
