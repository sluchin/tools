#!/usr/bin/perl -w
#
# モジュールのインストール
# cpan Net::SSLeay
#
# SSL証明書の作成
# openssl genrsa 2048 > server.key
# openssl req -new -key server.key > server.csr
# openssl x509 -days 3650 -req -signkey server.key < server.csr > server.crt
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

# ステータス
my %stathash = (
    'EX_OK' => 0,    # 正常終了
    'EX_NG' => 1,    # 異常終了
);

# デフォルトオプション
my %opt = (
    'status'  => "200",
    'file'    => "server.log",
    'ssl'     => 0,
    'body'    => "{\"result\":\"OK\",\"cid\":\"test_cid\",\"start_code\":\"012345678\"}",
    'port'    => 8888,
    'debug'   => 0,
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
    print << "EOF";
Usage: $progname [options]
   -s,  --status=status     Setting http status(200,600,601,602).
   -f,  --file              Output filename.
        --ssl               Send for ssl.
   -b,  --body              Send body.
   -p,  --port              This parameter sets port number default $opt{port}.
   -D,  --debug             Debug.
   -h,  --help              Display this help and exit.
   -V,  --version           Output version information and exit.
EOF
}

# オプション引数
Getopt::Long::Configure(qw{no_getopt_compat no_auto_abbrev no_ignore_case});
GetOptions(
    'status|s=s' => \$opt{'status'},
    'file|f=s'   => \$opt{'file'},
    'ssl'        => \$opt{'ssl'},
    'body|b=s'   => \$opt{'body'},
    'port|p=i'   => \$opt{'port'},
    'debug|D:i'  => \$opt{'debug'},
    'help|h|?'   => \$opt{'help'},
    'version|V'  => \$opt{'version'}
) or usage() and exit( $stathash{'EX_NG'} );

usage() and exit( $stathash{'EX_OK'} ) if ( $opt{'help'} );
print_version() if ( $opt{'version'} );

# HTTPステータス
# 200 正常
# 600 上位サーバで何らかのエラーが発生
# 601 上位サーバで認識していないHEMS端末
# 602 要求内容に不正がある
my %http_status = (
    '200' => "OK",
    '403' => "Forbidden",
    '404' => "Not Found",
    '600' => "Internal Server Error",
    '601' => "Hems Not Found",
    '602' => "Format Error",
);

my ( $header, $body );

# ヘッダ
$header =
    "HTTP/1.1 "
  . $opt{'status'} . " "
  . ( $http_status{ $opt{'status'} } || "" )
  . "\r\nConnection: close\r\n";

# ボディ
$body = $opt{'body'};

# バージョン取得
$body = "version=V2.01A"
  if ( $opt{'ver'} );

unless ( eval 'use Net::SSLeay qw(die_now die_if_ssl_error); 1' || $opt{'ssl'}) {
    print "no Net::SSLeay\n";
    exit( $stathash{'EX_NG'} );
}

if ($opt{'ssl'}) {
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

sub datetime {
    my $string = shift;
    my $out = shift;
    my ( $sec, $min, $hour, $mday, $mon, $year ) = localtime(time);
    my $datetime = sprintf(
        "[%04d-%02d-%02d %02d:%02d:%02d]",
        $year + 1900,
        $mon + 1, $mday, $hour, $min, $sec
    );

    print $datetime, " ", $string, "\n";
    print $out $datetime, " ", $string, "\n" if (defined $out);
}

socket( my $socket, PF_INET, SOCK_STREAM, getprotobyname("tcp") )
  or die("socket: $!\n");
setsockopt( $socket, SOL_SOCKET, SO_REUSEADDR, 1 )
  or die("setsockopt SOL_SOCKET, SO_REUSEADDR: $!\n");
bind( $socket, $our_params ) or die "bind:   $!";
listen( $socket, SOMAXCONN ) or die "listen: $!";

if ($opt{'ssl'}) {
    $ctx = Net::SSLeay::CTX_new() or die_now("CTX_new ($ctx): $!");
    Net::SSLeay::CTX_set_options( $ctx, &Net::SSLeay::OP_ALL )
            and die_if_ssl_error("ssl ctx set options");

    Net::SSLeay::CTX_use_RSAPrivateKey_file( $ctx, 'server.key',
                                             &Net::SSLeay::FILETYPE_PEM );
    die_if_ssl_error("private key");
    Net::SSLeay::CTX_use_certificate_file( $ctx, 'server.crt',
                                           &Net::SSLeay::FILETYPE_PEM );
    die_if_ssl_error("certificate");
}

open my $out, ">>", "$opt{'file'}"
  or die "open[$opt{'file'}]: $!";
my $acc;

# シグナル
$SIG{'INT'} = sub {
    close $acc if ( defined $acc );
    close $out if ( defined $out );
};

my $client_addr;
while (1) {
    print "Accepting connections...\n";
    #$addr = accept( $acc, $socket);
    ( $addr = accept( $acc, $socket ) ) or die "accept: $!";
    select($acc);
    $| = 1;
    select(STDOUT);

    # my ( $af, $client_port, $client_ip ) = unpack( $sockaddr_template, $addr );
    # my @inetaddr = unpack( 'C4', $client_ip );
    # print "$af connection from " . join( '.', @inetaddr ) . ":$client_port\n";

    my $name = gethostbyaddr( $addr, PF_INET );
    print "Connection recieved from $name\n";

    if ($opt{'ssl'}) {
        $ssl = Net::SSLeay::new($ctx) or die_now("SSL_new ($ssl): $!");
        Net::SSLeay::set_fd( $ssl, fileno($acc) );
        my $err = Net::SSLeay::accept($ssl) and die_if_ssl_error('ssl accept');
        print "Cipher `" . Net::SSLeay::get_cipher($ssl) . "'\n";
    }

    datetime("Started.", $out);

    # ヘッダ受信
    my $read_buffer;
    my ( $len, $rlen )= 0;
    while (1) {
        $len = 0;
        if ($opt{'ssl'}) {
            $read_buffer .= Net::SSLeay::read( $ssl, 16384 ) || "";
            die_if_ssl_error("ssl read");
            die "read: $!\n"
                unless defined $read_buffer
                    or $!{EAGAIN}
                    or $!{EINTR}
                    or $!{ENOBUFS};
        } else {
            #$len += read ($acc, $read_buffer, 16384) || 0;
            $read_buffer .= <$acc> || '';
        }
        $len = bytes::length($read_buffer) || 0;
        last if (!$len);

        printf "\nheader: %s bytes read.\n", ( $len || 0 );
        print $read_buffer;
        print $out $read_buffer;
        $rlen += $len;
        ( $read_buffer =~ m/\r\n\r\n/ ) and last;
    }
    #next if (!$len);
    print "\n";
    print "rlen=" . ( $rlen || 0 ) . "\n";
    ( $read_buffer =~ m/\r\n\r\n/ ) or next;

    # ヘッダ長を取得
    my @header = split m/\r\n\r\n/, $read_buffer;    # ヘッダ分割
    my $hlen = bytes::length( $header[0] ) if ( defined $header[0] );
    $hlen += bytes::length("\r\n\r\n");
    print "Header length[" . ( $hlen || 0 ) . "]\n";

    # シーケンス番号とコンテンツ長取得
    my @lines          = split m/\r\n/, $header[0];
    my $sequence_no    = 0;
    my $content_length = 0;
    foreach my $line (@lines) {
        if ( $line =~ m/^SequenceNo/i ) {
            $sequence_no = $line;
            $sequence_no =~ s/SequenceNo:\s*(.*)/$1/i;
        }
        elsif ( $line =~ m/^Content-Length/i ) {
            $content_length = $line;
            $content_length =~ s/Content-Length:\s*(.*)/$1/i;
        }
        $line =~ m/^$/ and last;
    }
    print "SequenceNo[" .     ( $sequence_no    || 0 ) . "]\n";
    print "Content-Length[" . ( $content_length || 0 ) . "]\n";

    # ボディ受信
    my $body_rlen = $rlen - $hlen;
    print "Body length[" . ( $body_rlen || 0 ) . "]\n";
    my $left = $content_length - $body_rlen;
    print "left[" . ( $left || 0 ) . "]\n" if $opt{'debug'};
    while ( $left > 0 ) {
        $len = 0;
        print "left[" . ( $left || 0 ) . "]\n" if $opt{'debug'};
        if ($opt{'ssl'}) {
            $read_buffer = Net::SSLeay::read( $ssl, $left ) || "";
            die_if_ssl_error("ssl read");
            die "read: $!\n"
              unless defined $read_buffer
                  or $!{EAGAIN}
                  or $!{EINTR}
                  or $!{ENOBUFS};
        }
        else {
            #$len = read($acc, $read_buffer, $left);
            $read_buffer = <$acc> || '';
        }
        $len = bytes::length($read_buffer) || 0;
        last if (!$len);

        printf "\nbody: %s bytes read.\n", ( $len || 0 );
        last if ( !$len || $read_buffer eq "");

        print $read_buffer;
        print $out $read_buffer;
        $left -= $len;
        $body_rlen += $len;
    }
    next if (!$len);
    print "\n";
    print $out "\n";
    print "body_rlen[" . ( $body_rlen || 0 ) . "]\n" if $opt{'debug'};
    datetime("Done.", $out);

    # 送信メッセージの組立て
    my $msg =
        $header
      . "SequenceNo: "
      . $sequence_no
      . "Content-Length: "
      . ( bytes::length($body) )
      . "\r\nDate: 2013/08/22 08:00:00\r\n"
      . "Server: test-server\r\n\r\n"
      . $body;

    # 送信
    if ($opt{'ssl'}) {
        Net::SSLeay::write( $ssl, $msg ) or die "write: $!";
        die_if_ssl_error("ssl write");
    }
    else {
        print $acc $msg;
    }
    printf "\n%s bytes write.\n", ( bytes::length($msg) );
    print $msg . "\n";

    if ($opt{'ssl'}) {
        Net::SSLeay::free($ssl);
    }
    close $acc and print "close $acc\n";
}

close $out if ( defined $out );

exit( $stathash{'EX_OK'} );

__END__

