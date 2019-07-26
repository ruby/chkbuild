chkbuild
========

chkbuild は、定期的にソフトウェアをビルドし、
ビルドの記録を HTML ページとして生成します。

作者
--------

田中 哲 <akr@fsij.org>

特徴
--------

* timeout を設定できます

  設定した時間が過ぎたら、プロセスを kill します。
  このため、ビルドが終了しない問題があった場合でも、指定した時間で終了します。

* backtrace を自動的にとります

  ビルドの結果 core を生成されていたら、自動的に gdb を起動し、
  backtrace を記録します。

* 過去の記録は自動的に gzip 圧縮されます

* 前回の記録との比較を行います
  このときコマンドを実行した時刻など、毎回異なるのが当然なものは事前に置換され、
  比較結果には表れません。
  個々のビルド固有の設定で置換する対象を設定することも可能です。

* git, svn でソースを取得する場合、diff へのリンクを生成できます。
  (現在のところ、git に対して GitHub, Savannah を、 svn に対して ViewVC に対応しています)

* ひとつのビルド中で失敗が起きたときに、その失敗に依存しない部分を続行することができます。

短気なユーザのための設置および試しに ruby の最新版をビルドしてみる方法
--------

```bash
  % cd $HOME
  % git clone https://github.com/ruby/chkbuild.git
  % cd chkbuild
  % ruby start-build

  % w3m tmp/public_html/ruby-master/summary.html
  % w3m tmp/public_html/ruby-2.6/summary.html
  % w3m tmp/public_html/ruby-2.5/summary.html

  % rm -rf tmp
```

  この方法はあくまでも試しに動かすものであって、
  これを cron で定期的に実行することはしないでください。

設置
--------

以下の例では、あなたのユーザ名が foo で、
/home/foo/chkbuild に chkbuild を設置することを仮定します。
ただし、コマンド例や設定例の中に $U とあるところは実際には foo もしくは
実際の設置対象にあわせて適切に変更してください。

(1) chkbuild のダウンロード・展開

```bash
      % export U=foo
      % cd /home/$U
      % git clone https://github.com/ruby/chkbuild.git
```

(2) chkbuild の設定

    さまざまなサンプルの設定が sample ディレクトリにありますので、
    適当なものを編集します。
    また、start-build はサンプルを呼び出すスクリプトです。

```bash
      % cd chkbuild
      % vi sample/build-ruby
      % vi start-build
```

    設定内容について詳しくは次節で述べます。

    とくに注意が必要なのは、RSS を使う場合は絶対 URL を結果に埋め込む必要があるため、
    結果を公開する URL を ChkBuild.top_uri = "..." と設定する必要があります。
    これについては sample/build-ruby にコメントがあります。
    (この設定を行わない場合、不適切な URL が HTML に埋め込まれます。)

    なお、設定の内容を変更せず、ruby start-build として実行した場合は、
    Ruby の main trunk といくつかのブランチを
    /home/$U/chkbuild/tmp 以下でビルドします。

    $U ユーザでビルドした場合、次の chkbuild ユーザでのビルドの邪魔になりますので、
    ビルド結果を削除しておきます。

```bash
      % rm -rf tmp
```

(3) chkbuild ユーザの作成

    chkbuild の動作専用のユーザ・グループを作ります。
    セキュリティのため、必ず専用ユーザ・グループを作ってください。
    また、chkbuild グループに $U を加えた上で
    また、以下のようなオーナ・グループ・モードでディレクトリを作り、
    chkbuild ユーザ自身は build, public_html 以下にしか書き込めないようにします。

```
      /home/chkbuild              user=$U group=chkbuild mode=2755
      /home/chkbuild/build        user=$U group=chkbuild mode=2775
      /home/chkbuild/public_html  user=$U group=chkbuild mode=2775
```

```bash
      % su
      # adduser --disabled-login --no-create-home chkbuild
      # usermod -G ...,chkbuild $U
      # cd /home
      # mkdir chkbuild
      # chown $U:chkbuild chkbuild
      # chmod 2755 chkbuild
      # mkdir chkbuild/build
      # mkdir chkbuild/public_html
      # chown $U:chkbuild chkbuild/build chkbuild/public_html
      # chmod 2775 chkbuild/build chkbuild/public_html
      # exit
```

(4) 生成ディレクトリの設定

```bash
      % ln -s /home/chkbuild /home/$U/chkbuild/tmp
```

    デフォルトの設定のまま /home/chkbuild 以下でビルドしたい場合にはこのように
    シンボリックリンクを作るのが簡単です。

(5) rsync によるファイルのアップロード

    chkbuild を動かすホストと chkbuild が生成したファイルを公開する
    HTTP サーバが異なる場合、ssh 経由の rsync でコピーすることができます。

    このためには、まず通信に使用する (パスフレーズのない) ssh 鍵対を生成します。

```bash
      % ssh-keygen -N '' -t rsa -f chkbuild-upload -C chkbuild-upload

    アップロードしたファイルを格納するディレクトリを HTTP サーバで作ります
    ここでは /home/$U/public_html/chkbuild を使うことにします。
```

```bash
      % mkdir -p /home/$U/public_html/chkbuild
```

    HTTP サーバでアップロードを受け取るための rsync daemon の設定を作ります。
    (daemon といっても常に動かしておくわけではありませんが。)
    ここでは /home/$U/.ssh/chkbuild-rsyncd.conf に作るとします。
    この設定を使った rsync daemon は /home/$U/public_html/chkbuild 下への
    書き込み専用になります。

```bash
      /home/$U/.ssh/chkbuild-rsyncd.conf :
      [upload]
      path = /home/$U/public_html/chkbuild
      use chroot = no
      read only = no
      write only = yes
```

    HTTP サーバでアップロードを受け取るユーザの ~/.ssh/authorized_keys に
    以下を加えます。
    これはここで使う鍵対が上記の設定での rsync daemon の起動専用にするものです。

      command="/usr/bin/rsync --server --daemon --config=/home/$U/.ssh/chkbuild-rsyncd.conf .",no-port-forwarding,no-X11-forwarding,no-agent-forwarding,no-pty 上記で生成した公開鍵 chkbuild-upload.pub の内容

    chkbuild を動作させるホストで、HTTP サーバの ssh fingerprint を記録します。
    HTTP サーバのホスト名を http.server.host.domain とします。

```bash
      % mkdir /home/chkbuild/.ssh
      % ssh-keyscan -t rsa http.server.host.domain >> /home/chkbuild/.ssh/known_hosts
```

    上で生成した鍵対の秘密鍵を chkbuild を動作させるホストの
    /home/chkbuild/.ssh/ にコピーします
    そして秘密鍵を chkbild ユーザが読めるようなグループパーミッションを
    設定します。

```bash
      % cp chkbuild-upload chkbuild-upload.pub /home/chkbuild/.ssh/
      % su
      # chgrp chkbuild /home/chkbuild/.ssh/chkbuild-upload
      # chmod g+r /home/chkbuild/.ssh/chkbuild-upload
```

    そして、start-build 内で以下の行を有効にします。

```ruby
      ChkBuild.rsync_ssh_upload_target("remoteuser@http.server.host.domain::upload/dir", "/home/chkbuild/.ssh/chkbuild-upload")
```

    これにより HTTP サーバの /home/$U/public_html/chkbuild/dir にコピーされる
    ようになります。

(6) HTTP サーバの設定

    chkbuild はディスクと帯域を節約するため、ファイルを gzip 圧縮します。
    圧縮したファイルは *.html.gz や *.txt.gz というファイル名になります。
    これらのファイルをブラウザから閲覧するためには以下のようなヘッダが
    HTTP サーバからブラウザに送られなければなりません。

```
      Content-Type: text/html
      Content-Encoding: gzip
```

    また、rss というファイルでは RSS を提供するので、以下のヘッダをつけます。

```
      Content-Type: application/rss+xml
```

    これらを行う設定方法は HTTP サーバに依存しますが、
    Apache の場合は mod_mime モジュールでヘッダを制御できます。
    http://httpd.apache.org/docs/2.2/mod/mod_mime.html

    大域的な設定の状況によって具体的なやりかたは異なりますが、
    例えば以下のような設定を /home/$U/public_html/.htaccess に入れることで
    上記を実現できるかもしれません。

```
      # サーバ全体の設定にある .gz に対する AddType を抑制し、
      # .gz なファイルで Content-Encoding: gzip とする
      # .html に対して Content-Type: text/html とするのはサーバ全体の設定で
      # 行われているものとしてここでは行わない
      RemoveType .gz
      AddEncoding gzip .gz

      # rss という名前のファイルは Content-Type: application/rss+xml とする
      <Files rss>
      ForceType application/rss+xml
      </Files>
```

(7) 定期実行の設定

```bash
      # vi /etc/crontab
```

    たとえば、毎日午前 3時33分に実行するには root の crontab で以下のような
    設定を行います。

```
      33 3 * * * root cd /home/$U/chkbuild; su chkbuild -c /home/$U/chkbuild/start-build
```

    su chkbuild により、chkbuild ユーザで start-build を起動します。

(8) アナウンス

    Ruby 開発者に見て欲しいなら、Ruby CI に登録するといいかも知れません。

    https://rubyci.org/

設定
--------

chkbuild の設定は、Ruby で記述されます。
実際のところ、chkbuild の本体は chkbuild.rb という Ruby のライブラリであり、
chkbuild.rb を利用するスクリプトを記述することが設定となります。

セキュリティ
--------

chkbuild により、git/svn/cvs サーバなどから入手できる最新版をコンパイルすることは、
サーバに書き込める開発者と サーバに入っているコードを信用することになります。

開発者を信用することは通常問題ありません。
もし開発者を信用しないのならば、そもそもあなたはそのプログラムを使わないでしょう。

しかし、サーバに入っているコードを信用するのは微妙な問題をはらんでいます。
サーバがクラックされ、悪意のある人物が危険なコードを挿入する可能性があります。
たとえば、あなたの権限で実行していたら、あなたのホームディレクトリが削除されてしまうかも知れませんし、
あなたの秘密鍵が盗まれてしまうかも知れません。

このため、chkbuild は少なくとも専用ユーザで実行し、
あなたのホームディレクトリに変更を加えられないようにすべきです。

また chkbuild のスクリプト自身を書き換えられないように、chkbuild はその専用ユーザとは別のユーザの所有とすべきです。
なお、ここでいう「別のユーザ」のために専用のユーザを用意する必要はありません。
あなたの権限でもいいですし、root でもかまいません。

なお、さらに注意深くありたい場合には、
xen, chroot, jail, user mode linux, VMware, ... などで環境を限定することも検討してください。

TODO
--------

* index.html を生成する

LICENSE
--------

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions
are met:

 1. Redistributions of source code must retain the above copyright
    notice, this list of conditions and the following disclaimer.
 2. Redistributions in binary form must reproduce the above
    copyright notice, this list of conditions and the following
    disclaimer in the documentation and/or other materials provided
    with the distribution.
 3. The name of the author may not be used to endorse or promote
    products derived from this software without specific prior
    written permission.

THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS
OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE
GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

(The modified BSD license)
