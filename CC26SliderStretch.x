#import "CC26.h"
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

// ---------------------------------------------------------------------------
// Brightness / volume sliders: when the finger keeps pushing past the maximum (or the
// minimum) the whole module stretches with rubber-band resistance and springs back on
// release. Ported from CCAster (CCAUpdateSliderOverscroll), adapted to this tweak.
// The hook is only installed when the stock selector exists on this iOS version.
// ---------------------------------------------------------------------------

static const void *kCC26SliderBaseKey   = &kCC26SliderBaseKey;
static const void *kCC26SliderStartKey  = &kCC26SliderStartKey;
static const void *kCC26SliderAmountKey = &kCC26SliderAmountKey;
static const void *kCC26SliderTargetKey = &kCC26SliderTargetKey;

static void CC26SliderClear(UIView *slider) {
    objc_setAssociatedObject(slider, kCC26SliderBaseKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(slider, kCC26SliderStartKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(slider, kCC26SliderAmountKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(slider, kCC26SliderTargetKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void CC26SliderOverscroll(UIView *slider, UIPanGestureRecognizer *gesture) {
    if (!slider || !gesture || !gEnabled || !gBouncyAnimations || gEditModeActive || gCCAModuleExpanded) return;
    UIGestureRecognizerState state = gesture.state;

    if (state == UIGestureRecognizerStateBegan) {
        // only the tall brightness / volume presentation
        if (CGRectGetHeight(slider.bounds) <= CGRectGetWidth(slider.bounds) * 1.15) return;
        UIView *target = nil;
        for (UIResponder *r = slider.nextResponder; r; r = r.nextResponder) {
            if ([r isKindOfClass:UIViewController.class] && IsModuleController((UIViewController *)r)) {
                target = ((UIViewController *)r).view;
                break;
            }
        }
        if (!target) target = slider;
        [target.layer removeAllAnimations];
        objc_setAssociatedObject(slider, kCC26SliderTargetKey, [NSValue valueWithNonretainedObject:target], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(slider, kCC26SliderBaseKey, [NSValue valueWithCGAffineTransform:target.transform], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        float value = [slider respondsToSelector:@selector(value)] ? ((float (*)(id, SEL))objc_msgSend)((id)slider, @selector(value)) : 0.0f;
        objc_setAssociatedObject(slider, kCC26SliderStartKey, @(value), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(slider, kCC26SliderAmountKey, @0.0, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    NSValue *baseValue = objc_getAssociatedObject(slider, kCC26SliderBaseKey);
    if (!baseValue) return;
    UIView *target = [objc_getAssociatedObject(slider, kCC26SliderTargetKey) nonretainedObjectValue] ?: slider;
    CGAffineTransform baseTransform = baseValue.CGAffineTransformValue;

    if (state == UIGestureRecognizerStateEnded || state == UIGestureRecognizerStateCancelled || state == UIGestureRecognizerStateFailed) {
        CGFloat tension = [objc_getAssociatedObject(slider, kCC26SliderAmountKey) doubleValue];
        CGFloat velocityY = [gesture velocityInView:slider.window].y;
        CGFloat displacementY = target.transform.ty - baseTransform.ty;
        BOOL flingingOutward = tension > 0.10 && displacementY * velocityY > 0.0;
        CGFloat springVelocity = flingingOutward ? -MIN(2.2, fabs(velocityY) / 520.0) * tension : 0.0;
        NSTimeInterval duration = 0.20 + 0.30 * tension;
        CGFloat damping = 0.88 - 0.32 * tension;
        [UIView animateWithDuration:duration delay:0.0
             usingSpringWithDamping:CC26SpringDamping(damping) initialSpringVelocity:CC26SpringVelocity(springVelocity)
                            options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                         animations:^{ target.transform = baseTransform; }
                         completion:^(__unused BOOL finished) { CC26SliderClear(slider); }];
        return;
    }
    if (state != UIGestureRecognizerStateBegan && state != UIGestureRecognizerStateChanged) return;

    // window-space translation, so deforming the module cannot feed back into the gesture
    CGFloat startValue = [objc_getAssociatedObject(slider, kCC26SliderStartKey) doubleValue];
    CGFloat translationY = [gesture translationInView:slider.window].y;
    CGFloat rawValue = startValue - translationY / MAX(1.0, CGRectGetHeight(slider.bounds));
    CGFloat overshoot = rawValue > 1.0 ? rawValue - 1.0 : (rawValue < 0.0 ? -rawValue : 0.0);
    CGFloat pull = overshoot * 6.0;
    CGFloat resisted = pull / (1.0 + pull);   // no hard ceiling, progressively less motion
    BOOL pullingTop = rawValue > 1.0;
    CGFloat travelY = (pullingTop ? -1.0 : 1.0) * 9.0 * resisted;
    CGAffineTransform transformed = CGAffineTransformTranslate(baseTransform, 0.0, travelY);
    transformed = CGAffineTransformScale(transformed, 1.0 - 0.045 * resisted, 1.0 + 0.040 * resisted);
    [UIView performWithoutAnimation:^{ target.transform = transformed; }];
    objc_setAssociatedObject(slider, kCC26SliderAmountKey, @(resisted), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

@interface CCUIContinuousSliderView : UIView @end

%group CC26SliderStretchGroup
%hook CCUIContinuousSliderView
- (void)_handleValueChangeGestureRecognizer:(UIPanGestureRecognizer *)gesture {
    %orig;
    @try { CC26SliderOverscroll((UIView *)(id)self, gesture); } @catch (__unused NSException *e) {}
}
%end
%end

%ctor {
    Class cls = NSClassFromString(@"CCUIContinuousSliderView");
    if (cls && class_getInstanceMethod(cls, NSSelectorFromString(@"_handleValueChangeGestureRecognizer:"))) {
        %init(CC26SliderStretchGroup);
    }
}
