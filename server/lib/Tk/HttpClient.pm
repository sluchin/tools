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

Tk::HttpClient - HTTPクライアントウィンドウ

=head1 SYNOPSIS

=cut

package Tk::HttpClient;

use strict;
use warnings;
use Encode qw/decode_utf8/;
use File::Basename qw/dirname/;
use Socket;
use Tk;

#use threads;
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
        'dest'      => '',
        'port'      => 80,
        'ssl'       => 0,
        'count'     => 1,
        'vorbis'    => 0,
        'msg'       => '',
        'clientcmd' => undef,
        @_
    );
    $self->{'dest'}      = $args{'dest'};
    $self->{'port'}      = $args{'port'};
    $self->{'ssl'}       = $args{'ssl'};
    $self->{'count'}     = $args{'count'};
    $self->{'vorbis'}    = $args{'vorbis'};
    $self->{'msg'}       = $args{'msg'};
    $self->{'clientcmd'} = $args{'clientcmd'};
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
    $mw->title( decode_utf8("HTTPクライアント") . "  [v"
          . $args{'version'}
          . "]" );
    $mw->geometry("500x500");
    $mw->resizable( 0, 0 );

    if ( -f $args{'iconfile'} ) {
        my $image = $mw->Pixmap( -file => $args{'iconfile'} );
        $mw->Icon( -image => $image );
    }
    $self->{'mw'} = $mw;

    _client($self);

    MainLoop();
}

sub _client {
    my $self = shift;

    $self->{'mw'}->Label( -text => decode_utf8("アドレス: ") )
      ->grid( -row => 1, -column => 1, -pady => 7 );
    my $entdest =
      $self->{'mw'}->Entry( -textvariable => $self->{'dest'}, -width => 12 )
      ->grid( -row => 1, -column => 2, -pady => 7 );

    $self->{'mw'}->Label( -text => decode_utf8("ポート: ") )
      ->grid( -row => 2, -column => 1, -pady => 7 );
    my $entport =
      $self->{'mw'}->Entry( -textvariable => $self->{'port'}, -width => 12 )
      ->grid( -row => 2, -column => 2, -pady => 7 );

    $self->{'mw'}->Label( -text => decode_utf8("送信データ: ") )
      ->grid( -row => 3, -column => 1, -pady => 7 );
    my $text = $self->{'mw'}->Scrolled(
        'Text',
        -background => 'white',
        -width      => 40,
        -height     => 10,
        -wrap       => 'none',
        -scrollbars => 'se'
    )->grid( -row => 3, -column => 2, -columnspan => 2, -pady => 7 );

    $text->insert( '1.0', $self->{'msg'} );

    $self->{'mw'}->Button(
        -text    => decode_utf8("送信"),
        -command => sub {
            my $contents = $text->get( '1.0', 'end' ) || '';
            $contents =~ s/\n/\r\n/g;
            if ( defined $self->{'clientcmd'} ) {
                $self->{'clientcmd'}->(
                    'dest' => $entdest->get || '',
                    'port' => $entport->get || '',
                    'ssl'  => $self->{'ssl'},
                    'count'  => $self->{'count'},
                    'vorbis' => $self->{'vorbis'},
                    'msg'    => $contents
                );
            }
            else {
                print "no cmd \n";
            }
        }
    )->grid( -row => 4, -column => 3, -padx => 15, -pady => 15 );

    $self->{'mw'}
      ->Button( -text => decode_utf8("終了"), -command => sub { _exit(); } )
      ->grid( -row => 5, -column => 4, -padx => 15, -pady => 15 );
}

# 後処理
sub _exit {
    my $self = shift;
    print "_exit\n";
    exit( $stathash{'EX_OK'} );
}

1;

__END__
