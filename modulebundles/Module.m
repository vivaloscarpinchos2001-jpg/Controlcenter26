// One source file, one bundle per radio (see makefile: -DCC26_KIND=...).
//
// A Control Center module that shows a single round button. It never touches the radios itself:
// it asks the ControlCenter26 tweak (loaded in SpringBoard) for the state of the stock iOS 16
// button and presses that button, so the module always matches the original connectivity module.
// Without the tweak loaded the button is shown dimmed and does nothing.
#import <UIKit/UIKit.h>
#import <dlfcn.h>

#ifndef CC26_KIND
#define CC26_KIND 0
#endif

typedef int (*CC26StateFn)(NSInteger);
typedef void (*CC26ToggleFn)(NSInteger);
typedef UIImage *(*CC26GlyphFn)(NSInteger, CGFloat);

static void *CC26Sym(const char *name) { return dlsym(RTLD_DEFAULT, name); }

static UIColor *CC26OnColor(void) {
    switch (CC26_KIND) {
        case 2:  return [UIColor colorWithRed:1.00 green:0.58 blue:0.00 alpha:1.0];   // airplane
        case 3:
        case 5:  return [UIColor colorWithRed:0.20 green:0.78 blue:0.35 alpha:1.0];   // cellular, hotspot
        default: return [UIColor colorWithRed:0.04 green:0.52 blue:1.00 alpha:1.0];   // wifi, bluetooth, airdrop
    }
}

@interface CC26_VC_CLASS : UIViewController
@end

@implementation CC26_VC_CLASS {
    UIView *_fill;
    UIImageView *_glyph;
    NSTimer *_timer;
    int _lastState;
}

- (void)loadView {
    UIView *root = [UIView new];
    root.backgroundColor = UIColor.clearColor;
    self.view = root;
    _lastState = -2;
    _fill = [UIView new];
    _fill.backgroundColor = CC26OnColor();
    _fill.alpha = 0.0;
    _fill.userInteractionEnabled = NO;
    [root addSubview:_fill];
    _glyph = [UIImageView new];
    _glyph.contentMode = UIViewContentModeCenter;
    _glyph.tintColor = UIColor.whiteColor;
    _glyph.userInteractionEnabled = NO;
    [root addSubview:_glyph];
    [root addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped)]];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect bounds = self.view.bounds;
    _fill.frame = bounds;
    _glyph.frame = bounds;
    CGFloat radius = self.view.superview.layer.cornerRadius;
    self.view.layer.cornerRadius = radius;
    self.view.layer.masksToBounds = radius > 0.0;
    _lastState = -2;   // glyph size depends on the bounds
    [self refresh];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [_timer invalidate];
    __weak typeof(self) weakSelf = self;
    _timer = [NSTimer scheduledTimerWithTimeInterval:0.6 repeats:YES block:^(NSTimer *t) { [weakSelf refresh]; }];
    [self refresh];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    [_timer invalidate];
    _timer = nil;
}

- (void)dealloc { [_timer invalidate]; }

- (void)refresh {
    CC26StateFn stateFn = (CC26StateFn)CC26Sym("CC26SplitModuleState");
    int state = stateFn ? stateFn(CC26_KIND) : -1;
    if (state == _lastState) return;
    BOOL first = (_lastState == -2);
    _lastState = state;
    CC26GlyphFn glyphFn = (CC26GlyphFn)CC26Sym("CC26SplitModuleGlyph");
    CGFloat side = MIN(CGRectGetWidth(self.view.bounds), CGRectGetHeight(self.view.bounds));
    UIImage *image = glyphFn ? glyphFn(CC26_KIND, side * 0.42) : nil;
    if (!image) image = [UIImage systemImageNamed:@"circle" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:side * 0.4]];
    _glyph.image = image;
    void (^apply)(void) = ^{
        self->_fill.alpha = (state == 1) ? 1.0 : 0.0;
        self->_glyph.alpha = (state < 0) ? 0.35 : 1.0;
    };
    if (first || !self.view.window) apply();
    else [UIView animateWithDuration:0.25 animations:apply];
}

- (void)tapped {
    CC26ToggleFn toggle = (CC26ToggleFn)CC26Sym("CC26SplitModuleToggle");
    if (!toggle || CC26Sym("CC26SplitModuleState") == NULL) return;
    UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [haptic impactOccurred];
    toggle(CC26_KIND);
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [weakSelf refresh]; });
}

// CCUIContentModuleContentViewController: a plain button, no expanded content
- (CGFloat)preferredExpandedContentHeight { return 0.0; }
- (CGFloat)preferredExpandedContentWidth { return 0.0; }
- (BOOL)providesOwnPlatter { return NO; }
- (BOOL)shouldBeginTransitionToExpandedContentModule { return NO; }
@end

@interface CC26_MODULE_CLASS : NSObject
@property (nonatomic, strong) id contentModuleContext;
@end

@implementation CC26_MODULE_CLASS {
    UIViewController *_controller;
}
- (UIViewController *)contentViewController {
    if (!_controller) _controller = [CC26_VC_CLASS new];
    return _controller;
}
- (UIViewController *)backgroundViewController { return nil; }
@end
