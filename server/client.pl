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

# ステータス
my %stathash = (
    'EX_OK' => 0,    # 正常終了
    'EX_NG' => 1,    # 異常終了
);

# デフォルトオプション
my %opt = (
    'dest'    => 'localhost',
    'port'    => 8888,
    'ssl'     => 0,
    'file'    => "client.log",
    'repeat'  => 1,
    'verbose' => 0,
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
    'dest|i=s'  => \$opt{'dest'},
    'port|p=i'  => \$opt{'port'},
    'ssl'       => \$opt{'ssl'},
    'file|f=s'  => \$opt{'file'},
    'count|c=i' => \$opt{'count'},
    'vorbis|v'  => \$opt{'vorbis'},
    'help|h|?'  => \$opt{'help'},
    'version|V' => \$opt{'version'}
  )
  or usage()
  and exit( $stathash{'EX_NG'} );

usage() and exit( $stathash{'EX_OK'} ) if ( $opt{'help'} );
print_version() if ( $opt{'version'} );

# ヘッダ
my $send_header =
"POST /Hems/Storage/Mete HTTP/1.1\r\nConnection: close\r\nPragma: no-cache\r\nHost: "
  . ( hostname() || "" )
  . "\r\nSequenceNo: 0\r\nHID: 11821000007\r\nContent-type: text/html; charset=utf-8\r\n";

# ボディ
my $send_body =
"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<cyclicDataRequest><softwareVersion>V2.01A</softwareVersion><configVersion>31</configVersion><status><SDInsert>0</SDInsert><SDMount>0</SDMount><WANLink>1</WANLink><LANLink>0</LANLink></status><measuredDataList><measuredData date=\"2013/08/03 00:00:00\"><AI id=\"1\">2147483647</AI><AI id=\"2\">2147483647</AI><AI id=\"3\">2147483647</AI><AI id=\"4\">2147483647</AI><AI id=\"5\">2147483647</AI><AI id=\"6\">2147483647</AI><PI id=\"1\">2147483647</PI><PI id=\"2\">2147483647</PI></measuredData><measuredData date=\"2013/08/03 00:01:00\"><AI id=\"1\">2147483647</AI><AI id=\"2\">2147483647</AI><AI id=\"3\">2147483647</AI><AI id=\"4\">2147483647</AI><AI id=\"5\">2147483647</AI><AI id=\"6\">2147483647</AI><PI id=\"1\">2147483647</PI><PI id=\"2\">2147483647</PI></measuredData><measuredData date=\"2013/08/03 00:02:00\">";

open my $out, ">>", "$opt{'file'}"
    or die "open[$opt{'file'}]: $!";

my $socket = undef;

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

$opt{'port'} = getservbyname( $opt{'port'}, 'tcp' )
  unless $opt{'port'} =~ /^\d+$/;
my $ipaddr = gethostbyname( $opt{'dest'} );
my $dest_params = sockaddr_in( $opt{'port'}, $ipaddr );

socket( $socket, PF_INET, SOCK_STREAM, getprotobyname("tcp") )
  or die("socket: $!\n");
connect( $socket, $dest_params ) or die "connect: $!";
select($socket);
$| = 1;
select(STDOUT);

my ( $ssl, $ctx );
if ( $opt{'ssl'} ) {
    my $ctx = Net::SSLeay::CTX_new() or die_now("Failed to create SSL_CTX $!");
    Net::SSLeay::CTX_set_options( $ctx, &Net::SSLeay::OP_ALL )
      and die_if_ssl_error("ssl ctx set options");
    $ssl = Net::SSLeay::new($ctx) or die_now("Failed to create SSL $!");
    Net::SSLeay::set_fd( $ssl, fileno($socket) );
    my $res = Net::SSLeay::connect($ssl) and die_if_ssl_error("ssl connect");
    print "Cipher `" . Net::SSLeay::get_cipher($ssl) . "'\n";
}

my $http = Http->new( 'soc' => $socket, 'ssl' => $ssl, 'fd' => $out );

# 送信
my $msg .= $send_header . "\r\n\r\n" . $send_body;
my %res = $http->write_msg(
    'soc'         => $socket,
    'ssl'         => $ssl,
    'sequence_no' => 0,
    'msg'         => $msg
);
print $res{'buffer'} . "\n";

# ヘッダ受信
my ( $left, $read_buffer );

print $out $http->datetime("Started.") . "\n";
my %header = $http->read_header();

print $header{'left'} || '' . "\n";
print $header{'buffer'} || '' . "\n";

# ボディ受信
my %body = $http->read_body( 'left' => $header{'left'} );
print $body{'buffer'} || '' . "\n";
print $out "\n" . $http->datetime("Done.") . "\n";

if ( $opt{'ssl'} ) {
    Net::SSLeay::free($ssl);
    Net::SSLeay::CTX_free($ctx);
}

close $socket and print "close $socket\n";

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
   -c,  --count      Repeat count.
   -v,  --vorbis     Display extra information.
   -h,  --help       Display this help and exit.
   -V,  --version    Output version information and exit.
