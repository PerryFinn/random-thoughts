# 合成 stdio App Server 替身

仅供隔离集成测试。所有身份、正文、目录和诊断标记均人工构造；没有真实会话或凭据，不读私有 JSONL。wire 依据 #4 指向的 `openai/codex@66919805ea080053d1933b6b43afeb0d8bf70c91` 的 Thread／Turn／ThreadItem schema，以及 [官方初始化与稳定读取说明](https://learn.chatgpt.com/docs/app-server)。

替身只接受本次隔离临时根目录中的 `CODEX_HOME`，并严格检查 `app-server` 参数、初始化、禁用实验能力、当前／归档列表和 `includeTurns`。fixture.json 选择固定故障场景；独立临时文件只用于合成夹具、进程身份和明确就绪屏障，脚本退出清理。不运行 Codex、AI、网络或应用入口。
