# This list is based upon:
# https://github.com/TUM-DSE/doctor-cluster-config/blob/master/pkgs/xilinx/fhs-env.nix
pkgs:

(with pkgs; [
  bash
  util-linux
  coreutils
  zlib
  lsb-release
  stdenv.cc.cc
  ncurses
  ncurses5
  libxext
  libx11
  libxrender
  libxtst
  libxi
  libxft
  libxcb
  # common requirements
  freetype
  fontconfig
  glib
  gtk2
  gtk3
  libxcrypt-legacy
  libdrm
  libgbm
  mesa
  libGL
  pixman
  libpng
  libxxf86vm
  libxcursor
  libxrandr
  libxfixes
  libxcomposite
  # For fetching project templates when creating projects
  gitMinimal
  # For the `arch` command
  toybox

  # to compile some xilinx examples
  opencl-clhpp
  ocl-icd
  opencl-headers

  # from installLibs.sh
  graphviz
  gcc
  unzip
  nettools

  nss
  nspr
  dbus.lib
  at-spi2-core
  cups.lib
  pango
  cairo
  libxdamage
  expat
  libxkbcommon
  alsa-lib
  nodejs_22
])
