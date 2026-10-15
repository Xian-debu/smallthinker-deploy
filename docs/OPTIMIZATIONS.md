# Optimization notes

All measurements below were taken on the development machine:

- CPU: 20-core (8 threads used for inference; the sparse-MoE runtime caps at 8)
- RAM: 54 GiB total, ~43 GiB available
- Model: Qwen3-30B-A3B-abliterated Q6_K (23.37 GiB)
- Engine: Tiiny-AI/PowerInfer at commit 8bd56d6 (llama.cpp 1594 fork)
  built with clang-18, Release, -march=native

## 1. Context extension: 40K -> 128K (YaRN + quantized KV + flash-attn)

The model's native context is 40,960 tokens. llama.cpp's YaRN rope scaling
extends it with minimal quality loss:

```
--rope-scaling yarn --yarn-orig-ctx 40960 -c 131072
-ctk q8_0 -ctv q8_0 --flash-attn
```

Important: in this fork, quantizing the V cache requires flash attention, otherwise
llama-server aborts with "V cache quantization requires flash_attn".

| config | prompt eval (tok/s) | eval (tok/s) | peak RSS |
|---|---|---|---|
| 40K f16 (baseline, 1.3K prompt) | 63.16 | 15.16 | ~27.3 GB |
| 128K YaRN + q8_0 + flash (1.3K prompt) | 63.19 | **20.11** | ~29.8 GB |
| 256K YaRN + q8_0 + flash (1.3K prompt) | 57.36 | 18.26 | ~36.2 GB |
| 40K f16 (short prompt matrix) | 52.15 | 18.02 | 28.5 GB |
| 128K f16 + yarn + flash (short prompt) | 28.95 | 16.70 | 37.2 GB |
| 128K q8_0 + yarn + flash (short prompt) | 53.19 | 18.07 | 31.3 GB |
| 128K q4_0 + yarn + flash (short prompt) | 49.79 | 18.17 | 28.1 GB |

Takeaways:

- 128K q8_0 is the sweet spot: +220% context with zero loss on short prompts and
  **+32.6% generation speed on long prompts** (20.11 vs 15.16 tok/s) because the
  quantized KV halves the memory bandwidth pressure (CPU bottleneck).
- 256K is feasible (18.26 tok/s, 36.2 GB RSS) but the memory headroom shrinks.
- KV quantization benefit grows with context length.

## 2. -march=native rebuild (KV-NATIVE-001)

The prebuilt binaries shipped without CPU instruction-set flags (-O3 only).
Rebuilding with `-march=native -mtune=native` (clang-18):

- short prompt: no measurable difference
- long prompt (3053 tokens): prompt 37.43 -> 38.41 tok/s (+2.6%),
  eval 10.79 -> 11.24 tok/s (+4.2%)

Small but free; the repo builds with -march=native by default.

## 3. Thread / batch tuning (KV-THREAD-001)

Sparse MoE has a hard cap of 8 inference threads in this runtime.

| config | prompt eval (tok/s) | eval (tok/s) |
|---|---|---|
| -t 8 -b 2048 (baseline) | 39.35 | 11.17 |
| -t 8 -tb 16 (batch 16) | 65.48 (+66%) | 10.25 |
| **-t 8 -tb 16 -ub 512** | **63.49 (+61%)** | **11.24** |

`-tb 16 -ub 512` is the recommended setting: +61% prefill with no generation
regression. (Note: -tb/-ub are the batch and micro-batch sizes for prompt
processing; larger batches make prefill faster on CPU.)

## 4. Speculative decoding: NEGATIVE on CPU (KV-SPEC-001)

A local draft model (Qwen3-0.6B Q4_K_M, matching 151,936-token vocabulary) was
tested with llama-server `--model-draft` (3045-token prefill + 64 generated):

| config | eval (tok/s) |
|---|---|
| no draft | 11.37 |
| draft_n 8 | 4.05 |
| draft_n 16 | 3.07 |

Even with every draft token accepted, CPU speculative decoding is 2.8-3.7x
slower (draft verification doubles the per-token compute). Not adopted.

## 5. KV quantization sweep (KV-QUANT-002)

128K YaRN + flash-attn, short prompt:

| type | eval (tok/s) |
|---|---|
| q8_0 | 18.07 |
| q4_0 | 18.17 |
| q4_1 | 17.07 |
| iq4_nl | 17.08 |
| q5_0 | 17.24 |
| q5_1 | 17.22 |

q8_0 / q4_0 win. q8_0 is kept for better quality/robustness.

## 6. Operational pitfalls

- **Proxy interception**: `curl 127.0.0.1:8321` must use `--noproxy '*'`;
  a system HTTP proxy forwards loopback to the upstream and fails with 502.
  The ctl script unsets proxy variables and exports no_proxy.
- **Readiness**: llama-server's `/v1/models` returns 200 while the model is
  still loading. Use `/health` with `{"status":"ok"}` for real readiness.
- **Shutdown**: this fork may ignore SIGTERM; the ctl script escalates to
  SIGKILL and reclaims the port.
