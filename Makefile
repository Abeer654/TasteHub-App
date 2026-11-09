# TasteHub Stage 1 build
#
# The AI extractor uses libcurl. On Debian/Ubuntu install libcurl4-openssl-dev.
# `make test` is offline: backend_test injects a fake RecipeExtractor.
# `make gemini-smoke` is the optional real-network check.

CXX ?= g++
CXXFLAGS ?= -std=c++17 -O2 -Wall -Wextra -pthread
CURL_LIBS ?= -lcurl
INCLUDES := -Isrc -Ithird_party
BUILD_DIR := build

.PHONY: all test gemini-smoke clean

CORE_HEADERS := src/core/Models.h src/core/Storage.h src/core/Search.h \
                src/core/AiRecipe.h src/core/BackendService.h
CLI_HEADERS := src/cli/Console.h src/cli/UploadMenu.h \
               src/cli/SearchMenu.h src/cli/ReviewMenu.h

all: $(BUILD_DIR)/tastehub $(BUILD_DIR)/backend_test

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(BUILD_DIR)/tastehub: src/main.cpp $(CLI_HEADERS) $(CORE_HEADERS) third_party/json.hpp | $(BUILD_DIR)
	$(CXX) $(CXXFLAGS) $(INCLUDES) src/main.cpp -o $@ $(CURL_LIBS)

$(BUILD_DIR)/backend_test: tests/backend_test.cpp $(CORE_HEADERS) third_party/json.hpp | $(BUILD_DIR)
	$(CXX) $(CXXFLAGS) $(INCLUDES) tests/backend_test.cpp -o $@ $(CURL_LIBS)

test: $(BUILD_DIR)/backend_test
	./$(BUILD_DIR)/backend_test

gemini-smoke: tests/gemini_smoke.cpp src/core/AiRecipe.h src/core/Models.h third_party/json.hpp | $(BUILD_DIR)
	$(CXX) $(CXXFLAGS) $(INCLUDES) tests/gemini_smoke.cpp -o $(BUILD_DIR)/gemini_smoke $(CURL_LIBS)
	./$(BUILD_DIR)/gemini_smoke

clean:
	rm -rf $(BUILD_DIR)
	rm -f tastehub backend_test upload search rating
