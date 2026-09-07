# ╔═══════════════════════════════════════════════════════════════════════════════════╗
# ║  Based on the Makefile from https://github.com/Chasmical/flag-emojis-for-windows  ║
# ╚═══════════════════════════════════════════════════════════════════════════════════╝

# Use bash, and run commands in a recipe in the same shell instance
SHELL := /bin/bash
.ONESHELL:

# As I'm using a WSL to emulate Unix, some operations (particularly I/O intensive ones, like git)
# are better off-loaded back to Windows by using `git.exe` (from Windows' PATH) instead of `git`.
# `git.exe` is used instead of `git` automatically if: 1. it's on a WSL at all, and 2. the current
# directory is somewhere in /mnt/* (that's where Windows' partitions (e.g. C:, D:) are).

IS_WSL := $(shell [[ -n "$$WSL_DISTRO_NAME" && $$PWD == /mnt/* ]] && echo yes)

define find_exe
$(if $(IS_WSL),$(shell command -v $1.exe >/dev/null && echo $1.exe || echo $1),$1)
endef
define find_ps1
$(if $(IS_WSL),$(shell command -v $1.ps1 >/dev/null && echo pwsh.exe -nop -c $1.ps1 || echo $1),$1)
endef

GIT := $(call find_exe,git)
DOTNET := $(call find_exe,dotnet)
NANOEMOJI := $(call find_exe,nanoemoji)
INKSCAPE := $(call find_exe,inkscape)
MAGICK := $(call find_exe,magick)
MKBITMAP := $(call find_exe,mkbitmap)
POTRACE := $(call find_exe,potrace)
FONTTOOLS := $(call find_exe,fonttools)
HB_VIEW := $(call find_exe,hb-view)
7Z := $(call find_exe,7z)

SVGO := $(call find_ps1,svgo)

# This is used for parallelization in recipes. The recipes themselves are run in an order.
CPU_CORES := $(shell cat /proc/cpuinfo | grep processor | wc -l)

# These are the only commands that should be run through the CLI
.PHONY: build package test test-vars clean rebuild



build: build/merged.ttf

package: build/Segoe.UI.Emoji.with.Pride.Flags.zip

# Can be overriden with `make test FLAGS_PER_LINE=8`
FLAGS_PER_LINE ?= 8

test: build/tests/flags_$(FLAGS_PER_LINE).png build/tests/flags_$(FLAGS_PER_LINE)_bw.png

test-vars:
	@printf "%s\n" GIT=$(GIT) DOTNET=$(DOTNET) \
		NANOEMOJI=$(NANOEMOJI) INKSCAPE=$(INKSCAPE) \
		MAGICK=$(MAGICK) MKBITMAP=$(MKBITMAP) POTRACE=$(POTRACE) \
		FONTTOOLS=$(FONTTOOLS) HB_VIEW=$(HB_VIEW) \
		7Z=$(7Z) SVGO="$(SVGO)" \
		CPU_CORES=$(CPU_CORES)

clean:
	rm -rf build

rebuild: clean
	@$(MAKE) build

build/assets.manifest: assets/svg/*.svg
	@mkdir -p $(@D)
	stat -c '%n %y' assets/svg/*.svg >$@

# Find all pride flag glyphs in the repo
build/glyph-paths.txt: build/assets.manifest
	ls assets/svg/*.svg >$@.tmp && mv $@.tmp $@



# I could have used Make's wildcards or patterns (*.svg, %.svg), but decided against them, as they
# bloated the process and slowed Make down significantly (it's definitely because I'm using a WSL
# instead of a proper Unix environment). So I decided to use manifests, that keep track of files
# matching a pattern, and that get updated only when something changes.

# When glyph-paths.txt changes, copy the glyphs over to svg-color/*.svg
build/svg-color/.manifest: build/glyph-paths.txt
	@mkdir -p $(@D)

	changed=$$(for glyph in $$(cat $<); do
		color=$(@D)/$${glyph##*/};
		[ "$$color" -nt "$$glyph" ] || echo "$$glyph";
	done);

	if [ -n "$$changed" ]; then
		count=$$(echo "$$changed" | wc -l)
		echo "Copying $$count glyphs from assets/svg..."

		echo "$$changed" | xargs -n 20 -P "$(CPU_CORES)" $(SVGO) --quiet --multipass -o $(@D) -i
		touch $@
	fi

# When svg-color/*.svg change, re-build whatever changed in svg-bw/*.svg
build/svg-bw/.manifest: build/svg-color/.manifest
	@mkdir -p $(@D)

	changed=$$(for color in build/svg-color/*.svg; do
		bw=$(@D)/$${color##*/};
		[ "$$bw" -nt "$$color" ] || echo "$$color";
	done);

	if [ -n "$$changed" ]; then
		count=$$(echo "$$changed" | wc -l)
		echo "Converting $$count glyphs to B&W..."

		echo "$$changed" | xargs -n 1 -P "$(CPU_CORES)" sh -c '
			bw=$(@D)/$${1##*/};
			echo "Converting to B&W $${bw##*/}...";
# Prevents random errors when running multiple Inkscapes in parallel:
# https://gitlab.com/inkscape/inkscape/-/work_items/4716#note_1898150983
			export SELF_CALL=xxx;

			$(INKSCAPE) -w 1000 -h 1000 --export-filename "$$bw.png" "$$1";
			$(MAGICK) "$$bw.png" -gravity center -extent 1066x1066 "$$bw.bmp";
			$(MKBITMAP) -g -s 1 -f 10 -o "$$bw.pgm" "$$bw.bmp";
			$(POTRACE) --flat -s -W 36pt -H 36pt -o "$$bw" "$$bw.pgm";
# Note: SVGO can't meaningfully optimize Potrace's output. It removes metadata and transforms,
# and converts int coords to float coords, resulting in an average 50% size increase. But, we
# do need to change the width and height from 36pt to just 36, so it's sized correctly.
			sed -i '\''s/width="36.000000pt" height="36.000000pt" //g'\'' "$$bw";
			rm "$$bw.png" "$$bw.bmp" "$$bw.pgm";
		' sh

		touch $@
	fi



# When the svg-color/ manifest changes, rebuild the font with color flags
build/pride.flags.color/Font.ttf: build/svg-color/.manifest
	@echo "Building $@..."
	@$(NANOEMOJI) --color_format glyf_colr_0 --upem 2048 --width 2812 \
		--transform "scale(1.666666) translate(-554.666666, 85.333333)" \
		--build_dir build/pride.flags.color \
		$$(ls -1 build/svg-color/*.svg)

# When the svg-bw/ manifest changes, rebuild the font with b&w flags
build/pride.flags.bw/Font.ttf: build/svg-bw/.manifest
	@echo "Building $@..."
	@$(NANOEMOJI) --color_format glyf --upem 2048 --width 2812 \
		--transform "scale(1.95) translate(-554.666666, 21.333333)" \
		--build_dir build/pride.flags.bw \
		$$(ls -1 build/svg-bw/*.svg)



build/pride.flags.color/Font.ttx: build/pride.flags.color/Font.ttf
	@rm -f $@
	@echo "Decompiling $<..."
	@$(FONTTOOLS) ttx $<

build/pride.flags.bw/Font.ttx: build/pride.flags.bw/Font.ttf
	@rm -f $@
	@echo "Decompiling $<..."
	@$(FONTTOOLS) ttx $<

# Merge all the fonts into one
build/merged-pre.ttx: scripts/gen_merged_font.cs assets/seguiemj.ttx build/pride.flags.color/Font.ttx build/pride.flags.bw/Font.ttx
	@echo "Generating $@..."
	@$(DOTNET) $^ $@

build/merged-pre.ttf: build/merged-pre.ttx
	@rm -f $@
	@echo "Recompiling $@..."
	@$(FONTTOOLS) ttx $<

build/merged.ttf: scripts/post_process_font.cs build/merged-pre.ttf $(wildcard notice.txt)
	@$(DOTNET) $< $(word 2,$^) $@



# Rename merged.ttf to this, and package it into a zip
build/Segoe.UI.Emoji.with.Pride.Flags.ttf: build/merged.ttf
	@cp $< $@

build/Segoe.UI.Emoji.with.Pride.Flags.zip: build/Segoe.UI.Emoji.with.Pride.Flags.ttf
	@rm -f $@
	@cd $(<D) && $(7Z) a -tzip -mx=9 $(@F) $(<F)



# Group flags into lines and render them using hb-view
build/tests/flags_$(FLAGS_PER_LINE).txt: scripts/print_glyphs.cs build/glyph-paths.txt
	@mkdir -p $(@D)
	@$(DOTNET) $^ | xargs -n $(FLAGS_PER_LINE) | tr -d " " | sed 's/^/🏳️‍⚧️/; s/$$/🏳️‍🌈/' >$@

build/tests/flags_$(FLAGS_PER_LINE).png: build/merged.ttf build/tests/flags_$(FLAGS_PER_LINE).txt
	@$(HB_VIEW) $< --output-file="$@" --text-file="$(word 2,$^)" --background=none

build/tests/flags_$(FLAGS_PER_LINE)_bw.png: build/merged.ttf build/tests/flags_$(FLAGS_PER_LINE).txt
	@$(HB_VIEW) $< --output-file="$@" --text-file="$(word 2,$^)" --draw
