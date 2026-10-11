# 合成 stdio App Server 替身

仅供隔离集成测试。所有身份、正文、目录和诊断标记均人工构造；没有真实会话或凭据，不读私有 JSONL。wire 依据 #4 指向的 `openai/codex@66919805ea080053d1933b6b43afeb0d8bf70c91` 的 Thread／Turn／ThreadItem schema，以及 [官方初始化与稳定读取说明](https://learn.chatgpt.com/docs/app-server)。

替身只接受本次隔离临时根目录中的 `CODEX_HOME`，并严格检查 `app-server` 参数、初始化、禁用实验能力、当前／归档列表和 `includeTurns`。fixture.json 选择固定故障场景；独立临时文件只用于合成夹具、进程身份和明确就绪屏障，脚本退出清理。不运行 Codex、AI、网络或应用入口。

#26 的 `scan` 场景以 v2 `Thread`／`Turn` 的合成 wire 构造分页列表与完整 `itemsView`，严格核对显式 `sourceKinds`、空 `modelProviders`、游标和只读方法。日期包含 2026 年洛杉矶 DST 及午夜；正文、元数据、未知阶段和内部来源各用独立合成标记。固定失败场景验证列表范围不全、具体读取失败、必要 schema、透明重启次数及取消。空锁文件验证由独立 `ReportStorageProbe` 持有生产 `CodexScanLock`，FIFO／stdin 作为就绪与释放屏障；不终止其他测试或用户进程。临时 `launches`／`pid` 仅证明合成子进程次数与回收，不是产品诊断出口。
