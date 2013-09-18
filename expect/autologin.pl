#!/usr/bin/perl -w

##
# @file autologin.pl
#
# 自動ログイン
#
# @author Tetsuya Higashi
#

use strict;
use warnings;
use File::Basename;
use Tk;
use Tk::NoteBook;
use File::Spec::Functions;
use YAML;
use Log::Log4perl;

our $VERSION = do { my @r = ( q$Revision: 0.01 $ =~ /\d+/g );
    sprintf "%d." . "%02d" x $#r, @r if (@r);
};

my $progname = basename($0);
my $progdir  = dirname( readlink($0) || $0 );
my $logconf = $progdir . '/' . "log4perl.conf";
my $passwdconf = "passwd.conf";

# ステータス
my %stathash = (
    'EX_OK' => 0,    # 正常終了
    'EX_NG' => 1,    # 異常終了
);

# デフォルトオプション
my %opt = (
    'gateway'  => '',
    'target'   => '',
    'guser'    => '',
    'gpass'    => '',
    'tuser'    => '',
    'tpass'    => '',
    'identity' => '',
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
   -g, --gateway=hostname  Hostname or ip address for gateway.
   -t, --target=hostname   Hostname or ip address for target.
       --guser             Gateway username.
       --gpass             Gateway password.
       --tuser             Target username.
       --tpass             Target password.
   -i  --identity          Selects a file from which the identity file.
       --nogui             Command line interface.
   -v, --vorbis            Display extra information.
   -h, --help              Display this help and exit.
   -V, --version           Output version information and exit.
EOF
}

# オプション引数
Getopt::Long::Configure(qw{no_getopt_compat no_auto_abbrev no_ignore_case});
GetOptions(
    'gateway|g=s' => \$opt{'gateway'},
    'target|t=s'  => \$opt{'target'},
    'guser=s'     => \$opt{'guser'},
    'gpass=s'     => \$opt{'gpass'},
    'tuser=s'     => \$opt{'tuser'},
    'tpass=s'     => \$opt{'tpass'},
    'identity=s'  => \$opt{'identity'},
    'nogui'       => \$opt{'nogui'},
    'vorbis|v'    => \$opt{'vorbis'},
    'help|h|?'    => \$opt{'help'},
    'version|V'   => \$opt{'version'}
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
if ( !$opt{'guser'} || !$opt{'gpass'} || !$opt{'tuser'} || !$opt{'tpass'} ) {

    #　設定ファイル
    my $confdir = $ENV{'HOME'} || undef;
    $confdir = $progdir
      if ( !defined $confdir || !-f catfile( $confdir, $passwdconf ) );
    $config_file = catfile( $confdir, $passwdconf );
    print $config_file . "\n" if ( $opt{'vorbis'} );
    $config = eval { YAML::LoadFile($config_file) } || {};
}

$opt{'guser'} = $config->{'guser'} unless ( $opt{'guser'} );
$opt{'gpass'} = $config->{'gpass'} unless ( $opt{'gpass'} );
$opt{'tuser'} = $config->{'tuser'} unless ( $opt{'tuser'} );
$opt{'tpass'} = $config->{'gpass'} unless ( $opt{'tpass'} );
$log->info("guser=", $opt{'guser'}, " gpass=", $opt{'gpass'},
           " tuser=", $opt{'tuser'}, " tpass=", $opt{'tpass'});
if ( !$opt{'guser'} || !$opt{'gpass'} || !$opt{'tuser'} || !$opt{'tpass'} ) {
    $log->error("guser=", $opt{'guser'}, " gpass=", $opt{'gpass'},
                " tuser=", $opt{'tuser'}, " tpass=", $opt{'tpass'});
    exit( $stathash{'EX_NG'} );
}



exit( $stathash{'EX_OK'} );

__END__

