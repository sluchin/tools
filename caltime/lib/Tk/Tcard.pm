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

Tk::Tcard - タイムカードウィンドウ

=head1 SYNOPSIS

=cut

package Tk::Tcard;

use strict;
use warnings;
use Encode qw/decode_utf8/;
use File::Basename qw/dirname/;
use Tk;
use Tk::NoteBook;
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
        'date'     => undef,
        'stime'    => 0,
        'etime'    => 0,
        'old'      => undef,
        'new'      => undef,
        'tcardcmd' => undef,
        'gettmcmd' => undef,
        'editcmd'  => undef,
        'dlcmd'    => undef,
        'savecmd'  => undef,
        @_
    );

    $self->{'id'}       = $args{'id'};
    $self->{'pw'}       = $args{'pw'};
    $self->{'dir'}      = $args{'dir'};
    $self->{'date'}     = $args{'date'};
    $self->{'stime'}    = $args{'stime'};
    $self->{'etime'}    = $args{'etime'};
    $self->{'old'}      = $args{'old'};
    $self->{'new'}      = $args{'new'};
    $self->{'tcardcmd'} = $args{'tcardcmd'};
    $self->{'gettmcmd'} = $args{'gettmcmd'};
    $self->{'editcmd'}  = $args{'editcmd'};
    $self->{'dlcmd'}    = $args{'dlcmd'};
    $self->{'savecmd'}  = $args{'savecmd'};

    my $src = $self->{'new'};
    $src->{'stime'} = $self->{'stime'} if ( defined $self->{'stime'} );
    $src->{'etime'} = $self->{'etime'} if ( defined $self->{'etime'} );
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
        decode_utf8("タイムカード") . "  [v" . $args{'version'} . "]" );
    $mw->geometry("500x400");
    $mw->resizable( 0, 0 );

    if ( -f $args{'iconfile'} ) {
        my $image = $mw->Pixmap( -file => $args{'iconfile'} );
        $mw->Icon( -image => $image );
    }
    $self->{'mw'} = $mw;

    my $book = $mw->NoteBook()->pack( -fill => 'both', -expand => 1 );

    my $tab1 = $book->add( "Sheet 1", -label => decode_utf8("出社/退社") );
    my $tab2 = $book->add( "Sheet 2", -label => decode_utf8("編集") );
    my $tab3 = $book->add( "Sheet 3", -label => decode_utf8("設定") );

    #my $tab4 = $book->add( "Sheet 4", -label => decode_utf8("ログ") );

    _tab_setime( $self, $tab1 );
    _tab_edit( $self, $tab2 );
    _tab_conf( $self, $tab3 );

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
            -message => $mes || ''
        ) if ( lc $level eq 'error' );
        $mw->messageBox(
            -type    => 'Ok',
            -icon    => 'warning',
            -title   => decode_utf8("警告"),
            -message => $mes || ''
        ) if ( lc $level eq 'warning' );
    }
}

=head2 work_state

就業状態

=cut

sub work_state {
    my $self      = shift;
    my @workstate = @_;

    eval { use Tk::Table; };
    if ( !$@ ) {
        my $top = MainWindow->new();
        $top->title( decode_utf8("就業状態") );
        $top->geometry("300x500");
        $top->resizable( 0, 0 );
        my $rows  = $#workstate + 1;
        my $table = $top->Table(
            -rows       => $rows,
            -columns    => 4,
            -scrollbars => 'e',
            -fixedrows  => 1,
            -takefocus  => 1
        )->pack( -expand => 1 );

        my $row = 0;
        for my $work (@workstate) {
            $table->put( $row, 0, $work->[0] );
            $table->put( $row, 1, $work->[1] );
            $table->put( $row, 2, $work->[2] );
            $table->put( $row, 3, $work->[3] );
            $row++;
        }
    }
    else {
        print "no Tk::Table\n";
    }
}

# 出社/退社タブ
sub _tab_setime {
    my $self = shift;
    my $tab  = shift;

    my $tcardcmd    = $self->{'tcardcmd'};
    my $dlcmd       = $self->{'dlcmd'};
    my $do_download = 1;

    $tab->Checkbutton(
        -text     => decode_utf8("ダウンロードする"),
        -variable => \$do_download,
        -onvalue  => 1
    )->grid( -row => 1, -column => 3, -padx => 15, -pady => 15 );

    $tab->Label( -textvariable => ( \$self->{'stime'} || '' ) )
      ->grid( -row => 2, -column => 2, -padx => 15, -pady => 15 );
    $tab->Button(
        -text    => decode_utf8("出社"),
        -command => sub {
            $tcardcmd->("go");
            if ($do_download) {
                $dlcmd->( $self->{'entry'}, $self->{'date'} );
            }
        },
    )->grid( -row => 2, -column => 3, -padx => 15, -pady => 15 );

    $tab->Label( -textvariable => ( \$self->{'etime'} || '' ) )
      ->grid( -row => 3, -column => 2, -padx => 15, -pady => 15 );
    my $entry;
    $tab->Button(
        -text    => decode_utf8("退社"),
        -command => sub {
            $tcardcmd->("leave");
            if ($do_download) {
                $dlcmd->( $self->{'entry'}, $self->{'date'} );
            }
        },
    )->grid( -row => 3, -column => 3, -padx => 15, -pady => 15 );

    $tab->Label( -text => decode_utf8("日付: ") )
      ->grid( -row => 4, -column => 1 );
    $entry = $tab->DateEntry(
        -textvariable => $self->{'date'},
        -width        => 10,
        -parsecmd     => \&_parse,
        -formatcmd    => \&_format
    );
    $entry->grid( -row => 4, -column => 2, -padx => 15, -pady => 15 );
    $tab->Button(
        -text    => decode_utf8("ダウンロード"),
        -command => [ $dlcmd, $self->{'entry'}, $self->{'date'} ]
    )->grid( -row => 4, -column => 3, -padx => 15, -pady => 15 );
    $tab->Button(
        -text    => decode_utf8("終了"),
        -command => sub { _exit(); }
    )->grid( -row => 5, -column => 4, -padx => 15, -pady => 15 );
}

# 編集タブ
sub _tab_edit {
    my $self = shift;
    my $tab  = shift;

    my $gettmcmd    = $self->{'gettmcmd'};
    my $editcmd     = $self->{'editcmd'};
    my $dlcmd       = $self->{'dlcmd'};
    my $old         = $self->{'old'};
    my $new         = $self->{'new'};
    my $do_download = 1;

    $tab->Checkbutton(
        -text     => decode_utf8("ダウンロードする"),
        -variable => \$do_download,
        -onvalue  => 1
    )->grid( -row => 1, -column => 2, -padx => 5, -pady => 5 );

    $tab->Label( -text => decode_utf8("日付: ") )
      ->grid( -row => 2, -column => 1, -pady => 5 );
    my $entry = $tab->DateEntry(
        -textvariable => $self->{'date'},
        -width        => 10,
        -parsecmd     => \&_parse,
        -formatcmd    => \&_format
    );
    $entry->grid( -row => 2, -column => 2, -pady => 5 );

    $tab->Button(
        -text    => decode_utf8("読込"),
        -command => [ $gettmcmd, $entry, $old, $new ]
    )->grid( -row => 2, -column => 3, -padx => 5, -pady => 5 );

    $tab->Label( -text => decode_utf8("欠勤: ") )
      ->grid( -row => 3, -column => 1, -pady => 7 );
    my $opt =
      $tab->Optionmenu( -textvariable => \$new->{'areason'}, -width => 10 )
      ->grid( -row => 3, -column => 2, -pady => 7 );
    $opt->addOptions(
        decode_utf8("未選択"), decode_utf8("欠勤"),
        decode_utf8("慶弔"),    decode_utf8("有休"),
        decode_utf8("代休"),    decode_utf8("その他"),
    );

    $tab->Label( -text => decode_utf8("出社: ") )
      ->grid( -row => 4, -column => 1, -pady => 7 );
    $tab->Entry( -textvariable => \$new->{'stime'}, -width => 12 )
      ->grid( -row => 4, -column => 2, -pady => 7 );
    $tab->Label( -text => decode_utf8("遅刻事由: ") )
      ->grid( -row => 4, -column => 3, -padx => 5, -pady => 7 );
    $tab->Entry( -textvariable => \$new->{'sreason'}, -width => 20 )
      ->grid( -row => 4, -column => 4, -padx => 5, -pady => 7 );

    $tab->Label( -text => decode_utf8("退社: ") )
      ->grid( -row => 5, -column => 1, -pady => 7 );
    $tab->Entry( -textvariable => \$new->{'etime'}, -width => 12 )
      ->grid( -row => 5, -column => 2, -pady => 7 );
    $tab->Label( -text => decode_utf8("早退事由: ") )
      ->grid( -row => 5, -column => 3, -padx => 5, -pady => 7 );
    $tab->Entry( -textvariable => \$new->{'ereason'}, -width => 20 )
      ->grid( -row => 5, -column => 4, -pady => 7 );

    $tab->Label( -text => decode_utf8("備考: ") )
      ->grid( -row => 6, -column => 1, -padx => 5, -pady => 10 );
    $tab->Entry( -textvariable => \$new->{'note'}, -width => 45 )
      ->grid( -row => 6, -column => 2, -columnspan => 3, -pady => 7 );

    $tab->Button(
        -text    => decode_utf8("編集"),
        -command => sub {
            $editcmd->( $entry, $self->{'date'}, $old, $new );
            if ($do_download) {
                $dlcmd->( $self->{'entry'}, $self->{'date'} );
            }
        }
    )->grid( -row => 7, -column => 3, -pady => 10 );

    $tab->Button(
        -text    => decode_utf8("終了"),
        -command => sub { _exit(); }
    )->grid( -row => 7, -column => 4, -padx => 15, -pady => 15 );
}

# 設定タブ
sub _tab_conf {
    my $self = shift;
    my $tab  = shift;

    my $savecmd = $self->{'savecmd'};

    $tab->Label( -text => decode_utf8("ディレクトリ: ") )
      ->grid( -row => 1, -column => 1, -pady => 7 );
    my $entdir =
      $tab->Entry( -textvariable => \$self->{'dir'}, -width => 30 )
      ->grid( -row => 1, -column => 2, -columnspan => 2, -pady => 7 );
    $tab->Button(
        -text    => decode_utf8("選択"),
        -command => [ \&_dir_dialog, $tab, $entdir ]
    )->grid( -row => 1, -column => 4, -pady => 10 );

    $tab->Label( -text => decode_utf8("ユーザ名: ") )
      ->grid( -row => 2, -column => 1, -pady => 7 );
    my $entid =
      $tab->Entry( -textvariable => \$self->{'id'}, -width => 20 )
      ->grid( -row => 2, -column => 2, -pady => 7 );

    $tab->Label( -text => decode_utf8("パスワード: ") )
      ->grid( -row => 3, -column => 1, -pady => 7 );
    my $entpw = $tab->Entry(
        -textvariable => \$self->{'pw'},
        -width        => 20,
        -show         => '*'
    )->grid( -row => 3, -column => 2, -pady => 7 );

    $tab->Button(
        -text    => decode_utf8("保存"),
        -command => [ $savecmd, $entdir, $entid, $entpw ]
    )->grid( -row => 4, -column => 3, -pady => 10 );

    $tab->Button(
        -text    => decode_utf8("終了"),
        -command => sub { _exit(); }
    )->grid( -row => 5, -column => 5, -padx => 15, -pady => 15 );
}

# 日付パース
sub _parse {
    my ( $day, $mon, $yr ) = split '-', $_[0];
    return ( $yr, $mon, $day );
}

# 日付フォーマット
sub _format {
    my ( $yr, $mon, $day ) = @_;
    return sprintf( "%04d%02d%02d", $yr, $mon, $day );
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
    exit( $stathash{'EX_OK'} );
}

1;

__END__
