{
  description = "Nix files made to ease imperative installation of Xilinx tools";

  # https://nixos.wiki/wiki/Flakes#Using_flakes_project_from_a_legacy_Nix
  inputs.flake-compat = {
    url = "github:edolstra/flake-compat";
    flake = false;
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-compat,
    }:
    let
      # We don't use flake-utils.lib.eachDefaultSystem since only x86_64-linux is
      # supported
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      targetPkgs = import ./common.nix;
      runScriptPrefix =
        {
          errorOut ? true,
        }:
        ''
          # Search for an imperative declaration of the installation directory of xilinx
          if [[ -f ~/.config/xilinx/nix.sh ]]; then
            source ~/.config/xilinx/nix.sh
        ''
        + pkgs.lib.optionalString errorOut ''
          else
            echo "nix-xilinx: error: Did not find ~/.config/xilinx/nix.sh" >&2
            exit 1
          fi
          if [[ ! -d "$INSTALL_DIR" ]]; then
            echo "nix-xilinx: error: INSTALL_DIR $INSTALL_DIR isn't a directory" >&2
            exit 2
        ''
        + ''
          fi
        '';
      # Might be useful for usage of this flake in another flake with devShell +
      # direnv setup. See:
      # https://gitlab.com/doronbehar/nix-matlab/-/merge_requests/1#note_631741222
      shellHooksCommon = (runScriptPrefix { }) + ''
        # Rename the variables for others to extend it in their shellHook
        export XILINX_INSTALL_DIR="$INSTALL_DIR"
        unset INSTALL_DIR
        export XILINX_VERSION=$VERSION
        unset VERSION
      '';
      # Used in many packages
      metaCommon = with pkgs.lib; {
        # This license is not of Xilinx' tools, but for this repository
        license = licenses.mit;
        # Probably best to install this completely imperatively on a system other
        # then NixOS.
        platforms = platforms.linux;
      };

      createXilinxPkg =
        { product, meta }:
        let
          name = pkgs.lib.strings.toLower product;
          fhsEnv = pkgs.buildFHSEnv {
            inherit name targetPkgs meta;
            runScript = pkgs.writeScript "xilinx-${product}-runner" (
              (runScriptPrefix { })
              + ''
                export LD_LIBRARY_PATH=/lib:$LD_LIBRARY_PATH
                export GDK_BACKEND=x11
                export DISPLAY="''${DISPLAY:-:0}"
                export _JAVA_AWT_WM_NONREPARENTING=1
                if [[ -d $INSTALL_DIR/$VERSION/${product} ]]; then
                  exec $INSTALL_DIR/$VERSION/${product}/bin/${name} "$@"
                else
                  echo It seems ${product} isn\'t installed because '$INSTALL_DIR/$VERSION/${product}' doesn\'t exist. Follow >&2
                  echo the instructions in the README of nix-xilinx and make sure ${product} is selected during the >&2
                  echo installation wizard. If it\'s supposed to be installed, check that your \~/.config/xilinx/nix.sh >&2
                  echo have a correct '$VERSION' variable set in it - check that the '$VERSION' directory actually exists. >&2
                  exit 1
                fi
              ''
            );
          };
          desktopItem = pkgs.makeDesktopItem {
            desktopName = product;
            inherit name;
            exec = "${fhsEnv}/bin/${name}";
            icon = name;
            categories = [
              "Utility"
              "Development"
              "IDE"
            ];
          };
          iconPkgs =
            {
              vivado = [
                (pkgs.runCommand "${name}-icon" { } ''
                  install -Dm644 ${./icons/vivado.png} $out/share/icons/hicolor/256x256/apps/${name}.png
                '')
              ];
              vitis_hls = [
                (pkgs.runCommand "${name}-icon" { } ''
                  install -Dm644 ${./icons/vitis_hls.png} $out/share/icons/hicolor/256x256/apps/${name}.png
                '')
              ];
              vitis = [ ];
              model_composer = [
                (pkgs.runCommand "${name}-icon" { } ''
                  install -Dm644 ${./icons/matlab.png} $out/share/icons/hicolor/256x256/apps/${name}.png
                '')
              ];
            }
            .${name};
        in
        pkgs.symlinkJoin {
          inherit name meta;
          paths = [
            fhsEnv
            desktopItem
          ]
          ++ iconPkgs;
        };
    in
    {
      packages.x86_64-linux.xilinx-shell = pkgs.buildFHSEnv {
        name = "xilinx-shell";
        inherit targetPkgs;
        runScript = pkgs.writeScript "xilinx-shell-runner" (
          (runScriptPrefix {
            # If the user hasn't setup a ~/.config/xilinx/nix.sh file yet, don't
            # yell at them that it's missing
            errorOut = false;
          })
          + ''
            cat <<EOF
            ============================
            welcome to nix-xilinx shell!

            To install vivado or vitis:
            ${nixpkgs.lib.strings.escape [ "`" "'" "\"" "$" ] (builtins.readFile ./install.adoc)}

            4. Finish the installation, and exit the shell (with \`exit\`).
            5. Follow the rest of the instructions in the README to make xilinx
               executable available anywhere on your system.
            ============================
            EOF
            LD_LIBRARY_PATH=/lib:$LD_LIBRARY_PATH exec bash
          ''
        );
        meta = metaCommon // {
          homepage = "https://gitlab.com/doronbehar/nix-xilinx";
          description = "A bash shell from which you can install xilinx tools or launch them from CLI";
        };
      };
      packages.x86_64-linux.vivado = createXilinxPkg {
        product = "Vivado";
        meta = metaCommon // {
          homepage = "https://www.xilinx.com/products/design-tools/vivado.html";
          description = "Software suite for synthesis and analysis of (HDL) designs";
        };
      };
      packages.x86_64-linux.vitis = createXilinxPkg {
        product = "Vitis";
        meta = metaCommon // {
          homepage = "https://www.xilinx.com/products/design-tools/vitis.html";
          description = "A comprehensive development environment";
        };
      };
      packages.x86_64-linux.vitis_hls = createXilinxPkg {
        product = "Vitis_HLS";
        meta = metaCommon // {
          homepage = "https://xilinx.github.io/Vitis-Tutorials/2020-2/docs/Getting_Started/Vitis_HLS/README.html";
          description = "High-Level Synthesis from C, C++ and OpenCL";
        };
      };
      packages.x86_64-linux.model_composer = createXilinxPkg {
        product = "Model_Composer";
        meta = metaCommon // {
          homepage = "https://www.xilinx.com/products/design-tools/vitis/vitis-model-composer.html";
          description = "A Xilinx toolbox for MATLAB and Simulink for DSP Design";
        };
      };
      overlay = final: prev: {
        inherit (self.packages.x86_64-linux)
          xilinx-shell
          vivado
          vitis
          vitis_hls
          model_composer
          ;
      };
      inherit shellHooksCommon;
      devShell.x86_64-linux = pkgs.mkShell {
        buildInputs = (targetPkgs pkgs) ++ [
          self.packages.x86_64-linux.xilinx-shell
        ];
        # From some reason using the attribute xilinx-shell directly as the
        # devShell doesn't make it run like that by default.
        shellHook = ''
          exec xilinx-shell
        '';
      };

      defaultPackage.x86_64-linux = self.packages.x86_64-linux.xilinx-shell;

    };
}
