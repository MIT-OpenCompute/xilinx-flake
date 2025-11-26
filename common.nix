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
  xorg.libXext
  xorg.libX11
  xorg.libXrender
  xorg.libXtst
  xorg.libXi
  xorg.libXft
  xorg.libxcb
  pixman
  libpng
  # common requirements
  freetype
  fontconfig
  glib
  gtk2
  gtk3
  libxcrypt-legacy
  libdrm
  libgbm
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
])
