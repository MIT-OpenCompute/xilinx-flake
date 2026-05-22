{ config, lib, pkgs, ... }:

let
  inherit (lib)
    flatten
    literalExpression
    mkDefault
    mkEnableOption
    mkIf
    mkMerge
    mkOption
    optional
    optionalAttrs
    optionalString
    types;

  cfg = config.services.vivadoServer;

  targetPkgs = import ../common.nix;

  vivadoBin = "${cfg.installDir}/${cfg.version}/Vivado/bin";

  # Build a minimal FHS env that exec's a specific Vivado daemon.
  # The runScript receives "$@" so ExecStart args are forwarded.
  mkDaemonFhs = name: script:
    pkgs.buildFHSEnv {
      inherit name targetPkgs;
      runScript = pkgs.writeScript "${name}-runner" script;
    };

  hwServerFhs = mkDaemonFhs "xilinx-hw-server" ''
    #!/bin/sh
    exec ${vivadoBin}/hw_server "$@"
  '';

  # lmgrd is a raw ELF; the wrapper scripts are not suitable for daemon use.
  lmgrdFhs = mkDaemonFhs "xilinx-lmgrd" ''
    #!/bin/sh
    exec ${vivadoBin}/unwrapped/lnx64.o/lmgrd "$@"
  '';

  csServerFhs = mkDaemonFhs "xilinx-cs-server" ''
    #!/bin/sh
    exec ${vivadoBin}/cs_server "$@"
  '';

  # Environment variables required by all Vivado server processes.
  commonEnv = [
    "XILINX_VIVADO=${cfg.installDir}/${cfg.version}/Vivado"
    "LD_LIBRARY_PATH=/lib"
    "LC_ALL=en_US.UTF-8"
    "LANG=en_US.UTF-8"
  ];

  # FHS wrapper for Vivado batch/headless use.  Uses installDir/version
  # directly — no ~/.config/xilinx/nix.sh needed on the server.
  # Named "vivado-remote-fhs" to avoid colliding with the overlay "vivado"
  # package if both happen to be in environment.systemPackages.
  vivadoRemoteFhs = pkgs.buildFHSEnv {
    name = "vivado-remote-fhs";
    inherit targetPkgs;
    runScript = pkgs.writeScript "vivado-batch-runner" (
      ''
        #!/bin/sh
        export XILINX_VIVADO=${cfg.installDir}/${cfg.version}/Vivado
        export LD_LIBRARY_PATH=/lib:$LD_LIBRARY_PATH
        export _JAVA_AWT_WM_NONREPARENTING=1
      ''
      + optionalString (cfg.remoteRuns.licenseFile != null) ''
        export XILINXD_LICENSE_FILE=${cfg.remoteRuns.licenseFile}
      ''
      + ''
        exec ${vivadoBin}/vivado "$@"
      ''
    );
  };

  # Thin wrapper package that exposes the binary under the name "vivado"
  # so it can be injected into PATH without touching environment.systemPackages.
  vivadoRemote = pkgs.runCommand "vivado-remote" { } ''
    mkdir -p $out/bin
    ln -s ${vivadoRemoteFhs}/bin/vivado-remote-fhs $out/bin/vivado
  '';

in
{
  options.services.vivadoServer = {
    enable = mkEnableOption "Xilinx Vivado headless remote services";

    installDir = mkOption {
      type = types.str;
      example = "/opt/Xilinx";
      description = ''
        Absolute path to the Xilinx imperative installation root.
        This corresponds to the <literal>Destination</literal> field in the
        Xilinx install config (INSTALL_DIR in the interactive-use nix.sh).
      '';
    };

    version = mkOption {
      type = types.str;
      default = "2025.2";
      example = "2024.1";
      description = "Vivado release version string (sub-directory of installDir).";
    };

    user = mkOption {
      type = types.str;
      default = "vivado";
      description = "System user account under which Vivado daemons run.";
    };

    group = mkOption {
      type = types.str;
      default = "vivado";
      description = "Primary group for the Vivado daemon user.";
    };

    hwServer = {
      enable = mkEnableOption ''
        hw_server — Xilinx JTAG hardware target daemon.
        Remote Vivado Hardware Manager sessions connect here to program and
        debug FPGAs without a local GUI
      '';

      port = mkOption {
        type = types.port;
        default = 3121;
        description = "TCP port hw_server listens on (Xilinx default: 3121).";
      };

      openFirewall = mkEnableOption "open the firewall for the hw_server port";
    };

    licenseServer = {
      enable = mkEnableOption ''
        lmgrd — Xilinx FlexLM floating license server.
        Enables licence sharing across multiple workstations on the LAN.
        Clients set <literal>XILINXD_LICENSE_FILE=@&lt;server-hostname&gt;</literal>
      '';

      port = mkOption {
        type = types.port;
        default = 27000;
        description = "TCP port lmgrd listens on (FlexLM default: 27000).";
      };

      vendorPort = mkOption {
        type = types.port;
        default = 27001;
        description = ''
          TCP port for the Xilinx vendor daemon (xilinxd).
          This port must match the <literal>port=</literal> value on the
          <literal>VENDOR xilinxd</literal> line of the license file so that
          firewall rules can be opened for it.
        '';
      };

      licenseFile = mkOption {
        type = types.path;
        example = literalExpression ''"/etc/xilinx/Xilinx.lic"'';
        description = ''
          Path to the Xilinx <literal>.lic</literal> license file.
          Ensure the VENDOR line specifies a fixed vendor port matching
          <option>services.vivadoServer.licenseServer.vendorPort</option>:
          <literal>VENDOR xilinxd port=27001</literal>
        '';
      };

      openFirewall = mkEnableOption "open the firewall for lmgrd and the vendor daemon ports";
    };

    csServer = {
      enable = mkEnableOption ''
        cs_server — Xilinx ChipScope / ILA analysis daemon.
        Hardware Manager ILA sessions connect here for in-system logic analysis
      '';

      port = mkOption {
        type = types.port;
        default = 3042;
        description = "TCP port cs_server listens on.";
      };

      openFirewall = mkEnableOption "open the firewall for the cs_server port";
    };

    remoteRuns = {
      enable = mkEnableOption ''
        SSH remote-run host for Vivado's "Launch runs on remote hosts" feature.
        Vivado on a client workstation will SSH into this server as
        <option>services.vivadoServer.user</option> and invoke
        <literal>vivado -mode batch</literal> to run synthesis and implementation
        jobs without a GUI on the client
      '';

      authorizedKeys = mkOption {
        type = types.listOf types.str;
        default = [ ];
        example = [ "ssh-ed25519 AAAA... engineer@workstation" ];
        description = ''
          SSH public keys that are permitted to connect as the Vivado daemon
          user and submit remote runs.  Add one entry per client workstation.
        '';
      };

      workDir = mkOption {
        type = types.str;
        default = "/var/lib/vivado-remote";
        description = ''
          Directory on the server where Vivado places run artifacts (checkpoints,
          logs, reports).  Configure this path as the "Remote working directory"
          in Vivado's "Configure Hosts" dialog.
        '';
      };

      licenseFile = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "@localhost";
        description = ''
          Value for <literal>XILINXD_LICENSE_FILE</literal> injected into every
          batch Vivado process spawned by a remote run.  Set to
          <literal>@localhost</literal> when
          <option>services.vivadoServer.licenseServer.enable</option> is true on
          this machine, or to <literal>@licence-server-hostname</literal> for an
          external server.  Defaults to null (inherits the SSH session environment).
        '';
      };

      openFirewall = mkEnableOption "open the firewall for SSH (port 22)";
    };
  };

  config = mkIf cfg.enable (mkMerge [
    # -------------------------------------------------------------------------
    # Shared: user + group
    # Always create a home directory so SSH authorized_keys and Vivado's
    # per-user cache (~/.Xilinx/) have a writable location.
    # -------------------------------------------------------------------------
    {
      users.users.${cfg.user} = {
        isSystemUser = true;
        group = cfg.group;
        description = "Xilinx Vivado daemon user";
        home = "/var/lib/vivado";
        createHome = true;
      };
      users.groups.${cfg.group} = { };
    }

    # -------------------------------------------------------------------------
    # hw_server
    # -------------------------------------------------------------------------
    (mkIf cfg.hwServer.enable {
      systemd.services.xilinx-hw-server = {
        description = "Xilinx hw_server JTAG Hardware Target Daemon";
        documentation = [
          "https://docs.amd.com/r/en-US/ug908-vivado-programming-debugging/Starting-and-Stopping-hw_server"
        ];
        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" ];

        serviceConfig = {
          Type = "simple";
          User = cfg.user;
          Group = cfg.group;
          # TCP::PORT is hw_server's canonical listen-all-interfaces form.
          ExecStart = "${hwServerFhs}/bin/xilinx-hw-server -s TCP::${toString cfg.hwServer.port}";
          Environment = commonEnv ++ [
            # Digilent / FTDI USB cable drivers are not available on a headless
            # server; disable them to suppress startup warnings.
            "HW_SERVER_FTDIMGR_DISABLE=1"
            "HW_SERVER_DJTG_DISABLE=1"
          ];
          Restart = "on-failure";
          RestartSec = "5s";
          NoNewPrivileges = true;
          PrivateTmp = true;
        };
      };

      networking.firewall.allowedTCPPorts =
        optional cfg.hwServer.openFirewall cfg.hwServer.port;
    })

    # -------------------------------------------------------------------------
    # lmgrd (FlexLM license server)
    # -------------------------------------------------------------------------
    (mkIf cfg.licenseServer.enable {
      systemd.services.xilinx-lmgrd = {
        description = "Xilinx FlexLM Floating License Server (lmgrd)";
        documentation = [
          "https://docs.amd.com/r/en-US/ug973-vivado-release-notes-install-license/License-Manager"
        ];
        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" ];

        serviceConfig = {
          # lmgrd forks by default; systemd cgroup tracking handles reaping.
          Type = "forking";
          User = cfg.user;
          Group = cfg.group;
          ExecStart = lib.concatStringsSep " " [
            "${lmgrdFhs}/bin/xilinx-lmgrd"
            "-c ${cfg.licenseServer.licenseFile}"
            "-port ${toString cfg.licenseServer.port}"
            "-l /var/log/xilinx-lmgrd/lmgrd.log"
          ];
          # Logs & state directories are created automatically by systemd.
          LogsDirectory = "xilinx-lmgrd";
          StateDirectory = "xilinx-lmgrd";
          Environment = commonEnv;
          Restart = "on-failure";
          RestartSec = "5s";
          NoNewPrivileges = true;
          PrivateTmp = true;
        };
      };

      networking.firewall.allowedTCPPorts =
        optional cfg.licenseServer.openFirewall cfg.licenseServer.port
        ++ optional cfg.licenseServer.openFirewall cfg.licenseServer.vendorPort;
    })

    # -------------------------------------------------------------------------
    # cs_server (ChipScope / ILA)
    # -------------------------------------------------------------------------
    (mkIf cfg.csServer.enable {
      systemd.services.xilinx-cs-server = {
        description = "Xilinx cs_server ChipScope / ILA Analysis Daemon";
        documentation = [
          "https://docs.amd.com/r/en-US/ug908-vivado-programming-debugging"
        ];
        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" ];

        serviceConfig = {
          Type = "simple";
          User = cfg.user;
          Group = cfg.group;
          ExecStart = "${csServerFhs}/bin/xilinx-cs-server -p ${toString cfg.csServer.port}";
          Environment = commonEnv ++ [
            # cs_server is a PyInstaller-frozen Python app; it will refuse to
            # start unless the locale is explicitly UTF-8.
            "PYTHONIOENCODING=utf-8"
          ];
          Restart = "on-failure";
          RestartSec = "5s";
          NoNewPrivileges = true;
          PrivateTmp = true;
        };
      };

      networking.firewall.allowedTCPPorts =
        optional cfg.csServer.openFirewall cfg.csServer.port;
    })

    # -------------------------------------------------------------------------
    # remoteRuns — SSH-based remote synthesis / implementation host
    # -------------------------------------------------------------------------
    (mkIf cfg.remoteRuns.enable {
      # Give the daemon user a login shell and SSH authorized keys so Vivado
      # can connect and invoke "vivado -mode batch" non-interactively.
      users.users.${cfg.user} = {
        shell = pkgs.bash;
        openssh.authorizedKeys.keys = cfg.remoteRuns.authorizedKeys;
      };

      # The sshd must be running for Vivado to reach this host.
      services.openssh.enable = mkDefault true;

      # Inject the vivado batch wrapper into PATH for login shells.
      # Vivado invokes remote commands as "bash --login -c '...'" so
      # /etc/profile.d/ is sourced before the vivado command runs.
      environment.etc."profile.d/xilinx-remote-runs.sh".text = ''
        export PATH="${vivadoRemote}/bin:$PATH"
      '';

      # Create the remote run working directory with correct ownership.
      systemd.tmpfiles.rules = [
        "d ${cfg.remoteRuns.workDir} 0750 ${cfg.user} ${cfg.group} -"
      ];

      networking.firewall.allowedTCPPorts =
        optional cfg.remoteRuns.openFirewall 22;
    })
  ]);
}
