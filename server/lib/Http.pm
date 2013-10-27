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
use bytes();

use Exporter;
use base qw/Exporter/;
our @EXPORT = qw//;

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
        'soc' => undef,
        'ssl' => undef,
        'fd'  => undef,
        @_
    );

    $self->{'soc'} = $args{'soc'};
    $self->{'ssl'} = $args{'ssl'};
    $self->{'fd'}  = $args{'fd'};
}

=head1 METHODS

=head2 window

ヘッダ受信

=cut

sub read_header {
    my $self = shift;

    my ( $read_buffer, $buf );
    my ( $len, $rlen ) = 0;

    while (1) {
        ( $len, $buf ) = _read($self);
        printf "\nHeader: %d bytes read.\n", ( $len || 0 );
        $read_buffer .= $buf || '';
        last if ( !$len );
        $rlen += $len;
        ( $read_buffer =~ m/\r\n\r\n/ ) and last;
    }
    print "rlen=" . ( $rlen || 0 ) . "\n";
    ( $read_buffer =~ m/\r\n\r\n/ ) or return undef;

    # ヘッダ長を取得
    my @header = split m/\r\n\r\n/, $read_buffer;    # ヘッダ分割
    my $hlen = bytes::length( $header[0] ) if ( defined $header[0] );
    $hlen += bytes::length("\r\n\r\n");
    print "Header length[" . ( $hlen || 0 ) . "]\n";
    $rlen -= $hlen;

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

    my $left = $content_length - $rlen;
    print { $self->{'fd'} } $read_buffer;

    return (
        'left'        => $left,
        'buffer'      => $read_buffer,
        'sequence_no' => $sequence_no,
    );
}

=head2 window

ボディ受信

=cut

sub read_body {
    my $self = shift;
    my %args = (
        'left' => 0,
        @_
    );
    my $left = $args{'left'};
    my ( $len, $rlen );
    my $read_buffer;
    while ( $left > 0 ) {
        ( $len, $read_buffer ) = _read($self);
        printf "\nBody: %d bytes read.\n", ( $len || 0 );
        last if ( !$len );

        print { $self->{'fd'} } $read_buffer;
        $left -= $len;
        $rlen += $len;
    }
    return (
        'len'    => $rlen,
        'buffer' => $read_buffer,
    );
}

sub _read {
    my $self = shift;
    my ( $len, $buf );
    if ( defined $self->{'ssl'} ) {
        $buf = Net::SSLeay::read( $self->{'ssl'}, 16384 );
        $len = bytes::length( $buf || '' ) || 0;
        die_if_ssl_error("ssl read");
    }
    else {
        read( $self->{'soc'}, $buf, 16384 );
        $len = bytes::length( $buf || '' ) || 0;
    }
    die "read: $!\n"
      unless $len
          or $!{EAGAIN}
          or $!{EINTR}
          or $!{ENOBUFS};
    return ( $len, $buf );
}
1;

__END__
