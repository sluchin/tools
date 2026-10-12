# プロジェクト設定

自分用のツール集 (`server`、`caltime`、`mail`、`iperf`、`zlib` など、ツールごとのディレクトリ)。

## コミットガイドライン

- コミットメッセージは英語で記述
- **件名は、Conventional Commits の形式で書く**: `type(scope): description`。scope (括弧を含む) は、省略できる。description は、英語で、命令形 (例: `feat(caltime): Add the option to print the week number`)。
  - type は、次のどれか。
    - `feat`: 機能の追加
    - `fix`: バグの修正
    - `docs`: 文書とコメントだけの変更 (`*.md`、ソースのコメント)
    - `style`: 整形、規約の適用 (動作を変えない)
    - `refactor`: 動作を変えない、書き換え
    - `test`: テストだけの変更
    - `build`: ビルド (各ツールの `Makefile` など) の変更
    - `ci`: CI (`.github/`) の変更
    - `chore`: そのほかの雑務 (最初のコミット、`.gitignore` など)
  - scope は、変更のあるツール (ディレクトリ名: `server` / `caltime` / `mail` / `iperf` / `zlib` / `counter` / `tz` / `json` / `hex` / `expect`)。複数のツールにまたがるときは、省略する。
  - 互換性を壊す変更は、type (または scope) の直後に、感嘆符を付ける (Conventional Commits の仕様のとおり)。
  - 複数の type にまたがるときは、変更の中心になる type にする。
- 件名のあとに空行を 1 行入れて、本文を書く。本文はダッシュ/ハイフンで始まる箇条書き (例: `- Fix bug in parser`)。箇条書きの各行の間には、空行を入れない
- コミットメッセージに `Co-Authored-By` または Claude 帰属行を含めない
- **rebase したあとの push は、`git push --force-with-lease --force-if-includes origin <ブランチ名>` で行う** (`--force` は使わない。リモートに、手元に取り込んでいないコミットがあれば、push は失敗する)。ユーザーに依頼されたときだけ、push する。
