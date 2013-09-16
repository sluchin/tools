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
use Encode qw/encode decode decode_utf8/;
use WWW::Mechanize;
use HTTP::Cookies;
use JSON;
use Tk;
use Tk::NoteBook;
use File::Spec::Functions;
use YAML;
use Log::Log4perl;

our $VERSION = do { my @r = ( q$Revision: 0.01 $ =~ /\d+/g );
    sprintf "%d." . "%02d" x $#r, @r if (@r);
};

my $progname = basename($0);
my $progdir = dirname( readlink($0) || $0 );
my $logconf = $progdir . '/' . "log4perl.conf";

# ステータス
my %stathash = (
    'EX_OK' => 0,    # 正常終了
    'EX_NG' => 1,    # 異常終了
);

# デフォルトオプション
my %opt = (
    'dir'      => '',
    'id'       => '',
    'pw'       => '',
    'date'     => undef,
    'stime'    => undef,
    'etime'    => undef,
    'start'    => 0,
    'stop'     => 0,
    'download' => 0,
    'edit'     => 0,
    'nogui'    => 0,
    'vorbis'   => 0,
    'help'     => 0,
    'version'  => 0
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
   -d, --dir=drectory  Output directory.
   -i, --id=id         Set id.
   -w, --pw=password   Set pw.
   -t, --date=date     Set date.
   -s, --stime=time    Edit time arriving at work.
   -e, --etime=time    Edit time getting away.
       --start         Start time card.
       --stop          Stop time card.
       --download      Download time card.
       --edit          Edit time card.
       --nogui         Command line interface.
   -v, --vorbis        Display extra information.
   -h, --help          Display this help and exit.
   -V, --version       Output version information and exit.
EOF
}

# オプション引数
Getopt::Long::Configure(qw{no_getopt_compat no_auto_abbrev no_ignore_case});
GetOptions(
    'dir|d:s'   => \$opt{'dir'},
    'id|i:s'    => \$opt{'id'},
    'pw|w:s'    => \$opt{'pw'},
    'date|t:s'  => \$opt{'date'},
    'stime|s:s' => \$opt{'stime'},
    'etime|e:s' => \$opt{'etime'},
    'start'     => \$opt{'start'},
    'stop'      => \$opt{'stop'},
    'download'  => \$opt{'download'},
    'edit'      => \$opt{'edit'},
    'nogui'     => \$opt{'nogui'},
    'vorbis|v'  => \$opt{'vorbis'},
    'help|h|?'  => \$opt{'help'},
    'version|V' => \$opt{'version'}
  )
  or usage()
  and exit( $stathash{'EX_NG'} );

usage() and exit( $stathash{'EX_OK'} ) if ( $opt{'help'} );
print_version() if ( $opt{'version'} );

# ログ
Log::Log4perl::init($logconf);
my $log = Log::Log4perl->get_logger('develop');

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
$log->info($opt{'dir'});

# ユーザ
$opt{'id'} = $config->{'user'} unless ( $opt{'id'} );
die "no user" unless ( $opt{'id'} );
print $opt{'id'} . "\n" if $opt{'vorbis'};
$log->info($opt{'id'});

# パスワード
$opt{'pw'} = $config->{'passwd'} unless ( $opt{'pw'} );
die "no passwd" unless ( $opt{'pw'} );
print $opt{'pw'} . "\n" if $opt{'vorbis'};
$log->info($opt{'pw'});

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

if ( defined $opt{'date'} ) {
    unless ( length $opt{'date'} eq 8 ) {
        print $opt{'date'} . "\n";
        usage();
        exit( $stathash{'EX_NG'} );
    }
}
else {
    my ( undef, undef, undef, $mday, $mon, $year ) = localtime(time);
    $opt{'date'} = sprintf( "%04d%02d%02d", $year + 1900, $mon + 1, $mday );
}
$log->debug($opt{'date'});

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
    $log->debug( encode( $enc, $mech->content ) );

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
    $log->debug( encode( $enc, $mech->content ) );
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
    $log->debug( $session_id );

    $mech->add_header( Cookie => $session_id );
    $mech->get($login);
    die "Can't login: ", $mech->response->status_line
      unless $mech->success;
    print encode( $enc, $mech->content ) if $opt{'vorbis'};
    $log->debug( encode( $enc, $mech->content ) );
}

sub logout {
    $mech->add_header(
        'Accept'           => 'application/json,text/javascript,*/*',
        'Accept-Language'  => 'ja, en-us',
        'Accept-Encoding'  => 'gzip, deflate',
        'Content-Type'     => 'application/x-www-form-urlencoded',
        'charset'          => 'UTF-8',
        'X-Requested-With' => 'XMLHttpRequest',
        'Referer'          => $home . '?',
        'Cookie'           => $session_id,
        'Connection'       => 'keep-alive',
        'Pragma'           => 'no-cache',
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
    $log->debug( encode( $enc, $mech->content ) );
}

sub tcard {
    my $arg = shift;

    login();
    $mech->add_header(
        'Accept'        => 'application/json,text/javascript,*/*',
        'Referer'       => $home . '?',
        'Cookie'        => $session_id,
        'Connection'    => 'keep-alive',
        'Pragma'        => 'no-cache',
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
    $log->debug( encode( $enc, $mech->content ) );
    logout;
}

sub tcard_dl {
    my ( $entry, $dt ) = @_;

    # ディレクトリの存在確認
    unless ( -d $opt{'dir'} ) {
        print "no directory: ", $opt{'dir'};
        return;
    }
    $dt = $entry->get if ( defined $entry );
    return unless ( length $dt eq 8 );
    my $filename = $opt{'dir'} . "/" . substr( $dt, 0, 6 ) . ".csv";

    login();

    $mech->follow_link( url => $tcardlnk );
    print encode( $enc, $mech->content ) if $opt{'vorbis'};
    $log->debug( encode( $enc, $mech->content ) );

    $mech->submit_form(
        fields => {
            cmd  => 'tcardcmdexport',
            date => $dt,
        },
    );
    print encode( $enc, decode( $dec, $mech->content ) ) if $opt{'vorbis'};
    $log->info( encode( $enc, decode( $dec, $mech->content ) ) );

    # ファイルに保存
    $mech->save_content($filename);
    logout();
}

sub tcard_edit {
    my ( $entry, $dt, $old, $new ) = @_;

    $dt = $entry->get if ( defined $entry );

    foreach my $key ( keys $new ) {
        if ( exists $old->{$key} && $old->{$key} eq $new->{$key} ) {
            $new->{$key} = undef;
        }
    }
    map { print encode( 'utf8', "$_(new) => " . ( $new->{$_} || '' ) . "\n" ) }
      keys $new if $opt{'vorbis'};

    my $id = substr( $dt, 6, 2 );
    print $id . "\n" if $opt{'vorbis'};

    login();
    $mech->follow_link( url => $tcardlnk );
    print encode( $enc, $mech->content ) if $opt{'vorbis'};
    $log->debug( encode( $enc, $mech->content ) );

    $mech->add_header(
        'Accept'        => 'application/json,text/javascript,*/*',
        'Referer'       => $tcardlnk,
        'Cookie'        => $session_id,
        'Connection'    => 'keep-alive',
        'Pragma'        => 'no-cache',
        'Cache-Control' => 'no-cache',
    );

    my $response = $mech->post(
        $tcard,
        [
            'cmd'               => 'tcardcmdentry',
            'id'                => ( $id || '' ),
            'prid'              => ( $prid || '' ),
            'date'              => ( $dt || '' ),
            'absencereason'     => '',
            'absencereasonfree' => '',
            'updatestime'       => ( $new->{'stime'} || '' ),
            'sreason'           => ( $new->{'sreason'} || '' ),
            'updateouttime1'    => '',
            'updateintime1'     => '',
            'updateouttime2'    => '',
            'updateintime2'     => '',
            'updateouttime3'    => '',
            'updateintime3'     => '',
            'updateetime'       => ( $new->{'etime'} || '' ),
            'ereason'           => ( $new->{'ereason'} || '' ),
            'Note'              => ( $new->{'note'} || '' ),
            $token              => 1,
        ]
    );
    print encode( $enc, $mech->content ) if $opt{'vorbis'};
    $log->info( encode( $enc, $mech->content ) );

    logout();
}

sub get_time {
    my ( $entry, $dt, $old, $new ) = @_;

    $dt = $entry->get if ( defined $entry );
    return unless ( length $dt eq 8 );
    my $year = substr( $dt, 0, 4 );
    my $mon  = substr( $dt, 4, 2 );
    my $day  = substr( $dt, 6, 2 );

    $dt = $year . '/' . $mon . '/' . $day;

    login();

    $mech->follow_link( url => $tcardlnk );
    print encode( $enc, $mech->content ) if $opt{'vorbis'};
    $log->debug( encode( $enc, $mech->content ) );

    $mech->submit_form(
        fields => {
            cmd  => 'tcardcmdexport',
            date => $dt,
        },
    );
    print encode( $enc, decode( $dec, $mech->content ) ) if $opt{'vorbis'};
    $log->debug( encode( $enc, decode( $dec, $mech->content ) ) );

    my @lines = split /\r\n/, decode( $dec, $mech->content );
    for my $line (@lines) {
        $line = decode_utf8($line);

        my ( $date, $stime, $etime, $sreason, $ereason, $areason, $note );
        (
            $date, undef,    $stime,   undef, undef,  $sreason,
            undef, undef,    undef,    undef, $etime, undef,
            undef, $ereason, $areason, $note
        ) = split( /,/, $line );

        if ( $date eq $dt ) {
            $stime =~ s/://;
            $etime =~ s/://;
            $note  =~ s/^"//;
            $note  =~ s/"$//;
            $old->{'stime'}   = $stime;
            $old->{'etime'}   = $etime;
            $old->{'sreason'} = $sreason;
            $old->{'ereason'} = $ereason;
            $old->{'areason'} = $areason;
            $old->{'note'}    = $note;
            last;
        }
    }
    logout();

    foreach my $key ( keys $old ) {
        $new->{$key} = $old->{$key};
    }
    map { $log->debug( encode( 'utf8', "$_ => " . ( $new->{$_} || '' ) . "\n" ) ) }
      keys $new
}

# コールバック
sub start {
    login();
    tcard('go');
    logout();
}

sub stop {
    tcard('leave');
    tcard();
}

sub download {
    my ( $entry, $d ) = @_;
    tcard_dl( $entry, $d );
}

sub edit {
    my ( $entry, $d, $old, $new ) = @_;
    tcard_edit( $entry, $d, $old, $new );
}

# ウィンドウ
sub tk_part {
    my ( $text, $func ) = @_;

    my $mw = MainWindow->new();
    $mw->title( decode_utf8("タイムカード") );
    $mw->geometry("200x100");
    $mw->resizable( 0, 0 );
    $mw->Label( -textvariable => \$text )->pack();
    $mw->Button( -text => 'Cancel', -command => \&exit )
      ->pack( -side => 'right', -expand => 1 );
    $mw->Button( -text => 'OK', -command => $func )
      ->pack( -side => 'left', -expand => 1 );

    MainLoop();
}

sub tk_all {
    my ( %old, %new );
    $new{'stime'} = $opt{'stime'} if ( defined $opt{'stime'} );
    $new{'etime'} = $opt{'etime'} if ( defined $opt{'etime'} );

    my $mw = MainWindow->new();
    $mw->title( decode_utf8("タイムカード") );
    $mw->geometry("500x300");
    $mw->resizable( 0, 0 );

    my $book = $mw->NoteBook()->pack( -fill => 'both', -expand => 1 );

    my $tab1 = $book->add( "Sheet 1", -label => decode_utf8("出社/退社") );
    my $tab2 = $book->add( "Sheet 2", -label => decode_utf8("編集") );

    $tab1->Button( -text => decode_utf8("出社"), -command => \&stop )
      ->grid( -row => 1, -column => 3, -padx => 15, -pady => 15 );
    $tab1->Button( -text => decode_utf8("退社"), -command => \&start )
      ->grid( -row => 2, -column => 3, -padx => 15, -pady => 15 );

    $tab1->Label( -text => decode_utf8("日付: ") )
      ->grid( -row => 3, -column => 1 );
    my $entry1 = $tab1->Entry( -text => \$opt{'date'}, -width => 10 );
    $entry1->grid( -row => 3, -column => 2, -padx => 15, -pady => 15 );
    $tab1->Button(
        -text    => decode_utf8("ダウンロード"),
        -command => [ \&download, $entry1, $opt{'date'} ]
    )->grid( -row => 3, -column => 3, -padx => 15, -pady => 15 );
    $tab1->Button( -text => decode_utf8("終了"), -command => \&exit )
      ->grid( -row => 4, -column => 4, -padx => 15, -pady => 15 );

    $tab2->Label( -text => decode_utf8("日付: ") )
      ->grid( -row => 1, -column => 1, -pady => 5 );
    my $entry2 = $tab2->Entry( -text => \$opt{'date'}, -width => 10 );
    $entry2->grid( -row => 1, -column => 2, -pady => 5 );
    $tab2->Button(
        -text    => decode_utf8("読込"),
        -command => [ \&get_time, $entry2, $opt{'date'}, \%old, \%new ]
    )->grid( -row => 1, -column => 3, -padx => 5, -pady => 5 );

    $tab2->Label( -text => decode_utf8("出社: ") )
      ->grid( -row => 2, -column => 1, -pady => 5 );
    $tab2->Entry( -textvariable => \$new{'stime'}, -width => 10 )
      ->grid( -row => 2, -column => 2, -pady => 5 );
    $tab2->Label( -text => decode_utf8("遅刻事由: ") )
      ->grid( -row => 2, -column => 3, -padx => 5, -pady => 5 );
    $tab2->Entry( -textvariable => \$new{'sreason'}, -width => 20 )
      ->grid( -row => 2, -column => 4, -pady => 5 );

    $tab2->Label( -text => decode_utf8("退社: ") )
      ->grid( -row => 3, -column => 1, -pady => 5 );
    $tab2->Entry( -textvariable => \$new{'etime'}, -width => 10 )
      ->grid( -row => 3, -column => 2, -pady => 5 );
    $tab2->Label( -text => decode_utf8("早退事由: ") )
      ->grid( -row => 3, -column => 3, -padx => 5, -pady => 5 );
    $tab2->Entry( -textvariable => \$new{'ereason'}, -width => 20 )
      ->grid( -row => 3, -column => 4, -pady => 5 );

    $tab2->Label( -text => decode_utf8("備考: ") )
      ->grid( -row => 4, -column => 1, -pady => 5 );
    $tab2->Entry( -textvariable => \$new{'note'}, -width => 42 )
      ->grid( -row => 4, -column => 2, -columnspan => 3, -pady => 5 );

    $tab2->Button(
        -text    => decode_utf8("編集"),
        -command => [ \&edit, $entry2, $opt{'date'}, \%old, \%new ]
    )->grid( -row => 5, -column => 4, -pady => 10 );

    $tab2->Button( -text => decode_utf8("終了"), -command => \&exit )
      ->grid( -row => 6, -column => 5, -padx => 15, -pady => 15 );

    MainLoop();
}

if ( $opt{'start'} ) {
    tk_part( decode_utf8("出社"), \&start )
      and exit( $stathash{'EX_OK'} )
      unless ( $opt{'nogui'} );
    start();
}
elsif ( $opt{'stop'} ) {
    tk_part( decode_utf8("退社"), \&stop )
      and exit( $stathash{'EX_OK'} )
      unless ( $opt{'nogui'} );
    stop();
}
elsif ( $opt{'download'} ) {
    tk_part(
        decode_utf8("ダウンロード"),
        [ \&download, undef, $opt{'date'} ]
      )
      and exit( $stathash{'EX_OK'} )
      unless ( $opt{'nogui'} );
    download();
}
elsif ( $opt{'edit'} ) {
    my ( %old, %new );
    usage() and exit( $stathash{'EX_NG'} )
      unless ( defined $opt{'stime'} || defined $opt{'etime'} );
    $new{'stime'} = $opt{'stime'};
    $new{'etime'} = $opt{'etime'};
    tk_part( decode_utf8("編集"),
        [ \&edit, undef, $opt{'date'}, \%old, \%new ] )
      and exit( $stathash{'EX_OK'} )
      unless ( $opt{'nogui'} );
    edit();
}
else {
    tk_all();
}

exit( $stathash{'EX_OK'} );

__END__

