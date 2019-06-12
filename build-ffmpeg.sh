#!/bin/sh

# directories
SOURCE="ffmpeg-4.1"
FAT="FFmpeg-iOS-4"

SCRATCH="scratch"
# must be an absolute path
THIN=`pwd`/"thin"

# absolute path to x264 library
#X264=`pwd`/fat-x264

#FDK_AAC=`pwd`/fdk-aac/fdk-aac-ios

CONFIGURE_FLAGS="--disable-doc \
--enable-libspeex \
--enable-cross-compile \
--extra-cflags=-fembed-bitcode \
--extra-cxxflags=-fembed-bitcode \
--disable-debug \
--disable-ffmpeg \
--disable-ffplay \
--disable-ffprobe \
--disable-avdevice \
--disable-avfilter \
--disable-encoders \
--disable-programs \
--disable-parsers \
--disable-decoders \
--disable-protocols \
--disable-filters \
--disable-muxers \
--disable-demuxers \
--disable-bsfs \
--disable-indevs \
--disable-outdevs \
--disable-swscale-alpha \
--disable-doc \
--disable-asm \
--disable-yasm \
--disable-symver \
--enable-decoder=aac \
--enable-decoder=h264 \
--enable-decoder=libspeex \
--enable-parser=h264 \
--enable-parser=aac \
--enable-videotoolbox"

if [ "$X264" ]
then
  CONFIGURE_FLAGS="$CONFIGURE_FLAGS --enable-gpl --enable-libx264"
fi

if [ "$FDK_AAC" ]
then
  CONFIGURE_FLAGS="$CONFIGURE_FLAGS --enable-libfdk-aac"
fi

# avresample
#CONFIGURE_FLAGS="$CONFIGURE_FLAGS --enable-avresample"

#ARCHS="arm64 armv7s armv7 x86_64"
ARCHS="arm64 armv7s armv7"

COMPILE="y"
LIPO="y"

DEPLOYMENT_TARGET="8.0"

if [ "$*" ]
then
  if [ "$*" = "lipo" ]
  then
    # skip compile
    COMPILE=
  else
    ARCHS="$*"
    if [ $# -eq 1 ]
    then
      # skip lipo
      LIPO=
    fi
  fi
fi

if [ "$COMPILE" ]
then
  if [ ! `which yasm` ]
  then
    echo 'Yasm not found'
    if [ ! `which brew` ]
    then
      echo 'Homebrew not found. Trying to install...'
      ruby -e "$(curl -fsSL https://raw.github.com/Homebrew/homebrew/go/install)" \
        || exit 1
    fi
    echo 'Trying to install Yasm...'
    brew install yasm || exit 1
  fi
  if [ ! `which gas-preprocessor.pl` ]
  then
    echo 'gas-preprocessor.pl not found. Trying to install...'
    (curl -L https://github.com/libav/gas-preprocessor/raw/master/gas-preprocessor.pl \
      -o /usr/local/bin/gas-preprocessor.pl \
      && chmod +x /usr/local/bin/gas-preprocessor.pl) \
      || exit 1
  fi

  if [ ! -r $SOURCE ]
  then
    echo 'FFmpeg source not found. Trying to download...'
    curl http://www.ffmpeg.org/releases/$SOURCE.tar.bz2 | tar xj \
      || exit 1
    # removed '' for macOS building.
    LC_ALL=C find $SOURCE -type f -name '*.c' -exec sed -i s/AVMediaType/AVMediaTypeFFMPEG/g {} +
    LC_ALL=C find $SOURCE -type f -name '*.h' -exec sed -i s/AVMediaType/AVMediaTypeFFMPEG/g {} +
  fi

  SPEEX=`pwd`/speex/build/speex
  CWD=`pwd`

  # let pkgconfig use our recently built speex as the dependency.
  export PKG_CONFIG_PATH="${SPEEX}/arm64/lib/pkgconfig"

  for ARCH in $ARCHS
  do

    SPEEXA=$SPEEX/$ARCH
    echo "building $ARCH..."
    echo "speex is at $SPEEXA"
    mkdir -p "$SCRATCH/$ARCH"
    cd "$SCRATCH/$ARCH"

    CFLAGS="-arch $ARCH"

    if [ "$ARCH" = "i386" -o "$ARCH" = "x86_64" ]
    then
        PLATFORM="iPhoneSimulator"
        CFLAGS="$CFLAGS -mios-simulator-version-min=$DEPLOYMENT_TARGET"
    else
        PLATFORM="iPhoneOS"
        CFLAGS="$CFLAGS -mios-version-min=$DEPLOYMENT_TARGET"
        if [ "$ARCH" = "arm64" ]
        then
            EXPORT="GASPP_FIX_XCODE5=1"
        fi
    fi

    XCRUN_SDK=`echo $PLATFORM | tr '[:upper:]' '[:lower:]'`
    CC="xcrun -sdk $XCRUN_SDK clang"
    CXXFLAGS="$CFLAGS"
    LDFLAGS="$CFLAGS"

    CFLAGS="$CFLAGS -I$SPEEXA/include"
    LDFLAGS="$LDFLAGS -L$SPEEXA/lib"

    if [ "$X264" ]
    then
      CFLAGS="$CFLAGS -I$X264/include"
      LDFLAGS="$LDFLAGS -L$X264/lib"
    fi
    if [ "$FDK_AAC" ]
    then
      CFLAGS="$CFLAGS -I$FDK_AAC/include"
      LDFLAGS="$LDFLAGS -L$FDK_AAC/lib"
    fi
  
    echo "${CWD}/${SOURCE}"

    TMPDIR=${TMPDIR/%\/} $CWD/$SOURCE/configure \
        --target-os=darwin \
        --arch=$ARCH \
        --cc="$CC" \
        $CONFIGURE_FLAGS \
        --extra-cflags="$CFLAGS" \
        --extra-cxxflags="$CXXFLAGS" \
        --extra-ldflags="$LDFLAGS" \
        --prefix="$THIN/$ARCH" \
    || exit 1

    echo "LETS MAKE"
    pwd

    make -j3 install $EXPORT || exit 1
    cd $CWD
  done
fi

if [ "$LIPO" ]
then
  echo "building fat binaries..."
  mkdir -p $FAT/lib
  set - $ARCHS
  CWD=`pwd`
  cd $THIN/$1/lib
  for LIB in *.a
  do
    cd $CWD
    echo lipo -create `find $THIN -name $LIB` -output $FAT/lib/$LIB 1>&2
    lipo -create `find $THIN -name $LIB` -output $FAT/lib/$LIB || exit 1
  done

  cd $CWD
  cp -rf $THIN/$1/include $FAT
fi

echo Done
