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
use Encode qw/encode decode decode_utf8/;
use Sys::Hostname;
use Socket;
use bytes ();

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
use Tk::HttpServer;

my $iconfile = catfile( $progdir, "icon", "icon.xpm" );

# ステータス
my %stathash = (
    'EX_OK' => 0,    # 正常終了
    'EX_NG' => 1,    # 異常終了
);

# デフォルトオプション
my %opt = (
    'port'   => "8888",
    'status' => "200",
    'file'   => "server.log",
    'ssl'    => 0,
    'body' =>
      "{\"result\":\"OK\",\"cid\":\"test_cid\",\"start_code\":\"012345678\"}",
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
    'port|p=s'   => \$opt{'port'},
    'status|s=s' => \$opt{'status'},
    'file|f=s'   => \$opt{'file'},
    'ssl'        => \$opt{'ssl'},
    'body|b=s'   => \$opt{'body'},
    'nogui'      => \$opt{'nogui'},
    'vorbis|v'   => \$opt{'vorbis'},
    'help|h|?'   => \$opt{'help'},
    'version|V'  => \$opt{'version'}
  )
  or usage()
  and exit( $stathash{'EX_NG'} );

usage() and exit( $stathash{'EX_OK'} ) if ( $opt{'help'} );
print_version() if ( $opt{'version'} );

# HTTPステータス
# 200 正常
my %http_status = (
    '200' => "OK",
    '403' => "Forbidden",
    '404' => "Not Found",
);

# ヘッダ
my $send_header =
    "HTTP/1.1 "
  . $opt{'status'} . " "
  . ( $http_status{ $opt{'status'} } || "" )
  . "\nConnection: close";

# ボディ
my $send_body = $opt{'body'};

open my $out, ">>", "$opt{'file'}"
  or die "open[$opt{'file'}]: $!";

my $win = undef;
my $soc = undef;
my $acc = undef;

# シグナル
sub sig_handler {
    print "catch INT\n";
    close $soc if ( defined $soc );
    close $acc if ( defined $acc );
    close $out if ( defined $out );
    $soc = $acc = $out = undef;
}

$SIG{'INT'} = \&sig_handler;

my $ourip             = "\0\0\0\0";
my $sockaddr_template = 'S n a4 x8';
my $ctx;
my $addr;

sub sock_bind {
    my %args = (
        'port'   => 80,
        'ssl'    => 0,
        'vorbis' => 0,
        @_
    );

    if ( $opt{'ssl'} ) {
        eval { use Net::SSLeay qw(die_now die_if_ssl_error); };
        if ( !$@ ) {
            print "Cannot use Net::SSLeay\nTry `cpan Net::SSLeay'\n";
            exit( $stathash{'EX_NG'} );
        }
        Net::SSLeay::load_error_strings();
        Net::SSLeay::SSLeay_add_ssl_algorithms();
        Net::SSLeay::randomize();
    }

    my $our_params =
      pack( $sockaddr_template, &PF_INET, $args{'port'}, $ourip );
    socket( $soc, PF_INET, SOCK_STREAM, getprotobyname("tcp") )
      or print "socket: $!\n" and return $stathash{'EX_NG'};
    setsockopt( $soc, SOL_SOCKET, SO_REUSEADDR, 1 )
      or print "setsockopt: $!\n" and return $stathash{'EX_NG'};
    bind( $soc, $our_params )
      or print "bind:   $!\n" and return $stathash{'EX_NG'};
    listen( $soc, SOMAXCONN )
      or print "listen: $!\n" and return $stathash{'EX_NG'};

    if ( $args{'ssl'} ) {
        unless ( -f "server.key" || -f "server.crt" ) {
            print "no server.key";
            return $stathash{'EX_NG'};
        }
        $ctx = Net::SSLeay::CTX_new() or die_now("CTX_new ($ctx): $!");
        Net::SSLeay::CTX_set_options( $ctx, &Net::SSLeay::OP_ALL )
          and die_if_ssl_error("ssl ctx set options");

        Net::SSLeay::CTX_use_RSAPrivateKey_file( $ctx, "server.key",
            &Net::SSLeay::FILETYPE_PEM );
        die_if_ssl_error("private key");
        Net::SSLeay::CTX_use_certificate_file( $ctx, "server.crt",
            &Net::SSLeay::FILETYPE_PEM );
        die_if_ssl_error("certificate");
    }
    return ( $stathash{'EX_OK'} );
}

sub http_server {
    my %args = (
        'port'   => 80,
        'ssl'    => 0,
        'vorbis' => 0,
        'data'   => '',
        'loop'   => 1,
        @_
    );

    while ( $args{'loop'} ) {
        print "Accepting connections...\n";
        $addr = accept( $acc, $soc ) or print "accept: $!" and next;
        select($acc);
        $| = 1;
        select(STDOUT);

        last if ( $!{EINTR} );

        my ( $af, $client_port, $client_ip ) =
          unpack( $sockaddr_template, $addr );
        my @inetaddr = unpack( 'C4', $client_ip );
        print "$af connection from "
          . join( '.', @inetaddr )
          . ":$client_port\n";

        print "ssl: " . ( $args{'ssl'} || 0 ) . "\n" if ( $args{'vorbis'} );
        if ( $args{'ssl'} ) {
            $acc = Net::SSLeay::new($ctx) or die_now("SSL_new ($acc): $!");
            Net::SSLeay::set_fd( $acc, fileno($acc) );
            my $err = Net::SSLeay::accept($acc)
              and die_if_ssl_error('ssl accept');
            print "Cipher `" . Net::SSLeay::get_cipher($acc) . "'\n";
        }

        # ヘッダ受信
        my $http = Http->new(
            'soc'    => $acc,
            'ssl'    => $args{'ssl'},
            'fd'     => $out,
            'vorbis' => $args{'vorbis'}
        );
        print $out $http->datetime("Started.") . "\n";
        my %header = $http->read_header();

        if (%header) {
            print "buffer: " . ( $header{'buffer'} || '' ) . "\n"
              if ( $args{'vorbis'} );
            print "left: " . ( $header{'left'} || '' ) . "\n"
              if ( $args{'vorbis'} );

            # ボディ受信
            my %body = $http->read_body( 'left' => $header{'left'} );
            print "" . ( $body{'buffer'} || '' ) . "\n" if ( $body{'len'} );
            print $out "\n" . $http->datetime("Done.") . "\n";

            # 送信
            my %res = $http->write_msg(
                'sequence_no' => $header{'sequence_no'},
                'msg'         => $args{'data'}
            );
            print "" . ( $res{'buffer'} || '' ) . "\n" if ( $args{'vorbis'} );
        }
        else {
            print "no header\n";
            $args{'loop'} = 0;
        }
        Net::SSLeay::free($acc) if ( $args{'ssl'} );
        close $acc and print "close $acc\n";
        $acc = undef;
    }

    close $soc if ( defined $soc );
    $soc = undef;
}

sub write_eof {
    my %args = (
        'ip'     => 'localhost',
        'port'   => 80,
        'ssl'    => 0,
        'vorbis' => 0,
        @_
    );

    my $soc = undef;

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
    my $ipaddr = gethostbyname( $args{'ip'} );
    my $dest_params = sockaddr_in( $args{'port'}, $ipaddr );

    socket( $soc, PF_INET, SOCK_STREAM, getprotobyname("tcp") )
      or print "socket: $!\n" and return;
    connect( $soc, $dest_params ) or print "connect: $!\n" and return;
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

    # 送信
    my $http = Http->new(
        'soc'  => $soc,
        'port' => $args{'port'},
        'ssl'  => $args{'ssl'},
    );
    my %res = $http->write_eof();

    #CORE::shutdown $soc, 1;
    print $res{'buffer'} . "\n" if ( $args{'vorbis'} );

    if ( $args{'ssl'} ) {
        Net::SSLeay::free($soc);
        Net::SSLeay::CTX_free($ctx);
    }
    close $soc and print "close $soc\n";
    $soc = undef;
}

my $data .= $send_header . "\n\n" . $send_body;

sub window {
    my $http = Http->new(
        'soc'  => $soc,
        'port' => $opt{'port'},
        'ssl'  => $opt{'ssl'},
    );
    my $localip = $http->get_localip();

    $win = Tk::HttpServer->new(
        'ip'        => $localip,
        'port'      => $opt{'port'},
        'ssl'       => $opt{'ssl'},
        'vorbis'    => $opt{'vorbis'},
        'data'      => $data,
        'sockcmd'   => \&sock_bind,
        'servercmd' => \&http_server,
        'stopcmd'   => \&write_eof
    );

    $win->create_window(
        'iconfile' => $iconfile,
        'version'  => $VERSION,
    );
}

if ( $opt{'nogui'} ) {
    sock_bind(
        'port'   => $opt{'port'},
        'ssl'    => $opt{'ssl'},
        'vorbis' => $opt{'vorbis'}
    );
    $data =~ s/\n/\r\n/g;
    http_server(
        'port'   => $opt{'port'},
        'ssl'    => $opt{'ssl'},
        'vorbis' => $opt{'vorbis'},
        'data'   => $data
    );
}
else {
    window();
}

close $out if ( defined $out );
$out = undef;

exit( $stathash{'EX_OK'} );

__END__

=head1 NAME

server.pl - http server program.

=head1 SYNOPSIS

server.pl [options]

 Options:
   -p,  --port           This parameter sets port number.
   -s,  --status=status  Setting http status(200,403,404).
   -f,  --file           Output filename.
        --ssl            Send for ssl.
   -b,  --body           Send body.
        --nogui          Command line interface.
   -v,  --vorbis         Display extra information.
   -h,  --help           Display this help and exit.
   -V,  --version        Output version information and exit.

=over 4

=back

=head1 DESCRIPTION

B<This program> is http server.

install module

cpan Net::SSLeay

create ssl key

秘密鍵の作成
openssl genrsa 2048 > server.key

証明書署名要求の作成
openssl req -new -key server.key > server.csr

サーバ証明書の作成
openssl x509 -days 3650 -req -signkey server.key < server.csr > server.crt

=cut
