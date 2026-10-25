#import "ControlCenter26RootListController.h"
#import <Preferences/PSSpecifier.h>
#import <spawn.h>
#import <unistd.h>
#import <rootless.h>

@implementation ControlCenter26RootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

- (void)respring {
    pid_t pid;
    const char *args[] = { "killall", "-9", "SpringBoard", NULL };
    posix_spawn(&pid, ROOT_PATH("/usr/bin/killall"), NULL, NULL, (char *const *)args, NULL);
}

@end