{
  pkgs,
  installerModules,
  imageModules,
  nixos,
  keylimeModule,
  keylimeAgentModule,
  keylimeAgentPackage,
}:
let
  inherit (pkgs) lib;

  # Disable the keylime agent in tests that don't provide a registrar.
  # Without a registrar the agent crash-loops, which can delay boot.
  noKeylimeAgent = {
    nodes.machine =
      { ... }:
      {
        services.keylime-agent.enable = lib.mkForce false;
      };
  };

  # NixOS VM tests include a custom backdoor for test instrumentation.
  # The installer does as well, while running inside a test VM, but
  # the installed system it boots into does not by default. So we
  # swap out the image to install with one that's extended to include
  # the test instrumentation backdoor.
  nixosWithBackdoor = nixos.extendModules {
    modules = [
      (
        { modulesPath, ... }:
        {
          imports = [
            "${modulesPath}/testing/test-instrumentation.nix"
          ];
          config = {
            testing = {
              backdoor = true;
              initrdBackdoor = true;
            };
            nixosAndroidBuilder.unattended.enable = lib.mkForce false;
          };
        }
      )
    ];
  };
  payload = "${nixosWithBackdoor.config.system.build.finalImage}/${nixosWithBackdoor.config.image.filePath}";
in
{
  integration = pkgs.testers.runNixOSTest {
    imports = [
      ./integration.nix
      noKeylimeAgent
      {
        _module.args = {
          imageModules = imageModules;
        };
      }
    ];
  };
  installer = pkgs.testers.runNixOSTest {
    imports = [
      ./installer.nix
      {
        _module.args = {
          inherit payload;
          inherit installerModules;
          vmInstallerTarget = "/dev/vdb";
          vmStorageTarget = "/dev/vdc";
        };
      }
    ];
  };
  installerInteractive = pkgs.testers.runNixOSTest {
    imports = [
      ./installer-interactive.nix
      {
        _module.args = {
          inherit payload;
          inherit installerModules;
          vmInstallerTarget = "select";
          vmStorageTarget = "select";
        };
      }
    ];
  };

  keylime = pkgs.testers.runNixOSTest {
    imports = [
      ./keylime.nix
      {
        _module.args = {
          imageModules = imageModules;
          inherit
            keylimeModule
            keylimeAgentModule
            keylimeAgentPackage
            ;
        };
      }
    ];
  };

  credentialStorage = pkgs.testers.runNixOSTest {
    imports = [
      ./credential-storage.nix
    ];
  };

}
