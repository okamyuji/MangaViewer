# ADR-0001 iPad対応

- 状態 Accepted
- 日付 2026-11-21

## 背景

MangaViewerはmacOS 14以降で動くSwiftUIアプリです。画像の型に`NSImage`を使い、キー入力を`NSEvent`で受け、ファイル選択に`NSOpenPanel`を使っています。このままではiPadOS向けにビルドできません。

利用者の目的は、自分のiPadにXcodeからインストールして、macOS版と同じライブラリ管理と見開き表示を使うことです。App Storeでの配布は目的に含めません。

## 決定

| 決定事項 | 検討した案 | 採用 | 理由 |
|---|---|---|---|
| ターゲット構成 | 1つのターゲットに複数の配布先を持たせる、iPad専用ターゲットを足す | iPad専用ターゲット`MangaViewer-iPad`を足す | macOS用の`Info.plist`は`NSPrincipalClass`に`NSApplication`を指定しており、iPadと共有できません |
| 対象端末と最低OS | iPhoneとiPad、iPadのみ | iPadのみ（`TARGETED_DEVICE_FAMILY = 2`）、iPadOS 17以降 | [SwiftData](https://developer.apple.com/documentation/swiftdata)がiPadOS 17以降を求めます |
| 画像の型 | プラットフォームごとに型を書き分ける、型の別名でまとめる | `PlatformImage`という別名で`NSImage`と`UIImage`をまとめる | 呼び出し側のコードを共有できます |
| 本の取り込み | 元の場所をブックマークで参照する、アプリ内にコピーする | 元の場所を参照する | macOS版と同じ仕組みで、端末の容量を使いません |
| ブックマークの指定 | macOSと同じ`.withSecurityScope`を使う、プラットフォームで分ける | macOSは`.withSecurityScope`、iPadは既定の指定 | iOS SDKの`NSURL.h`は`.withSecurityScope`を`API_UNAVAILABLE(ios)`としています |
| ファイル選択 | `NSOpenPanel`と`UIDocumentPickerViewController`を書き分ける、`fileImporter`にまとめる | 両方で`fileImporter`を使う | [fileImporter](https://developer.apple.com/documentation/swiftui/view/fileimporter(ispresented:allowedcontenttypes:allowsmultipleselection:oncompletion:))はmacOS 11とiPadOS 14から使えます |
| フォルダの読み取り | そのまま列挙する、ファイル調整を通して列挙する | iPadでは`NSFileCoordinator`を通す | Appleの[Providing access to directories](https://developer.apple.com/documentation/uikit/providing-access-to-directories)が、選んだフォルダの読み書きにファイル調整を求めています |
| 監視フォルダ | iPadでも常時監視する、起動時と引き下げ操作で読み直す | macOSは常時監視、iPadは起動時と引き下げ操作で読み直す | iPadで外部のファイルプロバイダの変更通知が届くことは確かめられていません |
| ページ表示 | 常に見開き、向きで切り替える | iPadでは縦向きで1ページ、横向きで見開き | 縦向きで2ページを並べると1ページの幅が狭くなります |
| ページ送り | ボタンだけ、タップとスワイプを足す | 左右3分の1のタップ、左右のスワイプ、中央タップでツールバーの出し入れ | 右綴じでは左側のタップと右方向へのスワイプで次のページへ進みます。左綴じでは左右が逆になります。ズーム中のドラッグは画像の移動に使います |
| キー入力 | iPadで`UIKeyCommand`を使う、`onKeyPress`を使う | iPadは[onKeyPress](https://developer.apple.com/documentation/swiftui/view/onkeypress(_:action:))、macOSは今の`NSEvent`の監視 | `onKeyPress`はiPadOS 17から使えます。macOSの挙動は変えません |
| 設定画面 | macOSと同じ`Settings`シーン、シート | iPadではサイドバーの歯車ボタンからシートで開く | iPadOSには`Settings`シーンがありません |
| CI | macOSだけ、iPadシミュレータを足す | fastlaneの`ci` laneにiPadシミュレータのテストを足す | iPad向けのビルドが壊れたことを検出できます |

## macOS版で合わせて直すもの

- 監視フォルダの監視と起動時の読み直しを、アプリの起動時に始めます。今は`LibraryViewModel`を`startWatching: false`でしか作っていないため、監視が動いていません。
- 設定画面の既定の読み方向とズームを、本を開くときに使います。今は`ReaderViewModel`がこの値を読んでいません。
- どの画面からも使われていない`LibraryView`と`BookGridItem`を消します。

## 影響

- iPadでiCloud上のまだダウンロードされていない本を開くと、ダウンロードを待つ時間が生じます。
- 利用者が設定アプリでフォルダへのアクセス権を取り消すと、ブックマークの解決が失敗します。この場合は本を追加し直す案内を出します。
- ライブラリ、読書の進み具合、しおり、タグは端末ごとのSwiftDataに保存され、macOSとiPadの間で同期されません。iPad版は空のライブラリから始まります。
- App Storeへの提出に要るiPad用アイコンとarchiveの手順は含めません。
