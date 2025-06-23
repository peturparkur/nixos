### Secrets

See nix-sops / sops-nix: https://github.com/Mic92/sops-nix

To edit secrets
```sh
nix-shell -p sops --run "sops secrets/example.yaml"
```

If new host is added to `.sops.yaml` or key is changed, then we will need to update the keys for all secrets that are used by the new host.
```sh
nix-shell -p sops --run "sops updatekeys secrets/example.yaml"
```
