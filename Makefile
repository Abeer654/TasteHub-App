# TasteHub Stage 1 build
#
# The AI extractor uses libcurl. On Debian/Ubuntu install libcurl4-openssl-dev.
# `make test` is offline: backend_test injects a fake RecipeExtractor.
# `make gemini-smoke` is the optional real-network check.

CXX ?= g++
CXXFLAGS ?= -std=c++17 -O2 -Wall -Wextra -pthread
CURL_LIBS ?= -lcurl

.PHONY: all test gemini-smoke clean

all: backend_test upload search rating

backend_test: backend_test.cpp BackendService.h AiRecipe.h RecipeCore.h json.hpp
	$(CXX) $(CXXFLAGS) backend_test.cpp -o $@ $(CURL_LIBS)

upload: upload.cpp ConsoleTools.h AiRecipe.h RecipeCore.h json.hpp
	$(CXX) $(CXXFLAGS) upload.cpp -o $@ $(CURL_LIBS)

search: search.cpp ConsoleTools.h RecipeCore.h json.hpp
	$(CXX) $(CXXFLAGS) search.cpp -o $@

rating: rating.cpp ConsoleTools.h RecipeCore.h json.hpp
	$(CXX) $(CXXFLAGS) rating.cpp -o $@

test: backend_test
	./backend_test

gemini-smoke: tests/gemini_smoke.cpp AiRecipe.h RecipeCore.h json.hpp
	$(CXX) $(CXXFLAGS) -I. tests/gemini_smoke.cpp -o /tmp/opencode/tastehub-gemini-smoke $(CURL_LIBS)
	/tmp/opencode/tastehub-gemini-smoke

clean:
	rm -f backend_test upload search rating
