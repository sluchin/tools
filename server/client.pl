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

#use Encode qw/encode decode decode_utf8/;
use Socket;
use bytes ();
use Sys::Hostname;

our $VERSION = do { my @r = ( q$Revision: 0.01 $ =~ /\d+/g );
    sprintf "%d." . "%02d" x $#r, @r if (@r);
};

my $progname = basename($0);
my $progdir;

BEGIN {
    $progdir = dirname( readlink($0) || $0 );
    push( @INC, $progdir . '/lib' );
}

use Http;
use Tk::HttpClient;

my $iconfile = catfile( $progdir, "icon", "icon.xpm" );

# ステータス
my %stathash = (
    'EX_OK' => 0,    # 正常終了
    'EX_NG' => 1,    # 異常終了
);

# デフォルトオプション
my %opt = (
    'dest'     => 'localhost',
    'port'     => 8888,
    'ssl'      => 0,
    'file'     => "client.log",
    'filelist' => '',
    'count'    => 1,
    'nogui'    => 0,
    'vorbis'   => 0,
    'help'     => 0,
    'version'  => 0
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
    'dest|i=s'     => \$opt{'dest'},
    'port|p=i'     => \$opt{'port'},
    'ssl'          => \$opt{'ssl'},
    'file|f=s'     => \$opt{'file'},
    'filelist|l=s' => \$opt{'filelist'},
    'count|c=i'    => \$opt{'count'},
    'nogui'        => \$opt{'nogui'},
    'vorbis|v'     => \$opt{'vorbis'},
    'help|h|?'     => \$opt{'help'},
    'version|V'    => \$opt{'version'}
  )
  or usage()
  and exit( $stathash{'EX_NG'} );

usage() and exit( $stathash{'EX_OK'} ) if ( $opt{'help'} );
print_version() if ( $opt{'version'} );

# ヘッダ
my $send_header =
"POST /Hems/Storage/Mete HTTP/1.1\nConnection: close\nPragma: no-cache\nHost: "
  . ( hostname() || "" )
  . "\nSequenceNo: 0\nContent-type: text/html; charset=utf-8";

# ボディ
my $send_body = "test";

my $win = undef;
my $soc = undef;
my $out = undef;

# シグナル
sub sig_handler {
    close $soc if ( defined $soc );
    close $out if ( defined $out );
    $soc = $out = undef;
}

$SIG{'INT'} = \&sig_handler;

sub http_client {
    my %args = (
        'dest'   => '',
        'port'   => 80,
        'ssl'    => 0,
        'count'  => 1,
        'vorbis' => 0,
        'msg'    => '',
        @_
    );

    open $out, ">>", "$opt{'file'}"
      or die "open[$opt{'file'}]: $!";

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

        print "port: " . ( $args{'port'} || '' ) . "\n";
        $args{'port'} = getservbyname( $args{'port'}, 'tcp' )
          unless $args{'port'} =~ /^\d+$/;
        print "port: " . ( $args{'port'} || '' ) . "\n";

        print "dest: " . ( $args{'dest'} || '' ) . "\n";
        my $ipaddr = gethostbyname( $args{'dest'} );
        print "ipaddr: " . ( $ipaddr || '' ) . "\n";

        my $dest_params = sockaddr_in( $args{'port'}, $ipaddr )
          or die "Cannot pack: $!";
        print "dest_params: " . ( $dest_params || '' ) . "\n";

        socket( $soc, PF_INET, SOCK_STREAM, getprotobyname("tcp") )
          or die("socket: $!\n");
        connect( $soc, $dest_params ) or die "connect: $!";
        select($soc);
        $| = 1;
        select(STDOUT);

        my $ctx;
        if ( $args{'ssl'} ) {
            $ctx = Net::SSLeay::CTX_new()
              or die_now("Failed to create SSL_CTX $!");
            Net::SSLeay::CTX_set_options( $ctx, &Net::SSLeay::OP_ALL )
              and die_if_ssl_error("ssl ctx set options");
            $soc = Net::SSLeay::new($ctx) or die_now("Failed to create SSL $!");
            Net::SSLeay::set_fd( $soc, fileno($soc) );
            my $res = Net::SSLeay::connect($soc)
              and die_if_ssl_error("ssl connect");
            print "Cipher `" . Net::SSLeay::get_cipher($soc) . "'\n";
        }

        print "test2\n";
        my $http = Http->new(
            'soc'    => $soc,
            'ssl'    => $args{'ssl'},
            'fd'     => $out,
            'vorbis' => $args{'vorbis'}
        );

        # 送信
        my %res = $http->write_msg(
            'sequence_no' => 0,
            'msg'         => $args{'msg'}
        );
        CORE::shutdown $soc, 1;
        print $res{'buffer'} . "\n";

        # ヘッダ受信
        print $out ( $http->datetime("Started.") || '' ) . "\n";
        my %header = $http->read_header();

        print $header{'left'}   || '' . "\n";
        print $header{'buffer'} || '' . "\n";

        # ボディ受信
        my %body = $http->read_body( 'left' => $header{'left'} );
        print $body{'buffer'} || '' . "\n";
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

my $msg .= $send_header . "\n\n" . $send_body;

sub window {
    $win = Tk::HttpClient->new(
        'dest'      => $opt{'dest'},
        'port'      => $opt{'port'},
        'ssl'       => $opt{'ssl'},
        'count'     => $opt{'count'},
        'vorbis'    => $opt{'vorbis'},
        'msg'       => $msg,
        'clientcmd' => \&http_client,
    );

    $win->create_window(
        'iconfile' => $iconfile,
        'version'  => $VERSION,
    );
}

if ( $opt{'nogui'} ) {
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
else {
    window();
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
   -f,  --file       Output filename.
   -l,  --filelist   Send filelist of data.
   -c,  --count      Repeat count.
   -v,  --vorbis     Display extra information.
        --nogui      Command line interface.
   -h,  --help       Display this help and exit.
   -V,  --version    Output version information and exit.
