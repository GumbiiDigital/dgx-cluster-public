# Spark Inventory

Date: 2026-06-28

Read-only inventory of the currently visible DGX Spark systems.

## Summary

| Host | Management IP | Tailscale IP | Root Disk | GPU State | Main Role Seen |
| --- | ---: | ---: | --- | --- | --- |
| `spark-b.example` | `192.0.2.10` | `192.0.2.10` | 3.7T ext4, 1.6T used, 2.0T free | NVIDIA GB10 active, Python using GPU | Active serving/workflow box |
| `spark-a.example` | `192.0.2.10` | `192.0.2.10` | 3.7T ext4, 3.1T used, 403G free | NVIDIA GB10 idle except desktop | Model/cache/workspace-heavy box |

Both systems report:

- Ubuntu `24.04.4 LTS`
- Kernel `6.17.0-1014-nvidia`
- NVIDIA driver `580.142`
- CUDA `13.0`
- NVIDIA DGX Dashboard services
- DGX Spark Prometheus exporter
- NVIDIA persistence daemon
- SSH
- Tailscale

## `spark-b.example`

Network:

```text
enP7s7           192.0.2.10/22
enp1s0f0np0      192.0.2.10/24
enP2p1s0f0np0    192.0.2.10/24
tailscale0       192.0.2.10/32
```

Storage:

```text
/dev/nvme0n1p2 ext4 3.7T total, 1.6T used, 2.0T available, 44% used
sshfs shared-office mount: public-user@192.0.2.10:/opt/public-cluster/shared-office
```

GPU:

```text
NVIDIA GB10
Driver Version: 580.142
CUDA Version: 13.0
GPU utilization: 0% at inventory time
Active GPU processes:
- /usr/bin/python3 /opt/public-cluster/serve_huihui_qwen3vl.py
- python main.py --listen 192.0.2.10 --port 8188 --enable-cors-header *
```

Running services and workloads:

- `a2a-spark-b.example.service`
- `clawspark-dashboard.service`
- `dgx-dashboard-public-admin.service`
- `dgx-dashboard.service`
- `dgx-spark-prometheus.service`
- `nvidia-persistenced.service`
- `ollama.service`
- `ssh.service`
- `tailscaled.service`

Open ports observed:

```text
22 ssh
80 http
8000 serve_huihui_qwen3vl.py
8188 ComfyUI-style Python process
8900 local ClawMetry dashboard
9123 A2A box agent on Tailscale
9835 DGX Spark Prometheus
11000 local DGX dashboard service
11434 Ollama
```

Ollama models:

```text
nemotron-mini:latest  2.7 GB
clicky-vlm:latest     23 GB
```

Major home directories:

```text
761G /opt/public-user/models
114G /opt/public-user/davinci-magihuman
101G /opt/public-user/clicky-dgx
81G  /opt/public-user/LTX-2
66G  /opt/public-user/holo-design-to-code-v1
44G  /opt/public-user/strata
39G  /opt/public-user/.cache
28G  /opt/public-user/.ollama
23G  /opt/public-user/personaplex-runtime
22G  /opt/public-user/clicky-gguf
17G  /opt/public-user/projects
```

Model directories observed:

```text
/opt/public-user/models/huggingface/openbmb__MiniCPM-o-2_6
/opt/public-user/models/huggingface/Qwen__Qwen2.5-Omni-7B
/opt/public-user/models/huggingface/sshleifer__tiny-gpt2
/opt/public-user/models/Huihui-Qwen3-VL-4B-Instruct-abliterated
```

## `spark-a.example`

Network:

```text
enP7s7           192.0.2.10/24
tailscale0       192.0.2.10/32
```

Storage:

```text
/dev/nvme0n1p2 ext4 3.7T total, 3.1T used, 403G available, 89% used
```

GPU:

```text
NVIDIA GB10
Driver Version: 580.142
CUDA Version: 13.0
GPU utilization: 0% at inventory time
Active GPU processes:
- /usr/lib/xorg/Xorg
- /usr/bin/gnome-shell
```

Running services and workloads:

- `dgx-dashboard-public-admin.service`
- `dgx-dashboard.service`
- `dgx-spark-prometheus.service`
- `nvidia-persistenced.service`
- `ssh.service`
- `tailscaled.service`
- `public-panel` process on localhost
- `hermes` gateway process
- `CLIProxyAPI`
- local Next.js/node services
- local Postgres process

Open ports observed:

```text
22 ssh
3000 next-server
7788 node
8317 CLIProxyAPI
8420 local public-panel
9835 DGX Spark Prometheus
11000 local DGX dashboard service
3100/3101/13100 local node/socat services
54329 local postgres
```

Ollama:

```text
ollama command not available in PATH at inventory time
/opt/public-user/.ollama exists and is 5.3G
```

Major home directories:

```text
1.4T /opt/public-user/models
385G /opt/public-user/comfyui-aeon-spark
235G /opt/public-user/ComfyUI-agent2
205G /opt/public-user/davinci-magihuman
180G /opt/public-user/.cache
128G /opt/public-user/.paperclip
103G /opt/public-user/ComfyUI-OmniBe
76G  /opt/public-user/public-wrapper-state
66G  /opt/public-user/holo-design-to-code-v1
43G  /opt/public-user/ComfyUI-agent3
35G  /opt/public-user/spark-lab
19G  /opt/public-user/projects
15G  /opt/public-user/.cache
13G  /opt/public-user/.hermes
12G  /opt/public-user/vllm
12G  /opt/public-user/vllm-venv
```

Model/cache directories:

```text
1.4T /opt/public-user/models
99G  /opt/public-user/.cache/huggingface
3.9G /opt/public-user/.cache/vllm
2.8G /opt/public-user/.cache/torch
5.3G /opt/public-user/.ollama
2.0G /opt/nvidia
```

Model directories observed:

```text
/opt/public-user/models/Qwen3-8B
/opt/public-user/models/Qwen3.6-27B-FP8
/opt/public-user/models/Qwen3.6-35B-A3B-FP8
/opt/public-user/models/aeon-workstation-b/Gemma-4-26B-A4B-it-Uncensored-NVFP4
/opt/public-user/models/aeon-workstation-b/Gemma-4-31B-it-DECKARD-HERETIC-Uncensored-NVFP4
/opt/public-user/models/aeon-workstation-b/Gemma-4-31B-it-DECKARD-HERETIC-Uncensored-NVFP4-SVDQuant
/opt/public-user/models/aeon-workstation-b/Gemma-4-E4B-DECKARD-HERETIC-NVFP4
/opt/public-user/models/aeon-workstation-b/Gemma-4-E4B-DECKARD-HERETIC-Uncensored-NVFP4
/opt/public-user/models/aeon-workstation-b/Gemma-4-E4B-it-Uncensored-NVFP4
/opt/public-user/models/aeon-workstation-b/Qwen3.6-27B-AEON-Ultimate-Uncensored-BF16
/opt/public-user/models/aeon-workstation-b/Qwen3.6-27B-AEON-Ultimate-Uncensored-Multimodal-NVFP4-MTP
/opt/public-user/models/aeon-workstation-b/Qwen3.6-27B-AEON-Ultimate-Uncensored-Multimodal-NVFP4-MTP-XS
/opt/public-user/models/aeon-workstation-b/Qwen3.6-27B-AEON-Ultimate-Uncensored-NVFP4
/opt/public-user/models/aeon-workstation-b/Qwen3.6-27B-AEON-Ultimate-Uncensored-Text-NVFP4-MTP
/opt/public-user/models/aeon-workstation-b/Qwen3.6-27B-AEON-Ultimate-Uncensored-Text-NVFP4-MTP-XS
/opt/public-user/models/aeon-workstation-b/Qwen3.6-35B-A3B-heretic-NVFP4
/opt/public-user/models/aeon-workstation-b/gemma-4-31B-it-speculator.eagle3-NVFP4
/opt/public-user/models/gguf/Jackrong-Qwen3.6-27B-GGUF
/opt/public-user/models/roleplay_7b
/opt/public-user/models/stable-audio-open-1.0
/opt/public-user/models/t5gemma-9b-9b-ul2
```
