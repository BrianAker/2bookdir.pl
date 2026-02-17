PREFIX ?= /usr/local
DESTDIR ?=
BINDIR := $(DESTDIR)$(PREFIX)/bin
PROVE ?= prove
FIXTURE_DIR := .test-fixtures
FIXTURE_WAV := $(FIXTURE_DIR)/source-2h.wav
FIXTURE_MP3 := $(FIXTURE_DIR)/source-2h.mp3
FIXTURE_M4B := $(FIXTURE_DIR)/source-2h.m4b
FIXTURE_STAMP := $(FIXTURE_DIR)/.ready

.PHONY: install test check prepare-fixtures

install:
	install -d "$(BINDIR)"
	install -m 0755 2bookdir.pl "$(BINDIR)/2bookdir.pl"

prepare-fixtures: $(FIXTURE_STAMP)

$(FIXTURE_STAMP):
	@mkdir -p "$(FIXTURE_DIR)"
	@command -v ffmpeg >/dev/null 2>&1 || { echo "Error: ffmpeg is required to build test fixtures."; exit 1; }
	@ffmpeg -hide_banner -loglevel error -version >/dev/null 2>&1 || { echo "Error: ffmpeg is present but not runnable. Please fix ffmpeg runtime dependencies."; exit 1; }
	@command -v tone >/dev/null 2>&1 || { echo "Error: tone is required to build test fixtures."; exit 1; }
	@tone --version >/dev/null 2>&1 || { echo "Error: tone is present but not runnable. Please fix tone runtime dependencies."; exit 1; }
	@if [ ! -f "$(FIXTURE_WAV)" ]; then \
		echo "Creating $(FIXTURE_WAV) (2-hour WAV fixture)..."; \
		ffmpeg -hide_banner -loglevel error -f lavfi -i anullsrc=r=8000:cl=mono -t 02:00:00 -c:a pcm_mulaw "$(FIXTURE_WAV)"; \
	fi
	@if [ ! -f "$(FIXTURE_MP3)" ]; then \
		echo "Creating $(FIXTURE_MP3) from WAV fixture..."; \
		ffmpeg -hide_banner -loglevel error -y -i "$(FIXTURE_WAV)" -c:a libmp3lame -b:a 64k "$(FIXTURE_MP3)"; \
	fi
	@if [ ! -f "$(FIXTURE_M4B)" ]; then \
		echo "Creating $(FIXTURE_M4B) from WAV fixture..."; \
		ffmpeg -hide_banner -loglevel error -y -i "$(FIXTURE_WAV)" -c:a aac -b:a 64k "$(FIXTURE_M4B)"; \
	fi
	@touch "$(FIXTURE_STAMP)"

test: prepare-fixtures
	$(PROVE) -lv t

check: test
