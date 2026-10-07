<#
.SYNOPSIS
    核实一条 X/Twitter 链接的真实性，或校验一个安装包的哈希与代码签名。

.DESCRIPTION
    模式一（-Url）：从推文 URL 反解 snowflake 时间戳，并请求两个互相独立的镜像 API
    （fxtwitter / vxtwitter），把 API 返回的 created_at 与反解时间比对。两者一致即说明
    该 URL 不是编造的（x.com 本身反爬，抓不动不代表是假链接）。

    模式二（-File）：计算文件 SHA-256（可与官方清单比对），并检查 Authenticode 代码签名。
    注意：判断签名必须用完整文件；截断文件会看到 PE 证书表假象。

.EXAMPLE
    powershell -File scripts/check-claim.ps1 -Url "https://x.com/<user>/status/<id>"

.EXAMPLE
    powershell -File scripts/check-claim.ps1 -File ".\app.exe" -ExpectedSha256 "<官方清单里的 sha256>"

.NOTES
    兼容 Windows PowerShell 5.1 与 PowerShell 7。本文件必须以 UTF-8 with BOM 保存，
    否则 5.1 会按 ANSI 解析，中文字符串会被撕裂并导致语法错误。
    某个镜像返回 403 属常见情况，脚本会降级为单源并给出提示。
#>
[CmdletBinding(DefaultParameterSetName = 'Url')]
param(
    [Parameter(ParameterSetName = 'Url', Mandatory = $true, Position = 0)]
    [string]$Url,

    [Parameter(ParameterSetName = 'File', Mandatory = $true)]
    [string]$File,

    [Parameter(ParameterSetName = 'File')]
    [string]$ExpectedSha256
)

$ErrorActionPreference = 'Stop'

# X 的 snowflake 纪元（毫秒）
$TwitterEpochMs = 1288834974657

function ConvertFrom-Snowflake {
    param([Parameter(Mandatory = $true)][string]$Id)

    if ($Id -notmatch '^\d{15,20}$') { throw "不是合法的 snowflake id: $Id" }
    $ms = ([long]$Id -shr 22) + $TwitterEpochMs
    # 显式构造 UTC 纪元：New-TimeSpan 在 Windows PowerShell 5.1 没有 -Milliseconds 参数
    $epoch = [datetime]::SpecifyKind([datetime]'1970-01-01T00:00:00', [System.DateTimeKind]::Utc)
    return $epoch.AddMilliseconds([double]$ms)
}

function Get-TweetMirror {
    param(
        [Parameter(Mandatory = $true)][string]$User,
        [Parameter(Mandatory = $true)][string]$Id
    )

    $sources = @{
        fxtwitter = "https://api.fxtwitter.com/$User/status/$Id"
        vxtwitter = "https://api.vxtwitter.com/$User/status/$Id"
    }

    $results = foreach ($name in $sources.Keys) {
        try {
            # Windows PowerShell 5.1 的 Invoke-RestMethod 不按 UTF-8 解码 JSON 正文，
            # 中文会变乱码；显式按字节取回再解码。
            $resp = Invoke-WebRequest -Uri $sources[$name] -TimeoutSec 30 -UseBasicParsing -Headers @{ 'User-Agent' = 'Mozilla/5.0' }
            if ($resp.RawContentStream) {
                $json = [System.Text.Encoding]::UTF8.GetString($resp.RawContentStream.ToArray())
            }
            else {
                $json = $resp.Content
            }
            $raw = $json | ConvertFrom-Json
            if ($name -eq 'fxtwitter') {
                $tweet = $raw.tweet
                [pscustomobject]@{
                    source     = $name
                    author     = $tweet.author.screen_name
                    name       = $tweet.author.name
                    followers  = $tweet.author.followers
                    verified   = $tweet.author.verification.verified
                    created_at = $tweet.created_at
                    likes      = $tweet.likes
                    retweets   = $tweet.retweets
                    replies    = $tweet.replies
                    views      = $tweet.views
                    text       = ($tweet.text -replace '\s+', ' ')
                    media      = ($tweet.media.all | ForEach-Object { $_.url }) -join ' '
                }
            }
            else {
                [pscustomobject]@{
                    source     = $name
                    author     = $raw.user_screen_name
                    name       = $raw.user_name
                    followers  = $null
                    verified   = $null
                    created_at = $raw.date
                    likes      = $raw.likes
                    retweets   = $raw.retweets
                    replies    = $raw.replies
                    views      = $null
                    text       = ($raw.text -replace '\s+', ' ')
                    media      = ($raw.mediaURLs) -join ' '
                }
            }
        }
        catch {
            Write-Warning "镜像 $name 请求失败：$($_.Exception.Message)"
        }
    }

    return $results
}

if ($PSCmdlet.ParameterSetName -eq 'Url') {
    if ($Url -notmatch '/(?<user>[^/]+)/status/(?<id>\d+)') {
        throw "无法从 URL 解析出用户名与 status id：$Url"
    }
    $user = $Matches['user']
    $id = $Matches['id']

    $decoded = ConvertFrom-Snowflake -Id $id
    Write-Host ''
    Write-Host "URL        : $Url"
    Write-Host "用户 / ID  : $user / $id"
    Write-Host ("反解时间   : {0:yyyy-MM-dd HH:mm:ss} UTC" -f $decoded)
    Write-Host ''

    $mirrors = @(Get-TweetMirror -User $user -Id $id)
    if ($mirrors.Count -eq 0) {
        Write-Warning '两个镜像都不可用，无法交叉验证。请勿据此判定链接为假。'
        exit 2
    }

    $mirrors | Format-List source, author, name, followers, verified, created_at, likes, retweets, replies, views, text, media | Out-String | Write-Host

    Write-Host '一致性检查'
    Write-Host '----------'
    $ok = $true
    foreach ($m in $mirrors) {
        if ($m.author -and $m.author -ne $user) {
            Write-Warning "  [$($m.source)] 作者与 URL 不一致：$($m.author) vs $user"
            $ok = $false
        }
        if ($m.created_at) {
            # 镜像返回的是 Twitter 经典格式：Wed Oct 07 08:57:31 +0000 2026
            $apiTime = $null
            $formats = @('ddd MMM dd HH:mm:ss zzz yyyy', 'ddd MMM dd HH:mm:ss \Z yyyy')
            foreach ($fmt in $formats) {
                try {
                    $apiTime = [datetime]::ParseExact($m.created_at, $fmt, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal)
                    break
                }
                catch { $apiTime = $null }
            }
            if ($null -eq $apiTime) {
                Write-Warning "  [$($m.source)] 无法解析 created_at：$($m.created_at)"
                $ok = $false
                continue
            }
            $drift = [math]::Abs(($apiTime - $decoded).TotalSeconds)
            if ($drift -le 2) {
                Write-Host ("  [{0}] created_at 与反解时间一致（偏差 {1:N1}s）" -f $m.source, $drift) -ForegroundColor Green
            }
            else {
                Write-Warning ("  [{0}] created_at 与反解时间偏差 {1:N1}s，需人工确认" -f $m.source, $drift)
                $ok = $false
            }
        }
    }
    if ($mirrors.Count -ge 2) {
        Write-Host "  两个独立镜像均返回该 id 的数据（$($mirrors.Count) 个来源）" -ForegroundColor Green
    }
    else {
        Write-Host "  仅 1 个镜像可用，交叉验证不足；换网络或稍后重试另一个镜像" -ForegroundColor Yellow
    }
    Write-Host ''
    if ($ok) { Write-Host '结论：该 URL 指向一条真实存在的公开推文。' -ForegroundColor Green }
    else { Write-Host '结论：存在不一致项，见上方警告。' -ForegroundColor Yellow }
    if ($mirrors[0].media) {
        Write-Host '提示：该推文含媒体，招聘/公告类关键宣称常只存在于图片内，请下载后直读。'
    }
    exit 0
}

# 模式二：安装包校验
if (-not (Test-Path -LiteralPath $File)) { throw "文件不存在：$File" }
$item = Get-Item -LiteralPath $File
$hash = (Get-FileHash -LiteralPath $File -Algorithm SHA256).Hash
$sig = Get-AuthenticodeSignature -LiteralPath $File

Write-Host ''
Write-Host "文件        : $($item.FullName)"
Write-Host ("大小        : {0} bytes" -f $item.Length)
Write-Host "SHA-256     : $hash"
if ($ExpectedSha256) {
    if ($hash -eq $ExpectedSha256.Trim().ToUpperInvariant()) {
        Write-Host '哈希比对    : MATCH（与官方清单逐字节一致）' -ForegroundColor Green
    }
    else {
        Write-Host "哈希比对    : MISMATCH（期望 $($ExpectedSha256.Trim().ToUpperInvariant())）" -ForegroundColor Red
    }
}
Write-Host "签名状态    : $($sig.Status) / $($sig.SignatureType)"
if ($sig.SignerCertificate) {
    Write-Host "签名主体    : $($sig.SignerCertificate.Subject)"
}
else {
    Write-Host '签名主体    : 无（Windows 会显示「未知发布者」并被 SmartScreen 拦截）' -ForegroundColor Yellow
}
Write-Host ''
Write-Host '提示：HTTPS 证书正常与安装包已代码签名是两件事，请分别表述。'
