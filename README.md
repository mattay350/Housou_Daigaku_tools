# Housou_Daigaku_tools

放送大学のシラバスを取得して DB 化し、Swank 経由で Emacs から引けるようにする常駐サーバ。

- 教養学部の科目一覧（12 カテゴリ）と、各科目の講義タイトルを取得して `db.lispdata` に保存する
- systemd ユーザーサービスとして常駐し、127.0.0.1:4005 で Swank を公開する
- Emacs 側（[el_conf](https://github.com/mattay350/el_conf) の `conf/51_org_housou_syllabus_db.el`）は、科目コードから学習管理用の org ノートを生成する

## 構成

| ファイル | 役割 |
|---|---|
| `housou-syllabus-db-server.lisp` | シラバスの取得、DB の保存・読み込み、Emacs 向けの org 文字列の生成 |
| `start-server.lisp` | DB を読み込み（無ければ取得し）、Swank を 4005 番で起動して待機する |
| `syllabus-db-server.service` | systemd ユーザーサービスのユニット |
| `setup-service.sh` | ユニットを `~/.config/systemd/user/` にコピーし、有効化・起動する |
| `start-server.org` | 起動・確認・DB 更新の手順メモ |
| `db.lispdata` | シラバス DB（`syllabus` 構造体のベクタを `print` したもの） |
| `gen-readme.lisp` | この README の「API」節をソースから生成する |

## 必要なもの

- [Roswell](https://github.com/roswell/roswell)（SBCL + Quicklisp）。ユニットは `/usr/local/bin/ros` を使う
- Quicklisp のライブラリ: `dexador` `split-sequence` `plump` `clss` `cl-cookie` `swank`（初回ロード時に取得される）
- systemd（ユーザーサービス）

## セットアップ

1. `syllabus-db-server.service` の `WorkingDirectory` を、このリポジトリの絶対パスに合わせる
2. 登録して起動する

   ```sh
   ./setup-service.sh
   ```

3. 確認する

   ```sh
   systemctl --user status syllabus-db-server.service
   journalctl --user -u syllabus-db-server.service -f
   ```

   ログの最後に `Swank server is running on port 4005...` が出ていれば稼働している。

## データの取得

- 科目一覧: `https://www.ouj.ac.jp/kamoku/kyouyou/C/` 以下のカテゴリページ（`*urls*`）から、科目名・URL・科目コード・主任講師・開設年度を取る
- 講義タイトル: 各科目のシラバス（WAKABA）から取る。セッション Cookie を得るため、科目ページへのアクセスと `initialize.do` への POST の2回に分けてアクセスする
- 起動時に `db.lispdata` があれば読み込む。無ければ全カテゴリを取得して保存してから Swank を起動する（時間がかかる）

## Emacs からの利用

入口は `emacs-callback-function` で、引数は機能名と科目コード（7桁の文字列）。

| 機能名 | 戻り値 |
|---|---|
| `"generate-note"` | 科目ノート全体（概要・Todo・columnview・講義ごとの TODO 見出し） |
| `"get-course"` | 講義タイトルを `** TODO` 見出しにした文字列 |

該当する科目が無ければ `"Not Found"` を返す。

```lisp
(cl-user::emacs-callback-function "generate-note" "5570115")
```

el_conf では `C-c h g`（ノート生成）と `C-c h c`（講義一覧）から呼んでいる。ノートのリンクを作るため、科目名は `find-name-by-code` で別に取得する。

## DB の更新

`emacs-callback-function` は呼ばれるたびに `db.lispdata` を読み直す。そのため、ファイルを差し替えれば再起動しなくても反映される。

取得し直す場合は、ファイルを消してサービスを再起動する。

```sh
rm db.lispdata
systemctl --user restart syllabus-db-server.service
```

サービスの起動中にファイルが無い状態で Emacs から呼ぶと、その呼び出しの中で全カテゴリの取得が始まる。取得が終わるまで Emacs は応答を待ち続ける。

## README の再生成

下の「API」節は、`gen-readme.lisp` がソースの docstring から生成している。関数や docstring を変えたら、次のコマンドで更新する。

```sh
ros run --load gen-readme.lisp
```

マーカーの間だけが書き換わるので、それ以外の部分は手で編集してよい。

## API

<!-- BEGIN GENERATED: API -->
<!-- このマーカーの間は gen-readme.lisp が生成する。手で編集しない。 -->

### 構造体

#### `syllabus`

1科目分のシラバス情報。

スロット: `name`, `url`, `code`, `lead-instructor`, `offering-year`, `lecture-titles`

### 変数

#### `*user-agent*`

WAKABA（シラバス）へのアクセス時に送る User-Agent。

初期値: `"Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"`

#### `*urls*`

科目一覧を取得する教養学部のカテゴリページ。

初期値: 12 要素のリスト

#### `*filepath*`

シラバス DB の保存先（作業ディレクトリからの相対パス）。

初期値: `"db.lispdata"`

#### `*syllabus-db*`

シラバス DB 本体。syllabus 構造体の可変長ベクタ。

初期値: `(make-array 0 :adjustable t :fill-pointer 0)`

### 関数

#### `(update-all-syllabus-db)`

指定したURLsから講義データを抽出し、`*syllabus-db*` を更新する

#### `(update-syllabus-db url)`

urlから講義データを取得し、追加する

#### `(clean-url url)`

HTMLエンティティの &amp;amp; を正しい &amp; に置換する

#### `(fetch-wakaba-page raw-url)`

WAKABAのセキュリティを通過するためのフェッチ関数

#### `(get-lecture-titles url)`

講義のタイトル名を取得する

#### `(save-syllabus-db filepath)`

DBをファイルにシリアライズする

#### `(load-syllabus-db filepath)`

ファイル FILEPATH から DB を読み込み、`*syllabus-db*` を置き換える

#### `(init)`

DB を初期化する。`*filepath*` があれば読み込み、なければ全カテゴリを取得して保存する

#### `(show-syllabus-db)`

現在 `*syllabus-db*` に格納されている内容を一覧表示する

#### `(find-name-by-code code)`

指定したコードに合致する講義名を探して返す

#### `(find-syllabus-by-code code)`

指定したコードに合致する講義内容を探して返す

#### `(clean-text str)`

全角スペースを半角スペースに置換し、前後の不要な空白をトリミングする

#### `(generate-org-note syllabus)`

Syllabus構造体を受け取り、Org-modeフォーマットの文字列を生成する

#### `(generate-note code)`

科目コード CODE の科目ノート（org）を返す。該当がなければ "Not Found"

#### `(org-get-course syllabus)`

Syllabus構造体を受け取り、講義タイトルを Org の TODO 見出しにした文字列を返す

#### `(get-course code)`

科目コード CODE の講義タイトルを TODO 見出しにした文字列を返す。該当がなければ "Not Found"

#### `(emacs-callback-function func code)`

Emacs から呼ぶ入口。DB を読み直してから FUNC に応じた文字列を返す。
FUNC が "generate-note" なら科目ノート、"get-course" なら講義タイトルの TODO 見出し。
該当する科目がなければ "Not Found"、FUNC が不明なら "Not found function" を返す

<!-- END GENERATED: API -->
