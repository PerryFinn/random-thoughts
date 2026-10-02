# 日报本地 token 计数库选型调研

- 日期：2026-10-02（Asia/Shanghai）
- 关联：[决策票 #16](https://github.com/PerryFinn/random-thoughts/issues/16)
- 状态：研究完成，用户已确认完整方案；本文保留选型证据与限制，正式行为以[长上下文预算决议](https://github.com/PerryFinn/random-thoughts/issues/16)为准。没有安装生产依赖。
- 范围：原生 SwiftUI / Xcode macOS 26.5 应用的文本输入预算。仅查第一方仓库、源码及官方文档；不调用远程计数服务，不上传会话正文。本轮只下载公开源码到临时目录、查验版本与词表哈希，没有实现功能、构建应用或运行应用。

## 结论与建议

社区确有真实 tokenizer 实现，不应把“UTF-8 每字节 1 token”定成唯一常规算法。推荐 **tiktoken-rs + 很薄的 C ABI/Swift 封装**，用它对明确的 OpenAI encoding 计数；官方 Python tiktoken 作为测试基准，不随应用携带 Python 运行时。这个建议基于直接内置官方词表、活跃维护、无需转换资源的组合，正式接入仍需小型集成验证。用户已认可此路线，最终产品行为以决策票的正式决议为准。

对于拥有可靠 `tokenizer.json` 的非 OpenAI 模型，Hugging Face 官方 `swift-transformers` 或社区 `swift-tokenizers` 是另一条路径。它们不能仅凭“OpenAI 兼容 API”或中转模型别名识别真实 tokenizer，也不能默认替代 cl100k/o200k。未知模型的估算策略仍须产品决策；没有找到能精确覆盖任意中转模型的本地通用库。

应分开描述三个概念：文本按某个 encoding 的计数、完整请求输入估算、服务实际计费/上下文用量。即使文本计数正确，隐藏消息格式、系统添加内容和中转改写仍不透明。因此保留已确认的 `inputEstimate ≤ floor(0.8 × (C − O))` 规则；20% 是产品余量，不是对任意服务误差的数学保证。不要把请求 JSON 的所有字节都当作服务实际看到的 token，也不要用库自带模型容量表覆盖用户配置预算。官方 tiktoken 的模型映射只给 encoding，未知名称会失败且前缀匹配可能命中不存在的名称。[OpenAI 映射源码](https://github.com/openai/tiktoken/blob/4e71bbe0c078468e00fefbf94b39849389f346e5/tiktoken/model.py)

## 候选比较

以下“最近提交”指现场浅克隆主分支 HEAD 的提交日期，不是 stars、搜索索引的 updatedAt 或 PR 活跃日期；发行日期来自仓库 Releases API。日期仅是维护证据，不能证明正确性。

| 候选 | 现场版本 / 主分支 | 集成、资源与限制 | 判断 |
| --- | --- | --- | --- |
| [OpenAI tiktoken](https://github.com/openai/tiktoken/releases/tag/0.14.0) | 0.14.0，2026-08-17 发布；HEAD 2026-08-16 | MIT；官方 Python 接口、Rust 核心，没有现成官方 Swift 产品；默认加载器下载并缓存词表，支持显式本地文件 | 权威差分基准；不建议为计数捆绑 Python |
| [tiktoken-rs](https://github.com/zurawiki/tiktoken-rs/releases/tag/v0.12.1) | 0.12.1，2026-09-24；HEAD 同日 | MIT；Rust 1.85+；cl100k/o200k 等词表编译内置；没有现成 Swift 产品，需要薄桥接、静态库打包与可重复构建 | 已认可的选型路线，尚未完成集成验证 |
| [HF swift-transformers](https://github.com/huggingface/swift-transformers/releases/tag/1.3.4) | 1.3.4，2026-09-02；HEAD 2026-09-23 | Apache-2.0；Swift 5.9 基础 manifest，另有 6.1 manifest；macOS 13+；`Tokenizers` 依赖 `Hub` / `Jinja`，并非孤立的小模块；可加载本地文件 | 官方 Swift 生态候选，适合已知且兼容的 HF tokenizer 资源 |
| [DePasqualeOrg/swift-tokenizers](https://github.com/DePasqualeOrg/swift-tokenizers/releases/tag/0.7.4) | 0.7.4，2026-09-15；HEAD 同日 | Apache-2.0；社区维护的 HF Rust tokenizers 封装；Swift 6.2+ / macOS 14+；本地目录加载，预编译静态 artifactbundle | 活跃且运行时聚焦；并非 HF 官方 Swift 项目，仍要管二进制与资源 |
| [DePasqualeOrg/swift-tiktoken](https://github.com/DePasqualeOrg/swift-tiktoken/tree/b4310ee520995ddff45b055de19e6605e0f8e5b6) | HEAD 2025-12-16；未发现 GitHub Release | MIT；纯 Swift 6.2 / macOS 13+；有 cl100k/o200k/harmony；默认下载词表；README 安装地址仍是 `yourname` 占位 | 可比较实现，不宜直接称成熟即插即用依赖 |
| [narner/TiktokenSwift](https://github.com/narner/TiktokenSwift/releases/tag/1.0.0) | 1.0.0，2025-08-12；HEAD 2025-08-11 | MIT；Swift 5.9，Rust UniFFI/XCFramework；README 说明首次使用下载词表；仓库二进制采用 Git LFS | 不是优选：发行包及分发复杂度高，维护证据较旧 |
| [aespinilla/Tiktoken](https://github.com/aespinilla/Tiktoken/tree/4ad6460448278f7a28f1e4ee2723500369f20acb) | HEAD 2023-06-07；未发现 GitHub Release | MIT；Swift 5.7；只列到 cl100k，没有 o200k；README 仍列优化、缓存、测试等 TODO | 排除首选 |
| [lawallet/TikTokenSwift](https://github.com/lawallet/TikTokenSwift/tree/2ac8b89a687c64af940900e5f2c53ea39fdcabcd) | HEAD 2025-06-11；未发现 GitHub Release | MIT；Swift 5.9；支持 o200k/cl100k，下载后磁盘缓存；README 仍说明 allowed-special=all 不完整 | 次级纯 Swift 候选，没有足够证据优于 tiktoken-rs |

“未发现 GitHub Release”仅指 latest-release API 返回 404，不推断仓库没有任何 tag。工程 `SWIFT_VERSION=5.0` 是工程语言模式，不能据此判断 Swift 6 编译器无法编译新版本包；真正集成仍须使用用户的 Xcode 工具链验证。

## 源码核对：OpenAI 与 Rust 路线

官方 tiktoken 的[加载器](https://github.com/openai/tiktoken/blob/4e71bbe0c078468e00fefbf94b39849389f346e5/tiktoken/load.py)有网络、缓存和哈希校验路径；[encoding 定义](https://github.com/openai/tiktoken/blob/4e71bbe0c078468e00fefbf94b39849389f346e5/tiktoken_ext/openai_public.py)包含词表 URL、哈希、正则预切分规则和特殊 token。只复制词表不能自动保证分词一致。

`tiktoken-rs` 的 [Cargo.toml](https://github.com/zurawiki/tiktoken-rs/blob/72a5a800651a1cea1ad609292446ba02c80e3bcd/tiktoken-rs/Cargo.toml)声明 MIT、Rust 1.85、regex / fancy-regex 等依赖；async-openai 是可选项，不应为本地计数启用网络客户端功能。[encoding 源码](https://github.com/zurawiki/tiktoken-rs/blob/72a5a800651a1cea1ad609292446ba02c80e3bcd/tiktoken-rs/src/tiktoken_ext/openai_public.rs)通过 `include_str!` 嵌入词表，直接配置预切分正则和特殊 token；[测试](https://github.com/zurawiki/tiktoken-rs/blob/72a5a800651a1cea1ad609292446ba02c80e3bcd/tiktoken-rs/tests/tiktoken.rs)包含移植自上游的重复文本、空串与正则案例。

现场读取仓库 assets 并计算 SHA-256，以下值与 OpenAI 官方定义相同：

| 资源 | 源文件字节数 | SHA-256 |
| --- | ---: | --- |
| cl100k_base.tiktoken | 1,681,126 | `223921b76ee99bde995b7ff738513eef100fb51d18c93597a113bcffe865b2a7` |
| o200k_base.tiktoken | 3,613,922 | `446a9538cb6c348e3516120d7c08b09f57c36495e2acfffe59a5bf8b0cfb1a2d` |

这是资源一致性证据，不是完整算法等价证明，也不是安装后的 app 增量体积。后续桥接只需提供本地计数、编码标识和错误边界，避免导入推理、费用估算、固定模型容量等无关接口。还需处理 Rust panic 不跨 FFI、内存所有权、并发复用以及 arm64 分发。上述是工程评估，尚未实测实现。

用户询问包体积后，另外下载并解包 crates.io 的 0.12.1 发行包进行核对：[发行元数据](https://crates.io/api/v1/crates/tiktoken-rs/0.12.1)、[发行包](https://crates.io/api/v1/crates/tiktoken-rs/0.12.1/download)。压缩包为 **3,788,463 字节（3.79 MB）**，解压后所有普通文件合计 **8,790,431 字节（8.79 MB）**；上述两份词表合计 **5,295,048 字节（5.30 MB）**。MB 使用十进制。这些数字不含完整依赖构建结果，不能用于宣称最终 app 增量、链接后静态库大小或运行时内存占用。

本次读取 [OpenAI Codex 主分支 Cargo.toml](https://github.com/openai/codex/blob/main/codex-rs/Cargo.toml)没有找到 tiktoken-rs，不能以“Codex 正在使用它”作为采用依据。OpenAI 将 Rust port 列为[非官方移植](https://github.com/openai/tiktoken/issues/97)，这也不构成对所有版本正确性的背书。

## 源码核对：两条 Hugging Face 路线

HF 官方 [Package.swift](https://github.com/huggingface/swift-transformers/blob/af520cfccbbdc2127a0b77a1547fa47b7cd1f8d8/Package.swift)明确列出 Tokenizers → Hub/Jinja 依赖；[Tokenizer.swift](https://github.com/huggingface/swift-transformers/blob/af520cfccbbdc2127a0b77a1547fa47b7cd1f8d8/Sources/Tokenizers/Tokenizer.swift)提供 `from(modelFolder:)`，含 BPE/Unigram 等已知类型映射和 strict 行为。不能把支持一种 JSON 格式等同于完整覆盖所有模型的预切分、normalizer 和模板。

社区 `swift-tokenizers` 的[目录加载接口](https://github.com/DePasqualeOrg/swift-tokenizers/blob/7d67e1479e2f11226bddc800ff1a964228a602b2/Sources/Tokenizers/AutoTokenizerDirectoryLoader.swift)只从本地读取 tokenizer.json 与可选 sidecar；其 [Rust Cargo.toml](https://github.com/DePasqualeOrg/swift-tokenizers/blob/7d67e1479e2f11226bddc800ff1a964228a602b2/rust/Cargo.toml)锁在 HF tokenizers 0.22 系列，源码注释说明暂避新版本特殊 token 解码回归。它不是 OpenAI .tiktoken 文件的直接加载器。

[Package.swift](https://github.com/DePasqualeOrg/swift-tokenizers/blob/7d67e1479e2f11226bddc800ff1a964228a602b2/Package.swift)使用校验和固定的 Rust artifactbundle；普通 Tokenizers 目标不依赖 HFAPI，但 package 层仍声明 swift-hf-api 供测试，不能笼统说整个解析过程“零额外依赖”。0.7.4 使用的 [Rust 0.7.3 发行资源](https://github.com/DePasqualeOrg/swift-tokenizers/releases/tag/tokenizers-rust-0.7.3)压缩包为 17,881,530 字节，覆盖多个 Apple/Linux 架构。它是构建依赖下载体积，不等于最终 macOS app 体积。

HF 官方确实提供 [convert_tiktoken_to_fast](https://huggingface.co/docs/transformers/main/en/tiktoken)：在构建准备阶段由 tiktoken encoding 导出 tokenizer.json，保存正则与附加 token 信息。这是可信的转换途径，但本轮没有验证生成资源在两种 Swift 引擎中的 token ID 与官方一致，所以不能把 HF 路线写成“开箱即用准确计数 OpenAI”。若采用，须锁定生成工具、原始词表、转换结果哈希，并做差分测试；用户运行应用时不应下载模型权重或临时执行 Python 转换。

## 纯 Swift 与现成 FFI 的实际缺口

`swift-tiktoken` 的 [EncodingLoader.swift](https://github.com/DePasqualeOrg/swift-tiktoken/blob/b4310ee520995ddff45b055de19e6605e0f8e5b6/Sources/SwiftTiktoken/EncodingLoader.swift)默认缓存未命中就下载词表；远程下载校验 SHA-256，本地缓存分支直接读取；底层 `loadFromFile`/`loadFromData` 是 private。源码还改变了部分上游正则表达，不能仅根据作者“等价”的注释认定完整 Unicode 情况都一致。生产接入需要显式离线资源策略和官方语料差分，不应依赖用户首次生成时联网取得词表。

narner 包的[manifest](https://github.com/narner/TiktokenSwift/blob/661c349ebdc5e90c29f855e8c19f8984d401863b/Package.swift)直接引用仓库内 XCFramework；本次克隆在二进制 checkout 阶段因本机没有 git-lfs 失败，文本文件可读。1.0.0 发行 ZIP 为 390,692,306 字节，这同样不是单架构应用安装增量。没有因此修改用户环境或安装 LFS。

## 性能证据与尚未测量的项目

OpenAI README 的 3–6 倍性能对比使用旧版本、GPT-2 和 1GB 文本，不应转述为当前 macOS 日报场景的速度保证。[上游基准说明](https://github.com/openai/tiktoken/blob/4e71bbe0c078468e00fefbf94b39849389f346e5/README.md)

社区 swift-tokenizers 作者在 M3 MacBook Pro 上比较 0.5.0 与 swift-transformers 1.3.2，报告 tokenization 4.5ms 对 29.1ms；这是特定版本和语料的作者基准，不是本项目实测，不能预测中文长会话峰值内存或 0.7.4 的性能。[基准与运行入口](https://github.com/DePasqualeOrg/swift-tokenizers/blob/7d67e1479e2f11226bddc800ff1a964228a602b2/README.md)

本轮没有测量最终链接体积、首次初始化耗时、长中文/代码混合文本吞吐、峰值内存或任务取消响应。后续可做独立临时原型，以官方 tiktoken 产生固定 token-ID 夹具，覆盖中文、英文、代码、JSON转义、emoji/组合字符、换行/空白、字面特殊-token文本和超长重复串。严格验证离线运行和首次加载无网络，再决定版本与集成方式。库许可证不自动涵盖任意模型 tokenizer 资源的许可；每份额外资源也要保留来源和许可证。

## Claude、未知中转与产品决策边界

Anthropic 旧[官方 TypeScript tokenizer](https://github.com/anthropics/anthropic-tokenizer-typescript/blob/4d75e64d32fe5cd2b5a24d954242f9fab12e8b4b/README.md)已归档，明确说明 Claude 3 起不准确。本轮未找到当前 Claude 的官方、可准确离线计数的 tokenizer 发行物；官方提供的是远程 [count_tokens](https://platform.claude.com/docs/en/build-with-claude/token-counting)，其结果也说明可能与最终使用量略有差别。不得为满足本地约束而把旧库或 o200k 伪装成当前 Claude 的准确计数。

调研时区分以下能力边界及备选路径；用户最终选择下节的统一参考估算，不把模型映射当作首版必需配置：

1. 常规路径优先本地真实 tokenizer；资源随应用版本固定打包，运行时不为计数外发正文、不自动下载 tokenizer。
2. encoding 映射元数据服务于估算，不构成模型选择白名单，继续允许完整自定义 endpoint/model。
3. 有可信匹配时使用相应 tokenizer；任意中转返回成功不能证明模型名称与底层 encoding 一致。
4. 无可信匹配时可选择“明确为近似的参考 encoding 估算”或“要求用户指定计数规则”；取多种参考 encoding 的最大计数也只是启发式，不能承诺上界。本轮不擅自恢复每字节 1 token 为已定方案。
5. 计数方法、encoding/资源版本和额外协议预留应纳入任务配置快照，使同一次生成的各批次一致。实际服务超限仍按既定失败规则处理，不自动重试；不能为塞进预算丢弃当天工作轮次。
6. 用户已确认每请求另留 1,024 token 给协议封装；这是产品参数，采用库并不会证明该数值对任意服务都充分。

### 已确认方案采用的统一参考估算

为避免维护不可信的中转模型名映射，首版统一用 `max(cl100k_base(text), o200k_base(text))` 作为各独立文本块的参考计数。结构化 schema 等实际发送的结构说明也计数，再另加每请求 1,024 token 协议封装预留，套用已确认的 20% 输入余量。这是产品选择，不要求用户理解模型与 encoding 的对应，也不新增模型白名单。字面 `<|endoftext|>` 等内容按普通文本处理，不能误当真实协议控制 token。这个公式仍不保证 Claude、其他 tokenizer 或中转服务的实际上界，不能描述为“保守到绝不会超限”；资源版本和算法在当次任务中固定。完整规则以决策票为准，不从已读库文档中虚构通用校准系数。

本轮 **没有构建 Swift 桥、没有验证 Rust 静态库在本工程的链接与签名、没有跑候选库差分测试**。上文保留调研时的选项与限制；用户已确认 tiktoken-rs 路线及完整估算契约。后续若集成验证失败，应显式报告并重新评估，不能静默改用另一计数方法。
