= chkbuild

chkbuild は、定期的にソフトウェアをビルドし、
ビルドの記録を HTML ページとして生成します。

== 作者

田中 哲 <akr@m17n.org>

== 特徴

* timeout を設定できます

  設定した時間が過ぎたら、プロセスを kill します。
  このため、ビルドが終了しない問題があった場合でも、指定した時間で終了します。

* backtrace を自動的にとります

  ビルドの結果 core を生成されていたら、自動的に gdb を起動し、
  backtrace を記録します。

* 過去の記録は自動的に gzip 圧縮されます

* 前回の記録との diff を生成します

== 短気なユーザのための設置および試しに ruby の最新版をビルドしてみる方法

  % cd $HOME
  % cvs -d :pserver:anonymous@cvs.m17n.org:/cvs/ruby co chkbuild
  % cd chkbuild
  % ruby start-build

  % w3m tmp/public_html/ruby-trunk/summary.html 
  % w3m tmp/public_html/ruby-trunk-pth/summary.html 
  % w3m tmp/public_html/ruby-1.8/summary.html 
  % w3m tmp/public_html/ruby-1.8-pth/summary.html 

  % rm -rf tmp

  この方法はあくまでも試しに動かすものであって、
  これを cron で定期的に実行することはしないでください。

== 設置

以下の例では、あなたのユーザ名が foo で、
/home/foo/chkbuild に chkbuild を設置することを仮定します。
他のディレクトリに設置する場合は適当に変更してください。

(1) chkbuild のダウンロード・展開

      % cd /home/foo
      % cvs -d :pserver:anonymous@cvs.m17n.org:/cvs/ruby co chkbuild

(2) chkbuild の設定

    さまざまなサンプルの設定が sample ディレクトリにありますので、
    適当なものを編集します。
    また、start-build はサンプルを呼び出すスクリプトです。

      % cd chkbuild
      % vi sample/build-ruby
      % vi start-build

    設定内容について詳しくは次節で述べます。

    なお、設定の内容を変更せず、ruby start-build として実行した場合は、
    Ruby の main trunk と ruby_1_8 branch を
    それぞれ --enable-pthread 無しと有りの設定として
    計4種類を /home/foo/chkbuild/tmp 以下でビルドします。

    foo ユーザでビルドした場合、次の chkbuild ユーザでのビルドの邪魔になりますので、
    ビルド結果を削除しておきます。

      % rm -rf tmp

(3) chkbuild ユーザの作成

    chkbuild の動作専用のユーザ・グループを作ります。
    セキュリティ上の理由もあり、必ず専用ユーザ・グループを作ってください。
    また、chkbuild グループに foo を加えた上で
    また、以下のようなオーナ・グループ・モードでディレクトリを作り、
    chkbuild ユーザ自身は build, public_html 以下にしか書き込めないようにします。

      /home/chkbuild              user=foo group=chkbuild mode=2750
      /home/chkbuild/build        user=foo group=chkbuild mode=2775
      /home/chkbuild/public_html  user=foo group=chkbuild mode=2775

      % su
      # adduser --disabled-login --no-create-home --shell /home/foo/chkbuild/start-build chkbuild
      # usermod -G ...,chkbuild foo
      # cd /home
      # mkdir chkbuild
      # chown foo:chkbuild chkbuild
      # chmod 2750 chkbuild
      # su foo
      % cd chkbuild
      % mkdir build public_html
      % chgrp chkbuild build public_html
      % chmod 2775 build public_html
      % exit
      # exit

(4) 生成ディレクトリの設定

      % ln -s /home/chkbuild tmp

    デフォルトの設定のまま /home/chkbuild 以下でビルドしたい場合にはこのように
    シンボリックリンクを作るのが簡単です。

(6) 定期実行の設定

      # vi /etc/crontab

    たとえば、毎日午前 3時33分に実行するには /etc/crontab に以下の行を挿入します。

      33 3 * * * root cd /home/foo/chkbuild; su chkbuild

    su chkbuild により、chkbuild ユーザに設定したシェルとして設定した
    /home/foo/chkbuild/start-build が起動します。

(7) 公開・アナウンス

    Ruby 開発者に見て欲しいなら、Ruby hotlinks に登録するといいかも知れません。

    http://www.rubyist.net/~kazu/samidare/latest

== 設定

chkbuild の設定は、Ruby で記述されます。
実際のところ、chkbuild の本体は chkbuild.rb という Ruby のライブラリであり、
chkbuild.rb を利用するスクリプトを記述することが設定となります。

== セキュリティ

chkbuild により、CVS サーバから入手できる最新版をコンパイルすることは、
CVS サーバに書き込める開発者と CVS サーバに入っているコードを信用することになります。

開発者を信用することは通常問題ありません。
もし開発者を信用しないのならば、そもそもあなたはそのプログラムを使わないでしょう。

しかし、CVS サーバに入っているコードを信用するのは微妙な問題をはらんでいます。
CVS サーバがクラックされ、悪意のある人物が危険なコードを挿入する可能性があります。
たとえば、あなたの権限で実行していたら、あなたのホームディレクトリが削除されてしまうかも知れませんし、
あなたの秘密鍵が盗まれてしまうかも知れません。

このため、chkbuild は少なくとも専用ユーザで実行し、
あなたのホームディレクトリに変更を加えられないようにすべきです。

また chkbuild のスクリプト自身を書き換えられないように、chkbuild はその専用ユーザとは別のユーザの所有とすべきです。
なお、ここでいう「別のユーザ」のために専用のユーザを用意する必要はありません。
あなたの権限でもいいですし、root でもかまいません。

なお、さらに注意深くありたい場合には、
xen, chroot, jail, user mode linux, VMware, ... などで環境を限定することも検討してください。

== TODO

* index.html を生成する。

