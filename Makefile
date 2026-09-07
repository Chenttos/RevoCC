ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:16.0
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = RevoCC
RevoCC_FILES = Tweak.xm
RevoCC_CFLAGS = -fobjc-arc -Wno-error=deprecated-declarations
RevoCC_FRAMEWORKS = UIKit QuartzCore
RevoCC_PRIVATE_FRAMEWORKS = ControlCenterUIKit ControlCenterServices

include $(THEOS_MAKE_PATH)/tweak.mk
