ifeq ($(THEOS_PACKAGE_SCHEME),rootless)
	TARGET := iphone:clang:latest:15.0
else
	TARGET := iphone:clang:latest:12.2
endif


include $(THEOS)/makefiles/common.mk

TWEAK_NAME = BunnyTweak

BunnyTweak_FILES = $(shell find Sources/BunnyTweak -name '*.swift') $(shell find Sources/BunnyTweakC -name '*.m' -o -name '*.xm' -o -name '*.c' -o -name '*.mm' -o -name '*.cpp')
BunnyTweak_FRAMEWORKS = UIKit Foundation SystemConfiguration
BunnyTweak_SWIFTFLAGS = -ISources/BunnyTweakC/include
BunnyTweak_CFLAGS = -fobjc-arc -ISources/BunnyTweakC/include

BunnyTweak_BUNDLE_NAME = BunnyPatches
BunnyTweak_BUNDLE_RESOURCE_DIRS = Resources

include $(THEOS_MAKE_PATH)/tweak.mk
