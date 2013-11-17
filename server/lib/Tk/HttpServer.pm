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

Tk::HttpServer - HTTPサーバウィンドウ

=head1 SYNOPSIS

=cut

package Tk::HttpServer;

use strict;
use warnings;
use Encode qw/decode_utf8/;
use File::Basename qw/dirname/;
use Socket;
use Tk;

use threads;

#use Thread::Queue;

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
        'ip'        => 'localhost',
        'port'      => '80',
        'ssl'       => 0,
        'vorbis'    => 0,
        'data'      => '',
        'sockcmd'   => undef,
        'servercmd' => undef,
        'stopcmd'   => undef,
        @_
    );

    $self->{'ip'}        = $args{'ip'};
    $self->{'port'}      = $args{'port'};
    $self->{'ssl'}       = $args{'ssl'};
    $self->{'vorbis'}    = $args{'vorbis'};
    $self->{'data'}      = $args{'data'};
    $self->{'sockcmd'}   = $args{'sockcmd'};
    $self->{'servercmd'} = $args{'servercmd'};
    $self->{'stopcmd'}   = $args{'stopcmd'};
}

=head1 METHODS

=head2 create_window

ウィンドウ生成

=cut

sub create_window {
    my $self = shift;
    my %args = (
        iconfile => '',
        version  => '',
        @_
    );
    my $mw;
    $mw = MainWindow->new();
    $mw->protocol( 'WM_DELETE_WINDOW', [ \&_exit, $mw ] );
    $mw->title(
        decode_utf8("HTTPサーバ") . "  [v" . $args{'version'} . "]" );
    $mw->geometry("500x500");
    $mw->resizable( 0, 0 );

    if ( -f $args{'iconfile'} ) {
        my $image = $mw->Pixmap( -file => $args{'iconfile'} );
        $mw->Icon( -image => $image );
    }
    $self->{'mw'} = $mw;

    _server($self);

    MainLoop();
}

my $pid;
my @threads;
my $contents;

sub _server {
    my $self = shift;

    $self->{'mw'}->Label( -text => decode_utf8("アドレス: ") )
      ->grid( -row => 1, -column => 1, -pady => 7 );
    $self->{'mw'}->Label( -text => $self->{'ip'} )
      ->grid( -row => 1, -column => 2, -pady => 7 );

    $self->{'mw'}->Label( -text => decode_utf8("ポート: ") )
      ->grid( -row => 2, -column => 1, -pady => 7 );
    my $entport =
      $self->{'mw'}->Entry( -textvariable => $self->{'port'}, -width => 12 )
      ->grid( -row => 2, -column => 2, -pady => 7 );

    $self->{'mw'}->Label( -text => decode_utf8("送信データ") )
      ->grid( -row => 3, -column => 1, -pady => 7 );
    my $text = $self->{'mw'}->Scrolled(
        'Text',
        -background => 'white',
        -width      => 40,
        -height     => 10,
        -wrap       => 'none',
        -scrollbars => 'se'
    )->grid( -row => 3, -column => 2, -columnspan => 2, -pady => 7 );

    $text->insert( '1.0', $self->{'data'} );

    $self->{'mw'}->Button(
        -text    => decode_utf8("起動"),
        -command => sub {
            $contents = $text->get( '1.0', 'end' );
            $contents =~ s/\n/\r\n/g;

            my $thread = threads->new( \&_callback, $self, $entport->get );
            push( @threads, $thread );
        }
    )->grid( -row => 4, -column => 2, -padx => 15, -pady => 15 );
    $self->{'mw'}->Button(
        -text    => decode_utf8("停止"),
        -command => sub {
            $self->{'stopcmd'}->(
                'ip'     => $self->{'ip'},
                'port'   => $self->{'port'},
                'ssl'    => $self->{'ssl'},
                'vorbis' => $self->{'vorbis'}
            ) if ( defined $self->{'stopcmd'} );
        }
    )->grid( -row => 4, -column => 3, -padx => 15, -pady => 15 );

    $self->{'mw'}
      ->Button( -text => decode_utf8("終了"), -command => sub { _exit(); } )
      ->grid( -row => 5, -column => 4, -padx => 15, -pady => 15 );
}

sub _callback {
    my $self = shift;
    my $port = shift;
    if ( defined $self->{'sockcmd'} ) {
        my $res = $self->{'sockcmd'}->(
            'port'   => $port,
            'ssl'    => $self->{'ssl'},
            'vorbis' => $self->{'vorbis'}
        );
        if ( !$res && defined $self->{'servercmd'} ) {
            $self->{'servercmd'}->(
                'port'   => $port,
                'ssl'    => $self->{'ssl'},
                'vorbis' => $self->{'vorbis'},
                'data'   => $contents,
                'loop'   => 1
            );
        }
    }
}

# 後処理
sub _exit {
    my $self = shift;
    print "_exit\n";

    foreach (@threads) {
        my ($return) = $_->join;
        print "$return closed\n";
    }
    exit( $stathash{'EX_OK'} );
}

1;

__END__
