TARGET = iphone:clang:latest:6.0
ARCHS = armv7
TARGET_IPHONEOS_DEPLOYMENT_VERSION = 6.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = PerfHUD
PerfHUD_FILES = Tweak.xm PerfHUDWindow.m PerfHUDView.m PerfMetrics.m
PerfHUD_FRAMEWORKS = UIKit CoreGraphics QuartzCore IOKit CoreFoundation
PerfHUD_CFLAGS = -fno-objc-arc

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += cli
include $(THEOS_MAKE_PATH)/aggregate.mk

after-install::
	install.exec "killall -9 SpringBoard"
