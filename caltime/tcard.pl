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
use File::Basename qw/basename dirname/;
use File::Spec::Functions qw/catfile/;
use Getopt::Long qw/GetOptions Configure/;
use Encode qw/encode decode decode_utf8/;
use WWW::Mechanize qw/post/;
use HTTP::Cookies;
use JSON qw/decode_json/;
use YAML qw/LoadFile Dump/;
use Log::Dispatch;

our $VERSION = do { my @r = ( q$Revision: 0.03 $ =~ /\d+/g );
    sprintf "%d." . "%02d" x $#r, @r if (@r);
};

my $progname = basename($0);
my $progdir;

BEGIN {
    $progdir = dirname( readlink($0) || $0 );
    push( @INC, $progdir . '/lib' );
}

my $logfile  = catfile( $progdir, "tcard.log" );
my $confname = "tcard.conf";
my $iconfile = catfile( $progdir, "icon", "icon.xpm" );

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

# バージョン情報表示
sub print_version() {
    print "$progname version "
      . $VERSION . "\n"
      . "  running on Perl version "
      . join( ".", map { $_ ||= 0; $_ * 1 } ( $] =~ /(\d)\.(\d{3})(\d{3})?/ ) )
      . "\n";
    exit( $stathash{'EX_OK'} );
}

# ヘルプ表示
sub usage() {
    require Pod::Usage;
    import Pod::Usage;
    pod2usage();
}

# オプション引数
Configure(qw{no_getopt_compat no_auto_abbrev no_ignore_case});
GetOptions(
    'dir|d=s'   => \$opt{'dir'},
    'id|i=s'    => \$opt{'id'},
    'pw|w=s'    => \$opt{'pw'},
    'date|t=s'  => \$opt{'date'},
    'stime|s=s' => \$opt{'stime'},
    'etime|e=s' => \$opt{'etime'},
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

# Tk ない場合, コマンドラインのみ
eval 'use Tk; 1'            || ( $opt{'nogui'} = 1 );
eval 'use Tk::NoteBook; 1'  || ( $opt{'nogui'} = 1 );
eval 'use Tk::DateEntry; 1' || ( $opt{'nogui'} = 1 );
eval 'use Tk::Table; 1'     || ( $opt{'nogui'} = 1 );

use Tk::Tcard;

print $opt{'nogui'} . "\n";

# メッセージ
my $mw;

sub messagebox {
    my ( $level, $mes ) = @_;
    if ( Exists($mw) ) {
        $mw->messageBox(
            -type    => 'Ok',
            -icon    => 'error',
            -title   => decode_utf8("エラー"),
            -message => $mes || ''
        ) if ( lc $level eq 'error' );
        $mw->messageBox(
            -type    => 'Ok',
            -icon    => 'warning',
            -title   => decode_utf8("警告"),
            -message => $mes || ''
        ) if ( lc $level eq 'warning' );
    }
}

# ログ出力
sub filecb {
    my %args = @_;
    my ( $pkg, $file, $line );
    my $caller = 0;
    while ( ( $pkg, $file, $line ) = caller($caller) ) {
        last if $pkg !~ m!^Log::Dispatch!;
        $caller++;
    }
    chomp( $args{'message'} );
    my @time = localtime;
    messagebox( $args{'level'}, $args{'message'} );
    sprintf "%04d-%02d-%02d %02d:%02d:%02d [%s] %s at %s line %d.\n",
      $time[5] + 1900, $time[4] + 1, @time[ 3, 2, 1, 0 ],
      $args{'level'}, $args{'message'}, $file, $line;
}

sub screencb {
    my %args = @_;
    chomp( $args{'message'} );
    sprintf $args{'message'} . "\n";
}

my $log = Log::Dispatch->new(
    outputs => [
        [
            'File',
            'min_level' => 'debug',
            'filename'  => $logfile,
            'mode'      => 'append',
            'callbacks' => \&filecb
        ],
        [
            'Screen',
            'min_level' => $opt{'vorbis'} ? 'debug' : 'info',
            'callbacks' => \&screencb
        ],
    ],
);

$log->debug("@INC");

# 設定ファイル読み込み(オプション引数の方が優先度高い)
my ( $config, $configfile );

sub load_config {

    #　設定ファイル
    my $confdir = $ENV{'HOME'} || undef;
    $confdir = $progdir
      if ( !defined $confdir || !-f catfile( $confdir, $confname ) );
    $configfile = catfile( $confdir, $confname );
    $log->info($configfile);
    $config = eval { LoadFile($configfile) } || {};
}

# 設定ファイル書き込み
sub dump_config {
    my ( $dir, $id, $pw ) = @_;

    $log->debug( $dir->get || '', $id->get || '', $pw->get || '' );
    load_config() if ( -f $configfile );
    $opt{'dir'} = $dir->get || $config->{'dir'};
    $opt{'id'}  = $id->get  || $config->{'user'};
    $opt{'pw'}  = $pw->get  || $config->{'passwd'};
    my $hash = {
        'dir'    => $opt{'dir'},
        'user'   => $opt{'id'},
        'passwd' => $opt{'pw'},
    };
    open my $cf, ">", $configfile
      or $log->error( "open[$configfile]:", $! );
    print $cf Dump $hash;
    close $cf;
}

load_config() if ( !$opt{'id'} || !$opt{'pw'} || !$opt{'dir'} );

# ディレクトリ
$opt{'dir'} = $config->{'dir'} unless ( $opt{'dir'} );
$opt{'dir'} = "." unless ( $opt{'dir'} );
$log->info( "dir:", $opt{'dir'} || '' );

# ユーザ
$opt{'id'} = $config->{'user'} unless ( $opt{'id'} );
$log->info( "id:", $opt{'id'} || '' );

# パスワード
$opt{'pw'} = $config->{'passwd'} unless ( $opt{'pw'} );
$log->info( "pw:", $opt{'pw'} || '' );

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
$log->debug( "date:", $opt{'date'} || '' );

my $cookie_jar;
my $mech;
my $session_id;
my ( $token, $prid );
my ( %old,   %new );

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
    $log->error( "Can't submit_form:", $mech->response->status_line )
      unless $mech->success;
    $log->debug( encode( $enc, $mech->content ) );
    my $json = decode_json( encode( $enc, $mech->content ) )
      or $log->error( "malformed JSON string: $!:",
        encode( $enc, $mech->content ) );

    $session_id =
        "dnzSid="
      . ( encode( $enc, $json->{'rssid'} ) || "" ) . ";"
      . "dnzToken="
      . ( encode( $enc, $json->{'STOKEN'} ) || "" ) . ";"
      . "dnzSv="
      . ( encode( $enc, $json->{'dnzSv'} ) || "" ) . ";"
      . "dnzInfo="
      . ( encode( $enc, $json->{'id'} ) || "" );
    $token = $json->{'STOKEN'};
    $prid  = $json->{'id'};

    map { print $log->debug( 'utf8', "$_ => $json->{$_}\n" ) } keys $json
      if ( $opt{'vorbis'} );
    $log->debug($session_id);

    $mech->add_header( Cookie => $session_id );
    $mech->get($login);
    $log->error( "Can't login:", $mech->response->status_line )
      unless $mech->success;
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
    $log->error( "Can't logout:", $mech->response->status_line )
      unless $mech->success;

    $log->debug( encode( $enc, $mech->content ) );
}

sub tcard {
    my $arg = shift;

    $log->warning("no user")   or return unless ( $opt{'id'} );
    $log->warning("no passwd") or return unless ( $opt{'pw'} );

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
    $log->error( "Can't post:", $mech->response->status_line )
      unless $mech->success;
    my $json = decode_json( encode( $enc, $mech->content ) )
      or $log->error( "malformed JSON string: $!:",
        encode( $enc, $mech->content ) );
    my $jsonhash = $json->{'1'};
    $opt{'stime'} = $new{'stime'} = $jsonhash->{'stime'};
    $opt{'etime'} = $new{'etime'} = $jsonhash->{'etime'};
    $log->debug( encode( $enc, $mech->content ) );
    logout;
}

sub tcard_dl {
    my ( $entry, $dt ) = @_;

    $log->warning("no user")    or return unless ( $opt{'id'} );
    $log->warning("no passwd")  or return unless ( $opt{'pw'} );
    $log->error("no directory") or return unless ( -d $opt{'dir'} );

    # ディレクトリの存在確認
    unless ( -d $opt{'dir'} ) {
        $log->error( "no directory:", $opt{'dir'} );
        return;
    }
    $dt = $entry->get if ( defined $entry );
    $log->warning( "date:", $dt || '' ) or return unless ( length $dt eq 8 );
    my $filename = $opt{'dir'} . "/" . substr( $dt, 0, 6 ) . ".csv";

    login();

    $mech->follow_link( url => $tcardlnk );
    $log->error( "Can't follow_link:",
        "$tcardlnk:", $mech->response->status_line )
      unless $mech->success;
    $log->debug( encode( $enc, $mech->content ) );

    $mech->submit_form(
        fields => {
            cmd  => 'tcardcmdexport',
            date => $dt,
        },
    );
    $log->error( "Can't submit_form:", $mech->response->status_line )
      unless $mech->success;
    $log->info( encode( $enc, decode( $dec, $mech->content ) ) );

    # ファイルに保存
    $mech->save_content($filename);
    logout();
}

sub tcard_edit {
    my ( $entry, $dt, $old, $new ) = @_;

    $log->warning("no user")   or return unless ( $opt{'id'} );
    $log->warning("no passwd") or return unless ( $opt{'pw'} );

    $dt = $entry->get if ( defined $entry );
    $log->warning( "date:", $dt || '' )
      or return
      if ( !defined $dt || length $dt ne 8 );

    foreach my $key ( keys $new ) {
        if ( exists $old->{$key} && $old->{$key} eq $new->{$key} ) {
            $new->{$key} = undef;
        }
    }
    map {
        $log->debug( encode( $enc, "$_(new) => " . ( $new->{$_} || '' ) ) )
      }
      keys $new
      if $opt{'vorbis'};

    my $id = substr( $dt, 6, 2 );

    login();
    $mech->follow_link( url => $tcardlnk );
    $log->error(
        "Can't follow_link:",
        $tcardlnk . ":",
        $mech->response->status_line
    ) unless $mech->success;
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
    $log->error( "Can't post:", $tcard . ":", $mech->response->status_line )
      unless $mech->success;
    $log->info( encode( $enc, $mech->content ) );

    logout();
}

sub get_time {
    my ( $entry, $dt, $old, $new ) = @_;

    $log->warning("no user")   or return unless ( $opt{'id'} );
    $log->warning("no passwd") or return unless ( $opt{'pw'} );

    $dt = $entry->get if ( defined $entry );
    $log->warning( "date:", $dt || '' )
      or return
      if ( !defined $dt || length $dt ne 8 );
    my $year = substr( $dt, 0, 4 );
    my $mon  = substr( $dt, 4, 2 );
    my $day  = substr( $dt, 6, 2 );

    $dt = $year . '/' . $mon . '/' . $day;

    login();

    $mech->follow_link( url => $tcardlnk );
    $log->error( "Can't follow_link:",
        "$tcardlnk:", $mech->response->status_line )
      unless $mech->success;
    $log->debug( encode( $enc, $mech->content ) );

    $mech->submit_form(
        fields => {
            cmd  => 'tcardcmdexport',
            date => $dt,
        },
    );
    $log->error( "Can't submit_form:", $mech->response->status_line )
      unless $mech->success;
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
    map { $log->debug( encode( 'utf8', "$_ => " . ( $new->{$_} || '' ) ) ) }
      keys $new;
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

    $new{'stime'} = $opt{'stime'} if ( defined $opt{'stime'} );
    $new{'etime'} = $opt{'etime'} if ( defined $opt{'etime'} );

    $mw = MainWindow->new();
    $mw->title( decode_utf8("タイムカード") . "  [v$VERSION]" );
    $mw->geometry("500x300");
    $mw->resizable( 0, 0 );
    if ( -f $iconfile ) {
        my $image = $mw->Pixmap( -file => $iconfile );
        $mw->Icon( -image => $image );
    }

    my $book = $mw->NoteBook()->pack( -fill => 'both', -expand => 1 );

    my $tab1 = $book->add( "Sheet 1", -label => decode_utf8("出社/退社") );
    my $tab2 = $book->add( "Sheet 2", -label => decode_utf8("編集") );
    my $tab3 = $book->add( "Sheet 4", -label => decode_utf8("設定") );

    #my $tab4 = $book->add( "Sheet 3", -label => decode_utf8("一覧") );
    #my $tab5 = $book->add( "Sheet 4", -label => decode_utf8("ログ") );

    tab_setime( $tab1, $opt{'date'}, \$opt{'stime'}, \$opt{'etime'}, \&tcard, \&tcard_dl );
    tab_edit( $tab2, $opt{'date'}, \%old, \%new, \&get_time, \&tcard_edit );
    tab_conf( $tab3, \&dump_config );

    MainLoop();
}

if ( $opt{'start'} ) {
    tk_part( decode_utf8("出社"), [ \&tcard, "go" ] )
      and exit( $stathash{'EX_OK'} )
      unless ( $opt{'nogui'} );
    tcard("go");
}
elsif ( $opt{'stop'} ) {
    tk_part( decode_utf8("退社"), [ \&tcard, "leave" ] )
      and exit( $stathash{'EX_OK'} )
      unless ( $opt{'nogui'} );
    tcard("leave");
}
elsif ( $opt{'download'} ) {
    tk_part(
        decode_utf8("ダウンロード"),
        [ \&tcard_dl, undef, $opt{'date'} ]
      )
      and exit( $stathash{'EX_OK'} )
      unless ( $opt{'nogui'} );
    tcard_dl( undef, $opt{'date'} );
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
    tcard_edit( undef, $opt{'date'}, \%old, \%new );
}
else {
    if ( $opt{'nogui'} ) {
        $log->warning("No Tk module.");
        usage();
        exit( $stathash{'EX_NG'} );
    }
    else {
        tk_all();
    }
}

exit( $stathash{'EX_OK'} );

__END__

=head1 NAME

tcard.pl - pushed time card.

=head1 SYNOPSIS

tcard.pl [options]

 Options:
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

=over 4

=back

=head1 DESCRIPTION

B<This program> is tool for time card.

tcard.conf:

dir: <Directory for download>
user: <User id>
passwd: <User password>

If ActivePerl, you must install from ppm.

ppm install YAML
ppm install Log-Dispatch

32bit
ppm install http://www.bribes.org/perl/ppm/Tk.ppd
64bit
ppm install http://www.bribes.org/perl/ppm64/Tk.ppd

=cut
