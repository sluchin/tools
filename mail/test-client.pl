#!/usr/bin/perl -w
##
# メール送信 テスト用プログラム
#
# @author Tetsuya Higashi
# @version $Id$
#
use strict;
use warnings;
use POSIX;
use File::Basename;
use File::Spec;
use Getopt::Long;
use IO::Socket;

use Logger;

my $VERSION = '0.01';
my $progpath = $0;
my $progfull = File::Spec->rel2abs($progpath);
my $procid = $$;
my $progname = basename($progpath);
my $filename = basename(__FILE__);
my $PERLCMD = '/usr/bin/perl -w ' . $progfull . '/' . $progname;
my $pidfile = $progpath;
$pidfile =~ s/^(.*)\..*$/$1/;
$pidfile .= '.pid';

my $send_mail = '/tmp/sendmail_sock';
my $recv_mail = '/tmp/recvmail_sock';
my $sock; # ソケット

# 真偽値
my $True  = 1;
my $False = 0;

# 終了ステータス
my %stathash = (
    EX_OK      => 0, # 正常終了
    EX_SIGNAL  => 1, # シグナルを受信した
    EX_SOCKET  => 2, # ソケット接続エラー
);

# プロトタイプ
sub print_version();
sub usage();
sub send_sock($$);
sub close_sock($);
sub read_cmd();
sub read_stdin();
sub read_file($);
sub main();

# デフォルトオプション
my %opt = (
    thread  => 0,
    worker  => 0,
    file    => [],
    debug   => 1,
    help    => 0,
    version => 0
);

# オプション引数
Getopt::Long::Configure(
    qw(bundling no_getopt_compat no_auto_abbrev no_ignore_case));
GetOptions(
    'thread|t:i' => \$opt{thread},
    'worker|w:i' => \$opt{worker},
    'file|f:s'   => \@{$opt{file}},
    'imap'       => \@{$opt{imap}},
    'debug|D'    => \$opt{debug},
    'verbos|v'   => \$opt{verbos},
    'help|h|?'   => \$opt{help},
    'version|V'  => \$opt{version}
) or usage();

if ($opt{help}) {
    usage();
    exit($stathash{EX_OK});
}

if ($opt{version}) {
    print_version();
    exit($stathash{EX_OK});
}

# ロガー生成
my $log = Logger->new(debug    => $opt{debug},
                      trace    => $opt{verbos},
                      level    => 'info');

if (defined $opt{debug}) {
    $log->debug(
        'thread='   . $opt{thread},
        'worker='   . $opt{worker},
        'file='     . exists($opt{file}),
        'imap='     . $opt{imap},
        'debug='    . $opt{debug},
        'help='     . $opt{help},
        'version='  . $opt{version}
    );
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
        or $log->error("error writing");
}

##
# ヘルプ表示
#
sub usage()
{
    print_version();

    print << "EOF"
Usage: $progname [options]
   -t,  --thread     thread
   -w,  --worker     fork
   -f,  --file       Read from file
        --imap       IMAP test
   -D,  --debug      Execute program for debug mode
   -h,  --help       Display this help and exit
   -V,  --version    Output version information and exit
EOF
    or $log->error('error writing');
}

##
# ソケット送信
#
# @param[in] $message 送信メッセージ
# @param[in] $sock_file UNIXドメインソケット
sub send_sock($$)
{
    my $message = shift;
    my $sock_file = shift;
    my $recv_data= '';
    my $line = '';

    $log->debug('send_sock start');

    # ソケット生成
    $sock = IO::Socket::UNIX->new(Type => SOCK_STREAM,
                                  Peer => $sock_file);
    unless ($sock) {
        $log->error('cannot connect');
        close_sock($sock);
        exit $stathash{'EX_SOCKET'};
    }
    $log->debug('sock=', fileno($sock));

    #select($sock);
    #$| = 1;
    # 送信
    $message .= "\n";
    $sock->send($message) or $log->error('send');
    #print $sock $message;
    $sock->flush() or $log->error('flush');

    $log->debug("send: data\n$message");

    $log->debug('recv');

    # 受信
    #alarm(5);
    while (defined($line = <$sock>)) {
    #do {
        #$line = <$sock>;
        $recv_data .= $line;
    #} until ($line eq "");
    }
    #alarm(0);
    $log->debug("recv: data\n$recv_data");

    # クローズ
    close_sock($sock);

    return $recv_data;
}

##
# ソケットクローズ
#
sub close_sock($)
{
    my $sock = shift;

    $log->debug('close_sock');

    return unless $sock;
    $sock->close
        or $log->error('close');
}

##
# 標準入力からリクエストコマンドを取得
#
# @return 文字列
sub read_cmd()
{
    my $line = '';

    $log->debug('read_cmd start');

    $line = <STDIN>;
#    while (defined($line = <STDIN>)) {
#        last;
#    }
    chomp $line;

    $log->debug("read_cmd end: line[$line]");

    return $line;
}

##
# 標準入力から文字列取得
#
# @return 文字列
sub read_stdin()
{
    my $line = '';
    my $message = '';

    $log->debug('read_stdin start');

    alarm(10); # 10秒でタイムアウト
    while (defined($line = <STDIN>)) {
        $message .= $line;
    }
    alarm(0);

    $log->debug('read_stdin end');
    print $message, "\n" if ($opt{debug});

    return $message;
}

##
# ファイルから文字列取得
#
# @param[in] $file ファイル名
# @return 文字列
sub read_file($)
{
    my $file = shift;
    my $line = '';
    my $message = '';
    local(*IN);

    $log->debug('read_file start');

    $log->debug($file);
    open(IN, "<$file") or $log->error('open');
    while (defined($line = <IN>)) {
        $message .= $line;
    }
    close(IN) or $log->error('close');

    $log->debug('read_file end');
    print $message if ($opt{debug});

    return $message;
}

sub main()
{
    my $file = '';
    my $message = '';
    my $recv_data = '';

    $log->info('start');

    if (@{$opt{imap}}) {
        while ($True) {
            $message = read_cmd();
            send_sock($message, $recv_mail);
        }
    } else {
        if (@{$opt{file}}) {
            foreach $file (@{$opt{file}}) {
                $message = read_file($file);
                send_sock($message, $send_mail);
            }
        } else {
            $message = read_stdin();
            send_sock($message, $send_mail);
        }
    }
    $log->info('end');
exit $stathash{EX_OK};
}

main();

__END__

