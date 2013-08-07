##
# @file Logger.pm
#
# ログ出力
#
# @author Tetsuya Higashi
# @version $Id$
#
package Logger;

use strict;
use warnings;
use Carp;
use Sys::Syslog;
use Time::HiRes qw(gettimeofday);
use File::Basename;

my $VERSION = '0.01';
my $progname = basename($0);

# プロトタイプ
sub new(@);
sub configure(@);
sub log(@);
sub message($);
sub get_time();
sub get_msec();
sub std_log($$$$;$);
sub sys_log($$$$);

BEGIN
{
    # ディスパッチ
    foreach my $level (qw(debug info error)) {
        my $sub = sub { my $self = shift;
                        my @p = @_ if (@_);
                        my ($pkg, $file, $line) = caller;
                        $self->log(level   => $level, 
                                   pkg     => $pkg,
                                   file    => basename($file),
                                   line    => $line,
                                   message => "@p",
                                   trace   => Carp::longmess(" called"));
                       };
        no strict 'refs';
        *{$level} = $sub;
    }
}

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

    $self = { debug    => 0,
              fh       => undef,
              trace    => 0,
              errno    => 0,
              level    => 0 };

    bless($self, $class);

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

    $self->{debug} = $p{debug} if ($p{debug});
    $self->{fh} = $p{fh} if ($p{fh});
    $self->{level} = $p{level} if ($p{level});
    $self->{trace} = $p{trace} if ($p{trace});

    return $self;
}

##
# ログ出力
#
# @param[in] %p メッセージ
sub log(@)
{
    my $err_no = $!; # errno退避
    my $self = shift;
    my %p = @_;

    return unless ($self->{debug});

    $self->{errno} = $err_no;

    if ($p{level} eq 'debug') {
        $self->std_log($p{pkg}, $p{file}, $p{line}, $p{message}, $p{trace});
    } else { # info error
        $self->sys_log($p{pkg}, $p{file}, $p{line}, $p{message});
    }
}

##
# 文字列取得
#
# @param[in] @p メッセージ
# @return 文字列
sub message($)
{
    my $self = shift;
    my $logmsg = shift;
    my $errstr = '';

    $errstr = sprintf("%s(%d)", $self->{errno}, $self->{errno})
                  or print "sprintf error";

    if ($logmsg cmp '') {
        $logmsg .= $self->{errno} ? (': ' . $errstr) : $errstr;
    } else {
        $logmsg .= $errstr;
    }
    return $logmsg;
}

##
# 時刻文字列取得
#
# @return 時刻
sub get_time()
{
    my $self = shift;
    my ($sec, $min, $hour, $mday, $mon, $year) = 0;

    ($sec, $min, $hour, $mday, $mon, $year,
     undef, undef, undef) = localtime(time);

    return sprintf("%04d-%02d-%02d %02d:%02d:%02d", 
                   $year + 1900, $mon + 1, $mday, $hour, $min, $sec)
               or print "sprintf error";
}

##
# マイクロ秒文字列取得
#
# @return マイクロ秒
sub get_msec()
{
    my $self = shift;
    my $msec = 0;

    (undef, $msec) = gettimeofday();

    return sprintf("%06g", $msec) or print "sprintf error";
}

##
# 標準出力にログ出力
#
# @param[in] $pkg パッケージ名
# @param[in] $file ファイル名
# @param[in] $line 行番号
# @param[in] $message メッセージ
# @param[in] $trace トレース
sub std_log($$$$;$)
{
    my ($self, $pkg, $file, $line, $message, $trace) = @_;
    my $logmsg = '';
    my $msg = '';

    if ($self->{trace}) {
        $msg = $self->message($message) . "\n$trace";
    } else {
        $msg = $self->message($message);
    }
    $logmsg = sprintf("[%s.%s]: %s[%s]: %s[%s]: %s: %s\n",
                      $self->get_time(),
                      $self->get_msec(),
                      $progname,
                      $$, 
                      $file,
                      $line,
                      $pkg,
                      $msg) or print "sprintf error";

    my $FH = $self->{fh} || \*STDERR;
    print $FH $logmsg or print "print error";
}

##
# シスログに出力
#
# @param[in] $pkg パッケージ名
# @param[in] $file ファイル名
# @param[in] $line 行番号
# @param[in] $message メッセージ
sub sys_log($$$$)
{
    my ($self, $pkg, $file, $line, $message) = @_;
    my $logmsg = '';

    $logmsg = sprintf "[%06g] %s[%s]: %s: %s",
                      $self->get_msec(),
                      $file,
                      $line,
                      $pkg,
                      $self->message($message) or print "sprintf error";

    openlog($progname, 'cons.pid', 'syslog')
        or print "openlog error";
    syslog($self->{level}, $logmsg)
        or print "syslog error";
    closelog()
        or print "closelog error";
}

1;

__END__

