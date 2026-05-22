# Windows版 open-computer-use 相当実装の設計方針

参照リポジトリ `nogu66/open-computer-use` は、macOS の **Accessibility API（AXUIElement）**、**CGEvent**、`screencapture` を組み合わせ、実ユーザーが開いているアプリを MCP stdio サーバーおよび CLI から操作できるようにする実装である。Windows 版では、これに対応する中核として **Microsoft UI Automation（UIA）** を採用し、入力合成には Windows の `SendInput`、スクリーンショットには .NET の `System.Drawing` / Win32 ウィンドウ矩形取得を使う。

| macOS実装 | Windows版の対応方針 | 用途 |
|---|---|---|
| `AXUIElement` | `System.Windows.Automation` / UI Automation | UIツリー取得、要素検索、Invoke/Value/ExpandCollapse等の操作 |
| `CGEvent` | Win32 `SendInput` | マウスクリック、右クリック、スクロール、キー入力 |
| `NSWorkspace` | `System.Diagnostics.Process` + Win32 window enumeration | 実行中GUIアプリ列挙、前面化 |
| `screencapture` | `Graphics.CopyFromScreen` | 画面またはウィンドウのPNG取得 |
| `NSPasteboard` | `System.Windows.Forms.Clipboard` | クリップボード読み書き |
| MCP JSON-RPC stdio | 標準入力/標準出力のJSON-RPC 2.0 | Claude/Cursor/Codex等からの利用 |

Windows版では、macOSの `bundle_id` に相当する安定識別子が存在しないため、CLI/MCPの引数名は互換性を優先して `bundle_id` を残しつつ、値として **プロセス名**、**PID文字列**、または **ウィンドウタイトル部分一致** を受け付ける設計にする。例えば Chrome は `chrome`、メモ帳は `notepad`、PID指定は `pid:1234` とする。

初期実装のツール面は、参照実装と同等の `list_apps`、`get_ax_tree`、`ax_tree_json`、`find_element`、`click_element`、`click_ref`、`activate`、`type_text`、`key_press`、`wait_for`、`scroll`、`right_click`、`screenshot`、`clip_get`、`clip_set` を実装対象にする。一方、macOSのメニューバーをAXで辿る `menu` はWindowsアプリごとに実装差が大きいため、初期版では **UIツリー上のMenuItem検索とInvokeにフォールバック** する実装にする。

> 重要な制約として、UIAで取得できる情報はアプリ側のアクセシビリティ実装に依存する。WPF、WinUI、UWP、標準Win32コントロールは比較的扱いやすいが、Electron、Chromium内Webコンテンツ、ゲーム、独自描画UIではツリーが粗くなる場合がある。その場合はスクリーンショットと座標操作を併用する。

セキュリティ面では、WindowsのUI AutomationはmacOSのような明示的なアクセシビリティ許可ダイアログを基本的に必要としないが、**UACで昇格されたアプリを非昇格プロセスから操作できない**、**セッション0やロック画面は操作できない**、**管理者権限アプリを操作するには本ツールも管理者権限で起動する必要がある** という制約がある。
