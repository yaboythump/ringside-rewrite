# Grave Mistakes - Nintendo DS funeral home sim.
# Builds with the official BlocksDS toolchain: install BlocksDS
# (https://blocksds.skylyrac.net) or use the skylyrac/blocksds Docker image, then run `make`.
# tools/llvm/build.sh builds the same sources with stock clang when Wonderful
# Toolchain isn't available; that is how the copy bundled in Retro Duo is made.

NAME		:= GraveMistakes
GAME_TITLE	:= Grave Mistakes
GAME_SUBTITLE	:= Funeral Home Sim
GAME_AUTHOR	:= Built with BlocksDS
GAME_ICON	:= icon.bmp
SOURCEDIRS	:= source
# No WiFi or music library needed: sound effects are PSG tones through libnds.
ARM7ELF		:= $(BLOCKSDS)/sys/arm7/main_core/arm7_minimal.elf
NDSTOOL_ARGS	:= -g GMFH 01 "GRAVEMISTAKE"

include $(BLOCKSDS)/sys/default_makefiles/rom_arm9/Makefile
