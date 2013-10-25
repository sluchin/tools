#!/usr/bin/perl -w

use strict;
use warnings;
use File::Basename;
use Getopt::Long;
use Socket;
use Net::SSLeay qw(die_now die_if_ssl_error);
use bytes();
use Sys::Hostname;

our $VERSION = do { my @r = ( q$Revision: 0.01 $ =~ /\d+/g );
    sprintf "%d." . "%02d" x $#r, @r if (@r);
};

my $progname = basename($0);

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
    'debug'   => 1,
    'verbose' => 0,
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
   -i,  --dest       Set the ipaddress server default $opt{dest}.
   -p,  --port       This parameter sets port number default $opt{port}.
        --ssl        Send for ssl.
   -h,  --help       Display this help and exit.
   -V,  --version    Output version information and exit.
EOF
}

# オプション引数
Getopt::Long::Configure(qw{no_getopt_compat no_auto_abbrev no_ignore_case});
GetOptions(
    'dest|i=s'  => \$opt{'dest'},
    'port|p=i'  => \$opt{'port'},
    'ssl'       => \$opt{'ssl'},
    'help|h|?'  => \$opt{'help'},
    'version|V' => \$opt{'version'}
) or usage() and exit( $stathash{'EX_NG'} );

usage() and exit( $stathash{'EX_OK'} ) if ( $opt{'help'} );
print_version() if ( $opt{'version'} );

my ( $header, $body );

# ヘッダ
$header =
"POST /Hems/Storage/Mete HTTP/1.1\r\nConnection: close\r\nPragma: no-cache\r\nHost: "
    . (hostname() || "")
    . "\r\nSequenceNo: 0\r\nHID: 11821000007\r\nContent-type: text/html; charset=utf-8\r\n";

# ボディ
$body =
"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<cyclicDataRequest><softwareVersion>V2.01A</softwareVersion><configVersion>31</configVersion><status><SDInsert>0</SDInsert><SDMount>0</SDMount><WANLink>1</WANLink><LANLink>0</LANLink></status><measuredDataList><measuredData date=\"2013/08/03 00:00:00\"><AI id=\"1\">2147483647</AI><AI id=\"2\">2147483647</AI><AI id=\"3\">2147483647</AI><AI id=\"4\">2147483647</AI><AI id=\"5\">2147483647</AI><AI id=\"6\">2147483647</AI><PI id=\"1\">2147483647</PI><PI id=\"2\">2147483647</PI></measuredData><measuredData date=\"2013/08/03 00:01:00\"><AI id=\"1\">2147483647</AI><AI id=\"2\">2147483647</AI><AI id=\"3\">2147483647</AI><AI id=\"4\">2147483647</AI><AI id=\"5\">2147483647</AI><AI id=\"6\">2147483647</AI><PI id=\"1\">2147483647</PI><PI id=\"2\">2147483647</PI></measuredData><measuredData date=\"2013/08/03 00:02:00\">";

my $content_length = bytes::length($body);

my $msg = $header;
$msg .= "Content-Length: " . $content_length . "\r\n\r\n";
$msg .= $body;

if ($opt{'ssl'}) {
    Net::SSLeay::load_error_strings();
    Net::SSLeay::SSLeay_add_ssl_algorithms();
    Net::SSLeay::randomize();
}

$opt{'port'} = getservbyname( $opt{'port'}, 'tcp' )
  unless $opt{'port'} =~ /^\d+$/;
my $ipaddr = gethostbyname( $opt{'dest'} );
my $dest_params = sockaddr_in( $opt{'port'}, $ipaddr );

socket( my $socket, PF_INET, SOCK_STREAM, getprotobyname("tcp") )
  or die("socket: $!\n");
connect( $socket, $dest_params ) or die "connect: $!";
select($socket);
$| = 1;
select(STDOUT);

my ($ssl, $ctx);
if ($opt{'ssl'}) {
    my $ctx = Net::SSLeay::CTX_new() or die_now("Failed to create SSL_CTX $!");
    Net::SSLeay::CTX_set_options( $ctx, &Net::SSLeay::OP_ALL )
            and die_if_ssl_error("ssl ctx set options");
    $ssl = Net::SSLeay::new($ctx) or die_now("Failed to create SSL $!");
    Net::SSLeay::set_fd( $ssl, fileno($socket) );
    my $res = Net::SSLeay::connect($ssl) and die_if_ssl_error("ssl connect");
    print "Cipher `" . Net::SSLeay::get_cipher($ssl) . "'\n";
    # 送信
    $res = Net::SSLeay::write( $ssl, $msg );
    die_if_ssl_error("ssl write");
    CORE::shutdown $socket, 1;
}
else {
    print $socket $msg;
    shutdown $socket, 1;
}

printf "\n%s bytes write.\n", bytes::length($msg);
print $msg;

my $read_buffer;
my $len;
while (1) {
    $len = 0;
    if ($opt{'ssl'}) {
        $read_buffer = Net::SSLeay::read( $ssl, 16384 ) || "";
        die_if_ssl_error("ssl read");
        die "read: $!\n"
          unless defined $read_buffer
              or $!{EAGAIN}
              or $!{EINTR}
              or $!{ENOBUFS};
        $len = bytes::length($read_buffer);
    }
    else {
        $len = read($socket, $read_buffer, 16384);
        last if ($len == 0);
    }
    printf "\n%s bytes read.\n", $len;
    last if ( !$len || $read_buffer eq "");
    print $read_buffer;
}

if ($opt{'ssl'}) {
    Net::SSLeay::free($ssl);
    Net::SSLeay::CTX_free($ctx);
}

close $socket and print "close $socket\n";

exit( $stathash{'EX_OK'} );

__END__

