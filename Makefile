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
	sleep 2
	open picaroon.xcodeproj

benchmark:
	/usr/local/bin/wrk -t 4 -c 100 http://localhost:8080/hello/world

docker:
	-DOCKER_HOST=tcp://192.168.1.209:2376 docker buildx create --name cluster --platform linux/arm64/v8 --append
	-DOCKER_HOST=tcp://192.168.1.198:2376 docker buildx create --name cluster --platform linux/amd64 --append
	-docker buildx use cluster
	-docker buildx inspect --bootstrap
	-docker login
	docker buildx build --platform linux/amd64,linux/arm64/v8 --push -t kittymac/sextant .