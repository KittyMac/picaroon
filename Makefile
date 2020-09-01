# Requirements for xcode project generation:
# sudo easy_install pip
# sudo pip install pbxproj

SWIFT_BUILD_FLAGS=--configuration release

all: fix_bad_header_files build
	
fix_bad_header_files:
	-@find  . -name '._*.h' -exec rm {} \;

build:
	./meta/CombinedBuildPhases.sh
	swift build -v $(SWIFT_BUILD_FLAGS)

clean:
	rm -rf .build

test:
	swift test -v

update:
	swift package update

xcode:
	swift package generate-xcodeproj
	meta/addBuildPhase picaroon.xcodeproj/project.pbxproj 'Picaroon::PicaroonFramework' 'cd $${SRCROOT}; ./meta/CombinedBuildPhases.sh'

