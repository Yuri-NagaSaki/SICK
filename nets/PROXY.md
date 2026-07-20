# NETS 短链 / 反代 URL 清单

你这边脚本和页面自理时，按下面路径做 **反代 / 重写** 即可。  
源站以 GitHub raw 或你的静态部署根目录为准（示例用 `origin`）。

## 建议公开 URL

| 用途 | 公开 URL（两套短域） | 反代到（二选一或都配） |
|------|----------------------|------------------------|
| **脚本** | `https://catbash.net/nets` | `…/nets/nets.sh` 或 raw 见下 |
| **脚本** | `https://ba.sh/nets` | 同上 |
| **页面** | `https://catbash.net/nets/` 或 `https://catbash.net/nets.html` | `…/nets/index.html`（或你的页面路径） |
| **页面** | `https://ba.sh/nets/`（可选） | 同上 |
| **端点 JSON**（可选） | `https://catbash.net/nets/endpoints.json` | `…/nets/endpoints.json` |
| **端点 Markdown**（可选） | `https://catbash.net/nets/endpoints.md` | `…/nets/endpoints.md` |

### GitHub raw 源（若直接反代仓库文件）

| 公开路径 | 建议 origin |
|----------|-------------|
| `/nets` | `https://raw.githubusercontent.com/Yuri-NagaSaki/SICK/main/nets/nets.sh` |
| `/nets/` 或 `/nets.html` | 静态站上的 `nets/index.html` / `nets.html`（需你放页面；仓库目前只有 README） |
| `/nets/endpoints.json` | `https://raw.githubusercontent.com/Yuri-NagaSaki/SICK/main/nets/endpoints.json` |
| `/nets/endpoints.md` | `https://raw.githubusercontent.com/Yuri-NagaSaki/SICK/main/nets/endpoints.md` |

### 与 SICK 对齐的已有短链（对照）

| 公开 | 目标 |
|------|------|
| `https://catbash.net/sick` | `hardware_info.sh` |
| `https://ba.sh/sick` | 你现有的 sick 反代（保留） |
| `https://catbash.net/hardware_info.sh` | 直链脚本文件 |

## Cloudflare / 反代注意

1. **`/nets` 不要 302 到 HTML**  
   `curl -sL https://catbash.net/nets | bash` 需要 **200 + 脚本正文**（`Content-Type: text/plain` 或 `application/x-sh`），与 `/sick` 相同。

2. **`/nets/`（带斜杠）可以出页面**  
   浏览器用；脚本短链用 **无尾斜杠** `/nets`，避免拿到 index HTML。

3. **CORS**  
   仅 curl/bash 不需要 CORS；若页面 `fetch('endpoints.json')` 跨域，再开 CORS。

4. **缓存**  
   脚本建议短缓存或 `max-age=300`，改 endpoints 后易生效。

## 用户侧一键命令（反代生效后）

```bash
# catbash
curl -sL https://catbash.net/nets | bash
curl -sL https://catbash.net/nets | bash -s -- -r
curl -sL https://catbash.net/nets | bash -s -- --region apac

# ba.sh（需你配置同样反代）
curl -sL https://ba.sh/nets | bash
curl -sL https://ba.sh/nets | bash -s -- -r
```

## 最小必配（优先）

只要两天内能跑起来，至少配：

1. `https://catbash.net/nets` → `nets/nets.sh`  
2. `https://ba.sh/nets` → 同一脚本  
3. （可选）`https://catbash.net/nets/` → 说明页  

`endpoints.json` 已打进仓库；脚本默认读**同目录** JSON。若只反代 `nets.sh` 单文件、不挂 JSON，需改脚本为内嵌列表或再反代：

- `https://catbash.net/nets/endpoints.json`
