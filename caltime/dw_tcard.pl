#!/usr/bin/perl -w

use strict;
use warnings;
use File::Basename;
use Getopt::Long;
use Socket;
use Net::SSLeay qw(die_now die_if_ssl_error);
use bytes();
#use Sys::Hostname;
use URI::Escape;
use Encode qw/encode decode/;

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
    'dir'     => './',
    'user'    => 'BC@CACjlLPFICX`LBC`MZFPFhMICY`NlMECnECNhLECBdL',
    'cid'     => 'ssn00265',
    'id'      => 'higashit',
    'pw'      => 'higashit',
    'month'   => '201308',
    'ssl'     => 0,
    'port'    => 80,
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
   -d,  --dir        Output directory
   -u,  --user       Set user
   -c,  --cid        Set cid
   -i,  --id         Set id
   -w,  --pw         Set pw
   -m,  --month      Set month
   -s,  --ssl        SSL
   -p,  --port       This parameter sets port number default $opt{port}
   -h,  --help       Display this help and exit
   -V,  --version    Output version information and exit
EOF
}

# オプション引数
Getopt::Long::Configure(qw{no_getopt_compat no_auto_abbrev no_ignore_case});
GetOptions(
    'dir|d:s'   => \$opt{'dir'},
    'user|u:s'  => \$opt{'user'},
    'cid|c:s'   => \$opt{'cid'},
    'id|i:s'    => \$opt{'id'},
    'pw|w:s'    => \$opt{'pw'},
    'month|m:s' => \$opt{'month'},
    'ssl|s'     => \$opt{'ssl'},
    'port|p:i'  => \$opt{'port'},
    'help|h|?'  => \$opt{'help'},
    'version|V' => \$opt{'version'}
) or usage() and exit( $stathash{'EX_NG'} );

usage() and exit( $stathash{'EX_OK'} ) if ( $opt{'help'} );
print_version() if ( $opt{'version'} );

my ( $header, $body );
my $dest = "h1.teki-pakinets.com";
# ヘッダ
$header =
"POST "
    . "/cgi-bin/asp/000265/xinfo.cgi"
    . " HTTP/1.1\r\nHost: " . $dest . "\r\n"
    . "User-Agent: Mozilla/5.0 (X11; Ubuntu; Linux i686; rv:23.0) Gecko/20100101 Firefox/23.0\r\n"
    . "Accept: test/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8\r\nAccept-Language: ja,en-us;q=0.7,en;q=0.3\r\nAccept-Encoding: gzip, deflate\r\nReferer: http://h1.teki-pakinets.com/cgi-bin/asp/000265/xinfo.cgi?page=tcardindex&prid=42&date="
    . $opt{'month'} . "\r\nCookie: "
    . "User="
    . uri_escape($opt{'user'}) . "; "
    . "dnptab=S; "
    . "dnptabg=22; "
    . "dnpbksf=1-42; "
    . "dnpschwph=; "
    . "dnpschwgh=; "
    . "dnpschm=; "
    . "dnpschd=; "
    . "dnptod=0; "
    . "dnpschwg=; "
    . "dnpschw=;"
    . "PlusDesknets="
    . "cid:" . $opt{'cid'} . ","
    . "id:" . $opt{'id'} . ","
    . "pw:" . $opt{'pw'}
    . "\r\nConnection: keep-alive\r\n"
    . "Connection-Type: application/x-www-form-urlencoded\r\n";

# ボディ
$body =
    "hsearch=&hmodule=&s_htagpopdown=&cmd=tcardcmdindex&lc=xinfo.cgi"
    . uri_escape("?prid=42&date="
                . $opt{'month'}
                . "&bpage=&fldsort=&order=&gid=&lcs=xinfo.cgi?page=tcardindex&prid=42&date="
                . $opt{'month'}
                . "&bpage=&fldsort=&order=&gid=")
    . "&date="
    . $opt{'month'}
    . "&prid=42&s_dloadb="
    . uri_escape(encode('euc-jp', decode('utf8', "ダウンロード")))
    . "&s_helpdisp=&s_subwinhide=";

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
my $ipaddr = gethostbyname( $dest );
my $dest_params = sockaddr_in( $opt{'port'}, $ipaddr );

socket( my $socket, PF_INET, SOCK_STREAM, getprotobyname("tcp") )
  or die("socket: $!\n");
connect( $socket, $dest_params ) or die "connect: $!";
select($socket);
$| = 1;
select(STDOUT);

my ($ctx, $ssl, $res);
if ($opt{'ssl'}) {
    $ctx = Net::SSLeay::CTX_new() or die_now("Failed to create SSL_CTX $!");
    Net::SSLeay::CTX_set_options( $ctx, &Net::SSLeay::OP_ALL )
        and die_if_ssl_error("ssl ctx set options");
    $ssl = Net::SSLeay::new($ctx) or die_now("Failed to create SSL $!");
    Net::SSLeay::set_fd( $ssl, fileno($socket) );
    Net::SSLeay::connect($ssl) and die_if_ssl_error("ssl connect");
    print "Cipher `" . Net::SSLeay::get_cipher($ssl) . "\n";
}

# 送信
if ($opt{'ssl'}) {
    Net::SSLeay::write( $ssl, $msg );
    die_if_ssl_error("ssl write");
    CORE::shutdown $socket, 1;
}
else {
    send( $socket, $msg, 0 );
}

printf "\n%s bytes write.\n", bytes::length($msg);
print $msg;

my $read_buffer;
while (1) {
    my $buf;
    if ($opt{'ssl'}) {
        $buf= Net::SSLeay::read( $ssl, 16384 ) || "";
        die_if_ssl_error("ssl read");
    }
    else {
        recv( $socket, $buf, 16384, MSG_WAITALL );
    }
    die "read: $!\n"
      unless (defined $read_buffer || $read_buffer eq "")
          or $!{EAGAIN}
          or $!{EINTR}
          or $!{ENOBUFS};
    my $len = bytes::length($buf);
    last if ( !$len || $buf eq "");
    printf "\n%s bytes read.\n", $len;
    print $buf;
    $read_buffer .= $buf;
}
my @msg = split m/\r\n\r\n/, $read_buffer, 2;    # ヘッダ分割
my @body = split m/\r\n/, $msg[1], 2 if (defined $msg[1]);

printf "%d bytes read.\n", hex($body[0]) if (defined $body[0]);

if (defined $body[1]) {
    my $filename = $opt{'dir'} . "/" . $opt{'month'} . ".csv";
    open my $out, ">", $filename
        or die "open[$filename]: $!";
    $body[1] =~ s/\r\n0\r\n//g;
    print $out $body[1];
    close $out and print "close $out\n";
}
else {
    die "no body\n";
}

if ($opt{'ssl'}) {
    Net::SSLeay::free($ssl);
    Net::SSLeay::CTX_free($ctx);
}

close $socket and print "close $socket\n";


exit( $stathash{'EX_OK'} );

__END__

