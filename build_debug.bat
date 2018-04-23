copy mpv_options_debug.txt build\mpv_options.txt
set MPV_ADD_CFLAGS=-O0\ -gdwarf-2\ -fno-omit-frame-pointer
media-autobuild_suite.bat

#-O0\ -gdwarf-2\ -fno-omit-frame-pointer