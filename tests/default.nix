{
  pkgs,
  installerModules,
  imageModules,
  nixos,
}:
let
  nixosWithBackdoor = nixos.extendModules {
    modules = [
      (
        { modulesPath, ... }:
        {
          imports = [
            "${modulesPath}/testing/test-instrumentation.nix"
          ];
          config.testing = {
            backdoor = true;
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
        _module.args = { inherit imageModules; };
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
        };
      }
    ];
  };
  installerInteractive = pkgs.testers.runNixOSTest {
    imports = [
      ./installer.nix
      {
        _module.args = {
          inherit payload;
          inherit installerModules;
          vmInstallerTarget = "select";
        };
      }
    ];
  };

}
