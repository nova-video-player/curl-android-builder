#!/bin/bash -x

if [[ "$OSTYPE" == "darwin"* ]]; then
    export CORES=$((`sysctl -n hw.logicalcpu`+1))
else
    export CORES=$((`nproc`+1))
fi

while getopts "a:" opt; do
  case $opt in
    a)
  ARCH=$OPTARG ;;
    :)
      echo "Option -$OPTARG requires an argument." >&2
      exit 1
      ;;
  esac
done

if [[ -z "${ARCH}" ]] ; then
  echo 'You need to input arch with -a ARCH.'
  echo 'Supported archs are:'
  echo -e '\tarm arm64 mips mips64 x86 x86_64'
  exit 1
fi

case `uname` in
  Linux)
    READLINK=readlink
    SED=sed
  ;;
  Darwin)
    # assumes brew install coreutils in order to support readlink -f on macOS
    READLINK=greadlink
    SED=gsed
  ;;
esac

LOCAL_PATH=$($READLINK -f .)

# android sdk directory is changing
[ -n "${ANDROID_HOME}" ] && androidSdk=${ANDROID_HOME}
[ -n "${ANDROID_SDK_ROOT}" ] && androidSdk=${ANDROID_SDK_ROOT}
# multiple sdkmanager paths
export PATH=${androidSdk}/cmdline-tools/tools/bin:${androidSdk}/tools/bin:$PATH
if [ ! -d "${androidSdk}/ndk-bundle" -a ! -d "${androidSdk}/ndk" ]
then
  ndk=$(pkg="ndk;$NDKVER"; sdkmanager --list | grep ${pkg} | sed "s/^.*\($pkg\.[0-9\.]*\) .*$/\1/g" | tail -n 1)
  yes | sdkmanager "${ndk}" > /dev/null
  echo NDK $ndk installed
fi
[ -d "${androidSdk}/ndk-bundle" ] && NDK_PATH=${androidSdk}/ndk-bundle
[ -d "${androidSdk}/ndk" ] && NDK_PATH=$(ls -d ${androidSdk}/ndk/* | sort -V | tail -n 1)
echo NDK_PATH is ${NDK_PATH}

export ANDROID_NDK_HOME=${NDK_PATH}
export ANDROID_NDK_ROOT=${NDK_PATH}

OPENSSL_DIR=$($READLINK -f ../openssl-android-builder)

if [ ! -d curl.git ]; then
  git clone https://github.com/curl/curl curl.git --bare --depth=1 -b curl-7_81_0
fi

CURL_BARE_PATH=$($READLINK -f curl.git)
ANDROID_API=21

ARCH_CONFIG_OPT=

case "${ARCH}" in
  'arm')
    ARCH_TRIPLET='arm-linux-androideabi'
    CLANG_TRIPLET='armv7a-linux-androideabi'
    ABI='armeabi-v7a'
    ARCH_CFLAGS='-march=armv7-a -mfpu=neon -mfloat-abi=softfp -mthumb'
    ARCH_LDFLAGS='-march=armv7-a -Wl,--fix-cortex-a8' ;;
  'arm64')
    ARCH_TRIPLET='aarch64-linux-android'
    CLANG_TRIPLET=${ARCH_TRIPLET}
    ABI='arm64-v8a' ;;
  'x86')
    ARCH_TRIPLET='i686-linux-android'
    CLANG_TRIPLET=${ARCH_TRIPLET}
    ARCH_CONFIG_OPT='--disable-asm'
    ARCH_CONFIG_OPT='--disable-asm'
    ARCH_CFLAGS='-march=i686 -mtune=i686 -mssse3 -mfpmath=sse -m32'
    ABI='x86' ;;
  'x86_64')
    ARCH_TRIPLET='x86_64-linux-android'
    CLANG_TRIPLET=${ARCH_TRIPLET}
    ARCH_CFLAGS='-march=x86-64 -msse4.2 -mpopcnt -m64 -mtune=x86-64'
    ABI='x86_64' ;;
  *)
    echo "Arch ${ARCH} is not supported."
    exit 1 ;;
esac

#CURL_DIR="$(mktemp -d)"
CURL_DIR="$PWD/curl-$ABI"
mkdir -p ${CURL_DIR}
git clone "${CURL_BARE_PATH}" "${CURL_DIR}"

pushd "${CURL_DIR}"

git clean -fdx

OS=$(uname -s | tr '[:upper:]' '[:lower:]')
CROSS_DIR=$NDK_PATH/toolchains/llvm/prebuilt/${OS}-x86_64
CROSS_PREFIX="${CROSS_DIR}/bin/${ARCH_TRIPLET}"

export PATH=${CROSS_DIR}/bin:$PATH

export AR=${CROSS_DIR}/bin/llvm-ar
export CC=${CROSS_DIR}/bin/${CLANG_TRIPLET}${ANDROID_API}-clang
export AS=$CC
export CXX=${CROSS_DIR}/bin/${CLANG_TRIPLET}${ANDROID_API}-clang++
export LD=${CROSS_DIR}/bin/ld
export RANLIB=${CROSS_DIR}/bin/llvm-ranlib
export OBJDUMP=${CROSS_DIR}/bin/llvm-objdump
export STRIP=${CROSS_DIR}/bin/llvm-strip
export NM=${CROSS_DIR}/bin/llvm-nm
export AR=${CROSS_DIR}/bin/llvm-ar

export CFLAGS="-Os"
export LDFLAGS="-Wl,-Bsymbolic"

mkdir -p "${CURL_DIR}/dist-${ABI}"

#export PKG_CONFIG_LIBDIR=${LOCAL_PATH}

ARGUMENTS=" \
    --with-pic \
    --disable-shared
    "

autoreconf -fi

./configure --host=${CLANG_TRIPLET} \
            --target=${CLANG_TRIPLET} \
	    --prefix=${LOCAL_PATH}/dist-${ABI} \
            --with-openssl=${OPENSSL_DIR}/dist-${ABI} ${ARGUMENTS}

make -j${CORES}
make install
make clean

popd

rm -Rf "${CURL_DIR}"
