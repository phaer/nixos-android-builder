{
  pkgs,
  installerModules,
  imageModules,
  nixos,
  keylimeModule,
  keylimeAgentModule,
  keylimePackage,
  keylimeAgentPackage,
}:
let
  inherit (pkgs) lib;
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
      {
        _module.args = {
          inherit imageModules;
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
          inherit
            imageModules
            keylimeModule
            keylimeAgentModule
            keylimePackage
            keylimeAgentPackage
            ;
        };
      }
    ];
  };

}
