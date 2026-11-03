# ZCHGSB 项目规则（opencode 自动加载）

## 开工前（必做）
1. 先读 `zchgsb/docs/STATUS.md` —— 当前目标、已完成、下一步、关键文件。
2. 只有 STATUS.md 不够用时，才去翻历史会话。

## 阶段性工作结束时（必做）
1. 更新 `zchgsb/docs/STATUS.md`（已完成 / 下一步 / 关键文件 / 坑）。
2. 靠 STATUS.md 交接，不要把历史消息重发一遍。

## 项目结构
- `zchgsb/src/` —— abapGit 序列化的 ABAP 对象（真正要改的东西）
- `zchgsb/docs/` —— 设计文档、状态（不参与 abapGit 同步）
- `.abapgit.xml` —— abapGit 配置，起始目录 `/zchgsb/src/`

## 系统红线
- 唯一相关系统：**S4H（client 100）**。ER1 是老的 ECC 系统，与本项目无关，不要连接、不要查询。
- **本地 git 是唯一真源**；系统对象只通过 **abapGit 导入/导出**，不在 SE80 里手工改。
- MCP（abap-adt-mcp）默认**只读**：查表、看源码、核对字段名、验证对象是否存在。
- 禁止用 MCP 的 createObject / deleteObject / 写源码 / 激活 / createTransport 直接改系统；确需执行必须先得到主人同意。
- 导入前先 `git commit`，保证任何系统改动都能回滚到某个提交。

## 约定
- 只动 `zchgsb/src/` 下的 ABAP 文件；不要改 `.abapgit.xml` 的语言配置
- 读大文件先用 `grep`/`head` 定位，别整文件读进来
- FM / Class / 字段名必须先核实存在，不得按名字推断
- 回复保持简短
- 需要大量探索/试错的工作，先写进 `zchgsb/docs/` 再动手
