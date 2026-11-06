{ lib, ... }:
{
  # Decrypt with the system's existing identities; the user receives only these
  # credential files, never a copy of the machine's private decryption keys.
  sops.secrets =
    lib.genAttrs
      [
        "rclone/garage/access-key-id"
        "rclone/garage/secret-access-key"
        "rclone/garage-k3s/access-key-id"
        "rclone/garage-k3s/secret-access-key"
        "rclone/backblaze/access-key-id"
        "rclone/backblaze/secret-access-key"
      ]
      (_: {
        owner = "peter";
        mode = "0400";
      });
}
