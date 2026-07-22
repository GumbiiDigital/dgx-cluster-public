# Six Spark Firmware Recheck - 2026-06-30

This note records the firmware recheck after Sparks 1 through 4 were moved back
onto the CRS804 breakout fabric and Sparks 5 and 6 were online in Tailscale.

Raw local evidence was captured under:

```text
evidence/firmware-recheck-20260630-111823/
```

The raw evidence directory is intentionally ignored by git.

## Source Guidance

Perplexity/forum research is being used as a hypothesis source for the CRS804
and RoCE behavior, but firmware status is accepted only from local device tools:

- `fwupdmgr get-upgrades` for platform firmware.
- `nvidia-smi` for the installed GPU driver and VBIOS.
- `mlxfwmanager --query` from NVIDIA MFT for visible ConnectX firmware state.

The official references checked for this pass were:

- MikroTik RouterOS SSH docs: `https://help.mikrotik.com/docs/spaces/ROS/pages/132350014/SSH`
- NVIDIA MFT `mlxfwmanager` docs: `https://docs.nvidia.com/networking/display/MFTv4350/mlxfwmanager+-+Firmware+Update+and+Query+Tool`

## Fleet Result

All six Sparks were online in Tailscale and reachable over SSH with the NVIDIA
Sync key.

| Alias | Hostname | Tailscale name | Reboot required | GPU driver | GPU VBIOS |
| --- | --- | --- | --- | --- | --- |
| `spark-a.example` | `spark-a.example` | `spark-a.example` | `no` | `580.159.03` | `9A.0B.25.00.00` |
| `spark-b.example` | `spark-b.example` | `spark-b.example` | `no` | `580.159.03` | `9A.0B.25.00.00` |
| `spark-c.example` | `spark-c.example` | `spark-c.example` | `no` | `580.159.03` | `9A.0B.25.00.00` |
| `spark-d.example` | `spark-d.example` | `spark-d.example` | `no` | `580.159.03` | `9A.0B.25.00.00` |
| `spark-e.example` | `spark-e.example` | `spark-e.example` | `no` | `580.159.03` | `9A.0B.25.00.00` |
| `spark-f.example` | `spark-f.example` | `spark-f.example` | `no` | `580.159.03` | `9A.0B.25.00.00` |

`fwupdmgr get-upgrades` reported `No updates available` on all six nodes.

## ConnectX Firmware

Sparks 1 through 4 have visible ConnectX-7 / MT2910 devices. Both `fwupdmgr`
and `mlxfwmanager` report no available update for the visible NIC firmware.

Uniform visible ConnectX baseline:

```text
Device Type: ConnectX7
Part Number: cx7_P4242_HORIZON_PK_Ax
Description: NVIDIA DGX Spark P4242
PSID: NVD0000000087
FW: 28.45.4028
PXE: 3.7.0500
UEFI: 14.37.0014
Available: N/A
Status: No matching image found
```

| Alias | Hostname | PCI device | Base GUID |
| --- | --- | --- | --- |
| `spark-a.example` | `spark-a.example` | `0000:01:00.0` | `4cbb4703002bab32` |
| `spark-b.example` | `spark-b.example` | `0000:01:00.0` | `4cbb4703002afaf5` |
| `spark-c.example` | `spark-c.example` | `0000:01:00.0` | `4cbb4703002d5e4a` |
| `spark-d.example` | `spark-d.example` | `0000:01:00.0` | `4cbb4703002d782a` |

Sparks 5 and 6 do not currently enumerate ConnectX devices:

```text
mlxfwmanager: No devices found or specified
mst status: No MST devices were found or MST modules are not loaded
lspci: no ConnectX/Mellanox device output
```

This is not treated as an update failure because Sparks 5 and 6 are not yet
connected to the QSFP/RDMA fabric. Their ConnectX firmware still needs to be
verified after those ports are cabled and enumerate.

## Temporary CRS804 Key Status

A temporary local key was generated for CRS804 access:

```text
Private key: /opt/public-user/.ssh/crs804_dgx_temp_ed25519
Public key:  /opt/public-user/.ssh/crs804_dgx_temp_ed25519.pub
Fingerprint: SHA256:74CydS/U1sdlkZDWLGFDgkiGV/wIAvJh/hFs4yO3svg
```

The key is not installed on the CRS804 yet. A key-only test currently returns:

```text
public-admin@192.0.2.10: Permission denied (publickey,password).
```

Next step is to import the public key into RouterOS for `public-admin`, then repeat the
CRS804 counter capture around the failing CRS804-path RoCE test.
