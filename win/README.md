# win-computer-use (`wcu`)

`win-computer-use` は、[`open-computer-use`](https://github.com/nogu66/open-computer-use) の Windows 版に相当する実験的実装です。macOS の Accessibility API / CGEvent による実アプリ操作を、Windows の **Microsoft UI Automation（UIA）** と **Win32入力合成** に置き換え、MCP stdio サーバーおよびCLIとして利用できるようにします。

> この実装は Windows 上でビルド・実行することを前提にした C# / .NET 8 プロジェクトです。Linuxサンドボックス上では Windows UI Automation アセンブリが利用できないため、実機動作確認は Windows 側で行ってください。

## 目的

ブラウザのDOMやPlaywrightではなく、**ユーザーが実際に開いているログイン済みアプリ** を対象に、アクセシビリティツリーの読み取り、要素検索、クリック、キー入力、スクリーンショット、クリップボード操作を行います。Chrome、Edge、Slack、Notepad、Office、WPF/WinUI/Win32系アプリなどを同一の操作面で扱うことを目指しています。

| 機能 | 実装方式 |
|---|---|
| UIツリー取得 | `System.Windows.Automation` |
| 要素検索 | UIAの `Name`、`AutomationId`、`ClassName`、`ValuePattern`、`ControlType` の部分一致 |
| クリック | `InvokePattern` / `SelectionItemPattern` / `ExpandCollapsePattern` 優先、不可なら座標クリック |
| キー入力 | `System.Windows.Forms.SendKeys` |
| テキスト入力 | クリップボード設定後 `Ctrl+V` |
| スクロール・右クリック | Win32 `mouse_event` |
| スクリーンショット | `Graphics.CopyFromScreen` |
| アプリ列挙・前面化 | Win32 top-level window enumeration / `SetForegroundWindow` |
| MCP | JSON-RPC 2.0 over stdio |

## ビルド

Windows 11 / Windows 10 と .NET 8 SDK が入った環境で以下を実行します。

```powershell
dotnet build -c Release
```

生成物は通常、次の場所に作成されます。

```text
bin\Release\net8.0-windows\wcu.exe
```

単一ファイルとして配布したい場合は、以下のように発行できます。

```powershell
dotnet publish -c Release -r win-x64 --self-contained false /p:PublishSingleFile=true
```

## CLIの使い方

`bundle_id` という引数名は参照実装との互換性のために残していますが、Windows版では次のいずれかを指定します。

| 指定方法 | 例 | 意味 |
|---|---|---|
| プロセス名 | `chrome`、`notepad` | `Process.ProcessName` の完全一致 |
| PID | `pid:1234` | 対象プロセスID |
| ウィンドウタイトル | `Untitled - Notepad` | top-level window title の部分一致 |

```powershell
wcu apps
wcu activate --bundle-id chrome
wcu tree --bundle-id chrome --depth 8
wcu find --bundle-id chrome --query "Search"
wcu click --bundle-id chrome --query "New tab"
wcu key --key l --mods ctrl
wcu type --text "https://example.com"
wcu key --key enter
wcu shot --bundle-id chrome
wcu clip set --text "hello"
wcu clip get
```

## MCPサーバーとして使う

引数なし、または `serve` で起動すると、標準入出力で MCP JSON-RPC サーバーとして動作します。

```powershell
wcu serve
```

MCPクライアント側の設定例は `examples/mcp.json` を参照してください。

## 実装済みツール

| MCP tool | CLI | 説明 |
|---|---|---|
| `list_apps` | `wcu apps` | 表示中のトップレベルウィンドウを持つGUIアプリを列挙 |
| `get_ax_tree` | `wcu tree` | UIAツリーを `@eN` 付きテキストで出力 |
| `ax_tree_json` | `wcu tree --json` | UIAツリーをJSONで出力 |
| `find_element` | `wcu find` | UI要素を部分一致検索 |
| `click_element` | `wcu click` | 検索した要素をクリックまたはInvoke |
| `click_ref` | MCPのみ | 直近ツリーの `@eN` をクリック |
| `activate` | `wcu activate` | 対象ウィンドウを前面化 |
| `type_text` | `wcu type` | テキスト貼り付け入力 |
| `key_press` | `wcu key` | キー送信 |
| `wait_for` | `wcu wait` | 要素出現待ち |
| `scroll` | `wcu scroll` | スクロール |
| `right_click` | `wcu rclick` | 右クリック |
| `screenshot` | `wcu shot` | PNGスクリーンショット |
| `menu` | `wcu menu` | MenuItem検索によるメニュー操作のベストエフォート実装 |
| `clip_get` / `clip_set` | `wcu clip get/set` | クリップボード操作 |

## 制約

Windows UI Automation はアプリ側のアクセシビリティ対応に依存します。標準コントロール、WPF、WinUI、UWPでは比較的良好に動作しますが、Electron、Chromium内のWebコンテンツ、ゲーム、独自描画UIでは取得できる要素情報が限定されることがあります。

また、**管理者権限で起動されたアプリを通常権限の `wcu` から操作することはできません**。昇格アプリを操作する場合は `wcu` も管理者権限で起動してください。ロック画面、別ユーザーセッション、セッション0サービスのUI操作も対象外です。

## 今後の改善候補

初期版では標準ライブラリ中心で実装しています。実運用に向けては、`SendKeys` からより低レベルな `SendInput` への完全移行、UIA CacheRequest による高速化、Chrome/EdgeのWebコンテンツ補助、OCR統合、座標クリック専用ツール、署名付きリリース、PowerShellインストーラを追加するとよいです。
