# smallthinker-deploy

在单机 **CPU** 上以 OpenAI 兼容 API 部署 **Qwen3-30B-A3B（abliterated 无审查版）** 的完整工程包，由 **SmallThinker**（PowerInfer sparse-MoE 引擎，llama.cpp 1594 fork）驱动。经过实测调优，开箱支持 **128K 长上下文**，无需 GPU。

> 本项目是部署/运维层封装：不包含模型文件（23.37 GiB），不修改引擎源码；所有脚本与配置均在本机实测验证后整理发布。

## 特性

- 🖥️ 纯 CPU 推理（8 线程，实测 17–20 tok/s 生成）
- 📜 上下文 40K → **128K**（YaRN 扩展 + KV cache q8_0 量化 + flash-attention）
- ⚡ 线程级调优（`-t 8 -tb 16 -ub 512`，prefill +61% 且不损失生成速度）
- 🔓 无审查权重（mlabonne abliterated → mradermacher Q6_K 量化）
- 🚀 OpenAI 兼容 `/v1` API（llama-server），可一键接入 DSH / 任意 OpenAI 客户端
- 🎛️ 单一控制脚本：`smallthinker-ctl {start|stop|status|restart}`
- ✅ 附带构建、下载、冒烟验证脚本与实测优化文档

## 目录结构

```
smallthinker-deploy/
├── README.md                    # 本文档
├── LICENSE                      # MIT（本仓库脚本）
├── .gitignore                   # 排除模型 / 构建产物 / 日志
├── bin/
│   └── smallthinker-ctl         # 引擎控制脚本（start/stop/status/restart）
├── scripts/
│   ├── build-engine.sh          # 构建 llama-server / llama-cli（clang-18 + -march=native）
│   ├── download-model.sh        # 下载 abliterated Q6_K GGUF（hf-mirror + 大小校验）
│   └── smoke-test.sh            # 端到端冒烟：/health → /v1/models → chat completion
├── config/
│   └── dsh-provider.yml.example # DSH（DeepSeek Harness）provider 集成示例
└── docs/
    └── OPTIMIZATIONS.md         # 全部优化实验的实测数据与结论
```

## 快速开始

### 0. 依赖

- Linux（开发环境：WSL2 / Ubuntu，20 核 CPU，54 GiB RAM，内存建议 ≥ 32 GiB）
- `clang-18`、`clang++-18`、`cmake ≥ 3.20`、`git`、`make`
- `curl`；下载模型建议 `aria2c`
- 磁盘：构建 ~20 GiB，模型 23.37 GiB

### 1. 构建引擎

```bash
git clone https://github.com/Xian-debu/smallthinker-deploy.git
cd smallthinker-deploy
chmod +x bin/smallthinker-ctl scripts/*.sh
./scripts/build-engine.sh
```

构建产物位于 `third_party/PowerInfer/build/bin/llama-server`（默认）。脚本会克隆
`Tiiny-AI/PowerInfer` 并固定到实测过的 commit `8bd56d6`。

### 2. 下载模型

```bash
./scripts/download-model.sh ~/models
```

详见下方「模型说明」。

### 3. 配置并启动

编辑 `bin/smallthinker-ctl` 顶部的默认路径，或通过环境变量覆盖：

```bash
export ST_BIN="$PWD/third_party/PowerInfer/build/bin/llama-server"
export ST_MODEL="$HOME/models/Qwen3-30B-A3B-abliterated.Q6_K.gguf"
export ST_MODEL_ID="qwen3-30b-a3b-abliterated"
export ST_PORT=8321
export ST_CTX=131072

bin/smallthinker-ctl start
bin/smallthinker-ctl status
```

### 4. 验证

```bash
./scripts/smoke-test.sh
# ==> [1/3] GET /health            OK
# ==> [2/3] GET /v1/models        OK
# ==> [3/3] POST /v1/chat/completions
#     reply: 我是由阿里云研发的人工智能助手……
#     usage: {'prompt_tokens': 18, 'completion_tokens': 64, 'total_tokens': 82}
# ==> Smoke test passed.
```

## 模型说明

| 项 | 值 |
|---|---|
| 基座模型 | Qwen3-30B-A3B（Qwen 团队，Apache-2.0，原生上下文 40960） |
| 无审查版本 | mlabonne 的 abliterated 权重（去除拒绝训练） |
| GGUF 量化 | mradermacher Q6_K，`Qwen3-30B-A3B-abliterated.Q6_K.gguf` |
| 文件大小 | **25,092,532,192 字节 ≈ 23.37 GiB** |
| 量化档位 | Q2_K ~ Q8_0 全系列可选（本项目实测选用 Q6_K） |

模型文件**不纳入本仓库**（.gitignore 已排除 `*.gguf`）。请自行下载：

- 主源（无审查）：`https://huggingface.co/mradermacher/Qwen3-30B-A3B-abliterated-GGUF`
- 国内镜像：把域名换为 `hf-mirror.com`（`download-model.sh` 默认使用）
- 官方 censored 版（无审查需求时）：`huggingface.co/Qwen/Qwen3-30B-A3B-GGUF`

下载后建议校验大小（脚本已内置）并自行计算 SHA256：

```bash
sha256sum Qwen3-30B-A3B-abliterated.Q6_K.gguf
```

## 性能实测（开发机）

| 场景 | prompt eval | 生成 eval |
|---|---|---|
| 40K 原生基线（f16 KV） | 52–63 tok/s | 15.2–18.0 tok/s |
| **128K YaRN + q8_0 KV + flash-attn** | 53–63 tok/s | **17–20 tok/s** |
| 256K YaRN + q8_0 KV + flash-attn | 57 tok/s | 18.3 tok/s |

- 128K 相比 40K 基线：上下文 +220%，长上下文生成速度 **+32.6%**，短上下文零损失。
- 峰值内存：128K ≈ 29.8 GB，256K ≈ 36.2 GB。
- 详细实验数据见 [docs/OPTIMIZATIONS.md](docs/OPTIMIZATIONS.md)。

## 与其它开源项目的关系

| 组件 | 上游项目 | 许可 |
|---|---|---|
| 推理引擎 | [Tiiny-AI/PowerInfer](https://github.com/Tiiny-AI/PowerInfer)（SmallThinker 引擎，llama.cpp 1594 fork） | Apache-2.0 |
| 基座模型 | [Qwen3-30B-A3B](https://huggingface.co/Qwen/Qwen3-30B-A3B)（Qwen 团队） | Apache-2.0 |
| 无审查权重 | mlabonne abliterated（[mradermacher GGUF 仓库](https://huggingface.co/mradermacher/Qwen3-30B-A3B-abliterated-GGUF) 内说明） | 派生自 Apache-2.0 权重 |
| GGUF 量化 | mradermacher | — |
| 本仓库脚本/文档 | smallthinker-deploy（Xian-debu） | MIT |

本仓库是**纯部署/运维层**：不修改上游引擎源码，不重新分发模型权重；所有贡献均基于上述项目的公开接口与实测经验整理。

## 后续改进方向

- **检索式 KV 窗口**：参考 ninfer KVMem 思路，把「当前窗口 + 检索到的历史 block」留在内存、其余分层到磁盘，进一步突破 128K（CPU 场景收益有限，需先做可行性原型）。
- **预取调度细化**：引擎已内置 MoE 预取（powerinfer_init_moe_pipeline + MAP_POPULATE），可研究按注意力热度的更细粒度预取。
- **MTP（多 token 预测）**：当前模型无 mtp 头、引擎无支持；等待上游模型/引擎演进后接入。
- **投机解码**：CPU 上实测为负优化（2.8–3.7× 变慢），有 GPU 后可复用本项目参数重新评估。
- **量化档位**：q4_0 与 q8_0 速度持平但省 3 GiB 内存，可做质量对比后切换。
- **256K 工程化**：已验证可行（36.2 GB），可通过增大内存或 4-bit KV 落地为可选配置。
- **更多客户端集成**：示例已覆盖 DSH，可补充 Ollama / LiteLLM / 任意 OpenAI SDK 接入指南。

## 许可

MIT © 2026 Xian-debu。详见 [LICENSE](LICENSE)。

上游引擎与模型权重分别遵循其自身许可（Apache-2.0）。
