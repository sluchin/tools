#!/usr/bin/perl -w
##
# @file recv_mail.pl
#
# IMAP受信処理
#
# @author Tetsuya Higashi
# @version $Id$
#
use strict;
use warnings;
use Config;
use POSIX;
use File::Basename;
use File::Spec;
use Getopt::Long;
use IO::Socket;
use IO::Select;
use Jcode;
use Net::IMAP::Simple;
use Data::Dumper;
use threads;
use threads::shared;
use shared;
#use Clone qw(clone);
#use Scalar::Util qw(reftype refaddr blessed);

our $VERSION = do { my @r = ( q$Revision: 0.01 $ =~ /\d+/g ); sprintf "%d." . "%02d" x $#r, @r if (@r) };
my $progpath = $0;
my $progfull = File::Spec->rel2abs($progpath);
my $procid = $$;
my $progname = basename($progpath);
my $filename = basename(__FILE__);
my $PERLCMD = '/usr/bin/perl -w ' . $progfull;
my $pidfile = $progfull;
$pidfile =~ s/^(.*)\..*$/$1/;
$pidfile .= '.pid';

my $sock_file = '/tmp/recvmail_sock';
my $sock; # ソケット

our %imaps; # IMAP
share(%imaps);

my $user_id;

my $thread = undef;

# パスの追加
use lib $progpath;

use Logger;
use Daemonize;

# 真偽値
my $True  = 1;
my $False = 0;

# 終了ステータス
my %stathash = (
    'EX_OK'      => 0, # 正常終了
    'EX_SIGNAL'  => 1, # シグナルを受信した
    'EX_EXIST'   => 2, # 多重起動
    'EX_LOGIN'   => 3, # IMAPログインエラー
    'EX_LOGOUT'  => 4  # IMAPログアウトエラー
);

# リクエストコマンド
my %reqhash = (
    'LOGIN'   => '^LOGIN',   # ログイン
    'FOLDER'  => '^FOLDER',  # フォルダ取得
    'UID'     => '^UID',     # UID取得
    'SUMMARY' => '^SUMMARY', # サマリ取得
    'MESSAGE' => '^MESSAGE', # メッセージ取得
    'DELETE'  => '^DELETE',  # 削除
    'APPEND'  => '^APPEND',  # 追加
    'LOGOUT'  => '^LOGOUT',  # ログアウト
);

# レスポンス
my %reshash = (
    'OK'      => 'OK',             # 正常
    'LOGIN'   => 'ERR login',      # ログインエラー
    'FOLDER'  => 'ERR no folder',  # フォルダ取得できない
    'SELECT'  => 'ERR select',     # フォルダ選択できない
    'UID'     => 'ERR no uid',     # UID取得できない
    'SUMMARY' => 'ERR no summary', # サマリ取得できない
    'MESSAGE' => 'ERR no message', # メッセージ取得できない
    'LOGOUT'  => 'ERR logout',     # ログアウトエラー
    'NOCMD'   => 'ERR no cmd'      # コマンドなし
);

# プロトタイプ
sub print_version();
sub usage();
sub setup_handlers();
sub close_sock($);
sub delete_sock();
sub recv_proc($);
sub send_data($);
sub wait_recv();
sub server_loop();
sub imap_login($$);
sub get_folder($$);
sub get_uid($$);
sub select_folder($$);
sub get_one_summary($$);
sub get_all_summary($$);
sub get_message($$$$);
sub append_mail();
sub delete_mail();
sub imap_logout($$);
sub signal_handler();
sub sigchld_handler();
sub sighup_handler();
sub main();

# デフォルトオプション
my %opt = (
    'imap'          => 'xyz.com',
    'port'          => 143,
    'user'          => 'xxxxxxx',
    'pass'          => 'yyyyyyy',
    'authmechanism' => 'CRAM-MD5',
    'ssl'           => 0,
    'starttls'      => 0,
    'folder'        => 0,
    'summary'       => undef,
    'message'       => undef,
    'thread'        => 0,
    'daemon'        => 0,
    'debug'         => 1,
    'verbose'       => 0,
    'help'          => 0,
    'version'       => 0
);

# オプション引数
Getopt::Long::Configure(
    qw{no_getopt_compat no_auto_abbrev no_ignore_case});
GetOptions(
    'imap|s:s'          => \$opt{imap},
    'port|P:i'          => \$opt{port},
    'user|u:s'          => \$opt{user},
    'pass|p:s'          => \$opt{pass},
    'authmechanism|A:s' => \$opt{authmechanism},
    'ssl|S'             => \$opt{ssl},
    'stattls|T'         => \$opt{starttls},
    'folder'            => \$opt{folder},
    'summary=s{1}'      => \@{$opt{summary}},
    'message=s{2}'      => \@{$opt{message}},
    'thread|t'          => \$opt{thread},
    'daemon|d'          => \$opt{daemon},
    'debug|D'           => \$opt{debug},
    'verbose|v+'        => \$opt{verbose},
    'help|h|?'          => \$opt{help},
    'version|V'         => \$opt{version}
) or usage();

if ($opt{'help'}) {
    usage();
    exit $stathash{'EX_OK'};
}

if ($opt{'version'}) {
    print_version();
    exit $stathash{'EX_OK'};
}

# ロガー生成
my $log = Logger->new('debug'    => $opt{debug},
                      'trace'    => $opt{verbose},
                      'level'    => 'info');

if ($opt{debug}) {
    my $mes = "imap=$opt{'imap'} port=$opt{'port'} user=$opt{'user'} ";
    $mes .= "pass=$opt{'pass'} authmechanism=$opt{'authmechanism'} ";
    $mes .= "ssl=$opt{'ssl'} starttls=$opt{'starttls'} ";
    $mes .= "folder=$opt{'folder'} summary=$opt{'summary'} ";
    $mes .= "message=$opt{'message'} ";
    $mes .= "daemon=$opt{'daemon'} debug=$opt{'debug'} help=$opt{'help'} ";
    $mes .= "version=$opt{'version'}";
    $log->debug($mes);
}

##
# バージョン情報表示
#
sub print_version()
{
    print "$progname version " . $VERSION . "\n" .
          "  running on Perl version " .
          join(".",
              map { $_||=0; $_*1 } ($] =~ /(\d)\.(\d{3})(\d{3})?/ )) . "\n"
        or $log->error('error writing');
}

##
# ヘルプ表示
#
sub usage()
{
    print_version();

    print << "EOF"
Usage: $progname [options]
   -s,  --imap            Set the IMAP server default $opt{imap}
   -P,  --port            This parameter sets port number default $opt{port}
   -u,  --user            Set the SMTP Auth userid
   -p,  --pass            Set the SMTP Auth password
   -A,  --authmechanism   Send mail on Authmechanism 
   -S,  --ssl             Send mail on SSL
   -T,  --starttls        Send mail on Starttls
   -t,  --thread          Execute recieve process on thread
   -d,  --daemon          Start for daemon
   -D,  --debug           Execute program for debug mode
   -v,  --verbose         Output verbose message
   -h,  --help            Display this help and exit
   -V,  --version         Output version information and exit
EOF
    or $log->error('error writing');
}

sub setup_handlers()
{
    $SIG{'HUP'}  = \&sighup_handler;
    $SIG{'CHLD'} = \&sigchld_handler;
    $SIG{'INT'}  = \&signal_handler;
    $SIG{'QUIT'} = \&signal_handler;
    $SIG{'TERM'} = \&signal_handler;
    $SIG{'USR2'} = \&sigusr2_handler;
    $SIG{'TRAP'} = 'IGNORE';
    $SIG{'ABRT'} = 'IGNORE';
    #$SIG{'PIPE'} = 'IGNORE';
    if ($opt{'debug'}) {
        print STDERR $Config{'sig_name'}, "\n"
            or $log->error('error writing');
    }
}

##
# ソケットクローズ
#
# @param[in] $sock ソケット
sub close_sock($)
{
    my $sock = shift;

    defined $sock or return undef;
    $sock->close
        or $log->error('close');
}

##
# ソケットファイル削除
#
sub delete_sock()
{
    return unless (-S $sock_file);
    unlink($sock_file)
        or $log->error('unlink');
}

##
# 送受信
#
# @param[in] $client アクセプト
sub recv_proc($)
{
    my $client = shift;
    my $recv_data = '';
    my $send_data = '';
    my $line = '';

    $log->debug('recv_proc start');

    if ($opt{thread}) {
        my $thr = threads->self();
        $thr->detach();
    }

    #select $client;
    #$| = 1;
    while (defined($line = <$client>)) {
        $recv_data = $line;
        $log->debug("line: $line");
        last;
    }
    $client->flush()
        or $log->error('flush', fileno($client));
    chomp $recv_data;

    $log->debug("recv: data\n$recv_data");
    $send_data = send_data($recv_data);
    $log->debug("send: data\n$send_data");

    # 送信
    $client->send($send_data);
    $client->flush()
        or $log->error('flush', fileno($client));

    close_sock($client);

    $log->debug('send end');
}

##
# 送信データ作成
#
# 受信したデータごとに処理を分岐する.
# @param[in] $recv_data 受信データ
# @return 送信データ文字列
sub send_data($)
{
    my $recv_data = shift;
    my $result = '';

    $log->debug('send_data start');

    if ($recv_data =~ m/$reqhash{'LOGIN'}/) {
        my (undef, $user, $pass) = split / /, $recv_data;
        $result = imap_login($user, $pass)
            or return $reshash{'LOGIN'};
    } elsif ($recv_data =~ m/$reqhash{'FOLDER'}/) {
        my (undef, $user, $pass) = split / /, $recv_data;
        $log->debug("user=$user pass=$pass");
        $log->debug(Dumper($imaps{$user}));
        $result = get_folder($imaps{$user}, $user)
            or return $reshash{'FOLDER'};
    } elsif ($recv_data =~ m/$reqhash{'UID'}/) {
        my (undef, $user, $pass, $folder) = split / /, $recv_data;
        $log->debug("user=$user pass=$pass folder=$folder");
        $result = select_folder($imaps{$user}, $folder)
            or return $reshash{'SELECT'};
        my @uids = get_uid($imaps{$user}, $user) or return $reshash{'UID'};
        $result = '';
        foreach my $uid (@uids) {
            $result .= "$uid,";
        }
        chop($result);
    } elsif ($recv_data =~ m/$reqhash{'SUMMARY'}/) {
        my (undef, $user, $pass, $folder, $uids) = split / /, $recv_data;
        $log->debug("user=$user pass=$pass folder=$folder uids=$uids");
        $result = select_folder($imaps{$user}, $folder)
            or return $reshash{'SELECT'};
        $result = '';
        my @uid = split(/,/, $uids);
        foreach my $u (@uid) {
            $result .= get_one_summary($imaps{$user}, $u) . "\n"
                or return $reshash{'SUMMARY'};
        }
        chomp($result);

    } elsif ($recv_data =~ m/$reqhash{'MESSAGE'}/) {
        my (undef, $user, $pass, $folder, $uids) = split / /, $recv_data;
        $log->debug("user=$user pass=$pass folder=$folder uids=$uids");
        $result = select_folder($imaps{$user}, $folder)
            or return $reshash{'SELECT'};
        $result = get_message($imaps{$user}, $user, $folder, $uids)
            or return $reshash{'MESSAGE'};
    } elsif ($recv_data =~ m/$reqhash{'LOGOUT'}/) {
        my (undef, $user, $pass) = split / /, $recv_data;
        $log->debug("user=$user pass=$pass");
        $result = imap_logout($imaps{$user}, $user)
            or return $reshash{'LOGOUT'};
    } else {
        $log->error('recv error')
            or return $reshash{'NOCMD'};
    }

    return $result;
}

##
# 受信待ち
#
sub wait_recv()
{
    my ($sel, @ready) = undef;
    my $pid = 0;

    $log->debug('wait_recv:', fileno($sock));

    $sel = IO::Select->new($sock);
    while (@ready = $sel->can_read) {
        foreach my $fh (@ready) { # 受信待ち
            $log->debug('fh:', fileno($fh), 'sock:', fileno($sock));
            if ($fh eq $sock) { # socket ok
                $log->debug('accept start');
                my $client = $sock->accept()
                    or $log->error('accept') and redo;

                if ($opt{thread}) {
                    $thread = threads->new(\&recv_proc, $client);
                    $log->debug('thread end');
                    #threads->exit();
                } else {
                    if (!defined($pid = fork)) { # エラー
                        $log->error('fork');
                        next;
                    } elsif ($pid) { # parent
                        $log->debug('parent');
                        close_sock($client);
                        next;
                    } else { # child
                        $log->debug('child');
                        close_sock($sock);
                        recv_proc($client);
                        close_sock($client);
                        POSIX::_exit($stathash{'EX_OK'});
                    }
                }
            } else {
                $log->error('fh:', fileno($fh), 'sock:', fileno($sock));
            }
        }
    }
}

##
# サーバループ
#
# ソケット接続し、ループする.
sub server_loop()
{
    $log->debug('server_loop');

    delete_sock();
    $sock = IO::Socket::UNIX->new(Type   => SOCK_STREAM,
                                  Listen => SOMAXCONN,
                                  Local  => $sock_file);
    unless ($sock) {
        $log->error('cannot listen');
        close_sock($sock);
        delete_sock();
        exit $stathash{'EX_SOCKET'};
    }
    $log->debug('sock=', fileno($sock));

    while ($True) {
        wait_recv();
    }
}

##
# IMAPログイン
#
# @param[in] $user ユーザ名
# @param[in] $pass パスワード
# @return ステータス
sub imap_login($$)
{
    my $user = shift;
    my $pass = shift;
    my $imap = undef;
    my $result = undef;

    $log->debug('imap_login start');

    return undef unless (defined $user or defined $pass);

    $imap = Net::IMAP::IMAPClient->new(
        server        => $opt{imap},
        port          => $opt{port},
        user          => $user,
        pass          => $pass,
        Authmechanism => $opt{authmechanism},
        ssl           => $opt{ssl},
        Starttls      => $opt{starttls},
        timeout       => 10,
    ) or return undef;

    #$imap->connect or $log->debug('imap connect error') and return undef;

    $log->debug("imap\n", Dumper($imap));

    $result = &get_folder($imap, $user);
    $imaps{$user} = shared_clone($imap);
    $log->debug(Dumper($imaps{$user}));

    $log->debug("imaps=", $imaps{$user});

    $log->debug('imap login end');

    return $result;
}

##
# フォルダ名取得
#
# @param[in] $imap imapオブジェクト
# @param[in] $user ユーザ名
# @return フォルダ名
sub get_folder($$)
{
    my $imap = shift;
    my $user = shift;
    my $folders = '';
    my $result = '';

    $log->debug('get_folder start');

    defined($imap) or return undef;

    $log->debug(Dumper($imap));

    $folders = $imap->folders
        or $log->debug('no folders') and return undef;

    @{$folders} = reverse(@{$folders});
    foreach my $folder (@{$folders}) {
        $result .= "$folder\n";
    }
    chomp($result);
    $log->debug("data\n$result");

    return $result;
}

##
# UID取得
#
# @param[in] $imap imapオブジェクト
# @param[in] $user ユーザ名
# @return UID
sub get_uid($$)
{
    my $imap = shift;
    my $user = shift;
    my @uids = undef;

    $log->debug('get_uid start');

    defined($imap) or return undef;

    @uids = $imap->messages
        or $log->error('messages')
        and return undef;

    return @uids;
}

##
# フォルダ選択
#
# @param[in] $imap imapオブジェクト
# @param[in] $folder フォルダ名
# @return 正常時$reshash{OK}
sub select_folder($$)
{
    my $imap = shift;
    my $folder = shift;

    $log->debug('select_folder start');

    defined($imap) or return undef;
    defined $folder or $log->debug('no folder') and return undef;

    $log->debug("imap\n", Dumper($imap));
    $imap->select($folder) or return undef;

    return $reshash{'OK'};
}

##
# サマリ取得
#
# CSV形式でサマリを出力.
# @param[in] $imap imapオブジェクト
# @param[in] $uid UID
# @return %summary サマリ
sub get_one_summary($$)
{
    my $imap = shift;
    my $uid = shift;
    my ($from, $subject, $date) = '';
    my ($week, $day, $month, $year, $time) = '';
    my $summary = '';

    $log->debug("get_one_summary start: $uid");

    defined($imap) or return undef;

    $from = $imap->get_header($uid, 'From')
        or $log->debug('no From');
    $subject = $imap->get_header($uid, 'Subject')
        or $log->debug('no Subject');
    $date = $imap->get_header($uid, 'Date')
        or $log->debug('no Date');

    ($week, $day, $month, $year, $time, undef, undef) = split(/ /, $date);
    chop($week); # コンマ削除
    $date = "$week $day $month $year $time";
    $summary = "$uid,$from,$date,$subject";

    $log->debug("summary[$summary]");
    return $summary;
}

##
# サマリ取得
#
# @param[in] $imap imapオブジェクト
# @param[in] $user ユーザ名
# @return %summary サマリ
sub get_all_summary($$)
{
    my $imap = shift;
    my $user = shift;
    my ($messageid, $from, $subject, $date) = '';
    my ($week, $day, $month, $year, $time) = '';
    my @uids = undef;
    my %summary = ();

    $log->debug('get_all_summary start');

    defined($imap) or return undef;

    # UID取得
    @uids = get_uid($imap, $user) or return undef;

    # ヘッダ取得
    foreach my $uid (@uids) {
        $summary{$uid} = get_one_summary($imap, $uid)
            or return undef;
    }

    if ($opt{'debug'}) {
        foreach my $uid (keys %summary) {
            $log->debug("$uid: $summary{$uid}");
        }
    }
    return %summary;
}

##
# メッセージ取得
#
# @param[in] $imap imapオブジェクト
# @param[in] $user ユーザ名
# @param[in] $folder フォルダ名
# @param[in] $uid UID
sub get_message($$$$)
{
    my $imap = shift;
    my $user = shift;
    my $folder = shift;
    my $uid = shift;
    my $message = '';

    $log->debug("get_message start: $uid");

    defined($imap) or return undef;
    defined $folder or $log->debug('no folder') and return undef;
    defined $uid or $log->debug('no uid') and return undef;

    # メッセージ取得
    no strict 'refs';
    $message = $imap->message_string($uid)
        or $log->debug('no message') and return undef;

    $log->debug("message:\n$message");

    return $message;
}

##
# メール追加
#
sub append_mail()
{
    $log->debug('append_mail start');


    return $reshash{'OK'};
}

##
# メール削除
#
sub delete_mail()
{
    $log->debug('delete_mail start');


    return $reshash{'OK'};
}

##
# ログアウト
#
# @param[in] $imap imapオブジェクト
# @param[in] $user ユーザ名
# @return 正常時$reshash{OK}
sub imap_logout($$)
{
    my $imap = shift;
    my $user = shift;

    $log->debug('imap_logout start');

    $imap->close 
        or $log->error('close error');
    $imap->logout
        or $log->error('login error')
        and return undef;

    return $reshash{'OK'};
}

##
# シグナル補足
#
# SIGINT SIGQUIT SIGTERM
sub signal_handler()
{
    $log->info('signal_handler');

    if ($thread->is_joinable()) {
        $thread->join();
    }
    exit $stathash{'EX_SIGNAL'};
}

##
# ゾンビプロセス消滅
#
# SIGCHLD
sub sigchld_handler()
{
    my $sig = 0;

    $log->info('sigchld_handler');

    do {
        $sig = waitpid(-1, WNOHANG);
    } while ($sig > 0);
}

##
# プロセス再起動
#
# SIGHUP
sub sighup_handler()
{
    $log->info('sighup_handler');

    if ($opt{daemon}) {
        my $daemon = Daemonize->new(pidfile => $pidfile,
                                    debug   => $opt{debug});
        my $cmd_option = '';
        close_sock($sock);
        delete_sock();
        $daemon->delete_pidfile();
        foreach my $key (keys %opt) {
            next if (!exists($opt{$key}));
            if ($opt{$key} eq 1) {
                $cmd_option .= ' --' . $key;
            } else {
                redo unless ($opt{$key});
                $cmd_option .= ' --' . $key . ' ' . $opt{$key};
            }
        }
        $log->debug("option[$cmd_option]");
        exec($PERLCMD . $cmd_option);
    }
}

##
# 主処理
#
sub main()
{
    my $pid = '';
    my $child_pid = '';

    $log->info('start');

    $log->debug(dirname($progfull));
    $log->debug("@INC") if ($opt{'debug'});

    # シグナルハンドラの設定
    &setup_handlers();

    if ($opt{'daemon'}) {
        if (!$opt{'debug'}) {
            # デーモン化(多重起動禁止)
            $log->debug("daemon $pidfile");
            my $daemon = Daemonize->new(pidfile => $pidfile,
                                        debug   => $opt{'debug'});
            $child_pid = $daemon->daemonize();
            $pid = $daemon->get_pidfile();
            $log->debug("old[$pid] new[$child_pid]");
            if ($pid) { # pidファイル存在する
                $log->debug("PERLCMD[$PERLCMD]");
                if (kill 0 => $pid or $!{EPERM}) { # プロセスが存在する
                    $log->error("bye bye: pid[$pid]");
                    exit $stathash{'EX_EXIST'};
                }
            }
            $procid = $child_pid;
        }
        server_loop();
    } else {
        # ログイン
        my $result;
        my $imap;

        $result = imap_login($opt{user}, $opt{pass});
        #defined $result or exit $stathash{EX_LOGIN};

        if ($opt{'folder'}) {
            $result = get_folder($imap, $opt{'user'});
        } elsif (defined(@{$opt{'summary'}})) {
            if (@{$opt{'summary'}} eq 1) {
                my $folder = @{$opt{'summary'}}[0];
                $log->debug("folder: $folder");
                $result = get_all_summary($imap, $opt{'user'});
            } else {
                $log->error('option error');
            }
        } elsif (defined(@{$opt{'message'}})) {
            if (@{$opt{message}} eq 2) {
                my $folder = @{$opt{'message'}}[0];
                my $uid = @{$opt{'message'}}[1];
                $log->debug("folder: $folder uid: $uid");
                $result = get_message($imap, $opt{'user'}, $folder, $uid);
            } else {
                $log->error('option error');
            }
        }

        # ログアウト
        #$result = imap_logout($imap, $opt{user});
        #defined $result or exit $stathash{EX_LOGOUT};
    }
    $log->info('end');

    exit $stathash{'EX_OK'};
}

main();

__END__

