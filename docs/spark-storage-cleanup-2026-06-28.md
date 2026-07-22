# Spark Storage Cleanup
Date: 2026-06-28

Goal: return the visible DGX Spark boxes to a storage-light baseline while preserving OS, SSH, Tailscale, NVIDIA drivers, DGX dashboard services, and DGX Spark Prometheus exporter.

## Preserved Baseline Services

Verified active on both `spark-a.example` and `spark-b.example` after cleanup:

```text
ssh
tailscaled
nvidia-persistenced
dgx-dashboard
dgx-dashboard-public-admin
dgx-spark-prometheus
```

Both systems still report:

```text
NVIDIA GB10, driver 580.142
```

## `spark-a.example`

Before:

```text
/dev/nvme0n1p2 ext4 3.7T total, 3.1T used, 403G available, 89% used
```

After:

```text
/dev/nvme0n1p2 ext4 3.7T total, 245G used, 3.3T available, 7% used
```

Removed high-volume user payloads included:

```text
/opt/public-user/.cache
/opt/public-user/.ollama
/opt/public-user/.paperclip
/opt/public-user/models
/opt/public-user/ComfyUI*
/opt/public-user/comfyui-*
/opt/public-user/comfy_queue_service
/opt/public-user/cosmos-predict2.5
/opt/public-user/daVinci-MagiHuman
/opt/public-user/davinci-magihuman
/opt/public-user/holo-design-to-code-v1
/opt/public-user/jupyterlab
/opt/public-user/llama.cpp
/opt/public-user/llama-cpp-venv
/opt/public-user/spark-lab
/opt/public-user/spark-vllm-docker
/opt/public-user/vllm*
/opt/public-user/voice
/opt/public-user/venv_audio
/opt/public-user/public-wrapper*
/opt/public-user/aeon-spark-studio
/opt/public-user/qwen-chat-ui
/opt/public-user/roleplay-chat-ui
/opt/public-user/unsloth_compiled_cache
/opt/public-user/projects
/opt/public-user/fleet-agent
/opt/public-user/.hermes
```

Disabled or removed custom user launchers included:

```text
cliproxyapi*
fleet-agent
public-wrapper-spark-a.example
hermes-gateway
paperclip*
comfyui-spark-a.example
comfy-queue
llama-qwen
director-*
tmux-*
lightreel-tiktok-ingest
```

Post-cleanup workload process scan showed only baseline `earlyoom`, SSH session processes, and the scan command itself.

## `spark-b.example`

Before:

```text
/dev/nvme0n1p2 ext4 3.7T total, 1.6T used, 2.0T available, 44% used
```

After:

```text
/dev/nvme0n1p2 ext4 3.7T total, 221G used, 3.3T available, 7% used
```

Removed high-volume user payloads included:

```text
/opt/public-user/.cache
/opt/public-user/.ollama
/opt/public-user/.clawspark
/opt/public-user/.clawmetry
/opt/public-user/.clicky-dgx
/opt/public-user/.openclaw
/opt/public-user/models
/opt/public-user/clicky-dgx
/opt/public-user/clicky-gguf
/opt/public-user/clicky-stt
/opt/public-user/clicky-tts
/opt/public-user/clicky-vlm
/opt/public-user/davinci-magihuman
/opt/public-user/daVinci-MagiHuman
/opt/public-user/holo-design-to-code-v1
/opt/public-user/jupyterlab
/opt/public-user/LTX-2
/opt/public-user/personaplex-fp8
/opt/public-user/personaplex-runtime
/opt/public-user/strata
/opt/public-user/a2a-comms
/opt/public-user/projects
/opt/public-user/frameworks
/opt/public-user/tensortowns
/opt/public-user/lhm-plusplus
/opt/public-user/.hermes
/opt/public-user/venv
```

Disabled or masked custom workload services included:

```text
ollama.service
a2a-spark-b.example.service
clawspark-dashboard.service
clawspark-gateway.service
clawspark-nodehost.service
huihui-qwen3vl.service
strata-comfy.service
```

Post-cleanup workload process scan showed no Ollama, ComfyUI, Clicky, DaVinci/MagiHuman, Qwen, A2A, or ClawSpark processes.

## Network Verification

The LAN verifier still passed after cleanup:

```text
CRS804 192.0.2.10 ping: 0.0% packet loss
CRS804 services: SSH and WinBox open; FTP, Telnet, HTTP, HTTPS, API, API-SSL closed
spark-b.example -> 192.0.2.10
spark-a.example -> 192.0.2.10
```
