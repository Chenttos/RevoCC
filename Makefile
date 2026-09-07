ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:16.0
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AsterCC
AsterCC_FILES = Tweak.xm
AsterCC_CFLAGS = -fobjc-arc
AsterCC_FRAMEWORKS = UIKit QuartzCore
AsterCC_PRIVATE_FRAMEWORKS = ControlCenterUIKit ControlCenterServices

include $(THEOS_MAKE_PATH)/tweak.mk
SUBPROJECTS += prefs
include $(THEOS_MAKE_PATH)/aggregate.mk
