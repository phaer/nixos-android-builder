{ pkgs, ... }:
{
  # Set an empty password for "user"
  users.users."user" = {
    initialHashedPassword = "";
  };

  # Allow root to login without password
  users.users.root.initialHashedPassword = "";

  # Allow password-less sudo for wheel users
  security.sudo.wheelNeedsPassword = false;

  # Auto-login user
  services.getty.autologinUser = "user";

  # Enable unauthenticated shell if early boot fails
  boot.initrd.systemd.emergencyAccess = true;

  # Add verbose log output, to aid debugging boot issues. log_level=debug is available as well.
  boot.kernelParams = [
    "systemd.show_status=true"
    "systemd.log_level=info"
    "systemd.log_target=console"
    "systemd.journald.forward_to_console=1"
  ];

  # Add grep to the initrd. Feel free to remove, this just makes
  # inspection and debugging in an emergency shell much more convinient.
  boot.initrd.systemd.initrdBin = [ pkgs.gnugrep ];
}
