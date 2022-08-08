# Requirements for xcode project generation:
# sudo easy_install pip
# sudo pip install pbxproj

SWIFT_BUILD_FLAGS=--configuration release

all: build
	
build:
	swift build -v $(SWIFT_BUILD_FLAGS)

clean:
	rm -rf .build

test:
	swift test -v

update:
	swift package update

benchmark:
	/opt/homebrew/bin/wrk -t 4 -c 100 http://localhost:8080/hello/world

docker:
	-docker buildx create --name local_builder
	-DOCKER_HOST=tcp://192.168.1.198:2376 docker buildx create --name local_builder --platform linux/amd64 --append
	-docker buildx use local_builder
	-docker buildx inspect --bootstrap
	-docker login
	docker buildx build --platform linux/amd64,linux/arm64 --push -t kittymac/picaroon .
