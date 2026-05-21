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
  libXext
  libX11
  libXrender
  libXtst
  libXi
  libXft
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
  xorg.libXxf86vm
  xorg.libXcursor
  xorg.libXrandr
  xorg.libXfixes
  xorg.libXcomposite
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
