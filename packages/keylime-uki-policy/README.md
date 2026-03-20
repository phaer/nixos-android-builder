# UKI Measured Boot Policy for Keylime

Custom keylime measured boot attestation (MBA) policy for Unified Kernel
Image (UKI) boot chains (systemd-boot + UKI), replacing keylime's
built-in `example` policy which expects a shim → GRUB → kernel chain.

## Why a custom policy?

A UKI boot produces a different UEFI event log than the traditional
shim/GRUB chain:

- **PCR 4** has a single `EV_EFI_BOOT_SERVICES_APPLICATION` (the UKI
  itself), not a shim → GRUB → kernel sequence.
- **PCR 8/9** have no `EV_IPL` events for kernel cmdline or initrd.
  Instead, systemd-stub measures UKI PE sections into **PCR 11**.
- **PCR 11** has both firmware-time events (UKI PE sections from
  systemd-stub) and runtime extensions (boot phases from
  systemd-pcrphase). Keylime claims PCR 11 globally for measured boot,
  so it cannot also be in `tpm_policy`. The policy accepts PCR 11
  events but does not include it in `relevant_pcr_indices`.

## Components

- **`uki_policy.py`** — Keylime MBA policy module. Loaded by the
  verifier via `measured_boot_imports = ["uki_policy"]` with the
  containing directory on `PYTHONPATH`. Registers as policy name `uki`.
- **`create_uki_refstate.py`** — CLI tool that parses a binary UEFI
  event log (via `tpm2_eventlog`) and outputs a reference state JSON.
  Used by `report-mb-refstate` on the agent side, and can be run manually.

## Reference state JSON schema

```json
{
  "scrtm_and_bios": [
    {
      "scrtm": {"sha256": "0x<64 hex chars>"},
      "platform_firmware": [
        {"sha256": "0x<64 hex chars>"},
        ...
      ]
    }
  ],
  "pk":  [{"SignatureOwner": "<guid>", "SignatureData": "0x<hex>"}],
  "kek": [{"SignatureOwner": "<guid>", "SignatureData": "0x<hex>"}],
  "db":  [{"SignatureOwner": "<guid>", "SignatureData": "0x<hex>"}],
  "dbx": [],
  "uki_digest": {"sha256": "0x<64 hex chars>"},
  "uki_sections": [{"sha256": "0x<64 hex chars>"}, ...]
}
```

| Field | Source | Policy action |
|-------|--------|---------------|
| `scrtm_and_bios` | PCR 0: `EV_S_CRTM_VERSION` + `EV_EFI_PLATFORM_FIRMWARE_BLOB` | Pinned |
| `pk`, `kek`, `db`, `dbx` | PCR 7: `EV_EFI_VARIABLE_DRIVER_CONFIG` | Pinned |
| `uki_digest` | PCR 4: `EV_EFI_BOOT_SERVICES_APPLICATION` (non-firmware) | Pinned |
| `uki_sections` | PCR 11: `EV_IPL` from systemd-stub | Not validated (accepted; PCR 11 is in the TPM quote via keylime's measured boot PCR mask) |

## What the policy validates

| PCR | Events | Action |
|-----|--------|--------|
| 0 | SCRTM version, firmware blobs | Pinned to refstate digests |
| 1 | Boot variables, platform config, handoff tables | Accepted (varies with BIOS settings) |
| 2 | Boot services drivers | Accepted |
| 3 | (empty, separator only) | Separator check |
| 4 | UKI application, EFI actions | UKI digest pinned to refstate |
| 5 | GPT table, EFI actions | Accepted |
| 7 | SecureBoot, PK, KEK, db, dbx, authority | Keys pinned to refstate |
| 9 | `EV_EVENT_TAG` from systemd-stub | Accepted |
| 11 | UKI PE sections from systemd-stub | Accepted |
