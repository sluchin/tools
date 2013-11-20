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
use Tk::NoteBook;

use threads;

#use Thread::Queue;
my @threads;

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
        'dir'       => '',
        'ssl'       => 0,
        'count'     => 1,
        'icon'      => '',
        'vorbis'    => 0,
        'msg'       => '',
        'clientcmd' => undef,
        @_
    );
    $self->{'dest'}      = $args{'dest'};
    $self->{'port'}      = $args{'port'};
    $self->{'dir'}       = $args{'dir'};
    $self->{'ssl'}       = $args{'ssl'};
    $self->{'count'}     = $args{'count'};
    $self->{'icon'}      = $args{'icon'};
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

    if ( -f $self->{'icon'} ) {
        my $image = $mw->Pixmap( -file => $self->{'icon'} );
        $mw->Icon( -image => $image );
    }
    $self->{'mw'} = $mw;

    my $book = $mw->NoteBook()->pack( -fill => 'both', -expand => 1 );

    my $tab1 = $book->add( "Sheet 1", -label => decode_utf8("送信") );
    my $tab2 = $book->add( "Sheet 2", -label => decode_utf8("ログ") );

    _tab_client( $self, $tab1 );
    _tab_log( $self, $tab2 );

    MainLoop();
}

=head2 window

メッセージボックス生成

=cut

sub messagebox {
    my ( $self, $level, $mes ) = @_;
    if ( Exists( $self->{'mw'} ) ) {
        my $mw = $self->{'mw'};
        $mw->messageBox(
            -type    => 'Ok',
            -icon    => 'error',
            -title   => decode_utf8("エラー"),
            -message => decode_utf8($mes) || ''
        ) if ( lc $level eq 'error' );
        $mw->messageBox(
            -type    => 'Ok',
            -icon    => 'warning',
            -title   => decode_utf8("警告"),
            -message => decode_utf8($mes) || ''
        ) if ( lc $level eq 'warning' );
    }
}

# 送信タブ
sub _tab_client {
    my $self = shift;
    my $tab  = shift;
    my %filelist;

    # IPアドレス
    $tab->Label( -text => decode_utf8("アドレス: ") )
      ->grid( -row => 1, -column => 1, -pady => 7 );
    my $entdest =
      $tab->Entry( -textvariable => $self->{'dest'}, -width => 12 )
      ->grid( -row => 1, -column => 2, -pady => 7 );

    # ポート
    $tab->Label( -text => decode_utf8("ポート: ") )
      ->grid( -row => 2, -column => 1, -pady => 7 );
    my $entport =
      $tab->Entry( -textvariable => $self->{'port'}, -width => 12 )
      ->grid( -row => 2, -column => 2, -pady => 7 );

    # データ
    $tab->Label( -text => decode_utf8("送信データ: ") )
      ->grid( -row => 3, -column => 1, -pady => 7 );
    my $text = $tab->Scrolled(
        'Text',
        -background => 'white',
        -width      => 40,
        -height     => 10,
        -wrap       => 'none',
        -scrollbars => 'se'
    )->grid( -row => 3, -column => 2, -columnspan => 3, -pady => 7 );

    $text->insert( '1.0', $self->{'msg'} );

    # ディレクトリ
    $tab->Label( -text => decode_utf8("ディレクトリ: ") )
      ->grid( -row => 4, -column => 1, -pady => 7 );
    my $entdir =
      $tab->Entry( -textvariable => $self->{'dir'}, -width => 30 )
      ->grid( -row => 4, -column => 2, -columnspan => 2, -pady => 7 );

    $tab->Button(
        -text    => decode_utf8("選択"),
        -command => [ \&_dir_dialog, $tab, $entdir ]
    )->grid( -row => 4, -column => 4, -pady => 10 );

    # 送信回数
    $tab->Label( -text => decode_utf8("送信回数: ") )
      ->grid( -row => 5, -column => 1, -pady => 7 );
    my $entcnt =
      $tab->Entry( -textvariable => $self->{'count'}, -width => 10 )
      ->grid( -row => 5, -column => 2,  -pady => 7 );

    # 読込ボタン
    my $table;
    $tab->Button(
        -text    => decode_utf8("読込"),
        -command => sub {
            _table_files( $self, $tab, $entdir->get, \%filelist );
        }
    )->grid( -row => 5, -column => 3, -padx => 15, -pady => 15 );

    # 送信ボタン
    $tab->Button(
        -text    => decode_utf8("送信"),
        -command => sub {
            $SIG{PIPE} = sub { return; };
            $SIG{INT} = sub { return; };
            $SIG{ALRM} = sub { return; };
            $self->{'dest'} = $entdest->get;
            $self->{'port'} = $entport->get;
            $self->{'cnt'}  = $entcnt->get;
            $self->{'msg'}  =  $text->get( '1.0', 'end' );
            _send_data($self, %filelist );
        }
    )->grid( -row => 5, -column => 4, -padx => 15, -pady => 15 );

    # 終了ボタン
    $tab->Button(
        -text    => decode_utf8("終了"),
        -command => sub { _exit( $self->{'mw'} ); }
    )->grid( -row => 6, -column => 5, -padx => 15, -pady => 15 );
}

# ログタブ
sub _tab_log {
    my $self = shift;
    my $tab  = shift;

    $self->{'text'} = $tab->Scrolled(
        'Text',
        -background => 'white',
        -width      => 80,
        -height     => 50,
        -wrap       => 'none',
        -scrollbars => 'se'
    )->pack( -side => 'left', -fill => 'both', -expand => 'yes' );

    # 終了ボタン
    # $tab->Button(
    #     -text    => decode_utf8("終了"),
    #     -command => sub { _exit($self->{'mw'}); }
    # )->pack(); #grid( -row => 7, -column => 5, -padx => 15, -pady => 15 );
}

# ファイルテーブル
sub _table_files {
    my $self     = shift;
    my $top      = shift;
    my $parent   = shift || undef;
    my $filelist = shift;

    eval { use Tk::Table; };
    if ( !$@ && defined $parent) {
        my @files = Http::recursive_dir($parent);
        my $rows  = $#files + 1;
        my $sub   = $top->Toplevel();
        $sub->protocol( 'WM_DELETE_WINDOW',
            [ \&_exit_table, $sub, $filelist ] );
        $sub->title( decode_utf8("ファイル") );
        $sub->geometry("400x200");
        #$sub->resizable( 0, 0 );
        if ( -f $self->{'icon'} ) {
            my $image = $sub->Pixmap( -file => $self->{'icon'} );
            $sub->Icon( -image => $image );
        }

        my $table_frm = $sub->Frame()->pack();
        my $table = $table_frm->Table(
            -rows         => $rows,
            -columns      => 2,
            -scrollbars   => 'se',
            -fixedrows    => 1,
            -fixedcolumns => 1,
            -takefocus    => 1,
            -relief       => 'raised',
        );

        my $row = 0;
        my @checkb;
        foreach my $file (@files) {
            #print "$file\n";
            my $value;

            $checkb[$row] = $table->Checkbutton(
                -text     => "",
                -onvalue  => "1 $file",
                -offvalue => "0 $file",
                -variable => \$value,
                -command  => sub {
                    #print "value: $value\n";
                    my @file = split(m# #, $value, 2);
                    $filelist->{$file[1]} = $file[0];
                }
            );
            my $label = $table->Label(
                -text       => $file,
                -padx       => 2,
                -anchor     => 'w',
                -background => 'white',
                -relief     => 'groove'
            );
            $table->put( $row, 0, $checkb[$row] );
            $table->put( $row, 1, $label );
            $row++;
        }
        $table->pack();
        my $button_frm = $sub->Frame( -borderwidth => 4 )->pack();

        # 選択解除ボタン
        $button_frm->Button(
            -text    => decode_utf8("選択解除"),
            -command => sub {
                #print $rows."\n";
                for (my $i = 0; $i < $rows; $i++) {
                    $checkb[$i]->deselect;
                }
            }
        )->pack(-anchor => 'w', -side => 'left');

        # 全選択ボタン
        $button_frm->Button(
            -text    => decode_utf8("全選択"),
            -command => sub {
                #print $rows."\n";
                for (my $i = 0; $i < $rows; $i++) {
                    $checkb[$i]->select;
                }
            }
        )->pack(-anchor => 'w', -side => 'left');

        # 終了ボタン
        $button_frm->Button(
            -text    => decode_utf8("閉じる"),
            -command => sub { _exit_table($sub, $filelist); }
        )->pack(-anchor => 'w', -side => 'left');

    }
    else {
        print "no Tk::Table\n";
    }
}

# テーブル終了
sub _exit_table {
    my $sub      = shift;
    my $filelist = shift;
    #print "_exit_table\n";
    $filelist = ();
    $sub->destroy();
}

# データ送信
sub _send_data {
    my $self     = shift;
    my %filelist = @_;

    my $contents;
    if (%filelist) {
        foreach my $key ( keys(%filelist) ) {
            if ( $filelist{$key} && -f $key ) {
                print "file: $key\n";
                open my $in, "<", "$key"
                  or print "open error: $!";

                $contents = '';
                while ( defined( my $line = <$in> ) ) {
                    $contents .= $line;
                }
                $contents =~ s/\n/\r\n/g;
                if ( defined $self->{'clientcmd'} ) {
                    $self->{'clientcmd'}->(
                        'dest'   => $self->{'dest'},
                        'port'   => $self->{'port'},
                        'ssl'    => $self->{'ssl'},
                        'count'  => $self->{'count'},
                        'text'   => $self->{'text'},
                        'vorbis' => $self->{'vorbis'},
                        'msg'    => $contents
                    );
                }
                else {
                    print "no cmd\n";
                }
                close $in if ( defined $in );
            }
        }
    }
    else {
        $contents = $self->{'msg'};
        $contents =~ s/\n/\r\n/g;
        if ( defined $self->{'clientcmd'} ) {
            $self->{'clientcmd'}->(
                'dest'   => $self->{'dest'},
                'port'   => $self->{'port'},
                'ssl'    => $self->{'ssl'},
                'count'  => $self->{'count'},
                'text'   => $self->{'text'},
                'vorbis' => $self->{'vorbis'},
                'msg'    => $contents
            );
        }
        else {
            print "no cmd\n";
        }
    }
}

# ディレクトリ選択
sub _dir_dialog {
    my ( $tab, $ent ) = @_;
    my $dir =
      $tab->chooseDirectory( -title => decode_utf8("ディレクトリ") );
    if ( defined $dir && $dir ne '' ) {
        $ent->delete( 0, 'end' );
        $ent->insert( 0, $dir );
        $ent->xview('end');
    }
}

# 後処理
sub _exit {
    my $mw = shift;

    #print "_exit\n";
    #$mw->destroy();
    #kill(&SIGKILL, $$);
    # if (@threads) {
    #     foreach (@threads) {
    #         my ($return) = $_->join;
    #         print "$return closed\n";
    #     }
    # }
    exit( $stathash{'EX_OK'} );
}

1;

__END__
