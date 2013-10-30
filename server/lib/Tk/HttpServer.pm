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
use Tk;

#use Tk::NoteBook;
use Tk::DateEntry;

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
        'port'      => '',
        'header'    => '',
        'body'      => '',
        'sockcmd'   => undef,
        'servercmd' => undef,
        @_
    );

    $self->{'sockcmd'}   = $args{'sockcmd'};
    $self->{'servercmd'} = $args{'servercmd'};
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
    $mw->protocol( 'WM_DELETE_WINDOW', \&_exit );
    $mw->title(
        decode_utf8("HTTPサーバ") . "  [v" . $args{'version'} . "]" );
    $mw->geometry("500x500");
    $mw->resizable( 0, 0 );

    if ( -f $args{'iconfile'} ) {
        my $image = $mw->Pixmap( -file => $args{'iconfile'} );
        $mw->Icon( -image => $image );
    }
    $self->{'mw'} = $mw;

    _server( $self );

    MainLoop();
}

sub _server {
    my $self = shift;

    my $sockcmd   = $self->{'sockcmd'};
    my $servercmd = $self->{'servercmd'};

    $self->{'mw'}->Label( -text => decode_utf8("ポート: ") )
      ->grid( -row => 1, -column => 1, -pady => 7 );
    $self->{'mw'}->Entry( -textvariable => \$self->{'port'}, -width => 12 )
      ->grid( -row => 1, -column => 2, -pady => 7 );

    $self->{'mw'}->Label( -text => decode_utf8("送信ヘッダ: ") )
      ->grid( -row => 2, -column => 1, -pady => 7 );
    # $self->{'mw'}->Text(
    #     -options => \$self->{'header'},
    #     -height  => 10,
    #     -width   => 12
    # )->grid( -row => 2, -column => 2, -pady => 7 );

    $self->{'mw'}->Label( -text => decode_utf8("送信データ: ") )
      ->grid( -row => 3, -column => 1, -pady => 7 );
    # $self->{'mw'}
    #   ->Text( -options => \$self->{'body'}, -height => 10, -width => 12 )
    #   ->grid( -row => 3, -column => 2, -pady => 7 );

    $self->{'mw'}->Button(
        -text    => decode_utf8("起動"),
        -command => sub { $sockcmd->(); $servercmd->(); }
    )->grid( -row => 4, -column => 2, -padx => 15, -pady => 15 );
    $self->{'mw'}
      ->Button( -text => decode_utf8("停止"), -command => sub { _exit(); } )
      ->grid( -row => 4, -column => 3, -padx => 15, -pady => 15 );

    $self->{'mw'}
      ->Button( -text => decode_utf8("終了"), -command => sub { _exit(); } )
      ->grid( -row => 5, -column => 5, -padx => 15, -pady => 15 );
}

# 後処理
sub _exit {
    exit( $stathash{'EX_OK'} );
}

1;

__END__
