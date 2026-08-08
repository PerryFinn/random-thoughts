# 领域文档

本文件说明工程技能在探索代码库时应如何读取领域文档。

## 开始探索前读取

- 如果根目录存在 `CONTEXT.md`，读取它；或
- 如果根目录存在 `CONTEXT-MAP.md`，读取它指向的、与当前主题相关的各个 `CONTEXT.md`。
- 读取与即将处理的代码区域有关的 `docs/adr/` 中的 ADR。

如果这些文件不存在，静默继续。不要提示缺失，也不要建议提前创建；`/domain-modeling`（通过 `/grill-with-docs` 和 `/improve-codebase-architecture` 进入）会在实际解决术语或决策时按需创建它们。

## 文件结构

单上下文仓库（大多数仓库）：

```text
/
├── CONTEXT.md
├── docs/adr/
│   ├── 0001-event-sourced-orders.md
│   └── 0002-postgres-for-write-model.md
└── src/
```

多上下文仓库（根目录存在 `CONTEXT-MAP.md` 时）：

```text
/
├── CONTEXT-MAP.md
├── docs/adr/                          ← 系统级决策
└── src/
    ├── ordering/
    │   ├── CONTEXT.md
    │   └── docs/adr/                  ← 上下文级决策
    └── billing/
        ├── CONTEXT.md
        └── docs/adr/
```

## 使用术语表中的词汇

当输出中出现领域概念（例如 issue 标题、重构提案、假设或测试名称）时，使用 `CONTEXT.md` 中定义的术语。不要使用术语表明确避免的同义词。

如果需要的概念尚未出现在术语表中，这是一个信号：要么项目并不使用该概念（应重新考虑），要么领域文档存在真实缺口（应记录给 `/domain-modeling`）。

## 标记 ADR 冲突

如果输出与现有 ADR 冲突，应明确指出，不要静默覆盖：

> 与 ADR-0007（event-sourced orders）冲突——但值得重新打开，因为……
