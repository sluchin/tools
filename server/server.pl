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
use File::Basename;
use Getopt::Long;
use Socket;
use bytes();

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

# ステータス
my %stathash = (
    'EX_OK' => 0,    # 正常終了
    'EX_NG' => 1,    # 異常終了
);

# デフォルトオプション
my %opt = (
    'port'    => 8888,
    'status'  => "200",
    'file'    => "server.log",
    'ssl'     => 0,
    'body'    => "test",
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
    'status|s=s' => \$opt{'status'},
    'file|f=s'   => \$opt{'file'},
    'ssl'        => \$opt{'ssl'},
    'body|b=s'   => \$opt{'body'},
    'port|p=i'   => \$opt{'port'},
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
  . "\r\nConnection: close\r\n";

# ボディ
my $send_body = $opt{'body'};

open my $out, ">>", "$opt{'file'}"
  or die "open[$opt{'file'}]: $!";

my $acc = undef;

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

my $ourip             = "\0\0\0\0";
my $sockaddr_template = 'S n a4 x8';
my $our_params = pack( $sockaddr_template, &PF_INET, $opt{'port'}, $ourip );
my $ctx;
my $ssl;
my $addr;

socket( my $socket, PF_INET, SOCK_STREAM, getprotobyname("tcp") )
  or die("socket: $!\n");
setsockopt( $socket, SOL_SOCKET, SO_REUSEADDR, 1 )
  or die("setsockopt SOL_SOCKET, SO_REUSEADDR: $!\n");
bind( $socket, $our_params ) or die "bind:   $!";
listen( $socket, SOMAXCONN ) or die "listen: $!";

if ( $opt{'ssl'} ) {
    die("no server.key") unless ( -f "server.key" );
    die("no server.crt") unless ( -f "server.crt" );
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

# シグナル
$SIG{'INT'} = sub {
    close $acc if ( defined $acc );
    close $out if ( defined $out );
};

while (1) {
    print "Accepting connections...\n";
    ( $addr = accept( $acc, $socket ) ) or die "accept: $!";
    select($acc);
    $| = 1;
    select(STDOUT);

    my ( $af, $client_port, $client_ip ) = unpack( $sockaddr_template, $addr );
    my @inetaddr = unpack( 'C4', $client_ip );
    print "$af connection from " . join( '.', @inetaddr ) . ":$client_port\n";

    if ( $opt{'ssl'} ) {
        $ssl = Net::SSLeay::new($ctx) or die_now("SSL_new ($ssl): $!");
        Net::SSLeay::set_fd( $ssl, fileno($acc) );
        my $err = Net::SSLeay::accept($ssl) and die_if_ssl_error('ssl accept');
        print "Cipher `" . Net::SSLeay::get_cipher($ssl) . "'\n";
    }

    # ヘッダ受信
    my ( $left, $read_buffer );

    my $http = Http->new( 'soc' => $acc, 'ssl' => $ssl, 'fd' => $out );
    print $out $http->datetime("Started.") . "\n";
    my %header = $http->read_header();
    next unless (%header);
    print $header{'buffer'} || '' . "\n";

    # ボディ受信
    my %body = $http->read_body( 'left' => $header{'left'} );
    print $body{'buffer'} || '' . "\n";
    print $out "\n" . $http->datetime("Done.") . "\n";

    # 送信
    my $msg .= $send_header . "\r\n\r\n" . $send_body;
    my %res = $http->write_msg(
        'soc'         => $acc,
        'ssl'         => $ssl,
        'sequence_no' => $header{'sequence_no'},
        'msg'         => $msg
    );
    print $res{'buffer'} . "\n";

    Net::SSLeay::free($ssl) if ( $opt{'ssl'} );
    close $acc and print "close $acc\n";
    $acc = undef;
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
   -p,  --port              This parameter sets port number.
   -s,  --status=status     Setting http status(200,403,404).
   -f,  --file              Output filename.
        --ssl               Send for ssl.
   -b,  --body              Send body.
   -v,  --vorbis            Display extra information.
   -h,  --help              Display this help and exit.
   -V,  --version           Output version information and exit.

=over 4

=back

=head1 DESCRIPTION

B<This program> is http server.

install module

cpan Net::SSLeay

create ssl key

openssl genrsa 2048 > server.key
openssl req -new -key server.key > server.csr
openssl x509 -days 3650 -req -signkey server.key < server.csr > server.crt

=cut
