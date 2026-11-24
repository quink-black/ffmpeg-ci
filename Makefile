.DEFAULT_GOAL := all

path ?= ../ffmpeg
do_test ?=
skip_test_case ?=
enable_asan ?= 0
enable_opt ?= 0

ffmpeg_options = --path "$(path)" --enable_asan "$(enable_asan)" --enable_opt "$(enable_opt)"
.PHONY: all deps ffmpeg clean FORCE

all deps:
	./cibuild.sh deps

.%: FORCE
	./cibuild.sh deps --deps "$(@:.%=%)"

ffmpeg:
	./cibuild.sh $(ffmpeg_options) --skip-test $(do_test) --skip-test-case "$(skip_test_case)"

clean:
	./cibuild.sh $(ffmpeg_options) --clean

FORCE:
