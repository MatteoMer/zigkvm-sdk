# Scripts

This directory groups helper scripts by backend or purpose.

## Ligero

Ligero installer and tooling live in `scripts/ligero/`:

- `scripts/ligero/install-ligero.sh` - build/install the Ligero prover
- `scripts/ligero/get-ligero.sh` - curl wrapper for the installer
- `scripts/ligero/create-ligero-config.zig` - generate Ligero JSON config from input.bin
- `scripts/ligero/run-ligero.zig` - run `webgpu_prover`/`webgpu_verifier` with JSON configs

See `scripts/ligero/README.md` for full usage details.
