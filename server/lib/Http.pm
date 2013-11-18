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

=encoding utf-8

=head1 NAME

Http - http 送信・受信

=head1 SYNOPSIS

=cut

package Http;

use strict;
use warnings;
use Socket;
use bytes ();
use Sys::Hostname qw/hostname/;
use File::Find;

# ステータス
my %stathash = (
    'EX_OK' => 0,    # 正常終了
    'EX_NG' => 1,    # 異常終了
);

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = {};
    bless( $self, $class );
    $self->init(@_);
    return $self;
}

sub init {
    my $self = shift;
    my %args = (
        'soc'    => undef,
        'port'   => undef,
        'ssl'    => 0,
        'fd'     => undef,
        'text'   => undef,
        'vorbis' => 0,
        @_
    );

    $self->{'soc'}    = $args{'soc'};
    $self->{'port'}   = $args{'port'};
    $self->{'ssl'}    = $args{'ssl'};
    $self->{'fd'}     = $args{'fd'};
    $self->{'text'}   = $args{'text'};
    $self->{'vorbis'} = $args{'vorbis'};
}

=head1 METHODS

=head1 METHODS

=head2 get_localip

IP取得

=cut

sub get_localip {
    my $self = shift;
    my $soc  = undef;

    socket( $soc, PF_INET, SOCK_DGRAM, 0 );

    $self->{'port'} = getservbyname( $self->{'port'}, 'tcp' )
      unless $self->{'port'} =~ /^\d+$/;
    my $ipaddr = gethostbyname("192.168.0.1");
    my $dest_params = sockaddr_in( $self->{'port'}, $ipaddr );
    connect( $soc, $dest_params );
    my @sock_addr = unpack_sockaddr_in( getsockname($soc) );
    my $localip   = inet_ntoa( $sock_addr[1] );

    close($soc) if ( defined $soc );
    $soc = undef;
    return $localip;
}

=head2 read_header

ヘッダ受信

=cut

sub read_header {
    my $self = shift;
    print "read_header: $!\n" if ( $self->{'vorbis'} );
    my ( $read_buffer, $buf );
    my ( $len, $rlen ) = 0;

    while (1) {
        $len = 0;
        ( $len, $buf ) = _read( $self, $self->{'soc'} );

        print "len=" . $len . "\n" if ( $self->{'vorbis'} );
        $read_buffer .= $buf || '';
        last if ( !$len );
        $rlen += $len;
        if ( $read_buffer =~ m/^EOF/ ) {
            print "read_buffer match EOF\n";
            return ();
        }
        ( $read_buffer =~ m/\r\n\r\n/ ) and last;
    }
    printf "\nHeader: %d bytes read.\n", ( $rlen || 0 );
    print "*****\n" . $read_buffer . "\n" if ( $self->{'vorbis'} );
    ( $read_buffer =~ m/\r\n\r\n/ ) or return ();

    # ヘッダ長を取得
    my @header = split m/\r\n\r\n/, $read_buffer;    # ヘッダ分割
    my $hlen = bytes::length( $header[0] ) if ( defined $header[0] );
    $hlen += bytes::length("\r\n\r\n");
    print "Header length[" . ( $hlen || 0 ) . "]\n";
    $rlen -= $hlen;

    # シーケンス番号とコンテンツ長取得
    my $sequence_no    = 0;
    my $content_length = 0;
    if ( defined $header[0] ) {
        my @lines = split m/\r\n/, $header[0];
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
    }
    print "SequenceNo[" .     ( $sequence_no    || 0 ) . "]\n";
    print "Content-Length[" . ( $content_length || 0 ) . "]\n";

    my $left = $content_length - $rlen;
    print { $self->{'fd'} } $read_buffer if ( defined $self->{'fd'} );
    $self->{'text'}->insert( 'end', datetime( $self, "Started\n" ) )
      if ( $self->{'text'} );
    $self->{'text'}->insert( 'end', $read_buffer ) if ( $self->{'text'} );

    return (
        'left'        => ( $left        || 0 ),
        'buffer'      => ( $read_buffer || '' ),
        'sequence_no' => ( $sequence_no || 0 )
    );
}

=head2 read_body

ボディ受信

=cut

sub read_body {
    my $self = shift;

    print "read_body: $!\n" if ( $self->{'vorbis'} );
    my ( $len, $rlen );
    my $buf;
    while (1) {
        $len = 0;
        ( $len, $buf ) = _read( $self, $self->{'soc'} );
        printf "\nBody: %d bytes read.\n", ( $len || 0 );
        last if ( !$len );

        print { $self->{'fd'} } $buf if ( defined $self->{'fd'} );
        $self->{'text'}->insert( 'end', $buf ) if ( $self->{'text'} );
        $self->{'text'}->insert( 'end', datetime( $self, "Doned\n" ) )
          if ( $self->{'text'} );

        $rlen += $len;
    }
    return (
        'len'    => ( $rlen || 0 ),
        'buffer' => ( $buf  || '' )
    );
}

=head2 read_body_to_len

長さまでボディ受信

=cut

sub read_body_to_len {
    my $self = shift;
    my %args = (
        'left' => 0,
        @_
    );
    print "read_body: $!\n" if ( $self->{'vorbis'} );
    my $left = $args{'left'} || 0;
    my ( $len, $rlen );
    my $read_buffer;
    while ( $left > 0 ) {
        $len = 0;
        ( $len, $read_buffer ) = _read( $self, $self->{'soc'} );
        printf "\nBody: %d bytes read.\n", ( $len || 0 );
        last if ( !$len );

        print { $self->{'fd'} } $read_buffer if ( defined $self->{'fd'} );
        $left -= $len;
        $rlen += $len;
    }
    return (
        'len'    => ( $rlen        || 0 ),
        'buffer' => ( $read_buffer || '' )
    );
}

=head2 write_msg

送信

=cut

sub write_msg {
    my $self = shift;
    my %args = (
        'sequence_no' => '',
        'msg'         => '',
        @_
    );
    print "write_msg: $!\n" if ( $self->{'vorbis'} );
    my ( $header, $body ) = split m/\r\n\r\n/, $args{'msg'};

    # 送信メッセージ
    my $msg =
        $header
      . "\r\nSequenceNo: "
      . ( $args{'sequence_no'} || '0' )
      . "\r\nContent-Length: "
      . ( ( bytes::length($body) ) || '0' )
      . "\r\nDate: "
      . ( datetime() || '' ) . "\r\n"
      . "Server: "
      . ( hostname() || '' )
      . "\r\n\r\n"
      . ( $body || '' );

    # 送信
    my $len = _write( $self, $self->{'soc'}, $msg );
    printf "\n%d bytes write.\n", $len || 0;

    return (
        'len'    => ( $len || 0 ),
        'buffer' => ( $msg || '' )
    );
}

=head2 write_eof

送信

=cut

sub write_eof {
    my $self = shift;

    print "write_eof: $!\n" if ( $self->{'vorbis'} );

    # 送信メッセージ
    my $msg = "EOF";

    # 送信
    my $len = _write( $self, $self->{'soc'}, $msg );
    printf "\n%d bytes write.\n", $len || 0;

    return (
        'len'    => ( $len || 0 ),
        'buffer' => ( $msg || '' )
    );
}

=head2 datetime

日時

=cut

sub datetime {
    my $self = shift;
    my $string = shift || '';
    my ( $sec, $min, $hour, $mday, $mon, $year ) = localtime(time);
    my $datetime = sprintf(
        "%04d-%02d-%02d %02d:%02d:%02d",
        $year + 1900,
        $mon + 1, $mday, $hour, $min, $sec
    );
    $datetime = "[" . $datetime . "] " . $string if ($string);
    return $datetime;
}

=head2 recursive_dir

ディレクトリ配下のファイルをリスト化

=cut

sub recursive_dir {
    my $dir    = shift;
    my @result = ();

    find sub {
        my $file = $_;
        my $path = $File::Find::name;
        push( @result, $path ) if ( -f $path );
    }, $dir;

    return @result;
}

# 受信
sub _read {
    my $self = shift;
    my $soc  = shift;

    print "soc: $soc\n" if ( $self->{'vorbis'} );
    my $buf = '';
    if ( $self->{'ssl'} ) {
        $buf = Net::SSLeay::read( $soc, 16384 );
        die_if_ssl_error("ssl read");
    }
    else {

        #read( $soc, $buf, 12 );
        #recv( $soc, $buf, 12, MSG_WAITALL);
        $buf = <$soc> || '';
    }
    my $len = bytes::length( $buf || '' ) || 0;
    print "len: $len\n" if ( $self->{'vorbis'} );
    die "read error: $!\n"
      if ( !$len
        && ( !$!{EAGAIN} && !$!{EINTR} && !$!{ENOBUFS} && $! ) );
    return ( $len, $buf );
}

# 送信
sub _write {
    my $self = shift;
    my $soc  = shift;
    my $msg  = shift;

    print "soc: $soc\n" if ( $self->{'vorbis'} );
    if ( $self->{'ssl'} ) {
        Net::SSLeay::write( $soc, $msg ) or die "write: $!";
        die_if_ssl_error("ssl write");
    }
    else {
        send( $soc, $msg, 0 );
    }
    my $len = bytes::length( $msg || '' ) || 0;
    die "write error: $!\n"
      if ( !$!{EAGAIN} && !$!{EINTR} && !$!{ENOBUFS} && $! );
    return $len;
}

1;

__END__
