#!/usr/bin/perl -w
##
# @file send_mail.pl
#
# メール送信
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
use Net::SMTP;
use Net::SMTP::TLS;
use Net::SMTP::SSL;

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

# パスの追加
use lib qw { $progpath };

use Logger;
use Daemonize;

my $sock_file = '/tmp/sendmail_sock';
my $sock; # ソケット

# 真偽値
my $True  = 1;
my $False = 0;

# 終了ステータス
my %stathash = (
    'EX_OK'      => 0, # 正常終了
    'EX_SIGNAL'  => 1, # シグナルを受信した
    'EX_CONNECT' => 2, # SMTP接続エラー
    'EX_SOCKET'  => 3, # ソケット接続エラー
    'EX_SEND'    => 4, # SMTPデータ送信エラー
    'EX_EXIST'   => 5  # 多重起動
);

# プロトタイプ
sub print_version();
sub usage();
sub setup_handlers();
sub close_sock($);
sub delete_sock();
sub server_loop();
sub scan_header($*);
sub send_message($%);
sub send_stdin();
sub send_file();
sub connect_smtp();
sub signal_handler();
sub sigchld_handler();
sub sighup_handler();
sub main();

# デフォルトオプション
my %opt = (
    'port'     => 587,
    'smtp'     => 'imap.gmail.com',
    'user'     => 'xxxxxx@gmail.com',
    'pass'     => 'yyyyyy',
    'auth'     => 1,
    'ssl'      => 0,
    'tls'      => 1,
    'time'     => 1,
    'sendonly' => 0,
    'saveonly' => 0,
    'file'     => undef,
    'daemon'   => 0,
    'verbose'  => 0,
    'debug'    => 1,
    'help'     => 0,
    'version'  => 0
);

# オプション引数
Getopt::Long::Configure(
    qw(bundling no_getopt_compat no_auto_abbrev no_ignore_case));
GetOptions(
    'smtp|s=s'   => \$opt{'smtp'},
    'port|P=i'   => \$opt{'port'},
    'user|u=s'   => \$opt{'user'},
    'pass|p=s'   => \$opt{'pass'},
    'auth|A'     => \$opt{'auth'},
    'tls|T'      => \$opt{'tls'},
    'ssl|S'      => \$opt{'ssl'},
    'file|f=s'   => \@{$opt{'file'}},
    'time|t=i'   => \$opt{'time'},
    'sendonly'   => \$opt{'sendonly'},
    'saveonly'   => \$opt{'saveonly'},
    'daemon|d'   => \$opt{'daemon'},
    'debug|D'    => \$opt{'debug'},
    'verbose|v'  => \$opt{'verbose'},
    'help|h|?'   => \$opt{'help'},
    'version|V'  => \$opt{'version'}
) or usage();

if ($opt{'help'}) {
    usage();
    exit($stathash{'EX_OK'});
}

if ($opt{'version'}) {
    print_version();
    exit($stathash{'EX_OK'});
}

# ロガー生成
my $log = Logger->new(debug    => $opt{'debug'},
                      trace    => $opt{'verbose'},
                      level    => 'info');

if ($opt{debug}) {
    my $mes = "smtp=$opt{'smtp'} port=$opt{'port'} user=$opt{'user'} ";
    $mes .= "pass=$opt{'pass'} auth=$opt{'auth'} ssh=$opt{'ssl'} ";
    $mes .= "ttl=$opt{'tls'} ";
    $mes .= "file=" . exists($opt{'file'}) . " sendonly=$opt{'sendonly'} ";
    $mes .= "saveonly=$opt{'saveonly'} daemon=$opt{'daemon'} ";
    $mes .= "verbos=$opt{'verbose'} ";
    $mes .= "debug=$opt{'debug'} help=$opt{'help'} version=$opt{'version'}";
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
   -s,  --smtp       Set the SMTP server default $opt{'smtp'}
   -P,  --port       This parameter sets port number default $opt{'port'}
   -u,  --user       Set the SMTP Auth userid
   -p,  --pass       Set the SMTP Auth password
   -A,  --auth       Send mail on SMTP AUTH
   -S,  --ssl        Send mail on SSL
   -T,  --tls        Send mail on TLS
   -t,  --time       Send mail on times
        --sendonly   Send mail only
        --saveonly   Save mail only
   -f,  --file       Send from file
   -d,  --daemon     Start for daemon
   -D,  --debug      Execute program for debug mode
   -v,  --verbose    Output verbos message
   -h,  --help       Display this help and exit
   -V,  --version    Output version information and exit
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
    $SIG{'TRAP'} = 'IGNORE';
    $SIG{'ABRT'} = 'IGNORE';
    #$SIG{PIPE} = 'IGNORE';
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
# アクセプトループ
#
# ソケット接続し、アクセプトする.
sub server_loop()
{
    my $timeout = 10;
    my $pid = 0;
    my %mes = ();
    my ($smtp, $sel, @ready);

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
    $log->debug('sock', $sock->sockname(), fileno($sock));

    while ($True) {
        $sel = IO::Select->new($sock);
        $log->debug('ready');
        while (@ready = $sel->can_read($timeout)) { # 受信待ち
            foreach my $fh (@ready) {
                $log->debug('fh:', fileno($fh),
                            'sock:', fileno($sock));
                if ($fh eq $sock) { # socket ok
                    $log->debug('accept start');
                    my $client = $sock->accept()
                        or $log->error('accept') and redo;

                    if (!defined($pid = fork)) { # エラー
                        $log->error('fork');
                    } elsif ($pid) { # parent
                        $log->debug('parent');
                        close_sock($client);
                    } else { # child
                        $log->debug('child');
                        close_sock($sock);
                        $smtp = connect_smtp(); # SMTPコネクション

                        # 受信
                        #select($client);
                        #$| = 1;
                        %mes = scan_header($smtp , *$client);
                        $client->flush()
                            or $log->error('flush', fileno($fh));
                        send_message($smtp, %mes);

                        $client->send('OK') or $log->error('send');
                        $client->flush()
                            or $log->error('flush', fileno($fh));
                        close_sock($client);
                        POSIX::_exit($stathash{'EX_OK'});
                    }
                    $pid = waitpid(-1, WNOHANG);
                    $log->debug("waitpid[$pid]");
                } # if
            } # foreach
        } # while
        $pid = waitpid(-1, WNOHANG);
        $log->debug("waitpid[$pid]");
    } # while
}

##
# 文字列取得しSMTPコマンド設定
#
# @param[in] $smtp smtpオブジェクト
# @param[in] *FH ファイルハンドル
# @return メッセージ
sub scan_header($*)
{
    my $smtp = shift;
    local(*FH) = shift;
    my $line = '';
    my %send_mes = ();

    $log->debug('scan_header start');

    defined $smtp or return undef;

    while (defined($line=<FH>)) {
        $log->debug($line);
        $send_mes{message} .= $line;
        chomp $line;
        if ($line =~ m/^From:/) {
            $line =~ s/^From://i;
            $send_mes{'from'} = $line;
        } elsif ($line =~ m/^To:/) {
            $line =~ s/^To://i;
            $send_mes{'to'} = $line;
        } elsif ($line =~ m/^Cc:/) {
            $line =~ s/^Cc://i;
            $send_mes{'cc'} = $line;
        } elsif ($line =~ m/^Bcc:/) {
            $line =~ s/^Bcc://i;
            $send_mes{'bcc'} = $line;
        }
    }
    $log->debug('scan_header end');

    return %send_mes;
}

##
# メッセージ送信
#
# @param[in] $smtp smtpオブジェクト
# @param[in] %send_mes メッセージ
# @return 正常時$False
sub send_message($%)
{
    my $smtp = shift;
    my %send_mes = @_;

    $log->debug('send_message start');

    defined $smtp or return undef;
    #defined %send_mes or return undef;
    return undef unless (exists($send_mes{'from'}));
    return undef unless (exists($send_mes{'to'}));

    for (my $i = 0; $i < $opt{'time'}; $i++) {
        $smtp->mail($send_mes{'from'});

        if (exists($send_mes{'to'})) {
            foreach (split /[,;]/, $send_mes{'to'}) {
                $smtp->to($_);
            }
        }
        if (exists($send_mes{'cc'})) {
            foreach (split /[,;]/, $send_mes{'cc'}) {
                $smtp->cc($_);
            }
        }
        if (exists($send_mes{'bcc'})) {
            foreach (split /[,;]/, $send_mes{'bcc'}) {
                $smtp->bcc($_);
            }
        }
        $smtp->data();
        $smtp->datasend(jcode($send_mes{'message'})->jis);
        $smtp->dataend();
        $log->debug("\n$send_mes{'message'}\n");
        $log->debug("count=$i");
    }
    $smtp->quit();
    $log->debug('send_message end');
}

##
# 標準入力から文字列取得し送信
#
sub send_stdin()
{
    my $line = '';
    my %mes = ();
    my $smtp = undef;

    $log->debug('send_stdin');

    $smtp = connect_smtp();

    alarm(10); # 10秒でタイムアウト
    %mes = scan_header($smtp, *STDIN);
    alarm(0);
    send_message($smtp, %mes);
}

##
# ファイルから文字列取得し送信
#
sub send_file()
{
    my $line = '';
    my %mes = ();
    my $file = '';
    my $smtp = undef;
    local(*IN);

    $log->debug('send_file');

    foreach $file (@{$opt{'file'}}) {
        $log->debug($file);
        $smtp = connect_smtp();
        open(IN, "<$file")
            or $log->error('open');
        %mes = scan_header($smtp, *IN);
        send_message($smtp, %mes);
        close(IN)
            or $log->error('close');
    }
}

##
# SMTPに接続
#
# @return $smtp SMTPコネクション
sub connect_smtp()
{
    my $smtp = undef;

    $log->debug('connect_smtp');

    if ($opt{'tls'}) {
        $smtp = Net::SMTP::TLS->new($opt{'smtp'},
                                    Port     => $opt{'port'},
                                    User     => $opt{'user'},
                                    Password => $opt{'pass'});
    } elsif ($opt{'ssl'}) {
        $smtp = Net::SMTP::SSL->new($opt{'smtp'},
                                    Port => $opt{'port'});
    } else {
        $smtp = Net::SMTP->new($opt{'smtp'},
                               Port    => $opt{'port'},
                               Timeout => 60,
                               Debug   => $opt{'debug'});
    }
    unless ($smtp) {
        $log->error('connect error');
        exit $stathash{'EX_CONNECT'};
    }

    # SMTP認証
    if (not $opt{'tls'} and $opt{'auth'}) {
        if (not $opt{'user'} or not $opt{'pass'}) {
            $log->error('Set userid and password');
        }
        $smtp->auth($opt{'user'}, $opt{'pass'})
             or $log->error('auth');
    }
    return $smtp;
}

##
# シグナル補足
#
# SIGINT SIGQUIT SIGTERM
sub signal_handler()
{
    $log->info('signal_handler');

    close_sock($sock);
    delete_sock();

    if ($opt{'daemon'}) {
        my $daemon = Daemonize->new(pidfile => $pidfile,
                                    debug   => $opt{'debug'});
        $daemon->delete_pidfile();
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
# 自プロセス再起動
#
# SIGHUP
sub sighup_handler()
{
    $log->info('sighup_handler');

    if ($opt{'daemon'}) {
        my $daemon = Daemonize->new(pidfile => $pidfile,
                                    debug   => $opt{'debug'});
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
                if (kill 0 => $pid or $!{'EPERM'}) { # プロセスが存在する
                    $log->error("bye bye: pid[$pid]");
                    exit $stathash{'EX_EXIST'};
                }
            }
            $procid = $child_pid;
        }
        server_loop();
    } else {
        if (defined(@{$opt{'file'}})) {
            send_file();
        } else {
            send_stdin();
        }
    }
    $log->info('end');

    exit $stathash{'EX_OK'};
}

main();

__END__
=head1 NAME

send_mail.pl - Send mail tool

=head1 SYNOPSIS

send_mail.pl [opt]

 Options:
   -s,  --smtp       Set the SMTP server
   -P,  --port       This parameter sets port number
   -u,  --user       Set the SMTP Auth userid
   -p,  --pass       Set the SMTP Auth password
   -A,  --auth       Send mail on SMTP AUTH
   -S,  --ssl        Send mail on SSL
   -T,  --tls        Send mail on TLS
   -t,  --time       Send mail on times
   --sendonly        Send mail only
   --saveonly        Save mail only
   -f,  --file       Send from file
   -d,  --daemon     Start for daemon
   -D,  --debug      Execute program for debug mode
   -v,  --verbose    Output verbos message
   -h,  --help       Display this help and exit
   -V,  --version    Output version information and exit

=over 4

=back

=head1 DESCRIPTION

B<This program> Send mail from stdin.

Example:

$cat test-message
From: higashi@pproj.servehttp.com
To: iannis_xenakis@y2.dion.ne.jp
Subject: test subject
Mime-Version: 1.0
Content-Type: text/plain; charset=ISO-2022-JP
Content-Trensfer-Encoding: 7bit

test body

$cat test-message | ./send_mail.pl

=cut

