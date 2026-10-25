ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = ControlCenter26Prefs

ControlCenter26Prefs_FILES = ControlCenter26RootListController.m
ControlCenter26Prefs_FRAMEWORKS = UIKit
ControlCenter26Prefs_PRIVATE_FRAMEWORKS = Preferences
ControlCenter26Prefs_INSTALL_PATH = /Library/PreferenceBundles
ControlCenter26Prefs_CFLAGS = -fobjc-arc
ControlCenter26Prefs_RESOURCE_DIRS = Resources


include $(THEOS_MAKE_PATH)/bundle.mk

after-ControlCenter26Prefs-stage::
	@mkdir -p "$(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences"
	@cp "Resources/ControlCenter26Prefs.plist" "$(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/ControlCenter26Prefs.plist"