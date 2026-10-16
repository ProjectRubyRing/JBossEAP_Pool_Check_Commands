# JBoss EAP コネクションプール確認コマンド「jbpool」解説書

ECS（ECS Exec）／Docker Compose で動く「フロント」「バック」各コンテナの JBoss EAP を、JBoss CLI でのぞいて調べるためのコマンドと、その読み方・歴史・しくみ

作成日：2026-10-17

## 目次

1. まず 3 分で理解しよう ―「学校の貸し出し傘」のお話
2. 登場の歴史と背景 ― 1997 年から 2026 年まで
3. このコマンドが必要になった経緯
4. 使い方 ― 1 歩ずつ（ECS と Docker Compose）
5. コマンド集 ― jbpool・環境変数・生の CLI・ログ
6. 出力の見方 ― 実際の画面と、各項目の意味
7. 「タイムアウトにより解消する予定の時刻」の計算方法
8. 検証結果 ― 実際に動かして確かめたこと
9. 注意点とトラブル対応
10. 用語集
11. 参考資料（出典）
12. jbpool.sh 全文

---

## 0. 表紙・概要

> ECS（ECS Exec）／Docker Compose で動く「フロント」「バック」各コンテナの JBoss EAP を、JBoss CLI でのぞいて調べるためのコマンドと、その読み方・歴史・しくみ

| 項目 | 内容 |
|---|---|
| 作成日 | 2026-10-17 |
| 対象 | JBoss EAP 7.4 / 8.0 / 8.1（standalone モード）と、その上流の WildFly 10 以降 |
| 実行場所 | ECS タスク内のフロント／バック各コンテナ（ECS Exec）、または docker compose のサービス内 |
| 前提 | コンテナの中で $JBOSS_HOME/bin/jboss-cli.sh が動くこと（このコマンドはそれを自動で探します） |
| 動作確認 | WildFly 41.0.1.Final（EAP 8 系の上流）を Docker で 2 台（front／back、ネットワーク共有＋port-offset 100）起動し、あふれ・タイムアウト・アイドル回収を実際に起こして確認（詳細は 08_検証結果） |

### 3 行まとめ

- jbpool.sh をコンテナのシェルに丸ごと貼り付けると、その JBoss EAP の全データソースについて「いま何本使っているか」「あふれて待っている人がいるか」「いつタイムアウトで解消するか」が一覧で出ます。
- 「jbpool watch 10」で 10 秒ごとの推移（増えた・減った・待った・タイムアウトした）を、「jbpool csv」で Excel 用の CSV を出せます。
- 設定を変えない（読み取り専用）・パスワードを読まない・小さなメモリで動く・フロント／バックの管理ポートのずれを自動判別、という安全設計です。

### 成果物

| ファイル | 中身 | 使い方 |
|---|---|---|
| jbpool.sh | 本体スクリプト（ASCII のみ・タブなし・貼り付け安全） | コンテナのシェルに全文を貼り付ける／docker compose exec -T … sh -s < jbpool.sh で流し込む |
| JBossEAP_ConnectionPool_Check.md | この解説書の Markdown 版 | Git やチャットで共有するとき |
| JBossEAP_ConnectionPool_Check.xlsx | この解説書の Excel 版 | 印刷・レビュー・計算シート（07）を使うとき |

### シートの案内

| シート | 書いてあること | こんな人に |
|---|---|---|
| 01_まず3分で理解 | 傘立てのたとえ話で、プール・あふれ・タイムアウトを説明 | はじめての人・小学生 |
| 02_歴史と背景 | 1997 年の JDBC から 2026 年の EAP 8.1／ECS Exec までの年表 | なぜ今こうなっているか知りたい人 |
| 03_必要になった経緯 | どんな困りごとがあり、なぜこのコマンドが必要か | 導入を説明する人 |
| 04_使い方（手順） | ECS と Docker Compose での手順を 1 歩ずつ（bash／PowerShell） | 実際に打つ人 |
| 05_コマンド集 | jbpool のサブコマンド・環境変数・生の CLI・ログ確認 | 手元に置いておきたい人 |
| 06_出力の見方 | 実際の出力例と、各項目の意味（元の JBoss 属性つき） | 結果を読む人 |
| 07_解消予定時刻の計算 | 「いつ解消するか」の計算式と、その根拠（ソースコード）／計算シート | 根拠を確かめたい人 |
| 08_検証結果 | 実機で再現テストした結果 | 品質を確認したい人 |
| 09_注意点とトラブル | メモリ・認証・ポート・統計 OFF などの注意と対処 | うまく動かない人 |
| 10_用語集 | むずかしい言葉を、ふつうの言葉とこども向けの言葉で | 全員 |
| 11_参考資料 | 公式ドキュメント・ソースコード・発表記事 | 出典を確かめたい人 |
| 12_スクリプト全文 | jbpool.sh の全行（Excel は行番号つき） | 中身を読みたい人 |

> **補足**　Excel のコードは「1 行＝1 セル」で入っています。コピーするときはコードの列（B 列、12_スクリプト全文では C 列）だけを縦に選んでコピーしてください。複数の列をまたいで選ぶと、見えないタブ文字が混ざり、端末に貼ったときに補完が動いてしまうことがあります。いちばん確実なのは jbpool.sh ファイルそのものを使う方法です。

---

## 1. まず 3 分で理解しよう ―「学校の貸し出し傘」のお話

> むずかしい言葉の前に、「学校の貸し出し傘」のお話で全体をつかみましょう。ここがわかれば、残りのシートは「お話を正式な言葉で言い直したもの」です。

### お話

① 雨の日、子どもたち（＝お客さんのリクエスト）が外に出るには傘（＝データベースとの「コネクション」）が必要です。毎回お店で新しい傘を買う（＝コネクションを新しく作る：ネットワークをつなぎ、ログインして…）のは、時間もお金もかかります。そこで学校は、昇降口に「貸し出し用の傘立て」（＝コネクションプール）を置きました。使い終わった傘は傘立てに返し、次の子がまた使います。

② 傘立てに置ける本数には上限があります（＝max-pool-size。何も設定しないと 20 本）。全部貸し出し中のときに来た子は、列に並んで待ちます。これが「あふれ（オーバーフロー）」です。待てる時間には決まりがあり（＝blocking-timeout-wait-millis。ふつうは 30 秒）、それを過ぎると「ごめんね、傘はありません」と断られます。JBoss ではこのとき IJ000453／IJ000655 というエラーが出ます。

③ 晴れが続いて傘があまっていると、用務員さん（＝IdleRemover）が見回りに来て、長いあいだ使われていない傘を片付けます（＝idle-timeout-minutes。ふつうは 30 分）。見回りは「いちばん短い片付け時間の半分」ごと。ただし同じ傘立てを調べるのは 1 分に 1 回までです。

④ 傘を借りるときは「さっき返ってきたばかりの傘」から先に渡されます（LIFO：後に入れたものから先に出す）。だから奥にある傘はずっと使われず、片付けの順番が回ってきます。片付けは「いちばん長く使われていない傘」から順番です。

⑤ 「いつも最低 ◯ 本は置いておく」という決まり（＝min-pool-size）もありますが、じつは「最初から並べておく（pool-prefill）」か「最低本数を厳しく守る（pool-use-strict-min）」のどちらかを ON にしていないと、片付けのときに 0 本まで減ることがあります。これは今回、実際に動かして確かめました。

⑥ 大事なのが「貸し出しノート」（＝統計 statistics）。最初はノートを付けていない（OFF）ので、数を聞いても 0 しか答えてくれません。「jbpool enable-stats」でノートを付け始めます。

⑦ お店（アプリ）には受付係（＝フロントコンテナ）と料理係（＝バックコンテナ）がいて、それぞれが自分の傘立てを持っています。料理係の傘が足りなくなると料理が遅れ、受付にもお客さんがたまっていきます（あふれの連鎖）。だから両方の傘立てを調べる必要があるのです。

⑧ jbpool は、管理人さん専用のトランシーバー（＝JBoss CLI）で「いま何本貸し出し中？並んでいる子は？いつ解決しそう？」と聞いて、表にまとめてくれる道具です。お店は遠くの AWS にあるので、合鍵（＝ECS Exec）で中に入って使います。手元の机の上に同じお店の模型（＝Docker Compose）を作って試すこともできます。

### ことばの対応表

| 本当のことば | 傘立てでいうと | ひとことで言うと |
|---|---|---|
| コネクション（接続） | 傘 | データベースと話すための通り道。作るのに時間がかかる |
| コネクションプール | 貸し出し用の傘立て | 作った通り道を使い回すしくみ |
| getConnection／close | 傘を借りる／返す | 返さないと次の人が使えない |
| max-pool-size | 傘立ての最大本数（既定 20） | これ以上は増えない |
| min-pool-size | いつも置いておきたい本数（既定 0） | prefill か strict-min が ON のときだけ守られる |
| InUseCount | いま貸し出し中の本数 | 使われている本数 |
| IdleCount | 傘立てで休んでいる本数 | すぐ貸せる本数 |
| ActiveCount | 学校にある傘の合計 | 貸し出し中＋休み中 |
| 待ち行列（キュー） | 傘がなくて並んでいる子の列 | これが「あふれ」 |
| blocking-timeout-wait-millis | 並んで待てる時間（既定 30 秒） | 過ぎるとエラー（IJ000655） |
| idle-timeout-minutes | 使われない傘を片付けるまでの時間（既定 30 分） | 過ぎると閉じられる |
| IdleRemover | 見回りの用務員さん | 片付け係。一番短い片付け時間の半分ごとに起きる |
| LIFO | さっき返された傘から貸す | 奥の傘ほど使われない |
| コネクションリーク | 傘の返し忘れ | 傘立てがだんだん空になる原因 |
| statistics-enabled | 貸し出しノート | OFF だと全部 0 に見える |
| JBoss CLI（jboss-cli.sh） | 管理人さんのトランシーバー | サーバーに質問・命令する道具 |
| ECS Exec | 遠くのお店に入る合鍵 | AWS のコンテナの中でコマンドを打てる |
| Docker Compose | お店の模型セット | 手元で同じ構成を動かせる |
| フロント／バック | 受付係／料理係 | それぞれ自分の傘立てを持つ |

### ぜんたいの絵

**図（矢印はリクエストの流れ）**

```text
お客さん --> [フロント JBoss] --(HTTP など)--> [バック JBoss] --(コネクション)--> [データベース]
               | 傘立て(プール) F                  | 傘立て(プール) B
               | jbpool で調べる                    | jbpool で調べる
```

> **補足**　ポイント：あふれは「どこか 1 か所の傘立て」で起きても、前の係（フロント）にも行列が伝わります。両方を同じ時刻に調べると、どこが本当の原因かがわかります。

---

## 2. 登場の歴史と背景 ― 1997 年から 2026 年まで

> コネクションプールは「データベースにつなぐのは高い（時間がかかる）」という昔からの悩みから生まれ、JBoss とともに育ち、いまはコンテナ（ECS／Docker）の中で動いています。年表で流れを追いましょう。

| 年 | できごと | それで何がよくなった？（背景） | このコマンドとの関係 |
|---|---|---|---|
| 1997 | JDBC 1.0 登場（JDK 1.1） | Java からいろいろなデータベースに同じ書き方でつなげるようになった | 「Connection（接続）」という考え方が Java に入った |
| 1998〜1999 | JDBC 2.0（Optional Package：javax.sql の DataSource／ConnectionPoolDataSource／XADataSource） | 接続を使い回す「プール」の標準の入口ができた | アプリは DataSource から借りる。今のプールの基本形 |
| 1999 | JBoss（当初は EJBoss）プロジェクト開始／J2EE 1.2（12 月） | 無料で使えるアプリケーションサーバーが広まった | JBoss EAP のご先祖さま |
| 2001 | J2EE 1.3 と JCA 1.0（Java コネクタ・アーキテクチャ） | プール・トランザクション・セキュリティをサーバーがまとめて面倒を見る標準ができた | JBoss のデータソースは JCA の上に作られている（だから IJ〜 のメッセージが出る） |
| 2006 | Red Hat が JBoss を買収 | 企業向けにサポートされる JBoss（のちの EAP）へ |  |
| 2010 年ごろ | IronJacamar（JCA 1.6 の実装）が登場 | 新しいプール実装と統計情報 | 今もプールの中身は IronJacamar（メッセージ ID の IJ はその頭文字） |
| 2011 | JBoss AS 7（モジュール化・管理モデル・jboss-cli.sh） | 設定も状態も「管理モデル」に一本化。CLI で読めるように | このコマンドの土台 |
| 2012 | JBoss EAP 6.0（AS 7 ベース） | 企業向けに CLI／管理 API が標準装備 | 当時の管理ポートは 9999（native） |
| 2013〜2014 | コミュニティ版が WildFly に改名（WildFly 8：2014 年 2 月） | EAP の上流（アップストリーム）として毎年進化 | 今回の検証は WildFly 41.0.1.Final で実施 |
| 2014〜2015 | Amazon ECS 発表（2014 年 11 月）・一般提供（2015 年 4 月）／Docker Compose 登場（2014 年） | コンテナを並べて動かす時代へ | フロント／バックを別コンテナで動かす形が一般的に |
| 2016 | JBoss EAP 7.0（WildFly 10 ベース） | 管理ポートが 9990（HTTP）に統一。statistics-enabled が設定として保存できるように（WFLY-3084、WildFly 9 で対応） | 既定の接続先 remote+http://127.0.0.1:9990 |
| 2017 | AWS Fargate 発表（11 月） | サーバー（EC2）を自分で持たずにコンテナを動かせる | 「SSH でホストに入って docker exec」ができなくなった |
| 2017〜2019 | Java EE が Eclipse 財団へ移り Jakarta EE に | パッケージ名が javax.* から jakarta.* へ | EAP 8 ではエラーが jakarta.resource.ResourceException と表示される |
| 2021 年 3 月 | ECS Exec 登場 | Fargate でもコンテナの中でコマンドを打てる | 今回の前提そのもの |
| 2021 | JBoss EAP 7.4 | EAP 7 系の最終マイナー版 | 今も多くの現場で稼働 |
| 2022〜2023 | Docker Compose V2（docker compose）。V1（docker-compose）は 2023 年 6 月でサポート終了 | Go で書き直され Docker CLI に統合 | 本書は docker compose（スペース区切り）で表記 |
| 2024 年 2 月 | JBoss EAP 8.0 一般提供（Jakarta EE 10） | 新世代。コンテナ用イメージの JBOSS_HOME は /opt/server | スクリプトが /opt/server を最初に探す理由 |
| 2025 年 6 月 | EAP 7.4 のフルサポート終了 → 延長サポート（ELS、2027 年 10 月まで） | 8 系への移行がすすむ | 7.4／8.x のどちらでも同じコマンドで動くように設計 |
| 2025 年 9 月 | EAP 8.1 提供開始（Red Hat Developer ブログ 2025/9/2）／ECS Exec が AWS マネジメントコンソールから利用可能に（2025/9/4） | ブラウザ（CloudShell）からも中に入れる | 手順 04 にコンソールからの入り方を記載 |
| 2026 | EAP 8.0 は Update 12 で更新終了と案内され、8.1 への移行が推奨 | 最新の更新は 8.1 系で提供 | 8.1 でも同じ管理モデル（datasources サブシステム） |

### なぜプールが生まれたのか

データベースに新しくつなぐには、ネットワークの接続（TCP）、暗号化（TLS）、ログイン（認証）、セッションの準備…と、何往復もの手続きが要ります。1 回のリクエストのたびにこれをやると、とても遅くなり、データベースにも負担がかかります。そこで「一度つないだ接続を取っておいて使い回す」＝コネクションプールが生まれました。

### JBoss とプール

JBoss のデータソースは、JCA（Java コネクタ・アーキテクチャ）という標準のしくみの上に作られています。プールの本体は IronJacamar というライブラリで、エラーメッセージの「IJ000655」などの IJ はその頭文字です。JBoss AS 7（2011 年）以降は、プールの設定も「いまの状態（統計）」も、管理モデルという 1 つの木構造にまとめられ、jboss-cli.sh で読み書きできるようになりました。jbpool はこの木を読みに行きます。

### コンテナ時代の新しい悩み

ECS や Fargate では、サーバーに SSH で入るという昔ながらの方法が使えません。2021 年の ECS Exec の登場で「コンテナの中でコマンドを打つ」ことができるようになり、2025 年 9 月にはマネジメントコンソールからも入れるようになりました。一方、CloudWatch などの外側の監視では、JBoss の中の「貸し出し中・待ち・タイムアウト」は見えません。そこで「中に入って、JBoss 自身に聞く」この方法が必要になります。

---

## 3. このコマンドが必要になった経緯

> 「なんだか遅い」「ときどき 30 秒でエラーになる」――その裏で何が起きているのかを、順番に見ていきます。

### あふれの連鎖（よくある障害のすじがき）

- ① データベースが遅くなる（重い SQL、ロック待ち、フェイルオーバー、ネットワークの遅れ など）。
- ② 1 本の接続を返すまでの時間が長くなり、プールの「貸し出し中」が増える。
- ③ プールが満杯（InUseCount = max-pool-size）になり、次のリクエストは列に並ぶ（あふれ）。
- ④ 待ち時間（既定 30 秒）を超えたリクエストは IJ000655 → IJ000453 のエラーで失敗する。
- ⑤ バックの処理を待つフロントのスレッドも動けなくなり、フロントでも行列が伸びる。
- ⑥ ヘルスチェックに失敗してタスクが入れ替わると、証拠（そのときの状態）が消えてしまう。

### 困りごとと、このコマンドでの解決

| 困りごと | ひと昔前のやり方 | いま（jbpool） |
|---|---|---|
| サーバーの中を見たい | SSH でサーバーにログイン | ECS Exec／docker compose exec でコンテナに入って実行（Fargate には SSH 先がない） |
| プールの中身を知りたい | 管理コンソール（Web 画面）を目で見る | JBoss CLI を文字で実行。記録・比較・共有がしやすい（コンテナ版 EAP には管理コンソールが含まれないことがある） |
| 外側の監視では足りない | CloudWatch で CPU・メモリ、RDS で接続総数まで | JBoss の中の「貸し出し中・待ち行列・タイムアウト回数・待っているスレッド名」まで見える |
| 「いつ直るの？」に答えたい | 経験と勘 | 設定値（待ち時間・片付け時間）と観測時刻から「◯時◯分までに解消」を計算して表示 |
| フロントとバックのどちらが原因？ | 片方だけ見て誤解 | 同じコマンドを両方で実行。同じタスク内で管理ポートがずれていても（port-offset）自動で判別 |
| 障害が終わると証拠が消える | タスクが入れ替わって再現しない | watch／csv で推移を残す。threads で「どのコードで待っているか」を残す |
| 統計が 0 のまま | 設定ミスに気づかない | STATS-OFF と表示し、enable-stats で（再起動なしで）すぐ ON にできる |

### 「タイムアウトで解消する予定の時刻」がなぜ大事か

障害対応では「待てば直るのか、手を打つ（再起動・スケールアウト・SQL 停止）べきなのか」をすばやく決める必要があります。jbpool は、待っているリクエストは『遅くとも何時何分までに（接続を得るか、エラーで）いなくなるか』、余っている接続は『何時何分ごろ片付けられるか』を、JBoss の設定値と IronJacamar の実際の動き（ソースコードで確認）から計算して表示します。

> **補足**　このコマンドは読み取り専用です（enable-stats／disable-stats を除く）。プールの設定（max-pool-size など）を変える命令は含みません。WildFly 41 で確認したところ、プール設定の変更は reload（再読み込み）が必要で、本番中に気軽に行うものではありません。

---

## 4. 使い方 ― 1 歩ずつ（ECS と Docker Compose）

> どちらの環境でも「コンテナに入る → jbpool.sh を貼る（または流し込む）→ 結果を読む」の 3 段階です。フロントとバックで同じことを 2 回やります。

### A. ECS（AWS）で使う ― 事前チェック

| チェック項目 | 内容 | 確認・設定方法 |
|---|---|---|
| 手元の道具 | AWS CLI v2 と Session Manager プラグイン | aws --version／session-manager-plugin のインストール |
| ECS Exec の有効化 | タスクの enableExecuteCommand が true | サービス更新時に --enable-execute-command（新しく起動したタスクから有効） |
| タスクロールの権限 | ssmmessages:CreateControlChannel／CreateDataChannel／OpenControlChannel／OpenDataChannel | IAM のタスクロールに付与 |
| （推奨）init プロセス | initProcessEnabled=true（SSM エージェントの子プロセス整理） | タスク定義の linuxParameters |
| 困ったとき | amazon-ecs-exec-checker で一括診断 | GitHub: aws-containers/amazon-ecs-exec-checker |
| ブラウザから入る | 2025/9 から、タスク詳細 → コンテナを選ぶ →「Connect」で CloudShell が開く | ローカルにツールが無いときに便利 |

### A-1〜A-3. タスクを選んでフロントに入る（bash）

**bash（Mac／Linux／WSL／Git Bash）**

```bash
# 0) 自分の環境に合わせて変える
REGION=ap-northeast-1; CLUSTER=my-cluster; SERVICE=my-service

# 1) 動いているタスクを 1 つ選ぶ
TASK=$(aws ecs list-tasks --region "$REGION" --cluster "$CLUSTER" --service-name "$SERVICE" --desired-status RUNNING --query 'taskArns[0]' --output text)
echo "$TASK"

# 2) ECS Exec が使えるか・コンテナ名は何か（agent が RUNNING ならOK）
aws ecs describe-tasks --region "$REGION" --cluster "$CLUSTER" --tasks "$TASK" --query 'tasks[0].{exec:enableExecuteCommand,containers:containers[].{name:name,agent:managedAgents[0].lastStatus}}' --output json

# 3) フロントのコンテナに入る（bash が無いイメージなら "/bin/sh"）
aws ecs execute-command --region "$REGION" --cluster "$CLUSTER" --task "$TASK" --container front --interactive --command "/bin/bash"
```

### A-1〜A-3. 同じことを PowerShell で

**PowerShell（Windows）**

```powershell
# 0) 自分の環境に合わせて変える（Windows PowerShell 5.1 / PowerShell 7 共通）
$Region = "ap-northeast-1"; $Cluster = "my-cluster"; $Service = "my-service"

# 1) 動いているタスクを 1 つ選ぶ
$Task = aws ecs list-tasks --region $Region --cluster $Cluster --service-name $Service --desired-status RUNNING --query "taskArns[0]" --output text
$Task

# 2) ECS Exec が使えるか・コンテナ名は何か
aws ecs describe-tasks --region $Region --cluster $Cluster --tasks $Task --query "tasks[0].{exec:enableExecuteCommand,containers:containers[].{name:name,agent:managedAgents[0].lastStatus}}" --output json

# 3) フロントのコンテナに入る
aws ecs execute-command --region $Region --cluster $Cluster --task $Task --container front --interactive --command "/bin/bash"
```

### A-4〜A-8. コンテナの中でやること

**コンテナの中（ECS Exec のシェル）**

```bash
# ===== ここからはコンテナの中 =====
# 4) jbpool.sh の中身を「全部」貼り付ける → 最後の行で自動的に snapshot が 1 回動く

# 5) 推移を見る（10 秒ごと。止めるときは Ctrl+C）。時刻を日本時間で出すなら TZ=JST-9
TZ=JST-9 jbpool watch 10

# 6) あふれていたら、どのコードで待っているかを見る
jbpool threads

# 7) 統計が OFF（STATUS が STATS-OFF）なら ON にする（再起動で元に戻る一時的な ON）
jbpool enable-stats

# 8) 終わったら抜ける
exit
```

### A-9. バックでも同じことをする

**bash**

```bash
# バックも同じ手順（--container だけ変える）
aws ecs execute-command --region "$REGION" --cluster "$CLUSTER" --task "$TASK" --container back --interactive --command "/bin/bash"
```

### A-10.（任意）ファイルに保存して、手元から front／back をまとめて実行

**コンテナの中**

```bash
# （任意）2 回目以降を楽にする：コンテナの中にファイルとして保存しておく
cat > /tmp/jbpool.sh <<'JBPOOL_EOF'
（ここに jbpool.sh の中身を全部貼る）
JBPOOL_EOF
sh /tmp/jbpool.sh            # snapshot
sh /tmp/jbpool.sh watch 10   # 推移
```

**bash（手元 PC）**

```bash
# 両方のコンテナに /tmp/jbpool.sh を置いたあと、手元 PC から front／back を続けて実行（bash）
for C in front back; do
  echo "===== $C"
  aws ecs execute-command --region "$REGION" --cluster "$CLUSTER" --task "$TASK" --container "$C" --interactive --command "env TZ=JST-9 JBP_LABEL=$C sh /tmp/jbpool.sh snapshot"
done
```

**PowerShell（手元 PC）**

```powershell
# 同じことを PowerShell で
foreach ($C in "front", "back") {
  "===== $C"
  aws ecs execute-command --region $Region --cluster $Cluster --task $Task --container $C --interactive --command "env TZ=JST-9 JBP_LABEL=$C sh /tmp/jbpool.sh snapshot"
}
```

> **補足**　ECS Exec のセッションログ（CloudWatch Logs／S3）を有効にしている場合、打った文字や画面の出力が記録されます。CLI_PASS などのパスワードを打たない運用にしてください（このコマンドは通常パスワード不要のローカル認証で動きます）。

### B. Docker Compose で使う

**bash**

```bash
# docker-compose.yml があるフォルダで実行（bash / Git Bash / WSL）
docker compose ps

# front と back の snapshot を続けて（ファイルを標準入力で流し込む方式。貼り付け不要）
for S in front back; do echo "===== $S"; docker compose exec -T -e TZ=JST-9 -e JBP_LABEL=$S "$S" sh -s -- snapshot < jbpool.sh; done

# back の推移を 10 秒ごと（Ctrl+C で止める）
docker compose exec -T -e TZ=JST-9 -e JBP_LABEL=back back sh -s -- watch 10 < jbpool.sh

# back の推移を CSV で 1 時間ぶん（10 秒 × 360 回）手元に保存
docker compose exec -T -e TZ=JST-9 -e JBP_LABEL=back back sh -s -- csv 10 360 < jbpool.sh > pool_back.csv
```

**PowerShell**

```powershell
# PowerShell では「<」が使えないので cmd /c に任せる
docker compose ps
foreach ($S in "front", "back") { "===== $S"; cmd /c "docker compose exec -T -e TZ=JST-9 -e JBP_LABEL=$S $S sh -s -- snapshot < jbpool.sh" }
cmd /c "docker compose exec -T -e TZ=JST-9 -e JBP_LABEL=back back sh -s -- watch 10 < jbpool.sh"
cmd /c "docker compose exec -T -e TZ=JST-9 -e JBP_LABEL=back back sh -s -- csv 10 360 < jbpool.sh > pool_back.csv"
```

**貼り付けで使う場合**

```bash
# 貼り付けで使う場合（ECS と同じ感覚）
docker compose exec front bash
# → 中に入ったら jbpool.sh の中身を全部貼る → jbpool watch 10 など
```

> **補足**　jbpool.sh は改行コード LF のまま保存してください（CRLF にすると sh がエラーになります）。長い貼り付けが途中で切れる端末では、スクリプト内の「PART 1/3」「PART 2/3」「PART 3/3」の区切りごとに分けて貼れば大丈夫です。

---

## 5. コマンド集 ― jbpool・環境変数・生の CLI・ログ

### jbpool のサブコマンド

| コマンド | 何をする | 何がわかる | 設定変更 |
|---|---|---|---|
| jbpool（= jbpool snapshot） | 全データソースをくわしく 1 回調べる | 設定・現在値・最大値・累計・待ちスレッド・解消予定・アドバイス | なし |
| jbpool watch [秒] [回数] | 指定秒ごとに 1 行ずつ推移を表示（既定 10 秒、回数 0 = 無限） | 増えた（NEW）・減った（DEL／T/O）・待った（WAIT）・タイムアウト（TMOUT）・行列（QUEUE）・片付け予定 | なし |
| jbpool csv [秒] [回数] | watch と同じ内容を CSV で出力 | Excel でグラフにできる推移データ | なし |
| jbpool threads | 接続待ちのスレッドのスタックトレースを表示 | どのクラス・どの行で接続を待っているか | なし |
| jbpool enable-stats | 全プールの statistics-enabled を true に（実行時のみ） | 以後の数値が記録される | あり（一時的） |
| jbpool disable-stats | 統計を OFF に戻す |  | あり（一時的） |
| jbpool raw | 解析前の CLI 出力そのもの（調査用） | 生データ（パスワード等は読まない） | なし |
| jbpool help | 使い方の表示 |  | なし |

### よく使う例

**コンテナの中**

```bash
jbpool                                   # snapshot（くわしい 1 回分）
TZ=JST-9 jbpool watch 10                 # 10 秒ごと、日本時間で（Ctrl+C で止める）
jbpool watch 5 120                       # 5 秒ごと 120 回（約 15 分）
JBP_CSV=/tmp/pool.csv jbpool watch 10    # 画面に出しながら CSV にも追記
jbpool csv 10 360 > /tmp/pool.csv        # CSV だけを 1 時間ぶん
cat /tmp/pool.csv                        # 中身を表示してコピー → Excel に貼る
MGMT_PORT=10090 jbpool                   # 管理ポートを手で指定（port-offset 100 のとき）
CLI_USER=admin CLI_PASS='xxxx' jbpool    # ローカル認証が使えない構成のとき（ログに残る点に注意）
JBP_WARN=70 jbpool watch 10              # 70% 以上を BUSY と表示
```

### 環境変数（必要なときだけ）

| 変数 | 意味 | 既定（自動） |
|---|---|---|
| JBOSS_HOME | EAP のインストール先 | /opt/server → /opt/eap → /opt/jboss/wildfly → … の順に自動検索 |
| MGMT_PORT | 管理ポート | 動いているサーバーの起動引数から 9990＋port-offset を自動計算 |
| MGMT_HOST | 管理インターフェースのアドレス | 127.0.0.1（-bmanagement などで特定アドレスなら自動でそれ） |
| CONTROLLER | 接続先 URL を丸ごと指定 | remote+http://ホスト:ポート |
| CLI_USER／CLI_PASS | 管理ユーザーで接続する | 未指定（ローカルのサイレント認証） |
| JBP_LABEL | 画面に出す名前 | ECS のコンテナ名（メタデータ v4）→ なければホスト名 |
| JBP_WARN | BUSY と表示するしきい値（%） | 80 |
| JBP_CSV | watch 中に CSV を追記するファイル | なし |
| JBP_JAVA_OPTS | CLI 用 JVM のオプション | -Xms16m -Xmx128m -XX:+UseSerialGC -XX:TieredStopAtLevel=1 |
| JBP_MIN_FREE_MB／JBP_FORCE | メモリの余裕が足りないときの停止しきい値／強制実行 | 200 MB／未指定 |
| TZ | 表示する時刻のタイムゾーン | コンテナの設定（多くは UTC）。TZ=JST-9 で日本時間（tzdata 不要） |

### 生の JBoss CLI コマンド（参考）

**コンテナの中**

```bash
# jbpool を使わずに、生の JBoss CLI で同じ情報を見る（コンテナの中で）
JB=${JBOSS_HOME:-/opt/server}
CLI="sh $JB/bin/jboss-cli.sh -c --controller=remote+http://127.0.0.1:9990"

# 全データソースのプール統計（ActiveCount, InUseCount, WaitCount ...）
$CLI --command='/subsystem=datasources/data-source=*/statistics=pool:read-resource(include-runtime=true)'

# XA データソースの場合
$CLI --command='/subsystem=datasources/xa-data-source=*/statistics=pool:read-resource(include-runtime=true)'

# いま接続を待っているスレッド（スタックトレースつき）
$CLI --command='/subsystem=datasources/data-source=ExampleDS:dump-queued-threads-in-pool'

# 設定値（環境変数の式も解決して表示）
$CLI --command='/subsystem=datasources/data-source=*:read-attribute(name=max-pool-size,resolve-expressions=true)'
$CLI --command='/subsystem=datasources/data-source=*:read-attribute(name=blocking-timeout-wait-millis,resolve-expressions=true)'
$CLI --command='/subsystem=datasources/data-source=*:read-attribute(name=idle-timeout-minutes,resolve-expressions=true)'

# 統計を今すぐ ON（実行時だけ。reload／再起動で元に戻る）
$CLI --command='/subsystem=datasources/data-source=ExampleDS/statistics=pool:write-attribute(name=statistics-enabled,value=true)'
```

### ログでの確認（あふれ・タイムアウトの痕跡）

**bash／PowerShell**

```powershell
# Docker Compose：直近 1 時間のコンテナログからプール関連のエラーを探す（bash）
docker compose logs --since 1h back 2>&1 | grep -E "IJ000453|IJ000655|IJ000604|IJ030027|IJ000100"

# 同じことを PowerShell で
docker compose logs --since 1h back 2>&1 | Select-String -Pattern "IJ000453|IJ000655|IJ000604|IJ030027|IJ000100"

# ECS（CloudWatch Logs）：ロググループを直近 1 時間さかのぼって表示（AWS CLI v2）
aws logs tail /ecs/my-app --since 1h --format short --region ap-northeast-1 --filter-pattern "?IJ000453 ?IJ000655 ?IJ000604 ?IJ030027"

# コンテナの中にログファイルがある構成なら
grep -E "IJ000453|IJ000655" "${JBOSS_HOME:-/opt/server}/standalone/log/server.log" | tail -n 50
```

**CloudWatch Logs Insights のクエリ**

```text
fields @timestamp, @logStream, @message
| filter @message like /IJ000453|IJ000655|IJ000604|IJ030027|IJ000100/
| sort @timestamp desc
| limit 200
```

| メッセージ ID | 意味 | 読み取り方 |
|---|---|---|
| IJ000655 | No managed connections available within configured blocking timeout | 待ち時間（blocking-timeout）を過ぎても空きが出なかった＝あふれ |
| IJ000453 | Unable to get managed connection for <JNDI 名> | アプリから見た「接続が取れない」エラー（多くは IJ000655 が原因） |
| IJ000604 | Throwable while attempting to get a new connection | 新しい接続を作れなかった（DB 停止・認証・ネットワーク） |
| IJ030027 | Destroying connection that is not valid | 検証に失敗した接続を捨てた（DB 再起動・フェイルオーバー後に多い） |
| IJ000100 | Closing a connection for you. Please close them yourself | アプリが接続を返し忘れた（リーク）。CCM（cached-connection-manager）の debug 設定時に出る |

> **補足**　スレッドダンプ（全スレッドの状態）が欲しいときは、jbpool を一度実行したあとの同じシェルで「kill -3 $JBP_PID」と打つと、JBoss の標準出力（＝コンテナログ／CloudWatch Logs）にスレッドダンプが出ます。SIGQUIT は JVM を止めずにダンプだけを出す合図です。

---

## 6. 出力の見方 ― 実際の画面と、各項目の意味

> ここに載せた出力は、08_検証結果のテストで実際に出たものです（WildFly 41、バック側、max-pool-size=3 に対して 6 本同時にリクエスト）。

> **補足**　Excel 版は全体を Meiryo UI（文字ごとに幅がちがうフォント）で表示しているため、実際の画面とくらべて列の位置が少しずれて見えます。端末の画面と同じ見た目で確認したいときは md 版（等幅表示）をご覧ください。

### snapshot の実例（あふれている最中）

**jbpool（snapshot）**

```text
[jbpool] target=back  controller=remote+http://127.0.0.1:10090  cli=/opt/jboss/wildfly/bin/jboss-cli.sh  server-pid=125
==========================================================================================
 JBoss connection pool snapshot : 2026-10-17 07:02:42 JST
 target    : back   (host 2d260dddc5a0)
 server    : WildFly 41.0.1.Final  state=running  controller=remote+http://127.0.0.1:10090
 idle check: IdleRemover wakes every 30s (smallest idle-timeout 1 min / 2), a pool is checked max once/min -> gap <= 1m30s
 io worker : default  busy 6 / max 64  queue 0
------------------------------------------------------------------------------------------
 [ExampleDS] data-source  java:jboss/datasources/ExampleDS   STATUS: OVERFLOW
   config   : min 1 / initial - / max 3   prefill=false* strict-min=false* fair=true*
              blocking-timeout 10000ms  idle-timeout 1min  allocation-retry 0* x 0*ms
              flush=FailingConnectionOnly*  background-validation=false* (-ms)  validate-on-match=false*   (*=default)
   now      : in-use 3 + idle 0 = active 3 / max 3   (use 100%, free permits 0)
   peak     : max-used 3   max-waiting 3   max-wait 1ms   max-get 189ms
   total    : created 15  destroyed 12 (idle-timeout 12, other 0)  waited 15  timeouts 12
   timing   : avg-get 38ms   avg-create 37ms   avg-usage 16834ms   max-usage 25005ms
   queue    : 3 thread(s) WAITING for a connection (pool overflow)
              default task-21 (<=07:02:52), default task-22 (<=07:02:52), default task-23 (<=07:02:52)
   forecast : waiting threads get a connection or fail with IJ000655 by <= 07:02:52 (wait limit 10s)
   advice   : pool reached max-pool-size (MaxUsedCount=3). guide: max-pool-size >= acceptable MaxUsedCount x 1.15, check slow SQL / leaks
            : 12 request(s) timed out waiting (look for IJ000453 / IJ000655 in the log)
            : requests are queuing now -> jbpool threads  (shows which code is waiting)
            : min-pool-size 1 is NOT kept after idle-timeout (pool-prefill / pool-use-strict-min are false)
==========================================================================================
```

### snapshot の各行の意味

| 表示 | 元データ（JBoss の属性・操作） | 意味 | こども向け |
|---|---|---|---|
| target | ECS メタデータ v4 のコンテナ名／ホスト名／JBP_LABEL | どのコンテナを見ているか（front か back か） | どの係の傘立てか |
| server | ルートの product-name／product-version／server-state | 製品と版、状態（running、reload-required など） | お店の名前と、開いているか |
| memory | cgroup の memory.current／memory.max | コンテナのメモリ使用量と上限（CLI を動かす余裕があるか） | お店の広さの残り |
| idle check | 全プールの idle-timeout-minutes の最小値 ÷ 2、1 プール 1 分 1 回の制限 | 片付け係が起きる間隔と、1 つのプールが調べられる最大間隔 | 用務員さんの見回り間隔 |
| io worker | /subsystem=io/worker=*（busy-task-thread-count など） | HTTP を処理する作業スレッドの使用状況（プールの手前の混雑） | 受付の窓口の混み具合 |
| STATUS | 下の「STATUS 一覧」参照 | ひとことでの判定 | 晴れ／くもり／雨 |
| config | min-pool-size／initial-pool-size／max-pool-size／pool-prefill／pool-use-strict-min／pool-fair ほか | プールの決まりごと。末尾の * は「未設定なので既定値」 | 傘立てのルール |
| now | InUseCount／IdleCount／ActiveCount／AvailableCount | いま貸し出し中＋休み中＝合計／最大、使用率、まだ貸せる枠 | いまの傘の数 |
| peak | MaxUsedCount／MaxWaitCount／MaxWaitTime／MaxGetTime | 統計 ON 以降の最大値（いちばん混んだとき） | いちばん混んだ日の記録 |
| total | CreatedCount／DestroyedCount／TimedOut／WaitCount／BlockingFailureCount | 累計：作った・捨てた（うちアイドル片付け）・待った・タイムアウトした | ノートの合計 |
| timing | AverageGetTime／AverageCreationTime／AverageUsageTime／MaxUsageTime（ms） | 借りるまで・作るまで・使っていた時間の平均と最大 | 借りるのにかかった時間 |
| queue | dump-queued-threads-in-pool の結果 | いま並んでいるスレッドの数と名前、それぞれの「遅くともこの時刻まで」 | 並んでいる子の名前 |
| forecast | 上の値＋設定値から計算（07 参照） | 待ちの解消予定、余った接続の片付け予定 | いつ解決しそうか |
| advice | しきい値による自動コメント | 次に何を見るべきか | 先生からのひとこと |

### watch の実例（推移）

**jbpool watch 5**

```text
--- 2026-10-17 07:02:34 JST  #1  back  (WildFly 41.0.1.Final, running)  idle-check<=1m30s ---
DATASOURCE           STATUS         USE/MAX  USE%  ACT IDLE   NEW   DEL   T/O  WAIT TMOUT QUEUE  MAXU  AVGGET
ExampleDS            OK                 0/3    0%    0    0     -     -     -     -     -     0     3    48ms
--- 2026-10-17 07:02:41 JST  #2  back  (WildFly 41.0.1.Final, running)  idle-check<=1m30s ---
DATASOURCE           STATUS         USE/MAX  USE%  ACT IDLE   NEW   DEL   T/O  WAIT TMOUT QUEUE  MAXU  AVGGET
ExampleDS            OVERFLOW           3/3  100%    3    0    +3    -0    -0    +3    +0     3     3    38ms
   queue  : 3 waiting -> all resolved by <= 07:02:51 : default task-21 (<=07:02:51), default task-22 (<=07:02:51), default task-23 (<=07:02:51)
   event | pool grew 0->3 (+3 created) | 3 request(s) had to wait
--- 2026-10-17 07:02:47 JST  #3  back  (WildFly 41.0.1.Final, running)  idle-check<=1m30s ---
DATASOURCE           STATUS         USE/MAX  USE%  ACT IDLE   NEW   DEL   T/O  WAIT TMOUT QUEUE  MAXU  AVGGET
ExampleDS            FULL+TMOUT         3/3  100%    3    0    +0    -0    -0    +0    +3     0     3    38ms
   event | 3 TIMEOUT error(s) IJ000655
--- 2026-10-17 07:02:54 JST  #4  back  (WildFly 41.0.1.Final, running)  idle-check<=1m30s ---
DATASOURCE           STATUS         USE/MAX  USE%  ACT IDLE   NEW   DEL   T/O  WAIT TMOUT QUEUE  MAXU  AVGGET
ExampleDS            FULL               3/3  100%    3    0    +0    -0    -0    +0    +0     0     3    38ms
--- 2026-10-17 07:03:00 JST  #5  back  (WildFly 41.0.1.Final, running)  idle-check<=1m30s ---
DATASOURCE           STATUS         USE/MAX  USE%  ACT IDLE   NEW   DEL   T/O  WAIT TMOUT QUEUE  MAXU  AVGGET
ExampleDS            OK                 2/3   66%    3    1    +0    -0    -0    +0    +0     0     3    38ms
   idle   : 1 idle conn above floor 2 (3->2) -> closing ~07:03:54 .. 07:05:30 (est.)
--- 2026-10-17 07:03:07 JST  #6  back  (WildFly 41.0.1.Final, running)  idle-check<=1m30s ---
DATASOURCE           STATUS         USE/MAX  USE%  ACT IDLE   NEW   DEL   T/O  WAIT TMOUT QUEUE  MAXU  AVGGET
ExampleDS            OK                 0/3    0%    3    3    +0    -0    -0    +0    +0     0     3    38ms
   idle   : 3 idle conn above floor 0 (3->0) -> closing ~07:03:54 .. 07:05:37 (est.)
   ...（1 回分 省略）...
--- 2026-10-17 07:03:20 JST  #8  back  (WildFly 41.0.1.Final, running)  idle-check<=1m30s ---
DATASOURCE           STATUS         USE/MAX  USE%  ACT IDLE   NEW   DEL   T/O  WAIT TMOUT QUEUE  MAXU  AVGGET
ExampleDS            OK                 0/3    0%    3    3    +0    -0    -0    +0    +0     0     3    36ms
   idle   : 3 idle conn above floor 0 (3->0) -> closing ~07:03:54 .. 07:05:50 (est.)
   ...（6 回分 省略）...
--- 2026-10-17 07:04:05 JST  #15  back  (WildFly 41.0.1.Final, running)  idle-check<=1m30s ---
DATASOURCE           STATUS         USE/MAX  USE%  ACT IDLE   NEW   DEL   T/O  WAIT TMOUT QUEUE  MAXU  AVGGET
ExampleDS            OK                 0/3    0%    3    3    +0    -0    -0    +0    +0     0     3    36ms
   idle   : 3 idle conn above floor 0 (3->0) -> closing ~07:03:54 .. 07:05:50 (est.)
--- 2026-10-17 07:04:12 JST  #16  back  (WildFly 41.0.1.Final, running)  idle-check<=1m30s ---
DATASOURCE           STATUS         USE/MAX  USE%  ACT IDLE   NEW   DEL   T/O  WAIT TMOUT QUEUE  MAXU  AVGGET
ExampleDS            OK                 0/3    0%    2    2    +0    -1    -1    +0    +0     0     3    36ms
   idle   : 2 idle conn above floor 0 (2->0) -> closing ~07:04:00 .. 07:05:50 (est.)
   event | 1 closed by idle-timeout
   ...（12 回分 省略）...
--- 2026-10-17 07:05:37 JST  #29  back  (WildFly 41.0.1.Final, running)  idle-check<=1m30s ---
DATASOURCE           STATUS         USE/MAX  USE%  ACT IDLE   NEW   DEL   T/O  WAIT TMOUT QUEUE  MAXU  AVGGET
ExampleDS            OK                 0/3    0%    2    2    +0    -0    -0    +0    +0     0     3    36ms
   idle   : 2 idle conn above floor 0 (2->0) -> closing ~07:04:00 .. 07:05:50 (est.)
--- 2026-10-17 07:05:47 JST  #30  back  (WildFly 41.0.1.Final, running)  idle-check<=1m30s ---
DATASOURCE           STATUS         USE/MAX  USE%  ACT IDLE   NEW   DEL   T/O  WAIT TMOUT QUEUE  MAXU  AVGGET
ExampleDS            OK                 0/3    0%    0    0    +0    -2    -2    +0    +0     0     3    36ms
   event | 2 closed by idle-timeout
   ...（3 回分 省略）...
--- 2026-10-17 07:06:15 JST  #34  back  (WildFly 41.0.1.Final, running)  idle-check<=1m30s ---
DATASOURCE           STATUS         USE/MAX  USE%  ACT IDLE   NEW   DEL   T/O  WAIT TMOUT QUEUE  MAXU  AVGGET
ExampleDS            OK                 0/3    0%    0    0    +0    -0    -0    +0    +0     0     3    36ms
```

> **補足**　読み方の例：#2 で一気に 3 本作られ（pool grew 0->3）、3 件が並び、#3 で 3 件がタイムアウト（TMOUT +3）。負荷が終わると idle 行に片付け予定が出ます。07:03:15〜18 に 3 秒だけ 2 本が使われましたが、観測と観測のあいだだったため USE には出ていません。jbpool は TotalUsageTime の増加から「見えない返却」を検知し、遅くともの時刻を 07:05:37 → 07:05:50 に自動で後ろへずらしています。実際の片付けは 07:04:05〜12 に 1 本、07:05:37〜47 に 2 本で、予定どおりでした。

### watch の列の意味

| 列 | 元データ | 意味 | 見るポイント |
|---|---|---|---|
| USE/MAX | InUseCount ／ max-pool-size | 貸し出し中 ／ 上限 | 上限に張り付いていないか |
| USE% | InUseCount ÷ max-pool-size | 使用率 | JBP_WARN（既定 80%）以上で BUSY |
| ACT／IDLE | ActiveCount／IdleCount | 合計本数／休み中の本数 | IDLE が多いまま → 片付け予定を見る |
| NEW | CreatedCount の増分 | 前回から新しく作った本数（プールの追加） | 急に増える＝負荷の山 |
| DEL | DestroyedCount の増分 | 前回から捨てた本数 | T/O 以外の DEL は検証失敗やフラッシュ |
| T/O | TimedOut の増分 | アイドルタイムアウトで片付けた本数 | 片付け予定どおりか |
| WAIT | WaitCount の増分 | 待たされたリクエスト数 | 0 でないなら一瞬でもあふれた |
| TMOUT | BlockingFailureCount の増分 | 待ちきれずエラーになった数 | 1 以上は利用者に影響あり |
| QUEUE | dump-queued-threads-in-pool の件数 | いま並んでいる数（n/a は操作が使えない版） | 1 以上＝あふれ中 |
| MAXU | MaxUsedCount | これまでの最大同時使用数 | max-pool-size に届いたか |
| AVGGET | AverageGetTime | 接続を借りるまでの平均時間 | 伸びてきたら要注意 |
| queue 行 | スレッド名ごとの初回観測時刻＋待てる最大時間 | 全員が遅くともいつまでに解消するか |  |
| idle 行 | 使用数の履歴＋idle-timeout＋見回り間隔 | 余った接続が何時ごろ片付くか（est.＝推定） |  |
| event 行 | 上の増分の文章化 | pool grew（追加）／closed by idle-timeout（片付け）／TIMEOUT error など |  |

### STATUS 一覧

| STATUS | 条件 | 意味 | こども向け |
|---|---|---|---|
| OK | 下のどれにも当てはまらない | ふつう | 晴れ |
| BUSY | 使用率 ≥ JBP_WARN（既定 80%） | 混んできた | くもり |
| FULL | InUseCount ≥ max-pool-size | 満杯（次に来たら並ぶ） | 傘が全部出払った |
| OVERFLOW | 待ちスレッドが 1 以上 | あふれ中 | 列ができている |
| ＋TMOUT | 前回からタイムアウトが増えた（watch／csv） | 誰かがエラーになった | 傘をもらえず帰った子がいる |
| STATS-OFF | statistics-enabled が false | 数値が記録されていない（0 に見える） | ノートを付けていない |
| DISABLED | データソースが無効（enabled=false） | 使われていない | 傘立てが閉まっている |

### CSV の列

| 列 | 意味 |
|---|---|
| date,time,epoch | 観測した日付・時刻（TZ に従う）・UNIX 秒 |
| label,datasource,status | コンテナ名・データソース名・STATUS |
| active,in_use,idle,max,available | 合計・使用中・休み・上限・まだ貸せる枠 |
| created,destroyed,timed_out,wait_count,blocking_failures | 累計値（差を取ると増分） |
| queued,max_used,max_wait_count,max_wait_ms | 待ち件数・最大同時使用・最大同時待ち・最大待ち時間 |
| avg_get_ms,max_get_ms,avg_usage_ms | 借りるまでの平均・最大、使用時間の平均 |
| idle_release_from,idle_release_by | 余った接続の片付け予定（早ければ／遅くとも） |
| queue_resolved_by | 待ち行列が遅くとも解消する時刻 |

**CSV の実例（先頭）**

```csv
date,time,epoch,label,datasource,status,active,in_use,idle,max,available,created,destroyed,timed_out,wait_count,blocking_failures,queued,max_used,max_wait_count,max_wait_ms,avg_get_ms,max_get_ms,avg_usage_ms,idle_release_from,idle_release_by,queue_resolved_by
2026-10-17,07:02:34,1792188154,back,ExampleDS,OK,0,0,0,3,3,12,12,12,12,12,0,3,3,1,48,189,16834,,,
2026-10-17,07:02:41,1792188161,back,ExampleDS,OVERFLOW,3,3,0,3,0,15,12,12,15,12,3,3,3,1,38,189,16834,,,07:02:51
2026-10-17,07:02:47,1792188167,back,ExampleDS,FULL+TMOUT,3,3,0,3,0,15,12,12,15,15,0,3,3,1,38,189,16834,,,
2026-10-17,07:02:54,1792188174,back,ExampleDS,FULL,3,3,0,3,0,15,12,12,15,15,0,3,3,1,38,189,16834,,,
2026-10-17,07:03:00,1792188180,back,ExampleDS,OK,3,2,1,3,1,15,12,12,15,15,0,3,3,1,38,189,17263,07:03:54,07:05:30,
2026-10-17,07:03:07,1792188187,back,ExampleDS,OK,3,0,3,3,3,15,12,12,15,15,0,3,3,1,38,189,18000,07:03:54,07:05:37,
2026-10-17,07:03:13,1792188193,back,ExampleDS,OK,3,0,3,3,3,15,12,12,15,15,0,3,3,1,38,189,18000,07:03:54,07:05:37,
```

### threads の実例（どこで待っているか）

**jbpool threads（先頭のみ）**

```text
[jbpool] target=2d260dddc5a0  controller=remote+http://127.0.0.1:10090  cli=/opt/jboss/wildfly/bin/jboss-cli.sh  server-pid=125
===== data-source ExampleDS : threads waiting for a connection =====
{
    "outcome" => "success",
    "result" => [
        "Queued thread: default task-23
  jdk.internal.misc.Unsafe:park:-2
  java.util.concurrent.locks.LockSupport:parkNanos:271
  java.util.concurrent.locks.AbstractQueuedSynchronizer:acquire:792
  java.util.concurrent.locks.AbstractQueuedSynchronizer:tryAcquireSharedNanos:1166
  java.util.concurrent.Semaphore:tryAcquire:415
  org.jboss.jca.core.connectionmanager.pool.api.Semaphore:tryAcquire:76
  org.jboss.jca.core.connectionmanager.pool.mcp.SemaphoreConcurrentLinkedDequeManagedConnectionPool:getConnection:348
  org.jboss.jca.core.connectionmanager.pool.AbstractPool:getSimpleConnection:688
  org.jboss.jca.core.connectionmanager.pool.AbstractPool:getConnection:653
  org.jboss.jca.core.connectionmanager.AbstractConnectionManager:getManagedConnection:624
  org.jboss.jca.core.connectionmanager.tx.TxConnectionManagerImpl:getManagedConnection:440
  org.jboss.jca.core.connectionmanager.AbstractConnectionManager:allocateConnection:789
  org.jboss.jca.adapters.jdbc.WrapperDataSource:getConnection:152
  org.jboss.as.connector.subsystems.datasources.WildFlyDataSource:getConnection:47
  org.apache.jsp.hold_jsp:_jspService:107
  org.apache.jasper.runtime.HttpJspBase:service:70
  jakarta.servlet.http.HttpServlet:service:723
  org.apache.jasper.servlet.JspServletWrapper:service:428
```

> **補足**　上の例では、hold_jsp（テスト用の JSP）が DataSource.getConnection() を呼び、IronJacamar の Semaphore.tryAcquire で待っていることがわかります。本番では、ここにアプリのクラス名とメソッド名が出るので「どの処理が接続を待っているか」を特定できます。

---

## 7. 「タイムアウトにより解消する予定の時刻」の計算方法

> jbpool が表示する予定時刻は 2 種類です。① 並んでいるリクエストがいなくなる時刻（待ちのタイムアウト）、② 余った接続が片付けられる時刻（アイドルタイムアウト）。どちらも JBoss の設定値と、IronJacamar（プールの本体）の実際のソースコードの動きにもとづいて計算しています。

### ① 待ちの解消予定（遅くとも）

| ことば | 式 | 説明 |
|---|---|---|
| 待てる最大時間 W（ms） | blocking-timeout-wait-millis ×（allocation-retry ＋ 1）＋ allocation-retry-wait-millis × allocation-retry | 既定は 30000 ×（0＋1）＋ 0 ＝ 30 秒。リトライ設定があると、その回数ぶん長くなる |
| 初回観測時刻 F | そのスレッド名を待ち行列で最初に見た時刻 | 実際に並び始めたのは F と同じかそれより前 |
| 解消予定（遅くとも） | F ＋ W | この時刻までに「接続を得る」か「IJ000655 でエラー」のどちらかになり、行列からいなくなる（上限） |

根拠：IronJacamar は Semaphore.tryAcquire(blocking-timeout) で空きを待ち、時間切れなら例外を投げます（threads の出力にも Semaphore.tryAcquire が出ます）。pool-fair（既定 true）なので、待っている順番どおりに空きが割り当てられます。

### ② アイドル接続の片付け予定（推定）

| ことば | 式 | 説明 |
|---|---|---|
| 見回り間隔 S | （全プールの idle-timeout-minutes の最小値）× 60 ÷ 2 秒 | IdleRemover（片付け係）が起きる間隔。JVM 全体で 1 つ |
| 1 プールの最大チェック間隔 K | S ＞ 60 秒なら S、そうでなければ S ×（INT(60 ÷ S) ＋ 1） | 既定の TimedOutDecrementer は 1 プールを「1 分に 1 回まで」しか調べない（例：S＝30 秒 → K＝90 秒） |
| 残る本数（床） | pool-prefill か pool-use-strict-min が true なら MAX(min-pool-size, 使用中)、どちらも false なら 使用中 | どちらも false だと min-pool-size は守られず 0 本まで減る（実機とソースで確認） |
| 片付け対象 | ActiveCount − 残る本数 | これが 0 なら片付けは起きない |
| 最後に使用中だった時刻 U | watch で「使用中がその段数以上」だった最後の観測時刻 | LIFO（新しく返された接続から貸す）なので、上の段（たくさん同時に使われたときだけ使う接続）ほど長く休んでいる |
| 返却ずみの時刻 R | その段が「使用中でない」と初めて観測された時刻。さらに TotalUsageTime（返却のたびに増える累計）が増えていたら、その観測時刻も R の候補にする | 観測のすき間で一瞬だけ使われて返された接続も取りこぼさないため（検証で見つけて改良） |
| 片付け予定（早ければ） | いちばん古い U ＋ idle-timeout | これより前には閉じられない（下限） |
| 片付け予定（遅くとも） | いちばん新しい R ＋ idle-timeout ＋ K | 見回りのタイミングのずれまで含めた上限（安全側） |
| snapshot のとき | 今 ＋ idle-timeout ＋ K（遅くとも） | 過去の使用履歴が無いので「この先使われなければ遅くともこの時刻まで」 |

根拠（IronJacamar のソースコード）：借りるときは deque の後ろから取り出し（pollLast）、返すときは後ろに戻す（addLast）＝ LIFO。片付け（removeIdleConnections）は先頭＝いちばん古い接続から順に調べ、タイムアウトしていない接続に当たったら止まります。また「now < lastIdleCheck + 60000 ならスキップ」という 1 分制限があり、片付け後に min-pool-size まで補充（prefill）するのは pool-prefill か pool-use-strict-min が true のときだけです。

> **補足**　推定には限界があります：観測と観測のあいだに一瞬だけ使われた接続は見えません。また background-validation（定期検証）が ON だと、検証のために接続が並び替わることがあります。「遅くとも」の時刻は安全側（遅め）に計算しています。

### 計算シート（Excel 版のみ：白い枠のセルを書きかえると、灰色のセルが自動で計算されます）

| 項目 | 値（例） | 計算式・説明 |
|---|---|---|
| **① 待ちの解消予定（遅くとも）** | | |
| 初回観測時刻 F | 07:02:41 | 入力　jbpool の queue 行に、そのスレッドが初めて出た時刻 |
| blocking-timeout-wait-millis | 10000 | 入力　config 行の値（未設定なら 30000） |
| allocation-retry | 0 | 入力　未設定なら 0 |
| allocation-retry-wait-millis | 0 | 入力　未設定なら 0 |
| 待てる最大時間 W（秒） | 10 | =(BT*(AR+1)+ARW*AR)/1000　BT ×（AR＋1）＋ ARW × AR をミリ秒→秒に |
| 解消予定（遅くとも） | 07:02:51 | =F+W/86400　この時刻までに、接続を得るか IJ000655 でエラーになる |
| **② アイドル接続の片付け予定** | | |
| 最後に使用中だった時刻 U（いちばん古いもの） | 07:02:54 | 入力　watch で、片付け対象の段が最後に使用中だった時刻 |
| 返却ずみの時刻 R（いちばん新しいもの） | 07:03:20 | 入力　使用中でないと初めて見えた時刻／TotalUsageTime が増えた観測時刻 |
| idle-timeout-minutes（このプール） | 1 | 入力　未設定なら 30 |
| idle-timeout-minutes（全プールの最小） | 1 | 入力　IdleRemover は JVM に 1 つ。いちばん短い設定に合わせて起きる |
| 見回り間隔 S（秒） | 30 | =ITMIN*60/2　最小 idle-timeout の半分 |
| 1 プールの最大チェック間隔 K（秒） | 90 | =IF(S>60,S,S*(INT(60/S)+1))　1 プールは 1 分に 1 回までしか調べられないため |
| 片付け予定（早ければ） | 07:03:54 | =U+IT*60/86400　これより前には閉じられない |
| 片付け予定（遅くとも） | 07:05:50 | =R+(IT*60+KK)/86400　見回りのずれまで含めた上限 |
| **③ 片付けたあとに残る本数** | | |
| min-pool-size | 1 | 入力 |
| pool-prefill（TRUE／FALSE） | FALSE | 入力 |
| pool-use-strict-min（TRUE／FALSE） | FALSE | 入力 |
| いまの使用中 InUseCount | 0 | 入力 |
| いまの合計 ActiveCount | 3 | 入力 |
| 残る本数（床） | 0 | =IF(OR(PF,SM),MAX(MN,USE),USE)　prefill も strict-min も FALSE なら min-pool-size は守られない |
| 片付け対象の本数 | 3 | =MAX(0,ACT-FL) |

### 実機での答え合わせ

| 項目 | 予定（jbpool の表示） | 実際 |
|---|---|---|
| 待ちの解消 | 初回観測 07:02:41 ＋ 待てる最大時間 10 秒 → 遅くとも 07:02:51 | 3 件とも 10,000〜10,001 ms 待って IJ000453 で終了（07:02:47〜48 ごろ）。予定内 |
| アイドル片付け | 早ければ 07:03:54（最後に使用中 07:02:54 ＋ 1 分）／遅くとも 07:05:50（07:03:15〜18 のすき間利用を TotalUsageTime で検知 → 07:03:20 ＋ 1 分 ＋ K 90 秒） | 1 本目は 07:04:05〜12、残り 2 本は 07:05:37〜47 に片付け（3→0）。予定内 |
| 改良前との比較 | 1 回目の検証では、すき間利用を見落として「遅くとも 06:58:02」と表示 | 実際は 06:58:03〜11 に片付け（数秒の超過）→ TotalUsageTime による検知を追加して上の結果に |
| min-pool-size | min=1 でも prefill／strict-min が false | 0 本まで減った（ソースコードどおり） |

---

## 8. 検証結果 ― 実際に動かして確かめたこと

> EAP そのものではなく、上流の WildFly 41.0.1.Final（EAP 8 系と同じ管理モデル・同じ IronJacamar 系統）で検証しました。EAP の本番に入れる前に、検証環境で一度 snapshot を実行して表示を確認することをおすすめします。

### 検証環境

| 項目 | 内容 |
|---|---|
| ホスト | Windows 11 ＋ Docker Desktop（Docker Engine 29.8.1） |
| イメージ | quay.io/wildfly/wildfly:latest → WildFly 41.0.1.Final（WildFly Core 33.0.1.Final）、RHEL 10.2 ベース |
| 構成 | front と back の 2 コンテナ。back は network_mode: service:front（ECS の awsvpc と同じく localhost を共有）＋ -Djboss.socket.binding.port-offset=100 |
| データソース | ExampleDS（H2）。back は max-pool-size=3／min-pool-size=1／idle-timeout-minutes=1／blocking-timeout-wait-millis=10000 に変更、front は既定値 |
| 負荷のかけ方 | 接続を指定秒つかんだまま待つテスト用 JSP（hold.jsp）に、同時に 6 本リクエスト |
| シェル／awk | bash（対話モード・履歴展開あり）、sh、dash、BusyBox ash ／ gawk、mawk、BusyBox awk |

### 検証項目と結果

| 検証項目 | やったこと | 結果 | 判定 |
|---|---|---|---|
| 管理ポートの自動判別 | 同じネットワークを共有する front／back で snapshot | front は 9990、back は 10090（9990＋100）に自動接続 | OK |
| 統計 OFF の検出と ON | 初期状態で snapshot → enable-stats | STATS-OFF 表示 → 実行時属性（storage=runtime）として即 true | OK |
| プール設定の変更 | max-pool-size などを write-attribute | WildFly 41 では process-state=reload-required（＝本番では気軽に変えない） | 確認 |
| あふれの検出 | max 3 に 6 本同時 | STATUS=OVERFLOW、QUEUE=3、待ちスレッド名（default task-◯）を表示 | OK |
| 待ちの解消予定 | 初回観測＋待てる最大時間を表示 | 予定 07:02:51 に対し、3 本が 10,000〜10,001 ms で IJ000453 終了（07:02:48 ごろ、予定内） | OK |
| タイムアウトの検出 | watch の増分 | TMOUT +3、STATUS=FULL+TMOUT、event に「3 TIMEOUT error(s)」 | OK |
| アイドル片付けの予定 | 負荷のあと放置（途中 07:03:15 に 3 秒だけ 2 本使う） | 予定 07:03:54〜07:05:50 に対し、07:04:05〜12 に 1 本、07:05:37〜47 に 2 本片付け | OK |
| 観測のすき間の利用 | サンプルとサンプルのあいだだけ接続を使う | 1 回目は予定 06:58:02 を数秒超過 → TotalUsageTime の増加で「見えない返却」を検知する改良を入れ、再検証で予定内に | 改良済 |
| min-pool-size の扱い | min=1・prefill=false・strict-min=false | 0 本まで減少 → 表示とアドバイスを実装に合わせて修正済み | OK |
| 待ち場所の特定 | jbpool threads | hold_jsp → WrapperDataSource.getConnection → Semaphore.tryAcquire のスタックを表示 | OK |
| CSV 出力 | JBP_CSV と csv モード | ヘッダー 1 回＋1 観測 1 行で追記 | OK |
| 貼り付け安全性 | 対話 bash（履歴展開 ON）に全文を流し込み、続けて watch／csv／help | 「event not found」などのエラーなし。最後に snapshot が自動実行 | OK |
| awk の互換性 | 同じ生データを gawk／mawk／BusyBox awk で表示 | 3 つとも同じ表示（同時刻のスレッド名の並び順だけ差） | OK |
| シェルの互換性 | dash -n／BusyBox sh -n | 構文エラーなし | OK |
| 機密情報を読まない | raw 出力を password／user-name／connection-url で検索 | 0 件（属性を個別に読む設計のため） | OK |
| CLI の使用メモリ | CLI 実行中の RSS を測定 | 隔離設定で約 119 MB、サーバーの -Xms1g を引き継ぐと約 217 MB → 隔離が有効 | OK |
| メモリ不足時の停止 | 上限 700 MB のコンテナで JBP_MIN_FREE_MB を大きくして実行 | 「STOP: headroom …」で停止、JBP_FORCE=1 で実行可 | OK |
| 接続失敗時のヒント | MGMT_PORT=19999 で実行 | 接続失敗の内容と「port-offset を確認」のヒントを表示 | OK |

> **補足**　所要時間：CLI は 1 回あたり JVM を起動するため 2〜3 秒かかります（snapshot は 2 回起動で約 5 秒）。watch の実際の間隔は「指定秒＋約 2〜3 秒」になります。

---

## 9. 注意点とトラブル対応

| 症状・注意 | 原因 | 対処 |
|---|---|---|
| Failed to connect to the controller | 管理ポートが違う（同じタスク内の 2 台目は port-offset でずれている）／管理インターフェースが別アドレス | MGMT_PORT=10090 jbpool のように指定。表示される controller= を確認 |
| Authentication failed などの認証エラー | ローカル（サイレント）認証が使えない：別ユーザーで入った、設定で無効化されている | root かサーバーと同じユーザーで実行。だめなら CLI_USER／CLI_PASS（ログに残る点に注意） |
| STATUS が STATS-OFF・数字が 0 | statistics-enabled が false（既定） | jbpool enable-stats（再起動で戻る）。恒久的には -Dwildfly.datasources.statistics-enabled=true で起動（式を使っているデータソースの場合）か、データソースの属性を true にして reload |
| STOP: container memory headroom | コンテナのメモリ上限に余裕がない（CLI 用 JVM は約 120〜150 MB） | ほかの方法（別コンテナから CONTROLLER 指定・ログ確認）を検討。どうしても必要なら JBP_FORCE=1 |
| jboss-cli.sh not found | インストール先が標準と違う | JBOSS_HOME=/path/to/eap jbpool |
| no writable temp directory | 読み取り専用ルート FS で /tmp なども書けない | 書き込めるボリュームを TMPDIR=/path で指定 |
| WARNING: 2 JBoss servers are visible | pidMode=task などで他コンテナのプロセスも見えている | 表示される controller が目的のサーバーか確認。違えば MGMT_PORT を指定 |
| queue が n/a | 古い版で dump-queued-threads-in-pool が使えない | WAIT／TMOUT の増分と IJ000655 ログで判断 |
| 貼り付けが途中で切れる・文字化け | 端末やセッションの貼り付け上限 | PART 1/3・2/3・3/3 の区切りごとに貼る／Compose なら sh -s < jbpool.sh／/tmp に保存して実行 |
| sh: $'\r': command not found | ファイルが CRLF で保存された | LF で保存し直す（エディタの改行コード設定） |
| 時刻が 9 時間ずれる | コンテナが UTC | TZ=JST-9 jbpool …（tzdata が無くても使える書き方） |
| ActiveCount がマイナス・不自然 | 統計の ON/OFF やフラッシュ直後の既知の数え方の問題（JBEAP-1745） | jbpool は in-use＋idle で補正して表示し、advice に注記 |
| ドメインモード | /host=…/server=… の階層になる | このコマンドは standalone 専用（ECS／Compose ではほぼ standalone） |
| EAP 6 | 管理ポート 9999（remote://）で、操作や属性も一部ちがう | CONTROLLER=remote://127.0.0.1:9999 で動く可能性はあるが対象外 |

### 安全のための設計

- 読み取り専用：enable-stats／disable-stats 以外は管理モデルを読むだけです（Red Hat も OpenShift 上の EAP では CLI での設定変更を推奨していません）。
- 機密を読まない：データソースの属性は名前を指定して 1 つずつ読み、password・user-name・connection-url は読みません。
- 小さな JVM：CLI 用の JVM には -Xmx128m などを明示し、JAVA_TOOL_OPTIONS（監視エージェントなど）を引き継ぎません。
- 止まっても安全：exit を使わず return で終わるので、貼り付けたシェル（ECS Exec のセッション）が閉じません。timeout コマンドがあれば CLI が固まっても 90 秒で打ち切ります。
- 貼り付け安全：ASCII のみ・タブなし・履歴展開文字（! の後ろに文字）なし・CR なし、を自動チェック済みです。

### 統計を恒久的に ON にする方法（参考）

**JBoss CLI（反映には reload が必要。コンテナでは再作成で消えるため、イメージ作成時に入れるのが確実）**

```bash
/subsystem=datasources/data-source=ExampleDS:write-attribute(name=statistics-enabled,value=true)
:reload
```

**起動オプションで（データソースが ${wildfly.datasources.statistics-enabled:...} の式を使っている場合）**

```bash
-Dwildfly.datasources.statistics-enabled=true
# Red Hat の EAP コンテナイメージなら例えば：JAVA_OPTS_APPEND=-Dwildfly.datasources.statistics-enabled=true
```

> **補足**　統計の収集にはわずかな負荷があります。常時 ON にするかはチームで決めてください。障害調査のときだけ enable-stats で一時的に ON にする運用もできます。

---

## 10. 用語集

| 用語 | 意味 | こども向け |
|---|---|---|
| JBoss EAP | Red Hat がサポートする Java（Jakarta EE）のアプリケーションサーバー。上流は WildFly | アプリを動かすお店の建物 |
| WildFly | JBoss EAP のもとになっているコミュニティ版 | お店の試作品 |
| データソース（DataSource） | アプリがデータベースの接続を借りる窓口。プールを持つ | 傘の貸し出し窓口 |
| XA データソース | 複数の資源にまたがるトランザクション用のデータソース | 2 つのお店で同時に約束するための窓口 |
| IronJacamar（IJ） | JBoss のプールの本体（JCA 実装）。メッセージ ID の IJ の由来 | 傘立てを作った会社 |
| JCA | Java のコネクタ標準。プール・トランザクション・セキュリティを扱う | 傘立ての共通ルール |
| 管理モデル | JBoss の設定と状態の木構造。/subsystem=datasources/… のように住所で指す | お店の案内図 |
| JBoss CLI | 管理モデルを読み書きするコマンド（jboss-cli.sh） | 管理人さんのトランシーバー |
| ローカル（サイレント）認証 | 同じマシン（コンテナ）内からなら、パスワードなしで CLI が接続できるしくみ | 合言葉なしで入れる職員通用口 |
| port-offset | すべてのポート番号をまとめてずらす設定（9990→10090 など） | 部屋番号を全部 100 ずらす |
| awsvpc | ECS のネットワークモード。同じタスクのコンテナは localhost を共有する | 同じ建物で電話番号を共有 |
| ECS Exec | ECS のコンテナの中でコマンドを実行する機能（SSM Session Manager を利用） | 遠くのお店の合鍵 |
| Docker Compose | 複数のコンテナを YAML で定義してまとめて動かす道具 | お店の模型セット |
| statistics（統計） | プールの数値（使用中・待ち・タイムアウトなど）の記録 | 貸し出しノート |
| blocking-timeout-wait-millis | 空きを待てる最大時間（ms）。既定 30000 | 並んで待てる時間 |
| idle-timeout-minutes | 使われていない接続を閉じるまでの時間（分）。既定 30 | 傘を片付けるまでの時間 |
| IdleRemover | アイドル接続を片付けるバックグラウンド処理 | 見回りの用務員さん |
| TimedOutDecrementer | 既定の片付けルール。タイムアウトした接続を閉じ、1 プールは 1 分に 1 回まで | 見回りのルール |
| LIFO | Last In, First Out。最後に返したものから先に使う | さっき返された傘から貸す |
| pool-prefill | 起動時などに min-pool-size まで先に作っておく | 朝のうちに傘を並べておく |
| pool-use-strict-min | min-pool-size を下回らないように厳しく守る | 最低本数は絶対に片付けない |
| pool-fair | 待っている順番どおりに空きを渡す（既定 true） | 並んだ順に渡す |
| コネクションリーク | アプリが接続を返し忘れること | 傘の返し忘れ |
| スレッドダンプ | JVM の全スレッドがいま何をしているかの一覧 | 全員の「いま何してる？」アンケート |
| cgroup | Linux がコンテナのメモリなどを制限するしくみ | お店の広さの上限 |

---

## 11. 参考資料（出典）

| 資料 | URL | 使ったところ |
|---|---|---|
| Red Hat: EAP 7.3 Performance Tuning Guide - Datasource and Resource Adapter Tuning | https://docs.redhat.com/documentation/en-us/red_hat_jboss_enterprise_application_platform/7.3/html/performance_tuning_guide/datasource_and_resource_adapter_tuning | 統計の有効化（reload 要）、max-pool-size は MaxUsedCount の 15% 増し以上 |
| Red Hat: EAP 7.1 Performance Tuning Guide - Reference Material（Datasource Statistics） | https://docs.redhat.com/documentation/en-us/red_hat_jboss_enterprise_application_platform/7.1/html/performance_tuning_guide/reference_material | 各統計項目（ActiveCount など）の定義 |
| WildFly Model Reference: data-source | https://docs.wildfly.org/28/wildscribe/deployment/subsystem/datasources/data-source/index.html | dump-queued-threads-in-pool などの操作、idle-timeout の説明 |
| IronJacamar ソースコード（GitHub） | https://github.com/ironjacamar/ironjacamar | LIFO（pollLast／addLast）、removeIdleConnections、1 分制限、prefill 条件、IdleRemover の間隔 |
| WFLY-3084（statistics-enabled を設定属性に） | https://lists.jboss.org/pipermail/jboss-jira/2014-July/261114.html | statistics-enabled の歴史 |
| JBEAP-1745（ActiveCount がマイナスになる件） | https://issues.redhat.com/browse/JBEAP-1745 | 数値の補正表示 |
| Red Hat Developer: JBoss EAP 8.1（2025/9/2） | https://developers.redhat.com/blog/2025/09/02/jboss-eap-81-modernizing-enterprise-java-applications | EAP 8.1 の提供開始 |
| Red Hat: EAP 8 Supported Configurations | https://access.redhat.com/articles/6961381 | EAP 8.0 Update 12 が最終・8.1 への移行 |
| Red Hat: JBoss EAP 7 ELS Availability | https://access.redhat.com/articles/7116565 | EAP 7.4 の延長サポート |
| endoflife.date: Red Hat JBoss EAP | https://endoflife.date/redhat-jboss-eap | 各版のサポート期限（第三者まとめ） |
| Red Hat Developer: How JBoss EAP 8 Beta makes deployment on OpenShift easier | https://developers.redhat.com/articles/2023/02/08/how-jboss-eap-8-beta-makes-deployment-openshift-easier | EAP 8 イメージの JBOSS_HOME＝/opt/server |
| AWS What's New: ECS Exec is now available in the AWS Management Console（2025/9/4） | https://aws.amazon.com/about-aws/whats-new/2025/09/ecs-exec-aws-management-console/ | コンソールからの ECS Exec |
| AWS: Monitor Amazon ECS containers with ECS Exec | https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs-exec.html | ECS Exec の前提・権限 |
| AWS: Task metadata endpoint version 4 | https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task-metadata-endpoint-v4.html | コンテナ名の自動取得 |
| aws-containers/amazon-ecs-exec-checker | https://github.com/aws-containers/amazon-ecs-exec-checker | ECS Exec の診断 |
| Docker Docs: docker compose exec | https://docs.docker.com/reference/cli/docker/compose/exec/ | -T・-e オプション |
| Docker Docs: Migrate to Compose V2 | https://docs.docker.com/compose/releases/migrate/ | Compose V1 のサポート終了 |

> **補足**　年表の一部（JDBC・J2EE・JBoss・ECS・Fargate などの古い年）は、一般に知られている公開情報をもとに記載しています。正確な日付が必要な場合は各公式発表を確認してください。

---

## 12. jbpool.sh 全文

> C 列だけを縦に選んでコピーすると、そのまま貼り付けられます（B 列の行番号は含めないでください）。いちばん確実なのは jbpool.sh ファイルを使うことです。

```bash
# =============================================================================
# jbpool.sh : JBoss EAP / WildFly datasource connection-pool inspector
#   Paste ALL of this text into the shell of the container
#   (ECS Exec / docker compose exec). A snapshot runs right after the paste.
#   After that you can type:
#     jbpool                  snapshot (detailed report, once)
#     jbpool watch 10         trend every 10 sec (Ctrl+C to stop)
#     jbpool csv 10 360 > /tmp/pool.csv   CSV for Excel
#     jbpool threads          stack traces of threads waiting for a connection
#     jbpool enable-stats     turn statistics on (runtime only)
#     jbpool help
#   Read-only, except enable-stats / disable-stats.
#   Optional env: JBOSS_HOME MGMT_HOST MGMT_PORT CONTROLLER CLI_USER CLI_PASS
#                 JBP_LABEL JBP_WARN JBP_CSV JBP_JAVA_OPTS JBP_MIN_FREE_MB JBP_FORCE
#                 TZ (e.g. TZ=JST-9)
#   ASCII only / no TAB / no history-expansion chars: safe to paste.
#   Long paste may be cut in some terminals: then paste PART 1, 2, 3 one by one.
# =============================================================================
# ---------------------------------------------------------------- PART 1/3 : functions
case $- in *H*) set +H ;; esac

jbp_help() {
  cat <<'JBP_HELP'
jbpool - JBoss EAP / WildFly datasource connection-pool inspector
  jbpool                    snapshot : detailed report (once)
  jbpool watch [sec] [n]    trend    : every sec (default 10), n times (0 = until Ctrl+C)
  jbpool csv   [sec] [n]    CSV      : same as watch, CSV lines for Excel
  jbpool threads            stack traces of threads queued for a connection
  jbpool enable-stats       statistics-enabled=true on every pool (runtime only)
  jbpool disable-stats      statistics-enabled=false
  jbpool raw                raw CLI output (debug)
env  JBOSS_HOME   EAP install dir (auto: /opt/server /opt/eap /opt/jboss/wildfly ...)
     MGMT_PORT    management port (auto: 9990 + port-offset of the running server)
     MGMT_HOST    management address (auto: 127.0.0.1 or -bmanagement)
     CONTROLLER   full controller URL, e.g. remote+http://127.0.0.1:10090
     CLI_USER / CLI_PASS   management user (only if local silent auth fails)
     JBP_LABEL    name to show (auto: ECS container name or hostname)
     JBP_WARN     BUSY threshold in % of max-pool-size (default 80)
     JBP_CSV      file to append CSV rows to while "watch" runs
     TZ           display time zone, e.g. TZ=JST-9 (works without tzdata)
     JBP_MIN_FREE_MB  stop if container memory headroom is below this (default 200)
     JBP_FORCE=1      run even if headroom is low
JBP_HELP
}

jbp_setup() {
  JBP_CLI=""
  for JBP_d in "${JBOSS_HOME:-}" /opt/server /opt/eap /opt/jboss/wildfly /opt/wildfly \
               /opt/jboss-eap /opt/jboss-eap-8.1 /opt/jboss-eap-8.0 /opt/jboss-eap-7.4 /usr/share/wildfly; do
    if [ -n "$JBP_d" ] && [ -f "$JBP_d/bin/jboss-cli.sh" ]; then JBP_CLI="$JBP_d/bin/jboss-cli.sh"; break; fi
  done
  if [ -z "$JBP_CLI" ]; then
    JBP_CLI=$(find / -xdev -path '*/bin/jboss-cli.sh' 2>/dev/null | head -n 1)
  fi
  if [ -z "$JBP_CLI" ]; then
    echo "[jbpool] jboss-cli.sh not found. set JBOSS_HOME=/path/to/eap and retry." >&2
    return 1
  fi
  # --- find the running standalone server and its management port / address
  JBP_NPROC=0; JBP_PID=""; JBP_off=""; JBP_mp=""; JBP_mh=""
  for JBP_p in /proc/[0-9]*; do
    [ -r "$JBP_p/cmdline" ] || continue
    JBP_c=$(tr '\000' ' ' < "$JBP_p/cmdline" 2>/dev/null)
    case "$JBP_c" in *org.jboss.as.standalone*) ;; *) continue ;; esac
    JBP_NPROC=$((JBP_NPROC + 1))
    [ -n "$JBP_PID" ] && continue
    JBP_PID=${JBP_p#/proc/}
    JBP_off=$(printf '%s\n' "$JBP_c" | sed -n 's/.*-Djboss\.socket\.binding\.port-offset=\([0-9][0-9]*\).*/\1/p')
    JBP_mp=$(printf '%s\n' "$JBP_c" | sed -n 's/.*-Djboss\.management\.http\.port=\([0-9][0-9]*\).*/\1/p')
    JBP_mh=$(printf '%s\n' "$JBP_c" | sed -n 's/.*-Djboss\.bind\.address\.management=\([^ ]*\).*/\1/p')
    [ -z "$JBP_mh" ] && JBP_mh=$(printf '%s\n' "$JBP_c" | sed -n 's/.*-bmanagement[= ]\([^ ]*\).*/\1/p')
  done
  JBP_host=${MGMT_HOST:-$JBP_mh}
  case "$JBP_host" in ""|0.0.0.0|::|"[::]") JBP_host=127.0.0.1 ;; esac
  JBP_port=${MGMT_PORT:-$(( ${JBP_mp:-9990} + ${JBP_off:-0} ))}
  JBP_CTRL=${CONTROLLER:-remote+http://$JBP_host:$JBP_port}
  # --- helpers: timeout command, temp dir, label
  JBP_TO=""
  command -v timeout >/dev/null 2>&1 && JBP_TO="timeout ${JBP_CLI_TIMEOUT:-90}"
  JBP_TMP=""
  for JBP_d in "${TMPDIR:-}" /tmp /dev/shm /var/tmp "${JBP_CLI%/bin/jboss-cli.sh}/standalone/tmp" "${HOME:-}"; do
    if [ -n "$JBP_d" ] && [ -d "$JBP_d" ] && [ -w "$JBP_d" ]; then JBP_TMP=$JBP_d; break; fi
  done
  if [ -z "$JBP_TMP" ]; then echo "[jbpool] no writable temp directory" >&2; return 1; fi
  JBP_F="$JBP_TMP/jbpool.$$.cli"; JBP_E="$JBP_TMP/jbpool.$$.err"
  JBP_HOSTN=$(hostname 2>/dev/null || cat /proc/sys/kernel/hostname 2>/dev/null)
  JBP_LBL=${JBP_LABEL:-}; JBP_TASK=""
  if [ -n "${ECS_CONTAINER_METADATA_URI_V4:-}" ]; then
    JBP_j=$( { curl -s -m 2 "$ECS_CONTAINER_METADATA_URI_V4" || wget -q -T 2 -O - "$ECS_CONTAINER_METADATA_URI_V4"; } 2>/dev/null )
    [ -z "$JBP_LBL" ] && JBP_LBL=$(printf '%s' "$JBP_j" | sed -n 's|.*"com\.amazonaws\.ecs\.container-name":"\([^"]*\)".*|\1|p')
    JBP_TASK=$(printf '%s' "$JBP_j" | sed -n 's|.*"com\.amazonaws\.ecs\.task-arn":"[^"]*/\([^"/]*\)".*|\1|p')
  fi
  [ -z "$JBP_LBL" ] && JBP_LBL=$JBP_HOSTN
  # --- memory headroom: the CLI JVM needs about 120-150 MB (measured RSS ~119 MB)
  JBP_MEM=""; JBP_lim=""; JBP_cur=""
  if [ -r /sys/fs/cgroup/memory.max ]; then
    JBP_lim=$(cat /sys/fs/cgroup/memory.max 2>/dev/null); JBP_cur=$(cat /sys/fs/cgroup/memory.current 2>/dev/null)
  elif [ -r /sys/fs/cgroup/memory/memory.limit_in_bytes ]; then
    JBP_lim=$(cat /sys/fs/cgroup/memory/memory.limit_in_bytes 2>/dev/null); JBP_cur=$(cat /sys/fs/cgroup/memory/memory.usage_in_bytes 2>/dev/null)
  fi
  case "$JBP_lim" in ""|*[a-z]*) JBP_lim="" ;; esac
  case "$JBP_cur" in ""|*[a-z]*) JBP_cur="" ;; esac
  if [ -n "$JBP_lim" ] && [ -n "$JBP_cur" ] && [ "$JBP_lim" -lt 1000000000000 ]; then
    JBP_free=$(( (JBP_lim - JBP_cur) / 1048576 ))
    JBP_MEM="$(( JBP_cur / 1048576 ))MB used / $(( JBP_lim / 1048576 ))MB limit (headroom ${JBP_free}MB)"
    if [ "$JBP_free" -lt "${JBP_MIN_FREE_MB:-200}" ] && [ -z "${JBP_FORCE:-}" ]; then
      echo "[jbpool] STOP: container memory headroom is only ${JBP_free}MB; the CLI JVM needs ~150MB (OOM-kill risk)." >&2
      echo "         run anyway:  JBP_FORCE=1 jbpool ...   (or set JBP_MIN_FREE_MB)" >&2
      return 1
    fi
  fi
  return 0
}

# run jboss-cli with a small, isolated JVM (does not inherit the server heap / agents)
jbp_cli() {
  ( unset JAVA_TOOL_OPTIONS _JAVA_OPTIONS JDK_JAVA_OPTIONS
    JAVA_OPTS=${JBP_JAVA_OPTS:-"-Xms16m -Xmx128m -XX:+UseSerialGC -XX:TieredStopAtLevel=1"}
    export JAVA_OPTS
    if [ -n "${CLI_USER:-}" ]; then
      $JBP_TO sh "$JBP_CLI" --connect --controller="$JBP_CTRL" --timeout=15000 \
        --user="$CLI_USER" --password="${CLI_PASS:-}" --file="$1" </dev/null
    else
      $JBP_TO sh "$JBP_CLI" --connect --controller="$JBP_CTRL" --timeout=15000 --file="$1" </dev/null
    fi )
}

jbp_fail() {
  echo "[jbpool] jboss-cli failed (rc=$1)  controller=$JBP_CTRL" >&2
  [ -n "${2:-}" ] && printf '%s\n' "$2" | grep -v '^JBPMARK' | head -n 10 >&2
  head -n 15 "$JBP_E" >&2
  JBP_msg=$( { printf '%s\n' "${2:-}"; cat "$JBP_E"; } 2>/dev/null )
  if printf '%s\n' "$JBP_msg" | grep -qiE 'refused|not available|WFLYPRT0053|timed out|unreachable'; then
    echo "  hint: management port not reachable. front/back in ONE task share localhost," >&2
    echo "        so one of them usually has a port-offset:  MGMT_PORT=10090 jbpool" >&2
  fi
  if printf '%s\n' "$JBP_msg" | grep -qiE 'authenticat|unauthori|JBREM|ELY0'; then
    echo "  hint: local (silent) auth failed. run as root/server user, or CLI_USER=... CLI_PASS=... jbpool" >&2
  fi
  [ "$1" = 124 ] && echo "  hint: CLI timed out (server hung? long GC?). thread dump: jcmd <pid> Thread.print" >&2
  return 0
}

# datasource names -> JBP_NAMES ("data-source NAME" lines)
jbp_names() {
  printf '%s\n' 'echo JBPMARK N data-source' \
    '/subsystem=datasources:read-children-names(child-type=data-source)' \
    'echo JBPMARK N xa-data-source' \
    '/subsystem=datasources:read-children-names(child-type=xa-data-source)' > "$JBP_F"
  JBP_out=$(jbp_cli "$JBP_F" 2>"$JBP_E"); JBP_rc=$?
  if [ "$JBP_rc" -ne 0 ]; then jbp_fail "$JBP_rc" "$JBP_out"; return 1; fi
  JBP_NAMES=$(printf '%s\n' "$JBP_out" | awk '
    /^JBPMARK N / { t = $3; r = 0; next }
    t != "" && /"result"/ { r = 1 }
    r == 1 { s = $0; sub(/.*"result" =>/, "", s)
             while (match(s, /"[^"]*"/)) { print t, substr(s, RSTART + 1, RLENGTH - 2); s = substr(s, RSTART + RLENGTH) }
             if ($0 ~ /]/) r = 0 }')
  return 0
}

# one sample = one CLI run: root info, pool config, pool statistics, queued threads, io worker
jbp_mkfile() {
  {
    echo 'echo JBPMARK ROOT'
    echo ':read-resource(attributes-only=true,include-runtime=true)'
    for JBP_a in jndi-name enabled statistics-enabled min-pool-size initial-pool-size max-pool-size \
                 pool-prefill pool-use-strict-min pool-fair blocking-timeout-wait-millis idle-timeout-minutes \
                 allocation-retry allocation-retry-wait-millis flush-strategy background-validation \
                 background-validation-millis validate-on-match; do
      echo "echo JBPMARK A $JBP_a"
      for JBP_t in data-source xa-data-source; do
        printf 'try\n/subsystem=datasources/%s=*:read-attribute(name=%s,resolve-expressions=true)\ncatch\necho JBPMARK AERR\nend-try\n' "$JBP_t" "$JBP_a"
      done
    done
    echo 'echo JBPMARK STAT'
    for JBP_t in data-source xa-data-source; do
      printf 'try\n/subsystem=datasources/%s=*/statistics=pool:read-resource(include-runtime=true)\ncatch\necho JBPMARK SERR\nend-try\n' "$JBP_t"
    done
    printf '%s\n' "$JBP_NAMES" | while read -r JBP_t JBP_n; do
      [ -n "$JBP_n" ] || continue
      printf 'echo JBPMARK Q %s %s\ntry\n/subsystem=datasources/%s=%s:dump-queued-threads-in-pool\ncatch\necho JBPMARK QERR\nend-try\n' "$JBP_t" "$JBP_n" "$JBP_t" "$JBP_n"
    done
    printf 'echo JBPMARK WORKER\ntry\n/subsystem=io/worker=*:read-resource(include-runtime=true)\ncatch\necho JBPMARK WERR\nend-try\necho JBPMARK END\n'
  } > "$JBP_F"
}

jbp_loop() {
  JBP_i=0
  while :; do
    JBP_i=$((JBP_i + 1))
    if [ $((JBP_i % 30)) -eq 0 ]; then jbp_names >/dev/null 2>&1; fi
    jbp_mkfile
    echo "JBPMARK SAMPLE $JBP_i"
    jbp_cli "$JBP_F" 2>"$JBP_E"
    JBP_rc=$?
    echo "JBPMARK TIME $(date +%s)"
    echo "JBPMARK RC $JBP_rc"
    if [ "$JBP_rc" -ne 0 ]; then sed -n '1,12s/^/JBPMARK ERR /p' "$JBP_E"; fi
    echo "JBPMARK DONE"
    if [ "$JBP_CNT" -gt 0 ] && [ "$JBP_i" -ge "$JBP_CNT" ]; then break; fi
    sleep "$JBP_INT"
  done
  rm -f "$JBP_F" "$JBP_E"
}

jbp_threads() {
  printf '%s\n' "$JBP_NAMES" | while read -r JBP_t JBP_n; do
    [ -n "$JBP_n" ] || continue
    printf 'echo ===== %s %s : threads waiting for a connection =====\ntry\n/subsystem=datasources/%s=%s:dump-queued-threads-in-pool\ncatch\necho not-available\nend-try\n' "$JBP_t" "$JBP_n" "$JBP_t" "$JBP_n"
  done > "$JBP_F"
  jbp_cli "$JBP_F" 2>"$JBP_E" | awk '{ gsub(/\\n/, "\n"); gsub(/\\t/, "    "); print }'
  rm -f "$JBP_F" "$JBP_E"
}

jbp_stats() {
  printf '%s\n' "$JBP_NAMES" | while read -r JBP_t JBP_n; do
    [ -n "$JBP_n" ] || continue
    for JBP_s in pool jdbc; do
      printf 'echo %s %s statistics=%s statistics-enabled=%s\ntry\n/subsystem=datasources/%s=%s/statistics=%s:write-attribute(name=statistics-enabled,value=%s)\ncatch\necho failed\nend-try\n' \
        "$JBP_t" "$JBP_n" "$JBP_s" "$1" "$JBP_t" "$JBP_n" "$JBP_s" "$1"
    done
  done > "$JBP_F"
  jbp_cli "$JBP_F" 2>"$JBP_E" | grep -E 'statistics-enabled=|failed|outcome|process-state|failure-description'
  cat "$JBP_E" >&2
  rm -f "$JBP_F" "$JBP_E"
  echo "[jbpool] runtime switch: it is lost on reload/restart. permanent: data-source attribute" >&2
  echo "         statistics-enabled=true + reload, or start with -Dwildfly.datasources.statistics-enabled=true" >&2
  echo "         (only if the datasource uses that expression)." >&2
}

# ---------------------------------------------------------------- PART 2/3 : renderer (awk)
JBP_AWK='
BEGIN {
  s = substr(TZOFF, 1, 1); TZS = (substr(TZOFF, 2, 2) + 0) * 3600 + (substr(TZOFF, 4, 2) + 0) * 60
  if (s == "-") TZS = -TZS
  if (WARN == "") WARN = 80
  MAXQ = 4; nsamp = 0; start = ""
  LINE = "------------------------------------------------------------------------------------------"
}
function trim(x) { sub(/^[ \t\r]+/, "", x); sub(/[ \t\r,]+$/, "", x); return x }
function val(x,   y) {
  x = trim(x)
  if (x ~ /^expression "/) { y = x; if (sub(/^.*:/, "", y) == 0) return "?"; gsub(/[}"]/, "", y); return y }
  if (x ~ /^".*"$/) return substr(x, 2, length(x) - 2)
  if (x ~ /^-?[0-9]+L$/) sub(/L$/, "", x)
  return x
}
function nz(x, d) { return (x == "" || x == "undefined" || x == "?") ? d : x }
function dv(d, k, def) { return (conf[d, k] == "" || conf[d, k] == "undefined") ? def "*" : conf[d, k] }
function hms(t,   x) { x = (t + TZS) % 86400; if (x < 0) x += 86400; return sprintf("%02d:%02d:%02d", int(x / 3600), int((x % 3600) / 60), x % 60) }
function ymd(t,   z, era, doe, yoe, y, doy, mp, dd, mm) {
  z = int((t + TZS) / 86400) + 719468; era = int(z / 146097); doe = z - era * 146097
  yoe = int((doe - int(doe / 1460) + int(doe / 36524) - int(doe / 146096)) / 365)
  y = yoe + era * 400; doy = doe - (365 * yoe + int(yoe / 4) - int(yoe / 100))
  mp = int((5 * doy + 2) / 153); dd = doy - int((153 * mp + 2) / 5) + 1
  mm = (mp < 10) ? mp + 3 : mp - 9; if (mm <= 2) y++
  return sprintf("%04d-%02d-%02d", y, mm, dd)
}
function at(t) { return (ymd(t) == ymd(now)) ? hms(t) : ymd(t) " " hms(t) }
function dur(x) { x = int(x); if (x >= 3600) return sprintf("%dh%02dm", int(x / 3600), int((x % 3600) / 60)); if (x >= 60) return sprintf("%dm%02ds", int(x / 60), x % 60); return x "s" }
function ms(x) { x = nz(x, ""); return (x == "") ? "-" : x "ms" }
function sd(d, k, sign) { if (R[d, "has"] == 0) return "-"; if (R[d, k] < 0) return "rst"; return sign R[d, k] }

/^JBPMARK SAMPLE / {
  split("", conf); split("", st); split("", root); split("", seen); split("", dtype); split("", qn); split("", qok)
  split("", qname); split("", wk); split("", wseen); split("", errl)
  nerr = 0; rc = 0; sec = ""; curds = ""; curw = ""; cura = ""; qds = ""; samp = $3; next
}
/^JBPMARK TIME / { now = $3 + 0; next }
/^JBPMARK RC / { rc = $3 + 0; next }
/^JBPMARK ERR / { errl[++nerr] = substr($0, 13); next }
/^JBPMARK DONE/ { render(); next }
/^JBPMARK ROOT/ { sec = "R"; next }
/^JBPMARK A / { sec = "A"; cura = $3; curds = ""; next }
/^JBPMARK STAT/ { sec = "S"; curds = ""; next }
/^JBPMARK Q / { sec = "Q"; qds = $4; seen[qds] = 1; dtype[qds] = $3; qok[qds] = 1; qn[qds] = 0; next }
/^JBPMARK QERR/ { qok[qds] = 0; next }
/^JBPMARK WORKER/ { sec = "W"; curw = ""; next }
/^JBPMARK END/ { sec = ""; next }
/^JBPMARK / { next }
sec == "Q" {
  p = index($0, "Queued thread: ")
  if (p > 0) { t = substr($0, p + 15); sub(/[\\"].*$/, "", t); t = trim(t); qn[qds]++; qname[qds, qn[qds]] = t }
  next
}
/\("(xa-)?data-source" => "/ {
  if (match($0, /"(xa-)?data-source" => "[^"]*"/)) {
    t = substr($0, RSTART, RLENGTH); dt = (t ~ /^"xa-/) ? "xa-data-source" : "data-source"
    sub(/^[^>]*> "/, "", t); sub(/"$/, "", t); curds = t; seen[t] = 1; dtype[t] = dt
  }
  next
}
/\("worker" => "/ {
  if (match($0, /"worker" => "[^"]*"/)) { t = substr($0, RSTART, RLENGTH); sub(/^[^>]*> "/, "", t); sub(/"$/, "", t); curw = t; wseen[t] = 1 }
  next
}
/^[ \t]*"[A-Za-z][A-Za-z0-9._-]*" => / {
  k = $0; sub(/^[ \t]*"/, "", k); sub(/".*$/, "", k)
  v = $0; sub(/^[^>]*=> /, "", v); v = val(v)
  if (sec == "A") { if (k == "result" && curds != "" && v != "" && (v ~ /^[\[{]/) == 0) conf[curds, cura] = v }
  else if (sec == "S") { if (curds != "") st[curds, k] = v }
  else if (sec == "R") root[k] = v
  else if (sec == "W") { if (curw != "") wk[curw, k] = v }
  next
}

function calc(d,   mn, mx, bt, it, ar, arw, wl, son, act, use, idl, cr, de, to, wc, bf, q, j, k, n, ord, tj, tmin, tmax, unk, fl, ex, del, nd, parts, tx, st2) {
  mn = nz(conf[d, "min-pool-size"], 0) + 0;   mx = nz(conf[d, "max-pool-size"], 20) + 0
  bt = nz(conf[d, "blocking-timeout-wait-millis"], 30000) + 0;   it = nz(conf[d, "idle-timeout-minutes"], 30) + 0
  ar = nz(conf[d, "allocation-retry"], 0) + 0;   arw = nz(conf[d, "allocation-retry-wait-millis"], 0) + 0
  wl = bt * (ar + 1) + arw * ar
  R[d, "mn"] = mn; R[d, "mx"] = mx; R[d, "bt"] = bt; R[d, "it"] = it; R[d, "ar"] = ar; R[d, "arw"] = arw; R[d, "wl"] = wl
  son = st[d, "statistics-enabled"]; if (son == "") son = conf[d, "statistics-enabled"]; R[d, "son"] = son
  act = nz(st[d, "ActiveCount"], 0) + 0; use = nz(st[d, "InUseCount"], 0) + 0
  idl = nz(st[d, "IdleCount"], act - use) + 0; R[d, "neg"] = 0
  if (act < 0 || act < use) { R[d, "neg"] = 1; act = use + idl }
  R[d, "act"] = act; R[d, "use"] = use; R[d, "idl"] = idl; R[d, "avl"] = nz(st[d, "AvailableCount"], mx - use) + 0
  R[d, "pct"] = (mx > 0) ? int(use * 100 / mx) : 0
  cr = nz(st[d, "CreatedCount"], 0) + 0; de = nz(st[d, "DestroyedCount"], 0) + 0; to = nz(st[d, "TimedOut"], 0) + 0
  wc = nz(st[d, "WaitCount"], 0) + 0;    bf = nz(st[d, "BlockingFailureCount"], 0) + 0
  R[d, "cr"] = cr; R[d, "de"] = de; R[d, "to"] = to; R[d, "wc"] = wc; R[d, "bf"] = bf
  R[d, "mxu"] = nz(st[d, "MaxUsedCount"], 0) + 0; R[d, "mwc"] = nz(st[d, "MaxWaitCount"], 0) + 0
  if (d in pcr) {
    R[d, "has"] = 1; R[d, "dcr"] = cr - pcr[d]; R[d, "dde"] = de - pde[d]; R[d, "dto"] = to - pto[d]
    R[d, "dwc"] = wc - pwc[d]; R[d, "dbf"] = bf - pbf[d]; R[d, "pact"] = pact[d]
  } else R[d, "has"] = 0
  pcr[d] = cr; pde[d] = de; pto[d] = to; pwc[d] = wc; pbf[d] = bf; pact[d] = act
  # ---- queued threads: first-seen time + wait limit = latest time it is resolved
  q = (d in qok) ? ((qok[d] == 1) ? qn[d] + 0 : -1) : -1
  split("", qcur)
  for (j = 1; j <= qn[d]; j++) {
    k = d SUBSEP qname[d, j]; qcur[k] = 1
    if ((k in qfs) == 0 || now > qfs[k] + wl / 1000 + 5) qfs[k] = now
  }
  nd = 0; for (k in qfs) { split(k, parts, SUBSEP); if (parts[1] == d && (k in qcur) == 0) del[++nd] = k }
  for (j = 1; j <= nd; j++) delete qfs[del[j]]
  n = 0; for (k in qcur) { n++; ord[n] = k }
  for (j = 2; j <= n; j++) { k = ord[j]; tj = j - 1; while (tj > 0 && qfs[ord[tj]] > qfs[k]) { ord[tj + 1] = ord[tj]; tj-- }; ord[tj + 1] = k }
  tx = ""; R[d, "qby"] = 0
  for (j = 1; j <= n; j++) {
    split(ord[j], parts, SUBSEP)
    if (j <= MAXQ) tx = tx ((j > 1) ? ", " : "") parts[2] " (<=" hms(qfs[ord[j]] + wl / 1000) ")"
    if (qfs[ord[j]] + wl / 1000 > R[d, "qby"]) R[d, "qby"] = qfs[ord[j]] + wl / 1000
  }
  if (n > MAXQ) tx = tx ", ... +" (n - MAXQ) " more"
  R[d, "q"] = q; R[d, "qtxt"] = tx
  # ---- idle surplus: the pool re-uses the newest connection first (LIFO), so "level j"
  #      was last used when in-use >= j (lal) and returned before it was seen free (fre).
  #      TotalUsageTime grows on every return -> also catches returns between two samples.
  if ((d in t0) == 0) t0[d] = now
  tx = nz(st[d, "TotalUsageTime"], "")
  if (tx != "" && (d in ptu) && tx + 0 != ptu[d]) actt[d] = now
  if (tx != "") ptu[d] = tx + 0
  for (j = 1; j <= use; j++) { lal[d, j] = now; if ((d, j) in fre) delete fre[d, j] }
  for (j = use + 1; j <= act; j++) if (((d, j) in lal) && (((d, j) in fre) == 0)) fre[d, j] = now
  nd = 0; for (k in lal) { split(k, parts, SUBSEP); if (parts[1] == d && parts[2] + 0 > act) del[++nd] = k }
  for (j = 1; j <= nd; j++) { delete lal[del[j]]; if (del[j] in fre) delete fre[del[j]] }
  # min-pool-size is kept only with pool-prefill or pool-use-strict-min (otherwise idle-timeout can go to 0)
  R[d, "keepmin"] = (conf[d, "pool-prefill"] == "true" || conf[d, "pool-use-strict-min"] == "true") ? 1 : 0
  fl = (R[d, "keepmin"] == 1 && mn > use) ? mn : use; ex = act - fl; if (ex < 0) ex = 0
  R[d, "fl"] = fl; R[d, "ex"] = ex; R[d, "e1"] = ""; R[d, "e2"] = ""; R[d, "unk"] = 0
  if (ex > 0 && it > 0 && son == "true") {
    tmin = -1; tmax = t0[d]; unk = 0
    for (j = fl + 1; j <= act; j++) {
      if ((d, j) in lal) {
        if (tmin < 0 || lal[d, j] < tmin) tmin = lal[d, j]
        tj = ((d, j) in fre) ? fre[d, j] : now; if (tj > tmax) tmax = tj
      } else unk++
    }
    if ((d in actt) && actt[d] > tmax) tmax = actt[d]
    R[d, "e1"] = (tmin < 0) ? "" : tmin + it * 60; R[d, "e2"] = tmax + it * 60 + CHK; R[d, "unk"] = unk
  }
  # ---- status
  if (conf[d, "enabled"] == "false") st2 = "DISABLED"
  else if (son != "true") st2 = "STATS-OFF"
  else if (q > 0) st2 = "OVERFLOW"
  else if (mx > 0 && use >= mx) st2 = "FULL"
  else if (mx > 0 && use * 100 >= WARN * mx) st2 = "BUSY"
  else st2 = "OK"
  if (R[d, "has"] == 1 && R[d, "dbf"] > 0) st2 = st2 "+TMOUT"
  R[d, "status"] = st2
}

function render(   n, i, j, d, nm, minit, it) {
  nsamp++
  if (start == "") start = now
  n = 0; for (d in seen) { n++; nm[n] = d }
  for (i = 2; i <= n; i++) { d = nm[i]; j = i - 1; while (j > 0 && nm[j] > d) { nm[j + 1] = nm[j]; j-- }; nm[j + 1] = d }
  minit = 0
  for (i = 1; i <= n; i++) {
    d = nm[i]; it = nz(conf[d, "idle-timeout-minutes"], 30) + 0
    if (conf[d, "enabled"] != "false" && it > 0 && (minit == 0 || it < minit)) minit = it
  }
  # IdleRemover wakes every SCAN sec; one pool is checked at most once per minute -> worst gap CHK
  SCAN = minit * 30; CHK = (SCAN > 60) ? SCAN : SCAN * (int(60 / SCAN) + 1)
  for (i = 1; i <= n; i++) calc(nm[i])
  if (MODE == "csv") { if (rc != 0) perr(); for (i = 1; i <= n; i++) csvrow(nm[i], 1); fflush(); return }
  if (CSVF != "") for (i = 1; i <= n; i++) csvrow(nm[i], 0)
  if (MODE == "watch") pwatch(n, nm); else psnap(n, nm)
  fflush()
}

function perr(   i) {
  printf " ** jboss-cli rc=%d : management call failed (server restarting / port / auth ?)\n", rc
  for (i = 1; i <= nerr && i <= 8; i++) print "    " errl[i]
}

function csvrow(d, out,   line) {
  if (csvh == "") {
    csvh = "date,time,epoch,label,datasource,status,active,in_use,idle,max,available,created,destroyed,timed_out,wait_count,blocking_failures,queued,max_used,max_wait_count,max_wait_ms,avg_get_ms,max_get_ms,avg_usage_ms,idle_release_from,idle_release_by,queue_resolved_by"
    if (out) print csvh; else if (CSVHDR == "1") { print csvh >> CSVF; close(CSVF) }
  }
  line = ymd(now) "," hms(now) "," now "," LABEL "," d "," R[d, "status"] "," R[d, "act"] "," R[d, "use"] "," R[d, "idl"] "," R[d, "mx"] "," R[d, "avl"]
  line = line "," R[d, "cr"] "," R[d, "de"] "," R[d, "to"] "," R[d, "wc"] "," R[d, "bf"] "," ((R[d, "q"] < 0) ? "" : R[d, "q"]) "," R[d, "mxu"] "," R[d, "mwc"]
  line = line "," nz(st[d, "MaxWaitTime"], "") "," nz(st[d, "AverageGetTime"], "") "," nz(st[d, "MaxGetTime"], "") "," nz(st[d, "AverageUsageTime"], "")
  line = line "," ((R[d, "e1"] == "" || R[d, "unk"] > 0) ? "" : at(R[d, "e1"])) "," ((R[d, "e2"] == "") ? "" : at(R[d, "e2"])) "," ((R[d, "q"] > 0) ? at(R[d, "qby"]) : "")
  if (out) print line; else { print line >> CSVF; close(CSVF) }
}

function idleline(d, head) {
  if (R[d, "it"] == 0) { print head "idle-timeout-minutes=0 -> idle connections are never closed by timeout"; return }
  if (R[d, "ex"] == 0 || R[d, "e2"] == "") return
  if (R[d, "unk"] == R[d, "ex"])
    printf "%s%d idle conn above floor %d (%d->%d) -> closed by <= %s if not reused (idle %dm + check<=%s)\n", head, R[d, "ex"], R[d, "fl"], R[d, "act"], R[d, "fl"], at(R[d, "e2"]), R[d, "it"], dur(CHK)
  else if (R[d, "unk"] > 0)
    printf "%s%d idle conn above floor %d (%d->%d) -> some any time, all by <= %s (est.)\n", head, R[d, "ex"], R[d, "fl"], R[d, "act"], R[d, "fl"], at(R[d, "e2"])
  else
    printf "%s%d idle conn above floor %d (%d->%d) -> closing ~%s .. %s (est.)\n", head, R[d, "ex"], R[d, "fl"], R[d, "act"], R[d, "fl"], at(R[d, "e1"]), at(R[d, "e2"])
}

function psnap(n, nm,   i, d, w, a, na, x) {
  print "=========================================================================================="
  printf " JBoss connection pool snapshot : %s %s %s\n", ymd(now), hms(now), TZN
  printf " target    : %s   (host %s%s)\n", LABEL, HOSTN, ((TASK != "") ? ", task " TASK : "")
  printf " server    : %s %s  state=%s  controller=%s\n", nz(root["product-name"], "?"), nz(root["product-version"], ""), nz(root["server-state"], "?"), CTRL
  if (MEM != "") printf " memory    : %s\n", MEM
  if (rc != 0) perr()
  if (SCAN > 0) printf " idle check: IdleRemover wakes every %s (smallest idle-timeout %d min / 2), a pool is checked max once/min -> gap <= %s\n", dur(SCAN), SCAN / 30, dur(CHK)
  for (w in wseen) printf " io worker : %s  busy %s / max %s  queue %s\n", w, nz(wk[w, "busy-task-thread-count"], "?"), nz(wk[w, "max-pool-size"], nz(wk[w, "task-max-threads"], "?")), nz(wk[w, "queue-size"], "?")
  if (n == 0) print " (no datasource found)"
  for (i = 1; i <= n; i++) {
    d = nm[i]
    print LINE
    printf " [%s] %s  %s   STATUS: %s\n", d, dtype[d], nz(conf[d, "jndi-name"], "?"), R[d, "status"]
    printf "   config   : min %s / initial %s / max %s   prefill=%s strict-min=%s fair=%s\n", dv(d, "min-pool-size", 0), nz(conf[d, "initial-pool-size"], "-"), dv(d, "max-pool-size", 20), dv(d, "pool-prefill", "false"), dv(d, "pool-use-strict-min", "false"), dv(d, "pool-fair", "true")
    printf "              blocking-timeout %sms  idle-timeout %smin  allocation-retry %s x %sms\n", dv(d, "blocking-timeout-wait-millis", 30000), dv(d, "idle-timeout-minutes", 30), dv(d, "allocation-retry", 0), dv(d, "allocation-retry-wait-millis", 0)
    printf "              flush=%s  background-validation=%s (%sms)  validate-on-match=%s   (*=default)\n", dv(d, "flush-strategy", "FailingConnectionOnly"), dv(d, "background-validation", "false"), nz(conf[d, "background-validation-millis"], "-"), dv(d, "validate-on-match", "false")
    if (R[d, "status"] == "DISABLED") continue
    if (R[d, "son"] != "true") { print "   stats    : DISABLED -> counters are not collected.  enable with:  jbpool enable-stats"; continue }
    printf "   now      : in-use %d + idle %d = active %d / max %d   (use %d%%, free permits %d)\n", R[d, "use"], R[d, "idl"], R[d, "act"], R[d, "mx"], R[d, "pct"], R[d, "avl"]
    printf "   peak     : max-used %d   max-waiting %d   max-wait %s   max-get %s\n", R[d, "mxu"], R[d, "mwc"], ms(st[d, "MaxWaitTime"]), ms(st[d, "MaxGetTime"])
    printf "   total    : created %d  destroyed %d (idle-timeout %d, other %d)  waited %d  timeouts %d\n", R[d, "cr"], R[d, "de"], R[d, "to"], R[d, "de"] - R[d, "to"], R[d, "wc"], R[d, "bf"]
    printf "   timing   : avg-get %s   avg-create %s   avg-usage %s   max-usage %s\n", ms(st[d, "AverageGetTime"]), ms(st[d, "AverageCreationTime"]), ms(st[d, "AverageUsageTime"]), ms(st[d, "MaxUsageTime"])
    if (R[d, "q"] < 0) print "   queue    : (dump-queued-threads-in-pool not available)"
    else if (R[d, "q"] == 0) print "   queue    : 0 thread waiting for a connection"
    else {
      printf "   queue    : %d thread(s) WAITING for a connection (pool overflow)\n", R[d, "q"]
      printf "              %s\n", R[d, "qtxt"]
      printf "   forecast : waiting threads get a connection or fail with IJ000655 by <= %s (wait limit %s)\n", at(R[d, "qby"]), dur(R[d, "wl"] / 1000)
    }
    idleline(d, "   forecast : ")
    na = 0
    if (R[d, "son"] == "true" && R[d, "mx"] > 0 && R[d, "mxu"] >= R[d, "mx"]) a[++na] = "pool reached max-pool-size (MaxUsedCount=" R[d, "mxu"] "). guide: max-pool-size >= acceptable MaxUsedCount x 1.15, check slow SQL / leaks"
    if (R[d, "bf"] > 0) a[++na] = R[d, "bf"] " request(s) timed out waiting (look for IJ000453 / IJ000655 in the log)"
    if (R[d, "q"] > 0) a[++na] = "requests are queuing now -> jbpool threads  (shows which code is waiting)"
    x = nz(st[d, "MaxUsageTime"], 0) + 0
    if (x >= 60000) a[++na] = "a connection was held for " dur(x / 1000) " (MaxUsageTime) -> long transaction or connection leak ?"
    if (R[d, "neg"] == 1) a[++na] = "ActiveCount looked inconsistent (counter reset / flush); shown as in-use + idle"
    if (R[d, "mn"] > 0 && R[d, "keepmin"] == 0) a[++na] = "min-pool-size " R[d, "mn"] " is NOT kept after idle-timeout (pool-prefill / pool-use-strict-min are false)"
    for (x = 1; x <= na; x++) printf "   %s : %s\n", ((x == 1) ? "advice  " : "        "), a[x]
  }
  print "=========================================================================================="
}

function pwatch(n, nm,   i, d, ev) {
  printf "--- %s %s %s  #%d  %s  (%s %s, %s)  idle-check<=%s ---\n", ymd(now), hms(now), TZN, samp, LABEL, nz(root["product-name"], "?"), nz(root["product-version"], ""), nz(root["server-state"], "?"), ((SCAN > 0) ? dur(CHK) : "-")
  if (rc != 0) perr()
  if (n == 0) { print "  (no datasource)"; return }
  printf "%-20s %-14s %7s %5s %4s %4s %5s %5s %5s %5s %5s %5s %5s %7s\n", "DATASOURCE", "STATUS", "USE/MAX", "USE%", "ACT", "IDLE", "NEW", "DEL", "T/O", "WAIT", "TMOUT", "QUEUE", "MAXU", "AVGGET"
  for (i = 1; i <= n; i++) {
    d = nm[i]
    printf "%-20s %-14s %7s %4d%% %4d %4d %5s %5s %5s %5s %5s %5s %5d %7s\n", substr(d, 1, 20), R[d, "status"], R[d, "use"] "/" R[d, "mx"], R[d, "pct"], R[d, "act"], R[d, "idl"], sd(d, "dcr", "+"), sd(d, "dde", "-"), sd(d, "dto", "-"), sd(d, "dwc", "+"), sd(d, "dbf", "+"), ((R[d, "q"] < 0) ? "n/a" : R[d, "q"]), R[d, "mxu"], ms(st[d, "AverageGetTime"])
    if (R[d, "q"] > 0) printf "   queue  : %d waiting -> all resolved by <= %s : %s\n", R[d, "q"], at(R[d, "qby"]), R[d, "qtxt"]
    idleline(d, "   idle   : ")
    if (R[d, "has"] == 1) {
      ev = ""
      if (R[d, "dcr"] > 0) ev = ev " | pool grew " R[d, "pact"] "->" R[d, "act"] " (+" R[d, "dcr"] " created)"
      if (R[d, "dto"] > 0) ev = ev " | " R[d, "dto"] " closed by idle-timeout"
      if (R[d, "dde"] - R[d, "dto"] > 0) ev = ev " | " (R[d, "dde"] - R[d, "dto"]) " destroyed (validation/flush/error)"
      if (R[d, "dwc"] > 0) ev = ev " | " R[d, "dwc"] " request(s) had to wait"
      if (R[d, "dbf"] > 0) ev = ev " | " R[d, "dbf"] " TIMEOUT error(s) IJ000655"
      if (ev != "") print "   event " substr(ev, 2)
    }
  }
}
'

# ---------------------------------------------------------------- PART 3/3 : main + run
jbpool() {
  JBP_MODE=${1:-snapshot}
  case "$JBP_MODE" in help|-h|--help) jbp_help; return 0 ;; esac
  case "$JBP_MODE" in
    snapshot|snap|s) JBP_MODE=snapshot; JBP_INT=0; JBP_CNT=1 ;;
    watch|w)         JBP_MODE=watch; JBP_INT=${2:-10}; JBP_CNT=${3:-0} ;;
    csv)             JBP_INT=${2:-10}; JBP_CNT=${3:-0} ;;
    threads|t|enable-stats|disable-stats|raw) ;;
    *) echo "[jbpool] unknown mode: $JBP_MODE" >&2; jbp_help; return 1 ;;
  esac
  jbp_setup || return 1
  echo "[jbpool] target=$JBP_LBL  controller=$JBP_CTRL  cli=$JBP_CLI  server-pid=${JBP_PID:-?}" >&2
  if [ "$JBP_NPROC" -gt 1 ]; then
    echo "[jbpool] WARNING: $JBP_NPROC JBoss servers are visible (shared pid namespace?). check MGMT_PORT." >&2
  fi
  jbp_names || return 1
  [ -z "$JBP_NAMES" ] && echo "[jbpool] no datasource is defined in this server" >&2
  case "$JBP_MODE" in
    threads|t)     jbp_threads; return 0 ;;
    enable-stats)  jbp_stats true; return 0 ;;
    disable-stats) jbp_stats false; return 0 ;;
    raw)           jbp_mkfile; jbp_cli "$JBP_F"; rm -f "$JBP_F" "$JBP_E"; return 0 ;;
  esac
  JBP_hdr=0
  if [ -n "${JBP_CSV:-}" ] && [ ! -s "$JBP_CSV" ]; then JBP_hdr=1; fi
  jbp_loop | awk -v MODE="$JBP_MODE" -v TZOFF="$(date +%z 2>/dev/null)" -v TZN="$(date +%Z 2>/dev/null)" \
    -v WARN="${JBP_WARN:-80}" -v LABEL="$JBP_LBL" -v HOSTN="$JBP_HOSTN" -v TASK="$JBP_TASK" \
    -v CTRL="$JBP_CTRL" -v MEM="$JBP_MEM" -v CSVF="${JBP_CSV:-}" -v CSVHDR="$JBP_hdr" "$JBP_AWK"
}

if [ $# -eq 0 ]; then jbpool snapshot; else jbpool "$@"; fi
```
