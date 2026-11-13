# TasteHub build
#
# The AI extractor uses libcurl. On Debian/Ubuntu install libcurl4-openssl-dev.
# `make run` builds and starts the HTTP server on 127.0.0.1:8080.
# Open http://127.0.0.1:8080 in Chrome for a small recipe page.
# `make demo` starts it on 0.0.0.0:8080 so other devices can connect.
# `make test` is offline: backend_test injects a fake RecipeExtractor.
# `make http-test` starts a temporary HTTP server and runs the API smoke test.
# `make gemini-smoke` is the optional real-network check.
# `make app-run` starts the Flutter client on Linux desktop.
# `make app-test` runs Flutter analyze and widget/model tests.
# `make app-apk` builds a debug APK; override APP_API_URL for a phone.
#
# third_party/httplib.h is cpp-httplib v0.65.0 (MIT):
# https://github.com/yhirose/cpp-httplib

CXX ?= g++
CXXFLAGS ?= -std=c++17 -O2 -Wall -Wextra -pthread
CURL_LIBS ?= -lcurl
INCLUDES := -Isrc -Ithird_party
BUILD_DIR := build

.PHONY: all server run demo reset-demo test http-test gemini-smoke \
        app app-build app-run app-test app-api-check app-apk clean

# Defaults for `make run` and `make demo`. Override them on the command line,
# for example: make run PORT=9000
PORT ?= 8080
DATA_DIR ?= data
UPLOADS_DIR ?= $(DATA_DIR)/uploads

# Flutter client settings.
APP_DIR := tastehub_app
APP_API_URL ?= http://127.0.0.1:8080

CORE_HEADERS := src/core/Models.h src/core/Storage.h src/core/Search.h \
                src/core/AiRecipe.h src/core/BackendService.h
CLI_HEADERS := src/cli/Console.h src/cli/UploadMenu.h \
               src/cli/SearchMenu.h src/cli/ReviewMenu.h
HTTP_HEADERS := third_party/httplib.h third_party/json.hpp
WEB_HEADERS := src/WebPage.h

all: $(BUILD_DIR)/tastehub $(BUILD_DIR)/backend_test $(BUILD_DIR)/tastehub-server

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(BUILD_DIR)/tastehub: src/main.cpp $(CLI_HEADERS) $(CORE_HEADERS) third_party/json.hpp | $(BUILD_DIR)
	$(CXX) $(CXXFLAGS) $(INCLUDES) src/main.cpp -o $@ $(CURL_LIBS)

$(BUILD_DIR)/backend_test: tests/backend_test.cpp $(CORE_HEADERS) third_party/json.hpp | $(BUILD_DIR)
	$(CXX) $(CXXFLAGS) $(INCLUDES) tests/backend_test.cpp -o $@ $(CURL_LIBS)

$(BUILD_DIR)/tastehub-server: src/server.cpp $(WEB_HEADERS) $(CORE_HEADERS) $(HTTP_HEADERS) | $(BUILD_DIR)
	$(CXX) $(CXXFLAGS) $(INCLUDES) src/server.cpp -o $@ $(CURL_LIBS)

server: $(BUILD_DIR)/tastehub-server

# Build and run the server with sane defaults: make run
# Use a different port or data folder: make run PORT=9000 DATA_DIR=my-data
run: $(BUILD_DIR)/tastehub-server
	./$(BUILD_DIR)/tastehub-server --host 127.0.0.1 --port $(PORT) \
		--data-dir $(DATA_DIR) --uploads-dir $(UPLOADS_DIR)

# Same as `run`, but reachable from phones and other devices on the network.
demo: $(BUILD_DIR)/tastehub-server
	./$(BUILD_DIR)/tastehub-server --host 0.0.0.0 --port $(PORT) \
		--data-dir $(DATA_DIR) --uploads-dir $(UPLOADS_DIR)

# Replace local demo recipes/users and clear uploads (with a backup).
reset-demo:
	bash scripts/reset-demo.sh

test: $(BUILD_DIR)/backend_test
	./$(BUILD_DIR)/backend_test

http-test: $(BUILD_DIR)/tastehub-server
	python3 tests/smoke_test.py

gemini-smoke: tests/gemini_smoke.cpp src/core/AiRecipe.h src/core/Models.h third_party/json.hpp | $(BUILD_DIR)
	$(CXX) $(CXXFLAGS) $(INCLUDES) tests/gemini_smoke.cpp -o $(BUILD_DIR)/gemini_smoke $(CURL_LIBS)
	./$(BUILD_DIR)/gemini_smoke

# ------------------------------------------------------------
#  Flutter client
# ------------------------------------------------------------

app: app-build

# Release build for Linux desktop.
app-build:
	cd $(APP_DIR) && flutter build linux --release \
		--dart-define=API_BASE_URL=$(APP_API_URL)

# Run the client on Linux desktop. Start `make run` in another terminal first.
app-run:
	cd $(APP_DIR) && flutter run -d linux \
		--dart-define=API_BASE_URL=$(APP_API_URL)

# Analyze and run all app tests. No server is needed; HTTP is mocked.
app-test:
	cd $(APP_DIR) && flutter analyze && flutter test

# Check the app's API client against a running server.
app-api-check:
	cd $(APP_DIR) && dart run tool/api_smoke.dart $(APP_API_URL)

# Debug APK for a phone. Use the laptop's LAN or Tailscale IP:
#   make app-apk APP_API_URL=http://100.x.y.z:8080
app-apk:
	cd $(APP_DIR) && flutter build apk --debug \
		--dart-define=API_BASE_URL=$(APP_API_URL)

clean:
	rm -rf $(BUILD_DIR)
	rm -f tastehub tastehub-server backend_test upload search rating
