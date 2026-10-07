# 取证入口表

按「实测是否可用」标注。`✅` 可用、`⛔` 受阻、`⚠️` 可用但需注意。样本为中国境内公司 + X 平台线索；其他平台与辖区的对应入口需另找。

## 1. 线索载体（社交贴文 / 网页 / 截图）

| 入口 | 状态 | 说明 |
|---|---|---|
| `x.com/<user>/status/<id>` 直抓 | ⛔ | fetch failed，反爬。**不可据此判定为假** |
| `api.fxtwitter.com/<user>/status/<id>` | ✅ | 返回 JSON：作者、粉丝、认证、正文、`created_at`、互动数、媒体 URL |
| `api.vxtwitter.com/<user>/status/<id>` | ⚠️ | 独立第二源，字段略有差异。**本次实测曾返回 403**，脚本会降级为单源 |
| 时间戳反解 | ✅ | `ts = (id >> 22) + 1288834974657`（毫秒），与 `created_at` 比对 |
| 附件图 `pbs.twimg.com/media/<file>?name=orig` | ✅ | `Invoke-WebRequest` 下载后用 `read_image` 直读。**关键宣称常在图内** |

**注意**：镜像 API 的互动数是快照，两源会有小差异（本次 404 vs 423 赞），属正常。

## 2. 主体官方一手源

| 入口 | 状态 | 能拿到什么 |
|---|---|---|
| `/robots.txt`、`/sitemap.xml` | ✅ | 全站页面清单，比爬首页可靠（首页可能间歇超时） |
| `/about`、`/contact` | ✅ | 办公地址、联系人、电话、邮箱域名 |
| `/changelog` | ✅ | 版本数与发布时间＝工程真实性 |
| `/status`、`/reset` 等运维页 | ✅ | **真实运营数字**（账号数、重置次数），最硬的一类自曝证据 |
| 页脚 | ✅ | ICP 备案号（缺失＝合规瑕疵线索） |
| 首页 | ⚠️ | 多次 `fetch failed` / 30s 超时，改用子页 |

## 3. 身份链

| 入口 | 状态 | 说明 |
|---|---|---|
| 技术大会讲师页 | ✅ | 姓名 + 职务 + **主体全称** + 演讲排期。本人自己提交 |
| Discourse 论坛帖（`/t/<id>`） | ✅ | 本人自述团队分工、技术细节、失败经历；`/t/<id>.json` 可读结构化数据 |
| 个人站、GitHub 主页 | ✅ | 本名、项目史、**可能暴露第二个公司主体** |
| 专业奖项档案 | ✅ | 学历与获奖，独立于自述 |
| 权威媒体（证券报、科技日报系） | ✅ | 一次给出全部创始人姓名与身份 |

## 4. 主体登记与合规（中国境内公司路径）

| 入口 | 状态 | 说明 |
|---|---|---|
| 天眼查公司页 | ⛔ | HTTP 418 / 登录壳页 |
| 爱企查 | ⛔ | 验证跳转页；未收录时返回 `total:0` |
| 启信宝 | ⛔ | 403 验证码 |
| 企查查 | ⛔ | 加密 JS 反爬体 |
| 百度百科 | ⛔ | 403「百度安全验证」 |
| 国家企业信用信息公示系统 | ⛔ | 重 JS，未取到 |
| 360 搜索 `/s?q=<公司全称>` 企业信息卡 | ✅ | **本次关键突破**：成立日期、法人、注册资本、注册地址、主要人员、经营范围摘要 |
| 搜狗企业信息卡 | ✅ | 与 360 同源，可交叉验证 |
| `whois.nic.ai` 协议直查（.ai 域名） | ✅ | 域名创建日期、注册商、注册人国别 |
| 名录集等工商聚合站 | ⚠️ | 部分公司有社保人数等字段 |
| Wayback CDX / availability API | ⛔ | 本次 CDX 返回空数组、availability 429 |

**判读要点**：注册地址含「入驻 XX 商务秘书有限公司」即地址托管；同名主体必须按统一社会信用代码区分；注意抢注时间点与事件时间的关系。

## 5. 产品真实性

| 入口 | 状态 | 说明 |
|---|---|---|
| 前端 JS / `release-config.js` | ✅ | 找 `PRODUCTION_API_ORIGIN` 与 releases 端点 |
| `api.<domain>/api/v1/.../releases/download?channel=stable` | ✅ | 版本、发布时间、文件大小、sha256 |
| 完整下载 + `Get-FileHash` | ✅ | 与官方 sha256 逐字节比对 |
| `Get-AuthenticodeSignature` | ✅ | 判断代码签名；**必须用完整文件**，截断会看到假象 |
| HTTPS 证书 | ✅ | 用 `curl`/`Invoke-WebRequest` 看签发者与有效期。**与代码签名是两件事** |
| 电商/众筹渠道检索 | ✅ | 无价格、无购买按钮、无预售＝尚未商业化 |

## 6. 口碑与生态

| 入口 | 状态 | 说明 |
|---|---|---|
| B 站 `api.bilibili.com/x/web-interface/card?mid=` | ⚠️ | 可用，但会返回 `-352` 风控；需先确认是官方号还是个人号 |
| Discourse `/t/<id>.json` | ✅ | 阅读、点赞、回复数，判断真实热度 |
| sov2ex / V2EX 全网搜 | ✅ | 开发者社区是否零讨论 |
| 抖音短链 | ⛔ | 未解析成功 |
| 微信公众号文章 | ⛔ | 「环境异常」验证页 |
| 知乎专栏 | ⛔ | 403 |
| 小红书 / 即刻 / 少数派 | ⚠️ | 未查到，可能是真没有，也可能未检索到 |

## 7. 机构背书核实

| 对象 | 怎么核 |
|---|---|
| 大赛奖项 | 主办方官网奖项/奖金页 + 有编辑责任的媒体；政府网站转载更硬 |
| 孵化器 | 机构官网「在孵团队」「公示公告」「最新消息」「学院百科」逐页检索公司名 |
| 投资机构 | portfolio / 校友页 + 该期路演项目完整名单 |
| 关键区分 | **「入营 / 孵化」≠「获投」**。例：某机构统一为「30 万美元换 7% 股权」，若有投资，工商股东名册会留痕 |

## 8. 常用命令

```powershell
# 推文时间戳反解 + 双镜像比对（脚本为 UTF-8 with BOM，兼容 PS 5.1 与 7）
powershell -File scripts/check-claim.ps1 -Url "https://x.com/<user>/status/<id>"

# 安装包哈希与签名（必须用完整文件，截断会看到 PE 证书表假象）
powershell -File scripts/check-claim.ps1 -File ".\app.exe" -ExpectedSha256 "<官方 sha256>"

# 官网全站清单
Invoke-RestMethod "https://<domain>/sitemap.xml"

# 域名年龄
#   whois.nic.ai 协议直查（.ai 域名），或 whois.chinaz.com/<domain>
```

**Windows PowerShell 5.1 的两个坑**（本环境实测）：
1. `.ps1` 若无 UTF-8 BOM，中文会被按 ANSI 解码并撕裂字符串，报「意外的标记」语法错误 → 保存为 **UTF-8 with BOM**。
2. `Invoke-RestMethod` 不按 UTF-8 解码 JSON，中文正文变乱码 → 用 `Invoke-WebRequest` 取 `RawContentStream` 后 `[System.Text.Encoding]::UTF8.GetString()`。
