#!/usr/bin/perl -w

##
# @file tcard.pl
#
# タイムカードを操作する.
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
use Tk;

our $VERSION = do { my @r = ( q$Revision: 0.01 $ =~ /\d+/g );
    sprintf "%d." . "%02d" x $#r, @r if (@r);
};

my $progname = basename($0);
my $progpath;
BEGIN { $progpath = dirname($0); }
use lib "$progpath/lib";
use gui;

# ステータス
my %stathash = (
    'EX_OK' => 0,    # 正常終了
    'EX_NG' => 1,    # 異常終了
);

# デフォルトオプション
my %opt = (
    'dir'     => '.',
    'cid'     => 'ssn00265',
    'id'      => 'higashit',
    'pw'      => 'higashit',
    'month'   => undef,
    'ssl'     => 0,
    'port'    => 80,
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
   -c, --cid        Set cid.
   -i, --id         Set id.
   -w, --pw         Set pw.
   -m, --month      Set month.
   -s, --ssl        SSL.
   -p, --port       This parameter sets port number default $opt{port}.
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
    'cid|c:s'   => \$opt{'cid'},
    'id|i:s'    => \$opt{'id'},
    'pw|w:s'    => \$opt{'pw'},
    'month|m:s' => \$opt{'month'},
    'ssl|s'     => \$opt{'ssl'},
    'port|p:i'  => \$opt{'port'},
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

# エンコード
my ( $enc, $dec );
if ( $^O eq "MSWin32" ) {
    $enc = 'Shift_JIS';
    $dec = 'Shift_JIS';
}
else {
    $enc = 'UTF-8';
    $dec = 'Shift_JIS';
}

my $start    = "s_go";
my $stop     = "s_leave";
my $download = "s_dloadb";
my $url      = "https://h1.teki-pakinets.com/";
my $home     = $url . "cgi-bin/asp/000265/dnet.cgi?";
my $login    = $url . "cgi-bin/ppzlogin.cgi";
my $tcard    = "xinfo.cgi?page=tcardindex&log=on";

my ( undef, undef, undef, undef, $mon, $year ) = localtime(time);
my $month = sprintf( "%04d%02d", $year + 1900, $mon + 1 );
my $filename = $opt{'dir'} . "/" . $month . ".csv";

my $mech = new WWW::Mechanize( autocheck => 1 );

sub login {
    $mech->get($login);
    print $mech->content if $opt{'vorbis'};

    $mech->submit_form(
        form_name => 'sf_auth',
        fields    => {
            userid   => $opt{'cid'},
            gwuserid => $opt{'id'},
            gwpasswd => $opt{'pw'},
        },
    );
    print $mech->content if $opt{'vorbis'};

    $mech->click();
    print $mech->content if $opt{'vorbis'};
}

sub tcard {
    login();
    $mech->get($home);
    print $mech->content if $opt{'vorbis'};

    $mech->follow_link( url => $tcard );
    print $mech->content if $opt{'vorbis'};
}

sub start {
    tcard();
    $mech->submit_form( button => $start );
}

sub stop {
    tcard();
    $mech->submit_form( button => $stop );
}

sub download {
    tcard();
    $mech->submit_form( button => $download );
    print encode( $enc, decode( $dec, $mech->content ) ) if $opt{'vorbis'};
    $mech->save_content($filename);
}

sub tk_window {
    my ( $text, $func ) = @_;

    my $mw = MainWindow->new();
    $mw->geometry("200x100");
    $mw->resizable( 0, 0 );
    $mw->Label( -textvariable => \$text )->pack();
    $mw->Button( -text => 'Cancel', -command => \&exit )
      ->pack( -side => 'right', -expand => 1 );
    $mw->Button( -text => 'OK', -command => $func )
      ->pack( -side => 'left', -expand => 1 );

    MainLoop();
}

if ( $opt{'nogui'} ) {
    if ( $opt{'start'} ) {
        start();
    }
    elsif ( $opt{'stop'} ) {
        stop();
    }
    else {
        download();
    }
}
else {
    if ( $opt{'start'} ) {
        tk_window( "Go", \&start );
    }
    elsif ( $opt{'stop'} ) {
        tk_window( "Leave", \&stop );
    }
    else {
        tk_window( "Download", \&download );
    }
}
exit( $stathash{'EX_OK'} );

