# entity-due-diligence

判断一个主体或一条宣称是否可信的 agent skill。主体可以是公司、机构、项目或个人；宣称可以是招聘、融资、获奖、资质、机构背书或产品能力。

An agent skill for entity and claim due diligence: turn a pile of claims into a verifiable checklist, gather evidence from first-party and public-registry sources, and deliver a report that separates **confirmed**, **wording inflated**, and **unverified**.

## 它解决什么问题

宣称的密度远高于可核实度。一条招聘图里可能同时塞了岗位、薪资、机构背书、投资方，其中一部分是真的、一部分是措辞升级、一部分查无实据。这个 skill 的做法是把宣称拆成表，逐条落到证据上，并给出可复核的原文摘录。

## 适用场景

| 适合 | 不适合 |
|---|---|
| 收到招聘/融资/获奖/资质消息，要判断真假与含金量 | 需要法律意见、财务审计或专业鉴定 |
| 入职、签约、采购、合作、投资前摸对方底细 | 对方内部资料已齐备 |
| 核实机构背书、大赛奖项、孵化与投资宣称 | 付费数据库级别的完整股权穿透 |
| 一条推文/链接/截图及其附件图真伪 | 必须实地走访或访谈才能确认的事项 |
| 某主体是否真实存在、是否与同名主体混淆 | 纯技术选型或产品能力评估 |

## 安装

按 skill 目录约定放置即可（DSH 扫描 `<项目根>/.agents/skills/` 与 `~/.agents/skills/`；Claude Code 用 `~/.claude/skills/`）：

```bash
git clone https://github.com/TCOTC/entity-due-diligence.git ~/.agents/skills/entity-due-diligence
```

## 结构

```
SKILL.md                        主流程：0–8 步 + 7 条铁律 + 落地行动清单
references/source-playbook.md   取证入口表：哪些入口可用、哪些被反爬挡住、绕行方式
references/pitfalls.md          15 条陷阱：错误做法 → 识别方法
scripts/check-claim.ps1         推文时间戳反解 + 双镜像比对；安装包哈希与签名校验
```

## 用法

```powershell
# 核实一条社交平台链接（反解 snowflake 时间戳 + 双镜像交叉验证）
powershell -File scripts/check-claim.ps1 -Url "https://x.com/<user>/status/<id>"

# 校验安装包：与官方清单比对 SHA-256，并检查 Authenticode 代码签名
powershell -File scripts/check-claim.ps1 -File ".\app.exe" -ExpectedSha256 "<官方 sha256>"
```

脚本兼容 Windows PowerShell 5.1 与 PowerShell 7。两个平台约束值得记住：

- 脚本文件本身必须是 **UTF-8 with BOM**，否则 5.1 会按 ANSI 解析中文并触发语法错误。
- `SKILL.md` 的 frontmatter 反过来**不能**带 BOM，否则首行不等于 `---`，skill 会被静默跳过。

## 七条铁律

1. 没有原文摘录的结论等于没有结论——每条都要 URL + 原文引用，搜索结果标题不算原文。
2. 「未查到」是合法结论，且不等于「没有风险」；取证受阻时如实说明，不填推测。
3. 信息源分四级并显式标注：官方 > 媒体 > 社区 > 自媒体。
4. 宣称口径要逐字比对，用词差异本身就是证据（「孵化」被写成「投资」即为一例）。
5. 反爬是常态，换入口比死磕一个站有效。
6. 先锁定唯一标识再谈其他——同名是最常见的污染源。
7. 主代理必须亲自复核最吃重的 2–3 条，复核失败要如实标注。

## 关于案例

本 skill 提炼自一次真实调查，但**文中所有案例细节均已去标识化**：不含真实主体名、人员姓名、联系方式、账号 ID 与可反查的精确数字。仓库内不含任何个人数据。

## 维护

本 skill 鼓励**就地维护**：使用中发现新陷阱、入口状态变化、脚本失效或触发不准，直接改对应文件并提交。完整的改动纪律见 `SKILL.md` 的「自我维护」一节，其中最关键的两条是：

- **只写实测过的内容**，无法验证的标注为「未实测」或写成 TODO，不伪装成已验证。
- **不得写入真实主体的名称、人员姓名、联系方式与可识别数字**——这个仓库是公开的。

## 许可

MIT
