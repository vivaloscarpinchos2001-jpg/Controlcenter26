#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <math.h>
#import "CC26.h"

@implementation CC26Anim

+ (void)popViews:(NSArray<UIView *> *)views {
    NSUInteger i;
    NSUInteger count = views.count;
    for (i = 0; i < count; i++) {
        UIView *view = views[i];
        if (!view.layer) continue;
        if ([view.layer animationForKey:@"CC26AnimPopScale"]) continue;

        CAKeyframeAnimation *scale = [CAKeyframeAnimation animationWithKeyPath:@"transform.scale"];
        scale.values = @[@0.90, @1.025, @1.0];
        scale.keyTimes = @[@0.0, @0.68, @1.0];
        scale.duration = 0.20;
        scale.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
        [view.layer addAnimation:scale forKey:@"CC26AnimPopScale"];

        CAKeyframeAnimation *fade = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
        fade.values = @[@0.08, @0.86, @1.0];
        fade.keyTimes = @[@0.0, @0.62, @1.0];
        fade.duration = 0.18;
        fade.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
        [view.layer addAnimation:fade forKey:@"CC26AnimPopFade"];
    }
}

@end