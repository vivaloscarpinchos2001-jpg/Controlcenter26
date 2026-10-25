THEOS_PACKAGE_SCHEME = rootless
ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0

INSTALL_TARGET_PROCESSES = SpringBoard
include $(THEOS)/makefiles/common.mk

TWEAK_NAME = ControlCenter26
ControlCenter26_FILES = tweak.xm CC26.x CC26Anim.x CC26Indicator.x CC26Media.x CC26Coordinator.x CC26Design.x CC26Edit.xm CC26LIQ.x CC26Connectivity.x CC26ConnectivityDetail.x CC26SliderStretch.x

ControlCenter26_CFLAGS = -fobjc-arc 
ControlCenter26_FRAMEWORKS = UIKit CFNetwork
include $(THEOS_MAKE_PATH)/tweak.mk
SUBPROJECTS += prefs modulebundles

include $(THEOS_MAKE_PATH)/aggregate.mk
after-install::
	install.exec "sbreload"