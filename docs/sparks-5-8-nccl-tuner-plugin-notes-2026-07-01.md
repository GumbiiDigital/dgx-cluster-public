# Sparks 5-8 NCCL Tuner Plugin Notes

Date: 2026-07-01

## Recommendation

Use a static NCCL profile first:

```bash
PROFILE_FILE=scripts/sparks58-nccl-profile.env \
  scripts/run-sparks58-nccl-profile.sh
```

The evidence from `evidence/nccl-experiment-program-5-8-20260701-110837/`
shows that a static profile is enough to move fixed 256MiB four-node
`all_reduce_perf` into the `23.8 GB/s` class.

## Why Not Build A Tuner Plugin First?

NVIDIA's NCCL tuning guidance says tuner plugins are the intended mechanism for
platform-specific overrides when NCCL's default model makes a poor choice. That
fits this CRS804/DGX Spark topology in principle.

For this repo, the next plugin step should wait until we have two more evidence
pieces:

1. A stable size-aware policy table across 2-node, 4-node, and eventually
   8-node runs.
2. A clear rule for when the profile should choose `channels8` versus
   `qps4split1` versus the combined profile.

The current size-aware sweep shows the best setting changes by message size:

- `8K`: baseline won.
- `64K-32M`: `channels8` won.
- `256M`: combined `qps4split1-ch8-ignore` won.
- `1G-4G`: `qps4split1` won.

That means a tuner plugin is attractive, but a hard-coded plugin today would be
premature unless it encodes message-size thresholds and is tested across the
full scaling matrix.

## Source Anchors

- NVIDIA NCCL environment variables:
  <https://docs.nvidia.com/deeplearning/nccl/user-guide/docs/env.html>
- NVIDIA NCCL tuning blog:
  <https://developer.nvidia.com/blog/understanding-nccl-tuning-to-accelerate-gpu-to-gpu-communication/>
