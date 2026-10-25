#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#include <string.h>
// these hooks sit on UIViewController / CALayer for ALL of SpringBoard (home screen, app switcher):
// bail out first, with a plain C string check, for everything that is not Control Center UI
static inline BOOL CC26IsControlCenterClass(id object) {
    const char *name = object_getClassName(object);
    return strstr(name, "CCUI") != NULL || strstr(name, "ControlCenter") != NULL;
}

#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <math.h>
#import <MediaPlayer/MediaPlayer.h>
#import <AVFoundation/AVFoundation.h>

#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wunused-variable"
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

#ifdef __cplusplus
extern "C" {
#endif

extern const NSInteger CC26TagConnectivityCluster;
extern const NSInteger CC26TagMediaButtonMaterial;
extern const NSInteger kPageIndicatorTag;
extern const NSInteger kQuickAccessTag;
extern const NSInteger kMediaPlayerTag;
extern const NSInteger kConnectivityPageTag;

extern const void *CC26KeyCompactRadius;
extern const void *CC26KeyMediaMode;
extern const void *CC26KeyMiniGlyphBaseSize;

extern BOOL gEnabled;
extern CGFloat gCC26GridCell;
extern CGFloat gCC26GridGap;
extern BOOL gQuickAccessButtonsEnabled;
extern BOOL gPagingEnabled;
extern BOOL gHapticsEnabled;
extern BOOL gExperimentalPagingEnabled;
extern BOOL gPageAnimating;
extern BOOL gPagerScrubbing;
extern BOOL gCCAModuleExpanded;
extern NSInteger gCurrentPage;
extern NSString *const kReloadNotification;
extern BOOL gEditModeEnabled;
extern BOOL gEditModeActive;
extern BOOL gCircularModulesEnabled;
extern BOOL gConnectivityPageEnabled;
extern BOOL gConnectivityGlassEnabled;
extern BOOL gBouncyAnimations;
extern BOOL gIOS26Icons;
extern BOOL gMenu26;                       // iOS 26 menu (ours) vs the stock iOS 16 menu on long press
extern BOOL gSwipePagingEnabled;
void CC26LoadEditPrefs(void);
CGFloat CC26SpringDamping(CGFloat damping);      // bouncy spring -> returns damping unchanged; bounce off -> 1.0
CGFloat CC26SpringVelocity(CGFloat velocity);    // bounce off -> 0.0
CGFloat CC26SpringCriticalDamping(CGFloat stiffness, CGFloat bouncyDamping); // for CASpringAnimation

CGFloat calculatedRadius(CGRect visibleRect, CGFloat radius);
void LoadPrefs(void);
void Haptic(void);
CGFloat PageSpan(void);
NSUInteger CC26PageCount(void);
NSInteger CC26ConnectivityPageIndex(void);
NSInteger CC26MediaPageIndex(void);
BOOL CC26LIQIsActive(void);
BOOL CC26LIQApplyGlass(UIView *host, CGFloat radius);
UIViewController *CC26OverlayForView(UIView *view);
void CC26PlayOpenStretch(UIViewController *overlay);
void CC26DismissEmbeddedConnectivity(UIViewController *overlay);
void CC26StripExpandedBackground(UIView *container);

UIViewController *OverlayIn(UIViewController *root);
BOOL IsModuleController(UIViewController *controller);
BOOL IsConnectivityController(UIViewController *controller);
NSArray<UIViewController *> *ModuleControllers(UIViewController *root);
UIViewController *ModuleCollection(UIViewController *overlay);
UIViewController *ConnectivityChild(UIViewController *controller, NSString *className);
UIView *CC26ViewIvar(id object, const char *name);

UIView *CC26ModuleAncestor(UIView *view);
CGFloat CC26ModuleCornerRadius(CGSize size);
CGFloat CC26RadiusForModule(UIView *module);
CGFloat CC26ConnectivityTileRadius(CGSize size, BOOL pill);
UIView *CC26Ancestor(UIView *view, NSString *className);
NSString *CC26MediaMode(UIView *view);
NSArray *CC26MediaMaterialFilters(UIView *view);
void CC26ResizeMediaRoutingGlyph(UIView *button);
void CC26ConfigureMedia(UIView *view);
void CC26SquareCornersForContainer(UIView *v);   // re-applies the iOS 26 "semi square" corner to a 2x2 module container right now
UIViewController *CC26ConnectivityChild(UIViewController *controller, NSString *className);
BOOL CC26FireStockLongPress(UIViewController *controller, NSString *className);
void CC26LIQRefreshGlass(UIView *host);   // rebuild the glass filter after the host changed size
// Separate Wi-Fi / Bluetooth / ... modules (bundles in modulebundles/) talk to the tweak through these.
// kind: 0 Wi-Fi, 1 Bluetooth, 2 Airplane, 3 Cellular data, 4 AirDrop, 5 Personal Hotspot
void CC26RememberStockConnectivity(UIViewController *controller);
int CC26SplitModuleState(NSInteger kind);            // 1 on, 0 off, -1 not available yet
void CC26SplitModuleToggle(NSInteger kind);
UIImage *CC26SplitModuleGlyph(NSInteger kind, CGFloat pointSize);   // forwards the long press to the stock button
void CC26EmbedExpandedMediaIfNeeded(UIView *nowPlaying);                          // music module expanded -> the music page player
UIView *CC26ModuleMaterial(void);
NSArray *CC26ConnectivityVibrantFilters(UIView *root);
void CC26ScaleMiniGlyphs(UIView *root, CGFloat scale);
UIImage *CC26BundledSymbol(NSString *name, UIColor *color, BOOL hierarchical);
UIImage *CC26SVGSymbol(NSString *name, CGFloat pointSize);
void CC26ConfigureConnectivity(UIViewController *controller);
CGFloat CC26ConnectivityExpandedHeightForWidth(CGFloat width);
CGRect CC26VisibleModuleBounds(UIViewController *overlay);
void CC26UpdateStockGrid(UIViewController *overlay);   // remembers where the stock module grid sits (window coordinates)
CGRect CC26StockGridRect(void);                         // CGRectNull until it has been measured

#ifdef __cplusplus
}
#endif

@interface MTMaterialLayer : CALayer
@property (nonatomic, copy, readwrite) NSString *recipeName;
@property (atomic, assign, readonly) CGRect visibleRect;
@end

@interface CALayer ()
@property (atomic, assign, readwrite) id unsafeUnretainedDelegate;
@end

@interface MRUNowPlayingView : UIView @end
@interface MRUArtworkView : UIView @end
@interface MRUNowPlayingHeaderView : UIView @end
@interface MRUNowPlayingLabelView : UIView @end
@interface MRUNowPlayingTransportControlsView : UIView @end
@interface MRUTransportButton : UIButton @end

@interface CCUIModuleCollectionView : UIScrollView @end

@interface CC26Anim : NSObject
+ (void)popViews:(NSArray<UIView *> *)views;
@end

@interface CCAPageIndicator : UIView
@property (nonatomic, weak) UIViewController *overlay;
@property (nonatomic) NSUInteger currentPage;
@property (nonatomic) NSUInteger pageCount;
@property (nonatomic, assign) BOOL transitionActive;
@property (nonatomic, assign) BOOL scrubbingActive;
@property (nonatomic, assign, readonly) BOOL scrubbing;
- (void)setCurrentPage:(NSUInteger)page forOverlay:(UIViewController *)overlay;
- (void)layoutButtons;
- (void)captureCollectionBase;
- (void)installSwipeRecognizerOnView:(UIView *)view;
@end

@interface CCAQuickAccessHost : UIView
@end

@interface CCAMediaPlayerView : UIView
@property (nonatomic, assign) BOOL embedded;   // lives in the expanded music module, not in the music page
- (void)setupUI;
- (void)refresh;
- (void)resetForPresentation;
- (void)fadeIn;
- (void)fadeOut;
- (void)slideOut;
- (void)slideOffScreen;
@end

@interface CCAConnectivityPageView : UIView
@property (nonatomic, assign) CGFloat availableHeight;
@property (nonatomic, assign) BOOL embedded;                       // lives inside the expanded module
@property (nonatomic, assign) BOOL fitsGrid;                       // page frame = stock module grid
@property (nonatomic, weak) UIViewController *hostController;      // the stock CCUIConnectivityModuleViewController
- (CGFloat)preferredHeightForWidth:(CGFloat)width;
- (void)refreshStates;
- (void)playStretchIn;
@end

@interface CC26 : NSObject
+ (instancetype)shared;
- (void)installOnOverlay:(UIViewController *)overlay;
- (void)syncModuleVisibilityForOverlay:(UIViewController *)overlay;
- (void)syncModuleVisibilityForOverlay:(UIViewController *)overlay animated:(BOOL)animated;
- (void)restoreModuleVisibilityForOverlay:(UIViewController *)overlay;
- (void)applyHeaderMaterialHidden:(BOOL)hidden forOverlay:(UIViewController *)overlay;
- (void)adjustStatusBarForOverlay:(UIViewController *)overlay;
- (void)animateElementsInForOverlay:(UIViewController *)overlay;
- (void)animateElementsOutForOverlay:(UIViewController *)overlay;
- (void)layoutPageIndicatorForOverlay:(UIViewController *)overlay;
- (void)updateQuickAccessButtonsForOverlay:(UIViewController *)overlay;
- (void)installPageIndicatorOnOverlay:(UIViewController *)overlay;
- (void)installMediaPlayerOnCollectionView:(UIScrollView *)collectionView;
- (void)layoutMediaPlayerForCollectionView:(UIScrollView *)collectionView;
- (void)installConnectivityPageOnCollectionView:(UIScrollView *)collectionView;
- (void)layoutConnectivityPageForCollectionView:(UIScrollView *)collectionView;
- (CGFloat)topInsetForOverlay:(UIViewController *)overlay;
- (UIButton *)makeRoundButtonWithSymbol:(NSString *)symbolName tag:(NSInteger)tag;
@end