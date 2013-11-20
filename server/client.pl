#!/usr/bin/perl -w
# COPYRIGHT:
#
# Copyright (c) 2013 Tetsuya Higashi
# All rights reserved.
#
# LICENSE:
#
# This work is made available to you under the terms of Version 2 of
# the GNU General Public License. A copy of that license should have
# been provided with this software, but in any event can be snarfed
# from www.gnu.org.
#
# This work is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
# 02110-1301 or visit their web page on the internet at
# http://www.gnu.org/licenses/old-licenses/gpl-2.0.html.

use strict;
use warnings;
use File::Basename qw/basename dirname/;
use File::Spec::Functions qw/catfile/;
use Getopt::Long qw/GetOptions Configure/;
use Socket;
use bytes ();
use Sys::Hostname qw/hostname/;
use Log::Dispatch;

#use Encode qw/encode decode decode_utf8/;

our $VERSION = do { my @r = ( q$Revision: 0.01 $ =~ /\d+/g );
    sprintf "%d." . "%02d" x $#r, @r if (@r);
};

my $progname = basename($0);
my $progdir;

BEGIN {
    $progdir = dirname( readlink($0) || $0 );
    push( @INC, $progdir . '/lib' );
}

my $logfile = catfile( $progdir, "client.log" );
my $iconfile = catfile( $progdir, "icon", "icon.xpm" );

# ステータス
my %stathash = (
    'EX_OK' => 0,    # 正常終了
    'EX_NG' => 1,    # 異常終了
);

# デフォルトオプション
my %opt = (
    'dest'    => 'localhost',
    'port'    => 80,
    'ssl'     => 0,
    'output'  => "client.dat",
    'file'    => undef,
    'dir'     => '',
    'count'   => 1,
    'nogui'   => 0,
    'vorbis'  => 0,
    'help'    => 0,
    'version' => 0
);

# バージョン情報表示
sub print_version {
    print "$progname version " 
      . $VERSION . "\n"
      . "  running on Perl version "
      . join( ".", map { $_ ||= 0; $_ * 1 } ( $] =~ /(\d)\.(\d{3})(\d{3})?/ ) )
      . "\n";
    exit( $stathash{'EX_OK'} );
}

# ヘルプ表示
sub usage {
    require Pod::Usage;
    import Pod::Usage;
    pod2usage();
}

# オプション引数
Getopt::Long::Configure(qw{no_getopt_compat no_auto_abbrev no_ignore_case});
GetOptions(
    'dest|i=s'      => \$opt{'dest'},
    'port|p=i'      => \$opt{'port'},
    'ssl'           => \$opt{'ssl'},
    'output|o=s'    => \$opt{'output'},
    'file|f=s'      => \@{ $opt{'file'} },
    'directory|d=s' => \$opt{'dir'},
    'count|c=i'     => \$opt{'count'},
    'nogui'         => \$opt{'nogui'},
    'vorbis|v'      => \$opt{'vorbis'},
    'help|h|?'      => \$opt{'help'},
    'version|V'     => \$opt{'version'}
  )
  or usage()
  and exit( $stathash{'EX_NG'} );

usage() and exit( $stathash{'EX_OK'} ) if ( $opt{'help'} );
print_version() if ( $opt{'version'} );

my $win = undef;
my $soc = undef;
my $out = undef;

use Http;

if ( !$opt{'nogui'} ) {
    eval { use Tk::HttpClient; };
    if ($@) {
        print "no Tk";
        exit( $stathash{'EX_NG'} );
    }
}

# ログ出力
sub cbfile {
    my %args = @_;
    my ( $pkg, $file, $line );
    my $caller = 0;
    while ( ( $pkg, $file, $line ) = caller($caller) ) {
        last if $pkg !~ m!^Log::Dispatch!;
        $caller++;
    }
    chomp( $args{'message'} );
    my @time = localtime;
    $win->messagebox( $args{'level'}, $args{'message'} ) if ( defined $win );

    sprintf "%04d-%02d-%02d %02d:%02d:%02d [%s] %s at %s line %d.\n",
      $time[5] + 1900, $time[4] + 1, @time[ 3, 2, 1, 0 ],
      $args{'level'}, $args{'message'}, $file, $line;
}

sub cbscreen {
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
            'callbacks' => \&cbfile
        ],
        [
            'Screen',
            'min_level' => $opt{'vorbis'} ? 'debug' : 'info',
            'callbacks' => \&cbscreen
        ],
    ],
);

# ヘッダ
my $send_header = '';

# my $send_header =
# "POST /api HTTP/1.1\nConnection: close\nPragma: no-cache\nHost: "
#   . ( hostname() || "" )
#   . "\nSequenceNo: 0\nContent-type: text/html; charset=utf-8";

# ボディ
my $send_body = '';

# my $send_body = "test";

# シグナル
sub sig_handler {
    close $soc if ( defined $soc );
    close $out if ( defined $out );
    $soc = $out = undef;
    exit( $stathash{'EX_NG'} );
}

$SIG{'INT'} = \&sig_handler;
#$SIG{PIPE} = 'IGNORE';

sub http_client {
    my %args = (
        'dest'   => '',
        'port'   => 80,
        'ssl'    => 0,
        'count'  => 1,
        'text'   => undef,
        'vorbis' => 0,
        'msg'    => '',
        @_
    );

    open $out, ">>", "$opt{'output'}"
      or $log->warning("open[$opt{'output'}]: $!");

    for ( my $i = 0 ; $i < $args{'count'} ; $i++ ) {

        if ( $args{'ssl'} ) {
            eval { use Net::SSLeay qw(die_now die_if_ssl_error); };
            if ( !$@ ) {
                print "Cannot use Net::SSLeay\nTry `cpan Net::SSLeay'\n";
                exit( $stathash{'EX_NG'} );
            }
            Net::SSLeay::load_error_strings();
            Net::SSLeay::SSLeay_add_ssl_algorithms();
            Net::SSLeay::randomize();
        }

        $args{'port'} = getservbyname( $args{'port'}, 'tcp' )
          unless $args{'port'} =~ /^\d+$/;

        print "dest: " . ( $args{'dest'} || '' ) . "\n";
        my $ipaddr = gethostbyname( $args{'dest'} );

        my $dest_params = sockaddr_in( $args{'port'}, $ipaddr )
          or $log->error("Cannot pack: $!");

        socket( $soc, PF_INET, SOCK_STREAM, getprotobyname("tcp") )
          or $log->error("socket: $!");
        if ( connect( $soc, $dest_params ) ) {
            $log->error("connect: $!");
            close $soc and print "close $soc\n";
            $soc = undef;
            last;
        }

        select($soc);
        $| = 1;
        select(STDOUT);

        my $ctx;
        if ( $args{'ssl'} ) {
            $ctx = Net::SSLeay::CTX_new()
              or $log->warning("Failed to create SSL_CTX $!");
            Net::SSLeay::CTX_set_options( $ctx, &Net::SSLeay::OP_ALL )
              and die_if_ssl_error("ssl ctx set options");
            $soc = Net::SSLeay::new($ctx) or die_now("Failed to create SSL $!");
            Net::SSLeay::set_fd( $soc, fileno($soc) );
            my $res = Net::SSLeay::connect($soc)
              and die_if_ssl_error("ssl connect");
            print "Cipher `" . Net::SSLeay::get_cipher($soc) . "'\n";
        }

        my $http = Http->new(
            'soc'    => $soc,
            'ssl'    => $args{'ssl'},
            'fd'     => $out,
            'text'   => $args{'text'},
            'vorbis' => $args{'vorbis'}
        );

        # 送信
        my %res = $http->write_msg(
            'sequence_no' => 0,
            'msg'         => $args{'msg'}
        );
        CORE::shutdown $soc, 1;

        # ヘッダ受信
        print $out ( $http->datetime("Started.") || '' ) . "\n";
        my %header = $http->read_header();

        #$args{'text'}->insert('1.0', $header{'buffer'}) if ($args{'text'});

        # ボディ受信
        my %body = $http->read_body( 'left' => $header{'left'} );

        #$args{'text'}->insert('1.0', $body{'buffer'}) if ($args{'text'});
        print $out "\n" . ( $http->datetime("Done.") || '' ) . "\n";

        if ( $args{'ssl'} ) {
            Net::SSLeay::free($soc);
            Net::SSLeay::CTX_free($ctx);
        }

        close $soc and print "close $soc\n";
        $soc = undef;
    }

    close $out if ( defined $out );
    $out = undef;
}

my $msg;
if ( $opt{'nogui'} ) {
    if ( @{ $opt{'file'} } ) {
        foreach my $file ( @{ $opt{'file'} } ) {
            open my $in, "<", $file
              or $log->error("open[$file]: $!");

            while ( defined( my $line = <$in> ) ) {
                $msg .= $line;
            }
            close $in if ( defined $in );
            $msg =~ s/\n/\r\n/g;
            http_client(
                'dest'   => $opt{'dest'},
                'port'   => $opt{'port'},
                'ssl'    => $opt{'ssl'},
                'count'  => $opt{'count'},
                'vorbis' => $opt{'vorbis'},
                'msg'    => $msg,
            );
        }
    }
    if ( $opt{'dir'} ) {
        my @files = Http::recursive_dir( $opt{'dir'} );
        foreach my $file (@files) {
            open my $in, "<", $file
              or $log->error("open[$file]: $!");

            while ( defined( my $line = <$in> ) ) {
                $msg .= $line;
            }
            close $in if ( defined $in );
            $msg =~ s/\n/\r\n/g;
            http_client(
                'dest'   => $opt{'dest'},
                'port'   => $opt{'port'},
                'ssl'    => $opt{'ssl'},
                'count'  => $opt{'count'},
                'vorbis' => $opt{'vorbis'},
                'msg'    => $msg,
            );
        }
    }
}
else {
    $msg .= $send_header . "\n\n" . $send_body;
    $win = Tk::HttpClient->new(
        'dest'      => $opt{'dest'},
        'port'      => $opt{'port'},
        'ssl'       => $opt{'ssl'},
        'count'     => $opt{'count'},
        'icon'      => $iconfile,
        'vorbis'    => $opt{'vorbis'},
        'msg'       => $msg,
        'clientcmd' => \&http_client,
    );

    $win->create_window(
        'version'  => $VERSION,
    );
}

exit( $stathash{'EX_OK'} );

__END__

=head1 NAME

client.pl - http client program.

=head1 SYNOPSIS

client.pl [options]

 Options:
   -i,  --dest       Set the ip address.
   -p,  --port       This parameter sets port number.
        --ssl        Send for ssl.
   -o,  --output     Output send data.
   -f,  --file       Send data from file.
   -d,  --directory  Send data from files in directory.
   -c,  --count      Repeat count.
   -v,  --vorbis     Display extra information.
        --nogui      Command line interface.
   -h,  --help       Display this help and exit.
   -V,  --version    Output version information and exit.
