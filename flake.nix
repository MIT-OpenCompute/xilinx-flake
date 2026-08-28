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
      # lmutil/lmgrd/xilinxd (the FlexLM binaries Xilinx ships under
      # bin/unwrapped/lnx64.o/) are linked against /lib64/ld-lsb-x86-64.so.3,
      # the LSB-compat dynamic loader that real distros' lsb-release packages
      # symlink to the regular one. buildFHSEnv never creates it, so those
      # binaries fail to exec at all inside the sandbox ("required file not
      # found"), which is what shows up as "lmutil not found" in xlicdiag/vlm.
      fhsExtraBuildCommands = ''
        ln -sf ld-linux-x86-64.so.2 "$out/usr/lib64/ld-lsb-x86-64.so.3"
      '';
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
          # XILINXD_LICENSE_FILE may come from ~/.config/xilinx/nix.sh (e.g.
          # "@license-server" or "/path/to/Xilinx.lic"), or already be set in
          # the calling shell - forward it into the tool's environment either way.
          if [[ -n "''${XILINXD_LICENSE_FILE:-}" ]]; then
            export XILINXD_LICENSE_FILE
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
        {
          product,
          # Executable name under $INSTALL_DIR/$VERSION/${product}/bin/, if it
          # differs from the lowercased product dir name (e.g. the License
          # Manager binary "vlm" lives under the "Vivado" product dir).
          binary ? null,
          # Desktop entry name, if it should differ from the product dir name.
          desktopName ? product,
          meta,
        }:
        let
          name = if binary != null then binary else pkgs.lib.strings.toLower product;
          fhsEnv = pkgs.buildFHSEnv {
            inherit name targetPkgs meta;
            extraBuildCommands = fhsExtraBuildCommands;
            runScript = pkgs.writeScript "xilinx-${product}-runner" (
              (runScriptPrefix { })
              + ''
                export LD_LIBRARY_PATH=/lib:$LD_LIBRARY_PATH
                export GDK_BACKEND=x11
                export DISPLAY="''${DISPLAY:-:0}"
                export _JAVA_AWT_WM_NONREPARENTING=1
                export ELECTRON_OZONE_PLATFORM_HINT=x11
                _xil_tmpdir=$(mktemp -d -t xilinx-node-XXXXXX)
                printf '#!/bin/sh\nexport LD_LIBRARY_PATH=/lib64:$LD_LIBRARY_PATH\nexec /usr/bin/node "$@"\n' \
                  > "$_xil_tmpdir/node"
                chmod +x "$_xil_tmpdir/node"
                # lmutil/lmgrd/xilinxd (FlexLM tools, e.g. the ones vlm shells
                # out to for license status) live in the raw ELF dir, not on
                # PATH by default.
                export PATH="$_xil_tmpdir:$INSTALL_DIR/$VERSION/${product}/bin:$INSTALL_DIR/$VERSION/${product}/bin/unwrapped/lnx64.o:$PATH"
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
            inherit desktopName name;
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
              vlm = [
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

      xilinxVendorShortcutMap = with self.packages.x86_64-linux; [
        {
          rel = "Vivado/bin/vivado";
          wrapped = "${vivado}/bin/vivado";
        }
        {
          rel = "Vivado/bin/vlm";
          wrapped = "${vlm}/bin/vlm";
        }
        {
          rel = "Vitis/bin/vitis";
          wrapped = "${vitis}/bin/vitis";
        }
        {
          rel = "Vitis_HLS/bin/vitis_hls";
          wrapped = "${vitis_hls}/bin/vitis_hls";
        }
        {
          rel = "Model_Composer/bin/model_composer";
          wrapped = "${model_composer}/bin/model_composer";
        }
      ];

      fixDesktopEntriesScript = pkgs.writeShellApplication {
        name = "fix-desktop-entries";
        runtimeInputs = with pkgs; [
          gnused
          gnugrep
          coreutils
        ];
        excludeShellChecks = [ "SC1090" ];
        text =
          (runScriptPrefix { errorOut = true; })
          + ''
            shopt -s nullglob
            fixed=0
            for f in "$HOME/.local/share/applications"/*.desktop "$HOME/Desktop"/*.desktop; do
          ''
          + pkgs.lib.concatMapStringsSep "\n" (e: ''
            if grep -q "$INSTALL_DIR/$VERSION/${e.rel}" "$f" 2>/dev/null; then
              sed -i "s#$INSTALL_DIR/$VERSION/${e.rel}#${e.wrapped}#g" "$f"
              fixed=$((fixed + 1))
            fi
          '') xilinxVendorShortcutMap
          + ''
            done
            if [[ $fixed -eq 0 ]]; then
              echo "nix-xilinx: no vendor-generated desktop entries needed fixing"
            else
              echo "nix-xilinx: fixed $fixed desktop entrie(s) to launch through the Nix FHS wrapper"
            fi
          '';
        meta = metaCommon // {
          description = "Repoints Xilinx-installer-generated .desktop shortcuts at the Nix-wrapped executables";
        };
      };
    in
    {
      packages.x86_64-linux.xilinx-shell = pkgs.buildFHSEnv {
        name = "xilinx-shell";
        inherit targetPkgs;
        extraBuildCommands = fhsExtraBuildCommands;
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
      packages.x86_64-linux.vlm = createXilinxPkg {
        product = "Vivado";
        binary = "vlm";
        desktopName = "Vivado License Manager";
        meta = metaCommon // {
          homepage = "https://docs.amd.com/r/en-US/ug973-vivado-release-notes-install-license/License-Manager";
          description = "Vivado/Vitis License Manager - view, load and manage Xilinx/AMD license files";
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
      packages.x86_64-linux.xsct = pkgs.buildFHSEnv {
        name = "xsct";
        inherit targetPkgs;
        extraBuildCommands = fhsExtraBuildCommands;
        runScript = pkgs.writeScript "xilinx-xsct-runner" (
          (runScriptPrefix { })
          + ''
            export LD_LIBRARY_PATH=/lib:$LD_LIBRARY_PATH
            export XILINX_VIVADO="$INSTALL_DIR/$VERSION/Vivado"
            exec "$INSTALL_DIR/$VERSION/Vivado/bin/xsdb" "$@"
          ''
        );
        meta = metaCommon // {
          description = "Xilinx Software Command-line Tool (xsct/xsdb)";
        };
      };
      packages.x86_64-linux.fix-desktop-entries = fixDesktopEntriesScript;
      overlay = final: prev: {
        inherit (self.packages.x86_64-linux)
          xilinx-shell
          vivado
          vlm
          vitis
          vitis_hls
          model_composer
          xsct
          fix-desktop-entries
          ;
      };
      nixosModules.vivado-server = import ./modules/vivado-server.nix;
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
