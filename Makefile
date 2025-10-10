# Requirements for xcode project generation:
# sudo easy_install pip
# sudo pip install pbxproj

SWIFT_BUILD_FLAGS=--configuration release

all: build
	
build:
	swift build -Xswiftc -enable-library-evolution -v $(SWIFT_BUILD_FLAGS)

clean:
	rm -rf .build

test:
	swift test -v

update:
	swift package update

profile: clean
	mkdir -p /tmp/picaroon.stats
	swift build \
		--configuration release \
		-Xswiftc -stats-output-dir \
		-Xswiftc /tmp/picaroon.stats \
		-Xswiftc -trace-stats-events \
		-Xswiftc -driver-time-compilation \
		-Xswiftc -debug-time-function-bodies


benchmark:
	/opt/homebrew/bin/wrk -t 4 -c 100 http://localhost:8080/hello/world

linux:
	-DOCKER_HOST=ssh://rjbowli@192.168.111.203 docker buildx create --name cluster_builder203 --platform linux/amd64
	-docker buildx create --name cluster_builder203 --platform linux/arm64 --append
	-docker buildx use cluster_builder203
	-docker buildx inspect --bootstrap
	-docker login
	
	swift package resolve
	docker buildx build --platform linux/arm64 --push -t kittymac/picaroon .
	#linux/amd64,

android:
	ANDROID_NDK_HOME=~/Downloads/android-ndk-r27d ~/Library/org.swift.swiftpm/swift-sdks/swift-6.2-RELEASE-android-0.1.artifactbundle/swift-android/scripts/setup-android-sdk.sh
	swiftly run swift build  --configuration=release --swift-sdk aarch64-unknown-linux-android28 +6.2
