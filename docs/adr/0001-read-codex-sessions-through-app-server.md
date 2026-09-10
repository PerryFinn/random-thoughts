# 通过用户安装的 Codex App Server 读取本机会话

工作日报只通过用户安装的 Codex 可执行文件，以操作级 stdio App Server 的稳定 `thread/list` 与 `thread/read(includeTurns)` 接口读取本机会话；应用不捆绑或更新 Codex，也不把私有 JSONL 当作备用路径。

兼容性以真实能力检查为准，版本号仅用于诊断；首版一次只解析一个明确的数据源，并以显式的扫描完整性与可用性状态换取公开协议边界、可追溯的数据源身份和可解释的升级失败。
