#!/bin/bash
shopt -s extglob

FFMPEG_BASE_OPTS=(--pkg-config-flags=--static)
alloptions="$*"
echo -e "\nBuild start: $(date +"%F %T %z")" >> "$LOCALBUILDDIR"/newchangelog
echo -ne "\e]0;media-autobuild_suite\007"

while true; do
  case $1 in
--cpuCount=* ) cpuCount="${1#*=}"; shift ;;
--build32=* ) build32="${1#*=}"; shift ;;
--build64=* ) build64="${1#*=}"; shift ;;
--mp4box=* ) mp4box="${1#*=}"; shift ;;
--rtmpdump=* ) rtmpdump="${1#*=}"; shift ;;
--vpx=* ) vpx="${1#*=}"; shift ;;
--x264=* ) x264="${1#*=}"; shift ;;
--x265=* ) x265="${1#*=}"; shift ;;
--other265=* ) other265="${1#*=}"; shift ;;
--flac=* ) flac="${1#*=}"; shift ;;
--fdkaac=* ) fdkaac="${1#*=}"; shift ;;
--mediainfo=* ) mediainfo="${1#*=}"; shift ;;
--sox=* ) sox="${1#*=}"; shift ;;
--ffmpeg=* ) ffmpeg="${1#*=}"; shift ;;
--ffmpegUpdate=* ) ffmpegUpdate="${1#*=}"; shift ;;
--ffmpegChoice=* ) ffmpegChoice="${1#*=}"; shift ;;
--mplayer=* ) mplayer="${1#*=}"; shift ;;
--mpv=* ) mpv="${1#*=}"; shift ;;
--deleteSource=* ) deleteSource="${1#*=}"; shift ;;
--license=* ) license="${1#*=}"; shift ;;
--standalone=* ) standalone="${1#*=}"; shift ;;
--stripping* ) stripping="${1#*=}"; shift ;;
--packing* ) packing="${1#*=}"; shift ;;
--xpcomp=* ) xpcomp="${1#*=}"; shift ;;
--logging=* ) logging="${1#*=}"; shift ;;
--bmx=* ) bmx="${1#*=}"; shift ;;
    -- ) shift; break ;;
    -* ) echo "Error, unknown option: '$1'."; exit 1 ;;
    * ) break ;;
  esac
done

[[ -f "$LOCALBUILDDIR"/media-suite_helper.sh ]] &&
    source "$LOCALBUILDDIR"/media-suite_helper.sh

buildProcess() {
echo -e "\n\t${orange_color}Starting $bits compilation of all tools${reset_color}"
[[ -f "$HOME"/custom_build_options ]] &&
    echo "Imported custom build options (unsupported)" &&
    source "$HOME"/custom_build_options

cd_safe "$LOCALBUILDDIR"

do_getFFmpegConfig "$license"
do_getMpvConfig
if [[ -n "$alloptions" ]]; then
    {
        echo '#!/bin/bash'
        echo 'FFMPEG_DEFAULT_OPTS=('
        printf '\t"%s"\n' "${FFMPEG_DEFAULT_OPTS[@]}"
        echo ')'
        echo "bash $LOCALBUILDDIR/media-suite_compile.sh $alloptions"
    } > "$LOCALBUILDDIR/last_run"
    unset alloptions
fi

echo -e "\n\t${orange_color}Starting $bits compilation of global tools${reset_color}"

if [[ $ffmpeg != "n" ]] && enabled libopenjpeg; then
    do_pacman_remove openjpeg2
    do_uninstall q j{config,error,morecfg,peglib}.h libjpeg.a

    _check=(libopenjp2.{a,pc})
    do_vcs "https://github.com/uclouvain/openjpeg.git" libopenjp2
    if [[ $compile = "true" ]]; then
        do_uninstall {include,lib}/openjpeg-2.1 libopen{jpwl,mj2}.{a,pc} "${_check[@]}"
        do_cmakeinstall -DBUILD_CODEC=off
        do_checkIfExist
    fi
fi

if [[ "$mplayer" = "y" ]] || ! mpv_disabled libass ||
    { [[ $ffmpeg != "n" ]] && enabled_any libass libfreetype {lib,}fontconfig libfribidi; }; then
    do_pacman_remove freetype fontconfig harfbuzz fribidi

    if do_pkgConfig "freetype2 = 18.3.12" "2.6.3"; then
        _check=(libfreetype.{l,}a freetype2.pc)
        do_wget -h 0037b25a8c090bc8a1218e867b32beb1 \
            "http://download.savannah.gnu.org/releases/freetype/freetype-2.6.3.tar.bz2"
        do_uninstall include/freetype2 bin-global/freetype-config "${_check[@]}"
        do_separate_confmakeinstall global --with-harfbuzz=no
        do_checkIfExist
    fi

    _deps=(freetype2.pc)
    if enabled_any {lib,}fontconfig && do_pkgConfig "fontconfig = 2.11.94"; then
        do_pacman_remove python2-lxml
        _check=(libfontconfig.{l,}a fontconfig.pc)
        [[ -d fontconfig-2.11.94 && ! -f fontconfig-2.11.94/fc-blanks/fcblanks.h ]] && rm -rf fontconfig-2.11.94
        do_wget -h 479be870c7f83f15f87bac085b61d641 \
            "https://www.freedesktop.org/software/fontconfig/release/fontconfig-2.11.94.tar.gz"
        do_uninstall include/fontconfig "${_check[@]}"
        [[ $standalone = y ]] || sed -i Makefile.in -e 's/SUBDIRS = .*/SUBDIRS = fontconfig src/' \
            -e '/fc-cache fc-cat fc-list/,+1d' \
            -e 's/CROSS_COMPILING_TRUE/CROSS_COMPILING_FALSE/'
        do_separate_confmakeinstall global
        do_checkIfExist
    fi

    [[ ! $harfbuzz_ver ]] &&
        harfbuzz_ver=$(/usr/bin/curl -sl "https://www.freedesktop.org/software/harfbuzz/release/" |
            /usr/bin/grep -Po '(?<=href=)"harfbuzz.*.tar.bz2"') &&
        harfbuzz_ver="$(get_last_version "$harfbuzz_ver" "" "1\.\d+\.\d+")"
    [[ $harfbuzz_ver ]] || harfbuzz_ver="1.2.3"
    _deps=({freetype2,fontconfig}.pc)
    if do_pkgConfig "harfbuzz = ${harfbuzz_ver}"; then
        do_pacman_install ragel
        _check=(libharfbuzz.{l,}a harfbuzz.pc)
        do_wget "https://www.freedesktop.org/software/harfbuzz/release/harfbuzz-${harfbuzz_ver}.tar.bz2"
        do_uninstall include/harfbuzz "${_check[@]}"
        do_separate_confmakeinstall --with-icu=no --with-glib=no --with-gobject=no
        do_checkIfExist
    fi

    if do_pkgConfig "fribidi = 0.19.7"; then
        _check=(libfribidi.{l,}a fribidi.pc)
        [[ $standalone = y ]] && _check+=(bin-global/fribidi.exe)
        do_wget -h 6c7e7cfdd39c908f7ac619351c1c5c23 \
            "http://fribidi.org/download/fribidi-0.19.7.tar.bz2"
        do_uninstall include/fribidi bin-global/fribidi.exe "${_check[@]}"
        [[ $standalone = y ]] || sed -i 's|bin doc test||' Makefile.in
        do_separate_confmakeinstall global --disable-deprecated --with-glib=no --disable-debug
        do_checkIfExist
    fi
fi

if { [[ $ffmpeg != "n" ]] && ! disabled_any sdl ffplay; } &&
    do_pkgConfig "sdl = 1.2.15"; then
    do_pacman_remove SDL
    _check=(bin-global/sdl-config libSDL{,main}.{l,}a sdl.pc)
    do_wget -h 9d96df8417572a2afb781a7c4c811a85 \
        "https://www.libsdl.org/release/SDL-1.2.15.tar.gz"
    do_uninstall include/SDL "${_check[@]}"
    CFLAGS="-DDECLSPEC=" do_separate_confmakeinstall global
    sed -i "s/-mwindows//" "$LOCALDESTDIR/bin-global/sdl-config"
    sed -i "s/-mwindows//" "$LOCALDESTDIR/lib/pkgconfig/sdl.pc"
    do_checkIfExist
fi

if { { [[ $ffmpeg != n ]] && enabled gnutls; } ||
    [[ $rtmpdump = y && $license != nonfree ]]; }; then
    [[ -z "$gnutls_ver" ]] && gnutls_ver="$(/usr/bin/curl -sl "ftp://ftp.gnutls.org/gcrypt/gnutls/v3.4/")"
    [[ -n "$gnutls_ver" ]] &&
        gnutls_ver="$(get_last_version "$gnutls_ver" "xz$" '3\.4\.\d+(\.\d+)?')" || gnutls_ver="3.4.9"

    if do_pkgConfig "gnutls = $gnutls_ver"; then
        do_pacman_install nettle
        do_uninstall q include/nettle libnettle.a nettle.pc

        _check=(libgnutls.{,l}a gnutls.pc)
        do_wget "ftp://ftp.gnutls.org/gcrypt/gnutls/v3.4/gnutls-${gnutls_ver}.tar.xz"
        do_uninstall include/gnutls "${_check[@]}"
        do_separate_confmakeinstall \
            --disable-cxx --disable-doc --disable-tools --disable-tests --without-p11-kit --disable-rpath \
            --disable-libdane --without-idn --without-tpm --enable-local-libopts --disable-guile
        sed -i 's/-lgnutls *$/-lgnutls -lnettle -lhogweed -lcrypt32 -lws2_32 -lz -lgmp -lintl -liconv/' \
            "$LOCALDESTDIR/lib/pkgconfig/gnutls.pc"
        do_checkIfExist
    fi
fi

if { { [[ $ffmpeg != n ]] && enabled openssl; } ||
    [[ $rtmpdump = y && $license = nonfree ]]; }; then
    [[ ! "$libressl_ver" ]] &&
        libressl_ver="$(/usr/bin/curl -sl "ftp://ftp.openbsd.org/pub/OpenBSD/LibreSSL/")" &&
        libressl_ver="$(get_last_version "$libressl_ver" "tar.gz$" '2\.\d+\.\d+')"
    [[ "$libressl_ver" ]] || libressl_ver="2.3.2"

    if do_pkgConfig "libssl = $libressl_ver"; then
        _check=(tls.h lib{crypto,ssl,tls}.{pc,{,l}a} openssl.pc)
        [[ $standalone = y ]] && _check+=("bin-global/openssl.exe")
        do_wget "ftp://ftp.openbsd.org/pub/OpenBSD/LibreSSL/libressl-${libressl_ver}.tar.gz"
        do_uninstall etc/ssl include/openssl "${_check[@]}"
        do_patch "libressl-0001-pc-add-platform-specific-libs-to-Libs.private.patch"
        _sed="man"
        [[ $standalone = y ]] || _sed="apps tests $_sed"
        sed -ri "s;(^SUBDIRS .*) $_sed;\1;" Makefile.in
        sed -i 's;DESTDIR)/\$;DESTDIR)$;g' apps/openssl/Makefile.in
        do_separate_confmakeinstall global
        do_checkIfExist
        unset _sed
    fi
fi

if [[ $mediainfo = y || $bmx = y ]]; then
    if do_pkgConfig "libcurl = 7.47.1"; then
        _check=(curl/curl.h libcurl.{{,l}a,pc})
        [[ $standalone = y ]] && _check+=(bin-global/curl.exe)
        do_wget -h 9ea3123449439bbd960cd25cf98796fb "https://curl.haxx.se/download/curl-7.47.1.tar.bz2"
        do_uninstall include/curl bin-global/curl-config "${_check[@]}"
        [[ $standalone = y ]] || sed -ri "s;(^SUBDIRS = lib) src (include) scripts;\1 \2;" Makefile.in
        do_separate_confmakeinstall global --without-{ssl,gnutls,ca-bundle,ca-path,random,libidn,libssh2} \
            --with-{winssl,winidn} --enable-sspi --disable-{debug,manual}
        do_checkIfExist
    fi
fi

if enabled libwebp; then
    do_pacman_install libtiff
    _check=(libwebp{,mux}.{{,l}a,pc})
    do_vcs "https://chromium.googlesource.com/webm/libwebp"
    if [[ $compile = "true" ]]; then
        do_autoreconf
        [[ -f Makefile ]] && log distclean make distclean
        if [[ $standalone = y ]]; then
            extracommands=(--enable-libwebp{demux,decoder,extras}
                LIBS="$($PKG_CONFIG --libs libpng libtiff-4)" --enable-experimental)
            _check+=(libwebp{,mux,demux,decoder,extras}.{{,l}a,pc}
                bin-global/{{c,d}webp,webpmux}.exe)
        else
            extracommands=()
            sed -i 's/ examples man//' Makefile.in
        fi
        do_uninstall include/webp bin-global/gif2webp.exe "${_check[@]}"
        do_separate_confmakeinstall global --enable-swap-16bit-csp \
            --enable-libwebpmux "${extracommands[@]}"
        do_checkIfExist
    fi
fi

syspath=$(cygpath -S)
[[ $bits = "32bit" && -d "$syspath/../SysWOW64" ]] && syspath="$syspath/../SysWOW64"
if enabled opencl && [[ -f "$syspath/OpenCL.dll" ]]; then
    echo -e "${orange_color}Tesseract, FFmpeg and related apps will depend on OpenCL.dll${reset_color}"
    _check=(libOpenCL.a)
    if ! files_exist "${_check[@]}"; then
        cd_safe "$LOCALBUILDDIR"
        do_pacman_install opencl-headers
        create_build_dir opencl
        gendef "$syspath/OpenCL.dll" >/dev/null 2>&1
        [[ -f OpenCL.def ]] && dlltool -l libOpenCL.a -d OpenCL.def -k -A
        [[ -f libOpenCL.a ]] && mv -f libOpenCL.a "$LOCALDESTDIR"/lib/
        do_checkIfExist
    fi
else
    do_removeOption --enable-opencl
fi
unset syspath

if enabled libtesseract; then
    do_pacman_remove tesseract-ocr
    do_pacman_install libtiff
    if do_pkgConfig "lept = 1.73"; then
        _check=(liblept.{,l}a lept.pc)
        do_wget -h 092cea2e568cada79fff178820397922 \
            "http://www.leptonica.com/source/leptonica-1.73.tar.gz"
        do_uninstall include/leptonica "${_check[@]}"
        do_separate_confmakeinstall --disable-programs --without-libopenjpeg --without-libwebp
        do_checkIfExist
    fi

    _check=(libtesseract.{,l}a tesseract.pc)
    do_vcs "https://github.com/tesseract-ocr/tesseract.git"
    if [[ $compile = "true" ]]; then
        do_autogen
        _check+=(bin-global/tesseract.exe)
        do_uninstall include/tesseract "${_check[@]}"
        sed -i "s|Libs.private.*|& -lstdc++|" tesseract.pc.in
        do_separate_confmakeinstall global --disable-graphics --disable-tessdata-prefix \
            LIBLEPT_HEADERSDIR="$LOCALDESTDIR/include" \
            LIBS="$($PKG_CONFIG --libs lept libtiff-4)" --datadir="$LOCALDESTDIR/bin-global" \
            $(enabled opencl && echo "--enable-opencl")
        if [[ ! -f $LOCALDESTDIR/bin-global/tessdata/eng.traineddata ]]; then
            do_pacman_install tesseract-data-eng
            mkdir -p "$LOCALDESTDIR"/bin-global/tessdata
            do_install "$MINGW_PREFIX/share/tessdata/eng.traineddata" bin-global/tessdata/
            printf "%s\n" "You can get more language data here:"\
                   "https://github.com/tesseract-ocr/tessdata/blob/master/"\
                   "Just download <lang you want>.traineddata and copy it to this directory."\
                    > "$LOCALDESTDIR"/bin-global/tessdata/need_more_languages.txt
        fi
        do_checkIfExist
    fi
fi

if { { [[ $ffmpeg != "n" ]] && enabled librubberband; } ||
    ! mpv_disabled rubberband; } && do_pkgConfig "rubberband = 1.8.1"; then
    _check=(librubberband.a rubberband.pc rubberband/{rubberband-c,RubberBandStretcher}.h)
    do_vcs https://github.com/lachs0r/rubberband.git
    do_uninstall "${_check[@]}"
    log "distclean" make distclean
    do_make PREFIX="$LOCALDESTDIR" install-static
    do_checkIfExist
    add_to_remove
fi

if { [[ $ffmpeg != "n" ]] && enabled libzimg; } ||
    { ! pc_exists zimg && ! mpv_disabled vapoursynth; } then
    _check=(zimg{.h,++.hpp} libzimg.{,l}a zimg.pc)
    do_vcs "https://github.com/sekrit-twc/zimg.git"
    if [[ $compile = "true" ]]; then
        do_uninstall "${_check[@]}"
        [[ -f Makefile ]] && log distclean make distclean
        grep -q "Libs.private" zimg.pc.in || sed -i "/Cflags:/ i\Libs.private: -lstdc++" zimg.pc.in
        do_autoreconf
        do_separate_confmakeinstall
        do_checkIfExist
    fi
fi

if [[ $ffmpeg != n ]] && enabled chromaprint; then
    do_pacman_install fftw
    _check=(libchromaprint.{a,pc} chromaprint.h)
    do_vcs "https://bitbucket.org/acoustid/chromaprint.git" libchromaprint
    if [[ $compile = "true" ]]; then
        do_uninstall "${_check[@]}"
        do_cmakeinstall -DWITH_FFTW3=on
        do_checkIfExist
    fi
    do_addOption --extra-libs=-lfftw3 --extra-libs=-lstdc++ --extra-cflags=-DCHROMAPRINT_NODLL
fi

echo -e "\n\t${orange_color}Starting $bits compilation of audio tools${reset_color}"

if [[ $ffmpeg != "n" ]] && enabled libilbc; then
    _check=(ilbc.h libilbc.{{l,}a,pc})
    do_vcs "https://github.com/TimothyGu/libilbc.git"
    if [[ $compile = "true" ]]; then
        do_autoreconf
        [[ -f Makefile ]] && log distclean make distclean
        do_uninstall "${_check[@]}"
        do_separate_confmakeinstall
        do_checkIfExist
    fi
fi

if [[ $flac = y || $sox = y ]] ||
    enabled_any libtheora libvorbis libspeex; then
    do_pacman_install libogg
    do_uninstall q include/ogg share/aclocal/ogg.m4 libogg.{l,}a ogg.pc
fi

if enabled_any libvorbis libtheora; then
    do_pacman_install libvorbis
    do_uninstall q include/vorbis share/aclocal/vorbis.m4 \
        libvorbis{,enc,file}.{l,}a vorbis{,enc,file}.pc
fi

if enabled libopus; then
    if do_pkgConfig "opus = 1.1.2"; then
        _check=(libopus.{l,}a opus.pc)
        do_wget -h 1f08a661bc72930187893a07f3741a91 \
            "http://downloads.xiph.org/releases/opus/opus-1.1.2.tar.gz"
        do_uninstall include/opus "${_check[@]}"
        # needed to allow building shared FFmpeg with libopus
        sed -i 's, __declspec(dllexport),,' include/opus_defines.h
        do_separate_confmakeinstall --disable-doc
        do_checkIfExist
    fi

    do_pacman_install opusfile
    do_uninstall q opus/opusfile.h libopus{file,url}.{l,}a opus{file,url}.pc
fi

if enabled libspeex && do_pkgConfig "speex = 1.2rc2"; then
    _check=(libspeex.{l,}a speex.pc)
    [[ $standalone = y ]] && _check+=(bin-audio/speex{enc,dec}.exe)
    do_wget -h 6ae7db3bab01e1d4b86bacfa8ca33e81 \
        "http://downloads.xiph.org/releases/speex/speex-1.2rc2.tar.gz"
    do_uninstall include/speex "${_check[@]}"
    do_patch speex-mingw-winmm.patch
    do_separate_confmakeinstall audio --enable-vorbis-psy \
        "$([[ $standalone = y ]] && echo --enable-binaries || echo --disable-binaries)"
    do_checkIfExist
fi

_check=(libFLAC.{l,}a bin-audio/flac.exe flac{,++}.pc)
if [[ $flac = y ]] && { do_pkgConfig "flac = 1.3.1" || ! files_exist "${_check[@]}"; }; then
    do_wget -h b9922c9a0378c88d3e901b234f852698 \
        "http://downloads.xiph.org/releases/flac/flac-1.3.1.tar.xz"
    _check+=(bin-audio/metaflac.exe)
    do_uninstall include/FLAC{,++} "${_check[@]}"
    [[ -f Makefile ]] && log distclean make distclean
    do_separate_confmakeinstall audio --disable-xmms-plugin --disable-doxygen-docs
    do_checkIfExist
fi

do_uninstall q include/vo-aacenc libvo-aacenc.{l,}a vo-aacenc.pc

if [[ $ffmpeg != "n" ]] && enabled_any libopencore-amr{wb,nb}; then
    do_pacman_install opencore-amr
    do_uninstall q include/opencore-amr{nb,wb} libopencore-amr{nb,wb}.{l,}a opencore-amr{nb,wb}.pc
fi

if { [[ $ffmpeg != n ]] && enabled libvo-amrwbenc; } &&
    do_pkgConfig "vo-amrwbenc = 0.1.2"; then
    do_wget_sf -h 588205f686adc23532e31fe3646ddcb6 \
        "opencore-amr/vo-amrwbenc/vo-amrwbenc-0.1.2.tar.gz"
    _check=(libvo-amrwbenc.{l,}a vo-amrwbenc.pc)
    do_uninstall include/vo-amrwbenc "${_check[@]}"
    [[ -f Makefile ]] && log distclean make distclean
    do_separate_confmakeinstall
    do_checkIfExist
fi

if { [[ $ffmpeg != n ]] && enabled libfdk-aac; } ||
    [[ $fdkaac = "y" ]]; then
    _check=(libfdk-aac.{l,}a fdk-aac.pc)
    do_vcs "https://github.com/mstorsjo/fdk-aac"
    if [[ $compile = "true" ]]; then
        do_autoreconf
        do_uninstall include/fdk-aac "${_check[@]}"
        [[ -f Makefile ]] && log distclean make distclean
        CXXFLAGS+=" -O2 -fno-exceptions -fno-rtti" do_separate_confmakeinstall
        do_checkIfExist
    fi
    if [[ $standalone = y ]]; then
        _check=(bin-audio/fdkaac.exe)
        _deps=(fdk-aac.pc)
        do_vcs "https://github.com/nu774/fdkaac" bin-fdk-aac
        if [[ $compile = "true" ]]; then
            do_autoreconf
            do_uninstall "${_check[@]}"
            [[ -f Makefile ]] && log distclean make distclean
            CXXFLAGS+=" -O2" do_separate_confmakeinstall audio
            do_checkIfExist
        fi
    else
        ! disabled libfdk-aac && do_addOption --enable-libfdk-aac
    fi
fi

if enabled libfaac; then
    _check=(libfaac.a faac{,cfg}.h)
    _ver="1.28"
    _hash="c5dde68840cefe46532089c9392d1df0"
    [[ $standalone = y ]] && _check+=(bin-audio/faac.exe)
    if files_exist "${_check[@]}" &&
        grep -q "$_ver" "$LOCALDESTDIR/lib/libfaac.a"; then
        do_print_status "faac $_ver" "$green_color" "Up-to-date"
    else
        do_wget_sf -h "$_hash" "faac/faac-src/faac-${_ver}/faac-${_ver}.tar.bz2"
        ./bootstrap 2>/dev/null
        do_uninstall "${_check[@]}"
        [[ $standalone = y ]] || sed -i 's|frontend||' Makefile.am
        do_separate_confmakeinstall audio --without-mp4v2
        do_checkIfExist
    fi
fi

_check=(bin-audio/oggenc.exe)
if [[ $standalone = y ]] && enabled libvorbis && ! files_exist "${_check[@]}"; then
    do_pacman_install flac
    do_vcs "https://git.xiph.org/vorbis-tools.git" vorbis-tools
    _check+=(bin-audio/oggdec.exe)
    do_autoreconf
    do_uninstall "${_check[@]}"
    [[ -f Makefile ]] && log distclean make distclean
    extracommands=()
    enabled libspeex || extracommands+=(--without-speex)
    do_separate_confmakeinstall audio --disable-ogg123 --disable-vorbiscomment \
        --disable-vcut --disable-ogginfo "${extracommands[@]}"
    do_checkIfExist
    add_to_remove
fi

_check=(bin-audio/opusenc.exe)
if [[ $standalone = y ]] && enabled libopus &&
    test_newer installed opus.pc "${_check[0]}"; then
    do_pacman_install flac
    _check+=(bin-audio/opus{dec,info}.exe)
    do_wget -h 20682e4d8d1ae9ec5af3cf43e808b8cb \
        "http://downloads.xiph.org/releases/opus/opus-tools-0.1.9.tar.gz"
    do_uninstall "${_check[@]}"
    [[ -f Makefile ]] && log distclean make distclean
    extracommands=()
    do_separate_confmakeinstall audio "${extracommands[@]}"
    do_checkIfExist
fi

if { [[ $ffmpeg != "n" ]] && enabled libsoxr; } && do_pkgConfig "soxr = 0.1.2"; then
    _check=(soxr.h libsoxr.a soxr.pc)
    do_wget_sf -h 0866fc4320e26f47152798ac000de1c0 "soxr/soxr-0.1.2-Source.tar.xz"
    sed -i 's|NOT WIN32|UNIX|g' ./src/CMakeLists.txt
    do_uninstall "${_check[@]}"
    do_cmakeinstall -DWITH_OPENMP=off -DWITH_LSR_BINDINGS=off
    do_checkIfExist
fi

if enabled libmp3lame; then
    _check=(libmp3lame.{l,}a)
    _ver="3.99.5"
    [[ $standalone = y ]] && _check+=(bin-audio/lame.exe)
    if files_exist "${_check[@]}" &&
        grep -q "$_ver" "$LOCALDESTDIR/lib/libmp3lame.a"; then
        do_print_status "lame $_ver" "$green_color" "Up-to-date"
    else
        do_wget_sf -h 84835b313d4a8b68f5349816d33e07ce "lame/lame/3.99/lame-${_ver}.tar.gz"
        if grep -q "xmmintrin\.h" configure.in configure; then
            do_patch lame-fixes.patch
            touch recently_updated
            do_autoreconf
        fi
        do_uninstall include/lame "${_check[@]}"
        [[ -f Makefile ]] && log distclean make distclean
        do_separate_confmakeinstall audio --disable-decoder \
            "$([[ $standalone = y ]] || echo --disable-frontend)"
        do_checkIfExist
    fi
fi

if [[ $ffmpeg != "n" ]] && enabled libgme; then
    _check=(libgme.{a,pc})
    do_vcs "https://bitbucket.org/mpyne/game-music-emu.git" libgme
    if [[ $compile = "true" ]]; then
        do_uninstall include/gme "${_check[@]}"
        do_cmakeinstall
        do_checkIfExist
    fi
fi

if enabled libtwolame; then
    do_pacman_install twolame
    do_uninstall q twolame.h bin-audio/twolame.exe libtwolame.{l,}a twolame.pc
    do_addOption --extra-cflags=-DLIBTWOLAME_STATIC
fi

if [[ $ffmpeg != "n" ]] && enabled libbs2b && do_pkgConfig "libbs2b = 3.1.0"; then
    _check=(libbs2b.{{l,}a,pc})
    do_wget_sf -h c1486531d9e23cf34a1892ec8d8bfc06 "bs2b/libbs2b/3.1.0/libbs2b-3.1.0.tar.bz2"
    do_uninstall include/bs2b "${_check[@]}"
    do_patch "libbs2b-disable-sndfile.patch"
    sed -i "s|bin_PROGRAMS = .*||" src/Makefile.in
    [[ -f Makefile ]] && log distclean make distclean
    do_separate_confmakeinstall
    do_checkIfExist
fi

if [[ $sox = y ]] && enabled_all libvorbis libopus libspeex; then
    _check=(libsndfile.{l,}a sndfile.{h,pc})
    do_vcs "https://github.com/erikd/libsndfile.git" sndfile
    if [[ $compile = "true" ]]; then
        do_pacman_install flac
        do_autogen
        do_uninstall include/sndfile.hh "${_check[@]}"
        [[ -f Makefile ]] && log "distclean" make distclean
        sed -i 's/ examples regtest tests programs//g' Makefile.am
        do_separate_confmakeinstall
        do_checkIfExist
    fi
fi

if [[ $sox = y ]]; then
    do_pacman_install libmad
    [[ $flac = y ]] || do_pacman_install flac
    do_uninstall lib{gnurx,regex}.a regex.h magic.h libmagic.{l,}a bin-global/file.exe

    _check=(bin-audio/sox.exe)
    do_vcs "http://git.code.sf.net/p/sox/code" sox
    if [[ $compile = "true" ]]; then
        sed -i 's|found_libgsm=yes|found_libgsm=no|g' configure.ac
        do_autoreconf
        do_uninstall sox.{pc,h} bin-audio/{soxi,play,rec}.exe libsox.{l,}a "${_check[@]}"
        [[ -f Makefile ]] && log "distclean" make distclean
        extracommands=()
        enabled libvorbis || extracommands+=(--without-oggvorbis)
        enabled libopus || extracommands+=(--without-opus)
        enabled libtwolame || extracommands+=(--without-twolame)
        enabled libmp3lame || extracommands+=(--without-lame)
        do_separate_conf --disable-symlinks \
            LIBS='-lshlwapi -lz' "${extracommands[@]}"
        do_make
        do_install src/sox.exe bin-audio/
        do_checkIfExist
    fi
fi

if [[ $ffmpeg != "n" ]] && enabled libmodplug; then
    do_pacman_install libmodplug
    do_addOption --extra-cflags=-DMODPLUG_STATIC
fi

echo -e "\n\t${orange_color}Starting $bits compilation of video tools${reset_color}"

if [[ $rtmpdump = "y" ]] ||
    { [[ $ffmpeg != "n" ]] && enabled librtmp; }; then
    req=""
    pc_exists librtmp && req="$(pkg-config --print-requires "$(file_installed librtmp.pc)")"
    if enabled gnutls || [[ $rtmpdump = "y" && $license != "nonfree" ]]; then
        ssl=GnuTLS
        crypto=GNUTLS
        pc=gnutls
    else
        ssl=LibreSSL
        crypto=OPENSSL
        pc=libssl
    fi
    _check=(librtmp.{a,pc})
    _deps=("${pc}.pc")
    [[ $rtmpdump = "y" ]] && _check+=(bin-video/rtmpdump.exe)
    do_vcs "http://repo.or.cz/rtmpdump.git" librtmp
    if [[ $compile = "true" ]] || [[ $req != *$pc* ]]; then
        [[ $rtmpdump = y ]] && _check+=(bin-video/rtmp{suck,srv,gw}.exe)
        do_uninstall include/librtmp "${_check[@]}"
        [[ -f "librtmp/librtmp.a" ]] && log "clean" make clean
        _ver="$(printf '%s-%s-%s_%s-%s-static' "$(/usr/bin/grep -oP "(?<=^VERSION=).+" Makefile)" \
                "$(git log -1 --format=format:%cd-g%h --date=format:%Y%m%d)" "$ssl" \
                "$(pkg-config --modversion "$pc")" "${MINGW_CHOST%%-*}")"
        do_makeinstall XCFLAGS="$CFLAGS -I$MINGW_PREFIX/include" XLDFLAGS="$LDFLAGS" SHARED= \
            SYS=mingw prefix="$LOCALDESTDIR" bindir="$LOCALDESTDIR"/bin-video \
            sbindir="$LOCALDESTDIR"/bin-video mandir="$LOCALDESTDIR"/share/man \
            CRYPTO="$crypto" LIB_${crypto}="$(pkg-config --static --libs $pc) -lz" VERSION="$_ver"
        do_checkIfExist
        unset crypto pc req
    fi
fi

if [[ $ffmpeg != "n" ]] && enabled libtheora; then
    do_pacman_install libtheora
    do_uninstall q include/theora libtheora{,enc,dec}.{l,}a theora{,enc,dec}.pc
fi

if [[ $vpx != n ]]; then
    _check=(libvpx.a vpx.pc)
    extracommands=()
    [[ $standalone = y ]] && _check+=(bin-video/vpxenc.exe)
    do_vcs "https://chromium.googlesource.com/webm/libvpx" vpx
    if [[ $compile = "true" ]]; then
        do_uninstall include/vpx bin-video/vpxdec.exe "${_check[@]}"
        [[ -f config.mk ]] && log "distclean" make distclean
        [[ $standalone = y ]] || extracommands+=(--disable-examples)
        create_build_dir
        [[ $bits = "32bit" ]] && target="x86-win32" || target="x86_64-win64"
        log "configure" ../configure --target="${target}-gcc" \
            --disable-shared --enable-static --disable-unit-tests --disable-docs \
            --enable-postproc --enable-vp9-postproc --enable-runtime-cpu-detect \
            --enable-vp9-highbitdepth --prefix="$LOCALDESTDIR" --disable-install-bins \
            "${extracommands[@]}"
        for _ff in *.mk; do
            sed -i 's;HAVE_GNU_STRIP=yes;HAVE_GNU_STRIP=no;' "$_ff"
        done
        do_make
        do_makeinstall
        if [[ $standalone = y ]]; then
            do_install vpx{enc,dec}.exe bin-video/
            _check+=(bin-video/vpxdec.exe)
        fi
        do_checkIfExist
        unset target extracommands
    fi
else
    pc_exists vpx || do_removeOption --enable-libvpx
fi

if [[ $other265 = "y" ]] || { [[ $ffmpeg != "n" ]] && enabled libkvazaar; }; then
    _check=(libkvazaar.{,l}a kvazaar.pc kvazaar.h)
    [[ $standalone = y ]] && _check+=(bin-video/kvazaar.exe)
    do_vcs "https://github.com/ultravideo/kvazaar.git"
    if [[ $compile = "true" ]]; then
        do_uninstall kvazaar_version.h "${_check[@]}"
        do_autogen
        [[ -f Makefile ]] && log distclean make distclean
        [[ $standalone = y || $other265 = y ]] ||
            sed -i "s|bin_PROGRAMS = .*||" src/Makefile.in
        do_separate_confmakeinstall video
        do_checkIfExist
    fi
fi

if [[ $mplayer = "y" ]] || ! mpv_disabled_all dvdread dvdnav; then
    _check=(libdvdread.{l,}a dvdread.pc)
    do_vcs "https://git.videolan.org/git/libdvdread.git" dvdread
    if [[ $compile = "true" ]]; then
        do_autoreconf
        do_uninstall include/dvdread "${_check[@]}"
        [[ -f Makefile ]] && log "distclean" make distclean
        do_separate_confmakeinstall
        do_checkIfExist
    fi
    grep -q 'ldl' "$LOCALDESTDIR"/lib/pkgconfig/dvdread.pc ||
        sed -i "/Libs:.*/ a\Libs.private: -ldl" "$LOCALDESTDIR"/lib/pkgconfig/dvdread.pc

    _check=(libdvdnav.{l,}a dvdnav.pc)
    do_vcs "https://git.videolan.org/git/libdvdnav.git" dvdnav
    if [[ $compile = "true" ]]; then
        do_autoreconf
        do_uninstall include/dvdnav "${_check[@]}"
        [[ -f Makefile ]] && log "distclean" make distclean
        do_separate_confmakeinstall
        do_checkIfExist
    fi
fi

if { [[ $ffmpeg != "n" ]] && enabled libbluray; } ||
    ! mpv_disabled libbluray; then
    _check=(libbluray.{{l,}a,pc})
    do_vcs "https://git.videolan.org/git/libbluray.git"
    if [[ $compile = "true" ]]; then
        [[ -f Makefile ]] && git clean -qxfd -e "/build_successful*" -e "/recently_updated"
        do_autoreconf
        do_uninstall include/libbluray "${_check[@]}"
        do_separate_confmakeinstall --enable-static --disable-{examples,bdjava,doxygen-doc,udf} \
            --without-{libxml2,fontconfig,freetype}
        do_checkIfExist
    fi
fi

if [[ $mplayer = "y" ]] || ! mpv_disabled libass ||
    { [[ $ffmpeg != "n" ]] && enabled libass; }; then
    _check=(ass/ass{,_types}.h libass.{{,l}a,pc})
    _deps=({freetype2,fontconfig,harfbuzz,fribidi}.pc)
    do_vcs "https://github.com/libass/libass.git"
    if [[ $compile = "true" ]]; then
        do_autoreconf
        do_uninstall "${_check[@]}"
        [[ -f Makefile ]] && log "distclean" make distclean
        extracommands=()
        enabled_any {lib,}fontconfig || extracommands+=(--disable-fontconfig)
        do_separate_confmakeinstall "${extracommands[@]}"
        do_checkIfExist
    fi
fi

if [[ $ffmpeg != "n" ]] && enabled libxavs && do_pkgConfig "xavs = 0.1." "0.1"; then
    _check=(libxavs.a xavs.{h,pc})
    do_vcs "https://github.com/Distrotech/xavs.git"
    [[ -f "libxavs.a" ]] && log "distclean" make distclean
    do_uninstall "${_check[@]}"
    sed -i 's|"NUL"|"/dev/null"|g' configure
    do_configure --host="$MINGW_CHOST" --prefix="$LOCALDESTDIR"
    do_make libxavs.a
    for _file in xavs.h libxavs.a xavs.pc; do do_install "$_file"; done
    do_checkIfExist
    add_to_remove
    unset _file
fi

if [[ $mediainfo = "y" ]]; then
    _check=(libzen.{a,pc})
    do_vcs "https://github.com/MediaArea/ZenLib" libzen
    if [[ $compile = "true" ]]; then
        do_uninstall include/ZenLib bin-global/libzen-config "${_check[@]}" libzen.la
        sed -i -e 's|NOT SIZE_T_IS_NOT_LONG|false|' -e 's|NOT WIN32|UNIX|' Project/CMake/CMakeLists.txt
        do_cmakeinstall Project/CMake
        do_checkIfExist
    fi

    _check=(libmediainfo.{a,pc})
    _deps=(libzen.pc)
    do_vcs "https://github.com/MediaArea/MediaInfoLib" libmediainfo
    if [[ $compile = "true" ]]; then
        do_uninstall include/MediaInfo{,DLL} bin-global/libmediainfo-config "${_check[@]}" libmediainfo.la
        sed -i 's|NOT WIN32|UNIX|g' Project/CMake/CMakeLists.txt
        do_cmakeinstall Project/CMake
        sed -i 's|libzen|libcurl libzen|' "$LOCALDESTDIR/lib/pkgconfig/libmediainfo.pc"
        do_checkIfExist
    fi

    _check=(bin-video/mediainfo.exe)
    _deps=(libmediainfo.pc)
    do_vcs "https://github.com/MediaArea/MediaInfo" mediainfo
    if [[ $compile = "true" ]]; then
        cd_safe Project/GNU/CLI
        do_autogen
        do_uninstall "${_check[@]}"
        [[ -f Makefile ]] && log distclean make distclean
        do_configure --build="$MINGW_CHOST" --disable-shared --bindir="$LOCALDESTDIR/bin-video" \
            --enable-staticlibs LIBS="$($PKG_CONFIG --libs libmediainfo)"
        do_makeinstall
        do_checkIfExist
    fi
fi

if [[ $ffmpeg != "n" ]] && enabled libvidstab; then
    _check=(libvidstab.a vidstab.pc)
    do_vcs "https://github.com/georgmartius/vid.stab.git" vidstab
    if [[ $compile = "true" ]]; then
        do_uninstall include/vid.stab "${_check[@]}"
        do_cmakeinstall
        do_checkIfExist
    fi
fi

if [[ $ffmpeg != "n" ]] && enabled libcaca; then
    do_pacman_install libcaca
    do_uninstall q libcaca.{l,}a caca.pc
    do_addOption --extra-cflags=-DCACA_STATIC
fi

_check=(libzvbi.{h,{l,}a})
_ver="0.2.35"
_hash="95e53eb208c65ba6667fd4341455fa27"
if { [[ $ffmpeg != "n" ]] && enabled libzvbi; } &&
    { ! files_exist "${_check[@]}" || ! grep -q "${_ver}" "$LOCALDESTDIR/lib/libzvbi.a"; }; then
    do_wget_sf -h "$_hash" "zapping/zvbi/${_ver}/zvbi-${_ver}.tar.bz2"
    do_uninstall "${_check[@]}" zvbi-0.2.pc
    do_patch "zvbi-win32.patch"
    do_patch "zvbi-ioctl.patch"
    [[ -f Makefile ]] && log distclean make distclean
    CFLAGS+=" -DPTW32_STATIC_LIB" do_separate_conf --disable-dvb --disable-bktr \
        --disable-nls --disable-proxy --without-doxygen LIBS="$LIBS -lpng"
    cd_safe src
    do_makeinstall
    do_checkIfExist
fi

if { [[ $ffmpeg != "n" ]] && enabled frei0r; } && do_pkgConfig "frei0r = 1.3.0"; then
    _check=(frei0r.{h,pc})
    do_wget -h 202375d1bcb545c1b6eb8f34e0260ec5 \
        "https://files.dyne.org/frei0r/releases/frei0r-plugins-1.4.tar.gz"
    sed -i 's/find_package (Cairo)//' "CMakeLists.txt"
    do_uninstall lib/frei0r-1 "${_check[@]}"
    do_cmakeinstall -DCMAKE_BUILD_TYPE=Release
    do_checkIfExist
fi

if [[ $ffmpeg != "n" ]] && enabled decklink; then
    _check=(DeckLinkAPI.h
           DeckLinkAPIVersion.h
           DeckLinkAPI_i.c)
    _hash=(cd04bb1f07f7aec30ba7944a6bae4378
           261f45f4fa8c69f75cbfaab6d8b68e7b
           871cacb23786aba031da0e7a7b505ff2)
    _ver="10.6.1"
    if files_exist -v "${_check[@]}" &&
        {
            count=0
            while [[ x"${_check[$count]}" != x"" ]]; do
                check_hash "$(file_installed "${_check[$count]}")" "${_hash[$count]}" || break
                let count+=1
            done
            test x"${_check[$count]}" = x""
        }; then
        do_print_status "DeckLinkAPI $_ver" "$green_color" "Up-to-date"
    else
        mkdir -p "$LOCALBUILDDIR/DeckLinkAPI" &&
            cd_safe "$LOCALBUILDDIR/DeckLinkAPI"
        count=0
        while [[ x"${_check[$count]}" != x"" ]]; do
            do_wget -r -c -h "${_hash[$count]}" "$LOCALBUILDDIR/extras/${_check[$count]}"
            do_install "${_check[$count]}"
            let count+=1
        done
        do_checkIfExist
    fi
    unset count
fi

if [[ $ffmpeg != "n" ]] && enabled nvenc; then
    _ver="6"
    _check=(nvEncodeAPI.h)
    _hash=(dcf25c9910a0af2b3aa20e969eb8c8ad)
    if files_exist -v "${_check[@]}" &&
        check_hash "$(file_installed "${_check[0]}")" "${_hash[0]}"; then
        do_print_status "nvEncodeAPI ${_ver}.0.1" "$green_color" "Up-to-date"
    else
        do_uninstall {cudaModuleMgr,drvapi_error_string,exception}.h \
            helper_{cuda{,_drvapi},functions,string,timer}.h \
            {nv{CPUOPSys,FileIO,Utils},NvHWEncoder}.h "${_check[0]}"
        mkdir -p "$LOCALBUILDDIR/NvEncAPI" &&
            cd_safe "$LOCALBUILDDIR/NvEncAPI"
        do_wget -r -c -h "${_hash[0]}" "$LOCALBUILDDIR/extras/${_check[0]}"
        do_install "${_check[0]}"
        do_checkIfExist
    fi
fi

if [[ $ffmpeg != "n" ]] && enabled libmfx; then
    _check=(libmfx.{{l,}a,pc})
    do_vcs "https://github.com/lu-zero/mfx_dispatch.git" libmfx
    if [[ $compile = "true" ]]; then
        do_autoreconf
        do_uninstall include/mfx "${_check[@]}"
        [[ -f Makefile ]] && log "distclean" make distclean
        do_separate_confmakeinstall
        do_checkIfExist
    fi
fi

if [[ $ffmpeg != "n" ]] && enabled libcdio; then
    [[ -d "$LOCALBUILDDIR/libcdio_paranoia-git" ]] &&
        add_to_remove "$LOCALBUILDDIR/libcdio_paranoia-git"
    do_uninstall q include/cdio libcdio_{cdda,paranoia}.{{l,}a,pc} bin-audio/cd-paranoia.exe
    do_pacman_install libcddb libcdio libcdio-paranoia
fi

if [[ $mp4box = "y" ]]; then
    _check=(libgpac_static.a)
    [[ $standalone = y ]] && _check+=(bin-video/MP4Box.exe)
    do_vcs "https://github.com/gpac/gpac.git"
    if [[ $compile = "true" ]]; then
        do_uninstall include/gpac "${_check[@]}"
        do_separate_conf --static-mp4box
        do_make
        log "install" make install-lib
        [[ $standalone = y ]] && do_install bin/gcc/MP4Box.exe bin-video/
        do_checkIfExist
    fi
fi

if [[ $x264 != n ]]; then
    _check=(x264{,_config}.h libx264.a x264.pc)
    [[ $standalone = y ]] && _check+=(bin-video/x264.exe)
    do_vcs "https://git.videolan.org/git/x264.git"
    if [[ $compile = "true" ]] ||
        { [[ $x264 != h ]] && /usr/bin/grep -q "X264_BIT_DEPTH *10" $(file_installed x264_config.h); } ||
        { [[ $x264 = h ]] && /usr/bin/grep -q "X264_BIT_DEPTH *8" $(file_installed x264_config.h); }; then
        extracommands=("--host=$MINGW_CHOST" "--prefix=$LOCALDESTDIR" --enable-static)
        if [[ $standalone = y && $x264 = f ]]; then
            _check=(libav{codec,format}.{a,pc})
            do_vcs "https://git.videolan.org/git/ffmpeg.git"
            do_uninstall include/lib{av{codec,device,filter,format,util,resample},{sw{scale,resample},postproc}} \
                lib{av{device,filter,util,resample},sw{scale,resample},postproc}.{a,pc} "${_check[@]}"
            [[ -f "config.mak" ]] && log "distclean" make distclean
            do_configure "${FFMPEG_BASE_OPTS[@]}" --prefix="$LOCALDESTDIR" --disable-programs \
            --disable-devices --disable-filters --disable-encoders --disable-muxers
            do_makeinstall
            do_checkIfExist
            cd_safe "$LOCALBUILDDIR"/x264-git
        else
            extracommands+=(--disable-lavf --disable-swscale --disable-ffms)
        fi

        if [[ $standalone = y ]]; then
            _check=(lsmash.h liblsmash.{a,pc})
            do_vcs "https://github.com/l-smash/l-smash.git" liblsmash
            if [[ $compile = "true" ]]; then
                [[ -f "config.mak" ]] && log "distclean" make distclean
                do_uninstall "${_check[@]}"
                create_build_dir
                log configure ../configure --prefix="$LOCALDESTDIR"
                do_make install-lib
                do_checkIfExist
            fi
            cd_safe "$LOCALBUILDDIR"/x264-git
            # x264 prefers and only uses lsmash if available
            extracommands+=(--disable-gpac)
        else
            extracommands+=(--disable-lsmash)
        fi

        _check=(x264{,_config}.h libx264.a x264.pc)
        [[ -f "config.h" ]] && log "distclean" make distclean
        if [[ $standalone = y ]]; then
            extracommands+=("--bindir=$LOCALDESTDIR/bin-video")
            _check+=(bin-video/x264.exe)
        else
            extracommands+=(--disable-gpac --disable-cli)
        fi
        if [[ $standalone = y && $x264 != h ]]; then
            do_print_progress "Building 10-bit x264"
            _check+=(bin-video/x264-10bit.exe)
            do_uninstall "${_check[@]}"
            create_build_dir
            CFLAGS="${CFLAGS// -O2 / }" log configure ../configure --bit-depth=10 "${extracommands[@]}"
            do_make
            do_install x264.exe bin-video/x264-10bit.exe
            cd_safe ..
            do_print_progress "Building 8-bit x264"
        else
            do_uninstall "${_check[@]}"
            if [[ $x264 = h ]]; then
                extracommands+=(--bit-depth=10) && do_print_progress "Building 10-bit x264"
            else
                do_print_progress "Building 8-bit x264"
            fi
        fi
        create_build_dir
        CFLAGS="${CFLAGS// -O2 / }" log configure ../configure "${extracommands[@]}"
        do_make
        do_makeinstall
        do_checkIfExist
        unset extracommands
    fi
else
    pc_exists x264 || do_removeOption --enable-libx264
fi

if [[ ! $x265 = "n" ]]; then
    _check=(x265{,_config}.h libx265.a x265.pc)
    [[ $standalone = y ]] && _check+=(bin-video/x265.exe)
    do_vcs "hg::https://bitbucket.org/multicoreware/x265"
    if [[ $compile = "true" ]]; then
        do_uninstall libx265{_main10,_main12}.a bin-video/libx265_main{10,12}.dll "${_check[@]}"
        do_patch x265-fix-git-describe.diff
        do_patch x265-fix-95bcd37.diff
        [[ $bits = "32bit" ]] && assembly="-DENABLE_ASSEMBLY=OFF"
        [[ $xpcomp = "y" ]] && xpsupport="-DWINXP_SUPPORT=ON"

        build_x265() {
            create_build_dir
            local build_root="$(pwd)"
            mkdir -p {8,10,12}bit

        do_x265_cmake() {
            log "cmake" cmake "$LOCALBUILDDIR/$(get_first_subdir)/source" -G Ninja \
            -DCMAKE_INSTALL_PREFIX="$LOCALDESTDIR" -DBIN_INSTALL_DIR="$LOCALDESTDIR/bin-video" \
            -DENABLE_SHARED=OFF -DENABLE_CLI=OFF -DHIGH_BIT_DEPTH=ON -DHG_EXECUTABLE=/usr/bin/hg.bat \
            $xpsupport "$@"
            log "ninja" ninja -j "${cpuCount:-1}"
        }
        [[ $standalone = y ]] && cli="-DENABLE_CLI=ON"

        if [[ $x265 != o* ]]; then
            cd_safe "$build_root/12bit"
            if [[ $x265 = s ]]; then
                do_print_progress "Building shared 12-bit lib"
                do_x265_cmake $assembly -DENABLE_SHARED=ON -DMAIN12=ON
                do_install libx265.dll bin-video/libx265_main12.dll
                _check+=(bin-video/libx265_main12.dll)
            else
                do_print_progress "Building 12-bit lib for multilib"
                do_x265_cmake $assembly -DEXPORT_C_API=OFF -DMAIN12=ON
                cp libx265.a ../8bit/libx265_main12.a
            fi
        fi

        if [[ $x265 != o8 ]]; then
            cd_safe "$build_root/10bit"
            if [[ $x265 = s ]]; then
                do_print_progress "Building shared 10-bit lib"
                do_x265_cmake $assembly -DENABLE_SHARED=ON
                do_install libx265.dll bin-video/libx265_main10.dll
                _check+=(bin-video/libx265_main10.dll)
            elif [[ $x265 = o10 ]]; then
                do_print_progress "Building 10-bit lib/bin"
                do_x265_cmake $assembly $cli
            else
                do_print_progress "Building 10-bit lib for multilib"
                do_x265_cmake $assembly -DEXPORT_C_API=OFF
                cp libx265.a ../8bit/libx265_main10.a
            fi
        fi

        if [[ $x265 != o10 ]]; then
            cd_safe "$build_root/8bit"
            if [[ $x265 = s || $x265 = o8 ]]; then
                do_print_progress "Building 8-bit lib/bin"
                do_x265_cmake $cli -DHIGH_BIT_DEPTH=OFF
            else
                do_print_progress "Building multilib lib/bin"
                do_x265_cmake -DEXTRA_LIB="x265_main10.a;x265_main12.a" -DEXTRA_LINK_FLAGS=-L. $cli \
                    -DHIGH_BIT_DEPTH=OFF -DLINKED_10BIT=ON -DLINKED_12BIT=ON
                mv libx265.a libx265_main.a
                ar -M <<EOF
CREATE libx265.a
ADDLIB libx265_main.a
ADDLIB libx265_main10.a
ADDLIB libx265_main12.a
SAVE
END
EOF
            fi
        fi
        }
        build_x265
        log "install" ninja -j "${cpuCount:=1}" install
        if [[ $standalone = y && $x265 = d ]]; then
            do_uninstall bin-video/x265-numa.exe
            do_print_progress "Building NUMA version of binary"
            xpsupport="" build_x265
            do_install x265.exe bin-video/x265-numa.exe
            _check+=(bin-video/x265-numa.exe)
        fi
        do_checkIfExist
        unset xpsupport assembly cli
    fi
else
    pc_exists x265 || do_removeOption "--enable-libx265"
fi

if [[ $ffmpeg != "n" ]]; then
    enabled gcrypt && do_pacman_install libgcrypt
    enabled libschroedinger && do_pacman_install schroedinger
    enabled libgsm && do_pacman_install gsm
    enabled libwavpack && do_pacman_install wavpack
    enabled libsnappy && do_pacman_install snappy
    if enabled libxvid; then
        do_pacman_install xvidcore
        [[ -f $MINGW_PREFIX/lib/xvidcore.a ]] && mv -f "$MINGW_PREFIX"/lib/{,lib}xvidcore.a
        [[ -f $MINGW_PREFIX/lib/xvidcore.dll.a ]] && mv -f "$MINGW_PREFIX"/lib/xvidcore.dll.a{,.dyn}
        [[ -f $MINGW_PREFIX/bin/xvidcore.dll ]] && mv -f "$MINGW_PREFIX"/bin/xvidcore.dll{,.disabled}
    fi
    if enabled libssh; then
        do_pacman_install libssh
        do_addOption --extra-cflags=-DLIBSSH_STATIC "--extra-ldflags=-Wl,--allow-multiple-definition"
        grep -q "Requires.private" "$MINGW_PREFIX"/lib/pkgconfig/libssh.pc ||
            sed -i "/Libs:/ i\Requires.private: libssl" "$MINGW_PREFIX"/lib/pkgconfig/libssh.pc
    fi
    enabled libdcadec && do_pacman_remove dcadec-git && do_pacman_install dcadec
    [[ -d "$LOCALBUILDDIR/dcadec-git" ]] && add_to_remove "$LOCALBUILDDIR/dcadec-git"
    do_uninstall q include/libdcadec libdcadec.a dcadec.pc

    do_hide_all_sharedlibs

    if [[ $ffmpeg = "s" ]]; then
        _check=(bin-video/ffmpegSHARED)
    else
        _check=(libavutil.{a,pc})
        disabled_any avfilter ffmpeg || _check+=(bin-video/ffmpeg.exe)
    fi
    [[ $ffmpegUpdate = y ]] && enabled_any lib{ass,x264,x265,vpx} &&
        _deps=({libass,x264,x265,vpx}.pc)
    do_vcs "https://git.videolan.org/git/ffmpeg.git"
    if [[ $compile = "true" ]]; then
        do_changeFFmpegConfig "$license"
        _patches=0
        do_patch "ffmpeg-0002-add-openhevc-intrinsics.patch" am && let _patches+=1
        [[ $_patches -gt 0 ]] && _patches=g"$(git rev-parse --short "HEAD~${_patches}")" ||
            _patches=""

        _uninstall=(include/libav{codec,device,filter,format,util,resample}
            include/lib{sw{scale,resample},postproc}
            libav{codec,device,filter,format,util,resample}.{a,pc}
            lib{sw{scale,resample},postproc}.{a,pc}
            )
        _check=()
        sedflags="prefix|bindir|extra-(cflags|libs|ldflags|version)|pkg-config-flags"

        # shared
        if [[ $ffmpeg != "y" ]] && [[ ! -f build_successful${bits}_shared ]]; then
            do_print_progress "Compiling ${bold_color}shared${reset_color} FFmpeg"
            [[ -f config.mak ]] && log "distclean" make distclean
            do_uninstall bin-video/ffmpegSHARED "${_uninstall[@]}"
            create_build_dir shared
            log configure ../configure --prefix="$LOCALDESTDIR/bin-video/ffmpegSHARED" \
                --disable-static --enable-shared "${FFMPEG_OPTS_SHARED[@]}" \
                --extra-version="$_patches"
            # cosmetics
            sed -ri "s/ ?--($sedflags)=(\S+[^\" ]|'[^']+')//g" config.h
            do_make && do_makeinstall
            if ! disabled_any programs avcodec avformat; then
                _check+=(bin-video/ffmpegSHARED)
                if ! disabled swresample; then
                    disabled_any avfilter ffmpeg || _check+=(bin-video/ffmpegSHARED/bin/ffmpeg.exe)
                    disabled_any sdl ffplay || _check+=(bin-video/ffmpegSHARED/bin/ffplay.exe)
                fi
                disabled ffprobe || _check+=(bin-video/ffmpegSHARED/bin/ffprobe.exe)
            fi
            cd_safe ..
            files_exist "${_check[@]}" && touch "build_successful${bits}_shared"
        fi

        # static
        if [[ $ffmpeg != "s" ]]; then
            do_print_progress "Compiling ${bold_color}static${reset_color} FFmpeg"
            [[ -f config.mak ]] && log "distclean" make distclean
            if ! disabled_any programs avcodec avformat; then
                _check+=(libavutil.{a,pc})
                if ! disabled swresample; then
                    disabled_any avfilter ffmpeg || _check+=(bin-video/ffmpeg.exe)
                    disabled_any sdl ffplay || _check+=(bin-video/ffplay.exe)
                fi
                disabled ffprobe || _check+=(bin-video/ffprobe.exe)
            fi
            do_uninstall bin-video/ff{mpeg,play,probe}.exe{,.debug} "${_uninstall[@]}"
            create_build_dir static
            log configure ../configure --prefix="$LOCALDESTDIR" --bindir="$LOCALDESTDIR"/bin-video \
                "${FFMPEG_OPTS[@]}" --extra-version="$_patches"
            # cosmetics
            sed -ri "s/ ?--($sedflags)=(\S+[^\" ]|'[^']+')//g" config.h
            do_make && do_makeinstall
            enabled debug &&
                create_debug_link "$LOCALDESTDIR"/bin-video/ff{mpeg,probe,play}.exe
            cd_safe ..
        fi
        do_checkIfExist
    fi
fi

if [[ $mplayer = "y" ]]; then
    [[ $license != "nonfree" ]] && faac=(--disable-faac --disable-faac-lavc)
    _check=(bin-video/m{player,encoder}.exe)
    do_vcs "svn::svn://svn.mplayerhq.hu/mplayer/trunk" mplayer

    if [[ $compile = "true" ]]; then
        do_uninstall "${_check[@]}"
        [[ -f config.mak ]] && log "distclean" make distclean
        if [[ ! -d ffmpeg ]]; then
            if [[ "$ffmpeg" != "n" ]] &&
                git clone -q "$LOCALBUILDDIR"/ffmpeg-git ffmpeg; then
                pushd ffmpeg >/dev/null
                git checkout -qf --no-track -B master origin/HEAD
                popd >/dev/null
            elif ! git clone "https://git.videolan.org/git/ffmpeg.git" ffmpeg; then
                rm -rf ffmpeg
                echo "Failed to get a FFmpeg checkout"
                echo "Please try again or put FFmpeg source code copy into ffmpeg/ manually."
                echo "Nightly snapshot: http://ffmpeg.org/releases/ffmpeg-snapshot.tar.bz2"
                echo "Either re-run the script or extract above to inside /build/mplayer-svn."
                do_prompt "<Enter> to continue or <Ctrl+c> to exit the script"
            fi
        fi
        if [[ -d ffmpeg ]]; then
            cd_safe ffmpeg
            git fetch -q origin
            git checkout -qf --no-track -B master origin/HEAD
            cd_safe ..
        else
            compilation_fail "Finding valid ffmpeg dir"
        fi

        grep -q "windows" libmpcodecs/ad_spdif.c ||
            sed -i '/#include "mp_msg.h/ a\#include <windows.h>' libmpcodecs/ad_spdif.c

        _notrequired="true"
        do_configure --prefix="$LOCALDESTDIR" --bindir="$LOCALDESTDIR"/bin-video --cc=gcc \
        --extra-cflags='-DPTW32_STATIC_LIB -O3 -std=gnu99 -DMODPLUG_STATIC' \
        --extra-libs='-llzma -lfreetype -lz -lbz2 -liconv -lws2_32 -lpthread -lwinpthread -lpng -lwinmm -ldl' \
        --extra-ldflags='-Wl,--allow-multiple-definition' --enable-static --enable-runtime-cpudetection \
        --disable-gif --disable-cddb "${faac[@]}" --with-dvdread-config="$PKG_CONFIG dvdread" \
        --with-freetype-config="$PKG_CONFIG freetype2" --with-dvdnav-config="$PKG_CONFIG dvdnav" &&
        do_makeinstall &&
        do_checkIfExist
        unset _notrequired
    fi
fi

if [[ $xpcomp = "n" && $mpv != "n" ]] && pc_exists libavcodec libavformat libswscale libavfilter; then
    [[ -d $LOCALBUILDDIR/waio-git ]] && do_uninstall include/waio libwaio.a &&
        add_to_remove "$LOCALBUILDDIR/waio-git"

    if ! mpv_disabled lua && [[ ${MPV_OPTS[@]} != "${MPV_OPTS[@]#--lua=lua51}" ]]; then
        do_pacman_install lua51
    elif ! mpv_disabled lua; then
        do_pacman_remove lua51
    if do_pkgConfig luajit; then
        _check=(libluajit-5.1.a luajit.pc luajit-2.0/luajit.h)
        do_vcs "http://luajit.org/git/luajit-2.0.git" luajit
        do_uninstall include/luajit-2.0 lib/lua "${_check[@]}"
        rm -rf ./temp
        [[ -f "src/luajit.exe" ]] && log "clean" make clean
        do_make BUILDMODE=static amalg
        do_makeinstall BUILDMODE=static PREFIX="$LOCALDESTDIR" DESTDIR="$(pwd)/temp"
        cd_safe "temp${LOCALDESTDIR}"
        mkdir -p "$LOCALDESTDIR/include/luajit-2.0"
        do_install include/luajit-2.0/*.h include/luajit-2.0/
        do_install lib/libluajit-5.1.a lib/
        # luajit comes with a broken .pc file
        sed -r -i "s/(Libs.private:).*/\1 -liconv/" lib/pkgconfig/luajit.pc
        do_install lib/pkgconfig/luajit.pc lib/pkgconfig/
        do_checkIfExist
        add_to_remove
    fi
    fi

    do_pacman_remove uchardet-git
    if ! mpv_disabled uchardet; then
        _check=(uchardet/uchardet.h uchardet.pc libuchardet.a)
        [[ $standalone = y ]] && _check+=(bin-global/uchardet.exe)
        do_vcs "https://github.com/BYVoid/uchardet.git"
        if [[ $compile = "true" ]]; then
            do_uninstall "${_check[@]}"
            do_cmakeinstall -DCMAKE_INSTALL_BINDIR="$LOCALDESTDIR/bin-global" \
                -DCMAKE_BUILD_TYPE=Release $([[ $standalone = y ]] || echo -DBUILD_BINARY=off)
            do_checkIfExist
        fi
    fi

    mpv_enabled libarchive && do_pacman_install libarchive
    ! mpv_disabled lcms2 && do_pacman_install lcms2

    if ! mpv_disabled egl-angle; then
        _check=(libEGL.{a,pc} libGLESv2.a)
        do_vcs "https://chromium.googlesource.com/angle/angle" angleproject
        if [[ $compile = "true" ]]; then
            do_patch "angle-0003-Add-makefile-and-pkgconfig-file-for-ANGLE.patch" am
            log "uninstall" make PREFIX="$LOCALDESTDIR" uninstall
            [[ -f libEGL.a ]] && log "clean" make clean
            do_makeinstall PREFIX="$LOCALDESTDIR"
            do_checkIfExist
        fi
    fi

    vsprefix=$(get_vs_prefix)
    if ! mpv_disabled vapoursynth && [[ -n $vsprefix ]]; then
        vsversion=$("$vsprefix"/vspipe -v | grep -Po "(?<=Core R)\d+")
        if [[ $vsversion -ge 24 ]]; then
            echo -e "${orange_color}Compiling mpv with Vapoursynth R${vsversion}${reset_color}"
        else
            vsprefix=""
            echo -e "${red_color}Update to at least Vapoursynth R24 to use with mpv${reset_color}"
        fi
        _check=(lib{vapoursynth,vsscript}.a vapoursynth{,-script}.pc
            vapoursynth/{VS{Helper,Script},VapourSynth}.h)
        if [[ x"$vsprefix" != x ]] &&
            { ! pc_exists "vapoursynth = $vsversion" || ! files_exist "${_check[@]}"; }; then
            do_uninstall {vapoursynth,vsscript}.lib "${_check[@]}"
            baseurl="https://github.com/vapoursynth/vapoursynth/raw/"
            [[ $(curl -sLw "%{response_code}" -o /dev/null "${baseurl}/R${vsversion}/configure.ac") != 404 ]] &&
                baseurl+="R${vsversion}" || baseurl+="master"
            mkdir -p "$LOCALBUILDDIR/vapoursynth" && cd_safe "$LOCALBUILDDIR/vapoursynth"

            # headers
            for _file in {VS{Helper,Script},VapourSynth}.h; do
                do_wget -r -c -q "${baseurl}/include/${_file}"
                [[ -f $_file ]] && do_install "$_file" "vapoursynth/$_file"
            done

            # import libs
            create_build_dir
            for _file in vapoursynth vsscript; do
                gendef - "$vsprefix/${_file}.dll" 2>/dev/null |
                    sed -r -e 's|^_||' -e 's|@[1-9]+$||' > "${_file}.def"
                dlltool -l "lib${_file}.a" -d "${_file}.def" 2>/dev/null
                rm -f "${_file}.def"
                [[ -f lib${_file}.a ]] && do_install "lib${_file}.a"
            done

            /usr/bin/curl -sL "$baseurl/pc/vapoursynth.pc.in" |
            sed -e "s;@prefix@;$LOCALDESTDIR;" \
                -e 's;@exec_prefix@;${prefix};' \
                -e 's;@libdir@;${prefix}/lib;' \
                -e 's;@includedir@;${prefix}/include;' \
                -e "s;@VERSION@;$vsversion;" \
                -e '/Libs.private/ d' \
                > vapoursynth.pc
            [[ -f vapoursynth.pc ]] && do_install vapoursynth.pc
            /usr/bin/curl -sL "$baseurl/pc/vapoursynth-script.pc.in" |
            sed -e "s;@prefix@;$LOCALDESTDIR;" \
                -e 's;@exec_prefix@;${prefix};' \
                -e 's;@libdir@;${prefix}/lib;' \
                -e 's;@includedir@;${prefix}/include;' \
                -e "s;@VERSION@;$vsversion;" \
                -e '/Requires.private/ d' \
                -e 's;lvapoursynth-script;lvsscript;' \
                -e '/Libs.private/ d' \
                > vapoursynth-script.pc
            [[ -f vapoursynth-script.pc ]] && do_install vapoursynth-script.pc

            do_checkIfExist
        elif [[ -z "$vsprefix" ]]; then
            mpv_disable vapoursynth
        fi
        unset vsprefix vsversion _file baseurl
    elif ! mpv_disabled vapoursynth; then
        mpv_disable vapoursynth
    fi

    _check=(bin-video/mpv.{exe,com})
    _deps=({libass,libavcodec,vapoursynth}.pc)
    do_vcs "https://github.com/mpv-player/mpv.git"
    if [[ $compile = "true" ]]; then
        # mpv uses libs from pkg-config but randomly uses MinGW's librtmp.a which gets compiled
        # with GnuTLS. If we didn't compile ours with GnuTLS the build fails on linking.
        hide_files "$MINGW_PREFIX"/lib/lib{rtmp,harfbuzz}.a

        [[ ! -f waf ]] && /usr/bin/python bootstrap.py >/dev/null 2>&1
        if [[ -d build ]]; then
            /usr/bin/python waf distclean >/dev/null 2>&1
            do_uninstall bin-video/mpv.exe.debug "${_check[@]}"
        fi

        # for purely cosmetic reasons, show the last release version when doing -V
        git describe --tags "$(git rev-list --tags --max-count=1)" | cut -c 2- > VERSION
        mpv_ldflags=()
        [[ $bits = "64bit" ]] && mpv_ldflags+=("-Wl,--image-base,0x140000000,--high-entropy-va")
        enabled libssh && mpv_ldflags+=("-Wl,--allow-multiple-definition")
        ! mpv_disabled egl-angle && do_patch "mpv-0001-waf-Use-pkgconfig-with-ANGLE.patch" am
        [[ $license = *v3 || $license = nonfree ]] && MPV_OPTS+=("--enable-gpl3")

        LDFLAGS+=" ${mpv_ldflags[*]}" log configure /usr/bin/python waf configure \
            "--prefix=$LOCALDESTDIR" "--bindir=$LOCALDESTDIR/bin-video" --enable-static-build \
            --disable-libguess --disable-vapoursynth-lazy "${MPV_OPTS[@]}"

        # Windows(?) has a lower argument limit than *nix so
        # we replace tons of repeated -L flags with just two
        replace="LIBPATH_lib\1 = ['${LOCALDESTDIR}/lib','${MINGW_PREFIX}/lib']"
        sed -r -i "s:LIBPATH_lib(ass|av(|device|filter)) = .*:$replace:g" ./build/c4che/_cache.py

        log "install" /usr/bin/python waf install -j "${cpuCount:-1}"

        unset mpv_ldflags replace withvs
        unhide_files "$MINGW_PREFIX"/lib/lib{rtmp,harfbuzz}.a
        ! mpv_disabled debug-build &&
            create_debug_link "$LOCALDESTDIR"/bin-video/mpv.exe
        do_checkIfExist
    fi
fi

if [[ $bmx = "y" ]]; then
    _ver="0.8.2"
    _hash="c5cf6b3941d887deb7defc2a86c40f1d"
    if do_pkgConfig "liburiparser = $_ver"; then
        _check=(liburiparser.{{,l}a,pc})
        do_wget_sf "uriparser/Sources/${_ver}/uriparser-${_ver}.tar.bz2"
        do_uninstall include/uriparser "${_check[@]}"
        [[ -f Makefile ]] && log distclean make distclean
        sed -i '/bin_PROGRAMS/ d' Makefile.am
        do_separate_confmakeinstall --disable-test --disable-doc
        do_checkIfExist
    fi

    _check=(bin-video/MXFDump.exe libMXF-1.0.{{,l}a,pc})
    do_vcs http://git.code.sf.net/p/bmxlib/libmxf libMXF-1.0
    if [[ $compile = "true" ]]; then
        sed -i 's| mxf_win32_mmap.c||' mxf/Makefile.am
        do_autogen
        do_uninstall include/libMXF-1.0 "${_check[@]}"
        [[ -f Makefile ]] && log distclean make distclean
        do_separate_confmakeinstall video --disable-examples
        do_checkIfExist
    fi

    _check=(libMXF++-1.0.{{,l}a,pc})
    _deps=(libMXF-1.0.pc)
    do_vcs http://git.code.sf.net/p/bmxlib/libmxfpp libMXF++-1.0
    if [[ $compile = "true" ]]; then
        do_autogen
        do_uninstall include/libMXF++-1.0 "${_check[@]}"
        [[ -f Makefile ]] && log distclean make distclean
        do_separate_confmakeinstall video --disable-examples
        do_checkIfExist
    fi

    _check=(bin-video/{bmxtranswrap,{h264,mov}dump,mxf2raw,raw2bmx}.exe)
    _deps=({liburiparser,libMXF{,++}-1.0}.pc)
    do_vcs http://git.code.sf.net/p/bmxlib/bmx
    if [[ $compile = "true" ]]; then
        do_patch bmx-0002-avoid-mmap-in-MinGW.patch am
        do_autogen
        do_uninstall libbmx-0.1.{{,l}a,pc} bin-video/bmxparse.exe \
            include/bmx-0.1 "${_check[@]}"
        [[ -f Makefile ]] && log distclean make distclean
        do_separate_confmakeinstall video
        do_checkIfExist
    fi
fi

echo -e "\n\t${orange_color}Finished $bits compilation of all tools${reset_color}"
}

run_builds() {
    new_updates="no"
    new_updates_packages=""
    if [[ $build32 = "yes" ]]; then
        source /local32/etc/profile.local
        buildProcess
    fi

    if [[ $build64 = "yes" ]]; then
        source /local64/etc/profile.local
        buildProcess
    fi
}

cd_safe "$LOCALBUILDDIR"
run_builds

while [[ $new_updates = "yes" ]]; do
    ret="no"
    echo "-------------------------------------------------------------------------------"
    echo "There were new updates while compiling."
    echo "Updated:$new_updates_packages"
    echo "Would you like to run compilation again to get those updates? Default: no"
    do_prompt "y/[n] "
    echo "-------------------------------------------------------------------------------"
    if [[ $ret = "y" || $ret = "Y" || $ret = "yes" ]]; then
        run_builds
    else
        break
    fi
done

clean_suite

echo -e "\n\t${green_color}Compilation successful.${reset_color}"
echo -e "\t${green_color}This window will close automatically in 5 seconds.${reset_color}"
sleep 5
