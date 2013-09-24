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

Caltime - 勤務時間を計算する

=head1 SYNOPSIS


=cut

package Tk::Tcard;

use strict;
use warnings;
use Encode qw/decode_utf8/;
use Tk;
use Tk::DateEntry;

use Exporter;
use base qw(Exporter);
our @EXPORT = qw(tab_setime tab_edit tab_conf);

=head1 METHODS

=head2 parse

日付解析

=cut

sub parse {
    my ( $day, $mon, $yr ) = split '-', $_[0];
    return ( $yr, $mon, $day );
}

=head2 format

日付フォーマット

=cut

sub format {
    my ( $yr, $mon, $day ) = @_;
    return sprintf( "%04d%02d%02d", $yr, $mon, $day );
}

=head2 dir_dialog

ディレクトリ選択

=cut

sub dir_dialog {
    my ( $tab, $ent ) = @_;
    my $dir =
        $tab->chooseDirectory( -title => decode_utf8("ディレクトリ") );
    if ( defined $dir && $dir ne '' ) {
        $ent->delete( 0, 'end' );
        $ent->insert( 0, $dir );
        $ent->xview('end');
    }
}

=head2 tab_setime

出社/退社タブ

=cut

sub tab_setime {
    my ( $tab, $date, $cmd1, $cmd2 ) = @_;

    $tab->Button(
        -text    => decode_utf8("出社"),
        -command => [ $cmd1, "go" ]
    )->grid( -row => 1, -column => 3, -padx => 15, -pady => 15 );
    $tab->Button(
        -text    => decode_utf8("退社"),
        -command => [ $cmd1, "leave" ]
    )->grid( -row => 2, -column => 3, -padx => 15, -pady => 15 );

    $tab->Label( -text => decode_utf8("日付: ") )
      ->grid( -row => 3, -column => 1 );
    my $entry = $tab->DateEntry(
        -textvariable => $date,
        -width        => 10,
        -parsecmd     => \&parse,
        -formatcmd    => \&format
    );
    $entry->grid( -row => 3, -column => 2, -padx => 15, -pady => 15 );
    $tab->Button(
        -text    => decode_utf8("ダウンロード"),
        -command => [ $cmd2, $entry, $date ]
    )->grid( -row => 3, -column => 3, -padx => 15, -pady => 15 );
    $tab->Button( -text => decode_utf8("終了"), -command => \&exit )
      ->grid( -row => 4, -column => 4, -padx => 15, -pady => 15 );
}

=head2 tab_edit

編集タブ

=cut

sub tab_edit {
    my ( $tab, $date, $old, $new, $cmd1, $cmd2 ) = @_;

    $tab->Label( -text => decode_utf8("日付: ") )
      ->grid( -row => 1, -column => 1, -pady => 5 );
    my $entry = $tab->DateEntry(
        -textvariable => $date,
        -width        => 10,
        -parsecmd     => \&parse,
        -formatcmd    => \&format
    );
    $entry->grid( -row => 1, -column => 2, -pady => 5 );
    $tab->Button(
        -text    => decode_utf8("読込"),
        -command => [ $cmd1, $entry, $date, $old, $new ]
    )->grid( -row => 1, -column => 3, -padx => 5, -pady => 5 );

    $tab->Label( -text => decode_utf8("出社: ") )
      ->grid( -row => 2, -column => 1, -pady => 7 );
    $tab->Entry( -textvariable => \$new->{'stime'}, -width => 12 )
      ->grid( -row => 2, -column => 2, -pady => 7 );
    $tab->Label( -text => decode_utf8("遅刻事由: ") )
      ->grid( -row => 2, -column => 3, -padx => 5, -pady => 7 );
    $tab->Entry( -textvariable => \$new->{'sreason'}, -width => 20 )
      ->grid( -row => 2, -column => 4, -padx => 5, -pady => 7 );

    $tab->Label( -text => decode_utf8("退社: ") )
      ->grid( -row => 3, -column => 1, -pady => 7 );
    $tab->Entry( -textvariable => \$new->{'etime'}, -width => 12 )
      ->grid( -row => 3, -column => 2, -pady => 7 );
    $tab->Label( -text => decode_utf8("早退事由: ") )
      ->grid( -row => 3, -column => 3, -padx => 5, -pady => 7 );
    $tab->Entry( -textvariable => \$new->{'ereason'}, -width => 20 )
      ->grid( -row => 3, -column => 4, -pady => 7 );

    $tab->Label( -text => decode_utf8("備考: ") )
      ->grid( -row => 4, -column => 1, -padx => 5, -pady => 10 );
    $tab->Entry( -textvariable => \$new->{'note'}, -width => 45 )
      ->grid( -row => 4, -column => 2, -columnspan => 3, -pady => 7 );

    $tab->Button(
        -text    => decode_utf8("編集"),
        -command => [ $cmd2, $entry, $date, $old, $new ]
    )->grid( -row => 5, -column => 4, -pady => 10 );

    $tab->Button( -text => decode_utf8("終了"), -command => \&exit )
      ->grid( -row => 6, -column => 5, -padx => 15, -pady => 15 );
}

=head2 tab_conf

設定タブ

=cut

sub tab_conf {
    my ($tab, $cmd) = @_;

    $tab->Label( -text => decode_utf8("ディレクトリ: ") )
      ->grid( -row => 1, -column => 1, -pady => 7 );
    my $entdir =
      $tab->Entry( -width => 30 )
      ->grid( -row => 1, -column => 2, -columnspan => 2, -pady => 7 );
    $tab->Button(
        -text    => decode_utf8("選択"),
        -command => [ \&dir_dialog, $tab, $entdir ]
    )->grid( -row => 1, -column => 4, -pady => 10 );

    $tab->Label( -text => decode_utf8("ユーザ名: ") )
      ->grid( -row => 2, -column => 1, -pady => 7 );
    my $entid =
      $tab->Entry( -width => 20 )->grid( -row => 2, -column => 2, -pady => 7 );

    $tab->Label( -text => decode_utf8("パスワード: ") )
      ->grid( -row => 3, -column => 1, -pady => 7 );
    my $entpw =
      $tab->Entry( -width => 20, -show => '*' )
      ->grid( -row => 3, -column => 2, -pady => 7 );

    $tab->Button(
        -text    => decode_utf8("保存"),
        -command => [ $cmd, $entdir, $entid, $entpw ]
    )->grid( -row => 4, -column => 3, -pady => 10 );

    $tab->Button( -text => decode_utf8("終了"), -command => \&exit )
      ->grid( -row => 5, -column => 5, -padx => 15, -pady => 15 );
}

1;

__END__
