ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = CC26WiFiModule CC26BluetoothModule CC26AirplaneModule CC26CellularModule CC26AirDropModule CC26HotspotModule

CC26WiFiModule_FILES = Module.m
CC26WiFiModule_FRAMEWORKS = UIKit
CC26WiFiModule_INSTALL_PATH = /Library/ControlCenter/Bundles
CC26WiFiModule_RESOURCE_DIRS = Resources/WiFi
CC26WiFiModule_CFLAGS = -fobjc-arc -DCC26_KIND=0 -DCC26_MODULE_CLASS=CC26WiFiModule -DCC26_VC_CLASS=CC26WiFiViewController

CC26BluetoothModule_FILES = Module.m
CC26BluetoothModule_FRAMEWORKS = UIKit
CC26BluetoothModule_INSTALL_PATH = /Library/ControlCenter/Bundles
CC26BluetoothModule_RESOURCE_DIRS = Resources/Bluetooth
CC26BluetoothModule_CFLAGS = -fobjc-arc -DCC26_KIND=1 -DCC26_MODULE_CLASS=CC26BluetoothModule -DCC26_VC_CLASS=CC26BluetoothViewController

CC26AirplaneModule_FILES = Module.m
CC26AirplaneModule_FRAMEWORKS = UIKit
CC26AirplaneModule_INSTALL_PATH = /Library/ControlCenter/Bundles
CC26AirplaneModule_RESOURCE_DIRS = Resources/Airplane
CC26AirplaneModule_CFLAGS = -fobjc-arc -DCC26_KIND=2 -DCC26_MODULE_CLASS=CC26AirplaneModule -DCC26_VC_CLASS=CC26AirplaneViewController

CC26CellularModule_FILES = Module.m
CC26CellularModule_FRAMEWORKS = UIKit
CC26CellularModule_INSTALL_PATH = /Library/ControlCenter/Bundles
CC26CellularModule_RESOURCE_DIRS = Resources/Cellular
CC26CellularModule_CFLAGS = -fobjc-arc -DCC26_KIND=3 -DCC26_MODULE_CLASS=CC26CellularModule -DCC26_VC_CLASS=CC26CellularViewController

CC26AirDropModule_FILES = Module.m
CC26AirDropModule_FRAMEWORKS = UIKit
CC26AirDropModule_INSTALL_PATH = /Library/ControlCenter/Bundles
CC26AirDropModule_RESOURCE_DIRS = Resources/AirDrop
CC26AirDropModule_CFLAGS = -fobjc-arc -DCC26_KIND=4 -DCC26_MODULE_CLASS=CC26AirDropModule -DCC26_VC_CLASS=CC26AirDropViewController

CC26HotspotModule_FILES = Module.m
CC26HotspotModule_FRAMEWORKS = UIKit
CC26HotspotModule_INSTALL_PATH = /Library/ControlCenter/Bundles
CC26HotspotModule_RESOURCE_DIRS = Resources/Hotspot
CC26HotspotModule_CFLAGS = -fobjc-arc -DCC26_KIND=5 -DCC26_MODULE_CLASS=CC26HotspotModule -DCC26_VC_CLASS=CC26HotspotViewController

include $(THEOS_MAKE_PATH)/bundle.mk
