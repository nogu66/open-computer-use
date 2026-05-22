# OpenComputerUse
<a href="README.md">English</a>

**macOS 向け Computer Use** — すでにログイン済みの Chrome やネイティブアプリを、Accessibility API と合成入力で操作し、MCP stdio サーバーと CLI として公開します。

[Codex Computer Use](https://developers.openai.com/codex/app/computer-use) と同じ発想（CDP ではなく OS レベルの AX + CGEvent）を、Claude Code / Cursor / Codex など任意の MCP クライアントで使える形にしたものです。

| | Playwright / CDP | **open-computer-use (`ocu`)** |
|---|---|---|
| ログイン済み Chrome | 別プロファイルが多い | **そのまま操作** |
| Cookie / SSO / 拡張 | 消えがち | **維持** |
| 自動化検知 | `webdriver` 等 | **ブラウザ外なので該当なし** |
| 対応 OS | クロスプラットフォーム | **macOS 13+ のみ** |

## インストール（推奨）

最新の **Release バイナリ** を `~/.local/bin/ocu` に入れます。

```bash
curl -fsSL https://raw.githubusercontent.com/nogu66/open-computer-use/main/scripts/install.sh | bash
```

リポジトリを clone 済みの場合:

```bash
./scripts/install.sh              # 最新 Release（失敗時はソースビルド）
./scripts/install.sh --version v0.1.0
./scripts/install.sh --from-source  # SwiftPM のみ
```

`~/.local/bin` を PATH に追加してから MCP を接続:

```bash
claude mcp add open-computer-use -- $(which ocu)
```

## プラグインとしてインストール

**Claude Code**、**Codex**、**Cursor** 向けプラグイン（スキル + MCP 設定）も同梱しています。先にバイナリを入れてからプラグインを追加するのがおすすめです。

### Claude Code

```bash
/plugin marketplace add nogu66/open-computer-use
/plugin install open-computer-use@open-computer-use
/reload-plugins
```

`open-computer-use` スキルと MCP サーバー（`open-computer-use`）が同梱されます。

### Codex

```bash
codex plugin marketplace add nogu66/open-computer-use
# Codex のプラグインディレクトリから open-computer-use をインストール
```

### Cursor

このリポジトリを Cursor で開くと、以下が自動的に有効になります。

- MCP: [`.cursor/mcp.json`](.cursor/mcp.json)
- スキル: [`.cursor/skills/open-computer-use/SKILL.md`](.cursor/skills/open-computer-use/SKILL.md)

詳細: [examples/plugin-install.md](examples/plugin-install.md)

## クイックスタート（手動ビルド）

### 必要環境

- macOS 13 (Ventura) 以降
- ソースビルド: Swift 5.9+（Xcode 15+）
- `ocu` を起動する親プロセスへの **アクセシビリティ** 許可

### ビルド

```bash
git clone https://github.com/nogu66/open-computer-use.git
cd open-computer-use
./scripts/install.sh --from-source
ocu --version
```

### MCP 登録（手動）

```bash
claude mcp add open-computer-use -- $(which ocu)
# 開発用 checkout（初回 MCP 接続時に latest を自動インストール）:
claude mcp add open-computer-use -- ./scripts/mcp-server.sh
```

Claude Code を再起動すると `mcp__open-computer-use__list_apps` などのツールが使えます。

他クライアント向け設定: [examples/](examples/)

### CLI の例

```bash
ocu apps
ocu activate --bundle-id com.google.Chrome
ocu tree --bundle-id com.google.Chrome --depth 6
ocu click --bundle-id com.google.Chrome --query "検索"
```

MCP の疎通確認:

```bash
./scripts/smoke-test.sh
```

## 権限

| 権限 | 用途 |
|---|---|
| **アクセシビリティ** | AX ツリー、クリック、キー、メニュー |
| **画面収録** | `screenshot`（`screencapture` 利用時） |

親アプリ（Claude Code など）に付与してください。詳細: [docs/permissions.md](docs/permissions.md)

## MCP ツール一覧

| ツール | 概要 |
|---|---|
| `list_apps` | 起動中 GUI アプリ一覧 |
| `get_ax_tree` | 番号付き AX ツリー（テキスト） |
| `ax_tree_json` | JSON 形式の AX ツリー |
| `find_element` | 部分一致で要素検索 |
| `click_element` / `click_ref` | クエリまたは `@eN` でクリック |
| `activate` | 前面化（入力前に推奨） |
| `type_text` / `key_press` | 文字入力・キー送信 |
| `wait_for` | 要素出現までポーリング |
| `scroll` / `right_click` | スクロール・右クリック |
| `screenshot` | スクリーンショット |
| `menu` | メニューバー操作 |
| `clip_get` / `clip_set` | クリップボード |

詳細: [docs/tools.md](docs/tools.md)

## エージェント向け推奨フロー

1. `list_apps` で `bundle_id` を特定
2. `activate` でフォーカス
3. `get_ax_tree` / `ax_tree_json` で UI を把握
4. `click_element` 等で操作
5. 必要なら `wait_for` / `screenshot`

## アーキテクチャ

```
エージェント ── MCP stdio ──► ocu (Swift)
                              ├── AXUIElement
                              ├── CGEvent
                              └── screencapture
                                    ▼
                            ユーザーが開いた実アプリ
```

[docs/architecture.md](docs/architecture.md)

## 開発

```bash
swift build && swift test
```

[CONTRIBUTING.md](CONTRIBUTING.md)

## ライセンス

MIT — [LICENSE](LICENSE)
