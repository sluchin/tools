#!/usr/bin/perl -w

##
# @file tcard.pl
#
# disknet's NEO タイムカードを操作する.
#
# @author Tetsuya Higashi
#

use strict;
use warnings;
use File::Basename;
use Getopt::Long;
use Socket;
use bytes();
use URI::Escape;
use Encode qw/encode decode/;
use WWW::Mechanize;
use HTTP::Cookies;
use JSON;
use Tk;
use File::Spec::Functions;
use YAML;

our $VERSION = do { my @r = ( q$Revision: 0.01 $ =~ /\d+/g );
    sprintf "%d." . "%02d" x $#r, @r if (@r);
};

my $progname = basename($0);
my $progdir = dirname( readlink($0) || $0 );

# ステータス
my %stathash = (
    'EX_OK' => 0,    # 正常終了
    'EX_NG' => 1,    # 異常終了
);

# デフォルトオプション
my %opt = (
    'dir'     => '',
    'id'      => '',
    'pw'      => '',
    'month'   => undef,
    'start'   => 0,
    'stop'    => 0,
    'nogui'   => 0,
    'vorbis'  => 0,
    'help'    => 0,
    'version' => 0
);

##
# バージョン情報表示
#
sub print_version() {
    print "$progname version "
      . $VERSION . "\n"
      . "  running on Perl version "
      . join( ".", map { $_ ||= 0; $_ * 1 } ( $] =~ /(\d)\.(\d{3})(\d{3})?/ ) )
      . "\n";
    exit( $stathash{'EX_OK'} );
}

##
# ヘルプ表示
#
sub usage() {
    print << "EOF"
Usage: $progname [options]
   -d, --dir        Output directory.
   -i, --id         Set id.
   -w, --pw         Set pw.
   -m, --month      Set month.
       --start      Start time card.
       --stop       Stop time card.
       --nogui      Command line interface.
   -v, --vorbis     Display extra information.
   -h, --help       Display this help and exit.
   -V, --version    Output version information and exit.
EOF
}

# オプション引数
Getopt::Long::Configure(qw{no_getopt_compat no_auto_abbrev no_ignore_case});
GetOptions(
    'dir|d:s'   => \$opt{'dir'},
    'id|i:s'    => \$opt{'id'},
    'pw|w:s'    => \$opt{'pw'},
    'month|m:s' => \$opt{'month'},
    'start'     => \$opt{'start'},
    'stop'      => \$opt{'stop'},
    'nogui'     => \$opt{'nogui'},
    'vorbis|v'  => \$opt{'vorbis'},
    'help|h|?'  => \$opt{'help'},
    'version|V' => \$opt{'version'}
  )
  or usage()
  and exit( $stathash{'EX_NG'} );

usage() and exit( $stathash{'EX_OK'} ) if ( $opt{'help'} );
print_version() if ( $opt{'version'} );

# 設定ファイル読み込み(オプション引数の方が優先度高い)
my ( $config_file, $config );
if ( !$opt{'id'} || !$opt{'pw'} || !$opt{'dir'} ) {

    #　設定ファイル
    my $conf_dir = $ENV{'HOME'} || undef;
    my $conf_name = ".tcard.conf";
    $conf_dir = $progdir
      if ( !defined $conf_dir || !-f catfile( $conf_dir, $conf_name ) );
    $config_file = catfile( $conf_dir, $conf_name );
    print $config_file . "\n" if ( $opt{'vorbis'} );
    $config = eval { YAML::LoadFile($config_file) } || {};
}

# ディレクトリ
$opt{'dir'} = $config->{'dir'} unless ( $opt{'dir'} );
$opt{'dir'} = "." unless ( $opt{'dir'} );
print $opt{'dir'} . "\n" if $opt{'vorbis'};

# ユーザ
$opt{'id'} = $config->{'user'} unless ( $opt{'id'} );
die "no user" unless ( $opt{'id'} );
print $opt{'id'} . "\n" if $opt{'vorbis'};

# パスワード
$opt{'pw'} = $config->{'passwd'} unless ( $opt{'pw'} );
die "no passwd" unless ( $opt{'pw'} );
print $opt{'pw'} . "\n" if $opt{'vorbis'};

# エンコード
my ( $enc, $dec );
if ( $^O eq "MSWin32" ) {
    $enc = 'Shift_JIS';
    $dec = 'Shift_JIS';
}
elsif ( $^O eq "cygwin" ) {
    $enc = 'UTF-8';
    $dec = 'Shift_JIS';
}
else {
    $enc = 'UTF-8';
    $dec = 'Shift_JIS';
}

my $url      = "https://itec-hokkaido.dn-cloud.com/";
my $home     = $url . "cgi-bin/dneo/dneo.cgi";
my $login    = $url . "cgi-bin/dneo/dneo.cgi?cmd=login";
my $tcardlnk = "ztcard.cgi?cmd=tcardindex";
my $tcard    = $url . "cgi-bin/dneo/zrtcard.cgi";

my ( undef, undef, undef, $mday, $mon, $year ) = localtime(time);
my $date = sprintf( "%04d%02d%02d", $year + 1900, $mon + 1, $mday );

unless ( defined $opt{'month'} ) {
    my ( undef, undef, undef, undef, $mon, $year ) = localtime(time);
    $opt{'month'} = substr( $date, 0, 6 );
}

my $filename = $opt{'dir'} . "/" . $opt{'month'} . ".csv";

my $cookie_jar;
my $mech;
my $session_id;
my ( $token, $prid );
my $json;

sub login {

    # cookie_jarの生成
    $cookie_jar = HTTP::Cookies->new(
        file           => "cookie.txt",
        autosave       => 1,
        ignore_discard => 1
    );

    $mech = WWW::Mechanize->new( autocheck => 1, cookie_jar => $cookie_jar );

    $mech->agent_alias('Linux Mozilla');
    $mech->get($login);
    print encode( $enc, $mech->content ) if $opt{'vorbis'};

    $mech->submit_form(
        fields => {
            cmd     => 'certify',
            nexturl => 'dneo.cgi?cmd=login',
            UserID  => $opt{'id'},
            _word   => $opt{'pw'},
            svlid   => 1,
        },
    );
    die "Can't login: ", $mech->response->status_line
      unless $mech->success;
    print encode( $enc, $mech->content ) . "\n" if $opt{'vorbis'};
    $json = decode_json( encode( 'utf8', $mech->content ) )
      or die "malformed JSON string: $!: ", encode( 'utf8', $mech->content );

    $session_id =
        "dnzSid="
      . ( encode( 'utf8', $json->{'rssid'} ) || "" ) . ";"
      . "dnzToken="
      . ( encode( 'utf8', $json->{'STOKEN'} ) || "" ) . ";"
      . "dnzSv="
      . ( encode( 'utf8', $json->{'dnzSv'} ) || "" ) . ";"
      . "dnzInfo="
      . ( encode( 'utf8', $json->{'id'} ) || "" );
    $token = $json->{'STOKEN'};
    $prid  = $json->{'id'};

    if ( $opt{'vorbis'} ) {
        print $session_id . "\n";
        map { print encode( 'utf8', "$_ => $json->{$_}\n" ) } keys $json;
    }

    $mech->add_header( Cookie => $session_id );
    $mech->get($login);
    die "Can't login: ", $mech->response->status_line
      unless $mech->success;
    print encode( $enc, $mech->content ) if $opt{'vorbis'};
}

sub logout {
    $mech->add_header(
        Accept             => 'application/json,text/javascript,*/*',
        'Accept-Language'  => 'ja, en-us',
        'Accept-Encoding'  => 'gzip, deflate',
        'Content-Type'     => 'application/x-www-form-urlencoded',
        charset            => 'UTF-8',
        'X-Requested-With' => 'XMLHttpRequest',
        Referer            => $home . '?',
        Cookie             => $session_id,
        Connection         => 'keep-alive',
        Pragma             => 'no-cache',
        'Cache-Control'    => 'no-cache',
    );
    my $response = $mech->post(
        $home,
        [
            cmd    => "logout",
            $token => 1
        ]
    );
    print encode( $enc, $mech->content ) if $opt{'vorbis'};
}

sub tcard {
    my $arg = shift;

    login();
    $mech->add_header(
        Accept          => 'application/json,text/javascript,*/*',
        Referer         => $home . '?',
        Cookie          => $session_id,
        Connection      => 'keep-alive',
        Pragma          => 'no-cache',
        'Cache-Control' => 'no-cache',
    );
    my $response = $mech->post(
        $tcard,
        [
            multicmd => "{\"0\":{\"cmd\":\"tcardcmdstamp\",\"mode\":\"" 
              . $arg
              . "\"},\"1\":{\"cmd\":\"tcardcmdtick\"}}",
            $token => 1
        ]
    );
    print encode( $enc, $mech->content ) if $opt{'vorbis'};
    logout;
}

sub tcard_dl {
    my $tdate = shift;

    login();

    # ディレクトリの存在確認
    unless ( -d $opt{'dir'} ) {
        print "no directory: ", $opt{'dir'};
        exit( $stathash{'EX_NG'} );
    }
    $mech->follow_link( url => $tcardlnk );
    print encode( $enc, $mech->content ) if $opt{'vorbis'};
    $mech->submit_form(
        fields => {
            cmd  => 'tcardcmdexport',
            date => $tdate,
        },
    );
    print encode( $enc, decode( $dec, $mech->content ) ) if $opt{'vorbis'};
    $mech->save_content($filename);
    logout();
}

sub tcard_edit {
    my $edate = shift;
    my $stime = shift || '';
    my $etime = shift || '';

    my $id = substr( $edate, 6, 2 );
    print $id . "\n" if $opt{'vorbis'};

    login();
    $mech->follow_link( url => $tcardlnk );
    print encode( $enc, $mech->content ) if $opt{'vorbis'};

    $mech->add_header(
        Accept          => 'application/json,text/javascript,*/*',
        Referer         => $tcardlnk,
        Cookie          => $session_id,
        Connection      => 'keep-alive',
        Pragma          => 'no-cache',
        'Cache-Control' => 'no-cache',
    );

    my $response = $mech->post(
        $tcard,
        [
            cmd               => 'tcardcmdentry',
            id                => $id,
            prid              => $prid,
            date              => $edate,
            absencereason     => '',
            absencereasonfree => '',
            updatestime       => $stime,
            sreason           => '',
            updateouttime1    => '',
            updateintime1     => '',
            updateouttime2    => '',
            updateintime2     => '',
            updateouttime3    => '',
            updateintime3     => '',
            updateetime       => $etime,
            ereason           => '',
            Note              => '',
            $token            => 1
        ]
    );
    print encode( $enc, $mech->content ) if $opt{'vorbis'};

    logout();
}

# コールバック
sub start {
    login();
    tcard('go');
    logout();
    exit( $stathash{'EX_OK'} );
}

sub stop {
    tcard('leave');
    tcard();
    exit( $stathash{'EX_OK'} );
}

sub download {
    my $d = shift;
    tcard_dl($d);
    exit( $stathash{'EX_OK'} );
}

sub edit {
    my ( $d, $s, $e ) = @_;
    tcard_edit( $d, $s, $e );
    exit( $stathash{'EX_OK'} );
}

# ウィンドウ
sub tk_window {
    my ( $text, $func ) = @_;

    my $mw = MainWindow->new();
    $mw->title( decode( "UTF-8", "タイムカード" ) );
    $mw->geometry("200x100");
    $mw->resizable( 0, 0 );
    $mw->Label( -textvariable => \$text )->pack();
    $mw->Button( -text => 'Cancel', -command => \&exit )
      ->pack( -side => 'right', -expand => 1 );
    $mw->Button( -text => 'OK', -command => $func )
      ->pack( -side => 'left', -expand => 1 );

    MainLoop();
}

if ( $opt{'start'} ) {
    tk_window( decode( "UTF-8", "出勤" ), \&start ) unless ( $opt{'nogui'} );
    start();
}
elsif ( $opt{'stop'} ) {
    tk_window( decode( "UTF-8", "退社" ), \&stop ) unless ( $opt{'nogui'} );
    stop();
}
else {
    tk_window( decode( "UTF-8", "ダウンロード" ), [ \&download, $date ] )
      unless ( $opt{'nogui'} );
    download();
}

exit( $stathash{'EX_OK'} );

