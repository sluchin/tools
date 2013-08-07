##
# @file Daemonize.pm
#
# プロセスデーモン化
#
# @author Tetsuya Higashi
# @version $Id$
#
package Daemonize;

use strict;
use warnings;
use POSIX;
use File::Basename;

my $VERSION = '0.01';
my $progpath = $0;
my $procid = $$;
my $progname = basename($progpath);
my $filename = basename(__FILE__);

# 終了ステータス
my $EX_OK = 0; # 正常終了

sub new(@);
sub configure(@);
sub daemonize($);
sub get_pidfile($);
sub set_pidfile($);
sub delete_pidfile();

##
# コンストラクタ
#
# @param[in] %p 設定値
sub new(@)
{
    my $proto = shift;
    my %p = @_;
    my $class = ref $proto || $proto;
    my $self = {};
    my $log;

    $self = { pidfile => '',
              debug   => 0,
              logger  => '' };

    bless($self, $class);

    $log = Logger->new(debug    => 0,
                       level    => 'info');
    $self->{logger} = $log;

    return scalar(%p) ? $self->configure(%p) : $self;
}

##
# 設定
#
# @parma[in] %p 設定値
sub configure(@)
{
    my $self = shift;
    my %p = @_;
    my $log = $self->{logger};

    $self->{pidfile} = $p{pidfile} if $p{pidfile};
    $self->{debug} = $p{debug} if $p{debug};

    $log->configure(debug => $self->{debug});
    $log->debug('pidfile', $self->{pidfile});

    return $self;
}

##
# プロセスのデーモン化
#
# @return プロセスID
sub daemonize($)
{
    my $self = shift;
    my $pid = 0;
    my $child_pid = 0;
    my $log = $self->{logger};

    $log->debug('daemonize start');

    $pid = fork();
    if ($pid < 0) { # エラー
        $log->error('fork error');
    } elsif ($pid > 0) { # parent
        $log->debug("parent $pid");
        exit $EX_OK
    }
    # child
    $child_pid = $$;
    $log->debug("child $child_pid");
    chdir('/') or $log->error('chdir');
    umask(0) or $log->error('umask');
    setsid() or $log->error('setsid');
    # dup
    open(STDIN, '</dev/null') or $log->error('open');
    open(STDOUT, '>>/dev/null') or $log->error('open');
    open(STDERR,'>>/dev/null') or $log->error('open');

    return $child_pid;
}

##
# PIDファイル取得
#
# @return プロセスID
sub get_pidfile($)
{
    my $self = shift;
    my $line = '';
    local(*IN);
    my $file = $self->{pidfile};
    my $log = $self->{logger};

    $log->debug("get_pidfile start: $file");

    if (-f $file and -r $file) {
        open(IN, "<$file") or $log->error("open $file");
        flock(IN, 1) or $log->error("flock $file");
        $line = <IN>; # 一行読み込み
        close(IN) or $log->error("close $file");
        chomp($line);
    } else {
        $self->delete_pidfile() if (-f $file and not -r $file);
        $line = '0';
    }

    return $line;
}

##
# PIDファイル作成
#
# @param[in] $pid プロセスID
sub set_pidfile($)
{
    my $self = shift;
    my $pid = shift;
    local(*OUT);
    my $file = $self->{pidfile};
    my $log = $self->{logger};

    $log->debug("set_pidfile start: $file");

    if (-f $file and -w $file) { # ファイルが存在する
        open(OUT, "+<$file") or $log->error("open $file");
        flock(OUT, 2) or $log->error("flock $file");
        truncate(OUT, 0) or $log->error("truncate $file");
        seek(OUT, 0, 0) or $log->error("seek $file");
    } else {
        $self->delete_pidfile() if (-f $file and not -w $file);
        open(OUT, ">$file") or $log->error("open $file");
        flock(OUT, 2) or $log->error("open $file");
    }
    # 書き込み
    print OUT "$pid";
    close(OUT) or $log->error("close $file");;
}

##
# PIDファイル削除
#
sub delete_pidfile()
{
    my $self = shift;
    my $file = $self->{pidfile};
    my $log = $self->{logger};

    $log->debug("delete_pidfile start: $file");

    if (-f $file) {
        unlink($file) or $log->error('unlink');
    }
}

1;

__END__

